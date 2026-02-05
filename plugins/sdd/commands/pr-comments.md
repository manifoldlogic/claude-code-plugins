---
description: Fetch and display PR comments for feedback processing
argument-hint: PR_NUMBER [TICKET_ID]
---

# Fetch PR Comments

## Context

PR Number/URL: $ARGUMENTS

## Workflow

**IMPORTANT: You are an orchestrator. Use gh CLI for data fetching and validation.**

### Classification Constants

Define classification heuristics at the top:

```bash
# Classification constants (validated against real PR data)
SIMPLE_KEYWORDS="typo|nit|minor|missing|rename|add comment|whitespace|formatting|spelling"
COMPLEX_KEYWORDS="consider|should we|redesign|refactor|feature|architecture|pattern|might want|performance|security|decompose"
WORD_COUNT_THRESHOLD=60
CODE_BLOCK_PATTERN="\`\`\`"
FILTER_PATTERNS="^(LGTM|Testing locally|Approved)$|^[[:emoji:]]+$"
```

### Step 1: Parse Arguments

Parse the arguments to extract PR_NUMBER (required) and optional TICKET_ID:

```bash
# Initialize variables
PR_NUMBER=""
TICKET_ID=""

# Parse all arguments
for arg in $ARGUMENTS; do
  if [[ -z "$PR_NUMBER" ]]; then
    PR_NUMBER="$arg"
  elif [[ -z "$TICKET_ID" ]]; then
    TICKET_ID="$arg"
  fi
done

# Validate PR_NUMBER was provided
if [[ -z "$PR_NUMBER" ]]; then
  echo "ERROR: PR_NUMBER is required."
  echo "Usage: /sdd:pr-comments PR_NUMBER [TICKET_ID]"
  echo ""
  echo "Examples:"
  echo "  /sdd:pr-comments 123"
  echo "  /sdd:pr-comments https://github.com/owner/repo/pull/123"
  echo "  /sdd:pr-comments 123 TICKET-456"
  exit 1
fi

# Extract PR number from URL if full URL was provided
if [[ "$PR_NUMBER" =~ ^https://github\.com/.+/pull/([0-9]+) ]]; then
  PR_NUMBER="${BASH_REMATCH[1]}"
  echo "Extracted PR number: $PR_NUMBER"
elif [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "PR Number: $PR_NUMBER"
else
  echo "ERROR: Invalid PR_NUMBER format."
  echo "Expected: PR number (e.g., 123) or GitHub URL (e.g., https://github.com/owner/repo/pull/123)"
  echo "Received: $PR_NUMBER"
  exit 1
fi

if [[ -n "$TICKET_ID" ]]; then
  echo "Ticket ID: $TICKET_ID"
fi
```

### Step 2: Validate Prerequisites

**Validate GitHub CLI installation and version:**

```bash
# Check if gh is installed
if ! command -v gh &> /dev/null; then
  echo "ERROR: GitHub CLI (gh) not found."
  echo "Install: https://cli.github.com/"
  exit 1
fi

# Check version (require >= 2.0.0 for JSON output support)
gh_version=$(gh version | head -n1 | grep -oP 'gh version \K[0-9]+\.[0-9]+\.[0-9]+' || echo "")

if [[ -z "$gh_version" ]]; then
  echo "WARNING: Could not parse gh version. Proceeding with caution."
else
  required_version="2.0.0"
  if ! printf '%s\n' "$required_version" "$gh_version" | sort -V -C; then
    echo "ERROR: gh CLI version $gh_version is too old."
    echo "Required: >= $required_version"
    echo "Update: gh upgrade"
    exit 1
  fi
  echo "✓ GitHub CLI version $gh_version"
fi

# Check authentication
if ! gh auth status &> /dev/null; then
  echo "ERROR: Not authenticated with GitHub."
  echo "Run: gh auth login"
  exit 1
fi
echo "✓ GitHub authentication verified"
```

### Step 3: Validate Ticket (if provided)

**Verify ticket directory exists if TICKET_ID was provided:**

