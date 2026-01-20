#!/bin/bash
# =============================================================================
# 05-deploy-microshop.sh
# Deploy MicroShop demo application for chaos engineering
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="${SCRIPT_DIR}/../charts/microshop"
NAMESPACE="microshop"

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          🛒 MicroShop Deployment                          ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# -----------------------------------------------------------------------------
# Step 1: Check prerequisites
# -----------------------------------------------------------------------------
echo -e "${YELLOW}🔍 Checking prerequisites...${NC}"

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl is not installed${NC}"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo -e "${RED}❌ helm is not installed${NC}"
    exit 1
fi

# Check if cluster is running
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ Kubernetes cluster is not running${NC}"
    echo -e "${YELLOW}   Run: ./scripts/01-create-cluster.sh${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Prerequisites satisfied${NC}"
echo ""

# -----------------------------------------------------------------------------
# Step 2: Create namespace (if not exists)
# -----------------------------------------------------------------------------
echo -e "${YELLOW}📁 Creating namespace: ${NAMESPACE}...${NC}"

kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

echo -e "${GREEN}✅ Namespace ready${NC}"
echo ""

# -----------------------------------------------------------------------------
# Step 3: Lint Helm chart
# -----------------------------------------------------------------------------
echo -e "${YELLOW}🔎 Linting Helm chart...${NC}"

if helm lint "${CHART_DIR}"; then
    echo -e "${GREEN}✅ Chart linting passed${NC}"
else
    echo -e "${RED}❌ Chart linting failed${NC}"
    exit 1
fi
echo ""

# -----------------------------------------------------------------------------
# Step 4: Deploy MicroShop with Helm
# -----------------------------------------------------------------------------
echo -e "${YELLOW}🚀 Deploying MicroShop via Helm...${NC}"

helm upgrade --install microshop "${CHART_DIR}" \
    --namespace ${NAMESPACE} \
    --create-namespace \
    --wait \
    --timeout 5m

echo -e "${GREEN}✅ Helm deployment complete${NC}"
echo ""

# -----------------------------------------------------------------------------
# Step 5: Wait for pods to be ready
# -----------------------------------------------------------------------------
echo -e "${YELLOW}⏳ Waiting for all pods to be ready...${NC}"

# Wait for deployments
echo "   Waiting for frontend..."
kubectl rollout status deployment/frontend -n ${NAMESPACE} --timeout=120s || true

echo "   Waiting for catalog..."
kubectl rollout status deployment/catalog -n ${NAMESPACE} --timeout=120s || true

echo "   Waiting for cart..."
kubectl rollout status deployment/cart -n ${NAMESPACE} --timeout=120s || true

echo "   Waiting for checkout..."
kubectl rollout status deployment/checkout -n ${NAMESPACE} --timeout=120s || true

echo "   Waiting for redis..."
kubectl rollout status deployment/redis -n ${NAMESPACE} --timeout=120s || true

echo "   Waiting for rabbitmq..."
kubectl rollout status deployment/rabbitmq -n ${NAMESPACE} --timeout=180s || true

echo "   Waiting for postgresql..."
kubectl rollout status statefulset/postgresql -n ${NAMESPACE} --timeout=120s || true

echo ""

# -----------------------------------------------------------------------------
# Step 6: Display status
# -----------------------------------------------------------------------------
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                📊 Deployment Status                       ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${YELLOW}Pods:${NC}"
kubectl get pods -n ${NAMESPACE} -o wide
echo ""

echo -e "${YELLOW}Services:${NC}"
kubectl get svc -n ${NAMESPACE}
echo ""

echo -e "${YELLOW}Ingress:${NC}"
kubectl get ingress -n ${NAMESPACE}
echo ""

# -----------------------------------------------------------------------------
# Step 7: Display access information
# -----------------------------------------------------------------------------
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                🌐 Access Information                      ║${NC}"
echo -e "${BLUE}╠═══════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║  Frontend:      http://localhost:8080                     ║${NC}"
echo -e "${BLUE}║  RabbitMQ UI:   kubectl port-forward svc/rabbitmq         ║${NC}"
echo -e "${BLUE}║                 15672:15672 -n microshop                  ║${NC}"
echo -e "${BLUE}║                 → http://localhost:15672                  ║${NC}"
echo -e "${BLUE}║                 (microshop/microshop123)                  ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${GREEN}🎉 MicroShop deployment complete!${NC}"
echo ""
echo -e "Next steps:"
echo -e "  1. Access the frontend at http://localhost:8080"
echo -e "  2. Run the load generator: python scripts/load-generator.py --profile steady"
echo -e "  3. View metrics in Grafana: http://localhost:3000"
echo -e "  4. Start chaos experiments in Phase 3!"
