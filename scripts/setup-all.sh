#!/bin/bash
# =============================================================================
# ChaosLab: Complete Setup Script
# =============================================================================
# Runs all setup scripts in sequence to create the full ChaosLab environment.
#
# Usage: ./scripts/setup-all.sh
#
# This will:
#   1. Create Kind cluster (1 control-plane + 3 workers)
#   2. Install NGINX Ingress Controller
#   3. Install Chaos Mesh
#   4. Install Prometheus + Grafana (Lightweight Observability)
#
# Total time: ~10-15 minutes
#
# Windows Users: Run this in Git Bash or WSL with Docker Desktop running
# =============================================================================

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Timer
START_TIME=$(date +%s)

echo ""
echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║                                                                   ║"
echo "║              🔬 ChaosLab: Complete Setup                          ║"
echo "║                                                                   ║"
echo "║    Chaos Engineering Learning Platform                            ║"
echo "║                                                                   ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""
echo "This script will set up the complete ChaosLab environment:"
echo ""
echo "  Step 1: Create Kind Cluster (4 nodes)"
echo "  Step 2: Install NGINX Ingress Controller"
echo "  Step 3: Install Chaos Mesh"
echo "  Step 4: Install Prometheus + Grafana"
echo ""
echo "Estimated time: 10-15 minutes"
echo ""
echo "─────────────────────────────────────────────────────────────────────"

# Confirm
read -p "Start setup? (Y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "Setup cancelled."
    exit 0
fi

echo ""

# =============================================================================
# Step 1: Create Cluster
# =============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  STEP 1/4: Creating Kind Cluster"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash "$SCRIPT_DIR/01-create-cluster.sh"

# =============================================================================
# Step 2: Install Ingress
# =============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  STEP 2/4: Installing NGINX Ingress Controller"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash "$SCRIPT_DIR/02-install-ingress.sh"

# =============================================================================
# Step 3: Install Chaos Mesh
# =============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  STEP 3/4: Installing Chaos Mesh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash "$SCRIPT_DIR/03-install-chaos-mesh.sh"

# =============================================================================
# Step 4: Install Observability
# =============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  STEP 4/4: Installing Observability Stack"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash "$SCRIPT_DIR/04-install-observability.sh"

# =============================================================================
# Summary
# =============================================================================
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

echo ""
echo ""
echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║                                                                   ║"
echo "║              🎉 CHAOSLAB SETUP COMPLETE! 🎉                        ║"
echo "║                                                                   ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""
echo "  Setup completed in ${MINUTES}m ${SECONDS}s"
echo ""
echo "─────────────────────────────────────────────────────────────────────"
echo "  CLUSTER OVERVIEW"
echo "─────────────────────────────────────────────────────────────────────"
echo ""
echo "  Cluster:       kind-chaoslab"
echo "  Nodes:         1 control-plane + 3 workers"
echo ""
echo "  Namespaces:"
echo "    • ingress-nginx  - Ingress controller"
echo "    • chaos-mesh     - Chaos engineering tools"
echo "    • monitoring     - Prometheus & Grafana"
echo ""
echo "─────────────────────────────────────────────────────────────────────"
echo "  ACCESS URLS (run port-forward commands first)"
echo "─────────────────────────────────────────────────────────────────────"
echo ""
echo "  1. Grafana (Dashboards):"
echo "     kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
echo "     → http://localhost:3000  (admin/chaoslab)"
echo ""
echo "  2. Prometheus (Metrics):"
echo "     kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
echo "     → http://localhost:9090"
echo ""
echo "  3. Chaos Dashboard:"
echo "     kubectl port-forward -n chaos-mesh svc/chaos-dashboard 2333:2333"
echo "     → http://localhost:2333"
echo ""
echo "  4. Application (after Phase 2):"
echo "     → http://localhost:8080"
echo ""
echo "─────────────────────────────────────────────────────────────────────"
echo "  QUICK COMMANDS"
echo "─────────────────────────────────────────────────────────────────────"
echo ""
echo "  View all pods:     kubectl get pods --all-namespaces"
echo "  View nodes:        kubectl get nodes -o wide"
echo "  Delete cluster:    ./scripts/teardown-all.sh"
echo ""
echo "─────────────────────────────────────────────────────────────────────"
echo "  NEXT STEPS"
echo "─────────────────────────────────────────────────────────────────────"
echo ""
echo "  Phase 2: Deploy Target Application"
echo "    → Run: ./scripts/05-deploy-microshop.sh (coming next)"
echo ""
echo "═══════════════════════════════════════════════════════════════════"
