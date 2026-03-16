# CrewChief Plugins

A collection of Claude Code plugins for development workflows, project management, and CI/CD automation.

## Available Plugins

| Name | Version | Description |
|------|---------|-------------|
| [sdd](sdd/README.md) | 0.7.0 | Spec Driven Development - workflow management for structured epic planning, ticket execution, and task-based implementation |
| [github-actions](github-actions/README.md) | 0.2.0 | GitHub Actions workflow management with specialized agent and gh CLI skill for CI/CD pipelines |
| [claude-code-dev](claude-code-dev/README.md) | 0.2.1 | Development tools for Claude Code itself - create skills, commands, hooks, and plugins |
| [maproom](maproom/README.md) | 0.9.1 | Semantic code search using the maproom CLI - find code by concept and explore architecture |
| [worktree](worktree/README.md) | 0.5.0 | Git worktree management using the crewchief CLI for parallel development branches |
| [vscode](vscode/README.md) | 0.2.0 | VS Code and Cursor workspace configuration management |
| [game-design](game-design/README.md) | 0.1.0 | Game design consultant agents synthesized from 14 legendary game designers |
| [iterm](iterm/README.md) | 0.5.1 | iTerm2 tab and pane management for macOS host and Linux container environments |
| [obsidian](obsidian/README.md) | 0.1.1 | Obsidian vault management using obsidian-cli from the devcontainer |
| [analysis](analysis/README.md) | 0.1.0 | Deep analytical thinking and problem-solving tools for complex decisions |
| [rust-analyzer-lsp](rust-analyzer-lsp/README.md) | 1.0.0 | Rust language server integration via rust-analyzer for code intelligence and diagnostics |
| [cmux](cmux/README.md) | 0.1.0 | cmux terminal management for macOS host via SSH from devcontainers |
| [devx](devx/README.md) | 0.2.1 | Developer experience orchestration layer composing worktree, cmux, and vscode plugins |

## Installation

### Add Marketplace from GitHub

```bash
/plugin marketplace add manifoldlogic/claude-code-plugins
```

### Install Plugins

Install plugins individually:
```bash
/plugin install <plugin-name>@crewchief
```

Or use the plugin manager UI:
```bash
/plugin
```

Then select "Browse Plugins" and choose the plugins you want to install.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

See individual plugin READMEs for licensing information.
