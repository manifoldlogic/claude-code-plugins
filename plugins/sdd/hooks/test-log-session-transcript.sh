#!/usr/bin/env zsh
# Test runner for log-session-transcript.py hook
# Validates happy paths, error paths, and edge cases for session logging
#
# The hook always exits 0 (passive logging, never blocks).
# It writes JSON metadata files to ${SDD_ROOT_DIR}/logs/session-transcripts/
#
# Test cases:
#   1.  PreCompact happy path (valid data, all fields)
#   2.  SessionEnd happy path (valid data, reason field)
#   3.  Empty transcript_path (status: "empty_path")
#   4.  Missing SDD_ROOT_DIR (no file, exit 0)
#   5.  Malformed JSON (no file, exit 0)
#   6.  Empty stdin (no file, exit 0)
#   7.  Unwritable log directory (no file, exit 0)
#   8.  Session ID sanitization (path traversal stripped)
#   9.  Session ID truncation (>128 chars truncated)
#   10. Concurrent uniqueness (two rapid calls, two files)
#   11. JSON schema validation (field type checks)
#   12. Unknown hook event name (sanitization, status: unknown_event)
#
# Usage: ./test-log-session-transcript.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
HOOK_SCRIPT="${SCRIPT_DIR}/log-session-transcript.py"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0
TESTS_RUN=0

cleanup() {
  if [ -n "${TEST_DIR:-}" ] && [ -d "$TEST_DIR" ]; then
    chmod -R u+rwx "$TEST_DIR" 2>/dev/null || true
    rm -rf "$TEST_DIR"
  fi
}
trap cleanup EXIT

TEST_DIR=$(mktemp -d)

echo "============================================"
echo "log-session-transcript.py Hook Test Suite"
echo "============================================"
echo ""

# Verify hook exists
if [ ! -f "$HOOK_SCRIPT" ]; then
  printf "${RED}ERROR: Hook not found at %s${NC}\n" "$HOOK_SCRIPT"
  exit 1
fi

# Verify jq is available
if ! command -v jq >/dev/null 2>&1; then
  printf "${RED}ERROR: jq is required but not found${NC}\n"
  exit 1
fi

# Cross-platform stat for file permissions
get_file_perms() {
  local filepath="$1"
  if stat -c '%a' "$filepath" 2>/dev/null; then
    return
  fi
  # macOS fallback
  stat -f '%A' "$filepath" 2>/dev/null
}

# Count files in log directory
count_log_files() {
  local dir="$1/logs/session-transcripts"
  if [ -d "$dir" ]; then
    ls -1 "$dir" 2>/dev/null | wc -l | tr -d ' '
  else
    echo "0"
  fi
}

# Get log directory path
log_dir_path() {
  echo "$1/logs/session-transcripts"
}

# Get the single log file path (assumes exactly one file)
get_log_file() {
  local dir="$1/logs/session-transcripts"
  local file
  file=$(ls -1 "$dir" 2>/dev/null | head -1)
  if [ -n "$file" ]; then
    echo "$dir/$file"
  fi
}

# Helper function: Validate required fields exist in JSON file
# Usage: validate_json_fields "/path/to/file.json" "field1 field2 field3"
# Returns: 0 on success, 1 if any field is missing or null
validate_json_fields() {
    local json_file="$1"
    local fields="$2"

    if [ ! -f "$json_file" ]; then
        echo "FAIL: JSON file not found: $json_file"
        return 1
    fi

    for field in $fields; do
        local value
        value=$(jq -r ".$field" "$json_file")
        if [ "$value" = "null" ] || [ -z "$value" ]; then
            echo "FAIL: Missing or null field '$field' in $json_file"
            return 1
        fi
    done

    return 0
}

# ============================================================
# Test 1: PreCompact happy path
# ============================================================
echo "--- Happy Paths ---"
echo ""

TESTS_RUN=$((TESTS_RUN + 1))
echo "Test ${TESTS_RUN}: PreCompact event with valid transcript_path"

# Create a fresh SDD_ROOT_DIR for this test
T1_DIR="${TEST_DIR}/t1"
mkdir -p "$T1_DIR"

