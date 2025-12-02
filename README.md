# CrewChief Plugins for Claude Code

A collection of Claude Code plugins for development workflows, project management, and CI/CD automation.

## Quick Start

Add the marketplace and install plugins:

```bash
# Add the crewchief marketplace from GitHub
/plugin marketplace add manifoldlogic/claude-code-plugins

# Install plugins
/plugin install workstream@crewchief
/plugin install github-actions@crewchief
```

## Available Plugins

| Plugin | Description |
|--------|-------------|
| **workstream** | Project and ticket workflow management with specialized agents |
| **github-actions** | GitHub Actions workflow creation, optimization, and troubleshooting |

## Workstream Plugin

Systematic project and ticket workflow management.

**Features:**
- Initiative and project planning with analysis and architecture documents
- Automated ticket generation from plans
- Complete workflow automation (implement → test → verify → commit)
- Specialized agents for each workflow phase (Haiku for mechanical tasks, Sonnet for reasoning)

**Commands:**
- `/workstream:project-create [description]` - Create a new project
- `/workstream:project-tickets [SLUG]` - Generate tickets from project plan
- `/workstream:project-work [SLUG]` - Execute all tickets for a project
- `/workstream:ticket [TICKET_ID]` - Complete a single ticket
- `/workstream:status [SLUG]` - Check project/ticket status

**[Full Documentation →](plugins/workstream/README.md)**

## GitHub Actions Plugin

GitHub Actions workflow creation, optimization, and troubleshooting.

**Features:**
- Workflow creation for any tech stack
- Performance optimization and debugging
- Matrix builds and caching strategies
- gh CLI integration for workflow management

**Agent:** `@github-actions-specialist`

**[Full Documentation →](plugins/github-actions/README.md)**

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
│   ├── workstream/           # Project workflow management
│   │   ├── commands/         # Slash commands
│   │   ├── agents/           # Specialized agents
│   │   └── skills/           # Agent skills with scripts
│   └── github-actions/       # GitHub Actions management
│       ├── agents/           # Specialized agents
│       └── skills/           # gh CLI skill
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
