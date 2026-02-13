#!/bin/bash
#
# Master Status Board
# Multi-repository SDD status aggregator
#
# Version: 2.0.0
# Description: Discovers all SDD spec directories under a specs root
#              and maps them to repos under a repos root, aggregating
#              status information across the two-root structure.
#
# Usage:
#   bash master-status-board.sh [options]
#
# Examples:
#   bash master-status-board.sh                                      # Use defaults
#   bash master-status-board.sh --specs-root /workspace/_SPECS/      # Custom specs root
#   bash master-status-board.sh --repos-root /workspace/repos/       # Custom repos root
#   bash master-status-board.sh --summary-only --verbose
#   SPECS_ROOT=/custom/_SPECS/ REPOS_ROOT=/custom/repos/ bash master-status-board.sh
#
# Options:
#   -h, --help          Show this help message and exit
#   -q, --quiet         Suppress progress messages (to stderr)
#   -s, --summary-only  Output only summary section (no per-repo details)
#   -v, --verbose       Include timing output for each repo scan (to stderr)
#   --specs-root PATH   Root directory containing SDD spec directories
#                        Priority: --specs-root > SPECS_ROOT env var > default
#                        Default: /workspace/_SPECS/
#   --repos-root PATH   Root directory containing code repositories
#                        Priority: --repos-root > REPOS_ROOT env var > default
#                        Default: /workspace/repos/
#   --json              Output JSON format (default, explicit specification)
#   --debug             Enable debug output to stderr
#
# Environment Variables:
#   SPECS_ROOT        Alternative to passing --specs-root option
#   REPOS_ROOT        Alternative to passing --repos-root option
#   WORKSPACE_ROOT    Deprecated: maps to REPOS_ROOT with warning
#   DEBUG             Set to "true" to enable debug output
#
# Output (JSON):
#   {
#     "version": "2.0.0",
#     "timestamp": "2024-01-15T10:30:00+00:00",
#     "specs_root": "/workspace/_SPECS/",
#     "repos_root": "/workspace/repos/",
#     "repos": [
#       {
#         "name": "repo-name",
#         "sdd_path": "/workspace/_SPECS/repo-name",
#         "repo_path": "/workspace/repos/repo-name"
#       }
#     ]
#   }
#
# JSON Schema:
#   type: object
#   required: [version, timestamp, specs_root, repos_root, repos]
#   properties:
#     version:
#       type: string
#       pattern: "^\\d+\\.\\d+\\.\\d+$"
#       description: Semantic version (MAJOR.MINOR.PATCH) for schema compatibility
#     timestamp:
#       type: string
#       format: date-time
#       description: ISO 8601 timestamp of scan
#     specs_root:
#       type: string
#       description: Absolute path to specs root directory
#     repos_root:
#       type: string
#       description: Absolute path to repos root directory
#     repos:
#       type: array
#       items:
#         type: object
#         required: [name, sdd_path]
#         properties:
#           name:
#             type: string
#             description: Repository directory name
#           sdd_path:
#             type: string
#             description: Absolute path to SDD spec directory
#           repo_path:
#             type: string
#             nullable: true
#             description: Absolute path to repository root, or null if not found
#           repo_status:
#             type: string
#             description: Present only when repo_path is null, value is "repo_not_found"
#
# Exit Codes:
#   0 - Success (including empty specs root)
#   1 - Specs directory does not exist
#   2 - Invalid arguments
#

set -euo pipefail

# Version constant
VERSION="2.0.0"

# Configuration defaults (guard against re-sourcing)
[ -z "${DEFAULT_SPECS_ROOT:-}" ] && readonly DEFAULT_SPECS_ROOT="/workspace/_SPECS/"
[ -z "${DEFAULT_REPOS_ROOT:-}" ] && readonly DEFAULT_REPOS_ROOT="/workspace/repos/"

# Global flags
DEBUG="${DEBUG:-false}"
SUMMARY_ONLY="${SUMMARY_ONLY:-false}"
VERBOSE="${VERBOSE:-false}"
QUIET="${QUIET:-false}"

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
# Print info message to stderr (suppressed by --quiet)
# Arguments:
#   $@ - Message to print
# Outputs:
#   Writes message to stderr if QUIET is not enabled
#######################################
log_info() {
    if [ "$QUIET" != "true" ]; then
        echo "[INFO] $*" >&2
    fi
}

