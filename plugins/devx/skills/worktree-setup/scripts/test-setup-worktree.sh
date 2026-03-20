#!/usr/bin/env bash
#
# test-setup-worktree.sh - Tests for setup-worktree.sh
#
# DESCRIPTION:
#   Unit and integration tests for setup-worktree.sh. Covers argument parsing,
#   validation, dry-run output, prerequisite checks, and the cmux polling
#   integration introduced by CMUXWAIT. All external dependencies are mocked
#   via temp-directory scripts and environment variables.
#
# USAGE:
#   bash test-setup-worktree.sh
#
# EXIT CODES:
#   0 - All tests passed
#   1 - One or more tests failed

set -euo pipefail

##############################################################################
# Test Configuration
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/setup-worktree.sh"

# Locate the real cmux-wait.sh so we can copy it into the mock plugin dir
CMUX_WAIT_REAL="$(cd "$SCRIPT_DIR/../../../../cmux/skills/terminal-management/scripts" 2>/dev/null && pwd)/cmux-wait.sh"

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

    # Create mock bin directory
    mkdir -p "$TEST_TMPDIR/bin"
    mkdir -p "$TEST_TMPDIR/cmux-plugin/skills/terminal-management/scripts"
    mkdir -p "$TEST_TMPDIR/repos/myrepo"

    # Mock crewchief
    cat > "$TEST_TMPDIR/bin/crewchief" <<'MOCKEOF'
#!/usr/bin/env bash
# Mock crewchief - always succeeds
if [ "${1:-}" = "worktree" ] && [ "${2:-}" = "create" ]; then
    WORKTREE_NAME="${3:-}"
    exit 0
fi
exit 0
MOCKEOF
    chmod +x "$TEST_TMPDIR/bin/crewchief"

    # Mock workspace-folder.sh
    cat > "$TEST_TMPDIR/workspace-folder.sh" <<'MOCKEOF'
#!/usr/bin/env bash
# Mock workspace-folder.sh - always succeeds
exit 0
MOCKEOF
    chmod +x "$TEST_TMPDIR/workspace-folder.sh"

    # Mock cmux-check.sh
    cat > "$TEST_TMPDIR/cmux-plugin/skills/terminal-management/scripts/cmux-check.sh" <<'MOCKEOF'
#!/usr/bin/env bash
# Mock cmux-check.sh - always succeeds
exit 0
MOCKEOF
    chmod +x "$TEST_TMPDIR/cmux-plugin/skills/terminal-management/scripts/cmux-check.sh"

    # Mock cmux-ssh.sh with all subcommands
    cat > "$TEST_TMPDIR/cmux-plugin/skills/terminal-management/scripts/cmux-ssh.sh" <<'MOCKEOF'
#!/usr/bin/env bash
# Mock cmux-ssh.sh - handles all subcommands used by setup-worktree.sh
cmd="${1:-}"
shift || true
case "$cmd" in
    new-workspace)
        echo "workspace:3 created"
        ;;
    rename-workspace)
        exit 0
        ;;
    send)
        exit 0
        ;;
    send-key)
        exit 0
        ;;
    list-workspaces)
        echo "workspace:3 test [selected]"
        ;;
    read-screen)
        echo "user@container:/workspace $ "
        ;;
    *)
        echo "Error: unknown command '$cmd'" >&2
        exit 1
        ;;
esac
MOCKEOF
    chmod +x "$TEST_TMPDIR/cmux-plugin/skills/terminal-management/scripts/cmux-ssh.sh"

    # Copy the real cmux-wait.sh into the mock plugin dir so setup-worktree.sh
    # can source it for polling functions
    if [ -f "$CMUX_WAIT_REAL" ]; then
        cp "$CMUX_WAIT_REAL" "$TEST_TMPDIR/cmux-plugin/skills/terminal-management/scripts/cmux-wait.sh"
    fi

    # Mock docker
    cat > "$TEST_TMPDIR/bin/docker" <<'MOCKEOF'
