#!/usr/bin/env bash
#
# orchestrator.sh - Main entry point for SDD automation workflow
#
# Version: 1.0.0
# Part of SDD Plugin automation framework (Epic ASDW)
#
# This script orchestrates the automated SDD workflow from JIRA ticket fetch
# to draft PR creation. It coordinates modules for state management, decision
# making, JIRA integration, and SDD command execution.
#
# Usage: ./orchestrator.sh [OPTIONS]
# See --help for full usage information.
#

set -euo pipefail

# Script directory and paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared utilities (logging, JSON helpers, file operations)
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# Version
VERSION="1.0.0"

# Global variables for parsed arguments
INPUT_TYPE=""      # jql | epic | team | tickets | resume
INPUT_VALUE=""     # The actual query/key/list
DRY_RUN=false      # --dry-run flag
VERBOSE=false      # --verbose flag
CONFIG_FILE=""     # --config override

# Global variables for run state
RUN_ID=""          # Unique identifier for this workflow run
RUN_DIR=""         # Directory for this run's state and logs

#
# show_help - Display usage information
#
show_help() {
    cat << 'EOF'
Usage: orchestrator.sh [OPTIONS]

Automated SDD workflow orchestrator - runs ticket lifecycle from JIRA to draft PR.

INPUT MODES (choose one):
  --jql QUERY          Execute workflow for tickets matching JQL query
  --epic EPIC_KEY      Execute workflow for all tickets in epic
  --team TEAM_NAME     Execute workflow for team's prioritized tickets
  --tickets LIST       Execute workflow for comma-separated ticket list
  --resume [RUN_ID]    Resume a previous run (uses latest if RUN_ID omitted)

OPTIONS:
  --config FILE        Use custom configuration file (default: config/default.json)
  --dry-run            Validate inputs but don't execute workflow
  --verbose            Enable debug logging to console
  --help               Display this help message
  --version            Display version information

EXAMPLES:
  # Process all open tickets in project UIT
  ./orchestrator.sh --jql "project = UIT AND status = 'To Do'"

  # Process all tickets in epic UIT-100
  ./orchestrator.sh --epic UIT-100

  # Process specific tickets
  ./orchestrator.sh --tickets UIT-3607,UIT-3608,UIT-3609

  # Resume interrupted run
  ./orchestrator.sh --resume

  # Resume specific run
  ./orchestrator.sh --resume 20251212-143052-a1b2c3d4

EXIT CODES:
  0   Success
  1   Usage error (invalid arguments)
  2   Configuration error
  3   Module loading error
  4   Initialization error
  5   Workflow error
  See full exit code reference in documentation.

ENVIRONMENT VARIABLES:
  SDD_ROOT_DIR         Override sdd_root config (default: /app/.sdd)
  SDD_LOG_LEVEL        Override logging level (debug|info|warn|error)
  SDD_RISK_TOLERANCE   Override risk tolerance (conservative|moderate|aggressive)

For more information, see: ${SDD_ROOT_DIR:-/app/.sdd}/automation/README.md
EOF
}

#
# show_version - Display version information
#
show_version() {
    cat << EOF
SDD Orchestrator v${VERSION}
Part of SDD Plugin automation framework (Epic ASDW)
EOF
}

