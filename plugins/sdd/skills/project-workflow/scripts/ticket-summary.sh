#!/usr/bin/env bash
#
# Ticket Summary Generator
# Generates a markdown summary of ticket status
#
# Usage:
#   bash ticket-summary.sh <TICKET_ID>
#
# Output:
#   Markdown summary to stdout

set -euo pipefail

SDD_ROOT_DIR="${SDD_ROOT_DIR:-/app/.sdd}"

# Count checkbox states
count_checkboxes() {
    local file="$1"
    local checked=$(grep -c '\[x\]\|\[X\]' "$file" 2>/dev/null || echo "0")
    local unchecked=$(grep -c '\[ \]' "$file" 2>/dev/null || echo "0")
    echo "$checked $unchecked"
}

# Get ticket phase from number
get_phase() {
    local ticket_id="$1"
    if [[ "$ticket_id" =~ \.([0-9]) ]]; then
        echo "Phase ${BASH_REMATCH[1]}"
    else
        echo "Unknown"
    fi
}

main() {
    local ticket_id="${1:-}"

    if [[ -z "$ticket_id" ]]; then
        echo "Usage: $(basename "$0") <TICKET_ID>"
        exit 1
    fi

    # Find ticket
    local ticket_path=$(find "$SDD_ROOT_DIR/tickets" -maxdepth 1 -type d -name "${ticket_id}_*" 2>/dev/null | head -1)

    if [[ -z "$ticket_path" ]]; then
        echo "Error: Ticket not found: $ticket_id"
        exit 1
    fi

    local ticket_name=$(basename "$ticket_path")
    local tasks_dir="$ticket_path/tasks"

    # Count tickets by status
    local total=0
    local pending=0
    local completed=0
    local tested=0
    local verified=0

    declare -A phases

    if [[ -d "$tasks_dir" ]]; then
        for file in "$tasks_dir"/*.md; do
            # Supports both PROJ.1001 and UIT-9819.1001 (Jira-style) formats
            if [[ -f "$file" ]] && [[ "$file" =~ [A-Z][A-Z0-9]*(-[A-Z0-9]+)*\.[0-9]+ ]]; then
                ((total++))

                local task_id=""
                if [[ "$(basename "$file")" =~ ^([A-Z][A-Z0-9]*(-[A-Z0-9]+)*\.[0-9]+) ]]; then
                    task_id="${BASH_REMATCH[1]}"
                fi

                local phase=$(get_phase "$task_id")
                phases[$phase]=$((${phases[$phase]:-0} + 1))

                # Check status
                local is_verified=$(grep -c '\[x\].*Verified\|\[X\].*Verified' "$file" 2>/dev/null || echo "0")
                local is_tested=$(grep -c '\[x\].*Tests pass\|\[X\].*Tests pass' "$file" 2>/dev/null || echo "0")
                local is_completed=$(grep -c '\[x\].*Task completed\|\[X\].*Task completed' "$file" 2>/dev/null || echo "0")

                if [[ $is_verified -gt 0 ]]; then
                    ((verified++))
                elif [[ $is_tested -gt 0 ]]; then
                    ((tested++))
                elif [[ $is_completed -gt 0 ]]; then
                    ((completed++))
                else
                    ((pending++))
                fi
            fi
        done
    fi

    # Generate markdown
    cat << EOF
# Ticket Summary: $ticket_name

**Generated:** $(date +"%Y-%m-%d %H:%M")

## Status Overview

| Metric | Count |
|--------|-------|
| Total Tasks | $total |
| Pending | $pending |
| Completed (not tested) | $completed |
| Tested (not verified) | $tested |
| Verified | $verified |

## Progress

EOF

    if [[ $total -gt 0 ]]; then
        local percent=$((verified * 100 / total))
        local bar=""
        local filled=$((percent / 5))
        for ((i=0; i<20; i++)); do
            if [[ $i -lt $filled ]]; then
                bar+="█"
            else
                bar+="░"
            fi
        done
        echo "**Verification Progress:** $bar $percent% ($verified/$total)"
        echo ""
    fi

    # Phases
    echo "## Tasks by Phase"
    echo ""
    echo "| Phase | Tasks |"
    echo "|-------|---------|"
    for phase in $(echo "${!phases[@]}" | tr ' ' '\n' | sort); do
        echo "| $phase | ${phases[$phase]} |"
    done
    echo ""

    # Recent activity hint
    echo "## Planning Documents"
    echo ""
    for file in "$ticket_path/planning"/*.md; do
        if [[ -f "$file" ]]; then
            local fname=$(basename "$file")
            local size=$(wc -c < "$file")
            local status="Present"
            if [[ $size -lt 500 ]]; then
                status="Needs content"
            fi
            echo "- **$fname**: $status"
        fi
    done
    echo ""

    # Next actions
    echo "## Recommended Actions"
    echo ""
    if [[ $pending -gt 0 ]]; then
        echo "1. Work on pending tasks ($pending remaining)"
    fi
    if [[ $completed -gt 0 ]]; then
        echo "2. Run tests for completed tasks ($completed need testing)"
    fi
    if [[ $tested -gt 0 ]]; then
        echo "3. Verify tested tasks ($tested need verification)"
    fi
    if [[ $verified -eq $total ]] && [[ $total -gt 0 ]]; then
        echo "**All tasks verified! Ready for archive.**"
    fi
}

main "$@"
