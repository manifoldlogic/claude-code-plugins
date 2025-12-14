#!/bin/bash
#
# Integration Tests: state-manager.sh with orchestrator
#
# Tests that state-manager module integrates correctly with orchestrator.sh
# by verifying module loading, checkpoint operations, and state management
# in realistic workflow scenarios.
#
# Usage:
#   ./tests/test_state_manager_integration.sh
#

set -euo pipefail

# Get the directory where this test script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTOMATION_DIR="$(dirname "$SCRIPT_DIR")"

# Source test harness
source "${SCRIPT_DIR}/test-harness.sh"

# ==============================================================================
# Integration Test Setup/Teardown
# ==============================================================================

setup_integration_env() {
    export TEST_DIR=$(mktemp -d)
    export SDD_ROOT="$TEST_DIR"
    export RUN_ID="test-$(date +%s)"
    export RUN_DIR="${TEST_DIR}/runs/${RUN_ID}"
    export CONFIG_LOG_LEVEL="error"  # Suppress info logs during tests

    mkdir -p "${RUN_DIR}/checkpoints"
}

teardown_integration_env() {
    rm -rf "$TEST_DIR"
    unset TEST_DIR SDD_ROOT RUN_ID RUN_DIR CONFIG_LOG_LEVEL
}

# ==============================================================================
# Test 1: Module Loading via Orchestrator Pattern
# ==============================================================================

test_module_loading_sets_state_file() {
    setup_integration_env

    # Source common.sh first (as orchestrator does)
    source "${AUTOMATION_DIR}/lib/common.sh"

    # Source state-manager (simulating load_modules)
    source "${AUTOMATION_DIR}/modules/state-manager.sh"

    # Verify STATE_FILE is set correctly
    [ -n "$STATE_FILE" ]
    assert_equals "0" "$?" "STATE_FILE should be set after module load"

    assert_equals "${RUN_DIR}/state.json" "$STATE_FILE" "STATE_FILE should be RUN_DIR/state.json"

    teardown_integration_env
}

test_module_loading_sets_checkpoint_dir() {
    setup_integration_env

    source "${AUTOMATION_DIR}/lib/common.sh"
    source "${AUTOMATION_DIR}/modules/state-manager.sh"

    # Verify CHECKPOINT_DIR is set correctly
    [ -n "$CHECKPOINT_DIR" ]
    assert_equals "0" "$?" "CHECKPOINT_DIR should be set after module load"

    assert_equals "${RUN_DIR}/checkpoints" "$CHECKPOINT_DIR" "CHECKPOINT_DIR should be RUN_DIR/checkpoints"

    teardown_integration_env
}

# ==============================================================================
# Test 2: Orchestrator Checkpoint Call Patterns
# ==============================================================================

test_orchestrator_checkpoint_after_fetch() {
    setup_integration_env

    source "${AUTOMATION_DIR}/lib/common.sh"
    source "${AUTOMATION_DIR}/modules/state-manager.sh"

    # Initialize state (simulate orchestrator's initialize_run)
    local state="{\"run_id\":\"$RUN_ID\",\"status\":\"running\",\"input_type\":\"jql\",\"input_value\":\"test\",\"started_at\":\"2025-12-14T10:00:00Z\",\"tickets\":[],\"current_ticket\":null}"
    echo "$state" > "${STATE_FILE}"

    # Simulate orchestrator checkpoint call (from orchestrator.sh line 1035)
    save_checkpoint "after_fetch_and_prioritize" >/dev/null

    # Verify checkpoint created
    [ -f "${CHECKPOINT_DIR}/checkpoint_001.json" ]
    assert_equals "0" "$?" "Checkpoint after_fetch_and_prioritize should be created"

    local label
    label=$(jq -r '.label' "${CHECKPOINT_DIR}/checkpoint_001.json")
    assert_equals "after_fetch_and_prioritize" "$label" "Checkpoint label should match orchestrator pattern"

    teardown_integration_env
}

