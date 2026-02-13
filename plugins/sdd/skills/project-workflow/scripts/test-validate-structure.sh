#!/usr/bin/env bash
#
# Tests for validate-structure.sh dynamic validation
# Covers: manifest-driven, legacy fallback, core enforcement,
#          invalid manifest, empty manifest, N/A documents, extra documents
#
# Usage:
#   bash test-validate-structure.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VALIDATE_SCRIPT="$SCRIPT_DIR/validate-structure.sh"
TEST_DIR=""
PASS=0
FAIL=0

# --- Helpers ---

setup_test_dir() {
    TEST_DIR=$(mktemp -d)
    export SDD_ROOT_DIR="$TEST_DIR"
    mkdir -p "$TEST_DIR/tickets"
}

teardown_test_dir() {
    if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi
}

# Create a minimal valid ticket structure
create_ticket() {
    local ticket_id="$1"
    local ticket_name="$2"
    local ticket_dir="$TEST_DIR/tickets/${ticket_id}_${ticket_name}"
    mkdir -p "$ticket_dir/planning" "$ticket_dir/tasks"
    printf "# Ticket\n" > "$ticket_dir/README.md"
    echo "$ticket_dir"
}

# Create a planning file with content
create_planning_file() {
    local ticket_dir="$1"
    local filename="$2"
    local content="${3:-# Document content}"
    printf "%s\n" "$content" > "$ticket_dir/planning/$filename"
}

# Create a triage manifest
create_manifest() {
    local ticket_dir="$1"
    local json_content="$2"
    printf "%s\n" "$json_content" > "$ticket_dir/planning/.triage-manifest.json"
}

assert_contains() {
    local output="$1"
    local expected="$2"
    local test_name="$3"
    if echo "$output" | grep -q "$expected"; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "$test_name"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s\n" "$test_name"
        printf "    Expected output to contain: %s\n" "$expected"
    fi
}

assert_not_contains() {
    local output="$1"
    local unexpected="$2"
    local test_name="$3"
    if echo "$output" | grep -q "$unexpected"; then
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s\n" "$test_name"
        printf "    Output should NOT contain: %s\n" "$unexpected"
    else
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "$test_name"
    fi
}

assert_valid() {
    local output="$1"
    local test_name="$2"
    if echo "$output" | grep -q '"valid": true'; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "$test_name"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s (expected valid=true)\n" "$test_name"
    fi
}

assert_invalid() {
    local output="$1"
    local test_name="$2"
    if echo "$output" | grep -q '"valid": false'; then
        PASS=$((PASS + 1))
        printf "  PASS: %s\n" "$test_name"
    else
        FAIL=$((FAIL + 1))
        printf "  FAIL: %s (expected valid=false)\n" "$test_name"
    fi
}

# --- Tests ---

test_legacy_fallback_all_present() {
    printf "\nTest: Legacy fallback - all required files present\n"
    setup_test_dir
    local ticket_dir
    ticket_dir=$(create_ticket "TEST" "legacy-all")

    # Create all legacy required files
    for f in analysis.md architecture.md plan.md prd.md quality-strategy.md security-review.md; do
        create_planning_file "$ticket_dir" "$f"
    done

    local output
    output=$(bash "$VALIDATE_SCRIPT" "TEST" 2>&1)
    assert_valid "$output" "Ticket is valid with all legacy files"
    assert_not_contains "$output" "Missing planning/" "No missing file errors"
    teardown_test_dir
}

test_legacy_fallback_missing_file() {
    printf "\nTest: Legacy fallback - missing prd.md\n"
    setup_test_dir
    local ticket_dir
    ticket_dir=$(create_ticket "TEST" "legacy-missing")

    # Create all except prd.md
    for f in analysis.md architecture.md plan.md quality-strategy.md security-review.md; do
        create_planning_file "$ticket_dir" "$f"
    done

    local output
    output=$(bash "$VALIDATE_SCRIPT" "TEST" 2>&1)
    assert_invalid "$output" "Ticket is invalid with missing prd.md"
    assert_contains "$output" "Missing planning/prd.md" "Reports missing prd.md"
    teardown_test_dir
}

