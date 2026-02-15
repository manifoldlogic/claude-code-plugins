# Worktree Plugin

## Introduction

The Worktree plugin provides Git worktree management capabilities powered by the crewchief CLI. It enables Claude Code to create, manage, and merge parallel development branches safely without disrupting your main working directory. With the Worktree plugin, you can work on multiple features simultaneously in isolated environments, experiment safely, and maintain clean separation between different development tasks.

## Features

- **Parallel Development**: Work on multiple features or bug fixes simultaneously without branch switching
- **Isolated Environments**: Each worktree is a separate directory with its own checkout, preventing conflicts
- **Safe Merge**: Merge worktrees back to main with built-in safety checks and automatic cleanup
- **Smart Cleanup**: Remove worktrees with SDD ticket status awareness to prevent accidental cleanup of incomplete work
- **Sync and Clean**: Pull latest changes and prune stale branches for a worktree in one command
- **Branch Management**: Create, list, and manage git worktrees with simple commands
- **Status Tracking**: View all active worktrees and their current state
- **VS Code Integration**: Automatic workspace file updates when spawning or cleaning up worktrees
- **Bulk Tab Opening**: Open iTerm tabs for all worktrees of a repository in a single command
- **Repository-Aware Tab Names**: Tabs use `"<repo> <worktree>"` format (e.g., `"crewchief MAPR-0001"`) for clear multi-repo context

## Breaking Changes

### Tab Naming Format (v0.2.0)

**Change**: Tab naming format changed from `"worktree: <name>"` to `"<repo> <worktree>"`.

**Impact**: External scripts or automation that match iTerm tab names by pattern will need updates.

**Migration**:
- Old pattern: `"worktree: feature-test"`
- New pattern: `"crewchief feature-test"`

If you have external scripts using the old pattern, update your tab name matching logic:
```bash
# Old
iterm-close-tab.sh "worktree: feature-test"

# New
iterm-close-tab.sh "crewchief feature-test"
```

**Benefit**: The new format includes the repository name, making it easier to work with multiple repositories simultaneously. When you have worktrees across different repos, tab names like `"crewchief MAPR-0001"` and `"claude-code-plugins FEAT-auth"` are immediately distinguishable.

## Prerequisites

Before using the Worktree plugin, ensure you have:

1. **crewchief CLI installed**: The plugin requires the `crewchief` command-line tool to be available in your system PATH
2. **Git repository context**: You must be working within a git repository to use worktree functionality
3. **Clean working state**: Best practice is to have a clean working directory before creating worktrees

To verify your setup:
```bash
# Check CLI is installed
crewchief --version

# Verify you're in a git repository
git status

# List existing worktrees
crewchief worktree list
```

## Installation

Install the Worktree plugin using the Claude Code plugin command:

```
/plugin install worktree@crewchief
```

Once installed, the plugin will automatically be available for use in your Claude Code sessions.

## Usage Examples

### Feature Development Workflow
```
Create a new worktree for implementing user authentication
```
The plugin will create a new git worktree in an isolated directory where you can develop the authentication feature without affecting your main branch.

### Working on Multiple Features
```
I need to work on the login feature and the dashboard redesign simultaneously
```
Creates separate worktrees for each feature, allowing parallel development without branch switching.

### Experimenting Safely
```
Create a worktree to experiment with refactoring the database layer
```
Sets up an isolated environment where you can safely experiment without risk to your main codebase.

### Merging Completed Work
```
Merge the authentication worktree back to main
```
Safely merges the completed feature back to the main branch with automatic cleanup of the worktree.

```bash
# Merge with explicit arguments
/worktree:merge feature-auth

# Auto-detect from current worktree directory
/worktree:merge

# Preview merge operations first
merge-worktree.sh feature-auth --repo myproject --dry-run
```

### Syncing and Cleaning a Worktree
```
Pull latest changes and prune stale branches for the authentication worktree
```
Syncs the worktree with the remote tracking branch and removes stale remote references.

```bash
# Sync with explicit worktree name
/worktree:sync-and-clean feature-auth

# Auto-detect from current worktree directory
/worktree:sync-and-clean
```

### Cleaning Up with Ticket Awareness
```
Remove the experimental-refactor worktree
```
Cleanly removes the worktree and optionally deletes the associated branch. If an SDD ticket is associated with the worktree and has incomplete tasks, you'll be prompted to confirm before cleanup to prevent accidental data loss.

### Safe Cleanup with Dry-Run
```
Show me what would happen if I cleaned up the feature-auth worktree
```
Preview cleanup operations without making changes using dry-run mode.

### Opening All Worktree Tabs at Once
```bash
open-all-worktrees.sh --repo crewchief
```
Opens iTerm tabs for all non-main worktrees of a repository. Each tab is named with the `"<repo> <worktree>"` format (e.g., `"crewchief MAPR-0001"`, `"crewchief FEAT-auth"`). Useful when starting a development session and you need to restore tabs for all active worktrees.