T1_JSON=$(cat <<'ENDJSON'
{
  "session_id": "test-session-001",
  "transcript_path": "/tmp/transcript-001.jsonl",
  "cwd": "/workspace/repos/my-project",
  "hook_event_name": "PreCompact",
  "trigger": "auto",
  "custom_instructions": "Follow coding standards"
}
ENDJSON
)

set +e
echo "$T1_JSON" | SDD_ROOT_DIR="$T1_DIR" python3 "$HOOK_SCRIPT"
T1_EXIT=$?
set -e

T1_COUNT=$(count_log_files "$T1_DIR")
T1_FILE=$(get_log_file "$T1_DIR")
T1_PASS=true

# Check exit code
if [ "$T1_EXIT" -ne 0 ]; then
  printf "  ${RED}FAIL: exit code %d, expected 0${NC}\n" "$T1_EXIT"
  T1_PASS=false
fi

# Check file was created
if [ "$T1_COUNT" -ne 1 ]; then
  printf "  ${RED}FAIL: expected 1 log file, found %s${NC}\n" "$T1_COUNT"
  T1_PASS=false
fi

if [ -n "$T1_FILE" ]; then
  # Check file is valid JSON
  if ! jq empty "$T1_FILE" 2>/dev/null; then
    printf "  ${RED}FAIL: log file is not valid JSON${NC}\n"
    T1_PASS=false
  fi

  # Check required fields
  if ! validate_json_fields "$T1_FILE" "session_id transcript_path cwd hook_event_name timestamp status trigger custom_instructions"; then
    T1_PASS=false
  fi

  # Check field values
  T1_STATUS=$(jq -r '.status' "$T1_FILE")
  if [ "$T1_STATUS" != "ok" ]; then
    printf "  ${RED}FAIL: status='%s', expected 'ok'${NC}\n" "$T1_STATUS"
    T1_PASS=false
  fi

  T1_TRIGGER=$(jq -r '.trigger' "$T1_FILE")
  if [ "$T1_TRIGGER" != "auto" ]; then
    printf "  ${RED}FAIL: trigger='%s', expected 'auto'${NC}\n" "$T1_TRIGGER"
    T1_PASS=false
  fi

  T1_INSTR=$(jq -r '.custom_instructions' "$T1_FILE")
  if [ "$T1_INSTR" != "Follow coding standards" ]; then
    printf "  ${RED}FAIL: custom_instructions mismatch${NC}\n"
    T1_PASS=false
  fi

  # Check file permissions
  T1_PERMS=$(get_file_perms "$T1_FILE")
  if [ "$T1_PERMS" != "600" ]; then
    printf "  ${RED}FAIL: permissions=%s, expected 600${NC}\n" "$T1_PERMS"
    T1_PASS=false
  fi

  # Check filename pattern: {session_id}_{event}_{timestamp}.json
  T1_BASENAME=$(basename "$T1_FILE")
  if ! echo "$T1_BASENAME" | grep -qE '^test-session-001_precompact_[0-9]{8}T[0-9]{12}\.json$'; then
    printf "  ${RED}FAIL: filename '%s' does not match expected pattern${NC}\n" "$T1_BASENAME"
    T1_PASS=false
  fi
else
  printf "  ${RED}FAIL: no log file found${NC}\n"
  T1_PASS=false
fi

if [ "$T1_PASS" = "true" ]; then
  printf "  ${GREEN}PASS${NC}\n"
  PASSED=$((PASSED + 1))
else
  FAILED=$((FAILED + 1))
fi

# ============================================================
# Test 2: SessionEnd happy path
# ============================================================
TESTS_RUN=$((TESTS_RUN + 1))
echo "Test ${TESTS_RUN}: SessionEnd event with valid transcript_path"

T2_DIR="${TEST_DIR}/t2"
mkdir -p "$T2_DIR"

T2_JSON=$(cat <<'ENDJSON'
{
  "session_id": "test-session-002",
  "transcript_path": "/tmp/transcript-002.jsonl",
  "cwd": "/workspace/repos/my-project",
  "hook_event_name": "SessionEnd",
  "reason": "user_exit"
}
ENDJSON
)

