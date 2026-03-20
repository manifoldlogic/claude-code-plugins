#!/usr/bin/env bash
#
# test-cmux-wait.sh - Unit tests for cmux-wait.sh polling functions
#
# DESCRIPTION:
#   Exercises cmux_wait_workspace and cmux_wait_prompt using mock cmux-ssh.sh
#   scripts in temp directories. Covers success paths, timeout paths, prompt
#   pattern variants, verbose logging, transient failure recovery, invalid
#   arguments, and login-banner false-positive prevention.
#
# USAGE:
#   bash test-cmux-wait.sh
#
# EXIT CODES:
#   0 - All tests passed
#   1 - One or more tests failed

set -euo pipefail

##############################################################################
# Test Configuration
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMUX_WAIT_SCRIPT="$SCRIPT_DIR/cmux-wait.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Temp directory for mocks (created in setup, removed in teardown)
TEST_TMPDIR=""

##############################################################################
# Test Utilities
##############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

run_test() {
    local test_name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    echo ""
    echo -e "${YELLOW}Test $TESTS_RUN: $test_name${NC}"
    echo "----------------------------------------"
}

##############################################################################
# Setup / Teardown
##############################################################################

setup() {
    TEST_TMPDIR="$(mktemp -d)"

    # Reset env vars to defaults before each test suite run
    unset CMUX_WAIT_WS_TIMEOUT CMUX_WAIT_WS_INTERVAL
    unset CMUX_WAIT_PROMPT_TIMEOUT CMUX_WAIT_PROMPT_INTERVAL
    unset CMUX_PROMPT_PATTERN CMUX_READ_SCREEN_LINES VERBOSE
}

