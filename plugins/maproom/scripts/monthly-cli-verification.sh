#!/usr/bin/env zsh
# monthly-cli-verification.sh - Automated CLI flag verification
#
# Verifies that maproom CLI flags have not drifted from the
# documented baseline. Detects flag deprecation, renaming, or behavior
# changes before agents encounter failures.
#
# Baseline: planning/deliverables/cli-flag-verification.md
# (located at the ticket level in the specs directory)
#
# Usage: monthly-cli-verification.sh [--help] [--baseline FILE]
# Exit codes: 0 = no drift detected, 1 = drift detected or error
#
# Reference: MAPAGENT.5001 (automate-monthly-verification)

set -e

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
  cat <<'USAGE'
monthly-cli-verification.sh - Automated CLI flag drift detection

USAGE:
  monthly-cli-verification.sh [--help] [--baseline FILE]

DESCRIPTION:
  Captures current maproom CLI help output and compares it
  against the documented baseline. Reports any flags that have been
  added, removed, renamed, or changed.

OPTIONS:
  --help, -h           Show this help message and exit
  --baseline FILE      Path to baseline verification file (optional)
                       Default: uses embedded expected flags

CHECKS:
  1. CLI availability (maproom in PATH)
  2. Version consistency (matches documented version)
  3. search --help flag presence (5 expected flags)
  4. vector-search --help flag presence (6 expected flags)
  5. Full help text comparison against baseline (if --baseline provided)

EXIT CODES:
  0   No drift detected - all flags match baseline
  1   Drift detected or error occurred

EXAMPLES:
  # Run with embedded baseline
  monthly-cli-verification.sh

  # Run with external baseline file
  monthly-cli-verification.sh --baseline planning/deliverables/cli-flag-verification.md

  # CI/CD usage (GitHub Actions)
  bash plugins/maproom/scripts/monthly-cli-verification.sh
USAGE
  exit 0
fi

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
BASELINE_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --baseline)
      shift
      BASELINE_FILE="$1"
      ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Configuration: Expected flags from baseline (cli-flag-verification.md)
# ---------------------------------------------------------------------------
# These are the flags documented in the baseline deliverable.
# If any flag is missing from the live CLI output, drift is detected.

# Expected flags for 'search' subcommand
SEARCH_EXPECTED_FLAGS="--format --kind --lang --preview --preview-length --repo --worktree --query --k --debug --deduplicate"

# Expected flags for 'vector-search' subcommand
VSEARCH_EXPECTED_FLAGS="--format --kind --lang --preview --preview-length --threshold --repo --worktree --query --k"

# Expected version
EXPECTED_VERSION="0.1.0"

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
DRIFT_COUNT=0
CHECK_COUNT=0
DIFF_OUTPUT=""

# ---------------------------------------------------------------------------
# Helper: record drift
# ---------------------------------------------------------------------------
record_drift() {
  DRIFT_COUNT=$((DRIFT_COUNT + 1))
  DIFF_OUTPUT="${DIFF_OUTPUT}DRIFT: $1
"
  echo "  DRIFT: $1"
}

record_pass() {
  echo "  PASS: $1"
}

# ---------------------------------------------------------------------------
# Check 1: CLI availability
# ---------------------------------------------------------------------------
CHECK_COUNT=$((CHECK_COUNT + 1))
echo "Check 1: CLI availability"
if ! command -v maproom >/dev/null 2>&1; then
  record_drift "maproom not found in PATH"
  echo ""
  echo "=========================================="
  echo "CLI Verification FAILED"
  echo "=========================================="
  echo "maproom CLI is not installed or not in PATH."
  echo "Cannot proceed with verification."
  echo ""
  echo "$DIFF_OUTPUT"
  exit 1
fi
record_pass "maproom found in PATH"

