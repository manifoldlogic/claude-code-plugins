# Agent Responsibilities

This document defines clear responsibilities for each agent in the workflow.

## Haiku Agents

### status-reporter

**Purpose:** Format status data into readable reports

**Inputs:**
- JSON from task-status.sh
- JSON from validate-structure.sh
- JSON from ticket-summary.sh

**Outputs:**
- Formatted markdown tables
- Progress summaries
- Status indicators

**Does NOT:**
- Modify files
- Make decisions
- Analyze content

---

### structure-validator

**Purpose:** Validate ticket and task structure

**Inputs:**
- Ticket ID or path
- Validation criteria

**Outputs:**
- Validation report
- List of issues
- List of warnings

**Does NOT:**
- Fix issues
- Create files
- Modify structure

---

### unit-test-runner

**Purpose:** Execute tests and report results with coverage metrics

**Inputs:**
- Test scope (unit, integration, all)
- Ticket context

**Outputs:**
- Pass/fail counts
- Failed test details
- Execution time
- Coverage percentage
- Coverage threshold status (met/not met)

**Does NOT:**
- Fix failing tests
- Modify code
- Suggest solutions

---

### commit-task

**Purpose:** Create conventional commits for verified work

**Inputs:**
- Verified ticket reference
- Staged changes

**Outputs:**
- Git commit with proper message
- Commit hash
- Success/failure report

**Does NOT:**
- Modify code
- Skip verification check
- Make scope decisions

---

## Sonnet Agents

### epic-planner

**Purpose:** Research and plan epics

**Inputs:**
- Epic vision/description
- Scaffolded epic structure

**Outputs:**
- Filled overview.md
- Completed analysis documents
- Ticket decomposition
- Decision log

**Does NOT:**
- Create ticket-level planning
- Create tickets
- Implement code

---

### ticket-planner

**Purpose:** Create comprehensive ticket plans

**Inputs:**
- Scaffolded ticket structure
- Ticket description/context

**Outputs:**
- analysis.md (filled)
- architecture.md (filled)
- plan.md (filled)
- quality-strategy.md (filled)
- security-review.md (filled)

**Does NOT:**
- Create tickets
- Implement code
- Skip research

---

### ticket-reviewer

**Purpose:** Critical review of ticket plans

**Inputs:**
- Completed planning documents
- Codebase context

**Outputs:**
- ticket-review.md
- Issue list with severity
- Recommendations
- Readiness assessment

**Does NOT:**
- Create tickets
- Modify planning docs
- Implement fixes

---

### task-creator

**Purpose:** Generate tasks from plans

**Inputs:**
- Completed plan.md
- Phase information
- Agent assignments

**Outputs:**
- Task files in tasks/
- Task index
- Agent assignments

**Does NOT:**
- Implement tasks
- Modify planning docs
- Make architectural decisions

---

### verify-task

**Purpose:** Verify task completion

**Inputs:**
- Task file
- Git diff/status
- Acceptance criteria

**Outputs:**
- Verification report
- Pass/fail determination
- Evidence for each criterion

**Does NOT:**
- Fix issues
- Modify code
- Create commits

---

## Responsibility Matrix

| Task | Agent | Model | Can Write Files | Can Reason |
|------|-------|-------|-----------------|------------|
| Format reports | status-reporter | Haiku | No | No |
| Validate structure | structure-validator | Haiku | No | Limited |
| Run tests | unit-test-runner | Haiku | No | No |
| Create commits | commit-task | Haiku | Scope registry only | Limited |
| Plan epics | epic-planner | Sonnet | Yes | Yes |
| Plan tickets | ticket-planner | Sonnet | Yes | Yes |
| Review tickets | ticket-reviewer | Sonnet | Review doc only | Yes |
| Create tasks | task-creator | Sonnet | Yes | Yes |
| Verify work | verify-task | Sonnet | Task checkbox only | Yes |

## Handoff Protocol

When agents hand off work, they must:

1. **Complete their task fully** before handoff
2. **Report status** to orchestrator
3. **Provide context** for next agent
4. **Not overlap** with next agent's responsibilities

### Example Handoff Chain

```
ticket-planner completes planning
  ↓ Reports: "Planning complete, recommend /sdd:review"

ticket-reviewer reviews plan
  ↓ Reports: "Review complete, status: Ready, recommend /sdd:create-tasks"

task-creator creates tasks
  ↓ Reports: "12 tasks created, ready for /sdd:do-all-tasks"

/sdd:do-all-tasks coordinates execution
  ↓ For each task: implement → test → verify → commit
```

## Anti-Patterns

### Wrong Agent for Task

| Task | Wrong Agent | Right Agent |
|------|-------------|-------------|
| Format status | Sonnet agent | status-reporter (Haiku) |
| Complex planning | Haiku agent | ticket-planner (Sonnet) |
| Run tests | verify-task | unit-test-runner (Haiku) |
| Quality judgment | Haiku agent | verify-task (Sonnet) |

### Responsibility Overlap

- **Don't:** Have verify-task also create commits
- **Do:** verify-task marks verified, then commit-task creates commit

- **Don't:** Have ticket-planner also create tasks
- **Do:** ticket-planner creates plan, then task-creator creates tasks

### Skipping Agents

- **Don't:** Commit without verification
- **Don't:** Create tickets without review
- **Don't:** Verify without running tests
