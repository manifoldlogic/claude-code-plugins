# Reference: architecture.md

This document provides complete guidance for creating and reviewing the architecture document (`architecture.md`) in an SDD ticket. It is used by document agents spawned via initiation prompts.

## Creation Guide

### Purpose

The architecture document defines HOW the system will be built. It translates the requirements from the PRD into concrete technical decisions: component design, technology choices, data flow, integration points, and design rationale. Architecture serves the PRD -- every technical decision should support a functional requirement defined in prd.md.

As a Level 2 document in the dependency graph, architecture.md depends on both analysis.md and prd.md. It serves as the technical foundation for plan.md (phased delivery of the architecture), quality-strategy.md (testing approach for architectural components), and security-review.md (security assessment of the design).

### Prerequisites

The following must be complete before creating the architecture document:

- **analysis.md** (Level 0): The analysis document must exist and contain a well-researched problem definition, existing solutions, codebase patterns, and constraints. The architecture must respect these constraints and leverage existing patterns found during analysis research.

- **prd.md** (Level 1): The PRD must exist and contain specific, testable requirements, acceptance criteria, and scope boundaries. The architecture document designs the technical solution to satisfy these requirements. Every architectural decision should be traceable to one or more PRD requirements.

Read both the analysis and PRD documents first. The architecture must be consistent with the problem definition and constraints from analysis.md, and must address all functional and non-functional requirements from prd.md.

### Research Steps

Before writing the architecture document, perform these steps:

1. **Read the PRD** at the ticket planning path. Understand the functional requirements, non-functional requirements, acceptance criteria, and scope boundaries. These define what the architecture must deliver.

2. **Read the analysis document** to understand the problem context, existing codebase patterns, constraints, and research findings. The architecture must leverage existing patterns and respect identified constraints.

3. **Read the ticket README.md** to understand the original ticket intent and verify alignment with the requirements and analysis.

4. **Search the codebase for existing architecture patterns.** Use Grep and Glob to find how similar systems are structured in the codebase. Identify naming conventions, directory layouts, module boundaries, and established architectural approaches. The architecture should follow existing patterns unless there is explicit justification for diverging.

5. **Identify reusable components.** Determine which existing modules, utilities, libraries, or abstractions can be leveraged rather than rebuilt. For each potential component, verify it is suitable for the requirements by checking its interface, capabilities, and limitations.

6. **Make key design decisions.** For each major architectural choice, document the context (why the decision was needed), the decision itself, the rationale (why this choice over alternatives), and what alternatives were considered and why they were rejected. Design decisions should be pragmatic -- match the complexity of the solution to the complexity of the problem.

7. **Define technology choices.** For each component or layer, identify what technology, library, or framework will be used. Justify each choice with reference to project constraints, existing usage in the codebase, team familiarity, or specific technical requirements from the PRD.

8. **Design component responsibilities and interfaces.** Define what each component is responsible for, what interfaces it exposes, and what dependencies it has. Components should have clear boundaries and single responsibilities.

9. **Map data flow.** Describe how data moves through the system from source to destination. Include the sequence of components involved, transformations applied, and integration points with external systems.

10. **Identify integration points.** Document where the new architecture connects with existing systems. For each integration point, specify the integration method (API, CLI, library, event), data format, and any constraints or compatibility requirements.

11. **Address performance and maintainability.** Consider how the architecture meets non-functional requirements from the PRD. Document design choices that address performance targets, and explain how the design enables long-term maintenance.

### Quality Criteria

The architecture document meets quality standards when:

- The solution addresses all functional requirements from the PRD. Every requirement in prd.md should be supported by the architectural design. If a requirement is not addressed, the architecture document must explain why.
- Design decisions include context, rationale, and alternatives considered. Each decision explains why it was needed, why this option was chosen, and what was rejected. Decisions are traceable to PRD requirements or analysis constraints.
- Technology choices are justified with concrete reasoning. Justification references existing codebase usage, project constraints, specific technical capabilities, or measurable advantages -- not vague preferences.
- The architecture follows existing codebase patterns. When the codebase has established conventions for directory structure, naming, module boundaries, or integration approaches, the architecture conforms to them. Any deviation is explicitly justified.
- Components have clear responsibilities, interfaces, and dependencies. Each component does one thing, exposes a well-defined interface, and has documented dependencies. There are no ambiguous ownership boundaries.
- Data flow is described concretely. The path data takes through the system is traceable, including transformations and handoffs between components.
- Integration points with existing systems are documented with integration method, data format, and constraints.
- The design is pragmatic and not over-engineered. The complexity of the architecture matches the complexity of the problem. Unnecessary abstractions, speculative future-proofing, and enterprise patterns applied to simple problems are anti-patterns.
- Performance considerations address non-functional requirements from the PRD with specific design choices, not aspirational statements.
- Maintainability considerations explain how the design supports long-term evolution, not just initial delivery.

### Template

The architecture document uses the template at:

    {PLUGIN_ROOT}/skills/project-workflow/templates/ticket/architecture.md

The template defines these sections that must be filled in:

| Section | What to Write |
|---------|---------------|
| Overview | High-level description of the solution architecture |
| Design Decisions | Key decisions with context, rationale, and alternatives considered |
| Technology Choices | Component-technology mapping with justification for each choice |
| Component Design | Components with responsibilities, interfaces, and dependencies |
| Data Flow | How data moves through the system with component sequence and transformations |
| Integration Points | Connections with existing systems, including method and data format |
| Performance Considerations | How the architecture addresses performance requirements |
| Maintainability | Design choices that enable long-term maintenance and evolution |

## Review Guide

### Review Focus Areas

When reviewing an architecture document, evaluate it from the perspective of a senior technical architect who needs to determine whether this design can be implemented successfully and will satisfy the PRD requirements. The reviewer should be asking: "Can I create an execution plan and write tasks from this architecture?"

**PRD Alignment**
- Does the architecture address all functional requirements from prd.md?
- Are non-functional requirements (performance, security, reliability) reflected in design choices?
- Can each architectural decision be traced to a specific requirement or constraint?
- Are there requirements in the PRD that have no corresponding architectural support?

**Design Decision Quality**
- Does each decision include context, rationale, and alternatives considered?
- Are rationales grounded in concrete reasoning (existing patterns, measured constraints, specific capabilities)?
- Are alternatives genuinely evaluated, not straw-man options?
- Would a different engineer reading this rationale reach the same conclusion?

**Codebase Consistency**
- Does the architecture follow existing patterns in the codebase?
- Are deviations from established conventions explicitly justified?
- Are reusable components identified and leveraged rather than rebuilt?
- Were similar implementations in the codebase researched and referenced?

**Pragmatism and Appropriate Complexity**
- Is the simplest adequate solution chosen?
- Are abstractions justified by actual complexity, not speculative future needs?
- Does the architecture match the scope of the problem (not over-engineered)?
- Would a simpler approach satisfy the requirements without sacrificing quality?

**Component Clarity**
- Does each component have a clear, single responsibility?
- Are interfaces well-defined and documented?
- Are dependencies explicit and manageable?
- Are there components with unclear boundaries or overlapping responsibilities?

**Integration Completeness**
- Are all integration points with existing systems documented?
- Is the integration method specified for each connection (API, CLI, library, event)?
- Are data formats and compatibility constraints noted?
- Are there missing integration points that will surface during implementation?

**Executability**
- Is there sufficient detail for an execution plan to be created?
- Can tasks be defined from this architecture?
- Are there ambiguous areas that will require design decisions during implementation?
- Are performance and maintainability considerations actionable, not aspirational?

### Common Issues

These problems frequently appear in architecture documents:

1. **Missing PRD traceability.** Design decisions and component designs exist without clear connection to PRD requirements. Fix: for each major decision or component, reference the specific requirement(s) it satisfies.

2. **Vague technology justification.** Technology choices are stated without rationale, or justified with subjective preferences ("it's the best framework"). Fix: justify with concrete criteria -- existing codebase usage, specific technical capabilities, measurable performance characteristics, or constraint satisfaction.

3. **Ignoring existing codebase patterns.** The architecture introduces new patterns when the codebase has established conventions for the same type of work. Fix: search the codebase for existing patterns and follow them, or explicitly justify why a different approach is needed.

4. **Over-engineering.** The architecture introduces unnecessary abstractions, excessive layering, or speculative extensibility for a problem that does not warrant it. Fix: simplify to the minimum complexity that satisfies PRD requirements. Remove abstractions that do not solve a concrete, current need.

5. **Missing integration details.** Integration points are mentioned in passing but lack specifics about method, data format, or constraints. Fix: document each integration point with the integration method, expected data format, error handling approach, and any compatibility requirements.

6. **No alternatives considered.** Design decisions present a single option without documenting what else was evaluated. Fix: include at least one alternative for each major decision and explain why it was rejected.

7. **Aspirational performance claims.** Performance considerations state goals ("the system will be fast") without specific design choices that achieve them. Fix: tie each performance claim to a concrete architectural mechanism (caching strategy, indexing approach, concurrency model).

8. **Component boundary ambiguity.** Multiple components have overlapping responsibilities or it is unclear which component owns a particular behavior. Fix: clarify ownership boundaries and ensure each behavior has exactly one owning component.

### Review Checklist

Use this checklist when reviewing an architecture document. Every item should be satisfied before approval.

- Architecture addresses all functional requirements from prd.md
- Non-functional requirements are reflected in specific design choices
- Design decisions include context, rationale, and alternatives considered
- Technology choices are justified with concrete reasoning (not preferences)
- Architecture follows existing codebase patterns (or deviations are justified)
- Reusable components are identified and leveraged
- Each component has a clear single responsibility
- Component interfaces and dependencies are documented
- Data flow is described with concrete component sequences and transformations
- Integration points specify method, data format, and constraints
- Architecture is pragmatic (not over-engineered for the problem scope)
- Performance considerations are tied to specific design mechanisms
- Maintainability considerations are actionable
- The document provides sufficient detail for execution planning
- All template sections are addressed (filled or marked N/A with reasoning)
- Content is specific to this ticket (no boilerplate or generic statements)
- Architecture is consistent with constraints from analysis.md
- Architecture is consistent with requirements from prd.md
