#!/bin/sh
# test-list-skills.sh - Test suite for list-skills.sh
#
# Covers:
#   - Happy path: empty dir, single skill, multiple skills
#   - Edge cases: minimal frontmatter, all optional fields, special characters,
#                 non-directory files
#   - Error handling: malformed SKILL.md, missing frontmatter, missing required
#                     fields, .claude/skills/ missing, permissions errors,
#                     non-git environment
#
# POSIX-compatible (no bash-only features).

set -e

# --- Resolve script directory ---
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
LIST_SKILLS="${SCRIPT_DIR}/list-skills.sh"
ORIG_DIR=$(pwd)

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
  _tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/test-list-skills.XXXXXX")
  CLEANUP_DIRS="${CLEANUP_DIRS} ${_tmpdir}"
  printf '%s' "${_tmpdir}"
}

# Initialize a git repo in a temp directory with config isolation
setup_test_git_repo() {
  local test_dir="$1"
  cd "${test_dir}"
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=test
  export GIT_AUTHOR_EMAIL=test@test.com
  export GIT_COMMITTER_NAME=test
  export GIT_COMMITTER_EMAIL=test@test.com
  git init
  mkdir -p .claude/skills
}

# Cleanup all temporary directories
cleanup() {
  cd "${ORIG_DIR}" 2>/dev/null || true
  for _dir in ${CLEANUP_DIRS}; do
    if [ -d "${_dir}" ]; then
      # Restore permissions in case we restricted them
      chmod -R u+rwx "${_dir}" 2>/dev/null || true
      rm -rf "${_dir}"
    fi
  done
}

trap cleanup EXIT

# --- Verify list-skills.sh exists ---
if [ ! -f "${LIST_SKILLS}" ]; then
  echo "ERROR: list-skills.sh not found at: ${LIST_SKILLS}"
  exit 1
fi

printf "=== list-skills.sh Test Suite ===\n\n"

# ============================================================================
# HAPPY PATH TESTS
# ============================================================================

printf '%s\n' "--- Happy Path ---"

# Test 1: Empty skills directory
run_test "Empty skills directory returns empty array"
TMPDIR_1=$(make_temp_dir)
setup_test_git_repo "${TMPDIR_1}"
OUTPUT=$(cd "${TMPDIR_1}" && sh "${LIST_SKILLS}" 2>/dev/null)
cd "${ORIG_DIR}"
EXPECTED='{"skills": [], "count": 0}'
if [ "${OUTPUT}" = "${EXPECTED}" ]; then
  pass "Empty dir returns empty array"
else
  fail "Empty dir returns empty array" "${EXPECTED}" "${OUTPUT}"
fi

# Test 2: Single skill with full frontmatter
run_test "Single skill with complete frontmatter"
TMPDIR_2=$(make_temp_dir)
setup_test_git_repo "${TMPDIR_2}"
mkdir -p "${TMPDIR_2}/.claude/skills/api-testing"
cat > "${TMPDIR_2}/.claude/skills/api-testing/SKILL.md" << 'SKILLEOF'
---
name: api-testing
description: API testing patterns for this repo
origin: APIV2
tags: [testing, api]
---

# API Testing

## Overview

Testing patterns for our API.
SKILLEOF

OUTPUT=$(cd "${TMPDIR_2}" && sh "${LIST_SKILLS}" 2>/dev/null)
cd "${ORIG_DIR}"
# Check that output contains expected fields
case "${OUTPUT}" in
  *'"name": "api-testing"'*'"description": "API testing patterns for this repo"'*'"origin": "APIV2"'*'"count": 1'*)
    pass "Single skill parsed correctly"
    ;;
  *)
    fail "Single skill parsed correctly" "JSON with name=api-testing, count=1" "${OUTPUT}"
    ;;
esac

# Test 3: Multiple skills
run_test "Multiple skills enumerated correctly"
TMPDIR_3=$(make_temp_dir)
setup_test_git_repo "${TMPDIR_3}"
mkdir -p "${TMPDIR_3}/.claude/skills/skill-a"
mkdir -p "${TMPDIR_3}/.claude/skills/skill-b"
mkdir -p "${TMPDIR_3}/.claude/skills/skill-c"

cat > "${TMPDIR_3}/.claude/skills/skill-a/SKILL.md" << 'SKILLEOF'
---
name: skill-a
description: First skill
---