#!/usr/bin/env bash
# Mock docker
if [ "${1:-}" = "ps" ]; then
    if echo "$*" | grep -q -- "--filter"; then
        echo "mock-devcontainer-1"
    fi
fi
exit 0
MOCKEOF
    chmod +x "$TEST_TMPDIR/bin/docker"
}

teardown() {
    if [ -n "${TEST_TMPDIR:-}" ] && [ -d "${TEST_TMPDIR:-}" ]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# Ensure teardown runs even on failure
trap teardown EXIT

##############################################################################
# Helper: Run setup-worktree.sh with mocked environment
##############################################################################

# Run setup-worktree.sh in a subshell with all mocks configured.
# Args: all args are passed to setup-worktree.sh
# Returns: exit code of the script
# Stdout+stderr captured and stored in global $LAST_OUTPUT
run_setup() {
    LAST_OUTPUT=$(
        PATH="$TEST_TMPDIR/bin:$PATH" \
        CMUX_PLUGIN_DIR="$TEST_TMPDIR/cmux-plugin" \
        WORKSPACE_FOLDER_SCRIPT="$TEST_TMPDIR/workspace-folder.sh" \
        WORKSPACE_REPOS_ROOT="$TEST_TMPDIR/repos" \
        DEVCONTAINER_NAME="mock-devcontainer-1" \
        CMUX_WAIT_WS_TIMEOUT="${CMUX_WAIT_WS_TIMEOUT:-2}" \
        CMUX_WAIT_WS_INTERVAL="${CMUX_WAIT_WS_INTERVAL:-0.1}" \
        CMUX_WAIT_PROMPT_TIMEOUT="${CMUX_WAIT_PROMPT_TIMEOUT:-2}" \
        CMUX_WAIT_PROMPT_INTERVAL="${CMUX_WAIT_PROMPT_INTERVAL:-0.1}" \
        bash "$SETUP_SCRIPT" "$@" 2>&1
    )
    return $?
}

##############################################################################
# Section A: Argument Parsing & Validation Tests
##############################################################################

test_help_flag() {
    run_test "--help shows usage"

    local output
    output=$(bash "$SETUP_SCRIPT" --help 2>&1) || true

    if echo "$output" | grep -q "Usage:"; then
        pass "--help shows usage text"
    else
        fail "--help does not show usage text"
    fi
}

test_missing_worktree_name() {
    run_test "Missing worktree name exits 1"

    if bash "$SETUP_SCRIPT" --repo myrepo 2>/dev/null; then
        fail "Should exit non-zero when worktree name is missing"
    else
        local exit_code=$?
        if [ "$exit_code" -eq 1 ]; then
            pass "Exit code 1 for missing worktree name"
        else
            fail "Expected exit code 1, got $exit_code"
        fi
    fi
}

test_missing_repo() {
    run_test "Missing --repo exits 1"

    if bash "$SETUP_SCRIPT" TICKET-1 2>/dev/null; then
        fail "Should exit non-zero when --repo is missing"
    else
        local exit_code=$?
        if [ "$exit_code" -eq 1 ]; then
            pass "Exit code 1 for missing --repo"
        else
            fail "Expected exit code 1, got $exit_code"
        fi
    fi
}

test_unrecognized_option() {
    run_test "Unrecognized option exits 3"

    if bash "$SETUP_SCRIPT" TICKET-1 --repo myrepo --badopt 2>/dev/null; then
        fail "Should exit non-zero for unrecognized option"
    else
        local exit_code=$?
        if [ "$exit_code" -eq 3 ]; then
            pass "Exit code 3 for unrecognized option"
        else
            fail "Expected exit code 3, got $exit_code"
        fi
    fi
}

test_invalid_worktree_name() {
    run_test "Invalid worktree name (starts with hyphen) exits 1"

    if bash "$SETUP_SCRIPT" "-bad" --repo myrepo 2>/dev/null; then
        fail "Should exit non-zero for invalid worktree name"
    else
        pass "Non-zero exit for invalid worktree name"
    fi
}

test_valid_worktree_names() {
    run_test "Valid worktree names accepted"

    # Dry-run so we don't need all mocks
    local output
    output=$(bash "$SETUP_SCRIPT" TICKET-1 --repo myrepo --dry-run 2>&1) || true
    if echo "$output" | grep -q "TICKET-1"; then
        pass "TICKET-1 accepted as valid name"
    else
        fail "TICKET-1 not accepted"
    fi

    output=$(bash "$SETUP_SCRIPT" my_worktree --repo myrepo --dry-run 2>&1) || true
    if echo "$output" | grep -q "my_worktree"; then
        pass "my_worktree accepted as valid name"
    else
        fail "my_worktree not accepted"
    fi
}

test_repo_flag_variants() {
    run_test "Short -r flag works for --repo"

    local output
    output=$(bash "$SETUP_SCRIPT" TICKET-1 -r myrepo --dry-run 2>&1) || true
    if echo "$output" | grep -q "myrepo"; then
        pass "-r flag sets repository"
    else
        fail "-r flag did not set repository"
    fi
}

test_branch_flag() {
    run_test "--branch / -b sets base branch"

    local output
    output=$(bash "$SETUP_SCRIPT" TICKET-1 --repo myrepo --branch develop --dry-run 2>&1) || true
    if echo "$output" | grep -q "develop"; then
        pass "--branch develop shown in dry-run output"
    else
        fail "--branch develop not shown in dry-run output"
    fi

    output=$(bash "$SETUP_SCRIPT" TICKET-1 --repo myrepo -b release --dry-run 2>&1) || true
    if echo "$output" | grep -q "release"; then
        pass "-b release shown in dry-run output"
    else
        fail "-b release not shown in dry-run output"
    fi
}

test_workspace_flag() {
    run_test "--workspace / -w sets workspace file"

    local output
    output=$(bash "$SETUP_SCRIPT" TICKET-1 --repo myrepo -w /my/file.code-workspace --dry-run 2>&1) || true
    if echo "$output" | grep -q "/my/file.code-workspace"; then
        pass "-w flag sets workspace file in dry-run output"
    else
        fail "-w flag did not set workspace file"
    fi
}

test_skip_cmux_flag() {
    run_test "--skip-cmux flag shows skip in dry-run"

    local output
    output=$(bash "$SETUP_SCRIPT" TICKET-1 --repo myrepo --skip-cmux --dry-run 2>&1) || true
    if echo "$output" | grep -q "SKIPPED.*--skip-cmux"; then
        pass "--skip-cmux flag acknowledged in dry-run"
    else
        fail "--skip-cmux flag not reflected in dry-run output"
    fi
}

test_skip_workspace_flag() {
    run_test "--skip-workspace flag shows skip in dry-run"

    local output
    output=$(bash "$SETUP_SCRIPT" TICKET-1 --repo myrepo --skip-workspace --dry-run 2>&1) || true
    if echo "$output" | grep -q "SKIPPED.*--skip-workspace"; then
        pass "--skip-workspace flag acknowledged in dry-run"
    else
        fail "--skip-workspace flag not reflected in dry-run output"
    fi
}

##############################################################################
# Section B: Dry-Run Tests
##############################################################################

test_dry_run_header() {
    run_test "Dry-run shows header and resolved parameters"

    local output
    output=$(bash "$SETUP_SCRIPT" TICKET-1 --repo myrepo --dry-run 2>&1) || true

    if echo "$output" | grep -q "DRY RUN"; then
        pass "DRY RUN header present"
    else
        fail "DRY RUN header missing"
    fi

    if echo "$output" | grep -q "Resolved parameters"; then
        pass "Resolved parameters section present"
    else
        fail "Resolved parameters section missing"
    fi
}

test_dry_run_shows_all_steps() {
    run_test "Dry-run shows steps 1-7"

    local output
    output=$(bash "$SETUP_SCRIPT" TICKET-1 --repo myrepo --dry-run 2>&1) || true

    local step
    for step in 1 2 3 4 5 6 7; do
        if echo "$output" | grep -q "Step $step"; then
            pass "Step $step mentioned in dry-run"
        else
            fail "Step $step missing from dry-run output"
        fi
    done
}

test_dry_run_exits_zero() {
    run_test "Dry-run exits 0"

    if bash "$SETUP_SCRIPT" TICKET-1 --repo myrepo --dry-run > /dev/null 2>&1; then
        pass "Dry-run exits 0"
    else
        fail "Dry-run exited non-zero"
    fi
}

test_dry_run_default_branch() {
    run_test "Dry-run shows default branch main"

    local output
    output=$(bash "$SETUP_SCRIPT" TICKET-1 --repo myrepo --dry-run 2>&1) || true

    if echo "$output" | grep -q "Base branch: main"; then
        pass "Default branch main shown"
    else
        fail "Default branch main not shown"
    fi
}

test_dry_run_worktree_path() {
    run_test "Dry-run shows computed worktree path"

    local output
    output=$(bash "$SETUP_SCRIPT" TICKET-1 --repo myrepo --dry-run 2>&1) || true

    if echo "$output" | grep -q "myrepo/TICKET-1"; then
        pass "Worktree path contains repo/name"
    else
        fail "Worktree path not shown correctly"
    fi
}

##############################################################################
# Section C: Prerequisite Validation Tests
##############################################################################

test_missing_crewchief() {
    run_test "Missing crewchief CLI exits 2"

    # Use empty PATH to simulate missing crewchief
    if PATH="/usr/bin:/bin" \
       CMUX_PLUGIN_DIR="$TEST_TMPDIR/cmux-plugin" \
       WORKSPACE_FOLDER_SCRIPT="$TEST_TMPDIR/workspace-folder.sh" \
       WORKSPACE_REPOS_ROOT="$TEST_TMPDIR/repos" \
       bash "$SETUP_SCRIPT" TICKET-1 --repo myrepo 2>/dev/null; then
        fail "Should exit non-zero when crewchief missing"
    else
        local exit_code=$?
        if [ "$exit_code" -eq 2 ]; then
            pass "Exit code 2 when crewchief missing"
        else
            fail "Expected exit code 2, got $exit_code"
        fi
    fi
}

test_missing_workspace_folder_script() {
    run_test "Missing workspace-folder.sh auto-skips workspace step"

    local output
    output=$(
        PATH="$TEST_TMPDIR/bin:$PATH" \
        CMUX_PLUGIN_DIR="$TEST_TMPDIR/cmux-plugin" \
        WORKSPACE_FOLDER_SCRIPT="/nonexistent/workspace-folder.sh" \
        WORKSPACE_REPOS_ROOT="$TEST_TMPDIR/repos" \
        DEVCONTAINER_NAME="mock-devcontainer-1" \
        CMUX_WAIT_WS_TIMEOUT=2 \
        CMUX_WAIT_WS_INTERVAL=0.1 \
        CMUX_WAIT_PROMPT_TIMEOUT=2 \
        CMUX_WAIT_PROMPT_INTERVAL=0.1 \
        bash "$SETUP_SCRIPT" TICKET-1 --repo myrepo 2>&1
    ) || true

    if echo "$output" | grep -q "workspace-folder.sh not found"; then
        pass "Warning about missing workspace-folder.sh shown"
    else
        fail "No warning about missing workspace-folder.sh"
    fi
}

test_missing_cmux_check_skips_cmux() {
    run_test "Missing cmux-check.sh auto-skips cmux steps"

    # Remove cmux-check.sh
    local backup="$TEST_TMPDIR/cmux-check-backup.sh"
    mv "$TEST_TMPDIR/cmux-plugin/skills/terminal-management/scripts/cmux-check.sh" "$backup"

    local output
    output=$(
        PATH="$TEST_TMPDIR/bin:$PATH" \
        CMUX_PLUGIN_DIR="$TEST_TMPDIR/cmux-plugin" \
        WORKSPACE_FOLDER_SCRIPT="$TEST_TMPDIR/workspace-folder.sh" \
        WORKSPACE_REPOS_ROOT="$TEST_TMPDIR/repos" \
        DEVCONTAINER_NAME="mock-devcontainer-1" \
        bash "$SETUP_SCRIPT" TICKET-1 --repo myrepo 2>&1
    ) || true

    # Restore
    mv "$backup" "$TEST_TMPDIR/cmux-plugin/skills/terminal-management/scripts/cmux-check.sh"

    if echo "$output" | grep -q "cmux-check.sh not found"; then
        pass "Warning about missing cmux-check.sh shown"
    else
        fail "No warning about missing cmux-check.sh"
    fi
}

##############################################################################
# Section D: Full Run Tests (with all mocks)
##############################################################################

test_full_run_skip_cmux() {
    run_test "Full run with --skip-cmux completes successfully"

    if run_setup TICKET-1 --repo myrepo --skip-cmux; then
        pass "Setup completed with --skip-cmux"
    else
        fail "Setup failed with --skip-cmux (exit code $?)"
    fi

    if echo "$LAST_OUTPUT" | grep -q "Worktree Setup Complete"; then
        pass "Success summary shown"
    else
        fail "Success summary missing"
    fi
}

test_full_run_skip_workspace() {
    run_test "Full run with --skip-workspace completes successfully"

    if run_setup TICKET-1 --repo myrepo --skip-workspace; then
        pass "Setup completed with --skip-workspace"
    else
        fail "Setup failed with --skip-workspace (exit code $?)"
    fi

    if echo "$LAST_OUTPUT" | grep -q "Skipping VS Code workspace"; then
        pass "Workspace skip message shown"
    else
        fail "Workspace skip message missing"
    fi
}

test_full_run_both_skips() {
    run_test "Full run with both --skip-cmux and --skip-workspace"

    if run_setup TICKET-1 --repo myrepo --skip-cmux --skip-workspace; then
        pass "Setup completed with both skips"
    else
        fail "Setup failed with both skips"
    fi
}

test_full_run_shows_worktree_path() {
    run_test "Full run output includes worktree path"

    run_setup TICKET-1 --repo myrepo --skip-cmux || true

    if echo "$LAST_OUTPUT" | grep -q "myrepo/TICKET-1"; then
        pass "Worktree path in output"
    else
        fail "Worktree path missing from output"
    fi
}

test_verbose_flag() {
    run_test "--verbose flag is accepted without error"

    if run_setup TICKET-1 --repo myrepo --skip-cmux --verbose; then
        pass "--verbose flag accepted"
    else
        fail "--verbose flag caused error"
    fi
}

test_worktree_creation_failure() {
    run_test "Worktree creation failure exits 4"

    # Create a failing crewchief
    cat > "$TEST_TMPDIR/bin/crewchief" <<'MOCKEOF'
#!/usr/bin/env bash
exit 1
MOCKEOF
    chmod +x "$TEST_TMPDIR/bin/crewchief"

    if run_setup TICKET-1 --repo myrepo --skip-cmux; then
        fail "Should exit non-zero when crewchief fails"
    else
        local exit_code=$?
        if [ "$exit_code" -eq 4 ]; then
            pass "Exit code 4 on worktree creation failure"
        else
            fail "Expected exit code 4, got $exit_code"
        fi
    fi

    # Restore working crewchief
    cat > "$TEST_TMPDIR/bin/crewchief" <<'MOCKEOF'
#!/usr/bin/env bash
exit 0
MOCKEOF
    chmod +x "$TEST_TMPDIR/bin/crewchief"
}

test_summary_shows_repo() {
    run_test "Summary section shows repository name"

    run_setup TICKET-1 --repo myrepo --skip-cmux || true

    if echo "$LAST_OUTPUT" | grep -q "Repository: myrepo"; then
        pass "Repository name in summary"
    else
        fail "Repository name missing from summary"
    fi
}

test_summary_shows_branch() {
    run_test "Summary section shows branch"

    run_setup TICKET-1 --repo myrepo --branch develop --skip-cmux || true

    if echo "$LAST_OUTPUT" | grep -q "Branch: develop"; then
        pass "Branch shown in summary"
    else
        fail "Branch missing from summary"
    fi
}

# Existing test count before CMUXWAIT.2002: 25

##############################################################################
# Section E: CMUXWAIT Integration Tests (CMUXWAIT.2002)
##############################################################################

test_integration_happy_path() {
    run_test "Integration: happy path with polling mocks returning ready responses"

    # The default mock cmux-ssh.sh returns workspace:3 for list-workspaces
    # and a prompt-like string for read-screen. cmux-wait.sh is sourced by
    # setup-worktree.sh when CMUX_WAIT_SCRIPT points to the real file.

    if run_setup TICKET-HP --repo myrepo; then
        pass "Happy-path integration run exits 0"
    else
        fail "Happy-path integration run exited non-zero ($?)"
    fi

    if echo "$LAST_OUTPUT" | grep -q "cmux workspace created"; then
        pass "Workspace creation logged"
    else
        fail "Workspace creation message missing"
    fi

    if echo "$LAST_OUTPUT" | grep -q "Worktree Setup Complete"; then
        pass "Setup completed successfully"
    else
        fail "Setup complete message missing"
    fi

    if echo "$LAST_OUTPUT" | grep -q "Claude launched\|cmux: Workspace ready"; then
        pass "cmux steps completed"
    else
        fail "cmux completion messages missing"
    fi
}

test_integration_workspace_polling_timeout() {
    run_test "Integration: workspace polling timeout logs warning and exits 0"

    # Override the mock cmux-ssh.sh to return a non-matching workspace for
    # list-workspaces, triggering a timeout in cmux_wait_workspace.
    cat > "$TEST_TMPDIR/cmux-plugin/skills/terminal-management/scripts/cmux-ssh.sh" <<'MOCKEOF'
#!/usr/bin/env bash
cmd="${1:-}"
shift || true
case "$cmd" in
    new-workspace)
        echo "workspace:3 created"
        ;;
    rename-workspace)
        exit 0
        ;;
    send)
        exit 0
        ;;
    send-key)
        exit 0
        ;;
    list-workspaces)
        # Return a workspace ID that does NOT match workspace:3 to force timeout
        echo "workspace:99 other"
        ;;
    read-screen)
        echo "user@container:/workspace $ "
        ;;
    *)
        echo "Error: unknown command '$cmd'" >&2
        exit 1
        ;;
