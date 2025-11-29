#!/usr/bin/env bash
#
# Structure Validator
# Validates project/ticket structure and reports issues
#
# Usage:
#   bash validate-structure.sh <SLUG>      # Validate specific project
#   bash validate-structure.sh             # Validate all projects
#
# Output:
#   JSON validation report

set -euo pipefail

CREWCHIEF_DIR="${CREWCHIEF_DIR:-.crewchief}"

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

# Validate project structure
validate_project() {
    local project_path="$1"
    local project_name=$(basename "$project_path")
    local issues=()
    local warnings=()

    # Check README exists
    if [[ ! -f "$project_path/README.md" ]]; then
        issues+=("Missing README.md")
    fi

    # Check planning directory
    if [[ ! -d "$project_path/planning" ]]; then
        issues+=("Missing planning/ directory")
    else
        # Check required planning files
        for file in "${REQUIRED_PLANNING_FILES[@]}"; do
            if [[ ! -f "$project_path/planning/$file" ]]; then
                issues+=("Missing planning/$file")
            elif [[ ! -s "$project_path/planning/$file" ]]; then
                warnings+=("Empty planning/$file")
            fi
        done
    fi

    # Check tickets directory
    if [[ ! -d "$project_path/tickets" ]]; then
        issues+=("Missing tickets/ directory")
    else
        # Count tickets
        local ticket_count=$(find "$project_path/tickets" -name "*.md" -type f 2>/dev/null | wc -l)
        if [[ $ticket_count -eq 0 ]]; then
            warnings+=("No tickets in tickets/ directory")
        fi
    fi

    # Extract SLUG from folder name
    local slug=""
    if [[ "$project_name" =~ ^([A-Z]+[A-Z0-9]*)_ ]]; then
        slug="${BASH_REMATCH[1]}"
    else
        issues+=("Invalid project folder name format (expected SLUG_name)")
    fi

    # Validate folder name format
    if [[ ! "$project_name" =~ ^[A-Z][A-Z0-9]{3,7}_[a-z][a-z0-9-]*$ ]]; then
        warnings+=("Folder name may not follow naming convention")
    fi

    # Output validation result
    local valid="true"
    if [[ ${#issues[@]} -gt 0 ]]; then
        valid="false"
    fi

    echo "  {"
    echo "    \"project\": \"$project_name\","
    echo "    \"path\": \"$project_path\","
    echo "    \"slug\": \"$slug\","
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

# Validate ticket structure
validate_ticket() {
    local file="$1"
    local filename=$(basename "$file")
    local issues=()
    local warnings=()

    # Check filename format
    if [[ ! "$filename" =~ ^[A-Z]+-[0-9]+_.*\.md$ ]]; then
        issues+=("Invalid ticket filename format")
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

# Validate all tickets in a project
validate_project_tickets() {
    local project_path="$1"
    local tickets_dir="$project_path/tickets"
    local first=true

    echo "  \"tickets\": ["

    if [[ -d "$tickets_dir" ]]; then
        for file in "$tickets_dir"/*.md; do
            if [[ -f "$file" ]]; then
                if [[ "$first" == "true" ]]; then
                    first=false
                else
                    echo ","
                fi
                validate_ticket "$file"
            fi
        done
    fi

    echo "  ]"
}

# Main execution
main() {
    local slug="${1:-}"

    echo "{"
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"validation\": {"

    if [[ -n "$slug" ]]; then
        # Validate specific project
        local project_path=$(find "$CREWCHIEF_DIR/projects" -maxdepth 1 -type d -name "${slug}_*" 2>/dev/null | head -1)
        if [[ -n "$project_path" ]]; then
            echo "  \"project\":"
            validate_project "$project_path"
            echo ","
            validate_project_tickets "$project_path"
        else
            echo "  \"error\": \"Project not found: $slug\""
        fi
    else
        # Validate all projects
        echo "  \"projects\": ["
        local first=true
        for project_path in "$CREWCHIEF_DIR/projects"/*; do
            if [[ -d "$project_path" ]]; then
                if [[ "$first" == "true" ]]; then
                    first=false
                else
                    echo ","
                fi
                validate_project "$project_path"
            fi
        done
        echo "  ]"
    fi

    echo "  }"
    echo "}"
}

main "$@"