#
# parse_arguments - Parse and validate command-line arguments
#
# Handles all input modes (--jql, --epic, --team, --tickets, --resume) and
# optional flags (--dry-run, --verbose, --config, --help, --version).
#
# Validation:
# - Exactly one input mode required (except --help, --version which exit early)
# - Input modes are mutually exclusive
# - Each input mode requires a value (except --resume which has optional RUN_ID)
# - Empty values are rejected
# - Unknown flags are rejected
#
# Sets global variables:
#   INPUT_TYPE, INPUT_VALUE, DRY_RUN, VERBOSE, CONFIG_FILE
#
# Arguments:
#   $@ - Command-line arguments
#
# Returns:
#   0 on success, exits with code 1 on validation errors
#
parse_arguments() {
    local input_mode_count=0

    # Handle no arguments case
    if [ $# -eq 0 ]; then
        log_error "Error: Missing required input mode. Use one of: --jql, --epic, --team, --tickets, --resume"
        echo "" >&2
        show_help >&2
        exit 1
    fi

    # Parse arguments manually (getopts doesn't support long options)
    while [ $# -gt 0 ]; do
        case "$1" in
            --help)
                show_help
                exit 0
                ;;
            --version)
                show_version
                exit 0
                ;;
            --jql)
                if [ -z "${2:-}" ]; then
                    log_error "Error: --jql requires a JQL query value"
                    echo "" >&2
                    show_help >&2
                    exit 1
                fi
                if [ -z "${2// /}" ]; then
                    log_error "Error: --jql value cannot be empty or whitespace only"
                    echo "" >&2
                    show_help >&2
                    exit 1
                fi
                INPUT_TYPE="jql"
                INPUT_VALUE="$2"
                input_mode_count=$((input_mode_count + 1))
                shift 2
                ;;
            --epic)
                if [ -z "${2:-}" ]; then
                    log_error "Error: --epic requires an epic key value"
                    echo "" >&2
                    show_help >&2
                    exit 1
                fi
                if [ -z "${2// /}" ]; then
                    log_error "Error: --epic value cannot be empty or whitespace only"
                    echo "" >&2
                    show_help >&2
                    exit 1
                fi
                INPUT_TYPE="epic"
                INPUT_VALUE="$2"
                input_mode_count=$((input_mode_count + 1))
                shift 2
                ;;
            --team)
                if [ -z "${2:-}" ]; then
                    log_error "Error: --team requires a team name value"
                    echo "" >&2
                    show_help >&2
                    exit 1
                fi
                if [ -z "${2// /}" ]; then
                    log_error "Error: --team value cannot be empty or whitespace only"
                    echo "" >&2
                    show_help >&2
                    exit 1
                fi
                INPUT_TYPE="team"
                INPUT_VALUE="$2"
                input_mode_count=$((input_mode_count + 1))
                shift 2
                ;;
            --tickets)
                if [ -z "${2:-}" ]; then
                    log_error "Error: --tickets requires a comma-separated list value"
                    echo "" >&2
                    show_help >&2
                    exit 1
                fi
                if [ -z "${2// /}" ]; then
                    log_error "Error: --tickets value cannot be empty or whitespace only"
                    echo "" >&2
                    show_help >&2
                    exit 1
                fi
                INPUT_TYPE="tickets"
                INPUT_VALUE="$2"
                input_mode_count=$((input_mode_count + 1))
                shift 2
                ;;
            --resume)
                INPUT_TYPE="resume"
                # --resume has optional RUN_ID argument
                if [ -n "${2:-}" ] && [[ "$2" != --* ]]; then
                    INPUT_VALUE="$2"
                    shift 2
                else
                    INPUT_VALUE=""  # Will use latest run
                    shift
                fi
                input_mode_count=$((input_mode_count + 1))
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --config)
                if [ -z "${2:-}" ]; then
                    log_error "Error: --config requires a file path value"
                    echo "" >&2
                    show_help >&2
                    exit 1
                fi
                if [ -z "${2// /}" ]; then
                    log_error "Error: --config value cannot be empty or whitespace only"
                    echo "" >&2
                    show_help >&2
                    exit 1
                fi
                CONFIG_FILE="$2"
                shift 2
                ;;
            --*)
                log_error "Error: Unknown option: $1"
                echo "" >&2
                show_help >&2
                exit 1
                ;;
            *)
                log_error "Error: Unknown argument: $1"
                echo "" >&2
                show_help >&2
                exit 1
                ;;
        esac
    done

    # Validate exactly one input mode was specified
    if [ $input_mode_count -eq 0 ]; then
        log_error "Error: Missing required input mode. Use one of: --jql, --epic, --team, --tickets, --resume"
        echo "" >&2
        show_help >&2
        exit 1
    fi

    if [ $input_mode_count -gt 1 ]; then
        log_error "Error: Cannot specify multiple input modes"
        echo "" >&2
        show_help >&2
        exit 1
    fi

    # Apply verbose flag to logging if set
    if [ "$VERBOSE" = true ]; then
        export CONFIG_LOG_LEVEL="debug"
    fi

    log_debug "Arguments parsed successfully"
    log_debug "INPUT_TYPE=$INPUT_TYPE"
    log_debug "INPUT_VALUE=$INPUT_VALUE"
    log_debug "DRY_RUN=$DRY_RUN"
    log_debug "VERBOSE=$VERBOSE"
    log_debug "CONFIG_FILE=$CONFIG_FILE"

    return 0
}

