#!/usr/bin/env bash
#
# Test Suite for triage-documents.sh
# Validates the document triage script against multiple test scenarios covering
# keyword matching, override handling, tier classification, and edge cases.
#
# Test Scenarios:
#   1. Backend API ticket - expects observability + api-contract conditional docs
#   2. UI redesign ticket - expects accessibility conditional doc
#   3. Database migration ticket - expects migration-plan conditional doc
#   4. Documentation-only ticket - expects only core + standard (no conditionals)
#   5. Override scenario - +accessibility forces include, -security-review forces exclude
#   6. Empty description - script exits non-zero
#   7. Case-insensitivity - "BACKEND API" matches same as lowercase
#   8. Partial keyword - "migrating database" matches migration-plan via "migrat"
#   9. JSON structure validation - manifest has required top-level fields
#  10. No duplicate documents - each document ID appears exactly once
#  11. Core documents always generated - analysis, architecture, plan always action=generate
#  12. Standard documents always generated - prd, quality-strategy, security-review always action=generate
#  17. Shell injection - command substitution $(whoami) with marker file
#  18. Shell injection - pipe operator
#  19. Shell injection - semicolon
#  20. Legitimate special characters preserved
#  21. Shell injection - backtick execution with marker file
#  22. Shell injection - redirect injection with marker file
#  23. Shell injection - combined injection vectors with marker file
#  24. jq dependency check - exits 1 with actionable error when jq not in PATH
#  25. Description length at limit (10240 bytes) - accepted
#  26. Description length over limit (11000 bytes) - rejected with exit 1
#  27. Registry schema validation - document-registry.json passes jq-based schema checks
#  28. Registry schema negative test - broken registry copy is caught by validation
#  29. Duplicate positive override warns - +accessibility +accessibility warns on stderr
#  30. Duplicate negative override warns - -observability -observability warns on stderr
#  31. Mixed duplicates both detected - +accessibility +accessibility -observability -observability
#  32. --no-color flag disables ANSI codes in stderr output
#  33. NO_COLOR env var disables ANSI codes in stderr output
#  34. --debug flag enables verbose tracing (set -x output on stderr)
#  35. DEBUG=1 env var enables verbose tracing (set -x output on stderr)
#  36. Stderr messages include [HH:MM:SS] timestamp prefix
#
# Usage:
#   bash test-triage-documents.sh
#
# Exit Codes:
#   0 - All tests passed
#   1 - One or more tests failed
#   2 - Setup validation failed (missing dependencies)

# Color variables in printf format strings are intentional; they contain ANSI escapes, not format specifiers
# shellcheck disable=SC2059

set -euo pipefail

# --- Configuration ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRIAGE_SCRIPT="$SCRIPT_DIR/triage-documents.sh"
REGISTRY_FILE="$SCRIPT_DIR/../templates/document-registry.json"

# --- Marker File Cleanup ---
# Shell injection tests use marker files to detect command execution.
# Clean up on exit to avoid leaving files behind even if tests fail.

cleanup_markers() {
    rm -f /tmp/smrting-test-marker-* 2>/dev/null
}
trap cleanup_markers EXIT

# Pre-clean any leftover marker files from prior runs
cleanup_markers

# --- Test Counters ---

PASS=0
FAIL=0
TOTAL=0

# --- Colors (if terminal supports) ---

if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    # YELLOW is defined for consistency with the color variable set; may be used in future tests
    # shellcheck disable=SC2034
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    GREEN=''
    RED=''
    # shellcheck disable=SC2034
    YELLOW=''
    CYAN=''
    NC=''
fi

# --- Helper Functions ---

log_pass() {
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
    printf "Test %d: %s ... ${GREEN}PASS${NC}\n" "$TOTAL" "$1"
}

log_fail() {
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
    printf "Test %d: %s ... ${RED}FAIL: %s${NC}\n" "$TOTAL" "$1" "$2"
}

# Run triage script and capture stdout (JSON output).
# Stderr is suppressed to avoid polluting test output.
# Arguments:
#   $@ - Arguments to pass to triage-documents.sh
# Sets global: TRIAGE_OUTPUT, TRIAGE_EXIT
run_triage() {
    set +e
    TRIAGE_OUTPUT=$(bash "$TRIAGE_SCRIPT" "$@" 2>/dev/null)
    TRIAGE_EXIT=$?
    set -e
}

# Run triage script and capture both stdout and stderr separately.
# Arguments:
#   $@ - Arguments to pass to triage-documents.sh
# Sets global: TRIAGE_OUTPUT, TRIAGE_STDERR, TRIAGE_EXIT
run_triage_with_stderr() {
    local stderr_file
    stderr_file=$(mktemp)
    set +e
    TRIAGE_OUTPUT=$(bash "$TRIAGE_SCRIPT" "$@" 2>"$stderr_file")
    TRIAGE_EXIT=$?
    set -e
    TRIAGE_STDERR=$(cat "$stderr_file")
    rm -f "$stderr_file"
}

# Get the action for a specific document ID from the triage output.
# Arguments:
#   $1 - document ID (e.g., "observability")
# Returns: the action string ("generate" or "skip")
get_action() {
    printf '%s' "$TRIAGE_OUTPUT" | jq -r --arg id "$1" \
        '.documents[] | select(.id == $id) | .action'
}

# Get the reason for a specific document ID from the triage output.
# Arguments:
#   $1 - document ID (e.g., "observability")
# Returns: the reason string
get_reason() {
    printf '%s' "$TRIAGE_OUTPUT" | jq -r --arg id "$1" \
        '.documents[] | select(.id == $id) | .reason'
}

