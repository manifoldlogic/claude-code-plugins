---
name: workspace-sync
description: Reconcile workspace.code-workspace with repos on disk — enforce naming conventions, ordering, and entry completeness per the workspace-file-spec.
---

# Workspace Sync Skill

**Last Updated:** 2026-04-08
**Script Source:** `plugins/devx/skills/workspace-sync/scripts/sync-workspace.sh`

## Overview

The sync-workspace.sh script scans `/workspace/repos/` and reconciles `/workspace/workspace.code-workspace` to match what is on disk. It detects flat-clone and worktree-managed repos, applies naming conventions (`<repo> | main`, `<repo> ⛙ <WORKTREE>`), enforces ordering (devcontainer first, then alphabetical), removes stale entries, and adds missing ones.

This is the authoritative tool for workspace file maintenance. It implements the full [workspace-file-spec](references/workspace-file-spec.md).

**KEY FEATURES:**

- Full reconciliation in a single command
- Naming convention enforcement per workspace-file-spec
- Alphabetical ordering with devcontainer always first
- Stale entry removal (paths that no longer exist)
- Missing entry detection and addition
- `--dry-run` mode to preview changes
- `--check` mode for CI/hooks (exit code indicates drift)
- Settings object preserved as-is

## Decision Tree

### Use sync-workspace.sh when:

- You suspect the workspace file has drifted from what is on disk
- A repo was cloned or removed outside the normal setup/teardown workflow
- You want to verify the workspace file is correct (CI, pre-commit)
- Entries have incorrect names or ordering
- You ran cleanup or merge operations that may have left stale entries

### Use setup-worktree.sh when:

- Creating a new worktree (it adds the entry with correct naming)

### Use teardown-worktree.sh when:

- Removing a worktree (it removes the entry by path)

### Do NOT use sync-workspace.sh when:

- You only need to modify workspace settings, extensions, or launch configs (use the vscode plugin's workspace-config-specialist instead)

## Prerequisites

**Required:**

- `jq` installed and on PATH
- Valid workspace file at the target path
- Repos directory exists

**Verification:**

```bash
command -v jq
ls /workspace/workspace.code-workspace
ls /workspace/repos/
```

## Usage

### CLI Syntax

```bash
sync-workspace.sh [OPTIONS]
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `-w, --workspace FILE` | Path to workspace file | `/workspace/workspace.code-workspace` |
| `-r, --repos-dir DIR` | Path to repos directory | `/workspace/repos` |
| `--dry-run` | Show what would change, do not modify | |
| `--check` | Exit 0 if in-sync, exit 1 if drift | |
| `--verbose` | Show detailed scan output | |
| `-h, --help` | Show help | |

### Exit Codes

| Code | Meaning | When |
|------|---------|------|
| 0 | Success / in-sync | Default mode or `--check` when no drift |
| 1 | Drift detected | `--check` mode only |
| 2 | Prerequisites missing | jq not installed, file not found |
| 3 | Invalid arguments | Unknown flags, missing values |

## How It Works

### Repo Detection Algorithm

The script iterates top-level directories under `/workspace/repos/`:

1. **Skip** hidden directories (`.crewchief`, `.obsidian`, `.DS_Store`)

2. **Flat clone** — the directory contains a `.git/` directory:
   - Entry name: `<dir-name> | main`
   - Entry path: `repos/<dir-name>`
   - Example: `django-olympics/.git/` → `"django-olympics | main"` at `repos/django-olympics`

3. **Wrapper directory** — no `.git` at top level; scan children:
   - Child with `.git/` directory → **main clone**: `"<wrapper> | main"` at `repos/<wrapper>/<child>`
   - Child with `.git` file → **worktree**: `"<wrapper> ⛙ <CHILD>"` at `repos/<wrapper>/<CHILD>`
   - Child with neither → skip (non-git directory)
   - Wrapper with zero git children → skip entirely

4. **Ordering**: devcontainer entry first, then all entries sorted alphabetically by name (case-insensitive). The `| main` entries naturally sort before `⛙` worktree entries for the same repo.

### Edge Cases

| Case | Handling |
|------|----------|
| Main dir name differs from wrapper (`mcp-quickbase/MCP-Quickbase`) | Uses wrapper name for display, actual dir name for path |
| Non-git child in wrapper (`crewchief/HEROSVG`) | Skipped — no `.git` file or directory |
| Test artifacts (`_test_exit6_17593`) | Skipped — no git children |
| Hidden dirs (`.crewchief`, `.obsidian`) | Skipped |
| Infographic HTML files | Skipped — not directories |

## Examples

### 1. Preview changes (recommended first use)

```bash
sync-workspace.sh --dry-run
```

Shows entries that would be added, removed, or reordered without modifying the file.

### 2. Check for drift (CI/hooks)

```bash
sync-workspace.sh --check
echo $?  # 0 = in-sync, 1 = drift
```

### 3. Full sync with verbose output

```bash
sync-workspace.sh --verbose
```

Scans repos, shows each detected repo/worktree, and updates the workspace file.

### 4. Custom paths

```bash
sync-workspace.sh -w /path/to/workspace.code-workspace -r /path/to/repos
```

## Related Skills

- **worktree-setup** — Creates worktrees with correct workspace entries (Step 3 passes `--name` with `⛙` convention)
- **worktree-teardown** — Removes worktrees and their workspace entries
- **workspace-manager** (vscode plugin) — Generic workspace settings, extensions, and launch configuration
