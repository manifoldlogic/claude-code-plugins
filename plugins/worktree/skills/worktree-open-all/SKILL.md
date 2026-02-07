---
title: worktree-open-all
description: Open iTerm tabs for all worktrees of a repository
version: 1.0.0
skill_type: workflow
agent: general-purpose
---

# Worktree Open All Skill

**Last Updated:** 2026-02-07
**Script Source:** `/workspace/.devcontainer/scripts/open-all-worktrees.sh`

## Overview

The open-all-worktrees.sh script opens iTerm2 tabs for all non-main worktrees of a given repository in a single command. It enumerates worktrees using `crewchief worktree list`, filters out the main worktree, and opens a tab for each remaining worktree via the iTerm plugin.

This automates the common workflow of opening tabs for all active worktrees when starting a development session. Instead of running `spawn-worktree.sh` or `iterm-open-tab.sh` multiple times, a single command opens everything at once.

**Tab Naming Convention**: Tabs are named using the format `"<repo> <worktree>"` (e.g., `"crewchief MAPR-0001"`). This matches the naming convention used by `spawn-worktree.sh`, providing consistency across all worktree-related tab operations.

**Main Worktree Filtering**: The script automatically skips the main worktree. A worktree is considered "main" if its directory basename matches the repository name or is literally `"main"`. All other worktrees get tabs opened.

## Decision Tree

### Use open-all-worktrees.sh when:
- Starting a development session and need tabs for all active worktrees
- You have multiple worktrees for a repository and want them all open at once
- Resuming work after a container restart or terminal session reset
- You want a quick way to restore your terminal layout for a project

### Use spawn-worktree.sh when:
- You need to open a tab for only one specific worktree
- You are creating a new worktree (open-all-worktrees.sh does not create worktrees)
- You need VS Code workspace integration alongside tab creation

### Consider before running:
- By default, the script does not check for existing tabs. Running it twice will create duplicate tabs for the same worktrees. Use `--skip-existing` to avoid duplicates.
- Only non-main worktrees are opened. If your repository has no worktrees beyond main, nothing will be opened.
- Each tab takes a moment to create. With many worktrees, expect a brief wait.

## Prerequisites

### Environment Requirements

- Running inside the devcontainer
- CrewChief CLI (`crewchief` command) installed
- iTerm plugin (`iterm-open-tab.sh`) available at the expected path
- Repository must exist in `/workspace/repos`
- `HOST_USER` environment variable configured (for SSH-based tab opening from container)

### Verification Commands

```bash
# Check CrewChief CLI
command -v crewchief

# Check iTerm plugin
ls /workspace/repos/claude-code-plugins/ITERM/plugins/iterm/skills/tab-management/scripts/iterm-open-tab.sh

# List worktrees for a repository
cd /workspace/repos/<repo>/<repo> && crewchief worktree list
```

## Usage

### CLI Syntax

```bash
open-all-worktrees.sh --repo <repository> [OPTIONS]
```

### Required Arguments

- `-r, --repo REPO` - Repository name (must exist in `/workspace/repos`)

### Optional Arguments

- `-f, --filter PATTERN` - Only open worktrees matching the given pattern (uses `grep -E` extended regex). Non-matching worktrees are skipped with an info message. Useful for focusing on a subset of worktrees by ticket prefix, feature name, or other naming convention.
- `-p, --profile PROFILE` - iTerm2 profile name (default: from `ITERM_PROFILE` or `"Devcontainer"`)
- `-m, --max-tabs N` - Maximum number of tabs to open (default: unlimited). Useful for repositories with many worktrees to prevent overwhelming iTerm2.
- `--skip-existing` - Skip worktrees that already have open iTerm tabs. Checks existing tab names using the iTerm plugin's `iterm-list-tabs.sh` script. If the list-tabs script is unavailable, a warning is displayed and all tabs are opened normally (graceful fallback).
- `--dry-run` - Show planned operations without executing
- `-h, --help` - Show help message and exit

### Environment Variables

- `ITERM_PROFILE` - iTerm2 profile name for new tabs
  - Default: `"Devcontainer"`
  - Overridden by `-p/--profile` flag

- `ITERM_PLUGIN_DIR` - Path to the iTerm plugin directory
  - Default: `/workspace/repos/claude-code-plugins/ITERM/plugins/iterm`
  - Override to use a custom iTerm plugin installation path

