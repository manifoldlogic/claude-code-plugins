# SDD Plugin (Spec Driven Development)

Enterprise workflow management for epics, tickets, and implementation tasks.

## Overview

This plugin provides a complete development workflow system:

```
Epic (research/discovery)
    └── Ticket (planning/execution)
            └── Task (individual work item)
```

## Key Features

- **Scripts for mechanical tasks** - Scaffolding, inventory, validation
- **Haiku agents for structured processing** - Status reports, test execution, commits
- **Sonnet agents for reasoning** - Planning, review, verification
- **Strict delegation** - Orchestrator coordinates, never does work itself

## Installation

```bash
# Add marketplace (if not already added)
/plugin marketplace add claude-code-plugins

# Install SDD plugin
/plugin install sdd@marketplace-name
```

After installation, restart Claude Code to activate the plugin.

## Commands

| Command | Description |
|---------|-------------|
| `/sdd:start-epic [JIRA_ID] [name]` | Create epic for research/discovery |
| `/sdd:plan-ticket [description]` | Create ticket with planning documents |
| `/sdd:import-jira-ticket [JIRA_KEY or URL]` | Import Jira ticket and create planning docs |
| `/sdd:review [TICKET_ID]` | Critical review before ticket creation |
| `/sdd:create-tasks [TICKET_ID]` | Generate tasks from plan |
| `/sdd:do-all-tasks [TICKET_ID]` | Execute all tasks systematically |
| `/sdd:do-task [TASK_ID]` | Complete single task workflow |
| `/sdd:recommend-agents [TICKET_ID]` | Recommend specialized agents for ticket |
| `/sdd:assign-agents [TICKET_ID]` | Assign agents to phases and tasks |
| `/sdd:update [TICKET_ID]` | Update ticket based on review findings |
| `/sdd:tasks-status [TICKET_ID]` | Check ticket/task status |
| `/sdd:archive [TICKET_ID]` | Archive completed projects |
| `/sdd:setup [force]` | Initialize SDD environment and verify structure |

> **Tip:** Most commands accept optional additional instructions after the primary argument to provide context or focus areas. For example: `/sdd:review TICKET_ID Focus on security concerns` or `/sdd:create-tasks TICKET_ID Create smaller tasks`. See individual command help for details.

## Agents

### Haiku Agents (Fast, Cheap)

| Agent | Purpose |
|-------|---------|
| `status-reporter` | Format status data into reports |
| `structure-validator` | Validate ticket structure |
| `unit-test-runner` | Execute tests and report results |
| `commit-task` | Create conventional commits |
| `workflow-logger` | Record workflow events for audit trail |

### Sonnet Agents (Reasoning)

| Agent | Purpose |
|-------|---------|
| `epic-planner` | Research and plan epics |
| `ticket-planner` | Create planning documents |
| `ticket-reviewer` | Critical ticket review |
| `ticket-updater` | Update ticket based on review findings |
| `task-creator` | Generate tasks from plans |
| `verify-task` | Verify acceptance criteria |
| `agent-recommender` | Recommend specialized agents |
| `agent-assigner` | Assign agents to phases and tickets |

## Skills

### project-workflow

The main skill providing orchestration guidance:

- Workflow diagrams
- Delegation patterns
- Agent responsibilities
- Templates for all document types

Location: `skills/project-workflow/SKILL.md`

## Scripts

Located in `skills/project-workflow/scripts/`:

| Script | Purpose |
|--------|---------|
| `scaffold-epic.sh` | Create epic structure |
| `scaffold-ticket.sh` | Create ticket structure |
| `task-status.sh` | Scan ticket checkboxes |
| `validate-structure.sh` | Validate ticket structure |
| `ticket-summary.sh` | Generate ticket summary |
| `collect-metrics.sh` | Collect and log workflow metrics |

## Workflow

### Creating a Ticket