test_orchestrator_checkpoint_after_ticket() {
    setup_integration_env

    source "${AUTOMATION_DIR}/lib/common.sh"
    source "${AUTOMATION_DIR}/modules/state-manager.sh"

    # Initialize state with a ticket
    local state="{\"run_id\":\"$RUN_ID\",\"status\":\"running\",\"input_type\":\"jql\",\"input_value\":\"test\",\"started_at\":\"2025-12-14T10:00:00Z\",\"tickets\":[{\"key\":\"UIT-1001\",\"status\":\"completed\",\"completed_stages\":[\"plan\"],\"error\":null}],\"current_ticket\":null}"
    echo "$state" > "${STATE_FILE}"

    # Simulate orchestrator checkpoint call (from orchestrator.sh line 1076)
    save_checkpoint "after_ticket_UIT-1001" >/dev/null

    # Verify checkpoint created with ticket-specific label
    [ -f "${CHECKPOINT_DIR}/checkpoint_001.json" ]
    assert_equals "0" "$?" "Checkpoint after_ticket should be created"

    local label
    label=$(jq -r '.label' "${CHECKPOINT_DIR}/checkpoint_001.json")
    assert_equals "after_ticket_UIT-1001" "$label" "Checkpoint label should include ticket key"

    teardown_integration_env
}

# ==============================================================================
# Test 3: Workflow State Progression with Checkpoints
# ==============================================================================

test_workflow_state_progression() {
    setup_integration_env

    source "${AUTOMATION_DIR}/lib/common.sh"
    source "${AUTOMATION_DIR}/modules/state-manager.sh"

    # Step 1: Initialize state (like orchestrator's initialize_run)
    local state="{\"run_id\":\"$RUN_ID\",\"status\":\"running\",\"input_type\":\"jql\",\"input_value\":\"test\",\"started_at\":\"2025-12-14T10:00:00Z\",\"tickets\":[{\"key\":\"UIT-1001\",\"status\":\"pending\",\"completed_stages\":[],\"error\":null}],\"current_ticket\":null}"
    echo "$state" > "${STATE_FILE}"

    # Checkpoint before processing
    save_checkpoint "before_ticket_processing" >/dev/null

    # Step 2: Update state (simulate ticket start)
    state=$(jq '.current_ticket = "UIT-1001" | .tickets[0].status = "in_progress"' "${STATE_FILE}")
    save_state "$state" >/dev/null

    # Checkpoint after ticket start
    save_checkpoint "after_ticket_start" >/dev/null

    # Verify checkpoints capture different states
    local cp1_status
    cp1_status=$(jq -r '.state.tickets[0].status' "${CHECKPOINT_DIR}/checkpoint_001.json")
    local cp2_status
    cp2_status=$(jq -r '.state.tickets[0].status' "${CHECKPOINT_DIR}/checkpoint_002.json")

    assert_equals "pending" "$cp1_status" "First checkpoint should have pending ticket"
    assert_equals "in_progress" "$cp2_status" "Second checkpoint should have in_progress ticket"

    teardown_integration_env
}

# ==============================================================================
# Test 4: Checkpoint Configuration
# ==============================================================================

test_checkpoint_max_configuration() {
    setup_integration_env

    source "${AUTOMATION_DIR}/lib/common.sh"
    source "${AUTOMATION_DIR}/modules/state-manager.sh"

    # Set after sourcing (common.sh sets defaults that override exports)
    CONFIG_CHECKPOINT_MAX=3

    # Initialize state
    local state="{\"run_id\":\"$RUN_ID\",\"status\":\"running\",\"input_type\":\"jql\",\"input_value\":\"test\",\"started_at\":\"2025-12-14T10:00:00Z\",\"tickets\":[],\"current_ticket\":null}"
    echo "$state" > "${STATE_FILE}"

    # Create more checkpoints than max
    for i in {1..5}; do
        save_checkpoint "checkpoint_$i" >/dev/null
    done

    # Verify rotation respected CONFIG_CHECKPOINT_MAX
    local checkpoint_count
    checkpoint_count=$(ls -1 "${CHECKPOINT_DIR}"/checkpoint_*.json 2>/dev/null | wc -l)
    assert_equals "3" "$checkpoint_count" "Should have exactly CONFIG_CHECKPOINT_MAX checkpoints"

    # Verify oldest checkpoints deleted (001, 002 should be gone)
    [ ! -f "${CHECKPOINT_DIR}/checkpoint_001.json" ]
    assert_equals "0" "$?" "checkpoint_001 should be rotated out"

    [ ! -f "${CHECKPOINT_DIR}/checkpoint_002.json" ]
    assert_equals "0" "$?" "checkpoint_002 should be rotated out"

    teardown_integration_env
}