esac
MOCKEOF
    chmod +x "$TEST_TMPDIR/cmux-plugin/skills/terminal-management/scripts/cmux-ssh.sh"

    local output
    local exit_code=0
    output=$(
        PATH="$TEST_TMPDIR/bin:$PATH" \
        CMUX_PLUGIN_DIR="$TEST_TMPDIR/cmux-plugin" \
        WORKSPACE_FOLDER_SCRIPT="$TEST_TMPDIR/workspace-folder.sh" \
        WORKSPACE_REPOS_ROOT="$TEST_TMPDIR/repos" \
        DEVCONTAINER_NAME="mock-devcontainer-1" \
        CMUX_WAIT_WS_TIMEOUT=0 \
        CMUX_WAIT_WS_INTERVAL=0.1 \
        CMUX_WAIT_PROMPT_TIMEOUT=2 \
        CMUX_WAIT_PROMPT_INTERVAL=0.1 \
        bash "$SETUP_SCRIPT" TICKET-WST --repo myrepo 2>&1
    ) || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        pass "Script exits 0 despite workspace polling timeout"
    else
        fail "Script exited $exit_code instead of 0 on workspace polling timeout"
    fi

    if echo "$output" | grep -qi "timeout\|readiness"; then
        pass "Timeout/readiness warning message present"
    else
        fail "No timeout/readiness warning in output"
    fi

    # Restore default mock
    setup_default_cmux_ssh_mock
}

