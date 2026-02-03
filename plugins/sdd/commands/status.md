---
description: Display comprehensive status overview across epics, tickets, and tasks with recommended actions
command-hint: /sdd:status
---

# SDD Unified Status

## Context

This command provides a comprehensive view across all three SDD hierarchy levels:
- **Epics**: Research and discovery checkpoints
- **Tickets**: Planning docs and task progress
- **Tasks**: Individual work items and verification status

## Workflow

**IMPORTANT: Aggregate data from all three tiers with graceful degradation.**

### Step 1: Initialize

```bash
SDD_ROOT_DIR="${SDD_ROOT_DIR:-/app/.sdd}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}/plugins/sdd"

echo "SDD STATUS OVERVIEW"
echo ""

# Track if we have any data
HAS_DATA=false
ERRORS=""
```

### Step 2: Gather Epic Status

```bash
# Try to get epic status
if EPIC_JSON=$(bash "${PLUGIN_ROOT}/skills/project-workflow/scripts/epic-status.sh" 2>&1); then
  # Parse epic count
  EPIC_COUNT=$(echo "$EPIC_JSON" | jq -r '.epics | length')

  if [[ $EPIC_COUNT -gt 0 ]]; then
    HAS_DATA=true
    echo "=== EPICS ($EPIC_COUNT active) ==="
    echo "| Epic | Progress | Checkpoints |"
    echo "|------|----------|-------------|"

    # Process each epic
    echo "$EPIC_JSON" | jq -r '.epics[] | "\(.name)|\(.progress)|\(.checkboxes)"' | while IFS='|' read -r name progress checkboxes; do
      # Extract checkbox states
      RESEARCH=$(echo "$checkboxes" | jq -r '.research_complete')
      ANALYSIS=$(echo "$checkboxes" | jq -r '.analysis_complete')
      DECOMPOSITION=$(echo "$checkboxes" | jq -r '.decomposition_complete')
      TICKETS=$(echo "$checkboxes" | jq -r '.tickets_created')

      # Determine next step
      NEXT_STEP=""
      if [[ "$RESEARCH" != "true" ]]; then
        NEXT_STEP="Research"
      elif [[ "$ANALYSIS" != "true" ]]; then
        NEXT_STEP="Analysis"
      elif [[ "$DECOMPOSITION" != "true" ]]; then
        NEXT_STEP="Decomposition"
      elif [[ "$TICKETS" != "true" ]]; then
        NEXT_STEP="Create Tickets"
      else
        NEXT_STEP="Complete"
      fi

      echo "| $name | $progress | $NEXT_STEP |"
    done
    echo ""
  else
    echo "=== EPICS ==="
    echo "No active epics. Use \`/sdd:start-epic [name]\` to create one."
    echo ""
  fi
else
  ERRORS="${ERRORS}Epic Status: Failed to load - ${EPIC_JSON}\n"
  echo "=== EPICS ==="
  echo "Error loading epic status. Check that epic overview.md files are valid."
  echo "Troubleshooting: Try /sdd:setup to initialize SDD environment"
  echo ""
fi
```

### Step 3: Gather Ticket Status

