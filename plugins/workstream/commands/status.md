---
description: Check status of projects and tickets
argument-hint: [PROJECT_SLUG or empty for all]
---

# Status Check

## Context

Project: $ARGUMENTS (optional - if empty, shows all projects)

## Workflow

**IMPORTANT: Use scripts for data gathering, optionally Haiku for formatting.**

### Step 1: Gather Status Data

**Run status script:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/scripts/ticket-status.sh ${ARGUMENTS}
```

This returns JSON with:
- Projects
- Tickets per project
- Checkbox states (completed, tested, verified)

### Step 2: Format Report

For simple output, parse JSON directly and format.

For rich formatting, optionally **delegate to status-reporter agent (Haiku):**

```
Task: Format ticket status report

Input: {JSON from script}

Instructions:
1. Create summary table
2. Calculate progress percentages
3. Highlight items needing attention
4. Group by phase

Return: Formatted markdown report
```

### Step 3: Report

**For single project:**

```
PROJECT STATUS: {SLUG}_{name}

Progress: ██████░░░░ 60% (6/10 verified)

By Phase:
| Phase | Total | Verified | Remaining |
|-------|-------|----------|-----------|
| 1     | 5     | 5        | 0         |
| 2     | 5     | 1        | 4         |

Tickets Needing Attention:
• {SLUG}-2002: Completed but not tested
• {SLUG}-2003: Pending

Next Actions:
1. Run tests for {SLUG}-2002
2. Continue work on {SLUG}-2003
```

**For all projects:**

```
ALL PROJECTS STATUS

| Project | Progress | Verified | Total |
|---------|----------|----------|-------|
| APIV2   | 60%      | 6        | 10    |
| CACHE   | 100%     | 4        | 4     |
| AUTH    | 25%      | 1        | 4     |

Ready to Archive: CACHE (all verified)

Most Active: APIV2 (Phase 2 in progress)

Recommended Next:
• /project-work APIV2 - Continue execution
• /archive - Archive CACHE
```

## Optional: Detailed Summary

If user asks for more detail:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/scripts/project-summary.sh ${SLUG}
```

This generates full markdown summary.

## Key Constraints

- Use ticket-status.sh for data (don't scan files manually)
- Keep reports concise
- Highlight actionable items
- Calculate percentages correctly
