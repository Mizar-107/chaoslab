#!/bin/bash
# =============================================================================
# ChaosLab: Collect Baseline Metrics
# =============================================================================
# Collects baseline metrics during steady-state operation.
# Run this BEFORE chaos experiments to establish normal behavior.
#
# Usage: ./scripts/06-collect-baseline.sh [OPTIONS]
#
# Options:
#   -d, --duration SECONDS   Collection duration (default: 300)
#   -p, --profile PROFILE    Load generator profile (default: steady)
#   -o, --output DIR         Output directory (default: baselines/TIMESTAMP)
#   --no-load                Skip load generator (use existing traffic)
#   -h, --help               Show this help
#
# Prerequisites:
#   - Cluster running with MicroShop deployed
#   - Prometheus port-forwarded to localhost:9090
#   - Python 3 installed (for load generator)
#
# Windows Users: Run this in Git Bash or WSL
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default configuration
DURATION=300
LOAD_PROFILE="steady"
PROM_URL="http://localhost:9090"
OUTPUT_DIR=""
SKIP_LOAD=false

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# =============================================================================
# Parse command line arguments
# =============================================================================
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--duration)
            DURATION="$2"
            shift 2
            ;;
        -p|--profile)
            LOAD_PROFILE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --no-load)
            SKIP_LOAD=true
            shift
            ;;
        -h|--help)
            head -30 "$0" | tail -20
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Set output directory if not specified
if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="${PROJECT_ROOT}/baselines/$(date +%Y%m%d_%H%M%S)"
fi

# =============================================================================
# Functions
# =============================================================================

check_prerequisites() {
    echo -e "${BLUE}▶ Checking prerequisites...${NC}"
    
    # Check kubectl connectivity
    if ! kubectl cluster-info &>/dev/null; then
        echo -e "${RED}✗ Cannot connect to Kubernetes cluster${NC}"
        echo "  Make sure your cluster is running and kubectl is configured"
        exit 1
    fi
    echo -e "  ${GREEN}✓${NC} Kubernetes cluster connected"
    
    # Check if microshop namespace exists
    if ! kubectl get namespace microshop &>/dev/null; then
        echo -e "${RED}✗ MicroShop namespace not found${NC}"
        echo "  Deploy MicroShop first: ./scripts/05-deploy-microshop.sh"
        exit 1
    fi
    echo -e "  ${GREEN}✓${NC} MicroShop namespace exists"
    
    # Check if pods are running
    READY_PODS=$(kubectl get pods -n microshop --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)
    if [[ "$READY_PODS" -lt 5 ]]; then
        echo -e "${YELLOW}⚠ Only $READY_PODS pods running in microshop namespace${NC}"
        echo "  Baseline may not be representative"
    else
        echo -e "  ${GREEN}✓${NC} $READY_PODS pods running in microshop"
    fi
    
    # Check Prometheus connectivity
    if ! curl -s --max-time 5 "${PROM_URL}/api/v1/status/runtimeinfo" &>/dev/null; then
        echo -e "${YELLOW}⚠ Cannot connect to Prometheus at ${PROM_URL}${NC}"
        echo "  Start port-forward: kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
        echo "  Continuing anyway, but metrics collection may fail..."
    else
        echo -e "  ${GREEN}✓${NC} Prometheus available at ${PROM_URL}"
    fi
    
    echo ""
}

query_prometheus() {
    local query="$1"
    local output_file="$2"
    
    local result
    result=$(curl -s --max-time 30 "${PROM_URL}/api/v1/query" \
        --data-urlencode "query=${query}" 2>/dev/null || echo '{"status":"error"}')
    
    if echo "$result" | jq -e '.status == "success"' &>/dev/null; then
        echo "$result" | jq -r '.data.result[0].value[1] // "N/A"' > "$output_file"
        return 0
    else
        echo "N/A" > "$output_file"
        return 1
    fi
}