test_integration_prompt_polling_timeout() {
    run_test "Integration: prompt polling timeout logs warning and exits 0"

    # Override read-screen to return non-prompt content
    cat > "$TEST_TMPDIR/cmux-plugin/skills/terminal-management/scripts/cmux-ssh.sh" <<'MOCKEOF'
#!/usr/bin/env bash
cmd="${1:-}"
shift || true
case "$cmd" in
    new-workspace)
        echo "workspace:3 created"
        ;;
    rename-workspace)
        exit 0
        ;;
    send)
        exit 0
        ;;
    send-key)
        exit 0
        ;;
    list-workspaces)
        echo "workspace:3 test [selected]"
        ;;
    read-screen)
        # Return something that does NOT look like a shell prompt
        echo "Loading system services..."
        ;;
    *)
        echo "Error: unknown command '$cmd'" >&2
        exit 1
        ;;
esac
MOCKEOF
    chmod +x "$TEST_TMPDIR/cmux-plugin/skills/terminal-management/scripts/cmux-ssh.sh"

    local output
    local exit_code=0
    output=$(
        PATH="$TEST_TMPDIR/bin:$PATH" \
        CMUX_PLUGIN_DIR="$TEST_TMPDIR/cmux-plugin" \
        WORKSPACE_FOLDER_SCRIPT="$TEST_TMPDIR/workspace-folder.sh" \
        WORKSPACE_REPOS_ROOT="$TEST_TMPDIR/repos" \
        DEVCONTAINER_NAME="mock-devcontainer-1" \
        CMUX_WAIT_WS_TIMEOUT=2 \
        CMUX_WAIT_WS_INTERVAL=0.1 \
        CMUX_WAIT_PROMPT_TIMEOUT=0 \
        CMUX_WAIT_PROMPT_INTERVAL=0.1 \
        bash "$SETUP_SCRIPT" TICKET-PT --repo myrepo 2>&1
    ) || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        pass "Script exits 0 despite prompt polling timeout"
    else
        fail "Script exited $exit_code instead of 0 on prompt polling timeout"
    fi

    if echo "$output" | grep -qi "timeout\|readiness"; then
        pass "Timeout/readiness warning message present"
    else
        fail "No timeout/readiness warning in output"
    fi

    # Restore default mock
    setup_default_cmux_ssh_mock
}

