---
description: |
  Create follow-up tasks mid-cycle from multiple input sources: code review findings,
  PR feedback comments, or user-provided instructions. Enables task creation after
  initial planning when new requirements emerge.

  Parses structured deliverables (code-review-report.md, pr-comments-analysis.md),
  applies severity filtering, assigns agents based on keywords, and delegates to
  task-creator for systematic task generation.

  Usage examples:
  - From user input: /sdd:extend TICKET "Add caching layer to API endpoints"
  - From code review: /sdd:extend TICKET --from-review --min-severity HIGH
  - From PR comments: /sdd:extend TICKET --from-pr-comments
  - Combined sources: /sdd:extend TICKET --from-review --from-pr-comments --max 5
  - With limits: /sdd:extend TICKET --from-review --max 5
  - Dry run: /sdd:extend TICKET --from-review --dry-run
  - Interactive: /sdd:extend TICKET --from-review --interactive
  - With agent: /sdd:extend TICKET --from-review --default-agent security-reviewer
  - With relationship: /sdd:extend TICKET --from-review --related-to TICKET.1003
argument-hint: TICKET_ID [--from-review] [--from-pr-comments] [--min-severity LEVEL] [--max N] [--dry-run] [--interactive] [--default-agent NAME] [--related-to TASK_ID] ["user instructions"]
---

# Extend Ticket with Follow-up Tasks

## Context

User input: "$ARGUMENTS"
Ticket folder: `${SDD_ROOT_DIR}/tickets/${TICKET_ID}_*/`

## Workflow

**IMPORTANT: You are an orchestrator. You do NOT create tasks yourself. You delegate to the task-creator agent.**

### Step 0: Parse Arguments

Extract from `$ARGUMENTS`:
- **TICKET_ID**: The ticket identifier (required, first non-flag argument)
- **--from-review**: Boolean flag to parse code review report
- **--from-pr-comments**: Boolean flag to parse PR comments analysis
- **--min-severity LEVEL**: Minimum severity to include (CRITICAL, HIGH, MEDIUM, NITPICK)
- **--max N**: Maximum number of tasks to create (default: 10, accepts 'unlimited')
- **--dry-run**: Boolean flag to preview tasks without creating them
- **--interactive**: Boolean flag to prompt for each task
- **--default-agent NAME**: Override agent assignment for all tasks
- **--related-to TASK_ID**: Link tasks to a related task
- **"user instructions"**: Quoted string with task description

**Parsing logic**:
```bash
# Initialize variables
TICKET_ID=""
FROM_REVIEW=false
FROM_PR_COMMENTS=false
MIN_SEVERITY="NITPICK"  # Default: include all
MAX_TASKS=10
DRY_RUN=false
INTERACTIVE=false
DEFAULT_AGENT=""
RELATED_TO=""
USER_INSTRUCTIONS=""
QUOTED_COUNT=0

# Parse arguments
args=($ARGUMENTS)
i=0
while [ $i -lt ${#args[@]} ]; do
  arg="${args[$i]}"

  case "$arg" in
    --from-review)
      FROM_REVIEW=true
      ;;
    --from-pr-comments)
      FROM_PR_COMMENTS=true
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    --interactive)
      INTERACTIVE=true
      ;;
    --min-severity)
      i=$((i + 1))
      MIN_SEVERITY="${args[$i]}"
      ;;
    --max)
      i=$((i + 1))
      MAX_TASKS="${args[$i]}"
      ;;
    --default-agent)
      i=$((i + 1))
      DEFAULT_AGENT="${args[$i]}"
      ;;
    --related-to)
      i=$((i + 1))
      RELATED_TO="${args[$i]}"
      ;;
    \"*\")
      # Quoted string - extract as user instructions
      QUOTED_COUNT=$((QUOTED_COUNT + 1))
      # Remove quotes
      USER_INSTRUCTIONS="${arg:1:${#arg}-2}"
      ;;
    *)
      # First non-flag argument is TICKET_ID
      if [[ -z "$TICKET_ID" && ! "$arg" =~ ^- ]]; then
        TICKET_ID="$arg"
      elif [[ ! "$arg" =~ ^- ]]; then
        # Unquoted text after TICKET_ID - error
        echo "ERROR: User instructions must be quoted"
        echo ""
        echo "Usage: /sdd:extend TICKET_ID \"your instructions here\""
        echo ""
        echo "Received unquoted text: $arg"
        exit 1
      fi
      ;;
  esac

  i=$((i + 1))
done

# Validate quoted strings
if [ $QUOTED_COUNT -gt 1 ]; then
  echo "ERROR: Multiple quoted strings provided"
  echo ""
  echo "Usage: /sdd:extend TICKET_ID \"single quoted instruction\""
  echo ""
  echo "Combine multiple instructions into one quoted string."
  exit 1
fi
```

