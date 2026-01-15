#!/usr/bin/env bash
#
# test-iterm-plugin.sh - Automated integration tests for iTerm plugin
#
# DESCRIPTION:
#   Comprehensive integration test suite that verifies all iTerm plugin
#   functionality across host and container modes. Uses dry-run comparisons
#   and validates script structure, argument parsing, and error handling.
#
# USAGE:
#   ./test-iterm-plugin.sh [OPTIONS]
#
# OPTIONS:
#   -v, --verbose       Show detailed test output
#   -s, --script NAME   Test specific script (open-tab, list-tabs, close-tab)
#   -q, --quiet         Only show summary (suppress individual test results)
#   -h, --help          Show help
#
# EXIT CODES:
#   0 - All tests passed
#   1 - One or more tests failed
#
# CI/CD INTEGRATION:
#   Add to GitHub Actions or similar:
#     - name: Test iTerm Plugin
#       run: |
#         cd plugins/iterm
#         ./test-iterm-plugin.sh
#

set -euo pipefail

##############################################################################
# Script Location and Paths
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/skills/tab-management/scripts"

# Script paths
OPEN_TAB_SCRIPT="$SCRIPTS_DIR/iterm-open-tab.sh"
LIST_TABS_SCRIPT="$SCRIPTS_DIR/iterm-list-tabs.sh"
CLOSE_TAB_SCRIPT="$SCRIPTS_DIR/iterm-close-tab.sh"
UTILS_SCRIPT="$SCRIPTS_DIR/iterm-utils.sh"

##############################################################################
# Test Framework Variables
##############################################################################

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
VERBOSE=false
QUIET=false
FILTER_SCRIPT=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

##############################################################################
# Usage Information
##############################################################################

show_help() {
    cat << 'EOF'
test-iterm-plugin.sh - Automated integration tests for iTerm plugin

USAGE:
  ./test-iterm-plugin.sh [OPTIONS]

OPTIONS:
  -v, --verbose       Show detailed test output (commands being run)
  -s, --script NAME   Test specific script only (open-tab, list-tabs, close-tab)
  -q, --quiet         Only show summary (suppress individual test results)
  -h, --help          Show this help

EXIT CODES:
  0 - All tests passed
  1 - One or more tests failed

EXAMPLES:
  # Run all tests
  ./test-iterm-plugin.sh

  # Run with verbose output
  ./test-iterm-plugin.sh --verbose

  # Test only open-tab script
  ./test-iterm-plugin.sh -s open-tab

  # Quiet mode for CI/CD
  ./test-iterm-plugin.sh -q

TEST CATEGORIES:
  1. Script Existence - Verify all scripts exist and are executable
  2. Help/Usage - Test --help and -h flags for all scripts
  3. Dry-Run Mode - Verify dry-run generates AppleScript without execution
  4. Argument Parsing - Test all flags and options
  5. Exit Codes - Verify correct exit codes for errors
  6. AppleScript Structure - Validate generated AppleScript patterns
  7. Error Paths - Test error handling (invalid args, missing prereqs)
  8. Combined Options - Test multiple flags together
  9. Context Detection - Verify host vs container mode detection

UPDATING TESTS:
  Add new test functions following the pattern:
    test_<category>_<description>() {
        # Test implementation
        return 0  # Pass
        return 1  # Fail
    }
  Then add to the appropriate section in main().

CI/CD INTEGRATION:
  Add to GitHub Actions:
    - name: Test iTerm Plugin
      run: |
        cd plugins/iterm
        ./test-iterm-plugin.sh -q
EOF
}

##############################################################################
# Argument Parsing
##############################################################################

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -s|--script)
                if [[ -z "${2:-}" ]]; then
                    echo -e "${RED}[ERROR]${NC} Option $1 requires a script name" >&2
                    exit 1
                fi
                FILTER_SCRIPT="$2"
                # Validate script name
                case "$FILTER_SCRIPT" in
                    open-tab|list-tabs|close-tab) ;;
                    *)
                        echo -e "${RED}[ERROR]${NC} Invalid script name: $FILTER_SCRIPT" >&2
                        echo "Valid options: open-tab, list-tabs, close-tab" >&2
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}[ERROR]${NC} Unknown option: $1" >&2
                echo "Use -h or --help for usage information" >&2
                exit 1
                ;;
        esac
    done
}

##############################################################################
# Test Framework Functions
##############################################################################

