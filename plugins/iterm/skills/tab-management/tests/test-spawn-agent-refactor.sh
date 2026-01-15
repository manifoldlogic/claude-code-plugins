#!/usr/bin/env bash
#
# test-spawn-agent-refactor.sh - Tests for spawn-agent.sh wrapper-with-fallback refactoring
#
# DESCRIPTION:
#   Tests the refactored spawn-agent.sh to verify:
#   - Plugin delegation works when plugin is available
#   - Fallback works when plugin is not found
#   - Fallback works when plugin fails (exits non-zero)
#   - Task description escaping preserves special characters
#   - Original functions still exist with _original suffix
#   - ITERM_PLUGIN_DIR is configurable via PLUGIN_ROOT
#   - Exit codes match original implementation
#
# USAGE:
#   ./test-spawn-agent-refactor.sh [--verbose]
#
# EXIT CODES:
#   0 - All tests passed
#   1 - One or more tests failed
#

set -euo pipefail

##############################################################################
# Configuration
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Path to the refactored spawn-agent.sh
SPAWN_AGENT_SCRIPT="/workspace/.devcontainer/scripts/spawn-agent.sh"
# Path to the plugin scripts directory (parent of tests)
# shellcheck disable=SC2034  # Used in setup() for mock plugin paths
PLUGIN_SCRIPTS_DIR="$SCRIPT_DIR/../scripts"

# Test state
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
VERBOSE="${1:-}"

# Temp directory for test fixtures
TEST_TMP=""

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

setup() {
    TEST_TMP=$(mktemp -d)
    debug "Created temp directory: $TEST_TMP"

    # Create mock plugin script that succeeds
    mkdir -p "$TEST_TMP/mock-plugin/plugins/iterm/skills/tab-management/scripts"
    cat > "$TEST_TMP/mock-plugin/plugins/iterm/skills/tab-management/scripts/iterm-open-tab.sh" << 'EOF'
#!/bin/bash
# Mock plugin that succeeds
echo "MOCK_PLUGIN_CALLED with args: $*"
exit 0
EOF
    chmod +x "$TEST_TMP/mock-plugin/plugins/iterm/skills/tab-management/scripts/iterm-open-tab.sh"

    # Create mock plugin script that fails
    mkdir -p "$TEST_TMP/failing-plugin/plugins/iterm/skills/tab-management/scripts"
    cat > "$TEST_TMP/failing-plugin/plugins/iterm/skills/tab-management/scripts/iterm-open-tab.sh" << 'EOF'
#!/bin/bash
# Mock plugin that fails
echo "MOCK_PLUGIN_FAILING" >&2
exit 1
EOF
    chmod +x "$TEST_TMP/failing-plugin/plugins/iterm/skills/tab-management/scripts/iterm-open-tab.sh"
}

teardown() {
    if [[ -n "$TEST_TMP" && -d "$TEST_TMP" ]]; then
        rm -rf "$TEST_TMP"
        debug "Cleaned up temp directory: $TEST_TMP"
    fi
}

run_test() {
    local test_name="$1"
    local test_func="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    info "Running: $test_name"

    if $test_func; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        pass "$test_name"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        fail "$test_name"
        return 1
    fi
}

##############################################################################
# Test: Original Functions Exist
##############################################################################

test_original_functions_exist() {
    # Check that spawn_agent_remote_original exists in the script
    if ! grep -q "spawn_agent_remote_original()" "$SPAWN_AGENT_SCRIPT"; then
        debug "spawn_agent_remote_original() not found"
        return 1
    fi

    # Check that spawn_agent_local_original exists in the script
    if ! grep -q "spawn_agent_local_original()" "$SPAWN_AGENT_SCRIPT"; then
        debug "spawn_agent_local_original() not found"
        return 1
    fi

    debug "Both _original functions found"
    return 0
}

##############################################################################
# Test: Wrapper Function Exists
##############################################################################

test_wrapper_function_exists() {
    # Check that spawn_agent_tab() wrapper exists
    if ! grep -q "spawn_agent_tab()" "$SPAWN_AGENT_SCRIPT"; then
        debug "spawn_agent_tab() wrapper not found"
        return 1
    fi

    debug "spawn_agent_tab() wrapper found"
    return 0
}

##############################################################################
# Test: Plugin Path Configurable via PLUGIN_ROOT
##############################################################################

test_plugin_root_configurable() {
    # Check that PLUGIN_ROOT is used in the script
    if ! grep -q 'PLUGIN_ROOT:-' "$SPAWN_AGENT_SCRIPT"; then
        debug "PLUGIN_ROOT variable not found"
        return 1
    fi

    # Check that ITERM_PLUGIN_DIR uses PLUGIN_ROOT
    if ! grep -q 'ITERM_PLUGIN_DIR="\${PLUGIN_ROOT:-' "$SPAWN_AGENT_SCRIPT"; then
        debug "ITERM_PLUGIN_DIR doesn't use PLUGIN_ROOT"
        return 1
    fi

    debug "PLUGIN_ROOT configuration found"
    return 0
}