#######################################
# Validate required dependencies are available
#
# Checks for jq (required) and realpath (required).
# Provides clear error messages with installation instructions.
#
# Outputs:
#   Error messages to stderr if dependencies missing
#
# Returns:
#   0 - All required dependencies available
#   1 - Required dependency missing
#######################################
check_dependencies() {
    local missing=0

    # Check jq (required for JSON parsing)
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: Required dependency not found: jq" >&2
        echo "Error: Install with: sudo apt-get install jq (Ubuntu/Debian) or brew install jq (macOS)" >&2
        missing=1
    fi

    # Check realpath (required for path canonicalization)
    if ! command -v realpath >/dev/null 2>&1; then
        echo "Error: Required dependency not found: realpath" >&2
        echo "Error: Install with: sudo apt-get install coreutils (Ubuntu/Debian) or brew install coreutils (macOS)" >&2
        missing=1
    fi

    if [ "$missing" -eq 1 ]; then
        echo "Error: Exiting due to missing required dependencies" >&2
        return 1
    fi

    return 0
}

#######################################
# Strip code blocks from file content
# Removes fenced code blocks (``` ... ```) to avoid parsing
# checkboxes that appear in code examples
# Arguments:
#   None - reads from stdin
# Outputs:
#   Content with code blocks removed to stdout
#######################################
strip_code_blocks() {
    # Use awk to remove content between ``` markers
    # State machine: in_block toggles on/off when we see ```
    awk '
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
# Scan a repository's SDD spec directory and aggregate all tickets
# Arguments:
#   $1 - Path to SDD spec directory (under specs root)
#   $2 - Path to code repository (under repos root), or empty if not found
# Outputs:
#   JSON object with repo status and ticket summaries to stdout
# Returns:
#   0 on success
#   1 if directory does not exist
#######################################
scan_repo() {
    local sdd_root="$1"
    local repo_path="${2:-}"

    # Validate directory exists
    if [ ! -d "$sdd_root" ]; then
        debug_log "SDD root directory not found: $sdd_root"
        printf '{\n'
        printf '  "name": "",\n'
        printf '  "sdd_root": "%s",\n' "$(json_escape "$sdd_root")"
        printf '  "repo_path": null,\n'
        printf '  "repo_status": "repo_not_found",\n'
        printf '  "tickets": [],\n'
        printf '  "summary": {"total_tickets": 0, "total_tasks": 0, "pending": 0, "completed": 0, "tested": 0, "verified": 0},\n'
        printf '  "error": "Directory not found"\n'
        printf '}'
        return 1
    fi

    # Extract repo name from the SDD directory itself (basename of specs dir)
    local repo_name
    repo_name=$(basename "$sdd_root")
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
    if [ -n "$repo_path" ] && [ -d "$repo_path" ]; then
        printf '  "repo_path": "%s",\n' "$(json_escape "$repo_path")"
    else
        printf '  "repo_path": null,\n'
        printf '  "repo_status": "repo_not_found",\n'
    fi
    printf '  "tickets": ['
    if [ -n "$tickets_json" ]; then
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
show_usage() {
    cat << EOF
Master Status Board v${VERSION} - Multi-repository SDD status aggregator

Usage:
  bash master-status-board.sh [options]

Examples:
  # Full output with all repo details (using defaults)
  ./master-status-board.sh

  # Custom specs and repos roots
  ./master-status-board.sh --specs-root /workspace/_SPECS/ --repos-root /workspace/repos/

  # Summary only (no per-repo details)
  ./master-status-board.sh --summary-only

  # Verbose timing output
  ./master-status-board.sh --verbose

  # Combined options
  ./master-status-board.sh -sv

  # Use environment variables
  SPECS_ROOT=/custom/_SPECS/ REPOS_ROOT=/custom/repos/ ./master-status-board.sh

Options:
  -h, --help          Show this help message and exit
  -q, --quiet         Suppress progress messages (to stderr)
  -s, --summary-only  Output only summary section (no per-repo details)
  -v, --verbose       Include timing output for each repo scan (to stderr)
  --specs-root PATH   Root directory containing SDD spec directories
                       Priority: --specs-root > SPECS_ROOT env var > default
                       Default: /workspace/_SPECS/
  --repos-root PATH   Root directory containing code repositories
                       Priority: --repos-root > REPOS_ROOT env var > default
                       Default: /workspace/repos/
  --json              Output JSON format (default, explicit specification)
  --debug             Enable debug output to stderr

Environment Variables:
  SPECS_ROOT        Root directory containing SDD spec directories
  REPOS_ROOT        Root directory containing code repositories
  WORKSPACE_ROOT    Deprecated: maps to REPOS_ROOT with warning
  DEBUG             Set to "true" to enable debug output

Timing Output (with --verbose):
  [0.12s] Scanned repo-a (3 tickets, 15 tasks)
  [0.25s] Scanned repo-b (2 tickets, 8 tasks)
  [0.38s] Total: 5 tickets, 23 tasks in 0.38s

Expected Directory Structure:
  specs-root/
      <repo-name>/
          tickets/
              <TICKET-ID>_<slug>/
                  tasks/
                      <TASK-ID>_<slug>.md
  repos-root/
      <repo-name>/
          <git-dir>/
              .git/

  Warnings are logged (non-blocking) if:
  - specs-root is empty (no subdirectories found)
  - specs-root and repos-root point to the same directory

Exit Codes:
  0 - Success (including empty specs root)
  1 - Specs directory does not exist
  2 - Invalid arguments
EOF
}

# Alias for backwards compatibility
show_help() {
    show_usage
}

#######################################
# Resolve path to absolute, following symlinks if safe
# Arguments:
#   $1 - Path to resolve
#   $2 - Specs root for symlink validation
# Outputs:
#   Absolute path, or empty string if symlink points outside specs root
#######################################
resolve_path() {
    local path="$1"
    local specs_root="$2"
    local resolved

    # Check if it's a symlink
    if [ -L "$path" ]; then
        # Resolve the symlink target
        resolved=$(readlink -f "$path" 2>/dev/null) || return 1

        # Validate symlink remains within specs root
        case "$resolved" in
            "$specs_root"*) ;;
            *)
                debug_log "Symlink $path points outside specs root: $resolved"
                return 1
                ;;
        esac
        echo "$resolved"
    else
        # Not a symlink, just canonicalize
        readlink -f "$path" 2>/dev/null || return 1
    fi
}

