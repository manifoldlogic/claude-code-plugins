---
description: Execute all tasks for a ticket systematically (supports --parallel for concurrent execution)
argument-hint: [TICKET_ID] [--parallel]
---

# Work on Ticket

## Context

Ticket: $ARGUMENTS
Task folder: `${SDD_ROOT_DIR}/tickets/$ARGUMENTS_*/`
Tasks: `${SDD_ROOT_DIR}/tickets/$ARGUMENTS_*/tasks/`

## Argument Parsing

Parse arguments to detect mode:
- Default: Sequential execution (existing behavior)
- `--parallel`: Enable parallel execution mode (experimental)

```bash
# Parse arguments
TICKET_ID="${ARGUMENTS%% *}"  # First argument is ticket ID (strip --parallel if present)
TICKET_ID="${TICKET_ID%%--*}"  # Remove any flags from ticket ID
TICKET_ID="${TICKET_ID%% }"   # Trim trailing space

if echo "$ARGUMENTS" | grep -q "\-\-parallel"; then
  PARALLEL_MODE=true
  echo "=== PARALLEL MODE ENABLED ==="
else
  PARALLEL_MODE=false
  echo "=== SEQUENTIAL MODE (default) ==="
fi
```

## Pre-Execution Checklist (BLOCKING)

**CRITICAL: All validation checks MUST pass before execution begins. If any check fails, execute CANNOT proceed.**

### Locate Ticket

```bash
TICKET_PATH=$(ls -d ${SDD_ROOT_DIR:-/app/.sdd}/tickets/${ARGUMENTS}_* 2>/dev/null | head -1)
```

If ticket doesn't exist, report error and exit.

### Validation Checks

Run the following validation checks:

```bash
# Define ticket path
TICKET_PATH=$(ls -d ${SDD_ROOT_DIR:-/app/.sdd}/tickets/${ARGUMENTS}_* 2>/dev/null | head -1)
VALIDATION_FAILED=false
CHECKLIST=""

echo "=== PRE-EXECUTION CHECKLIST ==="

# Check 1: Review document exists
if [ -f "$TICKET_PATH/planning/ticket-review.md" ]; then
  CHECKLIST="${CHECKLIST}\n✓ Review document exists"
else
  CHECKLIST="${CHECKLIST}\n✗ Review document missing (ticket-review.md)"
  VALIDATION_FAILED=true
fi

# Check 2: Review has PASS or Ready status (flexible check)
if [ -f "$TICKET_PATH/planning/ticket-review.md" ]; then
  if grep -qiE "(Ready|PASS|Proceed)" "$TICKET_PATH/planning/ticket-review.md"; then
    CHECKLIST="${CHECKLIST}\n✓ Review status: Approved"
  else
    CHECKLIST="${CHECKLIST}\n✗ Review status: Not approved (need Ready/PASS status)"
    VALIDATION_FAILED=true
  fi
fi

# Check 3: Tasks directory exists and has task files
TASK_COUNT=$(ls "$TICKET_PATH/tasks/"*.md 2>/dev/null | grep -v "_INDEX" | wc -l)
if [ "$TASK_COUNT" -gt 0 ]; then
  CHECKLIST="${CHECKLIST}\n✓ Tasks found: $TASK_COUNT task(s)"
else
  CHECKLIST="${CHECKLIST}\n✗ No tasks found in tasks/ directory"
  VALIDATION_FAILED=true
fi

# Check 4: Task naming convention (warn only)
NAMING_ISSUES=0
for task_file in "$TICKET_PATH/tasks/"*.md; do
  BASENAME=$(basename "$task_file")
  if [[ "$BASENAME" == *"_INDEX"* ]]; then
    continue  # Skip index files
  fi
  if [[ ! "$BASENAME" =~ ^[A-Z0-9-]+\.[0-9]+_.+\.md$ ]]; then
    NAMING_ISSUES=$((NAMING_ISSUES + 1))
  fi
done

if [ "$NAMING_ISSUES" -eq 0 ]; then
  CHECKLIST="${CHECKLIST}\n✓ Task naming: All files follow convention"
else
  CHECKLIST="${CHECKLIST}\n⚠️  Task naming: $NAMING_ISSUES file(s) don't follow convention (warning only)"
fi

# Report checklist results
echo -e "$CHECKLIST"
echo ""

# Report validation result
if [ "$VALIDATION_FAILED" = true ]; then
  echo "❌ VALIDATION FAILED: Cannot execute ticket"
  echo ""
  echo "Action Required:"
  echo "1. Complete ticket review with /sdd:review {TICKET_ID}"
  echo "2. Create tasks with /sdd:create-tasks {TICKET_ID}"
  echo "3. Re-run /sdd:do-all-tasks after prerequisites met"
  # EXIT - Do not proceed
fi
```

