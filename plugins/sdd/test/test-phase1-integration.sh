#!/bin/sh
#
# Phase 1 Integration Tests - SDD Tasks API Integration
#
# This test suite validates the complete integration between all Phase 1 components:
# - hydrate-tasks.py: Populates Tasks API from task markdown files
# - conflict-resolution.py: Detects and resolves file/API state mismatches
# - sync-task-status.sh: Updates task files based on Tasks API status
# - setup-sdd-env.js: Session start hook with task list detection
#
# Test Scenarios:
# 1. Hydration Cycle: Task files -> Tasks API entries with correct dependencies
# 2. Sync Cycle: TaskUpdate -> file checkbox updates
# 3. Round-Trip: Fresh ticket -> full cycle -> consistent state
# 4. Conflict Resolution: File/API mismatches resolved correctly (file wins)
# 5. Backward Compatibility: Existing tickets work without modification
#
# Usage:
#   ./test-phase1-integration.sh           # Run all tests
#   ./test-phase1-integration.sh -v        # Verbose output
#   ./test-phase1-integration.sh --help    # Show help
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed

# ============================================================================
# Configuration
# ============================================================================

# Get script directory (portable approach)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Component paths
HYDRATE_SCRIPT="$PLUGIN_ROOT/hooks/hydrate-tasks.py"
CONFLICT_SCRIPT="$PLUGIN_ROOT/hooks/conflict-resolution.py"
SYNC_SCRIPT="$PLUGIN_ROOT/scripts/sync-task-status.sh"
SETUP_HOOK="$PLUGIN_ROOT/hooks/setup-sdd-env.js"

TEMP_DIR=""

# Colors for output (if terminal supports it)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Verbose mode
VERBOSE=false

# ============================================================================
# Helper Functions
# ============================================================================

usage() {
    printf "Usage: %s [-v|--verbose] [--help]\n" "$0"
    printf "\n"
    printf "Options:\n"
    printf "  -v, --verbose  Show detailed output for each test\n"
    printf "  --help         Show this help message\n"
    exit 0
}

# Parse command line arguments
while [ $# -gt 0 ]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            printf "Unknown option: %s\n" "$1"
            usage
            ;;
    esac
done

# Setup temporary directory for test files
setup() {
    TEMP_DIR=$(mktemp -d)
    if [ "$VERBOSE" = true ]; then
        printf "Created temp directory: %s\n" "$TEMP_DIR"
    fi
    # Set SDD_ROOT_DIR to temp directory for tests
    export SDD_ROOT_DIR="$TEMP_DIR"
}

# Cleanup temporary directory
cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        if [ "$VERBOSE" = true ]; then
            printf "Cleaned up temp directory: %s\n" "$TEMP_DIR"
        fi
    fi
}

# Create a test ticket directory structure under SDD_ROOT/tickets/
create_test_ticket() {
    local ticket_name="$1"
    local ticket_dir="$TEMP_DIR/tickets/$ticket_name"
    mkdir -p "$ticket_dir/tasks"
    printf "%s" "$ticket_dir"
}

# Create a task file with specified status
# Usage: create_task_file TASKS_DIR TASK_ID TASK_NAME [STATUS] [DEPS]
# STATUS: 'pending' (default) or 'completed'
# DEPS: comma-separated dependencies (optional)
create_task_file() {
    local tasks_dir="$1"
    local task_id="$2"
    local task_name="$3"
    local status="${4:-pending}"
    local deps="${5:-}"

    local checkbox_status=" "
    if [ "$status" = "completed" ]; then
        checkbox_status="x"
    fi

    local file_path="$tasks_dir/${task_id}_${task_name}.md"

    cat > "$file_path" << EOF
# Task: [$task_id]: ${task_name}

## Status
- [$checkbox_status] **Task completed** - acceptance criteria met
- [ ] **Tests pass** - tests executed and passing (or N/A if no tests)
- [ ] **Verified** - by the verify-task agent

## Summary
This is the summary for task $task_id.

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2

EOF

    # Add dependencies section if provided
    if [ -n "$deps" ]; then
        printf "## Dependencies\n" >> "$file_path"
        # Split deps by comma and output each
        echo "$deps" | tr ',' '\n' | while read dep; do
            # Use echo instead of printf to avoid issues with dashes being interpreted as options
            echo "- $dep" >> "$file_path"
        done
        printf "\n" >> "$file_path"
    fi

    printf "## Technical Requirements\nSome technical requirements here.\n" >> "$file_path"

    printf "%s" "$file_path"
}

