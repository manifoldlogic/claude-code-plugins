#!/usr/bin/env bash
#
# iterm-split-pane.sh - Split iTerm2 panes from host or container
#
# DESCRIPTION:
#   Splits the current iTerm2 session into a new pane with support for
#   direction selection, profile specification, command execution, and
#   pane naming. Works from both macOS host (direct osascript) and
#   Linux container (SSH tunneling).
#
# USAGE:
#   iterm-split-pane.sh [OPTIONS]
#     -d, --direction DIR     Split direction: vertical or horizontal (default: vertical)
#     -p, --profile PROFILE   iTerm profile (default: Devcontainer)
#     -c, --command CMD       Command to run in the new pane
#     -n, --name NAME         Set pane title
#     --dry-run               Show what would be executed
#     -h, --help              Show help
#
# EXIT CODES:
#   0 - Success
#   1 - SSH/connection failure (container mode)
#   2 - iTerm2 not available
#   3 - Invalid arguments
#
# ENVIRONMENT:
#   HOST_USER - macOS host username (required for container mode)
#               Set in devcontainer.json: "remoteEnv": {"HOST_USER": "your-username"}
#
# NOTES:
#   - Requires an existing iTerm2 window (will not create one)
#   - Uses "first window" (frontmost) for multi-window safety
#   - Profile-based approach eliminates PATH resolution issues
#   - The -d flag sets split direction (not directory; use -c for navigation)
#   - Base64 encoding used for SSH transport to avoid escaping issues
#

set -euo pipefail

##############################################################################
# Script Location and Sourcing
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$(cd "$SCRIPT_DIR/../../tab-management/scripts" && pwd)"

# Source shared utilities from sibling skill directory
# shellcheck source=../../tab-management/scripts/iterm-utils.sh
if ! source "$UTILS_DIR/iterm-utils.sh" 2>/dev/null; then
    echo "[ERROR] Failed to source iterm-utils.sh from $UTILS_DIR" >&2
    exit 3
fi

##############################################################################
# Trap Handler Setup
##############################################################################

# Register cleanup trap BEFORE any temp file operations
# This ensures cleanup runs even on early exits
trap _cleanup_temp_script EXIT INT TERM

##############################################################################
# Default Values
##############################################################################

DEFAULT_DIRECTION="vertical"
DEFAULT_PROFILE="Devcontainer"

##############################################################################
# Usage Information
##############################################################################

show_help() {
    cat << 'EOF'
iterm-split-pane.sh - Split iTerm2 panes from host or container

USAGE:
  iterm-split-pane.sh [OPTIONS]

OPTIONS:
  -d, --direction DIR     Split direction: vertical or horizontal (default: vertical)
  -p, --profile PROFILE   iTerm profile (default: Devcontainer)
  -c, --command CMD       Command to run in the new pane
  -n, --name NAME         Set pane title
  --dry-run               Show what would be executed
  -h, --help              Show help

EXIT CODES:
  0 - Success
  1 - SSH/connection failure (container mode)
  2 - iTerm2 not available
  3 - Invalid arguments

EXAMPLES:
  # Split vertically with default Devcontainer profile
  iterm-split-pane.sh

  # Split horizontally
  iterm-split-pane.sh -d horizontal

  # Split with custom profile and title
  iterm-split-pane.sh -p "Custom Profile" -n "My Pane"

  # Split and run a command in the new pane
  iterm-split-pane.sh -c "git status"

  # Navigate to a directory in the new pane
  iterm-split-pane.sh -c "cd /workspace/repos/my-project"

  # Preview AppleScript without executing
  iterm-split-pane.sh --dry-run -d horizontal -n "Test Pane"

NOTES:
  - The -d flag sets split direction (not directory; use -c for navigation commands)
  - Requires an existing iTerm2 window (returns NO_WINDOWS if none exist)
  - In container mode, requires HOST_USER environment variable
  - Profile must exist in iTerm2 (fallback to Default if not found)
  - After splitting, the new pane automatically receives focus
EOF
}

##############################################################################
# Argument Parsing
##############################################################################

