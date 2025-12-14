#!/usr/bin/env bash
#
# Test suite for state-manager.sh using test-harness.sh framework
# Tests foundation functions: save_state(), load_state(), validate_state()
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-harness.sh"

# Module under test
MODULE_DIR="${SCRIPT_DIR}/../modules"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Source modules globally once (before test functions run)
# This avoids re-sourcing in each subshell which causes scoping issues
export GLOBAL_LOG_FILE="/tmp/test-state-manager-$$.log"
export CONFIG_LOG_LEVEL=info
set +u  # Temporarily disable to avoid array access issues
source "${LIB_DIR}/common.sh"
set -u

#
# Test Setup/Teardown Helpers
#

# Create isolated test environment with temp directory and RUN_DIR
# Note: Modules are sourced globally, this just sets up the test directory
setup_test_env() {
    export TEST_DIR=$(mktemp -d)
    export RUN_DIR="$TEST_DIR"
    export LOG_FILE="$TEST_DIR/test.log"
    mkdir -p "${TEST_DIR}/checkpoints"

    # Re-source state-manager with new RUN_DIR
    set +u
    source "${MODULE_DIR}/state-manager.sh"
    set -u
}

# Clean up test environment
teardown_test_env() {
    rm -rf "$TEST_DIR"
    unset RUN_DIR TEST_DIR LOG_FILE
}

#
# Module Initialization Tests
#

test_module_rejects_missing_run_dir() {
    # Module should fail to load if RUN_DIR is not set
    local output
    output=$(bash -c 'unset RUN_DIR; source "'"${MODULE_DIR}/state-manager.sh"'"' 2>&1 || true)

    assert_contains "$output" "RUN_DIR not set" "Module should reject missing RUN_DIR with clear error"
}

test_module_sets_global_variables() {
    setup_test_env

    assert_equals "${TEST_DIR}/state.json" "$STATE_FILE" "STATE_FILE should be set to RUN_DIR/state.json"
    assert_equals "${TEST_DIR}/checkpoints" "$CHECKPOINT_DIR" "CHECKPOINT_DIR should be set to RUN_DIR/checkpoints"

    teardown_test_env
}

#
# save_state() Tests
#

test_save_state_rejects_empty_input() {
    setup_test_env

    local result
    result=$(save_state "" 2>&1 || true)

    assert_contains "$result" '"success": false' "save_state should reject empty input"
    assert_contains "$result" "No state JSON provided" "Error message should indicate empty input"

    teardown_test_env
}

test_save_state_rejects_invalid_json() {
    setup_test_env

    local result
    result=$(save_state "{broken json" 2>&1 || true)

    assert_contains "$result" '"success": false' "save_state should reject invalid JSON"
    assert_contains "$result" "Invalid JSON syntax" "Error message should indicate JSON syntax error"

    teardown_test_env
}

test_save_state_accepts_valid_json() {
    setup_test_env

    local test_state='{"run_id":"test-123","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[],"current_ticket":null}'
    local result
    result=$(save_state "$test_state" 2>&1 || true)

    assert_contains "$result" '"success": true' "save_state should succeed with valid JSON"
    assert_file_exists "${TEST_DIR}/state.json" "State file should be created"

    teardown_test_env
}

test_save_state_creates_file_with_correct_permissions() {
    setup_test_env

    local test_state='{"run_id":"test-123","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[],"current_ticket":null}'
    save_state "$test_state" &>/dev/null || true

    local perms
    perms=$(stat -c "%a" "${TEST_DIR}/state.json" 2>/dev/null || stat -f "%A" "${TEST_DIR}/state.json" 2>/dev/null)
    assert_equals "600" "$perms" "State file should have 600 permissions"

    teardown_test_env
}

test_save_state_writes_valid_json_content() {
    setup_test_env

    local test_state='{"run_id":"test-456","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[],"current_ticket":null}'
    save_state "$test_state" &>/dev/null || true

    # Verify file contains valid JSON
    assert_true "jq empty '${TEST_DIR}/state.json' 2>/dev/null" "Saved content should be valid JSON"

    # Verify content matches input
    local saved_run_id
    saved_run_id=$(jq -r '.run_id' "${TEST_DIR}/state.json")
    assert_equals "test-456" "$saved_run_id" "Saved state should preserve run_id value"

    teardown_test_env
}

