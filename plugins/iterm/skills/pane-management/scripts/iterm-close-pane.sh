#!/usr/bin/env bash
#
# iterm-close-pane.sh - Close iTerm2 panes by pattern matching
#
# DESCRIPTION:
#   Closes iTerm2 panes (sessions) by matching a pattern against session names.
#   Supports dry-run preview, confirmation prompts for multiple matches, window
#   and tab filtering, and force mode. Works from both macOS host (direct
#   osascript) and Linux container (SSH tunneling).
#
# USAGE:
#   iterm-close-pane.sh [OPTIONS] <pattern>
#     -w, --window INDEX      Limit to specific window (1-based)
#     -t, --tab INDEX         Limit to specific tab (1-based)
#     --force                 Skip confirmation for multiple matches
#     --dry-run               Show what would be closed
#     -h, --help              Show help
#
# ARGUMENTS:
#   pattern                   Pattern to match session names (substring match)
#
# EXIT CODES:
#   0 - Success
#   1 - SSH/connection failure (container mode)
#   2 - iTerm2 not available
#   3 - Invalid arguments
#   4 - Pattern matches no panes
#
# ENVIRONMENT:
#   HOST_USER - macOS host username (required for container mode)
#               Set in devcontainer.json: "remoteEnv": {"HOST_USER": "your-username"}
#
# NOTES:
#   - Pattern matching is substring match (case-sensitive), not regex
#   - Panes are closed in reverse order to prevent index shifting bugs
#   - Use quotes for patterns containing spaces
#   - Confirmation required for multiple matches unless --force is used
#   - Closing the last pane in a tab will close the tab.
#     Closing the last tab in a window will close the window.
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
# Usage Information
##############################################################################

show_help() {
    cat << 'EOF'
iterm-close-pane.sh - Close iTerm2 panes by pattern matching

USAGE:
  iterm-close-pane.sh [OPTIONS] <pattern>

OPTIONS:
  -w, --window INDEX      Limit to specific window (1-based)
  -t, --tab INDEX         Limit to specific tab (1-based)
  --force                 Skip confirmation for multiple matches
  --dry-run               Show what would be closed
  -h, --help              Show help

ARGUMENTS:
  pattern                 Pattern to match session names (substring match)

EXIT CODES:
  0 - Success
  1 - SSH/connection failure (container mode)
  2 - iTerm2 not available
  3 - Invalid arguments
  4 - Pattern matches no panes

EXAMPLES:
  # Close panes with "agent:" in session name
  iterm-close-pane.sh "agent:"

  # Preview which panes would be closed
  iterm-close-pane.sh --dry-run "feature-branch"

  # Close panes in window 1 only
  iterm-close-pane.sh -w 1 "test"

  # Close panes in tab 2 only
  iterm-close-pane.sh -t 2 "worker"

  # Close without confirmation prompt
  iterm-close-pane.sh --force "cleanup"

  # Combine options
  iterm-close-pane.sh --force -w 2 -t 1 "worktree: feature"

NOTES:
  - Pattern matching is substring match (case-sensitive), NOT regex
  - Use quotes for patterns containing spaces
  - Panes are closed in reverse order to prevent index shifting bugs
  - Confirmation is required for multiple matches unless --force is used
  - In container mode, requires HOST_USER environment variable
  - Closing the last pane in a tab will close the tab.
    Closing the last tab in a window will close the window.
EOF
}

##############################################################################
# Argument Parsing
##############################################################################

parse_arguments() {
    # Initialize with defaults
    ARG_WINDOW=""
    ARG_TAB=""
    ARG_FORCE=false
    ARG_DRY_RUN=false
    ARG_PATTERN=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
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
            --force)
                ARG_FORCE=true
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
                # Positional argument = pattern
                if [[ -z "$ARG_PATTERN" ]]; then
                    ARG_PATTERN="$1"
                else
                    iterm_error "Only one pattern argument allowed"
                    iterm_error "Use -h or --help for usage information"
                    return $EXIT_INVALID_ARGS
                fi
                shift
                ;;
        esac
    done

    # Validate pattern is provided
    if [[ -z "$ARG_PATTERN" ]]; then
        iterm_error "Pattern is required"
        iterm_error "Use -h or --help for usage information"
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
# AppleScript Generation - List Panes
##############################################################################

