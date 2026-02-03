#!/bin/sh
#
# Task Sync Writer - Updates task file checkboxes based on Tasks API status
#
# This script synchronizes task completion state from the Tasks API back to
# task markdown files, completing the bidirectional sync layer.
#
# Usage:
#   sync-task-status.sh <TASK_ID> <NEW_STATUS>
#
# Arguments:
#   TASK_ID     - Task ID (e.g., TASKINT.1001)
#   NEW_STATUS  - New status: 'pending', 'in_progress', or 'completed'
#
# Status Mapping:
#   'pending'     -> no file update needed (initial state)
#   'in_progress' -> no file update (work started, not completed)
#   'completed'   -> check "Task completed" checkbox: - [ ] -> - [x]
#
# Exit Codes:
#   0 - Success (status updated or no update needed)
#   1 - Error (invalid arguments, file not found, pattern not found, etc.)
#
# Environment Variables:
#   SDD_ROOT_DIR - Root directory for SDD data (default: /app/.sdd)
#   SDD_TASKS_SYNC_DEBUG - Set to 'true' for verbose logging
#
# Safety Features:
#   - Atomic write operations (write temp, move)
#   - File lock to prevent concurrent writes
#   - Preserves file permissions and ownership
#   - Validates pattern exists before modification
#

set -e

# ============================================================================
# Configuration
# ============================================================================

SDD_ROOT_DIR="${SDD_ROOT_DIR:-/app/.sdd}"
DEBUG="${SDD_TASKS_SYNC_DEBUG:-false}"

# Checkbox pattern to find (unchecked "Task completed")
# Matches: - [ ] **Task completed** with optional text after
UNCHECKED_PATTERN='^- \[ \] \*\*Task completed\*\*'

# Replacement pattern (checked)
# Note: We preserve the rest of the line after **Task completed**
CHECKED_REPLACEMENT='- [x] **Task completed**'

# Lock file suffix for concurrent write protection
LOCK_SUFFIX=".sync-lock"

# ============================================================================
# Utility Functions
# ============================================================================

# Log message to stderr
log() {
    printf "%s\n" "$1" >&2
}

# Debug logging (only when SDD_TASKS_SYNC_DEBUG=true)
debug() {
    if [ "$DEBUG" = "true" ]; then
        printf "[DEBUG] %s\n" "$1" >&2
    fi
}

# Print usage information
usage() {
    log "Usage: sync-task-status.sh <TASK_ID> <NEW_STATUS>"
    log ""
    log "Arguments:"
    log "  TASK_ID     Task ID (e.g., TASKINT.1001)"
    log "  NEW_STATUS  New status: 'pending', 'in_progress', or 'completed'"
    log ""
    log "Exit codes:"
    log "  0 - Success"
    log "  1 - Error"
}

# Acquire file lock for concurrent write protection
# Returns 0 if lock acquired, 1 if failed
acquire_lock() {
    local lockfile="$1"
    local max_attempts=10
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        # Try to create lock file atomically
        if ( set -C; : > "$lockfile" ) 2>/dev/null; then
            debug "Lock acquired: $lockfile"
            return 0
        fi

        # Check if lock is stale (older than 60 seconds)
        if [ -f "$lockfile" ]; then
            # Get lock file age in seconds (portable approach)
            local lock_time
            lock_time=$(stat -c %Y "$lockfile" 2>/dev/null || stat -f %m "$lockfile" 2>/dev/null || echo 0)
            local now
            now=$(date +%s)
            local age=$((now - lock_time))

            if [ $age -gt 60 ]; then
                debug "Removing stale lock (age: ${age}s): $lockfile"
                rm -f "$lockfile"
                continue
            fi
        fi

        attempt=$((attempt + 1))
        debug "Lock busy, waiting (attempt $attempt/$max_attempts)..."
        sleep 0.5 2>/dev/null || sleep 1
    done

    log "Error: Could not acquire lock after $max_attempts attempts"
    return 1
}

# Release file lock
release_lock() {
    local lockfile="$1"
    rm -f "$lockfile"
    debug "Lock released: $lockfile"
}

# ============================================================================
# Task File Discovery
# ============================================================================

# Find task file by TASK_ID
# Searches in SDD_ROOT_DIR/tickets/*/tasks/ for matching task file
# Returns: file path on stdout, exit 0 on success, exit 1 on failure
find_task_file() {
    local task_id="$1"
    local ticket_prefix

    # Extract ticket prefix from task ID (e.g., TASKINT from TASKINT.1001)
    ticket_prefix=$(printf "%s" "$task_id" | sed 's/\.[0-9]*$//')

    if [ -z "$ticket_prefix" ]; then
        log "Error: Could not extract ticket prefix from task ID: $task_id"
        return 1
    fi

    debug "Looking for task file with ID: $task_id (ticket prefix: $ticket_prefix)"

    # Search for the task file
    # Pattern: {SDD_ROOT_DIR}/tickets/{TICKET_PREFIX}_*/tasks/{TASK_ID}_*.md
    local tickets_dir="${SDD_ROOT_DIR}/tickets"

    if [ ! -d "$tickets_dir" ]; then
        log "Error: Tickets directory not found: $tickets_dir"
        return 1
    fi

    # Find matching ticket directory
    local task_file=""
    for ticket_dir in "$tickets_dir"/"${ticket_prefix}"_*; do
        if [ -d "$ticket_dir" ]; then
            local tasks_subdir="$ticket_dir/tasks"
            if [ -d "$tasks_subdir" ]; then
                # Look for task file with matching ID
                for candidate in "$tasks_subdir"/"${task_id}"_*.md; do
                    if [ -f "$candidate" ]; then
                        task_file="$candidate"
                        break 2
                    fi
                done
            fi
        fi
    done

    if [ -z "$task_file" ] || [ ! -f "$task_file" ]; then
        log "Error: Task file not found for ID: $task_id"
        debug "Searched in: ${tickets_dir}/${ticket_prefix}_*/tasks/${task_id}_*.md"
        return 1
    fi

    debug "Found task file: $task_file"
    printf "%s" "$task_file"
    return 0
}

