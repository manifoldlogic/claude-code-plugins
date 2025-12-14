---
description: Display ticket-level status showing planning docs and task progress
argument-hint: [TICKET_ID or empty for all]
---

# Tickets Status Check

## Context

Ticket: $ARGUMENTS (optional - if empty, shows all tickets)

## Workflow

**IMPORTANT: Use scripts for task aggregation, inline bash for planning doc scanning.**

### Step 1: Gather Ticket Data

**Get list of ticket directories:**

```bash
SDD_ROOT_DIR="${SDD_ROOT_DIR:-/app/.sdd}"
TICKET_ID="${ARGUMENTS}"

# Get ticket directories
if [[ -n "$TICKET_ID" ]]; then
  # Specific ticket
  TICKET_DIRS=$(find "$SDD_ROOT_DIR/tickets" -maxdepth 1 -type d -name "${TICKET_ID}_*" 2>/dev/null)
else
  # All tickets
  TICKET_DIRS=$(find "$SDD_ROOT_DIR/tickets" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
fi

# Check if any tickets found
if [[ -z "$TICKET_DIRS" ]]; then
  echo "No active tickets found."
  echo ""
  echo "Use /sdd:plan-ticket [description] to create one."
  exit 0
fi
```

### Step 2: Gather Task Status

**Run task status script for all tickets or specific ticket:**

```bash
TASK_JSON=$(bash ${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/scripts/task-status.sh ${ARGUMENTS})
```

This returns JSON with:
- Ticket names and paths
- Tasks per ticket
- Checkbox states (completed, tested, verified)

### Step 3: Process Each Ticket

**For each ticket directory, gather planning and task data:**

```bash
echo "=== TICKETS STATUS ==="
echo ""

while IFS= read -r TICKET_PATH; do
  TICKET_FOLDER=$(basename "$TICKET_PATH")

  # Extract ticket ID and name (format: TICKETID_name)
  if [[ "$TICKET_FOLDER" =~ ^([A-Z][A-Z0-9]*(-[A-Z0-9]+)*)_(.*)$ ]]; then
    TICKET_ID="${BASH_REMATCH[1]}"
    TICKET_NAME="${BASH_REMATCH[3]}"
  else
    continue
  fi

  echo "Ticket: $TICKET_ID ($TICKET_NAME)"

  # Check planning documents
  PLANNING_DIR="$TICKET_PATH/planning"
  PLANNING_DOCS=("analysis.md" "architecture.md" "plan.md" "quality-strategy.md")
  SUBSTANTIVE_DOCS=0
  PLANNING_STATUS=""

  if [[ -d "$PLANNING_DIR" ]]; then
    for doc in "${PLANNING_DOCS[@]}"; do
      DOC_PATH="$PLANNING_DIR/$doc"
      if [[ -f "$DOC_PATH" ]]; then
        # Check if substantive (>500 bytes) - use Linux stat syntax
        DOC_SIZE=$(stat -c%s "$DOC_PATH" 2>/dev/null || echo "0")
        if [[ $DOC_SIZE -gt 500 ]]; then
          SUBSTANTIVE_DOCS=$((SUBSTANTIVE_DOCS + 1))
          PLANNING_STATUS="${PLANNING_STATUS}  ✓ ${doc}\n"
        else
          PLANNING_STATUS="${PLANNING_STATUS}  ☐ ${doc} (template only)\n"
        fi
      else
        PLANNING_STATUS="${PLANNING_STATUS}  ☐ ${doc} (missing)\n"
      fi
    done

    if [[ $SUBSTANTIVE_DOCS -eq 4 ]]; then
      echo "Planning: Complete (4/4 docs substantive)"
    elif [[ $SUBSTANTIVE_DOCS -gt 0 ]]; then
      echo "Planning: Partial ($SUBSTANTIVE_DOCS/4 docs substantive)"
    else
      echo "Planning: Missing (no substantive docs)"
    fi
    echo -e "$PLANNING_STATUS"
  else
    echo "Planning: Missing (no planning directory)"
    echo ""
  fi

  # Extract task counts from JSON for this ticket
  # Parse the JSON to find task counts for this ticket
  TICKET_TASKS=$(echo "$TASK_JSON" | jq -r ".tickets[] | select(.ticket == \"$TICKET_FOLDER\")")

  if [[ -n "$TICKET_TASKS" ]]; then
    TOTAL_TASKS=$(echo "$TICKET_TASKS" | jq '.tasks | length')
    VERIFIED_TASKS=$(echo "$TICKET_TASKS" | jq '[.tasks[] | select(.status == "verified")] | length')
    PENDING_TASKS=$(echo "$TICKET_TASKS" | jq '[.tasks[] | select(.status == "pending")] | length')

    if [[ $TOTAL_TASKS -eq 0 ]]; then
      echo "Tasks: 0 created"
      TICKET_STATUS="Planning (ready for task creation)"
    else
      VERIFIED_PCT=$((VERIFIED_TASKS * 100 / TOTAL_TASKS))
      echo "Tasks: $VERIFIED_TASKS/$TOTAL_TASKS verified (${VERIFIED_PCT}%)"

      # Determine status
      if [[ $VERIFIED_TASKS -eq $TOTAL_TASKS ]]; then
        TICKET_STATUS="Complete (ready for archival)"
      elif [[ $VERIFIED_TASKS -gt 0 ]] || [[ $PENDING_TASKS -lt $TOTAL_TASKS ]]; then
        TICKET_STATUS="In Progress"

        # Find next task needing attention
        NEXT_TASK=$(echo "$TICKET_TASKS" | jq -r '[.tasks[] | select(.status != "verified")] | .[0] | .ticket_id' 2>/dev/null || echo "")
        if [[ -n "$NEXT_TASK" ]]; then
          NEXT_STATUS=$(echo "$TICKET_TASKS" | jq -r "[.tasks[] | select(.ticket_id == \"$NEXT_TASK\")] | .[0] | .status")
          if [[ "$NEXT_STATUS" == "tested" ]] || [[ "$NEXT_STATUS" == "completed" ]]; then
            TICKET_STATUS="$TICKET_STATUS\n  Next: $NEXT_TASK ready for verification"
          else
            TICKET_STATUS="$TICKET_STATUS\n  Next: $NEXT_TASK pending"
          fi
        fi
      else
        TICKET_STATUS="In Progress"
      fi

      echo -e "Status: $TICKET_STATUS"
    fi
  else
    echo "Tasks: 0 created"
    if [[ $SUBSTANTIVE_DOCS -eq 4 ]]; then
      echo "Status: Planning (ready for task creation)"
    elif [[ $SUBSTANTIVE_DOCS -gt 0 ]]; then
      echo "Status: Planning (complete planning docs first)"
    else
      echo "Status: Needs Planning"
    fi
  fi

  echo ""
done <<< "$TICKET_DIRS"
```

