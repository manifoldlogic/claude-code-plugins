#!/bin/bash
# Test runner for warn-sdd-refs.py hook
# Validates hook against all test cases from quality-strategy.md

set -e

HOOK_PATH="$(dirname "$0")/warn-sdd-refs.py"
TEST_DIR="/tmp/test-sdd-refs-$$"
FAILURES=0
TESTS_RUN=0

# Colors for output (if terminal supports it)
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    NC='\033[0m' # No Color
else
    GREEN=''
    RED=''
    YELLOW=''
    NC=''
fi

echo "============================================"
echo "warn-sdd-refs.py Hook Test Suite"
echo "============================================"
echo ""

# Verify hook exists
if [[ ! -f "$HOOK_PATH" ]]; then
    echo -e "${RED}ERROR: Hook not found at $HOOK_PATH${NC}"
    exit 1
fi

mkdir -p "$TEST_DIR"
mkdir -p "$TEST_DIR/plugins/sdd"

# Helper function to run test
run_test() {
    local test_name="$1"
    local file_content="$2"
    local file_path="$3"
    local expect_warning="$4"  # "yes" or "no"
    local env_vars="$5"        # Optional environment variables

    TESTS_RUN=$((TESTS_RUN + 1))
    echo "Test $TESTS_RUN: $test_name"

    # Create the test file
    mkdir -p "$(dirname "$file_path")"
    echo "$file_content" > "$file_path"

    # Generate tool_input JSON and run hook
    local json_input='{"tool_input": {"file_path": "'"$file_path"'"}}'
    local output

    if [[ -n "$env_vars" ]]; then
        output=$(echo "$json_input" | env $env_vars python3 "$HOOK_PATH" 2>&1)
    else
        output=$(echo "$json_input" | python3 "$HOOK_PATH" 2>&1)
    fi
    local exit_code=$?

    # Check if warning was produced
    local has_warning="no"
    if echo "$output" | grep -q "WARNING"; then
        has_warning="yes"
    fi

    # Verify exit code is always 0 (non-blocking)
    if [[ $exit_code -ne 0 ]]; then
        echo -e "  ${RED}FAIL: Exit code $exit_code (expected 0)${NC}"
        FAILURES=$((FAILURES + 1))
        return
    fi

    # Check expected behavior
    if [[ "$expect_warning" == "yes" && "$has_warning" == "yes" ]]; then
        echo -e "  ${GREEN}PASS${NC}"
    elif [[ "$expect_warning" == "no" && "$has_warning" == "no" ]]; then
        echo -e "  ${GREEN}PASS${NC}"
    elif [[ "$expect_warning" == "yes" && "$has_warning" == "no" ]]; then
        echo -e "  ${RED}FAIL: Expected warning but none produced${NC}"
        FAILURES=$((FAILURES + 1))
    else
        echo -e "  ${RED}FAIL: Unexpected warning produced${NC}"
        echo "  Output: $output"
        FAILURES=$((FAILURES + 1))
    fi
}

echo "--- Basic Detection Tests ---"
echo ""

# Test 1: Production code with .sdd/ path reference - should warn
run_test "Production code with .sdd/ reference" \
    'const path = ".sdd/tickets/";' \
    "$TEST_DIR/config.ts" \
    "yes"

# Test 2: Production code with SDD_ROOT_DIR - should warn
run_test "Production code with SDD_ROOT_DIR variable" \
    'const root = process.env.SDD_ROOT_DIR;' \
    "$TEST_DIR/app.js" \
    "yes"

# Test 3: Production code with ${SDD_ROOT expansion - should warn
run_test "Production code with \${SDD_ROOT expansion" \
    'path="${SDD_ROOT}/tickets"' \
    "$TEST_DIR/script.sh" \
    "yes"

# Test 4: Production code with /app/.sdd path - should warn
run_test "Production code with /app/.sdd hardcoded path" \
    'const dir = "/app/.sdd/tickets";' \
    "$TEST_DIR/hardcoded.ts" \
    "yes"

echo ""
echo "--- Exclusion Tests (Should NOT Warn) ---"
echo ""

# Test 5: Plugin file with .sdd reference - should NOT warn
run_test "Plugin file with .sdd reference" \
    'SDD_ROOT_DIR = "/app/.sdd"' \
    "$TEST_DIR/plugins/sdd/test.py" \
    "no"

# Test 6: Clean code file - should NOT warn
run_test "Clean code file without .sdd references" \
    'export function helper() { return true; }' \
    "$TEST_DIR/utils.ts" \
    "no"

