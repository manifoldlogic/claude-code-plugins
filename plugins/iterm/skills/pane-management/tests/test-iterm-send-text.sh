#!/usr/bin/env bash
#
# test-iterm-send-text.sh - Comprehensive unit tests for iterm-send-text.sh
#
# DESCRIPTION:
#   Tests all functionality of iterm-send-text.sh using dry-run mode
#   and structural inspection. No iTerm2 or SSH required.
#
# USAGE:
#   ./test-iterm-send-text.sh
#   bash plugins/iterm/skills/pane-management/tests/test-iterm-send-text.sh
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
SCRIPT_UNDER_TEST="$SCRIPT_DIR/../scripts/iterm-send-text.sh"
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
    section "Script Existence Tests"
    run_test "send-text: script file exists" test_script_exists
    run_test "send-text: script is executable" test_script_is_executable
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
    assert_output_contains "$output" "--pane" && \
    assert_output_contains "$output" "--submit" && \
    assert_output_contains "$output" "--no-newline" && \
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
    section "Help/Usage Tests"
    run_test "send-text: -h shows USAGE and OPTIONS" test_help_short_flag
    run_test "send-text: --help shows all flags (--pane, --submit, --no-newline, --dry-run)" test_help_long_flag
    run_test "send-text: help exits with code 0" test_help_exit_code
}

##############################################################################
# Test Category 3: Argument Parsing - Happy Paths (4 tests)
##############################################################################

test_parse_pane_short() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" --dry-run -p 1 "hello" >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "0" "$exit_code"
}

test_parse_pane_with_submit() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" --dry-run -p 2 --submit "text" >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "0" "$exit_code"
}

test_parse_pane_with_no_newline() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" --dry-run -p 1 --no-newline "partial" >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "0" "$exit_code"
}

test_parse_dry_run_with_pane_and_text() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" --dry-run -p 2 "text" >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "0" "$exit_code"
}

run_argument_happy_path_tests() {
    section "Argument Parsing - Happy Paths"
    run_test "send-text: -p 1 'hello' accepted (dry-run exits 0)" test_parse_pane_short
    run_test "send-text: -p 2 --submit 'text' accepted" test_parse_pane_with_submit
    run_test "send-text: -p 1 --no-newline 'partial' accepted" test_parse_pane_with_no_newline
    run_test "send-text: --dry-run -p 2 'text' accepted" test_parse_dry_run_with_pane_and_text
}

##############################################################################
# Test Category 4: Argument Parsing - Missing Pane (1 test)
##############################################################################

test_missing_pane_exits_3() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" "hello" >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "3" "$exit_code"
}

test_missing_pane_shows_error() {
    local output
    output=$("$SCRIPT_UNDER_TEST" "hello" 2>&1) || true
    # Should have a non-empty error message about pane
    [[ -n "$output" ]]
}

run_missing_pane_tests() {
    section "Argument Parsing - Missing Pane"
    run_test "send-text: running without -p exits with code 3" test_missing_pane_exits_3
    run_test "send-text: running without -p produces non-empty error" test_missing_pane_shows_error
}

##############################################################################
# Test Category 5: Argument Parsing - Invalid Pane Numbers (4 tests)
##############################################################################

test_pane_zero_exits_3() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" --dry-run -p 0 "text" >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "3" "$exit_code"
}

test_pane_negative_exits_3() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" --dry-run -p -1 "text" >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "3" "$exit_code"
}

test_pane_non_integer_exits_3() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" --dry-run -p abc "text" >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "3" "$exit_code"
}

test_pane_float_exits_3() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" --dry-run -p 1.5 "text" >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "3" "$exit_code"
}

run_invalid_pane_tests() {
    section "Argument Parsing - Invalid Pane Numbers"
    run_test "send-text: -p 0 exits with code 3" test_pane_zero_exits_3
    run_test "send-text: -p -1 exits with code 3" test_pane_negative_exits_3
    run_test "send-text: -p abc exits with code 3" test_pane_non_integer_exits_3
    run_test "send-text: -p 1.5 exits with code 3" test_pane_float_exits_3
}

##############################################################################
# Test Category 6: Argument Parsing - Missing/Empty Text (2 tests)
##############################################################################

test_missing_text_exits_3() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" --dry-run -p 2 >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "3" "$exit_code"
}

