#!/usr/bin/env bash
#
# Scaffold Ticket Structure
# Creates the folder structure for a new ticket
#
# Usage:
#   bash scaffold-ticket.sh [--manifest <path>] <TICKET_ID> <name>
#
# Arguments:
#   --manifest <path>  Optional path to triage manifest JSON
#   TICKET_ID          Ticket identifier (2-12 chars, uppercase with optional dashes for Jira IDs like UIT-9819)
#   name               Ticket name (kebab-case)
#
# Output:
#   JSON with created structure

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../templates/ticket"
SDD_ROOT_DIR="${SDD_ROOT_DIR:-/app/.sdd}"

# Cleanup state: tracks whether this invocation created the ticket directory
CREATED_TICKET_DIR=false
CLEANUP_TICKET_PATH=""

error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }

# Cleanup partial ticket directory on failure.
# Only removes directory if it was created by THIS invocation (not pre-existing).
# Checks exit code so successful exits (via EXIT trap) do not trigger cleanup.
cleanup_on_error() {
    local exit_code=$?
    if [ "$CREATED_TICKET_DIR" = "true" ] && [ $exit_code -ne 0 ]; then
        error "Cleanup: Removing partial ticket directory $CLEANUP_TICKET_PATH due to failure"
        rm -rf "$CLEANUP_TICKET_PATH"
    fi
}

usage() {
    cat << EOF
Usage: $(basename "$0") [--manifest <path>] <TICKET_ID> <name>

Arguments:
  --manifest <path>  Optional triage manifest JSON (output of triage-documents.sh)
  TICKET_ID          Ticket identifier (e.g., APIV2, DKRHUB, or Jira ID like UIT-9819)
  name               Ticket name (kebab-case, e.g., "api-redesign")

Examples:
  $(basename "$0") APIV2 api-version-2
  $(basename "$0") --manifest /tmp/manifest.json DKRHUB docker-hub-publishing
  $(basename "$0") UIT-9819 user-profile-update    # Jira-based ticket ID

Output:
  JSON object with created structure
EOF
    exit 1
}

validate_ticket_id() {
    local ticket_id="$1"
    # Allow formats like: APIV2, DKRHUB (4-8 uppercase) OR UIT-9819, PROJ-123 (Jira-style)
    # Pattern: Start with uppercase letter, then alphanumeric, optionally followed by dash + alphanumeric segments
    if [[ ! "$ticket_id" =~ ^[A-Z][A-Z0-9]*(-[A-Z0-9]+)*$ ]]; then
        error "Invalid TICKET_ID format."
        error "Valid formats: APIV2, DKRHUB (uppercase) or UIT-9819, PROJ-123 (Jira-style)"
        exit 1
    fi
    # Check reasonable length (2-12 chars)
    if [[ ${#ticket_id} -lt 2 ]] || [[ ${#ticket_id} -gt 12 ]]; then
        error "TICKET_ID must be 2-12 characters. Got: ${#ticket_id}"
        exit 1
    fi
}

validate_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]] && [[ ! "$name" =~ ^[a-z]$ ]]; then
        error "Invalid name format. Use lowercase letters, numbers, and hyphens."
        error "Example: api-redesign, docker-hub-publishing"
        exit 1
    fi
}

check_ticket_id_unique() {
    local ticket_id="$1"
    # Pre-check: detect reuse of ticket ID with any name (non-atomic, defense-in-depth)
    # The atomic mkdir below is the authoritative duplicate guard
    if ls -d "$SDD_ROOT_DIR/tickets/${ticket_id}_"* 2>/dev/null | grep -q .; then
        error "TICKET_ID '$ticket_id' already exists in active tickets"
        exit 1
    fi
    # Check archived tickets (advisory warning only)
    if ls -d "$SDD_ROOT_DIR/archive/tickets/${ticket_id}_"* 2>/dev/null | grep -q .; then
        warn "TICKET_ID '$ticket_id' exists in archived tickets - proceeding with caution"
    fi
}

# Generate a planning document from a standalone template file.
# Reads the template, substitutes {NAME} with the ticket name, writes to output.
#
# Arguments:
#   $1 - filename (e.g., "analysis.md")
#   $2 - output directory (e.g., "/path/to/ticket/planning")
#   $3 - ticket_name (human-readable, spaces instead of hyphens)
generate_doc() {
    local filename="$1"
    local output_dir="$2"
    local ticket_name="$3"
    local template_path="$TEMPLATE_DIR/$filename"
    local output_path="$output_dir/$filename"

    # Validate filename against path traversal
    if printf '%s' "$filename" | grep -qE '\.\./' ; then
        error "Invalid template filename: $filename (path traversal attempt)"
        exit 1
    fi

    if [ ! -f "$template_path" ]; then
        error "Template file missing: $template_path"
        exit 1
    fi

    sed "s/{NAME}/${ticket_name}/g" "$template_path" > "$output_path"
}