# Create API tasks JSON file
# Usage: create_api_tasks_json OUTPUT_FILE ENTRY1 ENTRY2 ...
# Entry format: "task_id:status"
create_api_tasks_json() {
    local output_file="$1"
    shift

    printf "[\n" > "$output_file"
    local first=true
    for entry in "$@"; do
        local task_id="${entry%%:*}"
        local status="${entry##*:}"

        if [ "$first" = true ]; then
            first=false
        else
            printf ",\n" >> "$output_file"
        fi

        cat >> "$output_file" << EOF
  {
    "id": "api-${task_id}",
    "subject": "Task ${task_id}: Test Task",
    "status": "${status}",
    "metadata": {
      "file_path": "/test/tasks/${task_id}_test-task.md",
      "phase": 1,
      "source": "hydrate-tasks"
    }
  }
EOF
    done
    printf "\n]\n" >> "$output_file"
}

# Check if file contains checked checkbox
has_checked_checkbox() {
    local file="$1"
    grep -q '^\- \[x\] \*\*Task completed\*\*' "$file" 2>/dev/null
}

# Check if file contains unchecked checkbox
has_unchecked_checkbox() {
    local file="$1"
    grep -q '^\- \[ \] \*\*Task completed\*\*' "$file" 2>/dev/null
}

# Get JSON value using Python
get_json_value() {
    local json="$1"
    local key_path="$2"
    printf "%s" "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
keys = '$key_path'.split('.')
result = data
for key in keys:
    if key.isdigit():
        result = result[int(key)]
    else:
        result = result.get(key, None)
    if result is None:
        break
print(result if result is not None else '')
" 2>/dev/null
}

# Get task count from hydration JSON output
get_task_count() {
    local json="$1"
    printf "%s" "$json" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || printf "0"
}

# Get task status from hydration JSON output
get_task_status() {
    local json="$1"
    local task_id="$2"
    printf "%s" "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for task in data:
    if task['task_id'] == '$task_id':
        print(task['status'])
        break
" 2>/dev/null
}

# Get blockedBy list from hydration JSON output
get_blocked_by() {
    local json="$1"
    local task_id="$2"
    printf "%s" "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for task in data:
    if task['task_id'] == '$task_id':
        print(','.join(sorted(task['blockedBy'])))
        break
" 2>/dev/null
}

# Get conflicts count from conflict resolution JSON
get_conflicts_count() {
    local json="$1"
    printf "%s" "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('summary', {}).get('conflicts_found', 0))
" 2>/dev/null || printf "0"
}

# Get rehydration needed from conflict resolution JSON
get_rehydration_needed() {
    local json="$1"
    printf "%s" "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print('true' if data.get('summary', {}).get('rehydration_needed', False) else 'false')
" 2>/dev/null || printf "false"
}

# Report test result - pass
pass_test() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "%sPASS%s\n" "$GREEN" "$NC"
}

# Report test result - fail
fail_test() {
    local reason="$1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "%sFAIL%s (%s)\n" "$RED" "$NC" "$reason"
}

# ============================================================================
# Test Fixtures
# ============================================================================

# Create a simple ticket with 3 tasks in the same phase (no dependencies)
create_simple_ticket() {
    local ticket_name="${1:-SIMPLE_test-simple}"
    local ticket_dir
    ticket_dir=$(create_test_ticket "$ticket_name")

    create_task_file "$ticket_dir/tasks" "SIMPLE.1001" "first-task" "pending" >/dev/null
    create_task_file "$ticket_dir/tasks" "SIMPLE.1002" "second-task" "pending" >/dev/null
    create_task_file "$ticket_dir/tasks" "SIMPLE.1003" "third-task" "pending" >/dev/null

    printf "%s" "$ticket_dir"
}

# Create a phased ticket with tasks across multiple phases
create_phased_ticket() {
    local ticket_name="${1:-PHASED_test-phased}"
    local ticket_dir
    ticket_dir=$(create_test_ticket "$ticket_name")

    # Phase 0 tasks (foundations)
    create_task_file "$ticket_dir/tasks" "PHASED.0001" "foundation-task" "completed" >/dev/null
    # Phase 1 tasks (implementation)
    create_task_file "$ticket_dir/tasks" "PHASED.1001" "implement-feature" "pending" >/dev/null
    create_task_file "$ticket_dir/tasks" "PHASED.1002" "add-tests" "pending" >/dev/null
    # Phase 2 tasks (integration)
    create_task_file "$ticket_dir/tasks" "PHASED.2001" "integration-test" "pending" >/dev/null

    printf "%s" "$ticket_dir"
}

# Create a complex ticket with explicit dependencies
create_complex_ticket() {
    local ticket_name="${1:-COMPLEX_test-complex}"
    local ticket_dir
    ticket_dir=$(create_test_ticket "$ticket_name")

    # Tasks with explicit dependencies
    create_task_file "$ticket_dir/tasks" "COMPLEX.1001" "base-module" "pending" >/dev/null
    create_task_file "$ticket_dir/tasks" "COMPLEX.1002" "depends-on-base" "pending" "COMPLEX.1001" >/dev/null
    create_task_file "$ticket_dir/tasks" "COMPLEX.1003" "depends-on-both" "pending" "COMPLEX.1001,COMPLEX.1002" >/dev/null

    printf "%s" "$ticket_dir"
}

