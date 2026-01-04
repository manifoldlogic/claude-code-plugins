---
name: worktree-cleanup
description: Orchestration script for cleaning up git worktrees in devcontainer environments with VS Code workspace integration. Provides SDD ticket status checking to prevent accidental cleanup of incomplete work, with confirmation prompts and dry-run mode for safety.
---

# Worktree Cleanup Skill

**Last Updated:** 2026-01-04
**Script Source:** `/workspace/.devcontainer/scripts/cleanup-worktree.sh`

## Overview

The cleanup-worktree.sh script orchestrates the complete worktree removal workflow by combining multiple operations into a single command:

1. Check for associated SDD tickets and verify completion status
2. Prompt for confirmation if incomplete work is detected
3. Remove git worktree using CrewChief CLI
4. Optionally delete the associated git branch
5. Remove worktree folder from VS Code workspace file

Unlike basic `git worktree remove` or `ccwt clean`, cleanup-worktree.sh provides safety features including ticket status checking and confirmation prompts to prevent accidental data loss.

**KEY SAFETY FEATURES:**
- Automatic detection of associated SDD tickets
- Confirmation prompts when incomplete work is detected
- Dry-run mode to preview actions before execution
- Cannot cleanup worktree you're currently in

## Decision Tree

### Use cleanup-worktree.sh when:
- Work in a worktree is complete and merged
- You want ticket checking + cleanup + workspace update in one command
- Cleaning up after finishing feature/bugfix work
- You need confirmation before removing incomplete work
- You're using VS Code multi-root workspaces

### Use ccwt clean (CrewChief CLI) when:
- You only need worktree removal (no ticket checking)
- Working outside a devcontainer
- Scripting where you want direct control
- Maximum portability across different setups
- No SDD workflow integration needed

### Use standard git worktree remove when:
- Not using CrewChief CLI at all
- Simple worktree workflows without orchestration
- Working in non-devcontainer environments

### Do NOT use cleanup when:
- You're still actively working in the worktree
- You need to switch to a different worktree (use worktree-management)
- Work hasn't been merged yet (commit and merge first)
- You want to preserve the worktree for later (just close the tab instead)

## Prerequisites

### Environment Requirements

**For Container Execution (primary mode):**
- Running inside the devcontainer
- Git repositories in `/workspace/repos` directory
- CrewChief CLI (crewchief worktree) installed
- jq installed for workspace updates
- workspace-folder.sh script available

**Optional:**
- SDD plugin installed (for ticket status checking)
- SDD_ROOT_DIR environment variable configured

### Verification Commands

Check prerequisites before running cleanup-worktree.sh:

```bash
# Verify execution context
uname  # Should show Linux in container

# Check CrewChief CLI
which crewchief

# Check jq
which jq

# Verify workspace-folder.sh script
ls ~/.devcontainer/scripts/workspace-folder.sh

# Check SDD plugin (optional)
echo $SDD_ROOT_DIR
ls $SDD_ROOT_DIR/tickets/ 2>/dev/null
```

## Usage

### CLI Syntax

```bash
cleanup-worktree.sh <worktree-name> --repo <repository> [OPTIONS]
```

### Required Arguments

- `worktree-name` - Name of the worktree to remove (alphanumeric, hyphens, underscores only)
- `-r, --repo REPO` - Repository name (must exist in `/workspace/repos`)

### Optional Arguments

- `-w, --workspace FILE` - VS Code workspace file path (default: from WORKSPACE_FILE or auto-detect)
- `-y, --yes` - Skip confirmation prompt (for scripted usage)
- `--keep-branch` - Don't delete the git branch after worktree removal
- `--skip-workspace` - Skip removing from VS Code workspace
- `--dry-run` - Show what would be done without making changes
- `-h, --help` - Show help message and exit

### Environment Variables

All environment variables can be overridden by CLI flags (flags take precedence):

