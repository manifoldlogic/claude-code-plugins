# Observability Plan: {NAME}

## Overview

[High-level description of the observability needs for this ticket. What systems, services, or components need production visibility? What questions should operators be able to answer by looking at logs, metrics, and traces?]

**Observability Goals:**
- [Goal 1: e.g., "Detect API latency degradation within 2 minutes"]
- [Goal 2: e.g., "Trace requests end-to-end across service boundaries"]
- [Goal 3: e.g., "Identify root cause of failures without SSH access"]

## Logging Strategy

[What should be logged, at what level, and in what format? Logs are the most basic observability signal -- they must be structured, searchable, and actionable.]

### Log Levels

| Level | Usage | Example |
|-------|-------|---------|
| ERROR | Failures requiring attention | `Failed to process payment: timeout after 30s` |
| WARN | Degraded behavior, not yet failing | `Cache miss rate above 50%, falling back to DB` |
| INFO | Significant state changes | `Deployment started for version 2.3.1` |
| DEBUG | Diagnostic detail (off in production) | `Request payload: {sanitized_fields}` |

### Structured Fields

[What fields should every log entry include for searchability?]

- `service`: [Service name]
- `request_id`: [Correlation ID for request tracing]
- `user_id`: [If applicable, for user-scoped debugging]
- `operation`: [What action is being performed]
- `duration_ms`: [For performance-relevant operations]
- [Additional field]: [Purpose]

### Sensitive Data

[What data must NEVER appear in logs?]

- [ ] No credentials, tokens, or API keys logged
- [ ] No PII (emails, names, addresses) in plain text
- [ ] No full request/response bodies containing user data
- [ ] Sanitization approach: [Describe how sensitive fields are masked]

### Log Retention

- **Hot storage (searchable):** [Duration, e.g., 30 days]
- **Cold storage (archived):** [Duration, e.g., 1 year]
- **Log volume estimate:** [Approximate volume, e.g., ~500 MB/day]

## Metrics

[What numeric measurements should be collected to understand system health and behavior?]

### Key Metrics

| Metric | Type | Description | Labels |
|--------|------|-------------|--------|
| [e.g., `api_request_duration_seconds`] | Histogram | [What it measures] | `method`, `endpoint`, `status` |
| [e.g., `api_request_total`] | Counter | [What it measures] | `method`, `endpoint`, `status` |
| [e.g., `active_connections`] | Gauge | [What it measures] | `service` |
| [e.g., `queue_depth`] | Gauge | [What it measures] | `queue_name` |

### RED Metrics (Request-Driven Services)

If this ticket involves a request-driven service, define:

- **Rate:** [Requests per second metric name and labels]
- **Errors:** [Error rate metric name and how errors are classified]
- **Duration:** [Latency metric name and percentiles to track: p50, p90, p99]

### USE Metrics (Resource-Driven Components)

If this ticket involves infrastructure or resource management, define:

- **Utilization:** [Resource usage as percentage, e.g., CPU, memory, disk]
- **Saturation:** [Queue depth, wait times, backpressure signals]
- **Errors:** [Resource errors, e.g., OOM kills, disk full, connection refused]

### Business Metrics

[What business-level metrics should be tracked?]

- [e.g., `orders_processed_total` -- tracks successful order completions]
- [e.g., `user_signups_total` -- tracks new user registrations]
- [e.g., `feature_usage_total{feature="X"}` -- tracks adoption of new feature]

## Alerts

[What conditions should trigger alerts? Alerts should be actionable -- every alert should have a clear response procedure.]

### Critical Alerts (Page On-Call)

| Alert | Condition | Duration | Runbook |
|-------|-----------|----------|---------|
| [e.g., High Error Rate] | [e.g., Error rate > 5% for 5 minutes] | 5m | [Link to runbook section] |
| [e.g., Service Down] | [e.g., Zero successful requests for 2 minutes] | 2m | [Link to runbook section] |

### Warning Alerts (Notify Channel)

| Alert | Condition | Duration | Action |
|-------|-----------|----------|--------|
| [e.g., Elevated Latency] | [e.g., p99 latency > 500ms for 10 minutes] | 10m | [Investigation steps] |
| [e.g., Disk Usage High] | [e.g., Disk usage > 80%] | 15m | [Remediation steps] |