# ============================================================================
# Integration Test: Hydration Cycle
# ============================================================================

test_hydration_simple_ticket() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Hydration - Simple ticket (3 tasks, same phase) ... "

    local ticket_dir
    ticket_dir=$(create_simple_ticket "HYDSIMPLE_test")

    local output
    output=$(python3 "$HYDRATE_SCRIPT" "$ticket_dir" "HYDSIMPLE" 2>/dev/null) || {
        fail_test "hydration failed"
        return
    }

    local count
    count=$(get_task_count "$output")
    if [ "$count" != "3" ]; then
        fail_test "expected 3 tasks, got $count"
        return
    fi

    # All tasks in same phase should have no blockers
    local blocked1
    blocked1=$(get_blocked_by "$output" "SIMPLE.1001")
    if [ -n "$blocked1" ]; then
        fail_test "same-phase task should have no blockers, got '$blocked1'"
        return
    fi

    pass_test
}

test_hydration_phased_ticket() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Hydration - Phased ticket (tasks across phases) ... "

    local ticket_dir
    ticket_dir=$(create_phased_ticket "HYDPHASED_test")

    local output
    output=$(python3 "$HYDRATE_SCRIPT" "$ticket_dir" "HYDPHASED" 2>/dev/null) || {
        fail_test "hydration failed"
        return
    }

    local count
    count=$(get_task_count "$output")
    if [ "$count" != "4" ]; then
        fail_test "expected 4 tasks, got $count"
        return
    fi

    # Phase 0 task should have no blockers
    local blocked0
    blocked0=$(get_blocked_by "$output" "PHASED.0001")
    if [ -n "$blocked0" ]; then
        fail_test "Phase 0 task should have no blockers"
        return
    fi

    # Phase 1 tasks should be blocked by Phase 0
    local blocked1
    blocked1=$(get_blocked_by "$output" "PHASED.1001")
    if [ "$blocked1" != "PHASED.0001" ]; then
        fail_test "Phase 1 should be blocked by PHASED.0001, got '$blocked1'"
        return
    fi

    # Phase 2 should be blocked by Phase 1 tasks
    local blocked2
    blocked2=$(get_blocked_by "$output" "PHASED.2001")
    if [ "$blocked2" != "PHASED.1001,PHASED.1002" ]; then
        fail_test "Phase 2 should be blocked by Phase 1 tasks, got '$blocked2'"
        return
    fi

    pass_test
}

test_hydration_complex_dependencies() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Hydration - Complex ticket (explicit dependencies) ... "

    local ticket_dir
    ticket_dir=$(create_complex_ticket "HYDCOMPLEX_test")

    local output
    output=$(python3 "$HYDRATE_SCRIPT" "$ticket_dir" "HYDCOMPLEX" 2>/dev/null) || {
        fail_test "hydration failed"
        return
    }

    # Third task should have both explicit dependencies
    local blocked3
    blocked3=$(get_blocked_by "$output" "COMPLEX.1003")
    if [ "$blocked3" != "COMPLEX.1001,COMPLEX.1002" ]; then
        fail_test "expected blockers 'COMPLEX.1001,COMPLEX.1002', got '$blocked3'"
        return
    fi

    pass_test
}

test_hydration_status_mapping() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Hydration - Status correctly mapped from checkboxes ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "HYDSTATUS_test")

    create_task_file "$ticket_dir/tasks" "HYDSTATUS.1001" "pending-task" "pending" >/dev/null
    create_task_file "$ticket_dir/tasks" "HYDSTATUS.1002" "completed-task" "completed" >/dev/null

    local output
    output=$(python3 "$HYDRATE_SCRIPT" "$ticket_dir" "HYDSTATUS" 2>/dev/null) || {
        fail_test "hydration failed"
        return
    }

    local status1
    status1=$(get_task_status "$output" "HYDSTATUS.1001")
    if [ "$status1" != "pending" ]; then
        fail_test "expected pending status, got '$status1'"
        return
    fi

    local status2
    status2=$(get_task_status "$output" "HYDSTATUS.1002")
    if [ "$status2" != "completed" ]; then
        fail_test "expected completed status, got '$status2'"
        return
    fi

    pass_test
}

# ============================================================================
# Integration Test: Sync Cycle
# ============================================================================

