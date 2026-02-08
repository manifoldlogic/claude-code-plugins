---
name: iterm-nine-section-structure
description: Standard 9-section organizational structure for all iTerm plugin shell scripts
origin: PANE-001
created: 2026-02-08
tags: [iterm, shell-scripting, code-organization, templates]
---

# iTerm Nine-Section Script Structure

## Overview

All shell scripts in the iTerm plugin follow a consistent 9-section organizational structure. This pattern ensures scripts are immediately recognizable, maintainable, and follow established conventions. The structure was established in `iterm-open-tab.sh` and is enforced for all new iTerm scripts.

This is an architectural standard, not a suggestion. New scripts that deviate from this structure will be rejected during code review.

## When to Use

Apply this structure when:

- Creating any new shell script in the iTerm plugin (`plugins/iterm/skills/*/scripts/*.sh`)
- Refactoring existing iTerm scripts for consistency
- Reviewing iTerm script pull requests for compliance
- Teaching new contributors about iTerm plugin conventions

## Pattern/Procedure

### The Nine Sections

Every iTerm script must contain these sections in this order, with comment headers:

```bash
#!/usr/bin/env bash
#
# script-name.sh - Brief description
#
# [Header documentation block with DESCRIPTION, USAGE, EXIT CODES, etc.]
#

set -euo pipefail

##############################################################################
# 1. Script Location and Sourcing
##############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ... sourcing utilities ...

##############################################################################
# 2. Trap Handler Setup
##############################################################################

trap _cleanup_temp_script EXIT INT TERM

##############################################################################
# 3. Default Values
##############################################################################

DEFAULT_PROFILE="Devcontainer"
# ... other defaults ...

##############################################################################
# 4. Usage Information
##############################################################################

show_help() {
    cat << 'EOF'
# ... help text ...
EOF
}

##############################################################################
# 5. Argument Parsing
##############################################################################

parse_arguments() {
    # ... argument parsing logic ...
}

##############################################################################
# 6. AppleScript Escaping
##############################################################################

escape_applescript_string() {
    # ... escaping logic ...
}

##############################################################################
# 7. AppleScript Generation
##############################################################################

build_applescript() {
    # ... AppleScript generation logic ...
}

##############################################################################
# 8. Main Execution
##############################################################################

main() {
    # ... main logic orchestration ...
}

##############################################################################
# Script Entry Point
##############################################################################

main "$@"
```

### Section Details

#### Section 1: Script Location and Sourcing

**Purpose:** Establish script location and source dependencies

**Contents:**
- `SCRIPT_DIR` calculation using `BASH_SOURCE[0]`
- Source `iterm-utils.sh` with error handling
- Any other required sourcing

**Example:**
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UTILS_DIR="$(cd "$SCRIPT_DIR/../../tab-management/scripts" && pwd)"

if ! source "$UTILS_DIR/iterm-utils.sh" 2>/dev/null; then
    echo "[ERROR] Failed to source iterm-utils.sh from $UTILS_DIR" >&2
    exit 3
