# AppleScript Reference for iTerm2 Tab Management

## Introduction

This reference document provides comprehensive technical documentation for AppleScript patterns and iTerm2 automation API used in the tab management plugin. It serves advanced users who want to understand the underlying technology and maintainers who need to modify or extend the plugin scripts.

### Purpose

- **Maintainer Guide**: Technical foundation for understanding and extending plugin scripts
- **Troubleshooting Reference**: Detailed information for diagnosing AppleScript issues
- **API Documentation**: Complete coverage of iTerm2 AppleScript capabilities
- **Pattern Library**: Proven code patterns extracted from production scripts

### iTerm2 AppleScript Support Overview

iTerm2 provides comprehensive AppleScript support for automating terminal operations. Key capabilities include:

- Creating, closing, and managing tabs and windows
- Setting tab titles and session properties
- Executing commands in terminal sessions
- Querying window and tab state
- Configuring visual appearance (colors, profiles)

All automation in this plugin uses AppleScript executed via the `osascript` command, either directly on macOS or tunneled through SSH from Linux containers.

---

## iTerm2 Object Model

Understanding the iTerm2 object hierarchy is essential for writing effective AppleScript:

```
Application "iTerm2"
  └── Windows (array, 1-indexed)
      ├── index: integer
      ├── bounds: {left, top, right, bottom}
      └── Tabs (array, 1-indexed)
          ├── index: integer
          └── Sessions (array, 1-indexed)
              ├── name: string (tab title)
              ├── tty: string (e.g., "/dev/ttys001")
              ├── contents: string (terminal buffer)
              ├── background color: RGB tuple
              ├── foreground color: RGB tuple
              └── is processing: boolean
```

### Key Concepts

| Concept | Description |
|---------|-------------|
| Window | A single iTerm2 window containing one or more tabs |
| Tab | A tab within a window, containing one or more sessions (split panes) |
| Session | An individual terminal session within a tab |
| Profile | A saved configuration (colors, fonts, commands) that can be applied when creating tabs |
| `current window` | The active/focused window |
| `first window` | The frontmost window (useful for predictable multi-window behavior) |
| `current tab` | The active tab in the referenced window |
| `current session` | The active session in the referenced tab |

---

## Basic Operations

### Activating iTerm2

Always activate iTerm2 before performing operations to ensure it's running and responsive:

```applescript
tell application "iTerm2"
    activate
end tell
```

### Creating Tabs

**Create tab with default profile:**

```applescript
tell application "iTerm2"
    activate
    tell current window
        create tab with default profile
    end tell
end tell
```

**Create tab with specific profile:**

```applescript
tell application "iTerm2"
    activate
    tell first window
        create tab with profile "Devcontainer"
    end tell
end tell
```

> **Note**: We use `first window` (frontmost) rather than `current window` for more predictable behavior in multi-window scenarios. This is a key pattern used throughout the plugin.

**Create tab with fallback for no windows:**

This pattern from `iterm-open-tab.sh` handles the case when no windows exist:

```applescript
tell application "iTerm2"
    activate
    if (count of windows) is 0 then
        create window with profile "Devcontainer"
        tell current session of current tab of first window
            set name to "My Tab"
            write text "cd \"/workspace\" && clear"
        end tell
    else
        tell first window
            create tab with profile "Devcontainer"
            tell current session of current tab
                set name to "My Tab"
                write text "cd \"/workspace\" && clear"
            end tell
        end tell
    end if
end tell
```

### Creating Windows

**Create new window:**

```applescript
tell application "iTerm2"
    activate
    create window with profile "Devcontainer"
end tell
```

**Create window and configure:**

```applescript
tell application "iTerm2"
    activate
    create window with profile "Devcontainer"
    tell current session of current tab of first window
        set name to "New Window Tab"
        write text "cd /workspace && clear"
    end tell
end tell
```

### Setting Tab Properties

**Set tab name/title:**

```applescript
tell application "iTerm2"
    tell current session of current tab of current window
        set name to "My Custom Title"
    end tell
end tell
```

**Execute command in session:**

```applescript
tell application "iTerm2"
    tell current session of current tab of current window
        write text "echo 'Hello, World!'"
    end tell
end tell
```

**Combined: change directory and run command:**

```applescript
tell application "iTerm2"
    tell current session of current tab of first window
        write text "cd \"/workspace/repos/my-project\" && git status && clear"
    end tell
end tell
```

