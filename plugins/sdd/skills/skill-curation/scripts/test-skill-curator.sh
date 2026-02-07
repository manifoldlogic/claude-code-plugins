#!/bin/sh
# test-skill-curator.sh - Test suite for skill-curator agent validation rules
#
# Covers:
#   - Skill name length validation (40-character maximum, enforced)
#   - Boundary tests: 39 chars (accept), 40 chars (accept), 41 chars (reject), 50 chars (reject)
#
# Since skill-curator is a markdown agent definition, this test validates the
# documented validation logic by implementing and testing the length-check
# function that the agent is instructed to use.
#
# POSIX-compatible (no bash-only features).

set -e

# --- Test counters ---
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# --- Cleanup tracking ---
CLEANUP_DIRS=""

# --- Helpers ---
pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf "  PASS: %s\n" "$1"
}

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf "  FAIL: %s\n" "$1"
  if [ -n "$2" ]; then
    printf "    Expected: %s\n" "$2"
  fi
  if [ -n "$3" ]; then
    printf "    Got:      %s\n" "$3"
  fi
}

run_test() {
  TESTS_RUN=$((TESTS_RUN + 1))
  printf "Test %d: %s\n" "${TESTS_RUN}" "$1"
}

# Create a temporary directory and register it for cleanup
make_temp_dir() {
  _tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/test-skill-curator.XXXXXX")
  CLEANUP_DIRS="${CLEANUP_DIRS} ${_tmpdir}"
  printf '%s' "${_tmpdir}"
}

# Cleanup all temporary directories
cleanup() {
  for _dir in ${CLEANUP_DIRS}; do
    if [ -d "${_dir}" ]; then
      rm -rf "${_dir}"
    fi
  done
}

trap cleanup EXIT

# --- Validation function under test ---
# This implements the exact validation logic documented in skill-curator.md
# Step 6a: Validate Skill Name (length enforcement).
#
# Returns 0 if the name is valid (40 characters or fewer).
# Returns 1 if the name exceeds 40 characters, printing the error to stderr.
validate_skill_name_length() {
  _skill_name="$1"
  _name_length=$(printf '%s' "${_skill_name}" | wc -c | tr -d ' ')
  if [ "${_name_length}" -gt 40 ]; then
    printf 'ERROR: Skill name exceeds 40-character limit: %s (%d characters)\n' "${_skill_name}" "${_name_length}" >&2
    return 1
  fi
  return 0
}

printf "=== skill-curator Validation Test Suite ===\n\n"

# ============================================================================
# SKILL NAME LENGTH VALIDATION TESTS
# ============================================================================

printf '%s\n' "--- Skill Name Length Validation ---"

# Test 1: Skill name exactly 39 characters (within limit - accept)
run_test "Skill name exactly 39 characters (accept)"
# 39 characters: 10 + 1 + 10 + 1 + 6 + 1 + 10 = 39
NAME_39="abcdefghij-klmnopqrst-uvwxyz-abcdefghij"
ACTUAL_LEN=$(printf '%s' "${NAME_39}" | wc -c | tr -d ' ')
if [ "${ACTUAL_LEN}" -ne 39 ]; then
  fail "Test fixture is exactly 39 chars" "39" "${ACTUAL_LEN}"
else
  STDERR_OUTPUT=$(validate_skill_name_length "${NAME_39}" 2>&1)
  EXIT_CODE=$?
  if [ "${EXIT_CODE}" -eq 0 ]; then
    pass "39-character name accepted (exit code 0)"
  else
    fail "39-character name accepted" "exit code 0" "exit code ${EXIT_CODE}"
  fi
  if [ -z "${STDERR_OUTPUT}" ]; then
    pass "No error message for 39-character name"
  else
    fail "No error message for 39-character name" "(empty)" "${STDERR_OUTPUT}"
  fi
fi

