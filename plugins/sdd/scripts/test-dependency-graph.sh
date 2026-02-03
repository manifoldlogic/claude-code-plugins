#!/bin/bash
# test-dependency-graph.sh - Test suite for calculate-dependency-graph.py
#
# This script runs comprehensive unit tests for the SDD dependency graph calculator.
# It tests various scenarios including:
# - Simple linear dependencies (Phase 1 -> Phase 2)
# - Complex multi-phase dependencies
# - Independent tasks within phases
# - Circular dependency detection (error case)
# - Empty ticket (edge case)
# - Tasks with explicit dependencies
#
# Usage:
#   ./test-dependency-graph.sh           # Run all tests
#   ./test-dependency-graph.sh -v        # Verbose output
#   ./test-dependency-graph.sh --help    # Show help
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed

set -e  # Exit on first failure

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CALC_SCRIPT="$SCRIPT_DIR/calculate-dependency-graph.py"
TEMP_DIR=""

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
while [ $# -gt 0 ]; do
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

# Setup temporary directory for test files
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

# Create a test ticket directory structure
create_test_ticket() {
    local ticket_name="$1"
    local ticket_dir="$TEMP_DIR/$ticket_name"
    mkdir -p "$ticket_dir/tasks"
    echo "$ticket_dir"
}

# Create a task file
create_task_file() {
    local tasks_dir="$1"
    local task_id="$2"
    local task_name="$3"
    local deps="${4:-}"  # comma-separated dependencies

    local file_path="$tasks_dir/${task_id}_${task_name}.md"

    cat > "$file_path" << EOF
# Task: [$task_id]: ${task_name//-/ }

## Status
- [ ] **Task completed** - acceptance criteria met
- [ ] **Tests pass** - tests executed and passing (or N/A if no tests)
- [ ] **Verified** - by the verify-task agent

## Summary
This is the summary for task $task_id.

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2

EOF

    # Add dependencies section if provided
    if [ -n "$deps" ]; then
        echo "## Dependencies" >> "$file_path"
        # Use portable approach instead of bash arrays
        echo "$deps" | tr ',' '\n' | while read -r dep; do
            if [ -n "$dep" ]; then
                echo "- $dep" >> "$file_path"
            fi
        done
        echo "" >> "$file_path"
    fi

    echo "## Technical Requirements" >> "$file_path"
    echo "Some technical requirements here." >> "$file_path"
}

# Run calculation and store output
run_calculation() {
    local ticket_dir="$1"
    python3 "$CALC_SCRIPT" "$ticket_dir" 2>"$TEMP_DIR/stderr.txt"
}

# Get JSON field using Python (portable)
get_json_field() {
    local json="$1"
    local field="$2"
    echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
result = data.get('$field', {})
print(json.dumps(result, sort_keys=True))
" 2>/dev/null
}

# Get phases count
get_phases_count() {
    local json="$1"
    echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(len(data.get('phases', {})))
" 2>/dev/null
}

# Get tasks in phase
get_tasks_in_phase() {
    local json="$1"
    local phase="$2"
    echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
tasks = data.get('phases', {}).get('$phase', [])
print(','.join(sorted(tasks)))
" 2>/dev/null
}

# Get dependencies for a task (comma-separated, sorted)
get_deps_for_task() {
    local json="$1"
    local task_id="$2"
    echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
deps = data.get('dependencies', {}).get('$task_id', [])
print(','.join(sorted(deps)))
" 2>/dev/null
}

# Get independent tasks in phase
get_independent_in_phase() {
    local json="$1"
    local phase="$2"
    echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
tasks = data.get('independent', {}).get('$phase', [])
print(','.join(sorted(tasks)))
" 2>/dev/null
}

# Check if phases dict is empty
is_empty_graph() {
    local json="$1"
    echo "$json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if not data.get('phases') and not data.get('dependencies') and not data.get('independent'):
    print('yes')
else:
    print('no')
" 2>/dev/null
}

# Report test result
pass_test() {
    local name="$1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}PASS${NC}"
}

fail_test() {
    local name="$1"
    local reason="$2"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}FAIL${NC} ($reason)"
}

# ============================================================================
# Test Cases
# ============================================================================

