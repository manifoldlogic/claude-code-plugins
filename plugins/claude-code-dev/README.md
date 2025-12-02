# Claude Code Dev Plugin

Development tools for Claude Code itself. Create skills, commands, hooks, and plugins.

## Installation

```bash
/plugin install claude-code-dev@crewchief
```

## Skills

### skill-creator

Guide for creating effective skills that extend Claude's capabilities with specialized knowledge, workflows, or tool integrations.

**When to use:** When users want to create a new skill or update an existing skill.

**Features:**
- Step-by-step skill creation process
- Scripts for initialization, validation, and packaging
- Best practices for progressive disclosure design
- Bundled resource organization (scripts, references, assets)

**Usage:**
1. The skill activates automatically when creating/editing skills
2. Use `scripts/init_skill.py` to scaffold new skills
3. Use `scripts/package_skill.py` to validate and package for distribution

### marketplace-manager

Manages Claude Code plugin marketplaces - adding plugins, updating configurations, and keeping documentation in sync.

**When to use:** When adding new plugins to a marketplace, updating marketplace configuration, or managing plugin documentation.

**Features:**
- Marketplace structure reference
- Step-by-step plugin creation workflow
- Documentation sync guidelines
- Validation checklist

**Usage:**
1. The skill activates when working with marketplace.json, plugin.json, or plugin READMEs
2. Use `scripts/init_plugin.py` to scaffold new plugin directories
3. Follow the workflow: scaffold → configure → document → register

## Roadmap

Future additions may include:
- Command creation helpers
- Hook development guides
- MCP server integration guides

## License

MIT License - see LICENSE.txt in skill directories for details.
