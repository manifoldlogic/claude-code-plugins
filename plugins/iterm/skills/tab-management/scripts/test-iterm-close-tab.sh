#!/usr/bin/env bash
#
# test-iterm-close-tab.sh - Unit tests for iterm-close-tab.sh
#
# DESCRIPTION:
#   Comprehensive test suite for iterm-close-tab.sh functionality.
#   Tests argument parsing, AppleScript generation, dry-run mode,
#   error paths, and edge cases.
#
# USAGE:
#   ./test-iterm-close-tab.sh [--verbose]
#
# EXIT CODES:
#   0 - All tests passed
#   1 - One or more tests failed
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOSE_TAB_SCRIPT="$SCRIPT_DIR/iterm-close-tab.sh"

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
    [ -f "$CLOSE_TAB_SCRIPT" ] || return 1
    return 0
}

test_script_executable() {
    [ -x "$CLOSE_TAB_SCRIPT" ] || return 1
    return 0
}

##############################################################################
# Test: Help Flag
##############################################################################

test_help_flag_short() {
    local output
    output=$("$CLOSE_TAB_SCRIPT" -h 2>&1) || true

    # Should contain usage information
    [[ "$output" == *"USAGE"* ]] || return 1
    [[ "$output" == *"OPTIONS"* ]] || return 1
    return 0
}

test_help_flag_long() {
    local output
    output=$("$CLOSE_TAB_SCRIPT" --help 2>&1) || true

    # Should contain usage information
    [[ "$output" == *"USAGE"* ]] || return 1
    [[ "$output" == *"--window"* ]] || return 1
    [[ "$output" == *"--force"* ]] || return 1
    [[ "$output" == *"--dry-run"* ]] || return 1
    return 0
}

test_help_shows_exit_codes() {
    local output
    output=$("$CLOSE_TAB_SCRIPT" --help 2>&1) || true

    # Should document exit codes
    [[ "$output" == *"EXIT CODES"* ]] || return 1
    [[ "$output" == *"0"* ]] || return 1
    [[ "$output" == *"1"* ]] || return 1
    [[ "$output" == *"2"* ]] || return 1
    [[ "$output" == *"3"* ]] || return 1
    [[ "$output" == *"4"* ]] || return 1
    return 0
}

test_help_shows_pattern_required() {
    local output
    output=$("$CLOSE_TAB_SCRIPT" --help 2>&1) || true

    # Should show pattern is required
    [[ "$output" == *"pattern"* ]] || return 1
    [[ "$output" == *"ARGUMENTS"* ]] || return 1
    return 0
}

test_help_shows_examples() {
    local output
    output=$("$CLOSE_TAB_SCRIPT" --help 2>&1) || true

    # Should show examples
    [[ "$output" == *"EXAMPLES"* ]] || return 1
    return 0
}

##############################################################################
# Test: Pattern Argument
##############################################################################

test_pattern_is_required() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" 2>/dev/null; echo $?) || true

    # Should exit with EXIT_INVALID_ARGS (3)
    [ "$exit_code" = "3" ] || return 1
    return 0
}

test_pattern_required_error_message() {
    local output
    output=$("$CLOSE_TAB_SCRIPT" 2>&1) || true

    # Should show error about pattern being required
    [[ "$output" == *"Pattern is required"* ]] || return 1
    return 0
}

test_pattern_only_one_allowed() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" pattern1 pattern2 2>/dev/null; echo $?) || true

    # Should exit with EXIT_INVALID_ARGS (3)
    [ "$exit_code" = "3" ] || return 1
    return 0
}

test_pattern_only_one_error_message() {
    local output
    output=$("$CLOSE_TAB_SCRIPT" pattern1 pattern2 2>&1) || true

    # Should show error about only one pattern allowed
    [[ "$output" == *"Only one pattern"* ]] || return 1
    return 0
}

##############################################################################
# Test: Argument Parsing - Window
##############################################################################

test_window_flag_short() {
    local exit_code
    # Use --dry-run to prevent actual execution
    # Note: This will fail with no match but we're testing arg parsing
    exit_code=$("$CLOSE_TAB_SCRIPT" -w 1 "test" 2>/dev/null; echo $?) || true

    # Should accept -w with valid index (may fail later due to no iTerm)
    # Not exit 3 means argument parsing succeeded
    [ "$exit_code" != "3" ] || return 1
    return 0
}

test_window_flag_long() {
    local output
    output=$("$CLOSE_TAB_SCRIPT" --window 2 "test" 2>&1) || true

    # Should accept --window with valid index (argument parsing succeeds)
    # Exit code may be 3 if window doesn't exist at runtime, but error should be
    # "Window N not found" not "Invalid window index" which would mean arg parse failed
    # Check that we don't get an argument parsing error
    [[ "$output" != *"Invalid window index"* ]] || return 1
    [[ "$output" != *"requires a window index"* ]] || return 1
    return 0
}

