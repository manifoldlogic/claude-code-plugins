# Reference: quality-strategy.md

This document provides complete guidance for creating and reviewing the quality strategy document (`quality-strategy.md`) in an SDD ticket. It is used by document agents spawned via initiation prompts.

## Creation Guide

### Purpose

The quality strategy document defines the testing approach for the ticket. It establishes testing philosophy, coverage requirements, test types, critical paths that require comprehensive testing, negative testing requirements, test data strategy, and quality gates. The quality strategy ensures that implementation is enterprise-grade: tested thoroughly, with error paths treated as first-class concerns and coverage thresholds treated as mandatory floors.

As a Level 3 document in the dependency graph, quality-strategy.md depends on architecture.md (and transitively on prd.md and analysis.md). It is independent of plan.md and security-review.md, which are also Level 3 documents and may be created concurrently.

### Prerequisites

The following must be complete before creating the quality strategy document:

- **architecture.md** (Level 2): The architecture document must exist and contain a complete technical design with components, interfaces, design decisions, technology choices, data flow, and integration points. The quality strategy defines how each architectural component will be tested, what integration points require integration tests, and which design decisions introduce critical paths requiring comprehensive coverage.

- **prd.md** (Level 1): The PRD must exist and contain specific requirements, acceptance criteria, and non-functional requirements. The quality strategy must ensure that every acceptance criterion from the PRD is verifiable through defined tests. Non-functional requirements (performance, reliability) inform coverage targets and test types.

- **analysis.md** (Level 0): The analysis document must exist and contain the problem definition, constraints, existing codebase patterns, and success criteria. The quality strategy must respect technical constraints (e.g., available testing frameworks, CI environment) and align testing approach with existing test patterns found during analysis research.

Read the architecture document first, as it is the primary input to the quality strategy. The component design, integration points, and data flow define what must be tested. Then read the PRD for acceptance criteria and non-functional requirements, and the analysis for constraints and existing test patterns.

### Research Steps

Before writing the quality strategy document, perform these steps:

1. **Read the architecture document** at the ticket planning path. Understand the component design, technology choices, integration points, data flow, and design decisions. Each component requires unit testing. Each integration point requires integration testing. Each critical design decision introduces a critical path that must have comprehensive test coverage.

2. **Read the PRD** to understand the acceptance criteria and non-functional requirements. Every acceptance criterion in the PRD must be verifiable through tests defined in the quality strategy. Non-functional requirements (performance targets, reliability thresholds, scalability requirements) inform test types and coverage targets.

3. **Read the analysis document** to understand the constraints, existing codebase patterns, and success criteria. Identify existing test frameworks, test conventions, and coverage thresholds in the codebase. The quality strategy must use the same frameworks and meet or exceed existing coverage levels.

4. **Read the ticket README.md** to understand the original ticket intent and verify alignment with the planned testing approach.

5. **Search the codebase for existing test patterns.** Use Grep and Glob to find how tests are organized, which frameworks are used, what naming conventions exist, and what coverage thresholds are already established. The quality strategy must follow these patterns. Note the directory structure for tests, assertion libraries in use, and any test utility modules available for reuse.

6. **Identify existing coverage thresholds.** Search for coverage configuration (e.g., coverage settings in package.json, pytest config, or CI configuration). The quality strategy must define thresholds that meet or exceed these existing levels. Coverage must never decrease.

7. **Identify critical paths from the architecture.** A critical path is a code path where failure would cause significant user impact, data corruption, security breach, or system outage. For each critical path, the quality strategy must require comprehensive testing: happy path, error cases, edge cases, and boundary conditions.

8. **Map integration points to integration tests.** For each integration point documented in the architecture, define what integration tests are needed. Consider failure scenarios at each integration point: service unavailability, timeout handling, partial failures, and recovery behavior.

9. **Identify negative testing requirements.** For each component, determine what inputs are invalid, what resources could be missing, what permissions could be denied, and what concurrent access conflicts could occur. These must all have corresponding test cases.

10. **Define quality gates.** Determine what checks must pass before a task is considered verified. Quality gates include unit test passage, coverage threshold compliance, integration test passage, linting, type checking, and comprehensive critical path testing.

### Quality Criteria

The quality strategy document meets quality standards when:

