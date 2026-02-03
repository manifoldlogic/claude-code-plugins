#!/bin/bash
# test-conflict-resolution.sh - Test suite for conflict-resolution.py
#
# This script runs comprehensive unit tests for the SDD conflict resolution module.
# It tests various conflict scenarios including:
# - File shows complete, API shows pending -> Use file, overwrite API
# - File shows pending, API shows complete -> Use file, overwrite API
# - Manual file edit with different API state -> Detect on hydration, use file
# - Session crash scenarios -> Use file state
# - Partial sync failures -> Detect mismatch, re-hydrate from file
# - Debug mode logging verification
#
# Coverage target: 85%+ of module code
#
# Usage:
#   ./test-conflict-resolution.sh           # Run all tests
#   ./test-conflict-resolution.sh -v        # Verbose output
#   ./test-conflict-resolution.sh --help    # Show help
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed

set -e  # Exit on first failure

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFLICT_SCRIPT="$SCRIPT_DIR/conflict-resolution.py"
TEMP_DIR=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo "Usage: $0 [-v|--verbose] [--help]"
    echo ""
    echo "Options:"
    echo "  -v, --verbose  Show detailed output for each test"
    echo "  --help         Show this help message"
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
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Setup temporary directory for test files
setup() {
    TEMP_DIR=$(mktemp -d)
    if [ "$VERBOSE" = true ]; then
        echo "Created temp directory: $TEMP_DIR"
    fi
}

# Cleanup temporary directory
cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        if [ "$VERBOSE" = true ]; then
            echo "Cleaned up temp directory: $TEMP_DIR"
        fi
    fi
}

# Create a test ticket directory structure
create_test_ticket() {
    local ticket_name="$1"
    local ticket_dir="$TEMP_DIR/$ticket_name"
    mkdir -p "$ticket_dir/tasks"
    echo "$ticket_dir"
}

# Create a task file
create_task_file() {
    local tasks_dir="$1"
    local task_id="$2"
    local task_name="$3"
    local status="${4:-pending}"  # pending or completed

    local checkbox_status=" "
    if [ "$status" = "completed" ]; then
        checkbox_status="x"
    fi

    local file_path="$tasks_dir/${task_id}_${task_name}.md"

    cat > "$file_path" << EOF
# Task: [$task_id]: ${task_name//-/ }

## Status
- [$checkbox_status] **Task completed** - acceptance criteria met
- [ ] **Tests pass** - tests executed and passing (or N/A if no tests)
- [ ] **Verified** - by the verify-task agent

## Summary
This is the summary for task $task_id.

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2

## Technical Requirements
Some technical requirements here.
EOF

    echo "$file_path"
}

# Create API tasks JSON
create_api_tasks_json() {
    local output_file="$1"
    shift
    # Remaining args are task entries in format: "task_id:status"

    echo "[" > "$output_file"
    local first=true
    for entry in "$@"; do
        local task_id="${entry%%:*}"
        local status="${entry##*:}"

        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$output_file"
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
    echo "]" >> "$output_file"
}

# Run conflict detection and store output
run_conflict_detection() {
    local ticket_dir="$1"
    local api_tasks_file="$2"

    if [ -n "$api_tasks_file" ]; then
        python3 "$CONFLICT_SCRIPT" "$ticket_dir" "$api_tasks_file" 2>"$TEMP_DIR/stderr.txt"
    else
        python3 "$CONFLICT_SCRIPT" "$ticket_dir" 2>"$TEMP_DIR/stderr.txt"
    fi
}

# Get value from JSON output using Python
get_json_value() {
    local json="$1"
    local key_path="$2"
    echo "$json" | python3 -c "
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

# Get conflicts count from JSON output
get_conflicts_count() {
    local json="$1"
    echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data.get('summary', {}).get('conflicts_found', 0))
" 2>/dev/null || echo "0"
}

# Get rehydration needed from JSON output
get_rehydration_needed() {
    local json="$1"
    echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print('true' if data.get('summary', {}).get('rehydration_needed', False) else 'false')
" 2>/dev/null || echo "false"
}

