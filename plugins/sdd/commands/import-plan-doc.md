---
description: Import an external planning document and create SDD planning documents from it
argument-hint: FILE_PATH [TICKET_ID name] [additional instructions]
---

# Import Plan Document

## Context

User input: "$ARGUMENTS"
Plugin root: "${CLAUDE_PLUGIN_ROOT}"

## Workflow

**IMPORTANT: You are an orchestrator. You do NOT do the work yourself. You delegate to scripts and agents.**

### Step 1: Parse Arguments

Parse user input to detect one of three modes:

1. **Path-only**: First argument is a file path (contains `/` or is a valid file)
   - Example: `/sdd:import-plan-doc ./plan.md`
   - Identifiers derived from plan content

2. **Explicit IDs**: First argument is UPPERCASE (TICKET_ID), second is lowercase (name), third is file path
   - Example: `/sdd:import-plan-doc MYTICKET feature-name ./plan.md`
   - User provides identifiers explicitly

3. **Path with instructions**: File path followed by additional text
   - Example: `/sdd:import-plan-doc ./plan.md Focus on security aspects`
   - Identifiers derived, extra text passed to agent

**Argument Detection Logic:**

Execute this bash logic to parse arguments:

```bash
# Helper function for error logging
log_validation_error() {
    local msg="$1"
    SDD_ROOT="${SDD_ROOT_DIR:-/app/.sdd}"
    mkdir -p "$SDD_ROOT/logs"
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")|IMPORT_FAILED|${TICKET_ID:-UNKNOWN}|-|import-plan-doc|$msg" >> "$SDD_ROOT/logs/workflow.log"
}

# Validate TICKET_ID format and security
validate_ticket_id() {
    local ticket_id="$1"

    # Check for path traversal
    case "$ticket_id" in
        *..* | */*)
            echo "ERROR: TICKET_ID contains path traversal characters" >&2
            echo "TICKET_ID cannot contain '..' or '/' sequences" >&2
            echo "" >&2
            echo "Example: /sdd:import-plan-doc MYTICKET feature-name ./plan.md" >&2
            return 1
            ;;
    esac

    # Check minimum length
    if [ ${#ticket_id} -lt 2 ]; then
        echo "ERROR: TICKET_ID must be at least 2 characters" >&2
        echo "Received: '$ticket_id'" >&2
        echo "" >&2
        echo "Example: /sdd:import-plan-doc MYTICKET feature-name ./plan.md" >&2
        return 1
    fi

    # Check format (uppercase alphanumeric only)
    # Use grep -E for POSIX compatibility
    if echo "$ticket_id" | grep -Eq '[^A-Z0-9]'; then
        echo "ERROR: TICKET_ID must be uppercase alphanumeric (A-Z, 0-9)" >&2
        echo "Received: '$ticket_id'" >&2
        echo "" >&2
        echo "Example: /sdd:import-plan-doc MYTICKET feature-name ./plan.md" >&2
        return 1
    fi

    return 0
}

# Validate name format and security
validate_name() {
    local name="$1"

    # Check for path traversal
    case "$name" in
        *..* | */*)
            echo "ERROR: name contains path traversal characters" >&2
            echo "name cannot contain '..' or '/' sequences" >&2
            echo "" >&2
            echo "Example: /sdd:import-plan-doc MYTICKET feature-name ./plan.md" >&2
            return 1
            ;;
    esac

    # Check for spaces
    case "$name" in
        *\ *)
            echo "ERROR: name cannot contain spaces. Use hyphens instead." >&2
            echo "Example: 'feature-name' not 'feature name'" >&2
            echo "" >&2
            echo "Usage: /sdd:import-plan-doc MYTICKET feature-name ./plan.md" >&2
            return 1
            ;;
    esac

    return 0
}

# Get argument count
arg_count=$(echo "$ARGUMENTS" | awk '{print NF}')

# Extract first three arguments
first_arg=$(echo "$ARGUMENTS" | awk '{print $1}')
second_arg=$(echo "$ARGUMENTS" | awk '{print $2}')
third_arg=$(echo "$ARGUMENTS" | awk '{print $3}')

# Detect mode using POSIX-compatible case statement
MODE=""
TICKET_ID=""
name=""
FILE_PATH=""
additional_instructions=""

# Check if first argument looks like a file path
is_file_path=""
case "$first_arg" in
    /*|./*|../*|*/*) is_file_path="yes" ;;
esac

# Check if first argument is UPPERCASE (potential TICKET_ID)
is_uppercase=""
case "$first_arg" in
    [A-Z]*)
        # Verify it's all uppercase/digits
        cleaned=$(echo "$first_arg" | sed 's/[A-Z0-9]//g')
        [ -z "$cleaned" ] && is_uppercase="yes"
        ;;
esac

# Determine mode
if [ -n "$is_file_path" ] || [ -f "$first_arg" ]; then
    # Mode 1 or 3: Path-only or Path with instructions
    FILE_PATH="$first_arg"
    if [ "$arg_count" -gt 1 ]; then
        MODE="path_with_instructions"
        additional_instructions=$(echo "$ARGUMENTS" | cut -d' ' -f2-)
    else
        MODE="path_only"
    fi
elif [ -n "$is_uppercase" ] && [ "$arg_count" -ge 3 ]; then
    # Mode 2: Explicit IDs (TICKET_ID name file_path)
    MODE="explicit_ids"
    TICKET_ID="$first_arg"
    name="$second_arg"
    FILE_PATH="$third_arg"
    if [ "$arg_count" -gt 3 ]; then
        additional_instructions=$(echo "$ARGUMENTS" | cut -d' ' -f4-)
    fi
else
    # Invalid input
    MODE="invalid"
fi

# Validate explicit TICKET_ID and name if provided (Mode 2: explicit_ids)
if [ "$MODE" = "explicit_ids" ]; then
    # Validate TICKET_ID
    if ! validate_ticket_id "$TICKET_ID"; then
        log_validation_error "Invalid TICKET_ID: $TICKET_ID"
        exit 1
    fi

    # Validate name
    if ! validate_name "$name"; then
        log_validation_error "Invalid name: $name"
        exit 1
    fi
fi
```