### Validation Requirements

| Check | Required | Behavior |
|-------|----------|----------|
| Review document exists | YES | BLOCKS if missing |
| Review has PASS/Ready status | YES | BLOCKS if not approved |
| Tasks exist in tasks/ | YES | BLOCKS if no tasks |
| Task naming convention | Recommended | Warns only |

### Execution Summary

**If validation passes, display execution summary:**

```
=== EXECUTION SUMMARY ===

Ticket: {TICKET_ID}_{name}
Tasks to execute: {total_count}
Already verified: {verified_count}
Remaining: {remaining_count}

Execution Order:
1. {TICKET_ID.1001}: {title}
2. {TICKET_ID.1002}: {title}
...

Estimated time: {count * 2-8 hours per task}

Proceeding with execution...
```

**DO NOT PROCEED if validation fails. Address all requirements before executing.**

---

## Step 1.5: Tasks API Hydration (Optional)

**This step enables real-time progress tracking via Claude Code's Tasks API (Ctrl+T view).**

### Feature Flag Check

If `SDD_TASKS_API_ENABLED` is explicitly set to `'false'`, skip all Tasks API operations and proceed directly to the workflow.

```bash
# Check feature flag
# Default is ENABLED (feature flag only disables when explicitly set to 'false')
TASKS_API_ENABLED=true
if [ "$SDD_TASKS_API_ENABLED" = "false" ]; then
  echo "Tasks API disabled via SDD_TASKS_API_ENABLED=false"
  TASKS_API_ENABLED=false
fi
```

### Bulk Hydration Process

If Tasks API is enabled, hydrate all task files to the Tasks API before execution begins:

```bash
# Only run hydration if Tasks API is enabled
if [ "$TASKS_API_ENABLED" = "true" ]; then
  echo "=== TASKS API HYDRATION ==="

  # Set CLAUDE_TASK_LIST_ID to ticket ID for scoping
  export CLAUDE_TASK_LIST_ID="${ARGUMENTS}"
  echo "Set CLAUDE_TASK_LIST_ID=${ARGUMENTS}"

  # Call hydration module
  HYDRATION_OUTPUT=$(python ${CLAUDE_PLUGIN_ROOT}/hooks/hydrate-tasks.py "$TICKET_PATH" "${ARGUMENTS}" 2>&1)
  HYDRATION_STATUS=$?

  if [ $HYDRATION_STATUS -eq 0 ]; then
    # Extract task count from hydration output
    HYDRATED_COUNT=$(echo "$HYDRATION_OUTPUT" | grep -oE 'Hydrated [0-9]+ tasks' | grep -oE '[0-9]+' || echo "0")
    echo "Hydrated $HYDRATED_COUNT tasks to Tasks API"
    echo ""
  else
    echo "Warning: Tasks API hydration failed, continuing in file-only mode"
    echo "Hydration output: $HYDRATION_OUTPUT"
    TASKS_API_ENABLED=false
    echo ""
  fi
fi
```

### Hydration Summary Output

```
=== TASKS API HYDRATION ===
Set CLAUDE_TASK_LIST_ID={TICKET_ID}
Hydrated {N} tasks to Tasks API

{If hydration failed:}
Warning: Tasks API hydration failed, continuing in file-only mode
```

### Graceful Degradation

