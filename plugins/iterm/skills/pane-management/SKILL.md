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
- **Existing iTerm2 Window**: At least one window must be open. Unlike tab-management, pane-management will **not** create a new window if none exists. Use `iterm:open-tab` first if no window is available.

### Container Mode

- SSH access to `host.docker.internal` with mounted SSH keys
- `HOST_USER` environment variable set in `devcontainer.json`
- iTerm2 "Devcontainer" profile configured

See the tab-management SKILL.md section "Container Mode Requirements" for full SSH setup, HOST_USER configuration, and profile details.

### Host Mode

- iTerm2 running with at least one window open
- AppleScript permissions granted (System Preferences > Privacy & Security > Automation)

See the tab-management SKILL.md section "Host Mode Requirements" for details.

### Shared Utilities

This skill sources `iterm-utils.sh` from the tab-management skill directory. If `iterm-utils.sh` cannot be sourced, the script exits with code 3. See the tab-management SKILL.md for verification commands and utility details.

## Skills Overview

| Skill | Description | Key Flags |
|-------|-------------|-----------|
| `iterm:split-pane` | Split current session into a new pane with direction, profile, command, and name options | `-d` direction, `-p` profile, `-c` command, `-n` name |
| `iterm:list-panes` | List all panes across windows and tabs in table or JSON format with optional filtering | `-f` format (table/json), `-w` window filter, `-t` tab filter, `--dry-run` |
| `iterm:close-pane` | Close panes by substring pattern matching on session names with confirmation prompts | `<pattern>` argument, `--force`, `-w` window filter, `-t` tab filter |

## Decision Tree

```
User Request
├─ Need a separate workspace or full-width terminal?
│   └─ Yes → Use tab-management skill (iterm:open-tab)
├─ Need to create a window first (none exist)?
│   └─ Yes → Use tab-management skill (iterm:open-tab)
│       (pane-management requires an existing window)
└─ Want side-by-side panes in the current tab?
    └─ Yes → Use pane-management skill
        ├─ Create a new pane?
        │   └─ Use iterm:split-pane — which direction?
        │       ├─ "right", "side by side", "beside" → -d vertical
        │       └─ "below", "under", "stacked", "bottom" → -d horizontal
        ├─ See current pane layout?
        │   └─ Use iterm:list-panes
        │       ├─ Quick visual check → default table format
        │       └─ Programmatic parsing → -f json
        └─ Remove a pane?
            └─ Use iterm:close-pane <pattern>
                ├─ Preview first → --dry-run "pattern"
                ├─ With confirmation → "pattern"
                └─ Automated (no prompts) → --force "pattern"
```

## Direction Terminology

The `-d` flag for `iterm-split-pane.sh` accepts only two values: `vertical` and `horizontal`. The terminology follows iTerm2 convention where **vertical** means the divider is vertical (panes appear side by side, left/right) and **horizontal** means the divider is horizontal (panes appear stacked, top/bottom).

| Natural Language | Flag Value | Visual Result |
|------------------|------------|---------------|
| "right", "to the right" | `vertical` | New pane appears to the right |
| "left", "to the left" | `vertical` | New pane appears to the right (splits always add right/below) |
| "below", "under", "underneath" | `horizontal` | New pane appears below |
| "above", "over", "on top" | `horizontal` | New pane appears below (splits always add below) |
| "side by side", "alongside", "beside" | `vertical` | Panes arranged left and right |
| "stacked", "top and bottom", "one above the other" | `horizontal` | Panes arranged top and bottom |

**Important clarifications:**
- iTerm2 splits always place the new pane to the **right** (vertical) or **below** (horizontal). You cannot split to create a pane to the left or above.
- If a user says "left" or "above", use the corresponding direction but note that the new pane still appears right/below. The existing content shifts.

## Natural Language Mapping

This table maps common user requests to exact script invocations. Every command listed has been verified against the script source.

