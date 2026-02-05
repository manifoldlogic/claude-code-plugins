---
description: |
  Critically evaluate PR review comments and fix valid issues.

  Fetches PR comments (CodeRabbit, human reviewers, etc.), validates each
  against actual code to determine if correct, fixes valid issues, runs tests,
  and commits. Does NOT blindly trust reviewer suggestions - validates claims
  by examining code and tests.

  Usage examples:
  - Current branch PR: /sdd:fix-pr-feedback
  - Specific PR: /sdd:fix-pr-feedback 123
  - PR URL: /sdd:fix-pr-feedback https://github.com/owner/repo/pull/123
  - Dry run (analyze only): /sdd:fix-pr-feedback --dry-run
  - Skip nits: /sdd:fix-pr-feedback --skip-nits
argument-hint: "[PR_NUMBER|URL] [--dry-run] [--skip-nits]"
---

# Fix PR Feedback

## Context

User input: "$ARGUMENTS"

## Philosophy

**CRITICAL: Do NOT assume reviewers are correct.** Automated tools like CodeRabbit, and even human reviewers, can make mistakes. Before fixing any issue:

1. **Read the actual code** - Understand what it does and why
2. **Verify the claim** - Is the reviewer's assertion actually true?
3. **Check for context** - Does the reviewer understand the broader design?
4. **Run affected tests** - Would the suggested change break anything?

Only fix issues that are genuinely bugs or improvements. Skip issues where:
- The reviewer misunderstood the code's purpose
- The suggestion would break existing functionality
- The change is purely cosmetic with no practical benefit
- The issue is outside the scope of the current PR's changes

## Workflow

### Step 1: Parse Arguments

```bash
PR_NUMBER=""
DRY_RUN=false
SKIP_NITS=false

for arg in $ARGUMENTS; do
  case "$arg" in
    --dry-run)
      DRY_RUN=true
      ;;
    --skip-nits)
      SKIP_NITS=true
      ;;
    https://github.com/*/pull/*)
      # Extract PR number from URL
      PR_NUMBER=$(echo "$arg" | grep -oP 'pull/\K[0-9]+')
      ;;
    [0-9]*)
      PR_NUMBER="$arg"
      ;;
  esac
done
```

If no PR number provided, detect from current branch:
```bash
if [[ -z "$PR_NUMBER" ]]; then
  # Try to get PR for current branch
  PR_NUMBER=$(gh pr view --json number -q '.number' 2>/dev/null || echo "")

  if [[ -z "$PR_NUMBER" ]]; then
    echo "ERROR: No PR found for current branch."
    echo "Usage: /sdd:fix-pr-feedback [PR_NUMBER] [--dry-run] [--skip-nits]"
    exit 1
  fi
  echo "Detected PR #$PR_NUMBER for current branch"
fi
```

### Step 2: Fetch PR Comments

Fetch all comments using GitHub CLI:

```bash
# Fetch PR metadata
pr_json=$(gh pr view "$PR_NUMBER" --json number,title,url,headRefName,baseRefName)
pr_title=$(echo "$pr_json" | jq -r '.title')
pr_url=$(echo "$pr_json" | jq -r '.url')
head_branch=$(echo "$pr_json" | jq -r '.headRefName')
base_branch=$(echo "$pr_json" | jq -r '.baseRefName')

echo "PR #$PR_NUMBER: $pr_title"
echo "URL: $pr_url"
echo "Branch: $head_branch → $base_branch"

# Fetch review comments (file-level)
review_comments=$(gh api repos/{owner}/{repo}/pulls/$PR_NUMBER/comments --paginate 2>/dev/null || echo "[]")

# Count comments
comment_count=$(echo "$review_comments" | jq 'length')
echo "Found $comment_count review comments"
```

### Step 3: Identify Changed Files

Get the files actually changed in this PR to filter relevant comments:

```bash
# Get files changed in this PR
changed_files=$(gh pr diff "$PR_NUMBER" --name-only)
echo ""
echo "Files changed in PR:"
echo "$changed_files" | sed 's/^/  - /'
```

### Step 4: Analyze Each Comment

For EACH comment, apply the critical validation process:

**4a. Parse comment metadata:**
```bash
# Extract: file path, line number, body, author
path=$(echo "$comment" | jq -r '.path')
line=$(echo "$comment" | jq -r '.line // .original_line // "?"')
body=$(echo "$comment" | jq -r '.body')
author=$(echo "$comment" | jq -r '.user.login')
```

**4b. Filter to only PR-relevant files:**
```bash
# Skip comments on files not in this PR's changes
if ! echo "$changed_files" | grep -qF "$path"; then
  echo "SKIP: $path - not changed in this PR"
  continue
fi
```

**4c. Classify comment type:**
| Type | Description | Action |
|------|-------------|--------|
| BUG | Actual bug that will cause issues | MUST FIX |
| SECURITY | Security vulnerability | MUST FIX |
| CORRECTNESS | Logic error or incorrect behavior | MUST FIX |
| SHELLCHECK | ShellCheck/linting warning | VALIDATE then fix |
| PORTABILITY | Cross-platform compatibility issue | FIX if relevant |
| STYLE | Code style/formatting | FIX if --skip-nits not set |
| NIT | Minor improvement, optional | FIX if --skip-nits not set |
| INVALID | Reviewer is incorrect | SKIP with explanation |

**4d. Validate the claim:**

This is the critical step. For each comment:

1. **Read the referenced code:**
   ```bash
   # Read the actual code at the location
   Read tool: file_path=$path, offset=$((line - 10)), limit=30
   ```

2. **Understand the context:**
   - What is this code trying to do?
   - What is the reviewer claiming?
   - Is that claim accurate?

