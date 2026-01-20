#!/bin/bash
# =============================================================================
# ChaosLab: Teardown Script
# =============================================================================
# Removes the ChaosLab environment completely.
#
# Usage: ./scripts/teardown-all.sh [--force]
#
# Options:
#   --force    Skip confirmation prompt
#
# This will:
#   1. Delete the Kind cluster 'chaoslab'
#   2. Optionally clean up Docker resources
#
# Windows Users: Run this in Git Bash or WSL
# =============================================================================

set -euo pipefail

# Configuration
CLUSTER_NAME="chaoslab"
FORCE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force|-f)
            FORCE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--force]"
            exit 1
            ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║              ChaosLab: Teardown                                   ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""

# Check if cluster exists
if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo -e "${YELLOW}Cluster '$CLUSTER_NAME' does not exist.${NC}"
    echo "Nothing to tear down."
    exit 0
fi

# Confirm unless --force
if [ "$FORCE" = false ]; then
    echo -e "${RED}⚠️  WARNING: This will delete the entire ChaosLab environment!${NC}"
    echo ""
    echo "This action will:"
    echo "  • Delete Kind cluster '$CLUSTER_NAME'"
    echo "  • Remove all deployed applications"
    echo "  • Remove all chaos experiments"
    echo "  • Remove all monitoring data"
    echo ""
    read -p "Are you sure you want to proceed? (yes/no) " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Teardown cancelled."
        exit 0
    fi
fi

echo -e "${BLUE}▶ Deleting Kind cluster '$CLUSTER_NAME'...${NC}"
kind delete cluster --name "$CLUSTER_NAME"
echo -e "${GREEN}✓ Cluster deleted${NC}"
echo ""

# Optional: Clean up Docker resources
echo -e "${BLUE}▶ Docker cleanup options:${NC}"
echo "  The cluster has been deleted. Docker images are still cached."
echo ""
echo "  To free up disk space, you can run:"
echo "    docker system prune -f          # Remove unused containers, networks"
echo "    docker volume prune -f          # Remove unused volumes"
echo "    docker image prune -a -f        # Remove all unused images"
echo ""

# Summary
echo "═══════════════════════════════════════════════════════════════════"
echo -e "${GREEN}✓ ChaosLab teardown complete!${NC}"
echo ""
echo "To recreate the environment:"
echo "  ./scripts/setup-all.sh"
echo ""
echo "═══════════════════════════════════════════════════════════════════"
