#!/usr/bin/env bash
#
# Test suite for state-manager.sh module
# Tests all acceptance criteria from ASDW-2.1001
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function to print test results
pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Change to automation directory
cd "$(dirname "$0")/.."

echo "========================================="
echo "State Manager Module Test Suite"
echo "========================================="
echo ""

# Test 1: Module fails without RUN_DIR
echo "Test 1: Module rejects missing RUN_DIR..."
if bash -c 'unset RUN_DIR; source modules/state-manager.sh' 2>&1 | grep -q "RUN_DIR not set"; then
    pass "Module correctly rejects missing RUN_DIR"
else
    fail "Module did not reject missing RUN_DIR"
fi

# Setup for remaining tests
TEST_DIR="/tmp/test-state-manager-$$"
mkdir -p "$TEST_DIR"
export RUN_DIR="$TEST_DIR"
export LOG_FILE="$TEST_DIR/test.log"
export CONFIG_LOG_LEVEL=error

# Source the module
source modules/state-manager.sh

# Test 2: Verify global variables are set
echo "Test 2: Global variables are set correctly..."
if [ "$STATE_FILE" = "$RUN_DIR/state.json" ] && [ "$CHECKPOINT_DIR" = "$RUN_DIR/checkpoints" ]; then
    pass "Global variables STATE_FILE and CHECKPOINT_DIR set correctly"
else
    fail "Global variables not set correctly (STATE_FILE=$STATE_FILE, CHECKPOINT_DIR=$CHECKPOINT_DIR)"
fi

# Test 3: save_state validates empty input
echo "Test 3: save_state rejects empty input..."
save_state "" > "$TEST_DIR/output.txt" 2>&1 || true
if grep -q '"success": false' "$TEST_DIR/output.txt"; then
    pass "save_state correctly rejects empty input"
else
    fail "save_state did not reject empty input"
fi

# Test 4: save_state validates invalid JSON
echo "Test 4: save_state rejects invalid JSON..."
save_state "{broken json" > "$TEST_DIR/output.txt" 2>&1 || true
if grep -q '"success": false' "$TEST_DIR/output.txt"; then
    pass "save_state correctly rejects invalid JSON"
else
    fail "save_state did not reject invalid JSON"
fi

# Test 5: save_state works with valid JSON
echo "Test 5: save_state accepts valid JSON..."
test_state='{"run_id": "test-123", "status": "running", "tickets": []}'
save_state "$test_state" > "$TEST_DIR/output.txt" 2>&1 || true
if grep -q '"success": true' "$TEST_DIR/output.txt"; then
    pass "save_state successfully saved valid JSON"
else
    fail "save_state failed with valid JSON"
fi

# Test 6: Verify state file was created
echo "Test 6: State file is created..."
if [ -f "$RUN_DIR/state.json" ]; then
    pass "state.json file created"
else
    fail "state.json file not created"
fi

# Test 7: Verify permissions are 600
echo "Test 7: State file has correct permissions..."
if [ -f "$RUN_DIR/state.json" ]; then
    perms=$(stat -c "%a" "$RUN_DIR/state.json" 2>/dev/null || stat -f "%A" "$RUN_DIR/state.json" 2>/dev/null || echo "000")
    if [ "$perms" = "600" ]; then
        pass "state.json has correct permissions (600)"
    else
        fail "state.json has incorrect permissions ($perms, expected 600)"
    fi
else
    fail "state.json file does not exist for permission check"
fi

# Test 8: Verify content is valid JSON
echo "Test 8: Saved content is valid JSON..."
if [ -f "$RUN_DIR/state.json" ] && jq . "$RUN_DIR/state.json" >/dev/null 2>&1; then
    pass "Saved content is valid JSON"
else
    fail "Saved content is not valid JSON"
fi

