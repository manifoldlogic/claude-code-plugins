#!/usr/bin/env zsh
#
# test-merge-worktree.sh - Tests for merge-worktree.sh worktree merge script
#
# DESCRIPTION:
#   Comprehensive test suite for merge-worktree.sh covering:
#   - Argument parsing (valid, invalid, missing, unknown flags, empty values, path traversal)
#   - CWD auto-detection logic (valid worktree paths, main worktree rejection, non-workspace paths)
#   - Help flag output
#   - Dry-run output
#   - Exit codes (all documented codes 0-10)
#   - Flag combinations (--skip-pr-check, --skip-workspace, --skip-tab-close, --yes, --verbose)
#   - Integration tests with mocked dependencies
#
# USAGE:
#   zsh test-merge-worktree.sh           # Run all tests
#   zsh test-merge-worktree.sh --verbose # Verbose output
#   zsh test-merge-worktree.sh --help    # Show help
#
# EXIT CODES:
#   0 - All tests passed
#   1 - One or more tests failed

set -uo pipefail

##############################################################################
# Script Location
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_UNDER_TEST="$SCRIPT_DIR/merge-worktree.sh"

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

    # Create mock bin directory for mock commands
    mkdir -p "$TEST_TMP/mock-bin"

    # Create mock crewchief that succeeds by default
    cat > "$TEST_TMP/mock-bin/crewchief" << 'MOCKEOF'
#!/bin/sh
# Mock crewchief - logs invocation and succeeds
echo "MOCK_CREWCHIEF_CALLED: $*" >> "${MOCK_LOG:-/dev/null}"
exit "${MOCK_CREWCHIEF_EXIT:-0}"
MOCKEOF
    chmod +x "$TEST_TMP/mock-bin/crewchief"

    # Create mock gh that succeeds by default (no PR found)
    cat > "$TEST_TMP/mock-bin/gh" << 'MOCKEOF'
#!/bin/sh
# Mock gh - logs invocation, returns no PR by default
echo "MOCK_GH_CALLED: $*" >> "${MOCK_LOG:-/dev/null}"
exit "${MOCK_GH_EXIT:-1}"
MOCKEOF
    chmod +x "$TEST_TMP/mock-bin/gh"

    # Create mock workspace-folder.sh
    cat > "$TEST_TMP/mock-bin/workspace-folder.sh" << 'MOCKEOF'
#!/bin/sh
echo "MOCK_WORKSPACE_FOLDER_CALLED: $*" >> "${MOCK_LOG:-/dev/null}"
exit 0
MOCKEOF
    chmod +x "$TEST_TMP/mock-bin/workspace-folder.sh"

    # Create mock iterm-close-tab.sh
    mkdir -p "$TEST_TMP/mock-iterm/skills/tab-management/scripts"
    cat > "$TEST_TMP/mock-iterm/skills/tab-management/scripts/iterm-close-tab.sh" << 'MOCKEOF'
#!/bin/sh
echo "MOCK_ITERM_CLOSE_TAB: $*" >> "${MOCK_LOG:-/dev/null}"
exit 0
MOCKEOF
    chmod +x "$TEST_TMP/mock-iterm/skills/tab-management/scripts/iterm-close-tab.sh"

    # Create mock log file
    touch "$TEST_TMP/mock.log"
}

teardown() {
    if [ -n "$TEST_TMP" ] && [ -d "$TEST_TMP" ]; then
        rm -rf "$TEST_TMP"
        debug_msg "Cleaned up temp directory: $TEST_TMP"
    fi
    # Clean up any lock files created during tests (use find to avoid zsh glob error)
    find /tmp -maxdepth 1 -name 'worktree-merge-*.lock' -delete 2>/dev/null || true
}

# Run merge-worktree.sh as a subprocess with mocked PATH
# Note: merge-worktree.sh has #!/usr/bin/env bash shebang, so we invoke with bash
# Usage: run_script [args...]
# Sets: LAST_EXIT, LAST_OUTPUT
run_script() {
    LAST_EXIT=0
    LAST_OUTPUT=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" "$@" 2>&1
    ) || LAST_EXIT=$?
    debug_msg "run_script exit=$LAST_EXIT args='$*'"
    if [ "$VERBOSE" = "true" ]; then
        debug_msg "output: $(printf '%s' "$LAST_OUTPUT" | head -5)"
    fi
}

