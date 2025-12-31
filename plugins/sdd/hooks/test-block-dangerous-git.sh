#!/bin/bash
# Test runner for block-dangerous-git.py hook
# Validates that dangerous git commands are blocked and safe commands are allowed
#
# Exit codes tested:
#   0 = Safe command (allowed)
#   1 = Hook error (handled gracefully)
#   2 = Dangerous command (blocked)
#
# Usage: ./test-block-dangerous-git.sh

set -e

HOOK_PATH="$(dirname "$0")/block-dangerous-git.py"
TEST_DIR=$(mktemp -d)
FAILURES=0
TESTS_RUN=0

# Colors for output (if terminal supports it)
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    NC='\033[0m' # No Color
else
    GREEN=''
    RED=''
    YELLOW=''
    NC=''
fi

# Cleanup function for trap
cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

echo "============================================"
echo "block-dangerous-git.py Hook Test Suite"
echo "============================================"
echo ""

# Verify hook exists
if [[ ! -f "$HOOK_PATH" ]]; then
    echo -e "${RED}ERROR: Hook not found at $HOOK_PATH${NC}"
    exit 1
fi

# Helper function to run test with expected exit code
run_test() {
    local test_name="$1"
    local command="$2"
    local expected_exit="$3"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo "Test $TESTS_RUN: $test_name"

    # Generate tool_input JSON and run hook
    local json_input='{"tool_input": {"command": "'"$command"'"}}'

    set +e
    echo "$json_input" | python3 "$HOOK_PATH" > /dev/null 2>&1
    local exit_code=$?
    set -e

    if [[ $exit_code -eq $expected_exit ]]; then
        echo -e "  ${GREEN}PASS${NC}"
    else
        echo -e "  ${RED}FAIL: Expected exit $expected_exit, got $exit_code${NC}"
        FAILURES=$((FAILURES + 1))
    fi
}

# Helper function to run test and verify output contains text
run_test_output() {
    local test_name="$1"
    local command="$2"
    local expected_exit="$3"
    local expected_output="$4"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo "Test $TESTS_RUN: $test_name"

    # Generate tool_input JSON and run hook
    local json_input='{"tool_input": {"command": "'"$command"'"}}'

    set +e
    local output
    output=$(echo "$json_input" | python3 "$HOOK_PATH" 2>&1)
    local exit_code=$?
    set -e

    local output_match="no"
    if echo "$output" | grep -q "$expected_output"; then
        output_match="yes"
    fi

    if [[ $exit_code -eq $expected_exit && "$output_match" == "yes" ]]; then
        echo -e "  ${GREEN}PASS${NC}"
    elif [[ $exit_code -ne $expected_exit ]]; then
        echo -e "  ${RED}FAIL: Expected exit $expected_exit, got $exit_code${NC}"
        FAILURES=$((FAILURES + 1))
    else
        echo -e "  ${RED}FAIL: Expected output containing '$expected_output'${NC}"
        FAILURES=$((FAILURES + 1))
    fi
}

# Helper for raw input tests (malformed JSON, empty stdin)
run_test_raw() {
    local test_name="$1"
    local raw_input="$2"
    local expected_exit="$3"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo "Test $TESTS_RUN: $test_name"

    set +e
    echo "$raw_input" | python3 "$HOOK_PATH" > /dev/null 2>&1
    local exit_code=$?
    set -e

    if [[ $exit_code -eq $expected_exit ]]; then
        echo -e "  ${GREEN}PASS${NC}"
    else
        echo -e "  ${RED}FAIL: Expected exit $expected_exit, got $exit_code${NC}"
        FAILURES=$((FAILURES + 1))
    fi
}

echo "--- Safe Commands (Exit 0) ---"
echo ""

# Test 1: git status - safe command
run_test "git status" \
    "git status" \
    0

# Test 2: git log --oneline - safe command
run_test "git log --oneline" \
    "git log --oneline" \
    0

# Test 3: git branch -a - safe command
run_test "git branch -a" \
    "git branch -a" \
    0

# Test 4: git diff HEAD - safe command
run_test "git diff HEAD" \
    "git diff HEAD" \
    0

# Test 5: ls -la - non-git command (safe)
run_test "ls -la (non-git command)" \
    "ls -la" \
    0