#
# validate_module_interface - Validate that a module implements required functions
#
# Checks that all required functions are defined in the current shell environment.
# Uses declare -F to test for function existence without executing them.
#
# Arguments:
#   $1 - module_name: Name of the module being validated (for error messages)
#   $@ - required_functions: Space-separated list of required function names
#
# Returns:
#   0 if all functions exist, 1 if any are missing
#
# Logs:
#   - Error for each missing function
#   - Debug message when all functions present
#
validate_module_interface() {
    local module_name="$1"
    shift
    local required_functions=("$@")

    for func in "${required_functions[@]}"; do
        if ! declare -F "$func" > /dev/null; then
            log_error "Module $module_name missing required function: $func"
            return 1
        fi
    done

    log_debug "Module $module_name validated: all required functions present"
    return 0
}

#
# load_modules - Source and validate all required modules
#
# Loads modules in dependency order and validates their interfaces.
# Modules are sourced from the modules/ directory relative to SCRIPT_DIR.
#
# Module loading order (dependency-based):
#   1. lib/common.sh - Already sourced at top of file
#   2. state-manager.sh - State persistence
#   3. recovery-handler.sh - Error handling and retry
#   4. jira-adapter.sh - JIRA integration
#   5. decision-engine.sh - Claude-based decisions
#   6. sdd-executor.sh - SDD command execution
#
# For each module:
#   - Sources the module file (exits with code 3 on source failure)
#   - Validates required interface functions (exits with code 3 on validation failure)
#   - Logs success/failure appropriately
#
# Returns:
#   0 on success (all modules loaded and validated)
#   Exits with code 3 on any module loading or validation failure
#
load_modules() {
    local modules_dir="${SCRIPT_DIR}/modules"

    log_info "Loading automation modules..."

    # Module 1: State Manager
    # shellcheck source=modules/state-manager.sh
    if ! source "${modules_dir}/state-manager.sh"; then
        log_error "Failed to source state-manager"
        exit 3
    fi
    if ! validate_module_interface "state-manager" "save_state" "load_state" "save_checkpoint" "restore_checkpoint"; then
        exit 3
    fi
    log_debug "Loaded module: state-manager"

    # Module 2: Recovery Handler
    # shellcheck source=modules/recovery-handler.sh
    if ! source "${modules_dir}/recovery-handler.sh"; then
        log_error "Failed to source recovery-handler"
        exit 3
    fi
    if ! validate_module_interface "recovery-handler" "retry_with_backoff" "handle_error"; then
        exit 3
    fi
    log_debug "Loaded module: recovery-handler"

    # Module 3: JIRA Adapter
    # shellcheck source=modules/jira-adapter.sh
    if ! source "${modules_dir}/jira-adapter.sh"; then
        log_error "Failed to source jira-adapter"
        exit 3
    fi
    if ! validate_module_interface "jira-adapter" "fetch_tickets" "get_ticket_details"; then
        exit 3
    fi
    log_debug "Loaded module: jira-adapter"

    # Module 4: Decision Engine
    # shellcheck source=modules/decision-engine.sh
    if ! source "${modules_dir}/decision-engine.sh"; then
        log_error "Failed to source decision-engine"
        exit 3
    fi
    if ! validate_module_interface "decision-engine" "make_decision"; then
        exit 3
    fi
    log_debug "Loaded module: decision-engine"

    # Module 5: SDD Executor
    # shellcheck source=modules/sdd-executor.sh
    if ! source "${modules_dir}/sdd-executor.sh"; then
        log_error "Failed to source sdd-executor"
        exit 3
    fi
    if ! validate_module_interface "sdd-executor" "execute_stage"; then
        exit 3
    fi
    log_debug "Loaded module: sdd-executor"

    log_info "All modules loaded and validated successfully"
    return 0
}

