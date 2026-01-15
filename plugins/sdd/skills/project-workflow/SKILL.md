---
name: project-workflow
description: Orchestrates epics, tickets, and tasks for systematic software development. Use this skill when planning work, creating tickets, managing tasks, or executing development workflows. Includes scripts for scaffolding and status reporting, with Haiku agents for mechanical tasks and Sonnet agents for reasoning.
---

# Project Workflow Skill

## Overview

This skill manages the complete development workflow hierarchy:

```
Epic (research/discovery)
    └── Ticket (planning/execution container)
            └── Task (individual work item)
```

**Key Principles:**
1. **Scripts for mechanical tasks** - Scaffolding, inventory, validation
2. **Haiku for structured processing** - Status reporting, formatting, commits
3. **Sonnet for reasoning** - Planning, review, verification
4. **Strict delegation** - Orchestrator NEVER does work itself. This principle preserves context conservation by maximizing token efficiency (delegating work to fresh contexts instead of consuming orchestrator tokens), maintaining sharp attention focus (orchestrator coordinates rather than gets buried in implementation details), and extending session longevity (avoiding context exhaustion from doing work directly). For general-purpose implementation work, use the Task tool with `subagent_type: "general-purpose"` to spawn fresh subagent contexts. See [delegation-patterns.md](references/delegation-patterns.md) for detailed decision criteria on when and how to delegate.

## Workflow Hierarchy

### Epics
Higher-order discovery and research work that may spawn multiple tickets.

**Location:**
- Without Jira ID: `${SDD_ROOT_DIR}/epics/{DATE}_{name}/`
- With Jira ID: `${SDD_ROOT_DIR}/epics/{DATE}_{JIRA_ID}_{name}/`

**Examples:** `2025-12-22_api-redesign`, `2025-12-22_UIT-444_best-epic-name`

**When to use:** Exploring problem spaces, conducting research before knowing exact deliverables.

### Tickets
Planning and execution containers with defined scope and deliverables.

**Location:** `${SDD_ROOT_DIR}/tickets/{TICKET_ID}_{name}/`

**When to use:** Known deliverables, ready for planning and execution.

### Tasks
Individual work items with clear acceptance criteria and verification workflow.

**Location:** `${SDD_ROOT_DIR}/tickets/{TICKET_ID}_{name}/tasks/{TICKET_ID}.{NUMBER}_description.md`

**Workflow:** Implement → Test → Verify → Commit

## Quick Reference

### Create Epic
```bash
# Scaffold structure (without Jira ID)
bash scripts/scaffold-epic.sh "epic-name" "" "Vision statement"

# Scaffold structure (with Jira ID)
bash scripts/scaffold-epic.sh "epic-name" "UIT-444" "Vision statement"

# Then delegate to epic-planner agent for content
```

### Create Ticket
```bash
# Scaffold structure
bash scripts/scaffold-ticket.sh "TICKET_ID" "ticket-name"

# Then delegate to ticket-planner agent for planning docs
```

### Check Status
```bash
# Get ticket status as JSON
bash scripts/task-status.sh TICKET_ID

# Validate ticket structure
bash scripts/validate-structure.sh TICKET_ID
```

### Recommend and Assign Custom Agents
```bash
# After ticket planning, analyze for custom agent opportunities
/sdd:recommend-agents TICKET_ID

# Review recommendations, create agents you want

# Assign created agents to phases and tickets
/sdd:assign-agents TICKET_ID
```

### Execute Workflow
```
For each task:
1. Delegate to primary implementation agent (custom or general)
2. Delegate to unit-test-runner agent (Haiku)
3. Delegate to verify-task agent (Sonnet)
4. Delegate to commit-task agent (Haiku)
```

## Scripts

All scripts are in `scripts/` directory. Use these for mechanical tasks:

| Script | Purpose | Output |
|--------|---------|--------|
| `scaffold-epic.sh` | Create epic folder structure | Directory tree |
| `scaffold-ticket.sh` | Create ticket folder structure | Directory tree |
| `task-status.sh` | Scan ticket checkboxes | JSON status |
| `validate-structure.sh` | Verify ticket/task structure | Validation report |
| `ticket-summary.sh` | Generate ticket summary | Markdown summary |

### Script Usage Examples

```bash
# Create epic
bash scripts/scaffold-epic.sh "api-redesign" "Redesign the public API for v2"

# Create ticket
bash scripts/scaffold-ticket.sh "APIV2" "api-version-2"

# Get status of all tickets
bash scripts/task-status.sh APIV2

# Validate structure
bash scripts/validate-structure.sh APIV2

# Generate summary
bash scripts/ticket-summary.sh APIV2
```