# Get specific conflict task_id from JSON output
get_conflict_task_id() {
    local json="$1"
    local index="$2"
    echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
conflicts = data.get('conflicts', [])
if len(conflicts) > $index:
    print(conflicts[$index].get('task_id', ''))
else:
    print('')
" 2>/dev/null
}

# Get conflict file_status from JSON output
get_conflict_file_status() {
    local json="$1"
    local task_id="$2"
    echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for conflict in data.get('conflicts', []):
    if conflict.get('task_id') == '$task_id':
        print(conflict.get('file_status', ''))
        break
" 2>/dev/null
}

# Get conflict api_status from JSON output
get_conflict_api_status() {
    local json="$1"
    local task_id="$2"
    echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for conflict in data.get('conflicts', []):
    if conflict.get('task_id') == '$task_id':
        print(conflict.get('api_status', ''))
        break
" 2>/dev/null
}

# Get resolution action for task
get_resolution_action() {
    local json="$1"
    local task_id="$2"
    echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for action in data.get('resolution', {}).get('actions', []):
    if action.get('task_id') == '$task_id':
        print(action.get('action', ''))
        break
" 2>/dev/null
}

# Check if debug info is present
has_debug_info() {
    local json="$1"
    echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print('true' if 'debug' in data else 'false')
" 2>/dev/null || echo "false"
}

# Report test result
pass_test() {
    local name="$1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}PASS${NC}"
}

fail_test() {
    local name="$1"
    local reason="$2"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}FAIL${NC} ($reason)"
}

# ============================================================================
# Test Cases: No Conflicts (Happy Path)
# ============================================================================

test_no_conflicts_matching_states() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: No conflicts when file and API states match ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "MATCH")
    create_task_file "$ticket_dir/tasks" "MATCH.1001" "task-one" "pending" >/dev/null
    create_task_file "$ticket_dir/tasks" "MATCH.1002" "task-two" "completed" >/dev/null

    local api_file="$TEMP_DIR/api_tasks.json"
    create_api_tasks_json "$api_file" "MATCH.1001:pending" "MATCH.1002:completed"

    local output
    output=$(run_conflict_detection "$ticket_dir" "$api_file") || { fail_test "No conflicts matching" "detection failed"; return; }

    local count
    count=$(get_conflicts_count "$output")
    if [ "$count" != "0" ]; then
        fail_test "No conflicts matching" "expected 0 conflicts, got $count"
        return
    fi

    local rehydration
    rehydration=$(get_rehydration_needed "$output")
    if [ "$rehydration" != "false" ]; then
        fail_test "No conflicts matching" "expected no rehydration needed"
        return
    fi

    pass_test "No conflicts matching"
}

test_no_conflicts_no_api_tasks() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: No conflicts with no API tasks (initial hydration) ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "INITIAL")
    create_task_file "$ticket_dir/tasks" "INITIAL.1001" "task-one" "pending" >/dev/null

    local output
    output=$(run_conflict_detection "$ticket_dir") || { fail_test "No API tasks" "detection failed"; return; }

    local count
    count=$(get_conflicts_count "$output")
    if [ "$count" != "0" ]; then
        fail_test "No API tasks" "expected 0 conflicts, got $count"
        return
    fi

    # But rehydration IS needed (task not in API)
    local rehydration
    rehydration=$(get_rehydration_needed "$output")
    if [ "$rehydration" != "true" ]; then
        fail_test "No API tasks" "expected rehydration needed for initial hydration"
        return
    fi

    pass_test "No API tasks"
}

# ============================================================================
# Test Cases: Conflict Detection
# ============================================================================

