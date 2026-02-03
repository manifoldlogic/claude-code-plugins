#!/bin/sh
#
# Test suite for sync-task-status.sh
#
# This script runs comprehensive unit tests for the task sync writer module.
# It tests various scenarios including:
# - Valid status mappings (pending, in_progress, completed)
# - Checkbox updates (unchecked to checked)
# - Error handling (missing file, invalid status, pattern not found)
# - Concurrent write safety
# - File formatting preservation
#
# Usage:
#   ./test-sync-task-status.sh           # Run all tests
#   ./test-sync-task-status.sh -v        # Verbose output
#   ./test-sync-task-status.sh --help    # Show help
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed
#

# ============================================================================
# Configuration
# ============================================================================

# Get script directory (portable approach)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/sync-task-status.sh"
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

# Create a test ticket directory structure
# Usage: create_test_ticket TICKET_NAME
# Returns: path to ticket directory
create_test_ticket() {
    local ticket_name="$1"
    local ticket_dir="$TEMP_DIR/tickets/$ticket_name"
    mkdir -p "$ticket_dir/tasks"
    printf "%s" "$ticket_dir"
}

# Create a task file with specified status
# Usage: create_task_file TASKS_DIR TASK_ID TASK_NAME [STATUS]
# STATUS: 'pending' (default) or 'completed'
create_task_file() {
    local tasks_dir="$1"
    local task_id="$2"
    local task_name="$3"
    local status="${4:-pending}"

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

## Technical Requirements
Some technical requirements here.
EOF

    printf "%s" "$file_path"
}

# Create a task file with custom content (for edge cases)
# Usage: create_custom_task_file TASKS_DIR TASK_ID TASK_NAME CONTENT
create_custom_task_file() {
    local tasks_dir="$1"
    local task_id="$2"
    local task_name="$3"
    local content="$4"

    local file_path="$tasks_dir/${task_id}_${task_name}.md"
    printf "%s" "$content" > "$file_path"
    printf "%s" "$file_path"
}

# Run sync script and capture output
# Usage: run_sync TASK_ID NEW_STATUS
# Returns: exit code
run_sync() {
    local task_id="$1"
    local new_status="$2"

    if [ "$VERBOSE" = true ]; then
        "$SYNC_SCRIPT" "$task_id" "$new_status" 2>&1
    else
        "$SYNC_SCRIPT" "$task_id" "$new_status" >/dev/null 2>&1
    fi
    return $?
}

# Check if file contains checked checkbox
# Usage: has_checked_checkbox FILE
# Returns: 0 if found, 1 if not
has_checked_checkbox() {
    local file="$1"
    grep -q '^\- \[x\] \*\*Task completed\*\*' "$file" 2>/dev/null
}

# Check if file contains unchecked checkbox
# Usage: has_unchecked_checkbox FILE
# Returns: 0 if found, 1 if not
has_unchecked_checkbox() {
    local file="$1"
    grep -q '^\- \[ \] \*\*Task completed\*\*' "$file" 2>/dev/null
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
# Test Cases: Valid Status Mappings
# ============================================================================

test_pending_status_no_change() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Pending status - no file update needed ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "SYNC_test-pending")
    local task_file
    task_file=$(create_task_file "$ticket_dir/tasks" "SYNC.1001" "test-pending" "pending")

    local exit_code=0
    run_sync "SYNC.1001" "pending" || exit_code=$?

    if [ $exit_code -ne 0 ]; then
        fail_test "expected exit 0, got $exit_code"
        return
    fi

    # File should still have unchecked checkbox
    if ! has_unchecked_checkbox "$task_file"; then
        fail_test "checkbox was modified when it should not be"
        return
    fi

    pass_test
}

