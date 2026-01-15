#!/usr/bin/env bash
#
# iterm-close-tab.sh - Close iTerm2 tabs by pattern matching
#
# DESCRIPTION:
#   Closes iTerm2 tabs by matching a pattern against tab titles. Supports
#   dry-run preview, confirmation prompts for multiple matches, window filtering,
#   and force mode. Works from both macOS host (direct osascript) and Linux
#   container (SSH tunneling).
#
# USAGE:
#   iterm-close-tab.sh [OPTIONS] <pattern>
#     -w, --window INDEX      Limit to specific window (1-based)
#     --force                 Skip confirmation for multiple matches
#     --dry-run               Show what would be closed
#     -h, --help              Show help
#
# ARGUMENTS:
#   pattern                   Pattern to match tab titles (substring match)
#
# EXIT CODES:
#   0 - Success
#   1 - SSH/connection failure (container mode)
#   2 - iTerm2 not available
#   3 - Invalid arguments
#   4 - Pattern matches no tabs
#
# ENVIRONMENT:
#   HOST_USER - macOS host username (required for container mode)
#               Set in devcontainer.json: "remoteEnv": {"HOST_USER": "your-username"}
#
# NOTES:
#   - Pattern matching is substring match (case-sensitive), not regex
#   - Tabs are closed in reverse order to prevent index shifting bugs
#   - Use quotes for patterns containing spaces
#   - Confirmation required for multiple matches unless --force is used
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
# Usage Information
##############################################################################

show_help() {
    cat << 'EOF'
iterm-close-tab.sh - Close iTerm2 tabs by pattern matching

USAGE:
  iterm-close-tab.sh [OPTIONS] <pattern>

OPTIONS:
  -w, --window INDEX      Limit to specific window (1-based)
  --force                 Skip confirmation for multiple matches
  --dry-run               Show what would be closed
  -h, --help              Show help

ARGUMENTS:
  pattern                 Pattern to match tab titles (substring match)

EXIT CODES:
  0 - Success
  1 - SSH/connection failure (container mode)
  2 - iTerm2 not available
  3 - Invalid arguments
  4 - Pattern matches no tabs

EXAMPLES:
  # Close tabs with "worktree:" in title
  iterm-close-tab.sh "worktree:"

  # Preview which tabs would be closed
  iterm-close-tab.sh --dry-run "feature-branch"

  # Close tabs in window 1 only
  iterm-close-tab.sh -w 1 "test"

  # Close without confirmation prompt
  iterm-close-tab.sh --force "cleanup"

  # Combine options
  iterm-close-tab.sh --force -w 2 "worktree: feature"

NOTES:
  - Pattern matching is substring match (case-sensitive), NOT regex
  - Use quotes for patterns containing spaces
  - Tabs are closed in reverse order to prevent index shifting bugs
  - Confirmation is required for multiple matches unless --force is used
  - In container mode, requires HOST_USER environment variable
EOF
}

##############################################################################
# Argument Parsing
##############################################################################

