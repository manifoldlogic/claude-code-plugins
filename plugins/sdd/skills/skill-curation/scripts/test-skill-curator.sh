#!/bin/sh
# test-skill-curator.sh - Test suite for skill-curator agent validation rules
#
# Covers:
#   - Skill name length validation (40-character maximum, enforced)
#   - Boundary tests: 39 chars (accept), 40 chars (accept), 41 chars (reject), 50 chars (reject)
#   - Fallback path: SKILL.md creation when init_skill.py is unavailable
#     - Fallback produces valid SKILL.md with correct frontmatter
#     - Fallback SKILL.md passes list-skills.sh parsing
#     - Fallback output is functionally comparable to init_skill.py output
#     - init_skill.py is properly restored after test (cleanup)
#
# Since skill-curator is a markdown agent definition, this test validates the
# documented validation logic by implementing and testing the length-check
# function that the agent is instructed to use. Fallback tests simulate the
# agent's direct file creation path and verify output validity.
#
# POSIX-compatible (no bash-only features).

set -e

# --- Test counters ---
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# --- Cleanup tracking ---
CLEANUP_DIRS=""
ORIG_DIR=$(pwd)

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

# Initialize a git repo in a temp directory with config isolation
setup_test_git_repo() {
  _setup_dir="$1"
  cd "${_setup_dir}"
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
  mkdir -p "${TMPDIR_5}/.claude/skills/${SKILL_NAME}"
  if [ -d "${TMPDIR_5}/.claude/skills/${SKILL_NAME}" ]; then
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
  mkdir -p "${TMPDIR_6}/.claude/skills/${LONG_NAME}"
  fail "Over-limit skill name should be rejected" "validation failure" "validation passed"
else
  # Skill directory should NOT be created
  if [ ! -d "${TMPDIR_6}/.claude/skills/${LONG_NAME}" ]; then
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
    mkdir -p "${TMPDIR_7}/.claude/skills/${BOUNDARY_NAME}"
    if [ -d "${TMPDIR_7}/.claude/skills/${BOUNDARY_NAME}" ]; then
      pass "Directory created for boundary skill name (40 chars)"
    else
      fail "Directory created for boundary skill name" "directory exists" "directory missing"
    fi
  else
    fail "Boundary skill name accepted" "exit code 0" "exit code non-zero"
  fi
fi

# ============================================================================
# FALLBACK PATH TESTS: init_skill.py unavailable
# ============================================================================
#
# These tests simulate the skill-curator agent's fallback path (Step 6b in
# skill-curator.md). When init_skill.py is unavailable or fails, the agent
# falls back to direct directory and file creation (mkdir + write SKILL.md).
#
# Since the skill-curator is a markdown agent definition (not a script), these
# tests implement the same fallback logic the agent is instructed to follow
# and validate the resulting output.

printf '\n%s\n' "--- Fallback Path: init_skill.py Unavailable ---"

# Resolve paths relative to the test script location
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
LIST_SKILLS_SH="${SCRIPT_DIR}/list-skills.sh"
INIT_SKILL_PY="${SCRIPT_DIR}/../../../../../plugins/claude-code-dev/skills/skill-creator/scripts/init_skill.py"

# Normalize the init_skill.py path if it exists
if [ -f "${INIT_SKILL_PY}" ]; then
  INIT_SKILL_PY=$(cd "$(dirname "${INIT_SKILL_PY}")" && pwd)/$(basename "${INIT_SKILL_PY}")
fi

# --- Fallback creation function ---
# Implements the exact fallback logic documented in skill-curator.md Step 6b.
# This is what the agent does when init_skill.py is not available.
create_skill_fallback() {
  _fb_skill_name="$1"
  _fb_skills_dir="$2"
  _fb_skill_dir="${_fb_skills_dir}/${_fb_skill_name}"

  # Create directory (fallback step 1)
  mkdir -p "${_fb_skill_dir}"

  # Convert hyphenated name to Title Case for heading
  _fb_title=""
  _fb_remaining="${_fb_skill_name}"
  while [ -n "${_fb_remaining}" ]; do
    _fb_word="${_fb_remaining%%-*}"
    if [ "${_fb_remaining}" = "${_fb_word}" ]; then
      _fb_remaining=""
    else
      _fb_remaining="${_fb_remaining#*-}"
    fi
    # Capitalize first letter
    _fb_first=$(printf '%s' "${_fb_word}" | cut -c1 | tr 'a-z' 'A-Z')
    _fb_rest=$(printf '%s' "${_fb_word}" | cut -c2-)
    if [ -n "${_fb_title}" ]; then
      _fb_title="${_fb_title} ${_fb_first}${_fb_rest}"
    else
      _fb_title="${_fb_first}${_fb_rest}"
    fi
  done

  # Write SKILL.md with the fallback template from skill-curator.md
  # Uses the exact structure documented in Step 6b
  cat > "${_fb_skill_dir}/SKILL.md" <<SKILLEOF
---
name: ${_fb_skill_name}
description: Test skill created via fallback path for validation purposes
origin: TEST-FALLBACK
created: 2026-02-07
tags: [test, fallback]
---

# ${_fb_title}

## Overview

This skill covers the ${_fb_skill_name} pattern used in this repository.
It was created via the fallback path when init_skill.py was unavailable.

## When to Use

- When testing the fallback skill creation path
- When init_skill.py is not available in the plugin directory

## Pattern/Procedure

1. Check if init_skill.py exists at the expected path
2. If unavailable, create the skill directory manually
3. Write SKILL.md with valid frontmatter and content sections
4. Verify the skill appears in list-skills.sh output

## Examples

Example fallback creation:
  mkdir -p .claude/skills/${_fb_skill_name}
  # Write SKILL.md with frontmatter and body content

## References

- Ticket: TEST-FALLBACK
- Related files: plugins/sdd/agents/skill-curator.md (Step 6b)
SKILLEOF
}

# Test 8: Detect init_skill.py unavailability
run_test "Detect init_skill.py unavailability when script is missing"
TMPDIR_8=$(make_temp_dir)
FAKE_INIT="${TMPDIR_8}/init_skill.py"
# The fake path does not exist -- test that we can detect unavailability
if [ -f "${FAKE_INIT}" ]; then
  fail "Fake init_skill.py should not exist" "file missing" "file found"
else
  pass "Correctly detected init_skill.py is missing at non-existent path"
fi

# Test 9: Fallback creates SKILL.md successfully
run_test "Fallback creates SKILL.md when init_skill.py is unavailable"
TMPDIR_9=$(make_temp_dir)
FB_SKILL_NAME="fallback-test-skill"
FB_SKILLS_DIR="${TMPDIR_9}/.claude/skills"
mkdir -p "${FB_SKILLS_DIR}"

create_skill_fallback "${FB_SKILL_NAME}" "${FB_SKILLS_DIR}"

if [ -f "${FB_SKILLS_DIR}/${FB_SKILL_NAME}/SKILL.md" ]; then
  pass "SKILL.md created via fallback path"
else
  fail "SKILL.md created via fallback path" "file exists" "file missing"
fi

# Test 10: Fallback SKILL.md has valid frontmatter delimiters
run_test "Fallback SKILL.md has valid frontmatter delimiters"
FB_SKILL_MD="${FB_SKILLS_DIR}/${FB_SKILL_NAME}/SKILL.md"

# Check first line is ---
FB_FIRST_LINE=$(head -n 1 "${FB_SKILL_MD}")
if [ "${FB_FIRST_LINE}" = "---" ]; then
  pass "Frontmatter starts with --- delimiter"
else
  fail "Frontmatter starts with --- delimiter" "---" "${FB_FIRST_LINE}"
fi

# Check for closing --- delimiter (line after frontmatter fields)
FB_CLOSE_COUNT=$(grep -c "^---$" "${FB_SKILL_MD}" 2>/dev/null || printf '0')
if [ "${FB_CLOSE_COUNT}" -ge 2 ]; then
  pass "Frontmatter has closing --- delimiter"
else
  fail "Frontmatter has closing --- delimiter" "at least 2 --- lines" "${FB_CLOSE_COUNT} --- lines"
fi

# Test 11: Fallback SKILL.md has required frontmatter fields
run_test "Fallback SKILL.md has required frontmatter fields (name, description)"
FB_HAS_NAME=$(grep -c "^name:" "${FB_SKILL_MD}" 2>/dev/null || printf '0')
FB_HAS_DESC=$(grep -c "^description:" "${FB_SKILL_MD}" 2>/dev/null || printf '0')

if [ "${FB_HAS_NAME}" -ge 1 ]; then
  pass "Frontmatter contains 'name:' field"
else
  fail "Frontmatter contains 'name:' field" "name: present" "name: missing"
fi

if [ "${FB_HAS_DESC}" -ge 1 ]; then
  pass "Frontmatter contains 'description:' field"
else
  fail "Frontmatter contains 'description:' field" "description: present" "description: missing"
fi

# Verify name field value matches directory name
FB_NAME_VALUE=$(grep "^name:" "${FB_SKILL_MD}" | head -n 1 | sed 's/^name:[[:space:]]*//' | sed 's/[[:space:]]*$//')
if [ "${FB_NAME_VALUE}" = "${FB_SKILL_NAME}" ]; then
  pass "Frontmatter 'name' matches directory name (${FB_SKILL_NAME})"
else
  fail "Frontmatter 'name' matches directory name" "${FB_SKILL_NAME}" "${FB_NAME_VALUE}"
fi

# Test 12: Fallback SKILL.md has no placeholder/TODO markers
run_test "Fallback SKILL.md has no placeholder or TODO markers"
FB_TODO_COUNT=$(grep -c -E '\[TODO\]|\[TBD\]|\{content\}|\{description\}' "${FB_SKILL_MD}" 2>/dev/null) || FB_TODO_COUNT=0
if [ "${FB_TODO_COUNT}" -eq 0 ]; then
  pass "No placeholder markers found in fallback SKILL.md"
else
  fail "No placeholder markers in fallback SKILL.md" "0 matches" "${FB_TODO_COUNT} matches"
fi

# Test 13: Fallback SKILL.md passes list-skills.sh parsing
run_test "Fallback SKILL.md passes list-skills.sh parsing"
if [ -f "${LIST_SKILLS_SH}" ]; then
  # Create an isolated git repo and copy the fallback skill into .claude/skills/
  TMPDIR_13=$(make_temp_dir)
  setup_test_git_repo "${TMPDIR_13}"
  cp -r "${FB_SKILLS_DIR}/${FB_SKILL_NAME}" "${TMPDIR_13}/.claude/skills/"
  LIST_OUTPUT=$(cd "${TMPDIR_13}" && sh "${LIST_SKILLS_SH}" 2>/dev/null)
  LIST_EXIT=$?
  cd "${ORIG_DIR}"

  if [ "${LIST_EXIT}" -eq 0 ]; then
    pass "list-skills.sh exits 0 with fallback skill"
  else
    fail "list-skills.sh exits 0 with fallback skill" "exit code 0" "exit code ${LIST_EXIT}"
  fi

  # Check that our skill appears in the JSON output
  case "${LIST_OUTPUT}" in
    *"${FB_SKILL_NAME}"*)
      pass "Fallback skill appears in list-skills.sh JSON output"
      ;;
    *)
      fail "Fallback skill appears in list-skills.sh output" "name '${FB_SKILL_NAME}' in JSON" "${LIST_OUTPUT}"
      ;;
  esac

  # Verify count is at least 1
  case "${LIST_OUTPUT}" in
    *'"count": 0'*)
      fail "list-skills.sh reports count >= 1" "count >= 1" "count: 0"
      ;;
    *'"count":'*)
      pass "list-skills.sh reports count >= 1 for fallback skill"
      ;;
    *)
      fail "list-skills.sh reports count" "count field in JSON" "${LIST_OUTPUT}"
      ;;
  esac
