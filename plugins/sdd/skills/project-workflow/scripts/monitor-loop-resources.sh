#!/usr/bin/env bash
#
# Resource Monitor for SDD Loop Controller Load Testing
# Monitors memory, file descriptors, and CPU for a running process
#
# Version: 1.0.0
#
# DESCRIPTION
#   Background monitoring script that samples resource usage metrics
#   at regular intervals and outputs to CSV format for analysis.
#   Designed to detect resource leaks in long-running processes.
#
# USAGE
#   monitor-loop-resources.sh [options]
#
# OPTIONS
#   -h, --help              Show this help message
#   --pid PID               Process ID to monitor (required unless --pid-file)
#   --pid-file FILE         File containing PID to monitor
#   --output FILE           Output CSV file (default: stdout)
#   --interval SECONDS      Sampling interval (default: 300)
#   --workspace DIR         Test workspace for additional metrics
#   --max-samples N         Maximum samples before stopping (0=unlimited)
#
# OUTPUT FORMAT (CSV)
#   timestamp,elapsed_sec,pid,memory_rss_kb,memory_vsz_kb,fd_count,cpu_percent,
#   tasks_completed,tasks_failed,iteration_count
#
# EXIT CODES
#   0   - Monitoring completed (process ended or max samples reached)
#   1   - Error (invalid PID, file not found, etc.)
#   2   - Usage error
#

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

VERSION="1.0.0"

# Default sampling interval in seconds
DEFAULT_INTERVAL=300

# Maximum samples (0 = unlimited)
DEFAULT_MAX_SAMPLES=0

# =============================================================================
# Global State
# =============================================================================

TARGET_PID=""
PID_FILE=""
OUTPUT_FILE=""
INTERVAL="$DEFAULT_INTERVAL"
WORKSPACE=""
MAX_SAMPLES="$DEFAULT_MAX_SAMPLES"

START_TIME=""
SAMPLE_COUNT=0

# =============================================================================
# Logging Functions
# =============================================================================

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [MONITOR] $*" >&2
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [MONITOR ERROR] $*" >&2
}

# =============================================================================
# Help
# =============================================================================

show_usage() {
    cat << 'EOF'
Resource Monitor for SDD Loop Controller v1.0.0

DESCRIPTION
    Background monitoring script that samples resource usage metrics
    at regular intervals and outputs to CSV format for analysis.

USAGE
    monitor-loop-resources.sh [options]

OPTIONS
    -h, --help              Show this help message
    --pid PID               Process ID to monitor
    --pid-file FILE         File containing PID to monitor
    --output FILE           Output CSV file (default: stdout)
    --interval SECONDS      Sampling interval (default: 300)
    --workspace DIR         Test workspace for additional metrics
    --max-samples N         Maximum samples (0=unlimited, default: 0)

OUTPUT FORMAT (CSV)
    timestamp,elapsed_sec,pid,memory_rss_kb,memory_vsz_kb,fd_count,
    cpu_percent,tasks_completed,tasks_failed,iteration_count

EXAMPLES
    # Monitor PID 1234 every 60 seconds
    monitor-loop-resources.sh --pid 1234 --interval 60

    # Monitor from PID file with output
    monitor-loop-resources.sh --pid-file /tmp/app.pid --output metrics.csv

    # Full load test integration
    monitor-loop-resources.sh \
        --pid-file /tmp/sdd-loop.pid \
        --output /tmp/metrics.csv \
        --interval 300 \
        --workspace /tmp/load-test

EOF
}

# =============================================================================
# Argument Parsing
# =============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                exit 0
                ;;
            --pid)
                if [[ -z "${2:-}" ]]; then
                    log_error "--pid requires a value"
                    exit 2
                fi
                TARGET_PID="$2"
                shift 2
                ;;
            --pid-file)
                if [[ -z "${2:-}" ]]; then
                    log_error "--pid-file requires a value"
                    exit 2
                fi
                PID_FILE="$2"
                shift 2
                ;;
            --output)
                if [[ -z "${2:-}" ]]; then
                    log_error "--output requires a value"
                    exit 2
                fi
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --interval)
                if [[ -z "${2:-}" ]]; then
                    log_error "--interval requires a value"
                    exit 2
                fi
                if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    log_error "--interval must be a positive integer"
                    exit 2
                fi
                INTERVAL="$2"
                shift 2
                ;;
            --workspace)
                if [[ -z "${2:-}" ]]; then
                    log_error "--workspace requires a value"
                    exit 2
                fi
                WORKSPACE="$2"
                shift 2
                ;;
            --max-samples)
                if [[ -z "${2:-}" ]]; then
                    log_error "--max-samples requires a value"
                    exit 2
                fi
                if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    log_error "--max-samples must be a non-negative integer"
                    exit 2
                fi
                MAX_SAMPLES="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                exit 2
                ;;
        esac
    done
}

