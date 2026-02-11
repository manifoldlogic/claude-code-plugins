---
name: skill-md-structure
description: Two SKILL.md documentation patterns - comprehensive executable skill structure vs lightweight reference skill structure
origin: ISKIM
created: 2026-02-08
tags: [documentation, skills, patterns]
---

# SKILL.md Documentation Structure

## Overview

This skill documents the two distinct SKILL.md documentation patterns used in the claude-code-plugins repository. Understanding these patterns is essential when creating new skills, as the structure depends on whether the skill provides executable capabilities or reference documentation.

**Two patterns:**

1. **Executable Skills**: Comprehensive documentation for skills with scripts that perform operations (12+ sections)
2. **Reference Skills**: Lightweight documentation for pattern/reference skills without executable code (5 sections)

## When to Use

### Use Executable Skill Pattern When:

- Skill provides shell scripts that perform operations (tab management, pane splitting, git operations)
- Users need to understand script options, exit codes, and execution contexts
- Troubleshooting guidance is needed for operational failures
- Performance considerations affect usage

### Use Reference Skill Pattern When:

- Skill documents a pattern or convention (test structure, code organization)
- No executable scripts are provided
- Purpose is to guide development or code review
- Skill serves as reference material for agents

## Pattern/Procedure

### Pattern 1: Executable Skill Structure

Used for operational skills with executable scripts. Example: `tab-management`, `pane-management`.

**Complete structure:**

```markdown
---
name: skill-name
description: Brief description of skill capabilities
---

# Skill Title

**Last Updated:** YYYY-MM-DD
**Plugin:** plugin-name
**Scripts Location:** `plugins/{plugin}/skills/{skill}/scripts/`

## Overview

[1-2 paragraphs explaining what the skill does and why it exists]

**Key Capabilities:**
- Bullet list of main features
- What operations are supported
- Integration points

**When to Use This Skill vs Manual Operations:**

| Use This Skill | Use Manual Operations |
|----------------|----------------------|
| Automation scenarios | One-off manual tasks |
| Scripting workflows | Exploratory testing |

## Prerequisites

### Required for All Modes
- List of required tools
- Installation instructions
- System requirements

### [Optional: Context-Specific Requirements]
- Additional requirements for specific execution contexts

## Skills Overview

| Script | Purpose | Key Options |
|--------|---------|-------------|
| script-name.sh | What it does | Main flags |

## Decision Tree

Guidance on choosing between different operations:

```
Start
  |
  +-- Scenario A? --> Use script-one.sh
  |
  +-- Scenario B? --> Use script-two.sh
```

## Common Scenarios

### Scenario 1: [Use Case Title]

**When:** Describe when to use this

**Example:**
```bash
./script.sh --option value
```

**Expected Output:**
```
Example output here
```

[Repeat for 3-5 common scenarios]

## Script Reference

### script-name.sh

**Purpose:** What the script does

**Usage:**
```bash
script-name.sh [OPTIONS] [ARGS]
```

**Options:**

| Flag | Description | Default | Required |
|------|-------------|---------|----------|
| -f | Flag description | value | Yes/No |

**Examples:**

```bash
# Example 1: Basic usage
./script.sh --basic

# Example 2: Advanced usage
./script.sh --advanced --with-options
```

[Repeat Script Reference section for each script]

## Execution Contexts

### Host Mode
- When executed on macOS host
- Behavior specifics

### Container Mode
- When executed inside container
- How it differs from host mode

## Exit Codes

| Code | Meaning | When It Occurs |
|------|---------|----------------|
| 0 | Success | Operation completed |
| 1 | Error type 1 | Specific condition |
| 2 | Error type 2 | Specific condition |

## Troubleshooting

### Issue 1: [Problem Description]

**Symptoms:** What users see

**Cause:** Why it happens

**Solution:**
```bash
# Commands to fix
```

[Repeat for 5-7 common issues]

## Performance Considerations

- Performance characteristics
- When operations are slow
- Optimization suggestions

## Security

- Security considerations specific to this skill
- Credential handling
- Access control notes

## Integration

How this skill integrates with:
- Other skills
- Workflows
- External tools

## Related

- other-skill-name - How they relate
- another-skill - Connection point
```

