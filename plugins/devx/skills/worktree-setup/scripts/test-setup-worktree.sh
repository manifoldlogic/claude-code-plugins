#!/usr/bin/env zsh
#
# test-setup-worktree.sh - Tests for setup-worktree.sh worktree setup script
#
# DESCRIPTION:
#   Comprehensive test suite for setup-worktree.sh covering:
#   - Argument parsing (valid, invalid, missing, unknown flags)
#   - Help flag output
#   - Dry-run output (all step headers, skip annotations)
#   - Exit codes (all documented codes 0-4)
#   - Flag combinations (--skip-cmux, --skip-workspace)
#   - Prerequisite validation via mocked cmux scripts
#   - Mocked ccwt (crewchief CLI) for worktree creation tests
#
# USAGE:
#   zsh test-setup-worktree.sh           # Run all tests
#   zsh test-setup-worktree.sh --verbose # Verbose output
#   zsh test-setup-worktree.sh --help    # Show help
#
# EXIT CODES:
#   0 - All tests passed
#   1 - One or more tests failed

set -uo pipefail

##############################################################################
# Script Location
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_UNDER_TEST="$SCRIPT_DIR/setup-worktree.sh"

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

    cat > "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-ssh.sh" << 'EOF'
#!/bin/bash
case "$1" in
  new-workspace) echo "OK workspace:3" ;;
  rename-workspace|send|send-key) echo "OK" ;;
  *) echo "unknown command: $1" >&2; exit 1 ;;
esac
EOF
    chmod +x "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-ssh.sh"

    cat > "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-check.sh" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-check.sh"

    # Create mock workspace-folder.sh
    cat > "$TEST_TMP/mock-workspace-folder.sh" << 'EOF'
#!/bin/bash
echo "MOCK_WORKSPACE_FOLDER: $*"
exit 0
EOF
    chmod +x "$TEST_TMP/mock-workspace-folder.sh"

    # Create mock ccwt in mock-bin and prepend to PATH
    mkdir -p "$TEST_TMP/mock-bin"
    cat > "$TEST_TMP/mock-bin/ccwt" << 'EOF'
#!/bin/bash
# Mock ccwt -- capture invocations, return configurable exit code
# Handles: ccwt create <worktree> --repo <repo>
case "${MOCK_CCWT_EXIT:-0}" in
  0) echo "Created worktree at /workspace/repos/${3:-repo}/${1:-worktree}"; exit 0 ;;
  *) echo "Error: failed to create worktree" >&2; exit "${MOCK_CCWT_EXIT}" ;;
esac
EOF
    chmod +x "$TEST_TMP/mock-bin/ccwt"
}

# Run setup-worktree.sh as a subprocess with mocked environment
# Usage: run_script [args...]
# Sets: LAST_EXIT, LAST_OUTPUT
run_script() {
    LAST_EXIT=0
    LAST_OUTPUT=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        CMUX_PLUGIN_DIR="$TEST_TMP/mock-cmux" \
        WORKSPACE_FOLDER_SCRIPT="$TEST_TMP/mock-workspace-folder.sh" \
        DEVCONTAINER_NAME="mock-container" \
        bash "$SCRIPT_UNDER_TEST" "$@" 2>&1
    ) || LAST_EXIT=$?
    debug_msg "run_script exit=$LAST_EXIT args='$*'"
    if [ "$VERBOSE" = "true" ]; then
        debug_msg "output: $(printf '%s' "$LAST_OUTPUT" | head -10)"
    fi
}

# Run setup-worktree.sh with only CMUX_PLUGIN_DIR and DEVCONTAINER_NAME (no mock bin)
# Usage: run_script_no_ccwt [args...]
# Sets: LAST_EXIT, LAST_OUTPUT
run_script_no_ccwt() {
    LAST_EXIT=0
    LAST_OUTPUT=$(
        CMUX_PLUGIN_DIR="$TEST_TMP/mock-cmux" \
        WORKSPACE_FOLDER_SCRIPT="$TEST_TMP/mock-workspace-folder.sh" \
        DEVCONTAINER_NAME="mock-container" \
        bash "$SCRIPT_UNDER_TEST" "$@" 2>&1
    ) || LAST_EXIT=$?
    debug_msg "run_script_no_ccwt exit=$LAST_EXIT args='$*'"
}

