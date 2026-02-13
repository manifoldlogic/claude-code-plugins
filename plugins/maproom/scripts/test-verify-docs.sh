#!/usr/bin/env zsh
# test-verify-docs.sh - Meta-verification tests for verify-docs.sh
#
# Validates that verify-docs.sh correctly detects injected documentation
# failures. Each test case modifies a file, runs verify-docs.sh, expects
# a non-zero exit code (failure detected), then restores the original file.
#
# Usage: test-verify-docs.sh
# Exit codes: 0 = all tests pass, 1 = one or more tests failed

set -e

# ---------------------------------------------------------------------------
# Detect repo root and paths
# ---------------------------------------------------------------------------
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
PLUGIN_DIR="$REPO_ROOT/plugins/maproom"
VERIFY_SCRIPT="$PLUGIN_DIR/scripts/verify-docs.sh"
SKILL_DIR="$PLUGIN_DIR/skills/maproom-search"
SKILL_MD="$SKILL_DIR/SKILL.md"
MULTI_REPO_MD="$SKILL_DIR/references/multi-repo-guide.md"

# ---------------------------------------------------------------------------
# Validate prerequisites
# ---------------------------------------------------------------------------
if [ ! -f "$VERIFY_SCRIPT" ]; then
  echo "ERROR: verify-docs.sh not found at $VERIFY_SCRIPT"
  exit 1
fi

if [ ! -f "$SKILL_MD" ]; then
  echo "ERROR: SKILL.md not found at $SKILL_MD"
  exit 1
fi

if [ ! -f "$MULTI_REPO_MD" ]; then
  echo "ERROR: multi-repo-guide.md not found at $MULTI_REPO_MD"
  exit 1
fi

# ---------------------------------------------------------------------------
# Backup paths in /tmp/
# ---------------------------------------------------------------------------
BACKUP_SKILL="/tmp/test-verify-docs-SKILL.md.backup"
BACKUP_MULTI="/tmp/test-verify-docs-multi-repo-guide.md.backup"

# ---------------------------------------------------------------------------
# Cleanup trap - restore files on exit, interrupt, or error
# ---------------------------------------------------------------------------
cleanup() {
  if [ -f "$BACKUP_SKILL" ]; then
    mv "$BACKUP_SKILL" "$SKILL_MD" 2>/dev/null || true
  fi
  if [ -f "$BACKUP_MULTI" ]; then
    mv "$BACKUP_MULTI" "$MULTI_REPO_MD" 2>/dev/null || true
  fi
  # Remove any sed temp files
  rm -f "${MULTI_REPO_MD}.tmp" 2>/dev/null || true
}
trap cleanup EXIT INT TERM HUP

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
TEST_PASS=0
TEST_FAIL=0

# ===========================================================================
# Test 1: Inject bare search command into SKILL.md (Check 3)
# ===========================================================================
echo "Test 1: Bare command injection detection (Check 3)"

cp "$SKILL_MD" "$BACKUP_SKILL"

# Append a bare search command OUTSIDE the Output Formats section
# (appended at end of file, which is after the last section)
echo "" >> "$SKILL_MD"
echo 'crewchief-maproom search --repo myrepo --query "injected test"' >> "$SKILL_MD"

# Run verify-docs.sh and expect failure (non-zero exit)
if ! "$VERIFY_SCRIPT" >/dev/null 2>&1; then
  echo "  PASS: verify-docs.sh correctly detected bare command outside Output Formats"
  TEST_PASS=$((TEST_PASS + 1))
else
  echo "  FAIL: verify-docs.sh did not detect bare command injection"
  TEST_FAIL=$((TEST_FAIL + 1))
fi

# Restore original file
mv "$BACKUP_SKILL" "$SKILL_MD"

# ===========================================================================
# Test 2: Remove --format agent from multi-repo-guide.md (Check 2)
# ===========================================================================
echo "Test 2: Missing --format agent detection in multi-repo-guide.md (Check 2)"

cp "$MULTI_REPO_MD" "$BACKUP_MULTI"

# Remove all --format agent occurrences using sed
# Use -i.tmp for compatibility with both GNU and BSD sed
sed -i.tmp 's/--format agent//g' "$MULTI_REPO_MD"
rm -f "${MULTI_REPO_MD}.tmp"

# Run verify-docs.sh and expect failure (non-zero exit)
if ! "$VERIFY_SCRIPT" >/dev/null 2>&1; then
  echo "  PASS: verify-docs.sh correctly detected missing --format agent"
  TEST_PASS=$((TEST_PASS + 1))
else
  echo "  FAIL: verify-docs.sh did not detect missing --format agent"
  TEST_FAIL=$((TEST_FAIL + 1))
fi

# Restore original file
mv "$BACKUP_MULTI" "$MULTI_REPO_MD"

# ===========================================================================
# Test 3: Break cross-reference link (Check 11)
# ===========================================================================
echo "Test 3: Broken cross-reference detection (Check 11)"

cp "$SKILL_MD" "$BACKUP_SKILL"

# Append a markdown link to a non-existent reference file
echo "" >> "$SKILL_MD"
echo "[Broken](./references/nonexistent.md)" >> "$SKILL_MD"

# Run verify-docs.sh and expect failure (non-zero exit)
if ! "$VERIFY_SCRIPT" >/dev/null 2>&1; then
  echo "  PASS: verify-docs.sh correctly detected broken cross-reference"
  TEST_PASS=$((TEST_PASS + 1))
else
  echo "  FAIL: verify-docs.sh did not detect broken cross-reference"
  TEST_FAIL=$((TEST_FAIL + 1))
fi

# Restore original file
mv "$BACKUP_SKILL" "$SKILL_MD"

# ===========================================================================
# Summary
# ===========================================================================
TOTAL_TESTS=3
echo ""
echo "=========================================="
echo "Meta-Verification Test Summary"
echo "=========================================="
echo "Passed: $TEST_PASS / $TOTAL_TESTS"
echo "Failed: $TEST_FAIL / $TOTAL_TESTS"
echo ""

if [ "$TEST_FAIL" -eq 0 ]; then
  echo "Status: ALL TESTS PASSED"
  exit 0
else
  echo "Status: SOME TESTS FAILED"
  exit 1
fi
