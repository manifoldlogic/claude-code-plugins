---
name: worktree-merge
description: Merge a worktree back to main and clean up environment
---

# Worktree Merge Skill

**Last Updated:** 2026-02-11
**Script Source:** `plugins/worktree/skills/worktree-merge/scripts/merge-worktree.sh`

## Overview

The merge-worktree.sh script orchestrates the complete merge-and-teardown workflow for git worktrees by combining multiple operations into a single command:

1. Check PR status for the worktree branch (block if PR is OPEN)
2. Sync the main branch with origin before merging
3. Merge the worktree into the base branch via CrewChief CLI
4. Remove the worktree folder from the VS Code workspace file
5. Automatically close the associated iTerm tab

Unlike a manual `crewchief worktree merge` or `git merge`, merge-worktree.sh provides safety features including PR status verification, main branch sync, and post-merge environment cleanup. It is the merge companion to spawn-worktree.sh and cleanup-worktree.sh.

**KEY SAFETY FEATURES:**
- PR status verification blocks merge when a PR is still OPEN (non-draft)
- Main branch sync before merge reduces conflict risk
- Confirmation prompt before executing (skippable with `--yes`)
- Dry-run mode to preview all planned actions
- Concurrent execution protection via file locks
- Auto-detection of repo and worktree from current working directory

## Decision Tree

### Use merge-worktree.sh when:
- Work in a worktree is complete and ready to merge back to main
- The associated PR is merged, closed, or does not exist
- You want PR check + main sync + merge + workspace update + tab close in one command
- You are inside the devcontainer environment

### Use cleanup-worktree.sh when:
- Aborting work without merging (discarding the worktree)
- An SDD ticket is complete or aborted and you just need to remove the worktree
- You want SDD ticket status checking before removal
- The branch has already been merged via GitHub PR and you only need teardown

### Use crewchief worktree merge directly when:
- You need manual control over the merge process
- You are working outside the devcontainer
- You want to merge without any environment cleanup (workspace, tab)
- You are scripting and want direct control over each step

### Use crewchief worktree remove when:
- Cleaning up a worktree without merging any code
- The repository is in an unexpected state and you need low-level removal
- You do not need workspace or tab cleanup

### Do NOT use merge when:
- You are still actively working in the worktree
- The associated PR is still OPEN and under review (close or merge the PR first)
- You want to preserve the worktree for later (just close the tab instead)
- You are in the main worktree (navigate to the feature worktree first)

## Prerequisites

### Environment Requirements

**For Container Execution (primary mode):**
- Running inside the devcontainer
- Git repositories in `/workspace/repos` directory
- CrewChief CLI (`crewchief worktree merge`) installed
- jq installed for workspace updates (optional if `--skip-workspace`)
- workspace-folder.sh script available at `.devcontainer/scripts/`

**Optional:**
- gh CLI installed and authenticated (for PR status checks; degrades gracefully if absent)
- iTerm plugin installed (for automatic tab closing after merge)

### Verification Commands

Check prerequisites before running merge-worktree.sh:

```bash
# Verify execution context
uname  # Should show Linux in container

# Check CrewChief CLI
command -v crewchief

# Check jq (needed for workspace updates)
command -v jq

# Check gh CLI (needed for PR checks)
command -v gh && gh auth status

# Verify workspace-folder.sh script
ls ~/.devcontainer/scripts/workspace-folder.sh

# Verify iterm-close-tab.sh (optional)
ls plugins/iterm/skills/tab-management/scripts/iterm-close-tab.sh
```

## Usage

### CLI Syntax

```bash
merge-worktree.sh [<worktree-name>] [OPTIONS]
```

When `worktree-name` is omitted, the script auto-detects both the repository and worktree name from the current working directory. The path must follow the convention `/workspace/repos/<repo>/<worktree>`.

### Required Arguments

Both arguments are auto-detected from the current working directory when omitted:

- `worktree-name` - Name of the worktree to merge (positional argument; auto-detected from cwd if omitted)
- `-r, --repo REPO` - Repository name (must exist in `/workspace/repos`; auto-detected from cwd if omitted)