test_in_progress_status_no_change() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: In_progress status - no file update needed ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "SYNC_test-in-progress")
    local task_file
    task_file=$(create_task_file "$ticket_dir/tasks" "SYNC.1002" "test-in-progress" "pending")

    local exit_code=0
    run_sync "SYNC.1002" "in_progress" || exit_code=$?

    if [ $exit_code -ne 0 ]; then
        fail_test "expected exit 0, got $exit_code"
        return
    fi

    # File should still have unchecked checkbox
    if ! has_unchecked_checkbox "$task_file"; then
        fail_test "checkbox was modified when it should not be"
        return
    fi

    pass_test
}

test_completed_status_checks_checkbox() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Completed status - checks Task completed checkbox ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "SYNC_test-completed")
    local task_file
    task_file=$(create_task_file "$ticket_dir/tasks" "SYNC.1003" "test-completed" "pending")

    local exit_code=0
    run_sync "SYNC.1003" "completed" || exit_code=$?

    if [ $exit_code -ne 0 ]; then
        fail_test "expected exit 0, got $exit_code"
        return
    fi

    # File should now have checked checkbox
    if ! has_checked_checkbox "$task_file"; then
        fail_test "checkbox was not updated to checked"
        return
    fi

    pass_test
}

test_already_completed_idempotent() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Already completed - idempotent operation ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "SYNC_test-already-completed")
    local task_file
    task_file=$(create_task_file "$ticket_dir/tasks" "SYNC.1004" "test-already-completed" "completed")

    local exit_code=0
    run_sync "SYNC.1004" "completed" || exit_code=$?

    if [ $exit_code -ne 0 ]; then
        fail_test "expected exit 0, got $exit_code"
        return
    fi

    # File should still have checked checkbox
    if ! has_checked_checkbox "$task_file"; then
        fail_test "checkbox was incorrectly modified"
        return
    fi

    pass_test
}

# ============================================================================
# Test Cases: Error Handling
# ============================================================================

test_missing_task_id_argument() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Missing task ID argument - returns error ... "

    local exit_code=0
    "$SYNC_SCRIPT" "" "completed" >/dev/null 2>&1 || exit_code=$?

    if [ $exit_code -ne 1 ]; then
        fail_test "expected exit 1, got $exit_code"
        return
    fi

    pass_test
}

test_missing_status_argument() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Missing status argument - returns error ... "

    local exit_code=0
    "$SYNC_SCRIPT" "SYNC.1001" "" >/dev/null 2>&1 || exit_code=$?

    if [ $exit_code -ne 1 ]; then
        fail_test "expected exit 1, got $exit_code"
        return
    fi

    pass_test
}

test_invalid_status_value() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Invalid status value - returns error ... "

    local exit_code=0
    "$SYNC_SCRIPT" "SYNC.1001" "invalid_status" >/dev/null 2>&1 || exit_code=$?

    if [ $exit_code -ne 1 ]; then
        fail_test "expected exit 1, got $exit_code"
        return
    fi

    pass_test
}

test_invalid_task_id_format() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Invalid task ID format - returns error ... "

    local exit_code=0
    "$SYNC_SCRIPT" "invalid-task-id" "completed" >/dev/null 2>&1 || exit_code=$?

    if [ $exit_code -ne 1 ]; then
        fail_test "expected exit 1, got $exit_code"
        return
    fi

    pass_test
}

test_task_file_not_found() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Task file not found - returns error ... "

    # Create tickets directory but no matching task file
    mkdir -p "$TEMP_DIR/tickets/NOTFOUND_test/tasks"

    local exit_code=0
    run_sync "NOTFOUND.1001" "completed" || exit_code=$?

    if [ $exit_code -ne 1 ]; then
        fail_test "expected exit 1, got $exit_code"
        return
    fi

    pass_test
}

test_tickets_directory_not_found() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Tickets directory not found - returns error ... "

    # Use a non-existent SDD_ROOT_DIR
    local old_sdd_root="$SDD_ROOT_DIR"
    export SDD_ROOT_DIR="/nonexistent/path/to/sdd"

    local exit_code=0
    run_sync "MISSING.1001" "completed" || exit_code=$?

    export SDD_ROOT_DIR="$old_sdd_root"

    if [ $exit_code -ne 1 ]; then
        fail_test "expected exit 1, got $exit_code"
        return
    fi

    pass_test
}

