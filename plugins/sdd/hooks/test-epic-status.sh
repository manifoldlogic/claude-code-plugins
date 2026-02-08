#!/usr/bin/env bash
# test-epic-status.sh - Comprehensive test suite for epic-status.sh
#
# Tests the content-existence detection logic for epic status scanning:
# - Unit tests for check_file_substantive()
# - Unit tests for check_dir_has_md_files()
# - Integration tests for scan_epic() at various epic states
# - Edge case tests for graceful error handling
# - JSON validity tests using jq
# - Multi-epic scan tests
#
# Usage:
#   ./test-epic-status.sh           # Run all tests
#   ./test-epic-status.sh -v        # Verbose output
#   ./test-epic-status.sh --help    # Show help
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed

set -e  # Exit on first failure

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EPIC_STATUS_SCRIPT="$SCRIPT_DIR/../skills/project-workflow/scripts/epic-status.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Temp directory
TEST_DIR=""

# Verbose mode
VERBOSE=false

# Colors for output (if terminal supports it)
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    GREEN=''
    RED=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# ============================================================================
# Helper Functions
# ============================================================================

usage() {
    echo "Usage: $0 [-v|--verbose] [--help]"
    echo ""
    echo "Options:"
    echo "  -v, --verbose  Show detailed output for each test"
    echo "  --help         Show this help message"
    exit 0
}

