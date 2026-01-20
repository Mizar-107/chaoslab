#!/bin/bash
# =============================================================================
# 07-install-alerting.sh - Apply alerting rules to Prometheus
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "═══════════════════════════════════════════════════════════════"
echo "  ChaosLab: Installing Alerting Rules"
echo "═══════════════════════════════════════════════════════════════"

# Check prerequisites
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ Cannot connect to cluster"
    exit 1
fi

# Apply alerting rules
echo "📋 Applying PrometheusRule..."
kubectl apply -f "$PROJECT_ROOT/observability/alerting-rules.yaml"

# Verify
echo ""
echo "✅ Alerting rules installed!"
echo ""
echo "📊 Verify with:"
echo "   kubectl get prometheusrules -n monitoring"
echo ""
echo "🔔 View alerts in Alertmanager:"
echo "   kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-alertmanager 9093:9093"
echo "   → http://localhost:9093"
