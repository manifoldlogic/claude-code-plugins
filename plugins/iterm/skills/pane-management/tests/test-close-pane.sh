#!/usr/bin/env bash
#
# test-close-pane.sh - Comprehensive unit tests for iterm-close-pane.sh
#
# DESCRIPTION:
#   Tests all functionality of iterm-close-pane.sh using dry-run mode
#   and structural inspection. No iTerm2 or SSH required.
#
# USAGE:
#   ./test-close-pane.sh
#   bash plugins/iterm/skills/pane-management/tests/test-close-pane.sh
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
SCRIPT_UNDER_TEST="$SCRIPT_DIR/../scripts/iterm-close-pane.sh"
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

test_script_executable() {
    [[ -x "$SCRIPT_UNDER_TEST" ]]
}

run_existence_tests() {
    section "Script Existence Tests"
    run_test "close-pane: script file exists" test_script_exists
    run_test "close-pane: script is executable" test_script_executable
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
    assert_output_contains "$output" "iterm-close-pane.sh" && \
    assert_output_contains "$output" "--window" && \
    assert_output_contains "$output" "--tab" && \
    assert_output_contains "$output" "--force" && \
    assert_output_contains "$output" "--dry-run"
}

test_help_exit_code() {
    "$SCRIPT_UNDER_TEST" -h >/dev/null 2>&1
    local exit_code=$?
    assert_exit_code "0" "$exit_code"
}

run_help_tests() {
    section "Help/Usage Tests"
    run_test "close-pane: -h shows USAGE and OPTIONS" test_help_short_flag
    run_test "close-pane: --help shows all flags" test_help_long_flag
    run_test "close-pane: help exits with code 0" test_help_exit_code
}

##############################################################################
# Test Category 3: Dry-Run Mode (5 tests)
##############################################################################

test_dry_run_exits_zero() {
    "$SCRIPT_UNDER_TEST" --dry-run "test" >/dev/null 2>&1
    local exit_code=$?
    assert_exit_code "0" "$exit_code"
}

test_dry_run_shows_query_applescript() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run "test" 2>&1)
    assert_output_contains "$output" "repeat with w" && \
    assert_output_contains "$output" "repeat with t" && \
    assert_output_contains "$output" "repeat with s"
}

test_dry_run_shows_close_applescript() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run "test" 2>&1)
    assert_output_contains "$output" "to 1 by -1"
}

test_dry_run_shows_pattern_in_close() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run "mypattern" 2>&1)
    assert_output_contains "$output" "contains \"mypattern\""
}

test_dry_run_with_window_filter() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -w 1 "test" 2>&1)
    assert_output_contains "$output" "tell window 1"
}

run_dry_run_tests() {
    section "Dry-Run Mode Tests"
    run_test "close-pane: --dry-run exits with code 0" test_dry_run_exits_zero
    run_test "close-pane: --dry-run shows query AppleScript with session loop" test_dry_run_shows_query_applescript
    run_test "close-pane: --dry-run shows close AppleScript with reverse iteration" test_dry_run_shows_close_applescript
    run_test "close-pane: --dry-run shows pattern in close AppleScript contains clause" test_dry_run_shows_pattern_in_close
    run_test "close-pane: --dry-run -w 1 includes window targeting" test_dry_run_with_window_filter
}

##############################################################################
# Test Category 4: Argument Parsing (8 tests)
##############################################################################

test_pattern_required() {
    local exit_code=0
    "$SCRIPT_UNDER_TEST" 2>/dev/null || exit_code=$?
    assert_exit_code "3" "$exit_code"
}

test_window_short_flag() {
    local exit_code=0
    "$SCRIPT_UNDER_TEST" --dry-run -w 1 "test" >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "0" "$exit_code"
}

test_window_long_flag() {
    local exit_code=0
    "$SCRIPT_UNDER_TEST" --dry-run --window 1 "test" >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "0" "$exit_code"
}

test_tab_short_flag() {
    local exit_code=0
    "$SCRIPT_UNDER_TEST" --dry-run -t 1 "test" >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "0" "$exit_code"
}

test_tab_long_flag() {
    local exit_code=0
    "$SCRIPT_UNDER_TEST" --dry-run --tab 1 "test" >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "0" "$exit_code"
}

test_force_flag() {
    local exit_code=0
    "$SCRIPT_UNDER_TEST" --dry-run --force "test" >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "0" "$exit_code"
}

test_dry_run_flag() {
    local exit_code=0
    "$SCRIPT_UNDER_TEST" --dry-run "test" >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "0" "$exit_code"
}

test_combined_flags() {
    local exit_code=0
    "$SCRIPT_UNDER_TEST" -w 1 -t 2 --force --dry-run "test" >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "0" "$exit_code"
}

