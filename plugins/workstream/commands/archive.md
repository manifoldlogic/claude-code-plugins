---
description: Archive completed projects
argument-hint: [PROJECT_SLUG or empty to review all]
---

# Archive Projects

## Context

Project: $ARGUMENTS (optional - if empty, reviews all projects)

## Workflow

**IMPORTANT: You are an orchestrator. Use scripts for validation and scanning.**

### Step 1: Gather Status

**Run status script:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/scripts/ticket-status.sh ${ARGUMENTS}
```

### Step 2: Identify Candidates

From the status JSON, identify projects where:
- ALL tickets have `verified: true`
- No pending or in-progress tickets

### Step 3: Validate Structure

For each candidate, **run validation:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/scripts/validate-structure.sh ${SLUG}
```

Ensure:
- All required files exist
- No structural issues

### Step 4: Verify Ticket Checkboxes

**CRITICAL: Source of truth is the ticket files themselves.**

For each ticket file, verify the "Verified" checkbox is checked:
```markdown
- [x] **Verified** - by the verify-ticket agent
```

If ANY ticket has unchecked Verified, do NOT archive.

### Step 5: Update Documents Before Archive

Before moving:

1. **Update ticket index** to show final status
2. **Update README** with completion date
3. **Check for knowledge to extract to /docs/**

### Step 6: Archive

For each fully verified project:

```bash
mv .crewchief/projects/{SLUG}_{name}/ .crewchief/archive/projects/
```

### Step 7: Update References

Search for references to archived project:
```bash
grep -r "projects/${SLUG}" .crewchief/ docs/
```

Update paths from `projects/` to `archive/projects/`.

### Step 8: Report

```
ARCHIVE REVIEW

Projects Reviewed: {count}

ARCHIVED:
✓ {SLUG1}_{name}: All {count} tickets verified - Archived
✓ {SLUG2}_{name}: All {count} tickets verified - Archived

NOT ARCHIVED:
✗ {SLUG3}_{name}: {X}/{Y} tickets verified - Incomplete
  Missing verification: {SLUG3}-2003, {SLUG3}-2004

RECOMMENDATIONS:
• Complete work on {SLUG3} before archiving
• Run /project-work {SLUG3} to finish remaining tickets

References Updated: {count} files
```

## Archive Criteria

**Archive if ALL true:**
- ALL tickets have `- [x] **Verified**` checkbox
- No active development planned
- Knowledge extracted (if applicable)

**Do NOT archive if ANY true:**
- Any ticket has unchecked Verified
- Active development continuing
- Blocking other projects

## Key Constraints

- Source of truth: Verified checkbox in ticket files
- Do NOT archive partially complete projects
- Update references before moving
- Use scripts for scanning (don't read files manually)
