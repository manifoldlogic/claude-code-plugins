# SDD Loop Controller Examples

Autonomous workflow controller for multi-repository SDD development.

## Introduction and Overview

The SDD Loop Controller ("Ralph Wiggum Loop") is an autonomous workflow controller that continuously:

1. **Polls** `master-status-board.sh` for the next recommended task
2. **Executes** the task via Claude Code CLI (`/sdd:do-task`)
3. **Repeats** until no more work remains or safety limits are reached

The controller is designed for hands-off, overnight, or CI/CD operation where you want to process multiple tasks automatically with appropriate safety guardrails.

### When to Use the Loop Controller

- **Overnight batch processing** - Queue up work and let it run unattended
- **CI/CD pipelines** - Automated task execution as part of deployment workflows
- **Multi-ticket processing** - Execute tasks across multiple tickets and repos
- **Phase-limited processing** - Complete specific phases with stop_at_phase boundaries

### Key Features

- **Safety limits** - Max iterations and consecutive error tracking prevent runaway loops
- **Phase boundaries** - Stop automatically at phase boundaries for review
- **Dry-run mode** - Preview what would happen without executing
- **Cross-repo support** - Works across multiple repositories in a workspace
- **Signal handling** - Graceful shutdown on SIGINT/SIGTERM

## Basic Usage

### Run Against Default Workspace

```bash
# Run loop against /workspace/repos/ (default)
./sdd-loop.sh

# Specify workspace explicitly
./sdd-loop.sh /workspace/repos/
```

### Typical Output

```
[2026-01-15 10:30:00] [INFO] SDD Loop Controller v1.0.0 starting...
[2026-01-15 10:30:00] [INFO] Workspace: /workspace/repos/
[2026-01-15 10:30:00] [INFO] Safety limits: max_iterations=50, max_errors=3, timeout=3600s
[2026-01-15 10:30:00] [INFO] Iteration 1/50: polling for next task
[2026-01-15 10:30:01] [INFO] Action: execute task MYTICKET.1001 (ticket: MYTICKET)
[2026-01-15 10:30:01] [INFO] Executing task: MYTICKET.1001 (repo: /workspace/repos/my-project, timeout: 3600s)
... (Claude Code executes the task) ...
[2026-01-15 10:35:23] [INFO] Task completed successfully: MYTICKET.1001 (exit code: 0)
[2026-01-15 10:35:23] [INFO] Iteration 2/50: polling for next task
...
```

## Dry-Run Mode for Testing

Dry-run mode previews what the loop would do without actually executing Claude Code. This is essential for:

- Testing configuration before a real run
- Verifying which tasks would be selected
- Understanding the recommendation logic

### Basic Dry-Run

```bash
# Preview actions without executing
./sdd-loop.sh --dry-run /workspace/repos/
```

### Dry-Run Output

```
[2026-01-15 10:30:00] [INFO] SDD Loop Controller v1.0.0 starting...
[2026-01-15 10:30:00] [INFO] Workspace: /workspace/repos/
[2026-01-15 10:30:00] [INFO] Running in DRY-RUN mode - no tasks will be executed
[2026-01-15 10:30:00] [INFO] Safety limits: max_iterations=50, max_errors=3, timeout=3600s
[2026-01-15 10:30:00] [INFO] Iteration 1/50: polling for next task
[2026-01-15 10:30:01] [INFO] Action: execute task MYTICKET.1001 (ticket: MYTICKET)
[2026-01-15 10:30:01] [INFO] [DRY-RUN] Would execute task: MYTICKET.1001
[2026-01-15 10:30:01] [INFO] [DRY-RUN] Command: SDD_ROOT_DIR="/workspace/repos/my-project/_SDD" claude --dangerously-skip-permissions -p "/sdd:do-task MYTICKET.1001"
[2026-01-15 10:30:01] [INFO] [DRY-RUN] Working directory: /workspace/repos/my-project
```

### Dry-Run via Environment Variable

```bash
# Set dry-run mode via environment
export SDD_LOOP_DRY_RUN=true
./sdd-loop.sh /workspace/repos/
```