start_load_generator() {
    if [[ "$SKIP_LOAD" == "true" ]]; then
        echo -e "${YELLOW}  Skipping load generator (--no-load specified)${NC}"
        return 0
    fi
    
    if [[ ! -f "${SCRIPT_DIR}/load-generator.py" ]]; then
        echo -e "${YELLOW}  Load generator not found, skipping${NC}"
        return 0
    fi
    
    if ! command -v python3 &>/dev/null; then
        echo -e "${YELLOW}  Python3 not found, skipping load generator${NC}"
        return 0
    fi
    
    echo -e "${BLUE}▶ Starting load generator (profile: ${LOAD_PROFILE})...${NC}"
    python3 "${SCRIPT_DIR}/load-generator.py" --profile "$LOAD_PROFILE" --url "http://localhost:8080" &
    LOAD_PID=$!
    echo -e "  ${GREEN}✓${NC} Load generator started (PID: $LOAD_PID)"
    echo ""
}

stop_load_generator() {
    if [[ -n "${LOAD_PID:-}" ]]; then
        echo -e "${BLUE}▶ Stopping load generator...${NC}"
        kill "$LOAD_PID" 2>/dev/null || true
        wait "$LOAD_PID" 2>/dev/null || true
        echo -e "  ${GREEN}✓${NC} Load generator stopped"
    fi
}

collect_metrics() {
    echo -e "${BLUE}▶ Collecting metrics from Prometheus...${NC}"
    
    # Pod availability
    echo -e "  ${CYAN}→${NC} Querying pod availability..."
    query_prometheus \
        'sum(kube_pod_status_ready{namespace="microshop",condition="true"}) / count(kube_pod_info{namespace="microshop"})' \
        "${OUTPUT_DIR}/pod_availability.txt" || true
    
    # Pod count by status
    echo -e "  ${CYAN}→${NC} Querying pod counts..."
    query_prometheus \
        'count(kube_pod_info{namespace="microshop"})' \
        "${OUTPUT_DIR}/total_pods.txt" || true
    
    query_prometheus \
        'sum(kube_pod_status_ready{namespace="microshop",condition="true"})' \
        "${OUTPUT_DIR}/ready_pods.txt" || true
    
    # Pod restarts (should be 0 during steady state)
    echo -e "  ${CYAN}→${NC} Querying pod restarts..."
    query_prometheus \
        'sum(kube_pod_container_status_restarts_total{namespace="microshop"})' \
        "${OUTPUT_DIR}/total_restarts.txt" || true
    
    # CPU usage
    echo -e "  ${CYAN}→${NC} Querying CPU usage..."
    query_prometheus \
        'sum(rate(container_cpu_usage_seconds_total{namespace="microshop"}[5m]))' \
        "${OUTPUT_DIR}/cpu_usage.txt" || true
    
    # Memory usage
    echo -e "  ${CYAN}→${NC} Querying memory usage..."
    query_prometheus \
        'sum(container_memory_working_set_bytes{namespace="microshop"})' \
        "${OUTPUT_DIR}/memory_bytes.txt" || true
    
    # Service-specific metrics
    for service in frontend catalog cart checkout postgresql redis rabbitmq; do
        echo -e "  ${CYAN}→${NC} Querying ${service} readiness..."
        query_prometheus \
            "sum(kube_pod_status_ready{namespace=\"microshop\",pod=~\"${service}.*\",condition=\"true\"})" \
            "${OUTPUT_DIR}/${service}_ready_pods.txt" || true
    done
    
    echo ""
}

collect_kubernetes_state() {
    echo -e "${BLUE}▶ Collecting Kubernetes state...${NC}"
    
    # Pod status
    echo -e "  ${CYAN}→${NC} Saving pod status..."
    kubectl get pods -n microshop -o wide > "${OUTPUT_DIR}/pods.txt" 2>/dev/null || true
    
    # Resource usage (if metrics-server available)
    echo -e "  ${CYAN}→${NC} Saving resource usage..."
    kubectl top pods -n microshop --no-headers > "${OUTPUT_DIR}/pod_resources.txt" 2>/dev/null || \
        echo "metrics-server not available" > "${OUTPUT_DIR}/pod_resources.txt"
    
    # Service endpoints
    echo -e "  ${CYAN}→${NC} Saving service endpoints..."
    kubectl get endpoints -n microshop > "${OUTPUT_DIR}/endpoints.txt" 2>/dev/null || true
    
    # Events (last hour)
    echo -e "  ${CYAN}→${NC} Saving recent events..."
    kubectl get events -n microshop --sort-by='.lastTimestamp' > "${OUTPUT_DIR}/events.txt" 2>/dev/null || true
    
    echo ""
}

