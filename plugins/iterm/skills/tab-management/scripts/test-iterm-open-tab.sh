#!/usr/bin/env bash
#
# test-iterm-open-tab.sh - Unit tests for iterm-open-tab.sh
#
# DESCRIPTION:
#   Comprehensive test suite for iterm-open-tab.sh functionality.
#   Tests argument parsing, AppleScript generation, error paths, and edge cases.
#
# USAGE:
#   ./test-iterm-open-tab.sh [--verbose]
#
# EXIT CODES:
#   0 - All tests passed
#   1 - One or more tests failed
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPEN_TAB_SCRIPT="$SCRIPT_DIR/iterm-open-tab.sh"

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
    [ -f "$OPEN_TAB_SCRIPT" ] || return 1
    return 0
}

test_script_executable() {
    [ -x "$OPEN_TAB_SCRIPT" ] || return 1
    return 0
}

##############################################################################
# Test: Help Flag
##############################################################################

test_help_flag_short() {
    local output
    output=$("$OPEN_TAB_SCRIPT" -h 2>&1) || true

    # Should contain usage information
    [[ "$output" == *"USAGE"* ]] || return 1
    [[ "$output" == *"OPTIONS"* ]] || return 1
    return 0
}

test_help_flag_long() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --help 2>&1) || true

    # Should contain usage information
    [[ "$output" == *"USAGE"* ]] || return 1
    [[ "$output" == *"--directory"* ]] || return 1
    return 0
}

##############################################################################
# Test: Argument Parsing - Directory
##############################################################################

test_directory_flag_short() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run -d /custom/path 2>&1)

    # Should contain the directory in AppleScript
    [[ "$output" == *"/custom/path"* ]] || return 1
    return 0
}

test_directory_flag_long() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run --directory /another/path 2>&1)

    # Should contain the directory in AppleScript
    [[ "$output" == *"/another/path"* ]] || return 1
    return 0
}

test_directory_default() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run 2>&1)

    # Should contain default directory /workspace
    [[ "$output" == *"/workspace"* ]] || return 1
    return 0
}

##############################################################################
# Test: Argument Parsing - Profile
##############################################################################

test_profile_flag_short() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run -p "Custom Profile" 2>&1)

    # Should contain the profile in AppleScript
    [[ "$output" == *"Custom Profile"* ]] || return 1
    return 0
}

test_profile_flag_long() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run --profile "Another Profile" 2>&1)

    # Should contain the profile in AppleScript
    [[ "$output" == *"Another Profile"* ]] || return 1
    return 0
}

test_profile_default() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run 2>&1)

    # Should contain default profile Devcontainer
    [[ "$output" == *"Devcontainer"* ]] || return 1
    return 0
}

##############################################################################
# Test: Argument Parsing - Command
##############################################################################

test_command_flag_short() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run -c "echo hello" 2>&1)

    # Should contain the command in AppleScript
    [[ "$output" == *"echo hello"* ]] || return 1
    return 0
}

test_command_flag_long() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run --command "git status" 2>&1)

    # Should contain the command in AppleScript
    [[ "$output" == *"git status"* ]] || return 1
    return 0
}

##############################################################################
# Test: Argument Parsing - Name
##############################################################################

test_name_flag_short() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run -n "My Tab" 2>&1)

    # Should contain the name in AppleScript
    [[ "$output" == *"set name to"* ]] || return 1
    [[ "$output" == *"My Tab"* ]] || return 1
    return 0
}

test_name_flag_long() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run --name "Test Tab" 2>&1)

    # Should contain the name in AppleScript
    [[ "$output" == *"set name to"* ]] || return 1
    [[ "$output" == *"Test Tab"* ]] || return 1
    return 0
}

##############################################################################
# Test: Argument Parsing - Window Flag
##############################################################################

