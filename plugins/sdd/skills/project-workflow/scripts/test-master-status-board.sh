#!/bin/bash
#
# Unit Tests for Master Status Board
# Tests directory discovery and argument handling
#
# Usage:
#   bash test-master-status-board.sh
#
# Exit Codes:
#   0 - All tests passed
#   1 - One or more tests failed
#

set -euo pipefail

# Get the directory where this test script lives
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MASTER_SCRIPT="$SCRIPT_DIR/master-status-board.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Temporary directory for test fixtures
TEST_TMP_DIR=""

#######################################
# Set up test fixtures
#######################################
setup() {
    TEST_TMP_DIR=$(mktemp -d)
    echo "Setting up test fixtures in: $TEST_TMP_DIR" >&2
}

#######################################
# Clean up test fixtures
#######################################
teardown() {
    if [[ -n "$TEST_TMP_DIR" && -d "$TEST_TMP_DIR" ]]; then
        rm -rf "$TEST_TMP_DIR"
        echo "Cleaned up test fixtures" >&2
    fi
}

#######################################
# Log test result
# Arguments:
#   $1 - Test name
#   $2 - Result (pass/fail)
#   $3 - Optional message
#######################################
log_result() {
    local test_name="$1"
    local result="$2"
    local message="${3:-}"

    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$result" == "pass" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "[PASS] $test_name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "[FAIL] $test_name"
        if [[ -n "$message" ]]; then
            echo "       $message"
        fi
    fi
}

#######################################
# Assert that two values are equal
# Arguments:
#   $1 - Expected value
#   $2 - Actual value
#   $3 - Test name
#######################################
assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    if [[ "$expected" == "$actual" ]]; then
        log_result "$test_name" "pass"
    else
        log_result "$test_name" "fail" "Expected: '$expected', Got: '$actual'"
    fi
}

#######################################
# Assert that string contains substring
# Arguments:
#   $1 - Haystack (full string)
#   $2 - Needle (substring to find)
#   $3 - Test name
#######################################
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"

    if [[ "$haystack" == *"$needle"* ]]; then
        log_result "$test_name" "pass"
    else
        log_result "$test_name" "fail" "String does not contain: '$needle'"
    fi
}

#######################################
# Assert exit code
# Arguments:
#   $1 - Expected exit code
#   $2 - Actual exit code
#   $3 - Test name
#######################################
assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    if [[ "$expected" == "$actual" ]]; then
        log_result "$test_name" "pass"
    else
        log_result "$test_name" "fail" "Expected exit code: $expected, Got: $actual"
    fi
}

#######################################
# Test: Help option works
#######################################
test_help_option() {
    echo "--- Test: Help option ---"

    local output
    output=$(bash "$MASTER_SCRIPT" --help 2>&1)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "Help option exits with code 0"
    assert_contains "$output" "Usage:" "Help shows usage"
    assert_contains "$output" "workspace_root" "Help mentions workspace_root"
    assert_contains "$output" "WORKSPACE_ROOT" "Help mentions environment variable"
}

#######################################
# Test: Short help option works
#######################################
test_short_help_option() {
    echo "--- Test: Short help option ---"

    local output
    output=$(bash "$MASTER_SCRIPT" -h 2>&1)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "Short help option exits with code 0"
    assert_contains "$output" "Usage:" "Short help shows usage"
}

#######################################
# Test: Missing workspace directory exits with code 1
#######################################
test_missing_workspace() {
    echo "--- Test: Missing workspace directory ---"

    local output
    local exit_code=0
    output=$(bash "$MASTER_SCRIPT" "/nonexistent/path/that/does/not/exist" 2>&1) || exit_code=$?

    assert_exit_code 1 "$exit_code" "Missing workspace exits with code 1"
    assert_contains "$output" "Error:" "Missing workspace shows error message"
}