# Test 9: load_state reads the saved state
echo "Test 9: load_state reads saved state..."
load_state > "$TEST_DIR/output.txt" 2>&1 || true
if grep -q '"success": true' "$TEST_DIR/output.txt"; then
    run_id=$(jq -r '.result.state.run_id' "$TEST_DIR/output.txt" 2>/dev/null || echo "")
    if [ "$run_id" = "test-123" ]; then
        pass "load_state successfully loaded state with correct content"
    else
        fail "load_state loaded incorrect content (run_id=$run_id)"
    fi
else
    fail "load_state failed"
fi

# Test 10: load_state validates JSON structure
echo "Test 10: load_state rejects corrupted state file..."
echo "{broken" > "$RUN_DIR/state.json"
load_state > "$TEST_DIR/output.txt" 2>&1 || true
if grep -q '"success": false' "$TEST_DIR/output.txt"; then
    pass "load_state correctly rejects invalid JSON"
else
    fail "load_state did not reject invalid JSON"
fi

# Test 11: load_state handles missing file
echo "Test 11: load_state handles missing state file..."
rm -f "$RUN_DIR/state.json"
load_state > "$TEST_DIR/output.txt" 2>&1 || true
if grep -q '"success": false' "$TEST_DIR/output.txt"; then
    pass "load_state correctly handles missing file"
else
    fail "load_state did not handle missing file correctly"
fi

# Test 12: Functions return standard JSON format
echo "Test 12: Functions return standard JSON response format..."
test_state='{"run_id": "test-456", "status": "complete"}'
save_state "$test_state" > "$TEST_DIR/output.txt" 2>&1 || true
if grep -q '"success"' "$TEST_DIR/output.txt" && \
   grep -q '"result"' "$TEST_DIR/output.txt" && \
   grep -q '"next_action"' "$TEST_DIR/output.txt" && \
   grep -q '"error"' "$TEST_DIR/output.txt"; then
    pass "Response follows standard JSON format (success, result, next_action, error)"
else
    fail "Response does not follow standard format"
fi

echo ""
echo "========================================="
echo "validate_state() Tests (ASDW-2.1002)"
echo "========================================="
echo ""

# Test 13: validate_state handles missing state file
echo "Test 13: validate_state handles missing state file..."
rm -f "$RUN_DIR/state.json"
validate_state > "$TEST_DIR/output.txt" 2>&1 || true
if grep -q '"success": false' "$TEST_DIR/output.txt" && grep -q "State file not found" "$TEST_DIR/output.txt"; then
    pass "validate_state correctly handles missing state file"
else
    fail "validate_state did not handle missing state file correctly"
fi

# Test 14: validate_state detects malformed JSON
echo "Test 14: validate_state detects malformed JSON..."
echo "{broken json" > "$RUN_DIR/state.json"
validate_state > "$TEST_DIR/output.txt" 2>&1 || true
if grep -q '"success": false' "$TEST_DIR/output.txt" && grep -q "Invalid JSON syntax" "$TEST_DIR/output.txt"; then
    pass "validate_state correctly detects malformed JSON"
else
    fail "validate_state did not detect malformed JSON"
fi

# Test 15: validate_state detects missing required fields
echo "Test 15: validate_state detects missing required fields..."
cat > "$RUN_DIR/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running"
}
EOF
validate_state > "$TEST_DIR/output.txt" 2>&1 || true
if grep -q '"success": false' "$TEST_DIR/output.txt" && grep -q "Missing required fields" "$TEST_DIR/output.txt"; then
    pass "validate_state correctly detects missing required fields"
else
    fail "validate_state did not detect missing required fields"
fi

# Test 16: validate_state detects incorrect field types
echo "Test 16: validate_state detects incorrect field types (tickets not array)..."
cat > "$RUN_DIR/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-01-01T00:00:00Z",
  "tickets": "not-an-array",
  "current_ticket": null
}
EOF
validate_state > "$TEST_DIR/output.txt" 2>&1 || true
if grep -q '"success": false' "$TEST_DIR/output.txt" && grep -q "Type validation failed" "$TEST_DIR/output.txt"; then
    pass "validate_state correctly detects incorrect field types"
