---
name: build-claude-cmd-escape-modes
description: Shared command builder with transport-specific escaping for Claude CLI commands in iTerm spawning scripts
origin: PANE-004
created: 2026-02-09
tags: [shell-scripting, escaping, applescript, ssh, claude-cli]
---

# Claude Command Builder with Escape Modes

## Overview

This skill covers the pattern for building Claude CLI commands with transport-specific escaping. When spawning Claude agents in iTerm2 from a container environment, task descriptions must be escaped differently depending on the transport mechanism: double-quote escaping for SSH (remote/container mode) and single-quote escaping for osascript (local/host mode).

The `build_claude_cmd()` shared function consolidates this logic, ensuring correct escaping for both transport modes while eliminating duplication across wrapper and fallback functions.

## When to Use

Use this pattern when:
- Constructing Claude CLI commands that will be passed to iTerm spawning scripts
- Building commands that embed user-provided task descriptions in AppleScript
- Creating new iTerm automation scripts that spawn Claude agents
- Refactoring scripts to eliminate duplicated command construction logic

## Pattern/Procedure

### Shared Command Builder Function

Create a single `build_claude_cmd()` function that accepts an escape mode parameter:

```bash
build_claude_cmd() {
    local worktree_path="$1"
    local task="$2"
    local escape_mode="${3:-double}"  # "double" or "single"

    local escaped_task=""
    if [[ -n "$task" ]]; then
        if [[ "$escape_mode" == "double" ]]; then
            # Remote/SSH: Escape double quotes
            escaped_task="${task//\"/\\\"}"
        else
            # Local/osascript: Escape single quotes (AppleScript string literals)
            escaped_task="${task//\'/\'\\\'\'}"
        fi
    fi

    # Build command with or without task
    if [[ -n "$task" ]]; then
        echo "cd \"$worktree_path\" && echo \"$escaped_task\" | claude --dangerously-skip-permissions"
    else
        echo "cd \"$worktree_path\" && claude --dangerously-skip-permissions"
    fi
}
```

### When to Use Each Escape Mode

**Double-quote escaping (`escape_mode="double"`):**
- Use for **remote/container contexts** where command is sent via SSH
- SSH commands embed the command in double quotes
- Pattern: `${task//\"/\\\"}`
- Example: Task `Say "hello"` becomes `Say \"hello\"`

**Single-quote escaping (`escape_mode="single"`):**
- Use for **local/host contexts** where command is passed to osascript directly
- AppleScript string literals use single quotes
- Pattern: `${task//\'/\'\\\'\'}`
- Example: Task `Don't stop` becomes `Don'\'t stop`

### Calling the Builder from Wrapper Functions

Plugin delegation uses the builder without needing to specify escape mode (plugins handle escaping internally):

```bash
spawn_agent_tab() {
    local worktree_path="$1"
    local task="$2"

    # Build command with default double-quote escaping
    local claude_cmd
    claude_cmd=$(build_claude_cmd "$worktree_path" "$task" "double")

    # Delegate to plugin (plugin handles its own escaping)
    if [[ -x "$ITERM_OPEN_TAB_SCRIPT" ]]; then
        "$ITERM_OPEN_TAB_SCRIPT" -p "$PROFILE" -n "$session_name" -c "$claude_cmd"
        return $?
    fi

    # Fallback handles its own escaping needs
    # ...
}
```

### Calling the Builder from Fallback Functions

Fallback functions specify the escape mode based on their transport:

```bash
spawn_agent_remote_original() {
    local worktree_path="$1"
    local task="$2"

    # Use double-quote escaping for SSH transport
    local claude_cmd
    claude_cmd=$(build_claude_cmd "$worktree_path" "$task" "double")

    # Build AppleScript with escaped command
    local applescript="..."
    echo "$applescript" | base64 | ssh ... "base64 -d | osascript"
}

spawn_agent_local_original() {
    local worktree_path="$1"
    local task="$2"

    # Use single-quote escaping for osascript
    local claude_cmd
    claude_cmd=$(build_claude_cmd "$worktree_path" "$task" "single")

    # Execute AppleScript with escaped command
    osascript -e "..."
}
```