# Skill A
SKILLEOF

cat > "${TMPDIR_3}/.claude/skills/skill-b/SKILL.md" << 'SKILLEOF'
---
name: skill-b
description: Second skill
origin: TICKET1
---

# Skill B
SKILLEOF

cat > "${TMPDIR_3}/.claude/skills/skill-c/SKILL.md" << 'SKILLEOF'
---
name: skill-c
description: Third skill
tags: [one, two, three]
---

# Skill C
SKILLEOF

OUTPUT=$(cd "${TMPDIR_3}" && sh "${LIST_SKILLS}" 2>/dev/null)
cd "${ORIG_DIR}"
case "${OUTPUT}" in
  *'"count": 3'*)
    pass "Multiple skills counted correctly"
    ;;
  *)
    fail "Multiple skills counted correctly" "count: 3" "${OUTPUT}"
    ;;
esac

# Verify all three names are present
_all_found=1
for _name in skill-a skill-b skill-c; do
  case "${OUTPUT}" in
    *"\"name\": \"${_name}\""*)
      ;;
    *)
      _all_found=0
      ;;
  esac
done
if [ "${_all_found}" -eq 1 ]; then
  pass "All skill names present in output"
else
  fail "All skill names present in output" "skill-a, skill-b, skill-c" "${OUTPUT}"
fi

# ============================================================================
# EDGE CASE TESTS
# ============================================================================

printf '\n%s\n' "--- Edge Cases ---"

# Test 4: Minimal frontmatter (only required fields)
run_test "Minimal frontmatter with only name and description"
TMPDIR_4=$(make_temp_dir)
setup_test_git_repo "${TMPDIR_4}"
mkdir -p "${TMPDIR_4}/.claude/skills/minimal"
cat > "${TMPDIR_4}/.claude/skills/minimal/SKILL.md" << 'SKILLEOF'
---
name: minimal
description: A minimal skill
---

# Minimal
SKILLEOF

OUTPUT=$(cd "${TMPDIR_4}" && sh "${LIST_SKILLS}" 2>/dev/null)
cd "${ORIG_DIR}"
case "${OUTPUT}" in
  *'"name": "minimal"'*'"description": "A minimal skill"'*'"origin": ""'*'"tags": ""'*'"count": 1'*)
    pass "Minimal frontmatter parsed with empty optional fields"
    ;;
  *)
    fail "Minimal frontmatter parsed with empty optional fields" "name=minimal, empty origin/tags" "${OUTPUT}"
    ;;
esac

# Test 5: All optional fields present
run_test "All optional fields present in frontmatter"
TMPDIR_5=$(make_temp_dir)
setup_test_git_repo "${TMPDIR_5}"
mkdir -p "${TMPDIR_5}/.claude/skills/full"
cat > "${TMPDIR_5}/.claude/skills/full/SKILL.md" << 'SKILLEOF'
---
name: full
description: A fully documented skill
origin: FULL-1
created: 2025-01-15
tags: [alpha, beta]
promotion-candidate: true
last-used: 2025-06-01
last-updated: 2025-06-01
---

# Full Skill
SKILLEOF

OUTPUT=$(cd "${TMPDIR_5}" && sh "${LIST_SKILLS}" 2>/dev/null)
cd "${ORIG_DIR}"
case "${OUTPUT}" in
  *'"name": "full"'*'"description": "A fully documented skill"'*'"origin": "FULL-1"'*'"tags": "[alpha, beta]"'*'"count": 1'*)
    pass "All optional fields parsed correctly"
    ;;
  *)
    fail "All optional fields parsed correctly" "name=full, origin=FULL-1, tags=[alpha, beta]" "${OUTPUT}"
    ;;
esac

# Test 6: Special characters in description
run_test "Special characters in description are JSON-escaped"
TMPDIR_6=$(make_temp_dir)
setup_test_git_repo "${TMPDIR_6}"
mkdir -p "${TMPDIR_6}/.claude/skills/special-chars"
cat > "${TMPDIR_6}/.claude/skills/special-chars/SKILL.md" << 'SKILLEOF'
---
name: special-chars
description: Handles "quotes" and back\slashes
---

# Special
SKILLEOF