### Split Scenarios

| User Says | Mapped To | Notes |
|-----------|-----------|-------|
| "split right" | `iterm-split-pane.sh -d vertical` | Default direction is already vertical; `-d vertical` is explicit |
| "split below" | `iterm-split-pane.sh -d horizontal` | Horizontal divider creates top/bottom layout |
| "split and run my tests" | `iterm-split-pane.sh -c "npm test"` | Uses default vertical direction; adjust command as needed |
| "split right and run tests in watch mode" | `iterm-split-pane.sh -d vertical -c "npm test -- --watch"` | Combine direction and command |
| "split below and start the dev server" | `iterm-split-pane.sh -d horizontal -c "npm run dev"` | Horizontal split with command execution |
| "split with the ZSH profile" | `iterm-split-pane.sh -p ZSH` | Profile name must match an iTerm2 profile exactly |
| "split and name it Logs" | `iterm-split-pane.sh -n Logs` | Sets the pane title for identification |
| "open a pane below with Devcontainer profile running build" | `iterm-split-pane.sh -d horizontal -p Devcontainer -c "npm run build" -n "Build"` | All flags combined |
| "split right and navigate to my project" | `iterm-split-pane.sh -d vertical -c "cd /workspace/repos/my-project"` | Use `-c` with `cd` for directory navigation, not `-d` |
| "preview the split without doing it" | `iterm-split-pane.sh --dry-run -d vertical` | Dry-run shows generated AppleScript |

### List Scenarios

| User Says | Mapped To | Notes |
|-----------|-----------|-------|
| "show me all panes" | `iterm-list-panes.sh` | Default table format; shows Window, Tab, Pane, Name columns |
| "list panes in window 1" | `iterm-list-panes.sh -w 1` | Window index is 1-based |
| "list panes as JSON" | `iterm-list-panes.sh -f json` | JSON output for programmatic parsing |
| "show panes in window 1, tab 2 as JSON" | `iterm-list-panes.sh -w 1 -t 2 -f json` | Filters combine with AND logic |
| "what panes are in tab 3" | `iterm-list-panes.sh -t 3` | Tab filter across all windows |

### Close Scenarios

| User Says | Mapped To | Notes |
|-----------|-----------|-------|
| "close the test pane" | `iterm-close-pane.sh "test"` | Substring match on session name (case-sensitive) |
| "force close all agent panes" | `iterm-close-pane.sh --force "agent"` | Skips confirmation prompt for multiple matches |
| "close panes matching 'worker' in window 2" | `iterm-close-pane.sh -w 2 "worker"` | Pattern is a positional argument after options |
| "preview which panes would be closed for 'dev'" | `iterm-close-pane.sh --dry-run "dev"` | Dry-run shows AppleScripts without executing |
| "close the Logs pane in window 1, tab 1" | `iterm-close-pane.sh -w 1 -t 1 "Logs"` | Combined window and tab filter with pattern |

### Agent Spawn Scenarios

| User Says | Mapped To | Notes |
|-----------|-----------|-------|
| "spawn an agent in a new pane" | `spawn-agent.sh --pane` | Uses default vertical direction and current directory |
| "spawn agent to the right to investigate auth" | `spawn-agent.sh --pane --direction vertical /workspace/repos/project "investigate auth"` | Positional args: worktree path then task description |
| "spawn agent below in a horizontal split" | `spawn-agent.sh --pane --direction horizontal` | Direction only applies when `--pane` is set |

### Ambiguous Cases

| User Says | Resolution | Notes |
|-----------|------------|-------|
| "open a terminal" | Use **tab-management** skill (`iterm-open-tab.sh`) | Creates a separate workspace in a new tab; pane-management splits within existing tab |
| "run something on the side" | Use **pane-management** skill (`iterm-split-pane.sh -d vertical`) | "On the side" implies side-by-side layout within the current tab |
| "I need another shell" | Depends on context: tab-management for isolated workspace, pane-management for quick side panel | Ask the user whether they want an independent tab or a split pane |
| "put the logs somewhere I can see them" | Use **pane-management** skill (`iterm-split-pane.sh -d horizontal -c "tail -f logs"`) | "Somewhere I can see" suggests visible alongside current work, i.e., a pane |

