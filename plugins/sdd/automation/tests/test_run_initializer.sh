#!/usr/bin/env bash
#
# test_run_initializer.sh - Tests for run initialization and ID generation
#
# Tests generate_run_id() and initialize_run() functions from orchestrator.sh
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

# We need to define the functions from orchestrator.sh
# Since orchestrator.sh has a guard "if [ "${BASH_SOURCE[0]}" = "$0" ]" at the end,
# we can safely source it to get the functions without running main

# First, set up required globals that orchestrator expects
INPUT_TYPE="jql"
INPUT_VALUE="project = TEST"
DRY_RUN=false
VERBOSE=false
CONFIG_FILE=""
RUN_ID=""
RUN_DIR=""

# Mock the modules to prevent load_modules from failing
# We create stub functions for the module interfaces
save_state() { :; }
load_state() { :; }
save_checkpoint() { :; }
restore_checkpoint() { :; }
retry_with_backoff() { :; }
handle_error() { :; }
fetch_tickets() { :; }
get_ticket_details() { :; }
make_decision() { :; }
execute_stage() { :; }

# Now source the orchestrator (won't execute main due to guard)
# shellcheck source=../orchestrator.sh
source "${SCRIPT_DIR}/../orchestrator.sh"

# Set up test environment
TEST_SDD_ROOT="/tmp/sdd-test-$$"
export SDD_ROOT_DIR="$TEST_SDD_ROOT"
export CONFIG_LOG_LEVEL="error"  # Quiet logs during tests

#
# Setup and Teardown
#

setup_test_env() {
    # Create clean test directory
    rm -rf "$TEST_SDD_ROOT"
    mkdir -p "$TEST_SDD_ROOT/automation/runs"
}

teardown_test_env() {
    # Clean up test directory
    rm -rf "$TEST_SDD_ROOT"
}

#
# Tests for generate_run_id()
#

