#!/usr/bin/env bash
#
# Structure Validator
# Validates ticket/task structure and reports issues
#
# Usage:
#   bash validate-structure.sh <TICKET_ID> # Validate specific ticket
#   bash validate-structure.sh             # Validate all tickets
#
# Output:
#   JSON validation report

set -euo pipefail

SDD_ROOT_DIR="${SDD_ROOT_DIR:-/app/.sdd}"

# Required planning files
REQUIRED_PLANNING_FILES=(
    "analysis.md"
    "architecture.md"
    "plan.md"
    "quality-strategy.md"
    "security-review.md"
)

# Required ticket sections
REQUIRED_TICKET_SECTIONS=(
    "Status"
    "Summary"
    "Acceptance Criteria"
)

# Validate ticket structure
validate_ticket() {
    local ticket_path="$1"
    local ticket_name=$(basename "$ticket_path")
    local issues=()
    local warnings=()

    # Check README exists
    if [[ ! -f "$ticket_path/README.md" ]]; then
        issues+=("Missing README.md")
    fi

    # Check planning directory
    if [[ ! -d "$ticket_path/planning" ]]; then
        issues+=("Missing planning/ directory")
    else
        # Check required planning files
        for file in "${REQUIRED_PLANNING_FILES[@]}"; do
            if [[ ! -f "$ticket_path/planning/$file" ]]; then
                issues+=("Missing planning/$file")
            elif [[ ! -s "$ticket_path/planning/$file" ]]; then
                warnings+=("Empty planning/$file")
            fi
        done
    fi

    # Check tasks directory
    if [[ ! -d "$ticket_path/tasks" ]]; then
        issues+=("Missing tasks/ directory")
    else
        # Count tasks
        local task_count=$(find "$ticket_path/tasks" -name "*.md" -type f 2>/dev/null | wc -l)
        if [[ $task_count -eq 0 ]]; then
            warnings+=("No tasks in tasks/ directory")
        fi
    fi

    # Extract TICKET_ID from folder name (supports PROJ and UIT-9819 formats)
    local ticket_id=""
    if [[ "$ticket_name" =~ ^([A-Z][A-Z0-9]*(-[A-Z0-9]+)*)_ ]]; then
        ticket_id="${BASH_REMATCH[1]}"
    else
        issues+=("Invalid ticket folder name format (expected TICKET_ID_name)")
    fi

    # Validate folder name format (supports Jira-style IDs like UIT-9819)
    if [[ ! "$ticket_name" =~ ^[A-Z][A-Z0-9]*(-[A-Z0-9]+)*_[a-z][a-z0-9-]*$ ]]; then
        warnings+=("Folder name may not follow naming convention")
    fi

    # Output validation result
    local valid="true"
    if [[ ${#issues[@]} -gt 0 ]]; then
        valid="false"
    fi

    echo "  {"
    echo "    \"ticket\": \"$ticket_name\","
    echo "    \"path\": \"$ticket_path\","
    echo "    \"ticket_id\": \"$ticket_id\","
    echo "    \"valid\": $valid,"
    echo "    \"issues\": ["
    local first=true
    for issue in "${issues[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        echo "      \"$issue\""
    done
    echo "    ],"
    echo "    \"warnings\": ["
    first=true
    for warning in "${warnings[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        echo "      \"$warning\""
    done
    echo "    ]"
    echo "  }"
}

# Validate task file structure
validate_task() {
    local file="$1"
    local filename=$(basename "$file")
    local issues=()
    local warnings=()

    # Check filename format (supports PROJ.1001 and UIT-9819.1001 formats)
    if [[ ! "$filename" =~ ^[A-Z][A-Z0-9]*(-[A-Z0-9]+)*\.[0-9]+_.*\.md$ ]]; then
        issues+=("Invalid task filename format")
    fi

    # Check required sections
    local content=$(cat "$file")
    for section in "${REQUIRED_TICKET_SECTIONS[@]}"; do
        if ! grep -q "## $section" "$file" && ! grep -q "# $section" "$file"; then
            issues+=("Missing section: $section")
        fi
    done

    # Check for Status checkboxes
    if ! grep -q "\- \[.\] .*Task completed" "$file"; then
        issues+=("Missing 'Task completed' checkbox")
    fi
    if ! grep -q "\- \[.\] .*Tests pass" "$file"; then
        issues+=("Missing 'Tests pass' checkbox")
    fi
    if ! grep -q "\- \[.\] .*Verified" "$file"; then
        issues+=("Missing 'Verified' checkbox")
    fi

    # Check for Agents section
    if ! grep -q "## Agents" "$file"; then
        warnings+=("Missing Agents section")
    fi

    # Check for Acceptance Criteria checkboxes
    local ac_count=$(grep -c "\- \[.\] " "$file" 2>/dev/null || echo "0")
    if [[ $ac_count -lt 3 ]]; then
        warnings+=("Few acceptance criteria checkboxes (found $ac_count)")
    fi

    # Output
    local valid="true"
    if [[ ${#issues[@]} -gt 0 ]]; then
        valid="false"
    fi

    echo "    {"
    echo "      \"file\": \"$filename\","
    echo "      \"valid\": $valid,"
    echo "      \"issues\": ["
    local first=true
    for issue in "${issues[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        echo "        \"$issue\""
    done
    echo "      ],"
    echo "      \"warnings\": ["
    first=true
    for warning in "${warnings[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        echo "        \"$warning\""
    done
    echo "      ]"
    echo "    }"
}

# Validate all tasks in a ticket
validate_ticket_tasks() {
    local ticket_path="$1"
    local tasks_dir="$ticket_path/tasks"
    local first=true

    echo "  \"tasks\": ["

    if [[ -d "$tasks_dir" ]]; then
        for file in "$tasks_dir"/*.md; do
            if [[ -f "$file" ]]; then
                if [[ "$first" == "true" ]]; then
                    first=false
                else
                    echo ","
                fi
                validate_task "$file"
            fi
        done
    fi

    echo "  ]"
}

# Main execution
main() {
    local ticket_id="${1:-}"

    echo "{"
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"validation\": {"

    if [[ -n "$ticket_id" ]]; then
        # Validate specific ticket
        local ticket_path=$(find "$SDD_ROOT_DIR/tickets" -maxdepth 1 -type d -name "${ticket_id}_*" 2>/dev/null | head -1)
        if [[ -n "$ticket_path" ]]; then
            echo "  \"ticket\":"
            validate_ticket "$ticket_path"
            echo ","
            validate_ticket_tasks "$ticket_path"
        else
            echo "  \"error\": \"Ticket not found: $ticket_id\""
        fi
    else
        # Validate all tickets
        echo "  \"tickets\": ["
        local first=true
        for ticket_path in "$SDD_ROOT_DIR/tickets"/*; do
            if [[ -d "$ticket_path" ]]; then
                if [[ "$first" == "true" ]]; then
                    first=false
                else
                    echo ","
                fi
                validate_ticket "$ticket_path"
            fi
        done
        echo "  ]"
    fi

    echo "  }"
    echo "}"
}

main "$@"
