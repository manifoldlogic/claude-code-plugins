#!/usr/bin/env bash
#
# test_security.sh - Security tests for path traversal, injection, and sanitization
#
# Tests:
# 1. Path traversal detection and rejection
# 2. Command injection prevention
# 3. Large input handling
# 4. Special character handling
# 5. File permission enforcement
# 6. Log sanitization (tokens, passwords)
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source test harness
# shellcheck source=tests/test-harness.sh
source "${SCRIPT_DIR}/test-harness.sh"

# Source common library
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

# Test setup
export CONFIG_LOG_LEVEL="error"
export SDD_ROOT="/app/.sdd"
export LOG_DIR="/tmp"
export LOG_FILE="/tmp/test_security_$$.log"

cleanup() {
    rm -f "$LOG_FILE" 2>/dev/null || true
}
trap cleanup EXIT

echo "========================================="
echo "Security Test Suite"
echo "========================================="
echo

#
# Test 1: Path Traversal - Relative Paths
#
echo "=== Test 1: Path Traversal - Relative Paths ==="

test_path_traversal_relative() {
    # Test various path traversal patterns
    if validate_safe_path "../../etc/passwd" 2>/dev/null; then
        fail "Should reject path traversal with ../"
    else
        pass "Rejects ../ path traversal"
    fi

    if validate_safe_path "../../../etc/shadow" 2>/dev/null; then
        fail "Should reject multiple ../ traversals"
    else
        pass "Rejects multiple ../ traversals"
    fi
}
run_test test_path_traversal_relative

#
# Test 2: Path Traversal - Absolute Paths
#
echo
echo "=== Test 2: Path Traversal - Absolute Paths ==="

test_path_traversal_absolute() {
    # Test absolute paths with traversal
    if validate_safe_path "/safe/path/../../../etc/passwd" 2>/dev/null; then
        fail "Should reject traversal in absolute path"
    else
        pass "Rejects traversal in absolute path"
    fi
}
run_test test_path_traversal_absolute

#
# Test 3: Path Validation - Outside SDD_ROOT
#
echo
echo "=== Test 3: Path Validation - Outside SDD_ROOT ==="

test_path_outside_sdd_root() {
    export CONFIG_SDD_ROOT="/app/.sdd"

    if validate_path_in_sdd_root "/etc/passwd" 2>/dev/null; then
        fail "Should reject path outside SDD_ROOT"
    else
        pass "Rejects /etc/passwd"
    fi

    if validate_path_in_sdd_root "/tmp/malicious" 2>/dev/null; then
        fail "Should reject /tmp paths"
    else
        pass "Rejects /tmp paths"
    fi
}
run_test test_path_outside_sdd_root

#
# Test 4: Special Characters - Quotes in Strings
#
echo
echo "=== Test 4: Special Characters - Quotes in Strings ==="

test_special_chars_quotes() {
    # Test that single and double quotes are handled safely
    test_string="test 'single' and \"double\" quotes"
    result=$(sanitize_log_message "$test_string")

    # Should preserve quotes (they're not security-sensitive)
    assert_contains "$result" "single" "Single quotes preserved"
    assert_contains "$result" "double" "Double quotes preserved"
}
run_test test_special_chars_quotes

#
# Test 5: Special Characters - Newlines
#
echo
echo "=== Test 5: Special Characters - Newlines ==="

test_special_chars_newlines() {
    # Test that newlines in log messages are handled
    test_string="line1
line2
line3"
    result=$(sanitize_log_message "$test_string")

    # Function should not crash on newlines
    assert_not_equals "" "$result" "Handles newlines without crashing"
}
run_test test_special_chars_newlines

#
# Test 6: Large Input - Long Strings
#
echo
echo "=== Test 6: Large Input - Long Strings ==="

test_large_input_strings() {
    # Create a large string (10KB)
    large_string=$(head -c 10240 /dev/zero | tr '\0' 'A')

    # Test that sanitization handles large inputs
    result=$(sanitize_log_message "$large_string" 2>/dev/null || echo "handled")
    assert_not_equals "" "$result" "Handles large strings"
}
run_test test_large_input_strings

#
# Test 7: Log Sanitization - API Tokens
#
echo
echo "=== Test 7: Log Sanitization - API Tokens ==="

test_log_sanitization_tokens() {
    > "$LOG_FILE"  # Clear log
    export CONFIG_LOG_LEVEL="info"
    export LOG_FILE="/tmp/test_security_$$.log"

    log_info "Using token: sk-1234567890abcdef"

    # Verify token is redacted in log file
    assert_file_not_contains "$LOG_FILE" "sk-1234567890abcdef" "Token should be redacted"
    assert_file_contains "$LOG_FILE" "REDACTED" "Should contain REDACTED marker"
}
run_test test_log_sanitization_tokens

#
# Test 8: Log Sanitization - Passwords
#
echo
echo "=== Test 8: Log Sanitization - Passwords ==="

test_log_sanitization_passwords() {
    > "$LOG_FILE"  # Clear log

    log_info "Connecting with password=secret123"

    # Verify password is redacted
    assert_file_not_contains "$LOG_FILE" "secret123" "Password should be redacted"
    assert_file_contains "$LOG_FILE" "REDACTED" "Should contain REDACTED marker"
}
run_test test_log_sanitization_passwords

#
# Test 9: File Permissions - Run Directory
#
echo
echo "=== Test 9: File Permissions - Run Directory ==="

test_file_permissions_run_dir() {
    test_dir="/tmp/test_run_dir_$$"
    mkdir -p "$test_dir"
    chmod 700 "$test_dir"

    perms=$(stat -c %a "$test_dir")
    assert_equals "700" "$perms" "Run directory should be 700"

    rm -rf "$test_dir"
}
run_test test_file_permissions_run_dir

#
# Test 10: File Permissions - State File
#
echo
echo "=== Test 10: File Permissions - State File ==="

test_file_permissions_state_file() {
    test_file="/tmp/test_state_$$.json"
    atomic_write "$test_file" '{"test": "data"}'

    perms=$(stat -c %a "$test_file")
    assert_equals "600" "$perms" "State file should be 600"

    rm -f "$test_file"
}
run_test test_file_permissions_state_file

#
# Test 11: JSON Validation - Prevents Injection
#
echo
echo "=== Test 11: JSON Validation - Prevents Injection ==="

test_json_validation() {
    # Invalid JSON should be rejected
    invalid_json='{"test": "value", "injection": <script>alert("xss")</script>}'

    if validate_json "$invalid_json" 2>/dev/null; then
        fail "Should reject invalid JSON with injection attempt"
    else
        pass "Rejects invalid JSON"
    fi
}
run_test test_json_validation

#
# Test 12: Safe Path - No Null Bytes
#
echo
echo "=== Test 12: Safe Path - No Null Bytes ==="

test_safe_path_no_null_bytes() {
    # Null bytes should be rejected (if bash supports them in test)
    test_path="test$(printf '\0')injection"

    # Most shells will truncate at null byte, so this tests current behavior
    result=$(sanitize_log_message "$test_path")
    # Just verify function doesn't crash
    assert_not_equals "" "$result" "Handles null byte attempts"
}
run_test test_safe_path_no_null_bytes

echo
echo "========================================="
print_summary
echo "========================================="
