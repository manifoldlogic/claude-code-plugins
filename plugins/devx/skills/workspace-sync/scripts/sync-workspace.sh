#!/usr/bin/env bash
#
# sync-workspace.sh - Reconcile workspace.code-workspace with repos on disk
#
# Version: 1.0.0
#
# DESCRIPTION:
#   Scans /workspace/repos/ and produces a correct workspace.code-workspace
#   file that matches the workspace-file-spec. Detects flat-clone and
#   worktree-managed repos, applies naming conventions, enforces ordering,
#   removes stale entries, and adds missing ones.
#
# NAMING CONVENTIONS:
#   devcontainer                          (always first)
#   <repo-name> | main                   (main branch entry)
#   <repo-name> ⛙ <WORKTREE-NAME>       (worktree entry, U+26D9)
#
# REQUIREMENTS:
#   - jq (JSON processor)
#   - Valid workspace file (or --check/--dry-run with nonexistent file)
#
# USAGE:
#   sync-workspace.sh [OPTIONS]
#
# OPTIONS:
#   -w, --workspace FILE    Path to workspace file (default: /workspace/workspace.code-workspace)
#   -r, --repos-dir DIR     Path to repos directory (default: /workspace/repos)
#   --dry-run               Show what would change, do not modify
#   --check                 Exit 0 if in-sync, exit 1 if drift detected
#   --verbose               Show detailed scan output
#   -h, --help              Show help
#
# EXIT CODES:
#   0 - Success (or in-sync for --check)
#   1 - Drift detected (--check mode only)
#   2 - Prerequisites missing (jq, workspace file)
#   3 - Invalid arguments
#

set -euo pipefail

##############################################################################
# Configuration
##############################################################################

DEFAULT_WORKSPACE="/workspace/workspace.code-workspace"
DEFAULT_REPOS_DIR="/workspace/repos"

WORKSPACE_FILE=""
REPOS_DIR=""
DRY_RUN=false
CHECK_MODE=false
VERBOSE=false

# Unicode branch symbol (U+26D9)
BRANCH_SYMBOL="⛙"

##############################################################################
# Logging
##############################################################################

log_info() { printf '\033[0;34m[INFO]\033[0m %s\n' "$*" >&2; }
log_warn() { printf '\033[0;33m[WARN]\033[0m %s\n' "$*" >&2; }
log_error() { printf '\033[0;31m[ERROR]\033[0m %s\n' "$*" >&2; }
log_success() { printf '\033[0;32m[OK]\033[0m %s\n' "$*" >&2; }
log_verbose() {
    if [ "$VERBOSE" = true ]; then
        printf '\033[0;36m[VERBOSE]\033[0m %s\n' "$*" >&2
    fi
}
log_dry() { printf '\033[0;35m[DRY-RUN]\033[0m %s\n' "$*" >&2; }

##############################################################################
# Help
##############################################################################

show_help() {
    cat << 'EOF'
Usage: sync-workspace.sh [OPTIONS]

Reconcile workspace.code-workspace with the repos directory on disk.

Scans repos/ for git repositories and worktrees, generates correct workspace
entries with naming conventions per workspace-file-spec, and updates the
workspace file.

OPTIONS:
  -w, --workspace FILE    Path to workspace file
                          (default: /workspace/workspace.code-workspace)
  -r, --repos-dir DIR     Path to repos directory
                          (default: /workspace/repos)
  --dry-run               Show what would change, do not modify
  --check                 Exit 0 if in-sync, exit 1 if drift detected
  --verbose               Show detailed scan output
  -h, --help              Show this help message

EXIT CODES:
  0   Success (or in-sync for --check)
  1   Drift detected (--check mode only)
  2   Prerequisites missing
  3   Invalid arguments

NAMING CONVENTIONS:
  devcontainer                        Always first entry
  <repo-name> | main                  Main branch of a repo
  <repo-name> ⛙ <WORKTREE-NAME>      Git worktree (U+26D9 separator)

EXAMPLES:
  # Preview changes without modifying
  sync-workspace.sh --dry-run

  # Check if workspace is in-sync (for CI/hooks)
  sync-workspace.sh --check

  # Sync with verbose output
  sync-workspace.sh --verbose

  # Use custom paths
  sync-workspace.sh -w /path/to/workspace.code-workspace -r /path/to/repos

EOF
}

