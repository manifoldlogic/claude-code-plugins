---
description: Create a new epic for higher-order discovery and research work
argument-hint: [epic name or description] [optional: additional instructions]
---

# Create Epic

## Context

User input: "$ARGUMENTS"

## Workflow

**IMPORTANT: You are an orchestrator. You do NOT do the work yourself. You delegate to scripts and agents.**

### Step 1: Parse Input

Extract from user input:
- **Name**: kebab-case name for the epic
- **Jira ID**: Optional Jira epic ID (e.g., UIT-444, BE-1234, PROJ-123)
- **Vision**: Optional vision statement if provided
- **Additional Instructions**: Optional research focus areas or planning context (everything after name/Jira ID pattern)

If the input is a full description, extract the core name.

Examples:
- "api-redesign" → name: "api-redesign"
- "UIT-444 user-profile-update" → jira_id: "UIT-444", name: "user-profile-update"
- "Redesign the API for v2" → name: "api-redesign", vision: "Redesign the API for v2"
- "BE-1234 best-epic Some vision here" → jira_id: "BE-1234", name: "best-epic", vision: "Some vision here"
- "api-v2 Focus on migration path from v1" → name: "api-v2", instructions: "Focus on migration path from v1"
- "PROJ-123 auth-redesign Emphasize security considerations" → jira_id: "PROJ-123", name: "auth-redesign", instructions: "Emphasize security considerations"

**Jira ID detection**: If the input starts with an uppercase ID matching `[A-Z][A-Z0-9]*(-[A-Z0-9]+)*` (e.g., UIT-444, BE-1234, PROJ-123), treat it as a Jira ID.

**Additional Instructions**: Text that provides research focus or planning context but is not the epic's vision/description. Passed to the epic-planner agent to guide analysis priorities.

### Step 2: Scaffold Structure

**Delegate to script:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/scripts/scaffold-epic.sh "NAME" "JIRA_ID" "VISION"
```

Note: Pass empty string `""` for JIRA_ID if not provided.

This creates the folder structure:
- Without Jira ID: `${SDD_ROOT_DIR}/epics/{DATE}_{NAME}/`
- With Jira ID: `${SDD_ROOT_DIR}/epics/{DATE}_{JIRA_ID}_{NAME}/`

### Step 3: Fill Content (Optional)

If user wants content filled:

**Option A: Delegate to epic-planner agent (Sonnet) - Preferred:**

```
Assignment: Research and fill the epic documents for {NAME}

Context:
- Epic path: ${SDD_ROOT_DIR}/epics/{FOLDER_NAME}/
  (where FOLDER_NAME is {DATE}_{NAME} or {DATE}_{JIRA_ID}_{NAME})
- User's vision: {VISION or description}
- Additional instructions: {ARGUMENTS after NAME/JIRA_ID pattern, or "None provided"}

Instructions:
1. Research the problem space
2. Fill overview.md with vision and scope
3. Complete analysis documents
4. Identify potential tickets for decomposition

Return: Summary of what was created
```

**Option B: Use Task tool for complex codebase research:**

If epic-planner agent is unavailable or the research requires extensive codebase exploration (>3 files):

```
Task tool with subagent_type: "general-purpose"

Assignment:
## Task
Research and fill epic documents for {NAME}

## Context
- Epic path: ${SDD_ROOT_DIR}/epics/{FOLDER_NAME}/
- User's vision: {VISION or description}
- Additional instructions: {ARGUMENTS after NAME/JIRA_ID pattern, or "None provided"}
- This epic requires research across the codebase

## Expected Output
- overview.md filled with vision and scope
- Analysis documents completed
- Potential tickets identified
- Summary of findings

## Acceptance Criteria
- All epic documents have meaningful content
- Research covers relevant codebase areas
- Ticket decomposition opportunities documented
```

**Decision criteria:**
- Use epic-planner when available (preferred for consistency)
- Use Task tool when epic-planner unavailable or for extensive codebase exploration
- See [delegation-patterns.md](../skills/project-workflow/references/delegation-patterns.md) Pattern 6 for context conservation benefits

### Step 4: Report

After delegation completes, report to user:

```
EPIC CREATED: {FOLDER_NAME}
  (e.g., 2025-12-22_api-redesign or 2025-12-22_UIT-444_best-epic-name)

Structure:
${SDD_ROOT_DIR}/epics/{FOLDER_NAME}/
├── overview.md
├── reference/
├── analysis/
│   ├── opportunity-map.md
│   ├── domain-model.md
│   └── research-synthesis.md
├── decomposition/
│   ├── multi-ticket-overview.md
│   └── ticket-summaries/
├── decisions.md
└── backlog.md

Status: {Scaffolded | Scaffolded and filled}
```

### Next Step Prompt

After displaying the report above, use the **AskUserQuestion** tool to present next steps to the user:

**Question:** "What would you like to do next?"
**Header:** "Next step"
**multiSelect:** false

**Options:**
- Label: "/sdd:plan-ticket" | Description: "Create the first ticket from this epic's plan"
- Label: "/sdd:status" | Description: "Check epic and ticket status"

Where the plan-ticket option should reference the epic ID if available in the command context.

## Decision Points

- **Just scaffold**: If user just provides a name
- **Scaffold + fill**: If user provides description and context

## Example Usage

```bash
# Basic epic creation with name only
/sdd:start-epic api-v2

# With research focus instructions
/sdd:start-epic api-v2 Focus on migration path from v1 and backward compatibility

# Jira ID with epic name
/sdd:start-epic PROJ-123 auth-redesign

# Jira ID with name and additional instructions
/sdd:start-epic PROJ-123 auth-redesign Emphasize security considerations and OAuth integration

# Full description with research context
/sdd:start-epic "Redesign the API for v2" Prioritize performance benchmarks and caching strategies
```

## Key Constraints

- Use scaffold-epic.sh for creating structure
- Use epic-planner agent for content creation
- DO NOT write files directly yourself
- DO NOT research topics yourself
