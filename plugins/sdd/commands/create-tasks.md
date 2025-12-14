---
description: Create tasks from ticket plan
argument-hint: [TICKET_ID] [optional: additional instructions]
---

# Create Ticket Tasks

## Context

Ticket: $ARGUMENTS
Ticket folder: `${SDD_ROOT_DIR}/tickets/$ARGUMENTS_*/`

## Workflow

**IMPORTANT: You are an orchestrator. You do NOT create tasks yourself. You delegate to the task-creator agent.**

### Step 0: Parse Arguments

Extract from `$ARGUMENTS`:
- **TICKET_ID**: The ticket identifier (first argument)
- **Additional Instructions**: Optional task creation guidance or decomposition strategy (everything after TICKET_ID)

Examples:
- `APIV2` → ticket_id: "APIV2", instructions: none
- `APIV2 Create smaller tasks, 2-4 hours each` → ticket_id: "APIV2", instructions: "Create smaller tasks, 2-4 hours each"
- `APIV2 Separate frontend and backend changes into different tasks` → ticket_id: "APIV2", instructions: "Separate frontend and backend changes into different tasks"

### Step 1: Locate Ticket

Find the ticket folder:
```bash
TICKET_PATH=$(ls -d ${SDD_ROOT_DIR:-/app/.sdd}/tickets/${ARGUMENTS}_* 2>/dev/null | head -1)
```

If ticket doesn't exist, report error and exit.

### Step 2: Pre-Execution Validation (BLOCKING)

**CRITICAL: These validations MUST pass before proceeding. If any validation fails, create-tasks CANNOT continue.**

Run the following validation checks:

```bash
# Define ticket path
TICKET_PATH=$(ls -d ${SDD_ROOT_DIR:-/app/.sdd}/tickets/${ARGUMENTS}_* 2>/dev/null | head -1)
VALIDATION_FAILED=false
ERRORS=""

# Check 1: Required documents exist
echo "Validating planning documents..."

if [ ! -f "$TICKET_PATH/planning/plan.md" ]; then
  ERRORS="${ERRORS}\n❌ planning/plan.md - NOT FOUND (REQUIRED)"
  VALIDATION_FAILED=true
fi

if [ ! -f "$TICKET_PATH/planning/architecture.md" ]; then
  ERRORS="${ERRORS}\n❌ planning/architecture.md - NOT FOUND (REQUIRED)"
  VALIDATION_FAILED=true
fi

# Check 2: Required documents have substantial content (>100 words)
if [ -f "$TICKET_PATH/planning/plan.md" ]; then
  PLAN_WORDS=$(wc -w < "$TICKET_PATH/planning/plan.md")
  if [ "$PLAN_WORDS" -lt 100 ]; then
    ERRORS="${ERRORS}\n❌ planning/plan.md - insufficient content ($PLAN_WORDS words, need 100+)"
    VALIDATION_FAILED=true
  fi
fi

if [ -f "$TICKET_PATH/planning/architecture.md" ]; then
  ARCH_WORDS=$(wc -w < "$TICKET_PATH/planning/architecture.md")
  if [ "$ARCH_WORDS" -lt 100 ]; then
    ERRORS="${ERRORS}\n❌ planning/architecture.md - insufficient content ($ARCH_WORDS words, need 100+)"
    VALIDATION_FAILED=true
  fi
fi

# Check 3: quality-strategy.md recommended (warn but don't block)
if [ ! -f "$TICKET_PATH/planning/quality-strategy.md" ]; then
  echo "⚠️  planning/quality-strategy.md - NOT FOUND (recommended for testing requirements)"
fi

# Report validation result
if [ "$VALIDATION_FAILED" = true ]; then
  echo "❌ VALIDATION FAILED: Cannot create tasks for ticket"
  echo -e "$ERRORS"
  echo ""
  echo "Action Required:"
  echo "1. Complete all required planning documents"
  echo "2. Ensure each document has >100 words of content"
  echo "3. Run /sdd:plan-ticket or manually create missing docs"
  echo "4. Re-run /sdd:create-tasks after planning is complete"
  # EXIT - Do not proceed
fi
```

**Validation Requirements:**

| Document | Required | Min Content |
|----------|----------|-------------|
| planning/plan.md | YES | 100+ words |
| planning/architecture.md | YES | 100+ words |
| planning/quality-strategy.md | Recommended | - |
| planning/ticket-review.md | Recommended | - |

**If validation fails:**
```
❌ VALIDATION FAILED: Cannot create tasks for ticket

Missing Required Documents:
❌ planning/plan.md - NOT FOUND (REQUIRED)

Documents with Insufficient Content:
❌ planning/architecture.md - insufficient content (45 words, need 100+)

Action Required:
1. Complete all required planning documents
2. Ensure each document has >100 words of content
3. Run /sdd:plan-ticket or manually create missing docs
4. Re-run /sdd:create-tasks after planning is complete
```

**DO NOT PROCEED if validation fails. The task-creator agent cannot create quality tasks from incomplete plans.**

### Step 3: Check Review Status (Warning Only)