test_integration_missing_cmux_wait() {
    run_test "Integration: missing cmux-wait.sh uses stub fallback"

    # Point CMUX_WAIT_SCRIPT to nonexistent file.
    # setup-worktree.sh computes this from CMUX_PLUGIN_DIR, so we need to
    # remove the real cmux-wait.sh from the mock directory temporarily.
    # Since our mock plugin dir doesn't have cmux-wait.sh, the script should
    # fall back to stubs as long as cmux-wait.sh doesn't exist there.

    # Ensure cmux-wait.sh does NOT exist in our mock plugin dir
    rm -f "$TEST_TMPDIR/cmux-plugin/skills/terminal-management/scripts/cmux-wait.sh"

    local output
    local exit_code=0
    output=$(
        PATH="$TEST_TMPDIR/bin:$PATH" \
        CMUX_PLUGIN_DIR="$TEST_TMPDIR/cmux-plugin" \
        WORKSPACE_FOLDER_SCRIPT="$TEST_TMPDIR/workspace-folder.sh" \
        WORKSPACE_REPOS_ROOT="$TEST_TMPDIR/repos" \
        DEVCONTAINER_NAME="mock-devcontainer-1" \
        bash "$SETUP_SCRIPT" TICKET-STUB --repo myrepo 2>&1
    ) || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        pass "Script exits 0 with missing cmux-wait.sh (stub fallback)"
    else
        fail "Script exited $exit_code with missing cmux-wait.sh"
    fi

    if echo "$output" | grep -qi "falling back\|not found\|sleep-based"; then
        pass "Fallback warning message present"
    else
        fail "No fallback warning in output"
    fi

    if echo "$output" | grep -q "Worktree Setup Complete"; then
        pass "Script completed despite missing cmux-wait.sh"
    else
        fail "Script did not complete with missing cmux-wait.sh"
    fi
}

