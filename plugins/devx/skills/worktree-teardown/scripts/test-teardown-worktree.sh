#!/usr/bin/env bash
#
# test-teardown-worktree.sh - Tests for teardown-worktree.sh worktree teardown script
#
# DESCRIPTION:
#   Comprehensive test suite for teardown-worktree.sh covering:
#   - Argument parsing (valid, invalid, missing, unknown flags)
#   - Help flag output
#   - Invalid name validation
#   - Dry-run output (all step headers, skip annotations)
#   - Dry-run flag passthrough
#   - Flag passthrough (live execution with mock)
#   - Verbose forwarding
#   - cmux workspace matching (match, no-match, multiple-match)
#   - cmux failure modes (list-workspaces, close-workspace)
#   - Cleanup exit code passthrough
#   - Graceful degradation (skip-cmux, missing cmux dir)
#   - Exit codes (all documented codes 0-5)
#
# USAGE:
#   bash test-teardown-worktree.sh           # Run all tests
#   bash test-teardown-worktree.sh --verbose # Verbose output
#   bash test-teardown-worktree.sh --help    # Show help
#
# EXIT CODES:
#   0 - All tests passed
#   1 - One or more tests failed

set -uo pipefail

##############################################################################
# Script Location
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_UNDER_TEST="$SCRIPT_DIR/teardown-worktree.sh"

##############################################################################
# Test Framework Variables
##############################################################################

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
VERBOSE=false
TEST_TMP=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

##############################################################################
# CLI Argument Parsing
##############################################################################

while [ $# -gt 0 ]; do
    case "$1" in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            printf "Usage: %s [-v|--verbose] [--help]\n" "$0"
            printf "\nOptions:\n"
            printf "  -v, --verbose  Show detailed output for each test\n"
            printf "  --help         Show this help message\n"
            exit 0
            ;;
        *)
            printf "Unknown option: %s\n" "$1"
            exit 1
            ;;
    esac
done

##############################################################################
# Test Framework Functions
##############################################################################

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "  ${GREEN}[PASS]${NC} %s\n" "$1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "  ${RED}[FAIL]${NC} %s\n" "$1"
    if [ -n "${2:-}" ]; then
        printf "         ${YELLOW}Reason:${NC} %s\n" "$2"
    fi
}

section() {
    printf "\n=== %s ===\n" "$1"
}

debug_msg() {
    if [ "$VERBOSE" = "true" ]; then
        printf "  ${BLUE}[DEBUG]${NC} %s\n" "$*"
    fi
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local msg="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$expected" = "$actual" ]; then
        pass "$msg"
    else
        fail "$msg" "expected '$expected', got '$actual'"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
        pass "$msg"
    else
        fail "$msg" "output does not contain '$needle'"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
        fail "$msg" "output unexpectedly contains '$needle'"
    else
        pass "$msg"
    fi
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local msg="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$expected" = "$actual" ]; then
        pass "$msg"
    else
        fail "$msg" "expected exit code $expected, got $actual"
    fi
}

##############################################################################
# Setup / Teardown
##############################################################################

setup() {
    TEST_TMP=$(mktemp -d)
    debug_msg "Created temp directory: $TEST_TMP"

    # Create mock cmux plugin directory with passing cmux-check.sh
    mkdir -p "$TEST_TMP/mock-cmux/skills/terminal-management/scripts"

    # Default workspace list for mock cmux-ssh.sh
    printf 'workspace:0 default\nworkspace:1 TICKET-1\nworkspace:2 other-worktree\n' \
        > "$TEST_TMP/default-workspace-list"

    cat > "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-ssh.sh" << 'MOCKEOF'
#!/bin/bash
# Mock cmux-ssh.sh for teardown tests
# - list-workspaces: returns MOCK_WORKSPACE_LIST or default list
# - close-workspace: records call, returns MOCK_CLOSE_EXIT (default 0)
case "$1" in
    list-workspaces)
        if [ -n "${MOCK_WORKSPACE_LIST:-}" ]; then
            printf '%s\n' "$MOCK_WORKSPACE_LIST"
        elif [ -f "${MOCK_WORKSPACE_LIST_FILE:-/dev/null}" ]; then
            cat "$MOCK_WORKSPACE_LIST_FILE"
        else
            printf 'workspace:0 default\nworkspace:1 TICKET-1\nworkspace:2 other-worktree\n'
        fi
        exit "${MOCK_LIST_EXIT:-0}"
        ;;
    close-workspace)
        # Record the call with all arguments
        echo "$@" >> "${MOCK_CMUX_CALL_LOG:-/dev/null}"
        exit "${MOCK_CLOSE_EXIT:-0}"
        ;;
    *)
        echo "unknown command: $1" >&2
        exit 1
        ;;
esac
MOCKEOF
    chmod +x "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-ssh.sh"

    cat > "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-check.sh" << 'MOCKEOF'
#!/bin/bash
exit 0
MOCKEOF
    chmod +x "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-check.sh"

    # Create mock cleanup-worktree.sh
    cat > "$TEST_TMP/mock-cleanup-worktree.sh" << 'MOCKEOF'