#######################################
# Test: Empty workspace returns empty repos array
#######################################
test_empty_workspace() {
    echo "--- Test: Empty workspace ---"

    # Create empty workspace
    local empty_workspace="$TEST_TMP_DIR/empty_workspace"
    mkdir -p "$empty_workspace"

    local output
    output=$(bash "$MASTER_SCRIPT" "$empty_workspace" 2>&1)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "Empty workspace exits with code 0"
    assert_contains "$output" '"repos": [' "Output contains repos array"
    assert_contains "$output" '"workspace_root":' "Output contains workspace_root"
}

#######################################
# Test: Discovers _SDD directory
#######################################
test_discovers_sdd_directory() {
    echo "--- Test: Discovers _SDD directory ---"

    # Create test repo with _SDD
    local test_workspace="$TEST_TMP_DIR/test_workspace"
    mkdir -p "$test_workspace/my-repo/_SDD"

    local output
    output=$(bash "$MASTER_SCRIPT" "$test_workspace" 2>&1)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "Discovery exits with code 0"
    assert_contains "$output" '"name": "my-repo"' "Found repo name"
    assert_contains "$output" "_SDD" "Found _SDD path"
}

#######################################
# Test: Discovers multiple _SDD directories
#######################################
test_discovers_multiple_sdd_directories() {
    echo "--- Test: Discovers multiple _SDD directories ---"

    # Create multiple repos with _SDD
    local test_workspace="$TEST_TMP_DIR/multi_workspace"
    mkdir -p "$test_workspace/repo-alpha/_SDD"
    mkdir -p "$test_workspace/repo-beta/_SDD"
    mkdir -p "$test_workspace/repo-gamma/_SDD"
    mkdir -p "$test_workspace/no-sdd-here"  # This should not be found

    local output
    output=$(bash "$MASTER_SCRIPT" "$test_workspace" 2>&1)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "Multiple discovery exits with code 0"
    assert_contains "$output" '"name": "repo-alpha"' "Found repo-alpha"
    assert_contains "$output" '"name": "repo-beta"' "Found repo-beta"
    assert_contains "$output" '"name": "repo-gamma"' "Found repo-gamma"
}

#######################################
# Test: Environment variable WORKSPACE_ROOT
#######################################
test_environment_variable() {
    echo "--- Test: Environment variable WORKSPACE_ROOT ---"

    # Create test workspace
    local test_workspace="$TEST_TMP_DIR/env_workspace"
    mkdir -p "$test_workspace/env-repo/_SDD"

    local output
    output=$(WORKSPACE_ROOT="$test_workspace" bash "$MASTER_SCRIPT" 2>&1)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "Environment variable exits with code 0"
    assert_contains "$output" '"name": "env-repo"' "Found repo via env var"
}

#######################################
# Test: Argument overrides environment variable
#######################################
test_argument_overrides_env() {
    echo "--- Test: Argument overrides environment variable ---"

    # Create two workspaces
    local env_workspace="$TEST_TMP_DIR/env_only_workspace"
    local arg_workspace="$TEST_TMP_DIR/arg_workspace"
    mkdir -p "$env_workspace/env-only-repo/_SDD"
    mkdir -p "$arg_workspace/arg-repo/_SDD"

    local output
    output=$(WORKSPACE_ROOT="$env_workspace" bash "$MASTER_SCRIPT" "$arg_workspace" 2>&1)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "Argument override exits with code 0"
    assert_contains "$output" '"name": "arg-repo"' "Found arg-repo (from argument)"
    # Should NOT contain env-only-repo
    if [[ "$output" == *"env-only-repo"* ]]; then
        log_result "Argument correctly overrides env var" "fail" "Found env-only-repo when it should not be present"
    else
        log_result "Argument correctly overrides env var" "pass"
    fi
}