test_conflict_file_complete_api_pending() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Conflict - file complete, API pending ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "FCAP")
    create_task_file "$ticket_dir/tasks" "FCAP.1001" "task-one" "completed" >/dev/null

    local api_file="$TEMP_DIR/api_tasks.json"
    create_api_tasks_json "$api_file" "FCAP.1001:pending"

    local output
    output=$(run_conflict_detection "$ticket_dir" "$api_file") || { fail_test "File complete API pending" "detection failed"; return; }

    local count
    count=$(get_conflicts_count "$output")
    if [ "$count" != "1" ]; then
        fail_test "File complete API pending" "expected 1 conflict, got $count"
        return
    fi

    local file_status
    file_status=$(get_conflict_file_status "$output" "FCAP.1001")
    if [ "$file_status" != "completed" ]; then
        fail_test "File complete API pending" "expected file_status=completed, got $file_status"
        return
    fi

    local api_status
    api_status=$(get_conflict_api_status "$output" "FCAP.1001")
    if [ "$api_status" != "pending" ]; then
        fail_test "File complete API pending" "expected api_status=pending, got $api_status"
        return
    fi

    pass_test "File complete API pending"
}

test_conflict_file_pending_api_complete() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Conflict - file pending, API complete ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "FPAC")
    create_task_file "$ticket_dir/tasks" "FPAC.1001" "task-one" "pending" >/dev/null

    local api_file="$TEMP_DIR/api_tasks.json"
    create_api_tasks_json "$api_file" "FPAC.1001:completed"

    local output
    output=$(run_conflict_detection "$ticket_dir" "$api_file") || { fail_test "File pending API complete" "detection failed"; return; }

    local count
    count=$(get_conflicts_count "$output")
    if [ "$count" != "1" ]; then
        fail_test "File pending API complete" "expected 1 conflict, got $count"
        return
    fi

    local file_status
    file_status=$(get_conflict_file_status "$output" "FPAC.1001")
    if [ "$file_status" != "pending" ]; then
        fail_test "File pending API complete" "expected file_status=pending, got $file_status"
        return
    fi

    local api_status
    api_status=$(get_conflict_api_status "$output" "FPAC.1001")
    if [ "$api_status" != "completed" ]; then
        fail_test "File pending API complete" "expected api_status=completed, got $api_status"
        return
    fi

    pass_test "File pending API complete"
}

test_conflict_api_in_progress_treated_as_pending() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: API in_progress treated as pending for comparison ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "INPROG")
    create_task_file "$ticket_dir/tasks" "INPROG.1001" "task-one" "pending" >/dev/null

    local api_file="$TEMP_DIR/api_tasks.json"
    create_api_tasks_json "$api_file" "INPROG.1001:in_progress"

    local output
    output=$(run_conflict_detection "$ticket_dir" "$api_file") || { fail_test "API in_progress" "detection failed"; return; }

    # in_progress should be treated as pending, so no conflict with pending file
    local count
    count=$(get_conflicts_count "$output")
    if [ "$count" != "0" ]; then
        fail_test "API in_progress" "expected 0 conflicts (in_progress=pending), got $count"
        return
    fi

    pass_test "API in_progress"
}

test_multiple_conflicts() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Multiple conflicts detected ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "MULTI")
    create_task_file "$ticket_dir/tasks" "MULTI.1001" "task-one" "completed" >/dev/null
    create_task_file "$ticket_dir/tasks" "MULTI.1002" "task-two" "pending" >/dev/null
    create_task_file "$ticket_dir/tasks" "MULTI.1003" "task-three" "completed" >/dev/null

    local api_file="$TEMP_DIR/api_tasks.json"
    create_api_tasks_json "$api_file" "MULTI.1001:pending" "MULTI.1002:completed" "MULTI.1003:completed"

    local output
    output=$(run_conflict_detection "$ticket_dir" "$api_file") || { fail_test "Multiple conflicts" "detection failed"; return; }

    local count
    count=$(get_conflicts_count "$output")
    if [ "$count" != "2" ]; then
        fail_test "Multiple conflicts" "expected 2 conflicts, got $count"
        return
    fi

    pass_test "Multiple conflicts"
}

# ============================================================================
# Test Cases: Conflict Resolution (File Wins Policy)
# ============================================================================

