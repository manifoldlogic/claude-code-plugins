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
| [sdd](plugins/sdd/README.md) | Spec-Driven Development - workflow management for structured epic planning, ticket execution, and task-based implementation |
| [github-actions](plugins/github-actions/README.md) | GitHub Actions workflow creation, optimization, and troubleshooting |
| [claude-code-dev](plugins/claude-code-dev/README.md) | Development tools for Claude Code: skills, commands, hooks, and plugins |
| [maproom](plugins/maproom/README.md) | Semantic code search using maproom CLI |
| [obsidian](plugins/obsidian/README.md) | Obsidian vault management using obsidian-cli |
| [worktree](plugins/worktree/README.md) | Git worktree management using crewchief CLI |
| [game-design](plugins/game-design/README.md) | Game design consultant agents synthesized from 14 legendary designers |
| [vscode](plugins/vscode/README.md) | VS Code and Cursor workspace configuration management |
| [iterm](plugins/iterm/README.md) | iTerm2 tab and pane management for macOS host and Linux container environments |
| [analysis](plugins/analysis/README.md) | Deep analytical thinking and problem-solving tools for complex technical and strategic decisions |
| [rust-analyzer-lsp](plugins/rust-analyzer-lsp/README.md) | Rust language server integration via rust-analyzer for code intelligence, diagnostics, and navigation |
| [cmux](plugins/cmux/README.md) | cmux terminal management for macOS host via SSH from devcontainers |
| [devx](plugins/devx/README.md) | Developer experience orchestration layer for multi-plugin development workflows |

## Installation

After adding the marketplace (see Quick Start above), install individual plugins:

```bash
/plugin install <plugin-name>@crewchief
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

MIT License. Individual components may have their own licenses; see plugin directories for details.
