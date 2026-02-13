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

# Check for required dependencies (uses check_jq_version from common.sh)
check_jq_version || exit 1

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

# Validate triage manifest structure using jq-based schema checks.
# Checks required top-level keys, documents array, and per-document fields.
# Arguments:
#   $1 - path to the .triage-manifest.json file
# Sets global: MANIFEST_ERRORS (array of error strings)
# Returns 0 if valid, 1 if validation errors found
validate_manifest_schema() {
    local manifest_path="$1"
    MANIFEST_ERRORS=()

    # Check required top-level keys: ticket_description, overrides, documents
    local has_desc has_overrides has_docs
    has_desc=$(jq 'has("ticket_description")' "$manifest_path" 2>/dev/null)
    has_overrides=$(jq 'has("overrides")' "$manifest_path" 2>/dev/null)
    has_docs=$(jq 'has("documents")' "$manifest_path" 2>/dev/null)

    if [ "$has_desc" != "true" ]; then
        MANIFEST_ERRORS+=("Missing required property: \"ticket_description\"")
    fi
    if [ "$has_overrides" != "true" ]; then
        MANIFEST_ERRORS+=("Missing required property: \"overrides\"")
    fi
    if [ "$has_docs" != "true" ]; then
        MANIFEST_ERRORS+=("Missing required property: \"documents\"")
        # Cannot validate documents array if it doesn't exist
        if [ ${#MANIFEST_ERRORS[@]} -gt 0 ]; then
            return 1
        fi
    fi

    # Validate "documents" is an array
    local docs_type
    docs_type=$(jq -r '.documents | type' "$manifest_path" 2>/dev/null)
    if [ "$docs_type" != "array" ]; then
        MANIFEST_ERRORS+=("Property \"documents\" must be an array, got \"$docs_type\"")
        return 1
    fi

    # Validate each document entry has required fields and valid action values
    local doc_count
    doc_count=$(jq '.documents | length' "$manifest_path" 2>/dev/null)

    local i=0
    while [ "$i" -lt "$doc_count" ]; do
        local doc_id
        doc_id=$(jq -r ".documents[$i].id // \"(index $i)\"" "$manifest_path" 2>/dev/null)

        # Check required fields: id, filename, action, reason
        local has_id has_fn has_act has_rsn
        has_id=$(jq ".documents[$i] | has(\"id\")" "$manifest_path" 2>/dev/null)
        has_fn=$(jq ".documents[$i] | has(\"filename\")" "$manifest_path" 2>/dev/null)
        has_act=$(jq ".documents[$i] | has(\"action\")" "$manifest_path" 2>/dev/null)
        has_rsn=$(jq ".documents[$i] | has(\"reason\")" "$manifest_path" 2>/dev/null)

        if [ "$has_id" != "true" ]; then
            MANIFEST_ERRORS+=("Document at index $i: missing required field \"id\"")
        fi
        if [ "$has_fn" != "true" ]; then
            MANIFEST_ERRORS+=("Document \"$doc_id\": missing required field \"filename\"")
        fi
        if [ "$has_act" != "true" ]; then
            MANIFEST_ERRORS+=("Document \"$doc_id\": missing required field \"action\"")
        fi
        if [ "$has_rsn" != "true" ]; then
            MANIFEST_ERRORS+=("Document \"$doc_id\": missing required field \"reason\"")
        fi

        # Validate action enum: must be "generate" or "skip"
        if [ "$has_act" = "true" ]; then
            local action_val
            action_val=$(jq -r ".documents[$i].action" "$manifest_path" 2>/dev/null)
            if [ "$action_val" != "generate" ] && [ "$action_val" != "skip" ]; then
                MANIFEST_ERRORS+=("Invalid value for property \"action\" in document \"$doc_id\": \"$action_val\". Expected one of: [\"generate\", \"skip\"]")
            fi
        fi

        i=$((i + 1))
    done

    if [ ${#MANIFEST_ERRORS[@]} -gt 0 ]; then
        return 1
    fi
    return 0
}

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

        # Validate manifest structure against schema rules
        if ! validate_manifest_schema "$manifest_path"; then
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
            if [ ${#MANIFEST_ERRORS[@]} -gt 0 ]; then
                # Schema validation errors - report each one
                issues+=("Error: triage-manifest.json validation failed")
                for merr in "${MANIFEST_ERRORS[@]}"; do
                    issues+=("  - $merr")
                done
            else
                # Invalid manifest JSON (unparseable)
                issues+=("Error: Manifest file exists but contains invalid JSON")
            fi
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