When auto-detection is used, the script parses the current working directory path. If the current directory is `/workspace/repos/myproject/feature-auth`, the script detects `repo=myproject` and `worktree=feature-auth`. If the user is in the main worktree (where `repo == worktree`), the script exits with an error.

### Optional Arguments

- `-s, --strategy STRATEGY` - Merge strategy: `ff`, `squash`, `cherry-pick` (default: `ff`)
- `-b, --base-branch NAME` - Base branch to merge into (default: `main`)
- `-w, --workspace FILE` - VS Code workspace file path (default: from `WORKSPACE_FILE` env or auto-detect)
- `-y, --yes` - Skip confirmation prompts (passed through to crewchief)
- `--skip-pr-check` - Skip PR status verification
- `--skip-workspace` - Skip VS Code workspace folder removal
- `--skip-tab-close` - Skip iTerm tab closure
- `--dry-run` - Show what would be done without making changes
- `--verbose` - Enable debug logging to stderr for troubleshooting
- `-h, --help` - Show help message and exit

### Environment Variables

All environment variables can be overridden by CLI flags (flags take precedence):

- `WORKSPACE_FILE` - Path to VS Code workspace file
  - Default: Auto-detect `/workspace/workspace.code-workspace`
  - Overridden by `-w/--workspace` flag

- `ITERM_PLUGIN_DIR` - Path to the iTerm plugin directory
  - Default: `/workspace/repos/claude-code-plugins/claude-code-plugins/plugins/iterm`
  - Override to use a custom iTerm plugin installation path
  - Used to locate `iterm-close-tab.sh` for automatic tab closing

## Examples

### 1. Basic Usage - Merge with explicit arguments

```bash
merge-worktree.sh PANE-001 --repo crewchief --yes
```

**Output:**
```
[INFO] Validating worktree 'PANE-001' exists...
[OK] Worktree found: /workspace/repos/crewchief/PANE-001
[INFO] Checking PR status for branch 'PANE-001' targeting 'main'...
[INFO] No PR found for branch 'PANE-001' - proceeding
[INFO] Syncing main branch with origin (30s timeout)...
[OK] Main branch synced
[INFO] Merging worktree 'PANE-001' into 'main'...
[OK] Worktree merged successfully
[INFO] Removing worktree from VS Code workspace...
[OK] Workspace updated
[OK] Tab closed

==========================================
  Worktree Merge Complete
==========================================

[OK] Worktree merged: PANE-001 -> main
[INFO] Strategy: ff
[INFO] Repository: crewchief
[OK] Workspace: Updated
[OK] Tab close: Done
```

**Use case:** Standard merge after completing feature work. The `--yes` flag skips the confirmation prompt for scripted or agent-driven usage.

### 2. Auto-Detection from Current Working Directory

```bash
cd /workspace/repos/myproject/feature-auth
merge-worktree.sh
```

**Output:**
```
[INFO] Auto-detected from cwd: repo=myproject worktree=feature-auth
[INFO] Validating worktree 'feature-auth' exists...
[OK] Worktree found: /workspace/repos/myproject/feature-auth
[INFO] Checking PR status for branch 'feature-auth' targeting 'main'...
[OK] No PR found for branch - proceeding
[INFO] Syncing main branch with origin (30s timeout)...
[OK] Main branch synced
[INFO] Merging worktree 'feature-auth' into 'main'...
[OK] Worktree merged successfully
[INFO] Removing worktree from VS Code workspace...
[OK] Workspace updated
[INFO] Closing iTerm tab...
[OK] Tab closed
```

**Use case:** Convenient merge when you are already inside the worktree directory. No arguments needed -- both repo and worktree are detected from the path.

### 3. Dry-Run Preview

```bash
merge-worktree.sh PANE-001 --repo crewchief --dry-run
```

