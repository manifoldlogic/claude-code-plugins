# Exit Code Reference

## Overview

This document defines the comprehensive exit code scheme used throughout the SDD automation framework. All scripts, modules, and functions use these standardized exit codes to communicate status and enable proper error handling.

## Exit Code Categories

Exit codes are organized into logical categories for easier understanding and handling:

| Range | Category | Description |
|-------|----------|-------------|
| 0 | Success | Normal, successful completion |
| 1 | Usage | Command-line argument errors |
| 2 | Configuration | Configuration file or validation errors |
| 3 | Module | Module loading or interface errors |
| 4 | Initialization | Startup and setup errors |
| 5 | Workflow | Business logic execution errors |
| 6 | State | State persistence and recovery errors |
| 7 | External | External tool/service errors |
| 8 | Permission | Filesystem permission errors |
| 9 | Resource | System resource errors |
| 10 | Unexpected | Unhandled or unknown errors |

---

## Detailed Exit Code Reference

### Exit Code 0: Success

**Category:** Success

**Meaning:** The operation completed successfully without errors.

**When to Use:**
- Function or script completed its intended purpose
- All validations passed
- All operations succeeded

**Example Scenarios:**
- Orchestrator completed full workflow run
- Module function returned expected result
- State file saved successfully
- Configuration validated successfully

**Orchestrator Handling:** Normal termination, report success to user.

**Example:**
```bash
# Successful completion
run_workflow
log_info "Workflow completed successfully"
exit 0
```

---

### Exit Code 1: Usage Error

**Category:** Usage

**Meaning:** Invalid command-line arguments or missing required options.

**When to Use:**
- Required argument missing
- Invalid argument value
- Mutually exclusive options used together
- Unknown option provided

**Example Scenarios:**
- `orchestrator.sh` called without input mode (`--jql`, `--epic`, etc.)
- Invalid JQL syntax provided
- `--resume` with non-existent run ID format

**Orchestrator Handling:** Display help text, exit immediately without starting workflow.

**Example:**
```bash
# Missing required argument
if [ -z "$INPUT_TYPE" ]; then
    log_error "No input mode specified. Use --jql, --epic, --team, or --tickets"
    show_usage
    exit 1
fi

# Invalid option value
case "$INPUT_TYPE" in
    jql|epic|team|tickets|resume) ;;
    *)
        log_error "Invalid input type: $INPUT_TYPE"
        exit 1
        ;;
esac
```

---

### Exit Code 2: Configuration Error

**Category:** Configuration

**Meaning:** Configuration file missing, unreadable, invalid JSON, or failed validation.

**When to Use:**
- Config file not found
- Config file is not valid JSON
- Required config field missing
- Config field has invalid value or type
- Config validation logic failed

**Example Scenarios:**
- `config/default.json` does not exist
- JSON syntax error in config file
- `retry.max_attempts` is negative or not a number
- `logging.level` is not one of `debug|info|warn|error`
- `sdd_root` directory does not exist

**Orchestrator Handling:** Log specific error, exit before module loading.

**Example:**
```bash
# Config file not found
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Configuration file not found: $CONFIG_FILE"
    exit 2
fi

# Invalid JSON
if ! validate_json "$(cat "$CONFIG_FILE")"; then
    log_error "Configuration file is not valid JSON: $CONFIG_FILE"
    exit 2
fi

# Validation failed
if ! validate_config; then
    log_error "Configuration validation failed"
    exit 2
fi
```

---

### Exit Code 3: Module Loading Error

**Category:** Module

**Meaning:** A required module file could not be loaded or failed interface validation.

**When to Use:**
- Module file not found in `modules/` directory
- Module file has bash syntax error
- Module missing required function
- Module function has wrong signature

**Example Scenarios:**
- `modules/state-manager.sh` does not exist
- Syntax error prevents module from being sourced
- `state-manager` module missing `save_state` function
- Module function exists but doesn't return valid JSON

**Orchestrator Handling:** Log which module failed and why, exit before run initialization.

**Example:**
```bash
# Module file not found
source "modules/state-manager.sh" 2>/dev/null || {
    log_error "Failed to load module: modules/state-manager.sh"
    exit 3
}

# Interface validation failed
validate_module_interface "state-manager" "save_state" "load_state" "save_checkpoint" "restore_checkpoint" || {
    log_error "Module state-manager failed interface validation"
    exit 3
}
```

---

### Exit Code 4: Initialization Error

**Category:** Initialization

**Meaning:** Failed to initialize run environment (directories, state files, logging).

**When to Use:**
- Failed to create run directory
- Failed to initialize state file
- Failed to set up logging
- Run ID generation failed (collision after max attempts)

**Example Scenarios:**
- `runs/` directory cannot be created
- Initial `state.json` write failed
- Log file cannot be opened for writing
- 5 consecutive run ID collisions

**Orchestrator Handling:** Log error, attempt cleanup of partial initialization, exit.

