#!/bin/bash
# test-hydrate-tasks.sh - Test suite for hydrate-tasks.py
#
# This script runs comprehensive unit tests for the SDD task hydration module.
# It tests various scenarios including:
# - Simple task parsing (single task, status checkboxes)
# - Phased task ordering (Phase 0, 1, 2 dependencies)
# - Explicit dependency extraction from task files
# - Malformed file handling (graceful skip with warning)
# - Edge cases (empty directory, no tasks, invalid formats)
#
# Usage:
#   ./test-hydrate-tasks.sh           # Run all tests
#   ./test-hydrate-tasks.sh -v        # Verbose output
#   ./test-hydrate-tasks.sh --help    # Show help
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed

set -e  # Exit on first failure

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HYDRATE_SCRIPT="$SCRIPT_DIR/hydrate-tasks.py"
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
    local deps="${5:-}"  # comma-separated dependencies

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

EOF

    # Add dependencies section if provided
    if [ -n "$deps" ]; then
        echo "## Dependencies" >> "$file_path"
        IFS=',' read -ra DEP_ARRAY <<< "$deps"
        for dep in "${DEP_ARRAY[@]}"; do
            echo "- $dep" >> "$file_path"
        done
        echo "" >> "$file_path"
    fi

    echo "## Technical Requirements" >> "$file_path"
    echo "Some technical requirements here." >> "$file_path"
}

# Run hydration and store output
run_hydration() {
    local ticket_dir="$1"
    python3 "$HYDRATE_SCRIPT" "$ticket_dir" "TEST-TASK-LIST" 2>"$TEMP_DIR/stderr.txt"
}

# Get task count from JSON output
get_task_count() {
    local json="$1"
    echo "$json" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0"
}

# Get task status from JSON output
get_task_status() {
    local json="$1"
    local task_id="$2"
    echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for task in data:
    if task['task_id'] == '$task_id':
        print(task['status'])
        break
" 2>/dev/null
}

# Get blockedBy list from JSON output (comma-separated, sorted)
get_blocked_by() {
    local json="$1"
    local task_id="$2"
    echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for task in data:
    if task['task_id'] == '$task_id':
        print(','.join(sorted(task['blockedBy'])))
        break
" 2>/dev/null
}

# Get task IDs from JSON output (comma-separated, sorted)
get_task_ids() {
    local json="$1"
    echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(','.join(sorted([t['task_id'] for t in data])))
" 2>/dev/null
}

# Get description from JSON output
get_description() {
    local json="$1"
    local task_id="$2"
    echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for task in data:
    if task['task_id'] == '$task_id':
        print(task['description'])
        break
" 2>/dev/null
}

# Get activeForm from JSON output
get_active_form() {
    local json="$1"
    local task_id="$2"
    echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for task in data:
    if task['task_id'] == '$task_id':
        print(task['activeForm'])
        break
" 2>/dev/null
}

# Check if metadata has required fields
has_metadata() {
    local json="$1"
    echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if not data:
    print('no')
    sys.exit(0)
task = data[0]
meta = task.get('metadata', {})
if 'file_path' in meta and 'phase' in meta and 'source' in meta:
    print('yes')
else:
    print('no')
" 2>/dev/null
}

# Get task_list_id from JSON output
get_task_list_id() {
    local json="$1"
    echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if data:
    print(data[0]['task_list_id'])
" 2>/dev/null
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
# Test Cases
# ============================================================================

test_single_task_pending() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Single pending task ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "SINGLE")
    create_task_file "$ticket_dir/tasks" "SINGLE.1001" "simple-task" "pending"

    local output
    output=$(run_hydration "$ticket_dir") || { fail_test "Single pending task" "hydration failed"; return; }

    local count
    count=$(get_task_count "$output")
    if [ "$count" != "1" ]; then
        fail_test "Single pending task" "expected 1 task, got $count"
        return
    fi

    local status
    status=$(get_task_status "$output" "SINGLE.1001")
    if [ "$status" != "pending" ]; then
        fail_test "Single pending task" "expected pending status, got $status"
        return
    fi

    pass_test "Single pending task"
}