# Assert that a document has the expected action.
# Arguments:
#   $1 - test description (for log messages)
#   $2 - document ID
#   $3 - expected action ("generate" or "skip")
assert_action() {
    local desc="$1"
    local doc_id="$2"
    local expected="$3"
    local actual
    actual=$(get_action "$doc_id")

    if [ "$actual" = "$expected" ]; then
        return 0
    else
        log_fail "$desc" "$doc_id action='$actual', expected='$expected'"
        return 1
    fi
}

# --- Setup Validation ---

printf -- "${CYAN}============================================${NC}\n"
printf -- "${CYAN}triage-documents.sh Test Suite${NC}\n"
printf -- "${CYAN}============================================${NC}\n\n"

printf "Setup validation...\n"

if [ ! -f "$TRIAGE_SCRIPT" ]; then
    printf "${RED}ERROR: triage-documents.sh not found at: %s${NC}\n" "$TRIAGE_SCRIPT"
    exit 2
fi

if [ ! -f "$REGISTRY_FILE" ]; then
    printf "${RED}ERROR: document-registry.json not found at: %s${NC}\n" "$REGISTRY_FILE"
    exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
    printf "${RED}ERROR: jq is required but not installed${NC}\n"
    exit 2
fi

printf "  triage-documents.sh found: %s\n" "$TRIAGE_SCRIPT"
printf "  document-registry.json found: %s\n" "$REGISTRY_FILE"
printf "  jq available: $(jq --version)\n"
printf "\n"

# =============================================
# Test 1: Backend API ticket
# Description: "backend API caching layer"
# Expect: observability=generate, api-contract=generate
# =============================================

printf -- "${CYAN}--- Keyword Matching Tests ---${NC}\n\n"

run_triage "backend API caching layer"

test_name="Backend API ticket: observability + api-contract triggered"
test_passed=true

if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "script exited $TRIAGE_EXIT, expected 0"
    test_passed=false
fi

if $test_passed; then
    obs_action=$(get_action "observability")
    api_action=$(get_action "api-contract")

    if [ "$obs_action" = "generate" ] && [ "$api_action" = "generate" ]; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "observability='$obs_action', api-contract='$api_action' (both should be 'generate')"
    fi
fi

# =============================================
# Test 2: UI redesign ticket
# Description: "user profile page redesign with new form components"
# Expect: accessibility=generate (keywords: "page", "form", "component")
# =============================================

run_triage "user profile page redesign with new form components"

test_name="UI redesign ticket: accessibility triggered"
if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "script exited $TRIAGE_EXIT, expected 0"
else
    acc_action=$(get_action "accessibility")
    if [ "$acc_action" = "generate" ]; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "accessibility='$acc_action', expected 'generate'"
    fi
fi

# =============================================
# Test 3: Database migration ticket
# Description: "migrate user schema to support multi-tenant"
# Expect: migration-plan=generate (keywords: "migrat", "schema")
# =============================================

run_triage "migrate user schema to support multi-tenant"

test_name="Database migration ticket: migration-plan triggered"
if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "script exited $TRIAGE_EXIT, expected 0"
else
    mig_action=$(get_action "migration-plan")
    if [ "$mig_action" = "generate" ]; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "migration-plan='$mig_action', expected 'generate'"
    fi
fi

# =============================================
# Test 4: Documentation-only ticket
# Description: "update README and API documentation"
# Expect: core docs=generate, standard docs=generate
#         conditional docs that don't match keywords=skip
#         (Note: "api" keyword may trigger api-contract and observability)
# =============================================

run_triage "update README and API documentation"

test_name="Documentation-only ticket: core + standard always generated"
if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "script exited $TRIAGE_EXIT, expected 0"
else
    all_ok=true
    for core_doc in analysis architecture plan; do
        action=$(get_action "$core_doc")
        if [ "$action" != "generate" ]; then
            log_fail "$test_name" "core doc '$core_doc' action='$action', expected 'generate'"
            all_ok=false
            break
        fi
    done

    if $all_ok; then
        for std_doc in prd quality-strategy security-review; do
            action=$(get_action "$std_doc")
            if [ "$action" != "generate" ]; then
                log_fail "$test_name" "standard doc '$std_doc' action='$action', expected 'generate'"
                all_ok=false
                break
            fi
        done
    fi

    if $all_ok; then
        # Conditional docs that should NOT match: migration-plan, dependency-audit
        # (accessibility may match "page", runbook may match "deploy", etc. depending on description)
        mig_action=$(get_action "migration-plan")
        dep_action=$(get_action "dependency-audit")
        if [ "$mig_action" = "skip" ] && [ "$dep_action" = "skip" ]; then
            log_pass "$test_name"
        else
            log_fail "$test_name" "migration-plan='$mig_action', dependency-audit='$dep_action' (both should be 'skip')"
        fi
    fi
fi

# =============================================
# Test 5: Override scenario
# Description: "backend API" with +accessibility -security-review
# Expect: accessibility=generate (forced), security-review=skip (forced)
# =============================================

printf -- "\n${CYAN}--- Override Tests ---${NC}\n\n"

run_triage "backend API" "+accessibility" "-security-review"

