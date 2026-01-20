#!/bin/bash
# ============================================================================
# EXP-004: DNS Failure Experiment Runner
# ============================================================================
# Injects DNS resolution failures for frontend → catalog-service.
#
# Usage: ./run-exp-004.sh [--dry-run]
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EXPERIMENT="exp-004-dns-failure"
NAMESPACE="microshop"
DURATION=45

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║             EXPERIMENT EXP-004: DNS Failure                       ║${NC}"
echo -e "${BLUE}╠═══════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║  Target:    frontend → catalog-service DNS                        ║${NC}"
echo -e "${BLUE}║  Duration:  ${DURATION} seconds                                           ║${NC}"
echo -e "${BLUE}║  Risk:      🟡 Medium                                              ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════╝${NC}"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true && echo -e "${YELLOW}🔍 DRY RUN MODE${NC}"

# ============================================================================
# PRECONDITION CHECKS
# ============================================================================
echo ""
echo -e "${YELLOW}📋 Checking preconditions...${NC}"

if ! kubectl get namespace $NAMESPACE &>/dev/null; then
    echo -e "${RED}❌ ABORT: Namespace '$NAMESPACE' does not exist${NC}"
    exit 1
fi

FRONTEND_PODS=$(kubectl get pods -l app=frontend -n $NAMESPACE --no-headers 2>/dev/null | grep -c Running || echo "0")
CATALOG_PODS=$(kubectl get pods -l app=catalog -n $NAMESPACE --no-headers 2>/dev/null | grep -c Running || echo "0")

echo "   frontend pods:      $FRONTEND_PODS running"
echo "   catalog-service:    $CATALOG_PODS running"

if [ "$FRONTEND_PODS" -lt 1 ]; then
    echo -e "${RED}❌ ABORT: No running frontend pods${NC}"
    exit 1
fi

if [ "$CATALOG_PODS" -lt 1 ]; then
    echo -e "${RED}❌ ABORT: No running catalog-service pods${NC}"
    exit 1
fi

if ! kubectl get crd dnschaos.chaos-mesh.org &>/dev/null; then
    echo -e "${RED}❌ ABORT: Chaos Mesh DNSChaos CRD not found${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All preconditions met${NC}"

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}🔍 DRY RUN: Would apply $PROJECT_ROOT/experiments/exp-004-dns-failure.yaml${NC}"
    exit 0
fi

# ============================================================================
# APPLY EXPERIMENT
# ============================================================================
echo ""
echo -e "${RED}🔥 Applying DNS failure chaos...${NC}"
echo "   Pattern: catalog-service.microshop.svc.cluster.local"
kubectl apply -f "$PROJECT_ROOT/experiments/exp-004-dns-failure.yaml"

echo ""
echo -e "${YELLOW}⏳ Monitoring for $DURATION seconds...${NC}"
echo "   Frontend should NOT crash - check UI for graceful degradation"

START_TIME=$(date +%s)
FRONTEND_RESTARTS_START=$(kubectl get pods -l app=frontend -n $NAMESPACE -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}' 2>/dev/null | tr ' ' '+' | bc 2>/dev/null || echo "0")

for i in $(seq 1 $DURATION); do
    FRONTEND_RUNNING=$(kubectl get pods -l app=frontend -n $NAMESPACE --no-headers 2>/dev/null | grep -c Running || echo "0")
    CATALOG_RUNNING=$(kubectl get pods -l app=catalog -n $NAMESPACE --no-headers 2>/dev/null | grep -c Running || echo "0")
    CART_RUNNING=$(kubectl get pods -l app=cart -n $NAMESPACE --no-headers 2>/dev/null | grep -c Running || echo "0")
    
    PROGRESS=$((i * 100 / DURATION))
    BAR_WIDTH=30
    FILLED=$((PROGRESS * BAR_WIDTH / 100))
    BAR=$(printf "%${FILLED}s" | tr ' ' '█')$(printf "%$((BAR_WIDTH - FILLED))s" | tr ' ' '░')
    
    printf "\r   [%s] %3d%% | frontend: %s | catalog: %s (unreachable) | cart: %s   " "$BAR" "$PROGRESS" "$FRONTEND_RUNNING" "$CATALOG_RUNNING" "$CART_RUNNING"
    
    sleep 1
done
echo ""

# ============================================================================
# VERIFY RECOVERY
# ============================================================================
echo ""
echo -e "${YELLOW}🔍 Verifying recovery...${NC}"
echo "   Waiting 10 seconds for DNS resolution to recover..."
sleep 10

FINAL_FRONTEND=$(kubectl get pods -l app=frontend -n $NAMESPACE --no-headers 2>/dev/null | grep -c Running || echo "0")
FINAL_CATALOG=$(kubectl get pods -l app=catalog -n $NAMESPACE --no-headers 2>/dev/null | grep -c Running || echo "0")
FRONTEND_RESTARTS_END=$(kubectl get pods -l app=frontend -n $NAMESPACE -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}' 2>/dev/null | tr ' ' '+' | bc 2>/dev/null || echo "0")
FRONTEND_RESTARTS=$((FRONTEND_RESTARTS_END - FRONTEND_RESTARTS_START))

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
if [ "$FRONTEND_RESTARTS" -gt 0 ]; then
    echo -e "${RED}❌ FAIL: Frontend crashed during DNS failure ($FRONTEND_RESTARTS restarts)${NC}"
    RESULT="FAIL"
elif [ "$FINAL_FRONTEND" -lt 1 ]; then
    echo -e "${RED}❌ FAIL: Frontend not running after experiment${NC}"
    RESULT="FAIL"
else
    echo -e "${GREEN}✅ PASS: Frontend survived DNS failure without crashing${NC}"
fi

echo ""
echo "   📊 Summary:"
echo "   ├── Duration:            $ELAPSED seconds"
echo "   ├── DNS Pattern:         catalog-service.microshop.svc.cluster.local"
echo "   ├── Frontend Restarts:   $FRONTEND_RESTARTS"
echo "   ├── Frontend Running:    $FINAL_FRONTEND"
echo "   ├── Catalog Running:     $FINAL_CATALOG"
echo "   └── Result:              $RESULT"
echo ""
echo "   📝 Notes:"
echo "   - Check browser: Did frontend show graceful degradation?"
echo "   - Cart/checkout should have remained functional"

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
echo -e "${YELLOW}🧹 Cleaning up experiment...${NC}"
kubectl delete dnschaos $EXPERIMENT -n $NAMESPACE 2>/dev/null || true
echo -e "${GREEN}✅ Experiment cleaned up${NC}"

[ "$RESULT" = "PASS" ] && exit 0 || exit 1