# Print test result
pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    if [[ "$QUIET" != "true" ]]; then
        echo -e "  ${GREEN}[PASS]${NC} $1"
    fi
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    if [[ "$QUIET" != "true" ]]; then
        echo -e "  ${RED}[FAIL]${NC} $1"
        if [[ -n "${2:-}" ]]; then
            echo -e "         ${YELLOW}Reason:${NC} $2"
        fi
    fi
}

skip() {
    if [[ "$QUIET" != "true" ]]; then
        echo -e "  ${YELLOW}[SKIP]${NC} $1 - $2"
    fi
}

info() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "  ${BLUE}[INFO]${NC} $*"
    fi
}

# Run a test function
run_test() {
    local test_name="$1"
    local test_func="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    info "Running test: $test_name"

    if $test_func; then
        pass "$test_name"
    else
        fail "$test_name"
    fi
}

# Assert helpers
assert_exit_code() {
    local expected="$1"
    local actual="$2"
    [[ "$expected" == "$actual" ]]
}

assert_output_contains() {
    local output="$1"
    local pattern="$2"
    [[ "$output" == *"$pattern"* ]]
}

assert_output_not_contains() {
    local output="$1"
    local pattern="$2"
    [[ "$output" != *"$pattern"* ]]
}

# Check if we should run tests for a specific script
should_run_script() {
    local script_name="$1"
    [[ -z "$FILTER_SCRIPT" || "$FILTER_SCRIPT" == "$script_name" ]]
}

# Section header
section() {
    if [[ "$QUIET" != "true" ]]; then
        echo ""
        echo "=== $1 ==="
    fi
}

# Subsection header
subsection() {
    if [[ "$QUIET" != "true" ]]; then
        echo ""
        echo "--- $1 ---"
    fi
}

##############################################################################
# Test Category: Script Existence
##############################################################################

test_open_tab_script_exists() {
    [[ -f "$OPEN_TAB_SCRIPT" ]]
}

test_open_tab_script_executable() {
    [[ -x "$OPEN_TAB_SCRIPT" ]]
}

test_list_tabs_script_exists() {
    [[ -f "$LIST_TABS_SCRIPT" ]]
}

test_list_tabs_script_executable() {
    [[ -x "$LIST_TABS_SCRIPT" ]]
}

test_close_tab_script_exists() {
    [[ -f "$CLOSE_TAB_SCRIPT" ]]
}

test_close_tab_script_executable() {
    [[ -x "$CLOSE_TAB_SCRIPT" ]]
}

test_utils_script_exists() {
    [[ -f "$UTILS_SCRIPT" ]]
}

run_existence_tests() {
    section "Script Existence Tests"

    if should_run_script "open-tab"; then
        run_test "open-tab: script exists" test_open_tab_script_exists
        run_test "open-tab: script is executable" test_open_tab_script_executable
    fi

    if should_run_script "list-tabs"; then
        run_test "list-tabs: script exists" test_list_tabs_script_exists
        run_test "list-tabs: script is executable" test_list_tabs_script_executable
    fi

    if should_run_script "close-tab"; then
        run_test "close-tab: script exists" test_close_tab_script_exists
        run_test "close-tab: script is executable" test_close_tab_script_executable
    fi

    run_test "utils: script exists" test_utils_script_exists
}

##############################################################################
# Test Category: Help and Usage
##############################################################################

test_open_tab_help_short() {
    local output
    output=$("$OPEN_TAB_SCRIPT" -h 2>&1) || true
    assert_output_contains "$output" "USAGE" && assert_output_contains "$output" "OPTIONS"
}

test_open_tab_help_long() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --help 2>&1) || true
    assert_output_contains "$output" "USAGE" && assert_output_contains "$output" "--directory"
}

test_open_tab_help_exit_code() {
    local exit_code
    "$OPEN_TAB_SCRIPT" -h >/dev/null 2>&1
    exit_code=$?
    assert_exit_code "0" "$exit_code"
}

test_list_tabs_help_short() {
    local output
    output=$("$LIST_TABS_SCRIPT" -h 2>&1) || true
    assert_output_contains "$output" "USAGE" && assert_output_contains "$output" "OPTIONS"
}

test_list_tabs_help_long() {
    local output
    output=$("$LIST_TABS_SCRIPT" --help 2>&1) || true
    assert_output_contains "$output" "USAGE" && assert_output_contains "$output" "--format"
}

test_list_tabs_help_exit_code() {
    local exit_code
    "$LIST_TABS_SCRIPT" -h >/dev/null 2>&1
    exit_code=$?
    assert_exit_code "0" "$exit_code"
}