**Validation:**

If no valid file path is detected or mode is invalid, report error:
```
ERROR: Invalid arguments or file path not provided.

Usage: /sdd:import-plan-doc FILE_PATH [TICKET_ID name] [additional instructions]

FILE_PATH must be:
  - A valid path to a readable markdown or text file
  - Can be relative (./plan.md) or absolute (/path/to/plan.md)

Examples:
  /sdd:import-plan-doc ./plan.md
  /sdd:import-plan-doc /path/to/plan.md MYTICKET feature-name
  /sdd:import-plan-doc ./plan.md Focus on security aspects
```

### Step 2: Validate File

**Check file exists and is readable:**

```bash
# Check file exists FIRST (before path resolution)
if [ ! -f "$FILE_PATH" ]; then
    echo "ERROR: File not found: $FILE_PATH"
    echo ""
    echo "Please verify the file path and try again."
    echo ""
    echo "Usage: /sdd:import-plan-doc FILE_PATH [TICKET_ID name] [additional instructions]"
    echo ""
    echo "Examples:"
    echo "  /sdd:import-plan-doc ./my-plan.md"
    echo "  /sdd:import-plan-doc /path/to/plan.md MYTICKET feature-name"
    echo "  /sdd:import-plan-doc ./plan.md Focus on security aspects"
    SDD_ROOT="${SDD_ROOT_DIR:-/app/.sdd}"
    mkdir -p "$SDD_ROOT/logs"
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")|IMPORT_FAILED|${TICKET_ID:-UNKNOWN}|-|import-plan-doc|File not found: $FILE_PATH" >> "$SDD_ROOT/logs/workflow.log"
    exit 1
fi

# Check file readable
if [ ! -r "$FILE_PATH" ]; then
    echo "ERROR: File not readable: $FILE_PATH"
    echo ""
    echo "Check file permissions and try again."
    echo ""
    echo "Usage: /sdd:import-plan-doc FILE_PATH [TICKET_ID name] [additional instructions]"
    echo ""
    echo "Examples:"
    echo "  /sdd:import-plan-doc ./my-plan.md"
    echo "  /sdd:import-plan-doc /path/to/plan.md MYTICKET feature-name"
    echo "  /sdd:import-plan-doc ./plan.md Focus on security aspects"
    SDD_ROOT="${SDD_ROOT_DIR:-/app/.sdd}"
    mkdir -p "$SDD_ROOT/logs"
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")|IMPORT_FAILED|${TICKET_ID:-UNKNOWN}|-|import-plan-doc|File not readable: $FILE_PATH" >> "$SDD_ROOT/logs/workflow.log"
    exit 1
fi

# THEN resolve to absolute path (POSIX-compatible)
# This is guaranteed to work since file existence was validated above
FILE_PATH_ABS=$(cd "$(dirname "$FILE_PATH")" && pwd)/$(basename "$FILE_PATH")

# Check file size (10MB limit to prevent memory exhaustion)
file_size=$(wc -c < "$FILE_PATH" | tr -d ' ')
max_size=10485760  # 10MB

if [ "$file_size" -gt "$max_size" ]; then
    echo "ERROR: Plan file too large: $(($file_size / 1048576))MB"
    echo "Maximum allowed: 10MB"
    echo ""
    echo "For large files, consider:"
    echo "  1. Split into multiple smaller plans"
    echo "  2. Summarize content before importing"
    echo "  3. Create plan manually with /sdd:plan-ticket"
    SDD_ROOT="${SDD_ROOT_DIR:-/app/.sdd}"
    mkdir -p "$SDD_ROOT/logs"
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")|IMPORT_FAILED|${TICKET_ID:-UNKNOWN}|-|import-plan-doc|File too large: $(($file_size / 1048576))MB" >> "$SDD_ROOT/logs/workflow.log"
    exit 1
fi
```