- Testing philosophy is specific to this ticket, not generic platitudes. It states concrete principles that guide testing decisions for this particular architecture and these particular requirements.
- Coverage thresholds are defined with specific numeric targets (line, branch, function coverage). Thresholds meet or exceed existing codebase coverage levels. There is no tolerance for reducing existing coverage.
- Test types (unit, integration, end-to-end) are mapped to specific architectural components and integration points. Each test type section identifies what it covers, which tools or frameworks are used, and what the coverage target is.
- Critical paths are explicitly identified with references to specific architectural components or data flows. Each critical path has requirements for happy path testing, error case testing, edge case testing, and boundary condition testing. Critical paths are not just listed -- they include reasoning for why each is critical.
- Negative testing requirements are comprehensive. Invalid inputs, missing data, unauthorized access, resource-not-found scenarios, concurrent access conflicts, and system resource exhaustion are all addressed. These are not optional -- they are first-class testing concerns.
- Test data strategy is defined. The document specifies how test fixtures, mock data, and database state are managed. If existing test data utilities exist in the codebase, they are referenced.
- Quality gates are specific, actionable checklist items. Each gate can be verified programmatically or through explicit inspection. Gates include both functional correctness (tests pass) and quality standards (coverage thresholds, linting, type checking).
- The quality strategy is consistent with the architecture. Test types and coverage targets correspond to actual components and integration points in architecture.md. There are no references to components that do not exist in the architecture.
- Enterprise testing standards are upheld. Coverage is mandatory, not optional. Error paths are tested as thoroughly as success paths. Thresholds are floors, not aspirational targets.

### Template

The quality strategy document uses the template at:

    {PLUGIN_ROOT}/skills/project-workflow/templates/ticket/quality-strategy.md

The template defines these sections that must be filled in:

| Section | What to Write |
|---------|---------------|
| Testing Philosophy | Approach to testing specific to this ticket, covering focus areas and priorities |
| Coverage Requirements | Minimum thresholds for line, branch, and function coverage that meet or exceed existing levels |
| Test Types - Unit Tests | Scope, tools, coverage target, what to test, and error/edge case testing requirements |
| Test Types - Integration Tests | Scope, approach, key integration points, and failure scenarios to test |
| Test Types - End-to-End Tests | Critical user paths and E2E strategy (if applicable, mark N/A with reasoning if not) |
| Critical Paths | Specific code paths requiring comprehensive coverage with happy path, error, and edge case tests |
| Negative Testing Requirements | All features must include tests for invalid inputs, missing data, unauthorized access, etc. |
| Test Data Strategy | How test data is managed: fixtures, mocks, database state, and reusable test utilities |
| Quality Gates | Checklist of gates that must pass before task verification |
| Enterprise Standards | Mandatory coverage, first-class error path testing, thresholds as floors |

## Review Guide

### Review Focus Areas

When reviewing a quality strategy document, evaluate it from the perspective of a senior QA architect who needs to determine whether this strategy will catch defects before they reach production. The reviewer should be asking: "If agents implement this ticket following this quality strategy, will the resulting code be production-ready?"

**Coverage Threshold Adequacy**
- Are line, branch, and function coverage thresholds explicitly defined with numeric values?
- Do thresholds meet or exceed existing codebase coverage levels?
- Is there an explicit prohibition against reducing existing coverage?
- Are coverage targets realistic but demanding?

**Critical Path Identification**
- Are critical paths explicitly identified with references to architectural components?
- Does each critical path include requirements for happy path, error case, edge case, and boundary condition testing?
- Is the reasoning for why each path is critical documented?
- Are there obvious critical paths from the architecture that are missing from the strategy?

**Test Type Coverage**
- Are unit tests mapped to specific components from the architecture?
- Are integration tests mapped to specific integration points from the architecture?
- Are the correct testing frameworks specified (consistent with existing codebase)?
- Is each test type's scope clearly defined (what it covers and what it does not)?

**Negative Testing Completeness**
- Are invalid inputs and malformed data tested?
- Are missing required data scenarios covered?
- Are unauthorized access and permission failures tested?
- Are resource-not-found scenarios included?
- Are concurrent access conflicts addressed?
- Are system resource exhaustion scenarios considered?
- Are failure modes at each integration point tested (unavailability, timeouts, partial failures)?

