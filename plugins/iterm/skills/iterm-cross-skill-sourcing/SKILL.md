---
name: iterm-cross-skill-sourcing
description: Pattern for sourcing shared utilities from sibling skill directories in the iTerm plugin
origin: PANE-001
created: 2026-02-08
tags: [iterm, shell-scripting, code-organization]
---

# iTerm Cross-Skill Sourcing

## Overview

This skill documents the pattern for sourcing shared utilities from sibling skill directories within the iTerm plugin. The iTerm plugin uses a shared utilities file (`iterm-utils.sh`) located in the `tab-management` skill that must be sourced by scripts in other skills (like `pane-management`). This pattern ensures scripts can locate and source dependencies regardless of how they are invoked.

## When to Use

Use this pattern when creating new iTerm plugin scripts that need access to shared utilities:

- When creating scripts in the `pane-management` skill that need `iterm-utils.sh`
- When adding new skill directories to the iTerm plugin that require shared functions
- When refactoring existing scripts to use shared utilities
- When you see functions like `run_applescript()`, `is_container()`, `validate_iterm()` that are defined in `iterm-utils.sh`

## Pattern/Procedure

### Directory Structure Context

```
plugins/iterm/skills/
  tab-management/
    scripts/
      iterm-utils.sh          <-- SHARED utilities
      iterm-open-tab.sh
      iterm-list-tabs.sh
  pane-management/
    scripts/
      iterm-split-pane.sh     <-- Sources from sibling skill
```

### Sourcing Pattern

```bash
#!/usr/bin/env bash

set -euo pipefail

##############################################################################
# Script Location and Sourcing
##############################################################################

# Get absolute path of script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Compute path to sibling skill's scripts directory
UTILS_DIR="$(cd "$SCRIPT_DIR/../../tab-management/scripts" && pwd)"

# Source shared utilities with error handling
# shellcheck source=../../tab-management/scripts/iterm-utils.sh
if ! source "$UTILS_DIR/iterm-utils.sh" 2>/dev/null; then
    echo "[ERROR] Failed to source iterm-utils.sh from $UTILS_DIR" >&2
    exit 3
fi
```

### Key Elements

1. **Use `BASH_SOURCE[0]` not `$0`**: `BASH_SOURCE[0]` gives the script's path even when sourced
2. **Compute absolute path with `cd` and `pwd`**: Ensures the path works regardless of how the script is invoked
3. **Use relative path from SCRIPT_DIR**: Navigate up to skills level, then down to target skill
4. **Error handling**: Exit 3 (EXIT_INVALID_ARGS) if sourcing fails with descriptive error message
5. **Shellcheck directive**: Include source path comment for shellcheck static analysis

### Exit Code Convention

If sourcing fails, exit with code 3 (EXIT_INVALID_ARGS) to indicate a setup/configuration problem. This matches the iTerm plugin's exit code conventions:

- 0: Success
- 1: Connection failure (SSH)
- 2: iTerm unavailable
- 3: Invalid arguments or setup failure

## Examples

### Example 1: pane-management script sources from tab-management

From `plugins/iterm/skills/pane-management/scripts/iterm-split-pane.sh`:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$(cd "$SCRIPT_DIR/../../tab-management/scripts" && pwd)"

if ! source "$UTILS_DIR/iterm-utils.sh" 2>/dev/null; then
    echo "[ERROR] Failed to source iterm-utils.sh from $UTILS_DIR" >&2
    exit 3
fi

# Now can use functions from iterm-utils.sh:
is_container
validate_iterm
run_applescript "$applescript"
```

### Example 2: Future skill sourcing pattern

If creating a new `session-management` skill that needs utils:

```bash
# From plugins/iterm/skills/session-management/scripts/iterm-manage-session.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$(cd "$SCRIPT_DIR/../../tab-management/scripts" && pwd)"

if ! source "$UTILS_DIR/iterm-utils.sh" 2>/dev/null; then
    echo "[ERROR] Failed to source iterm-utils.sh from $UTILS_DIR" >&2
    exit 3
fi
```

### Example 3: Test scripts sourcing utilities

Test scripts in the `tests/` directory can also source utilities for validation:

```bash
# From plugins/iterm/skills/pane-management/tests/test-split-pane.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_SCRIPT="$SCRIPT_DIR/../../tab-management/scripts/iterm-utils.sh"

# Verify utils can be sourced (optional in tests)
if [[ -f "$UTILS_SCRIPT" ]]; then
    source "$UTILS_SCRIPT"
fi
```

## References

- Ticket: PANE-001
- Related files:
  - `plugins/iterm/skills/pane-management/scripts/iterm-split-pane.sh` (lines 44-52)
  - `plugins/iterm/skills/tab-management/scripts/iterm-utils.sh` (shared utilities)
  - Architecture document: `archive/tickets/PANE-001_core-split-script/planning/architecture.md` (section "Integration Points")
