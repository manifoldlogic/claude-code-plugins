---
name: worktree-cwd-auto-detection
description: Auto-detect repository and worktree names from current directory using /workspace/repos path convention
origin: WTMERGE
created: 2026-02-11
tags: [worktree, shell-scripting, path-parsing, auto-detection]
---

# Worktree CWD Auto-Detection

## Overview

This skill documents the pattern for automatically detecting the repository name and worktree name from a user's current working directory in worktree lifecycle scripts. The pattern parses the devcontainer path convention `/workspace/repos/<repo>/<worktree>` and includes critical validation to reject the main worktree (where repo == worktree) and handle deeply nested subdirectories.

This pattern enables worktree scripts to provide a frictionless user experience: when the user is inside a feature worktree, the script can infer the target of the operation without requiring explicit arguments.

## When to Use

Use this pattern when:

- Implementing worktree lifecycle scripts (spawn, merge, cleanup) that should auto-detect from the user's current directory
- The user is likely to invoke the script from within the worktree they want to operate on
- You want to provide explicit override via positional arguments or flags as a fallback
- You need to reject operations on the main worktree (which should not be merged or removed)

Do not use this pattern for:

- Scripts that operate on multiple worktrees at once
- Operations where the cwd is unrelated to the target worktree
- Scripts running in CI/CD where explicit arguments are clearer

## Pattern/Procedure

### Implementation Steps

1. **Extract path components from PWD:**
   ```bash
   cwd="$(pwd)"
   repos_prefix="/workspace/repos/"

   # Check if under /workspace/repos/
   if [[ "$cwd" != ${repos_prefix}* ]]; then
       return 1  # Not in repos directory
   fi

   # Strip prefix to get relative path
   relative_path="${cwd#${repos_prefix}}"
   ```

2. **Parse first two path segments:**
   ```bash
   # Extract repo (first segment) and worktree (second segment)
   repo_segment="$(echo "$relative_path" | cut -d'/' -f1)"
   worktree_segment="$(echo "$relative_path" | cut -d'/' -f2)"

   # Must have both segments
   if [[ -z "$repo_segment" ]] || [[ -z "$worktree_segment" ]]; then
       return 1
   fi
   ```

3. **Check for main worktree (critical validation):**
   ```bash
   # If repo == worktree, user is in main worktree
   if [[ "$repo_segment" == "$worktree_segment" ]]; then
       error "You appear to be in the main worktree (/workspace/repos/$repo_segment/$worktree_segment)"
       error "Navigate to a feature worktree directory, or specify the worktree name explicitly."
       exit 3
   fi
   ```

4. **Validate both names:**
   ```bash
   # Use validate_worktree_name() from worktree-common.sh
   if ! validate_worktree_name "$repo_segment"; then
       return 1
   fi
   if ! validate_worktree_name "$worktree_segment"; then
       return 1
   fi
   ```

5. **Set detected values:**
   ```bash
   DETECTED_REPO="$repo_segment"
   DETECTED_WORKTREE="$worktree_segment"
   return 0
   ```

### Integration with Argument Parsing

The auto-detection function should be called only when positional arguments are missing:

```bash
# After parsing all flags, check if worktree name was provided
if [[ -z "$WORKTREE_NAME" ]]; then
    if detect_from_cwd; then
        WORKTREE_NAME="$DETECTED_WORKTREE"
        REPO="${REPO:-$DETECTED_REPO}"  # Use detected repo if --repo not specified
        info "Auto-detected from cwd: repo=$REPO worktree=$WORKTREE_NAME"
    else
        error "Could not auto-detect worktree from current directory: $(pwd)"
        error "Provide worktree name explicitly: $0 <worktree-name> --repo <repo>"
        show_help
        exit 3
    fi
fi
```

### Edge Cases Handled

1. **Deeply nested paths**: Works correctly from any subdirectory depth
   - Input: `/workspace/repos/myproject/PANE-001/src/components/Button.tsx`
   - Output: repo=myproject, worktree=PANE-001

2. **Main worktree detection**: Correctly identifies and rejects `/workspace/repos/<repo>/<repo>`
   - Input: `/workspace/repos/crewchief/crewchief/src/index.ts`
   - Output: Error message, exit 3

3. **Repo-level paths**: Fails gracefully when user is at repo level
   - Input: `/workspace/repos/crewchief`
   - Output: Cannot extract both segments, return 1

4. **Non-repos paths**: Fails gracefully for paths outside /workspace/repos
   - Input: `/home/user/projects/something`
   - Output: Not under repos prefix, return 1

## Examples

### Example 1: Basic Auto-Detection (Feature Worktree)

User is in a feature worktree subdirectory:

```bash
$ cd /workspace/repos/myproject/PANE-001/src
$ merge-worktree.sh
# Output: [INFO] Auto-detected from cwd: repo=myproject worktree=PANE-001
```

The script extracts:
- repo_segment = "myproject" (first path component after /workspace/repos/)
- worktree_segment = "PANE-001" (second path component)
- Validation passes: myproject != PANE-001 (not main worktree)

### Example 2: Main Worktree Detection (Error Case)

User is in the main worktree:

```bash
$ cd /workspace/repos/crewchief/crewchief
$ merge-worktree.sh
# Output:
# [ERROR] You appear to be in the main worktree (/workspace/repos/crewchief/crewchief)
# [ERROR] Navigate to a feature worktree directory, or specify the worktree name explicitly.
```

The script detects:
- repo_segment = "crewchief"
- worktree_segment = "crewchief"
- Validation fails: crewchief == crewchief (this is the main worktree)
- Script exits with code 3

### Example 3: Explicit Override

User provides explicit arguments, auto-detection is skipped:

```bash
$ cd /anywhere
$ merge-worktree.sh PANE-001 --repo myproject
# Auto-detection is not invoked; explicit args used
```

### Example 4: Outside /workspace/repos (Error Case)

User is outside the expected path:

```bash
$ cd /tmp
$ merge-worktree.sh
# Output:
# [ERROR] Could not auto-detect worktree from current directory: /tmp
# [ERROR] Provide worktree name explicitly: merge-worktree.sh <worktree-name> --repo <repo>
```

The detect_from_cwd function returns 1, triggering the error path in argument validation.

## References

- Ticket: WTMERGE
- Implementation: `/workspace/.devcontainer/scripts/merge-worktree.sh` lines 295-345 (detect_from_cwd function)
- Architecture: `/workspace/_SPECS/claude-code-plugins/tickets/WTMERGE_worktree-merge-skill/planning/architecture.md` Section "Component 2: CWD Auto-Detection"
- Tests: `/workspace/.devcontainer/scripts/test-merge-worktree.sh` Category 2 (CWD Auto-Detection Tests)
- Related files: `spawn-worktree.sh`, `cleanup-worktree.sh` (candidates for adopting this pattern)
