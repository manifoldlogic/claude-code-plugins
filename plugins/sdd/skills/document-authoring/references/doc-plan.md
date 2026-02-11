# Reference: plan.md

This document provides complete guidance for creating and reviewing the execution plan document (`plan.md`) in an SDD ticket. It is used by document agents spawned via initiation prompts.

## Creation Guide

### Purpose

The plan document defines a phased execution strategy for delivering the architecture. It translates the technical design from the architecture document into concrete phases, each with objectives, deliverables, agent assignments, and estimated task counts. The plan is what the task-creator agent uses to generate individual tasks -- it must be specific enough that tasks can be derived directly from its phases and deliverables.

As a Level 3 document in the dependency graph, plan.md depends on architecture.md (and transitively on prd.md and analysis.md). It is independent of quality-strategy.md and security-review.md, which are also Level 3 documents and may be created concurrently.

### Prerequisites

The following must be complete before creating the plan document:

- **architecture.md** (Level 2): The architecture document must exist and contain a complete technical design with components, interfaces, design decisions, technology choices, data flow, and integration points. The plan organizes the delivery of this architecture into executable phases.

- **prd.md** (Level 1): The PRD must exist and contain specific requirements, acceptance criteria, and scope boundaries. The plan must deliver all features defined in the PRD.

- **analysis.md** (Level 0): The analysis document must exist and contain the problem definition, constraints, and success criteria. The plan must respect these constraints and its success metrics should align with analysis success criteria.

Read the architecture document first, as it is the primary input to the plan. Then read the PRD to verify that the plan covers all requirements. Reference the analysis for constraints and success criteria.

### Research Steps

Before writing the plan document, perform these steps:

1. **Read the architecture document** at the ticket planning path. Understand the component design, technology choices, integration points, and design decisions. The plan must deliver all of these components through organized phases.

2. **Read the PRD** to understand the functional requirements, non-functional requirements, and acceptance criteria. Every requirement in the PRD must be addressed by at least one phase in the plan. Verify that the plan's deliverables collectively satisfy all PRD requirements.

3. **Read the analysis document** to understand the constraints and success criteria. The plan must operate within identified constraints (technical, business, time) and its success metrics should be traceable to analysis success criteria.

4. **Read the ticket README.md** to understand the original ticket intent and verify alignment with the planned delivery approach.

5. **Identify natural phase boundaries.** Examine the architecture for logical groupings of work: foundation or infrastructure components that must exist before feature components, core functionality before integration or polish, and dependencies between components. Each phase should represent a coherent, independently testable milestone.

6. **Define deliverables for each phase.** Every phase must produce concrete, verifiable deliverables. A deliverable is a specific artifact -- a file, module, configuration, test suite, or document -- not an abstract activity. Deliverables should be specific enough that a task can be created to produce each one.

7. **Assign agents to deliverables.** Determine which agent type is best suited for each piece of work. Use the agent model strategy: Haiku for mechanical or structured tasks (scaffolding, status reports, commits, test execution), Sonnet for reasoning work (implementation, review, verification), and Opus for complex decisions (research-heavy planning, cross-cutting architectural work).

8. **Estimate task counts per phase.** Based on the number and complexity of deliverables, estimate how many individual tasks each phase will generate. Tasks should be scoped to 2-8 hours of agent work. If a deliverable requires more than 8 hours, it should be split into multiple tasks across the phase.

9. **Identify phase dependencies.** Document which phases must complete before others can start. Most plans follow a linear sequence (Phase 1 before Phase 2), but some phases within the same level may be parallelizable. External dependencies (on other tickets, systems, or decisions) must also be documented.

10. **Assess risks and define mitigations.** For each significant risk to the plan, document the probability, impact, and a concrete mitigation strategy. Risks should be specific to this plan, not generic software development risks.

11. **Define success metrics.** Create measurable success criteria for the overall plan. These should align with the success criteria from the analysis and the acceptance criteria from the PRD. Each metric must be verifiable.

### Task Numbering Convention

Tasks are numbered using a phase-based scheme:

