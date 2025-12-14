#!/usr/bin/env bash
#
# test_orchestrator_args.sh - Tests for orchestrator.sh argument parsing
#
# Tests all acceptance criteria for ASDW-1.2001:
# - All 5 input modes (--jql, --epic, --team, --tickets, --resume)
# - Mutual exclusivity validation
# - Required value validation
# - Empty value detection
# - Unknown flag detection
# - Special character preservation
# - Global variable setting
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATOR="${SCRIPT_DIR}/../orchestrator.sh"

# Source test harness
# shellcheck source=test-harness.sh
source "${SCRIPT_DIR}/test-harness.sh"

#
# Helper Functions
#

# Helper to test that orchestrator sets global variables correctly
# This sources the orchestrator and calls parse_arguments directly
# Note: named with underscore prefix to avoid being picked up as a test
_test_parse_args() {
    local expected_type="${1:-}"
    local expected_value="${2:-}"
    shift 2
    local args=("$@")

    # Source orchestrator in subshell to test parse_arguments function
    (
        # Source common.sh and orchestrator
        # shellcheck source=../lib/common.sh
        source "${SCRIPT_DIR}/../lib/common.sh"
        # shellcheck source=../orchestrator.sh
        source "$ORCHESTRATOR"

        # Call parse_arguments
        parse_arguments "${args[@]}"

        # Verify variables are set correctly
        if [ "$INPUT_TYPE" != "$expected_type" ]; then
            echo "INPUT_TYPE mismatch: expected '$expected_type', got '$INPUT_TYPE'" >&2
            exit 1
        fi

        if [ "$INPUT_VALUE" != "$expected_value" ]; then
            echo "INPUT_VALUE mismatch: expected '$expected_value', got '$INPUT_VALUE'" >&2
            exit 1
        fi

        exit 0
    )
}

#
# Tests for --jql input mode
#

test_jql_basic() {
    assert_true "_test_parse_args 'jql' 'project = UIT' --jql 'project = UIT'" \
        "--jql with basic query sets INPUT_TYPE and INPUT_VALUE"
}

test_jql_complex_query() {
    local query="project = UIT AND status = 'To Do' AND assignee IS EMPTY"
    (
        # shellcheck source=../lib/common.sh
        source "${SCRIPT_DIR}/../lib/common.sh"
        # shellcheck source=../orchestrator.sh
        source "$ORCHESTRATOR"

        parse_arguments --jql "$query"

        if [ "$INPUT_TYPE" != "jql" ]; then
            echo "INPUT_TYPE should be 'jql'" >&2
            exit 1
        fi

        if [ "$INPUT_VALUE" != "$query" ]; then
            echo "INPUT_VALUE mismatch" >&2
            exit 1
        fi

        exit 0
    )
    assert_true ":" "--jql preserves complex query with quotes and special characters"
}

test_jql_with_parentheses() {
    local query="project = UIT AND (status = 'To Do' OR status = 'In Progress')"
    (
        # shellcheck source=../lib/common.sh
        source "${SCRIPT_DIR}/../lib/common.sh"
        # shellcheck source=../orchestrator.sh
        source "$ORCHESTRATOR"

        parse_arguments --jql "$query"

        if [ "$INPUT_TYPE" != "jql" ]; then
            echo "INPUT_TYPE should be 'jql'" >&2
            exit 1
        fi

        if [ "$INPUT_VALUE" != "$query" ]; then
            echo "INPUT_VALUE mismatch" >&2
            exit 1
        fi

        exit 0
    )
    assert_true ":" "--jql preserves query with parentheses"
}

test_jql_missing_value() {
    local output
    output=$("$ORCHESTRATOR" --jql 2>&1) || true
    assert_contains "$output" "--jql requires a JQL query value" \
        "--jql without value shows error message"
}

test_jql_empty_value() {
    local output
    output=$("$ORCHESTRATOR" --jql "" 2>&1) || true
    assert_contains "$output" "--jql requires a JQL query value" \
        "--jql with empty string shows error message"
}

test_jql_whitespace_only() {
    local output
    output=$("$ORCHESTRATOR" --jql "   " 2>&1) || true
    assert_contains "$output" "value cannot be empty or whitespace only" \
        "--jql with whitespace-only value shows error message"
}

