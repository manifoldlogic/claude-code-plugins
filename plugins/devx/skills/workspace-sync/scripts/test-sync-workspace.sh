#!/usr/bin/env bash
#
# test-sync-workspace.sh - Tests for sync-workspace.sh
#
# DESCRIPTION:
#   Tests for the workspace sync engine. Creates temporary directory structures
#   simulating various repo layouts (flat clones, wrappers with worktrees,
#   non-git directories) and validates the output against expected entries.
#
# USAGE:
#   bash test-sync-workspace.sh
#
# EXIT CODES:
#   0 - All tests passed
#   1 - One or more tests failed

set -euo pipefail

##############################################################################
# Test Configuration
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/sync-workspace.sh"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

TEST_TMPDIR=""

##############################################################################
# Test Utilities
##############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
pass() { echo -e "${GREEN}[PASS]${NC} $*"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
fail() { echo -e "${RED}[FAIL]${NC} $*"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

run_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo ""
    echo -e "${YELLOW}Test $TESTS_RUN: $1${NC}"
    echo "----------------------------------------"
}

assert_exit_code() {
    local expected="$1" actual="$2" msg="$3"
    if [ "$actual" -eq "$expected" ]; then
        pass "$msg"
    else
        fail "$msg (expected exit $expected, got $actual)"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" msg="$3"
    if echo "$haystack" | grep -qF -- "$needle"; then
        pass "$msg"
    else
        fail "$msg (output does not contain: $needle)"
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" msg="$3"
    if echo "$haystack" | grep -qF -- "$needle"; then
        fail "$msg (output unexpectedly contains: $needle)"
    else
        pass "$msg"
    fi
}

assert_json_entry() {
    local json_file="$1" name="$2" path="$3" msg="$4"
    local found
    found=$(jq -r --arg n "$name" --arg p "$path" \
        '[.folders[] | select(.name == $n and .path == $p)] | length' \
        "$json_file")
    if [ "$found" = "1" ]; then
        pass "$msg"
    else
        fail "$msg (entry name='$name' path='$path' not found)"
    fi
}

assert_json_no_entry() {
    local json_file="$1" name="$2" msg="$3"
    local found
    found=$(jq -r --arg n "$name" \
        '[.folders[] | select(.name == $n)] | length' \
        "$json_file")
    if [ "$found" = "0" ]; then
        pass "$msg"
    else
        fail "$msg (entry name='$name' unexpectedly found)"
    fi
}

assert_json_first_entry() {
    local json_file="$1" expected_name="$2" msg="$3"
    local first
    first=$(jq -r '.folders[0].name' "$json_file")
    if [ "$first" = "$expected_name" ]; then
        pass "$msg"
    else
        fail "$msg (expected first entry '$expected_name', got '$first')"
    fi
}

assert_json_entry_count() {
    local json_file="$1" expected="$2" msg="$3"
    local actual
    actual=$(jq '.folders | length' "$json_file")
    if [ "$actual" = "$expected" ]; then
        pass "$msg"
    else
        fail "$msg (expected $expected entries, got $actual)"
    fi
}

##############################################################################
# Setup / Teardown
##############################################################################

setup_test_env() {
    TEST_TMPDIR=$(mktemp -d)
    mkdir -p "$TEST_TMPDIR/repos"

    # Create a minimal workspace file
    cat > "$TEST_TMPDIR/workspace.code-workspace" << 'WSJSON'
{
  "folders": [
    {
      "name": "devcontainer",
      "path": "."
    }
  ],
  "settings": {
    "editor.tabSize": 2
  }
}
WSJSON
}

teardown_test_env() {
    if [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ]; then
        rm -rf "$TEST_TMPDIR"
    fi
    TEST_TMPDIR=""
}

# Helper to create a flat-clone repo (has .git/ directory)
create_flat_clone() {
    local name="$1"
    mkdir -p "$TEST_TMPDIR/repos/$name/.git"
    # Minimal git structure
    echo "ref: refs/heads/main" > "$TEST_TMPDIR/repos/$name/.git/HEAD"
}

# Helper to create a wrapper with main clone
create_wrapper_main() {
    local wrapper="$1" main_dir="$2"
    mkdir -p "$TEST_TMPDIR/repos/$wrapper/$main_dir/.git"
    echo "ref: refs/heads/main" > "$TEST_TMPDIR/repos/$wrapper/$main_dir/.git/HEAD"
}

# Helper to create a worktree child (has .git file, not directory)
create_wrapper_worktree() {
    local wrapper="$1" wt_name="$2"
    mkdir -p "$TEST_TMPDIR/repos/$wrapper/$wt_name"
    echo "gitdir: ../../.git/worktrees/$wt_name" > "$TEST_TMPDIR/repos/$wrapper/$wt_name/.git"
}

# Helper to create a non-git directory
create_non_git_dir() {
    local path="$1"
    mkdir -p "$TEST_TMPDIR/repos/$path"
}

##############################################################################
# Tests
##############################################################################

test_flat_clone_detection() {
    run_test "Flat clone detection"
    setup_test_env

    create_flat_clone "my-project"

    local exit_code=0
    bash "$SYNC_SCRIPT" \
        -w "$TEST_TMPDIR/workspace.code-workspace" \
        -r "$TEST_TMPDIR/repos" 2>/dev/null || exit_code=$?

    assert_exit_code 0 "$exit_code" "Script exits 0"
    assert_json_entry "$TEST_TMPDIR/workspace.code-workspace" \
        "my-project | main" "repos/my-project" \
        "Flat clone entry has correct name and path"

    teardown_test_env
}

test_wrapper_with_main_and_worktrees() {
    run_test "Wrapper with main clone and worktrees"
    setup_test_env

    create_wrapper_main "myrepo" "myrepo"
    create_wrapper_worktree "myrepo" "TICKET-1"
    create_wrapper_worktree "myrepo" "FEAT-2"

    local exit_code=0
    bash "$SYNC_SCRIPT" \
        -w "$TEST_TMPDIR/workspace.code-workspace" \
        -r "$TEST_TMPDIR/repos" 2>/dev/null || exit_code=$?

    assert_exit_code 0 "$exit_code" "Script exits 0"
    assert_json_entry "$TEST_TMPDIR/workspace.code-workspace" \
        "myrepo | main" "repos/myrepo/myrepo" \
        "Main clone entry correct"
    assert_json_entry "$TEST_TMPDIR/workspace.code-workspace" \
        "myrepo ⛙ TICKET-1" "repos/myrepo/TICKET-1" \
        "Worktree TICKET-1 entry correct"
    assert_json_entry "$TEST_TMPDIR/workspace.code-workspace" \
        "myrepo ⛙ FEAT-2" "repos/myrepo/FEAT-2" \
        "Worktree FEAT-2 entry correct"

    teardown_test_env
}

test_non_git_directory_exclusion() {
    run_test "Non-git directory exclusion"
    setup_test_env

    create_non_git_dir "empty-dir"
    create_non_git_dir "_test_artifacts/_test_artifacts"
    create_non_git_dir "_test_artifacts/locked-wt"
    create_flat_clone "real-repo"

    local exit_code=0
    bash "$SYNC_SCRIPT" \
        -w "$TEST_TMPDIR/workspace.code-workspace" \
        -r "$TEST_TMPDIR/repos" 2>/dev/null || exit_code=$?

    assert_exit_code 0 "$exit_code" "Script exits 0"
    assert_json_no_entry "$TEST_TMPDIR/workspace.code-workspace" \
        "empty-dir | main" "Empty dir excluded"
    assert_json_no_entry "$TEST_TMPDIR/workspace.code-workspace" \
        "_test_artifacts | main" "Test artifacts excluded"
    assert_json_entry "$TEST_TMPDIR/workspace.code-workspace" \
        "real-repo | main" "repos/real-repo" \
        "Real repo still included"

    teardown_test_env
}

test_ordering() {
    run_test "Correct ordering (devcontainer first, then alphabetical)"
    setup_test_env

    create_flat_clone "zebra"
    create_flat_clone "alpha"
    create_wrapper_main "beta" "beta"
    create_wrapper_worktree "beta" "WT-1"

    local exit_code=0
    bash "$SYNC_SCRIPT" \
        -w "$TEST_TMPDIR/workspace.code-workspace" \
        -r "$TEST_TMPDIR/repos" 2>/dev/null || exit_code=$?

    assert_exit_code 0 "$exit_code" "Script exits 0"
    assert_json_first_entry "$TEST_TMPDIR/workspace.code-workspace" \
        "devcontainer" "devcontainer is first"

    # Check order: alpha, beta | main, beta ⛙ WT-1, zebra
    local names
    names=$(jq -r '.folders[].name' "$TEST_TMPDIR/workspace.code-workspace")
    local expected
    expected=$(printf 'devcontainer\nalpha | main\nbeta | main\nbeta ⛙ WT-1\nzebra | main')
    if [ "$names" = "$expected" ]; then
        pass "Entries in correct alphabetical order"
    else
        fail "Ordering incorrect. Expected:\n$expected\nGot:\n$names"
    fi

    teardown_test_env
}

test_mismatched_main_dir_name() {
    run_test "Mismatched main dir name (mcp-quickbase/MCP-Quickbase)"
    setup_test_env

    create_wrapper_main "mcp-quickbase" "MCP-Quickbase"

    local exit_code=0
    bash "$SYNC_SCRIPT" \
        -w "$TEST_TMPDIR/workspace.code-workspace" \
        -r "$TEST_TMPDIR/repos" 2>/dev/null || exit_code=$?

    assert_exit_code 0 "$exit_code" "Script exits 0"
    assert_json_entry "$TEST_TMPDIR/workspace.code-workspace" \
        "mcp-quickbase | main" "repos/mcp-quickbase/MCP-Quickbase" \
        "Name uses wrapper, path uses actual dir on disk"

    teardown_test_env
}

test_stale_entry_removal() {
    run_test "Stale entry removal"
    setup_test_env

    # Add a stale entry to the workspace file
    jq '.folders += [{"name": "deleted-repo | main", "path": "repos/deleted-repo"}]' \
        "$TEST_TMPDIR/workspace.code-workspace" > "$TEST_TMPDIR/workspace.code-workspace.tmp"
    mv "$TEST_TMPDIR/workspace.code-workspace.tmp" "$TEST_TMPDIR/workspace.code-workspace"

    create_flat_clone "real-repo"

    local exit_code=0
    bash "$SYNC_SCRIPT" \
        -w "$TEST_TMPDIR/workspace.code-workspace" \
        -r "$TEST_TMPDIR/repos" 2>/dev/null || exit_code=$?

    assert_exit_code 0 "$exit_code" "Script exits 0"
    assert_json_no_entry "$TEST_TMPDIR/workspace.code-workspace" \
        "deleted-repo | main" "Stale entry removed"
    assert_json_entry "$TEST_TMPDIR/workspace.code-workspace" \
        "real-repo | main" "repos/real-repo" \
        "Real repo kept"

    teardown_test_env
}

test_missing_entry_addition() {
    run_test "Missing entry addition"
    setup_test_env

    # Workspace only has devcontainer
    create_flat_clone "new-repo"
    create_wrapper_main "another" "another"

    local exit_code=0
    bash "$SYNC_SCRIPT" \
        -w "$TEST_TMPDIR/workspace.code-workspace" \
        -r "$TEST_TMPDIR/repos" 2>/dev/null || exit_code=$?

    assert_exit_code 0 "$exit_code" "Script exits 0"
    assert_json_entry "$TEST_TMPDIR/workspace.code-workspace" \
        "new-repo | main" "repos/new-repo" \
        "New flat clone added"
    assert_json_entry "$TEST_TMPDIR/workspace.code-workspace" \
        "another | main" "repos/another/another" \
        "New wrapper main added"

    teardown_test_env
}

test_check_mode_in_sync() {
    run_test "--check mode when in-sync"
    setup_test_env

    # No repos — workspace only has devcontainer which matches
    local exit_code=0
    bash "$SYNC_SCRIPT" \
        -w "$TEST_TMPDIR/workspace.code-workspace" \
        -r "$TEST_TMPDIR/repos" \
        --check 2>/dev/null || exit_code=$?

    assert_exit_code 0 "$exit_code" "--check exits 0 when in-sync"

    teardown_test_env
}

test_check_mode_drift() {
    run_test "--check mode when drifted"
    setup_test_env

    # Add a repo that is not in workspace
    create_flat_clone "missing-repo"

    local exit_code=0
    local output
    output=$(bash "$SYNC_SCRIPT" \
        -w "$TEST_TMPDIR/workspace.code-workspace" \
        -r "$TEST_TMPDIR/repos" \
        --check 2>&1) || exit_code=$?

    assert_exit_code 1 "$exit_code" "--check exits 1 when drifted"
    assert_contains "$output" "missing-repo" "Output mentions missing entry"

    teardown_test_env
}

test_dry_run_no_modification() {
    run_test "--dry-run does not modify workspace file"
    setup_test_env

    create_flat_clone "new-repo"

    local before
    before=$(cat "$TEST_TMPDIR/workspace.code-workspace")

    local exit_code=0
    bash "$SYNC_SCRIPT" \
        -w "$TEST_TMPDIR/workspace.code-workspace" \
        -r "$TEST_TMPDIR/repos" \
        --dry-run 2>/dev/null || exit_code=$?

    assert_exit_code 0 "$exit_code" "--dry-run exits 0"

    local after
    after=$(cat "$TEST_TMPDIR/workspace.code-workspace")
    if [ "$before" = "$after" ]; then
        pass "Workspace file was not modified"
    else
        fail "Workspace file was modified during --dry-run"
    fi

    teardown_test_env
}

test_settings_preservation() {
    run_test "Settings object preserved during sync"
    setup_test_env

    create_flat_clone "new-repo"

    local exit_code=0
    bash "$SYNC_SCRIPT" \
        -w "$TEST_TMPDIR/workspace.code-workspace" \
        -r "$TEST_TMPDIR/repos" 2>/dev/null || exit_code=$?

    assert_exit_code 0 "$exit_code" "Script exits 0"

    local tab_size
    tab_size=$(jq '.settings["editor.tabSize"]' "$TEST_TMPDIR/workspace.code-workspace")
    if [ "$tab_size" = "2" ]; then
        pass "Settings object preserved (editor.tabSize = 2)"
    else
        fail "Settings object lost or modified (editor.tabSize = $tab_size)"
    fi

    teardown_test_env
}

test_hidden_dirs_skipped() {
    run_test "Hidden directories under repos/ are skipped"
    setup_test_env

    mkdir -p "$TEST_TMPDIR/repos/.crewchief"
    mkdir -p "$TEST_TMPDIR/repos/.obsidian"
    mkdir -p "$TEST_TMPDIR/repos/.DS_Store"
    create_flat_clone "real-repo"

    local exit_code=0
    bash "$SYNC_SCRIPT" \
        -w "$TEST_TMPDIR/workspace.code-workspace" \
        -r "$TEST_TMPDIR/repos" 2>/dev/null || exit_code=$?

    assert_exit_code 0 "$exit_code" "Script exits 0"
    # Should only have devcontainer + real-repo
    assert_json_entry_count "$TEST_TMPDIR/workspace.code-workspace" \
        2 "Only 2 entries (devcontainer + real-repo)"

    teardown_test_env
}

test_wrapper_non_git_child_skipped() {
    run_test "Non-git children in wrappers are skipped"
    setup_test_env

    create_wrapper_main "myrepo" "myrepo"
    create_non_git_dir "myrepo/HEROSVG"
    create_non_git_dir "myrepo/.crewchief"

    local exit_code=0
    bash "$SYNC_SCRIPT" \
        -w "$TEST_TMPDIR/workspace.code-workspace" \
        -r "$TEST_TMPDIR/repos" 2>/dev/null || exit_code=$?

    assert_exit_code 0 "$exit_code" "Script exits 0"
    assert_json_no_entry "$TEST_TMPDIR/workspace.code-workspace" \
        "myrepo ⛙ HEROSVG" "HEROSVG not included as worktree"
    assert_json_entry "$TEST_TMPDIR/workspace.code-workspace" \
        "myrepo | main" "repos/myrepo/myrepo" \
        "Main clone still included"
    # devcontainer + myrepo main = 2 entries
    assert_json_entry_count "$TEST_TMPDIR/workspace.code-workspace" \
        2 "Only 2 entries"

    teardown_test_env
}

test_help_flag() {
    run_test "--help flag"

    local exit_code=0
    local output
    output=$(bash "$SYNC_SCRIPT" --help 2>&1) || exit_code=$?

    assert_exit_code 0 "$exit_code" "--help exits 0"
    assert_contains "$output" "sync-workspace.sh" "Help shows script name"
    assert_contains "$output" "--dry-run" "Help mentions --dry-run"
    assert_contains "$output" "--check" "Help mentions --check"
}

##############################################################################
# Run All Tests
##############################################################################

echo ""
echo "=========================================="
echo "  sync-workspace.sh Test Suite"
echo "=========================================="

test_flat_clone_detection
test_wrapper_with_main_and_worktrees
test_non_git_directory_exclusion
test_ordering
test_mismatched_main_dir_name
test_stale_entry_removal
test_missing_entry_addition
test_check_mode_in_sync
test_check_mode_drift
test_dry_run_no_modification
test_settings_preservation
test_hidden_dirs_skipped
test_wrapper_non_git_child_skipped
test_help_flag

##############################################################################
# Summary
##############################################################################

echo ""
echo "=========================================="
echo "  Results: $TESTS_PASSED/$TESTS_RUN passed"
echo "=========================================="
if [ "$TESTS_FAILED" -gt 0 ]; then
    echo -e "${RED}  $TESTS_FAILED test(s) FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}  All tests passed!${NC}"
    exit 0
fi
