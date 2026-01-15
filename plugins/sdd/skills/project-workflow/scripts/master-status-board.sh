#!/bin/bash
#
# Master Status Board
# Multi-repository SDD status aggregator
#
# Version: 1.0.0
# Description: Discovers all _SDD directories across multiple repositories
#              in a workspace and aggregates status information.
#
# Usage:
#   bash master-status-board.sh [options] [workspace_root]
#   bash master-status-board.sh                    # Use default workspace
#   bash master-status-board.sh /path/to/repos    # Use specific workspace
#   WORKSPACE_ROOT=/custom/path bash master-status-board.sh
#
# Arguments:
#   workspace_root    Root directory containing repositories (optional)
#                     Priority: argument > WORKSPACE_ROOT env var > default
#                     Default: /workspace/repos/
#
# Options:
#   --help, -h        Show this help message
#   --debug           Enable debug output to stderr
#
# Environment Variables:
#   WORKSPACE_ROOT    Alternative to passing workspace root as argument
#
# Output (JSON):
#   {
#     "timestamp": "2024-01-15T10:30:00+00:00",
#     "workspace_root": "/workspace/repos/",
#     "repos": [
#       {
#         "name": "repo-name",
#         "sdd_path": "/workspace/repos/repo-name/_SDD",
#         "repo_path": "/workspace/repos/repo-name"
#       }
#     ]
#   }
#
# JSON Schema:
#   type: object
#   required: [timestamp, workspace_root, repos]
#   properties:
#     timestamp:
#       type: string
#       format: date-time
#       description: ISO 8601 timestamp of scan
#     workspace_root:
#       type: string
#       description: Absolute path to workspace root
#     repos:
#       type: array
#       items:
#         type: object
#         required: [name, sdd_path, repo_path]
#         properties:
#           name:
#             type: string
#             description: Repository directory name
#           sdd_path:
#             type: string
#             description: Absolute path to _SDD directory
#           repo_path:
#             type: string
#             description: Absolute path to repository root
#
# Exit Codes:
#   0 - Success (including empty workspace)
#   1 - Workspace directory does not exist
#   2 - Invalid arguments
#

set -euo pipefail

# Configuration defaults (guard against re-sourcing)
[[ -z "${DEFAULT_WORKSPACE_ROOT:-}" ]] && readonly DEFAULT_WORKSPACE_ROOT="/workspace/repos/"
[[ -z "${MAX_SEARCH_DEPTH:-}" ]] && readonly MAX_SEARCH_DEPTH=2
[[ -z "${VERSION:-}" ]] && readonly VERSION="1.0.0"

# Global flags
DEBUG="${DEBUG:-false}"

#######################################
# Print debug message to stderr
# Arguments:
#   $@ - Message to print
# Outputs:
#   Writes message to stderr if DEBUG is enabled
#######################################
debug_log() {
    if [[ "$DEBUG" == "true" ]]; then
        echo "[DEBUG] $*" >&2
    fi
}

