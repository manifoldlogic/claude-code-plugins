#!/usr/bin/env bash
#
# test-iterm-list-tabs.sh - Unit tests for iterm-list-tabs.sh
#
# DESCRIPTION:
#   Comprehensive test suite for iterm-list-tabs.sh functionality.
#   Tests argument parsing, AppleScript generation, output formatting,
#   error paths, and edge cases.
#
# USAGE:
#   ./test-iterm-list-tabs.sh [--verbose]
#
# EXIT CODES:
#   0 - All tests passed
#   1 - One or more tests failed
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST_TABS_SCRIPT="$SCRIPT_DIR/iterm-list-tabs.sh"

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Verbose mode
VERBOSE="${1:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

##############################################################################
# Test Utilities
##############################################################################

# Print test result
pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}PASS${NC}: $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}FAIL${NC}: $1"
    if [ -n "${2:-}" ]; then
        echo -e "       ${YELLOW}Reason:${NC} $2"
    fi
}

skip() {
    echo -e "${YELLOW}SKIP${NC}: $1 - $2"
}

info() {
    if [ "$VERBOSE" = "--verbose" ]; then
        echo -e "${BLUE}INFO${NC}: $*"
    fi
}

# Run a test
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

##############################################################################
# Test: Script Existence and Permissions
##############################################################################

test_script_exists() {
    [ -f "$LIST_TABS_SCRIPT" ] || return 1
    return 0
}

test_script_executable() {
    [ -x "$LIST_TABS_SCRIPT" ] || return 1
    return 0
}

##############################################################################
# Test: Help Flag
##############################################################################

test_help_flag_short() {
    local output
    output=$("$LIST_TABS_SCRIPT" -h 2>&1) || true

    # Should contain usage information
    [[ "$output" == *"USAGE"* ]] || return 1
    [[ "$output" == *"OPTIONS"* ]] || return 1
    return 0
}

test_help_flag_long() {
    local output
    output=$("$LIST_TABS_SCRIPT" --help 2>&1) || true

    # Should contain usage information
    [[ "$output" == *"USAGE"* ]] || return 1
    [[ "$output" == *"--format"* ]] || return 1
    [[ "$output" == *"--window"* ]] || return 1
    return 0
}

test_help_shows_formats() {
    local output
    output=$("$LIST_TABS_SCRIPT" --help 2>&1) || true

    # Should document both formats
    [[ "$output" == *"json"* ]] || return 1
    [[ "$output" == *"table"* ]] || return 1
    return 0
}

test_help_shows_exit_codes() {
    local output
    output=$("$LIST_TABS_SCRIPT" --help 2>&1) || true

    # Should document exit codes
    [[ "$output" == *"EXIT CODES"* ]] || return 1
    return 0
}

##############################################################################
# Test: Argument Parsing - Format
##############################################################################

test_format_flag_short() {
    local output
    output=$("$LIST_TABS_SCRIPT" --dry-run -f json 2>&1)

    # Should accept -f json
    [[ "$output" == *"Dry-run mode"* ]] || return 1
    return 0
}

test_format_flag_long() {
    local output
    output=$("$LIST_TABS_SCRIPT" --dry-run --format table 2>&1)

    # Should accept --format table
    [[ "$output" == *"Dry-run mode"* ]] || return 1
    return 0
}

test_format_json_valid() {
    local exit_code
    exit_code=$("$LIST_TABS_SCRIPT" --dry-run -f json >/dev/null 2>&1; echo $?) || true

    # Should exit successfully with valid format
    [ "$exit_code" = "0" ] || return 1
    return 0
}

test_format_table_valid() {
    local exit_code
    exit_code=$("$LIST_TABS_SCRIPT" --dry-run -f table >/dev/null 2>&1; echo $?) || true

    # Should exit successfully with valid format
    [ "$exit_code" = "0" ] || return 1
    return 0
}

test_format_invalid() {
    local exit_code
    exit_code=$("$LIST_TABS_SCRIPT" -f invalid 2>/dev/null; echo $?) || true

    # Should exit with EXIT_INVALID_ARGS (3)
    [ "$exit_code" = "3" ] || return 1
    return 0
}