**Example:**
```bash
# Failed to create run directory
run_dir="${SDD_ROOT}/automation/runs/${RUN_ID}"
if ! mkdir -p "$run_dir" 2>/dev/null; then
    log_error "Failed to create run directory: $run_dir"
    exit 4
fi

# Failed to generate unique run ID
RUN_ID=$(generate_run_id) || {
    log_error "Failed to generate unique run ID after multiple attempts"
    exit 4
}

# Failed to initialize state
if ! save_state "$initial_state"; then
    log_error "Failed to initialize state file"
    rm -rf "$run_dir"  # cleanup
    exit 4
fi
```

---

### Exit Code 5: Workflow Error

**Category:** Workflow

**Meaning:** Error during workflow execution (JIRA fetch, decision making, stage execution).

**When to Use:**
- JIRA query returned error
- Decision engine failed to make decision
- SDD stage execution failed
- Ticket processing failed

**Example Scenarios:**
- JQL query syntax rejected by JIRA
- No tickets found matching criteria
- Claude decision timed out
- `/sdd:plan-ticket` command failed

**Orchestrator Handling:** Save checkpoint, attempt recovery via retry or skip, may continue with other tickets.

**Example:**
```bash
# JIRA fetch failed
fetch_result=$(fetch_tickets "$INPUT_TYPE" "$INPUT_VALUE")
if ! is_success "$fetch_result"; then
    error=$(extract_field "$fetch_result" "error")
    log_error "Failed to fetch tickets: $error"
    exit 5
fi

# Stage execution failed
stage_result=$(execute_stage "plan" "$ticket_key")
if ! is_success "$stage_result"; then
    next_action=$(extract_field "$stage_result" "next_action")
    case "$next_action" in
        retry) retry_with_backoff "execute_stage plan $ticket_key" ;;
        block) mark_ticket_blocked "$ticket_key"; continue ;;
        *)     exit 5 ;;
    esac
fi
```

---

### Exit Code 6: State Error

**Category:** State

**Meaning:** State management failed (save, load, checkpoint operations).

**When to Use:**
- State file write failed
- State file read/parse failed
- Checkpoint creation failed
- Checkpoint restore failed
- State file corrupted

**Example Scenarios:**
- Disk full during state save
- State file deleted mid-run
- Checkpoint file has invalid JSON
- State file has newer schema version

**Orchestrator Handling:** Log error with state file path, attempt to save emergency checkpoint, exit.

**Example:**
```bash
# State save failed
if ! save_state "$state_json"; then
    log_error "Failed to save workflow state"
    log_error "Manual recovery may be needed for run: $RUN_ID"
    exit 6
fi

# State load failed
result=$(load_state "$RUN_ID")
if ! is_success "$result"; then
    error=$(extract_field "$result" "error")
    log_error "Failed to load state for run $RUN_ID: $error"
    exit 6
fi

# Checkpoint corrupted
if ! validate_json "$checkpoint_content"; then
    log_error "Checkpoint file corrupted: $checkpoint_file"
    exit 6
fi
```

---

### Exit Code 7: External Tool Error

**Category:** External

**Meaning:** External tool not available, returned error, or timed out.

**When to Use:**
- Required tool not installed/found in PATH
- Tool execution returned non-zero
- Tool execution timed out
- Tool output unparseable

**Example Scenarios:**
- `claude` CLI not found
- `jq` not installed
- JIRA CLI (`acli`) authentication failed
- `gh` CLI not authenticated
- Claude CLI timeout (exceeded `decision.timeout_seconds`)

**Orchestrator Handling:** Log which tool failed and how, suggest remediation, exit.

**Example:**
```bash
# Tool not found
if ! command -v claude &>/dev/null; then
    log_error "Required tool not found: claude"
    log_error "Install Claude CLI: https://claude.ai/code"
    exit 7
fi

# Tool execution failed
if ! claude_output=$(timeout "${CONFIG_DECISION_TIMEOUT}s" claude -p "$prompt" 2>&1); then
    if [ $? -eq 124 ]; then
        log_error "Claude CLI timed out after ${CONFIG_DECISION_TIMEOUT}s"
    else
        log_error "Claude CLI failed: $claude_output"
    fi
    exit 7
fi

# Tool output unparseable
if ! validate_json "$tool_output"; then
    log_error "Tool returned invalid JSON: $(echo "$tool_output" | head -c 100)"
    exit 7
fi
```

---

### Exit Code 8: Permission Error

**Category:** Permission

**Meaning:** Filesystem permission denied for required operation.

**When to Use:**
- Cannot read required file
- Cannot write to required directory
- Cannot create required file
- Cannot delete temp file

**Example Scenarios:**
- Config file readable but state directory not writable
- Run directory exists but owned by different user
- Module file not readable
- Cannot set permissions on temp file

**Orchestrator Handling:** Log path and required permission, suggest `chmod`/`chown`, exit.

