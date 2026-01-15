#!/usr/bin/env bash
#
# Integration Test for SDD Loop Controller (sdd-loop.sh)
# Tests real Claude Code execution with a test ticket
#
# DESCRIPTION
#   This integration test creates a temporary SDD directory structure with a test
#   ticket, runs sdd-loop.sh with --max-iterations 1, and validates that Claude
#   Code successfully completes the task and updates status checkboxes.
#
# REQUIREMENTS
#   - Claude Code CLI must be installed and accessible
#   - CLAUDE_API_KEY environment variable (or valid ~/.anthropic/credentials)
#   - jq installed for JSON parsing
#
# USAGE
#   ./integration-test-sdd-loop.sh [options]
#
# OPTIONS
#   -h, --help      Show this help message
#   -v, --verbose   Enable verbose output
#   --skip-cleanup  Don't remove test directory after completion (for debugging)
#
# EXIT CODES
#   0 - All tests passed
#   1 - Test failed
#   2 - Prerequisites not met (missing claude, API key, etc.)
#
# NOTES
#   - This test uses real Claude Code and consumes API credits
#   - Typical execution time: 30-90 seconds
#   - Run with --skip-cleanup to inspect test artifacts on failure
#

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

# Script directory for locating sdd-loop.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDD_LOOP_SCRIPT="$SCRIPT_DIR/../sdd-loop.sh"

# Test directory base path
TEST_DIR_BASE="/tmp/sdd-integration-test"

# Test configuration
TEST_TIMEOUT=120  # Maximum time for the integration test (seconds)
TEST_TASK_TIMEOUT=90  # Timeout for sdd-loop.sh task execution

# Test identifiers
TEST_TICKET_ID="TEST"
TEST_TASK_ID="TEST.1001"

# Flags
VERBOSE=false
SKIP_CLEANUP=false

# Test directory (set during setup)
TEST_DIR=""

# =============================================================================
# Logging Functions
# =============================================================================

log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_success() {
    echo "[PASS] $*"
}

log_fail() {
    echo "[FAIL] $*" >&2
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[VERBOSE] $*"
    fi
}

# =============================================================================
# Usage
# =============================================================================

show_usage() {
    cat << 'EOF'
Integration Test for SDD Loop Controller

USAGE
    ./integration-test-sdd-loop.sh [options]

OPTIONS
    -h, --help      Show this help message
    -v, --verbose   Enable verbose output
    --skip-cleanup  Don't remove test directory after completion

REQUIREMENTS
    - Claude Code CLI installed and accessible
    - Valid Claude API credentials
    - jq installed for JSON parsing

EXAMPLES
    # Run integration test
    ./integration-test-sdd-loop.sh

    # Run with verbose output
    ./integration-test-sdd-loop.sh --verbose

    # Debug mode (keep test files)
    ./integration-test-sdd-loop.sh --skip-cleanup --verbose

EXIT CODES
    0 - All tests passed
    1 - Test failed
    2 - Prerequisites not met

EOF
}

# =============================================================================
# Cleanup Handler
# =============================================================================

cleanup() {
    local exit_code=$?

    if [[ -n "$TEST_DIR" && -d "$TEST_DIR" ]]; then
        if [[ "$SKIP_CLEANUP" == "true" ]]; then
            log_info "Skipping cleanup (--skip-cleanup). Test directory: $TEST_DIR"
        else
            log_verbose "Cleaning up test directory: $TEST_DIR"
            rm -rf "$TEST_DIR"
            log_verbose "Cleanup complete"
        fi
    fi

    exit "$exit_code"
}

# Set up trap for cleanup on exit (handles both success and failure)
trap cleanup EXIT

