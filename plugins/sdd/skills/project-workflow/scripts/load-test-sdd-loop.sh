#!/usr/bin/env bash
#
# Load Test Harness for SDD Loop Controller (sdd-loop.sh)
# Tests long-term stability, resource usage, and performance characteristics
#
# Version: 1.0.0
#
# DESCRIPTION
#   Creates a controlled test environment with mock components to run
#   sdd-loop.sh for extended periods while monitoring resource usage.
#   Designed to detect memory leaks, file descriptor leaks, and
#   performance degradation over time.
#
# USAGE
#   load-test-sdd-loop.sh [options]
#
# OPTIONS
#   -h, --help              Show this help message
#   --duration SECONDS      Test duration (default: 86400 = 24 hours)
#   --workspace DIR         Test workspace directory (default: auto-generated)
#   --report FILE           Output report file (default: stdout)
#   --poll-interval SECS    Monitoring poll interval (default: 300 = 5 min)
#   --task-count N          Number of mock tasks per ticket (default: 100)
#   --failure-rate PCT      Mock task failure rate 0-100 (default: 10)
#   --task-duration-min MS  Min mock task duration ms (default: 500)
#   --task-duration-max MS  Max mock task duration ms (default: 3000)
#   --verbose               Enable verbose output
#   --dry-run               Show configuration without running
#
# EXIT CODES
#   0   - Test completed successfully
#   1   - Test failed or error occurred
#   2   - Usage error
#   130 - Interrupted (SIGINT)
#   143 - Terminated (SIGTERM)
#
# EXAMPLES
#   # Quick validation test (5 minutes)
#   load-test-sdd-loop.sh --duration 300
#
#   # Standard 24-hour test with report
#   load-test-sdd-loop.sh --report /tmp/load-test-report.md
#
#   # Custom configuration
#   load-test-sdd-loop.sh --duration 3600 --task-count 50 --failure-rate 5
#

set -euo pipefail

# =============================================================================
# Configuration Defaults
# =============================================================================

VERSION="1.0.0"

# Test duration in seconds (default: 24 hours)
DEFAULT_DURATION=86400

# Monitoring poll interval in seconds (default: 5 minutes)
DEFAULT_POLL_INTERVAL=300

# Number of mock tasks per ticket
DEFAULT_TASK_COUNT=100

# Mock task failure rate (percentage)
DEFAULT_FAILURE_RATE=10

# Mock task duration range in milliseconds
DEFAULT_TASK_DURATION_MIN=500
DEFAULT_TASK_DURATION_MAX=3000

# =============================================================================
# Global State
# =============================================================================

# Configuration
DURATION="$DEFAULT_DURATION"
WORKSPACE=""
REPORT_FILE=""
POLL_INTERVAL="$DEFAULT_POLL_INTERVAL"
TASK_COUNT="$DEFAULT_TASK_COUNT"
FAILURE_RATE="$DEFAULT_FAILURE_RATE"
TASK_DURATION_MIN="$DEFAULT_TASK_DURATION_MIN"
TASK_DURATION_MAX="$DEFAULT_TASK_DURATION_MAX"
VERBOSE=false
DRY_RUN=false

# Runtime state
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_START_TIME=""
SDD_LOOP_PID=""
MONITOR_PID=""
CLEANUP_DONE=false

# =============================================================================
# Logging Functions
# =============================================================================

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*" >&2
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [VERBOSE] $*"
    fi
}

# =============================================================================
# Help and Usage
# =============================================================================

