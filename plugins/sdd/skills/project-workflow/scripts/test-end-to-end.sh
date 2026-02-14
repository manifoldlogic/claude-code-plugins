#!/usr/bin/env bash
#
# End-to-End Integration Test for Smart Document Inclusion Pipeline
# Tests the complete triage -> scaffold -> validate pipeline with 8 scenarios.
#
# This script validates the SCRIPTABLE components of the smart document
# inclusion workflow. The full AI-agent workflow (/sdd:plan-ticket) involves
# agents that cannot be scripted; this test exercises the mechanical pipeline:
#   1. triage-documents.sh  - produces correct manifests for each scenario
#   2. scaffold-ticket.sh   - creates correct documents based on manifest
#   3. validate-structure.sh - passes for created tickets
#
# Test Scenarios:
#   1. Backend API ticket - observability + api-contract conditional docs
#   2. UI redesign ticket - accessibility + prd conditional docs
#   3. Documentation-only ticket - only core + standard (no conditionals)
#   4. Override force include - +accessibility on backend ticket
#   5. Override force exclude - -security-review on auth ticket
#   6. Database migration ticket - migration-plan conditional doc
#   7. Variable document set validation - scaffold + validate pass
#   8. Full pipeline - triage -> scaffold -> validate -> consistency check
#
# Usage:
#   bash test-end-to-end.sh
#
# Exit Codes:
#   0 - All tests passed
#   1 - One or more tests failed
#   2 - Setup validation failed (missing dependencies)

set -euo pipefail

# --- Configuration ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRIAGE_SCRIPT="$SCRIPT_DIR/triage-documents.sh"
SCAFFOLD_SCRIPT="$SCRIPT_DIR/scaffold-ticket.sh"
VALIDATE_SCRIPT="$SCRIPT_DIR/validate-structure.sh"

# --- Test Infrastructure ---

PASS=0
FAIL=0
TOTAL=0
TEMP_DIR=""

# Colors (if terminal supports)
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    GREEN=''
    RED=''
    YELLOW=''
    CYAN=''
    NC=''
fi

# --- Helper Functions ---

log_pass() {
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
    printf "  Test %d: %s ... ${GREEN}PASS${NC}\n" "$TOTAL" "$1"
}

