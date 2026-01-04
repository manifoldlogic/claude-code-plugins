---
name: worktree-spawn
description: Orchestration script for spawning git worktrees in devcontainer environments with iTerm tab and VS Code workspace integration. Automates the complete workflow of creating worktrees, opening terminal tabs, and updating workspace files from either host or container contexts.
---

# Worktree Spawn Skill

**Last Updated:** 2025-12-23
**Script Source:** `/workspace/.devcontainer/scripts/spawn-worktree.sh`

## Overview

The spawn-worktree.sh script orchestrates the complete worktree creation workflow by combining three operations into a single command:

1. Create git worktree using CrewChief CLI
2. Open new iTerm2 tab pointed at the worktree
3. Add worktree folder to VS Code workspace file

Unlike the basic `ccwt` command which only creates worktrees, spawn-worktree.sh provides full environment integration for devcontainer-based development.

**IMPORTANT PREREQUISITE:** This script is designed exclusively for devcontainer environments. It requires:
- Running inside a devcontainer OR on the macOS host with container access
- Docker Desktop for macOS
- iTerm2 for terminal integration
- VS Code workspace files for editor integration

The script automatically detects whether it's running on the host or inside the container and adjusts its execution strategy accordingly.

## Decision Tree

### Use spawn-worktree.sh when:
- Working in a devcontainer environment
- You want worktree + iTerm tab + workspace folder in one command
- Starting new feature work that needs full environment setup
- You have iTerm2 and want automatic tab creation
- You're using VS Code multi-root workspaces

### Use ccwt (CrewChief CLI) when:
- You only need worktree creation (no tabs/workspace)
- Working outside a devcontainer
- Scripting or automation where iTerm/workspace aren't needed
- You want fine-grained control over each operation
- Maximum portability across different setups

### Use standard git worktree when:
- Not using CrewChief CLI at all
- Working in non-devcontainer environments
- Simple worktree workflows without orchestration

## Prerequisites

### Environment Requirements

**For Container Execution:**
- Running inside the devcontainer
- `HOST_USER` environment variable configured in devcontainer.json
- SSH access to `host.docker.internal` configured (via post-start.sh)
- SSH keys mounted at `~/.ssh/id_ed25519`
- Git repositories in `/workspace/repos` directory
- CrewChief CLI (ccwt command) installed in container
- workspace-folder.sh script available for VS Code workspace updates

**For Host Execution:**
- macOS operating system (for iTerm2 integration)
- Docker Desktop installed and running
- Running devcontainer accessible via docker compose
- iTerm2 installed at `/Applications/iTerm.app`
- jq installed for workspace updates (`brew install jq`)
- Helper scripts available:
  - open-devcontainer.sh
  - workspace-folder.sh

### Verification Commands

Check prerequisites before running spawn-worktree.sh:

```bash
# Verify execution context
uname  # Darwin = host, Linux = container

# Check Docker (host only)
docker info

# Check container status (host only)
docker compose -f ~/.devcontainer/docker-compose.yml ps

# Check CrewChief CLI
which ccwt

# Check iTerm2 (host only)
ls /Applications/iTerm.app

# Check jq (host only, if updating workspace)
which jq

# Check SSH to host (container only)
ssh -o BatchMode=yes -o ConnectTimeout=5 ${HOST_USER}@host.docker.internal "echo OK"

# Verify workspace-folder.sh script
ls ~/.devcontainer/scripts/workspace-folder.sh
```

## Usage

### CLI Syntax

```bash
spawn-worktree.sh <worktree-name> --repo <repository> [OPTIONS]
```

### Required Arguments

- `worktree-name` - Name for the new worktree (alphanumeric, hyphens, underscores only)
- `-r, --repo REPO` - Repository name (must exist in `/workspace/repos`)

### Optional Arguments

- `-b, --branch BRANCH` - Base branch to branch from (default: "main")
- `-p, --profile PROFILE` - iTerm2 profile name (default: from ITERM_PROFILE or "Default")
- `-w, --workspace FILE` - VS Code workspace file path (default: from WORKSPACE_FILE or auto-detect)
- `-n, --name DISPLAY_NAME` - Display name for workspace folder (default: "<repo> (<worktree>)")
- `--skip-tab` - Skip opening iTerm2 tab (only create worktree)
- `--skip-workspace` - Skip adding to VS Code workspace (only create worktree and tab)
- `--dry-run` - Show what would be done without making changes
- `-h, --help` - Show help message and exit

### Environment Variables

All environment variables can be overridden by CLI flags (flags take precedence):

- `HOST_USER` - macOS host username (required for container mode)
  - Set in devcontainer.json: `"remoteEnv": {"HOST_USER": "your-username"}`
  - Used for SSH-based iTerm tab opening from container

- `ITERM_PROFILE` - iTerm2 profile name for new tabs
  - Default: "Default"
  - Overridden by `-p/--profile` flag

- `WORKSPACE_FILE` - Path to VS Code workspace file
  - Default: Auto-detect `/workspace/.vscode/workspace.code-workspace`
  - Overridden by `-w/--workspace` flag

