#!/usr/bin/env bash
# Module: jira-adapter
# Status: STUB - to be implemented in ASDW-4

set -euo pipefail

fetch_tickets() {
    # shellcheck disable=SC2034  # Unused in stub, will be used in ASDW-4
    local input_type="${1:-}"
    # shellcheck disable=SC2034  # Unused in stub, will be used in ASDW-4
    local input_value="${2:-}"

    cat << EOF
{
  "success": true,
  "result": {
    "tickets": [
      {"key": "UIT-3607", "summary": "Mock Ticket 1", "status": "To Do"},
      {"key": "UIT-3608", "summary": "Mock Ticket 2", "status": "To Do"}
    ],
    "count": 2
  },
  "next_action": "proceed",
  "error": null
}
EOF
}

get_ticket_details() {
    local ticket_key="${1:-}"

    cat << EOF
{
  "success": true,
  "result": {
    "key": "$ticket_key",
    "summary": "Mock ticket details for $ticket_key",
    "description": "This is a stub implementation",
    "status": "To Do",
    "assignee": "unassigned"
  },
  "next_action": "proceed",
  "error": null
}
EOF
}