test_window_missing_value() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" -w 2>/dev/null; echo $?) || true

    # Should exit with EXIT_INVALID_ARGS (3)
    [ "$exit_code" = "3" ] || return 1
    return 0
}

test_window_invalid_zero() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" -w 0 "test" 2>/dev/null; echo $?) || true

    # Should exit with EXIT_INVALID_ARGS (3) - window is 1-based
    [ "$exit_code" = "3" ] || return 1
    return 0
}

test_window_invalid_negative() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" -w -1 "test" 2>/dev/null; echo $?) || true

    # Should exit with EXIT_INVALID_ARGS (3)
    [ "$exit_code" = "3" ] || return 1
    return 0
}

test_window_invalid_string() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" -w abc "test" 2>/dev/null; echo $?) || true

    # Should exit with EXIT_INVALID_ARGS (3)
    [ "$exit_code" = "3" ] || return 1
    return 0
}

test_window_invalid_float() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" -w 1.5 "test" 2>/dev/null; echo $?) || true

    # Should exit with EXIT_INVALID_ARGS (3)
    [ "$exit_code" = "3" ] || return 1
    return 0
}

test_window_invalid_error_message() {
    local output
    output=$("$CLOSE_TAB_SCRIPT" -w abc "test" 2>&1) || true

    # Should mention window index
    [[ "$output" == *"window"* ]] || [[ "$output" == *"index"* ]] || return 1
    return 0
}

##############################################################################
# Test: Force Flag
##############################################################################

test_force_flag() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" --force "test" 2>/dev/null; echo $?) || true

    # Should accept --force (may fail later but arg parsing should succeed)
    [ "$exit_code" != "3" ] || return 1
    return 0
}

test_force_with_pattern() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" --force "worktree:" 2>/dev/null; echo $?) || true

    # Argument parsing should succeed
    [ "$exit_code" != "3" ] || return 1
    return 0
}

##############################################################################
# Test: Dry-Run Mode
##############################################################################

test_dry_run_flag() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" --dry-run "test" 2>/dev/null; echo $?) || true

    # Should accept --dry-run (may fail later but arg parsing should succeed)
    [ "$exit_code" != "3" ] || return 1
    return 0
}

test_dry_run_with_force() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" --dry-run --force "test" 2>/dev/null; echo $?) || true

    # Both flags should be accepted
    [ "$exit_code" != "3" ] || return 1
    return 0
}

test_dry_run_with_window() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" --dry-run -w 1 "test" 2>/dev/null; echo $?) || true

    # Both options should be accepted
    [ "$exit_code" != "3" ] || return 1
    return 0
}

##############################################################################
# Test: Invalid Arguments
##############################################################################

test_invalid_flag_fails() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" --invalid-flag "test" 2>/dev/null; echo $?) || true

    # Should exit with EXIT_INVALID_ARGS (3)
    [ "$exit_code" = "3" ] || return 1
    return 0
}

test_invalid_flag_error_message() {
    local output
    output=$("$CLOSE_TAB_SCRIPT" --invalid-flag "test" 2>&1) || true

    # Should mention unknown option
    [[ "$output" == *"Unknown option"* ]] || return 1
    return 0
}

##############################################################################
# Test: Edge Cases - Patterns with Special Characters
##############################################################################

test_pattern_with_spaces() {
    local exit_code
    # Pattern with spaces should be accepted
    exit_code=$("$CLOSE_TAB_SCRIPT" "worktree: feature branch" 2>/dev/null; echo $?) || true

    # Argument parsing should succeed
    [ "$exit_code" != "3" ] || return 1
    return 0
}

test_pattern_with_colon() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" "worktree:" 2>/dev/null; echo $?) || true

    # Argument parsing should succeed
    [ "$exit_code" != "3" ] || return 1
    return 0
}

test_pattern_with_hyphen() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" "feature-branch" 2>/dev/null; echo $?) || true

    # Argument parsing should succeed
    [ "$exit_code" != "3" ] || return 1
    return 0
}

test_pattern_with_underscore() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" "test_branch" 2>/dev/null; echo $?) || true

    # Argument parsing should succeed
    [ "$exit_code" != "3" ] || return 1
    return 0
}

test_pattern_with_brackets() {
    local exit_code
    # Patterns with regex special chars should be treated as literals
    exit_code=$("$CLOSE_TAB_SCRIPT" "[feature]" 2>/dev/null; echo $?) || true

    # Argument parsing should succeed
    [ "$exit_code" != "3" ] || return 1
    return 0
}