set +e
echo "$T2_JSON" | SDD_ROOT_DIR="$T2_DIR" python3 "$HOOK_SCRIPT"
T2_EXIT=$?
set -e

T2_COUNT=$(count_log_files "$T2_DIR")
T2_FILE=$(get_log_file "$T2_DIR")
T2_PASS=true

if [ "$T2_EXIT" -ne 0 ]; then
  printf "  ${RED}FAIL: exit code %d, expected 0${NC}\n" "$T2_EXIT"
  T2_PASS=false
fi

if [ "$T2_COUNT" -ne 1 ]; then
  printf "  ${RED}FAIL: expected 1 log file, found %s${NC}\n" "$T2_COUNT"
  T2_PASS=false
fi

if [ -n "$T2_FILE" ]; then
  # Check required fields exist and are not null/empty
  if ! validate_json_fields "$T2_FILE" "session_id transcript_path cwd hook_event_name timestamp status reason"; then
    T2_PASS=false
  fi

  # Check status value
  T2_STATUS=$(jq -r '.status' "$T2_FILE")
  if [ "$T2_STATUS" != "ok" ]; then
    printf "  ${RED}FAIL: status='%s', expected 'ok'${NC}\n" "$T2_STATUS"
    T2_PASS=false
  fi

  # Check reason field value (SessionEnd-specific)
  T2_REASON=$(jq -r '.reason' "$T2_FILE")
  if [ "$T2_REASON" != "user_exit" ]; then
    printf "  ${RED}FAIL: reason='%s', expected 'user_exit'${NC}\n" "$T2_REASON"
    T2_PASS=false
  fi

  # Check filename pattern
  T2_BASENAME=$(basename "$T2_FILE")
  if ! echo "$T2_BASENAME" | grep -qE '^test-session-002_sessionend_[0-9]{8}T[0-9]{12}\.json$'; then
    printf "  ${RED}FAIL: filename '%s' does not match expected pattern${NC}\n" "$T2_BASENAME"
    T2_PASS=false
  fi

  # Verify trigger/custom_instructions are NOT present (SessionEnd should not have them)
  if jq -e 'has("trigger")' "$T2_FILE" >/dev/null 2>&1; then
    printf "  ${YELLOW}WARN: SessionEnd has 'trigger' field (unexpected)${NC}\n"
  fi
else
  printf "  ${RED}FAIL: no log file found${NC}\n"
  T2_PASS=false
fi

if [ "$T2_PASS" = "true" ]; then
  printf "  ${GREEN}PASS${NC}\n"
  PASSED=$((PASSED + 1))
else
  FAILED=$((FAILED + 1))
fi

# ============================================================
# Test 3: Empty transcript_path
# ============================================================
echo ""
echo "--- Error Paths ---"
echo ""

TESTS_RUN=$((TESTS_RUN + 1))
echo "Test ${TESTS_RUN}: Empty transcript_path produces status 'empty_path'"

T3_DIR="${TEST_DIR}/t3"
mkdir -p "$T3_DIR"

T3_JSON=$(cat <<'ENDJSON'
{
  "session_id": "test-session-003",
  "transcript_path": "",
  "cwd": "/workspace/repos/my-project",
  "hook_event_name": "PreCompact",
  "trigger": "auto",
  "custom_instructions": ""
}
ENDJSON
)

set +e
echo "$T3_JSON" | SDD_ROOT_DIR="$T3_DIR" python3 "$HOOK_SCRIPT"
T3_EXIT=$?
set -e

T3_COUNT=$(count_log_files "$T3_DIR")
T3_FILE=$(get_log_file "$T3_DIR")
T3_PASS=true

if [ "$T3_EXIT" -ne 0 ]; then
  printf "  ${RED}FAIL: exit code %d, expected 0${NC}\n" "$T3_EXIT"
  T3_PASS=false
fi

if [ "$T3_COUNT" -ne 1 ]; then
  printf "  ${RED}FAIL: expected 1 log file, found %s${NC}\n" "$T3_COUNT"
  T3_PASS=false
