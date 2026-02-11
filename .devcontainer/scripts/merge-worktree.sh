#!/usr/bin/env bash
#
# merge-worktree.sh - Merge git worktree back to main with environment cleanup
#
# Version: 1.0.0
#
# DESCRIPTION:
#   Orchestrates the merge of a git worktree back to the base branch, including
#   PR status verification, main branch sync, merge via crewchief CLI, VS Code
#   workspace folder removal, and iTerm tab closure. This is the merge companion
#   to spawn-worktree.sh and cleanup-worktree.sh.
#
#   The script delegates the actual git merge to `crewchief worktree merge`,
#   handling all pre-merge checks and post-merge cleanup automatically.
#
# REQUIREMENTS:
#   - Running inside the devcontainer (container-mode only)
#   - Git repository with worktree support
#   - CrewChief CLI (crewchief worktree merge) installed
#   - jq installed for workspace updates (optional if --skip-workspace)
#   - workspace-folder.sh script for VS Code workspace updates
#   - gh CLI for PR status checks (optional, degrades gracefully)
#
# USAGE:
#   merge-worktree.sh [<worktree-name>] [OPTIONS]
#
# POSITIONAL ARGUMENTS:
#   worktree-name               Name of worktree to merge (auto-detected from cwd if omitted)
#
# OPTIONAL ARGUMENTS:
#   -r, --repo REPO             Repository name (auto-detected from cwd if omitted)
#   -s, --strategy STRATEGY     Merge strategy: ff, squash, cherry-pick (default: ff)
#   -b, --base-branch NAME      Base branch to merge into (default: main)
#   -w, --workspace FILE        VS Code workspace file path
#                               (default: from WORKSPACE_FILE or auto-detect)
#   -y, --yes                   Skip confirmation prompts (passed through to crewchief)
#   --skip-pr-check             Skip PR status verification
#   --skip-workspace            Skip VS Code workspace removal
#   --skip-tab-close            Skip iTerm tab closure
#   --dry-run                   Show what would be done without making changes
#   --verbose                   Enable debug logging to stderr for troubleshooting
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
#   0  - Success (worktree merged and cleaned up)
#   1  - Docker or container issues (daemon not running, container not running)
#   2  - Missing prerequisites (crewchief not found)
#   3  - Invalid arguments (missing required args, invalid format, main worktree detected)
#   4  - Worktree not found
#   5  - User cancelled
#   6  - Lock acquisition failed (another operation in progress for same worktree)
#   7  - Merge failed (crewchief merge returned error; no cleanup attempted)
#   8  - PR check blocked (PR is OPEN and non-draft)
#   9  - Main worktree not found at expected paths
#   10 - Success with warnings (merge succeeded but cleanup operations failed)
#
# EXAMPLES:
#
#   1. Auto-Detect - Merge current worktree (when inside worktree directory)
#      $ cd /workspace/repos/myproject/feature-auth
#      $ merge-worktree.sh
#
#      Output:
#        [INFO] Auto-detected from cwd: repo=myproject worktree=feature-auth
#        [INFO] Checking PR status for branch 'feature-auth'...
#        [OK] No PR found for branch - proceeding
#        [INFO] Syncing main branch with origin...
#        [OK] Main branch synced
#        [INFO] Merging worktree 'feature-auth'...
#        [OK] Worktree merged successfully
#        [INFO] Removing from VS Code workspace...
#        [OK] Workspace updated
#        [INFO] Closing iTerm tab...
#        [OK] Tab closed
#
#   2. Explicit Arguments - Specify repo and worktree
#      $ merge-worktree.sh feature-auth --repo myproject --yes
#
#   3. Custom Strategy - Squash merge
#      $ merge-worktree.sh feature-auth --repo myproject --strategy squash --yes
#
#   4. Dry Run - Preview planned actions
#      $ merge-worktree.sh --dry-run
#
#      Output:
#        ==========================================
#          DRY RUN - No changes will be made
#        ==========================================
#
#        Would execute with resolved parameters:
#          Repository: myproject
#          Worktree name: feature-auth
#          Base branch: main
#          Strategy: ff
#          ...
#
#   5. Skip PR Check - Merge without PR verification
#      $ merge-worktree.sh feature-auth --repo myproject --skip-pr-check --yes
#
#   6. Custom Base Branch - Merge into develop
#      $ merge-worktree.sh feature-auth --repo myproject --base-branch develop --yes
#
# TROUBLESHOOTING:
#
#   Error: "Worktree 'xyz' not found"
#   Solution: Verify worktree name and repo with:
#     crewchief worktree list
#
#   Error: "You appear to be in the main worktree"
#   Solution: Navigate to the feature worktree directory, or specify the worktree
#     name explicitly as a positional argument.
#
#   Error: "PR is still open"
#   Solution: Close or merge the PR first, or use --skip-pr-check to bypass.
#
#   Error: "Main worktree not found"
#   Solution: Ensure the main worktree exists at /workspace/repos/<repo>/<repo>
#     or /workspace/repos/<repo>.
#
#   Error: "Merge failed"
#   Solution: The worktree remains intact. Resolve conflicts manually in the main
#     worktree and retry, or abort with: git merge --abort
#
#   Warning: "Could not close tab"
#   Solution: Close the tab manually. The merge succeeded; this is cosmetic.
#