test_name="Override: +accessibility forces generate, -security-review forces skip"
if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "script exited $TRIAGE_EXIT, expected 0"
else
    acc_action=$(get_action "accessibility")
    acc_reason=$(get_reason "accessibility")
    sec_action=$(get_action "security-review")
    sec_reason=$(get_reason "security-review")

    if [ "$acc_action" = "generate" ] && [ "$sec_action" = "skip" ]; then
        # Also validate reason contains "Override"
        if printf '%s' "$acc_reason" | grep -qi "override" && printf '%s' "$sec_reason" | grep -qi "override"; then
            log_pass "$test_name"
        else
            log_fail "$test_name" "actions correct but reason missing 'Override' (acc='$acc_reason', sec='$sec_reason')"
        fi
    else
        log_fail "$test_name" "accessibility='$acc_action', security-review='$sec_action'"
    fi
fi

# =============================================
# Test 6: Empty description
# Expect: script exits non-zero (error)
# =============================================

printf -- "\n${CYAN}--- Edge Case Tests ---${NC}\n\n"

set +e
bash "$TRIAGE_SCRIPT" "" >/dev/null 2>&1
empty_exit=$?
set -e

test_name="Empty description: exits non-zero"
if [ "$empty_exit" -ne 0 ]; then
    log_pass "$test_name"
else
    log_fail "$test_name" "exit code was 0, expected non-zero"
fi

# =============================================
# Test 7: Case-insensitivity
# Description: "BACKEND API" (uppercase)
# Expect: same results as lowercase "backend API"
#         observability=generate, api-contract=generate
# =============================================

run_triage "BACKEND API"

test_name="Case-insensitivity: 'BACKEND API' matches same as lowercase"
if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "script exited $TRIAGE_EXIT, expected 0"
else
    obs_action=$(get_action "observability")
    api_action=$(get_action "api-contract")

    if [ "$obs_action" = "generate" ] && [ "$api_action" = "generate" ]; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "observability='$obs_action', api-contract='$api_action' (both should be 'generate')"
    fi
fi

# =============================================
# Test 8: Partial keyword matching
# Description: "migrating database" (contains "migrat" prefix)
# Expect: migration-plan=generate
# =============================================

run_triage "migrating database"

test_name="Partial keyword: 'migrating database' triggers migration-plan via 'migrat'"
if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "script exited $TRIAGE_EXIT, expected 0"
else
    mig_action=$(get_action "migration-plan")
    if [ "$mig_action" = "generate" ]; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "migration-plan='$mig_action', expected 'generate'"
    fi
fi

# =============================================
# Test 9: JSON structure validation
# Verify manifest has required top-level fields:
#   ticket_description, overrides, documents
# =============================================

printf -- "\n${CYAN}--- Structure Validation Tests ---${NC}\n\n"

run_triage "test ticket for structure validation"

test_name="JSON structure: manifest has required top-level fields"
if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "script exited $TRIAGE_EXIT, expected 0"
else
    # Validate JSON is parseable
    if ! printf '%s' "$TRIAGE_OUTPUT" | jq empty 2>/dev/null; then
        log_fail "$test_name" "output is not valid JSON"
    else
        has_desc=$(printf '%s' "$TRIAGE_OUTPUT" | jq 'has("ticket_description")')
        has_overrides=$(printf '%s' "$TRIAGE_OUTPUT" | jq 'has("overrides")')
        has_docs=$(printf '%s' "$TRIAGE_OUTPUT" | jq 'has("documents")')

        if [ "$has_desc" = "true" ] && [ "$has_overrides" = "true" ] && [ "$has_docs" = "true" ]; then
            log_pass "$test_name"
        else
            log_fail "$test_name" "ticket_description=$has_desc, overrides=$has_overrides, documents=$has_docs"
        fi
    fi
fi

# =============================================
# Test 10: No duplicate documents
# Each document ID should appear exactly once in the output
# =============================================

run_triage "backend API with database migration"

test_name="No duplicate documents: each ID appears exactly once"
if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "script exited $TRIAGE_EXIT, expected 0"
else
    total_ids=$(printf '%s' "$TRIAGE_OUTPUT" | jq '.documents | length')
    unique_ids=$(printf '%s' "$TRIAGE_OUTPUT" | jq '[.documents[].id] | unique | length')

    if [ "$total_ids" = "$unique_ids" ]; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "total=$total_ids, unique=$unique_ids (duplicates found)"
    fi
fi

# =============================================
# Test 11: Core documents always generated
# Core: analysis, architecture, plan - should always be action=generate
# regardless of description content
# =============================================

run_triage "simple task with no special keywords"

test_name="Core documents always generated: analysis, architecture, plan"
if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "script exited $TRIAGE_EXIT, expected 0"
else
    all_core_ok=true
    for doc in analysis architecture plan; do
        action=$(get_action "$doc")
        if [ "$action" != "generate" ]; then
            log_fail "$test_name" "core doc '$doc' action='$action', expected 'generate'"
            all_core_ok=false
            break
        fi
    done
    if $all_core_ok; then
        log_pass "$test_name"
    fi
fi

# =============================================
# Test 12: Standard documents always generated
# Standard: prd, quality-strategy, security-review - should always be action=generate
# =============================================

test_name="Standard documents always generated: prd, quality-strategy, security-review"
# Reuse output from test 11 (same run)
all_std_ok=true
for doc in prd quality-strategy security-review; do
    action=$(get_action "$doc")
    if [ "$action" != "generate" ]; then
        log_fail "$test_name" "standard doc '$doc' action='$action', expected 'generate'"
        all_std_ok=false
        break
    fi
done
if $all_std_ok; then
    log_pass "$test_name"
fi

# =============================================
# Test 13: Document entry has required fields
# Each document in the array should have: id, filename, action, reason
# =============================================

run_triage "field validation test"