test_sync_completed_updates_checkbox() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Sync - Completed status updates checkbox ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "SYNC_test-completed")
    local task_file
    task_file=$(create_task_file "$ticket_dir/tasks" "SYNC.1001" "test-task" "pending")

    # Verify initial state
    if ! has_unchecked_checkbox "$task_file"; then
        fail_test "initial state should be unchecked"
        return
    fi

    # Run sync
    local exit_code=0
    "$SYNC_SCRIPT" "SYNC.1001" "completed" >/dev/null 2>&1 || exit_code=$?

    if [ $exit_code -ne 0 ]; then
        fail_test "sync failed with exit $exit_code"
        return
    fi

    # Verify final state
    if ! has_checked_checkbox "$task_file"; then
        fail_test "checkbox should be checked after sync"
        return
    fi

    pass_test
}

test_sync_pending_no_change() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Sync - Pending status makes no change ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "SYNCPEND_test-pending")
    local task_file
    task_file=$(create_task_file "$ticket_dir/tasks" "SYNCPEND.1001" "test-task" "pending")

    # Run sync with pending status
    local exit_code=0
    "$SYNC_SCRIPT" "SYNCPEND.1001" "pending" >/dev/null 2>&1 || exit_code=$?

    if [ $exit_code -ne 0 ]; then
        fail_test "sync failed with exit $exit_code"
        return
    fi

    # Checkbox should remain unchecked
    if ! has_unchecked_checkbox "$task_file"; then
        fail_test "checkbox should remain unchecked"
        return
    fi

    pass_test
}

test_sync_in_progress_no_change() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Sync - In_progress status makes no change ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "SYNCINP_test-in-progress")
    local task_file
    task_file=$(create_task_file "$ticket_dir/tasks" "SYNCINP.1001" "test-task" "pending")

    # Run sync with in_progress status
    local exit_code=0
    "$SYNC_SCRIPT" "SYNCINP.1001" "in_progress" >/dev/null 2>&1 || exit_code=$?

    if [ $exit_code -ne 0 ]; then
        fail_test "sync failed with exit $exit_code"
        return
    fi

    # Checkbox should remain unchecked
    if ! has_unchecked_checkbox "$task_file"; then
        fail_test "checkbox should remain unchecked"
        return
    fi

    pass_test
}

test_sync_idempotent() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Sync - Idempotent on already-completed tasks ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "SYNCIDEM_test-idempotent")
    local task_file
    task_file=$(create_task_file "$ticket_dir/tasks" "SYNCIDEM.1001" "test-task" "completed")

    # Run sync on already-completed task
    local exit_code=0
    "$SYNC_SCRIPT" "SYNCIDEM.1001" "completed" >/dev/null 2>&1 || exit_code=$?

    if [ $exit_code -ne 0 ]; then
        fail_test "sync failed with exit $exit_code"
        return
    fi

    # Checkbox should still be checked
    if ! has_checked_checkbox "$task_file"; then
        fail_test "checkbox should remain checked"
        return
    fi

    pass_test
}

# ============================================================================
# Integration Test: Conflict Resolution
# ============================================================================

test_conflict_file_wins_when_complete() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Conflict - File wins when file=completed, API=pending ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "CONFCOMP_test-conflict")
    create_task_file "$ticket_dir/tasks" "CONFCOMP.1001" "test-task" "completed" >/dev/null

    local api_file="$TEMP_DIR/api_tasks.json"
    create_api_tasks_json "$api_file" "CONFCOMP.1001:pending"

    local output
    output=$(python3 "$CONFLICT_SCRIPT" "$ticket_dir" "$api_file" 2>/dev/null) || {
        fail_test "conflict detection failed"
        return
    }

    local count
    count=$(get_conflicts_count "$output")
    if [ "$count" != "1" ]; then
        fail_test "expected 1 conflict, got $count"
        return
    fi

    # Verify file status is used in resolution
    local file_status
    file_status=$(printf "%s" "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for c in data.get('conflicts', []):
    if c['task_id'] == 'CONFCOMP.1001':
        print(c['file_status'])
        break
" 2>/dev/null)

    if [ "$file_status" != "completed" ]; then
        fail_test "file status should be completed, got '$file_status'"
        return
    fi

    pass_test
}

test_conflict_file_wins_when_pending() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Conflict - File wins when file=pending, API=completed ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "CONFPEND_test-conflict")
    create_task_file "$ticket_dir/tasks" "CONFPEND.1001" "test-task" "pending" >/dev/null

    local api_file="$TEMP_DIR/api_tasks.json"
    create_api_tasks_json "$api_file" "CONFPEND.1001:completed"

    local output
    output=$(python3 "$CONFLICT_SCRIPT" "$ticket_dir" "$api_file" 2>/dev/null) || {
        fail_test "conflict detection failed"
        return
    }

    local count
    count=$(get_conflicts_count "$output")
    if [ "$count" != "1" ]; then
        fail_test "expected 1 conflict, got $count"
        return
    fi

    # Rehydration should be needed
    local rehydration
    rehydration=$(get_rehydration_needed "$output")
    if [ "$rehydration" != "true" ]; then
        fail_test "rehydration should be needed"
        return
    fi

    pass_test
}

