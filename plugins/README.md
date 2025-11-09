# CrewChief Plugins

A collection of Claude Code plugins for development workflows, code search, and CI/CD automation.

## Available Plugins

### Maproom
**Version:** 0.1.0

Semantic code search with PostgreSQL, pgvector, and tree-sitter.

**Features:**
- Semantic code search (find code by concept)
- Repository indexing with scan/watch scripts
- MCP integration for search tools
- Multi-language support (TypeScript, Rust, Python, Go, JavaScript, Markdown)
- Multiple search modes (FTS, vector, hybrid)

**[Read More →](maproom/README.md)**

### Projects
**Version:** 0.1.0

Systematic project and ticket workflow management.

**Features:**
- Project planning with analysis and architecture documents
- Automated ticket generation from plans
- Complete workflow automation (implement → test → verify → commit)
- Specialized agents for each workflow phase
- Quality assurance built-in

**[Read More →](projects/README.md)**

### GitHub Actions
**Version:** 0.1.0

GitHub Actions workflow creation, optimization, and troubleshooting.

**Features:**
- Workflow creation for any tech stack
- Performance optimization
- Debugging and troubleshooting
- Matrix builds and caching
- MCP integration with GitHub API

**[Read More →](github-actions/README.md)**

## Installation

### Add Marketplace

```bash
/plugin marketplace add /workspace/.crewchief/claude-code-plugins
```

### Install Plugins

Install all plugins:
```bash
/plugin install maproom@crewchief
/plugin install projects@crewchief
/plugin install github-actions@crewchief
```

Or install individually via the plugin manager:
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
├── hooks/                   # Event handlers (optional)
│   └── hooks.json
└── .mcp.json               # MCP server config (optional)
```

## Usage Patterns

### Semantic Code Search (Maproom)
1. Start PostgreSQL: `docker compose up -d`
2. Scan repository: `bash scripts/scan.sh`
3. Search code: `mcp__maproom__search({ repo: "crewchief", query: "error handling" })`

### Project Management (Projects)
1. Create project: `/create-project [description]`
2. Generate tickets: `/create-project-tickets [PROJECT_SLUG]`
3. Execute tickets: `/work-on-project [PROJECT_SLUG]`

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
5. Add components (commands, agents, skills, hooks, MCP)

## Marketplace

**Name:** crewchief
**Owner:** Daniel Bushman (dbushman@manifoldlogic.com)
**Repository:** https://github.com/danielbushman/claude-code-plugins

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

See individual plugin READMEs for licensing information.

## Links

- [Plugin Documentation](../docs/plugins.md)
- [Repository](https://github.com/danielbushman/claude-code-plugins)
- [Claude Code Documentation](https://code.claude.com/docs)