fi

if [ -n "$T3_FILE" ]; then
  T3_STATUS=$(jq -r '.status' "$T3_FILE")
  if [ "$T3_STATUS" != "empty_path" ]; then
    printf "  ${RED}FAIL: status='%s', expected 'empty_path'${NC}\n" "$T3_STATUS"
    T3_PASS=false
  fi
else
  printf "  ${RED}FAIL: no log file found${NC}\n"
  T3_PASS=false
fi

if [ "$T3_PASS" = "true" ]; then
  printf "  ${GREEN}PASS${NC}\n"
  PASSED=$((PASSED + 1))
else
  FAILED=$((FAILED + 1))
fi

# ============================================================
# Test 4: Missing SDD_ROOT_DIR
# ============================================================
TESTS_RUN=$((TESTS_RUN + 1))
echo "Test ${TESTS_RUN}: Missing SDD_ROOT_DIR exits 0 and writes nothing"

T4_DIR="${TEST_DIR}/t4"
mkdir -p "$T4_DIR"

T4_JSON=$(cat <<'ENDJSON'
{
  "session_id": "test-session-004",
  "transcript_path": "/tmp/transcript-004.jsonl",
  "cwd": "/workspace/repos/my-project",
  "hook_event_name": "PreCompact",
  "trigger": "auto",
  "custom_instructions": ""
}
ENDJSON
)

set +e
echo "$T4_JSON" | SDD_ROOT_DIR="" python3 "$HOOK_SCRIPT"
T4_EXIT=$?
set -e

# Check no log directory was created
T4_PASS=true
if [ "$T4_EXIT" -ne 0 ]; then
  printf "  ${RED}FAIL: exit code %d, expected 0${NC}\n" "$T4_EXIT"
  T4_PASS=false
fi

if [ -d "$T4_DIR/logs/session-transcripts" ]; then
  T4_COUNT=$(count_log_files "$T4_DIR")
  if [ "$T4_COUNT" -ne 0 ]; then
    printf "  ${RED}FAIL: expected 0 log files, found %s${NC}\n" "$T4_COUNT"
    T4_PASS=false
  fi
fi

if [ "$T4_PASS" = "true" ]; then
  printf "  ${GREEN}PASS${NC}\n"
  PASSED=$((PASSED + 1))
else
  FAILED=$((FAILED + 1))
fi

# ============================================================
# Test 5: Malformed JSON
# ============================================================
TESTS_RUN=$((TESTS_RUN + 1))
echo "Test ${TESTS_RUN}: Malformed JSON on stdin exits 0 and writes nothing"

T5_DIR="${TEST_DIR}/t5"
mkdir -p "$T5_DIR"

set +e
echo "this is not valid JSON" | SDD_ROOT_DIR="$T5_DIR" python3 "$HOOK_SCRIPT"
T5_EXIT=$?
set -e

T5_PASS=true
if [ "$T5_EXIT" -ne 0 ]; then
  printf "  ${RED}FAIL: exit code %d, expected 0${NC}\n" "$T5_EXIT"
  T5_PASS=false
fi

T5_COUNT=$(count_log_files "$T5_DIR")
if [ "$T5_COUNT" -ne 0 ]; then
  printf "  ${RED}FAIL: expected 0 log files, found %s${NC}\n" "$T5_COUNT"
  T5_PASS=false
fi

if [ "$T5_PASS" = "true" ]; then
  printf "  ${GREEN}PASS${NC}\n"
  PASSED=$((PASSED + 1))
else
  FAILED=$((FAILED + 1))
fi

# ============================================================
# Test 6: Empty stdin
# ============================================================
TESTS_RUN=$((TESTS_RUN + 1))
echo "Test ${TESTS_RUN}: Empty stdin exits 0 and writes nothing"

T6_DIR="${TEST_DIR}/t6"
mkdir -p "$T6_DIR"

set +e
SDD_ROOT_DIR="$T6_DIR" python3 "$HOOK_SCRIPT" </dev/null
T6_EXIT=$?
set -e

