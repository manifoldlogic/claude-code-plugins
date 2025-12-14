# Delegation Patterns

This document explains how to properly delegate work to maintain efficiency and consistency.

## Core Principle

**The orchestrator NEVER does the work itself.**

All work is delegated to:
1. **Scripts** for mechanical tasks
2. **Haiku agents** for structured processing
3. **Sonnet agents** for reasoning tasks

## Context Conservation Principle

Delegation is not just about division of labor—it's about preserving the orchestrator's effectiveness across complex, multi-operation workflows.

**Why delegation matters:**

1. **Token efficiency**: Each subagent starts with a fresh context focused solely on its task. The orchestrator conserves tokens by delegating implementation details rather than consuming its own context with code and test output.

2. **Attention focus**: By delegating work, the orchestrator maintains sharp focus on coordination, quality gates, and strategic decisions. Implementation details don't clutter the orchestrator's context, keeping attention on what matters at the orchestration level.

3. **Session longevity**: Long-running workflows (tickets with many tasks, complex multi-phase execution) can exhaust context if the orchestrator does work directly. Delegation extends session effectiveness by keeping the orchestrator's context lean.

4. **Cost efficiency**: Orchestrator tokens are expensive. Delegating to specialized agents (especially Haiku for mechanical tasks) or fresh general-purpose subagents reduces token costs while maintaining quality.

**Practical impact**: An orchestrator that does work itself may successfully complete 2-3 tasks before context exhaustion. An orchestrator that delegates can coordinate 10+ tasks while remaining effective throughout.

## Pattern 1: Script-First

Use scripts before spawning agents to reduce token usage.

### When to Use
- Gathering status/inventory
- Validating structure
- Creating scaffolds
- Simple file operations

### Example: Status Check

```
❌ WRONG: Spawn agent to read files and count checkboxes
   (Expensive, slow, inconsistent)

✅ RIGHT: Run script, pass output to Haiku agent
   bash task-status.sh TICKET_ID → JSON → status-reporter formats
   (Fast, cheap, consistent)
```

### Implementation

```bash
# 1. Script gathers data
output=$(bash scripts/task-status.sh TICKET_ID)

# 2. Haiku agent formats (if needed)
# Or just return JSON directly for simple cases
```

## Pattern 2: Pipeline

Chain multiple operations with clear handoffs.

### When to Use
- Multi-step workflows
- Different capabilities needed at each step
- Quality gates between steps

### Example: Ticket Workflow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ Implement   │ --> │ Test        │ --> │ Verify      │ --> │ Commit      │
│ (Sonnet)    │     │ (Haiku)     │     │ (Sonnet)    │     │ (Haiku)     │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
     │                   │                   │                   │
     ▼                   ▼                   ▼                   ▼
   Code              Test results        Verification        Commit hash
   changes           (pass/fail)         (approved/rejected)  (done)
```

### Key Rules
1. Each agent completes fully before next starts
2. Output of one becomes input to next
3. Pipeline can stop at any failure point
4. No parallel execution within a ticket

## Pattern 3: Parallel Gathering

Run independent operations concurrently.

### When to Use
- Multiple independent data sources
- Status checks across projects
- Validation of multiple items

### Example: Multi-Ticket Status

```
┌────────────────┐
│  Orchestrator  │
└───────┬────────┘
        │
   ┌────┴────┬────────────┐
   │         │            │
   ▼         ▼            ▼
┌─────┐   ┌─────┐     ┌─────┐
│Proj1│   │Proj2│     │Proj3│
│stat │   │stat │     │stat │
└──┬──┘   └──┬──┘     └──┬──┘
   │         │            │
   └────┬────┴────────────┘
        │
        ▼
   ┌─────────┐
   │ Combine │
   │ results │
   └─────────┘
```

### Implementation

Run scripts in parallel:
```bash
for ticket_id in TICK1 TICK2 TICK3; do
  bash task-status.sh $ticket_id &
done
wait
```

## Pattern 4: Conditional Delegation

Choose agent based on task characteristics.

### Decision Tree

```
Is the task...
│
├── Mechanical/Procedural?
│   ├── Just data gathering? → Script only
│   └── Needs formatting? → Script + Haiku
│
├── Requires judgment?
│   ├── Quality/correctness? → Sonnet
│   └── Simple validation? → Haiku
│
└── Requires reasoning?
    ├── Planning/design? → Sonnet
    ├── Research? → Sonnet
    └── Analysis? → Sonnet
```

### Examples

| Task | Decision | Delegation |
|------|----------|------------|
| Count tickets | Mechanical | Script only |
| Format status table | Mechanical + format | Script + Haiku |
| Check file exists | Mechanical | Script only |
| Validate structure | Simple validation | Haiku |
| Review plan quality | Quality judgment | Sonnet |
| Design architecture | Reasoning | Sonnet |
| Parse test output | Structured processing | Haiku |
| Verify acceptance criteria | Complex judgment | Sonnet |

## Pattern 5: Escalation

Start with cheaper options, escalate if needed.

### Escalation Chain

```
1. Script (cheapest, fastest)
   ↓ Can't handle complexity?
2. Haiku agent (cheap, structured)
   ↓ Needs reasoning?
