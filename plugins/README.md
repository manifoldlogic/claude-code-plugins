# CrewChief Plugins

A collection of Claude Code plugins for development workflows and CI/CD automation.

## Available Plugins

### SDD (Spec-Driven Development)
**Version:** 0.3.0

Enterprise workflow management for epics, tickets, and tasks.

**Features:**
- Epic planning for research and discovery work
- Ticket-based deliverables with analysis and architecture documents
- Task-level implementation with verification
- Specialized agents for each workflow phase
- Quality assurance built-in

**[Read More →](sdd/README.md)**

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

### Maproom
**Version:** 0.1.0

Semantic code search using the maproom CLI.

**Features:**
- Semantic code search by concept (not just text matching)
- Full-text search (FTS) and vector similarity search
- Query formulation guidance for effective searches
- Architecture exploration and code navigation
- Integration with maproom CLI

**[Read More →](maproom/README.md)**

### Worktree
**Version:** 0.1.0

Git worktree management using the crewchief CLI.

**Features:**
- Create isolated worktrees for parallel development
- Safe branch operations with automatic stashing
- Merge and cleanup workflows
- Switch between worktrees seamlessly
- Integration with crewchief worktree commands

**[Read More →](worktree/README.md)**

### VS Code
**Version:** 0.1.0

VS Code and Cursor workspace configuration management.

**Features:**
- Create and modify .code-workspace files
- Manage folders, settings, and extensions
- Launch configuration management
- Task definition support

**[Read More →](vscode/README.md)**

### Game Design
**Version:** 0.1.0

Game design consultant agents synthesized from legendary designers.

**Features:**
- 9 specialized agent personas for game design consulting
- Design roles distilled from 14 legendary designers
- Core mechanics, narrative, audio, and visual design guidance

**[Read More →](game-design/README.md)**

## Installation

### Add Marketplace from GitHub

```bash
/plugin marketplace add manifoldlogic/claude-code-plugins
```

### Install Plugins

Install plugins individually:
```bash
/plugin install sdd@crewchief
/plugin install github-actions@crewchief
/plugin install maproom@crewchief
/plugin install worktree@crewchief
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

### Project Management (SDD)
1. Create ticket: `/sdd:plan-ticket [description]`
2. Generate tasks: `/sdd:create-tasks [TICKET_SLUG]`
3. Execute tasks: `/sdd:do-task [TASK_ID]`

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
