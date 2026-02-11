---
name: iterm-triple-nested-loops
description: AppleScript pattern for enumerating all iTerm2 sessions using triple-nested loops with field delimiters
origin: PANE-003
created: 2026-02-09
tags: [iterm, applescript, enumeration, parsing]
---

# iTerm Triple-Nested Loop Enumeration

## Overview

This skill documents the standard pattern for enumerating all iTerm2 sessions (panes) across all tabs in all windows using AppleScript. The pattern uses triple-nested loops (windows → tabs → sessions) with ASCII 31 (unit separator) as a field delimiter to produce structured output that can be safely parsed by shell scripts.

This pattern is used in `iterm-close-pane.sh` for session enumeration and should be used in any operation that needs to list, search, or filter iTerm2 sessions.

## When to Use

Apply this pattern when:

- Listing all iTerm2 sessions/panes (e.g., PANE-002 `iterm-list-panes.sh`)
- Finding sessions matching a pattern (used in `iterm-close-pane.sh`)
- Collecting session properties for bulk operations
- Implementing search or filter operations across all panes
- Building status reports or session inventories

## Pattern/Procedure

### Core AppleScript Structure

```applescript
tell application "iTerm2"
    -- Validation
    if not running then
        return "ITERM_NOT_RUNNING"
    end if
    set windowCount to count of windows
    if windowCount is 0 then
        return "NO_WINDOWS"
    end if

    -- Initialize output
    set output to ""

    -- Triple-nested enumeration
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
                        -- Build output line with field delimiters
                        set output to output & w & (ASCII character 31) & t & (ASCII character 31) & s & (ASCII character 31) & sessionName & (ASCII character 10)
                    end repeat
                end tell
            end repeat
        end tell
    end repeat

    return output
end tell
```

### Key Components

#### 1. Validation Block

Always validate iTerm2 state before attempting enumeration:

```applescript
if not running then
    return "ITERM_NOT_RUNNING"
end if
set windowCount to count of windows
if windowCount is 0 then
    return "NO_WINDOWS"
end if
```

**Why:** Attempting to enumerate windows when none exist causes AppleScript errors. Return sentinel values for shell-side handling.

#### 2. Count-Based Iteration

Use `count of windows`, `count of tabs`, `count of sessions` rather than iterating collections directly:

```applescript
set windowCount to count of windows
repeat with w from 1 to windowCount
    tell window w
        set tabCount to count of tabs
        repeat with t from 1 to tabCount
            tell tab t
                set sessionCount to count of sessions
                repeat with s from 1 to sessionCount
                    -- access session s
                end repeat
            end tell
        end repeat
    end tell
end repeat
```

**Why:** Count-based iteration provides stable indices for session access. Collection-based iteration (`repeat with session in sessions`) doesn't provide indices needed for targeting.

#### 3. Error Handling for Transient Sessions

Wrap session property access in try/on error blocks:

```applescript
try
    set sessionName to name of session s
on error
    set sessionName to ""
end try
```

**Why:** Sessions can be in transient states (closing, initializing). Error handling prevents enumeration failure when encountering unstable sessions.

#### 4. Field Delimiter: ASCII 31 (Unit Separator)

Use ASCII character 31 to separate fields in output:

```applescript
set output to output & w & (ASCII character 31) & t & (ASCII character 31) & s & (ASCII character 31) & sessionName & (ASCII character 10)
```

**Output format:** `window_index<US>tab_index<US>session_index<US>session_name<LF>`

**Why ASCII 31:**
- Designed for field separation in structured data
- Extremely unlikely to appear in session names (non-printable)
- Safe for any UTF-8 content in session names
- More robust than tab, comma, or pipe separators

**Shell-side parsing:**

```bash
while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    # Split by unit separator (ASCII 31)
    local window_idx tab_idx session_idx name
    IFS=$'\x1f' read -r window_idx tab_idx session_idx name <<< "$line"

    # Use fields...
done <<< "$raw_output"
```

#### 5. Newline Record Delimiter

Use ASCII character 10 (newline) to separate records:

```applescript
set output to output & ... & (ASCII character 10)
```

**Why:** Shell scripts naturally process line-by-line. Newlines allow standard bash `while read` loops for parsing.

### Bash Integration Pattern

