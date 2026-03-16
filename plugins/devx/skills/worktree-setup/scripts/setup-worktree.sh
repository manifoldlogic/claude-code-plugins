#!/usr/bin/env bash
#
# setup-worktree.sh - Create git worktree with VS Code and cmux workspace setup
#
# Version: 1.0.0
#
# DESCRIPTION:
#   Orchestrates the creation of a git worktree via crewchief CLI, updates the
#   VS Code workspace file, creates a cmux workspace, opens a devcontainer
#   session, navigates to the worktree, and launches claude. This is the
#   primary setup script for the devx plugin's worktree-setup skill.
#
# REQUIREMENTS:
#   - Running inside the devcontainer (container-mode only)
#   - CrewChief CLI (ccwt create) installed
#   - workspace-folder.sh script for VS Code workspace updates
#   - cmux-ssh.sh and cmux-check.sh for terminal session setup (optional)
#
# USAGE:
#   setup-worktree.sh <worktree-name> --repo <repository> [OPTIONS]
#
# POSITIONAL ARGUMENTS:
#   worktree-name               Name for the worktree (typically a ticket ID)
#
# REQUIRED ARGUMENTS:
#   -r, --repo REPO             Repository name
#
# OPTIONAL ARGUMENTS:
#   -b, --branch BRANCH         Base branch (default: main)
#   -w, --workspace FILE        VS Code workspace file path
#   --skip-cmux                 Skip cmux workspace creation (steps 4-7)
#   --skip-workspace            Skip VS Code workspace update (step 3)
#   --dry-run                   Preview planned operations
#   -h, --help                  Show this help message and exit
#
# EXIT CODES:
#   0  - Success (worktree created and environment set up)
#   1  - Usage error (missing required arguments)
#   2  - Prerequisite failure (required tools not found)
#   3  - Unrecognized option
#   4  - Worktree creation failure (ccwt create failed)
#
# EXAMPLES:
#
#   1. Create worktree with full setup
#      $ setup-worktree.sh TICKET-1 --repo crewchief
#
#   2. Create worktree with custom branch
#      $ setup-worktree.sh TICKET-1 --repo crewchief --branch develop
#
#   3. Skip cmux setup (worktree + workspace only)
#      $ setup-worktree.sh TICKET-1 --repo crewchief --skip-cmux
#
#   4. Dry run to preview
#      $ setup-worktree.sh --dry-run TICKET-1 --repo crewchief
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

##############################################################################
# Section 2: Configuration
##############################################################################

# Path defaults (configurable via environment)
CMUX_PLUGIN_DIR="${CMUX_PLUGIN_DIR:-/workspace/repos/claude-code-plugins/claude-code-plugins/plugins/cmux}"
CMUX_SSH_SCRIPT="$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-ssh.sh"
CMUX_CHECK_SCRIPT="$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-check.sh"
WORKSPACE_FOLDER_SCRIPT="${WORKSPACE_FOLDER_SCRIPT:-/workspace/.devcontainer/scripts/workspace-folder.sh}"

# Default values
DEFAULT_BRANCH="main"

# Variables to be set by argument parsing
WORKTREE_NAME=""
REPO=""
BRANCH="$DEFAULT_BRANCH"
WORKSPACE_FILE=""
SKIP_CMUX=false
SKIP_WORKSPACE=false
DRY_RUN=false

##############################################################################
# Section 3: Help Function
##############################################################################