T6_PASS=true
if [ "$T6_EXIT" -ne 0 ]; then
  printf "  ${RED}FAIL: exit code %d, expected 0${NC}\n" "$T6_EXIT"
  T6_PASS=false
fi

T6_COUNT=$(count_log_files "$T6_DIR")
if [ "$T6_COUNT" -ne 0 ]; then
  printf "  ${RED}FAIL: expected 0 log files, found %s${NC}\n" "$T6_COUNT"
  T6_PASS=false
fi

if [ "$T6_PASS" = "true" ]; then
  printf "  ${GREEN}PASS${NC}\n"
  PASSED=$((PASSED + 1))
else
  FAILED=$((FAILED + 1))
fi

# ============================================================
# Test 7: Unwritable log directory
# ============================================================
TESTS_RUN=$((TESTS_RUN + 1))
echo "Test ${TESTS_RUN}: Unwritable log directory exits 0 and writes nothing"

T7_DIR="${TEST_DIR}/t7"
mkdir -p "$T7_DIR/logs/session-transcripts"
chmod 000 "$T7_DIR/logs/session-transcripts"

T7_JSON=$(cat <<'ENDJSON'
{
  "session_id": "test-session-007",
  "transcript_path": "/tmp/transcript-007.jsonl",
  "cwd": "/workspace/repos/my-project",
  "hook_event_name": "PreCompact",
  "trigger": "auto",
  "custom_instructions": ""
}
ENDJSON
)

set +e
echo "$T7_JSON" | SDD_ROOT_DIR="$T7_DIR" python3 "$HOOK_SCRIPT"
T7_EXIT=$?
set -e

T7_PASS=true
if [ "$T7_EXIT" -ne 0 ]; then
  printf "  ${RED}FAIL: exit code %d, expected 0${NC}\n" "$T7_EXIT"
  T7_PASS=false
fi

# Restore permissions for cleanup
chmod 755 "$T7_DIR/logs/session-transcripts"

T7_COUNT=$(count_log_files "$T7_DIR")
if [ "$T7_COUNT" -ne 0 ]; then
  printf "  ${RED}FAIL: expected 0 log files, found %s${NC}\n" "$T7_COUNT"
  T7_PASS=false
fi

if [ "$T7_PASS" = "true" ]; then
  printf "  ${GREEN}PASS${NC}\n"
  PASSED=$((PASSED + 1))
else
  FAILED=$((FAILED + 1))
fi

# ============================================================
# Test 8: Session ID sanitization (path traversal)
# ============================================================
echo ""
echo "--- Edge Cases ---"
echo ""

TESTS_RUN=$((TESTS_RUN + 1))
echo "Test ${TESTS_RUN}: Session ID sanitization strips path traversal characters"

T8_DIR="${TEST_DIR}/t8"
mkdir -p "$T8_DIR"

T8_JSON=$(cat <<'ENDJSON'
{
  "session_id": "../../etc/passwd",
  "transcript_path": "/tmp/transcript-008.jsonl",
  "cwd": "/workspace/repos/my-project",
  "hook_event_name": "PreCompact",
  "trigger": "auto",
  "custom_instructions": ""
}
ENDJSON
)

set +e
echo "$T8_JSON" | SDD_ROOT_DIR="$T8_DIR" python3 "$HOOK_SCRIPT"
T8_EXIT=$?
set -e

T8_COUNT=$(count_log_files "$T8_DIR")
T8_PASS=true

if [ "$T8_EXIT" -ne 0 ]; then
  printf "  ${RED}FAIL: exit code %d, expected 0${NC}\n" "$T8_EXIT"
  T8_PASS=false
fi

if [ "$T8_COUNT" -ne 1 ]; then
  printf "  ${RED}FAIL: expected 1 log file, found %s${NC}\n" "$T8_COUNT"
  T8_PASS=false
fi

