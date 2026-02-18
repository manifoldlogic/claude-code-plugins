#!/usr/bin/env bash
#
# iterm-send-text.sh - Send text to a specific iTerm2 pane
#
# DESCRIPTION:
#   Sends text to a specific iTerm2 pane by session number with support for
#   three text modes: default (with newline), --submit (CR for Claude Code),
#   and --no-newline (partial input). Works from both macOS host (direct
#   osascript) and Linux container (SSH tunneling).
#
# NOTE: activate is intentionally omitted. This script targets panes for background
# automation without stealing focus from the user's current application.
#
# USAGE:
#   iterm-send-text.sh -p PANE [--submit | --no-newline] [--dry-run] [-h] <text>
#     -p, --pane PANE         Target pane number (1-based session index)
#     --submit                Send text + CR (ASCII 13) for command submission
#     --no-newline            Send text without trailing newline
#     --dry-run               Show AppleScript without executing
#     -h, --help              Show help
#
# EXIT CODES:
#   0 - Success
#   1 - SSH/connection failure (container mode)
#   2 - iTerm2 not available
#   3 - Invalid arguments (bad pane number, missing text, conflicting flags)
#
# ENVIRONMENT:
#   HOST_USER - macOS host username (required for container mode)
#               Set in devcontainer.json: "remoteEnv": {"HOST_USER": "your-username"}
#
# NOTES:
#   - Pane indexing is 1-based (matching iTerm2 conventions and iterm-list-panes.sh output)
#   - Target: session N of current tab of first window
#   - --submit and --no-newline are mutually exclusive
#   - Empty text is rejected (exit 3) -- silent no-ops provide no value
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

ARG_PANE=""
ARG_TEXT=""
ARG_TEXT_SET=false
ARG_SUBMIT=false
ARG_NO_NEWLINE=false
ARG_DRY_RUN=false

##############################################################################
# Usage Information
##############################################################################

show_help() {
    cat << 'EOF'
iterm-send-text.sh - Send text to a specific iTerm2 pane

USAGE:
  iterm-send-text.sh -p PANE [--submit | --no-newline] [--dry-run] [-h] <text>

OPTIONS:
  -p, --pane PANE         Target pane number (1-based session index)
  --submit                Send text + CR (ASCII 13) for command submission
  --no-newline            Send text without trailing newline
  --dry-run               Show AppleScript without executing
  -h, --help              Show help

ARGUMENTS:
  text                    Text to send to the pane (positional argument)

EXIT CODES:
  0 - Success
  1 - SSH/connection failure (container mode)
  2 - iTerm2 not available
  3 - Invalid arguments (bad pane number, missing text, conflicting flags)

TEXT MODES:
  Default:      Sends text with a trailing newline (standard iTerm2 behavior).
                Equivalent to typing text and pressing Enter in a shell.

  --submit:     Sends text without newline, then sends CR (ASCII 13).
                Use this for Claude Code, which interprets \n (ASCII 10) as a
                literal newline rather than Enter/Return.

  --no-newline: Sends text without any trailing character.
                Use for partial input or fine-grained control.

EXAMPLES:
  # Send a shell command to pane 2 (with newline, executes immediately)
  iterm-send-text.sh -p 2 "ls -la"

  # Submit text to Claude Code in pane 3 (CR instead of newline)
  iterm-send-text.sh -p 3 --submit "explain this code"

  # Send partial text to pane 1 (no trailing character)
  iterm-send-text.sh -p 1 --no-newline "partial input"

  # Preview AppleScript without executing
  iterm-send-text.sh --dry-run -p 2 "hello world"

  # Preview submit mode AppleScript
  iterm-send-text.sh --dry-run -p 2 --submit "claude"

NOTES:
  - Pane numbers are 1-based (use iterm-list-panes.sh to see pane indices)
  - --submit and --no-newline are mutually exclusive
  - In container mode, requires HOST_USER environment variable
  - Text with special characters (quotes, backslashes) is escaped automatically
EOF
}