test_save_state_returns_standard_json_format() {
    setup_test_env

    local test_state='{"run_id":"test-789","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[],"current_ticket":null}'
    local result
    result=$(save_state "$test_state" 2>&1 || true)

    assert_contains "$result" '"success"' "Response should contain success field"
    assert_contains "$result" '"result"' "Response should contain result field"
    assert_contains "$result" '"next_action"' "Response should contain next_action field"
    assert_contains "$result" '"error"' "Response should contain error field"

    teardown_test_env
}

#
# load_state() Tests
#

test_load_state_handles_missing_file() {
    setup_test_env

    # Ensure state file doesn't exist
    rm -f "${TEST_DIR}/state.json"

    local result
    result=$(load_state 2>&1 || true)

    assert_contains "$result" '"success": false' "load_state should fail when file missing"
    assert_contains "$result" "State file not found" "Error message should indicate missing file"

    teardown_test_env
}

test_load_state_rejects_invalid_json() {
    setup_test_env

    # Create state file with invalid JSON
    echo "{broken json" > "${TEST_DIR}/state.json"

    local result
    result=$(load_state 2>&1 || true)

    assert_contains "$result" '"success": false' "load_state should reject invalid JSON"
    assert_contains "$result" "invalid JSON" "Error message should indicate JSON error"

    teardown_test_env
}

test_load_state_reads_valid_state() {
    setup_test_env

    # Create valid state file
    local test_state='{"run_id":"test-load-123","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[],"current_ticket":null}'
    save_state "$test_state" &>/dev/null || true

    local result
    result=$(load_state 2>&1 || true)

    assert_contains "$result" '"success": true' "load_state should succeed with valid state file"

    # Verify state content is returned in result.state
    local loaded_run_id
    loaded_run_id=$(echo "$result" | jq -r '.result.state.run_id')
    assert_equals "test-load-123" "$loaded_run_id" "Loaded state should contain correct run_id"

    teardown_test_env
}

test_load_state_returns_standard_json_format() {
    setup_test_env

    local test_state='{"run_id":"test-format","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[],"current_ticket":null}'
    save_state "$test_state" &>/dev/null || true

    local result
    result=$(load_state 2>&1 || true)

    assert_contains "$result" '"success"' "Response should contain success field"
    assert_contains "$result" '"result"' "Response should contain result field"
    assert_contains "$result" '"next_action"' "Response should contain next_action field"
    assert_contains "$result" '"error"' "Response should contain error field"

    teardown_test_env
}

#
# validate_state() Tests - Missing File and Invalid JSON
#

test_validate_state_handles_missing_file() {
    setup_test_env

    # Ensure state file doesn't exist
    rm -f "${TEST_DIR}/state.json"

    local result
    result=$(validate_state 2>&1 || true)

    assert_contains "$result" '"success": false' "validate_state should fail when file missing"
    assert_contains "$result" "State file not found" "Error message should indicate missing file"

    teardown_test_env
}

test_validate_state_detects_invalid_json() {
    setup_test_env

    # Create state file with malformed JSON
    echo "{broken json" > "${TEST_DIR}/state.json"

    local result
    result=$(validate_state 2>&1 || true)

    assert_contains "$result" '"success": false' "validate_state should reject invalid JSON"
    assert_contains "$result" "Invalid JSON syntax" "Error message should indicate JSON syntax error"

    teardown_test_env
}

#
# validate_state() Tests - Required Fields
#

test_validate_state_detects_missing_required_fields() {
    setup_test_env

    # Create state with missing required fields
    cat > "${TEST_DIR}/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running"
}
EOF

    local result
    result=$(validate_state 2>&1 || true)

    assert_contains "$result" '"success": false' "validate_state should reject state missing required fields"
    assert_contains "$result" "Missing required fields" "Error message should indicate missing fields"

    teardown_test_env
}

#
# validate_state() Tests - Field Type Validation
#

test_validate_state_detects_incorrect_field_types() {
    setup_test_env

    # Create state with tickets as string instead of array
    cat > "${TEST_DIR}/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-12-14T10:00:00Z",
  "tickets": "not-an-array",
  "current_ticket": null
}
EOF

    local result
    result=$(validate_state 2>&1 || true)

    assert_contains "$result" '"success": false' "validate_state should reject incorrect field types"
    assert_contains "$result" "Type validation failed" "Error message should indicate type error"

    teardown_test_env
}

#
# validate_state() Tests - Status Enum Validation
#

test_validate_state_detects_invalid_status_enum() {
    setup_test_env

    cat > "${TEST_DIR}/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "invalid-status",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-12-14T10:00:00Z",
  "tickets": [],
  "current_ticket": null
}
EOF

    local result
    result=$(validate_state 2>&1 || true)

    assert_contains "$result" '"success": false' "validate_state should reject invalid status value"
    assert_contains "$result" "Invalid status value" "Error message should indicate invalid status"

    teardown_test_env
}