# =============================================================================
# Prerequisite Checks
# =============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."
    local failed=false

    # Check for Claude Code CLI
    if ! command -v claude &>/dev/null; then
        log_error "Claude Code CLI not found. Install from https://claude.ai/download"
        failed=true
    else
        log_verbose "Claude Code CLI found: $(command -v claude)"
    fi

    # Check for jq
    if ! command -v jq &>/dev/null; then
        log_error "jq not found. Install with: apt-get install jq (Debian/Ubuntu) or brew install jq (macOS)"
        failed=true
    else
        log_verbose "jq found: $(command -v jq)"
    fi

    # Check for sdd-loop.sh
    if [[ ! -f "$SDD_LOOP_SCRIPT" ]]; then
        log_error "sdd-loop.sh not found at: $SDD_LOOP_SCRIPT"
        failed=true
    else
        log_verbose "sdd-loop.sh found: $SDD_LOOP_SCRIPT"
    fi

    # Check for API key (optional - claude CLI may have its own auth)
    # We just warn if not set, don't fail
    if [[ -z "${ANTHROPIC_API_KEY:-}" && -z "${CLAUDE_API_KEY:-}" ]]; then
        log_verbose "Note: ANTHROPIC_API_KEY/CLAUDE_API_KEY not set. Claude CLI may use other auth methods."
    fi

    if [[ "$failed" == "true" ]]; then
        log_error "Prerequisites check failed"
        exit 2
    fi

    log_success "Prerequisites check passed"
}

# =============================================================================
# Test Setup
# =============================================================================

setup_test_environment() {
    log_info "Setting up test environment..."

    # Create unique test directory with timestamp
    local timestamp
    timestamp=$(date '+%Y%m%d-%H%M%S')
    TEST_DIR="${TEST_DIR_BASE}-${timestamp}-$$"

    log_verbose "Creating test directory: $TEST_DIR"
    mkdir -p "$TEST_DIR"

    # Create SDD directory structure
    local sdd_root="$TEST_DIR/_SDD"
    local ticket_dir="$sdd_root/tickets/${TEST_TICKET_ID}_integration-test"
    local tasks_dir="$ticket_dir/tasks"

    mkdir -p "$tasks_dir"
    log_verbose "Created SDD structure: $sdd_root"

    # Create .autogate.json to enable agent processing
    cat > "$ticket_dir/.autogate.json" << 'EOF'
{
    "ready": true,
    "agent_ready": true
}
EOF
    log_verbose "Created .autogate.json"

    # Create the test task file
    # The task asks Claude to create a simple file - deterministic and easy to verify
    local output_file="$TEST_DIR/integration-test-output.txt"

    cat > "$tasks_dir/${TEST_TASK_ID}_simple-integration-test.md" << EOF
# Task: [${TEST_TASK_ID}]: Simple Integration Test Task

## Status
- [ ] **Task completed** - acceptance criteria met
- [ ] **Tests pass** - N/A (no tests for this task)
- [ ] **Verified** - by the verify-task agent

## Agents
- general-purpose

## Summary
Create a test file to validate the SDD loop integration test.

## Acceptance Criteria
- [ ] File ${output_file} exists
- [ ] File contains exactly the text "Integration test success"

## Technical Requirements
Create the file ${output_file} with the content "Integration test success" (without quotes).

This is a simple, deterministic task for integration testing. Do not add any extra content.

## Files/Packages Affected
- ${output_file} (new)
EOF
    log_verbose "Created test task: $tasks_dir/${TEST_TASK_ID}_simple-integration-test.md"

    # Create a minimal master-status-board.sh mock that returns our test task
    # This is needed because the real master-status-board.sh scans for _SDD directories
    # and we want to ensure our test task is picked up

    # Actually, we'll use the real master-status-board.sh but need to ensure
    # our test directory is set up correctly for it to find

    log_success "Test environment setup complete"
    log_verbose "Test directory: $TEST_DIR"
    log_verbose "SDD root: $sdd_root"
    log_verbose "Expected output file: $output_file"
}

# =============================================================================
# Test Execution
# =============================================================================

