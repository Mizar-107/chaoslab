# Incident Runbook: Pod Crash Loop

> Response procedures for pods stuck in CrashLoopBackOff state.

## Detection

### Symptoms

- Pod status shows `CrashLoopBackOff` or `Error`
- Service availability drops
- Alerts: `PodCrashLooping`, `ServiceDegraded`

### Alert Query

```promql
# Pods restarting frequently
increase(kube_pod_container_status_restarts_total[5m]) > 3
```

---

## Diagnosis

### Step 1: Identify Affected Pods

```bash
# List all pods with issues
kubectl get pods -n microshop | grep -E "CrashLoop|Error|ImagePull"

# Get specific pod status
kubectl describe pod <POD_NAME> -n microshop
```

### Step 2: Check Container Logs

```bash
# Current container logs
kubectl logs <POD_NAME> -n microshop

# Previous container logs (if crashed)
kubectl logs <POD_NAME> -n microshop --previous

# All containers in pod
kubectl logs <POD_NAME> -n microshop --all-containers
```

### Step 3: Check Events

```bash
# Recent events for pod
kubectl get events -n microshop --field-selector involvedObject.name=<POD_NAME>

# All recent events
kubectl get events -n microshop --sort-by='.lastTimestamp' | tail -20
```

### Step 4: Check Resource Usage

```bash
# Node resource pressure
kubectl describe nodes | grep -A5 "Conditions:"

# Pod resource requests vs limits
kubectl get pod <POD_NAME> -n microshop -o jsonpath='{.spec.containers[*].resources}'
```

---

## Common Causes & Remediation

### Cause 1: OOMKilled (Memory)

**Detection:**
```bash
kubectl describe pod <POD_NAME> -n microshop | grep -A5 "Last State"
# Look for: Reason: OOMKilled
```

**Remediation:**
```bash
# Increase memory limit in values.yaml
# Then upgrade the deployment
helm upgrade microshop charts/microshop -n microshop \
  --set <service>.resources.limits.memory=512Mi
```

### Cause 2: Liveness Probe Failure

**Detection:**
```bash
kubectl describe pod <POD_NAME> -n microshop | grep -A10 "Events"
# Look for: Liveness probe failed
```

**Remediation:**
```bash
# Option 1: Increase probe timeouts
# Option 2: Fix application health endpoint
# Option 3: Temporarily disable probe (emergency only)
kubectl patch deployment <DEPLOY_NAME> -n microshop \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"<CONTAINER>","livenessProbe":null}]}}}}'
```

### Cause 3: Application Error

**Detection:**
```bash
kubectl logs <POD_NAME> -n microshop --previous | tail -50
# Look for stack traces, error messages
```

**Remediation:**
```bash
# Rollback to previous version
kubectl rollout undo deployment/<DEPLOY_NAME> -n microshop

# Or restart deployment
kubectl rollout restart deployment/<DEPLOY_NAME> -n microshop
```

### Cause 4: Missing Dependencies

**Detection:**
```bash
kubectl logs <POD_NAME> -n microshop
# Look for: connection refused, DNS resolution failed
```

**Remediation:**
```bash
# Check dependent services
kubectl get pods -n microshop -l app=<DEPENDENCY>

# Restart dependent service if needed
kubectl rollout restart deployment/<DEPENDENCY> -n microshop
```

---

## Recovery Verification

After applying remediation:

```bash
# Watch pod status
kubectl get pods -n microshop -l app=<APP_NAME> -w

# Verify no recent restarts
kubectl get pods -n microshop -o wide

# Check logs for healthy startup
kubectl logs -l app=<APP_NAME> -n microshop --tail=20
```

**Success Criteria:**
- [ ] Pod status is `Running`
- [ ] Container restart count stabilized
- [ ] Application responding to health checks
- [ ] No new error events

---

## Escalation

If issue persists after 15 minutes:

1. Check for cluster-wide issues
2. Check node health
3. Review recent deployments/changes
4. Engage on-call engineer

---

## Post-Incident

- [ ] Document root cause
- [ ] Update monitoring/alerting if gap found
- [ ] Create ticket for permanent fix
- [ ] Update this runbook if needed

---

*Last Updated: 2026-01-20*
