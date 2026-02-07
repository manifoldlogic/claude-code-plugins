---
description: Archive completed tickets
argument-hint: [TICKET_ID or empty to review all]
---

# Archive Tickets

## Context

Ticket: $ARGUMENTS (optional - if empty, reviews all tasks)

**Note:** Consider running code review before archiving:
- Review code: `/sdd:code-review {TICKET_ID}` (recommended)
- Create PR: `/sdd:pr {TICKET_ID}`

These steps are optional but recommended for production code.

## Workflow

**IMPORTANT: You are an orchestrator. Use scripts for validation and scanning.**

### Step 1: Gather Status

**Run status script:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/scripts/task-status.sh ${ARGUMENTS}
```

### Step 2: Identify Candidates

From the status JSON, identify tickets where:
- ALL tasks have `verified: true`
- No pending or in-progress tasks

### Step 3: Validate Structure

For each candidate, **run validation:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/scripts/validate-structure.sh ${TICKET_ID}
```

Ensure:
- All required files exist
- No structural issues

### Step 4: Verify Task Checkboxes

**CRITICAL: Source of truth is the task files themselves.**

For each task file, verify the "Verified" checkbox is checked:
```markdown
- [x] **Verified** - by the verify-task agent
```

If ANY task has unchecked Verified, do NOT archive.

### Step 5: Update Documents Before Archive

Before moving:

1. **Update task index** to show final status
2. **Update README** with completion date
3. **Check for knowledge to extract to /docs/**

### Step 5.5: Deliverable Review Gate

**VALIDATION: All deliverables must have explicit disposition decisions before archiving.**

This gate ensures deliverables are intentionally handled (extracted, archived, or acknowledged as external) before a ticket is archived. This prevents knowledge loss from deliverables that should have been extracted to permanent locations.

#### Helper Functions

These bash functions are used by the deliverable review gate:

```bash
# =============================================================================
# HELPER FUNCTION: validate_disposition_format
# Validates disposition string format against allowed patterns
# Returns 0 if valid, 1 if invalid
# =============================================================================
validate_disposition_format() {
    local disposition="$1"

    # Trim whitespace
    disposition=$(echo "$disposition" | xargs)

    # Check format
    if [ "$disposition" = "archive" ]; then
        return 0
    elif [[ "$disposition" =~ ^extract:[[:space:]]*[a-zA-Z0-9/_.-]+$ ]]; then
        return 0
    elif [[ "$disposition" =~ ^external:[[:space:]]*.+ ]]; then
        return 0
    else
        echo "ERROR: Invalid disposition format: '$disposition'"
        echo "Valid formats:"
        echo "  extract: path/to/dest"
        echo "  archive"
        echo "  external: Location Description"
        return 1
    fi
}

# =============================================================================
# HELPER FUNCTION: validate_extraction_path
# Security validation for extraction paths
# Rejects path traversal, absolute paths, and special characters
# Returns 0 if valid, 1 if invalid
# =============================================================================
validate_extraction_path() {
    local path="$1"

    # Reject path traversal
    if [[ "$path" == *".."* ]]; then
        echo "ERROR: Path traversal not allowed: $path"
        return 1
    fi

    # Reject absolute paths (Unix)
    if [[ "$path" == /* ]]; then
        echo "ERROR: Absolute paths not allowed: $path"
        return 1
    fi

    # Reject Windows absolute paths (C:\, D:\, etc.)
    if [[ "$path" =~ ^[A-Za-z]:.* ]]; then
        echo "ERROR: Windows absolute paths not allowed: $path"
        return 1
    fi

    # Reject home directory references
    if [[ "$path" == ~* ]]; then
        echo "ERROR: Home directory paths not allowed: $path"
        return 1
    fi

    # Reject UNC paths (\\server\share)
    if [[ "$path" == \\\\* ]] || [[ "$path" == \\* ]]; then
        echo "ERROR: UNC paths not allowed: $path"
        return 1
    fi

    # Reject command injection attempts
    if [[ "$path" == *";"* ]] || [[ "$path" == *'$('* ]] || [[ "$path" == *'`'* ]]; then
        echo "ERROR: Command injection characters not allowed: $path"
        return 1
    fi

    # Reject newlines and other control characters
    if [[ "$path" =~ [[:cntrl:]] ]]; then
        echo "ERROR: Control characters not allowed in path: $path"
        return 1
    fi

    # Validate allowed characters only: a-zA-Z0-9/_.-
    if ! [[ "$path" =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
        echo "ERROR: Invalid characters in path: $path"
        echo "Allowed characters: a-z A-Z 0-9 / _ . -"
        return 1
    fi

    return 0
}

# =============================================================================
# HELPER FUNCTION: parse_task_deliverables
# Extracts dispositions from task markdown table (## Deliverables Produced section)
# Populates the dispositions associative array
# =============================================================================
parse_task_deliverables() {
    local task_file="$1"

    # Check if file exists
    [ -f "$task_file" ] || return

    # Extract the Deliverables Produced section
    local in_section=false
    local in_table=false

    while IFS= read -r line; do
        # Detect section start
        if [[ "$line" =~ ^##[[:space:]]*Deliverables[[:space:]]*Produced ]]; then
            in_section=true
            continue
        fi

        # Detect section end (next ## heading)
        if [ "$in_section" = true ] && [[ "$line" =~ ^## ]]; then
            break
        fi

        # Skip if not in section
        [ "$in_section" = true ] || continue

        # Detect table start (header row with pipes)
        if [[ "$line" == *"|"*"Deliverable"*"|"* ]]; then
            in_table=true
            continue
        fi

        # Skip separator row
        if [ "$in_table" = true ] && [[ "$line" =~ ^\|[-[:space:]|]+\|$ ]]; then
            continue
        fi

        # Parse table row
        if [ "$in_table" = true ] && [[ "$line" == "|"* ]]; then
            # Split by pipe and extract columns
            local deliverable=$(echo "$line" | cut -d'|' -f2 | xargs)
            local disposition=$(echo "$line" | cut -d'|' -f4 | xargs)

            # Store if we have both values and disposition is not empty/placeholder
            if [ -n "$deliverable" ] && [ -n "$disposition" ] && [ "$disposition" != "(TBD)" ] && [ "$disposition" != "N/A" ]; then
                dispositions["$deliverable"]="$disposition"
            fi
        fi
    done < "$task_file"
}

# =============================================================================
# HELPER FUNCTION: parse_plan_deliverables
# Extracts dispositions from plan.md markdown table
# Only adds to dispositions array if not already set (task files take priority)
# =============================================================================
parse_plan_deliverables() {
    local plan_file="$1"

    # Check if file exists
    [ -f "$plan_file" ] || return

    # Extract the Deliverables section
    local in_section=false
    local in_table=false

    while IFS= read -r line; do
        # Detect section start (various formats: **Deliverables:**, ## Deliverables, etc.)
        if [[ "$line" =~ Deliverables ]] && [[ "$line" =~ (\*\*|^##) ]]; then
            in_section=true
            continue
        fi

        # Detect section end (next section heading)
        if [ "$in_section" = true ] && [[ "$line" =~ ^(\*\*|##)[^|] ]] && [[ ! "$line" =~ Deliverables ]]; then
            break
        fi

        # Skip if not in section
        [ "$in_section" = true ] || continue

        # Detect table start (header row with pipes)
        if [[ "$line" == *"|"*"Deliverable"*"|"* ]]; then
            in_table=true
            continue
        fi

        # Skip separator row
        if [ "$in_table" = true ] && [[ "$line" =~ ^\|[-[:space:]|]+\|$ ]]; then
            continue
        fi

        # Parse table row
        if [ "$in_table" = true ] && [[ "$line" == "|"* ]]; then
            # Split by pipe and extract columns
            local deliverable=$(echo "$line" | cut -d'|' -f2 | xargs)
            local disposition=$(echo "$line" | cut -d'|' -f4 | xargs)

            # Only add if not already set from task files (task files take priority)
            if [ -n "$deliverable" ] && [ -n "$disposition" ] && [ "$disposition" != "(TBD)" ] && [ "$disposition" != "N/A" ]; then
                if [ -z "${dispositions[$deliverable]}" ]; then
                    dispositions["$deliverable"]="$disposition"
                fi
            fi
        fi
    done < "$plan_file"
}

# =============================================================================
# HELPER FUNCTION: generate_manifest
# Creates MANIFEST.md file with all disposition decisions
# =============================================================================
generate_manifest() {
    local manifest_path="$1"
    local -n dispositions_ref="$2"
    local ticket_id="$3"

    cat > "$manifest_path" <<EOF
# Deliverable Manifest

**Format Version:** 1.0
**Ticket:** $ticket_id
**Archive Date:** $(date +%Y-%m-%d)

## Dispositions

| Deliverable | Disposition | Destination | Confirmed |
|-------------|-------------|-------------|-----------|
EOF

    for deliv_name in "${!dispositions_ref[@]}"; do
        disposition="${dispositions_ref[$deliv_name]}"

        if [[ "$disposition" =~ ^extract: ]]; then
            dest=$(echo "$disposition" | sed 's/^extract:[[:space:]]*//')
            echo "| $deliv_name | extract | $dest | Yes |" >> "$manifest_path"
        elif [ "$disposition" = "archive" ]; then
            echo "| $deliv_name | archive | - | Yes |" >> "$manifest_path"
        elif [[ "$disposition" =~ ^external: ]]; then
            desc=$(echo "$disposition" | sed 's/^external:[[:space:]]*//')
            echo "| $deliv_name | external | $desc | Yes |" >> "$manifest_path"
        fi
    done

    cat >> "$manifest_path" <<EOF