### Claude CLI Flags

The command builder includes repo-standard Claude CLI flags:

- `--dangerously-skip-permissions`: Required for running Claude in devcontainer without permission prompts
- Working directory: Always `cd` to the specified worktree path first
- Task input: Piped via `echo` if task is provided, otherwise interactive mode

## Examples

### Complete Implementation

From `/workspace/.devcontainer/scripts/spawn-agent.sh`:

```bash
##############################################################################
# Shared Command Builder
##############################################################################
build_claude_cmd() {
    local worktree_path="$1"
    local task="$2"
    local escape_mode="${3:-double}"

    local escaped_task=""
    if [[ -n "$task" ]]; then
        if [[ "$escape_mode" == "double" ]]; then
            escaped_task="${task//\"/\\\"}"
        else
            escaped_task="${task//\'/\'\\\'\'}"
        fi
    fi

    if [[ -n "$task" ]]; then
        echo "cd \"$worktree_path\" && echo \"$escaped_task\" | claude --dangerously-skip-permissions"
    else
        echo "cd \"$worktree_path\" && claude --dangerously-skip-permissions"
    fi
}
```

### Example Invocations

**No task (interactive mode):**
```bash
claude_cmd=$(build_claude_cmd "/workspace/repos/project" "" "double")
# Result: cd "/workspace/repos/project" && claude --dangerously-skip-permissions
```

**With task, double-quote escaping:**
```bash
claude_cmd=$(build_claude_cmd "/workspace/repos/project" 'Fix "auth" bug' "double")
# Result: cd "/workspace/repos/project" && echo "Fix \"auth\" bug" | claude --dangerously-skip-permissions
```

**With task, single-quote escaping:**
```bash
claude_cmd=$(build_claude_cmd "/workspace/repos/project" "Don't break" "single")
# Result: cd "/workspace/repos/project" && echo "Don'\'t break" | claude --dangerously-skip-permissions
```

### Usage in Remote Fallback (SSH Transport)

```bash
spawn_agent_pane_remote_original() {
    local worktree_path="$1"
    local task="$2"
    local profile="$3"
    local direction="$4"

    # Build command with double-quote escaping for SSH
    local claude_cmd
    claude_cmd=$(build_claude_cmd "$worktree_path" "$task" "double")

    local session_name="${task:-Claude Agent}"
    local split_direction="vertically"
    [[ "$direction" == "horizontal" ]] && split_direction="horizontally"

    # Build AppleScript
    local applescript=$(cat <<EOF
tell application "iTerm"
    tell current session of current window
        set newSession to (split ${split_direction} with profile "${profile}")
        tell newSession
            write text "${claude_cmd}"
            set name to "${session_name}"
        end tell
    end tell
end tell
EOF
)

    # Send via SSH with base64 encoding
    echo "$applescript" | base64 | ssh "${HOST_USER}@host.docker.internal" "base64 -d | osascript"
}
```

### Usage in Local Fallback (osascript Transport)

```bash
spawn_agent_local_original() {
    local worktree_path="$1"
    local task="$2"

    # Build command with single-quote escaping for osascript
    local claude_cmd
    claude_cmd=$(build_claude_cmd "$worktree_path" "$task" "single")

    local session_name="${task:-Claude Agent}"

    # Execute AppleScript directly
    osascript -e "
    tell application \"iTerm\"
        tell current window
            create tab with profile \"${PROFILE}\"
            tell current session
                write text '${claude_cmd}'
                set name to '${session_name}'
            end tell
        end tell
    end tell
    "
}
```

## References

- Ticket: PANE-004
- Related files:
  - `/workspace/.devcontainer/scripts/spawn-agent.sh` (lines 103-118, function implementation)
  - `/workspace/_SPECS/claude-code-plugins/tickets/PANE-004_agent-pane-spawn/tasks/PANE-004.1002_shared-command-builder.md`
  - `/workspace/_SPECS/claude-code-plugins/tickets/PANE-004_agent-pane-spawn/planning/architecture.md` (Component 2: Shared Claude Command Builder)
