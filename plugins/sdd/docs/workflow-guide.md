# SDD Workflow Guide

Visual guide to the complete SDD plugin workflow with quality gates.

**Version**: 1.0.0
**Last Updated**: 2025-12-11

---

## Overview

The SDD plugin orchestrates a systematic workflow from initial planning through completion and archival.

**Key Principles**:
- Plan before you build
- Review before you execute
- Verify before you commit
- Quality gates prevent errors

---

## Complete Workflow Diagram

```
                              ┌─────────────────────┐
                              │     NEW WORK        │
                              └──────────┬──────────┘
                                         │
                    ┌────────────────────┴────────────────────┐
                    │                                         │
                    ▼                                         ▼
           ┌───────────────┐                        ┌───────────────┐
           │ /sdd:start-   │                        │/sdd:plan-     │
           │  epic         │                        │ ticket        │
           │  (Research)   │                        │ (Direct)      │
           └───────┬───────┘                        └───────┬───────┘
                   │                                        │
                   ▼                                        │
           ┌───────────────┐                                │
           │   Research    │                                │
           │   & Analysis  │                                │
           └───────┬───────┘                                │
                   │                                        │
                   └────────────────┬───────────────────────┘
                                    │
                                    ▼
                           ┌───────────────┐
                           │   PLANNING    │
                           │ (plan.md,     │
                           │ architecture, │
                           │ quality)      │
                           └───────┬───────┘
                                   │
                                   ▼
                           ┌───────────────┐
                           │ /sdd:review   │
                           └───────┬───────┘
                                   │
                    ┌──────────────┴──────────────┐
                    │                             │
                   FAIL                          PASS
                    │                             │
                    ▼                             ▼
           ┌───────────────┐            ┌─────────────────┐
           │ /sdd:update   │            │ 🛡️ PRE-DECOMPOSE │
           │ (fix issues)  │            │    VALIDATION   │
           └───────┬───────┘            └────────┬────────┘
                   │                             │
                   └──────► back to ─────────────┤
                            PLANNING             │
                                                 ▼
                                        ┌───────────────┐
                                        │/sdd:create-   │
                                        │ tasks         │
                                        └───────┬───────┘
                                                │
                                                ▼
                                        ┌───────────────┐
                                        │ TASKS CREATED │
                                        │ (tasks/*.md)  │
                                        └───────┬───────┘
                                                │
                                                ▼
                                   ┌─────────────────────┐
                                   │ 🛡️ EXECUTE PRE-CHECK │
                                   │    VALIDATION       │
                                   └──────────┬──────────┘
                                              │
                                              ▼
                                     ┌───────────────┐
                                     │/sdd:do-all-   │
                                     │ tasks         │
                                     └───────┬───────┘
                                             │
                    ┌────────────────────────┴────────────────────────┐
                    │                                                 │
                    ▼                                                 │
           ┌───────────────┐                                         │
           │/sdd:do-task   │ ◄───────────────────────────────────────┤
           │  (per task)   │                                         │
           └───────┬───────┘                                         │
                   │                                                 │
                   ▼                                                 │
          ┌─────────────────┐                                        │
          │ 🛡️ DEPENDENCY   │                                        │
          │   VALIDATION    │                                        │
          └────────┬────────┘                                        │
                   │                                                 │
          ┌────────┴────────┐                                        │
          │                 │                                        │
       BLOCKED          SATISFIED                                    │
          │                 │                                        │
          ▼                 ▼                                        │
    ┌──────────┐    ┌───────────────┐                                │
    │ Complete │    │  IMPLEMENT    │                                │
    │ deps     │    │  (work done)  │                                │
    │ first    │    └───────┬───────┘                                │
    └──────────┘            │                                        │
                            ▼                                        │
                   ┌───────────────┐                                 │
                   │ unit-test-    │                                 │
                   │ runner (test) │                                 │
                   └───────┬───────┘                                 │
                           │                                         │
                           ▼                                         │
                  ┌─────────────────┐                                │
                  │ 🛡️ VERIFY-TASK  │                                │
                  │   VALIDATION    │                                │
                  └────────┬────────┘                                │
                           │                                         │
                  ┌────────┴────────┐                                │
                  │                 │                                │
                FAIL              PASS                               │
                  │                 │                                │
                  ▼                 ▼                                │
           ┌──────────┐    ┌───────────────┐                         │
           │ Fix work │    │  commit-task  │                         │
           └────┬─────┘    │  (commit)     │                         │
                │          └───────┬───────┘                         │
                │                  │                                 │
                └──► back to       │                                 │
                     IMPLEMENT     │                                 │
                                   ▼                                 │
                           ┌───────────────┐                         │
                           │  More tasks?  │─────────YES─────────────┘
                           └───────┬───────┘
                                   │
                                  NO
                                   │
                                   ▼
                          ┌─────────────────┐
                          │ 🛡️ ARCHIVE      │
                          │   VALIDATION    │
                          └────────┬────────┘
                                   │
                                   ▼
                           ┌───────────────┐
                           │ /sdd:archive  │
                           └───────┬───────┘
                                   │
                                   ▼
                           ┌───────────────┐
                           │   COMPLETE    │
                           └───────────────┘
```

