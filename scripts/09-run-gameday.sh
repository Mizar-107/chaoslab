#!/bin/bash
# ============================================================================
# GameDay Simulation Runner
# ============================================================================
# Orchestrates a complete GameDay chaos engineering session with automated
# experiment execution, monitoring, and reporting.
#
# Usage:
#   ./09-run-gameday.sh                    # Run full GameDay (30 min)
#   ./09-run-gameday.sh --dry-run          # Preview without execution
#   ./09-run-gameday.sh --phase warmup     # Run single phase
#   ./09-run-gameday.sh --duration 15      # Custom duration (minutes)
#
# Phases:
#   warmup    - Baseline collection (2 min)
#   chaos     - Experiment execution (variable)
#   recovery  - System stabilization (5 min)
#   report    - Generate analysis report
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
NAMESPACE="microshop"
CHAOS_NAMESPACE="chaos-mesh"
MONITORING_NAMESPACE="monitoring"
GAMEDAY_DURATION=30  # minutes
WARMUP_DURATION=120  # seconds
RECOVERY_DURATION=300 # seconds

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# State
DRY_RUN=false
SINGLE_PHASE=""
GAMEDAY_START=""
ABORT_REQUESTED=false

# ============================================================================
# ARGUMENT PARSING
# ============================================================================
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --phase)
            SINGLE_PHASE="$2"
            shift 2
            ;;
        --duration)
            GAMEDAY_DURATION="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run           Preview without executing experiments"
            echo "  --phase <name>      Run single phase (warmup|chaos|recovery|report)"
            echo "  --duration <min>    Total GameDay duration in minutes (default: 30)"
            echo "  -h, --help          Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

