---
name: tab-management
description: iTerm2 tab management for opening, listing, and closing terminal tabs from macOS host or Linux container environments.
---

# Tab Management Skill

**Last Updated:** 2026-01-15
**Plugin:** iterm
**Scripts Location:** `plugins/iterm/skills/tab-management/scripts/`

## Overview

The tab-management skill provides iTerm2 tab management capabilities for Claude Code, enabling automated terminal tab creation, querying, and cleanup from both macOS host environments and Linux containers (via SSH tunneling).

**Key Capabilities:**
- Open new iTerm2 tabs with specified profiles, directories, and commands
- List existing windows and tabs in table or JSON format
- Close tabs by pattern matching on titles
- Automatic context detection (host vs container mode)
- Profile-based connection for reliable devcontainer integration

**When to Use This Skill vs Manual Operations:**

| Use This Skill | Use Manual Operations |
|----------------|----------------------|
| Automating worktree workflows | One-off terminal needs |
| Spawning Claude agents in tabs | Quick manual tab creation |
| Cleaning up tabs after worktree deletion | Exploratory testing |
| Scripting multi-tab environments | When iTerm2 UI is preferred |
| Checking existing tabs programmatically | Visual tab inspection |

## Prerequisites

### Required for All Modes

- **macOS Host System**: iTerm2 is macOS-only; these scripts require a macOS host
- **iTerm2 Installed**: Must be installed at `/Applications/iTerm.app`
  - Install from: https://iterm2.com

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

- **iTerm2 Running**: Script will activate iTerm2 if not running
- **AppleScript Permissions**: System Preferences > Privacy & Security > Automation
  - Terminal (or calling app) must have permission to control iTerm2

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
| `iterm:open-tab` | `iterm-open-tab.sh` | Create new terminal tabs with profile, directory, and command options |
| `iterm:list-tabs` | `iterm-list-tabs.sh` | Query existing windows and tabs in table or JSON format |
| `iterm:close-tab` | `iterm-close-tab.sh` | Close tabs by pattern matching against tab titles |

## Decision Tree

```
What do you need to do?
    |
    +-- Need to execute command in new environment?
    |       |
    |       +-- Opening new worktree for development?
    |       |       --> Use iterm:open-tab with --directory, --profile "Devcontainer",
    |       |           and --wait-for-prompt (ensures shell is ready before cd)
    |       |
    |       +-- Spawning Claude agent for parallel work?
    |       |       --> Use iterm:open-tab with --command "claude ..."
    |       |
    |       +-- Opening specific directory in container?
    |               --> Use iterm:open-tab with --directory
    |
    +-- Need to check existing tabs?
    |       |
    |       +-- Quick visual check?
    |       |       --> Use iterm:list-tabs (table format, default)
    |       |
    |       +-- Programmatic parsing/scripting?
    |               --> Use iterm:list-tabs --format json
    |
    +-- Need to cleanup tabs?
    |       |
    |       +-- Preview what would be closed first?
    |       |       --> Use iterm:close-tab --dry-run "pattern"
    |       |
    |       +-- Close matching tabs with confirmation?
    |       |       --> Use iterm:close-tab "pattern"
    |       |
    |       +-- Automated cleanup (no prompts)?
    |               --> Use iterm:close-tab --force "pattern"
    |
    +-- Need to broadcast to multiple tabs?
            --> Consider broadcast-to-agents.sh (separate tool)
```

## Common Scenarios

### Scenario 1: Opening Tab for New Worktree

After creating a worktree, open a tab connected to it:

```bash
# Open tab in the new worktree directory using Devcontainer profile
iterm-open-tab.sh --directory "/workspace/repos/my-project/feature-branch" \
                  --profile "Devcontainer" \
                  --wait-for-prompt \
                  --name "worktree: feature-branch"
```

**What happens:**
1. Script detects execution context (host/container)
2. Builds AppleScript for tab creation with polling loop
3. Opens new tab in frontmost window (or creates window if none exist)
4. Tab uses "Devcontainer" profile which auto-connects to container
5. Polling loop waits for shell prompt (up to 15 seconds)
6. Once prompt detected (or timeout), navigates to specified directory
7. Sets tab title to "worktree: feature-branch"

