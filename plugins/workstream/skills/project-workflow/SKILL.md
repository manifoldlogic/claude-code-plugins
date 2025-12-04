---
name: project-workflow
description: Orchestrates initiatives, projects, and tickets for systematic software development. Use this skill when planning work, creating projects, managing tickets, or executing development workflows. Includes scripts for scaffolding and status reporting, with Haiku agents for mechanical tasks and Sonnet agents for reasoning.
---

# Project Workflow Skill

## Overview

This skill manages the complete development workflow hierarchy:

```
Initiative (research/discovery)
    └── Project (planning/execution container)
            └── Ticket (individual work item)
```

**Key Principles:**
1. **Scripts for mechanical tasks** - Scaffolding, inventory, validation
2. **Haiku for structured processing** - Status reporting, formatting, commits
3. **Sonnet for reasoning** - Planning, review, verification
4. **Strict delegation** - Orchestrator NEVER does work itself

## Workflow Hierarchy

### Initiatives
Higher-order discovery and research work that may spawn multiple projects.

**Location:** `.crewchief/initiatives/{DATE}_{name}/`

**When to use:** Exploring problem spaces, conducting research before knowing exact deliverables.

### Projects
Planning and execution containers with defined scope and deliverables.

**Location:** `.crewchief/projects/{SLUG}_{name}/`

**When to use:** Known deliverables, ready for planning and execution.

### Tickets
Individual work items with clear acceptance criteria and verification workflow.

**Location:** `.crewchief/projects/{SLUG}_{name}/tickets/{SLUG}-{NUMBER}_description.md`

**Workflow:** Implement → Test → Verify → Commit

## Quick Reference

### Create Initiative
```bash
# Scaffold structure
bash scripts/scaffold-initiative.sh "initiative-name" "Vision statement"

# Then delegate to initiative-planner agent for content
```

### Create Project
```bash
# Scaffold structure
bash scripts/scaffold-project.sh "SLUG" "project-name"

# Then delegate to project-planner agent for planning docs
```

### Check Status
```bash
# Get ticket status as JSON
bash scripts/ticket-status.sh SLUG

# Validate project structure
bash scripts/validate-structure.sh SLUG
```

### Recommend and Assign Custom Agents
```bash
# After project planning, analyze for custom agent opportunities
/workstream:project-recommend-agents SLUG

# Review recommendations, create agents you want

# Assign created agents to phases and tickets
/workstream:project-assign-agents SLUG
```

### Execute Workflow
```
For each ticket:
1. Delegate to primary implementation agent (custom or general)
2. Delegate to test-runner agent (Haiku)
3. Delegate to verify-ticket agent (Sonnet)
4. Delegate to commit-ticket agent (Haiku)
```

## Scripts

All scripts are in `scripts/` directory. Use these for mechanical tasks:

| Script | Purpose | Output |
|--------|---------|--------|
| `scaffold-initiative.sh` | Create initiative folder structure | Directory tree |
| `scaffold-project.sh` | Create project folder structure | Directory tree |
| `ticket-status.sh` | Scan ticket checkboxes | JSON status |
| `validate-structure.sh` | Verify project/ticket structure | Validation report |
| `project-summary.sh` | Generate project summary | Markdown summary |

### Script Usage Examples

```bash
# Create initiative
bash scripts/scaffold-initiative.sh "api-redesign" "Redesign the public API for v2"

# Create project
bash scripts/scaffold-project.sh "APIV2" "api-version-2"

# Get status of all tickets
bash scripts/ticket-status.sh APIV2

# Validate structure
bash scripts/validate-structure.sh APIV2

# Generate summary
bash scripts/project-summary.sh APIV2
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
| `test-runner` | Execute tests, report results |
| `commit-ticket` | Create commits after verification |

### Sonnet Agents (Reasoning, Analysis)

Use Sonnet agents for tasks that require:
- Complex decision making
- Multi-document synthesis
- Critical analysis
- Quality judgment

| Agent | Purpose |
|-------|---------|
| `initiative-planner` | Research and plan initiatives |
| `project-planner` | Create comprehensive planning docs |
| `project-reviewer` | Critical review of projects |
| `agent-recommender` | Analyze projects to recommend custom specialized agents |
| `agent-assigner` | Assign created agents to phases and tickets |
| `ticket-creator` | Generate tickets from plans |
| `verify-ticket` | Verify acceptance criteria met |

## Delegation Patterns

### Pattern 1: Script → Haiku Agent

For mechanical tasks with formatting:

```
1. Run script to gather data (e.g., ticket-status.sh)
2. Pass output to Haiku agent for formatting
3. Haiku returns formatted report
```

**Example:** Status reporting
```
ticket-status.sh → JSON → status-reporter agent → Formatted markdown
```

### Pattern 2: Sonnet Agent → Script → Haiku Agent

For complex workflows:

```
1. Sonnet agent makes decisions (what to create)
2. Script does mechanical work (scaffolding)
3. Haiku agent formats/reports results
```

**Example:** Project creation
```
project-planner decides content → scaffold-project.sh creates files → status-reporter confirms
```

### Pattern 3: Sequential Agent Pipeline

For ticket execution:

```
1. Implementation agent (Sonnet) - Does the work
2. test-runner (Haiku) - Runs tests
3. verify-ticket (Sonnet) - Verifies acceptance
4. commit-ticket (Haiku) - Creates commit
```

## Critical Rules

### DO:
- Always use scripts for scaffolding
- Delegate status gathering to scripts
- Use Haiku for formatting/reporting
- Use Sonnet for reasoning/verification
- Pass context between agents explicitly

### DON'T:
- Have orchestrator implement tickets directly
- Skip verification steps
- Use Sonnet for simple status checks
- Bypass the commit workflow
- Mix agent responsibilities

## Templates

Templates are in `templates/` directory:

```
templates/
├── initiative/
│   ├── overview.md
│   ├── opportunity-map.md
│   ├── domain-model.md
│   └── decisions.md
├── project/
│   ├── README.md
│   ├── analysis.md
│   ├── architecture.md
│   ├── plan.md
│   ├── quality-strategy.md
│   └── security-review.md
└── ticket/
    └── ticket-template.md
