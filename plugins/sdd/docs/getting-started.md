# Getting Started with SDD Plugin

This guide walks you through creating and completing your first ticket using the SDD (Spec Driven Development) plugin.

**Time to Complete**: ~30 minutes

**What You'll Learn**:
- How to initialize a new ticket
- How to complete planning documents
- How to review and decompose work into tasks
- How to execute tasks and commit results
- How to archive completed work

---

## Prerequisites

Before starting, ensure:

1. **SDD plugin installed** in Claude Code
2. **Working directory initialized** - The plugin sets `SDD_ROOT_DIR` automatically
3. **Basic familiarity** with Claude Code slash commands

To verify the plugin is working:

```bash
/sdd:tasks-status
```

**Expected output**: Status information showing any active tickets, or a message indicating no tickets found.

---

## Your First Ticket: Step by Step

Let's create a simple ticket for adding a new feature to demonstrate the complete workflow.

### Step 1: Initialize Your Ticket

```bash
/sdd:plan-ticket DEMO add-user-profile-feature
```

**What This Does**: Creates a new ticket directory with planning templates.

**Expected Output**:
```
Ticket scaffolded: DEMO_add-user-profile-feature

Created structure:
  DEMO_add-user-profile-feature/
    ├── README.md
    ├── planning/
    │   ├── plan.md
    │   ├── architecture.md
    │   ├── quality-strategy.md
    │   └── ...
    └── tasks/

---
RECOMMENDED NEXT STEP: /sdd:review DEMO
Complete planning documents, then run review to verify quality
```

### Step 2: Complete Planning Documents

Navigate to your ticket directory and complete the planning documents. The SDD plugin requires substantial planning before task creation.

**Required Documents**:

1. **plan.md** - What are we building and why?
   - Describe the feature in detail
   - List concrete deliverables
   - Break work into phases
   - Define success criteria

2. **architecture.md** - How will we build it?
   - Technical approach
   - Components involved
   - Integration points
   - Dependencies

3. **quality-strategy.md** - How will we ensure quality?
   - Testing approach
   - Coverage requirements
   - Risk mitigation

**Important**: Each document must have at least **100 words** of substantive content. Empty or stub planning documents will fail validation when you try to decompose.

### Step 3: Review Your Ticket

Once planning is complete, run the review:

```bash
/sdd:review DEMO
```

**What This Does**: Performs a critical review of your planning documents.

**Expected Output**: A review document (`planning/ticket-review.md`) with PASS or FAIL decision.

**If Review Fails**:
- `❌ Planning documents too short` → Add more detail
- `❌ Missing architecture` → Complete all required docs
- `❌ Unclear scope` → Refine deliverables and boundaries

Address any issues and re-run the review.

### Step 4: Decompose into Tasks

After review passes:

```bash
/sdd:create-tasks DEMO
```

**What This Does**: Generates individual task files from your plan.

**Expected Output**:
```
Pre-Execution Validation:
✓ planning/plan.md exists (245 words)
✓ planning/architecture.md exists (189 words)

Tasks created:
✓ DEMO.1001_implement-profile-model.md
✓ DEMO.1002_add-profile-api.md
✓ DEMO.1003_create-profile-ui.md

3 tasks ready for execution
```

**If Decompose Fails**:
- `❌ planning/plan.md has insufficient content` → Add more detail (need 100+ words)
- `❌ planning/architecture.md - NOT FOUND` → Create the missing file

### Step 5: Execute Tasks

Now execute all tasks systematically:

```bash
/sdd:do-all-tasks DEMO
```

**What This Does**: Runs each task through the full implementation workflow.

**Pre-Execution Checklist**:
```
=== PRE-EXECUTION CHECKLIST ===
✓ Review document exists
✓ Review status: Approved
✓ Tasks found: 3 task(s)
✓ Task naming: All files follow convention

Proceeding with execution...
```

**The Flow for Each Task**:
1. **Implement** - Primary agent does the work
2. **Test** - unit-test-runner executes tests
3. **Verify** - verify-task checks acceptance criteria
4. **Commit** - commit-task creates conventional commit

### Step 6: Work on Individual Tasks (Alternative)

You can also execute tasks one at a time:

```bash
/sdd:do-task DEMO.1001
```

This is useful when you want more control over the execution pace or need to handle tasks with complex dependencies.

### Step 7: Check Progress

At any time, check your ticket status:

```bash
/sdd:tasks-status DEMO
```

**Output shows**:
- Tasks completed vs remaining
- Verification status per task
- Any blockers or issues

### Step 8: Archive Completed Ticket

When all tasks are verified:

```bash
/sdd:archive DEMO
```

**What This Does**: Moves the completed ticket to the archive.

**Expected Output**:
```
ARCHIVE REVIEW

Tickets Reviewed: 1

ARCHIVED:
✓ DEMO_add-user-profile-feature: All 3 tasks verified - Archived

References Updated: 0 files
```

---

## Quick Reference

```
/sdd:plan-ticket [ID] [name]     → Initialize ticket
[Complete planning documents]    → Fill plan.md, architecture.md, quality-strategy.md
/sdd:review [ID]                 → Review planning (creates ticket-review.md)
/sdd:create-tasks [ID]           → Generate tasks from plan
/sdd:do-all-tasks [ID]           → Execute all tasks systematically
/sdd:do-task [TASK_ID]           → Execute single task (e.g., DEMO.1001)
/sdd:tasks-status [ID]           → Check progress
/sdd:code-review [ID]            → Review implementation (recommended)
/sdd:pr [ID]                     → Create pull request
/sdd:archive [ID]                → Archive completed ticket
```

---

## Common First-Time Issues

### "Decompose fails with validation error"

**Cause**: Planning documents too short or missing

**Solution**: Ensure each planning doc has >100 words of substantive content. The pre-decompose validation checks:
- `plan.md` exists and has >100 words
- `architecture.md` exists and has >100 words

### "Can't execute - review not passed"

**Cause**: Skipped `/sdd:review` or review returned FAIL

**Solution**: Run `/sdd:review [TICKET_ID]` and ensure it passes. If it fails, address the review findings first.

### "Task won't verify"

**Cause**: Not all acceptance criteria met

**Solution**:
1. Read the task file's acceptance criteria
2. Ensure each criterion has evidence in the code
3. Check that tests were actually run (not just created)
4. Verify the "Task completed" checkbox is checked

### "Dependency check failed"

**Cause**: Task depends on incomplete prerequisites

**Solution**: Complete the dependency tasks first. The error message shows which dependencies are blocking:
```
❌ DEMO.1001 - Not complete (Task completed checkbox unchecked)
```

### "Archive fails - tasks not verified"

**Cause**: Some tasks haven't been verified

**Solution**: Run `/sdd:tasks-status [TICKET_ID]` to see which tasks need verification, then complete them.

---

## Next Steps

Now that you've completed your first ticket:

- **[Command Reference](command-reference.md)** - Detailed command documentation
- **[Quality Assurance](../skills/project-workflow/references/quality-assurance.md)** - Understanding quality gates
- **[Troubleshooting](troubleshooting.md)** - Solutions to common issues
- **[Workflow Overview](../skills/project-workflow/references/workflow-overview.md)** - Visual workflow diagrams

---

**Document Version**: 1.0
**Last Updated**: 2025-12-11
**Applies to**: SDD Plugin v1.0.0+