## Common Scenarios

### Scenario 1: Split for Agent Work

**Goal:** Spawn a Claude agent in an adjacent pane so you can continue working in your current session while the agent handles a separate task.

**Steps:**

1. Split the current session vertically to create a side-by-side layout:
   ```bash
   iterm-split-pane.sh -d vertical -n "Agent: auth fix"
   ```

2. In the new pane, start a Claude agent with a task:
   ```bash
   iterm-split-pane.sh -d vertical -c "cd /workspace/repos/my-project && echo 'investigate the auth timeout in src/auth.ts' | claude --dangerously-skip-permissions" -n "Agent: auth fix"
   ```

**Outcome:** The agent runs in the right pane working on the auth investigation while you continue editing in the left pane. The pane title "Agent: auth fix" makes it easy to identify later.

### Scenario 2: Split for Test Monitoring

**Goal:** See test output continuously in a split pane while editing code in the main pane.

**Steps:**

1. Split horizontally to create a stacked layout with tests running below:
   ```bash
   iterm-split-pane.sh -d horizontal -c "cd /workspace/repos/my-project && npm test -- --watch" -n "Tests"
   ```

2. The test watcher starts immediately in the bottom pane. As you save files in the top pane, test results update automatically below.

**Outcome:** Tests run in the bottom pane in watch mode. The top pane remains your primary editing workspace. The pane title "Tests" identifies the pane in listings.

### Scenario 3: Multi-Pane Development Layout

**Goal:** Create a 3-pane layout in a single tab with editing space, test output, and log tailing.

**Steps:**

1. Split vertically to create a right-side pane for test output:
   ```bash
   iterm-split-pane.sh -d vertical -c "cd /workspace/repos/my-project && npm test -- --watch" -n "Tests"
   ```

2. Split the new pane horizontally to add a log tail below it:
   ```bash
   iterm-split-pane.sh -d horizontal -c "tail -f /workspace/repos/my-project/logs/app.log" -n "Logs"
   ```

3. Verify the layout by listing panes in the current tab:
   ```bash
   iterm-list-panes.sh -t 1
   ```

**Outcome:** Three panes in one tab: the original editing pane on the left, tests in the top-right, and logs in the bottom-right. Each pane has a descriptive title visible in the listing.

### Scenario 4: List and Inspect Pane Layout

**Goal:** See the current pane organization across all windows and tabs to understand what is running where.

**Steps:**

1. List all panes in table format for a quick visual overview:
   ```bash
   iterm-list-panes.sh
   ```
   Output:
   ```
   Window  Tab  Pane  Name
   1       1    1     Devcontainer
   1       1    2     Tests
   1       1    3     Logs
   1       2    1     claude-code-plugins
   ```

2. List panes in the current tab as JSON for programmatic use:
   ```bash
   iterm-list-panes.sh -w 1 -t 1 -f json
   ```

3. Filter to a specific window to see only its panes:
   ```bash
   iterm-list-panes.sh -w 1
   ```

**Outcome:** You can see every pane's window index, tab index, pane index, and session name. JSON output is useful for scripting; table output gives a quick visual check. Filters narrow the view to specific windows or tabs.

### Scenario 5: Pane Cleanup After Agents Complete

**Goal:** Close multiple agent panes that have finished their work, keeping only the main development pane.

**Steps:**

1. List panes to see which ones match the agent naming pattern:
   ```bash
   iterm-list-panes.sh
   ```
   Output:
   ```
   Window  Tab  Pane  Name
   1       1    1     Devcontainer
   1       1    2     Agent: auth fix
   1       1    3     Agent: test refactor
   1       2    1     claude-code-plugins
   ```

