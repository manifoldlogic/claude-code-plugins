---
name: worktree-teardown
description: Close cmux workspace and clean up git worktree
---

# Worktree Teardown Skill

**Last Updated:** 2026-03-16
**Script Source:** `plugins/devx/skills/worktree-teardown/scripts/teardown-worktree.sh`

## Overview

The teardown-worktree.sh script orchestrates the complete worktree teardown workflow by combining cmux workspace closure with worktree cleanup in a single command:

1. Validate prerequisites (cleanup-worktree.sh, cmux-check.sh)
2. Identify the cmux workspace by name matching (`cmux-ssh.sh list-workspaces`)
3. Close the cmux workspace (`cmux-ssh.sh close-workspace`)
4. Delegate worktree cleanup to `cleanup-worktree.sh` (ticket detection, confirmation, git cleanup, VS Code workspace update)

This is the teardown counterpart to `setup-worktree.sh`. Where setup creates worktree first then cmux workspace, teardown reverses the order: closes cmux workspace first, then removes worktree.

Unlike running `cleanup-worktree.sh` manually, teardown-worktree.sh also closes the cmux terminal workspace associated with the worktree, providing end-to-end environment teardown.

**KEY FEATURES:**
- Reverse-order orchestration mirroring setup-worktree.sh
- cmux workspace identification via name matching
- Graceful degradation when cmux is unavailable
- Dry-run mode to preview all planned actions
- Flag passthrough to cleanup-worktree.sh for fine-grained control

## Decision Tree

### Want to preview what will happen?
- Use `--dry-run` to see all planned operations without making changes
- Useful for verifying the correct worktree and cmux workspace will be targeted

### Is cmux unavailable or not needed?
- Use `--skip-cmux` to bypass cmux workspace closure entirely
- The script also gracefully degrades to skip cmux if cmux-check.sh is not found or fails

### Want to keep the git branch for future use?
- Use `--keep-branch` to remove the worktree but preserve the branch
- Useful when you plan to create a new worktree from the same branch later

### Want to skip confirmation prompts?
- Use `-y` or `--yes` to skip the confirmation prompt in cleanup-worktree.sh
- Useful in scripts or when you are certain you want to proceed

### Default: full teardown
- Without any skip flags, the script performs all four steps: validate, identify cmux workspace, close cmux workspace, clean up worktree
- cleanup-worktree.sh will prompt for confirmation if it detects an incomplete SDD ticket

## Prerequisites

### Environment Requirements

**Required:**
- Running inside the devcontainer
- `cleanup-worktree.sh` at `$CLEANUP_WORKTREE_SCRIPT` or `/workspace/.devcontainer/scripts/cleanup-worktree.sh`

**Optional (graceful degradation when absent):**
- `cmux-check.sh` and `cmux-ssh.sh` at `$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/` -- cmux steps skipped if not found or if cmux-check.sh returns non-zero
- CrewChief CLI (`ccwt`) -- required by cleanup-worktree.sh for worktree removal
- `workspace-folder.sh` -- required by cleanup-worktree.sh for VS Code workspace update (skipped if not found)

### Verification Commands

```bash
# Check cleanup-worktree.sh
ls /workspace/.devcontainer/scripts/cleanup-worktree.sh

# Check cmux scripts
ls "$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-check.sh"
ls "$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh"

# Check CrewChief CLI
command -v ccwt
```

## Usage

### CLI Syntax

```bash
teardown-worktree.sh <worktree-name> --repo <repository> [OPTIONS]
```

Both `worktree-name` and `--repo` are required. The worktree name is typically a ticket ID (e.g., `DEVX-1001`, `TICKET-123`).

### Required Arguments

- `worktree-name` -- Name of the worktree to tear down (positional argument, typically a ticket ID)
- `-r, --repo REPO` -- Repository name

### Optional Arguments

- `-y, --yes` -- Skip confirmation prompt (passed to cleanup-worktree.sh)
- `--keep-branch` -- Do not delete the git branch (passed to cleanup-worktree.sh)
- `--skip-cmux` -- Skip cmux workspace closure (steps 2-3)
- `--skip-workspace` -- Skip VS Code workspace update (passed to cleanup-worktree.sh)
- `--dry-run` -- Preview planned operations without making changes
- `--verbose` -- Show detailed cmux-ssh.sh and cleanup-worktree.sh output
- `-h, --help` -- Show help message and exit

### Environment Variables

- `CMUX_PLUGIN_DIR` -- Path to cmux plugin directory (default: `/workspace/repos/claude-code-plugins/claude-code-plugins/plugins/cmux`)
- `CLEANUP_WORKTREE_SCRIPT` -- Path to cleanup-worktree.sh (default: `/workspace/.devcontainer/scripts/cleanup-worktree.sh`)

## Dry-Run Usage

