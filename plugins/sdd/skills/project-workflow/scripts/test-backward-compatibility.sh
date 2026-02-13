#!/usr/bin/env bash
#
# Backward Compatibility Test Suite
# Validates Phase 2 changes (smart doc inclusion) haven't broken existing workflows.
#
# Tests:
#   1. scaffold-ticket.sh without --manifest produces original six documents
#   2. scaffold-ticket.sh creates planning/, tasks/, deliverables/ directories
#   3. validate-structure.sh passes for newly scaffolded ticket without manifest
#   4. validate-structure.sh passes for archived tickets (legacy structure)
#   5. create-tasks validation tiers: plan.md and architecture.md are "required"
#   6. README.md for legacy ticket contains links to all six documents
#
# Usage:
#   bash test-backward-compatibility.sh
#
# Exit Codes:
#   0 - All tests passed
#   1 - One or more tests failed
#   2 - Setup validation failed (missing dependencies)

set -euo pipefail

# --- Configuration ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAFFOLD_SCRIPT="$SCRIPT_DIR/scaffold-ticket.sh"
VALIDATE_SCRIPT="$SCRIPT_DIR/validate-structure.sh"
REGISTRY_FILE="$SCRIPT_DIR/../templates/document-registry.json"

# Two-root model: specs live in a parallel directory tree
SPECS_ROOT="${SPECS_ROOT:-/workspace/_SPECS/claude-code-plugins}"
ARCHIVE_DIR="$SPECS_ROOT/archive/tickets"

# --- Test Counters ---

PASS=0
FAIL=0
TOTAL=0

# --- Temporary directory with cleanup ---

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# --- Colors (if terminal supports) ---

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
    printf "Test %d: %s ... ${GREEN}PASS${NC}\n" "$TOTAL" "$1"
}

log_fail() {
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
    printf "Test %d: %s ... ${RED}FAIL: %s${NC}\n" "$TOTAL" "$1" "$2"
}

# --- Setup Validation ---

printf "${CYAN}============================================${NC}\n"
printf "${CYAN}Backward Compatibility Test Suite${NC}\n"
printf "${CYAN}============================================${NC}\n\n"

printf "Setup validation...\n"

if [ ! -f "$SCAFFOLD_SCRIPT" ]; then
    printf "${RED}ERROR: scaffold-ticket.sh not found at: %s${NC}\n" "$SCAFFOLD_SCRIPT"
    exit 2
fi

if [ ! -f "$VALIDATE_SCRIPT" ]; then
    printf "${RED}ERROR: validate-structure.sh not found at: %s${NC}\n" "$VALIDATE_SCRIPT"
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

printf "  scaffold-ticket.sh found: %s\n" "$SCAFFOLD_SCRIPT"
printf "  validate-structure.sh found: %s\n" "$VALIDATE_SCRIPT"
printf "  document-registry.json found: %s\n" "$REGISTRY_FILE"
printf "  jq available: $(jq --version)\n"
printf "\n"

# =============================================
# Test 1: scaffold-ticket.sh without --manifest
#         produces original six documents
# =============================================

printf -- "${CYAN}--- Scaffold Without Manifest Tests ---${NC}\n\n"

export SDD_ROOT_DIR="$TEMP_DIR/test1"
mkdir -p "$SDD_ROOT_DIR/tickets"

set +e
SCAFFOLD_OUTPUT=$(bash "$SCAFFOLD_SCRIPT" "BCTEST" "backward-compat" 2>&1)
SCAFFOLD_EXIT=$?
set -e

test_name="Scaffold without --manifest produces original six documents"
if [ "$SCAFFOLD_EXIT" -ne 0 ]; then
    log_fail "$test_name" "scaffold-ticket.sh exited $SCAFFOLD_EXIT"
else
    all_found=true
    missing_docs=""
    for doc in analysis.md architecture.md plan.md prd.md quality-strategy.md security-review.md; do
        if [ ! -f "$SDD_ROOT_DIR/tickets/BCTEST_backward-compat/planning/$doc" ]; then
            all_found=false
            missing_docs="${missing_docs} $doc"
        fi
    done

    if $all_found; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "Missing documents:${missing_docs}"
    fi