show_usage() {
    cat << 'EOF'
Load Test Harness for SDD Loop Controller v1.0.0

DESCRIPTION
    Creates a controlled test environment with mock components to run
    sdd-loop.sh for extended periods while monitoring resource usage.

USAGE
    load-test-sdd-loop.sh [options]

OPTIONS
    -h, --help              Show this help message
    --duration SECONDS      Test duration (default: 86400 = 24 hours)
    --workspace DIR         Test workspace directory (default: auto-generated)
    --report FILE           Output report file (default: stdout)
    --poll-interval SECS    Monitoring poll interval (default: 300 = 5 min)
    --task-count N          Number of mock tasks per ticket (default: 100)
    --failure-rate PCT      Mock task failure rate 0-100 (default: 10)
    --task-duration-min MS  Min mock task duration ms (default: 500)
    --task-duration-max MS  Max mock task duration ms (default: 3000)
    --verbose               Enable verbose output
    --dry-run               Show configuration without running

EXIT CODES
    0   - Test completed successfully
    1   - Test failed or error occurred
    2   - Usage error
    130 - Interrupted (SIGINT)
    143 - Terminated (SIGTERM)

EXAMPLES
    # Quick validation test (5 minutes)
    load-test-sdd-loop.sh --duration 300

    # Standard 24-hour test
    load-test-sdd-loop.sh --duration 86400 --report load-test-report.md

    # Short test with custom task count
    load-test-sdd-loop.sh --duration 600 --task-count 20

MONITORING
    The test harness runs a background monitoring process that samples:
    - Memory usage (RSS, VSZ)
    - File descriptor count
    - CPU utilization
    - Iteration count

    Metrics are written to {workspace}/metrics.csv

MOCK COMPONENTS
    The test creates mock versions of:
    - master-status-board.sh: Cycles through tasks
    - claude: Simulates task execution with configurable duration/failure

EOF
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                exit 0
                ;;
            --duration)
                if [[ -z "${2:-}" ]]; then
                    log_error "--duration requires a value"
                    exit 2
                fi
                if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    log_error "--duration must be a positive integer"
                    exit 2
                fi
                DURATION="$2"
                shift 2
                ;;
            --workspace)
                if [[ -z "${2:-}" ]]; then
                    log_error "--workspace requires a value"
                    exit 2
                fi
                WORKSPACE="$2"
                shift 2
                ;;
            --report)
                if [[ -z "${2:-}" ]]; then
                    log_error "--report requires a value"
                    exit 2
                fi
                REPORT_FILE="$2"
                shift 2
                ;;
            --poll-interval)
                if [[ -z "${2:-}" ]]; then
                    log_error "--poll-interval requires a value"
                    exit 2
                fi
                if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    log_error "--poll-interval must be a positive integer"
                    exit 2
                fi
                POLL_INTERVAL="$2"
                shift 2
                ;;
            --task-count)
                if [[ -z "${2:-}" ]]; then
                    log_error "--task-count requires a value"
                    exit 2
                fi
                if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    log_error "--task-count must be a positive integer"
                    exit 2
                fi
                TASK_COUNT="$2"
                shift 2
                ;;
            --failure-rate)
                if [[ -z "${2:-}" ]]; then
                    log_error "--failure-rate requires a value"
                    exit 2
                fi
                if ! [[ "$2" =~ ^[0-9]+$ ]] || [[ "$2" -gt 100 ]]; then
                    log_error "--failure-rate must be 0-100"
                    exit 2
                fi
                FAILURE_RATE="$2"
                shift 2
                ;;
            --task-duration-min)
                if [[ -z "${2:-}" ]]; then
                    log_error "--task-duration-min requires a value"
                    exit 2
                fi
                if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    log_error "--task-duration-min must be a positive integer"
                    exit 2
                fi
                TASK_DURATION_MIN="$2"
                shift 2
                ;;
            --task-duration-max)
                if [[ -z "${2:-}" ]]; then
                    log_error "--task-duration-max requires a value"
                    exit 2
                fi
                if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    log_error "--task-duration-max must be a positive integer"
                    exit 2
                fi
                TASK_DURATION_MAX="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information" >&2
                exit 2
                ;;
        esac
    done
}

# =============================================================================
# Cleanup and Signal Handling
# =============================================================================

cleanup() {
    # Prevent double cleanup
    if [[ "$CLEANUP_DONE" == "true" ]]; then
        return 0
    fi
    CLEANUP_DONE=true

    log_info "Cleaning up..."

    # Stop monitor process
    if [[ -n "$MONITOR_PID" ]] && kill -0 "$MONITOR_PID" 2>/dev/null; then
        log_verbose "Stopping monitor process (PID: $MONITOR_PID)"
        kill -TERM "$MONITOR_PID" 2>/dev/null || true
        wait "$MONITOR_PID" 2>/dev/null || true
    fi

    # Stop sdd-loop process
    if [[ -n "$SDD_LOOP_PID" ]] && kill -0 "$SDD_LOOP_PID" 2>/dev/null; then
        log_verbose "Stopping sdd-loop process (PID: $SDD_LOOP_PID)"
        kill -TERM "$SDD_LOOP_PID" 2>/dev/null || true
        wait "$SDD_LOOP_PID" 2>/dev/null || true
    fi

    log_info "Cleanup complete"
}