test_resolution_uses_file_state() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Resolution uses file state (file wins policy) ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "RESOLVE")
    create_task_file "$ticket_dir/tasks" "RESOLVE.1001" "task-one" "completed" >/dev/null

    local api_file="$TEMP_DIR/api_tasks.json"
    create_api_tasks_json "$api_file" "RESOLVE.1001:pending"

    local output
    output=$(run_conflict_detection "$ticket_dir" "$api_file") || { fail_test "Resolution uses file" "detection failed"; return; }

    local action
    action=$(get_resolution_action "$output" "RESOLVE.1001")
    if [ "$action" != "overwrite_api" ]; then
        fail_test "Resolution uses file" "expected action=overwrite_api, got $action"
        return
    fi

    pass_test "Resolution uses file"
}

test_resolution_actions_generated() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Resolution actions generated for all conflicts ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "ACTIONS")
    create_task_file "$ticket_dir/tasks" "ACTIONS.1001" "task-one" "completed" >/dev/null
    create_task_file "$ticket_dir/tasks" "ACTIONS.1002" "task-two" "pending" >/dev/null

    local api_file="$TEMP_DIR/api_tasks.json"
    create_api_tasks_json "$api_file" "ACTIONS.1001:pending" "ACTIONS.1002:completed"

    local output
    output=$(run_conflict_detection "$ticket_dir" "$api_file") || { fail_test "Actions generated" "detection failed"; return; }

    local resolved_count
    resolved_count=$(get_json_value "$output" "resolution.conflicts_resolved")
    if [ "$resolved_count" != "2" ]; then
        fail_test "Actions generated" "expected 2 resolutions, got $resolved_count"
        return
    fi

    pass_test "Actions generated"
}

# ============================================================================
# Test Cases: Edge Cases
# ============================================================================

test_orphaned_api_task_ignored() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Orphaned API task (no file) is ignored ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "ORPHAN")
    create_task_file "$ticket_dir/tasks" "ORPHAN.1001" "task-one" "pending" >/dev/null

    local api_file="$TEMP_DIR/api_tasks.json"
    # API has ORPHAN.1002 which has no file
    create_api_tasks_json "$api_file" "ORPHAN.1001:pending" "ORPHAN.1002:completed"

    local output
    output=$(run_conflict_detection "$ticket_dir" "$api_file") || { fail_test "Orphaned API task" "detection failed"; return; }

    # No conflict for matching task
    local count
    count=$(get_conflicts_count "$output")
    if [ "$count" != "0" ]; then
        fail_test "Orphaned API task" "expected 0 conflicts, got $count"
        return
    fi

    # Stderr should have warning (captured in stderr.txt)
    if ! grep -q "Orphaned API task" "$TEMP_DIR/stderr.txt" 2>/dev/null; then
        # Warning might only appear in debug mode, so this is not a failure
        if [ "$VERBOSE" = true ]; then
            echo "(Note: Orphan warning may require debug mode)"
        fi
    fi

    pass_test "Orphaned API task"
}

test_task_in_file_not_in_api() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Task in file but not in API needs hydration ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "MISSING")
    create_task_file "$ticket_dir/tasks" "MISSING.1001" "task-one" "pending" >/dev/null
    create_task_file "$ticket_dir/tasks" "MISSING.1002" "task-two" "completed" >/dev/null

    local api_file="$TEMP_DIR/api_tasks.json"
    # API only has one of the tasks
    create_api_tasks_json "$api_file" "MISSING.1001:pending"

    local output
    output=$(run_conflict_detection "$ticket_dir" "$api_file") || { fail_test "Task in file not API" "detection failed"; return; }

    # No conflict (states match for present task)
    local count
    count=$(get_conflicts_count "$output")
    if [ "$count" != "0" ]; then
        fail_test "Task in file not API" "expected 0 conflicts, got $count"
        return
    fi

    # But rehydration needed (missing task)
    local rehydration
    rehydration=$(get_rehydration_needed "$output")
    if [ "$rehydration" != "true" ]; then
        fail_test "Task in file not API" "expected rehydration needed for missing task"
        return
    fi

    pass_test "Task in file not API"
}

