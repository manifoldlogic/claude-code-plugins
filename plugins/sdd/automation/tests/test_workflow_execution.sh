#!/usr/bin/env bash
#
# Test Suite: Core Workflow Execution Loop
# Tests: run_workflow, has_pending_tickets, select_next_ticket, execute_pipeline, generate_report
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test-harness.sh
source "${SCRIPT_DIR}/test-harness.sh"

# Set up test environment
TEST_ROOT="/tmp/sdd-test-workflow-$$"
export SDD_ROOT_DIR="$TEST_ROOT"
export CONFIG_LOG_LEVEL="debug"
export LOG_FILE="${TEST_ROOT}/test.log"

# IMPORTANT: Override SCRIPT_DIR to point to test root so load_modules
# uses test stubs instead of real modules
ORCHESTRATOR_REAL_DIR="${SCRIPT_DIR}/../"

# Source the orchestrator (in test mode - won't execute main)
# We need to override SCRIPT_DIR before sourcing
(
    # Read orchestrator and modify SCRIPT_DIR line
    SCRIPT_DIR_OVERRIDE="SCRIPT_DIR=\"$TEST_ROOT/automation\""

    # Source common.sh first with real path
    source "${ORCHESTRATOR_REAL_DIR}/lib/common.sh"

    # Now eval the orchestrator with our override
    # We skip the first few lines that set SCRIPT_DIR and source common.sh
    eval "$(tail -n +24 "${ORCHESTRATOR_REAL_DIR}/orchestrator.sh" | sed "s|^SCRIPT_DIR=.*|${SCRIPT_DIR_OVERRIDE}|")"
) || true

# Actually, better approach: just redefine load_modules to use test modules
# Source the orchestrator normally first
source "${SCRIPT_DIR}/../orchestrator.sh"

# Then override load_modules to use TEST_ROOT
load_modules() {
    local modules_dir="${TEST_ROOT}/automation/modules"

    log_info "Loading test automation modules from: $modules_dir"

    # Module 1: State Manager
    if ! source "${modules_dir}/state-manager.sh"; then
        log_error "Failed to source state-manager"
        return 1
    fi
    if ! validate_module_interface "state-manager" "save_state" "load_state" "save_checkpoint" "restore_checkpoint"; then
        return 1
    fi

    # Module 2: Recovery Handler
    if ! source "${modules_dir}/recovery-handler.sh"; then
        log_error "Failed to source recovery-handler"
        return 1
    fi
    if ! validate_module_interface "recovery-handler" "retry_with_backoff" "handle_error"; then
        return 1
    fi

    # Module 3: JIRA Adapter
    if ! source "${modules_dir}/jira-adapter.sh"; then
        log_error "Failed to source jira-adapter"
        return 1
    fi
    if ! validate_module_interface "jira-adapter" "fetch_tickets" "get_ticket_details"; then
        return 1
    fi

    # Module 4: Decision Engine
    if ! source "${modules_dir}/decision-engine.sh"; then
        log_error "Failed to source decision-engine"
        return 1
    fi
    if ! validate_module_interface "decision-engine" "make_decision"; then
        return 1
    fi

    # Module 5: SDD Executor
    if ! source "${modules_dir}/sdd-executor.sh"; then
        log_error "Failed to source sdd-executor"
        return 1
    fi
    if ! validate_module_interface "sdd-executor" "execute_stage"; then
        return 1
    fi

    log_info "All test modules loaded successfully"
    return 0
}

#
# Setup and Teardown
#

