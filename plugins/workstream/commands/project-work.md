---
description: Execute all tickets for a project systematically
argument-hint: [PROJECT_SLUG]
---

# Work on Project

## Context

Project: $ARGUMENTS
Project folder: `.crewchief/projects/$ARGUMENTS_*/`
Tickets: `.crewchief/projects/$ARGUMENTS_*/tickets/`

## Workflow

**IMPORTANT: You are an orchestrator. You coordinate ticket execution by delegating to /ticket for each ticket.**

### Step 1: Gather Ticket Inventory

**Use script to get status:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/scripts/ticket-status.sh ${ARGUMENTS}
```

This returns JSON with all tickets and their status.

### Step 2: Plan Execution Order

From the status JSON, determine:
1. Which tickets are not yet verified
2. Dependency order (Phase 1 before Phase 2, etc.)
3. Skip already-verified tickets

### Step 3: Execute Each Ticket

**For each unverified ticket, in order:**

Invoke `/ticket {TICKET_ID}` which handles:
- Implementation
- Testing
- Verification
- Commit

Wait for each ticket to complete before starting the next.

**DO NOT manually implement tickets. The /ticket command handles the full workflow.**

### Step 4: Handle Failures

If a ticket fails verification:
1. Note the failure
2. **Do NOT use workarounds**
3. Create follow-up ticket if needed
4. Continue with other tickets
5. Report failures at the end

### Step 5: Track Progress

After each ticket:
- Update mental model of completed work
- Check if phase is complete
- Note any created follow-up tickets

### Step 6: Final Report

```
PROJECT EXECUTION COMPLETE: {PROJECT_NAME}

Summary:
- Total tickets: {total}
- Verified: {verified_count}
- Failed: {failed_count}
- Skipped: {skipped_count}

Completed Tickets:
✓ {SLUG}-1001: {title}
✓ {SLUG}-1002: {title}
...

{If any failed:}
Failed Tickets:
✗ {SLUG}-XXXX: {reason}

{If any follow-up:}
Follow-up Tickets Created:
• {SLUG}-XXXX: {description}

Git Status:
{run git status to confirm no uncommitted changes}

Next Steps:
{If all verified}: Run /archive to archive completed project
{If failures}: Address failed tickets and re-run
```

## Key Constraints

- Use /ticket for each ticket (do NOT implement directly)
- Use ticket-status.sh for inventory
- Complete tickets in dependency order
- Do NOT skip verification steps
- Do NOT use workarounds for blocked tickets