test_validate_state_accepts_all_valid_status_values() {
    setup_test_env

    local all_valid=true
    for status in "running" "paused" "completed" "failed" "completed_with_failures"; do
        cat > "${TEST_DIR}/state.json" << EOF
{
  "run_id": "test-123",
  "status": "$status",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-12-14T10:00:00Z",
  "tickets": [],
  "current_ticket": null
}
EOF

        local result
        result=$(validate_state 2>&1 || true)

        if ! echo "$result" | grep -q '"success": true'; then
            all_valid=false
            break
        fi
    done

    assert_true "[ '$all_valid' = true ]" "validate_state should accept all valid status values"

    teardown_test_env
}

#
# validate_state() Tests - Input Type Enum Validation
#

test_validate_state_detects_invalid_input_type_enum() {
    setup_test_env

    cat > "${TEST_DIR}/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "invalid-type",
  "input_value": "project=TEST",
  "started_at": "2025-12-14T10:00:00Z",
  "tickets": [],
  "current_ticket": null
}
EOF

    local result
    result=$(validate_state 2>&1 || true)

    assert_contains "$result" '"success": false' "validate_state should reject invalid input_type"
    assert_contains "$result" "Invalid input_type value" "Error message should indicate invalid input_type"

    teardown_test_env
}

test_validate_state_accepts_all_valid_input_type_values() {
    setup_test_env

    local all_valid=true
    for input_type in "jql" "epic" "team" "tickets" "resume"; do
        cat > "${TEST_DIR}/state.json" << EOF
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "$input_type",
  "input_value": "test-value",
  "started_at": "2025-12-14T10:00:00Z",
  "tickets": [],
  "current_ticket": null
}
EOF

        local result
        result=$(validate_state 2>&1 || true)

        if ! echo "$result" | grep -q '"success": true'; then
            all_valid=false
            break
        fi
    done

    assert_true "[ '$all_valid' = true ]" "validate_state should accept all valid input_type values"

    teardown_test_env
}

#
# validate_state() Tests - Referential Integrity
#

test_validate_state_detects_invalid_current_ticket_reference() {
    setup_test_env

    cat > "${TEST_DIR}/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-12-14T10:00:00Z",
  "tickets": [
    {"key": "TICKET-1", "status": "pending"}
  ],
  "current_ticket": "TICKET-999"
}
EOF

    local result
    result=$(validate_state 2>&1 || true)

    assert_contains "$result" '"success": false' "validate_state should reject non-existent current_ticket reference"
    assert_contains "$result" "current_ticket references non-existent ticket" "Error message should indicate referential integrity violation"

    teardown_test_env
}

test_validate_state_accepts_null_current_ticket() {
    setup_test_env

    cat > "${TEST_DIR}/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-12-14T10:00:00Z",
  "tickets": [
    {"key": "TICKET-1", "status": "pending"}
  ],
  "current_ticket": null
}
EOF

    local result
    result=$(validate_state 2>&1 || true)

    assert_contains "$result" '"success": true' "validate_state should accept null current_ticket"

    teardown_test_env
}

test_validate_state_accepts_valid_current_ticket_reference() {
    setup_test_env

    cat > "${TEST_DIR}/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-12-14T10:00:00Z",
  "tickets": [
    {"key": "TICKET-1", "status": "pending"},
    {"key": "TICKET-2", "status": "in_progress"}
  ],
  "current_ticket": "TICKET-2"
}
EOF

    local result
    result=$(validate_state 2>&1 || true)

    assert_contains "$result" '"success": true' "validate_state should accept valid current_ticket reference"

    teardown_test_env
}

#
# validate_state() Tests - Valid Complete State
#

test_validate_state_accepts_complete_valid_state() {
    setup_test_env

    cat > "${TEST_DIR}/state.json" << 'EOF'
{
  "run_id": "run-20251214-120000",
  "status": "running",
  "input_type": "jql",
  "input_value": "project=TEST AND status=Open",
  "started_at": "2025-12-14T12:00:00Z",
  "tickets": [
    {
      "key": "TEST-123",
      "status": "in_progress",
      "completed_stages": ["planning"],
      "error": null
    },
    {
      "key": "TEST-456",
      "status": "pending",
      "completed_stages": [],
      "error": null
    }
  ],
  "current_ticket": "TEST-123"
}
EOF

    local result
    result=$(validate_state 2>&1 || true)

    assert_contains "$result" '"success": true' "validate_state should accept complete valid state"
    assert_contains "$result" "State validation passed" "Success message should confirm validation passed"

    teardown_test_env
}

