#!/usr/bin/env bash
#
# iterm-open-tab.sh - Open iTerm2 tabs from host or container
#
# DESCRIPTION:
#   Opens new iTerm2 tabs with support for profile selection, directory
#   specification, command execution, and tab naming. Works from both
#   macOS host (direct osascript) and Linux container (SSH tunneling).
#
# USAGE:
#   iterm-open-tab.sh [OPTIONS]
#     -d, --directory DIR     Working directory (default: /workspace)
#     -p, --profile PROFILE   iTerm profile (default: Devcontainer)
#     -c, --command CMD       Command to run after connecting
#     -n, --name NAME         Set tab title
#     -w, --window            Create in new window instead of new tab
#     --dry-run               Show what would be executed
#     --wait-for-prompt       Wait for shell prompt before sending command
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
#   - Uses "first window" (frontmost) for multi-window safety
#   - Profile-based approach eliminates PATH resolution issues
#   - Base64 encoding used for SSH transport to avoid escaping issues
#

set -euo pipefail

##############################################################################
# Script Location and Sourcing
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared utilities
# shellcheck source=iterm-utils.sh
if ! source "$SCRIPT_DIR/iterm-utils.sh" 2>/dev/null; then
    echo "[ERROR] Failed to source iterm-utils.sh from $SCRIPT_DIR" >&2
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

DEFAULT_DIRECTORY="/workspace"
DEFAULT_PROFILE="Devcontainer"

##############################################################################
# Usage Information
##############################################################################

show_help() {
    cat << 'EOF'
iterm-open-tab.sh - Open iTerm2 tabs from host or container

USAGE:
  iterm-open-tab.sh [OPTIONS]

OPTIONS:
  -d, --directory DIR     Working directory (default: /workspace)
  -p, --profile PROFILE   iTerm profile (default: Devcontainer)
  -c, --command CMD       Command to run after connecting
  -n, --name NAME         Set tab title
  -w, --window            Create in new window instead of new tab
  --dry-run               Show what would be executed
  --wait-for-prompt       Wait for shell prompt before sending shell command.
                          Inserts an AppleScript polling loop (3s initial delay,
                          up to 12s polling, 15s total). Use with Devcontainer
                          profile when container startup takes a few seconds.
                          Has no effect if no shell command is specified.
  -h, --help              Show help

EXIT CODES:
  0 - Success
  1 - SSH/connection failure (container mode)
  2 - iTerm2 not available
  3 - Invalid arguments

EXAMPLES:
  # Open tab in default directory with Devcontainer profile
  iterm-open-tab.sh

  # Open tab in specific directory
  iterm-open-tab.sh -d /workspace/repos/my-project

  # Open tab with custom profile and title
  iterm-open-tab.sh -p "Custom Profile" -n "My Tab"

  # Open tab and run a command
  iterm-open-tab.sh -c "git status"

  # Preview AppleScript without executing
  iterm-open-tab.sh --dry-run -d /workspace -n "Test Tab"

  # Open in new window instead of new tab
  iterm-open-tab.sh -w -d /workspace

NOTES:
  - Uses "first window" (frontmost) for consistent multi-window behavior
  - In container mode, requires HOST_USER environment variable
  - Profile must exist in iTerm2 (fallback to Default if not found)
  - Paths with spaces are handled correctly
EOF
}

##############################################################################
# Argument Parsing
##############################################################################

