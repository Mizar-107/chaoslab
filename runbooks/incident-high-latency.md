# Incident Runbook: High Latency

> Response procedures for elevated response times and network latency.

## Detection

### Symptoms

- Response times exceed SLO thresholds
- Timeouts reported in logs
- User-facing slowness complaints
- Alerts: `HighLatency`, `SlowRequests`

### Alert Query

```promql
# P95 latency above threshold
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 0.5

# Increase in request duration
rate(http_request_duration_seconds_sum[5m]) / rate(http_request_duration_seconds_count[5m]) > 0.3
```

---

## Diagnosis

### Step 1: Identify Scope

```bash
# Check which services are affected
kubectl top pods -n microshop

# Check service endpoints
kubectl get endpoints -n microshop
```

### Step 2: Check for Active Chaos Experiments

```bash
# List all active chaos
kubectl get podchaos,networkchaos,stresschaos,dnschaos -n microshop

# If chaos is active during incident, this may be expected behavior
# If NOT during GameDay, investigate and remove
```

### Step 3: Network Diagnostics

```bash
# Check network policies
kubectl get networkpolicies -n microshop

# Test connectivity between pods
kubectl exec -it <SOURCE_POD> -n microshop -- wget -qO- --timeout=5 http://<TARGET_SERVICE>:8080/health

# Check DNS resolution
kubectl exec -it <POD> -n microshop -- nslookup <SERVICE_NAME>
```

### Step 4: Check Resource Pressure

```bash
# Node network stats
kubectl describe nodes | grep -A10 "Allocated resources"

# Pod resource consumption
kubectl top pods -n microshop --sort-by=cpu
kubectl top pods -n microshop --sort-by=memory
```

---

## Common Causes & Remediation

### Cause 1: Active Network Chaos Experiment

**Detection:**
```bash
kubectl get networkchaos -n microshop
```

**Remediation:**
```bash
# Remove network chaos (if unintended)
kubectl delete networkchaos --all -n microshop

# Verify connectivity restored
kubectl exec -it <POD> -n microshop -- wget -qO- --timeout=5 http://<TARGET>:8080/health
```

### Cause 2: DNS Issues

**Detection:**
```bash
kubectl exec -it <POD> -n microshop -- nslookup catalog-service
# Slow or failed resolution indicates DNS issues
```

**Remediation:**
```bash
# Check DNS chaos
kubectl get dnschaos -n microshop
kubectl delete dnschaos --all -n microshop

# Restart CoreDNS
kubectl rollout restart deployment/coredns -n kube-system

# Verify DNS working
kubectl exec -it <POD> -n microshop -- nslookup kubernetes.default
```

### Cause 3: Downstream Service Overload

**Detection:**
```bash
# Check downstream services (Redis, PostgreSQL)
kubectl get pods -n microshop -l tier=data
kubectl logs -l app=redis -n microshop --tail=20
```

**Remediation:**
```bash
# Restart affected data tier
kubectl rollout restart deployment/redis -n microshop

# Or scale if under-provisioned (temporarily)
kubectl scale deployment/<SERVICE> -n microshop --replicas=3
```

### Cause 4: Pod Throttling (CPU)

**Detection:**
```bash
kubectl top pods -n microshop
# Look for pods at CPU limit
```

**Remediation:**
```bash
# Scale horizontally
kubectl scale deployment/<AFFECTED_SERVICE> -n microshop --replicas=4

# Or increase CPU limits
helm upgrade microshop charts/microshop -n microshop \
  --set <service>.resources.limits.cpu=500m
```

---

## Recovery Verification

After applying remediation:

```bash
# Test response times
time kubectl exec -it <POD> -n microshop -- wget -qO- http://<SERVICE>:8080/health

# Watch metrics
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# Check Grafana dashboards for latency normalization
```

**Success Criteria:**
- [ ] P95 latency < 500ms
- [ ] No timeout errors in logs
- [ ] Network chaos experiments cleaned up
- [ ] All network policies as expected

---

## Prometheus Queries for Investigation

```promql
# Latency by service
histogram_quantile(0.95, 
  sum(rate(http_request_duration_seconds_bucket{namespace="microshop"}[5m])) 
  by (service, le)
)

# Error rate
sum(rate(http_requests_total{namespace="microshop", status=~"5.."}[5m])) 
/ sum(rate(http_requests_total{namespace="microshop"}[5m]))

# Request rate
sum(rate(http_requests_total{namespace="microshop"}[5m])) by (service)
```

---

## Escalation

If latency persists after 15 minutes:

1. Check cluster networking (CNI issues)
2. Check node network interfaces
3. Review recent network policy changes
4. Engage platform/infrastructure team

---

## Post-Incident

- [ ] Document root cause and timeline
- [ ] Verify chaos experiments properly cleaned up
- [ ] Review SLO thresholds (too aggressive?)
- [ ] Update alerting if detection was delayed

---

*Last Updated: 2026-01-20*
