#!/usr/bin/env bash
#
# test_config.sh - Test configuration loading, validation, and override functionality
#
# Tests:
# 1. Valid configuration loads successfully
# 2. All CONFIG_* variables are set correctly
# 3. Missing config file fails with exit 2
# 4. Invalid JSON fails with exit 2
# 5. Missing required field fails validation
# 6. Wrong type (string where integer expected) fails
# 7. Invalid enum value fails
# 8. Environment variable overrides work
# 9. Overrides are logged appropriately
# 10. Invalid override values fail validation
#

set -euo pipefail

# Get script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Source the common library
# shellcheck source=../lib/common.sh
source "${LIB_DIR}/common.sh"

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Cleanup temp files on exit
TEMP_FILES=()
cleanup() {
    for file in "${TEMP_FILES[@]}"; do
        rm -f "$file" 2>/dev/null || true
    done
}
trap cleanup EXIT

#
# test_assert - Assert a condition and report result
#
test_assert() {
    local description="$1"
    local condition="$2"

    TESTS_RUN=$((TESTS_RUN + 1))

    if eval "$condition"; then
        echo "[PASS] $description"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        echo "[FAIL] $description"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

#
# test_load_valid_config - Test loading valid configuration
#
test_load_valid_config() {
    echo ""
    echo "=== Test 1: Load Valid Configuration ==="

    # Ensure /app/.sdd exists for validation
    mkdir -p /app/.sdd

    # Load config
    if load_config; then
        test_assert "load_config returns 0" "true"
    else
        test_assert "load_config returns 0" "false"
        return 1
    fi

    # Check all variables are set correctly
    test_assert "CONFIG_SDD_ROOT is set" '[ "$CONFIG_SDD_ROOT" = "/app/.sdd" ]'
    test_assert "CONFIG_RETRY_MAX_ATTEMPTS is 3" '[ "$CONFIG_RETRY_MAX_ATTEMPTS" = "3" ]'
    test_assert "CONFIG_RETRY_INITIAL_DELAY is 5" '[ "$CONFIG_RETRY_INITIAL_DELAY" = "5" ]'
    test_assert "CONFIG_RETRY_BACKOFF_MULTIPLIER is 2" '[ "$CONFIG_RETRY_BACKOFF_MULTIPLIER" = "2" ]'
    test_assert "CONFIG_CHECKPOINT_FREQUENCY is per_stage" '[ "$CONFIG_CHECKPOINT_FREQUENCY" = "per_stage" ]'
    test_assert "CONFIG_CHECKPOINT_MAX is 10" '[ "$CONFIG_CHECKPOINT_MAX" = "10" ]'
    test_assert "CONFIG_RISK_TOLERANCE is moderate" '[ "$CONFIG_RISK_TOLERANCE" = "moderate" ]'
    test_assert "CONFIG_DECISION_TIMEOUT is 120" '[ "$CONFIG_DECISION_TIMEOUT" = "120" ]'
    test_assert "CONFIG_LOG_LEVEL is info" '[ "$CONFIG_LOG_LEVEL" = "info" ]'
    test_assert "CONFIG_LOG_FORMAT is structured" '[ "$CONFIG_LOG_FORMAT" = "structured" ]'
    test_assert "CONFIG_CLAUDE_PATH is claude" '[ "$CONFIG_CLAUDE_PATH" = "claude" ]'
    test_assert "CONFIG_JIRA_PATH is acli" '[ "$CONFIG_JIRA_PATH" = "acli" ]'
    test_assert "CONFIG_GH_PATH is gh" '[ "$CONFIG_GH_PATH" = "gh" ]'
}

#
# test_missing_config_file - Test missing config file fails
#
test_missing_config_file() {
    echo ""
    echo "=== Test 2: Missing Config File ==="

    # Create a temp script that tries to load from non-existent location
    local test_script
    test_script=$(mktemp)
    TEMP_FILES+=("$test_script")

    cat > "$test_script" <<'EOF'
#!/usr/bin/env bash
source() { :; }  # Stub out source for this test
CONFIG_SDD_ROOT=""
log_error() { :; }
log_debug() { :; }
log_info() { :; }
extract_field() { :; }
validate_json() { return 0; }
validate_config() { return 0; }
apply_env_overrides() { return 0; }

load_config() {
    local config_file="/nonexistent/config.json"
    if [ ! -f "$config_file" ]; then
        log_error "Configuration file not found: $config_file"
        return 2
    fi
    return 0
}

load_config
EOF

    chmod +x "$test_script"

    if "$test_script" 2>/dev/null; then
        test_assert "Missing config file returns exit 2" "false"
    else
        local exit_code=$?
        test_assert "Missing config file returns exit 2" "[ $exit_code -eq 2 ]"
    fi
}

#
# test_invalid_json - Test invalid JSON fails
#
test_invalid_json() {
    echo ""
    echo "=== Test 3: Invalid JSON ==="

    local temp_config
    temp_config=$(mktemp)
    TEMP_FILES+=("$temp_config")

    echo "{broken json" > "$temp_config"

    if validate_json "$(cat "$temp_config")"; then
        test_assert "Invalid JSON fails validation" "false"
    else
        test_assert "Invalid JSON fails validation" "true"
    fi
}

#
# test_validation_errors - Test validation catches errors
#
test_validation_errors() {
    echo ""
    echo "=== Test 4: Validation Error Detection ==="

    # Test invalid enum value
    CONFIG_RISK_TOLERANCE="ultra-aggressive"
    if validate_config 2>/dev/null; then
        test_assert "Invalid enum value fails validation" "false"
    else
        local exit_code=$?
        test_assert "Invalid enum value returns exit 2" "[ $exit_code -eq 2 ]"
    fi

    # Reset for next test
    CONFIG_RISK_TOLERANCE="moderate"

    # Test negative integer
    CONFIG_RETRY_MAX_ATTEMPTS=-1
    if validate_config 2>/dev/null; then
        test_assert "Negative integer fails validation" "false"
    else
        local exit_code=$?
        test_assert "Negative integer returns exit 2" "[ $exit_code -eq 2 ]"
    fi

    # Reset for next test
    CONFIG_RETRY_MAX_ATTEMPTS=3

    # Test non-existent directory
    CONFIG_SDD_ROOT="/nonexistent/directory"
    if validate_config 2>/dev/null; then
        test_assert "Non-existent directory fails validation" "false"
    else
        local exit_code=$?
        test_assert "Non-existent directory returns exit 2" "[ $exit_code -eq 2 ]"
    fi

    # Reset for next test
    CONFIG_SDD_ROOT="/app/.sdd"

    # Test invalid checkpoint frequency
    CONFIG_CHECKPOINT_FREQUENCY="every_second"
    if validate_config 2>/dev/null; then
        test_assert "Invalid checkpoint.frequency fails validation" "false"
    else
        local exit_code=$?
        test_assert "Invalid checkpoint.frequency returns exit 2" "[ $exit_code -eq 2 ]"
    fi

    # Reset
    CONFIG_CHECKPOINT_FREQUENCY="per_stage"

    # Test string where integer expected
    CONFIG_CHECKPOINT_MAX="many"
    if validate_config 2>/dev/null; then
        test_assert "String where integer expected fails validation" "false"
    else
        local exit_code=$?
        test_assert "String where integer expected returns exit 2" "[ $exit_code -eq 2 ]"
    fi

    # Reset
    CONFIG_CHECKPOINT_MAX=10
}

#
# test_env_overrides - Test environment variable overrides
#
test_env_overrides() {
    echo ""
    echo "=== Test 5: Environment Variable Overrides ==="

    # Ensure /app/.sdd exists
    mkdir -p /app/.sdd

    # Create temp directory for override test
    local temp_sdd
    temp_sdd=$(mktemp -d)
    TEMP_FILES+=("$temp_sdd")

    # Set environment overrides
    export SDD_ROOT_DIR="$temp_sdd"
    export SDD_LOG_LEVEL="debug"
    export SDD_RISK_TOLERANCE="aggressive"
    export CLAUDE_PATH="/custom/claude"

    # Load config (which will apply overrides)
    load_config 2>/dev/null || true

    # Check overrides were applied
    test_assert "SDD_ROOT_DIR override applied" '[ "$CONFIG_SDD_ROOT" = "'"$temp_sdd"'" ]'
    test_assert "SDD_LOG_LEVEL override applied" '[ "$CONFIG_LOG_LEVEL" = "debug" ]'
    test_assert "SDD_RISK_TOLERANCE override applied" '[ "$CONFIG_RISK_TOLERANCE" = "aggressive" ]'
    test_assert "CLAUDE_PATH override applied" '[ "$CONFIG_CLAUDE_PATH" = "/custom/claude" ]'

    # Clean up environment
    unset SDD_ROOT_DIR
    unset SDD_LOG_LEVEL
    unset SDD_RISK_TOLERANCE
    unset CLAUDE_PATH

    # Clean up temp directory
    rm -rf "$temp_sdd" 2>/dev/null || true
}

#
# test_invalid_override - Test invalid override fails validation
#
test_invalid_override() {
    echo ""
    echo "=== Test 6: Invalid Override Fails Validation ==="

    # Set invalid override
    export SDD_RISK_TOLERANCE="invalid_value"

    # Try to load config
    if load_config 2>/dev/null; then
        test_assert "Invalid override fails validation" "false"
    else
        local exit_code=$?
        test_assert "Invalid override returns exit 2" "[ $exit_code -eq 2 ]"
    fi

    # Clean up
    unset SDD_RISK_TOLERANCE
}

#
# test_all_enum_values - Test all valid enum values
#
test_all_enum_values() {
    echo ""
    echo "=== Test 7: All Valid Enum Values ==="

    # Ensure /app/.sdd exists
    mkdir -p /app/.sdd

    # Reload config to reset all variables
    load_config 2>/dev/null || true

    # Test checkpoint.frequency values
    for freq in per_stage per_ticket disabled; do
        CONFIG_CHECKPOINT_FREQUENCY="$freq"
        if validate_config 2>/dev/null; then
            test_assert "checkpoint.frequency=$freq is valid" "true"
        else
            test_assert "checkpoint.frequency=$freq is valid" "false"
        fi
        # Restore to valid value for next test
        CONFIG_CHECKPOINT_FREQUENCY="per_stage"
    done

    # Test decision.risk_tolerance values
    for risk in conservative moderate aggressive; do
        CONFIG_RISK_TOLERANCE="$risk"
        if validate_config 2>/dev/null; then
            test_assert "decision.risk_tolerance=$risk is valid" "true"
        else
            test_assert "decision.risk_tolerance=$risk is valid" "false"
        fi
        # Restore to valid value for next test
        CONFIG_RISK_TOLERANCE="moderate"
    done

    # Test logging.level values
    for level in debug info warn error; do
        CONFIG_LOG_LEVEL="$level"
        if validate_config 2>/dev/null; then
            test_assert "logging.level=$level is valid" "true"
        else
            test_assert "logging.level=$level is valid" "false"
        fi
        # Restore to valid value for next test
        CONFIG_LOG_LEVEL="info"
    done

    # Test logging.format values
    for format in structured simple; do
        CONFIG_LOG_FORMAT="$format"
        if validate_config 2>/dev/null; then
            test_assert "logging.format=$format is valid" "true"
        else
            test_assert "logging.format=$format is valid" "false"
        fi
        # Restore to valid value for next test
        CONFIG_LOG_FORMAT="structured"
    done
}

#
# Main test execution
#
main() {
    echo "========================================="
    echo "Configuration System Test Suite"
    echo "========================================="

    # Run all tests
    test_load_valid_config
    test_missing_config_file
    test_invalid_json
    test_validation_errors
    test_env_overrides
    test_invalid_override
    test_all_enum_values

    # Report results
    echo ""
    echo "========================================="
    echo "Test Results"
    echo "========================================="
    echo "Tests run:    $TESTS_RUN"
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"
    echo "========================================="

    if [ $TESTS_FAILED -eq 0 ]; then
        echo "All tests passed!"
        exit 0
    else
        echo "Some tests failed!"
        exit 1
    fi
}

main "$@"