test_simple_linear_dependencies() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Simple linear dependencies (Phase 1 -> Phase 2) ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "LINEAR")
    create_task_file "$ticket_dir/tasks" "LINEAR.1001" "phase-one-task"
    create_task_file "$ticket_dir/tasks" "LINEAR.2001" "phase-two-task"

    local output
    output=$(run_calculation "$ticket_dir") || { fail_test "Simple linear" "calculation failed"; return; }

    # Phase 1 task should have no dependencies
    local deps1
    deps1=$(get_deps_for_task "$output" "LINEAR.1001")
    if [ -n "$deps1" ]; then
        fail_test "Simple linear" "Phase 1 task should have no deps, got '$deps1'"
        return
    fi

    # Phase 2 task should depend on Phase 1 task
    local deps2
    deps2=$(get_deps_for_task "$output" "LINEAR.2001")
    if [ "$deps2" != "LINEAR.1001" ]; then
        fail_test "Simple linear" "Phase 2 should depend on LINEAR.1001, got '$deps2'"
        return
    fi

    pass_test "Simple linear"
}

test_three_phase_chain() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Three phase dependency chain ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "CHAIN")
    create_task_file "$ticket_dir/tasks" "CHAIN.1001" "phase-one"
    create_task_file "$ticket_dir/tasks" "CHAIN.2001" "phase-two"
    create_task_file "$ticket_dir/tasks" "CHAIN.3001" "phase-three"

    local output
    output=$(run_calculation "$ticket_dir") || { fail_test "Three phase chain" "calculation failed"; return; }

    # Phase 2 depends on Phase 1
    local deps2
    deps2=$(get_deps_for_task "$output" "CHAIN.2001")
    if [ "$deps2" != "CHAIN.1001" ]; then
        fail_test "Three phase chain" "Phase 2 should depend on CHAIN.1001, got '$deps2'"
        return
    fi

    # Phase 3 depends on Phase 2 (not Phase 1)
    local deps3
    deps3=$(get_deps_for_task "$output" "CHAIN.3001")
    if [ "$deps3" != "CHAIN.2001" ]; then
        fail_test "Three phase chain" "Phase 3 should depend on CHAIN.2001, got '$deps3'"
        return
    fi

    pass_test "Three phase chain"
}

test_multiple_tasks_per_phase() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Multiple tasks per phase ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "MULTI")
    create_task_file "$ticket_dir/tasks" "MULTI.1001" "phase-one-a"
    create_task_file "$ticket_dir/tasks" "MULTI.1002" "phase-one-b"
    create_task_file "$ticket_dir/tasks" "MULTI.1003" "phase-one-c"
    create_task_file "$ticket_dir/tasks" "MULTI.2001" "phase-two-a"

    local output
    output=$(run_calculation "$ticket_dir") || { fail_test "Multiple tasks per phase" "calculation failed"; return; }

    # Phase 2 task should depend on all Phase 1 tasks
    local deps2
    deps2=$(get_deps_for_task "$output" "MULTI.2001")
    if [ "$deps2" != "MULTI.1001,MULTI.1002,MULTI.1003" ]; then
        fail_test "Multiple tasks per phase" "Phase 2 should depend on all Phase 1 tasks, got '$deps2'"
        return
    fi

    pass_test "Multiple tasks per phase"
}

test_independent_tasks_same_phase() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Independent tasks in same phase can run parallel ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "INDEP")
    create_task_file "$ticket_dir/tasks" "INDEP.1001" "task-a"
    create_task_file "$ticket_dir/tasks" "INDEP.1002" "task-b"
    create_task_file "$ticket_dir/tasks" "INDEP.1003" "task-c"

    local output
    output=$(run_calculation "$ticket_dir") || { fail_test "Independent tasks" "calculation failed"; return; }

    # All tasks in Phase 1 should be independent (no intra-phase deps)
    local independent
    independent=$(get_independent_in_phase "$output" "1")
    if [ "$independent" != "INDEP.1001,INDEP.1002,INDEP.1003" ]; then
        fail_test "Independent tasks" "all Phase 1 tasks should be independent, got '$independent'"
        return
    fi

    pass_test "Independent tasks"
}