#
# validate_state() Tests - State Transition Validation
#

test_validate_state_accepts_valid_transition_running_to_completed() {
    setup_test_env

    cat > "${TEST_DIR}/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "completed",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-12-14T10:00:00Z",
  "tickets": [],
  "current_ticket": null
}
EOF

    local result
    result=$(validate_state "running" 2>&1 || true)

    assert_contains "$result" '"success": true' "validate_state should accept transition from running to completed"

    teardown_test_env
}

test_validate_state_rejects_invalid_transition_completed_to_running() {
    setup_test_env

    cat > "${TEST_DIR}/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-12-14T10:00:00Z",
  "tickets": [],
  "current_ticket": null
}
EOF

    local result
    result=$(validate_state "completed" 2>&1 || true)

    assert_contains "$result" '"success": false' "validate_state should reject transition from completed (terminal state) to running"
    assert_contains "$result" "Invalid state transition" "Error message should indicate invalid transition"

    teardown_test_env
}

test_validate_state_accepts_terminal_state_staying_same() {
    setup_test_env

    cat > "${TEST_DIR}/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "completed",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-12-14T10:00:00Z",
  "tickets": [],
  "current_ticket": null
}
EOF

    local result
    result=$(validate_state "completed" 2>&1 || true)

    assert_contains "$result" '"success": true' "validate_state should accept terminal state staying in same state"

    teardown_test_env
}

#
# ==========================================
# Internal Query Helper Tests
# ==========================================
#

test_get_current_ticket_returns_null_when_no_current() {
    setup_test_env

    # Create state with null current_ticket
    local state='{"run_id":"test","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[],"current_ticket":null}'
    echo "$state" > "${STATE_FILE}"

    local result
    result=$(_get_current_ticket)
    local ticket
    ticket=$(echo "$result" | jq -r '.result.ticket')

    assert_equals "null" "$ticket" "_get_current_ticket should return null when no current ticket"
    teardown_test_env
}

test_get_current_ticket_returns_ticket_when_present() {
    setup_test_env

    # Create state with current_ticket set
    local state='{"run_id":"test","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[{"key":"UIT-1001","status":"in_progress","completed_stages":[],"error":null}],"current_ticket":"UIT-1001"}'
    echo "$state" > "${STATE_FILE}"

    local result
    result=$(_get_current_ticket)
    local ticket_key
    ticket_key=$(echo "$result" | jq -r '.result.ticket.key')

    assert_equals "UIT-1001" "$ticket_key" "_get_current_ticket should return ticket when present"
    teardown_test_env
}

test_get_current_ticket_returns_full_ticket_object() {
    setup_test_env

    # Create state with ticket containing multiple fields
    local state='{"run_id":"test","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[{"key":"TEST-123","status":"in_progress","completed_stages":["planning","review"],"error":null}],"current_ticket":"TEST-123"}'
    echo "$state" > "${STATE_FILE}"

    local result
    result=$(_get_current_ticket)
    local ticket_status
    ticket_status=$(echo "$result" | jq -r '.result.ticket.status')
    local completed_count
    completed_count=$(echo "$result" | jq -r '.result.ticket.completed_stages | length')

    assert_equals "in_progress" "$ticket_status" "_get_current_ticket should return ticket with status field"
    assert_equals "2" "$completed_count" "_get_current_ticket should return ticket with completed_stages array"
    teardown_test_env
}

test_get_ticket_status_returns_status_for_valid_ticket() {
    setup_test_env

    # Create state with multiple tickets
    local state='{"run_id":"test","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[{"key":"TICKET-1","status":"pending","completed_stages":[],"error":null},{"key":"TICKET-2","status":"in_progress","completed_stages":[],"error":null}],"current_ticket":"TICKET-2"}'
    echo "$state" > "${STATE_FILE}"

    local result
    result=$(_get_ticket_status "TICKET-1")
    local status
    status=$(echo "$result" | jq -r '.result.status')

    assert_equals "pending" "$status" "_get_ticket_status should return status for valid ticket"
    teardown_test_env
}

