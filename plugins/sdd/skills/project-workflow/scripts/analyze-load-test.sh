#!/usr/bin/env bash
#
# Load Test Analysis Script for SDD Loop Controller
# Analyzes metrics CSV and generates markdown report
#
# Version: 1.0.0
#
# DESCRIPTION
#   Parses monitoring CSV data from load tests and generates a comprehensive
#   analysis report including summary statistics, trend detection, and
#   resource leak identification.
#
# USAGE
#   analyze-load-test.sh <metrics.csv> [workspace_dir]
#
# ARGUMENTS
#   metrics.csv     Path to metrics CSV file from monitor-loop-resources.sh
#   workspace_dir   Optional workspace directory for additional context
#
# OUTPUT
#   Markdown-formatted analysis report to stdout
#
# EXIT CODES
#   0   - Analysis completed successfully
#   1   - Error (file not found, invalid data)
#   2   - Usage error
#

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

VERSION="1.0.0"

# Thresholds for leak detection
MEMORY_GROWTH_THRESHOLD_KB_PER_HOUR=1024  # 1MB/hour considered a leak
FD_GROWTH_THRESHOLD_PER_HOUR=5             # 5 FDs/hour considered a leak
CPU_HIGH_THRESHOLD=50                       # >50% average is concerning

# =============================================================================
# Global State
# =============================================================================

METRICS_FILE=""
WORKSPACE_DIR=""

# =============================================================================
# Help
# =============================================================================

show_usage() {
    cat << 'EOF'
Load Test Analysis Script v1.0.0

DESCRIPTION
    Analyzes metrics CSV from load tests and generates a markdown report
    with summary statistics, trend analysis, and leak detection.

USAGE
    analyze-load-test.sh <metrics.csv> [workspace_dir]

ARGUMENTS
    metrics.csv     Path to metrics CSV file
    workspace_dir   Optional workspace directory for additional context

OUTPUT
    Markdown-formatted analysis report to stdout

EXAMPLES
    # Basic analysis
    analyze-load-test.sh /tmp/load-test/metrics.csv

    # Analysis with workspace context
    analyze-load-test.sh /tmp/load-test/metrics.csv /tmp/load-test

    # Save to file
    analyze-load-test.sh metrics.csv > analysis-report.md

EOF
}

# =============================================================================
# Utility Functions
# =============================================================================

#######################################
# Calculate statistics for a column of numbers
# Arguments:
#   Column data via stdin (one number per line)
# Outputs:
#   min,max,mean,stddev (comma-separated)
#######################################
calc_stats() {
    awk '
    BEGIN { n=0; sum=0; sum2=0; min=""; max="" }
    {
        n++
        sum += $1
        sum2 += $1 * $1
        if (min == "" || $1 < min) min = $1
        if (max == "" || $1 > max) max = $1
    }
    END {
        if (n == 0) {
            print "0,0,0,0"
        } else {
            mean = sum / n
            if (n > 1) {
                variance = (sum2 - (sum * sum) / n) / (n - 1)
                if (variance < 0) variance = 0
                stddev = sqrt(variance)
            } else {
                stddev = 0
            }
            printf "%.2f,%.2f,%.2f,%.2f\n", min, max, mean, stddev
        }
    }
    '
}

#######################################
# Calculate linear regression slope
# Arguments:
#   Two-column data via stdin (x y per line)
# Outputs:
#   slope (per unit x)
#######################################
calc_slope() {
    awk '
    BEGIN { n=0; sum_x=0; sum_y=0; sum_xy=0; sum_x2=0 }
    {
        n++
        x = $1
        y = $2
        sum_x += x
        sum_y += y
        sum_xy += x * y
        sum_x2 += x * x
    }
    END {
        if (n < 2) {
            print "0"
        } else {
            denom = n * sum_x2 - sum_x * sum_x
            if (denom == 0) {
                print "0"
            } else {
                slope = (n * sum_xy - sum_x * sum_y) / denom
                printf "%.6f\n", slope
            }
        }
    }
    '
}