fi

# =============================================
# Test 2: scaffold-ticket.sh creates planning/,
#         tasks/, deliverables/ directories
# =============================================

test_name="Scaffold creates planning/, tasks/, deliverables/ directories"
TICKET_DIR="$SDD_ROOT_DIR/tickets/BCTEST_backward-compat"

if [ "$SCAFFOLD_EXIT" -ne 0 ]; then
    log_fail "$test_name" "scaffold-ticket.sh failed in Test 1; cannot check directories"
else
    dirs_ok=true
    missing_dirs=""
    for d in planning tasks deliverables; do
        if [ ! -d "$TICKET_DIR/$d" ]; then
            dirs_ok=false
            missing_dirs="${missing_dirs} $d/"
        fi
    done

    if $dirs_ok; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "Missing directories:${missing_dirs}"
    fi
fi

# =============================================
# Test 3: validate-structure.sh passes for
#         newly scaffolded ticket without manifest
# =============================================

printf -- "\n${CYAN}--- Validation Tests ---${NC}\n\n"

test_name="validate-structure.sh passes for scaffolded ticket without manifest"
if [ "$SCAFFOLD_EXIT" -ne 0 ]; then
    log_fail "$test_name" "scaffold-ticket.sh failed in Test 1; cannot validate"
else
    set +e
    VALIDATE_OUTPUT=$(bash "$VALIDATE_SCRIPT" "BCTEST" 2>&1)
    VALIDATE_EXIT=$?
    set -e

    if printf '%s' "$VALIDATE_OUTPUT" | grep -q '"valid": true'; then
        log_pass "$test_name"
    else
        # Extract issues for clearer error message
        issues=$(printf '%s' "$VALIDATE_OUTPUT" | grep -o '"issues": \[.*\]' | head -1)
        log_fail "$test_name" "Validation did not report valid=true. ${issues:-Output: $VALIDATE_OUTPUT}"
    fi
fi

# =============================================
# Test 4: validate-structure.sh passes for
#         archived tickets (3 most recent)
# =============================================

test_name="validate-structure.sh passes for archived tickets"
ARCHIVE_FOUND=false

if [ -d "$ARCHIVE_DIR" ]; then
    # Get the 3 most recent archived tickets (by modification time)
    ARCHIVED_TICKETS=$(ls -t "$ARCHIVE_DIR" 2>/dev/null | head -3)
    if [ -n "$ARCHIVED_TICKETS" ]; then
        ARCHIVE_FOUND=true
    fi
fi

if $ARCHIVE_FOUND; then
    # Set SDD_ROOT_DIR to a temp space where we copy archived tickets
    ARCHIVE_TEST_DIR="$TEMP_DIR/archive-test"
    mkdir -p "$ARCHIVE_TEST_DIR/tickets"
    export SDD_ROOT_DIR="$ARCHIVE_TEST_DIR"

    archive_all_pass=true
    archive_failures=""
    archive_count=0

    for ticket_folder in $ARCHIVED_TICKETS; do
        archive_count=$((archive_count + 1))
        # Extract ticket ID from folder name (everything before the first underscore)
        ticket_id=$(printf '%s' "$ticket_folder" | sed 's/_.*//')

        # Copy the archived ticket into our test tickets directory
        # (cp -r instead of symlink so find -type d works in validate-structure.sh)
        cp -r "$ARCHIVE_DIR/$ticket_folder" "$ARCHIVE_TEST_DIR/tickets/$ticket_folder"

        set +e
        ARC_OUTPUT=$(bash "$VALIDATE_SCRIPT" "$ticket_id" 2>&1)
        ARC_EXIT=$?
        set -e

        if ! printf '%s' "$ARC_OUTPUT" | grep -q '"valid": true'; then
            archive_all_pass=false
            archive_failures="${archive_failures} ${ticket_id}"
        fi
    done

    if $archive_all_pass; then
        log_pass "$test_name ($archive_count archived tickets validated)"
    else
        log_fail "$test_name" "Failed for:${archive_failures}"
    fi
