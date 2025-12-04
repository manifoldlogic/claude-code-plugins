# Bash Tool Use Hook - Git Safety

Block dangerous git commands that permanently delete uncommitted work.

## Blocked Commands

The following commands are **BLOCKED** and will cause the Bash tool to return an error:

### `git reset --hard`
Permanently deletes uncommitted changes without any recovery mechanism.

**Why blocked**: During ticket workflows, agents implement code, test it, and then commit. If an agent runs `git reset --hard` to sync with origin, all uncommitted implementation work is permanently lost.

**Safe alternative**:
```bash
git stash push -m "WIP: description"
git fetch origin
git rebase origin/main
git stash pop
```

### `git clean -fd` / `git clean -fdx`
Permanently deletes untracked files and directories.

**Why blocked**: These commands delete files that haven't been committed yet, with no way to recover them.

**Safe alternative**:
```bash
# Preview what would be deleted
git clean -fdn

# Then selectively delete if needed
rm -rf specific/directory
```

## How This Hook Works

This hook intercepts all Bash tool calls and checks if the command contains any of the blocked patterns. If found, it returns an error with a message explaining why the command is blocked and suggesting safe alternatives.

## Override

If you absolutely must run these commands:
1. Run them directly in your terminal (outside of Claude Code)
2. Or temporarily disable this hook in the plugin configuration

## Incident That Led to This Hook

**MRMIGNR-2001 (2025-12-04)**: The commit-ticket agent ran `git reset --hard origin/main` to sync with upstream, permanently deleting:
- New implementation file: `crates/maproom/src/cli/clean_ignored.rs` (318 lines)
- Modified files: `main.rs`, `mod.rs`, `sqlite/mod.rs`, `CLAUDE.md`
- Updated ticket status
- 5 passing unit tests

The implementation was complete and verified, but lost before commit. This hook prevents recurrence.
