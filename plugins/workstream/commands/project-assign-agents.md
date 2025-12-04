---
description: Assign newly created agents to project phases and tickets
argument-hint: [PROJECT_SLUG]
---

# Assign Custom Agents to Project

## Context

User input: "$ARGUMENTS"
Plugin root: "${CLAUDE_PLUGIN_ROOT}"

## Workflow

**IMPORTANT: You are an orchestrator. You do NOT do the work yourself. You delegate to the agent-assigner agent.**

### Step 1: Parse Arguments

Extract from `$ARGUMENTS`:
- **SLUG**: Project identifier (e.g., "APIV2")

### Step 2: Validate Project and Recommendations Exist

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

Verify agent recommendations exist:
```bash
if [ ! -f "${PROJECT_PATH}/planning/agent-recommendations.md" ]; then
  echo "Error: No agent recommendations found for ${SLUG}"
  echo "Run /workstream:project-recommend-agents ${SLUG} first"
  exit 1
fi
```

### Step 3: Delegate to Agent Assigner

**Delegate to agent-assigner agent (Sonnet):**

```
Task: Integrate newly created agents into project {SLUG}

Context:
- Project path: {PROJECT_PATH}
- Agent recommendations: {PROJECT_PATH}/planning/agent-recommendations.md

Instructions:
1. Read agent-recommendations.md to understand recommended agents
2. Search for which recommended agents were actually created
3. Update plan.md to assign agents to appropriate phases
4. Update existing tickets with agent assignments (if tickets exist)
5. Update architecture.md if it mentions agent responsibilities
6. Create agent-assignments.md summarizing all assignments
7. Document which recommended agents were NOT created

Quality Requirements:
- Assignments must match recommended scope
- All similar work should use the same agent (consistency)
- Clear boundaries between agent responsibilities
- Document agents that were recommended but not created

Output: Updated planning docs + tickets + agent-assignments.md + summary report
```

### Step 4: Report Results

After agent completes, display summary:

```
AGENT ASSIGNMENTS COMPLETE

Project: {SLUG}_{name}

{Agent's summary of assignments}

Files Updated:
- {list of modified files}

New Document:
- {PROJECT_PATH}/planning/agent-assignments.md

Next Steps:
- Review agent assignments in plan.md and tickets
- Begin work with /workstream:project-work {SLUG}
- Individual tickets can be worked with /workstream:ticket {TICKET_ID}
```

## Key Constraints

- DO NOT update planning documents yourself
- DO NOT assign agents yourself
- ONLY delegate to agent-assigner agent
- ONLY report results after agent completes

## Example Usage

```bash
# After creating recommended agents
/workstream:project-assign-agents APIV2

# After creating some (but not all) recommended agents
/workstream:project-assign-agents DOCKER

# Update assignments after creating additional agents later
/workstream:project-assign-agents CACHE
```

## Typical Workflow

```bash
# 1. Create project
/workstream:project-create "API Version 2"

# 2. Get agent recommendations
/workstream:project-recommend-agents APIV2

# 3. Review recommendations, create agents you want
# (using agent creation commands)

# 4. Assign created agents to project
/workstream:project-assign-agents APIV2

# 5. Create tickets (agents already assigned)
/workstream:project-tickets APIV2

# 6. Execute work
/workstream:project-work APIV2
```

## Error Handling

If project doesn't exist:
```
Error: Project {SLUG} not found

Available projects:
{list projects in .crewchief/projects/}
```

If no recommendations found:
```
Error: No agent recommendations found for {SLUG}

Please run /workstream:project-recommend-agents {SLUG} first to analyze
the project and get recommendations for custom agents.
```

If planning incomplete:
```
Error: Project planning incomplete

Missing required documents for agent assignment:
{list missing planning docs like plan.md, architecture.md}

Cannot assign agents without execution plan.
```

## What Gets Updated

The agent-assigner will update:

1. **plan.md**: Adds agent assignments to each phase
2. **tickets/*.md**: Adds agent assignments to each ticket (if tickets exist)
3. **architecture.md**: Mentions agents in component responsibilities (if relevant)
4. **agent-assignments.md**: NEW - Summary of all agent assignments

## Agent Assignment Format

In plan.md:
```markdown
## Phase 2: Caching Implementation

**Agent Assignments:**
- cache-engineer: Design and implement cache layers
- database-engineer: Optimize database queries for caching
```

In tickets:
```markdown
## Agent Assignment
**Primary:** cache-engineer
- Responsible for cache invalidation strategy
- Ensures performance requirements met
```