### Step 1: Validate Arguments

**1. Validate TICKET_ID format**:
```bash
if [[ -z "$TICKET_ID" ]]; then
  echo "ERROR: TICKET_ID is required"
  echo ""
  echo "Usage: /sdd:extend TICKET_ID [options]"
  echo ""
  echo "Examples:"
  echo "  /sdd:extend MYTICKET \"Add error handling\""
  echo "  /sdd:extend MYTICKET --from-review --min-severity HIGH"
  exit 1
fi

# Validate format: ^[A-Z][A-Z0-9_-]*$
if [[ ! "$TICKET_ID" =~ ^[A-Z][A-Z0-9_-]*$ ]]; then
  echo "ERROR: Invalid TICKET_ID format: $TICKET_ID"
  echo ""
  echo "TICKET_ID must:"
  echo "  - Start with uppercase letter (A-Z)"
  echo "  - Contain only uppercase letters, numbers, underscores, hyphens"
  echo ""
  echo "Valid examples: TICKET, API-123, AUTH_V2"
  echo "Invalid examples: ticket, 123API, Ticket-1"
  exit 1
fi
```

**2. Validate at least one source**:
```bash
if [[ "$FROM_REVIEW" = false && "$FROM_PR_COMMENTS" = false && -z "$USER_INSTRUCTIONS" ]]; then
  echo "ERROR: No input source provided"
  echo ""
  echo "Provide at least one of:"
  echo "  - User instructions: \"your task description\""
  echo "  - Code review: --from-review"
  echo "  - PR comments: --from-pr-comments"
  echo ""
  echo "Examples:"
  echo "  /sdd:extend TICKET \"Add caching\""
  echo "  /sdd:extend TICKET --from-review"
  echo "  /sdd:extend TICKET --from-pr-comments"
  echo "  /sdd:extend TICKET --from-review --from-pr-comments"
  exit 1
fi
```

**3. Validate --min-severity**:
```bash
if [[ -n "$MIN_SEVERITY" ]]; then
  case "$MIN_SEVERITY" in
    CRITICAL|HIGH|MEDIUM|NITPICK)
      # Valid
      ;;
    *)
      echo "ERROR: Invalid --min-severity value: $MIN_SEVERITY"
      echo ""
      echo "Valid options: CRITICAL, HIGH, MEDIUM, NITPICK"
      echo ""
      echo "Usage: /sdd:extend TICKET --from-review --min-severity HIGH"
      exit 1
      ;;
  esac
fi
```

**4. Validate --max**:
```bash
if [[ "$MAX_TASKS" != "unlimited" && ! "$MAX_TASKS" =~ ^[0-9]+$ ]]; then
  echo "ERROR: Invalid --max value: $MAX_TASKS"
  echo ""
  echo "Must be a positive integer or 'unlimited'"
  echo ""
  echo "Examples:"
  echo "  /sdd:extend TICKET --from-review --max 5"
  echo "  /sdd:extend TICKET --from-review --max unlimited"
  exit 1
fi

if [[ "$MAX_TASKS" =~ ^[0-9]+$ && $MAX_TASKS -lt 1 ]]; then
  echo "ERROR: --max must be at least 1"
  exit 1
fi
```

**5. Validate --related-to format** (if provided):
```bash
if [[ -n "$RELATED_TO" && ! "$RELATED_TO" =~ ^[A-Z][A-Z0-9_-]*\.[0-9]{4}$ ]]; then
  echo "ERROR: Invalid --related-to format: $RELATED_TO"
  echo ""
  echo "Expected format: TICKET_ID.NNNN (e.g., MYTICKET.1001)"
  exit 1
fi
```

### Step 2: Locate Ticket

Find the ticket folder:
```bash
SDD_ROOT="${SDD_ROOT_DIR:-/app/.sdd}"
TICKET_PATH=$(ls -d "$SDD_ROOT/tickets/${TICKET_ID}_"* 2>/dev/null | head -1)

if [[ -z "$TICKET_PATH" ]]; then
  echo "ERROR: Ticket $TICKET_ID not found"
  echo ""
  echo "Expected location: $SDD_ROOT/tickets/${TICKET_ID}_*"
  echo ""
  echo "Actions:"
  echo "  1. Verify ticket ID is correct"
  echo "  2. Check available tickets: /sdd:tasks-status"
  echo "  3. Create ticket if needed: /sdd:plan-ticket"
  exit 1
fi

echo "✓ Ticket found: $TICKET_PATH"
```