```

Scripts use these templates when scaffolding.

## Status Indicators

### Ticket Status Checkboxes

```markdown
## Status
- [ ] **Task completed** - acceptance criteria met
- [ ] **Tests pass** - tests executed and passing
- [ ] **Verified** - by verify-ticket agent
```

### Project Readiness

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
| `/initiative-create` | scaffold-initiative.sh + initiative-planner |
| `/project-create` | scaffold-project.sh + project-planner |
| `/project-review` | project-reviewer agent |
| `/project-recommend-agents` | agent-recommender agent |
| `/project-assign-agents` | agent-assigner agent |
| `/project-tickets` | ticket-creator agent |
| `/project-work` | Sequential ticket execution |
| `/ticket` | Single ticket workflow |
| `/status` | ticket-status.sh + status-reporter |
| `/archive` | structure-validator + archive logic |

## Complete Project Workflow

The full project lifecycle with optional agent customization:

```
1. Create Project
   /workstream:project-create "Project description"
   → scaffold-project.sh creates structure
   → project-planner fills planning docs
   → May recommend agent analysis

2. Review Project (Optional but Recommended)
   /workstream:project-review SLUG
   → project-reviewer critiques plan
   → Identifies risks and gaps

3. Recommend Agents (Optional, for complex projects)
   /workstream:project-recommend-agents SLUG
   → agent-recommender analyzes project
   → Creates agent-recommendations.md
   → Suggests agents only if genuinely valuable

4. Create Custom Agents (If recommended)
   Review agent-recommendations.md
   Create agents you want
   (Use agent creation commands)

5. Assign Agents (If custom agents created)
   /workstream:project-assign-agents SLUG
   → agent-assigner updates plan.md and tickets
   → Creates agent-assignments.md

6. Create Tickets
   /workstream:project-tickets SLUG
   → ticket-creator generates tickets from plan
   → Custom agents already assigned (if Step 5 done)

7. Execute Work
   /workstream:project-work SLUG
   → Processes tickets sequentially
   → Uses custom or general agents as assigned

8. Archive (When complete)
   /workstream:archive SLUG
   → Moves to archive/
```

**When to use agent customization (Steps 3-5):**
- Complex specialized domains (migrations, caching, performance)
- High-risk areas where expertise prevents costly mistakes
- Repeated specialized patterns across phases
- Deep domain knowledge would improve quality

**When to skip agent customization:**
- Straightforward general programming
- Short projects with few phases
- General Claude skills sufficient

## Workflow Diagrams

See [references/workflow-overview.md](references/workflow-overview.md) for detailed diagrams.

## Agent Responsibilities

See [references/agent-responsibilities.md](references/agent-responsibilities.md) for detailed agent descriptions.

## Best Practices

### Efficiency
1. Use scripts for data gathering before spawning agents
2. Prefer Haiku when reasoning isn't needed
3. Batch status checks rather than per-ticket queries
4. Cache project context across ticket executions

### Quality
1. Never skip verification steps
2. Always run tests before verification
3. Use project-reviewer before ticket creation
4. Keep commits atomic (one ticket = one commit)

### Maintainability
1. Follow naming conventions strictly
2. Keep tickets at 2-8 hour scope
3. Document decisions in projects
4. Archive completed projects promptly