**Output:**
```
==========================================
  DRY RUN - No changes will be made
==========================================

Would execute with resolved parameters:
  Repository: crewchief
  Worktree name: PANE-001
  Worktree path: /workspace/repos/crewchief/PANE-001
  Main worktree: /workspace/repos/crewchief/crewchief
  Base branch: main
  Strategy: ff
  Workspace file: /workspace/workspace.code-workspace

Planned operations:

[DRY-RUN] 1. Check PR status:
     gh pr view PANE-001 --json state,isDraft (10s timeout)

[DRY-RUN] 2. Sync main branch:
     git -C /workspace/repos/crewchief/crewchief pull origin main (30s timeout)

[DRY-RUN] 3. Merge worktree (from main worktree directory):
     cd /workspace/repos/crewchief/crewchief
     crewchief worktree merge PANE-001 --strategy ff

[DRY-RUN] 4. Remove from workspace:
     workspace-folder.sh remove /workspace/repos/crewchief/PANE-001 -w "/workspace/workspace.code-workspace"

[DRY-RUN] 5. Close iTerm tab:
     iterm-close-tab.sh --force "crewchief PANE-001"

==========================================
```

**Use case:** Preview all planned actions before executing. Validates prerequisites, resolves paths, and shows exact commands that would run. Useful for verifying auto-detection and workspace resolution are correct.

### 4. Skip PR Check

```bash
merge-worktree.sh PANE-001 --repo crewchief --skip-pr-check --yes
```

**Output:**
```
[INFO] Validating worktree 'PANE-001' exists...
[OK] Worktree found: /workspace/repos/crewchief/PANE-001
[INFO] Skipping PR status check (--skip-pr-check flag)
[INFO] Syncing main branch with origin (30s timeout)...
[OK] Main branch synced
[INFO] Merging worktree 'PANE-001' into 'main'...
[OK] Worktree merged successfully
...
```

**Use case:** When you know there is no PR, when the PR has already been handled externally, or when `gh` CLI is not authenticated.

### 5. Squash Merge Strategy

```bash
merge-worktree.sh PANE-001 --repo crewchief --strategy squash --yes
```

**Output:**
```
[INFO] Validating worktree 'PANE-001' exists...
[OK] Worktree found: /workspace/repos/crewchief/PANE-001
[INFO] Checking PR status for branch 'PANE-001' targeting 'main'...
[INFO] PR already merged - proceeding
[INFO] Syncing main branch with origin (30s timeout)...
[OK] Main branch synced
[INFO] Merging worktree 'PANE-001' into 'main'...
[OK] Worktree merged successfully

==========================================
  Worktree Merge Complete
==========================================

[OK] Worktree merged: PANE-001 -> main
[INFO] Strategy: squash
[INFO] Repository: crewchief
[OK] Workspace: Updated
[OK] Tab close: Done
```

**Use case:** Squash all commits from the worktree branch into a single commit on the base branch. Valid strategies are `ff` (fast-forward, default), `squash`, and `cherry-pick`.

### 6. Custom Base Branch

```bash
merge-worktree.sh PANE-001 --repo crewchief --base-branch develop --yes
```

**Output:**
```
[INFO] Validating worktree 'PANE-001' exists...
[OK] Worktree found: /workspace/repos/crewchief/PANE-001
[INFO] Checking PR status for branch 'PANE-001' targeting 'develop'...
[INFO] No PR found for branch 'PANE-001' - proceeding
[INFO] Syncing develop branch with origin (30s timeout)...
[OK] Main branch synced
[INFO] Merging worktree 'PANE-001' into 'develop'...
[OK] Worktree merged successfully
...
```

**Use case:** Merge into a branch other than `main`. Useful for repositories that use `develop`, `staging`, or other branch naming conventions.

### 7. Skip Cleanup Operations

```bash
merge-worktree.sh PANE-001 --repo crewchief --skip-workspace --skip-tab-close --yes
```

**Output:**
```
[INFO] Validating worktree 'PANE-001' exists...
[OK] Worktree found: /workspace/repos/crewchief/PANE-001
[INFO] Checking PR status for branch 'PANE-001' targeting 'main'...
[INFO] No PR found for branch 'PANE-001' - proceeding
[INFO] Syncing main branch with origin (30s timeout)...
[OK] Main branch synced
[INFO] Merging worktree 'PANE-001' into 'main'...
[OK] Worktree merged successfully
[INFO] Skipping workspace update (--skip-workspace flag)
[INFO] Skipping tab close (--skip-tab-close flag)

==========================================
  Worktree Merge Complete
==========================================

[OK] Worktree merged: PANE-001 -> main
[INFO] Strategy: ff
[INFO] Repository: crewchief
[INFO] Workspace: Skipped
[INFO] Tab close: Skipped
```

**Use case:** When you only need the merge operation without workspace or tab cleanup. Useful in environments without VS Code workspaces or without iTerm integration.

### 8. Error Scenario - PR is Still Open

```bash
merge-worktree.sh PANE-001 --repo crewchief --yes
```

**Output:**
```
[INFO] Validating worktree 'PANE-001' exists...
[OK] Worktree found: /workspace/repos/crewchief/PANE-001
[INFO] Checking PR status for branch 'PANE-001' targeting 'main'...
[ERROR] PR for branch 'PANE-001' is still OPEN
[ERROR] Close or merge the PR first, or use --skip-pr-check to bypass
```

**Exit code:** 8

**Use case:** The PR for this branch is still open and under review. The script blocks the merge to prevent bypassing the review process. Either close/merge the PR first, or use `--skip-pr-check` if you intentionally want to bypass PR verification.

## Exit Codes

The script uses specific exit codes to indicate different outcomes:

| Exit Code | Meaning | Common Causes | Solution |
|-----------|---------|---------------|----------|
| **0** | Success | Worktree merged and all cleanup completed | (Success - no action needed) |
| **1** | Docker or container issues | Container not running, daemon unavailable | Start container |
| **2** | Missing prerequisites | crewchief CLI not installed | Install crewchief: `npm install -g @anthropic/crewchief` |
| **3** | Invalid arguments | Missing required args, invalid format, in main worktree | Check syntax with `--help`; navigate to feature worktree |
| **4** | Worktree not found | Worktree name doesn't exist or was already removed | Verify name: `crewchief worktree list` |
| **5** | User cancelled | Declined confirmation prompt | Re-run with `--yes` if intended |
| **6** | Lock acquisition failed | Another merge or cleanup operation in progress for same worktree | Wait for other operation to finish, or remove lock: `rm /tmp/worktree-merge-<repo>-<worktree>.lock` |
| **7** | Merge failed | crewchief merge returned error, merge conflicts | Resolve conflicts in main worktree: `git merge --continue` or `git merge --abort` |
| **8** | PR check blocked | PR is OPEN and non-draft | Close or merge the PR first, or use `--skip-pr-check` |
| **9** | Main worktree not found | Main worktree directory does not exist at expected paths | Ensure main worktree exists at `/workspace/repos/<repo>/<repo>` or `/workspace/repos/<repo>` |
| **10** | Success with warnings | Merge succeeded but workspace removal or tab close failed | Check warnings; manual cleanup may be needed |

## Known Limitations

### Single workspace file assumption

The script resolves a single VS Code workspace file using the priority order: `--workspace` flag, `WORKSPACE_FILE` environment variable, then auto-detect at `/workspace/workspace.code-workspace`. If your setup uses multiple workspace files, you must specify the correct one via `--workspace` or use `--skip-workspace` and update workspace files manually.

### Tab close race condition

After the merge completes, the worktree directory is removed by crewchief. The shell's working directory may change, and if iTerm updates the tab title based on the new cwd synchronously before `iterm-close-tab.sh` runs, the pattern match may fail to find the tab. The script mitigates this by capturing the tab pattern before changing directories, and treating tab close failure as non-fatal (exit 10 instead of error). If the tab is not closed automatically, close it manually.

### PR check targets base branch only

The PR status check uses `gh pr view <branch-name>` which checks for a PR from the worktree branch. If multiple PRs exist for the same source branch targeting different base branches, the check may not evaluate the correct one. The `--base-branch` flag controls which base branch to merge into, but the PR check does not filter by base branch. Use `--skip-pr-check` if PR detection produces unexpected results.

### Container-mode only

The initial release supports container execution only. Host-mode execution (running from outside the devcontainer) is not supported. Use `crewchief worktree merge` directly for host-mode workflows.

### Draft PRs are not blocked

PRs in DRAFT state are treated as non-blocking. The script warns about the draft state but proceeds with the merge. If you want to block merges when a draft PR exists, close the draft PR first or handle it manually.

## Troubleshooting