test_get_ticket_status_returns_error_for_invalid_ticket() {
    setup_test_env

    # Create state with known tickets
    local state='{"run_id":"test","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[{"key":"TICKET-1","status":"pending","completed_stages":[],"error":null}],"current_ticket":null}'
    echo "$state" > "${STATE_FILE}"

    local result
    result=$(_get_ticket_status "NONEXISTENT-999" 2>&1 || true)

    assert_contains "$result" '"success":false' "_get_ticket_status should return failure for invalid ticket"
    assert_contains "$result" "Ticket not found: NONEXISTENT-999" "_get_ticket_status should include error message with ticket key"
    teardown_test_env
}

test_get_ticket_status_handles_completed_status() {
    setup_test_env

    # Create state with completed ticket
    local state='{"run_id":"test","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[{"key":"DONE-1","status":"completed","completed_stages":["planning","execution","verification"],"error":null}],"current_ticket":null}'
    echo "$state" > "${STATE_FILE}"

    local result
    result=$(_get_ticket_status "DONE-1")
    local status
    status=$(echo "$result" | jq -r '.result.status')

    assert_equals "completed" "$status" "_get_ticket_status should handle completed status"
    teardown_test_env
}

test_is_workflow_complete_returns_true_when_all_tickets_completed() {
    setup_test_env

    # Create state with all completed tickets
    local state='{"run_id":"test","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[{"key":"TICKET-1","status":"completed","completed_stages":[],"error":null},{"key":"TICKET-2","status":"completed","completed_stages":[],"error":null}],"current_ticket":null}'
    echo "$state" > "${STATE_FILE}"

    local result
    result=$(_is_workflow_complete)
    local exit_code=$?
    local complete
    complete=$(echo "$result" | jq -r '.result.complete')

    assert_equals "0" "$exit_code" "_is_workflow_complete should return exit code 0 when complete"
    assert_equals "true" "$complete" "_is_workflow_complete should return complete:true when all tickets completed"
    teardown_test_env
}

test_is_workflow_complete_returns_false_when_pending_tickets_exist() {
    setup_test_env

    # Create state with pending tickets
    local state='{"run_id":"test","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[{"key":"TICKET-1","status":"completed","completed_stages":[],"error":null},{"key":"TICKET-2","status":"pending","completed_stages":[],"error":null}],"current_ticket":null}'
    echo "$state" > "${STATE_FILE}"

    # Call function and capture both output and exit code
    set +e
    local result
    result=$(_is_workflow_complete)
    local exit_code=$?
    set -e
    local complete
    complete=$(echo "$result" | jq -r '.result.complete')

    assert_equals "1" "$exit_code" "_is_workflow_complete should return exit code 1 when incomplete"
    assert_equals "false" "$complete" "_is_workflow_complete should return complete:false when pending tickets exist"
    teardown_test_env
}

test_is_workflow_complete_returns_false_when_in_progress_tickets_exist() {
    setup_test_env

    # Create state with in_progress tickets
    local state='{"run_id":"test","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[{"key":"TICKET-1","status":"completed","completed_stages":[],"error":null},{"key":"TICKET-2","status":"in_progress","completed_stages":[],"error":null}],"current_ticket":"TICKET-2"}'
    echo "$state" > "${STATE_FILE}"

    # Call function and capture both output and exit code
    set +e
    local result
    result=$(_is_workflow_complete)
    local exit_code=$?
    set -e
    local complete
    complete=$(echo "$result" | jq -r '.result.complete')

    assert_equals "1" "$exit_code" "_is_workflow_complete should return exit code 1 when work in progress"
    assert_equals "false" "$complete" "_is_workflow_complete should return complete:false when in_progress tickets exist"
    teardown_test_env
}

test_is_workflow_complete_returns_true_for_empty_tickets_array() {
    setup_test_env

    # Create state with empty tickets array
    local state='{"run_id":"test","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[],"current_ticket":null}'
    echo "$state" > "${STATE_FILE}"

    local result
    result=$(_is_workflow_complete)
    local exit_code=$?
    local complete
    complete=$(echo "$result" | jq -r '.result.complete')

    assert_equals "0" "$exit_code" "_is_workflow_complete should return exit code 0 when no tickets"
    assert_equals "true" "$complete" "_is_workflow_complete should return complete:true when tickets array is empty"
    teardown_test_env
}

# ==============================================================================
# save_checkpoint() Tests
# ==============================================================================

test_save_checkpoint_creates_checkpoint_file() {
    setup_test_env

    # Create initial state
    local state='{"run_id":"test","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[],"current_ticket":null}'
    echo "$state" > "${STATE_FILE}"

    # Save checkpoint (filter out log lines for clean JSON)
    local result
    result=$(save_checkpoint "test_label" | grep -v '^[0-9]')
    local checkpoint_id
    checkpoint_id=$(echo "$result" | jq -r '.result.checkpoint_id')

    assert_equals "checkpoint_001" "$checkpoint_id" "First checkpoint should be 001"
    teardown_test_env
}

