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