# Parse command line arguments
while [ $# -gt 0 ]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Setup test environment
setup() {
    TEST_DIR=$(mktemp -d)
    if [ "$VERBOSE" = true ]; then
        echo "Created temp directory: $TEST_DIR"
    fi
}

# Cleanup test environment
cleanup() {
    if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
        if [ "$VERBOSE" = true ]; then
            echo "Cleaned up temp directory: $TEST_DIR"
        fi
    fi
}
trap cleanup EXIT

# Assert helper: check exit code
assert_exit() {
    local test_name="$1"
    local actual_exit="$2"
    local expected_exit="$3"
    local extra_info="${4:-}"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "  Test $TESTS_RUN: $test_name ... "

    if [ "$actual_exit" -eq "$expected_exit" ]; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC} (expected exit $expected_exit, got $actual_exit)"
        if [ -n "$extra_info" ] && [ "$VERBOSE" = true ]; then
            echo "    Detail: $extra_info"
        fi
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Assert helper: check string contains substring
assert_contains() {
    local test_name="$1"
    local haystack="$2"
    local needle="$3"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "  Test $TESTS_RUN: $test_name ... "

    if echo "$haystack" | grep -q "$needle"; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC} (output did not contain '$needle')"
        if [ "$VERBOSE" = true ]; then
            echo "    Actual: $haystack"
        fi
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Assert helper: check JSON is valid using jq
assert_valid_json() {
    local test_name="$1"
    local json_str="$2"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "  Test $TESTS_RUN: $test_name ... "

    if echo "$json_str" | jq . > /dev/null 2>&1; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC} (invalid JSON)"
        if [ "$VERBOSE" = true ]; then
            echo "    JSON: $json_str"
        fi
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Assert helper: check JSON field equals expected value
assert_json_field() {
    local test_name="$1"
    local json_str="$2"
    local jq_path="$3"
    local expected="$4"

    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "  Test $TESTS_RUN: $test_name ... "

    local actual
    actual=$(echo "$json_str" | jq -r "$jq_path" 2>/dev/null)

    if [ "$actual" = "$expected" ]; then
        echo -e "${GREEN}PASS${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}FAIL${NC} (expected '$expected', got '$actual')"
        if [ "$VERBOSE" = true ]; then
            echo "    JSON: $json_str"
        fi
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Create a scaffolded epic with template-size files (small, <500 bytes)
create_scaffolded_epic() {
    local name="$1"
    local sdd_root="$2"
    local epic_path="$sdd_root/epics/$name"
    mkdir -p "$epic_path/analysis"
    mkdir -p "$epic_path/decomposition/ticket-summaries"
    mkdir -p "$epic_path/reference"
    echo "# Research Synthesis" > "$epic_path/analysis/research-synthesis.md"
    echo "# Opportunity Map" > "$epic_path/analysis/opportunity-map.md"
    echo "# Domain Model" > "$epic_path/analysis/domain-model.md"
    echo "# Multi-Ticket Overview" > "$epic_path/decomposition/multi-ticket-overview.md"
    printf "# Epic\n\n## Status\n- [ ] Research\n- [ ] Analysis\n- [ ] Decomposition\n- [ ] Tickets Created\n" > "$epic_path/overview.md"
}

# Make a file substantive (>500 bytes)
make_substantive() {
    local file="$1"
    python3 -c "print('x' * 600)" >> "$file"
}

# ============================================================================
# Source the script for unit testing helper functions
# ============================================================================

# Verify the script exists
if [ ! -f "$EPIC_STATUS_SCRIPT" ]; then
    echo -e "${RED}ERROR: epic-status.sh not found at $EPIC_STATUS_SCRIPT${NC}"
    exit 1
fi

# Source the script to get access to helper functions.
# We eval everything except the final 'main "$@"' call to avoid execution.
eval "$(sed '/^main "\$@"$/d' "$EPIC_STATUS_SCRIPT")"

echo "============================================"
echo "epic-status.sh Test Suite"
echo "============================================"
echo ""

# ============================================================================
# UNIT TESTS: check_file_substantive()
# ============================================================================

echo -e "${BLUE}--- Unit Tests: check_file_substantive() ---${NC}"
echo ""

setup

# Test: File exists >500 bytes -> returns 0
big_file="$TEST_DIR/big_file.txt"
python3 -c "print('x' * 600)" > "$big_file"
set +e
check_file_substantive "$big_file"
exit_code=$?
set -e
assert_exit "File >500 bytes returns 0" "$exit_code" 0

# Test: File exists =500 bytes -> returns 1 (must be GREATER than threshold)
exact_file="$TEST_DIR/exact_file.txt"
python3 -c "import sys; sys.stdout.buffer.write(b'x' * 500)" > "$exact_file"
set +e
check_file_substantive "$exact_file"
exit_code=$?
set -e
assert_exit "File =500 bytes returns 1 (not greater)" "$exit_code" 1

# Test: File exists <500 bytes -> returns 1
small_file="$TEST_DIR/small_file.txt"
echo "small content" > "$small_file"
set +e
check_file_substantive "$small_file"
exit_code=$?
set -e
assert_exit "File <500 bytes returns 1" "$exit_code" 1

# Test: File exists 0 bytes -> returns 1
empty_file="$TEST_DIR/empty_file.txt"
touch "$empty_file"
set +e
check_file_substantive "$empty_file"
exit_code=$?
set -e
assert_exit "File 0 bytes returns 1" "$exit_code" 1

# Test: File does not exist -> returns 1
set +e
check_file_substantive "$TEST_DIR/nonexistent_file.txt"
exit_code=$?
set -e
assert_exit "Nonexistent file returns 1" "$exit_code" 1

# Test: Custom threshold parameter
threshold_file="$TEST_DIR/threshold_file.txt"
python3 -c "print('x' * 200)" > "$threshold_file"
set +e
check_file_substantive "$threshold_file" 100
exit_code=$?
set -e
assert_exit "File >custom threshold (100) returns 0" "$exit_code" 0

# Test: Custom threshold - file below custom threshold
set +e
check_file_substantive "$threshold_file" 1000
exit_code=$?
set -e
assert_exit "File <custom threshold (1000) returns 1" "$exit_code" 1

# Test: Path with spaces
spaced_dir="$TEST_DIR/path with spaces"
mkdir -p "$spaced_dir"
spaced_file="$spaced_dir/my file.txt"
python3 -c "print('x' * 600)" > "$spaced_file"
set +e
check_file_substantive "$spaced_file"
exit_code=$?
set -e
assert_exit "Path with spaces returns 0" "$exit_code" 0

cleanup

echo ""

# ============================================================================
# UNIT TESTS: check_dir_has_md_files()
# ============================================================================

echo -e "${BLUE}--- Unit Tests: check_dir_has_md_files() ---${NC}"
echo ""

setup

# Test: Directory with .md files -> returns 0
md_dir="$TEST_DIR/has_md"
mkdir -p "$md_dir"
echo "# test" > "$md_dir/file1.md"
echo "# test2" > "$md_dir/file2.md"
set +e
check_dir_has_md_files "$md_dir"
exit_code=$?
set -e
assert_exit "Directory with .md files returns 0" "$exit_code" 0

# Test: Empty directory -> returns 1
empty_dir="$TEST_DIR/empty_dir"
mkdir -p "$empty_dir"
set +e
check_dir_has_md_files "$empty_dir"
exit_code=$?
set -e
assert_exit "Empty directory returns 1" "$exit_code" 1

# Test: Directory with non-.md files only -> returns 1
nonmd_dir="$TEST_DIR/nonmd_dir"
mkdir -p "$nonmd_dir"
echo "data" > "$nonmd_dir/file.txt"
echo "data" > "$nonmd_dir/file.json"
echo "data" > "$nonmd_dir/file.py"
set +e
check_dir_has_md_files "$nonmd_dir"
exit_code=$?
set -e
assert_exit "Directory with non-.md files only returns 1" "$exit_code" 1

# Test: Directory does not exist -> returns 1
set +e
check_dir_has_md_files "$TEST_DIR/nonexistent_dir"
exit_code=$?
set -e
assert_exit "Nonexistent directory returns 1" "$exit_code" 1

# Test: Subdirectories with .md files (should not recurse) -> returns 1
norecurse_dir="$TEST_DIR/norecurse"
mkdir -p "$norecurse_dir/subdir"
echo "# nested" > "$norecurse_dir/subdir/nested.md"
set +e
check_dir_has_md_files "$norecurse_dir"
exit_code=$?
set -e
assert_exit "Subdirectory .md files not found (no recursion) returns 1" "$exit_code" 1

cleanup

echo ""

# ============================================================================
# INTEGRATION TESTS: scan_epic() via full script run
# ============================================================================

echo -e "${BLUE}--- Integration Tests: scan_epic() progression ---${NC}"
echo ""

# --- Test: Freshly scaffolded epic (0/4 progress) ---
setup
SDD_ROOT="$TEST_DIR/sdd"
mkdir -p "$SDD_ROOT/epics"
create_scaffolded_epic "test-epic-fresh" "$SDD_ROOT"

output=$(SDD_ROOT_DIR="$SDD_ROOT" bash "$EPIC_STATUS_SCRIPT" "test-epic-fresh" 2>/dev/null)
assert_valid_json "Freshly scaffolded epic produces valid JSON" "$output"
assert_json_field "Freshly scaffolded epic progress is 0/4" "$output" ".epics[0].progress" "0/4"
assert_json_field "Freshly scaffolded epic research_complete is false" "$output" ".epics[0].checkboxes.research_complete" "false"
assert_json_field "Freshly scaffolded epic analysis_complete is false" "$output" ".epics[0].checkboxes.analysis_complete" "false"
assert_json_field "Freshly scaffolded epic decomposition_complete is false" "$output" ".epics[0].checkboxes.decomposition_complete" "false"
assert_json_field "Freshly scaffolded epic tickets_created is false" "$output" ".epics[0].checkboxes.tickets_created" "false"
cleanup

# --- Test: Research-only epic (1/4 progress) ---
setup
SDD_ROOT="$TEST_DIR/sdd"
mkdir -p "$SDD_ROOT/epics"
create_scaffolded_epic "test-epic-research" "$SDD_ROOT"
make_substantive "$SDD_ROOT/epics/test-epic-research/analysis/research-synthesis.md"

output=$(SDD_ROOT_DIR="$SDD_ROOT" bash "$EPIC_STATUS_SCRIPT" "test-epic-research" 2>/dev/null)
assert_valid_json "Research-only epic produces valid JSON" "$output"
assert_json_field "Research-only epic progress is 1/4" "$output" ".epics[0].progress" "1/4"
assert_json_field "Research-only epic research_complete is true" "$output" ".epics[0].checkboxes.research_complete" "true"
assert_json_field "Research-only epic analysis_complete is false" "$output" ".epics[0].checkboxes.analysis_complete" "false"
cleanup

# --- Test: Research + analysis epic (2/4 progress) ---
setup
SDD_ROOT="$TEST_DIR/sdd"
mkdir -p "$SDD_ROOT/epics"
create_scaffolded_epic "test-epic-analysis" "$SDD_ROOT"
make_substantive "$SDD_ROOT/epics/test-epic-analysis/analysis/research-synthesis.md"
make_substantive "$SDD_ROOT/epics/test-epic-analysis/analysis/opportunity-map.md"
make_substantive "$SDD_ROOT/epics/test-epic-analysis/analysis/domain-model.md"

output=$(SDD_ROOT_DIR="$SDD_ROOT" bash "$EPIC_STATUS_SCRIPT" "test-epic-analysis" 2>/dev/null)
assert_valid_json "Research+analysis epic produces valid JSON" "$output"
assert_json_field "Research+analysis epic progress is 2/4" "$output" ".epics[0].progress" "2/4"
assert_json_field "Research+analysis epic research_complete is true" "$output" ".epics[0].checkboxes.research_complete" "true"
assert_json_field "Research+analysis epic analysis_complete is true" "$output" ".epics[0].checkboxes.analysis_complete" "true"
assert_json_field "Research+analysis epic decomposition_complete is false" "$output" ".epics[0].checkboxes.decomposition_complete" "false"
cleanup

# --- Test: Decomposition without summaries (2/4 progress) ---
setup
SDD_ROOT="$TEST_DIR/sdd"
mkdir -p "$SDD_ROOT/epics"
create_scaffolded_epic "test-epic-decomp-nosummary" "$SDD_ROOT"
make_substantive "$SDD_ROOT/epics/test-epic-decomp-nosummary/analysis/research-synthesis.md"
make_substantive "$SDD_ROOT/epics/test-epic-decomp-nosummary/analysis/opportunity-map.md"
make_substantive "$SDD_ROOT/epics/test-epic-decomp-nosummary/analysis/domain-model.md"
make_substantive "$SDD_ROOT/epics/test-epic-decomp-nosummary/decomposition/multi-ticket-overview.md"
# No ticket summaries -> decomposition_complete=false, tickets_created=false

output=$(SDD_ROOT_DIR="$SDD_ROOT" bash "$EPIC_STATUS_SCRIPT" "test-epic-decomp-nosummary" 2>/dev/null)
assert_valid_json "Decomposition without summaries produces valid JSON" "$output"
assert_json_field "Decomposition without summaries progress is 2/4" "$output" ".epics[0].progress" "2/4"
assert_json_field "Decomposition without summaries decomposition_complete is false" "$output" ".epics[0].checkboxes.decomposition_complete" "false"
assert_json_field "Decomposition without summaries tickets_created is false" "$output" ".epics[0].checkboxes.tickets_created" "false"
cleanup

# --- Test: Decomposition with summaries (3/4 progress) ---
# Note: tickets_created and decomposition_complete both require ticket-summaries .md files.
# decomposition_complete ALSO requires substantive multi-ticket-overview.md.
# If we have analysis not done but decomposition done, that's 1 (research) + 0 (analysis) + 1 (decomp) + 1 (tickets) = 3
# Actually: research + analysis + decomposition with summaries = 3 is the right combo
# Let's set: research=true, analysis=true, decomposition=true (overview + summaries), tickets_created=false
# Wait: tickets_created checks ticket-summaries has .md files, same as decomposition.
# So decomposition_complete=true implies tickets_created=true. They're coupled.
# decomposition=true means multi-ticket-overview substantive AND ticket-summaries has .md = true
# tickets_created=true means ticket-summaries has .md = true
# So if decomp=true, then tickets=true always (progress would be 3 or 4 with decomp).
# To get 3/4: research + analysis + decomp + tickets minus one. Since decomp implies tickets:
# 3/4 = research(true) + analysis(true) + decomp(false) + tickets(true) or similar.
# Actually let's re-check: decomp requires (substantive overview AND summaries), tickets requires just summaries
# So: summaries present, overview NOT substantive -> decomp=false, tickets=true
# That with research + analysis = 2 + 0 + 1 = 3/4
setup
SDD_ROOT="$TEST_DIR/sdd"
mkdir -p "$SDD_ROOT/epics"
create_scaffolded_epic "test-epic-3of4" "$SDD_ROOT"
make_substantive "$SDD_ROOT/epics/test-epic-3of4/analysis/research-synthesis.md"
make_substantive "$SDD_ROOT/epics/test-epic-3of4/analysis/opportunity-map.md"
make_substantive "$SDD_ROOT/epics/test-epic-3of4/analysis/domain-model.md"
# multi-ticket-overview remains small (not substantive) -> decomposition_complete=false
# Add ticket summary .md files -> tickets_created=true
echo "# Ticket Summary TKT-001" > "$SDD_ROOT/epics/test-epic-3of4/decomposition/ticket-summaries/TKT-001.md"

output=$(SDD_ROOT_DIR="$SDD_ROOT" bash "$EPIC_STATUS_SCRIPT" "test-epic-3of4" 2>/dev/null)
assert_valid_json "3/4 progress epic produces valid JSON" "$output"
assert_json_field "3/4 progress: research_complete is true" "$output" ".epics[0].checkboxes.research_complete" "true"
assert_json_field "3/4 progress: analysis_complete is true" "$output" ".epics[0].checkboxes.analysis_complete" "true"
assert_json_field "3/4 progress: decomposition_complete is false" "$output" ".epics[0].checkboxes.decomposition_complete" "false"
assert_json_field "3/4 progress: tickets_created is true" "$output" ".epics[0].checkboxes.tickets_created" "true"
assert_json_field "3/4 progress epic progress is 3/4" "$output" ".epics[0].progress" "3/4"
cleanup

# --- Test: Fully complete epic (4/4 progress) ---
setup
SDD_ROOT="$TEST_DIR/sdd"
mkdir -p "$SDD_ROOT/epics"
create_scaffolded_epic "test-epic-complete" "$SDD_ROOT"
make_substantive "$SDD_ROOT/epics/test-epic-complete/analysis/research-synthesis.md"
make_substantive "$SDD_ROOT/epics/test-epic-complete/analysis/opportunity-map.md"
make_substantive "$SDD_ROOT/epics/test-epic-complete/analysis/domain-model.md"
make_substantive "$SDD_ROOT/epics/test-epic-complete/decomposition/multi-ticket-overview.md"
echo "# Ticket Summary TKT-001" > "$SDD_ROOT/epics/test-epic-complete/decomposition/ticket-summaries/TKT-001.md"
echo "# Ticket Summary TKT-002" > "$SDD_ROOT/epics/test-epic-complete/decomposition/ticket-summaries/TKT-002.md"

output=$(SDD_ROOT_DIR="$SDD_ROOT" bash "$EPIC_STATUS_SCRIPT" "test-epic-complete" 2>/dev/null)
assert_valid_json "Fully complete epic produces valid JSON" "$output"
assert_json_field "Fully complete epic progress is 4/4" "$output" ".epics[0].progress" "4/4"
assert_json_field "Fully complete epic research_complete is true" "$output" ".epics[0].checkboxes.research_complete" "true"
assert_json_field "Fully complete epic analysis_complete is true" "$output" ".epics[0].checkboxes.analysis_complete" "true"
assert_json_field "Fully complete epic decomposition_complete is true" "$output" ".epics[0].checkboxes.decomposition_complete" "true"
assert_json_field "Fully complete epic tickets_created is true" "$output" ".epics[0].checkboxes.tickets_created" "true"
cleanup

echo ""

# ============================================================================
# EDGE CASE TESTS
# ============================================================================

echo -e "${BLUE}--- Edge Case Tests ---${NC}"
echo ""

# --- Test: Missing overview.md -> warning to stderr, return 1 ---
setup
SDD_ROOT="$TEST_DIR/sdd"
mkdir -p "$SDD_ROOT/epics/test-epic-no-overview/analysis"
# No overview.md created

stderr_output=$(SDD_ROOT_DIR="$SDD_ROOT" bash "$EPIC_STATUS_SCRIPT" "test-epic-no-overview" 2>&1 1>/dev/null)
set +e
# The script continues but scan_epic returns 1; main catches it with || true
# Check that warning appears in stderr
echo "$stderr_output" | grep -q "Warning.*overview.md"
found_warning=$?
set -e
assert_exit "Missing overview.md produces warning on stderr" "$found_warning" 0

cleanup

# --- Test: Missing analysis directory -> graceful handling ---
setup
SDD_ROOT="$TEST_DIR/sdd"
mkdir -p "$SDD_ROOT/epics/test-epic-no-analysis"
printf "# Epic\n\n## Status\n" > "$SDD_ROOT/epics/test-epic-no-analysis/overview.md"
# No analysis directory

output=$(SDD_ROOT_DIR="$SDD_ROOT" bash "$EPIC_STATUS_SCRIPT" "test-epic-no-analysis" 2>/dev/null)
assert_valid_json "Missing analysis directory produces valid JSON" "$output"
assert_json_field "Missing analysis directory: research_complete is false" "$output" ".epics[0].checkboxes.research_complete" "false"
assert_json_field "Missing analysis directory: analysis_complete is false" "$output" ".epics[0].checkboxes.analysis_complete" "false"
cleanup

# --- Test: Missing decomposition directory -> graceful handling ---
setup
SDD_ROOT="$TEST_DIR/sdd"
mkdir -p "$SDD_ROOT/epics/test-epic-no-decomp/analysis"
printf "# Epic\n\n## Status\n" > "$SDD_ROOT/epics/test-epic-no-decomp/overview.md"
echo "# Research" > "$SDD_ROOT/epics/test-epic-no-decomp/analysis/research-synthesis.md"
# No decomposition directory

output=$(SDD_ROOT_DIR="$SDD_ROOT" bash "$EPIC_STATUS_SCRIPT" "test-epic-no-decomp" 2>/dev/null)
assert_valid_json "Missing decomposition directory produces valid JSON" "$output"
assert_json_field "Missing decomposition directory: decomposition_complete is false" "$output" ".epics[0].checkboxes.decomposition_complete" "false"
assert_json_field "Missing decomposition directory: tickets_created is false" "$output" ".epics[0].checkboxes.tickets_created" "false"
cleanup

# --- Test: Missing epics directory entirely ---
setup
SDD_ROOT="$TEST_DIR/sdd_empty"
# Don't create epics directory at all

output=$(SDD_ROOT_DIR="$SDD_ROOT" bash "$EPIC_STATUS_SCRIPT" 2>/dev/null)
assert_valid_json "Missing epics directory produces valid JSON" "$output"
cleanup

echo ""

# ============================================================================
# JSON VALIDITY TESTS
# ============================================================================

echo -e "${BLUE}--- JSON Validity Tests ---${NC}"
echo ""

# Test: All integration outputs already validated above with assert_valid_json.
# Additional test: scan all epics (no argument) produces valid JSON

setup
SDD_ROOT="$TEST_DIR/sdd"
mkdir -p "$SDD_ROOT/epics"
create_scaffolded_epic "epic-json-a" "$SDD_ROOT"
create_scaffolded_epic "epic-json-b" "$SDD_ROOT"
make_substantive "$SDD_ROOT/epics/epic-json-b/analysis/research-synthesis.md"

output=$(SDD_ROOT_DIR="$SDD_ROOT" bash "$EPIC_STATUS_SCRIPT" 2>/dev/null)
assert_valid_json "Multi-epic scan-all produces valid JSON" "$output"

# Verify the epics array has entries
epic_count=$(echo "$output" | jq '.epics | length' 2>/dev/null)
TESTS_RUN=$((TESTS_RUN + 1))
echo -n "  Test $TESTS_RUN: Multi-epic scan-all contains epics array ... "
if [ "$epic_count" -ge 2 ] 2>/dev/null; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC} (expected >= 2 epics, got $epic_count)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Verify timestamp field exists
TESTS_RUN=$((TESTS_RUN + 1))
echo -n "  Test $TESTS_RUN: JSON output has timestamp field ... "
has_timestamp=$(echo "$output" | jq 'has("timestamp")' 2>/dev/null)
if [ "$has_timestamp" = "true" ]; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC} (missing timestamp field)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

