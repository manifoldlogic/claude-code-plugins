#!/usr/bin/env bash
#
# iterm-list-tabs.sh - List iTerm2 windows and tabs
#
# DESCRIPTION:
#   Queries iTerm2 for current window and tab information, with support for
#   table and JSON output formats and window filtering. Works from both
#   macOS host (direct osascript) and Linux container (SSH tunneling).
#
# USAGE:
#   iterm-list-tabs.sh [OPTIONS]
#     -f, --format FORMAT     Output format: json, table (default: table)
#     -w, --window INDEX      Filter to specific window (1-based)
#     --dry-run               Show AppleScript without executing
#     -h, --help              Show help
#
# EXIT CODES:
#   0 - Success (or no windows exist)
#   1 - SSH/connection failure (container mode)
#   2 - iTerm2 not available
#   3 - Invalid arguments
#
# ENVIRONMENT:
#   HOST_USER - macOS host username (required for container mode)
#               Set in devcontainer.json: "remoteEnv": {"HOST_USER": "your-username"}
#
# NOTES:
#   - Table format shows window index in first column for multi-window clarity
#   - JSON output is valid JSON (validated with jq)
#   - Window indexing is 1-based (matching iTerm2 conventions)
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

DEFAULT_FORMAT="table"

##############################################################################
# Usage Information
##############################################################################

show_help() {
    cat << 'EOF'
iterm-list-tabs.sh - List iTerm2 windows and tabs

USAGE:
  iterm-list-tabs.sh [OPTIONS]

OPTIONS:
  -f, --format FORMAT     Output format: json, table (default: table)
  -w, --window INDEX      Filter to specific window (1-based)
  --dry-run               Show AppleScript without executing
  -h, --help              Show help

EXIT CODES:
  0 - Success (or no windows exist)
  1 - SSH/connection failure (container mode)
  2 - iTerm2 not available
  3 - Invalid arguments

OUTPUT FORMATS:

  Table format (default):
    Window  Tab  Title                    Session
    1       1    Devcontainer             Devcontainer
    1       2    claude-code-plugins      claude-code-plugins
    2       1    System Monitor           System Monitor

  Note: Title and Session show the same value (session name) as iTerm2's
  AppleScript API exposes the session name for both. The session name is
  what appears as the tab title in iTerm2.

  JSON format:
    {
      "windows": [
        {
          "index": 1,
          "tabs": [
            {"index": 1, "title": "Devcontainer", "session": "Devcontainer"},
            {"index": 2, "title": "claude-code-plugins", "session": "claude-code-plugins"}
          ]
        }
      ]
    }

EXAMPLES:
  # List all tabs in table format
  iterm-list-tabs.sh

  # List all tabs in JSON format
  iterm-list-tabs.sh -f json

  # List tabs from window 2 only
  iterm-list-tabs.sh -w 2

  # Preview AppleScript without executing
  iterm-list-tabs.sh --dry-run

  # Combine options
  iterm-list-tabs.sh --format json --window 1

NOTES:
  - Window indexing is 1-based (matching iTerm2 conventions)
  - In container mode, requires HOST_USER environment variable
  - Empty output indicates no windows/tabs exist
EOF
}

##############################################################################
# Argument Parsing
##############################################################################

parse_arguments() {
    # Initialize with defaults
    ARG_FORMAT="$DEFAULT_FORMAT"
    ARG_WINDOW=""
    ARG_DRY_RUN=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--format)
                if [[ -z "${2:-}" ]]; then
                    iterm_error "Option $1 requires a format argument (json or table)"
                    return $EXIT_INVALID_ARGS
                fi
                ARG_FORMAT="$2"
                # Validate format
                if [[ "$ARG_FORMAT" != "json" && "$ARG_FORMAT" != "table" ]]; then
                    iterm_error "Invalid format: $ARG_FORMAT (must be 'json' or 'table')"
                    return $EXIT_INVALID_ARGS
                fi
                shift 2
                ;;
            -w|--window)
                if [[ -z "${2:-}" ]]; then
                    iterm_error "Option $1 requires a window index"
                    return $EXIT_INVALID_ARGS
                fi
                ARG_WINDOW="$2"
                # Validate window index is a positive integer
                if ! [[ "$ARG_WINDOW" =~ ^[1-9][0-9]*$ ]]; then
                    iterm_error "Invalid window index: $ARG_WINDOW (must be a positive integer)"
                    return $EXIT_INVALID_ARGS
                fi
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

    return $EXIT_SUCCESS
}

##############################################################################
# AppleScript Generation
##############################################################################

build_applescript() {
    # AppleScript to query all windows and tabs
    # Output format: window_index<tab>tab_index<tab>title<tab>session_name<newline>
    # Uses ASCII unit separator (31) as delimiter for safety with special characters
    cat << 'APPLESCRIPT'
tell application "iTerm2"
    if not running then
        return "ITERM_NOT_RUNNING"
    end if
    set windowCount to count of windows
    if windowCount is 0 then
        return "NO_WINDOWS"
    end if
    set output to ""
    repeat with w from 1 to windowCount
        tell window w
            set tabCount to count of tabs
            repeat with t from 1 to tabCount
                tell tab t
                    try
                        set sessionName to name of current session
                    on error
                        set sessionName to ""
                    end try
                    -- Use ASCII 31 (unit separator) as delimiter for safety
                    set output to output & w & (ASCII character 31) & t & (ASCII character 31) & sessionName & (ASCII character 31) & sessionName & (ASCII character 10)
                end tell
            end repeat
        end tell
    end repeat
    return output
end tell
APPLESCRIPT
}

##############################################################################
# Output Formatting
##############################################################################