#######################################
# Discover all SDD spec directories under specs root
# Arguments:
#   $1 - Specs root directory
#   $2 - Repos root directory
# Outputs:
#   JSON array of discovered repos to stdout
#   Warnings to stderr for permission errors
#######################################
discover_sdd_directories() {
    local specs_root="$1"
    local repos_root="$2"
    local first=true

    debug_log "Discovering SDD spec directories in: $specs_root"

    # Output JSON array of repos
    echo "  \"repos\": ["

    # Iterate direct children of specs root
    for sdd_path in "$specs_root"*/; do
        [ -d "$sdd_path" ] || continue

        # Resolve and validate the path
        local resolved_path
        resolved_path=$(resolve_path "$sdd_path" "$specs_root") || {
            debug_log "Skipping invalid path: $sdd_path"
            continue
        }

        # Extract repo name from specs directory basename
        local repo_name
        repo_name=$(basename "$resolved_path")
        local repo_path="${repos_root}${repo_name}/"

        debug_log "Found SDD spec dir: $repo_name"

        # Output JSON object
        if [ "$first" = "true" ]; then
            first=false
        else
            # Print comma before next object (on same line as previous closing brace)
            printf ",\n"
        fi

        printf '    {\n'
        printf '      "name": "%s",\n' "$(json_escape "$repo_name")"
        printf '      "sdd_path": "%s",\n' "$(json_escape "$resolved_path")"
        if [ -d "$repo_path" ]; then
            printf '      "repo_path": "%s"\n' "$(json_escape "$repo_path")"
        else
            printf '      "repo_path": null,\n'
            printf '      "repo_status": "repo_not_found"\n'
        fi
        printf '    }'
    done
    # Add newline after last object
    echo ""

    echo "  ]"
}