set -euo pipefail

##############################################################################
# Section 1: Load Shared Functions
##############################################################################

# Locate worktree-common.sh: try script's own directory first, then canonical path
_WC_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_WC_COMMON="$_WC_SCRIPT_DIR/worktree-common.sh"
if [ ! -f "$_WC_COMMON" ]; then
    _WC_COMMON="/workspace/.devcontainer/scripts/worktree-common.sh"
fi
. "$_WC_COMMON" || {
    echo "Error: Failed to load worktree-common.sh" >&2
    echo "Searched: $_WC_SCRIPT_DIR/worktree-common.sh and /workspace/.devcontainer/scripts/worktree-common.sh" >&2
    exit 1
}
unset _WC_SCRIPT_DIR _WC_COMMON

# Dry-run output function (specific to merge-worktree.sh)
dry_run_msg() {
    printf '\033[0;35m[DRY-RUN]\033[0m %s\n' "$*" >&2
}

# Locate this script's directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

##############################################################################
# Section 2: Configuration
##############################################################################

# iTerm plugin integration (default to main repo plugins directory, allow override)
ITERM_PLUGIN_DIR="${ITERM_PLUGIN_DIR:-/workspace/repos/claude-code-plugins/claude-code-plugins/plugins/iterm}"
ITERM_CLOSE_TAB_SCRIPT="$ITERM_PLUGIN_DIR/skills/tab-management/scripts/iterm-close-tab.sh"

# Default values
DEFAULT_WORKSPACE="/workspace/workspace.code-workspace"
DEFAULT_BASE_BRANCH="main"
DEFAULT_STRATEGY="ff"

# Initialize variables from environment or defaults
WORKSPACE_FILE="${WORKSPACE_FILE:-}"

# Variables to be set by argument parsing
WORKTREE_NAME=""
REPO=""
STRATEGY="$DEFAULT_STRATEGY"
BASE_BRANCH="$DEFAULT_BASE_BRANCH"
SKIP_CONFIRMATION=false
SKIP_PR_CHECK=false
SKIP_WORKSPACE=false
SKIP_TAB_CLOSE=false
DRY_RUN=false

# Global array to collect warnings
WARNINGS=()

# Track whether we have a final non-zero exit
EXIT_CODE=0

##############################################################################
# Section 3: Help Function
##############################################################################

