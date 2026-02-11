---
name: iterm-two-phase-close-pattern
description: Two-phase architecture for destructive iTerm operations with query, match, and close phases using reverse iteration
origin: PANE-003
created: 2026-02-09
tags: [iterm, applescript, architecture, safety]
---

# iTerm Two-Phase Close Pattern

## Overview

This skill documents the architectural pattern for implementing destructive iTerm2 operations (close panes, close tabs, close windows) in the iTerm plugin. The pattern separates enumeration from deletion to enable dry-run preview, confirmation prompts, and atomic close operations with reverse iteration to prevent index shifting bugs.

This pattern is used in `iterm-close-tab.sh` and `iterm-close-pane.sh` and should be followed for any future destructive operations in the iTerm plugin.

## When to Use

Apply this pattern when:

- Implementing any destructive iTerm2 operation (close panes, close tabs, close windows, bulk deletions)
- Building operations that require user confirmation before execution
- Supporting dry-run preview of what would be affected
- Needing to close multiple targets atomically with correct index handling
- Implementing pattern-based or filtered close operations

## Pattern/Procedure

### Three-Phase Architecture

The two-phase close pattern actually consists of three distinct phases:

#### Phase 1: Query (Enumeration)

Build and execute a dedicated AppleScript that enumerates all potential targets (sessions, tabs, windows) and returns structured data.

**Key characteristics:**
- Read-only AppleScript (no mutations)
- Returns all targets, not just matches
- Uses field delimiters (ASCII 31) for safe parsing
- Handles errors gracefully (try/on error blocks)
- Single execution, returns all data at once

**Example (from iterm-close-pane.sh):**

```bash
build_list_panes_applescript() {
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
            repeat with t from 1 to tabCount
                tell tab t
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
```

#### Phase 2: Match (Shell-Level Filtering)

Parse query results in shell, apply pattern matching and filters, display matches to user, handle dry-run and confirmation.

**Key characteristics:**
- Shell-level string processing (no AppleScript execution)
- Pattern matching using substring match (`[[ "$name" == *"$pattern"* ]]`)
- Window/tab filter application
- Display formatted matches to user
- Dry-run exits here (no close AppleScript executed)
- Confirmation prompt for multiple matches (unless `--force`)

**Example (from iterm-close-pane.sh):**

```bash
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
```

#### Phase 3: Close (Reverse Iteration Deletion)

Build and execute a separate AppleScript that closes only matching targets using reverse iteration to prevent index shifting.

**Key characteristics:**
- Destructive AppleScript (mutates iTerm state)
- Pattern matching done in AppleScript (`contains` keyword)
- Reverse iteration (`to 1 by -1`) at all nesting levels
- Window/tab filtering applied in AppleScript structure
- Single atomic execution (all closes in one run)
- Returns count of closed items
- Error handling for each deletion (try/on error)

**Example (from iterm-close-pane.sh, no filters case):**

```bash
build_close_panes_applescript() {
    local pattern="$1"
    local window_filter="${2:-}"
    local tab_filter="${3:-}"

    # Escape pattern for AppleScript
    local escaped_pattern
    escaped_pattern=$(escape_applescript_string "$pattern")

    # No filters: close panes in all windows and all tabs
    if [[ -z "$window_filter" && -z "$tab_filter" ]]; then
        cat << EOF
tell application "iTerm2"
    if not running then
        return "ITERM_NOT_RUNNING"
    end if
    set closedCount to 0
    repeat with w from (count of windows) to 1 by -1
        tell window w
            repeat with t from (count of tabs) to 1 by -1
                tell tab t
                    repeat with s from (count of sessions) to 1 by -1
                        try
                            if name of session s contains "$escaped_pattern" then
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
end tell
EOF
    fi
    # ... other filter cases (window only, tab only, window+tab)
}
```

### Why Two Separate AppleScripts?

**Atomicity:** The close AppleScript executes all deletions in a single run, minimizing the window for state changes between query and close.

**Dry-run support:** Query AppleScript can be executed without side effects, allowing safe preview of what would be closed.

**Confirmation UX:** Shell can display formatted matches and prompt user before executing the close AppleScript.

**Pattern flexibility:** Shell-level matching supports complex filters and display formatting without complicating AppleScript.

**Testing:** Query AppleScript can be tested independently; dry-run mode exercises most of the code path without requiring live deletion.

### Reverse Iteration Requirement

When closing multiple items, always iterate in reverse order (`to 1 by -1`) to prevent index shifting bugs:

```applescript
# CORRECT: Reverse iteration
repeat with s from (count of sessions) to 1 by -1
    if name of session s contains "pattern" then
        tell session s to close
    end if
end repeat

# WRONG: Forward iteration
# If you close session 2 of 3, session 3 becomes session 2
# Forward iteration would skip the shifted item or error on non-existent index
repeat with s from 1 to (count of sessions)
    if name of session s contains "pattern" then
        tell session s to close  # BAD: indices shift during iteration
    end if
end repeat
```

Reverse iteration is required at ALL nesting levels when any level performs deletions.

### Main Function Orchestration

```bash
main() {
    # Parse arguments
    parse_arguments "$@"

    # Build query AppleScript
    local list_applescript
    list_applescript=$(build_list_panes_applescript)

    # Build close AppleScript (needed for dry-run display)
    local close_applescript
    close_applescript=$(build_close_panes_applescript "$ARG_PATTERN" "$ARG_WINDOW" "$ARG_TAB")

    # Dry-run mode: display AppleScripts and exit
    if [[ "$ARG_DRY_RUN" == "true" ]]; then
        iterm_info "Dry-run mode: Showing AppleScript that would be executed"
        echo "=== Query AppleScript ==="
        echo "$list_applescript"
        echo "=== Close AppleScript ==="
        echo "$close_applescript"
        exit $EXIT_SUCCESS
    fi

    # Validate prerequisites (iTerm running, SSH connected)
    validate_iterm
    if is_container; then
        validate_ssh_host
    fi

    # Execute query AppleScript
    local raw_output
    raw_output=$(run_applescript "$list_applescript")

    # Find matching targets
    local matching_panes
    matching_panes=$(find_matching_panes "$raw_output" "$ARG_PATTERN" "$ARG_WINDOW" "$ARG_TAB")

    # Handle no matches
    if [[ -z "$matching_panes" ]]; then
        iterm_error "No panes match pattern '$ARG_PATTERN'"
        exit $EXIT_NO_MATCH
    fi

    # Display matches
    echo "Matching panes found:"
    display_matching_panes "$matching_panes"

    # Prompt for confirmation if multiple matches and not --force
    local match_count
    match_count=$(echo "$matching_panes" | wc -l | tr -d ' ')
    if [[ "$match_count" -gt 1 && "$ARG_FORCE" == "false" ]]; then
        if ! prompt_confirmation "$match_count"; then
            iterm_info "Operation cancelled"
            exit $EXIT_SUCCESS
        fi
    fi

    # Execute close AppleScript
    iterm_info "Closing matching panes..."
    local close_result
    close_result=$(run_applescript "$close_applescript")

    # Report success
    iterm_ok "Closed $close_result pane(s) matching '$ARG_PATTERN'"
    exit $EXIT_SUCCESS
}
```

## Examples

### Example 1: Close Panes by Pattern (from PANE-003)

User invokes: `iterm-close-pane.sh "agent: tests"`

1. **Query phase:** `build_list_panes_applescript()` enumerates all sessions, returns `1\x1f1\x1f1\x1fDevcontainer\n1\x1f1\x1f2\x1fagent: tests\n1\x1f2\x1f1\x1fLogs\n`
2. **Match phase:** `find_matching_panes()` filters for "agent: tests", finds 1 match (window 1, tab 1, pane 2), displays it to user
3. **Close phase:** `build_close_panes_applescript()` generates AppleScript with reverse iteration, executes it, closes 1 pane, reports success

### Example 2: Close Tabs by Pattern (from iterm-close-tab.sh)

User invokes: `iterm-close-tab.sh --force "worktree: feature-"`

1. **Query phase:** Enumerates all tabs, returns `1\x1f1\x1fmain\n1\x1f2\x1fworktree: feature-a\n1\x1f3\x1fworktree: feature-b\n`
2. **Match phase:** Finds 2 matches, `--force` skips confirmation
3. **Close phase:** Closes 2 tabs in reverse order (tab 3 first, then tab 2)

### Example 3: Dry-Run Preview

User invokes: `iterm-close-pane.sh --dry-run "test"`

1. **Query phase:** AppleScript built but NOT executed
2. **Match phase:** NOT executed (dry-run exits before query execution)
3. **Close phase:** AppleScript built and displayed to user, NOT executed
4. Exit 0 (no side effects)

## References

- Ticket: PANE-003
- Related files:
  - `plugins/iterm/skills/pane-management/scripts/iterm-close-pane.sh` (build_list_panes_applescript lines 224-259, build_close_panes_applescript lines 265-397, main function lines 486-652)
  - `plugins/iterm/skills/tab-management/scripts/iterm-close-tab.sh` (original implementation of two-phase pattern)
- Architecture document: `/workspace/_SPECS/claude-code-plugins/archive/tickets/PANE-003_pane-close/planning/architecture.md` (Decision 4: Shell-Level Pattern Matching for Display, AppleScript-Level for Close)