test_pattern_with_asterisk() {
    local exit_code
    # Asterisk should be treated as literal, not regex
    exit_code=$("$CLOSE_TAB_SCRIPT" "test*" 2>/dev/null; echo $?) || true

    # Argument parsing should succeed
    [ "$exit_code" != "3" ] || return 1
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
    exit_code=$("$CLOSE_TAB_SCRIPT" "test" 2>/dev/null; echo $?) || true

    HOST_USER="$saved_host_user"

    # Should exit with EXIT_CONNECTION_FAIL (1)
    [ "$exit_code" = "1" ] || return 1
    return 0
}

##############################################################################
# Test: Shell Compatibility
##############################################################################

test_shebang_uses_env_bash() {
    local first_line
    first_line=$(head -n 1 "$CLOSE_TAB_SCRIPT")

    [[ "$first_line" == "#!/usr/bin/env bash" ]] || return 1
    return 0
}

test_uses_set_euo_pipefail() {
    local content
    content=$(cat "$CLOSE_TAB_SCRIPT")

    [[ "$content" == *"set -euo pipefail"* ]] || return 1
    return 0
}

##############################################################################
# Test: Sources iterm-utils.sh
##############################################################################

test_sources_iterm_utils() {
    local content
    content=$(cat "$CLOSE_TAB_SCRIPT")

    [[ "$content" == *"source"*"iterm-utils.sh"* ]] || return 1
    return 0
}

##############################################################################
# Test: Trap Handler Registration
##############################################################################

test_registers_trap_handler() {
    local content
    content=$(cat "$CLOSE_TAB_SCRIPT")

    # Should register trap for cleanup
    [[ "$content" == *"trap"*"_cleanup_temp_script"* ]] || return 1
    return 0
}

##############################################################################
# Test: AppleScript Structure
##############################################################################

test_has_close_applescript_builder() {
    local content
    content=$(cat "$CLOSE_TAB_SCRIPT")

    # Should have function to build close AppleScript
    [[ "$content" == *"build_close_tabs_applescript"* ]] || return 1
    return 0
}

test_close_applescript_uses_reverse_iteration() {
    local content
    content=$(cat "$CLOSE_TAB_SCRIPT")

    # Should iterate in reverse to prevent index shifting
    [[ "$content" == *"to 1 by -1"* ]] || return 1
    return 0
}

test_close_applescript_checks_running() {
    local content
    content=$(cat "$CLOSE_TAB_SCRIPT")

    # Should check if iTerm is running
    [[ "$content" == *"ITERM_NOT_RUNNING"* ]] || return 1
    return 0
}

test_has_pattern_matching() {
    local content
    content=$(cat "$CLOSE_TAB_SCRIPT")

    # Should use contains for substring matching
    [[ "$content" == *"contains"* ]] || return 1
    return 0
}

test_has_escape_function() {
    local content
    content=$(cat "$CLOSE_TAB_SCRIPT")

    # Should have function to escape AppleScript strings
    [[ "$content" == *"escape_applescript_string"* ]] || return 1
    return 0
}

##############################################################################
# Test: Combined Options
##############################################################################

test_all_options_combined() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" --dry-run --force -w 1 "worktree: test" 2>/dev/null; echo $?) || true

    # Argument parsing should succeed
    [ "$exit_code" != "3" ] || return 1
    return 0
}

test_long_options_combined() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" --dry-run --force --window 2 "test-pattern" 2>/dev/null; echo $?) || true

    # Argument parsing should succeed
    [ "$exit_code" != "3" ] || return 1
    return 0
}

##############################################################################
# Test: Exit Code Consistency
##############################################################################

test_help_exits_zero() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" -h >/dev/null 2>&1; echo $?) || true

    [ "$exit_code" = "0" ] || return 1
    return 0
}

test_invalid_args_exits_three() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" --invalid 2>/dev/null; echo $?) || true

    [ "$exit_code" = "3" ] || return 1
    return 0
}

test_missing_pattern_exits_three() {
    local exit_code
    exit_code=$("$CLOSE_TAB_SCRIPT" 2>/dev/null; echo $?) || true

    [ "$exit_code" = "3" ] || return 1
    return 0
}

##############################################################################
# Test: Dry-Run Output Format
##############################################################################

test_dry_run_output_format_documented() {
    local output
    output=$("$CLOSE_TAB_SCRIPT" --help 2>&1) || true

    # Help should mention dry-run shows what would be closed
    [[ "$output" == *"dry-run"* ]] || return 1
    [[ "$output" == *"Show what would be closed"* ]] || return 1
    return 0
}

##############################################################################
# Test: Confirmation Logic
##############################################################################