##############################################################################
# Category 1: Script Prerequisites
##############################################################################

run_prerequisite_tests() {
    section "1. Script Prerequisites"

    # Test: setup-worktree.sh exists
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -f "$SCRIPT_UNDER_TEST" ]; then
        pass "setup-worktree.sh exists"
    else
        fail "setup-worktree.sh exists" "file not found at $SCRIPT_UNDER_TEST"
        return
    fi

    # Test: setup-worktree.sh is executable or can be run with bash
    TESTS_RUN=$((TESTS_RUN + 1))
    if bash -n "$SCRIPT_UNDER_TEST" 2>/dev/null; then
        pass "setup-worktree.sh has valid syntax"
    else
        fail "setup-worktree.sh has valid syntax" "bash -n failed"
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
    assert_contains "$output" "setup-worktree.sh" "--help mentions script name"
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

    # Test: name starting with hyphen caught as unrecognized option (exit 3)
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" "-badname" --repo testrepo 2>&1) || exit_code=$?
    assert_exit_code "3" "$exit_code" "name starting with hyphen exits 3 (unrecognized option)"
    assert_contains "$output" "Unrecognized option" "hyphen-prefixed name shows unrecognized option error"

    # Test: --skip-tab-close (old flag) exits 3 (unrecognized option)
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo testrepo --skip-tab-close 2>&1) || exit_code=$?
    assert_exit_code "3" "$exit_code" "--skip-tab-close (old flag) exits 3"
    assert_contains "$output" "Unrecognized option" "--skip-tab-close shows unrecognized option error"

    # Test: completely unknown flag exits 3
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo testrepo --nonsense 2>&1) || exit_code=$?
    assert_exit_code "3" "$exit_code" "--nonsense exits 3"
    assert_contains "$output" "Unrecognized option" "--nonsense shows unrecognized option error"

    # Test: no arguments at all exits 1 (missing worktree name)
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" 2>&1) || exit_code=$?
    assert_exit_code "1" "$exit_code" "no arguments exits 1"

    # Test: duplicate positional argument exits 1
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" TICKET-1 TICKET-2 --repo testrepo 2>&1) || exit_code=$?
    assert_exit_code "1" "$exit_code" "duplicate positional arg exits 1"
    assert_contains "$output" "Unexpected positional argument" "duplicate positional shows error"

    # Test: --branch with missing value exits 1
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo testrepo --branch 2>&1) || exit_code=$?
    assert_exit_code "1" "$exit_code" "--branch with missing value exits 1"

    # Test: --workspace with missing value exits 1
    exit_code=0
    output=$(bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo testrepo --workspace 2>&1) || exit_code=$?
    assert_exit_code "1" "$exit_code" "--workspace with missing value exits 1"

    # Test: valid name with special chars (slash) is accepted by arg parser
    # The script does not validate name contents - ccwt would handle that
    exit_code=0
    output=$(
        CMUX_PLUGIN_DIR="$TEST_TMP/mock-cmux" \
        DEVCONTAINER_NAME="mock-container" \
        bash "$SCRIPT_UNDER_TEST" "feat/branch" --repo testrepo --dry-run 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "name with slash accepted in dry-run (no name validation in script)"
}

##############################################################################
# Category 4: Dry-Run Output Tests
##############################################################################

