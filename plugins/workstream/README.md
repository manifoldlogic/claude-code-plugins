# Workstream Plugin

Work lifecycle management for initiatives, projects, and tickets.

## Overview

This plugin provides a complete development workflow system:

```
Initiative (research/discovery)
    └── Project (planning/execution)
            └── Ticket (individual work item)
```

## Key Features

- **Scripts for mechanical tasks** - Scaffolding, inventory, validation
- **Haiku agents for structured processing** - Status reports, test execution, commits
- **Sonnet agents for reasoning** - Planning, review, verification
- **Strict delegation** - Orchestrator coordinates, never does work itself

## Installation

```bash
# Add marketplace (if not already added)
/plugin marketplace add /workspace/.crewchief/claude-code-plugins

# Install workstream plugin
/plugin install workstream@crewchief
```

After installation, restart Claude Code to activate the plugin.

## Commands

| Command | Description |
|---------|-------------|
| `/initiative-create [name]` | Create initiative for research/discovery |
| `/project-create [description]` | Create project with planning documents |
| `/project-review [SLUG]` | Critical review before ticket creation |
| `/project-tickets [SLUG]` | Generate tickets from plan |
| `/project-work [SLUG]` | Execute all tickets systematically |
| `/ticket [TICKET_ID]` | Complete single ticket workflow |
| `/status [SLUG]` | Check project/ticket status |
| `/archive [SLUG]` | Archive completed projects |

## Agents

### Haiku Agents (Fast, Cheap)

| Agent | Purpose |
|-------|---------|
| `status-reporter` | Format status data into reports |
| `structure-validator` | Validate project structure |
| `unit-test-runner` | Execute tests and report results |
| `commit-ticket` | Create conventional commits |

### Sonnet Agents (Reasoning)

| Agent | Purpose |
|-------|---------|
| `initiative-planner` | Research and plan initiatives |
| `project-planner` | Create planning documents |
| `project-reviewer` | Critical project review |
| `ticket-creator` | Generate tickets from plans |
| `verify-ticket` | Verify acceptance criteria |

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
| `scaffold-initiative.sh` | Create initiative structure |
| `scaffold-project.sh` | Create project structure |
| `ticket-status.sh` | Scan ticket checkboxes |
| `validate-structure.sh` | Validate project structure |
| `project-summary.sh` | Generate project summary |

## Workflow

### Creating a Project

```
1. /project-create "description"
   └── Runs scaffold-project.sh
   └── Delegates to project-planner agent

2. /project-review SLUG
   └── Delegates to project-reviewer agent
   └── Creates project-review.md

3. /project-tickets SLUG
   └── Delegates to ticket-creator agent
   └── Creates tickets in tickets/

4. /project-work SLUG
   └── For each ticket: /ticket TICKET_ID
       └── Implementation agent
       └── test-runner (Haiku)
       └── verify-ticket (Sonnet)
       └── commit-ticket (Haiku)

5. /archive SLUG
   └── Validates all verified
   └── Moves to archive
```

### Ticket Execution Flow

```
implement (Sonnet) → test (Haiku) → verify (Sonnet) → commit (Haiku)
```

## Quick Start

### Create a New Project

```bash
# 1. Create project with planning docs
/project-create Implement user authentication with OAuth

# 2. Review the project plan
/project-review AUTH

# 3. Generate tickets from plan
/project-tickets AUTH

# 4. Execute all tickets
/project-work AUTH

# 5. Archive when complete
/archive AUTH
```

### Work on Individual Tickets

```bash
# Complete a single ticket
/ticket AUTH-1001

# The workflow will:
# - Delegate to implementation agent
# - Run tests with test-runner (Haiku)
# - Verify with verify-ticket (Sonnet)
# - Commit with commit-ticket (Haiku)
```

### Check Status

```bash
# All projects
/status

# Specific project
/status AUTH
```

## Directory Structure

```
plugins/workstream/
├── .claude-plugin/
│   └── plugin.json
├── agents/
│   ├── status-reporter.md (Haiku)
│   ├── structure-validator.md (Haiku)
│   ├── unit-test-runner.md (Haiku)
│   ├── commit-ticket.md (Haiku)
│   ├── initiative-planner.md (Sonnet)
│   ├── project-planner.md (Sonnet)
│   ├── project-reviewer.md (Sonnet)
│   ├── ticket-creator.md (Sonnet)
│   └── verify-ticket.md (Sonnet)
├── commands/
│   ├── initiative-create.md
│   ├── project-create.md
│   ├── project-review.md
│   ├── project-tickets.md
│   ├── project-work.md
│   ├── ticket.md
│   ├── status.md
│   └── archive.md
├── skills/
│   └── project-workflow/
│       ├── SKILL.md
│       ├── scripts/
│       │   ├── scaffold-initiative.sh
│       │   ├── scaffold-project.sh
│       │   ├── ticket-status.sh
│       │   ├── validate-structure.sh
│       │   └── project-summary.sh
│       ├── templates/
│       │   ├── initiative/
│       │   ├── project/
│       │   └── ticket/
│       └── references/
│           ├── workflow-overview.md
│           ├── agent-responsibilities.md
│           └── delegation-patterns.md
└── README.md
```

## Data Directory

Work items are stored in `.crewchief/`:

```
.crewchief/
├── initiatives/      # Discovery/research work
├── projects/         # Active projects
│   └── {SLUG}_{name}/
│       ├── README.md
│       ├── planning/
│       │   ├── analysis.md
│       │   ├── architecture.md
│       │   ├── plan.md
│       │   ├── quality-strategy.md
│       │   └── security-review.md
│       └── tickets/
│           └── {SLUG}-{NNNN}_{description}.md
├── archive/          # Completed work
│   ├── initiatives/
│   └── projects/
├── reference/        # Documentation
├── research/         # Research notes
└── scratchpad/       # Temporary work
```

## Delegation Patterns

### Pattern 1: Script → Haiku

For mechanical tasks:
```
ticket-status.sh → JSON → status-reporter formats
```

### Pattern 2: Sonnet → Script → Haiku

For complex workflows:
```
project-planner decides → scaffold-project.sh creates → status-reporter confirms
```

### Pattern 3: Pipeline

For ticket execution:
```
implement (Sonnet) → test (Haiku) → verify (Sonnet) → commit (Haiku)
```

## Best Practices

1. **Always use scripts for scaffolding** - Consistent structure
2. **Use Haiku for structured, procedural tasks** - Cost efficient
3. **Use Sonnet for reasoning and judgment** - Quality decisions
4. **Never skip verification** - Maintain quality
5. **Keep tickets to 2-8 hour scope** - Agent-appropriate size
6. **Archive completed projects promptly** - Keep workspace clean

## Troubleshooting

### Tickets not found
- Ensure project directory exists in `.crewchief/projects/`
- Check ticket naming follows convention: `SLUG-NNNN_description.md`
- Verify PROJECT_SLUG matches directory name prefix

### Verification failures
- Run tests with test-runner first
- Check all acceptance criteria have evidence
- Ensure "Task completed" checkbox is checked

### Archive failures
- All tickets must have "Verified" checkbox checked
- Run `/status SLUG` to identify incomplete tickets

## Version History

- **0.3.0** - Renamed to workstream, data directory to `.crewchief/`
- **0.2.0** - Added skill, scripts, Haiku agents, delegation patterns, initiatives
- **0.1.0** - Initial version with basic commands and agents

## Links

- [Repository](https://github.com/manifoldlogic/claude-code-plugins)
- [CrewChief Directory](/.crewchief/README.md)
