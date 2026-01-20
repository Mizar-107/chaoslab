#!/bin/bash
# =============================================================================
# ChaosLab: Install NGINX Ingress Controller
# =============================================================================
# Installs the NGINX Ingress Controller configured for Kind clusters.
#
# Usage: ./scripts/02-install-ingress.sh
#
# This enables external access to services via:
#   - http://localhost:8080 (mapped from container port 80)
#   - https://localhost:8443 (mapped from container port 443)
#
# Windows Users: Run this in Git Bash or WSL
# =============================================================================

set -euo pipefail

# Configuration
INGRESS_NGINX_VERSION="controller-v1.9.5"  # Stable version
INGRESS_MANIFEST="https://raw.githubusercontent.com/kubernetes/ingress-nginx/${INGRESS_NGINX_VERSION}/deploy/static/provider/kind/deploy.yaml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║           ChaosLab: Install NGINX Ingress Controller              ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""

# Check kubectl context
echo -e "${BLUE}▶ Checking Kubernetes context...${NC}"
CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
if [[ "$CURRENT_CONTEXT" != *"chaoslab"* ]]; then
    echo -e "${YELLOW}  Warning: Current context is '$CURRENT_CONTEXT'${NC}"
    echo -e "${YELLOW}  Expected context containing 'chaoslab'${NC}"
    read -p "  Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
else
    echo -e "${GREEN}✓ Context: $CURRENT_CONTEXT${NC}"
fi
echo ""

# Apply NGINX Ingress Controller
echo -e "${BLUE}▶ Installing NGINX Ingress Controller...${NC}"
echo -e "  Version: ${INGRESS_NGINX_VERSION}"
echo -e "  Manifest: Kind-specific deployment"
echo ""

kubectl apply -f "$INGRESS_MANIFEST"

echo ""

# Wait for ingress controller to be ready
echo -e "${BLUE}▶ Waiting for Ingress Controller to be ready...${NC}"
echo -e "  This may take 1-2 minutes..."

# Wait for the deployment to exist first
kubectl wait --namespace ingress-nginx \
  --for=condition=available deployment/ingress-nginx-controller \
  --timeout=300s 2>/dev/null || true

# Wait for the pod to be ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

echo ""
echo -e "${GREEN}✓ Ingress Controller is ready!${NC}"
echo ""

# Show ingress-nginx resources
echo -e "${BLUE}▶ Ingress NGINX Resources${NC}"
echo "─────────────────────────────────────────────────────────"
kubectl get pods,svc -n ingress-nginx
echo ""

# Summary
echo "═══════════════════════════════════════════════════════════════════"
echo -e "${GREEN}✓ NGINX Ingress Controller installed successfully!${NC}"
echo ""
echo "Access points:"
echo "  HTTP:   http://localhost:8080"
echo "  HTTPS:  https://localhost:8443"
echo ""
echo "Next step: Run ./scripts/03-install-chaos-mesh.sh"
echo "═══════════════════════════════════════════════════════════════════"