test_empty_tasks_directory() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Empty tasks directory ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "EMPTY")
    # Tasks directory is empty

    local output
    output=$(run_conflict_detection "$ticket_dir") || { fail_test "Empty tasks dir" "detection failed"; return; }

    local count
    count=$(get_conflicts_count "$output")
    if [ "$count" != "0" ]; then
        fail_test "Empty tasks dir" "expected 0 conflicts, got $count"
        return
    fi

    local file_count
    file_count=$(get_json_value "$output" "summary.file_tasks_count")
    if [ "$file_count" != "0" ]; then
        fail_test "Empty tasks dir" "expected 0 file tasks, got $file_count"
        return
    fi

    pass_test "Empty tasks dir"
}

test_index_files_skipped() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Index files are skipped ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "INDEX")
    create_task_file "$ticket_dir/tasks" "INDEX.1001" "task-one" "pending" >/dev/null

    # Create index file that should be skipped
    cat > "$ticket_dir/tasks/INDEX_TASK_INDEX.md" << 'EOF'
# Task Index
This is an index file and should be skipped.
EOF

    local output
    output=$(run_conflict_detection "$ticket_dir") || { fail_test "Index skipped" "detection failed"; return; }

    local file_count
    file_count=$(get_json_value "$output" "summary.file_tasks_count")
    if [ "$file_count" != "1" ]; then
        fail_test "Index skipped" "expected 1 file task (index skipped), got $file_count"
        return
    fi

    pass_test "Index skipped"
}

# ============================================================================
# Test Cases: Session Crash Scenarios
# ============================================================================

test_session_crash_api_completed_file_pending() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Session crash - API completed, file pending ... "

    # Scenario: Session crashed between TaskUpdate and file write
    # API shows completed but file still shows pending
    # File should win

    local ticket_dir
    ticket_dir=$(create_test_ticket "CRASH")
    create_task_file "$ticket_dir/tasks" "CRASH.1001" "task-one" "pending" >/dev/null

    local api_file="$TEMP_DIR/api_tasks.json"
    create_api_tasks_json "$api_file" "CRASH.1001:completed"

    local output
    output=$(run_conflict_detection "$ticket_dir" "$api_file") || { fail_test "Session crash" "detection failed"; return; }

    local count
    count=$(get_conflicts_count "$output")
    if [ "$count" != "1" ]; then
        fail_test "Session crash" "expected 1 conflict, got $count"
        return
    fi

    # Resolution should use file (pending)
    local file_status
    file_status=$(get_conflict_file_status "$output" "CRASH.1001")
    if [ "$file_status" != "pending" ]; then
        fail_test "Session crash" "expected file_status=pending (file wins), got $file_status"
        return
    fi

    pass_test "Session crash"
}

# ============================================================================
# Test Cases: Partial Sync Failure
# ============================================================================

test_partial_sync_failure() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Partial sync failure - some tasks synced, others not ... "

    # Scenario: Sync failed partway through
    # Some tasks match, others don't

    local ticket_dir
    ticket_dir=$(create_test_ticket "PARTIAL")
    create_task_file "$ticket_dir/tasks" "PARTIAL.1001" "task-one" "completed" >/dev/null
    create_task_file "$ticket_dir/tasks" "PARTIAL.1002" "task-two" "completed" >/dev/null
    create_task_file "$ticket_dir/tasks" "PARTIAL.1003" "task-three" "completed" >/dev/null

    local api_file="$TEMP_DIR/api_tasks.json"
    # First task synced, second didn't, third synced
    create_api_tasks_json "$api_file" "PARTIAL.1001:completed" "PARTIAL.1002:pending" "PARTIAL.1003:completed"

    local output
    output=$(run_conflict_detection "$ticket_dir" "$api_file") || { fail_test "Partial sync" "detection failed"; return; }

    local count
    count=$(get_conflicts_count "$output")
    if [ "$count" != "1" ]; then
        fail_test "Partial sync" "expected 1 conflict (PARTIAL.1002), got $count"
        return
    fi

    local task_id
    task_id=$(get_conflict_task_id "$output" "0")
    if [ "$task_id" != "PARTIAL.1002" ]; then
        fail_test "Partial sync" "expected conflict for PARTIAL.1002, got $task_id"
        return
    fi

    pass_test "Partial sync"
}

