# Migration Plan: {NAME}

## Overview

[High-level description of the migration. What is changing, why, and what is the expected impact? Summarize the transition from current state to target state in 2-3 sentences.]

**Migration Type:** [Data schema / API version / Infrastructure / Configuration / Platform / Other]
**Estimated Risk Level:** [Low / Medium / High]
**Backward Compatibility Required:** [Yes / No -- if yes, for how long?]

## Current State

[Describe the system as it exists today. Include enough detail for someone unfamiliar with the system to understand what is changing and why.]

### Data Model / Schema

[Current schema, data structures, or configuration format. Include concrete examples.]

```
[Current schema or structure -- e.g., database table definition, API shape, config format]
```

### Consumers / Dependencies

[Who or what depends on the current state?]

| Consumer | Dependency Type | Impact of Change |
|----------|----------------|------------------|
| [e.g., Frontend app v2.1] | [Reads field X] | [Must be updated before migration] |
| [e.g., Analytics pipeline] | [Queries table Y] | [Tolerant -- uses SELECT *] |
| [e.g., External partner API] | [Expects response format Z] | [Breaking -- requires coordination] |

### Current Volume / Scale

- **Data volume:** [e.g., 2.3M rows, 15GB, 500K daily events]
- **Traffic pattern:** [e.g., 200 req/s average, 800 req/s peak]
- **Growth rate:** [e.g., ~10% month-over-month]

## Target State

[Describe the desired end state after migration is complete.]

### Data Model / Schema

```
[Target schema or structure]
```

### Key Differences

| Aspect | Current | Target | Migration Action |
|--------|---------|--------|-----------------|
| [e.g., User ID field] | [Integer, `user_id`] | [UUID, `user_uuid`] | [Add new column, backfill, switch reads] |
| [e.g., Config format] | [YAML v1] | [JSON v2] | [Transform and validate] |
| [e.g., API endpoint] | [`/api/v1/users`] | [`/api/v2/users`] | [Dual-serve during transition] |

## Migration Steps

[Ordered steps to execute the migration. Each step should be independently deployable and reversible where possible.]

### Pre-Migration

- [ ] [Backup current data / take snapshot]
- [ ] [Notify affected consumers / teams]
- [ ] [Verify rollback procedure works in staging]
- [ ] [Set up monitoring for migration progress]
- [ ] [Feature flag created and tested: `migration_xxx_enabled`]

### Phase 1: Prepare (Non-Breaking)

**Objective:** [Set up target state alongside current state without disrupting existing behavior]

1. [Step 1: e.g., Add new columns/tables with default values]
2. [Step 2: e.g., Deploy dual-write code (writes to both old and new)]
3. [Step 3: e.g., Verify dual-write correctness in staging]

**Validation:** [How to verify this phase succeeded]
**Rollback:** [How to undo this phase -- should be trivial]

### Phase 2: Migrate (Transition)

**Objective:** [Move data and/or traffic from old to new]

1. [Step 1: e.g., Backfill historical data to new schema]
2. [Step 2: e.g., Switch reads to new source (behind feature flag)]
3. [Step 3: e.g., Monitor error rates and performance]

**Validation:** [How to verify data integrity and correctness]
**Rollback:** [How to undo -- switch reads back to old source]

### Phase 3: Complete (Cleanup)

**Objective:** [Remove old state and dual-write code]

1. [Step 1: e.g., Remove old write path]
2. [Step 2: e.g., Drop old columns/tables (after bake period)]
3. [Step 3: e.g., Remove feature flags]

**Validation:** [How to verify cleanup is complete]
**Rollback:** [Typically not possible -- ensure Phase 2 is fully validated first]

**Bake Period:** [How long to wait between Phase 2 completion and Phase 3 cleanup, e.g., 1 week, 1 sprint]

## Rollback Strategy

[Detailed rollback plan. Every migration should have a clear "undo" path.]

### Rollback Triggers

[What conditions trigger a rollback decision?]

- [e.g., Error rate exceeds 1% for 5 minutes post-migration]
- [e.g., Data inconsistency detected between old and new]
- [e.g., Consumer reports failures related to migration]

### Rollback Procedure

1. [Step 1: e.g., Flip feature flag back to old path]
2. [Step 2: e.g., Verify traffic routing to old state]
3. [Step 3: e.g., Notify consumers of rollback]
4. [Step 4: e.g., Investigate root cause before retry]

### Rollback Limitations

[What cannot be easily rolled back? Be honest about risks.]

- [e.g., Destructive schema changes (DROP COLUMN) cannot be undone]
- [e.g., Data written only to new format during migration window]
- [e.g., External consumers who already adopted new API version]

### Point of No Return

[Is there a point after which rollback becomes impractical? When and why?]

- [e.g., After Phase 3 cleanup drops old tables, rollback requires restore from backup]
- [e.g., After external consumers switch to v2, rolling back v2 breaks their integrations]

## Risks

[What could go wrong during migration?]

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| [e.g., Data loss during backfill] | Low | High | [Take pre-migration backup, verify row counts] |
| [e.g., Downtime during schema change] | Medium | High | [Use online DDL, test on staging first] |
| [e.g., Consumer not updated in time] | Medium | Medium | [Backward-compatible transition period] |
| [e.g., Performance degradation during dual-write] | Low | Medium | [Monitor latency, scale if needed] |

## Testing

[How will the migration be tested before production execution?]

### Pre-Migration Testing

- [ ] Migration script tested on copy of production data
- [ ] Rollback procedure tested end-to-end
- [ ] Consumer compatibility verified with new schema/API
- [ ] Performance tested under production-like load
- [ ] Data integrity checks defined and automated

### During Migration

- [ ] Progress monitoring in place (% complete, rows migrated)
- [ ] Error rate monitoring active
- [ ] Data consistency checks running continuously
- [ ] Consumer health dashboards visible

### Post-Migration Validation

- [ ] Data integrity verified (row counts, checksums, spot checks)
- [ ] All consumers confirmed healthy
- [ ] Performance within expected bounds
- [ ] No data loss detected
- [ ] Rollback procedure remains viable (during bake period)

## Communication Plan

| When | Who | What |
|------|-----|------|
| [Pre-migration] | [Affected teams] | [Migration schedule, expected impact, action items] |
| [During migration] | [On-call, stakeholders] | [Progress updates, any issues] |
| [Post-migration] | [All consumers] | [Completion confirmation, new endpoints/schemas] |

## N/A Sign-Off (If Not Applicable)

If this document is not applicable to the current ticket, complete this section instead:

**Status:** N/A
**Assessed:** {date}

### Assessment
{1-3 sentence justification}

### Re-evaluate If
{Condition that would make this document applicable}
