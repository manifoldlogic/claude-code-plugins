---
description: Tear down a worktree by closing its cmux workspace and cleaning up the git worktree
argument-hint: <worktree-name> --repo <repository>
---

# Teardown Worktree

## Context

This command tears down a git worktree and its associated development environment: closes the cmux terminal workspace, removes the worktree from the VS Code workspace file, and cleans up the git worktree and branch. It is the teardown counterpart to `setup-worktree` and the primary entry point for finishing work on a ticket.

User input: $ARGUMENTS (worktree name and --repo are required; additional flags are optional)

For detailed usage, examples, exit codes, and troubleshooting, read `plugins/devx/skills/worktree-teardown/SKILL.md`.

## Workflow

### Step 1: Parse user input

1. Read `plugins/devx/skills/worktree-teardown/SKILL.md` for context on the teardown workflow, prerequisites, and known limitations.

2. Determine arguments from `$ARGUMENTS`:
   - The first token is the worktree name (typically a ticket ID like `DEVX-1001`).
   - `--repo <name>` is required. Parse it from the user's input.
   - Parse any additional flags the user included (e.g., `--dry-run`, `--skip-cmux`, `--skip-workspace`, `--keep-branch`, `--yes`).

3. Determine flags:
   - If the user explicitly requests a preview, include `--dry-run`.
   - If the user wants to skip cmux workspace closure, include `--skip-cmux`.
   - If the user wants to skip VS Code workspace update, include `--skip-workspace`.
   - If the user wants to keep the git branch, include `--keep-branch`.
   - If the user wants to skip confirmation prompts, include `--yes` or `-y`.
   - If the user wants verbose output, include `--verbose`.

### Step 2: Construct and run teardown-worktree.sh

**Script path:** Resolve relative to the plugin installation:
```
${PLUGIN_DIR}/skills/worktree-teardown/scripts/teardown-worktree.sh
```
Where `${PLUGIN_DIR}` is the devx plugin directory (e.g., `plugins/devx`).

**Command construction:**

- Full teardown (e.g., `/devx:teardown-worktree TICKET-1 --repo crewchief`):
  ```bash
  ${PLUGIN_DIR}/skills/worktree-teardown/scripts/teardown-worktree.sh TICKET-1 --repo crewchief
  ```

- Dry-run preview:
  ```bash
  ${PLUGIN_DIR}/skills/worktree-teardown/scripts/teardown-worktree.sh TICKET-1 --repo crewchief --dry-run
  ```

- Skip cmux workspace closure:
  ```bash
  ${PLUGIN_DIR}/skills/worktree-teardown/scripts/teardown-worktree.sh TICKET-1 --repo crewchief --skip-cmux
  ```

- Skip VS Code workspace update:
  ```bash
  ${PLUGIN_DIR}/skills/worktree-teardown/scripts/teardown-worktree.sh TICKET-1 --repo crewchief --skip-workspace
  ```

- Keep the git branch:
  ```bash
  ${PLUGIN_DIR}/skills/worktree-teardown/scripts/teardown-worktree.sh TICKET-1 --repo crewchief --keep-branch
  ```

- Skip confirmation prompt:
  ```bash
  ${PLUGIN_DIR}/skills/worktree-teardown/scripts/teardown-worktree.sh TICKET-1 --repo crewchief --yes
  ```

Run the constructed command and capture the exit code.

### Step 3: Report results to user

Handle the exit code from teardown-worktree.sh:

- **Exit 0 -- Success:** Report that the worktree was torn down and the environment cleaned up. Summarize the script output including which steps completed (cmux closure, worktree removal) and which were skipped.

- **Exit 1 -- Usage error:** Report the missing or invalid argument. Show the correct syntax: `teardown-worktree.sh <worktree-name> --repo <repository>`. Note that worktree names must not contain slashes, spaces, or dots.

- **Exit 2 -- Prerequisite failure:** Report which prerequisite failed (cleanup-worktree.sh not found, cmux-check.sh failed). If cmux is the missing component, suggest using `--skip-cmux` to bypass cmux prerequisites and still perform worktree cleanup.

- **Exit 3 -- Unrecognized option:** Report the unrecognized flag. Show valid options from `--help`. Note that worktree names starting with a hyphen are treated as unrecognized options.

- **Exit 4 -- Worktree cleanup failure:** Report that cleanup-worktree.sh failed. Suggest running `cleanup-worktree.sh` directly with `--verbose` for more detailed error output. Check if the worktree exists with `crewchief worktree list`.

- **Exit 5 -- User cancelled:** Report that the user declined the confirmation prompt. This is a normal outcome, not an error. The worktree was not removed. Suggest re-running with `--yes` to skip the prompt if the user is certain they want to proceed.