handle_sigint() {
    log_info "Received SIGINT, shutting down..."
    cleanup
    exit 130
}

handle_sigterm() {
    log_info "Received SIGTERM, shutting down..."
    cleanup
    exit 143
}

# Set up signal handlers
trap cleanup EXIT
trap handle_sigint SIGINT INT
trap handle_sigterm SIGTERM TERM

# =============================================================================
# Test Environment Setup
# =============================================================================

setup_workspace() {
    log_info "Setting up test workspace..."

    # Create workspace directory if not specified
    if [[ -z "$WORKSPACE" ]]; then
        WORKSPACE=$(mktemp -d "/tmp/sdd-load-test-XXXXXX")
    else
        mkdir -p "$WORKSPACE"
    fi

    log_verbose "Workspace: $WORKSPACE"

    # Create directory structure
    mkdir -p "$WORKSPACE/test-repo/_SDD/tickets/LOADTEST_stress-test/tasks"
    mkdir -p "$WORKSPACE/scripts"
    mkdir -p "$WORKSPACE/bin"
    mkdir -p "$WORKSPACE/logs"

    # Create state files
    echo "0" > "$WORKSPACE/task_counter"
    echo "0" > "$WORKSPACE/iteration_counter"
    echo "0" > "$WORKSPACE/completed_tasks"
    echo "0" > "$WORKSPACE/failed_tasks"

    log_verbose "Created directory structure"
}

create_mock_tasks() {
    log_info "Creating $TASK_COUNT mock tasks..."

    local ticket_dir="$WORKSPACE/test-repo/_SDD/tickets/LOADTEST_stress-test"
    local tasks_dir="$ticket_dir/tasks"

    # Create .autogate.json
    cat > "$ticket_dir/.autogate.json" << 'EOF'
{
    "ready": true,
    "agent_ready": true
}
EOF

    # Create mock tasks across multiple phases
    local task_num
    for ((task_num=1; task_num<=TASK_COUNT; task_num++)); do
        # Distribute tasks across phases 1-4
        local phase
        phase=$(( (task_num % 4) + 1 ))
        local task_id
        task_id="LOADTEST.${phase}$(printf '%03d' $task_num)"

        cat > "$tasks_dir/${task_id}_load-test-task.md" << EOF
# Task: [$task_id]: Load Test Task $task_num

## Status
- [ ] **Task completed** - acceptance criteria met
- [ ] **Tests pass** - N/A
- [ ] **Verified** - by the verify-task agent

## Agents
- general-purpose

## Summary
Load test task $task_num of $TASK_COUNT for stress testing.

## Acceptance Criteria
- [ ] Task simulated successfully

## Technical Requirements
This is a mock task for load testing. No actual work required.
EOF
    done

    log_verbose "Created $TASK_COUNT tasks"
}