---

## Querying Information

### List All Windows and Tabs

This pattern from `iterm-list-tabs.sh` queries all windows and tabs:

```applescript
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
```

### Get Tab Properties

**Get session name (tab title):**

```applescript
tell application "iTerm2"
    tell current session of current tab of current window
        set tabName to name
    end tell
end tell
```

**Get session TTY:**

```applescript
tell application "iTerm2"
    tell current session of current tab of current window
        set sessionTTY to tty
    end tell
end tell
```

**Get multiple properties:**

```applescript
tell application "iTerm2"
    tell current session of current tab of current window
        set sessionName to name
        set sessionTTY to tty
        set isProcessing to is processing
    end tell
end tell
```

### Check iTerm2 State

**Check if running:**

```applescript
tell application "iTerm2"
    if not running then
        return "NOT_RUNNING"
    end if
    return "RUNNING"
end tell
```

**Count windows:**

```applescript
tell application "iTerm2"
    return count of windows
end tell
```

---

## Closing Tabs

### Close by Pattern

The plugin uses pattern matching to close tabs with titles containing a specific string:

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
                    try
                        if name of current session contains "pattern" then
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
end tell
```

### Why Reverse Iteration is Critical

**The Problem:**

When closing tabs in a forward loop, each closure shifts the indices of subsequent tabs:

```applescript
-- BAD: Forward iteration causes index shifting
repeat with t from 1 to (count of tabs)
    tell tab t
        if name of current session contains "pattern" then
            close current session  -- Remaining tabs shift down!
        end if
    end tell
end repeat
```

Example failure:
- Tabs: [A, B, C, D] (indices 1, 2, 3, 4)
- Close tab 1 (A)
- Tabs become: [B, C, D] (indices 1, 2, 3)
- Loop moves to index 2, but now that's C, skipping B!

**The Solution:**

Iterate backwards so closed tabs don't affect remaining indices:

```applescript
-- GOOD: Reverse iteration prevents index shifting
repeat with t from (count of tabs) to 1 by -1
    tell tab t
        if name of current session contains "pattern" then
            close current session  -- Only affects already-processed indices
        end if
    end tell
end repeat
```

Example success:
- Tabs: [A, B, C, D] (indices 1, 2, 3, 4)
- Start at index 4 (D), don't close
- Index 3 (C), don't close
- Index 2 (B), close
- Tabs become: [A, C, D] but we already processed indices 3 and 4
- Index 1 (A), process correctly

### Close Tabs in Specific Window

```applescript
tell application "iTerm2"
    if not running then
        return "ITERM_NOT_RUNNING"
    end if
    set windowCount to count of windows
    if windowCount < 2 then
        return "WINDOW_NOT_FOUND"
    end if
    set closedCount to 0
    tell window 2
        repeat with t from (count of tabs) to 1 by -1
            tell tab t
                try
                    if name of current session contains "pattern" then
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
end tell
```

---

## Split Pane Operations

### Splitting a Session

Split the current session to create a new pane within the same tab.

**Split vertically (creates pane on right):**

```applescript
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

**Split horizontally (creates pane below):**

```applescript
tell application "iTerm2"
    activate
    if (count of windows) is 0 then
        return "NO_WINDOWS"
    end if
    tell current session of current tab of first window
        split horizontally with profile "Devcontainer"
    end tell
end tell
```

**Notes:**

- Splitting creates a new session within the existing tab
- Profile name must match an existing iTerm2 profile exactly (case-sensitive)
- "Vertically" creates side-by-side panes (left/right split)
- "Horizontally" creates stacked panes (top/bottom split)
- Uses `first window` (frontmost) rather than `current window` for multi-window safety
- Requires at least one existing window (the script checks for `NO_WINDOWS`)

### Enumerating Sessions Within Tabs

List all sessions (panes) across windows and tabs using a triple-nested loop.

**Pattern:**

```applescript
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
```

**Session Properties:**

- `name of session s` - Session title/name (string)
- Session index within tab is 1-based (first session is `session 1`)
- The `try...on error` block handles sessions in transient states

**Output Format:**

The `iterm-list-panes.sh` script uses ASCII unit separator (character 31) as the field delimiter and line feed (character 10) as the record separator:

```
window_index<US>tab_index<US>session_index<US>session_name<LF>
```

This ensures safe parsing even when session names contain spaces, quotes, or other special characters.

### Closing Individual Sessions

