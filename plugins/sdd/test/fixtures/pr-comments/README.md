# PR Comments Test Fixtures

This directory contains test fixtures for the `/sdd:pr-comments` command, simulating various GitHub PR comment scenarios for testing and validation.

## Purpose

These fixtures enable:
- Integration testing without requiring live GitHub API access
- Validation of comment classification heuristics
- Testing of edge cases and error handling
- Performance testing with large comment volumes
- Regression testing when modifying the command

## gh CLI Version Reference

These fixtures are based on the JSON structure returned by:
```bash
gh pr view PR_NUMBER --json comments,reviews,title,url,number
```

**gh CLI version used:** 2.40.0+ (January 2025)

If the gh CLI output format changes in future versions, these fixtures may need to be updated.

## Fixture Files

### validation-dataset.json
**Purpose:** Real-world comment examples from actual QuickBase PRs
**Content:** 26 comments (14 SIMPLE, 12 COMPLEX) collected from production PRs
**Source:** Based on validation-examples.md analysis of PRs #43887, #43853, #43832, #43829, #43824
**Use case:** Validate classification accuracy against real data
**Expected classifications:**
- SIMPLE (14): Short comments with typos, nits, simple questions, formatting issues
- COMPLEX (12): Code blocks, architectural discussions, multi-part feedback, detailed reviews
- Meta-comments (3): Should be filtered out (emoji-only, "Testing locally", "LGTM")

### pr-mixed-comments.json
**Purpose:** Typical PR with a realistic mix of comment types
**Content:** 10 total comments (6 SIMPLE, 4 COMPLEX)
**Breakdown:**
- PR-level comments: 6 (mix of simple and complex)
- Review comments: 4 with inline file/line references
**Expected behavior:**
- Console output shows all comments with classifications
- Analysis file includes both SIMPLE and COMPLEX sections
- Demonstrates typical workflow scenario

### pr-no-comments.json
**Purpose:** PR with zero comments
**Content:** Empty comments and reviews arrays
**Expected behavior:**
- Command should complete successfully
- Console displays "No comments found on PR #789"
- No analysis file created (or empty sections if TICKET_ID provided)
- Graceful handling of empty data

### pr-all-simple.json
**Purpose:** PR with only nit-level feedback
**Content:** 10 SIMPLE comments (typos, formatting, minor issues)
**Characteristics:**
- All comments <30 words
- No code blocks
- Simple suggestions
- Quick fixes only
**Expected behavior:**
- All classified as SIMPLE with high confidence
- Analysis suggests addressing all in current session
- No follow-up tasks recommended

### pr-all-complex.json
**Purpose:** PR requiring significant follow-up work
**Content:** 7 COMPLEX comments (architectural, performance, security concerns)
**Characteristics:**
- Long-form feedback (60-200 words)
- Code block suggestions
- Multi-point reviews
- Architectural discussions
- Security/performance concerns
**Expected behavior:**
- All classified as COMPLEX
- Analysis recommends creating follow-up tasks
- Each comment should have "Recommended Task" field

### pr-large-volume.json
**Purpose:** Test scalability and truncation behavior
**Content:** 125 total comment items (110 PR comments + 15 review inline comments)
**Breakdown:**
- 60 SIMPLE comments
- 50 COMPLEX comments
- 5 reviews with 3 inline comments each
**Expected behavior:**
- Console output truncates at 20 items with warning:
  - "⚠️  Large PR detected (125 comments)"
  - "Showing first 20 items. See analysis file for complete data."
  - "...and 105 more comments."
- Analysis file contains ALL comments (no truncation)
- Performance should be acceptable (<5 seconds)
- No memory issues

