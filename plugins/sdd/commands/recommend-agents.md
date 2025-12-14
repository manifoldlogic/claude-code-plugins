---
description: Analyze ticket and recommend custom specialized agents
argument-hint: [TICKET_ID] [optional: additional instructions]
---

# Recommend Custom Agents for Ticket

## Context

User input: "$ARGUMENTS"
Plugin root: "${CLAUDE_PLUGIN_ROOT}"

## Workflow

**IMPORTANT: You are an orchestrator. You do NOT do the work yourself. You delegate to the agent-recommender agent.**

### Step 1: Parse Arguments

Extract from `$ARGUMENTS`:
- **TICKET_ID**: Ticket identifier (e.g., "APIV2")
- **Additional Instructions**: Optional context or focus areas

### Step 2: Validate Ticket Exists

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

### Step 3: Verify Planning Documents Exist

Ensure planning is complete:
```bash
required_docs=(
  "${TICKET_PATH}/planning/analysis.md"
  "${TICKET_PATH}/planning/architecture.md"
  "${TICKET_PATH}/planning/plan.md"
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
Assignment: Analyze ticket {TICKET_ID} and recommend custom specialized agents

Context:
- Ticket path: {TICKET_PATH}
- Additional instructions: {ARGUMENTS after TICKET_ID, or "None provided"}

Instructions:
1. Read all planning documents (README, analysis, architecture, plan, quality-strategy, security-review)
2. Read existing tasks if they exist
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
- Cross-cutting concerns (spans multiple tasks)
- Domain expertise gaps (general agent might struggle)

Output: agent-recommendations.md document + summary report
```

### Step 5: Report Results

After agent completes, display summary:

```
AGENT RECOMMENDATIONS COMPLETE

Ticket: {TICKET_ID}_{name}

{Agent's summary of recommendations}

Document: {TICKET_PATH}/planning/agent-recommendations.md

Next Steps:
1. Review the recommendations in agent-recommendations.md
2. For each agent you want to create:
   - Open the /agents UI in Claude Code (from the main menu)
   - Select "Create new agent"
   - Choose "Generate with Claude (recommended)"
   - Paste the complete agent description from agent-recommendations.md
   - Claude Code's optimized agent creator will generate the agent configuration
   - Save the agent
3. After creating agents:
   - Run /sdd:assign-agents {TICKET_ID} to update planning documents
   - This updates plan.md and creates agent-assignments.md
   - Tasks will inherit agent assignments when created via /sdd:create-tasks
4. If not creating custom agents:
   - Skip directly to /sdd:create-tasks {TICKET_ID}
   - Default agents (ticket-planner, task-creator, etc.) are always available
   - Custom agents are optional enhancements for specialized work
```

## Key Constraints

- DO NOT analyze the ticket yourself
- DO NOT create the recommendations document yourself
- ONLY delegate to agent-recommender agent
- ONLY report results after agent completes

## Example Usage

```bash
# Basic usage
/sdd:recommend-agents APIV2

# With additional context
/sdd:recommend-agents DOCKER Focus on production safety and deployment concerns

# After planning is complete
/sdd:recommend-agents CACHE Consider caching strategies and invalidation patterns
```

## Error Handling

If ticket doesn't exist:
```
Error: Ticket {TICKET_ID} not found

Available tickets:
{list tickets in ${SDD_ROOT_DIR}/tickets/}
```

If planning incomplete:
```
Error: Ticket planning incomplete

Missing documents:
{list missing planning docs}

Please complete planning first with /sdd:plan-ticket
```
