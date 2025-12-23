# VS Code Workspace Plugin

VS Code and Cursor workspace configuration management with specialized agent for .code-workspace files.

## Overview

The VS Code Workspace plugin provides comprehensive workspace configuration management for VS Code and Cursor IDEs. Whether you're working with single-folder projects or complex multi-root workspaces, this plugin helps you manage workspace files, configure settings, organize folders, and maintain extension recommendations through conversational commands.

This plugin is designed for developers who want to streamline workspace configuration without manually editing JSON files. It understands the `.code-workspace` file structure, validates changes before applying them, and follows IDE configuration best practices. The plugin works seamlessly with both VS Code and Cursor, as they share the same workspace file format and configuration schema.

Perfect for teams standardizing development environments, developers managing multi-repo projects, or anyone who wants to avoid the tedium of hand-editing workspace configuration files.

## Installation

### Prerequisites

- **Claude Code** - This is a Claude Code plugin
  - Install: [Claude Code Installation Guide](https://docs.claude.ai/code)

### Install Plugin

```bash
# Add marketplace (if not already added)
/plugin marketplace add /workspace/.crewchief/claude-code-plugins

# Install vscode plugin
/plugin install vscode@crewchief
```

After installation, restart Claude Code to activate the plugin.

## Components

### Specialized Agent

#### `workspace-config-specialist`

Expert agent for VS Code and Cursor workspace configuration with comprehensive knowledge of `.code-workspace` file structure and IDE settings management.

**Workspace Management:**
- Add or remove folders from multi-root workspaces
- Configure workspace-level settings that override user preferences
- Manage extension recommendations for team consistency
- Create debug launch configurations
- Define build and test tasks

**Configuration Expertise:**
- Validate JSON syntax and prevent common errors
- Use relative paths for portability across machines
- Apply workspace settings for team-shared configuration
- Understand VS Code settings hierarchy (workspace > user > default)
- Handle both VS Code and Cursor workspace files identically

**Path Management:**
- Validate folder paths before adding to workspace
- Use ${workspaceFolder} variable substitutions
- Handle Windows vs Unix path separators correctly
- Prevent duplicate folder and extension entries

**Best Practices:**
- Keep workspace configuration focused and maintainable
- Document workspace-specific settings and their rationale
- Organize folders logically in multi-root setups
- Recommend only essential extensions

**Example Usage:**
```
@workspace-config-specialist Add the repos/frontend folder to my workspace
```

```
@workspace-config-specialist Configure TypeScript with strict type checking for this workspace
```

```
@workspace-config-specialist Add ESLint and Prettier to recommended extensions
```

### workspace-manager Skill

The `workspace-manager` skill provides comprehensive reference documentation for `.code-workspace` file schema, settings catalog, launch configuration options, and task definition patterns. The workspace-config-specialist agent uses this skill internally for detailed schema information.

## Quick Start

### Read Current Workspace Configuration

Ask Claude to examine your existing workspace setup:

```
@workspace-config-specialist Show me the current workspace configuration
```

The agent will read your `.code-workspace` file and explain the current folders, settings, and extension recommendations.

### Add a Folder to Workspace

Add a new folder to your multi-root workspace:

```
@workspace-config-specialist Add repos/backend to the workspace
```

The agent will:
- Validate the path exists
- Add the folder to the workspace configuration
- Prevent duplicate entries
- Suggest reloading the workspace to apply changes

### Configure Workspace Settings

Set workspace-level settings that apply to all team members:

```
@workspace-config-specialist Set tab size to 4 and enable format on save for this workspace
```

The agent will:
- Add the settings to the workspace configuration
- Explain how workspace settings override user settings
- Maintain existing settings that aren't being modified

### Recommend Extensions

Add extension recommendations to ensure team consistency:

```
@workspace-config-specialist Recommend the ESLint extension
```

The agent will:
- Add "dbaeumer.vscode-eslint" to extension recommendations
- Validate the extension ID format
- Prevent duplicate recommendations

### Create a Launch Configuration

Set up a debug configuration for your project:

```
@workspace-config-specialist Create a Node.js launch configuration for src/index.js
```

The agent will:
- Create a launch configuration with the correct debug adapter
- Set up program path with ${workspaceFolder} variable
- Configure appropriate request type (launch vs attach)

## Common Use Cases

### Adding Folders to Multi-Root Workspace

Multi-root workspaces allow you to work with multiple projects simultaneously in a single IDE window.

**Use Case:** You have a monorepo with frontend, backend, and shared packages that you want to manage together.

**Steps:**

1. **Create or open your workspace file:**
   ```
   @workspace-config-specialist Create a new workspace file at my-project.code-workspace
   ```

2. **Add folders one by one:**
   ```
   @workspace-config-specialist Add repos/frontend to the workspace
   @workspace-config-specialist Add repos/backend to the workspace
   @workspace-config-specialist Add repos/shared-packages to the workspace with display name "Shared"
   ```

3. **Review the configuration:**
   ```
   @workspace-config-specialist Show me the workspace folders
   ```

**Result:** Your workspace now contains three folders, each with its own file explorer section. You can navigate between projects easily and search across all folders simultaneously.

**Example Workspace Structure:**
```json
{
  "folders": [
    { "path": "repos/frontend" },
    { "path": "repos/backend" },
    { "path": "repos/shared-packages", "name": "Shared" }
  ]
}
```

### Configuring Workspace Settings

Workspace settings ensure consistent configuration across your team without requiring each developer to manually update their user settings.

**Use Case:** Your team uses Prettier for code formatting with specific rules, and you want all workspace developers to follow the same formatting standards.

**Steps:**

1. **Configure editor formatting:**
   ```
   @workspace-config-specialist Enable format on save and set tab size to 2 for this workspace
   ```

2. **Add language-specific settings:**
   ```
   @workspace-config-specialist Configure TypeScript to use strict mode in workspace settings
   ```

3. **Set file exclusions:**
   ```
   @workspace-config-specialist Exclude node_modules and dist folders from search
   ```

4. **Review final settings:**
   ```
   @workspace-config-specialist Show me all workspace settings
   ```

**Result:** All team members working in this workspace will automatically use the same formatting rules, TypeScript configuration, and search exclusions.

**Example Settings:**
```json
{
  "settings": {
    "editor.formatOnSave": true,
    "editor.tabSize": 2,
    "typescript.tsdk": "node_modules/typescript/lib",
    "search.exclude": {
      "**/node_modules": true,
      "**/dist": true
    }
  }
}
```

### Managing Extension Recommendations

Extension recommendations prompt team members to install essential extensions when they open the workspace.

**Use Case:** Your project uses ESLint for linting, Prettier for formatting, and Jest for testing. You want to ensure all developers have these extensions installed.

**Steps:**

1. **Add linting and formatting extensions:**
   ```
   @workspace-config-specialist Add ESLint and Prettier extensions to recommendations
   ```

2. **Add testing framework extension:**
   ```
   @workspace-config-specialist Recommend the Jest extension
   ```

3. **Add language-specific extensions:**
   ```
   @workspace-config-specialist Recommend the TypeScript extension pack
   ```

4. **Review recommendations:**
   ```
   @workspace-config-specialist List all recommended extensions
   ```

**Result:** When team members open the workspace, they'll receive prompts to install any missing recommended extensions.

**Example Recommendations:**
```json
{
  "extensions": {
    "recommendations": [
      "dbaeumer.vscode-eslint",
      "esbenp.prettier-vscode",
      "orta.vscode-jest",
      "ms-vscode.vscode-typescript-next"
    ]
  }
}
```

## Best Practices

### Workspace Organization

**Keep It Focused:**
- Include 2-8 folders maximum for usability
- Group related projects logically
- Place the primary project folder first in the list

**Use Meaningful Names:**
- Add display names to clarify folder purposes
- Example: `{ "path": "../shared", "name": "Shared Libraries" }`

**Organize by Function:**
- Group frontend/backend/infrastructure projects
- Separate application code from tooling/scripts
- Keep test fixtures in separate folders if they're large

### Settings Management

**Team vs Personal:**
- Use workspace settings for team-shared configuration (formatting, linting rules)
- Keep user settings for personal preferences (UI theme, font size)
- Document why workspace settings override defaults

**Language-Specific Settings:**
- Use `[javascript]` and `[typescript]` blocks for language-specific rules
- Apply language settings only when they differ from general editor settings

**Avoid Over-Configuration:**
- Only override settings that matter for project consistency
- Don't copy default settings into workspace configuration
- Test settings changes before committing to version control

### Extension Recommendations

**Curate Carefully:**
- Recommend 3-10 essential extensions, no more
- Choose well-maintained, popular extensions
- Avoid recommending extensions for personal preferences

**Document Purpose:**
- Add comments explaining why extensions are recommended
- Note if extensions are required vs optional

**Review Periodically:**
- Remove recommendations for obsolete extensions
- Update extension IDs when publishers change
- Test that recommended extensions still work with current IDE versions

### Configuration Portability

**Use Relative Paths:**
- Use paths relative to workspace file location
- Example: `"repos/frontend"` instead of `"/Users/name/repos/frontend"`

**Variable Substitution:**
- Use `${workspaceFolder}` in launch and task configurations
- Avoid hardcoded absolute paths

**Cross-Platform Compatibility:**
- Test workspace on Windows, macOS, and Linux if needed
- Use forward slashes in paths (VS Code normalizes them)
- Document any platform-specific requirements

## Troubleshooting

### Invalid JSON Syntax

**Symptom:**
```
Workspace file could not be parsed
Error: Unexpected token } in JSON at position 147
```

**Solution:**
The workspace-config-specialist agent validates JSON before writing, but if you've manually edited the file:

1. Ask the agent to validate the workspace file:
   ```
   @workspace-config-specialist Check the workspace file for syntax errors
   ```

2. Common issues:
   - Missing or extra commas
   - Unmatched brackets or braces
   - Unquoted property names
   - Trailing commas (not allowed in standard JSON)

3. The agent will identify the specific issue and fix it.

### Path Not Found Errors

**Symptom:**
```
Folder path does not exist: repos/nonexistent-project
```

**Solution:**

1. The agent validates paths before adding them. If you encounter this error, the path is incorrect or the folder doesn't exist.

2. Check the path relative to the workspace file location:
   ```bash
   # If workspace is at /workspace/my-workspace.code-workspace
   # And you want to add /workspace/repos/frontend
   # The relative path should be: repos/frontend
   ```

3. Ask the agent to verify:
   ```
   @workspace-config-specialist List folders in the current directory
   ```

4. Use absolute paths if relative paths are confusing:
   ```
   @workspace-config-specialist Add /absolute/path/to/project to workspace
   ```

### Settings Not Taking Effect

**Symptom:**
You've configured workspace settings, but they don't seem to apply in the IDE.

**Solution:**

1. **Check Settings Hierarchy:**
   - VS Code applies settings in order: Default → User → Workspace → Folder
   - User settings can be overridden by workspace settings
   - Check if user settings are conflicting

2. **Reload the Workspace:**
   - Some settings require a workspace reload
   - Command: "Developer: Reload Window" (Cmd/Ctrl+R)

3. **Verify Setting Name:**
   - Setting names must be exact (e.g., `editor.tabSize` not `editor.tab-size`)
   - Ask the agent to verify: `@workspace-config-specialist Show workspace settings`

4. **Scope-Specific Settings:**
   - Some settings only apply to specific file types
   - Use language-specific blocks: `"[typescript]": { "editor.tabSize": 4 }`

### IDE Compatibility Issues

**Symptom:**
Workspace file works in VS Code but not in Cursor (or vice versa).

**Solution:**

1. **Verify Compatibility:**
   - Cursor is a VS Code fork with high workspace file compatibility
   - All standard properties (folders, settings, extensions, launch, tasks) work identically

2. **Check Extension IDs:**
   - Ensure extension IDs follow the format: `publisher.extension-name`
   - Both IDEs use the same extension marketplace format

3. **Cursor-Specific Features:**
   - Any Cursor-specific settings are documented in [Cursor documentation](https://docs.cursor.com/)
   - Standard VS Code workspace features work in Cursor without modification

4. **IDE Version:**
   - Ensure both IDEs are up to date
   - Some newer workspace features require recent IDE versions

## Links

- [Repository](https://github.com/manifoldlogic/claude-code-plugins)
- [VS Code Workspace Documentation](https://code.visualstudio.com/docs/editor/workspaces)
- [VS Code Multi-root Workspaces](https://code.visualstudio.com/docs/editor/multi-root-workspaces)
- [VS Code Settings Reference](https://code.visualstudio.com/docs/getstarted/settings)
- [VS Code Extension Recommendations](https://code.visualstudio.com/docs/editor/extension-marketplace#_workspace-recommended-extensions)
- [VS Code Debugging](https://code.visualstudio.com/docs/editor/debugging)
- [VS Code Tasks](https://code.visualstudio.com/docs/editor/tasks)
- [Cursor Documentation](https://docs.cursor.com/)

## Examples

### Basic Single-Folder Workspace

```json
{
  "folders": [
    { "path": "." }
  ],
  "settings": {
    "editor.formatOnSave": true,
    "editor.tabSize": 2
  },
  "extensions": {
    "recommendations": [
      "dbaeumer.vscode-eslint",
      "esbenp.prettier-vscode"
    ]
  }
}
```

### Multi-Root Workspace with Named Folders

```json
{
  "folders": [
    { "path": "packages/frontend", "name": "Frontend" },
    { "path": "packages/backend", "name": "Backend" },
    { "path": "packages/shared", "name": "Shared Libraries" }
  ],
  "settings": {
    "editor.formatOnSave": true,
    "editor.tabSize": 2,
    "search.exclude": {
      "**/node_modules": true,
      "**/dist": true
    }
  }
}
```

### Workspace with Launch Configuration

```json
{
  "folders": [
    { "path": "." }
  ],
  "launch": {
    "version": "0.2.0",
    "configurations": [
      {
        "type": "node",
        "request": "launch",
        "name": "Launch Program",
        "program": "${workspaceFolder}/src/index.js",
        "skipFiles": ["<node_internals>/**"]
      }
    ]
  }
}
```

### Workspace with Build Task

```json
{
  "folders": [
    { "path": "." }
  ],
  "tasks": {
    "version": "2.0.0",
    "tasks": [
      {
        "label": "build",
        "type": "shell",
        "command": "npm run build",
        "group": {
          "kind": "build",
          "isDefault": true
        },
        "presentation": {
          "reveal": "always",
          "panel": "new"
        }
      }
    ]
  }
}
```

### Complete Workspace Configuration

```json
{
  "folders": [
    { "path": "." }
  ],
  "settings": {
    "editor.formatOnSave": true,
    "editor.tabSize": 2,
    "editor.rulers": [80, 120],
    "files.exclude": {
      "**/.git": true,
      "**/node_modules": true
    },
    "search.exclude": {
      "**/dist": true,
      "**/.cache": true
    },
    "[typescript]": {
      "editor.defaultFormatter": "esbenp.prettier-vscode"
    },
    "[javascript]": {
      "editor.defaultFormatter": "esbenp.prettier-vscode"
    }
  },
  "extensions": {
    "recommendations": [
      "dbaeumer.vscode-eslint",
      "esbenp.prettier-vscode",
      "ms-vscode.vscode-typescript-next",
      "orta.vscode-jest"
    ]
  },
  "launch": {
    "version": "0.2.0",
    "configurations": [
      {
        "type": "node",
        "request": "launch",
        "name": "Launch Program",
        "program": "${workspaceFolder}/src/index.js",
        "skipFiles": ["<node_internals>/**"],
        "env": {
          "NODE_ENV": "development"
        }
      },
      {
        "type": "node",
        "request": "launch",
        "name": "Debug Tests",
        "program": "${workspaceFolder}/node_modules/.bin/jest",
        "args": ["--runInBand"],
        "console": "integratedTerminal",
        "internalConsoleOptions": "neverOpen"
      }
    ]
  },
  "tasks": {
    "version": "2.0.0",
    "tasks": [
      {
        "label": "build",
        "type": "shell",
        "command": "npm run build",
        "group": {
          "kind": "build",
          "isDefault": true
        }
      },
      {
        "label": "test",
        "type": "shell",
        "command": "npm test",
        "group": {
          "kind": "test",
          "isDefault": true
        }
      }
    ]
  }
}
```