##############################################################################
# Argument Parsing
##############################################################################

while [ $# -gt 0 ]; do
    case "$1" in
        -w|--workspace)
            if [ -z "${2:-}" ]; then
                log_error "--workspace requires an argument"
                exit 3
            fi
            WORKSPACE_FILE="$2"
            shift 2
            ;;
        -r|--repos-dir)
            if [ -z "${2:-}" ]; then
                log_error "--repos-dir requires an argument"
                exit 3
            fi
            REPOS_DIR="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --check)
            CHECK_MODE=true
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
            log_error "Unexpected argument: $1"
            exit 3
            ;;
    esac
done

# Apply defaults
WORKSPACE_FILE="${WORKSPACE_FILE:-$DEFAULT_WORKSPACE}"
REPOS_DIR="${REPOS_DIR:-$DEFAULT_REPOS_DIR}"

##############################################################################
# Prerequisites
##############################################################################

if ! command -v jq > /dev/null 2>&1; then
    log_error "jq is required but not installed"
    exit 2
fi

if [ ! -f "$WORKSPACE_FILE" ]; then
    log_error "Workspace file not found: $WORKSPACE_FILE"
    exit 2
fi

if ! jq empty "$WORKSPACE_FILE" > /dev/null 2>&1; then
    log_error "Workspace file contains invalid JSON: $WORKSPACE_FILE"
    exit 2
fi

if [ ! -d "$REPOS_DIR" ]; then
    log_error "Repos directory not found: $REPOS_DIR"
    exit 2
fi

##############################################################################
# Scan Phase: Build desired entries
##############################################################################

# Temporary file to collect entries (name\tpath per line)
ENTRIES_FILE=$(mktemp)
trap 'rm -f "$ENTRIES_FILE" "${ENTRIES_FILE}.sorted" "${WORKSPACE_FILE}.sync-tmp" "${WORKSPACE_FILE}.sync-bak"' EXIT

log_verbose "Scanning repos directory: $REPOS_DIR"

# Compute the relative prefix from workspace file dir to repos dir
WORKSPACE_DIR=$(dirname "$WORKSPACE_FILE")
if command -v realpath > /dev/null 2>&1; then
    REPOS_REL=$(realpath --relative-to="$WORKSPACE_DIR" "$REPOS_DIR")
else
    # Fallback: assume standard layout
    REPOS_REL="repos"
fi

for entry_path in "$REPOS_DIR"/*/; do
    [ -d "$entry_path" ] || continue
    entry_name=$(basename "$entry_path")

    # Skip hidden directories
    case "$entry_name" in
        .*) log_verbose "Skipping hidden dir: $entry_name"; continue ;;
    esac

    if [ -d "$entry_path/.git" ]; then
        # FLAT CLONE: .git/ directory directly in entry
        log_verbose "Flat clone: $entry_name"
        printf '%s\t%s\n' "$entry_name | main" "$REPOS_REL/$entry_name" >> "$ENTRIES_FILE"

    elif [ -f "$entry_path/.git" ]; then
        # Worktree at top level — unusual, skip
        log_verbose "Skipping top-level worktree: $entry_name"
        continue

    else
        # WRAPPER DIRECTORY: scan children
        found_git=false

        for child_path in "$entry_path"/*/; do
            [ -d "$child_path" ] || continue
            child_name=$(basename "$child_path")

            # Skip hidden directories inside wrappers
            case "$child_name" in
                .*) log_verbose "Skipping hidden child: $entry_name/$child_name"; continue ;;
            esac

            if [ -d "$child_path/.git" ]; then
                # Main clone
                log_verbose "Wrapper main: $entry_name/$child_name"
                printf '%s\t%s\n' "$entry_name | main" "$REPOS_REL/$entry_name/$child_name" >> "$ENTRIES_FILE"
                found_git=true
            elif [ -f "$child_path/.git" ]; then
                # Worktree
                log_verbose "Wrapper worktree: $entry_name/$child_name"
                printf '%s\t%s\n' "$entry_name $BRANCH_SYMBOL $child_name" "$REPOS_REL/$entry_name/$child_name" >> "$ENTRIES_FILE"
                found_git=true
            else
                log_verbose "Skipping non-git child: $entry_name/$child_name"
            fi
        done

        if [ "$found_git" = false ]; then
            log_verbose "Skipping wrapper with no git children: $entry_name"
        fi
    fi
