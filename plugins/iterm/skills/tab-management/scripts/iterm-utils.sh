#!/usr/bin/env bash
#
# iterm-utils.sh - Shared utilities for iTerm2 tab management
#
# DESCRIPTION:
#   Provides common utility functions for detecting execution context
#   (host vs container), executing AppleScript locally or remotely via SSH,
#   and validating prerequisites for iTerm2 operations.
#
# USAGE:
#   Source this file to use the utility functions:
#     source /path/to/iterm-utils.sh
#
# FUNCTIONS:
#   is_container()      - Detect if running in container vs host
#   run_applescript()   - Execute AppleScript locally or remotely
#   validate_iterm()    - Check iTerm2 is available on macOS
#   validate_ssh_host() - Verify SSH connectivity to host.docker.internal
#
# EXIT CODES:
#   EXIT_SUCCESS=0         - Operation completed successfully
#   EXIT_CONNECTION_FAIL=1 - SSH/connection failure
#   EXIT_ITERM_UNAVAILABLE=2 - iTerm2 not available
#   EXIT_INVALID_ARGS=3    - Invalid arguments provided
#   EXIT_NO_MATCH=4        - Pattern matches no tabs (used by iterm-close-tab.sh)
#
# ENVIRONMENT VARIABLES:
#   HOST_USER - macOS host username (required for container mode)
#               Set in devcontainer.json: "remoteEnv": {"HOST_USER": "your-username"}
#
# shellcheck disable=SC2034

set -euo pipefail

##############################################################################
# Exit Code Constants
##############################################################################

readonly EXIT_SUCCESS=0
readonly EXIT_CONNECTION_FAIL=1
readonly EXIT_ITERM_UNAVAILABLE=2
readonly EXIT_INVALID_ARGS=3
readonly EXIT_NO_MATCH=4

##############################################################################
# Color Output Functions
##############################################################################

# Colors for terminal output
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_NC='\033[0m'  # No Color

# Output functions (all go to stderr to avoid polluting captured output)
iterm_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_NC} $*" >&2
}

iterm_ok() {
    echo -e "${COLOR_GREEN}[OK]${COLOR_NC} $*" >&2
}

iterm_warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_NC} $*" >&2
}

iterm_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_NC} $*" >&2
}

##############################################################################
# Context Detection
##############################################################################

# Detect if running inside container vs on macOS host
# Returns: 0 (true) if in container, 1 (false) if on host
#
# Detection methods (in order):
#   1. Docker environment file (/.dockerenv)
#   2. Docker in cgroup (for older Docker versions)
#   3. Not macOS (uname != Darwin implies container/Linux)
is_container() {
    # Primary check: Docker environment file
    [ -f /.dockerenv ] && return 0

    # Secondary check: Docker in cgroup (older Docker versions)
    # shellcheck disable=SC2015
    grep -q docker /proc/1/cgroup 2>/dev/null && return 0

    # Tertiary check: Not macOS implies container/Linux environment
    [ "$(uname -s)" != "Darwin" ] && return 0

    return 1
}

##############################################################################
# AppleScript Execution
##############################################################################

# Global variable to track temp file for cleanup
_ITERM_TEMP_SCRIPT=""

# Cleanup function for trap handlers
_cleanup_temp_script() {
    local host_user="${HOST_USER:-}"
    if [ -n "$_ITERM_TEMP_SCRIPT" ]; then
        if [ -n "$host_user" ]; then
            # Remote cleanup via SSH (suppress errors - file may already be cleaned)
            ssh -o BatchMode=yes -o ConnectTimeout=5 \
                "${host_user}@host.docker.internal" \
                "rm -f '$_ITERM_TEMP_SCRIPT'" 2>/dev/null || true
        else
            # Local cleanup
            rm -f "$_ITERM_TEMP_SCRIPT" 2>/dev/null || true
        fi
        _ITERM_TEMP_SCRIPT=""
    fi
}

# Execute AppleScript locally or remotely via SSH
#
# Arguments:
#   $1 - script: AppleScript code to execute
#   $2 - mode: Execution mode - "local", "remote", or "auto" (default: "auto")
#
# Returns:
#   EXIT_SUCCESS (0) on success
#   EXIT_CONNECTION_FAIL (1) on SSH/connection failure
#   EXIT_INVALID_ARGS (3) if script is empty
#
# Environment:
#   HOST_USER - Required for remote mode (macOS host username)
#
# Notes:
#   - Auto mode detects container vs host and chooses appropriate execution
#   - Remote mode uses base64 encoding to safely pass script through SSH
#   - Trap handlers ensure cleanup of temporary files on EXIT, INT, TERM
run_applescript() {
    local script="${1:-}"
    local mode="${2:-auto}"

    # Validate script is provided
    if [ -z "$script" ]; then
        iterm_error "run_applescript: Script argument is required"
        return $EXIT_INVALID_ARGS
    fi

    # Auto-detect mode if not specified
    if [ "$mode" = "auto" ]; then
        if is_container; then
            mode="remote"
        else
            mode="local"
        fi
    fi

    if [ "$mode" = "remote" ]; then
        _run_applescript_remote "$script"
    else
        _run_applescript_local "$script"
    fi
}

# Internal: Execute AppleScript locally (macOS host)
_run_applescript_local() {
    local script="$1"

    # Direct execution using osascript
    if ! osascript -e "$script"; then
        iterm_error "AppleScript execution failed"
        return $EXIT_CONNECTION_FAIL
    fi

    return $EXIT_SUCCESS
}

