#!/bin/zsh
#
# Validate prompt files for forbidden shell patterns
#
# Scans all .md files in prompts/create/ and prompts/review/ for patterns
# that could cause command injection or unintended shell expansion when
# prompts are passed to spawn-agent.sh.
#
# Forbidden patterns:
#   - $() command substitution
#   - ${...} shell variable expansion (dollar-sign curly braces)
#   - Backtick command substitution (single/double backticks around commands)
#     NOTE: Markdown code fences (``` on their own line) are NOT flagged
#
# Allowed patterns:
#   - {TICKET_ID}, {TICKET_PATH}, {PLUGIN_ROOT} placeholders (no dollar sign)
#   - Markdown code fences (triple backticks for code blocks)
#
# Usage:
#   validate-prompts.sh [PROMPTS_DIR]
#
# Arguments:
#   PROMPTS_DIR - Optional. Path to the prompts directory.
#                 Defaults to plugins/sdd/skills/document-authoring/prompts
#                 relative to the script's location.
#
# Exit codes:
#   0 - All prompts pass validation
#   1 - One or more violations found
#   2 - No prompt files found (configuration error)

set -euo pipefail

# --- Resolve prompts directory ---
if [ "$#" -ge 1 ]; then
    PROMPTS_DIR="$1"
else
    # Default: relative to the script's own location
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    PROMPTS_DIR="$SCRIPT_DIR/../prompts"
fi

# Normalize path
PROMPTS_DIR="$(cd "$PROMPTS_DIR" && pwd)"

# --- Verify directories exist ---
if [ ! -d "$PROMPTS_DIR/create" ]; then
    printf 'ERROR: Directory not found: %s/create\n' "$PROMPTS_DIR" >&2
    exit 2
fi

if [ ! -d "$PROMPTS_DIR/review" ]; then
    printf 'ERROR: Directory not found: %s/review\n' "$PROMPTS_DIR" >&2
    exit 2
fi

# --- Collect prompt files ---
file_count=0
violation_count=0
files_with_violations=0

# Allow globs to expand to nothing without error (zsh default is to fail)
setopt NULL_GLOB 2>/dev/null || true

for file in "$PROMPTS_DIR"/create/*.md "$PROMPTS_DIR"/review/*.md; do
    # Skip if glob did not match (safety for non-zsh shells)
    if [ ! -f "$file" ]; then
        continue
    fi
    file_count=$((file_count + 1))

    file_has_violation=0
    line_num=0

    while IFS= read -r line || [ -n "$line" ]; do
        line_num=$((line_num + 1))

        # --- Check 1: $() command substitution ---
        if printf '%s' "$line" | grep -qE '\$\('; then
            printf 'ERROR: Forbidden pattern in %s:%d\n' "$file" "$line_num"
            printf '  Pattern: $() command substitution\n'
            printf '  Line: "%s"\n\n' "$line"
            violation_count=$((violation_count + 1))
            file_has_violation=1
        fi

        # --- Check 2: ${...} shell variable expansion ---
        if printf '%s' "$line" | grep -qE '\$\{'; then
            printf 'ERROR: Forbidden pattern in %s:%d\n' "$file" "$line_num"
            printf '  Pattern: ${...} shell variable expansion\n'
            printf '  Line: "%s"\n\n' "$line"
            violation_count=$((violation_count + 1))
            file_has_violation=1
        fi

        # --- Check 3: Backtick command substitution ---
        # Skip lines that are markdown code fences (triple backticks, possibly
        # with a language tag like ```bash). These start with optional
        # whitespace followed by three or more backticks.
        is_code_fence=0
        if printf '%s' "$line" | grep -qE '^[[:space:]]*`{3,}'; then
            is_code_fence=1
        fi

        if [ "$is_code_fence" -eq 0 ]; then
            # Detect backtick-wrapped content: `...` where content is non-empty
            # This catches `command`, `echo foo`, etc.
            if printf '%s' "$line" | grep -qE '`[^`]+`'; then
                printf 'ERROR: Forbidden pattern in %s:%d\n' "$file" "$line_num"
                printf '  Pattern: backtick command substitution\n'
                printf '  Line: "%s"\n\n' "$line"
                violation_count=$((violation_count + 1))
                file_has_violation=1
            fi
        fi

    done < "$file"

    if [ "$file_has_violation" -ne 0 ]; then
        files_with_violations=$((files_with_violations + 1))
    fi
done

# --- Verify we found files ---
if [ "$file_count" -eq 0 ]; then
    printf 'ERROR: No .md files found in %s/create/ or %s/review/\n' "$PROMPTS_DIR" "$PROMPTS_DIR" >&2
    exit 2
fi

# --- Summary ---
if [ "$violation_count" -gt 0 ]; then
    printf 'FAILED: %d violation(s) in %d file(s) out of %d checked\n' \
        "$violation_count" "$files_with_violations" "$file_count"
    exit 1
else
    printf 'PASSED: All %d prompt files are clean\n' "$file_count"
    exit 0
fi