### Scenario 2: Spawning Claude Agent in New Tab

Open a tab and start a Claude Code agent session:

```bash
# Open tab and launch Claude with specific agent
iterm-open-tab.sh --directory "/workspace/repos/project" \
                  --command "claude --agent security-reviewer" \
                  --name "agent: security-reviewer"
```

**What happens:**
1. Tab opens with Devcontainer profile
2. Navigates to project directory
3. Executes the Claude command
4. Tab is named for easy identification

### Scenario 3: Listing Tabs Before Creating

Check if a tab already exists before creating a duplicate:

```bash
# List all tabs in table format
iterm-list-tabs.sh

# List tabs in JSON format for scripting
iterm-list-tabs.sh --format json

# Filter to specific window
iterm-list-tabs.sh --window 1

# Check for specific pattern programmatically
iterm-list-tabs.sh --format json | jq '.windows[].tabs[] | select(.title | contains("feature-branch"))'
```

**Example Output (table format):**
```
Window  Tab  Title                         Session
1       1    Devcontainer                  zsh
1       2    worktree: feature-branch      zsh
1       3    agent: security-reviewer      zsh
```

**Example Output (JSON format):**
```json
{
  "windows": [
    {
      "index": 1,
      "tabs": [
        {"index": 1, "title": "Devcontainer", "session": "zsh"},
        {"index": 2, "title": "worktree: feature-branch", "session": "zsh"},
        {"index": 3, "title": "agent: security-reviewer", "session": "zsh"}
      ]
    }
  ]
}
```

### Scenario 4: Cleanup After Worktree Deletion

After deleting a worktree, close associated tabs:

```bash
# First, preview which tabs would be closed (safe - no changes)
iterm-close-tab.sh --dry-run "worktree: old-feature"

# If preview looks correct, close the tabs
iterm-close-tab.sh "worktree: old-feature"

# For automated scripts, skip confirmation prompt
iterm-close-tab.sh --force "worktree: old-feature"

# Limit to specific window
iterm-close-tab.sh --window 1 "worktree: old-feature"
```

**Confirmation Flow (multiple matches):**
```
Matching tabs found:
  Window 1, Tab 2: worktree: old-feature
  Window 1, Tab 5: worktree: old-feature-test

Found 2 matching tabs. Close them all? [y/N]:
```

## Script Reference

### iterm-open-tab.sh

Opens new iTerm2 tabs with full customization.

**Usage:**
```bash
iterm-open-tab.sh [OPTIONS]
```

**Options:**

| Flag | Long Form | Description | Default |
|------|-----------|-------------|---------|
| `-d` | `--directory DIR` | Working directory for the new tab | `/workspace` |
| `-p` | `--profile PROFILE` | iTerm2 profile name | `Devcontainer` |
| `-c` | `--command CMD` | Command to execute after tab opens | (none) |
| `-n` | `--name NAME` | Tab title | (profile default) |
| `-w` | `--window` | Create new window instead of tab | (false) |
| | `--wait-for-prompt` | Wait for shell prompt before sending command | (false) |
| | `--dry-run` | Show AppleScript without executing | (false) |
| `-h` | `--help` | Display help information | |

**Note on `--wait-for-prompt`:** Inserts an AppleScript polling loop that checks `is at shell prompt` before sending the shell command. Uses a 3-second initial delay (`WAIT_INITIAL_DELAY`), then polls every 1 second (`WAIT_POLL_INTERVAL`) for up to 12 iterations (`WAIT_MAX_POLL`) — 15-second total maximum. If the prompt is not detected within that window, the command is sent anyway and a warning is logged to Apple System Log. Requires iTerm2 Shell Integration to be enabled on the macOS host (`iTerm2 > Install Shell Integration`). Has no effect when directory and command are both empty. Typical use case: opening a tab with the Devcontainer profile, where the container shell takes several seconds to become ready after `docker exec`.

**Examples:**