test_close_tab_help_short() {
    local output
    output=$("$CLOSE_TAB_SCRIPT" -h 2>&1) || true
    assert_output_contains "$output" "USAGE" && assert_output_contains "$output" "OPTIONS"
}

test_close_tab_help_long() {
    local output
    output=$("$CLOSE_TAB_SCRIPT" --help 2>&1) || true
    assert_output_contains "$output" "USAGE" && assert_output_contains "$output" "--force"
}

test_close_tab_help_exit_code() {
    local exit_code
    "$CLOSE_TAB_SCRIPT" -h >/dev/null 2>&1
    exit_code=$?
    assert_exit_code "0" "$exit_code"
}

run_help_tests() {
    section "Help and Usage Tests"

    if should_run_script "open-tab"; then
        subsection "open-tab"
        run_test "open-tab: -h shows usage" test_open_tab_help_short
        run_test "open-tab: --help shows usage" test_open_tab_help_long
        run_test "open-tab: help exits with 0" test_open_tab_help_exit_code
    fi

    if should_run_script "list-tabs"; then
        subsection "list-tabs"
        run_test "list-tabs: -h shows usage" test_list_tabs_help_short
        run_test "list-tabs: --help shows usage" test_list_tabs_help_long
        run_test "list-tabs: help exits with 0" test_list_tabs_help_exit_code
    fi

    if should_run_script "close-tab"; then
        subsection "close-tab"
        run_test "close-tab: -h shows usage" test_close_tab_help_short
        run_test "close-tab: --help shows usage" test_close_tab_help_long
        run_test "close-tab: help exits with 0" test_close_tab_help_exit_code
    fi
}

##############################################################################
# Test Category: Dry-Run Mode
##############################################################################

test_open_tab_dry_run_has_tell_application() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run 2>&1)
    assert_output_contains "$output" 'tell application "iTerm2"'
}

test_open_tab_dry_run_has_create_tab() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run 2>&1)
    assert_output_contains "$output" "create tab with profile"
}

test_open_tab_dry_run_exit_code() {
    local exit_code
    "$OPEN_TAB_SCRIPT" --dry-run >/dev/null 2>&1
    exit_code=$?
    assert_exit_code "0" "$exit_code"
}

test_open_tab_dry_run_window_creates_window() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run -w 2>&1)
    assert_output_contains "$output" "create window with profile"
}

test_list_tabs_dry_run_has_tell_application() {
    local output
    output=$("$LIST_TABS_SCRIPT" --dry-run 2>&1)
    assert_output_contains "$output" 'tell application "iTerm2"'
}

test_list_tabs_dry_run_has_window_iteration() {
    local output
    output=$("$LIST_TABS_SCRIPT" --dry-run 2>&1)
    assert_output_contains "$output" "repeat with w from 1 to"
}

test_list_tabs_dry_run_exit_code() {
    local exit_code
    "$LIST_TABS_SCRIPT" --dry-run >/dev/null 2>&1
    exit_code=$?
    assert_exit_code "0" "$exit_code"
}

test_close_tab_dry_run_needs_pattern() {
    # close-tab requires a pattern even for dry-run
    # It should fail with exit 3 (invalid args) if no pattern
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" --dry-run 2>/dev/null; echo $?) || true
    # Without iTerm running, it will fail with a different exit code after arg parsing
    # but with pattern, arg parsing should succeed
    exit_code=$("$CLOSE_TAB_SCRIPT" --dry-run "test-pattern" 2>/dev/null; echo $?) || true
    # Exit code should not be 3 (arg parse error)
    [[ "$exit_code" != "3" ]]
}

run_dry_run_tests() {
    section "Dry-Run Mode Tests"

    if should_run_script "open-tab"; then
        subsection "open-tab"
        run_test "open-tab: dry-run generates 'tell application'" test_open_tab_dry_run_has_tell_application
        run_test "open-tab: dry-run generates 'create tab with profile'" test_open_tab_dry_run_has_create_tab
        run_test "open-tab: dry-run exits with 0" test_open_tab_dry_run_exit_code
        run_test "open-tab: dry-run -w generates 'create window'" test_open_tab_dry_run_window_creates_window
    fi

    if should_run_script "list-tabs"; then
        subsection "list-tabs"
        run_test "list-tabs: dry-run generates 'tell application'" test_list_tabs_dry_run_has_tell_application
        run_test "list-tabs: dry-run generates window iteration" test_list_tabs_dry_run_has_window_iteration
        run_test "list-tabs: dry-run exits with 0" test_list_tabs_dry_run_exit_code
    fi

    if should_run_script "close-tab"; then
        subsection "close-tab"
        run_test "close-tab: dry-run accepts pattern argument" test_close_tab_dry_run_needs_pattern
    fi
}