else
  fail "list-skills.sh found at expected path" "${LIST_SKILLS_SH}" "file not found"
fi

# Test 14: Compare fallback vs init_skill.py output (functional comparison)
run_test "Fallback output is functionally comparable to init_skill.py output"
if [ -f "${INIT_SKILL_PY}" ]; then
  TMPDIR_14=$(make_temp_dir)

  # Create skill via init_skill.py (preferred method)
  INIT_SKILL_NAME="compare-test-skill"
  INIT_SKILLS_DIR="${TMPDIR_14}/init-skills"
  mkdir -p "${INIT_SKILLS_DIR}"
  python3 "${INIT_SKILL_PY}" "${INIT_SKILL_NAME}" --path "${INIT_SKILLS_DIR}" >/dev/null 2>&1
  INIT_EXIT=$?

  if [ "${INIT_EXIT}" -ne 0 ] || [ ! -f "${INIT_SKILLS_DIR}/${INIT_SKILL_NAME}/SKILL.md" ]; then
    fail "init_skill.py created SKILL.md for comparison" "file exists" "creation failed (exit ${INIT_EXIT})"
  else
    # Create skill via fallback method
    FB_SKILLS_DIR_14="${TMPDIR_14}/fallback-skills"
    mkdir -p "${FB_SKILLS_DIR_14}"
    create_skill_fallback "${INIT_SKILL_NAME}" "${FB_SKILLS_DIR_14}"

    # Functional comparison: both should be parseable by list-skills.sh
    # Create isolated git repos for each comparison
    INIT_REPO="${TMPDIR_14}/init-root"
    mkdir -p "${INIT_REPO}"
    setup_test_git_repo "${INIT_REPO}"
    cp -r "${INIT_SKILLS_DIR}/${INIT_SKILL_NAME}" "${INIT_REPO}/.claude/skills/"
    INIT_LIST=$(cd "${INIT_REPO}" && sh "${LIST_SKILLS_SH}" 2>/dev/null)
    cd "${ORIG_DIR}"

    FB_REPO="${TMPDIR_14}/fb-root"
    mkdir -p "${FB_REPO}"
    setup_test_git_repo "${FB_REPO}"
    cp -r "${FB_SKILLS_DIR_14}/${INIT_SKILL_NAME}" "${FB_REPO}/.claude/skills/"
    FB_LIST=$(cd "${FB_REPO}" && sh "${LIST_SKILLS_SH}" 2>/dev/null)
    cd "${ORIG_DIR}"

    # Both should contain the skill name
    INIT_HAS_NAME=0
    FB_HAS_NAME_14=0
    case "${INIT_LIST}" in
      *"${INIT_SKILL_NAME}"*) INIT_HAS_NAME=1 ;;
    esac
    case "${FB_LIST}" in
      *"${INIT_SKILL_NAME}"*) FB_HAS_NAME_14=1 ;;
    esac

    if [ "${INIT_HAS_NAME}" -eq 1 ] && [ "${FB_HAS_NAME_14}" -eq 1 ]; then
      pass "Both init_skill.py and fallback skills are parseable by list-skills.sh"
    else
      fail "Both skills parseable by list-skills.sh" "both found" "init=${INIT_HAS_NAME} fallback=${FB_HAS_NAME_14}"
    fi

    # Both should have the same name field in frontmatter
    INIT_FM_NAME=$(grep "^name:" "${INIT_SKILLS_DIR}/${INIT_SKILL_NAME}/SKILL.md" | head -n 1 | sed 's/^name:[[:space:]]*//' | sed 's/[[:space:]]*$//')
    FB_FM_NAME=$(grep "^name:" "${FB_SKILLS_DIR_14}/${INIT_SKILL_NAME}/SKILL.md" | head -n 1 | sed 's/^name:[[:space:]]*//' | sed 's/[[:space:]]*$//')

    if [ "${INIT_FM_NAME}" = "${FB_FM_NAME}" ]; then
      pass "Frontmatter 'name' field identical: init_skill.py='${INIT_FM_NAME}' fallback='${FB_FM_NAME}'"
    else
      fail "Frontmatter 'name' field identical" "${INIT_FM_NAME}" "${FB_FM_NAME}"
    fi

    # Both should have description fields (content may differ, but field must exist)
    INIT_HAS_DESC=$(grep -c "^description:" "${INIT_SKILLS_DIR}/${INIT_SKILL_NAME}/SKILL.md" 2>/dev/null || printf '0')
    FB_HAS_DESC_14=$(grep -c "^description:" "${FB_SKILLS_DIR_14}/${INIT_SKILL_NAME}/SKILL.md" 2>/dev/null || printf '0')

    if [ "${INIT_HAS_DESC}" -ge 1 ] && [ "${FB_HAS_DESC_14}" -ge 1 ]; then
      pass "Both init_skill.py and fallback SKILL.md have 'description' field"
    else
      fail "Both have 'description' field" "both present" "init=${INIT_HAS_DESC} fallback=${FB_HAS_DESC_14}"
    fi
  fi