```bash
if [[ -n "$TICKET_ID" ]]; then
  SDD_ROOT="${SDD_ROOT_DIR:-/app/.sdd}"
  TICKET_DIR=$(find "$SDD_ROOT/tickets" -maxdepth 1 -type d -name "${TICKET_ID}_*" | head -n1)

  if [[ -z "$TICKET_DIR" ]]; then
    echo "ERROR: Ticket directory not found for $TICKET_ID"
    echo "Expected pattern: $SDD_ROOT/tickets/${TICKET_ID}_*"
    echo ""
    echo "Run /sdd:tasks-status to see available tickets."
    exit 1
  fi
  echo "✓ Ticket directory found: $TICKET_DIR"
fi
```

### Step 4: Fetch PR Comments

**Fetch PR details including comments and reviews using gh CLI:**

```bash
echo "Fetching PR #${PR_NUMBER} comments..."

# Fetch PR data with comments and reviews in JSON format
pr_json=$(gh pr view "$PR_NUMBER" --json comments,reviews,title,url,number 2>&1)
fetch_status=$?

# Check if fetch failed
if [[ $fetch_status -ne 0 ]]; then
  # Determine error type and provide specific guidance
  if echo "$pr_json" | grep -qi "could not resolve to a PullRequest"; then
    echo "ERROR: Pull request #${PR_NUMBER} not found."
    echo ""
    echo "Possible causes:"
    echo "  - PR number is incorrect"
    echo "  - PR is in a different repository (check current directory)"
    echo "  - You don't have access to this repository"
    echo ""
    echo "Verify PR exists and you're in the correct repository."
    exit 1
  elif echo "$pr_json" | grep -qi "authentication"; then
    echo "ERROR: Authentication failure."
    echo "Run: gh auth login"
    exit 1
  elif echo "$pr_json" | grep -qi "network\|timeout\|connection"; then
    echo "ERROR: Network error while fetching PR."
    echo "$pr_json"
    echo ""
    echo "Check your network connection and retry."
    exit 1
  else
    # Generic error with gh version for debugging
    echo "ERROR: Failed to fetch PR #${PR_NUMBER}."
    echo "gh CLI version: $gh_version"
    echo ""
    echo "Error details:"
    echo "$pr_json"
    exit 1
  fi
fi

echo "✓ PR data fetched successfully"
```

### Step 5: Validate and Parse JSON

**Validate JSON structure and parse PR information:**

```bash
# Validate JSON structure - check for required fields
if ! echo "$pr_json" | jq -e '.comments' > /dev/null 2>&1; then
  echo "ERROR: Invalid JSON response - missing 'comments' field."
  echo "gh CLI version: $gh_version"
  echo ""
  echo "This may indicate a gh CLI format change."
  echo "Try updating gh: gh upgrade"
  exit 1
fi

if ! echo "$pr_json" | jq -e '.reviews' > /dev/null 2>&1; then
  echo "ERROR: Invalid JSON response - missing 'reviews' field."
  echo "gh CLI version: $gh_version"
  echo ""
  echo "This may indicate a gh CLI format change."
  echo "Try updating gh: gh upgrade"
  exit 1
fi

# Extract PR metadata
pr_title=$(echo "$pr_json" | jq -r '.title // "Unknown"')
pr_url=$(echo "$pr_json" | jq -r '.url // "Unknown"')
pr_number=$(echo "$pr_json" | jq -r '.number // 0')

echo "✓ JSON structure validated"
echo ""
echo "PR #${pr_number}: ${pr_title}"
echo "URL: ${pr_url}"
```

### Step 6: Extract and Display Comments

**Parse and display PR-level comments and review comments:**

```bash
# Count comments and reviews
comment_count=$(echo "$pr_json" | jq '.comments | length')
review_count=$(echo "$pr_json" | jq '.reviews | length')

echo ""
echo "=== Comment Summary ==="
echo "PR-level comments: $comment_count"
echo "Review comments: $review_count"
echo ""

# Display PR-level comments
if [[ $comment_count -gt 0 ]]; then
  echo "=== PR-Level Comments ==="
  echo ""

  # Parse each comment
  echo "$pr_json" | jq -r '.comments[] |
    "Author: \(.author.login)\n" +
    "Created: \(.createdAt)\n" +
    "Body:\n\(.body)\n" +
    "---"'
  echo ""
fi

# Display review comments
if [[ $review_count -gt 0 ]]; then
  echo "=== Review Comments ==="
  echo ""

  # Parse each review and its comments
  echo "$pr_json" | jq -r '.reviews[] |
    "Reviewer: \(.author.login)\n" +
    "State: \(.state)\n" +
    "Submitted: \(.submittedAt // "N/A")\n" +
    (if .body and .body != "" then "Review Body:\n\(.body)\n" else "" end) +
    (if .comments then
      "File Comments:\n" +
      (.comments | map(
        "  File: \(.path)\n" +
        "  Line: \(.line // .position)\n" +
        "  Comment: \(.body)"
      ) | join("\n\n"))
    else "" end) +
    "\n---"'
  echo ""
fi

# Store raw JSON for classification
raw_comments_json="$pr_json"
```

