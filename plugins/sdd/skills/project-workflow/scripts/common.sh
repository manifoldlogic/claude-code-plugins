#!/usr/bin/env bash
#
# Common Helper Functions
# Shared utility functions for SDD project workflow scripts.
# Sourced by scaffold-ticket.sh, triage-documents.sh, validate-structure.sh.
#
# Note: Does NOT set -euo pipefail - that is the caller's responsibility.
# Having set -e in a sourced file can cause unexpected behavior.

# Colors (stderr only)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Print error message to stderr in red
error() { printf "${RED}[ERROR]${NC} %s\n" "$1" >&2; }

# Print warning message to stderr in yellow
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1" >&2; }

# Print info message to stderr in green
info() { printf "${GREEN}[INFO]${NC} %s\n" "$1" >&2; }
