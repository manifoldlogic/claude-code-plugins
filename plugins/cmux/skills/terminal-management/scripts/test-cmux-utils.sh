#!/usr/bin/env bash
#
# test-cmux-utils.sh - Unit tests for cmux-utils.sh
#
# DESCRIPTION:
#   Comprehensive test suite for cmux-utils.sh utility functions.
#   Tests each function in isolation using SSH mocking.
#
# USAGE:
#   bash test-cmux-utils.sh
#
# EXIT CODES:
#   0 - All tests passed
#   1 - One or more tests failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "${GREEN}PASS${NC}: $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "${RED}FAIL${NC}: $1"
    if [ -n "${2:-}" ]; then
        echo "       Reason: $2"
    fi
}

##############################################################################
# 1. Direct execution guard
##############################################################################

test_direct_execution_guard() {
    echo ""
    echo "--- Direct Execution Guard ---"

    local exit_code=0
    bash "$SCRIPT_DIR/cmux-utils.sh" 2>/dev/null || exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        pass "direct execution exits non-zero (exit $exit_code)"
    else
        fail "direct execution exits non-zero" "expected non-zero, got 0"
    fi
}

##############################################################################
# 2. is_container() detection
##############################################################################

test_is_container() {
    echo ""
    echo "--- is_container() Detection ---"

    # Source utils in subshell to avoid guard
    # We are in a devcontainer, so /.dockerenv should exist or REMOTE_CONTAINERS be set
    local result=0
    (
        source "$SCRIPT_DIR/cmux-utils.sh" 2>/dev/null
        is_container
    ) || result=$?

    if [ -f /.dockerenv ] || [ -n "${REMOTE_CONTAINERS:-}" ]; then
        if [ "$result" -eq 0 ]; then
            pass "is_container() returns 0 in container"
        else
            fail "is_container() returns 0 in container" "got exit $result"
        fi
    else
        if [ "$result" -ne 0 ]; then
            pass "is_container() returns non-zero on host"
        else
            fail "is_container() returns non-zero on host" "got exit 0"
        fi
    fi
}

##############################################################################
# 3. validate_ssh_host() missing HOST_USER
##############################################################################

test_validate_ssh_host_missing_host_user() {
    echo ""
    echo "--- validate_ssh_host() Missing HOST_USER ---"

    local exit_code=0
    (
        unset HOST_USER
        source "$SCRIPT_DIR/cmux-utils.sh" 2>/dev/null
        validate_ssh_host 2>/dev/null
    ) || exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        pass "validate_ssh_host() fails when HOST_USER not set"
    else
        fail "validate_ssh_host() fails when HOST_USER not set" "expected non-zero, got 0"
    fi
}

##############################################################################
# 4. validate_ssh_host() SSH failure
##############################################################################

test_validate_ssh_host_ssh_failure() {
    echo ""
    echo "--- validate_ssh_host() SSH Failure ---"

    local exit_code=0
    (
        export HOST_USER="testuser"
        ssh() { return 1; }
        export -f ssh
        source "$SCRIPT_DIR/cmux-utils.sh" 2>/dev/null
        validate_ssh_host 2>/dev/null
    ) || exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        pass "validate_ssh_host() fails when SSH fails"
    else
        fail "validate_ssh_host() fails when SSH fails" "expected non-zero, got 0"
    fi
}

##############################################################################
# 5. validate_ssh_host() success
##############################################################################

test_validate_ssh_host_success() {
    echo ""
    echo "--- validate_ssh_host() Success ---"

    local exit_code=0
    (
        export HOST_USER="testuser"
        ssh() { return 0; }
        export -f ssh
        source "$SCRIPT_DIR/cmux-utils.sh" 2>/dev/null
        validate_ssh_host 2>/dev/null
    ) || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        pass "validate_ssh_host() succeeds with mock SSH"
    else
        fail "validate_ssh_host() succeeds with mock SSH" "got exit $exit_code"
    fi
}

##############################################################################
# 6. validate_cmux() not installed
# Note: validate_cmux() only checks binary existence (test -x CMUX_BIN via SSH).
# It does NOT check whether the cmux daemon is running. Daemon running state
# is verified separately in cmux-check.sh check 5 (cmux ping -> PONG).
##############################################################################

test_validate_cmux_not_installed() {
    echo ""
    echo "--- validate_cmux() Not Installed ---"

    local exit_code=0
    (
        export HOST_USER="testuser"
        ssh() { return 1; }
        export -f ssh
        source "$SCRIPT_DIR/cmux-utils.sh" 2>/dev/null
        validate_cmux 2>/dev/null
    ) || exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        pass "validate_cmux() fails when binary not found"
    else
        fail "validate_cmux() fails when binary not found" "expected non-zero, got 0"
    fi
}

##############################################################################
# 7. validate_cmux() success
##############################################################################

test_validate_cmux_success() {
    echo ""
    echo "--- validate_cmux() Success ---"

    local exit_code=0
    (
        export HOST_USER="testuser"
        ssh() { return 0; }
        export -f ssh
        source "$SCRIPT_DIR/cmux-utils.sh" 2>/dev/null
        validate_cmux 2>/dev/null
    ) || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        pass "validate_cmux() succeeds when binary exists"
    else
        fail "validate_cmux() succeeds when binary exists" "got exit $exit_code"
    fi
}

