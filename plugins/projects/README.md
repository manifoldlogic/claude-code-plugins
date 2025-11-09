# Projects Plugin

Systematic project and ticket workflow management for Claude Code.

## Overview

The Projects plugin provides a comprehensive system for planning, executing, and tracking software projects using a ticket-based workflow. It includes:

- **Project Planning** - Create structured projects with analysis, architecture, and quality strategy
- **Ticket Generation** - Automatically generate work tickets from project plans
- **Workflow Automation** - Complete ticket execution with implementation, testing, verification, and commits
- **Specialized Agents** - Purpose-built agents for each workflow phase
- **Quality Assurance** - Built-in verification and testing steps

## Installation

```bash
# Add marketplace (if not already added)
/plugin marketplace add /workspace/.crewchief/claude-code-plugins

# Install projects plugin
/plugin install projects@crewchief
```

After installation, restart Claude Code to activate the plugin.

## Components

### Slash Commands

#### `/create-project [description]`
Create initial project documents based on analysis, design, and planning framework.

**What it creates:**
- `.agents/projects/{SLUG}_{name}/README.md` - Project overview
- `.agents/projects/{SLUG}_{name}/planning/analysis.md` - Problem analysis
- `.agents/projects/{SLUG}_{name}/planning/architecture.md` - Technical design
- `.agents/projects/{SLUG}_{name}/planning/quality-strategy.md` - Testing strategy
- `.agents/projects/{SLUG}_{name}/planning/plan.md` - Execution plan

**Example:**
```
/create-project Implement user authentication with OAuth
```

#### `/create-project-tickets [PROJECT_SLUG]`
Generate individual work tickets from the project plan.

**What it does:**
- Reads the project plan
- Creates numbered tickets in `.agents/projects/{SLUG}/tickets/`
- Each ticket includes acceptance criteria, technical requirements, and dependencies

**Example:**
```
/create-project-tickets AUTH
```

#### `/review-tickets [PROJECT_SLUG]`
Comprehensive review of all created tickets for quality, consistency, and integration.

**Checks:**
- Ticket completeness and clarity
- Dependency correctness
- Naming consistency
- Acceptance criteria quality

**Example:**
```
/review-tickets AUTH
```

#### `/work-on-project [PROJECT_SLUG]`
Complete all tickets for a project systematically from start to finish.

**Process:**
1. Reads all tickets in order
2. For each ticket:
   - Implementation agent completes work
   - unit-test-runner executes tests
   - verify-ticket checks acceptance criteria
   - commit-ticket creates conventional commit
3. Proceeds to next ticket

**Example:**
```
/work-on-project AUTH
```

#### `/single-ticket [TICKET_ID]`
Complete, verify, and commit a single ticket following the full workflow.

**Workflow:**
1. Read ticket requirements
2. Implement functionality
3. Run tests (if applicable)
4. Verify acceptance criteria met
5. Create conventional commit

**Example:**
```
/single-ticket AUTH-1001
```

### Specialized Agents

#### `ticket-creator`
Creates standardized work tickets from requirements. Ensures tickets include:
- Clear acceptance criteria
- Technical requirements
- Implementation notes
- Dependencies
- Risk assessment

#### `verify-ticket`
Verifies completed work meets all acceptance criteria. Checks:
- All acceptance criteria met
- Tests executed and passing
- Code quality standards maintained
- No unintended side effects

#### `commit-ticket`
Creates conventional commits for completed tickets. Generates:
- Descriptive commit messages referencing ticket IDs
- Proper commit scopes (feat, fix, docs, etc.)
- Co-authored attribution

#### `unit-test-runner`
Executes tests and reports results without modifications. Provides:
- Clear pass/fail status
- Test output capture
- No code changes (observation only)

## Quick Start

### Create a New Project

```bash
# 1. Create project structure
/create-project Implement semantic code search

# 2. Review and refine planning documents
# Edit files in .agents/projects/SEARCH_semantic-code-search/planning/

# 3. Generate tickets from plan
/create-project-tickets SEARCH

# 4. Review ticket quality
/review-tickets SEARCH

# 5. Execute all tickets
/work-on-project SEARCH
```

### Work on Individual Tickets

```bash
# Complete a single ticket
/single-ticket SEARCH-1001

# The workflow will:
# - Implement the functionality
# - Run tests
# - Verify acceptance criteria
# - Create a commit
```

## Workflow Sequence

```
Planning Phase:
  /create-project → planning documents
  /create-project-tickets → ticket files
  /review-tickets → validation

Execution Phase (per ticket):
  Implementation → Tests → Verification → Commit

  If tests fail → return to implementation
  If verification fails → return to implementation
  If verification passes → commit and move to next ticket
```

## Project Organization

### Directory Structure

```
.agents/projects/{SLUG}_{descriptive-name}/
├── README.md           # Project overview
├── planning/           # Strategic documents
│   ├── analysis.md     # Problem definition
│   ├── architecture.md # Technical design
│   ├── plan.md         # Execution plan
│   └── quality-strategy.md # Testing strategy
└── tickets/            # Work tickets
    ├── {SLUG}-1001_description.md
    ├── {SLUG}-1002_description.md
    └── ...
```

### Ticket Naming Convention

- Format: `{SLUG}-{NUMBER}_{description}.md`
- SLUG: Project identifier (e.g., AUTH, SEARCH, DEPLOY)
- NUMBER: Sequential ticket number (1001, 1002, 1003...)
- Description: Brief kebab-case summary

**Examples:**
- `AUTH-1001_implement-oauth-flow.md`
- `SEARCH-2001_add-vector-search.md`
- `DEPLOY-1001_setup-docker-compose.md`

### Ticket Lifecycle

1. **Created** - Ticket file generated with requirements
2. **In Progress** - Implementation agent working
3. **Testing** - Tests being executed
4. **Verification** - Acceptance criteria checked
5. **Committed** - Changes committed to repository
6. **Complete** - Ticket archived or marked done

## Best Practices

### Planning
- Write clear, specific project descriptions
- Break large projects into phases
- Define measurable success criteria
- Document dependencies explicitly

### Tickets
- Keep tickets focused (single responsibility)
- Write testable acceptance criteria
- Include technical requirements upfront
- Note dependencies to avoid blockers

### Execution
- Complete tickets in sequence
- Verify tests pass before committing
- Review commits before pushing
- Document decisions in ticket notes

### Quality
- Use `/review-tickets` before execution
- Don't skip verification step
- Address test failures immediately
- Keep commits atomic (one ticket = one commit)

## Configuration

No configuration required. The plugin works with `.agents/` directory structure automatically.

## Troubleshooting

### Tickets not found
- Ensure project directory exists in `.agents/projects/`
- Check ticket naming follows convention
- Verify PROJECT_SLUG matches directory name

### Commit failures
- Ensure git repository is initialized
- Check for unstaged changes
- Verify commit message format

### Verification failures
- Review acceptance criteria carefully
- Check test execution output
- Ensure all requirements met

## Version

Current version: **0.1.0**

## Keywords

`projects`, `tickets`, `workflows`, `management`, `automation`, `planning`

## Links

- [Repository](https://github.com/danielbushman/claude-code-plugins)
- [Agents Directory](/.agents/README.md)
- [Ticket Workflow](/.agents/README.md#ticket-workflow)