test_conflict_no_conflict_when_matching() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Conflict - No conflict when states match ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "CONFMATCH_test-match")
    create_task_file "$ticket_dir/tasks" "CONFMATCH.1001" "test-task" "pending" >/dev/null
    create_task_file "$ticket_dir/tasks" "CONFMATCH.1002" "test-task2" "completed" >/dev/null

    local api_file="$TEMP_DIR/api_tasks.json"
    create_api_tasks_json "$api_file" "CONFMATCH.1001:pending" "CONFMATCH.1002:completed"

    local output
    output=$(python3 "$CONFLICT_SCRIPT" "$ticket_dir" "$api_file" 2>/dev/null) || {
        fail_test "conflict detection failed"
        return
    }

    local count
    count=$(get_conflicts_count "$output")
    if [ "$count" != "0" ]; then
        fail_test "expected 0 conflicts when states match, got $count"
        return
    fi

    local rehydration
    rehydration=$(get_rehydration_needed "$output")
    if [ "$rehydration" != "false" ]; then
        fail_test "no rehydration should be needed when states match"
        return
    fi

    pass_test
}

test_conflict_in_progress_treated_as_pending() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Conflict - API in_progress treated as pending ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "CONFINP_test")
    create_task_file "$ticket_dir/tasks" "CONFINP.1001" "test-task" "pending" >/dev/null

    local api_file="$TEMP_DIR/api_tasks.json"
    create_api_tasks_json "$api_file" "CONFINP.1001:in_progress"

    local output
    output=$(python3 "$CONFLICT_SCRIPT" "$ticket_dir" "$api_file" 2>/dev/null) || {
        fail_test "conflict detection failed"
        return
    }

    # in_progress should match pending - no conflict
    local count
    count=$(get_conflicts_count "$output")
    if [ "$count" != "0" ]; then
        fail_test "in_progress should be treated as pending (no conflict), got $count conflicts"
        return
    fi

    pass_test
}

# ============================================================================
# Integration Test: Round-Trip
# ============================================================================

test_roundtrip_fresh_ticket() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Round-trip - Fresh ticket hydration cycle ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "ROUND_test-roundtrip")

    # Create initial tasks
    local task1_file
    task1_file=$(create_task_file "$ticket_dir/tasks" "ROUND.1001" "task-one" "pending")
    local task2_file
    task2_file=$(create_task_file "$ticket_dir/tasks" "ROUND.1002" "task-two" "pending")

    # Step 1: Hydrate tasks
    local hydrate_output
    hydrate_output=$(python3 "$HYDRATE_SCRIPT" "$ticket_dir" "ROUND" 2>/dev/null) || {
        fail_test "hydration failed"
        return
    }

    local count
    count=$(get_task_count "$hydrate_output")
    if [ "$count" != "2" ]; then
        fail_test "hydration should return 2 tasks, got $count"
        return
    fi

    # Step 2: Simulate TaskUpdate by syncing completed status
    "$SYNC_SCRIPT" "ROUND.1001" "completed" >/dev/null 2>&1 || {
        fail_test "sync failed"
        return
    }

    # Step 3: Verify file state updated
    if ! has_checked_checkbox "$task1_file"; then
        fail_test "task 1 checkbox should be checked after sync"
        return
    fi

    if ! has_unchecked_checkbox "$task2_file"; then
        fail_test "task 2 checkbox should remain unchecked"
        return
    fi

    # Step 4: Run conflict detection - should find no conflicts
    local api_file="$TEMP_DIR/roundtrip_api.json"
    create_api_tasks_json "$api_file" "ROUND.1001:completed" "ROUND.1002:pending"

    local conflict_output
    conflict_output=$(python3 "$CONFLICT_SCRIPT" "$ticket_dir" "$api_file" 2>/dev/null) || {
        fail_test "conflict detection failed"
        return
    }

    local conflict_count
    conflict_count=$(get_conflicts_count "$conflict_output")
    if [ "$conflict_count" != "0" ]; then
        fail_test "expected 0 conflicts after round-trip, got $conflict_count"
        return
    fi

    pass_test
}