The `--dry-run` flag previews all planned operations without making any changes. It resolves all parameters, validates the configuration, and shows exactly what commands would run.

**Example invocation:**
```bash
teardown-worktree.sh TICKET-1 --repo crewchief --dry-run
```

**Expected output format:**
```
=== DRY RUN: teardown-worktree ===
Worktree: TICKET-1
Repo:     crewchief

Flags:
  Skip cmux: false
  Skip workspace: false
  Keep branch: false
  Yes (skip confirm): false
  Verbose: false

Planned operations:

[DRY-RUN] Step 1: Validate prerequisites
     Check: cleanup-worktree.sh, cmux-check.sh

[DRY-RUN] Step 2: Identify cmux workspace
     <CMUX_SSH_SCRIPT> list-workspaces
     Match workspace name: TICKET-1

[DRY-RUN] Step 3: Close cmux workspace
     <CMUX_SSH_SCRIPT> close-workspace --workspace <workspace_id>

[DRY-RUN] Step 4: Cleanup worktree (delegate to cleanup-worktree.sh)
     <CLEANUP_WORKTREE_SCRIPT> TICKET-1 --repo crewchief --dry-run

=== END DRY RUN ===
```

With `--skip-cmux`, steps 2 and 3 show the skip reason:
```
[DRY-RUN] Step 2: Identify cmux workspace [SKIPPED: --skip-cmux]

[DRY-RUN] Step 3: Close cmux workspace [SKIPPED: --skip-cmux]
```

## Examples

### 1. Full Teardown -- Close cmux workspace and clean up worktree

```bash
teardown-worktree.sh DEVX-1001 --repo claude-code-plugins
```

**Output:**
```
[INFO] Step 1: Validating prerequisites...
[OK] Prerequisites validated
[INFO] Step 2: Identifying cmux workspace for 'DEVX-1001'...
[OK] Found cmux workspace: workspace:3
[INFO] Step 3: Closing cmux workspace workspace:3...
[OK] cmux workspace workspace:3 closed
[INFO] Step 4: Cleaning up worktree (delegate to cleanup-worktree.sh)...
[OK] Worktree cleanup completed

==========================================
  Worktree Teardown Complete
==========================================

[OK] Worktree: DEVX-1001
[INFO] Repository: claude-code-plugins
[OK] cmux: Workspace closed
```

**Use case:** Finishing work on a ticket. Closes the cmux terminal session and removes the worktree, branch, and workspace entry.

### 2. Skip cmux -- Worktree cleanup only

```bash
teardown-worktree.sh TICKET-42 --repo myproject --skip-cmux
```

**Output:**
```
[INFO] Step 1: Validating prerequisites...
[OK] Prerequisites validated
[INFO] Steps 2-3: Skipping cmux workspace closure (--skip-cmux)
[INFO] Step 4: Cleaning up worktree (delegate to cleanup-worktree.sh)...
[OK] Worktree cleanup completed

==========================================
  Worktree Teardown Complete
==========================================

[OK] Worktree: TICKET-42
[INFO] Repository: myproject
[INFO] cmux: Skipped
```

**Use case:** When cmux is not available, not configured, or you manage your terminal sessions manually.

### 3. Dry Run -- Preview before teardown

```bash
teardown-worktree.sh TICKET-1 --repo crewchief --dry-run
```

