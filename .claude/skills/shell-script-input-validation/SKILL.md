---
name: shell-script-input-validation
description: Validate and reject dangerous input patterns in shell scripts to prevent command injection vulnerabilities
origin: PANE-004
created: 2026-02-09
tags: [security, shell-scripting, input-validation, command-injection]
---

# Shell Script Input Validation

## Overview

This skill covers the pattern for validating user input in shell scripts to prevent command injection vulnerabilities. When shell scripts accept task descriptions, file paths, or other user-provided strings that will be embedded in commands or passed to other programs, input validation is critical to prevent newline injection, command substitution, variable expansion, and other attack vectors.

This pattern was established in spawn-agent.sh and applies to any shell script in this repo that accepts user input.

## When to Use

Use this validation pattern when:
- Accepting task descriptions or user input that will be passed to external commands
- Building command strings dynamically from user-provided data
- Embedding user input in AppleScript, SSH commands, or other command contexts
- Creating scripts that might be used in multi-user or automated environments

## Pattern/Procedure

### Validation Block Placement

Add input validation after argument parsing completes and before any function calls that use the input. This ensures all inputs are collected but validated before use.

### Critical Patterns to Reject

Implement validation checks for these dangerous patterns:

```bash
# 1. Newline detection (breaks AppleScript and multi-line contexts)
if [[ "$TASK" =~ $'\n' ]]; then
    error "Task description cannot contain newlines"
    exit 1
fi

# 2. Backtick detection (command substitution)
if [[ "$TASK" =~ \` ]]; then
    error "Task description cannot contain backticks"
    exit 1
fi

# 3. Command substitution detection $(...)
if [[ "$TASK" =~ \$\( ]]; then
    error "Task description cannot contain command substitution (\$())"
    exit 1
fi

# 4. Variable expansion detection ${...}
if [[ "$TASK" =~ \$\{ ]]; then
    error "Task description cannot contain variable expansion (\${})"
    exit 1
fi
```

### Using Repo Error Handling

Use the existing `error()` function for consistent error messages:

```bash
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
```

Error messages should:
- Be clear and actionable
- Include the specific pattern that was rejected
- Provide guidance on what is allowed
- Exit with code 1 for validation failures

### Backward Compatibility

Validation should only reject dangerous patterns, not normal usage:
- Empty strings are valid (if semantically appropriate)
- Normal text with spaces, punctuation, and special chars like `!`, `?`, `@` should pass
- Run existing test suites to verify no regressions

## Examples

### Complete Validation Block

From `/workspace/.devcontainer/scripts/spawn-agent.sh` (after argument parsing, before main dispatcher):

```bash
# Input validation (prevent command injection)
if [[ -n "$TASK" ]]; then
    # Reject newlines
    if [[ "$TASK" =~ $'\n' ]]; then
        error "Task description cannot contain newlines"
        exit 1
    fi

    # Reject backticks
    if [[ "$TASK" =~ \` ]]; then
        error "Task description cannot contain backticks"
        exit 1
    fi

    # Reject command substitution
    if [[ "$TASK" =~ \$\( ]]; then
        error "Task description cannot contain command substitution (\$())"
        exit 1
    fi

    # Reject variable expansion
    if [[ "$TASK" =~ \$\{ ]]; then
        error "Task description cannot contain variable expansion (\${})"
        exit 1
    fi
fi

# Additional parameter validation
if [[ "$DIRECTION" != "vertical" && "$DIRECTION" != "horizontal" ]]; then
    error "Invalid direction: $DIRECTION (must be vertical or horizontal)"
    exit 1
fi
```

### What Gets Rejected

```bash
# These inputs would be rejected:
spawn-agent.sh /path $'line1\nline2' --pane        # Newline
spawn-agent.sh /path 'run `date`' --pane           # Backtick
spawn-agent.sh /path 'run $(whoami)' --pane        # Command substitution
spawn-agent.sh /path 'show ${HOME}' --pane         # Variable expansion
```

### What Gets Accepted

```bash
# These inputs pass validation:
spawn-agent.sh /path "Fix the auth bug" --pane
spawn-agent.sh /path "Review PR #42" --pane
spawn-agent.sh /path "Check /var/log/app.log for errors" --pane
spawn-agent.sh /path --pane                         # Empty task
```

## References

- Ticket: PANE-004
- Related files:
  - `/workspace/.devcontainer/scripts/spawn-agent.sh` (lines 77-108, validation implementation)
  - `/workspace/_SPECS/claude-code-plugins/tickets/PANE-004_agent-pane-spawn/tasks/PANE-004.3001_input-validation-sanitization.md`
  - `/workspace/_SPECS/claude-code-plugins/tickets/PANE-004_agent-pane-spawn/planning/security-review.md` (Section 8.3, 12.3, 12.4)
