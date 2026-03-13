#!/usr/bin/env bash
#
# test-cmux-ssh.sh - Unit tests for cmux-ssh.sh
#
# DESCRIPTION:
#   Comprehensive test suite for cmux-ssh.sh SSH wrapper.
#   Tests help flags, error paths, escaping, dry-run, and happy paths.
#
# USAGE:
#   bash test-cmux-ssh.sh
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
# 1. Help flag (--help)
##############################################################################

test_help_flag() {
    echo ""
    echo "--- Help Flag ---"

    local exit_code=0
    local output=""
    output=$(bash "$SCRIPT_DIR/cmux-ssh.sh" --help 2>/dev/null) || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        pass "--help exits 0"
    else
        fail "--help exits 0" "got exit $exit_code"
    fi

    if [ -n "$output" ]; then
        pass "--help produces non-empty output"
    else
        fail "--help produces non-empty output" "output was empty"
    fi
}

##############################################################################
# 2. Short help flag (-h)
##############################################################################

test_short_help_flag() {
    echo ""
    echo "--- Short Help Flag ---"

    local exit_code=0
    local output=""
    output=$(bash "$SCRIPT_DIR/cmux-ssh.sh" -h 2>/dev/null) || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        pass "-h exits 0"
    else
        fail "-h exits 0" "got exit $exit_code"
    fi

    if [ -n "$output" ]; then
        pass "-h produces non-empty output"
    else
        fail "-h produces non-empty output" "output was empty"
    fi
}

##############################################################################
# 3. No arguments (exit 3)
##############################################################################

test_no_arguments() {
    echo ""
    echo "--- No Arguments ---"

    local exit_code=0
    export HOST_USER="testuser"
    ssh() { return 0; }
    export -f ssh
    bash "$SCRIPT_DIR/cmux-ssh.sh" 2>/dev/null || exit_code=$?

    if [ "$exit_code" -eq 3 ]; then
        pass "no arguments exits 3"
    else
        fail "no arguments exits 3" "got exit $exit_code"
    fi
}

##############################################################################
# 4. Missing HOST_USER (exit 1)
##############################################################################

test_missing_host_user() {
    echo ""
    echo "--- Missing HOST_USER ---"

    local exit_code=0
    (
        unset HOST_USER
        ssh() { return 0; }
        export -f ssh
        bash "$SCRIPT_DIR/cmux-ssh.sh" list-workspaces 2>/dev/null
    ) || exit_code=$?

    if [ "$exit_code" -eq 1 ]; then
        pass "missing HOST_USER exits 1"
    else
        fail "missing HOST_USER exits 1" "got exit $exit_code"
    fi
}

##############################################################################
# 5. Simple command (happy path)
##############################################################################

test_simple_command() {
    echo ""
    echo "--- Simple Command (Happy Path) ---"

    local exit_code=0
    (
        export HOST_USER="testuser"
        ssh() {
            return 0
        }
        export -f ssh
        bash "$SCRIPT_DIR/cmux-ssh.sh" list-workspaces 2>/dev/null
    ) || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        pass "simple command exits 0"
    else
        fail "simple command exits 0" "got exit $exit_code"
    fi
}

##############################################################################
# 6. Workspace-targeting command
##############################################################################

test_workspace_targeting() {
    echo ""
    echo "--- Workspace-Targeting Command ---"

    local exit_code=0
    (
        export HOST_USER="testuser"
        ssh() {
            return 0
        }
        export -f ssh
        bash "$SCRIPT_DIR/cmux-ssh.sh" send --workspace "workspace:1" "hello" 2>/dev/null
    ) || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        pass "workspace-targeting command exits 0"
    else
        fail "workspace-targeting command exits 0" "got exit $exit_code"
    fi
}

##############################################################################
# 7. Full binary path in dry-run output
##############################################################################

test_full_binary_path_in_dry_run() {
    echo ""
    echo "--- Full Binary Path in Dry-Run Output ---"

    local output=""
    output=$(
        export HOST_USER="testuser"
        bash "$SCRIPT_DIR/cmux-ssh.sh" --dry-run list-workspaces 2>/dev/null
    )

    if echo "$output" | grep -qF "/Applications/cmux.app/Contents/Resources/bin/cmux"; then
        pass "full binary path in dry-run output"
    else
        fail "full binary path in dry-run output" "got: $output"
    fi
}

##############################################################################
# 8. Dry-run flag does not call ssh
##############################################################################

test_dry_run_no_ssh() {
    echo ""
    echo "--- Dry-Run Does Not Call SSH ---"

    local exit_code=0
    local output=""
    output=$(
        export HOST_USER="testuser"
        # If ssh were called, this would fail
        ssh() { exit 99; }
        export -f ssh
        bash "$SCRIPT_DIR/cmux-ssh.sh" --dry-run list-workspaces 2>/dev/null
    ) || exit_code=$?

    if [ "$exit_code" -eq 0 ] && [ -n "$output" ]; then
        pass "dry-run prints SSH command without calling ssh"
    else
        fail "dry-run prints SSH command without calling ssh" "exit=$exit_code output=$output"
    fi
}