test_manifest_driven_validation() {
    printf "\nTest: Manifest-driven - validate only manifested docs\n"
    setup_test_dir
    local ticket_dir
    ticket_dir=$(create_ticket "MANIF" "with-manifest")

    # Create manifest that generates core + observability.md
    create_manifest "$ticket_dir" '{
        "ticket_description": "test",
        "overrides": [],
        "documents": [
            {"id": "analysis", "filename": "analysis.md", "action": "generate", "reason": "core"},
            {"id": "architecture", "filename": "architecture.md", "action": "generate", "reason": "core"},
            {"id": "plan", "filename": "plan.md", "action": "generate", "reason": "core"},
            {"id": "observability", "filename": "observability.md", "action": "generate", "reason": "needed"},
            {"id": "prd", "filename": "prd.md", "action": "skip", "reason": "not needed"}
        ]
    }'

    # Create all files that should be required
    for f in analysis.md architecture.md plan.md observability.md; do
        create_planning_file "$ticket_dir" "$f"
    done

    local output
    output=$(bash "$VALIDATE_SCRIPT" "MANIF" 2>&1)
    assert_valid "$output" "Ticket valid with all manifested docs present"
    assert_not_contains "$output" "prd.md" "prd.md (skipped in manifest) not required"
    teardown_test_dir
}

test_manifest_missing_manifested_doc() {
    printf "\nTest: Manifest-driven - missing manifested document\n"
    setup_test_dir
    local ticket_dir
    ticket_dir=$(create_ticket "MANIF" "missing-manifest-doc")

    create_manifest "$ticket_dir" '{
        "ticket_description": "test",
        "overrides": [],
        "documents": [
            {"id": "analysis", "filename": "analysis.md", "action": "generate", "reason": "core"},
            {"id": "architecture", "filename": "architecture.md", "action": "generate", "reason": "core"},
            {"id": "plan", "filename": "plan.md", "action": "generate", "reason": "core"},
            {"id": "observability", "filename": "observability.md", "action": "generate", "reason": "needed"}
        ]
    }'

    # Create core files but not observability.md
    for f in analysis.md architecture.md plan.md; do
        create_planning_file "$ticket_dir" "$f"
    done

    local output
    output=$(bash "$VALIDATE_SCRIPT" "MANIF" 2>&1)
    assert_invalid "$output" "Ticket invalid when manifested doc missing"
    assert_contains "$output" "Manifested document missing: observability.md" "Error identifies manifested doc"
    teardown_test_dir
}

test_core_tier_enforcement() {
    printf "\nTest: Core-tier enforcement - manifest excludes architecture.md\n"
    setup_test_dir
    local ticket_dir
    ticket_dir=$(create_ticket "CORE" "core-enforcement")

    # Manifest skips architecture.md - but core tier overrides
    create_manifest "$ticket_dir" '{
        "ticket_description": "test",
        "overrides": [],
        "documents": [
            {"id": "analysis", "filename": "analysis.md", "action": "generate", "reason": "core"},
            {"id": "architecture", "filename": "architecture.md", "action": "skip", "reason": "not needed"},
            {"id": "plan", "filename": "plan.md", "action": "generate", "reason": "core"}
        ]
    }'

    # Only create analysis.md and plan.md (not architecture.md)
    for f in analysis.md plan.md; do
        create_planning_file "$ticket_dir" "$f"
    done

    local output
    output=$(bash "$VALIDATE_SCRIPT" "CORE" 2>&1)
    assert_invalid "$output" "Ticket invalid when core doc missing"
    assert_contains "$output" "Required core document missing: architecture.md" "Error identifies core doc"
    teardown_test_dir
}

test_invalid_manifest_json() {
    printf "\nTest: Invalid manifest JSON\n"
    setup_test_dir
    local ticket_dir
    ticket_dir=$(create_ticket "BAD" "invalid-json")

    # Create invalid JSON manifest
    create_manifest "$ticket_dir" 'this is not valid json {'

    # Create all core files (shouldn't matter - manifest parse should fail first)
    for f in analysis.md architecture.md plan.md; do
        create_planning_file "$ticket_dir" "$f"
    done

    local output
    output=$(bash "$VALIDATE_SCRIPT" "BAD" 2>&1)
    assert_invalid "$output" "Ticket invalid with broken manifest"
    assert_contains "$output" "Manifest file exists but contains invalid JSON" "Clear invalid JSON error"
    teardown_test_dir
}

test_empty_manifest_generate() {
    printf "\nTest: Empty manifest (zero generate entries)\n"
    setup_test_dir
    local ticket_dir
    ticket_dir=$(create_ticket "EMPTY" "empty-manifest")

    # Manifest with all skip, no generate
    create_manifest "$ticket_dir" '{
        "ticket_description": "test",
        "overrides": [],
        "documents": [
            {"id": "prd", "filename": "prd.md", "action": "skip", "reason": "not needed"},
            {"id": "security", "filename": "security-review.md", "action": "skip", "reason": "not needed"}
        ]
    }'

    # Create only core tier files
    for f in analysis.md architecture.md plan.md; do
        create_planning_file "$ticket_dir" "$f"
    done

    local output
    output=$(bash "$VALIDATE_SCRIPT" "EMPTY" 2>&1)
    assert_valid "$output" "Ticket valid with only core-tier when manifest has no generate entries"
    teardown_test_dir
}