show_help() {
    cat << 'EOF'
Usage: merge-worktree.sh [<worktree-name>] [OPTIONS]

Merge a git worktree back to the base branch and clean up environment.

Auto-detects repo and worktree name from current working directory when
positional argument is omitted.

POSITIONAL ARGUMENTS:
  worktree-name               Name of worktree to merge (auto-detected if omitted)

OPTIONS:
  -r, --repo REPO             Repository name (auto-detected from cwd if omitted)
  -s, --strategy STRATEGY     Merge strategy: ff, squash, cherry-pick (default: ff)
  -b, --base-branch NAME      Base branch to merge into (default: main)
  -w, --workspace FILE        VS Code workspace file path
                              (default: from WORKSPACE_FILE or auto-detect)
  -y, --yes                   Skip confirmation prompts (passed through to crewchief)
  --skip-pr-check             Skip PR status verification
  --skip-workspace            Skip VS Code workspace removal
  --skip-tab-close            Skip iTerm tab closure
  --dry-run                   Show what would be done without making changes
  --verbose                   Enable debug logging to stderr
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
  0   Success (worktree merged and cleaned up)
  1   Docker or container issues
  2   Missing prerequisites (crewchief CLI not found)
  3   Invalid arguments (missing required args, invalid format)
  4   Worktree not found
  5   User cancelled
  6   Lock acquisition failed (another operation in progress)
  7   Merge failed (crewchief merge returned error)
  8   PR check blocked (PR is OPEN and non-draft)
  9   Main worktree not found
  10  Success with warnings (merge ok, cleanup failed)

EXAMPLES:
  # Auto-detect from cwd (inside worktree directory)
  cd /workspace/repos/myproject/feature-auth && merge-worktree.sh

  # Explicit worktree and repo
  merge-worktree.sh feature-auth --repo myproject

  # Squash merge, skip confirmation
  merge-worktree.sh feature-auth --repo myproject --strategy squash --yes

  # Dry run to preview actions
  merge-worktree.sh --dry-run

  # Skip PR check
  merge-worktree.sh --skip-pr-check --yes

  # Merge into develop instead of main
  merge-worktree.sh feature-auth --repo myproject --base-branch develop --yes

REQUIREMENTS:
  - Running inside devcontainer
  - CrewChief CLI (crewchief worktree merge) installed
  - For PR checks: gh CLI installed and authenticated
  - For workspace: jq installed and workspace file exists
  - For tab close: iterm-close-tab.sh available

NOTE:
  The script must change to the main worktree directory before running the
  merge. If merge fails, the worktree remains intact for manual resolution.

EOF
}

##############################################################################
# Section 4: CWD Auto-Detection Functions
##############################################################################

# Detect repo and worktree from current working directory
# Sets: DETECTED_REPO, DETECTED_WORKTREE
# Returns: 0 if detected, 1 if not in a recognizable worktree path
detect_from_cwd() {
    local cwd
    cwd="$(pwd)"

    debug "detect_from_cwd(): cwd=$cwd"

    # Check if path is under /workspace/repos/
    local repos_prefix="/workspace/repos/"
    if [[ "$cwd" != ${repos_prefix}* ]]; then
        debug "detect_from_cwd(): not under $repos_prefix"
        return 1
    fi

    # Strip prefix to get the relative portion: <repo>/<worktree>[/subdir/...]
    local relative_path="${cwd#${repos_prefix}}"

    # Extract first two path components
    local repo_segment worktree_segment
    repo_segment="$(echo "$relative_path" | cut -d'/' -f1)"
    worktree_segment="$(echo "$relative_path" | cut -d'/' -f2)"

    debug "detect_from_cwd(): repo_segment=$repo_segment worktree_segment=$worktree_segment"

    # Must have both segments
    if [[ -z "$repo_segment" ]] || [[ -z "$worktree_segment" ]]; then
        debug "detect_from_cwd(): could not extract both repo and worktree segments"
        return 1
    fi

    # If repo == worktree, the user is in the main worktree
    if [[ "$repo_segment" == "$worktree_segment" ]]; then
        error "You appear to be in the main worktree (/workspace/repos/$repo_segment/$worktree_segment)"
        error "Navigate to a feature worktree directory, or specify the worktree name explicitly:"
        error "  merge-worktree.sh <worktree-name> --repo $repo_segment"
        exit 3
    fi

    # Validate both names
    if ! validate_worktree_name "$repo_segment"; then
        debug "detect_from_cwd(): repo segment failed validation"
        return 1
    fi
    if ! validate_worktree_name "$worktree_segment"; then
        debug "detect_from_cwd(): worktree segment failed validation"
        return 1
    fi

    DETECTED_REPO="$repo_segment"
    DETECTED_WORKTREE="$worktree_segment"
    return 0
}

##############################################################################
# Section 5: PR Status Check Functions
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