#
# generate_run_id - Generate unique run identifier with collision detection
#
# Creates a unique run ID in format YYYYMMDD-HHMMSS-RANDOM where RANDOM is
# 8 hex characters from /dev/urandom. Implements collision detection by checking
# if a run directory already exists for the generated ID.
#
# Retry logic:
# - Maximum 5 attempts to generate a unique ID
# - 0.1 second delay between attempts
# - Logs warning on collision, error if all attempts exhausted
#
# Format: 20251214-143052-a1b2c3d4
# - YYYYMMDD-HHMMSS: timestamp from `date +%Y%m%d-%H%M%S`
# - RANDOM: 8 hex chars from `head -c 4 /dev/urandom | xxd -p`
#
# Arguments:
#   None
#
# Environment:
#   SDD_ROOT_DIR - Root directory for SDD workspace (defaults to /app/.sdd)
#
# Returns:
#   0 on success (echoes run_id to stdout), 1 on failure after max attempts
#   Logs debug message on success, warn on collision, error on failure
#
# Examples:
#   run_id=$(generate_run_id)
#   if [ $? -eq 0 ]; then
#       echo "Generated run ID: $run_id"
#   else
#       log_error "Failed to generate unique run ID"
#       exit 4
#   fi
#
generate_run_id() {
    local timestamp
    local random_suffix
    local run_id
    local max_attempts=5
    local attempt=0
    local sdd_root="${SDD_ROOT_DIR:-/app/.sdd}"

    while [ $attempt -lt $max_attempts ]; do
        timestamp=$(date +%Y%m%d-%H%M%S)
        random_suffix=$(head -c 4 /dev/urandom | xxd -p)
        run_id="${timestamp}-${random_suffix}"

        # Check for collision
        local run_dir="${sdd_root}/automation/runs/${run_id}"
        if [ ! -d "$run_dir" ]; then
            log_debug "Generated unique run ID: $run_id"
            echo "$run_id"
            return 0
        fi

        log_warn "Run ID collision detected: $run_id, retrying..."
        attempt=$((attempt + 1))
        sleep 0.1
    done

    log_error "Failed to generate unique run ID after $max_attempts attempts"
    return 1
}

#
# initialize_run - Initialize run directory structure and state
#
# Creates a new workflow run with unique identifier, directory structure,
# and initial state file. This function must be called after modules are
# loaded but before any workflow execution.
#
# Directory structure created:
#   ${SDD_ROOT_DIR}/automation/runs/${RUN_ID}/
#   ├── state.json           (permissions: 600)
#   ├── checkpoints/         (for state snapshots)
#   ├── decisions/           (for decision logs)
#   └── logs/                (for run-specific logs)
#
# Initial state.json format:
#   {
#     "run_id": "20251214-143052-a1b2c3d4",
#     "status": "running",
#     "input_type": "jql",
#     "input_value": "project = UIT",
#     "started_at": "2025-12-14T14:30:52-05:00",
#     "tickets": [],
#     "current_ticket": null
#   }
#
# Global Variables Set:
#   RUN_ID - The generated unique run identifier
#   RUN_DIR - Full path to the run directory
#
# Arguments:
#   None (uses global INPUT_TYPE and INPUT_VALUE)
#
# Environment:
#   SDD_ROOT_DIR - Root directory for SDD workspace (defaults to /app/.sdd)
#
# Returns:
#   0 on success
#   Exits with code 4 on any initialization failure
#   Logs info on success, error on failure
#
# Examples:
#   INPUT_TYPE="jql"
#   INPUT_VALUE="project = UIT"
#   initialize_run || exit 4
#   echo "Run initialized: $RUN_ID"
#   echo "Run directory: $RUN_DIR"
#
initialize_run() {
    local sdd_root="${SDD_ROOT_DIR:-/app/.sdd}"

    log_info "Initializing workflow run..."

    # Generate unique run ID
    if ! RUN_ID=$(generate_run_id); then
        log_error "Failed to generate run ID"
        exit 4
    fi

    # Set run directory path
    RUN_DIR="${sdd_root}/automation/runs/${RUN_ID}"

    log_info "Creating run directory: $RUN_DIR"

    # Create run directory with restricted permissions (700 = rwx------)
    # Note: mkdir -p doesn't guarantee permissions on parent dirs, only final dir
    if ! mkdir -p "$RUN_DIR"; then
        log_error "Failed to create run directory: $RUN_DIR"
        exit 4
    fi

    # Set restrictive permissions on run directory
    if ! chmod 700 "$RUN_DIR"; then
        log_error "Failed to set permissions on run directory: $RUN_DIR"
        exit 4
    fi

    # Create subdirectories (755 = rwxr-xr-x)
    if ! mkdir -p "$RUN_DIR/checkpoints" "$RUN_DIR/decisions" "$RUN_DIR/logs"; then
        log_error "Failed to create run subdirectories"
        exit 4
    fi

    log_debug "Created run directory structure"

    # Create initial state.json
    local started_at
    started_at=$(date -Iseconds)

    local state_json
    state_json=$(cat <<EOF
{
  "run_id": "$RUN_ID",
  "status": "running",
  "input_type": "$INPUT_TYPE",
  "input_value": "$INPUT_VALUE",
  "started_at": "$started_at",
  "tickets": [],
  "current_ticket": null
}
EOF
)

    # Write state file atomically (sets 600 permissions)
    if ! atomic_write "${RUN_DIR}/state.json" "$state_json"; then
        log_error "Failed to write initial state file"
        exit 4
    fi

    log_info "Run initialized successfully: $RUN_ID"
    log_debug "Run directory: $RUN_DIR"
    log_debug "Initial state saved"

    return 0
}