##############################################################################
# Argument Parsing
##############################################################################

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--pane)
                if [[ -z "${2:-}" ]]; then
                    iterm_error "Option $1 requires a pane number"
                    return $EXIT_INVALID_ARGS
                fi
                ARG_PANE="$2"
                shift 2
                ;;
            --submit)
                ARG_SUBMIT=true
                shift
                ;;
            --no-newline)
                ARG_NO_NEWLINE=true
                shift
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
                # Positional argument = text
                if [[ "$ARG_TEXT_SET" == "false" ]]; then
                    ARG_TEXT="$1"
                    ARG_TEXT_SET=true
                else
                    iterm_error "Only one text argument allowed"
                    iterm_error "Use -h or --help for usage information"
                    return $EXIT_INVALID_ARGS
                fi
                shift
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
    local pane="$1"
    local escaped_text="$2"
    local submit="$3"
    local no_newline="$4"

    local write_command
    if [[ "$submit" == "true" ]]; then
        # --submit mode: write text without newline, then send CR
        write_command="        write text \"$escaped_text\" without newline
        write text (ASCII character 13) without newline"
    elif [[ "$no_newline" == "true" ]]; then
        # --no-newline mode: write text without newline only
        write_command="        write text \"$escaped_text\" without newline"
    else
        # Default mode: write text with newline (standard iTerm2 behavior)
        write_command="        write text \"$escaped_text\""
    fi

    cat << APPLESCRIPT
tell application "iTerm2"
    if (count of windows) is 0 then
        return "NO_WINDOWS"
    end if
    set sessionCount to count of sessions of current tab of first window
    if sessionCount < $pane then
        return "INVALID_PANE"
    end if
    tell session $pane of current tab of first window
$write_command
    end tell
end tell
APPLESCRIPT
}

##############################################################################
# Main Execution
##############################################################################

main() {
    # Parse arguments
    if ! parse_arguments "$@"; then
        exit $EXIT_INVALID_ARGS
    fi

    # Validate pane number is provided
    if [[ -z "$ARG_PANE" ]]; then
        iterm_error "Pane number is required (-p PANE)"
        iterm_error "Use -h or --help for usage information"
        exit $EXIT_INVALID_ARGS
    fi

    # Validate pane number is a positive integer (1+)
    if ! [[ "$ARG_PANE" =~ ^[1-9][0-9]*$ ]]; then
        iterm_error "Invalid pane number: $ARG_PANE (must be a positive integer, 1 or greater)"
        exit $EXIT_INVALID_ARGS
    fi

    # Validate text argument is provided
    if [[ "$ARG_TEXT_SET" == "false" ]]; then
        iterm_error "Text argument is required"
        iterm_error "Use -h or --help for usage information"
        exit $EXIT_INVALID_ARGS
    fi

    # Validate text is not empty string
    if [[ -z "$ARG_TEXT" ]]; then
        iterm_error "Text argument cannot be empty"
        exit $EXIT_INVALID_ARGS
    fi

    # Validate mutual exclusivity of --submit and --no-newline
    if [[ "$ARG_SUBMIT" == "true" && "$ARG_NO_NEWLINE" == "true" ]]; then
        iterm_error "--submit and --no-newline are mutually exclusive"
        iterm_error "Use --submit for CR (Enter), --no-newline for no trailing character"
        exit $EXIT_INVALID_ARGS
    fi

    # Escape text for AppleScript
    local escaped_text
    escaped_text=$(escape_applescript_string "$ARG_TEXT")

    # Build AppleScript
    local applescript
    applescript=$(build_applescript "$ARG_PANE" "$escaped_text" "$ARG_SUBMIT" "$ARG_NO_NEWLINE")

    # Dry-run mode: print script and exit
    if [[ "$ARG_DRY_RUN" == "true" ]]; then
        echo "$applescript"
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
        iterm_info "Sending text to iTerm2 pane $ARG_PANE via SSH (container mode)"
    else
        # Host mode: validate iTerm2 is installed
        if ! validate_iterm; then
            exit $EXIT_ITERM_UNAVAILABLE
        fi
        iterm_info "Sending text to iTerm2 pane $ARG_PANE (host mode)"
    fi

    # Execute AppleScript and capture output (result-capture pattern from iterm-list-panes.sh)
    local result
    if ! result=$(run_applescript "$applescript"); then
        iterm_error "Failed to communicate with iTerm2"
        exit $EXIT_CONNECTION_FAIL
    fi
    if [ "$result" = "NO_WINDOWS" ]; then
        iterm_error "No iTerm2 windows are open"
        exit $EXIT_ITERM_UNAVAILABLE
    fi
    if [ "$result" = "INVALID_PANE" ]; then
        iterm_error "Pane $ARG_PANE does not exist in the current tab"
        exit $EXIT_INVALID_ARGS
    fi

    iterm_ok "Text sent to pane $ARG_PANE"
    exit $EXIT_SUCCESS
}

##############################################################################
# Entry Point
##############################################################################

main "$@"