run_sdd_loop() {
    log_info "Running sdd-loop.sh with test ticket..."

    local sdd_root="$TEST_DIR/_SDD"
    local exit_code=0
    local output

    log_verbose "Executing: bash $SDD_LOOP_SCRIPT --max-iterations 1 --timeout $TEST_TASK_TIMEOUT $TEST_DIR"

    # Run sdd-loop.sh with:
    # - max-iterations 1: Only process one task
    # - timeout: Limit execution time
    # - Point to our test directory
    #
    # We capture both stdout and stderr
    # We use timeout to prevent runaway execution
    output=$(timeout "$TEST_TIMEOUT" bash "$SDD_LOOP_SCRIPT" \
        --max-iterations 1 \
        --timeout "$TEST_TASK_TIMEOUT" \
        "$TEST_DIR" 2>&1) || exit_code=$?

    log_verbose "sdd-loop.sh output:"
    if [[ "$VERBOSE" == "true" ]]; then
        echo "$output" | sed 's/^/    /'
    fi

    # Save output for later analysis
    echo "$output" > "$TEST_DIR/sdd-loop-output.log"

    # Check exit code
    # Note: exit code 0 means success or no work available
    #       exit code 1 could mean error or max iterations reached
    if [[ $exit_code -eq 0 ]]; then
        log_verbose "sdd-loop.sh exited with code 0 (success or no work)"
    elif [[ $exit_code -eq 124 ]]; then
        log_error "sdd-loop.sh timed out after $TEST_TIMEOUT seconds"
        return 1
    else
        log_verbose "sdd-loop.sh exited with code $exit_code"
    fi

    return 0
}

# =============================================================================
# Validation
# =============================================================================

validate_task_completion() {
    log_info "Validating task completion..."
    local passed=true

    local output_file="$TEST_DIR/integration-test-output.txt"
    local task_file="$TEST_DIR/_SDD/tickets/${TEST_TICKET_ID}_integration-test/tasks/${TEST_TASK_ID}_simple-integration-test.md"

    # Check 1: Output file exists
    log_verbose "Checking if output file exists: $output_file"
    if [[ -f "$output_file" ]]; then
        log_success "Output file exists"
    else
        log_fail "Output file does not exist: $output_file"
        passed=false
    fi

    # Check 2: Output file has correct content
    if [[ -f "$output_file" ]]; then
        local content
        content=$(cat "$output_file")
        log_verbose "Output file content: '$content'"

        if [[ "$content" == "Integration test success" ]]; then
            log_success "Output file has correct content"
        else
            log_fail "Output file content mismatch. Expected: 'Integration test success', Got: '$content'"
            passed=false
        fi
    fi

    # Check 3: Task status checkbox is checked
    log_verbose "Checking task status checkbox in: $task_file"
    if [[ -f "$task_file" ]]; then
        if grep -q '\- \[x\] \*\*Task completed\*\*' "$task_file"; then
            log_success "Task completed checkbox is checked"
        else
            log_verbose "Task file content:"
            if [[ "$VERBOSE" == "true" ]]; then
                head -20 "$task_file" | sed 's/^/    /'
            fi
            log_fail "Task completed checkbox is NOT checked"
            passed=false
        fi
    else
        log_fail "Task file not found: $task_file"
        passed=false
    fi

    # Check 4: Verify sdd-loop output shows task execution
    local loop_output="$TEST_DIR/sdd-loop-output.log"
    if [[ -f "$loop_output" ]]; then
        if grep -q "execute task\|Executing task\|do-task" "$loop_output"; then
            log_success "sdd-loop.sh output shows task execution"
        else
            log_verbose "sdd-loop.sh output did not show task execution"
            # This is a warning, not a failure - the task might still have completed
        fi
    fi

    if [[ "$passed" == "true" ]]; then
        log_success "All validations passed"
        return 0
    else
        log_fail "Some validations failed"
        return 1
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --skip-cleanup)
                SKIP_CLEANUP=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information" >&2
                exit 2
                ;;
        esac
    done

    echo "========================================"
    echo "SDD Loop Controller Integration Test"
    echo "========================================"
    echo ""

    # Run test phases
    check_prerequisites
    echo ""

    setup_test_environment
    echo ""

    if ! run_sdd_loop; then
        log_fail "sdd-loop.sh execution failed"
        exit 1
    fi
    echo ""

    if ! validate_task_completion; then
        log_fail "Task validation failed"
        echo ""
        echo "Test directory preserved at: $TEST_DIR"
        echo "Review logs with: cat $TEST_DIR/sdd-loop-output.log"
        exit 1
    fi
    echo ""

    echo "========================================"
    echo "Integration Test: PASSED"
    echo "========================================"
    exit 0
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