### Exit Codes

| Exit Code | Meaning | Common Causes |
|-----------|---------|---------------|
| **0** | Success | Tabs opened, or no non-main worktrees to open |
| **3** | Invalid arguments | Missing `--repo`, unknown flags |
| **4** | Operation failed | `crewchief` command error, repository not found |

## Examples

### 1. Basic Usage - Open tabs for all worktrees

```bash
open-all-worktrees.sh --repo crewchief
```

**Output:**
```
[INFO] Enumerating worktrees for repository 'crewchief'...
[INFO] Found 3 worktree(s) to open
[OK] Opened tab: crewchief MAPR-0001
[OK] Opened tab: crewchief FEAT-auth
[OK] Opened tab: crewchief bugfix-login

==========================================
  Worktree Tab Opening Complete
==========================================

[INFO] Repository: crewchief
[INFO] Worktrees processed: 3
==========================================
```

**Use case:** Starting a development session. Opens tabs for all active worktrees so you can immediately switch between them. The main worktree is automatically skipped.

### 2. Custom Profile - Use a specific iTerm profile

```bash
open-all-worktrees.sh --repo crewchief --profile "Dark Profile"
```

**Output:**
```
[INFO] Enumerating worktrees for repository 'crewchief'...
[INFO] Found 2 worktree(s) to open
[OK] Opened tab: crewchief MAPR-0001
[OK] Opened tab: crewchief FEAT-auth

==========================================
  Worktree Tab Opening Complete
==========================================

[INFO] Repository: crewchief
[INFO] Worktrees processed: 2
==========================================
```

**Use case:** Using a specific iTerm2 profile (e.g., different colors or font settings) for all worktree tabs. Useful for visually distinguishing worktree tabs from other terminal tabs.

### 3. Dry Run - Preview what would be opened

```bash
open-all-worktrees.sh --repo crewchief --dry-run
```

**Output:**
```
==========================================
  DRY RUN - No changes will be made
==========================================

Repository: crewchief
Repo path:  /workspace/repos/crewchief/crewchief
Profile:    Devcontainer

Would open tabs for the following worktrees:

  1. Tab name: "crewchief MAPR-0001"
     Directory: /workspace/repos/crewchief/MAPR-0001
     Command: /path/to/iterm-open-tab.sh --name "crewchief MAPR-0001" --directory "/workspace/repos/crewchief/MAPR-0001" --profile "Devcontainer"

  2. Tab name: "crewchief FEAT-auth"
     Directory: /workspace/repos/crewchief/FEAT-auth
     Command: /path/to/iterm-open-tab.sh --name "crewchief FEAT-auth" --directory "/workspace/repos/crewchief/FEAT-auth" --profile "Devcontainer"

Delay between tabs: 200ms (sleep 0.2)

==========================================
```

**Use case:** Verify which worktrees will be opened before actually opening tabs. Helpful for confirming the correct repository and checking which worktrees are detected.

### 4. Limit Tabs - Open only the first N worktrees

```bash
open-all-worktrees.sh --repo crewchief --max-tabs 5
```

**Output:**
```
[INFO] Enumerating worktrees for repository 'crewchief'...
[INFO] Found 8 worktree(s) to open
[OK] Opened tab: crewchief MAPR-0001
[OK] Opened tab: crewchief FEAT-auth
[OK] Opened tab: crewchief bugfix-login
[OK] Opened tab: crewchief FEAT-dashboard
[OK] Opened tab: crewchief FEAT-api
[WARN] Reached maximum tab limit (5). Skipped 3 worktree(s).

==========================================
  Worktree Tab Opening Complete
==========================================

[INFO] Repository: crewchief
[INFO] Worktrees processed: 5
[INFO] Max tabs limit: 5
==========================================
```

**Use case:** When a repository has many worktrees (e.g., 20+), use `--max-tabs` to limit how many tabs are opened at once. This prevents overwhelming iTerm2 and keeps the terminal manageable. Combine with `--dry-run` to preview which worktrees will be included.

### 5. Filter by Pattern - Open only matching worktrees

```bash
open-all-worktrees.sh --repo crewchief --filter "MAPR-"
```

