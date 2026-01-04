#!/usr/bin/env bash
#
# cleanup-worktree.sh - Remove git worktree with VS Code workspace cleanup
#
# Version: 1.0.0
#
# DESCRIPTION:
#   Orchestrates the cleanup of a git worktree, removing it from the VS Code
#   workspace file and deleting the worktree and optionally its branch. This is
#   the inverse operation of spawn-worktree.sh.
#
#   The script can run from either the macOS host OR from inside the devcontainer,
#   automatically detecting the execution environment and adjusting behavior.
#
# REQUIREMENTS:
#   - Git repository with worktree support
#   - CrewChief CLI (crewchief worktree) installed
#   - jq installed for workspace updates (optional if --skip-workspace)
#   - workspace-folder.sh script for VS Code workspace updates
#
# USAGE:
#   cleanup-worktree.sh <worktree-name> --repo <repository> [OPTIONS]
#
# REQUIRED ARGUMENTS:
#   worktree-name                Name of the worktree to remove
#   -r, --repo REPO             Repository name (must exist in /workspace/repos)
#
# OPTIONAL ARGUMENTS:
#   -w, --workspace FILE        VS Code workspace file path
#                               (default: from WORKSPACE_FILE or auto-detect)
#   -y, --yes                   Skip confirmation prompt
#   --keep-branch               Don't delete the git branch after worktree removal
#   --skip-workspace            Skip removing from VS Code workspace
#   --dry-run                   Show what would be done without making changes
#   -h, --help                  Show this help message and exit
#
# WORKSPACE FILE RESOLUTION (priority order):
#   1. CLI --workspace/-w flag (highest priority)
#   2. WORKSPACE_FILE environment variable
#   3. Auto-detect: /workspace/workspace.code-workspace
#   4. If none found: warn and continue (workspace removal is non-fatal)
#
# ENVIRONMENT VARIABLES:
#   WORKSPACE_FILE              Path to VS Code workspace file
#                               (overridden by -w flag)
#
#   Note: CLI flags take precedence over environment variables
#
# EXIT CODES:
#   0 - Success (worktree removed; workspace warnings are non-fatal)
#   1 - Docker or container issues (daemon not running, container not running)
#   2 - Missing prerequisites (jq not installed, crewchief not found)
#   3 - Invalid arguments (missing required args, invalid format, unknown flags)
#   4 - Worktree not found
#   5 - User cancelled
#
# EXAMPLES:
#
#   1. Basic Usage - Remove worktree and branch
#      $ cleanup-worktree.sh feature-auth --repo myproject
#
#      Output:
#        [INFO] Validating worktree 'feature-auth' exists...
#        [OK] Worktree found: /workspace/repos/myproject/feature-auth
#        [INFO] Fetching latest from origin main...
#        [OK] Git fetch complete
#        [INFO] Removing worktree from VS Code workspace...
#        [OK] Workspace updated
#        [INFO] Removing worktree and branch...
#        [OK] Worktree removed
#
#   2. Keep Branch - Remove worktree but preserve branch
#      $ cleanup-worktree.sh feature-auth --repo myproject --keep-branch
#
#      Output:
#        [INFO] Validating worktree 'feature-auth' exists...
#        [OK] Worktree found
#        ...
#        [INFO] Removing worktree (keeping branch)...
#        [OK] Worktree removed
#
#   3. Skip Confirmation - Automated cleanup
#      $ cleanup-worktree.sh feature-auth --repo myproject --yes
#
#      Use case: Non-interactive scripts or CI/CD pipelines
#
#   4. Dry Run - Preview planned actions
#      $ cleanup-worktree.sh feature-auth --repo myproject --dry-run
#
#      Output:
#        ==========================================
#          DRY RUN - No changes will be made
#        ==========================================
#
#        Would execute with resolved parameters:
#          Repository: myproject
#          Worktree name: feature-auth
#          Workspace file: /workspace/workspace.code-workspace
#          Keep branch: no
#
#        Commands that would run:
#          1. Validate worktree exists
#          2. Git fetch origin main (30s timeout)
#          3. Remove from workspace: workspace-folder.sh remove ...
#          4. Remove worktree: crewchief worktree clean feature-auth
#
#   5. Skip Workspace - Only remove worktree
#      $ cleanup-worktree.sh feature-auth --repo myproject --skip-workspace
#
#      Use case: When workspace file is managed externally
#
# TROUBLESHOOTING:
#
#   Error: "Worktree 'xyz' not found"
#   Solution: Verify worktree name and repo with:
#     crewchief worktree list
#
#   Error: "Cannot remove current worktree"
#   Solution: Switch to a different worktree first:
#     cd /workspace/repos/myproject/main
#
#   Warning: "Workspace update failed"
#   Solution: This is non-fatal. Manually remove folder from workspace if needed.
#     Or verify workspace file exists at expected location.
#
#   Error: "Git fetch timed out"
#   Solution: Check network connectivity. The fetch uses a 30-second timeout.
#     You can retry or proceed without fetch if acceptable.
#

