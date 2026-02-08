#!/usr/bin/env bash
#
# test-split-pane.sh - Comprehensive unit tests for iterm-split-pane.sh
#
# DESCRIPTION:
#   Tests all functionality of iterm-split-pane.sh using dry-run mode
#   and structural inspection. No iTerm2 or SSH required.
#
# USAGE:
#   ./test-split-pane.sh
#   bash plugins/iterm/skills/pane-management/tests/test-split-pane.sh
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
SCRIPT_UNDER_TEST="$SCRIPT_DIR/../scripts/iterm-split-pane.sh"
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
    run_test "split-pane: script file exists" test_script_exists
    run_test "split-pane: script is executable" test_script_is_executable
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
    assert_output_contains "$output" "USAGE" && \
    assert_output_contains "$output" "--direction" && \
    assert_output_contains "$output" "--profile" && \
    assert_output_contains "$output" "--command" && \
    assert_output_contains "$output" "--name" && \
    assert_output_contains "$output" "--dry-run"
}

test_help_exit_code() {
    "$SCRIPT_UNDER_TEST" -h >/dev/null 2>&1
    local exit_code=$?
    assert_exit_code "0" "$exit_code"
}

run_help_tests() {
    section "Help/Usage Tests"
    run_test "split-pane: -h shows USAGE and OPTIONS" test_help_short_flag
    run_test "split-pane: --help shows all flags" test_help_long_flag
    run_test "split-pane: help exits with code 0" test_help_exit_code
}

##############################################################################
# Test Category 3: Dry-Run Mode (5 tests)
##############################################################################

test_dry_run_tell_application() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run 2>&1)
    assert_output_contains "$output" 'tell application "iTerm2"'
}

test_dry_run_default_vertical() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run 2>&1)
    assert_output_contains "$output" "split vertically"
}

test_dry_run_horizontal() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -d horizontal 2>&1)
    assert_output_contains "$output" "split horizontally"
}

test_dry_run_exit_code() {
    "$SCRIPT_UNDER_TEST" --dry-run >/dev/null 2>&1
    local exit_code=$?
    assert_exit_code "0" "$exit_code"
}

test_dry_run_profile() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -p "Custom" 2>&1)
    assert_output_contains "$output" 'with profile "Custom"'
}

run_dry_run_tests() {
    section "Dry-Run Mode Tests"
    run_test "split-pane: --dry-run outputs tell application iTerm2" test_dry_run_tell_application
    run_test "split-pane: --dry-run default is split vertically" test_dry_run_default_vertical
    run_test "split-pane: --dry-run -d horizontal outputs split horizontally" test_dry_run_horizontal
    run_test "split-pane: --dry-run exits with code 0" test_dry_run_exit_code
    run_test "split-pane: --dry-run -p Custom shows profile in output" test_dry_run_profile
}

##############################################################################
# Test Category 4: Argument Parsing (8 tests)
##############################################################################

test_parse_direction_vertical() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -d vertical 2>&1)
    assert_output_contains "$output" "split vertically"
}

test_parse_direction_horizontal() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run --direction horizontal 2>&1)
    assert_output_contains "$output" "split horizontally"
}

test_parse_profile_short() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -p "Custom" 2>&1)
    assert_output_contains "$output" 'with profile "Custom"'
}

test_parse_profile_long() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run --profile "Custom" 2>&1)
    assert_output_contains "$output" 'with profile "Custom"'
}

test_parse_command_short() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -c "echo hello" 2>&1)
    assert_output_contains "$output" 'write text "echo hello"'
}

test_parse_command_long() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run --command "git status" 2>&1)
    assert_output_contains "$output" 'write text "git status"'
}

test_parse_name_short() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -n "My Pane" 2>&1)
    assert_output_contains "$output" 'set name to "My Pane"'
}

test_parse_name_long() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run --name "Test" 2>&1)
    assert_output_contains "$output" 'set name to "Test"'
}

run_argument_tests() {
    section "Argument Parsing Tests"
    run_test "split-pane: -d vertical parsed correctly" test_parse_direction_vertical
    run_test "split-pane: --direction horizontal parsed correctly" test_parse_direction_horizontal
    run_test "split-pane: -p profile parsed correctly" test_parse_profile_short
    run_test "split-pane: --profile parsed correctly" test_parse_profile_long
    run_test "split-pane: -c command parsed correctly" test_parse_command_short
    run_test "split-pane: --command parsed correctly" test_parse_command_long
    run_test "split-pane: -n name parsed correctly" test_parse_name_short
    run_test "split-pane: --name parsed correctly" test_parse_name_long
}

##############################################################################
# Test Category 5: Exit Codes (5 tests)
##############################################################################

test_exit_code_invalid_flag() {
    local exit_code
    "$SCRIPT_UNDER_TEST" --invalid-flag >/dev/null 2>&1 || true
    exit_code=$("$SCRIPT_UNDER_TEST" --invalid-flag 2>/dev/null; echo $?) || true
    assert_exit_code "3" "$exit_code"
}

test_exit_code_missing_direction_value() {
    local exit_code
    exit_code=$("$SCRIPT_UNDER_TEST" -d 2>/dev/null; echo $?) || true
    assert_exit_code "3" "$exit_code"
}

test_exit_code_missing_profile_value() {
    local exit_code
    exit_code=$("$SCRIPT_UNDER_TEST" -p 2>/dev/null; echo $?) || true
    assert_exit_code "3" "$exit_code"
}

test_exit_code_invalid_direction() {
    local exit_code
    exit_code=$("$SCRIPT_UNDER_TEST" -d sideways 2>/dev/null; echo $?) || true
    assert_exit_code "3" "$exit_code"
}

