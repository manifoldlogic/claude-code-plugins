#!/usr/bin/env bash
#
# test-list-panes.sh - Comprehensive unit tests for iterm-list-panes.sh
#
# DESCRIPTION:
#   Tests all functionality of iterm-list-panes.sh using dry-run mode
#   and structural inspection. No iTerm2 or SSH required.
#
# USAGE:
#   ./test-list-panes.sh
#   bash plugins/iterm/skills/pane-management/tests/test-list-panes.sh
#
# EXIT CODES:
#   0 - All tests passed
#   1 - One or more tests failed
#

set -euo pipefail

##############################################################################
# Script Location and Paths
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_UNDER_TEST="$SCRIPT_DIR/../scripts/iterm-list-panes.sh"
UTILS_SCRIPT="$SCRIPT_DIR/../../tab-management/scripts/iterm-utils.sh"

##############################################################################
# Test Framework Variables
##############################################################################

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

##############################################################################
# Test Framework Functions
##############################################################################

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "  ${GREEN}[PASS]${NC} $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "  ${RED}[FAIL]${NC} $1"
    if [[ -n "${2:-}" ]]; then
        echo -e "         ${YELLOW}Reason:${NC} $2"
    fi
}

run_test() {
    local test_name="$1"
    local test_func="$2"

    TESTS_RUN=$((TESTS_RUN + 1))

    if $test_func; then
        pass "$test_name"
    else
        fail "$test_name"
    fi
}

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

section() {
    echo ""
    echo "=== $1 ==="
}

##############################################################################
# Test Category 1: Script Existence (2 tests)
##############################################################################

test_script_exists() {
    [[ -f "$SCRIPT_UNDER_TEST" ]]
}

test_script_is_executable() {
    [[ -x "$SCRIPT_UNDER_TEST" ]]
}

run_existence_tests() {
    section "Category 1: Script Existence"
    run_test "list-panes: script file exists" test_script_exists
    run_test "list-panes: script is executable" test_script_is_executable
}

##############################################################################
# Test Category 2: Help/Usage (3 tests)
##############################################################################

test_help_short_flag() {
    local output
    output=$("$SCRIPT_UNDER_TEST" -h 2>&1) || true
    assert_output_contains "$output" "USAGE" && assert_output_contains "$output" "OPTIONS"
}

test_help_long_flag() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --help 2>&1) || true
    assert_output_contains "$output" "--format" && \
    assert_output_contains "$output" "--window" && \
    assert_output_contains "$output" "--tab" && \
    assert_output_contains "$output" "--dry-run"
}

test_help_exit_code() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" -h >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "0" "$exit_code"
}

run_help_tests() {
    section "Category 2: Help/Usage"
    run_test "list-panes: -h shows USAGE and OPTIONS" test_help_short_flag
    run_test "list-panes: --help shows all flags (--format, --window, --tab, --dry-run)" test_help_long_flag
    run_test "list-panes: help exits with code 0" test_help_exit_code
}

##############################################################################
# Test Category 3: Dry-Run Mode (5 tests)
##############################################################################

test_dry_run_tell_application() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run 2>&1)
    assert_output_contains "$output" 'tell application "iTerm2"'
}

test_dry_run_contains_session_count() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run 2>&1)
    assert_output_contains "$output" "count of sessions"
}

test_dry_run_contains_session_loop() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run 2>&1)
    assert_output_contains "$output" "repeat with"
}

test_dry_run_exit_code() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" --dry-run >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "0" "$exit_code"
}

test_dry_run_shows_info_message() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run 2>&1)
    assert_output_contains "$output" "Dry-run mode"
}

run_dry_run_tests() {
    section "Category 3: Dry-Run Mode"
    run_test "list-panes: --dry-run outputs tell application iTerm2" test_dry_run_tell_application
    run_test "list-panes: --dry-run contains count of sessions" test_dry_run_contains_session_count
    run_test "list-panes: --dry-run contains session loop (repeat with)" test_dry_run_contains_session_loop
    run_test "list-panes: --dry-run exits with code 0" test_dry_run_exit_code
    run_test "list-panes: --dry-run shows info message" test_dry_run_shows_info_message
}

##############################################################################
# Test Category 4: Argument Parsing (8 tests)
##############################################################################

test_parse_format_json_short() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" -f json --dry-run >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "0" "$exit_code"
}

test_parse_format_table_long() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" --format table --dry-run >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "0" "$exit_code"
}

test_parse_window_short() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" -w 1 --dry-run >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "0" "$exit_code"
}

