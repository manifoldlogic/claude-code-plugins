#!/usr/bin/env bash
#
# SDD Loop Controller ("Ralph Wiggum Loop")
# Autonomous SDD workflow controller for multi-repository development
#
# Version: 1.0.0
#
# DESCRIPTION
#   Polls master-status-board.sh for recommended tasks and executes them via
#   Claude Code CLI in an automated loop. The controller continues processing
#   until no more agent-ready work remains, safety limits are reached, or a
#   phase boundary is hit.
#
# USAGE
#   sdd-loop.sh [options] [workspace_root]
#
# OPTIONS
#   -h, --help              Show full help message and exit
#   -V, --version           Show version information and exit
#   -n, --dry-run           Preview actions without executing Claude Code
#   -v, --verbose           Enable verbose output with progress details
#   -q, --quiet             Suppress informational messages (errors only)
#   --debug                 Enable debug-level logging (very verbose)
#   --max-iterations N      Maximum task iterations before stopping (default: 50)
#   --max-errors N          Maximum consecutive errors before stopping (default: 3)
#   --timeout SECONDS       Task execution timeout in seconds (default: 3600)
#   --poll-interval SECONDS Interval between status polls (default: 5)
#
# ARGUMENTS
#   workspace_root    Root directory containing repositories with _SDD directories
#                     Priority: CLI argument > SDD_LOOP_WORKSPACE_ROOT env var > default
#                     Default: /workspace/repos/
#
# ENVIRONMENT VARIABLES
#   SDD_LOOP_WORKSPACE_ROOT   Default workspace root directory
#   SDD_LOOP_MAX_ITERATIONS   Maximum iterations (default: 50)
#   SDD_LOOP_MAX_ERRORS       Maximum consecutive errors (default: 3)
#   SDD_LOOP_TIMEOUT          Task timeout in seconds (default: 3600)
#   SDD_LOOP_POLL_INTERVAL    Poll interval in seconds (default: 5)
#   SDD_LOOP_DRY_RUN          Set to "true" for dry-run mode
#   SDD_LOOP_VERBOSE          Set to "true" for verbose output
#   SDD_LOOP_QUIET            Set to "true" for quiet mode
#   SDD_LOOP_DEBUG            Set to "true" for debug output
#
# EXIT CODES
#   0   - Success (all work completed or no work remaining)
#   1   - Error (task failure, max limits reached, missing dependencies)
#   2   - Usage error (invalid arguments or options)
#   130 - Interrupted by SIGINT (Ctrl+C)
#   143 - Terminated by SIGTERM
#
# EXAMPLES
#   # Basic usage - run against default workspace
#   sdd-loop.sh
#
#   # Dry-run mode to preview actions without executing
#   sdd-loop.sh --dry-run /workspace/repos/
#
#   # Custom safety limits for testing
#   sdd-loop.sh --max-iterations 10 --max-errors 5 /workspace/repos/
#
#   # Configure via environment variables
#   export SDD_LOOP_MAX_ITER=100
#   export SDD_LOOP_TIMEOUT=7200
#   sdd-loop.sh /workspace/repos/
#
#   # CI/CD integration with quiet mode
#   sdd-loop.sh --quiet --max-iterations 50 /workspace/repos/ || {
#       echo "Loop failed with exit code $?"
#       exit 1
#   }
#
# INTEGRATION
#   The loop controller integrates with:
#   - master-status-board.sh: Provides recommended_action JSON
#   - Claude Code CLI: Executes /sdd:do-task commands
#   - .autogate.json: Reads agent_ready and stop_at_phase settings
#
# SEE ALSO
#   sdd-loop-examples.md - Comprehensive usage examples and patterns
#   master-status-board.sh - Status board scanner
#   See --help for full documentation.
#

set -euo pipefail

# Version constant
VERSION="1.0.0"

# =============================================================================
# Configuration Defaults
# =============================================================================

# Default workspace root for repository scanning
[[ -z "${SDD_LOOP_DEFAULT_WORKSPACE_ROOT:-}" ]] && readonly SDD_LOOP_DEFAULT_WORKSPACE_ROOT="/workspace/repos/"

# Maximum number of task iterations before stopping (safety limit)
[[ -z "${SDD_LOOP_DEFAULT_MAX_ITERATIONS:-}" ]] && readonly SDD_LOOP_DEFAULT_MAX_ITERATIONS=50

# Maximum consecutive errors before stopping
[[ -z "${SDD_LOOP_DEFAULT_MAX_ERRORS:-}" ]] && readonly SDD_LOOP_DEFAULT_MAX_ERRORS=3

# Task execution timeout in seconds
[[ -z "${SDD_LOOP_DEFAULT_TIMEOUT:-}" ]] && readonly SDD_LOOP_DEFAULT_TIMEOUT=3600

# Poll interval in seconds between status board checks
[[ -z "${SDD_LOOP_DEFAULT_POLL_INTERVAL:-}" ]] && readonly SDD_LOOP_DEFAULT_POLL_INTERVAL=5

# =============================================================================
# Global State (configurable via env vars and CLI args)
# =============================================================================

# Workspace root directory
SDD_LOOP_WORKSPACE_ROOT="${SDD_LOOP_WORKSPACE_ROOT:-}"

# Maximum iterations (0 = unlimited)
SDD_LOOP_MAX_ITERATIONS="${SDD_LOOP_MAX_ITERATIONS:-}"

# Maximum consecutive errors
SDD_LOOP_MAX_ERRORS="${SDD_LOOP_MAX_ERRORS:-}"

# Task timeout in seconds
SDD_LOOP_TIMEOUT="${SDD_LOOP_TIMEOUT:-}"

# Poll interval in seconds
SDD_LOOP_POLL_INTERVAL="${SDD_LOOP_POLL_INTERVAL:-}"

# Dry run mode - log actions without executing
SDD_LOOP_DRY_RUN="${SDD_LOOP_DRY_RUN:-false}"

# Verbose mode - extra logging
SDD_LOOP_VERBOSE="${SDD_LOOP_VERBOSE:-false}"

# Quiet mode - minimal output
SDD_LOOP_QUIET="${SDD_LOOP_QUIET:-false}"

# Debug mode - debug-level logging
SDD_LOOP_DEBUG="${SDD_LOOP_DEBUG:-false}"

# Log format - "text" (default) or "json" for structured logging
SDD_LOOP_LOG_FORMAT="${SDD_LOOP_LOG_FORMAT:-text}"

# =============================================================================
# Internal State
# =============================================================================

# Script directory for locating master-status-board.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Iteration counter
ITERATION_COUNT=0

# Consecutive error counter
CONSECUTIVE_ERRORS=0

