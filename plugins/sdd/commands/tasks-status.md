---
description: Check task status for tickets
argument-hint: [TICKET_ID or empty for all]
---

# Status Check

## Context

Ticket: $ARGUMENTS (optional - if empty, shows all tasks)

## Workflow

**IMPORTANT: Use scripts for data gathering, optionally Haiku for formatting.**

### Step 1: Gather Status Data

**Run status script:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/scripts/task-status.sh ${ARGUMENTS}
```

This returns JSON with:
- Tickets
- Tasks per ticket
- Checkbox states (completed, tested, verified)

### Step 2: Format Report

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

Return: Formatted markdown report
```

### Step 3: Report

**For single ticket:**

```
TICKET STATUS: {TICKET_ID}_{name}

Progress: ██████░░░░ 60% (6/10 verified)

By Phase:
| Phase | Total | Verified | Remaining |
|-------|-------|----------|-----------|
| 1     | 5     | 5        | 0         |
| 2     | 5     | 1        | 4         |

Tickets Needing Attention:
• {TICKET_ID}.2002: Completed but not tested
• {TICKET_ID}.2003: Pending

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
• /sdd:do-all-tasks APIV2 - Continue execution
• /sdd:archive - Archive CACHE
```

## Optional: Detailed Summary

If user asks for more detail:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/scripts/ticket-summary.sh ${TICKET_ID}
```

This generates full markdown summary.

## Key Constraints

- Use task-status.sh for data (don't scan files manually)
- Keep reports concise
- Highlight actionable items
- Calculate percentages correctly