test_single_task_completed() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Single completed task ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "DONE")
    create_task_file "$ticket_dir/tasks" "DONE.1001" "completed-task" "completed"

    local output
    output=$(run_hydration "$ticket_dir") || { fail_test "Single completed task" "hydration failed"; return; }

    local status
    status=$(get_task_status "$output" "DONE.1001")
    if [ "$status" != "completed" ]; then
        fail_test "Single completed task" "expected completed status, got $status"
        return
    fi

    pass_test "Single completed task"
}

test_multiple_tasks_same_phase() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Multiple tasks in same phase ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "MULTI")
    create_task_file "$ticket_dir/tasks" "MULTI.1001" "first-task" "pending"
    create_task_file "$ticket_dir/tasks" "MULTI.1002" "second-task" "pending"
    create_task_file "$ticket_dir/tasks" "MULTI.1003" "third-task" "completed"

    local output
    output=$(run_hydration "$ticket_dir") || { fail_test "Multiple tasks same phase" "hydration failed"; return; }

    local count
    count=$(get_task_count "$output")
    if [ "$count" != "3" ]; then
        fail_test "Multiple tasks same phase" "expected 3 tasks, got $count"
        return
    fi

    pass_test "Multiple tasks same phase"
}

test_phase_dependencies() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Phase dependencies calculated correctly ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "PHASE")
    create_task_file "$ticket_dir/tasks" "PHASE.0001" "phase-zero-task" "completed"
    create_task_file "$ticket_dir/tasks" "PHASE.1001" "phase-one-task" "pending"
    create_task_file "$ticket_dir/tasks" "PHASE.2001" "phase-two-task" "pending"

    local output
    output=$(run_hydration "$ticket_dir") || { fail_test "Phase dependencies" "hydration failed"; return; }

    # Phase 0 should have no blockers
    local blocked0
    blocked0=$(get_blocked_by "$output" "PHASE.0001")
    if [ -n "$blocked0" ]; then
        fail_test "Phase dependencies" "Phase 0 task should have no blockers, got '$blocked0'"
        return
    fi

    # Phase 1 should be blocked by Phase 0
    local blocked1
    blocked1=$(get_blocked_by "$output" "PHASE.1001")
    if [ "$blocked1" != "PHASE.0001" ]; then
        fail_test "Phase dependencies" "Phase 1 should be blocked by PHASE.0001, got '$blocked1'"
        return
    fi

    # Phase 2 should be blocked by Phase 1
    local blocked2
    blocked2=$(get_blocked_by "$output" "PHASE.2001")
    if [ "$blocked2" != "PHASE.1001" ]; then
        fail_test "Phase dependencies" "Phase 2 should be blocked by PHASE.1001, got '$blocked2'"
        return
    fi

    pass_test "Phase dependencies"
}

test_explicit_dependencies() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Explicit dependencies extracted correctly ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "DEPS")
    create_task_file "$ticket_dir/tasks" "DEPS.1001" "base-task" "pending"
    create_task_file "$ticket_dir/tasks" "DEPS.1002" "depends-on-first" "pending" "DEPS.1001"
    create_task_file "$ticket_dir/tasks" "DEPS.1003" "depends-on-both" "pending" "DEPS.1001,DEPS.1002"

    local output
    output=$(run_hydration "$ticket_dir") || { fail_test "Explicit dependencies" "hydration failed"; return; }

    # First task has no deps
    local blocked1
    blocked1=$(get_blocked_by "$output" "DEPS.1001")
    if [ -n "$blocked1" ]; then
        fail_test "Explicit dependencies" "DEPS.1001 should have no blockers, got '$blocked1'"
        return
    fi

    # Second task depends on first
    local blocked2
    blocked2=$(get_blocked_by "$output" "DEPS.1002")
    if [ "$blocked2" != "DEPS.1001" ]; then
        fail_test "Explicit dependencies" "DEPS.1002 should be blocked by DEPS.1001, got '$blocked2'"
        return
    fi

    # Third task depends on both
    local blocked3
    blocked3=$(get_blocked_by "$output" "DEPS.1003")
    if [ "$blocked3" != "DEPS.1001,DEPS.1002" ]; then
        fail_test "Explicit dependencies" "DEPS.1003 should be blocked by DEPS.1001,DEPS.1002, got '$blocked3'"
        return
    fi

    pass_test "Explicit dependencies"
}