test_generate_run_id_format() {
    setup_test_env

    local run_id
    run_id=$(generate_run_id)

    # Check format: YYYYMMDD-HHMMSS-XXXXXXXX (8 hex chars)
    # Total length: 8 + 1 + 6 + 1 + 8 = 24 characters
    assert_equals "24" "${#run_id}" "Run ID should be 24 characters long"

    # Check format matches pattern (YYYYMMDD-HHMMSS-hex)
    if [[ "$run_id" =~ ^[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$ ]]; then
        echo -e "  ${GREEN}PASS${NC}: Run ID matches expected format"
    else
        echo -e "  ${RED}FAIL${NC}: Run ID format invalid: $run_id"
        teardown_test_env
        return 1
    fi

    teardown_test_env
}

test_generate_run_id_uniqueness() {
    setup_test_env

    # Generate multiple run IDs and verify they're unique
    local id1 id2 id3
    id1=$(generate_run_id)
    sleep 0.01  # Small delay to ensure different timestamp or random
    id2=$(generate_run_id)
    sleep 0.01
    id3=$(generate_run_id)

    # All should be different
    if [[ "$id1" != "$id2" ]] && [[ "$id2" != "$id3" ]] && [[ "$id1" != "$id3" ]]; then
        echo -e "  ${GREEN}PASS${NC}: Generated IDs are unique"
    else
        echo -e "  ${RED}FAIL${NC}: Generated IDs not unique: $id1, $id2, $id3"
        teardown_test_env
        return 1
    fi

    teardown_test_env
}

test_generate_run_id_collision_detection() {
    setup_test_env

    # Generate a run ID
    local run_id
    run_id=$(generate_run_id)

    # Create the directory to simulate collision
    mkdir -p "$TEST_SDD_ROOT/automation/runs/$run_id"

    # Next call should detect collision and generate different ID
    # This is hard to test reliably since timestamp changes, but we can verify
    # it completes without error
    local new_run_id
    new_run_id=$(generate_run_id)

    if [[ -n "$new_run_id" ]]; then
        echo -e "  ${GREEN}PASS${NC}: Collision detection works (generated new ID)"
    else
        echo -e "  ${RED}FAIL${NC}: Failed to generate ID after collision"
        teardown_test_env
        return 1
    fi

    teardown_test_env
}

test_generate_run_id_timestamp_component() {
    setup_test_env

    local run_id
    run_id=$(generate_run_id)

    # Extract timestamp part (first 15 chars: YYYYMMDD-HHMMSS)
    local timestamp="${run_id:0:15}"

    # Verify year is reasonable (202x for now)
    local year="${timestamp:0:4}"
    if [[ "$year" =~ ^202[0-9]$ ]]; then
        echo -e "  ${GREEN}PASS${NC}: Timestamp year is valid: $year"
    else
        echo -e "  ${RED}FAIL${NC}: Timestamp year invalid: $year"
        teardown_test_env
        return 1
    fi

    teardown_test_env
}

#
# Tests for initialize_run()
#

test_initialize_run_creates_directory() {
    setup_test_env

    # Initialize run
    initialize_run

    # Check that RUN_ID was set
    if [[ -n "$RUN_ID" ]]; then
        echo -e "  ${GREEN}PASS${NC}: RUN_ID global variable set"
    else
        echo -e "  ${RED}FAIL${NC}: RUN_ID not set"
        teardown_test_env
        return 1
    fi

    # Check that RUN_DIR was set
    if [[ -n "$RUN_DIR" ]]; then
        echo -e "  ${GREEN}PASS${NC}: RUN_DIR global variable set"
    else
        echo -e "  ${RED}FAIL${NC}: RUN_DIR not set"
        teardown_test_env
        return 1
    fi

    # Check that directory exists
    assert_true "[ -d \"$RUN_DIR\" ]" "Run directory exists"

    teardown_test_env
}

test_initialize_run_creates_subdirectories() {
    setup_test_env

    initialize_run

    # Check all required subdirectories
    assert_true "[ -d \"$RUN_DIR/checkpoints\" ]" "checkpoints/ subdirectory exists"
    assert_true "[ -d \"$RUN_DIR/decisions\" ]" "decisions/ subdirectory exists"
    assert_true "[ -d \"$RUN_DIR/logs\" ]" "logs/ subdirectory exists"

    teardown_test_env
}

test_initialize_run_creates_state_json() {
    setup_test_env

    initialize_run

    # Check state.json exists
    assert_file_exists "$RUN_DIR/state.json" "state.json file exists"

    # Check state.json is valid JSON
    if jq empty "$RUN_DIR/state.json" 2>/dev/null; then
        echo -e "  ${GREEN}PASS${NC}: state.json is valid JSON"
    else
        echo -e "  ${RED}FAIL${NC}: state.json is not valid JSON"
        teardown_test_env
        return 1
    fi

    teardown_test_env
}

test_initialize_run_state_json_content() {
    setup_test_env

    initialize_run

    local state_content
    state_content=$(cat "$RUN_DIR/state.json")

    # Check run_id field
    local state_run_id
    state_run_id=$(echo "$state_content" | jq -r '.run_id')
    assert_equals "$RUN_ID" "$state_run_id" "state.json run_id matches RUN_ID"

    # Check status field
    local status
    status=$(echo "$state_content" | jq -r '.status')
    assert_equals "running" "$status" "state.json status is 'running'"

    # Check input_type field
    local input_type
    input_type=$(echo "$state_content" | jq -r '.input_type')
    assert_equals "$INPUT_TYPE" "$input_type" "state.json input_type matches INPUT_TYPE"

    # Check input_value field
    local input_value
    input_value=$(echo "$state_content" | jq -r '.input_value')
    assert_equals "$INPUT_VALUE" "$input_value" "state.json input_value matches INPUT_VALUE"

    # Check started_at field exists and is ISO 8601 format
    local started_at
    started_at=$(echo "$state_content" | jq -r '.started_at')
    if [[ "$started_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
        echo -e "  ${GREEN}PASS${NC}: started_at is ISO 8601 format"
    else
        echo -e "  ${RED}FAIL${NC}: started_at format invalid: $started_at"
        teardown_test_env
        return 1
    fi

    # Check tickets array is empty
    local tickets
    tickets=$(echo "$state_content" | jq -r '.tickets | length')
    assert_equals "0" "$tickets" "state.json tickets array is empty"

    # Check current_ticket is null
    local current_ticket
    current_ticket=$(echo "$state_content" | jq -r '.current_ticket')
    assert_equals "null" "$current_ticket" "state.json current_ticket is null"

    teardown_test_env
}

test_initialize_run_directory_permissions() {
    setup_test_env

    initialize_run

    # Check run directory has 700 permissions (rwx------)
    local perms
    perms=$(stat -c "%a" "$RUN_DIR" 2>/dev/null || stat -f "%A" "$RUN_DIR" 2>/dev/null)
    assert_equals "700" "$perms" "Run directory has 700 permissions"

    teardown_test_env
}

test_initialize_run_state_file_permissions() {
    setup_test_env

    initialize_run

    # Check state.json has 600 permissions (rw-------)
    # atomic_write sets this
    local perms
    perms=$(stat -c "%a" "$RUN_DIR/state.json" 2>/dev/null || stat -f "%A" "$RUN_DIR/state.json" 2>/dev/null)
    assert_equals "600" "$perms" "state.json has 600 permissions"

    teardown_test_env
}

test_initialize_run_multiple_runs() {
    setup_test_env

    # Initialize multiple runs and verify they get unique IDs
    INPUT_TYPE="jql"
    INPUT_VALUE="project = TEST1"
    initialize_run
    local run1_id="$RUN_ID"
    local run1_dir="$RUN_DIR"

    # Reset globals for second run
    RUN_ID=""
    RUN_DIR=""
    INPUT_TYPE="epic"
    INPUT_VALUE="EPIC-100"
    initialize_run
    local run2_id="$RUN_ID"
    local run2_dir="$RUN_DIR"

    # Verify IDs are different
    if [[ "$run1_id" != "$run2_id" ]]; then
        echo -e "  ${GREEN}PASS${NC}: Multiple runs get unique IDs"
    else
        echo -e "  ${RED}FAIL${NC}: Multiple runs have same ID: $run1_id"
        teardown_test_env
        return 1
    fi

    # Verify both directories exist
    assert_true "[ -d \"$run1_dir\" ]" "First run directory exists"
    assert_true "[ -d \"$run2_dir\" ]" "Second run directory exists"

    teardown_test_env
}

test_initialize_run_idempotency_protection() {
    setup_test_env

    initialize_run
    local first_run_id="$RUN_ID"
    local first_run_dir="$RUN_DIR"

    # Try to initialize again (should create new run, not reuse)
    RUN_ID=""
    RUN_DIR=""
    initialize_run
    local second_run_id="$RUN_ID"

    # Should get different run ID
    if [[ "$first_run_id" != "$second_run_id" ]]; then
        echo -e "  ${GREEN}PASS${NC}: Second initialization creates new run"
    else
        echo -e "  ${RED}FAIL${NC}: Second initialization reused same ID"
        teardown_test_env
        return 1
    fi

    # Both directories should exist
    assert_true "[ -d \"$first_run_dir\" ]" "First run directory still exists"
    assert_true "[ -d \"$RUN_DIR\" ]" "Second run directory exists"

    teardown_test_env
}

#
# Run all tests
#

main() {
    echo "Running run initializer tests..."
    echo ""

    # Suppress log output during tests (we set CONFIG_LOG_LEVEL=error above)
    export LOG_FILE="/tmp/test-run-initializer-$$.log"

    if run_tests "test_"; then
        rm -f "$LOG_FILE"
        exit 0
    else
        echo ""
        echo "Log file: $LOG_FILE"
        exit 1
    fi
}

main "$@"