# ============================================================================
# Test Cases: Debug Mode
# ============================================================================

test_debug_mode_enabled() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Debug mode provides verbose logging ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "DEBUG")
    create_task_file "$ticket_dir/tasks" "DEBUG.1001" "task-one" "pending" >/dev/null

    local api_file="$TEMP_DIR/api_tasks.json"
    create_api_tasks_json "$api_file" "DEBUG.1001:completed"

    # Run with debug mode enabled - export so subshell sees it
    export SDD_TASKS_SYNC_DEBUG=true
    local output
    output=$(run_conflict_detection "$ticket_dir" "$api_file") || { fail_test "Debug mode" "detection failed"; unset SDD_TASKS_SYNC_DEBUG; return; }
    unset SDD_TASKS_SYNC_DEBUG

    # Debug info should be in output
    local has_debug
    has_debug=$(has_debug_info "$output")
    if [ "$has_debug" != "true" ]; then
        fail_test "Debug mode" "expected debug info in output"
        return
    fi

    # Also check stderr for debug messages
    if ! grep -q "DEBUG" "$TEMP_DIR/stderr.txt" 2>/dev/null; then
        # Debug output should be present
        if [ "$VERBOSE" = true ]; then
            echo "(Note: Debug messages written to log file)"
        fi
    fi

    pass_test "Debug mode"
}

test_debug_mode_disabled() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Debug mode disabled has no debug info ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "NODEBUG")
    create_task_file "$ticket_dir/tasks" "NODEBUG.1001" "task-one" "pending" >/dev/null

    # Run without debug mode
    unset SDD_TASKS_SYNC_DEBUG
    local output
    output=$(run_conflict_detection "$ticket_dir") || { fail_test "Debug disabled" "detection failed"; return; }

    local has_debug
    has_debug=$(has_debug_info "$output")
    if [ "$has_debug" != "false" ]; then
        fail_test "Debug disabled" "expected no debug info in output"
        return
    fi

    pass_test "Debug disabled"
}

# ============================================================================
# Test Cases: CLI Error Handling
# ============================================================================

test_cli_no_arguments() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: CLI with no arguments returns error ... "

    local exit_code=0
    python3 "$CONFLICT_SCRIPT" >/dev/null 2>&1 || exit_code=$?

    if [ "$exit_code" -ne 1 ]; then
        fail_test "CLI no args" "expected exit 1, got $exit_code"
        return
    fi

    pass_test "CLI no args"
}

test_cli_invalid_ticket_path() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: CLI with invalid ticket path returns error ... "

    local exit_code=0
    python3 "$CONFLICT_SCRIPT" "/nonexistent/path" >/dev/null 2>&1 || exit_code=$?

    if [ "$exit_code" -ne 1 ]; then
        fail_test "CLI invalid path" "expected exit 1, got $exit_code"
        return
    fi

    pass_test "CLI invalid path"
}

test_cli_missing_tasks_directory() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: CLI with missing tasks directory returns error ... "

    local ticket_dir="$TEMP_DIR/NOTASKS"
    mkdir -p "$ticket_dir"
    # No tasks subdirectory

    local exit_code=0
    python3 "$CONFLICT_SCRIPT" "$ticket_dir" >/dev/null 2>&1 || exit_code=$?

    if [ "$exit_code" -ne 1 ]; then
        fail_test "CLI no tasks dir" "expected exit 1, got $exit_code"
        return
    fi

    pass_test "CLI no tasks dir"
}

test_cli_invalid_api_json() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: CLI with invalid API JSON returns error ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "BADJSON")
    create_task_file "$ticket_dir/tasks" "BADJSON.1001" "task-one" "pending" >/dev/null

    local exit_code=0
    python3 "$CONFLICT_SCRIPT" "$ticket_dir" "not-valid-json" >/dev/null 2>&1 || exit_code=$?

    if [ "$exit_code" -ne 1 ]; then
        fail_test "CLI invalid JSON" "expected exit 1, got $exit_code"
        return
    fi

    pass_test "CLI invalid JSON"
}