### Step 6.5: Classify Comments

**Apply classification heuristics to each comment:**

```bash
echo ""
echo "=== Classifying Comments ==="
echo ""

# Initialize classification arrays
declare -a simple_comments
declare -a complex_comments
declare -a simple_reasoning
declare -a complex_reasoning
declare -a simple_locations
declare -a complex_locations
declare -a simple_authors
declare -a complex_authors
declare -a simple_bodies
declare -a complex_bodies

simple_count=0
complex_count=0

# Process PR-level comments
while IFS= read -r comment_json; do
  # Skip empty lines
  [[ -z "$comment_json" ]] && continue

  # Extract comment fields
  author=$(echo "$comment_json" | jq -r '.author.login // "unknown"')
  body=$(echo "$comment_json" | jq -r '.body // ""')
  created_at=$(echo "$comment_json" | jq -r '.createdAt // ""')

  # Filter out meta-comments (LGTM, Testing locally, emoji-only, empty)
  if [[ -z "$body" ]] || echo "$body" | grep -qE "$FILTER_PATTERNS"; then
    echo "  Skipping meta-comment from @$author"
    continue
  fi

  # Count indicators
  simple_indicators=0
  complex_indicators=0
  reasoning=""

  # Word count
  word_count=$(echo "$body" | wc -w)
  if [[ $word_count -lt $WORD_COUNT_THRESHOLD ]]; then
    ((simple_indicators++))
    reasoning+="Short comment ($word_count words). "
  else
    ((complex_indicators++))
    reasoning+="Long comment ($word_count words). "
  fi

  # Code block detection (triple backticks = STRONG COMPLEX signal)
  if echo "$body" | grep -q "$CODE_BLOCK_PATTERN"; then
    ((complex_indicators+=2))  # Strong signal, count twice
    reasoning+="Contains code block. "
  fi

  # Keyword matching
  if echo "$body" | grep -qiE "$SIMPLE_KEYWORDS"; then
    ((simple_indicators++))
    reasoning+="Contains SIMPLE keywords. "
  fi

  if echo "$body" | grep -qiE "$COMPLEX_KEYWORDS"; then
    ((complex_indicators++))
    reasoning+="Contains COMPLEX keywords. "
  fi

  # Bullet point detection (3+)
  bullet_count=$(echo "$body" | grep -cE "^[*-]|^[0-9]+\." || echo "0")
  if [[ $bullet_count -ge 3 ]]; then
    ((complex_indicators++))
    reasoning+="Has $bullet_count list items. "
  fi

  # Classify based on conflict resolution rules
  if [[ $complex_indicators -gt 0 ]]; then
    classification="COMPLEX"
    if [[ $simple_indicators -gt 0 ]]; then
      confidence="low"
    else
      confidence="high"
    fi
  elif [[ $simple_indicators -gt 0 ]]; then
    classification="SIMPLE"
    confidence="high"
  else
    # Default to COMPLEX when uncertain
    classification="COMPLEX"
    confidence="medium"
    reasoning+="No clear signals, defaulting to COMPLEX. "
  fi

  # Store classified comment
  if [[ "$classification" == "SIMPLE" ]]; then
    simple_comments[$simple_count]="$body"
    simple_reasoning[$simple_count]="$reasoning (confidence: $confidence)"
    simple_locations[$simple_count]="PR-level"
    simple_authors[$simple_count]="$author"
    simple_bodies[$simple_count]="$body"
    ((simple_count++))
    echo "  [@$author] SIMPLE (${confidence} confidence)"
  else
    complex_comments[$complex_count]="$body"
    complex_reasoning[$complex_count]="$reasoning (confidence: $confidence)"
    complex_locations[$complex_count]="PR-level"
    complex_authors[$complex_count]="$author"
    complex_bodies[$complex_count]="$body"
    ((complex_count++))
    echo "  [@$author] COMPLEX (${confidence} confidence)"
  fi
done < <(echo "$raw_comments_json" | jq -c '.comments[]?' 2>/dev/null)

# Process review comments
while IFS= read -r review_json; do
  # Skip empty lines
  [[ -z "$review_json" ]] && continue

  reviewer=$(echo "$review_json" | jq -r '.author.login // "unknown"')
  review_body=$(echo "$review_json" | jq -r '.body // ""')

  # Process review-level comment if it exists and is not a meta-comment
  if [[ -n "$review_body" ]] && ! echo "$review_body" | grep -qE "$FILTER_PATTERNS"; then
    # Apply same classification logic as PR comments
    word_count=$(echo "$review_body" | wc -w)
    simple_indicators=0
    complex_indicators=0
    reasoning=""

    if [[ $word_count -lt $WORD_COUNT_THRESHOLD ]]; then
      ((simple_indicators++))
      reasoning+="Short comment ($word_count words). "
    else
      ((complex_indicators++))
      reasoning+="Long comment ($word_count words). "
    fi

    if echo "$review_body" | grep -q "$CODE_BLOCK_PATTERN"; then
      ((complex_indicators+=2))
      reasoning+="Contains code block. "
    fi

    if echo "$review_body" | grep -qiE "$SIMPLE_KEYWORDS"; then
      ((simple_indicators++))
      reasoning+="Contains SIMPLE keywords. "
    fi

    if echo "$review_body" | grep -qiE "$COMPLEX_KEYWORDS"; then
      ((complex_indicators++))
      reasoning+="Contains COMPLEX keywords. "
    fi

    bullet_count=$(echo "$review_body" | grep -cE "^[*-]|^[0-9]+\." || echo "0")
    if [[ $bullet_count -ge 3 ]]; then
      ((complex_indicators++))
      reasoning+="Has $bullet_count list items. "
    fi

    if [[ $complex_indicators -gt 0 ]]; then
      classification="COMPLEX"
      confidence=$([[ $simple_indicators -gt 0 ]] && echo "low" || echo "high")
    elif [[ $simple_indicators -gt 0 ]]; then
      classification="SIMPLE"
      confidence="high"
    else
      classification="COMPLEX"
      confidence="medium"
      reasoning+="No clear signals, defaulting to COMPLEX. "
    fi

    if [[ "$classification" == "SIMPLE" ]]; then
      simple_comments[$simple_count]="$review_body"
      simple_reasoning[$simple_count]="$reasoning (confidence: $confidence)"
      simple_locations[$simple_count]="Review-level"
      simple_authors[$simple_count]="$reviewer"
      simple_bodies[$simple_count]="$review_body"
      ((simple_count++))
      echo "  [@$reviewer] SIMPLE (${confidence} confidence) - Review comment"
    else
      complex_comments[$complex_count]="$review_body"
      complex_reasoning[$complex_count]="$reasoning (confidence: $confidence)"
      complex_locations[$complex_count]="Review-level"
      complex_authors[$complex_count]="$reviewer"
      complex_bodies[$complex_count]="$review_body"
      ((complex_count++))
      echo "  [@$reviewer] COMPLEX (${confidence} confidence) - Review comment"
    fi
  fi

  # Process inline file comments
  while IFS= read -r file_comment_json; do
    [[ -z "$file_comment_json" ]] && continue

    file_path=$(echo "$file_comment_json" | jq -r '.path // "unknown"')
    line_num=$(echo "$file_comment_json" | jq -r '.line // .position // "?"')
    file_body=$(echo "$file_comment_json" | jq -r '.body // ""')

    # Filter meta-comments
    if [[ -z "$file_body" ]] || echo "$file_body" | grep -qE "$FILTER_PATTERNS"; then
      continue
    fi

    # Apply classification
    word_count=$(echo "$file_body" | wc -w)
    simple_indicators=0
    complex_indicators=0
    reasoning=""

    if [[ $word_count -lt $WORD_COUNT_THRESHOLD ]]; then
      ((simple_indicators++))
      reasoning+="Short comment ($word_count words). "
    else
      ((complex_indicators++))
      reasoning+="Long comment ($word_count words). "
    fi

    if echo "$file_body" | grep -q "$CODE_BLOCK_PATTERN"; then
      ((complex_indicators+=2))
      reasoning+="Contains code block. "
    fi

    if echo "$file_body" | grep -qiE "$SIMPLE_KEYWORDS"; then
      ((simple_indicators++))
      reasoning+="Contains SIMPLE keywords. "
    fi

    if echo "$file_body" | grep -qiE "$COMPLEX_KEYWORDS"; then
      ((complex_indicators++))
      reasoning+="Contains COMPLEX keywords. "
    fi

    bullet_count=$(echo "$file_body" | grep -cE "^[*-]|^[0-9]+\." || echo "0")
    if [[ $bullet_count -ge 3 ]]; then
      ((complex_indicators++))
      reasoning+="Has $bullet_count list items. "
    fi

    if [[ $complex_indicators -gt 0 ]]; then
      classification="COMPLEX"
      confidence=$([[ $simple_indicators -gt 0 ]] && echo "low" || echo "high")
    elif [[ $simple_indicators -gt 0 ]]; then
      classification="SIMPLE"
      confidence="high"
    else
      classification="COMPLEX"
      confidence="medium"
      reasoning+="No clear signals, defaulting to COMPLEX. "
    fi

    location="$file_path:$line_num"

    if [[ "$classification" == "SIMPLE" ]]; then
      simple_comments[$simple_count]="$file_body"
      simple_reasoning[$simple_count]="$reasoning (confidence: $confidence)"
      simple_locations[$simple_count]="$location"
      simple_authors[$simple_count]="$reviewer"
      simple_bodies[$simple_count]="$file_body"
      ((simple_count++))
      echo "  [@$reviewer] SIMPLE (${confidence} confidence) - $location"
    else
      complex_comments[$complex_count]="$file_body"
      complex_reasoning[$complex_count]="$reasoning (confidence: $confidence)"
      complex_locations[$complex_count]="$location"
      complex_authors[$complex_count]="$reviewer"
      complex_bodies[$complex_count]="$file_body"
      ((complex_count++))
      echo "  [@$reviewer] COMPLEX (${confidence} confidence) - $location"
    fi
  done < <(echo "$review_json" | jq -c '.comments[]?' 2>/dev/null)
done < <(echo "$raw_comments_json" | jq -c '.reviews[]?' 2>/dev/null)

total_classified=$((simple_count + complex_count))
echo ""
echo "✓ Classification complete: $total_classified comments classified"
echo "  SIMPLE: $simple_count"
echo "  COMPLEX: $complex_count"
```