| Error | Behavior |
|-------|----------|
| Hydration script fails | Log warning, continue with file-only mode |
| Tasks API unavailable | Skip API operations, proceed with existing workflow |
| Feature flag disabled | Skip hydration entirely, use file-only mode |

**Note:** The file remains authoritative. If Tasks API hydration fails, the file-based workflow continues to function normally. The Tasks API integration is a visibility enhancement, not a blocking requirement.

---

## Step 1.6: Parallel Mode Setup (Optional)

**This step only runs when --parallel flag is provided.**

### Calculate Dependency Graph

If parallel mode enabled:

```bash
if [ "$PARALLEL_MODE" = "true" ]; then
  echo "=== PARALLEL MODE SETUP ==="

  # Verify Tasks API is enabled (required for parallel mode)
  if [ "$TASKS_API_ENABLED" != "true" ]; then
    echo "Warning: Tasks API not enabled, falling back to sequential mode"
    echo "Parallel mode requires Tasks API for task state coordination"
    PARALLEL_MODE=false
  fi
fi

if [ "$PARALLEL_MODE" = "true" ]; then
  # Calculate dependency graph
  DEP_GRAPH=$(python ${CLAUDE_PLUGIN_ROOT}/scripts/calculate-dependency-graph.py "$TICKET_PATH" 2>&1)
  DEP_STATUS=$?

  if [ $DEP_STATUS -ne 0 ]; then
    echo "Warning: Dependency graph calculation failed, falling back to sequential mode"
    echo "Error: $DEP_GRAPH"
    PARALLEL_MODE=false
  else
    echo "Dependency graph calculated successfully"
    # Parse graph output for phase and dependency information
    echo "$DEP_GRAPH" | head -20
    echo ""
  fi
fi
```

### Parallel Execution Prerequisites

| Prerequisite | Required | Fallback |
|--------------|----------|----------|
| Tasks API enabled | YES | Falls back to sequential |
| Dependency graph calculates | YES | Falls back to sequential |
| Tasks hydrated with blockedBy | YES | Falls back to sequential |

**Note:** If any prerequisite fails, execution continues in sequential mode with a warning. This ensures robustness - parallel mode is an optimization, not a requirement.

---

## Workflow

**IMPORTANT: You are an orchestrator. You coordinate ticket execution by delegating to /sdd:do-task for each ticket.**

**Context Conservation:** As an orchestrator coordinating multiple tasks, preserve your context by delegating each task's implementation work. This keeps your context focused on coordination, progress tracking, and quality gates across all tasks. See [delegation-patterns.md](../skills/project-workflow/references/delegation-patterns.md) Pattern 6 for the context conservation principle.

### Step 1: Gather Ticket Inventory

**Use script to get status:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/scripts/task-status.sh ${ARGUMENTS}
```

This returns JSON with all tasks and their status.

### Step 2: Plan Execution Order

From the status JSON, determine:
1. Which tickets are not yet verified
2. Dependency order (Phase 1 before Phase 2, etc.)
3. Skip already-verified tickets

### Step 3: Execute Each Ticket

**For each unverified task, in order:**

Invoke `/sdd:do-task {TASK_ID}` which handles:
- Implementation
- Testing (including coverage verification)
- Verification
- Commit

Wait for each ticket to complete before starting the next.

**DO NOT manually implement tasks. The /sdd:do-task command handles the full workflow.**

### Step 4: Handle Failures

If a task fails verification:
1. Note the failure
2. **Do NOT use workarounds**
3. Create follow-up task if needed
4. Continue with other tasks
5. Report failures at the end

### Step 5: Track Progress

After each task:
- Update mental model of completed work
- Check if phase is complete
- Note any created follow-up tasks

### Step 6: Final Report

```
TICKET EXECUTION COMPLETE: {TICKET_NAME}

Summary:
- Total tasks: {total}
- Verified: {verified_count}
- Failed: {failed_count}
- Skipped: {skipped_count}

{If PARALLEL_MODE was true:}
Execution Mode: PARALLEL
- Max concurrent tasks: 3
- Phases executed: {phase_count}
- Total duration: {duration}

