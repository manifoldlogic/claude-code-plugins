---
name: plugin-marketplace-registration
description: Register a plugin in marketplace.json for plugin discovery and loading by the CrewChief framework
origin: ISKIM
created: 2026-02-08
tags: [plugin-system, configuration, marketplace]
---

# Plugin Marketplace Registration

## Overview

This skill documents how to register a plugin in the `.claude-plugin/marketplace.json` file, which is the plugin discovery mechanism for the CrewChief plugin framework. Without marketplace registration, a plugin will not be discoverable or loadable, even if fully implemented.

The marketplace.json file contains a `plugins` array where each entry defines a plugin's name, source location, and description. This skill covers the standard registration format and validation steps.

## When to Use

Use this skill when:

- Creating a new plugin and need to make it discoverable
- A plugin exists but is not loading (check if marketplace registration is missing)
- Updating a plugin's description in the marketplace
- Understanding the plugin discovery mechanism

## Pattern/Procedure

### Standard Registration Format

Each plugin entry in `.claude-plugin/marketplace.json` follows this JSON structure:

```json
{
  "name": "plugin-name",
  "source": "./plugins/plugin-name",
  "description": "Brief description of plugin capabilities"
}
```

**Field requirements:**

- **name**: Plugin identifier (string, lowercase, hyphens allowed, must match plugin.json name)
- **source**: Relative path to plugin directory from repo root (always `./plugins/{name}`)
- **description**: One-line summary of plugin capabilities (string, under 200 characters)

### Registration Steps

1. **Open marketplace.json:**
   ```bash
   # Located at repo root
   open .claude-plugin/marketplace.json
   ```

2. **Locate the plugins array:**
   ```json
   {
     "name": "crewchief",
     "plugins": [
       // existing plugin entries
     ]
   }
   ```

3. **Add new entry at end of array:**
   ```json
   {
     "name": "crewchief",
     "plugins": [
       // ... existing plugins ...
       {
         "name": "your-plugin",
         "source": "./plugins/your-plugin",
         "description": "Your plugin description here"
       }
     ]
   }
   ```

   **Note:** Array order is not significant for loading. Appending at the end minimizes diff noise.

4. **Validate JSON syntax:**
   ```bash
   jq . .claude-plugin/marketplace.json > /dev/null && echo "Valid JSON" || echo "Invalid JSON"
   ```

5. **Verify plugin.json exists at source location:**
   ```bash
   test -f "plugins/your-plugin/.claude-plugin/plugin.json" && echo "plugin.json exists" || echo "plugin.json missing"
   ```

6. **Marketplace Version Bump (Required)**

   After modifying marketplace.json, bump the marketplace version:

   **Determine the bump type:**

   | Change Type | Bump | Example |
   |-------------|------|---------|
   | Description update, metadata fix | PATCH (0.0.x) | 0.2.0 -> 0.2.1 |
   | New plugin registered | MINOR (0.x.0) | 0.2.1 -> 0.3.0 |
   | Breaking structural change | MAJOR (x.0.0) | 0.3.0 -> 1.0.0 |

   **Default to PATCH** unless a new plugin is being added (MINOR) or the marketplace structure changes (MAJOR).

   **Edit the version field in `.claude-plugin/marketplace.json`:**
   ```json
   {
     "version": "0.2.1"  // <-- bump this
   }
   ```

   **Verify the bump:**
   ```bash
   jq -r '.version' .claude-plugin/marketplace.json
   ```

### Complete Example

From ISKIM ticket (adding iTerm plugin):

**Before (marketplace.json lines 8-48):**
```json
{
  "name": "crewchief",
  "plugins": [
    {"name": "github-actions", "source": "./plugins/github-actions", "description": "..."},
    {"name": "claude-code-dev", "source": "./plugins/claude-code-dev", "description": "..."},
    {"name": "sdd", "source": "./plugins/sdd", "description": "..."},
    {"name": "maproom", "source": "./plugins/maproom", "description": "..."},
    {"name": "obsidian", "source": "./plugins/obsidian", "description": "..."},
    {"name": "worktree", "source": "./plugins/worktree", "description": "..."},
    {"name": "game-design", "source": "./plugins/game-design", "description": "..."},
    {"name": "vscode", "source": "./plugins/vscode", "description": "..."}
  ]
}
```

**After (iTerm added):**
```json
{
  "name": "crewchief",
  "plugins": [
    {"name": "github-actions", "source": "./plugins/github-actions", "description": "..."},
    {"name": "claude-code-dev", "source": "./plugins/claude-code-dev", "description": "..."},
    {"name": "sdd", "source": "./plugins/sdd", "description": "..."},
    {"name": "maproom", "source": "./plugins/maproom", "description": "..."},
    {"name": "obsidian", "source": "./plugins/obsidian", "description": "..."},
    {"name": "worktree", "source": "./plugins/worktree", "description": "..."},
    {"name": "game-design", "source": "./plugins/game-design", "description": "..."},
    {"name": "vscode", "source": "./plugins/vscode", "description": "..."},
    {"name": "iterm", "source": "./plugins/iterm", "description": "iTerm2 tab and pane management for macOS host and Linux container environments"}
  ]
}
```

### Validation Checklist

Before committing marketplace.json changes:

- [ ] JSON syntax is valid (use `jq .` to verify)
- [ ] Plugin name matches the name field in `plugins/{name}/.claude-plugin/plugin.json`
- [ ] Source path is correct relative path: `./plugins/{name}`
- [ ] Description is under 200 characters and clearly describes capabilities
- [ ] Plugin directory exists at specified source path
- [ ] Plugin.json exists at `{source}/.claude-plugin/plugin.json`
- [ ] No trailing commas or syntax errors in array
- [ ] Marketplace version bumped per Marketplace Version Bump step above

## Examples

### Example 1: iTerm Plugin Registration (ISKIM ticket)

**Task:** Register the iTerm plugin in marketplace.json

**Entry added:**
```json
{
  "name": "iterm",
  "source": "./plugins/iterm",
  "description": "iTerm2 tab and pane management for macOS host and Linux container environments"
}
```

**Validation:**
```bash
# Check JSON syntax
jq . .claude-plugin/marketplace.json

# Verify plugin.json exists
test -f plugins/iterm/.claude-plugin/plugin.json && echo "OK"

# Verify name matches
jq -r '.name' plugins/iterm/.claude-plugin/plugin.json
# Output: iterm
```

### Example 2: Checking Current Marketplace Plugins

```bash
# List all registered plugins
jq -r '.plugins[].name' .claude-plugin/marketplace.json

# Count registered plugins
jq '.plugins | length' .claude-plugin/marketplace.json

# Find specific plugin
jq '.plugins[] | select(.name == "iterm")' .claude-plugin/marketplace.json
```

## References

- Ticket: ISKIM (iTerm marketplace registration)
- Related files:
  - `.claude-plugin/marketplace.json` (marketplace configuration)
  - `plugins/{name}/.claude-plugin/plugin.json` (plugin metadata)
- Related skills:
  - skill-md-structure (SKILL.md documentation structure)