run_dry_run_tests() {
    section "4. Dry-Run Output Tests"

    local exit_code=0
    local output

    # Test: --dry-run exits 0 and shows DRY RUN header
    run_script TICKET-1 --repo crewchief --dry-run
    assert_exit_code "0" "$LAST_EXIT" "--dry-run exits 0"
    assert_contains "$LAST_OUTPUT" "DRY RUN" "--dry-run shows DRY RUN header"
    assert_contains "$LAST_OUTPUT" "Resolved parameters" "--dry-run shows resolved parameters"

    # Test: --dry-run output contains all 7 step headers
    assert_contains "$LAST_OUTPUT" "Step 1:" "--dry-run contains Step 1"
    assert_contains "$LAST_OUTPUT" "Step 2:" "--dry-run contains Step 2"
    assert_contains "$LAST_OUTPUT" "Step 3:" "--dry-run contains Step 3"
    assert_contains "$LAST_OUTPUT" "Step 4:" "--dry-run contains Step 4"
    assert_contains "$LAST_OUTPUT" "Step 5:" "--dry-run contains Step 5"
    assert_contains "$LAST_OUTPUT" "Step 6:" "--dry-run contains Step 6"
    assert_contains "$LAST_OUTPUT" "Step 7:" "--dry-run contains Step 7"

    # Test: --dry-run shows correct parameter values
    assert_contains "$LAST_OUTPUT" "Worktree name: TICKET-1" "--dry-run shows worktree name"
    assert_contains "$LAST_OUTPUT" "Repository: crewchief" "--dry-run shows repository"
    assert_contains "$LAST_OUTPUT" "Base branch: main" "--dry-run shows default branch"

    # Test: --dry-run with custom branch
    run_script TICKET-1 --repo crewchief --branch develop --dry-run
    assert_exit_code "0" "$LAST_EXIT" "--dry-run with --branch develop exits 0"
    assert_contains "$LAST_OUTPUT" "Base branch: develop" "--dry-run shows custom branch"

    # Test: --dry-run shows worktree path
    run_script TICKET-1 --repo crewchief --dry-run
    assert_contains "$LAST_OUTPUT" "/workspace/repos/crewchief/TICKET-1" "--dry-run shows worktree path"

    # Test: --dry-run shows ccwt create command
    assert_contains "$LAST_OUTPUT" "ccwt create TICKET-1 --repo crewchief" "--dry-run shows ccwt command"

    # Test: --dry-run shows cmux-ssh.sh commands
    assert_contains "$LAST_OUTPUT" "cmux-ssh.sh" "--dry-run references cmux-ssh.sh"
    assert_contains "$LAST_OUTPUT" "new-workspace" "--dry-run shows new-workspace step"
    assert_contains "$LAST_OUTPUT" "send-key" "--dry-run shows send-key step"
}

##############################################################################
# Category 5: Skip Flag Tests
##############################################################################

run_skip_flag_tests() {
    section "5. Skip Flag Tests"

    local exit_code=0
    local output

    # Test: --skip-cmux dry-run shows cmux steps as SKIPPED
    run_script TICKET-1 --repo crewchief --skip-cmux --dry-run
    assert_exit_code "0" "$LAST_EXIT" "--skip-cmux --dry-run exits 0"
    assert_contains "$LAST_OUTPUT" "SKIPPED (--skip-cmux)" "--skip-cmux shows SKIPPED annotation for step 4"

    # Verify all cmux steps (4-7) are shown as skipped
    # The dry-run output marks steps 4-7 with "SKIPPED (--skip-cmux)"
    TESTS_RUN=$((TESTS_RUN + 1))
    local skip_count
    skip_count=$(printf '%s' "$LAST_OUTPUT" | grep -c "SKIPPED (--skip-cmux)" || true)
    if [ "$skip_count" -ge 4 ]; then
        pass "--skip-cmux marks all 4 cmux steps as SKIPPED"
    else
        fail "--skip-cmux marks all 4 cmux steps as SKIPPED" "found $skip_count SKIPPED markers, expected 4+"
    fi

    # Test: --skip-workspace dry-run shows workspace step as SKIPPED
    run_script TICKET-1 --repo crewchief --skip-workspace --dry-run
    assert_exit_code "0" "$LAST_EXIT" "--skip-workspace --dry-run exits 0"
    assert_contains "$LAST_OUTPUT" "SKIPPED (--skip-workspace)" "--skip-workspace shows SKIPPED annotation for step 3"

    # Test: both skip flags together
    run_script TICKET-1 --repo crewchief --skip-cmux --skip-workspace --dry-run
    assert_exit_code "0" "$LAST_EXIT" "--skip-cmux --skip-workspace --dry-run exits 0"
    assert_contains "$LAST_OUTPUT" "SKIPPED (--skip-cmux)" "both skips: cmux SKIPPED"
    assert_contains "$LAST_OUTPUT" "SKIPPED (--skip-workspace)" "both skips: workspace SKIPPED"

    # Test: --skip-cmux dry-run still shows steps 1-3
    run_script TICKET-1 --repo crewchief --skip-cmux --dry-run
    assert_contains "$LAST_OUTPUT" "Step 1:" "--skip-cmux still shows Step 1 (prerequisites)"
    assert_contains "$LAST_OUTPUT" "Step 2:" "--skip-cmux still shows Step 2 (create worktree)"
    assert_contains "$LAST_OUTPUT" "Step 3:" "--skip-cmux still shows Step 3 (workspace)"

    # Test: --skip-workspace dry-run still shows cmux steps
    run_script TICKET-1 --repo crewchief --skip-workspace --dry-run
    assert_contains "$LAST_OUTPUT" "Step 4:" "--skip-workspace still shows Step 4 (cmux)"
    assert_contains "$LAST_OUTPUT" "Step 7:" "--skip-workspace still shows Step 7 (claude)"
}