#!/bin/bash
# Mock cleanup-worktree.sh for teardown tests
# - Captures all received arguments to MOCK_CLEANUP_ARGS_FILE
# - Returns MOCK_CLEANUP_EXIT (default 0)
echo "$@" > "${MOCK_CLEANUP_ARGS_FILE:-/dev/null}"
exit "${MOCK_CLEANUP_EXIT:-0}"
MOCKEOF
    chmod +x "$TEST_TMP/mock-cleanup-worktree.sh"

    # Create shared state files
    echo "" > "$TEST_TMP/cleanup-args"
    echo "" > "$TEST_TMP/cmux-close-log"
}

# Run teardown-worktree.sh as a subprocess with mocked environment
# Usage: run_script [args...]
# Sets: LAST_EXIT, LAST_OUTPUT
run_script() {
    LAST_EXIT=0
    LAST_OUTPUT=$(
        CMUX_PLUGIN_DIR="$TEST_TMP/mock-cmux" \
        CLEANUP_WORKTREE_SCRIPT="$TEST_TMP/mock-cleanup-worktree.sh" \
        MOCK_CLEANUP_ARGS_FILE="$TEST_TMP/cleanup-args" \
        MOCK_CMUX_CALL_LOG="$TEST_TMP/cmux-close-log" \
        bash "$SCRIPT_UNDER_TEST" "$@" 2>&1
    ) || LAST_EXIT=$?
    debug_msg "run_script exit=$LAST_EXIT args='$*'"
    if [ "$VERBOSE" = "true" ]; then
        debug_msg "output: $(printf '%s' "$LAST_OUTPUT" | head -20)"
    fi
}

# Run script with custom env var overrides
# Usage: run_script_env "VAR1=val1" "VAR2=val2" -- [script args...]
# Sets: LAST_EXIT, LAST_OUTPUT
run_script_env() {
    local env_vars=""
    local args_started=false

    # Collect env var assignments and script args
    local env_assignments=""
    local script_args=""
    for arg in "$@"; do
        if [ "$arg" = "--" ]; then
            args_started=true
            continue
        fi
        if [ "$args_started" = true ]; then
            script_args="$script_args $arg"
        else
            env_assignments="$env_assignments $arg"
        fi
    done

    LAST_EXIT=0
    LAST_OUTPUT=$(
        eval "$env_assignments" \
        CMUX_PLUGIN_DIR="$TEST_TMP/mock-cmux" \
        CLEANUP_WORKTREE_SCRIPT="$TEST_TMP/mock-cleanup-worktree.sh" \
        MOCK_CLEANUP_ARGS_FILE="$TEST_TMP/cleanup-args" \
        MOCK_CMUX_CALL_LOG="$TEST_TMP/cmux-close-log" \
        bash "$SCRIPT_UNDER_TEST" $script_args 2>&1
    ) || LAST_EXIT=$?
    debug_msg "run_script_env exit=$LAST_EXIT"
    if [ "$VERBOSE" = "true" ]; then
        debug_msg "output: $(printf '%s' "$LAST_OUTPUT" | head -20)"
    fi
}

# Reset mock state between tests
reset_mocks() {
    echo "" > "$TEST_TMP/cleanup-args"
    echo "" > "$TEST_TMP/cmux-close-log"

    # Reset cmux-check.sh to passing
    cat > "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-check.sh" << 'MOCKEOF'
#!/bin/bash
exit 0
MOCKEOF
    chmod +x "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-check.sh"

    # Reset cmux-ssh.sh to default behavior
    cat > "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-ssh.sh" << 'MOCKEOF'
#!/bin/bash
case "$1" in
    list-workspaces)
        if [ -n "${MOCK_WORKSPACE_LIST:-}" ]; then
            printf '%s\n' "$MOCK_WORKSPACE_LIST"
        elif [ -f "${MOCK_WORKSPACE_LIST_FILE:-/dev/null}" ]; then
            cat "$MOCK_WORKSPACE_LIST_FILE"
        else
            printf 'workspace:0 default\nworkspace:1 TICKET-1\nworkspace:2 other-worktree\n'
        fi
        exit "${MOCK_LIST_EXIT:-0}"
        ;;
    close-workspace)
        echo "$@" >> "${MOCK_CMUX_CALL_LOG:-/dev/null}"
        exit "${MOCK_CLOSE_EXIT:-0}"
        ;;
    *)
        echo "unknown command: $1" >&2
        exit 1
        ;;
esac
MOCKEOF
    chmod +x "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-ssh.sh"
}

##############################################################################
# Category 1: Script Prerequisites
##############################################################################

run_prerequisite_tests() {
    section "1. Script Prerequisites"

    # Test: teardown-worktree.sh exists
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -f "$SCRIPT_UNDER_TEST" ]; then
        pass "teardown-worktree.sh exists"
    else
        fail "teardown-worktree.sh exists" "file not found at $SCRIPT_UNDER_TEST"
        return
    fi

    # Test: teardown-worktree.sh has valid syntax
    TESTS_RUN=$((TESTS_RUN + 1))
    if bash -n "$SCRIPT_UNDER_TEST" 2>/dev/null; then
        pass "teardown-worktree.sh has valid syntax"
    else
        fail "teardown-worktree.sh has valid syntax" "bash -n failed"
    fi
}

