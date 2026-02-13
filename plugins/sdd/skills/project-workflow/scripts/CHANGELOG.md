# Changelog

All notable changes to the autonomous SDD loop scripts will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-02-XX

### Breaking Changes

This release changes the directory structure assumptions and CLI interface. Version bumped to 2.0.0 (MAJOR) to signal breaking changes.

#### Directory Structure

**Old Model (1.x):**
- SDD data nested inside repos: `repos/<name>/_SDD/`
- Single workspace root parameter
- Discovery via recursive `find` for `_SDD` directories

**New Model (2.0):**
- SDD data in separate tree: `_SPECS/<name>/`
- Code in repos tree: `repos/<name>/<git-root>/`
- Separate specs root and repos root parameters
- Discovery via direct child listing of specs root

#### CLI Interface Changes

**master-status-board.sh:**

Old:
```bash
bash master-status-board.sh [workspace_root]
```

New:
```bash
bash master-status-board.sh [--specs-root <path>] [--repos-root <path>]
```

**sdd-loop.sh:**

Old:
```bash
bash sdd-loop.sh [workspace_root]
```

New:
```bash
bash sdd-loop.sh [--specs-root <path>] [--repos-root <path>]
```

#### Environment Variables

**Deprecated (still supported with warnings):**
- `WORKSPACE_ROOT` -> maps to `REPOS_ROOT`
- `SDD_LOOP_WORKSPACE_ROOT` -> maps to `SDD_LOOP_REPOS_ROOT`

**New:**
- `SPECS_ROOT` / `SDD_LOOP_SPECS_ROOT` - location of SDD data
- `REPOS_ROOT` / `SDD_LOOP_REPOS_ROOT` - location of code repositories

### Migration Guide

#### For master-status-board.sh Users

1. **If using default paths:**
   - No changes required if your workspace follows the new structure
   - Default specs root: `/workspace/_SPECS/`
   - Default repos root: `/workspace/repos/`

2. **If using custom paths:**
   - Replace single workspace root with dual roots:
     ```bash
     # Old
     bash master-status-board.sh /custom/workspace/

     # New
     bash master-status-board.sh --specs-root /custom/_SPECS/ --repos-root /custom/repos/
     ```

3. **If using WORKSPACE_ROOT env var:**
   - Update to use new env vars:
     ```bash
     # Old (deprecated but still works)
     WORKSPACE_ROOT=/custom/repos/ bash master-status-board.sh

     # New
     SPECS_ROOT=/custom/_SPECS/ REPOS_ROOT=/custom/repos/ bash master-status-board.sh
     ```
   - Deprecation warning will be logged if old env var is used

#### For sdd-loop.sh Users

Same migration steps as above, but use `SDD_LOOP_SPECS_ROOT` and `SDD_LOOP_REPOS_ROOT` env vars.

#### Directory Structure Migration

If your workspace still uses the old `repos/<name>/_SDD/` structure, you must reorganize:

```bash
# Example migration (adjust paths as needed)
mkdir -p /workspace/_SPECS/
for repo in /workspace/repos/*/; do
    repo_name=$(basename "$repo")
    if [ -d "$repo/_SDD" ]; then
        mv "$repo/_SDD" "/workspace/_SPECS/$repo_name"
    fi
done
```

### Changed

- Discovery mechanism: from recursive `find` to direct child listing (faster, simpler)
- Repo name derivation: from parent directory to SDD directory name itself
- Path bounds validation: from single root to dual-root validation
- JSON output: added `specs_root` and `repos_root` top-level fields
- Missing repo handling: specs dirs with no matching repo now included in output with `repo_path: null`

### Added

- `find_git_root()` helper function in sdd-loop.sh for git root discovery
- Support for git root names differing from parent directory (e.g., `mattermost/mattermost-webapp`)
- Deprecation warnings for old environment variables
- Dual-root path bounds validation

### Removed

- `MAX_SEARCH_DEPTH` configuration constant (no longer needed)
- Recursive `find` based discovery (replaced with direct listing)

## [1.0.0] - 2026-01-XX

Initial release with single-root workspace model.
