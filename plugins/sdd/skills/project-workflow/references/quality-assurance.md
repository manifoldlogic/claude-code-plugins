# Quality Assurance Mechanisms

This document describes all quality gates and validation mechanisms in the SDD plugin workflow.

## Quality Philosophy

The SDD plugin uses multiple quality gates to ensure work quality and prevent common errors:

1. **Shift-Left Approach**: Catch issues early (planning validation before task creation)
2. **Defense in Depth**: Multiple gates at different lifecycle stages
3. **Clear Feedback**: Actionable error messages guide users to resolution
4. **Fail-Safe Defaults**: Gates block by default; overrides require explicit action
5. **Audit Trail**: All verification decisions logged for compliance

## Quality Gates Overview

```
[Ticket Init] → [Planning] → [Review] → 🛡️ Pre-Decompose Gate → [Decompose]
                                                    ↓
                                          [Tasks Created]
                                                    ↓
                                   🛡️ Execute Pre-Check Gate
                                                    ↓
                                          [Task Execution]
                                                    ↓
                                   🛡️ Dependency Validation Gate
                                                    ↓
                                             [Do Task]
                                                    ↓
                                        🛡️ Verify-Task Gate
                                                    ↓
                                       🛡️ Commit Requirements
                                                    ↓
                                      🛡️ Archive Requirements
```

---

## Quality Gates by Lifecycle Phase

### Planning Phase

No automated gates in planning phase - this phase relies on agent guidance and templates.

### Pre-Execution Phase (Task Creation)

#### Pre-Decompose Validation

**Purpose**: Ensures ticket planning is complete and substantial before creating tasks

**Triggered**: When running `/sdd:create-tasks [TICKET_ID]`

**Enforcement**: Hard block (decompose will not proceed if validation fails)

**Checks Performed**:
- `planning/plan.md` exists
- `planning/plan.md` has >100 words (substantial content)
- `planning/architecture.md` exists
- `planning/architecture.md` has >100 words (substantial content)

**Example Scenarios Caught**:

1. **Scenario**: User runs `/sdd:create-tasks` immediately after `/sdd:plan-ticket`
   - **Gate Response**: `❌ VALIDATION FAILED: planning/plan.md - NOT FOUND (REQUIRED)`
   - **Resolution**: Complete planning documents before decomposing

2. **Scenario**: User creates stub planning docs but doesn't fill them
   - **Gate Response**: `❌ VALIDATION FAILED: planning/plan.md has insufficient content (15 words, need 100+)`
   - **Resolution**: Add substantial content to planning docs

**Bypass**: Not available - planning must be complete

**Implemented In**: `/sdd:create-tasks` command (Step 2)

---

### Execution Phase

#### Execute Pre-Check

**Purpose**: Ensures ticket has been reviewed and tasks exist before starting execution

**Triggered**: When running `/sdd:do-all-tasks [TICKET_ID]`

**Enforcement**: Hard block (execution will not proceed if validation fails)

**Checks Performed**:
- `planning/ticket-review.md` exists
- Review document contains "Ready", "PASS", or "Proceed" keywords
- `tasks/` directory has task files
- Task files follow naming convention `TICKET_ID.XXXX_name.md` (warning only)

**Example Scenarios Caught**:

1. **Scenario**: User runs `/sdd:do-all-tasks` without running `/sdd:review`
   - **Gate Response**: `✗ Review document missing (ticket-review.md)`
   - **Resolution**: Run `/sdd:review {TICKET_ID}` first

2. **Scenario**: User runs `/sdd:do-all-tasks` after review returned FAIL
   - **Gate Response**: `✗ Review status: Not approved`
   - **Resolution**: Address review findings, re-run `/sdd:review`

3. **Scenario**: User runs `/sdd:do-all-tasks` without running `/sdd:create-tasks`
   - **Gate Response**: `✗ No tasks found in tasks/ directory`
   - **Resolution**: Run `/sdd:create-tasks {TICKET_ID}` first

**Bypass**: Not available - review and tasks must exist

**Implemented In**: `/sdd:do-all-tasks` command (Pre-Execution Checklist)

---

#### Task Dependency Validation

**Purpose**: Prevents tasks from running if prerequisite tasks are incomplete

**Triggered**: When running `/sdd:do-task [TASK_ID]`

**Enforcement**: Hard block (implementation will not proceed if dependencies unsatisfied)

**Checks Performed**:
- Parses `## Dependencies` section from task file
- Validates internal dependencies (same ticket) - checks "Task completed" checkbox
- Validates external dependencies (other tickets) - checks task completion or archived status
- Archived external tickets are treated as complete

**Example Scenarios Caught**:

1. **Scenario**: User tries to implement task that depends on incomplete task
   - **Gate Response**: `❌ SDDREV.1001 - Not complete (Task completed checkbox unchecked)`
   - **Resolution**: Complete dependency task first

2. **Scenario**: User tries to implement task that depends on missing task
   - **Gate Response**: `❌ OTHER.1001 - External task file not found`
   - **Resolution**: Verify dependency exists and create if needed

3. **Scenario**: User tries to implement task with archived dependency
   - **Gate Response**: `✓ EXTERNAL.2003 - Complete (archived)`
   - **Resolution**: None needed - archived tickets count as complete

**Bypass**: Not available - dependencies must be satisfied

**Implemented In**: `/sdd:do-task` command (Step 2: Check Dependencies)

---

### Verification Phase

#### Verify-Task Agent

**Purpose**: Ensures completed work matches all acceptance criteria before committing

**Triggered**: After implementation complete, via verify-task agent

**Enforcement**: Hard block (commit-task will not proceed without verification)

**Checks Performed**:
- "Task completed" checkbox is checked
- "Tests pass" checkbox is checked (with execution evidence if tests exist)
- All acceptance criteria verified against actual code changes
- All technical requirements addressed
- All listed files actually modified
- No TODO comments or incomplete implementations
- Test execution evidence exists (if tests created/modified)

**Example Scenarios Caught**:

1. **Scenario**: Developer marks task complete but missed an acceptance criterion
   - **Gate Response**: `✗ [UNMET criterion] - Issue: No endpoint implementation found`
   - **Resolution**: Implement missing functionality

2. **Scenario**: Developer checks "Tests pass" without actually running tests
   - **Gate Response**: `✗ [CRITICAL] "Tests pass" checked but no test execution evidence found`
   - **Resolution**: Run tests and capture output

3. **Scenario**: Developer's implementation is incomplete
   - **Gate Response**: `✗ TODO comment found in src/handler.rs:45`
   - **Resolution**: Complete the TODO or remove if not needed

**Bypass**: Not available - verification is mandatory quality gate

**Implemented In**: `verify-task` agent

**Audit Trail**: All verification decisions logged to "Verification Audit" table in task file

---

#### SDD Reference Check Gate

**Purpose**: Prevents hardcoded .sdd directory references in production code

**Triggered**:
- PostToolUse hook (warning): Immediately when editing/writing files
- verify-task agent (blocking): During task verification Step 2.5

**Enforcement**:
- PostToolUse: Warning only (non-blocking)
- verify-task: Hard block (verification fails if violations found)

