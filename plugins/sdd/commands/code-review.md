---
description: |
  Performs comprehensive post-implementation code review of a completed ticket.
  Produces 12-section analysis with confidence scoring and recommendations.

  Reviews implementation against planning documents, evaluates code quality,
  identifies security vulnerabilities, assesses performance, and generates
  actionable recommendations categorized by severity (CRITICAL/HIGH/MEDIUM/NITPICK).

  Usage examples:
  - Basic: /sdd:code-review DEEPREV
  - Focused: /sdd:code-review DEEPREV --focus security
  - Force incomplete: /sdd:code-review DEEPREV --force
argument-hint: TICKET_ID [--focus AREA] [--force]
---

# Code Review

## Context

User input: "$ARGUMENTS"
Ticket folder: `${SDD_ROOT_DIR}/tickets/$ARGUMENTS_*/`

## Workflow

**IMPORTANT: You are an orchestrator. You do NOT do the review yourself. You delegate to the code-reviewer agent.**

### Step 0: Parse Arguments

Extract from `$ARGUMENTS`:
- **TICKET_ID**: The ticket identifier (required, first argument)
- **--focus AREA**: Optional focus area (security, performance, architecture, quality)
- **--force**: Optional flag to allow review of incomplete ticket

Parse logic:
1. Extract TICKET_ID (first non-flag argument)
2. Check for `--focus` followed by area value
3. Check for `--force` flag

### Step 1: Locate Ticket

Find the ticket folder:
```bash
ls -d ${SDD_ROOT_DIR:-/app/.sdd}/tickets/${TICKET_ID}_* 2>/dev/null
```

**Error handling**:
- If not found: "Ticket {TICKET_ID} not found in ${SDD_ROOT_DIR:-/app/.sdd}/tickets/"
- If no TICKET_ID provided: "Usage: /sdd:code-review TICKET_ID [--focus AREA] [--force]"

### Step 2: Validate Ticket Completion (unless --force)

**If --force flag NOT provided:**

1. Check all task files for completion status:
   ```bash
   ls ${TICKET_PATH}/tasks/*.md 2>/dev/null
   ```

2. For each task file, check for the completion checkbox pattern:
   - Pattern: `- [x] **Task completed**`
   - If ANY task is incomplete (checkbox not checked): Halt with error

3. If incomplete tasks found, report:
   ```
   ❌ Ticket {TICKET_ID} has incomplete tasks:

   Incomplete:
   - {TASK_ID_1}: {task name}
   - {TASK_ID_2}: {task name}

   Complete all tasks before code review, or use --force to proceed anyway.

   Usage: /sdd:code-review {TICKET_ID} --force
   ```

**If --force flag PROVIDED:**

Display warning:
```
⚠️  WARNING: Reviewing incomplete ticket
⚠️  Results may be limited without all tasks completed
⚠️  Proceeding anyway due to --force flag...

```

### Step 3: Validate Focus Parameter (if provided)

**If --focus flag provided:**

Valid focus areas:
- `security`
- `performance`
- `architecture`
- `quality`

**Error handling**:
If invalid value provided:
```
❌ Invalid --focus value: {value}

Valid options: security, performance, architecture, quality

Usage: /sdd:code-review {TICKET_ID} --focus {security|performance|architecture|quality}
```

### Step 4: Token Cost Estimation

Calculate estimated token usage to set user expectations.

**Formula**:
```
total_tokens = (planning_files × 500) + (task_files × 300) + (diff_lines × 5) + 12000
```

**Component calculations**:

1. **Planning files count**:
   ```bash
   ls ${TICKET_PATH}/planning/*.md 2>/dev/null | wc -l
   ```
   Token estimate: `count × 500`

2. **Task files count**:
   ```bash
   ls ${TICKET_PATH}/tasks/*.md 2>/dev/null | wc -l
   ```
   Token estimate: `count × 300`

3. **Git diff line count** (with error handling):
   ```bash
   git diff main...HEAD 2>/dev/null | wc -l
   ```
   - If git command fails: Set diff_lines = 0, note "git diff unavailable"
   - If diff >3000 lines: Note "diff will be summarized"
   Token estimate: `lines × 5`

4. **Report output baseline**: `12000` (for 12-section report)

**Display format**:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TOKEN COST ESTIMATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Estimated token usage: ~{total}k tokens

