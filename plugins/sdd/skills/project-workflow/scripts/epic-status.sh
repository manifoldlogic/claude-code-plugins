#!/usr/bin/env bash
#
# Epic Status Scanner
# Scans epic overview.md files and returns checkbox status as JSON
#
# Usage:
#   bash epic-status.sh <EPIC_FOLDER>      # Specific epic
#   bash epic-status.sh                    # All epics
#
# Output:
#   JSON array of epic statuses
#

set -euo pipefail

SDD_ROOT_DIR="${SDD_ROOT_DIR:-/app/.sdd}"

# Check if a file has substantive content (exceeds byte threshold)
# Args: $1 = file path, $2 = threshold in bytes (default: 500)
# Returns: 0 if file exists and exceeds threshold, 1 otherwise
check_file_substantive() {
    local file="$1"
    local threshold="${2:-500}"
    if [ -f "$file" ]; then
        local size
        size=$(stat -c%s "$file" 2>/dev/null || echo "0")
        [ "$size" -gt "$threshold" ]
    else
        return 1
    fi
}

# Check if a directory contains any .md files
# Args: $1 = directory path
# Returns: 0 if directory exists and contains .md files, 1 otherwise
check_dir_has_md_files() {
    local dir="$1"
    if [ -d "$dir" ]; then
        local count
        count=$(find "$dir" -maxdepth 1 -name "*.md" -type f 2>/dev/null | wc -l)
        [ "$count" -gt 0 ]
    else
        return 1
    fi
}

# Extract epic info from overview.md file
scan_epic() {
    local epic_path="$1"
    local epic_name=$(basename "$epic_path")
    local overview_file="$epic_path/overview.md"

    local research_complete="false"
    local analysis_complete="false"
    local decomposition_complete="false"
    local tickets_created="false"

    # Check if overview.md exists
    if [[ ! -f "$overview_file" ]]; then
        echo "Warning: Missing overview.md in $epic_name" >&2
        return 1
    fi

    # Check checkbox states using grep - match checkbox lines
    # Handle both [x] and [X] as checked
    local research_count=$(grep -c '^-[[:space:]]*\[x\][[:space:]]*Research complete\|^-[[:space:]]*\[X\][[:space:]]*Research complete' "$overview_file" 2>/dev/null || true)
    local analysis_count=$(grep -c '^-[[:space:]]*\[x\][[:space:]]*Analysis complete\|^-[[:space:]]*\[X\][[:space:]]*Analysis complete' "$overview_file" 2>/dev/null || true)
    local decomposition_count=$(grep -c '^-[[:space:]]*\[x\][[:space:]]*Decomposition complete\|^-[[:space:]]*\[X\][[:space:]]*Decomposition complete' "$overview_file" 2>/dev/null || true)
    local tickets_count=$(grep -c '^-[[:space:]]*\[x\][[:space:]]*Tickets created\|^-[[:space:]]*\[X\][[:space:]]*Tickets created' "$overview_file" 2>/dev/null || true)

    # Convert counts to boolean
    if [[ -n "$research_count" ]] && [[ $research_count -gt 0 ]]; then
        research_complete="true"
    fi
    if [[ -n "$analysis_count" ]] && [[ $analysis_count -gt 0 ]]; then
        analysis_complete="true"
    fi
    if [[ -n "$decomposition_count" ]] && [[ $decomposition_count -gt 0 ]]; then
        decomposition_complete="true"
    fi
    if [[ -n "$tickets_count" ]] && [[ $tickets_count -gt 0 ]]; then
        tickets_created="true"
    fi

    # Calculate progress
    local checked=0
    [[ "$research_complete" == "true" ]] && ((checked++))
    [[ "$analysis_complete" == "true" ]] && ((checked++))
    [[ "$decomposition_complete" == "true" ]] && ((checked++))
    [[ "$tickets_created" == "true" ]] && ((checked++))
    local progress="$checked/4"

    # Output JSON object
    cat << EOF
    {
      "name": "$epic_name",
      "path": "$epic_path",
      "checkboxes": {
        "research_complete": $research_complete,
        "analysis_complete": $analysis_complete,
        "decomposition_complete": $decomposition_complete,
        "tickets_created": $tickets_created
      },
      "progress": "$progress"
    }
EOF
}

# Main execution
main() {
    local epic_folder="${1:-}"
    local epics_dir="$SDD_ROOT_DIR/epics"
    local first=true

    echo "{"
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"epics\": ["

    # Check if epics directory exists
    if [[ ! -d "$epics_dir" ]]; then
        echo "Warning: Epics directory does not exist: $epics_dir" >&2
        echo "  ]"
        echo "}"
        return 0
    fi

    if [[ -n "$epic_folder" ]]; then
        # Scan specific epic
        local epic_path="$epics_dir/$epic_folder"
        if [[ -d "$epic_path" ]]; then
            scan_epic "$epic_path" || true
        else
            echo "Error: Epic not found: $epic_folder" >&2
        fi
    else
        # Scan all epics
        for epic_path in "$epics_dir"/*; do
            if [[ -d "$epic_path" ]]; then
                # Try to scan epic, capture output
                local output
                if output=$(scan_epic "$epic_path" 2>&1); then
                    if [[ "$first" == "true" ]]; then
                        first=false
                    else
                        echo ","
                    fi
                    echo "$output"
                else
                    # Forward error to stderr
                    echo "$output" >&2
                fi
            fi
        done
    fi

    echo "  ]"
    echo "}"
}

main "$@"
