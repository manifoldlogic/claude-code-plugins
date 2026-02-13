#!/usr/bin/env bash
#
# Common Helper Functions
# Shared utility functions for SDD project workflow scripts.
# Sourced by scaffold-ticket.sh, triage-documents.sh, validate-structure.sh.
#
# Note: Does NOT set -euo pipefail - that is the caller's responsibility.
# Having set -e in a sourced file can cause unexpected behavior.

# Color control: respect NO_COLOR env var (https://no-color.org)
# Callers can also set USE_COLOR=false before sourcing
if [ "${NO_COLOR:-}" != "" ] || [ "${USE_COLOR:-}" = "false" ]; then
    RED=""
    GREEN=""
    YELLOW=""
    NC=""
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
fi

# Debug mode: enable verbose command tracing
# Callers can set SDD_DEBUG=true before sourcing, or use --debug flag
if [ "${SDD_DEBUG:-}" = "true" ] || [ "${DEBUG:-}" = "1" ]; then
    set -x
fi

# Ticket ID length constraints
# MIN: 2 characters (e.g., "TA")
# MAX: 12 characters (readable, fits in file paths, allows Jira-style IDs)
MIN_TICKET_ID_LENGTH=2
MAX_TICKET_ID_LENGTH=12

# Check that jq is installed and meets the minimum version requirement (1.5+).
# Returns 0 on success, 1 if jq is missing or too old.
check_jq_version() {
    if ! command -v jq >/dev/null 2>&1; then
        printf "[ERROR] jq is required but not installed.\n" >&2
        printf "\n" >&2
        printf "Install jq using your package manager:\n" >&2
        printf "  apt-get install jq    # Debian/Ubuntu\n" >&2
        printf "  brew install jq       # macOS\n" >&2
        printf "  yum install jq        # RHEL/CentOS\n" >&2
        return 1
    fi
    jq_version=$(jq --version 2>/dev/null)
    # Extract version number: "jq-1.6" -> "1.6", "jq-1.7.1" -> "1.7.1"
    version_num=$(printf '%s' "$jq_version" | sed 's/jq-//')
    major=$(printf '%s' "$version_num" | cut -d. -f1)
    minor=$(printf '%s' "$version_num" | cut -d. -f2)
    if [ "$major" -lt 1 ] 2>/dev/null || { [ "$major" -eq 1 ] && [ "$minor" -lt 5 ] 2>/dev/null; }; then
        printf "[ERROR] jq 1.5+ is required (found: %s)\n" "$jq_version" >&2
        return 1
    fi
    return 0
}

# Print error message to stderr in red (with timestamp)
error() { printf "[$(date +"%T")] ${RED}[ERROR]${NC} %s\n" "$1" >&2; }

# Print warning message to stderr in yellow (with timestamp)
warn() { printf "[$(date +"%T")] ${YELLOW}[WARN]${NC} %s\n" "$1" >&2; }

# Print info message to stderr in green (with timestamp)
info() { printf "[$(date +"%T")] ${GREEN}[INFO]${NC} %s\n" "$1" >&2; }
