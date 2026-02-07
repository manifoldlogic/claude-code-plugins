---
name: skill-curation
description: Curate, evaluate, and manage repo-local skills extracted from completed tickets. Use this skill when archiving tickets to capture reusable patterns, when planning tickets to discover existing skills, or when managing the repo-local skill library.
---

# Skill Curation

## Overview

The skill curation system adds a self-reinforcing learning loop to the SDD workflow. It captures reusable patterns from completed tickets as repo-local skills stored under `${SDD_ROOT_DIR}/skills/`, making them discoverable during future planning.

Repo-local skills follow the same SKILL.md format used by marketplace plugin skills. This consistency means skills can later be promoted to the marketplace without format conversion.

## When to Use

- **After archiving a ticket**: Evaluate completed work for reusable patterns worth capturing
- **During ticket planning**: Check for existing repo-local skills relevant to new work
- **On-demand curation**: Explicitly curate skills from any completed ticket
- **Skill management**: List, review, or evaluate existing repo-local skills

## Scripts

| Script | Purpose | Output |
|--------|---------|--------|
| `scripts/list-skills.sh` | Enumerate repo-local skills | JSON with skill metadata |

### list-skills.sh

Enumerates all skills under `${SDD_ROOT_DIR}/skills/` and outputs JSON:

```bash
bash scripts/list-skills.sh
```

Output format:
```json
{
  "skills": [
    {
      "name": "api-testing-patterns",
      "description": "REST API testing conventions for this project",
      "origin": "APIV2",
      "tags": "[testing, api]",
      "path": "/app/.sdd/skills/api-testing-patterns/"
    }
  ],
  "count": 1
}
```

## References

| Document | Purpose |
|----------|---------|
| `references/skill-quality-criteria.md` | Decision tree and evaluation criteria for skill candidates |
| `references/skill-creation-workflow.md` | Step-by-step instructions for creating a new skill |

## Skill Storage

Skills are stored at `${SDD_ROOT_DIR}/skills/{skill-name}/SKILL.md`. Each skill directory may also contain:

- `references/` - Detailed reference documentation
- `scripts/` - Automation scripts
- `assets/` - Output files

## Important Notes

**Version Control:** Repo-local skills are intended to remain local to your development environment and should not be committed to version control. If `${SDD_ROOT_DIR}` is located inside a git repository, ensure it is included in your `.gitignore` file (e.g., add `.sdd/` to `.gitignore`). If `SDD_ROOT_DIR` is outside your repository, no action is needed.

## Quick Start

1. **List existing skills:**
   ```bash
   bash scripts/list-skills.sh
   ```

2. **Evaluate a skill candidate:** Read `references/skill-quality-criteria.md` for the decision tree and checklist.

3. **Create a new skill:** Follow the steps in `references/skill-creation-workflow.md`.
