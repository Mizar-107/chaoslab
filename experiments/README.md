# Chaos Experiments Catalog

> A collection of Chaos Mesh experiments for testing MicroShop resilience.

## Quick Start

```bash
# Run an experiment
./scripts/experiments/run-exp-001.sh

# Dry run (see what would happen)
./scripts/experiments/run-exp-001.sh --dry-run
```

## Experiment Summary

| ID | Name | Type | Target | Duration | Risk |
|---|------|------|--------|----------|------|
| [EXP-001](#exp-001-pod-kill) | Pod Kill | PodChaos | catalog-service | 30s | 🟢 Low |
| [EXP-002](#exp-002-network-latency) | Network Latency | NetworkChaos | cart → redis | 60s | 🟡 Medium |
| [EXP-003](#exp-003-cpumemory-stress) | CPU Stress | StressChaos | checkout-service | 120s | 🟡 Medium |
| EXP-003B | Memory Stress | StressChaos | checkout-service | 120s | 🟡 Medium |
| [EXP-004](#exp-004-dns-failure) | DNS Failure | DNSChaos | frontend → catalog | 45s | 🟡 Medium |
| [EXP-005](#exp-005-node-drain) | Node Drain | kubectl drain | Worker node | Manual | 🔴 High |

---

## EXP-001: Pod Kill

**File:** `exp-001-pod-kill.yaml`  
**Script:** `scripts/experiments/run-exp-001.sh`

**Hypothesis:** When a catalog-service pod is killed, the service remains available through the remaining replica, and Kubernetes restarts the pod within 30 seconds.

**Success Criteria:**
- Error rate < 1%
- P95 latency < 500ms
- Pod recovery < 30 seconds

---

## EXP-002: Network Latency

**File:** `exp-002-network-latency.yaml`  
**Script:** `scripts/experiments/run-exp-003.sh`

**Hypothesis:** When 200ms latency is injected between cart-service and Redis, cart operations complete successfully with increased response times.

**Success Criteria:**
- Cart error rate < 5%
- No Redis timeout errors
- Checkout success rate > 95%

---

## EXP-003: CPU/Memory Stress

**Files:** `exp-003-cpu-stress.yaml`, `exp-003b-memory-stress.yaml`  
**Script:** `scripts/experiments/run-exp-002.sh [cpu|memory]`

**Hypothesis:** Under high CPU/memory load, checkout-service queues requests rather than failing.

**Success Criteria:**
- No OOMKilled events
- Error rate < 10%
- Recovery < 60 seconds

---

## EXP-004: DNS Failure

**File:** `exp-004-dns-failure.yaml`  
**Script:** `scripts/experiments/run-exp-004.sh`

**Hypothesis:** When frontend cannot resolve catalog-service DNS, it displays graceful degradation rather than crashing.

**Success Criteria:**
- Frontend: 0 pod restarts
- Cart operations > 95% success
- DNS recovery < 5 seconds

---

## EXP-005: Node Drain

**Script:** `scripts/experiments/run-exp-005.sh [--force]`

**Hypothesis:** When a worker node is drained, all pods reschedule to remaining nodes within 2 minutes.

**Success Criteria:**
- Pod rescheduling < 2 minutes
- Service availability > 90%
- No data loss

⚠️ **This is a high-impact experiment.** It will evict all pods from a worker node.

---

## Manual Experiment Execution

```bash
# Apply an experiment directly
kubectl apply -f experiments/exp-001-pod-kill.yaml

# Monitor chaos experiments
kubectl get podchaos,networkchaos,stresschaos,dnschaos -n microshop

# Emergency abort - delete all chaos
kubectl delete podchaos,networkchaos,stresschaos,dnschaos --all -n microshop
```

---

## Prerequisites

Before running experiments:

1. **Cluster running:** `kubectl get nodes`
2. **MicroShop deployed:** `kubectl get pods -n microshop`
3. **Chaos Mesh installed:** `kubectl get pods -n chaos-mesh`
4. **Load generator active:** `python3 scripts/load-generator.py --profile chaos`
5. **Grafana dashboard open:** `http://localhost:3000`