#
# has_pending_tickets - Check if there are any tickets remaining to process
#
# Checks the run state to determine if there are tickets that haven't been
# completed yet. A ticket is pending if its status is not "completed" or "failed".
#
# Arguments:
#   None (reads from RUN_DIR/state.json)
#
# Returns:
#   0 if there are pending tickets, 1 if all tickets are processed
#
has_pending_tickets() {
    local state_file="${RUN_DIR}/state.json"

    if [ ! -f "$state_file" ]; then
        log_error "State file not found: $state_file"
        return 1
    fi

    local state_content
    state_content=$(cat "$state_file")

    # Check if there are any tickets with status != "completed" and != "failed"
    local pending_count
    pending_count=$(echo "$state_content" | jq '[.tickets[] | select(.status != "completed" and .status != "failed")] | length' 2>/dev/null)

    if [ -z "$pending_count" ] || [ "$pending_count" -eq 0 ]; then
        log_debug "No pending tickets found"
        return 1
    fi

    log_debug "Found $pending_count pending ticket(s)"
    return 0
}

#
# select_next_ticket - Get the next ticket to process from the queue
#
# Selects the first ticket from the queue that has status "pending" or "in_progress".
# Returns the ticket key for processing.
#
# Arguments:
#   None (reads from RUN_DIR/state.json)
#
# Returns:
#   0 on success (echoes ticket key to stdout), 1 if no pending tickets
#
select_next_ticket() {
    local state_file="${RUN_DIR}/state.json"

    if [ ! -f "$state_file" ]; then
        log_error "State file not found: $state_file"
        return 1
    fi

    local state_content
    state_content=$(cat "$state_file")

    # Get first ticket with status "pending" or "in_progress"
    local ticket_key
    ticket_key=$(echo "$state_content" | jq -r '[.tickets[] | select(.status == "pending" or .status == "in_progress")][0].key // empty' 2>/dev/null)

    if [ -z "$ticket_key" ]; then
        log_debug "No pending tickets to select"
        return 1
    fi

    log_debug "Selected next ticket: $ticket_key"
    echo "$ticket_key"
    return 0
}