Breakdown:
  Planning docs:  {count} files (~{tokens} tokens)
  Task files:     {count} files (~{tokens} tokens)
  Code changes:   {lines} lines (~{tokens} tokens)
  Report output:  ~12k tokens

{If git unavailable: "Note: Git diff unavailable, estimate may be low"}
{If diff >3000: "Note: Large diff will be summarized, actual usage may be lower"}
```

**Warning thresholds**:

- **>20k tokens**:
  ```
  ⚠️  This will be a large analysis. Estimated: {total}k tokens
  ```

- **>40k tokens**:
  ```
  ⚠️  LARGE ANALYSIS: {total}k tokens
  ⚠️  Consider using --focus flag to reduce scope

  Examples:
    /sdd:code-review {TICKET_ID} --focus security
    /sdd:code-review {TICKET_ID} --focus performance
  ```

### Step 5: Delegate to code-reviewer Agent

**Delegate to code-reviewer agent (Sonnet):**

```
Assignment: Perform comprehensive code review for ticket {TICKET_ID}

Context:
- Ticket path: {TICKET_PATH}
- Focus area: {area if provided, otherwise "none - full analysis"}
- Planning docs: {TICKET_PATH}/planning/
- Task files: {TICKET_PATH}/tasks/
- Deliverables: {TICKET_PATH}/deliverables/
- Completion status: {complete/incomplete with --force}

Instructions:
1. Analyze ticket context:
   - Read all planning documents (analysis.md, architecture.md, plan.md, etc.)
   - Review all task files for acceptance criteria and scope
   - Read existing deliverables
   - Get git diff: git diff main...HEAD
     - If diff >3000 lines: Summarize per-file changes instead
     - If git fails: Proceed without diff, note limitation

2. Apply 12-section code review methodology:
   - Section 1: Executive Summary (write LAST)
   - Section 2: Sequence Diagrams
   - Section 3: Component Architecture & Dependency Map
   - Section 4: User Journeys
   - Section 5: Risk Analysis
   - Section 6: Edge Case Analysis
   - Section 7: Code Quality Evaluation
   - Section 8: Security Review
   - Section 9: Performance Review
   - Section 10: Cross-Domain Considerations
   - Section 11: Meta-Analysis
   - Section 12: Confidence Score & Recommendations

3. Write report INCREMENTALLY to {TICKET_PATH}/deliverables/code-review-report.md:
   - Write each section immediately after completing analysis
   - DO NOT hold full report in memory
   - Provides progress visibility and prevents truncation

4. Calculate confidence score using 8-dimension rubric:
   - Correctness (20%), Security (15%), Performance (10%)
   - Maintainability (15%), Test Coverage (15%), Edge Cases (10%)
   - Integration (10%), Documentation (5%)
   - Total: 0-100 with interpretation

5. Generate categorized recommendations:
   - CRITICAL: Must fix before merge (security, data loss, breaking)
   - HIGH: Should fix before merge (bugs, performance, error handling)
   - MEDIUM: Could fix or defer (code quality, missing tests, docs)
   - NITPICK: Optional improvements (style, minor refactoring)

{If --focus provided:}
6. Enhanced detail for --focus={area}:
   - All 12 sections remain present
   - Focus area gets deeper analysis with more examples
   - Non-focus areas abbreviated with "⚠️ Abbreviated" markers
   - Expected token reduction: 30-50%

Return summary with:
- Confidence score and interpretation
- Recommendation counts by category
- Top 3 issues (if any)
- Overall status (PROCEED | PROCEED WITH CAUTION | HOLD FOR FIXES)
```

### Step 6: Report Results

After code-reviewer agent completes, display summary:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CODE REVIEW COMPLETE: {TICKET_NAME}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Confidence Score: {XX}/100 ({interpretation})

Recommendations:
  CRITICAL: {count}
  HIGH: {count}
  MEDIUM: {count}
  NITPICK: {count}

{If any CRITICAL or HIGH recommendations exist:}
Top Issues:
1. [CRITICAL] {issue description with file reference}
2. [HIGH] {issue description with file reference}
3. [HIGH] {issue description with file reference}

Full report: {TICKET_PATH}/deliverables/code-review-report.md

```

### Next Step Prompt

After displaying the report above, use the **AskUserQuestion** tool to present next steps based on issue severity:

**Question:** "What would you like to do next?"
**Header:** "Next step"
**multiSelect:** false