### PR check blocks unexpectedly

```
[ERROR] PR for branch 'feature-xyz' is still OPEN
[ERROR] Close or merge the PR first, or use --skip-pr-check to bypass
```

**Solution:** Close or merge the PR on GitHub, then retry. Alternatively, bypass the check:
```bash
merge-worktree.sh feature-xyz --repo myproject --skip-pr-check --yes
```

### Main worktree not found

```
[ERROR] Main worktree not found at expected paths:
[ERROR]   Primary: /workspace/repos/myproject/myproject
[ERROR]   Fallback: /workspace/repos/myproject
[ERROR] Ensure the repository exists in /workspace/repos/
```

**Solution:** Verify the main worktree exists at one of the expected paths:
```bash
ls /workspace/repos/myproject/myproject 2>/dev/null || ls /workspace/repos/myproject
```
If the repository is not cloned, clone it first. If the directory structure differs from the expected convention, you may need to create a symlink or restructure.

### Tab close fails

```
[WARN] Could not close tab 'crewchief PANE-001'. Please close manually.
```

**Solution:** This warning is non-fatal -- the merge has already succeeded. Close the tab manually in iTerm. Common causes:
- The tab name does not match the expected pattern `"<repo> <worktree>"` (e.g., `"crewchief PANE-001"`)
- The tab was already closed manually
- iTerm2 is not running or not accessible via SSH from the container
- The iTerm plugin is not installed at the expected path

Verify the iTerm plugin path:
```bash
ls "$ITERM_PLUGIN_DIR/skills/tab-management/scripts/iterm-close-tab.sh"
```

### Lock contention

```
[ERROR] Another operation is in progress for worktree 'PANE-001' in repo 'crewchief'
[ERROR] If you're sure no other operation is running, remove: /tmp/worktree-merge-crewchief-PANE-001.lock
```

**Solution:** Another merge or cleanup operation is running for this worktree. Wait for it to finish. If you are certain no other operation is running (e.g., a previous run crashed), remove the stale lock file:
```bash
rm /tmp/worktree-merge-crewchief-PANE-001.lock
```

### Merge conflicts

```
[ERROR] Merge failed. Worktree remains intact.
[ERROR] To resolve: review conflicts in /workspace/repos/myproject/myproject and retry
[ERROR]   To continue merge: cd /workspace/repos/myproject/myproject && git merge --continue
[ERROR]   To abort merge: cd /workspace/repos/myproject/myproject && git merge --abort
```

**Solution:** The worktree remains intact after a merge failure. Navigate to the main worktree and resolve conflicts:
```bash
cd /workspace/repos/myproject/myproject
# Review conflicting files
git status
# Edit files to resolve conflicts, then:
git add <resolved-files>
git merge --continue
# Or abort entirely:
git merge --abort
```

After resolving, you can re-run merge-worktree.sh or complete the cleanup manually.

### gh auth failure

```
[WARN] gh CLI not available - skipping PR status check
```

**Solution:** If you need PR checking, install and authenticate the GitHub CLI:
```bash
gh auth login
```
If you do not need PR checking, the script proceeds safely without it. You can also explicitly skip with `--skip-pr-check`.

### You appear to be in the main worktree

```
[ERROR] You appear to be in the main worktree (/workspace/repos/myproject/myproject)
[ERROR] Navigate to a feature worktree directory, or specify the worktree name explicitly:
[ERROR]   merge-worktree.sh <worktree-name> --repo myproject
```

**Solution:** The script detected you are in the main worktree, not a feature worktree. Either navigate to the feature worktree directory, or provide the worktree name explicitly:
```bash
merge-worktree.sh feature-auth --repo myproject
```

## Related Skills

- **worktree-cleanup** - Remove worktrees with SDD ticket checking (use when aborting work without merging)
- **worktree-spawn** - Create new worktrees with full environment setup (iTerm tab, workspace, SDD integration)
- **worktree-management** - Core git worktree operations (create, use, merge, clean) via CrewChief CLI
- **workspace-folder.sh** - Manages folders in VS Code workspace files

For worktree creation with iTerm and workspace integration, see the worktree-spawn skill. For worktree removal without merging, see the worktree-cleanup skill.
