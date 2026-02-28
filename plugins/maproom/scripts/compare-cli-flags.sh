#!/usr/bin/env zsh
# compare-cli-flags.sh - Automated baseline diff tool for CLI flags
#
# Compares current maproom CLI flags against the baseline
# documented in cli-flag-verification.md. Extracts flags from both
# 'search --help' and 'vector-search --help' outputs, then diffs
# against the baseline flag tables.
#
# Usage: compare-cli-flags.sh [--help] [--baseline FILE]
# Exit codes: 0 = no drift, 1 = drift detected, 2 = usage error / CLI unavailable
#
# Expected baseline format:
#   Markdown file with flag tables using "| Flag | Present |" headers
#   and full help output blocks fenced in ``` code blocks.
#
# Reference: MAPAGENT.5002 (automated-baseline-diff)

set -e

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
  cat <<'USAGE'
compare-cli-flags.sh - Automated CLI flag baseline diff tool

USAGE:
  compare-cli-flags.sh [--help] [--baseline FILE]

DESCRIPTION:
  Compares current maproom CLI help output against the baseline
  documented in cli-flag-verification.md. Extracts flag names from both
  the baseline document and live CLI output, then reports any discrepancies.

  This reduces manual flag verification from 5-10 minutes to <10 seconds
  and eliminates human error in detecting subtle flag changes.

OPTIONS:
  --help, -h           Show this help message and exit
  --baseline FILE      Path to baseline cli-flag-verification.md
                       Default: auto-detected relative to script location

DETECTION:
  - Added flags:   Present in current CLI but not in baseline
  - Removed flags: Present in baseline but not in current CLI
  Checks both 'search' and 'vector-search' subcommands independently.

EXIT CODES:
  0   No drift detected - baseline matches current CLI
  1   Drift detected - flags differ between baseline and current
  2   Usage error (missing baseline file, CLI unavailable, parse failure)

EXAMPLES:
  # Run with auto-detected baseline
  compare-cli-flags.sh

  # Run with explicit baseline path
  compare-cli-flags.sh --baseline /path/to/cli-flag-verification.md

  # CI/CD usage
  bash plugins/maproom/scripts/compare-cli-flags.sh
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
      if [ $# -eq 0 ]; then
        echo "Error: --baseline requires a file path argument"
        exit 2
      fi
      BASELINE_FILE="$1"
      ;;
    *)
      echo "Error: Unknown option: $1"
      echo "Run with --help for usage information."
      exit 2
      ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Resolve baseline file path
# ---------------------------------------------------------------------------
if [ -z "$BASELINE_FILE" ]; then
  # Auto-detect: resolve relative to script location
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  # Script is at: <repo-root>/plugins/maproom/scripts/compare-cli-flags.sh
  REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)

  # Two-root model: /workspace/repos/<project>/<worktree> and /workspace/_SPECS/<project>
  # From REPO_ROOT, go up to /workspace level, then into _SPECS
  WORKSPACE_ROOT="$(cd "$REPO_ROOT/../../.." && pwd)"
  SPECS_ROOT="$WORKSPACE_ROOT/_SPECS/claude-code-plugins"
  BASELINE_CANDIDATE="$SPECS_ROOT/tickets/MAPAGENT_format-agent-skill/planning/deliverables/cli-flag-verification.md"

  if [ -f "$BASELINE_CANDIDATE" ]; then
    BASELINE_FILE="$BASELINE_CANDIDATE"
  else
    echo "Error: Baseline file not found."
    echo "Searched: $BASELINE_CANDIDATE"
    echo ""
    echo "Use --baseline to specify the path explicitly:"
    echo "  compare-cli-flags.sh --baseline /path/to/cli-flag-verification.md"
    exit 2
  fi
fi

if [ ! -f "$BASELINE_FILE" ]; then
  echo "Error: Baseline file not found: $BASELINE_FILE"
  exit 2
fi

# ---------------------------------------------------------------------------
# Check CLI availability
# ---------------------------------------------------------------------------
if ! command -v maproom >/dev/null 2>&1; then
  echo "Error: maproom not found in PATH"
  echo "Install the CLI or ensure it is available before running this script."
  exit 2
fi