test_force_skips_confirmation_documented() {
    local output
    output=$("$CLOSE_TAB_SCRIPT" --help 2>&1) || true

    # Help should mention --force skips confirmation
    [[ "$output" == *"--force"* ]] || return 1
    [[ "$output" == *"Skip confirmation"* ]] || return 1
    return 0
}

##############################################################################
# Test: Has Display Functions
##############################################################################

test_has_display_matching_tabs() {
    local content
    content=$(cat "$CLOSE_TAB_SCRIPT")

    # Should have function to display matching tabs
    [[ "$content" == *"display_matching_tabs"* ]] || return 1
    return 0
}

test_has_find_matching_tabs() {
    local content
    content=$(cat "$CLOSE_TAB_SCRIPT")

    # Should have function to find matching tabs
    [[ "$content" == *"find_matching_tabs"* ]] || return 1
    return 0
}

test_has_prompt_confirmation() {
    local content
    content=$(cat "$CLOSE_TAB_SCRIPT")

    # Should have function for confirmation prompt
    [[ "$content" == *"prompt_confirmation"* ]] || return 1
    return 0
}

##############################################################################
# Main Test Runner
##############################################################################

main() {
    echo ""
    echo "========================================"
    echo "  iTerm Close Tab Script Tests"
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
    run_test "Help shows exit codes" test_help_shows_exit_codes
    run_test "Help shows pattern required" test_help_shows_pattern_required
    run_test "Help shows examples" test_help_shows_examples

    # Pattern Argument Tests
    echo ""
    echo "--- Pattern Argument Tests ---"
    run_test "Pattern is required (missing = exit 3)" test_pattern_is_required
    run_test "Pattern required error message" test_pattern_required_error_message
    run_test "Only one pattern allowed" test_pattern_only_one_allowed
    run_test "Only one pattern error message" test_pattern_only_one_error_message

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
    run_test "Invalid window error message" test_window_invalid_error_message

    # Force Flag Tests
    echo ""
    echo "--- Force Flag Tests ---"
    run_test "Force flag accepted" test_force_flag
    run_test "Force with pattern" test_force_with_pattern

    # Dry-Run Tests
    echo ""
    echo "--- Dry-Run Tests ---"
    run_test "Dry-run flag accepted" test_dry_run_flag
    run_test "Dry-run with force" test_dry_run_with_force
    run_test "Dry-run with window" test_dry_run_with_window

    # Invalid Arguments Tests
    echo ""
    echo "--- Invalid Arguments Tests ---"
    run_test "Invalid flag fails" test_invalid_flag_fails
    run_test "Invalid flag error message" test_invalid_flag_error_message

    # Edge Cases - Patterns with Special Characters
    echo ""
    echo "--- Edge Cases: Patterns with Special Characters ---"
    run_test "Pattern with spaces" test_pattern_with_spaces
    run_test "Pattern with colon" test_pattern_with_colon
    run_test "Pattern with hyphen" test_pattern_with_hyphen
    run_test "Pattern with underscore" test_pattern_with_underscore
    run_test "Pattern with brackets" test_pattern_with_brackets
    run_test "Pattern with asterisk" test_pattern_with_asterisk

    # Error Paths Tests
    echo ""
    echo "--- Error Paths Tests ---"
    run_test "Container mode missing HOST_USER" test_container_mode_missing_host_user

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

    # AppleScript Structure Tests
    echo ""
    echo "--- AppleScript Structure Tests ---"
    run_test "Has close AppleScript builder" test_has_close_applescript_builder
    run_test "Close AppleScript uses reverse iteration" test_close_applescript_uses_reverse_iteration
    run_test "Close AppleScript checks running" test_close_applescript_checks_running
    run_test "Has pattern matching (contains)" test_has_pattern_matching
    run_test "Has escape function" test_has_escape_function

    # Combined Options Tests
    echo ""
    echo "--- Combined Options Tests ---"
    run_test "All options combined" test_all_options_combined
    run_test "Long options combined" test_long_options_combined

    # Exit Code Tests
    echo ""
    echo "--- Exit Code Tests ---"
    run_test "Help exits with 0" test_help_exits_zero
    run_test "Invalid args exits with 3" test_invalid_args_exits_three
    run_test "Missing pattern exits with 3" test_missing_pattern_exits_three

    # Documentation Tests
    echo ""
    echo "--- Documentation Tests ---"
    run_test "Dry-run output format documented" test_dry_run_output_format_documented
    run_test "Force skips confirmation documented" test_force_skips_confirmation_documented

    # Function Tests
    echo ""
    echo "--- Function Tests ---"
    run_test "Has display_matching_tabs function" test_has_display_matching_tabs
    run_test "Has find_matching_tabs function" test_has_find_matching_tabs
    run_test "Has prompt_confirmation function" test_has_prompt_confirmation

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