parse_arguments() {
    # Initialize with defaults
    ARG_DIRECTION="$DEFAULT_DIRECTION"
    ARG_PROFILE="$DEFAULT_PROFILE"
    ARG_COMMAND=""
    ARG_NAME=""
    ARG_DRY_RUN=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--direction)
                if [[ -z "${2:-}" ]]; then
                    iterm_error "Option $1 requires a direction argument"
                    return $EXIT_INVALID_ARGS
                fi
                ARG_DIRECTION="$2"
                shift 2
                ;;
            -p|--profile)
                if [[ -z "${2:-}" ]]; then
                    iterm_error "Option $1 requires a profile name"
                    return $EXIT_INVALID_ARGS
                fi
                ARG_PROFILE="$2"
                shift 2
                ;;
            -c|--command)
                if [[ -z "${2:-}" ]]; then
                    iterm_error "Option $1 requires a command string"
                    return $EXIT_INVALID_ARGS
                fi
                ARG_COMMAND="$2"
                shift 2
                ;;
            -n|--name)
                if [[ -z "${2:-}" ]]; then
                    iterm_error "Option $1 requires a name"
                    return $EXIT_INVALID_ARGS
                fi
                ARG_NAME="$2"
                shift 2
                ;;
            --dry-run)
                ARG_DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit $EXIT_SUCCESS
                ;;
            -*)
                iterm_error "Unknown option: $1"
                iterm_error "Use -h or --help for usage information"
                return $EXIT_INVALID_ARGS
                ;;
            *)
                iterm_error "Unexpected argument: $1"
                iterm_error "Use -h or --help for usage information"
                return $EXIT_INVALID_ARGS
                ;;
        esac
    done

    # Validate direction value
    if [[ "$ARG_DIRECTION" != "horizontal" && "$ARG_DIRECTION" != "vertical" ]]; then
        iterm_error "Invalid direction: $ARG_DIRECTION (must be horizontal or vertical)"
        return $EXIT_INVALID_ARGS
    fi

    return $EXIT_SUCCESS
}

##############################################################################
# AppleScript Escaping
##############################################################################

# Escape a string for use inside AppleScript double quotes
# Handles: backslashes, double quotes
escape_applescript_string() {
    local input="$1"
    # Escape backslashes first, then double quotes
    local escaped
    escaped="${input//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    printf '%s' "$escaped"
}

##############################################################################
# AppleScript Generation
##############################################################################

build_applescript() {
    local direction="$1"
    local profile="$2"
    local command="${3:-}"
    local name="${4:-}"

    # Escape values for AppleScript
    local escaped_profile escaped_name escaped_command
    escaped_profile=$(escape_applescript_string "$profile")
    escaped_name=$(escape_applescript_string "$name")
    escaped_command=$(escape_applescript_string "$command")

    # Build the AppleScript
    local script=""

    script="tell application \"iTerm2\"
    activate
    if (count of windows) is 0 then
        return \"NO_WINDOWS\"
    end if
    tell current session of current tab of first window
        split ${direction}ly with profile \"$escaped_profile\"
    end tell
    tell current session of current tab of first window"

    # Add name setting if provided
    if [[ -n "$name" ]]; then
        script="$script
        set name to \"$escaped_name\""
    fi

    # Add command execution if provided
    if [[ -n "$command" ]]; then
        script="$script
        write text \"$escaped_command\""
    fi

    script="$script
    end tell
end tell"

    printf '%s' "$script"
}

##############################################################################
# Main Execution
##############################################################################

main() {
    # Parse arguments
    if ! parse_arguments "$@"; then
        exit $EXIT_INVALID_ARGS
    fi

    # Build AppleScript
    local applescript
    applescript=$(build_applescript \
        "$ARG_DIRECTION" \
        "$ARG_PROFILE" \
        "$ARG_COMMAND" \
        "$ARG_NAME")

    # Dry-run mode: print script and exit
    if [[ "$ARG_DRY_RUN" == "true" ]]; then
        iterm_info "Dry-run mode: Showing AppleScript that would be executed"
        echo ""
        echo "$applescript"
        echo ""
        exit $EXIT_SUCCESS
    fi

    # Validate prerequisites based on context
    if is_container; then
        # Container mode: validate SSH connectivity and HOST_USER
        if ! validate_ssh_host; then
            exit $EXIT_CONNECTION_FAIL
        fi
        if ! validate_iterm; then
            exit $EXIT_ITERM_UNAVAILABLE
        fi
        iterm_info "Splitting iTerm2 pane via SSH (container mode)"
    else
        # Host mode: validate iTerm2 is installed
        if ! validate_iterm; then
            exit $EXIT_ITERM_UNAVAILABLE
        fi
        iterm_info "Splitting iTerm2 pane (host mode)"
    fi

    # Execute AppleScript
    if ! run_applescript "$applescript"; then
        iterm_error "Failed to split iTerm2 pane"
        exit $EXIT_CONNECTION_FAIL
    fi

    iterm_ok "Pane split successfully"
    exit $EXIT_SUCCESS
}

main "$@"
