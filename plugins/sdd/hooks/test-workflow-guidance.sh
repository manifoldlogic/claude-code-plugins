#!/bin/bash
# test-workflow-guidance.sh - Test suite for workflow-guidance.py Stop hook
#
# This script runs comprehensive integration tests for the SDD workflow guidance
# Stop hook. It tests various scenarios including:
# - No SDD context (generic conversations)
# - Planning workflow detection
# - Implementation workflow detection
# - Loop prevention (stop_hook_active)
# - Error handling (missing files, malformed data)
# - Environment variable controls
# - Gate functionality (AUTOGATE)
# - Performance benchmarks
#
# Usage:
#   ./test-workflow-guidance.sh           # Run all tests
#   ./test-workflow-guidance.sh -v        # Verbose output
#   ./test-workflow-guidance.sh --help    # Show help
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed

set -e  # Exit on first failure

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/workflow-guidance.py"
FIXTURES="$SCRIPT_DIR/fixtures"
TEMP_DIR=""
TEST_SDD_ROOT=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Verbose mode
VERBOSE=false

# ============================================================================
# Helper Functions
# ============================================================================

usage() {
    echo "Usage: $0 [-v|--verbose] [--help]"
    echo ""
    echo "Options:"
    echo "  -v, --verbose  Show detailed output for each test"
    echo "  --help         Show this help message"
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Setup temporary directory for test inputs
setup() {
    TEMP_DIR=$(mktemp -d)
    TEST_SDD_ROOT=$(mktemp -d)
    if [ "$VERBOSE" = true ]; then
        echo "Created temp directory: $TEMP_DIR"
        echo "Created test SDD root: $TEST_SDD_ROOT"
    fi
}

# Cleanup temporary directory
cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        if [ "$VERBOSE" = true ]; then
            echo "Cleaned up temp directory: $TEMP_DIR"
        fi
    fi
    if [ -n "$TEST_SDD_ROOT" ] && [ -d "$TEST_SDD_ROOT" ]; then
        rm -rf "$TEST_SDD_ROOT"
        if [ "$VERBOSE" = true ]; then
            echo "Cleaned up test SDD root: $TEST_SDD_ROOT"
        fi
    fi
}

# Generate input JSON with correct transcript path
generate_input() {
    local transcript_file="$1"
    local stop_hook_active="${2:-false}"
    local session_id="${3:-test-session-123}"

    local transcript_path=""
    if [ -n "$transcript_file" ]; then
        transcript_path="$FIXTURES/$transcript_file"
    fi

    cat > "$TEMP_DIR/input.json" << EOF
{
  "session_id": "$session_id",
  "transcript_path": "$transcript_path",
  "hook_event_name": "Stop",
  "stop_hook_active": $stop_hook_active
}
EOF
}

# Run a single test
# Args: test_name expected_exit [check_output_contains]
run_test() {
    local name="$1"
    local expected_exit="$2"
    local check_output="${3:-}"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: $name ... "

    local actual_exit=0
    local output=""

    # Capture both output and exit code
    output=$(cat "$TEMP_DIR/input.json" | python3 "$HOOK" 2>&1) || actual_exit=$?

    local passed=true
    local failure_reason=""

    # Check exit code
    if [ "$actual_exit" -ne "$expected_exit" ]; then
        passed=false
        failure_reason="expected exit $expected_exit, got $actual_exit"
    fi

    # Check output if specified
    if [ -n "$check_output" ] && [ "$passed" = true ]; then
        if ! echo "$output" | grep -qE "$check_output"; then
            passed=false
            failure_reason="output did not contain '$check_output'"
        fi
    fi

    if [ "$passed" = true ]; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        if [ "$VERBOSE" = true ] && [ -n "$output" ]; then
            echo "  Output: $output"
        fi
    else
        echo -e "${RED}FAIL${NC} ($failure_reason)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        if [ "$VERBOSE" = true ]; then
            echo "  Output: $output"
        fi
    fi
}

# Run a test with environment variable
run_test_with_env() {
    local name="$1"
    local expected_exit="$2"
    local env_var="$3"
    local env_value="$4"
    local check_output="${5:-}"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: $name ... "

    local actual_exit=0
    local output=""

    # Run with environment variable set
    output=$(export "$env_var=$env_value" && cat "$TEMP_DIR/input.json" | python3 "$HOOK" 2>&1) || actual_exit=$?

    local passed=true
    local failure_reason=""

    if [ "$actual_exit" -ne "$expected_exit" ]; then
        passed=false
        failure_reason="expected exit $expected_exit, got $actual_exit"
    fi

    # Check output if specified
    if [ -n "$check_output" ] && [ "$passed" = true ]; then
        if ! echo "$output" | grep -qE "$check_output"; then
            passed=false
            failure_reason="output did not contain '$check_output'"
        fi
    fi

    if [ "$passed" = true ]; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC} ($failure_reason)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        if [ "$VERBOSE" = true ]; then
            echo "  Output: $output"
        fi
    fi
}

# Run a test with raw stdin input (for invalid JSON tests)
run_test_raw_input() {
    local name="$1"
    local expected_exit="$2"
    local raw_input="$3"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: $name ... "

    local actual_exit=0
    local output=""

    output=$(echo "$raw_input" | python3 "$HOOK" 2>&1) || actual_exit=$?

    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC} (expected exit $expected_exit, got $actual_exit)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Run Python unit test helper
run_python_unit_test() {
    local name="$1"
    local test_code="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Unit Test: $name ... "

    local result
    if python3 -c "$test_code" 2>/dev/null; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Setup SDD test directory with gates
setup_sdd_gates() {
    local ticket_name="$1"
    local gate_config="$2"

    local ticket_dir="$TEST_SDD_ROOT/tickets/$ticket_name"
    mkdir -p "$ticket_dir"

    if [ -n "$gate_config" ]; then
        cp "$FIXTURES/configs/$gate_config" "$ticket_dir/.autogate.json"
    fi
}

# ============================================================================
# Prerequisite Checks
# ============================================================================

echo "================================"
echo "SDD Workflow Guidance Test Suite"
echo "================================"
echo ""

# Check Python is available
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}ERROR: python3 not found${NC}"
    exit 1
fi

# Check hook script exists
if [ ! -f "$HOOK" ]; then
    echo -e "${RED}ERROR: Hook script not found: $HOOK${NC}"
    exit 1
fi

# Check fixtures directory exists
if [ ! -d "$FIXTURES" ]; then
    echo -e "${RED}ERROR: Fixtures directory not found: $FIXTURES${NC}"
    exit 1
fi

echo "Hook: $HOOK"
echo "Fixtures: $FIXTURES"
echo ""

# ============================================================================
# Setup
# ============================================================================

setup
trap cleanup EXIT

# ============================================================================
# SECTION 1: Workflow Guidance Regression Tests (CRITICAL)
# These tests ensure existing functionality still works
# ============================================================================

echo -e "${BLUE}SECTION 1: Workflow Guidance Regression Tests${NC}"
echo "----------------------------------------------"

# Test 1.1: No SDD context - should exit 0, no guidance
generate_input "transcript-no-sdd.jsonl" false
run_test "No SDD context - exits 0" 0

# Test 1.2: Planning workflow - should exit 0 with guidance
generate_input "transcript-planning.jsonl" false
run_test "Planning workflow - exits 0 with guidance" 0 "planning"

# Test 1.3: Implementation workflow - should exit 0 with guidance
generate_input "transcript-implementation.jsonl" false
run_test "Implementation workflow - exits 0 with guidance" 0 "implementation"

# Test 1.4: stop_hook_active=true - should exit 0 immediately (loop prevention)
generate_input "transcript-planning.jsonl" true
run_test "stop_hook_active=true - exits 0 immediately" 0