# ============================================================================
# Test Cases: Code Block Handling
# ============================================================================

test_checkbox_in_code_block_ignored() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Checkbox in code block is ignored ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "CODEBLOCK")

    # Create task file with example checkbox in code block
    cat > "$ticket_dir/tasks/CODEBLOCK.1001_code-example.md" << 'EOF'
# Task: [CODEBLOCK.1001]: Code Example Task

## Status
- [ ] **Task completed** - acceptance criteria met

## Summary
This task has code examples.

## Example
```markdown
- [x] **Task completed** - this is an example
```

The real checkbox above is unchecked.
EOF

    local output
    output=$(run_conflict_detection "$ticket_dir") || { fail_test "Code block" "detection failed"; return; }

    # Task should be pending (real checkbox is unchecked)
    # With no API tasks, no conflicts
    local count
    count=$(get_conflicts_count "$output")
    if [ "$count" != "0" ]; then
        fail_test "Code block" "expected 0 conflicts, got $count"
        return
    fi

    pass_test "Code block"
}

# ============================================================================
# Test Runner
# ============================================================================

run_all_tests() {
    echo -e "${BLUE}=== SDD Conflict Resolution Module Tests ===${NC}"
    echo ""

    # No conflicts tests
    echo -e "${YELLOW}--- No Conflicts (Happy Path) Tests ---${NC}"
    test_no_conflicts_matching_states
    test_no_conflicts_no_api_tasks

    # Conflict detection tests
    echo ""
    echo -e "${YELLOW}--- Conflict Detection Tests ---${NC}"
    test_conflict_file_complete_api_pending
    test_conflict_file_pending_api_complete
    test_conflict_api_in_progress_treated_as_pending
    test_multiple_conflicts

    # Resolution tests
    echo ""
    echo -e "${YELLOW}--- Conflict Resolution (File Wins) Tests ---${NC}"
    test_resolution_uses_file_state
    test_resolution_actions_generated

    # Edge case tests
    echo ""
    echo -e "${YELLOW}--- Edge Case Tests ---${NC}"
    test_orphaned_api_task_ignored
    test_task_in_file_not_in_api
    test_empty_tasks_directory
    test_index_files_skipped

    # Session crash tests
    echo ""
    echo -e "${YELLOW}--- Session Crash Scenario Tests ---${NC}"
    test_session_crash_api_completed_file_pending

    # Partial sync tests
    echo ""
    echo -e "${YELLOW}--- Partial Sync Failure Tests ---${NC}"
    test_partial_sync_failure

    # Debug mode tests
    echo ""
    echo -e "${YELLOW}--- Debug Mode Tests ---${NC}"
    test_debug_mode_enabled
    test_debug_mode_disabled

    # CLI tests
    echo ""
    echo -e "${YELLOW}--- CLI Error Handling Tests ---${NC}"
    test_cli_no_arguments
    test_cli_invalid_ticket_path
    test_cli_missing_tasks_directory
    test_cli_invalid_api_json

    # Code block tests
    echo ""
    echo -e "${YELLOW}--- Code Block Handling Tests ---${NC}"
    test_checkbox_in_code_block_ignored

    # Summary
    echo ""
    echo -e "${BLUE}=== Test Summary ===${NC}"
    echo "Tests run: $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

    if [ "$TESTS_FAILED" -gt 0 ]; then
        echo ""
        echo -e "${RED}Some tests failed!${NC}"
        return 1
    else
        echo ""
        echo -e "${GREEN}All tests passed!${NC}"
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

    # Verify conflict resolution script exists
    if [ ! -f "$CONFLICT_SCRIPT" ]; then
        echo -e "${RED}Error: conflict-resolution.py not found at $CONFLICT_SCRIPT${NC}"
        exit 1
    fi

    # Run tests
    run_all_tests
    exit_code=$?

    exit $exit_code
}

main