#######################################
# Test: JSON output is valid structure
#######################################
test_json_structure() {
    echo "--- Test: JSON output structure ---"

    local test_workspace="$TEST_TMP_DIR/json_workspace"
    mkdir -p "$test_workspace/json-repo/_SDD"

    local output
    output=$(bash "$MASTER_SCRIPT" "$test_workspace" 2>&1)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "JSON structure test exits with code 0"
    assert_contains "$output" '"timestamp":' "JSON has timestamp"
    assert_contains "$output" '"workspace_root":' "JSON has workspace_root"
    assert_contains "$output" '"repos":' "JSON has repos"
    assert_contains "$output" '"name":' "JSON repos have name"
    assert_contains "$output" '"sdd_path":' "JSON repos have sdd_path"
    assert_contains "$output" '"repo_path":' "JSON repos have repo_path"
}

#######################################
# Test: Unknown option shows error
#######################################
test_unknown_option() {
    echo "--- Test: Unknown option ---"

    local output
    local exit_code=0
    output=$(bash "$MASTER_SCRIPT" --invalid-option 2>&1) || exit_code=$?

    assert_exit_code 2 "$exit_code" "Unknown option exits with code 2"
    assert_contains "$output" "Error:" "Unknown option shows error"
    assert_contains "$output" "--help" "Error suggests --help"
}

#######################################
# Test: Debug mode outputs to stderr
#######################################
test_debug_mode() {
    echo "--- Test: Debug mode ---"

    local test_workspace="$TEST_TMP_DIR/debug_workspace"
    mkdir -p "$test_workspace/debug-repo/_SDD"

    local stderr_output
    local stdout_output

    # Capture stderr separately
    stderr_output=$(bash "$MASTER_SCRIPT" --debug "$test_workspace" 2>&1 1>/dev/null)

    assert_contains "$stderr_output" "[DEBUG]" "Debug mode outputs DEBUG messages"
}

#######################################
# Test: Symlink within workspace is followed
#######################################
test_symlink_within_workspace() {
    echo "--- Test: Symlink within workspace ---"

    local test_workspace="$TEST_TMP_DIR/symlink_workspace"
    mkdir -p "$test_workspace/real-repo/_SDD"
    # Create symlink to real repo
    ln -s "$test_workspace/real-repo" "$test_workspace/linked-repo"

    local output
    output=$(bash "$MASTER_SCRIPT" "$test_workspace" 2>&1)
    local exit_code=$?

    # Should find both the real repo and follow the symlink
    assert_exit_code 0 "$exit_code" "Symlink test exits with code 0"
    assert_contains "$output" "real-repo" "Found real-repo"
}

#######################################
# Test: Depth limit prevents deep recursion
#######################################
test_depth_limit() {
    echo "--- Test: Depth limit ---"

    local test_workspace="$TEST_TMP_DIR/deep_workspace"
    # Create _SDD at depth 1 (should be found)
    mkdir -p "$test_workspace/shallow-repo/_SDD"
    # Create _SDD at depth 4 (should NOT be found with maxdepth 2)
    mkdir -p "$test_workspace/deep/nested/very/deep-repo/_SDD"

    local output
    output=$(bash "$MASTER_SCRIPT" "$test_workspace" 2>&1)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "Depth limit test exits with code 0"
    assert_contains "$output" '"name": "shallow-repo"' "Found shallow-repo"

    # Should NOT find deep-repo (too deep)
    if [[ "$output" == *"deep-repo"* ]]; then
        log_result "Depth limit prevents deep discovery" "fail" "Found deep-repo when it should be too deep"
    else
        log_result "Depth limit prevents deep discovery" "pass"
    fi
}