### Step 6.6: Generate Analysis File

**Create structured analysis file in deliverables directory:**

```bash
# Only create analysis file if TICKET_ID was provided
if [[ -n "$TICKET_ID" ]]; then
  echo ""
  echo "=== Generating Analysis File ==="

  # Create deliverables directory
  deliverables_dir="$TICKET_DIR/deliverables"
  mkdir -p "$deliverables_dir"

  analysis_file="$deliverables_dir/pr-comments-analysis.md"
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Generate analysis file
  cat > "$analysis_file" <<EOF
# PR Comments Analysis

**PR:** #${pr_number} - ${pr_title}
**URL:** ${pr_url}
**Analyzed:** ${timestamp}
**Ticket:** ${TICKET_ID}

## Summary

| Classification | Count |
|---------------|-------|
| SIMPLE        | ${simple_count}   |
| COMPLEX       | ${complex_count}   |
| Total         | ${total_classified}   |

## SIMPLE Comments

These comments can be addressed directly in the current session.

EOF

  # Add SIMPLE comments
  if [[ $simple_count -gt 0 ]]; then
    for i in "${!simple_comments[@]}"; do
      idx=$((i + 1))
      author="${simple_authors[$i]}"
      location="${simple_locations[$i]}"
      body="${simple_bodies[$i]}"
      reasoning="${simple_reasoning[$i]}"

      # Generate short description (first 50 chars of body)
      short_desc=$(echo "$body" | head -c 50 | tr '\n' ' ')
      [[ ${#body} -gt 50 ]] && short_desc="${short_desc}..."

      cat >> "$analysis_file" <<EOF
### SIMPLE-${idx}: ${short_desc}

- **Author:** @${author}
- **Location:** ${location}
- **Classification Confidence:** ${reasoning}

**Comment:**
> $(echo "$body" | sed 's/^/> /')

**Suggested Action:**
Review and apply the suggested change directly.

---

EOF
    done
  else
    echo "No SIMPLE comments found." >> "$analysis_file"
    echo "" >> "$analysis_file"
  fi

  # Add COMPLEX comments section
  cat >> "$analysis_file" <<EOF

## COMPLEX Comments

These comments require follow-up tasks or separate tickets to address properly.

EOF

  if [[ $complex_count -gt 0 ]]; then
    for i in "${!complex_comments[@]}"; do
      idx=$((i + 1))
      author="${complex_authors[$i]}"
      location="${complex_locations[$i]}"
      body="${complex_bodies[$i]}"
      reasoning="${complex_reasoning[$i]}"

      # Generate short description
      short_desc=$(echo "$body" | head -c 50 | tr '\n' ' ')
      [[ ${#body} -gt 50 ]] && short_desc="${short_desc}..."

      # Generate recommended task title
      task_title=$(echo "$body" | head -n 1 | head -c 80 | tr '\n' ' ')
      [[ ${#body} -gt 80 ]] && task_title="${task_title}..."

      cat >> "$analysis_file" <<EOF
### COMPLEX-${idx}: ${short_desc}

- **Author:** @${author}
- **Location:** ${location}
- **Classification Confidence:** ${reasoning}

**Comment:**
> $(echo "$body" | sed 's/^/> /')

**Recommended Task:**
${task_title}

**Task Context:**
Review the comment above and determine appropriate action. This may require architectural discussion, significant refactoring, or new feature development.

---

EOF
    done
  else
    echo "No COMPLEX comments found." >> "$analysis_file"
    echo "" >> "$analysis_file"
  fi

  # Add metadata
  cat >> "$analysis_file" <<EOF

## Metadata

\`\`\`json
{
  "format_version": "1.0",
  "pr_number": ${pr_number},
  "analyzed_at": "${timestamp}",
  "ticket_id": "${TICKET_ID}",
  "total_comments": ${total_classified},
  "simple_count": ${simple_count},
  "complex_count": ${complex_count},
  "classification_method": "heuristic"
}
\`\`\`
EOF

  echo "✓ Analysis file created: $analysis_file"
fi
```

