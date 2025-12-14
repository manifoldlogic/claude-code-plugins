#!/usr/bin/env bash
#
# Module: state-manager
# Status: ACTIVE
# Version: 1.0.0
# Description: State persistence and checkpoint management for SDD automation workflow
#
# This module provides atomic state persistence using filesystem-based JSON files.
# It manages the workflow state (state.json) and checkpoints for recovery scenarios.
#
# Key Functions:
# - save_state(state_json) - Atomically persist workflow state
# - load_state() - Load and validate current workflow state
# - validate_state() - Comprehensive state validation (structure, types, enums, referential integrity)
# - save_checkpoint(checkpoint_json) - Save recovery checkpoint
# - restore_checkpoint(checkpoint_id) - Restore from checkpoint
#
# Dependencies:
# - lib/common.sh - atomic_write(), log_* functions, JSON helpers
# - RUN_DIR environment variable - Must be set before sourcing this module
#
# Usage:
#   export RUN_DIR=/path/to/run/directory
#   source modules/state-manager.sh
#   save_state '{"run_id": "123", "status": "running"}'
#   state=$(load_state)
#

set -euo pipefail

# Source common library for atomic_write and logging functions
# Determine script directory - handle both sourcing and direct execution
if [ -n "${BASH_SOURCE[0]:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    # Fallback for contexts where BASH_SOURCE is not available
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

#
# RUN_DIR Validation
#
# RUN_DIR must be set before sourcing this module. It defines the directory
# where state.json and checkpoints/ will be stored. The orchestrator is
# responsible for setting RUN_DIR during initialize_run().
#
if [ -z "${RUN_DIR:-}" ]; then
    log_error "RUN_DIR not set - module must be loaded after orchestrator initialization"
    return 1
fi

#
# Global Variables
#
# These paths are derived from RUN_DIR and used throughout the module.
# - STATE_FILE: Path to the workflow state JSON file
# - CHECKPOINT_DIR: Directory containing checkpoint snapshots
#
STATE_FILE="${RUN_DIR}/state.json"
CHECKPOINT_DIR="${RUN_DIR}/checkpoints"

log_debug "state-manager initialized with STATE_FILE=$STATE_FILE"

#
# save_state - Atomically persist workflow state to state.json
#
# Validates JSON syntax, then writes state to disk using atomic_write() to
# ensure consistency. The atomic write pattern prevents partial writes and
# race conditions.
#
# Arguments:
#   $1 - Complete state JSON as string
#
# Returns:
#   JSON response with format:
#   {
#     "success": true|false,
#     "result": {"message": "State saved successfully"},
#     "next_action": "proceed",
#     "error": null|"error message"
#   }
#
# Examples:
#   state='{"run_id": "123", "status": "running", "tickets": []}'
#   response=$(save_state "$state")
#   if is_success "$response"; then
#       log_info "State saved successfully"
#   fi
#
#   # Invalid JSON triggers validation error
#   response=$(save_state '{broken json')
#   # Returns: {"success": false, "error": "Invalid JSON syntax", ...}
#
save_state() {
    local state_json="${1:-}"

    # Validate input is provided
    if [ -z "$state_json" ]; then
        log_error "save_state: No state JSON provided"
        cat << EOF
{
  "success": false,
  "result": {},
  "next_action": "block",
  "error": "No state JSON provided"
}
EOF
        return 1
    fi

    # Validate JSON syntax before writing
    if ! validate_json "$state_json"; then
        log_error "save_state: Invalid JSON syntax"
        cat << EOF
{
  "success": false,
  "result": {},
  "next_action": "block",
  "error": "Invalid JSON syntax"
}
EOF
        return 1
    fi

    # Write state atomically using atomic_write from common.sh
    # atomic_write handles:
    # - Temp file creation
    # - Write operation
    # - Permission setting (600)
    # - Atomic rename
    if ! atomic_write "$STATE_FILE" "$state_json"; then
        log_error "save_state: Failed to write state file: $STATE_FILE"
        cat << EOF
{
  "success": false,
  "result": {},
  "next_action": "retry",
  "error": "Failed to write state file"
}
EOF
        return 1
    fi

    log_info "State saved successfully to $STATE_FILE"
    cat << EOF
{
  "success": true,
  "result": {
    "message": "State saved successfully",
    "state_file": "$STATE_FILE"
  },
  "next_action": "proceed",
  "error": null
}
EOF
    return 0
}

#
# load_state - Load and validate workflow state from state.json
#
# Reads state.json, validates its structure, and returns the state content
# in the result.state field. This function does NOT create the state file;
# it must already exist (created by orchestrator's initialize_run()).
#
# Arguments:
#   None
#
# Returns:
#   JSON response with format:
#   {
#     "success": true|false,
#     "result": {
#       "state": { /* actual state content */ }
#     },
#     "next_action": "proceed",
#     "error": null|"error message"
#   }
#
# Examples:
#   response=$(load_state)
#   if is_success "$response"; then
#       state=$(extract_field "$response" "result.state")
#       run_id=$(echo "$state" | jq -r '.run_id')
#   fi
#
#   # Missing state file triggers error
#   # Returns: {"success": false, "error": "State file not found", ...}
#
load_state() {
    # Check if state file exists
    if [ ! -f "$STATE_FILE" ]; then
        log_error "load_state: State file not found: $STATE_FILE"
        cat << EOF
{
  "success": false,
  "result": {},
  "next_action": "block",
  "error": "State file not found: $STATE_FILE"
}
EOF
        return 1
    fi

    # Read state file content
    local state_content
    state_content=$(cat "$STATE_FILE" 2>/dev/null) || {
        log_error "load_state: Failed to read state file: $STATE_FILE"
        cat << EOF
{
  "success": false,
  "result": {},
  "next_action": "retry",
  "error": "Failed to read state file"
}
EOF
        return 1
    }

    # Validate JSON structure
    if ! validate_json "$state_content"; then
        log_error "load_state: State file contains invalid JSON: $STATE_FILE"
        cat << EOF
{
  "success": false,
  "result": {},
  "next_action": "block",
  "error": "State file contains invalid JSON"
}
EOF
        return 1
    fi

    log_debug "State loaded successfully from $STATE_FILE"

    # Return state in result.state field
    # Use jq to properly embed the state as a JSON object
    jq -n \
        --argjson state "$state_content" \
        '{
            "success": true,
            "result": {
                "state": $state
            },
            "next_action": "proceed",
            "error": null
        }'

    return 0
}

