---
description: Create GitHub Pull Request for completed ticket
argument-hint: TICKET_ID [BASE_BRANCH] [--draft]
---

# Create Pull Request

## Context

Ticket: $ARGUMENTS

## Workflow

**IMPORTANT: You are an orchestrator. Use scripts for validation and scanning.**

### Step 1: Parse Arguments

Parse the arguments to extract TICKET_ID, optional BASE_BRANCH, and optional --draft flag:

```bash
# Initialize variables
DRAFT_MODE="false"
TICKET_ID=""
BASE_BRANCH=""

# Parse all arguments
for arg in $ARGUMENTS; do
  if [[ "$arg" == "--draft" ]]; then
    DRAFT_MODE="true"
  elif [[ -z "$TICKET_ID" ]]; then
    TICKET_ID="$arg"
  elif [[ -z "$BASE_BRANCH" ]]; then
    BASE_BRANCH="$arg"
  fi
done

# Set default base branch if not provided
if [[ -z "$BASE_BRANCH" ]]; then
  BASE_BRANCH="main"
fi

echo "Ticket ID: $TICKET_ID"
echo "Base Branch: $BASE_BRANCH"
echo "Draft Mode: $DRAFT_MODE"
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

# Check version (require >= 2.0.0 for --body-file support)
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

**Validate current branch:**

```bash
current_branch=$(git branch --show-current)
if [[ "$current_branch" == "main" ]] || [[ "$current_branch" == "master" ]]; then
  echo "ERROR: Cannot create PR from main/master branch."
  echo "Switch to a feature branch first."
  exit 1
fi
echo "✓ Current branch: $current_branch"
```

**Log validation start:**

```bash
SDD_ROOT="${SDD_ROOT_DIR:-/app/.sdd}"
mkdir -p "$SDD_ROOT/logs"
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")|PR_VALIDATION|$TICKET_ID|$current_branch|validation_start|Validating prerequisites for PR creation" >> "$SDD_ROOT/logs/workflow.log"
```

### Step 3: Validate Ticket

**Verify ticket directory exists:**

```bash
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
```

**Validate all tasks are verified:**

```bash
# Use existing task-status.sh script
task_status_output=$("${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/scripts/task-status.sh" "$TICKET_ID" 2>&1)
verification_status=$?

if [[ $verification_status -ne 0 ]]; then
  echo "ERROR: Cannot create PR - tasks not verified."
  echo "$task_status_output"
  echo ""
  echo "Run /sdd:do-all-tasks $TICKET_ID to verify all tasks."
  exit 1
fi
echo "✓ All tasks verified"

# Log successful validation
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")|PR_VALIDATION|$TICKET_ID|$current_branch|validation_success|All prerequisites validated" >> "$SDD_ROOT/logs/workflow.log"
```

### Step 4: Generate PR Content

**Detect Jira ticket pattern:**

```bash
# Check if TICKET_ID matches Jira pattern
if [[ "$TICKET_ID" =~ ^[A-Z][A-Z0-9]*-[0-9]+$ ]]; then
  JIRA_KEY="$TICKET_ID"
else
  JIRA_KEY=""
fi
```

**Extract ticket name and summary:**

```bash
# Extract ticket name from directory (remove TICKET_ID_ prefix)
TICKET_NAME=$(basename "$TICKET_DIR" | sed "s/^${TICKET_ID}_//")

# SUMMARY extraction with fallback chain
if [[ -f "${TICKET_DIR}/README.md" ]]; then
  SUMMARY_TEXT=$(head -n1 "${TICKET_DIR}/README.md" 2>/dev/null | sed 's/^# //')
  # Check if empty - try analysis.md
  if [[ -z "$SUMMARY_TEXT" ]]; then
    if [[ -f "${TICKET_DIR}/planning/analysis.md" ]]; then
      SUMMARY_TEXT=$(head -n5 "${TICKET_DIR}/planning/analysis.md" 2>/dev/null | grep -v "^#" | grep -v "^$" | head -n1)
    fi
  fi
else
  # README missing, try analysis.md
  if [[ -f "${TICKET_DIR}/planning/analysis.md" ]]; then
    SUMMARY_TEXT=$(head -n5 "${TICKET_DIR}/planning/analysis.md" 2>/dev/null | grep -v "^#" | grep -v "^$" | head -n1)
  fi
fi

# Final fallback
if [[ -z "$SUMMARY_TEXT" ]]; then
  SUMMARY_TEXT="See ticket planning docs"
fi

echo "Summary: $SUMMARY_TEXT"
```

**Extract changes from plan.md:**

```bash
# CHANGES extraction with fallback
if [[ -f "${TICKET_DIR}/planning/plan.md" ]]; then
  CHANGES_TEXT=$(grep -A 20 "Deliverables:" "${TICKET_DIR}/planning/plan.md" 2>/dev/null | grep "^- " | head -n 10)
  if [[ -z "$CHANGES_TEXT" ]]; then
    CHANGES_TEXT="See planning/plan.md for detailed changes"
  fi
else
  CHANGES_TEXT="See planning/plan.md for detailed changes"
fi

echo "Changes extracted"
```

**Generate Jira section (conditional):**

```bash
# JIRA_SECTION conditional generation
# Requires both JIRA_BASE_URL environment variable AND Jira ticket pattern
if [[ -n "$JIRA_BASE_URL" ]] && [[ -n "$JIRA_KEY" ]]; then
  JIRA_SECTION_TEXT="## Jira Ticket

[${JIRA_KEY}](${JIRA_BASE_URL}/browse/${JIRA_KEY})"
else
  JIRA_SECTION_TEXT=""
fi