print_banner() {
    echo ""
    echo -e "${MAGENTA}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║                                                                           ║${NC}"
    echo -e "${MAGENTA}║   ██████╗  █████╗ ███╗   ███╗███████╗██████╗  █████╗ ██╗   ██╗           ║${NC}"
    echo -e "${MAGENTA}║  ██╔════╝ ██╔══██╗████╗ ████║██╔════╝██╔══██╗██╔══██╗╚██╗ ██╔╝           ║${NC}"
    echo -e "${MAGENTA}║  ██║  ███╗███████║██╔████╔██║█████╗  ██║  ██║███████║ ╚████╔╝            ║${NC}"
    echo -e "${MAGENTA}║  ██║   ██║██╔══██║██║╚██╔╝██║██╔══╝  ██║  ██║██╔══██║  ╚██╔╝             ║${NC}"
    echo -e "${MAGENTA}║  ╚██████╔╝██║  ██║██║ ╚═╝ ██║███████╗██████╔╝██║  ██║   ██║              ║${NC}"
    echo -e "${MAGENTA}║   ╚═════╝ ╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚═════╝ ╚═╝  ╚═╝   ╚═╝              ║${NC}"
    echo -e "${MAGENTA}║                                                                           ║${NC}"
    echo -e "${MAGENTA}║                    ChaosLab GameDay Simulation                            ║${NC}"
    echo -e "${MAGENTA}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_phase() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  📍 PHASE: $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

elapsed_time() {
    local start=$1
    local now=$(date +%s)
    local elapsed=$((now - start))
    local mins=$((elapsed / 60))
    local secs=$((elapsed % 60))
    printf "%02d:%02d" $mins $secs
}

countdown() {
    local duration=$1
    local message=$2
    for i in $(seq $duration -1 1); do
        printf "\r   ${message}: %3d seconds remaining..." "$i"
        sleep 1
        if [ "$ABORT_REQUESTED" = true ]; then
            echo ""
            return 1
        fi
    done
    echo ""
}

cleanup_chaos() {
    log_warning "Cleaning up all chaos experiments..."
    kubectl delete podchaos,networkchaos,stresschaos,dnschaos,workflow --all -n $NAMESPACE 2>/dev/null || true
    log_success "Chaos experiments cleaned up"
}

# Abort handler
abort_handler() {
    echo ""
    log_error "ABORT SIGNAL RECEIVED!"
    ABORT_REQUESTED=true
    cleanup_chaos
    echo ""
    log_info "GameDay aborted. Check runbooks/gameday-runbook.md for recovery steps."
    exit 130
}

trap abort_handler SIGINT SIGTERM

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================

preflight_checks() {
    log_phase "PRE-FLIGHT CHECKS"
    
    local checks_passed=true
    
    # Check kubectl context
    log_info "Checking kubectl context..."
    if kubectl config current-context | grep -q "chaoslab"; then
        log_success "kubectl context: $(kubectl config current-context)"
    else
        log_warning "kubectl context may not be chaoslab: $(kubectl config current-context)"
    fi
    
    # Check nodes
    log_info "Checking cluster nodes..."
    local ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready" || echo "0")
    if [ "$ready_nodes" -ge 4 ]; then
        log_success "Cluster nodes: $ready_nodes ready"
    else
        log_error "Cluster nodes: only $ready_nodes ready (need 4)"
        checks_passed=false
    fi
    
    # Check MicroShop namespace
    log_info "Checking MicroShop deployment..."
    if kubectl get namespace $NAMESPACE &>/dev/null; then
        local ready_pods=$(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        local total_pods=$(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | wc -l || echo "0")
        if [ "$ready_pods" -ge 5 ]; then
            log_success "MicroShop pods: $ready_pods/$total_pods running"
        else
            log_error "MicroShop pods: only $ready_pods running (need at least 5)"
            checks_passed=false
        fi
    else
        log_error "MicroShop namespace not found"
        checks_passed=false
    fi
    
    # Check Chaos Mesh
    log_info "Checking Chaos Mesh..."
    if kubectl get namespace $CHAOS_NAMESPACE &>/dev/null; then
        local chaos_pods=$(kubectl get pods -n $CHAOS_NAMESPACE --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        if [ "$chaos_pods" -ge 3 ]; then
            log_success "Chaos Mesh pods: $chaos_pods running"
        else
            log_error "Chaos Mesh pods: only $chaos_pods running"
            checks_passed=false
        fi
    else
        log_error "Chaos Mesh namespace not found"
        checks_passed=false
    fi
    
    # Check Prometheus
    log_info "Checking Prometheus..."
    if kubectl get pods -n $MONITORING_NAMESPACE -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | grep -q "Running"; then
        log_success "Prometheus is running"
    else
        log_warning "Prometheus may not be running (metrics collection affected)"
    fi
    
    # Check for existing chaos experiments
    log_info "Checking for existing chaos experiments..."
    local existing=$(kubectl get podchaos,networkchaos,stresschaos,dnschaos -n $NAMESPACE --no-headers 2>/dev/null | wc -l || echo "0")
    if [ "$existing" -gt 0 ]; then
        log_warning "Found $existing existing chaos experiments - will clean up"
        if [ "$DRY_RUN" = false ]; then
            cleanup_chaos
        fi
    else
        log_success "No existing chaos experiments"
    fi
    
    if [ "$checks_passed" = false ]; then
        log_error "Pre-flight checks failed. Please fix issues before running GameDay."
        exit 1
    fi
    
    log_success "All pre-flight checks passed!"
}

# ============================================================================
# PHASE: WARMUP
# ============================================================================

phase_warmup() {
    log_phase "WARMUP (Baseline Collection)"
    
    log_info "Collecting baseline metrics for $((WARMUP_DURATION / 60)) minutes..."
    log_info "This establishes steady-state before chaos injection"
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN: Would collect baseline for $WARMUP_DURATION seconds"
        return 0
    fi
    
    # Display current state
    echo ""
    echo "   📊 Current Pod Status:"
    kubectl get pods -n $NAMESPACE --no-headers | while read line; do
        echo "      $line"
    done
    
    echo ""
    countdown $WARMUP_DURATION "Warmup phase"
    
    log_success "Baseline collection complete"
}

# ============================================================================
# PHASE: CHAOS EXPERIMENTS
# ============================================================================

run_experiment() {
    local name=$1
    local file=$2
    local duration=$3
    
    echo ""
    log_info "Running experiment: $name"
    log_info "Duration: $duration seconds"
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN: Would apply $file"
        return 0
    fi
    
    # Apply experiment
    kubectl apply -f "$PROJECT_ROOT/experiments/$file"
    
    # Monitor
    countdown $duration "Experiment active"
    
    # Cleanup
    kubectl delete -f "$PROJECT_ROOT/experiments/$file" 2>/dev/null || true
    log_success "Experiment $name complete"
}

phase_chaos() {
    log_phase "CHAOS EXPERIMENTS"
    
    log_info "Executing chaos experiment sequence..."
    log_warning "Press Ctrl+C at any time to abort and cleanup"
    
    echo ""
    echo "   📋 Experiment Queue:"
    echo "      1. EXP-001: Pod Kill (catalog-service) - 30s"
    echo "      2. EXP-002: Network Latency (cart→redis) - 60s"
    echo "      3. EXP-003: CPU Stress (checkout) - 60s"
    echo "      4. EXP-004: DNS Failure (frontend→catalog) - 45s"
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN: Would execute 4 experiments"
        return 0
    fi
    
    # Experiment 1: Pod Kill
    run_experiment "EXP-001: Pod Kill" "exp-001-pod-kill.yaml" 30
    sleep 10  # Brief pause between experiments
    
    # Experiment 2: Network Latency
    run_experiment "EXP-002: Network Latency" "exp-002-network-latency.yaml" 60
    sleep 10
    
    # Experiment 3: CPU Stress
    run_experiment "EXP-003: CPU Stress" "exp-003-cpu-stress.yaml" 60
    sleep 10
    
    # Experiment 4: DNS Failure
    run_experiment "EXP-004: DNS Failure" "exp-004-dns-failure.yaml" 45
    
    log_success "All chaos experiments completed"
}

# ============================================================================
# PHASE: RECOVERY
# ============================================================================

phase_recovery() {
    log_phase "RECOVERY (System Stabilization)"
    
    log_info "Monitoring system recovery for $((RECOVERY_DURATION / 60)) minutes..."
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN: Would monitor recovery for $RECOVERY_DURATION seconds"
        return 0
    fi
    
    # Ensure no chaos experiments remain
    cleanup_chaos
    
    # Monitor recovery
    local recovery_start=$(date +%s)
    while true; do
        local elapsed=$(($(date +%s) - recovery_start))
        if [ $elapsed -ge $RECOVERY_DURATION ]; then
            break
        fi
        
        local running=$(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        local total=$(kubectl get pods -n $NAMESPACE --no-headers 2>/dev/null | wc -l || echo "0")
        local remaining=$((RECOVERY_DURATION - elapsed))
        
        printf "\r   Pods: %s/%s Running | Recovery: %3d seconds remaining...   " "$running" "$total" "$remaining"
        sleep 5
        
        if [ "$ABORT_REQUESTED" = true ]; then
            echo ""
            return 1
        fi
    done
    echo ""
    
    # Final status
    echo ""
    echo "   📊 Final Pod Status:"
    kubectl get pods -n $NAMESPACE --no-headers | while read line; do
        echo "      $line"
    done
    
    log_success "Recovery phase complete"
}

# ============================================================================
# PHASE: REPORT
# ============================================================================

phase_report() {
    log_phase "REPORT GENERATION"
    
    log_info "Generating GameDay summary report..."
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN: Would generate report"
        return 0
    fi
    
    # Run report generator if available
    if [ -f "$PROJECT_ROOT/scripts/08-generate-report.sh" ]; then
        bash "$PROJECT_ROOT/scripts/08-generate-report.sh" --gameday 2>/dev/null || {
            log_warning "Report generation had issues, manual review recommended"
        }
    else
        log_warning "Report generator not found, skipping"
    fi
    
    # Print summary
    local end_time=$(date +%s)
    local total_duration=$((end_time - GAMEDAY_START))
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                        GAMEDAY SUMMARY                                    ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "   📅 Date:          $(date '+%Y-%m-%d')"
    echo "   ⏱️  Duration:      $((total_duration / 60)) minutes $((total_duration % 60)) seconds"
    echo "   🔬 Experiments:   4 executed"
    echo ""
    echo "   📋 Experiments Run:"
    echo "      ├── EXP-001: Pod Kill (catalog-service)"
    echo "      ├── EXP-002: Network Latency (cart→redis)"
    echo "      ├── EXP-003: CPU Stress (checkout)"
    echo "      └── EXP-004: DNS Failure (frontend→catalog)"
    echo ""
    echo "   📊 Final System State:"
    kubectl get pods -n $NAMESPACE --no-headers | while read line; do
        echo "      $line"
    done
    echo ""
    echo "   📁 Reports saved to: $PROJECT_ROOT/analysis/"
    echo ""
    
    log_success "GameDay complete! Review runbooks/gameday-runbook.md for debrief template."
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    print_banner
    
    GAMEDAY_START=$(date +%s)
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}🔍 DRY RUN MODE - No changes will be made${NC}"
        echo ""
    fi
    
    log_info "GameDay Configuration:"
    echo "   • Duration:    $GAMEDAY_DURATION minutes"
    echo "   • Namespace:   $NAMESPACE"
    echo "   • Start Time:  $(date '+%Y-%m-%d %H:%M:%S')"
    if [ -n "$SINGLE_PHASE" ]; then
        echo "   • Single Phase: $SINGLE_PHASE"
    fi
    echo ""
    
    # Run phases
    if [ -n "$SINGLE_PHASE" ]; then
        case $SINGLE_PHASE in
            warmup)
                preflight_checks
                phase_warmup
                ;;
            chaos)
                preflight_checks
                phase_chaos
                ;;
            recovery)
                phase_recovery
                ;;
            report)
                phase_report
                ;;
            *)
                log_error "Unknown phase: $SINGLE_PHASE"
                log_info "Valid phases: warmup, chaos, recovery, report"
                exit 1
                ;;
        esac
    else
        # Full GameDay sequence
        preflight_checks
        phase_warmup
        phase_chaos
        phase_recovery
        phase_report
    fi
    
    echo ""
    log_success "GameDay simulation finished!"
}

main