##############################################################################
# Category 2: Help Flag Tests
##############################################################################

run_help_tests() {
    section "2. Help Flag Tests"

    local exit_code=0
    local output

    # Test: --help produces output and exits 0
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" --help 2>&1) || exit_code=$?
    assert_exit_code "0" "$exit_code" "--help exits 0"
    assert_contains "$output" "Usage:" "--help shows Usage line"
    assert_contains "$output" "teardown-worktree.sh" "--help mentions script name"
    assert_contains "$output" "OPTIONS:" "--help shows OPTIONS section"
    assert_contains "$output" "EXIT CODES:" "--help shows EXIT CODES section"
    assert_contains "$output" "EXAMPLES:" "--help shows EXAMPLES section"

    # Test: -h also works
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" -h 2>&1) || exit_code=$?
    assert_exit_code "0" "$exit_code" "-h exits 0"
    assert_contains "$output" "Usage:" "-h shows Usage line"
}

##############################################################################
# Category 3: Argument Parsing Tests
##############################################################################

run_argument_parsing_tests() {
    section "3. Argument Parsing Tests"

    local exit_code=0
    local output

    # Test: missing worktree name exits 1
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" --repo testrepo 2>&1) || exit_code=$?
    assert_exit_code "1" "$exit_code" "missing worktree name exits 1"
    assert_contains "$output" "worktree name is required" "missing worktree name shows error"

    # Test: missing --repo exits 1
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" TICKET-1 2>&1) || exit_code=$?
    assert_exit_code "1" "$exit_code" "missing --repo exits 1"
    assert_contains "$output" "--repo is required" "missing --repo shows error"

    # Test: --repo with missing value exits 1
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo 2>&1) || exit_code=$?
    assert_exit_code "1" "$exit_code" "--repo with missing value exits 1"
    assert_contains "$output" "--repo requires an argument" "--repo missing value shows error"

    # Test: unrecognized option exits 3
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo testrepo --nonsense 2>&1) || exit_code=$?
    assert_exit_code "3" "$exit_code" "--nonsense exits 3"
    assert_contains "$output" "Unrecognized option" "--nonsense shows unrecognized option error"

    # Test: no arguments at all exits 1
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" 2>&1) || exit_code=$?
    assert_exit_code "1" "$exit_code" "no arguments exits 1"

    # Test: duplicate positional argument exits 1
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" TICKET-1 TICKET-2 --repo testrepo 2>&1) || exit_code=$?
    assert_exit_code "1" "$exit_code" "duplicate positional arg exits 1"
    assert_contains "$output" "Unexpected positional argument" "duplicate positional shows error"
}

##############################################################################
# Category 4: Invalid Name Tests
##############################################################################

run_invalid_name_tests() {
    section "4. Invalid Name Tests"

    local exit_code=0
    local output

    # Test: name with slash exits 1
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" "feat/branch" --repo testrepo 2>&1) || exit_code=$?
    assert_exit_code "1" "$exit_code" "name with slash exits 1"
    assert_contains "$output" "Invalid worktree name" "slash name shows invalid name error"

    # Test: name with space exits 1
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" "ticket with spaces" --repo testrepo 2>&1) || exit_code=$?
    assert_exit_code "1" "$exit_code" "name with space exits 1"
    assert_contains "$output" "Invalid worktree name" "space name shows invalid name error"

    # Test: name with dot exits 1
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" "v1.0.0" --repo testrepo 2>&1) || exit_code=$?
    assert_exit_code "1" "$exit_code" "name with dot exits 1"
    assert_contains "$output" "Invalid worktree name" "dot name shows invalid name error"

    # Test: name starting with hyphen exits 3 (unrecognized option)
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" "-badname" --repo testrepo 2>&1) || exit_code=$?
    assert_exit_code "3" "$exit_code" "name starting with hyphen exits 3"
    assert_contains "$output" "Unrecognized option" "hyphen-prefixed name shows unrecognized option error"

    # Test: empty name (missing worktree name) exits 1
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" --repo testrepo 2>&1) || exit_code=$?
    assert_exit_code "1" "$exit_code" "empty name exits 1"

    # Test: --repo with slash exits 1
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo "foo/bar" 2>&1) || exit_code=$?
    assert_exit_code "1" "$exit_code" "--repo with slash exits 1"
    assert_contains "$output" "--repo value" "--repo slash shows invalid repo error"

    # Test: --repo with dot exits 1
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo "foo.bar" 2>&1) || exit_code=$?
    assert_exit_code "1" "$exit_code" "--repo with dot exits 1"
    assert_contains "$output" "--repo value" "--repo dot shows invalid repo error"

    # Test: --repo with space exits 1
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo "foo bar" 2>&1) || exit_code=$?
    assert_exit_code "1" "$exit_code" "--repo with space exits 1"
    assert_contains "$output" "--repo value" "--repo space shows invalid repo error"
}

