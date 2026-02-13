# Operational Runbook: {NAME}

## Overview

[High-level description of the service or component this runbook covers. What does it do, who maintains it, and when should someone consult this runbook?]

**Service/Component:** [Name of the service or component]
**Owner Team:** [Team responsible for this service]
**On-Call Rotation:** [Link to on-call schedule or rotation name]
**Criticality:** [P1 (business-critical) / P2 (high impact) / P3 (moderate) / P4 (low)]

### Quick Reference

| Item | Value |
|------|-------|
| Repository | [Link to repo] |
| Dashboard | [Link to monitoring dashboard] |
| Logs | [Link to log search, pre-filtered for this service] |
| CI/CD Pipeline | [Link to deployment pipeline] |
| Alerts Channel | [e.g., #team-alerts in Slack] |
| Escalation Contact | [Name, role, contact method] |

## Deployment

[Step-by-step deployment procedure. Write for someone performing this deployment for the first time.]

### Prerequisites

- [ ] [Access to deployment system (e.g., CI/CD pipeline, Kubernetes cluster)]
- [ ] [Required credentials or permissions]
- [ ] [Branch merged and CI passing]
- [ ] [Any feature flags configured]
- [ ] [Database migrations applied (if applicable)]

### Standard Deployment Steps

1. [Step 1: e.g., Verify CI pipeline is green on main branch]
2. [Step 2: e.g., Trigger deployment via `deploy.sh production` or CI button]
3. [Step 3: e.g., Monitor rolling deployment progress in dashboard]
4. [Step 4: e.g., Verify health checks pass on new instances]
5. [Step 5: e.g., Confirm metrics baseline restored (latency, error rate)]
6. [Step 6: e.g., Announce deployment completion in team channel]

### Deployment Validation

[How to verify a deployment succeeded.]

- [ ] Health endpoint returns 200: `curl https://service.example.com/health`
- [ ] Version endpoint shows expected version: `curl https://service.example.com/version`
- [ ] Error rate within normal range (< [X]%)
- [ ] Latency within normal range (p99 < [X]ms)
- [ ] No new error patterns in logs (check last 5 minutes)

### Canary / Staged Rollout (if applicable)

[If deployments roll out gradually, describe the stages.]

| Stage | Traffic % | Duration | Success Criteria |
|-------|-----------|----------|-----------------|
| [Canary] | [5%] | [10 min] | [No new errors, latency stable] |
| [Stage 1] | [25%] | [15 min] | [Error rate < 0.1%] |
| [Stage 2] | [50%] | [15 min] | [All metrics nominal] |
| [Full rollout] | [100%] | [--] | [Monitoring for 30 min post-deploy] |

## Monitoring

[What to monitor and how to interpret the signals.]

### Key Dashboards

| Dashboard | Purpose | When to Check |
|-----------|---------|---------------|
| [Service Overview] | [Request rate, errors, latency] | [Every deployment, during incidents] |
| [Infrastructure] | [CPU, memory, disk, network] | [During performance issues] |
| [Business Metrics] | [Revenue, user activity, conversions] | [During suspected impact events] |

### Health Signals

| Signal | Healthy Range | Warning | Critical |
|--------|--------------|---------|----------|
| [Error rate] | [< 0.1%] | [0.1% - 1%] | [> 1%] |
| [p99 Latency] | [< 200ms] | [200ms - 500ms] | [> 500ms] |
| [CPU Usage] | [< 60%] | [60% - 80%] | [> 80%] |
| [Memory Usage] | [< 70%] | [70% - 85%] | [> 85%] |
| [Request Rate] | [Baseline +/- 20%] | [> 50% deviation] | [Zero or 10x spike] |

### Log Queries

[Pre-built log queries for common investigation scenarios.]

| Scenario | Query | Where to Run |
|----------|-------|--------------|
| [Recent errors] | [e.g., `service=myapp level=ERROR last 15m`] | [Log platform link] |
| [Slow requests] | [e.g., `service=myapp duration_ms>500 last 1h`] | [Log platform link] |
| [Auth failures] | [e.g., `service=myapp status=401 OR status=403`] | [Log platform link] |
| [Specific user] | [e.g., `service=myapp user_id=X`] | [Log platform link] |

## Incident Response

[What to do when things go wrong. Organized by symptom for fast lookup.]

### Symptom: High Error Rate

**Detection:** Alert fires when error rate exceeds [X]% for [Y] minutes.

**Triage Steps:**
1. Check dashboard: [Link] -- Is the error rate still elevated?
2. Check recent deployments: Was anything deployed in the last 30 minutes?
3. Check error logs: `[query]` -- What errors are occurring?
4. Check dependencies: Are upstream/downstream services healthy?

**Common Causes:**
- **Recent deployment:** [Rollback, see Rollback section]
- **Dependency failure:** [Check dependency health, consider circuit breaker]
- **Bad data / input:** [Check for new traffic patterns, block offending source]
- **Resource exhaustion:** [Scale up, check for memory leaks]

### Symptom: High Latency

**Detection:** Alert fires when p99 latency exceeds [X]ms for [Y] minutes.

**Triage Steps:**
1. Check dashboard: [Link] -- Which endpoints are slow?
2. Check database: Are queries slow? Is connection pool exhausted?
3. Check external dependencies: Are API calls to other services timing out?
4. Check resource usage: CPU, memory, disk I/O -- any saturation?

**Common Causes:**
- **Database slow queries:** [Identify query, check for missing index, check for lock contention]
- **External service degradation:** [Check dependency dashboard, enable circuit breaker]
- **Resource saturation:** [Scale horizontally, investigate memory leak]
- **Traffic spike:** [Enable rate limiting, scale up, page additional support]

### Symptom: Service Unavailable

**Detection:** Alert fires when health checks fail or zero successful requests for [Y] minutes.

**Triage Steps:**
1. Check infrastructure: Are pods/instances running? `[kubectl get pods / equivalent]`
2. Check networking: Is load balancer healthy? Are DNS records correct?
3. Check dependencies: Is the database reachable? Are required services up?
4. Check logs: Any crash loops or OOM kills?

**Common Causes:**
- **Crash loop:** [Check logs for startup errors, recent config changes]
- **OOM kill:** [Increase memory limits, investigate leak]
- **Network partition:** [Check connectivity, DNS, load balancer health]
- **Configuration error:** [Review recent config changes, check environment variables]

## Rollback

[How to undo a bad deployment or change.]

### Automated Rollback (if available)

```bash
# [Command to trigger automated rollback, e.g.:]
# deploy.sh rollback production
# kubectl rollout undo deployment/myapp
# argocd app rollback myapp
```

### Manual Rollback Steps

1. [Step 1: Identify the last known good version/commit]
2. [Step 2: Trigger deployment of that version -- e.g., `deploy.sh production --version=X.Y.Z`]
3. [Step 3: Monitor rollback progress -- watch health checks and metrics]
4. [Step 4: Verify service restored to healthy state]
5. [Step 5: Announce rollback in team channel with reason]

### Rollback Validation

- [ ] Previous version deployed successfully
- [ ] Health checks passing
- [ ] Error rate returned to baseline
- [ ] No data corruption from partial migration
- [ ] Team notified of rollback and reason

### Database Rollback (if applicable)

[If the deployment included database changes, describe how to handle them.]

- **Forward-compatible migrations only:** [Migrations designed to work with both old and new code]
- **Rollback migration available:** [Run `migrate down` or equivalent]
- **Manual intervention required:** [Describe steps, who to contact]

## Escalation

[When and how to escalate beyond the immediate on-call responder.]

### Escalation Matrix

| Severity | Criteria | Response Time | Escalation Path |
|----------|----------|---------------|-----------------|
| [SEV-1] | [Complete service outage, data loss risk] | [15 min] | [On-call -> Team lead -> Engineering manager -> VP Eng] |
| [SEV-2] | [Significant degradation, >50% users affected] | [30 min] | [On-call -> Team lead -> Engineering manager] |
| [SEV-3] | [Partial degradation, <50% users affected] | [1 hour] | [On-call -> Team lead] |
| [SEV-4] | [Minor issue, workaround available] | [Next business day] | [On-call] |

### When to Escalate

Escalate immediately if:
- [ ] Service is completely down and you cannot identify the cause within 15 minutes
- [ ] Data loss is occurring or suspected
- [ ] The issue affects external customers or partners
- [ ] You need access or permissions you do not have
- [ ] The issue spans multiple services owned by different teams
- [ ] You are unsure whether to escalate (when in doubt, escalate)

### Escalation Contacts

| Role | Name | Contact | Availability |
|------|------|---------|-------------|
| [Primary On-Call] | [Name / rotation link] | [Phone, Slack, PagerDuty] | [24/7] |
| [Secondary On-Call] | [Name / rotation link] | [Phone, Slack, PagerDuty] | [24/7] |
| [Team Lead] | [Name] | [Contact method] | [Business hours + SEV-1/2] |
| [Engineering Manager] | [Name] | [Contact method] | [SEV-1 only] |
| [Infrastructure Team] | [Team name] | [Channel or contact] | [24/7] |
| [Database Team] | [Team name] | [Channel or contact] | [Business hours + SEV-1] |

### Post-Incident

After every SEV-1 or SEV-2 incident:
- [ ] Incident timeline documented
- [ ] Root cause identified
- [ ] Remediation actions assigned
- [ ] Runbook updated with lessons learned
- [ ] Post-mortem scheduled (blameless)

## Operational Checklist

- [ ] Deployment procedure documented and tested
- [ ] Monitoring dashboards created and accessible to on-call
- [ ] Alert rules configured with appropriate thresholds
- [ ] Rollback procedure tested in staging
- [ ] Escalation contacts current and reachable
- [ ] Log queries prepared for common scenarios
- [ ] On-call team briefed on this service
- [ ] Post-deployment validation steps defined

## N/A Sign-Off (If Not Applicable)

If this document is not applicable to the current ticket, complete this section instead:

**Status:** N/A
**Assessed:** {date}

### Assessment
{1-3 sentence justification}

### Re-evaluate If
{Condition that would make this document applicable}