#######################################
# Extract column from CSV by index (0-based)
# Arguments:
#   $1 - column index
#   CSV data via stdin
# Outputs:
#   Column values (one per line)
#######################################
get_column() {
    local col_idx="$1"
    awk -F',' -v col="$((col_idx + 1))" 'NR>1 {print $col}'
}

# =============================================================================
# Analysis Functions
# =============================================================================

analyze_metrics() {
    local metrics_file="$1"

    # Check file exists and has data
    if [[ ! -f "$metrics_file" ]]; then
        echo "ERROR: Metrics file not found: $metrics_file" >&2
        return 1
    fi

    local line_count
    line_count=$(wc -l < "$metrics_file")
    if [[ $line_count -lt 2 ]]; then
        echo "ERROR: Metrics file has no data (only header or empty)" >&2
        return 1
    fi

    local data_lines=$((line_count - 1))

    # Extract columns (skip header)
    # CSV format: timestamp,elapsed_sec,pid,memory_rss_kb,memory_vsz_kb,fd_count,cpu_percent,tasks_completed,tasks_failed,iteration_count

    local elapsed_data memory_rss_data memory_vsz_data fd_data cpu_data
    local completed_data failed_data

    elapsed_data=$(tail -n +2 "$metrics_file" | cut -d',' -f2)
    memory_rss_data=$(tail -n +2 "$metrics_file" | cut -d',' -f4)
    memory_vsz_data=$(tail -n +2 "$metrics_file" | cut -d',' -f5)
    fd_data=$(tail -n +2 "$metrics_file" | cut -d',' -f6)
    cpu_data=$(tail -n +2 "$metrics_file" | cut -d',' -f7)
    completed_data=$(tail -n +2 "$metrics_file" | cut -d',' -f8)
    failed_data=$(tail -n +2 "$metrics_file" | cut -d',' -f9)

    # Get first and last values for duration calculation
    local first_elapsed last_elapsed duration_sec
    first_elapsed=$(echo "$elapsed_data" | head -1)
    last_elapsed=$(echo "$elapsed_data" | tail -1)
    duration_sec=$((last_elapsed - first_elapsed))

    if [[ $duration_sec -eq 0 ]]; then
        duration_sec=1  # Avoid division by zero
    fi

    local duration_hours
    duration_hours=$(awk "BEGIN {printf \"%.2f\", $duration_sec / 3600}")

    # Calculate statistics for each metric
    local rss_stats vsz_stats fd_stats cpu_stats
    rss_stats=$(echo "$memory_rss_data" | calc_stats)
    vsz_stats=$(echo "$memory_vsz_data" | calc_stats)
    fd_stats=$(echo "$fd_data" | calc_stats)
    cpu_stats=$(echo "$cpu_data" | calc_stats)

    # Parse stats
    local rss_min rss_max rss_mean rss_stddev
    IFS=',' read -r rss_min rss_max rss_mean rss_stddev <<< "$rss_stats"

    local vsz_min vsz_max vsz_mean vsz_stddev
    IFS=',' read -r vsz_min vsz_max vsz_mean vsz_stddev <<< "$vsz_stats"

    local fd_min fd_max fd_mean fd_stddev
    IFS=',' read -r fd_min fd_max fd_mean fd_stddev <<< "$fd_stats"

    local cpu_min cpu_max cpu_mean cpu_stddev
    IFS=',' read -r cpu_min cpu_max cpu_mean cpu_stddev <<< "$cpu_stats"

    # Calculate growth trends (slope per second, then convert to per hour)
    local rss_slope vsz_slope fd_slope

    rss_slope=$(paste <(echo "$elapsed_data") <(echo "$memory_rss_data") | calc_slope)
    vsz_slope=$(paste <(echo "$elapsed_data") <(echo "$memory_vsz_data") | calc_slope)
    fd_slope=$(paste <(echo "$elapsed_data") <(echo "$fd_data") | calc_slope)

    # Convert to per-hour growth (using awk for portability)
    local rss_growth_per_hour vsz_growth_per_hour fd_growth_per_hour
    rss_growth_per_hour=$(awk "BEGIN {printf \"%.2f\", $rss_slope * 3600}")
    vsz_growth_per_hour=$(awk "BEGIN {printf \"%.2f\", $vsz_slope * 3600}")
    fd_growth_per_hour=$(awk "BEGIN {printf \"%.2f\", $fd_slope * 3600}")

    # Get final task counts
    local final_completed final_failed total_tasks
    final_completed=$(echo "$completed_data" | tail -1)
    final_failed=$(echo "$failed_data" | tail -1)
    total_tasks=$((final_completed + final_failed))

    # Detect potential issues
    local memory_leak_detected="No"
    local fd_leak_detected="No"
    local high_cpu_detected="No"

    # Check for memory leak (significant positive growth) - use awk for comparison
    if awk "BEGIN {exit !($rss_growth_per_hour > $MEMORY_GROWTH_THRESHOLD_KB_PER_HOUR)}"; then
        memory_leak_detected="POTENTIAL LEAK DETECTED"
    fi

    # Check for FD leak
    if awk "BEGIN {exit !($fd_growth_per_hour > $FD_GROWTH_THRESHOLD_PER_HOUR)}"; then
        fd_leak_detected="POTENTIAL LEAK DETECTED"
    fi

    # Check for high CPU
    if awk "BEGIN {exit !($cpu_mean > $CPU_HIGH_THRESHOLD)}"; then
        high_cpu_detected="HIGH CPU USAGE"
    fi

    # Calculate MB values for display (using awk)
    local rss_min_mb rss_max_mb rss_mean_mb
    local vsz_min_mb vsz_max_mb vsz_mean_mb
    rss_min_mb=$(awk "BEGIN {printf \"%.2f\", $rss_min / 1024}")
    rss_max_mb=$(awk "BEGIN {printf \"%.2f\", $rss_max / 1024}")
    rss_mean_mb=$(awk "BEGIN {printf \"%.2f\", $rss_mean / 1024}")
    vsz_min_mb=$(awk "BEGIN {printf \"%.2f\", $vsz_min / 1024}")
    vsz_max_mb=$(awk "BEGIN {printf \"%.2f\", $vsz_max / 1024}")
    vsz_mean_mb=$(awk "BEGIN {printf \"%.2f\", $vsz_mean / 1024}")

    # Generate markdown report section
    cat << EOF

## Resource Usage Analysis

### Memory Usage (RSS - Resident Set Size)

| Metric | Value |
|--------|-------|
| Minimum | ${rss_min} KB ($rss_min_mb MB) |
| Maximum | ${rss_max} KB ($rss_max_mb MB) |
| Average | ${rss_mean} KB ($rss_mean_mb MB) |
| Std Dev | ${rss_stddev} KB |
| Growth Rate | ${rss_growth_per_hour} KB/hour |
| Leak Status | **$memory_leak_detected** |

### Memory Usage (VSZ - Virtual Size)

| Metric | Value |
|--------|-------|
| Minimum | ${vsz_min} KB ($vsz_min_mb MB) |
| Maximum | ${vsz_max} KB ($vsz_max_mb MB) |
| Average | ${vsz_mean} KB ($vsz_mean_mb MB) |
| Std Dev | ${vsz_stddev} KB |
| Growth Rate | ${vsz_growth_per_hour} KB/hour |

### File Descriptors

| Metric | Value |
|--------|-------|
| Minimum | ${fd_min} |
| Maximum | ${fd_max} |
| Average | ${fd_mean} |
| Std Dev | ${fd_stddev} |
| Growth Rate | ${fd_growth_per_hour}/hour |
| Leak Status | **$fd_leak_detected** |

### CPU Utilization

| Metric | Value |
|--------|-------|
| Minimum | ${cpu_min}% |
| Maximum | ${cpu_max}% |
| Average | ${cpu_mean}% |
| Std Dev | ${cpu_stddev}% |
| Status | **$high_cpu_detected** |

### Sampling Statistics

| Metric | Value |
|--------|-------|
| Duration | ${duration_sec} seconds (${duration_hours} hours) |
| Sample Count | ${data_lines} |
| Tasks Completed | ${final_completed} |
| Tasks Failed | ${final_failed} |
| Total Tasks | ${total_tasks} |

## Stability Assessment

EOF

    # Generate overall assessment
    local overall_status="PASS"
    local issues=""

    if [[ "$memory_leak_detected" == "POTENTIAL LEAK DETECTED" ]]; then
        overall_status="FAIL"
        issues="${issues}\n- Memory growth detected: ${rss_growth_per_hour} KB/hour (threshold: ${MEMORY_GROWTH_THRESHOLD_KB_PER_HOUR} KB/hour)"
    fi

    if [[ "$fd_leak_detected" == "POTENTIAL LEAK DETECTED" ]]; then
        overall_status="FAIL"
        issues="${issues}\n- File descriptor growth detected: ${fd_growth_per_hour}/hour (threshold: ${FD_GROWTH_THRESHOLD_PER_HOUR}/hour)"
    fi

    if [[ "$high_cpu_detected" == "HIGH CPU USAGE" ]]; then
        overall_status="WARN"
        issues="${issues}\n- High average CPU usage: ${cpu_mean}% (threshold: ${CPU_HIGH_THRESHOLD}%)"
    fi

    cat << EOF
### Overall Status: **$overall_status**

EOF

    if [[ -n "$issues" ]]; then
        echo "**Issues Detected:**"
        echo -e "$issues"
        echo ""
    else
        echo "No resource leaks or significant issues detected."
        echo ""
    fi

    # Recommendations
    cat << EOF
### Recommendations

EOF

    if [[ "$memory_leak_detected" == "POTENTIAL LEAK DETECTED" ]]; then
        cat << 'EOF'
- **Memory Leak Investigation Required**
  - Review subprocesses created during task execution
  - Check for unbounded data structures (arrays, logs)
  - Verify temporary files are cleaned up
  - Consider running with `--debug` to trace allocations

EOF
    fi

    if [[ "$fd_leak_detected" == "POTENTIAL LEAK DETECTED" ]]; then
        cat << 'EOF'
- **File Descriptor Leak Investigation Required**
  - Check for unclosed file handles
  - Verify pipes and sockets are properly closed
  - Review subprocess communication patterns
  - Use `lsof -p <pid>` to identify open handles

EOF
    fi

    if [[ "$high_cpu_detected" == "HIGH CPU USAGE" ]]; then
        cat << 'EOF'
- **High CPU Usage Investigation**
  - Review poll interval configuration
  - Check for busy-wait loops
  - Consider increasing sleep intervals
  - Profile with `perf` or `strace` for hotspots

EOF
    fi

    if [[ "$overall_status" == "PASS" ]]; then
        cat << 'EOF'
- No immediate concerns identified
- Continue monitoring in production for extended periods
- Consider running 48+ hour tests for additional confidence

EOF
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    # Parse arguments
    if [[ $# -lt 1 ]]; then
        show_usage
        exit 2
    fi

    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_usage
        exit 0
    fi

    METRICS_FILE="$1"
    WORKSPACE_DIR="${2:-}"

    # Verify file exists
    if [[ ! -f "$METRICS_FILE" ]]; then
        echo "ERROR: Metrics file not found: $METRICS_FILE" >&2
        exit 1
    fi

    # Run analysis
    analyze_metrics "$METRICS_FILE"
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
