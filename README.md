# CrewChief Plugins for Claude Code

A collection of Claude Code plugins for development workflows, project management, and CI/CD automation.

## Quick Start

Add the marketplace and install plugins:

```bash
# Add the crewchief marketplace from GitHub
/plugin marketplace add manifoldlogic/claude-code-plugins

# Install plugins
/plugin install sdd@crewchief
/plugin install github-actions@crewchief
```

## Available Plugins

| Plugin | Description |
|--------|-------------|
| **sdd** | Spec-Driven Development - epic planning, ticket execution, and task-based implementation |
| **github-actions** | GitHub Actions workflow creation, optimization, and troubleshooting |
| **claude-code-dev** | Development tools for Claude Code: skills, commands, hooks, and plugins |
| **maproom** | Semantic code search using crewchief-maproom CLI |
| **worktree** | Git worktree management using crewchief CLI |
| **vscode** | VS Code workspace configuration management |
| **game-design** | Game design consultant agents synthesized from legendary designers |

## SDD Plugin

Spec-Driven Development - enterprise workflow management for structured development.

**Features:**
- Epic planning for research and discovery work
- Ticket-based deliverables with analysis and architecture documents
- Task-level implementation with verification
- Specialized agents for each workflow phase (Haiku for mechanical tasks, Sonnet for reasoning)

**Commands:**
- `/sdd:plan-ticket [description]` - Create a new ticket with planning documents
- `/sdd:create-tasks [SLUG]` - Generate tasks from ticket plan
- `/sdd:do-task [TASK_ID]` - Complete a single task with verification
- `/sdd:status` - Check epic/ticket/task status

**[Full Documentation →](plugins/sdd/README.md)**

## GitHub Actions Plugin

GitHub Actions workflow creation, optimization, and troubleshooting.

**Features:**
- Workflow creation for any tech stack
- Performance optimization and debugging
- Matrix builds and caching strategies
- gh CLI integration for workflow management

**Agent:** `@github-actions-specialist`

**[Full Documentation →](plugins/github-actions/README.md)**

## Claude Code Dev Plugin

Development tools for Claude Code itself.

**Features:**
- Skill creation and packaging
- Step-by-step guides for extending Claude capabilities
- Scripts for initialization, validation, and distribution

**Skill:** `skill-creator` - Guides creation of effective skills with bundled resources

**[Full Documentation →](plugins/claude-code-dev/README.md)**

## Installation Options

### From GitHub (Recommended)

```bash
/plugin marketplace add manifoldlogic/claude-code-plugins
```

### As a Submodule

For repositories that want to bundle the plugins:

```bash
git submodule add https://github.com/manifoldlogic/claude-code-plugins.git .crewchief/claude-code-plugins
```

Then add to `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "crewchief": {
      "source": {
        "source": "directory",
        "path": ".crewchief/claude-code-plugins"
      }
    }
  }
}
```

## Repository Structure

```
claude-code-plugins/
├── .claude-plugin/
│   └── marketplace.json      # Marketplace configuration
├── plugins/
│   ├── sdd/                  # Spec-Driven Development workflow
│   │   ├── commands/         # Slash commands
│   │   ├── agents/           # Specialized agents
│   │   └── skills/           # Agent skills with scripts
│   ├── github-actions/       # GitHub Actions management
│   │   ├── agents/           # Specialized agents
│   │   └── skills/           # gh CLI skill
│   └── claude-code-dev/      # Claude Code development tools
│       └── skills/           # skill-creator and more
└── docs/                     # Additional documentation
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Links

- [Repository](https://github.com/manifoldlogic/claude-code-plugins)
- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code)

## License

MIT License - see individual plugin READMEs for details.
