# 🔬 ChaosLab: Chaos Engineering Learning Platform

> **A hands-on chaos engineering project for SREs and DevOps engineers to master resilience testing through practical, reproducible experiments.**

---

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Phases Overview](#phases-overview)
- [Common Commands](#common-commands)
- [Troubleshooting](#troubleshooting)

---

## Overview

ChaosLab provides a complete environment for learning and practicing chaos engineering principles:

| Component | Purpose |
|-----------|---------|
| **Kind Cluster** | 4-node local Kubernetes (1 control-plane + 3 workers) |
| **Chaos Mesh** | Chaos engineering platform with web dashboard |
| **Prometheus + Grafana** | Monitoring and visualization |
| **MicroShop** | Target demo application for experiments |

### What You'll Learn

- 📊 Define and measure steady-state behavior using SLIs/SLOs
- 🎯 Design chaos experiments with proper blast radius containment
- 🔄 Implement automated rollback mechanisms
- 📈 Analyze system behavior during failure conditions
- 📝 Create actionable runbooks from experiment findings

---

## Prerequisites

### Required Tools

| Tool | Version | Installation |
|------|---------|--------------|
| Docker Desktop | ≥ 24.0 | [docker.com](https://www.docker.com/products/docker-desktop/) |
| kubectl | ≥ 1.28 | [kubernetes.io](https://kubernetes.io/docs/tasks/tools/) |
| kind | ≥ 0.20 | [kind.sigs.k8s.io](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) |
| helm | ≥ 3.12 | [helm.sh](https://helm.sh/docs/intro/install/) |

### Optional Tools

| Tool | Purpose | Installation |
|------|---------|--------------|
| Python 3.10+ | Load generator scripts | [python.org](https://www.python.org/) |
| jq | JSON processing | `choco install jq` / `brew install jq` |
| k9s | Cluster visualization | `choco install k9s` / `brew install k9s` |

### System Requirements

```
Minimum:
  CPU: 4 cores
  RAM: 16 GB (8 GB minimum, degraded experience)
  Disk: 30 GB free

Recommended:
  CPU: 8 cores
  RAM: 32 GB
  Disk: 50 GB SSD
```

### Verify Prerequisites

```bash
# Windows: Run in Git Bash or WSL
./scripts/check-prerequisites.sh
```

---

## Quick Start

### 1. Clone and Setup

```bash
# Navigate to chaoslab directory
cd chaoslab

# Run complete setup (takes ~10-15 minutes)
./scripts/setup-all.sh
```

### 2. Access the UIs

Open three terminals and run:

```bash
# Terminal 1: Grafana (Dashboards)
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# → http://localhost:3000  (admin/chaoslab)

# Terminal 2: Prometheus (Metrics)
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# → http://localhost:9090

# Terminal 3: Chaos Dashboard
kubectl port-forward -n chaos-mesh svc/chaos-dashboard 2333:2333
# → http://localhost:2333
```

### 3. Verify Installation

```bash
# Check all nodes
kubectl get nodes

# Check all pods
kubectl get pods --all-namespaces

# Check Chaos Mesh
kubectl get pods -n chaos-mesh
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         KIND CLUSTER: chaoslab                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    CONTROL PLANE NODE                            │   │
│  │  • API Server  • Scheduler  • Controller Manager                 │   │
│  │  • Ingress Controller (nginx)                                    │   │
│  │  Port mappings: 80→8080, 443→8443, 30000-30003                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                     │
│  │   WORKER 1  │  │   WORKER 2  │  │   WORKER 3  │                     │
│  │  (frontend) │  │  (backend)  │  │   (data)    │                     │
│  │             │  │             │  │             │                     │
│  │  Frontend   │  │  Catalog    │  │  PostgreSQL │                     │
│  │  pods       │  │  Cart       │  │  Redis      │                     │
│  │             │  │  Checkout   │  │  RabbitMQ   │                     │
│  └─────────────┘  └─────────────┘  └─────────────┘                     │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  NAMESPACES                                                      │   │
│  │  • chaos-mesh   - Chaos Mesh controller & daemon                 │   │
│  │  • monitoring   - Prometheus, Grafana, Alertmanager              │   │
│  │  • microshop    - Target application (Phase 2)                   │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Phases Overview

| Phase | Description | Status |
|-------|-------------|--------|
| **Phase 1** | Environment Setup | ✅ Implemented |
| **Phase 2** | Deploy Target Application | ✅ Implemented |
| **Phase 3** | Establish Steady State | ✅ Implemented |
| **Phase 4** | Chaos Experiments | ✅ Implemented |
| **Phase 5** | Observability & Analysis | ✅ Implemented |
| **Phase 6** | GameDay Simulation | ✅ Implemented |

See [PROGRESS.md](./PROGRESS.md) for detailed progress tracking.

---

## Common Commands

### Cluster Management

```bash
# View cluster info
kubectl cluster-info --context kind-chaoslab

# View all nodes
kubectl get nodes -o wide

# View all pods
kubectl get pods --all-namespaces

# Delete cluster
./scripts/teardown-all.sh
```

### Chaos Mesh

```bash
# View chaos experiments
kubectl get podchaos,networkchaos,stresschaos,dnschaos -n microshop

# Delete all chaos experiments
kubectl delete podchaos,networkchaos,stresschaos,dnschaos --all -n microshop
```

### Monitoring

```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Port-forward Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Port-forward Chaos Dashboard
kubectl port-forward -n chaos-mesh svc/chaos-dashboard 2333:2333
```

### Application (Phase 2+)

```bash
# View MicroShop pods
kubectl get pods -n microshop

# View MicroShop services
kubectl get svc -n microshop

# Restart all MicroShop deployments
kubectl rollout restart deploy --all -n microshop
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| **Docker not running** | Start Docker Desktop |
| **Kind cluster won't start** | Ensure Docker has enough resources (4+ GB RAM) |
| **Pods stuck in Pending** | Check node resources: `kubectl describe nodes` |
| **Chaos Mesh pods crashing** | Check runtime: containerd should be detected |
| **Port-forward fails** | Check if port is already in use |
| **Grafana shows no data** | Wait 2-3 minutes for metrics to be collected |

### Reset Everything

```bash
# Full teardown and recreate
./scripts/teardown-all.sh --force
./scripts/setup-all.sh
```

### View Logs

```bash
# Chaos Mesh controller
kubectl logs -n chaos-mesh -l app.kubernetes.io/component=controller-manager

# Prometheus
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus

# Grafana
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana
```

---

## Project Structure

```
chaoslab/
├── README.md                    # This file
├── PROGRESS.md                  # Implementation progress tracking
│
├── infrastructure/
│   └── kind-config.yaml        # Kind cluster configuration
│
├── scripts/
│   ├── check-prerequisites.sh  # Verify required tools
│   ├── 01-create-cluster.sh    # Create Kind cluster
│   ├── 02-install-ingress.sh   # Install NGINX ingress
│   ├── 03-install-chaos-mesh.sh # Install Chaos Mesh
│   ├── 04-install-observability.sh # Install Prometheus + Grafana
│   ├── setup-all.sh            # Run all setup scripts
│   └── teardown-all.sh         # Delete cluster
│
├── charts/                      # Helm charts (Phase 2)
├── experiments/                 # Chaos experiment YAMLs (Phase 4)
├── dashboards/                  # Grafana dashboards (Phase 5)
├── runbooks/                    # Incident response runbooks (Phase 6)
└── src/                         # Application source (if needed)
```

---

## License

This project is for educational purposes.

---

*Last Updated: 2026-01-20*
