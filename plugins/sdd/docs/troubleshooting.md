# Troubleshooting Guide

Common issues and solutions for the SDD plugin.

**Version**: 1.0.0
**Last Updated**: 2025-12-11

---

## How to Use This Guide

1. Find your issue by error message or symptom
2. Follow the resolution steps
3. If issue persists, see [Getting Help](#getting-help)

**Quick Links**:
- [Planning Issues](#planning-phase-issues)
- [Review/Decompose Issues](#reviewdecompose-issues)
- [Execution Issues](#execution-issues)
- [Verification Issues](#verification-issues)
- [Archive Issues](#archive-issues)
- [General Issues](#general-issues)
- [Recovery Procedures](#recovery-procedures)

---

## Planning Phase Issues

### "Ticket directory already exists"

**Error**:
```
ERROR: Ticket directory already exists: DEMO_example-ticket
```

**Cause**: Attempting to initialize a ticket with an ID that already exists.

**Solution**:
1. Check existing tickets: `/sdd:tasks-status`
2. If ticket exists and is active, proceed with planning instead
3. If old/abandoned, use a different TICKET_ID
4. If corrupted, manually remove directory (use caution)

**Prevention**: Check `/sdd:tasks-status` before initializing new tickets.

---

### "Planning documents too short"

**Error**:
```
❌ VALIDATION FAILED: planning/plan.md has insufficient content (45 words, need 100+)
```

**Cause**: Planning document doesn't meet minimum content requirement (100 words).

**Solution**:
1. Open the planning document in your editor
2. Add more detail:
   - Expand objectives section
   - Add deliverable descriptions
   - Include background context
3. Verify word count: `wc -w planning/plan.md`
4. Re-run `/sdd:create-tasks`

**Prevention**: Complete planning thoroughly before decomposing.

---

## Review/Decompose Issues

### "Review document missing"

**Error**:
```
✗ Review document missing (ticket-review.md)
```

**Cause**: Haven't run `/sdd:review` before attempting to execute.

**Solution**:
1. Run `/sdd:review [TICKET_ID]`
2. Address any review feedback
3. Ensure review passes
4. Then proceed with `/sdd:create-tasks` or `/sdd:do-all-tasks`

**Prevention**: Always run review after completing planning.

---

### "Review has not passed"

**Error**:
```
❌ VALIDATION FAILED: review has not passed
```

**Cause**: Review exists but returned FAIL decision.

**Solution**:
1. Read the review feedback in `planning/ticket-review.md`
2. Address each identified issue
3. Run `/sdd:update [TICKET_ID]` to fix issues
4. Re-run `/sdd:review [TICKET_ID]`
5. Repeat until review passes

**Prevention**: Address review feedback before proceeding.

---

### "Architecture document not found"

**Error**:
```
❌ planning/architecture.md - NOT FOUND (REQUIRED)
```

**Cause**: Required planning document doesn't exist.

**Solution**:
1. Create the missing file: `planning/architecture.md`
2. Add technical approach content (100+ words)
3. Include: components, integration points, dependencies
4. Re-run `/sdd:create-tasks`

**Prevention**: Use `/sdd:plan-ticket` which creates all required templates.

---

## Execution Issues

### "No tasks found"

**Error**:
```
✗ No tasks found in tasks/ directory
```

**Cause**: Attempting to execute before decomposing.

**Solution**:
1. Run `/sdd:create-tasks [TICKET_ID]` to create tasks
2. Verify tasks were created: check `tasks/` directory
3. Then run `/sdd:do-all-tasks [TICKET_ID]`

**Prevention**: Follow workflow order: review → create-tasks → execute.

---

### "Dependency check failed"

**Error**:
```
❌ DEPENDENCY CHECK FAILED: Cannot execute DEMO.2001

Unsatisfied Dependencies:
❌ DEMO.1001 - Not complete (Task completed checkbox unchecked)
```

**Cause**: Task depends on other tasks that aren't complete yet.

**Solution**:
1. Check which dependencies are blocking (shown in error)
2. Complete prerequisite tasks first: `/sdd:do-task [DEP_TASK_ID]`
3. Verify dependency shows "Task completed" checkbox checked
4. Re-run the blocked task

**Prevention**: Use `/sdd:do-all-tasks` for automatic dependency ordering.

---

### "Task file not found"

**Error**:
```
Task file not found: DEMO.1001
```

**Cause**: Task ID doesn't match any existing task file.

**Solution**:
1. List available tasks: `/sdd:tasks-status [TICKET_ID]`
2. Check task file naming in `tasks/` directory
3. Use exact task ID (case-sensitive)
4. Verify TICKET_ID prefix is correct

**Prevention**: Copy task IDs from status output.

---

## Verification Issues

### "Tests pass checkbox incorrectly checked"

**Error**:
```
❌ [CRITICAL] "Tests pass" checked but no test execution evidence found
```

**Cause**: Test checkbox marked complete without actually running tests.

**Solution**:
1. Run the appropriate test suite
2. Capture and document test output
3. Ensure all tests pass
4. Re-run verification

**Prevention**: Always run tests before marking the checkbox.

---

### "Acceptance criteria not met"

**Error**:
```
❌ VERIFICATION FAILED

Acceptance Criteria Status:
✓ Database schema created
✗ API endpoint returns user data - Issue: No endpoint implementation found
```

**Cause**: Task work incomplete or doesn't satisfy all criteria.

**Solution**:
1. Review which criteria failed (shown in error)
2. Complete missing implementation
3. Update task file checkboxes
4. Re-run verification

**Prevention**: Review all acceptance criteria before marking task complete.

---

## Archive Issues

### "Tasks not verified"

**Error**:
```
✗ DEMO_example-ticket: 2/4 tasks verified - Incomplete
  Missing verification: DEMO.1003, DEMO.1004
```

**Cause**: Attempting to archive with incomplete tasks.

**Solution**:
1. Run `/sdd:tasks-status [TICKET_ID]` to see incomplete tasks
2. Complete each incomplete task: `/sdd:do-task [TASK_ID]`
3. Ensure all tasks show "Verified" checkbox checked
4. Re-run `/sdd:archive`

**Prevention**: Complete all tasks before archiving.

---

## General Issues

### "Command not found"

**Symptom**: `/sdd:*` commands not recognized.

**Cause**: SDD plugin not installed or not loaded.

**Solution**:
1. Verify plugin installation
2. Restart Claude Code
3. Check plugin status in settings
4. Reinstall plugin if necessary

---

### "SDD_ROOT_DIR not set"

**Symptom**: Commands fail with directory errors.

**Cause**: Environment variable not configured.

**Solution**:
1. The plugin should set this automatically via SessionStart hook
2. If not set, verify hook is running
3. Manual override: `export SDD_ROOT_DIR=/app/.sdd`
4. Run `/sdd:setup` to verify environment

---

### "Git operations fail"

**Symptom**: Commit or archive fails with git errors.

**Cause**: Git not configured or not in repository.

**Solution**:
1. Verify git repository: `git status`
2. Configure git if needed:
   ```bash
   git config --global user.name "Your Name"
   git config --global user.email "your@email.com"
   ```
3. Initialize repository if needed: `git init`

---

## Recovery Procedures

### Recover from Failed Decompose

If decompose created partial tasks and then failed:

1. Review tasks created in `tasks/` directory
2. Delete any incomplete/corrupted task files
3. Fix the planning issues that caused failure
4. Re-run `/sdd:create-tasks` (won't overwrite existing valid tasks)

### Recover from Failed Task Execution

If task execution fails mid-work:

1. Review task file to see what was completed
2. Check `git status` for uncommitted changes
3. Decide: continue task or restart
4. Update task checkboxes to reflect actual state
5. Re-run `/sdd:do-task` to resume

### Recover from Corrupted Ticket

If ticket directory is corrupted:

1. Back up the ticket directory
2. Review what's salvageable (planning, tasks, commits)
3. If planning intact: Continue from last checkpoint
4. If planning lost: Recover from git history
5. If unrecoverable: Start new ticket, reference old work in notes

---

## Getting Help

### Self-Service Resources

- [Getting Started](getting-started.md) - Workflow walkthrough
- [Command Reference](command-reference.md) - Detailed command docs
- [Workflow Guide](workflow-guide.md) - Visual workflow
- [Quality Assurance](../skills/project-workflow/references/quality-assurance.md) - Quality gates

### When to Escalate

- Error messages not in this guide
- Repeated failures after following troubleshooting
- Plugin crashes or hangs
- Data corruption or loss

### How to Report Issues

1. Document exact error message
2. Capture command that caused error
3. Note which workflow phase you're in
4. Describe steps to reproduce
5. Report to plugin maintainers with details

---

**Document Version**: 1.0
**Applies to**: SDD Plugin v1.0.0+