# Generate README.md with links only to the documents that were actually created.
#
# Arguments:
#   $1 - ticket_path (e.g., "/path/to/ticket")
#   $2 - ticket_id
#   $3 - ticket_name (human-readable, spaces instead of hyphens)
#   $4 - space-separated list of created filenames (e.g., "analysis.md architecture.md plan.md")
generate_readme() {
    local ticket_path="$1"
    local ticket_id="$2"
    local ticket_name="$3"
    local created_files="$4"
    local readme_path="$ticket_path/README.md"

    # Build the planning documents link list
    local planning_links=""
    for filename in $created_files; do
        # Look up the title from the document registry if available
        local title=""
        if [ -f "$TEMPLATE_DIR/../document-registry.json" ]; then
            title=$(jq -r --arg fn "$filename" \
                '.documents[] | select(.filename == $fn) | .title // empty' \
                "$TEMPLATE_DIR/../document-registry.json" 2>/dev/null || true)
        fi
        # Fallback: derive title from filename
        if [ -z "$title" ]; then
            # Remove .md extension, replace hyphens with spaces, capitalize first letter
            title=$(printf '%s' "$filename" | sed 's/\.md$//' | sed 's/-/ /g' | sed 's/\b\(.\)/\u\1/g')
        fi
        planning_links="${planning_links}- [${filename}](planning/${filename}) - ${title}
"
    done

    cat > "$readme_path" << EOF
# Ticket: ${ticket_name}

**Ticket ID:** $ticket_id
**Status:** Planning
**Created:** $(date +%Y-%m-%d)

## Summary

[Brief description of the ticket]

## Problem Statement

[What problem does this ticket solve?]

## Proposed Solution

[High-level approach to solving the problem]

## Relevant Agents

- ticket-planner (planning phase)
- task-creator (ticket generation)
- [implementation agents]
- verify-task (verification)
- commit-task (commit)

## Deliverables

Work products created during ticket execution (if applicable):

See [deliverables/](deliverables/) for analysis reports, findings documents, and verification artifacts.

## Planning Documents

${planning_links}
## Tasks

See [tasks/](tasks/) for all ticket tasks.
EOF
}

main() {
    # --- Parse optional flags ---
    local manifest_path=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --manifest)
                if [ $# -lt 2 ]; then
                    error "--manifest requires a path argument"
                    exit 1
                fi
                manifest_path="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            -*)
                error "Unknown option: $1"
                usage
                ;;
            *)
                break
                ;;
        esac
    done

    if [[ $# -lt 2 ]]; then
        usage
    fi

    local ticket_id="$1"
    local name="$2"
    local folder_name="${ticket_id}_${name}"
    local ticket_path="$SDD_ROOT_DIR/tickets/$folder_name"
    local ticket_name="${name//-/ }"

    validate_ticket_id "$ticket_id"
    validate_name "$name"
    check_ticket_id_unique "$ticket_id"

    # Register cleanup trap (before any directory creation)
    CLEANUP_TICKET_PATH="$ticket_path"
    trap 'cleanup_on_error' ERR EXIT

    # Validate manifest if provided
    if [ -n "$manifest_path" ]; then
        if [ ! -f "$manifest_path" ]; then
            error "Manifest not found: $manifest_path"
            exit 1
        fi
        if ! jq empty "$manifest_path" 2>/dev/null; then
            error "Invalid JSON in manifest: $manifest_path"
            exit 1
        fi
    fi

    info "Creating ticket: $folder_name"

    # Ensure parent directory exists
    mkdir -p "$SDD_ROOT_DIR/tickets"

    # Atomic create-or-fail (no TOCTOU race window)
    # mkdir without -p fails if directory already exists, combining check + create atomically
    if ! mkdir "$ticket_path" 2>/dev/null; then
        error "Ticket already exists: $ticket_path"
        exit 1
    fi
    CREATED_TICKET_DIR=true

    # Create directory structure
    # IMPORTANT: If structure changes, update plugins/maproom/skills/sdd-spec-search/SKILL.md
    mkdir -p "$ticket_path"/{planning,tasks,deliverables}

    # --- Determine which documents to generate ---
    local docs_to_generate=""

    if [ -n "$manifest_path" ]; then
        # Manifest-driven: generate only documents with action="generate"
        docs_to_generate=$(jq -r '.documents[] | select(.action=="generate") | .filename' "$manifest_path")

        # Copy manifest for downstream reference
        cp "$manifest_path" "$ticket_path/planning/.triage-manifest.json"
        info "Triage manifest saved to planning/.triage-manifest.json"
    else
        # Legacy: generate original six documents
        docs_to_generate="analysis.md architecture.md plan.md prd.md quality-strategy.md security-review.md"
    fi

    # --- Generate planning documents ---
    local created_files=""
    local created_paths=""

    for doc in $docs_to_generate; do
        generate_doc "$doc" "$ticket_path/planning" "$ticket_name"
        created_files="${created_files}${created_files:+ }${doc}"
        created_paths="${created_paths}
    \"$ticket_path/planning/$doc\","
        info "Generated: planning/$doc"
    done

    # --- Generate README.md ---
    generate_readme "$ticket_path" "$ticket_id" "$ticket_name" "$created_files"

    # --- Build JSON created array ---
    local created_json=""
    created_json="\"$ticket_path/README.md\""
    for doc in $created_files; do
        created_json="${created_json},
    \"$ticket_path/planning/$doc\""
    done

    # Disable cleanup trap - execution succeeded, directory should be kept
    trap - ERR EXIT

    # Output JSON
    cat << EOF
{
  "success": true,
  "ticket": {
    "ticket_id": "$ticket_id",
    "name": "$name",
    "folder": "$folder_name",
    "path": "$ticket_path"
  },
  "created": [
    $created_json
  ],
  "directories": [
    "$ticket_path/planning",
    "$ticket_path/tasks",
    "$ticket_path/deliverables"
  ],
  "next_steps": [
    "Delegate to ticket-planner agent to fill planning docs",
    "Run /sdd:review $ticket_id before creating tasks",
    "Run /sdd:create-tasks $ticket_id to create tasks"
  ]
}
EOF

    info "Ticket created at: $ticket_path"
}

main "$@"
