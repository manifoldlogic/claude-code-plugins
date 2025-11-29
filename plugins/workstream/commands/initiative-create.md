---
description: Create a new initiative for higher-order discovery and research work
argument-hint: [initiative name or description]
---

# Create Initiative

## Context

User input: "$ARGUMENTS"

## Workflow

**IMPORTANT: You are an orchestrator. You do NOT do the work yourself. You delegate to scripts and agents.**

### Step 1: Parse Input

Extract from user input:
- **Name**: kebab-case name for the initiative
- **Vision**: Optional vision statement if provided

If the input is a full description, extract the core name.

Examples:
- "api-redesign" → name: "api-redesign"
- "Redesign the API for v2" → name: "api-redesign", vision: "Redesign the API for v2"

### Step 2: Scaffold Structure

**Delegate to script:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/scripts/scaffold-initiative.sh "NAME" "VISION"
```

This creates the folder structure in `.crewchief/initiatives/{DATE}_{NAME}/`

### Step 3: Fill Content (Optional)

If user wants content filled:

**Delegate to initiative-planner agent (Sonnet):**

```
Task: Research and fill the initiative documents for {NAME}

Context:
- Initiative path: .crewchief/initiatives/{DATE}_{NAME}/
- User's vision: {VISION or description}

Instructions:
1. Research the problem space
2. Fill overview.md with vision and scope
3. Complete analysis documents
4. Identify potential projects for decomposition

Return: Summary of what was created
```

### Step 4: Report

After delegation completes, report to user:

```
INITIATIVE CREATED: {DATE}_{NAME}

Structure:
.crewchief/initiatives/{DATE}_{NAME}/
├── overview.md
├── reference/
├── analysis/
│   ├── opportunity-map.md
│   ├── domain-model.md
│   └── research-synthesis.md
├── decomposition/
│   ├── multi-project-overview.md
│   └── project-summaries/
├── decisions.md
└── backlog.md

Status: {Scaffolded | Scaffolded and filled}

Next Steps:
1. Add reference materials to reference/
2. {Complete analysis documents | Review filled documents}
3. Run decomposition to identify projects
4. Use /project-create for each identified project
```

## Decision Points

- **Just scaffold**: If user just provides a name
- **Scaffold + fill**: If user provides description and context

## Key Constraints

- Use scaffold-initiative.sh for creating structure
- Use initiative-planner agent for content creation
- DO NOT write files directly yourself
- DO NOT research topics yourself