### Using Tab Names for Custom Automation
```bash
# Close a specific worktree tab by its name
iterm-close-tab.sh "crewchief feature-auth"

# Open a tab for a specific worktree
iterm-open-tab.sh --name "crewchief MAPR-0001" --directory "/workspace/repos/crewchief/MAPR-0001"
```
Tab names follow the `"<repo> <worktree>"` convention, enabling reliable tab management in external scripts.

## Troubleshooting

### CLI Not Found
**Problem**: Plugin reports `crewchief: command not found`

**Solution**:
- Verify the CLI is installed: `which crewchief`
- Ensure it's in your PATH
- If using a development build, run `pnpm build` in the crewchief repository

### Not in Git Repository
**Problem**: Commands fail with "not a git repository" error

**Solution**:
- Navigate to a git repository directory
- Initialize a git repository if needed: `git init`
- Verify with `git status`

### Worktree Already Exists
**Problem**: Cannot create worktree because name or branch already exists

**Solution**:
- List existing worktrees: `crewchief worktree list`
- Choose a different name for the new worktree
- Remove the existing worktree if no longer needed: `crewchief worktree remove <name>`

### Cannot Remove Worktree
**Problem**: Worktree removal fails due to uncommitted changes

**Solution**:
- Navigate to the worktree directory
- Commit or stash your changes: `git commit` or `git stash`
- Alternatively, use force removal (warning: loses uncommitted changes)

### Merge Conflicts
**Problem**: Merging a worktree results in conflicts

**Solution**:
- The plugin will report conflicts and stop the merge
- Manually resolve conflicts in the worktree directory
- Complete the merge using standard git commands: `git add` and `git commit`
- Then retry the merge operation

### Branch Tracking Issues
**Problem**: Worktree branch isn't tracking correctly

**Solution**:
- Check branch status: `git branch -vv` in the worktree directory
- Set upstream if needed: `git branch -u origin/<branch>`
- Ensure you've pushed the branch to remote if collaboration is needed

## Skills Reference

This plugin provides the following skills with detailed documentation:

| Skill | Description | Documentation |
|-------|-------------|---------------|
| worktree-spawn | Create new worktrees with iTerm and VS Code workspace integration | [SKILL.md](skills/worktree-spawn/SKILL.md) |
| worktree-open-all | Open iTerm tabs for all worktrees of a repository | [SKILL.md](skills/worktree-open-all/SKILL.md) |
| worktree-management | Core git worktree operations (create, use, merge, clean) | [SKILL.md](skills/worktree-management/SKILL.md) |
| worktree-merge | Merge a worktree back to main and clean up environment (PR check, sync, merge, workspace cleanup, tab close) | [SKILL.md](skills/worktree-merge/SKILL.md) |
| worktree-cleanup | Remove worktrees with SDD ticket status awareness | [SKILL.md](skills/worktree-cleanup/SKILL.md) |

## Directory Structure

```text
plugins/worktree/
├── .claude-plugin/
│   └── plugin.json
├── commands/
│   ├── merge.md
│   └── sync-and-clean.md
├── skills/
│   ├── worktree-spawn/
│   │   └── SKILL.md
│   ├── worktree-open-all/
│   │   └── SKILL.md
│   ├── worktree-management/
│   │   └── SKILL.md
│   ├── worktree-merge/
│   │   ├── SKILL.md
│   │   └── scripts/
│   │       ├── merge-worktree.sh
│   │       └── test-merge-worktree.sh
│   └── worktree-cleanup/
│       └── SKILL.md
└── README.md
```

## Related Scripts

The worktree plugin integrates with helper scripts in the devcontainer environment:

- **spawn-worktree.sh** - Orchestrates worktree creation with iTerm tab (named `"<repo> <worktree>"`) and workspace integration
- **open-all-worktrees.sh** - Opens iTerm tabs for all non-main worktrees of a repository in a single command
- **merge-worktree.sh** - Orchestrates worktree merge-and-teardown with PR check, main sync, crewchief merge, workspace cleanup, and tab close (packaged at `skills/worktree-merge/scripts/`)
- **cleanup-worktree.sh** - Orchestrates worktree cleanup with ticket status checking and automatic tab closing
- **workspace-folder.sh** - Manages VS Code workspace file folder entries
- **worktree-common.sh** - Shared library with common logging, validation, and utility functions used by all worktree scripts

### SSH Connection Performance

The devcontainer is configured with SSH multiplexing (ControlMaster) for connections to `host.docker.internal`. This reduces the ~100ms overhead per SSH call by reusing connections, significantly improving script performance when opening multiple iTerm tabs or running bulk worktree operations. The configuration is applied automatically during container setup via `post-create.sh`.