### pr-edge-cases.json
**Purpose:** Test unusual formatting and special characters
**Content:** 13 comments with edge case scenarios
**Edge cases covered:**
- Unicode characters (Chinese text)
- Emoji-only comments (should filter)
- Markdown formatting (bold, italic, links, images)
- Multiple code blocks in single comment
- Very long comment (300+ words)
- Multiple empty lines
- Special characters (<>&"'`~!@#$%^&*()_+-=[]{}|;:,.<>?/\)
- Nested quotes
- Markdown tables
- Task lists with checkboxes
- Mixed formatting with urgency markers
- URL-heavy comments
- @mentions
- Inline comments on deeply nested files
- Unicode in file names
**Expected behavior:**
- Handles all special characters without crashing
- Properly escapes markdown in output
- Emoji-only comment filtered as meta-comment
- Very long comment classified as COMPLEX
- Task lists with 4+ items → COMPLEX
- Mixed formatting comment → COMPLEX

### pr-malformed.json
**Purpose:** Test error handling for invalid/missing data
**Content:** Comments and reviews with malformed structure
**Malformed scenarios:**
- `null` author
- Missing body field
- `null` body
- Empty string body
- Empty author object
- Missing author wrapper
- Wrong object structure
- Missing comments array in review
- `null` comments array
- Missing line number in inline comment
- Missing path in inline comment
- String instead of number for line
- All fields `null`
- Missing author in review
- Missing state field
**Expected behavior:**
- Command should not crash
- Default to "unknown" for missing authors
- Skip comments with missing/null body
- Log warnings for malformed data
- Continue processing valid comments
- Graceful degradation

## Using These Fixtures

### Manual Testing

Test a fixture by temporarily modifying the `/sdd:pr-comments` command to read from a local file instead of calling gh CLI:

```bash
# Replace gh CLI call with file read
pr_json=$(cat /path/to/fixture.json)
```

Or create a wrapper script:
```bash
#!/bin/bash
# test-pr-comments.sh
export FIXTURE_FILE="$1"
# Modify command to check for FIXTURE_FILE env var
/sdd:pr-comments test TICKET_ID
```

### Integration Testing

For integration tests that mock the gh CLI:

```bash
# Create mock gh command
function gh() {
  if [[ "$1" == "pr" && "$2" == "view" ]]; then
    cat /app/claude-code-plugins/plugins/sdd/test/fixtures/pr-comments/pr-mixed-comments.json
  fi
}
export -f gh

# Run command
/sdd:pr-comments 456 TEST-123
```

### Validation Script

```bash
#!/bin/bash
# validate-fixtures.sh - Verify all fixtures are valid JSON

fixtures_dir="/app/claude-code-plugins/plugins/sdd/test/fixtures/pr-comments"

for fixture in "$fixtures_dir"/*.json; do
  echo "Validating: $(basename "$fixture")"
  if jq empty "$fixture" 2>/dev/null; then
    echo "  ✓ Valid JSON"
  else
    echo "  ✗ Invalid JSON"
    exit 1
  fi
done

echo ""
echo "All fixtures are valid JSON"
```

## Expected Classification Heuristics

Based on architecture.md (with validated adjustments from validation-examples.md):

### SIMPLE Indicators
- Word count < 60
- Keywords: typo, nit, minor, missing, rename, add comment, whitespace, formatting, spelling
- Single question
- Inline code only (single backticks)

### COMPLEX Indicators
- Word count >= 60
- Code blocks (triple backticks) - **STRONG signal**
- 3+ bullet points or list items
- Keywords: consider, should we, redesign, refactor, feature, architecture, pattern, might want, performance, security, decompose
- Multiple file references
- Embedded images
- Questions about design decisions

### Filter Patterns (Meta-comments)
- "LGTM"
- "Testing locally"
- "Approved"
- Emoji-only
- Empty body

### Conflict Resolution
```
if (COMPLEX_indicators > 0) {
  classification = "COMPLEX"
  confidence = SIMPLE_indicators > 0 ? "low" : "high"
} else if (SIMPLE_indicators > 0) {
  classification = "SIMPLE"
  confidence = "high"
} else {
  classification = "COMPLEX"  // Conservative default
  confidence = "medium"
}
```

## Testing Checklist

When testing the `/sdd:pr-comments` command with these fixtures:

- [ ] **validation-dataset.json**: Verify 85%+ accuracy on real PR data
- [ ] **pr-mixed-comments.json**: Confirms typical workflow works correctly
- [ ] **pr-no-comments.json**: Handles empty PR gracefully
- [ ] **pr-all-simple.json**: All classified as SIMPLE
- [ ] **pr-all-complex.json**: All classified as COMPLEX
- [ ] **pr-large-volume.json**: Console truncates at 20, file contains all 125
- [ ] **pr-edge-cases.json**: No crashes on special characters/formatting
- [ ] **pr-malformed.json**: Graceful error handling for invalid data

## Updating Fixtures

If the gh CLI output format changes:

1. Run `gh pr view <PR_NUMBER> --json comments,reviews,title,url,number` against a real PR
2. Save the output to compare with fixture structure
3. Update fixtures to match new format
4. Update the "gh CLI Version Reference" section above
5. Document any breaking changes in this README

## Fixture Statistics

| Fixture | Comments | Reviews | Inline | Total Items | Size |
|---------|----------|---------|--------|-------------|------|
| validation-dataset.json | 18 | 7 | 4 | 29 | ~8 KB |
| pr-mixed-comments.json | 6 | 2 | 3 | 11 | ~3 KB |
| pr-no-comments.json | 0 | 0 | 0 | 0 | ~200 B |
| pr-all-simple.json | 7 | 1 | 3 | 11 | ~2 KB |
| pr-all-complex.json | 3 | 3 | 2 | 8 | ~5 KB |
| pr-large-volume.json | 110 | 5 | 15 | 130 | ~50 KB |
| pr-edge-cases.json | 13 | 1 | 3 | 17 | ~6 KB |
| pr-malformed.json | 7 | 5 | 4 | 16 | ~3 KB |

## Format Specification

For details on parsing the output format (`pr-comments-analysis.md`), see the Format Specification section in `/app/claude-code-plugins/plugins/sdd/commands/pr-comments.md`.

Key points:
- Check `format_version` field in Metadata JSON block (current: "1.0")
- Parse sections by header pattern: `^## (SIMPLE|COMPLEX) Comments$`
- Extract individual comments by subsection: `^### (SIMPLE|COMPLEX)-\d+:`
- Field patterns are consistent across all comments
- Section headers enable regex-based parsing by downstream tools