test_format_missing_value() {
    local exit_code
    exit_code=$("$LIST_TABS_SCRIPT" -f 2>/dev/null; echo $?) || true

    # Should exit with EXIT_INVALID_ARGS (3)
    [ "$exit_code" = "3" ] || return 1
    return 0
}

##############################################################################
# Test: Argument Parsing - Window
##############################################################################

test_window_flag_short() {
    local exit_code
    exit_code=$("$LIST_TABS_SCRIPT" --dry-run -w 1 >/dev/null 2>&1; echo $?) || true

    # Should accept -w with valid index
    [ "$exit_code" = "0" ] || return 1
    return 0
}

test_window_flag_long() {
    local exit_code
    exit_code=$("$LIST_TABS_SCRIPT" --dry-run --window 2 >/dev/null 2>&1; echo $?) || true

    # Should accept --window with valid index
    [ "$exit_code" = "0" ] || return 1
    return 0
}

test_window_missing_value() {
    local exit_code
    exit_code=$("$LIST_TABS_SCRIPT" -w 2>/dev/null; echo $?) || true

    # Should exit with EXIT_INVALID_ARGS (3)
    [ "$exit_code" = "3" ] || return 1
    return 0
}

test_window_invalid_zero() {
    local exit_code
    exit_code=$("$LIST_TABS_SCRIPT" -w 0 2>/dev/null; echo $?) || true

    # Should exit with EXIT_INVALID_ARGS (3) - window is 1-based
    [ "$exit_code" = "3" ] || return 1
    return 0
}

test_window_invalid_negative() {
    local exit_code
    exit_code=$("$LIST_TABS_SCRIPT" -w -1 2>/dev/null; echo $?) || true

    # Should exit with EXIT_INVALID_ARGS (3)
    [ "$exit_code" = "3" ] || return 1
    return 0
}

test_window_invalid_string() {
    local exit_code
    exit_code=$("$LIST_TABS_SCRIPT" -w abc 2>/dev/null; echo $?) || true

    # Should exit with EXIT_INVALID_ARGS (3)
    [ "$exit_code" = "3" ] || return 1
    return 0
}

test_window_invalid_float() {
    local exit_code
    exit_code=$("$LIST_TABS_SCRIPT" -w 1.5 2>/dev/null; echo $?) || true

    # Should exit with EXIT_INVALID_ARGS (3)
    [ "$exit_code" = "3" ] || return 1
    return 0
}

test_window_valid_large() {
    local exit_code
    exit_code=$("$LIST_TABS_SCRIPT" --dry-run -w 100 >/dev/null 2>&1; echo $?) || true

    # Should accept any positive integer (validation happens at runtime)
    [ "$exit_code" = "0" ] || return 1
    return 0
}

##############################################################################
# Test: Dry-Run Mode
##############################################################################

test_dry_run_shows_applescript() {
    local output
    output=$("$LIST_TABS_SCRIPT" --dry-run 2>&1)

    # Should contain AppleScript elements
    [[ "$output" == *"tell application"* ]] || return 1
    [[ "$output" == *"iTerm2"* ]] || return 1
    return 0
}

test_dry_run_does_not_execute() {
    # Dry-run should exit successfully without actually running AppleScript
    local exit_code
    exit_code=$("$LIST_TABS_SCRIPT" --dry-run >/dev/null 2>&1; echo $?) || true

    [ "$exit_code" = "0" ] || return 1
    return 0
}

test_dry_run_shows_window_query() {
    local output
    output=$("$LIST_TABS_SCRIPT" --dry-run 2>&1)

    # Should query windows and tabs
    [[ "$output" == *"windows"* ]] || return 1
    [[ "$output" == *"tabs"* ]] || return 1
    return 0
}

test_dry_run_handles_not_running() {
    local output
    output=$("$LIST_TABS_SCRIPT" --dry-run 2>&1)

    # AppleScript should check if iTerm is running
    [[ "$output" == *"running"* ]] || return 1
    return 0
}

##############################################################################
# Test: Invalid Arguments
##############################################################################