# ============================================================================
# Checkbox Update Logic
# ============================================================================

# Check if file has unchecked "Task completed" checkbox
# Returns 0 if found, 1 if not
has_unchecked_checkbox() {
    local file="$1"
    grep -q "$UNCHECKED_PATTERN" "$file" 2>/dev/null
}

# Check if file has checked "Task completed" checkbox
# Returns 0 if found, 1 if not
has_checked_checkbox() {
    local file="$1"
    grep -q '^- \[x\] \*\*Task completed\*\*\|^- \[X\] \*\*Task completed\*\*' "$file" 2>/dev/null
}

# Update checkbox state in task file
# Uses atomic write: write to temp file, then move
# Returns 0 on success, 1 on failure
update_checkbox() {
    local file="$1"
    local temp_file
    local lockfile="${file}${LOCK_SUFFIX}"

    # Check if file is writable
    if [ ! -w "$file" ]; then
        log "Error: Task file is not writable: $file"
        return 1
    fi

    # Verify checkbox pattern exists before attempting update
    if ! has_unchecked_checkbox "$file"; then
        # Check if already checked
        if has_checked_checkbox "$file"; then
            debug "Checkbox already checked in: $file"
            return 0
        fi
        log "Error: Task completed checkbox pattern not found in: $file"
        return 1
    fi

    # Acquire lock for concurrent write protection
    if ! acquire_lock "$lockfile"; then
        return 1
    fi

    # Create temp file in same directory (for atomic move within filesystem)
    temp_file="${file}.tmp.$$"

    # Perform the substitution
    # sed pattern: Replace unchecked checkbox with checked checkbox
    # We match the entire line to preserve any trailing content
    if ! sed "s/^- \[ \] \*\*Task completed\*\*/- [x] **Task completed**/" "$file" > "$temp_file" 2>/dev/null; then
        log "Error: sed substitution failed for: $file"
        rm -f "$temp_file"
        release_lock "$lockfile"
        return 1
    fi

    # Verify the substitution was made
    if ! grep -q '^- \[x\] \*\*Task completed\*\*' "$temp_file" 2>/dev/null; then
        log "Error: Checkbox update verification failed for: $file"
        rm -f "$temp_file"
        release_lock "$lockfile"
        return 1
    fi

    # Preserve original file permissions
    if command -v chmod > /dev/null 2>&1; then
        chmod --reference="$file" "$temp_file" 2>/dev/null || true
    fi

    # Atomic move
    if ! mv -f "$temp_file" "$file"; then
        log "Error: Could not move temp file to: $file"
        rm -f "$temp_file"
        release_lock "$lockfile"
        return 1
    fi

    release_lock "$lockfile"
    debug "Successfully updated checkbox in: $file"
    return 0
}

# ============================================================================
# Main Logic
# ============================================================================

# Validate status value
# Returns 0 if valid, 1 if invalid
validate_status() {
    local status="$1"
    case "$status" in
        pending|in_progress|completed)
            return 0
            ;;
        *)
            log "Error: Invalid status value: $status"
            log "Valid values: pending, in_progress, completed"
            return 1
            ;;
    esac
}

# Main function
main() {
    local task_id="$1"
    local new_status="$2"

    # Validate arguments
    if [ -z "$task_id" ] || [ -z "$new_status" ]; then
        log "Error: Missing required arguments"
        usage
        return 1
    fi

    # Validate task ID format (e.g., TASKINT.1001, AUTH.2003)
    if ! printf "%s" "$task_id" | grep -qE '^[A-Z][A-Z0-9]*(-[A-Z0-9]+)*\.[0-9]{4}$'; then
        log "Error: Invalid task ID format: $task_id"
        log "Expected format: TICKETID.NNNN (e.g., TASKINT.1001)"
        return 1
    fi

    # Validate status
    if ! validate_status "$new_status"; then
        return 1
    fi

    debug "Processing: task_id=$task_id, new_status=$new_status"

    # Handle status based on mapping
    case "$new_status" in
        pending)
            debug "Status 'pending': No file update needed"
            return 0
            ;;
        in_progress)
            debug "Status 'in_progress': No file update needed"
            return 0
            ;;
        completed)
            debug "Status 'completed': Updating Task completed checkbox"

            # Find the task file
            local task_file
            if ! task_file=$(find_task_file "$task_id"); then
                return 1
            fi

            # Update the checkbox
            if ! update_checkbox "$task_file"; then
                return 1
            fi

            log "Successfully synced status 'completed' to: $task_file"
            return 0
            ;;
    esac

    # Should not reach here
    log "Error: Unexpected status: $new_status"
    return 1
}

# ============================================================================
# Entry Point
# ============================================================================

# Run main function with all arguments
main "$@"
