# Module Interface Specification

## Overview

This document defines the interface contract that all automation framework modules must implement. These specifications ensure consistent behavior, predictable communication patterns, and reliable integration between the orchestrator and its modules.

## JSON Response Contract

All module functions that perform operations (vs. pure queries) MUST return JSON following this standard structure:

```json
{
  "success": boolean,
  "result": object | null,
  "next_action": "proceed" | "retry" | "block" | "complete",
  "error": string | null
}
```

### Field Definitions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `success` | boolean | Yes | `true` if operation completed successfully, `false` otherwise |
| `result` | object \| null | Yes | Operation-specific result data; `null` on failure |
| `next_action` | string | Yes | Recommended next step for the orchestrator |
| `error` | string \| null | Yes | Human-readable error message; `null` on success |

### next_action Values

| Value | Meaning | When to Use |
|-------|---------|-------------|
| `proceed` | Continue to next step | Operation succeeded, workflow should continue |
| `retry` | Retry this operation | Transient failure (network timeout, rate limit) |
| `block` | Stop workflow for this ticket | Permanent failure requiring human intervention |
| `complete` | Workflow finished | All work for current context is done |

### Example Responses

**Success:**
```json
{
  "success": true,
  "result": {"ticket_count": 5, "tickets": ["UIT-100", "UIT-101", "UIT-102", "UIT-103", "UIT-104"]},
  "next_action": "proceed",
  "error": null
}
```

**Transient Failure (retry):**
```json
{
  "success": false,
  "result": null,
  "next_action": "retry",
  "error": "JIRA API rate limit exceeded, retry after 60 seconds"
}
```

**Permanent Failure (block):**
```json
{
  "success": false,
  "result": null,
  "next_action": "block",
  "error": "Ticket UIT-100 has unresolved dependencies that cannot be automatically resolved"
}
```

---

## Module: State Manager (ASDW-2)

Manages workflow state persistence and checkpoint/recovery functionality.

### Required Functions

#### `save_state(state_json)`

Persists the current workflow state to the state file.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `state_json` | string | Yes | JSON string containing complete workflow state |

**Returns:** JSON response contract

**State JSON Schema:**
```json
{
  "run_id": "string",
  "status": "running" | "paused" | "completed" | "failed",
  "input_type": "jql" | "epic" | "team" | "tickets",
  "input_value": "string",
  "tickets": [
    {
      "key": "string",
      "status": "pending" | "in_progress" | "completed" | "blocked",
      "current_stage": "string",
      "started_at": "ISO8601 timestamp | null",
      "completed_at": "ISO8601 timestamp | null",
      "error": "string | null"
    }
  ],
  "created_at": "ISO8601 timestamp",
  "updated_at": "ISO8601 timestamp"
}
```

**Example:**
```bash
state_json='{"run_id":"20251212-143052-a1b2c3d4","status":"running","tickets":[]}'
result=$(save_state "$state_json")
if is_success "$result"; then
    log_info "State saved successfully"
fi
```

**Exit Codes:**
- 0: Success
- 6: State write failed (permission, disk full)

---

#### `load_state(run_id)`

Loads workflow state from a previous run.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `run_id` | string | Yes | Unique run identifier to load |

**Returns:** JSON response contract with `result` containing the state object

**Example:**
```bash
result=$(load_state "20251212-143052-a1b2c3d4")
if is_success "$result"; then
    state=$(extract_field "$result" "result")
    status=$(extract_field "$state" "status")
    log_info "Loaded state with status: $status"
fi
```

**Exit Codes:**
- 0: Success
- 6: State file not found or corrupted

---

#### `save_checkpoint(checkpoint_json)`

Creates a recovery checkpoint at the current workflow position.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `checkpoint_json` | string | Yes | JSON containing checkpoint data |