```bash
# Scan tickets directory for planning status
TICKETS_DIR="$SDD_ROOT_DIR/tickets"

if [[ -d "$TICKETS_DIR" ]]; then
  TICKET_DIRS=$(find "$TICKETS_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
  TICKET_COUNT=$(echo "$TICKET_DIRS" | grep -c . || echo "0")

  if [[ $TICKET_COUNT -gt 0 ]]; then
    HAS_DATA=true
    echo "=== TICKETS ($TICKET_COUNT active) ==="
    echo "| Ticket | Planning | Tasks | Status |"
    echo "|--------|----------|-------|--------|"

    while IFS= read -r TICKET_PATH; do
      [[ -z "$TICKET_PATH" ]] && continue

      TICKET_FOLDER=$(basename "$TICKET_PATH")

      # Extract ticket ID and name (format: TICKETID_name)
      if [[ "$TICKET_FOLDER" =~ ^([A-Z][A-Z0-9]*(-[A-Z0-9]+)*)_(.*)$ ]]; then
        TICKET_ID="${BASH_REMATCH[1]}"
        TICKET_NAME="${BASH_REMATCH[3]}"
      else
        continue
      fi

      # Check planning documents
      PLANNING_DIR="$TICKET_PATH/planning"
      SUBSTANTIVE_DOCS=0
      PLANNING_STATUS=""

      if [[ -d "$PLANNING_DIR" ]]; then
        for doc in analysis.md architecture.md plan.md quality-strategy.md; do
          DOC_PATH="$PLANNING_DIR/$doc"
          if [[ -f "$DOC_PATH" ]]; then
            DOC_SIZE=$(stat -c%s "$DOC_PATH" 2>/dev/null || echo "0")
            if [[ $DOC_SIZE -gt 500 ]]; then
              SUBSTANTIVE_DOCS=$((SUBSTANTIVE_DOCS + 1))
            fi
          fi
        done
      fi

      # Determine planning status
      if [[ $SUBSTANTIVE_DOCS -eq 4 ]]; then
        PLANNING_STATUS="Complete"
      elif [[ $SUBSTANTIVE_DOCS -gt 0 ]]; then
        PLANNING_STATUS="Partial"
      else
        PLANNING_STATUS="Missing"
      fi

      # Get task count (scan tasks directory)
      TASKS_DIR="$TICKET_PATH/tasks"
      TASK_COUNT=0
      VERIFIED_COUNT=0

      if [[ -d "$TASKS_DIR" ]]; then
        # Count task files
        TASK_FILES=$(find "$TASKS_DIR" -name "*.md" -type f 2>/dev/null | grep -E '[A-Z][A-Z0-9]*(-[A-Z0-9]+)*\.[0-9]+' || echo "")
        if [[ -n "$TASK_FILES" ]]; then
          TASK_COUNT=$(echo "$TASK_FILES" | wc -l | tr -d ' \n')
        else
          TASK_COUNT=0
        fi

        # Count verified tasks
        if [[ $TASK_COUNT -gt 0 ]]; then
          VERIFIED_COUNT=$(find "$TASKS_DIR" -name "*.md" -type f -exec grep -l '^\-[[:space:]]*\[x\][[:space:]]*\*\*Verified\*\*' {} \; 2>/dev/null | wc -l | tr -d ' \n')
        fi
      fi

      # Determine overall status
      TICKET_STATUS=""
      if [[ $TASK_COUNT -eq 0 ]]; then
        if [[ "$PLANNING_STATUS" == "Complete" ]]; then
          TICKET_STATUS="Ready for Tasks"
        else
          TICKET_STATUS="Needs Planning"
        fi
      elif [[ $VERIFIED_COUNT -eq $TASK_COUNT ]]; then
        TICKET_STATUS="Complete"
      else
        TICKET_STATUS="In Progress"
      fi

      echo "| $TICKET_ID | $PLANNING_STATUS | $VERIFIED_COUNT/$TASK_COUNT | $TICKET_STATUS |"
    done <<< "$TICKET_DIRS"
    echo ""
  else
    echo "=== TICKETS ==="
    echo "No active tickets. Use \`/sdd:plan-ticket [description]\` to create one."
    echo ""
  fi
else
  echo "=== TICKETS ==="
  echo "No tickets directory found. Use \`/sdd:setup\` to initialize."
  echo ""
fi
```

### Step 4: Gather Task Status