#
# validate_state - Comprehensive state validation
#
# Validates workflow state structure, field types, enum values, referential
# integrity, and state transitions. This function provides fail-fast detection
# of state corruption and prevents invalid state modifications.
#
# State Schema (from orchestrator.sh initialize_run()):
# {
#   "run_id": "string (required)",
#   "status": "string (required) - enum: running|paused|completed|failed|completed_with_failures",
#   "input_type": "string (required) - enum: jql|epic|team|tickets|resume",
#   "input_value": "string (required)",
#   "started_at": "ISO 8601 timestamp (required)",
#   "finished_at": "ISO 8601 timestamp (optional)",
#   "tickets": [array of ticket objects],
#   "current_ticket": "string or null"
# }
#
# Validation Checks:
# 1. State file exists
# 2. Valid JSON syntax
# 3. All required fields present
# 4. Field types correct (tickets=array, status=string, etc.)
# 5. Enum values valid (status, input_type)
# 6. State transition legality (if previous_status provided)
# 7. Referential integrity (current_ticket exists in tickets array if not null)
#
# State Transition Rules:
# - Terminal states (completed, failed, completed_with_failures) cannot transition to other states
# - running -> completed|failed|paused (OK)
# - paused -> running (OK)
# - completed -> * (INVALID - terminal state)
# - failed -> * (INVALID - terminal state)
# - completed_with_failures -> * (INVALID - terminal state)
#
# Arguments:
#   $1 - (Optional) previous_status - If provided, validates state transition is legal
#
# Returns:
#   JSON response with format:
#   {
#     "success": true|false,
#     "result": {"message": "State validation passed"},
#     "next_action": "proceed"|"block",
#     "error": null|"specific validation error message"
#   }
#
# Examples:
#   # Validate state structure only
#   response=$(validate_state)
#   if is_success "$response"; then
#       log_info "State is valid"
#   else
#       error=$(extract_field "$response" "error")
#       log_error "State validation failed: $error"
#   fi
#
#   # Validate state transition
#   previous_status="running"
#   response=$(validate_state "$previous_status")
#   # Will fail if current state is invalid transition from running
#
validate_state() {
    local previous_status="${1:-}"
    # Check state file exists
    if [ ! -f "${STATE_FILE}" ]; then
        log_error "validate_state: State file not found: ${STATE_FILE}"
        cat << EOF
{
  "success": false,
  "result": {},
  "next_action": "block",
  "error": "State file not found"
}
EOF
        return 1
    fi

    # Validate JSON syntax
    if ! jq empty "${STATE_FILE}" 2>/dev/null; then
        log_error "validate_state: Invalid JSON syntax in state file"
        cat << EOF
{
  "success": false,
  "result": {},
  "next_action": "block",
  "error": "Invalid JSON syntax"
}
EOF
        return 1
    fi

    # Check all required fields are present
    local missing_fields
    missing_fields=$(jq -r '
        [
            (if has("run_id") then empty else "run_id" end),
            (if has("status") then empty else "status" end),
            (if has("input_type") then empty else "input_type" end),
            (if has("input_value") then empty else "input_value" end),
            (if has("started_at") then empty else "started_at" end),
            (if has("tickets") then empty else "tickets" end),
            (if has("current_ticket") then empty else "current_ticket" end)
        ] | join(", ")
    ' "${STATE_FILE}")

    if [ -n "$missing_fields" ]; then
        log_error "validate_state: Missing required fields: $missing_fields"
        cat << EOF
{
  "success": false,
  "result": {},
  "next_action": "block",
  "error": "Missing required fields: $missing_fields"
}
EOF
        return 1
    fi

    # Validate field types
    local type_errors
    type_errors=$(jq -r '
        [
            (if (.run_id | type) == "string" then empty else "run_id must be string" end),
            (if (.status | type) == "string" then empty else "status must be string" end),
            (if (.input_type | type) == "string" then empty else "input_type must be string" end),
            (if (.input_value | type) == "string" then empty else "input_value must be string" end),
            (if (.started_at | type) == "string" then empty else "started_at must be string" end),
            (if (.tickets | type) == "array" then empty else "tickets must be array" end),
            (if (.current_ticket | type) == "string" or .current_ticket == null then empty else "current_ticket must be string or null" end)
        ] | join(", ")
    ' "${STATE_FILE}")

    if [ -n "$type_errors" ]; then
        log_error "validate_state: Type validation failed: $type_errors"
        cat << EOF
{
  "success": false,
  "result": {},
  "next_action": "block",
  "error": "Type validation failed: $type_errors"
}
EOF
        return 1
    fi

    # Validate status enum
    local status
    status=$(jq -r '.status' "${STATE_FILE}")
    case "$status" in
        running|paused|completed|failed|completed_with_failures)
            # Valid status
            ;;
        *)
            log_error "validate_state: Invalid status value: $status"
            cat << EOF
{
  "success": false,
  "result": {},
  "next_action": "block",
  "error": "Invalid status value: $status (must be: running, paused, completed, failed, or completed_with_failures)"
}
EOF
            return 1
            ;;
    esac

    # Validate input_type enum
    local input_type
    input_type=$(jq -r '.input_type' "${STATE_FILE}")
    case "$input_type" in
        jql|epic|team|tickets|resume)
            # Valid input_type
            ;;
        *)
            log_error "validate_state: Invalid input_type value: $input_type"
            cat << EOF
{
  "success": false,
  "result": {},
  "next_action": "block",
  "error": "Invalid input_type value: $input_type (must be: jql, epic, team, tickets, or resume)"
}
EOF
            return 1
            ;;
    esac

    # Validate state transitions (if previous_status provided)
    # Terminal states (completed, failed, completed_with_failures) cannot transition to other states
    if [ -n "$previous_status" ]; then
        local current_status
        current_status=$(jq -r '.status' "${STATE_FILE}")

        case "$previous_status" in
            completed|failed|completed_with_failures)
                # Terminal states cannot transition to any other state
                if [ "$current_status" != "$previous_status" ]; then
                    log_error "validate_state: Invalid state transition: $previous_status -> $current_status"
                    cat << EOF
{
  "success": false,
  "result": {},
  "next_action": "block",
  "error": "Invalid state transition: $previous_status -> $current_status (terminal state cannot change)"
}
EOF
                    return 1
                fi
                ;;
            running|paused)
                # Non-terminal states can transition to any valid status
                # (already validated by status enum check above)
                ;;
            *)
                # Unknown previous_status - log warning but don't fail
                log_debug "validate_state: Unknown previous_status: $previous_status (skipping transition validation)"
                ;;
        esac
    fi

    # Validate current_ticket reference (if not null, must exist in tickets array)
    local current_ticket
    current_ticket=$(jq -r '.current_ticket' "${STATE_FILE}")
    if [ "$current_ticket" != "null" ] && [ -n "$current_ticket" ]; then
        local ticket_exists
        ticket_exists=$(jq --arg ticket "$current_ticket" '
            .tickets | map(select(.key == $ticket)) | length
        ' "${STATE_FILE}")

        if [ "$ticket_exists" -eq 0 ]; then
            log_error "validate_state: current_ticket references non-existent ticket: $current_ticket"
            cat << EOF
{
  "success": false,
  "result": {},
  "next_action": "block",
  "error": "current_ticket references non-existent ticket: $current_ticket"
}
EOF
            return 1
        fi
    fi

    # All validations passed
    log_debug "State validation passed"
    cat << EOF
{
  "success": true,
  "result": {
    "message": "State validation passed"
  },
  "next_action": "proceed",
  "error": null
}
EOF
    return 0
}

