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

    # Run tests
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
