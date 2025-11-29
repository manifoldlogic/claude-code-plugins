---
description: Create tickets from project plan
argument-hint: [PROJECT_SLUG]
---

# Create Project Tickets

## Context

Project: $ARGUMENTS
Project folder: `.crewchief/projects/$ARGUMENTS_*/`

## Workflow

**IMPORTANT: You are an orchestrator. You do NOT create tickets yourself. You delegate to the ticket-creator agent.**

### Step 1: Locate Project

Find the project folder and verify plan exists:
```bash
ls -d .crewchief/projects/${ARGUMENTS}_* 2>/dev/null
ls .crewchief/projects/${ARGUMENTS}_*/planning/plan.md 2>/dev/null
```

If plan.md doesn't exist, recommend running /project-create first.

### Step 2: Check Review Status

Check if project-review.md exists:
```bash
ls .crewchief/projects/${ARGUMENTS}_*/planning/project-review.md 2>/dev/null
```

If no review exists, **warn user** but allow proceeding:
```
WARNING: No project review found.
Recommendation: Run /project-review {SLUG} first to catch issues early.
Proceeding with ticket creation...
```

### Step 3: Delegate Ticket Creation

**Delegate to ticket-creator agent (Sonnet):**

```
Task: Create all tickets for project {SLUG} based on the execution plan

Context:
- Project path: {project_path}
- Plan: {project_path}/planning/plan.md
- Architecture: {project_path}/planning/architecture.md
- Quality strategy: {project_path}/planning/quality-strategy.md

Instructions:
1. Read plan.md to understand phases and deliverables
2. For each phase, create tickets:
   - Phase 1: SLUG-1001, SLUG-1002, etc.
   - Phase 2: SLUG-2001, SLUG-2002, etc.
3. Each ticket must have:
   - Clear acceptance criteria (measurable)
   - Agent assignments
   - Technical requirements
   - Dependencies noted
4. Keep tickets to 2-8 hour scope
5. Create ticket index: {SLUG}_TICKET_INDEX.md
6. Follow work-ticket-template.md format

Return:
- Count of tickets created per phase
- List of ticket IDs
- Any issues encountered
```

### Step 4: Report

```
TICKETS CREATED: {PROJECT_NAME}

Phase 1: {count} tickets
{SLUG}-1001: {brief title}
{SLUG}-1002: {brief title}
...

Phase 2: {count} tickets
{SLUG}-2001: {brief title}
...

Total: {total_count} tickets

Ticket Index: {project_path}/tickets/{SLUG}_TICKET_INDEX.md

Next Steps:
1. Run /review-tickets {SLUG} to verify quality
2. Run /project-work {SLUG} to execute all tickets
   Or /ticket {SLUG}-1001 to work on first ticket
```

## Key Constraints

- Use ticket-creator agent for creating tickets
- DO NOT write ticket files yourself
- DO NOT create ticket content yourself
- Verify plan exists before delegating