See the [Dry-Run Usage](#dry-run-usage) section above for the expected output format.

**Use case:** Verify that the correct worktree and cmux workspace will be targeted before running the actual teardown. Useful for debugging configuration issues.

### 4. Keep Branch -- Remove worktree but preserve the branch

```bash
teardown-worktree.sh FEATURE-99 --repo webapp --keep-branch
```

**Output:**
```
[INFO] Step 1: Validating prerequisites...
[OK] Prerequisites validated
[INFO] Step 2: Identifying cmux workspace for 'FEATURE-99'...
[OK] Found cmux workspace: workspace:5
[INFO] Step 3: Closing cmux workspace workspace:5...
[OK] cmux workspace workspace:5 closed
[INFO] Step 4: Cleaning up worktree (delegate to cleanup-worktree.sh)...
[OK] Worktree cleanup completed

==========================================
  Worktree Teardown Complete
==========================================

[OK] Worktree: FEATURE-99
[INFO] Repository: webapp
[OK] cmux: Workspace closed
```

**Use case:** When you plan to create a new worktree from the same branch later, or want to preserve the branch for a pull request review.

### 5. Auto-Confirm -- Skip confirmation prompts

```bash
teardown-worktree.sh TICKET-1 --repo crewchief -y
```

**Use case:** Scripts, automation, or when you are certain the worktree should be removed. Bypasses the confirmation prompt that cleanup-worktree.sh shows when it detects an incomplete SDD ticket.

### 6. Combined Flags -- Skip cmux and keep branch with auto-confirm

```bash
teardown-worktree.sh TICKET-1 --repo crewchief --skip-cmux --keep-branch --yes
```

**Use case:** Quick cleanup in a non-cmux environment where you want to preserve the branch.

## Exit Codes

| Exit Code | Meaning | Common Causes | Solution |
|-----------|---------|---------------|----------|
| **0** | Success | Worktree torn down, cmux closed or gracefully skipped | (Success - no action needed) |
| **1** | Usage error | Missing worktree name, missing `--repo`, missing flag value, invalid name format (contains slash/space/dot) | Check syntax with `--help` |
| **2** | Prerequisite failure | cleanup-worktree.sh not found, cmux-check.sh returned non-zero | Set `CLEANUP_WORKTREE_SCRIPT` env var or use `--skip-cmux` for cmux issues |
| **3** | Unrecognized option | Unknown flag, worktree name starting with a hyphen | Check valid options with `--help` |
| **4** | Worktree cleanup failure | cleanup-worktree.sh returned a fatal error | Run `cleanup-worktree.sh` directly with `--verbose` for details; check `ccwt list` |
| **5** | User cancelled | User declined the confirmation prompt in cleanup-worktree.sh | Re-run with `--yes` to skip the prompt, or verify the worktree should be removed |

Note: cleanup-worktree.sh may exit 1, 2, 3, or 6 (lock failure). These are passed through by teardown-worktree.sh as exit 4.

## Known Limitations

### iTerm "skipping tab close" warning

When cleanup-worktree.sh runs, it may emit a warning about skipping iTerm tab closure. This warning is cosmetic and harmless -- it occurs because cleanup-worktree.sh has iTerm awareness that does not apply inside the devcontainer. The teardown script handles terminal closure via cmux instead.

### cmux workspace naming convention

The cmux workspace must be named exactly after the worktree for identification to work. The `setup-worktree.sh` script renames workspaces to the worktree name during creation. If a workspace was renamed manually, teardown will not find it and will warn but continue with worktree cleanup.

### Container-mode only

The script is designed to run inside the devcontainer. Host-mode execution is not supported because it relies on cmux-ssh.sh for terminal management and cleanup-worktree.sh for worktree removal.

### cmux failure is non-fatal

If cmux workspace identification or closure fails (steps 2-3), the script still proceeds to worktree cleanup (step 4) and reports success (exit 0) if cleanup succeeds. The cmux failure is reported as a warning.

## Troubleshooting

### cmux workspace not found (no match warning)

```
[WARN] No cmux workspace found matching 'TICKET-1'. Continuing with worktree cleanup.
```

**What this means:** The script called `cmux-ssh.sh list-workspaces` but no workspace name matched the worktree name. This is non-fatal -- worktree cleanup proceeds.

**What to do:**
1. Check if the workspace was renamed manually:
   ```bash
   bash "$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh" list-workspaces
   ```
2. If no cmux workspace exists for this worktree, the warning is expected -- the worktree may have been created without cmux
3. Use `--skip-cmux` to suppress this check entirely

### cleanup-worktree.sh not found (exit 2)

```
[ERROR] cleanup-worktree.sh not found at: /workspace/.devcontainer/scripts/cleanup-worktree.sh
```

**What this means:** The required cleanup-worktree.sh script is not at the expected location. The teardown cannot proceed.

**What to do:**
1. Find the script:
   ```bash
   find /workspace -name cleanup-worktree.sh 2>/dev/null
   ```
2. If found at a different path, set the environment variable:
   ```bash
   CLEANUP_WORKTREE_SCRIPT="/path/to/cleanup-worktree.sh" teardown-worktree.sh TICKET-1 --repo crewchief
   ```

### Multiple cmux workspaces match (ambiguity warning)

```
[WARN] Multiple cmux workspaces match 'TICKET-1' (2 found). Skipping close to avoid ambiguity.
```

**What this means:** More than one cmux workspace has the same name as the worktree. The script skips closure to avoid closing the wrong workspace.

**What to do:**
1. List workspaces to identify the duplicates:
   ```bash
   bash "$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh" list-workspaces
   ```
2. Close the correct workspace manually:
   ```bash
   bash "$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh" close-workspace --workspace workspace:N
   ```
3. Then re-run teardown with `--skip-cmux` for the worktree cleanup

## Related Skills

- **worktree-setup** (`plugins/devx/skills/worktree-setup/SKILL.md`) -- The setup counterpart that creates worktrees and cmux workspaces. Teardown reverses the operations performed by setup.
- **terminal-management** (`plugins/cmux/skills/terminal-management/SKILL.md`) -- The cmux terminal management skill providing `cmux-ssh.sh` for workspace listing and closure.
- **worktree-management** -- Core git worktree operations via CrewChief CLI (`ccwt`)
