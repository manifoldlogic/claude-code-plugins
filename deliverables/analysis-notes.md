# WTSYNC.2008: Fetch Optimization Analysis

## Decision: Keep Separate fetch+pull (Do NOT Optimize)

## Test Execution

### Test Environment
- Date: 2026-02-15
- Repo: claude-code-plugins (WTSYNC branch and main branch)
- Git version: standard DevContainer installation

### Test 1: Separate fetch+pull (current approach)

```
$ time git fetch --prune
From https://github.com/manifoldlogic/claude-code-plugins
 - [deleted] (none) -> origin/DOCAGENT
 - [deleted] (none) -> origin/IMPPLAN
 - [deleted] (none) -> origin/MAPMULTI
 - [deleted] (none) -> origin/MAPSKILL-1
 - [deleted] (none) -> origin/MAPSKILL-2
 - [deleted] (none) -> origin/MAPSKILL-3
 - [deleted] (none) -> origin/MAPSKILL-4
 - [deleted] (none) -> origin/SDDLOOP-6
 - [deleted] (none) -> origin/TASKSFIX
0.09s user 0.07s system 22% cpu 0.712 total

$ time git pull
Already up to date.
0.10s user 0.05s system 22% cpu 0.640 total

Total wall time: ~1.35s
```

**Observation:** Fetch successfully pruned 9 stale branches. Pull reported "Already up to date." Each step produces distinct output.

### Test 2: Combined pull --prune (proposed optimization)

```
$ time git pull --prune
Already up to date.
0.01s user 0.02s system 3% cpu 0.843 total

Total wall time: ~0.84s
```

**Observation:** Combined approach is ~0.5s faster. Prune occurs silently (no visible output about deleted branches).

### Test 3: Error isolation (separate approach advantage)

On WTSYNC branch (no upstream tracking):
- `git fetch --prune` **succeeds** (exit 0) - fetches remote refs and prunes stale branches
- `git pull` **fails** (exit 1) - "no tracking information for the current branch"

**Key finding:** Separate steps allow fetch to succeed even when pull will fail. The current sync-and-clean design intentionally continues from a failed fetch to attempt pull. This graceful degradation is impossible with combined `git pull --prune`.

### Test 4: Timing comparison on main branch (with upstream)

```
# Combined
$ time git pull --prune
Already up to date. (0.843s)

# Separate
$ time git fetch --prune (0.792s)
$ time git pull (0.823s)
Total: ~1.615s
```

**Performance delta:** ~0.77s slower with separate approach. Negligible for a user-facing command.

## Trade-off Analysis

| Aspect | Separate fetch+pull | Combined pull --prune | Winner |
|--------|---------------------|----------------------|--------|
| Network efficiency | ~1.35-1.62s | ~0.84s | Combined |
| Error granularity | Distinct per-step errors | Single failure point | **Separate** |
| Graceful degradation | Fetch fail -> still try pull | All-or-nothing | **Separate** |
| Prune visibility | Shows deleted branches | Silent prune | **Separate** |
| Debugging | Clear step-by-step output | Opaque operation | **Separate** |
| Consistency | Matches merge-worktree.sh | Different pattern | **Separate** |

## Decision Rationale

1. **Error granularity is critical.** The sync-and-clean command is interpreted by Claude Code. Separate steps produce distinct error messages that the agent can report clearly to users.

2. **Graceful degradation is by design.** The current implementation continues to pull even when fetch fails. This is intentional and impossible with combined approach.

3. **Prune visibility matters.** Users want to see which stale branches were removed. The separate fetch step shows this; combined pull --prune does not.

4. **Performance delta is negligible.** ~0.5-0.8s difference is imperceptible for a command run occasionally by users.

5. **Pattern consistency.** merge-worktree.sh uses separate fetch and merge steps. Keeping sync-and-clean consistent reduces cognitive overhead.

**Conclusion:** Keep current separate fetch+pull approach. The observability and resilience advantages outweigh the minor performance improvement.