# Internal: Execute AppleScript remotely via SSH
_run_applescript_remote() {
    local script="$1"
    local host_user="${HOST_USER:-}"

    # Validate HOST_USER is set
    if [ -z "$host_user" ]; then
        iterm_error "HOST_USER not set - cannot execute AppleScript remotely"
        iterm_error "Set HOST_USER in devcontainer.json remoteEnv"
        return $EXIT_CONNECTION_FAIL
    fi

    # Base64 encode script to safely pass through SSH
    local encoded
    encoded=$(printf '%s' "$script" | base64 -w0 2>/dev/null || printf '%s' "$script" | base64)

    # Create temp file on remote host using mktemp
    local temp_script
    temp_script=$(ssh -o BatchMode=yes -o ConnectTimeout=5 \
        "${host_user}@host.docker.internal" \
        "mktemp /tmp/iterm-XXXXXX.scpt" 2>/dev/null)

    if [ -z "$temp_script" ]; then
        iterm_error "Failed to create temp file on remote host"
        return $EXIT_CONNECTION_FAIL
    fi

    # Store for cleanup
    _ITERM_TEMP_SCRIPT="$temp_script"

    # Set up trap handlers for cleanup on EXIT, INT, TERM
    trap _cleanup_temp_script EXIT INT TERM

    # Decode script to temp file, execute, then clean up
    if ssh -o BatchMode=yes -o ConnectTimeout=10 \
        "${host_user}@host.docker.internal" \
        "printf '%s' '$encoded' | base64 -d > '$temp_script' && osascript '$temp_script'"; then
        # Clean up temp file on success
        ssh -o BatchMode=yes -o ConnectTimeout=5 \
            "${host_user}@host.docker.internal" \
            "rm -f '$temp_script'" 2>/dev/null || true
        _ITERM_TEMP_SCRIPT=""
        return $EXIT_SUCCESS
    else
        local exit_code=$?
        iterm_error "Remote AppleScript execution failed"
        # Cleanup will happen via trap
        return $EXIT_CONNECTION_FAIL
    fi
}

##############################################################################
# Validation Functions
##############################################################################

# Check iTerm2 is available on macOS
#
# Returns:
#   EXIT_SUCCESS (0) if iTerm2 is available
#   EXIT_ITERM_UNAVAILABLE (2) if iTerm2 is not found
#
# Notes:
#   - Checks for iTerm.app in /Applications
#   - In container mode, validates via SSH to host
validate_iterm() {
    if is_container; then
        _validate_iterm_remote
    else
        _validate_iterm_local
    fi
}

# Internal: Validate iTerm2 locally (macOS host)
_validate_iterm_local() {
    if [ ! -d "/Applications/iTerm.app" ]; then
        iterm_error "iTerm2 not found at /Applications/iTerm.app"
        iterm_error "Install from: https://iterm2.com"
        return $EXIT_ITERM_UNAVAILABLE
    fi

    return $EXIT_SUCCESS
}

# Internal: Validate iTerm2 remotely via SSH
_validate_iterm_remote() {
    local host_user="${HOST_USER:-}"

    # First validate SSH connectivity
    if ! validate_ssh_host; then
        return $EXIT_CONNECTION_FAIL
    fi

    # Check for iTerm.app on remote host
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 \
        "${host_user}@host.docker.internal" \
        "[ -d '/Applications/iTerm.app' ]" 2>/dev/null; then
        iterm_error "iTerm2 not found on macOS host at /Applications/iTerm.app"
        iterm_error "Install from: https://iterm2.com"
        return $EXIT_ITERM_UNAVAILABLE
    fi

    return $EXIT_SUCCESS
}

# Verify SSH connectivity to host.docker.internal
#
# Returns:
#   EXIT_SUCCESS (0) if SSH connection succeeds
#   EXIT_CONNECTION_FAIL (1) if HOST_USER not set or SSH fails
#
# Environment:
#   HOST_USER - Required (macOS host username)
#
# Notes:
#   - Uses BatchMode=yes to prevent password prompts
#   - Uses ConnectTimeout=5 to fail fast on network issues
validate_ssh_host() {
    local host_user="${HOST_USER:-}"

    # Check HOST_USER is set
    if [ -z "$host_user" ]; then
        iterm_error "HOST_USER environment variable not set"
        iterm_error "Set HOST_USER in devcontainer.json remoteEnv"
        return $EXIT_CONNECTION_FAIL
    fi

    # Test SSH connection with timeout
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 \
        "${host_user}@host.docker.internal" \
        "exit 0" 2>/dev/null; then
        iterm_error "SSH connection to host.docker.internal failed"
        iterm_error "Verify SSH is configured (see post-start.sh setup)"
        return $EXIT_CONNECTION_FAIL
    fi

    return $EXIT_SUCCESS
}

##############################################################################
# Module Detection
##############################################################################

# Prevent execution if sourced (allow sourcing for function access)
# This check allows the file to be sourced without running any commands
# shellcheck disable=SC2128
if [[ -n "${BASH_SOURCE:-}" && "${BASH_SOURCE[0]:-}" == "${0:-}" ]]; then
    iterm_error "This script is meant to be sourced, not executed directly"
    iterm_error "Usage: source $(basename "${BASH_SOURCE[0]:-iterm-utils.sh}")"
    exit $EXIT_INVALID_ARGS
fi
