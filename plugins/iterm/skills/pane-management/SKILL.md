---
name: pane-management
description: iTerm2 pane management for splitting, listing, and closing panes within existing tabs from macOS host or Linux container environments.
---

# Pane Management Skill

**Last Updated:** 2026-02-08
**Plugin:** iterm
**Scripts Location:** `plugins/iterm/skills/pane-management/scripts/`

## Overview

The pane-management skill provides iTerm2 pane management capabilities for Claude Code, enabling automated splitting, listing, and closing of panes within existing terminal tabs from both macOS host environments and Linux containers (via SSH tunneling).

**Key Capabilities:**
- Split the current iTerm2 session vertically or horizontally
- Specify iTerm2 profiles for new panes
- Execute commands in newly created panes
- Set pane titles for identification
- List all panes across windows and tabs with window/tab filtering
- Close panes by substring pattern matching with confirmation prompts
- JSON and table output formats for automation
- Dry-run mode for all operations (split, list, close)
- Automatic context detection (host vs container mode)

**Important:** This skill splits panes within an existing iTerm2 window. It will not create a new window if none exists. Use the tab-management skill to create new tabs or windows first.

**When to Use This Skill vs Tab Management:**

| Use Pane Management | Use Tab Management |
|---------------------|--------------------|
| Side-by-side code and terminal output | Separate workspaces for different repos |
| Monitoring logs alongside development | Spawning Claude agents in isolated tabs |
| Running tests while editing | Opening new worktree environments |
| Quick reference pane (docs, git log) | Need full-width terminal workspace |
| Comparing output from two commands | Creating new windows |
| Batch close related panes by name pattern | Close tabs by name pattern |
| Inventory panes across windows/tabs (JSON) | List tabs across windows (JSON) |

## Prerequisites

### Required for All Modes

- **macOS Host System**: iTerm2 is macOS-only; these scripts require a macOS host
- **iTerm2 Installed**: Must be installed at `/Applications/iTerm.app`
  - Install from: https://iterm2.com
- **Existing iTerm2 Window**: At least one window must be open (the script does not create windows)

### Container Mode Requirements

When running from inside a devcontainer:

- **SSH Access to Host**: Container must be able to SSH to `host.docker.internal`
  - Configured via post-start.sh in devcontainer setup
  - SSH keys mounted at `~/.ssh/id_ed25519`

- **HOST_USER Environment Variable**: Required for SSH connection
  - Set in devcontainer.json:
    ```json
    {
      "remoteEnv": {
        "HOST_USER": "your-macos-username"
      }
    }
    ```

- **iTerm2 Profiles Configured**: Especially the "Devcontainer" profile
  - Profile should have startup script that connects to the container
  - Configured in iTerm2 Preferences > Profiles > Command

### Host Mode Requirements

When running directly on macOS:

- **iTerm2 Running**: At least one window must exist
- **AppleScript Permissions**: System Preferences > Privacy & Security > Automation
  - Terminal (or calling app) must have permission to control iTerm2

### Shared Utilities

This skill sources `iterm-utils.sh` from the sibling tab-management skill directory:

```
plugins/iterm/skills/
  tab-management/scripts/iterm-utils.sh   <-- shared utilities
  pane-management/scripts/iterm-split-pane.sh  <-- sources from above
```

This cross-skill sourcing pattern provides shared functions for context detection, AppleScript execution, SSH transport, and validation. If `iterm-utils.sh` cannot be sourced, the script exits with code 3.

### Verification Commands

```bash
# Check if running in container vs host
uname -s  # Darwin = host, Linux = container

# Verify iTerm2 (host only)
ls /Applications/iTerm.app

# Test SSH connectivity (container only)
ssh -o BatchMode=yes -o ConnectTimeout=5 ${HOST_USER}@host.docker.internal "echo OK"

# Check HOST_USER is set (container only)
echo "HOST_USER=${HOST_USER:-NOT SET}"
```

## Skills Overview

| Skill | Script | Purpose |
|-------|--------|---------|
| `iterm:split-pane` | `iterm-split-pane.sh` | Split current session into a new pane with direction, profile, command, and name options |

## Decision Tree

