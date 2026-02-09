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
    if [ ! -f "$overview_file" ]; then
        echo "Warning: Missing overview.md in $epic_path" >&2
        return 1
    fi

    # Detect status via content existence (not checkbox parsing)
    # Research complete: research-synthesis.md must be substantive (>500 bytes)
    if check_file_substantive "$epic_path/analysis/research-synthesis.md"; then
        research_complete=true
    fi

    # Analysis complete: both opportunity-map.md AND domain-model.md must be substantive
    if check_file_substantive "$epic_path/analysis/opportunity-map.md" && \
       check_file_substantive "$epic_path/analysis/domain-model.md"; then
        analysis_complete=true
    fi

    # Decomposition complete: multi-ticket-overview.md substantive AND ticket-summaries has .md files
    if check_file_substantive "$epic_path/decomposition/multi-ticket-overview.md" && \
       check_dir_has_md_files "$epic_path/decomposition/ticket-summaries"; then
        decomposition_complete=true
    fi

    # Tickets created: ticket-summaries directory has .md files
    if check_dir_has_md_files "$epic_path/decomposition/ticket-summaries"; then
        tickets_created=true
    fi

    # Calculate progress
    local checked=0
    [ "$research_complete" = "true" ] && checked=$((checked + 1))
    [ "$analysis_complete" = "true" ] && checked=$((checked + 1))
    [ "$decomposition_complete" = "true" ] && checked=$((checked + 1))
    [ "$tickets_created" = "true" ] && checked=$((checked + 1))
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