#
# execute_pipeline - Execute all stages for a ticket
#
# Executes the complete pipeline for a single ticket by calling execute_stage
# for each stage in the workflow. Updates ticket status in state after each stage.
#
# Pipeline stages (from architecture.md):
# 1. plan - Create ticket planning documents
# 2. review - Review ticket for quality and completeness
# 3. tasks - Create tasks from plan
# 4. execute - Execute all tasks
# 5. pr - Create draft pull request
#
# Arguments:
#   $1 - ticket_key: JIRA ticket key to process
#
# Returns:
#   0 on success, 1 on any stage failure
#
execute_pipeline() {
    local ticket_key="$1"
    local stages=("plan" "review" "tasks" "execute" "pr")

    log_info "Executing pipeline for ticket: $ticket_key"

    # Update ticket status to in_progress
    local state_file="${RUN_DIR}/state.json"
    local state_content
    state_content=$(cat "$state_file")

    # Update current_ticket in state
    state_content=$(echo "$state_content" | jq ".current_ticket = \"$ticket_key\"")

    # Update ticket status to in_progress
    state_content=$(echo "$state_content" | jq "(.tickets[] | select(.key == \"$ticket_key\")).status = \"in_progress\"")

    if ! atomic_write "$state_file" "$state_content"; then
        log_error "Failed to update state for ticket: $ticket_key"
        return 1
    fi

    # Execute each stage
    for stage in "${stages[@]}"; do
        log_info "Executing stage '$stage' for ticket: $ticket_key"

        if [ "$DRY_RUN" = true ]; then
            log_info "DRY RUN: Would execute stage '$stage' for ticket: $ticket_key"
            continue
        fi

        # Call execute_stage from sdd-executor module
        local stage_result
        stage_result=$(execute_stage "$stage" "$ticket_key" "{}")

        if ! is_success "$stage_result"; then
            local error_msg
            error_msg=$(extract_field "$stage_result" "error")
            log_error "Stage '$stage' failed for ticket $ticket_key: $error_msg"

            # Update ticket status to failed
            state_content=$(cat "$state_file")
            state_content=$(echo "$state_content" | jq "(.tickets[] | select(.key == \"$ticket_key\")).status = \"failed\"")
            state_content=$(echo "$state_content" | jq "(.tickets[] | select(.key == \"$ticket_key\")).error = \"Stage '$stage' failed: $error_msg\"")
            atomic_write "$state_file" "$state_content"

            return 1
        fi

        log_info "Stage '$stage' completed successfully for ticket: $ticket_key"

        # Update stage completion in state
        state_content=$(cat "$state_file")
        state_content=$(echo "$state_content" | jq "(.tickets[] | select(.key == \"$ticket_key\")).completed_stages += [\"$stage\"]")
        atomic_write "$state_file" "$state_content"
    done

    # Mark ticket as completed
    state_content=$(cat "$state_file")
    state_content=$(echo "$state_content" | jq "(.tickets[] | select(.key == \"$ticket_key\")).status = \"completed\"")
    state_content=$(echo "$state_content" | jq ".current_ticket = null")

    if ! atomic_write "$state_file" "$state_content"; then
        log_error "Failed to mark ticket as completed: $ticket_key"
        return 1
    fi

    log_info "Pipeline completed successfully for ticket: $ticket_key"
    return 0
}