##############################################################################
# Category 6: Prerequisite Validation Tests
##############################################################################

run_prerequisite_validation_tests() {
    section "6. Prerequisite Validation Tests"

    local exit_code=0
    local output

    # Test: CMUX_PLUGIN_DIR pointing to missing directory -> cmux auto-skipped
    # When cmux-check.sh is not found, the script warns and auto-skips cmux
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        CMUX_PLUGIN_DIR="$TEST_TMP/nonexistent-cmux-dir" \
        WORKSPACE_FOLDER_SCRIPT="$TEST_TMP/mock-workspace-folder.sh" \
        DEVCONTAINER_NAME="mock-container" \
        bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo crewchief 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "missing CMUX_PLUGIN_DIR -> script succeeds with cmux auto-skipped"
    assert_contains "$output" "cmux-check.sh not found" "missing CMUX_PLUGIN_DIR shows cmux-check.sh not found warning"
    assert_contains "$output" "cmux workspace creation will be skipped" "missing CMUX_PLUGIN_DIR shows skip message"

    # Test: cmux-check.sh fails -> exit 2 (prerequisite failure)
    # Create a failing cmux-check.sh
    cat > "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-check.sh" << 'FAILEOF'
#!/bin/bash
echo "cmux prerequisites not met" >&2
exit 1
FAILEOF
    chmod +x "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-check.sh"

    run_script TICKET-1 --repo crewchief
    assert_exit_code "2" "$LAST_EXIT" "failing cmux-check.sh exits 2"
    assert_contains "$LAST_OUTPUT" "cmux prerequisite check failed" "failing cmux-check.sh shows error message"

    # Restore passing cmux-check.sh for remaining tests
    cat > "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-check.sh" << 'PASSEOF'
#!/bin/bash
exit 0
PASSEOF
    chmod +x "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-check.sh"

    # Test: cmux-check.sh fails but --skip-cmux bypasses it
    cat > "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-check.sh" << 'FAILEOF'
#!/bin/bash
exit 1
FAILEOF
    chmod +x "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-check.sh"

    run_script TICKET-1 --repo crewchief --skip-cmux
    assert_exit_code "0" "$LAST_EXIT" "--skip-cmux bypasses failing cmux-check.sh"
    assert_contains "$LAST_OUTPUT" "Skipping cmux workspace setup" "--skip-cmux shows skip message"

    # Restore passing cmux-check.sh
    cat > "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-check.sh" << 'PASSEOF'
#!/bin/bash
exit 0
PASSEOF
    chmod +x "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-check.sh"

    # Test: missing workspace-folder.sh -> auto-skips workspace step
    exit_code=0
    output=$(
        PATH="$TEST_TMP/mock-bin:$PATH" \
        CMUX_PLUGIN_DIR="$TEST_TMP/mock-cmux" \
        WORKSPACE_FOLDER_SCRIPT="$TEST_TMP/nonexistent-workspace-folder.sh" \
        DEVCONTAINER_NAME="mock-container" \
        bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo crewchief 2>&1
    ) || exit_code=$?
    assert_exit_code "0" "$exit_code" "missing workspace-folder.sh -> script succeeds with workspace auto-skipped"
    assert_contains "$output" "workspace-folder.sh not found" "missing workspace-folder.sh shows warning"
}

##############################################################################
# Category 7: ccwt Mock Tests
##############################################################################

