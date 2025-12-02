---
description: Critical review of project readiness, risks, and alignment with development principles. Run BEFORE ticket creation to catch issues early, or after for complete assessment.
argument-hint: [PROJECT_SLUG]
---

# Project Review

## Context

Project: $ARGUMENTS
Project folder: `.crewchief/projects/$ARGUMENTS_*/`

## Workflow

**IMPORTANT: You are an orchestrator. You do NOT do the review yourself. You delegate to the project-reviewer agent.**

### Step 1: Locate Project

Find the project folder:
```bash
ls -d .crewchief/projects/${ARGUMENTS}_* 2>/dev/null
```

If not found, report error and suggest valid projects.

### Step 2: Check for Existing Tickets

```bash
ls .crewchief/projects/${ARGUMENTS}_*/tickets/*.md 2>/dev/null | wc -l
```

Determine if this is:
- **Pre-ticket review**: No tickets exist yet (planning phase)
- **Post-ticket review**: Tickets already created (includes ticket review)

### Step 3: Delegate Review

**Delegate to project-reviewer agent (Sonnet):**

```
Task: Conduct critical review of project {SLUG}

Context:
- Project path: {project_path}
- Planning docs: {project_path}/planning/
- Tickets exist: {yes/no}
- Ticket count: {count if any}

Instructions:
1. Read all planning documents
2. Search codebase for related implementations
3. Check for reinvention of existing functionality
4. Evaluate requirements quality
5. Assess scope and feasibility
6. Check alignment with MVP principles
7. Identify risks and gaps

{If tickets exist, ALSO:}
8. Review each ticket individually for:
   - Clarity and completeness
   - Proper acceptance criteria
   - Appropriate scope (2-8 hours)
   - Consistency with planning docs
   - Proper dependencies defined
   - No overlapping scope between tickets
9. Check ticket sequence and dependencies
10. Identify tickets needing revision

11. Create project-review.md with findings
12. Provide readiness recommendation

Be constructively critical. Find problems NOW, not after wasted effort.

Return:
- Overall status (Ready/Needs Work/Not Ready)
- Critical issues count
- {If tickets}: Tickets needing revision count
- Top 3 recommended actions
- Success probability
```

### Step 4: Report Summary

After review completes:

**If no tickets exist:**
```
PROJECT REVIEW COMPLETE: {PROJECT_NAME}

Status: {Not Ready | Needs Work | Proceed with Caution | Ready}
Risk Level: {Low | Medium | High | Critical}

Critical Issues: {count}
• {Issue 1 brief}
• {Issue 2 brief}

High Risks: {count}
• {Risk 1 brief}

Alignment:
• MVP Discipline: {Strong|Adequate|Weak}
• Pragmatism: {Strong|Adequate|Weak}
• Agent Compatibility: {Strong|Adequate|Weak}

Recommendation: {Proceed | Revise Then Proceed | Significant Rework | Reconsider}

Success Probability: {X}%

Top Actions Before Proceeding:
1. {Action 1}
2. {Action 2}
3. {Action 3}

Full review: {project_path}/planning/project-review.md

Next:
{If Ready/Caution}: /workstream:project-tickets {SLUG}
{If Needs Work}: /workstream:project-update {SLUG}
```

**If tickets exist:**
```
PROJECT REVIEW COMPLETE: {PROJECT_NAME}

Status: {Not Ready | Needs Work | Proceed with Caution | Ready}
Risk Level: {Low | Medium | High | Critical}

=== PLANNING REVIEW ===
Critical Issues: {count}
• {Issue 1 brief}

High Risks: {count}
• {Risk 1 brief}

=== TICKET REVIEW ===
Total Tickets: {count}
✅ Ready: {count}
⚠️ Needs Revision: {count}
❌ Blocked: {count}

Tickets Needing Attention:
• {SLUG-1001}: {issue summary}
• {SLUG-1003}: {issue summary}

Common Ticket Issues:
• {Pattern 1}
• {Pattern 2}

=== OVERALL ===
Alignment:
• MVP Discipline: {Strong|Adequate|Weak}
• Pragmatism: {Strong|Adequate|Weak}
• Agent Compatibility: {Strong|Adequate|Weak}

Recommendation: {Proceed | Revise Then Proceed | Significant Rework | Reconsider}

Success Probability: {X}%

Top Actions:
1. {Action 1}
2. {Action 2}
3. {Action 3}

Full review: {project_path}/planning/project-review.md

Next:
{If Ready}: /workstream:project-work {SLUG}
{If Needs Work}: /workstream:project-update {SLUG}
```

## Key Constraints

- Use project-reviewer agent for the review
- DO NOT analyze documents yourself
- DO NOT create the review document yourself
- Trust the agent's assessment
- Include ticket review if tickets exist