test_name="Document entries have required fields: id, filename, action, reason"
if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "script exited $TRIAGE_EXIT, expected 0"
else
    # Check that every document has all four required fields
    missing=$(printf '%s' "$TRIAGE_OUTPUT" | jq '[.documents[] | select((.id == null) or (.filename == null) or (.action == null) or (.reason == null))] | length')
    if [ "$missing" = "0" ]; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "$missing document(s) missing required fields"
    fi
fi

# =============================================
# Test 14: Reason field accuracy for conditional match
# When a keyword matches, reason should contain the matched keyword
# =============================================

run_triage "deploy new infrastructure service"

test_name="Reason field contains matched keyword for conditional documents"
if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "script exited $TRIAGE_EXIT, expected 0"
else
    obs_reason=$(get_reason "observability")
    obs_action=$(get_action "observability")
    # observability should match on "deploy", "infrastructure", "service"
    if [ "$obs_action" = "generate" ]; then
        # Reason should contain "Matched:" with at least one keyword
        if printf '%s' "$obs_reason" | grep -q "Matched:"; then
            log_pass "$test_name"
        else
            log_fail "$test_name" "observability reason='$obs_reason', expected to contain 'Matched:'"
        fi
    else
        log_fail "$test_name" "observability should be 'generate' for 'deploy new infrastructure service'"
    fi
fi

# =============================================
# Test 15: Reason field for skipped conditional
# When no keywords match, reason should indicate no match
# =============================================

run_triage "simple task with no special keywords"

test_name="Reason field for skipped conditional says 'No trigger keywords matched'"
if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "script exited $TRIAGE_EXIT, expected 0"
else
    obs_action=$(get_action "observability")
    obs_reason=$(get_reason "observability")
    if [ "$obs_action" = "skip" ] && [ "$obs_reason" = "No trigger keywords matched" ]; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "observability action='$obs_action', reason='$obs_reason'"
    fi
fi

# =============================================
# Test 16: Overrides reflected in manifest
# The overrides array in the JSON should list the override flags provided
# =============================================

run_triage "test overrides array" "+runbook" "-dependency-audit"

test_name="Overrides array in manifest reflects input flags"
if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "script exited $TRIAGE_EXIT, expected 0"
else
    has_plus=$(printf '%s' "$TRIAGE_OUTPUT" | jq '.overrides | index("+runbook") != null')
    has_minus=$(printf '%s' "$TRIAGE_OUTPUT" | jq '.overrides | index("-dependency-audit") != null')
    if [ "$has_plus" = "true" ] && [ "$has_minus" = "true" ]; then
        log_pass "$test_name"
    else
        overrides_val=$(printf '%s' "$TRIAGE_OUTPUT" | jq -c '.overrides')
        log_fail "$test_name" "overrides=$overrides_val, expected ['+runbook', '-dependency-audit']"
    fi
fi

# =============================================
# Test 17: Shell injection - command substitution
# Description contains $(whoami) - should be sanitized, not executed
# Also uses a marker file to prove the command was not executed
# =============================================

printf -- "\n${CYAN}--- Shell Injection Tests ---${NC}\n\n"

# Single quotes are intentional; testing that shell injection payloads are NOT expanded
# shellcheck disable=SC2016
run_triage 'test$(touch /tmp/smrting-test-marker-17)$(whoami)'

test_name="Shell injection: command substitution \$(whoami) is treated as literal"
if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "script exited $TRIAGE_EXIT, expected 0"
else
    test_ok=true
    # Check 1: The description in the JSON output should NOT contain the current username
    # from executing whoami - it should contain the escaped/literal form
    actual_user=$(whoami)
    desc_in_output=$(printf '%s' "$TRIAGE_OUTPUT" | jq -r '.ticket_description')
    if printf '%s' "$desc_in_output" | grep -qF "$actual_user"; then
        log_fail "$test_name" "command substitution was executed (found '$actual_user' in output)"
        test_ok=false
    fi
    # Check 2: Marker file should NOT exist - proves touch was not executed
    if [ -f /tmp/smrting-test-marker-17 ]; then
        log_fail "$test_name" "marker file /tmp/smrting-test-marker-17 was created (command executed!)"
        test_ok=false
    fi
    if $test_ok; then
        log_pass "$test_name"
    fi
fi

# =============================================
# Test 18: Shell injection - pipe
# Description: "test | echo injected" - pipe should not execute
# =============================================

run_triage 'test | echo injected'

test_name="Shell injection: pipe operator is sanitized"
if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "script exited $TRIAGE_EXIT, expected 0"
else
    # Verify the script produced valid JSON (did not break from pipe)
    if printf '%s' "$TRIAGE_OUTPUT" | jq empty 2>/dev/null; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "output is not valid JSON (pipe may have broken execution)"
    fi
fi

# =============================================
# Test 19: Shell injection - semicolon
# Description: "test; echo injected" - semicolon should not execute
# =============================================

run_triage 'test; echo injected'

test_name="Shell injection: semicolon is sanitized"
if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "script exited $TRIAGE_EXIT, expected 0"
else
    # Verify the script produced valid JSON (did not break from semicolon)
    if printf '%s' "$TRIAGE_OUTPUT" | jq empty 2>/dev/null; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "output is not valid JSON (semicolon may have broken execution)"
    fi
fi

# =============================================
# Test 20: Legitimate special characters preserved
# Description: "API (v2) deployment & testing"
# Should still match keywords: "api", "deploy"
# =============================================

run_triage 'API (v2) deployment & testing'