test_explicit_dependencies_within_phase() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Explicit dependencies within same phase ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "EXPLICIT")
    create_task_file "$ticket_dir/tasks" "EXPLICIT.1001" "base-task"
    create_task_file "$ticket_dir/tasks" "EXPLICIT.1002" "depends-on-first" "EXPLICIT.1001"
    create_task_file "$ticket_dir/tasks" "EXPLICIT.1003" "independent"

    local output
    output=$(run_calculation "$ticket_dir") || { fail_test "Explicit deps within phase" "calculation failed"; return; }

    # Task 1002 depends on 1001
    local deps2
    deps2=$(get_deps_for_task "$output" "EXPLICIT.1002")
    if [ "$deps2" != "EXPLICIT.1001" ]; then
        fail_test "Explicit deps within phase" "EXPLICIT.1002 should depend on EXPLICIT.1001, got '$deps2'"
        return
    fi

    # Independent tasks should be 1001 and 1003 (not 1002 since it depends on 1001)
    local independent
    independent=$(get_independent_in_phase "$output" "1")
    if [ "$independent" != "EXPLICIT.1001,EXPLICIT.1003" ]; then
        fail_test "Explicit deps within phase" "independent should be 'EXPLICIT.1001,EXPLICIT.1003', got '$independent'"
        return
    fi

    pass_test "Explicit deps within phase"
}

test_explicit_deps_across_phases() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Explicit dependencies across phases ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "CROSS")
    create_task_file "$ticket_dir/tasks" "CROSS.1001" "phase-one-a"
    create_task_file "$ticket_dir/tasks" "CROSS.1002" "phase-one-b"
    create_task_file "$ticket_dir/tasks" "CROSS.2001" "phase-two" "CROSS.1001"

    local output
    output=$(run_calculation "$ticket_dir") || { fail_test "Cross-phase explicit deps" "calculation failed"; return; }

    # Phase 2 has both phase deps (all of Phase 1) and explicit dep on CROSS.1001
    # Result should include both
    local deps2
    deps2=$(get_deps_for_task "$output" "CROSS.2001")
    if [ "$deps2" != "CROSS.1001,CROSS.1002" ]; then
        fail_test "Cross-phase explicit deps" "CROSS.2001 should depend on both Phase 1 tasks, got '$deps2'"
        return
    fi

    pass_test "Cross-phase explicit deps"
}

test_circular_dependency_direct() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Direct circular dependency detected ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "CIRCONE")
    create_task_file "$ticket_dir/tasks" "CIRCONE.1001" "task-a" "CIRCONE.1002"
    create_task_file "$ticket_dir/tasks" "CIRCONE.1002" "task-b" "CIRCONE.1001"

    local exit_code=0
    python3 "$CALC_SCRIPT" "$ticket_dir" >/dev/null 2>&1 || exit_code=$?

    if [ "$exit_code" -ne 2 ]; then
        fail_test "Direct circular" "expected exit code 2 for circular dep, got $exit_code"
        return
    fi

    pass_test "Direct circular"
}

test_circular_dependency_indirect() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Indirect circular dependency detected (A->B->C->A) ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "CIRCTWO")
    create_task_file "$ticket_dir/tasks" "CIRCTWO.1001" "task-a" "CIRCTWO.1003"
    create_task_file "$ticket_dir/tasks" "CIRCTWO.1002" "task-b" "CIRCTWO.1001"
    create_task_file "$ticket_dir/tasks" "CIRCTWO.1003" "task-c" "CIRCTWO.1002"

    local exit_code=0
    python3 "$CALC_SCRIPT" "$ticket_dir" >/dev/null 2>&1 || exit_code=$?

    if [ "$exit_code" -ne 2 ]; then
        fail_test "Indirect circular" "expected exit code 2 for circular dep, got $exit_code"
        return
    fi

    pass_test "Indirect circular"
}

test_empty_tasks_directory() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Empty tasks directory returns empty graph ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "EMPTY")
    # Tasks directory exists but is empty

    local output
    output=$(run_calculation "$ticket_dir") || { fail_test "Empty tasks dir" "calculation failed"; return; }

    local is_empty
    is_empty=$(is_empty_graph "$output")
    if [ "$is_empty" != "yes" ]; then
        fail_test "Empty tasks dir" "expected empty graph"
        return
    fi

    pass_test "Empty tasks dir"
}

