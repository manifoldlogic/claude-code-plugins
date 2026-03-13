# cmux Plugin

## Overview

The cmux plugin provides cmux terminal management capabilities for Claude Code, enabling automated workspace, pane, and surface management on a macOS host from within devcontainers via SSH. cmux uses workspaces as its primary organizational unit, with a hierarchy of window > workspace > pane > surface. This plugin is designed for developers who work in devcontainer-based workflows and need programmatic terminal control through the cmux application.

## Requirements

- **socketControlMode set to `allowAll`** -- The default socket access mode blocks SSH-based control. This must be configured before anything else:
  ```bash
  defaults write com.cmuxterm.app socketControlMode -string allowAll
  ```
- **cmux installed and running** on macOS host at `/Applications/cmux.app/Contents/Resources/bin/cmux`
- **Devcontainer with SSH access** to `host.docker.internal`
- **`HOST_USER` environment variable** set in `devcontainer.json` `remoteEnv` (see Configuration below)
- **SSH keys mounted** in the container at `~/.ssh/` and authorized on the macOS host

## Installation

The cmux plugin is registered in the CrewChief marketplace. If you are working within this repository, it is already registered and available.

To verify the plugin is registered:

```bash
jq '.plugins[] | select(.name == "cmux")' .claude-plugin/marketplace.json
```

## Configuration

### socketControlMode (required)

cmux defaults to a restricted socket access mode that blocks SSH-based control. You must change this setting before the plugin can communicate with cmux.

```bash
# Option 1: Command line (recommended)
defaults write com.cmuxterm.app socketControlMode -string allowAll

# Option 2: cmux Settings UI
# Open cmux → Settings → Socket Access Mode → "Allow All"
```

### CMUX_BIN_OVERRIDE (optional)

Override the default cmux binary path (`/Applications/cmux.app/Contents/Resources/bin/cmux`) when cmux is installed in a non-standard location:

```bash
export CMUX_BIN_OVERRIDE="/usr/local/bin/cmux"
```

Or set it in `devcontainer.json`:

```json
"remoteEnv": {
  "CMUX_BIN_OVERRIDE": "/usr/local/bin/cmux"
}
```

### HOST_USER

The `HOST_USER` environment variable tells the plugin which macOS user account to SSH into. Add it to your `devcontainer.json`:

```json
"remoteEnv": {
  "HOST_USER": "${localEnv:USER}"
}
```

Then rebuild the container: F1 > "Dev Containers: Rebuild Container"

## Verify Setup

Run the `cmux-check.sh` script to confirm all prerequisites are met:

```bash
bash plugins/cmux/skills/terminal-management/scripts/cmux-check.sh
```

When all checks pass, you will see output confirming:

- HOST_USER is set
- SSH connectivity to host.docker.internal works
- cmux binary is reachable at the expected path
- socketControlMode is set to allowAll

If the socketControlMode check fails, run the fix command on your macOS host:

```bash
defaults write com.cmuxterm.app socketControlMode -string allowAll
```

Then re-run the check script to confirm.

## Usage

```bash
# Set up for convenience
CMUX="/Applications/cmux.app/Contents/Resources/bin/cmux"
SSH="ssh -o BatchMode=yes -o ConnectTimeout=5 ${HOST_USER}@host.docker.internal"

# Check connectivity
bash plugins/cmux/skills/terminal-management/scripts/cmux-check.sh

# Create a new workspace
$SSH "$CMUX new-workspace"

# Send a command (two steps: type then execute)
$SSH "$CMUX send --workspace workspace:1 'your command'"
$SSH "$CMUX send-key --workspace workspace:1 enter"
```

For the complete command reference, scenarios, and advanced usage, see [SKILL.md](skills/terminal-management/SKILL.md).

## Troubleshooting

| Symptom                          | Likely Cause                                 | Fix                                                                      |
| -------------------------------- | -------------------------------------------- | ------------------------------------------------------------------------ |
| "Access denied" or socket errors | socketControlMode not set to allowAll        | `defaults write com.cmuxterm.app socketControlMode -string allowAll`     |
| `cmux: command not found`        | Binary not in SSH PATH                       | Use full path `/Applications/cmux.app/Contents/Resources/bin/cmux`       |
| HOST_USER not set                | `devcontainer.json` remoteEnv not configured | Add `"HOST_USER": "${localEnv:USER}"` to remoteEnv and rebuild container |
| SSH connection fails             | SSH keys not mounted or wrong user           | Check `~/.ssh/` exists in container and keys are authorized on host      |
| cmux not responding              | cmux app not running on macOS host           | Launch cmux on your macOS host                                           |

## Related

- [SKILL.md](skills/terminal-management/SKILL.md) -- Complete command reference and usage scenarios for cmux terminal management
- [iTerm Plugin](../iterm/README.md) -- Alternative terminal management plugin for iTerm2 users
