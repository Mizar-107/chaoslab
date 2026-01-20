#!/bin/bash
# =============================================================================
# ChaosLab Prerequisites Checker
# =============================================================================
# Verifies all required tools are installed and system meets requirements.
#
# Usage: ./scripts/check-prerequisites.sh
#
# Requirements:
#   - Docker Desktop >= 24.0
#   - kubectl >= 1.28
#   - kind >= 0.20
#   - helm >= 3.12
#   - (Optional) Python >= 3.10 for load generator
#   - (Optional) jq >= 1.6 for JSON processing
#
# Windows Users: Run this in Git Bash or WSL
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
ERRORS=0
WARNINGS=0

echo ""
echo "╔═══════════════════════════════════════════════════════════════════╗"
echo "║           ChaosLab Prerequisites Checker                          ║"
echo "╚═══════════════════════════════════════════════════════════════════╝"
echo ""

# Function to check if a command exists
check_command() {
    local cmd=$1
    local required=$2
    local version_cmd=$3
    local min_version=$4

    printf "Checking %-12s ... " "$cmd"
    
    if command -v "$cmd" &> /dev/null; then
        version=$($version_cmd 2>/dev/null | head -1 || echo "unknown")
        echo -e "${GREEN}✓ Installed${NC} ($version)"
        return 0
    else
        if [ "$required" = "required" ]; then
            echo -e "${RED}✗ NOT INSTALLED (required)${NC}"
            ((ERRORS++))
            return 1
        else
            echo -e "${YELLOW}○ Not installed (optional)${NC}"
            ((WARNINGS++))
            return 0
        fi
    fi
}

# Function to check Docker is running
check_docker_running() {
    printf "Checking Docker daemon   ... "
    if docker info &> /dev/null; then
        echo -e "${GREEN}✓ Running${NC}"
        return 0
    else
        echo -e "${YELLOW}○ Not running${NC}"
        echo -e "   ${YELLOW}→ Start Docker Desktop before running setup scripts${NC}"
        ((WARNINGS++))
        return 1
    fi
}

# =============================================================================
# Check Required Tools
# =============================================================================
echo -e "${BLUE}▶ Required Tools${NC}"
echo "─────────────────────────────────────────────────────────"

check_command "docker" "required" "docker --version" "24.0"
check_command "kubectl" "required" "kubectl version --client -o yaml 2>/dev/null | grep gitVersion | head -1" "1.28"
check_command "kind" "required" "kind version" "0.20"
check_command "helm" "required" "helm version --short" "3.12"

echo ""

# =============================================================================
# Check Optional Tools
# =============================================================================
echo -e "${BLUE}▶ Optional Tools${NC}"
echo "─────────────────────────────────────────────────────────"

check_command "python3" "optional" "python3 --version" "3.10"
check_command "jq" "optional" "jq --version" "1.6"
check_command "k9s" "optional" "k9s version --short 2>/dev/null || echo 'installed'" "0.27"

echo ""

# =============================================================================
# Check Docker Status
# =============================================================================
echo -e "${BLUE}▶ Docker Status${NC}"
echo "─────────────────────────────────────────────────────────"

check_docker_running

echo ""

# =============================================================================
# Check System Resources
# =============================================================================
echo -e "${BLUE}▶ System Resources${NC}"
echo "─────────────────────────────────────────────────────────"

# Get CPU cores
printf "CPU Cores            ... "
if command -v nproc &> /dev/null; then
    CPU_CORES=$(nproc)
elif command -v sysctl &> /dev/null; then
    CPU_CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo "unknown")
elif [ -f /proc/cpuinfo ]; then
    CPU_CORES=$(grep -c processor /proc/cpuinfo)
else
    CPU_CORES="unknown"
fi

if [ "$CPU_CORES" != "unknown" ] && [ "$CPU_CORES" -ge 4 ]; then
    echo -e "${GREEN}✓ $CPU_CORES cores${NC} (minimum: 4)"
elif [ "$CPU_CORES" != "unknown" ]; then
    echo -e "${YELLOW}○ $CPU_CORES cores${NC} (recommended: 4+)"
    ((WARNINGS++))
else
    echo -e "${YELLOW}○ Unable to detect${NC}"
fi

# Get RAM (works on Linux/Git Bash with /proc)
printf "RAM                  ... "
if [ -f /proc/meminfo ]; then
    RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    RAM_GB=$((RAM_KB / 1024 / 1024))
    if [ "$RAM_GB" -ge 16 ]; then
        echo -e "${GREEN}✓ ${RAM_GB} GB${NC} (minimum: 16 GB)"
    elif [ "$RAM_GB" -ge 8 ]; then
        echo -e "${YELLOW}○ ${RAM_GB} GB${NC} (recommended: 16 GB, may experience issues)"
        ((WARNINGS++))
    else
        echo -e "${RED}✗ ${RAM_GB} GB${NC} (minimum: 8 GB required)"
        ((ERRORS++))
    fi
else
    echo -e "${YELLOW}○ Unable to detect (check Docker Desktop settings)${NC}"
fi

# Check Docker allocated resources
printf "Docker Resources     ... "
if docker info &> /dev/null; then
    DOCKER_MEM=$(docker info 2>/dev/null | grep "Total Memory" | awk '{print $3, $4}' || echo "unknown")
    DOCKER_CPUS=$(docker info 2>/dev/null | grep "CPUs" | awk '{print $2}' || echo "unknown")
    echo -e "${GREEN}✓${NC} CPUs: $DOCKER_CPUS, Memory: $DOCKER_MEM"
else
    echo -e "${YELLOW}○ Docker not running${NC}"
fi

echo ""

# =============================================================================
# Summary
# =============================================================================
echo "═══════════════════════════════════════════════════════════════════"

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All prerequisites satisfied! Ready to proceed.${NC}"
    echo ""
    echo "Next step: Run ./scripts/setup-all.sh"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}○ Prerequisites met with $WARNINGS warning(s).${NC}"
    echo ""
    echo "You can proceed, but review the warnings above."
    echo "Next step: Run ./scripts/setup-all.sh"
    exit 0
else
    echo -e "${RED}✗ Missing $ERRORS required prerequisite(s).${NC}"
    echo ""
    echo "Please install the missing tools before proceeding."
    echo ""
    echo "Installation links:"
    echo "  Docker Desktop: https://www.docker.com/products/docker-desktop/"
    echo "  kubectl:        https://kubernetes.io/docs/tasks/tools/"
    echo "  kind:           https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
    echo "  helm:           https://helm.sh/docs/intro/install/"
    exit 1
fi
