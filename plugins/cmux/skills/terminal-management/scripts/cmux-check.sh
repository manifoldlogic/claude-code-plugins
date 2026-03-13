#!/usr/bin/env bash
#
# cmux-check.sh - Prerequisite validator for cmux plugin
#
# DESCRIPTION:
#   Validates all prerequisites needed for cmux operations.
#   Checks are run in order and all results are reported.
#
# USAGE:
#   cmux-check.sh [--quiet]
#
# OPTIONS:
#   --quiet  Suppress all output; exit code only
#
# EXIT CODES:
#   0 - All prerequisites pass
#   1 - One or more prerequisites failed

set -euo pipefail

##############################################################################
# Source shared utilities
##############################################################################

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
# shellcheck source=cmux-utils.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/cmux-utils.sh"

##############################################################################
# Argument Parsing
##############################################################################

quiet=false

if [ "${1:-}" = "--quiet" ]; then
    quiet=true
fi

##############################################################################
# Output Helpers
##############################################################################

check_pass() {
    if [ "$quiet" = false ]; then
        echo "[PASS] $*" >&2
    fi
}

check_fail() {
    if [ "$quiet" = false ]; then
        echo "[FAIL] $*" >&2
    fi
}

##############################################################################
# Run Checks
##############################################################################

all_passed=true

# Check 1: HOST_USER is set and non-empty
if [ -n "${HOST_USER:-}" ]; then
    check_pass "HOST_USER is set (${HOST_USER})"
else
    check_fail "HOST_USER environment variable is not set"
    all_passed=false
fi

# Check 2: SSH to host.docker.internal is reachable
if [ "$all_passed" = true ]; then
    if validate_ssh_host 2>/dev/null; then
        check_pass "SSH to host.docker.internal is reachable"
    else
        check_fail "SSH to host.docker.internal is not reachable"
        all_passed=false
    fi
else
    check_fail "SSH to host.docker.internal (skipped - HOST_USER not set)"
fi

# Check 3: socketControlMode is allowAll
if [ "$all_passed" = true ]; then
    if validate_socket_mode 2>/dev/null; then
        check_pass "cmux socketControlMode is allowAll"
    else
        check_fail "cmux socketControlMode is not 'allowAll'"
        if [ "$quiet" = false ]; then
            echo "       Fix: defaults write com.cmuxterm.app socketControlMode -string allowAll" >&2
        fi
        all_passed=false
    fi
else
    check_fail "cmux socketControlMode (skipped - prior check failed)"
fi

# Check 4: cmux binary exists at CMUX_BIN
if [ "$all_passed" = true ]; then
    if ssh -o BatchMode=yes -o ConnectTimeout=5 \
        "${HOST_USER}@host.docker.internal" \
        "test -x '${CMUX_BIN}'" 2>/dev/null; then
        check_pass "cmux binary found at ${CMUX_BIN}"
    else
        check_fail "cmux binary not found at ${CMUX_BIN}"
        all_passed=false
    fi
else
    check_fail "cmux binary exists (skipped - prior check failed)"
fi

# Check 5: cmux daemon is running (ping)
if [ "$all_passed" = true ]; then
    ping_result=$(ssh -o BatchMode=yes -o ConnectTimeout=5 \
        "${HOST_USER}@host.docker.internal" \
        "'${CMUX_BIN}' ping" 2>/dev/null) || true

    if [ "$ping_result" = "PONG" ]; then
        check_pass "cmux daemon is running"
    else
        check_fail "cmux daemon is not running"
        all_passed=false
    fi
else
    check_fail "cmux daemon running (skipped - prior check failed)"
fi

##############################################################################
# Final Result
##############################################################################

if [ "$all_passed" = true ]; then
    exit 0
else
    exit 1
fi
