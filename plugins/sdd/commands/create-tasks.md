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

### Step 2: Pre-Execution Validation

The create-tasks command performs two tiers of validation before delegating to the task-creator agent.

#### Validation Tiers

**Required (Blocking)** - These documents MUST exist and have substantial content (100+ words). If any required validation fails, task creation CANNOT proceed.

**Recommended (Warning Only)** - These documents should exist but are not required. If missing or insufficient, a warning is shown but task creation continues. This maintains backward compatibility with existing tickets.

#### Validation Checks

Run the following validation checks:

```bash
# Define ticket path
TICKET_PATH=$(ls -d ${SDD_ROOT_DIR:-/app/.sdd}/tickets/${ARGUMENTS}_* 2>/dev/null | head -1)
VALIDATION_FAILED=false
ERRORS=""
WARNINGS=""

# ═══════════════════════════════════════════════════════════════════
# REQUIRED VALIDATIONS (BLOCKING)
# ═══════════════════════════════════════════════════════════════════

echo "Validating planning documents..."

# Check 1: plan.md (REQUIRED)
if [ ! -f "$TICKET_PATH/planning/plan.md" ]; then
  ERRORS="${ERRORS}\n❌ planning/plan.md - NOT FOUND (REQUIRED)"
  VALIDATION_FAILED=true
else
  PLAN_WORDS=$(wc -w < "$TICKET_PATH/planning/plan.md")
  if [ "$PLAN_WORDS" -lt 100 ]; then
    ERRORS="${ERRORS}\n❌ planning/plan.md - insufficient content ($PLAN_WORDS words, need 100+)"
    VALIDATION_FAILED=true
  fi
fi

# Check 2: architecture.md (REQUIRED)
if [ ! -f "$TICKET_PATH/planning/architecture.md" ]; then
  ERRORS="${ERRORS}\n❌ planning/architecture.md - NOT FOUND (REQUIRED)"
  VALIDATION_FAILED=true
else
  ARCH_WORDS=$(wc -w < "$TICKET_PATH/planning/architecture.md")
  if [ "$ARCH_WORDS" -lt 100 ]; then
    ERRORS="${ERRORS}\n❌ planning/architecture.md - insufficient content ($ARCH_WORDS words, need 100+)"
    VALIDATION_FAILED=true
  fi
fi

# ═══════════════════════════════════════════════════════════════════
# RECOMMENDED VALIDATIONS (WARNING ONLY)
# ═══════════════════════════════════════════════════════════════════

# Check 3: prd.md (RECOMMENDED)
if [ ! -f "$TICKET_PATH/planning/prd.md" ]; then
  WARNINGS="${WARNINGS}\n⚠️  PRD.md not found at planning/prd.md"
  WARNINGS="${WARNINGS}\n"
  WARNINGS="${WARNINGS}\n   Consider creating a Product Requirements Document to:"
  WARNINGS="${WARNINGS}\n   - Define clear functional and non-functional requirements"
  WARNINGS="${WARNINGS}\n   - Establish measurable acceptance criteria"
  WARNINGS="${WARNINGS}\n   - Clarify what is in/out of scope"
  WARNINGS="${WARNINGS}\n   - Document assumptions and success metrics"
  WARNINGS="${WARNINGS}\n"
  WARNINGS="${WARNINGS}\n   This is recommended but not required. Task creation will continue."
else
  PRD_WORDS=$(wc -w < "$TICKET_PATH/planning/prd.md")
  if [ "$PRD_WORDS" -lt 100 ]; then
    WARNINGS="${WARNINGS}\n⚠️  PRD.md exists but is very short ($PRD_WORDS words, recommend 100+)"
    WARNINGS="${WARNINGS}\n"
    WARNINGS="${WARNINGS}\n   A comprehensive PRD should include:"
    WARNINGS="${WARNINGS}\n   - Product vision and target users"
    WARNINGS="${WARNINGS}\n   - Functional and non-functional requirements"
    WARNINGS="${WARNINGS}\n   - User stories and acceptance criteria"
    WARNINGS="${WARNINGS}\n   - Scope boundaries and assumptions"
    WARNINGS="${WARNINGS}\n"
    WARNINGS="${WARNINGS}\n   Consider expanding PRD.md before creating tasks."
    WARNINGS="${WARNINGS}\n   Task creation will continue."
  fi
fi

# Check 4: quality-strategy.md (RECOMMENDED)
if [ ! -f "$TICKET_PATH/planning/quality-strategy.md" ]; then
  WARNINGS="${WARNINGS}\n⚠️  planning/quality-strategy.md - NOT FOUND (recommended for testing requirements)"
fi

# ═══════════════════════════════════════════════════════════════════
# REPORT VALIDATION RESULTS
# ═══════════════════════════════════════════════════════════════════

# Show warnings (non-blocking)
if [ -n "$WARNINGS" ]; then
  echo ""
  echo "═══════════════════════════════════════════════════════════════════"
  echo "RECOMMENDED DOCUMENT WARNINGS"
  echo "═══════════════════════════════════════════════════════════════════"
  echo -e "$WARNINGS"
  echo ""
fi

# Check for blocking failures
if [ "$VALIDATION_FAILED" = true ]; then
  echo ""
  echo "═══════════════════════════════════════════════════════════════════"
  echo "❌ VALIDATION FAILED: Cannot create tasks for ticket"
  echo "═══════════════════════════════════════════════════════════════════"
  echo -e "$ERRORS"
  echo ""
  echo "Action Required:"
  echo "1. Complete all required planning documents"
  echo "2. Ensure each document has >100 words of content"
  echo "3. Run /sdd:plan-ticket or manually create missing docs"
  echo "4. Re-run /sdd:create-tasks after planning is complete"
  # EXIT - Do not proceed
else
  echo ""
  echo "✓ Validation passed (required documents present)."
  echo "Delegating to task-creator agent..."
fi
```

