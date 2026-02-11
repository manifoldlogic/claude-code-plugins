# Reference: README.md

This document provides complete guidance for creating and reviewing the ticket README document (`README.md`) in an SDD ticket. It is used by document agents spawned via initiation prompts.

## Creation Guide

### Purpose

The README document is the executive summary and navigation hub for the ticket. It synthesizes information from all other planning documents into a concise overview that allows any reader to quickly understand the ticket's purpose, scope, key decisions, and current status. As the entry point for the ticket, it must be clear, accurate, and navigable.

As a Level 4 document in the dependency graph, README.md depends on all six prior planning documents. It is always created last, after every other document has been completed and approved. The README does not introduce new analysis, requirements, or design -- it consolidates and summarizes what already exists.

### Prerequisites

The following must be complete before creating the README document:

- **analysis.md** (Level 0): The analysis document must exist and contain the problem definition, context, research findings, constraints, and success criteria. The README summarizes the problem and why this work is needed.

- **prd.md** (Level 1): The PRD must exist and contain functional requirements, non-functional requirements, acceptance criteria, and scope boundaries. The README summarizes what is being built and what is explicitly out of scope.

- **architecture.md** (Level 2): The architecture document must exist and contain the technical design, component structure, technology choices, and integration points. The README summarizes the solution approach and key design decisions.

- **plan.md** (Level 3): The plan document must exist and contain phased execution with deliverables, agent assignments, and success metrics. The README summarizes the execution approach and phase structure.

- **quality-strategy.md** (Level 3): The quality strategy must exist and contain testing philosophy, coverage requirements, critical paths, and quality gates. The README references the quality approach.

- **security-review.md** (Level 3): The security review must exist and contain the security assessment, known gaps, mitigations, and initial release scope. The README references the security posture.

Read all six planning documents before writing the README. The README is a synthesis document -- every statement in it should be traceable to content in one or more planning documents. Do not introduce new information that is not grounded in the existing plans.

### Research Steps

Before writing the README document, perform these steps:

1. **Read the analysis document** at the ticket planning path. Extract the problem statement, the context for why this work is needed, and the key constraints. These form the Problem Statement section of the README.

2. **Read the PRD** to understand the requirements scope, acceptance criteria, and what is explicitly out of scope. The Proposed Solution section of the README should reflect what the PRD defines as the deliverable scope.

3. **Read the architecture document** to understand the technical approach, key design decisions, component structure, and technology choices. The Proposed Solution section should summarize the architectural approach at a high level without repeating the full design.

4. **Read the plan document** to understand the phased execution approach, number of phases, key deliverables per phase, and agent assignments. This informs how the README describes the execution strategy and lists the relevant agents.

5. **Read the quality strategy** to understand the testing approach, coverage targets, and quality gates. The README should reference the quality approach without duplicating the full strategy.

6. **Read the security review** to understand the security posture, key risks, and mitigations. The README should reference the security assessment without duplicating the full review.

7. **Read the ticket README.md template** to understand the expected structure and sections. The template defines the sections that must be filled in.

8. **Verify all planning documents are complete.** Before writing, confirm that all six documents exist and contain substantive content. If any document is missing or empty, do not proceed -- the README cannot be written until all prerequisites are met.

9. **Identify the relevant agents** for this ticket. Review the plan document's agent assignments and the ticket's specific requirements to compile the list of agents that will be involved in execution.

10. **Synthesize, do not duplicate.** The README should provide a concise overview that helps a reader decide which planning document to read for details. It should not repeat full sections from other documents. Each section should be 2-5 sentences that capture the essence and point to the detailed document.

### Quality Criteria

The README document meets quality standards when:

- The Summary section concisely captures what the ticket accomplishes in 2-3 sentences. A reader should understand the ticket's purpose without reading any other document.
- The Problem Statement section clearly states what problem is being solved and why, grounded in the analysis document. It should reference specific context, not generic statements.
- The Proposed Solution section summarizes the architectural approach at a level appropriate for an overview. It should convey the key design decisions without duplicating the architecture document.
- The Relevant Agents section lists all agents involved in the ticket lifecycle, from planning through verification and commit. Agent names match those assigned in the plan document.
- The Planning Documents section provides links to all six planning documents with brief descriptions that help a reader decide which document to consult for specific information.
- The Tickets section correctly references the tasks directory.
- All information in the README is consistent with the planning documents. There are no contradictions between the README summary and the detailed plans.
- The README is self-contained as an entry point. A new team member reading only the README should understand the ticket's purpose, scope, approach, and how to navigate the planning documents for details.
- The document is concise. The README is an overview, not a comprehensive document. Each section should be brief and focused. If a section grows beyond a few sentences, content should be moved to the appropriate planning document instead.
- No new information is introduced. The README synthesizes existing content -- it does not add analysis, requirements, designs, or decisions that are not already documented in the planning documents.

### Template

The README document uses the template at:

    {PLUGIN_ROOT}/skills/project-workflow/templates/ticket/README.md

The template defines these sections that must be filled in:

| Section | What to Write |
|---------|---------------|
| Summary | 2-3 sentence overview of what the ticket accomplishes |
| Problem Statement | What problem this ticket solves and why it matters, sourced from analysis.md |
| Proposed Solution | High-level approach summarized from architecture.md and prd.md |
| Relevant Agents | List of all agents involved in ticket lifecycle (from plan.md agent assignments) |
| Planning Documents | Links to all six planning documents with brief descriptions |
| Tickets | Reference to the tasks directory |

## Review Guide

### Review Focus Areas

When reviewing a README document, evaluate it from the perspective of a new team member encountering this ticket for the first time. The reviewer should be asking: "Can I understand this ticket's purpose, scope, and structure from the README alone, and can I navigate to the right planning document for any detail I need?"

**Summary Clarity**
- Does the summary convey the ticket's purpose in 2-3 sentences?
- Would a reader unfamiliar with the project understand what this ticket accomplishes?
- Is the summary specific to this ticket (not a generic description that could apply to any ticket)?

**Problem Statement Accuracy**
- Is the problem statement grounded in the analysis document?
- Does it explain why this work is needed, not just what the work is?
- Are specific details included (not vague statements like "improve the system")?

**Solution Summary Quality**
- Does the proposed solution summarize the architectural approach accurately?
- Is the level of detail appropriate for an overview (not too detailed, not too vague)?
- Are key design decisions mentioned without duplicating the architecture document?

**Agent List Completeness**
- Are all agents from the plan document's assignments listed?
- Are standard lifecycle agents included (planner, reviewer, verifier, committer)?
- Do agent names match those used in the plan and task files?

**Navigation Completeness**
- Are all six planning documents linked with correct relative paths?
- Does each link have a brief description that helps the reader decide whether to read that document?
- Is the tasks directory referenced?

**Consistency with Planning Documents**
- Does the README summary align with the analysis problem definition?
- Does the proposed solution align with the architecture design?
- Are there any contradictions between the README and the detailed planning documents?
- Is the scope described in the README consistent with the PRD scope?

**Conciseness**
- Is the README appropriately brief for an overview document?
- Are there sections that duplicate content from planning documents instead of summarizing?
- Could any section be shortened without losing essential information?

### Common Issues

These problems frequently appear in README documents:

1. **Verbose summaries.** The summary section is a full paragraph or more, repeating content from the analysis or PRD. Fix: reduce to 2-3 focused sentences that capture the essence of the ticket.

2. **Missing problem context.** The problem statement says what will be built but not why it is needed. Fix: include the motivation and context from the analysis document -- what triggered this work and what pain point it addresses.

3. **Solution section duplicates architecture.** The proposed solution repeats the component design, data flow, or technology choices in detail. Fix: summarize the approach in 2-4 sentences that convey the key decisions. Point the reader to architecture.md for full details.

4. **Incomplete agent list.** The relevant agents section lists only implementation agents, missing planning, review, verification, or commit agents. Fix: include all agents across the full ticket lifecycle.

5. **Broken or missing document links.** Planning document links use incorrect paths or omit documents. Fix: verify that all six planning documents are linked with correct relative paths and that each link resolves.

6. **Contradictions with planning documents.** The README describes a scope, approach, or constraint that conflicts with what is written in the detailed planning documents. Fix: re-read the planning documents and ensure the README accurately reflects their content.

7. **New information introduced.** The README contains analysis findings, requirements, or design decisions not present in any planning document. Fix: move new information to the appropriate planning document and summarize it in the README.

8. **Generic descriptions.** The README reads like it could apply to any ticket, with no specific references to this ticket's problem domain, technology, or codebase. Fix: include specific details from the analysis and architecture that make this README uniquely about this ticket.

### Review Checklist

Use this checklist when reviewing a README document. Every item should be satisfied before approval.

- Summary is 2-3 sentences and conveys the ticket purpose clearly
- Summary is specific to this ticket (not generic or boilerplate)
- Problem statement is grounded in the analysis document
- Problem statement explains why this work is needed (motivation and context)
- Proposed solution summarizes the architectural approach at an appropriate level
- Proposed solution does not duplicate the architecture document
- Key design decisions are mentioned in the proposed solution
- Relevant agents list includes all agents from the plan document
- Relevant agents list includes lifecycle agents (planner, reviewer, verifier, committer)
- All six planning documents are linked (analysis, prd, architecture, plan, quality-strategy, security-review)
- Document links use correct relative paths
- Each document link has a brief description of the document's purpose
- Tasks directory is referenced
- README content is consistent with analysis problem definition
- README content is consistent with PRD requirements and scope
- README content is consistent with architecture design decisions
- README content is consistent with plan execution approach
- No contradictions exist between the README and any planning document
- No new information is introduced that is not in a planning document
- README is concise (overview-appropriate length, not verbose)
- README serves as a self-contained entry point for the ticket
- All template sections are addressed (filled or marked N/A with reasoning)
- Content is specific to this ticket (no boilerplate or generic statements)
