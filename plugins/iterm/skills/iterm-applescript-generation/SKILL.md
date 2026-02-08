---
name: iterm-applescript-generation
description: Pattern for generating iTerm2 AppleScript with window checks, dual tell blocks, and conditional configuration
origin: PANE-001
created: 2026-02-08
tags: [iterm, applescript, code-generation]
---

# iTerm AppleScript Generation Pattern

## Overview

This skill documents the established pattern for generating AppleScript for iTerm2 pane and tab operations in the iTerm plugin. The pattern includes window existence validation, dual tell block structure for operations and configuration, and conditional sections based on arguments.

This pattern ensures consistent error handling and operation structure across all iTerm plugin scripts.

## When to Use

Apply this pattern when:

- Creating new iTerm2 operations (pane splits, tab creation, session management)
- Building AppleScript dynamically from command-line arguments
- Implementing operations that require window validation
- Needing to configure iTerm2 sessions (set name, write text, etc.)

## Pattern/Procedure

### Core Structure

AppleScript generation follows this template:

```applescript
tell application "iTerm2"
    activate

    -- VALIDATION BLOCK (optional but recommended)
    if (count of windows) is 0 then
        return "NO_WINDOWS"
    end if

    -- OPERATION BLOCK (required)
    tell current session of current tab of first window
        -- perform operation (split, create tab, etc.)
    end tell

    -- CONFIGURATION BLOCK (conditional)
    tell current session of current tab of first window
        -- set name, write text, etc. (if arguments provided)
    end tell
end tell
```

### Key Components

#### 1. Application Activation

Always start with `activate` to ensure iTerm2 is frontmost:

```applescript
tell application "iTerm2"
    activate
```

**Why:** Operations on background applications can fail or behave unpredictably.

#### 2. Window Count Validation

For operations requiring existing windows, check before attempting operation:

```applescript
if (count of windows) is 0 then
    return "NO_WINDOWS"
end if
```

**When to use:**
- Pane splits (requires existing session)
- Session modifications (requires target session)

**When to skip:**
- Tab creation (can create window if none exist)
- Window creation operations

**Error handling:** Shell script checks for "NO_WINDOWS" return value and exits with appropriate error message.

#### 3. Operation Block

Single `tell` block for the primary operation:

```applescript
tell current session of current tab of first window
    split vertically with profile "Devcontainer"
end tell
```

**Targeting convention:**
- Always use `first window` for safety (not `current window`)
- Use `current session` for pane operations
- Use `current tab` for tab-level operations

**Why `first window`:** Multi-window safety. `current window` may be undefined; `first window` is always the frontmost window.

#### 4. Configuration Block

Separate `tell` block for post-operation configuration:

```applescript
tell current session of current tab of first window
    set name to "session title"
    write text "command to execute"
end tell
```

**Why separate block:** After operations like `split`, the new session receives focus. A second `tell current session` correctly targets the newly created pane/tab.

**Conditional inclusion:** Only include if configuration arguments were provided (`-n` for name, `-c` for command).

### Bash Implementation Pattern

```bash
build_applescript() {
    local direction="${1:-vertical}"
    local profile="${2:-Devcontainer}"
    local command="${3:-}"
    local name="${4:-}"

    # Escape special characters
    local escaped_profile
    escaped_profile=$(escape_applescript_string "$profile")

    # Start AppleScript
    local script
    script=$(cat << EOF
tell application "iTerm2"
    activate

    -- Window count validation
    if (count of windows) is 0 then
        return "NO_WINDOWS"
    end if

    -- Operation block
    tell current session of current tab of first window
        split ${direction} with profile "${escaped_profile}"
    end tell

EOF
)

    # Conditional configuration block
    if [[ -n "$name" || -n "$command" ]]; then
        script+=$(cat << EOF
    -- Configuration block
    tell current session of current tab of first window
EOF
)

        if [[ -n "$name" ]]; then
            local escaped_name
            escaped_name=$(escape_applescript_string "$name")
            script+=$(cat << EOF

        set name to "${escaped_name}"
EOF
)
        fi

        if [[ -n "$command" ]]; then
            local escaped_command
            escaped_command=$(escape_applescript_string "$command")
            script+=$(cat << EOF

        write text "${escaped_command}"
EOF
)
        fi

        script+=$(cat << EOF

    end tell
EOF
)
    fi

    # Close AppleScript
    script+=$(cat << EOF

end tell
EOF
)

    printf '%s' "$script"
}
```

### String Escaping

Always escape user-provided strings before embedding in AppleScript:

```bash
escape_applescript_string() {
    local input="$1"
    # Escape backslashes first, then double quotes
    local escaped="${input//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    printf '%s' "$escaped"
}
```

**Critical:** Escape backslashes before quotes to avoid double-escaping.

## Examples

### Example 1: Pane Split with Full Configuration

```bash
# Input
build_applescript "vertical" "Devcontainer" "npm test" "tests"

# Generated AppleScript
tell application "iTerm2"
    activate

    if (count of windows) is 0 then
        return "NO_WINDOWS"
    end if

    tell current session of current tab of first window
        split vertically with profile "Devcontainer"
    end tell

    tell current session of current tab of first window
        set name to "tests"
        write text "npm test"
    end tell
end tell
```

### Example 2: Pane Split with Name Only

```bash
# Input
build_applescript "horizontal" "Development" "" "Monitor Pane"

# Generated AppleScript
tell application "iTerm2"
    activate

    if (count of windows) is 0 then
        return "NO_WINDOWS"
    end if

    tell current session of current tab of first window
        split horizontally with profile "Development"
    end tell

    tell current session of current tab of first window
        set name to "Monitor Pane"
    end tell
end tell
```

### Example 3: Minimal Pane Split

```bash
# Input
build_applescript "vertical" "Devcontainer" "" ""

# Generated AppleScript
tell application "iTerm2"
    activate

    if (count of windows) is 0 then
        return "NO_WINDOWS"
    end if

    tell current session of current tab of first window
        split vertically with profile "Devcontainer"
    end tell
end tell
```

### Example 4: Shell-Side Error Handling

```bash
# In main() function
result=$(run_applescript "$applescript")

if [[ "$result" == "NO_WINDOWS" ]]; then
    iterm_error "No iTerm2 windows open. Cannot split pane."
    iterm_error "Open an iTerm2 window first, then retry."
    return "$EXIT_INVALID_ARGS"
fi
```

## References

- Ticket: PANE-001
- Related files:
  - `plugins/iterm/skills/pane-management/scripts/iterm-split-pane.sh` (build_applescript function, lines 200-260)
  - `plugins/iterm/skills/tab-management/scripts/iterm-open-tab.sh` (similar pattern for tab creation)
- Architecture document: `archive/tickets/PANE-001_core-split-script/planning/architecture.md` (Decision 3: Single AppleScript Block for Split + Configure)
