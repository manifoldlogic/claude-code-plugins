#!/usr/bin/env bash
#
# iterm-list-panes.sh - List iTerm2 windows, tabs, and panes (sessions)
#
# DESCRIPTION:
#   Queries iTerm2 for current window, tab, and session (pane) information,
#   with support for table and JSON output formats, window/tab filtering,
#   and dry-run mode. Works from both macOS host (direct osascript) and
#   Linux container (SSH tunneling).
#
# USAGE:
#   iterm-list-panes.sh [OPTIONS]
#     -f, --format FORMAT     Output format: json, table (default: table)
#     -w, --window INDEX      Filter to specific window (1-based)
#     -t, --tab INDEX         Filter to specific tab (1-based)
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
#   - Table format shows window, tab, and pane indices for multi-pane clarity
#   - JSON output is valid JSON (validated with jq)
#   - Window, tab, and pane indexing is 1-based (matching iTerm2 conventions)
#   - Filters can be combined (AND logic): -w 1 -t 2 shows panes in window 1, tab 2
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

DEFAULT_FORMAT="table"

##############################################################################
# Usage Information
##############################################################################

show_help() {
    cat << 'EOF'
iterm-list-panes.sh - List iTerm2 windows, tabs, and panes (sessions)

USAGE:
  iterm-list-panes.sh [OPTIONS]

OPTIONS:
  -f, --format FORMAT     Output format: json, table (default: table)
  -w, --window INDEX      Filter to specific window (1-based)
  -t, --tab INDEX         Filter to specific tab (1-based)
  --dry-run               Show AppleScript without executing
  -h, --help              Show help

EXIT CODES:
  0 - Success (or no windows exist)
  1 - SSH/connection failure (container mode)
  2 - iTerm2 not available
  3 - Invalid arguments

OUTPUT FORMATS:

  Table format (default):
    Window  Tab  Pane  Name
    1       1    1     Devcontainer
    1       1    2     Tests
    1       2    1     claude-code-plugins
    2       1    1     System Monitor

  JSON format:
    {
      "windows": [
        {
          "index": 1,
          "tabs": [
            {
              "index": 1,
              "panes": [
                {"index": 1, "name": "Devcontainer"},
                {"index": 2, "name": "Tests"}
              ]
            },
            {
              "index": 2,
              "panes": [
                {"index": 1, "name": "claude-code-plugins"}
              ]
            }
          ]
        }
      ]
    }

EXAMPLES:
  # List all panes in table format
  iterm-list-panes.sh

  # List all panes in JSON format
  iterm-list-panes.sh -f json

  # List panes from window 2 only
  iterm-list-panes.sh -w 2

  # List panes from tab 1 only (across all windows)
  iterm-list-panes.sh -t 1

  # List panes from window 1, tab 2 only
  iterm-list-panes.sh -w 1 -t 2

  # Preview AppleScript without executing
  iterm-list-panes.sh --dry-run

  # Combine options
  iterm-list-panes.sh --format json --window 1

NOTES:
  - Window, tab, and pane indexing is 1-based (matching iTerm2 conventions)
  - Filters can be combined with AND logic (both must match)
  - In container mode, requires HOST_USER environment variable
  - Empty output indicates no windows/tabs/panes exist
EOF
}

##############################################################################
# Argument Parsing
##############################################################################