done

# Sort entries case-insensitively by name (first column)
LC_ALL=C sort -f -t "$(printf '\t')" -k1,1 "$ENTRIES_FILE" > "${ENTRIES_FILE}.sorted"

##############################################################################
# Build desired JSON
##############################################################################

# Start with devcontainer entry, then sorted repo entries
DESIRED_JSON=$(
    {
        # devcontainer entry first
        printf '%s\t%s\n' "devcontainer" "."
        # Then sorted entries
        cat "${ENTRIES_FILE}.sorted"
    } | jq -R -s '
        [
            split("\n")[] |
            select(length > 0) |
            split("\t") |
            { "name": .[0], "path": .[1] }
        ]
    '
)

##############################################################################
# Read current state
##############################################################################

CURRENT_FOLDERS=$(jq '.folders // []' "$WORKSPACE_FILE")
CURRENT_SETTINGS=$(jq '.settings // {}' "$WORKSPACE_FILE")

##############################################################################
# Compare Phase
##############################################################################

# Normalize both to sorted JSON for comparison
DESIRED_NORMALIZED=$(echo "$DESIRED_JSON" | jq -S '.')
CURRENT_NORMALIZED=$(echo "$CURRENT_FOLDERS" | jq -S '.')

if [ "$DESIRED_NORMALIZED" = "$CURRENT_NORMALIZED" ]; then
    # In sync
    if [ "$CHECK_MODE" = true ]; then
        exit 0
    elif [ "$DRY_RUN" = true ]; then
        log_success "Workspace file is already in sync"
        exit 0
    else
        log_success "Workspace file is already in sync — no changes needed"
        exit 0
    fi
fi

# Compute differences for reporting
DESIRED_NAMES=$(echo "$DESIRED_JSON" | jq -r '.[].name' | sort -f)
CURRENT_NAMES=$(echo "$CURRENT_FOLDERS" | jq -r '.[].name' | sort -f)

ADDED=$(comm -23 <(echo "$DESIRED_NAMES") <(echo "$CURRENT_NAMES"))
REMOVED=$(comm -13 <(echo "$DESIRED_NAMES") <(echo "$CURRENT_NAMES"))
# Entries present in both but with different paths or different ordering
COMMON=$(comm -12 <(echo "$DESIRED_NAMES") <(echo "$CURRENT_NAMES"))

# Count path mismatches among common entries
PATH_MISMATCHES=""
while IFS= read -r name; do
    [ -z "$name" ] && continue
    desired_path=$(echo "$DESIRED_JSON" | jq -r --arg n "$name" '.[] | select(.name == $n) | .path')
    current_path=$(echo "$CURRENT_FOLDERS" | jq -r --arg n "$name" '.[] | select(.name == $n) | .path')
    if [ "$desired_path" != "$current_path" ]; then
        PATH_MISMATCHES="${PATH_MISMATCHES}  $name: $current_path -> $desired_path\n"
    fi
done <<< "$COMMON"

# Check ordering drift
DESIRED_ORDER=$(echo "$DESIRED_JSON" | jq -r '.[].name')
CURRENT_ORDER=$(echo "$CURRENT_FOLDERS" | jq -r '.[].name')
ORDER_DRIFT=false
if [ "$DESIRED_ORDER" != "$CURRENT_ORDER" ]; then
    ORDER_DRIFT=true
fi

##############################################################################
# Output Phase
##############################################################################

