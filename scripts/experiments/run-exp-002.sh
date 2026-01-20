#!/bin/bash
# ============================================================================
# EXP-003: CPU/Memory Stress Experiment Runner
# ============================================================================
# Stresses checkout-service with CPU or memory pressure.
#
# Usage: ./run-exp-003.sh [cpu|memory] [--dry-run]
#   cpu    - Run CPU stress experiment (default)
#   memory - Run memory stress experiment
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NAMESPACE="microshop"
DURATION=120

# Parse arguments
STRESS_TYPE="${1:-cpu}"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" || "${2:-}" == "--dry-run" ]] && DRY_RUN=true

if [[ "$STRESS_TYPE" == "memory" ]]; then
    EXPERIMENT="exp-003b-checkout-memory-stress"
    EXPERIMENT_FILE="exp-003b-memory-stress.yaml"
    STRESS_LABEL="Memory (256MB)"
else
    EXPERIMENT="exp-003-checkout-cpu-stress"
    EXPERIMENT_FILE="exp-003-cpu-stress.yaml"
    STRESS_LABEL="CPU (80% load)"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           EXPERIMENT EXP-003: Stress Testing                      ║${NC}"
echo -e "${BLUE}╠═══════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║  Target:    checkout-service                                      ║${NC}"
echo -e "${BLUE}║  Stress:    $STRESS_LABEL                                      ║${NC}"
echo -e "${BLUE}║  Duration:  ${DURATION} seconds                                          ║${NC}"
echo -e "${BLUE}║  Risk:      🟡 Medium                                              ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════╝${NC}"

[ "$DRY_RUN" = true ] && echo -e "${YELLOW}🔍 DRY RUN MODE${NC}"

# ============================================================================
# PRECONDITION CHECKS
# ============================================================================
echo ""
echo -e "${YELLOW}📋 Checking preconditions...${NC}"

if ! kubectl get namespace $NAMESPACE &>/dev/null; then
    echo -e "${RED}❌ ABORT: Namespace '$NAMESPACE' does not exist${NC}"
    exit 1
fi

CHECKOUT_PODS=$(kubectl get pods -l app=checkout -n $NAMESPACE --no-headers 2>/dev/null | grep -c Running || echo "0")
echo "   checkout-service pods: $CHECKOUT_PODS running"

if [ "$CHECKOUT_PODS" -lt 1 ]; then
    echo -e "${RED}❌ ABORT: No running checkout-service pods${NC}"
    exit 1
fi

if ! kubectl get crd stresschaos.chaos-mesh.org &>/dev/null; then
    echo -e "${RED}❌ ABORT: Chaos Mesh StressChaos CRD not found${NC}"
    exit 1
fi

# Record initial resource usage
echo ""
echo -e "${YELLOW}📊 Recording initial resource usage...${NC}"
kubectl top pods -l app=checkout -n $NAMESPACE 2>/dev/null || echo "   (metrics-server not available)"

echo -e "${GREEN}✅ All preconditions met${NC}"

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}🔍 DRY RUN: Would apply $PROJECT_ROOT/experiments/$EXPERIMENT_FILE${NC}"
    exit 0
fi

# ============================================================================
# APPLY EXPERIMENT
# ============================================================================
echo ""
echo -e "${RED}🔥 Applying $STRESS_TYPE stress chaos...${NC}"
kubectl apply -f "$PROJECT_ROOT/experiments/$EXPERIMENT_FILE"

echo ""
echo -e "${YELLOW}⏳ Monitoring for $DURATION seconds...${NC}"
echo "   Watch Grafana for CPU/Memory spikes on checkout-service"

START_TIME=$(date +%s)

for i in $(seq 1 $DURATION); do
    RUNNING=$(kubectl get pods -l app=checkout -n $NAMESPACE --no-headers 2>/dev/null | grep -c Running || echo "0")
    RESTARTS=$(kubectl get pods -l app=checkout -n $NAMESPACE -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}' 2>/dev/null | tr ' ' '+' | bc 2>/dev/null || echo "0")
    
    # Check for OOMKilled
    OOMKILLED=$(kubectl get pods -l app=checkout -n $NAMESPACE -o jsonpath='{.items[*].status.containerStatuses[*].lastState.terminated.reason}' 2>/dev/null | grep -c OOMKilled || echo "0")
    
    PROGRESS=$((i * 100 / DURATION))
    BAR_WIDTH=30
    FILLED=$((PROGRESS * BAR_WIDTH / 100))
    BAR=$(printf "%${FILLED}s" | tr ' ' '█')$(printf "%$((BAR_WIDTH - FILLED))s" | tr ' ' '░')
    
    OOM_STATUS=""
    [ "$OOMKILLED" -gt 0 ] && OOM_STATUS=" ⚠️ OOMKill!"
    
    printf "\r   [%s] %3d%% | Running: %s | Restarts: %s%s   " "$BAR" "$PROGRESS" "$RUNNING" "$RESTARTS" "$OOM_STATUS"
    
    # Abort on multiple restarts (potential crash loop)
    if [ "$RESTARTS" -gt 3 ]; then
        echo ""
        echo -e "${RED}⚠️ ABORTING: Multiple restarts detected (potential CrashLoopBackOff)${NC}"
        kubectl delete stresschaos $EXPERIMENT -n $NAMESPACE 2>/dev/null || true
        exit 1
    fi
    
    sleep 1
done
echo ""

# ============================================================================
# VERIFY RECOVERY
# ============================================================================
echo ""
echo -e "${YELLOW}🔍 Verifying recovery...${NC}"
sleep 10

FINAL_RUNNING=$(kubectl get pods -l app=checkout -n $NAMESPACE --no-headers 2>/dev/null | grep -c Running || echo "0")
FINAL_RESTARTS=$(kubectl get pods -l app=checkout -n $NAMESPACE -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}' 2>/dev/null | tr ' ' '+' | bc 2>/dev/null || echo "0")

# Check resource usage after stress
echo ""
echo -e "${YELLOW}📊 Post-experiment resource usage:${NC}"
kubectl top pods -l app=checkout -n $NAMESPACE 2>/dev/null || echo "   (metrics-server not available)"

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
if [ "$FINAL_RUNNING" -lt 1 ]; then
    echo -e "${RED}❌ FAIL: checkout-service did not survive stress test${NC}"
    RESULT="FAIL"
elif [ "$FINAL_RESTARTS" -gt 0 ]; then
    echo -e "${YELLOW}⚠️ PARTIAL: Service survived but had $FINAL_RESTARTS restart(s)${NC}"
    RESULT="PARTIAL"
else
    echo -e "${GREEN}✅ PASS: checkout-service survived $STRESS_TYPE stress without restarts${NC}"
fi

echo ""
echo "   📊 Summary:"
echo "   ├── Duration:        $ELAPSED seconds"
echo "   ├── Stress Type:     $STRESS_TYPE"
echo "   ├── Final Running:   $FINAL_RUNNING pods"
echo "   ├── Total Restarts:  $FINAL_RESTARTS"
echo "   └── Result:          $RESULT"

# ============================================================================
# CLEANUP
# ============================================================================
echo ""
echo -e "${YELLOW}🧹 Cleaning up experiment...${NC}"
kubectl delete stresschaos $EXPERIMENT -n $NAMESPACE 2>/dev/null || true
echo -e "${GREEN}✅ Experiment cleaned up${NC}"

[ "$RESULT" = "PASS" ] && exit 0 || exit 1
