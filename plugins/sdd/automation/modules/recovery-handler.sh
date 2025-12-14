#!/usr/bin/env bash
# Module: recovery-handler
# Status: STUB - to be implemented in ASDW-3

set -euo pipefail

retry_with_backoff() {
    local command="${1:-}"
    # shellcheck disable=SC2034  # Unused in stub, will be used in ASDW-3
    local max_attempts="${2:-3}"

    cat << EOF
{
  "success": true,
  "result": {
    "message": "STUB: retry_with_backoff called for command",
    "attempts": 1,
    "command": "$command"
  },
  "next_action": "proceed",
  "error": null
}
EOF
}

handle_error() {
    local error_code="${1:-0}"
    # shellcheck disable=SC2034  # Unused in stub, will be used in ASDW-3
    local context="${2:-}"

    cat << EOF
{
  "success": true,
  "result": {
    "message": "STUB: handle_error called with code $error_code",
    "recovery_action": "retry"
  },
  "next_action": "retry",
  "error": null
}
EOF
}