#### Validation Requirements Summary

| Document | Status | Min Content | Behavior |
|----------|--------|-------------|----------|
| planning/plan.md | **REQUIRED** | 100+ words | Blocks if missing/insufficient |
| planning/architecture.md | **REQUIRED** | 100+ words | Blocks if missing/insufficient |
| planning/prd.md | Recommended | 100+ words | Warning only, continues |
| planning/quality-strategy.md | Recommended | - | Warning only, continues |
| planning/ticket-review.md | Recommended | - | Warning only, continues |

#### Example: Validation with Warnings (Backward Compatible)

When recommended documents are missing but required documents are present:

```text
Validating planning documents...

═══════════════════════════════════════════════════════════════════
RECOMMENDED DOCUMENT WARNINGS
═══════════════════════════════════════════════════════════════════

⚠️  PRD.md not found at planning/prd.md

   Consider creating a Product Requirements Document to:
   - Define clear functional and non-functional requirements
   - Establish measurable acceptance criteria
   - Clarify what is in/out of scope
   - Document assumptions and success metrics

   This is recommended but not required. Task creation will continue.

⚠️  planning/quality-strategy.md - NOT FOUND (recommended for testing requirements)

✓ Validation passed (required documents present).
Delegating to task-creator agent...
```

Task creation proceeds normally after warnings. Existing tickets without PRD.md will see this warning but can still create tasks.

#### Example: Thin PRD.md Warning

When PRD.md exists but has insufficient content:

```text
Validating planning documents...

═══════════════════════════════════════════════════════════════════
RECOMMENDED DOCUMENT WARNINGS
═══════════════════════════════════════════════════════════════════

⚠️  PRD.md exists but is very short (42 words, recommend 100+)

   A comprehensive PRD should include:
   - Product vision and target users
   - Functional and non-functional requirements
   - User stories and acceptance criteria
   - Scope boundaries and assumptions

   Consider expanding PRD.md before creating tasks.
   Task creation will continue.

✓ Validation passed (required documents present).
Delegating to task-creator agent...
```

#### Example: Required Validation Fails

When required documents are missing or insufficient:

```text
Validating planning documents...

═══════════════════════════════════════════════════════════════════
RECOMMENDED DOCUMENT WARNINGS
═══════════════════════════════════════════════════════════════════

⚠️  PRD.md not found at planning/prd.md
   ...

═══════════════════════════════════════════════════════════════════
❌ VALIDATION FAILED: Cannot create tasks for ticket
═══════════════════════════════════════════════════════════════════

❌ planning/plan.md - NOT FOUND (REQUIRED)
❌ planning/architecture.md - insufficient content (45 words, need 100+)

Action Required:
1. Complete all required planning documents
2. Ensure each document has >100 words of content
3. Run /sdd:plan-ticket or manually create missing docs
4. Re-run /sdd:create-tasks after planning is complete
```

**DO NOT PROCEED if required validation fails.** The task-creator agent cannot create quality tasks from incomplete plans. However, warnings about recommended documents (PRD.md, quality-strategy.md) do not block task creation.

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
- PRD (if exists): {ticket_path}/planning/prd.md
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

```

### Next Step Prompt

After displaying the report above, use the **AskUserQuestion** tool to present next steps to the user:

**Question:** "What would you like to do next?"
**Header:** "Next step"
**multiSelect:** false

**Options:**
- Label: "/sdd:review {TICKET_ID}" | Description: "Verify task quality before execution"
- Label: "/sdd:do-all-tasks {TICKET_ID}" | Description: "Execute all tasks immediately"

Where {TICKET_ID} is the actual ticket ID from the command execution context, NOT the literal placeholder text.

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