```
What do you need to do?
    |
    +-- Need a new pane alongside current work?
    |       |
    |       +-- Side-by-side comparison or editing?
    |       |       --> Use iterm:split-pane -d vertical
    |       |
    |       +-- Stacked layout (code above, output below)?
    |       |       --> Use iterm:split-pane -d horizontal
    |       |
    |       +-- Need to run a command in the new pane?
    |       |       --> Add -c "your command here"
    |       |
    |       +-- Need to navigate to a directory?
    |               --> Use -c "cd /path/to/directory"
    |               (NOT -d, which sets split direction)
    |
    +-- Need a completely separate workspace?
    |       --> Use tab-management skill (iterm:open-tab) instead
    |
    +-- No iTerm2 windows exist?
            --> Use tab-management skill to create a window first
            (iterm:split-pane requires an existing window)
```

## Common Scenarios

### Scenario 1: Vertical Split for Side-by-Side Work

Split the current session vertically to work on code side-by-side:

```bash
# Split vertically (default direction) with Devcontainer profile
iterm-split-pane.sh

# Explicitly specify vertical direction
iterm-split-pane.sh -d vertical
```

**What happens:**
1. Script detects execution context (host/container)
2. Builds AppleScript targeting the current session of the first window
3. Splits the current session vertically with the specified profile
4. New pane appears to the right and receives focus

### Scenario 2: Horizontal Split for Log Monitoring

Split horizontally to monitor logs or output below your working pane:

```bash
# Split horizontally for stacked layout
iterm-split-pane.sh -d horizontal -n "Logs"
```

**What happens:**
1. Current session splits horizontally
2. New pane appears below and receives focus
3. Pane title is set to "Logs" for identification

### Scenario 3: Split with Command Execution

Open a new pane and immediately run a command:

```bash
# Split and run git status
iterm-split-pane.sh -c "git status"

# Split and start a dev server
iterm-split-pane.sh -d horizontal -c "npm run dev" -n "Dev Server"

# Split and run tests
iterm-split-pane.sh -d vertical -c "npm test -- --watch" -n "Tests"
```

**What happens:**
1. Pane splits in the specified direction
2. The command is written to the new pane's session
3. Command executes in the context of the pane's profile/shell

### Scenario 4: Navigate to Directory in New Pane

Open a pane in a specific directory (use `-c` for navigation, not `-d`):

```bash
# Navigate to a project directory in the new pane
iterm-split-pane.sh -c "cd /workspace/repos/my-project"

# Navigate and then run a command
iterm-split-pane.sh -c "cd /workspace/repos/my-project && git log --oneline -10"
```

**Important:** The `-d` flag sets split **direction** (vertical/horizontal), not directory. Use `-c` with a `cd` command for navigation.

## Script Reference

### iterm-split-pane.sh

Splits the current iTerm2 session into a new pane with support for direction selection, profile specification, command execution, and pane naming.

**Usage:**
```bash
iterm-split-pane.sh [OPTIONS]
```

**Options:**

| Flag | Long Form | Description | Default |
|------|-----------|-------------|---------|
| `-d` | `--direction DIR` | Split direction: `vertical` or `horizontal` | `vertical` |
| `-p` | `--profile PROFILE` | iTerm2 profile name | `Devcontainer` |
| `-c` | `--command CMD` | Command to run in the new pane | (none) |
| `-n` | `--name NAME` | Set pane title | (profile default) |
| | `--dry-run` | Show AppleScript without executing | (false) |
| `-h` | `--help` | Display help information | |

**Flag Clarification:**
- `-d` sets the split **direction** (`vertical` or `horizontal`), NOT the working directory. This is different from `-d` in the tab-management script (which sets the directory). To navigate to a directory in the new pane, use `-c "cd /path"`.
- `-c` sets a **command** to execute in the new pane. This can include navigation commands like `cd /path/to/dir`.

**Examples:**

```bash
# Split vertically with default Devcontainer profile
iterm-split-pane.sh

# Split horizontally
iterm-split-pane.sh -d horizontal

# Split with custom profile and title
iterm-split-pane.sh -p "Custom Profile" -n "My Pane"

# Split and run a command in the new pane
iterm-split-pane.sh -c "git status"

# Navigate to a directory in the new pane
iterm-split-pane.sh -c "cd /workspace/repos/my-project"

# Preview AppleScript without executing
iterm-split-pane.sh --dry-run -d horizontal -n "Test Pane"

# All options combined
iterm-split-pane.sh -d vertical -p "Development" -c "npm test" -n "Test Runner"
```