##############################################################################
# Category 5: Dry-Run Output Tests
##############################################################################

run_dry_run_tests() {
    section "5. Dry-Run Output Tests"
    reset_mocks

    # Test: --dry-run exits 0 and shows DRY RUN header
    run_script TICKET-1 --repo crewchief --dry-run
    assert_exit_code "0" "$LAST_EXIT" "--dry-run exits 0"
    assert_contains "$LAST_OUTPUT" "=== DRY RUN: teardown-worktree ===" "--dry-run shows DRY RUN header"

    # Test: --dry-run shows resolved parameters
    assert_contains "$LAST_OUTPUT" "Worktree: TICKET-1" "--dry-run shows worktree name"
    assert_contains "$LAST_OUTPUT" "Repo:     crewchief" "--dry-run shows repository"

    # Test: --dry-run output contains all 4 exact step headers from architecture.md
    assert_contains "$LAST_OUTPUT" "Step 1: Validate prerequisites" "--dry-run contains Step 1 header"
    assert_contains "$LAST_OUTPUT" "Step 2: Identify cmux workspace" "--dry-run contains Step 2 header"
    assert_contains "$LAST_OUTPUT" "Step 3: Close cmux workspace" "--dry-run contains Step 3 header"
    assert_contains "$LAST_OUTPUT" "Step 4: Cleanup worktree (delegate to cleanup-worktree.sh)" "--dry-run contains Step 4 header"
}

##############################################################################
# Category 6: Dry-Run + Skip-Cmux Tests
##############################################################################

run_dry_run_skip_cmux_tests() {
    section "6. Dry-Run + Skip-Cmux Tests"
    reset_mocks

    # Test: --dry-run --skip-cmux shows SKIPPED annotations for steps 2 and 3
    run_script TICKET-1 --repo crewchief --dry-run --skip-cmux
    assert_exit_code "0" "$LAST_EXIT" "--dry-run --skip-cmux exits 0"
    assert_contains "$LAST_OUTPUT" "Step 2: Identify cmux workspace [SKIPPED: --skip-cmux]" "--skip-cmux step 2 shows SKIPPED annotation"
    assert_contains "$LAST_OUTPUT" "Step 3: Close cmux workspace [SKIPPED: --skip-cmux]" "--skip-cmux step 3 shows SKIPPED annotation"

    # Test: step 1 and step 4 are still present
    assert_contains "$LAST_OUTPUT" "Step 1: Validate prerequisites" "--skip-cmux still shows Step 1"
    assert_contains "$LAST_OUTPUT" "Step 4: Cleanup worktree" "--skip-cmux still shows Step 4"
}

##############################################################################
# Category 7: Dry-Run Flag Passthrough Tests
##############################################################################

run_dry_run_flag_passthrough_tests() {
    section "7. Dry-Run Flag Passthrough Tests"
    reset_mocks

    # Test: --dry-run --skip-workspace shows --skip-workspace in cleanup command
    run_script TICKET-1 --repo crewchief --dry-run --skip-workspace
    assert_exit_code "0" "$LAST_EXIT" "--dry-run --skip-workspace exits 0"
    assert_contains "$LAST_OUTPUT" "--skip-workspace" "--dry-run shows --skip-workspace in cleanup command"

    # Test: --dry-run --keep-branch shows --keep-branch in cleanup command
    run_script TICKET-1 --repo crewchief --dry-run --keep-branch
    assert_exit_code "0" "$LAST_EXIT" "--dry-run --keep-branch exits 0"
    assert_contains "$LAST_OUTPUT" "--keep-branch" "--dry-run shows --keep-branch in cleanup command"

    # Test: --dry-run --yes shows --yes in cleanup command
    run_script TICKET-1 --repo crewchief --dry-run --yes
    assert_exit_code "0" "$LAST_EXIT" "--dry-run --yes exits 0"
    assert_contains "$LAST_OUTPUT" "--yes" "--dry-run shows --yes in cleanup command"

    # Test: --dry-run --verbose shows --verbose in cleanup command
    run_script TICKET-1 --repo crewchief --dry-run --verbose
    assert_exit_code "0" "$LAST_EXIT" "--dry-run --verbose exits 0"
    assert_contains "$LAST_OUTPUT" "--verbose" "--dry-run shows --verbose in cleanup command"
    # Also shows dry-run step headers
    assert_contains "$LAST_OUTPUT" "Step 1: Validate prerequisites" "--dry-run --verbose still shows step headers"
}

##############################################################################
# Category 8: Flag Passthrough (Live Execution with Mock)
##############################################################################