### Alert Design Principles

- [ ] Every alert has a documented response (no mystery alerts)
- [ ] Alerts fire on symptoms, not causes (e.g., "high error rate" not "pod restarted")
- [ ] Alert thresholds based on SLO/SLA targets, not arbitrary values
- [ ] Sufficient duration window to avoid flapping (minimum 2-5 minutes)
- [ ] Clear severity classification (critical = pages, warning = async notification)

## Dashboards

[What dashboards should be created to visualize system health?]

### Service Overview Dashboard

**Purpose:** Single-pane view of service health for on-call engineers.

**Panels:**
- [e.g., Request rate (requests/second) over time]
- [e.g., Error rate (%) over time with SLO threshold line]
- [e.g., Latency percentiles (p50, p90, p99) over time]
- [e.g., Active instances / pod count]
- [e.g., Resource utilization (CPU, memory)]

### Debugging Dashboard

**Purpose:** Detailed view for investigating incidents.

**Panels:**
- [e.g., Error breakdown by type and endpoint]
- [e.g., Slow query log / slow request details]
- [e.g., Dependency health (upstream/downstream service status)]
- [e.g., Recent deployments overlay on error rate graph]

### Business Dashboard (if applicable)

**Purpose:** Business-facing metrics for stakeholders.

**Panels:**
- [e.g., Daily active users]
- [e.g., Feature adoption rate]
- [e.g., Revenue-impacting metric]

## Tracing

[How will requests be traced across service boundaries? Distributed tracing is essential for microservice architectures.]

### Trace Propagation

- **Trace context format:** [e.g., W3C TraceContext, B3, or custom]
- **Propagation method:** [e.g., HTTP headers, gRPC metadata]
- **Sampling strategy:** [e.g., 100% for errors, 10% for normal traffic]

### Key Spans

[What operations should produce trace spans?]

| Span Name | Service | Description |
|-----------|---------|-------------|
| [e.g., `http.request`] | [Service] | [Inbound HTTP request handling] |
| [e.g., `db.query`] | [Service] | [Database query execution] |
| [e.g., `cache.lookup`] | [Service] | [Cache read operation] |
| [e.g., `external.api_call`] | [Service] | [Outbound API call] |

### Span Attributes

[What attributes should spans carry for effective debugging?]

- `service.name`: [Service identifier]
- `service.version`: [Deployed version]
- `http.method`, `http.url`, `http.status_code`: [For HTTP spans]
- `db.system`, `db.statement`: [For database spans, with query sanitization]
- `error`: [Boolean flag for error spans]
- `error.message`: [Error description, sanitized]

### Trace-Log Correlation

- [ ] Trace ID included in all log entries
- [ ] Logs linkable from trace UI
- [ ] Error traces automatically correlated with error logs

## SLOs and Error Budgets (if applicable)

[If this service has Service Level Objectives, define them here.]

| SLO | Target | Measurement Window | Error Budget |
|-----|--------|--------------------|--------------|
| [e.g., Availability] | [e.g., 99.9%] | [e.g., 30 days rolling] | [e.g., 43.2 minutes/month] |
| [e.g., Latency (p99)] | [e.g., < 500ms] | [e.g., 30 days rolling] | [e.g., 0.1% of requests] |

## Implementation Checklist

- [ ] Structured logging configured with required fields
- [ ] Key metrics instrumented (RED or USE as appropriate)
- [ ] Alert rules created and tested
- [ ] Service overview dashboard created
- [ ] Tracing instrumented for key operations
- [ ] Trace-log correlation verified
- [ ] Sensitive data excluded from logs and traces
- [ ] Log retention policy configured
- [ ] Dashboard access shared with on-call team
- [ ] Alert routing configured (PagerDuty, Slack, etc.)

## N/A Sign-Off (If Not Applicable)

If this document is not applicable to the current ticket, complete this section instead:

**Status:** N/A
**Assessed:** {date}

### Assessment
{1-3 sentence justification}

### Re-evaluate If
{Condition that would make this document applicable}
