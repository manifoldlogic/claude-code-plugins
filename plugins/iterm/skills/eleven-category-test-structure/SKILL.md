---
name: eleven-category-test-structure
description: Standard 11-category test organization for iTerm plugin shell scripts
origin: PANE-001
created: 2026-02-08
tags: [iterm, testing, quality-assurance, bash-testing]
---

# Eleven-Category Test Structure

## Overview

All unit tests for iTerm plugin shell scripts follow an 11-category organizational structure. This pattern was established in `test-iterm-plugin.sh` (87 tests for tab-management scripts) and is enforced for all new iTerm scripts to ensure consistent, comprehensive test coverage.

Each category targets a specific aspect of script behavior, ensuring no critical functionality is missed during testing.

## When to Use

Apply this structure when:

- Creating tests for any iTerm plugin shell script
- Reviewing test coverage for existing scripts
- Planning test implementation during ticket planning phase
- Verifying test completeness before merging pull requests

## Pattern/Procedure

### The Eleven Categories

Every iTerm script test suite must include tests in all eleven categories:

#### 1. Script Existence (2 tests minimum)

**Purpose:** Verify the script file exists and has correct permissions

**Tests:**
- Script file exists at expected path
- Script is executable (`chmod +x`)

**Example:**
```bash
test_script_exists() {
    [[ -f "$SCRIPT_UNDER_TEST" ]]
}

test_script_is_executable() {
    [[ -x "$SCRIPT_UNDER_TEST" ]]
}
```

#### 2. Help/Usage (3 tests minimum)

**Purpose:** Verify help text is complete and accessible

**Tests:**
- `-h` shows usage text containing "USAGE" and "OPTIONS"
- `--help` shows full help with all documented flags
- Help exits with code 0

**Example:**
```bash
test_help_short_flag() {
    local output
    output=$("$SCRIPT_UNDER_TEST" -h 2>&1) || true
    assert_output_contains "$output" "USAGE"
}
```

#### 3. Dry-Run Mode (4-5 tests minimum)

**Purpose:** Verify dry-run generates correct AppleScript without execution

**Tests:**
- `--dry-run` outputs `tell application "iTerm2"`
- `--dry-run` with default arguments generates expected AppleScript
- `--dry-run` with custom arguments reflects those arguments
- `--dry-run` exits with code 0
- Dry-run output contains expected operation (split, create, etc.)

**Example:**
```bash
test_dry_run_default() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run 2>&1)
    assert_output_contains "$output" "tell application \"iTerm2\""
}
```

#### 4. Argument Parsing (6-8 tests minimum)

**Purpose:** Verify all flags are parsed correctly

**Tests:**
- Each flag (short form) is parsed
- Each flag (long form) is parsed
- Flag values appear correctly in dry-run output
- Multiple flags can be combined

**Example:**
```bash
test_parse_direction_vertical() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -d vertical 2>&1)
    assert_output_contains "$output" "split vertically"
}
```

#### 5. Exit Codes (4-5 tests minimum)

**Purpose:** Verify error conditions produce correct exit codes

**Tests:**
- Invalid flag exits with code 3
- Missing required value exits with code 3
- Invalid argument value exits with code 3
- Successful operations exit with code 0

**Example:**
```bash
test_invalid_flag_exit_code() {
    "$SCRIPT_UNDER_TEST" --invalid-flag >/dev/null 2>&1 || true
    local exit_code=$?
    assert_exit_code "3" "$exit_code"
}
```

**Exit code reference:**
- 0: Success
- 1: Connection failure (SSH)
- 2: iTerm unavailable
- 3: Invalid arguments
- 4: No match (for close-tab pattern matching)

#### 6. AppleScript Structure (4-5 tests minimum)

**Purpose:** Verify generated AppleScript has correct structure

**Tests:**
- Output contains `activate`
- Output contains `first window` (or appropriate target)
- Output contains `end tell`
- Output contains expected operation command
- Output contains window count check (if applicable)

**Example:**
```bash
test_applescript_contains_activate() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run 2>&1)
    assert_output_contains "$output" "activate"
}
```

#### 7. Error Paths (3-4 tests minimum)

**Purpose:** Verify error handling for bad input

**Tests:**
- Unknown flag rejected with error message
- Unexpected positional argument rejected
- Invalid values rejected with meaningful error messages

**Example:**
```bash
test_unknown_flag_error() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --foo 2>&1) || true
    assert_output_contains "$output" "ERROR" || assert_output_contains "$output" "Unknown"
}
```

#### 8. Combined Options (2-3 tests minimum)

**Purpose:** Verify multiple flags work together

**Tests:**
- All options combined produce correct output
- Subsets of options work correctly
- Options order doesn't matter

**Example:**
```bash
test_combined_all_options() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -d vertical -p "Custom" -c "echo test" -n "Test Pane" 2>&1)
    assert_output_contains "$output" "split vertically" &&
    assert_output_contains "$output" "Custom" &&
    assert_output_contains "$output" "echo test" &&
    assert_output_contains "$output" "Test Pane"
}
```

#### 9. Context Detection (1-2 tests minimum)

**Purpose:** Verify script can source utilities and detect environment