# =============================================================================
# PID Resolution
# =============================================================================

resolve_pid() {
    # If PID was provided directly, use it
    if [[ -n "$TARGET_PID" ]]; then
        return 0
    fi

    # If PID file specified, read from it
    if [[ -n "$PID_FILE" ]]; then
        # Wait for PID file to appear (up to 30 seconds)
        local wait_count=0
        while [[ ! -f "$PID_FILE" && $wait_count -lt 30 ]]; do
            log_info "Waiting for PID file: $PID_FILE"
            sleep 1
            wait_count=$((wait_count + 1))
        done

        if [[ ! -f "$PID_FILE" ]]; then
            log_error "PID file not found after 30 seconds: $PID_FILE"
            return 1
        fi

        TARGET_PID=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -z "$TARGET_PID" ]]; then
            log_error "PID file is empty: $PID_FILE"
            return 1
        fi
    fi

    # Validate PID
    if [[ -z "$TARGET_PID" ]]; then
        log_error "No PID specified. Use --pid or --pid-file"
        return 1
    fi

    if ! [[ "$TARGET_PID" =~ ^[0-9]+$ ]]; then
        log_error "Invalid PID: $TARGET_PID"
        return 1
    fi

    return 0
}

# =============================================================================
# Metric Collection Functions
# =============================================================================

#######################################
# Get memory usage (RSS and VSZ) for a process
# Arguments:
#   $1 - PID
# Outputs:
#   rss_kb,vsz_kb (comma-separated)
# Returns:
#   0 on success, 1 on error
#######################################
get_memory_usage() {
    local pid="$1"
    local rss_kb vsz_kb

    # Try /proc first (Linux)
    if [[ -f "/proc/$pid/status" ]]; then
        # VmRSS and VmSize are in kB
        rss_kb=$(grep -i 'VmRSS' "/proc/$pid/status" 2>/dev/null | awk '{print $2}' || echo "0")
        vsz_kb=$(grep -i 'VmSize' "/proc/$pid/status" 2>/dev/null | awk '{print $2}' || echo "0")
    else
        # Fall back to ps (macOS, BSD)
        local ps_output
        ps_output=$(ps -o rss=,vsz= -p "$pid" 2>/dev/null | head -1)
        if [[ -n "$ps_output" ]]; then
            rss_kb=$(echo "$ps_output" | awk '{print $1}')
            vsz_kb=$(echo "$ps_output" | awk '{print $2}')
        else
            rss_kb="0"
            vsz_kb="0"
        fi
    fi

    echo "${rss_kb:-0},${vsz_kb:-0}"
}

#######################################
# Get file descriptor count for a process
# Arguments:
#   $1 - PID
# Outputs:
#   fd_count
# Returns:
#   0 on success, 1 on error
#######################################
get_fd_count() {
    local pid="$1"
    local fd_count

    # Try /proc first (Linux)
    if [[ -d "/proc/$pid/fd" ]]; then
        fd_count=$(ls -1 "/proc/$pid/fd" 2>/dev/null | wc -l)
    else
        # Fall back to lsof (macOS, BSD)
        if command -v lsof &>/dev/null; then
            # Skip header line with tail -n +2
            fd_count=$(lsof -p "$pid" 2>/dev/null | tail -n +2 | wc -l)
        else
            fd_count="0"
        fi
    fi

    echo "${fd_count:-0}"
}

#######################################
# Get CPU usage percentage for a process
# Arguments:
#   $1 - PID
# Outputs:
#   cpu_percent (may be decimal)
# Returns:
#   0 on success
#######################################
get_cpu_usage() {
    local pid="$1"
    local cpu_percent

    # Use ps to get CPU percentage
    cpu_percent=$(ps -o %cpu= -p "$pid" 2>/dev/null | tr -d ' ' || echo "0")

    # Handle empty result
    if [[ -z "$cpu_percent" ]]; then
        cpu_percent="0"
    fi

    echo "$cpu_percent"
}

