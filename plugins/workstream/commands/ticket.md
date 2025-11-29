---
description: Complete a single ticket with full verification workflow
argument-hint: [TICKET_ID like SLUG-1001]
---

# Single Ticket Workflow

## Context

Ticket ID: $ARGUMENTS
Ticket pattern: `.crewchief/projects/**/tickets/$ARGUMENTS_*.md`

## Workflow

**IMPORTANT: You are an orchestrator. You coordinate the implementation, testing, verification, and commit phases by delegating to appropriate agents.**

### Step 1: Locate Ticket

```bash
find .crewchief/projects -name "${ARGUMENTS}_*.md" -type f 2>/dev/null
```

Read the ticket to understand:
- Acceptance criteria
- Primary agent assigned
- Technical requirements
- Dependencies

### Step 2: Check Dependencies

If ticket has dependencies (e.g., depends on SLUG-1001):
1. Check if dependency tickets are verified
2. If not, report and suggest working on dependency first
3. If satisfied, proceed

### Step 3: Implementation

**Delegate to the primary implementation agent (from ticket's "Agents" section):**

```
Task: Implement ticket {TICKET_ID}

Context:
- Ticket: {ticket_path}
- Requirements: {from ticket}

Instructions:
1. Read and understand the ticket fully
2. Implement all acceptance criteria
3. Follow technical requirements
4. Check the "Task completed" checkbox when done
5. Note any issues or blockers

Return: Summary of implementation done
```

### Step 4: Testing

**Delegate to test-runner agent (Haiku):**

```
Task: Run tests for ticket {TICKET_ID}

Context:
- Changed files: {from git status}
- Test scope: {from quality strategy or ticket}

Instructions:
1. Run appropriate test suite
2. Report pass/fail results
3. If all pass, confirm "Tests pass" checkbox can be checked

Return: Test results summary
```

If tests fail, return to implementation agent to fix.

### Step 5: Verification

**Delegate to verify-ticket agent (Sonnet):**

```
Task: Verify ticket {TICKET_ID} implementation

Context:
- Ticket: {ticket_path}
- Implementation complete
- Tests passing

Instructions:
1. Check each acceptance criterion against code
2. Verify technical requirements met
3. Confirm test execution evidence exists
4. If all verified, check "Verified" checkbox
5. If not verified, report what's missing

Return: Verification result (pass/fail with details)
```

If verification fails, return to implementation agent.

### Step 6: Commit

**Delegate to commit-ticket agent (Haiku):**

```
Task: Commit verified changes for ticket {TICKET_ID}

Context:
- Ticket verified
- Changes staged

Instructions:
1. Confirm ticket is verified
2. Stage all relevant changes
3. Create conventional commit
4. Report commit hash

Return: Commit confirmation
```

### Step 7: Report

```
TICKET COMPLETE: {TICKET_ID}

Title: {ticket title}

Status:
✓ Task completed
✓ Tests pass
✓ Verified
✓ Committed: {commit_hash}

Changes:
- {file1}: {brief description}
- {file2}: {brief description}

Commit: {type}({scope}): {TICKET_ID} {message}

Next: {Next ticket in sequence or project complete}
```

## Failure Handling

If any phase fails:
1. Report specific failure reason
2. DO NOT proceed to next phase
3. Suggest remediation
4. Allow user to continue or fix

## Key Constraints

- Follow phase order: implement → test → verify → commit
- Use appropriate agent for each phase
- DO NOT skip verification
- DO NOT implement code yourself
- DO NOT commit without verification