#
# ==============================================================================
# Internal Query Helpers
# ==============================================================================
#
# These functions are module-internal utilities (marked with underscore prefix)
# for querying workflow state. They are NOT part of the validated module interface
# and should not be called by the orchestrator.
#
# The orchestrator has its own query implementations:
# - has_pending_tickets() - orchestrator.sh lines 615-630
# - select_next_ticket() - orchestrator.sh lines 632-674
#
# These helpers are for potential module-internal use (e.g., in checkpoint
# metadata or validation logic).
#

#
# _get_current_ticket - Get current ticket object or null
#
# Internal helper that retrieves the current ticket object from state.json.
# Returns the full ticket object if current_ticket is set, or null if no
# current ticket.
#
# Arguments:
#   None
#
# Returns:
#   JSON response with format:
#   {
#     "success": true,
#     "result": {
#       "ticket": { /* ticket object */ } | null
#     },
#     "next_action": "proceed",
#     "error": null
#   }
#
# Examples:
#   response=$(_get_current_ticket)
#   ticket=$(extract_field "$response" "result.ticket")
#   if [ "$ticket" != "null" ]; then
#       ticket_key=$(echo "$ticket" | jq -r '.key')
#   fi
#
_get_current_ticket() {
    local current
    current=$(jq -r '.current_ticket' "${STATE_FILE}")

    if [ "$current" = "null" ]; then
        echo '{"success":true,"result":{"ticket":null},"next_action":"proceed","error":null}'
    else
        local ticket
        ticket=$(jq --arg key "$current" '.tickets[] | select(.key == $key)' "${STATE_FILE}")
        echo "{\"success\":true,\"result\":{\"ticket\":$ticket},\"next_action\":\"proceed\",\"error\":null}"
    fi
}

