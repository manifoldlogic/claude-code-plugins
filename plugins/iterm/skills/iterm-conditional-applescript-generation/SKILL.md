---
name: iterm-conditional-applescript-generation
description: Pattern for generating AppleScript variants based on window/tab filters to optimize iteration scope
origin: PANE-003
created: 2026-02-09
tags: [iterm, applescript, filtering, optimization]
---

# iTerm Conditional AppleScript Generation

## Overview

This skill documents the pattern for generating different AppleScript variants based on window and tab filter arguments. Instead of iterating all windows/tabs and filtering in AppleScript, the pattern generates four distinct AppleScript structures that optimize iteration scope by directly targeting filtered windows/tabs when filters are provided.

This pattern is used in `iterm-close-pane.sh` for filtered close operations and should be applied to any iTerm operation that supports `-w/--window` and `-t/--tab` filtering.

## When to Use

Apply this pattern when:

- Implementing window or tab filtering for any iTerm operation (close, list, modify)
- Optimizing AppleScript to avoid unnecessary iteration
- Building operations where filters significantly reduce the scope of work
- Supporting `-w/--window` and `-t/--tab` command-line flags
- Generating AppleScript dynamically based on parsed arguments

## Pattern/Procedure

### Four AppleScript Variants

Based on whether window and tab filters are provided, generate one of four AppleScript structures:

| Window Filter | Tab Filter | AppleScript Structure |
|---------------|------------|----------------------|
| None | None | Full iteration (all windows, all tabs) |
| Provided | None | Targeted window, iterate tabs |
| None | Provided | Iterate windows, targeted tab in each |
| Provided | Provided | Targeted window and tab |

### Bash Implementation Pattern

```bash
build_close_panes_applescript() {
    local pattern="$1"
    local window_filter="${2:-}"
    local tab_filter="${3:-}"

    # Escape pattern for AppleScript
    local escaped_pattern
    escaped_pattern=$(escape_applescript_string "$pattern")

    local script=""

    if [[ -n "$window_filter" && -n "$tab_filter" ]]; then
        # Variant 1: Both window and tab specified
        script="<AppleScript targeting window W, tab T>"

    elif [[ -n "$window_filter" ]]; then
        # Variant 2: Window only
        script="<AppleScript targeting window W, iterating tabs>"

    elif [[ -n "$tab_filter" ]]; then
        # Variant 3: Tab only
        script="<AppleScript iterating windows, targeting tab T in each>"

    else
        # Variant 4: No filters
        script="<AppleScript iterating all windows and tabs>"
    fi

    printf '%s' "$script"
}
```

### Variant 1: Window + Tab Filter (Most Specific)

When both window and tab are specified, target exactly window W, tab T:

```applescript
tell application "iTerm2"
    if not running then
        return "ITERM_NOT_RUNNING"
    end if
    set windowCount to count of windows
    if windowCount < $window_filter then
        return "WINDOW_NOT_FOUND"
    end if
    set closedCount to 0
    tell window $window_filter
        if (count of tabs) < $tab_filter then
            return "TAB_NOT_FOUND"
        end if
        tell tab $tab_filter
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
    end tell
    return closedCount
end tell
```

**Key features:**
- Direct `tell window $window_filter` (no iteration)
- Direct `tell tab $tab_filter` (no iteration)
- Validates window and tab existence
- Only iterates sessions within the targeted tab

**Performance:** O(sessions in tab T) -- most efficient

### Variant 2: Window Filter Only

When only window is specified, target window W but iterate all its tabs:

```applescript
tell application "iTerm2"
    if not running then
        return "ITERM_NOT_RUNNING"
    end if
    set windowCount to count of windows
    if windowCount < $window_filter then
        return "WINDOW_NOT_FOUND"
    end if
    set closedCount to 0
    tell window $window_filter
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
    return closedCount
end tell
```

**Key features:**
- Direct `tell window $window_filter` (no window iteration)
- Iterates tabs within the window
- Reverse iteration for tab loop (in case closing last session closes tab)

**Performance:** O(tabs × sessions in window W)

### Variant 3: Tab Filter Only

When only tab is specified, iterate all windows but target tab T in each:

```applescript
tell application "iTerm2"
    if not running then
        return "ITERM_NOT_RUNNING"
    end if
    set closedCount to 0
    repeat with w from (count of windows) to 1 by -1
        tell window w
            if (count of tabs) >= $tab_filter then
                tell tab $tab_filter
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
            end if
        end tell
    end repeat
    return closedCount
end tell
```

**Key features:**
- Iterates windows (reverse order)
- Checks if tab T exists in current window (`>= $tab_filter`)
- Direct `tell tab $tab_filter` (no tab iteration)
- Skips windows that don't have tab T

**Performance:** O(windows × sessions in tab T)

**Use case:** "Close all panes matching pattern in tab 2 of every window"

### Variant 4: No Filters (Full Iteration)

When no filters are specified, iterate everything:

```applescript
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
```