# TESTING static value
TESTING_TEXT="All SDD tasks verified and passing"
```

**Export variables and generate PR body using template:**

```bash
# Generate PR title
PR_TITLE="[${TICKET_ID}] ${SUMMARY_TEXT}"

# Export variables for envsubst
export TICKET_ID="${TICKET_ID}"
export TICKET_NAME="${TICKET_NAME}"
export SUMMARY="${SUMMARY_TEXT}"
export CHANGES="${CHANGES_TEXT}"
export JIRA_SECTION="${JIRA_SECTION_TEXT}"
export TESTING="${TESTING_TEXT}"

# Read template and substitute variables
TEMPLATE_PATH="${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/templates/ticket/pr-description.md"
TEMP_BODY_FILE="/tmp/pr-body-${TICKET_ID}.md"

if [[ ! -f "$TEMPLATE_PATH" ]]; then
  echo "ERROR: Template file not found at $TEMPLATE_PATH"
  exit 1
fi

# Use envsubst to safely substitute variables (preserves special chars)
envsubst < "$TEMPLATE_PATH" > "$TEMP_BODY_FILE"

# Verify output file created
if [[ ! -f "$TEMP_BODY_FILE" ]]; then
  echo "ERROR: Failed to generate PR description"
  exit 1
fi

# Read generated body for preview
PR_BODY=$(cat "$TEMP_BODY_FILE")

echo "✓ PR content generated"
```

### Step 5: Preview and Confirm

**Display PR preview:**

```bash
echo ""
if [[ "$DRAFT_MODE" == "true" ]]; then
  echo "=== PR Preview (Draft) ==="
else
  echo "=== PR Preview ==="
fi
echo ""
echo "Title: ${PR_TITLE}"
echo ""
echo "--- Body ---"
echo "${PR_BODY}"
echo "-------------"
echo ""
```

**Prompt for confirmation:**

```bash
read -p "Create PR with this description? (y/n): " confirm

if [[ "$confirm" != "y" ]]; then
  echo "PR creation cancelled."
  exit 0
fi

echo "✓ Proceeding with PR creation"
```

### Step 6: Create PR

**Create PR using gh CLI:**

```bash
# Build gh pr create command with optional flags
gh_cmd="gh pr create --title \"$PR_TITLE\" --body-file \"$TEMP_BODY_FILE\""

# Add base branch if specified and not main
if [[ -n "$BASE_BRANCH" && "$BASE_BRANCH" != "main" ]]; then
  gh_cmd="$gh_cmd --base \"$BASE_BRANCH\""
fi

# Add draft flag if enabled
if [[ "$DRAFT_MODE" == "true" ]]; then
  gh_cmd="$gh_cmd --draft"
fi

# Execute PR creation
pr_output=$(eval "$gh_cmd" 2>&1)
pr_status=$?

# Cleanup temp file
rm -f "$TEMP_BODY_FILE"

# Check if PR creation succeeded
if [[ $pr_status -ne 0 ]]; then
  # Check if PR already exists
  if echo "$pr_output" | grep -q "already exists"; then
    pr_url=$(echo "$pr_output" | grep -oE 'https://github.com/[^ ]+')
    echo "NOTE: PR already exists for this branch."
    echo "PR: $pr_url"
    echo ""
    echo "Use /sdd:archive when ready to archive ticket."
    exit 0
  else
    echo "ERROR: Failed to create PR."
    echo "$pr_output"
    exit 1
  fi
fi

# Extract PR URL from success output
pr_url=$(echo "$pr_output" | grep -oE 'https://github.com/[^ ]+')
pr_number=$(echo "$pr_url" | grep -oE '/pull/[0-9]+' | grep -oE '[0-9]+')

echo "✓ PR created successfully"
```

### Step 7: Report Results

**Log PR creation to workflow.log:**

```bash
# Log PR creation
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")|PR_CREATED|${TICKET_ID}|${current_branch}|pr|PR #${pr_number} created: ${pr_url}" >> "${SDD_ROOT}/logs/workflow.log"
```

**Report success with PR URL and next steps:**

```bash
# Report success
if [[ "$DRAFT_MODE" == "true" ]]; then
  echo "✓ Draft Pull Request created successfully!"
else
  echo "✓ Pull Request created successfully!"
fi
echo ""
echo "PR: $pr_url"
echo "Title: $PR_TITLE"
echo "Ticket: $TICKET_ID"
if [[ "$DRAFT_MODE" == "true" ]]; then
  echo "Status: Draft"
fi
```

### Next Step Prompt

After displaying the report above, use the **AskUserQuestion** tool to present next steps to the user:

**Question:** "What would you like to do next?"
**Header:** "Next step"
**multiSelect:** false

**Options:**
- Label: "/sdd:archive {TICKET_ID}" | Description: "Archive ticket after successful PR"
- Label: "/sdd:fix-pr-feedback {TICKET_ID}" | Description: "Address PR review feedback"

Where {TICKET_ID} is the actual ticket ID from the command execution context, NOT the literal placeholder text.

## Next Steps

After PR creation:

1. **Review PR on GitHub:**
   - Check PR description is accurate
   - Verify all commits are included
   - Review CI/CD checks

2. **Request reviews:**
   - Tag appropriate reviewers
   - Respond to review comments
   - Make necessary changes

3. **Merge when approved:**
   - Ensure all checks pass
   - Merge to base branch
   - Delete feature branch if appropriate

## Key Constraints

- Requires gh CLI version >= 2.0.0
- Must be authenticated with GitHub
- Cannot create PR from main/master branch
- All tasks must be verified before PR creation
- Follow SDD orchestrator pattern: validate → preview → confirm → execute → report