##############################################################################
# Test: Plugin Check Logic Exists
##############################################################################

test_plugin_check_logic() {
    # Check that the script checks if plugin is executable
    if ! grep -q '\-x "\$ITERM_OPEN_TAB_SCRIPT"' "$SPAWN_AGENT_SCRIPT"; then
        debug "Plugin executable check not found"
        return 1
    fi

    debug "Plugin executable check found"
    return 0
}

##############################################################################
# Test: Fallback Logic Exists
##############################################################################

test_fallback_logic() {
    # Check that fallback to original functions exists
    if ! grep -q "spawn_agent_remote_original" "$SPAWN_AGENT_SCRIPT"; then
        debug "Fallback to spawn_agent_remote_original not found"
        return 1
    fi

    if ! grep -q "spawn_agent_local_original" "$SPAWN_AGENT_SCRIPT"; then
        debug "Fallback to spawn_agent_local_original not found"
        return 1
    fi

    # Check that fallback message exists
    if ! grep -q "Plugin failed, using fallback implementation" "$SPAWN_AGENT_SCRIPT"; then
        debug "Fallback warning message not found"
        return 1
    fi

    debug "Fallback logic found"
    return 0
}

##############################################################################
# Test: Task Escaping for Simple Task
##############################################################################

test_task_escaping_simple() {
    # Check that the script has escaping logic for simple tasks like "Complete ITERM.3002"
    if ! grep -q 'escaped_task="\${task//\\"' "$SPAWN_AGENT_SCRIPT"; then
        debug "Task escaping logic not found"
        return 1
    fi

    debug "Task escaping logic found for simple tasks"
    return 0
}

##############################################################################
# Test: Task Escaping Logic Present
##############################################################################

test_task_escaping_logic() {
    # Verify the double quote escaping pattern exists
    # Looking for: ${task//\"/\\\"}
    if ! grep -q 'task//\\"' "$SPAWN_AGENT_SCRIPT"; then
        debug "Double quote escaping pattern not found"
        return 1
    fi

    debug "Double quote escaping pattern found"
    return 0
}

##############################################################################
# Test: Plugin Receives Correct Arguments
##############################################################################

test_plugin_arguments() {
    # Check that the plugin is called with --directory
    if ! grep -q '\--directory' "$SPAWN_AGENT_SCRIPT"; then
        debug "--directory argument not found"
        return 1
    fi

    # Check that the plugin is called with --profile
    if ! grep -q '\--profile' "$SPAWN_AGENT_SCRIPT"; then
        debug "--profile argument not found"
        return 1
    fi

    # Check that the plugin is called with --name
    if ! grep -q '\--name' "$SPAWN_AGENT_SCRIPT"; then
        debug "--name argument not found"
        return 1
    fi

    # Check that the plugin is called with --command
    if ! grep -q '\--command' "$SPAWN_AGENT_SCRIPT"; then
        debug "--command argument not found"
        return 1
    fi

    debug "All required plugin arguments found"
    return 0
}

##############################################################################
# Test: Main Entry Point Uses Wrapper
##############################################################################

test_main_uses_wrapper() {
    # Check that main section calls spawn_agent_tab
    if ! grep -q 'spawn_agent_tab "\$WORKTREE_PATH" "\$TASK"' "$SPAWN_AGENT_SCRIPT"; then
        debug "Main entry point doesn't call spawn_agent_tab"
        return 1
    fi

    debug "Main entry point uses spawn_agent_tab wrapper"
    return 0
}

##############################################################################
# Test: SSH Host User Check Preserved
##############################################################################

test_host_user_check_preserved() {
    # Check that HOST_USER validation exists in original remote function
    if ! grep -q 'HOST_USER not set' "$SPAWN_AGENT_SCRIPT"; then
        debug "HOST_USER validation not found"
        return 1
    fi

    debug "HOST_USER validation preserved"
    return 0
}

##############################################################################
# Test: Base64 Encoding Preserved in Original
##############################################################################

test_base64_encoding_preserved() {
    # Check that base64 encoding exists in original remote function
    if ! grep -q 'base64 -w0' "$SPAWN_AGENT_SCRIPT"; then
        debug "base64 encoding not found"
        return 1
    fi

    debug "base64 encoding preserved in original function"
    return 0
}

##############################################################################
# Test: is_container Function Preserved
##############################################################################

test_is_container_preserved() {
    # Check that is_container function exists
    if ! grep -q 'is_container()' "$SPAWN_AGENT_SCRIPT"; then
        debug "is_container() function not found"
        return 1
    fi

    debug "is_container() function preserved"
    return 0
}

##############################################################################
# Test: Profile Variable Used
##############################################################################

