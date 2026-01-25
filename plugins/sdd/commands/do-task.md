---
description: Complete a single task with full verification workflow
argument-hint: [TASK_ID like TICKET_ID.1001]
---

# Single Task Workflow

## Context

Task ID: $ARGUMENTS
Task pattern: `${SDD_ROOT_DIR}/tickets/**/tasks/$ARGUMENTS_*.md`

## Workflow

**IMPORTANT: You are an orchestrator. You coordinate the implementation, testing, verification, and commit phases by delegating to appropriate agents.**

### Step 0: Write Session State File

**IMPORTANT: Before starting any task work, write a session state file to track active work.**

This enables multi-session reliable work detection. The Stop hook uses this file to block only THIS session when work is in progress.

```bash
# Get session_id from environment or use a generated fallback
SESSION_ID="${CLAUDE_SESSION_ID:-$(uuidgen 2>/dev/null || echo session-$$-$(date +%s))}"
SDD_ROOT="${SDD_ROOT_DIR:-/app/.sdd}"
TASK_ID="${ARGUMENTS}"
TICKET_ID=$(echo "$TASK_ID" | cut -d. -f1)

# Create session states directory if needed
mkdir -p "$SDD_ROOT/.sdd-session-states"

# Write session state file atomically (write to temp, rename)
TEMP_FILE=$(mktemp "$SDD_ROOT/.sdd-session-states/.tmp.XXXXXX")
cat > "$TEMP_FILE" << EOF
{
  "session_id": "$SESSION_ID",
  "ticket_id": "$TICKET_ID",
  "task_id": "$TASK_ID",
  "phase": "implementation",
  "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "command": "/sdd:do-task $TASK_ID"
}
EOF
mv "$TEMP_FILE" "$SDD_ROOT/.sdd-session-states/$SESSION_ID.json"
echo "Session state written: $SDD_ROOT/.sdd-session-states/$SESSION_ID.json"
```

**Error Handling:** If session state write fails, continue with task execution (graceful degradation). The Stop hook will fall back to task file inspection.

---

### Step 1: Locate Task

```bash
find ${SDD_ROOT_DIR:-/app/.sdd}/tickets -name "${ARGUMENTS}_*.md" -type f 2>/dev/null
```

Read the task to understand:
- Acceptance criteria
- Primary agent assigned
- Technical requirements
- Dependencies

### Step 1.5: Extract and Classify Primary Agent

**CRITICAL: The orchestrator must invoke specialized agents directly. Sub-agents cannot spawn other agents - this is an architectural constraint of the Task tool.**

#### Agent Extraction

Parse the task file's "## Agents" section to identify the primary agent:

1. **Find the Agents section** in the task file
2. **Extract the first bullet point** content (this is the primary agent responsible for implementation)
3. **Normalize the agent name**:
   - Remove markdown formatting: `[]`, `-`, `*`, etc.
   - Trim leading/trailing whitespace
   - If result contains newlines, take only first line
   - If result is empty after normalization, treat as missing agent

**Example parsing:**
```text
## Agents
- [game-design:game-core-mechanics-architect]    → "game-design:game-core-mechanics-architect"
- [general-purpose]                               → "general-purpose"
- task-executor                                   → "task-executor"
```

#### Agent Classification

Compare the extracted agent name against this **Standard Agent List**:

| Standard Agents (14 total) |
|---------------------------|
| verify-task |
| commit-task |
| unit-test-runner |
| status-reporter |
| structure-validator |
| task-creator |
| ticket-reviewer |
| ticket-planner |
| agent-assigner |
| agent-recommender |
| epic-planner |
| code-reviewer |
| task-executor |
| general-purpose |

**Classification Decision:**
- **If agent IS in the Standard Agent List** → Use `general-purpose` for implementation (standard workflow)
- **If agent is NOT in the Standard Agent List** → Use specialized agent directly via Task tool
- **If Agents section is missing or empty** → Log warning, use `general-purpose` (fallback for backward compatibility)