create_mock_status_board() {
    log_info "Creating mock master-status-board.sh..."

    # Create a mock status board that cycles through tasks
    cat > "$WORKSPACE/scripts/master-status-board.sh" << 'MOCK_SCRIPT'
#!/usr/bin/env bash
# Mock master-status-board.sh for load testing
# Cycles through tasks and occasionally returns "none"

set -euo pipefail

WORKSPACE_DIR="$(dirname "$(dirname "${BASH_SOURCE[0]}")")"
COUNTER_FILE="$WORKSPACE_DIR/task_counter"
TOTAL_TASKS="__TASK_COUNT__"

# Read and increment counter
if [[ ! -f "$COUNTER_FILE" ]]; then
    echo "0" > "$COUNTER_FILE"
fi

COUNTER=$(cat "$COUNTER_FILE")
COUNTER=$((COUNTER + 1))

# Wrap around after all tasks
if [[ $COUNTER -gt $TOTAL_TASKS ]]; then
    COUNTER=1
fi

echo "$COUNTER" > "$COUNTER_FILE"

# Calculate phase and task number
PHASE=$(( ((COUNTER - 1) % 4) + 1 ))
TASK_NUM=$COUNTER
TASK_ID="LOADTEST.${PHASE}$(printf '%03d' $TASK_NUM)"

# 10% chance to return "none" to simulate no work available
RANDOM_VAL=$((RANDOM % 100))
if [[ $RANDOM_VAL -lt 5 ]]; then
    # Return "none" action
    cat << EOF
{
    "version": "1.0.0",
    "recommended_action": {
        "action": "none",
        "task": "",
        "ticket": "",
        "sdd_root": "",
        "reason": "Periodic pause - no immediate work"
    }
}
EOF
else
    # Return do-task action
    cat << EOF
{
    "version": "1.0.0",
    "recommended_action": {
        "action": "do-task",
        "task": "$TASK_ID",
        "ticket": "LOADTEST",
        "sdd_root": "$WORKSPACE_DIR/test-repo/_SDD",
        "reason": "Task $TASK_NUM ready for execution"
    }
}
EOF
fi
MOCK_SCRIPT

    # Replace placeholder with actual task count (portable sed -i)
    sed -i.bak "s/__TASK_COUNT__/$TASK_COUNT/" "$WORKSPACE/scripts/master-status-board.sh"
    rm -f "$WORKSPACE/scripts/master-status-board.sh.bak"
    chmod +x "$WORKSPACE/scripts/master-status-board.sh"

    log_verbose "Created mock master-status-board.sh"
}

create_mock_claude() {
    log_info "Creating mock claude CLI..."

    # Create a mock claude that simulates task execution
    cat > "$WORKSPACE/bin/claude" << 'MOCK_CLAUDE'
#!/usr/bin/env bash
# Mock claude CLI for load testing
# Simulates task execution with configurable duration and failure rate

set -euo pipefail

WORKSPACE_DIR="__WORKSPACE__"
FAILURE_RATE="__FAILURE_RATE__"
TASK_DURATION_MIN="__TASK_DURATION_MIN__"
TASK_DURATION_MAX="__TASK_DURATION_MAX__"

# Track completed/failed tasks
COMPLETED_FILE="$WORKSPACE_DIR/completed_tasks"
FAILED_FILE="$WORKSPACE_DIR/failed_tasks"

# Calculate random duration in milliseconds
if [[ $TASK_DURATION_MAX -gt $TASK_DURATION_MIN ]]; then
    DURATION_RANGE=$((TASK_DURATION_MAX - TASK_DURATION_MIN))
    DURATION_MS=$((TASK_DURATION_MIN + (RANDOM % DURATION_RANGE)))
else
    DURATION_MS=$TASK_DURATION_MIN
fi

# Convert to seconds (with decimal) - use awk for portability
DURATION_SEC=$(awk "BEGIN {printf \"%.3f\", $DURATION_MS / 1000}")

# Simulate work
sleep "$DURATION_SEC"

# Determine success/failure based on failure rate
RANDOM_VAL=$((RANDOM % 100))
if [[ $RANDOM_VAL -lt $FAILURE_RATE ]]; then
    # Increment failed counter
    if [[ -f "$FAILED_FILE" ]]; then
        FAILED=$(cat "$FAILED_FILE")
        echo $((FAILED + 1)) > "$FAILED_FILE"
    fi
    echo "Mock claude: Simulated task failure" >&2
    exit 1
else
    # Increment completed counter
    if [[ -f "$COMPLETED_FILE" ]]; then
        COMPLETED=$(cat "$COMPLETED_FILE")
        echo $((COMPLETED + 1)) > "$COMPLETED_FILE"
    fi
    exit 0
fi
MOCK_CLAUDE

    # Replace placeholders (portable sed -i)
    sed -i.bak "s|__WORKSPACE__|$WORKSPACE|g" "$WORKSPACE/bin/claude"
    sed -i.bak "s|__FAILURE_RATE__|$FAILURE_RATE|g" "$WORKSPACE/bin/claude"
    sed -i.bak "s|__TASK_DURATION_MIN__|$TASK_DURATION_MIN|g" "$WORKSPACE/bin/claude"
    sed -i.bak "s|__TASK_DURATION_MAX__|$TASK_DURATION_MAX|g" "$WORKSPACE/bin/claude"
    rm -f "$WORKSPACE/bin/claude.bak"
    chmod +x "$WORKSPACE/bin/claude"

    log_verbose "Created mock claude CLI"
}

