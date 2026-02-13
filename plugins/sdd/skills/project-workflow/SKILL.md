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

## Prerequisites

- **jq 1.5+**: JSON processor used by scaffolding, triage, and validation scripts. Install with your package manager:
  - `apt-get install jq` (Debian/Ubuntu)
  - `brew install jq` (macOS)
  - `yum install jq` (RHEL/CentOS)
  - `apk add jq` (Alpine)

  Scripts validate the jq version on startup and exit with a clear error if the requirement is not met.

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
# Triage documents based on description and overrides
bash scripts/triage-documents.sh "ticket description" [+doc -doc]

# Scaffold structure (with manifest for selective document creation)
bash scripts/scaffold-ticket.sh --manifest /path/to/manifest.json "TICKET_ID" "ticket-name"

# Scaffold structure (legacy: all six default documents)
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
| `triage-documents.sh` | Select documents based on description + overrides | JSON manifest |
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

Templates are in `templates/` directory. The document registry (`templates/document-registry.json`) defines all document types, their tiers, and trigger keywords.

```
templates/
├── document-registry.json    # Authoritative document definitions
├── epic/
│   ├── overview.md
│   ├── opportunity-map.md
│   ├── domain-model.md
│   └── decisions.md
├── ticket/
│   ├── README.md
│   ├── analysis.md           # Core: Problem analysis
│   ├── architecture.md       # Core: Solution design
│   ├── plan.md               # Core: Execution plan
│   ├── prd.md                # Standard: Product requirements
│   ├── quality-strategy.md   # Standard: Testing approach
│   ├── security-review.md    # Standard: Security assessment
│   ├── observability.md      # Conditional: Logging, metrics, alerting
│   ├── migration-plan.md     # Conditional: Schema changes, rollback
│   ├── accessibility.md      # Conditional: WCAG, keyboard nav
│   ├── api-contract.md       # Conditional: API schemas, versioning
│   ├── runbook.md            # Conditional: Deployment, incident response
│   ├── dependency-audit.md   # Conditional: Package licenses, security
│   └── pr-description.md
└── task/
    └── task-template.md
```

Scripts use these templates when scaffolding. The triage system determines which ticket templates to use for each ticket (see Document Selection below).

## Document Selection

The triage system selects which planning documents to generate for each ticket. This replaces the previous fixed six-document approach with a context-aware selection algorithm.

### Script Flags

All workflow scripts (`triage-documents.sh`, `scaffold-ticket.sh`, `validate-structure.sh`) support the following common flags:

| Flag | Environment Variable | Description |
|------|---------------------|-------------|
| `--no-color` | `NO_COLOR=1` | Disable ANSI color codes in output |
| `--debug` | `DEBUG=1` | Enable shell command tracing (`set -x`) |
| `--verbose` | `VERBOSE=1` | Enable human-readable progress output to stderr |

The `--verbose` flag provides mid-level visibility between silent mode (default) and `--debug` (full shell tracing). Verbose output goes to stderr, preserving clean JSON on stdout.

**Example verbose output from `triage-documents.sh`:**
```
[VERBOSE] Checking jq availability... OK
[VERBOSE] Description validated (42 bytes)
[VERBOSE] Loaded document registry: 12 document types
[VERBOSE] Matched observability: keywords 'api', 'backend'
[VERBOSE] Matched api-contract: keywords 'api'
[VERBOSE] Override: +accessibility (force include)
[VERBOSE] Override: -runbook (force exclude)
[VERBOSE] Generating manifest: 9 documents selected
```

Flags can be combined: `--verbose --debug` shows both human-readable progress and shell command tracing.

### Triage Algorithm

The `triage-documents.sh` script runs during `/sdd:plan-ticket` (Step 1.5) and follows this algorithm:

1. **Load the document registry** from `templates/document-registry.json`.
2. **Always include core documents**: analysis, architecture, plan.
3. **Include standard documents by default**: prd, quality-strategy, security-review.
4. **Evaluate conditional documents**: For each conditional document, scan the ticket description for its trigger keywords (case-insensitive substring matching). Include the document if any keyword matches.
5. **Apply overrides**: Process `+doc-name` (force include) and `-doc-name` (force exclude) flags from the command arguments. Core documents cannot be excluded.
6. **Output a manifest**: Write a JSON manifest listing each document with its action (generate or skip) and the reason for that decision.

### Manifest File

The triage produces a manifest saved to the ticket's `planning/.triage-manifest.json`. This file records exactly which documents were selected and why:

```json
{
  "ticket_id": "AUTH",
  "description": "Implement user authentication with OAuth",
  "documents": [
    {"id": "analysis", "filename": "analysis.md", "tier": "core", "action": "generate", "reason": "Core document (always generated)"},
    {"id": "api-contract", "filename": "api-contract.md", "tier": "conditional", "action": "generate", "reason": "Keyword match: api"},
    {"id": "runbook", "filename": "runbook.md", "tier": "conditional", "action": "skip", "reason": "No trigger keywords matched"}
  ],
  "overrides": []
}
```

