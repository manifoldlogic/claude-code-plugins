---
description: Check task status for tickets with parallel execution support
argument-hint: [TICKET_ID or empty for all]
---

# Status Check

## Context

Ticket: $ARGUMENTS (optional - if empty, shows all tasks)

## Workflow

**IMPORTANT: Use scripts for data gathering, optionally Haiku for formatting. Check Tasks API for real-time parallel execution status.**

### Step 1: Check Tasks API Availability

```bash
# Check if Tasks API is enabled for real-time status
TASKS_API_ENABLED="${SDD_TASKS_API_ENABLED:-true}"
CLAUDE_TASK_LIST_ID="${CLAUDE_TASK_LIST_ID:-}"

if [ "$TASKS_API_ENABLED" != "false" ] && [ -n "$CLAUDE_TASK_LIST_ID" ]; then
  echo "Tasks API: ENABLED (Task List ID: $CLAUDE_TASK_LIST_ID)"
  USE_TASKS_API=true
else
  echo "Tasks API: DISABLED (using file inspection)"
  USE_TASKS_API=false
fi
```

### Step 2: Gather Status Data

**Run status script for file-based data:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/scripts/task-status.sh ${ARGUMENTS}
```

This returns JSON with:
- Tickets
- Tasks per ticket
- Checkbox states (completed, tested, verified)

**If Tasks API is enabled, also query TaskList tool for real-time status:**

When `USE_TASKS_API=true`, use the TaskList tool to get:
- Tasks currently `in_progress` (running concurrently)
- Tasks `pending` with no `blockedBy` dependencies (available for launch)
- Tasks `pending` with `blockedBy` dependencies (blocked)
- Tasks `completed`

### Step 3: Format Report

For simple output, parse JSON directly and format.

For rich formatting, optionally **delegate to status-reporter agent (Haiku):**

```
Assignment: Format ticket status report

Input: {JSON from script}

Instructions:
1. Create summary table
2. Calculate progress percentages
3. Highlight items needing attention
4. Group by phase
5. Show parallel execution status if Tasks API is enabled

Return: Formatted markdown report
```

### Step 4: Report (Sequential Mode)

**When Tasks API is disabled or not available, use traditional output:**

**For single ticket:**

```
TICKET STATUS: {TICKET_ID}_{name}

Progress: [======....] 60% (6/10 verified)

By Phase:
| Phase | Total | Verified | Remaining |
|-------|-------|----------|-----------|
| 1     | 5     | 5        | 0         |
| 2     | 5     | 1        | 4         |

Tasks Needing Attention:
- {TICKET_ID}.2002: Completed but not tested
- {TICKET_ID}.2003: Pending

Next Actions:
1. Run tests for {TICKET_ID}.2002
2. Continue work on {TICKET_ID}.2003
```

**For all tickets:**

```
ALL TICKETS STATUS

| Ticket | Progress | Verified | Total |
|---------|----------|----------|-------|
| APIV2   | 60%      | 6        | 10    |
| CACHE   | 100%     | 4        | 4     |
| AUTH    | 25%      | 1        | 4     |

Ready to Archive: CACHE (all verified)

Most Active: APIV2 (Phase 2 in progress)

Recommended Next:
- /sdd:do-all-tasks APIV2 - Continue execution
- /sdd:archive - Archive CACHE
```

### Step 5: Report (Parallel Mode with Tasks API)

**When Tasks API is enabled and active, show enhanced parallel execution status:**

**For single ticket with parallel execution:**

```
TICKET STATUS: {TICKET_ID}_{name}
Mode: Parallel Execution

Progress: [======....] 60% (6/10 verified)

Phase 0: [Complete] (2/2 tasks)
Phase 1: [Complete] (3/3 tasks)
Phase 2: [In Progress] (1/3 tasks)
  > {TICKET_ID}.2001 - task summary (IN PROGRESS)
  * {TICKET_ID}.2002 - task summary (BLOCKED by 2001)
  - {TICKET_ID}.2003 - task summary (PENDING)
Phase 3: [Blocked] (0/2 tasks started)

Parallel Execution Summary:
  Currently running: 1 task
  Available to launch: 1 task
  Blocked by dependencies: 1 task

Next Actions:
1. /sdd:do-task {TICKET_ID}.2003 - Launch available task
2. Monitor {TICKET_ID}.2001 - Currently in progress
```

**For all tickets with parallel execution:**

```
ALL TICKETS STATUS (Parallel Mode)

| Ticket | Progress | Running | Available | Blocked |
|---------|----------|---------|-----------|---------|
| APIV2   | 60%      | 2       | 1         | 2       |
| CACHE   | 100%     | 0       | 0         | 0       |
| AUTH    | 25%      | 1       | 0         | 3       |

Parallel Execution Summary:
  Total running: 3 tasks across 2 tickets
  Total available: 1 task

Ready to Archive: CACHE (all verified)

Most Active: APIV2 (2 tasks running concurrently)

Recommended Next:
- /sdd:do-task APIV2.2004 - Launch available task
- /sdd:do-all-tasks AUTH --parallel - Enable parallel execution
- /sdd:archive CACHE - Archive completed ticket
```

**Task Status Indicators:**
- `>` IN PROGRESS: Task currently executing
- `*` BLOCKED: Task waiting for dependencies (show blockedBy task IDs)
- `-` PENDING: Task ready but not started (available for launch)
- `+` COMPLETED: Task finished and verified

**Phase Status Indicators:**
- `[Complete]` All tasks in phase are verified
- `[In Progress]` Some tasks running or completed, not all verified
- `[Blocked]` All tasks blocked by previous phase dependencies
- `[Pending]` All tasks pending, no blockers (ready to start)

### Step 6: Parallel Execution Details (Optional)

If user requests detailed parallel execution info:

```bash
# Query TaskList for detailed dependency information
# Parse blockedBy relationships to show dependency graph
```

**Detailed Output:**
```
PARALLEL EXECUTION DETAILS: {TICKET_ID}

Dependency Graph:
  {TICKET_ID}.2001 (IN PROGRESS)
    blocks: 2003, 2004
  {TICKET_ID}.2002 (IN PROGRESS)
    blocks: 2003
  {TICKET_ID}.2003 (BLOCKED)
    blockedBy: 2001, 2002
  {TICKET_ID}.2004 (BLOCKED)
    blockedBy: 2001

Independent Tasks (can run in parallel):
  - {TICKET_ID}.2001, {TICKET_ID}.2002 (both currently running)

Next Wave (unblocked when current completes):
  - When 2001 completes: 2004 becomes available
  - When 2001 AND 2002 complete: 2003 becomes available
```

## Optional: Detailed Summary

If user asks for more detail:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/scripts/ticket-summary.sh ${TICKET_ID}
```

This generates full markdown summary.

## Key Constraints

- Use task-status.sh for data (don't scan files manually)
- Check Tasks API availability before querying TaskList
- Keep reports concise
- Highlight actionable items
- Calculate percentages correctly
- Show parallel execution info only when Tasks API is enabled
- Clearly indicate execution mode (Sequential vs Parallel)
- Fall back gracefully to file inspection when Tasks API unavailable

## Feature Flag Behavior

| SDD_TASKS_API_ENABLED | CLAUDE_TASK_LIST_ID | Behavior |
|----------------------|---------------------|----------|
| true (default)       | Set                 | Full parallel execution display |
| true                 | Not set             | File inspection fallback |
| false                | Any                 | File inspection only |

When in fallback mode:
- Do not show parallel execution information
- Use traditional status output
- No real-time task state updates
