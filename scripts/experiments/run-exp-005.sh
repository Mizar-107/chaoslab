#!/bin/bash
# ============================================================================
# EXP-005: Node Drain/Failure Experiment Runner
# ============================================================================
# ⚠️  HIGH IMPACT - Drains an entire worker node to simulate node failure.
#
# Usage: ./run-exp-005.sh [--force] [--dry-run]
#   --force   Skip confirmation prompt
#   --dry-run Show what would happen without making changes
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="microshop"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${RED}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║           EXPERIMENT EXP-005: Node Drain/Failure                  ║${NC}"
echo -e "${RED}╠═══════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${RED}║  ⚠️  HIGH IMPACT - This drains an entire worker node              ║${NC}"
echo -e "${RED}║  Risk Level: 🔴 High                                               ║${NC}"
echo -e "${RED}╚═══════════════════════════════════════════════════════════════════╝${NC}"

# Parse arguments
FORCE=false
DRY_RUN=false
for arg in "$@"; do
    case $arg in
        --force) FORCE=true ;;
        --dry-run) DRY_RUN=true ;;
    esac
done

[ "$DRY_RUN" = true ] && echo -e "${YELLOW}🔍 DRY RUN MODE - No changes will be made${NC}"

# ============================================================================
# SELECT TARGET NODE
# ============================================================================
echo ""
echo -e "${YELLOW}📋 Identifying worker nodes...${NC}"