## Execution Contexts

The script automatically detects whether it is running on the macOS host or inside a container and adapts its execution strategy. This detection uses the shared `iterm-utils.sh` from the tab-management skill.

### Detection Logic

```
Start
  |
  v
Check: /.dockerenv exists?
  |
  +-- Yes --> CONTAINER MODE
  |
  v
Check: /proc/1/cgroup contains "docker"?
  |
  +-- Yes --> CONTAINER MODE
  |
  v
Check: uname != "Darwin"?
  |
  +-- Yes --> CONTAINER MODE (Linux implies container)
  |
  v
HOST MODE
```

### Host Mode

**How it works:**
- AppleScript executed directly via `osascript`
- No SSH required
- Immediate execution

**Requirements:**
- iTerm2 installed at `/Applications/iTerm.app`
- AppleScript permissions granted
- At least one iTerm2 window open

### Container Mode

**How it works:**
1. AppleScript is base64-encoded (avoids shell escaping issues)
2. Encoded script sent via SSH to `host.docker.internal`
3. Decoded and written to temporary file on host
4. Executed via `osascript` on host
5. Temporary file cleaned up via trap handlers

**Requirements:**
- SSH access to `host.docker.internal`
- `HOST_USER` environment variable set
- SSH keys mounted in container

### Behavior Comparison

| Aspect | Host Mode | Container Mode |
|--------|-----------|----------------|
| AppleScript Execution | Direct osascript | SSH + osascript |
| Latency | ~100ms | ~500ms (SSH overhead) |
| Environment Variable | Not required | HOST_USER required |
| Prerequisites | iTerm2, permissions | SSH config, HOST_USER |
| Debug Output | Direct | Via SSH tunnel |

## Exit Codes

All exit codes are defined in `iterm-utils.sh` and shared across iterm skills:

| Exit Code | Constant | Meaning | Common Causes |
|-----------|----------|---------|---------------|
| 0 | EXIT_SUCCESS | Success | Pane split completed successfully |
| 1 | EXIT_CONNECTION_FAIL | SSH/connection failure | SSH key issues, HOST_USER not set, network problems, AppleScript execution failure |
| 2 | EXIT_ITERM_UNAVAILABLE | iTerm2 not available | iTerm2 not installed, not at expected path |
| 3 | EXIT_INVALID_ARGS | Invalid arguments | Unknown flags, missing required values, invalid direction, iterm-utils.sh not found |

**Note:** Unlike tab-management which also defines exit code 4 (EXIT_NO_MATCH for close-tab), pane-management only uses codes 0-3.

**Example Error Handling:**
```bash
#!/bin/bash
if iterm-split-pane.sh -d vertical -c "npm test"; then
    echo "Pane split successfully"
else
    exit_code=$?
    case $exit_code in
        1) echo "Connection failed - check SSH config" ;;
        2) echo "iTerm2 not available" ;;
        3) echo "Invalid arguments" ;;
        *) echo "Unknown error: $exit_code" ;;
    esac
    exit $exit_code
fi
```

## Troubleshooting

### Issue: "NO_WINDOWS" returned

**Symptom:** The script returns "NO_WINDOWS" instead of splitting a pane.

**Cause:** No iTerm2 windows are open. Unlike tab-management (which can create new windows), pane-management requires an existing window to split within.

**Solution:**
1. Open iTerm2 and ensure at least one window exists
2. Or use the tab-management skill first to create a tab/window:
   ```bash
   iterm-open-tab.sh -d /workspace
   ```
3. Then split the pane:
   ```bash
   iterm-split-pane.sh -d vertical
   ```

### Issue: "Failed to source iterm-utils.sh"

**Error Message:**
```
[ERROR] Failed to source iterm-utils.sh from /path/to/tab-management/scripts
```

**Cause:** The shared utility file `iterm-utils.sh` in the tab-management skill directory cannot be found or sourced. The pane-management script depends on this file via cross-skill sourcing.