show_help() {
    cat << 'EOF'
Usage: setup-worktree.sh <worktree-name> --repo <repository> [OPTIONS]

Create a git worktree with VS Code and cmux workspace setup.

Orchestrates 7 steps: prerequisite validation, worktree creation, VS Code
workspace update, cmux workspace creation, devcontainer session, navigation,
and claude launch.

POSITIONAL ARGUMENTS:
  worktree-name               Name for the worktree (typically a ticket ID)

REQUIRED:
  -r, --repo REPO             Repository name

OPTIONS:
  -b, --branch BRANCH         Base branch (default: main)
  -w, --workspace FILE        VS Code workspace file path
  --skip-cmux                 Skip cmux workspace creation (steps 4-7)
  --skip-workspace            Skip VS Code workspace update (step 3)
  --dry-run                   Preview planned operations
  -h, --help                  Show this help message and exit

EXIT CODES:
  0   Success (worktree created and environment set up)
  1   Usage error (missing required arguments)
  2   Prerequisite failure (required tools not found)
  3   Unrecognized option
  4   Worktree creation failure

EXAMPLES:
  # Create worktree with full setup
  setup-worktree.sh TICKET-1 --repo crewchief

  # Create worktree with custom branch
  setup-worktree.sh TICKET-1 --repo crewchief --branch develop

  # Skip cmux setup (worktree + workspace only)
  setup-worktree.sh TICKET-1 --repo crewchief --skip-cmux

  # Dry run to preview
  setup-worktree.sh --dry-run TICKET-1 --repo crewchief

  # Skip VS Code workspace update
  setup-worktree.sh TICKET-1 --repo crewchief --skip-workspace

ENVIRONMENT VARIABLES:
  CMUX_PLUGIN_DIR             Path to cmux plugin directory
                              (default: /workspace/repos/claude-code-plugins/claude-code-plugins/plugins/cmux)
  WORKSPACE_FOLDER_SCRIPT     Path to workspace-folder.sh
                              (default: /workspace/.devcontainer/scripts/workspace-folder.sh)
  DEVCONTAINER_NAME           Container name for docker exec
                              (auto-detected via docker ps if not set)

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
        -b|--branch)
            if [ -z "${2:-}" ]; then
                log_error "--branch requires an argument"
                exit 1
            fi
            BRANCH="$2"
            shift 2
            ;;
        -w|--workspace)
            if [ -z "${2:-}" ]; then
                log_error "--workspace requires an argument"
                exit 1
            fi
            WORKSPACE_FILE="$2"
            shift 2
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

# Validate worktree name format
if ! printf '%s' "$WORKTREE_NAME" | grep -qE '^[a-zA-Z0-9][a-zA-Z0-9_-]*$'; then
    log_error "Invalid worktree name: '$WORKTREE_NAME'"
    log_error "Names must start with a letter or digit and contain only letters, digits, hyphens, and underscores."
    exit 1
fi

# Compute worktree path
WORKTREE_PATH="/workspace/repos/$REPO/$WORKTREE_NAME"

##############################################################################
# Section 6: Dry Run Mode
##############################################################################

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "=========================================="
    echo "  DRY RUN - No changes will be made"
    echo "=========================================="
    echo ""

    echo "Resolved parameters:"
    echo "  Worktree name: $WORKTREE_NAME"
    echo "  Repository: $REPO"
    echo "  Base branch: $BRANCH"
    echo "  Worktree path: $WORKTREE_PATH"
    if [ -n "$WORKSPACE_FILE" ]; then
        echo "  Workspace file: $WORKSPACE_FILE"
    else
        echo "  Workspace file: (auto-detect)"
    fi
    echo "  Skip cmux: $SKIP_CMUX"
    echo "  Skip workspace: $SKIP_WORKSPACE"
    echo ""

    echo "Planned operations:"
    echo ""

    dry_run_msg "Step 1: Validate prerequisites"
    echo "     Check: ccwt, workspace-folder.sh, cmux-check.sh"
    echo ""

    dry_run_msg "Step 2: Create worktree"
    echo "     ccwt create $WORKTREE_NAME --repo $REPO --branch $BRANCH"
    echo ""

    if [ "$SKIP_WORKSPACE" = true ]; then
        dry_run_msg "Step 3: Update VS Code workspace: SKIPPED (--skip-workspace)"
    else
        dry_run_msg "Step 3: Update VS Code workspace"
        if [ -n "$WORKSPACE_FILE" ]; then
            echo "     $WORKSPACE_FOLDER_SCRIPT add $WORKTREE_PATH -w $WORKSPACE_FILE"
        else
            echo "     $WORKSPACE_FOLDER_SCRIPT add $WORKTREE_PATH"
        fi
    fi
    echo ""

    if [ "$SKIP_CMUX" = true ]; then
        dry_run_msg "Step 4: Create cmux workspace: SKIPPED (--skip-cmux)"
        echo ""
        dry_run_msg "Step 5: Open devcontainer session: SKIPPED (--skip-cmux)"
        echo ""
        dry_run_msg "Step 6: Navigate to worktree: SKIPPED (--skip-cmux)"
        echo ""
        dry_run_msg "Step 7: Launch claude: SKIPPED (--skip-cmux)"
    else
        dry_run_msg "Step 4: Create cmux workspace"
        echo "     $CMUX_SSH_SCRIPT new-workspace"
        echo "     sleep 0.5"
        echo "     $CMUX_SSH_SCRIPT rename-workspace <workspace_id> $WORKTREE_NAME"
        echo ""

        dry_run_msg "Step 5: Open devcontainer session"
        echo "     Container: <DEVCONTAINER_NAME>"
        echo "     $CMUX_SSH_SCRIPT send <workspace_id> \"docker exec -it <DEVCONTAINER_NAME> /bin/zsh\""
        echo "     $CMUX_SSH_SCRIPT send-key <workspace_id> enter"
        echo "     sleep 2"
        echo ""

        dry_run_msg "Step 6: Navigate to worktree"
        echo "     $CMUX_SSH_SCRIPT send <workspace_id> \"cd $WORKTREE_PATH\""
        echo "     $CMUX_SSH_SCRIPT send-key <workspace_id> enter"
        echo "     sleep 0.5"
        echo ""

        dry_run_msg "Step 7: Launch claude"
        echo "     $CMUX_SSH_SCRIPT send <workspace_id> \"claude\""
        echo "     $CMUX_SSH_SCRIPT send-key <workspace_id> enter"
    fi

    echo ""
    echo "=========================================="
    exit 0