test_no_tasks_directory() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: No tasks subdirectory returns empty graph ... "

    local ticket_dir="$TEMP_DIR/NOTASKS"
    mkdir -p "$ticket_dir"
    # No tasks subdirectory created

    local output
    output=$(run_calculation "$ticket_dir") || { fail_test "No tasks subdir" "calculation failed"; return; }

    local is_empty
    is_empty=$(is_empty_graph "$output")
    if [ "$is_empty" != "yes" ]; then
        fail_test "No tasks subdir" "expected empty graph"
        return
    fi

    pass_test "No tasks subdir"
}

test_nonexistent_directory() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Nonexistent directory returns error ... "

    local exit_code=0
    python3 "$CALC_SCRIPT" "/nonexistent/path/to/ticket" >/dev/null 2>&1 || exit_code=$?

    if [ "$exit_code" -ne 1 ]; then
        fail_test "Nonexistent dir" "expected exit code 1, got $exit_code"
        return
    fi

    pass_test "Nonexistent dir"
}

test_index_files_skipped() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Index files are skipped ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "INDEXSKIP")
    create_task_file "$ticket_dir/tasks" "INDEXSKIP.1001" "regular-task"

    # Create an index file that should be skipped
    cat > "$ticket_dir/tasks/INDEXSKIP_TASK_INDEX.md" << 'EOF'
# Task Index
This is an index file and should be skipped.
EOF

    local output
    output=$(run_calculation "$ticket_dir") || { fail_test "Index skipped" "calculation failed"; return; }

    local tasks_in_phase
    tasks_in_phase=$(get_tasks_in_phase "$output" "1")
    if [ "$tasks_in_phase" != "INDEXSKIP.1001" ]; then
        fail_test "Index skipped" "expected only INDEXSKIP.1001, got '$tasks_in_phase'"
        return
    fi

    pass_test "Index skipped"
}

test_external_deps_ignored() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: External dependencies (not in ticket) are ignored ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "EXTERNAL")
    create_task_file "$ticket_dir/tasks" "EXTERNAL.1001" "has-external-dep" "OTHER.9999"

    local output
    output=$(run_calculation "$ticket_dir") || { fail_test "External deps ignored" "calculation failed"; return; }

    local deps
    deps=$(get_deps_for_task "$output" "EXTERNAL.1001")
    if [ -n "$deps" ]; then
        fail_test "External deps ignored" "external deps should be ignored, got '$deps'"
        return
    fi

    pass_test "External deps ignored"
}

test_phase_zero_support() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Phase 0 tasks have no phase dependencies ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "PHASEZERO")
    create_task_file "$ticket_dir/tasks" "PHASEZERO.0001" "phase-zero-task"
    create_task_file "$ticket_dir/tasks" "PHASEZERO.1001" "phase-one-task"

    local output
    output=$(run_calculation "$ticket_dir") || { fail_test "Phase 0 support" "calculation failed"; return; }

    # Phase 0 task should have no dependencies
    local deps0
    deps0=$(get_deps_for_task "$output" "PHASEZERO.0001")
    if [ -n "$deps0" ]; then
        fail_test "Phase 0 support" "Phase 0 task should have no deps, got '$deps0'"
        return
    fi

    # Phase 1 should depend on Phase 0
    local deps1
    deps1=$(get_deps_for_task "$output" "PHASEZERO.1001")
    if [ "$deps1" != "PHASEZERO.0001" ]; then
        fail_test "Phase 0 support" "Phase 1 should depend on PHASEZERO.0001, got '$deps1'"
        return
    fi

    pass_test "Phase 0 support"
}

