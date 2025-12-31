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

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
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
    if [ "$VERBOSE" = true ]; then
        echo "Created temp directory: $TEMP_DIR"
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
        if ! echo "$output" | grep -q "$check_output"; then
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

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: $name ... "

    local actual_exit=0
    local output=""

    # Run with environment variable set
    output=$(export "$env_var=$env_value" && cat "$TEMP_DIR/input.json" | python3 "$HOOK" 2>&1) || actual_exit=$?

    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC} (expected exit $expected_exit, got $actual_exit)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
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
# Integration Tests
# ============================================================================

echo "Running Integration Tests..."
echo "----------------------------"

# Test 1: No SDD context - should exit 0, no guidance
generate_input "transcript-no-sdd.jsonl" false
run_test "No SDD context - exits 0" 0

# Test 2: Planning workflow - should exit 0 with guidance
generate_input "transcript-planning.jsonl" false
run_test "Planning workflow - exits 0 with guidance" 0 "planning"

# Test 3: Implementation workflow - should exit 0 with guidance
generate_input "transcript-implementation.jsonl" false
run_test "Implementation workflow - exits 0 with guidance" 0 "implementation"

# Test 4: stop_hook_active=true - should exit 0 immediately (loop prevention)
generate_input "transcript-planning.jsonl" true
run_test "stop_hook_active=true - exits 0 immediately" 0

# Test 5: Invalid transcript path - should exit 0 gracefully
cat > "$TEMP_DIR/input.json" << EOF
{
  "session_id": "test-session-123",
  "transcript_path": "/nonexistent/path/transcript.jsonl",
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
EOF
run_test "Invalid transcript path - exits 0 gracefully" 0

# Test 6: Empty transcript - should exit 0
generate_input "transcript-empty.jsonl" false
run_test "Empty transcript - exits 0" 0

# Test 7: Malformed transcript - should exit 0 gracefully (valid lines parsed)
generate_input "transcript-malformed.jsonl" false
run_test "Malformed transcript - exits 0 gracefully" 0

# Test 8: Missing transcript_path field - should exit 0
cat > "$TEMP_DIR/input.json" << EOF
{
  "session_id": "test-session-123",
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
EOF
run_test "Missing transcript_path - exits 0" 0

# Test 9: Invalid JSON input - should exit 0 (fail-safe)
run_test_raw_input "Invalid JSON input - exits 0" 0 "this is not json"

# Test 10: Empty stdin - should exit 0 (fail-safe)
run_test_raw_input "Empty stdin - exits 0" 0 ""

# Test 11: Environment variable SDD_DISABLE_STOP_HOOK - should exit 0 immediately
generate_input "transcript-planning.jsonl" false
run_test_with_env "SDD_DISABLE_STOP_HOOK set - exits 0" 0 "SDD_DISABLE_STOP_HOOK" "1"

# Test 12: Verify planning guidance contains expected content
generate_input "transcript-planning.jsonl" false
run_test "Planning guidance mentions review or create-tasks" 0 "sdd:review\|sdd:create-tasks"

# Test 13: Verify implementation guidance contains expected content
generate_input "transcript-implementation.jsonl" false
run_test "Implementation guidance mentions tests or commit" 0 "test\|commit"

# Test 14: Null transcript_path - should exit 0
cat > "$TEMP_DIR/input.json" << EOF
{
  "session_id": "test-session-123",
  "transcript_path": null,
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
EOF
run_test "Null transcript_path - exits 0" 0

# Test 15: Transcript path with special characters - should handle gracefully
cat > "$TEMP_DIR/input.json" << EOF
{
  "session_id": "test-session-123",
  "transcript_path": "/path/with spaces/and-special~chars!/transcript.jsonl",
  "hook_event_name": "Stop",
  "stop_hook_active": false
}
EOF
run_test "Special characters in path - exits 0" 0

# ============================================================================
# Unit Test Integration (Python internal tests)
# ============================================================================

echo ""
echo "Running Python Unit Tests..."
echo "----------------------------"

# Test individual functions using Python
UNIT_TESTS_PASSED=0
UNIT_TESTS_FAILED=0

# Unit test helper
run_python_unit_test() {
    local name="$1"
    local test_code="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Unit Test: $name ... "

    local result
    if python3 -c "$test_code" 2>/dev/null; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        UNIT_TESTS_PASSED=$((UNIT_TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        UNIT_TESTS_FAILED=$((UNIT_TESTS_FAILED + 1))
    fi
}

# Import the module for unit testing
HOOK_MODULE=$(cat << 'PYEOF'
import sys
sys.path.insert(0, '${SCRIPT_DIR}')
PYEOF
)

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

# ============================================================================
# Summary
# ============================================================================

echo ""
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