test_roundtrip_recovery_from_crash() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Round-trip - Recovery from simulated crash ... "

    # Scenario: Session crashed between TaskUpdate and file write
    # File shows pending, API shows completed
    # Recovery: File state wins, re-hydration overwrites API

    local ticket_dir
    ticket_dir=$(create_test_ticket "CRASH_test-crash")

    # File shows pending (crash happened before sync write)
    local task_file
    task_file=$(create_task_file "$ticket_dir/tasks" "CRASH.1001" "crashed-task" "pending")

    # API shows completed (TaskUpdate happened but sync didn't)
    local api_file="$TEMP_DIR/crash_api.json"
    create_api_tasks_json "$api_file" "CRASH.1001:completed"

    # Conflict detection should identify the mismatch
    local conflict_output
    conflict_output=$(python3 "$CONFLICT_SCRIPT" "$ticket_dir" "$api_file" 2>/dev/null) || {
        fail_test "conflict detection failed"
        return
    }

    local conflict_count
    conflict_count=$(get_conflicts_count "$conflict_output")
    if [ "$conflict_count" != "1" ]; then
        fail_test "expected 1 conflict from crash scenario, got $conflict_count"
        return
    fi

    # Verify file state is authoritative
    local rehydration
    rehydration=$(get_rehydration_needed "$conflict_output")
    if [ "$rehydration" != "true" ]; then
        fail_test "re-hydration should be needed after crash"
        return
    fi

    # Re-hydration would restore API to file state
    local hydrate_output
    hydrate_output=$(python3 "$HYDRATE_SCRIPT" "$ticket_dir" "CRASH" 2>/dev/null) || {
        fail_test "re-hydration failed"
        return
    }

    local status
    status=$(get_task_status "$hydrate_output" "CRASH.1001")
    if [ "$status" != "pending" ]; then
        fail_test "re-hydrated status should be pending (file state), got '$status'"
        return
    fi

    pass_test
}

# ============================================================================
# Integration Test: Backward Compatibility
# ============================================================================

test_backward_compat_existing_ticket() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Backward compatibility - Existing ticket without Tasks API ... "

    # Scenario: Existing ticket with tasks but no Tasks API history
    # Initial hydration should work correctly

    local ticket_dir
    ticket_dir=$(create_test_ticket "COMPAT_test-compat")

    # Create realistic ticket structure
    create_task_file "$ticket_dir/tasks" "COMPAT.1001" "setup-project" "completed" >/dev/null
    create_task_file "$ticket_dir/tasks" "COMPAT.1002" "implement-feature" "completed" >/dev/null
    create_task_file "$ticket_dir/tasks" "COMPAT.1003" "add-tests" "pending" >/dev/null

    # Initial hydration (no API tasks exist)
    local hydrate_output
    hydrate_output=$(python3 "$HYDRATE_SCRIPT" "$ticket_dir" "COMPAT" 2>/dev/null) || {
        fail_test "hydration failed"
        return
    }

    local count
    count=$(get_task_count "$hydrate_output")
    if [ "$count" != "3" ]; then
        fail_test "expected 3 tasks, got $count"
        return
    fi

    # Verify status is correctly mapped
    local status1
    status1=$(get_task_status "$hydrate_output" "COMPAT.1001")
    if [ "$status1" != "completed" ]; then
        fail_test "task 1 should be completed, got '$status1'"
        return
    fi

    local status3
    status3=$(get_task_status "$hydrate_output" "COMPAT.1003")
    if [ "$status3" != "pending" ]; then
        fail_test "task 3 should be pending, got '$status3'"
        return
    fi

    # Conflict detection with no API tasks should indicate hydration needed
    local conflict_output
    conflict_output=$(python3 "$CONFLICT_SCRIPT" "$ticket_dir" 2>/dev/null) || {
        fail_test "conflict detection failed"
        return
    }

    local rehydration
    rehydration=$(get_rehydration_needed "$conflict_output")
    if [ "$rehydration" != "true" ]; then
        fail_test "rehydration should be needed for initial sync"
        return
    fi

    pass_test
}

test_backward_compat_partial_sync() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Backward compatibility - Partial sync scenario ... "

    # Scenario: Some tasks were synced but others weren't
    # New tasks were added to the ticket

    local ticket_dir
    ticket_dir=$(create_test_ticket "PARTIAL_test-partial")

    # Original tasks (in API)
    create_task_file "$ticket_dir/tasks" "PARTIAL.1001" "original-task" "completed" >/dev/null
    # New task (not in API yet)
    create_task_file "$ticket_dir/tasks" "PARTIAL.1002" "new-task" "pending" >/dev/null

    # API only has the original task
    local api_file="$TEMP_DIR/partial_api.json"
    create_api_tasks_json "$api_file" "PARTIAL.1001:completed"

    # Conflict detection should identify missing task
    local conflict_output
    conflict_output=$(python3 "$CONFLICT_SCRIPT" "$ticket_dir" "$api_file" 2>/dev/null) || {
        fail_test "conflict detection failed"
        return
    }

    # No status conflicts (existing task matches)
    local conflict_count
    conflict_count=$(get_conflicts_count "$conflict_output")
    if [ "$conflict_count" != "0" ]; then
        fail_test "no status conflicts expected, got $conflict_count"
        return
    fi

    # But rehydration needed (new task missing from API)
    local rehydration
    rehydration=$(get_rehydration_needed "$conflict_output")
    if [ "$rehydration" != "true" ]; then
        fail_test "rehydration should be needed for missing task"
        return
    fi

    pass_test
}