run_ccwt_tests() {
    section "7. ccwt (Worktree Creation) Tests"

    local exit_code=0
    local output

    # Test: successful worktree creation with all mocks
    run_script TICKET-1 --repo crewchief
    assert_exit_code "0" "$LAST_EXIT" "successful worktree creation exits 0"
    assert_contains "$LAST_OUTPUT" "Worktree Setup Complete" "successful creation shows completion message"
    assert_contains "$LAST_OUTPUT" "Worktree: TICKET-1" "completion shows worktree name"
    assert_contains "$LAST_OUTPUT" "Repository: crewchief" "completion shows repository"

    # Test: ccwt failure -> exit 4
    exit_code=0
    output=$(
        MOCK_CCWT_EXIT=1 \
        PATH="$TEST_TMP/mock-bin:$PATH" \
        CMUX_PLUGIN_DIR="$TEST_TMP/mock-cmux" \
        WORKSPACE_FOLDER_SCRIPT="$TEST_TMP/mock-workspace-folder.sh" \
        DEVCONTAINER_NAME="mock-container" \
        bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo crewchief 2>&1
    ) || exit_code=$?
    assert_exit_code "4" "$exit_code" "ccwt failure exits 4"
    assert_contains "$output" "Worktree creation failed" "ccwt failure shows error message"

    # Test: successful creation with --skip-cmux
    run_script TICKET-1 --repo crewchief --skip-cmux
    assert_exit_code "0" "$LAST_EXIT" "creation with --skip-cmux exits 0"
    assert_contains "$LAST_OUTPUT" "cmux: Skipped" "--skip-cmux shows cmux skipped in summary"

    # Test: successful creation with --skip-workspace
    run_script TICKET-1 --repo crewchief --skip-workspace
    assert_exit_code "0" "$LAST_EXIT" "creation with --skip-workspace exits 0"
    assert_contains "$LAST_OUTPUT" "Skipping VS Code workspace update" "--skip-workspace shows skip in log"

    # Test: successful creation with both skip flags
    run_script TICKET-1 --repo crewchief --skip-cmux --skip-workspace
    assert_exit_code "0" "$LAST_EXIT" "creation with both skips exits 0"
    assert_contains "$LAST_OUTPUT" "Worktree Setup Complete" "both skips still shows completion"

    # Test: worktree name with valid characters (alphanumeric, hyphens, underscores)
    run_script DEVX-1001 --repo crewchief --dry-run
    assert_exit_code "0" "$LAST_EXIT" "DEVX-1001 is a valid name"

    run_script my_feature --repo crewchief --dry-run
    assert_exit_code "0" "$LAST_EXIT" "my_feature is a valid name"

    run_script TICKET123 --repo crewchief --dry-run
    assert_exit_code "0" "$LAST_EXIT" "TICKET123 is a valid name"
}

##############################################################################
# Category 8: Exit Code Summary Tests
##############################################################################

run_exit_code_tests() {
    section "8. Exit Code Summary"

    local exit_code=0

    # Exit 0: --help
    exit_code=0
    bash "$SCRIPT_UNDER_TEST" --help >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "0" "$exit_code" "exit 0: --help"

    # Exit 0: --dry-run
    exit_code=0
    CMUX_PLUGIN_DIR="$TEST_TMP/mock-cmux" \
    DEVCONTAINER_NAME="mock-container" \
    bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo crewchief --dry-run >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "0" "$exit_code" "exit 0: --dry-run"

    # Exit 1: missing worktree name
    exit_code=0
    bash "$SCRIPT_UNDER_TEST" --repo crewchief >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "1" "$exit_code" "exit 1: missing worktree name"

    # Exit 1: missing --repo
    exit_code=0
    bash "$SCRIPT_UNDER_TEST" TICKET-1 >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "1" "$exit_code" "exit 1: missing --repo"

    # Exit 3: unrecognized option
    exit_code=0
    bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo crewchief --unknown >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "3" "$exit_code" "exit 3: unrecognized option"

    # Exit 3: --skip-tab-close (old flag)
    exit_code=0
    bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo crewchief --skip-tab-close >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "3" "$exit_code" "exit 3: --skip-tab-close (old flag)"

    # Exit 2: cmux prerequisite failure
    cat > "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-check.sh" << 'FAILEOF'
#!/bin/bash
exit 1
FAILEOF
    chmod +x "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-check.sh"

    exit_code=0
    PATH="$TEST_TMP/mock-bin:$PATH" \
    CMUX_PLUGIN_DIR="$TEST_TMP/mock-cmux" \
    WORKSPACE_FOLDER_SCRIPT="$TEST_TMP/mock-workspace-folder.sh" \
    DEVCONTAINER_NAME="mock-container" \
    bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo crewchief >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "2" "$exit_code" "exit 2: cmux prerequisite failure"

    # Restore passing cmux-check.sh
    cat > "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-check.sh" << 'PASSEOF'
#!/bin/bash
exit 0
PASSEOF
    chmod +x "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-check.sh"

    # Exit 4: ccwt creation failure
    exit_code=0
    MOCK_CCWT_EXIT=1 \
    PATH="$TEST_TMP/mock-bin:$PATH" \
    CMUX_PLUGIN_DIR="$TEST_TMP/mock-cmux" \
    WORKSPACE_FOLDER_SCRIPT="$TEST_TMP/mock-workspace-folder.sh" \
    DEVCONTAINER_NAME="mock-container" \
    bash "$SCRIPT_UNDER_TEST" TICKET-1 --repo crewchief >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "4" "$exit_code" "exit 4: ccwt creation failure"
}