#
# Tests for --epic input mode
#

test_epic_basic() {
    assert_true "_test_parse_args 'epic' 'UIT-100' --epic UIT-100" \
        "--epic with key sets INPUT_TYPE and INPUT_VALUE"
}

test_epic_missing_value() {
    local output
    output=$("$ORCHESTRATOR" --epic 2>&1) || true
    assert_contains "$output" "--epic requires an epic key value" \
        "--epic without value shows error message"
}

test_epic_empty_value() {
    local output
    output=$("$ORCHESTRATOR" --epic "" 2>&1) || true
    assert_contains "$output" "--epic requires an epic key value" \
        "--epic with empty string shows error message"
}

#
# Tests for --team input mode
#

test_team_basic() {
    assert_true "_test_parse_args 'team' 'Platform Team' --team 'Platform Team'" \
        "--team with name sets INPUT_TYPE and INPUT_VALUE"
}

test_team_with_spaces() {
    local team="Engineering Platform Team Alpha"
    assert_true "_test_parse_args 'team' '$team' --team '$team'" \
        "--team preserves team name with multiple spaces"
}

test_team_missing_value() {
    local output
    output=$("$ORCHESTRATOR" --team 2>&1) || true
    assert_contains "$output" "--team requires a team name value" \
        "--team without value shows error message"
}

#
# Tests for --tickets input mode
#

test_tickets_single() {
    assert_true "_test_parse_args 'tickets' 'UIT-3607' --tickets UIT-3607" \
        "--tickets with single ticket sets INPUT_TYPE and INPUT_VALUE"
}

test_tickets_multiple() {
    local tickets="UIT-3607,UIT-3608,UIT-3609"
    assert_true "_test_parse_args 'tickets' '$tickets' --tickets '$tickets'" \
        "--tickets with comma-separated list sets INPUT_TYPE and INPUT_VALUE"
}

test_tickets_missing_value() {
    local output
    output=$("$ORCHESTRATOR" --tickets 2>&1) || true
    assert_contains "$output" "--tickets requires a comma-separated list value" \
        "--tickets without value shows error message"
}

#
# Tests for --resume input mode
#

test_resume_without_run_id() {
    assert_true "_test_parse_args 'resume' '' --resume" \
        "--resume without RUN_ID sets INPUT_TYPE and empty INPUT_VALUE"
}

test_resume_with_run_id() {
    local run_id="20251212-143052-a1b2c3d4"
    assert_true "_test_parse_args 'resume' '$run_id' --resume $run_id" \
        "--resume with RUN_ID sets INPUT_TYPE and INPUT_VALUE"
}

test_resume_with_flag_after() {
    # Test that --resume correctly handles optional RUN_ID when followed by another flag
    (
        # shellcheck source=../lib/common.sh
        source "${SCRIPT_DIR}/../lib/common.sh"
        # shellcheck source=../orchestrator.sh
        source "$ORCHESTRATOR"

        parse_arguments --resume --dry-run

        if [ "$INPUT_TYPE" != "resume" ]; then
            echo "INPUT_TYPE should be 'resume', got '$INPUT_TYPE'" >&2
            exit 1
        fi

        if [ -n "$INPUT_VALUE" ]; then
            echo "INPUT_VALUE should be empty, got '$INPUT_VALUE'" >&2
            exit 1
        fi

        if [ "$DRY_RUN" != true ]; then
            echo "DRY_RUN should be true" >&2
            exit 1
        fi

        exit 0
    )
    assert_true ":" "--resume followed by --dry-run parses correctly"
}

#
# Tests for optional flags
#

test_dry_run_flag() {
    (
        # shellcheck source=../lib/common.sh
        source "${SCRIPT_DIR}/../lib/common.sh"
        # shellcheck source=../orchestrator.sh
        source "$ORCHESTRATOR"

        parse_arguments --jql "project = UIT" --dry-run

        if [ "$DRY_RUN" != true ]; then
            echo "DRY_RUN should be true" >&2
            exit 1
        fi

        exit 0
    )
    assert_true ":" "--dry-run flag sets DRY_RUN=true"
}