##############################################################################
# 9. Escaping: spaces
##############################################################################

test_escaping_spaces() {
    echo ""
    echo "--- Escaping: Spaces ---"

    local output=""
    output=$(
        export HOST_USER="testuser"
        bash "$SCRIPT_DIR/cmux-ssh.sh" --dry-run send --workspace "workspace:1" "hello world" 2>/dev/null
    )

    if echo "$output" | grep -qF 'hello\ world'; then
        pass "escaping spaces: hello world -> hello\ world"
    else
        fail "escaping spaces" "got: $output"
    fi
}

##############################################################################
# 10. Escaping: single quote
##############################################################################

test_escaping_single_quote() {
    echo ""
    echo "--- Escaping: Single Quote ---"

    local output=""
    output=$(
        export HOST_USER="testuser"
        bash "$SCRIPT_DIR/cmux-ssh.sh" --dry-run send --workspace "workspace:1" "it's a test" 2>/dev/null
    )

    if echo "$output" | grep -qF "it\\'s\\ a\\ test"; then
        pass "escaping single quote: it's a test -> it\\'s\\ a\\ test"
    else
        fail "escaping single quote: it's a test -> it\\'s\\ a\\ test" "got: $output"
    fi
}

##############################################################################
# 11. Escaping: dollar sign
##############################################################################

test_escaping_dollar_sign() {
    echo ""
    echo "--- Escaping: Dollar Sign ---"

    local output=""
    output=$(
        export HOST_USER="testuser"
        bash "$SCRIPT_DIR/cmux-ssh.sh" --dry-run send --workspace "workspace:1" 'echo $HOME' 2>/dev/null
    )

    if echo "$output" | grep -qF '\$HOME'; then
        pass "escaping dollar sign: \$HOME is escaped"
    else
        fail "escaping dollar sign: \$HOME is escaped" "got: $output"
    fi
}

##############################################################################
# 12. Escaping: semicolon injection
##############################################################################

test_escaping_semicolon() {
    echo ""
    echo "--- Escaping: Semicolon Injection ---"

    local output=""
    output=$(
        export HOST_USER="testuser"
        bash "$SCRIPT_DIR/cmux-ssh.sh" --dry-run send --workspace "workspace:1" 'cmd; rm -rf /' 2>/dev/null
    )

    if echo "$output" | grep -qF '\;'; then
        pass "escaping semicolon: semicolon is escaped"
    else
        fail "escaping semicolon: semicolon is escaped" "got: $output"
    fi
}

##############################################################################
# 13. Escaping: command substitution
##############################################################################

test_escaping_command_substitution() {
    echo ""
    echo "--- Escaping: Command Substitution ---"

    local output=""
    output=$(
        export HOST_USER="testuser"
        bash "$SCRIPT_DIR/cmux-ssh.sh" --dry-run send --workspace "workspace:1" '$(whoami)' 2>/dev/null
    )

    if echo "$output" | grep -qF '\$'; then
        pass "escaping command substitution: \$( is escaped"
    else
        fail "escaping command substitution: \$( is escaped" "got: $output"
    fi
}

##############################################################################
# 14. Newline rejection (exit 2)
##############################################################################

test_newline_rejection() {
    echo ""
    echo "--- Newline Rejection ---"

    local exit_code=0
    local newline_arg
    newline_arg=$'line1\nline2'

    (
        export HOST_USER="testuser"
        ssh() { return 0; }
        export -f ssh
        bash "$SCRIPT_DIR/cmux-ssh.sh" send --workspace "workspace:1" "$newline_arg" 2>/dev/null
    ) || exit_code=$?

    if [ "$exit_code" -eq 2 ]; then
        pass "newline rejected with exit code 2"
    else
        fail "newline rejected with exit code 2" "got exit $exit_code"
    fi
}

##############################################################################
# 15. Pass-through of cmux output
##############################################################################

test_passthrough_output() {
    echo ""
    echo "--- Pass-Through of cmux Output ---"

    local output=""
    output=$(
        export HOST_USER="testuser"
        ssh() {
            echo "workspace:1 - my workspace"
            echo "workspace:2 - other workspace"
            return 0
        }
        export -f ssh
        bash "$SCRIPT_DIR/cmux-ssh.sh" list-workspaces 2>/dev/null
    )

    if echo "$output" | grep -qF "workspace:1 - my workspace"; then
        pass "SSH output passes through to stdout"
    else
        fail "SSH output passes through to stdout" "got: $output"
    fi
}

##############################################################################
# Main
##############################################################################

main() {
    echo ""
    echo "========================================"
    echo "  cmux-ssh.sh Unit Tests"
    echo "========================================"

    test_help_flag
    test_short_help_flag
    test_no_arguments
    test_missing_host_user
    test_simple_command
    test_workspace_targeting
    test_full_binary_path_in_dry_run
    test_dry_run_no_ssh
    test_escaping_spaces
    test_escaping_single_quote
    test_escaping_dollar_sign
    test_escaping_semicolon
    test_escaping_command_substitution
    test_newline_rejection
    test_passthrough_output

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