parse_arguments() {
    # Initialize with defaults
    ARG_DIRECTORY="$DEFAULT_DIRECTORY"
    ARG_PROFILE="$DEFAULT_PROFILE"
    ARG_COMMAND=""
    ARG_NAME=""
    ARG_NEW_WINDOW=false
    ARG_DRY_RUN=false
    ARG_WAIT_FOR_PROMPT=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--directory)
                if [[ -z "${2:-}" ]]; then
                    iterm_error "Option $1 requires a directory argument"
                    return $EXIT_INVALID_ARGS
                fi
                ARG_DIRECTORY="$2"
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
            -w|--window)
                ARG_NEW_WINDOW=true
                shift
                ;;
            --dry-run)
                ARG_DRY_RUN=true
                shift
                ;;
            --wait-for-prompt)
                ARG_WAIT_FOR_PROMPT=true
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
    local directory="$1"
    local profile="$2"
    local command="${3:-}"
    local name="${4:-}"
    local new_window="${5:-false}"
    local wait_for_prompt="${6:-false}"

    # Escape values for AppleScript
    local escaped_profile escaped_directory escaped_name escaped_command
    escaped_profile=$(escape_applescript_string "$profile")
    escaped_directory=$(escape_applescript_string "$directory")
    escaped_name=$(escape_applescript_string "$name")
    escaped_command=$(escape_applescript_string "$command")

    # Build the command to execute after tab opens
    # Note: We need \\\" to produce \" in the final AppleScript (escaped quote)
    # This allows paths with spaces to work: cd "/path with spaces"
    local shell_command=""
    if [[ -n "$directory" ]]; then
        shell_command="cd \\\"$escaped_directory\\\""
    fi
    if [[ -n "$command" ]]; then
        if [[ -n "$shell_command" ]]; then
            shell_command="$shell_command && $escaped_command"
        else
            shell_command="$escaped_command"
        fi
    fi
    # Add clear at the end if we have any commands
    if [[ -n "$shell_command" ]]; then
        shell_command="$shell_command && clear"
    fi

    # Build the AppleScript
    local script=""

    if [[ "$new_window" == "true" ]]; then
        # Create new window
        script="tell application \"iTerm2\"
    activate
    create window with profile \"$escaped_profile\"
    tell current session of current tab of first window"

        # Add name setting if provided
        if [[ -n "$name" ]]; then
            script="$script
        set name to \"$escaped_name\""
        fi

        # Add polling loop if wait_for_prompt is enabled and command exists
        if [[ "$wait_for_prompt" == "true" && -n "$shell_command" ]]; then
            script="$script
        delay 3
        set maxWait to 12
        set waited to 0
        repeat while waited < maxWait
            if is at shell prompt then
                exit repeat
            end if
            delay 1
            set waited to waited + 1
        end repeat"
        fi

        # Add command execution if provided
        if [[ -n "$shell_command" ]]; then
            script="$script
        write text \"$shell_command\""
        fi

        script="$script
    end tell
end tell"
    else
        # Create new tab in frontmost window (or new window if none exist)
        script="tell application \"iTerm2\"
    activate
    if (count of windows) is 0 then
        create window with profile \"$escaped_profile\"
        tell current session of current tab of first window"

        # Add name setting if provided
        if [[ -n "$name" ]]; then
            script="$script
            set name to \"$escaped_name\""
        fi

        # Add polling loop if wait_for_prompt is enabled and command exists
        if [[ "$wait_for_prompt" == "true" && -n "$shell_command" ]]; then
            script="$script
            delay 3
            set maxWait to 12
            set waited to 0
            repeat while waited < maxWait
                if is at shell prompt then
                    exit repeat
                end if
                delay 1
                set waited to waited + 1
            end repeat"
        fi

        # Add command execution if provided
        if [[ -n "$shell_command" ]]; then
            script="$script
            write text \"$shell_command\""
        fi

        script="$script
        end tell
    else
        tell first window
            create tab with profile \"$escaped_profile\"
            tell current session of current tab"

        # Add name setting if provided
        if [[ -n "$name" ]]; then
            script="$script
                set name to \"$escaped_name\""
        fi

        # Add polling loop if wait_for_prompt is enabled and command exists
        if [[ "$wait_for_prompt" == "true" && -n "$shell_command" ]]; then
            script="$script
                delay 3
                set maxWait to 12
                set waited to 0
                repeat while waited < maxWait
                    if is at shell prompt then
                        exit repeat
                    end if
                    delay 1
                    set waited to waited + 1
                end repeat"
        fi

        # Add command execution if provided
        if [[ -n "$shell_command" ]]; then
            script="$script
                write text \"$shell_command\""
        fi

        script="$script
            end tell
        end tell
    end if
end tell"
    fi

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
        "$ARG_DIRECTORY" \
        "$ARG_PROFILE" \
        "$ARG_COMMAND" \
        "$ARG_NAME" \
        "$ARG_NEW_WINDOW" \
        "$ARG_WAIT_FOR_PROMPT")

    # Dry-run mode: print script and exit
    if [[ "$ARG_DRY_RUN" == "true" ]]; then
        iterm_info "Dry-run mode: Showing AppleScript that would be executed"
        if [[ "$ARG_WAIT_FOR_PROMPT" == "true" ]]; then
            iterm_info "Wait-for-prompt: enabled (polling loop will be inserted before write text)"
        fi
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
        iterm_info "Opening iTerm2 tab via SSH (container mode)"
    else
        # Host mode: validate iTerm2 is installed
        if ! validate_iterm; then
            exit $EXIT_ITERM_UNAVAILABLE
        fi
        iterm_info "Opening iTerm2 tab (host mode)"
    fi

    # Execute AppleScript
    if ! run_applescript "$applescript"; then
        iterm_error "Failed to open iTerm2 tab"
        exit $EXIT_CONNECTION_FAIL
    fi

    iterm_ok "iTerm2 tab opened successfully"
    exit $EXIT_SUCCESS
}

main "$@"