# Check PR status for the worktree's branch
# Arguments: branch_name, base_branch
# Returns: 0 = proceed, exits 8 if PR is open and non-draft
check_pr_status() {
    local branch_name="$1"
    local base_branch="$2"

    if [[ "$SKIP_PR_CHECK" == true ]]; then
        info "Skipping PR status check (--skip-pr-check flag)"
        return 0
    fi

    # Check if gh CLI is available
    if ! command -v gh &>/dev/null; then
        warn "gh CLI not available - skipping PR status check"
        warn "Install with: brew install gh (macOS) or apt install gh (Linux)"
        return 0
    fi

    info "Checking PR status for branch '$branch_name' targeting '$base_branch'..."

    local pr_json
    local pr_exit_code=0
    pr_json=$(run_with_timeout 10 gh pr view "$branch_name" --json state,isDraft --jq '{state: .state, isDraft: .isDraft}' 2>/dev/null) || pr_exit_code=$?

    debug "check_pr_status(): pr_exit_code=$pr_exit_code pr_json=$pr_json"

    # Handle timeout (exit code 124)
    if [[ $pr_exit_code -eq 124 ]]; then
        warn "PR status check timed out after 10 seconds - proceeding"
        return 0
    fi

    # Handle no PR found or other gh failure
    if [[ $pr_exit_code -ne 0 ]] || [[ -z "$pr_json" ]]; then
        info "No PR found for branch '$branch_name' - proceeding"
        return 0
    fi

    # Parse state and isDraft
    local state is_draft
    state=$(echo "$pr_json" | jq -r '.state // empty' 2>/dev/null) || true
    is_draft=$(echo "$pr_json" | jq -r '.isDraft // false' 2>/dev/null) || true

    debug "check_pr_status(): state=$state isDraft=$is_draft"

    case "$state" in
        MERGED)
            info "PR already merged - proceeding"
            return 0
            ;;
        CLOSED)
            warn "PR was closed without merge - proceeding"
            return 0
            ;;
        OPEN)
            if [[ "$is_draft" == "true" ]]; then
                warn "PR is in DRAFT state - proceeding with merge"
                return 0
            else
                error "PR for branch '$branch_name' is still OPEN"
                error "Close or merge the PR first, or use --skip-pr-check to bypass"
                exit 8
            fi
            ;;
        *)
            warn "Unknown PR state '$state' - proceeding"
            return 0
            ;;
    esac
}

##############################################################################
# Section 6: Main Sync Function
##############################################################################

# Resolve and return the main worktree path for a repository
# Arguments: repo_name
# Returns: path on stdout, exits 9 if not found
resolve_main_worktree_path() {
    local repo="$1"

    # Try nested directory first: /workspace/repos/<repo>/<repo>
    local primary_path="/workspace/repos/$repo/$repo"
    if [[ -d "$primary_path" ]]; then
        echo "$primary_path"
        return 0
    fi

    # Fallback: /workspace/repos/<repo>
    local fallback_path="/workspace/repos/$repo"
    if [[ -d "$fallback_path" ]]; then
        echo "$fallback_path"
        return 0
    fi

    # Neither exists
    error "Main worktree not found at expected paths:"
    error "  Primary: $primary_path"
    error "  Fallback: $fallback_path"
    error "Ensure the repository exists in /workspace/repos/"
    exit 9
}

# Sync the main branch with origin
# Arguments: main_worktree_path, base_branch
# Returns: always 0 (non-fatal)
sync_main_branch() {
    local main_path="$1"
    local base_branch="$2"

    info "Syncing $base_branch branch with origin (30s timeout)..."

    if run_with_timeout 30 git -C "$main_path" pull origin "$base_branch" 2>/dev/null; then
        success "Main branch synced"
        return 0
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            warn "Git pull timed out after 30 seconds"
        else
            warn "Git pull failed (exit code: $exit_code)"
        fi
        warn "Main branch may not be up to date. Merge conflicts may occur."
        WARNINGS+=("Main branch sync failed - branch may not be up to date")
        return 0  # Non-fatal, continue with merge
    fi
}

##############################################################################
# Section 7: Workspace Removal Function
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

# Remove worktree folder from VS Code workspace
# Arguments: worktree_path, workspace_file
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
# Section 8: Argument Parsing
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
        -s|--strategy)
            if [[ -z "${2:-}" ]]; then
                error "--strategy requires an argument"
                show_help
                exit 3
            fi
            STRATEGY="$2"
            shift 2
            ;;
        -b|--base-branch)
            if [[ -z "${2:-}" ]]; then
                error "--base-branch requires an argument"
                show_help
                exit 3
            fi
            BASE_BRANCH="$2"
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
        --skip-pr-check)
            SKIP_PR_CHECK=true
            shift
            ;;
        --skip-workspace)
            SKIP_WORKSPACE=true
            shift
            ;;
        --skip-tab-close)
            SKIP_TAB_CLOSE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            DEBUG=true
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
# Argument Validation & Auto-Detection
##############################################################################