generate_summary() {
    echo -e "${BLUE}▶ Generating baseline summary...${NC}"
    
    local summary_file="${OUTPUT_DIR}/summary.txt"
    
    cat > "$summary_file" <<EOF
================================================================================
                        CHAOSLAB BASELINE METRICS
================================================================================
Collected: $(date)
Duration:  ${DURATION} seconds
Profile:   ${LOAD_PROFILE}
================================================================================

POD STATUS
----------
EOF
    
    cat "${OUTPUT_DIR}/pods.txt" >> "$summary_file" 2>/dev/null || echo "N/A" >> "$summary_file"
    
    cat >> "$summary_file" <<EOF

METRICS SUMMARY
---------------
Pod Availability:  $(cat "${OUTPUT_DIR}/pod_availability.txt" 2>/dev/null || echo "N/A")
Total Pods:        $(cat "${OUTPUT_DIR}/total_pods.txt" 2>/dev/null || echo "N/A")
Ready Pods:        $(cat "${OUTPUT_DIR}/ready_pods.txt" 2>/dev/null || echo "N/A")
Total Restarts:    $(cat "${OUTPUT_DIR}/total_restarts.txt" 2>/dev/null || echo "N/A")
CPU Usage:         $(cat "${OUTPUT_DIR}/cpu_usage.txt" 2>/dev/null || echo "N/A") cores
Memory Usage:      $(awk '{printf "%.2f MB", $1/1024/1024}' "${OUTPUT_DIR}/memory_bytes.txt" 2>/dev/null || echo "N/A")

SERVICE READINESS
-----------------
Frontend:   $(cat "${OUTPUT_DIR}/frontend_ready_pods.txt" 2>/dev/null || echo "N/A") pods ready
Catalog:    $(cat "${OUTPUT_DIR}/catalog_ready_pods.txt" 2>/dev/null || echo "N/A") pods ready
Cart:       $(cat "${OUTPUT_DIR}/cart_ready_pods.txt" 2>/dev/null || echo "N/A") pods ready
Checkout:   $(cat "${OUTPUT_DIR}/checkout_ready_pods.txt" 2>/dev/null || echo "N/A") pods ready
PostgreSQL: $(cat "${OUTPUT_DIR}/postgresql_ready_pods.txt" 2>/dev/null || echo "N/A") pods ready
Redis:      $(cat "${OUTPUT_DIR}/redis_ready_pods.txt" 2>/dev/null || echo "N/A") pods ready
RabbitMQ:   $(cat "${OUTPUT_DIR}/rabbitmq_ready_pods.txt" 2>/dev/null || echo "N/A") pods ready

================================================================================
This baseline represents normal system behavior. Compare against these metrics
during and after chaos experiments to measure impact.
================================================================================
EOF
    
    echo ""
}

# =============================================================================
# Main execution
# =============================================================================

echo ""
echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║              ChaosLab: Collect Baseline Metrics                    ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${CYAN}Configuration:${NC}"
echo "  Duration:   ${DURATION}s"
echo "  Profile:    ${LOAD_PROFILE}"
echo "  Output:     ${OUTPUT_DIR}"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Check prerequisites
check_prerequisites

# Start load generation
start_load_generator

# Wait for collection period
echo -e "${BLUE}▶ Collecting baseline for ${DURATION} seconds...${NC}"
echo -e "  ${YELLOW}Press Ctrl+C to abort${NC}"
echo ""

# Progress indicator
ELAPSED=0
INTERVAL=30
while [[ $ELAPSED -lt $DURATION ]]; do
    REMAINING=$((DURATION - ELAPSED))
    echo -e "  ${CYAN}⏳${NC} ${REMAINING}s remaining..."
    
    if [[ $REMAINING -lt $INTERVAL ]]; then
        sleep "$REMAINING"
        ELAPSED=$DURATION
    else
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
    fi
done
echo ""

# Stop load generator
stop_load_generator

# Collect final metrics
collect_metrics
collect_kubernetes_state
generate_summary

# Display results
echo "═══════════════════════════════════════════════════════════════════"
echo -e "${GREEN}✓ Baseline collection complete!${NC}"
echo ""
echo "Output directory: ${OUTPUT_DIR}"
echo ""
echo "Files created:"
ls -la "$OUTPUT_DIR"
echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo -e "${CYAN}Baseline Summary:${NC}"
echo ""
cat "${OUTPUT_DIR}/summary.txt"