```bash
# Try to get task status for attention items
if TASK_JSON=$(bash "${PLUGIN_ROOT}/skills/project-workflow/scripts/task-status.sh" 2>&1); then
  HAS_DATA=true

  # Find tasks needing attention
  COMPLETED_UNVERIFIED=$(echo "$TASK_JSON" | jq -r '.tickets[].tasks[] | select(.status == "completed" or .status == "tested") | .ticket_id' 2>/dev/null || echo "")
  PENDING_TASKS=$(echo "$TASK_JSON" | jq -r '.tickets[].tasks[] | select(.status == "pending") | .ticket_id' 2>/dev/null || echo "")

  if [[ -n "$COMPLETED_UNVERIFIED" ]] || [[ -n "$PENDING_TASKS" ]]; then
    echo "=== TASKS NEEDING ATTENTION ==="

    if [[ -n "$COMPLETED_UNVERIFIED" ]]; then
      echo "Completed but not verified:"
      echo "$COMPLETED_UNVERIFIED" | while read -r task_id; do
        [[ -z "$task_id" ]] && continue
        echo "  - $task_id: Ready for verification"
      done
    fi

    if [[ -n "$PENDING_TASKS" ]]; then
      echo "Pending tasks:"
      echo "$PENDING_TASKS" | head -5 | while read -r task_id; do
        [[ -z "$task_id" ]] && continue
        echo "  - $task_id: Not started"
      done

      PENDING_COUNT=$(echo "$PENDING_TASKS" | grep -c . || echo "0")
      if [[ $PENDING_COUNT -gt 5 ]]; then
        echo "  ... and $((PENDING_COUNT - 5)) more"
      fi
    fi
    echo ""
  else
    # Check if there are any tasks at all
    TOTAL_TASKS=$(echo "$TASK_JSON" | jq -r '[.tickets[].tasks[]] | length' 2>/dev/null || echo "0")
    if [[ $TOTAL_TASKS -eq 0 ]]; then
      echo "=== TASKS ==="
      echo "No tasks found. Use \`/sdd:create-tasks TICKET_ID\` to generate tasks."
      echo ""
    else
      echo "=== TASKS ==="
      echo "All tasks are verified! Use \`/sdd:archive\` to review completed tickets."
      echo ""
    fi
  fi
else
  ERRORS="${ERRORS}Task Status: Failed to load - ${TASK_JSON}\n"
  echo "=== TASKS ==="
  echo "Error loading task status. Check that task files are valid."
  echo "Troubleshooting: Try /sdd:setup to initialize SDD environment"
  echo ""
fi
```

### Step 4.5: Tasks API Enhanced Status (Parallel Execution)

**This section provides real-time task status when Tasks API is enabled.**

```bash
# Check if Tasks API is enabled
TASKS_API_ENABLED="${SDD_TASKS_API_ENABLED:-true}"
CLAUDE_TASK_LIST_ID="${CLAUDE_TASK_LIST_ID:-}"

if [ "$TASKS_API_ENABLED" != "false" ] && [ -n "$CLAUDE_TASK_LIST_ID" ]; then
  echo "=== REAL-TIME TASK STATUS (Tasks API) ==="
  echo "Task List ID: $CLAUDE_TASK_LIST_ID"
  echo ""

  # Note: Tasks API queries should be performed via TaskList tool
  # The agent executing this command should query TaskList for real-time status
  # and display parallel execution information below
fi
```

**When Tasks API is available, query TaskList tool and display:**

If `SDD_TASKS_API_ENABLED` is not `false` and `CLAUDE_TASK_LIST_ID` is set, use the TaskList tool to get real-time task status. Format the output as follows:

**Parallel Execution Display:**

When parallel execution is active, show enhanced status with phase breakdown:

```
Ticket: {TICKET_ID} - {ticket_name}
Status: In Progress (Parallel Mode)

Phase 0: [STATUS] ([completed]/[total] tasks)
Phase 1: [STATUS] ([completed]/[total] tasks)
Phase 2: [STATUS] ([completed]/[total] tasks)
  [INDICATOR] {TASK_ID} - {task_summary} (STATUS)
  ...
Phase 3: [STATUS] ([completed]/[total] tasks)

Parallel Execution:
  {N} tasks running concurrently
  {M} tasks available for launch
```

**Task Status Indicators:**
- `>` IN PROGRESS: Task currently executing
- `*` BLOCKED: Task waiting for dependencies (show blockedBy IDs)
- `-` PENDING: Task ready but not started
- `+` COMPLETED: Task finished and verified

**Phase Status Indicators:**
- `[Complete]` All tasks in phase are verified
- `[In Progress]` Some tasks running or completed
- `[Blocked]` All tasks blocked by previous phase
- `[Pending]` All tasks pending, no blockers

**Example Output:**
```
Ticket: TASKINT - Claude Code Tasks Integration
Status: In Progress (Parallel Mode)

Phase 0: [Complete] (4/4 tasks)
Phase 1: [Complete] (5/5 tasks)
Phase 2: [In Progress] (2/4 tasks)
  > TASKINT.2001 - do-task integration (IN PROGRESS)
  > TASKINT.2002 - do-all-tasks integration (IN PROGRESS)
  * TASKINT.2003 - workflow-guidance update (BLOCKED by 2001, 2002)
  - TASKINT.2004 - task-creator update (PENDING)
Phase 3: [Blocked] (0/5 tasks started)

Parallel Execution:
  2 tasks running concurrently
  2 tasks available for launch
```