### Step 3: Read File Content

**Read the full plan file content:**

```bash
# Read file content
PLAN_CONTENT=$(cat "$FILE_PATH_ABS")

# Verify content was read
if [ -z "$PLAN_CONTENT" ]; then
    echo "WARNING: File is empty: $FILE_PATH_ABS"
fi
```

### Step 4: Derive Identifiers

If not explicitly provided (Mode 1 or 3), derive identifiers from plan content:

```bash
# Force C locale for consistent tr/sed behavior across all environments
export LC_ALL=C

# Only derive if not in explicit_ids mode
if [ "$MODE" != "explicit_ids" ]; then
    # Extract first heading from plan file
    first_heading=$(grep -m 1 '^#' "$FILE_PATH_ABS" | sed 's/^#* *//')

    # Derive TICKET_ID: uppercase, alphanumeric only, max 12 chars
    TICKET_ID=$(echo "$first_heading" | tr '[:lower:]' '[:upper:]' | sed 's/[^A-Z0-9]//g' | cut -c1-12)

    # Derive name: kebab-case
    name=$(echo "$first_heading" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')

    # Fallback if derivation fails
    [ -z "$TICKET_ID" ] && TICKET_ID="PLAN$(date +%s)"
    [ -z "$name" ] && name="imported-plan"
fi

# Validate TICKET_ID minimum length (at least 2 characters)
if [ ${#TICKET_ID} -lt 2 ]; then
    echo "WARNING: Derived TICKET_ID too short: '$TICKET_ID'"
    echo "Using fallback identifier"
    TICKET_ID="PLAN$(date +%s)"
fi
```

**Check for uniqueness:**

```bash
SDD_ROOT="${SDD_ROOT_DIR:-/app/.sdd}"
existing=$(ls -d "$SDD_ROOT/tickets/${TICKET_ID}_"* "$SDD_ROOT/archive/tickets/${TICKET_ID}_"* 2>/dev/null | head -1)

if [ -n "$existing" ]; then
    echo "ERROR: Ticket with ID '$TICKET_ID' already exists."
    echo ""
    echo "Conflicting ticket: $existing"
    echo ""
    echo "Options:"
    echo "  1. Use explicit IDs: /sdd:import-plan-doc NEWID new-name ./plan.md"
    echo "  2. Archive existing ticket: /sdd:archive $TICKET_ID"
    echo ""
    echo "Usage: /sdd:import-plan-doc FILE_PATH [TICKET_ID name] [additional instructions]"
    echo ""
    echo "Examples:"
    echo "  /sdd:import-plan-doc ./my-plan.md"
    echo "  /sdd:import-plan-doc /path/to/plan.md MYTICKET feature-name"
    echo "  /sdd:import-plan-doc ./plan.md Focus on security aspects"
    mkdir -p "$SDD_ROOT/logs"
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")|IMPORT_FAILED|${TICKET_ID:-UNKNOWN}|-|import-plan-doc|Duplicate ticket ID: $TICKET_ID" >> "$SDD_ROOT/logs/workflow.log"
    exit 1
fi

# Cleanup function for error recovery
cleanup_on_error() {
    if [ -n "$TICKET_ID" ] && [ -n "$name" ]; then
        ticket_path="${SDD_ROOT}/tickets/${TICKET_ID}_${name}"
        if [ -d "$ticket_path" ]; then
            echo "Cleaning up incomplete ticket: $ticket_path"
            rm -rf "$ticket_path"
        fi
    fi
}

# Register trap to clean up on error (before scaffolding creates directory)
trap cleanup_on_error ERR EXIT
```

