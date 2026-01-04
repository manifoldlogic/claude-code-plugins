# SDD Command Reference

Complete reference for all SDD plugin commands.

**Version**: 1.1.0
**Last Updated**: 2026-01-04

---

## Commands by Workflow Phase

### Setup & Configuration
- [/sdd:setup](#sddsetup) - Initialize SDD environment

### Epic Management
- [/sdd:start-epic](#sddstart-epic) - Create research/discovery epic

### Ticket Management
- [/sdd:plan-ticket](#sddplan-ticket) - Initialize new ticket
- [/sdd:import-jira-ticket](#sddimport-jira-ticket) - Import from Jira
- [/sdd:review](#sddreview) - Critical review before decompose
- [/sdd:update](#sddupdate) - Update ticket based on review
- [/sdd:create-tasks](#sddcreate-tasks) - Generate tasks from plan

### Task Execution
- [/sdd:do-all-tasks](#sdddo-all-tasks) - Execute all tasks systematically
- [/sdd:do-task](#sdddo-task) - Complete single task

### Agent Management
- [/sdd:recommend-agents](#sddrecommend-agents) - Recommend specialized agents
- [/sdd:assign-agents](#sddassign-agents) - Assign agents to tasks

### Pull Request Management
- [/sdd:pr](#sddpr) - Create GitHub pull request

### Utility Commands
- [/sdd:tasks-status](#sddtasks-status) - Show ticket/task status
- [/sdd:archive](#sddarchive) - Archive completed ticket

---

## Setup & Configuration

### /sdd:setup

**Purpose**: Initialize or verify SDD environment and directory structure.

**When to Use**:
- First time using SDD plugin
- After plugin updates
- To verify environment is correctly configured

**Syntax**:
```
/sdd:setup [force]
```

**Parameters**:
- `force` (optional): Reinitialize even if already set up

**Behavior**:
1. Checks/creates SDD root directory structure
2. Verifies templates are accessible
3. Sets environment variables
4. Reports status

**Example**:
```bash
/sdd:setup
```

**Expected Output**:
```
SDD Environment Setup
✓ SDD_ROOT_DIR: /app/.sdd
✓ Directories created: epics/, tickets/, archive/
✓ Templates accessible
✓ Environment ready
```

**Common Errors**:

**Error**: "Permission denied creating directories"
- **Cause**: Insufficient permissions in target directory
- **Solution**: Check directory permissions or specify different SDD_ROOT_DIR

---

## Epic Management

### /sdd:start-epic

**Purpose**: Create a new epic for research and discovery work.

**When to Use**:
- Starting a large initiative requiring research
- When work scope is unclear and needs discovery
- When multiple tickets may result from research

**Syntax**:
```
/sdd:start-epic [JIRA_ID] [name]
```

**Parameters**:
- `JIRA_ID` (optional): Jira epic ID for traceability
- `name` (required): Descriptive name for the epic

**Behavior**:
1. Runs scaffold-epic.sh to create structure
2. Delegates to epic-planner agent (Sonnet)
3. Creates research templates
4. Sets up epic directory

**Prerequisites**:
- SDD environment initialized

**Example 1: Standard Epic**:
```bash
/sdd:start-epic authentication-redesign
```

**Example 2: Epic with Jira ID**:
```bash
/sdd:start-epic UIT-444 authentication-redesign
```

**Expected Output**:
```
Epic scaffolded: 2025-12-11_UIT-444_authentication-redesign

Created structure:
  epics/2025-12-11_UIT-444_authentication-redesign/
    ├── README.md
    ├── research/
    ├── analysis/
    └── tickets/

---
RECOMMENDED NEXT STEP: /sdd:plan-ticket {TICKET_ID} {name}
Research and analyze findings, then create tickets from epic discoveries
```

**Related Commands**:
- `/sdd:plan-ticket` - Create tickets from epic research

---

## Ticket Management

### /sdd:plan-ticket

**Purpose**: Initialize a new ticket with planning document templates.

**When to Use**:
- Starting a new piece of work (2-8 hour scope)
- Creating a ticket from epic research
- Beginning any tracked development task

**Syntax**:
```
/sdd:plan-ticket [TICKET_ID] [name]
```

**Parameters**:
- `TICKET_ID` (required): Unique identifier (e.g., DEMO, AUTH, UIT-9819)
- `name` (required): Descriptive name (will be slugified)

**Behavior**:
1. Runs scaffold-ticket.sh to create structure
2. Generates planning templates
3. Delegates to ticket-planner agent (Sonnet)
4. Creates README and planning documents

**Prerequisites**:
- SDD environment initialized

**Example**:
```bash
/sdd:plan-ticket AUTH user-authentication-oauth
```

**Expected Output**:
```
Ticket scaffolded: AUTH_user-authentication-oauth

Created structure:
  tickets/AUTH_user-authentication-oauth/
    ├── README.md
    ├── planning/
    │   ├── plan.md
    │   ├── architecture.md
    │   ├── quality-strategy.md
    │   └── analysis.md
    └── tasks/

---
RECOMMENDED NEXT STEP: /sdd:review AUTH
Complete planning documents (plan.md, architecture.md), then run review
```

**Common Errors**:

**Error**: "Ticket ID already exists"
- **Cause**: Directory with same TICKET_ID prefix exists
- **Solution**: Use unique TICKET_ID or archive existing ticket

**Related Commands**:
- `/sdd:import-jira-ticket` - Alternative: import from Jira
- `/sdd:review` - Next step after planning

---

### /sdd:import-jira-ticket

**Purpose**: Import a Jira ticket and create SDD planning documents from it.

**When to Use**:
- When work originates from a Jira ticket
- To maintain traceability with Jira
- To bootstrap planning from existing Jira details

**Syntax**:
```
/sdd:import-jira-ticket [JIRA_KEY or URL] [additional instructions]
```

**Parameters**:
- `JIRA_KEY` (required): Jira issue key (e.g., UIT-3670) or full URL
- `additional instructions` (optional): Extra context for planning

**Behavior**:
1. Fetches Jira ticket details via API
2. Extracts description, acceptance criteria, attachments
3. Creates ticket structure with Jira ID as TICKET_ID
4. Populates planning documents from Jira content
5. Delegates to ticket-planner for enhancement

**Prerequisites**:
- Jira MCP server configured with credentials
- Network access to Jira instance

**Example 1: Using Jira Key**:
```bash
/sdd:import-jira-ticket UIT-3670
```

**Example 2: Using Full URL**:
```bash
/sdd:import-jira-ticket https://company.atlassian.net/browse/UIT-3670
```

**Example 3: With Additional Instructions**:
```bash
/sdd:import-jira-ticket UIT-3670 Focus on performance optimization
```

**Expected Output**:
```
Importing from Jira: UIT-3670

Fetched:
- Title: Implement user profile caching
- Description: 1,234 chars
- Acceptance Criteria: 5 items
- Attachments: 2 files

Ticket scaffolded: UIT-3670_implement-user-profile-caching

Planning documents pre-populated from Jira content.

---
RECOMMENDED NEXT STEP: /sdd:review UIT-3670
Review and enhance auto-populated planning, then run ticket review
```

**Common Errors**:

**Error**: "Jira ticket not found"
- **Cause**: Invalid Jira key or no access
- **Solution**: Verify Jira key and MCP server credentials

**Error**: "MCP server not configured"
- **Cause**: Jira MCP server not set up
- **Solution**: Configure Jira MCP server with credentials

**Related Commands**:
- `/sdd:plan-ticket` - Alternative: manual ticket creation
- `/sdd:review` - Next step after planning

---

### /sdd:review

**Purpose**: Perform critical review of ticket planning before task decomposition.

**When to Use**:
- After completing planning documents
- Before running /sdd:create-tasks
- To validate ticket readiness

**Syntax**:
```
/sdd:review [TICKET_ID]
```

**Parameters**:
- `TICKET_ID` (required): The ticket to review

**Behavior**:
1. Delegates to ticket-reviewer agent (Sonnet)
2. Evaluates planning completeness
3. Checks for risks and gaps
4. Creates ticket-review.md with PASS/FAIL decision

**Prerequisites**:
- Ticket exists with planning documents
- Planning documents have substantial content

**Example**:
```bash
/sdd:review AUTH
```

**Expected Output (PASS)**:
```
TICKET REVIEW: AUTH

Planning Assessment:
✓ plan.md - Complete (245 words)
✓ architecture.md - Complete (189 words)
✓ quality-strategy.md - Complete (156 words)

Risk Assessment:
✓ No critical risks identified
⚠ Minor: Consider caching strategy

Decision: PASS - Ready for decomposition

---
RECOMMENDED NEXT STEP: /sdd:create-tasks AUTH
Ticket planning is complete and approved for task decomposition
```

**Expected Output (FAIL)**:
```
TICKET REVIEW: AUTH

Planning Assessment:
✓ plan.md - Complete (245 words)
✗ architecture.md - Insufficient (45 words)
✓ quality-strategy.md - Complete (156 words)

Issues Found:
1. Architecture document lacks detail
2. No integration points identified

Decision: FAIL - Address issues before decomposition

Action Required:
1. Expand architecture.md to >100 words
2. Document integration points
3. Re-run /sdd:review AUTH
```

**Related Commands**:
- `/sdd:update` - Fix issues found in review
- `/sdd:create-tasks` - Run after review passes

---

### /sdd:update

**Purpose**: Update ticket planning documents based on review findings.

**When to Use**:
- After /sdd:review identifies issues
- To systematically address review feedback
- Before re-running review

**Syntax**:
```
/sdd:update [TICKET_ID]
```

**Parameters**:
- `TICKET_ID` (required): The ticket to update

**Behavior**:
1. Reads ticket-review.md findings
2. Delegates to ticket-updater agent (Sonnet)
3. Updates planning documents to address issues
4. Reports changes made

**Prerequisites**:
- Ticket exists
- Review has been run (ticket-review.md exists)

**Example**:
```bash
/sdd:update AUTH
```

**Expected Output**:
```
Updating ticket AUTH based on review findings...

Issues Addressed:
✓ Expanded architecture.md (45 → 156 words)
✓ Added integration points section
✓ Clarified API design

---
RECOMMENDED NEXT STEP: /sdd:review AUTH
Re-run review to verify all issues have been addressed
```

**Related Commands**:
- `/sdd:review` - Run before and after update

---

### /sdd:create-tasks

**Purpose**: Generate executable tasks from ticket planning documents.

**When to Use**:
- After planning is complete and reviewed
- Before starting task execution
- When ready to break work into 2-8 hour tasks

**Syntax**:
```
/sdd:create-tasks [TICKET_ID]
```

**Parameters**:
- `TICKET_ID` (required): The ticket to decompose

**Behavior**:
1. **Validates planning** (BLOCKING):
   - plan.md exists and has >100 words
   - architecture.md exists and has >100 words
2. Parses planning documents
3. Delegates to task-creator agent (Sonnet)
4. Generates task files in tasks/ directory
5. Numbers tasks by phase (1xxx, 2xxx, 3xxx)

**Prerequisites**:
- Ticket exists with complete planning
- Planning documents have >100 words each

**Example**:
```bash
/sdd:create-tasks AUTH
```

**Expected Output**:
```
=== PRE-DECOMPOSE VALIDATION ===
✓ planning/plan.md exists (245 words)
✓ planning/architecture.md exists (189 words)

Generating tasks from plan...

Tasks created:
✓ AUTH.1001_setup-oauth-provider.md
✓ AUTH.1002_implement-token-handling.md
✓ AUTH.2001_create-login-flow.md
✓ AUTH.2002_add-session-management.md

4 tasks created in 2 phases

---
RECOMMENDED NEXT STEP: /sdd:do-all-tasks AUTH
Execute all tasks systematically through the full workflow
```

**Common Errors**:

**Error**: "❌ planning/plan.md has insufficient content (45 words, need 100+)"
- **Cause**: plan.md has less than 100 words
- **Solution**: Add more detail to plan.md

**Error**: "❌ planning/architecture.md - NOT FOUND"
- **Cause**: architecture.md doesn't exist
- **Solution**: Create architecture.md with >100 words

**Related Commands**:
- `/sdd:review` - Must pass before decompose
- `/sdd:do-all-tasks` - Run after decompose

**Notes**:
- Task numbering: Phase 1 = 1xxx, Phase 2 = 2xxx, etc.
- Existing tasks are not overwritten
- Tasks can be manually edited after generation

---

## Task Execution

### /sdd:do-all-tasks

**Purpose**: Execute all tasks in a ticket systematically.

**When to Use**:
- After tasks are created via /sdd:create-tasks
- To run through all tasks in sequence
- For automated task execution

**Syntax**:
```
/sdd:do-all-tasks [TICKET_ID]
```

**Parameters**:
- `TICKET_ID` (required): The ticket to execute

**Behavior**:
1. **Pre-execution validation** (BLOCKING):
   - Review document exists and passed
   - Tasks exist in tasks/ directory
   - Task naming follows convention
2. Identifies unverified tasks
3. For each task: runs /sdd:do-task workflow
4. Reports progress after each task

**Prerequisites**:
- Ticket has been decomposed
- Review has passed
- Tasks exist

**Example**:
```bash
/sdd:do-all-tasks AUTH
```

**Expected Output**:
```
=== PRE-EXECUTION CHECKLIST ===
✓ Review document exists
✓ Review status: Approved
✓ Tasks found: 4 task(s)
✓ Task naming: All files follow convention

=== EXECUTION SUMMARY ===
Ticket: AUTH_user-authentication-oauth
Tasks to execute: 4
Already verified: 0
Remaining: 4

Proceeding with execution...

[Executes AUTH.1001]
[Executes AUTH.1002]
...
```

**Common Errors**:

**Error**: "✗ Review document missing"
- **Cause**: Haven't run /sdd:review
- **Solution**: Run `/sdd:review TICKET_ID` first

**Error**: "✗ No tasks found"
- **Cause**: Haven't run /sdd:create-tasks
- **Solution**: Run `/sdd:create-tasks TICKET_ID` first

**Related Commands**:
- `/sdd:do-task` - Execute single task
- `/sdd:tasks-status` - Check progress

---

### /sdd:do-task

**Purpose**: Complete a single task through the full workflow (implement → test → verify → commit).

**When to Use**:
- Executing tasks one at a time
- When you need control over execution pace
- For tasks with complex requirements

**Syntax**:
```
/sdd:do-task [TASK_ID]
```

**Parameters**:
- `TASK_ID` (required): Task identifier (e.g., AUTH.1001)

**Behavior**:
1. Locates task file
2. **Checks dependencies** (BLOCKING):
   - Parses Dependencies section
   - Validates all prerequisites complete
3. Delegates to implementation agent
4. Runs unit-test-runner (Haiku)
5. Runs verify-task (Sonnet)
6. Runs commit-task (Haiku)

**Prerequisites**:
- Task file exists
- All task dependencies satisfied

**Example**:
```bash
/sdd:do-task AUTH.1001
```

**Expected Output**:
```
=== DEPENDENCY CHECK ===
✓ No task dependencies declared

=== IMPLEMENTATION ===
Delegating to implementation agent...
[Implementation work happens]

=== TESTING ===
Running unit-test-runner...
✓ All tests passing

=== VERIFICATION ===
Running verify-task...
✓ All acceptance criteria met

=== COMMIT ===
Running commit-task...
✓ Committed: feat(auth): AUTH.1001 setup oauth provider

TASK COMPLETE: AUTH.1001

---
RECOMMENDED NEXT STEP: /sdd:do-task AUTH.1002
Continue with next task in sequence (or use /sdd:do-all-tasks AUTH)
```

**Common Errors**:

**Error**: "❌ DEPENDENCY CHECK FAILED"
- **Cause**: Prerequisite tasks not complete
- **Solution**: Complete dependency tasks first (shown in error)

**Error**: "Task file not found"
- **Cause**: Invalid TASK_ID or task doesn't exist
- **Solution**: Run `/sdd:tasks-status TICKET_ID` to see valid task IDs

**Related Commands**:
- `/sdd:do-all-tasks` - Execute all tasks
- `/sdd:tasks-status` - Check which tasks exist

**Notes**:
- Workflow: implement → test → verify → commit
- Each phase must pass before proceeding
- Verification is mandatory

---

## Agent Management

### /sdd:recommend-agents

**Purpose**: Analyze ticket and recommend specialized agents for optimal execution.

**When to Use**:
- Before executing complex tickets
- When ticket requires specialized knowledge
- To optimize agent assignments

**Syntax**:
```
/sdd:recommend-agents [TICKET_ID] [additional instructions]
```

**Parameters**:
- `TICKET_ID` (required): The ticket to analyze
- `additional instructions` (optional): Context for recommendations

**Behavior**:
1. Reads ticket planning documents
2. Delegates to agent-recommender (Sonnet)
3. Identifies opportunities for specialized agents
4. Creates agent-recommendations.md

**Example**:
```bash
/sdd:recommend-agents AUTH
```

**Expected Output**:
```
Analyzing ticket AUTH for agent opportunities...

Recommended Agents:
1. oauth-specialist
   - Purpose: Handle OAuth protocol complexities
   - Tasks: AUTH.1001, AUTH.1002

2. security-reviewer
   - Purpose: Ensure security best practices
   - Tasks: All tasks (advisory)

Recommendation saved to: planning/agent-recommendations.md

---
RECOMMENDED NEXT STEP: /sdd:assign-agents AUTH
Create recommended agents, then assign them to ticket tasks
```

**Related Commands**:
- `/sdd:assign-agents` - Assign recommended agents

---

### /sdd:assign-agents

**Purpose**: Assign specialized agents to ticket phases and tasks.

**When to Use**:
- After creating recommended agents
- To customize agent assignments
- Before executing complex tickets

**Syntax**:
```
/sdd:assign-agents [TICKET_ID]
```

**Parameters**:
- `TICKET_ID` (required): The ticket to update

**Behavior**:
1. Reads agent-recommendations.md
2. Delegates to agent-assigner (Sonnet)
3. Updates task files with agent assignments
4. Reports changes

**Example**:
```bash
/sdd:assign-agents AUTH
```

**Expected Output**:
```
Assigning agents to ticket AUTH...

Assignments Made:
✓ AUTH.1001: oauth-specialist (primary)
✓ AUTH.1002: oauth-specialist (primary)
✓ AUTH.2001: sdd-implementation (primary)
✓ AUTH.2002: sdd-implementation (primary)

All tasks: security-reviewer (advisory)

Task files updated with agent assignments.
```

**Related Commands**:
- `/sdd:recommend-agents` - Get recommendations first

---

## Pull Request Management

### /sdd:pr

**Purpose**: Create a GitHub pull request for a completed ticket.

**When to Use**:
- After all tasks are verified and completed
- Ready to submit work for code review
- Before archiving a ticket

**Syntax**:
```
/sdd:pr [TICKET_ID] [BASE_BRANCH] [--draft]
```

**Arguments**:
- `TICKET_ID` (required) - The ticket to create a PR for
- `[BASE_BRANCH]` (optional) - Base branch for PR (defaults to main)
- `[--draft]` (optional) - Create draft PR instead of regular PR

**When to Use Draft PRs**:
- **Automated workflows**: Use `--draft` when creating PRs from automated task execution (e.g., Jira tickets via `/sdd:do-all-tasks`). This creates a draft PR that can be reviewed and converted to ready status after verification.
- **Manual workflows**: Omit `--draft` for manual invocation when you've already reviewed changes and are ready for immediate PR review.

**Behavior**:
1. Validates all tasks are verified
2. Extracts ticket summary and changes from planning docs
3. Generates PR title and description using template
4. Creates PR via GitHub CLI
5. Logs PR creation event
6. Reports PR URL and next steps

**Prerequisites**:
- GitHub CLI (gh) installed and authenticated
- All ticket tasks verified
- Not on main/master branch

**Example 1: Manual invocation - ready for review**:
```bash
/sdd:pr SDDUPD
```

**Example 2: Automated workflow - create draft for review**:
```bash
/sdd:pr UIT-9819 --draft
```

**Example 3: With custom base branch**:
```bash
/sdd:pr TOOLS main --draft
```

**Expected Output**:
```
=== PR Preview ===

Title: [AUTH] Implement user authentication OAuth

--- Body ---
## Summary
Implement OAuth-based user authentication system

## Changes
- Add OAuth provider configuration
- Implement token handling
- Create login flow
...
-------------

Create PR with this description? (y/n): y
✓ PR created successfully!

PR: https://github.com/org/repo/pull/123
Title: [AUTH] Implement user authentication OAuth
Ticket: AUTH

---
RECOMMENDED NEXT STEP: /sdd:archive AUTH
After PR is merged, archive the completed ticket
```

**Common Errors**:

**Error**: "ERROR: Cannot create PR - tasks not verified"
- **Cause**: Some tasks are not fully verified
- **Solution**: Run `/sdd:do-all-tasks TICKET_ID` to complete verification

**Error**: "ERROR: Not authenticated with GitHub"
- **Cause**: GitHub CLI not authenticated
- **Solution**: Run `gh auth login`

**Error**: "ERROR: Cannot create PR from main/master branch"
- **Cause**: Currently on main or master branch
- **Solution**: Switch to a feature branch first

**Related Commands**:
- `/sdd:do-all-tasks` - Complete and verify all tasks before PR
- `/sdd:tasks-status` - Check verification status
- `/sdd:archive` - Archive ticket after PR is merged

**Notes**:
- PR description is auto-generated from ticket planning docs
- For Jira tickets, adds Jira link if JIRA_BASE_URL is set
- Preview shown before creation for confirmation
- Draft PRs can be marked as ready for review later on GitHub

---

## Utility Commands

### /sdd:tasks-status

**Purpose**: Show status of tickets and tasks.

**When to Use**:
- To check progress on tickets
- To identify incomplete tasks
- Before archiving to verify completion

**Syntax**:
```
/sdd:tasks-status [TICKET_ID]
```

**Parameters**:
- `TICKET_ID` (optional): Specific ticket (omit for all tickets)

**Behavior**:
1. Runs task-status.sh script
2. Scans task files for checkbox status
3. Delegates to status-reporter (Haiku)
4. Formats and displays results

**Example 1: All Tickets**:
```bash
/sdd:tasks-status
```

**Example 2: Specific Ticket**:
```bash
/sdd:tasks-status AUTH
```

**Expected Output**:
```
TICKET STATUS: AUTH

Tasks: 4 total
✓ Completed: 2
◐ In Progress: 1
○ Pending: 1

Task Details:
✓ AUTH.1001: Setup OAuth provider [Verified]
✓ AUTH.1002: Implement token handling [Verified]
◐ AUTH.2001: Create login flow [In Progress]
○ AUTH.2002: Add session management [Pending]

Progress: 50% (2/4 verified)
```

**Related Commands**:
- `/sdd:do-all-tasks` - Continue execution
- `/sdd:archive` - Archive when complete

---

### /sdd:archive

**Purpose**: Archive completed tickets to archive directory.

**When to Use**:
- When all tasks are verified
- To clean up active tickets directory
- After ticket is fully complete

**Syntax**:
```
/sdd:archive [TICKET_ID]
```

**Parameters**:
- `TICKET_ID` (optional): Specific ticket (omit to review all)

**Behavior**:
1. Runs task-status.sh to identify candidates
2. **Validates completion** (BLOCKING):
   - ALL tasks must have Verified checkbox checked
   - No pending or in-progress tasks
3. Runs structure-validator (Haiku)
4. Moves ticket to archive/tickets/
5. Updates references
6. Logs archival event

**Prerequisites**:
- All tasks verified
- No incomplete work

**Example**:
```bash
/sdd:archive AUTH
```

**Expected Output**:
```
ARCHIVE REVIEW

Tickets Reviewed: 1

ARCHIVED:
✓ AUTH_user-authentication-oauth: All 4 tasks verified - Archived

References Updated: 0 files
Metrics logged to: logs/metrics.log
```

**Common Errors**:

**Error**: "✗ AUTH: 2/4 tasks verified - Incomplete"
- **Cause**: Not all tasks verified
- **Solution**: Complete and verify remaining tasks

**Related Commands**:
- `/sdd:tasks-status` - Check what's incomplete
- `/sdd:do-all-tasks` - Complete remaining tasks

**Notes**:
- Archived tickets move to archive/tickets/
- Git references updated automatically
- Event logged for audit trail

---

## Quick Reference Table

| Command | Purpose | Prerequisites |
|---------|---------|---------------|
| `/sdd:setup` | Initialize environment | None |
| `/sdd:start-epic` | Create research epic | setup |
| `/sdd:plan-ticket` | Create new ticket | setup |
| `/sdd:import-jira-ticket` | Import from Jira | setup, Jira MCP |
| `/sdd:review` | Review planning | ticket exists |
| `/sdd:update` | Fix review issues | review done |
| `/sdd:create-tasks` | Create tasks | review passed |
| `/sdd:do-all-tasks` | Run all tasks | tasks exist |
| `/sdd:do-task` | Run single task | task exists |
| `/sdd:recommend-agents` | Get agent suggestions | ticket exists |
| `/sdd:assign-agents` | Assign agents | recommendations exist |
| `/sdd:pr` | Create pull request | all verified, gh CLI |
| `/sdd:tasks-status` | Check progress | None |
| `/sdd:archive` | Archive completed | all verified |

---

## Workflow Summary

```
/sdd:setup                    → Initialize environment
/sdd:plan-ticket ID name      → Create ticket
[Complete planning docs]      → Fill plan.md, architecture.md
/sdd:review ID                → Review planning
/sdd:update ID                → Fix issues (if needed)
/sdd:create-tasks ID          → Generate tasks
/sdd:do-all-tasks ID          → Execute all tasks
/sdd:pr ID [--draft]          → Create pull request
/sdd:archive ID               → Archive when complete
```

---

**Document Version**: 1.1
**Applies to**: SDD Plugin v1.0.0+
