#!/usr/bin/env bash
#
# Maproom Scan Script
# Indexes a repository for semantic search using @crewchief/maproom-mcp
#
# Usage:
#   bash scan.sh                    # Scan current directory
#   bash scan.sh /path/to/repo      # Scan specific path
#
# Environment Variables:
#   EMBEDDING_PROVIDER   - openai, google, or ollama (required)
#   OPENAI_API_KEY       - Required for openai provider
#   GOOGLE_PROJECT_ID    - Required for google provider
#   GOOGLE_APPLICATION_CREDENTIALS - Required for google provider
#   DATABASE_URL         - PostgreSQL connection (default: postgresql://maproom:maproom@localhost:5432/maproom)

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

# Main execution
main() {
    info "Maproom Repository Scanner"

    # Check for EMBEDDING_PROVIDER
    if [[ -z "${EMBEDDING_PROVIDER:-}" ]]; then
        error "EMBEDDING_PROVIDER not set"
        error "Please set EMBEDDING_PROVIDER to one of: openai, google, ollama"
        error ""
        error "Examples:"
        error "  EMBEDDING_PROVIDER=openai bash scan.sh"
        error "  export EMBEDDING_PROVIDER=ollama && bash scan.sh"
        exit 1
    fi

    info "Using embedding provider: $EMBEDDING_PROVIDER"

    # Validate provider-specific requirements
    case "$EMBEDDING_PROVIDER" in
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
            error "Unsupported provider: $EMBEDDING_PROVIDER"
            error "Supported providers: openai, google, ollama"
            exit 1
            ;;
    esac

    # Parse arguments
    local scan_path="${1:-.}"

    # Convert scan_path to absolute path
    scan_path=$(cd "$scan_path" 2>/dev/null && pwd || echo "$scan_path")

    info "Scanning path: $scan_path"

    # Set DATABASE_URL if not already set
    export DATABASE_URL="${DATABASE_URL:-postgresql://maproom:maproom@localhost:5432/maproom}"

    # Check database connectivity (optional)
    if command -v psql &> /dev/null; then
        if psql "$DATABASE_URL" -c "SELECT 1" &> /dev/null 2>&1; then
            info "Database connection verified"
        else
            warn "Cannot connect to database at: $DATABASE_URL"
            warn "Scan will continue, but ensure database is running for indexing to work"
        fi
    fi

    # Run scan using npx
    info "Starting scan with @crewchief/maproom-mcp..."
    npx @crewchief/maproom-mcp scan "$scan_path"

    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        info "Scan completed successfully"
        info ""
        info "Next steps:"
        info "  - Use mcp__maproom__search to search your code"
        info "  - Run 'bash watch.sh' to keep index updated automatically"
    else
        error "Scan failed with exit code: $exit_code"
        exit $exit_code
    fi
}

# Execute main function
main "$@"