**Fallback Behavior:**

If `SDD_TASKS_API_ENABLED=false` or `CLAUDE_TASK_LIST_ID` is not set:
- Use file inspection only (Steps 3-4 above)
- Do not show parallel execution information
- Show traditional status output

**Implementation Notes:**
- The agent executing this command should use the TaskList tool when available
- Parse task metadata for phase information (stored in task descriptions or metadata)
- Calculate concurrent task count from tasks with status `in_progress`
- Calculate available tasks as `pending` tasks with no `blockedBy` dependencies
- Group tasks by phase number extracted from task ID (e.g., TASKINT.2001 = Phase 2)

### Step 5: Generate Recommended Actions

```bash
# Generate recommended actions based on current state
echo "RECOMMENDED ACTIONS:"

ACTION_COUNT=0

# Priority 1: Tasks ready for verification
if [[ -n "$COMPLETED_UNVERIFIED" ]]; then
  FIRST_UNVERIFIED=$(echo "$COMPLETED_UNVERIFIED" | head -1)
  if [[ -n "$FIRST_UNVERIFIED" ]]; then
    ACTION_COUNT=$((ACTION_COUNT + 1))
    echo "$ACTION_COUNT. /sdd:do-task $FIRST_UNVERIFIED - Verify completed work"
  fi
fi

# Priority 2: Pending tasks
if [[ -n "$PENDING_TASKS" ]]; then
  FIRST_PENDING=$(echo "$PENDING_TASKS" | head -1)
  if [[ -n "$FIRST_PENDING" ]] && [[ $ACTION_COUNT -lt 3 ]]; then
    ACTION_COUNT=$((ACTION_COUNT + 1))
    echo "$ACTION_COUNT. /sdd:do-task $FIRST_PENDING - Start pending task"
  fi
fi

# Priority 3: Tickets needing task creation
if [[ -n "$TICKET_DIRS" ]]; then
  while IFS= read -r TICKET_PATH; do
    [[ -z "$TICKET_PATH" ]] || [[ $ACTION_COUNT -ge 3 ]] && continue

    TICKET_FOLDER=$(basename "$TICKET_PATH")
    if [[ "$TICKET_FOLDER" =~ ^([A-Z][A-Z0-9]*(-[A-Z0-9]+)*)_(.*)$ ]]; then
      TICKET_ID="${BASH_REMATCH[1]}"

      PLANNING_DIR="$TICKET_PATH/planning"
      TASKS_DIR="$TICKET_PATH/tasks"

      # Check if planning is complete but no tasks
      SUBSTANTIVE_DOCS=0
      if [[ -d "$PLANNING_DIR" ]]; then
        for doc in analysis.md architecture.md plan.md quality-strategy.md; do
          DOC_PATH="$PLANNING_DIR/$doc"
          if [[ -f "$DOC_PATH" ]]; then
            DOC_SIZE=$(stat -c%s "$DOC_PATH" 2>/dev/null || echo "0")
            if [[ $DOC_SIZE -gt 500 ]]; then
              SUBSTANTIVE_DOCS=$((SUBSTANTIVE_DOCS + 1))
            fi
          fi
        done
      fi

      TASK_COUNT=0
      if [[ -d "$TASKS_DIR" ]]; then
        TASK_FILES=$(find "$TASKS_DIR" -name "*.md" -type f 2>/dev/null | grep -E '[A-Z][A-Z0-9]*(-[A-Z0-9]+)*\.[0-9]+' || echo "")
        if [[ -n "$TASK_FILES" ]]; then
          TASK_COUNT=$(echo "$TASK_FILES" | wc -l | tr -d ' \n')
        fi
      fi

      if [[ $SUBSTANTIVE_DOCS -eq 4 ]] && [[ $TASK_COUNT -eq 0 ]]; then
        ACTION_COUNT=$((ACTION_COUNT + 1))
        echo "$ACTION_COUNT. /sdd:create-tasks $TICKET_ID - Generate tasks from planning"
      fi
    fi
  done <<< "$TICKET_DIRS"
fi

# Priority 4: Tickets needing planning completion
if [[ -n "$TICKET_DIRS" ]]; then
  while IFS= read -r TICKET_PATH; do
    [[ -z "$TICKET_PATH" ]] || [[ $ACTION_COUNT -ge 5 ]] && continue

    TICKET_FOLDER=$(basename "$TICKET_PATH")
    if [[ "$TICKET_FOLDER" =~ ^([A-Z][A-Z0-9]*(-[A-Z0-9]+)*)_(.*)$ ]]; then
      TICKET_ID="${BASH_REMATCH[1]}"

      PLANNING_DIR="$TICKET_PATH/planning"

      # Check if planning is incomplete
      SUBSTANTIVE_DOCS=0
      if [[ -d "$PLANNING_DIR" ]]; then
        for doc in analysis.md architecture.md plan.md quality-strategy.md; do
          DOC_PATH="$PLANNING_DIR/$doc"
          if [[ -f "$DOC_PATH" ]]; then
            DOC_SIZE=$(stat -c%s "$DOC_PATH" 2>/dev/null || echo "0")
            if [[ $DOC_SIZE -gt 500 ]]; then
              SUBSTANTIVE_DOCS=$((SUBSTANTIVE_DOCS + 1))
            fi
          fi
        done
      fi

      if [[ $SUBSTANTIVE_DOCS -gt 0 ]] && [[ $SUBSTANTIVE_DOCS -lt 4 ]]; then
        ACTION_COUNT=$((ACTION_COUNT + 1))
        echo "$ACTION_COUNT. /sdd:update $TICKET_ID - Complete planning documents"
      fi
    fi
  done <<< "$TICKET_DIRS"
fi

# Priority 5: Epic checkpoints
if [[ -n "$EPIC_JSON" ]]; then
  echo "$EPIC_JSON" | jq -r '.epics[] | select(.progress != "4/4") | .name' 2>/dev/null | head -1 | while read -r epic_name; do
    [[ -z "$epic_name" ]] || [[ $ACTION_COUNT -ge 5 ]] && continue
    ACTION_COUNT=$((ACTION_COUNT + 1))
    echo "$ACTION_COUNT. /sdd:start-epic $epic_name - Continue epic checkpoint progress"
  done
fi

# If no actions, suggest starting something new
if [[ $ACTION_COUNT -eq 0 ]]; then
  if [[ "$HAS_DATA" == "true" ]]; then
    echo "No immediate actions needed. Consider:"
    echo "  - /sdd:archive - Archive completed tickets"
    echo "  - /sdd:start-epic [name] - Begin new research epic"
    echo "  - /sdd:plan-ticket [description] - Create new ticket"
  else
    echo "1. /sdd:setup - Initialize SDD environment"
    echo "2. /sdd:start-epic [name] - Begin with epic-level research"
    echo "3. /sdd:plan-ticket [description] - Or jump straight to a ticket"
  fi
fi

echo ""
```

### Step 6: Display Discoverability Tip

```bash
echo "Tip: For focused views, use /sdd:tasks-status, /sdd:tickets-status, or /sdd:epics-status"
```

### Step 7: Show Errors Summary (if any)

```bash
if [[ -n "$ERRORS" ]]; then
  echo ""
  echo "=== ERRORS ENCOUNTERED ==="
  echo -e "$ERRORS"
  echo "Some data could not be loaded. Check the troubleshooting hints above."
fi
```

## Key Constraints

- **Graceful degradation**: If one tier fails, continue with others
- **Never fail entirely** if at least one tier succeeds
- **Clear error messages** with troubleshooting hints
- **Actionable recommendations** with specific command syntax
- **Concise output** suitable for quick scanning
- **Empty state handling** for each tier independently
- **Linux stat syntax**: Use `stat -c%s` not macOS `stat -f%z`

## Output Format

The command produces a comprehensive overview with clear sections:
- Epic progress with checkpoint status
- Ticket planning and task counts
- Tasks needing immediate attention
- Prioritized recommended actions
- Discoverability tip for specialized commands
- Error summary if partial failures occurred
