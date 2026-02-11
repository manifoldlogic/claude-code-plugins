# Reference: analysis.md

This document provides complete guidance for creating and reviewing the analysis document (`analysis.md`) in an SDD ticket. It is used by document agents spawned via initiation prompts.

## Creation Guide

### Purpose

The analysis document provides a deep understanding of the problem being solved. It is the foundation for all subsequent planning documents. As a Level 0 document in the dependency graph, it has no prerequisites and is always created first.

The analysis captures: what the problem is, why it matters, what already exists in the codebase and industry, what constraints apply, and how success will be measured. Every statement should be specific to the ticket -- generic or boilerplate content is an anti-pattern.

### Prerequisites

None. The analysis document is Level 0 in the document dependency graph. It requires only:
- The ticket README.md (for intent and scope)
- Access to the codebase (for research)
- Access to web search (for industry context, if applicable)

### Research Steps

Before writing the analysis document, perform thorough research:

1. **Read the ticket README.md** to understand the ticket intent, goals, and initial scope description.

2. **Search the codebase for related implementations.** Use Grep and Glob to find existing code, patterns, utilities, or modules that relate to the problem domain. Note what already exists and how it works.

3. **Review existing patterns.** Identify how similar problems have been solved in the codebase. Note naming conventions, architectural patterns, and established approaches that the ticket should follow or extend.

4. **Check integration points.** Identify which parts of the codebase the ticket will interact with, depend on, or modify. Map out the boundaries of the change.

5. **Identify reusable components.** Determine which existing tools, libraries, utilities, or abstractions can be leveraged rather than rebuilt.

6. **Research industry solutions** (when applicable). Search for established approaches, best practices, or prior art that inform the solution space. Reference specific documentation or implementations found.

7. **Identify constraints.** Catalog technical constraints (language, platform, compatibility), business constraints (scope, priorities), and time constraints that bound the solution.

8. **Define measurable success criteria.** Determine how completion and quality will be objectively assessed. Each criterion should be verifiable, not subjective.

### Quality Criteria

The analysis document meets quality standards when:

- The problem is defined with specifics, not generalities. Statements reference actual code paths, file names, error messages, or user scenarios rather than abstract descriptions.
- Context and background explain why the work is needed now and what triggered it.
- Existing solutions are researched and cited. The industry section references real tools, libraries, or approaches. The codebase section references actual files, modules, or patterns found during research.
- Constraints are realistic and sourced from actual project context, not speculative.
- Success criteria are measurable. Each criterion can be verified programmatically or through explicit inspection -- not through subjective judgment.
- Gaps in understanding are explicitly identified. If research did not yield a clear answer on some aspect, the document says so rather than glossing over it.
- Assumptions are noted explicitly so that reviewers can validate or challenge them.

### Template

The analysis document uses the template at:

    {PLUGIN_ROOT}/skills/project-workflow/templates/ticket/analysis.md

The template defines these sections that must be filled in:

| Section | What to Write |
|---------|---------------|
| Problem Definition | Clear statement of the problem being solved, with specifics |
| Context | Background information and why this work is needed |
| Existing Solutions - Industry | What solutions exist externally (tools, libraries, approaches) |
| Existing Solutions - Codebase | What the codebase already does in this area (with file references) |
| Current State | Description of current implementation, if applicable |
| Research Findings | Key insights discovered during codebase and industry research |
| Constraints - Technical | Platform, language, compatibility, and technical limitations |
| Constraints - Business | Scope, priority, and organizational limitations |
| Constraints - Time | Timeline constraints, if applicable |
| Success Criteria | Measurable outcomes as a checklist |

## Review Guide

### Review Focus Areas

When reviewing an analysis document, evaluate it from the perspective of a senior technical architect who needs to determine whether this document provides sufficient foundation for writing a PRD. The reviewer should be asking: "Can I define concrete requirements from this analysis?"

**Problem Clarity**
- Is the problem clearly defined with specific details?
- Would two different engineers reading this analysis agree on what needs to be solved?
- Are concrete examples, error messages, or user scenarios provided?

**Research Thoroughness**
- Were existing codebase solutions searched and documented?
- Are industry alternatives referenced with specifics (not just "there are libraries for this")?
- Are integration points with existing code identified?

**Constraint Realism**
- Are constraints grounded in actual project context?
- Are there unstated constraints that should be explicit?
- Do the constraints properly scope the solution space?

**Success Criteria Quality**
- Is each criterion measurable and verifiable?
- Can an agent programmatically check whether each criterion is met?
- Are criteria specific enough to guide implementation decisions?

**Completeness**
- Are all template sections filled in (or explicitly marked N/A with reasoning)?
- Are research findings substantive rather than superficial?
- Are gaps and assumptions called out?

### Common Issues

These problems frequently appear in analysis documents:

1. **Generic problem statements.** The problem definition reads like it could apply to any project. Fix: add specific references to this codebase, these users, this error, this limitation.

2. **Missing codebase research.** The "Existing Solutions - Codebase" section is empty or vague. Fix: search the codebase and cite specific files, modules, or patterns found.

3. **Unmeasurable success criteria.** Criteria use subjective language ("improved performance", "better user experience"). Fix: define exact thresholds, counts, or verifiable states.

4. **Assumptions hidden as facts.** Statements presented as established truths that are actually assumptions. Fix: move to an explicit assumptions list and flag for validation.

5. **Constraint omission.** Important constraints discovered later during architecture or implementation that should have been identified during analysis. Fix: thoroughly investigate technical, business, and time constraints during research.

6. **Superficial industry research.** Industry section says "many solutions exist" without naming or evaluating them. Fix: name specific tools, libraries, or approaches and explain their relevance.

7. **Missing gap identification.** The document presents a complete picture without acknowledging areas of uncertainty. Fix: explicitly state what is not yet known or what requires further investigation.

### Review Checklist

Use this checklist when reviewing an analysis document. Every item should be satisfied before approval.

- Problem is defined with specifics (not generic descriptions)
- Context explains why this work is needed now
- Existing solutions in the codebase are researched and cited with file paths or module names
- Existing solutions in industry are researched with named references
- Current state is described (or explicitly marked N/A)
- Research findings contain substantive insights
- Technical constraints are identified and grounded in project reality
- Business constraints are identified
- Time constraints are noted (or explicitly marked N/A)
- Every success criterion is measurable and verifiable
- Assumptions are explicitly listed
- Gaps in understanding are acknowledged
- All template sections are addressed (filled or marked N/A with reasoning)
- Content is specific to this ticket (no boilerplate or generic statements)