```bash
# Basic: Open tab in default directory with Devcontainer profile
iterm-open-tab.sh

# Open tab in specific directory
iterm-open-tab.sh -d /workspace/repos/my-project

# Open tab with custom profile and title
iterm-open-tab.sh -p "Development" -n "My Custom Tab"

# Open tab and run a command
iterm-open-tab.sh -c "git status && npm test"

# Open in new window instead of tab
iterm-open-tab.sh -w -d /workspace

# Preview AppleScript without executing
iterm-open-tab.sh --dry-run -d /workspace -n "Test Tab"
```

### iterm-list-tabs.sh

Lists all iTerm2 windows and tabs.

**Usage:**
```bash
iterm-list-tabs.sh [OPTIONS]
```

**Options:**

| Flag | Long Form | Description | Default |
|------|-----------|-------------|---------|
| `-f` | `--format FORMAT` | Output format: `json` or `table` | `table` |
| `-w` | `--window INDEX` | Filter to specific window (1-based) | (all windows) |
| | `--dry-run` | Show AppleScript without executing | (false) |
| `-h` | `--help` | Display help information | |

**Examples:**

```bash
# List all tabs in table format (default)
iterm-list-tabs.sh

# List all tabs in JSON format
iterm-list-tabs.sh --format json

# List tabs from window 2 only
iterm-list-tabs.sh -w 2

# Combine options
iterm-list-tabs.sh --format json --window 1

# Preview AppleScript without executing
iterm-list-tabs.sh --dry-run
```

### iterm-close-tab.sh

Closes tabs by matching pattern against tab titles.

**Usage:**
```bash
iterm-close-tab.sh [OPTIONS] <pattern>
```

**Arguments:**

| Argument | Description |
|----------|-------------|
| `pattern` | Substring to match against tab titles (case-sensitive, not regex) |

**Options:**

| Flag | Long Form | Description | Default |
|------|-----------|-------------|---------|
| `-w` | `--window INDEX` | Limit to specific window (1-based) | (all windows) |
| | `--force` | Skip confirmation for multiple matches | (false) |
| | `--dry-run` | Show what would be closed without closing | (false) |
| `-h` | `--help` | Display help information | |

**Examples:**

```bash
# Close tabs containing "worktree:" in title
iterm-close-tab.sh "worktree:"

# Preview which tabs would be closed
iterm-close-tab.sh --dry-run "feature-branch"

# Close tabs in window 1 only
iterm-close-tab.sh -w 1 "test"

# Close without confirmation prompt
iterm-close-tab.sh --force "cleanup"

# Combine options
iterm-close-tab.sh --force -w 2 "worktree: feature"
```

## Execution Contexts

The scripts automatically detect whether they are running on the macOS host or inside a container and adapt their execution strategy.

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

### Container Mode

**How it works:**
1. AppleScript is base64-encoded (avoids shell escaping issues)
2. Encoded script sent via SSH to `host.docker.internal`
3. Decoded and written to temporary file on host
4. Executed via `osascript` on host
5. Temporary file cleaned up

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

## Profile-Based vs Docker Exec

### Profile-Based Approach (Primary)

The plugin uses iTerm2 profiles as the primary connection mechanism.

**How it works:**
1. Tab opens with "Devcontainer" profile
2. Profile has a startup command that connects to the container
3. After connection, script's directory and command are executed

**Example Profile Configuration:**
```bash
# iTerm2 Profile > Command setting
docker exec -it devcontainer /bin/zsh
```

**Advantages:**
- Bypasses Docker Desktop PATH bug
- Profile handles connection complexity
- Cleaner separation of concerns
- Consistent with spawn-agent.sh proven pattern

### Docker Exec Approach (Fallback)

For users not using the Devcontainer profile:

**How it works:**
1. Tab opens with specified profile
2. Script explicitly runs docker exec with PATH prefix

**Example:**
```bash
# Explicit PATH fixes Docker Desktop bug
osascript -e 'tell application "iTerm2" to tell current session of first window to write text "PATH=/usr/local/bin:$PATH docker exec -it devcontainer /bin/zsh"'
```

**When to use:**
- Custom profiles without container connection
- Need explicit control over docker exec
- Debugging connection issues

**Note:** Profile-based is strongly preferred. Docker exec approach requires explicit PATH prefix to work around Docker Desktop PATH resolution bug.