---

## Workflow Phases

### Phase 1: Planning

**Commands**: `/sdd:start-epic` (optional), `/sdd:plan-ticket`, `/sdd:import-jira-ticket`

**Purpose**: Define what needs to be built and why

**Activities**:
- Research (if using epic workflow)
- Complete plan.md (what and why)
- Complete architecture.md (how)
- Complete quality-strategy.md (testing approach)

**Quality Gate**: None (planning is exploratory)

**Exit Criteria**: Planning documents complete with >100 words each

---

### Phase 2: Review and Decomposition

**Commands**: `/sdd:review`, `/sdd:update`, `/sdd:create-tasks`

**Purpose**: Validate planning and break down into tasks

**Quality Gates**:

| Gate | When | Checks | Action on Failure |
|------|------|--------|-------------------|
| 🛡️ Pre-Decompose | Before `/sdd:create-tasks` | plan.md >100 words, architecture.md >100 words | BLOCK |

**Exit Criteria**: Tasks created in tasks/ directory

---

### Phase 3: Execution

**Commands**: `/sdd:do-all-tasks`, `/sdd:do-task`

**Purpose**: Complete all tasks systematically

**Quality Gates**:

| Gate | When | Checks | Action on Failure |
|------|------|--------|-------------------|
| 🛡️ Execute Pre-Check | Before `/sdd:do-all-tasks` | Review passed, tasks exist | BLOCK |
| 🛡️ Dependency Validation | Before each `/sdd:do-task` | Prerequisites complete | BLOCK |

**Task Workflow**:
```
implement → test → verify → commit
(Sonnet)   (Haiku) (Sonnet) (Haiku)
```

**Exit Criteria**: All tasks verified and committed

---

### Phase 4: Verification

**Agents**: verify-task (Sonnet), unit-test-runner (Haiku)

**Purpose**: Verify work quality before committing

**Quality Gates**:

| Gate | When | Checks | Action on Failure |
|------|------|--------|-------------------|
| 🛡️ Verify-Task | After task work | Acceptance criteria, tests, completeness | BLOCK commit |

**Exit Criteria**: "Verified" checkbox checked in task file

---

### Phase 5: Archival

**Commands**: `/sdd:archive`

**Purpose**: Archive completed ticket

**Quality Gates**:

| Gate | When | Checks | Action on Failure |
|------|------|--------|-------------------|
| 🛡️ Archive Validation | Before `/sdd:archive` | ALL tasks verified | BLOCK |

**Exit Criteria**: Ticket moved to archive/tickets/

---

## Quality Gates Summary

Six quality gates protect the workflow:

| Gate | Command | Purpose |
|------|---------|---------|
| Pre-Decompose | `/sdd:create-tasks` | Ensure planning complete |
| Execute Pre-Check | `/sdd:do-all-tasks` | Ensure review passed, tasks exist |
| Dependency Validation | `/sdd:do-task` | Ensure prerequisites satisfied |
| Verify-Task | verify-task agent | Ensure acceptance criteria met |
| Commit Requirements | commit-task agent | Ensure verification complete |
| Archive Validation | `/sdd:archive` | Ensure all tasks verified |

All gates use **hard block** enforcement - work cannot proceed until issues are resolved.

For detailed gate documentation, see [Quality Assurance](../skills/project-workflow/references/quality-assurance.md).

---

## Alternative Workflows

### Direct to Ticket (Skip Epic)

For well-defined work, skip the epic/research phase:

```
/sdd:plan-ticket → Planning → /sdd:review → /sdd:create-tasks → /sdd:do-all-tasks → /sdd:archive
```

### Jira Import

Import existing Jira tickets:

```
/sdd:import-jira-ticket → Planning Enhancement → /sdd:review → /sdd:create-tasks → /sdd:do-all-tasks
```

### Single Task Execution