OUTPUT=$(cd "${TMPDIR_6}" && sh "${LIST_SKILLS}" 2>/dev/null)
cd "${ORIG_DIR}"
# Verify valid JSON structure (count should be 1)
case "${OUTPUT}" in
  *'"count": 1'*)
    pass "Special characters handled (skill counted)"
    ;;
  *)
    fail "Special characters handled (skill counted)" "count: 1" "${OUTPUT}"
    ;;
esac
# Verify quotes are escaped
case "${OUTPUT}" in
  *'\"quotes\"'*)
    pass "Double quotes escaped in JSON output"
    ;;
  *)
    fail "Double quotes escaped in JSON output" "escaped quotes" "${OUTPUT}"
    ;;
esac

# Test 7: Non-directory files in skills/ are skipped
run_test "Non-directory files in skills/ are skipped"
TMPDIR_7=$(make_temp_dir)
setup_test_git_repo "${TMPDIR_7}"
mkdir -p "${TMPDIR_7}/.claude/skills/real-skill"
cat > "${TMPDIR_7}/.claude/skills/real-skill/SKILL.md" << 'SKILLEOF'
---
name: real-skill
description: The only real skill
---

# Real
SKILLEOF

# Create a regular file (not a directory) in skills/
printf "not a skill\n" > "${TMPDIR_7}/.claude/skills/random-file.txt"
printf "also not a skill\n" > "${TMPDIR_7}/.claude/skills/.hidden"

OUTPUT=$(cd "${TMPDIR_7}" && sh "${LIST_SKILLS}" 2>/dev/null)
cd "${ORIG_DIR}"
case "${OUTPUT}" in
  *'"name": "real-skill"'*'"count": 1'*)
    pass "Non-directory entries skipped"
    ;;
  *)
    fail "Non-directory entries skipped" "count: 1, only real-skill" "${OUTPUT}"
    ;;
esac

# Test 8: Directory without SKILL.md is skipped
run_test "Directory without SKILL.md is skipped"
TMPDIR_8=$(make_temp_dir)
setup_test_git_repo "${TMPDIR_8}"
mkdir -p "${TMPDIR_8}/.claude/skills/has-skill"
mkdir -p "${TMPDIR_8}/.claude/skills/no-skill"
cat > "${TMPDIR_8}/.claude/skills/has-skill/SKILL.md" << 'SKILLEOF'
---
name: has-skill
description: This one has a SKILL.md
---

# Has Skill
SKILLEOF

# no-skill directory has no SKILL.md

OUTPUT=$(cd "${TMPDIR_8}" && sh "${LIST_SKILLS}" 2>/dev/null)
cd "${ORIG_DIR}"
case "${OUTPUT}" in
  *'"name": "has-skill"'*'"count": 1'*)
    pass "Directory without SKILL.md skipped"
    ;;
  *)
    fail "Directory without SKILL.md skipped" "count: 1, only has-skill" "${OUTPUT}"
    ;;
esac

# ============================================================================
# ERROR HANDLING TESTS
# ============================================================================

printf '\n%s\n' "--- Error Handling ---"

# Test 9: Malformed SKILL.md (no closing frontmatter delimiter)
run_test "Malformed SKILL.md with unclosed frontmatter"
TMPDIR_9=$(make_temp_dir)
setup_test_git_repo "${TMPDIR_9}"
mkdir -p "${TMPDIR_9}/.claude/skills/good-skill"
mkdir -p "${TMPDIR_9}/.claude/skills/bad-skill"

cat > "${TMPDIR_9}/.claude/skills/good-skill/SKILL.md" << 'SKILLEOF'
---
name: good-skill
description: This is valid
---

# Good
SKILLEOF

cat > "${TMPDIR_9}/.claude/skills/bad-skill/SKILL.md" << 'SKILLEOF'
---
name: bad-skill
description: No closing delimiter
SKILLEOF

OUTPUT=$(cd "${TMPDIR_9}" && sh "${LIST_SKILLS}" 2>/dev/null)
STDERR=$(cd "${TMPDIR_9}" && sh "${LIST_SKILLS}" 2>&1 1>/dev/null)
EXIT_CODE=$?
cd "${ORIG_DIR}"

if [ "${EXIT_CODE}" -eq 0 ]; then
  pass "Exit code is 0 despite malformed SKILL.md"