test_integration_dry_run_no_sleep() {
    run_test "Integration: --dry-run does not contain sleep references for Steps 4-6"

    local output
    output=$(bash "$SETUP_SCRIPT" TICKET-DRY --repo myrepo --dry-run 2>&1) || true

    # Extract only Steps 4-6 section from the output
    local steps_4_to_6
    steps_4_to_6=$(echo "$output" | sed -n '/Step 4/,/Step 7/p')

    if echo "$steps_4_to_6" | grep -q "sleep 0\.5"; then
        fail "Steps 4-6 dry-run output contains 'sleep 0.5'"
    else
        pass "Steps 4-6 dry-run output does not contain 'sleep 0.5'"
    fi

    if echo "$steps_4_to_6" | grep -q "sleep 2"; then
        fail "Steps 4-6 dry-run output contains 'sleep 2'"
    else
        pass "Steps 4-6 dry-run output does not contain 'sleep 2'"
    fi

    # Verify polling is mentioned instead
    if echo "$steps_4_to_6" | grep -qi "polling\|readiness\|[Ww]ait"; then
        pass "Steps 4-6 mention polling/readiness/wait instead of sleep"
    else
        fail "Steps 4-6 do not mention polling/readiness/wait"
    fi
}

##############################################################################
# Helper: Restore default mock cmux-ssh.sh
##############################################################################