```bash
build_list_panes_applescript() {
    # Return the triple-nested enumeration AppleScript
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

# Execute and parse
raw_output=$(run_applescript "$(build_list_panes_applescript)")

# Check for special responses
if [[ "$raw_output" == "ITERM_NOT_RUNNING" ]]; then
    iterm_error "iTerm2 is not running"
    exit $EXIT_ITERM_UNAVAILABLE
fi

if [[ "$raw_output" == "NO_WINDOWS" || -z "$raw_output" ]]; then
    iterm_error "No iTerm2 windows found"
    exit $EXIT_NO_MATCH
fi

# Parse each record
while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    local window_idx tab_idx session_idx name
    IFS=$'\x1f' read -r window_idx tab_idx session_idx name <<< "$line"

    echo "Window $window_idx, Tab $tab_idx, Pane $session_idx: $name"
done <<< "$raw_output"
```

### Extending with Additional Properties

To collect more session properties, add fields to the output format:

```applescript
repeat with s from 1 to sessionCount
    try
        set sessionName to name of session s
        set sessionTTY to tty of session s
        set sessionCols to columns of session s
        set sessionRows to rows of session s
    on error
        set sessionName to ""
        set sessionTTY to ""
        set sessionCols to 0
        set sessionRows to 0
    end try
    set output to output & w & (ASCII character 31) & t & (ASCII character 31) & s & (ASCII character 31) & sessionName & (ASCII character 31) & sessionTTY & (ASCII character 31) & sessionCols & (ASCII character 31) & sessionRows & (ASCII character 10)
end repeat
```

**Updated shell parsing:**

```bash
IFS=$'\x1f' read -r window_idx tab_idx session_idx name tty cols rows <<< "$line"
```

## Examples

### Example 1: Simple Enumeration (from PANE-003)

Used in `iterm-close-pane.sh` to enumerate all sessions before filtering for close operation.

**Input:** iTerm2 with 1 window, 2 tabs, 3 total sessions
- Window 1, Tab 1: 2 sessions ("Devcontainer", "agent: tests")
- Window 1, Tab 2: 1 session ("Logs")

**Output:**
```
1\x1f1\x1f1\x1fDevcontainer\n
1\x1f1\x1f2\x1fagent: tests\n
1\x1f2\x1f1\x1fLogs\n
```

**Parsed:**
```
Window 1, Tab 1, Pane 1: Devcontainer
Window 1, Tab 1, Pane 2: agent: tests
Window 1, Tab 2, Pane 1: Logs
```

### Example 2: Multi-Window Enumeration

**Input:** iTerm2 with 2 windows
- Window 1, Tab 1: 1 session ("main")
- Window 2, Tab 1: 2 sessions ("split-left", "split-right")

**Output:**
```
1\x1f1\x1f1\x1fmain\n
2\x1f1\x1f1\x1fsplit-left\n
2\x1f1\x1f2\x1fsplit-right\n
```

### Example 3: Error Handling for Missing Sessions

If a session is closing while enumeration runs, the try/on error block prevents failure:

```applescript
repeat with s from 1 to sessionCount
    try
        set sessionName to name of session s  -- May fail if session just closed
    on error
        set sessionName to ""  -- Continue with empty name
    end try
    -- Still produces output line with empty name field
end repeat
```

### Example 4: Filtering After Enumeration

Shell-side filtering for pattern matching (used in close operations):

```bash
while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    local window_idx tab_idx session_idx name
    IFS=$'\x1f' read -r window_idx tab_idx session_idx name <<< "$line"

    # Filter for pattern
    if [[ "$name" == *"agent"* ]]; then
        echo "Match: Window $window_idx, Tab $tab_idx, Pane $session_idx: $name"
    fi
done <<< "$raw_output"
```

## References

- Ticket: PANE-003
- Related files:
  - `plugins/iterm/skills/pane-management/scripts/iterm-close-pane.sh` (build_list_panes_applescript function, lines 224-259)
  - Future: `plugins/iterm/skills/pane-management/scripts/iterm-list-panes.sh` (PANE-002, will use this pattern)
- Architecture document: `/workspace/_SPECS/claude-code-plugins/tickets/PANE-003_pane-close/planning/architecture.md` (Decision 2: Triple-Nested Query AppleScript, Technology Choices: Field delimiter)