**Warning message for missing/empty agent:**
```text
⚠ Warning: No primary agent found in task's Agents section.
  Falling back to general-purpose for implementation.
  To use a specialized agent, add an Agents section with the primary agent listed first.
```

### Step 2: Check Dependencies (BLOCKING)

**CRITICAL: Dependencies MUST be satisfied before proceeding. If any dependency is incomplete, task execution CANNOT continue.**

#### Parse Dependencies from Task File

```bash
# Locate task file
TASK_FILE=$(find ${SDD_ROOT_DIR:-/app/.sdd}/tickets -name "${ARGUMENTS}_*.md" -type f 2>/dev/null | head -1)
TICKET_ID=$(echo "$ARGUMENTS" | cut -d. -f1)
TICKET_PATH=$(ls -d ${SDD_ROOT_DIR:-/app/.sdd}/tickets/${TICKET_ID}_* 2>/dev/null | head -1)

# Extract dependency task IDs from "## Dependencies" section
# Format: "- TICKET_ID.XXXX (description) - MUST be complete"
DEPS=$(grep -A20 "## Dependencies" "$TASK_FILE" | grep -oE '[A-Z0-9-]+\.[0-9]+' | head -10)

if [ -z "$DEPS" ]; then
  echo "✓ No task dependencies declared"
  # Proceed to implementation
fi
```

#### Validate Each Dependency

```bash
BLOCKED=false
DEP_STATUS=""

for dep_id in $DEPS; do
  # Determine if internal (same ticket) or external dependency
  DEP_TICKET=$(echo "$dep_id" | cut -d. -f1)

  if [ "$DEP_TICKET" = "$TICKET_ID" ]; then
    # INTERNAL DEPENDENCY - same ticket
    DEP_FILE=$(ls ${TICKET_PATH}/tasks/${dep_id}_*.md 2>/dev/null | head -1)

    if [ -z "$DEP_FILE" ]; then
      DEP_STATUS="${DEP_STATUS}\n❌ $dep_id - Task file not found"
      BLOCKED=true
    elif grep -q "\- \[x\] \*\*Task completed\*\*" "$DEP_FILE"; then
      DEP_STATUS="${DEP_STATUS}\n✓ $dep_id - Complete"
    else
      DEP_STATUS="${DEP_STATUS}\n❌ $dep_id - Not complete (Task completed checkbox unchecked)"
      BLOCKED=true
    fi
  else
    # EXTERNAL DEPENDENCY - different ticket
    EXT_TICKET_PATH=$(ls -d ${SDD_ROOT_DIR:-/app/.sdd}/tickets/${DEP_TICKET}_* 2>/dev/null | head -1)

    if [ -z "$EXT_TICKET_PATH" ]; then
      # Check archive for completed external tickets
      EXT_ARCHIVE_PATH=$(ls -d ${SDD_ROOT_DIR:-/app/.sdd}/archive/tickets/${DEP_TICKET}_* 2>/dev/null | head -1)

      if [ -n "$EXT_ARCHIVE_PATH" ]; then
        DEP_STATUS="${DEP_STATUS}\n✓ $dep_id - Complete (archived)"
      else
        DEP_STATUS="${DEP_STATUS}\n❌ $dep_id - External ticket not found"
        BLOCKED=true
      fi
    else
      DEP_FILE=$(ls ${EXT_TICKET_PATH}/tasks/${dep_id}_*.md 2>/dev/null | head -1)

      if [ -z "$DEP_FILE" ]; then
        DEP_STATUS="${DEP_STATUS}\n❌ $dep_id - External task file not found"
        BLOCKED=true
      elif grep -q "\- \[x\] \*\*Task completed\*\*" "$DEP_FILE"; then
        DEP_STATUS="${DEP_STATUS}\n✓ $dep_id - Complete"
      else
        DEP_STATUS="${DEP_STATUS}\n❌ $dep_id - External task not complete"
        BLOCKED=true
      fi
    fi
  fi
done

echo "=== DEPENDENCY CHECK ==="
echo -e "$DEP_STATUS"
echo ""

if [ "$BLOCKED" = true ]; then
  echo "❌ DEPENDENCY CHECK FAILED: Cannot execute $ARGUMENTS"
  echo ""
  echo "Action Required:"
  echo "1. Complete all dependency tasks first"
  echo "2. Ensure 'Task completed' checkbox is checked in dependency tasks"
  echo "3. Re-run /sdd:do-task $ARGUMENTS after dependencies satisfied"
  # EXIT - Do not proceed
fi
```

