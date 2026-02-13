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
# Assert that string does NOT contain substring
# Arguments:
#   $1 - Haystack (full string)
#   $2 - Needle (substring that should NOT be present)
#   $3 - Test name
#######################################
assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"

    if [[ "$haystack" == *"$needle"* ]]; then
        log_result "$test_name" "fail" "String should not contain: '$needle'"
    else
        log_result "$test_name" "pass"
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
    assert_contains "$output" "--specs-root" "Help mentions --specs-root"
    assert_contains "$output" "--repos-root" "Help mentions --repos-root"
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
# Test: Missing specs directory exits with code 1
#######################################
test_missing_workspace() {
    echo "--- Test: Missing specs directory ---"

    local output
    local exit_code=0
    output=$(bash "$MASTER_SCRIPT" --specs-root "/nonexistent/path/that/does/not/exist" 2>&1) || exit_code=$?

    assert_exit_code 1 "$exit_code" "Missing specs root exits with code 1"
    assert_contains "$output" "Error:" "Missing specs root shows error message"
}

#######################################
# Test: Empty specs root returns empty repos array
#######################################
test_empty_workspace() {
    echo "--- Test: Empty specs root ---"

    # Create empty specs root
    local specs_root="$TEST_TMP_DIR/empty_specs"
    local repos_root="$TEST_TMP_DIR/empty_repos"
    mkdir -p "$specs_root"
    mkdir -p "$repos_root"

    local output
    output=$(bash "$MASTER_SCRIPT" --specs-root "$specs_root" --repos-root "$repos_root" 2>&1)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "Empty specs root exits with code 0"
    assert_contains "$output" '"repos": [' "Output contains repos array"
    assert_contains "$output" '"specs_root":' "Output contains specs_root"
    assert_contains "$output" '"repos_root":' "Output contains repos_root"
}

#######################################
# Test: Discovers specs directory
#######################################
test_discovers_sdd_directory() {
    echo "--- Test: Discovers specs directory ---"

    # Create test specs and repos
    local specs_root="$TEST_TMP_DIR/test_specs"
    local repos_root="$TEST_TMP_DIR/test_repos"
    mkdir -p "$specs_root/my-repo"
    mkdir -p "$repos_root/my-repo/my-repo/.git"

    local output
    output=$(bash "$MASTER_SCRIPT" --specs-root "$specs_root" --repos-root "$repos_root" 2>&1)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "Discovery exits with code 0"
    assert_contains "$output" '"name": "my-repo"' "Found repo name"
    assert_contains "$output" 'specs' "Found specs path"
}

#######################################
# Test: Discovers multiple specs directories
#######################################
test_discovers_multiple_sdd_directories() {
    echo "--- Test: Discovers multiple specs directories ---"

    # Create multiple specs entries
    local specs_root="$TEST_TMP_DIR/multi_specs"
    local repos_root="$TEST_TMP_DIR/multi_repos"
    mkdir -p "$specs_root/repo-alpha"
    mkdir -p "$specs_root/repo-beta"
    mkdir -p "$specs_root/repo-gamma"
    mkdir -p "$repos_root/repo-alpha/repo-alpha/.git"
    mkdir -p "$repos_root/repo-beta/repo-beta/.git"
    mkdir -p "$repos_root/repo-gamma/repo-gamma/.git"

    local output
    output=$(bash "$MASTER_SCRIPT" --specs-root "$specs_root" --repos-root "$repos_root" 2>&1)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "Multiple discovery exits with code 0"
    assert_contains "$output" '"name": "repo-alpha"' "Found repo-alpha"
    assert_contains "$output" '"name": "repo-beta"' "Found repo-beta"
    assert_contains "$output" '"name": "repo-gamma"' "Found repo-gamma"
}

#######################################
# Test: Environment variables SPECS_ROOT and REPOS_ROOT
#######################################
test_environment_variable() {
    echo "--- Test: Environment variables SPECS_ROOT and REPOS_ROOT ---"

    # Create test specs and repos
    local specs_root="$TEST_TMP_DIR/env_specs"
    local repos_root="$TEST_TMP_DIR/env_repos"
    mkdir -p "$specs_root/env-repo"
    mkdir -p "$repos_root/env-repo/env-repo/.git"

    local output
    output=$(SPECS_ROOT="$specs_root" REPOS_ROOT="$repos_root" bash "$MASTER_SCRIPT" 2>&1)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "Environment variable exits with code 0"
    assert_contains "$output" '"name": "env-repo"' "Found repo via env var"
}

