---
description: |
  Analyze a completed ticket and create repo-local skills from reusable patterns.
  Delegates to the skill-curator agent for analysis and skill creation.

  Usage examples:
  - Basic: /sdd:curate-skills AUTH
  - After completing tasks: /sdd:curate-skills CACHE
argument-hint: [TICKET_ID]
---

# Curate Skills

## Context

User input: "$ARGUMENTS"
Plugin root: "${CLAUDE_PLUGIN_ROOT}"

## Workflow

**IMPORTANT: You are an orchestrator. You do NOT do the analysis yourself. You delegate to the skill-curator agent.**

### Step 0: Parse Arguments

Extract from `$ARGUMENTS`:
- **TICKET_ID**: The ticket identifier (required, first argument)

If `$ARGUMENTS` is empty or not provided, go to the **Missing Arguments** section below.

### Step 1: Locate Ticket

Find the ticket folder:
```bash
ls -d ${SDD_ROOT_DIR:-/app/.sdd}/tickets/${ARGUMENTS}_* 2>/dev/null
```

**If not found**, check the archive:
```bash
ls -d ${SDD_ROOT_DIR:-/app/.sdd}/archive/tickets/${ARGUMENTS}_* 2>/dev/null
```

**Error handling**:
- If not found in either location: Go to the **Invalid Ticket** section below
- If found: Record the full ticket path as `TICKET_PATH`

### Step 2: List Existing Skills

Show current skill inventory for context:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/skill-curation/scripts/list-skills.sh
```

Note the count and names of existing skills.

### Step 3: Delegate to skill-curator Agent

**Delegate to skill-curator agent (Sonnet):**

```
Assignment: Analyze ticket {TICKET_ID} and curate repo-local skills from reusable patterns

Context:
- Ticket path: {TICKET_PATH}
- Planning docs: {TICKET_PATH}/planning/
- Task files: {TICKET_PATH}/tasks/
- Deliverables: {TICKET_PATH}/deliverables/
- Existing skills: {count from Step 2} skills already exist
- Skills directory: ${SDD_ROOT_DIR:-/app/.sdd}/skills/

Instructions:
1. Read reference documents (skill-quality-criteria.md and skill-creation-workflow.md)
2. Check existing skills via list-skills.sh
3. Read all ticket artifacts (planning docs, task files, deliverables)
4. Identify skill candidates from ticket patterns
5. Evaluate each candidate against quality criteria
6. Write evaluation report to {TICKET_PATH}/deliverables/skill-curation-report.md
7. Create SKILL.md files for accepted candidates
8. Verify all created skills
9. Report results summary

Return:
- Count of candidates evaluated
- Count of skills created
- Count of skills skipped
- Names of created skills (if any)
- Path to evaluation report
```

### Step 4: Report Results

After skill-curator agent completes, display summary:

```
SKILL CURATION COMPLETE: {TICKET_ID}

Evaluation Report: {TICKET_PATH}/deliverables/skill-curation-report.md

Candidates: {evaluated_count} evaluated
Created:    {created_count} skills
Skipped:    {skipped_count} candidates

{If skills were created:}
New Skills:
  - {skill-name}: {description}

{If no skills created:}
No reusable patterns identified for skill extraction.

Existing Skills: {total_count} (run list-skills.sh to see all)
```

### Next Step Prompt

After displaying the report above, use the **AskUserQuestion** tool to present next steps to the user:

**Question:** "What would you like to do next?"
**Header:** "Next step"
**multiSelect:** false

**Options:**
- Label: "/sdd:archive {TICKET_ID}" | Description: "Archive the completed ticket"
- Label: "/sdd:status" | Description: "Check current ticket and task status"
- Label: "/sdd:curate-skills {another_ticket}" | Description: "Curate skills from another ticket"

Where {TICKET_ID} is the actual ticket ID from the command execution context, NOT the literal placeholder text.

---

## Missing Arguments

If no TICKET_ID was provided, display usage guidance:

```
USAGE: /sdd:curate-skills TICKET_ID

Analyze a completed ticket and create repo-local skills from reusable patterns.

Arguments:
  TICKET_ID   The ticket identifier (e.g., AUTH, CACHE, APIV2)

What this does:
  1. Reads all ticket artifacts (planning docs, tasks, deliverables)
  2. Identifies reusable patterns worth capturing as skills
  3. Evaluates candidates against quality criteria
  4. Creates SKILL.md files for accepted patterns
  5. Produces an evaluation report showing reasoning

Examples:
  /sdd:curate-skills AUTH
  /sdd:curate-skills CACHE

Skills are created under: ${SDD_ROOT_DIR:-/app/.sdd}/skills/
```

Then use the **AskUserQuestion** tool:

**Question:** "Which ticket would you like to curate skills from?"
**Header:** "Select a ticket"
**multiSelect:** false

List active tickets as options by running:
```bash
ls -d ${SDD_ROOT_DIR:-/app/.sdd}/tickets/*/ 2>/dev/null
```

For each ticket directory found, create an option:
- Label: "/sdd:curate-skills {TICKET_ID}" | Description: "{ticket directory name}"

If no tickets are found, display:
```
No active tickets found. Create a ticket first with /sdd:plan-ticket.
```

---

## Invalid Ticket

If the TICKET_ID was provided but the ticket does not exist:

```
ERROR: Ticket "{ARGUMENTS}" not found.

Searched:
  - ${SDD_ROOT_DIR:-/app/.sdd}/tickets/{ARGUMENTS}_*
  - ${SDD_ROOT_DIR:-/app/.sdd}/archive/tickets/{ARGUMENTS}_*

Available tickets:
```

Then list available tickets:
```bash
ls -d ${SDD_ROOT_DIR:-/app/.sdd}/tickets/*/ 2>/dev/null
```

If tickets exist, display them and suggest:
```
Try: /sdd:curate-skills {first_available_TICKET_ID}
```

If no tickets exist:
```
No active tickets found. Create one with /sdd:plan-ticket.
```

## Key Constraints

- Use skill-curator agent for all analysis and creation
- DO NOT evaluate patterns yourself
- DO NOT create SKILL.md files yourself
- Trust the agent's quality assessment
- The evaluation report is a required intermediate deliverable
