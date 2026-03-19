---
name: terminal-management
description: cmux terminal management for macOS host via SSH from devcontainers.
---

# Terminal Management Skill

**Last Updated:** 2026-03-19
**Plugin:** cmux
**Scripts Location:** `plugins/cmux/skills/terminal-management/scripts/`

## Overview

The terminal-management skill enables Claude Code to control cmux terminals on a macOS host. From a devcontainer, all cmux operations are executed via SSH to the macOS host -- this is the standard operating model, not a workaround. The `cmux-ssh.sh` wrapper script handles SSH connection details, input validation, and argument escaping automatically. The workspace is the primary operational unit -- each workspace appears as a vertical tab in the cmux sidebar and contains one or more panes and surfaces.

## Execution Model

From a devcontainer, all cmux commands MUST be executed via SSH to the macOS host using `cmux-ssh.sh`. Direct cmux CLI invocation does not work from containers.

### Devcontainer Context (PRIMARY)

When running inside a devcontainer (the typical case), use the `cmux-ssh.sh` wrapper script at its absolute path:

```bash
$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh <cmux-subcommand> [args...]
```

The `$CMUX_PLUGIN_DIR` variable points to the cmux plugin root directory. The wrapper handles:
- SSH connection to the macOS host via `host.docker.internal`
- Full binary path resolution (`/Applications/cmux.app/Contents/Resources/bin/cmux`)
- Input validation (rejects newlines and null bytes)
- Argument escaping for safe SSH transport

All examples in this document assume devcontainer context unless stated otherwise.

### Host Context (FALLBACK)

When running directly on the macOS host (not in a devcontainer), you can invoke the cmux CLI directly without SSH:

```bash
/Applications/cmux.app/Contents/Resources/bin/cmux <subcommand> [args...]
```

This context applies only when:
- You are running in a terminal on the macOS host itself (not inside a container or SSH session)
- The cmux application is running
- `socketControlMode` is set to `allowAll`

Host-context invocation is a fallback. The primary workflow documented throughout this skill assumes devcontainer context with SSH.

### Why SSH is Required

Two distinct issues affect cmux CLI usage from devcontainers. They are independent and require separate fixes:

1. **"Access denied" error** -- caused by socketControlMode not being set to `allowAll`. By default, cmux's socket mode blocks connections from processes that did not originate inside cmux. Setting `socketControlMode` to `allowAll` resolves this error, allowing the macOS host's SSH daemon to connect to the cmux socket:
   ```bash
   defaults write com.cmuxterm.app socketControlMode -string allowAll
   ```

2. **Issue #373 (separate limitation)** -- the cmux CLI does not work when invoked from SSH remote sessions, even with socketControlMode correctly configured. The CLI was designed to be called from processes running directly on the host, not from within remote sessions. This is an upstream limitation unrelated to socket permissions.

This plugin's SSH-to-host pattern resolves both issues together. By SSHing from the devcontainer to the macOS host and executing the cmux binary there, the CLI runs directly on the host (satisfying Issue #373), and with socketControlMode set to `allowAll`, the SSH session is permitted to connect to the cmux socket (resolving the "Access denied" error). This SSH-wrapping pattern is the foundation of all cmux operations in this plugin and is encapsulated by the `$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh` helper script.

## Prerequisites

All prerequisites must be satisfied in this order. Run `cmux-check.sh` to validate all five automatically.

1. **socketControlMode set to `allowAll`** -- cmux's default socket mode blocks connections from SSH sessions, causing "Access denied" errors. This is the most common setup failure. Fix:
   ```bash
   defaults write com.cmuxterm.app socketControlMode -string allowAll
   ```
   Alternatively, set it in cmux Settings UI. This must be done on the macOS host directly.

2. **HOST_USER environment variable** -- your macOS username, set in `devcontainer.json`:
   ```json
   {
     "remoteEnv": {
       "HOST_USER": "your-macos-username"
     }
   }
   ```

3. **SSH connectivity to host.docker.internal** -- the container must be able to reach the macOS host via SSH:
   ```bash
   ssh -o BatchMode=yes -o ConnectTimeout=5 ${HOST_USER}@host.docker.internal "echo OK"
   ```