test_save_checkpoint_file_exists_on_disk() {
    setup_test_env

    local state='{"run_id":"test","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[],"current_ticket":null}'
    echo "$state" > "${STATE_FILE}"

    save_checkpoint "test_label" >/dev/null

    # Verify file exists
    [ -f "${CHECKPOINT_DIR}/checkpoint_001.json" ]
    assert_equals "0" "$?" "Checkpoint file should exist on disk"
    teardown_test_env
}

test_save_checkpoint_includes_label() {
    setup_test_env

    local state='{"run_id":"test","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[],"current_ticket":null}'
    echo "$state" > "${STATE_FILE}"

    save_checkpoint "my_custom_label" >/dev/null

    local label
    label=$(jq -r '.label' "${CHECKPOINT_DIR}/checkpoint_001.json")
    assert_equals "my_custom_label" "$label" "Checkpoint should contain the label"
    teardown_test_env
}

test_save_checkpoint_includes_state_snapshot() {
    setup_test_env

    local state='{"run_id":"snapshot_test","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[],"current_ticket":null}'
    echo "$state" > "${STATE_FILE}"

    save_checkpoint "test" >/dev/null

    local snapshot_run_id
    snapshot_run_id=$(jq -r '.state.run_id' "${CHECKPOINT_DIR}/checkpoint_001.json")
    assert_equals "snapshot_test" "$snapshot_run_id" "Checkpoint should contain state snapshot with correct run_id"
    teardown_test_env
}

test_save_checkpoint_numbering_increments() {
    setup_test_env

    local state='{"run_id":"test","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[],"current_ticket":null}'
    echo "$state" > "${STATE_FILE}"

    save_checkpoint "cp1" >/dev/null
    save_checkpoint "cp2" >/dev/null
    save_checkpoint "cp3" >/dev/null

    [ -f "${CHECKPOINT_DIR}/checkpoint_001.json" ] && \
    [ -f "${CHECKPOINT_DIR}/checkpoint_002.json" ] && \
    [ -f "${CHECKPOINT_DIR}/checkpoint_003.json" ]
    assert_equals "0" "$?" "Checkpoints should be numbered sequentially"
    teardown_test_env
}

test_save_checkpoint_rotation_deletes_oldest() {
    setup_test_env
    export CONFIG_CHECKPOINT_MAX=3

    local state='{"run_id":"test","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[],"current_ticket":null}'
    echo "$state" > "${STATE_FILE}"

    # Create 4 checkpoints (should rotate oldest)
    save_checkpoint "cp1" >/dev/null
    save_checkpoint "cp2" >/dev/null
    save_checkpoint "cp3" >/dev/null
    save_checkpoint "cp4" >/dev/null

    # checkpoint_001 should be deleted, 002-004 should exist
    [ ! -f "${CHECKPOINT_DIR}/checkpoint_001.json" ]
    assert_equals "0" "$?" "Oldest checkpoint should be deleted during rotation"

    local count
    count=$(ls -1 "${CHECKPOINT_DIR}"/checkpoint_*.json 2>/dev/null | wc -l)
    assert_equals "3" "$count" "Should have exactly CONFIG_CHECKPOINT_MAX checkpoints"
    teardown_test_env
}

test_save_checkpoint_requires_label() {
    setup_test_env

    local state='{"run_id":"test","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[],"current_ticket":null}'
    echo "$state" > "${STATE_FILE}"

    local result
    result=$(save_checkpoint "" 2>/dev/null | grep -v '^[0-9]')
    local success
    success=$(echo "$result" | jq -r '.success')

    assert_equals "false" "$success" "save_checkpoint should fail without label"
    teardown_test_env
}

# ==============================================================================
# restore_checkpoint() Tests
# ==============================================================================

test_restore_checkpoint_by_id() {
    setup_test_env

    # Create and checkpoint original state
    local state='{"run_id":"original","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[],"current_ticket":null}'
    echo "$state" > "${STATE_FILE}"
    save_checkpoint "before_change" >/dev/null

    # Modify state
    local modified_state='{"run_id":"modified","status":"completed","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[],"current_ticket":null}'
    echo "$modified_state" > "${STATE_FILE}"

    # Restore checkpoint
    restore_checkpoint "checkpoint_001" >/dev/null

    # Verify state restored
    local run_id
    run_id=$(jq -r '.run_id' "${STATE_FILE}")
    assert_equals "original" "$run_id" "State should be restored to original"
    teardown_test_env
}