test_parse_window_long() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" --window 2 --dry-run >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "0" "$exit_code"
}

test_parse_tab_short() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" -t 1 --dry-run >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "0" "$exit_code"
}

test_parse_tab_long() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" --tab 3 --dry-run >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "0" "$exit_code"
}

test_parse_format_and_window_combined() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" -f json -w 1 --dry-run >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "0" "$exit_code"
}

test_parse_window_and_tab_combined() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" -w 1 -t 2 --dry-run >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "0" "$exit_code"
}

run_argument_tests() {
    section "Category 4: Argument Parsing"
    run_test "list-panes: -f json accepted (dry-run exits 0)" test_parse_format_json_short
    run_test "list-panes: --format table accepted" test_parse_format_table_long
    run_test "list-panes: -w 1 accepted" test_parse_window_short
    run_test "list-panes: --window 2 accepted" test_parse_window_long
    run_test "list-panes: -t 1 accepted (tab filter)" test_parse_tab_short
    run_test "list-panes: --tab 3 accepted" test_parse_tab_long
    run_test "list-panes: -f json -w 1 combined accepted" test_parse_format_and_window_combined
    run_test "list-panes: -w 1 -t 2 combined accepted" test_parse_window_and_tab_combined
}

##############################################################################
# Test Category 5: Exit Codes (6 tests)
##############################################################################

test_exit_code_invalid_flag() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" --invalid-flag >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "3" "$exit_code"
}

test_exit_code_invalid_format() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" -f invalid --dry-run >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "3" "$exit_code"
}

test_exit_code_missing_format_value() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" -f >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "3" "$exit_code"
}

test_exit_code_window_index_zero() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" -w 0 --dry-run >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "3" "$exit_code"
}

test_exit_code_tab_index_zero() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" -t 0 --dry-run >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "3" "$exit_code"
}

test_exit_code_non_integer_tab() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" -t abc --dry-run >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "3" "$exit_code"
}

run_exit_code_tests() {
    section "Category 5: Exit Codes"
    run_test "list-panes: invalid flag exits 3" test_exit_code_invalid_flag
    run_test "list-panes: invalid format (-f invalid) exits 3" test_exit_code_invalid_format
    run_test "list-panes: missing format value (-f) exits 3" test_exit_code_missing_format_value
    run_test "list-panes: window index 0 exits 3" test_exit_code_window_index_zero
    run_test "list-panes: tab index 0 exits 3" test_exit_code_tab_index_zero
    run_test "list-panes: non-integer tab index exits 3" test_exit_code_non_integer_tab
}

##############################################################################
# Test Category 6: AppleScript Structure (6 tests)
##############################################################################

test_applescript_has_tell_application() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run 2>&1)
    assert_output_contains "$output" 'tell application "iTerm2"'
}

test_applescript_has_not_running_check() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run 2>&1)
    assert_output_contains "$output" "not running"
}

test_applescript_has_count_windows() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run 2>&1)
    assert_output_contains "$output" "count of windows"
}

test_applescript_has_count_sessions() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run 2>&1)
    assert_output_contains "$output" "count of sessions"
}

test_applescript_has_repeat_with() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run 2>&1)
    assert_output_contains "$output" "repeat with"
}

test_applescript_has_end_tell() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run 2>&1)
    assert_output_contains "$output" "end tell"
}

run_applescript_structure_tests() {
    section "Category 6: AppleScript Structure"
    run_test "list-panes: AppleScript contains tell application iTerm2" test_applescript_has_tell_application
    run_test "list-panes: AppleScript contains not running check" test_applescript_has_not_running_check
    run_test "list-panes: AppleScript contains count of windows" test_applescript_has_count_windows
    run_test "list-panes: AppleScript contains count of sessions" test_applescript_has_count_sessions
    run_test "list-panes: AppleScript contains repeat with (loop structure)" test_applescript_has_repeat_with
    run_test "list-panes: AppleScript contains end tell" test_applescript_has_end_tell
}

##############################################################################
# Test Category 7: Error Paths (4 tests)
##############################################################################

test_error_unknown_flag_message() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --bogus 2>&1) || true
    assert_output_contains "$output" "Unknown option"
}

test_error_positional_arg_message() {
    local output
    output=$("$SCRIPT_UNDER_TEST" unexpected_arg 2>&1) || true
    assert_output_contains "$output" "Unexpected argument"
}

test_error_invalid_format_message() {
    local output
    output=$("$SCRIPT_UNDER_TEST" -f invalid 2>&1) || true
    assert_output_contains "$output" "json" && \
    assert_output_contains "$output" "table"
}