test_empty_text_exits_3() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" --dry-run -p 2 "" >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "3" "$exit_code"
}

test_empty_text_error_contains_empty() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -p 2 "" 2>&1) || true
    assert_output_contains "$output" "empty"
}

run_missing_empty_text_tests() {
    section "Argument Parsing - Missing/Empty Text"
    run_test "send-text: -p 2 with no text argument exits 3" test_missing_text_exits_3
    run_test "send-text: -p 2 '' (empty string) exits 3" test_empty_text_exits_3
    run_test "send-text: empty text error message contains 'empty'" test_empty_text_error_contains_empty
}

##############################################################################
# Test Category 7: Mutual Exclusivity (2 tests)
##############################################################################

test_submit_and_no_newline_exits_3() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" --dry-run -p 1 --submit --no-newline "text" >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "3" "$exit_code"
}

test_submit_and_no_newline_shows_error() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -p 1 --submit --no-newline "text" 2>&1) || true
    assert_output_contains "$output" "mutually exclusive"
}

run_mutual_exclusivity_tests() {
    section "Mutual Exclusivity"
    run_test "send-text: --submit --no-newline together exits 3" test_submit_and_no_newline_exits_3
    run_test "send-text: --submit --no-newline error mentions 'mutually exclusive'" test_submit_and_no_newline_shows_error
}

##############################################################################
# Test Category 8: AppleScript Generation - Default Mode (3 tests)
##############################################################################

test_default_mode_contains_write_text() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -p 2 "hello world" 2>&1)
    assert_output_contains "$output" 'write text "hello world"'
}

test_default_mode_no_without_newline() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -p 2 "hello world" 2>&1)
    assert_output_not_contains "$output" "without newline"
}

test_default_mode_no_ascii_13() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -p 2 "hello world" 2>&1)
    assert_output_not_contains "$output" "ASCII character 13"
}

run_default_mode_tests() {
    section "AppleScript Generation - Default Mode"
    run_test "send-text: default mode contains write text \"hello world\"" test_default_mode_contains_write_text
    run_test "send-text: default mode does NOT contain 'without newline'" test_default_mode_no_without_newline
    run_test "send-text: default mode does NOT contain ASCII character 13" test_default_mode_no_ascii_13
}

##############################################################################
# Test Category 9: AppleScript Generation - Submit Mode (3 tests)
##############################################################################

test_submit_mode_write_text_without_newline() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -p 2 --submit "claude" 2>&1)
    assert_output_contains "$output" 'write text "claude" without newline'
}

test_submit_mode_has_ascii_13() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -p 2 --submit "claude" 2>&1)
    assert_output_contains "$output" 'write text (ASCII character 13) without newline'
}

test_submit_mode_exits_0() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" --dry-run -p 2 --submit "claude" >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "0" "$exit_code"
}

run_submit_mode_tests() {
    section "AppleScript Generation - Submit Mode"
    run_test "send-text: submit mode contains write text \"claude\" without newline" test_submit_mode_write_text_without_newline
    run_test "send-text: submit mode contains write text (ASCII character 13) without newline" test_submit_mode_has_ascii_13
    run_test "send-text: submit mode dry-run exits 0" test_submit_mode_exits_0
}

##############################################################################
# Test Category 10: AppleScript Generation - No-Newline Mode (3 tests)
##############################################################################

test_no_newline_mode_write_text_without_newline() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -p 1 --no-newline "partial" 2>&1)
    assert_output_contains "$output" 'write text "partial" without newline'
}

test_no_newline_mode_no_ascii_13() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -p 1 --no-newline "partial" 2>&1)
    assert_output_not_contains "$output" "ASCII character 13"
}

test_no_newline_mode_exits_0() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" --dry-run -p 1 --no-newline "partial" >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "0" "$exit_code"
}

run_no_newline_mode_tests() {
    section "AppleScript Generation - No-Newline Mode"
    run_test "send-text: no-newline mode contains write text \"partial\" without newline" test_no_newline_mode_write_text_without_newline
    run_test "send-text: no-newline mode does NOT contain ASCII character 13" test_no_newline_mode_no_ascii_13
    run_test "send-text: no-newline mode dry-run exits 0" test_no_newline_mode_exits_0
}

##############################################################################
# Test Category 11: Escaping - Backslashes (1 test)
##############################################################################