# ---------------------------------------------------------------------------
# Get current CLI version
# ---------------------------------------------------------------------------
CURRENT_VERSION=$(maproom --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
if [ -z "$CURRENT_VERSION" ]; then
  CURRENT_VERSION="unknown"
fi

# ---------------------------------------------------------------------------
# Extract baseline flags from cli-flag-verification.md
# ---------------------------------------------------------------------------
# Strategy: Parse flag tables that have "| Flag | Present |" headers.
# Extract flag names (column 1) from table rows, stripping backticks,
# pipes, and whitespace. Also extract "Additional flags" list items.

extract_baseline_flags_for_section() {
  # $1 = section heading pattern (e.g., "### search --help")
  # $2 = baseline file
  # Outputs one flag per line (e.g., --format)

  section="$1"
  file="$2"

  # Find line number of the section heading
  section_start=$(grep -n "$section" "$file" | head -1 | cut -d: -f1 || true)
  if [ -z "$section_start" ]; then
    return
  fi

  # Find next heading of same or higher level
  section_end=$(tail -n +"$((section_start + 1))" "$file" | grep -n "^##" | head -1 | cut -d: -f1 || true)
  if [ -z "$section_end" ]; then
    section_end=99999
  else
    section_end=$((section_start + section_end))
  fi

  # Extract the section content
  section_content=$(sed -n "${section_start},${section_end}p" "$file")

  # Extract flags from table rows: lines matching | `--flagname` | YES |
  # Only include flags where the Present column is YES (skip NO entries)
  echo "$section_content" | grep -E '^\|.*`--[a-z]' | grep -E '\| *YES *\|' | sed 's/^|[[:space:]]*//' | sed 's/[[:space:]]*|.*//' | sed 's/`//g' | sort -u

  # Extract flags from "Additional flags" bullet points: - `--flagname`
  # These are always present (no Present column), so include all
  echo "$section_content" | grep -E '^- `--[a-z]' | sed 's/^- `//' | sed 's/`.*$//' | sed 's/ (.*//' | sort -u
}

# Extract baseline flags for search subcommand
BASELINE_SEARCH_FLAGS=$(extract_baseline_flags_for_section "### search --help" "$BASELINE_FILE")

# Extract baseline flags for vector-search subcommand
BASELINE_VSEARCH_FLAGS=$(extract_baseline_flags_for_section "### vector-search --help" "$BASELINE_FILE")

# Validate that we extracted some flags (sanity check)
baseline_search_count=$(echo "$BASELINE_SEARCH_FLAGS" | grep -c "^--" || true)
baseline_vsearch_count=$(echo "$BASELINE_VSEARCH_FLAGS" | grep -c "^--" || true)

if [ "$baseline_search_count" -eq 0 ]; then
  echo "Warning: Could not extract any search flags from baseline document."
  echo "The baseline file format may have changed."
  echo "Expected table rows with \`--flag\` entries under '### search --help'."
  exit 2
fi

if [ "$baseline_vsearch_count" -eq 0 ]; then
  echo "Warning: Could not extract any vector-search flags from baseline document."
  echo "The baseline file format may have changed."
  echo "Expected table rows with \`--flag\` entries under '### vector-search --help'."
  exit 2
fi

# ---------------------------------------------------------------------------
# Extract current flags from CLI help output
# ---------------------------------------------------------------------------
extract_flags_from_help() {
  # $1 = help output text
  # Outputs one flag per line, sorted, unique
  # Extracts flags from option definition lines (lines starting with --flag after whitespace)
  # This avoids picking up flags mentioned in description text (e.g., --no-deduplicate)
  echo "$1" | grep -E '^\s+--[a-z]' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]].*//' | sort -u
}

SEARCH_HELP=$(maproom search --help 2>&1 || true)
VSEARCH_HELP=$(maproom vector-search --help 2>&1 || true)

CURRENT_SEARCH_FLAGS=$(extract_flags_from_help "$SEARCH_HELP")
CURRENT_VSEARCH_FLAGS=$(extract_flags_from_help "$VSEARCH_HELP")

current_search_count=$(echo "$CURRENT_SEARCH_FLAGS" | grep -c "^--" || true)
current_vsearch_count=$(echo "$CURRENT_VSEARCH_FLAGS" | grep -c "^--" || true)

if [ "$current_search_count" -eq 0 ]; then
  echo "Warning: Could not extract any flags from 'maproom search --help'."
  echo "The CLI help output format may have changed."
  exit 2
fi

if [ "$current_vsearch_count" -eq 0 ]; then
  echo "Warning: Could not extract any flags from 'maproom vector-search --help'."
  echo "The CLI help output format may have changed."
  exit 2
fi

# ---------------------------------------------------------------------------
# Diff: Compare baseline vs current for each subcommand
# ---------------------------------------------------------------------------
DRIFT_FOUND=0

# Helper: find items in set A that are not in set B
# Uses grep -e to avoid "--flag" being interpreted as a grep option
set_difference() {
  # $1 = set A (one item per line)
  # $2 = set B (one item per line)
  # Outputs items in A not in B
  if [ -z "$1" ]; then
    return
  fi
  if [ -z "$2" ]; then
    echo "$1"
    return
  fi
  echo "$1" | while IFS= read -r item; do
    if [ -z "$item" ]; then
      continue
    fi
    # Use -e to pass pattern explicitly (prevents --flag being parsed as grep option)
    if ! echo "$2" | grep -qFx -e "$item"; then
      echo "$item"
    fi
  done
}

