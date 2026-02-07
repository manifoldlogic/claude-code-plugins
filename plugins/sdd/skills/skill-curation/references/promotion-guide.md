# Skill Promotion Guide

How to evaluate, generalize, and promote repo-local skills to the marketplace.

## 1. Evaluation Criteria

### Cross-Repo Applicability Checklist

Before promoting a repo-local skill, evaluate it against these criteria:

- [ ] Skill used successfully in this repo for 2+ tickets
- [ ] Addresses common development pattern (not repo-specific quirk)
- [ ] Would benefit other projects using similar tech stacks
- [ ] Can be generalized (no hardcoded repo-specific values)
- [ ] No dependencies on repo-specific file paths or configurations

All five criteria should be met before proceeding with promotion. If any criterion fails, the skill may still be valuable as a repo-local skill but is not ready for marketplace promotion.

## 2. Generalization Steps

### 2.1 Identify Hardcoded Values

Review the skill for any values that are specific to the current repo:

- **File paths**: Replace absolute or repo-specific paths with parameterized references (e.g., `${PROJECT_ROOT}`, `${SDD_ROOT_DIR}`)
- **Repo names**: Replace with placeholders or configuration variables (e.g., `{repo-name}`, `${REPO_NAME}`)
- **URLs**: Replace with example URLs or configurable endpoints (e.g., `https://example.com/api`)

### 2.2 Add Configuration Guidance

Document how users should configure the skill for their environment:

- **Environment variables**: List all required and optional env vars with descriptions and defaults
- **Directory structure**: Describe expected directory layout and any prerequisites
- **Setup instructions**: Provide step-by-step setup for first-time users, including any dependencies

### 2.3 Expand Documentation

Broaden the skill documentation beyond the original repo context:

- **Multiple scenarios**: Document at least 3 different use cases across different project types
- **Edge cases**: Document known limitations, boundary conditions, and failure modes
- **Troubleshooting**: Add a troubleshooting section with common issues and their solutions

## 3. Documentation Requirements

A marketplace-ready skill must have comprehensive documentation:

- Comprehensive SKILL.md with clearly defined sections: Overview, Usage, Examples, and Troubleshooting
- At least 3 concrete examples showing different use cases (e.g., different languages, frameworks, or project sizes)
- References section linking to related skills, tools, and external documentation
- Clear "When to Use" and "When NOT to Use" guidance so users can quickly determine applicability

## 4. Testing Requirements

Before submitting to the marketplace, verify the skill works beyond the original repo:

- Test the generalized skill in 2+ different repositories with different tech stacks or project structures
- Verify the skill works in a fresh environment with no pre-existing assumptions (no leftover state, no implicit dependencies)
- Confirm all examples in the documentation are valid and have been tested end-to-end
- Ensure all scripts are portable and POSIX-compatible (no bash-only syntax, no platform-specific commands)

## 5. Promotion Workflow

### Step 1: Prepare

Generalize the skill using the steps in Section 2. Test using the criteria in Section 4. Document using the requirements in Section 3. The skill should be fully self-contained and ready for use outside the original repo.

### Step 2: Use skill-creator tool

Use the skill-creator tool to create a marketplace-ready skill package from the repo-local skill:

```
/claude-code-dev:create-skill
```

This will scaffold the marketplace skill structure from the existing repo-local skill, applying the standard template and ensuring all required files are present.

### Step 3: Test in fresh repo

Clone the marketplace skill into a fresh repository that has never used the skill before:

- Verify the skill installs and configures correctly
- Run through all documented examples
- Confirm the skill produces expected results without any repo-specific context

### Step 4: Submit to marketplace

Submit the skill to the marketplace via pull request:

- Include test results from Step 3 demonstrating cross-repo functionality
- Include usage examples covering at least 3 different scenarios
- Reference the original repo-local skill and tickets where it was developed and validated

## 6. References

- Skill creator tool: `plugins/claude-code-dev/skills/skill-creator/SKILL.md`
- Marketplace manager tool: `plugins/claude-code-dev/skills/marketplace-manager/SKILL.md`
- Plugin development guide: `plugins/claude-code-dev/README.md`