{If PARALLEL_MODE was false (default):}
Execution Mode: SEQUENTIAL
- Tasks executed in order
- Total duration: {duration}

{If Tasks API was enabled:}
Tasks API Status:
- Hydration: Successful ({hydrated_count} tasks)
- Tracking: Enabled via CLAUDE_TASK_LIST_ID={TICKET_ID}
- All task updates synced to Tasks API

{If Tasks API was disabled or failed:}
Tasks API Status:
- Mode: File-only (Tasks API not used)

Completed Tasks:
✓ {TICKET_ID.1001}: {title}
✓ {TICKET_ID.1002}: {title}
...

{If any failed:}
Failed Tasks:
✗ {TICKET_ID.XXXX}: {reason}

{If parallel mode fell back to sequential:}
Fallback Note:
- Parallel execution encountered issues
- Switched to sequential mode at task {TASK_ID}
- Remaining tasks completed sequentially

{If any follow-up:}
Follow-up Tasks Created:
• {TICKET_ID.XXXX}: {description}

Git Status:
{run git status to confirm no uncommitted changes}

---
RECOMMENDED NEXT STEP:
If all tasks verified:
  - Code review (recommended): /sdd:code-review {TICKET_ID}
  - Create PR directly: /sdd:pr {TICKET_ID}
If tasks have failures: /sdd:do-task {TICKET_ID}.{failed_task_id}
If review needed: /sdd:review {TICKET_ID}
```

### Step 7: Clear Session State on Completion

**When all tasks are verified and complete, clear the session state file:**

```bash
# Clear session state - ticket work is complete
SDD_ROOT="${SDD_ROOT_DIR:-/app/.sdd}"
SESSION_ID="${SDD_SESSION_ID:-${CLAUDE_SESSION_ID:-unknown}}"
STATE_FILE="$SDD_ROOT/.sdd-session-states/$SESSION_ID.json"

if [ -f "$STATE_FILE" ]; then
  rm -f "$STATE_FILE"
  echo "Session state cleared: $STATE_FILE"
fi
```

**Note:** This cleanup is also performed by the verify-task and commit-task agents for individual tasks, but this provides a final cleanup at ticket completion level.

---

## Key Constraints

- Use /sdd:do-task for each task (do NOT implement directly)
- Use task-status.sh for inventory
- Complete tasks in dependency order
- Do NOT skip verification steps
- Do NOT use workarounds for blocked tasks

---

## Parallel Workflow (--parallel flag)

**IMPORTANT: This is an experimental feature. Only use when tasks within a phase are truly independent.**

When `--parallel` flag is provided and all prerequisites pass (Tasks API enabled, dependency graph calculated), use this parallel workflow instead of the sequential workflow above.

### Parallel Execution Algorithm

1. Calculate dependency graph (done in Step 1.6)
2. Identify independent tasks within current phase (tasks with empty blockedBy)
3. Launch Task tool for each independent task simultaneously (up to MAX_CONCURRENT)
4. Poll TaskList for completions
5. When tasks complete, find newly unblocked tasks
6. Repeat until all tasks complete

### Concurrency Limits

- Maximum concurrent tasks: 3 (to avoid context limits)
- Phase boundaries enforced by blockedBy relationships
- Tasks in Phase N+1 cannot start until all Phase N tasks complete

### Step P1: Initialize Parallel State

```bash
# Initialize parallel execution state
PARALLEL_TASKS_RUNNING=0
MAX_CONCURRENT=3
COMPLETED_TASKS=""
FAILED_TASKS=""
PARALLEL_START_TIME=$(date +%s)
```

### Step P2: Parallel Execution Loop

**Main loop - repeat until all tasks complete:**

For each iteration:
1. Query TaskList to get current task states
2. Identify available tasks (status='pending', blockedBy is empty or all blockedBy tasks completed)
3. Launch up to MAX_CONCURRENT available tasks in parallel using Task tool
4. Poll TaskList periodically (every 30 seconds) for status changes
5. When tasks complete:
   - Update COMPLETED_TASKS or FAILED_TASKS list
   - Check for newly available tasks (blockedBy now resolved)
   - Launch newly available tasks (respecting MAX_CONCURRENT)
6. Continue until no tasks remain pending

```markdown
WHILE tasks remain pending:

  # Query current state
  Use TaskList to get all task statuses

  # Find available tasks
  AVAILABLE = tasks where:
    - status = 'pending'
    - blockedBy is empty OR all blockedBy tasks have status='completed'

  # Launch available tasks (up to limit)
  FOR each task in AVAILABLE (limit MAX_CONCURRENT - currently_running):
    Launch: Task(subagent_type="general-purpose", prompt="Execute /sdd:do-task {TASK_ID}")
    Update TaskUpdate(taskId={id}, status="in_progress")
    Increment PARALLEL_TASKS_RUNNING

  # Poll for completions
  WAIT 30 seconds
  Query TaskList for status changes

  # Process completions
  FOR each newly completed task:
    Decrement PARALLEL_TASKS_RUNNING
    IF task succeeded:
      Add to COMPLETED_TASKS
    ELSE:
      Add to FAILED_TASKS
      Log: "Task {TASK_ID} failed, continuing with independent tasks"

  # Check for newly available tasks
  LOOP (back to Query current state)