## Notes

Generated during archive process.
EOF
}
```

#### Gate Implementation

Run the following deliverable review gate logic before archiving:

```bash
#!/bin/bash
# =============================================================================
# DELIVERABLE REVIEW GATE
# Validates all deliverables have explicit disposition decisions
# =============================================================================

TICKET_PATH="${SDD_ROOT_DIR:-/app/.sdd}/tickets/${TICKET_ID}"
DELIVERABLES_DIR="${TICKET_PATH}/deliverables"
SDD_ROOT="${SDD_ROOT_DIR:-/app/.sdd}"

# Detect non-interactive mode
NON_INTERACTIVE=false
if [ "$ARCHIVE_NON_INTERACTIVE" = "true" ] || [ "$ARCHIVE_NON_INTERACTIVE" = "1" ]; then
    NON_INTERACTIVE=true
fi
# Also check for --non-interactive argument (passed via $ARGUMENTS or explicit)
if [[ "$*" == *"--non-interactive"* ]]; then
    NON_INTERACTIVE=true
fi

# -----------------------------------------------------------------------------
# Step 1: Check if deliverables exist
# -----------------------------------------------------------------------------
deliverable_files=$(find "$DELIVERABLES_DIR" -maxdepth 1 -type f -name "*.md" ! -name "MANIFEST.md" 2>/dev/null)

if [ -z "$deliverable_files" ]; then
    echo "No deliverables to review. Skipping disposition gate."
    # Gate passes - no deliverables to review
    exit 0
fi

# Check if deliverables folder exists
if [ ! -d "$DELIVERABLES_DIR" ]; then
    echo "No deliverables folder. Skipping disposition gate."
    # Gate passes - no deliverables folder
    exit 0
fi

# -----------------------------------------------------------------------------
# Step 2: Collect disposition data from task files and plan.md
# -----------------------------------------------------------------------------
declare -A dispositions  # Map: deliverable_name -> disposition

