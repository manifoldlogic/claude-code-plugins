# Skill Creation Workflow

This document provides step-by-step instructions for creating a new repo-local skill under `${SDD_ROOT_DIR}/skills/`. Follow these steps in order.

## Step 1: Detect Skill Candidate

Before creating a skill, verify the candidate passes the quality criteria:

1. Review ticket artifacts (planning docs, task files, commit messages)
2. Identify patterns that were reused or would be reused in future work
3. Apply the decision tree from `skill-quality-criteria.md`
4. Verify all three minimum criteria are met: Reusability, Specificity, Actionability
5. Run through the evaluation checklist in `skill-quality-criteria.md`

**Output:** A confirmed skill candidate with a proposed name and description.

## Step 2: Validate Skill Name

The skill name must conform to these rules:

- **Format:** Lowercase letters, digits, and hyphens only
- **Pattern:** `^[a-z][a-z0-9-]*$` (must start with a letter)
- **Length:** Maximum 40 characters (enforced -- names exceeding this limit are rejected during skill creation)
- **No path separators:** Must not contain `/`, `\`, or `..`
- **Descriptive:** The name should indicate what the skill covers

**Validation steps:**

1. Check the proposed name matches the pattern `^[a-z][a-z0-9-]*$`
2. Check the name is 40 characters or fewer. This limit is enforced during skill creation; names that exceed it will be rejected with the error: `"Skill name exceeds 40-character limit: {name} ({length} characters)"`
3. Check for conflicts with existing skills:
   ```bash
   bash scripts/list-skills.sh
   ```
   Verify no existing skill has the same name.

**Good names:** `api-authentication-patterns`, `test-file-conventions`, `database-migration-workflow`

**Bad names:** `My Skill` (spaces, uppercase), `../escape` (path traversal), `a` (not descriptive)

## Step 3: Create Skill Directory

Create the skill directory under `${SDD_ROOT_DIR}/skills/`:

```bash
mkdir -p "${SDD_ROOT_DIR}/skills/{skill-name}"
```

Optionally create subdirectories if the skill needs them:

```bash
mkdir -p "${SDD_ROOT_DIR}/skills/{skill-name}/references"
mkdir -p "${SDD_ROOT_DIR}/skills/{skill-name}/scripts"
```

## Step 4: Create SKILL.md

Create `${SDD_ROOT_DIR}/skills/{skill-name}/SKILL.md` using the template below. Replace all `{placeholder}` values with actual content. The final SKILL.md must have no placeholders or TODO markers.

### SKILL.md Template

```markdown
---
name: {skill-name}
description: {one-line description of when to use this skill}
origin: {TICKET_ID}
created: {YYYY-MM-DD}
tags: [{tag1}, {tag2}]
---

# {Skill Title}

## Overview

{Brief explanation of what this skill covers and why it is useful for this repo}

## When to Use

{Specific triggers or situations where this skill applies. Be concrete:
 - "When creating a new API endpoint..."
 - "When writing integration tests for..."
 - "When configuring the build pipeline for..."}

## Pattern/Procedure

{Concrete steps, examples, code snippets, or conventions.
 This is the core of the skill. Provide enough detail that an agent
 can follow these instructions and produce correct output.}

## Examples

{Real examples from this repo showing the pattern in use.
 Reference actual file paths and code where possible.}

## References

- Ticket: {TICKET_ID}
- Related files: {list of files where this pattern appears}
```

### Template Field Guide

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Skill name matching directory name |
| `description` | Yes | One-line summary, under 200 characters |
| `origin` | No | Ticket ID that created this skill |
| `created` | No | ISO date (YYYY-MM-DD) |
| `tags` | No | Comma-separated tags in brackets |
| `promotion-candidate` | No | `true` or `false`, for cross-repo potential |
| `last-used` | No | ISO date, for maintenance tracking |
| `last-updated` | No | ISO date, for maintenance tracking |

## Step 5: Verify Skill

After creating the skill, verify it meets all requirements:

1. **SKILL.md exists:**
   ```bash
   test -f "${SDD_ROOT_DIR}/skills/{skill-name}/SKILL.md"
   ```

2. **Frontmatter is valid:**
   - File starts with `---` on the first line
   - File has a second `---` delimiter closing the frontmatter block
   - All frontmatter lines are simple `key: value` pairs
   - `name` field is present and matches the directory name
   - `description` field is present and is under 200 characters

3. **No placeholders remain:**
   - Search for `{` and `}` in the SKILL.md body (outside frontmatter tags field)
   - Search for `TODO` or `TBD` markers

4. **Skill is listed:**
   ```bash
   bash scripts/list-skills.sh
   ```
   Verify the new skill appears in the output with correct metadata.

5. **Content quality:**
   - Has Overview section explaining the skill
   - Has When to Use section with specific triggers
   - Has Pattern/Procedure section with concrete steps
   - All examples reference actual repo files or conventions

## Frontmatter Schema

### Constraints

- **Simple key-value pairs only:** No multiline values, no nested structures, no complex YAML
- **Key format:** Must match `^[a-z][a-z0-9-]*$` (lowercase, hyphens, digits)
- **Value format:** Single-line strings only
- **Tags format:** YAML inline array syntax `[tag1, tag2]` (parsed as a single-line string)

### Required Fields

| Field | Type | Validation |
|-------|------|------------|
| `name` | string | Must match `^[a-z][a-z0-9-]*$`, max 40 chars (enforced) |
| `description` | string | Non-empty, max 200 characters |

### Optional Fields

| Field | Type | Default | Validation |
|-------|------|---------|------------|
| `origin` | string | none | Ticket ID format |
| `created` | string | none | ISO date (YYYY-MM-DD) |
| `tags` | string | none | Inline YAML array `[tag1, tag2]` |
| `promotion-candidate` | string | `false` | `true` or `false` |
| `last-used` | string | none | ISO date (YYYY-MM-DD) |
| `last-updated` | string | none | ISO date (YYYY-MM-DD) |

## Validation Rules

1. **Skill name must match directory name:** The `name` field in frontmatter must exactly match the directory name under `${SDD_ROOT_DIR}/skills/`.

2. **No path traversal:** Skill names must not contain `/`, `\`, or `..`. These are rejected to prevent directory traversal attacks.

3. **Description must be a single line:** The `description` field must be under 200 characters and contain no newlines.

4. **Frontmatter must be parseable by grep/sed:** Because `list-skills.sh` uses simple text matching (not a YAML parser), frontmatter must use only simple `key: value` pairs. Complex YAML features (multiline strings, anchors, nested maps) will cause parsing failures.

5. **SKILL.md body must have required sections:** At minimum, the body must contain Overview, When to Use, and Pattern/Procedure sections.

6. **No secrets or credentials:** Skills must never contain API keys, passwords, tokens, or other sensitive information. Use references to environment variables or configuration files instead.