test_combined_phase_and_explicit_deps() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Combined phase and explicit dependencies ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "COMBO")
    create_task_file "$ticket_dir/tasks" "COMBO.0001" "phase-zero" "completed"
    create_task_file "$ticket_dir/tasks" "COMBO.0002" "phase-zero-two" "completed" "COMBO.0001"
    create_task_file "$ticket_dir/tasks" "COMBO.1001" "phase-one" "pending"
    create_task_file "$ticket_dir/tasks" "COMBO.1002" "phase-one-two" "pending" "COMBO.1001"

    local output
    output=$(run_hydration "$ticket_dir") || { fail_test "Combined deps" "hydration failed"; return; }

    # Phase 1 task 2 has phase deps + explicit dep on 1001
    local blocked
    blocked=$(get_blocked_by "$output" "COMBO.1002")
    if [ "$blocked" != "COMBO.0001,COMBO.0002,COMBO.1001" ]; then
        fail_test "Combined deps" "COMBO.1002 expected 'COMBO.0001,COMBO.0002,COMBO.1001', got '$blocked'"
        return
    fi

    pass_test "Combined deps"
}

test_empty_tasks_directory() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Empty tasks directory returns empty list ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "EMPTY")
    # Tasks directory exists but is empty

    local output
    output=$(run_hydration "$ticket_dir") || { fail_test "Empty tasks dir" "hydration failed"; return; }

    local count
    count=$(get_task_count "$output")
    if [ "$count" != "0" ]; then
        fail_test "Empty tasks dir" "expected 0 tasks, got $count"
        return
    fi

    pass_test "Empty tasks dir"
}

test_no_tasks_directory() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Missing tasks directory returns error ... "

    local ticket_dir="$TEMP_DIR/NOTASKS"
    mkdir -p "$ticket_dir"
    # No tasks subdirectory

    local exit_code=0
    python3 "$HYDRATE_SCRIPT" "$ticket_dir" "TEST-TASK-LIST" >/dev/null 2>&1 || exit_code=$?

    if [ "$exit_code" -ne 1 ]; then
        fail_test "No tasks dir" "expected exit 1, got $exit_code"
        return
    fi

    pass_test "No tasks dir"
}

test_nonexistent_directory() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Nonexistent directory returns error ... "

    local exit_code=0
    python3 "$HYDRATE_SCRIPT" "/nonexistent/path/to/ticket" "TEST-TASK-LIST" >/dev/null 2>&1 || exit_code=$?

    if [ "$exit_code" -ne 1 ]; then
        fail_test "Nonexistent dir" "expected exit 1, got $exit_code"
        return
    fi

    pass_test "Nonexistent dir"
}

test_index_file_skipped() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Index files are skipped ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "INDEX")
    create_task_file "$ticket_dir/tasks" "INDEX.1001" "regular-task" "pending"

    # Create an index file that should be skipped
    cat > "$ticket_dir/tasks/INDEX_TASK_INDEX.md" << 'EOF'
# Task Index
This is an index file and should be skipped.
EOF

    local output
    output=$(run_hydration "$ticket_dir") || { fail_test "Index skipped" "hydration failed"; return; }

    local count
    count=$(get_task_count "$output")
    if [ "$count" != "1" ]; then
        fail_test "Index skipped" "expected 1 task (index should be skipped), got $count"
        return
    fi

    pass_test "Index skipped"
}

test_malformed_task_file_handled() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Malformed task files handled gracefully ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "MALFORMED")
    create_task_file "$ticket_dir/tasks" "MALFORMED.1001" "valid-task" "pending"

    # Create a malformed file (no Status section checkbox)
    cat > "$ticket_dir/tasks/MALFORMED.1002_broken.md" << 'EOF'