Execute one task at a time:

```
/sdd:do-task TASK_ID → (verify-task) → (commit-task) → /sdd:do-task NEXT_TASK
```

### Agent Customization

Add specialized agents before execution:

```
/sdd:create-tasks → /sdd:recommend-agents → /sdd:assign-agents → /sdd:do-all-tasks
```

---

## Diagram Symbols

| Symbol | Meaning |
|--------|---------|
| 🛡️ | Quality Gate (blocks if validation fails) |
| ┌───┐ | Command or action |
| ◄───► | Decision point |
| PASS/FAIL | Validation outcome |

---

## Deliverable Lifecycle

The SDD plugin manages deliverables through a structured lifecycle that ensures valuable artifacts are preserved while ephemeral work products are archived appropriately.

### Overview

Deliverables are documentation artifacts produced during ticket execution - audit reports, findings documents, verification reports, and similar outputs that go beyond code changes. The deliverable lifecycle tracks these artifacts from planning through archival, ensuring each one receives an explicit disposition decision:

- **Extract**: Copy to a permanent location in the codebase
- **Archive**: Store with the ticket (for ephemeral artifacts)
- **External**: Place in an external system (wiki, shared drive, other repo)

This lifecycle prevents knowledge loss by requiring intentional decisions about where valuable documentation should live after ticket completion.

**Data Flow:**

```
1. Planning: ticket-planner creates plan.md with deliverables + disposition
           |
           v
2. Task Creation: task-creator extracts deliverables + disposition to task files
           |
           v
3. Execution: Implementation agent creates deliverable files
           |
           v
4. Verification: verify-task validates deliverables exist
           |
           v
5. Archive Gate: archive.md checks all deliverables have disposition
           |
           v
6. User Action: User extracts "extract" deliverables manually
           |
           v
7. Recording: MANIFEST.md created, workflow.log updated
           |
           v
8. Archive: Ticket moved to archive/ with MANIFEST.md
```

### Planning Phase

During ticket planning, the ticket-planner identifies deliverables and assigns dispositions in `plan.md`.

**Deliverables table format:**

```markdown
**Deliverables:**
<!-- Disposition syntax: "extract: path/to/dest", "archive", or "external: Location Description" -->
| Deliverable | Purpose | Disposition |
|-------------|---------|-------------|
| gap-analysis.md | Document current state gaps | extract: docs/analysis/ |
| verification-report.md | Proof of phase completion | archive |
| user-guide.md | End-user documentation | external: Wiki: Product/UserGuide |
```

**Key decisions at this phase:**
- What deliverables will be produced?
- Which have permanent value (extract)?
- Which are temporary (archive)?
- Which belong elsewhere (external)?

See [ticket-planner.md](../agents/ticket-planner.md) for detailed planning guidance.

### Task Creation Phase

When tasks are created from `plan.md`, the task-creator agent automatically carries disposition metadata to individual task files.

**How disposition flows to tasks:**

1. Task-creator reads the deliverables table from plan.md
2. Parses the Disposition column if present
3. Includes disposition in the task's "Deliverables Produced" section

**Task deliverables section format:**

```markdown
## Deliverables Produced

| Deliverable | Purpose | Disposition |
|-------------|---------|-------------|
| gap-analysis.md | Document current state gaps | extract: docs/analysis/ |
```

**Backwards compatibility:** Task-creator handles both old format (without Disposition column) and new format (with Disposition column). Tables without disposition are still valid - the archive gate will prompt for disposition decisions later.

See [task-creator.md](../agents/task-creator.md) for task creation details.

### Execution Phase

During task execution, implementation agents create deliverable files in the ticket's `deliverables/` folder.

**Deliverable location:**
```
{SDD_ROOT}/tickets/{TICKET_ID}_{name}/deliverables/
├── gap-analysis.md
├── verification-report.md
└── findings.md
```

**Key points:**
- Deliverables are created in the `deliverables/` folder during task execution
- The verify-task agent validates that declared deliverables exist
- File names should match what was declared in the task file

### Archive Phase

The archive gate validates that all deliverables have disposition decisions before allowing archival.

**Archive gate behavior:**

1. **Scan deliverables folder** - Find all `.md` files in `deliverables/`
2. **Collect disposition data** - Check task files and plan.md for disposition metadata
3. **Validate completeness** - Ensure all deliverables have a disposition
4. **Prompt for missing** - If disposition is missing, prompt the user to decide
5. **Confirm extractions** - For "extract" type, confirm the file was copied
6. **Generate MANIFEST.md** - Record all disposition decisions
7. **Log events** - Update workflow.log with disposition events

