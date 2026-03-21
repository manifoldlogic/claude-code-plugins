---
name: worktree-setup
description: Create a git worktree with VS Code workspace and cmux terminal setup
---

# Worktree Setup Skill

**Last Updated:** 2026-03-20
**Script Source:** `plugins/devx/skills/worktree-setup/scripts/setup-worktree.sh`

## Overview

The setup-worktree.sh script orchestrates the complete worktree creation and environment setup workflow by combining multiple operations into a single command:

1. Validate prerequisites (crewchief, workspace-folder.sh, cmux-check.sh)
2. Create the git worktree via CrewChief CLI (`crewchief worktree create`)
3. Add the worktree folder to the VS Code workspace file
4. Create a cmux terminal workspace
5. Open a devcontainer session in the new workspace
6. Navigate to the worktree directory
7. Launch claude in the new session

Unlike running `crewchief worktree create` manually, setup-worktree.sh provides end-to-end environment setup including terminal management and workspace integration.

**KEY FEATURES:**

- Full environment orchestration in a single command
- Graceful degradation when cmux or workspace tools are unavailable
- Dry-run mode to preview all planned actions
- Skip flags to bypass cmux or workspace steps selectively
- Two-step send pattern for reliable terminal command execution

> **cmux Execution Context:** cmux terminal commands in this skill execute via SSH to the macOS host using `cmux-ssh.sh`. The script is not on PATH and must be invoked by absolute path: `$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh`. See the cmux terminal-management SKILL.md for the full SSH execution model.

## The Two-Step Send Pattern

The cmux terminal management uses a **two-step send pattern** for all commands sent to the terminal session. Every command requires two calls to cmux-ssh.sh:

1. `cmux-ssh.sh send <workspace_id> "<command>"` -- Sends the command text to the terminal input buffer
2. `cmux-ssh.sh send-key <workspace_id> enter` -- Presses Enter to execute the command

**Why this is required:** The `send` command types text into the terminal but does not execute it. Without the separate `send-key enter` call, the command sits in the terminal prompt without executing. This is by design in tmux/cmux -- it allows composing multi-part commands and gives the caller control over exactly when execution happens.

**Example from the script (Step 5 - Open devcontainer session):**

```bash
# Step 1: Type the docker exec command into the terminal
cmux-ssh.sh send --workspace "$workspace_id" "docker exec -it $CONTAINER_NAME /bin/zsh"
# Step 2: Press Enter to execute it
cmux-ssh.sh send-key --workspace "$workspace_id" enter
# Wait for the container shell to be ready (polls read-screen for prompt)
cmux_wait_prompt "$workspace_id" "$CMUX_SSH_SCRIPT"
```

This pattern repeats for every command sent to the terminal: the `cd` navigation in Step 6 and the `claude` launch in Step 7 both use the same two-step approach.

## Readiness Verification

After each two-step send in Steps 4-6, the script verifies that the cmux operation has completed before proceeding. Instead of using fixed-duration `sleep` calls, setup-worktree.sh polls cmux subcommands to detect when the terminal is ready. This is provided by the `cmux-wait.sh` utility library, which the script sources from the cmux plugin at `plugins/cmux/skills/terminal-management/scripts/cmux-wait.sh`.

The library provides two polling functions:

- **`cmux_wait_workspace`** -- Used after creating a new workspace (Step 4). Polls `list-workspaces` via `cmux-ssh.sh` until the newly created workspace ID appears in the output. This confirms that the workspace is registered and ready to receive commands.

- **`cmux_wait_prompt`** -- Used after opening a devcontainer session via `docker exec` (Step 5) and after navigating to the worktree directory with `cd` (Step 6). Polls `read-screen` via `cmux-ssh.sh` and matches the terminal output against a shell prompt pattern using `grep -E`. This confirms that the previous command has finished executing and the shell is ready for the next command.

Both functions poll in a loop with configurable timeouts and intervals. If the timeout expires, the function logs a warning and returns a non-zero exit code. The script treats readiness timeouts as non-fatal -- it logs a warning and continues with the next step.

### Readiness Environment Variables

The following environment variables control polling behavior. Set them before running setup-worktree.sh to override the defaults.

| Variable                    | Default            | Description                                        |
| --------------------------- | ------------------ | -------------------------------------------------- |
| `CMUX_WAIT_WS_TIMEOUT`      | `5`                | Seconds to wait for workspace creation             |
| `CMUX_WAIT_PROMPT_TIMEOUT`  | `10`               | Seconds to wait for shell prompt after docker exec |
| `CMUX_WAIT_WS_INTERVAL`     | `0.3`              | Seconds between workspace polls                    |
| `CMUX_WAIT_PROMPT_INTERVAL` | `0.5`              | Seconds between prompt polls                       |
| `CMUX_PROMPT_PATTERN`       | `[^#\$%][\$#%] *$` | grep -E pattern to match shell prompt              |