### Limited Dry-Run Iterations

```bash
# Preview just the first 3 tasks that would be executed
./sdd-loop.sh --dry-run --max-iterations 3 /workspace/repos/
```

## Configuring Safety Limits

Safety limits prevent runaway loops and excessive resource consumption.

### Maximum Iterations

```bash
# Process at most 10 tasks then stop
./sdd-loop.sh --max-iterations 10 /workspace/repos/
```

When the limit is reached, the loop exits with code 1:

```
[2026-01-15 12:00:00] [WARN] Reached maximum iterations (10)
[2026-01-15 12:00:00] [INFO] Loop stopped: safety limit reached after 10 iteration(s)
```

### Maximum Consecutive Errors

```bash
# Stop after 5 consecutive task failures
./sdd-loop.sh --max-errors 5 /workspace/repos/
```

The error counter **resets to zero** after each successful task. This allows the loop to continue despite occasional failures while stopping if something is systematically broken.

### Task Timeout

```bash
# Allow 2 hours per task (7200 seconds)
./sdd-loop.sh --timeout 7200 /workspace/repos/
```

When a task times out:

```
[2026-01-15 12:30:00] [ERROR] Task timed out after 7200 seconds: MYTICKET.2001
[2026-01-15 12:30:00] [WARN] Task failed (exit code: 124), consecutive errors: 1/3
```

### Combined Safety Configuration

```bash
# Conservative limits for testing
./sdd-loop.sh --max-iterations 5 --max-errors 2 --timeout 1800 /workspace/repos/

# Aggressive limits for production batch jobs
./sdd-loop.sh --max-iterations 100 --max-errors 10 --timeout 7200 /workspace/repos/
```

## Using Phase Boundaries (Autogate Integration)

Phase boundaries allow you to stop the loop automatically after completing specific phases, enabling manual review before proceeding.

### Setting a Phase Boundary

Create or update `.autogate.json` in the ticket directory:

```bash
# Stop after completing Phase 1 tasks (tasks 1001-1999)
cd /workspace/repos/my-project/_SDD/tickets/MYTICKET_feature/
echo '{"ready": true, "agent_ready": true, "stop_at_phase": 1}' > .autogate.json
```

### Phase Boundary Behavior

When a Phase 1 task completes and `stop_at_phase: 1` is set:

```
[2026-01-15 11:00:00] [INFO] Task completed successfully: MYTICKET.1003 (exit code: 0)
[2026-01-15 11:00:00] [INFO] Phase boundary reached (stop_at_phase: 1)
[2026-01-15 11:00:00] [INFO] Loop stopped: phase 1 limit reached after 3 iteration(s)
```

The loop exits with code 0 (success) when a phase boundary is reached.

### Phase Numbering Convention

Tasks are numbered with phases embedded in the ID:

| Task ID | Phase |
|---------|-------|
| TICKET.1001-1999 | Phase 1 (Foundation/Setup) |
| TICKET.2001-2999 | Phase 2 (Implementation) |
| TICKET.3001-3999 | Phase 3 (Testing/Documentation) |
| TICKET.4001-4999 | Phase 4 (Integration/Deployment) |

### Example: Phased Development Workflow

```bash
# 1. Enable agent processing with Phase 1 boundary
cd /workspace/repos/my-project/_SDD/tickets/FEATURE_auth/
echo '{"ready": true, "agent_ready": true, "stop_at_phase": 1}' > .autogate.json

# 2. Run loop - will complete Phase 1 and stop
./sdd-loop.sh /workspace/repos/

# 3. Review Phase 1 work manually
# ...

# 4. Update gate to allow Phase 2
echo '{"ready": true, "agent_ready": true, "stop_at_phase": 2}' > .autogate.json

# 5. Continue with Phase 2
./sdd-loop.sh /workspace/repos/
```

### Removing Phase Boundaries

```bash
# Remove phase limit (allow all phases)
echo '{"ready": true, "agent_ready": true}' > .autogate.json

# Or delete the file entirely to use defaults
rm .autogate.json
```

## Environment Variable Configuration

All options can be configured via environment variables, which is useful for:

- CI/CD pipelines where command-line arguments are harder to manage
- Consistent configuration across multiple runs
- Shell profile defaults

### Available Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SDD_LOOP_WORKSPACE_ROOT` | `/workspace/repos/` | Workspace root directory |
| `SDD_LOOP_MAX_ITERATIONS` | `50` | Maximum task iterations |
| `SDD_LOOP_MAX_ERRORS` | `3` | Maximum consecutive errors |
| `SDD_LOOP_TIMEOUT` | `3600` | Task timeout in seconds |
| `SDD_LOOP_POLL_INTERVAL` | `5` | Poll interval in seconds |
| `SDD_LOOP_DRY_RUN` | `false` | Enable dry-run mode |
| `SDD_LOOP_VERBOSE` | `false` | Enable verbose output |
| `SDD_LOOP_QUIET` | `false` | Enable quiet mode |
| `SDD_LOOP_DEBUG` | `false` | Enable debug output |

### Example: Environment-Based Configuration

```bash
# Configure via environment
export SDD_LOOP_MAX_ITERATIONS=100
export SDD_LOOP_TIMEOUT=7200
export SDD_LOOP_VERBOSE=true

# Run with environment configuration
./sdd-loop.sh /workspace/repos/
```

### Example: CI/CD Pipeline Environment

```bash
# In CI/CD script
export SDD_LOOP_MAX_ITERATIONS=50
export SDD_LOOP_MAX_ERRORS=5
export SDD_LOOP_TIMEOUT=3600
export SDD_LOOP_QUIET=true

# Run loop
./sdd-loop.sh /workspace/repos/ || {
    echo "Loop failed"
    exit 1
}
```

### Configuration Priority

Configuration values are resolved in this order (later overrides earlier):

1. **Built-in defaults** - Hardcoded in script
2. **Environment variables** - `SDD_LOOP_*` variables
3. **Command-line arguments** - `--max-iterations`, etc.

```bash
# Command-line overrides environment
export SDD_LOOP_MAX_ITERATIONS=100
./sdd-loop.sh --max-iterations 10 /workspace/repos/
# Result: max_iterations=10 (CLI wins)
```

## Integration with CI/CD

The loop controller is designed for CI/CD integration with appropriate exit codes and quiet mode.

### Basic CI/CD Integration

```bash
#!/bin/bash
# ci-sdd-loop.sh

set -e

# Run loop in quiet mode for cleaner logs
./sdd-loop.sh --quiet --max-iterations 50 /workspace/repos/ || {
    exit_code=$?
    case $exit_code in
        1) echo "ERROR: Loop failed (task error or limit reached)" ;;
        2) echo "ERROR: Invalid arguments" ;;
        130) echo "INFO: Loop interrupted by SIGINT" ;;
        143) echo "INFO: Loop terminated by SIGTERM" ;;
        *) echo "ERROR: Unknown exit code: $exit_code" ;;
    esac
    exit $exit_code
}

echo "SUCCESS: All work completed"
```

### GitHub Actions Example

```yaml
# .github/workflows/sdd-loop.yml
name: SDD Loop Processing

on:
  workflow_dispatch:
    inputs:
      max_iterations:
        description: 'Maximum iterations'
        default: '50'
      dry_run:
        description: 'Dry run mode'
        type: boolean
        default: false

jobs:
  process-tasks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y jq
          npm install -g @anthropic/claude-code

      - name: Run SDD Loop
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: |
          ./plugins/sdd/skills/project-workflow/scripts/sdd-loop.sh \
            --quiet \
            --max-iterations ${{ inputs.max_iterations }} \
            ${{ inputs.dry_run && '--dry-run' || '' }} \
            /workspace/repos/
```

### Jenkins Pipeline Example

```groovy
pipeline {
    agent any

    environment {
        SDD_LOOP_MAX_ITERATIONS = '50'
        SDD_LOOP_TIMEOUT = '3600'
        SDD_LOOP_QUIET = 'true'
    }

    stages {
        stage('SDD Loop') {
            steps {
                sh '''
                    ./sdd-loop.sh /workspace/repos/ || exit_code=$?
                    if [ "${exit_code:-0}" -ne 0 ]; then
                        echo "Loop exited with code: $exit_code"
                        exit $exit_code
                    fi
                '''
            }
        }
    }

    post {
        failure {
            echo 'SDD Loop failed - check task execution logs'
        }
    }
}
```

