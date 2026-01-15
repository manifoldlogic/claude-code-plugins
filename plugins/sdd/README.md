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
- **Workflow guidance** - Stop hook provides contextual next-step suggestions

## Workflow Guidance (Stop Hook)

### Overview

The SDD plugin includes a Stop hook that provides workflow guidance when Claude finishes responding. It analyzes your recent conversation to detect SDD workflow context and suggests next steps to keep you on track.

### How It Works

When Claude finishes responding, the hook:

1. **Reads recent transcript** - Analyzes the last 50 messages
2. **Detects SDD indicators** - Looks for `/sdd:` commands, ticket IDs, task IDs
3. **Determines workflow state** - Planning, implementation, or verification
4. **Provides contextual guidance** - Suggests logical next steps

### When Guidance Appears

Guidance appears when:

- You're mid-planning (e.g., after `/sdd:plan-ticket`)
- You're implementing a task (e.g., after `/sdd:do-task`)
- You're in verification phase
- Claude detects incomplete workflow steps

If no SDD context is detected, the hook exits silently.

### Understanding Guidance Messages

| Workflow State | Example Guidance |
|----------------|------------------|
| **Planning** | "Consider running `/sdd:review` or `/sdd:create-tasks`" |
| **Implementation** | "Consider running tests and committing your changes" |
| **Verification** | "Consider checking test results and creating a PR" |

### Disabling the Hook

To temporarily disable workflow guidance:

```bash
export SDD_DISABLE_STOP_HOOK=1
```

Add to your `.bashrc` or `.zshrc` to disable permanently.

### Troubleshooting

| Issue | Solution |
|-------|----------|
| **False positives** | Hook detected SDD context incorrectly - disable hook or ignore guidance |
| **Performance issues** | Check transcript size - hook is optimized for < 1 second execution |
| **Unwanted guidance** | Set `SDD_DISABLE_STOP_HOOK=1` environment variable |

### Work Gates

Work gates enhance the workflow guidance Stop hook with control over autonomous work progression. Gates work TOGETHER with workflow guidance - they can pause work for review while preserving all existing guidance features (planning phase tracking, review enforcement, contextual suggestions).

**When to use gates:**
- Pause autonomous work on specific tickets until you're ready
- Stop after completing specific phases for manual review
- Control work prioritization alongside workflow guidance

#### Configuration

Gates are configured using `.autogate.json` files placed in work item directories:

- `tickets/{TICKET_ID}_{name}/.autogate.json` - Gate for a specific ticket
- `epics/{DATE}_{name}/.autogate.json` - Gate for a specific epic

#### Schema

```json
{
  "ready": boolean,
  "stop_at_phase": integer | null
}
```

**Fields:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `ready` | boolean | `true` | Whether autonomous work can proceed on this item |
| `stop_at_phase` | integer or null | `null` | Stop after completing this phase number (e.g., 1, 2, 3) |

#### Examples

**Completely gate a ticket (no autonomous work):**
```json
{"ready": false}
```

**Allow work but stop after Phase 1 for review:**
```json
{"ready": true, "stop_at_phase": 1}
```

**Fully ready (same as no file):**
```json
{"ready": true}
```

#### Integration with Workflow Guidance

Gates work alongside workflow guidance in the same Stop hook:

1. **Gate blocks (ready=false):** Hook exits early with gate message, workflow guidance not shown
2. **Gate allows (ready=true):** Work proceeds, workflow guidance provided as normal
3. **No gate configured:** Workflow guidance works exactly as before gates were added

**When gate triggers:**
- Hook exits with code 2 (block stop) BEFORE showing workflow guidance
- Claude receives clear message about why work is gated
- Message provides guidance on how to proceed

**When gate allows or no gate:**
- Hook continues to workflow guidance logic
- Planning phase suggestions appear normally
- Review enforcement works as expected
- Contextual next-step guidance provided

**Fail-safe behavior (errors allow work to continue):**
- Invalid JSON in `.autogate.json` - Treated as "ready", workflow guidance continues
- Missing transcript - Treated as no active work, workflow guidance continues
- Any gate exception - Workflow guidance proceeds normally (fail-safe)

#### Override