test_restore_checkpoint_latest() {
    setup_test_env

    # Create multiple checkpoints with different states
    local state1='{"run_id":"v1","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[],"current_ticket":null}'
    echo "$state1" > "${STATE_FILE}"
    save_checkpoint "v1" >/dev/null

    local state2='{"run_id":"v2","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[],"current_ticket":null}'
    echo "$state2" > "${STATE_FILE}"
    save_checkpoint "v2" >/dev/null

    local state3='{"run_id":"v3","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[],"current_ticket":null}'
    echo "$state3" > "${STATE_FILE}"
    save_checkpoint "v3" >/dev/null

    # Modify state
    local modified_state='{"run_id":"current","status":"completed","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[],"current_ticket":null}'
    echo "$modified_state" > "${STATE_FILE}"

    # Restore latest
    restore_checkpoint "latest" >/dev/null

    # Should restore v3 (latest checkpoint)
    local run_id
    run_id=$(jq -r '.run_id' "${STATE_FILE}")
    assert_equals "v3" "$run_id" "Should restore latest checkpoint (v3)"
    teardown_test_env
}

test_restore_checkpoint_returns_checkpoint_id() {
    setup_test_env

    local state='{"run_id":"test","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[],"current_ticket":null}'
    echo "$state" > "${STATE_FILE}"
    save_checkpoint "test" >/dev/null
    save_checkpoint "test2" >/dev/null

    local result
    result=$(restore_checkpoint "latest" | grep -v '^[0-9]')
    local checkpoint_id
    checkpoint_id=$(echo "$result" | jq -r '.result.checkpoint_id')

    assert_equals "checkpoint_002" "$checkpoint_id" "Should return the restored checkpoint ID"
    teardown_test_env
}

test_restore_checkpoint_not_found() {
    setup_test_env

    local state='{"run_id":"test","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[],"current_ticket":null}'
    echo "$state" > "${STATE_FILE}"

    local result
    result=$(restore_checkpoint "checkpoint_999" 2>/dev/null | grep -v '^[0-9]')
    local success
    success=$(echo "$result" | jq -r '.success')

    assert_equals "false" "$success" "Should return error for non-existent checkpoint"
    teardown_test_env
}

test_restore_checkpoint_no_checkpoints_available() {
    setup_test_env

    local state='{"run_id":"test","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[],"current_ticket":null}'
    echo "$state" > "${STATE_FILE}"

    # Try to restore latest with no checkpoints
    local result
    result=$(restore_checkpoint "latest" 2>/dev/null | grep -v '^[0-9]')
    local error
    error=$(echo "$result" | jq -r '.error')

    assert_contains "$error" "No checkpoints" "Should indicate no checkpoints available"
    teardown_test_env
}

test_restore_checkpoint_corrupted() {
    setup_test_env

    local state='{"run_id":"test","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[],"current_ticket":null}'
    echo "$state" > "${STATE_FILE}"

    # Create corrupted checkpoint (missing required fields)
    mkdir -p "${CHECKPOINT_DIR}"
    echo '{"only_one_field": "bad"}' > "${CHECKPOINT_DIR}/checkpoint_001.json"

    local result
    result=$(restore_checkpoint "checkpoint_001" 2>/dev/null | grep -v '^[0-9]')
    local success
    success=$(echo "$result" | jq -r '.success')

    assert_equals "false" "$success" "Should reject corrupted checkpoint"
    teardown_test_env
}

# ==============================================================================
# Edge Case and Negative Tests
# ==============================================================================

# Path to test fixtures
FIXTURES_DIR="${SCRIPT_DIR}/fixtures/state"

test_validate_state_with_valid_fixture() {
    setup_test_env

    # Use valid_state.json fixture
    cp "${FIXTURES_DIR}/valid_state.json" "${STATE_FILE}"

    local result
    result=$(validate_state | grep -v '^[0-9]')
    local success
    success=$(echo "$result" | jq -r '.success')

    assert_equals "true" "$success" "Valid fixture should pass validation"
    teardown_test_env
}

test_validate_state_with_minimal_fixture() {
    setup_test_env

    # Use minimal_state.json fixture (empty tickets array)
    cp "${FIXTURES_DIR}/minimal_state.json" "${STATE_FILE}"

    local result
    result=$(validate_state | grep -v '^[0-9]')
    local success
    success=$(echo "$result" | jq -r '.success')

    assert_equals "true" "$success" "Minimal state with empty tickets should be valid"
    teardown_test_env
}