#######################################
# Test: scan_task with all checkboxes unchecked
#######################################
test_scan_task_all_unchecked() {
    echo "--- Test: scan_task with all unchecked ---"

    # Source the script to get access to functions
    source "$MASTER_SCRIPT"

    # Create test task file with all unchecked
    local task_file="$TEST_TMP_DIR/PROJ.1001_test-task.md"
    cat > "$task_file" << 'EOF'
# Task: [PROJ.1001]: Test Task

## Status
- [ ] **Task completed** - acceptance criteria met
- [ ] **Tests pass** - tests executed and passing
- [ ] **Verified** - by the verify-task agent

## Summary
Test task content
EOF

    local output
    output=$(scan_task "$task_file")
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "scan_task all unchecked exits with code 0"
    assert_contains "$output" '"task_id": "PROJ.1001"' "Task ID extracted correctly"
    assert_contains "$output" '"task_completed": false' "task_completed is false"
    assert_contains "$output" '"tests_pass": false' "tests_pass is false"
    assert_contains "$output" '"verified": false' "verified is false"
}

#######################################
# Test: scan_task with only task_completed checked
#######################################
test_scan_task_only_completed() {
    echo "--- Test: scan_task with only task_completed checked ---"

    source "$MASTER_SCRIPT"

    local task_file="$TEST_TMP_DIR/PROJ.1002_completed-only.md"
    cat > "$task_file" << 'EOF'
# Task: [PROJ.1002]: Completed Only

## Status
- [x] **Task completed** - acceptance criteria met
- [ ] **Tests pass** - tests executed and passing
- [ ] **Verified** - by the verify-task agent
EOF

    local output
    output=$(scan_task "$task_file")

    assert_contains "$output" '"task_completed": true' "task_completed is true"
    assert_contains "$output" '"tests_pass": false' "tests_pass is false"
    assert_contains "$output" '"verified": false' "verified is false"
}

#######################################
# Test: scan_task with task_completed and tests_pass checked
#######################################
test_scan_task_completed_and_tested() {
    echo "--- Test: scan_task with completed and tested ---"

    source "$MASTER_SCRIPT"

    local task_file="$TEST_TMP_DIR/PROJ.1003_tested.md"
    cat > "$task_file" << 'EOF'
# Task: [PROJ.1003]: Tested

## Status
- [x] **Task completed** - acceptance criteria met
- [x] **Tests pass** - tests executed and passing
- [ ] **Verified** - by the verify-task agent
EOF

    local output
    output=$(scan_task "$task_file")

    assert_contains "$output" '"task_completed": true' "task_completed is true"
    assert_contains "$output" '"tests_pass": true' "tests_pass is true"
    assert_contains "$output" '"verified": false' "verified is false"
}

#######################################
# Test: scan_task with all checkboxes checked (verified)
#######################################
test_scan_task_all_checked() {
    echo "--- Test: scan_task with all checked (verified) ---"

    source "$MASTER_SCRIPT"

    local task_file="$TEST_TMP_DIR/PROJ.1004_verified.md"
    cat > "$task_file" << 'EOF'
# Task: [PROJ.1004]: Verified

## Status
- [x] **Task completed** - acceptance criteria met
- [x] **Tests pass** - tests executed and passing
- [x] **Verified** - by the verify-task agent
EOF

    local output
    output=$(scan_task "$task_file")

    assert_contains "$output" '"task_completed": true' "task_completed is true"
    assert_contains "$output" '"tests_pass": true' "tests_pass is true"
    assert_contains "$output" '"verified": true' "verified is true"
}

#######################################
# Test: scan_task with uppercase X in checkboxes
#######################################
test_scan_task_uppercase_x() {
    echo "--- Test: scan_task with uppercase X ---"

    source "$MASTER_SCRIPT"

    local task_file="$TEST_TMP_DIR/PROJ.1005_uppercase.md"
    cat > "$task_file" << 'EOF'
# Task: [PROJ.1005]: Uppercase X

## Status
- [X] **Task completed** - acceptance criteria met
- [X] **Tests pass** - tests executed and passing
- [X] **Verified** - by the verify-task agent
EOF

    local output
    output=$(scan_task "$task_file")

    assert_contains "$output" '"task_completed": true' "task_completed is true (uppercase X)"
    assert_contains "$output" '"tests_pass": true' "tests_pass is true (uppercase X)"
    assert_contains "$output" '"verified": true' "verified is true (uppercase X)"
}