#######################################
# Format elapsed time in seconds with 2 decimal places
# Arguments:
#   $1 - Start time in nanoseconds
#   $2 - End time in nanoseconds
# Outputs:
#   Elapsed time formatted as X.XX
#######################################
format_elapsed_time() {
    local start_ns="$1"
    local end_ns="$2"
    local elapsed_ns=$((end_ns - start_ns))
    local elapsed_s=$((elapsed_ns / 1000000000))
    local elapsed_ms=$(((elapsed_ns % 1000000000) / 10000000))
    printf "%d.%02d" "$elapsed_s" "$elapsed_ms"
}

#######################################
# Main entry point
# Arguments:
#   $@ - Command line arguments
#######################################
main() {
    # Validate required dependencies before proceeding
    check_dependencies || exit 1

    local specs_root=""
    local repos_root=""
    local arg_specs_root=""
    local arg_repos_root=""

    # Parse arguments using getopts-style processing
    while [ $# -gt 0 ]; do
        case "$1" in
            --help|-h)
                show_usage
                exit 0
                ;;
            --quiet|-q)
                QUIET="true"
                shift
                ;;
            --summary-only|-s)
                SUMMARY_ONLY="true"
                shift
                ;;
            --verbose|-v)
                VERBOSE="true"
                shift
                ;;
            --specs-root)
                if [ $# -lt 2 ]; then
                    echo "Error: --specs-root requires a PATH argument" >&2
                    exit 2
                fi
                arg_specs_root="$2"
                if [ -z "$arg_specs_root" ]; then
                    echo "Error: --specs-root cannot be empty" >&2
                    exit 1
                fi
                shift 2
                ;;
            --repos-root)
                if [ $# -lt 2 ]; then
                    echo "Error: --repos-root requires a PATH argument" >&2
                    exit 2
                fi
                arg_repos_root="$2"
                if [ -z "$arg_repos_root" ]; then
                    echo "Error: --repos-root cannot be empty" >&2
                    exit 1
                fi
                shift 2
                ;;
            --json)
                # JSON is the default output format, this is a no-op
                shift
                ;;
            --debug)
                DEBUG="true"
                shift
                ;;
            -*)
                # Check for combined short options like -sv
                if echo "$1" | grep -qE '^-[a-zA-Z]+$'; then
                    local opts="${1#-}"
                    local i=0
                    local unknown_opt=""
                    while [ $i -lt ${#opts} ]; do
                        local opt="${opts:$i:1}"
                        case "$opt" in
                            q) QUIET="true" ;;
                            s) SUMMARY_ONLY="true" ;;
                            v) VERBOSE="true" ;;
                            h) show_usage; exit 0 ;;
                            *)
                                unknown_opt="$opt"
                                break
                                ;;
                        esac
                        i=$((i + 1))
                    done
                    if [ -n "$unknown_opt" ]; then
                        echo "Error: Unknown option: -$unknown_opt" >&2
                        echo "Use --help for usage information" >&2
                        exit 2
                    fi
                    shift
                else
                    echo "Error: Unknown option: $1" >&2
                    echo "Use --help for usage information" >&2
                    exit 2
                fi
                ;;
            *)
                echo "Error: Unexpected argument: $1" >&2
                echo "Use --help for usage information" >&2
                exit 2
                ;;
        esac
    done

    # Deprecation handling: WORKSPACE_ROOT maps to REPOS_ROOT with warning
    if [ -n "${WORKSPACE_ROOT:-}" ] && [ -z "${REPOS_ROOT:-}" ] && [ -z "$arg_repos_root" ]; then
        echo "Warning: WORKSPACE_ROOT is deprecated; use REPOS_ROOT instead" >&2
        REPOS_ROOT="$WORKSPACE_ROOT"
    fi

    # Determine specs root (priority: --specs-root > SPECS_ROOT env var > default)
    if [ -n "$arg_specs_root" ]; then
        specs_root="$arg_specs_root"
    elif [ -n "${SPECS_ROOT:-}" ]; then
        specs_root="$SPECS_ROOT"
    else
        specs_root="$DEFAULT_SPECS_ROOT"
    fi

    # Determine repos root (priority: --repos-root > REPOS_ROOT env var > default)
    if [ -n "$arg_repos_root" ]; then
        repos_root="$arg_repos_root"
    elif [ -n "${REPOS_ROOT:-}" ]; then
        repos_root="$REPOS_ROOT"
    else
        repos_root="$DEFAULT_REPOS_ROOT"
    fi

    debug_log "Specs root: $specs_root"
    debug_log "Repos root: $repos_root"

    # Expand specs root to absolute path
    if [ "${specs_root#/}" = "$specs_root" ]; then
        specs_root="$(cd "$specs_root" 2>/dev/null && pwd)" || {
            echo "Error: Cannot resolve specs root path: $specs_root" >&2
            exit 1
        }
    fi

    # Expand repos root to absolute path
    if [ "${repos_root#/}" = "$repos_root" ]; then
        repos_root="$(cd "$repos_root" 2>/dev/null && pwd)" || {
            echo "Error: Cannot resolve repos root path: $repos_root" >&2
            exit 1
        }
    fi

    # Ensure trailing slash for consistent path handling
    specs_root="${specs_root%/}/"
    repos_root="${repos_root%/}/"

    # Validate specs directory exists
    if [ ! -d "$specs_root" ]; then
        echo "Error: Specs directory does not exist: $specs_root" >&2
        exit 1
    fi

    debug_log "Resolved specs root: $specs_root"
    debug_log "Resolved repos root: $repos_root"
    debug_log "SUMMARY_ONLY: $SUMMARY_ONLY"
    debug_log "VERBOSE: $VERBOSE"

    # ==========================================================================
    # Root Structure Validation (non-blocking warnings)
    # Warns about common configuration errors after path canonicalization.
    # These are advisory only - execution continues regardless.
    # ==========================================================================

    # Canonicalize paths for reliable comparison
    local canonical_specs_root canonical_repos_root
    canonical_specs_root="$(realpath "$specs_root" 2>/dev/null)" || canonical_specs_root="$specs_root"
    canonical_repos_root="$(realpath "$repos_root" 2>/dev/null)" || canonical_repos_root="$repos_root"

    # Check 1: Empty specs-root (no subdirectories)
    if [ -z "$(ls -A "$canonical_specs_root" 2>/dev/null)" ]; then
        echo "Warning: specs-root is empty (no subdirectories): $specs_root" >&2
        echo "Warning: Expected structure: specs-root/<repo-name>/tickets/" >&2
    fi

    # Check 2: Identical specs-root and repos-root paths
    if [ "$canonical_specs_root" = "$canonical_repos_root" ]; then
        echo "Warning: specs-root and repos-root are identical: $canonical_specs_root" >&2
        echo "Warning: This may cause unexpected behavior. Typically they should be separate directories." >&2
    fi

    # Discover all SDD spec directories
    debug_log "Discovering SDD spec directories in: $specs_root"

    # Record total start time for verbose mode
    local total_start_ns
    if [ "$VERBOSE" = "true" ]; then
        total_start_ns=$(date +%s%N)
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

    # Count total specs directories before discovery loop (for progress indication)
    local discovery_total
    discovery_total=$(find "$specs_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
    discovery_total=$(echo "$discovery_total" | tr -d ' ')
    local discovery_current=0

    # Iterate direct children of specs root
    for sdd_path in "$specs_root"*/; do
        [ -d "$sdd_path" ] || continue

        # Resolve and validate the path
        local resolved_path
        resolved_path=$(resolve_path "$sdd_path" "$specs_root") || {
            debug_log "Skipping invalid path: $sdd_path"
            continue
        }

        # Increment discovery counter and log progress every 10 repos
        discovery_current=$((discovery_current + 1))
        if [ "$discovery_total" -ge 10 ] && [ $((discovery_current % 10)) -eq 0 ]; then
            log_info "Discovering repos... ($discovery_current/$discovery_total)"
        fi

        debug_log "Found SDD spec dir: $resolved_path"

        # Derive repo name and repo path
        local repo_name
        repo_name=$(basename "$resolved_path")
        local repo_path="${repos_root}${repo_name}/"

        # Record start time for this repo if verbose
        local repo_start_ns
        if [ "$VERBOSE" = "true" ]; then
            repo_start_ns=$(date +%s%N)
        fi

        # Scan the repo using scan_repo function
        # Pass repo_path only if the directory exists
        local repo_json
        if [ -d "$repo_path" ]; then
            repo_json=$(scan_repo "$resolved_path" "$repo_path")
        else
            repo_json=$(scan_repo "$resolved_path" "")
        fi

        # Add comma separator between repos
        if [ "$first_repo" = "true" ]; then
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

        # Output timing for this repo if verbose
        if [ "$VERBOSE" = "true" ]; then
            local repo_end_ns
            repo_end_ns=$(date +%s%N)
            local repo_elapsed
            repo_elapsed=$(format_elapsed_time "$repo_start_ns" "$repo_end_ns")
            echo "[${repo_elapsed}s] Scanned $repo_name ($repo_tickets tickets, $repo_tasks tasks)" >&2
        fi

        # Aggregate at workspace level
        total_repos=$((total_repos + 1))
        total_tickets=$((total_tickets + repo_tickets))
        total_tasks=$((total_tasks + repo_tasks))
        total_pending=$((total_pending + repo_pending))
        total_completed=$((total_completed + repo_completed))
        total_tested=$((total_tested + repo_tested))
        total_verified=$((total_verified + repo_verified))
    done

    # Final discovery progress (only if >= 10 repos)
    if [ "$discovery_total" -ge 10 ]; then
        log_info "Discovering repos... ($discovery_total/$discovery_total)"
    fi

    # Output total timing if verbose
    if [ "$VERBOSE" = "true" ]; then
        local total_end_ns
        total_end_ns=$(date +%s%N)
        local total_elapsed
        total_elapsed=$(format_elapsed_time "$total_start_ns" "$total_end_ns")
        echo "[${total_elapsed}s] Total: $total_tickets tickets, $total_tasks tasks in ${total_elapsed}s" >&2
    fi

    # Build the full output JSON (without recommended_action first)
    local full_json=""
    full_json+="{"$'\n'
    full_json+="  \"version\": \"$VERSION\","$'\n'
    full_json+="  \"timestamp\": \"$(date -Iseconds)\","$'\n'
    full_json+="  \"specs_root\": \"$(json_escape "$specs_root")\","$'\n'
    full_json+="  \"repos_root\": \"$(json_escape "$repos_root")\","$'\n'

    # Include repos array only if not summary-only mode
    if [ "$SUMMARY_ONLY" != "true" ]; then
        full_json+="  \"repos\": ["$'\n'
        if [ -n "$repos_json" ]; then
            full_json+="$repos_json"$'\n'
        fi
        full_json+="  ],"$'\n'
    fi

    full_json+="  \"summary\": {"$'\n'
    full_json+="    \"total_repos\": $total_repos,"$'\n'
    full_json+="    \"total_tickets\": $total_tickets,"$'\n'
    full_json+="    \"total_tasks\": $total_tasks,"$'\n'
    full_json+="    \"pending\": $total_pending,"$'\n'
    full_json+="    \"completed\": $total_completed,"$'\n'
    full_json+="    \"tested\": $total_tested,"$'\n'
    full_json+="    \"verified\": $total_verified"$'\n'
    full_json+="  },"$'\n'

    # Compute recommended action (only if we have full repo details)
    if [ "$SUMMARY_ONLY" != "true" ]; then
        # Build temporary JSON with repos for action computation
        local temp_json="{"
        temp_json+="\"repos\": ["
        if [ -n "$repos_json" ]; then
            temp_json+="$repos_json"
        fi
        temp_json+="]}"

        local recommended_action
        recommended_action=$(compute_recommended_action "$temp_json" 2>/dev/null)

        # Add recommended_action to output
        full_json+="  \"recommended_action\": $recommended_action"$'\n'
    else
        # In summary-only mode, we cannot compute recommended action (no repo details)
        full_json+="  \"recommended_action\": {\"action\": \"none\", \"reason\": \"Summary-only mode - full scan required for recommendation\"}"$'\n'
    fi

    full_json+="}"

    # Output the final JSON
    echo "$full_json"
}