**What It Checks**:
Production code files (*.ts, *.tsx, *.js, *.jsx, *.py, *.rs, *.go) for references to:
- `.sdd/` or `.sdd\` - Directory path references
- `SDD_ROOT_DIR` - Environment variable name (with word boundaries)
- `${SDD_ROOT` - Shell variable expansion
- `/app/.sdd` - Hardcoded default path

**Exclusions** (files NOT checked):
- Files in `.sdd/` directory (planning documents)
- Files in `plugins/` directory (Claude Code plugins need SDD access)
- Documentation files (*.md) anywhere
- Config files (*.json, *.yaml, *.yml) in .sdd/ or plugins/
- Files larger than 100KB (performance safeguard)
- Files with `sdd-ref-check: ignore` comment

**Why This Matters**:
The .sdd directory is for workflow management and planning, not production code:
- Creates environment-specific dependencies that break portability
- Breaks when SDD_ROOT_DIR location changes between environments
- Couples production code to development workflow tools
- May expose internal planning artifacts to end users

Production code should use:
- Configuration files or environment variables for paths
- Dependency injection for testing
- Abstract interfaces instead of direct file access

**Example Scenarios Caught**:

1. **Scenario**: Developer hardcodes .sdd path in config file
   ```typescript
   // src/config.ts
   const dataPath = ".sdd/tickets/";  // ❌ VIOLATION
   ```
   - **PostToolUse Response**: Warning displayed after edit
   - **verify-task Response**: `❌ FAIL: .sdd references found in production code`
   - **Resolution**: Use environment variable or configuration

2. **Scenario**: Developer references SDD_ROOT_DIR in production code
   ```typescript
   // src/utils.ts
   const root = process.env.SDD_ROOT_DIR;  // ❌ VIOLATION
   ```
   - **Gate Response**: Verification fails with remediation guidance
   - **Resolution**: Use application-specific config variable

3. **Scenario**: Plugin code with SDD reference (valid)
   ```python
   # plugins/sdd/hooks/check.py
   SDD_ROOT_DIR = os.environ.get('SDD_ROOT_DIR')  # ✅ VALID
   ```
   - **Gate Response**: No warning (plugins/ directory excluded)

4. **Scenario**: Variable name that looks similar (no false positive)
   ```typescript
   // src/config.ts
   const MY_SDD_CONFIG = { enabled: true };  // ✅ VALID
   const path = ".sddconfig/settings.json";  // ✅ VALID
   ```
   - **Gate Response**: No warning (word boundaries prevent false match)

**Bypass Mechanisms**:

*Environment variable (emergency disable all checks):*
```bash
export SDD_SKIP_REF_CHECK=true
```

*Comment-based bypass (per-file exception):*
```python
# sdd-ref-check: ignore
path = ".sdd/example"  # Documented exception for this file
```

**Remediation**:
If verification fails due to .sdd references:
1. Move hardcoded path to configuration file or environment variable
2. If this is plugin code, ensure file is in `plugins/` directory
3. Use comment bypass only for documented exceptions with clear justification

**Implemented In**:
- `warn-sdd-refs.py` PostToolUse hook
- `verify-task` agent Step 2.5

**Test Suite**: `plugins/sdd/hooks/test-warn-sdd-refs.sh` (21 test cases)

---

### Completion Phase

#### Commit Requirements

**Purpose**: Ensures only verified work is committed with proper conventional commit format

**Triggered**: When running commit-task agent

**Enforcement**: Hard block (will not commit unverified work)

**Checks Performed**:
- Task has "Verified" checkbox checked
- Commit follows Conventional Commits format
- Commit message includes task ID
- No secrets or sensitive files staged

**Example Scenarios Caught**:

1. **Scenario**: Developer tries to commit before verification
   - **Gate Response**: Commit-task agent requires verified status
   - **Resolution**: Run verify-task agent first

2. **Scenario**: Developer stages .env file with secrets
   - **Gate Response**: Warning about potential secret files
   - **Resolution**: Remove sensitive files from staging

**Bypass**: Not available - verification required before commit

**Implemented In**: `commit-task` agent

---

#### Archive Requirements

**Purpose**: Ensures only fully completed tickets are archived

**Triggered**: When running `/sdd:archive [TICKET_ID]`

**Enforcement**: Hard block (will not archive incomplete tickets)

**Checks Performed**:
- ALL tasks have "Verified" checkbox checked
- No pending or in-progress tasks
- Structure validation passes (all required files exist)
- No tasks with unchecked verification

**Example Scenarios Caught**:

1. **Scenario**: User tries to archive ticket with unverified tasks
   - **Gate Response**: `✗ {TICKET_ID}_{name}: {X}/{Y} tasks verified - Incomplete`
   - **Resolution**: Complete and verify remaining tasks

2. **Scenario**: User tries to archive ticket with missing structure
   - **Gate Response**: Structure validation fails
   - **Resolution**: Fix structural issues before archiving

**Bypass**: Not available - all tasks must be verified

**Implemented In**: `/sdd:archive` command

**Post-Archive**: References updated, metrics collected, event logged

---

## Summary Table

| Gate | Command/Agent | Enforcement | Key Checks |
|------|---------------|-------------|------------|
| Pre-Decompose Validation | `/sdd:create-tasks` | Hard block | plan.md exists, >100 words; architecture.md exists, >100 words |
| Execute Pre-Check | `/sdd:do-all-tasks` | Hard block | Review exists and passed; Tasks exist |
| Dependency Validation | `/sdd:do-task` | Hard block | All dependencies complete (internal and external) |
| SDD Reference Check | PostToolUse hook + verify-task | Warning + Hard block | No .sdd paths in production code |
| Verify-Task | verify-task agent | Hard block | All acceptance criteria; Tests executed; Status checkboxes |
| Commit Requirements | commit-task agent | Hard block | Verified checkbox; Conventional commit format |
| Archive Requirements | `/sdd:archive` | Hard block | ALL tasks verified; Structure valid |

---

## Enforcement Levels

**Hard Block**: Operation cannot proceed. User must resolve issue first.

**Warning**: Operation proceeds but user is notified of potential issue.

**Advisory**: Information provided but no enforcement.

All current quality gates use **Hard Block** enforcement to ensure quality is mandatory, not optional.

---

## Adding New Quality Gates

When adding new quality gates:

1. Choose appropriate lifecycle phase
2. Define clear purpose (what it prevents)
3. Specify enforcement level (prefer hard block for quality issues)
4. Implement clear error messages with actionable resolution steps
5. Document in this file
6. Add examples of scenarios caught

---

**Document Version**: 1.1
**Last Updated**: 2025-12-12
**Related Tasks**: SDDREV.3001, SDDREV.3002, SDDREV.3003, SDDREV.3004, SDDUPD.2004
