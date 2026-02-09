---
name: wrapper-with-fallback-pattern
description: Plugin delegation with graceful fallback to original implementation when plugin unavailable or fails
origin: PANE-004
created: 2026-02-09
tags: [architecture, patterns, iterm, plugin-system, fallback]
---

# Wrapper-with-Fallback Pattern

## Overview

This skill covers the architectural pattern used in iTerm automation scripts where scripts try a plugin implementation first, then fall back to an original implementation if the plugin is unavailable or fails. This provides graceful degradation and allows scripts to work in environments where the plugin system is not fully configured.

The pattern is used consistently across spawn-agent.sh for both tab spawning and pane spawning, and should be followed for any future iTerm automation scripts in this repo.

## When to Use

Use this pattern when:
- Creating new iTerm automation scripts that should work with or without the plugin system
- Extending existing iTerm automation scripts with new functionality
- Implementing features that delegate to plugin scripts but need standalone capability
- Building devcontainer scripts that interact with iTerm2 on the host

## Pattern/Procedure

### Component Structure

The wrapper-with-fallback pattern consists of three components:

1. **Original Implementation Functions**: Functions suffixed with `_original` that contain direct AppleScript logic, not dependent on any plugins
2. **Wrapper Function**: A function that attempts plugin delegation and falls back to original implementation
3. **Plugin Path Configuration**: Variables that point to plugin scripts, configurable via environment variables

### Original Implementation Functions

Create separate `_remote_original` and `_local_original` functions for container and host contexts:

```bash
##############################################################################
# Original Implementation - Remote (Container Mode)
##############################################################################
function_name_remote_original() {
    local param1="$1"
    local param2="$2"
    # ... additional parameters

    # Build AppleScript
    local applescript="..."

    # Execute via SSH with base64 encoding
    echo "$applescript" | base64 | ssh "${HOST_USER}@host.docker.internal" \
        "base64 -d | osascript"
}

##############################################################################
# Original Implementation - Local (Host Mode)
##############################################################################
function_name_local_original() {
    local param1="$1"
    local param2="$2"
    # ... additional parameters

    # Build AppleScript
    local applescript="..."

    # Execute directly
    osascript -e "$applescript"
}
```

### Wrapper Function with Delegation

The wrapper function checks for plugin availability and delegates, with fallback on failure:

```bash
##############################################################################
# Wrapper - Try Plugin, Fall Back to Original
##############################################################################
function_name() {
    local param1="$1"
    local param2="$2"
    # ... additional parameters

    # Check if plugin script is available and executable
    if [[ -x "$PLUGIN_SCRIPT_PATH" ]]; then
        info "Attempting plugin delegation..."

        # Try plugin with appropriate flags
        if "$PLUGIN_SCRIPT_PATH" -flag1 "$param1" -flag2 "$param2"; then
            ok "Plugin delegation succeeded"
            return 0
        else
            warn "Plugin failed (exit code $?), falling back to original implementation"
        fi
    else
        warn "Plugin not available at $PLUGIN_SCRIPT_PATH, using original implementation"
    fi

    # Fallback: determine context and call appropriate original function
    if is_container; then
        function_name_remote_original "$param1" "$param2"
    else
        function_name_local_original "$param1" "$param2"
    fi
}
```

### Plugin Path Configuration

Define plugin paths as variables, derived from a configurable base directory:

```bash
# iTerm Plugin path - configurable via PLUGIN_ROOT for testing
ITERM_PLUGIN_DIR="${PLUGIN_ROOT:-/workspace/repos/claude-code-plugins/ITERM}/plugins/iterm"
PLUGIN_SCRIPT_PATH="$ITERM_PLUGIN_DIR/skills/{skill-name}/scripts/{script-name}.sh"
```

This allows:
- Production use: Uses default path in `/workspace/repos/`
- Testing: Override `PLUGIN_ROOT` to point to test fixtures
- Debugging: Explicit path visibility in error messages

### Context Detection