# Test 7: Documentation file with .sdd reference - should NOT warn
run_test "Documentation file (.md) with .sdd reference" \
    'Configure SDD_ROOT_DIR in your environment' \
    "$TEST_DIR/setup.md" \
    "no"

# Test 8: JSON config file in plugins - should NOT warn
run_test "JSON config file in plugins with .sdd reference" \
    '{"path": ".sdd/tickets"}' \
    "$TEST_DIR/plugins/sdd/config.json" \
    "no"

echo ""
echo "--- False Positive Tests (Should NOT Warn) ---"
echo ""

# Test 9: Variable named config_sdd_enabled - should NOT warn (no word boundary match)
run_test "Variable config_sdd_enabled (no _ROOT_DIR)" \
    'const config_sdd_enabled = true;' \
    "$TEST_DIR/settings.ts" \
    "no"

# Test 10: Path like .sddconfig/ - should NOT warn (different directory)
run_test "Path .sddconfig/ (different directory name)" \
    'const path = ".sddconfig/settings.json";' \
    "$TEST_DIR/config2.ts" \
    "no"

# Test 11: Variable MY_SDD_CONFIG - should NOT warn (no _ROOT_DIR suffix)
run_test "Variable MY_SDD_CONFIG (not SDD_ROOT_DIR)" \
    'const MY_SDD_CONFIG = { enabled: true };' \
    "$TEST_DIR/myconfig.ts" \
    "no"

# Test 12: Comment mentioning SDD workflow - should NOT warn in .md file
run_test "Comment about SDD workflow in markdown" \
    '# The SDD workflow helps with planning' \
    "$TEST_DIR/workflow.md" \
    "no"

# Test 13: Pattern sdd without trailing slash - should NOT warn
run_test "Variable sdd_config without path separator" \
    'const sdd_config = { enabled: true };' \
    "$TEST_DIR/nosep.ts" \
    "no"

echo ""
echo "--- Bypass Mechanism Tests ---"
echo ""

# Test 14: Environment variable bypass
echo "Test $((TESTS_RUN + 1)): Environment variable bypass (SDD_SKIP_REF_CHECK=true)"
TESTS_RUN=$((TESTS_RUN + 1))
echo 'const path = ".sdd/tickets/";' > "$TEST_DIR/bypass_env.ts"
json_input='{"tool_input": {"file_path": "'"$TEST_DIR/bypass_env.ts"'"}}'
output=$(echo "$json_input" | SDD_SKIP_REF_CHECK=true python3 "$HOOK_PATH" 2>&1)
if echo "$output" | grep -q "WARNING"; then
    echo -e "  ${RED}FAIL: Environment bypass did not work${NC}"
    FAILURES=$((FAILURES + 1))
else
    echo -e "  ${GREEN}PASS${NC}"
fi

# Test 15: Comment bypass
echo "Test $((TESTS_RUN + 1)): Comment bypass (# sdd-ref-check: ignore)"
TESTS_RUN=$((TESTS_RUN + 1))
cat > "$TEST_DIR/bypass_comment.ts" << 'EOF'
// This file needs .sdd references for testing
// sdd-ref-check: ignore
const path = ".sdd/tickets/";
const root = process.env.SDD_ROOT_DIR;
EOF
json_input='{"tool_input": {"file_path": "'"$TEST_DIR/bypass_comment.ts"'"}}'
output=$(echo "$json_input" | python3 "$HOOK_PATH" 2>&1)
if echo "$output" | grep -q "WARNING"; then
    echo -e "  ${RED}FAIL: Comment bypass did not work${NC}"
    FAILURES=$((FAILURES + 1))
else
    echo -e "  ${GREEN}PASS${NC}"
fi

echo ""
echo "--- Edge Case Tests ---"
echo ""

# Test 16: Malformed JSON input - should handle gracefully
echo "Test $((TESTS_RUN + 1)): Malformed JSON input"
TESTS_RUN=$((TESTS_RUN + 1))
output=$(echo "not json at all" | python3 "$HOOK_PATH" 2>&1)
exit_code=$?
if [[ $exit_code -eq 0 ]]; then
    echo -e "  ${GREEN}PASS${NC}"
else
    echo -e "  ${RED}FAIL: Should exit 0 even on malformed input (got $exit_code)${NC}"
    FAILURES=$((FAILURES + 1))
fi