```
1. /sdd:plan-ticket "description"
   └── Runs scaffold-ticket.sh
   └── Delegates to ticket-planner agent

2. /sdd:review TICKET_ID
   └── Delegates to ticket-reviewer agent
   └── Creates ticket-review.md

3. /sdd:create-tasks TICKET_ID
   └── Delegates to task-creator agent
   └── Creates tasks in tasks/

4. /sdd:do-all-tasks TICKET_ID
   └── For each task: /sdd:do-task TASK_ID
       └── Implementation agent
       └── unit-test-runner (Haiku)
       └── verify-task (Sonnet)
       └── commit-task (Haiku)

5. /sdd:archive TICKET_ID
   └── Validates all verified
   └── Moves to archive
```

### Ticket Execution Flow

```
implement (Sonnet) → test (Haiku) → verify (Sonnet) → commit (Haiku)
```

## Quick Start

### Create a New Ticket

```bash
# 1. Create ticket with planning docs
/sdd:plan-ticket Implement user authentication with OAuth

# 2. Review the ticket plan
/sdd:review AUTH

# 3. Generate tasks from plan
/sdd:create-tasks AUTH

# 4. Execute all tasks
/sdd:do-all-tasks AUTH

# 5. Archive when complete
/sdd:archive AUTH
```

### Using Jira IDs

You can use Jira IDs directly when your work corresponds to a Jira epic, story, or bug:

**For Epics:**
```bash
# Create epic with Jira epic ID
/sdd:start-epic UIT-444 best-epic-name
# Creates: 2025-12-22_UIT-444_best-epic-name/
```

**For Tickets (Import from Jira):**
```bash
# Import ticket using Jira key
/sdd:import-jira-ticket UIT-3670

# Import using full Jira URL (also works)
/sdd:import-jira-ticket https://company.atlassian.net/browse/UIT-3670

# Import with additional instructions (both formats work)
/sdd:import-jira-ticket UIT-3670 Focus on performance optimization
/sdd:import-jira-ticket https://company.atlassian.net/browse/UIT-3670 Focus on performance

# This fetches the Jira ticket details and creates planning docs
# Tasks will be named: UIT-3670.1001, UIT-3670.2001, etc.
```

**For Tickets (Manual with Jira ID):**
```bash
# 1. Create ticket using Jira ID manually
/sdd:plan-ticket UIT-9819 user-profile-update

# 2. Review and decompose
/sdd:review UIT-9819
/sdd:create-tasks UIT-9819

# 3. Execute tasks (tasks are named like UIT-9819.1001)
/sdd:do-task UIT-9819.1001
```

### Work on Individual Tickets

```bash
# Complete a single ticket
/sdd:do-task AUTH.1001

# The workflow will:
# - Delegate to implementation agent
# - Run tests with unit-test-runner (Haiku)
# - Verify with verify-task (Sonnet)
# - Commit with commit-task (Haiku)
```

### Check Status

```bash
# All tickets
/sdd:tasks-status

# Specific ticket
/sdd:tasks-status AUTH
```

## Directory Structure

```
plugins/sdd/
├── .claude-plugin/
│   └── plugin.json
├── agents/
│   ├── agent-assigner.md (Sonnet)
│   ├── agent-recommender.md (Sonnet)
│   ├── commit-task.md (Haiku)
│   ├── epic-planner.md (Sonnet)
│   ├── ticket-planner.md (Sonnet)
│   ├── ticket-reviewer.md (Sonnet)
│   ├── ticket-updater.md (Sonnet)
│   ├── status-reporter.md (Haiku)
│   ├── structure-validator.md (Haiku)
│   ├── task-creator.md (Sonnet)
│   ├── unit-test-runner.md (Haiku)
│   ├── verify-task.md (Sonnet)
│   └── workflow-logger.md (Haiku)
├── commands/
│   ├── archive.md
│   ├── assign-agents.md
│   ├── decompose.md
│   ├── execute.md
│   ├── implement.md
│   ├── epic.md
│   ├── ticket-init.md
│   ├── recommend-agents.md
│   ├── review.md
│   ├── setup.md
│   ├── tasks-status.md
│   └── update.md
├── hooks/
│   ├── block-dangerous-git.py
│   ├── setup-sdd-env.js
│   └── warn-sdd-refs.py
├── skills/
│   └── project-workflow/
│       ├── SKILL.md
│       ├── scripts/
│       │   ├── collect-metrics.sh
│       │   ├── ticket-summary.sh
│       │   ├── scaffold-epic.sh
│       │   ├── scaffold-ticket.sh
│       │   ├── task-status.sh
│       │   └── validate-structure.sh
│       ├── templates/
│       │   ├── epic/
│       │   ├── ticket/
│       │   └── task/
│       └── references/
│           ├── agent-responsibilities.md
│           ├── delegation-patterns.md
│           ├── epic-boundary-evaluation.md
│           ├── ticket-boundary-evaluation.md
│           ├── ticket-naming-guidelines.md
│           ├── spec-driven-development.md
│           └── workflow-overview.md
└── README.md
```

