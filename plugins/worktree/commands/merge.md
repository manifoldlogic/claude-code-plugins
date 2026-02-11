---
description: Merge a worktree back to main and clean up environment
argument-hint: [worktree-name or empty to auto-detect]
---

# Merge Worktree

## Context

This command merges a completed worktree back to the base branch (default: main) and tears down the associated environment. The full workflow includes PR status verification, main branch sync, merge via CrewChief CLI, VS Code workspace folder removal, and iTerm tab closure.

User input: $ARGUMENTS (optional worktree name; if empty, merge-worktree.sh auto-detects from the current working directory)

For detailed usage, examples, exit codes, and troubleshooting, read `plugins/worktree/skills/worktree-merge/SKILL.md`.

## Workflow

### Step 1: Detect worktree info

1. Read `plugins/worktree/skills/worktree-merge/SKILL.md` for context on the merge workflow, prerequisites, and known limitations.

2. Determine worktree name and repo:
   - If `$ARGUMENTS` is provided, treat the first token as the worktree name. Parse any additional flags the user included (e.g., `--dry-run`, `--skip-pr-check`, `--strategy squash`).
   - If `$ARGUMENTS` is empty, the script will auto-detect both repo and worktree name from the current working directory. No positional argument is needed.

3. Determine flags:
   - Always include `--yes` to skip the interactive confirmation prompt (Claude cannot respond to prompts).
   - If the user explicitly requests a preview, include `--dry-run`.
   - If the user requests skipping PR checks, include `--skip-pr-check`.
   - If the user specifies a merge strategy, include `--strategy <ff|squash|cherry-pick>`.
   - If the user specifies a base branch other than main, include `--base-branch <branch>`.

### Step 2: Construct and run merge-worktree.sh

**Script path:** `/workspace/.devcontainer/scripts/merge-worktree.sh`

**Command construction:**

- User provided worktree name (e.g., `/worktree:merge PANE-001`):
  ```bash
  /workspace/.devcontainer/scripts/merge-worktree.sh PANE-001 --yes
  ```
  If the repo cannot be auto-detected from the current directory, add `--repo <repo>`:
  ```bash
  /workspace/.devcontainer/scripts/merge-worktree.sh PANE-001 --repo crewchief --yes
  ```

- Auto-detect (e.g., `/worktree:merge` with no arguments, run from inside the worktree):
  ```bash
  /workspace/.devcontainer/scripts/merge-worktree.sh --yes
  ```

- Dry-run preview:
  ```bash
  /workspace/.devcontainer/scripts/merge-worktree.sh PANE-001 --repo crewchief --dry-run
  ```

- With merge strategy:
  ```bash
  /workspace/.devcontainer/scripts/merge-worktree.sh PANE-001 --repo crewchief --strategy squash --yes
  ```

Run the constructed command and capture the exit code.

### Step 3: Report results to user

Handle the exit code from merge-worktree.sh:

- **Exit 0 -- Success:** Report that the worktree was merged, the workspace was updated, and the tab was closed. Summarize the script output.

- **Exit 7 -- Merge failed:** Report that the merge failed. Explain that the worktree remains intact for manual conflict resolution. Suggest:
  - Navigate to the main worktree and run `git merge --continue` after resolving conflicts
  - Or run `git merge --abort` to cancel

- **Exit 8 -- PR check blocked:** Report that a PR for this branch is still OPEN. Suggest:
  - Close or merge the PR on GitHub first, then retry
  - Or re-run with `--skip-pr-check` to bypass PR verification

- **Exit 10 -- Success with warnings:** Report that the merge succeeded but some cleanup operations failed (e.g., workspace removal or tab close). List the warnings from the script output and suggest manual cleanup if needed.

- **Other exit codes:** Report the error with the exit code. Direct the user to the SKILL.md exit code table for troubleshooting:
  - Exit 2: Missing prerequisites (crewchief CLI not installed)
  - Exit 3: Invalid arguments
  - Exit 4: Worktree not found
  - Exit 5: User cancelled
  - Exit 6: Lock contention (another operation in progress)
  - Exit 9: Main worktree not found
