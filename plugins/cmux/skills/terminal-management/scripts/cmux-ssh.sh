#!/usr/bin/env bash
#
# cmux-ssh.sh - SSH wrapper for cmux CLI commands
#
# DESCRIPTION:
#   Wraps cmux CLI commands via SSH to the macOS host. Because cmux CLI
#   does not work from SSH remote sessions (Issue #373), all commands
#   must be proxied via SSH using the full binary path.
#
# USAGE:
#   cmux-ssh.sh [--dry-run] [-h|--help] <cmux-subcommand> [args...]
#
# OPTIONS:
#   --dry-run   Print the SSH command without executing it
#   -h, --help  Print usage information and exit
#
# EXIT CODES:
#   0 - Success
#   1 - SSH or execution failure
#   2 - Invalid input (newlines or null bytes in arguments)
#   3 - No cmux subcommand provided
#
# ENVIRONMENT VARIABLES:
#   HOST_USER - macOS host username (required)

set -euo pipefail

##############################################################################
# Source shared utilities
##############################################################################

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
# shellcheck source=cmux-utils.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/cmux-utils.sh"

##############################################################################
# Usage
##############################################################################

usage() {
    cat <<'USAGE'
Usage: cmux-ssh.sh [--dry-run] [-h|--help] <cmux-subcommand> [args...]

Executes cmux CLI commands via SSH to the macOS host.

Options:
  --dry-run   Print the SSH command without executing it
  -h, --help  Print this usage information and exit

Arguments:
  <cmux-subcommand>  The cmux subcommand to run (e.g., send, list, ping)
  [args...]          Additional arguments for the cmux subcommand

Examples:
  cmux-ssh.sh ping
  cmux-ssh.sh send --workspace workspace:1 "hello world"
  cmux-ssh.sh --dry-run send --workspace workspace:1 "it's a test"

Exit Codes:
  0  Success
  1  SSH or execution failure
  2  Invalid input (newlines or null bytes in arguments)
  3  No cmux subcommand provided
USAGE
}

##############################################################################
# Argument Parsing
##############################################################################

dry_run=false

# Handle --help / -h / --dry-run before positional args
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            dry_run=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

# Require at least one positional argument (the cmux subcommand)
if [ $# -eq 0 ]; then
    cmux_error "No cmux subcommand provided"
    usage >&2
    exit 3
fi

##############################################################################
# Input Validation & Escaping
##############################################################################

# Validate and escape all arguments
escaped_args=""
for arg in "$@"; do
    # Reject arguments containing newlines
    if [[ "$arg" == *$'\n'* ]]; then
        cmux_error "Arguments must not contain newlines"
        exit 2
    fi

    # Reject arguments containing null bytes
    # Note: bash cannot store null bytes in variables, but we check the
    # original argument length vs printf output as a safeguard
    if printf '%s' "$arg" | grep -qP '\x00' 2>/dev/null; then
        cmux_error "Arguments must not contain null bytes"
        exit 2
    fi

    # Escape the argument using printf '%q'
    local_escaped=$(printf '%q' "$arg")

    if [ -z "$escaped_args" ]; then
        escaped_args="$local_escaped"
    else
        escaped_args="$escaped_args $local_escaped"
    fi
done

##############################################################################
# Build and Execute SSH Command
##############################################################################

host_user="${HOST_USER:-}"
if [ -z "$host_user" ]; then
    cmux_error "HOST_USER environment variable not set"
    exit 1
fi

ssh_target="${host_user}@host.docker.internal"
remote_cmd="${CMUX_BIN} ${escaped_args}"

if [ "$dry_run" = true ]; then
    echo "ssh -o BatchMode=yes -o ConnectTimeout=5 ${ssh_target} \"${remote_cmd}\""
    exit 0
fi

# Execute SSH command (call ssh as plain command for test mockability)
ssh -o BatchMode=yes -o ConnectTimeout=5 "${ssh_target}" "${remote_cmd}"
