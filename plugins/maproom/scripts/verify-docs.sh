#!/usr/bin/env zsh
# verify-docs.sh - Automated documentation consistency checks
#
# Executes all 11 grep-based consistency checks from quality-strategy.md
# to verify maproom plugin documentation integrity.
#
# Usage: verify-docs.sh [--help] [--json]
# Exit codes: 0 = all checks pass, 1 = one or more checks failed

set -e

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
  cat <<'USAGE'
verify-docs.sh - Automated documentation consistency checks for maproom plugin

USAGE:
  verify-docs.sh [--help] [--json]

DESCRIPTION:
  Executes all 11 grep-based consistency checks from quality-strategy.md
  and reports PASS/FAIL for each. Designed for CI/CD integration.

OPTIONS:
  --help, -h    Show this help message and exit
  --json        Output results as JSON array instead of human-readable text

CHECKS:
  1.  --format agent occurrences in SKILL.md (>= 10)
  2.  --format agent occurrences in multi-repo-guide.md (>= 15)
  3.  Bare search commands in SKILL.md (only allowed in Output Formats section)
  4.  Bare search commands in multi-repo-guide.md (zero in code blocks)
  5.  --format agent in search-best-practices.md (>= 1)
  6.  --kind/--lang in search-best-practices.md (>= 1)
  7.  Agent-optimized output mention in README.md (>= 1)
  8.  Output Formats and Filtering sections in SKILL.md (= 2)
  9.  New flags (--kind/--lang/--preview/--preview-length/--threshold) in SKILL.md (>= 5)
  10. --format agent in troubleshooting.md (informational)
  11. Cross-reference integrity (./references/*.md and ./templates/* links in SKILL.md)

EXIT CODES:
  0   All checks passed
  1   One or more checks failed

EXAMPLES:
  # Run from anywhere inside the repository
  verify-docs.sh

  # Run from the repository root
  plugins/maproom/scripts/verify-docs.sh

  # Output as JSON for automated processing
  verify-docs.sh --json

  # Validate JSON output
  verify-docs.sh --json | jq .
USAGE
  exit 0
fi

# ---------------------------------------------------------------------------
# Output mode detection
# ---------------------------------------------------------------------------
OUTPUT_MODE="human"
if [ "$1" = "--json" ]; then
  OUTPUT_MODE="json"
fi

# ---------------------------------------------------------------------------
# Detect repo root
# ---------------------------------------------------------------------------
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
PLUGIN_DIR="$REPO_ROOT/plugins/maproom"
SKILL_DIR="$PLUGIN_DIR/skills/maproom-search"
SKILL_MD="$SKILL_DIR/SKILL.md"
MULTI_REPO_MD="$SKILL_DIR/references/multi-repo-guide.md"
BEST_PRACTICES_MD="$SKILL_DIR/references/search-best-practices.md"
TROUBLESHOOTING_MD="$SKILL_DIR/references/troubleshooting.md"
README_MD="$PLUGIN_DIR/README.md"

# ---------------------------------------------------------------------------
# Validate plugin directory exists
# ---------------------------------------------------------------------------
if [ ! -d "$PLUGIN_DIR" ]; then
  if [ "$OUTPUT_MODE" = "json" ]; then
    printf '[]'
  else
    echo "Error: maproom plugin not found at $PLUGIN_DIR"
  fi
  exit 1
fi

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0
TOTAL_CHECKS=11

# ---------------------------------------------------------------------------
# JSON accumulation
# ---------------------------------------------------------------------------
JSON_RESULT_COUNT=0
JSON_RESULTS=""

# json_escape: escape special characters for JSON string values
# Handles: backslash, double quote, newline, tab, carriage return
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' | tr -d '\n\r'
}

# json_add_result: accumulate a check result for JSON output
# Args: id name status count threshold message
# count and threshold should be a number or "null" (without quotes) for null
json_add_result() {
  _id="$1"
  _name=$(json_escape "$2")
  _status="$3"
  _count="$4"
  _threshold="$5"
  _message=$(json_escape "$6")

  _obj=$(printf '{"id":%s,"name":"%s","status":"%s","count":%s,"threshold":%s,"message":"%s"}' \
    "$_id" "$_name" "$_status" "$_count" "$_threshold" "$_message")

  if [ "$JSON_RESULT_COUNT" -gt 0 ]; then
    JSON_RESULTS="${JSON_RESULTS},${_obj}"
  else
    JSON_RESULTS="${_obj}"
  fi
  JSON_RESULT_COUNT=$((JSON_RESULT_COUNT + 1))
}

# ---------------------------------------------------------------------------
# Helper: report result (human output + JSON accumulation)
# ---------------------------------------------------------------------------
report_pass() {
  if [ "$OUTPUT_MODE" = "human" ]; then
    echo "  PASS: $1"
  fi
  PASS_COUNT=$((PASS_COUNT + 1))
}

report_fail() {
  if [ "$OUTPUT_MODE" = "human" ]; then
    echo "  FAIL: $1"
  fi
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

# human_echo: only print in human mode
human_echo() {
  if [ "$OUTPUT_MODE" = "human" ]; then
    echo "$@"
  fi
}

# ===========================================================================
# Check 1: --format agent presence in SKILL.md (>= 10)
# ===========================================================================
human_echo "Check 1: --format agent presence in SKILL.md"
count=$(grep -c "\-\-format agent" "$SKILL_MD" || true)
if [ "$count" -ge 10 ]; then
  report_pass "$count occurrences (>= 10 required)"
  json_add_result 1 "--format agent presence in SKILL.md" "pass" "$count" 10 "$count occurrences (>= 10 required)"
else
  report_fail "$count occurrences (>= 10 required)"
  json_add_result 1 "--format agent presence in SKILL.md" "fail" "$count" 10 "$count occurrences (>= 10 required)"
fi

# ===========================================================================
# Check 2: --format agent presence in multi-repo-guide.md (>= 15)
# ===========================================================================
human_echo "Check 2: --format agent presence in multi-repo-guide.md"
count=$(grep -c "\-\-format agent" "$MULTI_REPO_MD" || true)
if [ "$count" -ge 15 ]; then
  report_pass "$count occurrences (>= 15 required)"
  json_add_result 2 "--format agent presence in multi-repo-guide.md" "pass" "$count" 15 "$count occurrences (>= 15 required)"
else
  report_fail "$count occurrences (>= 15 required)"
  json_add_result 2 "--format agent presence in multi-repo-guide.md" "fail" "$count" 15 "$count occurrences (>= 15 required)"
fi

# ===========================================================================
# Check 3: Bare search commands in SKILL.md (only in Output Formats section)
# ===========================================================================
human_echo "Check 3: Bare search commands in SKILL.md (only in Output Formats section)"
# Find search/vector-search commands that do NOT include --format agent
bare_lines=$(grep -n "crewchief-maproom search\|crewchief-maproom vector-search" "$SKILL_MD" | grep -v "\-\-format agent" || true)
if [ -n "$bare_lines" ]; then
  # Find the line range for the Output Formats section
  # Start: line with "## Output Formats"
  # End: next "## " heading after Output Formats
  section_start=$(grep -n "## Output Formats" "$SKILL_MD" | head -1 | cut -d: -f1 || true)
  section_end=$(grep -n "^## " "$SKILL_MD" | awk -F: -v start="$section_start" '$1 > start { print $1; exit }' || true)

  # If no next section found, use end of file
  if [ -z "$section_end" ]; then
    section_end=99999
  fi

  # Use heredoc to avoid subshell variable scoping issues with pipe
  bare_outside_section=0
  while IFS= read -r line; do
    if [ -z "$line" ]; then
      continue
    fi
    line_num=$(echo "$line" | cut -d: -f1)
    if [ -n "$section_start" ] && [ "$line_num" -ge "$section_start" ] && [ "$line_num" -lt "$section_end" ]; then
      : # Inside Output Formats section, acceptable
    else
      bare_outside_section=$((bare_outside_section + 1))
      human_echo "    WARNING: Bare command at line $line_num (outside Output Formats section)"
    fi
  done <<EOF
$bare_lines
EOF

  if [ "$bare_outside_section" -eq 0 ]; then
    report_pass "Bare commands found only in Output Formats section"
    json_add_result 3 "Bare search commands in SKILL.md" "pass" "$bare_outside_section" 0 "Bare commands found only in Output Formats section"
  else
    report_fail "$bare_outside_section bare command(s) found outside Output Formats section"
    json_add_result 3 "Bare search commands in SKILL.md" "fail" "$bare_outside_section" 0 "$bare_outside_section bare command(s) found outside Output Formats section"
  fi
else
  report_pass "No bare search commands found"
  json_add_result 3 "Bare search commands in SKILL.md" "pass" 0 0 "No bare search commands found"
fi

# ===========================================================================
# Check 4: Bare search commands in multi-repo-guide.md (zero in code blocks)
# ===========================================================================
human_echo "Check 4: Bare search commands in multi-repo-guide.md (zero in code blocks)"
# Find lines with search commands missing --format agent
bare_lines=$(grep -n "crewchief-maproom search\|crewchief-maproom vector-search" "$MULTI_REPO_MD" | grep -v "\-\-format agent" || true)
if [ -z "$bare_lines" ]; then
  report_pass "No bare search commands found"
  json_add_result 4 "Bare search commands in multi-repo-guide.md" "pass" 0 0 "No bare search commands found"
else
  # Filter to only flag actual command invocations (in code blocks),
  # not prose descriptions. Command lines start with optional whitespace
  # then the command, or with $ prompt. Prose mentions have other words first.
  bare_commands=0
  while IFS= read -r line; do
    if [ -z "$line" ]; then
      continue
    fi
    # Extract content after line number (remove "NNN:" prefix)
    content=$(echo "$line" | sed 's/^[0-9]*://')
    # Check if content starts with the command (possibly indented) or $ prompt
    if echo "$content" | grep -qE "^\s*(crewchief-maproom|\\\$\s*crewchief-maproom)"; then
      bare_commands=$((bare_commands + 1))
      human_echo "    WARNING: Bare command: $line"
    fi
  done <<EOF
$bare_lines
EOF

  if [ "$bare_commands" -eq 0 ]; then
    report_pass "No bare search commands in code blocks (prose mentions excluded)"
    json_add_result 4 "Bare search commands in multi-repo-guide.md" "pass" "$bare_commands" 0 "No bare search commands in code blocks (prose mentions excluded)"
  else
    report_fail "$bare_commands bare search command(s) found in code blocks without --format agent"
    json_add_result 4 "Bare search commands in multi-repo-guide.md" "fail" "$bare_commands" 0 "$bare_commands bare search command(s) found in code blocks without --format agent"
  fi
fi

# ===========================================================================
# Check 5: --format agent in search-best-practices.md (>= 1)
# ===========================================================================
human_echo "Check 5: --format agent in search-best-practices.md"
count=$(grep -c "\-\-format agent" "$BEST_PRACTICES_MD" || true)
if [ "$count" -ge 1 ]; then
  report_pass "$count occurrences (>= 1 required)"
  json_add_result 5 "--format agent in search-best-practices.md" "pass" "$count" 1 "$count occurrences (>= 1 required)"
else
  report_fail "$count occurrences (>= 1 required)"
  json_add_result 5 "--format agent in search-best-practices.md" "fail" "$count" 1 "$count occurrences (>= 1 required)"
fi

# ===========================================================================
# Check 6: Filtering flags in search-best-practices.md (>= 1)
# ===========================================================================
human_echo "Check 6: --kind/--lang in search-best-practices.md"
count=$(grep -c "\-\-kind\|\-\-lang" "$BEST_PRACTICES_MD" || true)
if [ "$count" -ge 1 ]; then
  report_pass "$count occurrences (>= 1 required)"
  json_add_result 6 "--kind/--lang in search-best-practices.md" "pass" "$count" 1 "$count occurrences (>= 1 required)"
else
  report_fail "$count occurrences (>= 1 required)"
  json_add_result 6 "--kind/--lang in search-best-practices.md" "fail" "$count" 1 "$count occurrences (>= 1 required)"
fi

# ===========================================================================
# Check 7: Agent-optimized output in README.md (>= 1)
# ===========================================================================
human_echo "Check 7: Agent-optimized output mention in README.md"
count=$(grep -i -c "agent.optimized\|format agent" "$README_MD" || true)
if [ "$count" -ge 1 ]; then
  report_pass "$count occurrences (>= 1 required)"
  json_add_result 7 "Agent-optimized output mention in README.md" "pass" "$count" 1 "$count occurrences (>= 1 required)"
else
  report_fail "$count occurrences (>= 1 required)"
  json_add_result 7 "Agent-optimized output mention in README.md" "fail" "$count" 1 "$count occurrences (>= 1 required)"
fi

# ===========================================================================
# Check 8: Output Formats and Filtering sections in SKILL.md (= 2)
# ===========================================================================
human_echo "Check 8: Output Formats and Filtering sections in SKILL.md"
count=$(grep -c "## Output Formats\|## Filtering" "$SKILL_MD" || true)
if [ "$count" -eq 2 ]; then
  report_pass "$count sections found (exactly 2 required)"
  json_add_result 8 "Output Formats and Filtering sections in SKILL.md" "pass" "$count" 2 "$count sections found (exactly 2 required)"
else
  report_fail "$count sections found (exactly 2 required)"
  json_add_result 8 "Output Formats and Filtering sections in SKILL.md" "fail" "$count" 2 "$count sections found (exactly 2 required)"
fi

# ===========================================================================
# Check 9: New flags documented in SKILL.md (>= 5)
# ===========================================================================
human_echo "Check 9: New flags (--kind/--lang/--preview/--preview-length/--threshold) in SKILL.md"
count=$(grep -c "\-\-kind\|\-\-lang\|\-\-preview\|\-\-preview-length\|\-\-threshold" "$SKILL_MD" || true)
if [ "$count" -ge 5 ]; then
  report_pass "$count occurrences (>= 5 required)"
  json_add_result 9 "New flags (--kind/--lang/--preview/--preview-length/--threshold) in SKILL.md" "pass" "$count" 5 "$count occurrences (>= 5 required)"
else
  report_fail "$count occurrences (>= 5 required)"
  json_add_result 9 "New flags (--kind/--lang/--preview/--preview-length/--threshold) in SKILL.md" "fail" "$count" 5 "$count occurrences (>= 5 required)"
fi

# ===========================================================================
# Check 10: --format agent in troubleshooting.md (informational)
# ===========================================================================
human_echo "Check 10: --format agent in troubleshooting.md"
count=$(grep -c "\-\-format agent" "$TROUBLESHOOTING_MD" || true)
# Note: troubleshooting.md now legitimately contains --format agent in
# example commands (debugging workflow, fallback commands, error recovery).
# This check is informational only - presence is expected and valid.
report_pass "$count occurrences (informational -- troubleshooting examples may include --format agent)"
json_add_result 10 "--format agent in troubleshooting.md" "pass" "$count" null "$count occurrences (informational -- troubleshooting examples may include --format agent)"

# ===========================================================================
# Check 11: Cross-reference integrity (./references/*.md and ./templates/* in SKILL.md)
# ===========================================================================
human_echo "Check 11: Cross-reference integrity (./references/*.md and ./templates/* links in SKILL.md)"

broken=0
total_refs=0

# --- 11a: Check ./references/*.md links ---
refs=$(grep -o '\./references/[a-z_-]*\.md' "$SKILL_MD" | sort -u || true)
if [ -z "$refs" ]; then
  human_echo "    WARNING: No ./references/*.md links found in SKILL.md"
else
  while IFS= read -r ref; do
    if [ -z "$ref" ]; then
      continue
    fi
    total_refs=$((total_refs + 1))
    target="$SKILL_DIR/$ref"
    if [ ! -f "$target" ]; then
      human_echo "    BROKEN: $ref -> $target does not exist"
      broken=$((broken + 1))
    fi
  done <<EOF
$refs
EOF
fi

# --- 11b: Check ./templates/*.yaml|yml|json|toml links ---
tmpl_refs=$(grep -o '\./templates/[a-z_-]*\.\(yaml\|yml\|json\|toml\)' "$SKILL_MD" | sort -u || true)
if [ -z "$tmpl_refs" ]; then
  human_echo "    INFO: No ./templates/* references found in SKILL.md (as expected if none exist)"
else
  while IFS= read -r ref; do
    if [ -z "$ref" ]; then
      continue
    fi
    total_refs=$((total_refs + 1))
    target="$SKILL_DIR/$ref"
    if [ ! -f "$target" ]; then
      human_echo "    BROKEN: $ref -> $target does not exist"
      broken=$((broken + 1))
    fi
  done <<EOF
$tmpl_refs
EOF
fi

# --- 11: Report result ---
if [ "$total_refs" -eq 0 ]; then
  report_fail "No cross-references found in SKILL.md"
  json_add_result 11 "Cross-reference integrity" "fail" 0 0 "No cross-references found in SKILL.md"
elif [ "$broken" -eq 0 ]; then
  report_pass "All $total_refs cross-references resolve to existing files"
  json_add_result 11 "Cross-reference integrity" "pass" "$broken" 0 "All $total_refs cross-references resolve to existing files"
else
  report_fail "$broken of $total_refs cross-references are broken"
  json_add_result 11 "Cross-reference integrity" "fail" "$broken" 0 "$broken of $total_refs cross-references are broken"
fi

# ===========================================================================
# Output
# ===========================================================================
if [ "$OUTPUT_MODE" = "json" ]; then
  printf '[%s]\n' "$JSON_RESULTS"
else
  echo ""
  echo "=========================================="
  echo "Verification Summary"
  echo "=========================================="
  echo "Passed: $PASS_COUNT / $TOTAL_CHECKS"
  echo "Failed: $FAIL_COUNT / $TOTAL_CHECKS"
  echo ""

  if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "Status: ALL CHECKS PASSED"
  else
    echo "Status: SOME CHECKS FAILED"
  fi
fi

if [ "$FAIL_COUNT" -eq 0 ]; then
  exit 0
else
  exit 1
fi