# Verify file was created in the correct directory (not traversed)
T8_LOG_DIR=$(log_dir_path "$T8_DIR")
if [ -d "$T8_LOG_DIR" ]; then
  # Check that filenames do not contain dangerous characters
  T8_FILENAMES=$(ls -1 "$T8_LOG_DIR" 2>/dev/null)
  if echo "$T8_FILENAMES" | grep -q '\.\.'; then
    printf "  ${RED}FAIL: filename contains '..' path traversal${NC}\n"
    T8_PASS=false
  fi
  if echo "$T8_FILENAMES" | grep -q '/'; then
    printf "  ${RED}FAIL: filename contains '/' characters${NC}\n"
    T8_PASS=false
  fi
  # Verify no files were written outside the log directory
  if [ -f "$T8_DIR/../../etc/passwd" ] || [ -f "/etc/passwd_PreCompact" ]; then
    printf "  ${RED}FAIL: path traversal succeeded - file written outside log dir${NC}\n"
    T8_PASS=false
  fi
else
  printf "  ${RED}FAIL: log directory not created${NC}\n"
  T8_PASS=false
fi

if [ "$T8_PASS" = "true" ]; then
  printf "  ${GREEN}PASS${NC}\n"
  PASSED=$((PASSED + 1))
else
  FAILED=$((FAILED + 1))
fi

# ============================================================
# Test 9: Session ID truncation (>128 chars)
# ============================================================
TESTS_RUN=$((TESTS_RUN + 1))
echo "Test ${TESTS_RUN}: Session ID truncation to 128 chars max"

T9_DIR="${TEST_DIR}/t9"
mkdir -p "$T9_DIR"

# Generate a 200-character session ID
T9_LONG_ID="abcdefghij"
# Repeat to get 200 chars (10 chars * 20 repetitions)
T9_LONG_ID="${T9_LONG_ID}${T9_LONG_ID}${T9_LONG_ID}${T9_LONG_ID}${T9_LONG_ID}"
T9_LONG_ID="${T9_LONG_ID}${T9_LONG_ID}${T9_LONG_ID}${T9_LONG_ID}"
# T9_LONG_ID is now 200 chars

T9_JSON="{
  \"session_id\": \"${T9_LONG_ID}\",
  \"transcript_path\": \"/tmp/transcript-009.jsonl\",
  \"cwd\": \"/workspace/repos/my-project\",
  \"hook_event_name\": \"PreCompact\",
  \"trigger\": \"auto\",
  \"custom_instructions\": \"\"
}"

set +e
echo "$T9_JSON" | SDD_ROOT_DIR="$T9_DIR" python3 "$HOOK_SCRIPT"
T9_EXIT=$?
set -e

T9_COUNT=$(count_log_files "$T9_DIR")
T9_PASS=true

if [ "$T9_EXIT" -ne 0 ]; then
  printf "  ${RED}FAIL: exit code %d, expected 0${NC}\n" "$T9_EXIT"
  T9_PASS=false
fi

if [ "$T9_COUNT" -ne 1 ]; then
  printf "  ${RED}FAIL: expected 1 log file, found %s${NC}\n" "$T9_COUNT"
  T9_PASS=false
fi