## Agents

### Haiku Agents (Structured, Fast, Cheap)

Use Haiku agents for tasks that are:
- Procedural with clear steps
- Pattern-matching based
- Report generation
- No complex reasoning required

| Agent | Purpose |
|-------|---------|
| `status-reporter` | Parse script output, format status reports |
| `structure-validator` | Check file structure, report issues |
| `unit-test-runner` | Execute tests, report results with coverage |
| `commit-task` | Create commits after verification |

### Sonnet Agents (Reasoning, Analysis)

Use Sonnet agents for tasks that require:
- Complex decision making
- Multi-document synthesis
- Critical analysis
- Quality judgment

| Agent | Purpose |
|-------|---------|
| `epic-planner` | Research and plan epics |
| `ticket-planner` | Create comprehensive planning docs |
| `ticket-reviewer` | Critical review of tickets |
| `agent-recommender` | Analyze tickets to recommend custom specialized agents |
| `agent-assigner` | Assign created agents to phases and tickets |
| `task-creator` | Generate tasks from plans |
| `verify-task` | Verify acceptance criteria met |

## Delegation Patterns

### Pattern 1: Script → Haiku Agent

For mechanical tasks with formatting:

```
1. Run script to gather data (e.g., task-status.sh)
2. Pass output to Haiku agent for formatting
3. Haiku returns formatted report
```

**Example:** Status reporting
```
task-status.sh → JSON → status-reporter agent → Formatted markdown
```

### Pattern 2: Sonnet Agent → Script → Haiku Agent

For complex workflows:

```
1. Sonnet agent makes decisions (what to create)
2. Script does mechanical work (scaffolding)
3. Haiku agent formats/reports results
```

**Example:** Ticket creation
```
ticket-planner decides content → scaffold-ticket.sh creates files → status-reporter confirms
```

### Pattern 3: Sequential Agent Pipeline

For task execution:

```
1. Implementation agent (Sonnet) - Does the work
2. unit-test-runner (Haiku) - Runs tests, reports coverage
3. verify-task (Sonnet) - Verifies acceptance
4. commit-task (Haiku) - Creates commit
```

## Critical Rules

### DO:
- Always use scripts for scaffolding
- Delegate status gathering to scripts
- Use Haiku for formatting/reporting
- Use Sonnet for reasoning/verification
- Pass context between agents explicitly

### DON'T:
- Have orchestrator implement tasks directly
- Skip verification steps
- Use Sonnet for simple status checks
- Bypass the commit workflow
- Mix agent responsibilities

## Templates

Templates are in `templates/` directory:

```
templates/
├── epic/
│   ├── overview.md
│   ├── opportunity-map.md
│   ├── domain-model.md
│   └── decisions.md
├── ticket/
│   ├── README.md
│   ├── analysis.md
│   ├── architecture.md
│   ├── plan.md
│   ├── quality-strategy.md
│   ├── security-review.md
│   └── pr-description.md
└── task/
    └── task-template.md
```

Scripts use these templates when scaffolding.

## Status Indicators

### Task Status Checkboxes

```markdown
## Status
- [ ] **Task completed** - acceptance criteria met
- [ ] **Tests pass** - tests executed and passing
- [ ] **Verified** - by verify-task agent
```

### Ticket Readiness

| Status | Meaning |
|--------|---------|
| `Not Ready` | Critical issues blocking execution |
| `Needs Work` | Issues to address before starting |
| `Proceed with Caution` | Risks identified, can proceed |
| `Ready` | Well-defined, ready for execution |

## Integration with Commands

Commands in the `commands/` directory provide user-friendly interfaces:

| Command | Delegates To |
|---------|--------------|
| `/sdd:archive` | structure-validator + archive logic |
| `/sdd:assign-agents` | agent-assigner agent |
| `/sdd:create-tasks` | task-creator agent |
| `/sdd:do-all-tasks` | Sequential task execution |
| `/sdd:do-task` | Single task workflow |
| `/sdd:import-jira-ticket` | acli jira + scaffold-ticket.sh + ticket-planner |
| `/sdd:mark-ready` | Update .autogate.json with agent_ready: true |
| `/sdd:plan-ticket` | scaffold-ticket.sh + ticket-planner |
| `/sdd:pr` | Create GitHub Pull Request for completed ticket |
| `/sdd:recommend-agents` | agent-recommender agent |
| `/sdd:review` | ticket-reviewer agent |
| `/sdd:start-epic` | scaffold-epic.sh + epic-planner |
| `/sdd:tasks-status` | task-status.sh + status-reporter |
| `/sdd:unmark-ready` | Update .autogate.json with agent_ready: false |