# Exit flag for signal handling
EXIT_REQUESTED=false

# Exit code to use when exiting
EXIT_CODE=0

# Tasks completed counter
TASKS_COMPLETED=0

# Flag to suppress cleanup output during help/version
HELP_SHOWN=""

# Poll result state (set by poll_status function)
POLL_ACTION=""
POLL_TASK=""
POLL_TICKET=""
POLL_SDD_ROOT=""
POLL_REASON=""

# Phase boundary state (set by check_phase_boundary function)
STOP_AT_PHASE=""

# Claude Code process PID (for cleanup on signal)
CLAUDE_PID=""

# Flag to prevent re-entry into cleanup function
CLEANUP_IN_PROGRESS=false

# =============================================================================
# Logging Functions
# =============================================================================

#######################################
# Format and output a JSON log entry
# Used internally by log_* functions when SDD_LOOP_LOG_FORMAT is "json"
#
# Arguments:
#   $1 - level: Log level (INFO, ERROR, WARN, VERBOSE, DEBUG)
#   $2 - message: Log message text
#
# Outputs:
#   Single-line JSON to stderr with format:
#   {"timestamp":"ISO8601","level":"LEVEL","message":"...","context":{...}}
#
# Notes:
#   - Uses jq for safe JSON string escaping
#   - Timestamp is UTC in ISO 8601 format
#   - Context object includes iteration, task_id, ticket_id, consecutive_errors
#     when those values are available
#######################################
format_json_log() {
    local level="$1"
    local message="$2"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Use jq to safely escape the message string
    local msg_json
    msg_json=$(jq -n --arg msg "$message" '$msg')

    # Build context object with available fields
    local context_fields=""

    # Add iteration count if available
    if [[ -n "${ITERATION_COUNT:-}" && "$ITERATION_COUNT" -gt 0 ]]; then
        context_fields="\"iteration\":$ITERATION_COUNT"
    fi

    # Add task_id if available
    if [[ -n "${POLL_TASK:-}" ]]; then
        if [[ -n "$context_fields" ]]; then
            context_fields="$context_fields,"
        fi
        local task_json
        task_json=$(jq -n --arg t "$POLL_TASK" '$t')
        context_fields="${context_fields}\"task_id\":$task_json"
    fi

    # Add ticket_id if available
    if [[ -n "${POLL_TICKET:-}" ]]; then
        if [[ -n "$context_fields" ]]; then
            context_fields="$context_fields,"
        fi
        local ticket_json
        ticket_json=$(jq -n --arg t "$POLL_TICKET" '$t')
        context_fields="${context_fields}\"ticket_id\":$ticket_json"
    fi

    # Add consecutive_errors if available and > 0
    if [[ -n "${CONSECUTIVE_ERRORS:-}" && "$CONSECUTIVE_ERRORS" -gt 0 ]]; then
        if [[ -n "$context_fields" ]]; then
            context_fields="$context_fields,"
        fi
        context_fields="${context_fields}\"consecutive_errors\":$CONSECUTIVE_ERRORS"
    fi

    # Build the final JSON output
    local context_json=""
    if [[ -n "$context_fields" ]]; then
        context_json=",\"context\":{$context_fields}"
    fi

    echo "{\"timestamp\":\"$timestamp\",\"level\":\"$level\",\"message\":$msg_json$context_json}" >&2
}

#######################################
# Log an informational message to stderr
# Arguments:
#   $@ - Message to print
# Outputs:
#   Writes timestamped message to stderr (text or JSON format)
#######################################
log_info() {
    if [[ "$SDD_LOOP_QUIET" != "true" ]]; then
        if [[ "$SDD_LOOP_LOG_FORMAT" == "json" ]]; then
            format_json_log "INFO" "$*"
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" >&2
        fi
    fi
}

#######################################
# Log an error message to stderr
# Arguments:
#   $@ - Message to print
# Outputs:
#   Writes timestamped error message to stderr (text or JSON format)
#######################################
log_error() {
    if [[ "$SDD_LOOP_LOG_FORMAT" == "json" ]]; then
        format_json_log "ERROR" "$*"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
    fi
}

#######################################
# Log a warning message to stderr
# Arguments:
#   $@ - Message to print
# Outputs:
#   Writes timestamped warning message to stderr (text or JSON format)
#######################################
log_warn() {
    if [[ "$SDD_LOOP_QUIET" != "true" ]]; then
        if [[ "$SDD_LOOP_LOG_FORMAT" == "json" ]]; then
            format_json_log "WARN" "$*"
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*" >&2
        fi
    fi
}

#######################################
# Log a verbose message to stderr (only if verbose mode enabled and not quiet)
# Arguments:
#   $@ - Message to print
# Outputs:
#   Writes timestamped message to stderr if verbose mode is enabled and quiet is disabled (text or JSON format)
#######################################
log_verbose() {
    [[ "$SDD_LOOP_VERBOSE" != "true" || "$SDD_LOOP_QUIET" == "true" ]] && return
    if [[ "$SDD_LOOP_LOG_FORMAT" == "json" ]]; then
        format_json_log "VERBOSE" "$*"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [VERBOSE] $*" >&2
    fi
}

#######################################
# Log a debug message to stderr (only if debug mode enabled)
# Arguments:
#   $@ - Message to print
# Outputs:
#   Writes timestamped message to stderr if debug mode is enabled (text or JSON format)
#######################################
log_debug() {
    if [[ "$SDD_LOOP_DEBUG" == "true" ]]; then
        if [[ "$SDD_LOOP_LOG_FORMAT" == "json" ]]; then
            format_json_log "DEBUG" "$*"
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $*" >&2
        fi
    fi
}

# =============================================================================
# JSON Helper Functions
# =============================================================================

#######################################
# Extract JSON field with jq, returning default if field is null/missing
# This helper reduces code duplication in JSON parsing operations.
#
# Arguments:
#   $1 - json: String containing JSON data
#   $2 - field_path: jq query path (e.g., ".recommended_action.action")
#   $3 - default: Default value if field not found or null (optional, defaults to "")
#
# Outputs:
#   Extracted field value or default to stdout
#
# Returns:
#   Always returns 0 (errors suppressed, default returned on failure)
#######################################
parse_json_field() {
    local json="$1"
    local field_path="$2"
    local default="${3:-}"
    echo "$json" | jq -r "$field_path // \"$default\"" 2>/dev/null
}

# =============================================================================
# Core Functions (Skeletons for Phase 1)
# =============================================================================

