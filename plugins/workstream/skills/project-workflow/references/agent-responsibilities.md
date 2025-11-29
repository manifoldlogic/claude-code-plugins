# Agent Responsibilities

This document defines clear responsibilities for each agent in the workflow.

## Haiku Agents

### status-reporter

**Purpose:** Format status data into readable reports

**Inputs:**
- JSON from ticket-status.sh
- JSON from validate-structure.sh
- JSON from project-summary.sh

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

**Purpose:** Validate project and ticket structure

**Inputs:**
- Project slug or path
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

### test-runner (unit-test-runner)

**Purpose:** Execute tests and report results

**Inputs:**
- Test scope (unit, integration, all)
- Project context

**Outputs:**
- Pass/fail counts
- Failed test details
- Execution time

**Does NOT:**
- Fix failing tests
- Modify code
- Suggest solutions

---

### commit-ticket

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

### initiative-planner

**Purpose:** Research and plan initiatives

**Inputs:**
- Initiative vision/description
- Scaffolded initiative structure

**Outputs:**
- Filled overview.md
- Completed analysis documents
- Project decomposition
- Decision log

**Does NOT:**
- Create project-level planning
- Create tickets
- Implement code

---

### project-planner

**Purpose:** Create comprehensive project plans

**Inputs:**
- Scaffolded project structure
- Project description/context

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

### project-reviewer

**Purpose:** Critical review of project plans

**Inputs:**
- Completed planning documents
- Codebase context

**Outputs:**
- project-review.md
- Issue list with severity
- Recommendations
- Readiness assessment

**Does NOT:**
- Create tickets
- Modify planning docs
- Implement fixes

---

### ticket-creator

**Purpose:** Generate tickets from plans

**Inputs:**
- Completed plan.md
- Phase information
- Agent assignments

**Outputs:**
- Ticket files in tickets/
- Ticket index
- Agent assignments

**Does NOT:**
- Implement tickets
- Modify planning docs
- Make architectural decisions

---

### verify-ticket

**Purpose:** Verify ticket completion

**Inputs:**
- Ticket file
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
| Run tests | test-runner | Haiku | No | No |
| Create commits | commit-ticket | Haiku | Scope registry only | Limited |
| Plan initiatives | initiative-planner | Sonnet | Yes | Yes |
| Plan projects | project-planner | Sonnet | Yes | Yes |
| Review projects | project-reviewer | Sonnet | Review doc only | Yes |
| Create tickets | ticket-creator | Sonnet | Yes | Yes |
| Verify work | verify-ticket | Sonnet | Ticket checkbox only | Yes |

## Handoff Protocol

When agents hand off work, they must:

1. **Complete their task fully** before handoff
2. **Report status** to orchestrator
3. **Provide context** for next agent
4. **Not overlap** with next agent's responsibilities

### Example Handoff Chain

```
project-planner completes planning
  ↓ Reports: "Planning complete, recommend /project-review"

project-reviewer reviews plan
  ↓ Reports: "Review complete, status: Ready, recommend /project-tickets"

ticket-creator creates tickets
  ↓ Reports: "12 tickets created, ready for /project-work"

/project-work coordinates execution
  ↓ For each ticket: implement → test → verify → commit
```

## Anti-Patterns

### Wrong Agent for Task

| Task | Wrong Agent | Right Agent |
|------|-------------|-------------|
| Format status | Sonnet agent | status-reporter (Haiku) |
| Complex planning | Haiku agent | project-planner (Sonnet) |
| Run tests | verify-ticket | test-runner (Haiku) |
| Quality judgment | Haiku agent | verify-ticket (Sonnet) |

### Responsibility Overlap

- **Don't:** Have verify-ticket also create commits
- **Do:** verify-ticket marks verified, then commit-ticket creates commit

- **Don't:** Have project-planner also create tickets
- **Do:** project-planner creates plan, then ticket-creator creates tickets

### Skipping Agents

- **Don't:** Commit without verification
- **Don't:** Create tickets without review
- **Don't:** Verify without running tests