# Check the filename: the session_id portion should be at most 128 chars
T9_LOG_DIR=$(log_dir_path "$T9_DIR")
if [ -d "$T9_LOG_DIR" ]; then
  T9_FILENAME=$(ls -1 "$T9_LOG_DIR" | head -1)
  # Filename format: {sanitized_session_id}_{event}_{timestamp}.json
  # Extract the session_id portion (everything before the first _PreCompact)
  T9_SID_PART=$(echo "$T9_FILENAME" | sed 's/_precompact_.*//')
  T9_SID_LEN=${#T9_SID_PART}
  if [ "$T9_SID_LEN" -gt 128 ]; then
    printf "  ${RED}FAIL: session_id in filename is %d chars, expected <= 128${NC}\n" "$T9_SID_LEN"
    T9_PASS=false
  fi
else
  printf "  ${RED}FAIL: log directory not created${NC}\n"
  T9_PASS=false
fi

if [ "$T9_PASS" = "true" ]; then
  printf "  ${GREEN}PASS${NC}\n"
  PASSED=$((PASSED + 1))
else
  FAILED=$((FAILED + 1))
fi

# ============================================================
# Test 10: Concurrent uniqueness (microsecond timestamps)
# ============================================================
TESTS_RUN=$((TESTS_RUN + 1))
echo "Test ${TESTS_RUN}: Concurrent invocations produce unique filenames"

T10_DIR="${TEST_DIR}/t10"
mkdir -p "$T10_DIR"

T10_JSON=$(cat <<'ENDJSON'
{
  "session_id": "test-session-010",
  "transcript_path": "/tmp/transcript-010.jsonl",
  "cwd": "/workspace/repos/my-project",
  "hook_event_name": "PreCompact",
  "trigger": "auto",
  "custom_instructions": ""
}
ENDJSON
)

# Run hook twice in rapid succession
set +e
echo "$T10_JSON" | SDD_ROOT_DIR="$T10_DIR" python3 "$HOOK_SCRIPT"
echo "$T10_JSON" | SDD_ROOT_DIR="$T10_DIR" python3 "$HOOK_SCRIPT"
T10_EXIT=$?
set -e

T10_COUNT=$(count_log_files "$T10_DIR")
T10_PASS=true

if [ "$T10_COUNT" -ne 2 ]; then
  printf "  ${RED}FAIL: expected 2 unique log files, found %s${NC}\n" "$T10_COUNT"
  T10_PASS=false
fi

# Verify filenames are different
if [ -d "$(log_dir_path "$T10_DIR")" ]; then
  T10_UNIQUE=$(ls -1 "$(log_dir_path "$T10_DIR")" | sort -u | wc -l | tr -d ' ')
  if [ "$T10_UNIQUE" -ne 2 ]; then
    printf "  ${RED}FAIL: filenames are not unique (found %s unique)${NC}\n" "$T10_UNIQUE"
    T10_PASS=false
  fi
fi

if [ "$T10_PASS" = "true" ]; then
  printf "  ${GREEN}PASS${NC}\n"
  PASSED=$((PASSED + 1))
else
  FAILED=$((FAILED + 1))
fi

# ============================================================
# Test 11: JSON schema validation (field type checks)
# ============================================================
TESTS_RUN=$((TESTS_RUN + 1))
echo "Test ${TESTS_RUN}: JSON schema validation - all fields have correct types"

T11_DIR="${TEST_DIR}/t11"
mkdir -p "$T11_DIR"

T11_JSON=$(cat <<'ENDJSON'
{
  "session_id": "test-session-011",
  "transcript_path": "/tmp/transcript-011.jsonl",
  "cwd": "/workspace/repos/my-project",
  "hook_event_name": "PreCompact",
  "trigger": "manual",
  "custom_instructions": "Use strict mode"
}
ENDJSON
)

set +e
echo "$T11_JSON" | SDD_ROOT_DIR="$T11_DIR" python3 "$HOOK_SCRIPT"
T11_EXIT=$?
set -e

T11_FILE=$(get_log_file "$T11_DIR")
T11_PASS=true

if [ -z "$T11_FILE" ]; then
  printf "  ${RED}FAIL: no log file created for schema validation${NC}\n"
  T11_PASS=false
else
  # Validate all required fields exist and are not null/empty
  if ! validate_json_fields "$T11_FILE" "session_id transcript_path cwd hook_event_name timestamp status trigger custom_instructions"; then
    T11_PASS=false
  fi

  # Validate timestamp looks like an ISO format
  T11_TS=$(jq -r '.timestamp' "$T11_FILE")
  if ! echo "$T11_TS" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}'; then
    printf "  ${RED}FAIL: timestamp '%s' does not match ISO format${NC}\n" "$T11_TS"
    T11_PASS=false
  fi

  # Validate hook_event_name is the expected value
  T11_EVENT=$(jq -r '.hook_event_name' "$T11_FILE")
  if [ "$T11_EVENT" != "PreCompact" ]; then
    printf "  ${RED}FAIL: hook_event_name='%s', expected 'PreCompact'${NC}\n" "$T11_EVENT"
    T11_PASS=false
  fi
fi