### Step 3: Detect Next Phase

**Phase detection with gap handling**:
```bash
# List existing task files
existing_tasks=$(ls "$TICKET_PATH/tasks/${TICKET_ID}".*.md 2>/dev/null || echo "")

if [[ -z "$existing_tasks" ]]; then
  # No tasks exist - start with phase 1
  NEXT_PHASE=1
  echo "No existing tasks - starting with Phase 1"
else
  # Extract phase numbers from filenames
  phases=$(echo "$existing_tasks" | grep -oP "${TICKET_ID}\.\K[0-9]" | sort -u)

  # Find highest phase
  highest_phase=$(echo "$phases" | tail -1)
  NEXT_PHASE=$((highest_phase + 1))

  # Check for gaps
  expected_sequence=$(seq 1 $highest_phase)
  missing_phases=$(comm -23 <(echo "$expected_sequence") <(echo "$phases"))

  if [[ -n "$missing_phases" ]]; then
    echo "⚠️  WARNING: Phase gap detected"
    echo ""
    echo "Existing phases: $(echo $phases | tr '\n' ' ')"
    echo "Missing phases: $(echo $missing_phases | tr '\n' ' ')"
    echo ""
    echo "This may indicate incomplete planning or previous task deletion."
    echo "New tasks will be created in Phase $NEXT_PHASE."
    echo ""
    read -p "Continue? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "Cancelled by user"
      exit 0
    fi
  fi

  echo "Next phase: $NEXT_PHASE (following phase $highest_phase)"
fi
```

### Step 4: Parse Input Sources

**A. Parse code review findings** (if --from-review):
```bash
if [[ "$FROM_REVIEW" = true ]]; then
  REVIEW_FILE="$TICKET_PATH/deliverables/code-review-report.md"

  if [[ ! -f "$REVIEW_FILE" ]]; then
    echo "ERROR: Code review report not found"
    echo ""
    echo "Expected location: $REVIEW_FILE"
    echo ""
    echo "Actions:"
    echo "  1. Run code review: /sdd:code-review $TICKET_ID"
    echo "  2. Verify deliverables directory exists"
    exit 1
  fi

  echo "Parsing code review report..."

  # Parse Section 12.2 recommendations by severity
  # Look for h4 headers: #### CRITICAL, #### HIGH, #### MEDIUM, #### NITPICK
  # Extract checkbox items: - [ ] **Title**: description - file (line X) - action

  # This is complex parsing - delegate to a structured approach
  # For now, collect findings into arrays by severity

  declare -a CRITICAL_FINDINGS
  declare -a HIGH_FINDINGS
  declare -a MEDIUM_FINDINGS
  declare -a NITPICK_FINDINGS

  # Read file and parse by severity sections
  current_severity=""
  while IFS= read -r line; do
    # Detect severity headers
    if [[ "$line" =~ ^####[[:space:]]+CRITICAL ]]; then
      current_severity="CRITICAL"
    elif [[ "$line" =~ ^####[[:space:]]+HIGH ]]; then
      current_severity="HIGH"
    elif [[ "$line" =~ ^####[[:space:]]+MEDIUM ]]; then
      current_severity="MEDIUM"
    elif [[ "$line" =~ ^####[[:space:]]+NITPICK ]]; then
      current_severity="NITPICK"
    fi

    # Parse checkbox items
    if [[ "$line" =~ ^-[[:space:]]\[[[:space:]]\][[:space:]]\*\*(.+)\*\*:[[:space:]](.+) ]]; then
      title="${BASH_REMATCH[1]}"
      rest="${BASH_REMATCH[2]}"

      # Store finding with severity
      finding="$title|$rest"

      case "$current_severity" in
        CRITICAL)
          CRITICAL_FINDINGS+=("$finding")
          ;;
        HIGH)
          HIGH_FINDINGS+=("$finding")
          ;;
        MEDIUM)
          MEDIUM_FINDINGS+=("$finding")
          ;;
        NITPICK)
          NITPICK_FINDINGS+=("$finding")
          ;;
      esac
    fi
  done < "$REVIEW_FILE"

  # Apply severity filter (inclusive)
  declare -a FILTERED_FINDINGS
  case "$MIN_SEVERITY" in
    CRITICAL)
      FILTERED_FINDINGS=("${CRITICAL_FINDINGS[@]}")
      ;;
    HIGH)
      FILTERED_FINDINGS=("${CRITICAL_FINDINGS[@]}" "${HIGH_FINDINGS[@]}")
      ;;
    MEDIUM)
      FILTERED_FINDINGS=("${CRITICAL_FINDINGS[@]}" "${HIGH_FINDINGS[@]}" "${MEDIUM_FINDINGS[@]}")
      ;;
    NITPICK)
      FILTERED_FINDINGS=("${CRITICAL_FINDINGS[@]}" "${HIGH_FINDINGS[@]}" "${MEDIUM_FINDINGS[@]}" "${NITPICK_FINDINGS[@]}")
      ;;
  esac

  echo "Found ${#FILTERED_FINDINGS[@]} findings after filtering (>= $MIN_SEVERITY)"

  if [[ ${#FILTERED_FINDINGS[@]} -eq 0 ]]; then
    echo "No findings match severity filter. Exiting."
    exit 0
  fi
fi
```

**B. Parse PR comments** (if --from-pr-comments):
```bash
if [[ "$FROM_PR_COMMENTS" = true ]]; then
  PR_COMMENTS_FILE="$TICKET_PATH/deliverables/pr-comments-analysis.md"

  if [[ ! -f "$PR_COMMENTS_FILE" ]]; then
    echo "ERROR: PR comments analysis not found"
    echo ""
    echo "Expected location: $PR_COMMENTS_FILE"
    echo ""
    echo "Actions:"
    echo "  1. Run PR comments analysis: /sdd:pr-comments PR_NUMBER $TICKET_ID"
    echo "  2. Verify deliverables directory exists"
    exit 1
  fi

  echo "Parsing PR comments analysis..."

  # Parse ## COMPLEX Comments section
  # Look for h3 headers: ### COMPLEX-{N}: {description}
  # Extract fields:
  #   - **Author:** @reviewer
  #   - **Location:** file:line (optional)
  #   - **Comment:** quote block (optional)
  #   - **Recommended Task:** task title (required)
  #   - **Task Context:** additional context (optional)

  declare -a PR_COMMENT_FINDINGS

  # Read file and parse COMPLEX Comments section
  in_complex_section=false
  in_comment_item=false
  current_title=""
  current_author=""
  current_location=""
  current_recommendation=""
  current_context=""

  while IFS= read -r line; do
    # Detect COMPLEX Comments section
    if [[ "$line" =~ ^##[[:space:]]+COMPLEX[[:space:]]+Comments ]]; then
      in_complex_section=true
      continue
    fi

    # Exit COMPLEX section if we hit another ## header or metadata
    if [[ "$in_complex_section" = true && "$line" =~ ^##[[:space:]] && ! "$line" =~ COMPLEX ]]; then
      in_complex_section=false
      break
    fi

    if [[ "$in_complex_section" = true ]]; then
      # Detect new COMPLEX item
      if [[ "$line" =~ ^###[[:space:]]+COMPLEX-[0-9]+:[[:space:]](.+) ]]; then
        # Save previous item if exists
        if [[ -n "$current_author" && -n "$current_recommendation" ]]; then
          # Store finding: title|author|location|recommendation|context
          finding="$current_title|$current_author|$current_location|$current_recommendation|$current_context"
          PR_COMMENT_FINDINGS+=("$finding")
        elif [[ -n "$current_title" ]]; then
          # Warn about malformed item (missing required fields)
          echo "⚠️  WARNING: Skipping malformed item '$current_title' - missing required fields (author or recommendation)"
        fi

        # Start new item
        current_title="${BASH_REMATCH[1]}"
        current_author=""
        current_location=""
        current_recommendation=""
        current_context=""
        in_comment_item=true
        continue
      fi

      # Parse item fields
      if [[ "$in_comment_item" = true ]]; then
        # Author field
        if [[ "$line" =~ ^\*\*Author:\*\*[[:space:]]+(.+)$ ]]; then
          current_author="${BASH_REMATCH[1]}"
          # Remove @ prefix if present
          current_author="${current_author#@}"
        fi

        # Location field (optional)
        if [[ "$line" =~ ^\*\*Location:\*\*[[:space:]]+(.+)$ ]]; then
          current_location="${BASH_REMATCH[1]}"
        fi

        # Recommended Task header (content on next lines)
        if [[ "$line" =~ ^\*\*Recommended[[:space:]]Task:\*\*$ ]]; then
          # Read next non-empty line as recommendation
          read -r next_line
          if [[ -n "$next_line" && ! "$next_line" =~ ^---$ ]]; then
            current_recommendation="$next_line"
          fi
        fi

        # Task Context header (content on next lines)
        if [[ "$line" =~ ^\*\*Task[[:space:]]Context:\*\*$ ]]; then
          # Read next non-empty line as context
          read -r next_line
          if [[ -n "$next_line" && ! "$next_line" =~ ^---$ ]]; then
            current_context="$next_line"
          fi
        fi

        # End of item (separator or next item)
        if [[ "$line" =~ ^---$ ]]; then
          in_comment_item=false
        fi
      fi
    fi
  done < "$PR_COMMENTS_FILE"

  # Save last item if exists
  if [[ -n "$current_author" && -n "$current_recommendation" ]]; then
    finding="$current_title|$current_author|$current_location|$current_recommendation|$current_context"
    PR_COMMENT_FINDINGS+=("$finding")
  elif [[ -n "$current_title" ]]; then
    # Warn about malformed last item
    echo "⚠️  WARNING: Skipping malformed item '$current_title' - missing required fields (author or recommendation)"
  fi

  echo "Found ${#PR_COMMENT_FINDINGS[@]} complex PR comments"

  if [[ ${#PR_COMMENT_FINDINGS[@]} -eq 0 ]]; then
    echo "No complex comments found in analysis. Exiting."
    exit 0
  fi
fi
```