END WHILE
```

### Step P3: Launching Concurrent Tasks

Use the Task tool to launch multiple subagents simultaneously:

```markdown
For each available task (up to MAX_CONCURRENT):

  1. Update task status to in_progress:
     TaskUpdate(taskId="{TASK_ID}", status="in_progress")

  2. Launch subagent:
     Task(
       subagent_type="general-purpose",
       prompt="Execute /sdd:do-task {TASK_ID}. Complete the full workflow: implement, test, verify, commit."
     )

  3. Track task as running:
     RUNNING_TASKS="${RUNNING_TASKS} {TASK_ID}"
```

**Note:** The Task tool allows multiple concurrent calls. Launch all available tasks (up to MAX_CONCURRENT) in a single response to maximize parallelism.

### Step P4: Polling for Completion

Use TaskList to check task status:

```markdown
Query: TaskList()

For each task in response:
  IF task.status = 'completed' AND task.id in RUNNING_TASKS:
    Remove from RUNNING_TASKS
    Add to COMPLETED_TASKS
    PARALLEL_TASKS_RUNNING -= 1

  IF task.status = 'pending' AND task.blockedBy is empty:
    Add to AVAILABLE_TASKS (for next launch cycle)
```

Poll every 30 seconds until all tasks complete or fail.

### Step P5: Error Handling in Parallel Mode

**Single Task Failure:**

If a task fails:
- Log the failure with reason
- Continue with independent tasks (do NOT cascade failure)
- Tasks that depend on the failed task will remain blocked
- Report failed tasks in final summary

```markdown
IF task fails:
  Log: "Task {TASK_ID} failed: {error_reason}"
  Add to FAILED_TASKS
  Continue execution loop (do not abort)
```

**Parallel Execution Error:**

If the parallel execution mechanism itself encounters issues:

```markdown
IF parallel execution error (TaskList unavailable, Task tool error, etc.):
  Log: "Warning: Parallel execution error, falling back to sequential mode"
  Set PARALLEL_MODE=false
  Continue with remaining tasks using sequential workflow (Step 3 above)
```

**Error Recovery:**
- Completed tasks remain completed
- In-progress tasks continue (tracked by subagents)
- Pending tasks continue in sequential mode

### Step P6: Parallel Mode Final Report

When parallel execution completes, generate the enhanced report:

```
=== PARALLEL EXECUTION REPORT ===

Mode: Parallel (--parallel)
Max concurrent: 3

Timing:
  Start: {start_time}
  End: {end_time}
  Duration: {parallel_duration}

Phase Breakdown:
  Phase 0: {count} tasks ({parallel_batches} parallel batches)
  Phase 1: {count} tasks ({parallel_batches} parallel batches)
  Phase 2: {count} tasks ({parallel_batches} parallel batches)
  Phase 3: {count} tasks ({parallel_batches} parallel batches)

