---
description: Mark a ticket as ready for autonomous agent execution
argument-hint: TICKET_ID [--priority N]
---

# Mark Ready Command

## Context

Ticket ID: $ARGUMENTS

This command marks a ticket as ready for autonomous agent execution by creating or updating the `.autogate.json` file in the ticket directory. It sets `agent_ready: true` and records the timestamp when the ticket was marked.

## Workflow

### Step 1: Validate Ticket and Parse Arguments

```bash
SDD_ROOT="${SDD_ROOT_DIR:-/app/.sdd}"

# Parse TICKET_ID from first argument
TICKET_ID=$(echo "$ARGUMENTS" | awk '{print $1}')

if [ -z "$TICKET_ID" ]; then
    echo "Error: TICKET_ID is required"
    echo "Usage: /sdd:mark-ready TICKET_ID [--priority N]"
    exit 1
fi

# Find ticket directory
TICKET_DIR=$(find "$SDD_ROOT/tickets" -maxdepth 1 -type d -name "${TICKET_ID}_*" 2>/dev/null | head -n1)

if [ -z "$TICKET_DIR" ]; then
    echo "Error: Ticket $TICKET_ID not found"
    echo "Usage: /sdd:mark-ready TICKET_ID [--priority N]"
    exit 1
fi

# Parse priority parameter
PRIORITY="null"
PRIORITY_ARG=$(echo "$ARGUMENTS" | grep -oE '\-\-priority[[:space:]]+[0-9]+' | awk '{print $2}')
PRIORITY_INVALID=$(echo "$ARGUMENTS" | grep -oE '\-\-priority[[:space:]]+[^0-9[:space:]][^[:space:]]*' | awk '{print $2}')

if [ -n "$PRIORITY_INVALID" ]; then
    echo "Error: Priority must be a non-negative integer: $PRIORITY_INVALID"
    echo "Usage: /sdd:mark-ready TICKET_ID [--priority N]"
    exit 1
fi

if [ -n "$PRIORITY_ARG" ]; then
    PRIORITY="$PRIORITY_ARG"
fi

# Read existing or start with empty object
AUTOGATE_FILE="$TICKET_DIR/.autogate.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

EXISTING="{}"
if [ -f "$AUTOGATE_FILE" ]; then
    EXISTING=$(cat "$AUTOGATE_FILE")
fi

# Merge fields using jq (preserves existing fields like ready, stop_at_phase)
TEMP_FILE=$(mktemp)
echo "$EXISTING" | jq \
    --argjson agent_ready true \
    --argjson priority $PRIORITY \
    --arg marked_at "$TIMESTAMP" \
    '. + {agent_ready: $agent_ready, priority: $priority, marked_at: $marked_at}' \
    > "$TEMP_FILE"

# Atomic rename
mv "$TEMP_FILE" "$AUTOGATE_FILE"

# Success output
echo "Ticket $TICKET_ID marked as agent-ready"
echo ""
cat "$AUTOGATE_FILE"
```

## Usage Examples

```bash
# Mark ticket as agent-ready (no priority)
/sdd:mark-ready PROJ-123

# Mark ticket with priority 1 (highest)
/sdd:mark-ready PROJ-123 --priority 1

# Mark ticket with lower priority
/sdd:mark-ready PROJ-123 --priority 5
```

## Error Cases

- **Missing TICKET_ID**: Shows usage help
- **Ticket not found**: Shows error with ticket ID
- **Invalid priority**: Shows error if priority is not a non-negative integer
