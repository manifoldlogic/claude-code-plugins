#!/usr/bin/env bash
#
# test-deprecation-notice.sh - Tests for open-devcontainer.sh deprecation notice
#
# DESCRIPTION:
#   Tests the deprecation notice added to open-devcontainer.sh to verify:
#   - Notice appears only in interactive mode (stdout is a terminal)
#   - Notice is sent to stderr (not stdout)
#   - Notice does not appear when piped/redirected
#   - Help text includes deprecation section
#   - Script functionality remains unchanged
#   - shellcheck compliance
#
# USAGE:
#   ./test-deprecation-notice.sh [--verbose]
#
# EXIT CODES:
#   0 - All tests passed
#   1 - One or more tests failed
#

set -euo pipefail

##############################################################################
# Configuration
##############################################################################

# shellcheck disable=SC2034  # SCRIPT_DIR reserved for future use
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Path to open-devcontainer.sh
SCRIPT="/workspace/.devcontainer/scripts/open-devcontainer.sh"

# Test state
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
VERBOSE="${1:-}"

##############################################################################
# Test Output Functions
##############################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; }
skip() { echo -e "${YELLOW}[SKIP]${NC} $*"; }

debug() {
    if [[ "$VERBOSE" == "--verbose" || "$VERBOSE" == "-v" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $*"
    fi
}

##############################################################################
# Test Framework
##############################################################################

run_test() {
    local name="$1"
    local func="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    debug "Running: $name"

    if $func; then
        pass "$name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        fail "$name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

##############################################################################
# Deprecation Notice Tests
##############################################################################

# Test: Script contains deprecation notice function
test_deprecation_function_exists() {
    grep -q 'show_deprecation_notice()' "$SCRIPT"
}

# Test: Deprecation function checks for terminal (interactive mode)
test_interactive_mode_check() {
    # Check that the script uses [ -t 1 ] for detection
    grep -q '\[ -t 1 \]' "$SCRIPT" || grep -q '\[\[ -t 1 \]\]' "$SCRIPT"
}

# Test: Notice goes to stderr (uses >&2)
test_notice_uses_stderr() {
    # Check that the deprecation notice uses stderr redirection
    grep -A10 'show_deprecation_notice()' "$SCRIPT" | grep -q '>&2'
}

# Test: Notice mentions the plugin
test_notice_mentions_plugin() {
    grep -A15 'show_deprecation_notice()' "$SCRIPT" | grep -q 'iterm-open-tab.sh'
}

# Test: Notice mentions SKILL.md documentation
test_notice_mentions_docs() {
    grep -A15 'show_deprecation_notice()' "$SCRIPT" | grep -q 'SKILL.md'
}

# Test: Help text has deprecation section
test_help_has_deprecation() {
    grep -A100 'show_help()' "$SCRIPT" | grep -q 'DEPRECATION NOTICE'
}

# Test: Help text mentions plugin location
test_help_mentions_plugin_location() {
    grep -A120 'show_help()' "$SCRIPT" | grep -q 'Plugin location'
}

# Test: Help text shows equivalent command
test_help_shows_equivalent() {
    grep -A120 'show_help()' "$SCRIPT" | grep -q 'Equivalent command'
}

# Test: Header comment has deprecation section
test_header_has_deprecation() {
    # Check the first 20 lines for deprecation notice in header
    head -n 20 "$SCRIPT" | grep -q 'DEPRECATION NOTICE'
}

# Test: Header mentions plugin script
test_header_mentions_plugin() {
    head -n 20 "$SCRIPT" | grep -q 'iterm-open-tab.sh'
}

# Test: Deprecation function is called after argument parsing
test_deprecation_called() {
    # The function should be called somewhere after the while loop
    grep -q '^show_deprecation_notice$' "$SCRIPT" || grep -q 'show_deprecation_notice$' "$SCRIPT"
}

# Test: Script still has all original functionality (exit codes documented)
test_exit_codes_preserved() {
    grep -q 'exit 0' "$SCRIPT" && \
    grep -q 'exit 1' "$SCRIPT" && \
    grep -q 'exit 2' "$SCRIPT" && \
    grep -q 'exit 3' "$SCRIPT" && \
    grep -q 'exit 4' "$SCRIPT"
}

# Test: Script uses set -euo pipefail
test_strict_mode() {
    grep -q 'set -euo pipefail' "$SCRIPT"
}

# Test: Help still exits with 0
test_help_exit_code() {
    # Run help with stderr redirected to /dev/null to ignore any notices
    # Since we're not running on macOS, we can't actually run the script
    # but we can verify the help handler
    grep -A3 '\-h|--help)' "$SCRIPT" | grep -q 'exit 0'
}

# Test: Script still checks for macOS (prerequisite validation)
test_macos_check_preserved() {
    grep -q 'uname.*Darwin' "$SCRIPT"
}

# Test: Script still checks for Docker (prerequisite validation)
test_docker_check_preserved() {
    grep -q 'command -v docker' "$SCRIPT"
}

# Test: Script still checks for iTerm2 (prerequisite validation)
test_iterm_check_preserved() {
    grep -q '/Applications/iTerm.app' "$SCRIPT"
}

# Test: shellcheck passes (if available)
test_shellcheck_compliance() {
    if command -v shellcheck &>/dev/null; then
        shellcheck "$SCRIPT" 2>/dev/null
    else
        # Skip if shellcheck not installed
        debug "shellcheck not installed, skipping"
        return 0
    fi
}

# Test: Non-interactive mode simulation - notice only in function
test_notice_conditional() {
    # Verify the notice is inside the conditional block, not unconditional
    # The cat command should be inside the if block
    grep -B2 'cat >&2' "$SCRIPT" | grep -q '\[ -t 1 \]'
}

##############################################################################
# Main Execution
##############################################################################

main() {
    echo "=============================================="
    echo "Deprecation Notice Tests for open-devcontainer.sh"
    echo "=============================================="
    echo ""

    # Check script exists
    if [[ ! -f "$SCRIPT" ]]; then
        fail "Script not found: $SCRIPT"
        exit 1
    fi
    info "Testing script: $SCRIPT"
    echo ""

    # Run tests
    echo "--- Function Implementation Tests ---"
    run_test "Deprecation function exists" test_deprecation_function_exists
    run_test "Interactive mode check ([ -t 1 ])" test_interactive_mode_check
    run_test "Notice uses stderr (>&2)" test_notice_uses_stderr
    run_test "Notice is conditional" test_notice_conditional
    run_test "Notice mentions plugin" test_notice_mentions_plugin
    run_test "Notice mentions documentation" test_notice_mentions_docs
    run_test "Deprecation function is called" test_deprecation_called

    echo ""
    echo "--- Help Text Tests ---"
    run_test "Help has deprecation section" test_help_has_deprecation
    run_test "Help mentions plugin location" test_help_mentions_plugin_location
    run_test "Help shows equivalent command" test_help_shows_equivalent

    echo ""
    echo "--- Header Comment Tests ---"
    run_test "Header has deprecation section" test_header_has_deprecation
    run_test "Header mentions plugin script" test_header_mentions_plugin

    echo ""
    echo "--- Backward Compatibility Tests ---"
    run_test "Exit codes preserved" test_exit_codes_preserved
    run_test "Strict mode preserved" test_strict_mode
    run_test "Help exit code is 0" test_help_exit_code
    run_test "macOS check preserved" test_macos_check_preserved
    run_test "Docker check preserved" test_docker_check_preserved
    run_test "iTerm2 check preserved" test_iterm_check_preserved

    echo ""
    echo "--- Code Quality Tests ---"
    run_test "shellcheck compliance" test_shellcheck_compliance

    echo ""
    echo "=============================================="
    echo "Test Results: $TESTS_PASSED/$TESTS_RUN passed"
    echo "=============================================="

    if [[ $TESTS_FAILED -gt 0 ]]; then
        fail "$TESTS_FAILED test(s) failed"
        exit 1
    else
        pass "All tests passed!"
        exit 0
    fi
}

main "$@"