test_phases_structure() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Phases structure is correctly populated ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "PHASES")
    create_task_file "$ticket_dir/tasks" "PHASES.1001" "phase-one-a"
    create_task_file "$ticket_dir/tasks" "PHASES.1002" "phase-one-b"
    create_task_file "$ticket_dir/tasks" "PHASES.2001" "phase-two-a"
    create_task_file "$ticket_dir/tasks" "PHASES.3001" "phase-three-a"

    local output
    output=$(run_calculation "$ticket_dir") || { fail_test "Phases structure" "calculation failed"; return; }

    # Check Phase 1 tasks
    local phase1
    phase1=$(get_tasks_in_phase "$output" "1")
    if [ "$phase1" != "PHASES.1001,PHASES.1002" ]; then
        fail_test "Phases structure" "Phase 1 should have 'PHASES.1001,PHASES.1002', got '$phase1'"
        return
    fi

    # Check Phase 2 tasks
    local phase2
    phase2=$(get_tasks_in_phase "$output" "2")
    if [ "$phase2" != "PHASES.2001" ]; then
        fail_test "Phases structure" "Phase 2 should have 'PHASES.2001', got '$phase2'"
        return
    fi

    # Check Phase 3 tasks
    local phase3
    phase3=$(get_tasks_in_phase "$output" "3")
    if [ "$phase3" != "PHASES.3001" ]; then
        fail_test "Phases structure" "Phase 3 should have 'PHASES.3001', got '$phase3'"
        return
    fi

    pass_test "Phases structure"
}

test_complex_dependency_scenario() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Complex scenario with mixed dependencies ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "COMPLEX")
    # Phase 1: Three tasks, 1003 depends on 1001
    create_task_file "$ticket_dir/tasks" "COMPLEX.1001" "foundation"
    create_task_file "$ticket_dir/tasks" "COMPLEX.1002" "parallel-work"
    create_task_file "$ticket_dir/tasks" "COMPLEX.1003" "depends-on-foundation" "COMPLEX.1001"

    # Phase 2: Two tasks, 2002 depends on 2001
    create_task_file "$ticket_dir/tasks" "COMPLEX.2001" "integration"
    create_task_file "$ticket_dir/tasks" "COMPLEX.2002" "finalize" "COMPLEX.2001"

    local output
    output=$(run_calculation "$ticket_dir") || { fail_test "Complex scenario" "calculation failed"; return; }

    # Check independent tasks in Phase 1 (should be 1001 and 1002, not 1003)
    local indep1
    indep1=$(get_independent_in_phase "$output" "1")
    if [ "$indep1" != "COMPLEX.1001,COMPLEX.1002" ]; then
        fail_test "Complex scenario" "Phase 1 independent should be 'COMPLEX.1001,COMPLEX.1002', got '$indep1'"
        return
    fi

    # Check independent tasks in Phase 2 (should be only 2001, not 2002)
    local indep2
    indep2=$(get_independent_in_phase "$output" "2")
    if [ "$indep2" != "COMPLEX.2001" ]; then
        fail_test "Complex scenario" "Phase 2 independent should be 'COMPLEX.2001', got '$indep2'"
        return
    fi

    # Check Phase 2 task 2002 has deps on all Phase 1 + 2001
    local deps_2002
    deps_2002=$(get_deps_for_task "$output" "COMPLEX.2002")
    if [ "$deps_2002" != "COMPLEX.1001,COMPLEX.1002,COMPLEX.1003,COMPLEX.2001" ]; then
        fail_test "Complex scenario" "COMPLEX.2002 should have all deps, got '$deps_2002'"
        return
    fi

    pass_test "Complex scenario"
}

test_dependencies_in_code_blocks_ignored() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Dependencies inside code blocks are ignored ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "CODEBLOCK")
    create_task_file "$ticket_dir/tasks" "CODEBLOCK.1001" "base"

    # Create a task file with dependency mentioned in code block (should be ignored)
    local task_file="$ticket_dir/tasks/CODEBLOCK.1002_with-code.md"
    cat > "$task_file" << 'EOFILE'
# Task: [CODEBLOCK.1002]: Task with code block

## Status
- [ ] **Task completed**

## Summary
This task has a code block example.

## Technical Requirements

Example:
```
## Dependencies
- CODEBLOCK.1001
```

This dependency should be ignored since it's in a code block.

## Dependencies
(none)
EOFILE

    local output
    output=$(run_calculation "$ticket_dir") || { fail_test "Code block deps" "calculation failed"; return; }

    # CODEBLOCK.1002 should have no dependencies (code block dep ignored)
    local deps
    deps=$(get_deps_for_task "$output" "CODEBLOCK.1002")
    if [ -n "$deps" ]; then
        fail_test "Code block deps" "deps in code block should be ignored, got '$deps'"
        return
    fi

    pass_test "Code block deps"
}