#### Dependency Validation Requirements

| Check | Required | Behavior |
|-------|----------|----------|
| Internal dependency complete | YES | BLOCKS if not complete |
| External dependency complete | YES | BLOCKS if not complete |
| Archived external dependency | OK | Treated as complete |
| Dependency task not found | YES | BLOCKS with clear error |

#### Error Message Format

If dependencies are not satisfied:

```
=== DEPENDENCY CHECK ===

✓ SDDREV.1001 - Complete
❌ SDDREV.1002 - Not complete (Task completed checkbox unchecked)
✓ EXTERNAL.2003 - Complete (archived)
❌ OTHER.1001 - External ticket not found

❌ DEPENDENCY CHECK FAILED: Cannot execute SDDREV.2003

Action Required:
1. Complete all dependency tasks first
2. Ensure 'Task completed' checkbox is checked in dependency tasks
3. Re-run /sdd:do-task SDDREV.2003 after dependencies satisfied
```

**DO NOT PROCEED if dependencies are not satisfied.**

---

### Step 3: Implementation

**Delegate to the appropriate agent based on the classification from Step 1.5.**

#### Conditional Invocation Logic

Based on the agent classification determined in Step 1.5, use ONE of the following delegation patterns:

---

**IF PRIMARY AGENT IS A SPECIALIZED AGENT** (not in Standard Agent List):

Invoke the specialized agent directly using the Task tool:

```text
Task tool with subagent_type: "{primary-agent-name}"

Assignment:
## Task
Implement task {TASK_ID}

## Context
- Task file: {task_path}
- Read the task file for full requirements and acceptance criteria
- You are the specialized agent assigned to this task
- Apply your domain expertise to the implementation

## Expected Output
- All acceptance criteria implemented
- "Task completed" checkbox can be checked
- Summary of implementation with specialist insights

## Acceptance Criteria
- All task acceptance criteria met
- Domain-specific quality standards applied
- Technical requirements satisfied
```

**Example - Specialized Agent Invocation:**
```text
# Task has: Agents: [game-design:game-core-mechanics-architect]
# Classification: NOT in Standard Agent List → Specialized agent

Task tool with subagent_type: "game-design:game-core-mechanics-architect"

Assignment:
## Task
Implement task SPIRIT.1003

## Context
- Task file: /workspace/_SDD/tickets/SPIRIT_spirit-system/tasks/SPIRIT.1003_implement-spirit-evolution.md
- Read the task file for full requirements and acceptance criteria
- You are the specialized agent assigned to this task
- Apply your domain expertise to the implementation

## Expected Output
- All acceptance criteria implemented
- "Task completed" checkbox can be checked
- Summary of implementation with specialist insights

## Acceptance Criteria
- All task acceptance criteria met
- Domain-specific quality standards applied
- Technical requirements satisfied
```

---

**IF PRIMARY AGENT IS A STANDARD/GENERAL AGENT** (in Standard Agent List or missing):

Use general-purpose delegation:

```text
Task tool with subagent_type: "general-purpose"

Assignment:
## Task
Implement task {TASK_ID}

## Context
- Task file: {task_path}
- Read the task file for full requirements and acceptance criteria
- Follow technical requirements specified in task

## Expected Output
- All acceptance criteria implemented
- "Task completed" checkbox can be checked
- Summary of implementation done

## Acceptance Criteria
- All task acceptance criteria met
- Code follows project patterns and conventions
- Technical requirements satisfied
- No breaking changes introduced
```