4. **cmux installed** at `/Applications/cmux.app/Contents/Resources/bin/cmux` -- the binary is not in PATH for SSH sessions, so the full path is always required.

5. **cmux running on macOS host** -- the cmux application must be open. Verify with:
   ```bash
   ssh -o BatchMode=yes -o ConnectTimeout=5 ${HOST_USER}@host.docker.internal \
     "/Applications/cmux.app/Contents/Resources/bin/cmux ping"
   ```
   Expected response: `PONG`

Run `cmux-check.sh` from the plugin scripts directory to validate all prerequisites at once. Use `cmux-check.sh --quiet` for exit-code-only checking (exit 0 = all pass, exit 1 = failure).

## cmux Hierarchy

cmux organizes terminals in a four-level hierarchy:

```
window > workspace > pane > surface
```

- **Window** -- the top-level cmux application window
- **Workspace** -- a vertical tab in the sidebar (identified as `workspace:N`); this is the primary unit for targeting commands
- **Pane** -- a subdivision within a workspace (created by splits)
- **Surface** -- the terminal surface within a pane (identified as `surface:N`)

Most commands target a workspace using `--workspace workspace:N`. Use `list-workspaces` to discover workspace IDs and `tree --all` to see the full hierarchy.

## Quick Start

Verify the plugin is working with these minimum steps:

```bash
CMUX="/Applications/cmux.app/Contents/Resources/bin/cmux"
SSH="ssh -o BatchMode=yes -o ConnectTimeout=5 ${HOST_USER}@host.docker.internal"

# 1. Health check
$SSH "$CMUX ping"
# Expected: PONG

# 2. List existing workspaces
$SSH "$CMUX list-workspaces"
# Expected: workspace:1 name [selected]

# 3. Create a new workspace
$SSH "$CMUX new-workspace"
# Expected: OK workspace:N
```

Or use the wrapper script (recommended):

```bash
CMUX_SSH="$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh"

$CMUX_SSH ping
$CMUX_SSH list-workspaces
$CMUX_SSH new-workspace
```

## Command Reference

All examples assume these variables are set:

```bash
CMUX="/Applications/cmux.app/Contents/Resources/bin/cmux"
SSH="ssh -o BatchMode=yes -o ConnectTimeout=5 ${HOST_USER}@host.docker.internal"
```

| Operation | SSH-wrapped invocation |
|-----------|----------------------|
| Health check / connectivity | `$SSH "$CMUX ping"` -- returns `PONG` |
| List workspaces | `$SSH "$CMUX list-workspaces"` -- returns `workspace:N name [selected]` |
| Show full hierarchy | `$SSH "$CMUX tree --all"` |
| Create workspace | `$SSH "$CMUX new-workspace"` -- returns `OK workspace:N` |
| Rename workspace | `$SSH "$CMUX rename-workspace --workspace workspace:N 'Name'"` |
| Type text (step 1 of 2) | `$SSH "$CMUX send --workspace workspace:N 'text'"` |
| Execute typed text (step 2 of 2) | `$SSH "$CMUX send-key --workspace workspace:N enter"` |
| Read screen content | `$SSH "$CMUX read-screen --workspace workspace:N --lines 20"` |
| Close workspace | `$SSH "$CMUX close-workspace --workspace workspace:N"` |
| Focus surface | `$SSH "$CMUX focus-surface --workspace workspace:N"` |
| List surfaces | `$SSH "$CMUX list-surfaces"` |
| Create split | `$SSH "$CMUX new-split [direction]"` |
| Show current context | `$SSH "$CMUX identify"` |
| CLI help | `$SSH "$CMUX --help"` |

When unsure about a specific cmux command or its flags, run `$SSH "$CMUX --help"` for the full CLI reference.

## Two-Step Send Pattern

The cmux `send` command types text into a workspace but does NOT execute it. To execute, you must follow with `send-key enter`. This two-step pattern prevents accidental command execution and allows verification before running.

```bash
CMUX="/Applications/cmux.app/Contents/Resources/bin/cmux"
SSH="ssh -o BatchMode=yes -o ConnectTimeout=5 ${HOST_USER}@host.docker.internal"

# Step 1: Type the command text (does NOT execute)
$SSH "$CMUX send --workspace workspace:1 'cd /workspace && ls'"
# Returns: OK surface:N workspace:N

# Step 2: Press Enter to execute
$SSH "$CMUX send-key --workspace workspace:1 enter"
# Returns: OK surface:N workspace:N

# Step 3: Verify output with read-screen
sleep 1  # allow command to complete
$SSH "$CMUX read-screen --workspace workspace:1 --lines 10"
```