else
    fail "validate_state did not detect incorrect field types"
fi

# Test 17: validate_state detects invalid status enum
echo "Test 17: validate_state detects invalid status enum value..."
cat > "$RUN_DIR/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "invalid-status",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-01-01T00:00:00Z",
  "tickets": [],
  "current_ticket": null
}
EOF
validate_state > "$TEST_DIR/output.txt" 2>&1 || true
if grep -q '"success": false' "$TEST_DIR/output.txt" && grep -q "Invalid status value" "$TEST_DIR/output.txt"; then
    pass "validate_state correctly detects invalid status enum"
else
    fail "validate_state did not detect invalid status enum"
fi

# Test 18: validate_state accepts all valid status values
echo "Test 18: validate_state accepts all valid status enum values..."
all_status_valid=true
for status in "running" "paused" "completed" "failed" "completed_with_failures"; do
    cat > "$RUN_DIR/state.json" << EOF
{
  "run_id": "test-123",
  "status": "$status",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-01-01T00:00:00Z",
  "tickets": [],
  "current_ticket": null
}
EOF
    validate_state > "$TEST_DIR/output.txt" 2>&1 || true
    if ! grep -q '"success": true' "$TEST_DIR/output.txt"; then
        all_status_valid=false
        break
    fi
done
if [ "$all_status_valid" = true ]; then
    pass "validate_state accepts all valid status values"
else
    fail "validate_state rejected valid status value: $status"
fi

# Test 19: validate_state detects invalid input_type enum
echo "Test 19: validate_state detects invalid input_type enum value..."
cat > "$RUN_DIR/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "invalid-type",
  "input_value": "project=TEST",
  "started_at": "2025-01-01T00:00:00Z",
  "tickets": [],
  "current_ticket": null
}
EOF
validate_state > "$TEST_DIR/output.txt" 2>&1 || true
if grep -q '"success": false' "$TEST_DIR/output.txt" && grep -q "Invalid input_type value" "$TEST_DIR/output.txt"; then
    pass "validate_state correctly detects invalid input_type enum"
else
    fail "validate_state did not detect invalid input_type enum"
fi

# Test 20: validate_state accepts all valid input_type values
echo "Test 20: validate_state accepts all valid input_type enum values..."
all_input_type_valid=true
for input_type in "jql" "epic" "team" "tickets" "resume"; do
    cat > "$RUN_DIR/state.json" << EOF
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "$input_type",
  "input_value": "test-value",
  "started_at": "2025-01-01T00:00:00Z",
  "tickets": [],
  "current_ticket": null
}
EOF
    validate_state > "$TEST_DIR/output.txt" 2>&1 || true
    if ! grep -q '"success": true' "$TEST_DIR/output.txt"; then
        all_input_type_valid=false
        break
    fi
done
if [ "$all_input_type_valid" = true ]; then
    pass "validate_state accepts all valid input_type values"
else
    fail "validate_state rejected valid input_type value: $input_type"
fi

# Test 21: validate_state detects invalid current_ticket reference
echo "Test 21: validate_state detects current_ticket referencing non-existent ticket..."
cat > "$RUN_DIR/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-01-01T00:00:00Z",
  "tickets": [
    {"key": "TICKET-1", "status": "pending"}
  ],
  "current_ticket": "TICKET-999"
}
EOF
validate_state > "$TEST_DIR/output.txt" 2>&1 || true
if grep -q '"success": false' "$TEST_DIR/output.txt" && grep -q "current_ticket references non-existent ticket" "$TEST_DIR/output.txt"; then
    pass "validate_state correctly detects invalid current_ticket reference"
else
    fail "validate_state did not detect invalid current_ticket reference"
fi