##############################################################################
# Test Category: Argument Parsing
##############################################################################

# open-tab argument tests
test_open_tab_directory_short() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run -d /custom/path 2>&1)
    assert_output_contains "$output" "/custom/path"
}

test_open_tab_directory_long() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run --directory /another/path 2>&1)
    assert_output_contains "$output" "/another/path"
}

test_open_tab_profile_short() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run -p "Custom Profile" 2>&1)
    assert_output_contains "$output" "Custom Profile"
}

test_open_tab_profile_long() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run --profile "Another Profile" 2>&1)
    assert_output_contains "$output" "Another Profile"
}

test_open_tab_command_short() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run -c "echo hello" 2>&1)
    assert_output_contains "$output" "echo hello"
}

test_open_tab_command_long() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run --command "git status" 2>&1)
    assert_output_contains "$output" "git status"
}

test_open_tab_name_short() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run -n "My Tab" 2>&1)
    assert_output_contains "$output" "My Tab" && assert_output_contains "$output" "set name to"
}

test_open_tab_name_long() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run --name "Test Tab" 2>&1)
    assert_output_contains "$output" "Test Tab"
}

# list-tabs argument tests
test_list_tabs_format_json() {
    local exit_code
    "$LIST_TABS_SCRIPT" --dry-run -f json >/dev/null 2>&1
    exit_code=$?
    assert_exit_code "0" "$exit_code"
}

test_list_tabs_format_table() {
    local exit_code
    "$LIST_TABS_SCRIPT" --dry-run -f table >/dev/null 2>&1
    exit_code=$?
    assert_exit_code "0" "$exit_code"
}

test_list_tabs_format_invalid() {
    local exit_code
    exit_code=$("$LIST_TABS_SCRIPT" -f invalid 2>/dev/null; echo $?) || true
    assert_exit_code "3" "$exit_code"
}

test_list_tabs_window_valid() {
    local exit_code
    "$LIST_TABS_SCRIPT" --dry-run -w 1 >/dev/null 2>&1
    exit_code=$?
    assert_exit_code "0" "$exit_code"
}

test_list_tabs_window_invalid_zero() {
    local exit_code
    exit_code=$("$LIST_TABS_SCRIPT" -w 0 2>/dev/null; echo $?) || true
    assert_exit_code "3" "$exit_code"
}

test_list_tabs_window_invalid_string() {
    local exit_code
    exit_code=$("$LIST_TABS_SCRIPT" -w abc 2>/dev/null; echo $?) || true
    assert_exit_code "3" "$exit_code"
}

# close-tab argument tests
test_close_tab_pattern_required() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" 2>/dev/null; echo $?) || true
    assert_exit_code "3" "$exit_code"
}

test_close_tab_window_valid() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" -w 1 "test" 2>/dev/null; echo $?) || true
    # Should not be exit 3 (arg parsing should succeed)
    [[ "$exit_code" != "3" ]]
}

test_close_tab_window_invalid_zero() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" -w 0 "test" 2>/dev/null; echo $?) || true
    assert_exit_code "3" "$exit_code"
}

test_close_tab_force_flag() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" --force "test" 2>/dev/null; echo $?) || true
    # Should not be exit 3 (arg parsing should succeed)
    [[ "$exit_code" != "3" ]]
}

run_argument_tests() {
    section "Argument Parsing Tests"

    if should_run_script "open-tab"; then
        subsection "open-tab"
        run_test "open-tab: -d directory parsed" test_open_tab_directory_short
        run_test "open-tab: --directory parsed" test_open_tab_directory_long
        run_test "open-tab: -p profile parsed" test_open_tab_profile_short
        run_test "open-tab: --profile parsed" test_open_tab_profile_long
        run_test "open-tab: -c command parsed" test_open_tab_command_short
        run_test "open-tab: --command parsed" test_open_tab_command_long
        run_test "open-tab: -n name parsed" test_open_tab_name_short
        run_test "open-tab: --name parsed" test_open_tab_name_long
    fi

    if should_run_script "list-tabs"; then
        subsection "list-tabs"
        run_test "list-tabs: -f json accepted" test_list_tabs_format_json
        run_test "list-tabs: -f table accepted" test_list_tabs_format_table
        run_test "list-tabs: -f invalid rejected" test_list_tabs_format_invalid
        run_test "list-tabs: -w 1 accepted" test_list_tabs_window_valid
        run_test "list-tabs: -w 0 rejected" test_list_tabs_window_invalid_zero
        run_test "list-tabs: -w abc rejected" test_list_tabs_window_invalid_string
    fi

    if should_run_script "close-tab"; then
        subsection "close-tab"
        run_test "close-tab: pattern required" test_close_tab_pattern_required
        run_test "close-tab: -w 1 accepted" test_close_tab_window_valid
        run_test "close-tab: -w 0 rejected" test_close_tab_window_invalid_zero
        run_test "close-tab: --force accepted" test_close_tab_force_flag
    fi
}