run_flag_passthrough_tests() {
    section "8. Flag Passthrough (Live with Mock)"
    reset_mocks

    local captured_args

    # Test: --yes is passed to cleanup-worktree.sh
    run_script TICKET-1 --repo crewchief --yes
    captured_args=$(cat "$TEST_TMP/cleanup-args")
    assert_contains "$captured_args" "--yes" "--yes forwarded to cleanup-worktree.sh"

    # Test: --keep-branch is passed to cleanup-worktree.sh
    reset_mocks
    run_script TICKET-1 --repo crewchief --keep-branch
    captured_args=$(cat "$TEST_TMP/cleanup-args")
    assert_contains "$captured_args" "--keep-branch" "--keep-branch forwarded to cleanup-worktree.sh"

    # Test: --skip-workspace is passed to cleanup-worktree.sh
    reset_mocks
    run_script TICKET-1 --repo crewchief --skip-workspace
    captured_args=$(cat "$TEST_TMP/cleanup-args")
    assert_contains "$captured_args" "--skip-workspace" "--skip-workspace forwarded to cleanup-worktree.sh"

    # Test: worktree name and --repo are passed to cleanup-worktree.sh
    reset_mocks
    run_script TICKET-1 --repo crewchief
    captured_args=$(cat "$TEST_TMP/cleanup-args")
    assert_contains "$captured_args" "TICKET-1" "worktree name forwarded to cleanup-worktree.sh"
    assert_contains "$captured_args" "--repo crewchief" "--repo value forwarded to cleanup-worktree.sh"
}

##############################################################################
# Category 9: Verbose Forwarding Tests
##############################################################################

run_verbose_tests() {
    section "9. Verbose Forwarding Tests"
    reset_mocks

    local captured_args

    # Test: --verbose is forwarded to cleanup-worktree.sh
    run_script TICKET-1 --repo crewchief --verbose
    captured_args=$(cat "$TEST_TMP/cleanup-args")
    assert_contains "$captured_args" "--verbose" "--verbose forwarded to cleanup-worktree.sh"

    # Test: --verbose enables cmux logging in teardown-worktree.sh output
    assert_contains "$LAST_OUTPUT" "cmux-ssh.sh" "--verbose shows cmux-ssh.sh invocation in output"
}

##############################################################################
# Category 10: cmux Workspace Match Tests
##############################################################################

run_cmux_workspace_match_tests() {
    section "10. cmux Workspace Match Tests"
    reset_mocks

    # Test: mock returns workspace list with TICKET-1; correct workspace:N extracted
    # Default mock list has "workspace:1 TICKET-1"
    run_script TICKET-1 --repo crewchief
    assert_exit_code "0" "$LAST_EXIT" "cmux workspace match exits 0"
    assert_contains "$LAST_OUTPUT" "workspace:1" "found correct workspace:1 ID"

    # Verify close-workspace was called with the correct workspace ID
    local close_log
    close_log=$(cat "$TEST_TMP/cmux-close-log")
    assert_contains "$close_log" "close-workspace" "close-workspace was called"
    assert_contains "$close_log" "workspace:1" "close-workspace called with workspace:1"

    # Test: workspace with [selected] marker is parsed correctly
    reset_mocks
    # Create a workspace list file with [selected] marker
    printf 'workspace:0 default\nworkspace:1 TICKET-1 [selected]\nworkspace:2 other\n' \
        > "$TEST_TMP/ws-selected-list"

    LAST_EXIT=0
    LAST_OUTPUT=$(
        CMUX_PLUGIN_DIR="$TEST_TMP/mock-cmux" \
        CLEANUP_WORKTREE_SCRIPT="$TEST_TMP/mock-cleanup-worktree.sh" \
        MOCK_CLEANUP_ARGS_FILE="$TEST_TMP/cleanup-args" \
        MOCK_CMUX_CALL_LOG="$TEST_TMP/cmux-close-log" \
        MOCK_WORKSPACE_LIST_FILE="$TEST_TMP/ws-selected-list" \
        bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo crewchief 2>&1
    ) || LAST_EXIT=$?
    assert_exit_code "0" "$LAST_EXIT" "workspace with [selected] marker exits 0"
    close_log=$(cat "$TEST_TMP/cmux-close-log")
    assert_contains "$close_log" "workspace:1" "[selected] marker stripped, correct workspace matched"
}

##############################################################################
# Category 11: cmux No-Match Tests
##############################################################################

run_cmux_no_match_tests() {
    section "11. cmux No-Match Tests"
    reset_mocks
    echo "" > "$TEST_TMP/cmux-close-log"

    # Test: workspace list with no matching name, script warns and continues
    LAST_EXIT=0
    LAST_OUTPUT=$(
        CMUX_PLUGIN_DIR="$TEST_TMP/mock-cmux" \
        CLEANUP_WORKTREE_SCRIPT="$TEST_TMP/mock-cleanup-worktree.sh" \
        MOCK_CLEANUP_ARGS_FILE="$TEST_TMP/cleanup-args" \
        MOCK_CMUX_CALL_LOG="$TEST_TMP/cmux-close-log" \
        MOCK_WORKSPACE_LIST="workspace:0 default
workspace:2 other-worktree
workspace:3 something-else" \
        bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo crewchief 2>&1
    ) || LAST_EXIT=$?
    assert_exit_code "0" "$LAST_EXIT" "cmux no-match exits 0"
    assert_contains "$LAST_OUTPUT" "No cmux workspace found matching" "cmux no-match shows warning"

    # Verify cleanup-worktree.sh was still called
    local captured_args
    captured_args=$(cat "$TEST_TMP/cleanup-args")
    assert_contains "$captured_args" "TICKET-1" "cleanup-worktree.sh still called after cmux no-match"

    # Verify close-workspace was NOT called (log should be empty or just whitespace)
    local close_log
    close_log=$(cat "$TEST_TMP/cmux-close-log")
    TESTS_RUN=$((TESTS_RUN + 1))
    if printf '%s' "$close_log" | grep -qF "close-workspace"; then
        fail "close-workspace NOT called on no-match" "close-workspace was unexpectedly called"
    else
        pass "close-workspace NOT called on no-match"
    fi
}