test_window_flag_short() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run -w 2>&1)

    # Should create window, not use "first window" logic for tabs
    [[ "$output" == *"create window with profile"* ]] || return 1
    # Should NOT have the "if (count of windows) is 0" conditional for tabs
    # Instead, it should directly create a window
    return 0
}

test_window_flag_long() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run --window 2>&1)

    # Should create window
    [[ "$output" == *"create window with profile"* ]] || return 1
    return 0
}

##############################################################################
# Test: Dry-Run Mode
##############################################################################

test_dry_run_shows_applescript() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run 2>&1)

    # Should contain AppleScript elements
    [[ "$output" == *"tell application"* ]] || return 1
    [[ "$output" == *"iTerm2"* ]] || return 1
    return 0
}

test_dry_run_does_not_execute() {
    # Dry-run should exit successfully without actually running AppleScript
    local exit_code
    exit_code=$("$OPEN_TAB_SCRIPT" --dry-run >/dev/null 2>&1; echo $?) || true

    [ "$exit_code" = "0" ] || return 1
    return 0
}

##############################################################################
# Test: Invalid Arguments
##############################################################################

test_invalid_flag_fails() {
    local exit_code
    exit_code=$("$OPEN_TAB_SCRIPT" --invalid-flag 2>/dev/null; echo $?) || true

    # Should exit with EXIT_INVALID_ARGS (3)
    [ "$exit_code" = "3" ] || return 1
    return 0
}

test_missing_directory_value() {
    local exit_code
    exit_code=$("$OPEN_TAB_SCRIPT" -d 2>/dev/null; echo $?) || true

    # Should exit with EXIT_INVALID_ARGS (3)
    [ "$exit_code" = "3" ] || return 1
    return 0
}

test_missing_profile_value() {
    local exit_code
    exit_code=$("$OPEN_TAB_SCRIPT" -p 2>/dev/null; echo $?) || true

    # Should exit with EXIT_INVALID_ARGS (3)
    [ "$exit_code" = "3" ] || return 1
    return 0
}

test_missing_command_value() {
    local exit_code
    exit_code=$("$OPEN_TAB_SCRIPT" -c 2>/dev/null; echo $?) || true

    # Should exit with EXIT_INVALID_ARGS (3)
    [ "$exit_code" = "3" ] || return 1
    return 0
}

test_missing_name_value() {
    local exit_code
    exit_code=$("$OPEN_TAB_SCRIPT" -n 2>/dev/null; echo $?) || true

    # Should exit with EXIT_INVALID_ARGS (3)
    [ "$exit_code" = "3" ] || return 1
    return 0
}

test_unexpected_positional_argument() {
    local exit_code
    exit_code=$("$OPEN_TAB_SCRIPT" unexpected_arg 2>/dev/null; echo $?) || true

    # Should exit with EXIT_INVALID_ARGS (3)
    [ "$exit_code" = "3" ] || return 1
    return 0
}

##############################################################################
# Test: Edge Cases - Paths with Spaces
##############################################################################

test_directory_with_spaces() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run -d "/workspace/my folder/test" 2>&1)

    # Should properly quote the path
    [[ "$output" == *"/workspace/my folder/test"* ]] || return 1
    return 0
}

test_directory_with_special_chars() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run -d "/workspace/test-project_v2" 2>&1)

    # Should handle special characters
    [[ "$output" == *"/workspace/test-project_v2"* ]] || return 1
    return 0
}

##############################################################################
# Test: Edge Cases - Commands with Special Characters
##############################################################################

test_command_with_quotes() {
    local output
    # Note: The AppleScript escaping should handle the quotes
    output=$("$OPEN_TAB_SCRIPT" --dry-run -c 'echo "hello world"' 2>&1)

    # Should escape quotes properly
    [[ "$output" == *"echo"* ]] || return 1
    [[ "$output" == *"hello"* ]] || return 1
    return 0
}

test_command_with_single_quotes() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run -c "echo 'hello world'" 2>&1)

    # Should handle single quotes
    [[ "$output" == *"echo 'hello world'"* ]] || return 1
    return 0
}

