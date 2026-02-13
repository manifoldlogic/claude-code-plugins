#!/usr/bin/env bash
#
# Structure Validator
# Validates ticket/task structure and reports issues
#
# Usage:
#   bash validate-structure.sh [--no-color] [--debug] <TICKET_ID> # Validate specific ticket
#   bash validate-structure.sh [--no-color] [--debug]             # Validate all tickets
#
# Arguments:
#   --no-color         Disable color output (also: NO_COLOR=1)
#   --debug            Enable verbose command tracing (also: DEBUG=1)
#
# Output:
#   JSON validation report

set -euo pipefail

# Source shared helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse flags before sourcing common.sh
for arg in "$@"; do
    case "$arg" in
        --no-color) USE_COLOR=false ;;
        --debug) SDD_DEBUG=true ;;
    esac
done

# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

# Check for required dependencies
if ! command -v jq >/dev/null 2>&1; then
    printf "[ERROR] jq is required but not installed.\n" >&2
    printf "\n" >&2
    printf "Install jq using your package manager:\n" >&2
    printf "  apt-get install jq    # Debian/Ubuntu\n" >&2
    printf "  brew install jq       # macOS\n" >&2
    printf "  yum install jq        # RHEL/CentOS\n" >&2
    exit 1
fi

SDD_ROOT_DIR="${SDD_ROOT_DIR:-/app/.sdd}"

# Core-tier documents: ALWAYS required regardless of manifest content
CORE_TIER_FILES=(
    "analysis.md"
    "architecture.md"
    "plan.md"
)

# Legacy required set: used when no triage manifest is present
LEGACY_REQUIRED_FILES=(
    "analysis.md"
    "architecture.md"
    "plan.md"
    "prd.md"
    "quality-strategy.md"
    "security-review.md"
)

# Required ticket sections
REQUIRED_TICKET_SECTIONS=(
    "Status"
    "Summary"
    "Acceptance Criteria"
)

# Resolve required planning files for a ticket directory
# Sets RESOLVED_REQUIRED_FILES array and VALIDATION_MODE string
# Returns 1 if manifest is invalid JSON (caller should handle)
resolve_required_files() {
    local ticket_path="$1"
    local manifest_path="$ticket_path/planning/.triage-manifest.json"

    RESOLVED_REQUIRED_FILES=()
    RESOLVED_CORE_FILES=()
    RESOLVED_MANIFEST_FILES=()
    VALIDATION_MODE="legacy"

    if [[ -f "$manifest_path" ]]; then
        # Manifest exists - validate it is parseable JSON
        if ! jq empty "$manifest_path" 2>/dev/null; then
            VALIDATION_MODE="invalid"
            return 1
        fi

        VALIDATION_MODE="manifest"

        # Core-tier documents are always required
        for file in "${CORE_TIER_FILES[@]}"; do
            RESOLVED_CORE_FILES+=("$file")
        done

        # Get documents with action="generate" from manifest
        local manifest_files
        manifest_files=$(jq -r '.documents[] | select(.action=="generate") | .filename' "$manifest_path" 2>/dev/null)

        # Add manifest-generated files (dedup against core)
        local f
        for f in $manifest_files; do
            # Skip if already in core tier
            local is_core=false
            local c
            for c in "${CORE_TIER_FILES[@]}"; do
                if [[ "$f" = "$c" ]]; then
                    is_core=true
                    break
                fi
            done
            if [[ "$is_core" = "false" ]]; then
                RESOLVED_MANIFEST_FILES+=("$f")
            fi
        done

        # Combine: core + manifest-only files
        RESOLVED_REQUIRED_FILES=("${RESOLVED_CORE_FILES[@]}")
        if [[ ${#RESOLVED_MANIFEST_FILES[@]} -gt 0 ]]; then
            RESOLVED_REQUIRED_FILES+=("${RESOLVED_MANIFEST_FILES[@]}")
        fi
    else
        # No manifest - use legacy required set
        VALIDATION_MODE="legacy"
        RESOLVED_REQUIRED_FILES=("${LEGACY_REQUIRED_FILES[@]}")
    fi

    return 0
}

# Check if a filename is in the core tier
is_core_tier() {
    local filename="$1"
    local c
    for c in "${CORE_TIER_FILES[@]}"; do
        if [[ "$filename" = "$c" ]]; then
            return 0
        fi
    done
    return 1
}

# Validate ticket structure
validate_ticket() {
    local ticket_path="$1"
    local ticket_name
    ticket_name=$(basename "$ticket_path")
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
        # Resolve required planning files dynamically
        if ! resolve_required_files "$ticket_path"; then
            # Invalid manifest JSON
            issues+=("Error: Manifest file exists but contains invalid JSON")
        fi

        if [[ "$VALIDATION_MODE" != "invalid" ]]; then
            # Validate each required file
            for file in "${RESOLVED_REQUIRED_FILES[@]}"; do
                if [[ ! -f "$ticket_path/planning/$file" ]]; then
                    if [[ "$VALIDATION_MODE" = "manifest" ]]; then
                        # Manifest mode: distinguish core vs manifested errors
                        if is_core_tier "$file"; then
                            issues+=("Error: Required core document missing: $file")
                        else
                            issues+=("Error: Manifested document missing: $file")
                        fi
                    else
                        # Legacy mode: use original error format
                        issues+=("Missing planning/$file")
                    fi
                elif [[ ! -s "$ticket_path/planning/$file" ]]; then
                    warnings+=("Empty planning/$file")
                fi
            done
        fi
    fi

    # Check tasks directory
    if [[ ! -d "$ticket_path/tasks" ]]; then
        issues+=("Missing tasks/ directory")
    else
        # Count tasks
        local task_count
        task_count=$(find "$ticket_path/tasks" -name "*.md" -type f 2>/dev/null | wc -l)
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
    local filename
    filename=$(basename "$file")
    local issues=()
    local warnings=()

    # Check filename format (supports PROJ.1001 and UIT-9819.1001 formats)
    if [[ ! "$filename" =~ ^[A-Z][A-Z0-9]*(-[A-Z0-9]+)*\.[0-9]+_.*\.md$ ]]; then
        issues+=("Invalid task filename format")
    fi

    # Check required sections
    # content loaded for potential future use; cat also validates readability
    # shellcheck disable=SC2155
    # shellcheck disable=SC2034
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
    local ac_count
    ac_count=$(grep -c "\- \[.\] " "$file" 2>/dev/null || echo "0")
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
    # Strip --no-color and --debug from positional args (already handled before sourcing common.sh)
    local ticket_id=""
    for arg in "$@"; do
        case "$arg" in
            --no-color|--debug) ;;
            *) ticket_id="$arg" ;;
        esac
    done

    echo "{"
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"validation\": {"

    if [[ -n "$ticket_id" ]]; then
        # Validate specific ticket
        local ticket_path
        ticket_path=$(find "$SDD_ROOT_DIR/tickets" -maxdepth 1 -type d -name "${ticket_id}_*" 2>/dev/null | head -1)
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