3. **Search for related code:**
   ```bash
   # If comment mentions a variable/function, find its usage
   Grep tool: pattern="$referenced_item", path="."
   ```

4. **Check tests:**
   ```bash
   # See if tests cover this code path
   Grep tool: pattern="$function_name", path="**/test*"
   ```

5. **Make a determination:**
   - **VALID**: The comment is correct, fix it
   - **INVALID**: The reviewer misunderstood, skip it
   - **PARTIAL**: Some aspects are valid, fix those

### Step 5: Build Fix Plan

Create a todo list tracking each issue to fix:

```markdown
## Issues to Fix

| # | File | Line | Type | Description | Status |
|---|------|------|------|-------------|--------|
| 1 | sdd-loop.sh | 1609 | BUG | set -e swallows exit code | PENDING |
| 2 | load-test.sh | 392 | SHELLCHECK | SC2155 local assignment | PENDING |
| ... | ... | ... | ... | ... | ... |

## Issues to Skip

| # | File | Line | Reason |
|---|------|------|--------|
| 1 | other-file.sh | 42 | Not in PR scope |
| 2 | utils.sh | 100 | Reviewer misunderstood intent |
| ... | ... | ... | ... |
```

If `--dry-run`, stop here and report the plan.

### Step 6: Apply Fixes

For each issue marked PENDING:

1. **Read the current code**
2. **Apply the fix** using Edit tool
3. **Mark as FIXED in todo list**

Group related fixes logically (e.g., all fixes in one file together).

### Step 7: Run Tests

After all fixes applied:

```bash
# Detect test framework and run tests
if [[ -f "package.json" ]]; then
  npm test
elif [[ -f "pytest.ini" ]] || [[ -f "setup.py" ]]; then
  pytest
elif [[ -f "Cargo.toml" ]]; then
  cargo test
elif [[ -f "go.mod" ]]; then
  go test ./...
else
  # Look for test scripts
  find . -name "test*.sh" -o -name "*_test.sh" | head -1 | xargs bash
fi
```

If tests fail:
1. Identify which fix caused the failure
2. Revert that fix or adjust it
3. Re-run tests
4. Repeat until tests pass

### Step 8: Commit and Push

Once tests pass:

```bash
# Stage all changes
git add -A

# Create commit with summary of fixes
git commit -m "$(cat <<'EOF'
fix: address PR review feedback

- {fix 1 summary}
- {fix 2 summary}
- ...

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"

# Push to update PR
git push
```

### Step 9: Report Results

```markdown
## PR Feedback Fix Results

**PR:** #{pr_number} - {title}
**Mode:** {normal|dry-run}

### Issues Fixed ({count})

| File | Line | Type | Fix Applied |
|------|------|------|-------------|
| sdd-loop.sh | 1609 | BUG | Changed to if-not pattern |
| load-test.sh | 392 | SHELLCHECK | Separated local declaration |
| ... | ... | ... | ... |

### Issues Skipped ({count})

| File | Line | Reason |
|------|------|--------|
| other.sh | 42 | Not in PR scope |
| utils.sh | 100 | Reviewer incorrect - code is intentional |
| ... | ... | ... |

### Test Results
- Tests run: {count}
- Passed: {count}
- Failed: 0

### Commit
{commit_hash} pushed to {branch}

### PR Updated
{pr_url}
```

### Next Step Prompt

After displaying the report above, use the **AskUserQuestion** tool to present next steps to the user:

**Question:** "What would you like to do next?"
**Header:** "Next step"
**multiSelect:** false

**Options:**
- Label: "/sdd:pr {TICKET_ID}" | Description: "Check PR status after fixes"
- Label: "/sdd:code-review {TICKET_ID}" | Description: "Verify fixes with code review"

Where {TICKET_ID} is the actual ticket ID from the command execution context, NOT the literal placeholder text.

## Issue Type Decision Tree

```
Is the file changed in this PR?
├── NO → SKIP (out of scope)
└── YES → Continue

Is the reviewer's claim factually correct?
├── NO → SKIP (invalid feedback)
│   └── Document WHY it's incorrect
└── YES/MAYBE → Continue

Is this a real bug or security issue?
├── YES → MUST FIX
└── NO → Continue

Would this change improve the code?
├── NO → SKIP
└── YES → Continue

Is --skip-nits set AND this is style/formatting?
├── YES → SKIP
└── NO → FIX
```

## Validation Examples

### Example 1: Valid Bug (FIX)

**Comment:** "Line 1609: With `set -e`, the script will exit before capturing the return value."

**Validation:**
1. Read file, confirm `set -e` is enabled (line 89)
2. Check the code at line 1609 - yes, it captures `$?` after a command
3. This IS a real bug - the command's non-zero exit would terminate the script
4. **Decision: VALID BUG - FIX**

### Example 2: Invalid Suggestion (SKIP)

**Comment:** "Line 452: The `2>&1` captures stderr which could corrupt the JSON output."

**Validation:**
1. Read the code - JSON is parsed with `jq` afterward
2. If stderr corrupted the output, `jq` would fail and trigger error handling
3. The existing error handling is robust
4. **Decision: INVALID - SKIP (reviewer doesn't see the error handling)**

### Example 3: Out of Scope (SKIP)

**Comment:** "obsidian-plugin/cli.ts:42 - Should use const instead of let."

**Validation:**
1. Check `git diff --name-only` for this PR
2. File `obsidian-plugin/cli.ts` is NOT in the diff
3. **Decision: OUT OF SCOPE - SKIP (not part of this PR's changes)**

## Key Constraints

- NEVER blindly apply reviewer suggestions
- ALWAYS read the actual code first
- ALWAYS run tests after fixes
- Document reasoning for both fixes AND skips
- Group related fixes in single commit
- Fail fast if tests break - investigate before continuing