Always include both steps when sending commands. Omitting `send-key enter` will leave the text typed but not executed.

## Using cmux-ssh.sh

The `$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh` wrapper script handles SSH connection details, input validation, and argument escaping automatically. It is the recommended way to run cmux commands from the devcontainer.

**Location:** `$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh`

**Usage:**

```bash
$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh [--dry-run] [-h|--help] <cmux-subcommand> [args...]
```

**Examples:**

```bash
CMUX_SSH="$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh"

# Run a cmux command
$CMUX_SSH ping
$CMUX_SSH list-workspaces
$CMUX_SSH send --workspace workspace:1 "hello world"

# Preview the SSH command without executing
$CMUX_SSH --dry-run send --workspace workspace:1 "it's a test"
# Output: ssh -o BatchMode=yes -o ConnectTimeout=5 user@host.docker.internal "/Applications/cmux.app/Contents/Resources/bin/cmux send --workspace workspace:1 it\'s\ a\ test"
```

**Exit Codes:**

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | SSH or execution failure |
| 2 | Invalid input (newlines or null bytes in arguments) |
| 3 | No cmux subcommand provided |

**Flags:**

| Flag | Description |
|------|-------------|
| `--dry-run` | Print the SSH command without executing it |
| `-h`, `--help` | Print usage information and exit |

The `--dry-run` flag is useful for debugging SSH command construction and verifying argument escaping before execution. Its output is for inspection only -- do not copy-paste it into a shell, as the escaping is optimized for SSH transport and may not work in a local context. Always use `$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh` directly to execute commands.

## Decision Tree

| Request | Action |
|---------|--------|
| "Open a new workspace/tab" | `$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh new-workspace` (note the `workspace:N` ID returned) |
| "Send this command to another session" | `$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh list-workspaces`, then two-step send to target `workspace:N` |
| "List my open workspaces/terminals" | `$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh list-workspaces` |
| "Open a devcontainer in a new workspace" | See Scenario 3 in Common Scenarios below |
| "Check if cmux is working" | Run `cmux-check.sh` (checks socketControlMode and connectivity) |
| "Verify a command ran correctly" | `$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh read-screen --workspace workspace:N --lines 20` |
| "I don't know the cmux command for X" | `$SSH "$CMUX --help"` to see CLI reference (see Command Reference) |
| "cmux says 'Access denied'" | Fix socketControlMode: `defaults write com.cmuxterm.app socketControlMode -string allowAll` |
| "Rename a workspace" | `$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh rename-workspace --workspace workspace:N 'New Name'` |
| "Close a workspace" | `$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh close-workspace --workspace workspace:N` |

## Common Scenarios

### Scenario 1: Create a New Workspace

```bash
CMUX="/Applications/cmux.app/Contents/Resources/bin/cmux"
SSH="ssh -o BatchMode=yes -o ConnectTimeout=5 ${HOST_USER}@host.docker.internal"

# Create workspace (returns: OK workspace:N)
$SSH "$CMUX new-workspace"

# Rename it for context
$SSH "$CMUX rename-workspace --workspace workspace:2 'My Work'"

# Or use the wrapper script:
CMUX_SSH="$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh"
$CMUX_SSH new-workspace
$CMUX_SSH rename-workspace --workspace workspace:2 'My Work'
```

### Scenario 2: Send a Command to a Workspace

```bash
CMUX="/Applications/cmux.app/Contents/Resources/bin/cmux"
SSH="ssh -o BatchMode=yes -o ConnectTimeout=5 ${HOST_USER}@host.docker.internal"

# Step 1: List workspaces to find target
$SSH "$CMUX list-workspaces"   # e.g., returns: workspace:1 dev [selected]

# Step 2: Type the command
$SSH "$CMUX send --workspace workspace:1 'npm test'"

# Step 3: Execute it
$SSH "$CMUX send-key --workspace workspace:1 enter"

# Step 4: Verify with read-screen
sleep 1  # allow command to run
$SSH "$CMUX read-screen --workspace workspace:1 --lines 20"
```

