# Obsidian Plugin

## Overview

The Obsidian plugin enables Obsidian vault management from within a devcontainer environment, powered by the [obsidian-cli](https://github.com/Yakitrak/obsidian-cli) command-line tool. It provides seamless note creation, search, and management capabilities by executing commands on the macOS host via SSH. With this plugin, you can interact with your Obsidian vaults without leaving your development environment.

### Key Features

- **Note Management**: Create, read, update, and delete notes in your Obsidian vault
- **Search**: Find notes by name or search within note content
- **Daily Notes**: Create and access daily notes with automatic date-based naming
- **Frontmatter Operations**: Set and update YAML frontmatter fields in notes
- **Multi-Vault Support**: Work with multiple vaults using the default vault or specifying vaults explicitly
- **SSH Integration**: Secure communication between container and macOS host

## Prerequisites

Before using the Obsidian plugin, ensure the following are configured:

### 1. obsidian-cli on macOS Host

Install obsidian-cli on your macOS host machine using Homebrew:

```bash
# Install obsidian-cli
brew tap yakitrak/yakitrak
brew install yakitrak/yakitrak/obsidian-cli

# Verify installation
obsidian-cli --version
```

### 2. Configure Default Vault

Set your default Obsidian vault so commands work without specifying the vault each time:

```bash
# List available vaults
obsidian-cli list-vaults

# Set the default vault
obsidian-cli set-default "My Vault"

# Verify default vault
obsidian-cli print-default
```

### 3. SSH Access from Container to Host

SSH connectivity must be configured between the container and macOS host:

```bash
# From within the container, test SSH connectivity
ssh -o BatchMode=yes -o ConnectTimeout=5 ${HOST_USER}@host.docker.internal "echo OK"
```

If this fails, see the [SSH Configuration](#ssh-configuration) section below.

### 4. HOST_USER Environment Variable

The `HOST_USER` environment variable must be set in your devcontainer.json to identify the macOS username:

```json
{
  "remoteEnv": {
    "HOST_USER": "your-macos-username"
  }
}
```

After adding this, rebuild your container: F1 > "Dev Containers: Rebuild Container"

### Verification Checklist

Run these commands from within the container to verify your setup:

```bash
# 1. Verify HOST_USER is set
echo "HOST_USER: ${HOST_USER}"

# 2. Test SSH connectivity
ssh -o BatchMode=yes ${HOST_USER}@host.docker.internal "echo SSH OK"

# 3. Verify obsidian-cli is available on host
ssh ${HOST_USER}@host.docker.internal "which obsidian-cli"

# 4. Check default vault is configured
ssh ${HOST_USER}@host.docker.internal "obsidian-cli print-default"
```

## Installation

Install the Obsidian plugin using the Claude Code plugin command:

```
/plugin install obsidian@crewchief
```

Once installed, the plugin skills will be available in your Claude Code sessions.

### Verify Installation

After installation, verify the plugin is loaded:

```
/plugin list
```

You should see `obsidian` in the list of installed plugins.

## Security Recommendations

The Obsidian plugin executes commands on your macOS host via SSH, which requires careful security consideration.

### SSH Key Security

- **Never commit SSH keys**: Ensure `.ssh/` directories are in `.gitignore`
- **Use proper permissions**: SSH private keys must have 600 permissions
  ```bash
  chmod 600 ~/.ssh/id_ed25519
  ```
- **Use ssh-agent**: Consider using ssh-agent for key management instead of exposing keys directly
- **Use dedicated keys**: Consider using a dedicated SSH key pair for container-to-host communication

### SSH Key Mounting in Devcontainer

Mount SSH keys securely in your devcontainer.json:

```json
{
  "mounts": [
    "source=${localEnv:HOME}/.ssh/id_ed25519,target=/home/vscode/.ssh/id_ed25519,type=bind,readonly"
  ]
}
```

Key points:
- Mount keys as read-only when possible
- Only mount the specific keys needed, not the entire `.ssh` directory
- Ensure the mounted key has correct permissions inside the container

### HOST_USER Environment Variable

The `HOST_USER` variable determines which user account SSH connects to on your macOS host:

- Set this only in `devcontainer.json`, not in shell scripts or code
- This gives the container the same access as your macOS user account
- Be aware of what vaults and files your macOS user can access

### Vault Access (Principle of Least Privilege)

- Configure a default vault to limit the scope of operations
- obsidian-cli validates vault paths internally, preventing arbitrary file access
- Consider which vaults should be accessible and set appropriate file permissions
- Note content transits through the SSH connection (encrypted) but is not cached in the container

### Data Protection

- All communication between container and host is encrypted via SSH
- No note content or vault data is persistently stored in the container
- SSH keys stored on mounted volumes should have appropriate permissions
- Consider vault-level encryption for highly sensitive notes

## Quick Start

After completing the prerequisites, you can start using the plugin immediately.

### Create a Note

```
Create a note called "Meeting Notes" with the content "Discussed project timeline"
```

### Search for Notes

```
Search for notes containing "project" in the title
```

### Read a Note

```
Show me the contents of the note "Meeting Notes"
```

### Create Today's Daily Note

```
Create or open today's daily note
```

### Update Frontmatter

```
Add a tag "important" to the frontmatter of "Meeting Notes"
```

## Troubleshooting

### SSH Connection Failed

**Problem**: `Permission denied` or `Connection refused` when executing commands.

**Solution**:
1. Verify `HOST_USER` is set correctly:
   ```bash
   echo $HOST_USER
   ```
2. Test SSH connectivity:
   ```bash
   ssh -o BatchMode=yes ${HOST_USER}@host.docker.internal "echo OK"
   ```
3. Ensure SSH keys are mounted in the container:
   ```bash
   ls -la ~/.ssh/
   ```
4. Verify the SSH key is authorized on the host:
   ```bash
   # On macOS host, check authorized_keys
   cat ~/.ssh/authorized_keys
   ```

### HOST_USER Not Set

**Problem**: Commands fail with `HOST_USER environment variable not set` error.

**Solution**:
Add `HOST_USER` to your devcontainer.json:
```json
{
  "remoteEnv": {
    "HOST_USER": "your-macos-username"
  }
}
```
Then rebuild the container: F1 > "Dev Containers: Rebuild Container"

### obsidian-cli Not Found

**Problem**: `obsidian-cli: command not found` when running commands.

**Solution**:
1. Verify obsidian-cli is installed on the macOS host:
   ```bash
   # On macOS host
   which obsidian-cli
   ```
2. If not installed, install via Homebrew:
   ```bash
   brew tap yakitrak/yakitrak
   brew install yakitrak/yakitrak/obsidian-cli
   ```
3. Ensure the CLI is in the PATH for non-interactive SSH sessions. Add to `~/.zshrc` or `~/.bash_profile` on the host:
   ```bash
   export PATH="/opt/homebrew/bin:$PATH"
   ```

### Default Vault Not Configured

**Problem**: Commands fail with `no default vault configured` error.

**Solution**:
1. List available vaults on the macOS host:
   ```bash
   ssh ${HOST_USER}@host.docker.internal "obsidian-cli list-vaults"
   ```
2. Set the default vault:
   ```bash
   ssh ${HOST_USER}@host.docker.internal "obsidian-cli set-default 'Your Vault Name'"
   ```
3. Verify the default vault:
   ```bash
   ssh ${HOST_USER}@host.docker.internal "obsidian-cli print-default"
   ```

### Interactive Commands Not Working

**Problem**: Search commands with fuzzy finder don't work.

**Solution**:
Interactive modes (fuzzy finder) in obsidian-cli are not available over non-interactive SSH sessions. Use non-interactive alternatives:
- For searching note names: Use `obsidian-cli search "pattern"` with non-interactive output
- For searching content: Combine with `grep` for filtering results
- Request specific note names when possible instead of interactive browsing

### SSH Key Permission Issues

**Problem**: SSH fails with `Permissions for 'id_ed25519' are too open` error.

**Solution**:
Fix the key permissions inside the container:
```bash
chmod 600 ~/.ssh/id_ed25519
```

If the key is mounted read-only and you cannot change permissions, you may need to copy it:
```bash
cp ~/.ssh/id_ed25519 ~/.ssh/id_ed25519_copy
chmod 600 ~/.ssh/id_ed25519_copy
# Use the copy for SSH operations
```

### Note Names with Special Characters

**Problem**: Commands fail when note names contain quotes or special characters.

**Solution**:
Shell escaping is required for special characters. The plugin documentation includes escaping patterns, but generally:
- Avoid using special characters (`'`, `"`, `;`, `$`, backticks) in note names when possible
- If special characters are needed, ensure proper escaping is applied
- Test with a simple note name first to verify connectivity

## SSH Configuration

### Setting Up SSH Access

If SSH is not yet configured between your container and macOS host:

1. **Generate SSH key** (if needed):
   ```bash
   ssh-keygen -t ed25519 -C "devcontainer"
   ```

2. **Add public key to macOS authorized_keys**:
   ```bash
   # On macOS host
   cat /path/to/id_ed25519.pub >> ~/.ssh/authorized_keys
   ```

3. **Mount the private key in devcontainer.json**:
   ```json
   {
     "mounts": [
       "source=${localEnv:HOME}/.ssh/id_ed25519,target=/home/vscode/.ssh/id_ed25519,type=bind,readonly"
     ]
   }
   ```

4. **Ensure sshd is running on macOS**:
   - System Preferences > Sharing > Enable "Remote Login"
   - Or enable via command line: `sudo systemsetup -setremotelogin on`

## Skills Reference

This plugin provides the following skill:

| Skill | Description | Documentation |
|-------|-------------|---------------|
| obsidian-cli | Obsidian vault operations via SSH | [SKILL.md](skills/obsidian-cli/SKILL.md) |

## Directory Structure

```text
plugins/obsidian/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   └── obsidian-cli/
│       ├── SKILL.md
│       └── references/
│           └── cli-reference.md
└── README.md
```

## Related

- **obsidian-cli**: [GitHub Repository](https://github.com/Yakitrak/obsidian-cli) - The underlying CLI tool
- **iTerm Plugin**: Uses similar SSH patterns for host communication
- **worktree-spawn skill**: Another skill using SSH to macOS host