# Escape a string for JSON output
# Handles: backslashes, double quotes, newlines, tabs, carriage returns
escape_json_string() {
    local input="$1"
    local escaped
    # Escape backslashes first
    escaped="${input//\\/\\\\}"
    # Escape double quotes
    escaped="${escaped//\"/\\\"}"
    # Escape newlines
    escaped="${escaped//$'\n'/\\n}"
    # Escape tabs
    escaped="${escaped//$'\t'/\\t}"
    # Escape carriage returns
    escaped="${escaped//$'\r'/\\r}"
    printf '%s' "$escaped"
}

# Format output as a table
format_table() {
    local data="$1"
    local window_filter="${2:-}"

    # Check for special responses
    if [[ "$data" == "ITERM_NOT_RUNNING" ]]; then
        iterm_error "iTerm2 is not running"
        return $EXIT_ITERM_UNAVAILABLE
    fi

    if [[ "$data" == "NO_WINDOWS" || -z "$data" ]]; then
        echo "No windows found"
        return $EXIT_SUCCESS
    fi

    # Print header
    printf "%-8s %-5s %-30s %s\n" "Window" "Tab" "Title" "Session"

    # Parse and print data
    # Data format: window_index<US>tab_index<US>title<US>session_name<LF>
    local found_window=false
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Split by unit separator (ASCII 31)
        local window_idx tab_idx title session
        IFS=$'\x1f' read -r window_idx tab_idx title session <<< "$line"

        # Apply window filter if specified
        if [[ -n "$window_filter" ]]; then
            if [[ "$window_idx" == "$window_filter" ]]; then
                found_window=true
            else
                continue
            fi
        fi

        # Truncate title if too long for display
        local display_title="$title"
        if [[ ${#display_title} -gt 30 ]]; then
            display_title="${display_title:0:27}..."
        fi

        printf "%-8s %-5s %-30s %s\n" "$window_idx" "$tab_idx" "$display_title" "$session"
    done <<< "$data"

    # Check if window filter found any results
    if [[ -n "$window_filter" && "$found_window" == "false" ]]; then
        iterm_error "Window $window_filter not found"
        return $EXIT_INVALID_ARGS
    fi

    return $EXIT_SUCCESS
}

# Format output as JSON
format_json() {
    local data="$1"
    local window_filter="${2:-}"

    # Check for special responses
    if [[ "$data" == "ITERM_NOT_RUNNING" ]]; then
        iterm_error "iTerm2 is not running"
        return $EXIT_ITERM_UNAVAILABLE
    fi

    if [[ "$data" == "NO_WINDOWS" || -z "$data" ]]; then
        echo '{"windows": []}'
        return $EXIT_SUCCESS
    fi

    # Build JSON structure
    # Use associative arrays if available, otherwise use simple parsing
    local json_output='{"windows": ['
    local current_window=""
    local first_window=true
    local first_tab=true
    local found_window=false

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Split by unit separator (ASCII 31)
        local window_idx tab_idx title session
        IFS=$'\x1f' read -r window_idx tab_idx title session <<< "$line"

        # Apply window filter if specified
        if [[ -n "$window_filter" ]]; then
            if [[ "$window_idx" == "$window_filter" ]]; then
                found_window=true
            else
                continue
            fi
        fi

        # Escape strings for JSON
        local escaped_title escaped_session
        escaped_title=$(escape_json_string "$title")
        escaped_session=$(escape_json_string "$session")

        # Check if we're starting a new window
        if [[ "$window_idx" != "$current_window" ]]; then
            # Close previous window if not first
            if [[ -n "$current_window" ]]; then
                json_output+=']}'
            fi

            # Start new window
            if [[ "$first_window" == "true" ]]; then
                first_window=false
            else
                json_output+=', '
            fi
            json_output+='{"index": '"$window_idx"', "tabs": ['
            current_window="$window_idx"
            first_tab=true
        fi

        # Add tab
        if [[ "$first_tab" == "true" ]]; then
            first_tab=false
        else
            json_output+=', '
        fi
        json_output+='{"index": '"$tab_idx"', "title": "'"$escaped_title"'", "session": "'"$escaped_session"'"}'
    done <<< "$data"

    # Close the last window if we had any
    if [[ -n "$current_window" ]]; then
        json_output+=']}'
    fi

    # Close the windows array
    json_output+=']}'

    # Check if window filter found any results
    if [[ -n "$window_filter" && "$found_window" == "false" ]]; then
        iterm_error "Window $window_filter not found"
        return $EXIT_INVALID_ARGS
    fi

    echo "$json_output"
    return $EXIT_SUCCESS
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
    applescript=$(build_applescript)

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
        iterm_info "Listing iTerm2 tabs via SSH (container mode)"
    else
        # Host mode: validate iTerm2 is installed
        if ! validate_iterm; then
            exit $EXIT_ITERM_UNAVAILABLE
        fi
        iterm_info "Listing iTerm2 tabs (host mode)"
    fi

    # Execute AppleScript and capture output
    local raw_output
    if ! raw_output=$(run_applescript "$applescript"); then
        iterm_error "Failed to query iTerm2 tabs"
        exit $EXIT_CONNECTION_FAIL
    fi

    # Format output based on selected format
    local format_result
    if [[ "$ARG_FORMAT" == "json" ]]; then
        if ! format_json "$raw_output" "$ARG_WINDOW"; then
            format_result=$?
            exit $format_result
        fi
    else
        if ! format_table "$raw_output" "$ARG_WINDOW"; then
            format_result=$?
            exit $format_result
        fi
    fi

    exit $EXIT_SUCCESS
}

main "$@"