else
    # No archived tickets found - create test tickets that mimic legacy structure
    LEGACY_TEST_DIR="$TEMP_DIR/legacy-test"
    mkdir -p "$LEGACY_TEST_DIR/tickets"
    export SDD_ROOT_DIR="$LEGACY_TEST_DIR"

    # Create 3 test tickets mimicking legacy structure
    legacy_all_pass=true
    legacy_failures=""
    legacy_count=0

    for tname in LEGONE_legacy-first LEGTWO_legacy-second LEGTHREE_legacy-third; do
        legacy_count=$((legacy_count + 1))
        ticket_id=$(printf '%s' "$tname" | sed 's/_.*//')
        mkdir -p "$LEGACY_TEST_DIR/tickets/$tname/planning"
        mkdir -p "$LEGACY_TEST_DIR/tickets/$tname/tasks"
        printf "# Ticket README\n" > "$LEGACY_TEST_DIR/tickets/$tname/README.md"

        for doc in analysis.md architecture.md plan.md prd.md quality-strategy.md security-review.md; do
            printf "# %s\n\nContent for legacy test ticket.\n" "$doc" > "$LEGACY_TEST_DIR/tickets/$tname/planning/$doc"
        done

        set +e
        LEG_OUTPUT=$(bash "$VALIDATE_SCRIPT" "$ticket_id" 2>&1)
        LEG_EXIT=$?
        set -e

        if ! printf '%s' "$LEG_OUTPUT" | grep -q '"valid": true'; then
            legacy_all_pass=false
            legacy_failures="${legacy_failures} ${ticket_id}"
        fi
    done

    if $legacy_all_pass; then
        log_pass "$test_name ($legacy_count synthetic legacy tickets validated)"
    else
        log_fail "$test_name" "Failed for:${legacy_failures}"
    fi
fi

# =============================================
# Test 5: create-tasks validation tiers unchanged
#         plan.md and architecture.md remain "required"
# =============================================

printf -- "\n${CYAN}--- Registry Validation Tests ---${NC}\n\n"

test_name="create-tasks validation: plan.md and architecture.md are 'required'"

plan_tier=$(jq -r '.documents.plan.create_tasks_validation' "$REGISTRY_FILE" 2>/dev/null)
arch_tier=$(jq -r '.documents.architecture.create_tasks_validation' "$REGISTRY_FILE" 2>/dev/null)

if [ "$plan_tier" = "required" ] && [ "$arch_tier" = "required" ]; then
    log_pass "$test_name"
else
    log_fail "$test_name" "plan='$plan_tier', architecture='$arch_tier' (both should be 'required')"
fi

# =============================================
# Test 6: README.md for legacy ticket contains
#         links to all six documents
# =============================================

printf -- "\n${CYAN}--- README Link Tests ---${NC}\n\n"

# Use the ticket scaffolded in Test 1
README_PATH="$TEMP_DIR/test1/tickets/BCTEST_backward-compat/README.md"

test_name="README.md contains links to all six legacy documents"
if [ ! -f "$README_PATH" ]; then
    log_fail "$test_name" "README.md not found at: $README_PATH"
else
    all_links=true
    missing_links=""
    for doc in analysis.md architecture.md plan.md prd.md quality-strategy.md security-review.md; do
        if ! grep -q "planning/$doc" "$README_PATH"; then
            all_links=false
            missing_links="${missing_links} $doc"
        fi
    done

    if $all_links; then
        log_pass "$test_name"
    else
        log_fail "$test_name" "Missing links for:${missing_links}"
    fi
fi

# --- Summary ---

printf "\n${CYAN}============================================${NC}\n"
printf "${CYAN}Test Summary${NC}\n"
printf "${CYAN}============================================${NC}\n\n"

printf "%d/%d tests passed\n" "$PASS" "$TOTAL"

if [ "$FAIL" -eq 0 ]; then
    printf "\n${GREEN}All tests passed.${NC}\n"
    exit 0
else
    printf "\n${RED}%d test(s) failed.${NC}\n" "$FAIL"
    exit 1
fi