#
# _get_ticket_status - Get status for a specific ticket
#
# Internal helper that retrieves the status field for a given ticket key.
# Returns an error if the ticket key does not exist in the state.
#
# Arguments:
#   $1 - ticket_key: The ticket key to query (required)
#
# Returns:
#   JSON response with format:
#   Success case:
#   {
#     "success": true,
#     "result": {"status": "pending|in_progress|completed|failed"},
#     "next_action": "proceed",
#     "error": null
#   }
#
#   Error case (ticket not found):
#   {
#     "success": false,
#     "result": {},
#     "next_action": "block",
#     "error": "Ticket not found: TICKET-123"
#   }
#
# Examples:
#   response=$(_get_ticket_status "ASDW-1")
#   if is_success "$response"; then
#       status=$(extract_field "$response" "result.status")
#       echo "Ticket ASDW-1 status: $status"
#   fi
#
_get_ticket_status() {
    local ticket_key="$1"
    local status
    status=$(jq -r --arg key "$ticket_key" '.tickets[] | select(.key == $key) | .status' "${STATE_FILE}")

    if [ -z "$status" ]; then
        echo "{\"success\":false,\"result\":{},\"next_action\":\"block\",\"error\":\"Ticket not found: $ticket_key\"}"
        return 1
    fi

    echo "{\"success\":true,\"result\":{\"status\":\"$status\"},\"next_action\":\"proceed\",\"error\":null}"
}