Bypass all gate checks temporarily:

```bash
export AUTOGATE_BYPASS=true
```

When set, all gates are ignored and work can proceed normally.

#### Work Gates Troubleshooting

| Issue | Solution |
|-------|----------|
| **Gate not blocking when expected** | Verify `.autogate.json` is in correct location (ticket/epic root directory) |
| **Invalid JSON** | Check JSON syntax is valid - use `python3 -m json.tool < .autogate.json` |
| **Gate for wrong ticket** | Confirm active work matches ticket with gate |
| **Hook blocking unexpectedly** | Check for `.autogate.json` in current work item directory |
| **Need to override temporarily** | Use `AUTOGATE_BYPASS=true` environment variable |

**Behavior when nothing is ready:**
If all tickets have gates blocking work (`ready: false`), the hook exits cleanly with success (exit code 0), allowing Claude to complete without error.

### Reporting Issues

Found a bug or have suggestions? [File an issue](https://github.com/manifoldlogic/claude-code-plugins/issues) with:

- Steps to reproduce
- Expected vs actual behavior
- Relevant transcript context (if possible)

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
| `master-status-board.sh` | Multi-repo status aggregation with recommended actions for autonomous loops |
| `sdd-loop.sh` | Autonomous loop controller for batch task execution |

## Loop Controller

The SDD Loop Controller ("Ralph Wiggum Loop") provides autonomous task execution across multiple repositories. It continuously polls for work, executes tasks via Claude Code, and respects safety limits and phase boundaries.

### Quick Start

```bash
# Basic usage - run against default workspace
./sdd-loop.sh /workspace/repos/

# Preview what would happen without executing
./sdd-loop.sh --dry-run /workspace/repos/

# Limit iterations for testing
./sdd-loop.sh --max-iterations 10 /workspace/repos/
```

### Key Features

- **Safety limits** - Configurable max iterations and consecutive error limits
- **Phase boundaries** - Stop at specific phases for manual review via `.autogate.json`
- **Dry-run mode** - Preview actions without executing Claude Code
- **Cross-repo support** - Processes tasks across multiple repositories
- **Signal handling** - Graceful shutdown on Ctrl+C or SIGTERM

### Configuration

```bash
# Via command-line options
./sdd-loop.sh --max-iterations 50 --max-errors 3 --timeout 3600 /workspace/repos/

# Via environment variables
export SDD_LOOP_MAX_ITERATIONS=100
export SDD_LOOP_TIMEOUT=7200
./sdd-loop.sh /workspace/repos/
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success - all work completed |
| 1 | Error - task failure or limit reached |
| 2 | Usage error - invalid arguments |
| 130 | Interrupted by SIGINT (Ctrl+C) |
| 143 | Terminated by SIGTERM |

### Phase Boundary Control

Stop the loop after completing specific phases:

```bash
# Set phase boundary in ticket directory
cd /path/to/_SDD/tickets/TICKET_name/
echo '{"ready": true, "agent_ready": true, "stop_at_phase": 1}' > .autogate.json

# Run loop - will stop after Phase 1 tasks complete
./sdd-loop.sh /workspace/repos/
```

### Documentation

- [sdd-loop-examples.md](skills/project-workflow/scripts/sdd-loop-examples.md) - Comprehensive usage examples
- [sdd-loop.sh](skills/project-workflow/scripts/sdd-loop.sh) - Full script with `--help` documentation

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
│   ├── code-review.md
│   ├── create-tasks.md
│   ├── do-all-tasks.md
│   ├── do-task.md
│   ├── epics-status.md
│   ├── extend.md
│   ├── import-jira-ticket.md
│   ├── plan-ticket.md
│   ├── pr-comments.md
│   ├── pr.md
│   ├── recommend-agents.md
│   ├── review.md
│   ├── setup.md
│   ├── start-epic.md
│   ├── status.md
│   ├── tasks-status.md
│   ├── tickets-status.md
│   └── update.md
├── hooks/
│   ├── block-dangerous-git.py
│   ├── setup-sdd-env.js
│   ├── warn-sdd-refs.py
│   └── workflow-guidance.py
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

- [Repository](https://github.com/manifoldlogic/claude-code-plugins)