### Fallback When cmux-wait.sh Is Missing

If `cmux-wait.sh` is not found at the expected path, the script defines stub functions that replicate the original sleep-based timing: `cmux_wait_workspace` sleeps for 0.5 seconds and `cmux_wait_prompt` sleeps for 2 seconds. A warning is logged when this fallback activates. The stub functions always return success (exit 0), so the rest of the script proceeds normally. This ensures backward compatibility when the cmux plugin does not include the polling library.

## DEVCONTAINER_NAME Environment Variable

The `DEVCONTAINER_NAME` variable tells setup-worktree.sh which Docker container to connect to when opening a devcontainer session in Step 5.

**How to set it:**

```bash
# Set before running setup-worktree.sh
export DEVCONTAINER_NAME="my-devcontainer-1"
setup-worktree.sh TICKET-1
```

Or inline:

```bash
DEVCONTAINER_NAME="my-devcontainer-1" setup-worktree.sh TICKET-1
```

**When to set it:**

- Set `DEVCONTAINER_NAME` when you know your container name and want deterministic behavior
- Set it in CI/CD or automated pipelines where auto-detection may not work
- Set it in tests to avoid Docker dependencies (e.g., `DEVCONTAINER_NAME=mock-container`)

**Auto-detection fallback:**
When `DEVCONTAINER_NAME` is not set, the script attempts to auto-detect the container:

```bash
docker ps --filter name=devcontainer --format '{{.Names}}' | head -1
```

Setting `DEVCONTAINER_NAME` explicitly is the preferred method. The docker auto-detection fallback may fail with a permission-denied error if the Docker socket is not accessible from within the container. When this happens, the script warns and skips cmux steps 5-7.

If auto-detection fails (no matching container found or Docker is inaccessible), the script warns and skips cmux steps 5-7. The worktree and workspace setup (steps 1-3) still complete successfully.

## Decision Tree

### Use setup-worktree.sh when:

- Starting work on a new ticket and you want a complete environment in one command
- You want git worktree + VS Code workspace + cmux terminal all set up together
- You are inside the devcontainer and want to spawn a parallel work environment

### Use setup-worktree.sh with --skip-cmux when:

- You want the worktree and workspace setup but prefer to manage your terminal manually
- cmux is not available or configured in your environment
- You are working in a non-tmux terminal and do not need remote session management

### Use setup-worktree.sh with --skip-workspace when:

- You want the worktree and terminal setup but do not use VS Code workspaces
- The workspace-folder.sh script is not available
- You manage your VS Code workspace configuration manually

### Use crewchief worktree create directly when:

- You only need the git worktree without any environment setup
- You are working outside the devcontainer
- You want full manual control over every step
- You are scripting and want to compose your own workflow

### Do NOT use setup-worktree.sh when:

- The worktree already exists (crewchief worktree create will fail)
- You want to merge or remove a worktree (use merge-worktree.sh or cleanup-worktree.sh instead)
- You are on a host machine without Docker (cmux steps will fail)

## Prerequisites

### Environment Requirements

**Required:**

- Running inside the devcontainer
- CrewChief CLI (`crewchief worktree create`) installed and on PATH
- Git repositories in `/workspace/repos` directory

**Optional (graceful degradation when absent):**

- `workspace-folder.sh` at `$WORKSPACE_FOLDER_SCRIPT` or `/workspace/.devcontainer/scripts/workspace-folder.sh` -- skipped if not found
- `cmux-check.sh` and `cmux-ssh.sh` at `$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/` -- cmux steps skipped if not found
- Docker CLI for container name auto-detection -- set `DEVCONTAINER_NAME` as alternative

### Verification Commands

```bash
# Check CrewChief CLI
command -v crewchief

# Check cmux scripts
ls "$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-check.sh"
ls "$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh"

# Check workspace-folder.sh
ls /workspace/.devcontainer/scripts/workspace-folder.sh

# Check container name (if DEVCONTAINER_NAME not set)
docker ps --filter name=devcontainer --format '{{.Names}}'
```

## Usage

### CLI Syntax

```bash
setup-worktree.sh <worktree-name> [OPTIONS]
```

The script must be run from inside a git repository. The worktree name is typically a ticket ID (e.g., `DEVX-1001`, `TICKET-123`). The repository is auto-detected from the current git root.

