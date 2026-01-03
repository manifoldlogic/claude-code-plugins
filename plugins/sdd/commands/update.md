---
description: Systematically update ticket planning documents and tasks based on ticket-review findings to address critical issues, gaps, and recommendations
argument-hint: [TICKET_ID] [optional: additional instructions]
---

# Ticket Update

## Context

User input: "$ARGUMENTS"
Ticket folder: `${SDD_ROOT_DIR}/tickets/$ARGUMENTS_*/`
Review document: `${SDD_ROOT_DIR}/tickets/$ARGUMENTS_*/planning/ticket-review.md`

## Workflow

**IMPORTANT: You are an orchestrator. You do NOT do the updates yourself. You delegate to the ticket-updater agent.**

### Step 0: Parse Arguments

Extract from `$ARGUMENTS`:
- **TICKET_ID**: The ticket identifier (first argument)
- **Additional Instructions**: Optional update priorities or focus areas (everything after TICKET_ID)

### Step 1: Locate Ticket and Review

Find the ticket folder:
```bash
ls -d ${SDD_ROOT_DIR:-/app/.sdd}/tickets/${ARGUMENTS}_* 2>/dev/null
```

If not found, report error and suggest valid tickets.

Check for review document:
```bash
ls ${SDD_ROOT_DIR:-/app/.sdd}/tickets/${ARGUMENTS}_*/planning/ticket-review.md 2>/dev/null
```

If no review exists:
```
❌ NO REVIEW FOUND

Cannot update ticket without a review.

Run first: /sdd:review {TICKET_ID}

Then run: /sdd:update {TICKET_ID}
```

### Step 2: Check for Existing Tasks

```bash
ls ${SDD_ROOT_DIR:-/app/.sdd}/tickets/${ARGUMENTS}_*/tasks/*.md 2>/dev/null | wc -l
```

Determine scope:
- **Planning only**: No tasks exist (update planning docs only)
- **Planning + Tasks**: Tasks exist (update both planning docs AND tasks)

### Step 3: Delegate Update

**Delegate to ticket-updater agent (Sonnet):**

```
Assignment: Update ticket {TICKET_ID} based on review findings

Context:
- Ticket path: {ticket_path}
- Review document: {ticket_path}/planning/ticket-review.md
- Planning docs: {ticket_path}/planning/
- Tasks exist: {yes/no}
- Task count: {count if any}
- Task path: {ticket_path}/tasks/
- Additional instructions: {ARGUMENTS after TICKET_ID, or "None provided"}

Instructions:
1. Read ticket-review.md thoroughly
2. Extract all critical issues, high-risk areas, gaps, and recommendations
3. Create review-updates.md to track all changes

Update Priority Order:
1. Critical Issues (Blockers) - Must fix
2. Boundary Violations - Fix improper integrations
3. High-Risk Areas - Mitigate risks
4. Gaps & Ambiguities - Fill missing info
5. Scope & Feasibility - Adjust scope
6. Alignment Issues - Improve scope discipline

For planning documents:
- Update analysis.md, architecture.md, plan.md as needed
- Update quality-strategy.md, security-review.md as needed
- Make changes specific and concrete (not vague improvements)
- Maintain consistency across documents

{If tasks exist, ALSO:}
For each task needing revision (from review):
- Fix acceptance criteria if vague
- Adjust scope if too large/small
- Add missing implementation details
- Fix dependency declarations
- Ensure consistency with updated planning docs

Document all changes in review-updates.md

Return:
- Count of planning docs updated
- Count of tasks updated (if any)
- Key improvements made
- Remaining concerns (if any)
- Recommendation for next step
```

### Step 4: Report Summary

After update completes:

**If no tasks:**
```
📝 TICKET UPDATES COMPLETE: {TICKET_NAME}

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

Full update log: {ticket_path}/planning/review-updates.md

---
RECOMMENDED NEXT STEP: /sdd:review {TICKET_ID}
Verify update quality before proceeding.
```

**If tasks exist:**
```
📝 TICKET UPDATES COMPLETE: {TICKET_NAME}

=== PLANNING UPDATES ===
Documents Updated: {count}

✅ CRITICAL ISSUES RESOLVED: {X}/{X}
• {Most significant fix}

⚠️ RISKS MITIGATED: {X}/{X}
• {Key mitigation}

=== TASK UPDATES ===
Tasks Updated: {count}/{total}

📋 TASKS MODIFIED:
• {TICKET_ID.1001}: {what was fixed}
• {TICKET_ID.1003}: {what was fixed}

📋 TASKS UNCHANGED (already good):
• {TICKET_ID.1002}, {TICKET_ID.1004}

🔗 DEPENDENCY FIXES:
• {Any dependency corrections}

✨ KEY IMPROVEMENTS:
1. {Most impactful improvement}
2. {Second major improvement}
3. {Third significant change}

⚠️ REMAINING CONCERNS (if any):
• {Concern that couldn't be fully resolved}

Full update log: {ticket_path}/planning/review-updates.md

---
RECOMMENDED NEXT STEP: /sdd:review {TICKET_ID}
Verify update quality before proceeding.
```

## Example Usage

```bash
# Basic update
/sdd:update APIV2

# Prioritize critical issues
/sdd:update APIV2 Address critical issues first, then quick wins

# Focus on specific type
/sdd:update CACHE Focus on performance-related findings

# Defer certain updates
/sdd:update DOCKER Skip documentation updates for now, focus on security issues
```

## Key Constraints

- REQUIRES ticket-review.md to exist
- Use ticket-updater agent for the updates
- DO NOT analyze or update documents yourself
- DO NOT make changes yourself
- Trust the agent's implementation
- Must update BOTH planning docs AND tasks if tasks exist
- All changes must be tracked in review-updates.md
