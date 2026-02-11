#!/bin/zsh
#
# Validate prompt placeholders before spawning document agents
#
# Ensures TICKET_ID, TICKET_PATH, and PLUGIN_ROOT are valid before
# placeholder substitution occurs. Catches common errors early with
# clear, actionable messages.
#
# Usage:
#   validate-prompt-placeholders.sh TICKET_ID TICKET_PATH PLUGIN_ROOT
#
# Arguments:
#   TICKET_ID   - Ticket identifier (uppercase alphanumeric, hyphens, underscores)
#   TICKET_PATH - Absolute path to the ticket directory (must exist)
#   PLUGIN_ROOT - Absolute path to the sdd plugin root (must exist)
#
# Exit codes:
#   0 - All placeholders valid
#   1 - Validation failure (see stderr for details)

set -euo pipefail

# --- Argument count check ---
if [ "$#" -ne 3 ]; then
    printf 'ERROR: Expected 3 arguments, received %d\n' "$#" >&2
    printf 'Usage: validate-prompt-placeholders.sh TICKET_ID TICKET_PATH PLUGIN_ROOT\n' >&2
    exit 1
fi

TICKET_ID="$1"
TICKET_PATH="$2"
PLUGIN_ROOT="$3"

errors=0

# --- Validate TICKET_ID ---
if [ -z "$TICKET_ID" ]; then
    printf 'ERROR: TICKET_ID is empty\n' >&2
    printf 'Expected: Uppercase alphanumeric with hyphens/underscores (e.g., DOCAGENT, UIT-9819)\n' >&2
    printf 'Received: (empty)\n' >&2
    errors=1
elif ! printf '%s' "$TICKET_ID" | grep -qE '^[A-Z0-9_-]+$'; then
    printf 'ERROR: TICKET_ID is empty or invalid\n' >&2
    printf 'Expected: Uppercase alphanumeric with hyphens/underscores (e.g., DOCAGENT, UIT-9819)\n' >&2
    printf 'Received: %s\n' "$TICKET_ID" >&2
    errors=1
fi

# --- Validate TICKET_PATH ---
if [ -z "$TICKET_PATH" ]; then
    printf 'ERROR: TICKET_PATH is empty\n' >&2
    printf 'Expected: Absolute path to ticket directory (e.g., /app/.sdd/tickets/APIV2_api-redesign)\n' >&2
    printf 'Received: (empty)\n' >&2
    errors=1
else
    case "$TICKET_PATH" in
        /*)
            # Starts with / -- good, now check existence
            if [ ! -d "$TICKET_PATH" ]; then
                printf 'ERROR: TICKET_PATH directory does not exist\n' >&2
                printf 'Expected: An existing directory\n' >&2
                printf 'Received: %s\n' "$TICKET_PATH" >&2
                errors=1
            fi
            ;;
        *)
            printf 'ERROR: TICKET_PATH is not an absolute path\n' >&2
            printf 'Expected: Path starting with / (e.g., /app/.sdd/tickets/APIV2_api-redesign)\n' >&2
            printf 'Received: %s\n' "$TICKET_PATH" >&2
            errors=1
            ;;
    esac
fi

# --- Validate PLUGIN_ROOT ---
if [ -z "$PLUGIN_ROOT" ]; then
    printf 'ERROR: PLUGIN_ROOT is empty\n' >&2
    printf 'Expected: Absolute path to sdd plugin root (e.g., /workspace/repos/claude-code-plugins/plugins/sdd)\n' >&2
    printf 'Received: (empty)\n' >&2
    errors=1
else
    case "$PLUGIN_ROOT" in
        /*)
            # Starts with / -- good, now check existence
            if [ ! -d "$PLUGIN_ROOT" ]; then
                printf 'ERROR: PLUGIN_ROOT directory does not exist\n' >&2
                printf 'Expected: An existing directory\n' >&2
                printf 'Received: %s\n' "$PLUGIN_ROOT" >&2
                errors=1
            fi
            ;;
        *)
            printf 'ERROR: PLUGIN_ROOT is not an absolute path\n' >&2
            printf 'Expected: Path starting with / (e.g., /workspace/repos/claude-code-plugins/plugins/sdd)\n' >&2
            printf 'Received: %s\n' "$PLUGIN_ROOT" >&2
            errors=1
            ;;
    esac
fi

# --- Result ---
if [ "$errors" -ne 0 ]; then
    exit 1
fi

printf 'OK: All placeholders valid (TICKET_ID=%s, TICKET_PATH=%s, PLUGIN_ROOT=%s)\n' \
    "$TICKET_ID" "$TICKET_PATH" "$PLUGIN_ROOT"
exit 0