**Checkpoint JSON Schema:**
```json
{
  "checkpoint_id": "string (auto-generated if empty)",
  "run_id": "string",
  "ticket_key": "string",
  "stage": "string",
  "stage_data": "object (stage-specific data)",
  "created_at": "ISO8601 timestamp"
}
```

**Returns:** JSON response contract with `result.checkpoint_id`

**Example:**
```bash
checkpoint='{"run_id":"20251212-143052-a1b2c3d4","ticket_key":"UIT-100","stage":"planning"}'
result=$(save_checkpoint "$checkpoint")
if is_success "$result"; then
    checkpoint_id=$(extract_field "$result" "result.checkpoint_id")
    log_info "Checkpoint created: $checkpoint_id"
fi
```

**Exit Codes:**
- 0: Success
- 6: Checkpoint write failed

---

#### `restore_checkpoint(checkpoint_id)`

Restores workflow to a previous checkpoint state.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `checkpoint_id` | string | Yes | Checkpoint identifier to restore |

**Returns:** JSON response contract with `result` containing checkpoint data

**Example:**
```bash
result=$(restore_checkpoint "chk-20251212-143052-001")
if is_success "$result"; then
    stage=$(extract_field "$result" "result.stage")
    log_info "Restored to stage: $stage"
fi
```

**Exit Codes:**
- 0: Success
- 6: Checkpoint not found or corrupted

---

## Module: Recovery Handler (ASDW-3)

Handles error recovery, retry logic, and failure escalation.

### Required Functions

#### `retry_with_backoff(command, max_attempts)`

Executes a command with exponential backoff retry logic.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `command` | string | Yes | Command/function to execute |
| `max_attempts` | integer | No | Maximum retry attempts (default: from config) |

**Returns:** JSON response contract with the successful command's result, or failure after exhausting retries

**Backoff Algorithm:**
```
delay = initial_delay * (backoff_multiplier ^ attempt_number)
```

Where:
- `initial_delay` = `CONFIG_RETRY_INITIAL_DELAY` (default: 5 seconds)
- `backoff_multiplier` = `CONFIG_RETRY_BACKOFF_MULTIPLIER` (default: 2)

**Example:**
```bash
# Retry JIRA fetch up to 3 times with backoff
result=$(retry_with_backoff "fetch_tickets jql 'project=UIT'" 3)
if is_success "$result"; then
    tickets=$(extract_field "$result" "result.tickets")
fi
```

**Exit Codes:**
- 0: Command succeeded (possibly after retries)
- 5: All retry attempts exhausted

---

#### `handle_error(error_code, context_json)`

Processes errors and determines appropriate recovery action.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `error_code` | integer | Yes | Exit code from failed operation |
| `context_json` | string | Yes | JSON context about the failure |

**Context JSON Schema:**
```json
{
  "operation": "string (function name)",
  "ticket_key": "string | null",
  "stage": "string | null",
  "attempt": "integer",
  "error_message": "string"
}
```

**Returns:** JSON response contract with `result.action` being one of:
- `retry`: Retry the operation
- `skip`: Skip this ticket, continue with others
- `abort`: Abort the entire workflow
- `checkpoint`: Save checkpoint and pause

**Example:**
```bash
context='{"operation":"execute_stage","ticket_key":"UIT-100","stage":"review","attempt":1,"error_message":"Claude timeout"}'
result=$(handle_error 7 "$context")
action=$(extract_field "$result" "result.action")
case "$action" in
    retry) # retry the operation ;;
    skip)  # mark ticket as blocked, continue ;;
    abort) # exit workflow ;;
esac
```

**Exit Codes:**
- 0: Recovery action determined
- 10: Unable to determine recovery action

---

## Module: JIRA Adapter (ASDW-4)

Interfaces with JIRA to fetch ticket information.

### Required Functions

#### `fetch_tickets(input_type, input_value)`

Retrieves tickets based on input criteria.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `input_type` | string | Yes | One of: `jql`, `epic`, `team`, `tickets` |
| `input_value` | string | Yes | Query/key/list based on input_type |