## Troubleshooting

### Issue: "iTerm2 not found"

**Error Message:**
```
[ERROR] iTerm2 not found at /Applications/iTerm.app
[ERROR] Install from: https://iterm2.com
```

**Cause:** iTerm2 is not installed on the macOS host.

**Solution:**
1. Download iTerm2 from https://iterm2.com
2. Move iTerm2.app to /Applications/
3. Launch iTerm2 at least once to complete setup

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

### Issue: "HOST_USER environment variable required"

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

### Issue: "Profile 'Devcontainer' not found"

**Error Message:**
Tab opens but shows profile not found or uses Default profile.

**Cause:** iTerm2 "Devcontainer" profile not configured.

**Solution:**
1. Open iTerm2 Preferences (Cmd+,)
2. Go to Profiles tab
3. Click "+" to create new profile
4. Name it "Devcontainer"
5. Under "General" > "Command", select "Login Shell" or custom command
6. For container connection, set command to:
   ```bash
   docker exec -it devcontainer /bin/zsh
   ```

### Issue: "--wait-for-prompt times out (command sent late)"

**Symptoms:**
- Tab opens with Devcontainer profile
- A 15-second delay occurs before the `cd` command runs
- Warning logged to Apple System Log: "shell prompt not detected after 15 seconds"

**Cause:** iTerm2 Shell Integration is not installed, so `is at shell prompt` always returns false.

**Solution:**
1. Install Shell Integration in iTerm2: `iTerm2 > Install Shell Integration`
2. Restart your terminal session
3. Verify with: `iTerm2 > Shell Integration > Check Installation`

**Note:** Even without Shell Integration, the command will still execute after the timeout — it just takes longer.

### Issue: "Tab opens but command doesn't execute"

**Symptoms:**
- Tab opens successfully
- Directory is correct
- But --command flag command doesn't run

**Causes:**
- Profile startup script conflicts
- Timing issues
- Shell initialization blocking

**Solutions:**
1. Ensure profile Command is set to run login shell
2. Check `.zshrc` or `.bashrc` for blocking prompts
3. Try without profile customizations first
4. Use simpler command to test:
   ```bash
   iterm-open-tab.sh -c "echo test"
   ```

### Issue: "AppleScript execution failed"

**Error Message:**
```
[ERROR] AppleScript execution failed
```

**Causes:**
- iTerm2 not running
- AppleScript permissions not granted
- Syntax error in generated script

**Solutions:**
1. Launch iTerm2 manually first
2. Grant permissions in System Preferences > Privacy & Security > Automation
3. Use --dry-run to inspect generated AppleScript:
   ```bash
   iterm-open-tab.sh --dry-run -d /workspace
   ```
4. Test AppleScript directly:
   ```bash
   osascript -e 'tell application "iTerm2" to activate'
   ```

## Exit Codes

All scripts use consistent exit codes for error handling:

| Exit Code | Constant | Meaning | Common Causes |
|-----------|----------|---------|---------------|
| 0 | EXIT_SUCCESS | Success | Operation completed successfully |
| 1 | EXIT_CONNECTION_FAIL | SSH/connection failure | SSH key issues, HOST_USER not set, network problems |
| 2 | EXIT_ITERM_UNAVAILABLE | iTerm2 not available | iTerm2 not installed, not at expected path |
| 3 | EXIT_INVALID_ARGS | Invalid arguments | Missing required args, unknown flags, invalid values |
| 4 | EXIT_NO_MATCH | Pattern matches no tabs | (close-tab only) No tabs match the provided pattern |