##############################################################################
# Category 9: cmux-ssh.sh Mock Validation Tests
##############################################################################

run_cmux_mock_tests() {
    section "9. cmux-ssh.sh Mock Validation"

    local exit_code=0
    local output

    # Test: mock cmux-ssh.sh returns OK workspace:3 for new-workspace
    exit_code=0
    output=$(bash "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-ssh.sh" new-workspace 2>&1) || exit_code=$?
    assert_exit_code "0" "$exit_code" "mock cmux-ssh.sh new-workspace exits 0"
    assert_contains "$output" "OK workspace:3" "mock cmux-ssh.sh new-workspace returns OK workspace:3"

    # Test: mock cmux-ssh.sh returns OK for rename-workspace
    exit_code=0
    output=$(bash "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-ssh.sh" rename-workspace workspace:3 TICKET-1 2>&1) || exit_code=$?
    assert_exit_code "0" "$exit_code" "mock cmux-ssh.sh rename-workspace exits 0"
    assert_contains "$output" "OK" "mock cmux-ssh.sh rename-workspace returns OK"

    # Test: mock cmux-ssh.sh returns OK for send
    exit_code=0
    output=$(bash "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-ssh.sh" send workspace:3 "docker exec -it mock /bin/zsh" 2>&1) || exit_code=$?
    assert_exit_code "0" "$exit_code" "mock cmux-ssh.sh send exits 0"

    # Test: mock cmux-ssh.sh returns OK for send-key
    exit_code=0
    output=$(bash "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-ssh.sh" send-key workspace:3 enter 2>&1) || exit_code=$?
    assert_exit_code "0" "$exit_code" "mock cmux-ssh.sh send-key exits 0"

    # Test: mock cmux-ssh.sh returns error for unknown command
    exit_code=0
    output=$(bash "$TEST_TMP/mock-cmux/skills/terminal-management/scripts/cmux-ssh.sh" bad-command 2>&1) || exit_code=$?
    assert_exit_code "1" "$exit_code" "mock cmux-ssh.sh unknown command exits 1"
    assert_contains "$output" "unknown command" "mock cmux-ssh.sh unknown command shows error"

    # Test: mock ccwt returns success by default
    exit_code=0
    output=$(bash "$TEST_TMP/mock-bin/ccwt" create TICKET-1 --repo crewchief 2>&1) || exit_code=$?
    assert_exit_code "0" "$exit_code" "mock ccwt default exits 0"
    assert_contains "$output" "Created worktree" "mock ccwt shows creation message"

    # Test: mock ccwt returns error when MOCK_CCWT_EXIT=1
    exit_code=0
    output=$(MOCK_CCWT_EXIT=1 bash "$TEST_TMP/mock-bin/ccwt" create TICKET-1 --repo crewchief 2>&1) || exit_code=$?
    assert_exit_code "1" "$exit_code" "mock ccwt with MOCK_CCWT_EXIT=1 exits 1"
    assert_contains "$output" "Error: failed to create worktree" "mock ccwt failure shows error"
}

##############################################################################
# Main Test Runner
##############################################################################

main() {
    printf "\n"
    printf "========================================================\n"
    printf "  setup-worktree.sh Test Suite\n"
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
    run_dry_run_tests
    run_skip_flag_tests
    run_prerequisite_validation_tests
    run_ccwt_tests
    run_exit_code_tests
    run_cmux_mock_tests

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