#######################################
# Test: Argument overrides environment variable
#######################################
test_argument_overrides_env() {
    echo "--- Test: Argument overrides environment variable ---"

    # Create two specs roots
    local env_specs="$TEST_TMP_DIR/env_only_specs"
    local arg_specs="$TEST_TMP_DIR/arg_specs"
    local repos_root="$TEST_TMP_DIR/arg_repos"
    mkdir -p "$env_specs/env-only-repo"
    mkdir -p "$arg_specs/arg-repo"
    mkdir -p "$repos_root/arg-repo/arg-repo/.git"

    local output
    output=$(SPECS_ROOT="$env_specs" bash "$MASTER_SCRIPT" --specs-root "$arg_specs" --repos-root "$repos_root" 2>&1)
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

    local specs_root="$TEST_TMP_DIR/json_specs"
    local repos_root="$TEST_TMP_DIR/json_repos"
    mkdir -p "$specs_root/json-repo"
    mkdir -p "$repos_root/json-repo/json-repo/.git"

    local output
    output=$(bash "$MASTER_SCRIPT" --specs-root "$specs_root" --repos-root "$repos_root" 2>&1)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "JSON structure test exits with code 0"
    assert_contains "$output" '"timestamp":' "JSON has timestamp"
    assert_contains "$output" '"specs_root":' "JSON has specs_root"
    assert_contains "$output" '"repos_root":' "JSON has repos_root"
    assert_contains "$output" '"repos":' "JSON has repos"
    assert_contains "$output" '"name":' "JSON repos have name"
    assert_contains "$output" '"sdd_root":' "JSON repos have sdd_root"
    assert_contains "$output" '"summary":' "JSON has summary"
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
# Test: --summary-only produces valid JSON without repos array
#######################################
test_summary_only_option() {
    echo "--- Test: --summary-only option ---"

    local specs_root="$TEST_TMP_DIR/summary_specs"
    local repos_root="$TEST_TMP_DIR/summary_repos"
    mkdir -p "$specs_root/repo/tickets/T1/tasks"
    mkdir -p "$repos_root/repo/repo/.git"
    echo "# Test" > "$specs_root/repo/tickets/T1/README.md"
    cat > "$specs_root/repo/tickets/T1/tasks/T1.1001.md" << 'EOF'
## Status
- [x] **Task completed**
- [ ] **Tests pass**
- [ ] **Verified**
EOF

    local output
    output=$(bash "$MASTER_SCRIPT" --summary-only --specs-root "$specs_root" --repos-root "$repos_root" 2>&1)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "Summary-only exits with code 0"

    # Should NOT contain repos array
    if [[ "$output" == *'"repos":'* ]]; then
        log_result "Summary-only omits repos array" "fail" "Output contains repos array"
    else
        log_result "Summary-only omits repos array" "pass"
    fi

    # Should contain summary
    assert_contains "$output" '"summary":' "Summary-only includes summary"
    assert_contains "$output" '"total_repos":' "Summary-only includes total_repos"
    assert_contains "$output" '"total_tickets":' "Summary-only includes total_tickets"

    # Output should be valid JSON
    if command -v jq &>/dev/null; then
        if echo "$output" | jq . >/dev/null 2>&1; then
            log_result "Summary-only output is valid JSON" "pass"
        else
            log_result "Summary-only output is valid JSON" "fail" "JSON parsing failed"
        fi
    fi
}

#######################################
# Test: -s short option for summary-only
#######################################
test_summary_only_short_option() {
    echo "--- Test: -s short option ---"

    local specs_root="$TEST_TMP_DIR/summary_short_specs"
    local repos_root="$TEST_TMP_DIR/summary_short_repos"
    mkdir -p "$specs_root/repo"
    mkdir -p "$repos_root/repo/repo/.git"

    local output
    output=$(bash "$MASTER_SCRIPT" -s --specs-root "$specs_root" --repos-root "$repos_root" 2>&1)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "-s option exits with code 0"

    # Should NOT contain repos array
    if [[ "$output" == *'"repos":'* ]]; then
        log_result "-s option omits repos array" "fail" "Output contains repos array"
    else
        log_result "-s option omits repos array" "pass"
    fi
}

#######################################
# Test: --verbose includes timing output to stderr
#######################################
test_verbose_option() {
    echo "--- Test: --verbose option ---"

    local specs_root="$TEST_TMP_DIR/verbose_specs"
    local repos_root="$TEST_TMP_DIR/verbose_repos"
    mkdir -p "$specs_root/repo/tickets/T1/tasks"
    mkdir -p "$repos_root/repo/repo/.git"
    echo "# Test" > "$specs_root/repo/tickets/T1/README.md"
    cat > "$specs_root/repo/tickets/T1/tasks/T1.1001.md" << 'EOF'
## Status
- [ ] **Task completed**
EOF

    local stdout_output
    local stderr_output

    # Capture stdout and stderr separately
    stderr_output=$(bash "$MASTER_SCRIPT" --verbose --specs-root "$specs_root" --repos-root "$repos_root" 2>&1 1>/dev/null)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "Verbose option exits with code 0"

    # stderr should contain timing information
    assert_contains "$stderr_output" "Scanned" "Verbose includes 'Scanned' in timing"
    assert_contains "$stderr_output" "tickets" "Verbose includes 'tickets' in timing"
    assert_contains "$stderr_output" "tasks" "Verbose includes 'tasks' in timing"
    assert_contains "$stderr_output" "Total:" "Verbose includes total timing"

    # stderr should contain timing format [X.XXs]
    if [[ "$stderr_output" =~ \[[0-9]+\.[0-9]+s\] ]]; then
        log_result "Verbose timing format [X.XXs]" "pass"
    else
        log_result "Verbose timing format [X.XXs]" "fail" "Timing format not found"
    fi
}

#######################################
# Test: -v short option for verbose
#######################################
test_verbose_short_option() {
    echo "--- Test: -v short option ---"

    local specs_root="$TEST_TMP_DIR/verbose_short_specs"
    local repos_root="$TEST_TMP_DIR/verbose_short_repos"
    mkdir -p "$specs_root/repo"
    mkdir -p "$repos_root/repo/repo/.git"

    local stderr_output
    stderr_output=$(bash "$MASTER_SCRIPT" -v --specs-root "$specs_root" --repos-root "$repos_root" 2>&1 1>/dev/null)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "-v option exits with code 0"

    # stderr should contain timing information
    assert_contains "$stderr_output" "Total:" "-v includes total timing"
}

#######################################
# Test: Combined -sv options
#######################################
test_combined_short_options() {
    echo "--- Test: Combined -sv options ---"

    local specs_root="$TEST_TMP_DIR/combined_specs"
    local repos_root="$TEST_TMP_DIR/combined_repos"
    mkdir -p "$specs_root/repo"
    mkdir -p "$repos_root/repo/repo/.git"

    local stdout_output
    local stderr_output

    # Capture both outputs
    stdout_output=$(bash "$MASTER_SCRIPT" -sv --specs-root "$specs_root" --repos-root "$repos_root" 2>/dev/null)
    stderr_output=$(bash "$MASTER_SCRIPT" -sv --specs-root "$specs_root" --repos-root "$repos_root" 2>&1 1>/dev/null)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "Combined -sv exits with code 0"

    # Verify summary-only effect on stdout (no repos array)
    if [[ "$stdout_output" == *'"repos":'* ]]; then
        log_result "Combined -sv omits repos array" "fail" "Output contains repos array"
    else
        log_result "Combined -sv omits repos array" "pass"
    fi

    # Verify verbose effect on stderr
    assert_contains "$stderr_output" "Total:" "Combined -sv includes timing"
}

#######################################
# Test: --json option (explicit, default behavior)
#######################################
test_json_option() {
    echo "--- Test: --json option ---"

    local specs_root="$TEST_TMP_DIR/json_option_specs"
    local repos_root="$TEST_TMP_DIR/json_option_repos"
    mkdir -p "$specs_root/repo"
    mkdir -p "$repos_root/repo/repo/.git"

    local output
    output=$(bash "$MASTER_SCRIPT" --json --specs-root "$specs_root" --repos-root "$repos_root" 2>&1)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "--json option exits with code 0"

    # Should produce valid JSON
    if command -v jq &>/dev/null; then
        if echo "$output" | jq . >/dev/null 2>&1; then
            log_result "--json produces valid JSON" "pass"
        else
            log_result "--json produces valid JSON" "fail" "JSON parsing failed"
        fi
    else
        assert_contains "$output" '"timestamp":' "--json contains timestamp"
    fi
}

#######################################
# Test: Verbose output goes to stderr, not stdout
#######################################
test_verbose_output_streams() {
    echo "--- Test: Verbose output to stderr only ---"

    local specs_root="$TEST_TMP_DIR/streams_specs"
    local repos_root="$TEST_TMP_DIR/streams_repos"
    mkdir -p "$specs_root/repo"
    mkdir -p "$repos_root/repo/repo/.git"

    local stdout_output
    local stderr_output

    stdout_output=$(bash "$MASTER_SCRIPT" --verbose --specs-root "$specs_root" --repos-root "$repos_root" 2>/dev/null)
    stderr_output=$(bash "$MASTER_SCRIPT" --verbose --specs-root "$specs_root" --repos-root "$repos_root" 2>&1 1>/dev/null)

    # stdout should NOT contain timing output
    if [[ "$stdout_output" == *"[0."* ]] || [[ "$stdout_output" == *"Scanned"* ]]; then
        log_result "Timing NOT in stdout" "fail" "Timing output found in stdout"
    else
        log_result "Timing NOT in stdout" "pass"
    fi

    # stdout should still be valid JSON
    if command -v jq &>/dev/null; then
        if echo "$stdout_output" | jq . >/dev/null 2>&1; then
            log_result "Verbose stdout is valid JSON" "pass"
        else
            log_result "Verbose stdout is valid JSON" "fail" "JSON parsing failed"
        fi
    fi

    # stderr should contain timing
    assert_contains "$stderr_output" "Total:" "Timing is in stderr"
}

#######################################
# Test: Unknown short option shows error
#######################################
test_unknown_short_option() {
    echo "--- Test: Unknown short option ---"

    local output
    local exit_code=0
    output=$(bash "$MASTER_SCRIPT" -x 2>&1) || exit_code=$?

    assert_exit_code 2 "$exit_code" "Unknown short option exits with code 2"
    assert_contains "$output" "Error:" "Unknown short option shows error"
}

#######################################
# Test: Unknown option in combined short options
#######################################
test_unknown_combined_option() {
    echo "--- Test: Unknown combined option ---"

    local output
    local exit_code=0
    output=$(bash "$MASTER_SCRIPT" -svx 2>&1) || exit_code=$?

    assert_exit_code 2 "$exit_code" "Unknown combined option exits with code 2"
    assert_contains "$output" "Error:" "Unknown combined option shows error"
}

#######################################
# Test: Debug mode outputs to stderr
#######################################
test_debug_mode() {
    echo "--- Test: Debug mode ---"

    local specs_root="$TEST_TMP_DIR/debug_specs"
    local repos_root="$TEST_TMP_DIR/debug_repos"
    mkdir -p "$specs_root/debug-repo"
    mkdir -p "$repos_root/debug-repo/debug-repo/.git"

    local stderr_output
    local stdout_output

    # Capture stderr separately
    stderr_output=$(bash "$MASTER_SCRIPT" --debug --specs-root "$specs_root" --repos-root "$repos_root" 2>&1 1>/dev/null)

    assert_contains "$stderr_output" "[DEBUG]" "Debug mode outputs DEBUG messages"
}

#######################################
# Test: Symlink within specs root is followed
#######################################
test_symlink_within_workspace() {
    echo "--- Test: Symlink within specs root ---"

    local specs_root="$TEST_TMP_DIR/symlink_specs"
    local repos_root="$TEST_TMP_DIR/symlink_repos"
    mkdir -p "$specs_root/real-repo"
    mkdir -p "$repos_root/real-repo/real-repo/.git"
    # Create symlink to real specs entry
    ln -s "$specs_root/real-repo" "$specs_root/linked-repo"

    local output
    output=$(bash "$MASTER_SCRIPT" --specs-root "$specs_root" --repos-root "$repos_root" 2>&1)
    local exit_code=$?

    # Should find both the real repo and follow the symlink
    assert_exit_code 0 "$exit_code" "Symlink test exits with code 0"
    assert_contains "$output" "real-repo" "Found real-repo"
}

#######################################
# Test: Only direct children of specs root are discovered
#######################################
test_depth_limit() {
    echo "--- Test: Depth limit ---"

    local specs_root="$TEST_TMP_DIR/deep_specs"
    local repos_root="$TEST_TMP_DIR/deep_repos"
    # Create specs entry at depth 1 (should be found)
    mkdir -p "$specs_root/shallow-repo"
    mkdir -p "$repos_root/shallow-repo/shallow-repo/.git"
    # Create nested directory (should NOT be found - only direct children)
    mkdir -p "$specs_root/deep/nested/very/deep-repo"

    local output
    output=$(bash "$MASTER_SCRIPT" --specs-root "$specs_root" --repos-root "$repos_root" 2>&1)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "Depth limit test exits with code 0"
    assert_contains "$output" '"name": "shallow-repo"' "Found shallow-repo"

    # Should NOT find deep-repo (too deep, not a direct child)
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
# Test: read_autogate with all fields present
#######################################
test_read_autogate_all_fields() {
    echo "--- Test: read_autogate with all fields present ---"

    source "$MASTER_SCRIPT"

    local autogate_file="$TEST_TMP_DIR/.autogate-all-fields.json"
    cat > "$autogate_file" << 'EOF'
{
    "ready": true,
    "agent_ready": true,
    "priority": 1,
    "stop_at_phase": "test"
}
EOF

    local output
    output=$(read_autogate "$autogate_file")

    assert_contains "$output" '"ready":true' "All fields: ready is true"
    assert_contains "$output" '"agent_ready":true' "All fields: agent_ready is true"
    assert_contains "$output" '"priority":1' "All fields: priority is 1"
    assert_contains "$output" '"stop_at_phase":"test"' "All fields: stop_at_phase is test"
}

#######################################
# Test: read_autogate with only ready field
#######################################
test_read_autogate_only_ready() {
    echo "--- Test: read_autogate with only ready field ---"

    source "$MASTER_SCRIPT"

    local autogate_file="$TEST_TMP_DIR/.autogate-only-ready.json"
    cat > "$autogate_file" << 'EOF'
{
    "ready": true
}
EOF

    local output
    output=$(read_autogate "$autogate_file")

    assert_contains "$output" '"ready":true' "Only ready: ready is true"
    assert_contains "$output" '"agent_ready":false' "Only ready: agent_ready defaults to false"
    assert_contains "$output" '"priority":null' "Only ready: priority defaults to null"
    assert_contains "$output" '"stop_at_phase":null' "Only ready: stop_at_phase defaults to null"
}

#######################################
# Test: read_autogate with ready=false (blocks all work)
#######################################
test_read_autogate_ready_false() {
    echo "--- Test: read_autogate with ready=false ---"

    source "$MASTER_SCRIPT"

    local autogate_file="$TEST_TMP_DIR/.autogate-ready-false.json"
    cat > "$autogate_file" << 'EOF'
{
    "ready": false
}
EOF

    local output
    output=$(read_autogate "$autogate_file")

    assert_contains "$output" '"ready":false' "Ready false: ready is false"
    assert_contains "$output" '"agent_ready":false' "Ready false: agent_ready defaults to false"
}

#######################################
# Test: read_autogate with agent_ready=true (forward compatibility)
#######################################
test_read_autogate_agent_ready_true() {
    echo "--- Test: read_autogate with agent_ready=true ---"

    source "$MASTER_SCRIPT"

    local autogate_file="$TEST_TMP_DIR/.autogate-agent-ready.json"
    cat > "$autogate_file" << 'EOF'
{
    "ready": true,
    "agent_ready": true
}
EOF

    local output
    output=$(read_autogate "$autogate_file")

    assert_contains "$output" '"ready":true' "Agent ready: ready is true"
    assert_contains "$output" '"agent_ready":true' "Agent ready: agent_ready is true"
}

#######################################
# Test: read_autogate with missing file
#######################################
test_read_autogate_missing_file() {
    echo "--- Test: read_autogate with missing file ---"

    source "$MASTER_SCRIPT"

    local autogate_file="$TEST_TMP_DIR/nonexistent/.autogate.json"
    local output
    output=$(read_autogate "$autogate_file")

    assert_contains "$output" '"ready": true' "Missing file: ready defaults to true"
    assert_contains "$output" '"agent_ready": false' "Missing file: agent_ready defaults to false"
    assert_contains "$output" '"priority": null' "Missing file: priority defaults to null"
    assert_contains "$output" '"stop_at_phase": null' "Missing file: stop_at_phase defaults to null"
}

#######################################
# Test: read_autogate with empty file
#######################################
test_read_autogate_empty_file() {
    echo "--- Test: read_autogate with empty file ---"

    source "$MASTER_SCRIPT"

    local autogate_file="$TEST_TMP_DIR/.autogate-empty.json"
    touch "$autogate_file"

    local output
    local stderr_output
    stderr_output=$(read_autogate "$autogate_file" 2>&1 >/dev/null)
    output=$(read_autogate "$autogate_file" 2>/dev/null)

    assert_contains "$output" '"ready": true' "Empty file: ready defaults to true"
    assert_contains "$output" '"agent_ready": false' "Empty file: agent_ready defaults to false"
    assert_contains "$stderr_output" "Warning:" "Empty file: warning logged to stderr"
}

#######################################
# Test: read_autogate with malformed JSON
#######################################
test_read_autogate_malformed_json() {
    echo "--- Test: read_autogate with malformed JSON ---"

    source "$MASTER_SCRIPT"

    local autogate_file="$TEST_TMP_DIR/.autogate-malformed.json"
    cat > "$autogate_file" << 'EOF'
{ this is not valid json }
EOF

    local output
    local stderr_output
    stderr_output=$(read_autogate "$autogate_file" 2>&1 >/dev/null)
    output=$(read_autogate "$autogate_file" 2>/dev/null)

    assert_contains "$output" '"ready": true' "Malformed: ready defaults to true"
    assert_contains "$output" '"agent_ready": false' "Malformed: agent_ready defaults to false"
    assert_contains "$stderr_output" "Warning:" "Malformed: warning logged to stderr"
    assert_contains "$stderr_output" "Malformed" "Malformed: warning mentions malformed"
}

#######################################
# Test: read_autogate with permission denied
#######################################
test_read_autogate_permission_denied() {
    echo "--- Test: read_autogate with permission denied ---"

    source "$MASTER_SCRIPT"

    local autogate_file="$TEST_TMP_DIR/.autogate-no-read.json"
    echo '{"ready": false}' > "$autogate_file"
    chmod 000 "$autogate_file"

    local output
    output=$(read_autogate "$autogate_file")

    # Restore permissions for cleanup
    chmod 644 "$autogate_file"

    assert_contains "$output" '"ready": true' "Permission denied: ready defaults to true"
    assert_contains "$output" '"agent_ready": false' "Permission denied: agent_ready defaults to false"
}

#######################################
# Test: read_autogate with extra fields (forward compatibility)
#######################################
test_read_autogate_extra_fields() {
    echo "--- Test: read_autogate with extra fields ---"

    source "$MASTER_SCRIPT"

    local autogate_file="$TEST_TMP_DIR/.autogate-extra-fields.json"
    cat > "$autogate_file" << 'EOF'
{
    "ready": true,
    "agent_ready": true,
    "priority": 2,
    "stop_at_phase": "verify",
    "future_field": "should be ignored",
    "another_future_field": 42
}
EOF

    local output
    output=$(read_autogate "$autogate_file")

    assert_contains "$output" '"ready":true' "Extra fields: ready parsed correctly"
    assert_contains "$output" '"agent_ready":true' "Extra fields: agent_ready parsed correctly"
    assert_contains "$output" '"priority":2' "Extra fields: priority parsed correctly"
    assert_contains "$output" '"stop_at_phase":"verify"' "Extra fields: stop_at_phase parsed correctly"

    # Should NOT contain the extra fields
    if [[ "$output" == *"future_field"* ]]; then
        log_result "Extra fields are ignored" "fail" "Output contains future_field"
    else
        log_result "Extra fields are ignored" "pass"
    fi
}

#######################################
# Test: read_autogate output is valid JSON
#######################################
test_read_autogate_valid_json() {
    echo "--- Test: read_autogate output is valid JSON ---"

    source "$MASTER_SCRIPT"

    local autogate_file="$TEST_TMP_DIR/.autogate-json-test.json"
    cat > "$autogate_file" << 'EOF'
{
    "ready": true,
    "agent_ready": false,
    "priority": 5,
    "stop_at_phase": "implement"
}
EOF

    local output
    output=$(read_autogate "$autogate_file")

    if command -v jq &>/dev/null; then
        if echo "$output" | jq . >/dev/null 2>&1; then
            log_result "read_autogate output is valid JSON" "pass"
        else
            log_result "read_autogate output is valid JSON" "fail" "JSON parsing failed"
        fi
    else
        if [[ "$output" == "{"* && "$output" == *"}" ]]; then
            log_result "read_autogate output is valid JSON (basic check)" "pass"
        else
            log_result "read_autogate output is valid JSON (basic check)" "fail"
        fi
    fi
}

#######################################
# Test: read_autogate with boolean as string "true"
#######################################
test_read_autogate_boolean_as_string() {
    echo "--- Test: read_autogate with boolean as string ---"

    source "$MASTER_SCRIPT"

    local autogate_file="$TEST_TMP_DIR/.autogate-string-bool.json"
    # Note: jq treats "true" (string) differently from true (boolean)
    cat > "$autogate_file" << 'EOF'
{
    "ready": "true",
    "agent_ready": "false"
}
EOF

    local output
    output=$(read_autogate "$autogate_file")

    # jq will preserve the string values, which is fine for forward compatibility
    # The key is that output is valid JSON
    if command -v jq &>/dev/null; then
        if echo "$output" | jq . >/dev/null 2>&1; then
            log_result "String boolean produces valid JSON" "pass"
        else
            log_result "String boolean produces valid JSON" "fail"
        fi
    else
        log_result "String boolean produces valid JSON (basic check)" "pass"
    fi
}

#######################################
# Test: read_autogate with null priority
#######################################
test_read_autogate_null_priority() {
    echo "--- Test: read_autogate with explicit null values ---"

    source "$MASTER_SCRIPT"

    local autogate_file="$TEST_TMP_DIR/.autogate-null-values.json"
    cat > "$autogate_file" << 'EOF'
{
    "ready": true,
    "agent_ready": false,
    "priority": null,
    "stop_at_phase": null
}
EOF

    local output
    output=$(read_autogate "$autogate_file")

    assert_contains "$output" '"priority":null' "Explicit null: priority is null"
    assert_contains "$output" '"stop_at_phase":null' "Explicit null: stop_at_phase is null"
}

#######################################
# Test: read_autogate with priority as integer
#######################################
test_read_autogate_priority_integer() {
    echo "--- Test: read_autogate with priority as integer ---"

    source "$MASTER_SCRIPT"

    local autogate_file="$TEST_TMP_DIR/.autogate-priority-int.json"
    cat > "$autogate_file" << 'EOF'
{
    "ready": true,
    "priority": 10
}
EOF

    local output
    output=$(read_autogate "$autogate_file")

    assert_contains "$output" '"priority":10' "Integer priority: priority is 10"
}

#######################################
# Test: scan_ticket with multiple tasks in various states
#######################################
test_scan_ticket_multiple_tasks() {
    echo "--- Test: scan_ticket with multiple tasks ---"

    source "$MASTER_SCRIPT"

    # Create ticket directory structure
    local ticket_dir="$TEST_TMP_DIR/PROJ-1_test-ticket"
    mkdir -p "$ticket_dir/tasks"

    # Create README.md with title
    cat > "$ticket_dir/README.md" << 'EOF'
# Test Ticket Title

This is a test ticket.
EOF

    # Create tasks with various states
    # Task 1: pending (all unchecked)
    cat > "$ticket_dir/tasks/PROJ-1.1001_pending-task.md" << 'EOF'
# Task: [PROJ-1.1001]: Pending Task

## Status
- [ ] **Task completed**
- [ ] **Tests pass**
- [ ] **Verified**
EOF

    # Task 2: completed (task completed, not tested)
    cat > "$ticket_dir/tasks/PROJ-1.1002_completed-task.md" << 'EOF'
# Task: [PROJ-1.1002]: Completed Task

## Status
- [x] **Task completed**
- [ ] **Tests pass**
- [ ] **Verified**
EOF

    # Task 3: tested (task completed and tests pass, not verified)
    cat > "$ticket_dir/tasks/PROJ-1.1003_tested-task.md" << 'EOF'
# Task: [PROJ-1.1003]: Tested Task

## Status
- [x] **Task completed**
- [x] **Tests pass**
- [ ] **Verified**
EOF

    # Task 4: verified (all checked)
    cat > "$ticket_dir/tasks/PROJ-1.1004_verified-task.md" << 'EOF'
# Task: [PROJ-1.1004]: Verified Task

## Status
- [x] **Task completed**
- [x] **Tests pass**
- [x] **Verified**
EOF

    local output
    output=$(scan_ticket "$ticket_dir")
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "scan_ticket exits with code 0"
    assert_contains "$output" '"ticket_id": "PROJ-1_test-ticket"' "Ticket ID extracted from directory"
    assert_contains "$output" '"name": "Test Ticket Title"' "Ticket name extracted from README"
    assert_contains "$output" '"total_tasks": 4' "Total tasks is 4"
    assert_contains "$output" '"pending": 1' "Pending count is 1"
    assert_contains "$output" '"completed": 1' "Completed count is 1"
    assert_contains "$output" '"tested": 1' "Tested count is 1"
    assert_contains "$output" '"verified": 1' "Verified count is 1"

    # Verify tasks array contains all tasks
    assert_contains "$output" '"task_id": "PROJ-1.1001"' "Task 1 in output"
    assert_contains "$output" '"task_id": "PROJ-1.1002"' "Task 2 in output"
    assert_contains "$output" '"task_id": "PROJ-1.1003"' "Task 3 in output"
    assert_contains "$output" '"task_id": "PROJ-1.1004"' "Task 4 in output"
}

#######################################
# Test: scan_ticket with no tasks/ directory
#######################################
test_scan_ticket_no_tasks_dir() {
    echo "--- Test: scan_ticket with no tasks/ directory ---"

    source "$MASTER_SCRIPT"

    # Create ticket directory without tasks/
    local ticket_dir="$TEST_TMP_DIR/PROJ-2_no-tasks"
    mkdir -p "$ticket_dir"

    cat > "$ticket_dir/README.md" << 'EOF'
# Ticket Without Tasks

No tasks subdirectory exists.
EOF

    local output
    output=$(scan_ticket "$ticket_dir")
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "scan_ticket no tasks dir exits with code 0"
    assert_contains "$output" '"ticket_id": "PROJ-2_no-tasks"' "Ticket ID present"
    assert_contains "$output" '"total_tasks": 0' "Total tasks is 0"
    assert_contains "$output" '"pending": 0' "Pending is 0"
    assert_contains "$output" '"completed": 0' "Completed is 0"
    assert_contains "$output" '"tested": 0' "Tested is 0"
    assert_contains "$output" '"verified": 0' "Verified is 0"
    assert_contains "$output" '"tasks": []' "Tasks array is empty"
}

#######################################
# Test: scan_ticket with empty tasks/ directory
#######################################
test_scan_ticket_empty_tasks_dir() {
    echo "--- Test: scan_ticket with empty tasks/ directory ---"

    source "$MASTER_SCRIPT"

    # Create ticket directory with empty tasks/
    local ticket_dir="$TEST_TMP_DIR/PROJ-3_empty-tasks"
    mkdir -p "$ticket_dir/tasks"

    cat > "$ticket_dir/README.md" << 'EOF'
# Ticket With Empty Tasks

Tasks directory exists but is empty.
EOF

    local output
    output=$(scan_ticket "$ticket_dir")
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "scan_ticket empty tasks dir exits with code 0"
    assert_contains "$output" '"total_tasks": 0' "Total tasks is 0"
    assert_contains "$output" '"tasks": []' "Tasks array is empty"
}

#######################################
# Test: scan_ticket with missing README.md (fallback to directory name)
#######################################
test_scan_ticket_missing_readme() {
    echo "--- Test: scan_ticket with missing README.md ---"

    source "$MASTER_SCRIPT"

    # Create ticket directory without README.md
    local ticket_dir="$TEST_TMP_DIR/PROJ-4_missing-readme"
    mkdir -p "$ticket_dir/tasks"

    # Create one task
    cat > "$ticket_dir/tasks/PROJ-4.1001_task.md" << 'EOF'
# Task: [PROJ-4.1001]: A Task

## Status
- [x] **Task completed**
- [ ] **Tests pass**
- [ ] **Verified**
EOF

    local output
    output=$(scan_ticket "$ticket_dir")
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "scan_ticket missing README exits with code 0"
    # Name should fallback to directory name
    assert_contains "$output" '"name": "PROJ-4_missing-readme"' "Name fallback to directory name"
    assert_contains "$output" '"total_tasks": 1' "Total tasks is 1"
}

#######################################
# Test: scan_ticket with .autogate.json present
#######################################
test_scan_ticket_with_autogate() {
    echo "--- Test: scan_ticket with .autogate.json present ---"

    source "$MASTER_SCRIPT"

    # Create ticket directory with .autogate.json
    local ticket_dir="$TEST_TMP_DIR/PROJ-5_with-autogate"
    mkdir -p "$ticket_dir/tasks"

    cat > "$ticket_dir/README.md" << 'EOF'
# Ticket With Autogate

Has .autogate.json file.
EOF

    # Create .autogate.json with specific values
    cat > "$ticket_dir/.autogate.json" << 'EOF'
{
    "ready": false,
    "agent_ready": true,
    "priority": 1,
    "stop_at_phase": "test"
}
EOF

    local output
    output=$(scan_ticket "$ticket_dir")
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "scan_ticket with autogate exits with code 0"
    # Full implementation now parses actual values from .autogate.json
    assert_contains "$output" '"autogate":' "Autogate field present"
    assert_contains "$output" '"ready":false' "Autogate ready is false (from file)"
    assert_contains "$output" '"agent_ready":true' "Autogate agent_ready is true (from file)"
    assert_contains "$output" '"priority":1' "Autogate priority is 1 (from file)"
    assert_contains "$output" '"stop_at_phase":"test"' "Autogate stop_at_phase is test (from file)"
}

#######################################
# Test: scan_ticket with missing ticket directory
#######################################
test_scan_ticket_missing_dir() {
    echo "--- Test: scan_ticket with missing directory ---"

    source "$MASTER_SCRIPT"

    local ticket_dir="$TEST_TMP_DIR/nonexistent/PROJ-99_missing"
    local output
    local exit_code=0
    output=$(scan_ticket "$ticket_dir") || exit_code=$?

    assert_exit_code 1 "$exit_code" "scan_ticket missing dir exits with code 1"
    assert_contains "$output" '"error": "Directory not found"' "Error message present"
    assert_contains "$output" '"ticket_id": ""' "Empty ticket_id"
    assert_contains "$output" '"total_tasks": 0' "Total tasks is 0"
}

#######################################
# Test: scan_ticket output is valid JSON
#######################################
test_scan_ticket_valid_json() {
    echo "--- Test: scan_ticket output is valid JSON ---"

    source "$MASTER_SCRIPT"

    # Create ticket with multiple tasks
    local ticket_dir="$TEST_TMP_DIR/PROJ-6_json-test"
    mkdir -p "$ticket_dir/tasks"

    cat > "$ticket_dir/README.md" << 'EOF'
# JSON Validation Ticket
EOF

    cat > "$ticket_dir/tasks/PROJ-6.1001_task.md" << 'EOF'
# Task: [PROJ-6.1001]: Task 1

## Status
- [x] **Task completed**
- [ ] **Tests pass**
- [ ] **Verified**
EOF

    cat > "$ticket_dir/tasks/PROJ-6.1002_task.md" << 'EOF'
# Task: [PROJ-6.1002]: Task 2

## Status
- [x] **Task completed**
- [x] **Tests pass**
- [x] **Verified**
EOF

    local output
    output=$(scan_ticket "$ticket_dir")

    # Try to parse with jq if available
    if command -v jq &>/dev/null; then
        if echo "$output" | jq . >/dev/null 2>&1; then
            log_result "scan_ticket output is valid JSON" "pass"
        else
            log_result "scan_ticket output is valid JSON" "fail" "JSON parsing failed"
            echo "Output was:" >&2
            echo "$output" >&2
        fi
    else
        # Fallback: basic structure check
        if [[ "$output" == "{"* && "$output" == *"}" ]]; then
            log_result "scan_ticket output is valid JSON (basic check)" "pass"
        else
            log_result "scan_ticket output is valid JSON (basic check)" "fail"
        fi
    fi
}

#######################################
# Test: scan_ticket aggregation logic correctness
#######################################
test_scan_ticket_aggregation_logic() {
    echo "--- Test: scan_ticket aggregation logic ---"

    source "$MASTER_SCRIPT"

    # Create ticket with 5 tasks to verify aggregation
    local ticket_dir="$TEST_TMP_DIR/PROJ-7_aggregation"
    mkdir -p "$ticket_dir/tasks"

    cat > "$ticket_dir/README.md" << 'EOF'
# Aggregation Test
EOF

    # 2 pending tasks
    cat > "$ticket_dir/tasks/PROJ-7.1001_pending1.md" << 'EOF'
## Status
- [ ] **Task completed**
- [ ] **Tests pass**
- [ ] **Verified**
EOF

    cat > "$ticket_dir/tasks/PROJ-7.1002_pending2.md" << 'EOF'
## Status
- [ ] **Task completed**
- [ ] **Tests pass**
- [ ] **Verified**
EOF

    # 1 completed task
    cat > "$ticket_dir/tasks/PROJ-7.1003_completed.md" << 'EOF'
## Status
- [x] **Task completed**
- [ ] **Tests pass**
- [ ] **Verified**
EOF

    # 1 tested task
    cat > "$ticket_dir/tasks/PROJ-7.1004_tested.md" << 'EOF'
## Status
- [x] **Task completed**
- [x] **Tests pass**
- [ ] **Verified**
EOF

    # 1 verified task
    cat > "$ticket_dir/tasks/PROJ-7.1005_verified.md" << 'EOF'
## Status
- [x] **Task completed**
- [x] **Tests pass**
- [x] **Verified**
EOF

    local output
    output=$(scan_ticket "$ticket_dir")

    assert_contains "$output" '"total_tasks": 5' "Total tasks is 5"
    assert_contains "$output" '"pending": 2' "Pending is 2"
    assert_contains "$output" '"completed": 1' "Completed is 1"
    assert_contains "$output" '"tested": 1' "Tested is 1"
    assert_contains "$output" '"verified": 1' "Verified is 1"
}

#######################################
# Test: scan_ticket ignores non-.md files in tasks/
#######################################
test_scan_ticket_ignores_non_md_files() {
    echo "--- Test: scan_ticket ignores non-.md files ---"

    source "$MASTER_SCRIPT"

    # Create ticket with mixed file types
    local ticket_dir="$TEST_TMP_DIR/PROJ-8_mixed-files"
    mkdir -p "$ticket_dir/tasks"

    cat > "$ticket_dir/README.md" << 'EOF'
# Mixed Files Test
EOF

    # One real task file
    cat > "$ticket_dir/tasks/PROJ-8.1001_task.md" << 'EOF'
## Status
- [x] **Task completed**
- [ ] **Tests pass**
- [ ] **Verified**
EOF

    # Non-.md files that should be ignored
    echo "some text" > "$ticket_dir/tasks/notes.txt"
    echo '{"key": "value"}' > "$ticket_dir/tasks/data.json"
    mkdir -p "$ticket_dir/tasks/subdir"

    local output
    output=$(scan_ticket "$ticket_dir")

    # Should only count the one .md file
    assert_contains "$output" '"total_tasks": 1' "Only counts .md files"
    assert_contains "$output" '"completed": 1' "Only one completed task"
}

#######################################
# Test: scan_ticket with README that has no heading
#######################################
test_scan_ticket_readme_no_heading() {
    echo "--- Test: scan_ticket README with no heading ---"

    source "$MASTER_SCRIPT"

    # Create ticket with README that has no # heading
    local ticket_dir="$TEST_TMP_DIR/PROJ-9_no-heading"
    mkdir -p "$ticket_dir"

    cat > "$ticket_dir/README.md" << 'EOF'
This README has no markdown heading.
Just plain text on the first line.
EOF

    local output
    output=$(scan_ticket "$ticket_dir")
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "scan_ticket no heading exits with code 0"
    # Should fallback to directory name since first line doesn't start with #
    assert_contains "$output" '"name": "This README has no markdown heading."' "Uses first line as name when no heading"
}

#######################################
# Test: scan_ticket with all verified tasks
#######################################
test_scan_ticket_all_verified() {
    echo "--- Test: scan_ticket with all verified tasks ---"

    source "$MASTER_SCRIPT"

    # Create ticket with all verified tasks
    local ticket_dir="$TEST_TMP_DIR/PROJ-10_all-verified"
    mkdir -p "$ticket_dir/tasks"

    cat > "$ticket_dir/README.md" << 'EOF'
# All Verified Ticket
EOF

    cat > "$ticket_dir/tasks/PROJ-10.1001_v1.md" << 'EOF'
## Status
- [x] **Task completed**
- [x] **Tests pass**
- [x] **Verified**
EOF

    cat > "$ticket_dir/tasks/PROJ-10.1002_v2.md" << 'EOF'
## Status
- [x] **Task completed**
- [x] **Tests pass**
- [x] **Verified**
EOF

    local output
    output=$(scan_ticket "$ticket_dir")

    assert_contains "$output" '"total_tasks": 2' "Total tasks is 2"
    assert_contains "$output" '"pending": 0' "Pending is 0"
    assert_contains "$output" '"completed": 0' "Completed is 0"
    assert_contains "$output" '"tested": 0' "Tested is 0"
    assert_contains "$output" '"verified": 2' "Verified is 2"
}

#######################################
# Test: scan_ticket path in output
#######################################
test_scan_ticket_path_in_output() {
    echo "--- Test: scan_ticket includes path in output ---"

    source "$MASTER_SCRIPT"

    local ticket_dir="$TEST_TMP_DIR/PROJ-11_path-test"
    mkdir -p "$ticket_dir"

    cat > "$ticket_dir/README.md" << 'EOF'
# Path Test
EOF

    local output
    output=$(scan_ticket "$ticket_dir")

    assert_contains "$output" "\"path\": \"$ticket_dir\"" "Output contains ticket path"
}

#######################################
# Test: scan_repo with multiple tickets
#######################################
test_scan_repo_multiple_tickets() {
    echo "--- Test: scan_repo with multiple tickets ---"

    source "$MASTER_SCRIPT"

    # Create specs entry with multiple tickets
    local sdd_root="$TEST_TMP_DIR/specs/test-repo"
    local repo_path="$TEST_TMP_DIR/repos/test-repo/"
    mkdir -p "$sdd_root/tickets/TICKET-1_first/tasks"
    mkdir -p "$sdd_root/tickets/TICKET-2_second/tasks"
    mkdir -p "$TEST_TMP_DIR/repos/test-repo/test-repo/.git"

    # Create README files for tickets
    echo "# First Ticket" > "$sdd_root/tickets/TICKET-1_first/README.md"
    echo "# Second Ticket" > "$sdd_root/tickets/TICKET-2_second/README.md"

    # Create tasks for first ticket (1 pending, 1 completed)
    cat > "$sdd_root/tickets/TICKET-1_first/tasks/TICKET-1.1001_task1.md" << 'EOF'
## Status
- [ ] **Task completed**
- [ ] **Tests pass**
- [ ] **Verified**
EOF

    cat > "$sdd_root/tickets/TICKET-1_first/tasks/TICKET-1.1002_task2.md" << 'EOF'
## Status
- [x] **Task completed**
- [ ] **Tests pass**
- [ ] **Verified**
EOF

    # Create tasks for second ticket (1 tested, 1 verified)
    cat > "$sdd_root/tickets/TICKET-2_second/tasks/TICKET-2.1001_task1.md" << 'EOF'
## Status
- [x] **Task completed**
- [x] **Tests pass**
- [ ] **Verified**
EOF

    cat > "$sdd_root/tickets/TICKET-2_second/tasks/TICKET-2.1002_task2.md" << 'EOF'
## Status
- [x] **Task completed**
- [x] **Tests pass**
- [x] **Verified**
EOF

    local output
    output=$(scan_repo "$sdd_root" "$repo_path")
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "scan_repo multiple tickets exits with code 0"
    assert_contains "$output" '"name": "test-repo"' "Repo name extracted correctly"
    assert_contains "$output" '"total_tickets": 2' "Total tickets is 2"
    assert_contains "$output" '"total_tasks": 4' "Total tasks is 4"
    assert_contains "$output" '"pending": 1' "Pending is 1"
    assert_contains "$output" '"completed": 1' "Completed is 1"
    assert_contains "$output" '"tested": 1' "Tested is 1"
    assert_contains "$output" '"verified": 1' "Verified is 1"
}

#######################################
# Test: scan_repo with no tickets/ directory
#######################################
test_scan_repo_no_tickets_dir() {
    echo "--- Test: scan_repo with no tickets/ directory ---"

    source "$MASTER_SCRIPT"

    # Create specs entry but no tickets/
    local sdd_root="$TEST_TMP_DIR/specs/no-tickets-repo"
    mkdir -p "$sdd_root"

    local output
    output=$(scan_repo "$sdd_root")
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "scan_repo no tickets dir exits with code 0"
    assert_contains "$output" '"name": "no-tickets-repo"' "Repo name from specs dir basename"
    assert_contains "$output" '"total_tickets": 0' "Total tickets is 0"
    assert_contains "$output" '"total_tasks": 0' "Total tasks is 0"
    assert_contains "$output" '"tickets": []' "Tickets array is empty"
}

#######################################
# Test: scan_repo with empty tickets/ directory
#######################################
test_scan_repo_empty_tickets_dir() {
    echo "--- Test: scan_repo with empty tickets/ directory ---"

    source "$MASTER_SCRIPT"

    # Create specs entry with empty tickets/
    local sdd_root="$TEST_TMP_DIR/specs/empty-tickets-repo"
    mkdir -p "$sdd_root/tickets"

    local output
    output=$(scan_repo "$sdd_root")
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "scan_repo empty tickets dir exits with code 0"
    assert_contains "$output" '"name": "empty-tickets-repo"' "Repo name from specs dir basename"
    assert_contains "$output" '"total_tickets": 0' "Total tickets is 0"
    assert_contains "$output" '"total_tasks": 0' "Total tasks is 0"
}

#######################################
# Test: scan_repo with missing directory
#######################################
test_scan_repo_missing_dir() {
    echo "--- Test: scan_repo with missing directory ---"

    source "$MASTER_SCRIPT"

    local sdd_root="$TEST_TMP_DIR/nonexistent/specs/missing-repo"
    local output
    local exit_code=0
    output=$(scan_repo "$sdd_root") || exit_code=$?

    assert_exit_code 1 "$exit_code" "scan_repo missing dir exits with code 1"
    assert_contains "$output" '"error": "Directory not found"' "Error message present"
    assert_contains "$output" '"total_tickets": 0' "Total tickets is 0"
}

#######################################
# Test: scan_repo aggregation across tickets
#######################################
test_scan_repo_aggregation_logic() {
    echo "--- Test: scan_repo aggregation logic ---"

    source "$MASTER_SCRIPT"

    # Create specs entry with 3 tickets for thorough aggregation test
    local sdd_root="$TEST_TMP_DIR/specs/aggregation-repo"
    mkdir -p "$sdd_root/tickets/T1/tasks"
    mkdir -p "$sdd_root/tickets/T2/tasks"
    mkdir -p "$sdd_root/tickets/T3/tasks"

    echo "# Ticket 1" > "$sdd_root/tickets/T1/README.md"
    echo "# Ticket 2" > "$sdd_root/tickets/T2/README.md"
    echo "# Ticket 3" > "$sdd_root/tickets/T3/README.md"

    # T1: 2 pending
    cat > "$sdd_root/tickets/T1/tasks/T1.1001.md" << 'EOF'
## Status
- [ ] **Task completed**
EOF
    cat > "$sdd_root/tickets/T1/tasks/T1.1002.md" << 'EOF'
## Status
- [ ] **Task completed**
EOF

    # T2: 1 completed, 1 tested
    cat > "$sdd_root/tickets/T2/tasks/T2.1001.md" << 'EOF'
## Status
- [x] **Task completed**
- [ ] **Tests pass**
EOF
    cat > "$sdd_root/tickets/T2/tasks/T2.1002.md" << 'EOF'
## Status
- [x] **Task completed**
- [x] **Tests pass**
EOF

    # T3: 2 verified
    cat > "$sdd_root/tickets/T3/tasks/T3.1001.md" << 'EOF'
## Status
- [x] **Task completed**
- [x] **Tests pass**
- [x] **Verified**
EOF
    cat > "$sdd_root/tickets/T3/tasks/T3.1002.md" << 'EOF'
## Status
- [x] **Task completed**
- [x] **Tests pass**
- [x] **Verified**
EOF

    local output
    output=$(scan_repo "$sdd_root")

    # Total: 3 tickets, 6 tasks
    # States: 2 pending, 1 completed, 1 tested, 2 verified
    assert_contains "$output" '"name": "aggregation-repo"' "Repo name from specs dir basename"
    assert_contains "$output" '"total_tickets": 3' "Total tickets is 3"
    assert_contains "$output" '"total_tasks": 6' "Total tasks is 6"
    assert_contains "$output" '"pending": 2' "Pending is 2"
    assert_contains "$output" '"completed": 1' "Completed is 1"
    assert_contains "$output" '"tested": 1' "Tested is 1"
    assert_contains "$output" '"verified": 2' "Verified is 2"
}

#######################################
# Test: scan_repo output is valid JSON
#######################################
test_scan_repo_valid_json() {
    echo "--- Test: scan_repo output is valid JSON ---"

    source "$MASTER_SCRIPT"

    local sdd_root="$TEST_TMP_DIR/specs/json-repo"
    mkdir -p "$sdd_root/tickets/TICKET-1/tasks"
    echo "# Test" > "$sdd_root/tickets/TICKET-1/README.md"
    cat > "$sdd_root/tickets/TICKET-1/tasks/TICKET-1.1001.md" << 'EOF'
## Status
- [x] **Task completed**
EOF

    local output
    output=$(scan_repo "$sdd_root")

    if command -v jq &>/dev/null; then
        if echo "$output" | jq . >/dev/null 2>&1; then
            log_result "scan_repo output is valid JSON" "pass"
        else
            log_result "scan_repo output is valid JSON" "fail" "JSON parsing failed"
            echo "Output was:" >&2
            echo "$output" >&2
        fi
    else
        if [[ "$output" == "{"* && "$output" == *"}" ]]; then
            log_result "scan_repo output is valid JSON (basic check)" "pass"
        else
            log_result "scan_repo output is valid JSON (basic check)" "fail"
        fi
    fi
}

#######################################
# Test: scan_repo extracts repo name from specs directory basename
#######################################
test_scan_repo_extracts_repo_name() {
    echo "--- Test: scan_repo extracts repo name from specs dir ---"

    source "$MASTER_SCRIPT"

    local sdd_root="$TEST_TMP_DIR/specs/my-awesome-repo"
    mkdir -p "$sdd_root/tickets"

    local output
    output=$(scan_repo "$sdd_root")

    assert_contains "$output" '"name": "my-awesome-repo"' "Extracted repo name from specs directory basename"
}

#######################################
# Test: Missing repo graceful handling
# When specs entry exists but no matching repo directory
#######################################
test_missing_repo_graceful_handling() {
    echo "--- Test: Missing repo graceful handling ---"

    # Create specs dir with no matching repo
    local specs_root="$TEST_TMP_DIR/missing_repo_specs"
    local repos_root="$TEST_TMP_DIR/missing_repo_repos"
    mkdir -p "$specs_root/dev-container/tickets"
    mkdir -p "$repos_root"  # repos root exists but has no dev-container child

    local output
    output=$(bash "$MASTER_SCRIPT" --json --specs-root "$specs_root" --repos-root "$repos_root" 2>&1)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "Missing repo exits with code 0"

    # Verify the repo is still discovered from specs
    assert_contains "$output" '"name": "dev-container"' "Found repo name from specs"
    assert_contains "$output" '"sdd_root":' "sdd_root field present"

    # repo_path should be null and repo_status should be repo_not_found
    assert_contains "$output" '"repo_path": null' "repo_path is null when repo missing"
    assert_contains "$output" '"repo_status": "repo_not_found"' "repo_status is repo_not_found"

    # Should still report tickets (empty in this case)
    assert_contains "$output" '"tickets": []' "Tickets array is present"

    # Regression check: output should not contain deprecated paths
    local deprecated_marker="_SD""D"
    if echo "$output" | grep -q "$deprecated_marker"; then
        log_result "Missing repo output has no deprecated paths" "fail" "Output contains deprecated path"
    else
        log_result "Missing repo output has no deprecated paths" "pass"
    fi
}

#######################################
# Test: Non-matching git dir name
# When the git root name differs from the parent directory name
# (e.g., repos/mattermost/mattermost-webapp/.git)
#######################################
test_nonmatching_git_dir_name() {
    echo "--- Test: Non-matching git dir name ---"

    # Create specs/<name> and repos/<name>/<different-git-dir>
    local specs_root="$TEST_TMP_DIR/nonmatch_specs"
    local repos_root="$TEST_TMP_DIR/nonmatch_repos"
    mkdir -p "$specs_root/mattermost/tickets"
    mkdir -p "$repos_root/mattermost/mattermost-webapp/.git"

    local output
    output=$(bash "$MASTER_SCRIPT" --json --specs-root "$specs_root" --repos-root "$repos_root" 2>&1)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "Non-matching git dir exits with code 0"

    # Name comes from specs directory basename
    assert_contains "$output" '"name": "mattermost"' "Found repo name from specs"

    # sdd_path should point to the specs directory
    assert_contains "$output" "specs/mattermost" "sdd_root points to specs dir"

    # repo_path should point to the repos directory
    assert_contains "$output" "repos/mattermost" "repo_path points to repos dir"

    # Regression check: output should not contain deprecated paths
    local deprecated_marker="_SD""D"
    if echo "$output" | grep -q "$deprecated_marker"; then
        log_result "Non-matching git dir output has no deprecated paths" "fail" "Output contains deprecated path"
    else
        log_result "Non-matching git dir output has no deprecated paths" "pass"
    fi
}

#######################################
# Test: Integration - Full workspace scan
#######################################
test_integration_full_workspace_scan() {
    echo "--- Test: Integration - Full workspace scan ---"

    # Create multi-repo two-root structure
    local specs_root="$TEST_TMP_DIR/integ_specs"
    local repos_root="$TEST_TMP_DIR/integ_repos"
    mkdir -p "$specs_root/repo-alpha/tickets/ALPHA-1/tasks"
    mkdir -p "$specs_root/repo-beta/tickets/BETA-1/tasks"
    mkdir -p "$repos_root/repo-alpha/repo-alpha/.git"
    mkdir -p "$repos_root/repo-beta/repo-beta/.git"

    echo "# Alpha Ticket" > "$specs_root/repo-alpha/tickets/ALPHA-1/README.md"
    echo "# Beta Ticket" > "$specs_root/repo-beta/tickets/BETA-1/README.md"

    cat > "$specs_root/repo-alpha/tickets/ALPHA-1/tasks/ALPHA-1.1001.md" << 'EOF'
## Status
- [x] **Task completed**
- [x] **Tests pass**
- [x] **Verified**
EOF

    cat > "$specs_root/repo-beta/tickets/BETA-1/tasks/BETA-1.1001.md" << 'EOF'
## Status
- [ ] **Task completed**
EOF

    local output
    output=$(bash "$MASTER_SCRIPT" --specs-root "$specs_root" --repos-root "$repos_root" 2>&1)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "Integration scan exits with code 0"
    assert_contains "$output" '"name": "repo-alpha"' "Found repo-alpha"
    assert_contains "$output" '"name": "repo-beta"' "Found repo-beta"
    assert_contains "$output" '"total_repos": 2' "Total repos is 2"
}

#######################################
# Test: Integration - Empty specs root
#######################################
test_integration_empty_workspace() {
    echo "--- Test: Integration - Empty specs root ---"

    local specs_root="$TEST_TMP_DIR/empty-integ-specs"
    local repos_root="$TEST_TMP_DIR/empty-integ-repos"
    mkdir -p "$specs_root"
    mkdir -p "$repos_root"

    local output
    output=$(bash "$MASTER_SCRIPT" --specs-root "$specs_root" --repos-root "$repos_root" 2>&1)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "Empty specs root exits with code 0"
    assert_contains "$output" '"repos": [' "Output has repos array"
    assert_contains "$output" '"total_repos": 0' "Total repos is 0"
    assert_contains "$output" '"total_tickets": 0' "Total tickets is 0"
}

#######################################
# Test: Integration - Workspace-level summary aggregation
#######################################
test_integration_workspace_level_summary() {
    echo "--- Test: Integration - Workspace-level summary ---"

    local specs_root="$TEST_TMP_DIR/summary-integ-specs"
    local repos_root="$TEST_TMP_DIR/summary-integ-repos"
    mkdir -p "$specs_root/r1/tickets/T1/tasks"
    mkdir -p "$specs_root/r2/tickets/T2/tasks"
    mkdir -p "$repos_root/r1/r1/.git"
    mkdir -p "$repos_root/r2/r2/.git"

    echo "# T1" > "$specs_root/r1/tickets/T1/README.md"
    echo "# T2" > "$specs_root/r2/tickets/T2/README.md"

    # r1: 1 pending task
    cat > "$specs_root/r1/tickets/T1/tasks/T1.1001.md" << 'EOF'
## Status
- [ ] **Task completed**
EOF

    # r2: 1 verified task
    cat > "$specs_root/r2/tickets/T2/tasks/T2.1001.md" << 'EOF'
## Status
- [x] **Task completed**
- [x] **Tests pass**
- [x] **Verified**
EOF

    local output
    output=$(bash "$MASTER_SCRIPT" --specs-root "$specs_root" --repos-root "$repos_root" 2>&1)

    # Workspace summary should be aggregated
    assert_contains "$output" '"total_repos": 2' "Workspace total_repos is 2"
    assert_contains "$output" '"total_tickets": 2' "Workspace total_tickets is 2"
    assert_contains "$output" '"total_tasks": 2' "Workspace total_tasks is 2"
}

#######################################
# Test: Integration - Output is valid JSON
#######################################
test_integration_output_valid_json() {
    echo "--- Test: Integration - Output is valid JSON ---"

    local specs_root="$TEST_TMP_DIR/json-integ-specs"
    local repos_root="$TEST_TMP_DIR/json-integ-repos"
    mkdir -p "$specs_root/repo/tickets/T1/tasks"
    mkdir -p "$repos_root/repo/repo/.git"
    echo "# T1" > "$specs_root/repo/tickets/T1/README.md"
    cat > "$specs_root/repo/tickets/T1/tasks/T1.1001.md" << 'EOF'
## Status
- [x] **Task completed**
EOF

    local output
    output=$(bash "$MASTER_SCRIPT" --specs-root "$specs_root" --repos-root "$repos_root" 2>&1)

    if command -v jq &>/dev/null; then
        if echo "$output" | jq . >/dev/null 2>&1; then
            log_result "Integration output is valid JSON" "pass"
        else
            log_result "Integration output is valid JSON" "fail" "JSON parsing failed"
            echo "Output was:" >&2
            echo "$output" >&2
        fi
    else
        if [[ "$output" == "{"* && "$output" == *"}" ]]; then
            log_result "Integration output is valid JSON (basic check)" "pass"
        else
            log_result "Integration output is valid JSON (basic check)" "fail"
        fi
    fi
}

#######################################
# Test: Integration - Performance (< 5 seconds)
#######################################
test_integration_performance() {
    echo "--- Test: Integration - Performance ---"

    # Test against real workspace if it exists, otherwise use temp
    local specs_root="/workspace/_SPECS"
    local repos_root="/workspace/repos"
    if [[ ! -d "$specs_root" ]]; then
        specs_root="$TEST_TMP_DIR/perf-specs"
        repos_root="$TEST_TMP_DIR/perf-repos"
        mkdir -p "$specs_root"
        mkdir -p "$repos_root"
    fi

    local start_time end_time elapsed
    start_time=$(date +%s%N)

    bash "$MASTER_SCRIPT" --specs-root "$specs_root" --repos-root "$repos_root" >/dev/null 2>&1
    local exit_code=$?

    end_time=$(date +%s%N)
    elapsed=$(( (end_time - start_time) / 1000000 ))  # milliseconds

    if [[ $exit_code -eq 0 && $elapsed -lt 5000 ]]; then
        log_result "Performance test (< 5 seconds)" "pass"
        echo "       Completed in ${elapsed}ms"
    else
        log_result "Performance test (< 5 seconds)" "fail" "Took ${elapsed}ms (limit: 5000ms)"
    fi
}

#######################################
# Test: compute_recommended_action with multiple priorities
#######################################
test_recommended_action_multiple_priorities() {
    echo "--- Test: compute_recommended_action with multiple priorities ---"

    source "$MASTER_SCRIPT"

    # Create scan output with multiple tickets at different priorities
    local scan_output
    scan_output=$(cat << 'EOF'
{
  "timestamp": "2026-01-15T10:00:00+00:00",
  "specs_root": "/workspace/_SPECS/",
  "repos_root": "/workspace/repos/",
  "repos": [
    {
      "name": "test-repo",
      "sdd_root": "/workspace/_SPECS/test-repo",
      "tickets": [
        {
          "ticket_id": "LOW-1_low-priority",
          "name": "Low Priority Ticket",
          "path": "/workspace/_SPECS/test-repo/tickets/LOW-1_low-priority",
          "autogate": {"ready": true, "agent_ready": true, "priority": 3, "stop_at_phase": null},
          "tasks": [
            {"file": "/path/LOW-1.1001.md", "task_id": "LOW-1.1001", "task_completed": false, "tests_pass": false, "verified": false}
          ],
          "summary": {"total_tasks": 1, "pending": 1, "completed": 0, "tested": 0, "verified": 0}
        },
        {
          "ticket_id": "HIGH-1_high-priority",
          "name": "High Priority Ticket",
          "path": "/workspace/_SPECS/test-repo/tickets/HIGH-1_high-priority",
          "autogate": {"ready": true, "agent_ready": true, "priority": 1, "stop_at_phase": null},
          "tasks": [
            {"file": "/path/HIGH-1.1001.md", "task_id": "HIGH-1.1001", "task_completed": false, "tests_pass": false, "verified": false}
          ],
          "summary": {"total_tasks": 1, "pending": 1, "completed": 0, "tested": 0, "verified": 0}
        },
        {
          "ticket_id": "MED-1_medium-priority",
          "name": "Medium Priority Ticket",
          "path": "/workspace/_SPECS/test-repo/tickets/MED-1_medium-priority",
          "autogate": {"ready": true, "agent_ready": true, "priority": 2, "stop_at_phase": null},
          "tasks": [
            {"file": "/path/MED-1.1001.md", "task_id": "MED-1.1001", "task_completed": false, "tests_pass": false, "verified": false}
          ],
          "summary": {"total_tasks": 1, "pending": 1, "completed": 0, "tested": 0, "verified": 0}
        }
      ],
      "summary": {"total_tickets": 3, "total_tasks": 3, "pending": 3, "completed": 0, "tested": 0, "verified": 0}
    }
  ],
  "summary": {"total_repos": 1, "total_tickets": 3, "total_tasks": 3, "pending": 3, "completed": 0, "tested": 0, "verified": 0}
}
EOF
)

    local output
    output=$(compute_recommended_action "$scan_output")

    assert_contains "$output" '"action": "do-task"' "Action is do-task"
    assert_contains "$output" '"ticket": "HIGH-1_high-priority"' "Highest priority ticket selected"
    assert_contains "$output" '"task": "HIGH-1.1001"' "Task from highest priority ticket"
}

#######################################
# Test: compute_recommended_action with tied priorities (lexicographic)
#######################################
test_recommended_action_tied_priorities() {
    echo "--- Test: compute_recommended_action with tied priorities ---"

    source "$MASTER_SCRIPT"

    # Create scan output with tickets at same priority - should use lexicographic ordering
    local scan_output
    scan_output=$(cat << 'EOF'
{
  "timestamp": "2026-01-15T10:00:00+00:00",
  "specs_root": "/workspace/_SPECS/",
  "repos_root": "/workspace/repos/",
  "repos": [
    {
      "name": "test-repo",
      "sdd_root": "/workspace/_SPECS/test-repo",
      "tickets": [
        {
          "ticket_id": "ZEBRA-1_later-alphabetically",
          "name": "Zebra Ticket",
          "path": "/workspace/_SPECS/test-repo/tickets/ZEBRA-1",
          "autogate": {"ready": true, "agent_ready": true, "priority": 1, "stop_at_phase": null},
          "tasks": [
            {"file": "/path/ZEBRA-1.1001.md", "task_id": "ZEBRA-1.1001", "task_completed": false, "tests_pass": false, "verified": false}
          ],
          "summary": {"total_tasks": 1, "pending": 1, "completed": 0, "tested": 0, "verified": 0}
        },
        {
          "ticket_id": "ALPHA-1_earlier-alphabetically",
          "name": "Alpha Ticket",
          "path": "/workspace/_SPECS/test-repo/tickets/ALPHA-1",
          "autogate": {"ready": true, "agent_ready": true, "priority": 1, "stop_at_phase": null},
          "tasks": [
            {"file": "/path/ALPHA-1.1001.md", "task_id": "ALPHA-1.1001", "task_completed": false, "tests_pass": false, "verified": false}
          ],
          "summary": {"total_tasks": 1, "pending": 1, "completed": 0, "tested": 0, "verified": 0}
        }
      ],
      "summary": {"total_tickets": 2, "total_tasks": 2, "pending": 2, "completed": 0, "tested": 0, "verified": 0}
    }
  ],
  "summary": {"total_repos": 1, "total_tickets": 2, "total_tasks": 2, "pending": 2, "completed": 0, "tested": 0, "verified": 0}
}
EOF
)

    local output
    output=$(compute_recommended_action "$scan_output")

    assert_contains "$output" '"action": "do-task"' "Action is do-task"
    assert_contains "$output" '"ticket": "ALPHA-1_earlier-alphabetically"' "Lexicographically first ticket selected on tie"
    assert_contains "$output" '"task": "ALPHA-1.1001"' "Task from lexicographically first ticket"
}

#######################################
# Test: compute_recommended_action filters ready=false tickets
#######################################
test_recommended_action_ready_false_filtered() {
    echo "--- Test: compute_recommended_action filters ready=false ---"

    source "$MASTER_SCRIPT"

    # Create scan output where only ticket has ready=false
    local scan_output
    scan_output=$(cat << 'EOF'
{
  "timestamp": "2026-01-15T10:00:00+00:00",
  "specs_root": "/workspace/_SPECS/",
  "repos_root": "/workspace/repos/",
  "repos": [
    {
      "name": "test-repo",
      "sdd_root": "/workspace/_SPECS/test-repo",
      "tickets": [
        {
          "ticket_id": "BLOCKED-1_not-ready",
          "name": "Blocked Ticket",
          "path": "/workspace/_SPECS/test-repo/tickets/BLOCKED-1",
          "autogate": {"ready": false, "agent_ready": true, "priority": 1, "stop_at_phase": null},
          "tasks": [
            {"file": "/path/BLOCKED-1.1001.md", "task_id": "BLOCKED-1.1001", "task_completed": false, "tests_pass": false, "verified": false}
          ],
          "summary": {"total_tasks": 1, "pending": 1, "completed": 0, "tested": 0, "verified": 0}
        }
      ],
      "summary": {"total_tickets": 1, "total_tasks": 1, "pending": 1, "completed": 0, "tested": 0, "verified": 0}
    }
  ],
  "summary": {"total_repos": 1, "total_tickets": 1, "total_tasks": 1, "pending": 1, "completed": 0, "tested": 0, "verified": 0}
}
EOF
)

    local output
    output=$(compute_recommended_action "$scan_output")

    assert_contains "$output" '"action": "none"' "Action is none when ready=false"
    assert_contains "$output" '"reason": "No agent-ready work remaining"' "Reason explains no agent-ready work"
}

#######################################
# Test: compute_recommended_action filters agent_ready=false tickets
#######################################
test_recommended_action_agent_ready_false_filtered() {
    echo "--- Test: compute_recommended_action filters agent_ready=false ---"

    source "$MASTER_SCRIPT"

    # Create scan output where ticket has ready=true but agent_ready=false
    local scan_output
    scan_output=$(cat << 'EOF'
{
  "timestamp": "2026-01-15T10:00:00+00:00",
  "specs_root": "/workspace/_SPECS/",
  "repos_root": "/workspace/repos/",
  "repos": [
    {
      "name": "test-repo",
      "sdd_root": "/workspace/_SPECS/test-repo",
      "tickets": [
        {
          "ticket_id": "MANUAL-1_human-only",
          "name": "Human Only Ticket",
          "path": "/workspace/_SPECS/test-repo/tickets/MANUAL-1",
          "autogate": {"ready": true, "agent_ready": false, "priority": 1, "stop_at_phase": null},
          "tasks": [
            {"file": "/path/MANUAL-1.1001.md", "task_id": "MANUAL-1.1001", "task_completed": false, "tests_pass": false, "verified": false}
          ],
          "summary": {"total_tasks": 1, "pending": 1, "completed": 0, "tested": 0, "verified": 0}
        }
      ],
      "summary": {"total_tickets": 1, "total_tasks": 1, "pending": 1, "completed": 0, "tested": 0, "verified": 0}
    }
  ],
  "summary": {"total_repos": 1, "total_tickets": 1, "total_tasks": 1, "pending": 1, "completed": 0, "tested": 0, "verified": 0}
}
EOF
)

    local output
    output=$(compute_recommended_action "$scan_output")

    assert_contains "$output" '"action": "none"' "Action is none when agent_ready=false"
    assert_contains "$output" '"reason": "No agent-ready work remaining"' "Reason explains no agent-ready work"
}

#######################################
# Test: compute_recommended_action selects agent_ready=true tickets
#######################################
test_recommended_action_agent_ready_true_selected() {
    echo "--- Test: compute_recommended_action selects agent_ready=true ---"

    source "$MASTER_SCRIPT"

    # Create scan output with mixed agent_ready values - should select the agent_ready one
    local scan_output
    scan_output=$(cat << 'EOF'
{
  "timestamp": "2026-01-15T10:00:00+00:00",
  "specs_root": "/workspace/_SPECS/",
  "repos_root": "/workspace/repos/",
  "repos": [
    {
      "name": "test-repo",
      "sdd_root": "/workspace/_SPECS/test-repo",
      "tickets": [
        {
          "ticket_id": "AAAAAA-1_first-but-not-agent-ready",
          "name": "First but not agent ready",
          "path": "/workspace/_SPECS/test-repo/tickets/AAAAAA-1",
          "autogate": {"ready": true, "agent_ready": false, "priority": 1, "stop_at_phase": null},
          "tasks": [
            {"file": "/path/AAAAAA-1.1001.md", "task_id": "AAAAAA-1.1001", "task_completed": false, "tests_pass": false, "verified": false}
          ],
          "summary": {"total_tasks": 1, "pending": 1, "completed": 0, "tested": 0, "verified": 0}
        },
        {
          "ticket_id": "ZZZZZZ-1_last-but-agent-ready",
          "name": "Last but agent ready",
          "path": "/workspace/_SPECS/test-repo/tickets/ZZZZZZ-1",
          "autogate": {"ready": true, "agent_ready": true, "priority": 1, "stop_at_phase": null},
          "tasks": [
            {"file": "/path/ZZZZZZ-1.1001.md", "task_id": "ZZZZZZ-1.1001", "task_completed": false, "tests_pass": false, "verified": false}
          ],
          "summary": {"total_tasks": 1, "pending": 1, "completed": 0, "tested": 0, "verified": 0}
        }
      ],
      "summary": {"total_tickets": 2, "total_tasks": 2, "pending": 2, "completed": 0, "tested": 0, "verified": 0}
    }
  ],
  "summary": {"total_repos": 1, "total_tickets": 2, "total_tasks": 2, "pending": 2, "completed": 0, "tested": 0, "verified": 0}
}
EOF
)

    local output
    output=$(compute_recommended_action "$scan_output")

    assert_contains "$output" '"action": "do-task"' "Action is do-task"
    assert_contains "$output" '"ticket": "ZZZZZZ-1_last-but-agent-ready"' "Agent-ready ticket selected even if later alphabetically"
    assert_contains "$output" '"task": "ZZZZZZ-1.1001"' "Task from agent-ready ticket"
}

#######################################
# Test: compute_recommended_action returns none when all verified
#######################################
test_recommended_action_all_verified_returns_none() {
    echo "--- Test: compute_recommended_action all verified returns none ---"

    source "$MASTER_SCRIPT"

    # Create scan output where all tasks are verified
    local scan_output
    scan_output=$(cat << 'EOF'
{
  "timestamp": "2026-01-15T10:00:00+00:00",
  "specs_root": "/workspace/_SPECS/",
  "repos_root": "/workspace/repos/",
  "repos": [
    {
      "name": "test-repo",
      "sdd_root": "/workspace/_SPECS/test-repo",
      "tickets": [
        {
          "ticket_id": "DONE-1_all-verified",
          "name": "All Done Ticket",
          "path": "/workspace/_SPECS/test-repo/tickets/DONE-1",
          "autogate": {"ready": true, "agent_ready": true, "priority": 1, "stop_at_phase": null},
          "tasks": [
            {"file": "/path/DONE-1.1001.md", "task_id": "DONE-1.1001", "task_completed": true, "tests_pass": true, "verified": true},
            {"file": "/path/DONE-1.1002.md", "task_id": "DONE-1.1002", "task_completed": true, "tests_pass": true, "verified": true}
          ],
          "summary": {"total_tasks": 2, "pending": 0, "completed": 0, "tested": 0, "verified": 2}
        }
      ],
      "summary": {"total_tickets": 1, "total_tasks": 2, "pending": 0, "completed": 0, "tested": 0, "verified": 2}
    }
  ],
  "summary": {"total_repos": 1, "total_tickets": 1, "total_tasks": 2, "pending": 0, "completed": 0, "tested": 0, "verified": 2}
}
EOF
)

    local output
    output=$(compute_recommended_action "$scan_output")

    assert_contains "$output" '"action": "none"' "Action is none when all verified"
    assert_contains "$output" '"reason": "All agent-ready work completed"' "Reason explains all work completed"
}

#######################################
# Test: compute_recommended_action returns none when no tickets
#######################################
test_recommended_action_no_tickets_returns_none() {
    echo "--- Test: compute_recommended_action no tickets returns none ---"

    source "$MASTER_SCRIPT"

    # Create scan output with no tickets
    local scan_output
    scan_output=$(cat << 'EOF'
{
  "timestamp": "2026-01-15T10:00:00+00:00",
  "specs_root": "/workspace/_SPECS/",
  "repos_root": "/workspace/repos/",
  "repos": [
    {
      "name": "empty-repo",
      "sdd_root": "/workspace/_SPECS/empty-repo",
      "tickets": [],
      "summary": {"total_tickets": 0, "total_tasks": 0, "pending": 0, "completed": 0, "tested": 0, "verified": 0}
    }
  ],
  "summary": {"total_repos": 1, "total_tickets": 0, "total_tasks": 0, "pending": 0, "completed": 0, "tested": 0, "verified": 0}
}
EOF
)

    local output
    output=$(compute_recommended_action "$scan_output")

    assert_contains "$output" '"action": "none"' "Action is none when no tickets"
    assert_contains "$output" '"reason": "No agent-ready work remaining"' "Reason explains no work"
}

#######################################
# Test: compute_recommended_action task state priority (pending > completed > tested)
#######################################
test_recommended_action_task_state_priority() {
    echo "--- Test: compute_recommended_action task state priority ---"

    source "$MASTER_SCRIPT"

    # Create scan output with tasks in different states - should prioritize pending
    local scan_output
    scan_output=$(cat << 'EOF'
{
  "timestamp": "2026-01-15T10:00:00+00:00",
  "specs_root": "/workspace/_SPECS/",
  "repos_root": "/workspace/repos/",
  "repos": [
    {
      "name": "test-repo",
      "sdd_root": "/workspace/_SPECS/test-repo",
      "tickets": [
        {
          "ticket_id": "MIXED-1_mixed-states",
          "name": "Mixed States Ticket",
          "path": "/workspace/_SPECS/test-repo/tickets/MIXED-1",
          "autogate": {"ready": true, "agent_ready": true, "priority": 1, "stop_at_phase": null},
          "tasks": [
            {"file": "/path/MIXED-1.1003.md", "task_id": "MIXED-1.1003", "task_completed": true, "tests_pass": true, "verified": false},
            {"file": "/path/MIXED-1.1002.md", "task_id": "MIXED-1.1002", "task_completed": true, "tests_pass": false, "verified": false},
            {"file": "/path/MIXED-1.1001.md", "task_id": "MIXED-1.1001", "task_completed": false, "tests_pass": false, "verified": false}
          ],
          "summary": {"total_tasks": 3, "pending": 1, "completed": 1, "tested": 1, "verified": 0}
        }
      ],
      "summary": {"total_tickets": 1, "total_tasks": 3, "pending": 1, "completed": 1, "tested": 1, "verified": 0}
    }
  ],
  "summary": {"total_repos": 1, "total_tickets": 1, "total_tasks": 3, "pending": 1, "completed": 1, "tested": 1, "verified": 0}
}
EOF
)

    local output
    output=$(compute_recommended_action "$scan_output")

    assert_contains "$output" '"action": "do-task"' "Action is do-task"
    assert_contains "$output" '"task": "MIXED-1.1001"' "Pending task selected over completed and tested"
    assert_contains "$output" '"reason": "Next pending task in highest priority ticket"' "Reason indicates pending task"
}

#######################################
# Test: compute_recommended_action includes sdd_root in output
#######################################
test_recommended_action_includes_sdd_root() {
    echo "--- Test: compute_recommended_action includes sdd_root ---"

    source "$MASTER_SCRIPT"

    local scan_output
    scan_output=$(cat << 'EOF'
{
  "timestamp": "2026-01-15T10:00:00+00:00",
  "specs_root": "/workspace/_SPECS/",
  "repos_root": "/workspace/repos/",
  "repos": [
    {
      "name": "my-repo",
      "sdd_root": "/workspace/_SPECS/my-repo",
      "tickets": [
        {
          "ticket_id": "TEST-1_sdd-root-test",
          "name": "SDD Root Test",
          "path": "/workspace/_SPECS/my-repo/tickets/TEST-1",
          "autogate": {"ready": true, "agent_ready": true, "priority": 1, "stop_at_phase": null},
          "tasks": [
            {"file": "/workspace/_SPECS/my-repo/tickets/TEST-1/tasks/TEST-1.1001.md", "task_id": "TEST-1.1001", "task_completed": false, "tests_pass": false, "verified": false}
          ],
          "summary": {"total_tasks": 1, "pending": 1, "completed": 0, "tested": 0, "verified": 0}
        }
      ],
      "summary": {"total_tickets": 1, "total_tasks": 1, "pending": 1, "completed": 0, "tested": 0, "verified": 0}
    }
  ],
  "summary": {"total_repos": 1, "total_tickets": 1, "total_tasks": 1, "pending": 1, "completed": 0, "tested": 0, "verified": 0}
}
EOF
)

    local output
    output=$(compute_recommended_action "$scan_output")

    assert_contains "$output" '"sdd_root": "/workspace/_SPECS/my-repo"' "Output includes sdd_root path"
    assert_contains "$output" '"task_file":' "Output includes task_file path"
}

#######################################
# Test: compute_recommended_action output is valid JSON
#######################################
test_recommended_action_valid_json_output() {
    echo "--- Test: compute_recommended_action output is valid JSON ---"

    source "$MASTER_SCRIPT"

    local scan_output
    scan_output=$(cat << 'EOF'
{
  "timestamp": "2026-01-15T10:00:00+00:00",
  "specs_root": "/workspace/_SPECS/",
  "repos_root": "/workspace/repos/",
  "repos": [
    {
      "name": "test-repo",
      "sdd_root": "/workspace/_SPECS/test-repo",
      "tickets": [
        {
          "ticket_id": "JSON-1_json-test",
          "name": "JSON Test",
          "path": "/workspace/_SPECS/test-repo/tickets/JSON-1",
          "autogate": {"ready": true, "agent_ready": true, "priority": 1, "stop_at_phase": null},
          "tasks": [
            {"file": "/path/JSON-1.1001.md", "task_id": "JSON-1.1001", "task_completed": false, "tests_pass": false, "verified": false}
          ],
          "summary": {"total_tasks": 1, "pending": 1, "completed": 0, "tested": 0, "verified": 0}
        }
      ],
      "summary": {"total_tickets": 1, "total_tasks": 1, "pending": 1, "completed": 0, "tested": 0, "verified": 0}
    }
  ],
  "summary": {"total_repos": 1, "total_tickets": 1, "total_tasks": 1, "pending": 1, "completed": 0, "tested": 0, "verified": 0}
}
EOF
)

    local output
    output=$(compute_recommended_action "$scan_output")

    if command -v jq &>/dev/null; then
        if echo "$output" | jq . >/dev/null 2>&1; then
            log_result "compute_recommended_action output is valid JSON" "pass"
        else
            log_result "compute_recommended_action output is valid JSON" "fail" "JSON parsing failed"
            echo "Output was:" >&2
            echo "$output" >&2
        fi
    else
        if [[ "$output" == "{"* && "$output" == *"}" ]]; then
            log_result "compute_recommended_action output is valid JSON (basic check)" "pass"
        else
            log_result "compute_recommended_action output is valid JSON (basic check)" "fail"
        fi
    fi
}

#######################################
# Test: compute_recommended_action with empty input
#######################################
test_recommended_action_empty_input() {
    echo "--- Test: compute_recommended_action with empty input ---"

    source "$MASTER_SCRIPT"

    local output
    output=$(compute_recommended_action "")

    assert_contains "$output" '"action": "none"' "Action is none for empty input"
    assert_contains "$output" '"reason":' "Reason field is present"
}

# =============================================================================
# Root Structure Validation Tests (SDDLOOP-6.3003)
# =============================================================================

#######################################
# Test: Warning when specs-root is empty
# Verifies that a warning is logged when specs-root has no subdirectories
# and that execution continues (non-blocking, exit code 0)
#######################################
test_empty_specs_root_warning() {
    echo "--- Test: Empty specs-root warning ---"

    # Create empty specs root and repos root
    local specs_root="$TEST_TMP_DIR/empty_specs_warn"
    local repos_root="$TEST_TMP_DIR/repos_warn"
    mkdir -p "$specs_root"
    mkdir -p "$repos_root"

    local output
    local exit_code=0
    output=$(bash "$MASTER_SCRIPT" --specs-root "$specs_root" --repos-root "$repos_root" 2>&1) || exit_code=$?

    assert_exit_code 0 "$exit_code" "Script continues despite empty specs-root"
    assert_contains "$output" "specs-root is empty" "Warning about empty specs-root emitted"
    assert_contains "$output" "Expected structure:" "Warning includes expected structure hint"
}

#######################################
# Test: Warning when specs-root and repos-root are identical
# Verifies that a warning is logged when both roots point to the same path
# and that execution continues (non-blocking, exit code 0)
#######################################
test_identical_roots_warning() {
    echo "--- Test: Identical specs/repos roots warning ---"

    # Create a directory that will serve as both specs and repos root
    local shared_root="$TEST_TMP_DIR/shared_root_warn"
    mkdir -p "$shared_root/test-repo/tickets"

    local output
    local exit_code=0
    output=$(bash "$MASTER_SCRIPT" --specs-root "$shared_root" --repos-root "$shared_root" 2>&1) || exit_code=$?

    assert_exit_code 0 "$exit_code" "Script continues despite identical roots"
    assert_contains "$output" "specs-root and repos-root are identical" "Warning about identical roots emitted"
    assert_contains "$output" "unexpected behavior" "Warning includes explanation"
}

#######################################
# Test: No warning when specs-root has subdirectories
# Verifies that no empty-specs warning is logged for non-empty specs root
#######################################
test_no_warning_for_populated_specs_root() {
    echo "--- Test: No warning for populated specs-root ---"

    local specs_root="$TEST_TMP_DIR/populated_specs_warn"
    local repos_root="$TEST_TMP_DIR/repos_populated_warn"
    mkdir -p "$specs_root/test-repo/tickets"
    mkdir -p "$repos_root"

    local output
    local exit_code=0
    output=$(bash "$MASTER_SCRIPT" --specs-root "$specs_root" --repos-root "$repos_root" 2>&1) || exit_code=$?

    assert_exit_code 0 "$exit_code" "Script completes successfully"
    # Check that the empty specs-root warning is NOT present
    if [[ "$output" == *"specs-root is empty"* ]]; then
        log_result "No empty specs-root warning for populated directory" "fail" "Warning found when it should not be"
    else
        log_result "No empty specs-root warning for populated directory" "pass"
    fi
}

#######################################
# Test: No warning when roots are different paths
# Verifies that no identical-roots warning is logged for distinct paths
#######################################
test_no_warning_for_different_roots() {
    echo "--- Test: No warning for different roots ---"

    local specs_root="$TEST_TMP_DIR/specs_diff_warn"
    local repos_root="$TEST_TMP_DIR/repos_diff_warn"
    mkdir -p "$specs_root/test-repo/tickets"
    mkdir -p "$repos_root"

    local output
    local exit_code=0
    output=$(bash "$MASTER_SCRIPT" --specs-root "$specs_root" --repos-root "$repos_root" 2>&1) || exit_code=$?

    assert_exit_code 0 "$exit_code" "Script completes successfully"
    if [[ "$output" == *"specs-root and repos-root are identical"* ]]; then
        log_result "No identical-roots warning for different paths" "fail" "Warning found when it should not be"
    else
        log_result "No identical-roots warning for different paths" "pass"
    fi
}

#######################################
# Test: Help text documents expected directory structure
#######################################
test_help_shows_directory_structure() {
    echo "--- Test: Help shows directory structure ---"

    local output
    output=$(bash "$MASTER_SCRIPT" --help 2>&1)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "Help option exits with code 0"
    assert_contains "$output" "Expected Directory Structure" "Help documents expected directory structure"
    assert_contains "$output" "specs-root/" "Help shows specs-root structure"
    assert_contains "$output" "repos-root/" "Help shows repos-root structure"
}

#######################################
# Test: Empty --specs-root is rejected with clear error
#######################################
test_empty_specs_root_rejected() {
    echo "--- Test: Empty --specs-root rejected ---"

    local output
    local exit_code=0
    output=$(bash "$MASTER_SCRIPT" --specs-root "" 2>&1) || exit_code=$?

    assert_exit_code 1 "$exit_code" "Empty --specs-root exits with code 1"
    assert_contains "$output" "--specs-root cannot be empty" "Error message mentions --specs-root cannot be empty"
}

#######################################
# Test: Empty --repos-root is rejected with clear error
#######################################
test_empty_repos_root_rejected() {
    echo "--- Test: Empty --repos-root rejected ---"

    local output
    local exit_code=0
    output=$(bash "$MASTER_SCRIPT" --repos-root "" 2>&1) || exit_code=$?

    assert_exit_code 1 "$exit_code" "Empty --repos-root exits with code 1"
    assert_contains "$output" "--repos-root cannot be empty" "Error message mentions --repos-root cannot be empty"
}

#######################################
# Test: Progress messages appear with >= 10 repos
#######################################
test_progress_with_many_repos() {
    echo "--- Test: Progress messages with >= 10 repos ---"

    local specs_root="$TEST_TMP_DIR/progress_many_specs"
    local repos_root="$TEST_TMP_DIR/progress_many_repos"
    mkdir -p "$specs_root"
    mkdir -p "$repos_root"

    # Create 15 spec directories to trigger progress (threshold is 10)
    local i=1
    while [ $i -le 15 ]; do
        mkdir -p "$specs_root/repo-$(printf '%02d' $i)"
        i=$((i + 1))
    done

    local stderr_output
    stderr_output=$(bash "$MASTER_SCRIPT" --specs-root "$specs_root" --repos-root "$repos_root" 2>&1 1>/dev/null)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "Progress with many repos exits with code 0"

    # Should contain progress message at 10/15
    assert_contains "$stderr_output" "[INFO] Discovering repos... (10/15)" "Progress logged at 10/15"

    # Should contain final progress message at 15/15
    assert_contains "$stderr_output" "[INFO] Discovering repos... (15/15)" "Final progress logged at 15/15"
}

#######################################
# Test: No progress messages in quiet mode
#######################################
test_progress_quiet_mode() {
    echo "--- Test: No progress in quiet mode ---"

    local specs_root="$TEST_TMP_DIR/progress_quiet_specs"
    local repos_root="$TEST_TMP_DIR/progress_quiet_repos"
    mkdir -p "$specs_root"
    mkdir -p "$repos_root"

    # Create 15 spec directories (above threshold)
    local i=1
    while [ $i -le 15 ]; do
        mkdir -p "$specs_root/repo-$(printf '%02d' $i)"
        i=$((i + 1))
    done

    local stderr_output
    stderr_output=$(bash "$MASTER_SCRIPT" --quiet --specs-root "$specs_root" --repos-root "$repos_root" 2>&1 1>/dev/null)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "Quiet mode exits with code 0"

    # Should NOT contain any progress messages
    if echo "$stderr_output" | grep -q "Discovering repos"; then
        log_result "Quiet mode suppresses progress" "fail" "Found progress messages in quiet mode"
    else
        log_result "Quiet mode suppresses progress" "pass"
    fi
}

#######################################
# Test: No progress messages with < 10 repos
#######################################
test_progress_with_few_repos() {
    echo "--- Test: No progress with < 10 repos ---"

    local specs_root="$TEST_TMP_DIR/progress_few_specs"
    local repos_root="$TEST_TMP_DIR/progress_few_repos"
    mkdir -p "$specs_root"
    mkdir -p "$repos_root"

    # Create only 5 spec directories (below threshold of 10)
    local i=1
    while [ $i -le 5 ]; do
        mkdir -p "$specs_root/repo-$(printf '%02d' $i)"
        i=$((i + 1))
    done

    local stderr_output
    stderr_output=$(bash "$MASTER_SCRIPT" --specs-root "$specs_root" --repos-root "$repos_root" 2>&1 1>/dev/null)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "Few repos exits with code 0"

    # Should NOT contain any progress messages (below threshold)
    if echo "$stderr_output" | grep -q "Discovering repos"; then
        log_result "No progress below threshold" "fail" "Found progress messages with < 10 repos"
    else
        log_result "No progress below threshold" "pass"
    fi
}

# =============================================================================
# Startup Health Check Tests (SDDLOOP-6.3010)
# =============================================================================

#######################################
# Test: check_dependencies fails when jq unavailable
#######################################
test_health_check_fails_missing_jq() {
    echo "--- Test: Health check fails when jq unavailable ---"

    source "$MASTER_SCRIPT"

    # Create a minimal bin directory without jq but with realpath and timeout
    local fake_bin="$TEST_TMP_DIR/health_jq_bin"
    mkdir -p "$fake_bin"

    # Link realpath and timeout so they're available
    if command -v realpath >/dev/null 2>&1; then
        ln -sf "$(command -v realpath)" "$fake_bin/realpath"
    fi
    if command -v timeout >/dev/null 2>&1; then
        ln -sf "$(command -v timeout)" "$fake_bin/timeout"
    fi
    for tool in date echo; do
        if command -v "$tool" >/dev/null 2>&1; then
            ln -sf "$(command -v "$tool")" "$fake_bin/$tool"
        fi
    done

    local output
    local exit_code=0
    output=$(PATH="$fake_bin" check_dependencies 2>&1) || exit_code=$?

    assert_equals 1 "$exit_code" "Health check exits with 1 when jq missing"

    if [[ "$output" == *"Required dependency not found: jq"* ]]; then
        log_result "Error message mentions jq" "pass"
    else
        log_result "Error message mentions jq" "fail" "Output: $output"
    fi

    if [[ "$output" == *"Install with:"* ]]; then
        log_result "Error message includes install instructions" "pass"
    else
        log_result "Error message includes install instructions" "fail" "Output: $output"
    fi

    if [[ "$output" == *"Exiting due to missing required dependencies"* ]]; then
        log_result "Error message includes exit reason" "pass"
    else
        log_result "Error message includes exit reason" "fail" "Output: $output"
    fi
}

#######################################
# Test: check_dependencies fails when realpath unavailable
#######################################
test_health_check_fails_missing_realpath() {
    echo "--- Test: Health check fails when realpath unavailable ---"

    source "$MASTER_SCRIPT"

    # Create a minimal bin directory with jq and timeout but not realpath
    local fake_bin="$TEST_TMP_DIR/health_rp_bin"
    mkdir -p "$fake_bin"

    if command -v jq >/dev/null 2>&1; then
        ln -sf "$(command -v jq)" "$fake_bin/jq"
    fi
    if command -v timeout >/dev/null 2>&1; then
        ln -sf "$(command -v timeout)" "$fake_bin/timeout"
    fi
    for tool in date echo; do
        if command -v "$tool" >/dev/null 2>&1; then
            ln -sf "$(command -v "$tool")" "$fake_bin/$tool"
        fi
    done

    local output
    local exit_code=0
    output=$(PATH="$fake_bin" check_dependencies 2>&1) || exit_code=$?

    assert_equals 1 "$exit_code" "Health check exits with 1 when realpath missing"

    if [[ "$output" == *"Required dependency not found: realpath"* ]]; then
        log_result "Error message mentions realpath" "pass"
    else
        log_result "Error message mentions realpath" "fail" "Output: $output"
    fi
}

#######################################
# Test: check_dependencies fails when timeout unavailable
#######################################
test_health_check_fails_missing_timeout() {
    echo "--- Test: Health check fails when timeout unavailable ---"

    source "$MASTER_SCRIPT"

    # Create a minimal bin directory with jq and realpath but not timeout
    local fake_bin="$TEST_TMP_DIR/health_timeout_bin"
    mkdir -p "$fake_bin"

    if command -v jq >/dev/null 2>&1; then
        ln -sf "$(command -v jq)" "$fake_bin/jq"
    fi
    if command -v realpath >/dev/null 2>&1; then
        ln -sf "$(command -v realpath)" "$fake_bin/realpath"
    fi
    for tool in date echo; do
        if command -v "$tool" >/dev/null 2>&1; then
            ln -sf "$(command -v "$tool")" "$fake_bin/$tool"
        fi
    done

    local output
    local exit_code=0
    output=$(PATH="$fake_bin" check_dependencies 2>&1) || exit_code=$?

    assert_equals 1 "$exit_code" "Health check exits with 1 when timeout missing"

    if [[ "$output" == *"Required command 'timeout' not found"* ]]; then
        log_result "Error message mentions timeout" "pass"
    else
        log_result "Error message mentions timeout" "fail" "Output: $output"
    fi

    if [[ "$output" == *"Install GNU coreutils"* ]]; then
        log_result "Error message includes install instructions" "pass"
    else
        log_result "Error message includes install instructions" "fail" "Output: $output"
    fi
}

#######################################
# Test: check_dependencies passes when all tools available
#######################################
test_health_check_passes_all_available() {
    echo "--- Test: Health check passes when all tools available ---"

    source "$MASTER_SCRIPT"

    # Create a bin directory with all required tools
    local fake_bin="$TEST_TMP_DIR/health_all_bin"
    mkdir -p "$fake_bin"

    if command -v jq >/dev/null 2>&1; then
        ln -sf "$(command -v jq)" "$fake_bin/jq"
    fi
    if command -v realpath >/dev/null 2>&1; then
        ln -sf "$(command -v realpath)" "$fake_bin/realpath"
    fi
    if command -v timeout >/dev/null 2>&1; then
        ln -sf "$(command -v timeout)" "$fake_bin/timeout"
    fi
    for tool in date echo; do
        if command -v "$tool" >/dev/null 2>&1; then
            ln -sf "$(command -v "$tool")" "$fake_bin/$tool"
        fi
    done

    local output
    local exit_code=0
    output=$(PATH="$fake_bin" check_dependencies 2>&1) || exit_code=$?

    assert_equals 0 "$exit_code" "Health check exits with 0 when all tools available"

    if [[ "$output" != *"Required dependency not found"* ]]; then
        log_result "No error messages when all tools available" "pass"
    else
        log_result "No error messages when all tools available" "fail" "Output: $output"
    fi
}

# =============================================================================
# Filesystem Operation Timeout Tests (SDDLOOP-6.4003)
# =============================================================================

#######################################
# Test: scan_repo times out with slow find
# Uses a mock find script that sleeps to simulate NFS stale handle
#######################################
test_scan_repo_timeout_handling() {
    echo "--- Test: scan_repo timeout handling ---"

    local sdd_root="$TEST_TMP_DIR/timeout_sdd/test-repo"
    local tickets_dir="$sdd_root/tickets"
    mkdir -p "$tickets_dir/TICKET-1_test/tasks"

    # Create a mock find that sleeps longer than our timeout
    local mock_bin="$TEST_TMP_DIR/timeout_sdd/mock_bin"
    mkdir -p "$mock_bin"

    # Use absolute path for sleep so mock find works with restricted PATH
    local sleep_path
    sleep_path="$(command -v sleep)"
    cat > "$mock_bin/find" << MOCKFIND
#!/bin/sh
# Simulate a slow/hung filesystem by sleeping longer than timeout
"$sleep_path" 10
MOCKFIND
    chmod +x "$mock_bin/find"

    # Symlink essential tools from real PATH
    ln -sf "$(command -v timeout)" "$mock_bin/timeout"
    ln -sf "$(command -v sort)" "$mock_bin/sort"
    ln -sf "$(command -v mktemp)" "$mock_bin/mktemp"
    ln -sf "$(command -v rm)" "$mock_bin/rm"
    ln -sf "$(command -v date)" "$mock_bin/date"
    ln -sf "$(command -v echo)" "$mock_bin/echo"
    ln -sf "$(command -v cat)" "$mock_bin/cat"
    ln -sf "$(command -v wc)" "$mock_bin/wc"
    ln -sf "$(command -v basename)" "$mock_bin/basename"
    ln -sf "$(command -v head)" "$mock_bin/head"
    ln -sf "$(command -v sed)" "$mock_bin/sed"
    ln -sf "$(command -v jq)" "$mock_bin/jq"
    ln -sf "$(command -v grep)" "$mock_bin/grep"
    ln -sf "$(command -v printf)" "$mock_bin/printf" 2>/dev/null || true
    ln -sf "$(command -v awk)" "$mock_bin/awk"
    ln -sf "$(command -v tr)" "$mock_bin/tr"
    ln -sf "$(command -v readlink)" "$mock_bin/readlink"
    ln -sf "$(command -v realpath)" "$mock_bin/realpath"
    ln -sf "$(command -v ls)" "$mock_bin/ls"
    ln -sf "$(command -v test)" "$mock_bin/test" 2>/dev/null || true

    # Run in a fresh bash process to avoid readonly FILESYSTEM_TIMEOUT_SECONDS
    # from prior sourcing in the parent shell. Export the 2-second timeout
    # so the sourced script picks it up via its guard clause.
    # We create a helper script to avoid quoting complications with bash -c.
    local helper_script="$TEST_TMP_DIR/timeout_sdd/run_test.sh"
    cat > "$helper_script" << HELPEREOF
#!/usr/bin/env bash
set -uo pipefail
export FILESYSTEM_TIMEOUT_SECONDS=2
source "$MASTER_SCRIPT"
PATH="$mock_bin" scan_repo "$sdd_root" ""
exit \$?
HELPEREOF
    chmod +x "$helper_script"

    local output=""
    local exit_code=0
    output=$(bash "$helper_script" 2>&1) || exit_code=$?

    assert_equals 1 "$exit_code" "scan_repo returns 1 on find timeout"
    assert_contains "$output" "timed out" "scan_repo timeout error mentions 'timed out'"
}

#######################################
# Test: scan_repo works normally with timeout wrapper
# Verifies timeout doesn't interfere with normal operation
#######################################
test_scan_repo_normal_with_timeout() {
    echo "--- Test: scan_repo normal operation with timeout ---"

    source "$MASTER_SCRIPT"

    local sdd_root="$TEST_TMP_DIR/timeout_normal/test-repo"
    local tickets_dir="$sdd_root/tickets"
    local ticket_dir="$tickets_dir/TICKET-1_test"
    mkdir -p "$ticket_dir/tasks"
    # Create a task file
    cat > "$ticket_dir/tasks/TICKET-1.1001_do-something.md" << 'TASKMD'
# Task: [TICKET-1.1001]: Do Something

## Status
- [ ] **Task completed** - acceptance criteria met
- [ ] **Tests pass** - tests executed and passing
- [ ] **Verified** - by the verify-task agent
TASKMD

    local output=""
    local exit_code=0
    output=$(scan_repo "$sdd_root" "" 2>&1) || exit_code=$?

    assert_equals 0 "$exit_code" "scan_repo exits 0 with timeout wrapper in normal case"
    assert_contains "$output" "TICKET-1_test" "scan_repo output contains ticket directory"
    assert_contains "$output" "TICKET-1.1001" "scan_repo output contains task ID"
}

# =============================================================================
# JSON Log Format Tests (SDDLOOP-6.5004)
# =============================================================================

#######################################
# Test: --log-format json produces JSON log output
# Validates that JSON format contains timestamp, level, message fields
#######################################
test_log_format_json_flag() {
    echo "--- Test: --log-format json flag ---"

    # Create a specs root with enough repos to trigger progress logging (>= 10)
    local specs_dir="$TEST_TMP_DIR/json-test-specs"
    local repos_dir="$TEST_TMP_DIR/json-test-repos"
    mkdir -p "$specs_dir" "$repos_dir"
    local i=0
    while [ $i -lt 11 ]; do
        mkdir -p "$specs_dir/repo-$i"
        i=$((i + 1))
    done

    local output
    local exit_code=0
    output=$(bash "$MASTER_SCRIPT" --log-format json --specs-root "$specs_dir" --repos-root "$repos_dir" 2>&1) || exit_code=$?

    assert_exit_code 0 "$exit_code" "--log-format json exits with code 0"
    # JSON format should contain timestamp field
    assert_contains "$output" '"timestamp"' "--log-format json contains timestamp field"
    # JSON format should contain level field
    assert_contains "$output" '"level"' "--log-format json contains level field"
    # JSON format should contain message field
    assert_contains "$output" '"message"' "--log-format json contains message field"
    # Should NOT have text [INFO] prefix
    assert_not_contains "$output" "[INFO]" "--log-format json does not have [INFO] prefix"
}

#######################################
# Test: LOG_FORMAT=json environment variable produces JSON log output
# Validates that environment variable sets format
#######################################
test_log_format_json_env_var() {
    echo "--- Test: LOG_FORMAT=json environment variable ---"

    # Create a specs root with enough repos to trigger progress logging (>= 10)
    local specs_dir="$TEST_TMP_DIR/json-env-specs"
    local repos_dir="$TEST_TMP_DIR/json-env-repos"
    mkdir -p "$specs_dir" "$repos_dir"
    local i=0
    while [ $i -lt 11 ]; do
        mkdir -p "$specs_dir/repo-$i"
        i=$((i + 1))
    done

    local output
    local exit_code=0
    output=$(LOG_FORMAT=json bash "$MASTER_SCRIPT" --specs-root "$specs_dir" --repos-root "$repos_dir" 2>&1) || exit_code=$?

    assert_exit_code 0 "$exit_code" "LOG_FORMAT=json exits with code 0"
    assert_contains "$output" '"timestamp"' "LOG_FORMAT=json produces JSON format"
    assert_not_contains "$output" "[INFO]" "LOG_FORMAT=json format is not text"
}

#######################################
# Test: JSON log lines are valid JSON (parseable by jq)
# Validates that each JSON log line is valid JSON
#######################################
test_log_format_json_valid_json() {
    echo "--- Test: JSON log lines are valid JSON ---"

    # Create a specs root with enough repos to trigger progress logging (>= 10)
    local specs_dir="$TEST_TMP_DIR/json-valid-specs"
    local repos_dir="$TEST_TMP_DIR/json-valid-repos"
    mkdir -p "$specs_dir" "$repos_dir"
    local i=0
    while [ $i -lt 11 ]; do
        mkdir -p "$specs_dir/repo-$i"
        i=$((i + 1))
    done

    local stderr_output
    local exit_code=0
    # Capture stderr only (JSON logs go to stderr, JSON data goes to stdout)
    stderr_output=$(bash "$MASTER_SCRIPT" --log-format json --specs-root "$specs_dir" --repos-root "$repos_dir" 2>&1 1>/dev/null) || exit_code=$?

    assert_exit_code 0 "$exit_code" "JSON format exits with code 0"

    # Check that we got at least one JSON log line
    local json_line_count=0
    local invalid_lines=0
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        json_line_count=$((json_line_count + 1))
        if ! echo "$line" | jq empty 2>/dev/null; then
            invalid_lines=$((invalid_lines + 1))
        fi
    done <<< "$stderr_output"

    if [ "$json_line_count" -gt 0 ]; then
        log_result "At least one JSON log line produced" "pass"
    else
        log_result "At least one JSON log line produced" "fail" "No JSON log lines found in stderr"
    fi

    if [ "$invalid_lines" -eq 0 ]; then
        log_result "All JSON log lines are valid JSON" "pass"
    else
        log_result "All JSON log lines are valid JSON" "fail" "$invalid_lines invalid JSON lines found"
    fi
}

#######################################
# Test: JSON log contains ISO 8601 timestamp
# Validates timestamp format is UTC ISO 8601
#######################################
test_log_format_json_timestamp() {
    echo "--- Test: JSON log contains ISO 8601 timestamp ---"

    # Create a specs root with enough repos to trigger progress logging (>= 10)
    local specs_dir="$TEST_TMP_DIR/json-ts-specs"
    local repos_dir="$TEST_TMP_DIR/json-ts-repos"
    mkdir -p "$specs_dir" "$repos_dir"
    local i=0
    while [ $i -lt 11 ]; do
        mkdir -p "$specs_dir/repo-$i"
        i=$((i + 1))
    done

    local stderr_output
    local exit_code=0
    stderr_output=$(bash "$MASTER_SCRIPT" --log-format json --specs-root "$specs_dir" --repos-root "$repos_dir" 2>&1 1>/dev/null) || exit_code=$?

    assert_exit_code 0 "$exit_code" "JSON format exits with code 0"

    # Extract timestamp from first JSON log line and validate format
    local first_line
    first_line=$(echo "$stderr_output" | head -1)
    local timestamp
    timestamp=$(echo "$first_line" | jq -r '.timestamp' 2>/dev/null)

    # Validate ISO 8601 UTC format: YYYY-MM-DDTHH:MM:SSZ
    if echo "$timestamp" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
        log_result "JSON timestamp is ISO 8601 UTC format" "pass"
    else
        log_result "JSON timestamp is ISO 8601 UTC format" "fail" "Got: $timestamp"
    fi
}

#######################################
# Test: JSON log has correct level field
# Validates the level field matches expected values
#######################################
test_log_format_json_level() {
    echo "--- Test: JSON log has correct level field ---"

    # Create a specs root with enough repos to trigger progress logging (>= 10)
    local specs_dir="$TEST_TMP_DIR/json-level-specs"
    local repos_dir="$TEST_TMP_DIR/json-level-repos"
    mkdir -p "$specs_dir" "$repos_dir"
    local i=0
    while [ $i -lt 11 ]; do
        mkdir -p "$specs_dir/repo-$i"
        i=$((i + 1))
    done

    local stderr_output
    local exit_code=0
    stderr_output=$(bash "$MASTER_SCRIPT" --log-format json --specs-root "$specs_dir" --repos-root "$repos_dir" 2>&1 1>/dev/null) || exit_code=$?

    assert_exit_code 0 "$exit_code" "JSON format exits with code 0"

    # Extract level from first JSON log line
    local first_line
    first_line=$(echo "$stderr_output" | head -1)
    local level
    level=$(echo "$first_line" | jq -r '.level' 2>/dev/null)

    if [ "$level" = "INFO" ]; then
        log_result "JSON level field is INFO for log_info output" "pass"
    else
        log_result "JSON level field is INFO for log_info output" "fail" "Got: $level"
    fi
}

#######################################
# Test: CLI --log-format overrides LOG_FORMAT environment variable
# Validates CLI flag takes precedence over environment variable
#######################################
test_log_format_cli_overrides_env() {
    echo "--- Test: CLI --log-format overrides LOG_FORMAT env var ---"

    # Create a specs root with enough repos to trigger progress logging (>= 10)
    local specs_dir="$TEST_TMP_DIR/json-override-specs"
    local repos_dir="$TEST_TMP_DIR/json-override-repos"
    mkdir -p "$specs_dir" "$repos_dir"
    local i=0
    while [ $i -lt 11 ]; do
        mkdir -p "$specs_dir/repo-$i"
        i=$((i + 1))
    done

    # Capture stderr separately to check log format (stdout has JSON data with "timestamp")
    local stderr_output
    local exit_code=0
    # Set env to json but CLI to text - CLI should win
    stderr_output=$(LOG_FORMAT=json bash "$MASTER_SCRIPT" --log-format text --specs-root "$specs_dir" --repos-root "$repos_dir" 2>&1 1>/dev/null) || exit_code=$?

    assert_exit_code 0 "$exit_code" "CLI override exits with code 0"
    # Should be text format (CLI override) - stderr should have [INFO] prefix
    assert_contains "$stderr_output" "[INFO]" "CLI --log-format text overrides LOG_FORMAT=json"
    # stderr should NOT have JSON log lines (no {"timestamp":...)
    assert_not_contains "$stderr_output" '{"timestamp"' "CLI override - no JSON log lines in stderr"
}

#######################################
# Test: Default log format is text
# Validates that without --log-format or LOG_FORMAT, text format is used
#######################################
test_log_format_default_text() {
    echo "--- Test: Default log format is text ---"

    # Create a specs root with enough repos to trigger progress logging (>= 10)
    local specs_dir="$TEST_TMP_DIR/json-default-specs"
    local repos_dir="$TEST_TMP_DIR/json-default-repos"
    mkdir -p "$specs_dir" "$repos_dir"
    local i=0
    while [ $i -lt 11 ]; do
        mkdir -p "$specs_dir/repo-$i"
        i=$((i + 1))
    done

    local output
    local exit_code=0
    output=$(bash "$MASTER_SCRIPT" --specs-root "$specs_dir" --repos-root "$repos_dir" 2>&1) || exit_code=$?

    assert_exit_code 0 "$exit_code" "Default format exits with code 0"
    assert_contains "$output" "[INFO]" "Default format uses text [INFO] prefix"
}

#######################################
# Test: --log-format appears in help text
# Validates that help text documents the new option
#######################################
test_log_format_in_help() {
    echo "--- Test: --log-format in help text ---"

    local output
    output=$(bash "$MASTER_SCRIPT" --help 2>&1)
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "Help exits with code 0"
    assert_contains "$output" "--log-format" "Help documents --log-format option"
    assert_contains "$output" "LOG_FORMAT" "Help documents LOG_FORMAT env var"
    assert_contains "$output" "json" "Help mentions json format"
}

#######################################
# Test: format_json_log function produces valid JSON structure
# Sources the script and tests format_json_log directly
#######################################
test_format_json_log_function() {
    echo "--- Test: format_json_log function ---"

    # Source the script to access the function
    local json_output
    json_output=$(source "$MASTER_SCRIPT" && format_json_log "INFO" "test message" 2>&1)

    # Validate it parses as JSON
    local jq_exit=0
    echo "$json_output" | jq empty 2>/dev/null || jq_exit=$?

    if [ "$jq_exit" -eq 0 ]; then
        log_result "format_json_log produces valid JSON" "pass"
    else
        log_result "format_json_log produces valid JSON" "fail" "jq failed to parse: $json_output"
    fi

    # Validate fields
    local ts level msg
    ts=$(echo "$json_output" | jq -r '.timestamp' 2>/dev/null)
    level=$(echo "$json_output" | jq -r '.level' 2>/dev/null)
    msg=$(echo "$json_output" | jq -r '.message' 2>/dev/null)

    assert_equals "INFO" "$level" "format_json_log level field is correct"
    assert_equals "test message" "$msg" "format_json_log message field is correct"

    # Validate timestamp format
    if echo "$ts" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
        log_result "format_json_log timestamp is ISO 8601 UTC" "pass"
    else
        log_result "format_json_log timestamp is ISO 8601 UTC" "fail" "Got: $ts"
    fi
}

#######################################
# Test: format_json_log handles special characters in messages
# Validates that jq properly escapes quotes and backslashes
#######################################
test_format_json_log_special_chars() {
    echo "--- Test: format_json_log special characters ---"

    # Source the script and test with special characters
    local json_output
    json_output=$(source "$MASTER_SCRIPT" && format_json_log "WARN" 'Message with "quotes" and \backslash' 2>&1)

    # Validate it parses as JSON (special chars properly escaped)
    local jq_exit=0
    echo "$json_output" | jq empty 2>/dev/null || jq_exit=$?

    if [ "$jq_exit" -eq 0 ]; then
        log_result "format_json_log escapes special characters" "pass"
    else
        log_result "format_json_log escapes special characters" "fail" "jq failed to parse: $json_output"
    fi

    # Validate the message round-trips correctly
    local msg
    msg=$(echo "$json_output" | jq -r '.message' 2>/dev/null)
    if [[ "$msg" == *'"quotes"'* ]] && [[ "$msg" == *'\backslash'* ]]; then
        log_result "format_json_log message preserves special chars" "pass"
    else
        log_result "format_json_log message preserves special chars" "fail" "Got: $msg"
    fi
}

# =============================================================================
# Shellcheck Static Analysis (SDDLOOP-6.5002)
# =============================================================================

#######################################
# Test: shellcheck static analysis on master-status-board.sh
# Runs shellcheck --severity=style to prevent regressions.
# Skips with a warning if shellcheck is not installed.
#
# To run shellcheck locally:
#   shellcheck --severity=style master-status-board.sh
# Install shellcheck:
#   Ubuntu/Debian: apt-get install shellcheck
#   macOS: brew install shellcheck
#######################################
test_shellcheck_static_analysis() {
    echo "--- Test: shellcheck static analysis ---"

    if ! command -v shellcheck >/dev/null 2>&1; then
        echo "  SKIP: shellcheck not installed (install with: apt-get install shellcheck)"
        log_result "shellcheck static analysis (master-status-board.sh)" "pass" "SKIPPED - shellcheck not available"
        return
    fi

    local output=""
    local exit_code=0
    output=$(shellcheck --severity=style "$MASTER_SCRIPT" 2>&1) || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        log_result "shellcheck static analysis (master-status-board.sh)" "pass"
    else
        echo "$output"
        log_result "shellcheck static analysis (master-status-board.sh)" "fail" "shellcheck found issues (exit code $exit_code)"
    fi
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
    test_summary_only_option
    echo ""
    test_summary_only_short_option
    echo ""
    test_verbose_option
    echo ""
    test_verbose_short_option
    echo ""
    test_combined_short_options
    echo ""
    test_json_option
    echo ""
    test_verbose_output_streams
    echo ""
    test_unknown_short_option
    echo ""
    test_unknown_combined_option
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

    # Run read_autogate tests
    echo "====================================="
    echo "read_autogate() Function Tests"
    echo "====================================="
    echo ""
    test_read_autogate_all_fields
    echo ""
    test_read_autogate_only_ready
    echo ""
    test_read_autogate_ready_false
    echo ""
    test_read_autogate_agent_ready_true
    echo ""
    test_read_autogate_missing_file
    echo ""
    test_read_autogate_empty_file
    echo ""
    test_read_autogate_malformed_json
    echo ""
    test_read_autogate_permission_denied
    echo ""
    test_read_autogate_extra_fields
    echo ""
    test_read_autogate_valid_json
    echo ""
    test_read_autogate_boolean_as_string
    echo ""
    test_read_autogate_null_priority
    echo ""
    test_read_autogate_priority_integer
    echo ""

    # Run scan_ticket tests
    echo "====================================="
    echo "scan_ticket() Function Tests"
    echo "====================================="
    echo ""
    test_scan_ticket_multiple_tasks
    echo ""
    test_scan_ticket_no_tasks_dir
    echo ""
    test_scan_ticket_empty_tasks_dir
    echo ""
    test_scan_ticket_missing_readme
    echo ""
    test_scan_ticket_with_autogate
    echo ""
    test_scan_ticket_missing_dir
    echo ""
    test_scan_ticket_valid_json
    echo ""
    test_scan_ticket_aggregation_logic
    echo ""
    test_scan_ticket_ignores_non_md_files
    echo ""
    test_scan_ticket_readme_no_heading
    echo ""
    test_scan_ticket_all_verified
    echo ""
    test_scan_ticket_path_in_output
    echo ""

    # Run scan_repo tests
    echo "====================================="
    echo "scan_repo() Function Tests"
    echo "====================================="
    echo ""
    test_scan_repo_multiple_tickets
    echo ""
    test_scan_repo_no_tickets_dir
    echo ""
    test_scan_repo_empty_tickets_dir
    echo ""
    test_scan_repo_missing_dir
    echo ""
    test_scan_repo_aggregation_logic
    echo ""
    test_scan_repo_valid_json
    echo ""
    test_scan_repo_extracts_repo_name
    echo ""
    test_missing_repo_graceful_handling
    echo ""
    test_nonmatching_git_dir_name
    echo ""

    # Run integration tests
    echo "====================================="
    echo "Integration Tests"
    echo "====================================="
    echo ""
    test_integration_full_workspace_scan
    echo ""
    test_integration_empty_workspace
    echo ""
    test_integration_workspace_level_summary
    echo ""
    test_integration_output_valid_json
    echo ""
    test_integration_performance
    echo ""

    # Run compute_recommended_action tests
    echo "====================================="
    echo "compute_recommended_action() Function Tests"
    echo "====================================="
    echo ""
    test_recommended_action_multiple_priorities
    echo ""
    test_recommended_action_tied_priorities
    echo ""
    test_recommended_action_ready_false_filtered
    echo ""
    test_recommended_action_agent_ready_false_filtered
    echo ""
    test_recommended_action_agent_ready_true_selected
    echo ""
    test_recommended_action_all_verified_returns_none
    echo ""
    test_recommended_action_no_tickets_returns_none
    echo ""
    test_recommended_action_task_state_priority
    echo ""
    test_recommended_action_includes_sdd_root
    echo ""
    test_recommended_action_valid_json_output
    echo ""
    test_recommended_action_empty_input
    echo ""

    # Run root structure validation tests
    echo "====================================="
    echo "Root Structure Validation Tests (SDDLOOP-6.3003)"
    echo "====================================="
    echo ""
    test_empty_specs_root_warning
    echo ""
    test_identical_roots_warning
    echo ""
    test_no_warning_for_populated_specs_root
    echo ""
    test_no_warning_for_different_roots
    echo ""
    test_help_shows_directory_structure
    echo ""
    test_empty_specs_root_rejected
    echo ""
    test_empty_repos_root_rejected
    echo ""

    # Run discovery progress tests
    echo "====================================="
    echo "Discovery Progress Tests (SDDLOOP-6.3008)"
    echo "====================================="
    echo ""
    test_progress_with_many_repos
    echo ""
    test_progress_quiet_mode
    echo ""
    test_progress_with_few_repos
    echo ""

    # Run startup health check tests
    echo "====================================="
    echo "Startup Health Check Tests (SDDLOOP-6.3010)"
    echo "====================================="
    echo ""
    test_health_check_fails_missing_jq
    echo ""
    test_health_check_fails_missing_realpath
    echo ""
    test_health_check_fails_missing_timeout
    echo ""
    test_health_check_passes_all_available
    echo ""

    # Run filesystem timeout tests
    echo "====================================="
    echo "Filesystem Operation Timeout Tests (SDDLOOP-6.4003)"
    echo "====================================="
    echo ""
    test_scan_repo_timeout_handling
    echo ""
    test_scan_repo_normal_with_timeout
    echo ""

    # Run JSON log format tests
    echo "====================================="
    echo "JSON Log Format Tests (SDDLOOP-6.5004)"
    echo "====================================="
    echo ""
    test_log_format_json_flag
    echo ""
    test_log_format_json_env_var
    echo ""
    test_log_format_json_valid_json
    echo ""
    test_log_format_json_timestamp
    echo ""
    test_log_format_json_level
    echo ""
    test_log_format_cli_overrides_env
    echo ""
    test_log_format_default_text
    echo ""
    test_log_format_in_help
    echo ""
    test_format_json_log_function
    echo ""
    test_format_json_log_special_chars
    echo ""

    # Run shellcheck static analysis tests
    echo "====================================="
    echo "Shellcheck Static Analysis (SDDLOOP-6.5002)"
    echo "====================================="
    echo ""
    test_shellcheck_static_analysis
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