### Step 7: Report Results

**Summarize fetched data and next steps:**

```bash
echo ""
echo "==================================================================="
echo "PR COMMENTS ANALYZED: #${pr_number}"
echo "==================================================================="
echo ""
echo "Total Comments: ${total_classified}"
echo ""
echo "Classification:"
echo "  SIMPLE:  ${simple_count} (can address directly)"
echo "  COMPLEX: ${complex_count} (recommend follow-up tasks)"
echo ""

# Determine if we need to truncate console output (50+ comments)
if [[ $total_classified -gt 50 ]]; then
  display_limit=20
  echo "⚠️  Large PR detected (${total_classified} comments)"
  echo "   Showing first ${display_limit} items. See analysis file for complete data."
  echo ""
else
  display_limit=$total_classified
fi

# Display SIMPLE comments (up to limit)
if [[ $simple_count -gt 0 ]]; then
  echo "=== SIMPLE COMMENTS ==="
  echo ""
  displayed=0
  for i in "${!simple_comments[@]}"; do
    [[ $displayed -ge $display_limit ]] && break
    idx=$((i + 1))
    author="${simple_authors[$i]}"
    location="${simple_locations[$i]}"
    body="${simple_bodies[$i]}"

    # Truncate long comments for console display (>500 chars)
    if [[ ${#body} -gt 500 ]]; then
      display_body="${body:0:500}... (truncated)"
    else
      display_body="$body"
    fi

    echo "$idx. [@$author] $location"
    echo "   \"$display_body\""
    echo "   → Review and apply directly"
    echo ""
    ((displayed++))
  done
fi

# Display COMPLEX comments (up to limit)
if [[ $complex_count -gt 0 ]]; then
  echo "=== COMPLEX COMMENTS ==="
  echo ""
  displayed=0
  for i in "${!complex_comments[@]}"; do
    [[ $displayed -ge $display_limit ]] && break
    idx=$((i + 1))
    author="${complex_authors[$i]}"
    location="${complex_locations[$i]}"
    body="${complex_bodies[$i]}"

    # Truncate long comments for console display (>500 chars)
    if [[ ${#body} -gt 500 ]]; then
      display_body="${body:0:500}... (truncated)"
    else
      display_body="$body"
    fi

    # Generate task title from first line
    task_title=$(echo "$body" | head -n 1 | head -c 80)
    [[ ${#body} -gt 80 ]] && task_title="${task_title}..."

    echo "$idx. [@$author] $location"
    echo "   \"$display_body\""
    echo "   → Recommend task: $task_title"
    echo ""
    ((displayed++))
  done
fi

# Show truncation warning if needed
if [[ $total_classified -gt $display_limit ]]; then
  remaining=$((total_classified - display_limit))
  echo "...and ${remaining} more comments."
  echo ""
fi

# Display file path if created
if [[ -n "$TICKET_ID" ]]; then
  echo "==================================================================="
  echo "Analysis saved: $analysis_file"
  echo "==================================================================="
  echo ""
fi

```

