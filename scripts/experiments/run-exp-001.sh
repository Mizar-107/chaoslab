#!/bin/bash
# ============================================================================
# EXP-001: Pod Kill Experiment Runner
# ============================================================================
# Targets catalog-service pod to test ReplicaSet self-healing capability.
#
# Usage: ./run-exp-001.sh [--dry-run]
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EXPERIMENT="exp-001-catalog-pod-kill"
NAMESPACE="microshop"
TARGET_APP="catalog"
DURATION=30

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              EXPERIMENT EXP-001: Pod Kill                         ║${NC}"
echo -e "${BLUE}╠═══════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║  Target:    ${TARGET_APP}-service                                        ║${NC}"
echo -e "${BLUE}║  Duration:  ${DURATION} seconds                                           ║${NC}"
echo -e "${BLUE}║  Risk:      🟢 Low                                                 ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════╝${NC}"

# Dry run check
if [[ "${1:-}" == "--dry-run" ]]; then
    echo -e "${YELLOW}🔍 DRY RUN MODE - No changes will be made${NC}"
    DRY_RUN=true
else
    DRY_RUN=false
fi

# ============================================================================
# PRECONDITION CHECKS
# ============================================================================
echo ""
echo -e "${YELLOW}📋 Checking preconditions...${NC}"

# Check if namespace exists
if ! kubectl get namespace $NAMESPACE &>/dev/null; then
    echo -e "${RED}❌ ABORT: Namespace '$NAMESPACE' does not exist${NC}"
    echo "   Run: ./scripts/05-deploy-microshop.sh first"
    exit 1
fi

# Check if target pods exist and are ready
READY_PODS=$(kubectl get pods -l app=$TARGET_APP -n $NAMESPACE -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -o True | wc -l || echo "0")
TOTAL_PODS=$(kubectl get pods -l app=$TARGET_APP -n $NAMESPACE --no-headers 2>/dev/null | wc -l || echo "0")

echo "   ${TARGET_APP}-service pods: $READY_PODS/$TOTAL_PODS ready"

if [ "$READY_PODS" -lt 2 ]; then
    echo -e "${RED}❌ ABORT: ${TARGET_APP}-service does not have at least 2 ready pods${NC}"
    echo "   Current: $READY_PODS ready pods"
    echo "   Required: At least 2 for safe pod-kill experiment"
    exit 1
fi
echo -e "${GREEN}✅ Preconditions met: $READY_PODS ${TARGET_APP} pods ready${NC}"

# Check if Chaos Mesh is installed
if ! kubectl get crd podchaos.chaos-mesh.org &>/dev/null; then
    echo -e "${RED}❌ ABORT: Chaos Mesh is not installed${NC}"
    echo "   Run: ./scripts/03-install-chaos-mesh.sh first"
    exit 1
fi
echo -e "${GREEN}✅ Chaos Mesh is installed${NC}"

# ============================================================================
# RECORD BASELINE
# ============================================================================
echo ""
echo -e "${YELLOW}📊 Recording pre-experiment state...${NC}"
START_TIME=$(date +%s)

# Get current pod names
echo "   Current pods:"
kubectl get pods -l app=$TARGET_APP -n $NAMESPACE -o wide --no-headers | while read line; do
    echo "   - $line"
done

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo -e "${YELLOW}🔍 DRY RUN: Would apply experiment from:${NC}"
    echo "   $PROJECT_ROOT/experiments/exp-001-pod-kill.yaml"
    echo ""
    echo -e "${GREEN}✅ Dry run complete - no changes made${NC}"
    exit 0
fi

# ============================================================================
# APPLY CHAOS EXPERIMENT
# ============================================================================
echo ""
echo -e "${RED}🔥 Applying chaos experiment...${NC}"
kubectl apply -f "$PROJECT_ROOT/experiments/exp-001-pod-kill.yaml"

echo ""
echo -e "${YELLOW}⏳ Monitoring for $DURATION seconds...${NC}"

# Monitor pod status during experiment
for i in $(seq 1 $DURATION); do
    RUNNING=$(kubectl get pods -l app=$TARGET_APP -n $NAMESPACE --no-headers 2>/dev/null | grep -c Running || echo "0")
    TOTAL=$(kubectl get pods -l app=$TARGET_APP -n $NAMESPACE --no-headers 2>/dev/null | wc -l || echo "0")
    RESTARTS=$(kubectl get pods -l app=$TARGET_APP -n $NAMESPACE -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}' 2>/dev/null | tr ' ' '+' | bc 2>/dev/null || echo "0")
    
    # Progress bar
    PROGRESS=$((i * 100 / DURATION))
    BAR_WIDTH=30
    FILLED=$((PROGRESS * BAR_WIDTH / 100))
    EMPTY=$((BAR_WIDTH - FILLED))
    BAR=$(printf "%${FILLED}s" | tr ' ' '█')$(printf "%${EMPTY}s" | tr ' ' '░')
    
    printf "\r   [%s] %3d%% | Pods: %s/%s running | Restarts: %s   " "$BAR" "$PROGRESS" "$RUNNING" "$TOTAL" "$RESTARTS"
    
    sleep 1
done
echo ""

# ============================================================================
# VERIFY RECOVERY
# ============================================================================
echo ""
echo -e "${YELLOW}🔍 Verifying recovery...${NC}"

# Wait for pods to stabilize
echo "   Waiting 10 seconds for pod stabilization..."
sleep 10

FINAL_READY=$(kubectl get pods -l app=$TARGET_APP -n $NAMESPACE -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -o True | wc -l || echo "0")
FINAL_RESTARTS=$(kubectl get pods -l app=$TARGET_APP -n $NAMESPACE -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}' 2>/dev/null | tr ' ' '+' | bc 2>/dev/null || echo "0")

echo ""
echo "   Final pod state:"
kubectl get pods -l app=$TARGET_APP -n $NAMESPACE -o wide --no-headers | while read line; do
    echo "   - $line"
done

# Calculate recovery time
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

# ============================================================================
# RESULTS
# ============================================================================
echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                        EXPERIMENT RESULTS                          ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════╝${NC}"

if [ "$FINAL_READY" -ge 2 ]; then
    echo -e "${GREEN}✅ PASS: System recovered - $FINAL_READY pods ready${NC}"
    RESULT="PASS"
else
    echo -e "${RED}❌ FAIL: System did not recover - only $FINAL_READY pods ready${NC}"
    RESULT="FAIL"
fi

echo ""
echo "   📊 Summary:"
echo "   ├── Duration:        $ELAPSED seconds"
echo "   ├── Initial Pods:    $READY_PODS ready"
echo "   ├── Final Pods:      $FINAL_READY ready"
echo "   ├── Pod Restarts:    $FINAL_RESTARTS"
echo "   └── Result:          $RESULT"

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
echo -e "${YELLOW}🧹 Cleaning up experiment...${NC}"
kubectl delete podchaos $EXPERIMENT -n $NAMESPACE 2>/dev/null || true
echo -e "${GREEN}✅ Experiment cleaned up${NC}"

# Return appropriate exit code
if [ "$RESULT" = "PASS" ]; then
    exit 0
else
    exit 1
fi
