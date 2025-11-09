#!/usr/bin/env bash
#
# Maproom Scan Script
# Indexes a repository for semantic search
#
# Usage:
#   bash scan.sh                    # Scan current directory
#   bash scan.sh /path/to/repo      # Scan specific path
#   bash scan.sh /path/to/repo main # Scan with specific worktree name

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect platform
detect_platform() {
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    local arch=$(uname -m)

    case "$os" in
        darwin)
            case "$arch" in
                arm64) echo "darwin-arm64" ;;
                x86_64) echo "darwin-x64" ;;
                *) error "Unsupported architecture: $arch"; exit 1 ;;
            esac
            ;;
        linux)
            case "$arch" in
                x86_64) echo "linux-x64" ;;
                aarch64|arm64) echo "linux-arm64" ;;
                *) error "Unsupported architecture: $arch"; exit 1 ;;
            esac
            ;;
        mingw*|msys*|cygwin*)
            echo "win32-x64"
            ;;
        *)
            error "Unsupported operating system: $os"
            exit 1
            ;;
    esac
}

# Find workspace root (where .git directory is)
find_workspace_root() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -d "$dir/.git" ]]; then
            echo "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    error "Not in a git repository"
    exit 1
}

# Main execution
main() {
    info "Maproom Repository Scanner"

    # Get workspace root
    local workspace_root=$(find_workspace_root)
    info "Workspace root: $workspace_root"

    # Detect platform and find binary
    local platform=$(detect_platform)
    local binary_path="$workspace_root/packages/cli/bin/$platform/crewchief-maproom"

    if [[ ! -x "$binary_path" ]]; then
        error "Maproom binary not found at: $binary_path"
        error "Please ensure the binary is built and available"
        exit 1
    fi

    info "Using binary: $binary_path"

    # Parse arguments
    local scan_path="${1:-$PWD}"
    local worktree="${2:-}"

    # Convert scan_path to absolute path
    scan_path=$(cd "$scan_path" 2>/dev/null && pwd || echo "$scan_path")

    info "Scanning path: $scan_path"
    [[ -n "$worktree" ]] && info "Worktree: $worktree"

    # Check database connectivity
    if ! command -v psql &> /dev/null; then
        warn "psql not found, skipping database connectivity check"
    else
        local db_url="${DATABASE_URL:-postgresql://maproom:maproom@maproom-postgres:5432/maproom}"
        if ! psql "$db_url" -c "SELECT 1" &> /dev/null; then
            error "Cannot connect to database at: $db_url"
            error "Please ensure PostgreSQL is running (docker compose up -d)"
            exit 1
        fi
        info "Database connection verified"
    fi

    # Run scan
    info "Starting scan..."
    if [[ -n "$worktree" ]]; then
        "$binary_path" scan --path "$scan_path" --worktree "$worktree"
    else
        "$binary_path" scan --path "$scan_path"
    fi

    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        info "Scan completed successfully"
    else
        error "Scan failed with exit code: $exit_code"
        exit $exit_code
    fi
}

# Execute main function
main "$@"
