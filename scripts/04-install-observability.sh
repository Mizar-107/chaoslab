#!/bin/bash
# =============================================================================
# ChaosLab: Install Observability Stack (Lightweight)
# =============================================================================
# Installs Prometheus and Grafana for monitoring chaos experiments.
#
# Usage: ./scripts/04-install-observability.sh
#
# This is a LIGHTWEIGHT installation including:
#   - Prometheus (metrics collection)
#   - Grafana (dashboards)
#   - Alertmanager (alerting)
#
# NOT included (to save resources):
#   - Loki (log aggregation)
#   - Promtail (log collection)
#
# Windows Users: Run this in Git Bash or WSL
# =============================================================================

set -euo pipefail

# Configuration
MONITORING_NAMESPACE="monitoring"
PROM_STACK_VERSION="55.5.0"  # kube-prometheus-stack version
GRAFANA_PASSWORD="chaoslab"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║        ChaosLab: Install Observability Stack (Lightweight)        ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""

# Add Helm repositories
echo -e "${BLUE}▶ Adding Helm repositories...${NC}"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update
echo -e "${GREEN}✓ Helm repositories added${NC}"
echo ""

# Create namespace
echo -e "${BLUE}▶ Creating namespace '${MONITORING_NAMESPACE}'...${NC}"
kubectl create namespace "$MONITORING_NAMESPACE" 2>/dev/null || echo "  Namespace already exists"
echo ""

# Install kube-prometheus-stack
echo -e "${BLUE}▶ Installing kube-prometheus-stack...${NC}"
echo -e "  Version: ${PROM_STACK_VERSION}"
echo -e "  Namespace: ${MONITORING_NAMESPACE}"
echo -e "  Grafana password: ${GRAFANA_PASSWORD}"
echo ""
echo -e "  ${YELLOW}This may take 3-5 minutes...${NC}"
echo ""

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace "$MONITORING_NAMESPACE" \
  --version "$PROM_STACK_VERSION" \
  --set grafana.adminPassword="$GRAFANA_PASSWORD" \
  --set grafana.enabled=true \
  --set prometheus.enabled=true \
  --set alertmanager.enabled=true \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false \
  --set grafana.sidecar.dashboards.enabled=true \
  --set grafana.sidecar.dashboards.searchNamespace=ALL \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.accessModes[0]=ReadWriteOnce \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=5Gi \
  --set alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.accessModes[0]=ReadWriteOnce \
  --set alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.resources.requests.storage=2Gi \
  --set prometheus.prometheusSpec.retention=3d \
  --set prometheus.prometheusSpec.resources.requests.cpu=100m \
  --set prometheus.prometheusSpec.resources.requests.memory=512Mi \
  --set prometheus.prometheusSpec.resources.limits.cpu=500m \
  --set prometheus.prometheusSpec.resources.limits.memory=1Gi \
  --wait \
  --timeout 10m

echo ""
echo -e "${GREEN}✓ kube-prometheus-stack installed${NC}"
echo ""

# Wait for all pods to be ready
echo -e "${BLUE}▶ Waiting for monitoring pods to be ready...${NC}"
kubectl wait --for=condition=Ready pods --all -n "$MONITORING_NAMESPACE" --timeout=600s 2>/dev/null || {
    echo -e "${YELLOW}  Some pods still starting, checking status...${NC}"
    kubectl get pods -n "$MONITORING_NAMESPACE"
}
echo ""

# Show monitoring resources
echo -e "${BLUE}▶ Monitoring Resources${NC}"
echo "─────────────────────────────────────────────────────────"
kubectl get pods -n "$MONITORING_NAMESPACE"
echo ""

# Show services
echo -e "${BLUE}▶ Monitoring Services${NC}"
echo "─────────────────────────────────────────────────────────"
kubectl get svc -n "$MONITORING_NAMESPACE"
echo ""

# Summary
echo "═══════════════════════════════════════════════════════════════════"
echo -e "${GREEN}✓ Observability Stack installed successfully!${NC}"
echo ""
echo "Components installed:"
echo "  • Prometheus      - Metrics collection and storage"
echo "  • Grafana         - Dashboards and visualization"
echo "  • Alertmanager    - Alert routing and notifications"
echo "  • Node Exporter   - Host-level metrics"
echo "  • Kube State Metrics - Kubernetes object metrics"
echo ""
echo "Access URLs (after port-forwarding):"
echo "─────────────────────────────────────────────────────────"
echo ""
echo "  Grafana (primary dashboard):"
echo "    kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
echo "    URL:      http://localhost:3000"
echo "    User:     admin"
echo "    Password: $GRAFANA_PASSWORD"
echo ""
echo "  Prometheus (metrics):"
echo "    kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
echo "    URL:      http://localhost:9090"
echo ""
echo "  Alertmanager (alerts):"
echo "    kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-alertmanager 9093:9093"
echo "    URL:      http://localhost:9093"
echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo -e "${GREEN}✓ Phase 1 setup complete!${NC}"
echo ""
echo "You can now run: ./scripts/setup-all.sh to verify everything"
echo "Or proceed to Phase 2: Deploy Target Application"