### Next Step Prompt

After displaying the report above, use the **AskUserQuestion** tool to present next steps to the user:

**Question:** "What would you like to do next?"
**Header:** "Next step"
**multiSelect:** false

**Options:**
- Label: "/sdd:fix-pr-feedback {TICKET_ID}" | Description: "Address PR review comments"
- Label: "/sdd:pr {TICKET_ID}" | Description: "Check PR status after updates"

Where {TICKET_ID} is the actual ticket ID from the command execution context, NOT the literal placeholder text.

## Error Handling Summary

All error scenarios produce clear, actionable messages:

1. **gh not installed** → Install link: https://cli.github.com/
2. **gh version too old** → Update command: `gh upgrade`
3. **Not authenticated** → Auth command: `gh auth login`
4. **Invalid PR number format** → Show expected formats with examples
5. **PR not found** → Suggest verification steps and repository check
6. **Network error** → Clear message with retry guidance
7. **JSON format changed** → Include gh version for debugging, suggest upgrade
8. **Missing required argument** → Show usage with examples

## Key Constraints

- Requires gh CLI version >= 2.0.0
- Must be authenticated with GitHub
- Must have access to the repository containing the PR
- No automatic retries - user controls when to retry after error
- Fails fast with non-zero exit code on any error
- Validates JSON structure before parsing to detect format changes