setup_sdd_loop_copy() {
    log_info "Setting up sdd-loop.sh copy..."

    # Copy sdd-loop.sh to workspace so it finds our mock master-status-board.sh
    cp "$SCRIPT_DIR/sdd-loop.sh" "$WORKSPACE/scripts/sdd-loop.sh"
    chmod +x "$WORKSPACE/scripts/sdd-loop.sh"

    log_verbose "Copied sdd-loop.sh to workspace"
}

# =============================================================================
# Test Execution
# =============================================================================

show_configuration() {
    local duration_hours
    duration_hours=$(awk "BEGIN {printf \"%.1f\", $DURATION / 3600}")

    log_info "Load Test Configuration:"
    echo "  Duration:          $DURATION seconds ($duration_hours hours)"
    echo "  Workspace:         ${WORKSPACE:-<auto-generated>}"
    echo "  Poll Interval:     $POLL_INTERVAL seconds"
    echo "  Task Count:        $TASK_COUNT"
    echo "  Failure Rate:      $FAILURE_RATE%"
    echo "  Task Duration:     ${TASK_DURATION_MIN}-${TASK_DURATION_MAX} ms"
    echo "  Report File:       ${REPORT_FILE:-<stdout>}"
    echo ""
}

start_monitoring() {
    log_info "Starting resource monitoring..."

    local monitor_script="$SCRIPT_DIR/monitor-loop-resources.sh"

    if [[ ! -f "$monitor_script" ]]; then
        log_error "Monitor script not found: $monitor_script"
        return 1
    fi

    # Start monitoring in background
    bash "$monitor_script" \
        --pid-file "$WORKSPACE/sdd-loop.pid" \
        --output "$WORKSPACE/metrics.csv" \
        --interval "$POLL_INTERVAL" \
        --workspace "$WORKSPACE" \
        > "$WORKSPACE/logs/monitor.log" 2>&1 &

    MONITOR_PID=$!
    echo "$MONITOR_PID" > "$WORKSPACE/monitor.pid"

    log_verbose "Monitor started (PID: $MONITOR_PID)"
}

run_sdd_loop() {
    log_info "Starting sdd-loop.sh..."

    # Calculate max iterations based on duration and estimated task time
    # Assuming average task time of ~2 seconds plus overhead
    local avg_task_time=3
    local max_iterations=$((DURATION / avg_task_time + 100))

    log_verbose "Max iterations: $max_iterations"

    # Run sdd-loop.sh with our mock components
    # Use PATH to inject mock claude, and run from workspace so it finds mock status board
    PATH="$WORKSPACE/bin:$PATH" \
        timeout "$DURATION" \
        bash "$WORKSPACE/scripts/sdd-loop.sh" \
        --max-iterations "$max_iterations" \
        --max-errors 100 \
        --timeout 60 \
        --poll-interval 1 \
        "$WORKSPACE/test-repo" \
        > "$WORKSPACE/logs/sdd-loop.log" 2>&1 &

    SDD_LOOP_PID=$!
    echo "$SDD_LOOP_PID" > "$WORKSPACE/sdd-loop.pid"

    log_info "sdd-loop.sh started (PID: $SDD_LOOP_PID)"
}

wait_for_completion() {
    local start_time
    start_time=$(date +%s)
    local last_status_time=$start_time

    log_info "Test running for $DURATION seconds..."
    log_info "Workspace: $WORKSPACE"
    log_info "Logs: $WORKSPACE/logs/"
    log_info "Metrics: $WORKSPACE/metrics.csv"
    echo ""

    while kill -0 "$SDD_LOOP_PID" 2>/dev/null; do
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        # Print status every 60 seconds
        if [[ $((current_time - last_status_time)) -ge 60 ]]; then
            local completed failed
            completed=$(cat "$WORKSPACE/completed_tasks" 2>/dev/null || echo "0")
            failed=$(cat "$WORKSPACE/failed_tasks" 2>/dev/null || echo "0")
            local total=$((completed + failed))

            log_info "Progress: ${elapsed}s elapsed, $total tasks processed ($completed completed, $failed failed)"
            last_status_time=$current_time
        fi

        # Check if we've exceeded duration
        if [[ $elapsed -ge $DURATION ]]; then
            log_info "Duration limit reached"
            break
        fi

        sleep 5
    done

    # Wait for sdd-loop to fully exit
    wait "$SDD_LOOP_PID" 2>/dev/null || true
}