**Architecture Alignment**
- Does the quality strategy reference actual components from architecture.md?
- Are all integration points from the architecture covered by integration tests?
- Are there references to components or systems not present in the architecture?
- Does the testing approach match the technology choices from the architecture?

**Quality Gate Rigor**
- Are quality gates specific and actionable (not vague aspirations)?
- Can each gate be verified programmatically or through explicit inspection?
- Do gates include both functional correctness and quality standards?
- Are gates comprehensive: test passage, coverage thresholds, linting, type checking, critical path testing?

**Enterprise Standards Compliance**
- Is testing treated as mandatory, not optional?
- Are error paths given equal importance to success paths?
- Are thresholds treated as floors, not targets?
- Is the overall tone enterprise-grade (no "nice to have" or "if time permits" language)?

### Common Issues

These problems frequently appear in quality strategy documents:

1. **Generic testing philosophy.** The testing philosophy section reads like boilerplate that could apply to any project. Fix: include specific references to this ticket's architecture, critical components, and risk areas. Explain why the testing focus areas were chosen for this particular work.

2. **Missing or vague coverage thresholds.** Coverage requirements say "high coverage" or "adequate testing" without numeric targets. Fix: specify exact percentages for line, branch, and function coverage. Reference existing codebase thresholds to ensure they are met or exceeded.

3. **Happy-path-only test planning.** Test descriptions only cover success scenarios. Error handling, invalid inputs, boundary conditions, and failure modes are missing. Fix: for every test area, explicitly include negative tests, error cases, and edge conditions.

4. **Critical paths not identified.** The document lists test types and coverage targets but does not identify which code paths are critical and require comprehensive testing. Fix: extract critical paths from the architecture -- components that handle data integrity, authentication, financial operations, or other high-impact functions -- and define comprehensive test requirements for each.

5. **Test types not mapped to architecture.** The unit tests and integration tests sections describe testing in the abstract without connecting to specific architectural components or integration points. Fix: reference specific components from architecture.md in each test type section. Map each integration test to a specific integration point.

6. **Missing test data strategy.** The document defines what to test but not how test data is managed. Fix: specify the approach to fixtures, mocks, database state, and test data cleanup. Reference existing test data utilities in the codebase if they exist.

7. **Weak quality gates.** Quality gates are vague ("code is tested") or incomplete (missing linting, type checking, or coverage threshold verification). Fix: define each gate as a specific, verifiable check with a clear pass/fail criterion.

8. **Architecture inconsistency.** The quality strategy references components, services, or integration points not present in architecture.md, or omits testing for components that are in the architecture. Fix: cross-reference every test target against the architecture document and reconcile differences.

9. **Aspirational language for mandatory requirements.** Sections use "should", "ideally", or "if time permits" for testing requirements that are actually mandatory in enterprise software. Fix: use "must" and "required" language. Testing is not optional.

### Review Checklist

Use this checklist when reviewing a quality strategy document. Every item should be satisfied before approval.

- Testing philosophy is specific to this ticket (not generic boilerplate)
- Coverage thresholds are defined with specific numeric values (line, branch, function)
- Coverage thresholds meet or exceed existing codebase levels
- Explicit prohibition against reducing existing coverage is stated
- Unit tests are mapped to specific architectural components
- Integration tests are mapped to specific integration points from architecture.md
- Testing frameworks match existing codebase conventions
- Critical paths are identified with references to architectural components or data flows
- Each critical path has happy path, error case, edge case, and boundary condition test requirements
- Reasoning for each critical path's criticality is documented
- Negative testing requirements cover: invalid inputs, missing data, unauthorized access, resource-not-found, concurrent access, resource exhaustion
- Integration point failure scenarios are covered: unavailability, timeouts, partial failures, recovery
- Test data strategy is defined (fixtures, mocks, database state management)
- Quality gates are specific, actionable, and verifiable
- Quality gates include: test passage, coverage thresholds, linting, type checking, critical path testing
- Enterprise standards are upheld (mandatory language, not aspirational)
- Quality strategy is consistent with architecture.md (references real components and integration points)
- Quality strategy addresses non-functional requirements from prd.md
- Quality strategy respects technical constraints from analysis.md (available frameworks, CI environment)
- All template sections are addressed (filled or marked N/A with reasoning)
- Content is specific to this ticket (no boilerplate or generic statements)
