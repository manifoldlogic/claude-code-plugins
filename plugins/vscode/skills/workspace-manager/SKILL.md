---
name: workspace-manager
description: Manage VS Code multi-root workspaces including folder configuration, workspace settings, extension recommendations, and launch configurations.
---

# Workspace Manager

Manage VS Code `.code-workspace` files for multi-root workspace configurations.

## When to Use This Skill

| Trigger | Use workspace-manager |
|---------|----------------------|
| User mentions ".code-workspace" files | Yes |
| User wants to add/remove workspace folders | Yes |
| User asks about workspace settings | Yes |
| User needs to configure workspace extensions | Yes |
| User needs launch/debug configurations | Yes |
| User asks about single-folder settings (.vscode/) | No - use standard file editing |
| User wants to modify user/global settings | No - workspace-specific only |

### Use workspace-manager when:
- Creating or modifying `.code-workspace` files
- Adding/removing folders in multi-root workspaces
- Configuring workspace-level settings (overrides folder settings)
- Managing extension recommendations per workspace
- Setting up debug/launch configurations for the workspace

### Use standard editing when:
- Working with single-folder `.vscode/settings.json`
- Modifying user or global VS Code settings
- Simple JSON edits not requiring schema validation

## Quick Reference

### Add Folder
Add a folder to the workspace's `folders` array:

```json
{
  "folders": [
    {
      "path": "../existing-folder"
    },
    {
      "name": "Custom Name",
      "path": "/absolute/path/to/folder"
    }
  ]
}
```

**Note**: Paths can be relative to the workspace file or absolute.

### Remove Folder
Identify and remove the folder object from the `folders` array by matching the `path` property.

### Configure Settings
Set workspace-level settings in the `settings` object:

```json
{
  "settings": {
    "editor.formatOnSave": true,
    "typescript.tsdk": "node_modules/typescript/lib"
  }
}
```

**Note**: Workspace settings override folder-level settings.

### Add Extension Recommendation
Add extensions to the `extensions.recommendations` array:

```json
{
  "extensions": {
    "recommendations": [
      "dbaeumer.vscode-eslint",
      "esbenp.prettier-vscode"
    ]
  }
}
```

**Format**: Publisher ID + extension name (e.g., `publisher.extension-name`)

### Create Launch Configuration
Add debug configurations to the `launch` object:

```json
{
  "launch": {
    "version": "0.2.0",
    "configurations": [
      {
        "type": "node",
        "request": "launch",
        "name": "Debug App",
        "program": "${workspaceFolder}/src/index.js"
      }
    ]
  }
}
```

**Note**: For complex launch configurations, reference the schema documentation for all available options.

## Structure Overview

A typical `.code-workspace` file contains:

```json
{
  "folders": [],           // Required: array of folder objects
  "settings": {},          // Optional: workspace settings
  "extensions": {},        // Optional: extension recommendations
  "launch": {},           // Optional: debug configurations
  "tasks": {}             // Optional: task configurations
}
```

## Links

- [Workspace Schema Reference](references/workspace-schema.md) - Complete schema documentation
- [Settings Reference](references/settings-reference.md) - Available workspace settings
