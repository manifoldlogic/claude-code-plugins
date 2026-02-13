#!/usr/bin/env bash
#
# Triage Documents
# Evaluates a ticket description against the document registry trigger criteria
# and produces a JSON manifest indicating which documents to generate.
#
# Usage:
#   bash triage-documents.sh [--no-color] [--debug] [--verbose] "ticket description" [+override] [-override] ...
#
# Arguments:
#   --no-color          - Disable color output (also: NO_COLOR=1)
#   --debug             - Enable verbose command tracing (also: DEBUG=1)
#   --verbose           - Enable human-readable progress output (also: VERBOSE=1)
#   ticket description  - Text describing the ticket (required, first argument)
#   +doc-name           - Force-include a document (e.g., +accessibility)
#   -doc-name           - Force-exclude a document (e.g., -runbook)
#
# Output:
#   JSON manifest to stdout listing documents with action and reason.
#   Warnings and errors are printed to stderr.
#
# Exit Codes:
#   0 - Success
#   1 - Error (missing arguments, missing registry, invalid JSON)
#
# Examples:
#   bash triage-documents.sh "backend API caching layer"
#   bash triage-documents.sh "backend API caching layer" +accessibility -runbook
#   bash triage-documents.sh "add new npm package for auth" +dependency-audit

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY_FILE="$SCRIPT_DIR/../templates/document-registry.json"

# Parse flags before sourcing common.sh
for arg in "$@"; do
    case "$arg" in
        --no-color) USE_COLOR=false ;;
        --debug) SDD_DEBUG=true ;;
        --verbose) SDD_VERBOSE=true ;;
    esac
done

# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

# Check for required dependencies (after sourcing common.sh for check_jq_version)
check_jq_version || exit 1
verbose "Checking jq availability... OK"

# Sanitize user-provided description to prevent shell injection.
# Escapes shell metacharacters: backticks, $, (), {}, ;, <, >, |, &
# Preserves the original text content for keyword matching.
sanitize_description() {
    # WHY: Security - escape shell metacharacters in user-provided descriptions to prevent
    # injection when the description is later used in shell contexts (e.g., jq --arg).
    # Escapes: backticks, $, (), {}, ;, <, >, |, & by prepending a backslash.
    # Example: "deploy $(rm -rf /)" -> "deploy \$\(rm -rf /\)"
    # Single quotes are intentional to prevent shell expansion in sed pattern
    # shellcheck disable=SC2016
    printf '%s' "$1" | sed 's/[`$(){};<>|&]/\\&/g'
}

usage() {
    cat >&2 << 'EOF'
Usage: triage-documents.sh [--no-color] [--debug] [--verbose] "ticket description" [+override] [-override] ...

Arguments:
  --no-color          Disable color output (also: NO_COLOR=1)
  --debug             Enable verbose command tracing (also: DEBUG=1)
  --verbose           Enable human-readable progress output (also: VERBOSE=1)
  ticket description  Text describing the ticket (required, first argument)
  +doc-name           Force-include a document (e.g., +accessibility)
  -doc-name           Force-exclude a document (e.g., -runbook)

Examples:
  bash triage-documents.sh "backend API caching layer"
  bash triage-documents.sh "backend API caching layer" +accessibility -runbook
  bash triage-documents.sh --verbose "backend API caching layer"
EOF
    exit 1
}

# --- Input Validation ---

# Skip --no-color, --debug, and --verbose if they appear before the description (already handled above)
while [ "${1:-}" = "--no-color" ] || [ "${1:-}" = "--debug" ] || [ "${1:-}" = "--verbose" ]; do
    shift
done

if [ $# -lt 1 ] || [ -z "$1" ]; then
    error "Missing required argument: ticket description"
    usage
fi

description=$(sanitize_description "$1")
shift

# Validate description length (prevent jq OOM on very large inputs)
DESCRIPTION_MAX_LENGTH=10240  # 10KB
desc_length=${#description}
if [ "$desc_length" -gt "$DESCRIPTION_MAX_LENGTH" ]; then
    printf "[ERROR] Ticket description exceeds %d-byte limit (current: %d bytes).\n" "$DESCRIPTION_MAX_LENGTH" "$desc_length" >&2
    printf "\n" >&2
    printf "Please provide a concise description. Move detailed requirements to planning documents.\n" >&2
    exit 1
fi

verbose "Description validated (${desc_length} bytes)"

# --- Parse Overrides ---

overrides_plus=""
overrides_minus=""
overrides_json="[]"
seen_overrides=""

while [ $# -gt 0 ]; do
    arg="$1"
    # Skip --no-color, --debug, and --verbose (already handled before sourcing common.sh)
    if [ "$arg" = "--no-color" ] || [ "$arg" = "--debug" ] || [ "$arg" = "--verbose" ]; then
        shift
        continue
    fi
    # WHY: Override arguments use +name to force-include and -name to force-exclude documents.
    # Names must be lowercase kebab-case matching document registry IDs (e.g., "accessibility",
    # "dependency-audit"). The pattern requires starting with a letter to prevent ambiguity
    # with numeric arguments or flags.
    # Valid: +accessibility, +dependency-audit, -runbook, -security-review
    # Invalid: +Accessibility (uppercase), +123 (starts with digit), + (empty name)
    if printf '%s' "$arg" | grep -qE '^\+[a-z][a-z0-9-]*$'; then
        # Check for duplicate override
        case " $seen_overrides " in
            *" $arg "*)
                warn "Duplicate override '$arg' ignored"
                shift
                continue
                ;;
        esac
        seen_overrides="$seen_overrides $arg"
        doc_name="${arg#+}"
        overrides_plus="$overrides_plus $doc_name"
        overrides_json=$(printf '%s' "$overrides_json" | jq --arg o "$arg" '. + [$o]')
    # WHY: Same naming rules as +override above, but with "-" prefix to force-exclude a document.
    elif printf '%s' "$arg" | grep -qE '^-[a-z][a-z0-9-]*$'; then
        # Check for duplicate override
        case " $seen_overrides " in
            *" $arg "*)
                warn "Duplicate override '$arg' ignored"
                shift
                continue
                ;;
        esac
        seen_overrides="$seen_overrides $arg"
        doc_name="${arg#-}"
        overrides_minus="$overrides_minus $doc_name"
        overrides_json=$(printf '%s' "$overrides_json" | jq --arg o "$arg" '. + [$o]')
    else
        warn "Ignoring unrecognized argument: $arg"
    fi
    shift
done

# --- Validate Conflicting Overrides ---

for plus_doc in $overrides_plus; do
    case " $overrides_minus " in
        *" $plus_doc "*)
            error "Conflicting overrides for document '$plus_doc': both +$plus_doc and -$plus_doc specified"
            exit 1
            ;;
    esac