parse_arguments() {
    # Initialize with defaults
    ARG_FORMAT="$DEFAULT_FORMAT"
    ARG_WINDOW=""
    ARG_TAB=""
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
            -t|--tab)
                if [[ -z "${2:-}" ]]; then
                    iterm_error "Option $1 requires a tab index"
                    return $EXIT_INVALID_ARGS
                fi
                ARG_TAB="$2"
                # Validate tab index is a positive integer
                if ! [[ "$ARG_TAB" =~ ^[1-9][0-9]*$ ]]; then
                    iterm_error "Invalid tab index: $ARG_TAB (must be a positive integer)"
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
    # AppleScript to query all windows, tabs, and sessions (panes)
    # Output format: window_index<US>tab_index<US>session_index<US>session_name<LF>
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
    set US to ASCII character 31
    set LF to ASCII character 10
    repeat with w from 1 to windowCount
        tell window w
            set tabCount to count of tabs
            repeat with t from 1 to tabCount
                tell tab t
                    set sessionCount to count of sessions
                    repeat with s from 1 to sessionCount
                        try
                            set sessionName to name of session s
                        on error
                            set sessionName to ""
                        end try
                        set output to output & w & US & t & US & s & US & sessionName & LF
                    end repeat
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
    local tab_filter="${3:-}"

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
    printf "%-8s %-5s %-6s %s\n" "Window" "Tab" "Pane" "Name"

    # Parse and print data
    # Data format: window_index<US>tab_index<US>session_index<US>session_name<LF>
    local found_match=false
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Split by unit separator (ASCII 31)
        local window_idx tab_idx pane_idx name
        IFS=$'\x1f' read -r window_idx tab_idx pane_idx name <<< "$line"

        # Apply window filter if specified
        if [[ -n "$window_filter" ]]; then
            if [[ "$window_idx" != "$window_filter" ]]; then
                continue
            fi
        fi

        # Apply tab filter if specified
        if [[ -n "$tab_filter" ]]; then
            if [[ "$tab_idx" != "$tab_filter" ]]; then
                continue
            fi
        fi

        found_match=true

        # Truncate name if too long for display
        local display_name="$name"
        if [[ ${#display_name} -gt 30 ]]; then
            display_name="${display_name:0:27}..."
        fi

        printf "%-8s %-5s %-6s %s\n" "$window_idx" "$tab_idx" "$pane_idx" "$display_name"
    done <<< "$data"

    # Check if filters found any results
    if [[ "$found_match" == "false" ]]; then
        if [[ -n "$window_filter" && -n "$tab_filter" ]]; then
            iterm_error "No panes found in window $window_filter, tab $tab_filter"
        elif [[ -n "$window_filter" ]]; then
            iterm_error "Window $window_filter not found"
        elif [[ -n "$tab_filter" ]]; then
            iterm_error "Tab $tab_filter not found"
        fi
        return $EXIT_INVALID_ARGS
    fi

    return $EXIT_SUCCESS
}

# Format output as JSON
format_json() {
    local data="$1"
    local window_filter="${2:-}"
    local tab_filter="${3:-}"

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
    local json_output='{"windows": ['
    local current_window=""
    local current_tab=""
    local first_window=true
    local first_tab=true
    local first_pane=true
    local found_match=false

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Split by unit separator (ASCII 31)
        local window_idx tab_idx pane_idx name
        IFS=$'\x1f' read -r window_idx tab_idx pane_idx name <<< "$line"

        # Apply window filter if specified
        if [[ -n "$window_filter" ]]; then
            if [[ "$window_idx" != "$window_filter" ]]; then
                continue
            fi
        fi

        # Apply tab filter if specified
        if [[ -n "$tab_filter" ]]; then
            if [[ "$tab_idx" != "$tab_filter" ]]; then
                continue
            fi
        fi

        found_match=true

        # Escape strings for JSON
        local escaped_name
        escaped_name=$(escape_json_string "$name")

        # Check if we're starting a new window
        if [[ "$window_idx" != "$current_window" ]]; then
            # Close previous tab and window if not first
            if [[ -n "$current_tab" ]]; then
                json_output+=']}'
            fi
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
            current_tab=""
            first_tab=true
        fi

        # Check if we're starting a new tab
        if [[ "$tab_idx" != "$current_tab" ]]; then
            # Close previous tab if not first in this window
            if [[ -n "$current_tab" ]]; then
                json_output+=']}'
            fi

            # Start new tab
            if [[ "$first_tab" == "true" ]]; then
                first_tab=false
            else
                json_output+=', '
            fi
            json_output+='{"index": '"$tab_idx"', "panes": ['
            current_tab="$tab_idx"
            first_pane=true
        fi

        # Add pane
        if [[ "$first_pane" == "true" ]]; then
            first_pane=false
        else
            json_output+=', '
        fi
        json_output+='{"index": '"$pane_idx"', "name": "'"$escaped_name"'"}'
    done <<< "$data"

    # Close the last tab and window if we had any
    if [[ -n "$current_tab" ]]; then
        json_output+=']}'
    fi
    if [[ -n "$current_window" ]]; then
        json_output+=']}'
    fi

    # Close the windows array
    json_output+=']}'

    # Check if filters found any results
    if [[ "$found_match" == "false" ]]; then
        if [[ -n "$window_filter" && -n "$tab_filter" ]]; then
            iterm_error "No panes found in window $window_filter, tab $tab_filter"
        elif [[ -n "$window_filter" ]]; then
            iterm_error "Window $window_filter not found"
        elif [[ -n "$tab_filter" ]]; then
            iterm_error "Tab $tab_filter not found"
        fi
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
        iterm_info "Listing iTerm2 panes via SSH (container mode)"
    else
        # Host mode: validate iTerm2 is installed
        if ! validate_iterm; then
            exit $EXIT_ITERM_UNAVAILABLE
        fi
        iterm_info "Listing iTerm2 panes (host mode)"
    fi

    # Execute AppleScript and capture output
    local raw_output
    if ! raw_output=$(run_applescript "$applescript"); then
        iterm_error "Failed to query iTerm2 panes"
        exit $EXIT_CONNECTION_FAIL
    fi

    # Format output based on selected format
    local format_result
    if [[ "$ARG_FORMAT" == "json" ]]; then
        if ! format_json "$raw_output" "$ARG_WINDOW" "$ARG_TAB"; then
            format_result=$?
            exit $format_result
        fi
    else
        if ! format_table "$raw_output" "$ARG_WINDOW" "$ARG_TAB"; then
            format_result=$?
            exit $format_result
        fi
    fi

    exit $EXIT_SUCCESS
}

main "$@"