# Test 22: validate_state accepts null current_ticket
echo "Test 22: validate_state accepts null current_ticket..."
cat > "$RUN_DIR/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-01-01T00:00:00Z",
  "tickets": [
    {"key": "TICKET-1", "status": "pending"}
  ],
  "current_ticket": null
}
EOF
validate_state > "$TEST_DIR/output.txt" 2>&1 || true
if grep -q '"success": true' "$TEST_DIR/output.txt"; then
    pass "validate_state correctly accepts null current_ticket"
else
    fail "validate_state did not accept null current_ticket"
fi

# Test 23: validate_state accepts valid current_ticket reference
echo "Test 23: validate_state accepts valid current_ticket reference..."
cat > "$RUN_DIR/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-01-01T00:00:00Z",
  "tickets": [
    {"key": "TICKET-1", "status": "pending"},
    {"key": "TICKET-2", "status": "in_progress"}
  ],
  "current_ticket": "TICKET-2"
}
EOF
validate_state > "$TEST_DIR/output.txt" 2>&1 || true
if grep -q '"success": true' "$TEST_DIR/output.txt"; then
    pass "validate_state correctly accepts valid current_ticket reference"
else
    fail "validate_state did not accept valid current_ticket reference"
fi

# Test 24: validate_state accepts completely valid state
echo "Test 24: validate_state accepts completely valid state..."
cat > "$RUN_DIR/state.json" << 'EOF'
{
  "run_id": "run-20250101-120000",
  "status": "running",
  "input_type": "jql",
  "input_value": "project=TEST AND status=Open",
  "started_at": "2025-01-01T12:00:00Z",
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
validate_state > "$TEST_DIR/output.txt" 2>&1 || true
if grep -q '"success": true' "$TEST_DIR/output.txt" && grep -q "State validation passed" "$TEST_DIR/output.txt"; then
    pass "validate_state correctly accepts completely valid state"
else
    fail "validate_state did not accept valid state"
fi

# Test 25: validate_state returns standard response format
echo "Test 25: validate_state returns standard JSON response format..."
cat > "$RUN_DIR/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-01-01T00:00:00Z",
  "tickets": [],
  "current_ticket": null
}
EOF
validate_state > "$TEST_DIR/output.txt" 2>&1 || true
if grep -q '"success"' "$TEST_DIR/output.txt" && \
   grep -q '"result"' "$TEST_DIR/output.txt" && \
   grep -q '"next_action"' "$TEST_DIR/output.txt" && \
   grep -q '"error"' "$TEST_DIR/output.txt"; then
    pass "validate_state follows standard JSON format"
else
    fail "validate_state does not follow standard format"
fi

# Test 26: validate_state detects multiple type errors
echo "Test 26: validate_state detects multiple type errors..."
cat > "$RUN_DIR/state.json" << 'EOF'
{
  "run_id": 123,
  "status": "running",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-01-01T00:00:00Z",
  "tickets": "not-array",
  "current_ticket": 456
}
EOF
validate_state > "$TEST_DIR/output.txt" 2>&1 || true
if grep -q '"success": false' "$TEST_DIR/output.txt" && grep -q "Type validation failed" "$TEST_DIR/output.txt"; then
    pass "validate_state correctly detects multiple type errors"
else
    fail "validate_state did not detect multiple type errors"
fi

echo ""
echo "========================================="
echo "State Transition Validation Tests"
echo "========================================="
echo ""

# Test 27: validate_state accepts valid transition from running to completed
echo "Test 27: validate_state accepts valid transition (running -> completed)..."
cat > "$RUN_DIR/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "completed",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-01-01T00:00:00Z",
  "tickets": [],
  "current_ticket": null
}
EOF
validate_state "running" > "$TEST_DIR/output.txt" 2>&1 || true
if grep -q '"success": true' "$TEST_DIR/output.txt"; then
    pass "validate_state accepts valid transition (running -> completed)"
else
    fail "validate_state rejected valid transition (running -> completed)"
fi