#
# _is_workflow_complete - Check if workflow has any pending or in-progress tickets
#
# Internal helper that determines if the workflow is complete by checking for
# any tickets with status "pending" or "in_progress". Returns true (exit code 0)
# if workflow is complete, false (exit code 1) if work remains.
#
# Arguments:
#   None
#
# Returns:
#   JSON response with format:
#   Complete case (no pending/in_progress tickets):
#   {
#     "success": true,
#     "result": {"complete": true},
#     "next_action": "complete",
#     "error": null
#   }
#   Exit code: 0
#
#   Incomplete case (work remains):
#   {
#     "success": true,
#     "result": {"complete": false},
#     "next_action": "proceed",
#     "error": null
#   }
#   Exit code: 1
#
# Examples:
#   response=$(_is_workflow_complete)
#   exit_code=$?
#   if [ $exit_code -eq 0 ]; then
#       echo "Workflow is complete"
#   else
#       echo "Work remains"
#   fi
#
#   # Or check the result field
#   complete=$(extract_field "$response" "result.complete")
#   if [ "$complete" = "true" ]; then
#       echo "Workflow is complete"
#   fi
#
_is_workflow_complete() {
    local pending_count
    pending_count=$(jq '[.tickets[] | select(.status == "pending" or .status == "in_progress")] | length' "${STATE_FILE}")

    if [ "$pending_count" -eq 0 ]; then
        echo '{"success":true,"result":{"complete":true},"next_action":"complete","error":null}'
        return 0
    else
        echo '{"success":true,"result":{"complete":false},"next_action":"proceed","error":null}'
        return 1
    fi
}

#
# ==============================================================================
# Checkpoint Functions
# ==============================================================================
#

