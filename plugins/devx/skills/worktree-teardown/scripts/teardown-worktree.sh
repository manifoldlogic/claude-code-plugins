#!/usr/bin/env bash
#
# teardown-worktree.sh - Close cmux workspace and clean up git worktree
#
# Version: 1.0.0
#
# DESCRIPTION:
#   Orchestrates the teardown of a git worktree by first closing the associated
#   cmux workspace (identified by name matching) and then delegating worktree
#   cleanup to cleanup-worktree.sh. This is the teardown counterpart to
#   setup-worktree.sh in the devx plugin's worktree lifecycle.
#
# REQUIREMENTS:
#   - Running inside the devcontainer (container-mode only)
#   - cleanup-worktree.sh script for worktree removal
#   - cmux-ssh.sh and cmux-check.sh for terminal session closure (optional)
#
# USAGE:
#   teardown-worktree.sh <worktree-name> --repo <repository> [OPTIONS]
#
# POSITIONAL ARGUMENTS:
#   worktree-name               Name of the worktree to tear down
#
# REQUIRED ARGUMENTS:
#   -r, --repo REPO             Repository name
#
# OPTIONAL ARGUMENTS:
#   -y, --yes                   Skip confirmation prompt (passed to cleanup-worktree.sh)
#   --keep-branch               Don't delete the git branch (passed to cleanup-worktree.sh)
#   --skip-cmux                 Skip cmux workspace closure (steps 2-3)
#   --skip-workspace            Skip VS Code workspace update (passed to cleanup-worktree.sh)
#   --dry-run                   Preview planned operations
#   --verbose                   Show detailed cmux-ssh.sh and cleanup-worktree.sh output
#   -h, --help                  Show this help message and exit
#
# EXIT CODES:
#   0  - Success (worktree torn down, cmux closed or gracefully skipped)
#   1  - Usage error (missing required arguments, invalid name format)
#   2  - Prerequisite failure (required tools not found)
#   3  - Unrecognized option (including name starting with hyphen)
#   4  - Worktree cleanup failure (cleanup-worktree.sh fatal error)
#   5  - User cancelled (cleanup-worktree.sh exit 5 passthrough)
#
# EXAMPLES:
#
#   1. Tear down worktree with full cleanup
#      $ teardown-worktree.sh TICKET-1 --repo crewchief
#
#   2. Tear down without confirmation prompt
#      $ teardown-worktree.sh TICKET-1 --repo crewchief --yes
#
#   3. Skip cmux workspace closure
#      $ teardown-worktree.sh TICKET-1 --repo crewchief --skip-cmux
#
#   4. Dry run to preview
#      $ teardown-worktree.sh TICKET-1 --repo crewchief --dry-run
#
#   5. Keep the git branch after teardown
#      $ teardown-worktree.sh TICKET-1 --repo crewchief --keep-branch
#

set -euo pipefail

##############################################################################
# Section 1: Logging Helpers
##############################################################################

log_info() {
    printf '\033[0;34m[INFO]\033[0m %s\n' "$*" >&2
}

log_warn() {
    printf '\033[0;33m[WARN]\033[0m %s\n' "$*" >&2
}

log_error() {
    printf '\033[0;31m[ERROR]\033[0m %s\n' "$*" >&2
}

log_success() {
    printf '\033[0;32m[OK]\033[0m %s\n' "$*" >&2
}

dry_run_msg() {
    printf '\033[0;35m[DRY-RUN]\033[0m %s\n' "$*" >&2
}

log_verbose() {
    if [ "$VERBOSE" = "true" ]; then
        printf '\033[0;36m[VERBOSE]\033[0m %s\n' "$*" >&2
    fi
}

##############################################################################
# Section 2: Configuration
##############################################################################

# Path defaults (configurable via environment)
CMUX_PLUGIN_DIR="${CMUX_PLUGIN_DIR:-/workspace/repos/claude-code-plugins/claude-code-plugins/plugins/cmux}"
CMUX_SSH_SCRIPT="$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh"
CMUX_CHECK_SCRIPT="$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-check.sh"
CLEANUP_WORKTREE_SCRIPT="${CLEANUP_WORKTREE_SCRIPT:-/workspace/.devcontainer/scripts/cleanup-worktree.sh}"

# Variables to be set by argument parsing
WORKTREE_NAME=""
REPO=""
SKIP_CMUX=false
SKIP_WORKSPACE=false
KEEP_BRANCH=false
YES=false
DRY_RUN=false
VERBOSE=false