### Required Arguments

- `worktree-name` -- Name for the worktree (positional argument, typically a ticket ID)

### Optional Arguments

- `-b, --branch BRANCH` -- Base branch (default: `main`)
- `-w, --workspace FILE` -- VS Code workspace file path (overrides auto-detect)
- `--skip-cmux` -- Skip cmux workspace creation (steps 4-7)
- `--skip-workspace` -- Skip VS Code workspace update (step 3)
- `--dry-run` -- Preview planned operations without making changes
- `--verbose` -- Show cmux-ssh.sh invocations and output
- `-h, --help` -- Show help message and exit

### Environment Variables

- `CMUX_PLUGIN_DIR` -- Path to cmux plugin directory (default: `/workspace/repos/claude-code-plugins/claude-code-plugins/plugins/cmux`)
- `WORKSPACE_FOLDER_SCRIPT` -- Path to workspace-folder.sh (default: `/workspace/.devcontainer/scripts/workspace-folder.sh`)
- `DEVCONTAINER_NAME` -- Container name for docker exec (auto-detected via `docker ps` if not set)

## --dry-run Usage

The `--dry-run` flag previews all planned operations without making any changes. It resolves all parameters, validates the configuration, and shows exactly what commands would run.

**Example invocation:**

```bash
setup-worktree.sh TICKET-1 --dry-run
```

**Expected output format:**

```
==========================================
  DRY RUN - No changes will be made
==========================================

Resolved parameters:
  Worktree name: TICKET-1
  Repository: claude-code-plugins
  Git root: /workspace/repos/claude-code-plugins
  Base branch: main
  Worktree path: /workspace/repos/TICKET-1
  Workspace file: (auto-detect)
  Skip cmux: false
  Skip workspace: false

Planned operations:

[DRY-RUN] Step 1: Validate prerequisites
     Check: crewchief, workspace-folder.sh, cmux-check.sh

[DRY-RUN] Step 2: Create worktree
     (cd /workspace/repos/claude-code-plugins && crewchief worktree create TICKET-1 --branch main)

[DRY-RUN] Step 3: Update VS Code workspace
     workspace-folder.sh add /workspace/repos/TICKET-1

[DRY-RUN] Step 4: Create cmux workspace
     $CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh new-workspace
     cmux_wait_workspace <workspace_id>
     $CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh rename-workspace --workspace <workspace_id> TICKET-1

[DRY-RUN] Step 5: Open devcontainer session
     Container: <DEVCONTAINER_NAME>
     $CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh send --workspace <workspace_id> "docker exec -it <DEVCONTAINER_NAME> /bin/zsh"
     $CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh send-key --workspace <workspace_id> enter
     cmux_wait_prompt <workspace_id>

[DRY-RUN] Step 6: Navigate to worktree
     $CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh send --workspace <workspace_id> "cd /workspace/repos/TICKET-1"
     $CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh send-key --workspace <workspace_id> enter
     cmux_wait_prompt <workspace_id>

[DRY-RUN] Step 7: Launch claude
     $CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh send --workspace <workspace_id> "claude"
     $CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh send-key --workspace <workspace_id> enter

==========================================
```

With `--skip-cmux`, steps 4-7 show "SKIPPED (--skip-cmux)" instead of commands:

```
[DRY-RUN] Step 4: Create cmux workspace: SKIPPED (--skip-cmux)
[DRY-RUN] Step 5: Open devcontainer session: SKIPPED (--skip-cmux)
[DRY-RUN] Step 6: Navigate to worktree: SKIPPED (--skip-cmux)
[DRY-RUN] Step 7: Launch claude: SKIPPED (--skip-cmux)
```

With `--skip-workspace`, step 3 shows "SKIPPED (--skip-workspace)":

```
[DRY-RUN] Step 3: Update VS Code workspace: SKIPPED (--skip-workspace)
```

## Examples

### 1. Full Setup -- Create worktree with complete environment

```bash
setup-worktree.sh DEVX-1001
```

**Output:**

```
[INFO] Step 1: Validating prerequisites...
[OK] Prerequisites validated
[INFO] Step 2: Creating worktree 'DEVX-1001' in repo 'claude-code-plugins'...
[OK] Worktree created at /workspace/repos/DEVX-1001
[INFO] Step 3: Updating VS Code workspace...
[OK] VS Code workspace updated
[INFO] Step 4: Creating cmux workspace...
[OK] cmux workspace created: workspace:3
[INFO] Step 5: Opening devcontainer session...
[OK] Devcontainer session opened (container: my-devcontainer-1)
[INFO] Step 6: Navigating to worktree...
[OK] Navigated to /workspace/repos/DEVX-1001
[INFO] Step 7: Launching claude...
[OK] Claude launched

==========================================
  Worktree Setup Complete
==========================================

[OK] Worktree: DEVX-1001
[INFO] Repository: claude-code-plugins
[INFO] Path: /workspace/repos/DEVX-1001
[INFO] Branch: main
[OK] cmux: Workspace ready
```

