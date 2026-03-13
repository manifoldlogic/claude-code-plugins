#!/usr/bin/env bash
#
# test-cmux-check.sh - Unit tests for cmux-check.sh
#
# DESCRIPTION:
#   Comprehensive test suite for cmux-check.sh prerequisite validator.
#   Tests all check combinations using SSH mocking.
#
# USAGE:
#   bash test-cmux-check.sh
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
# 1. All prerequisites pass
##############################################################################

test_all_pass() {
    echo ""
    echo "--- All Prerequisites Pass ---"

    local exit_code=0
    (
        export HOST_USER="testuser"
        ssh() {
            if echo "$*" | grep -q "defaults read"; then
                echo "allowAll"
                return 0
            elif echo "$*" | grep -q "ping"; then
                echo "PONG"
                return 0
            fi
            return 0
        }
        export -f ssh
        bash "$SCRIPT_DIR/cmux-check.sh" 2>/dev/null
    ) || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        pass "all prerequisites pass exits 0"
    else
        fail "all prerequisites pass exits 0" "got exit $exit_code"
    fi
}

##############################################################################
# 2. HOST_USER not set
##############################################################################

test_host_user_not_set() {
    echo ""
    echo "--- HOST_USER Not Set ---"

    local exit_code=0
    local output=""
    output=$(
        unset HOST_USER
        bash "$SCRIPT_DIR/cmux-check.sh" 2>&1
    ) || exit_code=$?

    if [ "$exit_code" -eq 1 ]; then
        pass "HOST_USER not set exits 1"
    else
        fail "HOST_USER not set exits 1" "got exit $exit_code"
    fi

    if echo "$output" | grep -qi "HOST_USER"; then
        pass "HOST_USER not set message mentions HOST_USER"
    else
        fail "HOST_USER not set message mentions HOST_USER" "got: $output"
    fi
}

##############################################################################
# 3. SSH unreachable
##############################################################################

test_ssh_unreachable() {
    echo ""
    echo "--- SSH Unreachable ---"

    local exit_code=0
    (
        export HOST_USER="testuser"
        ssh() { return 255; }
        export -f ssh
        bash "$SCRIPT_DIR/cmux-check.sh" 2>/dev/null
    ) || exit_code=$?

    if [ "$exit_code" -eq 1 ]; then
        pass "SSH unreachable exits 1"
    else
        fail "SSH unreachable exits 1" "got exit $exit_code"
    fi
}

##############################################################################
# 4. socketControlMode not allowAll
##############################################################################

test_socket_mode_not_allow_all() {
    echo ""
    echo "--- socketControlMode Not allowAll ---"

    local exit_code=0
    local output=""
    output=$(
        export HOST_USER="testuser"
        ssh() {
            if echo "$*" | grep -q "defaults read"; then
                echo "cmuxOnly"
                return 0
            fi
            # connectivity check: pass
            return 0
        }
        export -f ssh
        bash "$SCRIPT_DIR/cmux-check.sh" 2>&1
    ) || exit_code=$?

    if [ "$exit_code" -eq 1 ]; then
        pass "socketControlMode=cmuxOnly exits 1"
    else
        fail "socketControlMode=cmuxOnly exits 1" "got exit $exit_code"
    fi

    if echo "$output" | grep -qF "defaults write com.cmuxterm.app socketControlMode -string allowAll"; then
        pass "socketControlMode failure includes fix command"
    else
        fail "socketControlMode failure includes fix command" "got: $output"
    fi
}

##############################################################################
# 5. socketControlMode not set (empty/error)
##############################################################################

test_socket_mode_not_set() {
    echo ""
    echo "--- socketControlMode Not Set ---"

    local exit_code=0
    local output=""
    output=$(
        export HOST_USER="testuser"
        ssh() {
            if echo "$*" | grep -q "defaults read"; then
                echo ""
                return 1
            fi
            return 0
        }
        export -f ssh
        bash "$SCRIPT_DIR/cmux-check.sh" 2>&1
    ) || exit_code=$?

    if [ "$exit_code" -eq 1 ]; then
        pass "socketControlMode not set exits 1"
    else
        fail "socketControlMode not set exits 1" "got exit $exit_code"
    fi

    if echo "$output" | grep -qF "defaults write com.cmuxterm.app socketControlMode -string allowAll"; then
        pass "socketControlMode not set includes fix command"
    else
        fail "socketControlMode not set includes fix command" "got: $output"
    fi
}

##############################################################################
# 6. cmux binary not found
##############################################################################

test_binary_not_found() {
    echo ""
    echo "--- cmux Binary Not Found ---"

    local exit_code=0
    local output=""
    output=$(
        export HOST_USER="testuser"
        ssh() {
            if echo "$*" | grep -q "defaults read"; then
                echo "allowAll"
                return 0
            elif echo "$*" | grep -q "test -x"; then
                return 1
            fi
            return 0
        }
        export -f ssh
        bash "$SCRIPT_DIR/cmux-check.sh" 2>&1
    ) || exit_code=$?

    if [ "$exit_code" -eq 1 ]; then
        pass "binary not found exits 1"
    else
        fail "binary not found exits 1" "got exit $exit_code"
    fi

    if echo "$output" | grep -qi "not found"; then
        pass "binary not found message says not found"
    else
        fail "binary not found message says not found" "got: $output"
    fi
}