fi
```

#### Section 2: Trap Handler Setup

**Purpose:** Register cleanup handlers before any operations

**Contents:**
- Single `trap` statement calling `_cleanup_temp_script` from iterm-utils.sh
- Must occur before any temp file operations

**Example:**
```bash
trap _cleanup_temp_script EXIT INT TERM
```

#### Section 3: Default Values

**Purpose:** Define constants and default values

**Contents:**
- All default values for script options
- Constants (if any)
- No logic, only assignments

**Example:**
```bash
DEFAULT_DIRECTION="vertical"
DEFAULT_PROFILE="Devcontainer"
DEFAULT_DIRECTORY="/workspace"
```

#### Section 4: Usage Information

**Purpose:** Provide help text via `show_help()` function

**Contents:**
- Function named `show_help()`
- Heredoc with complete usage documentation
- Includes: USAGE, OPTIONS, EXIT CODES, EXAMPLES, NOTES

**Example:**
```bash
show_help() {
    cat << 'EOF'
script-name.sh - Brief description

USAGE:
  script-name.sh [OPTIONS]

OPTIONS:
  -h, --help    Show help

EXIT CODES:
  0 - Success
  # ... etc
EOF
}
```

#### Section 5: Argument Parsing

**Purpose:** Parse and validate command-line arguments

**Contents:**
- Function named `parse_arguments()`
- While loop processing all arguments
- Validation logic for argument values
- Error handling for unknown flags

**Example:**
```bash
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            # ... other cases ...
        esac
        shift
    done
}
```

#### Section 6: AppleScript Escaping

**Purpose:** Escape strings for safe AppleScript embedding

**Contents:**
- Function named `escape_applescript_string()`
- Escapes backslashes and double quotes
- Takes input, returns escaped output

**Note:** This function is currently duplicated across scripts. Future cleanup may move it to iterm-utils.sh.

**Example:**
```bash
escape_applescript_string() {
    local input="$1"
    # Escape backslashes first, then double quotes
    local escaped="${input//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    printf '%s' "$escaped"
}
```

#### Section 7: AppleScript Generation

**Purpose:** Build the AppleScript to be executed

**Contents:**
- Function named `build_applescript()` or similar
- Takes parsed arguments as parameters
- Returns complete AppleScript as string
- Uses `cat << 'EOF'` for AppleScript template

**Example:**
```bash
build_applescript() {
    local direction="$1"
    local profile="$2"

    cat << 'EOF'
tell application "iTerm2"
    activate
    # ... AppleScript ...
end tell
EOF
}
```

#### Section 8: Main Execution

**Purpose:** Orchestrate the script's workflow

**Contents:**
- Function named `main()`
- Calls other functions in correct order
- Handles dry-run mode
- Validates preconditions (iTerm availability, SSH, etc.)
- Executes AppleScript via `run_applescript()`
- Reports success/failure

**Example:**
```bash
main() {
    parse_arguments "$@"

    local applescript
    applescript=$(build_applescript ...)

    if [[ "${ARG_DRY_RUN:-false}" == "true" ]]; then
        echo "$applescript"
        exit 0
    fi

    validate_iterm
    run_applescript "$applescript"
    iterm_ok "Operation completed successfully"
}
```

#### Entry Point

**Contents:**
- Single call to `main "$@"` at end of file

**Example:**
```bash
##############################################################################
# Script Entry Point
##############################################################################

main "$@"
```

## Examples

### Example 1: iterm-split-pane.sh

Complete implementation of the 9-section structure:

```
plugins/iterm/skills/pane-management/scripts/iterm-split-pane.sh
- 316 lines total
- 9 sections clearly marked with comment headers
- Each section contains expected components
- Model implementation for new scripts
```

### Example 2: iterm-open-tab.sh

Original template that established this pattern:

```
plugins/iterm/skills/tab-management/scripts/iterm-open-tab.sh
- 377 lines total
- Same 9 sections as iterm-split-pane.sh
- Proven in production with 87 passing tests
- Reference implementation
```

### Example 3: Verification Checklist

When reviewing a new iTerm script, verify:

```bash
# Check for all section headers
grep "Script Location and Sourcing" script.sh
grep "Trap Handler Setup" script.sh
grep "Default Values" script.sh
grep "Usage Information" script.sh
grep "Argument Parsing" script.sh
grep "AppleScript Escaping" script.sh
grep "AppleScript Generation" script.sh
grep "Main Execution" script.sh

# Verify strict mode
head -n 50 script.sh | grep "set -euo pipefail"

# Verify entry point
tail -n 5 script.sh | grep 'main "$@"'
```

## References

- Ticket: PANE-001
- Related files:
  - `plugins/iterm/skills/pane-management/scripts/iterm-split-pane.sh` (316 lines, full implementation)
  - `plugins/iterm/skills/tab-management/scripts/iterm-open-tab.sh` (377 lines, original template)
  - `plugins/iterm/skills/tab-management/scripts/iterm-close-tab.sh` (follows same pattern)
- Architecture document: `archive/tickets/PANE-001_core-split-script/planning/architecture.md` (Decision 1: Mirror iterm-open-tab.sh Structure Exactly)