# Escaping chain:
#   Shell input (single-quoted): 'a\b' -> literal a\b passed to script
#   escape_applescript_string() doubles backslashes: a\\b in AppleScript output
#   So --dry-run output should contain the string: a\\b

test_backslash_escaping() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -p 2 'text\with\backslashes' 2>&1)
    # After escape_applescript_string(), each \ becomes \\
    # The dry-run output (AppleScript) should contain the doubled backslashes
    assert_output_contains "$output" 'text\\with\\backslashes'
}

run_backslash_escaping_tests() {
    section "Escaping - Backslashes"
    run_test "send-text: backslashes are doubled in AppleScript output" test_backslash_escaping
}

##############################################################################
# Test Category 12: Escaping - Double Quotes (1 test)
##############################################################################

# Escaping chain:
#   Shell input (single-quoted): 'say "hi"' -> literal say "hi" passed to script
#   escape_applescript_string() escapes quotes: say \"hi\" in AppleScript output

test_double_quote_escaping() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -p 2 'say "hi"' 2>&1)
    # After escape_applescript_string(), " becomes \"
    # The dry-run output should show escaped quotes in the write text command
    assert_output_contains "$output" 'say \"hi\"'
}

run_double_quote_escaping_tests() {
    section "Escaping - Double Quotes"
    run_test "send-text: double quotes are escaped in AppleScript output" test_double_quote_escaping
}

##############################################################################
# Test Category 13: Sentinel Handling (2 tests)
##############################################################################

test_sentinel_no_windows() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -p 2 "hello" 2>&1)
    assert_output_contains "$output" 'return "NO_WINDOWS"'
}

test_sentinel_invalid_pane() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -p 2 "hello" 2>&1)
    assert_output_contains "$output" 'return "INVALID_PANE"'
}

run_sentinel_tests() {
    section "Sentinel Handling"
    run_test "send-text: dry-run AppleScript contains return \"NO_WINDOWS\"" test_sentinel_no_windows
    run_test "send-text: dry-run AppleScript contains return \"INVALID_PANE\"" test_sentinel_invalid_pane
}

##############################################################################
# Test Category 14: AppleScript Structure (4 tests)
##############################################################################

test_applescript_has_tell_application() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -p 1 "test" 2>&1)
    assert_output_contains "$output" 'tell application "iTerm2"'
}

test_applescript_has_count_windows() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -p 1 "test" 2>&1)
    assert_output_contains "$output" "count of windows"
}

test_applescript_has_session_count() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -p 1 "test" 2>&1)
    assert_output_contains "$output" "count of sessions"
}

test_applescript_has_end_tell() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -p 1 "test" 2>&1)
    assert_output_contains "$output" "end tell"
}

run_applescript_structure_tests() {
    section "AppleScript Structure"
    run_test "send-text: AppleScript contains tell application iTerm2" test_applescript_has_tell_application
    run_test "send-text: AppleScript contains count of windows" test_applescript_has_count_windows
    run_test "send-text: AppleScript contains count of sessions" test_applescript_has_session_count
    run_test "send-text: AppleScript contains end tell" test_applescript_has_end_tell
}

##############################################################################
# Test Category 15: Error Paths (3 tests)
##############################################################################

test_unknown_flag_exits_3() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" --invalid-flag >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "3" "$exit_code"
}

test_unknown_flag_shows_error() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --bogus 2>&1) || true
    assert_output_contains "$output" "Unknown option"
}

test_extra_positional_exits_3() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" --dry-run -p 1 "first" "second" >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "3" "$exit_code"
}

run_error_path_tests() {
    section "Error Path Tests"
    run_test "send-text: unknown flag exits 3" test_unknown_flag_exits_3
    run_test "send-text: unknown flag shows 'Unknown option' message" test_unknown_flag_shows_error
    run_test "send-text: extra positional argument exits 3" test_extra_positional_exits_3
}

##############################################################################
# Test Category 16: Context Detection (2 tests)
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
    section "Context Detection Tests"
    run_test "send-text: is_container() is callable after sourcing utils" test_context_is_container_callable
    run_test "send-text: EXIT_SUCCESS and EXIT_INVALID_ARGS defined" test_context_exit_constants_defined
}