**Real example:** See `plugins/iterm/skills/tab-management/SKILL.md` (779 lines)

**Section count:** 12+ sections for comprehensive documentation

---

### Pattern 2: Reference Skill Structure

Used for documentation-only pattern skills. Example: `iterm-applescript-generation`, `eleven-category-test-structure`.

**Complete structure:**

```markdown
---
name: skill-name
description: One-line description under 200 characters
origin: TICKET_ID
created: YYYY-MM-DD
tags: [tag1, tag2, tag3]
---

# Skill Title

## Overview

[2-3 paragraphs explaining what pattern/convention this documents and why it's important]

This pattern ensures [benefit 1], [benefit 2], and [benefit 3].

## When to Use

Apply this pattern when:

- Creating/modifying [context 1]
- Building [context 2]
- Implementing [context 3]
- [4-6 specific triggers]

## Pattern/Procedure

### Core Structure

[Description of the pattern with code examples]

```language
# Example of the pattern
code here
```

### Key Components

#### 1. Component Name

[Detailed explanation with examples]

```language
# Component example
```

**Why:** Rationale for this component

**When to use:** When this component is needed

**When to skip:** When it's not needed

[Repeat for 3-5 key components]

### [Additional subsections as needed]

- Step-by-step procedures
- Variations on the pattern
- Edge cases
- Best practices

## Examples

### Example 1: [Scenario Title]

**Context:** When this example applies

**Implementation:**
```language
# Complete example code
```

**Key points:**
- What makes this example work
- Critical details
- Common mistakes to avoid

[Repeat for 2-4 examples from real code]

## References

- Ticket: TICKET_ID (origin of this pattern)
- Related files:
  - `path/to/file.ext` (where pattern is used)
  - `path/to/another.ext` (another example)
- Related skills:
  - related-skill-name (how it connects)
```

**Real examples:**
- `plugins/iterm/skills/iterm-applescript-generation/SKILL.md` (302 lines)
- `plugins/iterm/skills/iterm-cross-skill-sourcing/SKILL.md` (139 lines)
- `plugins/iterm/skills/eleven-category-test-structure/SKILL.md` (436 lines)

**Section count:** 5 sections (Overview, When to Use, Pattern/Procedure, Examples, References)

## Examples

### Example 1: Executable Skill (pane-management from ISKIM.1003)

**Context:** Documenting the iterm-split-pane.sh script

**SKILL.md frontmatter:**
```yaml
---
name: pane-management
description: iTerm2 pane splitting for opening new panes within existing tabs from macOS host or Linux container environments.
---
```

**Structure used:**
- Overview (2 paragraphs + key capabilities)
- Prerequisites (shared with tab-management)
- Skills Overview (table of scripts)
- Decision Tree (when to split vertically vs horizontally)
- Common Scenarios (4 scenarios with examples)
- Script Reference (iterm-split-pane.sh with full options table)
- Execution Contexts (host vs container)
- Exit Codes (table of 4 codes)
- Troubleshooting (6 common issues)
- Performance Considerations (SSH overhead notes)
- Related (cross-references)

**Total:** 515 lines, 11 major sections

**Why this pattern:** The skill provides an executable script with options, exit codes, and operational concerns requiring comprehensive documentation.

---

### Example 2: Reference Skill (iterm-applescript-generation from ISKIM.2002)

**Context:** Documenting AppleScript generation pattern for iTerm scripts

**SKILL.md frontmatter:**
```yaml
---
name: iterm-applescript-generation
description: Pattern for generating iTerm2 AppleScript with window checks, dual tell blocks, and conditional configuration
origin: PANE-001
created: 2026-02-08
tags: [iterm, applescript, code-generation]
---
```