generate_report() {
    log_info "Generating report..."

    local end_time
    end_time=$(date +%s)
    local elapsed=$((end_time - TEST_START_TIME))

    local completed failed
    completed=$(cat "$WORKSPACE/completed_tasks" 2>/dev/null || echo "0")
    failed=$(cat "$WORKSPACE/failed_tasks" 2>/dev/null || echo "0")
    local total=$((completed + failed))

    # Stop monitoring
    if [[ -n "$MONITOR_PID" ]] && kill -0 "$MONITOR_PID" 2>/dev/null; then
        kill -TERM "$MONITOR_PID" 2>/dev/null || true
        sleep 1
    fi

    # Generate analysis report
    local analyze_script="$SCRIPT_DIR/analyze-load-test.sh"
    local report_content=""

    if [[ -f "$analyze_script" && -f "$WORKSPACE/metrics.csv" ]]; then
        report_content=$(bash "$analyze_script" "$WORKSPACE/metrics.csv" "$WORKSPACE" 2>/dev/null || true)
    fi

    # Calculate derived values using awk (more portable than bc)
    local elapsed_hours success_rate
    elapsed_hours=$(awk "BEGIN {printf \"%.2f\", $elapsed / 3600}")
    if [[ $total -gt 0 ]]; then
        success_rate=$(awk "BEGIN {printf \"%.1f\", $completed * 100 / $total}")
    else
        success_rate="0.0"
    fi

    # Build report
    local report
    report=$(cat << EOF
# SDD Loop Controller Load Test Report

## Test Summary

| Metric | Value |
|--------|-------|
| Test Duration | ${elapsed} seconds ($elapsed_hours hours) |
| Total Tasks Processed | $total |
| Tasks Completed | $completed |
| Tasks Failed | $failed |
| Success Rate | ${success_rate}% |
| Configured Task Count | $TASK_COUNT |
| Configured Failure Rate | $FAILURE_RATE% |

## Test Configuration

- Duration: $DURATION seconds
- Poll Interval: $POLL_INTERVAL seconds
- Task Count: $TASK_COUNT
- Failure Rate: $FAILURE_RATE%
- Task Duration: ${TASK_DURATION_MIN}-${TASK_DURATION_MAX} ms

## Workspace

- Location: \`$WORKSPACE\`
- Metrics File: \`$WORKSPACE/metrics.csv\`
- sdd-loop Log: \`$WORKSPACE/logs/sdd-loop.log\`
- Monitor Log: \`$WORKSPACE/logs/monitor.log\`

$report_content

## Raw Metrics Location

Detailed metrics CSV file: \`$WORKSPACE/metrics.csv\`

To analyze further:
\`\`\`bash
$SCRIPT_DIR/analyze-load-test.sh $WORKSPACE/metrics.csv $WORKSPACE
\`\`\`

---
Generated: $(date '+%Y-%m-%d %H:%M:%S')
EOF
)

    # Output report
    if [[ -n "$REPORT_FILE" ]]; then
        echo "$report" > "$REPORT_FILE"
        log_info "Report written to: $REPORT_FILE"
    else
        echo ""
        echo "$report"
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    echo "========================================"
    echo "SDD Loop Controller Load Test v$VERSION"
    echo "========================================"
    echo ""

    show_configuration

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run - exiting without running test"
        exit 0
    fi

    # Record start time
    TEST_START_TIME=$(date +%s)

    # Setup
    setup_workspace
    create_mock_tasks
    create_mock_status_board
    create_mock_claude
    setup_sdd_loop_copy
    echo ""

    # Run test
    start_monitoring
    run_sdd_loop
    wait_for_completion
    echo ""

    # Generate report
    generate_report

    log_info "Load test complete"
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
