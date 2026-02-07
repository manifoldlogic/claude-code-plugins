# Skill Quality Criteria

This document provides the evaluation framework for determining whether a pattern extracted from a completed ticket qualifies as a repo-local skill. Use this during skill curation to ensure only high-quality, genuinely reusable skills are created.

## Skill Candidate Decision Tree

Work through these questions in order. A candidate must pass all four to qualify as a skill:

```
1. Was this pattern reused across multiple tasks in this ticket?
   |
   +-- YES --> Continue to question 2
   +-- NO  --> 2. Will this pattern likely be reused in future tickets?
                  |
                  +-- YES --> Continue to question 3
                  +-- NO  --> REJECT: Not reusable enough for a skill
   |
3. Is this pattern repo-specific or general knowledge?
   |
   +-- REPO-SPECIFIC --> Continue to question 4
   +-- GENERAL       --> REJECT: Already covered by general agent knowledge
   |
4. Can this pattern be explained concretely with examples?
   |
   +-- YES --> ACCEPT: Good skill candidate
   +-- NO  --> REJECT: Too abstract to be actionable
```

## Minimum Criteria

All three criteria must be satisfied for a pattern to qualify as a skill:

### 1. Reusability

The pattern must be reusable across multiple tickets or features. A pattern used only once in a single, unique context is not a skill -- it is an implementation detail.

**Ask:** "If a new developer started a similar ticket next month, would this pattern save them meaningful time or prevent mistakes?"

### 2. Specificity

The pattern must be repo-specific. General programming knowledge, language conventions, or widely-documented practices do not need to be captured as repo-local skills because agents already have this knowledge.

**Ask:** "Does this pattern depend on something specific to this repo -- its file structure, APIs, conventions, tools, or domain?"

### 3. Actionability

The pattern must provide concrete, actionable guidance. Observations, opinions, or abstract principles are not skills. A skill must tell the reader exactly what to do, with specific steps, file paths, code patterns, or commands.

**Ask:** "Could an agent follow this skill and produce correct output without asking clarifying questions?"

## Positive Examples

### Example 1: API Authentication Patterns

**Skill name:** `api-authentication-patterns`

**Why this is a good skill:** Captures the repo-specific bearer token format, error response structure, and retry logic. A new ticket involving API calls would benefit from knowing that this repo expects `Authorization: Bearer <token>` with a specific refresh flow, that 401 responses require token rotation (not just retry), and that the retry backoff follows a custom exponential pattern defined in `lib/http-client.ts`.

**Key qualities:** Repo-specific token handling, concrete code references, immediately actionable.

### Example 2: Test File Conventions

**Skill name:** `test-file-conventions`

**Why this is a good skill:** Documents where test files go (`__tests__/` adjacent to source), naming patterns (`*.test.ts` for unit, `*.integration.ts` for integration), required test structure (describe/it blocks with specific setup/teardown patterns), and test utilities available in `test/helpers/`. Without this skill, agents might create tests in the wrong location or miss required setup patterns.

**Key qualities:** Prevents common mistakes, references actual directory structure, includes naming rules.

### Example 3: Database Migration Workflow

**Skill name:** `database-migration-workflow`

**Why this is a good skill:** Explains the repo-specific migration process: generate migration with `pnpm db:migrate:create`, required naming convention (`YYYYMMDD_HHMMSS_description.sql`), that migrations must be idempotent, and the rollback testing procedure (`pnpm db:migrate:down && pnpm db:migrate:up` must succeed). Also documents that the CI pipeline runs migrations against a test database before merge.

**Key qualities:** Step-by-step procedure, repo-specific tooling, prevents CI failures.

## Negative Examples

### Example 1: "Write Good Code"

**Proposed skill:** General advice about code quality, readability, and maintainability.

**Why this fails:** Too vague and not actionable. Does not reference any repo-specific conventions. An agent already knows to write good code. This is an observation, not a procedure.

**Criteria failed:** Specificity, Actionability.

### Example 2: "Use Git for Version Control"

**Proposed skill:** Instructions on how to use git commit, push, and pull.

**Why this fails:** General knowledge that every agent already has. Not repo-specific. Adding this as a skill provides zero value because it duplicates built-in knowledge.

**Criteria failed:** Specificity.

### Example 3: "Testing is Important"

**Proposed skill:** A reminder that tests should be written for all code changes.

**Why this fails:** An observation, not actionable guidance. Does not tell the reader what kind of tests to write, where to put them, what conventions to follow, or what tools to use. Provides no concrete steps.

**Criteria failed:** Actionability, Specificity.

### Example 4: One-Off Debugging Session

**Proposed skill:** "How I fixed the memory leak in the batch processor on 2025-12-15."

**Why this fails:** A single debugging session for a specific bug is not reusable. Unless the debugging technique reveals a recurring pattern (e.g., "batch processors in this repo need explicit stream cleanup"), the fix itself is an implementation detail, not a skill.

**Criteria failed:** Reusability.

## Evaluation Checklist

Use this checklist when evaluating a skill candidate. All items must be checked for the skill to be accepted:

- [ ] Skill has a clear, specific trigger ("when to use this")
- [ ] Skill provides concrete steps or examples (not abstract advice)
- [ ] Skill is repo-specific (references actual files, APIs, conventions)
- [ ] Skill is reusable (applies to multiple tickets or features)
- [ ] Skill has no placeholders or TODO markers (immediately usable)
- [ ] Skill contains no secrets, credentials, or PII
- [ ] Skill name is descriptive and follows naming convention (`^[a-z][a-z0-9-]*$`, max 40 chars)
