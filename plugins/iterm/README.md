# iTerm Plugin

## Overview

The iTerm plugin provides iTerm2 tab management capabilities for Claude Code, enabling automated terminal tab creation and management from both macOS host environments and Linux containers. This plugin is designed for developers who work in devcontainer-based workflows and need seamless terminal integration.

### Key Features

- **Tab Creation**: Open new iTerm2 tabs programmatically with specified profiles
- **Directory Navigation**: Create tabs pre-navigated to specific directories
- **Command Execution**: Open tabs and execute commands automatically
- **Dual-Mode Support**: Works from both macOS host and Linux containers
- **Profile Integration**: Use custom iTerm2 profiles for different contexts (e.g., "Devcontainer" profile)

## Requirements

### macOS Host Mode

- **iTerm2**: Version 3.4 or later (installed at `/Applications/iTerm.app`)
- **macOS**: Version 11 (Big Sur) or later

### Container Mode

- **SSH Access**: SSH connectivity to `host.docker.internal` from within the container
- **HOST_USER Variable**: Environment variable set to the macOS username in devcontainer.json
- **SSH Keys**: SSH keys mounted and accessible in the container at `~/.ssh/`

### General Requirements

- **Claude Code**: With plugin support enabled
- **Git Repository**: Working within a git repository context

## Installation

Install the iTerm plugin using the Claude Code plugin command:

```
/plugin install iterm
```

Once installed, the plugin skills will be available in your Claude Code sessions.

### Verify Installation

After installation, verify the plugin is loaded:

```
/plugin list
```

You should see `iterm` in the list of installed plugins.

## Profile Setup

For optimal devcontainer workflow integration, create a dedicated iTerm2 profile named "Devcontainer". This profile can be configured to auto-connect to your container environment.

### Creating the Devcontainer Profile

1. **Open iTerm2 Preferences**
   - Launch iTerm2
   - Press `Cmd + ,` or go to iTerm2 > Preferences

2. **Create New Profile**
   - Navigate to the **Profiles** tab
   - Click the **+** button at the bottom left to create a new profile
   - Name the profile: `Devcontainer`

3. **Configure General Tab**
   - **Name**: Ensure it's set to `Devcontainer`
   - **Badge**: (Optional) Set to `container` or similar for visual identification
   - **Command**: Choose one of the following options:

     **Option A: Login Shell (Recommended)**
     - Select "Login shell" - the profile will use your default shell
     - You can manually connect to the container when needed

     **Option B: Auto-Connect Script**
     - Select "Custom Shell" or "Command"
     - Enter a startup command that connects to your container:
       ```bash
       /path/to/.devcontainer/scripts/open-devcontainer.sh || exec $SHELL
       ```
     - This automatically connects to the running devcontainer on tab open

