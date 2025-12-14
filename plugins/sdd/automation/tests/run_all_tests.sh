#!/usr/bin/env bash
#
# run_all_tests.sh - Run all test suites and generate summary
#
# Executes all test files in the tests/ directory and provides
# a comprehensive summary of results.
#

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test tracking
TOTAL_TESTS=0
TOTAL_PASSED=0
TOTAL_FAILED=0
SUITE_COUNT=0

echo "========================================="
echo "Running All Test Suites"
echo "========================================="
echo

# Array of test files to run
TEST_FILES=(
    "test_configuration.sh"
    "test_common_utilities.sh"
    "test_module_loading.sh"
    "test_run_initializer.sh"
    "test_security.sh"
    "test_integration.sh"
)

# Run each test suite
for test_file in "${TEST_FILES[@]}"; do
    test_path="${SCRIPT_DIR}/${test_file}"

    if [[ ! -f "$test_path" ]]; then
        echo -e "${YELLOW}SKIP${NC}: $test_file (not found)"
        continue
    fi

    echo -e "${BLUE}Running${NC}: $test_file"
    ((SUITE_COUNT++))

    # Run test and capture output
    if output=$(bash "$test_path" 2>&1); then
        status="${GREEN}PASS${NC}"
    else
        status="${RED}FAIL${NC}"
    fi

    # Extract test counts from output
    tests_run=$(echo "$output" | grep "Tests run:" | awk '{print $3}' || echo "0")
    tests_passed=$(echo "$output" | grep "Tests passed:" | awk '{print $3}' || echo "0")
    tests_failed=$(echo "$output" | grep "Tests failed:" | awk '{print $3}' || echo "0")

    # Accumulate totals
    TOTAL_TESTS=$((TOTAL_TESTS + tests_run))
    TOTAL_PASSED=$((TOTAL_PASSED + tests_passed))
    TOTAL_FAILED=$((TOTAL_FAILED + tests_failed))

    # Print suite result
    echo -e "  Status: $status"
    echo -e "  Tests: ${tests_run} run, ${tests_passed} passed, ${tests_failed} failed"
    echo

    # Show failures if any
    if [[ $tests_failed -gt 0 ]]; then
        echo "  Failure output:"
        echo "$output" | grep -A 2 "FAIL" || true
        echo
    fi
done

echo "========================================="
echo "Test Summary"
echo "========================================="
echo "Suites run:    $SUITE_COUNT"
echo "Tests run:     $TOTAL_TESTS"
echo "Tests passed:  $TOTAL_PASSED"
echo "Tests failed:  $TOTAL_FAILED"
echo

if [[ $TOTAL_FAILED -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi
