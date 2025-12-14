#!/usr/bin/env bash
#
# Test Harness Framework for SDD Automation
# Provides assertion functions and test runner with isolation
#

set -euo pipefail

# Global counters
TESTS_PASSED=0
TESTS_FAILED=0
# Reserved for future skip functionality
# shellcheck disable=SC2034
TESTS_SKIPPED=0
VERBOSE=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#
# Assertion Functions
#

# Compare expected and actual values
# Usage: assert_equals "expected" "actual" "description"
assert_equals() {
    local expected="$1"
    local actual="$2"
    local description="${3:-}"

    if [[ "$expected" == "$actual" ]]; then
        echo -e "  ${GREEN}PASS${NC}: ${description}"
        return 0
    else
        echo -e "  ${RED}FAIL${NC}: ${description}"
        echo "    Expected: '$expected'"
        echo "    Actual:   '$actual'"
        return 1
    fi
}

# Check expression is truthy (exit 0)
# Usage: assert_true command "description"
assert_true() {
    local description="${2:-}"

    if eval "$1" &>/dev/null; then
        echo -e "  ${GREEN}PASS${NC}: ${description}"
        return 0
    else
        echo -e "  ${RED}FAIL${NC}: ${description}"
        echo "    Expression evaluated to false: $1"
        return 1
    fi
}

# Check expression is falsy (exit non-0)
# Usage: assert_false command "description"
assert_false() {
    local description="${2:-}"

    if ! eval "$1" &>/dev/null; then
        echo -e "  ${GREEN}PASS${NC}: ${description}"
        return 0
    else
        echo -e "  ${RED}FAIL${NC}: ${description}"
        echo "    Expression evaluated to true: $1"
        return 1
    fi
}

# Check file exists
# Usage: assert_file_exists "/path/to/file" "description"
assert_file_exists() {
    local file_path="$1"
    local description="${2:-File $file_path should exist}"

    if [[ -f "$file_path" ]]; then
        echo -e "  ${GREEN}PASS${NC}: ${description}"
        return 0
    else
        echo -e "  ${RED}FAIL${NC}: ${description}"
        echo "    File not found: $file_path"
        return 1
    fi
}

# Check string contains substring
# Usage: assert_contains "haystack" "needle" "description"
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local description="${3:-}"

    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "  ${GREEN}PASS${NC}: ${description}"
        return 0
    else
        echo -e "  ${RED}FAIL${NC}: ${description}"
        echo "    String: '$haystack'"
        echo "    Does not contain: '$needle'"
        return 1
    fi
}

# Check command exits with expected code
# Usage: assert_exit_code expected_code command "description"
assert_exit_code() {
    local expected_code="$1"
    shift
    local description="${*: -1}"
    local command="${*:1:$(($#-1))}"

    local actual_code=0
    eval "$command" &>/dev/null || actual_code=$?

    if [[ "$expected_code" -eq "$actual_code" ]]; then
        echo -e "  ${GREEN}PASS${NC}: ${description}"
        return 0
    else
        echo -e "  ${RED}FAIL${NC}: ${description}"
        echo "    Expected exit code: $expected_code"
        echo "    Actual exit code:   $actual_code"
        return 1
    fi
}

# Check values are not equal
# Usage: assert_not_equals "unexpected" "actual" "description"
assert_not_equals() {
    local unexpected="$1"
    local actual="$2"
    local description="${3:-}"

    if [[ "$unexpected" != "$actual" ]]; then
        echo -e "  ${GREEN}PASS${NC}: ${description}"
        return 0
    else
        echo -e "  ${RED}FAIL${NC}: ${description}"
        echo "    Should not be: '$unexpected'"
        echo "    Actual:        '$actual'"
        return 1
    fi
}

# Check string does not contain substring
# Usage: assert_not_contains "haystack" "needle" "description"
assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local description="${3:-}"

    if [[ "$haystack" != *"$needle"* ]]; then
        echo -e "  ${GREEN}PASS${NC}: ${description}"
        return 0
    else
        echo -e "  ${RED}FAIL${NC}: ${description}"
        echo "    String: '$haystack'"
        echo "    Should not contain: '$needle'"
        return 1
    fi
}

# Check file contains text
# Usage: assert_file_contains "/path/to/file" "text" "description"
assert_file_contains() {
    local file_path="$1"
    local text="$2"
    local description="${3:-File should contain text}"

    if [[ ! -f "$file_path" ]]; then
        echo -e "  ${RED}FAIL${NC}: ${description}"
        echo "    File not found: $file_path"
        return 1
    fi

    if grep -q "$text" "$file_path" 2>/dev/null; then
        echo -e "  ${GREEN}PASS${NC}: ${description}"
        return 0
    else
        echo -e "  ${RED}FAIL${NC}: ${description}"
        echo "    File: $file_path"
        echo "    Does not contain: '$text'"
        return 1
    fi
}