##############################################################################
# 8. validate_socket_mode() not configured (cmuxOnly)
##############################################################################

test_validate_socket_mode_not_configured() {
    echo ""
    echo "--- validate_socket_mode() Not Configured ---"

    local exit_code=0
    local stderr_output=""
    stderr_output=$(
        export HOST_USER="testuser"
        ssh() {
            echo "cmuxOnly"
            return 0
        }
        export -f ssh
        source "$SCRIPT_DIR/cmux-utils.sh" 2>/dev/null
        validate_socket_mode 2>&1
    ) || exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        pass "validate_socket_mode() fails when mode is cmuxOnly"
    else
        fail "validate_socket_mode() fails when mode is cmuxOnly" "expected non-zero, got 0"
    fi

    # Check fix command is in output
    if echo "$stderr_output" | grep -qF "defaults write com.cmuxterm.app socketControlMode -string allowAll"; then
        pass "validate_socket_mode() error includes fix command"
    else
        fail "validate_socket_mode() error includes fix command" "got: $stderr_output"
    fi
}

##############################################################################
# 9. validate_socket_mode() allowAll
##############################################################################

test_validate_socket_mode_allow_all() {
    echo ""
    echo "--- validate_socket_mode() allowAll ---"

    local exit_code=0
    (
        export HOST_USER="testuser"
        ssh() {
            echo "allowAll"
            return 0
        }
        export -f ssh
        source "$SCRIPT_DIR/cmux-utils.sh" 2>/dev/null
        validate_socket_mode 2>/dev/null
    ) || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        pass "validate_socket_mode() passes when mode is allowAll"
    else
        fail "validate_socket_mode() passes when mode is allowAll" "got exit $exit_code"
    fi
}

##############################################################################
# 10. Output functions write to stderr
##############################################################################

test_output_functions_stderr() {
    echo ""
    echo "--- Output Functions Write to Stderr ---"

    # cmux_info
    local stdout_output=""
    stdout_output=$(
        source "$SCRIPT_DIR/cmux-utils.sh" 2>/dev/null
        cmux_info "test message" 2>/dev/null
    )
    if [ -z "$stdout_output" ]; then
        pass "cmux_info() produces no stdout"
    else
        fail "cmux_info() produces no stdout" "got: $stdout_output"
    fi

    local stderr_output=""
    stderr_output=$(
        source "$SCRIPT_DIR/cmux-utils.sh" 2>/dev/null
        cmux_info "test message" 2>&1 >/dev/null
    )
    if [ -n "$stderr_output" ]; then
        pass "cmux_info() writes to stderr"
    else
        fail "cmux_info() writes to stderr" "stderr was empty"
    fi

    # cmux_error
    stdout_output=$(
        source "$SCRIPT_DIR/cmux-utils.sh" 2>/dev/null
        cmux_error "test error" 2>/dev/null
    )
    if [ -z "$stdout_output" ]; then
        pass "cmux_error() produces no stdout"
    else
        fail "cmux_error() produces no stdout" "got: $stdout_output"
    fi

    # cmux_warn
    stdout_output=$(
        source "$SCRIPT_DIR/cmux-utils.sh" 2>/dev/null
        cmux_warn "test warning" 2>/dev/null
    )
    if [ -z "$stdout_output" ]; then
        pass "cmux_warn() produces no stdout"
    else
        fail "cmux_warn() produces no stdout" "got: $stdout_output"
    fi
}

##############################################################################
# 11. CMUX_BIN constant value
##############################################################################

test_cmux_bin_constant() {
    echo ""
    echo "--- CMUX_BIN Constant ---"

    local cmux_bin_value=""
    cmux_bin_value=$(
        unset CMUX_BIN_OVERRIDE
        source "$SCRIPT_DIR/cmux-utils.sh" 2>/dev/null
        echo "$CMUX_BIN"
    )

    if [ "$cmux_bin_value" = "/Applications/cmux.app/Contents/Resources/bin/cmux" ]; then
        pass "CMUX_BIN equals /Applications/cmux.app/Contents/Resources/bin/cmux"
    else
        fail "CMUX_BIN equals /Applications/cmux.app/Contents/Resources/bin/cmux" "got: $cmux_bin_value"
    fi
}

##############################################################################
# Main
##############################################################################

main() {
    echo ""
    echo "========================================"
    echo "  cmux-utils.sh Unit Tests"
    echo "========================================"

    test_direct_execution_guard
    test_is_container
    test_validate_ssh_host_missing_host_user
    test_validate_ssh_host_ssh_failure
    test_validate_ssh_host_success
    test_validate_cmux_not_installed
    test_validate_cmux_success
    test_validate_socket_mode_not_configured
    test_validate_socket_mode_allow_all
    test_output_functions_stderr
    test_cmux_bin_constant

    echo ""
    echo "========================================"
    echo "  Test Results"
    echo "========================================"
    echo ""
    echo -e "Tests run:    $TESTS_RUN"
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