**User prompts during archive:**

If a deliverable lacks disposition, you'll see:
```
ERROR: Deliverable 'findings.md' missing disposition
Please add disposition:
  extract: <destination>  - Copy to permanent location
  archive                 - Archive with ticket
  external: <description> - Placed externally

Enter disposition for findings.md: _
```

For "extract" dispositions, you'll be prompted to confirm:
```
ACTION REQUIRED: Extract gap-analysis.md
  Source: deliverables/gap-analysis.md
  Destination: docs/analysis/

Have you copied this file to the destination? (yes/no) _
```

See [archive.md](../commands/archive.md) for complete archive workflow.

### Disposition Types

Three disposition types cover all use cases:

#### Extract (`extract: path/to/dest`)

Use for documentation with **permanent value** that should live in the codebase.

**When to use extract:**
- Design decisions that inform future development
- Gap analyses that guide feature planning
- Migration guides needed by other teams
- Architecture Decision Records (ADRs)
- Reference documentation with lasting value

**Examples:**

| Deliverable | Disposition | Reasoning |
|-------------|-------------|-----------|
| `adr-caching-strategy.md` | `extract: docs/decisions/` | ADR - permanent reference for caching decisions |
| `gap-analysis-report.md` | `extract: docs/analysis/` | Findings inform future feature planning |
| `migration-guide.md` | `extract: docs/guides/` | Teams will need this for future migrations |

#### Archive (`archive`)

Use for **temporary artifacts** only needed during ticket execution.

**When to use archive:**
- Verification reports proving quality gate passage
- Working notes and scratch documentation
- Test execution summaries (already captured in CI)
- Phase completion proofs
- Intermediate analysis that's superseded by final documents

**Examples:**

| Deliverable | Disposition | Reasoning |
|-------------|-------------|-----------|
| `phase2-verification-report.md` | `archive` | Proof of gate passage - only needed during ticket |
| `working-notes.md` | `archive` | Developer notes - ephemeral |
| `testing-summary.md` | `archive` | Test results captured in CI permanently |

#### External (`external: description`)

Use for content that **belongs outside the repository**.

**When to use external:**
- User-facing documentation destined for a wiki
- Operations runbooks that live in Confluence
- Design assets shared via Google Drive
- Content for non-developers who use different systems
- Organizational policy requires external placement

**Examples:**

| Deliverable | Disposition | Reasoning |
|-------------|-------------|-----------|
| `user-guide.md` | `external: Wiki: Product/UserGuide` | End-user docs live on wiki |
| `runbook.md` | `external: Confluence: Ops/Runbooks` | Ops runbooks are in Confluence |
| `design-deck.md` | `external: Google Drive: Design/ProjectX` | Design assets shared via Drive |

### MANIFEST.md Format

When a ticket is archived, a `MANIFEST.md` file is created in the `deliverables/` folder to record all disposition decisions.

**Purpose:**
- Audit trail of what happened to each deliverable
- Reference for finding extracted deliverables later
- Documentation of knowledge transfer from ticket to codebase

**Format:**

```markdown
# Deliverable Manifest

**Format Version:** 1.0
**Ticket:** TICKET_ID
**Archive Date:** 2026-01-03

## Dispositions

| Deliverable | Disposition | Destination | Confirmed |
|-------------|-------------|-------------|-----------|
| gap-analysis.md | extract | docs/analysis/gap-analysis.md | Yes |
| verification.md | archive | - | Yes |
| user-guide.md | external | Wiki: Product/UserGuide | Yes |

## Notes

Any additional context about disposition decisions.
```

**Field descriptions:**
- **Format Version**: Schema version for future compatibility
- **Ticket**: Ticket ID for reference
- **Archive Date**: When archive was performed
- **Deliverable**: Name of the deliverable file
- **Disposition**: Type (extract/archive/external)
- **Destination**: Where extracted files went, or external location description
- **Confirmed**: "Yes" if user confirmed, "Auto" if auto-determined

### Backwards Compatibility

The deliverable lifecycle is designed to work with both old tickets (without disposition metadata) and new tickets (with disposition).

**How old tickets are handled:**

1. **Detection**: The archive gate checks if ANY deliverable has disposition metadata
2. **Old format detected**: If no dispositions exist anywhere, a warning is shown:
   ```
   WARNING: Ticket uses old format (no disposition metadata)
   ```