# This file has no proper status section
Some random content without proper structure.
EOF

    create_task_file "$ticket_dir/tasks" "MALFORMED.1003" "another-valid" "pending"

    local output
    output=$(run_hydration "$ticket_dir") || { fail_test "Malformed handled" "hydration failed"; return; }

    local count
    count=$(get_task_count "$output")
    if [ "$count" != "3" ]; then
        fail_test "Malformed handled" "expected 3 tasks (malformed still parses), got $count"
        return
    fi

    pass_test "Malformed handled"
}

test_active_form_generation() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Active form generated for tasks ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "ACTIVE")

    # Create a task file with a verb-starting title
    local task_file="$ticket_dir/tasks/ACTIVE.1001_implement-feature.md"
    cat > "$task_file" << 'EOF'
# Task: [ACTIVE.1001]: Implement the feature

## Status
- [ ] **Task completed** - acceptance criteria met

## Summary
Implementing a feature.
EOF

    local output
    output=$(run_hydration "$ticket_dir") || { fail_test "Active form" "hydration failed"; return; }

    local active_form
    active_form=$(get_active_form "$output" "ACTIVE.1001")
    if [ "$active_form" != "Implementing the feature" ]; then
        fail_test "Active form" "expected 'Implementing the feature', got '$active_form'"
        return
    fi

    pass_test "Active form"
}

test_metadata_included() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Metadata included in task output ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "META")
    create_task_file "$ticket_dir/tasks" "META.1001" "metadata-test" "pending"

    local output
    output=$(run_hydration "$ticket_dir") || { fail_test "Metadata included" "hydration failed"; return; }

    local has_meta
    has_meta=$(has_metadata "$output")
    if [ "$has_meta" != "yes" ]; then
        fail_test "Metadata included" "metadata fields missing"
        return
    fi

    pass_test "Metadata included"
}

test_task_list_id_in_output() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Task list ID included in output ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "LISTID")
    create_task_file "$ticket_dir/tasks" "LISTID.1001" "list-id-test" "pending"

    local output
    output=$(run_hydration "$ticket_dir") || { fail_test "Task list ID" "hydration failed"; return; }

    local list_id
    list_id=$(get_task_list_id "$output")
    if [ "$list_id" != "TEST-TASK-LIST" ]; then
        fail_test "Task list ID" "expected 'TEST-TASK-LIST', got '$list_id'"
        return
    fi

    pass_test "Task list ID"
}

test_three_phases() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Three phase dependency chain ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "THREEPHASE")
    create_task_file "$ticket_dir/tasks" "THREEPHASE.1001" "phase-one-a" "pending"
    create_task_file "$ticket_dir/tasks" "THREEPHASE.1002" "phase-one-b" "pending"
    create_task_file "$ticket_dir/tasks" "THREEPHASE.2001" "phase-two-a" "pending"
    create_task_file "$ticket_dir/tasks" "THREEPHASE.3001" "phase-three-a" "pending"

    local output
    output=$(run_hydration "$ticket_dir") || { fail_test "Three phases" "hydration failed"; return; }

    # Phase 1 tasks have no phase deps
    local blocked1a
    blocked1a=$(get_blocked_by "$output" "THREEPHASE.1001")
    if [ -n "$blocked1a" ]; then
        fail_test "Three phases" "Phase 1 task should have no blockers, got '$blocked1a'"
        return
    fi

    # Phase 2 blocked by all phase 1
    local blocked2
    blocked2=$(get_blocked_by "$output" "THREEPHASE.2001")
    if [ "$blocked2" != "THREEPHASE.1001,THREEPHASE.1002" ]; then
        fail_test "Three phases" "Phase 2 expected blockers 'THREEPHASE.1001,THREEPHASE.1002', got '$blocked2'"
        return
    fi

    # Phase 3 blocked by all phase 2
    local blocked3
    blocked3=$(get_blocked_by "$output" "THREEPHASE.3001")
    if [ "$blocked3" != "THREEPHASE.2001" ]; then
        fail_test "Three phases" "Phase 3 expected blocker 'THREEPHASE.2001', got '$blocked3'"
        return
    fi

    pass_test "Three phases"
}

