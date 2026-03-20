#!/usr/bin/env bash
#
# cmux-wait.sh - Polling utilities for cmux workspace and terminal readiness
#
# DESCRIPTION:
#   Provides polling functions that wait for cmux operations to complete.
#   Replaces hard-coded sleep calls with condition-based polling via
#   cmux-ssh.sh subcommands (list-workspaces, read-screen).
#
# USAGE:
#   Source this file to use the polling functions:
#     source /path/to/cmux-wait.sh
#
# FUNCTIONS:
#   cmux_wait_workspace()  - Poll until workspace ID appears in list-workspaces
#   cmux_wait_prompt()     - Poll until shell prompt appears in read-screen
#
# EXIT CODES:
#   0 - Readiness condition met
#   1 - Timeout expired or invalid arguments
#
# ENVIRONMENT VARIABLES:
#   CMUX_WAIT_WS_TIMEOUT      - Max seconds to wait for workspace (default: 5)
#   CMUX_WAIT_WS_INTERVAL     - Seconds between workspace polls (default: 0.3)
#   CMUX_WAIT_PROMPT_TIMEOUT   - Max seconds to wait for prompt (default: 10)
#   CMUX_WAIT_PROMPT_INTERVAL  - Seconds between prompt polls (default: 0.5)
#   CMUX_PROMPT_PATTERN        - grep -E pattern for shell prompt (default: '[^#\$%][\$#%] *$')
#   CMUX_READ_SCREEN_LINES     - Number of screen lines to read (default: 5)
#   VERBOSE                    - Set to "true" to emit debug polling lines

##############################################################################
# Direct Execution Guard
##############################################################################

# shellcheck disable=SC2128
if [[ -n "${BASH_SOURCE:-}" && "${BASH_SOURCE[0]:-}" == "${0:-}" ]]; then
    echo "Error: cmux-wait.sh must be sourced, not executed directly." >&2
    exit 1
fi

##############################################################################
# Configuration Defaults
##############################################################################

: "${CMUX_WAIT_WS_TIMEOUT:=5}"
: "${CMUX_WAIT_WS_INTERVAL:=0.3}"
: "${CMUX_WAIT_PROMPT_TIMEOUT:=10}"
: "${CMUX_WAIT_PROMPT_INTERVAL:=0.5}"
: "${CMUX_PROMPT_PATTERN:=[^#\$%][\$#%] *$}"
: "${CMUX_READ_SCREEN_LINES:=5}"

##############################################################################
# Polling Functions
##############################################################################

# Wait for a workspace to appear in cmux list-workspaces output
#
# Args:
#   $1 - workspace_id (e.g., "workspace:3")
#   $2 - cmux_ssh_script_path (path to cmux-ssh.sh)
#
# Returns:
#   0 if workspace found within timeout
#   1 if timeout expired or invalid arguments
cmux_wait_workspace() {
    local workspace_id="${1:-}"
    local cmux_ssh_script="${2:-}"

    if [ -z "$workspace_id" ]; then
        echo "[cmux-wait] ERROR: cmux_wait_workspace requires a workspace_id argument" >&2
        return 1
    fi

    if [ -z "$cmux_ssh_script" ]; then
        echo "[cmux-wait] ERROR: cmux_wait_workspace requires a cmux_ssh_script_path argument" >&2
        return 1
    fi

    local timeout="${CMUX_WAIT_WS_TIMEOUT}"
    local interval="${CMUX_WAIT_WS_INTERVAL}"
    local start=$SECONDS
    local attempt=0
    local output

    while (( SECONDS - start < timeout )); do
        attempt=$((attempt + 1))

        if [ "${VERBOSE:-false}" = "true" ]; then
            echo "[cmux-wait] Polling for ${workspace_id} attempt ${attempt}..." >&2
        fi

        output=$(bash "$cmux_ssh_script" list-workspaces 2>/dev/null) || true
        # Match workspace_id as the first column to prevent substring false positives
        # (e.g., workspace:3 must not match workspace:33). list-workspaces output
        # format is "workspace:N name [selected]", so the ID is always column 1.
        if printf '%s\n' "$output" | awk -v id="$workspace_id" '$1 == id { found = 1; exit } END { exit !found }'; then
            return 0
        fi

        sleep "$interval"
    done

    echo "[cmux-wait] WARN: Timed out waiting for workspace ${workspace_id} after ${timeout}s" >&2
    return 1
}

# Wait for a shell prompt to appear in cmux read-screen output
#
# Args:
#   $1 - workspace_id (e.g., "workspace:3")
#   $2 - cmux_ssh_script_path (path to cmux-ssh.sh)
#
# Returns:
#   0 if prompt pattern matched within timeout
#   1 if timeout expired or invalid arguments
cmux_wait_prompt() {
    local workspace_id="${1:-}"
    local cmux_ssh_script="${2:-}"

    if [ -z "$workspace_id" ]; then
        echo "[cmux-wait] ERROR: cmux_wait_prompt requires a workspace_id argument" >&2
        return 1
    fi

    if [ -z "$cmux_ssh_script" ]; then
        echo "[cmux-wait] ERROR: cmux_wait_prompt requires a cmux_ssh_script_path argument" >&2
        return 1
    fi

    local timeout="${CMUX_WAIT_PROMPT_TIMEOUT}"
    local interval="${CMUX_WAIT_PROMPT_INTERVAL}"
    local pattern="${CMUX_PROMPT_PATTERN}"
    local lines="${CMUX_READ_SCREEN_LINES}"
    local start=$SECONDS
    local attempt=0
    local output

    while (( SECONDS - start < timeout )); do
        attempt=$((attempt + 1))

        if [ "${VERBOSE:-false}" = "true" ]; then
            echo "[cmux-wait] Polling for prompt in ${workspace_id} attempt ${attempt}..." >&2
        fi

        output=$(bash "$cmux_ssh_script" read-screen --workspace "$workspace_id" --lines "$lines" 2>/dev/null) || true
        if echo "$output" | grep -qE "$pattern"; then
            return 0
        fi

        sleep "$interval"
    done

    echo "[cmux-wait] WARN: Timed out waiting for prompt in ${workspace_id} after ${timeout}s" >&2
    return 1
}