### Step 5: Scaffold Structure

**Validate scaffold script exists:**

```bash
# Validate scaffold-ticket.sh exists and is executable
scaffold_script="${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/scripts/scaffold-ticket.sh"

if [ ! -f "$scaffold_script" ]; then
    echo "ERROR: scaffold-ticket.sh not found"
    echo "Expected location: $scaffold_script"
    echo "Please verify plugin installation."
    SDD_ROOT="${SDD_ROOT_DIR:-/app/.sdd}"
    mkdir -p "$SDD_ROOT/logs"
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")|IMPORT_FAILED|${TICKET_ID:-UNKNOWN}|-|import-plan-doc|Scaffolding failed: script not found" >> "$SDD_ROOT/logs/workflow.log"
    exit 1
fi

if [ ! -x "$scaffold_script" ]; then
    echo "ERROR: scaffold-ticket.sh not executable"
    echo "Location: $scaffold_script"
    echo "Run: chmod +x $scaffold_script"
    SDD_ROOT="${SDD_ROOT_DIR:-/app/.sdd}"
    mkdir -p "$SDD_ROOT/logs"
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")|IMPORT_FAILED|${TICKET_ID:-UNKNOWN}|-|import-plan-doc|Scaffolding failed: script not executable" >> "$SDD_ROOT/logs/workflow.log"
    exit 1
fi
```

**Delegate to script:**

```bash
bash "$scaffold_script" "${TICKET_ID}" "${name}"
```

This creates:
- `${SDD_ROOT_DIR}/tickets/{TICKET_ID}_{name}/README.md`
- `${SDD_ROOT_DIR}/tickets/{TICKET_ID}_{name}/planning/` with template files
- `${SDD_ROOT_DIR}/tickets/{TICKET_ID}_{name}/tasks/`

### Step 6: Fill Planning Documents

**Display progress messages:**

```bash
echo ""
echo "Importing plan from: ${FILE_PATH_ABS}"
echo "Creating ticket: ${TICKET_ID}_${name}"
echo ""
echo "Delegating to ticket-planner agent..."
echo "(This may take 30-60 seconds while agent researches codebase)"
echo ""
```

**Delegate to ticket-planner agent (Opus):**

```
Assignment: Create comprehensive planning documents for ticket {TICKET_ID}_{name}

Context:
- Ticket path: ${SDD_ROOT_DIR}/tickets/{TICKET_ID}_{name}/
- Scaffolded files exist with templates

Imported Plan Content:
---BEGIN IMPORTED PLAN---
{full content of the plan file}
---END IMPORTED PLAN---

Import Source: {FILE_PATH_ABS}

Additional Instructions: {additional_instructions or "None provided"}

Instructions:
1. ABSORB the imported plan content completely into SDD planning documents
2. Map imported sections to appropriate SDD documents:
   - Problem/Goal sections -> analysis.md
   - Requirements/Features -> prd.md
   - Architecture/Approach -> architecture.md
   - Implementation steps -> plan.md (as phases)
   - Testing considerations -> quality-strategy.md
   - Security/Risk items -> security-review.md
3. The imported plan is SOURCE MATERIAL - extract and restructure, don't just copy
4. After import, the original plan file should NOT be needed
5. Update README.md with overview and note the import source
6. Research codebase to supplement imported content where needed

Return: Summary of planning decisions made
```

**Display completion message:**

```bash
echo "Planning documents created successfully."
echo ""
```

**Verify planning documents were created:**