##############################################################################
# 7. cmux not running (ping fails)
##############################################################################

test_not_running() {
    echo ""
    echo "--- cmux Not Running ---"

    local exit_code=0
    local output=""
    output=$(
        export HOST_USER="testuser"
        ssh() {
            if echo "$*" | grep -q "defaults read"; then
                echo "allowAll"
                return 0
            elif echo "$*" | grep -q "test -x"; then
                return 0
            elif echo "$*" | grep -q "ping"; then
                echo "ERROR"
                return 1
            fi
            return 0
        }
        export -f ssh
        bash "$SCRIPT_DIR/cmux-check.sh" 2>&1
    ) || exit_code=$?

    if [ "$exit_code" -eq 1 ]; then
        pass "cmux not running exits 1"
    else
        fail "cmux not running exits 1" "got exit $exit_code"
    fi

    if echo "$output" | grep -qi "not running"; then
        pass "cmux not running message says not running"
    else
        fail "cmux not running message says not running" "got: $output"
    fi
}

##############################################################################
# 8. Partial failure (SSH ok, socketControlMode ok, binary not found)
##############################################################################

test_partial_failure() {
    echo ""
    echo "--- Partial Failure ---"

    local exit_code=0
    (
        export HOST_USER="testuser"
        ssh() {
            if echo "$*" | grep -q "defaults read"; then
                echo "allowAll"
                return 0
            elif echo "$*" | grep -q "test -x"; then
                return 1
            fi
            return 0
        }
        export -f ssh
        bash "$SCRIPT_DIR/cmux-check.sh" 2>/dev/null
    ) || exit_code=$?

    if [ "$exit_code" -eq 1 ]; then
        pass "partial failure (binary not found) exits 1"
    else
        fail "partial failure (binary not found) exits 1" "got exit $exit_code"
    fi
}

##############################################################################
# 9. Quiet mode success
##############################################################################

test_quiet_mode_success() {
    echo ""
    echo "--- Quiet Mode Success ---"

    local exit_code=0
    local combined_output=""
    combined_output=$(
        export HOST_USER="testuser"
        ssh() {
            if echo "$*" | grep -q "defaults read"; then
                echo "allowAll"
                return 0
            elif echo "$*" | grep -q "ping"; then
                echo "PONG"
                return 0
            fi
            return 0
        }
        export -f ssh
        bash "$SCRIPT_DIR/cmux-check.sh" --quiet 2>&1
    ) || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        pass "quiet mode success exits 0"
    else
        fail "quiet mode success exits 0" "got exit $exit_code"
    fi

    if [ -z "$combined_output" ]; then
        pass "quiet mode success produces no output"
    else
        fail "quiet mode success produces no output" "got: $combined_output"
    fi
}

##############################################################################
# 10. Quiet mode failure
##############################################################################

test_quiet_mode_failure() {
    echo ""
    echo "--- Quiet Mode Failure ---"

    local exit_code=0
    local combined_output=""
    combined_output=$(
        unset HOST_USER
        bash "$SCRIPT_DIR/cmux-check.sh" --quiet 2>&1
    ) || exit_code=$?

    if [ "$exit_code" -eq 1 ]; then
        pass "quiet mode failure exits 1"
    else
        fail "quiet mode failure exits 1" "got exit $exit_code"
    fi

    if [ -z "$combined_output" ]; then
        pass "quiet mode failure produces no output"
    else
        fail "quiet mode failure produces no output" "got: $combined_output"
    fi
}

##############################################################################
# 11. HOST_USER not set - stdout is clean (diagnostics go to stderr)
##############################################################################

test_host_user_not_set_stdout_clean() {
    echo ""
    echo "--- HOST_USER Not Set: stdout Clean ---"

    local exit_code=0
    local stdout_only=""
    stdout_only=$(
        HOST_USER="" bash "$SCRIPT_DIR/cmux-check.sh" 2>/dev/null
    ) || exit_code=$?

    if [ -z "$stdout_only" ]; then
        pass "HOST_USER not set produces no stdout"
    else
        fail "HOST_USER not set produces no stdout" "got stdout: $stdout_only"
    fi
}

##############################################################################
# Main
##############################################################################

main() {
    echo ""
    echo "========================================"
    echo "  cmux-check.sh Unit Tests"
    echo "========================================"

    test_all_pass
    test_host_user_not_set
    test_ssh_unreachable
    test_socket_mode_not_allow_all
    test_socket_mode_not_set
    test_binary_not_found
    test_not_running
    test_partial_failure
    test_quiet_mode_success
    test_quiet_mode_failure
    test_host_user_not_set_stdout_clean

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
