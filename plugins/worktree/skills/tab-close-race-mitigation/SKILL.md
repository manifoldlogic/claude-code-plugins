**Status: Archived** -- This skill documents an iTerm-specific race condition that is no longer relevant. The worktree plugin no longer manages terminal tabs.

---

---
name: tab-close-race-mitigation
description: Capture iTerm tab pattern before directory changes to prevent race condition in self-closing scripts
origin: WTMERGE
created: 2026-02-11
tags: [iterm, tab-management, race-condition, worktree, shell-scripting]
---

# Tab Close Race Condition Mitigation

## Overview

This skill documents a subtle race condition that occurs when a shell script attempts to close its own iTerm tab after changing directories or removing the working directory. The problem: if iTerm updates the tab title based on the new current directory before `iterm-close-tab.sh` executes, the pattern matching will fail to find the tab.

The solution is to capture the tab pattern (title) BEFORE any directory changes or worktree removals, store it in a variable, and use that captured pattern when invoking `iterm-close-tab.sh` at the end of the script.

This pattern was identified during the WTMERGE ticket and should be adopted by other self-closing scripts like `cleanup-worktree.sh`.

## When to Use

Use this pattern when:

- A script will close its own iTerm tab as the final operation
- The script changes directory or removes the working directory before tab close
- The tab title follows a predictable pattern that might change during script execution
- You're using the iTerm plugin's pattern-matching tab close feature

Do not use this pattern for:

- Scripts that close OTHER tabs (not their own)
- Scripts that don't change directory before tab close
- Scripts running outside iTerm (the pattern is iTerm-specific)

## Pattern/Procedure

### Implementation Steps

1. **Capture tab pattern EARLY in script execution:**
   ```bash
   # Capture the tab pattern BEFORE changing directory or removing worktree
   # This must happen before any cd commands or crewchief worktree merge/remove
   TAB_PATTERN="$REPO $WORKTREE_NAME"
   debug "Captured tab pattern: $TAB_PATTERN"
   ```

   The pattern should match the actual tab title format used by your iTerm configuration. In worktree scripts, the convention is `"<repo> <worktree>"`.

2. **Execute directory-changing or worktree-removing operations:**
   ```bash
   # Change to main worktree directory
   cd "$MAIN_WORKTREE_PATH"

   # OR: Remove the worktree entirely
   crewchief worktree merge "$WORKTREE_NAME"  # This removes the feature worktree directory
   ```

   After this point, the shell's cwd may be invalid or different, and iTerm may update the tab title.

3. **Use the captured pattern for tab close:**
   ```bash
   # Use the CAPTURED pattern, not a newly computed one
   if "$ITERM_CLOSE_TAB_SCRIPT" --force "$TAB_PATTERN"; then
       success "Tab closed"
   else
       warn "Could not close tab '$TAB_PATTERN'. Please close manually."
   fi
   ```

4. **Make tab close non-fatal:**
   ```bash
   # Tab close failure should not cause the entire operation to fail
   # Use exit code 10 (success with warnings) if tab close fails after critical work succeeds
   if [[ ${#WARNINGS[@]} -gt 0 ]]; then
       exit 10  # Success with warnings
   else
       exit 0   # Complete success
   fi
   ```

### Where to Capture the Pattern

The capture location depends on when directory changes occur:

**For merge-worktree.sh (cd happens mid-script):**
```bash
# After argument parsing and validation, BEFORE cd to main worktree
WORKTREE_NAME="feature-x"
REPO="myproject"

# Capture here (before any directory changes)
TAB_PATTERN="$REPO $WORKTREE_NAME"

# ... confirmation prompt ...

# Now safe to change directory
cd "$MAIN_WORKTREE_PATH"
crewchief worktree merge "$WORKTREE_NAME"

# ... later ...
iterm-close-tab.sh --force "$TAB_PATTERN"  # Uses captured pattern
```