else
  fail "Exit code is 0 despite malformed SKILL.md" "0" "${EXIT_CODE}"
fi

case "${OUTPUT}" in
  *'"name": "good-skill"'*'"count": 1'*)
    pass "Good skill parsed, bad skill skipped"
    ;;
  *)
    fail "Good skill parsed, bad skill skipped" "count: 1, good-skill" "${OUTPUT}"
    ;;
esac

case "${STDERR}" in
  *"Warning"*"bad-skill"*)
    pass "Warning emitted for malformed SKILL.md"
    ;;
  *)
    fail "Warning emitted for malformed SKILL.md" "Warning mentioning bad-skill" "${STDERR}"
    ;;
esac

# Test 10: Missing frontmatter (no --- at start)
run_test "Missing frontmatter (no opening delimiter)"
TMPDIR_10=$(make_temp_dir)
setup_test_git_repo "${TMPDIR_10}"
mkdir -p "${TMPDIR_10}/.claude/skills/no-frontmatter"

cat > "${TMPDIR_10}/.claude/skills/no-frontmatter/SKILL.md" << 'SKILLEOF'
# No Frontmatter

This file has no YAML frontmatter at all.
SKILLEOF

OUTPUT=$(cd "${TMPDIR_10}" && sh "${LIST_SKILLS}" 2>/dev/null)
STDERR=$(cd "${TMPDIR_10}" && sh "${LIST_SKILLS}" 2>&1 1>/dev/null)
cd "${ORIG_DIR}"

case "${OUTPUT}" in
  *'"count": 0'*)
    pass "Skill without frontmatter returns count 0"
    ;;
  *)
    fail "Skill without frontmatter returns count 0" "count: 0" "${OUTPUT}"
    ;;
esac

case "${STDERR}" in
  *"Warning"*)
    pass "Warning emitted for missing frontmatter"
    ;;
  *)
    fail "Warning emitted for missing frontmatter" "Warning message" "${STDERR}"
    ;;
esac

# Test 11: Missing required field (name)
run_test "Missing required field: name"
TMPDIR_11=$(make_temp_dir)
setup_test_git_repo "${TMPDIR_11}"
mkdir -p "${TMPDIR_11}/.claude/skills/no-name"

cat > "${TMPDIR_11}/.claude/skills/no-name/SKILL.md" << 'SKILLEOF'
---
description: Has description but no name
---

# No Name
SKILLEOF

OUTPUT=$(cd "${TMPDIR_11}" && sh "${LIST_SKILLS}" 2>/dev/null)
STDERR=$(cd "${TMPDIR_11}" && sh "${LIST_SKILLS}" 2>&1 1>/dev/null)
cd "${ORIG_DIR}"

case "${OUTPUT}" in
  *'"count": 0'*)
    pass "Skill missing name returns count 0"
    ;;
  *)
    fail "Skill missing name returns count 0" "count: 0" "${OUTPUT}"
    ;;
esac

case "${STDERR}" in
  *"Warning"*"name"*)
    pass "Warning about missing name field"
    ;;
  *)
    fail "Warning about missing name field" "Warning mentioning 'name'" "${STDERR}"
    ;;
esac

# Test 12: Missing required field (description)
run_test "Missing required field: description"
TMPDIR_12=$(make_temp_dir)
setup_test_git_repo "${TMPDIR_12}"
mkdir -p "${TMPDIR_12}/.claude/skills/no-desc"

cat > "${TMPDIR_12}/.claude/skills/no-desc/SKILL.md" << 'SKILLEOF'
---
name: no-desc
---

# No Description
SKILLEOF

OUTPUT=$(cd "${TMPDIR_12}" && sh "${LIST_SKILLS}" 2>/dev/null)
STDERR=$(cd "${TMPDIR_12}" && sh "${LIST_SKILLS}" 2>&1 1>/dev/null)
cd "${ORIG_DIR}"

case "${OUTPUT}" in
  *'"count": 0'*)
    pass "Skill missing description returns count 0"
    ;;
  *)
    fail "Skill missing description returns count 0" "count: 0" "${OUTPUT}"
    ;;
esac

case "${STDERR}" in
  *"Warning"*"description"*)
    pass "Warning about missing description field"
    ;;
  *)
    fail "Warning about missing description field" "Warning mentioning 'description'" "${STDERR}"
    ;;