# 2a. Parse task files for disposition tables
for task_file in "${TICKET_PATH}"/tasks/*.md; do
    [ -f "$task_file" ] || continue
    parse_task_deliverables "$task_file"
done

# 2b. Fallback to plan.md if not in tasks
if [ -f "${TICKET_PATH}/planning/plan.md" ]; then
    parse_plan_deliverables "${TICKET_PATH}/planning/plan.md"
fi

# -----------------------------------------------------------------------------
# Step 3: Detect ticket format (old vs new)
# Old format: No dispositions anywhere (backwards compatibility mode)
# New format: At least one disposition present (strict validation)
# -----------------------------------------------------------------------------
has_any_disposition=false
for deliv in $deliverable_files; do
    basename_deliv=$(basename "$deliv")
    if [ -n "${dispositions[$basename_deliv]}" ]; then
        has_any_disposition=true
        break
    fi
done

# -----------------------------------------------------------------------------
# Step 4: Process each deliverable
# -----------------------------------------------------------------------------
all_dispositions_valid=true
declare -A final_dispositions
missing_dispositions=()

for deliv_path in $deliverable_files; do
    deliv_name=$(basename "$deliv_path")

    # Check if disposition exists
    disposition="${dispositions[$deliv_name]}"

    if [ -z "$disposition" ]; then
        if [ "$has_any_disposition" = true ]; then
            # NEW FORMAT: Some have disposition, this one missing
            if [ "$NON_INTERACTIVE" = true ]; then
                # Non-interactive mode: collect missing and fail at end
                missing_dispositions+=("$deliv_name")
                all_dispositions_valid=false
                continue
            fi

            echo ""
            echo "ERROR: Deliverable '$deliv_name' missing disposition."
            echo "Please add disposition to plan.md or task file:"
            echo "  extract: <destination>  - Copy to permanent location"
            echo "  archive                 - Archive with ticket"
            echo "  external: <description> - Placed externally"
            echo ""

            # Prompt for disposition with validation retry
            retry_count=0
            while [ $retry_count -lt 3 ]; do
                read -p "Enter disposition for $deliv_name: " disposition

                if validate_disposition_format "$disposition"; then
                    # Additional validation for extract paths
                    if [[ "$disposition" =~ ^extract: ]]; then
                        extract_path=$(echo "$disposition" | sed 's/^extract:[[:space:]]*//')
                        if ! validate_extraction_path "$extract_path"; then
                            ((retry_count++))
                            continue
                        fi
                    fi
                    break
                fi
                ((retry_count++))
            done

            if [ $retry_count -ge 3 ]; then
                echo "ERROR: Too many invalid inputs. Please fix dispositions in plan.md or task files."
                all_dispositions_valid=false
                continue
            fi
        else
            # OLD FORMAT: No dispositions at all - backwards compatibility
            if [ "$NON_INTERACTIVE" = true ]; then
                # Non-interactive mode: default to archive for old format
                echo "WARNING: Ticket uses old format. Defaulting '$deliv_name' to 'archive' for backwards compatibility."
                disposition="archive"
            else
                echo ""
                echo "WARNING: Ticket uses old format (no disposition metadata)"
                echo "Deliverable: $deliv_name"
                read -p "Add disposition now? (extract:/archive/external:/skip) " disposition

                if [ "$disposition" = "skip" ]; then
                    disposition="archive"  # Default for old tickets
                    echo "Defaulting to 'archive' for backwards compatibility"
                elif ! validate_disposition_format "$disposition"; then
                    echo "Invalid format. Defaulting to 'archive'"
                    disposition="archive"
                fi
            fi
        fi
    fi

    # Validate disposition format (for dispositions from files)
    if ! validate_disposition_format "$disposition" 2>/dev/null; then
        echo "ERROR: Invalid disposition format for $deliv_name: '$disposition'"
        all_dispositions_valid=false
        continue
    fi

    # Validate extraction path security if extract type
    if [[ "$disposition" =~ ^extract: ]]; then
        extract_path=$(echo "$disposition" | sed 's/^extract:[[:space:]]*//')
        if ! validate_extraction_path "$extract_path"; then
            echo "ERROR: Invalid extraction path for $deliv_name: '$extract_path'"
            all_dispositions_valid=false
            continue
        fi
    fi

    final_dispositions[$deliv_name]="$disposition"
done