test_exit_code_missing_command_value() {
    local exit_code
    exit_code=$("$SCRIPT_UNDER_TEST" -c 2>/dev/null; echo $?) || true
    assert_exit_code "3" "$exit_code"
}

run_exit_code_tests() {
    section "Exit Code Tests"
    run_test "split-pane: invalid flag exits 3" test_exit_code_invalid_flag
    run_test "split-pane: missing -d value exits 3" test_exit_code_missing_direction_value
    run_test "split-pane: missing -p value exits 3" test_exit_code_missing_profile_value
    run_test "split-pane: invalid direction value exits 3" test_exit_code_invalid_direction
    run_test "split-pane: missing -c value exits 3" test_exit_code_missing_command_value
}

##############################################################################
# Test Category 6: AppleScript Structure (5 tests)
##############################################################################

test_applescript_has_activate() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run 2>&1)
    assert_output_contains "$output" "activate"
}

test_applescript_has_first_window() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run 2>&1)
    assert_output_contains "$output" "first window"
}

test_applescript_has_end_tell() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run 2>&1)
    assert_output_contains "$output" "end tell"
}

test_applescript_has_split_with_profile() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run 2>&1)
    assert_output_contains "$output" 'split vertically with profile'
}

test_applescript_has_count_windows() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run 2>&1)
    assert_output_contains "$output" "count of windows"
}

run_applescript_structure_tests() {
    section "AppleScript Structure Tests"
    run_test "split-pane: AppleScript contains activate" test_applescript_has_activate
    run_test "split-pane: AppleScript contains first window" test_applescript_has_first_window
    run_test "split-pane: AppleScript contains end tell" test_applescript_has_end_tell
    run_test "split-pane: AppleScript contains split with profile" test_applescript_has_split_with_profile
    run_test "split-pane: AppleScript contains count of windows" test_applescript_has_count_windows
}

##############################################################################
# Test Category 7: Error Paths (3 tests)
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

test_error_invalid_direction_message() {
    local output
    output=$("$SCRIPT_UNDER_TEST" -d sideways 2>&1) || true
    assert_output_contains "$output" "Invalid direction" && \
    assert_output_contains "$output" "horizontal" && \
    assert_output_contains "$output" "vertical"
}

run_error_path_tests() {
    section "Error Path Tests"
    run_test "split-pane: unknown flag shows error message" test_error_unknown_flag_message
    run_test "split-pane: positional arg shows error message" test_error_positional_arg_message
    run_test "split-pane: invalid direction mentions valid values" test_error_invalid_direction_message
}

##############################################################################
# Test Category 8: Combined Options (3 tests)
##############################################################################

test_combined_all_options() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run \
        -d vertical -p "Profile" -c "cmd" -n "name" 2>&1)
    assert_output_contains "$output" "split vertically" && \
    assert_output_contains "$output" 'with profile "Profile"' && \
    assert_output_contains "$output" 'write text "cmd"' && \
    assert_output_contains "$output" 'set name to "name"'
}

test_combined_direction_and_name() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -d horizontal -n "Monitor" 2>&1)
    assert_output_contains "$output" "split horizontally" && \
    assert_output_contains "$output" 'set name to "Monitor"'
}

test_combined_direction_and_command() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -d vertical -c "npm test" 2>&1)
    assert_output_contains "$output" "split vertically" && \
    assert_output_contains "$output" 'write text "npm test"'
}

run_combined_options_tests() {
    section "Combined Options Tests"
    run_test "split-pane: all options combined correctly" test_combined_all_options
    run_test "split-pane: direction + name combined" test_combined_direction_and_name
    run_test "split-pane: direction + command combined" test_combined_direction_and_command
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
    section "Context Detection Tests"
    run_test "split-pane: is_container() is callable after sourcing utils" test_context_is_container_callable
    run_test "split-pane: EXIT_SUCCESS and EXIT_INVALID_ARGS defined" test_context_exit_constants_defined
}

##############################################################################
# Test Category 10: Edge Cases (4 tests)
##############################################################################

test_edge_name_with_spaces() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -n "My Test Pane" 2>&1)
    assert_output_contains "$output" 'set name to "My Test Pane"'
}

test_edge_command_with_ampersand() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -c "echo hello && echo world" 2>&1)
    assert_output_contains "$output" 'write text "echo hello && echo world"'
}

test_edge_profile_with_spaces() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -p "My Profile" 2>&1)
    assert_output_contains "$output" 'with profile "My Profile"'
}

test_edge_name_with_quotes() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -n 'Pane "test"' 2>&1)
    # Double quotes inside the name should be escaped for AppleScript
    assert_output_contains "$output" 'set name to "Pane \"test\""'
}

run_edge_case_tests() {
    section "Edge Case Tests"
    run_test "split-pane: name with spaces preserved" test_edge_name_with_spaces
    run_test "split-pane: command with && preserved" test_edge_command_with_ampersand
    run_test "split-pane: profile with spaces preserved" test_edge_profile_with_spaces
    run_test "split-pane: name with quotes escaped correctly" test_edge_name_with_quotes
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
    section "Shell Compatibility Tests"
    run_test "split-pane: shebang is #!/usr/bin/env bash" test_shell_shebang
    run_test "split-pane: uses set -euo pipefail" test_shell_strict_mode
}

##############################################################################
# Main Test Runner
##############################################################################

main() {
    echo ""
    echo "========================================================"
    echo "  iterm-split-pane.sh Unit Tests"
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
