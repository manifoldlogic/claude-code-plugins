#!/usr/bin/env bash
#
# setup-worktree.sh - Create git worktree with VS Code and cmux workspace setup
#
# Version: 2.0.0
#
# DESCRIPTION:
#   Orchestrates the creation of a git worktree via crewchief CLI, updates the
#   VS Code workspace file, creates a cmux workspace, opens a devcontainer
#   session, navigates to the worktree, and launches claude. This is the
#   primary setup script for the devx plugin's worktree-setup skill.
#
# REQUIREMENTS:
#   - Running inside the devcontainer (container-mode only)
#   - CrewChief CLI (crewchief worktree create) installed
#   - workspace-folder.sh script for VS Code workspace updates
#   - cmux-ssh.sh and cmux-check.sh for terminal session setup (optional)
#
# USAGE:
#   setup-worktree.sh <worktree-name> [OPTIONS]
#
# POSITIONAL ARGUMENTS:
#   worktree-name               Name for the worktree (typically a ticket ID)
#
# OPTIONAL ARGUMENTS:
#   -b, --branch BRANCH         Base branch (default: main)
#   -w, --workspace FILE        VS Code workspace file path
#   --skip-cmux                 Skip cmux workspace creation (steps 4-7)
#   --skip-workspace            Skip VS Code workspace update (step 3)
#   --dry-run                   Preview planned operations
#   --verbose                   Show cmux-ssh.sh invocations and output
#   -h, --help                  Show this help message and exit
#
# EXIT CODES:
#   0  - Success (worktree created and environment set up)
#   1  - Usage error (missing required arguments)
#   2  - Prerequisite failure (required tools not found)
#   3  - Unrecognized option
#   4  - Worktree creation failure (crewchief worktree create failed)
#
# NOTE:
#   Must be run from within a git repository.
#
# EXAMPLES:
#
#   1. Create worktree with full setup
#      $ setup-worktree.sh TICKET-1
#
#   2. Create worktree with custom branch
#      $ setup-worktree.sh TICKET-1 --branch develop
#
#   3. Skip cmux setup (worktree + workspace only)
#      $ setup-worktree.sh TICKET-1 --skip-cmux
#
#   4. Dry run to preview
#      $ setup-worktree.sh --dry-run TICKET-1
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
CMUX_WAIT_SCRIPT="$CMUX_PLUGIN_DIR/skills/terminal-management/scripts/cmux-wait.sh"
WORKSPACE_FOLDER_SCRIPT="${WORKSPACE_FOLDER_SCRIPT:-/workspace/.devcontainer/scripts/workspace-folder.sh}"

# Default values
DEFAULT_BRANCH="main"

# Variables to be set by argument parsing
WORKTREE_NAME=""
BRANCH="$DEFAULT_BRANCH"
WORKSPACE_FILE=""
SKIP_CMUX=false
SKIP_WORKSPACE=false
DRY_RUN=false
VERBOSE=false

##############################################################################
# Section 3: Help Function
##############################################################################

show_help() {
    cat << 'EOF'
Usage: setup-worktree.sh <worktree-name> [OPTIONS]

Create a git worktree with VS Code and cmux workspace setup.

Must be run from within a git repository. The repository is detected
automatically using git rev-parse --show-toplevel.

Orchestrates 7 steps: prerequisite validation, worktree creation, VS Code
workspace update, cmux workspace creation, devcontainer session, navigation,
and claude launch.

POSITIONAL ARGUMENTS:
  worktree-name               Name for the worktree (typically a ticket ID)

OPTIONS:
  -b, --branch BRANCH         Base branch (default: main)
  -w, --workspace FILE        VS Code workspace file path
  --skip-cmux                 Skip cmux workspace creation (steps 4-7)
  --skip-workspace            Skip VS Code workspace update (step 3)
  --dry-run                   Preview planned operations
  --verbose                   Show cmux-ssh.sh invocations and output
  -h, --help                  Show this help message and exit

EXIT CODES:
  0   Success (worktree created and environment set up)
  1   Usage error (missing required arguments)
  2   Prerequisite failure (required tools not found)
  3   Unrecognized option
  4   Worktree creation failure

EXAMPLES:
  # Create worktree with full setup (run from inside a git repo)
  setup-worktree.sh TICKET-1

  # Create worktree with custom branch
  setup-worktree.sh TICKET-1 --branch develop

  # Skip cmux setup (worktree + workspace only)
  setup-worktree.sh TICKET-1 --skip-cmux

  # Dry run to preview
  setup-worktree.sh --dry-run TICKET-1

  # Skip VS Code workspace update
  setup-worktree.sh TICKET-1 --skip-workspace

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

# Validate worktree name format
if ! printf '%s' "$WORKTREE_NAME" | grep -qE '^[a-zA-Z0-9][a-zA-Z0-9_-]*$'; then
    log_error "Invalid worktree name: '$WORKTREE_NAME'"
    log_error "Names must start with a letter or digit and contain only letters, digits, hyphens, and underscores."
    exit 1
fi

# Detect git repository root
GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
    log_error "Not inside a git repository. Run this script from within a git repo."
    exit 1
}
REPO=$(basename "$GIT_ROOT")
WORKTREE_PATH="$(dirname "$GIT_ROOT")/$WORKTREE_NAME"

