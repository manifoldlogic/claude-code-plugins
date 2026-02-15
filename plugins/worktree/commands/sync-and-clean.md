---
description: Pull latest changes and clean up a worktree
argument-hint: "[worktree-name or empty to auto-detect]"
---

# Sync and Clean Worktree

## Context

This command fetches remote changes with stale branch pruning and pulls the latest commits for a specified worktree. It runs `git fetch --prune` followed by `git pull` using the `git -C <path>` pattern so the agent does not need to change directories.

User input: $ARGUMENTS (optional worktree name; if empty, auto-detect from the current working directory)

## Workflow

### Step 1: Detect worktree info

1. Determine worktree name and repo:
   - If `$ARGUMENTS` is provided, treat the first token as the worktree name.
   - If `$ARGUMENTS` is empty, auto-detect from the current working directory:
     - Run `pwd` and parse the path to extract the repo and worktree name.
     - The expected path structure is `/workspace/repos/<repo>/<worktree>`.
     - If the current directory does not match this pattern, report an error: "Could not auto-detect worktree from current directory. Please provide a worktree name: `/worktree:sync-and-clean <worktree-name>`"

2. Resolve the worktree path:
   - If the worktree name was provided but the repo is unknown, search `/workspace/repos/` for a repo directory containing a subdirectory matching the worktree name. Use `ls` to list directories under `/workspace/repos/` and check each one.
   - Construct the full path as `/workspace/repos/<repo>/<worktree>`.
   - Verify the directory exists by checking with `ls -d /workspace/repos/<repo>/<worktree>`.
   - If the directory does not exist, report an error: "Worktree directory not found at `/workspace/repos/<repo>/<worktree>`. Check the worktree name and try again. Use `ccwt list` to see available worktrees."

### Step 2: Fetch and prune

Run `git fetch --prune` to retrieve remote updates and remove stale remote-tracking branches:

```bash
git -C /workspace/repos/<repo>/<worktree> fetch --prune
```

**Error handling:**
- If `git fetch --prune` fails (non-zero exit code), warn the user that fetch failed but **continue to Step 3** anyway. The pull may still succeed if the local tracking is intact. Report the fetch error output so the user can investigate (e.g., network issues, authentication problems).

### Step 3: Pull latest changes

Run `git pull` to merge remote changes into the local branch:

```bash
git -C /workspace/repos/<repo>/<worktree> pull
```

**Error handling:**
- If `git pull` fails due to merge conflicts, report the error clearly. Suggest:
  - Navigate to the worktree and resolve conflicts manually
  - Or run `git -C /workspace/repos/<repo>/<worktree> merge --abort` to cancel
- If `git pull` fails for other reasons (network error, detached HEAD, etc.), report the full error output and exit code to the user.

### Step 4: Report results

Summarize the outcome based on what happened in Steps 2 and 3:

- **Both succeeded:** Report that the worktree is up to date. Include a brief summary of what was fetched/pulled (e.g., "Already up to date" or the list of updated refs).

- **Fetch failed, pull succeeded:** Report that the pull succeeded but the fetch encountered an error. Suggest the user check their network connection or remote configuration.

- **Fetch succeeded, pull failed:** Report the pull failure with the error details. If merge conflicts are the cause, list the conflicting files and suggest resolution steps.

- **Both failed:** Report both errors. Suggest the user verify the remote is reachable (`git -C <path> remote -v`) and that the branch has an upstream configured (`git -C <path> branch -vv`).