**Use case:** Starting work on a new ticket. Creates everything needed for a parallel development session.

### 2. Worktree Only -- Skip terminal setup

```bash
setup-worktree.sh TICKET-42 --skip-cmux
```

**Output:**

```
[INFO] Step 1: Validating prerequisites...
[OK] Prerequisites validated
[INFO] Step 2: Creating worktree 'TICKET-42' in repo 'claude-code-plugins'...
[OK] Worktree created at /workspace/repos/TICKET-42
[INFO] Step 3: Updating VS Code workspace...
[OK] VS Code workspace updated
[INFO] Step 4-7: Skipping cmux workspace setup (--skip-cmux)

==========================================
  Worktree Setup Complete
==========================================

[OK] Worktree: TICKET-42
[INFO] Repository: claude-code-plugins
[INFO] Path: /workspace/repos/TICKET-42
[INFO] Branch: main
[INFO] cmux: Skipped
```

**Use case:** When you want the worktree and workspace setup but will manage your terminal manually.

### 3. Dry Run -- Preview before creating

```bash
setup-worktree.sh TICKET-1 --dry-run
```

See the [--dry-run Usage](#--dry-run-usage) section above for the expected output format.

**Use case:** Verify that all parameters are correct and all prerequisites will be found before running the actual setup. Useful for debugging configuration issues.

### 4. Custom Branch -- Create worktree from develop

```bash
setup-worktree.sh FEATURE-99 --branch develop --skip-cmux
```

**Output:**

```
[INFO] Step 1: Validating prerequisites...
[OK] Prerequisites validated
[INFO] Step 2: Creating worktree 'FEATURE-99' in repo 'claude-code-plugins'...
[OK] Worktree created at /workspace/repos/FEATURE-99
[INFO] Step 3: Updating VS Code workspace...
[OK] VS Code workspace updated
[INFO] Step 4-7: Skipping cmux workspace setup (--skip-cmux)

==========================================
  Worktree Setup Complete
==========================================

[OK] Worktree: FEATURE-99
[INFO] Repository: claude-code-plugins
[INFO] Path: /workspace/repos/FEATURE-99
[INFO] Branch: develop
[INFO] cmux: Skipped
```

**Use case:** Repositories that use `develop` or other branches instead of `main`.

### 5. Explicit Container Name -- Deterministic setup

```bash
DEVCONTAINER_NAME="devx-container-1" setup-worktree.sh TICKET-1
```

**Use case:** CI/CD environments or situations where auto-detection may not work. Setting `DEVCONTAINER_NAME` explicitly ensures the script connects to the correct container.

## Exit Codes

| Exit Code | Meaning                   | Common Causes                                                          | Solution                                          |
| --------- | ------------------------- | ---------------------------------------------------------------------- | ------------------------------------------------- |
| **0**     | Success                   | Worktree created, all steps completed or gracefully skipped            | (Success - no action needed)                      |
| **1**     | Usage error               | Missing worktree name, not inside a git repository, missing flag value | Check syntax with `--help`                        |
| **2**     | Prerequisite failure      | crewchief not found, cmux-check.sh returned non-zero                   | Install crewchief or use `--skip-cmux`            |
| **3**     | Unrecognized option       | Unknown flag (e.g., `--skip-tab-close`, `--nonsense`)                  | Check valid options with `--help`                 |
| **4**     | Worktree creation failure | crewchief worktree create returned non-zero, worktree already exists   | Check `crewchief worktree list`, verify repo name |

## Known Limitations

### Container-mode only

The script is designed to run inside the devcontainer. Host-mode execution is not supported because it relies on Docker container detection and cmux-ssh.sh for terminal management.

### No worktree name validation

The script does not validate worktree name characters (e.g., slashes, spaces). Invalid names are passed through to `crewchief worktree create`, which handles its own validation. Names starting with a hyphen are caught as unrecognized options (exit 3).

### cmux failure is non-fatal for steps 1-3

If cmux workspace creation fails (step 4), the script still reports success (exit 0) because the worktree and workspace were created. The cmux failure is reported as a warning. Steps 5-7 are skipped when step 4 fails.

### Single workspace file assumption

The script uses a single workspace file. Specify `--workspace` to target a specific file, or use `--skip-workspace` if you manage multiple workspace files manually.

## Troubleshooting

### cmux-check.sh fails (exit 2)

```
[ERROR] cmux prerequisite check failed (cmux-check.sh returned non-zero)
```

**What this means:** The cmux-check.sh script verified that cmux prerequisites (tmux session, SSH access) are not met. The script cannot proceed with terminal setup.

**What to do:**

1. Run cmux-check.sh manually to see the specific failure:
   ```bash
   bash "$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-check.sh"
   ```
2. Fix the underlying issue (e.g., start tmux, configure SSH)
3. Or bypass cmux entirely with `--skip-cmux`:
   ```bash
   setup-worktree.sh TICKET-1 --skip-cmux
   ```

### Container name not detected

```
[WARN] Could not detect devcontainer name. Set DEVCONTAINER_NAME env var.
```

**What this means:** The script tried to auto-detect the container name via `docker ps` but found no containers matching the `devcontainer` filter. cmux steps 5-7 are skipped, but the worktree and workspace setup (steps 1-3) still complete.

**What to do:**

1. Check if the container is running:
   ```bash
   docker ps --filter name=devcontainer
   ```
2. If the container has a different name, set it explicitly:
   ```bash
   DEVCONTAINER_NAME="your-container-name" setup-worktree.sh TICKET-1
   ```
3. If you do not need terminal setup, use `--skip-cmux`

### Docker container detection failed

```
[WARN] Docker container detection failed
```

**What this means:** The script attempted to auto-detect the container name via `docker ps` but the Docker socket is not accessible from within the container, resulting in a permission-denied error. cmux steps 5-7 are skipped, but the worktree and workspace setup (steps 1-3) still complete.

**What to do:**

1. Set `DEVCONTAINER_NAME` explicitly to bypass Docker auto-detection:
   ```bash
   DEVCONTAINER_NAME="your-container-name" setup-worktree.sh TICKET-1
   ```
2. Or export it in your shell profile so it persists across sessions:
   ```bash
   export DEVCONTAINER_NAME="your-container-name"
   ```

### workspace-folder.sh not found

```
[WARN] workspace-folder.sh not found at: /workspace/.devcontainer/scripts/workspace-folder.sh
[WARN] VS Code workspace update will be skipped
```

**What this means:** The workspace-folder.sh script is not at the expected location. The VS Code workspace step is automatically skipped.

**What to do:**

1. Check if the script exists at a different path:
   ```bash
   find /workspace -name workspace-folder.sh 2>/dev/null
   ```
2. If found at a different location, set the path:
   ```bash
   WORKSPACE_FOLDER_SCRIPT="/path/to/workspace-folder.sh" setup-worktree.sh TICKET-1
   ```
3. If you do not use VS Code workspaces, this warning is safe to ignore

### crewchief worktree create fails (exit 4)

```
[ERROR] Worktree creation failed (crewchief worktree create returned non-zero)
```

**What this means:** The `crewchief worktree create` command failed. Common causes include the worktree already existing or the repository not being found.

**What to do:**

1. Check if the worktree already exists:
   ```bash
   crewchief worktree list
   ls /workspace/repos/<repo>/<worktree-name>
   ```
2. Verify the repository name:
   ```bash
   ls /workspace/repos/
   ```
3. If the worktree exists but needs recreation, remove it first and retry

### Running from inside an existing worktree

**What this means:** If you run `setup-worktree.sh` from inside an existing worktree (e.g., `repos/myrepo-TICKET-99/`) rather than the main clone, `git rev-parse --show-toplevel` returns that worktree's root. The new worktree will be created as a sibling of the current worktree, not the main clone. This is expected behavior — a worktree is a valid git repository context.

**What to do:**

1. To confirm which root will be used before running the script:
   ```bash
   git rev-parse --show-toplevel
   ```
2. To create the new worktree as a sibling of the main clone instead, navigate to the main clone first:
   ```bash
   cd /workspace/repos/myrepo
   setup-worktree.sh TICKET-200
   ```

## Related Skills

- **worktree-merge** -- Merge a worktree back to main and clean up environment
- **worktree-management** -- Core git worktree operations via CrewChief CLI
- **terminal-management** -- cmux-ssh.sh terminal session management
- **workspace-folder.sh** -- Manages folders in VS Code workspace files

For worktree removal, see the worktree-merge skill. For direct terminal management, see the cmux plugin's terminal-management skill.