## Next Steps

After analyzing comments:

1. **Address SIMPLE comments** directly in current session - these are quick fixes
2. **Review COMPLEX comments** in analysis file to determine if follow-up tasks needed
3. **Create tasks** for COMPLEX items that require significant work
4. **Update ticket planning** based on feedback themes identified in the analysis

## Format Specification

The `pr-comments-analysis.md` file uses a structured, versioned format suitable for both human reading and programmatic consumption.

### Output File Structure

```markdown
# PR Comments Analysis

**Metadata header with PR info**

## Summary
| Classification | Count |
...

## SIMPLE Comments
### SIMPLE-1: {short description}
- **Author:** @{login}
- **Location:** {file}:{line} or "PR-level"
- **Classification Confidence:** {reasoning}

**Comment:**
> {body}

**Suggested Action:**
{action}
---

## COMPLEX Comments
### COMPLEX-1: {short description}
- **Author:** @{login}
- **Location:** {file}:{line} or "PR-level"
- **Classification Confidence:** {reasoning}

**Comment:**
> {body}

**Recommended Task:**
{task title}

**Task Context:**
{task description}
---

## Metadata
```json
{
  "format_version": "1.0",
  "pr_number": {number},
  ...
}
```
```

### Parsing Guide for Downstream Consumers

To programmatically parse `pr-comments-analysis.md`:

#### 1. Check Format Version
```bash
format_version=$(grep -A 20 "^## Metadata" analysis.md | grep -oP '"format_version":\s*"\K[^"]+')

if [[ "$format_version" != "1.0" ]]; then
  echo "WARNING: Unsupported format version $format_version"
fi
```

#### 2. Extract COMPLEX Comments for Task Creation
```bash
# Find COMPLEX Comments section
sed -n '/^## COMPLEX Comments$/,/^## Metadata$/p' analysis.md > complex-section.md

# Parse each COMPLEX-N subsection
grep -oP '^### COMPLEX-\d+:.*$' complex-section.md
```

#### 3. Section Header Patterns (Regex)

