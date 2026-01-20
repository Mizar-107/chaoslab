# GameDay Runbook

> Step-by-step guide for executing a ChaosLab GameDay session.

## Overview

| Attribute | Value |
|-----------|-------|
| **Duration** | 90 minutes (recommended) |
| **Participants** | 2-5 engineers |
| **Frequency** | Monthly or after major deployments |

---

## Pre-GameDay Checklist

### 1 Week Before

- [ ] Schedule GameDay and invite participants
- [ ] Assign roles (Facilitator, Operator, Observer, Scribe)
- [ ] Review recent production incidents
- [ ] Select experiments based on areas of concern

### 1 Day Before

- [ ] Verify cluster is running: `kubectl get nodes`
- [ ] Verify MicroShop is deployed: `kubectl get pods -n microshop`
- [ ] Verify monitoring is working: Grafana dashboards accessible
- [ ] Run `./scripts/check-prerequisites.sh`
- [ ] Prepare video conferencing (if remote)

### Day Of (Before Start)

- [ ] Start screen recording for post-mortem
- [ ] Open Grafana dashboards (chaos-experiments, slo-overview)
- [ ] Open Chaos Mesh dashboard (port 2333)
- [ ] Start load generator: `python3 scripts/load-generator.py --profile chaos`
- [ ] Verify communication channel (Slack/Teams)

---

## Roles

| Role | Responsibilities |
|------|------------------|
| **Facilitator** | Keeps time, manages agenda, mediates discussions |
| **Operator** | Executes experiments, monitors systems |
| **Observer(s)** | Watch dashboards, document observations |
| **Scribe** | Records findings, actions, and learnings |

---

## Execution Timeline

### Phase 1: Kickoff (10 min)

```
0:00 - 0:05  | Welcome and agenda review
0:05 - 0:10  | Verify all systems operational
```

- Confirm all participants understand abort procedures
- Verify everyone has dashboard access
- State the hypothesis for each experiment

### Phase 2: Baseline (10 min)

```
0:10 - 0:20  | Collect steady-state metrics
```

Run:
```bash
./scripts/06-collect-baseline.sh
```

Document baseline values:
- Pod availability: _____%
- P95 latency: _____ms
- Error rate: _____%

### Phase 3: Experiments (45 min)

```
0:20 - 0:30  | EXP-001: Pod Kill
0:30 - 0:40  | EXP-002: Network Latency
0:40 - 0:50  | EXP-003: CPU Stress
0:50 - 1:00  | EXP-004: DNS Failure
1:00 - 1:05  | Buffer / catch-up
```

**For each experiment:**

1. State hypothesis aloud
2. Execute: `./scripts/experiments/run-exp-XXX.sh`
3. Observe impact on dashboards
4. Document: Did system behave as expected?
5. Wait for recovery before next experiment

### Phase 4: Recovery Verification (10 min)

```
1:05 - 1:15  | System stabilization
```

- Verify all pods healthy
- Check for any lingering alerts
- Compare current metrics to baseline

### Phase 5: Debrief (15 min)

```
1:15 - 1:30  | Discussion and action items
```

Discuss:
1. What surprised us?
2. What worked well?
3. What needs improvement?
4. Action items with owners

---

## Abort Procedures

### Immediate Abort (Critical Issue)

```bash
# Delete ALL chaos experiments
kubectl delete podchaos,networkchaos,stresschaos,dnschaos,workflow --all -n microshop

# Restart affected deployments
kubectl rollout restart deploy --all -n microshop
```

### Graceful Abort (Minor Issue)

```bash
# Delete specific experiment
kubectl delete -f experiments/exp-XXX-*.yaml

# Wait for recovery
kubectl get pods -n microshop -w
```

### When to Abort

- 🔴 **Immediate**: Node unresponsive, cluster instability
- 🟡 **Graceful**: Single service cascade failure
- 🟢 **Continue**: Expected degradation within hypothesis

---

## Post-GameDay

### Immediately After

1. Stop screen recording
2. Collect final metrics
3. Generate report: `./scripts/08-generate-report.sh`

### Within 24 Hours

1. Share recording and report with team
2. Create tickets for action items
3. Update runbooks based on findings

### Within 1 Week

1. Implement critical fixes
2. Schedule follow-up GameDay if needed
3. Update experiment library

---

## Debrief Template

Copy this template to your notes:

```markdown
# GameDay Debrief - [DATE]

## Participants
- Facilitator: 
- Operator: 
- Observers: 
- Scribe: 

## Experiments Executed
| Experiment | Hypothesis | Result | Surprise Level |
|------------|------------|--------|----------------|
| EXP-001 | | PASS/FAIL | Low/Med/High |
| EXP-002 | | PASS/FAIL | Low/Med/High |
| EXP-003 | | PASS/FAIL | Low/Med/High |
| EXP-004 | | PASS/FAIL | Low/Med/High |

## Key Observations
1. 
2. 
3. 

## Action Items
| Action | Owner | Due Date |
|--------|-------|----------|
| | | |
| | | |

## Improvements for Next GameDay
- 
- 
```

---

## Quick Reference

### Port Forwards

```bash
# Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Prometheus  
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Chaos Dashboard
kubectl port-forward -n chaos-mesh svc/chaos-dashboard 2333:2333
```

### Automated GameDay

```bash
# Full automated session
./scripts/09-run-gameday.sh

# Dry run (preview)
./scripts/09-run-gameday.sh --dry-run

# Single phase
./scripts/09-run-gameday.sh --phase chaos
```

---

*Last Updated: 2026-01-20*