# Test 28: validate_state accepts valid transition from paused to running
echo "Test 28: validate_state accepts valid transition (paused -> running)..."
cat > "$RUN_DIR/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-01-01T00:00:00Z",
  "tickets": [],
  "current_ticket": null
}
EOF
validate_state "paused" > "$TEST_DIR/output.txt" 2>&1 || true
if grep -q '"success": true' "$TEST_DIR/output.txt"; then
    pass "validate_state accepts valid transition (paused -> running)"
else
    fail "validate_state rejected valid transition (paused -> running)"
fi

# Test 29: validate_state rejects invalid transition from completed to running
echo "Test 29: validate_state rejects invalid transition (completed -> running)..."
cat > "$RUN_DIR/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-01-01T00:00:00Z",
  "tickets": [],
  "current_ticket": null
}
EOF
validate_state "completed" > "$TEST_DIR/output.txt" 2>&1 || true
if grep -q '"success": false' "$TEST_DIR/output.txt" && grep -q "Invalid state transition" "$TEST_DIR/output.txt"; then
    pass "validate_state correctly rejects invalid transition (completed -> running)"
else
    fail "validate_state did not reject invalid transition (completed -> running)"
fi

# Test 30: validate_state rejects invalid transition from failed to running
echo "Test 30: validate_state rejects invalid transition (failed -> running)..."
cat > "$RUN_DIR/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-01-01T00:00:00Z",
  "tickets": [],
  "current_ticket": null
}
EOF
validate_state "failed" > "$TEST_DIR/output.txt" 2>&1 || true
if grep -q '"success": false' "$TEST_DIR/output.txt" && grep -q "Invalid state transition" "$TEST_DIR/output.txt"; then
    pass "validate_state correctly rejects invalid transition (failed -> running)"
else
    fail "validate_state did not reject invalid transition (failed -> running)"
fi

# Test 31: validate_state rejects invalid transition from completed_with_failures to running
echo "Test 31: validate_state rejects invalid transition (completed_with_failures -> running)..."
cat > "$RUN_DIR/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-01-01T00:00:00Z",
  "tickets": [],
  "current_ticket": null
}
EOF
validate_state "completed_with_failures" > "$TEST_DIR/output.txt" 2>&1 || true
if grep -q '"success": false' "$TEST_DIR/output.txt" && grep -q "Invalid state transition" "$TEST_DIR/output.txt"; then
    pass "validate_state correctly rejects invalid transition (completed_with_failures -> running)"
else
    fail "validate_state did not reject invalid transition (completed_with_failures -> running)"
fi

# Test 32: validate_state accepts terminal state staying in same state
echo "Test 32: validate_state accepts terminal state staying in same state (completed -> completed)..."
cat > "$RUN_DIR/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "completed",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-01-01T00:00:00Z",
  "tickets": [],
  "current_ticket": null
}
EOF
validate_state "completed" > "$TEST_DIR/output.txt" 2>&1 || true
if grep -q '"success": true' "$TEST_DIR/output.txt"; then
    pass "validate_state accepts terminal state staying in same state"
else
    fail "validate_state rejected terminal state staying in same state"
fi

# Test 33: validate_state works without previous_status parameter (backward compatibility)
echo "Test 33: validate_state works without previous_status parameter..."
cat > "$RUN_DIR/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-01-01T00:00:00Z",
  "tickets": [],
  "current_ticket": null
}
EOF
validate_state > "$TEST_DIR/output.txt" 2>&1 || true
if grep -q '"success": true' "$TEST_DIR/output.txt"; then
    pass "validate_state works without previous_status parameter"
else
    fail "validate_state failed without previous_status parameter"
fi

echo ""
echo "========================================="
echo "Internal Query Helper Tests (ASDW-2.2001)"
echo "========================================="
echo ""