#######################################
# Test: scan_task with missing file
#######################################
test_scan_task_missing_file() {
    echo "--- Test: scan_task with missing file ---"

    source "$MASTER_SCRIPT"

    local task_file="$TEST_TMP_DIR/nonexistent/PROJ.9999_missing.md"
    local output
    local exit_code=0
    output=$(scan_task "$task_file") || exit_code=$?

    assert_exit_code 1 "$exit_code" "scan_task missing file exits with code 1"
    assert_contains "$output" '"error": "File not found"' "Error message present"
    assert_contains "$output" '"task_completed": false' "task_completed defaults to false"
    assert_contains "$output" '"tests_pass": false' "tests_pass defaults to false"
    assert_contains "$output" '"verified": false' "verified defaults to false"
}

#######################################
# Test: scan_task with empty file
#######################################
test_scan_task_empty_file() {
    echo "--- Test: scan_task with empty file ---"

    source "$MASTER_SCRIPT"

    local task_file="$TEST_TMP_DIR/PROJ.1006_empty.md"
    touch "$task_file"

    local output
    output=$(scan_task "$task_file")
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "scan_task empty file exits with code 0"
    assert_contains "$output" '"task_completed": false' "task_completed is false for empty"
    assert_contains "$output" '"tests_pass": false' "tests_pass is false for empty"
    assert_contains "$output" '"verified": false' "verified is false for empty"
}

#######################################
# Test: scan_task with no checkboxes
#######################################
test_scan_task_no_checkboxes() {
    echo "--- Test: scan_task with no checkboxes ---"

    source "$MASTER_SCRIPT"

    local task_file="$TEST_TMP_DIR/PROJ.1007_no-checkboxes.md"
    cat > "$task_file" << 'EOF'
# Task: [PROJ.1007]: No Checkboxes

## Summary
This task file has no status checkboxes at all.

## Implementation
Just some content here.
EOF

    local output
    output=$(scan_task "$task_file")
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "scan_task no checkboxes exits with code 0"
    assert_contains "$output" '"task_completed": false' "task_completed is false (no checkboxes)"
    assert_contains "$output" '"tests_pass": false' "tests_pass is false (no checkboxes)"
    assert_contains "$output" '"verified": false' "verified is false (no checkboxes)"
}

#######################################
# Test: scan_task ignores checkboxes in code blocks
#######################################
test_scan_task_ignores_code_blocks() {
    echo "--- Test: scan_task ignores checkboxes in code blocks ---"

    source "$MASTER_SCRIPT"

    local task_file="$TEST_TMP_DIR/PROJ.1008_code-blocks.md"
    cat > "$task_file" << 'EOF'
# Task: [PROJ.1008]: Code Blocks

## Status
- [ ] **Task completed** - acceptance criteria met
- [ ] **Tests pass** - tests executed and passing
- [ ] **Verified** - by the verify-task agent

## Example Code

Here is how the checkbox looks in code:

```markdown
## Status
- [x] **Task completed** - this is in a code block
- [x] **Tests pass** - this is in a code block
- [x] **Verified** - this is in a code block
```

The above should be ignored.
EOF

    local output
    output=$(scan_task "$task_file")

    assert_contains "$output" '"task_completed": false' "Ignores task_completed in code block"
    assert_contains "$output" '"tests_pass": false' "Ignores tests_pass in code block"
    assert_contains "$output" '"verified": false' "Ignores verified in code block"
}

#######################################
# Test: scan_task with Jira-style task ID
#######################################
test_scan_task_jira_style_id() {
    echo "--- Test: scan_task with Jira-style ID ---"

    source "$MASTER_SCRIPT"

    local task_file="$TEST_TMP_DIR/UIT-9819.1001_jira-style.md"
    cat > "$task_file" << 'EOF'
# Task: [UIT-9819.1001]: Jira Style

## Status
- [x] **Task completed** - acceptance criteria met
- [ ] **Tests pass** - tests executed and passing
- [ ] **Verified** - by the verify-task agent
EOF

    local output
    output=$(scan_task "$task_file")

    assert_contains "$output" '"task_id": "UIT-9819.1001"' "Jira-style task ID extracted"
    assert_contains "$output" '"task_completed": true' "task_completed is true"
}

