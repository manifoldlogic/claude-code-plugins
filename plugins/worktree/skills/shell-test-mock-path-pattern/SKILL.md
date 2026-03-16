---
name: shell-test-mock-path-pattern
description: Mock external commands in shell script tests using PATH override and invocation logging for assertion verification
origin: WTMERGE
created: 2026-02-11
tags: [testing, shell-scripting, mocking, test-pattern, worktree]
---

# Shell Test Mock PATH Pattern

## Overview

This skill documents the pattern for testing shell scripts that invoke external commands (like `crewchief`, `gh`, `jq`, etc.) without requiring those commands to be installed or configured. The pattern creates temporary mock executables, adds them to PATH for test execution, and logs invocations to a file for assertion verification.

This approach is used in `test-merge-worktree.sh` (977 lines, 103 tests) and provides a lightweight alternative to complex mocking frameworks. The pattern is particularly valuable for integration tests that verify argument passing and command orchestration without executing real operations.

## When to Use

Use this pattern when:

- Testing shell scripts that invoke external CLI tools (crewchief, gh, docker, etc.)
- You want to verify the script calls commands with correct arguments
- Real command execution would be slow, destructive, or require authentication
- You need to simulate command failures to test error handling paths
- You're writing integration tests that focus on coordination logic

Do not use this pattern for:

- Unit testing shell functions in isolation (use function mocking instead)
- End-to-end tests where real command execution is required
- Scripts that don't invoke external commands
- Tests where command output format matters more than invocation verification

## Pattern/Procedure

### Setup Phase: Create Mock Directory and Stub Commands

1. **Create temporary test directory with mock-bin:**
   ```bash
   setup() {
       TEST_TMP=$(mktemp -d)
       mkdir -p "$TEST_TMP/mock-bin"
       touch "$TEST_TMP/mock.log"
   }
   ```

2. **Create mock executable for each external command:**
   ```bash
   # Mock crewchief CLI
   cat > "$TEST_TMP/mock-bin/crewchief" << 'MOCKEOF'
   #!/bin/sh
   # Log invocation with all arguments
   echo "MOCK_CREWCHIEF_CALLED: $*" >> "${MOCK_LOG:-/dev/null}"
   # Return configurable exit code
   exit "${MOCK_CREWCHIEF_EXIT:-0}"
   MOCKEOF
   chmod +x "$TEST_TMP/mock-bin/crewchief"
   ```

3. **Create mocks for all external dependencies:**
   ```bash
   # Mock gh CLI
   cat > "$TEST_TMP/mock-bin/gh" << 'MOCKEOF'
   #!/bin/sh
   echo "MOCK_GH_CALLED: $*" >> "${MOCK_LOG:-/dev/null}"
   exit "${MOCK_GH_EXIT:-1}"  # Default: no PR found
   MOCKEOF
   chmod +x "$TEST_TMP/mock-bin/gh"

   # Mock workspace-folder.sh
   cat > "$TEST_TMP/mock-bin/workspace-folder.sh" << 'MOCKEOF'
   #!/bin/sh
   echo "MOCK_WORKSPACE_FOLDER_CALLED: $*" >> "${MOCK_LOG:-/dev/null}"
   exit 0
   MOCKEOF
   chmod +x "$TEST_TMP/mock-bin/workspace-folder.sh"
   ```

### Test Execution Phase: Override PATH and Capture Invocations

1. **Execute script under test with PATH override:**
   ```bash
   # Prepend mock-bin to PATH so mocks are found first
   PATH="$TEST_TMP/mock-bin:$PATH" \
   MOCK_LOG="$TEST_TMP/mock.log" \
   bash "$SCRIPT_UNDER_TEST" feature-x --repo myproject --yes 2>&1
   ```

2. **Set environment variables to control mock behavior:**
   ```bash
   # Simulate command failure
   MOCK_CREWCHIEF_EXIT=7 \
   PATH="$TEST_TMP/mock-bin:$PATH" \
   MOCK_LOG="$TEST_TMP/mock.log" \
   bash "$SCRIPT_UNDER_TEST" feature-x --repo myproject 2>&1 || exit_code=$?

   # Verify script handles failure correctly
   assert_exit_code "7" "$exit_code" "script exits 7 when merge fails"
   ```

### Verification Phase: Assert on Invocation Log

1. **Check that commands were called:**
   ```bash
   # Read mock log
   mock_log=$(cat "$TEST_TMP/mock.log")

   # Verify crewchief was invoked
   assert_contains "$mock_log" "MOCK_CREWCHIEF_CALLED" "crewchief was invoked"
   ```