4. **Configure Colors Tab (Optional)**
   - Set a distinctive color scheme to differentiate container tabs from local tabs
   - Suggested: Use a darker background or accent color for container sessions
   - Example: Set background to a dark blue (#1a1a2e) for visual distinction

5. **Configure Window Tab (Optional)**
   - **Columns**: 120 (wider for development work)
   - **Rows**: 40 (taller for log viewing)
   - **Style**: "Normal" or "Full-Height Left/Right of Screen" based on preference

6. **Configure Terminal Tab (Optional)**
   - **Scrollback Lines**: Set to a high value (10000+) for development work
   - **Unlimited scrollback**: Enable for long-running processes

7. **Configure Advanced Tab - Automatic Profile Switching (Optional)**

   Automatic Profile Switching can automatically activate the Devcontainer profile when certain conditions are met.

   - Scroll to the **Automatic Profile Switching** section
   - Add rules based on your setup:

     **Based on Username** (if container has different user):
     - Add rule: `vscode@*` to match the container's default user

     **Based on Hostname**:
     - Add rule matching your container hostname pattern

     **Based on Path**:
     - Add rule: `/workspace/*` to match container workspace paths

### Profile Verification

After creating the profile, verify it works:

1. Open a new iTerm2 tab with the profile:
   - Right-click on tab bar > New Tab > Devcontainer
   - Or use Cmd+Shift+O and type "Devcontainer"

2. If using auto-connect, the tab should connect to your running container

3. Verify the profile appears correctly:
   - The tab should have any custom badge or colors you configured
   - If auto-connect is set, you should be in the container environment

### Using the Profile with Scripts

The iTerm plugin scripts accept a `--profile` or `-p` flag to specify which iTerm2 profile to use:

```bash
# Example: Open tab with Devcontainer profile
open-tab.sh --profile Devcontainer

# Example: Navigate to directory with profile
open-in-dir.sh /workspace/repos/myproject --profile Devcontainer
```

### Environment Variable Configuration

You can set a default profile via environment variable in your devcontainer.json:

```json
{
  "remoteEnv": {
    "ITERM_PROFILE": "Devcontainer",
    "HOST_USER": "your-macos-username"
  }
}
```

This ensures all iTerm tabs opened from the container use the Devcontainer profile by default.

## Usage

### Opening a New Tab

```
Open a new iTerm tab
```

### Opening a Tab in a Specific Directory

```
Open an iTerm tab in the /workspace/repos/myproject directory
```

### Opening a Tab with a Specific Profile

```
Open an iTerm tab using the Devcontainer profile
```

### Running a Command in a New Tab

```
Open an iTerm tab and run npm install
```

### Complex Example

```
Open a new iTerm tab with the Development profile, navigate to /workspace/repos/api-server, and run the test suite
```

## Troubleshooting

### iTerm2 Not Responding

**Problem**: Commands to open tabs time out or fail silently.

**Solution**:
1. Ensure iTerm2 is running
2. Check that iTerm2 has Automation permissions:
   - System Preferences > Security & Privacy > Privacy > Automation
   - Ensure your shell or terminal has permission to control iTerm2
3. Restart iTerm2 if it becomes unresponsive

### Container Mode: SSH Connection Failed

**Problem**: `Permission denied` or `Connection refused` when trying to open tabs from container.

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
4. Check that the SSH key is authorized on the host machine

### Container Mode: HOST_USER Not Set

**Problem**: `HOST_USER environment variable not set` error.

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

### Profile Not Found

**Problem**: `Profile 'Devcontainer' not found` error.

**Solution**:
1. Verify the profile exists in iTerm2 Preferences > Profiles
2. Check the profile name matches exactly (case-sensitive)
3. If the profile was recently created, restart iTerm2

### AppleScript Errors

**Problem**: `execution error` or `not allowed to send keystrokes` errors.

**Solution**:
1. Grant Accessibility permissions:
   - System Preferences > Security & Privacy > Privacy > Accessibility
   - Add Terminal.app or your shell application
2. For container mode, ensure the `osascript` commands can execute via SSH:
   ```bash
   ssh ${HOST_USER}@host.docker.internal "osascript -e 'tell application \"iTerm\" to version'"
   ```

### Tabs Open But Don't Navigate

**Problem**: Tabs open but remain in home directory instead of specified path.

**Solution**:
1. Verify the target directory exists:
   ```bash
   ls -la /path/to/directory
   ```
2. Check for shell initialization issues that might override the working directory
3. Ensure the iTerm2 profile doesn't have a "Send text at start" setting that changes directories

## Skills Reference

This plugin provides the following skill:

| Skill | Description | Documentation |
|-------|-------------|---------------|
| tab-management | Core iTerm2 tab operations (open, navigate, execute) | [SKILL.md](skills/tab-management/SKILL.md) |

## Directory Structure

```text
plugins/iterm/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   └── tab-management/
│       ├── SKILL.md
│       ├── scripts/
│       └── references/
└── README.md
```

## Related

- **worktree-spawn skill**: Uses iTerm tab management for devcontainer worktree workflows
- **open-devcontainer.sh**: Opens iTerm2 tabs connected to devcontainer environments
- **Claude Code Plugin Documentation**: For general plugin installation and management