teardown() {
    if [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# Ensure teardown runs even on failure
trap teardown EXIT

##############################################################################
# Mock Helpers
##############################################################################

# Create a mock cmux-ssh.sh that echoes fixed output for list-workspaces
# Args: $1 = output to return
create_mock_list_workspaces() {
    local output="$1"
    local mock_script="$TEST_TMPDIR/cmux-ssh.sh"
    cat > "$mock_script" <<MOCKEOF
#!/usr/bin/env bash
if [ "\$1" = "list-workspaces" ]; then
    echo "$output"
fi
MOCKEOF
    chmod +x "$mock_script"
    echo "$mock_script"
}

# Create a mock cmux-ssh.sh that echoes fixed output for read-screen
# Args: $1 = output to return
create_mock_read_screen() {
    local output="$1"
    local mock_script="$TEST_TMPDIR/cmux-ssh.sh"
    cat > "$mock_script" <<MOCKEOF
#!/usr/bin/env bash
if [ "\$1" = "read-screen" ]; then
    cat <<'SCREENEOF'
$output
SCREENEOF
fi
MOCKEOF
    chmod +x "$mock_script"
    echo "$mock_script"
}

# Create a mock using a counter file for delayed responses
# Args: $1 = threshold (succeed after N calls), $2 = success output, $3 = subcommand
create_mock_counter() {
    local threshold="$1"
    local success_output="$2"
    local subcommand="$3"
    local counter_file="$TEST_TMPDIR/counter"
    echo "0" > "$counter_file"
    local mock_script="$TEST_TMPDIR/cmux-ssh.sh"
    cat > "$mock_script" <<MOCKEOF
#!/usr/bin/env bash
COUNTER_FILE="$counter_file"
COUNT=\$(cat "\$COUNTER_FILE")
COUNT=\$((COUNT + 1))
echo "\$COUNT" > "\$COUNTER_FILE"
if [ "\$1" = "$subcommand" ] && [ "\$COUNT" -ge $threshold ]; then
    echo "$success_output"
fi
MOCKEOF
    chmod +x "$mock_script"
    echo "$mock_script"
}

# Create a mock that fails on first call, succeeds on second
# Args: $1 = success output, $2 = subcommand
create_mock_transient_failure() {
    local success_output="$1"
    local subcommand="$2"
    local counter_file="$TEST_TMPDIR/counter"
    echo "0" > "$counter_file"
    local mock_script="$TEST_TMPDIR/cmux-ssh.sh"
    cat > "$mock_script" <<MOCKEOF
#!/usr/bin/env bash
COUNTER_FILE="$counter_file"
COUNT=\$(cat "\$COUNTER_FILE")
COUNT=\$((COUNT + 1))
echo "\$COUNT" > "\$COUNTER_FILE"
if [ "\$COUNT" -eq 1 ]; then
    exit 1
fi
if [ "\$1" = "$subcommand" ]; then
    echo "$success_output"
fi
MOCKEOF
    chmod +x "$mock_script"
    echo "$mock_script"
}

##############################################################################
# Source the module under test (in a subshell-safe way)
##############################################################################

# We source cmux-wait.sh in each test subshell so env vars can be set per-test.
# Helper to run a test body that sources cmux-wait.sh with given env vars.
run_with_env() {
    # All positional args are the env assignments, last arg is the function body
    bash -c "
        # Source the module under test
        source '$CMUX_WAIT_SCRIPT'
        $*
    "
}

##############################################################################
# Tests
##############################################################################

test_1_workspace_immediate_success() {
    run_test "cmux_wait_workspace returns 0 on immediate match"

    local mock_script
    mock_script=$(create_mock_list_workspaces "workspace:3 myproject")

    if run_with_env "
        export CMUX_WAIT_WS_TIMEOUT=2
        export CMUX_WAIT_WS_INTERVAL=0.1
        cmux_wait_workspace 'workspace:3' '$mock_script'
    "; then
        pass "cmux_wait_workspace returned 0 for immediate workspace match"
    else
        fail "cmux_wait_workspace returned non-zero for immediate workspace match"
    fi
}

test_2_workspace_delayed_success() {
    run_test "cmux_wait_workspace returns 0 after delayed match"

    local mock_script
    mock_script=$(create_mock_counter 3 "workspace:5 myproject" "list-workspaces")

    if run_with_env "
        export CMUX_WAIT_WS_TIMEOUT=5
        export CMUX_WAIT_WS_INTERVAL=0.1
        cmux_wait_workspace 'workspace:5' '$mock_script'
    "; then
        pass "cmux_wait_workspace returned 0 after polling"
    else
        fail "cmux_wait_workspace did not return 0 after delayed match"
    fi
}

test_3_workspace_timeout() {
    run_test "cmux_wait_workspace returns non-zero after timeout"

    local mock_script
    mock_script=$(create_mock_list_workspaces "workspace:99 other")

    if run_with_env "
        export CMUX_WAIT_WS_TIMEOUT=1
        export CMUX_WAIT_WS_INTERVAL=0.1
        cmux_wait_workspace 'workspace:1' '$mock_script'
    " 2>/dev/null; then
        fail "cmux_wait_workspace returned 0 but should have timed out"
    else
        pass "cmux_wait_workspace returned non-zero after timeout"
    fi
}

test_4_prompt_bash_style() {
    run_test "cmux_wait_prompt returns 0 for bash-style prompt (\$ )"

    local mock_script
    mock_script=$(create_mock_read_screen 'user@host:~/project$ ')

    if run_with_env "
        export CMUX_WAIT_PROMPT_TIMEOUT=2
        export CMUX_WAIT_PROMPT_INTERVAL=0.1
        cmux_wait_prompt 'workspace:1' '$mock_script'
    "; then
        pass "cmux_wait_prompt matched bash-style prompt"
    else
        fail "cmux_wait_prompt did not match bash-style prompt"
    fi
}

test_5_prompt_root_and_zsh() {
    run_test "cmux_wait_prompt returns 0 for root (#) and zsh (%) prompts"

    # Test root prompt
    local mock_root
    mock_root=$(create_mock_read_screen 'root@host:/# ')

    if run_with_env "
        export CMUX_WAIT_PROMPT_TIMEOUT=2
        export CMUX_WAIT_PROMPT_INTERVAL=0.1
        cmux_wait_prompt 'workspace:1' '$mock_root'
    "; then
        pass "cmux_wait_prompt matched root-style prompt (# )"
    else
        fail "cmux_wait_prompt did not match root-style prompt"
    fi

    # Test zsh prompt - need a new mock script (different tmpdir entry)
    local saved_tmpdir="$TEST_TMPDIR"
    TEST_TMPDIR="$(mktemp -d)"
    local mock_zsh
    mock_zsh=$(create_mock_read_screen 'user@host% ')

    if run_with_env "
        export CMUX_WAIT_PROMPT_TIMEOUT=2
        export CMUX_WAIT_PROMPT_INTERVAL=0.1
        cmux_wait_prompt 'workspace:1' '$mock_zsh'
    "; then
        pass "cmux_wait_prompt matched zsh-style prompt (% )"
    else
        fail "cmux_wait_prompt did not match zsh-style prompt"
    fi

    # Clean up extra tmpdir
    rm -rf "$TEST_TMPDIR"
    TEST_TMPDIR="$saved_tmpdir"
}

test_6_prompt_timeout() {
    run_test "cmux_wait_prompt returns non-zero after timeout"

    local mock_script
    mock_script=$(create_mock_read_screen 'Loading system services...')

    if run_with_env "
        export CMUX_WAIT_PROMPT_TIMEOUT=1
        export CMUX_WAIT_PROMPT_INTERVAL=0.1
        cmux_wait_prompt 'workspace:1' '$mock_script'
    " 2>/dev/null; then
        fail "cmux_wait_prompt returned 0 but should have timed out"
    else
        pass "cmux_wait_prompt returned non-zero after timeout"
    fi
}

test_7_custom_prompt_pattern() {
    run_test "cmux_wait_prompt returns 0 with custom CMUX_PROMPT_PATTERN"

    local mock_script
    mock_script=$(create_mock_read_screen 'myhost >>> ')

    if run_with_env "
        export CMUX_WAIT_PROMPT_TIMEOUT=2
        export CMUX_WAIT_PROMPT_INTERVAL=0.1
        export CMUX_PROMPT_PATTERN='>>> *$'
        cmux_wait_prompt 'workspace:1' '$mock_script'
    "; then
        pass "cmux_wait_prompt matched custom prompt pattern"
    else
        fail "cmux_wait_prompt did not match custom prompt pattern"
    fi
}

test_8_transient_ssh_failure() {
    run_test "Transient SSH failure - recovers on second call"

    local mock_script
    mock_script=$(create_mock_transient_failure "workspace:7 myproject" "list-workspaces")

    if run_with_env "
        export CMUX_WAIT_WS_TIMEOUT=5
        export CMUX_WAIT_WS_INTERVAL=0.1
        cmux_wait_workspace 'workspace:7' '$mock_script'
    "; then
        pass "cmux_wait_workspace recovered after transient SSH failure"
    else
        fail "cmux_wait_workspace did not recover after transient SSH failure"
    fi
}

test_9_invalid_arguments() {
    run_test "Invalid arguments return non-zero with error on stderr"

    # Empty workspace ID
    local stderr_output
    stderr_output=$(run_with_env "
        cmux_wait_workspace '' '/some/path'
    " 2>&1 >/dev/null) || true

    if echo "$stderr_output" | grep -q "ERROR"; then
        pass "Empty workspace_id produces error on stderr"
    else
        fail "Empty workspace_id did not produce error on stderr"
    fi

    # Empty script path
    stderr_output=$(run_with_env "
        cmux_wait_workspace 'workspace:1' ''
    " 2>&1 >/dev/null) || true

    if echo "$stderr_output" | grep -q "ERROR"; then
        pass "Empty cmux_ssh_script produces error on stderr"
    else
        fail "Empty cmux_ssh_script did not produce error on stderr"
    fi

    # Verify non-zero exit
    if run_with_env "cmux_wait_workspace '' '/some/path'" 2>/dev/null; then
        fail "Empty workspace_id should return non-zero"
    else
        pass "Empty workspace_id returns non-zero exit code"
    fi
}

test_10_verbose_output() {
    run_test "VERBOSE=true emits polling attempt messages"

    local mock_script
    mock_script=$(create_mock_counter 2 "workspace:10 myproject" "list-workspaces")

    local all_output
    all_output=$(run_with_env "
        export CMUX_WAIT_WS_TIMEOUT=5
        export CMUX_WAIT_WS_INTERVAL=0.1
        export VERBOSE=true
        cmux_wait_workspace 'workspace:10' '$mock_script'
    " 2>&1)

    if echo "$all_output" | grep -q "Polling.*attempt"; then
        pass "VERBOSE=true produces polling attempt messages"
    else
        fail "VERBOSE=true did not produce polling attempt messages"
    fi

    # Verify multiple attempts were logged
    local attempt_count
    attempt_count=$(echo "$all_output" | grep -c "Polling.*attempt" || true)
    if [ "$attempt_count" -ge 2 ]; then
        pass "Multiple polling attempts logged ($attempt_count attempts)"
    else
        fail "Expected at least 2 polling attempts, got $attempt_count"
    fi
}

test_11_login_banner_false_positive() {
    run_test "Login banner false-positive guard (MOTD does not match prompt)"

    local banner_text='##############################################
# Welcome to the devcontainer
# This is a shared development environment
##############################################'

    local mock_script
    mock_script=$(create_mock_read_screen "$banner_text")

    if run_with_env "
        export CMUX_WAIT_PROMPT_TIMEOUT=1
        export CMUX_WAIT_PROMPT_INTERVAL=0.1
        cmux_wait_prompt 'workspace:1' '$mock_script'
    " 2>/dev/null; then
        fail "cmux_wait_prompt incorrectly matched login banner as prompt"
    else
        pass "cmux_wait_prompt correctly rejected login banner (no false positive)"
    fi
}

test_12_cmux_wait_prompt_invalid_arguments() {
    run_test "cmux_wait_prompt invalid arguments return non-zero with error on stderr"

    # Empty workspace ID
    local stderr_output
    stderr_output=$(run_with_env "
        cmux_wait_prompt '' '/some/path'
    " 2>&1 >/dev/null) || true

    if echo "$stderr_output" | grep -q "ERROR"; then
        pass "cmux_wait_prompt: empty workspace_id produces error on stderr"
    else
        fail "cmux_wait_prompt: empty workspace_id did not produce error on stderr"
    fi

    # Verify non-zero exit for empty workspace_id
    if run_with_env "cmux_wait_prompt '' '/some/path'" 2>/dev/null; then
        fail "cmux_wait_prompt: empty workspace_id should return non-zero"
    else
        pass "cmux_wait_prompt: empty workspace_id returns non-zero exit code"
    fi

    # Empty script path
    stderr_output=$(run_with_env "
        cmux_wait_prompt 'workspace:1' ''
    " 2>&1 >/dev/null) || true

    if echo "$stderr_output" | grep -q "ERROR"; then
        pass "cmux_wait_prompt: empty cmux_ssh_script produces error on stderr"
    else
        fail "cmux_wait_prompt: empty cmux_ssh_script did not produce error on stderr"
    fi

    # Verify non-zero exit for empty script path
    if run_with_env "cmux_wait_prompt 'workspace:1' ''" 2>/dev/null; then
        fail "cmux_wait_prompt: empty cmux_ssh_script should return non-zero"
    else
        pass "cmux_wait_prompt: empty cmux_ssh_script returns non-zero exit code"
    fi
}

test_edge_substring_workspace() {
    run_test "Edge case: workspace:3 does not match workspace:33"

    local mock_script
    mock_script=$(create_mock_list_workspaces "workspace:33 other")

    # The implementation uses grep -qF "${workspace_id} " (with trailing space)
    # to prevent substring false positives. workspace:33 does not contain
    # "workspace:3 " so this should correctly NOT match.
    if run_with_env "
        export CMUX_WAIT_WS_TIMEOUT=1
        export CMUX_WAIT_WS_INTERVAL=0.1
        cmux_wait_workspace 'workspace:3' '$mock_script'
    " 2>/dev/null; then
        fail "workspace:3 incorrectly matched workspace:33 (substring false positive)"
    else
        pass "workspace:3 correctly did NOT match workspace:33"
    fi
}

##############################################################################
# Test Runner
##############################################################################

run_all_tests() {
    echo ""
    echo "=========================================="
    echo "  cmux-wait.sh Unit Tests"
    echo "=========================================="
    echo ""
    echo "Script under test: $CMUX_WAIT_SCRIPT"
    echo ""

    setup

    test_1_workspace_immediate_success
    test_2_workspace_delayed_success
    test_3_workspace_timeout
    test_4_prompt_bash_style
    test_5_prompt_root_and_zsh
    test_6_prompt_timeout
    test_7_custom_prompt_pattern
    test_8_transient_ssh_failure
    test_9_invalid_arguments
    test_10_verbose_output
    test_11_login_banner_false_positive
    test_12_cmux_wait_prompt_invalid_arguments
    test_edge_substring_workspace

    # Summary
    echo ""
    echo "=========================================="
    echo "  Test Summary"
    echo "=========================================="
    echo ""
    echo "Tests run:    $TESTS_RUN"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo ""

    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}$TESTS_FAILED test(s) failed${NC}"
        return 1
    fi
}

run_all_tests