**Input Type Behaviors:**
| Type | Input Value | Behavior |
|------|-------------|----------|
| `jql` | JQL query string | Execute JQL, return matching tickets |
| `epic` | Epic key (e.g., UIT-100) | Return all tickets linked to epic |
| `team` | Team name | Return tickets assigned to team |
| `tickets` | Comma-separated keys | Return specified tickets |

**Returns:** JSON response contract with `result` containing:
```json
{
  "ticket_count": "integer",
  "tickets": ["array of ticket keys"]
}
```

**Example:**
```bash
# Fetch by JQL
result=$(fetch_tickets "jql" "project = UIT AND status = 'To Do'")

# Fetch by epic
result=$(fetch_tickets "epic" "UIT-100")

# Fetch specific tickets
result=$(fetch_tickets "tickets" "UIT-3607,UIT-3608,UIT-3609")

if is_success "$result"; then
    count=$(extract_field "$result" "result.ticket_count")
    log_info "Found $count tickets"
fi
```

**Exit Codes:**
- 0: Success
- 5: JIRA query failed
- 7: JIRA CLI not available

---

#### `get_ticket_details(ticket_key)`

Retrieves detailed information about a single ticket.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `ticket_key` | string | Yes | JIRA ticket key (e.g., UIT-3607) |

**Returns:** JSON response contract with `result` containing:
```json
{
  "key": "string",
  "summary": "string",
  "description": "string",
  "status": "string",
  "priority": "string",
  "assignee": "string | null",
  "epic_link": "string | null",
  "story_points": "number | null",
  "labels": ["array of strings"],
  "dependencies": ["array of ticket keys"],
  "subtasks": ["array of ticket keys"]
}
```

**Example:**
```bash
result=$(get_ticket_details "UIT-3607")
if is_success "$result"; then
    summary=$(extract_field "$result" "result.summary")
    status=$(extract_field "$result" "result.status")
    log_info "Ticket: $summary (Status: $status)"
fi
```

**Exit Codes:**
- 0: Success
- 5: Ticket not found or fetch failed
- 7: JIRA CLI not available

---

## Module: Decision Engine (ASDW-5)

Uses Claude CLI for AI-driven decision making.

### Required Functions

#### `make_decision(context_json, options_json)`

Invokes Claude to make a decision based on context.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `context_json` | string | Yes | JSON context for the decision |
| `options_json` | string | No | JSON array of available options |

**Context JSON Schema:**
```json
{
  "decision_type": "string",
  "ticket_key": "string | null",
  "current_stage": "string | null",
  "history": ["array of previous decisions"],
  "constraints": ["array of constraint strings"],
  "data": "object (decision-specific data)"
}
```

**Decision Types:**
| Type | Purpose | Expected Output |
|------|---------|-----------------|
| `prioritize` | Order tickets by importance | Ordered list of ticket keys |
| `proceed_or_block` | Determine if ticket can proceed | `proceed` or `block` with reason |
| `select_approach` | Choose implementation approach | Selected option with rationale |
| `resolve_conflict` | Handle conflicting requirements | Resolution strategy |

**Returns:** JSON response contract with `result` containing:
```json
{
  "decision": "string (the decision made)",
  "confidence": "number (0.0-1.0)",
  "rationale": "string (explanation)",
  "alternatives_considered": ["array of rejected options with reasons"]
}
```

**Example:**
```bash
context='{
  "decision_type": "proceed_or_block",
  "ticket_key": "UIT-3607",
  "data": {
    "dependencies": ["UIT-3600", "UIT-3601"],
    "dependency_statuses": {"UIT-3600": "completed", "UIT-3601": "in_progress"}
  }
}'
result=$(make_decision "$context")
if is_success "$result"; then
    decision=$(extract_field "$result" "result.decision")
    if [ "$decision" = "proceed" ]; then
        log_info "Decision: proceed with ticket"
    else
        reason=$(extract_field "$result" "result.rationale")
        log_warn "Decision: blocked - $reason"
    fi
fi
```

