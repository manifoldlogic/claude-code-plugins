---
description: Archive completed tickets
argument-hint: [TICKET_ID or empty to review all]
---

# Archive Tickets

## Context

Ticket: $ARGUMENTS (optional - if empty, reviews all tasks)

**Note:** Consider creating a Pull Request before archiving:
```bash
/sdd:pr {TICKET_ID}
```
This is optional but recommended for code review workflow.

## Workflow

**IMPORTANT: You are an orchestrator. Use scripts for validation and scanning.**

### Step 1: Gather Status

**Run status script:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/scripts/task-status.sh ${ARGUMENTS}
```

### Step 2: Identify Candidates

From the status JSON, identify tickets where:
- ALL tasks have `verified: true`
- No pending or in-progress tasks

### Step 3: Validate Structure

For each candidate, **run validation:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/scripts/validate-structure.sh ${TICKET_ID}
```

Ensure:
- All required files exist
- No structural issues

### Step 4: Verify Task Checkboxes

**CRITICAL: Source of truth is the task files themselves.**

For each task file, verify the "Verified" checkbox is checked:
```markdown
- [x] **Verified** - by the verify-task agent
```

If ANY task has unchecked Verified, do NOT archive.

### Step 5: Update Documents Before Archive

Before moving:

1. **Update task index** to show final status
2. **Update README** with completion date
3. **Check for knowledge to extract to /docs/**

### Step 6: Archive

For each fully verified ticket:

```bash
mv ${SDD_ROOT_DIR:-/app/.sdd}/tickets/{TICKET_ID}_{name}/ ${SDD_ROOT_DIR:-/app/.sdd}/archive/tickets/
```

### Step 7: Update References

Search for references to archived ticket:
```bash
grep -r "tickets/${TICKET_ID}" ${SDD_ROOT_DIR:-/app/.sdd}/ docs/
```

Update paths from `tickets/` to `archive/tickets/`.

### Step 8: Log Archival

For each archived ticket, log the event:

```bash
SDD_ROOT="${SDD_ROOT_DIR:-/app/.sdd}"
mkdir -p "$SDD_ROOT/logs"
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")|TICKET_ARCHIVED|{TICKET_ID}|-|archive|Completed, {X}/{X} tasks verified" >> "$SDD_ROOT/logs/workflow.log"
```

### Step 9: Collect Metrics

After archiving, collect and log metrics snapshot:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/scripts/collect-metrics.sh" --log
```

This captures the current state of all tickets and tickets to `{{SDD_ROOT}}/logs/metrics.log` for trend analysis.

### Step 10: Report

```
ARCHIVE REVIEW

Tickets Reviewed: {count}

ARCHIVED:
✓ {TICKET_ID1}_{name}: All {count} tasks verified - Archived
✓ {TICKET_ID2}_{name}: All {count} tasks verified - Archived

NOT ARCHIVED:
✗ {TICKET_ID3}_{name}: {X}/{Y} tasks verified - Incomplete
  Missing verification: {TICKET_ID3}.2003, {TICKET_ID3}.2004

RECOMMENDATIONS:
• Complete work on {TICKET_ID3} before archiving
• Run /sdd:do-all-tasks {TICKET_ID3} to finish remaining tasks

References Updated: {count} files
```

## Next Steps

After archiving completed tickets:

1. **Check remaining work:**
   - Run `/sdd:tasks-status` to see other active tickets
   - Review epic progress if this was part of an epic
   - Identify next priority ticket

2. **Continue epic work (if applicable):**
   - Run `/sdd:start-epic {EPIC_ID}` to review epic decomposition
   - Create next tickets with `/sdd:plan-ticket`

3. **Start new work:**
   - Create new ticket with `/sdd:plan-ticket [description]`
   - Import from Jira with `/sdd:import-jira-ticket [JIRA_KEY]`
   - Create new epic with `/sdd:start-epic [description]`

4. **Review metrics:**
   - Metrics logged to `${SDD_ROOT}/logs/metrics.log`
   - Track velocity and quality trends over time

## Archive Criteria

**Archive if ALL true:**
- ALL tasks have `- [x] **Verified**` checkbox
- No active development planned
- Knowledge extracted (if applicable)

**Do NOT archive if ANY true:**
- Any task has unchecked Verified
- Active development continuing
- Blocking other tickets

## Key Constraints

- Source of truth: Verified checkbox in task files
- Do NOT archive partially complete tickets
- Update references before moving
- Use scripts for scanning (don't read files manually)