#
# generate_report - Generate final workflow summary report
#
# Creates a comprehensive report of the workflow run including:
# - Run metadata (ID, duration, input parameters)
# - Ticket summary (total, completed, failed)
# - Per-ticket results
# - Final status
#
# The report is written to RUN_DIR/report.txt and also logged.
#
# Arguments:
#   None (reads from RUN_DIR/state.json)
#
# Returns:
#   0 on success, 1 on failure
#
generate_report() {
    local state_file="${RUN_DIR}/state.json"
    local report_file="${RUN_DIR}/report.md"

    log_info "Generating workflow report..."

    if [ ! -f "$state_file" ]; then
        log_error "State file not found: $state_file"
        return 1
    fi

    local state_content
    state_content=$(cat "$state_file")

    # Extract report data
    local run_id
    local input_type
    local input_value
    local started_at
    local total_tickets
    local completed_tickets
    local failed_tickets
    local blocked_tickets

    run_id=$(extract_field "$state_content" "run_id")
    input_type=$(extract_field "$state_content" "input_type")
    input_value=$(extract_field "$state_content" "input_value")
    started_at=$(extract_field "$state_content" "started_at")

    total_tickets=$(echo "$state_content" | jq '.tickets | length' 2>/dev/null)
    completed_tickets=$(echo "$state_content" | jq '[.tickets[] | select(.status == "completed")] | length' 2>/dev/null)
    failed_tickets=$(echo "$state_content" | jq '[.tickets[] | select(.status == "failed")] | length' 2>/dev/null)
    blocked_tickets=$(echo "$state_content" | jq '[.tickets[] | select(.status == "blocked")] | length' 2>/dev/null)

    local finished_at
    finished_at=$(date -Iseconds)

    # Calculate duration
    local start_time end_time duration minutes seconds duration_str
    start_time=$(date -d "$started_at" +%s 2>/dev/null || echo "0")
    end_time=$(date -d "$finished_at" +%s 2>/dev/null || echo "0")
    duration=$((end_time - start_time))
    minutes=$((duration / 60))
    seconds=$((duration % 60))
    duration_str="${minutes}m ${seconds}s"

    # Construct input display
    local input_display
    if [ "$input_type" = "jql" ]; then
        input_display="--jql \"$input_value\""
    else
        input_display="$input_value"
    fi

    # Generate report content
    local report
    report=$(cat <<EOF
# Workflow Run Report

**Run ID:** $run_id
**Input:** $input_display
**Started:** $started_at
**Completed:** $finished_at
**Duration:** $duration_str

## Summary

- Total Tickets: $total_tickets
- Processed: $total_tickets
- Successful: $completed_tickets
- Failed: $failed_tickets
- Blocked: $blocked_tickets

## Tickets Processed

EOF
)

    # Add per-ticket details
    local tickets_json
    tickets_json=$(echo "$state_content" | jq -c '.tickets[]' 2>/dev/null)

    local counter=0
    while IFS= read -r ticket; do
        counter=$((counter + 1))
        local key status error status_display
        key=$(echo "$ticket" | jq -r '.key')
        status=$(echo "$ticket" | jq -r '.status')
        error=$(echo "$ticket" | jq -r '.error // ""')

        case "$status" in
            completed)
                status_display="Success"
                ;;
            failed)
                if [ -n "$error" ]; then
                    status_display="Failed ($error)"
                else
                    status_display="Failed"
                fi
                ;;
            blocked)
                if [ -n "$error" ]; then
                    status_display="Blocked ($error)"
                else
                    status_display="Blocked"
                fi
                ;;
            *)
                status_display="$status"
                ;;
        esac

        report+=$'\n'"${counter}. ${key} - ${status_display}"
    done <<< "$tickets_json"

    report+=$'\n'$'\n'"## Details"
    report+=$'\n'$'\n'"See full logs at: ${RUN_DIR}/logs/run.log"

    # Write report to file
    if ! echo "$report" > "$report_file"; then
        log_error "Failed to write report file: $report_file"
        return 1
    fi

    # Update state with finished timestamp and status
    state_content=$(echo "$state_content" | jq ".finished_at = \"$finished_at\"")

    if [ "$failed_tickets" -gt 0 ]; then
        state_content=$(echo "$state_content" | jq '.status = "completed_with_failures"')
    else
        state_content=$(echo "$state_content" | jq '.status = "completed"')
    fi

    if ! atomic_write "$state_file" "$state_content"; then
        log_error "Failed to update final state"
        return 1
    fi

    # Log report summary
    log_info "Workflow report generated: $report_file"
    log_info "Summary: $completed_tickets/$total_tickets tickets completed successfully"

    if [ "$failed_tickets" -gt 0 ]; then
        log_warn "Warning: $failed_tickets ticket(s) failed"
    fi

    return 0
}