Check if ticket-review.md exists:
```bash
ls ${SDD_ROOT_DIR:-/app/.sdd}/tickets/${ARGUMENTS}_*/planning/ticket-review.md 2>/dev/null
```

If no review exists, **strongly warn user** but allow proceeding:
```
⚠️  WARNING: No ticket review found

STRONGLY RECOMMENDED: Run /sdd:review {TICKET_ID} before creating tasks

Why review matters:
• Catches planning issues before they become task problems
• Identifies missing requirements and unclear scope
• Validates alignment with development principles
• Significantly reduces rework and wasted effort

Skipping review increases risk of:
• Creating tasks based on incomplete or flawed plans
• Missing critical dependencies or conflicts
• Poor task decomposition requiring revision
• Lower success probability

Tickets reviewed before task creation have ~80% higher success rates.

Proceeding with task creation anyway...
```

### Step 4: Delegate Task Creation

**Delegate to task-creator agent (Sonnet):**

```
Assignment: Create all tasks for ticket {TICKET_ID} based on the execution plan

Context:
- Ticket path: {ticket_path}
- Plan: {ticket_path}/planning/plan.md
- Architecture: {ticket_path}/planning/architecture.md
- Quality strategy: {ticket_path}/planning/quality-strategy.md
- Additional instructions: {ARGUMENTS after TICKET_ID, or "None provided"}

Instructions:
1. Read plan.md to understand phases and deliverables
2. For each phase, create tasks:
   - Phase 1: TICKET_ID.1001, TICKET_ID.1002, etc.
   - Phase 2: TICKET_ID.2001, TICKET_ID.2002, etc.
3. Each task must have:
   - Clear acceptance criteria (measurable)
   - Agent assignments
   - Technical requirements
   - Dependencies noted
   - Test requirements (happy path, error cases, edge conditions)
4. Keep tasks to 2-8 hour scope
5. Create task index: {TICKET_ID}_TASK_INDEX.md
6. Follow work-task-template.md format

Return:
- Count of tasks created per phase
- List of task IDs
- Any issues encountered
```

### Step 5: Report

```
TASKS CREATED: {TICKET_NAME}

Phase 1: {count} tasks
{TICKET_ID.1001}: {brief title}
{TICKET_ID.1002}: {brief title}
...

Phase 2: {count} tasks
{TICKET_ID.2001}: {brief title}
...

Total: {total_count} tasks

Task Index: {ticket_path}/tasks/{TICKET_ID}_TASK_INDEX.md

Next Steps:
1. Review tasks quality: /sdd:review {TICKET_ID}
   (Recommended to verify task quality before execution)
2. After review passes, execute tasks:
   - Run all: /sdd:do-all-tasks {TICKET_ID}
   - Or run first: /sdd:do-task {TICKET_ID.1001}
```

## Error Recovery

### If task-creator agent fails or produces partial output:

1. **Check for partial task creation:**
   ```bash
   ls ${SDD_ROOT_DIR}/tickets/${TICKET_ID}_*/tasks/
   ```

2. **Recovery options:**
   - **Option A - Retry:** Re-run `/sdd:create-tasks {TICKET_ID}` (will recreate all tasks)
   - **Option B - Manual completion:** Create remaining tasks manually using the template:
     ```bash
     # Copy template for each missing task
     cp ${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/templates/work-task-template.md \
        ${SDD_ROOT_DIR}/tickets/${TICKET_ID}_*/tasks/${TICKET_ID}.{PHASE}{NUMBER}_{task-name}.md
     ```
   - **Option C - Adjust plan:** If agent repeatedly fails, simplify plan.md and retry

3. **For manual task creation:**
   - Follow work-task-template.md structure exactly
   - Use proper task ID format: `TICKET_ID.{PHASE}{NUMBER}` (e.g., APIV2.1001)
   - Ensure all checkboxes and sections are present
   - Update task index manually

4. **Validation after recovery:**
   - Verify all tasks follow template structure
   - Ensure task IDs are sequential within phases
   - Check that all plan.md phases have corresponding tasks

### If plan.md is incomplete or unclear:

1. **Update the plan first:**
   - Run `/sdd:review {TICKET_ID}` to identify issues
   - Run `/sdd:update {TICKET_ID}` to fix planning documents
   - Re-run `/sdd:review {TICKET_ID}` to validate improvements

2. **Then retry create-tasks:**
   - Clear plan = successful task creation
   - Agent needs good structure to work from

## Example Usage

```bash
# Basic task creation
/sdd:create-tasks APIV2

# Specify task size preference
/sdd:create-tasks APIV2 Create smaller tasks, 2-4 hours each

# Provide decomposition strategy
/sdd:create-tasks APIV2 Separate frontend and backend changes into different tasks

# Prioritize specific aspects
/sdd:create-tasks APIV2 Ensure comprehensive test coverage tasks are included for each feature

# Multiple guidance items
/sdd:create-tasks APIV2 Create parallel tasks where possible, keep tasks under 4 hours
```

## Key Constraints

- Use task-creator agent for creating tasks
- DO NOT write task files yourself
- DO NOT create task content yourself
- Verify plan exists before delegating
