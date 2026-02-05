---
description: Create a new ticket with planning documents
argument-hint: [ticket description or TICKET_ID name] [optional: additional instructions]
---

# Create Ticket

## Context

User input: "$ARGUMENTS"
Plugin root: "${CLAUDE_PLUGIN_ROOT}"

## Workflow

**IMPORTANT: You are an orchestrator. You do NOT do the work yourself. You delegate to scripts and agents.**

### Step 0: Parse Arguments

Extract from `$ARGUMENTS`:
- **DESCRIPTION or ID + name**: Ticket description or "TICKET_ID name" pattern (primary identifier)
- **Additional Instructions**: Optional planning context (everything after the description/ID-name pattern)

Examples:
- `"API redesign"` → description: "API redesign", instructions: none
- `"API redesign" Focus on backward compatibility` → description: "API redesign", instructions: "Focus on backward compatibility"
- `APIV2 redesign` → id: "APIV2", name: "redesign", instructions: none
- `APIV2 redesign Emphasize testing` → id: "APIV2", name: "redesign", instructions: "Emphasize testing"

### Step 1: Determine Identifiers

If user provides just a description, derive:
- **TICKET_ID**: 2-12 uppercase characters, may include dashes for Jira IDs like UIT-9819 (unique across active/archived tickets)
- **name**: kebab-case descriptive name

If user provides "TICKET_ID name":
- Parse as provided

Check for uniqueness:
```bash
ls -d ${SDD_ROOT_DIR:-/app/.sdd}/tickets/${TICKET_ID}_* ${SDD_ROOT_DIR:-/app/.sdd}/archive/tickets/${TICKET_ID}_* 2>/dev/null
```

### Step 2: Scaffold Structure

**Delegate to script:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/scripts/scaffold-ticket.sh "TICKET_ID" "name"
```

This creates:
- `${SDD_ROOT_DIR}/tickets/{TICKET_ID}_{name}/README.md`
- `${SDD_ROOT_DIR}/tickets/{TICKET_ID}_{name}/planning/` with template files
- `${SDD_ROOT_DIR}/tickets/{TICKET_ID}_{name}/tasks/`

### Step 3: Fill Planning Documents

**Option A: Delegate to ticket-planner agent (Sonnet) - Preferred:**

```
Assignment: Create comprehensive planning documents for ticket {TICKET_ID}_{name}

Context:
- Ticket path: ${SDD_ROOT_DIR}/tickets/{TICKET_ID}_{name}/
- User's description: {ARGUMENTS}
- Scaffolded files exist with templates
- Additional instructions: {planning context from user, or "None provided"}

Instructions:
1. Research the problem space and codebase
2. Fill analysis.md with problem analysis
3. Create prd.md with product requirements (source of truth for requirements)
4. Create architecture.md with solution design
5. Define plan.md with phased execution
6. Write quality-strategy.md with testing approach
7. Complete security-review.md with security assessment
8. Update README.md with overview

Follow enterprise-grade quality standards with disciplined scope management.

Return: Summary of planning decisions made
```

**Option B: Use Task tool if specialized planner unavailable:**

```
Task tool with subagent_type: "general-purpose"

Assignment:
## Task
Create comprehensive planning documents for ticket {TICKET_ID}_{name}

## Context
- Ticket path: ${SDD_ROOT_DIR}/tickets/{TICKET_ID}_{name}/
- User's description: {ARGUMENTS}
- Scaffolded files exist with templates
- Additional instructions: {planning context from user, or "None provided"}
- Follow enterprise-grade quality standards

## Expected Output
- All planning documents completed (analysis.md, prd.md, architecture.md, plan.md, quality-strategy.md, security-review.md)
- README.md updated with overview
- Summary of planning decisions

## Acceptance Criteria
- Problem space thoroughly analyzed
- Solution design is sound and phased
- Testing and security strategies defined
- Scope is disciplined and manageable
```

**Decision criteria:**
- Use ticket-planner when available (preferred for consistency)
- Use Task tool when ticket-planner unavailable
- Both options preserve orchestrator context for coordination

### Step 4: Log Creation

Log the ticket creation event:

```bash
SDD_ROOT="${SDD_ROOT_DIR:-/app/.sdd}"
mkdir -p "$SDD_ROOT/logs"
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")|TICKET_CREATED|{TICKET_ID}|-|plan-ticket|{phases} phases planned" >> "$SDD_ROOT/logs/workflow.log"
```

### Step 5: Report

```
TICKET CREATED: {TICKET_ID}_{name}

Structure:
${SDD_ROOT_DIR}/tickets/{TICKET_ID}_{name}/
├── README.md
├── planning/
│   ├── analysis.md
│   ├── prd.md
│   ├── architecture.md
│   ├── plan.md
│   ├── quality-strategy.md
│   └── security-review.md
└── tasks/

Planning Summary:
- Problem: {one-line from analysis}
- Solution: {one-line from architecture}
- Phases: {count} phases planned

```

### Next Step Prompt

After displaying the report above, use the **AskUserQuestion** tool to present next steps to the user:

**Question:** "What would you like to do next?"
**Header:** "Next step"
**multiSelect:** false

**Options:**
- Label: "/sdd:review {TICKET_ID}" | Description: "Verify planning quality before creating tasks"
- Label: "/sdd:create-tasks {TICKET_ID}" | Description: "Skip review and create tasks directly"
- Label: "/sdd:status" | Description: "Check current ticket and task status"

Where {TICKET_ID} is the actual ticket ID from the command execution context (e.g., "APIV2", "AUTH"), NOT the literal placeholder text.

## Example Usage

```bash
# Basic with description
/sdd:plan-ticket "API redesign for version 2"

# Description with planning context
/sdd:plan-ticket "API redesign" Focus on backward compatibility and migration path

# ID-name pattern basic
/sdd:plan-ticket APIV2 api-redesign

# ID-name pattern with planning context
/sdd:plan-ticket APIV2 api-redesign Emphasize comprehensive testing strategy

# With specific focus areas
/sdd:plan-ticket "User authentication" Prioritize security review and consider OAuth integration
```

## Key Constraints

- Use scaffold-ticket.sh for structure
- Use ticket-planner agent for content
- DO NOT write planning docs yourself
- DO NOT skip any planning document
