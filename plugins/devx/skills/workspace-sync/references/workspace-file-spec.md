# workspace.code-workspace Maintenance Spec

## File Location

`/workspace/workspace.code-workspace` (repository root of `dev-container`)

## Purpose

This file defines the VS Code / Cursor multi-root workspace. Every repo and worktree under `/workspace/repos/` must be represented as a folder entry so it's visible in the editor sidebar.

## Structure

The file is JSON with a single `folders` array and a `settings` object. Only `folders` is actively maintained.

## Folder Entry Format

Each entry has a `name` and a `path`.

### Naming Convention

**Main branch entry:**
```
"name": "<repo-name> | main"
```

**Worktree entry:**
```
"name": "<repo-name> ⛙ <WORKTREE-NAME>"
```

**devcontainer (always first):**
```
"name": "devcontainer"
```

The `⛙` character (U+26D9) is the literal separator for worktree entries. Do not substitute other characters.

### Path Convention

There are two repo layouts under `repos/`. The path depends on which layout a repo uses.

**Worktree-managed repos** have a parent directory containing subdirectories for main and each worktree:
```
repos/<repo-name>/<main-dir>        → main branch
repos/<repo-name>/<WORKTREE-NAME>   → worktree
```
Note: the main directory name may differ from the repo directory name (e.g., `mcp-quickbase/MCP-Quickbase`, `mattermost/mattermost-webapp`). Use whatever directory name actually exists on disk.

**Flat-clone repos** are cloned directly without a worktree wrapper:
```
repos/<repo-name>                   → main branch (path points here directly)
```
A flat clone has no parent wrapper directory — the repo contents (`.git/`, `src/`, etc.) are directly inside `repos/<repo-name>/`.

## Ordering Rules

1. **`devcontainer`** is always the first entry.
2. All remaining entries are sorted **alphabetically by `name`** (case-insensitive).
3. Because repo names sort together, this naturally groups a repo's main branch before its worktrees (` |` sorts before ` ⛙`).

## What Must Be Included

- Every directory under `repos/` that contains a git repository or is a git worktree gets an entry.
- Both the main branch and all active worktrees for each repo.

## What Must Be Excluded

- Empty directories, test artifacts, non-repo files (e.g., `*.html` infographics, `README.md`).
- Worktree directories that are empty or broken (no `.git` file inside).
- Stale entries pointing to paths that no longer exist on disk.

## When to Update

The workspace file must be updated whenever:
- A new repo is cloned into `repos/`
- A worktree is created or deleted
- A repo is removed from `repos/`

## Validation Criteria

A correct workspace file satisfies all of these:
1. Every git repo and valid worktree under `repos/` has exactly one entry.
2. No entry points to a nonexistent path.
3. Entries are alphabetized by name (devcontainer first).
4. Names follow the exact `| main` / `⛙ WORKTREE` conventions.
5. The `settings` object is preserved as-is (do not add or remove settings).