Results:
  Completed: {completed_count}
  Failed: {failed_count}

Completed Tasks:
{foreach completed task:}
  {timestamp} {TASK_ID}: {title}

{If any failed:}
Failed Tasks:
  {TASK_ID}: {error_reason}

{If fallback occurred:}
Note: Parallel execution encountered issues at {timestamp}
      Fell back to sequential mode for remaining {count} tasks

=== END PARALLEL EXECUTION REPORT ===
```

### Parallel vs Sequential Mode Summary

| Aspect | Sequential (default) | Parallel (--parallel) |
|--------|---------------------|----------------------|
| Task execution | One at a time | Up to 3 concurrent |
| Dependencies | Phase order | blockedBy graph |
| Error handling | Stop or continue | Continue with independent |
| Prerequisites | None | Tasks API + dependency graph |
| Fallback | N/A | Falls back to sequential |
| Use case | Safety, simplicity | Speed with independent tasks |

### When to Use Parallel Mode

**Good candidates for parallel execution:**
- Tickets with many independent tasks in the same phase
- Tasks that don't share files or resources
- Well-defined dependency graph

**Avoid parallel execution when:**
- Tasks have implicit dependencies not in the graph
- Tasks modify shared files
- Debugging is needed (sequential is easier to follow)
- First time running a ticket (use sequential to verify correctness)

---

## Help / Quick Reference

### Usage

```bash
# Sequential execution (default)
/sdd:do-all-tasks TICKET_ID

# Parallel execution (opt-in)
/sdd:do-all-tasks TICKET_ID --parallel
```

**Examples:**
```bash
/sdd:do-all-tasks AUTH
/sdd:do-all-tasks FEATURE --parallel
```

### What This Command Does

1. **Validates ticket** - Checks review approval and task existence
2. **Gathers inventory** - Scans tasks and their status
3. **Hydrates to Tasks API** - Enables Ctrl+T tracking (if enabled)
4. **Executes tasks** - Calls `/sdd:do-task` for each unverified task
5. **Reports progress** - Provides summary at completion

### Parallel Mode (--parallel)

Enable concurrent execution of independent tasks within phases:

| Mode | Execution | Best For |
|------|-----------|----------|
| Sequential (default) | One task at a time | Small tickets, debugging |
| Parallel (--parallel) | Up to 3 concurrent | Medium/large tickets with independent tasks |

**Performance expectations:**

| Ticket Type | Independent Tasks | Expected Improvement |
|-------------|-------------------|---------------------|
| Medium (12 tasks) | 6+ | ~32% faster |
| Large (22 tasks) | 12+ | ~28% faster |
| Small (< 6 tasks) | Any | Minimal benefit |
| Linear chain | 0 | No benefit (slight overhead) |

### Feature Flags

| Flag | Default | Description |
|------|---------|-------------|
| `SDD_TASKS_API_ENABLED` | `true` | Enable Tasks API. Set to `'false'` to disable. |
| `CLAUDE_TASK_LIST_ID` | Auto-set | Set automatically to TICKET_ID |

### Disable Tasks API (file-only mode)

```bash
SDD_TASKS_API_ENABLED=false /sdd:do-all-tasks TICKET_ID
```

### Common Issues

| Issue | Solution |
|-------|----------|
| Review not approved | Run `/sdd:review TICKET_ID` first |
| No tasks found | Run `/sdd:create-tasks TICKET_ID` first |
| Parallel mode slower | Normal for small/linear tickets; use sequential |
| Tasks API unavailable | Automatic fallback to file-only mode |
| Parallel execution error | Automatic fallback to sequential mode |

### See Also

- `/sdd:do-task` - Execute single task
- `/sdd:tasks-status` - Check task completion status
- `/sdd:create-tasks` - Generate tasks from plan
- [SKILL.md](../skills/project-workflow/SKILL.md) - Full documentation
- [delegation-patterns.md](../skills/project-workflow/references/delegation-patterns.md) - Parallel execution details
