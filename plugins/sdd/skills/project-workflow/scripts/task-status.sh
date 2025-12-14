#!/usr/bin/env bash
#
# Task Status Scanner
# Scans task files and returns checkbox status as JSON
#
# Usage:
#   bash task-status.sh <TICKET_ID>      # Specific ticket
#   bash task-status.sh                  # All tickets
#
# Output:
#   JSON array of task statuses

set -euo pipefail

SDD_ROOT_DIR="${SDD_ROOT_DIR:-/app/.sdd}"

# Extract task info from file
scan_task() {
    local file="$1"
    local filename=$(basename "$file")
    local ticket_id=""
    local title=""
    local task_completed="false"
    local tests_pass="false"
    local verified="false"

    # Extract task ID from filename (e.g., TICKET_ID.1001_description.md)
    # Supports both PROJ.1001 and UIT-9819.1001 (Jira-style) formats
    if [[ "$filename" =~ ^([A-Z][A-Z0-9]*(-[A-Z0-9]+)*\.[0-9]+) ]]; then
        ticket_id="${BASH_REMATCH[1]}"
    fi

    # Extract title from file
    title=$(grep -m1 '^# Task:' "$file" 2>/dev/null | sed 's/^# Task:[[:space:]]*//' || echo "")

    # Check checkbox states using grep - match only actual checkbox lines starting with dash
    local verified_count=$(grep -c '^-[[:space:]]*\[x\][[:space:]]*\*\*Verified\*\*\|^-[[:space:]]*\[X\][[:space:]]*\*\*Verified\*\*' "$file" 2>/dev/null || true)
    local tests_count=$(grep -c '^-[[:space:]]*\[x\][[:space:]]*\*\*Tests pass\*\*\|^-[[:space:]]*\[X\][[:space:]]*\*\*Tests pass\*\*' "$file" 2>/dev/null || true)
    local completed_count=$(grep -c '^-[[:space:]]*\[x\][[:space:]]*\*\*Task completed\*\*\|^-[[:space:]]*\[X\][[:space:]]*\*\*Task completed\*\*' "$file" 2>/dev/null || true)

    # Convert counts to boolean (handle empty/0 cases)
    if [[ -n "$verified_count" ]] && [[ $verified_count -gt 0 ]]; then
        verified="true"
    fi
    if [[ -n "$tests_count" ]] && [[ $tests_count -gt 0 ]]; then
        tests_pass="true"
    fi
    if [[ -n "$completed_count" ]] && [[ $completed_count -gt 0 ]]; then
        task_completed="true"
    fi

    # Determine overall status
    local status="pending"
    if [[ "$verified" == "true" ]]; then
        status="verified"
    elif [[ "$tests_pass" == "true" ]]; then
        status="tested"
    elif [[ "$task_completed" == "true" ]]; then
        status="completed"
    fi

    # Output JSON object
    cat << EOF
    {
      "ticket_id": "$ticket_id",
      "file": "$file",
      "title": "$title",
      "status": "$status",
      "checkboxes": {
        "task_completed": $task_completed,
        "tests_pass": $tests_pass,
        "verified": $verified
      }
    }
EOF
}

# Scan all tasks in a ticket
scan_ticket_tasks() {
    local ticket_path="$1"
    local ticket_name=$(basename "$ticket_path")
    local tasks_dir="$ticket_path/tasks"
    local first=true

    if [[ ! -d "$tasks_dir" ]]; then
        return
    fi

    # Find all task files (supports PROJ.1001 and UIT-9819.1001 formats)
    local task_files=$(find "$tasks_dir" -name "*.md" -type f 2>/dev/null | grep -E '[A-Z][A-Z0-9]*(-[A-Z0-9]+)*\.[0-9]+' | sort)

    if [[ -z "$task_files" ]]; then
        return
    fi

    echo "  {"
    echo "    \"ticket\": \"$ticket_name\","
    echo "    \"path\": \"$ticket_path\","
    echo "    \"tasks\": ["

    while IFS= read -r file; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        scan_task "$file"
    done <<< "$task_files"

    echo "    ]"
    echo "  }"
}

# Main execution
main() {
    local ticket_id="${1:-}"
    local first=true

    echo "{"
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"tickets\": ["

    if [[ -n "$ticket_id" ]]; then
        # Scan specific ticket
        local ticket_path=$(find "$SDD_ROOT_DIR/tickets" -maxdepth 1 -type d -name "${ticket_id}_*" 2>/dev/null | head -1)
        if [[ -n "$ticket_path" ]]; then
            scan_ticket_tasks "$ticket_path"
        else
            echo "    {\"error\": \"Ticket not found: $ticket_id\"}"
        fi
    else
        # Scan all tickets
        for ticket_path in "$SDD_ROOT_DIR/tickets"/*; do
            if [[ -d "$ticket_path" ]]; then
                if [[ "$first" == "true" ]]; then
                    first=false
                else
                    echo ","
                fi
                scan_ticket_tasks "$ticket_path"
            fi
        done
    fi

    echo "  ]"
    echo "}"
}

main "$@"