test_name="Legitimate special chars: 'API (v2) deployment & testing' still matches keywords"
if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "script exited $TRIAGE_EXIT, expected 0"
else
    api_action=$(get_action "api-contract")
    obs_action=$(get_action "observability")
    if [ "$api_action" = "generate" ] && [ "$obs_action" = "generate" ]; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "api-contract='$api_action', observability='$obs_action' (both should be 'generate')"
    fi
fi

# =============================================
# Test 21: Shell injection - backtick execution
# Description: "test `touch /tmp/smrting-test-marker-21`"
# Backticks should be sanitized, marker file must NOT be created
# =============================================

# Single quotes are intentional; testing that backtick injection is NOT expanded
# shellcheck disable=SC2016
run_triage 'test `touch /tmp/smrting-test-marker-21`'

test_name="Shell injection: backtick execution is sanitized"
if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "script exited $TRIAGE_EXIT, expected 0"
else
    test_ok=true
    # Verify valid JSON output
    if ! printf '%s' "$TRIAGE_OUTPUT" | jq empty 2>/dev/null; then
        log_fail "$test_name" "output is not valid JSON (backtick may have broken execution)"
        test_ok=false
    fi
    # Verify marker file was NOT created (proves backtick command was not executed)
    if [ -f /tmp/smrting-test-marker-21 ]; then
        log_fail "$test_name" "marker file /tmp/smrting-test-marker-21 was created (backtick command executed!)"
        test_ok=false
    fi
    if $test_ok; then
        log_pass "$test_name"
    fi
fi

# =============================================
# Test 22: Shell injection - redirect injection
# Description: "test > /tmp/smrting-test-marker-22"
# Redirect operator should be sanitized, file must NOT be created
# =============================================

run_triage 'test > /tmp/smrting-test-marker-22'

test_name="Shell injection: redirect operator is sanitized"
if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "script exited $TRIAGE_EXIT, expected 0"
else
    test_ok=true
    # Verify valid JSON output
    if ! printf '%s' "$TRIAGE_OUTPUT" | jq empty 2>/dev/null; then
        log_fail "$test_name" "output is not valid JSON (redirect may have broken execution)"
        test_ok=false
    fi
    # Verify marker file was NOT created (proves redirect was not executed)
    if [ -f /tmp/smrting-test-marker-22 ]; then
        log_fail "$test_name" "marker file /tmp/smrting-test-marker-22 was created (redirect was executed!)"
        test_ok=false
    fi
    if $test_ok; then
        log_pass "$test_name"
    fi
fi

# =============================================
# Test 23: Shell injection - combined injection with marker file
# Description contains multiple injection vectors with a marker file
# $(touch /tmp/smrting-test-marker-23); `id` | cat
# =============================================

# Single quotes are intentional; testing that combined injection vectors are NOT expanded
# shellcheck disable=SC2016
run_triage 'deploy $(touch /tmp/smrting-test-marker-23); `id` | cat'

test_name="Shell injection: combined vectors with marker file detection"
if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "script exited $TRIAGE_EXIT, expected 0"
else
    test_ok=true
    # Verify valid JSON output
    if ! printf '%s' "$TRIAGE_OUTPUT" | jq empty 2>/dev/null; then
        log_fail "$test_name" "output is not valid JSON (combined injection broke execution)"
        test_ok=false
    fi
    # Verify marker file was NOT created
    if [ -f /tmp/smrting-test-marker-23 ]; then
        log_fail "$test_name" "marker file /tmp/smrting-test-marker-23 was created (command executed!)"
        test_ok=false
    fi
    # Verify keyword matching still works - "deploy" should trigger observability
    if $test_ok; then
        obs_action=$(get_action "observability")
        if [ "$obs_action" = "generate" ]; then
            log_pass "$test_name"
        else
            log_fail "$test_name" "keyword matching broken: observability='$obs_action', expected 'generate' for 'deploy'"
        fi
    fi
fi

# =============================================
# Test 24: jq dependency check
# Run triage-documents.sh with jq removed from PATH
# Expect: exit code 1, error message contains "jq is required"
# =============================================

printf -- "\n${CYAN}--- Dependency Check Tests ---${NC}\n\n"

test_name="jq dependency check: exits 1 with actionable error when jq missing"

# Create a temporary bin directory with symlinks to all essential commands EXCEPT jq.
# This is more reliable than removing directories from PATH, because jq may share
# directories with bash, printf, grep, sed, and other tools the script needs.
NO_JQ_BIN=$(mktemp -d)
for cmd in bash printf grep sed cat cd dirname pwd mkdir wc find head sort ls rm cp; do
    cmd_path=$(command -v "$cmd" 2>/dev/null || true)
    if [ -n "$cmd_path" ] && [ -x "$cmd_path" ]; then
        ln -sf "$cmd_path" "$NO_JQ_BIN/$cmd"
    fi
done
# Explicitly do NOT link jq

set +e
# JQ_CHECK_OUTPUT captures stderr where the error message is printed
# shellcheck disable=SC2034
JQ_CHECK_OUTPUT=$(PATH="$NO_JQ_BIN" bash "$TRIAGE_SCRIPT" "test description" 2>&1)
JQ_CHECK_EXIT=$?
set -e

# Clean up temporary bin directory
rm -rf "$NO_JQ_BIN"

test_ok=true
if [ "$JQ_CHECK_EXIT" -ne 1 ]; then
    log_fail "$test_name" "exit code was $JQ_CHECK_EXIT, expected 1"
    test_ok=false
fi
if $test_ok; then
    if printf '%s' "$JQ_CHECK_OUTPUT" | grep -q "jq is required"; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "error message does not contain 'jq is required'"
    fi