setup_default_cmux_ssh_mock() {
    cat > "$TEST_TMPDIR/cmux-plugin/skills/terminal-management/scripts/cmux-ssh.sh" <<'MOCKEOF'
#!/usr/bin/env bash
cmd="${1:-}"
shift || true
case "$cmd" in
    new-workspace)
        echo "workspace:3 created"
        ;;
    rename-workspace)
        exit 0
        ;;
    send)
        exit 0
        ;;
    send-key)
        exit 0
        ;;
    list-workspaces)
        echo "workspace:3 test [selected]"
        ;;
    read-screen)
        echo "user@container:/workspace $ "
        ;;
    *)
        echo "Error: unknown command '$cmd'" >&2
        exit 1
        ;;
esac
MOCKEOF
    chmod +x "$TEST_TMPDIR/cmux-plugin/skills/terminal-management/scripts/cmux-ssh.sh"
}

##############################################################################
# Test Runner
##############################################################################

run_all_tests() {
    echo ""
    echo "=========================================="
    echo "  setup-worktree.sh Tests"
    echo "=========================================="
    echo ""
    echo "Script under test: $SETUP_SCRIPT"
    echo ""

    setup

    # Section A: Argument parsing & validation (14 tests)
    test_help_flag
    test_missing_worktree_name
    test_missing_repo
    test_unrecognized_option
    test_invalid_worktree_name
    test_valid_worktree_names
    test_repo_flag_variants
    test_branch_flag
    test_workspace_flag
    test_skip_cmux_flag
    test_skip_workspace_flag

    # Section B: Dry-run tests (7 tests)
    test_dry_run_header
    test_dry_run_shows_all_steps
    test_dry_run_exits_zero
    test_dry_run_default_branch
    test_dry_run_worktree_path

    # Section C: Prerequisite validation (3 tests)
    test_missing_crewchief
    test_missing_workspace_folder_script
    test_missing_cmux_check_skips_cmux

    # Section D: Full run tests (8 tests)
    test_full_run_skip_cmux
    test_full_run_skip_workspace
    test_full_run_both_skips
    test_full_run_shows_worktree_path
    test_verbose_flag
    test_worktree_creation_failure
    test_summary_shows_repo
    test_summary_shows_branch

    # Section E: CMUXWAIT integration tests (5 tests)
    test_integration_happy_path
    test_integration_workspace_polling_timeout
    test_integration_prompt_polling_timeout
    test_integration_missing_cmux_wait
    test_integration_dry_run_no_sleep

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