fi

##############################################################################
# Section 7: Prerequisite Validation (Step 1)
##############################################################################

log_info "Step 1: Validating prerequisites..."

# Check ccwt
if ! command -v ccwt > /dev/null 2>&1; then
    log_error "ccwt (crewchief worktree CLI) is required but not found"
    exit 2
fi

# Check workspace-folder.sh (only if workspace update not skipped)
if [ "$SKIP_WORKSPACE" != true ]; then
    if [ ! -f "$WORKSPACE_FOLDER_SCRIPT" ]; then
        log_warn "workspace-folder.sh not found at: $WORKSPACE_FOLDER_SCRIPT"
        log_warn "VS Code workspace update will be skipped"
        SKIP_WORKSPACE=true
    fi
fi

# Check cmux prerequisites (only if cmux not skipped)
if [ "$SKIP_CMUX" != true ]; then
    if [ ! -f "$CMUX_CHECK_SCRIPT" ]; then
        log_warn "cmux-check.sh not found at: $CMUX_CHECK_SCRIPT"
        log_warn "cmux workspace creation will be skipped"
        SKIP_CMUX=true
    else
        if ! bash "$CMUX_CHECK_SCRIPT" > /dev/null 2>&1; then
            log_error "cmux prerequisite check failed (cmux-check.sh returned non-zero)"
            exit 2
        fi
    fi
fi

log_success "Prerequisites validated"

##############################################################################
# Section 8: Create Worktree (Step 2)
##############################################################################

log_info "Step 2: Creating worktree '$WORKTREE_NAME' in repo '$REPO'..."

if ! ccwt create "$WORKTREE_NAME" --repo "$REPO" --branch "$BRANCH"; then
    log_error "Worktree creation failed (ccwt create returned non-zero)"
    exit 4
fi

log_success "Worktree created at $WORKTREE_PATH"

##############################################################################
# Section 9: Update VS Code Workspace (Step 3)
##############################################################################

if [ "$SKIP_WORKSPACE" = true ]; then
    log_info "Step 3: Skipping VS Code workspace update (--skip-workspace)"
else
    log_info "Step 3: Updating VS Code workspace..."

    if [ -n "$WORKSPACE_FILE" ]; then
        ws_result=0
        bash "$WORKSPACE_FOLDER_SCRIPT" add "$WORKTREE_PATH" -w "$WORKSPACE_FILE" || ws_result=$?
    else
        ws_result=0
        bash "$WORKSPACE_FOLDER_SCRIPT" add "$WORKTREE_PATH" || ws_result=$?
    fi

    if [ "$ws_result" -eq 0 ]; then
        log_success "VS Code workspace updated"
    else
        log_warn "Failed to update VS Code workspace (non-fatal)"
    fi
fi

##############################################################################
# Section 10: cmux Workspace Setup (Steps 4-7)
##############################################################################

if [ "$SKIP_CMUX" = true ]; then
    log_info "Step 4-7: Skipping cmux workspace setup (--skip-cmux)"