run_argument_tests() {
    section "Argument Parsing Tests"
    run_test "close-pane: pattern is required (no pattern exits 3)" test_pattern_required
    run_test "close-pane: -w 1 accepted without error" test_window_short_flag
    run_test "close-pane: --window 1 accepted without error" test_window_long_flag
    run_test "close-pane: -t 1 accepted without error" test_tab_short_flag
    run_test "close-pane: --tab 1 accepted without error" test_tab_long_flag
    run_test "close-pane: --force accepted without error" test_force_flag
    run_test "close-pane: --dry-run accepted" test_dry_run_flag
    run_test "close-pane: combined flags -w 1 -t 2 --force --dry-run all accepted" test_combined_flags
}

##############################################################################
# Test Category 5: Exit Codes (6 tests)
##############################################################################

test_missing_pattern_exits_3() {
    local exit_code=0
    "$SCRIPT_UNDER_TEST" 2>/dev/null || exit_code=$?
    assert_exit_code "3" "$exit_code"
}

test_unknown_flag_exits_3() {
    local exit_code=0
    "$SCRIPT_UNDER_TEST" --bogus 2>/dev/null || exit_code=$?
    assert_exit_code "3" "$exit_code"
}

test_invalid_window_exits_3() {
    local exit_code=0
    "$SCRIPT_UNDER_TEST" -w abc "test" 2>/dev/null || exit_code=$?
    assert_exit_code "3" "$exit_code"
}

test_invalid_tab_exits_3() {
    local exit_code=0
    "$SCRIPT_UNDER_TEST" -t abc "test" 2>/dev/null || exit_code=$?
    assert_exit_code "3" "$exit_code"
}

test_window_zero_exits_3() {
    local exit_code=0
    "$SCRIPT_UNDER_TEST" -w 0 "test" 2>/dev/null || exit_code=$?
    assert_exit_code "3" "$exit_code"
}

test_tab_zero_exits_3() {
    local exit_code=0
    "$SCRIPT_UNDER_TEST" -t 0 "test" 2>/dev/null || exit_code=$?
    assert_exit_code "3" "$exit_code"
}

run_exit_code_tests() {
    section "Exit Code Tests"
    run_test "close-pane: missing pattern exits 3" test_missing_pattern_exits_3
    run_test "close-pane: unknown flag --bogus exits 3" test_unknown_flag_exits_3
    run_test "close-pane: invalid window -w abc exits 3" test_invalid_window_exits_3
    run_test "close-pane: invalid tab -t abc exits 3" test_invalid_tab_exits_3
    run_test "close-pane: window zero -w 0 exits 3" test_window_zero_exits_3
    run_test "close-pane: tab zero -t 0 exits 3" test_tab_zero_exits_3
}

##############################################################################
# Test Category 6: AppleScript Structure (7 tests)
##############################################################################

test_query_has_triple_nested_repeat() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run "test" 2>&1)
    # Query AppleScript has three nested repeat with statements (w, t, s)
    local count
    count=$(echo "$output" | grep -c "repeat with" || true)
    [[ "$count" -ge 3 ]]
}

test_query_has_session_name() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run "test" 2>&1)
    assert_output_contains "$output" "name of session s"
}

test_query_uses_unit_separator() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run "test" 2>&1)
    assert_output_contains "$output" "ASCII character 31"
}

test_close_has_reverse_iteration() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run "test" 2>&1)
    assert_output_contains "$output" "to 1 by -1"
}

test_close_has_contains_keyword() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run "test" 2>&1)
    assert_output_contains "$output" "contains"
}

test_close_has_close_command() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run "test" 2>&1)
    assert_output_contains "$output" "to close"
}

test_close_has_error_handling() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run "test" 2>&1)
    assert_output_contains "$output" "on error"
}

run_applescript_structure_tests() {
    section "AppleScript Structure Tests"
    run_test "close-pane: query AppleScript has 3 nested repeat with statements" test_query_has_triple_nested_repeat
    run_test "close-pane: query AppleScript reads name of session s" test_query_has_session_name
    run_test "close-pane: query AppleScript uses ASCII character 31" test_query_uses_unit_separator
    run_test "close-pane: close AppleScript has reverse iteration (to 1 by -1)" test_close_has_reverse_iteration
    run_test "close-pane: close AppleScript has contains for pattern matching" test_close_has_contains_keyword
    run_test "close-pane: close AppleScript has close command" test_close_has_close_command
    run_test "close-pane: close AppleScript has on error block" test_close_has_error_handling
}

##############################################################################
# Test Category 7: Error Paths (4 tests)
##############################################################################

test_unknown_flag_shows_error() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --bogus 2>&1) || true
    assert_output_contains "$output" "Unknown option"
}

test_extra_positional_shows_error() {
    local output
    output=$("$SCRIPT_UNDER_TEST" "first" "second" 2>&1) || true
    assert_output_contains "$output" "Only one pattern"
}

test_missing_window_value_shows_error() {
    local output
    output=$("$SCRIPT_UNDER_TEST" -w 2>&1) || true
    assert_output_contains "$output" "requires"
}

