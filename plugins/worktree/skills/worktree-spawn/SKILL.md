---
name: worktree-spawn
description: Create git worktrees using CrewChief CLI with VS Code workspace integration.
---

# Worktree Spawn Skill

**Last Updated:** 2026-03-15

## Overview

The worktree-spawn skill orchestrates worktree creation by combining two operations:

1. Create git worktree using CrewChief CLI (`crewchief worktree create`)
2. Add worktree folder to VS Code workspace file via `workspace-folder.sh`

## Naming Rules

**CRITICAL: Use the user's exact input as the worktree name.**

When a user asks to create a worktree with a specific name:
- The worktree name MUST be the user's exact input, unchanged
- Do NOT add prefixes (e.g., "feature-", "bugfix-")
- Do NOT add suffixes (e.g., "-dev", "-wip")
- Do NOT convert case or reformat the name
- The branch name equals the worktree name
- The folder name equals the worktree name

Examples of correct behavior:
| User says | Worktree name | Branch name | Folder name |
|-----------|---------------|-------------|-------------|
| "create worktree PANE-001" | PANE-001 | PANE-001 | PANE-001 |
| "worktree for UIT-9819" | UIT-9819 | UIT-9819 | UIT-9819 |
| "create worktree my-feature" | my-feature | my-feature | my-feature |
| "worktree called bugfix-auth" | bugfix-auth | bugfix-auth | bugfix-auth |

The only transformation applied is validation: names must match [a-zA-Z0-9_-]+ and cannot start with a hyphen.

## Decision Tree

### Use crewchief worktree create when:
- You need to create a new worktree
- Working inside a devcontainer or any environment with CrewChief CLI
- You want fine-grained control over each operation

### Use standard git worktree when:
- Not using CrewChief CLI at all
- Working in non-devcontainer environments
- Simple worktree workflows without orchestration

## Prerequisites

### Environment Requirements

- Git repositories in `/workspace/repos` directory
- CrewChief CLI (`crewchief worktree` command) installed
- workspace-folder.sh script available for VS Code workspace updates (optional)
- jq installed for workspace updates (optional)

### Verification Commands

```bash
# Check CrewChief CLI
command -v crewchief

# Verify workspace-folder.sh script
ls ~/.devcontainer/scripts/workspace-folder.sh
```

## Usage

### Creating a Worktree

```bash
crewchief worktree create <worktree-name> --repo <repository> --branch <base-branch>
```

### Adding to VS Code Workspace

After creating the worktree, add it to the workspace file:

```bash
workspace-folder.sh add repos/<repo>/<worktree> --name "<repo> (<worktree>)"
```

### Combined Workflow

```bash
# 1. Create worktree from main branch
crewchief worktree create feature-auth --repo crewchief --branch main

# 2. Add to VS Code workspace
workspace-folder.sh add repos/crewchief/feature-auth --name "crewchief (feature-auth)"
```

## Examples

### 1. Basic Usage - Create worktree with workspace integration

```bash
crewchief worktree create feature-auth --repo crewchief --branch main
workspace-folder.sh add repos/crewchief/feature-auth --name "crewchief (feature-auth)"
```

**Use case:** Standard workflow for starting new feature development. Creates the worktree from main branch and adds it to your workspace file for easy navigation in VS Code.

### 2. Custom Base Branch

```bash
crewchief worktree create bugfix-login --repo crewchief --branch develop
workspace-folder.sh add repos/crewchief/bugfix-login --name "crewchief (bugfix-login)"
```

**Use case:** Working on a bugfix that needs to branch from develop instead of main.

### 3. Skip Workspace Update

```bash
crewchief worktree create quick-test --repo crewchief --branch main
```

**Use case:** Quickly create a worktree for temporary testing or experimentation without modifying the workspace file.

## SDD Workflow Integration

When working with the SDD (Spec-Driven Development) plugin, use worktree names that match ticket IDs for traceability:

```bash
# Start work on ticket MAPR-0001
crewchief worktree create MAPR-0001 --repo crewchief --branch main
workspace-folder.sh add repos/crewchief/MAPR-0001 --name "crewchief (MAPR-0001)"
```

**Benefits:**
- Worktree name matches ticket ID in the SDD system
- Easy to track work across multiple tickets and repositories

**Tip**: The SDD plugin's `do-task` and `do-all-tasks` commands may suggest creating worktrees with ticket IDs automatically.

## Related

- **worktree-management** - Core git worktree operations using CrewChief CLI (create, use, merge, clean)
- **workspace-folder.sh** - Manages folders in VS Code workspace files

For worktree lifecycle management (merging, cleaning up) after creation, see the worktree-management skill.

## See Also

- **devx:setup-worktree** - Full terminal-integrated worktree creation workflow with tab management