if [ "$CHECK_MODE" = true ]; then
    # Report drift to stderr and exit 1
    log_warn "Workspace file is out of sync"
    if [ -n "$ADDED" ]; then
        echo "Missing entries:" >&2
        echo "$ADDED" | while IFS= read -r name; do
            [ -n "$name" ] && echo "  + $name" >&2
        done
    fi
    if [ -n "$REMOVED" ]; then
        echo "Stale entries:" >&2
        echo "$REMOVED" | while IFS= read -r name; do
            [ -n "$name" ] && echo "  - $name" >&2
        done
    fi
    if [ -n "$PATH_MISMATCHES" ]; then
        echo "Path mismatches:" >&2
        printf '%b' "$PATH_MISMATCHES" >&2
    fi
    if [ "$ORDER_DRIFT" = true ]; then
        echo "Ordering drift detected" >&2
    fi
    exit 1
fi

if [ "$DRY_RUN" = true ]; then
    log_info "Workspace file needs updating:"
    echo "" >&2
    if [ -n "$ADDED" ]; then
        echo "Entries to add:" >&2
        echo "$ADDED" | while IFS= read -r name; do
            if [ -n "$name" ]; then
                path=$(echo "$DESIRED_JSON" | jq -r --arg n "$name" '.[] | select(.name == $n) | .path')
                echo "  + $name  ($path)" >&2
            fi
        done
        echo "" >&2
    fi
    if [ -n "$REMOVED" ]; then
        echo "Entries to remove:" >&2
        echo "$REMOVED" | while IFS= read -r name; do
            if [ -n "$name" ]; then
                path=$(echo "$CURRENT_FOLDERS" | jq -r --arg n "$name" '.[] | select(.name == $n) | .path')
                echo "  - $name  ($path)" >&2
            fi
        done
        echo "" >&2
    fi
    if [ -n "$PATH_MISMATCHES" ]; then
        echo "Path corrections:" >&2
        printf '%b' "$PATH_MISMATCHES" >&2
        echo "" >&2
    fi
    if [ "$ORDER_DRIFT" = true ]; then
        echo "Ordering will be corrected (devcontainer first, then alphabetical)" >&2
        echo "" >&2
    fi
    exit 0
fi

# Default mode: write the workspace file
log_info "Updating workspace file..."

# Create backup
cp "$WORKSPACE_FILE" "${WORKSPACE_FILE}.sync-bak" || {
    log_error "Failed to create backup"
    exit 2
}

# Build complete workspace JSON preserving settings
FULL_JSON=$(jq -n \
    --argjson folders "$DESIRED_JSON" \
    --argjson settings "$CURRENT_SETTINGS" \
    '{ folders: $folders, settings: $settings }')

# Write to temp file
echo "$FULL_JSON" | jq '.' > "${WORKSPACE_FILE}.sync-tmp" || {
    log_error "Failed to write temp file"
    cp "${WORKSPACE_FILE}.sync-bak" "$WORKSPACE_FILE" 2>/dev/null
    exit 2
}

# Atomic move
mv "${WORKSPACE_FILE}.sync-tmp" "$WORKSPACE_FILE" || {
    log_error "Failed to update workspace file"
    cp "${WORKSPACE_FILE}.sync-bak" "$WORKSPACE_FILE" 2>/dev/null
    exit 2
}

# Cleanup backup
rm -f "${WORKSPACE_FILE}.sync-bak"

# Report what changed
if [ -n "$ADDED" ]; then
    echo "$ADDED" | while IFS= read -r name; do
        [ -n "$name" ] && log_success "Added: $name"
    done
fi
if [ -n "$REMOVED" ]; then
    echo "$REMOVED" | while IFS= read -r name; do
        [ -n "$name" ] && log_success "Removed: $name"
    done
fi
if [ -n "$PATH_MISMATCHES" ]; then
    log_success "Corrected path mismatches"
fi
if [ "$ORDER_DRIFT" = true ]; then
    log_success "Corrected entry ordering"
fi

log_success "Workspace file updated successfully"
exit 0