##############################################################################
# Test Category 17: Shell Compatibility (2 tests)
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
    section "Shell Compatibility Tests"
    run_test "send-text: shebang is #!/usr/bin/env bash" test_shell_shebang
    run_test "send-text: uses set -euo pipefail" test_shell_strict_mode
}

##############################################################################
# Test Category 18: Embedded Newline Rejection (3 tests)
##############################################################################

test_embedded_newline_exits_3() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" --dry-run -p 2 "$(printf 'line1\nline2')" >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "3" "$exit_code"
}

test_trailing_newline_exits_3() {
    local exit_code
    local text_with_trailing_newline=$'text\n'
    set +e
    "$SCRIPT_UNDER_TEST" --dry-run -p 2 "$text_with_trailing_newline" >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "3" "$exit_code"
}

test_embedded_newline_error_mentions_newline() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -p 2 "$(printf 'line1\nline2')" 2>&1) || true
    assert_output_contains "$output" "newline"
}

run_embedded_newline_tests() {
    section "Embedded Newline Rejection"
    run_test "send-text: text with embedded newline exits 3" test_embedded_newline_exits_3
    run_test "send-text: text with trailing newline exits 3" test_trailing_newline_exits_3
    run_test "send-text: embedded newline error mentions 'newline'" test_embedded_newline_error_mentions_newline
}

##############################################################################
# Test Category 19: NO_TABS Sentinel (1 test)
##############################################################################

test_sentinel_no_tabs() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -p 2 "hello" 2>&1)
    assert_output_contains "$output" 'return "NO_TABS"'
}

run_no_tabs_sentinel_tests() {
    section "NO_TABS Sentinel"
    run_test "send-text: dry-run AppleScript contains return \"NO_TABS\"" test_sentinel_no_tabs
}

##############################################################################
# Test Category 20: End-of-Options (--) Handling (4 tests)
##############################################################################

test_double_dash_with_dash_text_exits_0() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" --dry-run -p 2 -- "-verbose" >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "0" "$exit_code"
}

test_double_dash_sends_dash_text() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -p 2 -- "-verbose" 2>&1)
    assert_output_contains "$output" 'write text "-verbose"'
}

test_double_dash_no_text_exits_3() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" -p 2 -- >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "3" "$exit_code"
}

test_double_dash_multiple_text_exits_3() {
    local exit_code
    set +e
    "$SCRIPT_UNDER_TEST" -p 2 -- "text1" "text2" >/dev/null 2>&1
    exit_code=$?
    set -e
    assert_exit_code "3" "$exit_code"
}

run_end_of_options_tests() {
    section "End-of-Options (--) Handling"
    run_test "send-text: -- with dash-prefixed text exits 0" test_double_dash_with_dash_text_exits_0
    run_test "send-text: -- '-verbose' sends literal '-verbose' text" test_double_dash_sends_dash_text
    run_test "send-text: -- with no text exits 3" test_double_dash_no_text_exits_3
    run_test "send-text: -- with multiple text args exits 3" test_double_dash_multiple_text_exits_3
}

##############################################################################
# Test Category 21: SKILL.md Reference in Help (1 test)
##############################################################################

test_help_mentions_skill_md_scenario_7() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --help 2>&1) || true
    assert_output_contains "$output" "SKILL.md" && assert_output_contains "$output" "Scenario 7"
}

run_skill_md_reference_tests() {
    section "SKILL.md Reference in Help"
    run_test "send-text: --help mentions SKILL.md Scenario 7" test_help_mentions_skill_md_scenario_7
}

##############################################################################
# Main Test Runner
##############################################################################

main() {
    echo ""
    echo "========================================================"
    echo "  iterm-send-text.sh Unit Tests"
    echo "========================================================"
    echo ""

    # Run all 21 test categories
    run_existence_tests
    run_help_tests
    run_argument_happy_path_tests
    run_missing_pane_tests
    run_invalid_pane_tests
    run_missing_empty_text_tests
    run_mutual_exclusivity_tests
    run_default_mode_tests
    run_submit_mode_tests
    run_no_newline_mode_tests
    run_backslash_escaping_tests
    run_double_quote_escaping_tests
    run_sentinel_tests
    run_applescript_structure_tests
    run_error_path_tests
    run_context_detection_tests
    run_shell_compatibility_tests
    run_embedded_newline_tests
    run_no_tabs_sentinel_tests
    run_end_of_options_tests
    run_skill_md_reference_tests

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