**C. Prepare user instructions** (if provided):
```bash
if [[ -n "$USER_INSTRUCTIONS" ]]; then
  echo "User instructions: $USER_INSTRUCTIONS"
  # User instructions become a single task
  declare -a USER_TASKS
  USER_TASKS=("$USER_INSTRUCTIONS")
fi
```

### Step 5: Combine and Limit Tasks

**Merge all sources with priority sorting and apply --max limit**:
```bash
# Combine all task sources with priority
# Priority order: user input (CRITICAL) > code review (by severity) > PR comments (MEDIUM)
# Format: priority|severity|source|data

declare -a PRIORITIZED_TASKS

# Add user instructions first (highest priority)
if [[ -n "$USER_INSTRUCTIONS" ]]; then
  for task_data in "${USER_TASKS[@]}"; do
    # Priority 0 = highest, severity CRITICAL, source user-input
    PRIORITIZED_TASKS+=("0|CRITICAL|user-input|$task_data")
  done
fi

# Add code review findings by severity
if [[ "$FROM_REVIEW" = true ]]; then
  # CRITICAL findings (priority 1)
  for finding in "${CRITICAL_FINDINGS[@]}"; do
    PRIORITIZED_TASKS+=("1|CRITICAL|code-review|$finding")
  done

  # HIGH findings (priority 2)
  for finding in "${HIGH_FINDINGS[@]}"; do
    PRIORITIZED_TASKS+=("2|HIGH|code-review|$finding")
  done

  # MEDIUM findings (priority 3)
  for finding in "${MEDIUM_FINDINGS[@]}"; do
    PRIORITIZED_TASKS+=("3|MEDIUM|code-review|$finding")
  done

  # NITPICK findings (priority 4)
  for finding in "${NITPICK_FINDINGS[@]}"; do
    PRIORITIZED_TASKS+=("4|NITPICK|code-review|$finding")
  done
fi

# Add PR comments (all MEDIUM priority, priority 3)
if [[ "$FROM_PR_COMMENTS" = true ]]; then
  for finding in "${PR_COMMENT_FINDINGS[@]}"; do
    PRIORITIZED_TASKS+=("3|MEDIUM|pr-comments|$finding")
  done
fi

# Sort by priority (first field)
IFS=$'\n' SORTED_TASKS=($(sort -t'|' -k1,1n <<<"${PRIORITIZED_TASKS[*]}"))
unset IFS

TOTAL_TASKS=${#SORTED_TASKS[@]}

# Apply --max limit AFTER combining all sources
if [[ "$MAX_TASKS" != "unlimited" && $TOTAL_TASKS -gt $MAX_TASKS ]]; then
  echo "⚠️  Limiting to $MAX_TASKS tasks (total available: $TOTAL_TASKS)"
  SORTED_TASKS=("${SORTED_TASKS[@]:0:$MAX_TASKS}")
  TOTAL_TASKS=$MAX_TASKS
fi

echo "Tasks to create: $TOTAL_TASKS"
echo ""

# Display source breakdown
user_count=0
review_count=0
pr_count=0
for task in "${SORTED_TASKS[@]}"; do
  source=$(echo "$task" | cut -d'|' -f3)
  case "$source" in
    user-input) user_count=$((user_count + 1)) ;;
    code-review) review_count=$((review_count + 1)) ;;
    pr-comments) pr_count=$((pr_count + 1)) ;;
  esac
done

echo "Source breakdown:"
if [[ $user_count -gt 0 ]]; then
  echo "  User input: $user_count"
fi
if [[ $review_count -gt 0 ]]; then
  echo "  Code review: $review_count"
fi
if [[ $pr_count -gt 0 ]]; then
  echo "  PR comments: $pr_count"
fi
echo ""
```