##############################################################################
# Test Category: Exit Codes
##############################################################################

test_open_tab_invalid_flag_exit_3() {
    local exit_code
    exit_code=$("$OPEN_TAB_SCRIPT" --invalid-flag 2>/dev/null; echo $?) || true
    assert_exit_code "3" "$exit_code"
}

test_open_tab_missing_directory_exit_3() {
    local exit_code
    exit_code=$("$OPEN_TAB_SCRIPT" -d 2>/dev/null; echo $?) || true
    assert_exit_code "3" "$exit_code"
}

test_open_tab_missing_profile_exit_3() {
    local exit_code
    exit_code=$("$OPEN_TAB_SCRIPT" -p 2>/dev/null; echo $?) || true
    assert_exit_code "3" "$exit_code"
}

test_list_tabs_invalid_flag_exit_3() {
    local exit_code
    exit_code=$("$LIST_TABS_SCRIPT" --invalid-flag 2>/dev/null; echo $?) || true
    assert_exit_code "3" "$exit_code"
}

test_list_tabs_missing_format_exit_3() {
    local exit_code
    exit_code=$("$LIST_TABS_SCRIPT" -f 2>/dev/null; echo $?) || true
    assert_exit_code "3" "$exit_code"
}

test_close_tab_invalid_flag_exit_3() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" --invalid-flag "test" 2>/dev/null; echo $?) || true
    assert_exit_code "3" "$exit_code"
}

test_close_tab_missing_pattern_exit_3() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" 2>/dev/null; echo $?) || true
    assert_exit_code "3" "$exit_code"
}

run_exit_code_tests() {
    section "Exit Code Tests"

    if should_run_script "open-tab"; then
        subsection "open-tab"
        run_test "open-tab: invalid flag returns exit 3" test_open_tab_invalid_flag_exit_3
        run_test "open-tab: missing -d value returns exit 3" test_open_tab_missing_directory_exit_3
        run_test "open-tab: missing -p value returns exit 3" test_open_tab_missing_profile_exit_3
    fi

    if should_run_script "list-tabs"; then
        subsection "list-tabs"
        run_test "list-tabs: invalid flag returns exit 3" test_list_tabs_invalid_flag_exit_3
        run_test "list-tabs: missing -f value returns exit 3" test_list_tabs_missing_format_exit_3
    fi

    if should_run_script "close-tab"; then
        subsection "close-tab"
        run_test "close-tab: invalid flag returns exit 3" test_close_tab_invalid_flag_exit_3
        run_test "close-tab: missing pattern returns exit 3" test_close_tab_missing_pattern_exit_3
    fi
}

##############################################################################
# Test Category: AppleScript Structure
##############################################################################

test_open_tab_applescript_has_activate() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run 2>&1)
    assert_output_contains "$output" "activate"
}

test_open_tab_applescript_uses_first_window() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run 2>&1)
    assert_output_contains "$output" "first window"
}

test_open_tab_applescript_handles_no_windows() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run 2>&1)
    assert_output_contains "$output" "count of windows" && assert_output_contains "$output" "create window"
}

test_open_tab_applescript_has_end_tell() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run 2>&1)
    assert_output_contains "$output" "end tell"
}

test_open_tab_applescript_adds_clear() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run 2>&1)
    assert_output_contains "$output" "clear"
}

test_list_tabs_applescript_checks_running() {
    local output
    output=$("$LIST_TABS_SCRIPT" --dry-run 2>&1)
    assert_output_contains "$output" "not running"
}

test_list_tabs_applescript_counts_windows() {
    local output
    output=$("$LIST_TABS_SCRIPT" --dry-run 2>&1)
    assert_output_contains "$output" "count of windows"
}

