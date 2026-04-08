---
description: Reconcile workspace.code-workspace with repos on disk — fix naming, ordering, stale entries, and missing repos
argument-hint: [--dry-run | --check]
---

# Sync Workspace

## Context

This command reconciles `/workspace/workspace.code-workspace` with the actual repos and worktrees on disk. It scans `/workspace/repos/`, detects flat-clone and worktree-managed repos, applies naming conventions (`<repo> | main`, `<repo> ⛙ <WORKTREE>`), enforces alphabetical ordering (devcontainer first), removes stale entries, and adds missing ones.

User input: $ARGUMENTS (optional flags like `--dry-run`, `--check`, `--verbose`)

For detailed usage, algorithm, exit codes, and troubleshooting, read `plugins/devx/skills/workspace-sync/SKILL.md`.

## Workflow

### Step 1: Parse user input

1. Read `plugins/devx/skills/workspace-sync/SKILL.md` for context on the sync algorithm, naming conventions, and edge cases.

2. Parse flags from `$ARGUMENTS`:
   - `--dry-run`: Preview changes without modifying the file
   - `--check`: Exit 0 if in-sync, exit 1 if drift detected (for validation)
   - `--verbose`: Show detailed scan output
   - `-w <file>` or `--workspace <file>`: Custom workspace file path
   - `-r <dir>` or `--repos-dir <dir>`: Custom repos directory path

### Step 2: Construct and run sync-workspace.sh

**Script path:** Resolve relative to the plugin installation:

```
${PLUGIN_DIR}/skills/workspace-sync/scripts/sync-workspace.sh
```

Where `${PLUGIN_DIR}` is the devx plugin directory (e.g., `plugins/devx`).

**Command construction:**

- Default sync (fix everything):

  ```bash
  ${PLUGIN_DIR}/skills/workspace-sync/scripts/sync-workspace.sh
  ```

- Preview changes:

  ```bash
  ${PLUGIN_DIR}/skills/workspace-sync/scripts/sync-workspace.sh --dry-run
  ```

- Check for drift:

  ```bash
  ${PLUGIN_DIR}/skills/workspace-sync/scripts/sync-workspace.sh --check
  ```

- Verbose sync:

  ```bash
  ${PLUGIN_DIR}/skills/workspace-sync/scripts/sync-workspace.sh --verbose
  ```

Run the constructed command and capture the exit code.

### Step 3: Report results to user

Handle the exit code from sync-workspace.sh:

- **Exit 0 -- Success:** Report that the workspace file is in sync (or was updated). Summarize what changed: entries added, removed, reordered, or path corrections applied.

- **Exit 1 -- Drift detected (--check mode):** Report the drift summary. Show which entries are missing, stale, or misordered. Suggest running without `--check` to fix.

- **Exit 2 -- Prerequisites missing:** Report which prerequisite is missing (jq not installed, realpath not found, workspace file not found, invalid workspace JSON, repos directory not found).

- **Exit 3 -- Invalid arguments:** Report the unrecognized flag.