- `WORKSPACE_FILE` - Path to VS Code workspace file
  - Default: Auto-detect `/workspace/workspace.code-workspace`
  - Overridden by `-w/--workspace` flag

- `SDD_ROOT_DIR` - Path to SDD directory for ticket detection
  - Default: None (ticket checking skipped if unset)
  - Used by SDD plugin to locate tickets

## Ticket Detection Behavior

When SDD_ROOT_DIR is configured, the cleanup script automatically:

1. **Searches for associated tickets** - Looks for tickets matching the worktree name (exact match, prefix match, or case-insensitive match)
2. **Checks task completion status** - Reads task files to determine if all tasks are verified
3. **Prompts for confirmation** - If incomplete work is detected, asks for confirmation before proceeding

### Ticket Status Categories

| Status | Meaning | Behavior |
|--------|---------|----------|
| **complete** | All tasks verified | Cleanup proceeds without extra prompts |
| **partial** | Some tasks verified | Warning shown, confirmation required |
| **not_started** | No tasks verified | Warning shown, confirmation required |
| **no_tasks** | Ticket exists but no tasks | Cleanup proceeds (empty ticket) |
| **no_ticket** | No associated ticket found | Cleanup proceeds normally |

### Match Priority

The script searches for tickets in this order:
1. Active tickets (exact match on worktree name)
2. Active tickets (prefix match, e.g., "FEAT" matches "FEAT_feature-name")
3. Archived tickets (same matching rules)

## Examples

### 1. Basic Usage - Remove completed worktree

```bash
cleanup-worktree.sh feature-auth --repo myproject
```

**Output (with complete ticket):**
```
[INFO] Checking for associated SDD ticket...
[INFO] Found ticket: FEATURE_auth-system (complete)
[INFO] All tasks verified - no confirmation needed
[INFO] Removing worktree 'feature-auth' from repository 'myproject'...
[OK] Worktree removed
[INFO] Deleting branch 'feature-auth'...
[OK] Branch deleted
[INFO] Removing from VS Code workspace...
[OK] Workspace updated
```

**Use case:** Standard workflow after completing and merging feature work. Ticket is complete, so no confirmation needed.

### 2. Cleanup with Incomplete Ticket

```bash
cleanup-worktree.sh bugfix-login --repo myproject
```

**Output (with partial ticket):**
```
[INFO] Checking for associated SDD ticket...
[WARN] Found ticket: BUGFIX_login-issue
       Status: partial (2/5 tasks verified)
       Location: /workspace/_SDD/tickets/BUGFIX_login-issue

This worktree has incomplete work. Do you want to proceed? [y/N]:
```

**Use case:** Attempting to clean up work that isn't finished. The confirmation prompt prevents accidental data loss.

### 3. Keep Branch After Cleanup

```bash
cleanup-worktree.sh experiment --repo myproject --keep-branch
```

**Output:**
```
[INFO] Removing worktree 'experiment' from repository 'myproject'...
[OK] Worktree removed
[INFO] Keep branch: yes (--keep-branch specified)
[INFO] Removing from VS Code workspace...
[OK] Workspace updated
```

**Use case:** Clean up worktree but preserve the branch for later. Useful when you want to free up disk space but might return to the work.

### 4. Skip Confirmation (Scripted Usage)

```bash
cleanup-worktree.sh test-feature --repo myproject --yes
```

**Output:**
```
[INFO] Skipping ticket check (--yes specified)
[INFO] Removing worktree 'test-feature'...
[OK] Worktree removed
```

**Use case:** Automated scripts or when you've already verified the work is complete. Use with caution.

### 5. Dry-Run Mode

```bash
cleanup-worktree.sh feature-test --repo myproject --dry-run
```

