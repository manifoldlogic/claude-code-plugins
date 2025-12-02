# Plugin Directory Structure Reference

Complete reference for Claude Code plugin directory structure.

## Directory Layout

```
plugin-name/
├── .claude-plugin/
│   └── plugin.json           # Required: Plugin metadata
├── README.md                 # Required: Plugin documentation
├── agents/                   # Optional: Agent definitions
│   └── agent-name.md
├── commands/                 # Optional: Slash commands
│   └── command-name.md
└── skills/                   # Optional: Skills
    └── skill-name/
        ├── SKILL.md          # Required for skills
        ├── scripts/          # Optional: Executable scripts
        ├── references/       # Optional: Reference docs
        └── assets/           # Optional: Output files
```

## Required Files

### plugin.json

Located at `.claude-plugin/plugin.json`. Defines plugin metadata.

```json
{
  "name": "plugin-name",
  "version": "1.0.0",
  "description": "What the plugin does",
  "author": {
    "name": "Author Name",
    "email": "email@example.com",
    "url": "https://github.com/author"
  },
  "repository": "https://github.com/org/repo",
  "keywords": ["keyword1", "keyword2"]
}
```

| Field | Required | Description |
|-------|----------|-------------|
| name | Yes | Plugin identifier (lowercase, hyphenated) |
| version | Yes | Semantic version (x.y.z) |
| description | Yes | 1-2 sentence description |
| author.name | Yes | Author or organization name |
| author.email | No | Contact email |
| author.url | No | Author URL or repo |
| repository | No | Source code repository |
| keywords | No | Discovery keywords |

### README.md

Plugin documentation at root level. Should include:

- Title and description
- Installation instructions
- Feature list
- Usage documentation
- License information

## Optional Components

### agents/

Agent definitions as markdown files. Each `.md` file defines one agent.

**Filename**: `agent-name.md` (lowercase, hyphenated)

**Content**: System prompt and instructions for the agent.

**Example agents**:
- `github-actions-specialist.md` - CI/CD expertise
- `project-planner.md` - Planning workflows

### commands/

Slash commands as markdown files. Each `.md` file defines one command.

**Filename**: `command-name.md` (lowercase, hyphenated)

**Usage**: `/plugin-name:command-name [args]`

**Content**: Prompt template with optional `$ARGUMENTS` placeholder.

**Example commands**:
- `status.md` - Check project status
- `project-create.md` - Create new project

### skills/

Skills are directories containing `SKILL.md` plus optional resources.

**Structure**:
```
skill-name/
├── SKILL.md              # Required: Skill definition with YAML frontmatter
├── scripts/              # Python/bash scripts
├── references/           # Documentation for Claude to read
└── assets/               # Files for output (templates, images)
```

**SKILL.md frontmatter**:
```yaml
---
name: skill-name
description: When to use this skill and what it does
---
```

## Naming Conventions

| Component | Convention | Example |
|-----------|------------|---------|
| Plugin directory | lowercase-hyphenated | `github-actions` |
| plugin.json name | matches directory | `"name": "github-actions"` |
| Agent files | lowercase-hyphenated.md | `code-reviewer.md` |
| Command files | lowercase-hyphenated.md | `run-tests.md` |
| Skill directories | lowercase-hyphenated | `skill-creator` |

## Marketplace Registration

After creating a plugin, register it in the marketplace's `marketplace.json`:

```json
{
  "plugins": [
    {
      "name": "plugin-name",
      "source": "./plugins/plugin-name",
      "description": "Brief description"
    }
  ]
}
```

The `source` path is relative to the marketplace root directory.