**Exit Codes:**
- 0: Decision made successfully
- 5: Decision making failed
- 7: Claude CLI not available or timeout

**Timeout:** Uses `CONFIG_DECISION_TIMEOUT` (default: 120 seconds)

---

## Module: SDD Executor (ASDW-6)

Executes SDD workflow stages for tickets.

### Required Functions

#### `execute_stage(stage_name, ticket_key, context_json)`

Executes a specific SDD workflow stage for a ticket.

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `stage_name` | string | Yes | Stage to execute |
| `ticket_key` | string | Yes | JIRA ticket key |
| `context_json` | string | No | Additional context for execution |

**Stage Names:**
| Stage | SDD Command | Description |
|-------|-------------|-------------|
| `import` | `/sdd:import-jira-ticket` | Import JIRA ticket to SDD |
| `plan` | `/sdd:plan-ticket` | Create planning documents |
| `review_plan` | `/sdd:review` | Review ticket plan |
| `update` | `/sdd:update` | Update based on review findings |
| `create_tasks` | `/sdd:create-tasks` | Create tasks from plan |
| `execute_tasks` | `/sdd:do-all-tasks` | Execute all tasks |
| `verify` | (verify-task agent) | Verify task completion |
| `commit` | (commit-task agent) | Commit verified changes |
| `pr` | `/sdd:pr` | Create pull request |

**Returns:** JSON response contract with `result` containing:
```json
{
  "stage": "string",
  "ticket_key": "string",
  "status": "completed" | "failed" | "blocked",
  "artifacts": ["array of created file paths"],
  "output": "string (stage output summary)",
  "duration_seconds": "number"
}
```

**Example:**
```bash
result=$(execute_stage "plan" "UIT-3607" '{"epic": "UIT-100"}')
if is_success "$result"; then
    status=$(extract_field "$result" "result.status")
    if [ "$status" = "completed" ]; then
        artifacts=$(extract_field "$result" "result.artifacts")
        log_info "Planning complete, artifacts: $artifacts"
    fi
fi
```

**Exit Codes:**
- 0: Stage completed successfully
- 5: Stage execution failed
- 7: Required tool (claude, gh) not available

---

## Function Implementation Requirements

### All Functions Must

1. **Accept string parameters** - All parameters are passed as strings
2. **Return valid JSON** - Output must be parseable by `jq`
3. **Use stdout for JSON output** - All structured output goes to stdout
4. **Use stderr for debug output** - Use logging functions, not raw echo
5. **Handle empty/null inputs** - Graceful handling, not crashes
6. **Be idempotent where possible** - Safe to retry

### Function Template

```bash
#!/usr/bin/env bash
# Module: module-name
# Function: function_name
# Description: Brief description of what the function does

function_name() {
    local param1="${1:-}"
    local param2="${2:-}"

    # Validate required parameters
    if [ -z "$param1" ]; then
        cat << EOF
{
  "success": false,
  "result": null,
  "next_action": "block",
  "error": "Missing required parameter: param1"
}
EOF
        return 1
    fi

    # Perform operation
    local operation_result
    if operation_result=$(do_something "$param1" "$param2" 2>/dev/null); then
        cat << EOF
{
  "success": true,
  "result": $(echo "$operation_result" | jq -c '.'),
  "next_action": "proceed",
  "error": null
}
EOF
        return 0
    else
        cat << EOF
{
  "success": false,
  "result": null,
  "next_action": "retry",
  "error": "Operation failed: $(sanitize_log_message "$operation_result")"
}
EOF
        return 1
    fi
}
```

---

## Cross-References

- **Architecture Document:** See `architecture.md` for component design details
- **Exit Codes:** See `exit-codes.md` for comprehensive exit code reference
- **Configuration:** See `config/default.json` for configuration options
- **Test Harness:** See `tests/test-harness.sh` for testing utilities