### Decision Factors

| Factor | Effect |
|--------|--------|
| Ticket description keywords | Trigger conditional document inclusion |
| `+doc-name` override | Force-include a document regardless of keywords |
| `-doc-name` override | Force-exclude a standard or conditional document |
| Document tier (core) | Always included, cannot be overridden |
| Document tier (standard) | Included by default, can be excluded with `-` |
| Document tier (conditional) | Included only on keyword match or `+` override |

### Fallback Behavior

If the triage script fails or is unavailable, the workflow falls back to legacy behavior: the original six documents (analysis, architecture, plan, prd, quality-strategy, security-review) are generated without a manifest. This ensures backward compatibility.

## Override Mechanism

Override flags let developers adjust document selection without modifying the registry or triage logic.

### Syntax

```
+doc-name    Force include a document
-doc-name    Force exclude a document
```

Override flags can appear anywhere in the `/sdd:plan-ticket` arguments. They are extracted before the description is parsed.

### Examples

```bash
# Backend ticket, but needs accessibility review
/sdd:plan-ticket "payment processing backend" +accessibility

# API ticket, no new infrastructure needed
/sdd:plan-ticket "REST API v2 endpoints" -runbook

# Multiple overrides with planning context
/sdd:plan-ticket "data pipeline service" +observability -dependency-audit Focus on reliability
```

### Validation

- Override names are validated against the document registry. Unknown names produce a warning but do not block the workflow.
- Core documents (`analysis`, `architecture`, `plan`) cannot be excluded. Attempting `-analysis` has no effect.

## Extensibility

New document types can be added without modifying the triage script or any hook code.

### Adding a New Document Type

1. **Create the template**: Add a new file at `templates/ticket/{new-document}.md` with the template structure.

2. **Register in the document registry**: Add an entry to `templates/document-registry.json` in the `documents` object:
   ```json
   "new-document": {
     "filename": "new-document.md",
     "title": "Human-Readable Title",
     "tier": "conditional",
     "template": "new-document.md",
     "create_tasks_validation": "none",
     "triggers": {
       "keywords": ["keyword1", "keyword2"],
       "description": "Short description of when this document should be generated"
     }
   }
   ```

3. **Add to the tier list**: In the `tiers` section of the same file, add the document ID to the appropriate tier's `documents` array.

The triage script reads the registry dynamically at runtime, so new document types are immediately available. Developers can use `+new-document` or `-new-document` overrides as soon as the registry entry exists.

### Tier Selection Guide

| Tier | Use When |
|------|----------|
| `core` | Document should be generated for every ticket without exception |
| `standard` | Document should be generated by default but can be N/A-signed when irrelevant |
| `conditional` | Document is only relevant for certain ticket types, identified by keywords |

## Keyword Tuning

The triage system uses keyword matching to decide which conditional documents to generate. Over time, you may find that certain documents are relevant to your tickets but not being automatically included. This section explains how to identify and fix these false negatives.

### Identifying False Negatives

A false negative occurs when a document should be included but the triage system skips it because none of its trigger keywords appear in the ticket description. Signs of false negatives:

- You repeatedly use `+doc-name` overrides for the same document type across different tickets.
- Reviewers flag missing documents that should have been auto-generated.
- A document type is relevant to your domain but the keywords are too narrow.

To check override frequency, look at recent triage manifests:

```bash
# Find tickets where a specific document was force-included
grep -r '"action": "generate"' */planning/.triage-manifest.json | grep '"reason": "Override: +observability"'
```

### Tuning Process

1. **Identify the pattern**: Notice that you're repeatedly overriding `+observability` for backend service tickets.

2. **Examine the current keywords**: Look at the document's entry in `document-registry.json`:
   ```json
   "observability": {
     "triggers": {
       "keywords": ["monitoring", "logging", "metrics", "alerting", "dashboard", "tracing"],
       "description": "Backend services, infrastructure, or production-facing changes"
     }
   }
   ```

3. **Find the missing keywords**: Your ticket descriptions use terms like "backend", "microservice", or "api gateway" but none of those match the existing trigger keywords.

4. **Add new keywords**: Update the `keywords` array in `document-registry.json`:
   ```json
   "observability": {
     "triggers": {
       "keywords": ["monitoring", "logging", "metrics", "alerting", "dashboard", "tracing", "backend", "microservice"],
       "description": "Backend services, infrastructure, or production-facing changes"
     }
   }
   ```

5. **Test the change**: Run the triage script with a sample description to verify improved matching:
   ```bash
   bash scripts/triage-documents.sh "implement backend microservice for payments"
   ```

