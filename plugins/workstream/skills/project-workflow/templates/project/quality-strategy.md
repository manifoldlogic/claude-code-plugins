# Quality Strategy: {NAME}

## Testing Philosophy

[Approach to testing - pragmatic, focused on confidence not coverage]

Our goal is to test for **confidence**, not **coverage metrics**. We focus on:
- Critical paths that must work
- Integration points where bugs are likely
- Business logic that would cause real problems if wrong

## Test Types

### Unit Tests

**Scope:** [What unit tests cover]

**Tools:** [Testing frameworks]

**Coverage Target:** [Pragmatic target - focus on critical paths, not 100%]

**What to Test:**
- [Critical function 1]
- [Business logic 1]

**What NOT to Test:**
- Simple getters/setters
- Trivial transformations
- Framework code

### Integration Tests

**Scope:** [What integration tests cover]

**Approach:** [How integration is tested]

**Key Integration Points:**
- [Integration point 1]
- [Integration point 2]

### End-to-End Tests (if applicable)

**Scope:** [Critical user paths only]

**Approach:** [E2E testing strategy]

**Critical Paths:**
- [Critical path 1]
- [Critical path 2]

## Critical Paths

The following paths **MUST** be tested:

1. **[Critical Path 1]**
   - [Why it's critical]
   - [How to test]

2. **[Critical Path 2]**
   - [Why it's critical]
   - [How to test]

## Test Data Strategy

[How test data is managed]

- [Fixtures approach]
- [Mock data approach]
- [Database state management]

## Quality Gates

Before verification, each ticket must:

- [ ] Unit tests pass for new/modified code
- [ ] Integration tests pass (if applicable)
- [ ] No linting errors
- [ ] No type errors (if applicable)
- [ ] Critical paths tested

## Pragmatic Approach

We **avoid**:
- Testing for coverage metrics alone
- Testing trivial code
- Complex mocking when simpler approaches work
- Slow tests when fast tests work

We **embrace**:
- Testing what matters
- Simple test setups
- Fast feedback loops
- Integration tests for integration points