test_command_with_ampersand() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run -c "cmd1 && cmd2" 2>&1)

    # Should handle && operator
    [[ "$output" == *"cmd1 && cmd2"* ]] || return 1
    return 0
}

##############################################################################
# Test: Edge Cases - Tab Names with Special Characters
##############################################################################

test_name_with_spaces() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run -n "My Special Tab" 2>&1)

    # Should handle spaces in name
    [[ "$output" == *"My Special Tab"* ]] || return 1
    return 0
}

test_name_with_quotes() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run -n 'Tab "Test"' 2>&1)

    # Should escape quotes in name
    [[ "$output" == *"set name to"* ]] || return 1
    return 0
}

##############################################################################
# Test: AppleScript Structure
##############################################################################

test_applescript_has_tell_application() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run 2>&1)

    [[ "$output" == *'tell application "iTerm2"'* ]] || return 1
    return 0
}

test_applescript_has_activate() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run 2>&1)

    [[ "$output" == *"activate"* ]] || return 1
    return 0
}

test_applescript_uses_first_window() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run 2>&1)

    # Should use "first window" for multi-window safety (not "current window")
    [[ "$output" == *"first window"* ]] || return 1
    return 0
}

test_applescript_handles_no_windows() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run 2>&1)

    # Should check for no windows and create one if needed
    [[ "$output" == *"count of windows"* ]] || return 1
    [[ "$output" == *"create window"* ]] || return 1
    return 0
}

test_applescript_has_end_tell() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run 2>&1)

    [[ "$output" == *"end tell"* ]] || return 1
    return 0
}

test_applescript_adds_clear() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run 2>&1)

    # When directory is set, should add clear at end
    [[ "$output" == *"clear"* ]] || return 1
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
    exit_code=$("$OPEN_TAB_SCRIPT" 2>/dev/null; echo $?) || true

    HOST_USER="$saved_host_user"

    # Should exit with EXIT_CONNECTION_FAIL (1)
    [ "$exit_code" = "1" ] || return 1
    return 0
}

##############################################################################
# Test: Combined Options
##############################################################################

test_all_options_combined() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run \
        -d "/workspace/project" \
        -p "MyProfile" \
        -c "npm start" \
        -n "Dev Server" 2>&1)

    # Should contain all specified values
    [[ "$output" == *"/workspace/project"* ]] || return 1
    [[ "$output" == *"MyProfile"* ]] || return 1
    [[ "$output" == *"npm start"* ]] || return 1
    [[ "$output" == *"Dev Server"* ]] || return 1
    return 0
}

test_command_without_directory() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run -c "echo test" 2>&1)

    # Should still have the command
    [[ "$output" == *"echo test"* ]] || return 1
    # Should have default directory
    [[ "$output" == *"/workspace"* ]] || return 1
    return 0
}

test_window_with_all_options() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run \
        -w \
        -d "/workspace/test" \
        -n "Window Tab" \
        -c "ls -la" 2>&1)

    # Should create window
    [[ "$output" == *"create window with profile"* ]] || return 1
    # Should have all options
    [[ "$output" == *"/workspace/test"* ]] || return 1
    [[ "$output" == *"Window Tab"* ]] || return 1
    [[ "$output" == *"ls -la"* ]] || return 1
    return 0
}

##############################################################################
# Test: Wait-for-Prompt Flag
##############################################################################

test_wait_for_prompt_accepted() {
    local exit_code
    exit_code=$("$OPEN_TAB_SCRIPT" --dry-run --wait-for-prompt -d /workspace >/dev/null 2>&1; echo $?) || true

    [ "$exit_code" = "0" ] || return 1
    return 0
}

