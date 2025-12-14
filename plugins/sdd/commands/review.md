---
description: Critical review of ticket readiness, risks, and alignment with development principles. Run BEFORE task creation to catch issues early, or after for complete assessment.
argument-hint: [TICKET_ID] [optional: additional instructions]
---

# Ticket Review

## Context

User input: "$ARGUMENTS"
Ticket folder: `${SDD_ROOT_DIR}/tickets/$ARGUMENTS_*/`

## Workflow

**IMPORTANT: You are an orchestrator. You do NOT do the review yourself. You delegate to the ticket-reviewer agent.**

### Step 0: Parse Arguments

Extract from `$ARGUMENTS`:
- **TICKET_ID**: The ticket identifier (first argument)
- **Additional Instructions**: Optional review focus areas or specific concerns (everything after TICKET_ID)

### Step 1: Locate Ticket

Find the ticket folder:
```bash
ls -d ${SDD_ROOT_DIR:-/app/.sdd}/tickets/${ARGUMENTS}_* 2>/dev/null
```

If not found, report error and suggest valid tickets.

### Step 2: Check for Existing Tasks

```bash
ls ${SDD_ROOT_DIR:-/app/.sdd}/tickets/${ARGUMENTS}_*/tasks/*.md 2>/dev/null | wc -l
```

Determine if this is:
- **Pre-task review**: No tasks exist yet (planning phase)
- **Post-task review**: Tasks already created (includes task review)

### Step 3: Delegate Review

**Delegate to ticket-reviewer agent (Sonnet):**

```
Assignment: Conduct critical review of ticket {TICKET_ID}

Context:
- Ticket path: {ticket_path}
- Planning docs: {ticket_path}/planning/
- Tasks exist: {yes/no}
- Task count: {count if any}
- Additional instructions: {ARGUMENTS after TICKET_ID, or "None provided"}

Instructions:
1. Read all planning documents
2. Search codebase for related implementations
3. Check for reinvention of existing functionality
4. Evaluate requirements quality
5. Assess scope and feasibility
6. Check alignment with scope discipline principles
7. Identify risks and gaps

{If tasks exist, ALSO:}
8. Review each task individually for:
   - Clarity and completeness
   - Proper acceptance criteria
   - Appropriate scope (2-8 hours)
   - Consistency with planning docs
   - Proper dependencies defined
   - No overlapping scope between tasks
9. Check task sequence and dependencies
10. Identify tasks needing revision

11. Create ticket-review.md with findings
12. Provide readiness recommendation

Be constructively critical. Find problems NOW, not after wasted effort.

Return:
- Overall status (Ready/Needs Work/Not Ready)
- Critical issues count
- {If tasks}: Tasks needing revision count
- Top 3 recommended actions
- Success probability
```

### Step 4: Report Summary

After review completes:

**If no tasks exist:**
```
TICKET REVIEW COMPLETE: {TICKET_NAME}

Status: {Not Ready | Needs Work | Proceed with Caution | Ready}
Risk Level: {Low | Medium | High | Critical}

Critical Issues: {count}
• {Issue 1 brief}
• {Issue 2 brief}

High Risks: {count}
• {Risk 1 brief}

Alignment:
• Scope Discipline: {Strong|Adequate|Weak}
• Pragmatism: {Strong|Adequate|Weak}
• Agent Compatibility: {Strong|Adequate|Weak}

Recommendation: {Proceed | Revise Then Proceed | Significant Rework | Reconsider}

Success Probability: {X}%

Top Actions Before Proceeding:
1. {Action 1}
2. {Action 2}
3. {Action 3}

Full review: {ticket_path}/planning/ticket-review.md

Next:
{If Ready/Caution}: /sdd:create-tasks {TICKET_ID}
{If Needs Work}: /sdd:update {TICKET_ID}
```

**If tasks exist:**
```
TICKET REVIEW COMPLETE: {TICKET_NAME}

Status: {Not Ready | Needs Work | Proceed with Caution | Ready}
Risk Level: {Low | Medium | High | Critical}

=== PLANNING REVIEW ===
Critical Issues: {count}
• {Issue 1 brief}

High Risks: {count}
• {Risk 1 brief}

=== TASK REVIEW ===
Total Tasks: {count}
✅ Ready: {count}
⚠️ Needs Revision: {count}
❌ Blocked: {count}

Tasks Needing Attention:
• {TICKET_ID.1001}: {issue summary}
• {TICKET_ID.1003}: {issue summary}

Common Task Issues:
• {Pattern 1}
• {Pattern 2}

=== OVERALL ===
Alignment:
• Scope Discipline: {Strong|Adequate|Weak}
• Pragmatism: {Strong|Adequate|Weak}
• Agent Compatibility: {Strong|Adequate|Weak}

Recommendation: {Proceed | Revise Then Proceed | Significant Rework | Reconsider}

Success Probability: {X}%

Top Actions:
1. {Action 1}
2. {Action 2}
3. {Action 3}

Full review: {ticket_path}/planning/ticket-review.md

Next:
{If Ready}: /sdd:do-all-tasks {TICKET_ID}
{If Needs Work}: /sdd:update {TICKET_ID}
```

## When to Re-run Review

Review is not a one-time gate - re-run in these scenarios:

1. **After `/sdd:update`** (recommended):
   - Validate that fixes addressed the issues
   - Verify no new problems were introduced
   - Confirm readiness improved

2. **After significant plan changes:**
   - Manual edits to plan.md or architecture.md
   - Scope adjustments based on new information
   - Major requirement clarifications

3. **Before `/sdd:do-all-tasks` (optional validation):**
   - Additional safety check after task creation
   - Catches issues that emerged during decompose
   - Recommended for high-risk or complex tickets

4. **After creating/updating multiple tasks:**
   - Validate task consistency
   - Check for overlapping scope
   - Ensure dependencies are correct

5. **When stuck or uncertain:**
   - Get fresh perspective on ticket health
   - Identify what might be blocking progress
   - Validate assumptions before continuing

**Iteration Guidance:**
- First review → Update → Second review: Normal, expected flow
- Third+ review: Consider if fundamental redesign needed
- If 3+ review iterations with persistent issues, consider "Reconsider" recommendation

## Example Usage

```bash
# Basic review
/sdd:review APIV2

# Focus on specific area
/sdd:review APIV2 Focus on security and input validation

# Check specific concern
/sdd:review CACHE Check for race conditions in concurrent access paths

# Performance-focused review
/sdd:review DOCKER Focus on container startup time and resource constraints
```

## Key Constraints

- Use ticket-reviewer agent for the review
- DO NOT analyze documents yourself
- DO NOT create the review document yourself
- Trust the agent's assessment
- Include task review if tasks exist