# Auto-detect repo and worktree from cwd if not provided
if [[ -z "$WORKTREE_NAME" ]] || [[ -z "$REPO" ]]; then
    DETECTED_REPO=""
    DETECTED_WORKTREE=""

    if detect_from_cwd; then
        # Use detected values for any missing arguments
        if [[ -z "$REPO" ]]; then
            REPO="$DETECTED_REPO"
            debug "Auto-detected repo: $REPO"
        fi
        if [[ -z "$WORKTREE_NAME" ]]; then
            WORKTREE_NAME="$DETECTED_WORKTREE"
            debug "Auto-detected worktree: $WORKTREE_NAME"
        fi
        info "Auto-detected from cwd: repo=$REPO worktree=$WORKTREE_NAME"
    else
        # Auto-detection failed and we're missing arguments
        if [[ -z "$WORKTREE_NAME" ]]; then
            error "Missing worktree name and could not auto-detect from current directory"
            error "Either navigate to a worktree directory or provide the name explicitly:"
            error "  merge-worktree.sh <worktree-name> --repo <repository>"
            show_help
            exit 3
        fi
        if [[ -z "$REPO" ]]; then
            error "Missing --repo and could not auto-detect from current directory"
            error "Provide the repository name explicitly:"
            error "  merge-worktree.sh $WORKTREE_NAME --repo <repository>"
            show_help
            exit 3
        fi
    fi
fi

# Validate worktree name format
validate_worktree_name "$WORKTREE_NAME" || exit 3

# Validate repository name format
validate_worktree_name "$REPO" || exit 3

# Validate strategy
case "$STRATEGY" in
    ff|squash|cherry-pick)
        ;;
    *)
        error "Invalid merge strategy: $STRATEGY"
        error "Valid strategies: ff, squash, cherry-pick"
        exit 3
        ;;
esac

debug "Parsed arguments: REPO=$REPO WORKTREE_NAME=$WORKTREE_NAME"
debug "Flags: DRY_RUN=$DRY_RUN SKIP_WORKSPACE=$SKIP_WORKSPACE SKIP_PR_CHECK=$SKIP_PR_CHECK SKIP_TAB_CLOSE=$SKIP_TAB_CLOSE SKIP_CONFIRMATION=$SKIP_CONFIRMATION"
debug "Strategy=$STRATEGY BaseBranch=$BASE_BRANCH"
debug "WORKSPACE_FILE=${WORKSPACE_FILE:-<auto>}"

##############################################################################
# Prerequisite Validation
##############################################################################