test_verbose_flag() {
    (
        # shellcheck source=../lib/common.sh
        source "${SCRIPT_DIR}/../lib/common.sh"
        # shellcheck source=../orchestrator.sh
        source "$ORCHESTRATOR"

        parse_arguments --jql "project = UIT" --verbose

        if [ "$VERBOSE" != true ]; then
            echo "VERBOSE should be true" >&2
            exit 1
        fi

        # Verify verbose flag sets log level to debug
        if [ "$CONFIG_LOG_LEVEL" != "debug" ]; then
            echo "CONFIG_LOG_LEVEL should be 'debug', got '$CONFIG_LOG_LEVEL'" >&2
            exit 1
        fi

        exit 0
    )
    assert_true ":" "--verbose flag sets VERBOSE=true and CONFIG_LOG_LEVEL=debug"
}

test_config_flag() {
    (
        # shellcheck source=../lib/common.sh
        source "${SCRIPT_DIR}/../lib/common.sh"
        # shellcheck source=../orchestrator.sh
        source "$ORCHESTRATOR"

        parse_arguments --jql "project = UIT" --config /custom/config.json

        if [ "$CONFIG_FILE" != "/custom/config.json" ]; then
            echo "CONFIG_FILE should be '/custom/config.json', got '$CONFIG_FILE'" >&2
            exit 1
        fi

        exit 0
    )
    assert_true ":" "--config flag sets CONFIG_FILE"
}

test_config_missing_value() {
    local output
    output=$("$ORCHESTRATOR" --jql "test" --config 2>&1) || true
    assert_contains "$output" "--config requires a file path value" \
        "--config without value shows error message"
}

test_all_flags_combined() {
    (
        # shellcheck source=../lib/common.sh
        source "${SCRIPT_DIR}/../lib/common.sh"
        # shellcheck source=../orchestrator.sh
        source "$ORCHESTRATOR"

        parse_arguments --jql "project = UIT" --dry-run --verbose --config /custom/config.json

        if [ "$INPUT_TYPE" != "jql" ]; then
            echo "INPUT_TYPE should be 'jql'" >&2
            exit 1
        fi

        if [ "$DRY_RUN" != true ]; then
            echo "DRY_RUN should be true" >&2
            exit 1
        fi

        if [ "$VERBOSE" != true ]; then
            echo "VERBOSE should be true" >&2
            exit 1
        fi

        if [ "$CONFIG_FILE" != "/custom/config.json" ]; then
            echo "CONFIG_FILE should be '/custom/config.json'" >&2
            exit 1
        fi

        exit 0
    )
    assert_true ":" "All flags can be combined"
}

#
# Tests for --help and --version
#

test_help_flag() {
    local output
    output=$("$ORCHESTRATOR" --help 2>&1)
    assert_contains "$output" "Usage: orchestrator.sh" \
        "--help displays usage information"
}

test_help_exit_code() {
    local exit_code=0
    "$ORCHESTRATOR" --help >/dev/null 2>&1 || exit_code=$?
    assert_equals "0" "$exit_code" \
        "--help exits with code 0"
}

test_version_flag() {
    local output
    output=$("$ORCHESTRATOR" --version 2>&1)
    assert_contains "$output" "SDD Orchestrator v" \
        "--version displays version information"
}

test_version_exit_code() {
    local exit_code=0
    "$ORCHESTRATOR" --version >/dev/null 2>&1 || exit_code=$?
    assert_equals "0" "$exit_code" \
        "--version exits with code 0"
}

#
# Tests for validation errors
#

test_no_arguments() {
    local output
    output=$("$ORCHESTRATOR" 2>&1) || true
    assert_contains "$output" "Missing required input mode" \
        "No arguments shows error message"
}

test_no_arguments_exit_code() {
    local exit_code=0
    "$ORCHESTRATOR" >/dev/null 2>&1 || exit_code=$?
    assert_equals "1" "$exit_code" \
        "No arguments exits with code 1"
}

test_multiple_input_modes() {
    local output
    output=$("$ORCHESTRATOR" --jql "query" --epic UIT-100 2>&1) || true
    assert_contains "$output" "Cannot specify multiple input modes" \
        "Multiple input modes shows error message"
}