```bash
# Verify all planning docs exist and are non-empty
SDD_ROOT="${SDD_ROOT_DIR:-/app/.sdd}"
ticket_path="${SDD_ROOT}/tickets/${TICKET_ID}_${name}"

for doc in analysis.md prd.md architecture.md plan.md quality-strategy.md security-review.md; do
    doc_path="${ticket_path}/planning/${doc}"
    if [ ! -f "$doc_path" ]; then
        echo "ERROR: Agent failed to create $doc"
        echo "Ticket directory: $ticket_path"
        echo "Please check agent logs and retry import."
        mkdir -p "$SDD_ROOT/logs"
        echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")|IMPORT_FAILED|${TICKET_ID:-UNKNOWN}|-|import-plan-doc|Agent failed to create planning docs: $TICKET_ID" >> "$SDD_ROOT/logs/workflow.log"
        exit 1
    fi
    if [ ! -s "$doc_path" ]; then
        echo "ERROR: Agent created empty $doc"
        echo "Ticket directory: $ticket_path"
        echo "Please check agent logs and retry import."
        mkdir -p "$SDD_ROOT/logs"
        echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")|IMPORT_FAILED|${TICKET_ID:-UNKNOWN}|-|import-plan-doc|Agent failed to create planning docs: $TICKET_ID" >> "$SDD_ROOT/logs/workflow.log"
        exit 1
    fi
done
```

### Step 7: Log and Report

**Log the import event:**

```bash
SDD_ROOT="${SDD_ROOT_DIR:-/app/.sdd}"
mkdir -p "$SDD_ROOT/logs"
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")|TICKET_IMPORTED|${TICKET_ID}|-|import-plan-doc|Imported from file ${FILE_PATH_ABS}" >> "$SDD_ROOT/logs/workflow.log"

# Disable cleanup trap on success (ticket is complete)
trap - ERR EXIT
```

**Report success:**

```
PLAN IMPORTED: {TICKET_ID}_{name}

Source: {FILE_PATH_ABS}
Mode: {MODE}

Structure:
${SDD_ROOT_DIR}/tickets/{TICKET_ID}_{name}/
├── README.md
├── planning/
│   ├── analysis.md
│   ├── architecture.md
│   ├── plan.md
│   ├── quality-strategy.md
│   └── security-review.md
└── tasks/

Planning Summary:
- Problem: {one-line from analysis}
- Solution: {one-line from architecture}
- Phases: {count} phases planned

Import Details:
- Original file: {FILE_PATH_ABS}
- Derived identifiers: TICKET_ID={TICKET_ID}, name={name}
- Task IDs will be: {TICKET_ID}.1001, {TICKET_ID}.2001, etc.

```

### Next Step Prompt

After displaying the report above, use the **AskUserQuestion** tool to present next steps to the user:

**Question:** "What would you like to do next?"
**Header:** "Next step"
**multiSelect:** false

**Options:**
- Label: "/sdd:review {TICKET_ID}" | Description: "Review imported plan quality"
- Label: "/sdd:create-tasks {TICKET_ID}" | Description: "Skip review and create tasks directly"

Where {TICKET_ID} is the actual ticket ID from the command execution context, NOT the literal placeholder text.

## Key Constraints

- ALWAYS validate file exists and is readable before processing
- Use scaffold-ticket.sh for structure creation
- Use ticket-planner agent for content processing
- DO NOT write planning docs yourself - delegate to agent
- DO NOT skip any planning document
- DO NOT modify the source plan file (read-only operation)
- Include import source reference in generated documentation
- Use POSIX-compatible bash syntax (no `[[`, use `[ ]` and `case`)
- Quote all file paths for spaces: `"$FILE_PATH"`

## Examples

```bash
# Path-only (identifiers derived from first heading)
/sdd:import-plan-doc ./plan.md

# Absolute path
/sdd:import-plan-doc /home/user/projects/my-plan.md

# Explicit IDs provided
/sdd:import-plan-doc MYTICKET feature-name ./plan.md

# Explicit IDs with absolute path
/sdd:import-plan-doc AUTH auth-refactor /home/user/auth-plan.md

# Path with additional instructions
/sdd:import-plan-doc ./plan.md Focus on security aspects

# Path with detailed instructions
/sdd:import-plan-doc ./plan.md Phase 1 should focus on API changes only

# Explicit IDs with additional instructions
/sdd:import-plan-doc PERF performance-tuning ./perf-plan.md Focus on database optimizations
```
