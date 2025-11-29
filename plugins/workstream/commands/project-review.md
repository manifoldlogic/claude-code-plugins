---
description: Critical review of project before creating tickets
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

### Step 2: Delegate Review

**Delegate to project-reviewer agent (Sonnet):**

```
Task: Conduct critical review of project {SLUG}

Context:
- Project path: {project_path}
- Planning docs: {project_path}/planning/

Instructions:
1. Read all planning documents
2. Search codebase for related implementations
3. Check for reinvention of existing functionality
4. Evaluate requirements quality
5. Assess scope and feasibility
6. Check alignment with MVP principles
7. Identify risks and gaps
8. Create project-review.md with findings
9. Provide readiness recommendation

Be constructively critical. Find problems NOW, not after wasted effort.

Return:
- Overall status (Ready/Needs Work/Not Ready)
- Critical issues count
- Top 3 recommended actions
- Success probability
```

### Step 3: Report Summary

After review completes:

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
{If Ready/Caution}: /project-tickets {SLUG}
{If Needs Work}: Address issues, then re-run /project-review {SLUG}
```

## Key Constraints

- Use project-reviewer agent for the review
- DO NOT analyze documents yourself
- DO NOT create the review document yourself
- Trust the agent's assessment