**Example Error Handling:**
```bash
#!/bin/bash
if iterm-open-tab.sh -d /workspace/repos/project; then
    echo "Tab opened successfully"
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

## Integration

### Integration with spawn-worktree.sh

The spawn-worktree.sh script can delegate tab opening to this plugin:

```bash
# spawn-worktree.sh uses wrapper approach
open_iterm_tab() {
    local directory="$1"
    local profile="${2:-Devcontainer}"
    local name="$3"
    local wait_flag=""

    # Wait for shell prompt when using Devcontainer profile
    if [ "$profile" = "Devcontainer" ]; then
        wait_flag="--wait-for-prompt"
    fi

    local plugin_script="$ITERM_PLUGIN/scripts/iterm-open-tab.sh"

    if [[ -x "$plugin_script" ]]; then
        "$plugin_script" \
            --directory "$directory" \
            --profile "$profile" \
            ${wait_flag:+"$wait_flag"} \
            --name "$name"
    else
        # Fallback to original implementation (inline AppleScript with polling)
        open_iterm_tab_original "$@"
    fi
}
```

**Workflow:**
1. User runs `spawn-worktree.sh feature-branch --repo myproject`
2. Worktree is created
3. spawn-worktree.sh delegates to iterm-open-tab.sh
4. Tab opens in new worktree directory

### Integration with spawn-agent.sh

Similarly, spawn-agent.sh uses the plugin for tab creation:

```bash
# spawn-agent.sh delegates tab opening
spawn_agent_tab() {
    iterm-open-tab.sh \
        --directory "$WORKTREE_PATH" \
        --command "claude --agent $AGENT_NAME" \
        --name "agent: $AGENT_NAME"
}
```

**Workflow:**
1. User runs `spawn-agent.sh security-reviewer --worktree feature-branch`
2. spawn-agent.sh calls iterm-open-tab.sh
3. Tab opens with Claude agent session running

### Integration with Worktree Cleanup

When deleting worktrees, use iterm:close-tab for cleanup:

```bash
# Cleanup workflow
cleanup_worktree() {
    local worktree_name="$1"

    # Preview tabs to close
    iterm-close-tab.sh --dry-run "worktree: $worktree_name"

    # Close matching tabs (with --force for automation)
    iterm-close-tab.sh --force "worktree: $worktree_name"

    # Delete the worktree
    crewchief worktree clean "$worktree_name"
}
```

## Performance Considerations

### SSH Overhead (Container Mode)

Each operation from container mode incurs ~500ms SSH overhead:
- Connection establishment: ~200ms
- Key exchange: ~100ms
- Command execution: ~100ms
- Cleanup: ~100ms

**Optimization:** For batch operations, consider running from host mode when possible.

### Recommended Delays

When creating multiple tabs rapidly:
```bash
# Add small delay between tab creations
for branch in feature-1 feature-2 feature-3; do
    iterm-open-tab.sh -d "/workspace/repos/project/$branch" -n "worktree: $branch"
    sleep 0.2  # 200ms delay prevents iTerm2 race conditions
done
```

### Large Tab Sets

Querying tabs with many windows (50+ tabs):
- Table format: Truncates titles for readability
- JSON format: Full data, may be large
- Window filter: Use `--window` to reduce query scope

```bash
# Faster: Query specific window only
iterm-list-tabs.sh -w 1 -f json

# Slower: Query all windows
iterm-list-tabs.sh -f json
```

## Security Considerations

### SSH Key Authentication

- Scripts use `BatchMode=yes` - no interactive password prompts
- SSH keys must be pre-configured (no password fallback)
- Keys should be ed25519 or RSA 4096-bit

### AppleScript Permissions

- macOS requires explicit permission for automation
- Grant in System Preferences > Privacy & Security > Automation
- Terminal/calling app needs permission to control iTerm2

### Input Validation

Scripts validate inputs to prevent injection:
- Directory paths: Quoted in AppleScript
- Tab names: Escaped for AppleScript strings
- Patterns: Used as substring match, not regex execution

**Note:** While inputs are sanitized, avoid passing untrusted user input directly to these scripts in production environments.

### Temporary Files

- Container mode creates temp files on host for AppleScript
- Files are created in `/tmp/` with random names
- Cleanup via trap handlers on EXIT, INT, TERM
- Files are removed immediately after execution

## Related

- **worktree-spawn** - Orchestrates worktree creation with iTerm tab integration
- **worktree-cleanup** - Worktree deletion workflow (can integrate with iterm:close-tab)
- **spawn-agent.sh** - Claude agent spawning with tab management
- **applescript-reference.md** - iTerm2 AppleScript API reference (in references/)