set -euo pipefail

##############################################################################
# Utility Functions
##############################################################################

# Detect if running inside container vs on macOS host
# Returns: 0 (true) if in container, 1 (false) if on host
is_container() {
    # Primary check: not macOS
    [[ "$(uname)" != "Darwin" ]] && return 0

    # Secondary check: Docker environment file
    [[ -f "/.dockerenv" ]] && return 0

    return 1
}

##############################################################################
# Color Output Functions
##############################################################################

# Color output functions (all go to stderr to avoid polluting captured output)
info() {
    echo -e "\033[0;34m[INFO]\033[0m $*" >&2
}

success() {
    echo -e "\033[0;32m[OK]\033[0m $*" >&2
}

warn() {
    echo -e "\033[0;33m[WARN]\033[0m $*" >&2
}

error() {
    echo -e "\033[0;31m[ERROR]\033[0m $*" >&2
}

# Dry-run output function
dry_run_msg() {
    echo -e "\033[0;35m[DRY-RUN]\033[0m $*" >&2
}

# Locate this script's directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
DEFAULT_WORKSPACE="/workspace/workspace.code-workspace"

# Initialize variables from environment or defaults
WORKSPACE_FILE="${WORKSPACE_FILE:-}"

# Variables to be set by argument parsing
WORKTREE_NAME=""
REPO=""
SKIP_CONFIRMATION=false
KEEP_BRANCH=false
SKIP_WORKSPACE=false
DRY_RUN=false

# Global array to collect warnings
WARNINGS=()

# Ticket detection variables (populated during execution)
TICKET_PATH=""
TICKET_STATUS=""

##############################################################################
# Help Function
##############################################################################

show_help() {
    cat << 'EOF'
Usage: cleanup-worktree.sh <worktree-name> --repo <repository> [OPTIONS]

Remove a git worktree with optional VS Code workspace cleanup.

REQUIRED ARGUMENTS:
  worktree-name                Name of the worktree to remove
  -r, --repo REPO             Repository name (must exist in /workspace/repos)

OPTIONAL ARGUMENTS:
  -w, --workspace FILE        VS Code workspace file path
                              (default: from WORKSPACE_FILE or auto-detect)
  -y, --yes                   Skip confirmation prompt
  --keep-branch               Don't delete the git branch after worktree removal
  --skip-workspace            Skip removing from VS Code workspace
  --dry-run                   Show what would be done without making changes
  -h, --help                  Show this help message and exit

WORKSPACE FILE RESOLUTION (priority order):
  1. CLI --workspace/-w flag (highest priority)
  2. WORKSPACE_FILE environment variable
  3. Auto-detect: /workspace/workspace.code-workspace
  4. If none found: warn and continue (workspace removal is non-fatal)

ENVIRONMENT VARIABLES:
  WORKSPACE_FILE              Path to VS Code workspace file
                              (overridden by -w flag)

  Note: CLI flags take precedence over environment variables

EXIT CODES:
  0   Success (worktree removed, workspace updated)
  1   Docker or container issues
  2   Missing prerequisites (jq, crewchief CLI)
  3   Invalid arguments (missing required args, invalid format)
  4   Worktree not found
  5   User cancelled

EXAMPLES:
  # Basic usage - remove worktree and branch
  cleanup-worktree.sh feature-auth --repo myapp

  # Keep the branch after removing worktree
  cleanup-worktree.sh bugfix-123 --repo myapp --keep-branch

  # Skip confirmation prompt (for scripts)
  cleanup-worktree.sh experiment --repo myapp --yes

  # Dry run to preview actions
  cleanup-worktree.sh test-branch --repo myapp --dry-run

  # Skip workspace update
  cleanup-worktree.sh feature-new --repo myapp --skip-workspace

REQUIREMENTS:
  - Running inside devcontainer or with access to /workspace/repos
  - Git repositories in /workspace/repos directory
  - CrewChief CLI (crewchief worktree) installed
  - For workspace: jq installed and workspace file exists

NOTE:
  You cannot remove the worktree you are currently in. Switch to a different
  worktree first before running this script.

EOF
}