# ==============================================================================
# Test 5: Module Interface Validation
# ==============================================================================

test_module_interface_functions_exist() {
    setup_integration_env

    source "${AUTOMATION_DIR}/lib/common.sh"
    source "${AUTOMATION_DIR}/modules/state-manager.sh"

    # Verify all required functions exist (matching validated interface from architecture)
    [ "$(type -t save_state)" = "function" ]
    assert_equals "0" "$?" "save_state function should be defined"

    [ "$(type -t load_state)" = "function" ]
    assert_equals "0" "$?" "load_state function should be defined"

    [ "$(type -t save_checkpoint)" = "function" ]
    assert_equals "0" "$?" "save_checkpoint function should be defined"

    [ "$(type -t restore_checkpoint)" = "function" ]
    assert_equals "0" "$?" "restore_checkpoint function should be defined"

    teardown_integration_env
}

test_module_interface_validate_state_exists() {
    setup_integration_env

    source "${AUTOMATION_DIR}/lib/common.sh"
    source "${AUTOMATION_DIR}/modules/state-manager.sh"

    [ "$(type -t validate_state)" = "function" ]
    assert_equals "0" "$?" "validate_state function should be defined"

    teardown_integration_env
}

# ==============================================================================
# Test 6: Full Workflow Simulation
# ==============================================================================

test_full_workflow_simulation() {
    setup_integration_env

    source "${AUTOMATION_DIR}/lib/common.sh"
    source "${AUTOMATION_DIR}/modules/state-manager.sh"

    # 1. Initialize run (orchestrator pattern)
    local state="{\"run_id\":\"$RUN_ID\",\"status\":\"running\",\"input_type\":\"jql\",\"input_value\":\"project=TEST\",\"started_at\":\"2025-12-14T10:00:00Z\",\"tickets\":[{\"key\":\"TEST-1\",\"status\":\"pending\",\"completed_stages\":[],\"error\":null},{\"key\":\"TEST-2\",\"status\":\"pending\",\"completed_stages\":[],\"error\":null}],\"current_ticket\":null}"
    echo "$state" > "${STATE_FILE}"

    # 2. Checkpoint after fetch (orchestrator line 1035 pattern)
    save_checkpoint "after_fetch_and_prioritize" >/dev/null

    # 3. Process first ticket
    state=$(jq '.current_ticket = "TEST-1" | .tickets[0].status = "in_progress"' "${STATE_FILE}")
    save_state "$state" >/dev/null

    # 4. Complete first ticket
    state=$(jq '.tickets[0].status = "completed" | .tickets[0].completed_stages = ["plan","implement","verify"]' "${STATE_FILE}")
    save_state "$state" >/dev/null
    save_checkpoint "after_ticket_TEST-1" >/dev/null

    # 5. Verify final state
    local completed_count
    completed_count=$(jq '[.tickets[] | select(.status == "completed")] | length' "${STATE_FILE}")
    assert_equals "1" "$completed_count" "Should have 1 completed ticket"

    # 6. Verify checkpoints created
    local checkpoint_count
    checkpoint_count=$(ls -1 "${CHECKPOINT_DIR}"/checkpoint_*.json 2>/dev/null | wc -l)
    assert_equals "2" "$checkpoint_count" "Should have 2 checkpoints (fetch + ticket)"

    teardown_integration_env
}

# ==============================================================================
# Run Integration Tests
# ==============================================================================

run_tests
