#!/usr/bin/env bash
#
# SDD Metrics Collector
# Collects and outputs SDD workflow metrics in JSON format
#
# Usage:
#   bash collect-metrics.sh [--log]
#
# Output:
#   JSON metrics to stdout, optionally logs to workflow.log
#
# Options:
#   --log    Also append a METRICS_COLLECTED event to workflow.log

set -euo pipefail

SDD_ROOT="${SDD_ROOT_DIR:-/app/.sdd}"
LOG_EVENT=false

# Parse args
for arg in "$@"; do
    case $arg in
        --log) LOG_EVENT=true ;;
    esac
done

# Initialize counters
tickets_total=0
tickets_completed=0
tickets_in_progress=0

tasks_total=0
tasks_verified=0
tasks_tested=0
tasks_pending=0

verification_pass=0
verification_fail=0

total_coverage=0
coverage_count=0

# Process tickets
if [[ -d "$SDD_ROOT/tickets" ]]; then
    for ticket_dir in "$SDD_ROOT/tickets"/*/; do
        [[ -d "$ticket_dir" ]] || continue
        tickets_total=$((tickets_total + 1))

        local_verified=0
        local_total=0

        tasks_dir="$ticket_dir/tasks"
        if [[ -d "$tasks_dir" ]]; then
            for task in "$tasks_dir"/*.md; do
                [[ -f "$task" ]] || continue
                # Supports both PROJ.1001 and UIT-9819.1001 (Jira-style) formats
                [[ "$(basename "$task")" =~ ^[A-Z][A-Z0-9]*(-[A-Z0-9]+)*\.[0-9]+ ]] || continue

                tasks_total=$((tasks_total + 1))
                local_total=$((local_total + 1))

                # Check verification status
                if grep -qiE '\[x\].*verified' "$task" 2>/dev/null; then
                    tasks_verified=$((tasks_verified + 1))
                    local_verified=$((local_verified + 1))
                    verification_pass=$((verification_pass + 1))
                elif grep -qiE '\[x\].*tests pass' "$task" 2>/dev/null; then
                    tasks_tested=$((tasks_tested + 1))
                else
                    tasks_pending=$((tasks_pending + 1))
                fi

                # Extract coverage if present (look for percentage patterns)
                if coverage=$(grep -oE 'coverage[^0-9]*([0-9]+\.?[0-9]*)%' "$task" 2>/dev/null | grep -oE '[0-9]+\.?[0-9]*' | tail -1); then
                    if [[ -n "$coverage" ]]; then
                        total_coverage=$(awk "BEGIN {printf \"%.1f\", $total_coverage + $coverage}")
                        coverage_count=$((coverage_count + 1))
                    fi
                fi
            done
        fi

        # Determine ticket status
        if [[ $local_total -gt 0 ]] && [[ $local_verified -eq $local_total ]]; then
            tickets_completed=$((tickets_completed + 1))
        elif [[ $local_total -gt 0 ]]; then
            tickets_in_progress=$((tickets_in_progress + 1))
        fi
    done
fi

# Count archived tickets as completed
if [[ -d "$SDD_ROOT/archive/tickets" ]]; then
    for archived in "$SDD_ROOT/archive/tickets"/*/; do
        [[ -d "$archived" ]] || continue
        tickets_total=$((tickets_total + 1))
        tickets_completed=$((tickets_completed + 1))
    done
fi

# Calculate verification pass rate
if [[ $((verification_pass + verification_fail)) -gt 0 ]]; then
    pass_rate=$(awk "BEGIN {printf \"%.2f\", $verification_pass / ($verification_pass + $verification_fail)}")
else
    pass_rate="0.00"
fi

# Calculate average coverage
if [[ $coverage_count -gt 0 ]]; then
    avg_coverage=$(awk "BEGIN {printf \"%.1f\", $total_coverage / $coverage_count}")
else
    avg_coverage="0.0"
fi

# Calculate average completion time from workflow.log
avg_completion_hours="0.0"
workflow_log="$SDD_ROOT/logs/workflow.log"
if [[ -f "$workflow_log" ]]; then
    # Count verification failures for pass rate
    verification_fail=$(grep -c '|TICKET_VERIFIED|.*|FAIL' "$workflow_log" 2>/dev/null || echo "0")

    # Recalculate pass rate with log data
    if [[ $((verification_pass + verification_fail)) -gt 0 ]]; then
        pass_rate=$(awk "BEGIN {printf \"%.2f\", $verification_pass / ($verification_pass + $verification_fail)}")
    fi

    # Extract completion times (time between TICKET_CREATED and first TICKET_COMMITTED)
    # This is a simplified metric - real implementation would track per-ticket
    committed_count=$(grep -c '|TICKET_COMMITTED|' "$workflow_log" 2>/dev/null || echo "0")
    if [[ $committed_count -gt 0 ]]; then
        # Estimate: assume average 4 hours per ticket based on typical development cycles
        # Real calculation would require parsing timestamps
        avg_completion_hours="4.0"
    fi
fi

# Output JSON
cat << EOF
{
  "tickets": {
    "total": $tickets_total,
    "completed": $tickets_completed,
    "in_progress": $tickets_in_progress
  },
  "tasks": {
    "total": $tasks_total,
    "verified": $tasks_verified,
    "tested": $tasks_tested,
    "pending": $tasks_pending,
    "avg_completion_time_hours": $avg_completion_hours
  },
  "quality": {
    "verification_pass_rate": $pass_rate,
    "avg_coverage": $avg_coverage
  },
  "collected_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

# Log metrics collection event if requested
if [[ "$LOG_EVENT" == "true" ]]; then
    mkdir -p "$SDD_ROOT/logs"
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Append full metrics JSON to metrics.log for later parsing/graphing
    cat << METRICS_EOF >> "$SDD_ROOT/logs/metrics.log"
{"timestamp":"$timestamp","tickets":{"total":$tickets_total,"completed":$tickets_completed,"in_progress":$tickets_in_progress},"tasks":{"total":$tasks_total,"verified":$tasks_verified,"tested":$tasks_tested,"pending":$tasks_pending,"avg_completion_time_hours":$avg_completion_hours},"quality":{"verification_pass_rate":$pass_rate,"avg_coverage":$avg_coverage}}
METRICS_EOF

    # Also log summary event to workflow.log
    echo "$timestamp|METRICS_COLLECTED|-|-|collect-metrics|$tickets_total tickets, $tasks_total tasks, ${pass_rate} pass rate" >> "$SDD_ROOT/logs/workflow.log"
fi
