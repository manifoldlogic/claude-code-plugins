#!/bin/zsh
#
# check-template-drift.sh - CI check for template drift detection
#
# Compares section headers (## headings) from project-workflow templates
# to corresponding reference documents in document-authoring/references/.
# Detects when templates evolve but reference docs become outdated.
#
# Usage:
#   check-template-drift.sh [PLUGIN_ROOT]
#
# Arguments:
#   PLUGIN_ROOT - (Optional) Absolute path to the sdd plugin root.
#                 Defaults to auto-detection based on script location.
#
# Exit codes:
#   0 - No drift detected (reference docs are up to date)
#   1 - Drift detected (reference docs are missing template sections)
#   2 - Script error (missing files, invalid paths)
#
# How it works:
#   1. Extracts ## headings from each project-workflow template
#   2. Checks if each heading text appears in the corresponding reference doc
#   3. Reports any headings from templates not mentioned in reference docs
#
# When drift is detected:
#   Update the reference document to include guidance for the missing section.
#   Reference docs are in: plugins/sdd/skills/document-authoring/references/
#   Each reference doc has a "Template" subsection with a section table --
#   add the new section there and provide creation/review guidance.
#
# Template-to-reference mapping:
#   templates/ticket/analysis.md        -> references/doc-analysis.md
#   templates/ticket/prd.md             -> references/doc-prd.md
#   templates/ticket/architecture.md    -> references/doc-architecture.md
#   templates/ticket/plan.md            -> references/doc-plan.md
#   templates/ticket/quality-strategy.md -> references/doc-quality-strategy.md
#   templates/ticket/security-review.md -> references/doc-security-review.md
#

set -euo pipefail

# --- Determine plugin root ---
if [ "$#" -ge 1 ] && [ -n "$1" ]; then
    PLUGIN_ROOT="$1"
else
    # Auto-detect from script location
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    # Script is at plugins/sdd/skills/document-authoring/scripts/
    # Plugin root is plugins/sdd/
    PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
fi

if [ ! -d "$PLUGIN_ROOT" ]; then
    printf 'ERROR: Plugin root directory does not exist: %s\n' "$PLUGIN_ROOT" >&2
    exit 2
fi

TEMPLATE_DIR="$PLUGIN_ROOT/skills/project-workflow/templates/ticket"
REFERENCE_DIR="$PLUGIN_ROOT/skills/document-authoring/references"

if [ ! -d "$TEMPLATE_DIR" ]; then
    printf 'ERROR: Template directory does not exist: %s\n' "$TEMPLATE_DIR" >&2
    exit 2
fi

if [ ! -d "$REFERENCE_DIR" ]; then
    printf 'ERROR: Reference directory does not exist: %s\n' "$REFERENCE_DIR" >&2
    exit 2
fi

# --- Temp file for drift results (avoids subshell variable scoping) ---
_drift_report="$(mktemp)"
trap 'rm -f "$_drift_report"' EXIT

# --- Check one template against its reference doc ---
# Appends drift findings to the report file.
check_pair() {
    template_file="$1"
    reference_file="$2"
    template_path="$TEMPLATE_DIR/$template_file"
    reference_path="$REFERENCE_DIR/$reference_file"

    # Verify files exist
    if [ ! -f "$template_path" ]; then
        printf 'WARNING: Template file not found: %s\n' "$template_path" >&2
        return 0
    fi

    if [ ! -f "$reference_path" ]; then
        printf 'WARNING: Reference file not found: %s\n' "$reference_path" >&2
        return 0
    fi

    # Extract ## headings from template (level-2 only, strip the ## prefix)
    _headings="$(grep -E '^## ' "$template_path" | sed 's/^## //')" || true

    if [ -z "$_headings" ]; then
        return 0
    fi

    _missing=""

    # Use a here-string to avoid subshell from pipe
    while IFS= read -r section; do
        # Strip template placeholders like {NAME}, (Optional), etc.
        clean_section="$(printf '%s' "$section" | sed 's/{[^}]*}//g; s/([^)]*)//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"

        # Skip empty sections after cleanup
        if [ -z "$clean_section" ]; then
            continue
        fi

        # Use grep -F for literal match (no regex), case-insensitive
        if ! grep -qiF "$clean_section" "$reference_path" 2>/dev/null; then
            _missing="${_missing}    - ${section}\n"
        fi
    done <<< "$_headings"

    if [ -n "$_missing" ]; then
        {
            printf 'DRIFT DETECTED: %s\n' "$reference_file"
            printf '  Template: %s\n' "$template_file"
            printf '  Missing sections from template:\n'
            printf '%b' "$_missing"
            printf '\n  Action: Update %s to include guidance for these sections.\n' "references/$reference_file"
            printf '  See the "Template" subsection for the section table.\n\n'
        } >> "$_drift_report"
    fi
}

# --- Header ---
printf 'Checking template drift...\n'
printf 'Template directory:  %s\n' "$TEMPLATE_DIR"
printf 'Reference directory: %s\n' "$REFERENCE_DIR"
printf '\n'

# --- Process each template-reference pair ---
check_pair "analysis.md"        "doc-analysis.md"
check_pair "prd.md"             "doc-prd.md"
check_pair "architecture.md"    "doc-architecture.md"
check_pair "plan.md"            "doc-plan.md"
check_pair "quality-strategy.md" "doc-quality-strategy.md"
check_pair "security-review.md" "doc-security-review.md"

# --- Report results ---
if [ -s "$_drift_report" ]; then
    cat "$_drift_report"
    printf 'RESULT: Drift detected. Reference docs need updating.\n'
    exit 1
else
    printf 'RESULT: No drift detected. All template sections are documented in reference docs.\n'
    exit 0
fi