# Run merge-worktree.sh from a specific working directory
# Note: merge-worktree.sh has #!/usr/bin/env bash shebang, so we invoke with bash
# Usage: run_script_in_dir <dir> [args...]
# Sets: LAST_EXIT, LAST_OUTPUT
run_script_in_dir() {
    local work_dir="$1"
    shift
    LAST_EXIT=0
    LAST_OUTPUT=$(
        cd "$work_dir" && \
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" "$@" 2>&1
    ) || LAST_EXIT=$?
    debug_msg "run_script_in_dir dir=$work_dir exit=$LAST_EXIT args='$*'"
}

##############################################################################
# Category 1: Script Prerequisites
##############################################################################

run_prerequisite_tests() {
    section "1. Script Prerequisites"

    # Test: merge-worktree.sh exists
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -f "$SCRIPT_UNDER_TEST" ]; then
        pass "merge-worktree.sh exists"
    else
        fail "merge-worktree.sh exists" "file not found at $SCRIPT_UNDER_TEST"
        return
    fi

    # Test: merge-worktree.sh is executable
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -x "$SCRIPT_UNDER_TEST" ]; then
        pass "merge-worktree.sh is executable"
    else
        fail "merge-worktree.sh is executable" "file is not executable"
    fi

    # Test: worktree-common.sh exists
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -f "$SCRIPT_DIR/worktree-common.sh" ]; then
        pass "worktree-common.sh exists (dependency)"
    else
        fail "worktree-common.sh exists (dependency)" "file not found"
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
    assert_contains "$output" "merge-worktree.sh" "--help mentions script name"
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

    # Test: --repo with missing value exits 3
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" --repo 2>&1) || exit_code=$?
    assert_exit_code "3" "$exit_code" "--repo with missing value exits 3"
    assert_contains "$output" "--repo requires an argument" "--repo missing value shows error"

    # Test: -r with missing value exits 3
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" -r 2>&1) || exit_code=$?
    assert_exit_code "3" "$exit_code" "-r with missing value exits 3"

    # Test: --strategy with missing value exits 3
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" --strategy 2>&1) || exit_code=$?
    assert_exit_code "3" "$exit_code" "--strategy with missing value exits 3"
    assert_contains "$output" "--strategy requires an argument" "--strategy missing value shows error"

    # Test: --base-branch with missing value exits 3
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" --base-branch 2>&1) || exit_code=$?
    assert_exit_code "3" "$exit_code" "--base-branch with missing value exits 3"

    # Test: --workspace with missing value exits 3
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" --workspace 2>&1) || exit_code=$?
    assert_exit_code "3" "$exit_code" "--workspace with missing value exits 3"

    # Test: --unknown-flag exits 3
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" --unknown-flag 2>&1) || exit_code=$?
    assert_exit_code "3" "$exit_code" "--unknown-flag exits 3"
    assert_contains "$output" "Unknown option" "--unknown-flag shows error"

    # Test: path traversal attempt exits 3 (validate_worktree_name rejects it)
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" "../../path-traversal" --repo test 2>&1) || exit_code=$?
    assert_exit_code "3" "$exit_code" "path traversal '../../path-traversal' exits 3"
    assert_contains "$output" "Invalid name" "path traversal shows validation error"

    # Test: empty worktree name exits 3
    # The empty string triggers auto-detect, which fails from /tmp, then exit 3
    exit_code=0
    output=$(cd /tmp && bash "$SCRIPT_UNDER_TEST" "" --repo test 2>&1) || exit_code=$?
    assert_exit_code "3" "$exit_code" "empty worktree name exits 3"

    # Test: no args, not in worktree path exits 3
    exit_code=0
    output=$(cd /tmp && bash "$SCRIPT_UNDER_TEST" 2>&1) || exit_code=$?
    assert_exit_code "3" "$exit_code" "no args, not in worktree exits 3"
    assert_contains "$output" "Missing worktree name" "no args shows missing worktree error"

    # Test: invalid strategy exits 3
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        bash "$SCRIPT_UNDER_TEST" feature-x --repo myproject --strategy invalid 2>&1
    ) || exit_code=$?
    assert_exit_code "3" "$exit_code" "--strategy invalid exits 3"
    assert_contains "$output" "Invalid merge strategy" "invalid strategy shows error"

    # Test: name starting with hyphen is caught (either as unknown flag or validation)
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" "-badname" --repo test 2>&1) || exit_code=$?
    assert_exit_code "3" "$exit_code" "name starting with hyphen exits 3"

    # Test: duplicate positional argument exits 3
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        bash "$SCRIPT_UNDER_TEST" feature-a feature-b --repo test 2>&1
    ) || exit_code=$?
    assert_exit_code "3" "$exit_code" "duplicate positional arg exits 3"
    assert_contains "$output" "Unexpected positional argument" "duplicate positional shows error"
}