### Guidelines for Keyword Quality

- **Be specific**: Prefer "microservice" over "service" to avoid false positives.
- **Use domain terms**: Add keywords that reflect how your team describes work (e.g., "pipeline" for CI/CD-related observability).
- **Avoid overly broad terms**: Words like "update", "fix", or "change" match too many tickets and generate unnecessary documents.
- **Base tuning on evidence**: Only add keywords when you see a pattern of repeated overrides, not on speculation.
- **Test before committing**: Run `triage-documents.sh` with several representative descriptions to verify the new keywords match appropriately without causing noise.

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
| `/sdd:plan-ticket` | triage-documents.sh + scaffold-ticket.sh + ticket-planner |
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
   /sdd:plan-ticket "Ticket description" [+doc -doc]
   → triage-documents.sh selects relevant documents
   → Developer confirms document selection
   → scaffold-ticket.sh --manifest creates structure (selected docs only)
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

---

## Tasks API Integration

The SDD plugin integrates with Claude Code's native Tasks API for improved task tracking and optional parallel execution.

### Features

- **Real-time task status** in Ctrl+T view
- **Cross-session persistence** - task state survives session restarts
- **Optional parallel execution** for independent tasks within phases
- **Hybrid file+API architecture** - file remains authoritative

### Architecture

The Tasks API integration uses a hybrid approach:

```
Task File (.md)          Tasks API
     |                       |
     v                       v
  Authoritative          Visibility
  Source of Truth        Enhancement
     |                       |
     +--------> Sync <-------+
```

**Key Principle:** The task file is always authoritative. If the Tasks API is unavailable or states diverge, the file takes precedence.

### Configuration

#### Feature Flags

| Flag | Default | Description |
|------|---------|-------------|
| `SDD_TASKS_API_ENABLED` | `true` | Enable Tasks API integration. Set to `'false'` to disable. |
| `CLAUDE_TASK_LIST_ID` | Auto-set | Scopes tasks to a ticket. Set automatically by commands. |

#### Disabling Tasks API

To run in file-only mode (legacy behavior):

```bash
export SDD_TASKS_API_ENABLED=false
```

### How It Works

1. **Hydration**: When `/sdd:do-all-tasks` runs, it hydrates task files to the Tasks API
2. **Status Sync**: Task completion updates both the file checkbox and API status
3. **Visibility**: Active tasks appear in Claude Code's Ctrl+T task view
4. **Fallback**: If API is unavailable, file-only mode activates automatically

### Parallel Execution

When enabled via `--parallel` flag, independent tasks within a phase can execute concurrently:

```bash
/sdd:do-all-tasks TICKET_ID --parallel
```

**Performance expectations** (based on benchmarks):

| Ticket Type | Tasks | Independent | Expected Improvement |
|-------------|-------|-------------|---------------------|
| Small | 5 | 2 | ~15% (marginal) |
| Medium | 12 | 6 | **~32%** (significant) |
| Large | 22 | 12 | **~28%** (significant) |
| Linear | 10 | 0 | 0% (no benefit) |

**When to use --parallel:**
- Medium/large tickets with 3+ independent tasks per phase
- Implementation-heavy tasks (longer tasks = more savings)
- Time-sensitive deliveries

**When to use sequential (default):**
- Small tickets (< 6 tasks)
- Linear dependency chains
- First-time execution (simpler to debug)
- Context-constrained sessions

See [delegation-patterns.md](references/delegation-patterns.md) for detailed parallel execution patterns.

### Troubleshooting

#### Tasks API not available

If Tasks API is unavailable, the plugin falls back to file-only mode automatically:

```
Warning: Tasks API unavailable, continuing with file-only mode
```

No action needed - workflow continues normally.

#### Parallel execution issues

If parallel execution encounters errors, it falls back to sequential mode:

```
Warning: Parallel execution error, falling back to sequential mode
```

To troubleshoot:
1. Check that Tasks API is enabled (`SDD_TASKS_API_ENABLED` not set to `false`)
2. Verify ticket structure with `/sdd:tasks-status TICKET_ID`
3. Run without `--parallel` flag to isolate the issue

#### State mismatch between file and API

If file and API states diverge:

1. **File is authoritative** - the file checkbox determines actual status
2. **Re-sync by re-running command** - task status will be re-hydrated
3. **Clear stale state** - delete `.sdd-task-state/` directory if needed

### Migration Guide

**Existing tickets work without modification.** When you run a command on an existing ticket:

1. Tasks are automatically hydrated to the Tasks API on first load
2. No manual migration steps required
3. Existing file-based workflows continue to work
4. Tasks API integration is purely additive

To opt out of Tasks API for a specific session:
```bash
export SDD_TASKS_API_ENABLED=false
```