2. Preview which panes would be closed using dry-run:
   ```bash
   iterm-close-pane.sh --dry-run "Agent:"
   ```

3. Close all agent panes (skip confirmation since you already previewed):
   ```bash
   iterm-close-pane.sh --force "Agent:"
   ```

**Outcome:** Both "Agent: auth fix" and "Agent: test refactor" panes are closed. The main "Devcontainer" pane and the "claude-code-plugins" tab remain open. Panes are closed in reverse order to prevent index shifting issues.

### Scenario 6: Spawn Agent in Pane via spawn-agent.sh

**Goal:** Use the `spawn-agent.sh` wrapper to spawn a Claude agent in a split pane with a single command, instead of manually building the split and agent command.

**Steps:**

1. Spawn an agent in a vertical split pane with a task description:
   ```bash
   spawn-agent.sh --pane --direction vertical /workspace/repos/my-project "investigate the failing CI pipeline"
   ```

2. Or spawn an agent in a horizontal split for a stacked layout:
   ```bash
   spawn-agent.sh --pane --direction horizontal /workspace/repos/my-project "refactor the database connection pool"
   ```

3. Spawn an agent in a pane using defaults (vertical direction, current directory):
   ```bash
   spawn-agent.sh --pane
   ```

**Outcome:** The wrapper delegates to `iterm-split-pane.sh` with the correct flags, builds the Claude command with the task description piped in, and sets the pane name from the task. The agent starts running in the new pane immediately. If the plugin script is unavailable, spawn-agent.sh falls back to its built-in AppleScript implementation.

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

### iterm-list-panes.sh

**Purpose:** List all panes across windows and tabs with optional filtering.

**Usage:**
```bash
iterm-list-panes.sh [OPTIONS]
```

**Flags:**

| Flag | Long Form | Description | Default |
|------|-----------|-------------|---------|
| `-f` | `--format FORMAT` | Output format: `table` or `json` | `table` |
| `-w` | `--window INDEX` | Filter to specific window (1-based) | (all windows) |
| `-t` | `--tab INDEX` | Filter to specific tab (1-based) | (all tabs) |
| | `--dry-run` | Show AppleScript without executing | (false) |
| `-h` | `--help` | Show help message | |

**Output Formats:**

- **table** (default): ASCII table with columns `Window`, `Tab`, `Pane`, `Name`. Names longer than 30 characters are truncated with `...`.

  ```
  Window  Tab  Pane  Name
  1       1    1     Devcontainer
  1       1    2     Tests
  1       2    1     claude-code-plugins
  2       1    1     System Monitor
  ```

- **json**: Nested JSON object with `windows` array containing `tabs` arrays containing `panes` arrays. Each pane has `index` and `name` fields.

  ```json
  {
    "windows": [
      {
        "index": 1,
        "tabs": [
          {
            "index": 1,
            "panes": [
              {"index": 1, "name": "Devcontainer"},
              {"index": 2, "name": "Tests"}
            ]
          }
        ]
      }
    ]
  }
  ```

**Examples:**

```bash
# List all panes in default table format
iterm-list-panes.sh

# List panes in window 1 only
iterm-list-panes.sh -w 1

# List panes as JSON for programmatic parsing
iterm-list-panes.sh -f json

# List panes in window 1, tab 2 (filters combine with AND logic)
iterm-list-panes.sh -w 1 -t 2

# List panes in tab 3 across all windows
iterm-list-panes.sh -t 3

# JSON output filtered to a specific window
iterm-list-panes.sh --format json --window 1

# Preview AppleScript without executing
iterm-list-panes.sh --dry-run
```

**Exit Codes:**