test_missing_tab_value_shows_error() {
    local output
    output=$("$SCRIPT_UNDER_TEST" -t 2>&1) || true
    assert_output_contains "$output" "requires"
}

run_error_path_tests() {
    section "Error Path Tests"
    run_test "close-pane: unknown flag shows error message" test_unknown_flag_shows_error
    run_test "close-pane: extra positional arg shows error" test_extra_positional_shows_error
    run_test "close-pane: -w without value shows error" test_missing_window_value_shows_error
    run_test "close-pane: -t without value shows error" test_missing_tab_value_shows_error
}

##############################################################################
# Test Category 8: Combined Options (4 tests)
##############################################################################

test_pattern_with_window() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -w 2 "agent" 2>&1)
    assert_output_contains "$output" "tell window 2"
}

test_pattern_with_tab() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -t 3 "agent" 2>&1)
    assert_output_contains "$output" "tab 3"
}

test_pattern_with_window_and_tab() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -w 1 -t 2 "agent" 2>&1)
    assert_output_contains "$output" "tell window 1" && \
    assert_output_contains "$output" "tab 2"
}

test_all_options() {
    local exit_code=0
    "$SCRIPT_UNDER_TEST" --dry-run --force -w 1 -t 1 "test" >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "0" "$exit_code"
}

run_combined_options_tests() {
    section "Combined Options Tests"
    run_test "close-pane: pattern with -w 2 targets window 2" test_pattern_with_window
    run_test "close-pane: pattern with -t 3 references tab 3" test_pattern_with_tab
    run_test "close-pane: -w 1 -t 2 both reflected in AppleScript" test_pattern_with_window_and_tab
    run_test "close-pane: all options --force -w 1 -t 1 accepted, exit 0" test_all_options
}

##############################################################################
# Test Category 9: Context Detection (2 tests)
##############################################################################

test_utils_sourced() {
    # Verify that iterm-utils.sh can be sourced successfully
    (
        source "$UTILS_SCRIPT" 2>/dev/null || return 1
        return 0
    )
}

test_exit_constants_defined() {
    # Source utils and verify exit code constants are defined
    (
        source "$UTILS_SCRIPT" 2>/dev/null || return 1
        [[ -n "$EXIT_SUCCESS" ]] && \
        [[ -n "$EXIT_INVALID_ARGS" ]] && \
        [[ -n "$EXIT_NO_MATCH" ]] && \
        [[ "$EXIT_SUCCESS" == "0" ]] && \
        [[ "$EXIT_INVALID_ARGS" == "3" ]] && \
        [[ "$EXIT_NO_MATCH" == "4" ]]
    )
}

run_context_detection_tests() {
    section "Context Detection Tests"
    run_test "close-pane: iterm-utils.sh sources successfully" test_utils_sourced
    run_test "close-pane: EXIT_SUCCESS, EXIT_INVALID_ARGS, EXIT_NO_MATCH defined" test_exit_constants_defined
}

##############################################################################
# Test Category 10: Edge Cases (4 tests)
##############################################################################

test_pattern_with_spaces() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run "my agent" 2>&1)
    assert_output_contains "$output" "my agent"
}

test_pattern_with_quotes() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run 'has"quotes' 2>&1)
    # Pattern with double quotes should be escaped in AppleScript output
    assert_output_contains "$output" 'has\"quotes'
}

test_large_window_index() {
    local exit_code=0
    "$SCRIPT_UNDER_TEST" --dry-run -w 999 "test" >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "0" "$exit_code"
}

test_help_documents_last_pane_note() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --help 2>&1) || true
    assert_output_contains "$output" "last pane"
}

run_edge_case_tests() {
    section "Edge Case Tests"
    run_test "close-pane: pattern with spaces works" test_pattern_with_spaces
    run_test "close-pane: pattern with quotes handled" test_pattern_with_quotes
    run_test "close-pane: large window index -w 999 accepted in dry-run" test_large_window_index
    run_test "close-pane: help text documents last pane closure warning" test_help_documents_last_pane_note
}

##############################################################################
# Test Category 11: Shell Compatibility (2 tests)
##############################################################################

test_shebang() {
    local first_line
    first_line=$(head -n 1 "$SCRIPT_UNDER_TEST")
    [[ "$first_line" == "#!/usr/bin/env bash" ]]
}

test_strict_mode() {
    local content
    content=$(cat "$SCRIPT_UNDER_TEST")
    assert_output_contains "$content" "set -euo pipefail"
}

run_shell_compatibility_tests() {
    section "Shell Compatibility Tests"
    run_test "close-pane: shebang is #!/usr/bin/env bash" test_shebang
    run_test "close-pane: uses set -euo pipefail" test_strict_mode
}

##############################################################################
# Main Test Runner
##############################################################################

main() {
    echo ""
    echo "========================================================"
    echo "  iterm-close-pane.sh Unit Tests"
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