#######################################
# Poll master-status-board.sh for recommended action
# Invokes the master status board script to scan the workspace and
# determine the next recommended task based on autogate configuration.
#
# Arguments:
#   $1 - Workspace root directory
#
# Globals Set:
#   POLL_ACTION   - Recommended action (e.g., "do-task", "none")
#   POLL_TASK     - Task ID to execute (e.g., "TICKET.1001")
#   POLL_TICKET   - Ticket ID containing the task
#   POLL_SDD_ROOT - SDD root directory path
#   POLL_REASON   - Human-readable reason for recommendation
#
# Outputs:
#   JSON output from master-status-board.sh to stdout
#
# Returns:
#   0 - Success (JSON parsed successfully)
#   1 - JSON parse error (jq failed or malformed JSON)
#   2 - master-status-board.sh execution failed
#
# Version Compatibility:
#   Extracts and validates the "version" field from status board JSON output.
#   Expected version: 1.0.0 (semantic versioning: MAJOR.MINOR.PATCH)
#   - Logs warning if version mismatches or is missing (falls back to "unknown")
#   - Version mismatch does NOT fail execution (graceful degradation)
#   - MAJOR changes indicate breaking schema changes
#   - MINOR changes indicate backward-compatible additions
#   - PATCH changes indicate bug fixes with no schema changes
#######################################
poll_status() {
    local workspace_root="$1"

    log_debug "poll_status: Polling status board for workspace: $workspace_root"

    # Reset poll result state
    POLL_ACTION=""
    POLL_TASK=""
    POLL_TICKET=""
    POLL_SDD_ROOT=""
    POLL_REASON=""

    # Check if jq is installed (required for JSON parsing)
    if ! command -v jq &>/dev/null; then
        log_error "jq not found. Install with: apt-get install jq (Debian/Ubuntu) or brew install jq (macOS)"
        return 1
    fi

    # Build path to master-status-board.sh
    # The script is in the same directory as sdd-loop.sh
    local status_board_script="$SCRIPT_DIR/master-status-board.sh"

    # Verify script exists and is executable
    if [[ ! -f "$status_board_script" ]]; then
        log_error "master-status-board.sh not found: $status_board_script"
        return 2
    fi

    if [[ ! -x "$status_board_script" ]]; then
        # Try to make it executable, or warn user
        log_debug "poll_status: master-status-board.sh not executable, will invoke with bash"
    fi

    log_debug "poll_status: Executing: bash $status_board_script --json $workspace_root"

    # Execute master-status-board.sh with --json flag and capture output
    local status_output
    local exit_code=0
    status_output=$(bash "$status_board_script" --json "$workspace_root" 2>&1) || exit_code=$?

    # Check if master-status-board.sh failed
    if [[ $exit_code -ne 0 ]]; then
        log_error "master-status-board.sh failed with exit code $exit_code"
        log_debug "poll_status: Output was: $status_output"
        return 2
    fi

    # Validate that output is valid JSON
    if ! echo "$status_output" | jq empty 2>/dev/null; then
        log_error "master-status-board.sh returned invalid JSON"
        log_debug "poll_status: Output was: $status_output"
        return 1
    fi

    # ==========================================================================
    # Version Compatibility Check
    # Extract version field and validate before parsing other fields
    # ==========================================================================
    local status_version
    status_version=$(parse_json_field "$status_output" ".version" "unknown")
    local expected_version="1.0.0"

    if [[ "$status_version" != "$expected_version" ]]; then
        log_warn "Status board version mismatch: $status_version (expected $expected_version)"
        log_debug "poll_status: Version check - actual=$status_version, expected=$expected_version"
    else
        log_debug "poll_status: Version check passed - $status_version"
    fi

    # Parse JSON using helper function to extract recommended_action fields
    # The parse_json_field helper handles errors gracefully and returns defaults
    POLL_ACTION=$(parse_json_field "$status_output" ".recommended_action.action" "")
    POLL_TASK=$(parse_json_field "$status_output" ".recommended_action.task" "")
    POLL_TICKET=$(parse_json_field "$status_output" ".recommended_action.ticket" "")
    POLL_SDD_ROOT=$(parse_json_field "$status_output" ".recommended_action.sdd_root" "")
    POLL_REASON=$(parse_json_field "$status_output" ".recommended_action.reason" "")

    # Log poll results at verbose level (compact summary)
    log_verbose "Poll returned: action=$POLL_ACTION, task=$POLL_TASK"
    # Detailed breakdown follows
    if [[ -n "$POLL_TICKET" ]]; then
        log_verbose "  Ticket: $POLL_TICKET"
    fi
    if [[ -n "$POLL_SDD_ROOT" ]]; then
        log_verbose "  SDD Root: $POLL_SDD_ROOT"
    fi
    if [[ -n "$POLL_REASON" ]]; then
        log_verbose "  Reason: $POLL_REASON"
    fi

    # Output the full JSON to stdout for potential downstream use
    echo "$status_output"

    return 0
}