done

# --- Validate Registry ---

if [ ! -f "$REGISTRY_FILE" ]; then
    error "Document registry not found: $REGISTRY_FILE"
    exit 1
fi

# Validate that registry is valid JSON
if ! jq empty "$REGISTRY_FILE" 2>/dev/null; then
    error "Document registry is not valid JSON: $REGISTRY_FILE"
    exit 1
fi

# --- Validate Overrides Against Registry ---

all_doc_ids=$(jq -r '.documents | keys[]' "$REGISTRY_FILE")
doc_count=$(printf '%s\n' "$all_doc_ids" | wc -l | tr -d ' ')
verbose "Loaded document registry: ${doc_count} document types"

for doc_name in $overrides_plus; do
    if ! printf '%s\n' "$all_doc_ids" | grep -qx "$doc_name"; then
        warn "Override +$doc_name references non-existent document ID"
    fi
done

for doc_name in $overrides_minus; do
    if ! printf '%s\n' "$all_doc_ids" | grep -qx "$doc_name"; then
        warn "Override -$doc_name references non-existent document ID"
    fi
done

# --- Triage Each Document ---

documents_json="[]"

for doc_id in $all_doc_ids; do
    tier=$(jq -r ".documents[\"$doc_id\"].tier" "$REGISTRY_FILE")
    filename=$(jq -r ".documents[\"$doc_id\"].filename" "$REGISTRY_FILE")

    action=""
    reason=""

    # Determine action based on tier
    case "$tier" in
        core)
            action="generate"
            reason="Core document (always generated)"
            ;;
        standard)
            action="generate"
            reason="Standard document (generated by default)"
            ;;
        conditional)
            # Check trigger keywords against description
            matched_keywords=""
            # Use while-read to handle multi-word keywords (e.g., "backward compat")
            while IFS= read -r keyword; do
                [ -z "$keyword" ] && continue
                # Case-insensitive substring match
                if printf '%s' "$description" | grep -qiF "$keyword"; then
                    if [ -z "$matched_keywords" ]; then
                        matched_keywords="'$keyword'"
                    else
                        matched_keywords="$matched_keywords, '$keyword'"
                    fi
                fi
            done <<EOF
$(jq -r ".documents[\"$doc_id\"].triggers.keywords[]" "$REGISTRY_FILE" 2>/dev/null || true)
EOF

            if [ -n "$matched_keywords" ]; then
                action="generate"
                reason="Matched: $matched_keywords"
                verbose "Matched ${doc_id}: keywords ${matched_keywords}"
            else
                action="skip"
                reason="No trigger keywords matched"
            fi
            ;;
        *)
            action="skip"
            reason="Unknown tier: $tier"
            ;;
    esac

    # Apply overrides (after triage decision)
    # Check if this doc_id is in the plus overrides
    for plus_doc in $overrides_plus; do
        if [ "$plus_doc" = "$doc_id" ]; then
            action="generate"
            reason="Override: +$doc_id"
            verbose "Override: +${doc_id} (force include)"
            break
        fi
    done

    # Check if this doc_id is in the minus overrides
    for minus_doc in $overrides_minus; do
        if [ "$minus_doc" = "$doc_id" ]; then
            action="skip"
            reason="Override: -$doc_id"
            verbose "Override: -${doc_id} (force exclude)"
            break
        fi
    done

    # Add document entry to the JSON array
    documents_json=$(printf '%s' "$documents_json" | jq \
        --arg id "$doc_id" \
        --arg fn "$filename" \
        --arg act "$action" \
        --arg rsn "$reason" \
        '. + [{"id": $id, "filename": $fn, "action": $act, "reason": $rsn}]')
done

# --- Output JSON Manifest ---

generate_count=$(printf '%s' "$documents_json" | jq '[.[] | select(.action == "generate")] | length')
verbose "Generating manifest: ${generate_count} documents selected"

jq -n \
    --arg desc "$description" \
    --argjson overrides "$overrides_json" \
    --argjson documents "$documents_json" \
    '{
        "ticket_description": $desc,
        "overrides": $overrides,
        "documents": $documents
    }'