test_na_documents_pass() {
    printf "\nTest: N/A-signed documents pass validation (file exists)\n"
    setup_test_dir
    local ticket_dir
    ticket_dir=$(create_ticket "NAD" "na-documents")

    # Create all legacy files, one with N/A content
    for f in analysis.md architecture.md plan.md quality-strategy.md security-review.md; do
        create_planning_file "$ticket_dir" "$f"
    done
    create_planning_file "$ticket_dir" "prd.md" "# PRD\n\nN/A - Not applicable for this ticket type"

    local output
    output=$(bash "$VALIDATE_SCRIPT" "NAD" 2>&1)
    assert_valid "$output" "N/A document passes (file exists)"
    teardown_test_dir
}

test_extra_documents_no_failure() {
    printf "\nTest: Extra documents do not cause failure\n"
    setup_test_dir
    local ticket_dir
    ticket_dir=$(create_ticket "EXTRA" "extra-docs")

    create_manifest "$ticket_dir" '{
        "ticket_description": "test",
        "overrides": [],
        "documents": [
            {"id": "analysis", "filename": "analysis.md", "action": "generate", "reason": "core"},
            {"id": "architecture", "filename": "architecture.md", "action": "generate", "reason": "core"},
            {"id": "plan", "filename": "plan.md", "action": "generate", "reason": "core"}
        ]
    }'

    # Create required files PLUS extras
    for f in analysis.md architecture.md plan.md prd.md observability.md extra-notes.md; do
        create_planning_file "$ticket_dir" "$f"
    done

    local output
    output=$(bash "$VALIDATE_SCRIPT" "EXTRA" 2>&1)
    assert_valid "$output" "Ticket valid despite extra documents"
    assert_not_contains "$output" "prd.md" "Extra prd.md not flagged"
    assert_not_contains "$output" "observability.md" "Extra observability.md not flagged"
    teardown_test_dir
}

test_manifest_core_always_required() {
    printf "\nTest: Core tier always required even with manifest\n"
    setup_test_dir
    local ticket_dir
    ticket_dir=$(create_ticket "COREA" "core-always")

    # Manifest generates only non-core docs
    create_manifest "$ticket_dir" '{
        "ticket_description": "test",
        "overrides": [],
        "documents": [
            {"id": "observability", "filename": "observability.md", "action": "generate", "reason": "needed"}
        ]
    }'

    # Create only the manifested doc, missing core
    create_planning_file "$ticket_dir" "observability.md"

    local output
    output=$(bash "$VALIDATE_SCRIPT" "COREA" 2>&1)
    assert_invalid "$output" "Ticket invalid when core docs missing (even with manifest)"
    assert_contains "$output" "Required core document missing: analysis.md" "Missing analysis.md"
    assert_contains "$output" "Required core document missing: architecture.md" "Missing architecture.md"
    assert_contains "$output" "Required core document missing: plan.md" "Missing plan.md"
    teardown_test_dir
}

test_legacy_missing_core_doc() {
    printf "\nTest: Legacy mode - missing core doc uses legacy error format\n"
    setup_test_dir
    local ticket_dir
    ticket_dir=$(create_ticket "LEGC" "legacy-core-missing")

    # Create all except analysis.md
    for f in architecture.md plan.md prd.md quality-strategy.md security-review.md; do
        create_planning_file "$ticket_dir" "$f"
    done

    local output
    output=$(bash "$VALIDATE_SCRIPT" "LEGC" 2>&1)
    assert_invalid "$output" "Ticket invalid with missing analysis.md in legacy mode"
    assert_contains "$output" "Missing planning/analysis.md" "Legacy error format used"
    teardown_test_dir
}

# --- Run all tests ---
printf "=== validate-structure.sh Dynamic Validation Tests ===\n"

test_legacy_fallback_all_present
test_legacy_fallback_missing_file
test_manifest_driven_validation
test_manifest_missing_manifested_doc
test_core_tier_enforcement
test_invalid_manifest_json
test_empty_manifest_generate
test_na_documents_pass
test_extra_documents_no_failure
test_manifest_core_always_required
test_legacy_missing_core_doc

printf "\n=== Results: %d passed, %d failed ===\n" "$PASS" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
