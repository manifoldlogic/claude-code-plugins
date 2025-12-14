#!/usr/bin/env bash
#
# test_common_utilities.sh - Test common utility functions from lib/common.sh
#
# Tests:
# 1. Logging functions (debug, info, warn, error)
# 2. Log sanitization (tokens, passwords, auth headers)
# 3. JSON helper functions (is_success, extract_field, validate_json)
# 4. Atomic write (success, permission error, cleanup)
# 5. Path validation (safe paths, traversal attempts, SDD_ROOT checks)
#

set -euo pipefail

# Get script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Source the common library
# shellcheck source=../lib/common.sh
source "${LIB_DIR}/common.sh"

# Source test harness
# shellcheck source=test-harness.sh
source "${SCRIPT_DIR}/test-harness.sh"

# Test setup
TEST_LOG_DIR="/tmp/test_common_utilities_$$"
mkdir -p "$TEST_LOG_DIR"
export LOG_DIR="$TEST_LOG_DIR"
export LOG_FILE="${TEST_LOG_DIR}/test.log"
export CONFIG_LOG_LEVEL="debug"
export SDD_ROOT="/app/.sdd"  # Required for path validation tests

# Cleanup on exit
cleanup() {
    rm -rf "$TEST_LOG_DIR" 2>/dev/null || true
}
trap cleanup EXIT

echo "========================================="
echo "Common Utilities Test Suite"
echo "========================================="
echo

#
# Test 1: Logging Functions - All Levels
#
echo "=== Test 1: Logging Functions - All Levels ==="

test_log_all_levels() {
    log_debug "This is a debug message"
    log_info "This is an info message"
    log_warn "This is a warning message"
    log_error "This is an error message"

    assert_file_exists "$LOG_FILE" "Log file should exist"
    assert_file_contains "$LOG_FILE" "DEBUG" "Should contain DEBUG level"
    assert_file_contains "$LOG_FILE" "INFO" "Should contain INFO level"
    assert_file_contains "$LOG_FILE" "WARN" "Should contain WARN level"
    assert_file_contains "$LOG_FILE" "ERROR" "Should contain ERROR level"
}
run_test test_log_all_levels

#
# Test 2: Log Sanitization - Tokens
#
echo
echo "=== Test 2: Log Sanitization - Tokens ==="

test_log_sanitize_tokens() {
    > "$LOG_FILE"  # Clear log
    log_info "Using API token: sk-abc123def456ghi789"

    # Current implementation only sanitizes sk- tokens
    assert_file_not_contains "$LOG_FILE" "sk-abc123def456ghi789" "Token should be redacted"
    assert_file_contains "$LOG_FILE" "REDACTED" "Should contain REDACTED marker"
}
run_test test_log_sanitize_tokens

#
# Test 3: Log Sanitization - Passwords
#
echo
echo "=== Test 3: Log Sanitization - Passwords ==="

test_log_sanitize_passwords() {
    > "$LOG_FILE"  # Clear log
    log_info "password=verysecure456"

    # Current implementation sanitizes password= pattern
    assert_file_not_contains "$LOG_FILE" "verysecure456" "Password should be redacted"
    assert_file_contains "$LOG_FILE" "REDACTED" "Should contain REDACTED marker"
}
run_test test_log_sanitize_passwords

#
# Test 4: Log Sanitization - Auth Headers
#
echo
echo "=== Test 4: Log Sanitization - Auth Headers ==="

test_log_sanitize_auth_headers() {
    > "$LOG_FILE"  # Clear log
    log_info "Authorization: Bearer xyz789abc456"

    # Current implementation sanitizes "Bearer" keyword in Authorization headers
    assert_file_contains "$LOG_FILE" "REDACTED" "Auth header should contain REDACTED"
    assert_file_not_contains "$LOG_FILE" "Bearer" "Bearer keyword should be redacted"
}
run_test test_log_sanitize_auth_headers

#
# Test 5: JSON Helper - is_success True
#
echo
echo "=== Test 5: JSON Helper - is_success True ==="

test_is_success_true() {
    json='{"success": true, "data": "test"}'
    is_success "$json"
    assert_equals "0" "$?" "is_success should return 0 for success=true"
}
run_test test_is_success_true

#
# Test 6: JSON Helper - is_success False
#
echo
echo "=== Test 6: JSON Helper - is_success False ==="

test_is_success_false() {
    json='{"success": false, "error": "test error"}'
    if is_success "$json"; then
        fail "is_success should return non-zero for success=false"
    else
        pass "is_success returns non-zero for success=false"
    fi
}
run_test test_is_success_false

#
# Test 7: JSON Helper - extract_field Simple
#
echo
echo "=== Test 7: JSON Helper - extract_field Simple ==="

test_extract_field_simple() {
    json='{"name": "test", "value": 123}'
    result=$(extract_field "$json" "name")
    assert_equals "test" "$result" "Should extract simple field"
}
run_test test_extract_field_simple

#
# Test 8: JSON Helper - extract_field Nested
#
echo
echo "=== Test 8: JSON Helper - extract_field Nested ==="

test_extract_field_nested() {
    json='{"result": {"data": {"key": "value"}}}'
    result=$(extract_field "$json" "result.data.key")
    assert_equals "value" "$result" "Should extract nested field"
}
run_test test_extract_field_nested

#
# Test 9: JSON Helper - extract_field Missing
#
echo
echo "=== Test 9: JSON Helper - extract_field Missing ==="

test_extract_field_missing() {
    json='{"name": "test"}'
    result=$(extract_field "$json" "nonexistent" 2>/dev/null || echo "")
    assert_equals "" "$result" "Should return empty for missing field"
}
run_test test_extract_field_missing