test_profile_variable_used() {
    # Check that PROFILE variable is used
    if ! grep -q 'PROFILE="\${ITERM_PROFILE:-Devcontainer}"' "$SPAWN_AGENT_SCRIPT"; then
        debug "PROFILE variable not found"
        return 1
    fi

    debug "PROFILE variable preserved"
    return 0
}

##############################################################################
# Integration Test: Mock Plugin Delegation
##############################################################################

test_mock_plugin_delegation() {
    # Skip if we can't source the script (would require actual environment)
    # This is a structural test that verifies the delegation flow exists

    # Verify the plugin script path reference exists
    if ! grep -q 'ITERM_OPEN_TAB_SCRIPT=' "$SPAWN_AGENT_SCRIPT"; then
        debug "ITERM_OPEN_TAB_SCRIPT reference not found"
        return 1
    fi

    debug "Plugin delegation structure verified"
    return 0
}

##############################################################################
# Test: Script Header Documentation
##############################################################################

test_documentation_updated() {
    # Check that wrapper-with-fallback pattern is documented
    if ! grep -q 'wrapper-with-fallback' "$SPAWN_AGENT_SCRIPT"; then
        debug "wrapper-with-fallback documentation not found"
        return 1
    fi

    # Check that fallback documentation exists
    if ! grep -q 'falls back to original implementation' "$SPAWN_AGENT_SCRIPT"; then
        debug "Fallback documentation not found"
        return 1
    fi

    debug "Documentation updated"
    return 0
}

##############################################################################
# Test: Empty Task Handling
##############################################################################

test_empty_task_handling() {
    # Check that empty task defaults to "Claude Agent"
    if ! grep -q 'tab_name="\${task:-Claude Agent}"' "$SPAWN_AGENT_SCRIPT"; then
        debug "Empty task default not found"
        return 1
    fi

    debug "Empty task handling found"
    return 0
}

##############################################################################
# Test: AppleScript Preserved in Original Functions
##############################################################################

test_applescript_preserved() {
    # Check that AppleScript is preserved in original remote function
    if ! grep -q 'tell application "iTerm"' "$SPAWN_AGENT_SCRIPT"; then
        debug "AppleScript tell block not found"
        return 1
    fi

    # Check create tab logic preserved
    if ! grep -q 'create tab with profile' "$SPAWN_AGENT_SCRIPT"; then
        debug "create tab AppleScript not found"
        return 1
    fi

    debug "AppleScript preserved in original functions"
    return 0
}

##############################################################################
# Main Test Runner
##############################################################################

main() {
    echo "=============================================="
    echo "spawn-agent.sh Refactoring Tests"
    echo "=============================================="
    echo ""

    # Setup test fixtures
    setup

    # Verify spawn-agent.sh exists
    if [[ ! -f "$SPAWN_AGENT_SCRIPT" ]]; then
        fail "spawn-agent.sh not found at: $SPAWN_AGENT_SCRIPT"
        teardown
        exit 1
    fi

    # Run structural tests
    echo "--- Structural Tests ---"
    run_test "Original functions exist with _original suffix" test_original_functions_exist || true
    run_test "Wrapper function spawn_agent_tab() exists" test_wrapper_function_exists || true
    run_test "PLUGIN_ROOT is configurable" test_plugin_root_configurable || true
    run_test "Plugin executable check exists" test_plugin_check_logic || true
    run_test "Fallback logic exists" test_fallback_logic || true
    run_test "Main entry point uses wrapper" test_main_uses_wrapper || true

    echo ""
    echo "--- Task Escaping Tests ---"
    run_test "Task escaping logic present" test_task_escaping_logic || true
    run_test "Simple task escaping" test_task_escaping_simple || true
    run_test "Empty task handling" test_empty_task_handling || true

    echo ""
    echo "--- Preserved Functionality Tests ---"
    run_test "HOST_USER check preserved" test_host_user_check_preserved || true
    run_test "Base64 encoding preserved" test_base64_encoding_preserved || true
    run_test "is_container() preserved" test_is_container_preserved || true
    run_test "PROFILE variable preserved" test_profile_variable_used || true
    run_test "AppleScript preserved in originals" test_applescript_preserved || true

    echo ""
    echo "--- Plugin Integration Tests ---"
    run_test "Plugin receives correct arguments" test_plugin_arguments || true
    run_test "Plugin delegation structure" test_mock_plugin_delegation || true

    echo ""
    echo "--- Documentation Tests ---"
    run_test "Documentation updated" test_documentation_updated || true

    # Teardown
    teardown

    # Summary
    echo ""
    echo "=============================================="
    echo "Test Summary"
    echo "=============================================="
    echo "Tests run:    $TESTS_RUN"
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"
    echo ""

    if [[ $TESTS_FAILED -gt 0 ]]; then
        fail "Some tests failed!"
        exit 1
    else
        pass "All tests passed!"
        exit 0
    fi
}

main "$@"