See the [Exit Codes](#exit-codes) section below. This script uses codes 0 (success), 1 (connection failure), 2 (iTerm2 unavailable), and 3 (invalid arguments).

### iterm-close-pane.sh

**Purpose:** Close panes matching a pattern in their session name.

**Usage:**
```bash
iterm-close-pane.sh [OPTIONS] <pattern>
```

**Arguments:**

| Argument | Required | Description |
|----------|----------|-------------|
| `pattern` | Yes | String to match in pane session name (case-sensitive, substring match) |

**Flags:**

| Flag | Long Form | Description | Default |
|------|-----------|-------------|---------|
| `-w` | `--window INDEX` | Limit to specific window (1-based) | (all windows) |
| `-t` | `--tab INDEX` | Limit to specific tab (1-based) | (all tabs) |
| | `--force` | Skip confirmation prompt for multiple matches | (interactive) |
| | `--dry-run` | Show what would be closed without executing | (false) |
| `-h` | `--help` | Show help message | |

**Confirmation Flow:**

- When multiple panes match the pattern, the user is prompted to confirm before closing: `Found N matching panes. Close them all? [y/N]:`
- Use `--force` to bypass the confirmation prompt (useful for automation and scripting)
- Single-match closures proceed without prompting

**Behavior:**

- Pattern matching is **case-sensitive substring match**, not regex. The pattern `"agent"` matches `"Agent: auth"` only if the casing matches exactly.
- Use quotes for patterns containing spaces: `iterm-close-pane.sh "worktree: feature"`
- Panes are closed in reverse order to prevent index shifting bugs
- Closing the last pane in a tab closes the tab. Closing the last tab in a window closes the window.
- Exit code 4 (`EXIT_NO_MATCH`) is returned when no panes match the provided pattern

**Examples:**

```bash
# Close panes with "agent:" in session name
iterm-close-pane.sh "agent:"

# Force close without confirmation prompt
iterm-close-pane.sh --force "cleanup"

# Close panes matching "test" in window 1 only
iterm-close-pane.sh -w 1 "test"

# Close panes matching "worker" in tab 2 only
iterm-close-pane.sh -t 2 "worker"

# Close panes in window 2, tab 1 with pattern
iterm-close-pane.sh --force -w 2 -t 1 "worktree: feature"

# Preview which panes would be closed (dry-run)
iterm-close-pane.sh --dry-run "feature-branch"
```

**Exit Codes:**

See the [Exit Codes](#exit-codes) section below. This script uses codes 0 (success), 1 (connection failure), 2 (iTerm2 unavailable), 3 (invalid arguments), and 4 (no panes match pattern).

## Execution Contexts

The script automatically detects whether it is running on the macOS host or inside a container and adapts its execution strategy. This detection uses the shared `iterm-utils.sh` from the tab-management skill.

- **Host mode**: AppleScript executed directly via `osascript` (~100ms latency)
- **Container mode**: AppleScript base64-encoded and sent via SSH to `host.docker.internal` (~500ms latency)

**Pane-specific difference:** Pane operations require an existing window and will not create one. In both modes, the script targets the `first window` in its AppleScript. If no window exists, the script returns "NO_WINDOWS" (exit code 2). Use `iterm:open-tab` to create a window first.

See the tab-management SKILL.md section "Execution Contexts" for the complete detection logic diagram, host/container mode details, and behavior comparison table.

## Exit Codes

Codes 0-3 are defined in `iterm-utils.sh` (shared across all iterm skills). Code 4 is defined in `iterm-close-pane.sh`.

| Code | Constant | Description | Used By |
|------|----------|-------------|---------|
| 0 | EXIT_SUCCESS | Operation completed successfully | All scripts |
| 1 | EXIT_CONNECTION_FAIL | SSH connection to host failed | All scripts (container mode) |
| 2 | EXIT_ITERM_UNAVAILABLE | iTerm2 not running or not accessible | All scripts |
| 3 | EXIT_INVALID_ARGS | Invalid arguments or configuration | All scripts |
| 4 | EXIT_NO_MATCH | No panes matched the specified pattern | iterm-close-pane.sh |

**Example Error Handling:**
```bash
#!/bin/bash
if iterm-close-pane.sh --force "agent:"; then
    echo "Panes closed successfully"
else
    exit_code=$?
    case $exit_code in
        1) echo "Connection failed - check SSH config" ;;
        2) echo "iTerm2 not available" ;;
        3) echo "Invalid arguments" ;;
        4) echo "No panes matched pattern" ;;
        *) echo "Unknown error: $exit_code" ;;
    esac
    exit $exit_code
fi
```

## Troubleshooting

### Split-Specific Issues

**"NO_WINDOWS" returned**

The script returns "NO_WINDOWS" instead of splitting a pane. No iTerm2 windows are open. Unlike tab-management (which can create new windows), pane-management requires an existing window to split within.

Solution:
1. Open iTerm2 and ensure at least one window exists
2. Or use the tab-management skill first to create a tab/window:
   ```bash
   iterm-open-tab.sh -d /workspace
   ```
3. Then split the pane:
   ```bash
   iterm-split-pane.sh -d vertical
   ```

**"Invalid direction" (exit code 3)**

The `-d` flag received a value other than `vertical` or `horizontal`. A common mistake is passing a directory path to `-d` (which sets direction, not directory).

Solution:
- Use only `vertical` or `horizontal` with `-d`:
  ```bash
  iterm-split-pane.sh -d vertical
  iterm-split-pane.sh -d horizontal
  ```
- To navigate to a directory, use `-c` with a `cd` command:
  ```bash
  iterm-split-pane.sh -c "cd /workspace/repos/my-project"
  ```

**"Profile not found" / AppleScript execution failed (exit code 1)**

The profile specified with `-p` does not exist in iTerm2, or AppleScript permissions have not been granted.

Solution:
1. Use `--dry-run` to inspect generated AppleScript:
   ```bash
   iterm-split-pane.sh --dry-run -d vertical -p "Devcontainer"
   ```
2. Verify the profile exists in iTerm2 Preferences > Profiles
3. Grant permissions in System Preferences > Privacy & Security > Automation

### List-Specific Issues

**Empty output / No panes found**

The list command returns no rows or an empty table. This occurs when no iTerm2 windows are open, or when the applied filters exclude all panes.

Solution:
1. Verify iTerm2 has at least one window open
2. Run without filters first to see all panes:
   ```bash
   iterm-list-panes.sh
   ```
3. Then apply specific window or tab filters once you know the correct indices

**Filter not matching expected panes**

The `-w` or `-t` filter returns fewer panes than expected or none at all. Window and tab indices are 1-based. Using a 0-based index or an index that exceeds the window/tab count returns no results.

Solution:
1. List all panes without filters to see the actual indices:
   ```bash
   iterm-list-panes.sh
   ```
2. Use the exact window and tab indices from the output
3. Remember filters combine with AND logic: `-w 1 -t 2` shows only panes in window 1 AND tab 2

**JSON output issues**

If JSON output appears malformed or truncated, the most likely cause is an iTerm2 session name containing special characters that interfere with the delimiter parsing.

Solution:
1. Compare table and JSON output for the same filter to verify data consistency:
   ```bash
   iterm-list-panes.sh -f table
   iterm-list-panes.sh -f json
   ```
2. If the issue persists, report it as a bug with the output of both commands

### Close-Specific Issues

**Exit code 4: No panes matched pattern**

The pattern provided to `iterm-close-pane.sh` does not match any pane session names. Pattern matching is case-sensitive substring match, not regex.

Solution:
1. List panes first to verify the exact session names:
   ```bash
   iterm-list-panes.sh
   ```
2. Check case-sensitivity: `"Agent"` does not match `"agent"`
3. Use `--dry-run` to preview what would be matched:
   ```bash
   iterm-close-pane.sh --dry-run "your-pattern"
   ```

**Last pane closes the entire tab**

When the last pane in a tab is closed, the tab itself closes. If it is the last tab in a window, the window closes. This is expected iTerm2 behavior, not a bug.

Solution:
1. List panes before closing to check the pane count in the target tab:
   ```bash
   iterm-list-panes.sh -w 1 -t 1
   ```
2. If the tab should remain open, ensure at least one pane will survive the close operation

**Confirmation prompt blocks automation**

When multiple panes match the pattern, the script prompts for confirmation interactively. This blocks non-interactive scripts and automation pipelines.

Solution:
- Use the `--force` flag to bypass the confirmation prompt:
  ```bash
  iterm-close-pane.sh --force "agent:"
  ```
- Single-match closures proceed without prompting regardless of `--force`

### Infrastructure Issues

For SSH connectivity, HOST_USER configuration, `iterm-utils.sh` sourcing failures, and AppleScript permission issues, see the tab-management SKILL.md Troubleshooting section. These infrastructure issues are shared across tab and pane management skills and are documented in detail there.

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

## Recommended Pane Limits

For agent workflows and concurrent task monitoring:
- **Optimal:** 2-3 panes per tab
  - Example: Main pane + agent pane
  - Example: Editor + test output + logs
- **Maximum:** 3 panes recommended
  - Beyond 3 panes, readability decreases
  - Window size becomes constraining factor

**When to Use Tabs Instead:**
- Need 4+ separate views
- Need full-width terminal for each task
- Need workspace isolation (different repos)
- Spawning multiple Claude agents (use tabs for better isolation)

Use the tab-management skill to create additional tabs when pane limits are reached.

## Integration

### spawn-agent.sh Pane Mode

The devcontainer `spawn-agent.sh` script supports spawning Claude agents directly in panes:

**Flags:**
- `--pane`: Spawn agent in a new pane instead of a new tab
- `--direction <vertical|horizontal>`: Specify split direction (requires --pane)

**Example:**
```bash
# Spawn agent in vertical pane (right side)
spawn-agent.sh --pane --direction vertical
```

**Behavior:**
- `spawn-agent.sh` detects the iterm plugin and delegates to `iterm-split-pane.sh`
- If plugin not available, falls back to original tab-based behavior
- Inherits profile and context from current pane

### Combining Pane and Tab Operations

You can mix pane and tab management in workflows:

**Example: Multi-Agent Workflow**
1. Create new tab for agent workspace: `iterm-open-tab.sh -n "Agents"`
2. Split pane for first agent: `spawn-agent.sh --pane --direction vertical`
3. Split again for second agent: `iterm-split-pane.sh -d horizontal`

### Cleanup Workflows

After completing agent work:
1. List panes to verify layout: `iterm-list-panes.sh`
2. Close agent panes by pattern: `iterm-close-pane.sh "Agent:"`
3. Close entire tab if no longer needed: `iterm-close-tab.sh "Agents"`

## Related

**Skills:**
- [tab-management](../tab-management/SKILL.md) - Opening, listing, and closing iTerm2 tabs
- [iterm-utils](../tab-management/scripts/iterm-utils.sh) - Shared utilities for context detection and AppleScript execution

**Scripts:**
- [spawn-agent.sh](/workspace/.devcontainer/scripts/spawn-agent.sh) - Spawn Claude agents with pane/tab mode
- [iterm-split-pane.sh](./scripts/iterm-split-pane.sh) - Split pane script
- [iterm-list-panes.sh](./scripts/iterm-list-panes.sh) - List panes script
- [iterm-close-pane.sh](./scripts/iterm-close-pane.sh) - Close panes script

**References:**
- [AppleScript Reference](../tab-management/references/applescript-reference.md) - iTerm2 AppleScript patterns (includes split pane operations after Phase 2 completion)
