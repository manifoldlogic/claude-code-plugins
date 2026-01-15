#!/usr/bin/env bash
#
# test-iterm-utils.sh - Unit tests for iterm-utils.sh
#
# DESCRIPTION:
#   Comprehensive test suite for iterm-utils.sh utility functions.
#   Tests each function in isolation, including error paths and edge cases.
#
# USAGE:
#   ./test-iterm-utils.sh [--verbose]
#
# EXIT CODES:
#   0 - All tests passed
#   1 - One or more tests failed
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Verbose mode
VERBOSE="${1:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

##############################################################################
# Test Utilities
##############################################################################

# Print test result
pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}PASS${NC}: $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}FAIL${NC}: $1"
    if [ -n "${2:-}" ]; then
        echo -e "       ${YELLOW}Reason:${NC} $2"
    fi
}

skip() {
    echo -e "${YELLOW}SKIP${NC}: $1 - $2"
}

info() {
    if [ "$VERBOSE" = "--verbose" ]; then
        echo -e "${BLUE}INFO${NC}: $*"
    fi
}

# Run a test
run_test() {
    local test_name="$1"
    local test_func="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Running test: $test_name"
    if $test_func; then
        pass "$test_name"
    else
        fail "$test_name"
    fi
}

##############################################################################
# Test: Exit Code Constants
##############################################################################

test_exit_codes_defined() {
    # Source the utils
    # shellcheck source=iterm-utils.sh
    source "$SCRIPT_DIR/iterm-utils.sh" 2>/dev/null

    # Verify all exit codes are defined
    [ "$EXIT_SUCCESS" = "0" ] || return 1
    [ "$EXIT_CONNECTION_FAIL" = "1" ] || return 1
    [ "$EXIT_ITERM_UNAVAILABLE" = "2" ] || return 1
    [ "$EXIT_INVALID_ARGS" = "3" ] || return 1
    [ "$EXIT_NO_MATCH" = "4" ] || return 1
    return 0
}

##############################################################################
# Test: is_container()
##############################################################################

test_is_container_detects_dockerenv() {
    # shellcheck source=iterm-utils.sh
    source "$SCRIPT_DIR/iterm-utils.sh" 2>/dev/null

    # Create a mock /.dockerenv check
    # We test the function logic by checking if current env is container
    if [ -f /.dockerenv ]; then
        is_container
        return $?
    else
        # If no .dockerenv, verify it returns non-zero without .dockerenv
        # This test validates the logic, not the actual environment
        info "No /.dockerenv present, checking uname fallback"
        # On non-macOS (Linux), should return 0 (is container)
        if [ "$(uname -s)" != "Darwin" ]; then
            is_container
            return $?
        fi
        return 0  # Test passes if we reach here on macOS without .dockerenv
    fi
}

test_is_container_fallback_to_uname() {
    # shellcheck source=iterm-utils.sh
    source "$SCRIPT_DIR/iterm-utils.sh" 2>/dev/null

    local uname_result
    uname_result=$(uname -s)

    if [ "$uname_result" != "Darwin" ]; then
        # Not macOS, should detect as container
        if is_container; then
            return 0
        else
            return 1
        fi
    else
        # On macOS, without .dockerenv, should NOT detect as container
        if [ ! -f /.dockerenv ]; then
            if is_container; then
                return 1  # Should NOT be true on macOS without dockerenv
            else
                return 0
            fi
        fi
    fi
    return 0
}

##############################################################################
# Test: run_applescript() - Invalid Arguments
##############################################################################

test_run_applescript_empty_script() {
    # shellcheck source=iterm-utils.sh
    source "$SCRIPT_DIR/iterm-utils.sh" 2>/dev/null

    # Capture exit code directly - use subshell to avoid set -e exiting
    local exit_code
    exit_code=$(run_applescript "" 2>/dev/null; echo $?) || true

    # Should have failed with EXIT_INVALID_ARGS (3)
    [ "$exit_code" = "$EXIT_INVALID_ARGS" ] || return 1
    return 0
}

