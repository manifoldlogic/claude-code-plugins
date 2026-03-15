# devx Plugin

Developer experience orchestration layer for multi-plugin development workflows.

## Purpose

The devx plugin composes multiple plugins (worktree, cmux, vscode) into streamlined commands that automate common development workflows. Instead of manually running separate commands across plugins, devx provides single-command orchestration.

## Commands

| Command | Description |
|---------|-------------|
| `/devx:setup-worktree` | Create a worktree with full development environment setup |

## Dependencies

The devx plugin delegates to these plugins:

- **worktree** - Git worktree creation via `ccwt create`
- **cmux** - Terminal workspace management via `cmux`
- **vscode** - VS Code workspace file management via `workspace-folder.sh`

## Skills

| Skill | Description |
|-------|-------------|
| `worktree-setup` | Orchestrates worktree creation with terminal and editor integration |
