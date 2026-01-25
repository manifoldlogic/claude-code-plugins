# Safety Guidelines for SDD Loop Controller

Comprehensive safety documentation for autonomous SDD workflow execution.

**Version:** 1.0.0  |  **Last Updated:** 2026-01-25  |  **Applies To:** SDD Loop Controller v1.0.0+

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [When to Use Autonomous Execution](#2-when-to-use-autonomous-execution)
3. [Safety Features Overview](#3-safety-features-overview)
4. [Configuration for Safety](#4-configuration-for-safety)
5. [Risk Assessment Framework](#5-risk-assessment-framework)
6. [Operational Procedures](#6-operational-procedures)
7. [Emergency Procedures](#7-emergency-procedures)
8. [Audit and Monitoring](#8-audit-and-monitoring)

---

## 1. Introduction

### Safety Philosophy

The SDD Loop Controller is built on a core safety philosophy: **maximum autonomy with maximum visibility**. The system provides extensive warnings and monitoring without unnecessarily blocking legitimate work.

Three guiding principles:

1. **Advisory-Only Monitoring**: The circuit breaker warns about long-running loops but never automatically aborts productive work. Warnings at iterations 25 and 40 provide visibility without disruption.

2. **Targeted Blocking**: Only catastrophic, irreversible commands are blocked. The filter stops exactly three categories of system-destroying operations while allowing all legitimate development commands.

3. **Configurable Limits**: Safety limits (max iterations, max consecutive errors) are configurable to match your operational needs rather than imposing arbitrary restrictions.

This philosophy recognizes that autonomous execution is valuable precisely because it can work unattended. Overly aggressive safety measures that interrupt legitimate work would undermine this value.

### Why Autonomous Execution Matters

Autonomous loop execution enables:

- **Overnight Processing**: Queue work before leaving, return to completed tasks
- **CI/CD Integration**: Automated task execution in deployment pipelines
- **Multi-Ticket Batch Processing**: Process tasks across multiple tickets efficiently
- **Phased Development**: Complete specific phases, pause for review, then continue

### Implementation References

All safety features documented here are implemented in:
- **Loop Controller**: `plugins/sdd/skills/project-workflow/scripts/sdd-loop.sh`
- **Catastrophic Filter**: `plugins/sdd/hooks/block-catastrophic-commands.py`
- **Test Coverage**: 78 tests in `test-sdd-loop.sh` (see Phase 1 audit)

---

## 2. When to Use Autonomous Execution

### Appropriate Use Cases

**High-Volume Mechanical Work**
- Multiple small, well-defined tasks
- Tickets with clear, unambiguous requirements
- Established task sequences

**Overnight/Background Processing**
- Queuing work before end of day
- Running during off-hours
- Background execution during meetings

**CI/CD Pipeline Integration**
- Automated execution triggered by commits
- Scheduled batch processing
- Quality gates with phase boundaries

### When Manual Execution is Preferred

**High Complexity or Ambiguity**
- Tasks requiring judgment calls or design decisions
- Unclear or ambiguous requirements
- Novel patterns not covered by existing code

**Critical or Sensitive Operations**
- Modifying production configurations
- Changing authentication or security code
- Affecting data integrity or persistence

**Debugging or Learning**
- Investigating task failures
- Understanding Claude's approach
- Building familiarity with SDD workflow

### Decision Criteria Checklist

| Question | If "No" |
|----------|---------|
| Are all tasks well-defined with clear acceptance criteria? | Use manual execution |
| Is the ticket complexity S or M (not L or XL)? | Consider phased execution |
| Are affected files non-critical (not auth, config, data)? | Increase monitoring |
| Is the work easily reversible via git? | Reduce max-iterations |
| Has similar work succeeded autonomously before? | Start with dry-run |

---

## 3. Safety Features Overview

The SDD Loop Controller implements four independent safety mechanisms.

### 3.1 Circuit Breaker (Advisory Warnings)

**Purpose**: Provide visibility into long-running loops without disrupting legitimate work.

**Implementation**: `sdd-loop.sh`, lines 1080-1133 (`circuit_breaker_check` function)

**Thresholds**:

| Iteration | Warning Message |
|-----------|-----------------|
| 25 | "Long-running loop detected" |
| 40 | "Extended loop execution, approaching max_iterations" |

**Characteristics**:
- **Advisory only**: Warnings logged but execution continues
- **Non-blocking**: Never aborts automatically
- **Metrics integration**: Tracked in JSON metrics output

**Rationale**: Long-running loops may be legitimate (large backlogs). Automatic abortion would waste completed work.

**Test Coverage**: 7 dedicated tests verify exact thresholds and boundary conditions.

### 3.2 Catastrophic Command Filter

**Purpose**: Block irreversible, system-destroying commands.

**Implementation**: `plugins/sdd/hooks/block-catastrophic-commands.py` (59 lines)

**Blocked Patterns** (exactly 3 categories):

| Pattern | Description |
|---------|-------------|
| `rm -rf /` or `rm -rf /*` | Root filesystem deletion |
| `chmod -R 777 /` or `chmod -R 777 /*` | Root permission compromise |
| `dd` to `/dev/sd*` | Disk wiping |

**Pattern Implementation** (lines 26-35):
```python
CATASTROPHIC_PATTERNS = [
    (r"\brm\s+-rf\s+/+(\s|$|[)`'\"])", "rm -rf / (root filesystem deletion)"),
    (r"\brm\s+-rf\s+/\*", "rm -rf /* (root filesystem deletion)"),
    (r"\bchmod\s+-R\s+777\s+/+(\s|$|[)`'\"])", "chmod -R 777 / (root permission compromise)"),
    (r"\bchmod\s+-R\s+777\s+/\*", "chmod -R 777 /* (root permission compromise)"),
    (r"\bdd\b.*of=/dev/sd", "dd to block device (disk wipe)"),
]
```

**NOT Blocked**: `rm -rf /tmp/*`, `rm -rf /home/user/project/`, `chmod 755 file.sh`, `sudo apt install`

**Exit Codes**: 0 = allow, 2 = block

**Bypass Detection**: Patterns catch command substitution (`$(rm -rf /)`) and backtick forms.

### 3.3 Error Limits

**Purpose**: Prevent runaway failures and resource exhaustion.

**Implementation**: `sdd-loop.sh`, lines 1618-1732 (main loop)

| Limit | Default | Purpose | Exit Code |
|-------|---------|---------|-----------|
| Max Iterations | 50 | Prevents infinite loops | 1 |
| Max Consecutive Errors | 3 | Prevents repeated failure cycles | 1 |

**Key Behavior**: The consecutive error counter **resets to zero after each successful task**. This allows recovery from occasional failures while stopping systematic problems.

**Configuration**:
```bash
./sdd-loop.sh --max-iterations 100 --max-errors 5
```

**Test Coverage**: `test_max_iterations_limit`, `test_max_errors_limit`, `test_error_recovery`, plus 13 input validation tests.

### 3.4 Phase Boundaries

**Purpose**: Enable phased execution with manual review checkpoints.

**Implementation**: `sdd-loop.sh`, lines 734-835 (`check_phase_boundary` function)

**Configuration** (`.autogate.json`):
```json
{"ready": true, "agent_ready": true, "stop_at_phase": 2}
```

**Phase Detection** (from task ID):
- `TICKET.1001-1999` = Phase 1 (Foundation)
- `TICKET.2001-2999` = Phase 2 (Implementation)
- `TICKET.3001-3999` = Phase 3 (Testing)
- `TICKET.4001-4999` = Phase 4 (Integration)

**Behavior**: When a task completes and its phase >= `stop_at_phase`, the loop exits with code 0 (success).

**Error Handling**: Missing `.autogate.json` or missing `stop_at_phase` means no limit.

---

## 4. Configuration for Safety

### .autogate.json Schema

**Location**: `<SDD_ROOT>/tickets/<TICKET_ID>_<name>/.autogate.json`

```json
{
  "ready": true,          // Ticket ready for processing
  "agent_ready": true,    // Ready for autonomous execution
  "stop_at_phase": 1      // Optional: stop after this phase
}
```

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `ready` | Yes | false | Gate for any processing |
| `agent_ready` | Yes | false | Gate for autonomous execution |
| `stop_at_phase` | No | none | Phase (1-4) to stop at |

### Command-Line Options

```bash
# Safety limits
--max-iterations N    # Default: 50
--max-errors N        # Default: 3
--timeout SECONDS     # Default: 3600

# Operational modes
--dry-run            # Preview without executing
--verbose            # Detailed progress output
--quiet              # Errors only

# Output
--metrics-file FILE  # JSON metrics for monitoring
--log-format json    # Structured logging
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SDD_LOOP_MAX_ITERATIONS` | `50` | Maximum iterations |
| `SDD_LOOP_MAX_ERRORS` | `3` | Maximum consecutive errors |
| `SDD_LOOP_TIMEOUT` | `3600` | Task timeout (seconds) |
| `SDD_LOOP_DRY_RUN` | `false` | Enable dry-run mode |
| `SDD_LOOP_VERBOSE` | `false` | Enable verbose output |

**Priority**: Built-in defaults < Environment variables < Command-line arguments

### Recommended Configurations

**Conservative (Testing)**:
```bash
./sdd-loop.sh --dry-run --max-iterations 5 --verbose
```

**Standard (Daily Development)**:
```bash
./sdd-loop.sh --max-iterations 20 --max-errors 2 --verbose
```

**Production (Overnight/CI)**:
```bash
./sdd-loop.sh --max-iterations 100 --max-errors 5 --timeout 7200 \
  --metrics-file /var/log/sdd-metrics.json --log-format json
```

---

## 5. Risk Assessment Framework

### Risk Assessment Checklist

| Factor | Lower Risk | Higher Risk |
|--------|------------|-------------|
| **Size** | S or M ticket | L or XL ticket |
| **Files Affected** | < 10 files | > 20 files |
| **File Criticality** | Utility code, tests | Auth, config, data layer |
| **Complexity** | Mechanical changes | Design decisions needed |
| **Reversibility** | Easy git revert | Complex rollback |
| **Test Coverage** | > 80% coverage | < 50% coverage |
| **Prior Success** | Similar work succeeded | Novel patterns |

### Risk Scoring

| Risk Factor | Points |
|-------------|--------|
| XL ticket | +3 |
| L ticket | +2 |
| M ticket | +1 |
| > 20 files affected | +2 |
| Critical files (auth, config) | +3 |
| Design decisions required | +2 |
| Complex rollback needed | +2 |
| < 50% test coverage | +2 |
| Novel pattern | +1 |

| Total Score | Risk Level | Recommendation |
|-------------|------------|----------------|
| 0-2 | Low | Full autonomous execution |
| 3-5 | Medium | Autonomous with phase boundaries |
| 6-8 | High | Manual or tight limits |
| 9+ | Critical | Manual execution only |

### Example Assessments

**Low Risk (Score: 0)**: S ticket adding logging to 3 utility functions, similar work done before.
- Recommendation: Full autonomous execution

**Medium Risk (Score: 4)**: M ticket refactoring auth flow, 12 files including `auth/` directory.
- Recommendation: Autonomous with `stop_at_phase: 1`, then review

**High Risk (Score: 7)**: L ticket for new database migration, 25 files, design decisions needed.
- Recommendation: Manual execution or `--max-iterations 5` with close monitoring

### Pre-Execution Checklist

1. Review task list for clear acceptance criteria
2. Verify prerequisite tasks are complete
3. Run existing tests to establish baseline
4. Ensure clean git working tree
5. Configure appropriate limits and phase boundaries
6. Enable verbose logging for visibility

---

## 6. Operational Procedures

### Procedure 1: Pre-Execution Assessment

1. **Review ticket**: `cat _SDD/tickets/TICKET_name/ticket.md`
2. **Check tasks**: `ls _SDD/tickets/TICKET_name/tasks/`
3. **Verify clarity**: Each task should have summary, acceptance criteria, technical requirements
4. **Assess risk** using Section 5 framework
5. **Check status**: `./master-status-board.sh /workspace/repos/ | jq '.repos[].tickets'`
6. **Decide**: Full autonomous, phased, or manual execution

### Procedure 2: Starting Autonomous Execution

1. **Verify clean git state**:
   ```bash
   git status  # Commit or stash uncommitted changes
   ```

2. **Enable autonomous processing**:
   ```bash
   echo '{"ready": true, "agent_ready": true}' > _SDD/tickets/TICKET_name/.autogate.json
   ```

3. **Dry-run first** (always recommended):
   ```bash
   ./sdd-loop.sh --dry-run --max-iterations 5 /workspace/repos/
   ```

4. **Start execution**:
   ```bash
   ./sdd-loop.sh --verbose /workspace/repos/
   ```

### Procedure 3: Monitoring Execution

**Watch for**:
- `[INFO] Task completed successfully` - Progress indicator
- `[WARN]` - Attention needed
- `[ERROR]` - Failures

**Health Indicators**:

| Indicator | Healthy | Concerning |
|-----------|---------|------------|
| Task completion | Regular completions | Long gaps |
| Consecutive errors | 0-1 | Incrementing |
| Iteration progress | Steady | Stuck |

**JSON Monitoring**:
```bash
./sdd-loop.sh --log-format json 2>&1 | tee loop.log
tail -f loop.log | jq 'select(.level == "ERROR")'
```

### Procedure 4: Intervening

**Graceful Pause**: Press `Ctrl+C`, wait for shutdown message

**Mid-Run Adjustments**:
- Modify `.autogate.json` to change phase boundaries
- Or stop and restart with different parameters

**Disable Ticket**:
```bash
echo '{"ready": true, "agent_ready": false}' > .autogate.json
```

### Procedure 5: Error Recovery

**Single Failure**: Loop handles automatically, continues if under error limit

**Consecutive Error Limit Reached**:
1. Identify failing task: `./master-status-board.sh | jq '.recommended_action'`
2. Review task definition
3. Fix task, mark blocked, or complete manually
4. Resume: `./sdd-loop.sh --verbose /workspace/repos/`

### Procedure 6: Post-Execution Review

1. **Check exit status**: 0=success, 1=error, 130=interrupted
2. **Review metrics**: `cat /tmp/metrics.json | jq .`
3. **Check git changes**: `git status && git diff --stat HEAD~N`
4. **Run tests**: `npm test`
5. **Document learnings**: Problematic tasks? Configuration adjustments?

---

## 7. Emergency Procedures

### Emergency 1: Stopping a Runaway Loop

**Symptoms**: Loop running too long, same task retrying, unexpected resource use

**Option A - Graceful (Preferred)**:
```bash
Ctrl+C
# Wait for: "Received SIGINT, shutting down gracefully..."
```

**Option B - Force**:
```bash
ps aux | grep sdd-loop
kill -TERM <PID>
# If still running:
kill -KILL <PID>
```

**Option C - Kill Claude**:
```bash
ps aux | grep claude
kill -TERM <PID>
```

### Emergency 2: Post-Stop Assessment

1. **Check workspace**: `git status`
2. **Review progress**: Look for partial files, uncommitted changes
3. **Kill orphans**: `ps aux | grep claude` and terminate
4. **Review commits**: `git log --oneline -10`

### Emergency 3: Cleanup

**Discard All Changes**:
```bash
git checkout -- .
git clean -fd
```

**Selective Cleanup**:
```bash
git diff                      # Review
git checkout -- path/to/file  # Discard specific
```

**Revert Commits**:
```bash
git reset --soft HEAD~N  # Keep changes
git reset --hard HEAD~N  # Discard everything
```

**Create Recovery Branch**:
```bash
git checkout -b recovery-branch
git add -A && git commit -m "Recovery: interrupted execution"
git checkout main
```

### Emergency 4: Restart vs Abandon

**Restart When**: Transient issue, task fixed, configuration adjusted

**Restart Procedure**:
```bash
git status
./sdd-loop.sh --max-iterations 5 --verbose /workspace/repos/
```

**Abandon When**: Systematic failures, task definitions need rework

**Abandon Procedure**:
1. Clean up (Emergency 3)
2. Disable: `echo '{"ready": true, "agent_ready": false}' > .autogate.json`
3. Document and switch to manual

---

## 8. Audit and Monitoring

### Log Formats

**Text (default)**:
```
[2026-01-25 10:30:00] [INFO] SDD Loop Controller v1.0.0 starting...
```

**JSON** (for aggregation):
```bash
./sdd-loop.sh --log-format json 2>&1 | tee loop.json
```
```json
{"timestamp":"2026-01-25T10:30:00Z","level":"INFO","message":"Iteration 1/50","context":{"iteration":1}}
```

### Metrics Output

**Enable**:
```bash
./sdd-loop.sh --metrics-file /var/log/sdd-metrics.json
```

**Schema**:
```json
{
  "version": "1.0.0",
  "timestamp": "2026-01-25T14:30:00Z",
  "exit_code": 0,
  "iterations": 25,
  "tasks_completed": 23,
  "tasks_failed": 2,
  "duration_seconds": 14400,
  "configuration": {
    "max_iterations": 50,
    "max_errors": 3,
    "timeout": 3600
  },
  "circuit_breaker": {
    "warnings_logged": 1,
    "warning_iterations": [25]
  }
}
```

### Analysis Examples

```bash
# Success rate
jq '.tasks_completed / (.tasks_completed + .tasks_failed)' metrics.json

# Find failures
jq 'select(.tasks_failed > 0)' /var/log/sdd-metrics-*.json
```

### Monitoring Best Practices

1. **Always use metrics file in production**
2. **Use JSON logging for aggregation systems**
3. **Alert on**: Exit code != 0, tasks_failed > threshold, circuit_breaker warnings
4. **Review cadence**: Daily (failures), Weekly (warnings), Monthly (trends)

### Test Coverage Reference

**Test File**: `plugins/sdd/skills/project-workflow/scripts/test-sdd-loop.sh`

| Category | Tests |
|----------|-------|
| Circuit breaker | 7 tests (thresholds, boundaries, metrics) |
| Error limits | 4 tests (iterations, errors, recovery) |
| Phase boundaries | 3 tests (detection, error handling) |
| Path bounds | 6 tests (validation, traversal) |
| **Total** | 78 tests, 100% epic scenario coverage |

---

## Quick Reference

### Defaults

| Limit | Default |
|-------|---------|
| Max Iterations | 50 |
| Max Errors | 3 |
| Timeout | 3600s |

### Circuit Breaker

| Iteration | Warning |
|-----------|---------|
| 25 | "Long-running loop detected" |
| 40 | "Extended loop execution" |

### Catastrophic Commands (Blocked)

- `rm -rf /` or `rm -rf /*`
- `chmod -R 777 /` or `chmod -R 777 /*`
- `dd` to `/dev/sd*`

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Error |
| 2 | Usage error |
| 130 | SIGINT |
| 143 | SIGTERM |

### Emergency Commands

```bash
Ctrl+C                                    # Graceful stop
kill -TERM $(pgrep -f sdd-loop)           # Force stop
git checkout -- . && git clean -fd        # Discard changes
echo '{"ready":true,"agent_ready":false}' > .autogate.json  # Disable
```

---

## Related Documentation

- [SDD Loop Examples](../skills/project-workflow/scripts/sdd-loop-examples.md)
- [Troubleshooting Guide](./troubleshooting.md)
- [Phase 1 Test Coverage Audit](../../../_SDD/tickets/SDDLOOP-5_integration-testing-docs/deliverables/test-coverage-audit.md)

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-01-25 | Initial release |