##############################################################################
# Workspace File Resolution
##############################################################################

# Auto-detect workspace file if not specified
# Returns the resolved workspace file path or empty string if not found
resolve_workspace_file() {
    # Priority 1: Already set via --workspace flag or WORKSPACE_FILE env
    if [[ -n "$WORKSPACE_FILE" ]]; then
        if [[ -f "$WORKSPACE_FILE" ]]; then
            echo "$WORKSPACE_FILE"
        else
            warn "Specified workspace file not found: $WORKSPACE_FILE"
            echo ""
        fi
        return
    fi

    # Priority 2: Auto-detect default location
    if [[ -f "$DEFAULT_WORKSPACE" ]]; then
        echo "$DEFAULT_WORKSPACE"
        return
    fi

    # Not found
    echo ""
}

##############################################################################
# Prerequisite Validation
##############################################################################

validate_prerequisites() {
    # Check for crewchief CLI
    if ! command -v crewchief &>/dev/null; then
        error "crewchief CLI is required but not installed"
        error "Install with: npm install -g @anthropic/crewchief"
        exit 2
    fi

    # Check for jq (only if workspace update not skipped)
    if [[ "$SKIP_WORKSPACE" != true ]]; then
        if ! command -v jq &>/dev/null; then
            warn "jq is not installed - workspace updates will be skipped"
            warn "Install with: brew install jq (macOS) or apt install jq (Linux)"
            SKIP_WORKSPACE=true
        fi
    fi

    # Check workspace-folder.sh exists (only if workspace update not skipped)
    if [[ "$SKIP_WORKSPACE" != true ]]; then
        if [[ ! -f "$SCRIPT_DIR/workspace-folder.sh" ]]; then
            warn "workspace-folder.sh not found at: $SCRIPT_DIR/workspace-folder.sh"
            warn "Workspace updates will be skipped"
            SKIP_WORKSPACE=true
        fi
    fi
}

##############################################################################
# Worktree Validation
##############################################################################

# Check if worktree exists
# Returns: 0 if exists, 1 if not found
worktree_exists() {
    local name="$1"
    local repo="$2"

    # Get list of worktrees from crewchief
    local worktree_list
    local repo_path="/workspace/repos/$repo/$repo"

    # Try nested directory first
    if [[ ! -d "$repo_path" ]]; then
        repo_path="/workspace/repos/$repo"
    fi

    if [[ ! -d "$repo_path" ]]; then
        return 1
    fi

    # Run crewchief worktree list from repo directory
    worktree_list=$(cd "$repo_path" && crewchief worktree list 2>/dev/null) || return 1

    # Check if the worktree name appears in the list
    # Format: [info] /workspace/repos/project/worktree-name [branch-name]
    if echo "$worktree_list" | grep -q "/$name \[" || echo "$worktree_list" | grep -q "/$name$"; then
        return 0
    fi

    return 1
}