##############################################################################
# Category 12: cmux Multiple-Match Tests
##############################################################################

run_cmux_multiple_match_tests() {
    section "12. cmux Multiple-Match Tests"
    reset_mocks
    echo "" > "$TEST_TMP/cmux-close-log"

    # Test: two workspaces both named TICKET-1
    LAST_EXIT=0
    LAST_OUTPUT=$(
        CMUX_PLUGIN_DIR="$TEST_TMP/mock-cmux" \
        CLEANUP_WORKTREE_SCRIPT="$TEST_TMP/mock-cleanup-worktree.sh" \
        MOCK_CLEANUP_ARGS_FILE="$TEST_TMP/cleanup-args" \
        MOCK_CMUX_CALL_LOG="$TEST_TMP/cmux-close-log" \
        MOCK_WORKSPACE_LIST="workspace:0 default
workspace:1 TICKET-1
workspace:3 TICKET-1" \
        bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo crewchief 2>&1
    ) || LAST_EXIT=$?
    assert_exit_code "0" "$LAST_EXIT" "cmux multiple-match exits 0"
    assert_contains "$LAST_OUTPUT" "Multiple cmux workspaces match" "multiple-match shows warning"

    # Verify close-workspace was NOT called
    local close_log
    close_log=$(cat "$TEST_TMP/cmux-close-log")
    TESTS_RUN=$((TESTS_RUN + 1))
    if printf '%s' "$close_log" | grep -qF "close-workspace"; then
        fail "close-workspace NOT called on multiple-match" "close-workspace was unexpectedly called"
    else
        pass "close-workspace NOT called on multiple-match"
    fi

    # Verify cleanup-worktree.sh was still called
    local captured_args
    captured_args=$(cat "$TEST_TMP/cleanup-args")
    assert_contains "$captured_args" "TICKET-1" "cleanup-worktree.sh still called after multiple-match"
}

##############################################################################
# Category 13: cmux Failure Modes
##############################################################################

run_cmux_failure_tests() {
    section "13. cmux Failure Modes"
    reset_mocks

    # Test: list-workspaces fails -- warn and continue to cleanup
    echo "" > "$TEST_TMP/cmux-close-log"
    LAST_EXIT=0
    LAST_OUTPUT=$(
        CMUX_PLUGIN_DIR="$TEST_TMP/mock-cmux" \
        CLEANUP_WORKTREE_SCRIPT="$TEST_TMP/mock-cleanup-worktree.sh" \
        MOCK_CLEANUP_ARGS_FILE="$TEST_TMP/cleanup-args" \
        MOCK_CMUX_CALL_LOG="$TEST_TMP/cmux-close-log" \
        MOCK_LIST_EXIT=1 \
        bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo crewchief 2>&1
    ) || LAST_EXIT=$?
    assert_exit_code "0" "$LAST_EXIT" "list-workspaces failure exits 0 (graceful)"
    assert_contains "$LAST_OUTPUT" "list-workspaces failed" "list-workspaces failure shows warning"

    # Verify cleanup-worktree.sh was still called
    local captured_args
    captured_args=$(cat "$TEST_TMP/cleanup-args")
    assert_contains "$captured_args" "TICKET-1" "cleanup called after list-workspaces failure"

    # Test: close-workspace fails -- warn and continue
    reset_mocks
    echo "" > "$TEST_TMP/cmux-close-log"
    LAST_EXIT=0
    LAST_OUTPUT=$(
        CMUX_PLUGIN_DIR="$TEST_TMP/mock-cmux" \
        CLEANUP_WORKTREE_SCRIPT="$TEST_TMP/mock-cleanup-worktree.sh" \
        MOCK_CLEANUP_ARGS_FILE="$TEST_TMP/cleanup-args" \
        MOCK_CMUX_CALL_LOG="$TEST_TMP/cmux-close-log" \
        MOCK_CLOSE_EXIT=1 \
        bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo crewchief 2>&1
    ) || LAST_EXIT=$?
    assert_exit_code "0" "$LAST_EXIT" "close-workspace failure exits 0 (graceful)"
    assert_contains "$LAST_OUTPUT" "Failed to close cmux workspace" "close-workspace failure shows warning"

    # Verify cleanup-worktree.sh was still called
    captured_args=$(cat "$TEST_TMP/cleanup-args")
    assert_contains "$captured_args" "TICKET-1" "cleanup called after close-workspace failure"
}

##############################################################################
# Category 14: Cleanup Exit Passthrough
##############################################################################