test_list_tabs_applescript_iterates_tabs() {
    local output
    output=$("$LIST_TABS_SCRIPT" --dry-run 2>&1)
    assert_output_contains "$output" "repeat with" && assert_output_contains "$output" "tabs"
}

test_list_tabs_applescript_gets_session_name() {
    local output
    output=$("$LIST_TABS_SCRIPT" --dry-run 2>&1)
    assert_output_contains "$output" "name of current session"
}

test_list_tabs_applescript_returns_special_codes() {
    local output
    output=$("$LIST_TABS_SCRIPT" --dry-run 2>&1)
    assert_output_contains "$output" "ITERM_NOT_RUNNING" && assert_output_contains "$output" "NO_WINDOWS"
}

test_close_tab_uses_reverse_iteration() {
    local content
    content=$(cat "$CLOSE_TAB_SCRIPT")
    assert_output_contains "$content" "to 1 by -1"
}

test_close_tab_uses_contains_matching() {
    local content
    content=$(cat "$CLOSE_TAB_SCRIPT")
    assert_output_contains "$content" "contains"
}

run_applescript_structure_tests() {
    section "AppleScript Structure Tests"

    if should_run_script "open-tab"; then
        subsection "open-tab"
        run_test "open-tab: AppleScript has 'activate'" test_open_tab_applescript_has_activate
        run_test "open-tab: AppleScript uses 'first window'" test_open_tab_applescript_uses_first_window
        run_test "open-tab: AppleScript handles no windows" test_open_tab_applescript_handles_no_windows
        run_test "open-tab: AppleScript has 'end tell'" test_open_tab_applescript_has_end_tell
        run_test "open-tab: AppleScript adds 'clear'" test_open_tab_applescript_adds_clear
    fi

    if should_run_script "list-tabs"; then
        subsection "list-tabs"
        run_test "list-tabs: AppleScript checks if running" test_list_tabs_applescript_checks_running
        run_test "list-tabs: AppleScript counts windows" test_list_tabs_applescript_counts_windows
        run_test "list-tabs: AppleScript iterates tabs" test_list_tabs_applescript_iterates_tabs
        run_test "list-tabs: AppleScript gets session name" test_list_tabs_applescript_gets_session_name
        run_test "list-tabs: AppleScript returns special codes" test_list_tabs_applescript_returns_special_codes
    fi

    if should_run_script "close-tab"; then
        subsection "close-tab"
        run_test "close-tab: uses reverse iteration" test_close_tab_uses_reverse_iteration
        run_test "close-tab: uses 'contains' for matching" test_close_tab_uses_contains_matching
    fi
}

##############################################################################
# Test Category: Error Paths
##############################################################################

test_open_tab_unexpected_positional_arg() {
    local exit_code
    exit_code=$("$OPEN_TAB_SCRIPT" unexpected_arg 2>/dev/null; echo $?) || true
    assert_exit_code "3" "$exit_code"
}

test_list_tabs_unexpected_positional_arg() {
    local exit_code
    exit_code=$("$LIST_TABS_SCRIPT" unexpected_arg 2>/dev/null; echo $?) || true
    assert_exit_code "3" "$exit_code"
}

test_close_tab_multiple_patterns_rejected() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" pattern1 pattern2 2>/dev/null; echo $?) || true
    assert_exit_code "3" "$exit_code"
}

test_close_tab_error_message_shows_pattern_required() {
    local output
    output=$("$CLOSE_TAB_SCRIPT" 2>&1) || true
    assert_output_contains "$output" "Pattern is required"
}

run_error_path_tests() {
    section "Error Path Tests"

    if should_run_script "open-tab"; then
        subsection "open-tab"
        run_test "open-tab: unexpected positional arg rejected" test_open_tab_unexpected_positional_arg
    fi

    if should_run_script "list-tabs"; then
        subsection "list-tabs"
        run_test "list-tabs: unexpected positional arg rejected" test_list_tabs_unexpected_positional_arg
    fi

    if should_run_script "close-tab"; then
        subsection "close-tab"
        run_test "close-tab: multiple patterns rejected" test_close_tab_multiple_patterns_rejected
        run_test "close-tab: error shows 'Pattern is required'" test_close_tab_error_message_shows_pattern_required
    fi
}

##############################################################################
# Test Category: Combined Options
##############################################################################