# Get worker nodes (not control-plane)
WORKER_NODES=$(kubectl get nodes --selector='!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

if [ -z "$WORKER_NODES" ]; then
    echo -e "${RED}❌ ABORT: No worker nodes found${NC}"
    exit 1
fi

echo "   Available worker nodes:"
for node in $WORKER_NODES; do
    READY=$(kubectl get node "$node" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    echo "   - $node (Ready: $READY)"
done

# Select first worker node as target
DRAIN_NODE=$(echo $WORKER_NODES | awk '{print $1}')
echo ""
echo -e "${RED}🎯 Target node: $DRAIN_NODE${NC}"

# ============================================================================
# SHOW IMPACT
# ============================================================================
echo ""
echo -e "${YELLOW}📊 Pods on target node:${NC}"
kubectl get pods --all-namespaces --field-selector spec.nodeName=$DRAIN_NODE --no-headers 2>/dev/null | while read line; do
    echo "   $line"
done

MICROSHOP_PODS=$(kubectl get pods -n $NAMESPACE --field-selector spec.nodeName=$DRAIN_NODE --no-headers 2>/dev/null | wc -l || echo "0")
echo ""
echo "   MicroShop pods that will be evicted: $MICROSHOP_PODS"

# ============================================================================
# CONFIRMATION
# ============================================================================
if [ "$DRY_RUN" = true ]; then
    echo ""
    echo -e "${YELLOW}🔍 DRY RUN: Would drain node '$DRAIN_NODE'${NC}"
    echo "   The following would happen:"
    echo "   1. Node would be cordoned (no new pods scheduled)"
    echo "   2. All pods would be evicted to other nodes"
    echo "   3. Wait 60 seconds for pod rescheduling"
    echo "   4. Node would be uncordoned"
    exit 0
fi

if [ "$FORCE" != true ]; then
    echo ""
    echo -e "${RED}⚠️  WARNING: This will evict ALL pods from node '$DRAIN_NODE'${NC}"
    echo ""
    read -p "   Proceed with draining $DRAIN_NODE? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "   Aborted."
        exit 0
    fi
fi

# ============================================================================
# RECORD PRE-DRAIN STATE
# ============================================================================
echo ""
echo -e "${YELLOW}📊 Recording pre-drain state...${NC}"
kubectl get pods -n $NAMESPACE -o wide > /tmp/pre-drain-pods.txt 2>/dev/null || true
echo "   Saved to /tmp/pre-drain-pods.txt"

START_TIME=$(date +%s)

# ============================================================================
# DRAIN NODE
# ============================================================================
echo ""
echo -e "${RED}🚧 Step 1: Cordoning node (preventing new pods)...${NC}"
kubectl cordon $DRAIN_NODE
echo -e "${GREEN}   Node cordoned${NC}"

echo ""
echo -e "${RED}🔄 Step 2: Draining node (evicting pods)...${NC}"
echo "   This may take up to 2 minutes..."

if ! kubectl drain $DRAIN_NODE \
    --ignore-daemonsets \
    --delete-emptydir-data \
    --force \
    --timeout=120s 2>&1; then
    echo -e "${YELLOW}⚠️  Some pods could not be evicted gracefully${NC}"
fi

echo -e "${GREEN}   Node drained${NC}"

# ============================================================================
# MONITOR RECOVERY
# ============================================================================
echo ""
echo -e "${YELLOW}⏳ Step 3: Monitoring pod rescheduling (60 seconds)...${NC}"

for i in $(seq 1 60); do
    PENDING=$(kubectl get pods -n $NAMESPACE --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l || echo "0")
    RUNNING=$(kubectl get pods -n $NAMESPACE --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")
    
    PROGRESS=$((i * 100 / 60))
    BAR_WIDTH=30
    FILLED=$((PROGRESS * BAR_WIDTH / 100))
    BAR=$(printf "%${FILLED}s" | tr ' ' '█')$(printf "%$((BAR_WIDTH - FILLED))s" | tr ' ' '░')
    
    printf "\r   [%s] %3d%% | Running: %s | Pending: %s   " "$BAR" "$PROGRESS" "$RUNNING" "$PENDING"
    
    # Early exit if all pods are running
    if [ "$PENDING" -eq 0 ] && [ "$i" -gt 10 ]; then
        echo ""
        echo -e "${GREEN}   All pods rescheduled successfully!${NC}"
        break
    fi
    
    sleep 1
done
echo ""

# ============================================================================
# VERIFY RECOVERY
# ============================================================================
echo ""
echo -e "${YELLOW}🔍 Verifying recovery...${NC}"

FINAL_PENDING=$(kubectl get pods -n $NAMESPACE --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l || echo "0")
FINAL_RUNNING=$(kubectl get pods -n $NAMESPACE --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l || echo "0")

echo ""
echo "   Post-drain pod distribution:"
kubectl get pods -n $NAMESPACE -o wide --no-headers 2>/dev/null | while read line; do
    echo "   $line"
done

# ============================================================================
# UNCORDON NODE
# ============================================================================
echo ""
echo -e "${YELLOW}🔓 Step 4: Uncordoning node (returning to service)...${NC}"
kubectl uncordon $DRAIN_NODE
echo -e "${GREEN}   Node $DRAIN_NODE is back in service${NC}"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

# ============================================================================
# RESULTS
# ============================================================================
echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                        EXPERIMENT RESULTS                          ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════╝${NC}"

RESULT="PASS"
if [ "$FINAL_PENDING" -gt 0 ]; then
    echo -e "${YELLOW}⚠️ PARTIAL: $FINAL_PENDING pods still pending${NC}"
    RESULT="PARTIAL"
elif [ "$FINAL_RUNNING" -lt 1 ]; then
    echo -e "${RED}❌ FAIL: No pods running in $NAMESPACE${NC}"
    RESULT="FAIL"
else
    echo -e "${GREEN}✅ PASS: All pods rescheduled successfully${NC}"
fi

echo ""
echo "   📊 Summary:"
echo "   ├── Duration:        $ELAPSED seconds"
echo "   ├── Target Node:     $DRAIN_NODE"
echo "   ├── Evicted Pods:    $MICROSHOP_PODS"
echo "   ├── Pending:         $FINAL_PENDING"
echo "   ├── Running:         $FINAL_RUNNING"
echo "   └── Result:          $RESULT"
echo ""
echo "   📝 Recommendations:"
echo "   - If pods were stuck pending, check node resources"
echo "   - Consider adding PodDisruptionBudgets for critical services"
echo "   - Review pod anti-affinity rules to spread replicas"

[ "$RESULT" = "PASS" ] && exit 0 || exit 1