3. **User prompted**: For each deliverable, you're asked:
   ```
   Add disposition now? (extract:/archive/external:/skip) _
   ```
4. **Skip option**: Entering "skip" defaults to "archive" for backwards compatibility
5. **MANIFEST created**: Disposition decisions are still recorded in MANIFEST.md

**Default behavior:**
- Skipping disposition prompts defaults to "archive"
- Old tickets can still be archived (with warnings)
- No disposition metadata required for archive to succeed

**New ticket behavior:**
- If some deliverables have disposition but others don't, it's an error
- User must provide disposition for the missing ones
- Archive blocks until all dispositions are valid

### Troubleshooting

#### Missing Disposition Decision

**Symptom:** Archive shows "ERROR: Deliverable 'X' missing disposition"

**Cause:** The deliverable was created but no disposition was specified in plan.md or task file.

**Resolution:**
1. Enter disposition when prompted during archive
2. Or update the task file's "Deliverables Produced" section before archiving
3. Or update plan.md with the disposition column

#### Deliverable Extracted Incorrectly

**Symptom:** You extracted a deliverable to the wrong location.

**Resolution:**
1. Move the file to the correct location manually
2. Update MANIFEST.md to reflect the correct destination
3. The archive process doesn't track post-extraction changes

#### Finding Extracted Deliverables After Archive

**Symptom:** An archived task references a deliverable that no longer exists in `deliverables/`.

**Resolution:**
1. Check `deliverables/MANIFEST.md` in the archived ticket
2. Find the deliverable in the Dispositions table
3. Look at the Destination column for where it was extracted
4. For "extract" type: File should be at that path in the codebase
5. For "external" type: Description tells you which external system

**Example:**
```
Looking for: findings.md (referenced in archived task)

MANIFEST.md shows:
| findings.md | extract | docs/analysis/findings.md | Yes |

→ Check: docs/analysis/findings.md
```

#### Invalid Disposition Format

**Symptom:** Archive shows "ERROR: Invalid disposition format"

**Cause:** Disposition string doesn't match expected format.

**Valid formats:**
- `archive` (exact match)
- `extract: path/to/dest` (relative path, no `..` or leading `/`)
- `external: description` (any descriptive text)

**Invalid examples:**
- `keep` (use "archive" instead)
- `extract: ../../../etc` (path traversal blocked)
- `extract: /absolute/path` (absolute paths blocked)

### Decision Guidance

Use this decision tree when choosing disposition:

```
Is this document valuable after the ticket is complete?
├── No → "archive"
│   (verification reports, working notes, test summaries)
│
└── Yes → Does it belong in the repository?
    ├── No → "external: <location>"
    │   (wiki pages, shared drives, external systems)
    │
    └── Yes → "extract: <path>"
        (ADRs, guides, analysis reports, reference docs)
```

**Questions to ask:**
1. Will someone need to read this 6 months from now?
2. Does it document decisions that affect the codebase?
3. Would losing this document lose institutional knowledge?
4. Does organizational policy dictate where it should live?

### Cross-Phase Reference Resolution

When reviewing archived tickets, you may encounter references to deliverables that no longer exist in the `deliverables/` folder (because they were extracted).

**Resolution process:**

1. Open the archived ticket's `deliverables/MANIFEST.md`
2. Find the deliverable name in the Dispositions table
3. Check the Destination column:
   - For `extract`: Navigate to that path in the codebase
   - For `archive`: File is still in `deliverables/` folder
   - For `external`: Check the external system described

**Example scenario:**

Task TICKET.2003 references `findings.md` which Phase 1 created. After archive:

```markdown
# In archived ticket's MANIFEST.md:

| Deliverable | Disposition | Destination | Confirmed |
|-------------|-------------|-------------|-----------|
| findings.md | extract | docs/analysis/findings.md | Yes |
```

The file now lives at `docs/analysis/findings.md` in the repository.

---

## Related Documentation

- [Getting Started](getting-started.md) - Step-by-step first ticket guide
- [Command Reference](command-reference.md) - Detailed command documentation
- [Quality Assurance](../skills/project-workflow/references/quality-assurance.md) - Quality gate details
- [Troubleshooting](troubleshooting.md) - Common issues and solutions
- [ticket-planner.md](../agents/ticket-planner.md) - Planning guidance including disposition decisions
- [task-creator.md](../agents/task-creator.md) - Task creation and deliverable handling
- [archive.md](../commands/archive.md) - Archive command with deliverable gate

---

**Document Version**: 1.1
**Applies to**: SDD Plugin v1.0.0+