setup_test_environment() {
    # Create test directory structure
    mkdir -p "$TEST_ROOT"
    mkdir -p "$TEST_ROOT/automation/modules"
    mkdir -p "$TEST_ROOT/automation/config"
    mkdir -p "$TEST_ROOT/automation/runs"

    # Create minimal config file
    cat > "$TEST_ROOT/automation/config/default.json" <<'EOF'
{
  "sdd_root": "/tmp/sdd-test-workflow",
  "retry": {
    "max_attempts": 3,
    "initial_delay_seconds": 1,
    "backoff_multiplier": 2
  },
  "checkpoint": {
    "frequency": "per_ticket",
    "max_checkpoints": 5
  },
  "decision": {
    "risk_tolerance": "moderate",
    "timeout_seconds": 60
  },
  "logging": {
    "level": "debug",
    "format": "structured"
  },
  "tools": {
    "claude_path": "claude",
    "jira_path": "acli",
    "gh_path": "gh"
  }
}
EOF

    # Update config to use actual test root
    sed -i "s|/tmp/sdd-test-workflow|$TEST_ROOT|g" "$TEST_ROOT/automation/config/default.json"

    # Create stub modules
    create_stub_modules
}

create_stub_modules() {
    # State manager stub
    cat > "$TEST_ROOT/automation/modules/state-manager.sh" <<'EOF'
#!/usr/bin/env bash
# STUB: state-manager

save_state() {
    return 0
}

load_state() {
    return 0
}

save_checkpoint() {
    return 0
}

restore_checkpoint() {
    return 0
}
EOF

    # Recovery handler stub
    cat > "$TEST_ROOT/automation/modules/recovery-handler.sh" <<'EOF'
#!/usr/bin/env bash
# STUB: recovery-handler

retry_with_backoff() {
    "$@"
}

handle_error() {
    return 0
}
EOF

    # JIRA adapter stub
    cat > "$TEST_ROOT/automation/modules/jira-adapter.sh" <<'EOFMAIN'
#!/usr/bin/env bash
# STUB: jira-adapter

fetch_tickets() {
    local input_type="${1:-}"
    local input_value="${2:-}"

    cat <<EOFJSON
{
  "success": true,
  "result": {
    "tickets": [
      {"key": "TEST-1", "summary": "Test Ticket 1", "status": "To Do"},
      {"key": "TEST-2", "summary": "Test Ticket 2", "status": "To Do"}
    ],
    "count": 2
  },
  "next_action": "proceed",
  "error": null
}
EOFJSON
}

get_ticket_details() {
    local ticket_key="${1:-}"
    cat <<EOFJSON
{
  "success": true,
  "result": {
    "key": "$ticket_key",
    "summary": "Details for $ticket_key"
  },
  "next_action": "proceed",
  "error": null
}
EOFJSON
}
EOFMAIN

    # Decision engine stub
    cat > "$TEST_ROOT/automation/modules/decision-engine.sh" <<'EOFMAIN'
#!/usr/bin/env bash
# STUB: decision-engine

make_decision() {
    local context="${1:-}"
    local options="${2:-}"

    cat <<EOFJSON
{
  "success": true,
  "result": {
    "decision": "proceed",
    "confidence": 0.8
  },
  "next_action": "proceed",
  "error": null
}
EOFJSON
}
EOFMAIN

    # SDD executor stub
    cat > "$TEST_ROOT/automation/modules/sdd-executor.sh" <<'EOFMAIN'
#!/usr/bin/env bash
# STUB: sdd-executor

execute_stage() {
    local stage_name="${1:-}"
    local ticket="${2:-}"
    local context="${3:-}"

    cat <<EOFJSON
{
  "success": true,
  "result": {
    "stage": "$stage_name",
    "ticket": "$ticket"
  },
  "next_action": "proceed",
  "error": null
}
EOFJSON
}
EOFMAIN

    chmod +x "$TEST_ROOT/automation/modules"/*.sh
}

teardown_test_environment() {
    if [ -d "$TEST_ROOT" ]; then
        rm -rf "$TEST_ROOT"
    fi
}

#
# Test: has_pending_tickets
#

test_has_pending_tickets() {
    # Create a test run directory
    local run_id="test-run-001"
    RUN_DIR="$TEST_ROOT/automation/runs/$run_id"
    mkdir -p "$RUN_DIR"

    # Test 1: No pending tickets (all completed)
    cat > "$RUN_DIR/state.json" <<'EOF'
{
  "tickets": [
    {"key": "TEST-1", "status": "completed"},
    {"key": "TEST-2", "status": "completed"}
  ]
}
EOF

    assert_false "has_pending_tickets" "has_pending_tickets returns false when all tickets completed"

    # Test 2: Has pending tickets
    cat > "$RUN_DIR/state.json" <<'EOF'
{
  "tickets": [
    {"key": "TEST-1", "status": "pending"},
    {"key": "TEST-2", "status": "completed"}
  ]
}
EOF

    assert_true "has_pending_tickets" "has_pending_tickets returns true for pending tickets"

    # Test 3: Mixed status including in_progress
    cat > "$RUN_DIR/state.json" <<'EOF'
{
  "tickets": [
    {"key": "TEST-1", "status": "in_progress"},
    {"key": "TEST-2", "status": "completed"}
  ]
}
EOF

    assert_true "has_pending_tickets" "has_pending_tickets returns true for in_progress tickets"
}

#
# Test: select_next_ticket
#

test_select_next_ticket() {
    # Create a test run directory
    local run_id="test-run-002"
    RUN_DIR="$TEST_ROOT/automation/runs/$run_id"
    mkdir -p "$RUN_DIR"

    # Test 1: Select first pending ticket
    cat > "$RUN_DIR/state.json" <<'EOF'
{
  "tickets": [
    {"key": "TEST-1", "status": "pending"},
    {"key": "TEST-2", "status": "pending"}
  ]
}
EOF

    local ticket
    ticket=$(select_next_ticket)
    assert_equals "TEST-1" "$ticket" "select_next_ticket returns first pending ticket"

    # Test 2: Select in_progress ticket
    cat > "$RUN_DIR/state.json" <<'EOF'
{
  "tickets": [
    {"key": "TEST-1", "status": "completed"},
    {"key": "TEST-2", "status": "in_progress"}
  ]
}
EOF

    ticket=$(select_next_ticket)
    assert_equals "TEST-2" "$ticket" "select_next_ticket returns in_progress ticket"

    # Test 3: No pending tickets
    cat > "$RUN_DIR/state.json" <<'EOF'
{
  "tickets": [
    {"key": "TEST-1", "status": "completed"},
    {"key": "TEST-2", "status": "failed"}
  ]
}
EOF

    assert_false "select_next_ticket &>/dev/null" "select_next_ticket fails when no pending tickets"
}

#
# Test: execute_pipeline
#

test_execute_pipeline() {
    # Create a test run directory
    local run_id="test-run-003"
    RUN_DIR="$TEST_ROOT/automation/runs/$run_id"
    mkdir -p "$RUN_DIR"

    # Initialize state
    cat > "$RUN_DIR/state.json" <<'EOF'
{
  "tickets": [
    {"key": "TEST-1", "status": "pending", "completed_stages": [], "error": null}
  ],
  "current_ticket": null
}
EOF

    # Load modules (needed for execute_stage)
    load_modules

    # Set DRY_RUN to false for actual execution
    DRY_RUN=false

    # Execute pipeline
    assert_true "execute_pipeline TEST-1" "execute_pipeline completes successfully"

    # Verify ticket status updated to completed
    local state_content
    state_content=$(cat "$RUN_DIR/state.json")
    local status
    status=$(echo "$state_content" | jq -r '.tickets[0].status')
    assert_equals "completed" "$status" "Ticket status updated to completed"

    # Verify all stages completed
    local stages_count
    stages_count=$(echo "$state_content" | jq '.tickets[0].completed_stages | length')
    assert_equals "5" "$stages_count" "All 5 stages completed"
}

#
# Test: generate_report
#

test_generate_report() {
    # Create a test run directory
    local run_id="test-run-004"
    RUN_DIR="$TEST_ROOT/automation/runs/$run_id"
    mkdir -p "$RUN_DIR"

    # Initialize state with completed and failed tickets
    cat > "$RUN_DIR/state.json" <<'EOF'
{
  "run_id": "test-run-004",
  "input_type": "tickets",
  "input_value": "TEST-1,TEST-2,TEST-3",
  "started_at": "2025-12-14T10:00:00-05:00",
  "tickets": [
    {"key": "TEST-1", "status": "completed"},
    {"key": "TEST-2", "status": "completed"},
    {"key": "TEST-3", "status": "failed", "error": "Stage plan failed"}
  ]
}
EOF

    # Generate report
    assert_true "generate_report" "generate_report completes successfully"

    # Verify report file created
    assert_file_exists "$RUN_DIR/report.txt" "Report file created"

    # Verify report contains expected content
    local report
    report=$(cat "$RUN_DIR/report.txt")

    assert_contains "$report" "TEST-1" "Report contains TEST-1"
    assert_contains "$report" "Completed: 2" "Report shows 2 completed tickets"
    assert_contains "$report" "Failed: 1" "Report shows 1 failed ticket"
}

#
# Test: run_workflow (dry run)
#

test_run_workflow_dry_run() {
    # Set up global variables
    INPUT_TYPE="tickets"
    INPUT_VALUE="TEST-1,TEST-2"
    DRY_RUN=true

    # Create run directory
    local run_id="test-run-005"
    RUN_ID="$run_id"
    RUN_DIR="$TEST_ROOT/automation/runs/$run_id"
    mkdir -p "$RUN_DIR/checkpoints" "$RUN_DIR/decisions" "$RUN_DIR/logs"

    # Initialize state
    cat > "$RUN_DIR/state.json" <<'EOF'
{
  "run_id": "test-run-005",
  "status": "running",
  "input_type": "tickets",
  "input_value": "TEST-1,TEST-2",
  "started_at": "2025-12-14T10:00:00-05:00",
  "tickets": [],
  "current_ticket": null
}
EOF

    # Load modules and config
    load_modules
    load_config

    # Run workflow in dry-run mode
    assert_true "run_workflow" "run_workflow completes in dry-run mode"

    # Verify report generated
    assert_file_exists "$RUN_DIR/report.txt" "Report generated in dry-run mode"
}

#
# Test: run_workflow (full execution)
#

test_run_workflow_full() {
    # Set up global variables
    INPUT_TYPE="jql"
    INPUT_VALUE="project = TEST"
    DRY_RUN=false

    # Create run directory
    local run_id="test-run-006"
    RUN_ID="$run_id"
    RUN_DIR="$TEST_ROOT/automation/runs/$run_id"
    mkdir -p "$RUN_DIR/checkpoints" "$RUN_DIR/decisions" "$RUN_DIR/logs"

    # Initialize state
    cat > "$RUN_DIR/state.json" <<'EOF'
{
  "run_id": "test-run-006",
  "status": "running",
  "input_type": "jql",
  "input_value": "project = TEST",
  "started_at": "2025-12-14T10:00:00-05:00",
  "tickets": [],
  "current_ticket": null
}
EOF

    # Load modules and config
    load_modules
    load_config

    # Run workflow
    assert_true "run_workflow" "run_workflow completes successfully"

    # Verify state updated
    local state_content
    state_content=$(cat "$RUN_DIR/state.json")

    # Verify tickets were processed
    local ticket_count
    ticket_count=$(echo "$state_content" | jq '.tickets | length')
    assert_equals "2" "$ticket_count" "Two tickets processed (from stub)"

    # Verify final status
    local final_status
    final_status=$(echo "$state_content" | jq -r '.status')
    assert_equals "completed" "$final_status" "Workflow status is completed"

    # Verify report exists
    assert_file_exists "$RUN_DIR/report.txt" "Final report generated"
}

#
# Run all tests
#

main() {
    echo "========================================"
    echo "Test Suite: Core Workflow Execution"
    echo "========================================"
    echo ""

    setup_test_environment

    # Use the test harness run_tests function
    run_tests "test_"

    teardown_test_environment
}

main "$@"