#
# run_workflow - Main workflow execution loop
#
# Orchestrates the complete workflow cycle:
# 1. Phase 1: Fetch tickets based on INPUT_TYPE and INPUT_VALUE
# 2. Phase 2: Prioritize tickets using decision engine
# 3. Phase 3: Execute pipeline for each ticket
# 4. Phase 4: Generate final report
#
# Implements safety features:
# - Maximum iteration limit (100 tickets) to prevent infinite loops
# - State persistence after each phase
# - DRY_RUN mode support
# - Comprehensive error handling
#
# Arguments:
#   None (uses global variables INPUT_TYPE, INPUT_VALUE, DRY_RUN, RUN_DIR)
#
# Returns:
#   0 on success, 5 on workflow error
#
run_workflow() {
    local max_iterations=100
    local iteration_count=0

    log_info "Starting workflow run: $RUN_ID"
    log_info "Input: $INPUT_TYPE = $INPUT_VALUE"

    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN MODE: Validation only, no execution"
    fi

    # Phase 1: Fetch tickets
    log_info "Phase 1: Fetching tickets..."

    local fetch_result
    fetch_result=$(fetch_tickets "$INPUT_TYPE" "$INPUT_VALUE")

    if ! is_success "$fetch_result"; then
        local error_msg
        error_msg=$(extract_field "$fetch_result" "error")
        log_error "Failed to fetch tickets: $error_msg"
        return 5
    fi

    # Extract ticket list and update state
    local tickets_json
    tickets_json=$(extract_field "$fetch_result" "result.tickets")

    local state_file="${RUN_DIR}/state.json"
    local state_content
    state_content=$(cat "$state_file")

    # Transform tickets to include status and completed_stages fields
    local tickets_with_status
    tickets_with_status=$(echo "$tickets_json" | jq '[.[] | . + {status: "pending", completed_stages: [], error: null}]')

    state_content=$(echo "$state_content" | jq ".tickets = $tickets_with_status")

    if ! atomic_write "$state_file" "$state_content"; then
        log_error "Failed to save tickets to state"
        return 5
    fi

    local ticket_count
    ticket_count=$(echo "$tickets_json" | jq 'length' 2>/dev/null)
    log_info "Fetched $ticket_count ticket(s)"

    if [ "$ticket_count" -eq 0 ]; then
        log_warn "No tickets found to process"
        generate_report
        return 0
    fi

    # Phase 2: Prioritize tickets (optional, using decision engine)
    log_info "Phase 2: Prioritizing tickets..."

    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would prioritize $ticket_count tickets"
    else
        # Call decision engine to prioritize tickets
        local priority_context
        priority_context=$(cat <<EOF
{
  "task": "prioritize_tickets",
  "tickets": $tickets_json,
  "risk_tolerance": "${CONFIG_RISK_TOLERANCE:-moderate}"
}
EOF
)

        local priority_result
        priority_result=$(make_decision "$priority_context" "{}")

        if ! is_success "$priority_result"; then
            log_warn "Ticket prioritization failed, using original order"
        else
            log_info "Tickets prioritized successfully"
        fi
    fi

    # Save checkpoint after fetch and prioritize phases
    if ! save_checkpoint "after_fetch_and_prioritize"; then
        log_warn "Failed to save checkpoint after phase 2"
    fi

    # Phase 3: Execute pipeline for each ticket
    log_info "Phase 3: Executing ticket pipelines..."

    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would execute pipelines for $ticket_count tickets"
        log_info "DRY RUN: Workflow validated successfully"
        generate_report
        return 0
    fi

    while has_pending_tickets; do
        # Safety check: prevent infinite loops
        iteration_count=$((iteration_count + 1))
        if [ $iteration_count -gt $max_iterations ]; then
            log_error "Maximum iteration limit ($max_iterations) reached, aborting workflow"
            generate_report
            return 5
        fi

        # Select next ticket
        local ticket
        if ! ticket=$(select_next_ticket); then
            log_debug "No more pending tickets"
            break
        fi

        log_info "Processing ticket ($iteration_count/$ticket_count): $ticket"

        # Execute pipeline for ticket
        if ! execute_pipeline "$ticket"; then
            log_error "Pipeline failed for ticket: $ticket"
            # Continue with next ticket (don't abort entire workflow)
            continue
        fi

        # Save checkpoint after each ticket if configured
        if [ "${CONFIG_CHECKPOINT_FREQUENCY:-per_stage}" = "per_ticket" ]; then
            if ! save_checkpoint "after_ticket_${ticket}"; then
                log_warn "Failed to save checkpoint after ticket: $ticket"
            fi
        fi
    done

    log_info "Phase 3 complete: Processed $iteration_count ticket(s)"

    # Phase 4: Generate final report
    log_info "Phase 4: Generating final report..."

    if ! generate_report; then
        log_error "Failed to generate final report"
        return 5
    fi

    log_info "Workflow complete: $RUN_ID"

    # Return success if we completed successfully
    return 0
}

#
# Main execution
#
main() {
    # Parse command-line arguments
    parse_arguments "$@"

    # Load and validate modules
    load_modules

    # Initialize run (creates unique ID and directory structure)
    initialize_run

    # Load configuration
    if ! load_config; then
        log_error "Failed to load configuration"
        exit 2
    fi

    # Execute workflow
    if ! run_workflow; then
        log_error "Workflow execution failed"
        exit 5
    fi

    log_info "Orchestrator completed successfully"
    return 0
}

# Only run main if script is executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