# Get the full path to a worktree
get_worktree_path() {
    local name="$1"
    local repo="$2"

    local repo_path="/workspace/repos/$repo/$repo"
    if [[ ! -d "$repo_path" ]]; then
        repo_path="/workspace/repos/$repo"
    fi

    local target_path="$repo_path/../$name"
    # Try GNU realpath -m first, then fall back for macOS compatibility
    if command -v realpath &>/dev/null && realpath -m . &>/dev/null 2>&1; then
        realpath -m "$target_path" 2>/dev/null
    else
        # Fallback for systems without realpath -m (e.g., macOS)
        (cd "$(dirname "$target_path")" 2>/dev/null && echo "$(pwd)/$(basename "$target_path")") || echo "/workspace/repos/$repo/$name"
    fi
}

##############################################################################
# Git Fetch
##############################################################################

# Portable timeout function for macOS compatibility
run_with_timeout() {
    local timeout_seconds="$1"
    shift
    if command -v timeout &>/dev/null; then
        timeout "${timeout_seconds}s" "$@"
    elif command -v gtimeout &>/dev/null; then
        # GNU timeout from Homebrew coreutils on macOS
        gtimeout "${timeout_seconds}s" "$@"
    else
        # Fallback: run without timeout
        "$@"
    fi
}

# Fetch from origin main with timeout
git_fetch_origin() {
    local repo="$1"
    local repo_path="/workspace/repos/$repo/$repo"

    if [[ ! -d "$repo_path" ]]; then
        repo_path="/workspace/repos/$repo"
    fi

    info "Fetching latest from origin main (30s timeout)..."

    # Use portable timeout wrapper
    if run_with_timeout 30 git -C "$repo_path" fetch origin main 2>/dev/null; then
        success "Git fetch complete"
        return 0
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            warn "Git fetch timed out after 30 seconds"
        else
            warn "Git fetch failed (exit code: $exit_code)"
        fi
        warn "Continuing without fetch - worktree may not be up to date"
        return 0  # Non-fatal, continue with cleanup
    fi
}

##############################################################################
# Workspace Removal
##############################################################################

remove_from_workspace() {
    local worktree_path="$1"
    local workspace_file="$2"

    if [[ "$SKIP_WORKSPACE" == true ]]; then
        info "Skipping workspace update (--skip-workspace flag)"
        return 0
    fi

    if [[ -z "$workspace_file" ]]; then
        warn "No workspace file found - skipping workspace update"
        WARNINGS+=("Workspace update skipped - no workspace file found")
        return 0
    fi

    info "Removing worktree from VS Code workspace..."

    # Build arguments for workspace-folder.sh
    local args=("remove" "$worktree_path" -w "$workspace_file")

    if "$SCRIPT_DIR/workspace-folder.sh" "${args[@]}" 2>/dev/null; then
        success "Workspace updated"
    else
        warn "Failed to update workspace (exit code $?)"
        warn "You may need to manually remove the folder from your workspace"
        WARNINGS+=("Workspace update failed - remove folder manually if needed")
    fi
}

##############################################################################
# Worktree Removal
##############################################################################

remove_worktree() {
    local name="$1"
    local repo="$2"
    local keep_branch="$3"

    local repo_path="/workspace/repos/$repo/$repo"
    if [[ ! -d "$repo_path" ]]; then
        repo_path="/workspace/repos/$repo"
    fi

    if [[ "$keep_branch" == true ]]; then
        info "Removing worktree (keeping branch)..."
    else
        info "Removing worktree and branch..."
    fi

    # Build crewchief command
    local cmd_args=("worktree" "clean" "$name")
    if [[ "$keep_branch" == true ]]; then
        cmd_args+=("--keep-branch")
    fi

    # Execute from repo directory
    if (cd "$repo_path" && crewchief "${cmd_args[@]}"); then
        success "Worktree removed"
        return 0
    else
        error "Failed to remove worktree"
        error "You may need to manually remove it with: git worktree remove $name"
        exit 4
    fi
}

##############################################################################
# Ticket Detection Functions
##############################################################################