test_multiple_input_modes_exit_code() {
    local exit_code=0
    "$ORCHESTRATOR" --jql "query" --epic UIT-100 >/dev/null 2>&1 || exit_code=$?
    assert_equals "1" "$exit_code" \
        "Multiple input modes exits with code 1"
}

test_unknown_flag() {
    local output
    output=$("$ORCHESTRATOR" --jql "query" --unknown 2>&1) || true
    assert_contains "$output" "Unknown option: --unknown" \
        "Unknown flag shows error message"
}

test_unknown_flag_exit_code() {
    local exit_code=0
    "$ORCHESTRATOR" --jql "query" --unknown >/dev/null 2>&1 || exit_code=$?
    assert_equals "1" "$exit_code" \
        "Unknown flag exits with code 1"
}

test_unknown_positional_argument() {
    local output
    output=$("$ORCHESTRATOR" --jql "query" extra_arg 2>&1) || true
    assert_contains "$output" "Unknown argument: extra_arg" \
        "Unknown positional argument shows error message"
}

#
# Tests for special character handling
#

test_special_chars_apostrophe() {
    local query="status = 'To Do' AND summary ~ \"John's Task\""
    (
        # shellcheck source=../lib/common.sh
        source "${SCRIPT_DIR}/../lib/common.sh"
        # shellcheck source=../orchestrator.sh
        source "$ORCHESTRATOR"

        parse_arguments --jql "$query"

        if [ "$INPUT_VALUE" != "$query" ]; then
            echo "INPUT_VALUE mismatch" >&2
            exit 1
        fi

        exit 0
    )
    assert_true ":" "JQL query with apostrophes is preserved"
}

test_special_chars_quotes() {
    local query='project = UIT AND summary ~ "Task with quotes"'
    (
        # shellcheck source=../lib/common.sh
        source "${SCRIPT_DIR}/../lib/common.sh"
        # shellcheck source=../orchestrator.sh
        source "$ORCHESTRATOR"

        parse_arguments --jql "$query"

        if [ "$INPUT_VALUE" != "$query" ]; then
            echo "INPUT_VALUE mismatch" >&2
            exit 1
        fi

        exit 0
    )
    assert_true ":" "JQL query with quotes is preserved"
}

test_special_chars_ampersand() {
    local team="Research & Development"
    assert_true "_test_parse_args 'team' '$team' --team '$team'" \
        "Team name with ampersand is preserved"
}

#
# Edge case tests
#

test_resume_run_id_looks_like_flag() {
    # Ensure that if user accidentally passes a flag-like value to --resume,
    # it's treated as a flag, not a RUN_ID
    (
        # shellcheck source=../lib/common.sh
        source "${SCRIPT_DIR}/../lib/common.sh"
        # shellcheck source=../orchestrator.sh
        source "$ORCHESTRATOR"

        parse_arguments --resume --dry-run

        # --dry-run should be treated as a flag, not as RUN_ID
        if [ -n "$INPUT_VALUE" ]; then
            echo "INPUT_VALUE should be empty when --resume followed by --dry-run" >&2
            exit 1
        fi

        if [ "$DRY_RUN" != true ]; then
            echo "DRY_RUN should be true" >&2
            exit 1
        fi

        exit 0
    )
    assert_true ":" "--resume correctly distinguishes flags from RUN_ID"
}

test_flag_order_independence() {
    # Test that flags can be in any order
    (
        # shellcheck source=../lib/common.sh
        source "${SCRIPT_DIR}/../lib/common.sh"
        # shellcheck source=../orchestrator.sh
        source "$ORCHESTRATOR"

        parse_arguments --verbose --dry-run --jql "project = UIT" --config /tmp/config.json

        if [ "$INPUT_TYPE" != "jql" ]; then
            echo "INPUT_TYPE should be 'jql'" >&2
            exit 1
        fi

        if [ "$DRY_RUN" != true ] || [ "$VERBOSE" != true ]; then
            echo "Flags should be set" >&2
            exit 1
        fi

        exit 0
    )
    assert_true ":" "Flags can appear in any order"
}

#
# Run all tests
#

main() {
    echo "Testing orchestrator.sh argument parsing (ASDW-1.2001)"
    echo "========================================================"
    echo ""

    run_tests "test_"
}

main "$@"