##############################################################################
# Section 3: Help Function
##############################################################################

show_help() {
    cat << 'EOF'
Usage: teardown-worktree.sh <worktree-name> --repo <repository> [OPTIONS]

Close cmux workspace and clean up git worktree.

Orchestrates 4 steps: prerequisite validation, cmux workspace identification,
cmux workspace closure, and worktree cleanup (delegated to cleanup-worktree.sh).

POSITIONAL ARGUMENTS:
  worktree-name               Name of the worktree to tear down

REQUIRED:
  -r, --repo REPO             Repository name

OPTIONS:
  -y, --yes                   Skip confirmation prompt (passed to cleanup-worktree.sh)
  --keep-branch               Don't delete the git branch (passed to cleanup-worktree.sh)
  --skip-cmux                 Skip cmux workspace closure (steps 2-3)
  --skip-workspace            Skip VS Code workspace update (passed to cleanup-worktree.sh)
  --dry-run                   Preview planned operations
  --verbose                   Show detailed cmux-ssh.sh and cleanup-worktree.sh output
  -h, --help                  Show this help message and exit

EXIT CODES:
  0   Success (worktree torn down, cmux closed or gracefully skipped)
  1   Usage error (missing required arguments, invalid name format)
  2   Prerequisite failure (required tools not found)
  3   Unrecognized option (including name starting with hyphen)
  4   Worktree cleanup failure (cleanup-worktree.sh fatal error)
  5   User cancelled (cleanup-worktree.sh exit 5 passthrough)

EXAMPLES:
  # Tear down worktree with full cleanup
  teardown-worktree.sh TICKET-1 --repo crewchief

  # Tear down without confirmation prompt
  teardown-worktree.sh TICKET-1 --repo crewchief --yes

  # Skip cmux workspace closure
  teardown-worktree.sh TICKET-1 --repo crewchief --skip-cmux

  # Dry run to preview
  teardown-worktree.sh TICKET-1 --repo crewchief --dry-run

  # Keep the git branch after teardown
  teardown-worktree.sh TICKET-1 --repo crewchief --keep-branch

ENVIRONMENT VARIABLES:
  CMUX_PLUGIN_DIR             Path to cmux plugin directory
                              (default: /workspace/repos/claude-code-plugins/claude-code-plugins/plugins/cmux)
  CLEANUP_WORKTREE_SCRIPT     Path to cleanup-worktree.sh
                              (default: /workspace/.devcontainer/scripts/cleanup-worktree.sh)

EOF
}

##############################################################################
# Section 4: Argument Parsing
##############################################################################

while [ $# -gt 0 ]; do
    case "$1" in
        -r|--repo)
            if [ -z "${2:-}" ]; then
                log_error "--repo requires an argument"
                exit 1
            fi
            REPO="$2"
            shift 2
            ;;
        -y|--yes)
            YES=true
            shift
            ;;
        --keep-branch)
            KEEP_BRANCH=true
            shift
            ;;
        --skip-cmux)
            SKIP_CMUX=true
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
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            log_error "Unrecognized option: $1"
            exit 3
            ;;
        *)
            # Positional argument - treat as worktree name
            if [ -z "$WORKTREE_NAME" ]; then
                WORKTREE_NAME="$1"
                shift
            else
                log_error "Unexpected positional argument: $1"
                exit 1
            fi
            ;;
    esac
done

##############################################################################
# Section 5: Argument Validation
##############################################################################

if [ -z "$WORKTREE_NAME" ]; then
    log_error "Error: worktree name is required"
    echo "" >&2
    show_help
    exit 1
fi

if [ -z "$REPO" ]; then
    log_error "Error: --repo is required"
    echo "" >&2
    show_help
    exit 1
fi

# Validate worktree name format - reject names containing /, spaces, or .
if printf '%s' "$WORKTREE_NAME" | grep -qE '[/ .]'; then
    log_error "Invalid worktree name: '$WORKTREE_NAME'"
    log_error "Names must not contain slashes, spaces, or dots."
    exit 1
fi

# Validate worktree name format - must start with alphanumeric and contain only valid chars
if ! printf '%s' "$WORKTREE_NAME" | grep -qE '^[a-zA-Z0-9][a-zA-Z0-9_-]*$'; then
    log_error "Invalid worktree name: '$WORKTREE_NAME'"
    log_error "Names must start with a letter or digit and contain only letters, digits, hyphens, and underscores."
    exit 1