#######################################
# Test: scan_task with SDDLOOP style task ID
#######################################
test_scan_task_sddloop_style_id() {
    echo "--- Test: scan_task with SDDLOOP-style ID ---"

    source "$MASTER_SCRIPT"

    local task_file="$TEST_TMP_DIR/SDDLOOP-1.1002_sddloop-style.md"
    cat > "$task_file" << 'EOF'
# Task: [SDDLOOP-1.1002]: SDDLOOP Style

## Status
- [x] **Task completed** - acceptance criteria met
- [x] **Tests pass** - tests executed and passing
- [ ] **Verified** - by the verify-task agent
EOF

    local output
    output=$(scan_task "$task_file")

    assert_contains "$output" '"task_id": "SDDLOOP-1.1002"' "SDDLOOP-style task ID extracted"
    assert_contains "$output" '"task_completed": true' "task_completed is true"
    assert_contains "$output" '"tests_pass": true' "tests_pass is true"
}

#######################################
# Test: scan_task output is valid JSON
#######################################
test_scan_task_valid_json() {
    echo "--- Test: scan_task output is valid JSON ---"

    source "$MASTER_SCRIPT"

    local task_file="$TEST_TMP_DIR/PROJ.1009_json-test.md"
    cat > "$task_file" << 'EOF'
# Task: [PROJ.1009]: JSON Validation

## Status
- [x] **Task completed** - acceptance criteria met
- [ ] **Tests pass** - tests executed and passing
- [ ] **Verified** - by the verify-task agent
EOF

    local output
    output=$(scan_task "$task_file")

    # Try to parse with jq if available
    if command -v jq &>/dev/null; then
        if echo "$output" | jq . >/dev/null 2>&1; then
            log_result "scan_task output is valid JSON" "pass"
        else
            log_result "scan_task output is valid JSON" "fail" "JSON parsing failed"
        fi
    else
        # Fallback: basic structure check
        if [[ "$output" == "{"* && "$output" == *"}" ]]; then
            log_result "scan_task output is valid JSON (basic check)" "pass"
        else
            log_result "scan_task output is valid JSON (basic check)" "fail"
        fi
    fi
}

#######################################
# Test: scan_task with partial checkboxes (only verified missing)
#######################################
test_scan_task_partial_checkboxes() {
    echo "--- Test: scan_task with partial checkboxes ---"

    source "$MASTER_SCRIPT"

    local task_file="$TEST_TMP_DIR/PROJ.1010_partial.md"
    cat > "$task_file" << 'EOF'
# Task: [PROJ.1010]: Partial Checkboxes

## Status
- [x] **Task completed** - acceptance criteria met
- [x] **Tests pass** - tests executed and passing

## Summary
This file is missing the verified checkbox entirely
EOF

    local output
    output=$(scan_task "$task_file")

    assert_contains "$output" '"task_completed": true' "task_completed is true"
    assert_contains "$output" '"tests_pass": true' "tests_pass is true"
    assert_contains "$output" '"verified": false' "verified defaults to false when missing"
}

#######################################
# Test: strip_code_blocks helper function
#######################################
test_strip_code_blocks() {
    echo "--- Test: strip_code_blocks helper ---"

    source "$MASTER_SCRIPT"

    local input
    input=$(cat << 'EOF'
Line 1 before code
```bash
This is code
- [x] **Task completed** - in code block
```
Line after code
EOF
)

    local output
    output=$(echo "$input" | strip_code_blocks)

    # Should NOT contain the code block content
    if [[ "$output" == *"This is code"* ]]; then
        log_result "strip_code_blocks removes code content" "fail" "Code block content still present"
    else
        log_result "strip_code_blocks removes code content" "pass"
    fi

    # Should contain lines outside code block
    assert_contains "$output" "Line 1 before code" "Preserves content before code block"
    assert_contains "$output" "Line after code" "Preserves content after code block"
}