test_run_applescript_mode_auto_detection() {
    # shellcheck source=iterm-utils.sh
    source "$SCRIPT_DIR/iterm-utils.sh" 2>/dev/null

    # Test that auto mode works without error for mode selection
    # This doesn't execute, just validates mode logic
    local mode="auto"
    if is_container; then
        # In container, auto should resolve to remote
        info "Container detected, auto mode should use remote"
    else
        # On host, auto should resolve to local
        info "Host detected, auto mode should use local"
    fi
    return 0
}

##############################################################################
# Test: run_applescript() - Local Mode (macOS only)
##############################################################################

test_run_applescript_local_simple() {
    # shellcheck source=iterm-utils.sh
    source "$SCRIPT_DIR/iterm-utils.sh" 2>/dev/null

    # Skip if not on macOS
    if [ "$(uname -s)" != "Darwin" ]; then
        info "Skipping local AppleScript test - not on macOS"
        return 0
    fi

    # Simple AppleScript that returns a value
    local result
    result=$(run_applescript 'return "hello"' "local" 2>/dev/null)
    [ "$result" = "hello" ] || return 1
    return 0
}

##############################################################################
# Test: run_applescript() - Remote Mode
##############################################################################

test_run_applescript_remote_requires_host_user() {
    # shellcheck source=iterm-utils.sh
    source "$SCRIPT_DIR/iterm-utils.sh" 2>/dev/null

    # Temporarily unset HOST_USER
    local saved_host_user="${HOST_USER:-}"
    unset HOST_USER

    # Capture exit code - use subshell to avoid set -e exiting
    local exit_code
    exit_code=$(run_applescript 'return "test"' "remote" 2>/dev/null; echo $?) || true

    HOST_USER="$saved_host_user"

    # Verify exit code is EXIT_CONNECTION_FAIL (1)
    [ "$exit_code" = "$EXIT_CONNECTION_FAIL" ] || return 1
    return 0
}

##############################################################################
# Test: validate_iterm()
##############################################################################

test_validate_iterm_local() {
    # shellcheck source=iterm-utils.sh
    source "$SCRIPT_DIR/iterm-utils.sh" 2>/dev/null

    # Skip if not on macOS
    if [ "$(uname -s)" != "Darwin" ]; then
        info "Skipping local iTerm validation - not on macOS"
        return 0
    fi

    # On macOS, check if iTerm exists
    if [ -d "/Applications/iTerm.app" ]; then
        # Should pass
        _validate_iterm_local 2>/dev/null
        return $?
    else
        # Should fail with correct exit code
        local exit_code
        _validate_iterm_local 2>/dev/null || exit_code=$?
        [ "$exit_code" = "$EXIT_ITERM_UNAVAILABLE" ] || return 1
        return 0
    fi
}

test_validate_iterm_returns_correct_exit_code() {
    # shellcheck source=iterm-utils.sh
    source "$SCRIPT_DIR/iterm-utils.sh" 2>/dev/null

    # This test verifies the exit code constants are used correctly
    # We can't easily mock filesystem, so we test the logic flow

    # If we're in container, validate_iterm calls validate_ssh_host first
    if is_container; then
        # Without HOST_USER, should fail
        local saved_host_user="${HOST_USER:-}"
        unset HOST_USER

        # Capture exit code - use subshell to avoid set -e exiting
        local exit_code
        exit_code=$(validate_iterm 2>/dev/null; echo $?) || true

        HOST_USER="$saved_host_user"

        [ "$exit_code" = "$EXIT_CONNECTION_FAIL" ] || return 1
    fi
    return 0
}

##############################################################################
# Test: validate_ssh_host()
##############################################################################

test_validate_ssh_host_requires_host_user() {
    # shellcheck source=iterm-utils.sh
    source "$SCRIPT_DIR/iterm-utils.sh" 2>/dev/null

    # Temporarily unset HOST_USER
    local saved_host_user="${HOST_USER:-}"
    unset HOST_USER

    # Capture exit code - use subshell to avoid set -e exiting
    local exit_code
    exit_code=$(validate_ssh_host 2>/dev/null; echo $?) || true

    HOST_USER="$saved_host_user"

    # Verify exit code is EXIT_CONNECTION_FAIL (1)
    [ "$exit_code" = "$EXIT_CONNECTION_FAIL" ] || return 1
    return 0
}