- `DEVCONTAINER_SERVICE` - Docker compose service name (host mode only)
  - Default: "devcontainer"

- `COMPOSE_FILE` - Path to docker-compose.yml (host mode only)
  - Default: Auto-detect from script location (searches up 3 levels)

## Examples

### 1. Basic Usage - Create worktree with all defaults

```bash
spawn-worktree.sh feature-auth --repo myproject
```

**Output:**
```
[INFO] Creating worktree 'feature-auth' for repository 'myproject' from branch 'main'...
[OK] Worktree created: /workspace/repos/myproject/feature-auth
[INFO] Opening iTerm tab for worktree...
[OK] iTerm tab opened
[INFO] Adding worktree to VS Code workspace...
[OK] Workspace updated
```

**Use case:** Standard workflow for starting new feature development. Creates the worktree from main branch, opens it in iTerm2 with default profile, and adds it to your workspace file for easy navigation in VS Code.

### 2. Custom Options - Custom base branch and iTerm profile

```bash
spawn-worktree.sh bugfix-login --repo myproject -b develop -p Development
```

**Output:**
```
[INFO] Creating worktree 'bugfix-login' for repository 'myproject' from branch 'develop'...
[OK] Worktree created: /workspace/repos/myproject/bugfix-login
[INFO] Opening iTerm tab for worktree...
[OK] iTerm tab opened
```

**Use case:** Working on a bugfix that needs to branch from develop instead of main, using a custom iTerm2 profile (e.g., "Development") that might have different colors or settings to visually distinguish development work.

### 3. Custom Display Name - Different display name in workspace

```bash
spawn-worktree.sh feat-user-auth-system --repo myproject -n "Feature: User Authentication"
```

**Output:**
```
[INFO] Creating worktree 'feat-user-auth-system' for repository 'myproject'...
[OK] Worktree created: /workspace/repos/myproject/feat-user-auth-system
[OK] Workspace updated
```

**Use case:** Technical branch names can be long or unclear. Custom display names make workspace folders easier to identify in VS Code's file explorer while keeping git branch names concise and following naming conventions.

### 4. Skip Flags - Create worktree only, skip convenience features

```bash
spawn-worktree.sh quick-test --repo myproject --skip-tab --skip-workspace
```

**Output:**
```
[INFO] Creating worktree 'quick-test' for repository 'myproject' from branch 'main'...
[OK] Worktree created: /workspace/repos/myproject/quick-test
[INFO] iTerm tab: Skipped (--skip-tab)
[INFO] Workspace: Skipped (--skip-workspace)
```

**Use case:** Quickly create a worktree for temporary testing or experimentation without the overhead of opening tabs or modifying workspace. Useful for short-lived branches or automated scripts that just need the worktree path.

### 5. Dry-Run - Preview planned actions without making changes

```bash
spawn-worktree.sh feature-test --repo myproject --dry-run
```

**Output:**
```
==========================================
  DRY RUN - No changes will be made
==========================================

Would execute with resolved parameters:
  Repository: myproject
  Worktree name: feature-test
  Base branch: main (default)
  iTerm profile: Default (default)
  Workspace file: /workspace/.vscode/workspace.code-workspace
  Display name: myproject (feature-test) (default)

Commands that would run:

  1. Create worktree:
     docker compose -f ~/.devcontainer/docker-compose.yml exec -T devcontainer \
       crewchief worktree create feature-test --repo myproject --branch main
     Expected path: /workspace/repos/myproject/feature-test

  2. Open iTerm tab:
     ~/.devcontainer/scripts/open-devcontainer.sh -d /workspace/repos/myproject/feature-test -p "Default"

  3. Update workspace:
     ~/.devcontainer/scripts/workspace-folder.sh add repos/myproject/feature-test --name "myproject (feature-test)"
```

**Use case:** Verify configuration and preview all actions before executing. Helpful for understanding what the script will do, debugging issues, or confirming environment variable resolution and default values.

### 6. Script Integration - Use from another script with exit code checking

```bash
#!/bin/bash
# Example: Automated worktree creation with error handling
if output=$(spawn-worktree.sh feature-branch --repo myproject 2>&1); then
    # Extract worktree path from output
    path=$(echo "$output" | grep "Worktree created:" | awk '{print $4}')
    echo "Success! Created worktree at: $path"

    # Continue with additional automation
    cd "$path" && npm install
else
    exit_code=$?
    echo "Failed to create worktree (exit code $exit_code)"

    # Handle specific error cases
    case $exit_code in
        1) echo "Docker or container issue - check if container is running" ;;
        2) echo "Missing prerequisites - install required tools" ;;
        3) echo "Invalid arguments - check syntax" ;;
        4) echo "Worktree creation failed - check if branch already exists" ;;
    esac
    exit $exit_code
fi
```

**Use case:** Integrate spawn-worktree.sh into automated workflows or CI/CD pipelines. Exit codes allow proper error handling, and stdout can be parsed to extract the created worktree path for subsequent operations.

