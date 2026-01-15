# Autogate Schema Documentation

This document defines the schema for `.autogate.json` files used to control ticket readiness and agent execution approval in the SDD workflow.

## Overview

The `.autogate.json` file is placed in a ticket directory to indicate readiness states and execution parameters. It serves as the coordination mechanism between human approval workflows and autonomous agent execution.

**Location:** `{SDD_ROOT}/tickets/{TICKET_ID}/.autogate.json`

## Schema Definition

```json
{
  "ready": boolean,
  "agent_ready": boolean,
  "priority": integer | null,
  "stop_at_phase": integer | null,
  "marked_at": string | null
}
```

## Field Definitions

### ready

| Property | Value |
|----------|-------|
| **Type** | `boolean` |
| **Required** | No |
| **Default** | `false` |
| **Valid Values** | `true`, `false` |

**Description:**
Human approval signal indicating the ticket is ready for work. This field is typically set during the `/sdd:plan-ticket` flow when a ticket has been sufficiently planned and reviewed.

**Behavior:**
- When `true`: Ticket appears in the master status board
- When `false`: Ticket is hidden from status displays
- Must be `true` (along with `agent_ready`) for autonomous execution

---

### agent_ready

| Property | Value |
|----------|-------|
| **Type** | `boolean` |
| **Required** | No |
| **Default** | `false` |
| **Valid Values** | `true`, `false` |

**Description:**
Agent execution approval signal. This field explicitly authorizes autonomous agents to execute tasks for this ticket. It provides a second-level approval gate beyond the basic `ready` flag.

**Behavior:**
- When `true`: Agents are authorized to work on this ticket autonomously
- When `false`: Agents will not process this ticket without human intervention
- Both `ready` and `agent_ready` must be `true` for autonomous execution
- Set via `/sdd:mark-ready` command
- Cleared via `/sdd:unmark-ready` command

---

### priority

| Property | Value |
|----------|-------|
| **Type** | `integer` or `null` |
| **Required** | No |
| **Default** | `null` |
| **Valid Values** | Non-negative integers (0, 1, 2, ...) or `null` |

**Description:**
Optional prioritization for execution ordering. Lower numbers indicate higher priority.

**Behavior:**
- `1` = Highest priority
- `null` = Lowest priority (processed last)
- `0` is a valid priority value (higher than `1`)
- Negative values are rejected with an error
- No upper bound on priority values
- Set via `/sdd:mark-ready --priority N`
- Cleared to `null` by `/sdd:unmark-ready`

**Sorting Rules:**
1. Tickets with numeric priorities are sorted ascending (1 before 2 before 3)
2. Tickets with `null` priority come after all numeric priorities
3. Ties (same priority or both `null`) are sorted alphabetically by `ticket_id`

---

### stop_at_phase

| Property | Value |
|----------|-------|
| **Type** | `integer` or `null` |
| **Required** | No |
| **Default** | `null` |
| **Valid Values** | Positive integers or `null` |

**Description:**
Optional phase limiter that stops autonomous execution at a specific phase number. Useful for controlling how far an agent progresses through the workflow.

**Behavior:**
- When set: Agent stops after completing the specified phase
- When `null`: No phase limit; execute all phases
- Phases are numbered starting from 1

---

### marked_at

| Property | Value |
|----------|-------|
| **Type** | `string` (ISO 8601 timestamp) or `null` |
| **Required** | No |
| **Default** | `null` |
| **Valid Values** | ISO 8601 formatted timestamp string or `null` |

**Description:**
Audit trail timestamp recording when the `.autogate.json` was last modified by a mark/unmark command.

**Behavior:**
- Set automatically by `/sdd:mark-ready` and `/sdd:unmark-ready` commands
- Format: ISO 8601 (e.g., `"2025-01-15T14:30:00Z"`)
- Used for audit and debugging purposes
- Not used in sorting or execution logic

---

## Examples

### Example 1: Minimal Configuration (Human Ready Only)

A ticket that is ready for human review but not yet approved for agent execution:

```json
{
  "ready": true
}
```