**Structure used:**
- Overview (what pattern covers, why it matters)
- When to Use (4 specific triggers)
- Pattern/Procedure:
  - Core Structure (AppleScript template)
  - Key Components (5 components with examples)
- Examples (3 real examples from codebase)
- References (ticket origin, related files)

**Total:** 302 lines, 5 major sections

**Why this pattern:** The skill documents a code pattern, not an executable script. It guides developers/agents in writing consistent AppleScript, making the lightweight reference structure appropriate.

---

### Example 3: Decision Logic for Pattern Selection

```
Creating a new skill?
  |
  +-- Does it include executable scripts?
  |     |
  |     YES -> Use Executable Skill Pattern
  |           - 12+ sections
  |           - Include: Script Reference, Exit Codes, Troubleshooting, Performance
  |           - Examples: tab-management, pane-management
  |
  +-- Is it documentation/pattern/convention?
        |
        YES -> Use Reference Skill Pattern
              - 5 sections
              - Focus on: Pattern/Procedure, Examples
              - Examples: applescript-generation, test-structure
```

## Validation Checklist

### For Executable Skills:

- [ ] Frontmatter includes name and description
- [ ] Overview explains capabilities and use cases
- [ ] Prerequisites list all requirements
- [ ] Script Reference documents all scripts with options tables
- [ ] Exit Codes table covers all possible exit codes
- [ ] Common Scenarios provide 3-5 realistic examples
- [ ] Troubleshooting addresses 5-7 common issues
- [ ] Decision Tree or guidance for choosing operations
- [ ] Execution Contexts if skill behaves differently in different environments
- [ ] Related section cross-references other skills

### For Reference Skills:

- [ ] Frontmatter includes name, description, origin, created, tags
- [ ] Overview explains pattern and its importance
- [ ] When to Use has 4-6 specific triggers
- [ ] Pattern/Procedure provides concrete template and components
- [ ] Key Components section breaks down pattern elements
- [ ] Examples show 2-4 real uses from codebase
- [ ] References list ticket origin and related files

## Common Mistakes

### Mistake 1: Using executable pattern for reference skill

**Problem:** Documentation-only skill has Script Reference, Exit Codes, Troubleshooting sections

**Why it's wrong:** No scripts to document, these sections are empty or irrelevant

**Fix:** Use reference skill pattern with 5 sections focused on the pattern itself

---

### Mistake 2: Using reference pattern for executable skill

**Problem:** Skill with scripts lacks exit codes, troubleshooting, or options documentation

**Why it's wrong:** Users can't effectively use the scripts without this operational information

**Fix:** Use executable skill pattern with comprehensive sections

---

### Mistake 3: Mixing patterns inconsistently

**Problem:** Skills in same plugin use different structures arbitrarily

**Why it's wrong:** Makes navigation unpredictable, harder to find information

**Fix:** Apply patterns based on skill type (executable vs reference), not personal preference

---

### Mistake 4: Missing frontmatter fields

**Problem:** Reference skill lacks origin/created/tags, or executable skill lacks description

**Why it's wrong:** Breaks skill discovery and metadata tracking

**Fix:**
- Executable skills: Require name and description minimum
- Reference skills: Require name, description, origin, created, tags

## References

- Ticket: ISKIM (created 5 SKILL.md files following both patterns)
- Related files:
  - `plugins/iterm/skills/tab-management/SKILL.md` (executable pattern, 779 lines)
  - `plugins/iterm/skills/pane-management/SKILL.md` (executable pattern, 515 lines)
  - `plugins/iterm/skills/iterm-applescript-generation/SKILL.md` (reference pattern, 302 lines)
  - `plugins/iterm/skills/iterm-cross-skill-sourcing/SKILL.md` (reference pattern, 139 lines)
  - `plugins/iterm/skills/eleven-category-test-structure/SKILL.md` (reference pattern, 436 lines)
- Related skills:
  - plugin-skills-registration (how skills are registered in plugin.json)
