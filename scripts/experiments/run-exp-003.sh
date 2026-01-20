#!/bin/bash
# ============================================================================
# EXP-002: Network Latency Experiment Runner
# ============================================================================
# Injects 200ms latency between cart-service and Redis.
#
# Usage: ./run-exp-002.sh [--dry-run]
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EXPERIMENT="exp-002-cart-network-latency"
NAMESPACE="microshop"
DURATION=60

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           EXPERIMENT EXP-002: Network Latency                     ║${NC}"
echo -e "${BLUE}╠═══════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║  Target:    cart-service → redis                                  ║${NC}"
echo -e "${BLUE}║  Latency:   200ms ± 50ms                                          ║${NC}"
echo -e "${BLUE}║  Duration:  ${DURATION} seconds                                           ║${NC}"
echo -e "${BLUE}║  Risk:      🟡 Medium                                              ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════╝${NC}"

# Dry run check
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true && echo -e "${YELLOW}🔍 DRY RUN MODE${NC}"

# ============================================================================
# PRECONDITION CHECKS
# ============================================================================
echo ""
echo -e "${YELLOW}📋 Checking preconditions...${NC}"

# Check namespace
if ! kubectl get namespace $NAMESPACE &>/dev/null; then
    echo -e "${RED}❌ ABORT: Namespace '$NAMESPACE' does not exist${NC}"
    exit 1
fi

# Check cart-service pods
CART_PODS=$(kubectl get pods -l app=cart -n $NAMESPACE --no-headers 2>/dev/null | grep -c Running || echo "0")
echo "   cart-service pods: $CART_PODS running"
if [ "$CART_PODS" -lt 1 ]; then
    echo -e "${RED}❌ ABORT: No running cart-service pods${NC}"
    exit 1
fi

# Check redis pods
REDIS_PODS=$(kubectl get pods -l app=redis -n $NAMESPACE --no-headers 2>/dev/null | grep -c Running || echo "0")
echo "   redis pods: $REDIS_PODS running"
if [ "$REDIS_PODS" -lt 1 ]; then
    echo -e "${RED}❌ ABORT: No running redis pods${NC}"
    exit 1
fi

# Check Chaos Mesh NetworkChaos CRD
if ! kubectl get crd networkchaos.chaos-mesh.org &>/dev/null; then
    echo -e "${RED}❌ ABORT: Chaos Mesh NetworkChaos CRD not found${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All preconditions met${NC}"

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}🔍 DRY RUN: Would apply $PROJECT_ROOT/experiments/exp-002-network-latency.yaml${NC}"
    exit 0
fi

# ============================================================================
# APPLY EXPERIMENT
# ============================================================================
echo ""
echo -e "${RED}🔥 Applying network latency chaos...${NC}"
kubectl apply -f "$PROJECT_ROOT/experiments/exp-002-network-latency.yaml"

echo ""
echo -e "${YELLOW}⏳ Monitoring for $DURATION seconds...${NC}"
echo "   Watch for increased cart-service response times in Grafana"

START_TIME=$(date +%s)

for i in $(seq 1 $DURATION); do
    CART_RUNNING=$(kubectl get pods -l app=cart -n $NAMESPACE --no-headers 2>/dev/null | grep -c Running || echo "0")
    REDIS_RUNNING=$(kubectl get pods -l app=redis -n $NAMESPACE --no-headers 2>/dev/null | grep -c Running || echo "0")
    
    # Check if NetworkChaos is active
    CHAOS_STATUS=$(kubectl get networkchaos $EXPERIMENT -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="AllRecovered")].status}' 2>/dev/null || echo "N/A")
    
    PROGRESS=$((i * 100 / DURATION))
    BAR_WIDTH=30
    FILLED=$((PROGRESS * BAR_WIDTH / 100))
    BAR=$(printf "%${FILLED}s" | tr ' ' '█')$(printf "%$((BAR_WIDTH - FILLED))s" | tr ' ' '░')
    
    printf "\r   [%s] %3d%% | cart: %s | redis: %s | chaos: %s   " "$BAR" "$PROGRESS" "$CART_RUNNING" "$REDIS_RUNNING" "$CHAOS_STATUS"
    
    sleep 1
done
echo ""

# ============================================================================
# VERIFY RECOVERY
# ============================================================================
echo ""
echo -e "${YELLOW}🔍 Verifying recovery...${NC}"
sleep 5

FINAL_CART=$(kubectl get pods -l app=cart -n $NAMESPACE --no-headers 2>/dev/null | grep -c Running || echo "0")
FINAL_REDIS=$(kubectl get pods -l app=redis -n $NAMESPACE --no-headers 2>/dev/null | grep -c Running || echo "0")

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
if [ "$FINAL_CART" -lt 1 ] || [ "$FINAL_REDIS" -lt 1 ]; then
    echo -e "${RED}❌ FAIL: Services did not survive latency injection${NC}"
    RESULT="FAIL"
else
    echo -e "${GREEN}✅ PASS: Services remained operational during latency injection${NC}"
fi

echo ""
echo "   📊 Summary:"
echo "   ├── Duration:        $ELAPSED seconds"
echo "   ├── Injected Latency: 200ms ± 50ms"
echo "   ├── cart-service:    $FINAL_CART running"
echo "   ├── redis:           $FINAL_REDIS running"
echo "   └── Result:          $RESULT"
echo ""
echo "   📈 Check Grafana for latency impact on cart operations"

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
echo -e "${YELLOW}🧹 Cleaning up experiment...${NC}"
kubectl delete networkchaos $EXPERIMENT -n $NAMESPACE 2>/dev/null || true
echo -e "${GREEN}✅ Experiment cleaned up${NC}"

[ "$RESULT" = "PASS" ] && exit 0 || exit 1