build_list_panes_applescript() {
    # AppleScript to query all windows, tabs, and sessions
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
                        set output to output & w & (ASCII character 31) & t & (ASCII character 31) & s & (ASCII character 31) & sessionName & (ASCII character 10)
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
# AppleScript Generation - Close Panes
##############################################################################

build_close_panes_applescript() {
    local pattern="$1"
    local window_filter="${2:-}"
    local tab_filter="${3:-}"

    # Escape pattern for AppleScript
    local escaped_pattern
    escaped_pattern=$(escape_applescript_string "$pattern")

    # Build the close AppleScript
    # IMPORTANT: Iterate in reverse order to prevent index shifting bugs
    local script=""

    if [[ -n "$window_filter" && -n "$tab_filter" ]]; then
        # Close panes in specific window and specific tab
        script="tell application \"iTerm2\"
    if not running then
        return \"ITERM_NOT_RUNNING\"
    end if
    set windowCount to count of windows
    if windowCount < $window_filter then
        return \"WINDOW_NOT_FOUND\"
    end if
    set closedCount to 0
    tell window $window_filter
        if (count of tabs) < $tab_filter then
            return \"TAB_NOT_FOUND\"
        end if
        tell tab $tab_filter
            repeat with s from (count of sessions) to 1 by -1
                try
                    if name of session s contains \"$escaped_pattern\" then
                        tell session s to close
                        set closedCount to closedCount + 1
                    end if
                on error
                    -- Skip sessions that can't be accessed
                end try
            end repeat
        end tell
    end tell
    return closedCount
end tell"

    elif [[ -n "$window_filter" ]]; then
        # Close panes in specific window only, all tabs
        script="tell application \"iTerm2\"
    if not running then
        return \"ITERM_NOT_RUNNING\"
    end if
    set windowCount to count of windows
    if windowCount < $window_filter then
        return \"WINDOW_NOT_FOUND\"
    end if
    set closedCount to 0
    tell window $window_filter
        repeat with t from (count of tabs) to 1 by -1
            tell tab t
                repeat with s from (count of sessions) to 1 by -1
                    try
                        if name of session s contains \"$escaped_pattern\" then
                            tell session s to close
                            set closedCount to closedCount + 1
                        end if
                    on error
                        -- Skip sessions that can't be accessed
                    end try
                end repeat
            end tell
        end repeat
    end tell
    return closedCount
end tell"

    elif [[ -n "$tab_filter" ]]; then
        # Close panes in specific tab across all windows
        script="tell application \"iTerm2\"
    if not running then
        return \"ITERM_NOT_RUNNING\"
    end if
    set closedCount to 0
    repeat with w from (count of windows) to 1 by -1
        tell window w
            if (count of tabs) >= $tab_filter then
                tell tab $tab_filter
                    repeat with s from (count of sessions) to 1 by -1
                        try
                            if name of session s contains \"$escaped_pattern\" then
                                tell session s to close
                                set closedCount to closedCount + 1
                            end if
                        on error
                            -- Skip sessions that can't be accessed
                        end try
                    end repeat
                end tell
            end if
        end tell
    end repeat
    return closedCount
end tell"

    else
        # Close panes in all windows and all tabs
        script="tell application \"iTerm2\"
    if not running then
        return \"ITERM_NOT_RUNNING\"
    end if
    set closedCount to 0
    repeat with w from (count of windows) to 1 by -1
        tell window w
            repeat with t from (count of tabs) to 1 by -1
                tell tab t
                    repeat with s from (count of sessions) to 1 by -1
                        try
                            if name of session s contains \"$escaped_pattern\" then
                                tell session s to close
                                set closedCount to closedCount + 1
                            end if
                        on error
                            -- Skip sessions that can't be accessed
                        end try
                    end repeat
                end tell
            end repeat
        end tell
    end repeat
    return closedCount
end tell"
    fi

    printf '%s' "$script"
}

##############################################################################
# Pane Matching and Display
##############################################################################

# Find panes matching the pattern
# Outputs matching panes in format: window_index|tab_index|session_index|name
find_matching_panes() {
    local raw_data="$1"
    local pattern="$2"
    local window_filter="${3:-}"
    local tab_filter="${4:-}"

    local matches=()

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Split by unit separator (ASCII 31)
        local window_idx tab_idx session_idx name
        IFS=$'\x1f' read -r window_idx tab_idx session_idx name <<< "$line"

        # Apply window filter if specified
        if [[ -n "$window_filter" && "$window_idx" != "$window_filter" ]]; then
            continue
        fi

        # Apply tab filter if specified
        if [[ -n "$tab_filter" && "$tab_idx" != "$tab_filter" ]]; then
            continue
        fi

        # Check if name contains pattern (substring match, case-sensitive)
        if [[ "$name" == *"$pattern"* ]]; then
            matches+=("$window_idx|$tab_idx|$session_idx|$name")
        fi
    done <<< "$raw_data"

    # Output matches (only if there are any)
    if [[ ${#matches[@]} -gt 0 ]]; then
        printf '%s\n' "${matches[@]}"
    fi
}

# Display matching panes for dry-run or confirmation
display_matching_panes() {
    local matches="$1"
    local count=0

    while IFS= read -r match; do
        [[ -z "$match" ]] && continue

        local window_idx tab_idx session_idx name
        IFS='|' read -r window_idx tab_idx session_idx name <<< "$match"

        # Truncate name if too long
        local display_name="$name"
        if [[ ${#display_name} -gt 40 ]]; then
            display_name="${display_name:0:37}..."
        fi

        echo "  Window $window_idx, Tab $tab_idx, Pane $session_idx: $display_name"
        count=$((count + 1))
    done <<< "$matches"

    return $count
}

# Prompt for confirmation
prompt_confirmation() {
    local count="$1"

    echo ""
    read -r -p "Found $count matching panes. Close them all? [y/N]: " response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

##############################################################################
# Main Execution
##############################################################################

main() {
    # Parse arguments
    if ! parse_arguments "$@"; then
        exit $EXIT_INVALID_ARGS
    fi

    # Build list panes AppleScript
    local list_applescript
    list_applescript=$(build_list_panes_applescript)

    # Build close panes AppleScript (needed for dry-run display)
    local close_applescript
    close_applescript=$(build_close_panes_applescript "$ARG_PATTERN" "$ARG_WINDOW" "$ARG_TAB")

    # Dry-run mode: display AppleScripts and exit
    if [[ "$ARG_DRY_RUN" == "true" ]]; then
        iterm_info "Dry-run mode: Showing AppleScript that would be executed"
        echo ""
        echo "=== Query AppleScript ==="
        echo "$list_applescript"
        echo ""
        echo "=== Close AppleScript ==="
        echo "$close_applescript"
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
        iterm_info "Querying iTerm2 panes via SSH (container mode)"
    else
        # Host mode: validate iTerm2 is installed
        if ! validate_iterm; then
            exit $EXIT_ITERM_UNAVAILABLE
        fi
        iterm_info "Querying iTerm2 panes (host mode)"
    fi

    # Execute list panes AppleScript
    local raw_output
    if ! raw_output=$(run_applescript "$list_applescript"); then
        iterm_error "Failed to query iTerm2 panes"
        exit $EXIT_CONNECTION_FAIL
    fi

    # Check for special responses
    if [[ "$raw_output" == "ITERM_NOT_RUNNING" ]]; then
        iterm_error "iTerm2 is not running"
        exit $EXIT_ITERM_UNAVAILABLE
    fi

    if [[ "$raw_output" == "NO_WINDOWS" || -z "$raw_output" ]]; then
        iterm_error "No panes match pattern '$ARG_PATTERN'"
        exit $EXIT_NO_MATCH
    fi

    # Validate window filter if specified
    if [[ -n "$ARG_WINDOW" ]]; then
        local window_exists=false
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local window_idx
            IFS=$'\x1f' read -r window_idx _ _ _ <<< "$line"
            if [[ "$window_idx" == "$ARG_WINDOW" ]]; then
                window_exists=true
                break
            fi
        done <<< "$raw_output"

        if [[ "$window_exists" == "false" ]]; then
            iterm_error "Window $ARG_WINDOW not found"
            exit $EXIT_INVALID_ARGS
        fi
    fi

    # Validate tab filter if specified
    if [[ -n "$ARG_TAB" ]]; then
        local tab_exists=false
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local tab_idx
            IFS=$'\x1f' read -r _ tab_idx _ _ <<< "$line"
            # If window filter is also set, only check tabs in that window
            if [[ -n "$ARG_WINDOW" ]]; then
                local w_idx
                IFS=$'\x1f' read -r w_idx tab_idx _ _ <<< "$line"
                if [[ "$w_idx" == "$ARG_WINDOW" && "$tab_idx" == "$ARG_TAB" ]]; then
                    tab_exists=true
                    break
                fi
            else
                if [[ "$tab_idx" == "$ARG_TAB" ]]; then
                    tab_exists=true
                    break
                fi
            fi
        done <<< "$raw_output"

        if [[ "$tab_exists" == "false" ]]; then
            iterm_error "Tab $ARG_TAB not found"
            exit $EXIT_INVALID_ARGS
        fi
    fi

    # Find matching panes
    local matching_panes
    matching_panes=$(find_matching_panes "$raw_output" "$ARG_PATTERN" "$ARG_WINDOW" "$ARG_TAB")

    # Count matches
    local match_count=0
    while IFS= read -r match; do
        [[ -n "$match" ]] && match_count=$((match_count + 1))
    done <<< "$matching_panes"

    # Handle no matches
    if [[ "$match_count" -eq 0 ]]; then
        iterm_error "No panes match pattern '$ARG_PATTERN'"
        exit $EXIT_NO_MATCH
    fi

    # Display matches
    echo "Matching panes found:"
    display_matching_panes "$matching_panes"

    # Prompt for confirmation if multiple matches and not --force
    if [[ "$match_count" -gt 1 && "$ARG_FORCE" == "false" ]]; then
        if ! prompt_confirmation "$match_count"; then
            iterm_info "Operation cancelled"
            exit $EXIT_SUCCESS
        fi
    fi

    # Execute close panes AppleScript
    iterm_info "Closing matching panes..."
    local close_result
    if ! close_result=$(run_applescript "$close_applescript"); then
        iterm_error "Failed to close iTerm2 panes"
        exit $EXIT_CONNECTION_FAIL
    fi

    # Check for errors
    if [[ "$close_result" == "ITERM_NOT_RUNNING" ]]; then
        iterm_error "iTerm2 is not running"
        exit $EXIT_ITERM_UNAVAILABLE
    fi

    if [[ "$close_result" == "WINDOW_NOT_FOUND" ]]; then
        iterm_error "Window $ARG_WINDOW not found"
        exit $EXIT_INVALID_ARGS
    fi

    if [[ "$close_result" == "TAB_NOT_FOUND" ]]; then
        iterm_error "Tab $ARG_TAB not found"
        exit $EXIT_INVALID_ARGS
    fi

    # Report success
    iterm_ok "Closed $close_result pane(s) matching '$ARG_PATTERN'"
    exit $EXIT_SUCCESS
}

main "$@"