test_validate_state_with_corrupted_fixture() {
    setup_test_env

    # Use corrupted_state.json fixture
    cp "${FIXTURES_DIR}/corrupted_state.json" "${STATE_FILE}"

    local result
    result=$(validate_state 2>/dev/null | grep -v '^[0-9]')
    local success
    success=$(echo "$result" | jq -r '.success')

    assert_equals "false" "$success" "Corrupted JSON should fail validation"
    teardown_test_env
}

test_validate_state_with_missing_fields_fixture() {
    setup_test_env

    # Use missing_fields_state.json fixture
    cp "${FIXTURES_DIR}/missing_fields_state.json" "${STATE_FILE}"

    local result
    result=$(validate_state 2>/dev/null | grep -v '^[0-9]')
    local success
    success=$(echo "$result" | jq -r '.success')

    assert_equals "false" "$success" "State with missing fields should fail validation"
    teardown_test_env
}

test_validate_state_with_invalid_types_fixture() {
    setup_test_env

    # Use invalid_types_state.json fixture
    cp "${FIXTURES_DIR}/invalid_types_state.json" "${STATE_FILE}"

    local result
    result=$(validate_state 2>/dev/null | grep -v '^[0-9]')
    local success
    success=$(echo "$result" | jq -r '.success')

    assert_equals "false" "$success" "State with invalid types should fail validation"
    teardown_test_env
}

test_save_state_empty_string() {
    setup_test_env

    local result
    result=$(save_state "" 2>/dev/null | grep -v '^[0-9]')
    local success
    success=$(echo "$result" | jq -r '.success')

    assert_equals "false" "$success" "Empty string should fail save_state"
    teardown_test_env
}

test_load_state_empty_file() {
    setup_test_env

    # Create empty state file
    touch "${STATE_FILE}"

    local result
    result=$(load_state 2>/dev/null | grep -v '^[0-9]')
    local success
    success=$(echo "$result" | jq -r '.success')

    assert_equals "false" "$success" "Empty file should fail load_state"
    teardown_test_env
}

test_checkpoint_max_boundary_exact() {
    setup_test_env

    source "${SCRIPT_DIR}/../lib/common.sh"
    CONFIG_CHECKPOINT_MAX=5

    local state='{"run_id":"test","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[],"current_ticket":null}'
    echo "$state" > "${STATE_FILE}"

    # Create exactly CONFIG_CHECKPOINT_MAX checkpoints
    for i in {1..5}; do
        save_checkpoint "cp$i" >/dev/null
    done

    local count
    count=$(ls -1 "${CHECKPOINT_DIR}"/checkpoint_*.json 2>/dev/null | wc -l)
    assert_equals "5" "$count" "Should have exactly 5 checkpoints at boundary"

    # Create one more, should trigger rotation
    save_checkpoint "cp6" >/dev/null

    count=$(ls -1 "${CHECKPOINT_DIR}"/checkpoint_*.json 2>/dev/null | wc -l)
    assert_equals "5" "$count" "Should still have 5 checkpoints after rotation"

    teardown_test_env
}

test_restore_checkpoint_empty_id() {
    setup_test_env

    local result
    result=$(restore_checkpoint "" 2>/dev/null | grep -v '^[0-9]')
    local success
    success=$(echo "$result" | jq -r '.success')

    assert_equals "false" "$success" "Empty checkpoint ID should fail"
    teardown_test_env
}

test_save_checkpoint_verifies_state_file_exists() {
    setup_test_env

    # Don't create state file

    local result
    result=$(save_checkpoint "test" 2>/dev/null | grep -v '^[0-9]')
    local success
    success=$(echo "$result" | jq -r '.success')

    assert_equals "false" "$success" "save_checkpoint should fail without state file"
    teardown_test_env
}

test_validate_state_referential_integrity_multiple_tickets() {
    setup_test_env

    # State with current_ticket pointing to non-existent ticket
    local state='{"run_id":"test","status":"running","input_type":"jql","input_value":"test","started_at":"2025-12-14T10:00:00Z","tickets":[{"key":"UIT-1","status":"pending","completed_stages":[],"error":null}],"current_ticket":"UIT-999"}'
    echo "$state" > "${STATE_FILE}"

    local result
    result=$(validate_state 2>/dev/null | grep -v '^[0-9]')
    local success
    success=$(echo "$result" | jq -r '.success')

    assert_equals "false" "$success" "Should reject invalid current_ticket reference"
    teardown_test_env
}

# Run all tests
run_tests