**Solution:**
1. Verify the tab-management skill directory exists:
   ```bash
   ls plugins/iterm/skills/tab-management/scripts/iterm-utils.sh
   ```
2. Ensure both skills are installed together (they share utilities)
3. Check file permissions allow reading

### Issue: "Invalid direction"

**Error Message:**
```
[ERROR] Invalid direction: <value> (must be horizontal or vertical)
```

**Cause:** The `-d` flag received a value other than `vertical` or `horizontal`. A common mistake is passing a directory path to `-d` (which sets direction, not directory).

**Solution:**
- Use only `vertical` or `horizontal` with `-d`:
  ```bash
  iterm-split-pane.sh -d vertical
  iterm-split-pane.sh -d horizontal
  ```
- To navigate to a directory, use `-c` with a `cd` command:
  ```bash
  iterm-split-pane.sh -c "cd /workspace/repos/my-project"
  ```

### Issue: "SSH connection failed"

**Error Message:**
```
[ERROR] SSH connection to host.docker.internal failed
[ERROR] Verify SSH is configured (see post-start.sh setup)
```

**Causes:**
- SSH keys not mounted in container
- SSH not configured for host.docker.internal
- Docker Desktop networking issue

**Solutions:**
1. Verify SSH keys are mounted:
   ```bash
   ls -la ~/.ssh/id_ed25519
   ```
2. Check devcontainer.json includes SSH mount:
   ```json
   "mounts": [
     "source=${localEnv:HOME}/.ssh,target=/home/vscode/.ssh,type=bind,readonly"
   ]
   ```
3. Test SSH manually:
   ```bash
   ssh -o BatchMode=yes -o ConnectTimeout=5 ${HOST_USER}@host.docker.internal "echo OK"
   ```
4. Rebuild container after adding SSH configuration

### Issue: "HOST_USER environment variable not set"

**Error Message:**
```
[ERROR] HOST_USER environment variable not set
[ERROR] Set HOST_USER in devcontainer.json remoteEnv
```

**Cause:** HOST_USER is required for SSH from container but not configured.

**Solution:**
Add to devcontainer.json:
```json
{
  "remoteEnv": {
    "HOST_USER": "your-macos-username"
  }
}
```
Then rebuild the container.

### Issue: "AppleScript execution failed"

**Error Message:**
```
[ERROR] Failed to split iTerm2 pane
```

**Causes:**
- iTerm2 not running
- AppleScript permissions not granted
- Profile specified with `-p` does not exist in iTerm2

**Solutions:**
1. Launch iTerm2 manually first
2. Grant permissions in System Preferences > Privacy & Security > Automation
3. Use `--dry-run` to inspect generated AppleScript:
   ```bash
   iterm-split-pane.sh --dry-run -d vertical -p "Devcontainer"
   ```
4. Verify the profile exists in iTerm2 Preferences > Profiles
5. Test AppleScript directly:
   ```bash
   osascript -e 'tell application "iTerm2" to activate'
   ```

## Performance Considerations

### SSH Overhead (Container Mode)

Each operation from container mode incurs ~500ms SSH overhead:
- Connection establishment: ~200ms
- Key exchange: ~100ms
- Command execution: ~100ms
- Cleanup: ~100ms

**Optimization:** For batch operations, consider running from host mode when possible.

### Multiple Pane Splits

When splitting multiple panes rapidly:
```bash
# Add small delay between pane splits to avoid race conditions
for cmd in "npm test" "npm run dev" "git log --follow -p"; do
    iterm-split-pane.sh -d vertical -c "$cmd"
    sleep 0.3  # 300ms delay prevents iTerm2 race conditions
done
```

### First Window Behavior

The script always targets `first window` in its AppleScript for multi-window safety. This means:
- Splits always occur in the frontmost iTerm2 window
- Predictable behavior when multiple windows exist
- No risk of splitting in the wrong window

## Related

- **tab-management** - Tab creation, listing, and closing (shares `iterm-utils.sh` utilities)
- **iterm-cross-skill-sourcing** - Pattern for sharing `iterm-utils.sh` across pane-management and tab-management skills
- **iterm-utils.sh** - Shared utility library providing context detection, AppleScript execution, SSH transport, and validation functions (`plugins/iterm/skills/tab-management/scripts/iterm-utils.sh`)