test_invalid_flag_fails() {
    local exit_code
    exit_code=$("$LIST_TABS_SCRIPT" --invalid-flag 2>/dev/null; echo $?) || true

    # Should exit with EXIT_INVALID_ARGS (3)
    [ "$exit_code" = "3" ] || return 1
    return 0
}

test_unexpected_positional_argument() {
    local exit_code
    exit_code=$("$LIST_TABS_SCRIPT" unexpected_arg 2>/dev/null; echo $?) || true

    # Should exit with EXIT_INVALID_ARGS (3)
    [ "$exit_code" = "3" ] || return 1
    return 0
}

##############################################################################
# Test: AppleScript Structure
##############################################################################

test_applescript_has_tell_application() {
    local output
    output=$("$LIST_TABS_SCRIPT" --dry-run 2>&1)

    [[ "$output" == *'tell application "iTerm2"'* ]] || return 1
    return 0
}

test_applescript_checks_running() {
    local output
    output=$("$LIST_TABS_SCRIPT" --dry-run 2>&1)

    # Should check if iTerm is running
    [[ "$output" == *"not running"* ]] || return 1
    return 0
}

test_applescript_counts_windows() {
    local output
    output=$("$LIST_TABS_SCRIPT" --dry-run 2>&1)

    # Should count windows
    [[ "$output" == *"count of windows"* ]] || return 1
    return 0
}

test_applescript_iterates_tabs() {
    local output
    output=$("$LIST_TABS_SCRIPT" --dry-run 2>&1)

    # Should iterate through tabs
    [[ "$output" == *"repeat with"* ]] || return 1
    [[ "$output" == *"tabs"* ]] || return 1
    return 0
}

test_applescript_gets_session_name() {
    local output
    output=$("$LIST_TABS_SCRIPT" --dry-run 2>&1)

    # Should get session name
    [[ "$output" == *"name of current session"* ]] || return 1
    return 0
}

test_applescript_has_end_tell() {
    local output
    output=$("$LIST_TABS_SCRIPT" --dry-run 2>&1)

    [[ "$output" == *"end tell"* ]] || return 1
    return 0
}

test_applescript_returns_special_codes() {
    local output
    output=$("$LIST_TABS_SCRIPT" --dry-run 2>&1)

    # Should return special codes for error conditions
    [[ "$output" == *"ITERM_NOT_RUNNING"* ]] || return 1
    [[ "$output" == *"NO_WINDOWS"* ]] || return 1
    return 0
}

##############################################################################
# Test: Error Paths - Missing HOST_USER (Container Mode)
##############################################################################

test_container_mode_missing_host_user() {
    # shellcheck source=iterm-utils.sh
    source "$SCRIPT_DIR/iterm-utils.sh" 2>/dev/null

    # Skip if not in container
    if ! is_container; then
        info "Not in container, skipping HOST_USER test"
        return 0
    fi

    # Save and unset HOST_USER
    local saved_host_user="${HOST_USER:-}"
    unset HOST_USER

    local exit_code
    exit_code=$("$LIST_TABS_SCRIPT" 2>/dev/null; echo $?) || true

    HOST_USER="$saved_host_user"

    # Should exit with EXIT_CONNECTION_FAIL (1)
    [ "$exit_code" = "1" ] || return 1
    return 0
}

##############################################################################
# Test: Combined Options
##############################################################################

test_format_and_window_combined() {
    local exit_code
    exit_code=$("$LIST_TABS_SCRIPT" --dry-run -f json -w 1 >/dev/null 2>&1; echo $?) || true

    # Should accept both options together
    [ "$exit_code" = "0" ] || return 1
    return 0
}

test_format_window_dry_run_combined() {
    local output
    output=$("$LIST_TABS_SCRIPT" --dry-run --format table --window 2 2>&1)

    # Should show dry-run message
    [[ "$output" == *"Dry-run mode"* ]] || return 1
    return 0
}

##############################################################################
# Test: JSON Output Structure Validation
##############################################################################

test_json_output_mock_no_windows() {
    # Test JSON structure for empty windows case
    # We can't test actual output without iTerm, but we can test the help docs
    local output
    output=$("$LIST_TABS_SCRIPT" --help 2>&1)

    # Help should show JSON example structure
    [[ "$output" == *'"windows"'* ]] || return 1
    [[ "$output" == *'"index"'* ]] || return 1
    [[ "$output" == *'"tabs"'* ]] || return 1
    [[ "$output" == *'"title"'* ]] || return 1
    [[ "$output" == *'"session"'* ]] || return 1
    return 0
}