log_fail() {
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
    printf "  Test %d: %s ... ${RED}FAIL: %s${NC}\n" "$TOTAL" "$1" "$2"
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
get_action() {
    printf '%s' "$TRIAGE_OUTPUT" | jq -r --arg id "$1" \
        '.documents[] | select(.id == $id) | .action'
}

# Get the reason for a specific document ID from the triage output.
get_reason() {
    printf '%s' "$TRIAGE_OUTPUT" | jq -r --arg id "$1" \
        '.documents[] | select(.id == $id) | .reason'
}

# Get list of document IDs with action=generate
get_generated_ids() {
    printf '%s' "$TRIAGE_OUTPUT" | jq -r '.documents[] | select(.action=="generate") | .id' | sort
}

# Get list of document IDs with action=skip
get_skipped_ids() {
    printf '%s' "$TRIAGE_OUTPUT" | jq -r '.documents[] | select(.action=="skip") | .id' | sort
}

# Check if a document ID is in the generated set
is_generated() {
    local doc_id="$1"
    local action
    action=$(get_action "$doc_id")
    [ "$action" = "generate" ]
}

# Check if a document ID is in the skipped set
is_skipped() {
    local doc_id="$1"
    local action
    action=$(get_action "$doc_id")
    [ "$action" = "skip" ]
}

# Run scaffold-ticket.sh with manifest and capture output
# Arguments:
#   $1 - manifest path
#   $2 - ticket ID
#   $3 - ticket name (kebab-case)
# Sets global: SCAFFOLD_OUTPUT, SCAFFOLD_EXIT
run_scaffold() {
    local manifest_path="$1"
    local ticket_id="$2"
    local ticket_name="$3"
    set +e
    SCAFFOLD_OUTPUT=$(bash "$SCAFFOLD_SCRIPT" --manifest "$manifest_path" "$ticket_id" "$ticket_name" 2>/dev/null)
    SCAFFOLD_EXIT=$?
    set -e
}

# Run validate-structure.sh for a ticket
# Arguments:
#   $1 - ticket ID
# Sets global: VALIDATE_OUTPUT, VALIDATE_EXIT
run_validate() {
    local ticket_id="$1"
    set +e
    VALIDATE_OUTPUT=$(bash "$VALIDATE_SCRIPT" "$ticket_id" 2>/dev/null)
    VALIDATE_EXIT=$?
    set -e
}

# --- Cleanup ---

cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

trap cleanup EXIT

# --- Setup ---

printf -- "${CYAN}============================================${NC}\n"
printf -- "${CYAN}End-to-End Integration Test Suite${NC}\n"
printf -- "${CYAN}Smart Document Inclusion Pipeline${NC}\n"
printf -- "${CYAN}============================================${NC}\n\n"

printf "Setup validation...\n"

# Verify scripts exist
for script_path in "$TRIAGE_SCRIPT" "$SCAFFOLD_SCRIPT" "$VALIDATE_SCRIPT"; do
    if [ ! -f "$script_path" ]; then
        printf "${RED}ERROR: Script not found: %s${NC}\n" "$script_path"
        exit 2
    fi
    printf "  Found: %s\n" "$(basename "$script_path")"
done

# Verify jq available
if ! command -v jq >/dev/null 2>&1; then
    printf "${RED}ERROR: jq is required but not installed${NC}\n"
    exit 2
fi
printf "  jq available: %s\n" "$(jq --version)"

# Create temporary directory for all tests
TEMP_DIR=$(mktemp -d)
export SDD_ROOT_DIR="$TEMP_DIR"
mkdir -p "$SDD_ROOT_DIR/tickets"

printf "  SDD_ROOT_DIR: %s\n" "$SDD_ROOT_DIR"
printf "\n"


# =============================================================
# Scenario 1: Backend API Ticket
# Description: "backend API caching layer"
# Expected: core + standard + observability + api-contract generated
# NOT expected: accessibility, migration-plan, runbook, dependency-audit
# =============================================================

printf -- "${CYAN}--- Scenario 1: Backend API Ticket ---${NC}\n\n"

run_triage "backend API caching layer"

test_name="S1: Triage succeeds"
if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "exit code $TRIAGE_EXIT"
else
    log_pass "$test_name"
fi

test_name="S1: Observability included"
if is_generated "observability"; then
    log_pass "$test_name"
else
    log_fail "$test_name" "observability action=$(get_action 'observability')"
fi

test_name="S1: API contract included"
if is_generated "api-contract"; then
    log_pass "$test_name"
else
    log_fail "$test_name" "api-contract action=$(get_action 'api-contract')"
fi

test_name="S1: Core docs (analysis, architecture, plan) included"
core_ok=true
for doc in analysis architecture plan; do
    if ! is_generated "$doc"; then
        log_fail "$test_name" "$doc action=$(get_action "$doc")"
        core_ok=false
        break
    fi
done
if $core_ok; then
    log_pass "$test_name"
fi

test_name="S1: Standard docs (prd, quality-strategy, security-review) included"
std_ok=true
for doc in prd quality-strategy security-review; do
    if ! is_generated "$doc"; then
        log_fail "$test_name" "$doc action=$(get_action "$doc")"
        std_ok=false
        break
    fi
done
if $std_ok; then
    log_pass "$test_name"
fi

test_name="S1: Accessibility NOT included"
if is_skipped "accessibility"; then
    log_pass "$test_name"
else
    log_fail "$test_name" "accessibility action=$(get_action 'accessibility')"
fi

test_name="S1: Migration-plan NOT included"
if is_skipped "migration-plan"; then
    log_pass "$test_name"
else
    log_fail "$test_name" "migration-plan action=$(get_action 'migration-plan')"
fi

test_name="S1: Dependency-audit NOT included"
if is_skipped "dependency-audit"; then
    log_pass "$test_name"
else
    log_fail "$test_name" "dependency-audit action=$(get_action 'dependency-audit')"
fi

# Save manifest for later use in scenario 7 and 8
S1_MANIFEST="$TEMP_DIR/s1-manifest.json"
printf '%s' "$TRIAGE_OUTPUT" > "$S1_MANIFEST"

# Scaffold ticket
run_scaffold "$S1_MANIFEST" "BKAPI" "backend-api-caching"

test_name="S1: Scaffold succeeds"
if [ "$SCAFFOLD_EXIT" -ne 0 ]; then
    log_fail "$test_name" "exit code $SCAFFOLD_EXIT"
else
    log_pass "$test_name"
fi

test_name="S1: Scaffold creates observability.md"
if [ -f "$SDD_ROOT_DIR/tickets/BKAPI_backend-api-caching/planning/observability.md" ]; then
    log_pass "$test_name"
else
    log_fail "$test_name" "file not found"
fi

test_name="S1: Scaffold creates api-contract.md"
if [ -f "$SDD_ROOT_DIR/tickets/BKAPI_backend-api-caching/planning/api-contract.md" ]; then
    log_pass "$test_name"
else
    log_fail "$test_name" "file not found"
fi

test_name="S1: Scaffold does NOT create accessibility.md"
if [ ! -f "$SDD_ROOT_DIR/tickets/BKAPI_backend-api-caching/planning/accessibility.md" ]; then
    log_pass "$test_name"
else
    log_fail "$test_name" "file unexpectedly exists"
fi

printf "\n"


# =============================================================
# Scenario 2: UI Redesign Ticket
# Description: "user profile page redesign with new form components"
# Expected: core + standard + accessibility + prd generated
# NOT expected: migration-plan, runbook, dependency-audit
# =============================================================

printf -- "${CYAN}--- Scenario 2: UI Redesign Ticket ---${NC}\n\n"

run_triage "user profile page redesign with new form components"

test_name="S2: Triage succeeds"
if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "exit code $TRIAGE_EXIT"
else
    log_pass "$test_name"
fi

test_name="S2: Accessibility included"
if is_generated "accessibility"; then
    log_pass "$test_name"
else
    log_fail "$test_name" "accessibility action=$(get_action 'accessibility')"
fi

test_name="S2: PRD included"
if is_generated "prd"; then
    log_pass "$test_name"
else
    log_fail "$test_name" "prd action=$(get_action 'prd')"
fi

test_name="S2: Migration-plan NOT included"
if is_skipped "migration-plan"; then
    log_pass "$test_name"
else
    log_fail "$test_name" "migration-plan action=$(get_action 'migration-plan')"
fi

test_name="S2: Dependency-audit NOT included"
if is_skipped "dependency-audit"; then
    log_pass "$test_name"
else
    log_fail "$test_name" "dependency-audit action=$(get_action 'dependency-audit')"
fi

# Scaffold
S2_MANIFEST="$TEMP_DIR/s2-manifest.json"
printf '%s' "$TRIAGE_OUTPUT" > "$S2_MANIFEST"
run_scaffold "$S2_MANIFEST" "UIRED" "user-profile-redesign"

test_name="S2: Scaffold creates accessibility.md"
if [ -f "$SDD_ROOT_DIR/tickets/UIRED_user-profile-redesign/planning/accessibility.md" ]; then
    log_pass "$test_name"
else
    log_fail "$test_name" "file not found"
fi

test_name="S2: Scaffold creates prd.md"
if [ -f "$SDD_ROOT_DIR/tickets/UIRED_user-profile-redesign/planning/prd.md" ]; then
    log_pass "$test_name"
else
    log_fail "$test_name" "file not found"
fi

printf "\n"


# =============================================================
# Scenario 3: Documentation-Only Ticket
# Description: "update README and developer documentation"
# Expected: core + standard only (no conditional documents)
# =============================================================

printf -- "${CYAN}--- Scenario 3: Documentation-Only Ticket ---${NC}\n\n"

run_triage "update README and developer documentation"

test_name="S3: Triage succeeds"
if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "exit code $TRIAGE_EXIT"
else
    log_pass "$test_name"
fi

test_name="S3: Core + standard docs included"
all_ok=true
for doc in analysis architecture plan prd quality-strategy security-review; do
    if ! is_generated "$doc"; then
        log_fail "$test_name" "$doc action=$(get_action "$doc")"
        all_ok=false
        break
    fi
done
if $all_ok; then
    log_pass "$test_name"
fi

test_name="S3: No conditional documents generated"
conditionals_ok=true
for doc in observability migration-plan accessibility api-contract runbook dependency-audit; do
    if is_generated "$doc"; then
        log_fail "$test_name" "$doc unexpectedly has action=generate"
        conditionals_ok=false
        break
    fi
done
if $conditionals_ok; then
    log_pass "$test_name"
fi

# Scaffold
S3_MANIFEST="$TEMP_DIR/s3-manifest.json"
printf '%s' "$TRIAGE_OUTPUT" > "$S3_MANIFEST"
run_scaffold "$S3_MANIFEST" "DOCUP" "doc-update"

test_name="S3: Scaffold creates only core + standard docs"
s3_planning="$SDD_ROOT_DIR/tickets/DOCUP_doc-update/planning"
s3_ok=true
# Should have: analysis.md, architecture.md, plan.md, prd.md, quality-strategy.md, security-review.md
for doc in analysis.md architecture.md plan.md prd.md quality-strategy.md security-review.md; do
    if [ ! -f "$s3_planning/$doc" ]; then
        log_fail "$test_name" "missing $doc"
        s3_ok=false
        break
    fi
done
if $s3_ok; then
    log_pass "$test_name"
fi

test_name="S3: No conditional document files created"
s3_cond_ok=true
for doc in observability.md migration-plan.md accessibility.md api-contract.md runbook.md dependency-audit.md; do
    if [ -f "$s3_planning/$doc" ]; then
        log_fail "$test_name" "$doc unexpectedly created"
        s3_cond_ok=false
        break
    fi
done
if $s3_cond_ok; then
    log_pass "$test_name"
fi

printf "\n"


# =============================================================
# Scenario 4: Override Force Include
# Description: "backend API" +accessibility
# Expected: accessibility included despite no UI keywords
# =============================================================

printf -- "${CYAN}--- Scenario 4: Override Force Include ---${NC}\n\n"

run_triage "backend API" "+accessibility"

test_name="S4: Triage succeeds"
if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "exit code $TRIAGE_EXIT"
else
    log_pass "$test_name"
fi

test_name="S4: Accessibility force-included"
if is_generated "accessibility"; then
    log_pass "$test_name"
else
    log_fail "$test_name" "accessibility action=$(get_action 'accessibility')"
fi

test_name="S4: Override reason in manifest"
acc_reason=$(get_reason "accessibility")
if printf '%s' "$acc_reason" | grep -qi "override"; then
    log_pass "$test_name"
else
    log_fail "$test_name" "reason='$acc_reason', expected to contain 'Override'"
fi

# Scaffold
S4_MANIFEST="$TEMP_DIR/s4-manifest.json"
printf '%s' "$TRIAGE_OUTPUT" > "$S4_MANIFEST"
run_scaffold "$S4_MANIFEST" "BKAP" "backend-api-override"

test_name="S4: Scaffold creates accessibility.md from override"
if [ -f "$SDD_ROOT_DIR/tickets/BKAP_backend-api-override/planning/accessibility.md" ]; then
    log_pass "$test_name"
else
    log_fail "$test_name" "file not found"
fi

printf "\n"


# =============================================================
# Scenario 5: Override Force Exclude
# Description: "add JWT authentication" -security-review
# Expected: security-review excluded despite security keywords
# =============================================================

printf -- "${CYAN}--- Scenario 5: Override Force Exclude ---${NC}\n\n"

run_triage "add JWT authentication" "-security-review"

test_name="S5: Triage succeeds"
if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "exit code $TRIAGE_EXIT"
else
    log_pass "$test_name"
fi

test_name="S5: Security-review force-excluded"
if is_skipped "security-review"; then
    log_pass "$test_name"
else
    log_fail "$test_name" "security-review action=$(get_action 'security-review')"
fi

test_name="S5: Override reason in manifest"
sec_reason=$(get_reason "security-review")
if printf '%s' "$sec_reason" | grep -qi "override"; then
    log_pass "$test_name"
else
    log_fail "$test_name" "reason='$sec_reason', expected to contain 'Override'"
fi

# Scaffold
S5_MANIFEST="$TEMP_DIR/s5-manifest.json"
printf '%s' "$TRIAGE_OUTPUT" > "$S5_MANIFEST"
run_scaffold "$S5_MANIFEST" "JWTAU" "jwt-authentication"

test_name="S5: Scaffold does NOT create security-review.md"
if [ ! -f "$SDD_ROOT_DIR/tickets/JWTAU_jwt-authentication/planning/security-review.md" ]; then
    log_pass "$test_name"
else
    log_fail "$test_name" "file unexpectedly exists"
fi

printf "\n"


# =============================================================
# Scenario 6: Database Migration Ticket
# Description: "migrate user schema to support multi-tenancy"
# Expected: core + standard + migration-plan generated
# =============================================================

printf -- "${CYAN}--- Scenario 6: Database Migration Ticket ---${NC}\n\n"

run_triage "migrate user schema to support multi-tenancy"

test_name="S6: Triage succeeds"
if [ "$TRIAGE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "exit code $TRIAGE_EXIT"
else
    log_pass "$test_name"
fi

test_name="S6: Migration-plan included"
if is_generated "migration-plan"; then
    log_pass "$test_name"
else
    log_fail "$test_name" "migration-plan action=$(get_action 'migration-plan')"
fi

# Scaffold
S6_MANIFEST="$TEMP_DIR/s6-manifest.json"
printf '%s' "$TRIAGE_OUTPUT" > "$S6_MANIFEST"
run_scaffold "$S6_MANIFEST" "DBMIG" "user-schema-migration"

test_name="S6: Scaffold creates migration-plan.md"
if [ -f "$SDD_ROOT_DIR/tickets/DBMIG_user-schema-migration/planning/migration-plan.md" ]; then
    log_pass "$test_name"
else
    log_fail "$test_name" "file not found"
fi

test_name="S6: migration-plan.md has content"
if [ -s "$SDD_ROOT_DIR/tickets/DBMIG_user-schema-migration/planning/migration-plan.md" ]; then
    log_pass "$test_name"
else
    log_fail "$test_name" "file is empty"
fi

printf "\n"


# =============================================================
# Scenario 7: Variable Document Set Validation
# Uses Backend API ticket (BKAPI) from Scenario 1
# Run validate-structure.sh, should pass with manifest-driven docs
# =============================================================

printf -- "${CYAN}--- Scenario 7: Variable Document Set Validation ---${NC}\n\n"

run_validate "BKAPI"

test_name="S7: Validate-structure succeeds for manifest-driven ticket"
if [ "$VALIDATE_EXIT" -ne 0 ]; then
    log_fail "$test_name" "exit code $VALIDATE_EXIT"
else
    log_pass "$test_name"
fi

test_name="S7: Validation reports ticket as valid"
valid_flag=$(printf '%s' "$VALIDATE_OUTPUT" | jq -r '.validation.ticket.valid // empty' 2>/dev/null)
if [ "$valid_flag" = "true" ]; then
    log_pass "$test_name"
else
    issues=$(printf '%s' "$VALIDATE_OUTPUT" | jq -c '.validation.ticket.issues // []' 2>/dev/null)
    log_fail "$test_name" "valid=$valid_flag, issues=$issues"
fi

test_name="S7: No issues reported"
issue_count=$(printf '%s' "$VALIDATE_OUTPUT" | jq '.validation.ticket.issues | length' 2>/dev/null)
if [ "$issue_count" = "0" ]; then
    log_pass "$test_name"
else
    issues=$(printf '%s' "$VALIDATE_OUTPUT" | jq -c '.validation.ticket.issues' 2>/dev/null)
    log_fail "$test_name" "issue_count=$issue_count, issues=$issues"
fi

# Also validate the documentation-only ticket (DOCUP)
run_validate "DOCUP"

test_name="S7: Validate-structure also passes for doc-only ticket"
valid_flag=$(printf '%s' "$VALIDATE_OUTPUT" | jq -r '.validation.ticket.valid // empty' 2>/dev/null)
if [ "$valid_flag" = "true" ]; then
    log_pass "$test_name"
else
    issues=$(printf '%s' "$VALIDATE_OUTPUT" | jq -c '.validation.ticket.issues // []' 2>/dev/null)
    log_fail "$test_name" "valid=$valid_flag, issues=$issues"
fi

printf "\n"


# =============================================================
# Scenario 8: Full Pipeline Consistency Check
# Run full pipeline for one scenario: triage -> scaffold -> validate
# Verify:
#   - .triage-manifest.json saved in planning/
#   - README.md links match created documents
#   - All created files have content (not empty)
# =============================================================

printf -- "${CYAN}--- Scenario 8: Full Pipeline Consistency Check ---${NC}\n\n"

# Triage
run_triage "implement real-time notification service with WebSocket endpoints"

S8_MANIFEST="$TEMP_DIR/s8-manifest.json"
printf '%s' "$TRIAGE_OUTPUT" > "$S8_MANIFEST"

test_name="S8: Triage produces valid manifest"
if [ "$TRIAGE_EXIT" -eq 0 ] && printf '%s' "$TRIAGE_OUTPUT" | jq empty 2>/dev/null; then
    log_pass "$test_name"
else
    log_fail "$test_name" "exit=$TRIAGE_EXIT or invalid JSON"
fi

# Scaffold
run_scaffold "$S8_MANIFEST" "NTSVC" "notification-service"

test_name="S8: Scaffold succeeds"
if [ "$SCAFFOLD_EXIT" -eq 0 ]; then
    log_pass "$test_name"
else
    log_fail "$test_name" "exit code $SCAFFOLD_EXIT"
fi

# Verify .triage-manifest.json saved
test_name="S8: .triage-manifest.json saved in planning/"
manifest_saved="$SDD_ROOT_DIR/tickets/NTSVC_notification-service/planning/.triage-manifest.json"
if [ -f "$manifest_saved" ]; then
    log_pass "$test_name"
else
    log_fail "$test_name" "file not found"
fi

# Verify saved manifest matches original
test_name="S8: Saved manifest matches original triage output"
if [ -f "$manifest_saved" ]; then
    orig_hash=$(printf '%s' "$TRIAGE_OUTPUT" | jq -cS '.' | md5sum | cut -d' ' -f1)
    saved_hash=$(jq -cS '.' "$manifest_saved" | md5sum | cut -d' ' -f1)
    if [ "$orig_hash" = "$saved_hash" ]; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "hashes differ: orig=$orig_hash, saved=$saved_hash"
    fi
else
    log_fail "$test_name" "manifest not saved"
fi

# Verify README.md links match created documents
test_name="S8: README.md links match created planning documents"
s8_ticket="$SDD_ROOT_DIR/tickets/NTSVC_notification-service"
s8_readme="$s8_ticket/README.md"
if [ -f "$s8_readme" ]; then
    # Get expected docs from manifest (action=generate)
    expected_docs=$(printf '%s' "$TRIAGE_OUTPUT" | jq -r '.documents[] | select(.action=="generate") | .filename' | sort)
    # Get links from README (planning/*.md links)
    readme_links=$(grep -o 'planning/[a-z-]*\.md' "$s8_readme" 2>/dev/null | sed 's|planning/||' | sort)

    if [ "$expected_docs" = "$readme_links" ]; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "expected=$(printf '%s' "$expected_docs" | tr '\n' ','), readme=$(printf '%s' "$readme_links" | tr '\n' ',')"
    fi
else
    log_fail "$test_name" "README.md not found"
fi

# Verify all created files have content (not empty)
test_name="S8: All planning documents have content (not empty)"
all_have_content=true
empty_files=""
for doc_file in "$s8_ticket"/planning/*.md; do
    if [ -f "$doc_file" ] && [ ! -s "$doc_file" ]; then
        all_have_content=false
        empty_files="${empty_files} $(basename "$doc_file")"
    fi
done
if $all_have_content; then
    log_pass "$test_name"
else
    log_fail "$test_name" "empty files:$empty_files"
fi

# Validate structure
run_validate "NTSVC"

test_name="S8: Validate-structure passes for full pipeline ticket"
valid_flag=$(printf '%s' "$VALIDATE_OUTPUT" | jq -r '.validation.ticket.valid // empty' 2>/dev/null)
if [ "$valid_flag" = "true" ]; then
    log_pass "$test_name"
else
    issues=$(printf '%s' "$VALIDATE_OUTPUT" | jq -c '.validation.ticket.issues // []' 2>/dev/null)
    log_fail "$test_name" "valid=$valid_flag, issues=$issues"
fi

# Verify the generated docs count matches expected
test_name="S8: Document count matches manifest generate count"
expected_count=$(printf '%s' "$TRIAGE_OUTPUT" | jq '[.documents[] | select(.action=="generate")] | length')
actual_count=$(find "$s8_ticket/planning" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$expected_count" = "$actual_count" ]; then
    log_pass "$test_name"
else
    log_fail "$test_name" "expected=$expected_count, actual=$actual_count"
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