2. **Verify arguments passed to commands:**
   ```bash
   # Verify specific arguments
   assert_contains "$mock_log" "worktree merge feature-x" "crewchief received correct args"
   assert_contains "$mock_log" "--strategy squash" "merge strategy passed through"
   ```

3. **Verify command sequence:**
   ```bash
   # Extract invocation order
   mock_log=$(cat "$TEST_TMP/mock.log")
   first_call=$(echo "$mock_log" | head -1)
   last_call=$(echo "$mock_log" | tail -1)

   assert_contains "$first_call" "MOCK_GH_CALLED" "PR check happens first"
   assert_contains "$last_call" "MOCK_WORKSPACE_FOLDER_CALLED" "workspace update happens last"
   ```

### Teardown Phase: Cleanup

```bash
teardown() {
    if [ -n "$TEST_TMP" ] && [ -d "$TEST_TMP" ]; then
        rm -rf "$TEST_TMP"
    fi
}

# Call teardown on test completion
trap teardown EXIT
```

## Examples

### Example 1: Basic Mock Setup and Execution

Test script structure:

```bash
#!/usr/bin/env zsh
SCRIPT_UNDER_TEST="plugins/worktree/skills/worktree-merge/scripts/merge-worktree.sh"

# Setup
TEST_TMP=$(mktemp -d)
mkdir -p "$TEST_TMP/mock-bin"
touch "$TEST_TMP/mock.log"

# Create mock crewchief
cat > "$TEST_TMP/mock-bin/crewchief" << 'EOF'
#!/bin/sh
echo "MOCK_CREWCHIEF_CALLED: $*" >> "${MOCK_LOG:-/dev/null}"
exit "${MOCK_CREWCHIEF_EXIT:-0}"
EOF
chmod +x "$TEST_TMP/mock-bin/crewchief"

# Create mock repo structure
mkdir -p "/workspace/repos/_test_$$/_test_$$"
mkdir -p "/workspace/repos/_test_$$/feature-x"

# Execute test
exit_code=0
output=$(
    PATH="$TEST_TMP/mock-bin:$PATH" \
    MOCK_LOG="$TEST_TMP/mock.log" \
    bash "$SCRIPT_UNDER_TEST" feature-x --repo "_test_$$" --yes 2>&1
) || exit_code=$?

# Verify
mock_log=$(cat "$TEST_TMP/mock.log")
if echo "$mock_log" | grep -q "worktree merge feature-x"; then
    echo "[PASS] crewchief invoked with correct args"
else
    echo "[FAIL] expected crewchief invocation"
fi

# Cleanup
rm -rf "$TEST_TMP" "/workspace/repos/_test_$$"
```

### Example 2: Simulating Command Failures

Test error handling by configuring mock exit codes:

```bash
# Test: Merge failure (exit code 7)
MOCK_CREWCHIEF_EXIT=7 \
PATH="$TEST_TMP/mock-bin:$PATH" \
MOCK_LOG="$TEST_TMP/mock.log" \
bash "$SCRIPT_UNDER_TEST" feature-x --repo myproject --yes 2>&1 || exit_code=$?

assert_exit_code "7" "$exit_code" "script exits 7 when crewchief merge fails"
```

This simulates `crewchief worktree merge` returning exit code 7, allowing you to test the script's error handling path.

### Example 3: Verifying Argument Passing

Test that arguments are correctly passed through to mocked commands:

```bash
# Execute with --strategy squash
PATH="$TEST_TMP/mock-bin:$PATH" \
MOCK_LOG="$TEST_TMP/mock.log" \
bash "$SCRIPT_UNDER_TEST" feature-x --repo myproject --strategy squash --yes 2>&1

# Verify strategy was passed to crewchief
mock_log=$(cat "$TEST_TMP/mock.log")
if echo "$mock_log" | grep -qF "worktree merge feature-x --strategy squash --yes"; then
    echo "[PASS] strategy argument passed through correctly"
else
    echo "[FAIL] strategy argument not found in crewchief invocation"
fi
```

### Example 4: Mocking Commands with Output

Some tests need mocks to produce output (not just log invocations):

```bash
# Mock gh that returns JSON PR status
cat > "$TEST_TMP/mock-bin/gh" << 'EOF'
#!/bin/sh
echo "MOCK_GH_CALLED: $*" >> "${MOCK_LOG:-/dev/null}"
if [ "$MOCK_GH_RETURN_PR" = "open" ]; then
    echo '{"state": "OPEN", "isDraft": false}'
    exit 0
elif [ "$MOCK_GH_RETURN_PR" = "merged" ]; then
    echo '{"state": "MERGED", "isDraft": false}'
    exit 0
else
    exit 1  # No PR found
fi
EOF
chmod +x "$TEST_TMP/mock-bin/gh"

# Test: PR status OPEN blocks merge
MOCK_GH_RETURN_PR="open" \
PATH="$TEST_TMP/mock-bin:$PATH" \
MOCK_LOG="$TEST_TMP/mock.log" \
bash "$SCRIPT_UNDER_TEST" feature-x --repo myproject --yes 2>&1 || exit_code=$?

assert_exit_code "8" "$exit_code" "script exits 8 when PR is OPEN"
```

