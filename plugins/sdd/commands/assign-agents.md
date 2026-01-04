---
description: Assign newly created agents to ticket phases and tasks
argument-hint: [TICKET_ID] [optional: additional instructions]
---

# Assign Custom Agents to Ticket

## Context

User input: "$ARGUMENTS"
Plugin root: "${CLAUDE_PLUGIN_ROOT}"

## Workflow

**IMPORTANT: You are an orchestrator. You do NOT do the work yourself. You delegate to the agent-assigner agent.**

### Step 1: Parse Arguments

Extract from `$ARGUMENTS`:
- **TICKET_ID**: Ticket identifier (e.g., "APIV2")
- **Additional Instructions**: Optional agent assignment preferences or criteria (everything after TICKET_ID)

Examples:
- `APIV2` → ticket_id: "APIV2", instructions: none
- `APIV2 Prefer specialized agents over general ones` → ticket_id: "APIV2", instructions: "Prefer specialized agents over general ones"
- `CACHE Assign agents with concurrency expertise` → ticket_id: "CACHE", instructions: "Assign agents with concurrency expertise"

### Step 2: Validate Ticket and Recommendations Exist

Check ticket exists:
```bash
if [ ! -d "${SDD_ROOT_DIR:-/app/.sdd}/tickets/${TICKET_ID}_"* ]; then
  echo "Error: Ticket ${TICKET_ID} not found"
  exit 1
fi
```

Find exact ticket path:
```bash
TICKET_PATH=$(ls -d ${SDD_ROOT_DIR:-/app/.sdd}/tickets/${TICKET_ID}_* 2>/dev/null | head -1)
```

Verify agent recommendations exist:
```bash
if [ ! -f "${TICKET_PATH}/planning/agent-recommendations.md" ]; then
  echo "Error: No agent recommendations found for ${TICKET_ID}"
  echo "Run /sdd:recommend-agents ${TICKET_ID} first"
  exit 1
fi
```

### Step 3: Delegate to Agent Assigner

**Delegate to agent-assigner agent (Sonnet):**

```
Assignment: Integrate newly created agents into ticket {TICKET_ID}

Context:
- Ticket path: {TICKET_PATH}
- Agent recommendations: {TICKET_PATH}/planning/agent-recommendations.md
- Additional instructions: {ARGUMENTS after TICKET_ID, or "None provided"}

Instructions:
1. Read agent-recommendations.md to understand recommended agents
2. Search for which recommended agents were actually created
3. Update plan.md to assign agents to appropriate phases
4. Update existing tasks with agent assignments (if tasks exist)
5. Update architecture.md if it mentions agent responsibilities
6. Create agent-assignments.md summarizing all assignments
7. Document which recommended agents were NOT created

Quality Requirements:
- Assignments must match recommended scope
- All similar work should use the same agent (consistency)
- Clear boundaries between agent responsibilities
- Document agents that were recommended but not created

Output: Updated planning docs + tasks + agent-assignments.md + summary report
```

### Step 4: Report Results

After agent completes, display summary:

```
AGENT ASSIGNMENTS COMPLETE

Ticket: {TICKET_ID}_{name}

{Agent's summary of assignments}

Files Updated:
- {list of modified files}

New Document:
- {TICKET_PATH}/planning/agent-assignments.md

---
RECOMMENDED NEXT STEP: /sdd:do-all-tasks {TICKET_ID}
Begin work now that agents are assigned.
```

## Key Constraints

- DO NOT update planning documents yourself
- DO NOT assign agents yourself
- ONLY delegate to agent-assigner agent
- ONLY report results after agent completes

## Example Usage

```bash
# Basic agent assignment
/sdd:assign-agents APIV2

# Prefer specialized agents
/sdd:assign-agents APIV2 Prefer specialized agents over general ones

# Require specific expertise
/sdd:assign-agents CACHE Assign agents with concurrency and caching expertise

# Assignment strategy guidance
/sdd:assign-agents DOCKER Assign same agent for related container tasks

# After creating some (but not all) recommended agents
/sdd:assign-agents DOCKER

# Update assignments after creating additional agents later
/sdd:assign-agents CACHE Use general agents for flexibility
```

## Timing: Before or After Task Creation?

**Recommended: Run BEFORE `/sdd:create-tasks`**

```bash
# 1. Create ticket and review
/sdd:plan-ticket "API Version 2"
/sdd:review APIV2

# 2. Get agent recommendations
/sdd:recommend-agents APIV2

# 3. Create agents using Claude Code's /agents UI
# (Paste descriptions from agent-recommendations.md)

# 4. Assign agents to phases ← BEFORE decompose
/sdd:assign-agents APIV2

# 5. Create tasks (inherits agent assignments from plan.md)
/sdd:create-tasks APIV2

# 6. Execute work
/sdd:do-all-tasks APIV2
```

**Alternative: Run AFTER `/sdd:create-tasks`**

If you create tasks first, then decide to add custom agents:

```bash
# Tasks already exist
/sdd:create-tasks APIV2

# Later: Get agent recommendations
/sdd:recommend-agents APIV2

# Create agents, then retroactively assign
/sdd:assign-agents APIV2  # Updates both plan.md AND existing tasks
```

**Pros of Before-Decompose:**
- Tasks inherit agent assignments automatically from plan.md
- Cleaner workflow, agents assigned once
- Task-creator knows which agents to use

**Pros of After-Decompose:**
- Can create tasks faster without agent setup
- Add specialized agents only after seeing complexity
- Flexibility to adjust assignments per task

**Re-running Assign-Agents:**
- Safe to re-run after creating additional agents later
- Will update all planning docs and tasks with new assignments
- Won't remove existing assignments (additive)

## Error Handling

If ticket doesn't exist:
```
Error: Ticket {TICKET_ID} not found

Available tickets:
{list projects in ${SDD_ROOT_DIR}/tickets/}
```

If no recommendations found:
```
Error: No agent recommendations found for {TICKET_ID}

Please run /sdd:recommend-agents {TICKET_ID} first to analyze
the ticket and get recommendations for custom agents.
```

If planning incomplete:
```
Error: Ticket planning incomplete

Missing required documents for agent assignment:
{list missing planning docs like plan.md, architecture.md}

Cannot assign agents without execution plan.
```

## What Gets Updated

The agent-assigner will update:

1. **plan.md**: Adds agent assignments to each phase
2. **tasks/*.md**: Adds agent assignments to each task (if tasks exist)
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

In tasks:
```markdown
## Agent Assignment
**Primary:** cache-engineer
- Responsible for cache invalidation strategy
- Ensures performance requirements met
```
