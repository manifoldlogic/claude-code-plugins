#!/usr/bin/env bash
#
# Maproom Watch Script
# Continuously monitors and re-indexes a repository using @crewchief/maproom-mcp
#
# Usage:
#   bash watch.sh                    # Watch current directory
#   bash watch.sh /path/to/repo      # Watch specific path
#
# Environment Variables:
#   MAPROOM_EMBEDDING_PROVIDER   - openai, google, or ollama (required)
#   OPENAI_API_KEY       - Required for openai provider
#   GOOGLE_PROJECT_ID    - Required for google provider
#   GOOGLE_APPLICATION_CREDENTIALS - Required for google provider
#   MAPROOM_DATABASE_URL         - PostgreSQL connection (default: postgresql://maproom:maproom@localhost:5432/maproom)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Main execution
main() {
    info "Maproom Repository Watcher"

    # Check for MAPROOM_EMBEDDING_PROVIDER
    if [[ -z "${MAPROOM_EMBEDDING_PROVIDER:-}" ]]; then
        error "MAPROOM_EMBEDDING_PROVIDER not set"
        error "Please set MAPROOM_EMBEDDING_PROVIDER to one of: openai, google, ollama"
        error ""
        error "Examples:"
        error "  MAPROOM_EMBEDDING_PROVIDER=openai bash watch.sh"
        error "  export MAPROOM_EMBEDDING_PROVIDER=ollama && bash watch.sh"
        exit 1
    fi

    info "Using embedding provider: $MAPROOM_EMBEDDING_PROVIDER"

    # Validate provider-specific requirements
    case "$MAPROOM_EMBEDDING_PROVIDER" in
        openai)
            if [[ -z "${OPENAI_API_KEY:-}" ]]; then
                error "OPENAI_API_KEY not set (required for OpenAI provider)"
                exit 1
            fi
            ;;
        google)
            if [[ -z "${GOOGLE_PROJECT_ID:-}" ]]; then
                error "GOOGLE_PROJECT_ID not set (required for Google provider)"
                exit 1
            fi
            if [[ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
                error "GOOGLE_APPLICATION_CREDENTIALS not set (required for Google provider)"
                exit 1
            fi
            ;;
        ollama)
            info "Using local Ollama provider (no API key required)"
            ;;
        *)
            error "Unsupported provider: $MAPROOM_EMBEDDING_PROVIDER"
            error "Supported providers: openai, google, ollama"
            exit 1
            ;;
    esac

    # Parse arguments
    local watch_path="${1:-.}"

    # Convert watch_path to absolute path
    watch_path=$(cd "$watch_path" 2>/dev/null && pwd || echo "$watch_path")

    info "Watching path: $watch_path"

    # Set MAPROOM_DATABASE_URL if not already set
    export MAPROOM_DATABASE_URL="${MAPROOM_DATABASE_URL:-postgresql://maproom:maproom@localhost:5432/maproom}"

    # Check database connectivity (optional)
    if command -v psql &> /dev/null; then
        if psql "$MAPROOM_DATABASE_URL" -c "SELECT 1" &> /dev/null 2>&1; then
            info "Database connection verified"
        else
            warn "Cannot connect to database at: $MAPROOM_DATABASE_URL"
            warn "Watch will continue, but ensure database is running for indexing to work"
        fi
    fi

    # Run watch using npx
    info "Starting watch mode with @crewchief/maproom-mcp..."
    info "File changes will be automatically re-indexed"
    info "Press Ctrl+C to stop"
    npx @crewchief/maproom-mcp watch "$watch_path"

    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        info "Watch stopped"
    else
        error "Watch failed with exit code: $exit_code"
        exit $exit_code
    fi
}

# Trap Ctrl+C for graceful shutdown
trap 'echo ""; info "Stopping watch..."; exit 0' INT TERM

# Execute main function
main "$@"