## Execution Modes

The script automatically detects its execution environment and adapts its behavior:

### Mode Detection Flowchart

```
Start
  |
  v
Check: uname != "Darwin"?
  |
  ├─ Yes --> CONTAINER MODE
  |
  v
Check: /.dockerenv exists?
  |
  ├─ Yes --> CONTAINER MODE
  |
  v
Check: /proc/1/cgroup contains "docker"?
  |
  ├─ Yes --> CONTAINER MODE
  |
  v
HOST MODE
```

The `is_container()` function uses multiple checks to reliably detect the execution environment:
1. Primary check: Operating system is not macOS (Darwin)
2. Secondary check: Docker environment file exists at `/.dockerenv`
3. Fallback: Process control group contains "docker" identifier

### Host vs Container Behavior Comparison

| Operation | Host Mode | Container Mode |
|-----------|-----------|----------------|
| **Worktree Creation** | `docker compose exec` to run ccwt in container | Direct `ccwt` execution |
| **iTerm Tab Opening** | Direct AppleScript via open-devcontainer.sh | SSH to host.docker.internal + remote osascript |
| **Workspace Update** | Direct workspace-folder.sh execution | Direct workspace-folder.sh execution |
| **Environment Requirements** | Docker Desktop, iTerm2, jq | HOST_USER env var, SSH configured |
| **Prerequisites Check** | Docker daemon, container status, macOS | SSH connectivity, ccwt availability |

**Key Difference:** Container mode uses SSH to execute AppleScript on the macOS host for iTerm tab creation, while host mode executes AppleScript directly. Both modes update the workspace file the same way since it's accessible from both contexts.

## Troubleshooting

### Exit Codes

The script uses specific exit codes to indicate different failure types:

| Exit Code | Meaning | Common Causes | Solution |
|-----------|---------|---------------|----------|
| **0** | Success | Worktree created successfully | (Success - no action needed) |
| **1** | Docker or container issues | Docker daemon not running, container not running | Start Docker Desktop: `docker compose up -d` |
| **2** | Missing prerequisites | jq not installed, iTerm2 not installed, helper scripts missing | Install required tools or use skip flags |
| **3** | Invalid arguments | Missing required args, invalid worktree name format, unknown flags | Check syntax: `spawn-worktree.sh --help` |
| **4** | Worktree creation failed | ccwt command error, invalid path returned | Check if branch already exists, verify repo name |

### Common Error Messages

**Container 'devcontainer' is not running**
```
[ERROR] Container 'devcontainer' is not running.
[ERROR] Start with: cd .devcontainer && docker compose up -d
```
**Solution:** Start the container first:
```bash
cd .devcontainer && docker compose up -d
```

**jq is required for workspace updates**
```
[ERROR] jq is required for workspace updates
[ERROR] Install with: brew install jq
[ERROR] Or skip workspace updates with: --skip-workspace
```
**Solution:** Install jq or skip workspace updates:
```bash
brew install jq
# OR
spawn-worktree.sh myworktree --repo myproject --skip-workspace
```

**iTerm2 is required for tab creation**
```
[ERROR] iTerm2 is required for tab creation
[ERROR] Install from: https://iterm2.com
[ERROR] Or skip tab creation with: --skip-tab
```
**Solution:** Install iTerm2 or skip tab creation:
```bash
# Install from https://iterm2.com
# OR
spawn-worktree.sh myworktree --repo myproject --skip-tab
```

**HOST_USER not set - cannot open iTerm tab remotely**
```
[WARN] HOST_USER not set - cannot open iTerm tab remotely
[WARN] Rebuild container to pick up HOST_USER from devcontainer.json
```
**Solution:** Set HOST_USER in devcontainer.json and rebuild:
```json
{
  "remoteEnv": {
    "HOST_USER": "your-macos-username"
  }
}
```

### Non-Fatal Warnings

These warnings don't cause the script to fail (exit code 0) but indicate optional features that didn't complete:

**Workspace update failed**
```
[WARN] Workspace update failed - add folder manually if needed
```
**Solution:** Verify workspace file exists at expected location, or specify with `-w`:
```bash
spawn-worktree.sh myworktree --repo myproject -w /path/to/workspace.code-workspace
```
If file doesn't exist, create it in VS Code first (File → Save Workspace As).

**iTerm tab creation failed**
```
[WARN] Failed to open iTerm tab (exit code ...)
[WARN] iTerm tab creation failed - open manually if needed
```
**Solution:** The worktree was created successfully. Open manually:
```bash
open-devcontainer.sh -d /workspace/repos/myproject/myworktree
```
Or check if iTerm2 is running and responding to AppleScript.

## Related

- **worktree-management** - Core git worktree operations using CrewChief CLI (create, use, merge, clean)
- **open-devcontainer.sh** - Opens iTerm2 tabs connected to devcontainer
- **workspace-folder.sh** - Manages folders in VS Code workspace files

For worktree lifecycle management (merging, cleaning up) after creation, see the worktree-management skill.