# ============================================================================
# Integration Test: Session Start Hook
# ============================================================================

test_session_hook_detects_ticket() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Session hook - Detects active ticket from task files ... "

    local test_sdd_root="$TEMP_DIR/hook_test"
    local test_env_file="$TEMP_DIR/hook_env"

    mkdir -p "$test_sdd_root/tickets/HOOKTEST_test-ticket/tasks"
    touch "$test_env_file"

    # Create an incomplete task
    cat > "$test_sdd_root/tickets/HOOKTEST_test-ticket/tasks/HOOKTEST.1001_test-task.md" << 'EOF'
# Task: [HOOKTEST.1001]: Test Task

## Status
- [ ] **Task completed** - acceptance criteria met

## Summary
Test task for session hook testing.
EOF

    # Run session hook
    local exit_code=0
    SDD_ROOT_DIR="$test_sdd_root" CLAUDE_ENV_FILE="$test_env_file" node "$SETUP_HOOK" >/dev/null 2>&1 || exit_code=$?

    if [ $exit_code -ne 0 ]; then
        fail_test "session hook failed with exit $exit_code"
        return
    fi

    # Verify CLAUDE_TASK_LIST_ID was set
    if ! grep -q 'CLAUDE_TASK_LIST_ID="HOOKTEST"' "$test_env_file"; then
        fail_test "CLAUDE_TASK_LIST_ID not set correctly"
        return
    fi

    pass_test
}

test_session_hook_no_ticket_when_all_complete() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Session hook - No ticket when all tasks complete ... "

    local test_sdd_root="$TEMP_DIR/hook_complete_test"
    local test_env_file="$TEMP_DIR/hook_complete_env"

    mkdir -p "$test_sdd_root/tickets/COMPLETE_test-ticket/tasks"
    touch "$test_env_file"

    # Create a completed task
    cat > "$test_sdd_root/tickets/COMPLETE_test-ticket/tasks/COMPLETE.1001_test-task.md" << 'EOF'
# Task: [COMPLETE.1001]: Test Task

## Status
- [x] **Task completed** - acceptance criteria met

## Summary
Completed task.
EOF

    # Run session hook
    local exit_code=0
    SDD_ROOT_DIR="$test_sdd_root" CLAUDE_ENV_FILE="$test_env_file" node "$SETUP_HOOK" >/dev/null 2>&1 || exit_code=$?

    if [ $exit_code -ne 0 ]; then
        fail_test "session hook failed with exit $exit_code"
        return
    fi

    # CLAUDE_TASK_LIST_ID should NOT be set when all tasks are complete
    if grep -q 'CLAUDE_TASK_LIST_ID' "$test_env_file"; then
        fail_test "CLAUDE_TASK_LIST_ID should not be set when all tasks complete"
        return
    fi

    pass_test
}

# ============================================================================
# Integration Test: End-to-End Workflow
# ============================================================================

test_e2e_complete_workflow() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: E2E - Complete workflow (hydrate -> work -> sync -> verify) ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "WORKFLOW_test-workflow")

    # Step 1: Create initial tasks
    local task1
    task1=$(create_task_file "$ticket_dir/tasks" "WORKFLOW.1001" "first-task" "pending")
    local task2
    task2=$(create_task_file "$ticket_dir/tasks" "WORKFLOW.1002" "second-task" "pending" "WORKFLOW.1001")

    # Step 2: Initial hydration
    local hydrate_output
    hydrate_output=$(python3 "$HYDRATE_SCRIPT" "$ticket_dir" "E2E" 2>/dev/null) || {
        fail_test "initial hydration failed"
        return
    }

    # Verify dependency
    local blocked2
    blocked2=$(get_blocked_by "$hydrate_output" "WORKFLOW.1002")
    if [ "$blocked2" != "WORKFLOW.1001" ]; then
        fail_test "task 2 should be blocked by task 1"
        return
    fi

    # Step 3: Complete first task (simulate TaskUpdate)
    "$SYNC_SCRIPT" "WORKFLOW.1001" "completed" >/dev/null 2>&1 || {
        fail_test "sync for task 1 failed"
        return
    }

    # Step 4: Verify file updated
    if ! has_checked_checkbox "$task1"; then
        fail_test "task 1 checkbox should be checked"
        return
    fi

    # Step 5: Re-hydrate to verify consistent state
    hydrate_output=$(python3 "$HYDRATE_SCRIPT" "$ticket_dir" "WORKFLOW" 2>/dev/null) || {
        fail_test "re-hydration failed"
        return
    }

    local status1
    status1=$(get_task_status "$hydrate_output" "WORKFLOW.1001")
    if [ "$status1" != "completed" ]; then
        fail_test "re-hydrated task 1 should show completed"
        return
    fi

    # Step 6: Run conflict detection with matching API state
    local api_file="$TEMP_DIR/workflow_api.json"
    create_api_tasks_json "$api_file" "WORKFLOW.1001:completed" "WORKFLOW.1002:pending"

    local conflict_output
    conflict_output=$(python3 "$CONFLICT_SCRIPT" "$ticket_dir" "$api_file" 2>/dev/null) || {
        fail_test "conflict detection failed"
        return
    }

    local conflict_count
    conflict_count=$(get_conflicts_count "$conflict_output")
    if [ "$conflict_count" != "0" ]; then
        fail_test "no conflicts expected in consistent state"
        return
    fi

    pass_test
}