#######################################
# Execute a single task via Claude Code CLI
# Invokes Claude Code with the /sdd:do-task command, setting up
# the appropriate environment variables and working directory.
#
# Arguments:
#   $1 - Task ID (e.g., "TICKET-1.1001")
#   $2 - SDD root directory (e.g., "/workspace/repos/project/_SDD")
#
# Environment:
#   SDD_ROOT_DIR is set to the sdd_root parameter for Claude Code
#   Working directory is set to the repo root (parent of _SDD)
#
# Outputs:
#   Logs execution progress to stderr
#   Claude Code output goes to stdout/stderr
#
# Returns:
#   0 on success
#   1 on error (invalid task ID, claude not found, execution failure)
#######################################
execute_task() {
    local task_id="$1"
    local sdd_root="$2"

    log_debug "execute_task: task_id=$task_id, sdd_root=$sdd_root"

    # ==========================================================================
    # Step 1: Validate task ID format (CRITICAL for security)
    # Pattern: TICKET-ID.NNNN where TICKET-ID is uppercase alphanumeric with dashes
    # Examples: SDDLOOP-3.1001, TICKET.1001, PROJECT-ABC.2005
    # ==========================================================================
    if [[ ! "$task_id" =~ ^[A-Z][A-Z0-9]*(-[A-Z0-9]+)*\.[0-9]+$ ]]; then
        log_error "Invalid task ID format: $task_id"
        return 1
    fi

    # ==========================================================================
    # Step 2: Validate sdd_root parameter
    # ==========================================================================
    if [[ -z "$sdd_root" ]]; then
        log_error "SDD root directory not specified"
        return 1
    fi

    if [[ ! -d "$sdd_root" ]]; then
        log_error "SDD root directory does not exist: $sdd_root"
        return 1
    fi

    # ==========================================================================
    # Step 2.5: Validate sdd_root is within workspace boundaries (defense in depth)
    # Prevents path traversal attacks if master-status-board returns malformed data
    # ==========================================================================
    local canonical_workspace
    local canonical_sdd_root

    # Resolve canonical paths using realpath (preferred) or readlink -f (fallback)
    if command -v realpath &>/dev/null; then
        canonical_workspace="$(realpath "$SDD_LOOP_WORKSPACE_ROOT" 2>/dev/null)" || {
            log_error "Failed to resolve canonical path for workspace: $SDD_LOOP_WORKSPACE_ROOT"
            return 1
        }
        canonical_sdd_root="$(realpath "$sdd_root" 2>/dev/null)" || {
            log_error "Failed to resolve canonical path for SDD root: $sdd_root"
            return 1
        }
    elif command -v readlink &>/dev/null && readlink -f / &>/dev/null; then
        # readlink -f is available (GNU coreutils)
        canonical_workspace="$(readlink -f "$SDD_LOOP_WORKSPACE_ROOT" 2>/dev/null)" || {
            log_error "Failed to resolve canonical path for workspace: $SDD_LOOP_WORKSPACE_ROOT"
            return 1
        }
        canonical_sdd_root="$(readlink -f "$sdd_root" 2>/dev/null)" || {
            log_error "Failed to resolve canonical path for SDD root: $sdd_root"
            return 1
        }
    else
        log_error "Neither realpath nor readlink -f available for path canonicalization"
        return 1
    fi

    # Remove trailing slashes for consistent comparison
    canonical_workspace="${canonical_workspace%/}"
    canonical_sdd_root="${canonical_sdd_root%/}"

    log_debug "execute_task: canonical_workspace=$canonical_workspace"
    log_debug "execute_task: canonical_sdd_root=$canonical_sdd_root"

    # Validate sdd_root is a proper subdirectory of workspace (not equal to workspace)
    # Pattern: sdd_root must start with workspace path followed by "/"
    if [[ "$canonical_sdd_root" != "$canonical_workspace"/* ]]; then
        log_error "SDD root outside workspace bounds: $sdd_root (workspace: $SDD_LOOP_WORKSPACE_ROOT)"
        log_debug "execute_task: Canonical paths - sdd_root=$canonical_sdd_root, workspace=$canonical_workspace"
        return 1
    fi

    log_debug "execute_task: Path bounds validation passed"

    # ==========================================================================
    # Step 3: Extract repo path from sdd_root (remove /_SDD suffix)
    # ==========================================================================
    local repo_path
    repo_path="${sdd_root%/_SDD}"
    repo_path="${repo_path%/}"  # Remove trailing slash if present

    # Validate repo path exists
    if [[ ! -d "$repo_path" ]]; then
        log_error "Repository directory does not exist: $repo_path"
        return 1
    fi

    log_debug "execute_task: repo_path=$repo_path"

    # ==========================================================================
    # Step 4: Check dry-run mode (skip execution, just log)
    # ==========================================================================
    if [[ "$SDD_LOOP_DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would execute task: $task_id"
        log_info "[DRY-RUN] Command: SDD_ROOT_DIR=\"$sdd_root\" claude --dangerously-skip-permissions -p \"/sdd:do-task $task_id\""
        log_info "[DRY-RUN] Working directory: $repo_path"
        return 0
    fi

    # ==========================================================================
    # Step 5: Check claude CLI availability
    # ==========================================================================
    if ! command -v claude &>/dev/null; then
        log_error "claude CLI not found. Install Claude Code from https://claude.ai/download"
        return 1
    fi

    # ==========================================================================
    # Step 5b: Check timeout command availability
    # ==========================================================================
    if ! command -v timeout &>/dev/null; then
        log_error "timeout command not found. Install GNU coreutils (apt-get install coreutils or brew install coreutils)"
        return 1
    fi

    # ==========================================================================
    # Step 6: Log execution start
    # ==========================================================================
    local task_timeout="${SDD_LOOP_TIMEOUT:-$SDD_LOOP_DEFAULT_TIMEOUT}"
    log_info "Executing task: $task_id (repo: $repo_path, timeout: ${task_timeout}s)"

    # ==========================================================================
    # Step 7: Execute claude with correct environment, working directory, and timeout
    # ==========================================================================
    local exit_code=0

    # Change to repo directory and execute claude with SDD_ROOT_DIR set
    # Using subshell to avoid changing cwd in the main script
    # Wrap with timeout command to enforce task execution time limit
    # Run in background and capture PID for cleanup on signal
    (
        cd "$repo_path" || exit 1
        timeout "$task_timeout" env SDD_ROOT_DIR="$sdd_root" claude --dangerously-skip-permissions -p "/sdd:do-task $task_id"
    ) &
    CLAUDE_PID=$!
    log_debug "execute_task: Started Claude process with PID: $CLAUDE_PID"

    # Wait for the backgrounded process to complete
    wait "$CLAUDE_PID"
    exit_code=$?

    # Clear PID after process completes (no longer running)
    log_debug "execute_task: Claude process (PID: $CLAUDE_PID) exited with code: $exit_code"
    CLAUDE_PID=""

    # ==========================================================================
    # Step 8: Log execution completion with exit code
    # ==========================================================================
    if [[ $exit_code -eq 0 ]]; then
        log_info "Task completed successfully: $task_id (exit code: $exit_code)"
    elif [[ $exit_code -eq 124 ]]; then
        log_error "Task timed out after $task_timeout seconds: $task_id"
    elif [[ $exit_code -eq 137 ]]; then
        log_error "Task killed by timeout (SIGKILL) after $task_timeout seconds: $task_id"
    else
        log_error "Task execution failed with exit code $exit_code: $task_id"
    fi

    # ==========================================================================
    # Step 9: Return exit code to caller
    # ==========================================================================
    return $exit_code
}

#######################################
# Check if phase boundary has been reached based on .autogate.json
# Reads stop_at_phase from the ticket's .autogate.json file and compares
# it with the current task's phase number.
#
# Arguments:
#   $1 - Ticket ID (e.g., "SDDLOOP-3")
#   $2 - Task ID (e.g., "SDDLOOP-3.1001")
#   $3 - SDD root directory (e.g., "/workspace/repos/project/_SDD")
#
# Globals Set:
#   STOP_AT_PHASE - The stop_at_phase value from .autogate.json (for logging)
#
# Returns:
#   0 - Continue (no limit, or current phase < stop_at_phase)
#   1 - Should stop (current phase >= stop_at_phase)
#
# Error Handling (graceful - default to continue):
#   - Missing .autogate.json: Log verbose, return 0
#   - Invalid JSON: Log warning, return 0
#   - Invalid task ID format: Log warning, return 0
#   - stop_at_phase not a number: Log warning, return 0
#
# Note: Phase extraction handles single-digit phases only (1-9).
#       Task ID format: TICKET.XYYY where X is phase number (1-9).
#       Phases 10+ would require regex update (unlikely in practice).
#######################################
check_phase_boundary() {
    local ticket_id="$1"
    local task_id="$2"
    local sdd_root="$3"

    log_debug "check_phase_boundary: ticket_id=$ticket_id, task_id=$task_id, sdd_root=$sdd_root"

    # Reset global state
    STOP_AT_PHASE=""

    # ==========================================================================
    # Step 1: Find ticket directory
    # ==========================================================================
    local ticket_dir
    ticket_dir=$(find "$sdd_root/tickets" -maxdepth 1 -type d -name "${ticket_id}_*" 2>/dev/null | head -n1)

    if [[ -z "$ticket_dir" ]]; then
        log_verbose "check_phase_boundary: Ticket directory not found for $ticket_id"
        return 0  # Continue - no limit
    fi

    log_debug "check_phase_boundary: Found ticket directory: $ticket_dir"

    # ==========================================================================
    # Step 2: Check if .autogate.json exists
    # ==========================================================================
    local autogate_file="$ticket_dir/.autogate.json"

    if [[ ! -f "$autogate_file" ]]; then
        log_verbose "check_phase_boundary: No .autogate.json found at $autogate_file"
        return 0  # Continue - no limit
    fi

    # ==========================================================================
    # Step 3: Parse stop_at_phase from .autogate.json
    # ==========================================================================
    local stop_at_phase

    # Check if jq is available
    if ! command -v jq &>/dev/null; then
        log_warn "check_phase_boundary: jq not found, cannot parse .autogate.json"
        return 0  # Continue - no limit
    fi

    # Parse JSON and extract stop_at_phase
    # Use jq with error suppression and null handling
    # Note: Use || jq_exit_code=$? pattern to capture exit code without triggering set -e
    local jq_exit_code=0
    stop_at_phase=$(jq -r '.stop_at_phase // empty' "$autogate_file" 2>/dev/null) || jq_exit_code=$?

    if [[ $jq_exit_code -ne 0 ]]; then
        log_error "Failed to parse .autogate.json at $autogate_file (invalid JSON format). Phase boundary checking disabled - loop will continue indefinitely."
        return 0  # Continue - no limit
    fi

    # If stop_at_phase is empty or null, no limit is set
    if [[ -z "$stop_at_phase" ]]; then
        log_verbose "check_phase_boundary: stop_at_phase not set in $autogate_file"
        return 0  # Continue - no limit
    fi

    # Validate stop_at_phase is a positive integer
    if ! [[ "$stop_at_phase" =~ ^[0-9]+$ ]]; then
        log_warn "check_phase_boundary: stop_at_phase is not a valid number: $stop_at_phase"
        return 0  # Continue - no limit
    fi

    # Set global for logging
    STOP_AT_PHASE="$stop_at_phase"
    log_debug "check_phase_boundary: stop_at_phase=$stop_at_phase"

    # ==========================================================================
    # Step 4: Extract phase number from task ID
    # ==========================================================================
    # Task ID format: TICKET.XYYY where X is phase number (1-9)
    # Examples: SDDLOOP-3.1001 -> phase 1, TICKET.2005 -> phase 2
    local phase
    phase=$(echo "$task_id" | sed -n 's/.*\.\([0-9]\)[0-9]\{3\}/\1/p')

    if [[ -z "$phase" ]]; then
        log_warn "check_phase_boundary: Could not extract phase from task ID: $task_id"
        return 0  # Continue - no limit
    fi

    log_debug "check_phase_boundary: current phase=$phase, stop_at_phase=$stop_at_phase"

    # Log verbose for user visibility
    log_verbose "Checking phase boundary: phase=$phase, stop_at_phase=$stop_at_phase"

    # ==========================================================================
    # Step 5: Compare phase with stop_at_phase
    # ==========================================================================
    # Stop if current_phase >= stop_at_phase
    if [[ "$phase" -ge "$stop_at_phase" ]]; then
        log_debug "check_phase_boundary: Phase boundary reached (phase $phase >= stop_at_phase $stop_at_phase)"
        return 1  # Should stop
    fi

    log_debug "check_phase_boundary: Phase boundary not reached (phase $phase < stop_at_phase $stop_at_phase)"
    return 0  # Continue
}

# =============================================================================
# Signal Handling and Cleanup
# =============================================================================

#######################################
# Cleanup Claude Code process if running
# Terminates any running Claude Code process gracefully (SIGTERM),
# then forcefully (SIGKILL) if it doesn't exit within timeout.
# Idempotent - safe to call multiple times.
#
# Globals:
#   CLAUDE_PID - PID of currently running Claude Code process
#   CLEANUP_IN_PROGRESS - Flag to prevent re-entry
#
# Returns:
#   0 - Always returns success (cleanup is best-effort)
#######################################
cleanup_claude_process() {
    # Prevent re-entry (handles multiple rapid signals)
    if [[ "$CLEANUP_IN_PROGRESS" == "true" ]]; then
        log_debug "cleanup_claude_process: Already in progress, skipping"
        return 0
    fi
    CLEANUP_IN_PROGRESS=true

    # Check if we have a PID to clean up
    if [[ -z "$CLAUDE_PID" ]]; then
        log_debug "cleanup_claude_process: No Claude PID to clean up"
        CLEANUP_IN_PROGRESS=false
        return 0
    fi

    # Check if process is still running
    if ! kill -0 "$CLAUDE_PID" 2>/dev/null; then
        log_debug "cleanup_claude_process: Claude process (PID: $CLAUDE_PID) already terminated"
        CLAUDE_PID=""
        CLEANUP_IN_PROGRESS=false
        return 0
    fi

    # Process is running - terminate it
    log_info "Terminating Claude Code process (PID: $CLAUDE_PID)..."

    # Send SIGTERM for graceful shutdown
    kill -TERM "$CLAUDE_PID" 2>/dev/null

    # Wait up to 3 seconds for graceful exit (30 iterations x 0.1 second)
    local wait_count=0
    while [[ $wait_count -lt 30 ]]; do
        if ! kill -0 "$CLAUDE_PID" 2>/dev/null; then
            log_debug "cleanup_claude_process: Claude process terminated gracefully"
            CLAUDE_PID=""
            CLEANUP_IN_PROGRESS=false
            return 0
        fi
        sleep 0.1
        wait_count=$((wait_count + 1))
    done

    # Process still running after timeout - force kill
    if kill -0 "$CLAUDE_PID" 2>/dev/null; then
        log_warn "Claude process did not terminate gracefully, force killing..."
        kill -KILL "$CLAUDE_PID" 2>/dev/null

        # Brief wait for SIGKILL to take effect
        sleep 0.2

        if kill -0 "$CLAUDE_PID" 2>/dev/null; then
            log_error "Failed to kill Claude process (PID: $CLAUDE_PID)"
        else
            log_debug "cleanup_claude_process: Claude process killed with SIGKILL"
        fi
    fi

    CLAUDE_PID=""
    CLEANUP_IN_PROGRESS=false
    return 0
}

#######################################
# Cleanup function called on script exit
# Outputs final status summary showing iterations and tasks completed.
# Skipped during --help/--version to avoid confusing output.
#
# Globals:
#   HELP_SHOWN - If set, suppresses cleanup output
#   ITERATION_COUNT - Number of iterations completed
#   TASKS_COMPLETED - Number of tasks successfully executed
#######################################
cleanup() {
    # Don't output during help/version
    [[ -n "$HELP_SHOWN" ]] && return

    # Clean up any running Claude process
    cleanup_claude_process

    log_info "Exiting after $ITERATION_COUNT iteration(s) ($TASKS_COMPLETED task(s) completed)"
}

#######################################
# Handle SIGINT (Ctrl+C) signal
# Cleans up Claude process and exits with code 130 (conventional for SIGINT)
#######################################
handle_sigint() {
    EXIT_REQUESTED=true
    log_info "Received SIGINT (Ctrl+C), shutting down gracefully..."
    cleanup_claude_process
    exit 130
}

#######################################
# Handle SIGTERM signal
# Cleans up Claude process and exits with code 143 (conventional for SIGTERM)
#######################################
handle_sigterm() {
    EXIT_REQUESTED=true
    log_info "Received SIGTERM, shutting down gracefully..."
    cleanup_claude_process
    exit 143
}

# Set up trap handlers at script load time
trap cleanup EXIT
trap handle_sigint SIGINT INT
trap handle_sigterm SIGTERM TERM

# =============================================================================
# Help and Usage
# =============================================================================

#######################################
# Show usage information
# Outputs:
#   Help text to stdout
#######################################
show_usage() {
    cat << 'EOF'
SDD Loop Controller v1.0.0 - Autonomous SDD workflow controller

DESCRIPTION
    The SDD Loop Controller ("Ralph Wiggum Loop") is an autonomous workflow
    controller that polls master-status-board.sh for recommended tasks and
    executes them via Claude Code CLI.

    The controller continues processing tasks until:
    - No more agent-ready work remains (action: "none")
    - Maximum iterations reached (safety limit)
    - Maximum consecutive errors reached
    - Stop-at-phase boundary reached
    - Interrupted by signal (SIGINT/SIGTERM)

USAGE
    sdd-loop.sh [options] [workspace_root]

ARGUMENTS
    workspace_root
        Root directory containing repositories with _SDD directories.
        Priority: CLI argument > SDD_LOOP_WORKSPACE_ROOT env var > default
        Default: /workspace/repos/

OPTIONS
    -h, --help
        Show this help message and exit.

    -V, --version
        Show version information and exit.

    -n, --dry-run
        Preview mode: log actions without executing Claude Code.
        Useful for testing and verification.

    -v, --verbose
        Enable verbose output with additional progress details.

    -q, --quiet
        Suppress informational messages, show only errors.

    --max-iterations N
        Maximum number of task iterations before stopping.
        Default: 50. Must be a positive integer.
        Loop exits with code 1 when limit is reached.

    --max-errors N
        Maximum consecutive errors before stopping.
        Default: 3. Must be a positive integer.
        Counter resets to 0 on successful task execution.
        Loop exits with code 1 when limit is reached.

    --timeout SECONDS
        Task execution timeout in seconds.
        Default: 3600 (1 hour). Must be a positive integer.
        Timeout uses GNU coreutils timeout command.
        Exit code 124 indicates timeout occurred.

    --poll-interval SECONDS
        Interval between status board polls in seconds.
        Default: 5.
        [Phase 2 - not yet implemented]

    --debug
        Enable debug-level logging (very verbose).

    --log-format FORMAT
        Set log output format: "text" (default) or "json".
        Text format: [YYYY-MM-DD HH:MM:SS] [LEVEL] message
        JSON format: {"timestamp":"ISO8601","level":"LEVEL","message":"...","context":{...}}
        JSON output includes optional context object with iteration, task_id,
        ticket_id, and consecutive_errors when available.
        Useful for log aggregation systems (ELK, CloudWatch, Datadog).

ENVIRONMENT VARIABLES
    SDD_LOOP_WORKSPACE_ROOT
        Default workspace root directory.
        Overridden by CLI argument.

    SDD_LOOP_MAX_ITERATIONS
        Maximum task iterations (default: 50).
        Overridden by --max-iterations.

    SDD_LOOP_MAX_ERRORS
        Maximum consecutive errors (default: 3).
        Overridden by --max-errors.

    SDD_LOOP_TIMEOUT
        Task execution timeout in seconds (default: 3600).
        Overridden by --timeout.

    SDD_LOOP_POLL_INTERVAL
        Poll interval in seconds (default: 5).
        Overridden by --poll-interval.

    SDD_LOOP_DRY_RUN
        Set to "true" for dry-run mode.
        Overridden by --dry-run.

    SDD_LOOP_VERBOSE
        Set to "true" for verbose output.
        Overridden by --verbose.

    SDD_LOOP_QUIET
        Set to "true" for quiet mode.
        Overridden by --quiet.

    SDD_LOOP_DEBUG
        Set to "true" for debug output.
        Overridden by --debug.

    SDD_LOOP_LOG_FORMAT
        Log output format: "text" (default) or "json".
        Overridden by --log-format.

CONFIGURATION HIERARCHY
    Configuration values are resolved in the following order (later overrides earlier):
    1. Built-in defaults (SDD_LOOP_DEFAULT_* constants)
    2. Environment variables (SDD_LOOP_*)
    3. Command-line arguments

EXIT CODES
    0   - Success: All work completed or no work remaining
    1   - Error: Task failure, missing dependencies, or runtime error
    2   - Usage error: Invalid arguments or options
    130 - Interrupted: Received SIGINT (Ctrl+C)
    143 - Terminated: Received SIGTERM

EXAMPLES
    # Basic usage with default workspace
    sdd-loop.sh

    # Specify workspace root
    sdd-loop.sh /workspace/repos/my-project/

    # Dry-run mode to preview actions
    sdd-loop.sh --dry-run

    # Verbose output for debugging
    sdd-loop.sh --verbose

    # Limit iterations for testing
    sdd-loop.sh --max-iterations 5

    # Using environment variables
    SDD_LOOP_DRY_RUN=true SDD_LOOP_VERBOSE=true sdd-loop.sh

    # Quiet mode for CI/CD pipelines
    sdd-loop.sh --quiet

    # JSON logging for log aggregation
    sdd-loop.sh --log-format json

    # JSON logging with environment variable
    SDD_LOOP_LOG_FORMAT=json sdd-loop.sh

INTEGRATION
    The loop controller integrates with:
    - master-status-board.sh: Provides recommended_action JSON
    - Claude Code CLI: Executes /sdd:do-task commands
    - .autogate.json: Reads agent_ready and stop_at_phase settings

    Typical workflow:
    1. Enable agent mode: sdd:mark-ready TICKET --agent
    2. Run loop: sdd-loop.sh /workspace/repos/
    3. Monitor logs for progress
    4. Review completed work

SEE ALSO
    master-status-board.sh - Status board scanner
    sdd:mark-ready - Enable/disable agent processing
    sdd:do-task - Manual task execution

EOF
}

#######################################
# Show version information
# Outputs:
#   Version string to stdout
#######################################
show_version() {
    echo "sdd-loop.sh version $VERSION"
}

# =============================================================================
# Main Function
# =============================================================================

#######################################
# Main entry point
# Arguments:
#   $@ - Command line arguments
#######################################
main() {
    local workspace_root=""
    local positional_args=()

    # Set up signal handlers
    trap handle_sigint SIGINT
    trap handle_sigterm SIGTERM

    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                HELP_SHOWN=true
                show_usage
                exit 0
                ;;
            -V|--version)
                HELP_SHOWN=true
                show_version
                exit 0
                ;;
            -n|--dry-run)
                SDD_LOOP_DRY_RUN="true"
                shift
                ;;
            -v|--verbose)
                SDD_LOOP_VERBOSE="true"
                shift
                ;;
            -q|--quiet)
                SDD_LOOP_QUIET="true"
                shift
                ;;
            --debug)
                SDD_LOOP_DEBUG="true"
                shift
                ;;
            --log-format)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option --log-format requires a value"
                    exit 2
                fi
                if [[ "$2" != "text" && "$2" != "json" ]]; then
                    log_error "Option --log-format requires 'text' or 'json' (got: '$2')"
                    exit 2
                fi
                SDD_LOOP_LOG_FORMAT="$2"
                shift 2
                ;;
            --max-iterations)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option --max-iterations requires a value"
                    exit 2
                fi
                if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    log_error "Option --max-iterations requires a positive integer (got: '$2')"
                    exit 2
                fi
                if [[ "$2" -eq 0 ]]; then
                    log_error "Option --max-iterations requires a positive integer greater than zero (got: $2)"
                    exit 2
                fi
                SDD_LOOP_MAX_ITERATIONS="$2"
                shift 2
                ;;
            --max-errors)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option --max-errors requires a value"
                    exit 2
                fi
                if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    log_error "Option --max-errors requires a positive integer (got: '$2')"
                    exit 2
                fi
                if [[ "$2" -eq 0 ]]; then
                    log_error "Option --max-errors requires a positive integer greater than zero (got: $2)"
                    exit 2
                fi
                SDD_LOOP_MAX_ERRORS="$2"
                shift 2
                ;;
            --timeout)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option --timeout requires a value"
                    exit 2
                fi
                if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    log_error "Option --timeout requires a positive integer (got: '$2')"
                    exit 2
                fi
                if [[ "$2" -eq 0 ]]; then
                    log_error "Option --timeout requires a positive integer greater than zero (got: $2)"
                    exit 2
                fi
                SDD_LOOP_TIMEOUT="$2"
                shift 2
                ;;
            --poll-interval)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option --poll-interval requires a value"
                    exit 2
                fi
                if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    log_error "Option --poll-interval requires a non-negative integer (got: '$2')"
                    exit 2
                fi
                SDD_LOOP_POLL_INTERVAL="$2"
                shift 2
                ;;
            -*)
                # Check for combined short options like -nv
                if [[ "$1" =~ ^-[a-zA-Z]+$ ]]; then
                    local opts="${1:1}"
                    local i=0
                    local unknown_opt=""
                    while [[ $i -lt ${#opts} ]]; do
                        local opt="${opts:$i:1}"
                        case "$opt" in
                            n) SDD_LOOP_DRY_RUN="true" ;;
                            v) SDD_LOOP_VERBOSE="true" ;;
                            q) SDD_LOOP_QUIET="true" ;;
                            h) HELP_SHOWN=true; show_usage; exit 0 ;;
                            V) HELP_SHOWN=true; show_version; exit 0 ;;
                            *)
                                unknown_opt="$opt"
                                break
                                ;;
                        esac
                        i=$((i + 1))
                    done
                    if [[ -n "$unknown_opt" ]]; then
                        log_error "Unknown option: -$unknown_opt"
                        echo "Use --help for usage information" >&2
                        exit 2
                    fi
                    shift
                else
                    log_error "Unknown option: $1"
                    echo "Use --help for usage information" >&2
                    exit 2
                fi
                ;;
            *)
                positional_args+=("$1")
                shift
                ;;
        esac
    done

    # Apply configuration hierarchy: defaults < env vars < CLI args
    # (CLI args already set above, now apply defaults for unset values)

    # Workspace root: CLI arg > env var > default
    if [[ ${#positional_args[@]} -gt 0 ]]; then
        workspace_root="${positional_args[0]}"
    elif [[ -n "${SDD_LOOP_WORKSPACE_ROOT:-}" ]]; then
        workspace_root="$SDD_LOOP_WORKSPACE_ROOT"
    else
        workspace_root="$SDD_LOOP_DEFAULT_WORKSPACE_ROOT"
    fi

    # Apply defaults for numeric options if not set
    if [[ -z "$SDD_LOOP_MAX_ITERATIONS" ]]; then
        SDD_LOOP_MAX_ITERATIONS="$SDD_LOOP_DEFAULT_MAX_ITERATIONS"
    fi
    if [[ -z "$SDD_LOOP_MAX_ERRORS" ]]; then
        SDD_LOOP_MAX_ERRORS="$SDD_LOOP_DEFAULT_MAX_ERRORS"
    fi
    if [[ -z "$SDD_LOOP_TIMEOUT" ]]; then
        SDD_LOOP_TIMEOUT="$SDD_LOOP_DEFAULT_TIMEOUT"
    fi
    if [[ -z "$SDD_LOOP_POLL_INTERVAL" ]]; then
        SDD_LOOP_POLL_INTERVAL="$SDD_LOOP_DEFAULT_POLL_INTERVAL"
    fi

    # Expand workspace root to absolute path
    if [[ ! "$workspace_root" = /* ]]; then
        workspace_root="$(cd "$workspace_root" 2>/dev/null && pwd)" || {
            log_error "Cannot resolve workspace root path: $workspace_root"
            exit 1
        }
    fi

    # Ensure trailing slash for consistent path handling
    workspace_root="${workspace_root%/}/"

    # Validate workspace directory exists
    if [[ ! -d "$workspace_root" ]]; then
        log_error "Workspace directory does not exist: $workspace_root"
        exit 1
    fi

    # Update global SDD_LOOP_WORKSPACE_ROOT with resolved value for use in execute_task()
    SDD_LOOP_WORKSPACE_ROOT="$workspace_root"

    # Log startup configuration
    log_debug "Configuration:"
    log_debug "  Workspace root: $workspace_root"
    log_debug "  Max iterations: $SDD_LOOP_MAX_ITERATIONS"
    log_debug "  Max errors: $SDD_LOOP_MAX_ERRORS"
    log_debug "  Timeout: $SDD_LOOP_TIMEOUT"
    log_debug "  Poll interval: $SDD_LOOP_POLL_INTERVAL"
    log_debug "  Dry run: $SDD_LOOP_DRY_RUN"
    log_debug "  Verbose: $SDD_LOOP_VERBOSE"
    log_debug "  Quiet: $SDD_LOOP_QUIET"
    log_debug "  Log format: $SDD_LOOP_LOG_FORMAT"

    log_info "SDD Loop Controller v$VERSION starting..."
    log_info "Workspace: $workspace_root"

    if [[ "$SDD_LOOP_DRY_RUN" == "true" ]]; then
        log_info "Running in DRY-RUN mode - no tasks will be executed"
    fi

    # ==========================================================================
    # Main Poll-Execute Loop
    # ==========================================================================
    # Safety limits enforced:
    # - Max iteration limit (default: 50)
    # - Consecutive error tracking (default: 3)
    # - Task execution timeout (default: 3600s)
    # ==========================================================================

    local consecutive_errors=0
    local max_iterations="$SDD_LOOP_MAX_ITERATIONS"
    local max_errors="$SDD_LOOP_MAX_ERRORS"

    # Log verbose configuration
    log_verbose "Configuration: max_iterations=$max_iterations, max_errors=$max_errors, timeout=$SDD_LOOP_TIMEOUT"

    log_info "Safety limits: max_iterations=$max_iterations, max_errors=$max_errors, timeout=${SDD_LOOP_TIMEOUT}s"

    while true; do
        # Check if exit was requested via signal
        if [[ "$EXIT_REQUESTED" == "true" ]]; then
            log_info "Loop stopped: exit requested via signal"
            exit "$EXIT_CODE"
        fi

        # =======================================================================
        # Safety Check: Max Iterations
        # =======================================================================
        if [[ $ITERATION_COUNT -ge $max_iterations ]]; then
            log_warn "Reached maximum iterations ($max_iterations)"
            log_info "Loop stopped: safety limit reached after $ITERATION_COUNT iteration(s)"
            exit 1
        fi

        # Increment iteration counter (global for cleanup)
        ITERATION_COUNT=$((ITERATION_COUNT + 1))

        # Log iteration start
        log_info "Iteration $ITERATION_COUNT/$max_iterations: polling for next task"

        # Poll status board for recommended action
        # Redirect stdout to /dev/null since poll_status outputs JSON to stdout
        # but we only need the global variables it sets
        if ! poll_status "$workspace_root" >/dev/null; then
            log_error "Polling failed at iteration $ITERATION_COUNT"
            log_info "Loop stopped: polling error"
            exit 1
        fi

        # Handle the recommended action
        case "$POLL_ACTION" in
            "none")
                log_info "No more work available (reason: ${POLL_REASON:-no tasks remaining})"
                log_info "Loop stopped: all work completed after $ITERATION_COUNT iteration(s)"
                exit 0
                ;;
            "do-task")
                log_info "Action: execute task $POLL_TASK (ticket: $POLL_TICKET)"

                # Execute the task and capture exit code
                local task_exit_code=0
                execute_task "$POLL_TASK" "$POLL_SDD_ROOT" || task_exit_code=$?

                # =============================================================
                # Error Tracking: Update consecutive error counter
                # =============================================================
                if [[ $task_exit_code -eq 0 ]]; then
                    # Success: increment tasks completed counter
                    TASKS_COMPLETED=$((TASKS_COMPLETED + 1))

                    # Reset consecutive error counter
                    if [[ $consecutive_errors -gt 0 ]]; then
                        log_verbose "Task succeeded, resetting consecutive error counter (was: $consecutive_errors)"
                    fi
                    consecutive_errors=0

                    # ==========================================================
                    # Phase Boundary Check: Stop if stop_at_phase reached
                    # Note: check_phase_boundary returns 1 (non-zero) when should stop
                    # ==========================================================
                    check_phase_boundary "$POLL_TICKET" "$POLL_TASK" "$POLL_SDD_ROOT"
                    local boundary_result=$?
                    if [[ $boundary_result -eq 1 ]]; then
                        log_info "Phase boundary reached (stop_at_phase: $STOP_AT_PHASE)"
                        log_info "Loop stopped: phase $STOP_AT_PHASE limit reached after $ITERATION_COUNT iteration(s)"
                        exit 0
                    fi

                    log_verbose "Task $POLL_TASK completed, continuing to next iteration"
                else
                    # Failure: increment consecutive error counter
                    consecutive_errors=$((consecutive_errors + 1))
                    log_warn "Task failed (exit code: $task_exit_code), consecutive errors: $consecutive_errors/$max_errors"

                    # ==========================================================
                    # Safety Check: Max Consecutive Errors
                    # ==========================================================
                    if [[ $consecutive_errors -ge $max_errors ]]; then
                        log_error "Reached maximum consecutive errors ($max_errors)"
                        log_info "Loop stopped: too many consecutive failures after $ITERATION_COUNT iteration(s)"
                        exit 1
                    fi

                    log_info "Continuing despite error ($consecutive_errors/$max_errors consecutive errors)"
                fi
                ;;
            *)
                log_warn "Unknown action: $POLL_ACTION (treating as 'none')"
                log_info "Loop stopped: unknown action at iteration $ITERATION_COUNT"
                exit 0
                ;;
        esac
    done
}

# =============================================================================
# Entry Point
# =============================================================================

# Run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