- Phase 1 tasks: X.1001, X.1002, X.1003, ...
- Phase 2 tasks: X.2001, X.2002, X.2003, ...
- Phase 3 tasks: X.3001, X.3002, X.3003, ...

Where X is the ticket identifier. This numbering scheme makes it immediately clear which phase a task belongs to and preserves ordering within phases.

### Deliverable Disposition

When a phase produces deliverable artifacts (documents, reports, findings), each deliverable should have a disposition indicating what happens to it after the ticket completes:

- **extract: path/to/dest** -- Extract to a permanent location in the codebase (for documentation with lasting value)
- **archive** -- Archive with the ticket (for temporary proof-of-work or working documents)
- **external: description** -- Place in an external system (wiki, shared drive, etc.)

Include a deliverables table with a Disposition column when phases produce non-code artifacts.

### Quality Criteria

The plan document meets quality standards when:

- Phases are logical and represent coherent milestones. Each phase has a clear objective that can be independently verified. Phase boundaries align with natural breakpoints in the architecture (foundation before features, core before integration).
- Deliverables are concrete and specific. Each deliverable names a specific artifact (file, module, test suite) rather than an abstract activity ("implement caching"). A task can be directly created to produce each deliverable.
- Task scope is appropriate. Estimated task counts reflect 2-8 hour tasks. A phase with a single massive deliverable that would take 40 hours should be broken into multiple deliverables or sub-tasks.
- Agent assignments are appropriate. Mechanical tasks (scaffolding, running tests, committing code) are assigned to Haiku. Reasoning tasks (implementation, review, verification) are assigned to Sonnet. Complex decision-making tasks (research, architectural analysis) are assigned to Opus.
- Dependencies are documented. Both phase-to-phase dependencies and external dependencies are identified, with impact assessment for external dependencies.
- Risks are specific and mitigations are actionable. Risks reference actual concerns for this plan (not generic platitudes), and mitigations describe concrete steps to reduce probability or impact.
- Success metrics are measurable and traceable. Each metric can be verified objectively and traces back to success criteria in the analysis or acceptance criteria in the PRD.
- The plan covers all PRD requirements. Every functional requirement in the PRD is addressed by at least one phase's deliverables. There are no orphaned requirements.
- The plan is consistent with the architecture. Phases deliver the components, interfaces, and integration points described in architecture.md. The plan does not introduce architectural decisions not present in the architecture document.

### Template

The plan document uses the template at:

    {PLUGIN_ROOT}/skills/project-workflow/templates/ticket/plan.md

The template defines these sections that must be filled in:

| Section | What to Write |
|---------|---------------|
| Overview | Brief description of the execution approach and overall strategy |
| Phase 1 (and subsequent phases) | Objective, deliverables, agent assignments, and estimated task count for each phase |
| Dependencies - Phase Dependencies | Which phases depend on which, typically a linear chain |
| Dependencies - External Dependencies | Dependencies on other tickets, systems, or decisions with status and impact |
| Risk Mitigation | Specific risks with probability, impact, and mitigation strategy |
| Success Metrics | Measurable criteria for plan success as a checklist |
| Timeline (Optional) | Task count estimates per phase and total; avoid specific date commitments |

## Review Guide

### Review Focus Areas

When reviewing a plan document, evaluate it from the perspective of a senior technical architect who needs to determine whether this plan can be successfully executed by agents. The reviewer should be asking: "Can a task-creator agent generate well-scoped, executable tasks from this plan?"

**Phase Organization**
- Are phases logically ordered with clear, verifiable objectives?
- Does each phase represent a coherent milestone that can be independently tested?
- Are phase boundaries aligned with natural breakpoints in the architecture?
- Are there too few phases (massive monolithic phases) or too many (unnecessary granularity)?

**Deliverable Specificity**
- Is each deliverable a concrete artifact (file, module, test suite), not an abstract activity?
- Can a task be directly created to produce each deliverable?
- Are deliverables specific enough that completion can be objectively verified?
- Do deliverables collectively cover all PRD requirements?

**Task Scope Appropriateness**
- Do estimated task counts reflect 2-8 hour tasks?
- Are there deliverables that would require more than 8 hours and should be split?
- Can agents work independently on individual tasks within a phase?
- Are verification criteria for each task implicit in the deliverable definition?

