# Document Dependency Graph

This document defines the creation order for SDD ticket planning documents. Each document type has explicit prerequisites that must be completed and approved before it can be started. The graph is a directed acyclic graph (DAG) with no circular dependencies.

## Dependency Levels

Documents are organized into levels based on their prerequisites. All documents at a given level depend on documents from earlier levels. Documents within the same level are independent of each other and may be created in any order (or concurrently).

### Level 0: No Dependencies

| Document | File | Dependencies | Purpose |
|----------|------|--------------|---------|
| Analysis | `{TICKET_PATH}/planning/analysis.md` | None | Research and context gathering |

The analysis document is always created first. It requires no prior planning documents -- only the ticket description and codebase access.

### Level 1: Depends on Analysis

| Document | File | Dependencies | Purpose |
|----------|------|--------------|---------|
| PRD | `{TICKET_PATH}/planning/prd.md` | analysis.md | Requirements and scope definition |

The PRD translates analysis findings into concrete requirements. It cannot be written without understanding the research context from the analysis.

### Level 2: Depends on PRD

| Document | File | Dependencies | Purpose |
|----------|------|--------------|---------|
| Architecture | `{TICKET_PATH}/planning/architecture.md` | prd.md | Technical design and component structure |

The architecture document designs the technical solution to satisfy the requirements defined in the PRD. It must read both the analysis (for context) and the PRD (for requirements).

### Level 3: Depends on Architecture

| Document | File | Dependencies | Purpose |
|----------|------|--------------|---------|
| Plan | `{TICKET_PATH}/planning/plan.md` | architecture.md | Phased execution plan with task breakdown |
| Quality Strategy | `{TICKET_PATH}/planning/quality-strategy.md` | architecture.md | Testing approach and quality gates |
| Security Review | `{TICKET_PATH}/planning/security-review.md` | architecture.md | Security analysis and threat modeling |

These three documents are independent of each other. Each depends on the architecture document (and transitively on the PRD and analysis). They may be created in any order or concurrently.

### Level 4: Depends on All Others

| Document | File | Dependencies | Purpose |
|----------|------|--------------|---------|
| README | `{TICKET_PATH}/README.md` | analysis.md, prd.md, architecture.md, plan.md, quality-strategy.md, security-review.md | Ticket overview and navigation |

The README is always created last. It synthesizes information from all other documents into a navigable overview of the ticket.

## Visual Dependency Graph

```
Level 0    Level 1    Level 2    Level 3              Level 4

                                 plan.md
                                /
analysis   prd.md     arch.md --  quality-strategy.md -- README.md
  .md   ->         ->          \                      /
                                 security-review.md --
```

## Execution Order

### Linear Execution (Sequential)

When creating documents one at a time, follow this order:

1. `analysis.md`
2. `prd.md`
3. `architecture.md`
4. `plan.md` (or quality-strategy.md or security-review.md -- order within Level 3 is flexible)
5. `quality-strategy.md`
6. `security-review.md`
7. `README.md`

### Parallel Execution (Concurrent)

When spawning multiple agents, respect level boundaries:

1. Spawn Level 0: `analysis.md` -- wait for approval
2. Spawn Level 1: `prd.md` -- wait for approval
3. Spawn Level 2: `architecture.md` -- wait for approval
4. Spawn Level 3: `plan.md`, `quality-strategy.md`, `security-review.md` -- spawn all three concurrently, wait for all approvals
5. Spawn Level 4: `README.md` -- wait for approval

## Template References

Each document has a corresponding template in the project-workflow skill:

| Document | Template Location |
|----------|-------------------|
| analysis.md | `{PLUGIN_ROOT}/skills/project-workflow/templates/ticket/analysis.md` |
| prd.md | `{PLUGIN_ROOT}/skills/project-workflow/templates/ticket/prd.md` |
| architecture.md | `{PLUGIN_ROOT}/skills/project-workflow/templates/ticket/architecture.md` |
| plan.md | `{PLUGIN_ROOT}/skills/project-workflow/templates/ticket/plan.md` |
| quality-strategy.md | `{PLUGIN_ROOT}/skills/project-workflow/templates/ticket/quality-strategy.md` |
| security-review.md | `{PLUGIN_ROOT}/skills/project-workflow/templates/ticket/security-review.md` |
| README.md | `{PLUGIN_ROOT}/skills/project-workflow/templates/ticket/README.md` |

## Usage

This document is referenced by:
- The orchestrator SKILL.md to determine spawning order
- Each per-document initiation prompt to identify prerequisite documents
- The per-document reference documents (`doc-*.md`) to specify prerequisites in their Creation Guide sections