# -----------------------------------------------------------------------------
# Step 5: Non-interactive mode error handling
# -----------------------------------------------------------------------------
if [ "$NON_INTERACTIVE" = true ] && [ ${#missing_dispositions[@]} -gt 0 ]; then
    echo ""
    echo "ERROR: Cannot archive in non-interactive mode. Missing dispositions: ${missing_dispositions[*]}."
    echo "Fix these in plan.md or task files before re-running."
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 6: Gate decision
# -----------------------------------------------------------------------------
if [ "$all_dispositions_valid" = false ]; then
    echo ""
    echo "ARCHIVE BLOCKED: Fix disposition issues above before archiving"
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 7: Process "extract" dispositions - require user confirmation
# -----------------------------------------------------------------------------
for deliv_name in "${!final_dispositions[@]}"; do
    disposition="${final_dispositions[$deliv_name]}"

    if [[ "$disposition" =~ ^extract: ]]; then
        extract_path=$(echo "$disposition" | sed 's/^extract:[[:space:]]*//')

        if [ "$NON_INTERACTIVE" = true ]; then
            echo "WARNING: Non-interactive mode - assuming extract confirmed for $deliv_name -> $extract_path"
            # Log extraction
            mkdir -p "$SDD_ROOT/logs"
            echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")|DELIVERABLE_EXTRACTED|$TICKET_ID|$deliv_name|extract|destination=$extract_path" >> "$SDD_ROOT/logs/workflow.log"
        else
            echo ""
            echo "ACTION REQUIRED: Extract $deliv_name"
            echo "  Source: $DELIVERABLES_DIR/$deliv_name"
            echo "  Destination: $extract_path"
            echo ""
            read -p "Have you copied this file to the destination? (yes/no) " confirmed

            if [[ "$confirmed" != "yes" && "$confirmed" != "y" ]]; then
                echo ""
                echo "Please extract the file before archiving."
                echo "You can run: cp \"$DELIVERABLES_DIR/$deliv_name\" \"$extract_path\""
                exit 1
            fi

            # Log extraction
            mkdir -p "$SDD_ROOT/logs"
            echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")|DELIVERABLE_EXTRACTED|$TICKET_ID|$deliv_name|extract|destination=$extract_path" >> "$SDD_ROOT/logs/workflow.log"
        fi
    elif [ "$disposition" = "archive" ]; then
        # Log archive
        mkdir -p "$SDD_ROOT/logs"
        echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")|DELIVERABLE_ARCHIVED|$TICKET_ID|$deliv_name|archive|Archived with ticket" >> "$SDD_ROOT/logs/workflow.log"
    elif [[ "$disposition" =~ ^external: ]]; then
        external_desc=$(echo "$disposition" | sed 's/^external:[[:space:]]*//')
        # Log external
        mkdir -p "$SDD_ROOT/logs"
        echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")|DELIVERABLE_EXTERNAL|$TICKET_ID|$deliv_name|external|location=\"$external_desc\"" >> "$SDD_ROOT/logs/workflow.log"
    fi
done

# -----------------------------------------------------------------------------
# Step 8: Generate MANIFEST.md
# -----------------------------------------------------------------------------
generate_manifest "$DELIVERABLES_DIR/MANIFEST.md" final_dispositions "$TICKET_ID"

echo ""
echo "All deliverables processed. Disposition decisions recorded in MANIFEST.md."
echo "Archive may proceed."
```

#### User Interaction Flows

**Flow 1: New ticket, all dispositions present**
- Gate runs and finds dispositions for all deliverables
- Validates formats and paths
- Prompts for extraction confirmation if any "extract:" dispositions
- Generates MANIFEST.md
- **RESULT: PASS**

**Flow 2: New ticket, missing disposition**
- Gate runs and detects some dispositions exist (new format)
- Finds deliverable without disposition
- **PROMPTS:** "ERROR: Deliverable '<name>' missing disposition..."
- User enters disposition (up to 3 retries for invalid input)
- Validates format
- **RESULT: PASS (if all valid) or BLOCK (if invalid after retries)**

**Flow 3: Old ticket, no dispositions**
- Gate runs and detects no dispositions anywhere (old format)
- **WARNS:** "WARNING: Ticket uses old format (no disposition metadata)"
- For each deliverable: **PROMPTS:** "Add disposition now? (extract:/archive/external:/skip)"
- User enters or skips (skip defaults to "archive")
- Generates MANIFEST.md
- **RESULT: PASS**

**Flow 4: Extract confirmation**
- Gate finds disposition: "extract: docs/decisions/"
- **PROMPTS:** "Have you copied this file to the destination? (yes/no)"
- User responds:
  - "yes" or "y" -> Logs extraction event, continues
  - "no" or anything else -> **BLOCKS** with message and suggested cp command

**Flow 5: Non-interactive mode**
- Detected via `ARCHIVE_NON_INTERACTIVE=true` env var or `--non-interactive` argument
- Validation runs but fails immediately if issues found
- Error message lists all missing/invalid dispositions
- **RESULT: BLOCK with actionable error message**

#### Edge Cases

| Scenario | Behavior |
|----------|----------|
| No deliverables folder | Gate passes - nothing to review |
| Empty deliverables folder | Gate passes - no .md files found |
| Only MANIFEST.md exists | Gate passes - MANIFEST.md excluded from review |
| Mixed old/new format | If ANY disposition found, treats as new format (strict) |
| Invalid path characters | Rejected with specific error message |
| Path traversal attempt | Rejected: "Path traversal not allowed" |

### Step 5.6: Skill Curation Opportunity

After reviewing deliverables, consider whether this ticket produced reusable patterns worth capturing as repo-local skills.

**Check for skill candidates:**
1. Run list-skills.sh to see existing skills:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/skill-curation/scripts/list-skills.sh
   ```
   If list-skills.sh fails, log a warning and continue (non-blocking).

2. Prompt the user using AskUserQuestion:
   > This ticket has been completed and reviewed. Would you like to curate repo-local skills from this ticket's learnings?
   >
   > Repo-local skills help future tickets by capturing repo-specific patterns, conventions, and procedures.
   >
   > **Options:**
   > - `yes` - Analyze this ticket for skill candidates (delegated to skill-curator agent)
   > - `no` - Skip skill curation and proceed to archive
   > - `defer` - Curate later with `/sdd:curate-skills TICKET_ID`

3. **If user responds "yes":**
   - Delegate to skill-curator agent
   - Agent analyzes ticket artifacts and creates skills
   - Agent reports created/updated skills
   - Continue to Step 6

4. **If user responds "no" or "defer":**
   - Continue to Step 6 (no curation)
   - If "defer", remind user they can run `/sdd:curate-skills TICKET_ID` later

5. **Error handling:**
   - If list-skills.sh fails, log warning and continue (non-blocking)
   - If skill-curator agent fails, log error and continue (curation is optional)

### Step 6: Archive

For each fully verified ticket:

```bash
mv ${SDD_ROOT_DIR:-/app/.sdd}/tickets/{TICKET_ID}_{name}/ ${SDD_ROOT_DIR:-/app/.sdd}/archive/tickets/
```

### Step 7: Update References

Search for references to archived ticket:
```bash
grep -r "tickets/${TICKET_ID}" ${SDD_ROOT_DIR:-/app/.sdd}/ docs/
```

Update paths from `tickets/` to `archive/tickets/`.

### Step 8: Log Archival

For each archived ticket, log the event:

```bash
SDD_ROOT="${SDD_ROOT_DIR:-/app/.sdd}"
mkdir -p "$SDD_ROOT/logs"
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")|TICKET_ARCHIVED|{TICKET_ID}|-|archive|Completed, {X}/{X} tasks verified" >> "$SDD_ROOT/logs/workflow.log"
```

### Step 9: Collect Metrics

After archiving, collect and log metrics snapshot:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/scripts/collect-metrics.sh" --log
```

This captures the current state of all tickets and tickets to `{{SDD_ROOT}}/logs/metrics.log` for trend analysis.

### Step 10: Report

```
ARCHIVE REVIEW

Tickets Reviewed: {count}

ARCHIVED:
✓ {TICKET_ID1}_{name}: All {count} tasks verified - Archived
✓ {TICKET_ID2}_{name}: All {count} tasks verified - Archived

NOT ARCHIVED:
✗ {TICKET_ID3}_{name}: {X}/{Y} tasks verified - Incomplete
  Missing verification: {TICKET_ID3}.2003, {TICKET_ID3}.2004

RECOMMENDATIONS:
• Complete work on {TICKET_ID3} before archiving
• Run /sdd:do-all-tasks {TICKET_ID3} to finish remaining tasks

References Updated: {count} files
```

### Next Step Prompt

After displaying the report above, use the **AskUserQuestion** tool to present next steps to the user:

**Question:** "What would you like to do next?"
**Header:** "Next step"
**multiSelect:** false

**Options:**
- Label: "/sdd:plan-ticket" | Description: "Create a new ticket"
- Label: "/sdd:status" | Description: "Check current status across tickets and epics"
- Label: "/sdd:start-epic" | Description: "Start working on an epic"

## Archive Criteria

**Archive if ALL true:**
- ALL tasks have `- [x] **Verified**` checkbox
- No active development planned
- Knowledge extracted (if applicable)

**Do NOT archive if ANY true:**
- Any task has unchecked Verified
- Active development continuing
- Blocking other tickets

## Key Constraints

- Source of truth: Verified checkbox in task files
- Do NOT archive partially complete tickets
- Update references before moving
- Use scripts for scanning (don't read files manually)