#######################################
# Strip code blocks from file content
# Removes fenced code blocks (``` ... ```) to avoid parsing
# checkboxes that appear in code examples
# Arguments:
#   $1 - File content (stdin if not provided)
# Outputs:
#   Content with code blocks removed
#######################################
strip_code_blocks() {
    local content
    if [[ $# -gt 0 ]]; then
        content="$1"
    else
        content=$(cat)
    fi

    # Use awk to remove content between ``` markers
    # State machine: in_block toggles on/off when we see ```
    echo "$content" | awk '
        BEGIN { in_block = 0 }
        /^```/ { in_block = !in_block; next }
        !in_block { print }
    '
}

#######################################
# Scan a task file and extract checkbox status
# Arguments:
#   $1 - Path to task markdown file
# Outputs:
#   JSON object with task status to stdout
# Returns:
#   0 on success
#   1 if file does not exist
#######################################
scan_task() {
    local task_file="$1"

    # Validate file exists
    if [[ ! -f "$task_file" ]]; then
        debug_log "Task file not found: $task_file"
        # Return JSON with error status
        printf '{\n'
        printf '  "file": "%s",\n' "$(json_escape "$task_file")"
        printf '  "task_id": "",\n'
        printf '  "task_completed": false,\n'
        printf '  "tests_pass": false,\n'
        printf '  "verified": false,\n'
        printf '  "error": "File not found"\n'
        printf '}'
        return 1
    fi

    # Extract task ID from filename
    # Supports formats: SDDLOOP-1.1002_task-scanner.md, PROJ.1001_name.md, UIT-9819.1001_name.md
    local filename
    filename=$(basename "$task_file" .md)
    local task_id=""
    if [[ "$filename" =~ ^([A-Z][A-Z0-9]*(-[A-Z0-9]+)*\.[0-9]+) ]]; then
        task_id="${BASH_REMATCH[1]}"
    fi

    debug_log "Scanning task: $task_file (ID: $task_id)"

    # Read file content and strip code blocks
    local content
    content=$(strip_code_blocks < "$task_file")

    # Initialize checkbox states (fail-safe: default to false)
    local task_completed=false
    local tests_pass=false
    local verified=false

    # Check for "Task completed" checkbox
    # Pattern: "- [x] **Task completed**" or "- [X] **Task completed**"
    # Uses case-insensitive match for x/X
    if echo "$content" | grep -qE '^\s*-\s*\[[xX]\]\s*\*\*Task completed\*\*'; then
        task_completed=true
        debug_log "  Task completed: checked"
    fi

    # Check for "Tests pass" checkbox
    if echo "$content" | grep -qE '^\s*-\s*\[[xX]\]\s*\*\*Tests pass\*\*'; then
        tests_pass=true
        debug_log "  Tests pass: checked"
    fi

    # Check for "Verified" checkbox
    if echo "$content" | grep -qE '^\s*-\s*\[[xX]\]\s*\*\*Verified\*\*'; then
        verified=true
        debug_log "  Verified: checked"
    fi

    # Output JSON object
    printf '{\n'
    printf '  "file": "%s",\n' "$(json_escape "$task_file")"
    printf '  "task_id": "%s",\n' "$(json_escape "$task_id")"
    printf '  "task_completed": %s,\n' "$task_completed"
    printf '  "tests_pass": %s,\n' "$tests_pass"
    printf '  "verified": %s\n' "$verified"
    printf '}'
}

#######################################
# Read autogate configuration from .autogate.json file
# Arguments:
#   $1 - Path to .autogate.json file
# Outputs:
#   JSON object with autogate configuration to stdout
# Notes:
#   - Missing file returns default: ready=true, agent_ready=false
#   - Malformed JSON returns default with warning to stderr
#   - Missing fields are filled with defaults
#   - Extra fields are ignored (forward compatibility)
#######################################
read_autogate() {
    local autogate_file="$1"

    # Default values as JSON
    local default_json='{"ready": true, "agent_ready": false, "priority": null, "stop_at_phase": null}'

    debug_log "read_autogate: $autogate_file"

    # Check if file exists and is readable
    if [[ ! -f "$autogate_file" ]] || [[ ! -r "$autogate_file" ]]; then
        debug_log "  File missing or not readable, using defaults"
        echo "$default_json"
        return 0
    fi

    # Check if file is empty
    if [[ ! -s "$autogate_file" ]]; then
        echo "Warning: Empty .autogate.json at $autogate_file, using defaults" >&2
        debug_log "  File is empty, using defaults"
        echo "$default_json"
        return 0
    fi

    # Attempt to parse with jq
    # Use defaults for missing fields:
    # - ready: defaults to true (allow human work)
    # - agent_ready: defaults to false (block autonomous work)
    # - priority: defaults to null (no priority set)
    # - stop_at_phase: defaults to null (no phase limit)
    local parsed
    if ! parsed=$(jq -c '{
        ready: (if .ready == null then true else .ready end),
        agent_ready: (if .agent_ready == null then false else .agent_ready end),
        priority: (.priority // null),
        stop_at_phase: (.stop_at_phase // null)
    }' "$autogate_file" 2>/dev/null); then
        echo "Warning: Malformed .autogate.json at $autogate_file, using defaults" >&2
        debug_log "  JSON parse error, using defaults"
        echo "$default_json"
        return 0
    fi

    debug_log "  Parsed autogate: $parsed"
    echo "$parsed"
}

#######################################
# Scan a ticket directory and aggregate task status
# Arguments:
#   $1 - Path to ticket directory
# Outputs:
#   JSON object with ticket status and task summaries to stdout
# Returns:
#   0 on success
#   1 if directory does not exist
#######################################
scan_ticket() {
    local ticket_dir="$1"

    # Validate directory exists
    if [[ ! -d "$ticket_dir" ]]; then
        debug_log "Ticket directory not found: $ticket_dir"
        printf '{\n'
        printf '  "ticket_id": "",\n'
        printf '  "name": "",\n'
        printf '  "path": "%s",\n' "$(json_escape "$ticket_dir")"
        printf '  "autogate": {"ready": true, "agent_ready": false, "priority": null, "stop_at_phase": null},\n'
        printf '  "tasks": [],\n'
        printf '  "summary": {"total_tasks": 0, "pending": 0, "completed": 0, "tested": 0, "verified": 0},\n'
        printf '  "error": "Directory not found"\n'
        printf '}'
        return 1
    fi

    # Extract ticket ID from directory name
    local ticket_id
    ticket_id=$(basename "$ticket_dir")
    debug_log "Scanning ticket: $ticket_dir (ID: $ticket_id)"

    # Extract ticket name from README.md first line (# Title) or fallback to directory name
    local ticket_name
    ticket_name=$(head -n 1 "$ticket_dir/README.md" 2>/dev/null | sed 's/^#[[:space:]]*//')
    if [[ -z "$ticket_name" ]]; then
        ticket_name="$ticket_id"
        debug_log "  No README.md title found, using directory name: $ticket_name"
    else
        debug_log "  Ticket name from README: $ticket_name"
    fi

    # Read autogate configuration (stub returns defaults)
    local autogate_json
    local autogate_file="$ticket_dir/.autogate.json"
    if [[ -f "$autogate_file" ]]; then
        autogate_json=$(read_autogate "$autogate_file")
        debug_log "  Read autogate from: $autogate_file"
    else
        autogate_json='{"ready": true, "agent_ready": false, "priority": null, "stop_at_phase": null}'
        debug_log "  No .autogate.json, using defaults"
    fi

    # Initialize counters
    local total_tasks=0
    local pending=0
    local completed=0
    local tested=0
    local verified=0

    # Collect task JSON objects
    local tasks_json=""
    local first_task=true
    local tasks_dir="$ticket_dir/tasks"

    # Scan tasks if tasks/ directory exists
    if [[ -d "$tasks_dir" ]]; then
        debug_log "  Scanning tasks directory: $tasks_dir"

        # Find all .md files in tasks directory (not recursive)
        while IFS= read -r -d '' task_file; do
            debug_log "    Found task file: $task_file"

            # Get task status by calling scan_task
            local task_json
            task_json=$(scan_task "$task_file")

            # Add comma separator between tasks
            if [[ "$first_task" == "true" ]]; then
                first_task=false
            else
                tasks_json+=","
            fi
            tasks_json+=$'\n'"      $task_json"

            # Extract checkbox states for aggregation
            local task_completed tests_pass task_verified
            task_completed=$(echo "$task_json" | grep -o '"task_completed": [a-z]*' | grep -o 'true\|false')
            tests_pass=$(echo "$task_json" | grep -o '"tests_pass": [a-z]*' | grep -o 'true\|false')
            task_verified=$(echo "$task_json" | grep -o '"verified": [a-z]*' | grep -o 'true\|false')

            # Increment total
            total_tasks=$((total_tasks + 1))

            # Aggregate logic:
            # - pending: !task_completed
            # - completed: task_completed && !tests_pass
            # - tested: tests_pass && !verified
            # - verified: verified
            if [[ "$task_verified" == "true" ]]; then
                verified=$((verified + 1))
            elif [[ "$tests_pass" == "true" ]]; then
                tested=$((tested + 1))
            elif [[ "$task_completed" == "true" ]]; then
                completed=$((completed + 1))
            else
                pending=$((pending + 1))
            fi
        done < <(find "$tasks_dir" -maxdepth 1 -type f -name "*.md" -print0 2>/dev/null | sort -z)
    else
        debug_log "  No tasks/ directory found"
    fi

    # Output JSON object
    printf '{\n'
    printf '  "ticket_id": "%s",\n' "$(json_escape "$ticket_id")"
    printf '  "name": "%s",\n' "$(json_escape "$ticket_name")"
    printf '  "path": "%s",\n' "$(json_escape "$ticket_dir")"
    printf '  "autogate": %s,\n' "$autogate_json"
    printf '  "tasks": ['
    if [[ -n "$tasks_json" ]]; then
        printf '%s\n' "$tasks_json"
        printf '  ],\n'
    else
        printf '],\n'
    fi
    printf '  "summary": {\n'
    printf '    "total_tasks": %d,\n' "$total_tasks"
    printf '    "pending": %d,\n' "$pending"
    printf '    "completed": %d,\n' "$completed"
    printf '    "tested": %d,\n' "$tested"
    printf '    "verified": %d\n' "$verified"
    printf '  }\n'
    printf '}'
}

#######################################
# Scan a repository's _SDD directory and aggregate all tickets
# Arguments:
#   $1 - Path to _SDD directory
# Outputs:
#   JSON object with repo status and ticket summaries to stdout
# Returns:
#   0 on success
#   1 if directory does not exist
#######################################
scan_repo() {
    local sdd_root="$1"

    # Validate directory exists
    if [[ ! -d "$sdd_root" ]]; then
        debug_log "SDD root directory not found: $sdd_root"
        printf '{\n'
        printf '  "name": "",\n'
        printf '  "sdd_root": "%s",\n' "$(json_escape "$sdd_root")"
        printf '  "tickets": [],\n'
        printf '  "summary": {"total_tickets": 0, "total_tasks": 0, "pending": 0, "completed": 0, "tested": 0, "verified": 0},\n'
        printf '  "error": "Directory not found"\n'
        printf '}'
        return 1
    fi

    # Extract repo name from parent directory of _SDD
    local repo_name
    repo_name=$(basename "$(dirname "$sdd_root")")
    debug_log "Scanning repo: $repo_name (SDD root: $sdd_root)"

    # Initialize aggregation counters
    local total_tickets=0
    local total_tasks=0
    local total_pending=0
    local total_completed=0
    local total_tested=0
    local total_verified=0

    # Collect ticket JSON objects
    local tickets_json=""
    local first_ticket=true
    local tickets_dir="$sdd_root/tickets"

    # Scan tickets if tickets/ directory exists
    if [[ -d "$tickets_dir" ]]; then
        debug_log "  Scanning tickets directory: $tickets_dir"

        # Find all ticket directories (not recursive, one level only)
        while IFS= read -r -d '' ticket_dir; do
            # Skip if not a directory (shouldn't happen with -type d, but be safe)
            [[ ! -d "$ticket_dir" ]] && continue

            debug_log "    Found ticket directory: $ticket_dir"

            # Get ticket status by calling scan_ticket
            local ticket_json
            ticket_json=$(scan_ticket "$ticket_dir")

            # Add comma separator between tickets
            if [[ "$first_ticket" == "true" ]]; then
                first_ticket=false
            else
                tickets_json+=","
            fi
            tickets_json+=$'\n'"      $ticket_json"

            # Extract summary values for aggregation
            local ticket_tasks ticket_pending ticket_completed ticket_tested ticket_verified
            ticket_tasks=$(echo "$ticket_json" | grep -o '"total_tasks": [0-9]*' | grep -o '[0-9]*')
            ticket_pending=$(echo "$ticket_json" | grep -o '"pending": [0-9]*' | grep -o '[0-9]*')
            ticket_completed=$(echo "$ticket_json" | grep -o '"completed": [0-9]*' | grep -o '[0-9]*')
            ticket_tested=$(echo "$ticket_json" | grep -o '"tested": [0-9]*' | grep -o '[0-9]*')
            ticket_verified=$(echo "$ticket_json" | grep -o '"verified": [0-9]*' | grep -o '[0-9]*')

            # Handle empty values (default to 0)
            ticket_tasks=${ticket_tasks:-0}
            ticket_pending=${ticket_pending:-0}
            ticket_completed=${ticket_completed:-0}
            ticket_tested=${ticket_tested:-0}
            ticket_verified=${ticket_verified:-0}

            # Aggregate
            total_tickets=$((total_tickets + 1))
            total_tasks=$((total_tasks + ticket_tasks))
            total_pending=$((total_pending + ticket_pending))
            total_completed=$((total_completed + ticket_completed))
            total_tested=$((total_tested + ticket_tested))
            total_verified=$((total_verified + ticket_verified))
        done < <(find "$tickets_dir" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null | sort -z)
    else
        debug_log "  No tickets/ directory found in $sdd_root"
    fi

    # Output JSON object
    printf '{\n'
    printf '  "name": "%s",\n' "$(json_escape "$repo_name")"
    printf '  "sdd_root": "%s",\n' "$(json_escape "$sdd_root")"
    printf '  "tickets": ['
    if [[ -n "$tickets_json" ]]; then
        printf '%s\n' "$tickets_json"
        printf '  ],\n'
    else
        printf '],\n'
    fi
    printf '  "summary": {\n'
    printf '    "total_tickets": %d,\n' "$total_tickets"
    printf '    "total_tasks": %d,\n' "$total_tasks"
    printf '    "pending": %d,\n' "$total_pending"
    printf '    "completed": %d,\n' "$total_completed"
    printf '    "tested": %d,\n' "$total_tested"
    printf '    "verified": %d\n' "$total_verified"
    printf '  }\n'
    printf '}'
}

#######################################
# Escape string for safe JSON output
# Arguments:
#   $1 - String to escape
# Outputs:
#   JSON-safe escaped string
#######################################
json_escape() {
    local str="$1"
    # Escape backslashes first, then quotes
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    echo -n "$str"
}

#######################################
# Show usage information
# Outputs:
#   Help text to stdout
#######################################
show_help() {
    cat << 'EOF'
Master Status Board - Multi-repository SDD status aggregator

Usage:
  bash master-status-board.sh [options] [workspace_root]

Examples:
  bash master-status-board.sh                         # Use default workspace
  bash master-status-board.sh /path/to/repos          # Use specific workspace
  WORKSPACE_ROOT=/custom/path bash master-status-board.sh
  bash master-status-board.sh --debug /workspace/repos

Arguments:
  workspace_root    Root directory containing repositories (optional)
                    Priority: argument > WORKSPACE_ROOT env var > default
                    Default: /workspace/repos/

Options:
  --help, -h        Show this help message
  --debug           Enable debug output to stderr

Environment Variables:
  WORKSPACE_ROOT    Alternative to passing workspace root as argument
  DEBUG             Set to "true" to enable debug output

Exit Codes:
  0 - Success (including empty workspace)
  1 - Workspace directory does not exist
  2 - Invalid arguments
EOF
}

#######################################
# Resolve path to absolute, following symlinks if safe
# Arguments:
#   $1 - Path to resolve
#   $2 - Workspace root for symlink validation
# Outputs:
#   Absolute path, or empty string if symlink points outside workspace
#######################################
resolve_path() {
    local path="$1"
    local workspace_root="$2"
    local resolved

    # Check if it's a symlink
    if [[ -L "$path" ]]; then
        # Resolve the symlink target
        resolved=$(readlink -f "$path" 2>/dev/null) || return 1

        # Validate symlink remains within workspace root
        if [[ ! "$resolved" == "$workspace_root"* ]]; then
            debug_log "Symlink $path points outside workspace: $resolved"
            return 1
        fi
        echo "$resolved"
    else
        # Not a symlink, just canonicalize
        readlink -f "$path" 2>/dev/null || return 1
    fi
}

#######################################
# Discover all _SDD directories under workspace root
# Arguments:
#   $1 - Workspace root directory
# Outputs:
#   JSON array of discovered repos to stdout
#   Warnings to stderr for permission errors
#######################################
discover_sdd_directories() {
    local workspace_root="$1"
    local first=true

    debug_log "Discovering _SDD directories in: $workspace_root"

    # Use find with maxdepth to limit search scope
    # -type d: only directories
    # -name "_SDD": exact match
    # 2>/dev/null: suppress permission denied errors (we handle them)
    local find_output
    find_output=$(find "$workspace_root" -maxdepth "$MAX_SEARCH_DEPTH" -type d -name "_SDD" 2>&1) || true

    # Separate actual results from errors
    local sdd_dirs=""
    local errors=""

    while IFS= read -r line; do
        if [[ "$line" == *"Permission denied"* ]]; then
            errors+="$line"$'\n'
        elif [[ -n "$line" && -d "$line" ]]; then
            sdd_dirs+="$line"$'\n'
        fi
    done <<< "$find_output"

    # Log permission errors to stderr
    if [[ -n "$errors" ]]; then
        echo "Warning: Some directories were not accessible:" >&2
        echo "$errors" >&2
    fi

    # Output JSON array of repos
    echo "  \"repos\": ["

    # Process discovered directories
    if [[ -n "$sdd_dirs" ]]; then
        # Sort for consistent output
        local sorted_dirs
        sorted_dirs=$(echo -n "$sdd_dirs" | sort)

        while IFS= read -r sdd_path; do
            [[ -z "$sdd_path" ]] && continue

            # Resolve and validate the path
            local resolved_path
            resolved_path=$(resolve_path "$sdd_path" "$workspace_root") || {
                debug_log "Skipping invalid path: $sdd_path"
                continue
            }

            # Extract repo name (parent directory of _SDD)
            local repo_path
            repo_path=$(dirname "$resolved_path")
            local repo_name
            repo_name=$(basename "$repo_path")

            debug_log "Found _SDD in repo: $repo_name"

            # Output JSON object
            if [[ "$first" == "true" ]]; then
                first=false
            else
                # Print comma before next object (on same line as previous closing brace)
                printf ",\n"
            fi

            printf '    {\n'
            printf '      "name": "%s",\n' "$(json_escape "$repo_name")"
            printf '      "sdd_path": "%s",\n' "$(json_escape "$resolved_path")"
            printf '      "repo_path": "%s"\n' "$(json_escape "$repo_path")"
            printf '    }'
        done <<< "$sorted_dirs"
        # Add newline after last object
        echo ""
    fi

    echo "  ]"
}

#######################################
# Main entry point
# Arguments:
#   $@ - Command line arguments
#######################################
main() {
    local workspace_root=""
    local positional_args=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help
                exit 0
                ;;
            --debug)
                DEBUG="true"
                shift
                ;;
            -*)
                echo "Error: Unknown option: $1" >&2
                echo "Use --help for usage information" >&2
                exit 2
                ;;
            *)
                positional_args+=("$1")
                shift
                ;;
        esac
    done

    # Determine workspace root (priority: argument > env var > default)
    if [[ ${#positional_args[@]} -gt 0 ]]; then
        workspace_root="${positional_args[0]}"
    elif [[ -n "${WORKSPACE_ROOT:-}" ]]; then
        workspace_root="$WORKSPACE_ROOT"
    else
        workspace_root="$DEFAULT_WORKSPACE_ROOT"
    fi

    debug_log "Workspace root: $workspace_root"

    # Expand to absolute path
    if [[ ! "$workspace_root" = /* ]]; then
        workspace_root="$(cd "$workspace_root" 2>/dev/null && pwd)" || {
            echo "Error: Cannot resolve workspace root path: $workspace_root" >&2
            exit 1
        }
    fi

    # Ensure trailing slash for consistent path handling
    workspace_root="${workspace_root%/}/"

    # Validate workspace directory exists
    if [[ ! -d "$workspace_root" ]]; then
        echo "Error: Workspace directory does not exist: $workspace_root" >&2
        exit 1
    fi

    debug_log "Resolved workspace root: $workspace_root"

    # Discover all _SDD directories
    debug_log "Discovering _SDD directories in: $workspace_root"

    local find_output
    find_output=$(find "$workspace_root" -maxdepth "$MAX_SEARCH_DEPTH" -type d -name "_SDD" 2>&1) || true

    # Separate actual results from errors
    local sdd_dirs=""
    local errors=""

    while IFS= read -r line; do
        if [[ "$line" == *"Permission denied"* ]]; then
            errors+="$line"$'\n'
        elif [[ -n "$line" && -d "$line" ]]; then
            sdd_dirs+="$line"$'\n'
        fi
    done <<< "$find_output"

    # Log permission errors to stderr
    if [[ -n "$errors" ]]; then
        echo "Warning: Some directories were not accessible:" >&2
        echo "$errors" >&2
    fi

    # Initialize workspace-level aggregation counters
    local total_repos=0
    local total_tickets=0
    local total_tasks=0
    local total_pending=0
    local total_completed=0
    local total_tested=0
    local total_verified=0

    # Collect repo JSON objects
    local repos_json=""
    local first_repo=true

    # Process discovered directories
    if [[ -n "$sdd_dirs" ]]; then
        # Sort for consistent output
        local sorted_dirs
        sorted_dirs=$(echo -n "$sdd_dirs" | sort)

        while IFS= read -r sdd_path; do
            [[ -z "$sdd_path" ]] && continue

            # Resolve and validate the path
            local resolved_path
            resolved_path=$(resolve_path "$sdd_path" "$workspace_root") || {
                debug_log "Skipping invalid path: $sdd_path"
                continue
            }

            debug_log "Found _SDD: $resolved_path"

            # Scan the repo using scan_repo function
            local repo_json
            repo_json=$(scan_repo "$resolved_path")

            # Add comma separator between repos
            if [[ "$first_repo" == "true" ]]; then
                first_repo=false
            else
                repos_json+=","
            fi
            repos_json+=$'\n'"    $repo_json"

            # Extract summary values for workspace-level aggregation
            # Use tail -1 to get the repo-level summary (last occurrence) instead of ticket summaries
            local repo_tickets repo_tasks repo_pending repo_completed repo_tested repo_verified
            repo_tickets=$(echo "$repo_json" | grep -o '"total_tickets": [0-9]*' | tail -1 | grep -o '[0-9]*')
            repo_tasks=$(echo "$repo_json" | grep -o '"total_tasks": [0-9]*' | tail -1 | grep -o '[0-9]*')
            repo_pending=$(echo "$repo_json" | grep -o '"pending": [0-9]*' | tail -1 | grep -o '[0-9]*')
            repo_completed=$(echo "$repo_json" | grep -o '"completed": [0-9]*' | tail -1 | grep -o '[0-9]*')
            repo_tested=$(echo "$repo_json" | grep -o '"tested": [0-9]*' | tail -1 | grep -o '[0-9]*')
            repo_verified=$(echo "$repo_json" | grep -o '"verified": [0-9]*' | tail -1 | grep -o '[0-9]*')

            # Handle empty values (default to 0)
            repo_tickets=${repo_tickets:-0}
            repo_tasks=${repo_tasks:-0}
            repo_pending=${repo_pending:-0}
            repo_completed=${repo_completed:-0}
            repo_tested=${repo_tested:-0}
            repo_verified=${repo_verified:-0}

            # Aggregate at workspace level
            total_repos=$((total_repos + 1))
            total_tickets=$((total_tickets + repo_tickets))
            total_tasks=$((total_tasks + repo_tasks))
            total_pending=$((total_pending + repo_pending))
            total_completed=$((total_completed + repo_completed))
            total_tested=$((total_tested + repo_tested))
            total_verified=$((total_verified + repo_verified))
        done <<< "$sorted_dirs"
    fi

    # Output final JSON
    echo "{"
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"workspace_root\": \"$(json_escape "$workspace_root")\","
    echo "  \"repos\": ["
    if [[ -n "$repos_json" ]]; then
        echo "$repos_json"
    fi
    echo "  ],"
    echo "  \"summary\": {"
    echo "    \"total_repos\": $total_repos,"
    echo "    \"total_tickets\": $total_tickets,"
    echo "    \"total_tasks\": $total_tasks,"
    echo "    \"pending\": $total_pending,"
    echo "    \"completed\": $total_completed,"
    echo "    \"tested\": $total_tested,"
    echo "    \"verified\": $total_verified"
    echo "  }"
    echo "}"
}

# Run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
