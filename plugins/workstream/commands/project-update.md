---
description: Systematically update project planning documents and tickets based on project-review findings to address critical issues, gaps, and recommendations
argument-hint: [PROJECT_SLUG]
---

# Project Update

## Context

Project: $ARGUMENTS
Project folder: `.crewchief/projects/$ARGUMENTS_*/`
Review document: `.crewchief/projects/$ARGUMENTS_*/planning/project-review.md`

## Workflow

**IMPORTANT: You are an orchestrator. You do NOT do the updates yourself. You delegate to the project-updater agent.**

### Step 1: Locate Project and Review

Find the project folder:
```bash
ls -d .crewchief/projects/${ARGUMENTS}_* 2>/dev/null
```

If not found, report error and suggest valid projects.

Check for review document:
```bash
ls .crewchief/projects/${ARGUMENTS}_*/planning/project-review.md 2>/dev/null
```

If no review exists:
```
❌ NO REVIEW FOUND

Cannot update project without a review.

Run first: /workstream:project-review {SLUG}

Then run: /workstream:project-update {SLUG}
```

### Step 2: Check for Existing Tickets

```bash
ls .crewchief/projects/${ARGUMENTS}_*/tickets/*.md 2>/dev/null | wc -l
```

Determine scope:
- **Planning only**: No tickets exist (update planning docs only)
- **Planning + Tickets**: Tickets exist (update both planning docs AND tickets)

### Step 3: Delegate Update

**Delegate to project-updater agent (Sonnet):**

```
Task: Update project {SLUG} based on review findings

Context:
- Project path: {project_path}
- Review document: {project_path}/planning/project-review.md
- Planning docs: {project_path}/planning/
- Tickets exist: {yes/no}
- Ticket count: {count if any}
- Ticket path: {project_path}/tickets/

Instructions:
1. Read project-review.md thoroughly
2. Extract all critical issues, high-risk areas, gaps, and recommendations
3. Create review-updates.md to track all changes

Update Priority Order:
1. Critical Issues (Blockers) - Must fix
2. Boundary Violations - Fix improper integrations
3. High-Risk Areas - Mitigate risks
4. Gaps & Ambiguities - Fill missing info
5. Scope & Feasibility - Adjust scope
6. Alignment Issues - Improve MVP discipline

For planning documents:
- Update analysis.md, architecture.md, plan.md as needed
- Update quality-strategy.md, security-review.md as needed
- Make changes specific and concrete (not vague improvements)
- Maintain consistency across documents

{If tickets exist, ALSO:}
For each ticket needing revision (from review):
- Fix acceptance criteria if vague
- Adjust scope if too large/small
- Add missing implementation details
- Fix dependency declarations
- Ensure consistency with updated planning docs

Document all changes in review-updates.md

Return:
- Count of planning docs updated
- Count of tickets updated (if any)
- Key improvements made
- Remaining concerns (if any)
- Recommendation for next step
```

### Step 4: Report Summary

After update completes:

**If no tickets:**
```
📝 PROJECT UPDATES COMPLETE: {PROJECT_NAME}

=== PLANNING UPDATES ===
Documents Updated: {count}

✅ CRITICAL ISSUES RESOLVED: {X}/{X}
• {Most significant fix}
• {Second major fix}

⚠️ RISKS MITIGATED: {X}/{X}
• {Key mitigation}

🔧 GAPS FILLED: {X}/{X}
• {Major gap resolved}

📊 SCOPE OPTIMIZED:
• Removed: {features/complexity removed}
• Clarified: {key boundaries}

📁 DOCUMENTS MODIFIED:
• analysis.md - {brief change}
• architecture.md - {brief change}
• plan.md - {brief change}

✨ KEY IMPROVEMENTS:
1. {Most impactful improvement}
2. {Second major improvement}
3. {Third significant change}

📋 NEXT STEP: /workstream:project-review {SLUG}
   (Re-run review to verify all issues resolved)

Full update log: {project_path}/planning/review-updates.md
```

**If tickets exist:**
```
📝 PROJECT UPDATES COMPLETE: {PROJECT_NAME}

=== PLANNING UPDATES ===
Documents Updated: {count}

✅ CRITICAL ISSUES RESOLVED: {X}/{X}
• {Most significant fix}

⚠️ RISKS MITIGATED: {X}/{X}
• {Key mitigation}

=== TICKET UPDATES ===
Tickets Updated: {count}/{total}

📋 TICKETS MODIFIED:
• {SLUG-1001}: {what was fixed}
• {SLUG-1003}: {what was fixed}

📋 TICKETS UNCHANGED (already good):
• {SLUG-1002}, {SLUG-1004}

🔗 DEPENDENCY FIXES:
• {Any dependency corrections}

✨ KEY IMPROVEMENTS:
1. {Most impactful improvement}
2. {Second major improvement}
3. {Third significant change}

⚠️ REMAINING CONCERNS (if any):
• {Concern that couldn't be fully resolved}

📋 NEXT STEP: /workstream:project-review {SLUG}
   (Re-run review to verify all issues resolved)

   If review passes: /workstream:project-work {SLUG}

Full update log: {project_path}/planning/review-updates.md
```

## Key Constraints

- REQUIRES project-review.md to exist
- Use project-updater agent for the updates
- DO NOT analyze or update documents yourself
- DO NOT make changes yourself
- Trust the agent's implementation
- Must update BOTH planning docs AND tickets if tickets exist
- All changes must be tracked in review-updates.md