### Autonomous Execution Commands

These commands control the agent-ready status for autonomous execution via the Ralph Loop Controller (SDDLOOP-3).

#### /sdd:mark-ready

**File:** [mark-ready.md](commands/mark-ready.md)
**Argument Hint:** TICKET_ID [--priority N]
**Description:** Mark a ticket as ready for autonomous agent execution. Creates or updates `.autogate.json` with `agent_ready: true`.

**Usage:**
- Basic: `/sdd:mark-ready SDDLOOP-2`
- With priority: `/sdd:mark-ready SDDLOOP-2 --priority 1`

**See:** [autogate-schema.md](references/autogate-schema.md) for field details.

#### /sdd:unmark-ready

**File:** [unmark-ready.md](commands/unmark-ready.md)
**Argument Hint:** TICKET_ID
**Description:** Remove agent-ready status from a ticket. Sets `agent_ready: false` in `.autogate.json`.

**Usage:**
- `/sdd:unmark-ready SDDLOOP-2`

**See:** [autogate-schema.md](references/autogate-schema.md) for field details.

## Complete Ticket Workflow

The full ticket lifecycle with optional agent customization:

```
1. Create Ticket
   /sdd:plan-ticket "Ticket description"
   → scaffold-ticket.sh creates structure
   → ticket-planner fills planning docs
   → May recommend agent analysis

   OR (for Jira integration):
   /sdd:import-jira-ticket UIT-3670
   → acli jira fetches ticket details
   → scaffold-ticket.sh creates structure
   → ticket-planner uses Jira description

2. Review Ticket (Optional but Recommended)
   /sdd:review TICKET_ID
   → ticket-reviewer critiques plan
   → Identifies risks and gaps

3. Recommend Agents (Optional, for complex tickets)
   /sdd:recommend-agents TICKET_ID
   → agent-recommender analyzes ticket
   → Creates agent-recommendations.md
   → Suggests agents only if genuinely valuable

4. Create Custom Agents (If recommended)
   Review agent-recommendations.md
   Create agents you want
   (Use agent creation commands)

5. Assign Agents (If custom agents created)
   /sdd:assign-agents TICKET_ID
   → agent-assigner updates plan.md and tickets
   → Creates agent-assignments.md

6. Create Tasks
   /sdd:create-tasks TICKET_ID
   → task-creator generates tasks from plan
   → Custom agents already assigned (if Step 5 done)

7. Execute Work
   /sdd:do-all-tasks TICKET_ID
   → Processes tasks sequentially
   → Uses custom or general agents as assigned

8. Create Pull Request (Optional)
   /sdd:pr TICKET_ID [BASE_BRANCH]
   → Validates all tasks are verified
   → Generates PR description from planning docs
   → Creates GitHub PR via gh CLI
   → Includes Jira link if JIRA_BASE_URL is set

9. Archive (When complete)
   /sdd:archive TICKET_ID
   → Moves to archive/
```

**When to use agent customization (Steps 3-5):**
- Complex specialized domains (migrations, caching, performance)
- High-risk areas where expertise prevents costly mistakes
- Repeated specialized patterns across phases
- Deep domain knowledge would improve quality

**When to skip agent customization:**
- Straightforward general programming
- Short tickets with few phases
- General Claude skills sufficient

## Workflow Diagrams

See [references/workflow-overview.md](references/workflow-overview.md) for detailed diagrams.

## Agent Responsibilities

See [references/agent-responsibilities.md](references/agent-responsibilities.md) for detailed agent descriptions.

## Configuration

### Jira Integration (Optional)

Set `JIRA_BASE_URL` to automatically include Jira links in PR descriptions:

```bash
export JIRA_BASE_URL=https://your-org.atlassian.net
```

This enables automatic Jira ticket linking for tickets imported via `/sdd:import-jira-ticket`.

### PR Command Examples

**Create PR for Jira-imported ticket:**
```bash
/sdd:pr UIT-9819
```

**Create PR for manual ticket:**
```bash
/sdd:pr FEATURE
```

**Create PR with custom base branch:**
```bash
/sdd:pr FEATURE develop
```

## Best Practices

### Efficiency
1. Use scripts for data gathering before spawning agents
2. Prefer Haiku when reasoning isn't needed
3. Batch status checks rather than per-task queries
4. Cache ticket context across task executions

### Quality
1. Never skip verification steps
2. Always run tests before verification
3. Use ticket-reviewer before ticket creation
4. Keep commits atomic (one task = one commit)

### Maintainability
1. Follow naming conventions strictly
2. Keep tasks at 2-8 hour scope
3. Document decisions in tickets
4. Archive completed tickets promptly