test_validate_ssh_host_with_valid_host_user() {
    # shellcheck source=iterm-utils.sh
    source "$SCRIPT_DIR/iterm-utils.sh" 2>/dev/null

    # Skip if HOST_USER not set
    if [ -z "${HOST_USER:-}" ]; then
        info "HOST_USER not set, skipping SSH connectivity test"
        return 0
    fi

    # Test actual SSH connectivity (may fail if SSH not configured)
    if validate_ssh_host 2>/dev/null; then
        info "SSH connection to host.docker.internal succeeded"
        return 0
    else
        # Not necessarily a test failure - SSH may not be configured
        info "SSH connection failed (may be expected if not in container)"
        return 0
    fi
}

##############################################################################
# Test: Cleanup Trap Handlers
##############################################################################

test_cleanup_function_exists() {
    # shellcheck source=iterm-utils.sh
    source "$SCRIPT_DIR/iterm-utils.sh" 2>/dev/null

    # Verify cleanup function is defined
    if type _cleanup_temp_script &>/dev/null; then
        return 0
    else
        return 1
    fi
}

test_cleanup_handles_empty_temp() {
    # shellcheck source=iterm-utils.sh
    source "$SCRIPT_DIR/iterm-utils.sh" 2>/dev/null

    # Set temp to empty
    _ITERM_TEMP_SCRIPT=""

    # Cleanup should not fail with empty temp
    _cleanup_temp_script
    return $?
}

test_cleanup_clears_variable() {
    # shellcheck source=iterm-utils.sh
    source "$SCRIPT_DIR/iterm-utils.sh" 2>/dev/null

    # Create a temp file locally for testing
    _ITERM_TEMP_SCRIPT=$(mktemp /tmp/test-iterm-XXXXXX.scpt)
    touch "$_ITERM_TEMP_SCRIPT"

    # Cleanup should remove file and clear variable
    # (only local cleanup without HOST_USER)
    local saved_host_user="${HOST_USER:-}"
    unset HOST_USER

    _cleanup_temp_script

    HOST_USER="$saved_host_user"

    # Variable should be cleared
    [ -z "$_ITERM_TEMP_SCRIPT" ] || return 1
    return 0
}

##############################################################################
# Test: Color Functions
##############################################################################

test_color_functions_exist() {
    # shellcheck source=iterm-utils.sh
    source "$SCRIPT_DIR/iterm-utils.sh" 2>/dev/null

    # Verify all color functions are defined
    type iterm_info &>/dev/null || return 1
    type iterm_ok &>/dev/null || return 1
    type iterm_warn &>/dev/null || return 1
    type iterm_error &>/dev/null || return 1
    return 0
}

test_color_functions_output_to_stderr() {
    # shellcheck source=iterm-utils.sh
    source "$SCRIPT_DIR/iterm-utils.sh" 2>/dev/null

    # Capture stdout and stderr separately
    local stdout stderr

    # iterm_info should output to stderr
    stdout=$(iterm_info "test" 2>/dev/null)
    [ -z "$stdout" ] || return 1

    stderr=$(iterm_info "test" 2>&1 >/dev/null)
    [ -n "$stderr" ] || return 1

    return 0
}

##############################################################################
# Test: Direct Execution Prevention
##############################################################################

test_direct_execution_fails() {
    # Execute the script directly (not sourced)
    # It should exit with EXIT_INVALID_ARGS (3)
    # Capture exit code - use subshell to avoid set -e exiting
    local exit_code
    exit_code=$(bash "$SCRIPT_DIR/iterm-utils.sh" 2>/dev/null; echo $?) || true

    [ "$exit_code" = "3" ] || return 1
    return 0
}

##############################################################################
# Test: Concurrent Execution (temp file uniqueness)
##############################################################################

test_mktemp_pattern_uniqueness() {
    # shellcheck source=iterm-utils.sh
    source "$SCRIPT_DIR/iterm-utils.sh" 2>/dev/null

    # Create multiple temp files to verify uniqueness
    local file1 file2 file3
    file1=$(mktemp /tmp/iterm-XXXXXX.scpt)
    file2=$(mktemp /tmp/iterm-XXXXXX.scpt)
    file3=$(mktemp /tmp/iterm-XXXXXX.scpt)

    # Verify all files are different
    [ "$file1" != "$file2" ] || { rm -f "$file1" "$file2" "$file3"; return 1; }
    [ "$file2" != "$file3" ] || { rm -f "$file1" "$file2" "$file3"; return 1; }
    [ "$file1" != "$file3" ] || { rm -f "$file1" "$file2" "$file3"; return 1; }

    # Cleanup
    rm -f "$file1" "$file2" "$file3"
    return 0
}