**Example - General Agent Invocation:**
```text
# Task has: Agents: [general-purpose] OR Agents: [task-executor] OR missing Agents section
# Classification: IN Standard Agent List or missing → Use general-purpose

Task tool with subagent_type: "general-purpose"

Assignment:
## Task
Implement task SETUP.1001

## Context
- Task file: /workspace/_SDD/tickets/SETUP_project-setup/tasks/SETUP.1001_initialize-config.md
- Read the task file for full requirements and acceptance criteria
- Follow technical requirements specified in task

## Expected Output
- All acceptance criteria implemented
- "Task completed" checkbox can be checked
- Summary of implementation done

## Acceptance Criteria
- All task acceptance criteria met
- Code follows project patterns and conventions
- Technical requirements satisfied
- No breaking changes introduced
```

---

#### Error Handling for Agent Invocation

**If Task tool fails with "agent not found" or similar error:**

```text
❌ Agent Invocation Error: Could not find agent "{agent-name}"

Possible causes:
1. Agent not installed or registered in the system
2. Agent name misspelled in task's Agents section
3. Agent definition file missing from plugins/sdd/agents/

Suggested actions:
1. Verify agent exists: Check if agents/{agent-name}.md exists
2. Check agent name spelling in task file
3. If specialized agent is missing, either:
   a. Create the agent definition using /sdd:recommend-agents
   b. Update task's Agents section to use general-purpose
4. Re-run /sdd:do-task {TASK_ID} after fixing
```

---

**Context conservation:** The Task tool spawns a fresh subagent context for implementation, preserving the orchestrator's context for coordinating the full workflow (implement → test → verify → commit). See [delegation-patterns.md](../skills/project-workflow/references/delegation-patterns.md) Pattern 6.

### Step 4: Testing

**Delegate to unit-test-runner agent (Haiku):**

```
Assignment: Run tests for task {TASK_ID}

Context:
- Changed files: {from git status}
- Test scope: {from quality strategy or task}

Instructions:
1. Run appropriate test suite
2. Report pass/fail results with coverage metrics
3. Verify coverage thresholds are met
4. If all pass and coverage is adequate, confirm "Tests pass" checkbox can be checked

Return: Test results summary including coverage percentage and threshold status
```

If tests fail or coverage drops below thresholds, return to implementation agent to fix.

### Step 5: Verification

**Delegate to verify-task agent (Sonnet):**

```
Assignment: Verify task {TASK_ID} implementation

Context:
- Task: {task_path}
- Implementation complete
- Tests passing

Instructions:
1. Check each acceptance criterion against code
2. Verify technical requirements met
3. Confirm test execution evidence exists
4. If all verified, check "Verified" checkbox
5. If not verified, report what's missing

Return: Verification result (pass/fail with details)
```

If verification fails, return to implementation agent.

### Step 6: Commit

**Delegate to commit-task agent (Haiku):**

```
Assignment: Commit verified changes for task {TASK_ID}

Context:
- Task verified
- Changes staged

Instructions:
1. Confirm task is verified
2. Stage all relevant changes
3. Create conventional commit
4. Report commit hash

Return: Commit confirmation
```

### Step 7: Report

```
TASK COMPLETE: {TASK_ID}

Title: {task title}

Status:
✓ Task completed
✓ Tests pass
✓ Verified
✓ Committed: {commit_hash}

Changes:
- {file1}: {brief description}
- {file2}: {brief description}

Commit: {type}({scope}): {TASK_ID} {message}

---
RECOMMENDED NEXT STEP:
{If more tasks: Next task in sequence}
{If ticket complete: /sdd:code-review {TICKET_ID} (recommended) or /sdd:pr {TICKET_ID}}
```

## Failure Handling

If any phase fails:
1. Report specific failure reason
2. DO NOT proceed to next phase
3. Suggest remediation
4. Allow user to continue or fix

## Key Constraints

- Follow phase order: implement → test → verify → commit
- Use appropriate agent for each phase
- DO NOT skip verification
- DO NOT implement code yourself
- DO NOT commit without verification