# Test 2: Skill name exactly 40 characters (boundary - accept)
run_test "Skill name exactly 40 characters (boundary - accept)"
# 40 characters: 10 + 1 + 10 + 1 + 6 + 1 + 11 = 40
NAME_40="abcdefghij-klmnopqrst-uvwxyz-abcdefghijk"
ACTUAL_LEN=$(printf '%s' "${NAME_40}" | wc -c | tr -d ' ')
if [ "${ACTUAL_LEN}" -ne 40 ]; then
  fail "Test fixture is exactly 40 chars" "40" "${ACTUAL_LEN}"
else
  STDERR_OUTPUT=$(validate_skill_name_length "${NAME_40}" 2>&1)
  EXIT_CODE=$?
  if [ "${EXIT_CODE}" -eq 0 ]; then
    pass "40-character name accepted (exit code 0)"
  else
    fail "40-character name accepted" "exit code 0" "exit code ${EXIT_CODE}"
  fi
  if [ -z "${STDERR_OUTPUT}" ]; then
    pass "No error message for 40-character name"
  else
    fail "No error message for 40-character name" "(empty)" "${STDERR_OUTPUT}"
  fi
fi

# Test 3: Skill name 41 characters (boundary - reject)
run_test "Skill name 41 characters (boundary - reject)"
# 41 characters: 10 + 1 + 10 + 1 + 6 + 1 + 12 = 41
NAME_41="abcdefghij-klmnopqrst-uvwxyz-abcdefghijkl"
ACTUAL_LEN=$(printf '%s' "${NAME_41}" | wc -c | tr -d ' ')
if [ "${ACTUAL_LEN}" -ne 41 ]; then
  fail "Test fixture is exactly 41 chars" "41" "${ACTUAL_LEN}"
else
  STDERR_OUTPUT=$(validate_skill_name_length "${NAME_41}" 2>&1) || true
  EXIT_CODE=0
  validate_skill_name_length "${NAME_41}" >/dev/null 2>/dev/null || EXIT_CODE=$?
  if [ "${EXIT_CODE}" -ne 0 ]; then
    pass "41-character name rejected (exit code non-zero)"
  else
    fail "41-character name rejected" "exit code non-zero" "exit code 0"
  fi
  case "${STDERR_OUTPUT}" in
    *"Skill name exceeds 40-character limit"*"41 characters"*)
      pass "Error message includes limit and actual length (41)"
      ;;
    *)
      fail "Error message includes limit and actual length" "message with '40-character limit' and '41 characters'" "${STDERR_OUTPUT}"
      ;;
  esac
  case "${STDERR_OUTPUT}" in
    *"${NAME_41}"*)
      pass "Error message includes the offending skill name"
      ;;
    *)
      fail "Error message includes the offending skill name" "${NAME_41}" "${STDERR_OUTPUT}"
      ;;
  esac
fi

# Test 4: Skill name 50 characters (well over limit - reject)
run_test "Skill name 50 characters (well over limit - reject)"
# 50 characters: 10 + 1 + 10 + 1 + 6 + 1 + 10 + 1 + 10 = 50
NAME_50="abcdefghij-klmnopqrst-uvwxyz-abcdefghij-klmnopqrst"
ACTUAL_LEN=$(printf '%s' "${NAME_50}" | wc -c | tr -d ' ')
if [ "${ACTUAL_LEN}" -ne 50 ]; then
  fail "Test fixture is exactly 50 chars" "50" "${ACTUAL_LEN}"
else
  STDERR_OUTPUT=$(validate_skill_name_length "${NAME_50}" 2>&1) || true
  EXIT_CODE=0
  validate_skill_name_length "${NAME_50}" >/dev/null 2>/dev/null || EXIT_CODE=$?
  if [ "${EXIT_CODE}" -ne 0 ]; then
    pass "50-character name rejected (exit code non-zero)"
  else
    fail "50-character name rejected" "exit code non-zero" "exit code 0"
  fi
  case "${STDERR_OUTPUT}" in
    *"Skill name exceeds 40-character limit"*"50 characters"*)
      pass "Error message includes limit and actual length (50)"
      ;;
    *)
      fail "Error message includes limit and actual length" "message with '40-character limit' and '50 characters'" "${STDERR_OUTPUT}"
      ;;
  esac