parse_arguments() {
    # Initialize with defaults
    ARG_WINDOW=""
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
# AppleScript Generation - List Tabs
##############################################################################

build_list_tabs_applescript() {
    # AppleScript to query all windows and tabs
    # Output format: window_index<US>tab_index<US>title<LF>
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
                    set output to output & w & (ASCII character 31) & t & (ASCII character 31) & sessionName & (ASCII character 10)
                end tell
            end repeat
        end tell
    end repeat
    return output
end tell
APPLESCRIPT
}

##############################################################################
# AppleScript Generation - Close Tabs
##############################################################################

build_close_tabs_applescript() {
    local pattern="$1"
    local window_filter="${2:-}"

    # Escape pattern for AppleScript
    local escaped_pattern
    escaped_pattern=$(escape_applescript_string "$pattern")

    # Build the close AppleScript
    # IMPORTANT: Iterate in reverse order to prevent index shifting bugs
    local script=""

    if [[ -n "$window_filter" ]]; then
        # Close tabs in specific window only
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
                try
                    if name of current session contains \"$escaped_pattern\" then
                        close current session
                        set closedCount to closedCount + 1
                    end if
                on error
                    -- Skip tabs that can't be accessed
                end try
            end tell
        end repeat
    end tell
    return closedCount
end tell"
    else
        # Close tabs in all windows
        script="tell application \"iTerm2\"
    if not running then
        return \"ITERM_NOT_RUNNING\"
    end if
    set closedCount to 0
    repeat with w from (count of windows) to 1 by -1
        tell window w
            repeat with t from (count of tabs) to 1 by -1
                tell tab t
                    try
                        if name of current session contains \"$escaped_pattern\" then
                            close current session
                            set closedCount to closedCount + 1
                        end if
                    on error
                        -- Skip tabs that can't be accessed
                    end try
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
# Tab Matching and Display
##############################################################################

# Find tabs matching the pattern
# Outputs matching tabs in format: window_index|tab_index|title
find_matching_tabs() {
    local raw_data="$1"
    local pattern="$2"
    local window_filter="${3:-}"

    local matches=()

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Split by unit separator (ASCII 31)
        local window_idx tab_idx title
        IFS=$'\x1f' read -r window_idx tab_idx title <<< "$line"

        # Apply window filter if specified
        if [[ -n "$window_filter" && "$window_idx" != "$window_filter" ]]; then
            continue
        fi

        # Check if title contains pattern (substring match, case-sensitive)
        if [[ "$title" == *"$pattern"* ]]; then
            matches+=("$window_idx|$tab_idx|$title")
        fi
    done <<< "$raw_data"

    # Output matches
    printf '%s\n' "${matches[@]}"
}

# Display matching tabs for dry-run or confirmation
display_matching_tabs() {
    local matches="$1"
    local count=0

    while IFS= read -r match; do
        [[ -z "$match" ]] && continue

        local window_idx tab_idx title
        IFS='|' read -r window_idx tab_idx title <<< "$match"

        # Truncate title if too long
        local display_title="$title"
        if [[ ${#display_title} -gt 40 ]]; then
            display_title="${display_title:0:37}..."
        fi

        echo "  Window $window_idx, Tab $tab_idx: $display_title"
        count=$((count + 1))
    done <<< "$matches"

    return $count
}

# Prompt for confirmation
prompt_confirmation() {
    local count="$1"

    echo ""
    read -r -p "Found $count matching tabs. Close them all? [y/N]: " response
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

    # Build list tabs AppleScript
    local list_applescript
    list_applescript=$(build_list_tabs_applescript)

    # Validate prerequisites based on context
    if is_container; then
        # Container mode: validate SSH connectivity and HOST_USER
        if ! validate_ssh_host; then
            exit $EXIT_CONNECTION_FAIL
        fi
        if ! validate_iterm; then
            exit $EXIT_ITERM_UNAVAILABLE
        fi
        iterm_info "Querying iTerm2 tabs via SSH (container mode)"
    else
        # Host mode: validate iTerm2 is installed
        if ! validate_iterm; then
            exit $EXIT_ITERM_UNAVAILABLE
        fi
        iterm_info "Querying iTerm2 tabs (host mode)"
    fi

    # Execute list tabs AppleScript
    local raw_output
    if ! raw_output=$(run_applescript "$list_applescript"); then
        iterm_error "Failed to query iTerm2 tabs"
        exit $EXIT_CONNECTION_FAIL
    fi

    # Check for special responses
    if [[ "$raw_output" == "ITERM_NOT_RUNNING" ]]; then
        iterm_error "iTerm2 is not running"
        exit $EXIT_ITERM_UNAVAILABLE
    fi

    if [[ "$raw_output" == "NO_WINDOWS" || -z "$raw_output" ]]; then
        iterm_error "No tabs match pattern '$ARG_PATTERN'"
        exit $EXIT_NO_MATCH
    fi

    # Validate window filter if specified
    if [[ -n "$ARG_WINDOW" ]]; then
        # Check if the window exists in the output
        local window_exists=false
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local window_idx
            IFS=$'\x1f' read -r window_idx _ _ <<< "$line"
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

    # Find matching tabs
    local matching_tabs
    matching_tabs=$(find_matching_tabs "$raw_output" "$ARG_PATTERN" "$ARG_WINDOW")

    # Count matches
    local match_count=0
    while IFS= read -r match; do
        [[ -n "$match" ]] && match_count=$((match_count + 1))
    done <<< "$matching_tabs"

    # Handle no matches
    if [[ "$match_count" -eq 0 ]]; then
        iterm_error "No tabs match pattern '$ARG_PATTERN'"
        exit $EXIT_NO_MATCH
    fi

    # Dry-run mode: display matches and exit
    if [[ "$ARG_DRY_RUN" == "true" ]]; then
        echo "Would close the following tabs:"
        display_matching_tabs "$matching_tabs"
        echo ""
        if [[ "$match_count" -gt 1 ]]; then
            echo "Use --force to close without confirmation."
        fi
        exit $EXIT_SUCCESS
    fi

    # Display matches
    echo "Matching tabs found:"
    display_matching_tabs "$matching_tabs"

    # Prompt for confirmation if multiple matches and not --force
    if [[ "$match_count" -gt 1 && "$ARG_FORCE" == "false" ]]; then
        if ! prompt_confirmation "$match_count"; then
            iterm_info "Operation cancelled"
            exit $EXIT_SUCCESS
        fi
    fi

    # Build close tabs AppleScript
    local close_applescript
    close_applescript=$(build_close_tabs_applescript "$ARG_PATTERN" "$ARG_WINDOW")

    # Execute close tabs AppleScript
    iterm_info "Closing matching tabs..."
    local close_result
    if ! close_result=$(run_applescript "$close_applescript"); then
        iterm_error "Failed to close iTerm2 tabs"
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

    # Report success
    iterm_ok "Closed $close_result tab(s) matching '$ARG_PATTERN'"
    exit $EXIT_SUCCESS
}

main "$@"