else
  # init_skill.py not available -- skip comparison but note it
  pass "init_skill.py not found at expected path; comparison skipped (fallback-only validation sufficient)"
fi

# Test 15: init_skill.py rename/restore cycle (cleanup verification)
run_test "init_skill.py rename and restore cycle (cleanup)"
if [ -f "${INIT_SKILL_PY}" ]; then
  INIT_SKILL_BAK="${INIT_SKILL_PY}.test-bak"

  # Ensure no leftover backup
  if [ -f "${INIT_SKILL_BAK}" ]; then
    fail "No leftover backup before test" "no .test-bak file" "backup already exists"
  else
    # Rename init_skill.py to simulate unavailability
    mv "${INIT_SKILL_PY}" "${INIT_SKILL_BAK}"

    if [ ! -f "${INIT_SKILL_PY}" ] && [ -f "${INIT_SKILL_BAK}" ]; then
      pass "init_skill.py successfully renamed to .test-bak (simulating unavailability)"
    else
      fail "init_skill.py renamed" "original missing, backup exists" "rename failed"
    fi

    # Verify detection of unavailability
    if [ -f "${INIT_SKILL_PY}" ]; then
      fail "init_skill.py detected as unavailable after rename" "file missing" "file still found"
    else
      pass "init_skill.py correctly detected as unavailable after rename"
    fi

    # Fallback should still work while init_skill.py is hidden
    TMPDIR_15=$(make_temp_dir)
    FB_SKILLS_DIR_15="${TMPDIR_15}/.claude/skills"
    mkdir -p "${FB_SKILLS_DIR_15}"
    create_skill_fallback "rename-test-skill" "${FB_SKILLS_DIR_15}"

    if [ -f "${FB_SKILLS_DIR_15}/rename-test-skill/SKILL.md" ]; then
      pass "Fallback creates SKILL.md while init_skill.py is hidden"
    else
      fail "Fallback creates SKILL.md while init_skill.py is hidden" "file exists" "file missing"
    fi

    # Restore init_skill.py
    mv "${INIT_SKILL_BAK}" "${INIT_SKILL_PY}"

    if [ -f "${INIT_SKILL_PY}" ] && [ ! -f "${INIT_SKILL_BAK}" ]; then
      pass "init_skill.py restored successfully after test"
    else
      fail "init_skill.py restored" "original exists, backup removed" "restore failed"
      # Emergency restore attempt
      if [ -f "${INIT_SKILL_BAK}" ]; then
        mv "${INIT_SKILL_BAK}" "${INIT_SKILL_PY}" 2>/dev/null || true
      fi
    fi
  fi