##############################################################################
# Test: Table Output Structure Validation
##############################################################################

test_table_output_documented() {
    local output
    output=$("$LIST_TABS_SCRIPT" --help 2>&1)

    # Help should show table format columns
    [[ "$output" == *"Window"* ]] || return 1
    [[ "$output" == *"Tab"* ]] || return 1
    [[ "$output" == *"Title"* ]] || return 1
    [[ "$output" == *"Session"* ]] || return 1
    return 0
}

##############################################################################
# Test: Default Format
##############################################################################

test_default_format_is_table() {
    # Without -f option, should use table format
    # We verify this by checking the help shows table as default
    local output
    output=$("$LIST_TABS_SCRIPT" --help 2>&1)

    [[ "$output" == *"default: table"* ]] || return 1
    return 0
}

##############################################################################
# Test: Exit Code Consistency
##############################################################################

test_help_exits_zero() {
    local exit_code
    exit_code=$("$LIST_TABS_SCRIPT" -h >/dev/null 2>&1; echo $?) || true

    [ "$exit_code" = "0" ] || return 1
    return 0
}

test_dry_run_exits_zero() {
    local exit_code
    exit_code=$("$LIST_TABS_SCRIPT" --dry-run >/dev/null 2>&1; echo $?) || true

    [ "$exit_code" = "0" ] || return 1
    return 0
}

##############################################################################
# Test: Error Message Quality
##############################################################################

test_invalid_format_error_message() {
    local output
    output=$("$LIST_TABS_SCRIPT" -f invalid 2>&1) || true

    # Should mention valid options
    [[ "$output" == *"json"* ]] || return 1
    [[ "$output" == *"table"* ]] || return 1
    return 0
}

test_invalid_window_error_message() {
    local output
    output=$("$LIST_TABS_SCRIPT" -w abc 2>&1) || true

    # Should mention window index
    [[ "$output" == *"window"* ]] || [[ "$output" == *"index"* ]] || return 1
    return 0
}

##############################################################################
# Test: Shell Compatibility
##############################################################################

test_shebang_uses_env_bash() {
    local first_line
    first_line=$(head -n 1 "$LIST_TABS_SCRIPT")

    [[ "$first_line" == "#!/usr/bin/env bash" ]] || return 1
    return 0
}

test_uses_set_euo_pipefail() {
    local content
    content=$(cat "$LIST_TABS_SCRIPT")

    [[ "$content" == *"set -euo pipefail"* ]] || return 1
    return 0
}

##############################################################################
# Test: Sources iterm-utils.sh
##############################################################################

test_sources_iterm_utils() {
    local content
    content=$(cat "$LIST_TABS_SCRIPT")

    [[ "$content" == *"source"*"iterm-utils.sh"* ]] || return 1
    return 0
}

##############################################################################
# Test: Trap Handler Registration
##############################################################################

test_registers_trap_handler() {
    local content
    content=$(cat "$LIST_TABS_SCRIPT")

    # Should register trap for cleanup
    [[ "$content" == *"trap"*"_cleanup_temp_script"* ]] || return 1
    return 0
}

##############################################################################
# Main Test Runner
##############################################################################

