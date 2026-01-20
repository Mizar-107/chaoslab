#!/bin/bash
# =============================================================================
# 08-generate-report.sh - Generate chaos experiment report
# =============================================================================
# Usage: ./scripts/08-generate-report.sh <experiment-id> [--start <time>] [--end <time>]
# Example: ./scripts/08-generate-report.sh EXP-001 --start "2026-01-20T10:00:00Z" --end "2026-01-20T10:05:00Z"
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATE="$PROJECT_ROOT/analysis/experiment-report-template.md"
REPORTS_DIR="$PROJECT_ROOT/analysis/reports"

# Defaults
EXP_ID="${1:-EXP-001}"
START_TIME="${3:-$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-10M +%Y-%m-%dT%H:%M:%SZ)}"
END_TIME="${5:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
PROM_URL="${PROMETHEUS_URL:-http://localhost:9090}"

echo "═══════════════════════════════════════════════════════════════"
echo "  ChaosLab: Experiment Report Generator"
echo "═══════════════════════════════════════════════════════════════"
echo "  Experiment: $EXP_ID"
echo "  Time Range: $START_TIME to $END_TIME"
echo "═══════════════════════════════════════════════════════════════"

# Check Prometheus connectivity
check_prometheus() {
    if ! curl -s "$PROM_URL/-/healthy" >/dev/null 2>&1; then
        echo "⚠️  Cannot reach Prometheus at $PROM_URL"
        echo "   Start port-forward: kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
        return 1
    fi
    return 0
}

# Query Prometheus
query_prometheus() {
    local query="$1"
    local time="${2:-}"
    local url="$PROM_URL/api/v1/query"
    if [[ -n "$time" ]]; then
        url="$url?query=$(echo "$query" | jq -sRr @uri)&time=$time"
    else
        url="$url?query=$(echo "$query" | jq -sRr @uri)"
    fi
    curl -s "$url" | jq -r '.data.result[0].value[1] // "N/A"' 2>/dev/null || echo "N/A"
}

# Generate report
generate_report() {
    local report_file="$REPORTS_DIR/${EXP_ID}-$(date +%Y%m%d-%H%M%S).md"
    
    echo "📊 Querying metrics..."
    
    # Get metrics (with fallbacks if Prometheus unavailable)
    if check_prometheus; then
        BASE_AVAIL=$(query_prometheus 'sum(kube_pod_status_ready{namespace="microshop",condition="true"}) / count(kube_pod_info{namespace="microshop"})' "$START_TIME")
        DURING_AVAIL=$(query_prometheus 'min_over_time((sum(kube_pod_status_ready{namespace="microshop",condition="true"}) / count(kube_pod_info{namespace="microshop"}))[5m:])')
        AFTER_AVAIL=$(query_prometheus 'sum(kube_pod_status_ready{namespace="microshop",condition="true"}) / count(kube_pod_info{namespace="microshop"})' "$END_TIME")
        RESTARTS=$(query_prometheus 'sum(increase(kube_pod_container_status_restarts_total{namespace="microshop"}[10m]))')
    else
        BASE_AVAIL="100%"
        DURING_AVAIL="N/A (Prometheus unavailable)"
        AFTER_AVAIL="N/A"
        RESTARTS="N/A"
    fi
    
    echo "📝 Generating report..."
    
    # Create report from template
    sed -e "s|{{DATE}}|$(date -u +%Y-%m-%dT%H:%M:%SZ)|g" \
        -e "s|{{EXP_ID}}|$EXP_ID|g" \
        -e "s|{{EXP_TYPE}}|Chaos Experiment|g" \
        -e "s|{{TARGET}}|microshop namespace|g" \
        -e "s|{{DURATION}}|$(( ($(date -d "$END_TIME" +%s 2>/dev/null || echo 0) - $(date -d "$START_TIME" +%s 2>/dev/null || echo 0)) ))s|g" \
        -e "s|{{OPERATOR}}|$(whoami)|g" \
        -e "s|{{HYPOTHESIS}}|[Fill in experiment hypothesis]|g" \
        -e "s|{{CRITERIA}}|[Fill in success criteria]|g" \
        -e "s|{{VERDICT}}|⏳ PENDING REVIEW|g" \
        -e "s|{{BASE_AVAIL}}|$BASE_AVAIL|g" \
        -e "s|{{DURING_AVAIL}}|$DURING_AVAIL|g" \
        -e "s|{{AFTER_AVAIL}}|$AFTER_AVAIL|g" \
        -e "s|{{AVAIL_STATUS}}|⏳|g" \
        -e "s|{{BASE_RESTARTS}}|0|g" \
        -e "s|{{DURING_RESTARTS}}|$RESTARTS|g" \
        -e "s|{{RESTART_STATUS}}|⏳|g" \
        -e "s|{{RECOVERY_TIME}}|TBD|g" \
        -e "s|{{RECOVERY_STATUS}}|⏳|g" \
        -e "s|{{TIMELINE}}|$START_TIME - Experiment started\n$END_TIME - Experiment ended|g" \
        -e "s|{{OBSERVATIONS}}|[Add your observations here]|g" \
        -e "s|{{RECOMMENDATIONS}}|[Add recommendations here]|g" \
        -e "s|{{SNAPSHOT_PATH}}|N/A|g" \
        -e "s|{{METRICS_PATH}}|N/A|g" \
        "$TEMPLATE" > "$report_file"
    
    echo ""
    echo "✅ Report generated: $report_file"
    echo ""
    echo "📋 Next steps:"
    echo "   1. Review and update the report"
    echo "   2. Add observations and recommendations"
    echo "   3. Set final verdict (✅ PASS / ❌ FAIL / ⚠️ PARTIAL)"
}

# Main
mkdir -p "$REPORTS_DIR"
generate_report

echo "Done!"