### Example 5: Integration Test with Multiple Mocks

Full integration test verifying command sequence and coordination:

```bash
# Setup all mocks
setup_all_mocks() {
    cat > "$TEST_TMP/mock-bin/crewchief" << 'EOF'
#!/bin/sh
echo "STEP:crewchief $*" >> "${MOCK_LOG:-/dev/null}"
exit 0
EOF
    chmod +x "$TEST_TMP/mock-bin/crewchief"

    cat > "$TEST_TMP/mock-bin/gh" << 'EOF'
#!/bin/sh
echo "STEP:gh $*" >> "${MOCK_LOG:-/dev/null}"
exit 1  # No PR
EOF
    chmod +x "$TEST_TMP/mock-bin/gh"

    cat > "$TEST_TMP/mock-bin/workspace-folder.sh" << 'EOF'
#!/bin/sh
echo "STEP:workspace-folder $*" >> "${MOCK_LOG:-/dev/null}"
exit 0
EOF
    chmod +x "$TEST_TMP/mock-bin/workspace-folder.sh"
}

setup_all_mocks

# Execute
PATH="$TEST_TMP/mock-bin:$PATH" \
MOCK_LOG="$TEST_TMP/mock.log" \
bash "$SCRIPT_UNDER_TEST" feature-x --repo myproject --yes 2>&1

# Verify sequence
mock_log=$(cat "$TEST_TMP/mock.log")
echo "$mock_log" | grep -n "STEP:" | while IFS=: read -r line_num content; do
    echo "[$line_num] $content"
done

# Expected sequence:
# 1. gh (PR check)
# 2. crewchief (merge)
# 3. workspace-folder (workspace cleanup)
```

## Key Patterns and Best Practices

### 1. Heredoc with Quoted Delimiter

Use quoted heredoc delimiter to prevent variable expansion in mock scripts:

```bash
cat > "$TEST_TMP/mock-bin/command" << 'EOF'  # Note: 'EOF' is quoted
#!/bin/sh
echo "$*" >> "$MOCK_LOG"  # Variables expand at runtime, not creation time
EOF
```

### 2. Configurable Exit Codes

Make mocks return configurable exit codes for testing error paths:

```bash
exit "${MOCK_COMMAND_EXIT:-0}"  # Default to success, override via env var
```

### 3. Separate Setup and Teardown Functions

Isolate test state management:

```bash
setup() { ... }
teardown() { ... }
trap teardown EXIT
```

### 4. Descriptive Mock Log Prefixes

Use prefixes in log messages to distinguish mock sources:

```bash
echo "MOCK_CREWCHIEF_CALLED: $*" >> "$MOCK_LOG"
echo "MOCK_GH_CALLED: $*" >> "$MOCK_LOG"
```

### 5. Test in Subshells

Run tests in subshells to isolate environment variables:

```bash
exit_code=0
output=$(
    PATH="$TEST_TMP/mock-bin:$PATH" \
    MOCK_LOG="$TEST_TMP/mock.log" \
    bash "$SCRIPT_UNDER_TEST" args 2>&1
) || exit_code=$?
```

## Limitations

1. **Mock complexity**: Complex command outputs (multi-line JSON, streaming output) are harder to mock accurately.
2. **Path dependencies**: Scripts that use absolute paths bypass PATH mocking.
3. **Built-in commands**: Shell built-ins (cd, echo, test) cannot be mocked via PATH.
4. **Subprocess behavior**: Mocks don't replicate real command performance characteristics (latency, resource usage).

For these cases, consider:
- Using real commands with sandboxed environments
- Mocking at the function level instead of PATH level
- Integration tests with real commands in CI/CD

## References

- Ticket: WTMERGE
- Implementation: `plugins/worktree/skills/worktree-merge/scripts/test-merge-worktree.sh` (977 lines, 103 tests)
  - Lines 150-197: setup() function creating mock-bin and stub commands
  - Lines 500-599: Test execution with PATH override
  - Lines 546-643: Exit code tests using mock failures
- Test sections: Argument parsing, CWD auto-detection, exit codes, flag combinations, integration tests
- Related patterns: shell-script-input-validation (testing validation functions)