fi

# Validate repo name format (must not contain /, ., or spaces)
if ! printf '%s' "$REPO" | grep -qE '^[a-zA-Z0-9][a-zA-Z0-9_-]*$'; then
    log_error "--repo value '$REPO' is invalid. Use alphanumeric characters, hyphens, and underscores only."
    exit 1
fi

##############################################################################
# Section 6: Dry Run Mode
##############################################################################

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "=== DRY RUN: teardown-worktree ==="
    echo "Worktree: $WORKTREE_NAME"
    echo "Repo:     $REPO"
    echo ""

    echo "Flags:"
    echo "  Skip cmux: $SKIP_CMUX"
    echo "  Skip workspace: $SKIP_WORKSPACE"
    echo "  Keep branch: $KEEP_BRANCH"
    echo "  Yes (skip confirm): $YES"
    echo "  Verbose: $VERBOSE"
    echo ""

    echo "Planned operations:"
    echo ""

    dry_run_msg "Step 1: Validate prerequisites"
    echo "     Check: cleanup-worktree.sh, cmux-check.sh"
    echo ""

    if [ "$SKIP_CMUX" = true ]; then
        dry_run_msg "Step 2: Identify cmux workspace [SKIPPED: --skip-cmux]"
        echo ""
        dry_run_msg "Step 3: Close cmux workspace [SKIPPED: --skip-cmux]"
    else
        dry_run_msg "Step 2: Identify cmux workspace"
        echo "     $CMUX_SSH_SCRIPT list-workspaces"
        echo "     Match workspace name: $WORKTREE_NAME"
        echo ""
        dry_run_msg "Step 3: Close cmux workspace"
        echo "     $CMUX_SSH_SCRIPT close-workspace --workspace <workspace_id>"
    fi
    echo ""

    dry_run_msg "Step 4: Cleanup worktree (delegate to cleanup-worktree.sh)"
    cleanup_cmd="$CLEANUP_WORKTREE_SCRIPT $WORKTREE_NAME --repo $REPO"
    if [ "$YES" = true ]; then
        cleanup_cmd="$cleanup_cmd --yes"
    fi
    if [ "$KEEP_BRANCH" = true ]; then
        cleanup_cmd="$cleanup_cmd --keep-branch"
    fi
    if [ "$SKIP_WORKSPACE" = true ]; then
        cleanup_cmd="$cleanup_cmd --skip-workspace"
    fi
    cleanup_cmd="$cleanup_cmd --dry-run"
    if [ "$VERBOSE" = true ]; then
        cleanup_cmd="$cleanup_cmd --verbose"
    fi
    echo "     $cleanup_cmd"

    echo ""
    echo "=== END DRY RUN ==="
    exit 0
fi

##############################################################################
# Section 7: Prerequisite Validation (Step 1)
##############################################################################

log_info "Step 1: Validating prerequisites..."

# Check cleanup-worktree.sh (required)
if [ ! -f "$CLEANUP_WORKTREE_SCRIPT" ]; then
    log_error "cleanup-worktree.sh not found at: $CLEANUP_WORKTREE_SCRIPT"
    log_error "Set CLEANUP_WORKTREE_SCRIPT env var to the correct path."
    exit 2
fi

# Check cmux prerequisites (only if cmux not skipped)
if [ "$SKIP_CMUX" != true ]; then
    if [ ! -f "$CMUX_CHECK_SCRIPT" ]; then
        log_warn "cmux-check.sh not found at: $CMUX_CHECK_SCRIPT"
        log_warn "cmux workspace closure will be skipped"
        SKIP_CMUX=true
    else
        if ! bash "$CMUX_CHECK_SCRIPT" > /dev/null 2>&1; then
            log_warn "cmux prerequisite check failed (cmux-check.sh returned non-zero)"
            log_warn "cmux workspace closure will be skipped"
            SKIP_CMUX=true
        fi
    fi
fi

log_success "Prerequisites validated"

##############################################################################
# Section 8: Identify and Close cmux Workspace (Steps 2-3)
##############################################################################

CMUX_FAILED=false

if [ "$SKIP_CMUX" = true ]; then
    log_info "Steps 2-3: Skipping cmux workspace closure (--skip-cmux)"