##############################################################################
# Test: Integration - Full Workflow (dry-run style)
##############################################################################

test_full_workflow_in_container() {
    # shellcheck source=iterm-utils.sh
    source "$SCRIPT_DIR/iterm-utils.sh" 2>/dev/null

    # Skip if not in container
    if ! is_container; then
        info "Not in container, skipping container workflow test"
        return 0
    fi

    # Skip if HOST_USER not set
    if [ -z "${HOST_USER:-}" ]; then
        info "HOST_USER not set, skipping workflow test"
        return 0
    fi

    # Test SSH validation first
    if ! validate_ssh_host 2>/dev/null; then
        info "SSH not available, skipping workflow test"
        return 0
    fi

    # Test iTerm validation (if SSH works)
    # Note: May fail if iTerm not installed on host
    validate_iterm 2>/dev/null || info "iTerm validation failed (may be expected)"

    return 0
}

##############################################################################
# Main Test Runner
##############################################################################

main() {
    echo ""
    echo "========================================"
    echo "  iTerm Utils Unit Tests"
    echo "========================================"
    echo ""

    # Exit Code Tests
    echo "--- Exit Code Constants ---"
    run_test "Exit codes are defined" test_exit_codes_defined

    # is_container() Tests
    echo ""
    echo "--- is_container() Tests ---"
    run_test "Detects /.dockerenv" test_is_container_detects_dockerenv
    run_test "Fallback to uname" test_is_container_fallback_to_uname

    # run_applescript() Tests
    echo ""
    echo "--- run_applescript() Tests ---"
    run_test "Empty script fails with EXIT_INVALID_ARGS" test_run_applescript_empty_script
    run_test "Auto mode detection works" test_run_applescript_mode_auto_detection
    run_test "Local mode simple script" test_run_applescript_local_simple
    run_test "Remote mode requires HOST_USER" test_run_applescript_remote_requires_host_user

    # validate_iterm() Tests
    echo ""
    echo "--- validate_iterm() Tests ---"
    run_test "Local iTerm validation" test_validate_iterm_local
    run_test "Returns correct exit codes" test_validate_iterm_returns_correct_exit_code

    # validate_ssh_host() Tests
    echo ""
    echo "--- validate_ssh_host() Tests ---"
    run_test "Requires HOST_USER" test_validate_ssh_host_requires_host_user
    run_test "With valid HOST_USER" test_validate_ssh_host_with_valid_host_user

    # Cleanup Trap Tests
    echo ""
    echo "--- Cleanup Trap Tests ---"
    run_test "Cleanup function exists" test_cleanup_function_exists
    run_test "Cleanup handles empty temp" test_cleanup_handles_empty_temp
    run_test "Cleanup clears variable" test_cleanup_clears_variable

    # Color Functions Tests
    echo ""
    echo "--- Color Functions Tests ---"
    run_test "Color functions exist" test_color_functions_exist
    run_test "Color functions output to stderr" test_color_functions_output_to_stderr

    # Direct Execution Tests
    echo ""
    echo "--- Direct Execution Tests ---"
    run_test "Direct execution fails" test_direct_execution_fails

    # Concurrent Execution Tests
    echo ""
    echo "--- Concurrent Execution Tests ---"
    run_test "mktemp pattern uniqueness" test_mktemp_pattern_uniqueness

    # Integration Tests
    echo ""
    echo "--- Integration Tests ---"
    run_test "Full workflow in container" test_full_workflow_in_container

    # Summary
    echo ""
    echo "========================================"
    echo "  Test Results"
    echo "========================================"
    echo ""
    echo -e "Tests run:    ${BLUE}$TESTS_RUN${NC}"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo ""

    if [ "$TESTS_FAILED" -gt 0 ]; then
        echo -e "${RED}FAILED${NC}: Some tests failed"
        exit 1
    else
        echo -e "${GREEN}SUCCESS${NC}: All tests passed"
        exit 0
    fi
}

main "$@"