test_checkbox_pattern_not_found() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Checkbox pattern not found - returns error ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "NOCHECK_test-no-checkbox")

    # Create task file without proper checkbox
    local malformed_content="# Task: [NOCHECK.1001]: Test Task

## Status
This file has no proper checkbox.

## Summary
Malformed task file.
"
    local task_file
    task_file=$(create_custom_task_file "$ticket_dir/tasks" "NOCHECK.1001" "no-checkbox" "$malformed_content")

    local exit_code=0
    run_sync "NOCHECK.1001" "completed" || exit_code=$?

    if [ $exit_code -ne 1 ]; then
        fail_test "expected exit 1, got $exit_code"
        return
    fi

    pass_test
}

# ============================================================================
# Test Cases: File Formatting Preservation
# ============================================================================

test_preserves_file_structure() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Preserves file structure and formatting ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "FORMAT_test-preserve")
    local task_file
    task_file=$(create_task_file "$ticket_dir/tasks" "FORMAT.1001" "test-preserve" "pending")

    # Count lines before
    local lines_before
    lines_before=$(wc -l < "$task_file")

    run_sync "FORMAT.1001" "completed"

    # Count lines after
    local lines_after
    lines_after=$(wc -l < "$task_file")

    if [ "$lines_before" != "$lines_after" ]; then
        fail_test "line count changed from $lines_before to $lines_after"
        return
    fi

    # Verify other checkboxes are unchanged
    if ! grep -q '^\- \[ \] \*\*Tests pass\*\*' "$task_file"; then
        fail_test "Tests pass checkbox was incorrectly modified"
        return
    fi

    if ! grep -q '^\- \[ \] \*\*Verified\*\*' "$task_file"; then
        fail_test "Verified checkbox was incorrectly modified"
        return
    fi

    pass_test
}

test_preserves_checkbox_suffix() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Preserves text after checkbox ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "SUFFIX_test-suffix")
    local task_file
    task_file=$(create_task_file "$ticket_dir/tasks" "SUFFIX.1001" "test-suffix" "pending")

    run_sync "SUFFIX.1001" "completed"

    # Verify suffix is preserved
    if ! grep -q '^\- \[x\] \*\*Task completed\*\* - acceptance criteria met' "$task_file"; then
        fail_test "suffix text was not preserved"
        return
    fi

    pass_test
}

test_handles_special_characters_in_file() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Handles special characters in file content ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "SPECIAL_test-special")

    # Create task file with special characters
    local special_content='# Task: [SPECIAL.1001]: Test with $pecial Ch@rs!

## Status
- [ ] **Task completed** - acceptance criteria met
- [ ] **Tests pass** - tests executed and passing

## Summary
This file has $special characters like `backticks` and "quotes".

## Technical Requirements
- Handle paths like /foo/bar/baz.md
- Handle regex patterns like [A-Z]+
'
    local task_file
    task_file=$(create_custom_task_file "$ticket_dir/tasks" "SPECIAL.1001" "special-chars" "$special_content")

    local exit_code=0
    run_sync "SPECIAL.1001" "completed" || exit_code=$?

    if [ $exit_code -ne 0 ]; then
        fail_test "sync failed with exit $exit_code"
        return
    fi

    if ! has_checked_checkbox "$task_file"; then
        fail_test "checkbox was not updated"
        return
    fi

    # Verify special content is preserved
    if ! grep -q '\$pecial' "$task_file"; then
        fail_test "special characters were corrupted"
        return
    fi

    pass_test
}

# ============================================================================
# Test Cases: Jira-style Task IDs
# ============================================================================