esac

# Test 13: .claude/skills/ directory does not exist in repo
run_test ".claude/skills/ directory does not exist in repo"
TMPDIR_13=$(make_temp_dir)
cd "${TMPDIR_13}"
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test
export GIT_AUTHOR_EMAIL=test@test.com
export GIT_COMMITTER_NAME=test
export GIT_COMMITTER_EMAIL=test@test.com
git init
# Do NOT create .claude/skills/ directory

OUTPUT=$(cd "${TMPDIR_13}" && sh "${LIST_SKILLS}" 2>/dev/null)
STDERR=$(cd "${TMPDIR_13}" && sh "${LIST_SKILLS}" 2>&1 1>/dev/null)
EXIT_CODE=$?
cd "${ORIG_DIR}"

if [ "${EXIT_CODE}" -eq 0 ]; then
  pass "Exit code is 0 when .claude/skills/ missing"
else
  fail "Exit code is 0 when .claude/skills/ missing" "0" "${EXIT_CODE}"
fi

case "${OUTPUT}" in
  *'"skills": []'*'"count": 0'*)
    pass "Returns empty array when .claude/skills/ missing"
    ;;
  *)
    fail "Returns empty array when .claude/skills/ missing" '{"skills": [], "count": 0}' "${OUTPUT}"
    ;;
esac

case "${STDERR}" in
  *"Warning"*"Skills directory"*"does not exist"*)
    pass "Warning about .claude/skills/ not existing"
    ;;
  *)
    fail "Warning about .claude/skills/ not existing" "Warning mentioning skills directory" "${STDERR}"
    ;;
esac

# Test 14: .claude/ exists but skills/ subdirectory does not
run_test ".claude/ exists but skills/ subdirectory does not"
TMPDIR_14=$(make_temp_dir)
cd "${TMPDIR_14}"
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test
export GIT_AUTHOR_EMAIL=test@test.com
export GIT_COMMITTER_NAME=test
export GIT_COMMITTER_EMAIL=test@test.com
git init
mkdir -p .claude
# Do NOT create .claude/skills/ directory

OUTPUT=$(cd "${TMPDIR_14}" && sh "${LIST_SKILLS}" 2>/dev/null)
STDERR=$(cd "${TMPDIR_14}" && sh "${LIST_SKILLS}" 2>&1 1>/dev/null)
EXIT_CODE=$?
cd "${ORIG_DIR}"

if [ "${EXIT_CODE}" -eq 0 ]; then
  pass "Exit code is 0 when skills/ missing under .claude/"
else
  fail "Exit code is 0 when skills/ missing under .claude/" "0" "${EXIT_CODE}"
fi

case "${OUTPUT}" in
  *'"skills": []'*'"count": 0'*)
    pass "Returns empty array when skills/ missing under .claude/"
    ;;
  *)
    fail "Returns empty array when skills/ missing under .claude/" '{"skills": [], "count": 0}' "${OUTPUT}"
    ;;
esac

# Test 15: Permissions error on .claude/skills/ directory
run_test "Permissions error on .claude/skills/ directory"

# Skip permissions test if running as root (root can read everything)
CURRENT_UID=$(id -u)
if [ "${CURRENT_UID}" -eq 0 ]; then
  printf "  SKIP: Running as root, cannot test permission denial\n"
  TESTS_RUN=$((TESTS_RUN - 1))
else
  TMPDIR_15=$(make_temp_dir)
  setup_test_git_repo "${TMPDIR_15}"
  chmod 000 "${TMPDIR_15}/.claude/skills"

  OUTPUT=$(cd "${TMPDIR_15}" && sh "${LIST_SKILLS}" 2>/dev/null)
  STDERR=$(cd "${TMPDIR_15}" && sh "${LIST_SKILLS}" 2>&1 1>/dev/null)
  EXIT_CODE=$?
  cd "${ORIG_DIR}"

  # Restore permissions for cleanup
  chmod 755 "${TMPDIR_15}/.claude/skills"

  if [ "${EXIT_CODE}" -eq 0 ]; then
    pass "Exit code is 0 on permissions error"
  else
    fail "Exit code is 0 on permissions error" "0" "${EXIT_CODE}"
  fi

  case "${OUTPUT}" in
    *'"skills": []'*'"count": 0'*)
      pass "Returns empty array on permissions error"
      ;;
    *)
      fail "Returns empty array on permissions error" '{"skills": [], "count": 0}' "${OUTPUT}"
      ;;
  esac