test_json_output_format() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Output is valid JSON with required structure ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "FORMAT")
    create_task_file "$ticket_dir/tasks" "FORMAT.1001" "test-task"

    local output
    output=$(run_calculation "$ticket_dir") || { fail_test "JSON format" "calculation failed"; return; }

    # Validate JSON has required keys
    local has_keys
    has_keys=$(echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if 'phases' in data and 'dependencies' in data and 'independent' in data:
    print('yes')
else:
    print('no')
" 2>/dev/null)

    if [ "$has_keys" != "yes" ]; then
        fail_test "JSON format" "output missing required keys (phases, dependencies, independent)"
        return
    fi

    pass_test "JSON format"
}

test_multiple_explicit_deps() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test: Multiple explicit dependencies in one task ... "

    local ticket_dir
    ticket_dir=$(create_test_ticket "MULTIDEP")
    create_task_file "$ticket_dir/tasks" "MULTIDEP.1001" "first"
    create_task_file "$ticket_dir/tasks" "MULTIDEP.1002" "second"
    create_task_file "$ticket_dir/tasks" "MULTIDEP.1003" "third"
    create_task_file "$ticket_dir/tasks" "MULTIDEP.1004" "depends-on-multiple" "MULTIDEP.1001,MULTIDEP.1002,MULTIDEP.1003"

    local output
    output=$(run_calculation "$ticket_dir") || { fail_test "Multiple explicit deps" "calculation failed"; return; }

    local deps
    deps=$(get_deps_for_task "$output" "MULTIDEP.1004")
    if [ "$deps" != "MULTIDEP.1001,MULTIDEP.1002,MULTIDEP.1003" ]; then
        fail_test "Multiple explicit deps" "MULTIDEP.1004 should depend on 1001,1002,1003, got '$deps'"
        return
    fi

    pass_test "Multiple explicit deps"
}

# ============================================================================
# Test Runner
# ============================================================================

run_all_tests() {
    echo -e "${BLUE}=== SDD Dependency Graph Calculator Tests ===${NC}"
    echo ""

    # Simple dependency tests
    echo -e "${YELLOW}--- Simple Dependency Tests ---${NC}"
    test_simple_linear_dependencies
    test_three_phase_chain
    test_multiple_tasks_per_phase

    # Independent task tests
    echo ""
    echo -e "${YELLOW}--- Independent Task Tests ---${NC}"
    test_independent_tasks_same_phase
    test_explicit_dependencies_within_phase
    test_explicit_deps_across_phases

    # Circular dependency tests
    echo ""
    echo -e "${YELLOW}--- Circular Dependency Tests ---${NC}"
    test_circular_dependency_direct
    test_circular_dependency_indirect

    # Edge case tests
    echo ""
    echo -e "${YELLOW}--- Edge Case Tests ---${NC}"
    test_empty_tasks_directory
    test_no_tasks_directory
    test_nonexistent_directory
    test_index_files_skipped
    test_external_deps_ignored

    # Phase structure tests
    echo ""
    echo -e "${YELLOW}--- Phase Structure Tests ---${NC}"
    test_phase_zero_support
    test_phases_structure

    # Complex scenario tests
    echo ""
    echo -e "${YELLOW}--- Complex Scenario Tests ---${NC}"
    test_complex_dependency_scenario
    test_dependencies_in_code_blocks_ignored
    test_multiple_explicit_deps

    # Output format tests
    echo ""
    echo -e "${YELLOW}--- Output Format Tests ---${NC}"
    test_json_output_format

    # Summary
    echo ""
    echo -e "${BLUE}=== Test Summary ===${NC}"
    echo "Tests run: $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

    if [ "$TESTS_FAILED" -gt 0 ]; then
        echo ""
        echo -e "${RED}Some tests failed!${NC}"
        return 1
    else
        echo ""
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    # Trap to ensure cleanup
    trap cleanup EXIT

    # Setup
    setup

    # Verify calculation script exists
    if [ ! -f "$CALC_SCRIPT" ]; then
        echo -e "${RED}Error: calculate-dependency-graph.py not found at $CALC_SCRIPT${NC}"
        exit 1
    fi

    # Run tests
    run_all_tests
    exit_code=$?

    exit $exit_code
}

main