test_dependency_outside_ticket_ignored() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: External dependencies are ignored ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "EXTERNAL")
    create_task_file "$ticket_dir/tasks" "EXTERNAL.1001" "has-external-dep" "pending" "OTHER.9999"

    local output
    output=$(run_hydration "$ticket_dir") || { fail_test "External deps ignored" "hydration failed"; return; }

    local blocked
    blocked=$(get_blocked_by "$output" "EXTERNAL.1001")
    if [ -n "$blocked" ]; then
        fail_test "External deps ignored" "expected no blockers (external ignored), got '$blocked'"
        return
    fi

    pass_test "External deps ignored"
}

test_summary_extraction() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Summary extraction works correctly ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "SUMMARY")

    local task_file="$ticket_dir/tasks/SUMMARY.1001_summary-test.md"
    cat > "$task_file" << 'EOF'
# Task: [SUMMARY.1001]: Summary Test Task

## Status
- [ ] **Task completed** - acceptance criteria met

## Summary
This is the first paragraph of the summary.

This is the second paragraph that should not be included.

## Technical Requirements
Some requirements here.
EOF

    local output
    output=$(run_hydration "$ticket_dir") || { fail_test "Summary extraction" "hydration failed"; return; }

    local desc
    desc=$(get_description "$output" "SUMMARY.1001")
    if [ "$desc" != "This is the first paragraph of the summary." ]; then
        fail_test "Summary extraction" "description mismatch: '$desc'"
        return
    fi

    pass_test "Summary extraction"
}

test_working_on_prefix_for_nouns() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Working on prefix for noun-phrase subjects ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "NOUNS")

    local task_file="$ticket_dir/tasks/NOUNS.1001_api-test.md"
    cat > "$task_file" << 'EOF'
# Task: [NOUNS.1001]: API Verification

## Status
- [ ] **Task completed** - acceptance criteria met

## Summary
Verifying the API.
EOF

    local output
    output=$(run_hydration "$ticket_dir") || { fail_test "Working on prefix" "hydration failed"; return; }

    local active_form
    active_form=$(get_active_form "$output" "NOUNS.1001")
    if [ "$active_form" != "Working on: API Verification" ]; then
        fail_test "Working on prefix" "expected 'Working on: API Verification', got '$active_form'"
        return
    fi

    pass_test "Working on prefix"
}

# ============================================================================
# Test Runner
# ============================================================================

run_all_tests() {
    echo -e "${BLUE}=== SDD Task Hydration Module Tests ===${NC}"
    echo ""

    # Simple task tests
    echo -e "${YELLOW}--- Simple Task Tests ---${NC}"
    test_single_task_pending
    test_single_task_completed
    test_multiple_tasks_same_phase

    # Phase dependency tests
    echo ""
    echo -e "${YELLOW}--- Phase Dependency Tests ---${NC}"
    test_phase_dependencies
    test_three_phases

    # Explicit dependency tests
    echo ""
    echo -e "${YELLOW}--- Explicit Dependency Tests ---${NC}"
    test_explicit_dependencies
    test_combined_phase_and_explicit_deps
    test_dependency_outside_ticket_ignored

    # Edge case tests
    echo ""
    echo -e "${YELLOW}--- Edge Case Tests ---${NC}"
    test_empty_tasks_directory
    test_no_tasks_directory
    test_nonexistent_directory
    test_index_file_skipped

    # Error handling tests
    echo ""
    echo -e "${YELLOW}--- Error Handling Tests ---${NC}"
    test_malformed_task_file_handled

    # Output format tests
    echo ""
    echo -e "${YELLOW}--- Output Format Tests ---${NC}"
    test_active_form_generation
    test_working_on_prefix_for_nouns
    test_metadata_included
    test_task_list_id_in_output
    test_summary_extraction

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

    # Verify hydrate script exists
    if [ ! -f "$HYDRATE_SCRIPT" ]; then
        echo -e "${RED}Error: hydrate-tasks.py not found at $HYDRATE_SCRIPT${NC}"
        exit 1
    fi

    # Run tests
    run_all_tests
    exit_code=$?

    exit $exit_code
}

main
