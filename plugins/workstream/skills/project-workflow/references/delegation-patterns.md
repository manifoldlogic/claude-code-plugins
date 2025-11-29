# Delegation Patterns

This document explains how to properly delegate work to maintain efficiency and consistency.

## Core Principle

**The orchestrator NEVER does the work itself.**

All work is delegated to:
1. **Scripts** for mechanical tasks
2. **Haiku agents** for structured processing
3. **Sonnet agents** for reasoning tasks

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
   bash ticket-status.sh SLUG → JSON → status-reporter formats
   (Fast, cheap, consistent)
```

### Implementation

```bash
# 1. Script gathers data
output=$(bash scripts/ticket-status.sh SLUG)

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

### Example: Multi-Project Status

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
for project in PROJ1 PROJ2 PROJ3; do
  bash ticket-status.sh $project &
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
   - If complex issues: Recommend project-reviewer (Sonnet)

3. project-reviewer analyzes deeply
   - Provides full analysis and recommendations
```

## Anti-Patterns

### 1. Over-Delegation

```
❌ WRONG: Spawn Sonnet agent to read one file
✅ RIGHT: Use Read tool directly
```

### 2. Under-Delegation

```
❌ WRONG: Orchestrator writes all planning docs
✅ RIGHT: Spawn project-planner agent
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
Format the ticket status report for project APIV2.

## Input
<json output from ticket-status.sh>

## Expected Output
Markdown table with status summary, grouped by phase.

## Constraints
- Include progress percentage
- Highlight tickets needing attention
- Keep concise (one screen)
```
