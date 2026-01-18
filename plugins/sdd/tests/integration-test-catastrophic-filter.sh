#!/bin/bash
#
# Integration Test: Catastrophic Command Filter End-to-End
#
# Tests the block-catastrophic-commands.py hook in an end-to-end scenario
# simulating Claude Code's hook invocation protocol.
#
# Usage:
#   bash tests/integration-test-catastrophic-filter.sh
#
# Exit Codes:
#   0 - All tests passed
#   1 - One or more tests failed
#

set -euo pipefail

# Get the directory where this test script lives
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
HOOK_CATASTROPHIC="$PLUGIN_DIR/hooks/block-catastrophic-commands.py"
HOOK_DANGEROUS_GIT="$PLUGIN_DIR/hooks/block-dangerous-git.py"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

log_pass() {
    echo -e "${GREEN}✓${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
}

log_fail() {
    echo -e "${RED}✗${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
}

# =============================================================================
# Integration Test: Catastrophic Command Blocking
# =============================================================================

test_integration_blocks_root_deletion() {
    echo ""
    echo "--- Test: Integration - Root Deletion Blocked ---"

    # Simulate Claude Code hook invocation for catastrophic command
    local input='{"tool_input":{"command":"rm -rf /"}}'
    local output
    local exit_code=0

    output=$(echo "$input" | python3 "$HOOK_CATASTROPHIC" 2>&1) || exit_code=$?

    if [ $exit_code -eq 2 ]; then
        log_pass "Root deletion command blocked with exit code 2"
    else
        log_fail "Expected exit code 2, got $exit_code"
    fi

    if echo "$output" | grep -q "root filesystem deletion"; then
        log_pass "Error message explains catastrophic risk"
    else
        log_fail "Missing 'root filesystem deletion' in error message"
    fi

    if echo "$output" | grep -q "BLOCKED"; then
        log_pass "Error message includes BLOCKED indicator"
    else
        log_fail "Missing BLOCKED indicator in error message"
    fi
}

test_integration_blocks_disk_wipe() {
    echo ""
    echo "--- Test: Integration - Disk Wipe Blocked ---"

    local input='{"tool_input":{"command":"dd if=/dev/zero of=/dev/sda bs=1M"}}'
    local output
    local exit_code=0

    output=$(echo "$input" | python3 "$HOOK_CATASTROPHIC" 2>&1) || exit_code=$?

    if [ $exit_code -eq 2 ]; then
        log_pass "Disk wipe command blocked with exit code 2"
    else
        log_fail "Expected exit code 2, got $exit_code"
    fi

    if echo "$output" | grep -q "disk wipe"; then
        log_pass "Error message explains disk wipe risk"
    else
        log_fail "Missing 'disk wipe' in error message"
    fi
}

test_integration_allows_safe_command() {
    echo ""
    echo "--- Test: Integration - Safe Command Allowed ---"

    local input='{"tool_input":{"command":"rm -rf /tmp/test-output"}}'
    local output
    local exit_code=0

    output=$(echo "$input" | python3 "$HOOK_CATASTROPHIC" 2>&1) || exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log_pass "Safe command allowed with exit code 0"
    else
        log_fail "Expected exit code 0, got $exit_code"
    fi

    if [ -z "$output" ]; then
        log_pass "No error output for allowed command"
    else
        log_fail "Unexpected output for allowed command: $output"
    fi
}

# =============================================================================
# Integration Test: Hook Chain (Both Hooks)
# =============================================================================

test_hook_chain_dangerous_git_blocked() {
    echo ""
    echo "--- Test: Hook Chain - Dangerous Git Blocked ---"

    # Verify block-dangerous-git.py also works
    if [ ! -f "$HOOK_DANGEROUS_GIT" ]; then
        log_fail "block-dangerous-git.py not found at $HOOK_DANGEROUS_GIT"
        return
    fi

    local input='{"tool_input":{"command":"git reset --hard"}}'
    local output
    local exit_code=0

    output=$(echo "$input" | python3 "$HOOK_DANGEROUS_GIT" 2>&1) || exit_code=$?

    if [ $exit_code -eq 2 ]; then
        log_pass "Dangerous git command blocked"
    else
        log_fail "Expected dangerous git blocked (exit 2), got $exit_code"
    fi
}