**If CRITICAL issues found (count > 0):**
**Options:**
- Label: "Fix CRITICAL issues before proceeding" | Description: "Address blocking issues first"
- Label: "/sdd:code-review {TICKET_ID}" | Description: "Re-run code review after fixes"

**If HIGH issues found (count > 0, no CRITICAL issues):**
**Options:**
- Label: "/sdd:pr {TICKET_ID}" | Description: "Create pull request (HIGH issues documented in PR description)"
- Label: "/sdd:code-review {TICKET_ID}" | Description: "Re-run after addressing HIGH issues"

**If only MEDIUM or lower severity issues (no HIGH or CRITICAL):**
**Options:**
- Label: "/sdd:pr {TICKET_ID}" | Description: "Create pull request"
- Label: "/sdd:archive {TICKET_ID}" | Description: "Archive ticket if no PR needed"

**If clean (no significant issues):**
**Options:**
- Label: "/sdd:pr {TICKET_ID}" | Description: "Create pull request"
- Label: "/sdd:archive {TICKET_ID}" | Description: "Archive ticket"

Where {TICKET_ID} is the actual ticket ID from the command execution context, NOT the literal placeholder text. Determine which severity path to use based on the CRITICAL, HIGH, and MEDIUM issue counts from the report above.

## Error Handling

Comprehensive error handling for all failure scenarios:

| Error Condition | Error Message | Exit |
|----------------|---------------|------|
| No TICKET_ID provided | "Usage: /sdd:code-review TICKET_ID [--focus AREA] [--force]" | Yes |
| Ticket not found | "Ticket {TICKET_ID} not found in ${SDD_ROOT_DIR:-/app/.sdd}/tickets/" | Yes |
| Invalid --focus value | "Invalid --focus value: {value}\n\nValid options: security, performance, architecture, quality" | Yes |
| Incomplete tasks (no --force) | "Ticket {TICKET_ID} has incomplete tasks:\n\nIncomplete:\n- {task list}\n\nComplete all tasks or use --force" | Yes |
| Git command failures | Log warning, proceed with estimation set to 0, note in output | No |
| Agent delegation failure | Report error from agent, include in output | Yes |

## Example Usage

```bash
# Basic usage - full analysis of completed ticket
/sdd:code-review DEEPREV

# Focus on security aspects only
/sdd:code-review DEEPREV --focus security

# Focus on performance analysis
/sdd:code-review API --focus performance

# Force review of incomplete ticket (e.g., partial review during development)
/sdd:code-review DEEPREV --force

# Combined: focused review of incomplete ticket
/sdd:code-review CACHE --focus architecture --force

# Review different focus areas
/sdd:code-review AUTH --focus quality
```

## When to Use Code Review

**Recommended workflow position**:
1. Complete all ticket tasks: `/sdd:do-all-tasks {TICKET_ID}`
2. Run code review: `/sdd:code-review {TICKET_ID}`
3. Address CRITICAL/HIGH issues (if any)
4. Create PR: `/sdd:pr {TICKET_ID}`

**Use cases**:

1. **Pre-PR validation** (most common):
   - After all tasks completed
   - Before creating pull request
   - Ensures production-ready quality

2. **Focused analysis**:
   - Security review before deploying to production
   - Performance assessment for critical features
   - Architecture validation for major changes

3. **Mid-development check** (with --force):
   - Early feedback during implementation
   - Validate approach before completing all tasks
   - Identify issues before investing more time

4. **Post-feedback iteration**:
   - After addressing initial review findings
   - Re-validate after fixing CRITICAL/HIGH issues
   - Confirm improvements before PR

**Comparison to /sdd:review**:

| Command | When | Purpose | Output |
|---------|------|---------|--------|
| `/sdd:review` | Before/during planning | Validate requirements and task design | Planning review report |
| `/sdd:code-review` | After implementation | Evaluate code quality and production readiness | Comprehensive code review report |

## Key Constraints

- **Orchestrator role**: DO NOT analyze code yourself, delegate to code-reviewer agent
- **Agent dependency**: Requires code-reviewer agent at `plugins/sdd/agents/code-reviewer.md`
- **Completion validation**: Default behavior requires all tasks complete (override with --force)
- **Token transparency**: Always show cost estimation before analysis
- **Incremental reporting**: Agent writes report section-by-section (not all at once)
- **Focus flag optional**: Full analysis by default, focus reduces scope and tokens
- **Report location**: Always in `{TICKET_PATH}/deliverables/code-review-report.md`