Close specific sessions (panes) without closing the entire tab. Uses reverse iteration to prevent index shifting.

**Close sessions by pattern (single tab):**

```applescript
tell application "iTerm2"
    tell window 1
        tell tab 1
            repeat with s from (count of sessions) to 1 by -1
                try
                    if name of session s contains "pattern" then
                        tell session s to close
                    end if
                on error
                    -- Skip sessions that can't be accessed
                end try
            end repeat
        end tell
    end tell
end tell
```

**Close sessions by pattern (all windows and tabs):**

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
                            if name of session s contains "pattern" then
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

**Important:**

- Closing the last session in a tab will close the tab; closing the last tab in a window will close the window
- Always use reverse iteration (`to 1 by -1`) when closing multiple sessions to prevent index shifting (same principle as [closing tabs](#why-reverse-iteration-is-critical))
- Session indices are 1-based (first session is `session 1`, not `session 0`)
- The close command uses `tell session s to close` syntax rather than `close session s`
- Pattern matching is substring-based (`contains`), not regex

### Split and Configure Pattern

Split a session, then configure the new pane in a separate step.

**Two-step approach (from `iterm-split-pane.sh`):**

```applescript
tell application "iTerm2"
    activate
    if (count of windows) is 0 then
        return "NO_WINDOWS"
    end if
    -- Step 1: Split the current session
    tell current session of current tab of first window
        split vertically with profile "Devcontainer"
    end tell
    -- Step 2: Configure the new session (now the current session)
    tell current session of current tab of first window
        set name to "Test Runner"
        write text "npm test"
    end tell
end tell
```

**Why two steps:**

- After a split, the newly created session becomes the `current session` of the tab
- The split command itself does not return a reference to the new session
- A second `tell current session` block targets the newly created pane
- `set name` assigns the session title; `write text` executes a command in the new pane
- Both steps use `first window` for consistent window targeting

---

## Base64 Encoding Technique

### The Problem

When executing AppleScript from a container via SSH, the script must pass through multiple shell interpretation layers. This causes severe escaping issues:

```bash
# PROBLEMATIC: Multiple escape layers
ssh user@host "osascript -e \"tell application \\\"iTerm2\\\" to create window\""
```

Problems include:
- Nested quotes require multiple escape levels
- Newlines in scripts break command parsing
- Special characters (`$`, backticks, etc.) get interpreted
- Scripts become unreadable and error-prone

### The Solution

Base64 encode the entire AppleScript to make it transport-safe:

```bash
# Encode AppleScript to safely pass through SSH
applescript='tell application "iTerm2"
    activate
    tell first window
        create tab with profile "Devcontainer"
    end tell
end tell'

# Base64 encode (with -w0 for no line wrapping on Linux)
encoded=$(printf '%s' "$applescript" | base64 -w0 2>/dev/null || printf '%s' "$applescript" | base64)

# Execute on remote host
ssh "user@host.docker.internal" "printf '%s' '$encoded' | base64 -d | osascript"
```

### Implementation from iterm-utils.sh

The plugin uses a more robust approach with temporary files:

```bash
# Create temp file on remote host
temp_script=$(ssh -o BatchMode=yes -o ConnectTimeout=5 \
    "${host_user}@host.docker.internal" \
    "mktemp /tmp/iterm-XXXXXX.scpt" 2>/dev/null)

# Decode script to temp file, execute, then clean up
ssh -o BatchMode=yes -o ConnectTimeout=10 \
    "${host_user}@host.docker.internal" \
    "printf '%s' '$encoded' | base64 -d > '$temp_script' && osascript '$temp_script'"

# Clean up temp file
ssh -o BatchMode=yes -o ConnectTimeout=5 \
    "${host_user}@host.docker.internal" \
    "rm -f '$temp_script'" 2>/dev/null || true
```

### Benefits of Base64 Encoding

| Benefit | Description |
|---------|-------------|
| Quote Safety | No need to escape nested quotes |
| Multiline Support | Newlines are preserved without special handling |
| Special Characters | `$`, backticks, `!`, etc. are safely transported |
| Readability | Original script remains human-readable |
| Reliability | Eliminates entire class of escaping bugs |

### Cross-Platform Considerations

macOS and Linux `base64` commands have different options:

```bash
# Linux uses -w0 for no wrapping
encoded=$(echo "$script" | base64 -w0)

# macOS doesn't need -w0 (doesn't wrap by default)
encoded=$(echo "$script" | base64)

# Compatible version (try Linux first, fall back to macOS)
encoded=$(printf '%s' "$script" | base64 -w0 2>/dev/null || printf '%s' "$script" | base64)
```

---

## Error Handling

### AppleScript Try-Catch

AppleScript uses `try...on error...end try` for exception handling:

```applescript
tell application "iTerm2"
    try
        tell current window
            create tab with profile "NonExistentProfile"
        end tell
    on error errMsg number errNum
        log "Error " & errNum & ": " & errMsg
        return "ERROR: " & errMsg
    end try
end tell
```

### Handling Missing Windows

```applescript
tell application "iTerm2"
    if (count of windows) is 0 then
        -- Create a new window if none exist
        create window with default profile
    end if
    tell first window
        create tab with default profile
    end tell
end tell
```

### Safe Session Property Access

When iterating tabs, some sessions may be in transient states:

```applescript
tell application "iTerm2"
    repeat with w from 1 to (count of windows)
        tell window w
            repeat with t from 1 to (count of tabs)
                tell tab t
                    try
                        set sessionName to name of current session
                    on error
                        set sessionName to "(unavailable)"
                    end try
                end tell
            end repeat
        end tell
    end repeat
end tell
```

### Shell-Level Error Handling

Wrap `osascript` calls in conditionals for proper error detection:

```bash
# Check if iTerm2 is available
if ! osascript -e 'tell application "iTerm2" to activate'; then
    echo "Error: iTerm2 not available" >&2
    exit 2
fi

# Execute and capture result
result=$(osascript -e "$applescript" 2>&1)
exit_code=$?

if [ $exit_code -ne 0 ]; then
    echo "AppleScript failed: $result" >&2
    exit 1
fi
```

---

## Advanced Techniques

### Window Management

**Set window bounds:**

```applescript
tell application "iTerm2"
    tell current window
        set bounds to {100, 100, 900, 700}  -- {left, top, right, bottom}
    end tell
end tell
```

**Get window bounds:**

```applescript
tell application "iTerm2"
    tell current window
        return bounds
    end tell
end tell
```

**Bring window to front:**

```applescript
tell application "iTerm2"
    activate
    tell current window
        select
    end tell
end tell
```

### Session Properties

**Set session colors:**

```applescript
tell application "iTerm2"
    tell current session of current tab of current window
        set background color to {0, 0, 0}           -- Black
        set foreground color to {65535, 65535, 65535}  -- White
    end tell
end tell
```

**Note**: Colors use RGB values from 0-65535 (16-bit), not 0-255.

**Get session state:**

```applescript
tell application "iTerm2"
    tell current session of current tab of current window
        set sessionName to name
        set sessionTTY to tty
        set isProcessing to is processing
        set sessionText to contents  -- Get terminal buffer contents
    end tell
end tell
```

### Select-Tab Pattern

While `create tab` automatically selects the new tab, you can explicitly select tabs:

```applescript
tell application "iTerm2"
    tell first window
        -- After creating a tab, it becomes "current tab"
        create tab with profile "Devcontainer"
        tell current session of current tab
            set name to "New Tab"
        end tell
    end tell
end tell
```

---

## Escaping and Quoting

### The Challenge

AppleScript uses double quotes for strings, which conflicts with shell quoting:

```applescript
tell application "iTerm2" to activate
```

When embedded in shell, this becomes problematic:

```bash
# Quotes conflict - this fails
osascript -e "tell application "iTerm2" to activate"
```

### Solution 1: Single Quotes (Simple Scripts)

For simple scripts without shell variables:

```bash
# Good: Use single quotes to contain AppleScript double quotes
osascript -e 'tell application "iTerm2" to activate'
```

### Solution 2: Escaped Quotes

When mixing shell variables:

```bash
profile="Devcontainer"
osascript -e "tell application \"iTerm2\"
    tell first window
        create tab with profile \"$profile\"
    end tell
end tell"
```

### Solution 3: Heredoc (Complex Scripts)

For multiline scripts:

```bash
osascript <<'EOF'
tell application "iTerm2"
    activate
    tell first window
        create tab with default profile
    end tell
end tell
EOF
```

**Note**: Using `<<'EOF'` (quoted) prevents shell variable expansion. Use `<<EOF` (unquoted) if you need variables:

```bash
profile="Devcontainer"
osascript <<EOF
tell application "iTerm2"
    tell first window
        create tab with profile "$profile"
    end tell
end tell
EOF
```

### Solution 4: AppleScript String Escaping Function

The plugin uses a bash function to escape strings for AppleScript:

```bash
escape_applescript_string() {
    local input="$1"
    # Escape backslashes first, then double quotes
    local escaped
    escaped="${input//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    printf '%s' "$escaped"
}

# Usage
profile="My \"Special\" Profile"
escaped_profile=$(escape_applescript_string "$profile")
# Result: My \"Special\" Profile
```

### Paths with Spaces

The plugin handles paths with spaces using nested escaping:

```bash
directory="/workspace/My Project"
escaped_directory=$(escape_applescript_string "$directory")

# The \\\" produces \" in the final AppleScript
shell_command="cd \\\"$escaped_directory\\\""
# In AppleScript, this becomes: cd "/workspace/My Project"
```

---

## Troubleshooting

### Common Issues and Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| "Application isn't running" | iTerm2 not launched | Add `activate` command or ensure iTerm2 is running |
| "Can't get current window" | No windows open | Check window count first, create if needed |
| "Profile not found" | Profile name doesn't match exactly | Use exact case-sensitive profile name from iTerm2 Preferences |
| "Syntax error in AppleScript" | Unbalanced quotes, missing `end tell` | Test AppleScript separately before embedding |
| "Connection refused" (container mode) | SSH not configured | Verify SSH keys and host.docker.internal connectivity |
| "HOST_USER not set" | Missing environment variable | Set in devcontainer.json `remoteEnv` |
| Tabs skipped during close | Forward iteration used | Always iterate in reverse when closing tabs |

### Debugging AppleScript

**Test script standalone:**

```bash
# Save to file
cat > /tmp/test.scpt << 'EOF'
tell application "iTerm2"
    activate
    tell first window
        create tab with default profile
    end tell
end tell
EOF

# Execute with error details
osascript /tmp/test.scpt
```

**Get verbose errors:**

```bash
osascript -e 'tell application "iTerm2"
    -- Your script here
end tell' 2>&1
```

**Check AppleScript syntax:**

```bash
# This will report syntax errors without executing
osacompile -o /dev/null <<'EOF'
tell application "iTerm2"
    -- Your script here
end tell
EOF
```

### Container Mode Issues

**Test SSH connectivity:**

```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 \
    "${HOST_USER}@host.docker.internal" "echo 'SSH works'"
```

**Test remote osascript:**

```bash
ssh "${HOST_USER}@host.docker.internal" \
    "osascript -e 'tell application \"iTerm2\" to activate'"
```

**Verify HOST_USER:**

```bash
echo "HOST_USER is: '${HOST_USER:-NOT SET}'"
```

---

## Testing AppleScript

### Interactive Testing

Test scripts directly from the command line:

```bash
# Simple test
osascript -e 'tell application "iTerm2" to activate'

# Multiline test
osascript <<'EOF'
tell application "iTerm2"
    activate
    tell first window
        create tab with default profile
    end tell
end tell
EOF
```

### Dry-Run Pattern

The plugin scripts support `--dry-run` to preview AppleScript:

```bash
# Show what would be executed
iterm-open-tab.sh --dry-run -d /workspace -n "Test Tab"
```

Implement this pattern in custom scripts:

```bash
DRY_RUN=false

# Parse args...
if [ "$DRY_RUN" = true ]; then
    echo "Would execute:"
    echo "$applescript"
    exit 0
fi

osascript -e "$applescript"
```

### Capturing AppleScript Return Values

AppleScript `return` values come through stdout:

```bash
result=$(osascript <<'EOF'
tell application "iTerm2"
    return count of windows
end tell
EOF
)
echo "iTerm2 has $result windows"
```

---

## Performance Considerations

### Timing Expectations

| Operation | Typical Time |
|-----------|-------------|
| AppleScript activation | ~50-100ms |
| Create tab | ~100-200ms |
| Query tabs | ~100-200ms + ~10ms per tab |
| SSH overhead (container mode) | +300-500ms |
| Base64 encode/decode | <10ms |

### Optimization Tips

1. **Batch Operations**: Combine multiple operations in single AppleScript when possible
2. **Avoid Repeated Queries**: Cache window/tab counts if needed multiple times
3. **Use First Window**: `first window` is faster than iterating to find "current window"
4. **Minimize SSH Calls**: In container mode, do as much as possible per SSH connection

### Recommended Delays

When performing rapid sequential operations:

```bash
# Small delay between rapid tab operations prevents race conditions
osascript -e "$create_tab_script"
sleep 0.2
osascript -e "$configure_tab_script"
```

---

## Version Compatibility

### Tested Versions

| Component | Version | Status |
|-----------|---------|--------|
| iTerm2 | 3.4.x, 3.5.x | Fully Tested |
| macOS | 12 (Monterey), 13 (Ventura), 14 (Sonoma), 15 (Sequoia) | Compatible |
| osascript | (bundled with macOS) | Compatible |

### API Stability

iTerm2's AppleScript API has been stable for several major versions. Key API elements used in this plugin:

- `create tab with profile` - Stable since iTerm2 3.0
- `create window with profile` - Stable since iTerm2 3.0
- `name of session` - Stable since iTerm2 2.x
- `write text` - Stable since iTerm2 2.x
- `close session` - Stable since iTerm2 2.x

### Breaking Changes

Known breaking changes to watch for in future versions:

- None documented as of iTerm2 3.5.x
- Monitor [iTerm2 release notes](https://iterm2.com/downloads.html) for announcements

---

## Official Documentation Links

### iTerm2 Documentation

- **[iTerm2 AppleScript Documentation](https://iterm2.com/documentation-scripting.html)** - Official scripting reference
- **[iTerm2 Python API](https://iterm2.com/python-api/)** - Alternative to AppleScript for complex automation
- **[iTerm2 Profiles](https://iterm2.com/documentation-preferences-profiles.html)** - Profile configuration reference

### Apple Documentation

- **[AppleScript Language Guide](https://developer.apple.com/library/archive/documentation/AppleScript/Conceptual/AppleScriptLangGuide/introduction/ASLR_intro.html)** - Complete language reference
- **[osascript Man Page](https://ss64.com/mac/osascript.html)** - Command-line AppleScript execution
- **[AppleScript Release Notes](https://developer.apple.com/library/archive/releasenotes/AppleScript/RN-AppleScript/Introduction/Introduction.html)** - Historical changes

### Related Tools

- **[Automator](https://support.apple.com/guide/automator/welcome/mac)** - Visual automation tool (can wrap AppleScript)
- **[Script Editor](https://support.apple.com/guide/script-editor/welcome/mac)** - macOS IDE for AppleScript development

---

## Quick Reference

### Common Patterns Cheat Sheet

```applescript
-- Activate iTerm2
tell application "iTerm2" to activate

-- Create tab with profile
tell application "iTerm2"
    tell first window
        create tab with profile "ProfileName"
    end tell
end tell

-- Set tab name
tell application "iTerm2"
    tell current session of current tab of first window
        set name to "TabName"
    end tell
end tell

-- Execute command
tell application "iTerm2"
    tell current session of current tab of first window
        write text "your command here"
    end tell
end tell

-- Query all tabs (with safe delimiter)
tell application "iTerm2"
    repeat with w from 1 to (count of windows)
        tell window w
            repeat with t from 1 to (count of tabs)
                tell tab t
                    log (name of current session)
                end tell
            end repeat
        end tell
    end repeat
end tell

-- Close matching tabs (reverse iteration!)
tell application "iTerm2"
    repeat with w from (count of windows) to 1 by -1
        tell window w
            repeat with t from (count of tabs) to 1 by -1
                tell tab t
                    if name of current session contains "pattern" then
                        close current session
                    end if
                end tell
            end repeat
        end tell
    end repeat
end tell
```

### ASCII Delimiter Reference

The plugin uses ASCII control characters as safe delimiters:

| Character | Code | AppleScript | Use Case |
|-----------|------|-------------|----------|
| Unit Separator | 31 | `(ASCII character 31)` | Field delimiter (won't appear in tab names) |
| Line Feed | 10 | `(ASCII character 10)` | Record delimiter |

---

## Change Log

| Date | Version | Changes |
|------|---------|---------|
| 2025-01-15 | 1.0.0 | Initial documentation created |
| 2026-02-10 | 1.1.0 | Added Split Pane Operations section documenting pane management AppleScript patterns: splitting sessions (vertical/horizontal), enumerating sessions within tabs, closing individual sessions, and split-and-configure pattern. Supports PANE-005 ticket for comprehensive pane-management SKILL.md documentation. |
