---
description: Create a new worktree with VS Code workspace and cmux terminal setup
argument-hint: <worktree-name> --repo <repository>
---

# Setup Worktree

## Context

This command creates a new git worktree and sets up the full development environment: VS Code workspace folder, cmux terminal workspace, devcontainer session, navigation, and claude launch. It is the primary entry point for starting work on a new ticket.

User input: $ARGUMENTS (worktree name and --repo are required; additional flags are optional)

For detailed usage, examples, exit codes, and troubleshooting, read `plugins/devx/skills/worktree-setup/SKILL.md`.

## Workflow

### Step 1: Parse user input

1. Read `plugins/devx/skills/worktree-setup/SKILL.md` for context on the setup workflow, prerequisites, and known limitations.

2. Determine arguments from `$ARGUMENTS`:
   - The first token is the worktree name (typically a ticket ID like `DEVX-1001`).
   - `--repo <name>` is required. Parse it from the user's input.
   - Parse any additional flags the user included (e.g., `--dry-run`, `--skip-cmux`, `--skip-workspace`, `--branch develop`).

3. Determine flags:
   - If the user explicitly requests a preview, include `--dry-run`.
   - If the user wants to skip terminal setup, include `--skip-cmux`.
   - If the user wants to skip VS Code workspace update, include `--skip-workspace`.
   - If the user specifies a base branch other than main, include `--branch <branch>`.

### Step 2: Construct and run setup-worktree.sh

**Script path:** Resolve relative to the plugin installation:
```
${PLUGIN_DIR}/skills/worktree-setup/scripts/setup-worktree.sh
```
Where `${PLUGIN_DIR}` is the devx plugin directory (e.g., `plugins/devx`).

**Command construction:**

- Full setup (e.g., `/devx:setup-worktree TICKET-1 --repo crewchief`):
  ```bash
  ${PLUGIN_DIR}/skills/worktree-setup/scripts/setup-worktree.sh TICKET-1 --repo crewchief
  ```

- With custom branch:
  ```bash
  ${PLUGIN_DIR}/skills/worktree-setup/scripts/setup-worktree.sh TICKET-1 --repo crewchief --branch develop
  ```

- Dry-run preview:
  ```bash
  ${PLUGIN_DIR}/skills/worktree-setup/scripts/setup-worktree.sh TICKET-1 --repo crewchief --dry-run
  ```

- Skip cmux terminal setup:
  ```bash
  ${PLUGIN_DIR}/skills/worktree-setup/scripts/setup-worktree.sh TICKET-1 --repo crewchief --skip-cmux
  ```

- Skip VS Code workspace update:
  ```bash
  ${PLUGIN_DIR}/skills/worktree-setup/scripts/setup-worktree.sh TICKET-1 --repo crewchief --skip-workspace
  ```

Run the constructed command and capture the exit code.

### Step 3: Report results to user

Handle the exit code from setup-worktree.sh:

- **Exit 0 -- Success:** Report that the worktree was created and the environment is ready. Summarize the script output including the worktree path and which optional steps were completed or skipped.

- **Exit 1 -- Usage error:** Report the missing or invalid argument. Show the correct syntax.

- **Exit 2 -- Prerequisite failure:** Report which prerequisite failed (crewchief not found, cmux-check failed). Suggest installing the missing tool or using `--skip-cmux` to bypass cmux prerequisites.

- **Exit 3 -- Unrecognized option:** Report the unrecognized flag. Show valid options from `--help`.

- **Exit 4 -- Worktree creation failure:** Report that crewchief worktree failed to create the worktree. Suggest checking if the worktree already exists (`crewchief worktree list`) or if the repository name is correct.

- **Other exit codes:** Report the error with the exit code. Direct the user to the SKILL.md for troubleshooting.
