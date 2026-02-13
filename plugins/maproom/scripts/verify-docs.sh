#!/usr/bin/env zsh
# verify-docs.sh - Automated documentation consistency checks
#
# Executes all 11 grep-based consistency checks from quality-strategy.md
# to verify maproom plugin documentation integrity.
#
# Usage: verify-docs.sh [--help]
# Exit codes: 0 = all checks pass, 1 = one or more checks failed

set -e

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
  cat <<'USAGE'
verify-docs.sh - Automated documentation consistency checks for maproom plugin

USAGE:
  verify-docs.sh [--help]

DESCRIPTION:
  Executes all 11 grep-based consistency checks from quality-strategy.md
  and reports PASS/FAIL for each. Designed for CI/CD integration.

OPTIONS:
  --help, -h    Show this help message and exit

CHECKS:
  1.  --format agent occurrences in SKILL.md (>= 10)
  2.  --format agent occurrences in multi-repo-guide.md (>= 15)
  3.  Bare search commands in SKILL.md (only allowed in Output Formats section)
  4.  Bare search commands in multi-repo-guide.md (zero expected)
  5.  --format agent in search-best-practices.md (>= 1)
  6.  --kind/--lang in search-best-practices.md (>= 1)
  7.  Agent-optimized output mention in README.md (>= 1)
  8.  Output Formats and Filtering sections in SKILL.md (= 2)
  9.  New flags (--kind/--lang/--preview/--preview-length/--threshold) in SKILL.md (>= 5)
  10. --format agent in troubleshooting.md (= 0, must not appear)
  11. Cross-reference integrity (./references/*.md and ./templates/* links in SKILL.md)

EXIT CODES:
  0   All checks passed
  1   One or more checks failed

EXAMPLES:
  # Run from anywhere inside the repository
  verify-docs.sh

  # Run from the repository root
  plugins/maproom/scripts/verify-docs.sh
USAGE
  exit 0
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
  echo "Error: maproom plugin not found at $PLUGIN_DIR"
  exit 1
fi

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0
TOTAL_CHECKS=11

# ---------------------------------------------------------------------------
# Helper: report result
# ---------------------------------------------------------------------------
report_pass() {
  echo "  PASS: $1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

report_fail() {
  echo "  FAIL: $1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

# ===========================================================================
# Check 1: --format agent presence in SKILL.md (>= 10)
# ===========================================================================
echo "Check 1: --format agent presence in SKILL.md"
count=$(grep -c "\-\-format agent" "$SKILL_MD" || true)
if [ "$count" -ge 10 ]; then
  report_pass "$count occurrences (>= 10 required)"
else
  report_fail "$count occurrences (>= 10 required)"
fi

# ===========================================================================
# Check 2: --format agent presence in multi-repo-guide.md (>= 15)
# ===========================================================================
echo "Check 2: --format agent presence in multi-repo-guide.md"
count=$(grep -c "\-\-format agent" "$MULTI_REPO_MD" || true)
if [ "$count" -ge 15 ]; then
  report_pass "$count occurrences (>= 15 required)"
else
  report_fail "$count occurrences (>= 15 required)"
fi

# ===========================================================================
# Check 3: Bare search commands in SKILL.md (only in Output Formats section)
# ===========================================================================
echo "Check 3: Bare search commands in SKILL.md (only in Output Formats section)"
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
      echo "    WARNING: Bare command at line $line_num (outside Output Formats section)"
    fi
  done <<EOF
$bare_lines
EOF

  if [ "$bare_outside_section" -eq 0 ]; then
    report_pass "Bare commands found only in Output Formats section"
  else
    report_fail "$bare_outside_section bare command(s) found outside Output Formats section"
  fi
else
  report_pass "No bare search commands found"
fi

# ===========================================================================
# Check 4: Bare search commands in multi-repo-guide.md (zero expected)
# ===========================================================================
echo "Check 4: Bare search commands in multi-repo-guide.md (zero expected)"
bare_lines=$(grep -n "crewchief-maproom search\|crewchief-maproom vector-search" "$MULTI_REPO_MD" | grep -v "\-\-format agent" || true)
if [ -z "$bare_lines" ]; then
  report_pass "No bare search commands found"
else
  bare_count=$(echo "$bare_lines" | wc -l | tr -d ' ')
  report_fail "$bare_count bare search command(s) found without --format agent"
  echo "$bare_lines" | while IFS= read -r line; do
    echo "    Line: $line"
  done
fi

# ===========================================================================
# Check 5: --format agent in search-best-practices.md (>= 1)
# ===========================================================================
echo "Check 5: --format agent in search-best-practices.md"
count=$(grep -c "\-\-format agent" "$BEST_PRACTICES_MD" || true)
if [ "$count" -ge 1 ]; then
  report_pass "$count occurrences (>= 1 required)"
else
  report_fail "$count occurrences (>= 1 required)"
fi

# ===========================================================================
# Check 6: Filtering flags in search-best-practices.md (>= 1)
# ===========================================================================
echo "Check 6: --kind/--lang in search-best-practices.md"
count=$(grep -c "\-\-kind\|\-\-lang" "$BEST_PRACTICES_MD" || true)
if [ "$count" -ge 1 ]; then
  report_pass "$count occurrences (>= 1 required)"
else
  report_fail "$count occurrences (>= 1 required)"
fi

# ===========================================================================
# Check 7: Agent-optimized output in README.md (>= 1)
# ===========================================================================
echo "Check 7: Agent-optimized output mention in README.md"
count=$(grep -i -c "agent.optimized\|format agent" "$README_MD" || true)
if [ "$count" -ge 1 ]; then
  report_pass "$count occurrences (>= 1 required)"
else
  report_fail "$count occurrences (>= 1 required)"
fi

# ===========================================================================
# Check 8: Output Formats and Filtering sections in SKILL.md (= 2)
# ===========================================================================
echo "Check 8: Output Formats and Filtering sections in SKILL.md"
count=$(grep -c "## Output Formats\|## Filtering" "$SKILL_MD" || true)
if [ "$count" -eq 2 ]; then
  report_pass "$count sections found (exactly 2 required)"
else
  report_fail "$count sections found (exactly 2 required)"
fi

# ===========================================================================
# Check 9: New flags documented in SKILL.md (>= 5)
# ===========================================================================
echo "Check 9: New flags (--kind/--lang/--preview/--preview-length/--threshold) in SKILL.md"
count=$(grep -c "\-\-kind\|\-\-lang\|\-\-preview\|\-\-preview-length\|\-\-threshold" "$SKILL_MD" || true)
if [ "$count" -ge 5 ]; then
  report_pass "$count occurrences (>= 5 required)"
else
  report_fail "$count occurrences (>= 5 required)"
fi

# ===========================================================================
# Check 10: --format agent in troubleshooting.md (= 0)
# ===========================================================================
echo "Check 10: --format agent in troubleshooting.md (must be 0)"
count=$(grep -c "\-\-format agent" "$TROUBLESHOOTING_MD" || true)
if [ "$count" -eq 0 ]; then
  report_pass "0 occurrences (diagnostic commands correctly omit --format agent)"
else
  report_fail "$count occurrences found (expected 0 -- diagnostic commands must not include --format agent)"
fi

# ===========================================================================
# Check 11: Cross-reference integrity (./references/*.md and ./templates/* in SKILL.md)
# ===========================================================================
echo "Check 11: Cross-reference integrity (./references/*.md and ./templates/* links in SKILL.md)"

broken=0
total_refs=0

# --- 11a: Check ./references/*.md links ---
refs=$(grep -o '\./references/[a-z_-]*\.md' "$SKILL_MD" | sort -u || true)
if [ -z "$refs" ]; then
  echo "    WARNING: No ./references/*.md links found in SKILL.md"
else
  while IFS= read -r ref; do
    if [ -z "$ref" ]; then
      continue
    fi
    total_refs=$((total_refs + 1))
    target="$SKILL_DIR/$ref"
    if [ ! -f "$target" ]; then
      echo "    BROKEN: $ref -> $target does not exist"
      broken=$((broken + 1))
    fi
  done <<EOF
$refs
EOF
fi

# --- 11b: Check ./templates/*.yaml|yml|json|toml links ---
tmpl_refs=$(grep -o '\./templates/[a-z_-]*\.\(yaml\|yml\|json\|toml\)' "$SKILL_MD" | sort -u || true)
if [ -z "$tmpl_refs" ]; then
  echo "    INFO: No ./templates/* references found in SKILL.md (as expected if none exist)"
else
  while IFS= read -r ref; do
    if [ -z "$ref" ]; then
      continue
    fi
    total_refs=$((total_refs + 1))
    target="$SKILL_DIR/$ref"
    if [ ! -f "$target" ]; then
      echo "    BROKEN: $ref -> $target does not exist"
      broken=$((broken + 1))
    fi
  done <<EOF
$tmpl_refs
EOF
fi

# --- 11: Report result ---
if [ "$total_refs" -eq 0 ]; then
  report_fail "No cross-references found in SKILL.md"
elif [ "$broken" -eq 0 ]; then
  report_pass "All $total_refs cross-references resolve to existing files"
else
  report_fail "$broken of $total_refs cross-references are broken"
fi

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "=========================================="
echo "Verification Summary"
echo "=========================================="
echo "Passed: $PASS_COUNT / $TOTAL_CHECKS"
echo "Failed: $FAIL_COUNT / $TOTAL_CHECKS"
echo ""

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "Status: ALL CHECKS PASSED"
  exit 0
else
  echo "Status: SOME CHECKS FAILED"
  exit 1
fi