## Data Directory

Work items are stored in `${SDD_ROOT_DIR}` (defaults to `/app/.sdd`):

Note: The `SDD_ROOT_DIR` environment variable is automatically set by the SessionStart hook. If not set, defaults to `/app/.sdd`.

```
${SDD_ROOT_DIR}/
├── epics/      # Discovery/research work
├── tickets/         # Active projects
│   └── {TICKET_ID}_{name}/
│       ├── README.md
│       ├── planning/
│       │   ├── analysis.md
│       │   ├── architecture.md
│       │   ├── plan.md
│       │   ├── quality-strategy.md
│       │   └── security-review.md
│       └── tasks/
│           └── {TICKET_ID}.{NNNN}_{description}.md
├── archive/          # Completed work
│   ├── epics/
│   └── tickets/
├── reference/        # Documentation
├── research/         # Research notes
├── scratchpad/       # Temporary work
└── logs/             # Workflow and metrics logs
    ├── workflow.log  # Event log (pipe-delimited)
    └── metrics.log   # Metrics snapshots (JSON per line)
```

## Delegation Patterns

### Pattern 1: Script → Haiku

For mechanical tasks:
```
task-status.sh → JSON → status-reporter formats
```

### Pattern 2: Sonnet → Script → Haiku

For complex workflows:
```
ticket-planner decides → scaffold-ticket.sh creates → status-reporter confirms
```

### Pattern 3: Pipeline

For ticket execution:
```
implement (Sonnet) → test (Haiku) → verify (Sonnet) → commit (Haiku)
```

### Pattern 4: Conditional Delegation

```
Is the task...
├── Mechanical/Procedural? → Script only or Script + Haiku
├── Requires judgment? → Simple: Haiku, Quality: Sonnet
└── Requires reasoning? → Sonnet
```

## Enterprise Testing Standards

The plugin enforces enterprise-grade testing:

1. **Coverage thresholds must be met** - Never reduce existing coverage
2. **Critical paths require comprehensive testing** - Happy path, error cases, edge cases
3. **Negative testing is mandatory** - Test what happens when things go wrong
4. **Error paths are first-class** - Test failures as thoroughly as successes
5. **Thresholds are floors** - Meet or exceed, never reduce

## Best Practices

1. **Always use scripts for scaffolding** - Consistent structure
2. **Use Haiku for structured, procedural tasks** - Cost efficient
3. **Use Sonnet for reasoning and judgment** - Quality decisions
4. **Never skip verification** - Maintain quality
5. **Keep tickets to 2-8 hour scope** - Agent-appropriate size
6. **Archive completed projects promptly** - Keep workspace clean

## Troubleshooting

### Tickets not found
- Ensure ticket directory exists in your SDD root (check `echo ${SDD_ROOT_DIR:-/app/.sdd}/tickets/`)
- Check ticket naming follows convention: `TICKET_ID.NNNN_description.md`
- Verify TICKET_ID matches directory name prefix

### Verification failures
- Run tests with unit-test-runner first
- Check all acceptance criteria have evidence
- Ensure "Task completed" checkbox is checked

### Archive failures
- All tickets must have "Verified" checkbox checked
- Run `/sdd:tasks-status TICKET_ID` to identify incomplete tickets

## Version History

- **1.0.0** - Rebranded as SDD (Spec Driven Development) with enterprise focus
- **0.3.0** - Added configurable SDD_ROOT_DIR environment variable
- **0.2.0** - Added skill, scripts, Haiku agents, delegation patterns, epics
- **0.1.0** - Initial version with basic commands and agents

## Links

- [Repository](https://github.com/quickbase/claude-code-plugins)
