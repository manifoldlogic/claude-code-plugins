---
description: Create a new project with planning documents
argument-hint: [project description or SLUG name]
---

# Create Project

## Context

User input: "$ARGUMENTS"
Plugin root: "${CLAUDE_PLUGIN_ROOT}"

## Workflow

**IMPORTANT: You are an orchestrator. You do NOT do the work yourself. You delegate to scripts and agents.**

### Step 1: Determine Identifiers

If user provides just a description, derive:
- **SLUG**: 4-8 uppercase characters (unique across active/archived projects)
- **name**: kebab-case descriptive name

If user provides "SLUG name":
- Parse as provided

Check for uniqueness:
```bash
ls -d .crewchief/projects/${SLUG}_* .crewchief/archive/projects/${SLUG}_* 2>/dev/null
```

### Step 2: Scaffold Structure

**Delegate to script:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/scripts/scaffold-project.sh "SLUG" "name"
```

This creates:
- `.crewchief/projects/{SLUG}_{name}/README.md`
- `.crewchief/projects/{SLUG}_{name}/planning/` with template files
- `.crewchief/projects/{SLUG}_{name}/tickets/`

### Step 3: Fill Planning Documents

**Delegate to project-planner agent (Sonnet):**

```
Task: Create comprehensive planning documents for project {SLUG}_{name}

Context:
- Project path: .crewchief/projects/{SLUG}_{name}/
- User's description: {ARGUMENTS}
- Scaffolded files exist with templates

Instructions:
1. Research the problem space and codebase
2. Fill analysis.md with problem analysis
3. Create architecture.md with solution design
4. Define plan.md with phased execution
5. Write quality-strategy.md with testing approach
6. Complete security-review.md with security assessment
7. Update README.md with overview

Follow MVP principles - ship value, not ceremonies.

Return: Summary of planning decisions made
```

### Step 4: Report

```
PROJECT CREATED: {SLUG}_{name}

Structure:
.crewchief/projects/{SLUG}_{name}/
├── README.md
├── planning/
│   ├── analysis.md
│   ├── architecture.md
│   ├── plan.md
│   ├── quality-strategy.md
│   └── security-review.md
└── tickets/

Planning Summary:
- Problem: {one-line from analysis}
- Solution: {one-line from architecture}
- Phases: {count} phases planned

Next Step: Run /project-review {SLUG} before creating tickets
```

## Key Constraints

- Use scaffold-project.sh for structure
- Use project-planner agent for content
- DO NOT write planning docs yourself
- DO NOT skip any planning document