# ---------------------------------------------------------------------------
# Check 2: Version consistency
# ---------------------------------------------------------------------------
CHECK_COUNT=$((CHECK_COUNT + 1))
echo "Check 2: Version consistency"
CURRENT_VERSION=$(maproom --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
if [ -z "$CURRENT_VERSION" ]; then
  record_drift "Could not determine maproom version"
elif [ "$CURRENT_VERSION" != "$EXPECTED_VERSION" ]; then
  record_drift "Version changed: expected $EXPECTED_VERSION, got $CURRENT_VERSION"
else
  record_pass "Version matches expected ($EXPECTED_VERSION)"
fi

# ---------------------------------------------------------------------------
# Check 3: search --help flag presence
# ---------------------------------------------------------------------------
CHECK_COUNT=$((CHECK_COUNT + 1))
echo "Check 3: search --help flag presence"
SEARCH_HELP=$(maproom search --help 2>&1 || true)

missing_search=""
for flag in $SEARCH_EXPECTED_FLAGS; do
  if ! echo "$SEARCH_HELP" | grep -q -- "$flag"; then
    missing_search="${missing_search} ${flag}"
  fi
done

if [ -n "$missing_search" ]; then
  record_drift "search: missing flags:${missing_search}"
else
  record_pass "All expected search flags present"
fi

# Check for unexpected new flags in search (informational)
# Extract all --flags from help output
SEARCH_ACTUAL_FLAGS=$(echo "$SEARCH_HELP" | grep -oE '\-\-[a-z][-a-z]*' | sort -u || true)
new_search=""
for actual_flag in $SEARCH_ACTUAL_FLAGS; do
  found=0
  for expected_flag in $SEARCH_EXPECTED_FLAGS; do
    if [ "$actual_flag" = "$expected_flag" ]; then
      found=1
      break
    fi
  done
  # Exclude --help as it is always present
  if [ "$found" -eq 0 ] && [ "$actual_flag" != "--help" ]; then
    new_search="${new_search} ${actual_flag}"
  fi
done

if [ -n "$new_search" ]; then
  echo "  INFO: New flags detected in search:${new_search}"
  DIFF_OUTPUT="${DIFF_OUTPUT}INFO: New flags detected in search:${new_search}
"
fi

# ---------------------------------------------------------------------------
# Check 4: vector-search --help flag presence
# ---------------------------------------------------------------------------
CHECK_COUNT=$((CHECK_COUNT + 1))
echo "Check 4: vector-search --help flag presence"
VSEARCH_HELP=$(maproom vector-search --help 2>&1 || true)

missing_vsearch=""
for flag in $VSEARCH_EXPECTED_FLAGS; do
  if ! echo "$VSEARCH_HELP" | grep -q -- "$flag"; then
    missing_vsearch="${missing_vsearch} ${flag}"
  fi
done

if [ -n "$missing_vsearch" ]; then
  record_drift "vector-search: missing flags:${missing_vsearch}"
else
  record_pass "All expected vector-search flags present"
fi

# Check for unexpected new flags in vector-search (informational)
VSEARCH_ACTUAL_FLAGS=$(echo "$VSEARCH_HELP" | grep -oE '\-\-[a-z][-a-z]*' | sort -u || true)
new_vsearch=""
for actual_flag in $VSEARCH_ACTUAL_FLAGS; do
  found=0
  for expected_flag in $VSEARCH_EXPECTED_FLAGS; do
    if [ "$actual_flag" = "$expected_flag" ]; then
      found=1
      break
    fi
  done
  # Exclude --help as it is always present
  if [ "$found" -eq 0 ] && [ "$actual_flag" != "--help" ]; then
    new_vsearch="${new_vsearch} ${actual_flag}"
  fi
done

if [ -n "$new_vsearch" ]; then
  echo "  INFO: New flags detected in vector-search:${new_vsearch}"
  DIFF_OUTPUT="${DIFF_OUTPUT}INFO: New flags detected in vector-search:${new_vsearch}
"
fi

# ---------------------------------------------------------------------------
# Check 5: Full help text comparison (if baseline file provided)
# ---------------------------------------------------------------------------
CHECK_COUNT=$((CHECK_COUNT + 1))
echo "Check 5: Full help text comparison"

if [ -n "$BASELINE_FILE" ] && [ -f "$BASELINE_FILE" ]; then
  # Extract the search --help block from baseline
  BASELINE_SEARCH=$(sed -n '/^Full `search --help` output:/,/^```$/{ /^```$/!p; }' "$BASELINE_FILE" | sed '1d; /^```/d' || true)
  BASELINE_VSEARCH=$(sed -n '/^Full `vector-search --help` output:/,/^```$/{ /^```$/!p; }' "$BASELINE_FILE" | sed '1d; /^```/d' || true)

  # Normalize whitespace for comparison
  NORM_SEARCH_HELP=$(echo "$SEARCH_HELP" | sed 's/[[:space:]]*$//' | sed '/^$/d')
  NORM_BASELINE_SEARCH=$(echo "$BASELINE_SEARCH" | sed 's/[[:space:]]*$//' | sed '/^$/d')
  NORM_VSEARCH_HELP=$(echo "$VSEARCH_HELP" | sed 's/[[:space:]]*$//' | sed '/^$/d')
  NORM_BASELINE_VSEARCH=$(echo "$BASELINE_VSEARCH" | sed 's/[[:space:]]*$//' | sed '/^$/d')

  # Compare search help
  SEARCH_DIFF=$(diff <(echo "$NORM_BASELINE_SEARCH") <(echo "$NORM_SEARCH_HELP") 2>/dev/null || true)
  if [ -n "$SEARCH_DIFF" ] && [ -n "$NORM_BASELINE_SEARCH" ]; then
    record_drift "search --help text differs from baseline"
    DIFF_OUTPUT="${DIFF_OUTPUT}--- search --help diff ---
${SEARCH_DIFF}
"
    echo "$SEARCH_DIFF"
  elif [ -z "$NORM_BASELINE_SEARCH" ]; then
    echo "  SKIP: Could not extract search --help baseline from file"
  else
    record_pass "search --help text matches baseline"
  fi

  # Compare vector-search help
  VSEARCH_DIFF=$(diff <(echo "$NORM_BASELINE_VSEARCH") <(echo "$NORM_VSEARCH_HELP") 2>/dev/null || true)
  if [ -n "$VSEARCH_DIFF" ] && [ -n "$NORM_BASELINE_VSEARCH" ]; then
    record_drift "vector-search --help text differs from baseline"
    DIFF_OUTPUT="${DIFF_OUTPUT}--- vector-search --help diff ---
${VSEARCH_DIFF}
"
    echo "$VSEARCH_DIFF"
  elif [ -z "$NORM_BASELINE_VSEARCH" ]; then
    echo "  SKIP: Could not extract vector-search --help baseline from file"
  else
    record_pass "vector-search --help text matches baseline"
  fi
else
  if [ -n "$BASELINE_FILE" ]; then
    echo "  SKIP: Baseline file not found at $BASELINE_FILE"
  else
    record_pass "No baseline file specified (flag-level checks sufficient)"
  fi
fi

# ---------------------------------------------------------------------------
# Output full help text for CI logs
# ---------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "Current CLI Help Output (for CI logs)"
echo "=========================================="
echo ""
echo "--- maproom --version ---"
maproom --version 2>&1 || true
echo ""
echo "--- maproom search --help ---"
echo "$SEARCH_HELP"
echo ""
echo "--- maproom vector-search --help ---"
echo "$VSEARCH_HELP"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "CLI Verification Summary"
echo "=========================================="
echo "Checks: $CHECK_COUNT"
echo "Drift detected: $DRIFT_COUNT"
echo ""

if [ "$DRIFT_COUNT" -eq 0 ]; then
  echo "Status: NO DRIFT DETECTED"
  exit 0
else
  echo "Status: DRIFT DETECTED"
  echo ""
  echo "Drift details:"
  echo "$DIFF_OUTPUT"
  exit 1
fi
