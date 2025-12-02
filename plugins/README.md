# CrewChief Plugins

A collection of Claude Code plugins for development workflows and CI/CD automation.

## Available Plugins

### Workstream
**Version:** 0.3.0

Systematic project and ticket workflow management.

**Features:**
- Initiative and project planning with analysis and architecture documents
- Automated ticket generation from plans
- Complete workflow automation (implement → test → verify → commit)
- Specialized agents for each workflow phase
- Quality assurance built-in

**[Read More →](workstream/README.md)**

### GitHub Actions
**Version:** 0.1.0

GitHub Actions workflow creation, optimization, and troubleshooting.

**Features:**
- Workflow creation for any tech stack
- Performance optimization
- Debugging and troubleshooting
- Matrix builds and caching
- gh CLI integration for workflow management

**[Read More →](github-actions/README.md)**

## Installation

### Add Marketplace from GitHub

```bash
/plugin marketplace add manifoldlogic/claude-code-plugins
```

### Install Plugins

Install plugins individually:
```bash
/plugin install workstream@crewchief
/plugin install github-actions@crewchief
```

Or use the plugin manager UI:
```bash
/plugin
```

Then select "Browse Plugins" and choose the plugins you want to install.

## Plugin Structure

Each plugin follows the standard Claude Code plugin structure:

```
plugin-name/
├── .claude-plugin/
│   └── plugin.json          # Plugin metadata
├── README.md                # Plugin documentation
├── commands/                # Slash commands (optional)
├── agents/                  # Specialized agents (optional)
├── skills/                  # Agent skills (optional)
│   └── skill-name/
│       ├── SKILL.md
│       ├── scripts/
│       ├── references/
│       └── assets/
└── hooks/                   # Event handlers (optional)
    └── hooks.json
```

## Usage Patterns

### Project Management (Workstream)
1. Create project: `/workstream:project-create [description]`
2. Generate tickets: `/workstream:project-tickets [PROJECT_SLUG]`
3. Execute tickets: `/workstream:project-work [PROJECT_SLUG]`

### CI/CD Workflows (GitHub Actions)
1. Ask specialist: `@github-actions-specialist Create a CI workflow...`
2. Review generated workflow
3. Commit and push

## Development

### Testing Plugins Locally

1. Make changes to plugins
2. Uninstall plugin: `/plugin uninstall plugin-name@crewchief`
3. Reinstall plugin: `/plugin install plugin-name@crewchief`
4. Test changes

### Adding New Plugins

1. Create plugin directory in `plugins/`
2. Add `.claude-plugin/plugin.json` with metadata
3. Add plugin to `.claude-plugin/marketplace.json`
4. Create README.md with documentation
5. Add components (commands, agents, skills, hooks)

## Marketplace

**Name:** crewchief
**Owner:** Daniel Bushman (dbushman@manifoldlogic.com)
**Repository:** https://github.com/manifoldlogic/claude-code-plugins

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

See individual plugin READMEs for licensing information.

## Links

- [Repository](https://github.com/manifoldlogic/claude-code-plugins)
- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code)