# Test 1.5: Invalid transcript path - should exit 0 gracefully
cat > "$TEMP_DIR/input.json" << EOF
{
  "session_id": "test-session-123",
  "transcript_path": "/nonexistent/path/transcript.jsonl",
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
EOF
run_test "Invalid transcript path - exits 0 gracefully" 0

# Test 1.6: Empty transcript - should exit 0
generate_input "transcript-empty.jsonl" false
run_test "Empty transcript - exits 0" 0

# Test 1.7: Malformed transcript - should exit 0 gracefully (valid lines parsed)
generate_input "transcript-malformed.jsonl" false
run_test "Malformed transcript - exits 0 gracefully" 0

# Test 1.8: Missing transcript_path field - should exit 0
cat > "$TEMP_DIR/input.json" << EOF
{
  "session_id": "test-session-123",
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
EOF
run_test "Missing transcript_path - exits 0" 0

# Test 1.9: Invalid JSON input - should exit 0 (fail-safe)
run_test_raw_input "Invalid JSON input - exits 0" 0 "this is not json"

# Test 1.10: Empty stdin - should exit 0 (fail-safe)
run_test_raw_input "Empty stdin - exits 0" 0 ""

# Test 1.11: Environment variable SDD_DISABLE_STOP_HOOK - should exit 0 immediately
generate_input "transcript-planning.jsonl" false
run_test_with_env "SDD_DISABLE_STOP_HOOK set - exits 0" 0 "SDD_DISABLE_STOP_HOOK" "1"

# Test 1.12: Verify planning guidance contains expected content
generate_input "transcript-planning.jsonl" false
run_test "Planning guidance mentions review or create-tasks" 0 "sdd:review|sdd:create-tasks"

# Test 1.13: Verify implementation guidance contains expected content
generate_input "transcript-implementation.jsonl" false
run_test "Implementation guidance mentions tests or commit" 0 "test|commit"

# Test 1.14: Null transcript_path - should exit 0
cat > "$TEMP_DIR/input.json" << EOF
{
  "session_id": "test-session-123",
  "transcript_path": null,
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
EOF
run_test "Null transcript_path - exits 0" 0

# Test 1.15: Transcript path with special characters - should handle gracefully
cat > "$TEMP_DIR/input.json" << EOF
{
  "session_id": "test-session-123",
  "transcript_path": "/path/with spaces/and-special~chars!/transcript.jsonl",
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
EOF
run_test "Special characters in path - exits 0" 0

echo ""

# ============================================================================
# SECTION 2: Planning Phase Tracking Tests (4 Phases)
# ============================================================================

echo -e "${BLUE}SECTION 2: Planning Phase Tracking Tests${NC}"
echo "-----------------------------------------"

# Test 2.1: needs_review phase detection
run_python_unit_test "Planning phase 'needs_review' detected correctly" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

# Ticket just created, needs review
entries = [
    {'display': '/sdd:plan-ticket AUTH-123'},
    {'display': 'Creating ticket AUTH_test'},
]
result = module.detect_sdd_context(entries)
assert result['planning_phase'] == 'needs_review', f\"Expected 'needs_review', got {result['planning_phase']}\"
"

# Test 2.2: reviewed phase detection
run_python_unit_test "Planning phase 'reviewed' detected correctly" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

# Review has been run
entries = [
    {'display': '/sdd:plan-ticket AUTH-123'},
    {'display': 'Creating ticket AUTH_test'},
    {'display': '/sdd:review AUTH-123'},
]
result = module.detect_sdd_context(entries)
assert result['planning_phase'] == 'reviewed', f\"Expected 'reviewed', got {result['planning_phase']}\"
assert result['has_review'] == True, 'Expected has_review to be True'
"

# Test 2.3: tasks_created phase detection
run_python_unit_test "Planning phase 'tasks_created' detected correctly" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

# Tasks have been created
entries = [
    {'display': '/sdd:plan-ticket AUTH-123'},
    {'display': '/sdd:review AUTH-123'},
    {'display': '/sdd:create-tasks AUTH-123'},
]
result = module.detect_sdd_context(entries)
assert result['planning_phase'] == 'tasks_created', f\"Expected 'tasks_created', got {result['planning_phase']}\"
assert result['has_create_tasks'] == True, 'Expected has_create_tasks to be True'
"

# Test 2.4: init phase detection
run_python_unit_test "Planning phase 'init' for minimal context" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

# Minimal planning context without specific commands
entries = [
    {'display': 'Working on AUTH-123'},
    {'display': 'Ticket AUTH_test mentioned again'},
]
result = module.detect_sdd_context(entries)
# With only ticket mentions (no specific commands), phase should be init
if result['workflow'] == 'planning':
    assert result['planning_phase'] == 'init', f\"Expected 'init', got {result['planning_phase']}\"
"

echo ""

# ============================================================================
# SECTION 3: Review Enforcement Tests
# ============================================================================

echo -e "${BLUE}SECTION 3: Review Enforcement Tests${NC}"
echo "------------------------------------"

# Test 3.1: Review enforcement suggestion appears after plan-ticket
run_python_unit_test "Review enforcement suggested after plan-ticket" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

# Context shows ticket created but not reviewed
context = {
    'workflow': 'planning',
    'planning_phase': 'needs_review',
    'ticket_id': 'AUTH-123'
}
guidance = module.generate_guidance(context)
assert guidance is not None, 'Expected guidance for needs_review phase'
assert 'review' in guidance.lower(), f'Expected review suggestion in guidance: {guidance}'
"

# Test 3.2: Create-tasks suggestion appears after review
run_python_unit_test "Create-tasks suggested after review" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

# Context shows review complete
context = {
    'workflow': 'planning',
    'planning_phase': 'reviewed',
    'ticket_id': 'AUTH-123'
}
guidance = module.generate_guidance(context)
assert guidance is not None, 'Expected guidance for reviewed phase'
assert 'create-tasks' in guidance.lower() or 'update' in guidance.lower(), f'Expected create-tasks or update suggestion: {guidance}'
"

echo ""

# ============================================================================
# SECTION 4: Ticket ID Detection Tests
# ============================================================================

echo -e "${BLUE}SECTION 4: Ticket ID Detection Tests${NC}"
echo "-------------------------------------"

# Test 4.1: Jira-style ticket ID detection
run_python_unit_test "Jira-style ticket ID (AUTH-123) detected" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

entries = [
    {'display': 'Working on AUTH-123'},
    {'display': 'Ticket AUTH-123 planning'},
]
result = module.detect_sdd_context(entries)
assert result['ticket_id'] == 'AUTH-123', f\"Expected 'AUTH-123', got {result['ticket_id']}\"
"

# Test 4.2: Directory-style ticket ID detection
run_python_unit_test "Directory-style ticket ID (AUTH_test-ticket) detected" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

entries = [
    {'display': 'Working on AUTH_test-ticket'},
    {'display': 'Ticket AUTH_test-ticket created'},
]
result = module.detect_sdd_context(entries)
assert result['ticket_id'] == 'AUTH_test-ticket', f\"Expected 'AUTH_test-ticket', got {result['ticket_id']}\"
"

# Test 4.3: Task ID detection
run_python_unit_test "Task ID (AUTH.1001) detected" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

entries = [
    {'display': 'Working on AUTH.1001'},
    {'display': 'Task AUTH.1001 in progress'},
]
result = module.detect_sdd_context(entries)
assert result['task_id'] == 'AUTH.1001', f\"Expected 'AUTH.1001', got {result['task_id']}\"
"

echo ""

# ============================================================================
# SECTION 5: SDD Command Detection Tests
# ============================================================================

echo -e "${BLUE}SECTION 5: SDD Command Detection Tests${NC}"
echo "---------------------------------------"

# Test 5.1: /sdd:plan-ticket command detected
run_python_unit_test "/sdd:plan-ticket command detected" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

entries = [
    {'display': '/sdd:plan-ticket AUTH-123 Some feature'},
    {'display': 'Creating ticket AUTH-123...'},
]
result = module.detect_sdd_context(entries)
assert '/sdd:plan-ticket' in result['indicators'], 'Expected /sdd:plan-ticket in indicators'
assert result['workflow'] == 'planning', f\"Expected planning workflow, got {result['workflow']}\"
"

# Test 5.2: /sdd:do-task command detected
run_python_unit_test "/sdd:do-task command detected" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

entries = [
    {'display': '/sdd:do-task AUTH.1001'},
    {'display': 'Starting task...'},
]
result = module.detect_sdd_context(entries)
assert '/sdd:do-task' in result['indicators'], 'Expected /sdd:do-task in indicators'
assert result['workflow'] == 'implementation', f\"Expected implementation workflow, got {result['workflow']}\"
"

# Test 5.3: /sdd:review command detected
run_python_unit_test "/sdd:review command detected and tracked" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

entries = [
    {'display': '/sdd:plan-ticket AUTH-123'},
    {'display': '/sdd:review AUTH-123'},
]
result = module.detect_sdd_context(entries)
assert result['has_review'] == True, 'Expected has_review to be True'
"

# Test 5.4: /sdd:create-tasks command detected
run_python_unit_test "/sdd:create-tasks command detected and tracked" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

entries = [
    {'display': '/sdd:plan-ticket AUTH-123'},
    {'display': '/sdd:review AUTH-123'},
    {'display': '/sdd:create-tasks AUTH-123'},
]
result = module.detect_sdd_context(entries)
assert result['has_create_tasks'] == True, 'Expected has_create_tasks to be True'
"

echo ""

# ============================================================================
# SECTION 6: Gate Configuration Parsing Tests
# ============================================================================

echo -e "${BLUE}SECTION 6: Gate Configuration Parsing Tests${NC}"
echo "--------------------------------------------"

# Test 6.1: Valid gated config (ready: false)
run_python_unit_test "Parse gate config - ready: false" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

config = module.parse_autogate_config('{\"ready\": false}')
assert config['ready'] == False, f\"Expected ready=False, got {config['ready']}\"
assert config['stop_at_phase'] is None, f\"Expected stop_at_phase=None, got {config['stop_at_phase']}\"
"

# Test 6.2: Valid ready config (ready: true)
run_python_unit_test "Parse gate config - ready: true" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

config = module.parse_autogate_config('{\"ready\": true}')
assert config['ready'] == True, f\"Expected ready=True, got {config['ready']}\"
"

# Test 6.3: Phase gate config
run_python_unit_test "Parse gate config - stop_at_phase: 1" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

config = module.parse_autogate_config('{\"ready\": true, \"stop_at_phase\": 1}')
assert config['ready'] == True, f\"Expected ready=True, got {config['ready']}\"
assert config['stop_at_phase'] == 1, f\"Expected stop_at_phase=1, got {config['stop_at_phase']}\"
"

# Test 6.4: Invalid JSON config (fail-safe to ready)
run_python_unit_test "Parse gate config - invalid JSON defaults to ready" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

config = module.parse_autogate_config('{this is not valid json')
assert config['ready'] == True, f\"Invalid JSON should default to ready=True, got {config['ready']}\"
"

# Test 6.5: Empty config (fail-safe to ready)
run_python_unit_test "Parse gate config - empty object defaults to ready" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

config = module.parse_autogate_config('{}')
assert config['ready'] == True, f\"Empty config should default to ready=True, got {config['ready']}\"
"

# Test 6.6: Invalid type for ready (fail-safe)
run_python_unit_test "Parse gate config - invalid ready type defaults to true" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

config = module.parse_autogate_config('{\"ready\": \"not a bool\"}')
assert config['ready'] == True, f\"Invalid ready type should default to True, got {config['ready']}\"
"

# Test 6.7: Invalid type for stop_at_phase (fail-safe)
run_python_unit_test "Parse gate config - invalid stop_at_phase type defaults to None" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

config = module.parse_autogate_config('{\"ready\": true, \"stop_at_phase\": \"not an int\"}')
assert config['stop_at_phase'] is None, f\"Invalid stop_at_phase type should default to None, got {config['stop_at_phase']}\"
"

echo ""

# ============================================================================
# SECTION 7: Gate Evaluation Logic Tests
# ============================================================================

echo -e "${BLUE}SECTION 7: Gate Evaluation Logic Tests${NC}"
echo "---------------------------------------"

# Test 7.1: Gate blocks when ready=false
run_python_unit_test "Gate blocks when ready=false" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

gates = {'AUTH_test-ticket': {'ready': False, 'stop_at_phase': None}}
context = {'ticket_id': 'AUTH_test-ticket', 'workflow': 'planning'}
result = module.evaluate_gates(gates, context)
assert result['blocked'] == True, f\"Expected blocked=True, got {result['blocked']}\"
assert 'AUTOGATE' in result['message'], 'Expected AUTOGATE in block message'
"

# Test 7.2: Gate allows when ready=true
run_python_unit_test "Gate allows when ready=true" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

gates = {'AUTH_test-ticket': {'ready': True, 'stop_at_phase': None}}
context = {'ticket_id': 'AUTH_test-ticket', 'workflow': 'planning'}
result = module.evaluate_gates(gates, context)
assert result['blocked'] == False, f\"Expected blocked=False, got {result['blocked']}\"
"

# Test 7.3: No gate config for ticket allows work
run_python_unit_test "No gate config for ticket allows work" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

gates = {}  # No gates configured
context = {'ticket_id': 'AUTH_test-ticket', 'workflow': 'planning'}
result = module.evaluate_gates(gates, context)
assert result['blocked'] == False, f\"Expected blocked=False for missing gate, got {result['blocked']}\"
"

# Test 7.4: No active ticket allows work
run_python_unit_test "No active ticket in context allows work" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

gates = {'AUTH_test-ticket': {'ready': False, 'stop_at_phase': None}}
context = {'ticket_id': None, 'workflow': 'none'}  # No active ticket
result = module.evaluate_gates(gates, context)
assert result['blocked'] == False, f\"Expected blocked=False for no active ticket, got {result['blocked']}\"
"

echo ""

# ============================================================================
# SECTION 8: Phase Gate Logic Tests
# ============================================================================

echo -e "${BLUE}SECTION 8: Phase Gate Logic Tests${NC}"
echo "----------------------------------"

# Test 8.1: Phase gate blocks when current phase exceeds stop_at_phase
run_python_unit_test "Phase gate blocks when phase > stop_at_phase" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

# stop_at_phase=1 means block after phase 1 (review)
gates = {'AUTH_test-ticket': {'ready': True, 'stop_at_phase': 1}}
# Phase 2 = reviewed (past phase 1)
context = {'ticket_id': 'AUTH_test-ticket', 'workflow': 'planning', 'planning_phase': 'reviewed'}
result = module.evaluate_gates(gates, context)
assert result['blocked'] == True, f\"Expected blocked=True when phase > stop_at_phase, got {result['blocked']}\"
assert 'Phase 1 complete' in result['message'], f'Expected phase complete message: {result[\"message\"]}'
"

# Test 8.2: Phase gate allows when current phase equals stop_at_phase
run_python_unit_test "Phase gate allows when phase <= stop_at_phase" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

# stop_at_phase=1, currently at phase 1
gates = {'AUTH_test-ticket': {'ready': True, 'stop_at_phase': 1}}
# Phase 1 = needs_review (still at phase 1)
context = {'ticket_id': 'AUTH_test-ticket', 'workflow': 'planning', 'planning_phase': 'needs_review'}
result = module.evaluate_gates(gates, context)
assert result['blocked'] == False, f\"Expected blocked=False when at stop_at_phase, got {result['blocked']}\"
"

# Test 8.3: get_current_phase_number returns correct values
run_python_unit_test "get_current_phase_number maps phases correctly" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

# Phase 1: init or needs_review
assert module.get_current_phase_number({'workflow': 'planning', 'planning_phase': 'init'}) == 1
assert module.get_current_phase_number({'workflow': 'planning', 'planning_phase': 'needs_review'}) == 1

# Phase 2: reviewed
assert module.get_current_phase_number({'workflow': 'planning', 'planning_phase': 'reviewed'}) == 2

# Phase 3: tasks_created
assert module.get_current_phase_number({'workflow': 'planning', 'planning_phase': 'tasks_created'}) == 3

# Phase 4: implementation or verification
assert module.get_current_phase_number({'workflow': 'implementation'}) == 4
assert module.get_current_phase_number({'workflow': 'verification'}) == 4

# None for no workflow
assert module.get_current_phase_number({'workflow': 'none'}) is None
"

echo ""

# ============================================================================
# SECTION 9: AUTOGATE_BYPASS Functionality Tests
# ============================================================================

echo -e "${BLUE}SECTION 9: AUTOGATE_BYPASS Functionality Tests${NC}"
echo "-----------------------------------------------"

# Test 9.1: AUTOGATE_BYPASS=true bypasses all gate checks
# Setup a gated ticket
setup_sdd_gates "GATED_test-ticket" "gated.json"
generate_input "transcript-gated-ticket.jsonl" false
run_test_with_env "AUTOGATE_BYPASS bypasses gate block" 0 "AUTOGATE_BYPASS" "true" ""

# Test 9.2: Without bypass, gate should block (needs SDD_ROOT_DIR set)
# This is tested in integration section

echo ""

# ============================================================================
# SECTION 10: Edge Cases and Error Handling Tests
# ============================================================================

echo -e "${BLUE}SECTION 10: Edge Cases and Error Handling Tests${NC}"
echo "------------------------------------------------"

# Test 10.1: Missing SDD_ROOT_DIR doesn't break gate scanning
run_python_unit_test "scan_autogate_configs handles missing SDD_ROOT_DIR" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

# Empty string should return empty dict
result = module.scan_autogate_configs('')
assert result == {}, f'Expected empty dict for empty SDD root, got {result}'

# None should return empty dict
result = module.scan_autogate_configs(None)
assert result == {}, f'Expected empty dict for None SDD root, got {result}'
"

# Test 10.2: Invalid directory doesn't break gate scanning
run_python_unit_test "scan_autogate_configs handles invalid directory" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

result = module.scan_autogate_configs('/nonexistent/path/definitely/not/real')
assert result == {}, f'Expected empty dict for nonexistent path, got {result}'
"

# Test 10.3: Unicode in ticket names handled correctly
run_python_unit_test "Unicode in ticket names handled correctly" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

entries = [
    {'display': 'Working on AUTH-123'},
    {'display': 'Feature with unicode: caf\u00e9'},
]
result = module.detect_sdd_context(entries)
# Should not crash, ticket_id should still be detected
assert result['ticket_id'] == 'AUTH-123', f\"Expected 'AUTH-123', got {result['ticket_id']}\"
"

# Test 10.4: Very long display text doesn't crash
run_python_unit_test "Very long display text handled" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

long_text = 'A' * 100000  # 100KB of text
entries = [
    {'display': f'/sdd:plan-ticket AUTH-123 {long_text}'},
    {'display': 'Working on AUTH-123'},
]
result = module.detect_sdd_context(entries)
assert result['ticket_id'] == 'AUTH-123', 'Should still detect ticket ID in long text'
"

# Test 10.5: Empty display field handled
run_python_unit_test "Empty display field handled gracefully" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

entries = [
    {'display': ''},
    {'display': None},
    {},
    {'display': '/sdd:plan-ticket AUTH-123'},
    {'display': 'AUTH-123'},
]
result = module.detect_sdd_context(entries)
# Should not crash and should still detect valid entries
assert 'AUTH-123' in result['indicators'], 'Should find AUTH-123 in valid entries'
"

# Test 10.6: gate_result structure is always valid
run_python_unit_test "evaluate_gates always returns valid structure" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

# Test with empty inputs
result = module.evaluate_gates({}, {})
assert 'blocked' in result, 'Result must have blocked field'
assert 'message' in result, 'Result must have message field'
assert isinstance(result['blocked'], bool), 'blocked must be bool'
assert isinstance(result['message'], str), 'message must be string'
"

echo ""

# ============================================================================
# SECTION 11: Integration Tests - Gate + Workflow Guidance
# ============================================================================

echo -e "${BLUE}SECTION 11: Integration Tests - Gate + Workflow Guidance${NC}"
echo "---------------------------------------------------------"

# Test 11.1: Ready ticket allows workflow guidance to proceed
# Setup ready ticket
setup_sdd_gates "AUTH_test-ready" "ready.json"
generate_input "transcript-planning.jsonl" false

# Create a temp transcript that references the ready ticket
cat > "$TEMP_DIR/transcript-auth-ready.jsonl" << EOF
{"display": "/sdd:plan-ticket AUTH_test-ready", "timestamp": 1700000001000, "sessionId": "test-123"}
{"display": "Working on AUTH_test-ready", "timestamp": 1700000002000, "sessionId": "test-123"}
EOF

cat > "$TEMP_DIR/input.json" << EOF
{
  "session_id": "test-session-123",
  "transcript_path": "$TEMP_DIR/transcript-auth-ready.jsonl",
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
EOF

run_test_with_env "Ready ticket allows workflow guidance" 0 "SDD_ROOT_DIR" "$TEST_SDD_ROOT" "planning"

# Test 11.2: Gated ticket blocks BEFORE workflow guidance (exit 2)
setup_sdd_gates "GATED_blocked-ticket" "gated.json"

cat > "$TEMP_DIR/transcript-gated-blocked.jsonl" << EOF
{"display": "/sdd:plan-ticket GATED_blocked-ticket", "timestamp": 1700000001000, "sessionId": "test-123"}
{"display": "Working on GATED_blocked-ticket", "timestamp": 1700000002000, "sessionId": "test-123"}
EOF

cat > "$TEMP_DIR/input.json" << EOF
{
  "session_id": "test-session-123",
  "transcript_path": "$TEMP_DIR/transcript-gated-blocked.jsonl",
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
EOF

run_test_with_env "Gated ticket blocks with exit 2" 2 "SDD_ROOT_DIR" "$TEST_SDD_ROOT" "AUTOGATE"

# Test 11.3: Gate errors don't prevent workflow guidance
# Setup with invalid gate config
mkdir -p "$TEST_SDD_ROOT/tickets/ERROR_test-ticket"
echo "{this is invalid json" > "$TEST_SDD_ROOT/tickets/ERROR_test-ticket/.autogate.json"

cat > "$TEMP_DIR/transcript-error-ticket.jsonl" << EOF
{"display": "/sdd:plan-ticket ERROR_test-ticket", "timestamp": 1700000001000, "sessionId": "test-123"}
{"display": "Working on ERROR_test-ticket", "timestamp": 1700000002000, "sessionId": "test-123"}
EOF

cat > "$TEMP_DIR/input.json" << EOF
{
  "session_id": "test-session-123",
  "transcript_path": "$TEMP_DIR/transcript-error-ticket.jsonl",
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
EOF

# Invalid gate config should default to ready, so workflow guidance proceeds
run_test_with_env "Gate error allows workflow guidance (fail-safe)" 0 "SDD_ROOT_DIR" "$TEST_SDD_ROOT" "planning"

# Test 11.4: Phase gate triggers after phase complete
setup_sdd_gates "PHASE_gate-test" "phase-gate.json"

cat > "$TEMP_DIR/transcript-phase-gate.jsonl" << EOF
{"display": "/sdd:plan-ticket PHASE_gate-test", "timestamp": 1700000001000, "sessionId": "test-123"}
{"display": "Creating ticket PHASE_gate-test", "timestamp": 1700000002000, "sessionId": "test-123"}
{"display": "/sdd:review PHASE_gate-test", "timestamp": 1700000003000, "sessionId": "test-123"}
{"display": "Review complete for PHASE_gate-test", "timestamp": 1700000004000, "sessionId": "test-123"}
EOF

cat > "$TEMP_DIR/input.json" << EOF
{
  "session_id": "test-session-123",
  "transcript_path": "$TEMP_DIR/transcript-phase-gate.jsonl",
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
EOF

# Phase gate is stop_at_phase=1, and we're now at phase 2 (reviewed), so should block
run_test_with_env "Phase gate blocks after phase complete" 2 "SDD_ROOT_DIR" "$TEST_SDD_ROOT" "AUTOGATE"

echo ""

# ============================================================================
# SECTION 12: scan_autogate_configs Integration Tests
# ============================================================================

echo -e "${BLUE}SECTION 12: Gate Config Scanning Tests${NC}"
echo "---------------------------------------"

# Test 12.1: scan_autogate_configs finds configs in tickets/ directory
run_python_unit_test "scan_autogate_configs finds ticket configs" "
import sys
import os
import tempfile
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

# Create temp structure
with tempfile.TemporaryDirectory() as tmpdir:
    tickets_dir = os.path.join(tmpdir, 'tickets')
    os.makedirs(tickets_dir)

    # Create a ticket with gate config
    ticket_dir = os.path.join(tickets_dir, 'TEST_ticket')
    os.makedirs(ticket_dir)
    with open(os.path.join(ticket_dir, '.autogate.json'), 'w') as f:
        f.write('{\"ready\": false}')

    result = module.scan_autogate_configs(tmpdir)
    assert 'TEST_ticket' in result, f'Expected TEST_ticket in result, got {result}'
    assert result['TEST_ticket']['ready'] == False, f'Expected ready=False'
"

# Test 12.2: scan_autogate_configs finds configs in epics/ directory
run_python_unit_test "scan_autogate_configs finds epic configs" "
import sys
import os
import tempfile
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

# Create temp structure
with tempfile.TemporaryDirectory() as tmpdir:
    epics_dir = os.path.join(tmpdir, 'epics')
    os.makedirs(epics_dir)

    # Create an epic with gate config
    epic_dir = os.path.join(epics_dir, 'EPIC_test')
    os.makedirs(epic_dir)
    with open(os.path.join(epic_dir, '.autogate.json'), 'w') as f:
        f.write('{\"ready\": true, \"stop_at_phase\": 2}')

    result = module.scan_autogate_configs(tmpdir)
    assert 'EPIC_test' in result, f'Expected EPIC_test in result, got {result}'
    assert result['EPIC_test']['stop_at_phase'] == 2, f'Expected stop_at_phase=2'
"

echo ""

# ============================================================================
# SECTION 13: Unit Tests (Python internal functions)
# ============================================================================

echo -e "${BLUE}SECTION 13: Python Unit Tests${NC}"
echo "------------------------------"

# Unit Test: detect_sdd_context with empty list
run_python_unit_test "detect_sdd_context with empty list" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

result = module.detect_sdd_context([])
assert result['workflow'] == 'none', f\"Expected 'none', got {result['workflow']}\"
assert result['indicators'] == [], f\"Expected empty list, got {result['indicators']}\"
"

# Unit Test: detect_sdd_context with planning patterns
run_python_unit_test "detect_sdd_context with planning patterns" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

entries = [
    {'display': '/sdd:plan-ticket some ticket'},
    {'display': 'Working on AUTH_test-ticket'},
]
result = module.detect_sdd_context(entries)
assert result['workflow'] == 'planning', f\"Expected 'planning', got {result['workflow']}\"
"

# Unit Test: detect_sdd_context with implementation patterns
run_python_unit_test "detect_sdd_context with implementation patterns" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

entries = [
    {'display': '/sdd:do-task AUTH.1001'},
    {'display': 'Implementing task AUTH.1002'},
]
result = module.detect_sdd_context(entries)
assert result['workflow'] == 'implementation', f\"Expected 'implementation', got {result['workflow']}\"
assert result['task_id'] == 'AUTH.1002', f\"Expected 'AUTH.1002', got {result['task_id']}\"
"

# Unit Test: generate_guidance returns None for 'none' workflow
run_python_unit_test "generate_guidance returns None for 'none' workflow" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

result = module.generate_guidance({'workflow': 'none'})
assert result is None, f\"Expected None, got {result}\"
"

# Unit Test: generate_guidance returns string for planning workflow
run_python_unit_test "generate_guidance returns string for planning workflow" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

result = module.generate_guidance({'workflow': 'planning', 'ticket_id': 'AUTH-123'})
assert result is not None, 'Expected non-None result'
assert isinstance(result, str), f'Expected string, got {type(result)}'
assert 'AUTH-123' in result, f'Expected ticket ID in guidance'
"

# Unit Test: generate_guidance returns string for implementation workflow
run_python_unit_test "generate_guidance returns string for implementation workflow" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

result = module.generate_guidance({'workflow': 'implementation', 'task_id': 'AUTH.1001'})
assert result is not None, 'Expected non-None result'
assert isinstance(result, str), f'Expected string, got {type(result)}'
assert 'AUTH.1001' in result, f'Expected task ID in guidance'
"

# Unit Test: determine_workflow_state prioritizes implementation
run_python_unit_test "determine_workflow_state prioritizes implementation" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

# Implementation should take priority over planning
result = module.determine_workflow_state(
    ['/sdd:plan-ticket', '/sdd:do-task'],
    ['AUTH.1001'],
    ['AUTH-123']
)
assert result == 'implementation', f\"Expected 'implementation', got {result}\"
"

# Unit Test: read_transcript_tail handles missing file
run_python_unit_test "read_transcript_tail handles missing file" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

result = module.read_transcript_tail('/nonexistent/path/file.jsonl')
assert result == [], f'Expected empty list, got {result}'
"

# Unit Test: read_transcript_tail parses valid JSONL
run_python_unit_test "read_transcript_tail parses valid JSONL" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

result = module.read_transcript_tail('$FIXTURES/transcript-planning.jsonl')
assert len(result) > 0, 'Expected non-empty result'
assert 'display' in result[0], 'Expected display field in entries'
"

# Unit Test: MIN_INDICATORS threshold prevents false positives
run_python_unit_test "MIN_INDICATORS threshold prevents false positives" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

# Single indicator should not trigger workflow
entries = [
    {'display': 'Just mentioned AUTH-123 once'},
]
result = module.detect_sdd_context(entries)
assert result['workflow'] == 'none', f\"Expected 'none' with single indicator, got {result['workflow']}\"
"

# Unit Test: generate_guidance for verification workflow
run_python_unit_test "generate_guidance for verification workflow" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

result = module.generate_guidance({'workflow': 'verification'})
assert result is not None, 'Expected non-None result'
assert 'pr' in result.lower() or 'test' in result.lower(), f'Expected PR or test mention in guidance'
"

echo ""

# ============================================================================
# SECTION 14: Performance Tests
# ============================================================================

echo -e "${BLUE}SECTION 14: Performance Tests${NC}"
echo "------------------------------"

# Performance test helper
run_performance_test() {
    local name="$1"
    local max_time_ms="$2"  # Maximum allowed time in milliseconds
    local setup_cmd="$3"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Perf Test: $name ... "

    # Run setup if provided
    if [ -n "$setup_cmd" ]; then
        eval "$setup_cmd"
    fi

    # Measure execution time
    local start_time=$(python3 -c "import time; print(int(time.time() * 1000))")
    cat "$TEMP_DIR/input.json" | python3 "$HOOK" > /dev/null 2>&1 || true
    local end_time=$(python3 -c "import time; print(int(time.time() * 1000))")

    local elapsed=$((end_time - start_time))

    if [ "$elapsed" -le "$max_time_ms" ]; then
        echo -e "${GREEN}PASS${NC} (${elapsed}ms <= ${max_time_ms}ms)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC} (${elapsed}ms > ${max_time_ms}ms)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Test 14.1: Baseline performance (empty context)
generate_input "transcript-empty.jsonl" false
run_performance_test "Baseline (empty context)" 500

# Test 14.2: Normal transcript performance
generate_input "transcript-planning.jsonl" false
run_performance_test "Normal transcript" 500

# Test 14.3: Performance with gate checks (10 tickets)
# Setup 10 ticket gates
for i in {1..10}; do
    setup_sdd_gates "PERF_ticket-$i" "ready.json"
done
generate_input "transcript-planning.jsonl" false
run_performance_test "With 10 ticket gates" 1000

# Test 14.4: Performance with gate checks (50 tickets)
for i in {11..50}; do
    setup_sdd_gates "PERF_ticket-$i" "ready.json"
done
cat > "$TEMP_DIR/input.json" << EOF
{
  "session_id": "test-session-123",
  "transcript_path": "$FIXTURES/transcript-planning.jsonl",
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
EOF
run_performance_test "With 50 ticket gates" 1000

# Test 14.5: Large transcript performance (simulate 10MB)
# Create a large transcript file
python3 << EOF
import json
with open('$TEMP_DIR/large-transcript.jsonl', 'w') as f:
    for i in range(10000):
        entry = {'display': f'Line {i}: Working on AUTH-123 with lots of text ' * 10, 'timestamp': i}
        f.write(json.dumps(entry) + '\n')
EOF

cat > "$TEMP_DIR/input.json" << EOF
{
  "session_id": "test-session-123",
  "transcript_path": "$TEMP_DIR/large-transcript.jsonl",
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
EOF
run_performance_test "Large transcript (10K lines)" 1000

echo ""

# ============================================================================
# SECTION 15: Task File Inspection - Checkbox Parsing Unit Tests
# ============================================================================

echo -e "${BLUE}SECTION 15: Task File Inspection - Checkbox Parsing Unit Tests${NC}"
echo "---------------------------------------------------------------"

# Test 15.1: Parse unchecked Task completed checkbox
run_python_unit_test "Parse unchecked Task completed checkbox" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

content = '''## Status
- [ ] **Task completed** - acceptance criteria met
- [ ] **Tests pass** - tests executed and passing
- [ ] **Verified** - by the verify-task agent
'''
result = module.parse_task_file_status(content)
assert result['task_completed'] == False, f'Expected task_completed=False, got {result[\"task_completed\"]}'
assert result['is_in_progress'] == True, f'Expected is_in_progress=True, got {result[\"is_in_progress\"]}'
"

# Test 15.2: Parse checked Task completed checkbox
run_python_unit_test "Parse checked Task completed checkbox" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

content = '''## Status
- [x] **Task completed** - acceptance criteria met
- [x] **Tests pass** - tests executed and passing
- [ ] **Verified** - by the verify-task agent
'''
result = module.parse_task_file_status(content)
assert result['task_completed'] == True, f'Expected task_completed=True, got {result[\"task_completed\"]}'
assert result['tests_pass'] == True, f'Expected tests_pass=True, got {result[\"tests_pass\"]}'
assert result['verified'] == False, f'Expected verified=False, got {result[\"verified\"]}'
assert result['is_in_progress'] == False, f'Expected is_in_progress=False, got {result[\"is_in_progress\"]}'
"

# Test 15.3: Parse fully verified task
run_python_unit_test "Parse fully verified task" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

content = '''## Status
- [x] **Task completed** - acceptance criteria met
- [x] **Tests pass** - tests executed and passing
- [x] **Verified** - by the verify-task agent
'''
result = module.parse_task_file_status(content)
assert result['task_completed'] == True, f'Expected task_completed=True'
assert result['tests_pass'] == True, f'Expected tests_pass=True'
assert result['verified'] == True, f'Expected verified=True'
assert result['is_in_progress'] == False, f'Expected is_in_progress=False'
"

# Test 15.4: Parse checkbox without bold formatting
run_python_unit_test "Parse checkbox without bold formatting" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

content = '''## Status
- [ ] Task completed - acceptance criteria met
- [ ] Tests pass - tests executed and passing
- [ ] Verified - by the verify-task agent
'''
result = module.parse_task_file_status(content)
assert result['task_completed'] == False, 'Should parse without bold'
assert result['is_in_progress'] == True, 'Should detect in progress without bold'
"

# Test 15.5: Parse checkbox with uppercase X
run_python_unit_test "Parse checkbox with uppercase X" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

content = '''## Status
- [X] **Task completed** - acceptance criteria met
- [X] **Tests pass** - tests executed and passing
- [X] **Verified** - by the verify-task agent
'''
result = module.parse_task_file_status(content)
assert result['task_completed'] == True, f'Should parse uppercase X, got {result[\"task_completed\"]}'
assert result['tests_pass'] == True, 'Should parse uppercase X'
assert result['verified'] == True, 'Should parse uppercase X'
"

# Test 15.6: Parse indented checkboxes
run_python_unit_test "Parse indented checkboxes" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

content = '''## Status
  - [ ] **Task completed** - acceptance criteria met
  - [ ] **Tests pass** - tests executed and passing
  - [ ] **Verified** - by the verify-task agent
'''
result = module.parse_task_file_status(content)
assert result['task_completed'] == False, 'Should parse indented checkboxes'
assert result['is_in_progress'] == True, 'Should detect in progress with indentation'
"

# Test 15.7: Ignore checkboxes in code blocks
run_python_unit_test "Ignore checkboxes in code blocks" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

content = '''## Status
- [x] **Task completed** - acceptance criteria met
- [x] **Tests pass** - tests executed and passing
- [x] **Verified** - by the verify-task agent

## Example

\`\`\`markdown
- [ ] **Task completed** - acceptance criteria met
\`\`\`

Should ignore the above.
'''
result = module.parse_task_file_status(content)
assert result['task_completed'] == True, f'Should ignore code block, got task_completed={result[\"task_completed\"]}'
assert result['is_in_progress'] == False, f'Should ignore code block, got is_in_progress={result[\"is_in_progress\"]}'
"

# Test 15.8: Empty content returns defaults
run_python_unit_test "Empty content returns safe defaults" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

result = module.parse_task_file_status('')
assert result['task_completed'] == False, 'Empty content: task_completed should be False'
assert result['tests_pass'] == False, 'Empty content: tests_pass should be False'
assert result['verified'] == False, 'Empty content: verified should be False'
assert result['is_in_progress'] == False, 'Empty content: is_in_progress should be False (no checkbox found)'
"

# Test 15.9: Content with only other checkboxes (no Status section)
run_python_unit_test "Content with unrelated checkboxes" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

content = '''## Acceptance Criteria
- [ ] Some random criteria
- [x] Another criteria
'''
result = module.parse_task_file_status(content)
# Should not find Task completed, so is_in_progress should be False
assert result['is_in_progress'] == False, 'No Status section: is_in_progress should be False'
"

echo ""

# ============================================================================
# SECTION 16: Task File Inspection - Task ID Extraction Tests
# ============================================================================

echo -e "${BLUE}SECTION 16: Task File Inspection - Task ID Extraction Tests${NC}"
echo "-------------------------------------------------------------"

# Test 16.1: Extract task ID from standard filename
run_python_unit_test "Extract task ID from standard filename" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

result = module.extract_task_id_from_filename('STOPHOOK.1001_task-file-inspection.md')
assert result == 'STOPHOOK.1001', f\"Expected 'STOPHOOK.1001', got {result}\"
"

# Test 16.2: Extract task ID with short ticket prefix
run_python_unit_test "Extract task ID with short prefix" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

result = module.extract_task_id_from_filename('AUTH.2001_some-task.md')
assert result == 'AUTH.2001', f\"Expected 'AUTH.2001', got {result}\"
"

# Test 16.3: Non-.md file returns None
run_python_unit_test "Non-.md file returns None" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

result = module.extract_task_id_from_filename('STOPHOOK.1001_task.txt')
assert result is None, f'Expected None for non-.md file, got {result}'
"

# Test 16.4: Invalid filename format returns None
run_python_unit_test "Invalid filename format returns None" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

result = module.extract_task_id_from_filename('readme.md')
assert result is None, f'Expected None for invalid format, got {result}'
"

echo ""

# ============================================================================
# SECTION 17: Task File Inspection - check_task_status Integration Tests
# ============================================================================

echo -e "${BLUE}SECTION 17: Task File Inspection - check_task_status Integration Tests${NC}"
echo "-----------------------------------------------------------------------"

# Setup for integration tests - create a test ticket structure
setup_task_fixtures() {
    local ticket_name="$1"
    local ticket_dir="$TEST_SDD_ROOT/tickets/$ticket_name"
    local tasks_dir="$ticket_dir/tasks"
    mkdir -p "$tasks_dir"

    # Copy task fixtures
    if [ -d "$FIXTURES/tasks" ]; then
        cp "$FIXTURES/tasks"/*.md "$tasks_dir/" 2>/dev/null || true
    fi
}

# Test 17.1: check_task_status finds in-progress tasks
setup_task_fixtures "TEST_has-in-progress"
run_python_unit_test "check_task_status finds in-progress tasks" "
import sys
import os
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

result = module.check_task_status('$TEST_SDD_ROOT', 'TEST_has-in-progress')
assert result['has_in_progress'] == True, f\"Expected has_in_progress=True, got {result['has_in_progress']}\"
assert len(result['in_progress_tasks']) > 0, f\"Expected some in_progress_tasks, got {result['in_progress_tasks']}\"
assert 'TEST.1001' in result['in_progress_tasks'], f\"Expected TEST.1001 in in_progress_tasks: {result['in_progress_tasks']}\"
"

# Test 17.2: check_task_status finds completed tasks
run_python_unit_test "check_task_status finds completed tasks" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

result = module.check_task_status('$TEST_SDD_ROOT', 'TEST_has-in-progress')
assert 'TEST.1002' in result['completed_tasks'], f\"Expected TEST.1002 in completed_tasks: {result['completed_tasks']}\"
"

# Test 17.3: check_task_status finds verified tasks
run_python_unit_test "check_task_status finds verified tasks" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

result = module.check_task_status('$TEST_SDD_ROOT', 'TEST_has-in-progress')
assert 'TEST.1003' in result['verified_tasks'], f\"Expected TEST.1003 in verified_tasks: {result['verified_tasks']}\"
"

# Test 17.4: check_task_status handles missing ticket gracefully
run_python_unit_test "check_task_status handles missing ticket" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

result = module.check_task_status('$TEST_SDD_ROOT', 'NONEXISTENT_ticket')
assert result['has_in_progress'] == False, 'Missing ticket should return has_in_progress=False (fail-safe)'
assert result['error'] is None, 'Missing ticket should not set error'
"

# Test 17.5: check_task_status handles empty SDD_ROOT gracefully
run_python_unit_test "check_task_status handles empty SDD_ROOT" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

result = module.check_task_status('', 'TEST_ticket')
assert result['has_in_progress'] == False, 'Empty SDD_ROOT should return has_in_progress=False (fail-safe)'
"

# Test 17.6: check_task_status handles None ticket_id gracefully
run_python_unit_test "check_task_status handles None ticket_id" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

result = module.check_task_status('$TEST_SDD_ROOT', None)
assert result['has_in_progress'] == False, 'None ticket_id should return has_in_progress=False (fail-safe)'
"

# Test 17.7: Create a ticket with only completed tasks (no in-progress)
mkdir -p "$TEST_SDD_ROOT/tickets/TEST_all-completed/tasks"
cat > "$TEST_SDD_ROOT/tickets/TEST_all-completed/tasks/TEST.9001_done.md" << EOF
# Task: [TEST.9001]: Done Task

## Status
- [x] **Task completed** - acceptance criteria met
- [x] **Tests pass** - tests executed and passing
- [x] **Verified** - by the verify-task agent
EOF

run_python_unit_test "check_task_status returns has_in_progress=False for completed tasks" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

result = module.check_task_status('$TEST_SDD_ROOT', 'TEST_all-completed')
assert result['has_in_progress'] == False, f\"All completed: expected has_in_progress=False, got {result['has_in_progress']}\"
assert len(result['verified_tasks']) > 0, 'Should have verified tasks'
"

echo ""

# ============================================================================
# SECTION 18: Task File Inspection - Blocking Behavior Integration Tests
# ============================================================================

echo -e "${BLUE}SECTION 18: Task File Inspection - Blocking Behavior Integration Tests${NC}"
echo "-----------------------------------------------------------------------"

# Test 18.1: Hook blocks when task is in progress
# Create a transcript that references the ticket with in-progress tasks
cat > "$TEMP_DIR/transcript-task-in-progress.jsonl" << EOF
{"display": "/sdd:do-task TEST.1001", "timestamp": 1700000001000, "sessionId": "test-123"}
{"display": "Working on TEST_has-in-progress", "timestamp": 1700000002000, "sessionId": "test-123"}
EOF

cat > "$TEMP_DIR/input.json" << EOF
{
  "session_id": "test-session-123",
  "transcript_path": "$TEMP_DIR/transcript-task-in-progress.jsonl",
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
EOF

run_test_with_env "Hook blocks when task is in progress" 2 "SDD_ROOT_DIR" "$TEST_SDD_ROOT" "TASKS? IN PROGRESS"

# Test 18.2: Hook allows when all tasks completed
cat > "$TEMP_DIR/transcript-all-completed.jsonl" << EOF
{"display": "/sdd:do-task TEST.9001", "timestamp": 1700000001000, "sessionId": "test-123"}
{"display": "Working on TEST_all-completed", "timestamp": 1700000002000, "sessionId": "test-123"}
EOF

cat > "$TEMP_DIR/input.json" << EOF
{
  "session_id": "test-session-123",
  "transcript_path": "$TEMP_DIR/transcript-all-completed.jsonl",
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
EOF

run_test_with_env "Hook allows when all tasks completed" 0 "SDD_ROOT_DIR" "$TEST_SDD_ROOT"

# Test 18.3: Hook allows when ticket has no tasks
mkdir -p "$TEST_SDD_ROOT/tickets/TEST_no-tasks"
# Note: No tasks directory created

cat > "$TEMP_DIR/transcript-no-tasks.jsonl" << EOF
{"display": "/sdd:plan-ticket TEST-999", "timestamp": 1700000001000, "sessionId": "test-123"}
{"display": "Working on TEST_no-tasks", "timestamp": 1700000002000, "sessionId": "test-123"}
EOF

cat > "$TEMP_DIR/input.json" << EOF
{
  "session_id": "test-session-123",
  "transcript_path": "$TEMP_DIR/transcript-no-tasks.jsonl",
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
EOF

run_test_with_env "Hook allows when ticket has no tasks" 0 "SDD_ROOT_DIR" "$TEST_SDD_ROOT"

# Test 18.4: Hook allows when ticket not found (fail-safe)
cat > "$TEMP_DIR/transcript-missing-ticket.jsonl" << EOF
{"display": "/sdd:do-task MISSING.1001", "timestamp": 1700000001000, "sessionId": "test-123"}
{"display": "Working on MISSING_ticket", "timestamp": 1700000002000, "sessionId": "test-123"}
EOF

cat > "$TEMP_DIR/input.json" << EOF
{
  "session_id": "test-session-123",
  "transcript_path": "$TEMP_DIR/transcript-missing-ticket.jsonl",
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
EOF

run_test_with_env "Hook allows when ticket not found (fail-safe)" 0 "SDD_ROOT_DIR" "$TEST_SDD_ROOT"

# Test 18.5: SDD_DISABLE_STOP_HOOK bypasses task inspection
cat > "$TEMP_DIR/input.json" << EOF
{
  "session_id": "test-session-123",
  "transcript_path": "$TEMP_DIR/transcript-task-in-progress.jsonl",
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
EOF

TESTS_RUN=$((TESTS_RUN + 1))
echo -n "Test: SDD_DISABLE_STOP_HOOK bypasses task inspection ... "
actual_exit=0
output=$(export SDD_ROOT_DIR="$TEST_SDD_ROOT" && export SDD_DISABLE_STOP_HOOK="1" && cat "$TEMP_DIR/input.json" | python3 "$HOOK" 2>&1) || actual_exit=$?
if [ "$actual_exit" -eq 0 ]; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC} (expected exit 0, got $actual_exit)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

echo ""

# ============================================================================
# SECTION 19: Task File Inspection - Message Generation Tests
# ============================================================================

echo -e "${BLUE}SECTION 19: Task File Inspection - Message Generation Tests${NC}"
echo "------------------------------------------------------------"

# Test 19.1: Single task in progress message
run_python_unit_test "Single task in progress message" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

context = {'ticket_id': 'TEST_ticket'}
task_status = {'in_progress_tasks': ['TEST.1001']}
message = module.generate_task_in_progress_message(context, task_status)
assert 'TEST.1001' in message, f'Message should contain task ID: {message}'
assert 'TASK IN PROGRESS' in message, f'Message should contain header: {message}'
assert 'multi-session' in message.lower(), f'Message should mention multi-session limitation: {message}'
"

# Test 19.2: Multiple tasks in progress message
run_python_unit_test "Multiple tasks in progress message" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

context = {'ticket_id': 'TEST_ticket'}
task_status = {'in_progress_tasks': ['TEST.1001', 'TEST.1002', 'TEST.1003']}
message = module.generate_task_in_progress_message(context, task_status)
assert 'TASKS IN PROGRESS' in message, f'Message should contain plural header: {message}'
assert '3 tasks' in message, f'Message should mention count: {message}'
assert 'TEST.1001' in message, f'Message should list tasks: {message}'
assert 'TEST.1002' in message, f'Message should list tasks: {message}'
"

echo ""

# ============================================================================
# SECTION 20: Task File Inspection - Performance Tests
# ============================================================================

echo -e "${BLUE}SECTION 20: Task File Inspection - Performance Tests${NC}"
echo "-----------------------------------------------------"

# Setup: Create 50 task files for performance testing
mkdir -p "$TEST_SDD_ROOT/tickets/PERF_many-tasks/tasks"
for i in $(seq -w 1001 1050); do
    cat > "$TEST_SDD_ROOT/tickets/PERF_many-tasks/tasks/PERF.${i}_task-${i}.md" << EOF
# Task: [PERF.${i}]: Task ${i}

## Status
- [x] **Task completed** - acceptance criteria met
- [x] **Tests pass** - tests executed and passing
- [x] **Verified** - by the verify-task agent

## Summary
This is task ${i} for performance testing.
EOF
done

# Test 20.1: Performance with 50 task files
run_python_unit_test "check_task_status < 100ms with 50 tasks" "
import sys
import time
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

start = time.time()
result = module.check_task_status('$TEST_SDD_ROOT', 'PERF_many-tasks')
elapsed_ms = (time.time() - start) * 1000

assert elapsed_ms < 100, f'Performance: expected < 100ms, got {elapsed_ms:.1f}ms'
assert len(result['task_statuses']) == 50, f'Should parse 50 tasks, got {len(result[\"task_statuses\"])}'
"

# Test 20.2: Full hook performance with task inspection
cat > "$TEMP_DIR/transcript-perf-tasks.jsonl" << EOF
{"display": "/sdd:do-task PERF.1001", "timestamp": 1700000001000, "sessionId": "test-123"}
{"display": "Working on PERF_many-tasks", "timestamp": 1700000002000, "sessionId": "test-123"}
EOF

cat > "$TEMP_DIR/input.json" << EOF
{
  "session_id": "test-session-123",
  "transcript_path": "$TEMP_DIR/transcript-perf-tasks.jsonl",
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
EOF

run_performance_test "Hook with 50 task files" 500

echo ""

# ============================================================================
# SECTION 21: Task File Inspection - Edge Cases
# ============================================================================

echo -e "${BLUE}SECTION 21: Task File Inspection - Edge Cases${NC}"
echo "----------------------------------------------"

# Test 21.1: Task file with multiple code blocks
run_python_unit_test "Multiple code blocks handled correctly" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

content = '''## Status
- [x] **Task completed** - done

## Example 1
\`\`\`
- [ ] **Task completed** - example 1
\`\`\`

## Example 2
\`\`\`markdown
- [ ] **Task completed** - example 2
\`\`\`

## Notes
More content here.
'''
result = module.parse_task_file_status(content)
assert result['task_completed'] == True, f'Should find real checkbox, not code blocks'
assert result['is_in_progress'] == False, f'Should not be in progress'
"

# Test 21.2: Unicode in task content
run_python_unit_test "Unicode in task content handled" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

content = '''## Status
- [ ] **Task completed** - acceptance criteria met
- [ ] **Tests pass** - tests pass

## Summary
This task has unicode: cafe, emojis, and special chars.
'''
result = module.parse_task_file_status(content)
assert result['task_completed'] == False, 'Should parse despite unicode'
assert result['is_in_progress'] == True, 'Should detect in progress'
"

# Test 21.3: Very long task file
run_python_unit_test "Very long task file handled" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

# Create a task file with lots of content
long_content = '''## Status
- [ ] **Task completed** - acceptance criteria met
- [ ] **Tests pass** - tests pass
- [ ] **Verified** - verified

## Summary
This is a very long task file.

''' + 'A' * 100000 + '''

## End
More content.
'''
result = module.parse_task_file_status(long_content)
assert result['task_completed'] == False, 'Should parse long content'
assert result['is_in_progress'] == True, 'Should detect in progress in long content'
"

# Test 21.4: find_ticket_tasks_directory with Jira-style ticket ID
mkdir -p "$TEST_SDD_ROOT/tickets/AUTH-123_feature-name/tasks"
touch "$TEST_SDD_ROOT/tickets/AUTH-123_feature-name/tasks/AUTH.1001_test.md"

run_python_unit_test "find_ticket_tasks_directory with Jira-style ID" "
import sys
sys.path.insert(0, '$SCRIPT_DIR')
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

spec = spec_from_loader('workflow_guidance', SourceFileLoader('workflow_guidance', '$HOOK'))
module = module_from_spec(spec)
spec.loader.exec_module(module)

result = module.find_ticket_tasks_directory('$TEST_SDD_ROOT', 'AUTH-123')
assert result is not None, f'Should find directory for Jira-style ID'
assert 'AUTH-123_feature-name' in result, f'Should find correct directory: {result}'
"

echo ""

# ============================================================================
# Summary
# ============================================================================

echo "================================"
echo "Test Summary"
echo "================================"
echo "Tests run:   $TESTS_RUN"
echo -e "Passed:      ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed:      ${RED}$TESTS_FAILED${NC}"
echo "================================"

if [ $TESTS_FAILED -gt 0 ]; then
    echo ""
    echo -e "${RED}FAILED: $TESTS_FAILED test(s) failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}SUCCESS: All tests passed!${NC}"
exit 0