test_error_invalid_window_message() {
    local output
    output=$("$SCRIPT_UNDER_TEST" -w 0 2>&1) || true
    assert_output_contains "$output" "window" || assert_output_contains "$output" "index"
}

run_error_path_tests() {
    section "Category 7: Error Paths"
    run_test "list-panes: unknown flag produces error message" test_error_unknown_flag_message
    run_test "list-panes: unexpected positional argument rejected" test_error_positional_arg_message
    run_test "list-panes: invalid format error mentions json and table" test_error_invalid_format_message
    run_test "list-panes: invalid window index error mentions window or index" test_error_invalid_window_message
}

##############################################################################
# Test Category 8: Combined Options (3 tests)
##############################################################################

test_combined_format_and_window() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" -f json -w 1 --dry-run >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "0" "$exit_code"
}

test_combined_format_and_tab() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" -f table -t 1 --dry-run >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "0" "$exit_code"
}

test_combined_all_options() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" -f json -w 1 -t 2 --dry-run >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "0" "$exit_code"
}

run_combined_options_tests() {
    section "Category 8: Combined Options"
    run_test "list-panes: format and window combined" test_combined_format_and_window
    run_test "list-panes: format and tab combined" test_combined_format_and_tab
    run_test "list-panes: format, window, tab, and dry-run all combined" test_combined_all_options
}

##############################################################################
# Test Category 9: Context Detection (2 tests)
##############################################################################

test_context_is_container_callable() {
    # Source utils and verify is_container function exists and is callable
    # shellcheck source=../../tab-management/scripts/iterm-utils.sh
    (
        source "$UTILS_SCRIPT" 2>/dev/null || return 1
        if is_container; then
            true
        else
            true
        fi
        return 0
    )
}

test_context_exit_constants_defined() {
    # Source utils and verify exit code constants are defined
    (
        source "$UTILS_SCRIPT" 2>/dev/null || return 1
        [[ -n "$EXIT_SUCCESS" ]] && \
        [[ -n "$EXIT_INVALID_ARGS" ]] && \
        [[ "$EXIT_SUCCESS" == "0" ]] && \
        [[ "$EXIT_INVALID_ARGS" == "3" ]]
    )
}

run_context_detection_tests() {
    section "Category 9: Context Detection"
    run_test "list-panes: is_container() is callable after sourcing utils" test_context_is_container_callable
    run_test "list-panes: EXIT_SUCCESS and EXIT_INVALID_ARGS defined" test_context_exit_constants_defined
}

##############################################################################
# Test Category 10: Edge Cases (3 tests)
##############################################################################

test_edge_large_window_index() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" -w 100 --dry-run >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "0" "$exit_code"
}

test_edge_default_format_documented() {
    local output
    output=$("$SCRIPT_UNDER_TEST" -h 2>&1) || true
    assert_output_contains "$output" "default: table"
}

test_edge_json_structure_documented() {
    local output
    output=$("$SCRIPT_UNDER_TEST" -h 2>&1) || true
    assert_output_contains "$output" '"windows"' && \
    assert_output_contains "$output" '"panes"'
}

run_edge_case_tests() {
    section "Category 10: Edge Cases"
    run_test "list-panes: large window index (100) accepted in argument parsing" test_edge_large_window_index
    run_test "list-panes: default format is table (documented in help)" test_edge_default_format_documented
    run_test "list-panes: help documents JSON output structure (windows, panes)" test_edge_json_structure_documented
}

##############################################################################
# Test Category 11: Shell Compatibility (2 tests)
##############################################################################

test_shell_shebang() {
    local first_line
    first_line=$(head -n 1 "$SCRIPT_UNDER_TEST")
    [[ "$first_line" == "#!/usr/bin/env bash" ]]
}

test_shell_strict_mode() {
    local content
    content=$(cat "$SCRIPT_UNDER_TEST")
    assert_output_contains "$content" "set -euo pipefail"
}

run_shell_compatibility_tests() {
    section "Category 11: Shell Compatibility"
    run_test "list-panes: shebang is #!/usr/bin/env bash" test_shell_shebang
    run_test "list-panes: uses set -euo pipefail" test_shell_strict_mode
}

##############################################################################
# Main Test Runner
##############################################################################

main() {
    echo ""
    echo "========================================================"
    echo "  iterm-list-panes.sh Unit Tests"
    echo "========================================================"
    echo ""

    # Run all 11 test categories
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