#######################################
# Test: scan_task with mixed case x
#######################################
test_scan_task_mixed_case() {
    echo "--- Test: scan_task with mixed case x ---"

    source "$MASTER_SCRIPT"

    local task_file="$TEST_TMP_DIR/PROJ.1011_mixed-case.md"
    cat > "$task_file" << 'EOF'
# Task: [PROJ.1011]: Mixed Case

## Status
- [x] **Task completed** - lowercase x
- [X] **Tests pass** - uppercase X
- [x] **Verified** - lowercase x
EOF

    local output
    output=$(scan_task "$task_file")

    assert_contains "$output" '"task_completed": true' "task_completed handles lowercase x"
    assert_contains "$output" '"tests_pass": true' "tests_pass handles uppercase X"
    assert_contains "$output" '"verified": true' "verified handles lowercase x"
}

#######################################
# Test: scan_task file path in output
#######################################
test_scan_task_file_path() {
    echo "--- Test: scan_task includes file path in output ---"

    source "$MASTER_SCRIPT"

    local task_file="$TEST_TMP_DIR/PROJ.1012_file-path.md"
    cat > "$task_file" << 'EOF'
# Task: [PROJ.1012]: File Path

## Status
- [ ] **Task completed**
EOF

    local output
    output=$(scan_task "$task_file")

    assert_contains "$output" "\"file\": \"$task_file\"" "Output contains full file path"
}

#######################################
# Main test runner
#######################################
main() {
    echo "====================================="
    echo "Master Status Board Unit Tests"
    echo "====================================="
    echo ""

    # Verify master script exists
    if [[ ! -f "$MASTER_SCRIPT" ]]; then
        echo "ERROR: Master script not found: $MASTER_SCRIPT" >&2
        exit 1
    fi

    # Setup
    setup

    # Trap to ensure cleanup on exit
    trap teardown EXIT

    # Run directory discovery tests
    test_help_option
    echo ""
    test_short_help_option
    echo ""
    test_missing_workspace
    echo ""
    test_empty_workspace
    echo ""
    test_discovers_sdd_directory
    echo ""
    test_discovers_multiple_sdd_directories
    echo ""
    test_environment_variable
    echo ""
    test_argument_overrides_env
    echo ""
    test_json_structure
    echo ""
    test_unknown_option
    echo ""
    test_debug_mode
    echo ""
    test_symlink_within_workspace
    echo ""
    test_depth_limit
    echo ""

    # Run scan_task tests
    echo "====================================="
    echo "scan_task() Function Tests"
    echo "====================================="
    echo ""
    test_scan_task_all_unchecked
    echo ""
    test_scan_task_only_completed
    echo ""
    test_scan_task_completed_and_tested
    echo ""
    test_scan_task_all_checked
    echo ""
    test_scan_task_uppercase_x
    echo ""
    test_scan_task_missing_file
    echo ""
    test_scan_task_empty_file
    echo ""
    test_scan_task_no_checkboxes
    echo ""
    test_scan_task_ignores_code_blocks
    echo ""
    test_scan_task_jira_style_id
    echo ""
    test_scan_task_sddloop_style_id
    echo ""
    test_scan_task_valid_json
    echo ""
    test_scan_task_partial_checkboxes
    echo ""
    test_strip_code_blocks
    echo ""
    test_scan_task_mixed_case
    echo ""
    test_scan_task_file_path
    echo ""

    # Summary
    echo "====================================="
    echo "Test Summary"
    echo "====================================="
    echo "Tests run: $TESTS_RUN"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo ""

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo "RESULT: FAILED"
        exit 1
    else
        echo "RESULT: PASSED"
        exit 0
    fi
}

main "$@"