# Find SDD ticket for a worktree name
# Arguments: worktree_name
# Returns: ticket directory path on stdout, or empty string if no match
# Exit codes: 0 = match found, 1 = no match, 3 = multiple matches at same priority
find_ticket_for_worktree() {
    local worktree_name="$1"

    # Check if SDD_ROOT_DIR is set
    if [[ -z "${SDD_ROOT_DIR+x}" ]]; then
        # Variable is completely unset
        info "SDD_ROOT_DIR not set - skipping ticket detection"
        echo ""
        return 0
    fi

    # Check if SDD_ROOT_DIR is empty
    if [[ -z "$SDD_ROOT_DIR" ]]; then
        info "SDD_ROOT_DIR is empty - skipping ticket detection"
        echo ""
        return 0
    fi

    # Check if SDD_ROOT_DIR directory exists
    if [[ ! -d "$SDD_ROOT_DIR" ]]; then
        info "SDD_ROOT_DIR directory does not exist: $SDD_ROOT_DIR - skipping ticket detection"
        echo ""
        return 0
    fi

    # Convert worktree name to lowercase for case-insensitive matching
    local worktree_lower
    worktree_lower=$(echo "$worktree_name" | tr '[:upper:]' '[:lower:]')

    local active_tickets_dir="${SDD_ROOT_DIR}/tickets"
    local archived_tickets_dir="${SDD_ROOT_DIR}/archive/tickets"

    local matches=()
    local ticket_name
    local ticket_lower

    # Priority 1: Exact match in active tickets
    if [[ -d "$active_tickets_dir" ]]; then
        for ticket_dir in "$active_tickets_dir"/*/; do
            [[ -d "$ticket_dir" ]] || continue
            ticket_name=$(basename "$ticket_dir")
            ticket_lower=$(echo "$ticket_name" | tr '[:upper:]' '[:lower:]')

            # Exact match: ticket name equals worktree name
            if [[ "$ticket_lower" == "$worktree_lower" ]]; then
                matches+=("$ticket_dir")
            fi
        done

        if [[ ${#matches[@]} -eq 1 ]]; then
            echo "${matches[0]%/}"
            return 0
        elif [[ ${#matches[@]} -gt 1 ]]; then
            error "Multiple exact matches found for '$worktree_name':"
            for match in "${matches[@]}"; do
                error "  - $match"
            done
            return 3
        fi
    fi

    # Priority 2: Prefix match in active tickets
    matches=()
    if [[ -d "$active_tickets_dir" ]]; then
        for ticket_dir in "$active_tickets_dir"/*/; do
            [[ -d "$ticket_dir" ]] || continue
            ticket_name=$(basename "$ticket_dir")
            ticket_lower=$(echo "$ticket_name" | tr '[:upper:]' '[:lower:]')

            # Prefix match: ticket name starts with worktree name followed by underscore
            if [[ "$ticket_lower" == "${worktree_lower}_"* ]]; then
                matches+=("$ticket_dir")
            fi
        done

        if [[ ${#matches[@]} -ge 1 ]]; then
            # Return first match for prefix (not an error if multiple)
            echo "${matches[0]%/}"
            return 0
        fi
    fi

    # Priority 3: Exact match in archived tickets
    matches=()
    if [[ -d "$archived_tickets_dir" ]]; then
        for ticket_dir in "$archived_tickets_dir"/*/; do
            [[ -d "$ticket_dir" ]] || continue
            ticket_name=$(basename "$ticket_dir")
            ticket_lower=$(echo "$ticket_name" | tr '[:upper:]' '[:lower:]')

            # Exact match in archive
            if [[ "$ticket_lower" == "$worktree_lower" ]]; then
                matches+=("$ticket_dir")
            fi
        done

        if [[ ${#matches[@]} -eq 1 ]]; then
            echo "${matches[0]%/}"
            return 0
        elif [[ ${#matches[@]} -gt 1 ]]; then
            error "Multiple exact matches found in archive for '$worktree_name':"
            for match in "${matches[@]}"; do
                error "  - $match"
            done
            return 3
        fi
    fi

    # Priority 4: Prefix match in archived tickets
    matches=()
    if [[ -d "$archived_tickets_dir" ]]; then
        for ticket_dir in "$archived_tickets_dir"/*/; do
            [[ -d "$ticket_dir" ]] || continue
            ticket_name=$(basename "$ticket_dir")
            ticket_lower=$(echo "$ticket_name" | tr '[:upper:]' '[:lower:]')

            # Prefix match in archive
            if [[ "$ticket_lower" == "${worktree_lower}_"* ]]; then
                matches+=("$ticket_dir")
            fi
        done

        if [[ ${#matches[@]} -ge 1 ]]; then
            # Return first match for prefix
            echo "${matches[0]%/}"
            return 0
        fi
    fi

    # No match found
    echo ""
    return 1
}

# Get ticket status by parsing task files
# Arguments: ticket_directory_path
# Returns: "complete", "partial", or "not_started" on stdout
get_ticket_status() {
    local ticket_path="$1"
    local tasks_dir="${ticket_path}/tasks"

    # If no tasks directory, treat as not started
    if [[ ! -d "$tasks_dir" ]]; then
        echo "not_started"
        return 0
    fi

    local total_tasks=0
    local verified_tasks=0

    # Parse each task file
    for task_file in "$tasks_dir"/*.md; do
        [[ -f "$task_file" ]] || continue
        ((total_tasks++))

        # Check for verified checkbox: - [x] **Verified**
        if grep -q '\- \[x\] \*\*Verified\*\*' "$task_file" 2>/dev/null; then
            ((verified_tasks++))
        fi
    done

    # Determine status
    if [[ $total_tasks -eq 0 ]]; then
        echo "not_started"
    elif [[ $verified_tasks -eq $total_tasks ]]; then
        echo "complete"
    elif [[ $verified_tasks -gt 0 ]]; then
        echo "partial"
    else
        echo "not_started"
    fi
}

# Confirm cleanup with ticket status awareness
# Arguments: ticket_path, status, skip_confirmation_flag
# Exit codes: 0 = proceed, 5 = user cancelled
confirm_ticket_cleanup() {
    local ticket_path="$1"
    local status="$2"
    local skip_confirmation="$3"

    # If ticket is complete or no ticket found, proceed without prompting
    if [[ -z "$ticket_path" ]] || [[ "$status" == "complete" ]]; then
        return 0
    fi

    # Ticket is incomplete - display warning
    echo "" >&2
    echo "=========================================="  >&2
    echo "  WARNING: Incomplete Ticket Detected"  >&2
    echo "=========================================="  >&2
    echo "" >&2
    echo "  Ticket: $ticket_path" >&2
    echo "  Status: $status" >&2

    if [[ "$status" == "partial" ]]; then
        echo "  (Some tasks are not yet verified)" >&2
    elif [[ "$status" == "not_started" ]]; then
        echo "  (No tasks have been verified yet)" >&2
    fi
    echo "" >&2

    # If --yes flag is set, proceed without prompting
    if [[ "$skip_confirmation" == true ]]; then
        info "Proceeding with cleanup (--yes flag)"
        return 0
    fi

    # Prompt user for confirmation
    read -r -p "Continue with cleanup? (y/n) " response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        [nN][oO]|[nN])
            info "Cleanup cancelled by user"
            exit 5
            ;;
        *)
            info "Cleanup cancelled by user (invalid response)"
            exit 5
            ;;
    esac
}

##############################################################################
# Confirmation Prompt
##############################################################################

confirm_cleanup() {
    local name="$1"
    local repo="$2"
    local keep_branch="$3"
    local ticket_path="${4:-}"
    local ticket_status="${5:-}"

    echo "" >&2
    echo "=========================================="  >&2
    echo "  Worktree Cleanup Confirmation"  >&2
    echo "=========================================="  >&2
    echo "" >&2
    echo "  Repository: $repo" >&2
    echo "  Worktree: $name" >&2
    if [[ "$keep_branch" == true ]]; then
        echo "  Branch: will be KEPT" >&2
    else
        echo "  Branch: will be DELETED" >&2
    fi

    # Display ticket info if available
    if [[ -n "$ticket_path" ]]; then
        echo "" >&2
        echo "  Ticket: $(basename "$ticket_path")" >&2
        echo "  Ticket Status: $ticket_status" >&2
    fi
    echo "" >&2

    read -r -p "Proceed with cleanup? [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            info "Cleanup cancelled by user"
            exit 5
            ;;
    esac
}

##############################################################################
# Argument Parsing
##############################################################################

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -r|--repo)
            if [[ -z "${2:-}" ]]; then
                error "--repo requires an argument"
                show_help
                exit 3
            fi
            REPO="$2"
            shift 2
            ;;
        -w|--workspace)
            if [[ -z "${2:-}" ]]; then
                error "--workspace requires an argument"
                show_help
                exit 3
            fi
            WORKSPACE_FILE="$2"
            shift 2
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --keep-branch)
            KEEP_BRANCH=true
            shift
            ;;
        --skip-workspace)
            SKIP_WORKSPACE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            error "Unknown option: $1"
            show_help
            exit 3
            ;;
        *)
            # Positional argument - treat as worktree name
            if [[ -z "$WORKTREE_NAME" ]]; then
                WORKTREE_NAME="$1"
                shift
            else
                error "Unexpected positional argument: $1"
                show_help
                exit 3
            fi
            ;;
    esac
done

##############################################################################
# Argument Validation
##############################################################################

# Validate required arguments
if [[ -z "$WORKTREE_NAME" ]]; then
    error "Missing required argument: worktree-name"
    show_help
    exit 3
fi

if [[ -z "$REPO" ]]; then
    error "Missing required argument: --repo"
    show_help
    exit 3
fi

# Validate worktree name format
if [[ ! "$WORKTREE_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    error "Invalid worktree-name: $WORKTREE_NAME"
    error "Must contain only alphanumeric characters, hyphens, and underscores"
    exit 3
fi

# Validate repository name format
if [[ ! "$REPO" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    error "Invalid repository name: $REPO"
    error "Must contain only alphanumeric characters, hyphens, and underscores"
    exit 3
fi

##############################################################################
# Dry Run Mode
##############################################################################

if [[ "$DRY_RUN" == true ]]; then
    # Resolve workspace file for display
    resolved_workspace=$(resolve_workspace_file)

    echo ""
    echo "=========================================="
    echo "  DRY RUN - No changes will be made"
    echo "=========================================="
    echo ""

    # Platform detection
    if is_container; then
        echo "Platform: Container (direct execution)"
    else
        echo "Platform: macOS Host"
    fi

    echo ""
    echo "Would execute with resolved parameters:"
    echo "  Repository: $REPO"
    echo "  Worktree name: $WORKTREE_NAME"
    echo "  Worktree path: $(get_worktree_path "$WORKTREE_NAME" "$REPO")"

    if [[ -n "$resolved_workspace" ]]; then
        echo "  Workspace file: $resolved_workspace"
    else
        echo "  Workspace file: (none found - would skip workspace update)"
    fi

    if [[ "$KEEP_BRANCH" == true ]]; then
        echo "  Keep branch: yes"
    else
        echo "  Keep branch: no (branch will be deleted)"
    fi

    echo ""
    echo "Commands that would run:"
    echo ""

    dry_run_msg "1. Validate worktree exists:"
    echo "     crewchief worktree list | grep '$WORKTREE_NAME'"
    echo ""

    dry_run_msg "2. Git fetch origin main (30s timeout):"
    dry_run_repo_path="/workspace/repos/$REPO/$REPO"
    if [[ ! -d "$dry_run_repo_path" ]]; then
        dry_run_repo_path="/workspace/repos/$REPO"
    fi
    echo "     timeout 30s git -C $dry_run_repo_path fetch origin main"
    echo ""

    if [[ "$SKIP_WORKSPACE" != true ]] && [[ -n "$resolved_workspace" ]]; then
        dry_run_msg "3. Remove from workspace:"
        echo "     $SCRIPT_DIR/workspace-folder.sh remove $(get_worktree_path "$WORKTREE_NAME" "$REPO") -w \"$resolved_workspace\""
        echo ""
    else
        dry_run_msg "3. Workspace update: SKIPPED"
        if [[ "$SKIP_WORKSPACE" == true ]]; then
            echo "     (--skip-workspace flag)"
        else
            echo "     (no workspace file found)"
        fi
        echo ""
    fi

    dry_run_msg "4. Remove worktree:"
    if [[ "$KEEP_BRANCH" == true ]]; then
        echo "     crewchief worktree clean $WORKTREE_NAME --keep-branch"
    else
        echo "     crewchief worktree clean $WORKTREE_NAME"
    fi
    echo ""

    echo "=========================================="
    exit 0
fi

##############################################################################
# Main Execution
##############################################################################

# Validate prerequisites
validate_prerequisites

# Validate worktree exists
info "Validating worktree '$WORKTREE_NAME' exists..."
if ! worktree_exists "$WORKTREE_NAME" "$REPO"; then
    error "Worktree '$WORKTREE_NAME' not found in repository '$REPO'"
    error "Available worktrees:"

    # List available worktrees
    repo_path="/workspace/repos/$REPO/$REPO"
    if [[ ! -d "$repo_path" ]]; then
        repo_path="/workspace/repos/$REPO"
    fi
    if [[ -d "$repo_path" ]]; then
        (cd "$repo_path" && crewchief worktree list 2>/dev/null) >&2 || true
    fi

    exit 4
fi

WORKTREE_PATH=$(get_worktree_path "$WORKTREE_NAME" "$REPO")
success "Worktree found: $WORKTREE_PATH"

# Resolve workspace file
RESOLVED_WORKSPACE=$(resolve_workspace_file)

# Detect associated SDD ticket (before git fetch)
info "Checking for associated SDD ticket..."
set +e  # Temporarily disable exit on error for ticket detection
TICKET_PATH=$(find_ticket_for_worktree "$WORKTREE_NAME")
find_ticket_exit_code=$?
set -e  # Re-enable exit on error

if [[ $find_ticket_exit_code -eq 3 ]]; then
    error "Ambiguous ticket match - please resolve manually"
    exit 3
fi

# Get ticket status if ticket found
if [[ -n "$TICKET_PATH" ]]; then
    TICKET_STATUS=$(get_ticket_status "$TICKET_PATH")
    success "Ticket found: $(basename "$TICKET_PATH") (status: $TICKET_STATUS)"

    # Check for incomplete ticket and prompt for confirmation
    confirm_ticket_cleanup "$TICKET_PATH" "$TICKET_STATUS" "$SKIP_CONFIRMATION"
else
    info "No associated ticket found"
fi

# Confirm with user unless --yes flag
if [[ "$SKIP_CONFIRMATION" != true ]]; then
    confirm_cleanup "$WORKTREE_NAME" "$REPO" "$KEEP_BRANCH" "$TICKET_PATH" "$TICKET_STATUS"
fi

# Git fetch origin main
git_fetch_origin "$REPO"

# Remove from workspace (non-fatal)
remove_from_workspace "$WORKTREE_PATH" "$RESOLVED_WORKSPACE"

# Remove worktree (fatal if fails)
remove_worktree "$WORKTREE_NAME" "$REPO" "$KEEP_BRANCH"

##############################################################################
# Summary
##############################################################################

echo ""
echo "=========================================="
echo "  Worktree Cleanup Complete"
echo "=========================================="
echo ""
success "Worktree removed: $WORKTREE_PATH"

if [[ "$KEEP_BRANCH" == true ]]; then
    info "Branch kept (--keep-branch flag)"
else
    success "Branch deleted"
fi

if [[ "$SKIP_WORKSPACE" == true ]]; then
    info "Workspace: Skipped"
elif [[ -z "$RESOLVED_WORKSPACE" ]]; then
    info "Workspace: Skipped (no workspace file found)"
elif [[ " ${WARNINGS[*]} " =~ "Workspace update failed" ]]; then
    warn "Workspace: Failed (see warnings above)"
else
    success "Workspace: Updated"
fi

# Display ticket info
if [[ -n "$TICKET_PATH" ]]; then
    info "Ticket: $(basename "$TICKET_PATH") ($TICKET_STATUS)"
fi

# Display warnings if any
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo ""
    echo "Warnings:"
    for warning in "${WARNINGS[@]}"; do
        warn "$warning"
    done
fi

echo ""
echo "=========================================="

exit 0