fi

# ============================================================================
# INTEGRATION TEST: Simulated skill creation with length check
# ============================================================================

printf '\n%s\n' "--- Integration: Simulated Skill Creation ---"

# Test 5: Valid-length skill name leads to directory creation
run_test "Valid skill name (30 chars) allows directory creation"
TMPDIR_5=$(make_temp_dir)
SKILL_NAME="api-authentication-patterns"
SKILL_LEN=$(printf '%s' "${SKILL_NAME}" | wc -c | tr -d ' ')

if validate_skill_name_length "${SKILL_NAME}" 2>/dev/null; then
  mkdir -p "${TMPDIR_5}/skills/${SKILL_NAME}"
  if [ -d "${TMPDIR_5}/skills/${SKILL_NAME}" ]; then
    pass "Directory created for valid skill name (${SKILL_LEN} chars)"
  else
    fail "Directory created for valid skill name" "directory exists" "directory missing"
  fi
else
  fail "Valid skill name accepted" "exit code 0" "exit code non-zero"
fi

# Test 6: Over-limit skill name prevents directory creation
run_test "Over-limit skill name (41 chars) prevents directory creation"
TMPDIR_6=$(make_temp_dir)
LONG_NAME="abcdefghij-klmnopqrst-uvwxyz-abcdefghijkl"
LONG_LEN=$(printf '%s' "${LONG_NAME}" | wc -c | tr -d ' ')

if validate_skill_name_length "${LONG_NAME}" 2>/dev/null; then
  mkdir -p "${TMPDIR_6}/skills/${LONG_NAME}"
  fail "Over-limit skill name should be rejected" "validation failure" "validation passed"
else
  # Skill directory should NOT be created
  if [ ! -d "${TMPDIR_6}/skills/${LONG_NAME}" ]; then
    pass "Directory NOT created for over-limit skill name (${LONG_LEN} chars)"
  else
    fail "Directory NOT created for over-limit skill name" "no directory" "directory exists"
  fi
fi

# Test 7: Exactly 40-char name allows directory creation
run_test "Boundary skill name (40 chars) allows directory creation"
TMPDIR_7=$(make_temp_dir)
BOUNDARY_NAME="abcdefghij-klmnopqrst-uvwxyz-abcdefghijk"
BOUNDARY_LEN=$(printf '%s' "${BOUNDARY_NAME}" | wc -c | tr -d ' ')

if [ "${BOUNDARY_LEN}" -ne 40 ]; then
  fail "Test fixture is exactly 40 chars" "40" "${BOUNDARY_LEN}"
else
  if validate_skill_name_length "${BOUNDARY_NAME}" 2>/dev/null; then
    mkdir -p "${TMPDIR_7}/skills/${BOUNDARY_NAME}"
    if [ -d "${TMPDIR_7}/skills/${BOUNDARY_NAME}" ]; then
      pass "Directory created for boundary skill name (40 chars)"
    else
      fail "Directory created for boundary skill name" "directory exists" "directory missing"
    fi
  else
    fail "Boundary skill name accepted" "exit code 0" "exit code non-zero"
  fi
fi

# ============================================================================
# SUMMARY
# ============================================================================

printf "\n=== Test Summary ===\n"
printf "Tests run:    %d\n" "${TESTS_RUN}"
printf "Tests passed: %d\n" "${TESTS_PASSED}"
printf "Tests failed: %d\n" "${TESTS_FAILED}"

if [ "${TESTS_FAILED}" -gt 0 ]; then
  printf "\nRESULT: FAILED\n"
  exit 1
else
  printf "\nRESULT: ALL TESTS PASSED\n"
  exit 0
fi