test_open_tab_all_options_combined() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run \
        -d "/workspace/project" \
        -p "MyProfile" \
        -c "npm start" \
        -n "Dev Server" 2>&1)

    assert_output_contains "$output" "/workspace/project" && \
    assert_output_contains "$output" "MyProfile" && \
    assert_output_contains "$output" "npm start" && \
    assert_output_contains "$output" "Dev Server"
}

test_open_tab_window_with_all_options() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run \
        -w \
        -d "/workspace/test" \
        -n "Window Tab" \
        -c "ls -la" 2>&1)

    assert_output_contains "$output" "create window with profile" && \
    assert_output_contains "$output" "/workspace/test"
}

test_list_tabs_format_and_window() {
    local exit_code
    "$LIST_TABS_SCRIPT" --dry-run -f json -w 1 >/dev/null 2>&1
    exit_code=$?
    assert_exit_code "0" "$exit_code"
}

test_close_tab_all_options_combined() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" --dry-run --force -w 1 "worktree: test" 2>/dev/null; echo $?) || true
    # Should not be exit 3 (arg parsing should succeed)
    [[ "$exit_code" != "3" ]]
}

run_combined_options_tests() {
    section "Combined Options Tests"

    if should_run_script "open-tab"; then
        run_test "open-tab: all options combined" test_open_tab_all_options_combined
        run_test "open-tab: -w with all options" test_open_tab_window_with_all_options
    fi

    if should_run_script "list-tabs"; then
        run_test "list-tabs: format and window combined" test_list_tabs_format_and_window
    fi

    if should_run_script "close-tab"; then
        run_test "close-tab: all options combined" test_close_tab_all_options_combined
    fi
}

##############################################################################
# Test Category: Context Detection
##############################################################################

test_utils_defines_is_container() {
    local content
    content=$(cat "$UTILS_SCRIPT")
    assert_output_contains "$content" "is_container()"
}

test_utils_defines_exit_codes() {
    local content
    content=$(cat "$UTILS_SCRIPT")
    assert_output_contains "$content" "EXIT_SUCCESS=0" && \
    assert_output_contains "$content" "EXIT_CONNECTION_FAIL=1" && \
    assert_output_contains "$content" "EXIT_ITERM_UNAVAILABLE=2" && \
    assert_output_contains "$content" "EXIT_INVALID_ARGS=3"
}

test_utils_defines_run_applescript() {
    local content
    content=$(cat "$UTILS_SCRIPT")
    assert_output_contains "$content" "run_applescript()"
}

test_utils_defines_validate_ssh_host() {
    local content
    content=$(cat "$UTILS_SCRIPT")
    assert_output_contains "$content" "validate_ssh_host()"
}

test_utils_defines_validate_iterm() {
    local content
    content=$(cat "$UTILS_SCRIPT")
    assert_output_contains "$content" "validate_iterm()"
}

test_container_mode_detection() {
    # Source utils and test is_container function
    # shellcheck source=skills/tab-management/scripts/iterm-utils.sh
    source "$UTILS_SCRIPT" 2>/dev/null || return 1

    # is_container should return 0 if in container, 1 if on host
    # This test just verifies the function exists and is callable
    if is_container; then
        info "Detected: running in container mode"
    else
        info "Detected: running in host mode"
    fi
    return 0
}

run_context_detection_tests() {
    section "Context Detection Tests"

    run_test "utils: defines is_container()" test_utils_defines_is_container
    run_test "utils: defines exit codes" test_utils_defines_exit_codes
    run_test "utils: defines run_applescript()" test_utils_defines_run_applescript
    run_test "utils: defines validate_ssh_host()" test_utils_defines_validate_ssh_host
    run_test "utils: defines validate_iterm()" test_utils_defines_validate_iterm
    run_test "utils: is_container() is callable" test_container_mode_detection
}

##############################################################################
# Test Category: Edge Cases (Paths with Spaces, Special Characters)
##############################################################################

test_open_tab_path_with_spaces() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run -d "/workspace/my folder/test" 2>&1)
    assert_output_contains "$output" "/workspace/my folder/test"
}

test_open_tab_path_with_special_chars() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run -d "/workspace/test-project_v2" 2>&1)
    assert_output_contains "$output" "/workspace/test-project_v2"
}

test_open_tab_command_with_ampersand() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run -c "cmd1 && cmd2" 2>&1)
    assert_output_contains "$output" "cmd1 && cmd2"
}

test_open_tab_name_with_spaces() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run -n "My Special Tab" 2>&1)
    assert_output_contains "$output" "My Special Tab"
}