cleanup

echo ""

# ============================================================================
# MULTI-EPIC SCAN TESTS
# ============================================================================

echo -e "${BLUE}--- Multi-Epic Scan Tests ---${NC}"
echo ""

setup
SDD_ROOT="$TEST_DIR/sdd"
mkdir -p "$SDD_ROOT/epics"

# Epic 1: freshly scaffolded (0/4)
create_scaffolded_epic "multi-epic-fresh" "$SDD_ROOT"

# Epic 2: research only (1/4)
create_scaffolded_epic "multi-epic-research" "$SDD_ROOT"
make_substantive "$SDD_ROOT/epics/multi-epic-research/analysis/research-synthesis.md"

# Epic 3: fully complete (4/4)
create_scaffolded_epic "multi-epic-complete" "$SDD_ROOT"
make_substantive "$SDD_ROOT/epics/multi-epic-complete/analysis/research-synthesis.md"
make_substantive "$SDD_ROOT/epics/multi-epic-complete/analysis/opportunity-map.md"
make_substantive "$SDD_ROOT/epics/multi-epic-complete/analysis/domain-model.md"
make_substantive "$SDD_ROOT/epics/multi-epic-complete/decomposition/multi-ticket-overview.md"
echo "# TKT-001" > "$SDD_ROOT/epics/multi-epic-complete/decomposition/ticket-summaries/TKT-001.md"