### Scenario 3: Open Devcontainer Session in New Workspace

```bash
CMUX="/Applications/cmux.app/Contents/Resources/bin/cmux"
SSH="ssh -o BatchMode=yes -o ConnectTimeout=5 ${HOST_USER}@host.docker.internal"

# Create the workspace
$SSH "$CMUX new-workspace"  # note the workspace:N ID returned

# Type docker exec command
$SSH "$CMUX send --workspace workspace:2 'docker exec -it dev-container_devcontainer-devcontainer-1 /bin/zsh -l'"

# Execute it
$SSH "$CMUX send-key --workspace workspace:2 enter"

# Wait and verify connection
sleep 2
$SSH "$CMUX read-screen --workspace workspace:2 --lines 5"
```

### Scenario 4: List All Workspaces

```bash
CMUX="/Applications/cmux.app/Contents/Resources/bin/cmux"
SSH="ssh -o BatchMode=yes -o ConnectTimeout=5 ${HOST_USER}@host.docker.internal"

$SSH "$CMUX list-workspaces"

# Or with the wrapper script:
$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh list-workspaces
```

## Environment Variables

### CMUX_BIN_OVERRIDE

Set `CMUX_BIN_OVERRIDE` to use a custom cmux binary path instead of the default `/Applications/cmux.app/Contents/Resources/bin/cmux`. This is useful when cmux is installed in a non-standard location (e.g., Homebrew, custom builds, or Linux hosts).

```bash
export CMUX_BIN_OVERRIDE="/usr/local/bin/cmux"
```

When set, all scripts (`cmux-utils.sh`, `$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh`, `cmux-check.sh`) will use this path instead of the default.

### CMUX_WORKSPACE_ID and CMUX_SURFACE_ID

cmux sets the environment variables `CMUX_WORKSPACE_ID` and `CMUX_SURFACE_ID` in shells running directly inside cmux on the macOS host. These variables identify which workspace and surface the shell belongs to.

**These variables are NOT propagated into the devcontainer.** When running commands from inside a container, you must always use explicit `--workspace workspace:N` targeting. Do not rely on these environment variables being available.

To discover the current workspace IDs, use:

```bash
$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh list-workspaces
```

## Performance Notes

Each cmux command runs over SSH, adding approximately 200-500ms of latency per invocation. When executing multiple cmux commands in sequence (batch operations), add a small delay between commands to avoid race conditions:

```bash
CMUX_SSH="$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh"

$CMUX_SSH new-workspace
sleep 0.5
$CMUX_SSH rename-workspace --workspace workspace:2 'Build'
sleep 0.5
$CMUX_SSH send --workspace workspace:2 'make build'
$CMUX_SSH send-key --workspace workspace:2 enter
```

For single commands, no delay is needed. The `send` and `send-key` pair can be issued back-to-back without delay since they target the same workspace sequentially.

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| "Access denied -- only processes started inside cmux can connect" | Default socket mode blocks SSH | `defaults write com.cmuxterm.app socketControlMode -string allowAll` (or use cmux Settings UI) |
| `cmux: command not found` in SSH session | Binary not in SSH PATH | Use full path: `/Applications/cmux.app/Contents/Resources/bin/cmux` |
| SSH connection refused | HOST_USER wrong or SSH keys not set up | Run `cmux-check.sh`; verify HOST_USER; check SSH key setup |
| `cmux ping` fails but cmux is running | socketControlMode not set | Same fix as "Access denied" above |
| Commands type text but don't execute | Missing `send-key enter` step | Add `cmux send-key --workspace workspace:N enter` after `send` |
| HOST_USER not set | Environment variable missing from devcontainer config | Add `"HOST_USER": "your-username"` to `remoteEnv` in `devcontainer.json` |

For comprehensive diagnostics, run `cmux-check.sh` which validates all five prerequisites in order and reports pass/fail for each.

## Issue #373 Reference

> For the full explanation of why SSH is required and how the SSH-to-host pattern resolves both the "Access denied" error and the Issue #373 CLI limitation, see the [Execution Model > Why SSH is Required](#why-ssh-is-required) section above.
