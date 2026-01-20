# Incident Runbook: Resource Exhaustion

> Response procedures for CPU/memory exhaustion and node pressure.

## Detection

### Symptoms

- Pods evicted or OOMKilled
- High CPU throttling
- Node memory/disk pressure
- Alerts: `HighCPU`, `HighMemory`, `NodePressure`, `PodEvicted`

### Alert Queries

```promql
# High memory usage
container_memory_working_set_bytes / container_spec_memory_limit_bytes > 0.9

# CPU throttling
rate(container_cpu_cfs_throttled_seconds_total[5m]) > 0.1

# Node memory pressure
kube_node_status_condition{condition="MemoryPressure", status="true"} == 1
```

---

## Diagnosis

### Step 1: Identify Resource Pressure

```bash
# Node-level resource status
kubectl describe nodes | grep -A20 "Allocated resources"

# Top resource consumers
kubectl top nodes
kubectl top pods -n microshop --sort-by=memory
kubectl top pods -n microshop --sort-by=cpu
```

### Step 2: Check for OOMKilled Pods

```bash
# Find OOMKilled containers
kubectl get pods -n microshop -o json | jq -r '.items[] | 
  select(.status.containerStatuses[].lastState.terminated.reason == "OOMKilled") | 
  .metadata.name'

# Get restart counts
kubectl get pods -n microshop -o wide
```

### Step 3: Check for Stress Chaos

```bash
# Active stress experiments
kubectl get stresschaos -n microshop

# If active during GameDay, this is expected
# If NOT expected, remove immediately
```

### Step 4: Check Node Conditions

```bash
# Check for node pressure conditions
kubectl get nodes -o json | jq -r '.items[] | 
  .metadata.name + ": " + 
  (.status.conditions | map(select(.status == "True") | .type) | join(", "))'
```

---

## Common Causes & Remediation

### Cause 1: Stress Chaos Experiment

**Detection:**
```bash
kubectl get stresschaos -n microshop
```

**Remediation:**
```bash
# Remove stress chaos
kubectl delete stresschaos --all -n microshop

# Wait for pods to recover
kubectl get pods -n microshop -w
```

### Cause 2: Memory Leak in Application

**Detection:**
```bash
# Check memory growth over time
kubectl top pods -n microshop --sort-by=memory

# Compare to limits
kubectl get pods -n microshop -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].resources.limits.memory}{"\n"}{end}'
```

**Remediation:**
```bash
# Restart affected pods
kubectl rollout restart deployment/<AFFECTED_DEPLOYMENT> -n microshop

# Long-term: increase limits or fix memory leak
helm upgrade microshop charts/microshop -n microshop \
  --set <service>.resources.limits.memory=1Gi
```

### Cause 3: CPU-Intensive Workload

**Detection:**
```bash
kubectl top pods -n microshop --sort-by=cpu
# Compare CPU usage to limits
```

**Remediation:**
```bash
# Scale out to distribute load
kubectl scale deployment/<SERVICE> -n microshop --replicas=4

# Or increase CPU limits
helm upgrade microshop charts/microshop -n microshop \
  --set <service>.resources.limits.cpu=1000m
```

### Cause 4: Node Resource Exhaustion

**Detection:**
```bash
kubectl describe nodes | grep -A5 "Conditions:"
# Look for MemoryPressure, DiskPressure, PIDPressure
```

**Remediation:**
```bash
# Remove non-essential workloads
kubectl delete jobs --all -n microshop

# If using Kind, restart Docker to clear resources
# docker restart $(docker ps -q)

# Cordon node temporarily
kubectl cordon <NODE_NAME>
```

---

## Emergency Actions

### Immediate Relief

```bash
# Delete all stress chaos
kubectl delete stresschaos --all -n microshop

# Scale down non-critical services
kubectl scale deployment/catalog --replicas=1 -n microshop
kubectl scale deployment/cart --replicas=1 -n microshop

# Delete pending pods consuming resources
kubectl delete pods --field-selector=status.phase=Pending -n microshop
```

### If Node Unresponsive

```bash
# Drain the node (if recoverable)
kubectl drain <NODE_NAME> --ignore-daemonsets --delete-emptydir-data

# For Kind: restart the node container
docker restart chaoslab-worker
```

---

## Recovery Verification

After applying remediation:

```bash
# Check resource usage stabilized
kubectl top pods -n microshop
kubectl top nodes

# Verify no node pressure
kubectl get nodes -o json | jq '.items[].status.conditions[] | 
  select(.type | contains("Pressure")) | 
  {type: .type, status: .status}'

# Check pods recovered
kubectl get pods -n microshop
```

**Success Criteria:**
- [ ] No OOMKilled events in last 5 minutes
- [ ] CPU usage < 80% of limits
- [ ] Memory usage < 90% of limits
- [ ] No node pressure conditions
- [ ] All pods Running

---

## Prevention

### Resource Quotas

```bash
# Apply namespace quotas
kubectl apply -f - <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: microshop-quota
  namespace: microshop
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
EOF
```

### Limit Ranges

```bash
# Apply default limits
kubectl apply -f - <<EOF
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: microshop
spec:
  limits:
  - default:
      cpu: 500m
      memory: 512Mi
    defaultRequest:
      cpu: 100m
      memory: 128Mi
    type: Container
EOF
```

---

## Escalation

If issues persist after 15 minutes:

1. Check for cluster-wide resource contention
2. Consider adding more nodes (if cloud)
3. Review recent deployments for resource regression
4. Engage infrastructure team

---

## Post-Incident

- [ ] Review and adjust resource limits
- [ ] Add resource quotas if missing  
- [ ] Update monitoring thresholds
- [ ] Document root cause

---

*Last Updated: 2026-01-20*