**Output:**
```
==========================================
  DRY RUN - No changes will be made
==========================================

Would execute with resolved parameters:
  Repository: myproject
  Worktree name: feature-test
  Keep branch: no
  Skip workspace: no
  Workspace file: /workspace/workspace.code-workspace

Ticket check:
  Found: FEATURE_test-feature
  Status: complete
  Action: Would proceed without confirmation

Commands that would run:

  1. Remove worktree:
     crewchief worktree clean feature-test --repo myproject
     Expected path: /workspace/repos/myproject/feature-test

  2. Delete branch:
     git -C /workspace/repos/myproject/myproject fetch --prune
     git -C /workspace/repos/myproject/myproject branch -d feature-test

  3. Update workspace:
     workspace-folder.sh remove repos/myproject/feature-test
```

**Use case:** Preview all actions before executing. Verify ticket detection and workspace resolution are correct.

### 6. Skip Workspace Update

```bash
cleanup-worktree.sh hotfix --repo myproject --skip-workspace
```

**Output:**
```
[INFO] Removing worktree 'hotfix'...
[OK] Worktree removed
[INFO] Workspace: Skipped (--skip-workspace)
```

**Use case:** When you've already removed the folder from workspace manually, or don't use VS Code workspaces.

## Exit Codes

The script uses specific exit codes to indicate different outcomes:

| Exit Code | Meaning | Common Causes | Solution |
|-----------|---------|---------------|----------|
| **0** | Success | Worktree removed successfully | (Success - no action needed) |
| **1** | Docker or container issues | Container not running | Start container |
| **2** | Missing prerequisites | crewchief CLI or jq not installed | Install required tools |
| **3** | Invalid arguments | Missing required args, invalid format | Check syntax: `--help` |
| **4** | Worktree not found | Worktree doesn't exist, already removed | Verify worktree name |
| **5** | User cancelled | User answered 'n' to confirmation | Re-run if intended |

## Troubleshooting

### CrewChief CLI not found

```
[ERROR] crewchief CLI is required for worktree operations
[ERROR] Install from: https://github.com/your-org/crewchief
```

**Solution:** Install CrewChief CLI in the devcontainer.

### Worktree not found

```
[ERROR] Worktree 'feature-xyz' not found in repository 'myproject'
[ERROR] Available worktrees:
         - main
         - feature-auth
         - bugfix-123
```

**Solution:** Check the worktree name and verify it exists:
```bash
crewchief worktree list --repo myproject
```

### Cannot cleanup current worktree

```
[ERROR] Cannot remove worktree - you are currently in it
[ERROR] Switch to a different worktree first:
         cd /workspace/repos/myproject/main
```

**Solution:** Navigate to a different worktree before cleanup:
```bash
cd /workspace/repos/myproject/main
cleanup-worktree.sh feature-old --repo myproject
```

### Workspace file not found

```
[WARN] Workspace file not found: /workspace/workspace.code-workspace
[WARN] Skipping workspace update
```

**Solution:** This is non-fatal. Specify workspace file with `-w`:
```bash
cleanup-worktree.sh feature-old --repo myproject -w /path/to/workspace.code-workspace
```

### jq not installed

```
[ERROR] jq is required for workspace updates
[ERROR] Install with: apt-get install jq
[ERROR] Or skip workspace updates with: --skip-workspace
```

**Solution:** Install jq or skip workspace updates:
```bash
sudo apt-get install jq
# OR
cleanup-worktree.sh feature --repo myproject --skip-workspace
```

### Branch still has unmerged work

```
[WARN] Branch 'feature-xyz' has unmerged commits
[WARN] Use --keep-branch to preserve the branch
```

**Solution:** Either merge the work first, or use `--keep-branch`:
```bash
cleanup-worktree.sh feature-xyz --repo myproject --keep-branch
```

## Related Skills

- **worktree-spawn** - Create new worktrees with full environment setup
- **worktree-management** - Core git worktree operations (create, use, merge, clean)
- **workspace-folder.sh** - Manages folders in VS Code workspace files

For worktree creation with iTerm and workspace integration, see the worktree-spawn skill.
