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

### Step 1: Locate Task

```bash
find ${SDD_ROOT_DIR:-/app/.sdd}/tickets -name "${ARGUMENTS}_*.md" -type f 2>/dev/null
```

Read the task to understand:
- Acceptance criteria
- Primary agent assigned
- Technical requirements
- Dependencies

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

**Choose delegation strategy based on task requirements:**

**Option A: Task tool with general-purpose subagent (Primary option):**

Use this for standard implementation work when no specialized domain expertise is required:

```
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

**Option B: Specialized agent (if assigned in task's "Agents" section):**

Use this when a custom specialized agent has been created and assigned to this task:

```
Assignment: Implement task {TASK_ID}

Context:
- Task: {task_path}
- Requirements: {from task}

Instructions:
1. Read and understand the task fully
2. Implement all acceptance criteria
3. Follow technical requirements
4. Check the "Task completed" checkbox when done
5. Note any issues or blockers

Return: Summary of implementation done
```

**Decision criteria:**
- **Use Task tool (Option A)** when:
  - General coding skills are sufficient
  - No specialized domain expertise needed
  - Task is straightforward implementation
  - Context conservation is important (keeps orchestrator clean)

- **Use specialized agent (Option B)** when:
  - Custom agent explicitly assigned in task's "Agents" section
  - Domain-specific expertise prevents costly mistakes
  - Specialized knowledge improves quality significantly

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

Next: {Next task in sequence or ticket complete}
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