### Step 6: Token Cost Warning

**Display token warning for >5 tasks**:
```bash
if [[ $TOTAL_TASKS -gt 5 && "$DRY_RUN" = false ]]; then
  estimated_tokens=$((TOTAL_TASKS * 3000))
  estimated_k=$((estimated_tokens / 1000))

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "TOKEN COST WARNING"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Creating $TOTAL_TASKS tasks (~${estimated_k}k tokens)"
  echo ""
  echo "Estimated cost: $TOTAL_TASKS tasks × 3k tokens = ~${estimated_k}k tokens"
  echo ""

  read -p "Continue? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled by user"
    echo ""
    echo "Consider using --max N to limit task count:"
    echo "  /sdd:extend $TICKET_ID --from-review --max 5"
    exit 0
  fi
fi
```

### Step 7: Delegate Task Creation

**For each task, delegate to task-creator agent**:
```bash
echo ""
echo "Creating tasks..."
echo ""

declare -a CREATED_TASKS
declare -a FAILED_TASKS

task_num=1
for task_entry in "${SORTED_TASKS[@]}"; do
  # Parse prioritized task entry: priority|severity|source|data
  priority=$(echo "$task_entry" | cut -d'|' -f1)
  severity=$(echo "$task_entry" | cut -d'|' -f2)
  source=$(echo "$task_entry" | cut -d'|' -f3)
  task_data=$(echo "$task_entry" | cut -d'|' -f4-)

  # Parse task data based on source
  if [[ "$source" == "code-review" ]]; then
    # Code review finding: "Title|rest"
    title=$(echo "$task_data" | cut -d'|' -f1)
    description=$(echo "$task_data" | cut -d'|' -f2)
  elif [[ "$source" == "pr-comments" ]]; then
    # PR comment finding: "title|author|location|recommendation|context"
    title=$(echo "$task_data" | cut -d'|' -f1)
    author=$(echo "$task_data" | cut -d'|' -f2)
    location=$(echo "$task_data" | cut -d'|' -f3)
    recommendation=$(echo "$task_data" | cut -d'|' -f4)
    context=$(echo "$task_data" | cut -d'|' -f5)
    # Use recommendation as description, add author and location as context
    description="$recommendation"
    if [[ -n "$context" ]]; then
      description="$description. $context"
    fi
    if [[ -n "$author" ]]; then
      description="Suggested by $author. $description"
    fi
    if [[ -n "$location" ]]; then
      description="$description (Location: $location)"
    fi
  else
    # User instruction
    title="$task_data"
    description="$task_data"
  fi

  # Sanitize content (strip HTML, escape markdown)
  title=$(echo "$title" | sed 's/<[^>]*>//g' | sed 's/[*_`]//g')
  description=$(echo "$description" | sed 's/<[^>]*>//g')

  # Agent assignment
  if [[ -n "$DEFAULT_AGENT" ]]; then
    agent="$DEFAULT_AGENT"
  else
    # Keyword-based assignment
    lower_text=$(echo "$title $description" | tr '[:upper:]' '[:lower:]')
    if [[ "$lower_text" =~ security|vulnerability|injection|xss|csrf|auth ]]; then
      agent="security-reviewer"
    elif [[ "$lower_text" =~ performance|slow|cache|optimization|n\+1 ]]; then
      agent="performance-specialist"
    elif [[ "$lower_text" =~ test|coverage|testing|spec|assertion ]]; then
      agent="test-specialist"
    elif [[ "$lower_text" =~ documentation|docs|readme|comments|jsdoc ]]; then
      agent="documentation-specialist"
    else
      agent="general"
    fi
  fi

  # Format task ID
  task_id=$(printf "%s.%d%03d" "$TICKET_ID" "$NEXT_PHASE" "$task_num")

  if [[ "$DRY_RUN" = true ]]; then
    echo "[$task_num/$TOTAL_TASKS] DRY RUN: $task_id - $title"
    echo "  Agent: $agent"
    echo "  Source: $source"
    if [[ -n "$RELATED_TO" ]]; then
      echo "  Related: $RELATED_TO"
    fi
    echo ""
    CREATED_TASKS+=("$task_id: $title")
  elif [[ "$INTERACTIVE" = true ]]; then
    echo "[$task_num/$TOTAL_TASKS] Preview: $task_id"
    echo "  Title: $title"
    echo "  Agent: $agent"
    echo "  Source: $source"
    if [[ -n "$RELATED_TO" ]]; then
      echo "  Related: $RELATED_TO"
    fi
    echo ""
    read -p "Create this task? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "  Skipped"
      echo ""
      task_num=$((task_num + 1))
      continue
    fi

    # Delegate to task-creator agent (see delegation format below)
    echo "  Creating..."
    CREATED_TASKS+=("$task_id: $title")
    echo "  ✓ Created"
    echo ""
  else
    echo "[$task_num/$TOTAL_TASKS] Creating: $task_id - $title"

    # Delegate to task-creator agent (see delegation format below)
    CREATED_TASKS+=("$task_id: $title")
    echo "  ✓ Created"
  fi

  task_num=$((task_num + 1))