# Run scan-all
output=$(SDD_ROOT_DIR="$SDD_ROOT" bash "$EPIC_STATUS_SCRIPT" 2>/dev/null)
assert_valid_json "Multi-epic scan with 3 epics produces valid JSON" "$output"

# Verify count
epic_count=$(echo "$output" | jq '.epics | length' 2>/dev/null)
TESTS_RUN=$((TESTS_RUN + 1))
echo -n "  Test $TESTS_RUN: Multi-epic scan returns 3 epics ... "
if [ "$epic_count" -eq 3 ]; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC} (expected 3, got $epic_count)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Check each epic has the expected progress by name
# Epic names come from directory names, sorted alphabetically by filesystem iteration
# We use jq to find by name

fresh_progress=$(echo "$output" | jq -r '.epics[] | select(.name == "multi-epic-fresh") | .progress' 2>/dev/null)
assert_exit "Multi-epic: fresh epic has 0/4 progress" "$([ "$fresh_progress" = "0/4" ] && echo 0 || echo 1)" 0

research_progress=$(echo "$output" | jq -r '.epics[] | select(.name == "multi-epic-research") | .progress' 2>/dev/null)
assert_exit "Multi-epic: research epic has 1/4 progress" "$([ "$research_progress" = "1/4" ] && echo 0 || echo 1)" 0

complete_progress=$(echo "$output" | jq -r '.epics[] | select(.name == "multi-epic-complete") | .progress' 2>/dev/null)
assert_exit "Multi-epic: complete epic has 4/4 progress" "$([ "$complete_progress" = "4/4" ] && echo 0 || echo 1)" 0

# Verify each epic has correct checkbox structure
TESTS_RUN=$((TESTS_RUN + 1))
echo -n "  Test $TESTS_RUN: Multi-epic: all epics have checkboxes object ... "
checkbox_count=$(echo "$output" | jq '[.epics[] | .checkboxes] | length' 2>/dev/null)
if [ "$checkbox_count" -eq 3 ]; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    echo -e "${RED}FAIL${NC} (expected 3 checkbox objects, got $checkbox_count)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

cleanup

echo ""

# ============================================================================
# Test Results Summary
# ============================================================================

echo "============================================"
echo "Test Results"
echo "============================================"
echo ""
echo "Tests run:    $TESTS_RUN"
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo ""

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "${GREEN}All $TESTS_PASSED tests PASSED${NC}"
    exit 0
else
    echo -e "${RED}$TESTS_FAILED test(s) FAILED${NC}"
    exit 1
fi
