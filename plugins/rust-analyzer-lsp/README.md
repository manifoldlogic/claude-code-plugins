# rust-analyzer-lsp Plugin

Rust language server integration for Claude Code via rust-analyzer.

## Overview

This plugin provides LSP (Language Server Protocol) capabilities for Rust development in Claude Code. It configures Claude Code to use the `rust-analyzer` language server, enabling code intelligence features for `.rs` files including diagnostics, go-to-definition, find-references, and hover information.

This plugin is a drop-in replacement for the official `rust-analyzer-lsp@claude-plugins-official` plugin, which is broken due to a caching bug that loses the LSP configuration during installation.

## Features

- **Diagnostics**: Real-time error and warning detection in Rust source files
- **Go-to-Definition**: Navigate to function, type, and variable definitions
- **Find References**: Locate all usages of a symbol across the codebase
- **Hover Information**: View type signatures and documentation on hover
- **Code Intelligence**: Type inference, trait resolution, and macro expansion

## Prerequisites

**rust-analyzer** must be installed and available in your PATH.

Verify installation:
```bash
command -v rust-analyzer
```

If not installed, see the [rust-analyzer installation guide](https://rust-analyzer.github.io/manual.html#installation).

Common installation methods:
```bash
# Via rustup (recommended)
rustup component add rust-analyzer

# Via Homebrew (macOS)
brew install rust-analyzer

# Via GitHub releases
# Download from https://github.com/rust-lang/rust-analyzer/releases
```

**Recommended version**: rust-analyzer 1.70.0 or later

This plugin works with any recent rust-analyzer version (tested with 1.93.0). Older versions may have limited LSP features.

## Installation

Install the plugin using the Claude Code plugin command:

```
/plugin install rust-analyzer-lsp@crewchief --scope project
```

### Migrating from the Official Plugin

If you have the broken official plugin installed, uninstall it first:

```
claude plugin uninstall rust-analyzer-lsp@claude-plugins-official
/plugin install rust-analyzer-lsp@crewchief --scope project
```

Both plugins register the same LSP server name, so having both installed simultaneously may cause conflicts. Uninstall the official plugin before installing this one.

## Verifying Installation

After installing the plugin, verify it's working:

1. Check plugin is installed: `claude plugin list | grep rust-analyzer`
2. Check rust-analyzer is in PATH: `command -v rust-analyzer`
3. Open a .rs file and ask Claude about errors in the file
4. Claude should mention diagnostics from rust-analyzer

## How It Works

The plugin ships a `.lsp.json` file that tells Claude Code how to launch rust-analyzer:

- **Server**: `rust-analyzer` (spawned as a child process)
- **Transport**: stdio (stdin/stdout)
- **File mapping**: `.rs` files are mapped to the `rust` language identifier

When you open or edit a `.rs` file, Claude Code automatically starts rust-analyzer and begins receiving diagnostics, type information, and navigation data.

## Troubleshooting

### "Executable not found in $PATH"

**Problem**: Claude Code reports that `rust-analyzer` cannot be found.

**Solution**:
1. Verify rust-analyzer is installed: `command -v rust-analyzer`
2. If installed via rustup, ensure `~/.cargo/bin` is in your PATH
3. Restart Claude Code after modifying your PATH

### LSP Not Activating on .rs Files

**Problem**: No diagnostics or code intelligence when editing Rust files.

**Solution**:
1. Verify the plugin is installed: check your plugin list
2. Confirm rust-analyzer is in your PATH
3. Check that the project has a `Cargo.toml` (rust-analyzer requires a Cargo project)
4. Restart the Claude Code session

### Duplicate LSP Server Registration

**Problem**: Both the official and crewchief plugins are installed.

**Solution**: Uninstall the official plugin:
```
claude plugin uninstall rust-analyzer-lsp@claude-plugins-official
```

### LSP Works After Installing rust-analyzer but Not Before

**Problem**: You installed rust-analyzer after installing the plugin, but LSP still doesn't activate.

**Solution**: Claude Code reads $PATH at session start. Restart your Claude Code session to pick up the new binary location.

## Version

1.0.0

## Author

Daniel Bushman (dbushman@manifoldlogic.com)

## Repository

https://github.com/manifoldlogic/claude-code-plugins