done
```

**For each task, delegate to task-creator agent using the Task tool with this format:**
```
Assignment: Create follow-up task for ticket {TICKET_ID}

Context:
- Ticket path: {TICKET_PATH}
- Phase number: {NEXT_PHASE}
- Primary agent: {agent}
- Related task: {RELATED_TO if provided, otherwise "None"}

Task Details:
- Title: {sanitized_title}
- Summary: {sanitized_description}
- Source: {code-review | user-input}
- Severity: {CRITICAL | HIGH | MEDIUM | NITPICK}
- Background: Follow-up from {source}. Original finding: {description}

Instructions:
1. Create task file: {TICKET_PATH}/tasks/{task_id}_{slug}.md
2. Use work-task-template.md format
3. Include acceptance criteria based on summary
4. Assign agent: {agent}
5. Note source in background section
6. Link to related task if provided
```

### Step 8: Update Task Index

**Update the task index file**:
```bash
if [[ "$DRY_RUN" = false && ${#CREATED_TASKS[@]} -gt 0 ]]; then
  TASK_INDEX="$TICKET_PATH/${TICKET_ID}_TASK_INDEX.md"

  # Append extended tasks section
  {
    echo ""
    echo "## Extended Tasks (Phase $NEXT_PHASE)"
    echo ""
    echo "Source: /sdd:extend command"
    echo "Created: $(date +%Y-%m-%d)"
    echo ""
    for task in "${CREATED_TASKS[@]}"; do
      echo "- $task"
    done
  } >> "$TASK_INDEX"

  echo "✓ Task index updated"
fi
```

### Step 9: Report Results

**Display summary**:
```bash
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "$DRY_RUN" = true ]]; then
  echo "DRY RUN COMPLETE: $TICKET_ID"
else
  echo "TASKS EXTENDED: $TICKET_ID"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Source summary
echo "Sources:"
if [[ -n "$USER_INSTRUCTIONS" ]]; then
  echo "  ✓ User instructions"
fi
if [[ "$FROM_REVIEW" = true ]]; then
  echo "  ✓ Code review report"
fi
if [[ "$FROM_PR_COMMENTS" = true ]]; then
  echo "  ✓ PR comments analysis"
fi
echo ""

# Task counts
if [[ "$DRY_RUN" = true ]]; then
  echo "Would create: ${#CREATED_TASKS[@]} tasks in Phase $NEXT_PHASE"
else
  echo "Created: ${#CREATED_TASKS[@]} tasks in Phase $NEXT_PHASE"
fi
echo ""

# List created tasks
for task in "${CREATED_TASKS[@]}"; do
  echo "  $task"
done
echo ""

# Error summary
if [[ ${#FAILED_TASKS[@]} -gt 0 ]]; then
  echo "Failed: ${#FAILED_TASKS[@]} tasks"
  echo ""
  for task in "${FAILED_TASKS[@]}"; do
    echo "  ✗ $task"
  done
  echo ""
fi

# Next steps
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "NEXT STEPS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ "$DRY_RUN" = true ]]; then
  echo "This was a dry run. To create tasks, remove --dry-run flag:"
  echo "  /sdd:extend $TICKET_ID --from-review"
elif [[ ${#CREATED_TASKS[@]} -gt 0 ]]; then
  echo "Execute new tasks:"
  echo "  /sdd:do-task ${CREATED_TASKS[0]%%:*}"
  echo ""
  echo "Or execute all tasks:"
  echo "  /sdd:do-all-tasks $TICKET_ID"
fi

if [[ ${#FAILED_TASKS[@]} -gt 0 ]]; then
  echo ""
  echo "Retry failed tasks:"
  echo "  Review error messages above"
  echo "  Fix issues and re-run /sdd:extend"
fi
```

## Error Handling

Comprehensive error handling for all failure scenarios:

| Error Condition | Error Message | Exit |
|----------------|---------------|------|
| No TICKET_ID | "ERROR: TICKET_ID is required" | Yes |
| Invalid TICKET_ID format | "ERROR: Invalid TICKET_ID format: {id}\n\nMust start with uppercase letter..." | Yes |
| Ticket not found | "ERROR: Ticket {id} not found\n\nExpected: {path}\n\nActions: verify ID, check /sdd:tasks-status" | Yes |
| No input source | "ERROR: No input source provided\n\nProvide: user instructions, --from-review, or --from-pr-comments" | Yes |
| Invalid --min-severity | "ERROR: Invalid --min-severity: {value}\n\nValid: CRITICAL, HIGH, MEDIUM, NITPICK" | Yes |
| Invalid --max | "ERROR: Invalid --max: {value}\n\nMust be positive integer or 'unlimited'" | Yes |
| Code review file missing | "ERROR: Code review report not found\n\nExpected: {path}\n\nAction: Run /sdd:code-review" | Yes |
| PR comments file missing | "ERROR: PR comments analysis not found\n\nExpected: {path}\n\nAction: Run /sdd:pr-comments" | Yes |
| Multiple quoted strings | "ERROR: Multiple quoted strings\n\nCombine into one quoted string" | Yes |
| Unquoted user input | "ERROR: User instructions must be quoted\n\nUsage: \"instructions here\"" | Yes |
| No findings after filter | "No findings match severity filter. Exiting." | Yes (0) |
| Task creation failure | Log error, continue with remaining, report in summary | No |

## Example Usage

```bash
# User instructions only
/sdd:extend MYTICKET "Add caching layer to API endpoints"

# From code review - all recommendations
/sdd:extend MYTICKET --from-review

# From PR comments - all complex comments
/sdd:extend MYTICKET --from-pr-comments

# From code review - HIGH and CRITICAL only
/sdd:extend MYTICKET --from-review --min-severity HIGH

# Combined sources - code review + PR comments
/sdd:extend MYTICKET --from-review --from-pr-comments

# Combined sources with limit
/sdd:extend MYTICKET --from-review --from-pr-comments --max 5

# All three sources
/sdd:extend MYTICKET --from-review --from-pr-comments "Also add error handling"

# Limit number of tasks
/sdd:extend MYTICKET --from-review --max 5

# Unlimited tasks
/sdd:extend MYTICKET --from-review --max unlimited

# Dry run preview
/sdd:extend MYTICKET --from-pr-comments --dry-run

# Interactive mode (prompt for each)
/sdd:extend MYTICKET --from-review --interactive

# Override agent assignment
/sdd:extend MYTICKET --from-review --default-agent security-reviewer

# Link to related task
/sdd:extend MYTICKET --from-review --related-to MYTICKET.1003

# Combined options
/sdd:extend MYTICKET --from-review --min-severity HIGH --max 3 --dry-run
```

## Key Constraints

- **Orchestrator role**: DO NOT create task files yourself, delegate to task-creator agent
- **Input validation**: Strict validation on all arguments before processing
- **Error recovery**: Continue processing remaining tasks if individual creation fails
- **Token transparency**: Warn user about token costs for >5 tasks
- **Phase detection**: Auto-detect next phase, warn on gaps
- **Severity filtering**: Inclusive filtering (HIGH includes CRITICAL)
- **Content sanitization**: Strip HTML, escape markdown before delegation
- **Single responsibility**: Command orchestrates, task-creator implements
