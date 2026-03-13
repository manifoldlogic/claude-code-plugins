#!/usr/bin/env bash
#
# cmux-utils.sh - Shared utilities for cmux terminal management
#
# DESCRIPTION:
#   Provides common utility functions for detecting execution context
#   (host vs container), validating prerequisites for cmux operations,
#   and SSH connectivity checks.
#
# USAGE:
#   Source this file to use the utility functions:
#     source /path/to/cmux-utils.sh
#
# FUNCTIONS:
#   is_container()         - Detect if running in container vs host
#   validate_ssh_host()    - Verify SSH connectivity to host.docker.internal
#   validate_cmux()        - Check cmux binary exists (via SSH)
#   validate_socket_mode() - Check socketControlMode is allowAll
#   cmux_info()            - Print info message to stderr
#   cmux_error()           - Print error message to stderr
#   cmux_warn()            - Print warning message to stderr
#
# EXIT CODES:
#   0 - Success / check passed
#   1 - Failure / check failed / direct execution rejected
#
# ENVIRONMENT VARIABLES:
#   HOST_USER - macOS host username (required for container mode)
#   CMUX_BIN_OVERRIDE - Override default cmux binary path (optional)

set -euo pipefail

##############################################################################
# Constants
##############################################################################

readonly CMUX_BIN="${CMUX_BIN_OVERRIDE:-/Applications/cmux.app/Contents/Resources/bin/cmux}"
readonly CMUX_PING_RESPONSE="PONG"

##############################################################################
# Output Functions (all write to stderr with [cmux] prefix)
##############################################################################

cmux_info() {
    echo "[cmux] INFO: $*" >&2
}

cmux_error() {
    echo "[cmux] ERROR: $*" >&2
}

cmux_warn() {
    echo "[cmux] WARN: $*" >&2
}

##############################################################################
# Context Detection
##############################################################################

# Detect if running inside container vs on macOS host
# Returns: 0 (true) if in container, 1 (false) if on host
is_container() {
    # Primary check: Docker environment file
    [ -f /.dockerenv ] && return 0

    # Secondary check: REMOTE_CONTAINERS env var
    [ -n "${REMOTE_CONTAINERS:-}" ] && return 0

    return 1
}

##############################################################################
# Validation Functions
##############################################################################

# Verify SSH connectivity to host.docker.internal
#
# Returns:
#   0 if SSH connection succeeds
#   1 if HOST_USER not set or SSH fails
validate_ssh_host() {
    local host_user="${HOST_USER:-}"

    # Check HOST_USER is set
    if [ -z "$host_user" ]; then
        cmux_error "HOST_USER environment variable not set"
        return 1
    fi

    # Test SSH connection with timeout
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 \
        "${host_user}@host.docker.internal" \
        "true" 2>/dev/null; then
        cmux_error "SSH connection to host.docker.internal failed"
        return 1
    fi

    return 0
}

# Check cmux binary exists and is executable on the host (via SSH)
# This checks binary existence only -- does NOT check if daemon is running
#
# Returns:
#   0 if binary is found and executable
#   1 if binary is not found or not executable
validate_cmux() {
    local host_user="${HOST_USER:-}"

    if [ -z "$host_user" ]; then
        cmux_error "HOST_USER environment variable not set"
        return 1
    fi

    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 \
        "${host_user}@host.docker.internal" \
        "test -x '${CMUX_BIN}'" 2>/dev/null; then
        cmux_error "cmux binary not found at ${CMUX_BIN}"
        return 1
    fi

    return 0
}

# Check socketControlMode is set to allowAll
#
# Returns:
#   0 if socketControlMode is allowAll
#   1 if not set or set to a different value
validate_socket_mode() {
    local host_user="${HOST_USER:-}"

    if [ -z "$host_user" ]; then
        cmux_error "HOST_USER environment variable not set"
        return 1
    fi

    local mode
    mode=$(ssh -o BatchMode=yes -o ConnectTimeout=5 \
        "${host_user}@host.docker.internal" \
        "defaults read com.cmuxterm.app socketControlMode" 2>/dev/null) || true

    if [ "$mode" != "allowAll" ]; then
        cmux_error "cmux socketControlMode is not set to 'allowAll' (current: '${mode:-unset}')"
        cmux_error "Fix with: defaults write com.cmuxterm.app socketControlMode -string allowAll"
        return 1
    fi

    return 0
}

##############################################################################
# Direct Execution Guard
##############################################################################

# shellcheck disable=SC2128
if [[ -n "${BASH_SOURCE:-}" && "${BASH_SOURCE[0]:-}" == "${0:-}" ]]; then
    cmux_error "This script is meant to be sourced, not executed directly"
    exit 1
fi