validate_prerequisites() {
    debug "Entering validate_prerequisites()"

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

# Run prerequisite validation (also runs in dry-run mode)
validate_prerequisites

##############################################################################
# Worktree Path Resolution
##############################################################################

# Get the full path to the worktree
get_worktree_path() {
    local name="$1"
    local repo="$2"

    local repo_path="/workspace/repos/$repo/$repo"
    if [[ ! -d "$repo_path" ]]; then
        repo_path="/workspace/repos/$repo"
    fi

    local target_path="$repo_path/../$name"
    # Try GNU realpath -m first, then fall back for compatibility
    if command -v realpath &>/dev/null && realpath -m . &>/dev/null 2>&1; then
        realpath -m "$target_path" 2>/dev/null
    else
        # Fallback for systems without realpath -m
        (cd "$(dirname "$target_path")" 2>/dev/null && echo "$(pwd)/$(basename "$target_path")") || echo "/workspace/repos/$repo/$name"
    fi
}

WORKTREE_PATH=$(get_worktree_path "$WORKTREE_NAME" "$REPO")

##############################################################################
# Dry Run Mode
##############################################################################

if [[ "$DRY_RUN" == true ]]; then
    # Resolve workspace file for display
    resolved_workspace=$(resolve_workspace_file)

    # Resolve main worktree path (for display; may exit 9 if not found)
    main_path=$(resolve_main_worktree_path "$REPO")

    echo ""
    echo "=========================================="
    echo "  DRY RUN - No changes will be made"
    echo "=========================================="
    echo ""

    echo "Would execute with resolved parameters:"
    echo "  Repository: $REPO"
    echo "  Worktree name: $WORKTREE_NAME"
    echo "  Worktree path: $WORKTREE_PATH"
    echo "  Main worktree: $main_path"
    echo "  Base branch: $BASE_BRANCH"
    echo "  Strategy: $STRATEGY"

    if [[ -n "$resolved_workspace" ]]; then
        echo "  Workspace file: $resolved_workspace"
    else
        echo "  Workspace file: (none found - would skip workspace update)"
    fi

    echo ""
    echo "Planned operations:"
    echo ""

    local_step=1

    if [[ "$SKIP_PR_CHECK" != true ]]; then
        dry_run_msg "$local_step. Check PR status:"
        echo "     gh pr view $WORKTREE_NAME --json state,isDraft (10s timeout)"
        echo ""
        local_step=$((local_step + 1))
    else
        dry_run_msg "$local_step. PR status check: SKIPPED (--skip-pr-check)"
        echo ""
        local_step=$((local_step + 1))
    fi

    dry_run_msg "$local_step. Sync main branch:"
    echo "     git -C $main_path pull origin $BASE_BRANCH (30s timeout)"
    echo ""
    local_step=$((local_step + 1))

    dry_run_msg "$local_step. Merge worktree (from main worktree directory):"
    echo "     cd $main_path"
    echo "     crewchief worktree merge $WORKTREE_NAME --strategy $STRATEGY"
    echo ""
    local_step=$((local_step + 1))

    if [[ "$SKIP_WORKSPACE" != true ]] && [[ -n "$resolved_workspace" ]]; then
        dry_run_msg "$local_step. Remove from workspace:"
        echo "     $SCRIPT_DIR/workspace-folder.sh remove $WORKTREE_PATH -w \"$resolved_workspace\""
        echo ""
        local_step=$((local_step + 1))
    else
        dry_run_msg "$local_step. Workspace update: SKIPPED"
        if [[ "$SKIP_WORKSPACE" == true ]]; then
            echo "     (--skip-workspace flag)"
        else
            echo "     (no workspace file found)"
        fi
        echo ""
        local_step=$((local_step + 1))
    fi

    if [[ "$SKIP_TAB_CLOSE" != true ]]; then
        dry_run_msg "$local_step. Close iTerm tab:"
        echo "     iterm-close-tab.sh --force \"$REPO $WORKTREE_NAME\""
        echo ""
    else
        dry_run_msg "$local_step. Tab close: SKIPPED (--skip-tab-close)"
        echo ""
    fi

    echo "=========================================="
    exit 0
fi

##############################################################################
# Concurrent Execution Protection
##############################################################################

LOCK_FILE="/tmp/worktree-merge-${REPO}-${WORKTREE_NAME}.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    error "Another operation is in progress for worktree '$WORKTREE_NAME' in repo '$REPO'"
    error "If you're sure no other operation is running, remove: $LOCK_FILE"
    exit 6
fi
trap 'flock -u 200; rm -f "$LOCK_FILE"' EXIT INT TERM

##############################################################################
# Section 9: Main Execution Flow
##############################################################################

# Step 1: Validate worktree exists
info "Validating worktree '$WORKTREE_NAME' exists..."
if [[ ! -d "$WORKTREE_PATH" ]]; then
    error "Worktree '$WORKTREE_NAME' not found at: $WORKTREE_PATH"
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
success "Worktree found: $WORKTREE_PATH"

# Step 2: PR status check
check_pr_status "$WORKTREE_NAME" "$BASE_BRANCH"

# Step 3: Resolve main worktree path
MAIN_WORKTREE_PATH=$(resolve_main_worktree_path "$REPO")
debug "Main worktree path: $MAIN_WORKTREE_PATH"

# Step 4: Sync main branch (non-fatal)
sync_main_branch "$MAIN_WORKTREE_PATH" "$BASE_BRANCH"

# Capture tab pattern BEFORE changing directory
TAB_PATTERN="$REPO $WORKTREE_NAME"
debug "Captured tab pattern: $TAB_PATTERN"

# Step 5: Confirmation prompt
if [[ "$SKIP_CONFIRMATION" != true ]]; then
    echo "" >&2
    echo "==========================================" >&2
    echo "  Worktree Merge Confirmation" >&2
    echo "==========================================" >&2
    echo "" >&2
    echo "  Repository: $REPO" >&2
    echo "  Worktree: $WORKTREE_NAME" >&2
    echo "  Base branch: $BASE_BRANCH" >&2
    echo "  Strategy: $STRATEGY" >&2
    echo "  Main worktree: $MAIN_WORKTREE_PATH" >&2
    echo "" >&2

    read -r -p "Proceed with merge? [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY])
            ;;
        *)
            info "Merge cancelled by user"
            exit 5
            ;;
    esac