# Test 34: _get_current_ticket returns null when current_ticket is null
echo "Test 34: _get_current_ticket returns null when no current ticket..."
cat > "$RUN_DIR/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-01-01T00:00:00Z",
  "tickets": [
    {"key": "TICKET-1", "status": "pending"}
  ],
  "current_ticket": null
}
EOF
_get_current_ticket > "$TEST_DIR/output.txt" 2>&1 || true
if grep -qE '"success":\s*true' "$TEST_DIR/output.txt" && grep -qE '"ticket":\s*null' "$TEST_DIR/output.txt"; then
    pass "_get_current_ticket correctly returns null when no current ticket"
else
    fail "_get_current_ticket did not return null when expected"
fi

# Test 35: _get_current_ticket returns ticket object when current_ticket is set
echo "Test 35: _get_current_ticket returns ticket object when current ticket exists..."
cat > "$RUN_DIR/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-01-01T00:00:00Z",
  "tickets": [
    {"key": "TICKET-1", "status": "pending"},
    {"key": "TICKET-2", "status": "in_progress"}
  ],
  "current_ticket": "TICKET-2"
}
EOF
_get_current_ticket > "$TEST_DIR/output.txt" 2>&1 || true
ticket_key=$(jq -r '.result.ticket.key' "$TEST_DIR/output.txt" 2>/dev/null || echo "")
if grep -qE '"success":\s*true' "$TEST_DIR/output.txt" && [ "$ticket_key" = "TICKET-2" ]; then
    pass "_get_current_ticket correctly returns current ticket object"
else
    fail "_get_current_ticket did not return correct ticket (key=$ticket_key)"
fi

# Test 36: _get_ticket_status returns status for valid ticket
echo "Test 36: _get_ticket_status returns status for valid ticket..."
cat > "$RUN_DIR/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-01-01T00:00:00Z",
  "tickets": [
    {"key": "TICKET-1", "status": "pending"},
    {"key": "TICKET-2", "status": "in_progress"}
  ],
  "current_ticket": null
}
EOF
_get_ticket_status "TICKET-1" > "$TEST_DIR/output.txt" 2>&1 || true
status=$(jq -r '.result.status' "$TEST_DIR/output.txt" 2>/dev/null || echo "")
if grep -qE '"success":\s*true' "$TEST_DIR/output.txt" && [ "$status" = "pending" ]; then
    pass "_get_ticket_status correctly returns ticket status"
else
    fail "_get_ticket_status did not return correct status (status=$status)"
fi

# Test 37: _get_ticket_status returns error for unknown ticket
echo "Test 37: _get_ticket_status returns error for unknown ticket..."
cat > "$RUN_DIR/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-01-01T00:00:00Z",
  "tickets": [
    {"key": "TICKET-1", "status": "pending"}
  ],
  "current_ticket": null
}
EOF
_get_ticket_status "TICKET-999" > "$TEST_DIR/output.txt" 2>&1 || true
if grep -qE '"success":\s*false' "$TEST_DIR/output.txt" && grep -q "Ticket not found" "$TEST_DIR/output.txt"; then
    pass "_get_ticket_status correctly returns error for unknown ticket"
else
    fail "_get_ticket_status did not return error for unknown ticket"
fi

# Test 38: _is_workflow_complete returns true when no pending/in_progress tickets
echo "Test 38: _is_workflow_complete returns true when workflow is complete..."
cat > "$RUN_DIR/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-01-01T00:00:00Z",
  "tickets": [
    {"key": "TICKET-1", "status": "completed"},
    {"key": "TICKET-2", "status": "completed"}
  ],
  "current_ticket": null
}
EOF
_is_workflow_complete > "$TEST_DIR/output.txt" 2>&1
exit_code=$?
if [ $exit_code -eq 0 ] && grep -q '"complete":true' "$TEST_DIR/output.txt"; then
    pass "_is_workflow_complete correctly returns true when complete"
else
    fail "_is_workflow_complete did not return true when expected (exit_code=$exit_code)"
fi