3. Sonnet agent (balanced)
```

### Example: Validation

```
1. validate-structure.sh runs
   - If all valid: Done (script only)
   - If issues found: Pass to structure-validator (Haiku)

2. structure-validator formats report
   - If simple issues: Report and done
   - If complex issues: Recommend ticket-reviewer (Sonnet)

3. ticket-reviewer analyzes deeply
   - Provides full analysis and recommendations
```

## Pattern 6: General-Purpose Subagent Delegation

Use the Task tool to delegate implementation work to fresh general-purpose subagent contexts.

### When to Use

Use the Task tool with `subagent_type: "general-purpose"` when:

1. **Implementation work required**: The task involves writing code, editing files, running tests, or other hands-on implementation
2. **No specialized agent exists**: The work doesn't require deep domain expertise that would justify a custom specialized agent
3. **Context conservation needed**: The orchestrator needs to preserve its context for coordination across multiple tasks
4. **Fresh perspective valuable**: Starting with a clean context helps focus on the specific task requirements

**Decision criteria:**

| Scenario | Choice | Rationale |
|----------|--------|-----------|
| Data gathering only | Script | No reasoning needed, pure mechanical |
| Simple formatting | Script + Haiku | Mechanical + structured output |
| Code implementation | Task tool (general-purpose) | Needs fresh context, no specialized domain |
| Domain-specific implementation | Custom Sonnet agent | Requires specialized expertise |
| Test execution | Haiku agent | Structured, procedural |
| Quality verification | Sonnet agent | Complex judgment |

### Syntax

Use the Task tool with the assignment structure:

```
Task tool:
  assignment: |
    ## Task
    [Clear description of what needs to be done]

    ## Context
    [Relevant background, file paths, constraints]

    ## Expected Output
    [What the subagent should produce/report]

    ## Acceptance Criteria
    [Specific criteria to check completion]

  subagent_type: "general-purpose"
```

**Critical:** The `subagent_type: "general-purpose"` parameter is required to spawn a fresh subagent context.

### Example: Task Implementation

```
# Orchestrator delegates task APIV2.1001 implementation:

Task tool:
  assignment: |
    ## Task
    Implement task APIV2.1001: Add pagination support to /users endpoint

    ## Context
    - Task file: /app/.sdd/tickets/APIV2_api-version-2/tasks/APIV2.1001_add-pagination.md
    - Read the task file for full requirements and acceptance criteria
    - API route: /app/src/routes/users.ts
    - Follow patterns from /app/src/routes/posts.ts (already has pagination)

    ## Expected Output
    - Implementation complete
    - Acceptance criteria from task file verified
    - Summary of changes made

    ## Acceptance Criteria
    - All checkboxes in task file can be marked complete
    - Code follows existing pagination patterns
    - No breaking changes to existing API behavior

  subagent_type: "general-purpose"
```

### Example: Multi-Task Workflow

```
# Orchestrator coordinates ticket with 5 tasks:

For each task in APIV2:
  1. Delegate implementation → Task tool (general-purpose subagent)
  2. Delegate test execution → unit-test-runner (Haiku)
  3. Delegate verification → verify-task (Sonnet)
  4. Delegate commit → commit-task (Haiku)

Next task (fresh iteration, orchestrator context preserved)
```

**Key insight**: The orchestrator never implements directly. Each task gets a fresh subagent context via Task tool, while the orchestrator maintains coordination context across all 5 tasks.

### Complementary to Specialized Agents

Pattern 6 complements custom specialized agents (created via `/sdd:recommend-agents`):

- **General-purpose subagent**: Use for straightforward implementation when Claude's general coding skills suffice
- **Specialized agent**: Use when domain expertise (migrations, caching, security) prevents costly mistakes or improves quality significantly

Both preserve context conservation. The choice depends on whether specialized knowledge adds value.

## Anti-Patterns

### 1. Over-Delegation

```
❌ WRONG: Spawn Sonnet agent to read one file
✅ RIGHT: Use Read tool directly
```

### 2. Under-Delegation

```
❌ WRONG: Orchestrator writes all planning docs
✅ RIGHT: Spawn ticket-planner agent
```

### 3. Wrong Model Choice

```
❌ WRONG: Use Sonnet to format JSON into table
✅ RIGHT: Use Haiku or script

❌ WRONG: Use Haiku to review code quality
✅ RIGHT: Use Sonnet
```

### 4. Skipping Pipeline Steps

```
❌ WRONG: Commit without verification
✅ RIGHT: implement → test → verify → commit
```

### 5. Duplicate Work

```
❌ WRONG: Script validates, then agent validates again
✅ RIGHT: Script validates, agent only formats results
```

## Context Passing

When delegating, always pass:

1. **Task description**: What needs to be done
2. **Input data**: Results from previous steps
3. **Expected output**: What format to return
4. **Constraints**: Any limits or requirements

### Example Prompt to Agent

```
## Task
Format the task status report for ticket APIV2.

## Input
<json output from task-status.sh>

## Expected Output
Markdown table with status summary, grouped by phase.

## Constraints
- Include progress percentage
- Highlight tickets needing attention
- Keep concise (one screen)
```
