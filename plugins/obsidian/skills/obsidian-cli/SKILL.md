---
name: obsidian-cli
description: Manage Obsidian vault notes using obsidian-cli from a devcontainer environment via SSH to macOS host
---

# Obsidian CLI Skill

**Last Updated:** 2025-01-15
**CLI Tool:** obsidian-cli (Yakitrak)

## Overview

The obsidian-cli tool provides command-line access to Obsidian vaults, enabling note creation, search, content retrieval, and vault management without opening the Obsidian GUI application.

This skill enables Claude Code to interact with Obsidian vaults on the macOS host from within a devcontainer environment. Commands are executed via SSH tunneling using the established host-communication pattern.

**Capabilities:**
- Create new notes with specified content and frontmatter
- Search notes by filename or content patterns
- Retrieve note content for analysis or modification
- List and manage vaults
- Move notes between folders
- Open notes in Obsidian (GUI)

## Decision Tree

### Use obsidian-cli skill when:
- User wants to create, read, search, or manage Obsidian notes
- Task involves knowledge management in an Obsidian vault
- User mentions "vault", "obsidian", or "note" in the context of knowledge management
- Need to programmatically access note content from the devcontainer
- Creating notes from code analysis, documentation, or research

### Use alternative approaches when:
- **Direct file operations**: If you already know the exact vault path and just need to read/write markdown files, use the Read/Write tools directly
- **Git-tracked vaults**: For version-controlled vault changes, use git commands
- **Obsidian GUI required**: For commands like `open` that require the Obsidian app to be running

### NOT available over SSH:
- Interactive commands requiring GUI input
- Plugin-specific operations (obsidian-cli works at filesystem level)
- Real-time sync status (Obsidian app feature)

## Prerequisites

### Environment Requirements

- Running inside a devcontainer with SSH access to macOS host
- `HOST_USER` environment variable configured in devcontainer.json
- SSH keys mounted at `~/.ssh/id_ed25519`
- obsidian-cli installed on the macOS host via Homebrew

### Verification Commands

Before using obsidian-cli commands, verify the environment is properly configured:

```bash
# 1. Verify SSH connectivity to host
ssh -o BatchMode=yes -o ConnectTimeout=5 ${HOST_USER}@host.docker.internal "echo OK"

# 2. Verify obsidian-cli is installed on host
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "which obsidian-cli"

# 3. Verify default vault is configured
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli print-default"
```

**If verification fails:**

- **SSH fails**: Check HOST_USER is set in devcontainer.json, rebuild container if needed
- **CLI not found**: Install on host with `brew tap yakitrak/yakitrak && brew install yakitrak/yakitrak/obsidian-cli`
- **No default vault**: Set default with `obsidian-cli set-default "VaultName"`

## SSH Command Pattern

**CRITICAL:** All obsidian-cli commands must be executed via SSH to the macOS host.

### Template

```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli <command> [arguments]"
```

### Pattern Components

| Component | Value | Purpose |
|-----------|-------|---------|
| SSH key | `~/.ssh/id_ed25519` | Authentication to host |
| Host user | `${HOST_USER}` | macOS username from devcontainer.json |
| Host address | `host.docker.internal` | Docker DNS for host machine |
| CLI | `obsidian-cli` | Obsidian CLI tool on host |

### Example Commands

```bash
# Create a note
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli create 'My Note' --content 'Note content here'"

# Search notes
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli search 'keyword'"

# Print note content
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli print 'My Note'"

# List vaults
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli list-vaults"
```

## Shell Escaping (CRITICAL)

**WARNING:** User-provided input (note names, content, search terms) must be properly escaped before inclusion in SSH commands to prevent command injection.

### Special Characters Requiring Attention