# --- search subcommand ---
SEARCH_ADDED=$(set_difference "$CURRENT_SEARCH_FLAGS" "$BASELINE_SEARCH_FLAGS")
SEARCH_REMOVED=$(set_difference "$BASELINE_SEARCH_FLAGS" "$CURRENT_SEARCH_FLAGS")

# Filter out --help from added (always present in CLI, may not be in baseline table)
if [ -n "$SEARCH_ADDED" ]; then
  SEARCH_ADDED=$(echo "$SEARCH_ADDED" | grep -v -e "^--help$" || true)
fi

search_added_count=0
if [ -n "$SEARCH_ADDED" ]; then
  search_added_count=$(echo "$SEARCH_ADDED" | grep -c "^--" || true)
fi
search_removed_count=0
if [ -n "$SEARCH_REMOVED" ]; then
  search_removed_count=$(echo "$SEARCH_REMOVED" | grep -c "^--" || true)
fi

# --- vector-search subcommand ---
VSEARCH_ADDED=$(set_difference "$CURRENT_VSEARCH_FLAGS" "$BASELINE_VSEARCH_FLAGS")
VSEARCH_REMOVED=$(set_difference "$BASELINE_VSEARCH_FLAGS" "$CURRENT_VSEARCH_FLAGS")

# Filter out --help from added
if [ -n "$VSEARCH_ADDED" ]; then
  VSEARCH_ADDED=$(echo "$VSEARCH_ADDED" | grep -v -e "^--help$" || true)
fi

vsearch_added_count=0
if [ -n "$VSEARCH_ADDED" ]; then
  vsearch_added_count=$(echo "$VSEARCH_ADDED" | grep -c "^--" || true)
fi
vsearch_removed_count=0
if [ -n "$VSEARCH_REMOVED" ]; then
  vsearch_removed_count=$(echo "$VSEARCH_REMOVED" | grep -c "^--" || true)
fi

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
echo "CLI Flag Drift Report"
echo "====================="
echo "Baseline: cli-flag-verification.md"
echo "Current:  maproom $CURRENT_VERSION"
echo ""

# --- search section ---
echo "search subcommand"
echo "-----------------"
echo "Baseline flags: $baseline_search_count"
echo "Current flags:  $current_search_count (excluding --help)"
echo ""

if [ "$search_added_count" -gt 0 ]; then
  DRIFT_FOUND=1
  echo "Added flags ($search_added_count):"
  echo "$SEARCH_ADDED" | while IFS= read -r flag; do
    if [ -n "$flag" ]; then
      echo "  $flag"
    fi
  done
  echo ""
fi

if [ "$search_removed_count" -gt 0 ]; then
  DRIFT_FOUND=1
  echo "Removed flags ($search_removed_count):"
  echo "$SEARCH_REMOVED" | while IFS= read -r flag; do
    if [ -n "$flag" ]; then
      echo "  $flag"
    fi
  done
  echo ""
fi

if [ "$search_added_count" -eq 0 ] && [ "$search_removed_count" -eq 0 ]; then
  echo "No drift detected."
  echo ""
fi

# --- vector-search section ---
echo "vector-search subcommand"
echo "------------------------"
echo "Baseline flags: $baseline_vsearch_count"
echo "Current flags:  $current_vsearch_count (excluding --help)"
echo ""

if [ "$vsearch_added_count" -gt 0 ]; then
  DRIFT_FOUND=1
  echo "Added flags ($vsearch_added_count):"
  echo "$VSEARCH_ADDED" | while IFS= read -r flag; do
    if [ -n "$flag" ]; then
      echo "  $flag"
    fi
  done
  echo ""
fi

if [ "$vsearch_removed_count" -gt 0 ]; then
  DRIFT_FOUND=1
  echo "Removed flags ($vsearch_removed_count):"
  echo "$VSEARCH_REMOVED" | while IFS= read -r flag; do
    if [ -n "$flag" ]; then
      echo "  $flag"
    fi
  done
  echo ""
fi

if [ "$vsearch_added_count" -eq 0 ] && [ "$vsearch_removed_count" -eq 0 ]; then
  echo "No drift detected."
  echo ""
fi

# --- Result ---
echo "====================="
if [ "$DRIFT_FOUND" -eq 0 ]; then
  echo "Result: NO DRIFT (exit 0)"
  exit 0
else
  total_added=$((search_added_count + vsearch_added_count))
  total_removed=$((search_removed_count + vsearch_removed_count))
  echo "Result: DRIFT DETECTED (exit 1)"
  echo "  Total added:   $total_added"
  echo "  Total removed: $total_removed"
  exit 1
fi