# ============================================================================
# Test Runner
# ============================================================================

run_all_tests() {
    printf "%s=== Phase 1 Integration Tests ===%s\n" "$BLUE" "$NC"
    printf "\n"

    # Hydration cycle tests
    printf "%s--- Hydration Cycle Tests ---%s\n" "$YELLOW" "$NC"
    test_hydration_simple_ticket
    test_hydration_phased_ticket
    test_hydration_complex_dependencies
    test_hydration_status_mapping

    # Sync cycle tests
    printf "\n"
    printf "%s--- Sync Cycle Tests ---%s\n" "$YELLOW" "$NC"
    test_sync_completed_updates_checkbox
    test_sync_pending_no_change
    test_sync_in_progress_no_change
    test_sync_idempotent

    # Conflict resolution tests
    printf "\n"
    printf "%s--- Conflict Resolution Tests ---%s\n" "$YELLOW" "$NC"
    test_conflict_file_wins_when_complete
    test_conflict_file_wins_when_pending
    test_conflict_no_conflict_when_matching
    test_conflict_in_progress_treated_as_pending

    # Round-trip tests
    printf "\n"
    printf "%s--- Round-Trip Tests ---%s\n" "$YELLOW" "$NC"
    test_roundtrip_fresh_ticket
    test_roundtrip_recovery_from_crash

    # Backward compatibility tests
    printf "\n"
    printf "%s--- Backward Compatibility Tests ---%s\n" "$YELLOW" "$NC"
    test_backward_compat_existing_ticket
    test_backward_compat_partial_sync

    # Session start hook tests
    printf "\n"
    printf "%s--- Session Start Hook Tests ---%s\n" "$YELLOW" "$NC"
    test_session_hook_detects_ticket
    test_session_hook_no_ticket_when_all_complete

    # End-to-end tests
    printf "\n"
    printf "%s--- End-to-End Workflow Tests ---%s\n" "$YELLOW" "$NC"
    test_e2e_complete_workflow

    # Summary
    printf "\n"
    printf "%s=== Test Summary ===%s\n" "$BLUE" "$NC"
    printf "Tests run: %d\n" "$TESTS_RUN"
    printf "Passed: %s%d%s\n" "$GREEN" "$TESTS_PASSED" "$NC"
    printf "Failed: %s%d%s\n" "$RED" "$TESTS_FAILED" "$NC"

    if [ "$TESTS_FAILED" -gt 0 ]; then
        printf "\n"
        printf "%sSome tests failed!%s\n" "$RED" "$NC"
        return 1
    else
        printf "\n"
        printf "%sAll tests passed!%s\n" "$GREEN" "$NC"
        return 0
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    # Trap to ensure cleanup
    trap cleanup EXIT

    # Setup
    setup

    # Verify all component scripts exist
    if [ ! -f "$HYDRATE_SCRIPT" ]; then
        printf "%sError: hydrate-tasks.py not found at %s%s\n" "$RED" "$HYDRATE_SCRIPT" "$NC"
        exit 1
    fi

    if [ ! -f "$CONFLICT_SCRIPT" ]; then
        printf "%sError: conflict-resolution.py not found at %s%s\n" "$RED" "$CONFLICT_SCRIPT" "$NC"
        exit 1
    fi

    if [ ! -f "$SYNC_SCRIPT" ]; then
        printf "%sError: sync-task-status.sh not found at %s%s\n" "$RED" "$SYNC_SCRIPT" "$NC"
        exit 1
    fi

    if [ ! -f "$SETUP_HOOK" ]; then
        printf "%sError: setup-sdd-env.js not found at %s%s\n" "$RED" "$SETUP_HOOK" "$NC"
        exit 1
    fi

    # Run tests
    run_all_tests
    exit_code=$?

    exit $exit_code
}

main