#
# _get_next_checkpoint_number - Get next sequential checkpoint number
#
# Internal helper that determines the next checkpoint number by finding the
# highest existing checkpoint number and incrementing it. Returns zero-padded
# 3-digit string (001, 002, etc.).
#
# Arguments:
#   None
#
# Returns:
#   Zero-padded checkpoint number (e.g., "001", "002", "015")
#
_get_next_checkpoint_number() {
    local checkpoint_dir="${CHECKPOINT_DIR}"
    mkdir -p "$checkpoint_dir"

    # Find highest existing checkpoint number
    local max_num
    max_num=$(ls -1 "$checkpoint_dir"/checkpoint_*.json 2>/dev/null | \
        sed 's/.*checkpoint_\([0-9]*\)\.json/\1/' | \
        sort -n | \
        tail -1)

    if [ -z "$max_num" ]; then
        echo "001"
    else
        printf "%03d" $((10#$max_num + 1))
    fi
}

#
# _rotate_checkpoints - Delete oldest checkpoints when over limit
#
# Internal helper that enforces CONFIG_CHECKPOINT_MAX by deleting the oldest
# checkpoint files (FIFO). Called after each checkpoint creation.
#
# Arguments:
#   None
#
# Environment:
#   CONFIG_CHECKPOINT_MAX - Maximum checkpoints to keep (default: 10)
#
_rotate_checkpoints() {
    local checkpoint_dir="${CHECKPOINT_DIR}"
    local max_checkpoints="${CONFIG_CHECKPOINT_MAX:-10}"

    # Count existing checkpoints
    local count
    count=$(ls -1 "$checkpoint_dir"/checkpoint_*.json 2>/dev/null | wc -l)

    # Delete oldest if over limit (rotate after new checkpoint is written)
    while [ "$count" -gt "$max_checkpoints" ]; do
        local oldest
        oldest=$(ls -1 "$checkpoint_dir"/checkpoint_*.json 2>/dev/null | sort | head -1)
        if [ -n "$oldest" ]; then
            rm -f "$oldest"
            log_debug "Rotated out checkpoint: $oldest"
        fi
        count=$((count - 1))
    done
}

#
# save_checkpoint - Save recovery checkpoint with rotation
#
# Creates a timestamped checkpoint file containing the current state snapshot
# and metadata. Checkpoint files are numbered sequentially (001, 002, etc.)
# and rotated when count exceeds CONFIG_CHECKPOINT_MAX.
#
# Arguments:
#   $1 - label: Human-readable label for the checkpoint (required)
#        Examples: "after_fetch_and_prioritize", "after_ticket_UIT-1234"
#
# Checkpoint Structure:
#   {
#     "checkpoint_id": "checkpoint_004",
#     "label": "after_plan_stage",
#     "created_at": "2025-12-14T14:35:00-05:00",
#     "state": { /* complete state.json snapshot */ }
#   }
#
# Returns:
#   JSON response with format:
#   {
#     "success": true|false,
#     "result": {"checkpoint_id": "checkpoint_004"},
#     "next_action": "proceed",
#     "error": null|"error message"
#   }
#
# Examples:
#   # After fetching tickets
#   response=$(save_checkpoint "after_fetch_and_prioritize")
#
#   # After completing a ticket
#   response=$(save_checkpoint "after_ticket_${ticket_key}")
#
save_checkpoint() {
    local label="${1:-}"

    # Validate label provided
    if [ -z "$label" ]; then
        log_error "save_checkpoint: Label required"
        echo '{"success":false,"result":{},"next_action":"block","error":"Label required"}'
        return 1
    fi

    # Verify state file exists
    if [ ! -f "$STATE_FILE" ]; then
        log_error "save_checkpoint: State file not found: $STATE_FILE"
        echo '{"success":false,"result":{},"next_action":"block","error":"State file not found"}'
        return 1
    fi

    # Read current state
    local state_content
    state_content=$(cat "$STATE_FILE" 2>/dev/null) || {
        log_error "save_checkpoint: Failed to read state file"
        echo '{"success":false,"result":{},"next_action":"retry","error":"Failed to read state file"}'
        return 1
    }

    # Validate state is valid JSON
    if ! validate_json "$state_content"; then
        log_error "save_checkpoint: State file contains invalid JSON"
        echo '{"success":false,"result":{},"next_action":"block","error":"State file contains invalid JSON"}'
        return 1
    fi

    # Get next checkpoint number
    local checkpoint_num
    checkpoint_num=$(_get_next_checkpoint_number)
    local checkpoint_id="checkpoint_${checkpoint_num}"
    local checkpoint_file="${CHECKPOINT_DIR}/${checkpoint_id}.json"

    # Create checkpoint structure with jq
    local created_at
    created_at=$(date -Iseconds)
    local checkpoint
    checkpoint=$(jq -n \
        --arg id "$checkpoint_id" \
        --arg lbl "$label" \
        --arg created "$created_at" \
        --argjson state "$state_content" \
        '{"checkpoint_id": $id, "label": $lbl, "created_at": $created, "state": $state}')

    # Write checkpoint atomically
    if ! atomic_write "$checkpoint_file" "$checkpoint"; then
        log_error "save_checkpoint: Failed to write checkpoint file: $checkpoint_file"
        echo '{"success":false,"result":{},"next_action":"retry","error":"Failed to write checkpoint file"}'
        return 1
    fi

    log_info "Checkpoint saved: $checkpoint_id ($label)"

    # Rotate if needed (after successful write)
    _rotate_checkpoints

    # Return success response
    echo "{\"success\":true,\"result\":{\"checkpoint_id\":\"$checkpoint_id\"},\"next_action\":\"proceed\",\"error\":null}"
    return 0
}

#
# restore_checkpoint - Restore state from a saved checkpoint
#
# Reads a checkpoint file, validates its structure, and restores the embedded
# state to state.json. Supports "latest" keyword to restore the most recent
# checkpoint without knowing its ID.
#
# Arguments:
#   $1 - checkpoint_id: Either a specific checkpoint ID (e.g., "checkpoint_003")
#        or "latest" to restore the most recent checkpoint
#
# Returns:
#   JSON response with format:
#   {
#     "success": true|false,
#     "result": {"checkpoint_id": "checkpoint_003", "restored": true},
#     "next_action": "proceed",
#     "error": null|"error message"
#   }
#
# Examples:
#   # Restore specific checkpoint
#   response=$(restore_checkpoint "checkpoint_003")
#
#   # Restore most recent checkpoint
#   response=$(restore_checkpoint "latest")
#
restore_checkpoint() {
    local checkpoint_id="${1:-}"

    # Validate parameter
    if [ -z "$checkpoint_id" ]; then
        log_error "restore_checkpoint: Checkpoint ID required"
        echo '{"success":false,"result":{},"next_action":"block","error":"Checkpoint ID required"}'
        return 1
    fi

    # Handle "latest" shortcut
    if [ "$checkpoint_id" = "latest" ]; then
        checkpoint_id=$(ls -1 "${CHECKPOINT_DIR}"/checkpoint_*.json 2>/dev/null | \
            sed 's/.*checkpoint_\([0-9]*\)\.json/checkpoint_\1/' | \
            sort | \
            tail -1)

        if [ -z "$checkpoint_id" ]; then
            log_error "restore_checkpoint: No checkpoints available"
            echo '{"success":false,"result":{},"next_action":"block","error":"No checkpoints available"}'
            return 1
        fi
    fi

    # Build checkpoint file path
    local checkpoint_file="${CHECKPOINT_DIR}/${checkpoint_id}.json"

    # Check file exists
    if [ ! -f "$checkpoint_file" ]; then
        log_error "restore_checkpoint: Checkpoint not found: $checkpoint_id"
        echo "{\"success\":false,\"result\":{},\"next_action\":\"block\",\"error\":\"Checkpoint not found: $checkpoint_id\"}"
        return 1
    fi

    # Validate checkpoint structure (has required fields)
    if ! jq -e '.checkpoint_id and .label and .created_at and .state' "$checkpoint_file" >/dev/null 2>&1; then
        log_error "restore_checkpoint: Checkpoint corrupted or invalid structure: $checkpoint_id"
        echo '{"success":false,"result":{},"next_action":"block","error":"Checkpoint corrupted or invalid structure"}'
        return 1
    fi

    # Extract state from checkpoint
    local restored_state
    restored_state=$(jq '.state' "$checkpoint_file")

    # Restore state using save_state (ensures validation and atomic write)
    # Filter out log lines (timestamp prefix) to get only JSON response
    local save_result
    save_result=$(save_state "$restored_state" | grep -v '^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T')

    # Check if save_state succeeded
    local save_success
    save_success=$(echo "$save_result" | jq -r '.success' 2>/dev/null)
    if [ "$save_success" != "true" ]; then
        local save_error
        save_error=$(echo "$save_result" | jq -r '.error')
        log_error "restore_checkpoint: Failed to restore state: $save_error"
        echo "{\"success\":false,\"result\":{},\"next_action\":\"block\",\"error\":\"Failed to restore state: $save_error\"}"
        return 1
    fi

    log_info "Checkpoint restored: $checkpoint_id"

    # Return success
    echo "{\"success\":true,\"result\":{\"checkpoint_id\":\"$checkpoint_id\",\"restored\":true},\"next_action\":\"proceed\",\"error\":null}"
    return 0
}