fi

# =============================================
# Test 25: Description length at limit (10240 bytes)
# A description of exactly 10240 bytes should be accepted
# =============================================

printf -- "\n${CYAN}--- Description Length Limit Tests ---${NC}\n\n"

# Generate a description of exactly 10240 bytes
desc_at_limit=$(dd if=/dev/zero bs=1 count=10240 2>/dev/null | tr '\0' 'a')

run_triage "$desc_at_limit"

test_name="Description length at limit (10240 bytes): accepted"
if [ "$TRIAGE_EXIT" -eq 0 ]; then
    log_pass "$test_name"
else
    log_fail "$test_name" "exit code was $TRIAGE_EXIT, expected 0"
fi

# =============================================
# Test 26: Description length over limit (11000 bytes)
# A description of 11000 bytes should be rejected with exit 1
# and error message containing "exceeds"
# =============================================

# Generate a description of 11000 bytes
desc_over_limit=$(dd if=/dev/zero bs=1 count=11000 2>/dev/null | tr '\0' 'a')

set +e
OVERLIMIT_OUTPUT=$(bash "$TRIAGE_SCRIPT" "$desc_over_limit" 2>&1)
OVERLIMIT_EXIT=$?
set -e

test_name="Description length over limit (11000 bytes): rejected with exit 1"
test_ok=true
if [ "$OVERLIMIT_EXIT" -ne 1 ]; then
    log_fail "$test_name" "exit code was $OVERLIMIT_EXIT, expected 1"
    test_ok=false
fi
if $test_ok; then
    if printf '%s' "$OVERLIMIT_OUTPUT" | grep -q "exceeds"; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "error message does not contain 'exceeds'"
    fi
fi

# =============================================
# Test 27: Registry schema validation (jq-based)
# Validate document-registry.json structure:
#   - All documents have required fields (filename, title, tier, template, create_tasks_validation)
#   - All tier values are one of: core, standard, conditional
#   - All filenames match pattern ^[a-z][a-z0-9-]*\.md$
#   - All trigger objects (when present) have keywords array and description string
# =============================================

printf -- "\n${CYAN}--- Registry Schema Validation Tests ---${NC}\n\n"

SCHEMA_REGISTRY="$SCRIPT_DIR/../templates/document-registry.json"

test_name="Registry schema validation: document-registry.json passes jq-based checks"
schema_ok=true