**Output:**
```
[INFO] Enumerating worktrees for repository 'crewchief'...
[INFO] Found 5 worktree(s) to open
[INFO] Skipping worktree (does not match filter): FEAT-auth
[INFO] Skipping worktree (does not match filter): bugfix-login
[OK] Opened tab: crewchief MAPR-0001
[OK] Opened tab: crewchief MAPR-0002
[OK] Opened tab: crewchief MAPR-0003

==========================================
  Worktree Tab Opening Complete
==========================================

[INFO] Repository: crewchief
[INFO] Worktrees processed: 3
==========================================
```

**Use case:** When you only want to open tabs for a specific set of worktrees. Common patterns:
- `--filter "MAPR-"` - Open only MapRoom-related worktrees
- `--filter "^feature-"` - Open worktrees starting with "feature-"
- `--filter "auth|login"` - Open worktrees containing "auth" or "login"
- `--filter ".*-[0-9]+$"` - Open worktrees ending with a number

### 6. Filter with Dry Run - Preview filtered results

```bash
open-all-worktrees.sh --repo crewchief --filter "MAPR-" --dry-run
```

**Output:**
```
==========================================
  DRY RUN - No changes will be made
==========================================

Repository: crewchief
Repo path:  /workspace/repos/crewchief/crewchief
Profile:    Devcontainer
Filter:     MAPR-

Would open tabs for the following worktrees:

  [SKIP] FEAT-auth (does not match filter)
  [SKIP] bugfix-login (does not match filter)
  1. Tab name: "crewchief MAPR-0001"
     Directory: /workspace/repos/crewchief/MAPR-0001
     Command: /path/to/iterm-open-tab.sh --name "crewchief MAPR-0001" --directory "/workspace/repos/crewchief/MAPR-0001" --profile "Devcontainer"

Delay between tabs: 200ms (sleep 0.2)

==========================================
```

**Use case:** Preview which worktrees will match the filter pattern before actually opening tabs. Combine `--filter` with `--dry-run` to verify the pattern selects the right worktrees.

### 7. Skip Existing Tabs - Avoid duplicates on repeated runs

```bash
open-all-worktrees.sh --repo crewchief --skip-existing
```

**Output:**
```
[INFO] Enumerating worktrees for repository 'crewchief'...
[INFO] Found 3 worktree(s) to open
[INFO] Skipping worktree (tab already exists): MAPR-0001
[OK] Opened tab: crewchief FEAT-auth
[OK] Opened tab: crewchief bugfix-login

==========================================
  Worktree Tab Opening Complete
==========================================

[INFO] Repository: crewchief
[INFO] Worktrees processed: 2
[INFO] Tabs skipped (already exist): 1
==========================================
```

**Use case:** When resuming a session or running the script multiple times, `--skip-existing` prevents duplicate tabs. The script queries iTerm2 for currently open tabs and skips any worktree whose tab is already open. This makes the script safe to run repeatedly (idempotent behavior).

### 8. Skip Existing with Dry Run - Preview skip behavior

```bash
open-all-worktrees.sh --repo crewchief --skip-existing --dry-run
```

**Output:**
```
==========================================
  DRY RUN - No changes will be made
==========================================

Repository: crewchief
Repo path:  /workspace/repos/crewchief/crewchief
Profile:    Devcontainer
Skip existing: yes

Would open tabs for the following worktrees:

  [SKIP] MAPR-0001 (tab already exists)
  1. Tab name: "crewchief FEAT-auth"
     Directory: /workspace/repos/crewchief/FEAT-auth
     Command: /path/to/iterm-open-tab.sh --name "crewchief FEAT-auth" --directory "/workspace/repos/crewchief/FEAT-auth" --profile "Devcontainer"

Delay between tabs: 200ms (sleep 0.2)

==========================================
```

**Use case:** Preview which tabs would be opened and which would be skipped before actually executing. Combine `--skip-existing` with `--dry-run` to verify the skip detection is working as expected.

### 9. No Worktrees Found

```bash
open-all-worktrees.sh --repo new-project
```

**Output:**
```
[INFO] Enumerating worktrees for repository 'new-project'...
[INFO] No non-main worktrees to open for repository 'new-project'
```

**Use case:** When a repository only has its main worktree (no feature branches checked out as worktrees), the script exits cleanly with exit code 0 and an informational message. This is expected behavior, not an error.

## Performance