# Derive workspace entry name per workspace-file-spec naming convention
# The wrapper directory name (parent of GIT_ROOT) is the repo name for display
REPO_WRAPPER_NAME=$(basename "$(dirname "$GIT_ROOT")")
WORKSPACE_ENTRY_NAME="$REPO_WRAPPER_NAME ⛙ $WORKTREE_NAME"

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
    echo "  Git root: $GIT_ROOT"
    echo "  Base branch: $BRANCH"
    echo "  Worktree path: $WORKTREE_PATH"
    if [ -n "$WORKSPACE_FILE" ]; then
        echo "  Workspace file: $WORKSPACE_FILE"
    else
        echo "  Workspace file: (auto-detect)"
    fi
    echo "  Skip cmux: $SKIP_CMUX"
    echo "  Skip workspace: $SKIP_WORKSPACE"
    echo "  Verbose: $VERBOSE"
    echo ""

    echo "Planned operations:"
    echo ""

    dry_run_msg "Step 1: Validate prerequisites"
    echo "     Check: crewchief, workspace-folder.sh, cmux-check.sh"
    echo ""

    dry_run_msg "Step 2: Create worktree"
    echo "     (cd $GIT_ROOT && crewchief worktree create $WORKTREE_NAME --branch $BRANCH)"
    echo ""

    if [ "$SKIP_WORKSPACE" = true ]; then
        dry_run_msg "Step 3: Update VS Code workspace: SKIPPED (--skip-workspace)"
    else
        dry_run_msg "Step 3: Update VS Code workspace"
        if [ -n "$WORKSPACE_FILE" ]; then
            echo "     $WORKSPACE_FOLDER_SCRIPT add $WORKTREE_PATH --name \"$WORKSPACE_ENTRY_NAME\" -w $WORKSPACE_FILE"
        else
            echo "     $WORKSPACE_FOLDER_SCRIPT add $WORKTREE_PATH --name \"$WORKSPACE_ENTRY_NAME\""
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
        echo "     [cmux] Wait for workspace readiness (polling)"
        echo "     $CMUX_SSH_SCRIPT rename-workspace --workspace <workspace_id> $WORKTREE_NAME"
        echo ""

        dry_run_msg "Step 5: Open devcontainer session"
        echo "     Container: <DEVCONTAINER_NAME>"
        echo "     $CMUX_SSH_SCRIPT send --workspace <workspace_id> \"docker exec -it <DEVCONTAINER_NAME> /bin/zsh\""
        echo "     $CMUX_SSH_SCRIPT send-key --workspace <workspace_id> enter"
        echo "     [cmux] Wait for shell prompt readiness (polling)"
        echo ""

        dry_run_msg "Step 6: Navigate to worktree"
        echo "     $CMUX_SSH_SCRIPT send --workspace <workspace_id> \"cd $WORKTREE_PATH\""
        echo "     $CMUX_SSH_SCRIPT send-key --workspace <workspace_id> enter"
        echo "     [cmux] Wait for shell prompt readiness (polling)"
        echo ""

        dry_run_msg "Step 7: Launch claude"
        echo "     $CMUX_SSH_SCRIPT send --workspace <workspace_id> \"claude\""
        echo "     $CMUX_SSH_SCRIPT send-key --workspace <workspace_id> enter"
    fi

    echo ""
    echo "=========================================="
    exit 0
fi

##############################################################################
# Section 7: Prerequisite Validation (Step 1)
##############################################################################

log_info "Step 1: Validating prerequisites..."

# Check crewchief
if ! command -v crewchief > /dev/null 2>&1; then
    log_error "crewchief CLI is required but not found"
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