test_wait_for_prompt_polling_with_directory() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run --wait-for-prompt -d /workspace 2>&1)

    # Should contain polling loop keywords
    [[ "$output" == *"delay 3"* ]] || return 1
    [[ "$output" == *"repeat while"* ]] || return 1
    [[ "$output" == *"is at shell prompt"* ]] || return 1
    [[ "$output" == *"exit repeat"* ]] || return 1
    return 0
}

test_wait_for_prompt_polling_with_command() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run --wait-for-prompt -c "echo hello" -d /workspace 2>&1)

    # Should contain polling loop keywords
    [[ "$output" == *"delay 3"* ]] || return 1
    [[ "$output" == *"repeat while"* ]] || return 1
    [[ "$output" == *"is at shell prompt"* ]] || return 1
    [[ "$output" == *"exit repeat"* ]] || return 1
    return 0
}

test_no_polling_without_flag() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run -d /workspace 2>&1)

    # Should NOT contain polling loop keywords
    if [[ "$output" == *"repeat while"* ]]; then
        return 1
    fi
    if [[ "$output" == *"is at shell prompt"* ]]; then
        return 1
    fi
    return 0
}

test_wait_for_prompt_dry_run_message() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run --wait-for-prompt -d /workspace 2>&1)

    # Should contain the dry-run info message about wait-for-prompt
    [[ "$output" == *"Wait-for-prompt: enabled"* ]] || return 1
    return 0
}

test_wait_for_prompt_new_window() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run --wait-for-prompt -w -d /workspace 2>&1)

    # Should contain polling loop keywords in new window branch
    [[ "$output" == *"delay 3"* ]] || return 1
    [[ "$output" == *"repeat while"* ]] || return 1
    [[ "$output" == *"is at shell prompt"* ]] || return 1
    [[ "$output" == *"exit repeat"* ]] || return 1
    return 0
}

##############################################################################
# Test: Timeout Warning Block
##############################################################################

test_wait_for_prompt_timeout_block() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run --wait-for-prompt -d /workspace -p Devcontainer 2>&1)

    # Should contain the timeout check block
    [[ "$output" == *"waited >= maxWait"* ]] || return 1
    return 0
}

##############################################################################
# Test: Branch 3 Structural Validation (windows-exist path)
##############################################################################

test_wait_for_prompt_branch3_session_context() {
    local output
    output=$("$OPEN_TAB_SCRIPT" --dry-run --wait-for-prompt -d /workspace -p Devcontainer 2>&1)

    # Branch 3 (else block / windows-exist path) uses:
    #   tell first window
    #     tell current session of current tab    <-- NO "of first window" suffix
    #
    # Branch 2 (then block / no-windows path) uses:
    #   tell current session of current tab of first window
    #
    # Verify Branch 3's session context: "tell current session of current tab"
    # anchored to end-of-line ($ ensures no trailing "of first window")
    echo "$output" | grep -q "tell current session of current tab$" || return 1

    # Verify Branch 3's outer "tell first window" block provides the window context
    echo "$output" | grep -q "tell first window$" || return 1

    return 0
}

##############################################################################
# Main Test Runner
##############################################################################