run_cleanup_exit_passthrough_tests() {
    section "14. Cleanup Exit Passthrough"
    reset_mocks

    # Test: cleanup exits 4 -> script exits 4
    LAST_EXIT=0
    LAST_OUTPUT=$(
        CMUX_PLUGIN_DIR="$TEST_TMP/mock-cmux" \
        CLEANUP_WORKTREE_SCRIPT="$TEST_TMP/mock-cleanup-worktree.sh" \
        MOCK_CLEANUP_ARGS_FILE="$TEST_TMP/cleanup-args" \
        MOCK_CMUX_CALL_LOG="$TEST_TMP/cmux-close-log" \
        MOCK_CLEANUP_EXIT=4 \
        bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo crewchief 2>&1
    ) || LAST_EXIT=$?
    assert_exit_code "4" "$LAST_EXIT" "cleanup exit 4 -> script exits 4"

    # Test: cleanup exits 5 (user cancelled) -> script exits 5
    LAST_EXIT=0
    LAST_OUTPUT=$(
        CMUX_PLUGIN_DIR="$TEST_TMP/mock-cmux" \
        CLEANUP_WORKTREE_SCRIPT="$TEST_TMP/mock-cleanup-worktree.sh" \
        MOCK_CLEANUP_ARGS_FILE="$TEST_TMP/cleanup-args" \
        MOCK_CMUX_CALL_LOG="$TEST_TMP/cmux-close-log" \
        MOCK_CLEANUP_EXIT=5 \
        bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo crewchief 2>&1
    ) || LAST_EXIT=$?
    assert_exit_code "5" "$LAST_EXIT" "cleanup exit 5 -> script exits 5 (user cancelled)"
    assert_contains "$LAST_OUTPUT" "User cancelled" "user cancelled shows warning"
}

##############################################################################
# Category 15: Graceful Degradation
##############################################################################

run_graceful_degradation_tests() {
    section "15. Graceful Degradation"
    reset_mocks

    # Test: --skip-cmux with cmux-check.sh failure still succeeds
    cat > "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-check.sh" << 'FAILEOF'
#!/bin/bash
exit 1
FAILEOF
    chmod +x "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-check.sh"

    run_script TICKET-1 --repo crewchief --skip-cmux
    assert_exit_code "0" "$LAST_EXIT" "--skip-cmux with failing cmux-check.sh exits 0"

    # Test: cmux-check.sh not found (no cmux dir) -- cmux auto-skipped
    reset_mocks
    LAST_EXIT=0
    LAST_OUTPUT=$(
        CMUX_PLUGIN_DIR="$TEST_TMP/nonexistent-cmux-dir" \
        CLEANUP_WORKTREE_SCRIPT="$TEST_TMP/mock-cleanup-worktree.sh" \
        MOCK_CLEANUP_ARGS_FILE="$TEST_TMP/cleanup-args" \
        MOCK_CMUX_CALL_LOG="$TEST_TMP/cmux-close-log" \
        bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo crewchief 2>&1
    ) || LAST_EXIT=$?
    assert_exit_code "0" "$LAST_EXIT" "missing cmux dir -> cmux auto-skipped, exits 0"
    assert_contains "$LAST_OUTPUT" "cmux-check.sh not found" "missing cmux dir shows cmux-check.sh not found"
    assert_contains "$LAST_OUTPUT" "cmux workspace closure will be skipped" "missing cmux dir shows skip message"

    # Verify cleanup-worktree.sh was still called
    local captured_args
    captured_args=$(cat "$TEST_TMP/cleanup-args")
    assert_contains "$captured_args" "TICKET-1" "cleanup still called after cmux auto-skip"

    # Test: cmux-check.sh fails (no --skip-cmux) -- cmux auto-skipped, cleanup proceeds
    reset_mocks
    cat > "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-check.sh" << 'FAILEOF'
#!/bin/bash
exit 1
FAILEOF
    chmod +x "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-check.sh"

    run_script TICKET-1 --repo crewchief
    assert_exit_code "0" "$LAST_EXIT" "cmux-check.sh failure auto-skips cmux, exits 0"
    assert_contains "$LAST_OUTPUT" "cmux prerequisite check failed" "cmux-check failure shows warning"
    assert_contains "$LAST_OUTPUT" "Worktree Teardown Complete" "cmux-check failure still completes teardown"

    # Test: cleanup-worktree.sh not found exits 2
    reset_mocks
    LAST_EXIT=0
    LAST_OUTPUT=$(
        CMUX_PLUGIN_DIR="$TEST_TMP/mock-cmux" \
        CLEANUP_WORKTREE_SCRIPT="$TEST_TMP/nonexistent-cleanup.sh" \
        bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo crewchief 2>&1
    ) || LAST_EXIT=$?
    assert_exit_code "2" "$LAST_EXIT" "missing cleanup-worktree.sh exits 2"
    assert_contains "$LAST_OUTPUT" "cleanup-worktree.sh not found" "missing cleanup shows error"
}

##############################################################################
# Category 16: Exit Code Summary Tests
##############################################################################