# Check file does not contain text
# Usage: assert_file_not_contains "/path/to/file" "text" "description"
assert_file_not_contains() {
    local file_path="$1"
    local text="$2"
    local description="${3:-File should not contain text}"

    if [[ ! -f "$file_path" ]]; then
        echo -e "  ${RED}FAIL${NC}: ${description}"
        echo "    File not found: $file_path"
        return 1
    fi

    if ! grep -q "$text" "$file_path" 2>/dev/null; then
        echo -e "  ${GREEN}PASS${NC}: ${description}"
        return 0
    else
        echo -e "  ${RED}FAIL${NC}: ${description}"
        echo "    File: $file_path"
        echo "    Should not contain: '$text'"
        return 1
    fi
}

# Simple pass/fail helpers for custom tests
pass() {
    local description="${1:-Test passed}"
    echo -e "  ${GREEN}PASS${NC}: ${description}"
    return 0
}

fail() {
    local description="${1:-Test failed}"
    echo -e "  ${RED}FAIL${NC}: ${description}"
    return 1
}

# Run a single test function and track results
# Usage: run_test test_function_name
run_test() {
    local test_func="$1"
    if ( $test_func ); then
        ((TESTS_PASSED++)) || true
        return 0
    else
        ((TESTS_FAILED++)) || true
        return 1
    fi
}

# Print test summary
print_summary() {
    local total=$((TESTS_PASSED + TESTS_FAILED))
    echo "Tests run:    $total"
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "All tests passed!"
        return 0
    else
        return 1
    fi
}

#
# Test Runner
#

# Run tests matching pattern
# Usage: run_tests [pattern] [-v|--verbose]
run_tests() {
    local test_pattern="test_"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            *)
                test_pattern="$1"
                shift
                ;;
        esac
    done

    # Reset counters
    TESTS_PASSED=0
    TESTS_FAILED=0
    # shellcheck disable=SC2034
    TESTS_SKIPPED=0

    # Discover tests
    local tests
    tests=$(declare -F | awk '{print $3}' | grep "^${test_pattern}" || true)

    if [[ -z "$tests" ]]; then
        echo -e "${YELLOW}No tests found matching pattern: ${test_pattern}${NC}"
        return 1
    fi

    local total_tests
    total_tests=$(echo "$tests" | wc -l)

    echo "Discovered $total_tests test(s) matching '${test_pattern}'"
    echo ""

    # Run each test in isolated subshell
    local test_func
    while IFS= read -r test_func; do
        echo "Running: $test_func"

        # Run test in subshell for isolation
        if ( $test_func ); then
            ((TESTS_PASSED++)) || true
            if [[ "$VERBOSE" == true ]]; then
                echo -e "${GREEN}✓${NC} Test passed\n"
            else
                echo ""
            fi
        else
            ((TESTS_FAILED++)) || true
            if [[ "$VERBOSE" == true ]]; then
                echo -e "${RED}✗${NC} Test failed\n"
            else
                echo ""
            fi
        fi
    done <<< "$tests"

    # Print summary
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}Results: $TESTS_PASSED passed, $TESTS_FAILED failed${NC}"
        return 0
    else
        echo -e "${RED}Results: $TESTS_PASSED passed, $TESTS_FAILED failed${NC}"
        return 1
    fi
}

# Show usage information
show_usage() {
    cat <<EOF
Test Harness Framework

Usage: source test-harness.sh

Assertion Functions:
  assert_equals "expected" "actual" "description"
  assert_true "command" "description"
  assert_false "command" "description"
  assert_file_exists "/path/to/file" "description"
  assert_contains "haystack" "needle" "description"
  assert_exit_code expected_code command "description"

Test Runner:
  run_tests [pattern] [-v|--verbose]

  pattern   - Optional test name pattern (default: "test_")
  -v        - Verbose mode for detailed output

Examples:
  # Run all tests
  run_tests

  # Run tests matching pattern
  run_tests "test_config_"

  # Run with verbose output
  run_tests -v

  # Run specific pattern with verbose
  run_tests "test_parse_" -v

Test Functions:
  - Must start with "test_" prefix (or match custom pattern)
  - Run in isolated subshells (state changes don't persist)
  - Should use assertion functions for checks
  - Return 0 for pass, non-0 for fail

Example Test:
  test_example_addition() {
      local result=\$((2 + 2))
      assert_equals "4" "\$result" "2 + 2 should equal 4"
  }

EOF
}

# If script is executed directly (not sourced), show usage
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    show_usage
    exit 0
fi
