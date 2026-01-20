#!/bin/bash
# =============================================================================
# ChaosLab: Create Kind Cluster
# =============================================================================
# Creates a multi-node Kind cluster for chaos engineering experiments.
#
# Usage: ./scripts/01-create-cluster.sh
#
# This script will:
#   1. Delete any existing 'chaoslab' cluster
#   2. Create a new cluster with 1 control-plane + 3 workers
#   3. Wait for all nodes to be ready
#   4. Set kubectl context to the new cluster
#
# Windows Users: Run this in Git Bash or WSL with Docker Desktop running
# =============================================================================

set -euo pipefail

# Configuration
CLUSTER_NAME="chaoslab"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KIND_CONFIG="$PROJECT_ROOT/infrastructure/kind-config.yaml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║           ChaosLab: Create Kind Cluster                           ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""

# Check Docker is running
echo -e "${BLUE}▶ Checking Docker...${NC}"
if ! docker info &> /dev/null; then
    echo -e "${RED}✗ Docker is not running. Please start Docker Desktop.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Docker is running${NC}"
echo ""

# Check kind-config.yaml exists
if [ ! -f "$KIND_CONFIG" ]; then
    echo -e "${RED}✗ Kind config not found: $KIND_CONFIG${NC}"
    exit 1
fi

# Delete existing cluster if present
echo -e "${BLUE}▶ Checking for existing cluster...${NC}"
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo -e "${YELLOW}  Found existing cluster '$CLUSTER_NAME', deleting...${NC}"
    kind delete cluster --name "$CLUSTER_NAME"
    echo -e "${GREEN}✓ Existing cluster deleted${NC}"
else
    echo -e "  No existing cluster found"
fi
echo ""

# Create new cluster
echo -e "${BLUE}▶ Creating Kind cluster '$CLUSTER_NAME'...${NC}"
echo -e "  Config: $KIND_CONFIG"
echo -e "  This may take 2-5 minutes..."
echo ""

kind create cluster --config "$KIND_CONFIG" --wait 5m

echo ""
echo -e "${GREEN}✓ Cluster created successfully!${NC}"
echo ""

# Verify nodes
echo -e "${BLUE}▶ Verifying cluster nodes...${NC}"
kubectl get nodes -o wide
echo ""

# Wait for all nodes to be ready
echo -e "${BLUE}▶ Waiting for all nodes to be Ready...${NC}"
kubectl wait --for=condition=Ready nodes --all --timeout=300s
echo -e "${GREEN}✓ All nodes are Ready${NC}"
echo ""

# Show cluster info
echo -e "${BLUE}▶ Cluster Information${NC}"
echo "─────────────────────────────────────────────────────────"
kubectl cluster-info --context "kind-${CLUSTER_NAME}"
echo ""

# Summary
echo "═══════════════════════════════════════════════════════════════════"
echo -e "${GREEN}✓ Kind cluster '$CLUSTER_NAME' is ready!${NC}"
echo ""
echo "Cluster details:"
echo "  Name:          $CLUSTER_NAME"
echo "  Context:       kind-$CLUSTER_NAME"
echo "  Nodes:         1 control-plane + 3 workers"
echo ""
echo "Next step: Run ./scripts/02-install-ingress.sh"
echo "═══════════════════════════════════════════════════════════════════"