| Section | Pattern | Purpose |
|---------|---------|---------|
| SIMPLE comments | `/^## SIMPLE Comments$/` | Start of simple comments section |
| COMPLEX comments | `/^## COMPLEX Comments$/` | Start of complex comments section |
| Individual SIMPLE | `/^### SIMPLE-\d+:/` | Each simple comment |
| Individual COMPLEX | `/^### COMPLEX-\d+:/` | Each complex comment |
| Metadata | `/^## Metadata$/` | JSON metadata block |

#### 4. Field Extraction Patterns

Extract fields from each comment subsection:

```bash
# Extract author
grep -oP '^\*\*Author:\*\*\s*@\K\w+' comment.md

# Extract location
grep -oP '^\*\*Location:\*\*\s*\K.*$' comment.md

# Extract recommended task (COMPLEX only)
grep -oP '^\*\*Recommended Task:\*\*\s*\K.*$' comment.md

# Extract task context (COMPLEX only)
sed -n '/^\*\*Task Context:\*\*$/,/^---$/p' comment.md | sed '1d;$d'

# Extract comment body (always quoted with >)
sed -n '/^\*\*Comment:\*\*$/,/^\*\*[A-Z]/p' comment.md | sed '1d;$d' | sed 's/^> //'
```

#### 5. Full Parsing Example

```bash
#!/bin/bash
# parse-pr-comments-analysis.sh

analysis_file="$1"

# Verify format version
format_version=$(grep -A 20 "^## Metadata" "$analysis_file" | \
  grep -oP '"format_version":\s*"\K[^"]+')

if [[ "$format_version" != "1.0" ]]; then
  echo "ERROR: Unsupported format version: $format_version"
  exit 1
fi

# Extract all COMPLEX comments
echo "Extracting COMPLEX comments for task creation..."

# Get COMPLEX section
complex_section=$(sed -n '/^## COMPLEX Comments$/,/^## Metadata$/p' "$analysis_file")

# Count COMPLEX comments
complex_count=$(echo "$complex_section" | grep -c '^### COMPLEX-')

echo "Found $complex_count COMPLEX comments"

# Parse each COMPLEX comment
for i in $(seq 1 "$complex_count"); do
  echo ""
  echo "=== COMPLEX-$i ==="

  # Extract this specific comment (from COMPLEX-N to next COMPLEX or end marker)
  comment_text=$(echo "$complex_section" | \
    sed -n "/^### COMPLEX-$i:/,/^### COMPLEX-$((i+1)):/p" | \
    sed '$d')  # Remove last line (next header)

  # Extract fields
  author=$(echo "$comment_text" | grep -oP '^\*\*Author:\*\*\s*@\K\w+')
  location=$(echo "$comment_text" | grep -oP '^\*\*Location:\*\*\s*\K.*$')
  task_title=$(echo "$comment_text" | grep -oP '^\*\*Recommended Task:\*\*\s*\K.*$')

  echo "Author: $author"
  echo "Location: $location"
  echo "Task: $task_title"
done
```

### Format Versioning

The `format_version` field enables format evolution without breaking existing parsers.

**Version 1.0 (current):**
- Two-section structure (SIMPLE, COMPLEX)
- Consistent field names
- Markdown table for summary
- JSON metadata block

**Future versions** may add:
- Additional classification categories
- Confidence scores in metadata
- Task priority recommendations
- Automated fix suggestions

**Backward compatibility:** Parsers should check `format_version` and handle gracefully:
```bash
case "$format_version" in
  "1.0")
    parse_v1 "$file"
    ;;
  "2.0")
    parse_v2 "$file"
    ;;
  *)
    echo "ERROR: Unknown format version $format_version"
    exit 1
    ;;
esac
```

### Location Field Format

The **Location** field indicates where the comment appears:

| Format | Meaning | Example |
|--------|---------|---------|
| `PR-level` | General PR comment | Not tied to specific code |
| `Review-level` | Review summary comment | Top-level review feedback |
| `{file}:{line}` | Inline code comment | `src/auth/jwt.ts:42` |

Use this to prioritize comments:
- File-specific comments are often more actionable
- PR-level comments may be architectural or process-related

### Next Steps After Parsing

Once COMPLEX comments are extracted:

1. **Create tasks** using `/sdd:create-tasks` with recommended task titles
2. **Assign to phases** based on task context (implementation vs refactoring vs new feature)
3. **Update ticket plan** to reflect feedback-driven scope changes
4. **Document decisions** for deferred or rejected feedback