**For cleanup-worktree.sh (worktree removal happens mid-script):**
```bash
# After argument parsing and validation, BEFORE worktree removal
TAB_PATTERN="$REPO $WORKTREE_NAME"

# ... confirmation prompt ...

# Worktree removal invalidates cwd
crewchief worktree remove "$WORKTREE_NAME"

# Tab close uses captured pattern
iterm-close-tab.sh --force "$TAB_PATTERN"
```

## Examples

### Example 1: Race Condition Without Mitigation (Problem)

Script WITHOUT pattern capture:

```bash
cd "$MAIN_WORKTREE_PATH"
crewchief worktree merge "PANE-001"

# Compute pattern AFTER directory change - WRONG!
TAB_PATTERN="$REPO $WORKTREE_NAME"

# At this point, iTerm may have already updated tab title to reflect new cwd
# Pattern match may fail to find the tab
iterm-close-tab.sh --force "$TAB_PATTERN"
# Result: Tab not found, manual cleanup required
```

Timeline of events:
1. Script changes directory to main worktree
2. Script invokes crewchief merge, which removes feature worktree directory
3. iTerm detects cwd change and updates tab title (RACE CONDITION)
4. Script computes tab pattern
5. iterm-close-tab.sh searches for pattern but tab title has changed
6. Tab close fails

### Example 2: Race Condition WITH Mitigation (Solution)

Script WITH pattern capture:

```bash
# Capture pattern BEFORE directory change - CORRECT!
TAB_PATTERN="$REPO $WORKTREE_NAME"
debug "Captured tab pattern: $TAB_PATTERN"

cd "$MAIN_WORKTREE_PATH"
crewchief worktree merge "PANE-001"

# Use captured pattern (not recomputed)
iterm-close-tab.sh --force "$TAB_PATTERN"
# Result: Tab closes successfully
```

Timeline of events:
1. Script captures tab pattern while cwd is still feature worktree
2. Script changes directory and removes feature worktree
3. iTerm may update tab title (doesn't matter now)
4. Script uses previously captured pattern
5. iterm-close-tab.sh finds and closes tab (may match old title before update)
6. Tab closes successfully

### Example 3: Non-Fatal Tab Close

Even with mitigation, tab close may fail due to timing or multiple tabs with similar names. The script should treat this as non-fatal:

```bash
WARNINGS=()

# ... capture pattern, do critical work ...

if "$ITERM_CLOSE_TAB_SCRIPT" --force "$TAB_PATTERN"; then
    success "Tab closed"
else
    warn "Could not close tab '$TAB_PATTERN'. Please close manually."
    WARNINGS+=("Tab close failed for: $TAB_PATTERN")
fi

# Exit with success-with-warnings if tab close failed
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo "Operation completed with warnings. Manual cleanup may be needed."
    exit 10
else
    exit 0
fi
```

Output:
```
[OK] Worktree merged successfully
[WARN] Could not close tab 'myproject PANE-001'. Please close manually.

Operation completed with warnings. Manual cleanup may be needed.
```

Exit code: 10 (success with warnings)

## Known Limitations

Even with this mitigation:

1. **Multiple tabs with similar names**: If multiple tabs have titles matching the pattern, the wrong tab may be closed.
2. **iTerm synchronous title update**: If iTerm updates the tab title synchronously (before AppleScript executes), matching may still fail.
3. **User renames tab manually**: If the user manually changed the tab title, pattern matching will always fail.

These limitations are acceptable because:
- The critical work (merge, cleanup) has already succeeded
- Tab cleanup is a convenience feature, not a requirement
- The script provides clear manual cleanup instructions when tab close fails
- Exit code 10 distinguishes "success with warnings" from "failure"

## References

- Ticket: WTMERGE
- Implementation: `/workspace/.devcontainer/scripts/merge-worktree.sh` lines 901-903 (capture), 962-975 (tab close)
- Architecture: `/workspace/_SPECS/claude-code-plugins/tickets/WTMERGE_worktree-merge-skill/planning/architecture.md` Component 6 "Tab Close Race Condition"
- Related files: `/workspace/.devcontainer/scripts/cleanup-worktree.sh` (should adopt this pattern)
- iTerm plugin: `plugins/iterm/skills/tab-management/scripts/iterm-close-tab.sh` (the tab close script being invoked)
