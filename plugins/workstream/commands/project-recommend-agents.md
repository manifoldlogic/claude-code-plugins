---
description: Analyze project and recommend custom specialized agents
argument-hint: [PROJECT_SLUG] [optional: additional instructions]
---

# Recommend Custom Agents for Project

## Context

User input: "$ARGUMENTS"
Plugin root: "${CLAUDE_PLUGIN_ROOT}"

## Workflow

**IMPORTANT: You are an orchestrator. You do NOT do the work yourself. You delegate to the agent-recommender agent.**

### Step 1: Parse Arguments

Extract from `$ARGUMENTS`:
- **SLUG**: Project identifier (e.g., "APIV2")
- **Additional Instructions**: Optional context or focus areas

### Step 2: Validate Project Exists

Check project exists:
```bash
if [ ! -d ".crewchief/projects/${SLUG}_"* ]; then
  echo "Error: Project ${SLUG} not found"
  exit 1
fi
```

Find exact project path:
```bash
PROJECT_PATH=$(ls -d .crewchief/projects/${SLUG}_* 2>/dev/null | head -1)
```

### Step 3: Verify Planning Documents Exist

Ensure planning is complete:
```bash
required_docs=(
  "${PROJECT_PATH}/planning/analysis.md"
  "${PROJECT_PATH}/planning/architecture.md"
  "${PROJECT_PATH}/planning/plan.md"
)

for doc in "${required_docs[@]}"; do
  if [ ! -f "$doc" ]; then
    echo "Error: Missing required planning document: $doc"
    exit 1
  fi
done
```

### Step 4: Delegate to Agent Recommender

**Delegate to agent-recommender agent (Sonnet):**

```
Task: Analyze project {SLUG} and recommend custom specialized agents

Context:
- Project path: {PROJECT_PATH}
- Additional instructions: {ARGUMENTS after SLUG, if any}

Instructions:
1. Read all planning documents (README, analysis, architecture, plan, quality-strategy, security-review)
2. Read existing tickets if they exist
3. Identify areas where specialized agents would meaningfully improve success probability
4. For each recommendation, provide strong justification
5. Create agent-recommendations.md with:
   - Summary of whether agents are recommended
   - Detailed recommendations for each agent
   - Agent descriptions ready for creation
   - List of areas where agents are NOT needed
6. Be selective - only recommend agents with clear value

Follow these criteria:
- Complexity concentration (specialized knowledge prevents errors)
- Repeated patterns (appears multiple times)
- High-risk areas (mistakes would be costly)
- Cross-cutting concerns (spans multiple tickets)
- Domain expertise gaps (general agent might struggle)

Output: agent-recommendations.md document + summary report
```

### Step 5: Report Results

After agent completes, display summary:

```
AGENT RECOMMENDATIONS COMPLETE

Project: {SLUG}_{name}

{Agent's summary of recommendations}

Document: {PROJECT_PATH}/planning/agent-recommendations.md

Next Steps:
1. Review the recommendations
2. Create any agents you want using agent creation commands
3. Run /workstream:project-assign-agents {SLUG} to update planning docs and tickets
```

## Key Constraints

- DO NOT analyze the project yourself
- DO NOT create the recommendations document yourself
- ONLY delegate to agent-recommender agent
- ONLY report results after agent completes

## Example Usage

```bash
# Basic usage
/workstream:project-recommend-agents APIV2

# With additional context
/workstream:project-recommend-agents DOCKER Focus on production safety and deployment concerns

# After planning is complete
/workstream:project-recommend-agents CACHE Consider caching strategies and invalidation patterns
```

## Error Handling

If project doesn't exist:
```
Error: Project {SLUG} not found

Available projects:
{list projects in .crewchief/projects/}
```

If planning incomplete:
```
Error: Project planning incomplete

Missing documents:
{list missing planning docs}

Please complete planning first with /workstream:project-create
```