**Example:**
```bash
# Directory not writable
if [ ! -w "$state_dir" ]; then
    log_error "State directory not writable: $state_dir"
    log_error "Fix with: chmod u+w $state_dir"
    exit 8
fi

# File not readable
if [ ! -r "$config_file" ]; then
    log_error "Configuration file not readable: $config_file"
    log_error "Fix with: chmod u+r $config_file"
    exit 8
fi

# Permission denied during write
if ! echo "$content" > "$target_file" 2>/dev/null; then
    if [ $? -eq 1 ]; then
        log_error "Permission denied writing to: $target_file"
        exit 8
    fi
fi
```

---

### Exit Code 9: Resource Error

**Category:** Resource

**Meaning:** System resource exhausted or unavailable.

**When to Use:**
- Disk full
- Out of memory
- Too many open files
- Process limit reached

**Example Scenarios:**
- State file write fails due to full disk
- Fork failed due to process limit
- Memory allocation failed
- Network resource unavailable

**Orchestrator Handling:** Log resource type and suggested action, save minimal diagnostic info, exit.

**Example:**
```bash
# Disk full check before write
available_kb=$(df -k "$state_dir" | tail -1 | awk '{print $4}')
if [ "$available_kb" -lt 1024 ]; then
    log_error "Insufficient disk space in $state_dir (${available_kb}KB available)"
    log_error "Free space or use different directory"
    exit 9
fi

# Write failed - check if disk full
if ! echo "$content" > "$file"; then
    if [ "$(df -k "$(dirname "$file")" | tail -1 | awk '{print $4}')" -lt 10 ]; then
        log_error "Disk full, cannot write: $file"
        exit 9
    fi
fi
```

---

### Exit Code 10: Unexpected Error

**Category:** Unexpected

**Meaning:** Unhandled error condition or unknown failure.

**When to Use:**
- Error condition not matching other categories
- Bug in error handling logic
- Undefined behavior encountered
- Catch-all for truly unexpected situations

**Example Scenarios:**
- Reached "impossible" code path
- Error handler itself failed
- Unrecognized error code from subcommand
- State inconsistency detected

**Orchestrator Handling:** Log maximum diagnostic information, save state if possible, exit.

**Example:**
```bash
# Unexpected error catch-all
trap 'log_error "Unexpected error at line $LINENO: $BASH_COMMAND"; exit 10' ERR

# Unknown error code
case "$error_code" in
    0|1|2|3|4|5|6|7|8|9) ;; # known codes
    *)
        log_error "Unexpected error code: $error_code"
        log_error "Context: $context"
        exit 10
        ;;
esac

# Impossible state
if [ "$status" = "completed" ] && [ -z "$completed_at" ]; then
    log_error "Invalid state: completed but no completion timestamp"
    exit 10
fi
```

---

## Error Handling Best Practices

### 1. Exit Immediately on Critical Errors

```bash
set -euo pipefail  # Exit on error, undefined var, pipe failure

# Or use explicit checks
result=$(some_operation) || {
    log_error "Operation failed"
    exit 5
}
```

### 2. Log Before Exiting

Always log meaningful context before exiting:

```bash
# Bad
exit 5

# Good
log_error "Failed to process ticket $ticket_key at stage $stage"
log_error "Error: $error_message"
exit 5
```

### 3. Clean Up on Exit

```bash
cleanup() {
    # Remove temp files
    rm -f "${TEMP_FILES[@]}" 2>/dev/null
    # Save emergency state if possible
    if [ -n "$RUN_ID" ]; then
        log_debug "Saving emergency state before exit"
        save_state "$state_json" 2>/dev/null || true
    fi
}
trap cleanup EXIT
```

### 4. Use Specific Exit Codes

Choose the most specific applicable exit code:

```bash
# Bad - generic error
if [ ! -f "$config" ]; then
    exit 1
fi

# Good - specific error category
if [ ! -f "$config" ]; then
    log_error "Configuration file not found: $config"
    exit 2  # Configuration error
fi
```

### 5. Document Expected Exit Codes

```bash
# Function: validate_config
# Returns:
#   0 - Configuration is valid
#   2 - Configuration validation failed
validate_config() {
    # ...
}
```

---

## Exit Code Summary Table

| Code | Name | Category | Recoverable | Typical Action |
|------|------|----------|-------------|----------------|
| 0 | Success | - | N/A | Normal completion |
| 1 | Usage Error | Usage | Yes | Fix arguments, retry |
| 2 | Config Error | Config | Yes | Fix config file, retry |
| 3 | Module Error | Module | Yes | Fix module, retry |
| 4 | Init Error | Init | Sometimes | Check permissions/disk |
| 5 | Workflow Error | Workflow | Sometimes | Retry or skip ticket |
| 6 | State Error | State | Sometimes | Manual recovery |
| 7 | Tool Error | External | Sometimes | Install/configure tool |
| 8 | Permission Error | Permission | Yes | Fix permissions |
| 9 | Resource Error | Resource | Sometimes | Free resources |
| 10 | Unexpected | Unknown | No | Debug required |

---

## Cross-References

- **Architecture Document:** See `architecture.md` for component design
- **Module Interface:** See `module-interface-spec.md` for function specifications
- **Configuration:** See `config/default.json` for configuration options
