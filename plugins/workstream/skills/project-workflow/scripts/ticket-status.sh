#!/usr/bin/env bash
#
# Ticket Status Scanner
# Scans ticket files and returns checkbox status as JSON
#
# Usage:
#   bash ticket-status.sh <SLUG>           # Specific project
#   bash ticket-status.sh                  # All projects
#
# Output:
#   JSON array of ticket statuses

set -euo pipefail

CREWCHIEF_DIR="${CREWCHIEF_DIR:-.crewchief}"

# Parse checkbox state from line
parse_checkbox() {
    local line="$1"
    if [[ "$line" =~ \[x\] ]] || [[ "$line" =~ \[X\] ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# Extract ticket info from file
scan_ticket() {
    local file="$1"
    local filename=$(basename "$file")
    local ticket_id=""
    local title=""
    local task_completed="false"
    local tests_pass="false"
    local verified="false"

    # Extract ticket ID from filename (e.g., SLUG-1001_description.md)
    if [[ "$filename" =~ ^([A-Z]+-[0-9]+) ]]; then
        ticket_id="${BASH_REMATCH[1]}"
    fi

    # Read file and extract info
    while IFS= read -r line; do
        # Extract title
        if [[ "$line" =~ ^#[[:space:]]+Ticket:[[:space:]]*(.*) ]]; then
            title="${BASH_REMATCH[1]}"
        fi
        # Check for Task completed
        if [[ "$line" =~ Task[[:space:]]+completed ]] || [[ "$line" =~ \*\*Task[[:space:]]+completed\*\* ]]; then
            task_completed=$(parse_checkbox "$line")
        fi
        # Check for Tests pass
        if [[ "$line" =~ Tests[[:space:]]+pass ]] || [[ "$line" =~ \*\*Tests[[:space:]]+pass\*\* ]]; then
            tests_pass=$(parse_checkbox "$line")
        fi
        # Check for Verified
        if [[ "$line" =~ Verified ]] && [[ "$line" =~ verify-ticket ]]; then
            verified=$(parse_checkbox "$line")
        fi
    done < "$file"

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

# Scan all tickets in a project
scan_project() {
    local project_path="$1"
    local project_name=$(basename "$project_path")
    local tickets_dir="$project_path/tickets"
    local first=true

    if [[ ! -d "$tickets_dir" ]]; then
        return
    fi

    # Find all ticket files
    local ticket_files=$(find "$tickets_dir" -name "*.md" -type f 2>/dev/null | grep -E '[A-Z]+-[0-9]+' | sort)

    if [[ -z "$ticket_files" ]]; then
        return
    fi

    echo "  {"
    echo "    \"project\": \"$project_name\","
    echo "    \"path\": \"$project_path\","
    echo "    \"tickets\": ["

    while IFS= read -r file; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        scan_ticket "$file"
    done <<< "$ticket_files"

    echo "    ]"
    echo "  }"
}

# Main execution
main() {
    local slug="${1:-}"
    local first=true

    echo "{"
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"projects\": ["

    if [[ -n "$slug" ]]; then
        # Scan specific project
        local project_path=$(find "$CREWCHIEF_DIR/projects" -maxdepth 1 -type d -name "${slug}_*" 2>/dev/null | head -1)
        if [[ -n "$project_path" ]]; then
            scan_project "$project_path"
        else
            echo "    {\"error\": \"Project not found: $slug\"}"
        fi
    else
        # Scan all projects
        for project_path in "$CREWCHIEF_DIR/projects"/*; do
            if [[ -d "$project_path" ]]; then
                if [[ "$first" == "true" ]]; then
                    first=false
                else
                    echo ","
                fi
                scan_project "$project_path"
            fi
        done
    fi

    echo "  ]"
    echo "}"
}

main "$@"