## Troubleshooting Common Issues

### Loop Stops Immediately

**Symptom:** Loop completes after first iteration with "No more work available"

**Causes and Solutions:**

1. **No agent-ready tickets**
   ```bash
   # Check if any tickets have agent_ready=true
   ./master-status-board.sh /workspace/repos/ | jq '[.repos[].tickets[] | select(.autogate.agent_ready == true)]'
   ```

2. **All tasks already completed**
   ```bash
   # Check task status
   ./master-status-board.sh /workspace/repos/ | jq '.summary'
   ```

3. **Action is "none"**
   ```bash
   # Check recommended action
   ./master-status-board.sh /workspace/repos/ | jq '.recommended_action'
   ```

**Fix:** Enable agent mode on the ticket:

```bash
# Enable agent_ready in .autogate.json
cd /path/to/_SDD/tickets/TICKET_name/
echo '{"ready": true, "agent_ready": true}' > .autogate.json
```

### Task Times Out

**Symptom:** Task fails with exit code 124

```
[ERROR] Task timed out after 3600 seconds: MYTICKET.2001
```

**Solutions:**

1. **Increase timeout:**
   ```bash
   ./sdd-loop.sh --timeout 7200 /workspace/repos/  # 2 hours
   ```

2. **Break down large tasks:** If tasks consistently timeout, they may be too large. Consider splitting into smaller tasks.

3. **Check task complexity:** Some tasks may be inherently long-running and need appropriate timeouts.

### Max Iterations Reached

**Symptom:** Loop exits with "Reached maximum iterations"

```
[WARN] Reached maximum iterations (50)
[INFO] Loop stopped: safety limit reached after 50 iteration(s)
```

**Solutions:**

1. **Increase limit if intentional:**
   ```bash
   ./sdd-loop.sh --max-iterations 100 /workspace/repos/
   ```

2. **Check for stuck tasks:** If the same task is being retried repeatedly:
   ```bash
   # Check which task is being recommended
   ./master-status-board.sh /workspace/repos/ | jq '.recommended_action'
   ```

3. **Review task completion:** Ensure tasks are being marked as complete properly.

### Claude Not Found

**Symptom:** Error "claude CLI not found"

```
[ERROR] claude CLI not found. Install Claude Code from https://claude.ai/download
```

**Solution:** Install Claude Code CLI:

```bash
npm install -g @anthropic/claude-code
```

### Permission Denied

**Symptom:** Error "Permission denied" when running the script

**Solutions:**

1. **Make script executable:**
   ```bash
   chmod +x sdd-loop.sh
   ```

2. **Run with bash explicitly:**
   ```bash
   bash sdd-loop.sh /workspace/repos/
   ```

### jq Not Found

**Symptom:** Error "jq not found"

```
[ERROR] jq not found. Install with: apt-get install jq (Debian/Ubuntu) or brew install jq (macOS)
```

**Solution:** Install jq:

```bash
# Debian/Ubuntu
sudo apt-get install jq

# macOS
brew install jq

# Alpine
apk add jq
```

### Invalid JSON from Status Board

**Symptom:** Error "master-status-board.sh returned invalid JSON"

**Solutions:**

1. **Test status board directly:**
   ```bash
   ./master-status-board.sh /workspace/repos/ | jq .
   ```

2. **Run with debug mode:**
   ```bash
   ./sdd-loop.sh --debug /workspace/repos/
   ```

3. **Check for stderr contamination:** Ensure no other output is mixed with JSON.

## Advanced Patterns

### Parallel Multi-Workspace Processing

Run separate loops for different workspaces:

```bash
#!/bin/bash
# parallel-loops.sh

# Run loops in parallel for different workspaces
./sdd-loop.sh --quiet /workspace/repos/project-a/ &
PID_A=$!

./sdd-loop.sh --quiet /workspace/repos/project-b/ &
PID_B=$!

# Wait for both to complete
wait $PID_A
EXIT_A=$?

wait $PID_B
EXIT_B=$?

echo "Project A exit code: $EXIT_A"
echo "Project B exit code: $EXIT_B"
```

### Scheduled Batch Processing

Use cron or systemd timers for scheduled execution:

```bash
# crontab entry: Run every night at 2 AM
0 2 * * * /path/to/sdd-loop.sh --quiet --max-iterations 100 /workspace/repos/ >> /var/log/sdd-loop.log 2>&1
```

### Conditional Phase Processing

Process specific phases based on conditions:

```bash
#!/bin/bash
# phased-processing.sh

TICKET_DIR="/workspace/repos/project/_SDD/tickets/FEATURE_auth"

# Phase 1: Foundation
echo '{"ready": true, "agent_ready": true, "stop_at_phase": 1}' > "$TICKET_DIR/.autogate.json"
./sdd-loop.sh /workspace/repos/

# Run tests after Phase 1
npm test || {
    echo "Tests failed after Phase 1"
    exit 1
}

# Phase 2: Implementation
echo '{"ready": true, "agent_ready": true, "stop_at_phase": 2}' > "$TICKET_DIR/.autogate.json"
./sdd-loop.sh /workspace/repos/

# Run integration tests after Phase 2
npm run test:integration || {
    echo "Integration tests failed after Phase 2"
    exit 1
}

# Phase 3+: Complete remaining work
echo '{"ready": true, "agent_ready": true}' > "$TICKET_DIR/.autogate.json"
./sdd-loop.sh /workspace/repos/
```

### Monitoring and Alerting

```bash
#!/bin/bash
# monitored-loop.sh

LOG_FILE="/var/log/sdd-loop-$(date +%Y%m%d).log"

./sdd-loop.sh --verbose /workspace/repos/ 2>&1 | tee "$LOG_FILE"
EXIT_CODE=${PIPESTATUS[0]}

if [ $EXIT_CODE -ne 0 ]; then
    # Send alert (example: Slack webhook)
    curl -X POST -H 'Content-type: application/json' \
        --data "{\"text\":\"SDD Loop failed with exit code $EXIT_CODE\"}" \
        "$SLACK_WEBHOOK_URL"
fi

exit $EXIT_CODE
```

### Pre-Flight Checks

Validate environment before running:

```bash
#!/bin/bash
# preflight-loop.sh

# Check dependencies
command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 1; }
command -v claude >/dev/null 2>&1 || { echo "claude required"; exit 1; }
command -v timeout >/dev/null 2>&1 || { echo "timeout required"; exit 1; }

# Verify workspace
WORKSPACE="/workspace/repos/"
if [ ! -d "$WORKSPACE" ]; then
    echo "Workspace not found: $WORKSPACE"
    exit 1
fi

# Check for SDD directories
SDD_COUNT=$(find "$WORKSPACE" -maxdepth 2 -type d -name "_SDD" | wc -l)
if [ "$SDD_COUNT" -eq 0 ]; then
    echo "No _SDD directories found in workspace"
    exit 1
fi

echo "Pre-flight checks passed. Found $SDD_COUNT SDD directories."

# Run the loop
./sdd-loop.sh "$WORKSPACE"
```

## Exit Codes Reference

| Code | Meaning | Action |
|------|---------|--------|
| 0 | Success - all work completed | No action needed |
| 1 | Error - task failure, limits reached, or dependency error | Check logs, investigate failure |
| 2 | Usage error - invalid arguments | Fix command-line arguments |
| 130 | Interrupted by SIGINT (Ctrl+C) | Expected on manual interrupt |
| 143 | Terminated by SIGTERM | Expected on system shutdown |

## Related Documentation

- [SDD Plugin README](../../../README.md) - Full plugin documentation
- [Master Status Board Examples](./master-status-board-examples.md) - Status board usage
- [Workflow Overview](../references/workflow-overview.md) - SDD workflow patterns
- [Autogate Configuration](../../../README.md#work-gates) - `.autogate.json` schema