main() {
    echo ""
    echo "========================================"
    echo "  iTerm List Tabs Script Tests"
    echo "========================================"
    echo ""

    # Script Existence Tests
    echo "--- Script Existence ---"
    run_test "Script exists" test_script_exists
    run_test "Script is executable" test_script_executable

    # Help Flag Tests
    echo ""
    echo "--- Help Flag Tests ---"
    run_test "Short help flag (-h)" test_help_flag_short
    run_test "Long help flag (--help)" test_help_flag_long
    run_test "Help shows formats" test_help_shows_formats
    run_test "Help shows exit codes" test_help_shows_exit_codes

    # Format Argument Tests
    echo ""
    echo "--- Format Argument Tests ---"
    run_test "Short format flag (-f)" test_format_flag_short
    run_test "Long format flag (--format)" test_format_flag_long
    run_test "Format json is valid" test_format_json_valid
    run_test "Format table is valid" test_format_table_valid
    run_test "Invalid format fails" test_format_invalid
    run_test "Missing format value" test_format_missing_value

    # Window Argument Tests
    echo ""
    echo "--- Window Argument Tests ---"
    run_test "Short window flag (-w)" test_window_flag_short
    run_test "Long window flag (--window)" test_window_flag_long
    run_test "Missing window value" test_window_missing_value
    run_test "Window index 0 is invalid" test_window_invalid_zero
    run_test "Negative window index" test_window_invalid_negative
    run_test "String window index" test_window_invalid_string
    run_test "Float window index" test_window_invalid_float
    run_test "Large window index accepted" test_window_valid_large

    # Dry-Run Tests
    echo ""
    echo "--- Dry-Run Tests ---"
    run_test "Dry-run shows AppleScript" test_dry_run_shows_applescript
    run_test "Dry-run does not execute" test_dry_run_does_not_execute
    run_test "Dry-run shows window query" test_dry_run_shows_window_query
    run_test "Dry-run handles not running check" test_dry_run_handles_not_running

    # Invalid Arguments Tests
    echo ""
    echo "--- Invalid Arguments Tests ---"
    run_test "Invalid flag fails" test_invalid_flag_fails
    run_test "Unexpected positional argument" test_unexpected_positional_argument

    # AppleScript Structure Tests
    echo ""
    echo "--- AppleScript Structure Tests ---"
    run_test "AppleScript has tell application" test_applescript_has_tell_application
    run_test "AppleScript checks if running" test_applescript_checks_running
    run_test "AppleScript counts windows" test_applescript_counts_windows
    run_test "AppleScript iterates tabs" test_applescript_iterates_tabs
    run_test "AppleScript gets session name" test_applescript_gets_session_name
    run_test "AppleScript has end tell" test_applescript_has_end_tell
    run_test "AppleScript returns special codes" test_applescript_returns_special_codes

    # Error Paths Tests
    echo ""
    echo "--- Error Paths Tests ---"
    run_test "Container mode missing HOST_USER" test_container_mode_missing_host_user

    # Combined Options Tests
    echo ""
    echo "--- Combined Options Tests ---"
    run_test "Format and window combined" test_format_and_window_combined
    run_test "Format, window, and dry-run" test_format_window_dry_run_combined

    # Output Structure Tests
    echo ""
    echo "--- Output Structure Tests ---"
    run_test "JSON output structure documented" test_json_output_mock_no_windows
    run_test "Table output structure documented" test_table_output_documented
    run_test "Default format is table" test_default_format_is_table

    # Exit Code Tests
    echo ""
    echo "--- Exit Code Tests ---"
    run_test "Help exits with 0" test_help_exits_zero
    run_test "Dry-run exits with 0" test_dry_run_exits_zero

    # Error Message Tests
    echo ""
    echo "--- Error Message Tests ---"
    run_test "Invalid format error message" test_invalid_format_error_message
    run_test "Invalid window error message" test_invalid_window_error_message

    # Shell Compatibility Tests
    echo ""
    echo "--- Shell Compatibility Tests ---"
    run_test "Shebang uses env bash" test_shebang_uses_env_bash
    run_test "Uses set -euo pipefail" test_uses_set_euo_pipefail

    # Sourcing Tests
    echo ""
    echo "--- Sourcing Tests ---"
    run_test "Sources iterm-utils.sh" test_sources_iterm_utils
    run_test "Registers trap handler" test_registers_trap_handler

    # Summary
    echo ""
    echo "========================================"
    echo "  Test Results"
    echo "========================================"
    echo ""
    echo -e "Tests run:    ${BLUE}$TESTS_RUN${NC}"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo ""

    if [ "$TESTS_FAILED" -gt 0 ]; then
        echo -e "${RED}FAILED${NC}: Some tests failed"
        exit 1
    else
        echo -e "${GREEN}SUCCESS${NC}: All tests passed"
        exit 0
    fi
}

main "$@"