run_exit_code_summary_tests() {
    section "16. Exit Code Summary"
    reset_mocks

    local exit_code=0

    # Exit 0: --help
    exit_code=0
    bash "$SCRIPT_UNDER_TEST" --help >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "0" "$exit_code" "exit 0: --help"

    # Exit 0: --dry-run
    exit_code=0
    CMUX_PLUGIN_DIR="$TEST_TMP/mock-cmux" \
    CLEANUP_WORKTREE_SCRIPT="$TEST_TMP/mock-cleanup-worktree.sh" \
    bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo crewchief --dry-run >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "0" "$exit_code" "exit 0: --dry-run"

    # Exit 0: successful teardown
    exit_code=0
    CMUX_PLUGIN_DIR="$TEST_TMP/mock-cmux" \
    CLEANUP_WORKTREE_SCRIPT="$TEST_TMP/mock-cleanup-worktree.sh" \
    MOCK_CLEANUP_ARGS_FILE="$TEST_TMP/cleanup-args" \
    MOCK_CMUX_CALL_LOG="$TEST_TMP/cmux-close-log" \
    bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo crewchief >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "0" "$exit_code" "exit 0: successful teardown"

    # Exit 1: missing worktree name
    exit_code=0
    bash "$SCRIPT_UNDER_TEST" --repo crewchief >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "1" "$exit_code" "exit 1: missing worktree name"

    # Exit 1: missing --repo
    exit_code=0
    bash "$SCRIPT_UNDER_TEST" TICKET-1 >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "1" "$exit_code" "exit 1: missing --repo"

    # Exit 2: cleanup-worktree.sh not found
    exit_code=0
    CMUX_PLUGIN_DIR="$TEST_TMP/mock-cmux" \
    CLEANUP_WORKTREE_SCRIPT="$TEST_TMP/nonexistent-cleanup.sh" \
    bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo crewchief >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "2" "$exit_code" "exit 2: cleanup-worktree.sh not found"

    # Exit 3: unrecognized option
    exit_code=0
    bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo crewchief --unknown >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "3" "$exit_code" "exit 3: unrecognized option"

    # Exit 4: cleanup failure
    exit_code=0
    CMUX_PLUGIN_DIR="$TEST_TMP/mock-cmux" \
    CLEANUP_WORKTREE_SCRIPT="$TEST_TMP/mock-cleanup-worktree.sh" \
    MOCK_CLEANUP_ARGS_FILE="$TEST_TMP/cleanup-args" \
    MOCK_CMUX_CALL_LOG="$TEST_TMP/cmux-close-log" \
    MOCK_CLEANUP_EXIT=4 \
    bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo crewchief >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "4" "$exit_code" "exit 4: cleanup failure"

    # Exit 5: user cancelled
    exit_code=0
    CMUX_PLUGIN_DIR="$TEST_TMP/mock-cmux" \
    CLEANUP_WORKTREE_SCRIPT="$TEST_TMP/mock-cleanup-worktree.sh" \
    MOCK_CLEANUP_ARGS_FILE="$TEST_TMP/cleanup-args" \
    MOCK_CMUX_CALL_LOG="$TEST_TMP/cmux-close-log" \
    MOCK_CLEANUP_EXIT=5 \
    bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo crewchief >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "5" "$exit_code" "exit 5: user cancelled"
}

##############################################################################
# Main Test Runner
##############################################################################

main() {
    printf "\n"
    printf "========================================================\n"
    printf "  teardown-worktree.sh Test Suite\n"
    printf "========================================================\n"
    printf "\n"

    # Setup
    setup

    # Ensure cleanup runs on exit
    trap 'rm -rf $TEST_TMP' EXIT INT TERM

    # Run all test categories
    run_prerequisite_tests
    run_help_tests
    run_argument_parsing_tests
    run_invalid_name_tests
    run_dry_run_tests
    run_dry_run_skip_cmux_tests
    run_dry_run_flag_passthrough_tests
    run_flag_passthrough_tests
    run_verbose_tests
    run_cmux_workspace_match_tests
    run_cmux_no_match_tests
    run_cmux_multiple_match_tests
    run_cmux_failure_tests
    run_cleanup_exit_passthrough_tests
    run_graceful_degradation_tests
    run_exit_code_summary_tests

    # Summary
    printf "\n"
    printf "========================================================\n"
    printf "  Test Summary\n"
    printf "========================================================\n"
    printf "\n"
    printf "  Tests run:    ${BLUE}%d${NC}\n" "$TESTS_RUN"
    printf "  Tests passed: ${GREEN}%d${NC}\n" "$TESTS_PASSED"
    printf "  Tests failed: ${RED}%d${NC}\n" "$TESTS_FAILED"
    printf "\n"

    if [ "$TESTS_FAILED" -gt 0 ]; then
        printf "  ${RED}FAILED${NC}: %d test(s) failed\n" "$TESTS_FAILED"
        printf "\n"
        exit 1
    else
        printf "  ${GREEN}SUCCESS${NC}: All tests passed\n"
        printf "\n"
        exit 0
    fi
}

main "$@"