Use the `is_container()` helper to determine whether to use remote (SSH) or local (direct) original implementation:

```bash
is_container() {
    [[ "$(uname)" != "Darwin" ]] || [[ -f /.dockerenv ]] || grep -q docker /proc/1/cgroup 2>/dev/null
}
```

## Examples

### Complete Example: spawn_agent_tab()

From `/workspace/.devcontainer/scripts/spawn-agent.sh`:

```bash
##############################################################################
# Wrapper - Tab Mode
##############################################################################
spawn_agent_tab() {
    local worktree_path="$1"
    local task="$2"

    # Build command and session name
    local claude_cmd
    claude_cmd=$(build_claude_cmd "$worktree_path" "$task" "double")
    local session_name="${task:-Claude Agent}"

    # Try plugin first
    if [[ -x "$ITERM_OPEN_TAB_SCRIPT" ]]; then
        info "Attempting plugin delegation for tab spawning..."

        if "$ITERM_OPEN_TAB_SCRIPT" -p "$PROFILE" -n "$session_name" -c "$claude_cmd"; then
            ok "Plugin delegation succeeded for tab spawning"
            return 0
        else
            warn "Plugin failed (exit $?), falling back to original tab implementation"
        fi
    else
        warn "Plugin not available at $ITERM_OPEN_TAB_SCRIPT, using original implementation"
    fi

    # Fallback to original
    if is_container; then
        spawn_agent_remote_original "$worktree_path" "$task"
    else
        spawn_agent_local_original "$worktree_path" "$task"
    fi
}
```

### Plugin Path Variables

```bash
# Configuration section (near top of script)
ITERM_PLUGIN_DIR="${PLUGIN_ROOT:-/workspace/repos/claude-code-plugins/ITERM}/plugins/iterm"
ITERM_OPEN_TAB_SCRIPT="$ITERM_PLUGIN_DIR/skills/tab-management/scripts/iterm-open-tab.sh"
ITERM_SPLIT_PANE_SCRIPT="$ITERM_PLUGIN_DIR/skills/pane-management/scripts/iterm-split-pane.sh"
```

### Parallel Pattern for Pane Mode

```bash
##############################################################################
# Wrapper - Pane Mode
##############################################################################
spawn_agent_pane() {
    local worktree_path="$1"
    local task="$2"
    local profile="$3"
    local direction="$4"

    # Build command and session name
    local claude_cmd
    claude_cmd=$(build_claude_cmd "$worktree_path" "$task" "double")
    local pane_name="${task:-Claude Agent}"

    # Try plugin first
    if [[ -x "$ITERM_SPLIT_PANE_SCRIPT" ]]; then
        info "Attempting plugin delegation for pane spawning..."

        if "$ITERM_SPLIT_PANE_SCRIPT" -d "$direction" -p "$profile" -n "$pane_name" -c "$claude_cmd"; then
            ok "Plugin delegation succeeded for pane spawning"
            return 0
        else
            warn "Plugin failed (exit $?), falling back to original pane implementation"
        fi
    else
        warn "Plugin not available at $ITERM_SPLIT_PANE_SCRIPT, using original implementation"
    fi

    # Fallback to original
    if is_container; then
        spawn_agent_pane_remote_original "$worktree_path" "$task" "$profile" "$direction"
    else
        spawn_agent_pane_local_original "$worktree_path" "$task" "$profile" "$direction"
    fi
}
```

## References

- Ticket: PANE-004
- Related files:
  - `/workspace/.devcontainer/scripts/spawn-agent.sh` (complete implementation with tab and pane wrappers)
  - `plugins/iterm/skills/tab-management/scripts/iterm-open-tab.sh` (plugin that wrappers delegate to)
  - `plugins/iterm/skills/pane-management/scripts/iterm-split-pane.sh` (plugin that wrappers delegate to)
  - `/workspace/_SPECS/claude-code-plugins/tickets/PANE-004_agent-pane-spawn/planning/architecture.md` (Design Decision 2: Single Wrapper Function with Mode Dispatch)
