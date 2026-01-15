---
description: Remove agent-ready status from a ticket
argument-hint: TICKET_ID
---

# Unmark Ready Command

## Context

Ticket ID: $ARGUMENTS

This command removes agent-ready status from a ticket by updating the `.autogate.json` file in the ticket directory. It sets `agent_ready: false`, clears the priority, and records the timestamp. Other fields like `ready` and `stop_at_phase` are preserved.

## Workflow

### Step 1: Validate Ticket and Update Autogate

```bash
SDD_ROOT="${SDD_ROOT_DIR:-/app/.sdd}"

# Parse TICKET_ID from first argument
TICKET_ID=$(echo "$ARGUMENTS" | awk '{print $1}')

if [ -z "$TICKET_ID" ]; then
    echo "Error: TICKET_ID is required"
    echo "Usage: /sdd:unmark-ready TICKET_ID"
    exit 1
fi

# Find ticket directory
TICKET_DIR=$(find "$SDD_ROOT/tickets" -maxdepth 1 -type d -name "${TICKET_ID}_*" 2>/dev/null | head -n1)

if [ -z "$TICKET_DIR" ]; then
    echo "Error: Ticket $TICKET_ID not found"
    echo "Usage: /sdd:unmark-ready TICKET_ID"
    exit 1
fi

# Read existing or start with empty object
AUTOGATE_FILE="$TICKET_DIR/.autogate.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

EXISTING="{}"
if [ -f "$AUTOGATE_FILE" ]; then
    EXISTING=$(cat "$AUTOGATE_FILE")
fi

# Update: agent_ready=false, priority=null, marked_at=timestamp
TEMP_FILE=$(mktemp)
echo "$EXISTING" | jq \
    --argjson agent_ready false \
    --argjson priority null \
    --arg marked_at "$TIMESTAMP" \
    '. + {agent_ready: $agent_ready, priority: $priority, marked_at: $marked_at}' \
    > "$TEMP_FILE"

# Atomic rename
mv "$TEMP_FILE" "$AUTOGATE_FILE"

# Success output
echo "Ticket $TICKET_ID unmarked (agent_ready: false)"
echo ""
cat "$AUTOGATE_FILE"
```

## Usage Examples

```bash
# Remove agent-ready status from ticket
/sdd:unmark-ready PROJ-123

# Idempotent: Running on already-unmarked ticket succeeds
/sdd:unmark-ready PROJ-123
```

## Error Cases

- **Missing TICKET_ID**: Shows usage help
- **Ticket not found**: Shows error with ticket ID