# Test 39: _is_workflow_complete returns false when pending tickets exist
echo "Test 39: _is_workflow_complete returns false when pending tickets exist..."
cat > "$RUN_DIR/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-01-01T00:00:00Z",
  "tickets": [
    {"key": "TICKET-1", "status": "completed"},
    {"key": "TICKET-2", "status": "pending"}
  ],
  "current_ticket": null
}
EOF
set +e
_is_workflow_complete > "$TEST_DIR/output.txt" 2>&1
exit_code=$?
set -e
if [ $exit_code -eq 1 ] && grep -qE '"complete":\s*false' "$TEST_DIR/output.txt"; then
    pass "_is_workflow_complete correctly returns false when work remains"
else
    fail "_is_workflow_complete did not return false when expected (exit_code=$exit_code)"
fi

# Test 40: _is_workflow_complete returns false when in_progress tickets exist
echo "Test 40: _is_workflow_complete returns false when in_progress tickets exist..."
cat > "$RUN_DIR/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-01-01T00:00:00Z",
  "tickets": [
    {"key": "TICKET-1", "status": "completed"},
    {"key": "TICKET-2", "status": "in_progress"}
  ],
  "current_ticket": null
}
EOF
set +e
_is_workflow_complete > "$TEST_DIR/output.txt" 2>&1
exit_code=$?
set -e
if [ $exit_code -eq 1 ] && grep -qE '"complete":\s*false' "$TEST_DIR/output.txt"; then
    pass "_is_workflow_complete correctly returns false when in_progress tickets exist"
else
    fail "_is_workflow_complete did not return false when expected (exit_code=$exit_code)"
fi

# Test 41: All internal helpers return standard JSON response format
echo "Test 41: Internal query helpers return standard JSON response format..."
cat > "$RUN_DIR/state.json" << 'EOF'
{
  "run_id": "test-123",
  "status": "running",
  "input_type": "jql",
  "input_value": "project=TEST",
  "started_at": "2025-01-01T00:00:00Z",
  "tickets": [
    {"key": "TICKET-1", "status": "pending"}
  ],
  "current_ticket": null
}
EOF

all_format_valid=true

# Test _get_current_ticket format
_get_current_ticket > "$TEST_DIR/output.txt" 2>&1 || true
if ! (grep -q '"success"' "$TEST_DIR/output.txt" && \
      grep -q '"result"' "$TEST_DIR/output.txt" && \
      grep -q '"next_action"' "$TEST_DIR/output.txt" && \
      grep -q '"error"' "$TEST_DIR/output.txt"); then
    all_format_valid=false
fi

# Test _get_ticket_status format
_get_ticket_status "TICKET-1" > "$TEST_DIR/output.txt" 2>&1 || true
if ! (grep -q '"success"' "$TEST_DIR/output.txt" && \
      grep -q '"result"' "$TEST_DIR/output.txt" && \
      grep -q '"next_action"' "$TEST_DIR/output.txt" && \
      grep -q '"error"' "$TEST_DIR/output.txt"); then
    all_format_valid=false
fi

# Test _is_workflow_complete format
_is_workflow_complete > "$TEST_DIR/output.txt" 2>&1 || true
if ! (grep -q '"success"' "$TEST_DIR/output.txt" && \
      grep -q '"result"' "$TEST_DIR/output.txt" && \
      grep -q '"next_action"' "$TEST_DIR/output.txt" && \
      grep -q '"error"' "$TEST_DIR/output.txt"); then
    all_format_valid=false
fi

if [ "$all_format_valid" = true ]; then
    pass "All internal query helpers follow standard JSON format"
else
    fail "Some internal query helpers do not follow standard format"
fi

# Cleanup
rm -rf "$TEST_DIR"

# Summary
echo ""
echo "========================================="
echo "Test Summary"
echo "========================================="
echo -e "Tests passed: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Tests failed: ${RED}${TESTS_FAILED}${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