### Step 4: Format Output

**Output format for each ticket:**

```
Ticket: STATCMD (status-command-restructure)
Planning: Complete (4/4 docs substantive)
  ✓ analysis.md
  ✓ architecture.md
  ✓ plan.md
  ✓ quality-strategy.md
Tasks: 0 created
Status: Planning (ready for task creation)

Ticket: APIV2 (api-v2-implementation)
Planning: Complete (4/4 docs substantive)
  ✓ analysis.md
  ✓ architecture.md
  ✓ plan.md
  ✓ quality-strategy.md
Tasks: 6/10 verified (60%)
Status: In Progress
  Next: APIV2.2003 ready for verification
```

**Empty state message:**

```
No active tickets found.

Use /sdd:plan-ticket [description] to create one.
```

### Step 5: Error Handling

**If task-status.sh fails:**

```
Error: Failed to retrieve task status.

Check that:
- SDD_ROOT_DIR is set correctly (default: /app/.sdd)
- Ticket directories exist in ${SDD_ROOT_DIR}/tickets/
- Task files are present in tasks/ subdirectories

Try: /sdd:setup to initialize SDD environment
```

**If specific ticket not found:**

```
No active tickets found.

Use /sdd:plan-ticket [description] to create one.
```

## Status Classification

- **Needs Planning**: Missing or incomplete planning docs (<4 substantive docs)
- **Planning**: Has planning docs but no tasks (ready for task creation)
- **In Progress**: Has tasks, some verified, some pending
- **Complete**: All tasks verified (ready for archival)

## Output Symbols

- Use ✓ for substantive docs (>500 bytes)
- Use ☐ for missing or template-only docs

## Key Constraints

- Use task-status.sh for task aggregation (don't scan task files manually)
- Use inline bash for planning doc checks (simple stat operations)
- Use Linux stat syntax: `stat -c%s` (not macOS `stat -f%z`)
- Keep reports concise and scannable
- Show clear progress indicators
- Display actionable next steps for empty states
- Handle missing planning directories gracefully