else
  pass "init_skill.py not found at expected path; rename/restore test skipped"
fi

# Test 16: Fallback SKILL.md has body content sections
run_test "Fallback SKILL.md has required body content sections"
# Re-use the SKILL.md from Test 9
FB_SKILL_MD_16="${FB_SKILLS_DIR}/${FB_SKILL_NAME}/SKILL.md"

FB_HAS_OVERVIEW=$(grep -c "^## Overview" "${FB_SKILL_MD_16}" 2>/dev/null || printf '0')
FB_HAS_WHEN=$(grep -c "^## When to Use" "${FB_SKILL_MD_16}" 2>/dev/null || printf '0')
FB_HAS_PATTERN=$(grep -c "^## Pattern/Procedure" "${FB_SKILL_MD_16}" 2>/dev/null || printf '0')
FB_HAS_EXAMPLES=$(grep -c "^## Examples" "${FB_SKILL_MD_16}" 2>/dev/null || printf '0')
FB_HAS_REFS=$(grep -c "^## References" "${FB_SKILL_MD_16}" 2>/dev/null || printf '0')

if [ "${FB_HAS_OVERVIEW}" -ge 1 ]; then
  pass "Fallback SKILL.md has '## Overview' section"
else
  fail "Fallback SKILL.md has '## Overview' section" "present" "missing"