fi

# Test 16: Empty frontmatter block
run_test "Empty frontmatter block (just delimiters)"
TMPDIR_16=$(make_temp_dir)
setup_test_git_repo "${TMPDIR_16}"
mkdir -p "${TMPDIR_16}/.claude/skills/empty-fm"

cat > "${TMPDIR_16}/.claude/skills/empty-fm/SKILL.md" << 'SKILLEOF'
---
---

# Empty Frontmatter
SKILLEOF

OUTPUT=$(cd "${TMPDIR_16}" && sh "${LIST_SKILLS}" 2>/dev/null)
STDERR=$(cd "${TMPDIR_16}" && sh "${LIST_SKILLS}" 2>&1 1>/dev/null)
cd "${ORIG_DIR}"

case "${OUTPUT}" in
  *'"count": 0'*)
    pass "Empty frontmatter returns count 0"
    ;;
  *)
    fail "Empty frontmatter returns count 0" "count: 0" "${OUTPUT}"
    ;;
esac

# Test 17: Valid JSON output (pipe to jq for validation)
run_test "Output is valid JSON"
TMPDIR_17=$(make_temp_dir)
setup_test_git_repo "${TMPDIR_17}"
mkdir -p "${TMPDIR_17}/.claude/skills/json-test"
cat > "${TMPDIR_17}/.claude/skills/json-test/SKILL.md" << 'SKILLEOF'
---
name: json-test
description: Testing JSON validity
origin: TEST1
tags: [a, b]
---

# JSON Test
SKILLEOF

OUTPUT=$(cd "${TMPDIR_17}" && sh "${LIST_SKILLS}" 2>/dev/null)
cd "${ORIG_DIR}"

if command -v jq >/dev/null 2>&1; then
  JQ_RESULT=$(printf '%s' "${OUTPUT}" | jq . 2>&1)
  JQ_EXIT=$?
  if [ "${JQ_EXIT}" -eq 0 ]; then
    pass "Output is valid JSON (verified by jq)"
  else
    fail "Output is valid JSON (verified by jq)" "valid JSON" "${JQ_RESULT}"
  fi
else
  # Fallback: basic structure check
  case "${OUTPUT}" in
    '{"skills":'*'"count":'*'}')
      pass "Output has valid JSON structure (jq not available for full validation)"
      ;;
    *)
      fail "Output has valid JSON structure" '{"skills": [...], "count": N}' "${OUTPUT}"
      ;;
  esac
fi

# Test 18: git rev-parse failure (non-git environment)
run_test "Non-git environment returns error and empty result"
TMPDIR_18=$(make_temp_dir)
# Do NOT run git init - this is not a git repository
# Ensure we are not inside any git repo by setting GIT_CEILING_DIRECTORIES
OUTPUT=$(cd "${TMPDIR_18}" && GIT_CEILING_DIRECTORIES="${TMPDIR_18}" sh "${LIST_SKILLS}" 2>/dev/null)
STDERR=$(cd "${TMPDIR_18}" && GIT_CEILING_DIRECTORIES="${TMPDIR_18}" sh "${LIST_SKILLS}" 2>&1 1>/dev/null)
EXIT_CODE=$?
cd "${ORIG_DIR}"

if [ "${EXIT_CODE}" -eq 0 ]; then
  pass "Exit code is 0 in non-git environment"
else
  fail "Exit code is 0 in non-git environment" "0" "${EXIT_CODE}"
fi

case "${STDERR}" in
  *"Error: Cannot detect repository root"*"git repository"*)
    pass "Error message about non-git environment on stderr"
    ;;
  *)
    fail "Error message about non-git environment on stderr" "Error: Cannot detect repository root. Skill curation requires a git repository." "${STDERR}"
    ;;
esac

EXPECTED_18='{"skills": [], "count": 0}'
if [ "${OUTPUT}" = "${EXPECTED_18}" ]; then
  pass "Empty JSON output in non-git environment"
else
  fail "Empty JSON output in non-git environment" "${EXPECTED_18}" "${OUTPUT}"
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