else
    # Step 2: Identify cmux workspace
    log_info "Step 2: Identifying cmux workspace for '$WORKTREE_NAME'..."

    ws_list=""
    log_verbose "exec: bash $CMUX_SSH_SCRIPT list-workspaces"
    ws_list=$( bash "$CMUX_SSH_SCRIPT" list-workspaces 2>&1 ) || {
        log_warn "cmux list-workspaces failed"
        CMUX_FAILED=true
    }

    workspace_id=""
    match_count=0

    if [ "$CMUX_FAILED" = false ]; then
        while IFS= read -r line; do
            # Skip empty lines
            if [ -z "$line" ]; then
                continue
            fi
            ws_id=$( echo "$line" | grep -oE 'workspace:[0-9]+' ) || continue
            ws_name=$( echo "$line" | sed -E 's/workspace:[0-9]+ //' | sed 's/ \[selected\]$//' )
            if [ "$ws_name" = "$WORKTREE_NAME" ]; then
                workspace_id="$ws_id"
                match_count=$((match_count + 1))
            fi
        done << WSEOF
$ws_list
WSEOF

        if [ "$match_count" -gt 1 ]; then
            log_warn "Multiple cmux workspaces match '$WORKTREE_NAME' ($match_count found). Skipping close to avoid ambiguity."
            workspace_id=""
        elif [ "$match_count" -eq 0 ]; then
            log_warn "No cmux workspace found matching '$WORKTREE_NAME'. Continuing with worktree cleanup."
            workspace_id=""
        else
            log_success "Found cmux workspace: $workspace_id"
        fi
    fi

    # Step 3: Close cmux workspace
    if [ "$CMUX_FAILED" = false ] && [ -n "$workspace_id" ]; then
        log_info "Step 3: Closing cmux workspace $workspace_id..."
        log_verbose "exec: bash $CMUX_SSH_SCRIPT close-workspace --workspace $workspace_id"
        if bash "$CMUX_SSH_SCRIPT" close-workspace --workspace "$workspace_id" > /dev/null 2>&1; then
            log_success "cmux workspace $workspace_id closed"
        else
            log_warn "Failed to close cmux workspace $workspace_id (non-fatal)"
            CMUX_FAILED=true
        fi
    elif [ "$CMUX_FAILED" = true ]; then
        log_info "Step 3: Skipping cmux workspace closure (list-workspaces failed)"
    else
        log_info "Step 3: Skipping cmux workspace closure (no matching workspace found)"
    fi
fi

##############################################################################
# Section 9: Cleanup Worktree (Step 4)
##############################################################################

log_info "Step 4: Cleaning up worktree (delegate to cleanup-worktree.sh)..."

# Build cleanup-worktree.sh command arguments as an array (prevents word-splitting)
cleanup_args_array=("$WORKTREE_NAME" "--repo" "$REPO")
[ "$YES" = "true" ]            && cleanup_args_array+=("--yes")
[ "$KEEP_BRANCH" = "true" ]    && cleanup_args_array+=("--keep-branch")
[ "$SKIP_WORKSPACE" = "true" ] && cleanup_args_array+=("--skip-workspace")
[ "$VERBOSE" = "true" ]        && cleanup_args_array+=("--verbose")

log_verbose "exec: bash $CLEANUP_WORKTREE_SCRIPT ${cleanup_args_array[*]}"

cleanup_exit=0
bash "$CLEANUP_WORKTREE_SCRIPT" "${cleanup_args_array[@]}" || cleanup_exit=$?

if [ "$cleanup_exit" -eq 5 ]; then
    log_warn "User cancelled worktree cleanup"
    exit 5
elif [ "$cleanup_exit" -ne 0 ]; then
    log_error "cleanup-worktree.sh failed with exit code $cleanup_exit"
    exit 4
fi

log_success "Worktree cleanup completed"

##############################################################################
# Summary
##############################################################################

echo ""
echo "=========================================="
echo "  Worktree Teardown Complete"
echo "=========================================="
echo ""
log_success "Worktree: $WORKTREE_NAME"
log_info "Repository: $REPO"

if [ "$SKIP_CMUX" = true ]; then
    log_info "cmux: Skipped"
elif [ "$CMUX_FAILED" = true ]; then
    log_warn "cmux: Failed (worktree was still cleaned up successfully)"
else
    log_success "cmux: Workspace closed"
fi

echo ""
echo "=========================================="

exit 0