**Agent Assignment Correctness**
- Are mechanical tasks assigned to Haiku (scaffolding, test execution, commits)?
- Are reasoning tasks assigned to Sonnet (implementation, review, verification)?
- Are complex decision tasks assigned to Opus (research, architectural analysis)?
- Are there mismatches where the wrong agent tier is assigned to a task type?

**Architecture Alignment**
- Does the plan deliver all components defined in architecture.md?
- Are integration points from the architecture addressed in the appropriate phases?
- Does the plan introduce work not justified by the architecture?
- Is the phasing consistent with architectural dependencies (e.g., foundation components before dependent components)?

**Dependency Completeness**
- Are phase-to-phase dependencies documented?
- Are external dependencies identified with status and impact assessment?
- Are there hidden dependencies that would block execution if unmet?
- Is the dependency chain free of circular dependencies?

**Risk Assessment Quality**
- Are risks specific to this plan, not generic software development risks?
- Are mitigations actionable and concrete?
- Are high-probability or high-impact risks addressed?
- Do mitigations reduce probability or impact to acceptable levels?

### Common Issues

These problems frequently appear in plan documents:

1. **Abstract deliverables.** Deliverables describe activities ("implement caching", "set up testing") rather than specific artifacts. Fix: name the exact file, module, or artifact that will be produced, and specify what it contains.

2. **Oversized tasks.** A phase has very few deliverables but an estimated large task count, or deliverables that clearly require more than 8 hours of work. Fix: break large deliverables into smaller, independently verifiable pieces that fit the 2-8 hour task scope.

3. **Missing PRD coverage.** Some PRD requirements are not addressed by any phase's deliverables. Fix: map each PRD requirement to at least one deliverable and identify any gaps.

4. **Incorrect agent assignments.** Implementation work assigned to Haiku (which lacks reasoning depth) or mechanical scaffolding assigned to Opus (which is overqualified and more expensive). Fix: match agent tier to task complexity using the agent model strategy.

5. **Missing external dependencies.** The plan assumes availability of systems, services, or decisions that are not yet confirmed. Fix: document all external dependencies with their current status and the impact if they are unavailable.

6. **Generic risk assessment.** Risks are boilerplate ("scope creep", "technical debt") without specific relevance to this plan. Fix: identify risks that are specific to the actual work being planned, referencing particular components, integrations, or decisions.

7. **No phase verification criteria.** Phases have deliverables but no clear way to verify the phase is complete. Fix: ensure each phase's deliverables are concrete enough that completion is self-evident, or add explicit verification criteria.

8. **Architecture inconsistency.** The plan describes components, technologies, or approaches not present in architecture.md, or omits architectural components. Fix: cross-reference every plan deliverable against the architecture document and reconcile differences.

9. **Missing task numbering guidance.** The plan does not indicate how tasks will be numbered across phases. Fix: include phase-based numbering convention (Phase 1: X.1001+, Phase 2: X.2001+, etc.).

### Review Checklist

Use this checklist when reviewing a plan document. Every item should be satisfied before approval.

- Phases are logically ordered with clear objectives
- Each phase represents a coherent, independently testable milestone
- Phase boundaries align with architectural dependencies
- Deliverables are concrete artifacts (files, modules, test suites), not abstract activities
- Each deliverable can be used to create a 2-8 hour task
- Agent assignments follow the agent model strategy (Haiku/Sonnet/Opus)
- All PRD requirements are covered by at least one phase's deliverables
- Plan is consistent with architecture.md (delivers all components, no unauthorized additions)
- Phase-to-phase dependencies are documented
- External dependencies are identified with status and impact
- Risks are specific to this plan with actionable mitigations
- Success metrics are measurable and traceable to analysis/PRD criteria
- Task numbering convention is specified (phase-based: X.1001, X.2001, etc.)
- Deliverable dispositions are specified for non-code artifacts (if applicable)
- All template sections are addressed (filled or marked N/A with reasoning)
- Content is specific to this ticket (no boilerplate or generic statements)
- Plan is consistent with constraints from analysis.md
- Plan delivers all requirements from prd.md