test_hook_chain_safe_git_allowed() {
    echo ""
    echo "--- Test: Hook Chain - Safe Git Allowed ---"

    local input='{"tool_input":{"command":"git status"}}'
    local output
    local exit_code=0

    output=$(echo "$input" | python3 "$HOOK_DANGEROUS_GIT" 2>&1) || exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log_pass "Safe git command allowed"
    else
        log_fail "Expected safe git allowed (exit 0), got $exit_code"
    fi
}

# =============================================================================
# Integration Test: Hook Execution Order
# =============================================================================

test_multiple_hooks_in_sequence() {
    echo ""
    echo "--- Test: Multiple Hooks Execute in Sequence ---"

    # Simulate running both hooks for a command that passes both
    local input='{"tool_input":{"command":"ls -la /tmp"}}'
    local exit_code_1=0
    local exit_code_2=0

    echo "$input" | python3 "$HOOK_DANGEROUS_GIT" >/dev/null 2>&1 || exit_code_1=$?
    echo "$input" | python3 "$HOOK_CATASTROPHIC" >/dev/null 2>&1 || exit_code_2=$?

    if [ $exit_code_1 -eq 0 ] && [ $exit_code_2 -eq 0 ]; then
        log_pass "Safe command passes both hooks in sequence"
    else
        log_fail "Command should pass both hooks (git: $exit_code_1, catastrophic: $exit_code_2)"
    fi
}

test_catastrophic_blocked_even_if_git_passes() {
    echo ""
    echo "--- Test: Catastrophic Blocked Even If Git Passes ---"

    # rm -rf / is not a git command, so block-dangerous-git allows it
    # but block-catastrophic-commands should block it
    local input='{"tool_input":{"command":"rm -rf /"}}'
    local exit_code_git=0
    local exit_code_cat=0

    echo "$input" | python3 "$HOOK_DANGEROUS_GIT" >/dev/null 2>&1 || exit_code_git=$?
    echo "$input" | python3 "$HOOK_CATASTROPHIC" >/dev/null 2>&1 || exit_code_cat=$?

    if [ $exit_code_git -eq 0 ] && [ $exit_code_cat -eq 2 ]; then
        log_pass "Git hook allows, catastrophic hook blocks (correct chain behavior)"
    else
        log_fail "Expected git allow (0) and catastrophic block (2), got git=$exit_code_git, cat=$exit_code_cat"
    fi
}

# =============================================================================
# Main Test Runner
# =============================================================================

main() {
    echo "====================================="
    echo "Integration Tests: Catastrophic Filter"
    echo "====================================="

    # Verify hooks exist
    if [ ! -f "$HOOK_CATASTROPHIC" ]; then
        echo "ERROR: block-catastrophic-commands.py not found at $HOOK_CATASTROPHIC"
        exit 1
    fi

    # Run integration tests
    test_integration_blocks_root_deletion
    test_integration_blocks_disk_wipe
    test_integration_allows_safe_command
    test_hook_chain_dangerous_git_blocked
    test_hook_chain_safe_git_allowed
    test_multiple_hooks_in_sequence
    test_catastrophic_blocked_even_if_git_passes

    # Summary
    echo ""
    echo "====================================="
    echo "Integration Test Summary"
    echo "====================================="
    echo "Tests: $TESTS_RUN | Passed: $TESTS_PASSED | Failed: $TESTS_FAILED"
    echo ""

    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "${RED}RESULT: FAILED${NC}"
        exit 1
    else
        echo -e "${GREEN}RESULT: PASSED${NC}"
        echo ""
        echo "All integration tests passed - hook chain verified"
        exit 0
    fi
}

main "$@"
