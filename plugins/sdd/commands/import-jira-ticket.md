---
description: Import a Jira ticket and create SDD planning documents from it
argument-hint: [JIRA_KEY or URL] [optional: additional instructions]
---

# Import Jira Ticket

## Context

User input: "$ARGUMENTS"
Plugin root: "${CLAUDE_PLUGIN_ROOT}"

## Workflow

**IMPORTANT: You are an orchestrator. You do NOT do the work yourself. You delegate to scripts and agents.**

### Step 1: Parse Arguments

Parse user input to extract:
- **JIRA_KEY**: Required. Can be provided as:
  - Direct Jira key (e.g., UIT-3670, CIA-2201, BE-4567)
  - Full Jira URL (e.g., https://company.atlassian.net/browse/UIT-3670)
- **additional_instructions**: Optional. Any extra context or instructions to augment the Jira ticket description

**URL Extraction (if needed):**

Execute this bash logic to extract the key:

```bash
# Extract first argument (may be URL or direct key)
first_arg=$(echo "$ARGUMENTS" | awk '{print $1}')

# Check if input contains /browse/ pattern and extract key
if [[ "$first_arg" == *"/browse/"* ]]; then
    # Extract everything after /browse/
    key_with_params="${first_arg#*\/browse\/}"
    # Remove query parameters (everything after ?)
    key_no_query="${key_with_params%%\?*}"
    # Remove fragments (everything after #)
    JIRA_KEY="${key_no_query%%\#*}"
else
    # No /browse/ found, use input as-is
    JIRA_KEY="$first_arg"
fi
```

**Validation:**

The JIRA_KEY (extracted or direct) must match pattern: `[A-Z][A-Z0-9]*-[0-9]+` (e.g., UIT-3670, CIA-2201)

**Examples of extraction:**
- Input: `UIT-3670` → JIRA_KEY: `UIT-3670`
- Input: `https://company.atlassian.net/browse/UIT-3670` → JIRA_KEY: `UIT-3670`
- Input: `https://company.atlassian.net/browse/UIT-3670?page=details` → JIRA_KEY: `UIT-3670`
- Input: `/browse/UIT-3670` → JIRA_KEY: `UIT-3670`
- Input: `https://company.atlassian.net/browse/CIA-2201 Focus on performance` → JIRA_KEY: `CIA-2201`

If no JIRA_KEY is provided or extraction fails, report error:
```
ERROR: Jira ticket key required.

Usage: /sdd:import-jira-ticket JIRA_KEY [additional instructions]

JIRA_KEY can be:
  - Direct key: UIT-3670, CIA-2201, BE-4567
  - Full URL: https://company.atlassian.net/browse/UIT-3670

Examples:
  /sdd:import-jira-ticket UIT-3670
  /sdd:import-jira-ticket https://company.atlassian.net/browse/UIT-3670
  /sdd:import-jira-ticket CIA-2201 Focus on performance optimization aspects
  /sdd:import-jira-ticket https://company.atlassian.net/browse/CIA-2201 Focus on performance
```

### Step 2: Fetch Jira Ticket Details

**Execute command to retrieve Jira ticket:**

```bash
acli jira workitem view {JIRA_KEY} --fields '*all' --json
```

This returns JSON with:
- `key`: The ticket key (e.g., UIT-3670)
- `summary`: Ticket title/summary
- `description`: Full description
- `issuetype`: Story, Bug, Task, Epic, etc.
- `status`: Current status
- `assignee`: Assigned user
- `priority`: Priority level
- Additional fields as available

If the command fails, report:
```
ERROR: Could not fetch Jira ticket {JIRA_KEY}

Possible causes:
- Ticket does not exist
- Not authenticated (run: acli jira auth)
- Network/permission issues

Run manually to debug: acli jira workitem view {JIRA_KEY}
```

### Step 3: Derive Identifiers

From the Jira ticket:
- **TICKET_ID**: Use the JIRA_KEY directly (e.g., UIT-3670)
- **name**: Derive kebab-case name from summary (e.g., "React Router Upgrade" → "react-router-upgrade")

Check for uniqueness:
```bash
ls -d ${SDD_ROOT_DIR:-/app/.sdd}/tickets/${TICKET_ID}_* ${SDD_ROOT_DIR:-/app/.sdd}/archive/tickets/${TICKET_ID}_* 2>/dev/null
```

If ticket already exists, report and ask user how to proceed.

### Step 4: Scaffold Structure

**Delegate to script:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/scripts/scaffold-ticket.sh "{TICKET_ID}" "{name}"
```

This creates:
- `${SDD_ROOT_DIR}/tickets/{TICKET_ID}_{name}/README.md`
- `${SDD_ROOT_DIR}/tickets/{TICKET_ID}_{name}/planning/` with template files
- `${SDD_ROOT_DIR}/tickets/{TICKET_ID}_{name}/tasks/`

### Step 5: Fill Planning Documents

**Delegate to ticket-planner agent (Sonnet):**

```
Assignment: Create comprehensive planning documents for ticket {TICKET_ID}_{name}

Context:
- Ticket path: ${SDD_ROOT_DIR}/tickets/{TICKET_ID}_{name}/
- Jira ticket key: {JIRA_KEY}
- Jira ticket type: {issuetype}
- Jira ticket status: {status}
- Jira ticket summary: {summary}
- Jira ticket description:
{description}

Additional instructions: {additional_instructions or "None provided"}

Instructions:
1. Use the Jira ticket information as the primary source of requirements
2. Research the problem space and codebase to understand implementation context
3. Fill analysis.md with problem analysis (incorporate Jira description)
4. Create architecture.md with solution design
5. Define plan.md with phased execution
6. Write quality-strategy.md with testing approach
7. Complete security-review.md with security assessment
8. Update README.md with overview (reference Jira ticket key)

Important:
- The Jira ticket description is the source of truth for requirements
- Additional instructions supplement but don't replace Jira requirements
- Include Jira ticket reference in README.md header
- Task IDs will use format: {TICKET_ID}.1001, {TICKET_ID}.2001, etc.

Follow enterprise-grade quality standards with disciplined scope management.

Return: Summary of planning decisions made
```

### Step 6: Log Creation

Log the ticket creation event:

```bash
SDD_ROOT="${SDD_ROOT_DIR:-/app/.sdd}"
mkdir -p "$SDD_ROOT/logs"
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")|TICKET_IMPORTED|{TICKET_ID}|-|import-jira-ticket|Imported from Jira {JIRA_KEY}" >> "$SDD_ROOT/logs/workflow.log"
```

### Step 7: Report

```
TICKET IMPORTED: {TICKET_ID}_{name}

Source: Jira {JIRA_KEY}
Type: {issuetype}
Status: {status}

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

Jira Integration:
- Ticket imported from: {JIRA_KEY}
- Task IDs will be: {TICKET_ID}.1001, {TICKET_ID}.2001, etc.

---
RECOMMENDED NEXT STEP: /sdd:review {TICKET_ID}
Verify imported planning quality before proceeding.
```

## Key Constraints

- ALWAYS use the Jira ticket key as the TICKET_ID
- Use scaffold-ticket.sh for structure
- Use ticket-planner agent for content
- DO NOT write planning docs yourself
- DO NOT skip any planning document
- DO NOT modify the Jira ticket (read-only integration)
- Include Jira ticket reference in generated documentation

## Examples

```bash
# Direct key (existing behavior)
/sdd:import-jira-ticket UIT-3670

# Full Jira URL (new behavior)
/sdd:import-jira-ticket https://company.atlassian.net/browse/UIT-3670

# URL with query parameters (new behavior)
/sdd:import-jira-ticket https://company.atlassian.net/browse/UIT-3670?page=details

# Import with additional context (direct key)
/sdd:import-jira-ticket UIT-3670 Focus on the ui-reuse migration aspects

# Import with additional context (URL)
/sdd:import-jira-ticket https://company.atlassian.net/browse/UIT-3670 Focus on the ui-reuse migration aspects

# Import a bug ticket (URL)
/sdd:import-jira-ticket https://company.atlassian.net/browse/BUG-1234 This is a critical production issue

# Import with specific phase guidance (URL)
/sdd:import-jira-ticket https://company.atlassian.net/browse/CIA-2201 Phase 1 should focus on API changes only
```
