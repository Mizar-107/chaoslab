#!/bin/bash
# =============================================================================
# ChaosLab: Install Chaos Mesh
# =============================================================================
# Installs Chaos Mesh for chaos engineering experiments.
#
# Usage: ./scripts/03-install-chaos-mesh.sh
#
# Chaos Mesh provides:
#   - Pod chaos (kill, failure)
#   - Network chaos (latency, partition, loss)
#   - Stress chaos (CPU, memory)
#   - DNS chaos
#   - Web dashboard for experiment management
#
# Windows Users: Run this in Git Bash or WSL
# =============================================================================

set -euo pipefail

# Configuration
CHAOS_MESH_NAMESPACE="chaos-mesh"
CHAOS_MESH_VERSION="2.6.2"  # Stable version

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║           ChaosLab: Install Chaos Mesh                            ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""

# Add Chaos Mesh Helm repository
echo -e "${BLUE}▶ Adding Chaos Mesh Helm repository...${NC}"
helm repo add chaos-mesh https://charts.chaos-mesh.org 2>/dev/null || true
helm repo update
echo -e "${GREEN}✓ Helm repository added${NC}"
echo ""

# Create namespace
echo -e "${BLUE}▶ Creating namespace '${CHAOS_MESH_NAMESPACE}'...${NC}"
kubectl create namespace "$CHAOS_MESH_NAMESPACE" 2>/dev/null || echo "  Namespace already exists"
echo ""

# Install Chaos Mesh
echo -e "${BLUE}▶ Installing Chaos Mesh via Helm...${NC}"
echo -e "  Version: ${CHAOS_MESH_VERSION}"
echo -e "  Namespace: ${CHAOS_MESH_NAMESPACE}"
echo -e "  Runtime: containerd (Kind default)"
echo ""

helm upgrade --install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace "$CHAOS_MESH_NAMESPACE" \
  --version "$CHAOS_MESH_VERSION" \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock \
  --set dashboard.create=true \
  --set dashboard.securityMode=false \
  --set dashboard.service.type=ClusterIP \
  --wait \
  --timeout 10m

echo ""
echo -e "${GREEN}✓ Chaos Mesh installed${NC}"
echo ""

# Wait for all pods to be ready
echo -e "${BLUE}▶ Waiting for Chaos Mesh pods to be ready...${NC}"
kubectl wait --for=condition=Ready pods --all -n "$CHAOS_MESH_NAMESPACE" --timeout=300s
echo ""

# Show Chaos Mesh resources
echo -e "${BLUE}▶ Chaos Mesh Resources${NC}"
echo "─────────────────────────────────────────────────────────"
kubectl get pods -n "$CHAOS_MESH_NAMESPACE"
echo ""

# Show services
echo -e "${BLUE}▶ Chaos Mesh Services${NC}"
echo "─────────────────────────────────────────────────────────"
kubectl get svc -n "$CHAOS_MESH_NAMESPACE"
echo ""

# Summary
echo "═══════════════════════════════════════════════════════════════════"
echo -e "${GREEN}✓ Chaos Mesh installed successfully!${NC}"
echo ""
echo "Components installed:"
echo "  • chaos-controller-manager  - Orchestrates chaos experiments"
echo "  • chaos-daemon (DaemonSet)  - Executes chaos on each node"
echo "  • chaos-dashboard           - Web UI for experiment management"
echo ""
echo "To access the Chaos Dashboard:"
echo "  kubectl port-forward -n chaos-mesh svc/chaos-dashboard 2333:2333"
echo "  Then open: http://localhost:2333"
echo ""
echo "Next step: Run ./scripts/04-install-observability.sh"
echo "═══════════════════════════════════════════════════════════════════"