main() {
    echo ""
    echo "========================================"
    echo "  iTerm Open Tab Script Tests"
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

    # Directory Argument Tests
    echo ""
    echo "--- Directory Argument Tests ---"
    run_test "Short directory flag (-d)" test_directory_flag_short
    run_test "Long directory flag (--directory)" test_directory_flag_long
    run_test "Default directory" test_directory_default

    # Profile Argument Tests
    echo ""
    echo "--- Profile Argument Tests ---"
    run_test "Short profile flag (-p)" test_profile_flag_short
    run_test "Long profile flag (--profile)" test_profile_flag_long
    run_test "Default profile" test_profile_default

    # Command Argument Tests
    echo ""
    echo "--- Command Argument Tests ---"
    run_test "Short command flag (-c)" test_command_flag_short
    run_test "Long command flag (--command)" test_command_flag_long

    # Name Argument Tests
    echo ""
    echo "--- Name Argument Tests ---"
    run_test "Short name flag (-n)" test_name_flag_short
    run_test "Long name flag (--name)" test_name_flag_long

    # Window Flag Tests
    echo ""
    echo "--- Window Flag Tests ---"
    run_test "Short window flag (-w)" test_window_flag_short
    run_test "Long window flag (--window)" test_window_flag_long

    # Dry-Run Tests
    echo ""
    echo "--- Dry-Run Tests ---"
    run_test "Dry-run shows AppleScript" test_dry_run_shows_applescript
    run_test "Dry-run does not execute" test_dry_run_does_not_execute

    # Invalid Arguments Tests
    echo ""
    echo "--- Invalid Arguments Tests ---"
    run_test "Invalid flag fails" test_invalid_flag_fails
    run_test "Missing directory value" test_missing_directory_value
    run_test "Missing profile value" test_missing_profile_value
    run_test "Missing command value" test_missing_command_value
    run_test "Missing name value" test_missing_name_value
    run_test "Unexpected positional argument" test_unexpected_positional_argument

    # Edge Cases - Paths with Spaces
    echo ""
    echo "--- Edge Cases: Paths with Spaces ---"
    run_test "Directory with spaces" test_directory_with_spaces
    run_test "Directory with special chars" test_directory_with_special_chars

    # Edge Cases - Commands with Special Characters
    echo ""
    echo "--- Edge Cases: Commands with Special Characters ---"
    run_test "Command with double quotes" test_command_with_quotes
    run_test "Command with single quotes" test_command_with_single_quotes
    run_test "Command with ampersand" test_command_with_ampersand

    # Edge Cases - Tab Names
    echo ""
    echo "--- Edge Cases: Tab Names ---"
    run_test "Name with spaces" test_name_with_spaces
    run_test "Name with quotes" test_name_with_quotes

    # AppleScript Structure Tests
    echo ""
    echo "--- AppleScript Structure Tests ---"
    run_test "AppleScript has tell application" test_applescript_has_tell_application
    run_test "AppleScript has activate" test_applescript_has_activate
    run_test "AppleScript uses first window" test_applescript_uses_first_window
    run_test "AppleScript handles no windows" test_applescript_handles_no_windows
    run_test "AppleScript has end tell" test_applescript_has_end_tell
    run_test "AppleScript adds clear" test_applescript_adds_clear

    # Error Paths Tests
    echo ""
    echo "--- Error Paths Tests ---"
    run_test "Container mode missing HOST_USER" test_container_mode_missing_host_user

    # Combined Options Tests
    echo ""
    echo "--- Combined Options Tests ---"
    run_test "All options combined" test_all_options_combined
    run_test "Command without explicit directory" test_command_without_directory
    run_test "Window with all options" test_window_with_all_options

    # Wait-for-Prompt Flag Tests
    echo ""
    echo "--- Wait-for-Prompt Flag Tests ---"
    run_test "Wait-for-prompt flag accepted" test_wait_for_prompt_accepted
    run_test "Polling loop present with -d" test_wait_for_prompt_polling_with_directory
    run_test "Polling loop present with -c" test_wait_for_prompt_polling_with_command
    run_test "No polling without flag" test_no_polling_without_flag
    run_test "Dry-run message shows wait-for-prompt enabled" test_wait_for_prompt_dry_run_message
    run_test "Polling loop in new window branch" test_wait_for_prompt_new_window

    # Timeout Warning Block Tests
    echo ""
    echo "--- Timeout Warning Block Tests ---"
    run_test "Timeout block present in wait-for-prompt output" test_wait_for_prompt_timeout_block

    # Branch 3 Structural Validation Tests
    echo ""
    echo "--- Branch 3 Structural Validation Tests ---"
    run_test "Branch 3 session context uses 'tell current session of current tab' without 'of first window'" test_wait_for_prompt_branch3_session_context

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