The following characters require careful escaping when passed through SSH:
- `'` (single quote)
- `"` (double quote)
- `;` (semicolon)
- `$` (dollar sign)
- `` ` `` (backtick)
- `\` (backslash)
- `|` (pipe)
- `&` (ampersand)

### Safe Escaping Patterns

**For single quotes (recommended for most cases):**

```bash
# Escape single quotes by replacing ' with '\''
escaped="${var//\'/\'\\\'\'}"

# Use in command
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli create '${escaped}' --content 'Safe content'"
```

**For double quotes:**

```bash
# Escape double quotes by replacing " with \"
escaped="${var//\"/\\\"}"

# Use in command (wrap outer command in single quotes)
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal 'obsidian-cli search "'"${escaped}"'"'
```

### Anti-Examples (DO NOT USE)

**DO NOT USE - Direct variable interpolation without escaping:**
```bash
# UNSAFE - DO NOT USE
note="User's Note; rm -rf ~"
ssh ... "obsidian-cli create '${note}'"
# This could execute arbitrary commands!
```

**DO NOT USE - Unescaped backticks:**
```bash
# UNSAFE - DO NOT USE
content="Note about `whoami` user"
ssh ... "obsidian-cli create 'Test' --content '${content}'"
# Backticks will be evaluated as command substitution!
```

**DO NOT USE - Unescaped dollar signs:**
```bash
# UNSAFE - DO NOT USE
note="Cost: $100"
ssh ... "obsidian-cli create '${note}'"
# $100 will be interpreted as variable expansion!
```

### Test Command for Escaping Validation

Use this command to verify escaping is working correctly:

```bash
# Test with potentially dangerous input
note="Test'; echo hacked"
escaped="${note//\'/\'\\\'\'}"
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli create '${escaped}' --content 'Test content'"
# SUCCESS: Should create note literally named "Test'; echo hacked"
# FAILURE: If you see "hacked" printed to terminal, escaping failed
```

### Escaping Best Practices

1. **Always escape user input** - Never trust input directly in commands
2. **Use single-quoted strings** - Single quotes prevent most shell interpretation
3. **Test with special characters** - Verify commands handle edge cases
4. **Escape before building command** - Apply escaping to variables, not after concatenation
5. **Check output for injection signs** - Unexpected output may indicate escaping failure

## Common Workflows

### Create a Note

```bash
# Simple note
title="API Design Decisions"
escaped_title="${title//\'/\'\\\'\'}"
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli create '${escaped_title}' --content '# API Design\n\nDecisions made today...'"

# Note in specific folder
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli create 'Projects/MyProject/Architecture' --content '..content..'"
```

### Search Notes

```bash
# Search by filename
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli search 'architecture'"

# Search in specific vault
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli search 'keyword' --vault 'MyVault'"
```

### Read Note Content

```bash
# Print note content
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli print 'MyNote'"

# Use content in workflow
content=$(ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli print 'MyNote'" 2>/dev/null)
```

### Move a Note

```bash
# Move note to different folder
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli move 'OldLocation/Note' 'NewLocation/Note'"
```

## Error Handling

### Common Errors and Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| `ssh: connect to host ... port 22: Connection refused` | SSH not configured | Verify HOST_USER and SSH keys |
| `command not found: obsidian-cli` | CLI not installed on host | Install via Homebrew |
| `Error: No default vault set` | Default vault not configured | Run `obsidian-cli set-default "VaultName"` on host |
| `Error: Note not found` | Note doesn't exist or wrong path | Check note name and folder path |
| `Error: Vault not found` | Invalid vault name | List vaults with `list-vaults` command |

### Handling Output

```bash
# Capture output and check for errors
output=$(ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli create 'MyNote' --content 'Content'" 2>&1)
if [[ $? -ne 0 ]]; then
    echo "Error: ${output}"
else
    echo "Success: Note created"
fi
```

## Reference

For complete command documentation including all options and parameters, see:
`references/cli-reference.md`

## Related

- **worktree-spawn** - SSH command pattern reference
- **maproom-search** - Documentation-based skill pattern
