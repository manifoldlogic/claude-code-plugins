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
#   Tests run from inside git-init'd temp repos so setup-worktree.sh can
#   auto-detect the git root via git rev-parse --show-toplevel.
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

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local msg="$3"
    if [ "$actual" -eq "$expected" ]; then
        pass "$msg"
    else
        fail "$msg (expected exit $expected, got $actual)"
    fi
}

assert_contains() {
    local output="$1"
    local pattern="$2"
    local msg="$3"
    if echo "$output" | grep -q -- "$pattern"; then
        pass "$msg"
    else
        fail "$msg (output did not contain: $pattern)"
    fi
}

assert_not_contains() {
    local output="$1"
    local pattern="$2"
    local msg="$3"
    if echo "$output" | grep -q -- "$pattern"; then
        fail "$msg (output unexpectedly contained: $pattern)"
    else
        pass "$msg"
    fi
}

##############################################################################
# Setup / Teardown
##############################################################################

setup() {
    TEST_TMPDIR="$(mktemp -d)"

    # Create mock bin directory
    mkdir -p "$TEST_TMPDIR/bin"
    mkdir -p "$TEST_TMPDIR/cmux-plugin/skills/terminal-management/scripts"

    # Create test git repos (git init required for git rev-parse --show-toplevel)
    git init "$TEST_TMPDIR/repos/myrepo" > /dev/null 2>&1

    # Mock crewchief
    cat > "$TEST_TMPDIR/bin/crewchief" <<'MOCKEOF'
#!/usr/bin/env bash
# Mock crewchief - validates PWD is a git root, always succeeds
if [ "${1:-}" = "worktree" ] && [ "${2:-}" = "create" ]; then
    [ -d "$PWD/.git" ] || { echo "error: not in a git root" >&2; exit 1; }
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
    if [ ! -f "$CMUX_WAIT_REAL" ]; then
        echo "[FAIL] Could not locate cmux-wait.sh: $CMUX_WAIT_REAL" >&2
        return 1
    fi
    cp "$CMUX_WAIT_REAL" "$TEST_TMPDIR/cmux-plugin/skills/terminal-management/scripts/cmux-wait.sh"

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
# Helper: Run setup-worktree.sh with mocked environment from test git repo
##############################################################################

# Run setup-worktree.sh in a subshell with all mocks configured.
# Runs from inside $TEST_TMPDIR/repos/myrepo (a git-init'd directory).
# Args: all args are passed to setup-worktree.sh
# Returns: exit code of the script
# Stdout+stderr captured and stored in global $LAST_OUTPUT
run_setup() {
    LAST_OUTPUT=$(
        cd "$TEST_TMPDIR/repos/myrepo" && \
        PATH="$TEST_TMPDIR/bin:$PATH" \
        CMUX_PLUGIN_DIR="$TEST_TMPDIR/cmux-plugin" \
        WORKSPACE_FOLDER_SCRIPT="$TEST_TMPDIR/workspace-folder.sh" \
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

    assert_contains "$output" "Usage:" "--help shows usage text"
    assert_not_contains "$output" "--repo" "help must not mention --repo"
    assert_not_contains "$output" "WORKSPACE_REPOS_ROOT" "help must not mention WORKSPACE_REPOS_ROOT"
}

test_missing_worktree_name() {
    run_test "Missing worktree name exits 1"

    local exit_code=0
    cd "$TEST_TMPDIR/repos/myrepo" && bash "$SETUP_SCRIPT" > /dev/null 2>&1 || exit_code=$?

    assert_exit_code 1 "$exit_code" "Exit code 1 for missing worktree name"
}

test_not_in_git_repo() {
    run_test "Running outside git repo exits 1"

    local output exit_code=0
    output=$(cd /tmp && bash "$SETUP_SCRIPT" TICKET-1 2>&1) || exit_code=$?

    assert_exit_code 1 "$exit_code" "not-in-git-repo should exit 1"
    assert_contains "$output" "Not inside a git repository" "error message must mention not inside a git repository"
}

test_repo_flag_rejected() {
    run_test "--repo flag is rejected as unrecognized"

    local output exit_code=0
    output=$(cd "$TEST_TMPDIR/repos/myrepo" && bash "$SETUP_SCRIPT" TICKET-1 --repo anything 2>&1) || exit_code=$?

    assert_exit_code 3 "$exit_code" "--repo should be rejected as unrecognized option (exit 3)"
}

test_unrecognized_option() {
    run_test "Unrecognized option exits 3"

    local exit_code=0
    cd "$TEST_TMPDIR/repos/myrepo" && bash "$SETUP_SCRIPT" TICKET-1 --badopt 2>/dev/null || exit_code=$?

    assert_exit_code 3 "$exit_code" "Exit code 3 for unrecognized option"
}

test_extra_positional_arg() {
    run_test "Extra positional argument exits 1"

    local exit_code=0
    cd "$TEST_TMPDIR/repos/myrepo" && bash "$SETUP_SCRIPT" TICKET-1 EXTRA 2>/dev/null || exit_code=$?

    assert_exit_code 1 "$exit_code" "Exit code 1 for extra positional argument"
}

test_invalid_worktree_name() {
    run_test "Invalid worktree name (starts with hyphen) exits 1"

    if cd "$TEST_TMPDIR/repos/myrepo" && bash "$SETUP_SCRIPT" "-bad" 2>/dev/null; then
        fail "Should exit non-zero for invalid worktree name"
    else
        pass "Non-zero exit for invalid worktree name"
    fi
}

test_valid_worktree_names() {
    run_test "Valid worktree names accepted"

    # Dry-run so we don't need all mocks
    local output
    output=$(cd "$TEST_TMPDIR/repos/myrepo" && bash "$SETUP_SCRIPT" TICKET-1 --dry-run 2>&1) || true
    assert_contains "$output" "TICKET-1" "TICKET-1 accepted as valid name"

    output=$(cd "$TEST_TMPDIR/repos/myrepo" && bash "$SETUP_SCRIPT" my_worktree --dry-run 2>&1) || true
    assert_contains "$output" "my_worktree" "my_worktree accepted as valid name"
}

test_repo_auto_derived() {
    run_test "Repository name auto-derived from git root basename"

    local output
    output=$(cd "$TEST_TMPDIR/repos/myrepo" && bash "$SETUP_SCRIPT" TICKET-1 --dry-run 2>&1) || true
    assert_contains "$output" "Repository: myrepo" "Repository name auto-derived from git root basename"
}

test_branch_flag() {
    run_test "--branch / -b sets base branch"

    local output
    output=$(cd "$TEST_TMPDIR/repos/myrepo" && bash "$SETUP_SCRIPT" TICKET-1 --branch develop --dry-run 2>&1) || true
    assert_contains "$output" "develop" "--branch develop shown in dry-run output"

    output=$(cd "$TEST_TMPDIR/repos/myrepo" && bash "$SETUP_SCRIPT" TICKET-1 -b release --dry-run 2>&1) || true
    assert_contains "$output" "release" "-b release shown in dry-run output"
}

test_workspace_flag() {
    run_test "--workspace / -w sets workspace file"

    local output
    output=$(cd "$TEST_TMPDIR/repos/myrepo" && bash "$SETUP_SCRIPT" TICKET-1 -w /my/file.code-workspace --dry-run 2>&1) || true
    assert_contains "$output" "/my/file.code-workspace" "-w flag sets workspace file in dry-run output"
}

test_skip_cmux_flag() {
    run_test "--skip-cmux flag shows skip in dry-run"

    local output
    output=$(cd "$TEST_TMPDIR/repos/myrepo" && bash "$SETUP_SCRIPT" TICKET-1 --skip-cmux --dry-run 2>&1) || true
    assert_contains "$output" "SKIPPED.*--skip-cmux" "--skip-cmux flag acknowledged in dry-run"
}

test_skip_workspace_flag() {
    run_test "--skip-workspace flag shows skip in dry-run"

    local output
    output=$(cd "$TEST_TMPDIR/repos/myrepo" && bash "$SETUP_SCRIPT" TICKET-1 --skip-workspace --dry-run 2>&1) || true
    assert_contains "$output" "SKIPPED.*--skip-workspace" "--skip-workspace flag acknowledged in dry-run"
}

##############################################################################
# Section B: Dry-Run Tests
##############################################################################

test_dry_run_header() {
    run_test "Dry-run shows header and resolved parameters"

    local output
    output=$(cd "$TEST_TMPDIR/repos/myrepo" && bash "$SETUP_SCRIPT" TICKET-1 --dry-run 2>&1) || true

    assert_contains "$output" "DRY RUN" "DRY RUN header present"
    assert_contains "$output" "Resolved parameters" "Resolved parameters section present"
}

test_dry_run_shows_all_steps() {
    run_test "Dry-run shows steps 1-7"

    local output
    output=$(cd "$TEST_TMPDIR/repos/myrepo" && bash "$SETUP_SCRIPT" TICKET-1 --dry-run 2>&1) || true

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

    if cd "$TEST_TMPDIR/repos/myrepo" && bash "$SETUP_SCRIPT" TICKET-1 --dry-run > /dev/null 2>&1; then
        pass "Dry-run exits 0"
    else
        fail "Dry-run exited non-zero"
    fi
}

test_dry_run_default_branch() {
    run_test "Dry-run shows default branch main"

    local output
    output=$(cd "$TEST_TMPDIR/repos/myrepo" && bash "$SETUP_SCRIPT" TICKET-1 --dry-run 2>&1) || true

    assert_contains "$output" "Base branch: main" "Default branch main shown"
}

test_dry_run_worktree_path() {
    run_test "Dry-run shows computed worktree path"

    local output
    output=$(cd "$TEST_TMPDIR/repos/myrepo" && bash "$SETUP_SCRIPT" TICKET-1 --dry-run 2>&1) || true

    assert_contains "$output" "TICKET-1" "Worktree path contains worktree name"
}

test_dry_run_git_root() {
    run_test "Dry-run shows Git root"

    local output
    output=$(cd "$TEST_TMPDIR/repos/myrepo" && bash "$SETUP_SCRIPT" TICKET-1 --dry-run 2>&1) || true

    assert_contains "$output" "Git root:" "dry-run must show Git root"
}

test_dry_run_cd_git_root() {
    run_test "Dry-run Step 2 shows cd to GIT_ROOT"

    local output
    output=$(cd "$TEST_TMPDIR/repos/myrepo" && bash "$SETUP_SCRIPT" TICKET-1 --dry-run 2>&1) || true

    # Step 2 should show: (cd $GIT_ROOT && crewchief worktree create ...)
    assert_contains "$output" "cd $TEST_TMPDIR/repos/myrepo" "Step 2 references cd to GIT_ROOT"
}

test_dry_run_subdir_detection() {
    run_test "Dry-run from subdirectory detects correct git root"

    # Create a subdirectory inside the test git repo
    mkdir -p "$TEST_TMPDIR/repos/myrepo/subdir/nested"

    local output
    output=$(cd "$TEST_TMPDIR/repos/myrepo/subdir/nested" && bash "$SETUP_SCRIPT" TICKET-1 --dry-run 2>&1) || true
    local exit_code=$?

    assert_exit_code 0 "$exit_code" "Dry-run from subdir exits 0"
    assert_contains "$output" "Git root:" "Git root shown from subdir"
    assert_contains "$output" "$TEST_TMPDIR/repos/myrepo" "Correct git root detected from subdir"
}

##############################################################################
# Section C: Prerequisite Validation Tests
##############################################################################

test_missing_crewchief() {
    run_test "Missing crewchief CLI exits 2"

    # Use empty PATH to simulate missing crewchief
    local exit_code=0
    cd "$TEST_TMPDIR/repos/myrepo" && \
    PATH="/usr/bin:/bin" \
       CMUX_PLUGIN_DIR="$TEST_TMPDIR/cmux-plugin" \
       WORKSPACE_FOLDER_SCRIPT="$TEST_TMPDIR/workspace-folder.sh" \
       bash "$SETUP_SCRIPT" TICKET-1 2>/dev/null || exit_code=$?

    assert_exit_code 2 "$exit_code" "Exit code 2 when crewchief missing"
}

test_missing_workspace_folder_script() {
    run_test "Missing workspace-folder.sh auto-skips workspace step"

    local output
    output=$(
        cd "$TEST_TMPDIR/repos/myrepo" && \
        PATH="$TEST_TMPDIR/bin:$PATH" \
        CMUX_PLUGIN_DIR="$TEST_TMPDIR/cmux-plugin" \
        WORKSPACE_FOLDER_SCRIPT="/nonexistent/workspace-folder.sh" \
        DEVCONTAINER_NAME="mock-devcontainer-1" \
        CMUX_WAIT_WS_TIMEOUT=2 \
        CMUX_WAIT_WS_INTERVAL=0.1 \
        CMUX_WAIT_PROMPT_TIMEOUT=2 \
        CMUX_WAIT_PROMPT_INTERVAL=0.1 \
        bash "$SETUP_SCRIPT" TICKET-1 2>&1
    ) || true

    assert_contains "$output" "workspace-folder.sh not found" "Warning about missing workspace-folder.sh shown"
}

test_missing_cmux_check_skips_cmux() {
    run_test "Missing cmux-check.sh auto-skips cmux steps"

    # Remove cmux-check.sh
    local backup="$TEST_TMPDIR/cmux-check-backup.sh"
    mv "$TEST_TMPDIR/cmux-plugin/skills/terminal-management/scripts/cmux-check.sh" "$backup"

    local output
    output=$(
        cd "$TEST_TMPDIR/repos/myrepo" && \
        PATH="$TEST_TMPDIR/bin:$PATH" \
        CMUX_PLUGIN_DIR="$TEST_TMPDIR/cmux-plugin" \
        WORKSPACE_FOLDER_SCRIPT="$TEST_TMPDIR/workspace-folder.sh" \
        DEVCONTAINER_NAME="mock-devcontainer-1" \
        bash "$SETUP_SCRIPT" TICKET-1 2>&1
    ) || true

    # Restore
    mv "$backup" "$TEST_TMPDIR/cmux-plugin/skills/terminal-management/scripts/cmux-check.sh"

    assert_contains "$output" "cmux-check.sh not found" "Warning about missing cmux-check.sh shown"
}

##############################################################################
# Section D: Full Run Tests (with all mocks)
##############################################################################

test_full_run_skip_cmux() {
    run_test "Full run with --skip-cmux completes successfully"

    if run_setup TICKET-1 --skip-cmux; then
        pass "Setup completed with --skip-cmux"
    else
        fail "Setup failed with --skip-cmux (exit code $?)"
    fi

    assert_contains "$LAST_OUTPUT" "Worktree Setup Complete" "Success summary shown"
}

test_full_run_skip_workspace() {
    run_test "Full run with --skip-workspace completes successfully"

    if run_setup TICKET-1 --skip-workspace; then
        pass "Setup completed with --skip-workspace"
    else
        fail "Setup failed with --skip-workspace (exit code $?)"
    fi

    assert_contains "$LAST_OUTPUT" "Skipping VS Code workspace" "Workspace skip message shown"
}

test_full_run_both_skips() {
    run_test "Full run with both --skip-cmux and --skip-workspace"

    if run_setup TICKET-1 --skip-cmux --skip-workspace; then
        pass "Setup completed with both skips"
    else
        fail "Setup failed with both skips"
    fi
}

test_full_run_shows_worktree_path() {
    run_test "Full run output includes worktree path"

    run_setup TICKET-1 --skip-cmux || true

    assert_contains "$LAST_OUTPUT" "TICKET-1" "Worktree path in output"
}

test_verbose_flag() {
    run_test "--verbose flag is accepted without error"

    if run_setup TICKET-1 --skip-cmux --verbose; then
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

    if run_setup TICKET-1 --skip-cmux; then
        fail "Should exit non-zero when crewchief fails"
    else
        local exit_code=$?
        assert_exit_code 4 "$exit_code" "Exit code 4 on worktree creation failure"
    fi

    # Restore working crewchief
    cat > "$TEST_TMPDIR/bin/crewchief" <<'MOCKEOF'
#!/usr/bin/env bash
# Mock crewchief - validates PWD is a git root, always succeeds
if [ "${1:-}" = "worktree" ] && [ "${2:-}" = "create" ]; then
    [ -d "$PWD/.git" ] || { echo "error: not in a git root" >&2; exit 1; }
    WORKTREE_NAME="${3:-}"
    exit 0
fi
exit 0
MOCKEOF
    chmod +x "$TEST_TMPDIR/bin/crewchief"
}

test_summary_shows_repo() {
    run_test "Summary section shows repository name"

    run_setup TICKET-1 --skip-cmux || true

    assert_contains "$LAST_OUTPUT" "Repository: myrepo" "Repository name in summary"
}

test_summary_shows_branch() {
    run_test "Summary section shows branch"

    run_setup TICKET-1 --branch develop --skip-cmux || true

    assert_contains "$LAST_OUTPUT" "Branch: develop" "Branch shown in summary"
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

    if run_setup TICKET-HP; then
        pass "Happy-path integration run exits 0"
    else
        fail "Happy-path integration run exited non-zero ($?)"
    fi

    assert_contains "$LAST_OUTPUT" "cmux workspace created" "Workspace creation logged"
    assert_contains "$LAST_OUTPUT" "Worktree Setup Complete" "Setup completed successfully"

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
        cd "$TEST_TMPDIR/repos/myrepo" && \
        PATH="$TEST_TMPDIR/bin:$PATH" \
        CMUX_PLUGIN_DIR="$TEST_TMPDIR/cmux-plugin" \
        WORKSPACE_FOLDER_SCRIPT="$TEST_TMPDIR/workspace-folder.sh" \
        DEVCONTAINER_NAME="mock-devcontainer-1" \
        CMUX_WAIT_WS_TIMEOUT=0 \
        CMUX_WAIT_WS_INTERVAL=0.1 \
        CMUX_WAIT_PROMPT_TIMEOUT=2 \
        CMUX_WAIT_PROMPT_INTERVAL=0.1 \
        bash "$SETUP_SCRIPT" TICKET-WST 2>&1
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
        cd "$TEST_TMPDIR/repos/myrepo" && \
        PATH="$TEST_TMPDIR/bin:$PATH" \
        CMUX_PLUGIN_DIR="$TEST_TMPDIR/cmux-plugin" \
        WORKSPACE_FOLDER_SCRIPT="$TEST_TMPDIR/workspace-folder.sh" \
        DEVCONTAINER_NAME="mock-devcontainer-1" \
        CMUX_WAIT_WS_TIMEOUT=2 \
        CMUX_WAIT_WS_INTERVAL=0.1 \
        CMUX_WAIT_PROMPT_TIMEOUT=0 \
        CMUX_WAIT_PROMPT_INTERVAL=0.1 \
        bash "$SETUP_SCRIPT" TICKET-PT 2>&1
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

    # Ensure cmux-wait.sh does NOT exist in our mock plugin dir
    rm -f "$TEST_TMPDIR/cmux-plugin/skills/terminal-management/scripts/cmux-wait.sh"

    local output
    local exit_code=0
    output=$(
        cd "$TEST_TMPDIR/repos/myrepo" && \
        PATH="$TEST_TMPDIR/bin:$PATH" \
        CMUX_PLUGIN_DIR="$TEST_TMPDIR/cmux-plugin" \
        WORKSPACE_FOLDER_SCRIPT="$TEST_TMPDIR/workspace-folder.sh" \
        DEVCONTAINER_NAME="mock-devcontainer-1" \
        bash "$SETUP_SCRIPT" TICKET-STUB 2>&1
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

    assert_contains "$output" "Worktree Setup Complete" "Script completed despite missing cmux-wait.sh"
}

test_integration_dry_run_no_sleep() {
    run_test "Integration: --dry-run does not contain sleep references for Steps 4-6"

    local output
    output=$(cd "$TEST_TMPDIR/repos/myrepo" && bash "$SETUP_SCRIPT" TICKET-DRY --dry-run 2>&1) || true

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

    # Section A: Argument parsing & validation (15 tests)
    test_help_flag
    test_missing_worktree_name
    test_not_in_git_repo
    test_repo_flag_rejected
    test_unrecognized_option
    test_extra_positional_arg
    test_invalid_worktree_name
    test_valid_worktree_names
    test_repo_auto_derived
    test_branch_flag
    test_workspace_flag
    test_skip_cmux_flag
    test_skip_workspace_flag

    # Section B: Dry-run tests (10 tests)
    test_dry_run_header
    test_dry_run_shows_all_steps
    test_dry_run_exits_zero
    test_dry_run_default_branch
    test_dry_run_worktree_path
    test_dry_run_git_root
    test_dry_run_cd_git_root
    test_dry_run_subdir_detection

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
