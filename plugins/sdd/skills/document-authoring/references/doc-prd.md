# Reference: prd.md

This document provides complete guidance for creating and reviewing the Product Requirements Document (`prd.md`) in an SDD ticket. It is used by document agents spawned via initiation prompts.

## Creation Guide

### Purpose

The PRD defines WHAT is being built. It is the authoritative source of truth for requirements, acceptance criteria, user stories, and scope boundaries. It translates the problem understanding from the analysis document into concrete, testable requirements that drive all downstream planning.

As a Level 1 document in the dependency graph, the PRD depends on a completed analysis.md. It serves as the foundation for architecture.md (technical design to meet PRD requirements), plan.md (delivery strategy for PRD features), and quality-strategy.md (testing approach to validate PRD criteria).

### Prerequisites

The following must be complete before creating the PRD:

- **analysis.md** (Level 0): The analysis document must exist and contain a well-researched problem definition, existing solutions, constraints, and success criteria. The PRD translates these findings into formal requirements.

Read the analysis document first. The PRD must be consistent with the problem definition, constraints, and success criteria established there. Any requirements in the PRD should be traceable back to findings in the analysis.

### Research Steps

Before writing the PRD, perform these steps:

1. **Read the analysis document** at the ticket planning path. Understand the problem definition, constraints, existing solutions, and success criteria. These inform and bound the requirements you will define.

2. **Read the ticket README.md** to understand the original ticket intent, goals, and scope description. Verify alignment between README intent and analysis findings.

3. **Identify target users.** Determine who will use the feature or system being built. Include both direct users (those who interact with it) and secondary stakeholders (those affected by it). For internal tooling or infrastructure tickets, identify the developer or operator personas.

4. **Define functional requirements.** Translate the problem and solution approach from the analysis into specific behaviors the system must exhibit. Each requirement should describe what the system does, not how it does it. Requirements must be testable -- an agent should be able to verify whether each one is satisfied.

5. **Define non-functional requirements.** Identify performance, security, reliability, scalability, and accessibility constraints. Draw on the technical constraints identified in the analysis document. Mark subsections N/A when genuinely not applicable.

6. **Write user stories.** Describe how users will interact with the feature. Use the format: "As a [user type], I want [goal] so that [benefit]." For technical tickets without user-facing changes, mark this section N/A.

7. **Define acceptance criteria.** Create specific, testable conditions that must be met for the work to be considered complete. Each criterion should be unambiguous and verifiable -- either programmatically or through explicit inspection. Avoid subjective language.

8. **Define scope boundaries.** Explicitly list what is out of scope. This prevents scope creep during architecture and implementation. Items listed here are acknowledged as related but deliberately excluded from this ticket.

9. **Document assumptions.** List conditions assumed to be true that could affect implementation or success. Include dependency assumptions, environmental assumptions, and any constraints inherited from the analysis that are not yet validated.

10. **Define success metrics.** Describe how the work will be measured for success. Where possible, connect metrics back to the success criteria in the analysis document. Include both immediate deliverable measures and longer-term impact indicators where applicable.

### Quality Criteria

The PRD meets quality standards when:

- Functional requirements are clear, specific, and testable. Each requirement describes a concrete behavior the system must exhibit, not a vague aspiration. An agent reading the requirement can determine exactly what to implement.
- Requirements distinguish WHAT from HOW. The PRD defines what the system must do; architecture.md defines how. If a requirement specifies implementation approach, it belongs in architecture.
- Acceptance criteria are measurable and verifiable. Each criterion can be checked programmatically or through explicit inspection. Criteria like "works correctly" or "performs well" are insufficient -- they must specify exact thresholds, states, or conditions.
- Non-functional requirements include specific targets where applicable (response time thresholds, coverage percentages, error rate limits) rather than qualitative statements.
- Out of scope is explicitly defined. Items that might reasonably be expected but are excluded are listed, preventing scope creep during downstream planning.
- User stories reflect actual usage scenarios grounded in the target user analysis, not generic template fill-ins.
- Assumptions are explicitly stated so that reviewers, architects, and implementers can validate or challenge them.
- The document is consistent with the analysis. Requirements trace back to the problem definition, constraints, and success criteria in analysis.md. There are no requirements that contradict or ignore analysis findings.
- Sections that do not apply are marked N/A with a brief explanation, not left blank or filled with boilerplate.

### Template

The PRD uses the template at:

    {PLUGIN_ROOT}/skills/project-workflow/templates/ticket/prd.md

The template defines these sections that must be filled in:

| Section | What to Write |
|---------|---------------|
| Product Vision | Problem statement and proposed solution in 2-3 sentences |
| Target Users | Primary and secondary user personas with context |
| Functional Requirements | Specific, testable behaviors the system must exhibit |
| Non-Functional Requirements | Performance, security, and reliability targets with measurable thresholds |
| User Stories | Usage scenarios in "As a [user], I want [goal] so that [benefit]" format |
| Acceptance Criteria | Specific, testable conditions for completion |
| Out of Scope | Items explicitly excluded from this ticket |
| Assumptions | Conditions assumed true that affect implementation |
| Success Metrics | Measurable outcomes indicating the work achieved its goals |

## Review Guide

### Review Focus Areas

When reviewing a PRD, evaluate it from the perspective of a senior technical architect who needs to determine whether this document provides sufficient foundation for designing the architecture and planning execution. The reviewer should be asking: "Can I design a solution and create executable tasks from these requirements?"

**Requirements Clarity**
- Are functional requirements specific and testable?
- Would two different engineers reading these requirements build the same thing?
- Does each requirement describe a behavior (what), not an implementation (how)?

**Acceptance Criteria Quality**
- Is each criterion specific and measurable?
- Can completion be programmatically verified or verified through explicit inspection?
- Are there subjective requirements that need to be made concrete ("make it good", "improve performance")?

**Scope Boundaries**
- Is the out-of-scope section populated with items that prevent scope creep?
- Are scope boundaries clear enough that architecture and implementation will not drift?
- Does the scope cover all defined requirements without adding beyond what is needed?

**Consistency with Analysis**
- Do requirements trace back to the problem definition in analysis.md?
- Are the constraints from analysis.md reflected in non-functional requirements?
- Do success metrics align with success criteria in the analysis?
- Are there requirements that contradict or ignore analysis findings?

**Completeness**
- Are all template sections filled in (or explicitly marked N/A with reasoning)?
- Are non-functional requirements addressed for performance, security, and reliability?
- Are assumptions documented rather than hidden as implicit facts?

**Feasibility**
- Are requirements achievable within the constraints identified in the analysis?
- Is the scope reasonable for the ticket size?
- Are there requirements that will be difficult or impossible to verify?

### Common Issues

These problems frequently appear in PRD documents:

1. **Vague functional requirements.** Requirements use imprecise language ("implement properly", "handle errors gracefully") instead of specifying exact behaviors. Fix: rewrite each requirement as a specific, testable statement of what the system does.

2. **Unmeasurable acceptance criteria.** Criteria use subjective language ("improved user experience", "performs well") that cannot be verified. Fix: define exact thresholds, counts, states, or conditions that can be checked.

3. **Missing scope boundaries.** The out-of-scope section is empty or absent, leading to scope creep during architecture and implementation. Fix: list items that are related but explicitly excluded, and items deferred to future work.

4. **Requirements specify implementation.** Requirements describe how to build something rather than what it should do ("use a Redis cache", "implement with a factory pattern"). Fix: move implementation details to architecture.md and restate the requirement in terms of behavior or outcome.

5. **Inconsistency with analysis.** Requirements introduce goals or constraints not grounded in the analysis document, or contradict findings from analysis research. Fix: ensure every requirement traces to analysis findings, and reconcile any contradictions.

6. **Missing non-functional requirements.** Performance, security, or reliability requirements are omitted even when the analysis identifies relevant constraints. Fix: translate technical constraints from analysis into specific non-functional requirements with measurable targets.

7. **Generic user stories.** User stories read like template fill-ins rather than real usage scenarios. Fix: ground stories in the actual target users and use cases identified during analysis and ticket scoping.

8. **Hidden assumptions.** Conditions assumed to be true are embedded in requirements rather than listed explicitly. Fix: extract assumptions into the dedicated section so reviewers can validate them.

### Review Checklist

Use this checklist when reviewing a PRD. Every item should be satisfied before approval.

- Functional requirements are specific and testable (no vague language)
- Each requirement describes what the system does, not how it is built
- Non-functional requirements include measurable targets where applicable
- Acceptance criteria are measurable and verifiable (no subjective judgment)
- User stories reflect actual usage scenarios (or section marked N/A with reasoning)
- Out of scope explicitly lists excluded items to prevent scope creep
- Assumptions are documented explicitly (not embedded in requirements)
- Success metrics are measurable and connected to analysis success criteria
- Product vision aligns with the problem statement in analysis.md
- Requirements are consistent with constraints identified in analysis.md
- No requirements contradict analysis findings
- All template sections are addressed (filled or marked N/A with reasoning)
- Content is specific to this ticket (no boilerplate or generic statements)
- Requirements are feasible within the identified constraints
- The document provides sufficient foundation for architecture design