else
    # Track cmux failure for graceful degradation
    CMUX_FAILED=false

    # Step 4: Create cmux workspace
    log_info "Step 4: Creating cmux workspace..."

    result=""
    result=$( bash "$CMUX_SSH_SCRIPT" new-workspace 2>&1 ) || {
        log_warn "cmux new-workspace failed"
        log_warn "Warning: cmux setup failed. Worktree created at $WORKTREE_PATH. Set up your terminal session manually."
        CMUX_FAILED=true
    }

    if [ "$CMUX_FAILED" = false ]; then
        workspace_id=$( echo "$result" | grep -oE 'workspace:[0-9]+' ) || workspace_id=""

        if [ -z "$workspace_id" ]; then
            log_warn "Could not extract workspace ID from cmux output: $result"
            log_warn "Warning: cmux setup failed. Worktree created at $WORKTREE_PATH. Set up your terminal session manually."
            CMUX_FAILED=true
        else
            log_success "cmux workspace created: $workspace_id"

            sleep 0.5

            # Rename workspace
            bash "$CMUX_SSH_SCRIPT" rename-workspace "$workspace_id" "$WORKTREE_NAME" > /dev/null 2>&1 || {
                log_warn "Failed to rename cmux workspace (non-fatal)"
            }
        fi
    fi

    # Step 5: Open devcontainer session
    if [ "$CMUX_FAILED" = false ]; then
        log_info "Step 5: Opening devcontainer session..."

        # Detect container name
        CONTAINER_NAME="${DEVCONTAINER_NAME:-}"
        if [ -z "$CONTAINER_NAME" ]; then
            CONTAINER_NAME=$( docker ps --filter name=devcontainer --format '{{.Names}}' | head -1 ) || CONTAINER_NAME=""
        fi

        if [ -z "$CONTAINER_NAME" ]; then
            log_warn "Could not detect devcontainer name. Set DEVCONTAINER_NAME env var."
            log_warn "Warning: cmux setup failed. Worktree created at $WORKTREE_PATH. Set up your terminal session manually."
            CMUX_FAILED=true
        else
            bash "$CMUX_SSH_SCRIPT" send "$workspace_id" "docker exec -it $CONTAINER_NAME /bin/zsh" > /dev/null 2>&1 || true
            bash "$CMUX_SSH_SCRIPT" send-key "$workspace_id" enter > /dev/null 2>&1 || true
            sleep 2
            log_success "Devcontainer session opened (container: $CONTAINER_NAME)"
        fi
    fi

    # Step 6: Navigate to worktree
    if [ "$CMUX_FAILED" = false ]; then
        log_info "Step 6: Navigating to worktree..."
        bash "$CMUX_SSH_SCRIPT" send "$workspace_id" "cd $WORKTREE_PATH" > /dev/null 2>&1 || true
        bash "$CMUX_SSH_SCRIPT" send-key "$workspace_id" enter > /dev/null 2>&1 || true
        sleep 0.5
        log_success "Navigated to $WORKTREE_PATH"
    fi

    # Step 7: Launch claude
    if [ "$CMUX_FAILED" = false ]; then
        log_info "Step 7: Launching claude..."
        bash "$CMUX_SSH_SCRIPT" send "$workspace_id" "claude" > /dev/null 2>&1 || true
        bash "$CMUX_SSH_SCRIPT" send-key "$workspace_id" enter > /dev/null 2>&1 || true
        log_success "Claude launched"
    fi

    if [ "$CMUX_FAILED" = true ]; then
        log_info "Steps 5-7: Skipped due to cmux failure"
    fi
fi

##############################################################################
# Summary
##############################################################################

echo ""
echo "=========================================="
echo "  Worktree Setup Complete"
echo "=========================================="
echo ""
log_success "Worktree: $WORKTREE_NAME"
log_info "Repository: $REPO"
log_info "Path: $WORKTREE_PATH"
log_info "Branch: $BRANCH"

if [ "$SKIP_CMUX" = true ]; then
    log_info "cmux: Skipped"
elif [ "${CMUX_FAILED:-false}" = true ]; then
    log_warn "cmux: Failed (worktree was still created successfully)"
else
    log_success "cmux: Workspace ready"
fi

echo ""
echo "=========================================="

exit 0