if ! (cd "$GIT_ROOT" && crewchief worktree create "$WORKTREE_NAME" --branch "$BRANCH"); then
    log_error "Worktree creation failed (crewchief worktree create returned non-zero)"
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
        bash "$WORKSPACE_FOLDER_SCRIPT" add "$WORKTREE_PATH" --name "$WORKSPACE_ENTRY_NAME" -w "$WORKSPACE_FILE" || ws_result=$?
    else
        ws_result=0
        bash "$WORKSPACE_FOLDER_SCRIPT" add "$WORKTREE_PATH" --name "$WORKSPACE_ENTRY_NAME" || ws_result=$?
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
    # Source cmux-wait.sh for polling functions
    if [ -f "$CMUX_WAIT_SCRIPT" ]; then
        source "$CMUX_WAIT_SCRIPT"
    else
        log_warn "cmux-wait.sh not found, falling back to sleep-based timing"
        cmux_wait_workspace() { sleep 0.5; return 0; }
        # Fallback stub: conservative 2s wait; Step 6 originally slept 0.5s
        cmux_wait_prompt() { sleep 2; return 0; }
    fi

    # Track cmux failure for graceful degradation
    CMUX_FAILED=false

    # Step 4: Create cmux workspace
    log_info "Step 4: Creating cmux workspace..."

    result=""
    log_verbose "exec: bash $CMUX_SSH_SCRIPT new-workspace"
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

            cmux_wait_workspace "$workspace_id" "$CMUX_SSH_SCRIPT" || log_warn "cmux workspace readiness timeout at Step 4, continuing"

            # Rename workspace
            log_verbose "exec: bash $CMUX_SSH_SCRIPT rename-workspace --workspace $workspace_id $WORKTREE_NAME"
            bash "$CMUX_SSH_SCRIPT" rename-workspace --workspace "$workspace_id" "$WORKTREE_NAME" > /dev/null 2>&1 || {
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
            CONTAINER_NAME=$( docker ps --filter name=devcontainer --format '{{.Names}}' 2>/dev/null | head -1 ) || true
            if [ -z "$CONTAINER_NAME" ]; then
                if ! docker ps > /dev/null 2>&1; then
                    log_verbose "docker ps failed (permission denied or docker unavailable)"
                    log_warn "Docker container detection failed. Set DEVCONTAINER_NAME env var."
                else
                    log_warn "Could not detect devcontainer name. Set DEVCONTAINER_NAME env var."
                fi
                CMUX_FAILED=true
            fi
        fi

        if [ -z "$CONTAINER_NAME" ]; then
            log_warn "Warning: cmux setup failed. Worktree created at $WORKTREE_PATH. Set up your terminal session manually."
        else
            log_verbose "exec: bash $CMUX_SSH_SCRIPT send --workspace $workspace_id \"docker exec -it $CONTAINER_NAME /bin/zsh\""
            step5_ok=true
            if ! bash "$CMUX_SSH_SCRIPT" send --workspace "$workspace_id" "docker exec -it $CONTAINER_NAME /bin/zsh" > /dev/null 2>&1; then
                log_warn "Failed to send docker exec command to cmux workspace"
                step5_ok=false
            fi
            log_verbose "exec: bash $CMUX_SSH_SCRIPT send-key --workspace $workspace_id enter"
            if [ "$step5_ok" = true ] && ! bash "$CMUX_SSH_SCRIPT" send-key --workspace "$workspace_id" enter > /dev/null 2>&1; then
                log_warn "Failed to send enter keypress to cmux workspace"
                step5_ok=false
            fi
            if [ "$step5_ok" = true ]; then
                cmux_wait_prompt "$workspace_id" "$CMUX_SSH_SCRIPT" || log_warn "cmux prompt readiness timeout at Step 5, continuing"
                log_success "Devcontainer session opened (container: $CONTAINER_NAME)"
            else
                CMUX_FAILED=true
            fi
        fi
    fi

    # Step 6: Navigate to worktree
    if [ "$CMUX_FAILED" = false ]; then
        log_info "Step 6: Navigating to worktree..."
        step6_ok=true
        log_verbose "exec: bash $CMUX_SSH_SCRIPT send --workspace $workspace_id \"cd $WORKTREE_PATH\""
        if ! bash "$CMUX_SSH_SCRIPT" send --workspace "$workspace_id" "cd $WORKTREE_PATH" > /dev/null 2>&1; then
            log_warn "Failed to send cd command to cmux workspace"
            step6_ok=false
        fi
        log_verbose "exec: bash $CMUX_SSH_SCRIPT send-key --workspace $workspace_id enter"
        if [ "$step6_ok" = true ] && ! bash "$CMUX_SSH_SCRIPT" send-key --workspace "$workspace_id" enter > /dev/null 2>&1; then
            log_warn "Failed to send enter keypress to cmux workspace"
            step6_ok=false
        fi
        if [ "$step6_ok" = true ]; then
            cmux_wait_prompt "$workspace_id" "$CMUX_SSH_SCRIPT" || log_warn "cmux prompt readiness timeout at Step 6, continuing"
            log_success "Navigated to $WORKTREE_PATH"
        else
            CMUX_FAILED=true
        fi
    fi

    # Step 7: Launch claude
    if [ "$CMUX_FAILED" = false ]; then
        log_info "Step 7: Launching claude..."
        step7_ok=true
        log_verbose "exec: bash $CMUX_SSH_SCRIPT send --workspace $workspace_id \"claude\""
        if ! bash "$CMUX_SSH_SCRIPT" send --workspace "$workspace_id" "claude" > /dev/null 2>&1; then
            log_warn "Failed to send claude command to cmux workspace"
            step7_ok=false
        fi
        log_verbose "exec: bash $CMUX_SSH_SCRIPT send-key --workspace $workspace_id enter"
        if [ "$step7_ok" = true ] && ! bash "$CMUX_SSH_SCRIPT" send-key --workspace "$workspace_id" enter > /dev/null 2>&1; then
            log_warn "Failed to send enter keypress to cmux workspace"
            step7_ok=false
        fi
        if [ "$step7_ok" = true ]; then
            log_success "Claude launched"
        else
            CMUX_FAILED=true
        fi
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
    log_info "cmux workspace: $REPO $WORKTREE_NAME"
fi

echo ""
echo "=========================================="

exit 0