test_jira_style_task_id() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Supports Jira-style task IDs (UIT-9819.1001) ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "UIT-9819_jira-test")
    local task_file
    task_file=$(create_task_file "$ticket_dir/tasks" "UIT-9819.1001" "jira-style" "pending")

    local exit_code=0
    run_sync "UIT-9819.1001" "completed" || exit_code=$?

    if [ $exit_code -ne 0 ]; then
        fail_test "expected exit 0, got $exit_code"
        return
    fi

    if ! has_checked_checkbox "$task_file"; then
        fail_test "checkbox was not updated"
        return
    fi

    pass_test
}

# ============================================================================
# Test Cases: Debug Mode
# ============================================================================

test_debug_mode_outputs_logs() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Debug mode outputs detailed logs ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "DEBUG_test-debug")
    local task_file
    task_file=$(create_task_file "$ticket_dir/tasks" "DEBUG.1001" "test-debug" "pending")

    export SDD_TASKS_SYNC_DEBUG=true
    local output
    output=$("$SYNC_SCRIPT" "DEBUG.1001" "completed" 2>&1)
    unset SDD_TASKS_SYNC_DEBUG

    if ! printf "%s" "$output" | grep -q '\[DEBUG\]'; then
        fail_test "debug output not found"
        return
    fi

    pass_test
}

# ============================================================================
# Test Cases: Concurrent Write Safety
# ============================================================================

test_atomic_write_creates_no_temp_files() {
    TESTS_RUN=$((TESTS_RUN + 1))
    printf "Test: Atomic write leaves no temp files ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "ATOMIC_test-atomic")
    local task_file
    task_file=$(create_task_file "$ticket_dir/tasks" "ATOMIC.1001" "test-atomic" "pending")

    run_sync "ATOMIC.1001" "completed"

    # Check for any remaining temp or lock files
    local tasks_dir="$ticket_dir/tasks"
    local temp_files
    temp_files=$(find "$tasks_dir" -name "*.tmp*" -o -name "*.sync-lock" 2>/dev/null | wc -l)

    if [ "$temp_files" -gt 0 ]; then
        fail_test "temp/lock files were not cleaned up"
        return
    fi

    pass_test
}

# ============================================================================
# Test Runner
# ============================================================================

run_all_tests() {
    printf "%s=== Task Sync Writer Tests ===%s\n" "$BLUE" "$NC"
    printf "\n"

    # Status mapping tests
    printf "%s--- Status Mapping Tests ---%s\n" "$YELLOW" "$NC"
    test_pending_status_no_change
    test_in_progress_status_no_change
    test_completed_status_checks_checkbox
    test_already_completed_idempotent

    # Error handling tests
    printf "\n"
    printf "%s--- Error Handling Tests ---%s\n" "$YELLOW" "$NC"
    test_missing_task_id_argument
    test_missing_status_argument
    test_invalid_status_value
    test_invalid_task_id_format
    test_task_file_not_found
    test_tickets_directory_not_found
    test_checkbox_pattern_not_found

    # File formatting tests
    printf "\n"
    printf "%s--- File Formatting Tests ---%s\n" "$YELLOW" "$NC"
    test_preserves_file_structure
    test_preserves_checkbox_suffix
    test_handles_special_characters_in_file

    # Task ID format tests
    printf "\n"
    printf "%s--- Task ID Format Tests ---%s\n" "$YELLOW" "$NC"
    test_jira_style_task_id

    # Debug mode tests
    printf "\n"
    printf "%s--- Debug Mode Tests ---%s\n" "$YELLOW" "$NC"
    test_debug_mode_outputs_logs

    # Concurrent safety tests
    printf "\n"
    printf "%s--- Concurrent Safety Tests ---%s\n" "$YELLOW" "$NC"
    test_atomic_write_creates_no_temp_files

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

    # Verify sync script exists
    if [ ! -f "$SYNC_SCRIPT" ]; then
        printf "${RED}Error: sync-task-status.sh not found at %s${NC}\n" "$SYNC_SCRIPT"
        exit 1
    fi

    # Run tests
    run_all_tests
    exit_code=$?

    exit $exit_code
}

main