**Key features:**
- Triple-nested reverse iteration (windows, tabs, sessions)
- No direct targeting
- Processes all sessions in all tabs in all windows

**Performance:** O(windows × tabs × sessions) -- least efficient, but necessary when no filters provided

## Examples

### Example 1: Variant 1 Usage (Window + Tab)

**Command:** `iterm-close-pane.sh -w 1 -t 2 "agent"`

**Generated AppleScript:**
- Targets `window 1` directly
- Targets `tab 2` directly
- Iterates only sessions within window 1, tab 2
- Validates window 1 and tab 2 exist before attempting operation

**Performance:** If window 1, tab 2 has 5 sessions, only 5 iterations occur (not N windows × M tabs × 5 sessions).

### Example 2: Variant 2 Usage (Window Only)

**Command:** `iterm-close-pane.sh -w 2 "worker"`

**Generated AppleScript:**
- Targets `window 2` directly
- Iterates all tabs in window 2
- Iterates all sessions in each tab

**Performance:** If window 2 has 3 tabs with 2 sessions each, 6 iterations occur (not N windows × 3 tabs × 2 sessions).

### Example 3: Variant 3 Usage (Tab Only)

**Command:** `iterm-close-pane.sh -t 1 "main"`

**Generated AppleScript:**
- Iterates all windows
- Targets `tab 1` in each window (if it exists)
- Iterates sessions in tab 1

**Performance:** If there are 2 windows each with tab 1 having 3 sessions, 6 iterations occur. Windows without tab 1 are skipped.

**Use case:** Close main session in the first tab of every window.

### Example 4: Variant 4 Usage (No Filters)

**Command:** `iterm-close-pane.sh "temp"`

**Generated AppleScript:**
- Iterates all windows
- Iterates all tabs in each window
- Iterates all sessions in each tab

**Performance:** If there are 2 windows, 4 tabs per window, 3 sessions per tab, 24 iterations occur.

### Example 5: Validation Errors

**Window doesn't exist:**

```applescript
if windowCount < $window_filter then
    return "WINDOW_NOT_FOUND"
end if
```

Shell handles the error:

```bash
if [[ "$close_result" == "WINDOW_NOT_FOUND" ]]; then
    iterm_error "Window $ARG_WINDOW not found"
    exit $EXIT_INVALID_ARGS
fi
```

**Tab doesn't exist:**

```applescript
if (count of tabs) < $tab_filter then
    return "TAB_NOT_FOUND"
end if
```

Shell handles the error:

```bash
if [[ "$close_result" == "TAB_NOT_FOUND" ]]; then
    iterm_error "Tab $ARG_TAB not found"
    exit $EXIT_INVALID_ARGS
fi
```

## Implementation Notes

### Shell-Side Filter Validation

Before generating AppleScript, validate filter values are positive integers:

```bash
# In parse_arguments()
if ! [[ "$ARG_WINDOW" =~ ^[1-9][0-9]*$ ]]; then
    iterm_error "Invalid window index: $ARG_WINDOW (must be a positive integer)"
    return $EXIT_INVALID_ARGS
fi

if ! [[ "$ARG_TAB" =~ ^[1-9][0-9]*$ ]]; then
    iterm_error "Invalid tab index: $ARG_TAB (must be a positive integer)"
    return $EXIT_INVALID_ARGS
fi
```

### AppleScript-Side Existence Validation

Always validate window/tab exists before attempting to target it:

```applescript
# Window validation
set windowCount to count of windows
if windowCount < $window_filter then
    return "WINDOW_NOT_FOUND"
end if

# Tab validation (inside window tell block)
if (count of tabs) < $tab_filter then
    return "TAB_NOT_FOUND"
end if
```

**Why both shell and AppleScript validation:** Shell validation catches obvious errors early (e.g., non-numeric input). AppleScript validation handles race conditions (window/tab closed between query and close phases).

### Reverse Iteration in All Variants

All four variants use reverse iteration for sessions (`to 1 by -1`). Variants 2-4 also use reverse iteration for tabs and windows to handle the case where closing the last session closes the tab, and closing the last tab closes the window.

### String Escaping

Always escape the pattern before embedding in AppleScript:

```bash
local escaped_pattern
escaped_pattern=$(escape_applescript_string "$pattern")
```

Use `escaped_pattern` in AppleScript contains clause:

```applescript
if name of session s contains "$escaped_pattern" then
```

## References

- Ticket: PANE-003
- Related files:
  - `plugins/iterm/skills/pane-management/scripts/iterm-close-pane.sh` (build_close_panes_applescript function, lines 265-397, implements all four variants)
  - Future: Apply this pattern to `iterm-list-panes.sh` (PANE-002) for filtered listing
  - Future: Apply this pattern to any tab-level operations with filtering
- Architecture document: `/workspace/_SPECS/claude-code-plugins/archive/tickets/PANE-003_pane-close/planning/architecture.md` (Decision 6: Window and Tab Filter Applied in Close AppleScript, Decision 7: Tab Filter Requires Window Filter)