**Effect:** Ticket appears in status board but agents will not execute tasks autonomously.

---

### Example 2: Agent-Ready with Priority

A ticket fully approved for autonomous execution with high priority:

```json
{
  "ready": true,
  "agent_ready": true,
  "priority": 1,
  "marked_at": "2025-01-15T10:30:00Z"
}
```

**Effect:** Ticket is first in the agent execution queue, processed before all other tickets.

---

### Example 3: All Fields Populated

A ticket with all fields explicitly set, including a phase limiter:

```json
{
  "ready": true,
  "agent_ready": true,
  "priority": 5,
  "stop_at_phase": 2,
  "marked_at": "2025-01-15T14:45:30Z"
}
```

**Effect:** Ticket is queued for agent execution at priority 5, but will stop after completing phase 2.

---

### Example 4: Low Priority (Null Priority)

A ticket approved for agent execution but with no specific priority:

```json
{
  "ready": true,
  "agent_ready": true,
  "priority": null,
  "marked_at": "2025-01-15T09:00:00Z"
}
```

**Effect:** Ticket is processed after all tickets with numeric priorities.

---

## Backward Compatibility

All fields are **optional** with safe defaults. This ensures backward compatibility with existing `.autogate.json` files that may not include newer fields.

### Safe Defaults for Missing Fields

| Field | Default When Missing |
|-------|---------------------|
| `ready` | `false` |
| `agent_ready` | `false` |
| `priority` | `null` |
| `stop_at_phase` | `null` |
| `marked_at` | `null` |

### Migration Notes

- **Files without `agent_ready`:** Treated as `agent_ready: false`. These tickets will not be processed by autonomous agents until explicitly marked ready.
- **Files without `priority`:** Treated as `priority: null`. These tickets sort to the end of the queue.
- **Files without `marked_at`:** No timestamp audit trail until next modification.

### Empty or Missing File

If `.autogate.json` is missing or empty:
- Ticket is treated as not ready (`ready: false`)
- Ticket will not appear in status board
- Agents will not process the ticket

---

## Error Message Format Standard

Commands that manipulate `.autogate.json` follow a consistent error message format:

```
Error: {specific error message}
Usage: {command signature}
```

### Error Message Examples

**Invalid Ticket ID Format:**
```
Error: Invalid ticket ID format: FAKE@123
Usage: /sdd:mark-ready TICKET_ID [--priority N]
```

**Ticket Not Found:**
```
Error: Ticket not found: NOEXIST-999
Usage: /sdd:mark-ready TICKET_ID [--priority N]
```

**Invalid Priority Value:**
```
Error: Priority must be a non-negative integer: -5
Usage: /sdd:mark-ready TICKET_ID [--priority N]
```

**Ticket Not Ready:**
```
Error: Ticket PROJ-42 is not marked ready. Set ready: true first.
Usage: /sdd:mark-ready TICKET_ID [--priority N]
```

### Error Categories

| Category | Message Pattern |
|----------|-----------------|
| Validation | `Error: Invalid {field}: {value}` |
| Not Found | `Error: {resource} not found: {identifier}` |
| State | `Error: {resource} is not {required state}` |
| Permission | `Error: Cannot {action}: {reason}` |

---

## Related Commands

| Command | Purpose | Modifies |
|---------|---------|----------|
| `/sdd:plan-ticket` | Creates ticket, sets `ready: true` | `ready` |
| `/sdd:mark-ready` | Enables agent execution | `agent_ready`, `priority`, `marked_at` |
| `/sdd:unmark-ready` | Disables agent execution | `agent_ready`, `priority`, `marked_at` |
| `/sdd:status` | Displays tickets based on autogate state | (read-only) |

---

## Validation Rules Summary

1. **ready**: Must be boolean if present
2. **agent_ready**: Must be boolean if present
3. **priority**: Must be `null` or non-negative integer (>= 0)
4. **stop_at_phase**: Must be `null` or positive integer (>= 1)
5. **marked_at**: Must be `null` or valid ISO 8601 timestamp string
6. **Unknown fields**: Ignored (forward compatibility)