#
# Test 10: JSON Helper - validate_json Valid
#
echo
echo "=== Test 10: JSON Helper - validate_json Valid ==="

test_validate_json_valid() {
    json='{"valid": true, "array": [1, 2, 3]}'
    validate_json "$json"
    assert_equals "0" "$?" "validate_json should return 0 for valid JSON"
}
run_test test_validate_json_valid

#
# Test 11: JSON Helper - validate_json Invalid
#
echo
echo "=== Test 11: JSON Helper - validate_json Invalid ==="

test_validate_json_invalid() {
    json='{"invalid": true, "missing": }'
    if validate_json "$json" 2>/dev/null; then
        fail "validate_json should fail on invalid JSON"
    else
        pass "validate_json fails on invalid JSON"
    fi
}
run_test test_validate_json_invalid

#
# Test 12: Atomic Write - Success
#
echo
echo "=== Test 12: Atomic Write - Success ==="

test_atomic_write_success() {
    temp_file="${TEST_LOG_DIR}/atomic_test_$$"
    content="Test content with special chars: 'quotes' \"double\" \$vars"

    atomic_write "$temp_file" "$content"

    assert_file_exists "$temp_file" "File should exist after atomic_write"

    actual_content=$(cat "$temp_file")
    assert_equals "$content" "$actual_content" "Content should match"

    # Check permissions (600 = rw-------)
    perms=$(stat -c %a "$temp_file")
    assert_equals "600" "$perms" "File permissions should be 600"
}
run_test test_atomic_write_success

#
# Test 13: Atomic Write - Multiple Writes
#
echo
echo "=== Test 13: Atomic Write - Multiple Writes ==="

test_atomic_write_overwrite() {
    temp_file="${TEST_LOG_DIR}/overwrite_test_$$"

    # First write
    atomic_write "$temp_file" "first content"
    assert_file_contains "$temp_file" "first content" "First write should succeed"

    # Second write (overwrite)
    atomic_write "$temp_file" "second content"
    assert_file_contains "$temp_file" "second content" "Second write should overwrite"
    assert_file_not_contains "$temp_file" "first content" "First content should be gone"
}
run_test test_atomic_write_overwrite

#
# Test 14: Path Validation - Safe Path
#
echo
echo "=== Test 14: Path Validation - Safe Path ==="

test_validate_safe_path_ok() {
    validate_safe_path "/app/.sdd/tickets/TEST-1"
    assert_equals "0" "$?" "Safe path should validate"

    validate_safe_path "./relative/path/file.txt"
    assert_equals "0" "$?" "Relative path without traversal should validate"
}
run_test test_validate_safe_path_ok

#
# Test 15: Path Validation - Traversal Detected
#
echo
echo "=== Test 15: Path Validation - Traversal Detected ==="

test_validate_safe_path_traversal() {
    if validate_safe_path "../../etc/passwd" 2>/dev/null; then
        fail "Should detect path traversal"
    else
        pass "Path traversal detected"
    fi

    if validate_safe_path "/safe/path/../../../etc/shadow" 2>/dev/null; then
        fail "Should detect path traversal in absolute path"
    else
        pass "Path traversal in absolute path detected"
    fi
}
run_test test_validate_safe_path_traversal

#
# Test 16: Path Validation - Within SDD_ROOT
#
echo
echo "=== Test 16: Path Validation - Within SDD_ROOT ==="

test_validate_path_in_sdd_root_ok() {
    export CONFIG_SDD_ROOT="/app/.sdd"

    validate_path_in_sdd_root "/app/.sdd/tickets"
    assert_equals "0" "$?" "Path within SDD_ROOT should validate"

    validate_path_in_sdd_root "/app/.sdd/epics/EPIC-1"
    assert_equals "0" "$?" "Nested path within SDD_ROOT should validate"
}
run_test test_validate_path_in_sdd_root_ok

#
# Test 17: Path Validation - Outside SDD_ROOT
#
echo
echo "=== Test 17: Path Validation - Outside SDD_ROOT ==="

test_validate_path_in_sdd_root_outside() {
    export CONFIG_SDD_ROOT="/app/.sdd"

    if validate_path_in_sdd_root "/etc/passwd" 2>/dev/null; then
        fail "Should reject path outside SDD_ROOT"
    else
        pass "Path outside SDD_ROOT rejected"
    fi

    if validate_path_in_sdd_root "/tmp/some/file" 2>/dev/null; then
        fail "Should reject path outside SDD_ROOT"
    else
        pass "Path outside SDD_ROOT rejected"
    fi
}
run_test test_validate_path_in_sdd_root_outside

#
# Test 18: Component Name Extraction
#
echo
echo "=== Test 18: Component Name Extraction ==="

test_get_component_name() {
    # Mock BASH_SOURCE for testing
    result=$(get_component_name)
    # Should return something (exact value depends on script name)
    assert_not_equals "" "$result" "Component name should not be empty"
}
run_test test_get_component_name

#
# Test 19: Sanitize Log Message Function
#
echo
echo "=== Test 19: Sanitize Log Message Function ==="

test_sanitize_log_message() {
    result=$(sanitize_log_message "Token: sk-abc123")
    assert_not_contains "$result" "sk-abc123" "Token should be sanitized"
    assert_contains "$result" "REDACTED" "Should contain REDACTED"

    result=$(sanitize_log_message "Normal message")
    assert_equals "Normal message" "$result" "Normal message unchanged"
}
run_test test_sanitize_log_message

echo
echo "========================================="
print_summary
echo "========================================="
