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

    # Output JSON
    echo "{"
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"workspace_root\": \"$(json_escape "$workspace_root")\","

    discover_sdd_directories "$workspace_root"

    echo "}"
}

# Run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