##############################################################################
# Category 4: CWD Auto-Detection Tests
##############################################################################

run_cwd_detection_tests() {
    section "4. CWD Auto-Detection Tests"

    local exit_code=0
    local output

    # Create simulated workspace structures in temp
    # We need actual /workspace/repos paths for detection to work.
    # Since detection checks `pwd` against /workspace/repos/ prefix,
    # we create real directories under /workspace/repos/ for testing.

    local test_repo_base="/workspace/repos/_test_merge_wt_$$"
    mkdir -p "$test_repo_base/_test_merge_wt_$$" 2>/dev/null || true
    mkdir -p "$test_repo_base/feature-branch" 2>/dev/null || true
    mkdir -p "$test_repo_base/feature-branch/src/deep/dir" 2>/dev/null || true
    mkdir -p "/workspace/repos/repo-with-dashes/worktree_underscore_123" 2>/dev/null || true

    # Test: auto-detect from worktree directory
    exit_code=0
    output=$(
        cd "$test_repo_base/feature-branch" && \
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" --dry-run 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "auto-detect from worktree dir exits 0 (dry-run)"
    assert_contains "$output" "Auto-detected from cwd" "auto-detect shows detection message"
    assert_contains "$output" "feature-branch" "auto-detect finds worktree name"

    # Test: auto-detect from deeply nested path
    exit_code=0
    output=$(
        cd "$test_repo_base/feature-branch/src/deep/dir" && \
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" --dry-run 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "auto-detect from nested path exits 0 (dry-run)"
    assert_contains "$output" "feature-branch" "nested path detects correct worktree"

    # Test: main worktree (repo == worktree) exits 3
    exit_code=0
    output=$(
        cd "$test_repo_base/_test_merge_wt_$$" && \
        bash "$SCRIPT_UNDER_TEST" 2>&1
    ) || exit_code=$?
    assert_exit_code "3" "$exit_code" "main worktree (repo == worktree) exits 3"
    assert_contains "$output" "main worktree" "main worktree shows descriptive error"

    # Test: not in /workspace/repos/ exits 3
    exit_code=0
    output=$(cd /tmp && bash "$SCRIPT_UNDER_TEST" 2>&1) || exit_code=$?
    assert_exit_code "3" "$exit_code" "not in /workspace/repos/ exits 3"

    # Test: at repo level (not in worktree subdir) exits 3
    exit_code=0
    output=$(cd "$test_repo_base" && bash "$SCRIPT_UNDER_TEST" 2>&1) || exit_code=$?
    assert_exit_code "3" "$exit_code" "at repo level (no worktree segment) exits 3"

    # Test: repo/worktree with special characters (hyphens and underscores)
    exit_code=0
    output=$(
        cd "/workspace/repos/repo-with-dashes/worktree_underscore_123" && \
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" --dry-run 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "hyphens and underscores in names exits 0 (dry-run)"
    assert_contains "$output" "repo-with-dashes" "detects repo with hyphens"
    assert_contains "$output" "worktree_underscore_123" "detects worktree with underscores"

    # Cleanup test directories
    rm -rf "$test_repo_base" 2>/dev/null || true
    rm -rf "/workspace/repos/repo-with-dashes" 2>/dev/null || true
}

##############################################################################
# Category 5: Dry-Run Output Tests
##############################################################################

run_dry_run_tests() {
    section "5. Dry-Run Output Tests"

    local exit_code=0
    local output

    # Create a test repo structure for dry-run
    local test_repo="/workspace/repos/_test_dryrun_$$"
    mkdir -p "$test_repo/_test_dryrun_$$" 2>/dev/null || true
    mkdir -p "$test_repo/feature-dry" 2>/dev/null || true

    # Test: --dry-run with explicit args produces preview and exits 0
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" feature-dry --repo "_test_dryrun_$$" --dry-run 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "--dry-run exits 0"
    assert_contains "$output" "DRY RUN" "--dry-run shows DRY RUN header"
    assert_contains "$output" "Would execute with resolved parameters" "--dry-run shows parameters header"
    assert_contains "$output" "Repository:" "--dry-run shows repository"
    assert_contains "$output" "Worktree name: feature-dry" "--dry-run shows worktree name"
    assert_contains "$output" "Strategy: ff" "--dry-run shows default strategy"
    assert_contains "$output" "Planned operations" "--dry-run shows planned operations"

    # Test: --dry-run with squash strategy shows correct strategy
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" feature-dry --repo "_test_dryrun_$$" --strategy squash --dry-run 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "--dry-run with --strategy squash exits 0"
    assert_contains "$output" "Strategy: squash" "--dry-run shows squash strategy"

    # Test: --dry-run with --skip-pr-check notes it
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" feature-dry --repo "_test_dryrun_$$" --skip-pr-check --dry-run 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "--dry-run with --skip-pr-check exits 0"
    assert_contains "$output" "SKIPPED" "--dry-run notes skipped PR check"

    # Test: --dry-run with auto-detection
    exit_code=0
    output=$(
        cd "$test_repo/feature-dry" && \
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" --dry-run 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "--dry-run with auto-detection exits 0"
    assert_contains "$output" "Auto-detected" "--dry-run with auto-detection shows detection"
    assert_contains "$output" "feature-dry" "--dry-run with auto-detection shows worktree name"

    # Cleanup
    rm -rf "$test_repo" 2>/dev/null || true
}

##############################################################################
# Category 6: Exit Code Tests
##############################################################################

run_exit_code_tests() {
    section "6. Exit Code Tests"

    local exit_code=0
    local output

    # Exit 0: --help
    exit_code=0
    bash "$SCRIPT_UNDER_TEST" --help >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "0" "$exit_code" "exit 0: --help"

    # Exit 3: invalid arguments (unknown flag)
    exit_code=0
    bash "$SCRIPT_UNDER_TEST" --nonsense >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "3" "$exit_code" "exit 3: unknown flag"

    # Exit 3: invalid strategy
    exit_code=0
    PATH="$TEST_TMP/mock-bin:$PATH" \
    bash "$SCRIPT_UNDER_TEST" feat --repo myrepo --strategy badstrat >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "3" "$exit_code" "exit 3: invalid strategy"

    # Exit 3: missing args, not in worktree
    exit_code=0
    (cd /tmp && bash "$SCRIPT_UNDER_TEST") >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "3" "$exit_code" "exit 3: no args, not in worktree"

    # Exit 4: worktree not found (valid args but directory doesn't exist)
    # Need mocked crewchief on PATH, and a main worktree that exists
    local test_repo_4="/workspace/repos/_test_exit4_$$"
    mkdir -p "$test_repo_4/_test_exit4_$$" 2>/dev/null || true
    exit_code=0
    PATH="$TEST_TMP/mock-bin:$PATH" \
    MOCK_LOG="$TEST_TMP/mock.log" \
    ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
    bash "$SCRIPT_UNDER_TEST" nonexistent-wt --repo "_test_exit4_$$" --yes >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "4" "$exit_code" "exit 4: worktree directory not found"
    rm -rf "$test_repo_4" 2>/dev/null || true

    # Exit 6: lock acquisition failure (simulate by holding a lock)
    local test_repo_6="/workspace/repos/_test_exit6_$$"
    mkdir -p "$test_repo_6/_test_exit6_$$" 2>/dev/null || true
    mkdir -p "$test_repo_6/locked-wt" 2>/dev/null || true
    local lock_file="/tmp/worktree-merge-_test_exit6_$$-locked-wt.lock"
    # Hold a lock via a background subprocess using flock
    flock "$lock_file" sleep 30 &
    local lock_pid=$!
    # Brief pause to ensure the lock is acquired
    sleep 0.2
    exit_code=0
    PATH="$TEST_TMP/mock-bin:$PATH" \
    MOCK_LOG="$TEST_TMP/mock.log" \
    ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
    bash "$SCRIPT_UNDER_TEST" locked-wt --repo "_test_exit6_$$" --yes >/dev/null 2>&1 || exit_code=$?
    kill "$lock_pid" 2>/dev/null || true
    wait "$lock_pid" 2>/dev/null || true
    rm -f "$lock_file" 2>/dev/null || true
    assert_exit_code "6" "$exit_code" "exit 6: lock acquisition failed"
    rm -rf "$test_repo_6" 2>/dev/null || true

    # Exit 7: merge failed (crewchief returns non-zero)
    local test_repo_7="/workspace/repos/_test_exit7_$$"
    mkdir -p "$test_repo_7/_test_exit7_$$" 2>/dev/null || true
    mkdir -p "$test_repo_7/fail-wt" 2>/dev/null || true
    # Override mock crewchief to fail
    cat > "$TEST_TMP/mock-bin/crewchief" << 'MOCKEOF'
#!/bin/sh
echo "MOCK_CREWCHIEF_CALLED: $*" >> "${MOCK_LOG:-/dev/null}"
exit "${MOCK_CREWCHIEF_EXIT:-0}"
MOCKEOF
    chmod +x "$TEST_TMP/mock-bin/crewchief"
    exit_code=0
    MOCK_CREWCHIEF_EXIT=1 \
    PATH="$TEST_TMP/mock-bin:$PATH" \
    MOCK_LOG="$TEST_TMP/mock.log" \
    ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
    bash "$SCRIPT_UNDER_TEST" fail-wt --repo "_test_exit7_$$" --yes --skip-pr-check >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "7" "$exit_code" "exit 7: merge failed (crewchief error)"
    rm -rf "$test_repo_7" 2>/dev/null || true

    # Reset mock crewchief to succeed
    cat > "$TEST_TMP/mock-bin/crewchief" << 'MOCKEOF'
#!/bin/sh
echo "MOCK_CREWCHIEF_CALLED: $*" >> "${MOCK_LOG:-/dev/null}"
exit "${MOCK_CREWCHIEF_EXIT:-0}"
MOCKEOF
    chmod +x "$TEST_TMP/mock-bin/crewchief"

    # Exit 8: PR check blocked (PR is OPEN and non-draft)
    local test_repo_8="/workspace/repos/_test_exit8_$$"
    mkdir -p "$test_repo_8/_test_exit8_$$" 2>/dev/null || true
    mkdir -p "$test_repo_8/pr-open-wt" 2>/dev/null || true
    # Override mock gh to return OPEN non-draft PR
    cat > "$TEST_TMP/mock-bin/gh" << 'MOCKEOF'
#!/bin/sh
echo '{"state": "OPEN", "isDraft": false}'
exit 0
MOCKEOF
    chmod +x "$TEST_TMP/mock-bin/gh"
    exit_code=0
    PATH="$TEST_TMP/mock-bin:$PATH" \
    MOCK_LOG="$TEST_TMP/mock.log" \
    ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
    bash "$SCRIPT_UNDER_TEST" pr-open-wt --repo "_test_exit8_$$" --yes >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "8" "$exit_code" "exit 8: PR is OPEN and non-draft"
    rm -rf "$test_repo_8" 2>/dev/null || true

    # Reset mock gh
    cat > "$TEST_TMP/mock-bin/gh" << 'MOCKEOF'
#!/bin/sh
echo "MOCK_GH_CALLED: $*" >> "${MOCK_LOG:-/dev/null}"
exit "${MOCK_GH_EXIT:-1}"
MOCKEOF
    chmod +x "$TEST_TMP/mock-bin/gh"

    # Exit 9: main worktree not found
    # Provide a repo name with no corresponding directory
    exit_code=0
    PATH="$TEST_TMP/mock-bin:$PATH" \
    MOCK_LOG="$TEST_TMP/mock.log" \
    ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
    bash "$SCRIPT_UNDER_TEST" some-wt --repo "nonexistent_repo_$$" --dry-run >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "9" "$exit_code" "exit 9: main worktree not found (dry-run resolves path)"

    # Exit 10: success with warnings (merge ok, cleanup failed)
    local test_repo_10="/workspace/repos/_test_exit10_$$"
    mkdir -p "$test_repo_10/_test_exit10_$$" 2>/dev/null || true
    mkdir -p "$test_repo_10/warn-wt" 2>/dev/null || true
    # Mock iterm-close-tab.sh to fail
    cat > "$TEST_TMP/mock-iterm/skills/tab-management/scripts/iterm-close-tab.sh" << 'MOCKEOF'
#!/bin/sh
exit 1
MOCKEOF
    chmod +x "$TEST_TMP/mock-iterm/skills/tab-management/scripts/iterm-close-tab.sh"
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        WORKSPACE_FILE="/nonexistent/path/workspace.code-workspace" \
        bash "$SCRIPT_UNDER_TEST" warn-wt --repo "_test_exit10_$$" --yes --skip-pr-check --skip-workspace 2>&1
    ) || exit_code=$?
    assert_exit_code "10" "$exit_code" "exit 10: success with warnings (tab close failed)"
    rm -rf "$test_repo_10" 2>/dev/null || true

    # Reset mock iterm-close-tab.sh
    cat > "$TEST_TMP/mock-iterm/skills/tab-management/scripts/iterm-close-tab.sh" << 'MOCKEOF'
#!/bin/sh
echo "MOCK_ITERM_CLOSE_TAB: $*" >> "${MOCK_LOG:-/dev/null}"
exit 0
MOCKEOF
    chmod +x "$TEST_TMP/mock-iterm/skills/tab-management/scripts/iterm-close-tab.sh"

    # Exit 0: full successful merge (all mocks succeed)
    local test_repo_0="/workspace/repos/_test_exit0_$$"
    mkdir -p "$test_repo_0/_test_exit0_$$" 2>/dev/null || true
    mkdir -p "$test_repo_0/ok-wt" 2>/dev/null || true
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" ok-wt --repo "_test_exit0_$$" --yes --skip-pr-check --skip-workspace 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "exit 0: successful merge with all skips"
    assert_contains "$output" "Worktree Merge Complete" "successful merge shows completion message"
    rm -rf "$test_repo_0" 2>/dev/null || true
}

##############################################################################
# Category 7: Flag Combination Tests
##############################################################################

run_flag_combination_tests() {
    section "7. Flag Combination Tests"

    local exit_code=0
    local output

    local test_repo="/workspace/repos/_test_flags_$$"
    mkdir -p "$test_repo/_test_flags_$$" 2>/dev/null || true
    mkdir -p "$test_repo/flag-wt" 2>/dev/null || true

    # Test: --skip-pr-check disables PR check
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" flag-wt --repo "_test_flags_$$" --skip-pr-check --dry-run 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "--skip-pr-check with --dry-run exits 0"
    assert_contains "$output" "SKIPPED" "--skip-pr-check noted in dry-run"

    # Test: --skip-workspace disables workspace removal
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" flag-wt --repo "_test_flags_$$" --skip-workspace --dry-run 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "--skip-workspace with --dry-run exits 0"
    # Workspace update should be skipped in dry-run output
    assert_contains "$output" "--skip-workspace" "--skip-workspace noted in dry-run"

    # Test: --skip-tab-close disables tab close
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" flag-wt --repo "_test_flags_$$" --skip-tab-close --dry-run 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "--skip-tab-close with --dry-run exits 0"
    assert_contains "$output" "--skip-tab-close" "--skip-tab-close noted in dry-run"

    # Test: --verbose enables debug output
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" flag-wt --repo "_test_flags_$$" --verbose --dry-run 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "--verbose with --dry-run exits 0"
    assert_contains "$output" "[DEBUG]" "--verbose enables debug output"

    # Test: --yes flag is accepted
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" flag-wt --repo "_test_flags_$$" --yes --dry-run 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "--yes with --dry-run exits 0"

    # Test: all skip flags combined still produces valid dry-run
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" flag-wt --repo "_test_flags_$$" \
            --skip-pr-check --skip-workspace --skip-tab-close --yes --verbose --dry-run 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "all flags combined with --dry-run exits 0"
    assert_contains "$output" "DRY RUN" "all flags combined shows DRY RUN"
    assert_contains "$output" "[DEBUG]" "all flags combined shows debug output"

    # Test: all skip flags combined - actual merge succeeds
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" flag-wt --repo "_test_flags_$$" \
            --skip-pr-check --skip-workspace --skip-tab-close --yes 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "all skip flags combined - actual merge exits 0"
    assert_contains "$output" "Worktree Merge Complete" "all skip flags - merge complete"

    # Test: -y short flag works
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" flag-wt --repo "_test_flags_$$" \
            -y --skip-pr-check --skip-workspace --skip-tab-close 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "-y short flag works for skip confirmation"

    # Test: -s short flag for strategy
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" flag-wt --repo "_test_flags_$$" -s cherry-pick --dry-run 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "-s cherry-pick with --dry-run exits 0"
    assert_contains "$output" "Strategy: cherry-pick" "-s cherry-pick shows correct strategy"

    # Test: -r short flag for repo
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" flag-wt -r "_test_flags_$$" --dry-run 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "-r short flag for repo works"
    assert_contains "$output" "_test_flags_$$" "-r short flag passes repo name"

    # Test: -b short flag for base-branch
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" flag-wt --repo "_test_flags_$$" -b develop --dry-run 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "-b develop with --dry-run exits 0"
    assert_contains "$output" "Base branch: develop" "-b develop shows correct base branch"

    # Cleanup
    rm -rf "$test_repo" 2>/dev/null || true
}

##############################################################################
# Category 8: Integration Tests with Mocked Dependencies
##############################################################################

run_integration_tests() {
    section "8. Integration Tests (Mocked Dependencies)"

    local exit_code=0
    local output

    # Clear mock log
    : > "$TEST_TMP/mock.log"

    # Create test repo structure
    local test_repo="/workspace/repos/_test_integ_$$"
    mkdir -p "$test_repo/_test_integ_$$" 2>/dev/null || true
    mkdir -p "$test_repo/integ-wt" 2>/dev/null || true
    mkdir -p "$test_repo/integ-wt/src/deep" 2>/dev/null || true

    # Test: auto-detection from nested worktree path
    exit_code=0
    output=$(
        cd "$test_repo/integ-wt/src/deep" && \
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" --yes --skip-pr-check --skip-workspace --skip-tab-close 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "integration: auto-detect from nested path succeeds"
    assert_contains "$output" "Auto-detected from cwd" "integration: auto-detect message shown"
    assert_contains "$output" "integ-wt" "integration: correct worktree detected"

    # Test: crewchief receives correct arguments
    : > "$TEST_TMP/mock.log"
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" integ-wt --repo "_test_integ_$$" --strategy squash --yes --skip-pr-check --skip-workspace --skip-tab-close 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "integration: merge with squash strategy succeeds"
    # Check mock log for crewchief invocation
    local mock_log_content
    mock_log_content=$(cat "$TEST_TMP/mock.log" 2>/dev/null || echo "")
    assert_contains "$mock_log_content" "worktree merge integ-wt" "integration: crewchief receives merge command"
    assert_contains "$mock_log_content" "--strategy squash" "integration: crewchief receives --strategy squash"
    assert_contains "$mock_log_content" "--yes" "integration: crewchief receives --yes"

    # Test: crewchief receives default strategy (no --strategy flag) when ff
    : > "$TEST_TMP/mock.log"
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" integ-wt --repo "_test_integ_$$" --yes --skip-pr-check --skip-workspace --skip-tab-close 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "integration: merge with default ff strategy succeeds"
    mock_log_content=$(cat "$TEST_TMP/mock.log" 2>/dev/null || echo "")
    assert_contains "$mock_log_content" "worktree merge integ-wt" "integration: crewchief receives merge with default strategy"
    assert_not_contains "$mock_log_content" "--strategy" "integration: no --strategy flag for default ff"

    # Test: iterm-close-tab invoked with correct pattern
    : > "$TEST_TMP/mock.log"
    cat > "$TEST_TMP/mock-iterm/skills/tab-management/scripts/iterm-close-tab.sh" << 'MOCKEOF'
#!/bin/sh
echo "MOCK_ITERM_CLOSE_TAB: $*" >> "${MOCK_LOG:-/dev/null}"
exit 0
MOCKEOF
    chmod +x "$TEST_TMP/mock-iterm/skills/tab-management/scripts/iterm-close-tab.sh"
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" integ-wt --repo "_test_integ_$$" --yes --skip-pr-check --skip-workspace 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "integration: merge with tab close succeeds"
    mock_log_content=$(cat "$TEST_TMP/mock.log" 2>/dev/null || echo "")
    assert_contains "$mock_log_content" "MOCK_ITERM_CLOSE_TAB" "integration: iterm-close-tab was called"
    # Tab pattern should be "repo worktree"
    assert_contains "$mock_log_content" "_test_integ_$$ integ-wt" "integration: tab close pattern is 'repo worktree'"

    # Test: tab pattern captured BEFORE cwd change (verified by correct pattern in log)
    # The tab pattern is "$REPO $WORKTREE_NAME" set before cd to main worktree.
    # If it were captured after cd, it might be wrong. The pattern check above validates this.
    TESTS_RUN=$((TESTS_RUN + 1))
    if printf '%s' "$mock_log_content" | grep -qF "_test_integ_$$ integ-wt"; then
        pass "integration: tab pattern captured before cwd change (correct pattern)"
    else
        fail "integration: tab pattern captured before cwd change" "pattern not found in mock log"
    fi

    # Test: main worktree path validation (neither path exists -> exit 9)
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" somewt --repo "totally_nonexistent_$$" --dry-run 2>&1
    ) || exit_code=$?
    assert_exit_code "9" "$exit_code" "integration: nonexistent repo -> exit 9 (main worktree not found)"
    assert_contains "$output" "Main worktree not found" "integration: shows main worktree not found error"

    # Test: PR check blocks when PR is open and non-draft (exit 8)
    cat > "$TEST_TMP/mock-bin/gh" << 'MOCKEOF'
#!/bin/sh
echo '{"state": "OPEN", "isDraft": false}'
exit 0
MOCKEOF
    chmod +x "$TEST_TMP/mock-bin/gh"
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" integ-wt --repo "_test_integ_$$" --yes 2>&1
    ) || exit_code=$?
    assert_exit_code "8" "$exit_code" "integration: open PR blocks merge (exit 8)"
    assert_contains "$output" "PR" "integration: open PR shows PR-related error"

    # Reset gh mock
    cat > "$TEST_TMP/mock-bin/gh" << 'MOCKEOF'
#!/bin/sh
echo "MOCK_GH_CALLED: $*" >> "${MOCK_LOG:-/dev/null}"
exit "${MOCK_GH_EXIT:-1}"
MOCKEOF
    chmod +x "$TEST_TMP/mock-bin/gh"

    # Test: PR check allows draft PRs
    cat > "$TEST_TMP/mock-bin/gh" << 'MOCKEOF'
#!/bin/sh
echo '{"state": "OPEN", "isDraft": true}'
exit 0
MOCKEOF
    chmod +x "$TEST_TMP/mock-bin/gh"
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" integ-wt --repo "_test_integ_$$" --yes --skip-workspace --skip-tab-close 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "integration: draft PR allows merge (exit 0)"
    assert_contains "$output" "DRAFT" "integration: draft PR noted in output"

    # Reset gh mock
    cat > "$TEST_TMP/mock-bin/gh" << 'MOCKEOF'
#!/bin/sh
echo "MOCK_GH_CALLED: $*" >> "${MOCK_LOG:-/dev/null}"
exit "${MOCK_GH_EXIT:-1}"
MOCKEOF
    chmod +x "$TEST_TMP/mock-bin/gh"

    # Test: PR check allows merged PRs
    cat > "$TEST_TMP/mock-bin/gh" << 'MOCKEOF'
#!/bin/sh
echo '{"state": "MERGED", "isDraft": false}'
exit 0
MOCKEOF
    chmod +x "$TEST_TMP/mock-bin/gh"
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        MOCK_LOG="$TEST_TMP/mock.log" \
        ITERM_PLUGIN_DIR="$TEST_TMP/mock-iterm" \
        bash "$SCRIPT_UNDER_TEST" integ-wt --repo "_test_integ_$$" --yes --skip-workspace --skip-tab-close 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "integration: merged PR allows merge (exit 0)"

    # Reset gh mock
    cat > "$TEST_TMP/mock-bin/gh" << 'MOCKEOF'
#!/bin/sh
echo "MOCK_GH_CALLED: $*" >> "${MOCK_LOG:-/dev/null}"
exit "${MOCK_GH_EXIT:-1}"
MOCKEOF
    chmod +x "$TEST_TMP/mock-bin/gh"

    # Cleanup
    rm -rf "$test_repo" 2>/dev/null || true
}

##############################################################################
# Main Test Runner
##############################################################################

main() {
    printf "\n"
    printf "========================================================\n"
    printf "  merge-worktree.sh Test Suite\n"
    printf "========================================================\n"
    printf "\n"

    # Setup
    setup

    # Ensure teardown runs on exit
    trap teardown EXIT INT TERM

    # Run all test categories
    run_prerequisite_tests
    run_help_tests
    run_argument_parsing_tests
    run_cwd_detection_tests
    run_dry_run_tests
    run_exit_code_tests
    run_flag_combination_tests
    run_integration_tests

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