**Tests:**
- Utils sourcing succeeds (or script sources utils successfully)
- Exit code constants are defined
- Functions from utils are available

**Example:**
```bash
test_utils_sourcing() {
    # Verify utils can be sourced
    local utils_path="$SCRIPT_DIR/../../tab-management/scripts/iterm-utils.sh"
    [[ -f "$utils_path" ]]
}
```

#### 10. Edge Cases (3-4 tests minimum)

**Purpose:** Verify handling of special characters and complex inputs

**Tests:**
- Names with spaces are handled correctly
- Commands with `&&` or other shell metacharacters are escaped
- Profile names with spaces work
- Names with quotes are escaped in AppleScript

**Example:**
```bash
test_name_with_spaces() {
    local output
    output=$("$SCRIPT_UNDER_TEST" --dry-run -n "My Test Pane" 2>&1)
    assert_output_contains "$output" "My Test Pane"
}
```

#### 11. Shell Compatibility (2 tests minimum)

**Purpose:** Verify script structure and shell configuration

**Tests:**
- Shebang is `#!/usr/bin/env bash`
- Script uses `set -euo pipefail` (strict mode)

**Example:**
```bash
test_shebang_correct() {
    local first_line
    first_line=$(head -n 1 "$SCRIPT_UNDER_TEST")
    [[ "$first_line" == "#!/usr/bin/env bash" ]]
}

test_strict_mode() {
    grep -q "set -euo pipefail" "$SCRIPT_UNDER_TEST"
}
```

### Test Count Requirements

**Minimum:** 30 tests total (average ~3 per category)
**Target:** 40+ tests for comprehensive coverage
**Example:** test-split-pane.sh has 42 tests across all 11 categories

### Test Framework Template

```bash
#!/usr/bin/env bash
set -euo pipefail

##############################################################################
# Test Framework Variables
##############################################################################

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
SCRIPT_UNDER_TEST="../scripts/script-name.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

##############################################################################
# Test Framework Functions
##############################################################################

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "  ${GREEN}[PASS]${NC} $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "  ${RED}[FAIL]${NC} $1"
}

run_test() {
    local test_name="$1"
    local test_func="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if $test_func; then
        pass "$test_name"
    else
        fail "$test_name"
    fi
}

assert_exit_code() {
    [[ "$1" == "$2" ]]
}

assert_output_contains() {
    [[ "$1" == *"$2"* ]]
}

section() {
    echo ""
    echo "=== $1 ==="
}

##############################################################################
# Test Categories (11 sections)
##############################################################################

run_existence_tests() {
    section "Script Existence Tests"
    # ... tests ...
}

run_help_tests() {
    section "Help/Usage Tests"
    # ... tests ...
}

# ... 9 more category runners ...

##############################################################################
# Test Execution
##############################################################################

main() {
    echo "Testing: $SCRIPT_UNDER_TEST"

    run_existence_tests
    run_help_tests
    run_dry_run_tests
    run_argument_parsing_tests
    run_exit_code_tests
    run_applescript_structure_tests
    run_error_path_tests
    run_combined_options_tests
    run_context_detection_tests
    run_edge_case_tests
    run_shell_compatibility_tests

    echo ""
    echo "=== Test Summary ==="
    echo "Tests run:    $TESTS_RUN"
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        exit 1
    fi
}

main "$@"
```

## Examples

### Example 1: test-split-pane.sh

Complete implementation with all 11 categories:

```
plugins/iterm/skills/pane-management/tests/test-split-pane.sh
- 548 lines total
- 42 tests across 11 categories
- All tests passing (42/42)
- Model implementation for new test suites
```

**Test distribution:**
- Script Existence: 2 tests
- Help/Usage: 3 tests
- Dry-Run Mode: 5 tests
- Argument Parsing: 8 tests
- Exit Codes: 5 tests
- AppleScript Structure: 5 tests
- Error Paths: 3 tests
- Combined Options: 3 tests
- Context Detection: 2 tests
- Edge Cases: 4 tests
- Shell Compatibility: 2 tests

### Example 2: test-iterm-plugin.sh

Original test suite that established this pattern:

```
plugins/iterm/skills/tab-management/tests/test-iterm-plugin.sh
- 87 tests total for 3 scripts
- Average ~29 tests per script
- Same 11-category structure
```

### Example 3: Test Execution Output

```
Testing: ../scripts/iterm-split-pane.sh

=== Script Existence Tests ===
  [PASS] split-pane: script file exists
  [PASS] split-pane: script is executable

=== Help/Usage Tests ===
  [PASS] split-pane: -h shows USAGE and OPTIONS
  [PASS] split-pane: --help shows all flags
  [PASS] split-pane: help exits with code 0

... (9 more categories) ...

=== Test Summary ===
Tests run:    42
Tests passed: 42
Tests failed: 0
All tests passed!
```

## References

- Ticket: PANE-001
- Related files:
  - `plugins/iterm/skills/pane-management/tests/test-split-pane.sh` (548 lines, 42 tests, model implementation)
  - `plugins/iterm/skills/tab-management/tests/test-iterm-plugin.sh` (87 tests for 3 scripts, original pattern)
- Quality strategy document: `archive/tickets/PANE-001_core-split-script/planning/quality-strategy.md` (test categories defined, lines 30-49)