# Test 17: Empty tool_input - should handle gracefully
echo "Test $((TESTS_RUN + 1)): Empty tool_input"
TESTS_RUN=$((TESTS_RUN + 1))
output=$(echo '{"tool_input": {}}' | python3 "$HOOK_PATH" 2>&1)
exit_code=$?
if [[ $exit_code -eq 0 ]]; then
    echo -e "  ${GREEN}PASS${NC}"
else
    echo -e "  ${RED}FAIL: Should exit 0 on empty tool_input (got $exit_code)${NC}"
    FAILURES=$((FAILURES + 1))
fi

# Test 18: Missing file - should handle gracefully
echo "Test $((TESTS_RUN + 1)): Missing file"
TESTS_RUN=$((TESTS_RUN + 1))
output=$(echo '{"tool_input": {"file_path": "/nonexistent/file.ts"}}' | python3 "$HOOK_PATH" 2>&1)
exit_code=$?
if [[ $exit_code -eq 0 ]]; then
    echo -e "  ${GREEN}PASS${NC}"
else
    echo -e "  ${RED}FAIL: Should exit 0 on missing file (got $exit_code)${NC}"
    FAILURES=$((FAILURES + 1))
fi

# Test 19: Multiple patterns in same file - should warn once with all matches
echo "Test $((TESTS_RUN + 1)): Multiple patterns in same file"
TESTS_RUN=$((TESTS_RUN + 1))
cat > "$TEST_DIR/multi_pattern.ts" << 'EOF'
const sddPath = ".sdd/tickets/";
const root = process.env.SDD_ROOT_DIR;
const hardcoded = "/app/.sdd/logs";
EOF
json_input='{"tool_input": {"file_path": "'"$TEST_DIR/multi_pattern.ts"'"}}'
output=$(echo "$json_input" | python3 "$HOOK_PATH" 2>&1)
warning_count=$(echo "$output" | grep -c "Line" || true)
if [[ $warning_count -ge 3 ]]; then
    echo -e "  ${GREEN}PASS${NC} (found $warning_count pattern matches)"
else
    echo -e "  ${RED}FAIL: Expected 3+ pattern matches, found $warning_count${NC}"
    FAILURES=$((FAILURES + 1))
fi

# Test 20: Large file (>100KB) - should skip
echo "Test $((TESTS_RUN + 1)): Large file (>100KB) should be skipped"
TESTS_RUN=$((TESTS_RUN + 1))
# Create a file larger than 100KB with .sdd reference
{
    echo 'const path = ".sdd/tickets/";'
    # Add enough lines to exceed 100KB
    for i in $(seq 1 3000); do
        echo "// This is padding line $i to make the file large enough to exceed 100KB limit for performance testing"
    done
} > "$TEST_DIR/large_file.ts"
file_size=$(wc -c < "$TEST_DIR/large_file.ts")
json_input='{"tool_input": {"file_path": "'"$TEST_DIR/large_file.ts"'"}}'
output=$(echo "$json_input" | python3 "$HOOK_PATH" 2>&1)
if echo "$output" | grep -q "WARNING"; then
    echo -e "  ${RED}FAIL: Large file ($file_size bytes) should be skipped${NC}"
    FAILURES=$((FAILURES + 1))
else
    echo -e "  ${GREEN}PASS${NC} (file size: $file_size bytes)"
fi

# Test 21: File in .sdd directory - should NOT warn
echo "Test $((TESTS_RUN + 1)): File in .sdd directory"
TESTS_RUN=$((TESTS_RUN + 1))
mkdir -p "$TEST_DIR/.sdd/tickets"
echo 'SDD_ROOT_DIR = "/app/.sdd"' > "$TEST_DIR/.sdd/tickets/planning.md"
json_input='{"tool_input": {"file_path": "'"$TEST_DIR/.sdd/tickets/planning.md"'"}}'
output=$(echo "$json_input" | python3 "$HOOK_PATH" 2>&1)
if echo "$output" | grep -q "WARNING"; then
    echo -e "  ${RED}FAIL: Files in .sdd directory should not warn${NC}"
    FAILURES=$((FAILURES + 1))
else
    echo -e "  ${GREEN}PASS${NC}"
fi

echo ""
echo "============================================"
echo "Cleanup"
echo "============================================"
rm -rf "$TEST_DIR"
echo "Temporary files cleaned up: $TEST_DIR"

echo ""
echo "============================================"
echo "Test Results"
echo "============================================"
echo ""
echo "Tests run: $TESTS_RUN"
if [[ $FAILURES -eq 0 ]]; then
    echo -e "${GREEN}All tests PASSED${NC}"
    exit 0
else
    echo -e "${RED}$FAILURES test(s) FAILED${NC}"
    exit 1
fi