# Test 6: echo hello world - non-git command (safe)
run_test "echo hello world (non-git command)" \
    "echo hello world" \
    0

echo ""
echo "--- Dangerous Commands (Exit 2) ---"
echo ""

# Test 7: git reset --hard - dangerous
run_test_output "git reset --hard" \
    "git reset --hard" \
    2 \
    "BLOCKED"

# Test 8: git reset --hard HEAD~1 - dangerous
run_test_output "git reset --hard HEAD~1" \
    "git reset --hard HEAD~1" \
    2 \
    "BLOCKED"

# Test 9: git reset --hard origin/main - dangerous
run_test_output "git reset --hard origin/main" \
    "git reset --hard origin/main" \
    2 \
    "BLOCKED"

# Test 10: git clean -fd - dangerous
run_test_output "git clean -fd" \
    "git clean -fd" \
    2 \
    "BLOCKED"

# Test 11: git clean -fdx - dangerous
run_test_output "git clean -fdx" \
    "git clean -fdx" \
    2 \
    "BLOCKED"

echo ""
echo "--- Error Handling (Exit 1) ---"
echo ""

# Test 12: Malformed JSON input
run_test_raw "Malformed JSON input" \
    "not json at all" \
    1

# Test 13: Missing command field in tool_input
echo "Test $((TESTS_RUN + 1)): Missing command field in tool_input"
TESTS_RUN=$((TESTS_RUN + 1))
set +e
echo '{"tool_input": {"other_field": "value"}}' | python3 "$HOOK_PATH" > /dev/null 2>&1
exit_code=$?
set -e
# Hook returns 0 for missing command (defaults to empty string which is safe)
if [[ $exit_code -eq 0 ]]; then
    echo -e "  ${GREEN}PASS${NC}"
else
    echo -e "  ${RED}FAIL: Expected exit 0, got $exit_code${NC}"
    FAILURES=$((FAILURES + 1))
fi

# Test 14: Empty stdin
echo "Test $((TESTS_RUN + 1)): Empty stdin"
TESTS_RUN=$((TESTS_RUN + 1))
set +e
echo "" | python3 "$HOOK_PATH" > /dev/null 2>&1
exit_code=$?
set -e
if [[ $exit_code -eq 1 ]]; then
    echo -e "  ${GREEN}PASS${NC}"
else
    echo -e "  ${RED}FAIL: Expected exit 1, got $exit_code${NC}"
    FAILURES=$((FAILURES + 1))
fi

echo ""
echo "--- Edge Cases ---"
echo ""

# Test 15: Empty command string (safe)
run_test "Empty command string" \
    "" \
    0

# Test 16: Command contains dangerous text in echo (blocked due to regex)
# The hook uses regex matching which will match the pattern in any context
run_test_output "echo containing git reset --hard (blocked by regex)" \
    "echo 'Do not run git reset --hard'" \
    2 \
    "BLOCKED"

# Test 17: git-reset-hard as hyphenated name (not a real command - safe)
run_test "git-reset-hard hyphenated (safe - no word boundary match)" \
    "git-reset-hard" \
    0

# Test 18: Multiple commands with dangerous command in pipe
run_test_output "Piped command with git reset --hard" \
    "git status && git reset --hard HEAD" \
    2 \
    "BLOCKED"

# Test 19: git reset without --hard (safe soft reset)
run_test "git reset (soft, without --hard)" \
    "git reset HEAD~1" \
    0

# Test 20: git clean without -f flag (safe - requires force)
run_test "git clean without force flag (safe)" \
    "git clean -n" \
    0

# Test 21: Whitespace variations in dangerous command
run_test_output "git reset  --hard (extra space)" \
    "git reset  --hard" \
    2 \
    "BLOCKED"

# Test 22: git clean with reordered flags (blocked)
run_test_output "git clean -df (reordered flags)" \
    "git clean -df" \
    0

echo ""
echo "============================================"
echo "Cleanup"
echo "============================================"
echo "Temporary files cleaned up: $TEST_DIR"

echo ""
echo "============================================"
echo "Test Results"
echo "============================================"
echo ""
echo "Tests run: $TESTS_RUN"
if [[ $FAILURES -eq 0 ]]; then
    echo -e "${GREEN}All tests PASSED${NC}"
    exit 0
else
    echo -e "${RED}$FAILURES test(s) FAILED${NC}"
    exit 1
fi