#######################################
# Compute recommended action from scan results
# Analyzes aggregated status to find the next actionable task
# considering autogate configuration and priority ordering
#
# Arguments:
#   $1 - Full scan output JSON (from main function)
#
# Outputs:
#   JSON object with recommended action to stdout
#
# Algorithm:
#   1. Filter tickets where ready=true AND agent_ready=true
#   2. Sort filtered tickets by priority (1=highest, missing=last), then ticket_id
#   3. Within each ticket, find first actionable task: pending > completed > tested
#   4. Return first match or "none" if no work
#######################################
compute_recommended_action() {
    local scan_output="$1"

    debug_log "compute_recommended_action: Analyzing scan results"

    # Validate input
    if [[ -z "$scan_output" ]]; then
        debug_log "  Empty scan output, returning none"
        printf '{\n'
        printf '  "action": "none",\n'
        printf '  "reason": "No scan data provided"\n'
        printf '}'
        return 0
    fi

    # Check if jq is available
    if ! command -v jq &>/dev/null; then
        echo "Error: jq is required for compute_recommended_action" >&2
        printf '{\n'
        printf '  "action": "none",\n'
        printf '  "reason": "jq not available"\n'
        printf '}'
        return 1
    fi

    # Use jq to find the recommended action
    # This complex jq query:
    # 1. Flattens repos -> tickets -> tasks structure
    # 2. Filters to agent-ready tickets (ready=true AND agent_ready=true)
    # 3. Sorts by priority (null treated as infinity) then ticket_id
    # 4. For each ticket, finds the first actionable task by state priority
    # 5. Returns the first overall match
    local recommendation
    local jq_exit_code=0
    recommendation=$(echo "$scan_output" | jq -c '
        # Helper function to determine task state priority
        # Returns: 1 for pending, 2 for completed (needs testing), 3 for tested (needs verification), 4 for verified (skip)
        def task_state_priority:
            if .verified == true then 4
            elif .tests_pass == true then 3
            elif .task_completed == true then 2
            else 1
            end;

        # Helper function to get task state description
        def task_state_description:
            if .verified == true then "verified"
            elif .tests_pass == true then "tested"
            elif .task_completed == true then "completed"
            else "pending"
            end;

        # Flatten the structure to get all tickets with their repo context
        [.repos[] | . as $repo | .tickets[] | {
            repo_name: $repo.name,
            sdd_root: $repo.sdd_root,
            ticket_id: .ticket_id,
            ticket_path: .path,
            ready: .autogate.ready,
            agent_ready: .autogate.agent_ready,
            priority: .autogate.priority,
            tasks: .tasks
        }]

        # Filter to only agent-ready tickets
        | map(select(.ready == true and .agent_ready == true))

        # Sort by priority (null last) then ticket_id
        | sort_by([
            (if .priority == null then 999999 else .priority end),
            .ticket_id
        ])

        # For each ticket, find the first actionable task
        | . as $tickets
        | if ($tickets | length) == 0 then
            {
                action: "none",
                reason: "No agent-ready work remaining"
            }
          else
            # Process tickets in priority order
            reduce $tickets[] as $ticket (
                {found: false, result: null};
                if .found then .
                else
                    # Find actionable tasks in this ticket (sorted by state priority, then task_id)
                    ($ticket.tasks
                        | map(select(task_state_priority < 4))  # Skip verified tasks
                        | sort_by([task_state_priority, .task_id])
                        | first
                    ) as $best_task
                    |
                    if $best_task != null then
                        {
                            found: true,
                            result: {
                                action: "do-task",
                                repo: $ticket.repo_name,
                                ticket: $ticket.ticket_id,
                                task: $best_task.task_id,
                                task_file: $best_task.file,
                                sdd_root: $ticket.sdd_root,
                                reason: (
                                    if ($best_task | task_state_priority) == 1 then
                                        "Next pending task in highest priority ticket"
                                    elif ($best_task | task_state_priority) == 2 then
                                        "Next completed task needs testing in ticket " + $ticket.ticket_id
                                    else
                                        "Next tested task needs verification in ticket " + $ticket.ticket_id
                                    end
                                )
                            }
                        }
                    else
                        .
                    end
                end
            )
            | if .found then .result
              else
                {
                    action: "none",
                    reason: "All agent-ready work completed"
                }
              end
          end
    ' 2>/dev/null) || jq_exit_code=$?

    # Check if jq succeeded
    if [[ $jq_exit_code -ne 0 ]] || [[ -z "$recommendation" ]]; then
        debug_log "  jq parsing failed, returning none"
        printf '{\n'
        printf '  "action": "none",\n'
        printf '  "reason": "Failed to parse scan output"\n'
        printf '}'
        return 0
    fi

    debug_log "  Recommendation: $recommendation"

    # Pretty-print the recommendation
    echo "$recommendation" | jq '.'
}

# Run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
