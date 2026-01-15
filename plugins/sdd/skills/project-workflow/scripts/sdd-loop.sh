#!/usr/bin/env bash
#
# SDD Loop Controller ("Ralph Wiggum Loop")
# Autonomous SDD workflow controller
#
# Version: 1.0.0
# Description: Polls master-status-board.sh for recommended tasks and executes
#              them via Claude Code CLI in an automated loop.
#
# Usage:
#   bash sdd-loop.sh [options] [workspace_root]
#
# Examples:
#   bash sdd-loop.sh                              # Use default workspace
#   bash sdd-loop.sh /workspace/repos/            # Use specific workspace
#   bash sdd-loop.sh --dry-run                    # Preview actions without executing
#   bash sdd-loop.sh --max-iterations 10          # Limit to 10 task executions
#   SDD_LOOP_DRY_RUN=true bash sdd-loop.sh        # Dry run via environment
#
# Arguments:
#   workspace_root    Root directory containing repositories (optional)
#                     Priority: argument > SDD_LOOP_WORKSPACE_ROOT env var > default
#                     Default: /workspace/repos/
#
# Exit Codes:
#   0   - Success (completed work or no work remaining)
#   1   - General error (task failure, missing dependencies)
#   2   - Usage error (invalid arguments)
#   130 - Interrupted by SIGINT (Ctrl+C)
#   143 - Terminated by SIGTERM
#
# See --help for full documentation.
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

# Poll result state (set by poll_status function)
POLL_ACTION=""
POLL_TASK=""
POLL_TICKET=""
POLL_SDD_ROOT=""
POLL_REASON=""

# =============================================================================
# Logging Functions
# =============================================================================

