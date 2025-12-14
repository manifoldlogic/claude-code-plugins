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

## Related Documentation

- [Getting Started](getting-started.md) - Step-by-step first ticket guide
- [Command Reference](command-reference.md) - Detailed command documentation
- [Quality Assurance](../skills/project-workflow/references/quality-assurance.md) - Quality gate details
- [Troubleshooting](troubleshooting.md) - Common issues and solutions

---

**Document Version**: 1.0
**Applies to**: SDD Plugin v1.0.0+