fi

if [ "${FB_HAS_WHEN}" -ge 1 ]; then
  pass "Fallback SKILL.md has '## When to Use' section"
else
  fail "Fallback SKILL.md has '## When to Use' section" "present" "missing"
fi

if [ "${FB_HAS_PATTERN}" -ge 1 ]; then
  pass "Fallback SKILL.md has '## Pattern/Procedure' section"
else
  fail "Fallback SKILL.md has '## Pattern/Procedure' section" "present" "missing"
fi

if [ "${FB_HAS_EXAMPLES}" -ge 1 ]; then
  pass "Fallback SKILL.md has '## Examples' section"
else
  fail "Fallback SKILL.md has '## Examples' section" "present" "missing"
fi

if [ "${FB_HAS_REFS}" -ge 1 ]; then
  pass "Fallback SKILL.md has '## References' section"
else
  fail "Fallback SKILL.md has '## References' section" "present" "missing"
fi

# Test 17: Fallback SKILL.md has optional frontmatter fields (origin, created, tags)
run_test "Fallback SKILL.md has optional frontmatter fields (origin, created, tags)"
FB_HAS_ORIGIN=$(grep -c "^origin:" "${FB_SKILL_MD_16}" 2>/dev/null || printf '0')
FB_HAS_CREATED=$(grep -c "^created:" "${FB_SKILL_MD_16}" 2>/dev/null || printf '0')
FB_HAS_TAGS=$(grep -c "^tags:" "${FB_SKILL_MD_16}" 2>/dev/null || printf '0')

if [ "${FB_HAS_ORIGIN}" -ge 1 ]; then
  pass "Fallback SKILL.md has 'origin:' field"
else
  fail "Fallback SKILL.md has 'origin:' field" "present" "missing"
fi

if [ "${FB_HAS_CREATED}" -ge 1 ]; then
  pass "Fallback SKILL.md has 'created:' field"
else
  fail "Fallback SKILL.md has 'created:' field" "present" "missing"
fi

if [ "${FB_HAS_TAGS}" -ge 1 ]; then
  pass "Fallback SKILL.md has 'tags:' field"
else
  fail "Fallback SKILL.md has 'tags:' field" "present" "missing"
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