#######################################
# Log an informational message to stderr
# Arguments:
#   $@ - Message to print
# Outputs:
#   Writes timestamped message to stderr
#######################################
log_info() {
    if [[ "$SDD_LOOP_QUIET" != "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" >&2
    fi
}

#######################################
# Log an error message to stderr
# Arguments:
#   $@ - Message to print
# Outputs:
#   Writes timestamped error message to stderr
#######################################
log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

#######################################
# Log a verbose message to stderr (only if verbose mode enabled)
# Arguments:
#   $@ - Message to print
# Outputs:
#   Writes timestamped message to stderr if verbose mode is enabled
#######################################
log_verbose() {
    if [[ "$SDD_LOOP_VERBOSE" == "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [VERBOSE] $*" >&2
    fi
}

#######################################
# Log a debug message to stderr (only if debug mode enabled)
# Arguments:
#   $@ - Message to print
# Outputs:
#   Writes timestamped message to stderr if debug mode is enabled
#######################################
log_debug() {
    if [[ "$SDD_LOOP_DEBUG" == "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $*" >&2
    fi
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

    # Parse JSON using jq to extract recommended_action fields
    # Use safe defaults (// "") for missing fields
    local parse_error=0

    POLL_ACTION=$(echo "$status_output" | jq -r '.recommended_action.action // ""' 2>/dev/null) || parse_error=1
    if [[ $parse_error -ne 0 ]]; then
        log_error "Failed to parse JSON field: recommended_action.action"
        return 1
    fi

    POLL_TASK=$(echo "$status_output" | jq -r '.recommended_action.task // ""' 2>/dev/null) || parse_error=1
    if [[ $parse_error -ne 0 ]]; then
        log_error "Failed to parse JSON field: recommended_action.task"
        return 1
    fi

    POLL_TICKET=$(echo "$status_output" | jq -r '.recommended_action.ticket // ""' 2>/dev/null) || parse_error=1
    if [[ $parse_error -ne 0 ]]; then
        log_error "Failed to parse JSON field: recommended_action.ticket"
        return 1
    fi

    POLL_SDD_ROOT=$(echo "$status_output" | jq -r '.recommended_action.sdd_root // ""' 2>/dev/null) || parse_error=1
    if [[ $parse_error -ne 0 ]]; then
        log_error "Failed to parse JSON field: recommended_action.sdd_root"
        return 1
    fi

    POLL_REASON=$(echo "$status_output" | jq -r '.recommended_action.reason // ""' 2>/dev/null) || parse_error=1
    if [[ $parse_error -ne 0 ]]; then
        log_error "Failed to parse JSON field: recommended_action.reason"
        return 1
    fi

    # Log poll results at verbose level
    log_verbose "Poll result: action=$POLL_ACTION"
    if [[ -n "$POLL_TASK" ]]; then
        log_verbose "  Task: $POLL_TASK"
    fi
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
# Arguments:
#   $1 - Task ID (e.g., "TICKET.1001")
#   $2 - Task file path
#   $3 - SDD root directory
# Outputs:
#   Logs execution progress to stderr
# Returns:
#   0 on success
#   1 on error (Claude Code failure, timeout)
#######################################
execute_task() {
    local task_id="$1"
    local task_file="$2"
    local sdd_root="$3"

    log_debug "execute_task: task_id=$task_id, task_file=$task_file, sdd_root=$sdd_root"

    # Placeholder implementation - will be completed in subsequent task
    # This skeleton demonstrates the expected interface

    if [[ "$SDD_LOOP_DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute task: $task_id"
        log_info "[DRY RUN] Task file: $task_file"
        log_info "[DRY RUN] SDD root: $sdd_root"
        return 0
    fi

    # Check if claude CLI is available
    if ! command -v claude &>/dev/null; then
        log_error "Claude Code CLI not found. Please install claude-code."
        return 1
    fi

    # In full implementation, this will:
    # 1. Set SDD_ROOT_DIR environment variable
    # 2. Invoke claude with appropriate arguments
    # 3. Handle timeout
    # 4. Parse exit code and output
    log_info "Would execute task: $task_id (skeleton implementation)"

    return 0
}

# =============================================================================
# Signal Handling
# =============================================================================

#######################################
# Handle SIGINT (Ctrl+C) signal
# Globals:
#   EXIT_REQUESTED - Set to true
#   EXIT_CODE - Set to 130
#######################################
handle_sigint() {
    log_info "Received SIGINT (Ctrl+C), shutting down gracefully..."
    EXIT_REQUESTED=true
    EXIT_CODE=130
}

#######################################
# Handle SIGTERM signal
# Globals:
#   EXIT_REQUESTED - Set to true
#   EXIT_CODE - Set to 143
#######################################
handle_sigterm() {
    log_info "Received SIGTERM, shutting down gracefully..."
    EXIT_REQUESTED=true
    EXIT_CODE=143
}

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
        Default: 50. Set to 0 for unlimited (not recommended).
        [Phase 2 - not yet implemented]

    --max-errors N
        Maximum consecutive errors before stopping.
        Default: 3.
        [Phase 2 - not yet implemented]

    --timeout SECONDS
        Task execution timeout in seconds.
        Default: 3600 (1 hour).
        [Phase 2 - not yet implemented]

    --poll-interval SECONDS
        Interval between status board polls in seconds.
        Default: 5.
        [Phase 2 - not yet implemented]

    --debug
        Enable debug-level logging (very verbose).

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
                show_usage
                exit 0
                ;;
            -V|--version)
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
            --max-iterations)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option --max-iterations requires a value"
                    exit 2
                fi
                if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    log_error "Option --max-iterations requires a numeric value"
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
                    log_error "Option --max-errors requires a numeric value"
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
                    log_error "Option --timeout requires a numeric value"
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
                    log_error "Option --poll-interval requires a numeric value"
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
                            h) show_usage; exit 0 ;;
                            V) show_version; exit 0 ;;
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

    log_info "SDD Loop Controller v$VERSION starting..."
    log_info "Workspace: $workspace_root"

    if [[ "$SDD_LOOP_DRY_RUN" == "true" ]]; then
        log_info "Running in DRY-RUN mode - no tasks will be executed"
    fi

    # Main loop placeholder
    # Full implementation will be added in subsequent tasks
    log_info "Polling for recommended actions..."

    local status_output
    if ! status_output=$(poll_status "$workspace_root"); then
        log_error "Failed to poll status board"
        exit 1
    fi

    log_verbose "Status board output: $status_output"
    log_info "Loop controller skeleton complete. Full implementation pending."

    # Clean exit
    exit "$EXIT_CODE"
}

# =============================================================================
# Entry Point
# =============================================================================

# Run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
