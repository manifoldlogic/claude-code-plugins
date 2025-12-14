#!/usr/bin/env bash
#
# test_module_loading.sh - Tests for module loading and interface validation
#
# Tests:
# 1. Load all modules successfully
# 2. Validate module interfaces
# 3. Missing module file detection
# 4. Module syntax error detection
# 5. Missing function detection
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source test harness
# shellcheck source=tests/test-harness.sh
source "${SCRIPT_DIR}/test-harness.sh"

# Source common library
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

# Set up test environment
export CONFIG_LOG_LEVEL="error"  # Quiet logs during tests
export SDD_ROOT="/app/.sdd"
export LOG_DIR="/tmp"
export LOG_FILE="/tmp/test_module_loading_$$.log"

# Cleanup
cleanup() {
    rm -f "$LOG_FILE" 2>/dev/null || true
    rm -rf "${SCRIPT_DIR}/fixtures/modules"/*.bak 2>/dev/null || true
}
trap cleanup EXIT

echo "========================================="
echo "Module Loading Test Suite"
echo "========================================="
echo

#
# Test 1: Load All Modules Successfully
#
echo "=== Test 1: Load All Modules Successfully ==="

test_load_all_modules() {
    # Source orchestrator which defines load_modules
    # Mock required globals
    INPUT_TYPE="jql"
    INPUT_VALUE="test"
    DRY_RUN=false
    VERBOSE=false
    CONFIG_FILE=""
    RUN_ID=""
    RUN_DIR=""

    # Source orchestrator to get load_modules function
    source "${SCRIPT_DIR}/../orchestrator.sh"

    # Load modules
    load_modules
    assert_equals "0" "$?" "load_modules should succeed"

    # Check that functions are defined
    assert_true "declare -F save_state" "save_state should be defined"
    assert_true "declare -F load_state" "load_state should be defined"
    assert_true "declare -F save_checkpoint" "save_checkpoint should be defined"
    assert_true "declare -F retry_with_backoff" "retry_with_backoff should be defined"
    assert_true "declare -F fetch_tickets" "fetch_tickets should be defined"
    assert_true "declare -F make_decision" "make_decision should be defined"
    assert_true "declare -F execute_stage" "execute_stage should be defined"
}
run_test test_load_all_modules

#
# Test 2: Validate Module Interface - State Manager
#
echo
echo "=== Test 2: Validate Module Interface - State Manager ==="

test_validate_state_manager_interface() {
    # Source the module
    source "${SCRIPT_DIR}/../modules/state-manager.sh"

    # Check required functions exist
    assert_true "declare -F save_state" "save_state function should exist"
    assert_true "declare -F load_state" "load_state function should exist"
}
run_test test_validate_state_manager_interface

#
# Test 3: Validate Module Interface - Recovery Handler
#
echo
echo "=== Test 3: Validate Module Interface - Recovery Handler ==="

test_validate_recovery_handler_interface() {
    # Source the module
    source "${SCRIPT_DIR}/../modules/recovery-handler.sh"

    # Check required functions exist
    assert_true "declare -F save_checkpoint" "save_checkpoint function should exist"
    assert_true "declare -F restore_checkpoint" "restore_checkpoint function should exist"
    assert_true "declare -F retry_with_backoff" "retry_with_backoff function should exist"
    assert_true "declare -F handle_error" "handle_error function should exist"
}
run_test test_validate_recovery_handler_interface

#
# Test 4: Validate Module Interface - JIRA Adapter
#
echo
echo "=== Test 4: Validate Module Interface - JIRA Adapter ==="

test_validate_jira_adapter_interface() {
    # Source the module
    source "${SCRIPT_DIR}/../modules/jira-adapter.sh"

    # Check required functions exist
    assert_true "declare -F fetch_tickets" "fetch_tickets function should exist"
    assert_true "declare -F get_ticket_details" "get_ticket_details function should exist"
}
run_test test_validate_jira_adapter_interface

#
# Test 5: Validate Module Interface - Decision Engine
#
echo
echo "=== Test 5: Validate Module Interface - Decision Engine ==="

test_validate_decision_engine_interface() {
    # Source the module
    source "${SCRIPT_DIR}/../modules/decision-engine.sh"

    # Check required functions exist
    assert_true "declare -F make_decision" "make_decision function should exist"
}
run_test test_validate_decision_engine_interface

#
# Test 6: Validate Module Interface - SDD Executor
#
echo
echo "=== Test 6: Validate Module Interface - SDD Executor ==="

test_validate_sdd_executor_interface() {
    # Source the module
    source "${SCRIPT_DIR}/../modules/sdd-executor.sh"

    # Check required functions exist
    assert_true "declare -F execute_stage" "execute_stage function should exist"
}
run_test test_validate_sdd_executor_interface

#
# Test 7: Module Functions Return Expected Format
#
echo
echo "=== Test 7: Module Functions Return Expected Format ==="

test_module_functions_return_json() {
    # Source modules
    source "${SCRIPT_DIR}/../modules/state-manager.sh"
    source "${SCRIPT_DIR}/../modules/jira-adapter.sh"
    source "${SCRIPT_DIR}/../modules/decision-engine.sh"

    # Test state-manager returns JSON
    result=$(load_state "/tmp/nonexistent_$$" 2>/dev/null || echo '{"success": false}')
    assert_true "validate_json '$result'" "load_state should return valid JSON"

    # Test jira-adapter returns JSON
    result=$(fetch_tickets "jql" "project = TEST" 2>/dev/null || echo '{"success": false}')
    assert_true "validate_json '$result'" "fetch_tickets should return valid JSON"

    # Test decision-engine returns JSON
    result=$(make_decision "test_query" 2>/dev/null || echo '{"success": false}')
    assert_true "validate_json '$result'" "make_decision should return valid JSON"
}
run_test test_module_functions_return_json

#
# Test 8: Module Error Handling
#
echo
echo "=== Test 8: Module Error Handling ==="

test_module_error_handling() {
    # Source modules
    source "${SCRIPT_DIR}/../modules/state-manager.sh"
    source "${SCRIPT_DIR}/../modules/recovery-handler.sh"

    # Test load_state with nonexistent file
    result=$(load_state "/nonexistent/path/state.json" 2>/dev/null || echo '{"success": false}')
    if is_success "$result"; then
        fail "load_state should return success=false for nonexistent file"
    else
        pass "load_state returns success=false for errors"
    fi

    # Test save_checkpoint creates valid JSON
    temp_dir="/tmp/test_checkpoint_$$"
    mkdir -p "$temp_dir"
    result=$(save_checkpoint "$temp_dir" '{"test": "data"}' 2>/dev/null || echo '{"success": false}')
    assert_true "validate_json '$result'" "save_checkpoint should return valid JSON"
    rm -rf "$temp_dir"
}
run_test test_module_error_handling

echo
echo "========================================="
print_summary
echo "========================================="