if [ "$T11_PASS" = "true" ]; then
  printf "  ${GREEN}PASS${NC}\n"
  PASSED=$((PASSED + 1))
else
  FAILED=$((FAILED + 1))
fi

# ============================================================
# Test 12: Unknown hook event name
# ============================================================
TESTS_RUN=$((TESTS_RUN + 1))
echo "Test ${TESTS_RUN}: Unknown event name handling"

T12_DIR="${TEST_DIR}/t12"
mkdir -p "$T12_DIR"

T12_JSON=$(cat <<'ENDJSON'
{
  "session_id": "test-session-012",
  "transcript_path": "/tmp/transcript-012.jsonl",
  "cwd": "/workspace/repos/my-project",
  "hook_event_name": "NewEventType-With Spaces!!!"
}
ENDJSON
)

set +e
echo "$T12_JSON" | SDD_ROOT_DIR="$T12_DIR" python3 "$HOOK_SCRIPT"
T12_EXIT=$?
set -e

T12_PASS=true

if [ "$T12_EXIT" -ne 0 ]; then
  printf "  ${RED}FAIL: exit code %d, expected 0${NC}\n" "$T12_EXIT"
  T12_PASS=false
fi

# Verify file created with sanitized event name (lowercase, special chars removed)
T12_LOG_DIR=$(log_dir_path "$T12_DIR")
T12_COUNT=$(count_log_files "$T12_DIR")

if [ "$T12_COUNT" -ne 1 ]; then
  printf "  ${RED}FAIL: expected 1 log file, found %s${NC}\n" "$T12_COUNT"
  T12_PASS=false
fi

if [ -d "$T12_LOG_DIR" ]; then
  T12_FILENAME=$(ls -1 "$T12_LOG_DIR" | head -1)
  # Event "NewEventType-With Spaces!!!" -> strip non-alnum except -/_ -> "NewEventType-WithSpaces"
  # -> truncate to 20 chars -> "NewEventType-WithSpa" -> lowercase -> "neweventtype-withspa"
  if ! echo "$T12_FILENAME" | grep -qE '^test-session-012_neweventtype-withspa_[0-9]{8}T[0-9]{12}\.json$'; then
    printf "  ${RED}FAIL: filename '%s' does not match expected sanitized pattern${NC}\n" "$T12_FILENAME"
    T12_PASS=false
  fi
fi

# Verify status indicates unknown event
T12_FILE=$(get_log_file "$T12_DIR")
if [ -n "$T12_FILE" ]; then
  T12_STATUS=$(jq -r '.status' "$T12_FILE")
  if [ "$T12_STATUS" != "unknown_event" ]; then
    printf "  ${RED}FAIL: status='%s', expected 'unknown_event'${NC}\n" "$T12_STATUS"
    T12_PASS=false
  fi

  # Verify original event name is preserved in the JSON
  T12_EVENT=$(jq -r '.hook_event_name' "$T12_FILE")
  if [ "$T12_EVENT" != "NewEventType-With Spaces!!!" ]; then
    printf "  ${RED}FAIL: hook_event_name='%s', expected original unsanitized value${NC}\n" "$T12_EVENT"
    T12_PASS=false
  fi
else
  printf "  ${RED}FAIL: no log file found${NC}\n"
  T12_PASS=false
fi

if [ "$T12_PASS" = "true" ]; then
  printf "  ${GREEN}PASS${NC}\n"
  PASSED=$((PASSED + 1))
else
  FAILED=$((FAILED + 1))
fi

# ============================================================
# Additional validations rolled into previous tests:
# - Test 1 covers: file permissions (0600), filename pattern, field presence
# - Test 2 covers: SessionEnd-specific 'reason' field
# - Test 3 covers: empty_path status
# - Test 8 covers: path traversal sanitization
# ============================================================

echo ""
echo "=========================================="
echo "Test Summary:"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo "=========================================="

if [ $FAILED -eq 0 ]; then
  printf "${GREEN}All tests passed!${NC}\n"
  exit 0
else
  printf "${RED}Some tests failed.${NC}\n"
  exit 1
fi