# Check 1: All documents have required fields
missing_fields=$(jq -r '
  .documents | to_entries[] |
  select(
    (.value.filename == null) or
    (.value.title == null) or
    (.value.tier == null) or
    (.value.template == null) or
    (.value.create_tasks_validation == null)
  ) | .key
' "$SCHEMA_REGISTRY")

if [ -n "$missing_fields" ]; then
    log_fail "$test_name" "documents missing required fields: $missing_fields"
    schema_ok=false
fi

# Check 2: All tier values are valid enum
if $schema_ok; then
    invalid_tiers=$(jq -r '
      .documents | to_entries[] |
      select(.value.tier != "core" and .value.tier != "standard" and .value.tier != "conditional") |
      "\(.key)=\(.value.tier)"
    ' "$SCHEMA_REGISTRY")

    if [ -n "$invalid_tiers" ]; then
        log_fail "$test_name" "invalid tier values: $invalid_tiers"
        schema_ok=false
    fi
fi

# Check 3: All filenames match pattern ^[a-z][a-z0-9-]*\.md$
if $schema_ok; then
    invalid_filenames=$(jq -r '
      .documents | to_entries[] |
      select(.value.filename | test("^[a-z][a-z0-9-]*\\.md$") | not) |
      "\(.key)=\(.value.filename)"
    ' "$SCHEMA_REGISTRY")

    if [ -n "$invalid_filenames" ]; then
        log_fail "$test_name" "invalid filenames: $invalid_filenames"
        schema_ok=false
    fi
fi

# Check 4: All trigger objects have keywords (array) and description (string)
if $schema_ok; then
    invalid_triggers=$(jq -r '
      .documents | to_entries[] |
      select(.value.triggers != null) |
      select(
        (.value.triggers.keywords | type) != "array" or
        (.value.triggers.description | type) != "string"
      ) |
      .key
    ' "$SCHEMA_REGISTRY")

    if [ -n "$invalid_triggers" ]; then
        log_fail "$test_name" "documents with invalid triggers structure: $invalid_triggers"
        schema_ok=false
    fi
fi

# Check 5: Root-level required fields exist
if $schema_ok; then
    has_version=$(jq 'has("version")' "$SCHEMA_REGISTRY")
    has_tiers=$(jq 'has("tiers")' "$SCHEMA_REGISTRY")
    has_documents=$(jq 'has("documents")' "$SCHEMA_REGISTRY")

    if [ "$has_version" != "true" ] || [ "$has_tiers" != "true" ] || [ "$has_documents" != "true" ]; then
        log_fail "$test_name" "missing root fields: version=$has_version, tiers=$has_tiers, documents=$has_documents"
        schema_ok=false
    fi
fi

if $schema_ok; then
    log_pass "$test_name"
fi

# =============================================
# Test 28: Registry schema negative test
# Create a broken registry copy (missing tier field, invalid filename)
# and verify jq-based validation catches the errors
# =============================================

test_name="Registry schema negative test: broken registry caught by validation"
BROKEN_REGISTRY=$(mktemp)

# Create a broken registry: remove "tier" from first document, set invalid filename on second
jq '
  .documents.analysis |= del(.tier) |
  .documents.architecture.filename = "INVALID_NAME"
' "$SCHEMA_REGISTRY" > "$BROKEN_REGISTRY"

negative_ok=true

# Negative check 1: Should detect missing tier field
missing_tier=$(jq -r '
  .documents | to_entries[] |
  select(.value.tier == null) |
  .key
' "$BROKEN_REGISTRY")

if [ -z "$missing_tier" ]; then
    log_fail "$test_name" "validation did not catch missing tier field"
    negative_ok=false
fi

# Negative check 2: Should detect invalid filename
if $negative_ok; then
    invalid_fn=$(jq -r '
      .documents | to_entries[] |
      select(.value.filename != null) |
      select(.value.filename | test("^[a-z][a-z0-9-]*\\.md$") | not) |
      "\(.key)=\(.value.filename)"
    ' "$BROKEN_REGISTRY")

    if [ -z "$invalid_fn" ]; then
        log_fail "$test_name" "validation did not catch invalid filename"
        negative_ok=false
    fi
fi

# Clean up temporary file
rm -f "$BROKEN_REGISTRY"

if $negative_ok; then
    log_pass "$test_name"
fi

# =============================================
# Test 29: Duplicate positive override warns
# Running with +accessibility +accessibility should:
#   - Print warning to stderr about duplicate
#   - Produce same manifest as single +accessibility
# =============================================

printf -- "\n${CYAN}--- Duplicate Override Tests ---${NC}\n\n"

run_triage_with_stderr "simple task" "+accessibility" "+accessibility"

test_name="Duplicate positive override: warns on stderr"
test_ok=true

if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "script exited $TRIAGE_EXIT, expected 0"
    test_ok=false
fi

if $test_ok; then
    # Check stderr contains duplicate warning
    if printf '%s' "$TRIAGE_STDERR" | grep -qF "Duplicate override '+accessibility' ignored"; then
        # Verify manifest matches single-override version
        run_triage "simple task" "+accessibility"
        single_manifest=$(printf '%s' "$TRIAGE_OUTPUT" | jq -c '.documents')
        run_triage_with_stderr "simple task" "+accessibility" "+accessibility"
        dup_manifest=$(printf '%s' "$TRIAGE_OUTPUT" | jq -c '.documents')
        if [ "$single_manifest" = "$dup_manifest" ]; then
            log_pass "$test_name"
        else
            log_fail "$test_name" "manifest differs between single and duplicate override"
        fi
    else
        log_fail "$test_name" "stderr missing duplicate warning (got: $TRIAGE_STDERR)"
    fi
fi

# =============================================
# Test 30: Duplicate negative override warns
# Running with -observability -observability should:
#   - Print warning to stderr about duplicate
# =============================================

run_triage_with_stderr "backend API caching layer" "-observability" "-observability"

test_name="Duplicate negative override: warns on stderr"
test_ok=true

if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "script exited $TRIAGE_EXIT, expected 0"
    test_ok=false
fi

if $test_ok; then
    if printf '%s' "$TRIAGE_STDERR" | grep -qF "Duplicate override '-observability' ignored"; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "stderr missing duplicate warning (got: $TRIAGE_STDERR)"
    fi
fi

# =============================================
# Test 31: Mixed duplicates both detected
# Running with +accessibility +accessibility -observability -observability should:
#   - Print both duplicate warnings to stderr
# =============================================

run_triage_with_stderr "simple task" "+accessibility" "+accessibility" "-observability" "-observability"

test_name="Mixed duplicates: both duplicate warnings present"
test_ok=true

if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "script exited $TRIAGE_EXIT, expected 0"
    test_ok=false
fi

if $test_ok; then
    has_plus_dup=$(printf '%s' "$TRIAGE_STDERR" | grep -cF "Duplicate override '+accessibility' ignored" || true)
    has_minus_dup=$(printf '%s' "$TRIAGE_STDERR" | grep -cF "Duplicate override '-observability' ignored" || true)
    if [ "$has_plus_dup" -ge 1 ] && [ "$has_minus_dup" -ge 1 ]; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "expected both warnings (plus_dup=$has_plus_dup, minus_dup=$has_minus_dup, stderr: $TRIAGE_STDERR)"
    fi
fi

# =============================================
# Test 32: --no-color flag disables ANSI codes
# Run triage-documents.sh with --no-color and invalid args to force error output
# Verify no ANSI escape codes (\033 or \x1b) in stderr output
# =============================================

printf -- "\n${CYAN}--- Color Control Tests ---${NC}\n\n"

# Use --no-color with empty description to force error output on stderr
set +e
NO_COLOR_OUTPUT=$(bash "$TRIAGE_SCRIPT" --no-color "" 2>&1)
NO_COLOR_EXIT=$?
set -e

test_name="--no-color flag disables ANSI codes in stderr output"
# Check for ANSI escape sequences (ESC character = octal 033)
if printf '%s' "$NO_COLOR_OUTPUT" | grep -qP '\x1b\[' 2>/dev/null || printf '%s' "$NO_COLOR_OUTPUT" | grep -q "$(printf '\033')" 2>/dev/null; then
    log_fail "$test_name" "ANSI escape codes found in output with --no-color"
else
    # Verify the script actually produced output (not a false pass from empty output)
    if [ -n "$NO_COLOR_OUTPUT" ]; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "no output produced (cannot verify color was disabled)"
    fi
fi

# =============================================
# Test 33: NO_COLOR env var disables ANSI codes
# Run triage-documents.sh with NO_COLOR=1 env var and invalid args
# Verify no ANSI escape codes in stderr output
# =============================================

set +e
NO_COLOR_ENV_OUTPUT=$(NO_COLOR=1 bash "$TRIAGE_SCRIPT" "" 2>&1)
NO_COLOR_ENV_EXIT=$?
set -e

test_name="NO_COLOR env var disables ANSI codes in stderr output"
# Check for ANSI escape sequences
if printf '%s' "$NO_COLOR_ENV_OUTPUT" | grep -qP '\x1b\[' 2>/dev/null || printf '%s' "$NO_COLOR_ENV_OUTPUT" | grep -q "$(printf '\033')" 2>/dev/null; then
    log_fail "$test_name" "ANSI escape codes found in output with NO_COLOR=1"
else
    # Verify the script actually produced output
    if [ -n "$NO_COLOR_ENV_OUTPUT" ]; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "no output produced (cannot verify color was disabled)"
    fi
fi

# =============================================
# Test 34: --debug flag enables verbose tracing
# Run triage with --debug and a valid description
# Capture stderr; verify it contains "+ " prefixed lines (set -x output)
# =============================================

printf -- "\n${CYAN}--- Debug Flag Tests ---${NC}\n\n"

run_triage_with_stderr "--debug" "backend API caching layer"

test_name="--debug flag enables verbose tracing (set -x output on stderr)"
test_ok=true

if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "script exited $TRIAGE_EXIT, expected 0"
    test_ok=false
fi

if $test_ok; then
    # set -x output produces lines starting with "+ " on stderr
    if printf '%s' "$TRIAGE_STDERR" | grep -q '^+ '; then
        # Also verify stdout JSON is still clean (no set -x pollution)
        if printf '%s' "$TRIAGE_OUTPUT" | jq empty 2>/dev/null; then
            log_pass "$test_name"
        else
            log_fail "$test_name" "stdout JSON is invalid (debug output leaked to stdout)"
        fi
    else
        log_fail "$test_name" "stderr does not contain set -x trace lines (expected '+ ' prefix)"
    fi
fi

# =============================================
# Test 35: DEBUG=1 env var enables verbose tracing
# Run DEBUG=1 triage-documents.sh with valid description
# Capture stderr; verify it contains "+ " prefixed lines
# =============================================

stderr_file_35=$(mktemp)
set +e
DEBUG_ENV_OUTPUT=$(DEBUG=1 bash "$TRIAGE_SCRIPT" "backend API caching layer" 2>"$stderr_file_35")
DEBUG_ENV_EXIT=$?
set -e
DEBUG_ENV_STDERR=$(cat "$stderr_file_35")
rm -f "$stderr_file_35"

test_name="DEBUG=1 env var enables verbose tracing (set -x output on stderr)"
test_ok=true

if [ "$DEBUG_ENV_EXIT" -ne 0 ]; then
    log_fail "$test_name" "script exited $DEBUG_ENV_EXIT, expected 0"
    test_ok=false
fi

if $test_ok; then
    # set -x output produces lines starting with "+ " on stderr
    if printf '%s' "$DEBUG_ENV_STDERR" | grep -q '^+ '; then
        # Also verify stdout JSON is still clean
        if printf '%s' "$DEBUG_ENV_OUTPUT" | jq empty 2>/dev/null; then
            log_pass "$test_name"
        else
            log_fail "$test_name" "stdout JSON is invalid (debug output leaked to stdout)"
        fi
    else
        log_fail "$test_name" "stderr does not contain set -x trace lines (expected '+ ' prefix)"
    fi
fi

# =============================================
# Test 36: Timestamp format in stderr output
# Run triage with empty description (forces error on stderr)
# Capture stderr; verify it contains [HH:MM:SS] timestamp pattern
# =============================================

printf -- "\n${CYAN}--- Timestamp Tests ---${NC}\n\n"

stderr_file_36=$(mktemp)
set +e
bash "$TRIAGE_SCRIPT" "" 2>"$stderr_file_36" >/dev/null
TIMESTAMP_EXIT=$?
set -e
TIMESTAMP_STDERR=$(cat "$stderr_file_36")
rm -f "$stderr_file_36"

test_name="Stderr messages include [HH:MM:SS] timestamp prefix"
test_ok=true

# Script should exit non-zero for empty description (error output expected)
if [ "$TIMESTAMP_EXIT" -eq 0 ]; then
    log_fail "$test_name" "script exited 0, expected non-zero (no stderr output to check)"
    test_ok=false
fi

if $test_ok; then
    # Verify stderr is not empty
    if [ -z "$TIMESTAMP_STDERR" ]; then
        log_fail "$test_name" "stderr is empty (expected error messages with timestamps)"
        test_ok=false
    fi
fi

if $test_ok; then
    # Verify at least one line matches [HH:MM:SS] pattern
    if printf '%s' "$TIMESTAMP_STDERR" | grep -qE '\[([0-9]{2}:){2}[0-9]{2}\]'; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "no [HH:MM:SS] timestamp found in stderr (got: $TIMESTAMP_STDERR)"
    fi
fi

# --- Summary ---

printf -- "\n${CYAN}============================================${NC}\n"
printf -- "${CYAN}Test Summary${NC}\n"
printf -- "${CYAN}============================================${NC}\n\n"

printf "%d/%d tests passed\n" "$PASS" "$TOTAL"

if [ "$FAIL" -eq 0 ]; then
    printf "\n${GREEN}All tests passed.${NC}\n"
    exit 0
else
    printf "\n${RED}%d test(s) failed.${NC}\n" "$FAIL"
    exit 1
fi