fi

# Step 6: Change to main worktree and execute merge
info "Merging worktree '$WORKTREE_NAME' into '$BASE_BRANCH'..."

# Build crewchief command arguments
MERGE_ARGS=("worktree" "merge" "$WORKTREE_NAME")
if [[ "$STRATEGY" != "$DEFAULT_STRATEGY" ]]; then
    MERGE_ARGS+=("--strategy" "$STRATEGY")
fi
if [[ "$SKIP_CONFIRMATION" == true ]]; then
    MERGE_ARGS+=("--yes")
fi

debug "Executing: cd $MAIN_WORKTREE_PATH && crewchief ${MERGE_ARGS[*]}"

if (cd "$MAIN_WORKTREE_PATH" && crewchief "${MERGE_ARGS[@]}"); then
    success "Worktree merged successfully"
else
    error "Merge failed. Worktree remains intact."
    error "To resolve: review conflicts in $MAIN_WORKTREE_PATH and retry"
    error "  To continue merge: cd $MAIN_WORKTREE_PATH && git merge --continue"
    error "  To abort merge: cd $MAIN_WORKTREE_PATH && git merge --abort"
    exit 7
fi

# Step 7: Resolve workspace file and remove from workspace (non-fatal, after successful merge)
RESOLVED_WORKSPACE=$(resolve_workspace_file)
remove_from_workspace "$WORKTREE_PATH" "$RESOLVED_WORKSPACE"

# Step 8: Close iTerm tab (last operation, non-fatal)
if [[ "$SKIP_TAB_CLOSE" == true ]]; then
    info "Skipping tab close (--skip-tab-close flag)"
else
    debug "Attempting to close iTerm tab with pattern: $TAB_PATTERN"
    if [ -x "$ITERM_CLOSE_TAB_SCRIPT" ]; then
        if "$ITERM_CLOSE_TAB_SCRIPT" --force "$TAB_PATTERN"; then
            success "Tab closed"
        else
            warn "Could not close tab '$TAB_PATTERN'. Please close manually."
            WARNINGS+=("Tab close failed for: $TAB_PATTERN")
        fi
    else
        warn "iTerm plugin not available at: $ITERM_CLOSE_TAB_SCRIPT"
        warn "Skipping tab close"
        WARNINGS+=("Tab close skipped - iTerm plugin not available")
    fi
fi

##############################################################################
# Summary
##############################################################################

echo ""
echo "=========================================="
echo "  Worktree Merge Complete"
echo "=========================================="
echo ""
success "Worktree merged: $WORKTREE_NAME -> $BASE_BRANCH"
info "Strategy: $STRATEGY"
info "Repository: $REPO"

if [[ "$SKIP_WORKSPACE" == true ]]; then
    info "Workspace: Skipped"
elif [[ -z "$RESOLVED_WORKSPACE" ]]; then
    info "Workspace: Skipped (no workspace file found)"
else
    # Check if workspace update failed by searching warnings
    if [[ " ${WARNINGS[*]} " =~ "Workspace update failed" ]]; then
        warn "Workspace: Failed (see warnings above)"
    else
        success "Workspace: Updated"
    fi
fi

if [[ "$SKIP_TAB_CLOSE" == true ]]; then
    info "Tab close: Skipped"
else
    if [[ " ${WARNINGS[*]} " =~ "Tab close" ]]; then
        warn "Tab close: Failed (see warnings above)"
    else
        success "Tab close: Done"
    fi
fi

# Display warnings if any
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo ""
    echo "Warnings:"
    for warning in "${WARNINGS[@]}"; do
        warn "$warning"
    done

    # If there are warnings but merge succeeded, exit 10
    echo ""
    echo "=========================================="
    echo ""
    warn "Merge succeeded but some cleanup operations failed."
    warn "Manual cleanup may be needed (see warnings above)."
    exit 10
fi

echo ""
echo "=========================================="

exit 0