The script introduces a 200ms delay between tab creations to prevent race conditions in iTerm2's AppleScript interface. Expected timing:

| Worktrees | Approximate Time |
|-----------|-----------------|
| 1 | ~100-500ms |
| 2 | ~400ms-1.2s |
| 4 | ~1-2.5s |
| 8 | ~2-5s |

Actual tab creation time depends on the execution mode:
- **Container mode** (SSH to host): ~300-500ms per tab
- **Host mode** (direct AppleScript): ~100-200ms per tab

The 200ms inter-tab delay accounts for iTerm2 needing time to fully initialize each tab before the next one is created. Without this delay, tabs may fail to open or receive incorrect configurations.

## Troubleshooting

### "No worktrees found" or "No non-main worktrees to open"

**Cause:** The repository only has its main worktree. No additional worktrees have been created.

**Solution:** This is expected behavior. Create worktrees first using `spawn-worktree.sh` or `ccwt`, then run open-all-worktrees.sh:
```bash
spawn-worktree.sh FEAT-0001 --repo crewchief
open-all-worktrees.sh --repo crewchief
```

### "iTerm plugin not available"

```
[WARN] iTerm plugin not available at: /path/to/iterm-open-tab.sh
[WARN] Cannot open tab for: worktree-name
```

**Cause:** The iTerm plugin script is not found at the expected path, or it is not executable.

**Solution:** Verify the plugin path and permissions:
```bash
ls -la /workspace/repos/claude-code-plugins/ITERM/plugins/iterm/skills/tab-management/scripts/iterm-open-tab.sh
```
If the plugin is at a different location, set the `ITERM_PLUGIN_DIR` environment variable to the correct path.

### "Repository not found"

```
[ERROR] Repository not found: my-repo
[ERROR] Checked: /workspace/repos/my-repo/my-repo and /workspace/repos/my-repo
```

**Cause:** The specified repository does not exist in `/workspace/repos`.

**Solution:** Verify the repository name and check that it exists:
```bash
ls /workspace/repos/
```
Repository names are case-sensitive. Ensure you are using the exact directory name.

### "crewchief worktree list failed"

```
[ERROR] crewchief worktree list failed (exit code N)
```

**Cause:** The CrewChief CLI encountered an error when listing worktrees.

**Solution:** Run the command manually to see detailed output:
```bash
cd /workspace/repos/<repo>/<repo> && crewchief worktree list
```
Common causes include the repository not being a valid git repository or CrewChief CLI not being installed.

### Duplicate tabs opened

**Cause:** The script was run without `--skip-existing`, so it does not check for existing tabs. Running it multiple times creates duplicate tabs for the same worktrees.

**Solution:** Use `--skip-existing` to prevent duplicates:
```bash
open-all-worktrees.sh --repo crewchief --skip-existing
```
This checks existing iTerm tabs by name and skips any worktree whose tab is already open. If duplicate tabs already exist, close them manually or use the iTerm plugin's close-tab functionality.

### Some tabs failed to open

```
[WARN] Failed to open tab for worktree: worktree-name (exit code N)
```

**Cause:** Individual tab creation failed, but other tabs may have succeeded. The script continues opening remaining tabs.

**Solution:** Check iTerm2 is running and accessible. In container mode, verify SSH connectivity to the host:
```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 ${HOST_USER}@host.docker.internal "echo OK"
```

## Integration with crewchief worktree list

The script relies on `crewchief worktree list` for worktree enumeration. The expected output format is:

```
[info] /workspace/repos/project/worktree-name [branch-name]
[info] /workspace/repos/project/main [main]
[info] /workspace/repos/project/project [master]
```

The script:
1. Runs `crewchief worktree list` from the repository directory
2. Extracts lines starting with `[info]`
3. Parses the worktree path (between `[info] ` prefix and ` [branch]` suffix)
4. Extracts the worktree name as the basename of the path
5. Filters out entries where the name matches the repository name or `"main"`
6. Opens tabs for all remaining worktrees

## Related Skills

- **worktree-spawn** - Create a new worktree with iTerm tab and VS Code workspace integration
- **worktree-cleanup** - Remove a worktree with automatic tab closing and workspace cleanup
- **iterm-open-tab** - Low-level iTerm tab opening (delegated to by this script)
- **worktree-management** - Core git worktree operations using CrewChief CLI
