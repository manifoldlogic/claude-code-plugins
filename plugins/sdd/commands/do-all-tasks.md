---
description: Execute all tasks for a ticket systematically
argument-hint: [TICKET_ID]
---

# Work on Ticket

## Context

Ticket: $ARGUMENTS
Task folder: `${SDD_ROOT_DIR}/tickets/$ARGUMENTS_*/`
Tasks: `${SDD_ROOT_DIR}/tickets/$ARGUMENTS_*/tasks/`

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

Completed Tasks:
✓ {TICKET_ID.1001}: {title}
✓ {TICKET_ID.1002}: {title}
...

{If any failed:}
Failed Tasks:
✗ {TICKET_ID.XXXX}: {reason}

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