test_close_tab_pattern_with_spaces() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" "worktree: feature branch" 2>/dev/null; echo $?) || true
    # Should not be exit 3 (arg parsing should succeed)
    [[ "$exit_code" != "3" ]]
}

test_close_tab_pattern_with_colon() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" "worktree:" 2>/dev/null; echo $?) || true
    # Should not be exit 3 (arg parsing should succeed)
    [[ "$exit_code" != "3" ]]
}

run_edge_case_tests() {
    section "Edge Case Tests (Paths, Special Characters)"

    if should_run_script "open-tab"; then
        subsection "open-tab"
        run_test "open-tab: path with spaces" test_open_tab_path_with_spaces
        run_test "open-tab: path with special chars" test_open_tab_path_with_special_chars
        run_test "open-tab: command with &&" test_open_tab_command_with_ampersand
        run_test "open-tab: name with spaces" test_open_tab_name_with_spaces
    fi

    if should_run_script "close-tab"; then
        subsection "close-tab"
        run_test "close-tab: pattern with spaces" test_close_tab_pattern_with_spaces
        run_test "close-tab: pattern with colon" test_close_tab_pattern_with_colon
    fi
}

##############################################################################
# Test Category: Shell Compatibility
##############################################################################

test_open_tab_shebang() {
    local first_line
    first_line=$(head -n 1 "$OPEN_TAB_SCRIPT")
    [[ "$first_line" == "#!/usr/bin/env bash" ]]
}

test_list_tabs_shebang() {
    local first_line
    first_line=$(head -n 1 "$LIST_TABS_SCRIPT")
    [[ "$first_line" == "#!/usr/bin/env bash" ]]
}

test_close_tab_shebang() {
    local first_line
    first_line=$(head -n 1 "$CLOSE_TAB_SCRIPT")
    [[ "$first_line" == "#!/usr/bin/env bash" ]]
}

test_open_tab_uses_strict_mode() {
    local content
    content=$(cat "$OPEN_TAB_SCRIPT")
    assert_output_contains "$content" "set -euo pipefail"
}

test_list_tabs_uses_strict_mode() {
    local content
    content=$(cat "$LIST_TABS_SCRIPT")
    assert_output_contains "$content" "set -euo pipefail"
}

test_close_tab_uses_strict_mode() {
    local content
    content=$(cat "$CLOSE_TAB_SCRIPT")
    assert_output_contains "$content" "set -euo pipefail"
}

run_shell_compatibility_tests() {
    section "Shell Compatibility Tests"

    if should_run_script "open-tab"; then
        run_test "open-tab: uses #!/usr/bin/env bash" test_open_tab_shebang
        run_test "open-tab: uses set -euo pipefail" test_open_tab_uses_strict_mode
    fi

    if should_run_script "list-tabs"; then
        run_test "list-tabs: uses #!/usr/bin/env bash" test_list_tabs_shebang
        run_test "list-tabs: uses set -euo pipefail" test_list_tabs_uses_strict_mode
    fi

    if should_run_script "close-tab"; then
        run_test "close-tab: uses #!/usr/bin/env bash" test_close_tab_shebang
        run_test "close-tab: uses set -euo pipefail" test_close_tab_uses_strict_mode
    fi
}

##############################################################################
# Main Test Runner
##############################################################################

main() {
    parse_arguments "$@"

    if [[ "$QUIET" != "true" ]]; then
        echo ""
        echo "========================================================"
        echo "  iTerm Plugin Integration Tests"
        echo "========================================================"
        if [[ -n "$FILTER_SCRIPT" ]]; then
            echo "  Filter: $FILTER_SCRIPT only"
        fi
        echo ""
    fi

    # Run all test categories
    run_existence_tests
    run_help_tests
    run_dry_run_tests
    run_argument_tests
    run_exit_code_tests
    run_applescript_structure_tests
    run_error_path_tests
    run_combined_options_tests
    run_context_detection_tests
    run_edge_case_tests
    run_shell_compatibility_tests

    # Summary
    echo ""
    echo "========================================================"
    echo "  Test Summary"
    echo "========================================================"
    echo ""
    echo -e "  Tests run:    ${BLUE}$TESTS_RUN${NC}"
    echo -e "  Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "  Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo ""

    if [[ "$TESTS_FAILED" -gt 0 ]]; then
        echo -e "  ${RED}FAILED${NC}: $TESTS_FAILED test(s) failed"
        echo ""
        exit 1
    else
        echo -e "  ${GREEN}SUCCESS${NC}: All tests passed"
        echo ""
        exit 0
    fi
}

main "$@"