#######################################
# Get task counters from workspace
# Arguments:
#   None (uses WORKSPACE global)
# Outputs:
#   completed,failed,iterations (comma-separated)
#######################################
get_task_counters() {
    local completed="0"
    local failed="0"
    local iterations="0"

    if [[ -n "$WORKSPACE" && -d "$WORKSPACE" ]]; then
        if [[ -f "$WORKSPACE/completed_tasks" ]]; then
            completed=$(cat "$WORKSPACE/completed_tasks" 2>/dev/null || echo "0")
        fi
        if [[ -f "$WORKSPACE/failed_tasks" ]]; then
            failed=$(cat "$WORKSPACE/failed_tasks" 2>/dev/null || echo "0")
        fi
        if [[ -f "$WORKSPACE/iteration_counter" ]]; then
            iterations=$(cat "$WORKSPACE/iteration_counter" 2>/dev/null || echo "0")
        fi
    fi

    echo "${completed:-0},${failed:-0},${iterations:-0}"
}

#######################################
# Collect all metrics for current sample
# Arguments:
#   $1 - PID
# Outputs:
#   Full CSV line
#######################################
collect_sample() {
    local pid="$1"
    local timestamp
    local elapsed_sec
    local memory_info
    local fd_count
    local cpu_percent
    local task_counters

    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    elapsed_sec=$(($(date +%s) - START_TIME))

    memory_info=$(get_memory_usage "$pid")
    fd_count=$(get_fd_count "$pid")
    cpu_percent=$(get_cpu_usage "$pid")
    task_counters=$(get_task_counters)

    echo "$timestamp,$elapsed_sec,$pid,$memory_info,$fd_count,$cpu_percent,$task_counters"
}

# =============================================================================
# Output Functions
# =============================================================================

write_header() {
    local header="timestamp,elapsed_sec,pid,memory_rss_kb,memory_vsz_kb,fd_count,cpu_percent,tasks_completed,tasks_failed,iteration_count"

    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "$header" > "$OUTPUT_FILE"
    else
        echo "$header"
    fi
}

write_sample() {
    local line="$1"

    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "$line" >> "$OUTPUT_FILE"
    else
        echo "$line"
    fi
}

# =============================================================================
# Main Monitoring Loop
# =============================================================================

monitor_loop() {
    log_info "Starting monitoring for PID $TARGET_PID (interval: ${INTERVAL}s)"

    START_TIME=$(date +%s)
    write_header

    while true; do
        # Check if process is still running
        if ! kill -0 "$TARGET_PID" 2>/dev/null; then
            log_info "Process $TARGET_PID no longer running, stopping monitor"
            break
        fi

        # Collect and write sample
        local sample
        sample=$(collect_sample "$TARGET_PID")
        write_sample "$sample"

        SAMPLE_COUNT=$((SAMPLE_COUNT + 1))

        # Check max samples limit
        if [[ $MAX_SAMPLES -gt 0 && $SAMPLE_COUNT -ge $MAX_SAMPLES ]]; then
            log_info "Reached max samples ($MAX_SAMPLES), stopping monitor"
            break
        fi

        # Re-resolve PID in case it changed (for PID file mode)
        if [[ -n "$PID_FILE" && -f "$PID_FILE" ]]; then
            local new_pid
            new_pid=$(cat "$PID_FILE" 2>/dev/null)
            if [[ -n "$new_pid" && "$new_pid" != "$TARGET_PID" ]]; then
                log_info "PID changed from $TARGET_PID to $new_pid"
                TARGET_PID="$new_pid"
            fi
        fi

        # Wait for next sample interval
        sleep "$INTERVAL"
    done

    log_info "Monitoring complete. Collected $SAMPLE_COUNT samples."
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    # Resolve target PID
    if ! resolve_pid; then
        exit 1
    fi

    # Verify process exists
    if ! kill -0 "$TARGET_PID" 2>/dev/null; then
        log_error "Process $TARGET_PID not found"
        exit 1
    fi

    log_info "Monitor v$VERSION starting"
    log_info "Target PID: $TARGET_PID"
    log_info "Interval: ${INTERVAL}s"
    if [[ -n "$OUTPUT_FILE" ]]; then
        log_info "Output: $OUTPUT_FILE"
    fi

    # Run monitoring loop
    monitor_loop

    exit 0
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
