# VS Code Workspace Schema Reference

## Overview

The `.code-workspace` file is a JSON configuration file that defines a VS Code multi-root workspace. It specifies which folders to include, workspace-level settings, extension recommendations, debug configurations, and task definitions. This reference documents the complete schema structure, validation rules, and provides working examples.

---

## Schema Properties

### 1. folders (Required)

The `folders` array defines which directories are included in the workspace. This is the only required property in a workspace file.

**Type**: Array of folder objects

**Required**: Yes (must contain at least one folder)

**Structure**:
```json
{
  "path": "string (required)",
  "name": "string (optional)"
}
```

**Properties**:
- **path** (required): Relative or absolute path to the folder
  - Relative paths are recommended for portability
  - Relative paths are resolved from the workspace file location
  - Absolute paths tie workspace to specific machine locations
- **name** (optional): Custom display name for the folder in VS Code Explorer
  - Overrides the default folder name
  - Useful for clarifying folder purpose or distinguishing similar names

**Example**:
```json
{
  "folders": [
    {
      "path": "../project-backend",
      "name": "Backend API"
    },
    {
      "path": "../project-frontend",
      "name": "React Frontend"
    },
    {
      "path": "/Users/dev/shared-utils"
    }
  ]
}
```

**Notes**:
- At least one folder must be specified
- Duplicate paths are allowed but not recommended
- Non-existent paths will show as unavailable in VS Code

---

### 2. settings (Optional)

Workspace-level settings that apply across all folders in the workspace. These override user settings but are overridden by folder-specific settings.

**Type**: Object (nested key-value pairs)

**Required**: No

**Structure**: Flat or nested object matching VS Code settings schema

**Example**:
```json
{
  "settings": {
    "files.autoSave": "afterDelay",
    "files.autoSaveDelay": 1000,
    "editor.formatOnSave": true,
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "editor.tabSize": 2,
    "terminal.integrated.defaultProfile.linux": "zsh",
    "[typescript]": {
      "editor.defaultFormatter": "esbenp.prettier-vscode"
    },
    "[python]": {
      "editor.formatOnSave": true,
      "editor.defaultFormatter": "ms-python.black-formatter"
    }
  }
}
```

**Notes**:
- **Important Constraint**: Only resource-scoped settings (file/folder level) are applied in multi-root workspaces
- Editor-wide UI settings (e.g., `window.zoomLevel`, `workbench.colorTheme`) are ignored
- Language-specific settings use `[languageId]` syntax
- For complete settings reference, see [settings-reference.md](./settings-reference.md)
- Folder-specific settings in `.vscode/settings.json` take precedence

---

### 3. extensions (Optional)

Defines workspace-recommended extensions that VS Code will prompt users to install.

**Type**: Object containing recommendations array

**Required**: No

**Structure**:
```json
{
  "recommendations": ["string array of extension IDs"]
}
```

**Extension ID Format**: `publisher.extension` (e.g., `esbenp.prettier-vscode`)

**Example**:
```json
{
  "extensions": {
    "recommendations": [
      "esbenp.prettier-vscode",
      "dbaeumer.vscode-eslint",
      "ms-python.python",
      "ms-python.black-formatter",
      "ms-azuretools.vscode-docker",
      "eamodio.gitlens",
      "github.copilot"
    ]
  }
}
```

**Notes**:
- Extension IDs are case-insensitive but conventionally lowercase
- Find extension IDs on VS Code Marketplace or via command palette: "Extensions: Show Recommended Extensions"
- Users receive a notification to install missing recommended extensions
- Extensions are not automatically installed (user must approve)

---

### 4. launch (Optional)

Workspace-level debug configurations for running and debugging applications. Supports multiple configurations and compound launches.

**Type**: Object containing configurations array and optional compounds array

**Required**: No

**Structure**:
```json
{
  "configurations": [
    {
      "type": "string (debugger type)",
      "request": "launch | attach",
      "name": "string (display name)",
      // ... debugger-specific properties
    }
  ],
  "compounds": [
    {
      "name": "string",
      "configurations": ["string array of config names"]
    }
  ]
}
```

**Example**:
```json
{
  "launch": {
    "version": "0.2.0",
    "configurations": [
      {
        "type": "node",
        "request": "launch",
        "name": "Launch Backend",
        "program": "${workspaceFolder:Backend API}/src/server.js",
        "cwd": "${workspaceFolder:Backend API}",
        "env": {
          "NODE_ENV": "development"
        }
      },
      {
        "type": "chrome",
        "request": "launch",
        "name": "Launch Frontend",
        "url": "http://localhost:3000",
        "webRoot": "${workspaceFolder:React Frontend}/src"
      },
      {
        "type": "python",
        "request": "launch",
        "name": "Python: Current File",
        "program": "${file}",
        "console": "integratedTerminal"
      }
    ],
    "compounds": [
      {
        "name": "Full Stack",
        "configurations": ["Launch Backend", "Launch Frontend"],
        "stopAll": true
      }
    ]
  }
}
```

**Notes**:
- **Critical**: Multi-root workspaces require folder-scoped variables: `${workspaceFolder:FolderName}`
- Standard `${workspaceFolder}` is ambiguous in multi-root and should be avoided
- Each debugger type (node, chrome, python, etc.) has specific required properties
- For complete launch configuration schemas, see [VS Code Debugging Documentation](https://code.visualstudio.com/docs/editor/debugging)
- Compound configurations allow launching multiple debuggers simultaneously
- `stopAll` in compounds stops all debuggers when one stops

---

### 5. tasks (Optional)

Workspace-level task definitions for running build scripts, tests, linters, and other automation.

**Type**: Object containing version and tasks array

**Required**: No

**Structure**:
```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "string (required)",
      "type": "shell | process (required)",
      "command": "string (required)",
      // ... additional task properties
    }
  ]
}
```

**Task Types**:
- **shell**: Command executed in shell (bash, zsh, cmd, PowerShell)
- **process**: Command executed as direct process (no shell interpretation)

**Common Properties**:
- **label** (required): Task display name in UI
- **type** (required): `shell` or `process`
- **command** (required): Command to execute
- **args** (optional): Array of command arguments
- **group** (optional): Task category (`build`, `test`, or custom)
- **problemMatcher** (optional): Parser for error/warning output
- **presentation** (optional): Terminal display behavior
- **options** (optional): Execution options (cwd, env, shell)
- **dependsOn** (optional): Tasks that must run first
- **isBackground** (optional): Long-running background task flag

**Example**:
```json
{
  "tasks": {
    "version": "2.0.0",
    "tasks": [
      {
        "label": "Build Backend",
        "type": "shell",
        "command": "npm",
        "args": ["run", "build"],
        "options": {
          "cwd": "${workspaceFolder:Backend API}"
        },
        "group": {
          "kind": "build",
          "isDefault": true
        },
        "problemMatcher": ["$tsc"]
      },
      {
        "label": "Test Frontend",
        "type": "shell",
        "command": "npm",
        "args": ["test", "--", "--watchAll=false"],
        "options": {
          "cwd": "${workspaceFolder:React Frontend}"
        },
        "group": "test",
        "presentation": {
          "reveal": "always",
          "panel": "new"
        }
      },
      {
        "label": "Run Dev Server",
        "type": "process",
        "command": "python",
        "args": ["-m", "uvicorn", "main:app", "--reload"],
        "options": {
          "cwd": "${workspaceFolder:Backend API}",
          "env": {
            "PYTHONPATH": "${workspaceFolder:Backend API}/src"
          }
        },
        "isBackground": true,
        "problemMatcher": {
          "pattern": {
            "regexp": "^ERROR",
            "file": 1,
            "line": 2,
            "message": 3
          },
          "background": {
            "activeOnStart": true,
            "beginsPattern": "Started server process",
            "endsPattern": "Application startup complete"
          }
        }
      },
      {
        "label": "Full Build",
        "dependsOn": ["Build Backend", "Test Frontend"],
        "problemMatcher": []
      }
    ]
  }
}
```

**Notes**:
- Only `shell` and `process` types are supported in workspace files
- Use folder-scoped variables in multi-root workspaces: `${workspaceFolder:FolderName}`
- Problem matchers parse output for errors/warnings (see [Tasks Documentation](https://code.visualstudio.com/docs/editor/tasks))
- Background tasks require proper `problemMatcher.background` configuration
- `dependsOn` creates compound tasks that run in sequence or parallel

---

## Validation Rules

### Structural Requirements

1. **Valid JSON Format**
   - File must be valid JSON
   - Comments are supported (VS Code strips them on read)
   - Trailing commas are not allowed in standard JSON

2. **folders Array**
   - Must be present (required property)
   - Must contain at least one folder object
   - Each folder must have a `path` property
   - Empty folders array is invalid

3. **Extension IDs**
   - Must use format: `publisher.extension`
   - Case-insensitive but conventionally lowercase
   - Must match published extension identifiers

4. **Variable Scoping**
   - Multi-root workspaces require folder-scoped variables
   - Use `${workspaceFolder:FolderName}` not `${workspaceFolder}`
   - Folder name must match the `name` property or default folder name

### Settings Constraints

5. **Settings Scope**
   - Only resource-scoped settings apply in multi-root workspaces
   - Editor-wide UI settings are ignored
   - Window-level settings (themes, zoom) have no effect

6. **Task Types**
   - Only `shell` and `process` types allowed in workspace tasks
   - Other task types (npm, gulp, etc.) must be in folder `.vscode/tasks.json`

7. **Launch Configurations**
   - Each configuration must have `type`, `request`, and `name`
   - Debugger-specific properties vary by type
   - Invalid configurations are silently ignored

### Path Handling

8. **Relative Paths**
   - Resolved relative to workspace file location
   - Use forward slashes (/) or OS-appropriate separators
   - Backslashes must be escaped in JSON (`\\`)

9. **Absolute Paths**
   - Reduce workspace portability
   - Valid but discouraged for shared workspaces
   - Use platform-specific formats (Windows: `C:\\`, Unix: `/home/`)

### Best Practices

10. **Workspace Portability**
    - Prefer relative paths for cross-platform sharing
    - Avoid absolute paths tied to specific machines
    - Use environment variables for machine-specific values

11. **Folder Organization**
    - Order folders logically (e.g., backend before frontend)
    - Use descriptive `name` properties for clarity
    - Avoid deeply nested relative paths

---

## Complete Example

This example demonstrates a full-featured workspace configuration with all major properties:

```json
{
  "folders": [
    {
      "path": "../monorepo/packages/api",
      "name": "API Server"
    },
    {
      "path": "../monorepo/packages/web",
      "name": "Web Client"
    },
    {
      "path": "../monorepo/packages/shared",
      "name": "Shared Libraries"
    }
  ],
  "settings": {
    "files.autoSave": "afterDelay",
    "files.autoSaveDelay": 1000,
    "editor.formatOnSave": true,
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "editor.tabSize": 2,
    "editor.rulers": [80, 120],
    "files.exclude": {
      "**/.git": true,
      "**/node_modules": true,
      "**/__pycache__": true
    },
    "[typescript]": {
      "editor.defaultFormatter": "esbenp.prettier-vscode",
      "editor.codeActionsOnSave": {
        "source.organizeImports": "explicit"
      }
    },
    "[python]": {
      "editor.formatOnSave": true,
      "editor.defaultFormatter": "ms-python.black-formatter"
    },
    "terminal.integrated.defaultProfile.linux": "zsh",
    "typescript.tsdk": "node_modules/typescript/lib"
  },
  "extensions": {
    "recommendations": [
      "esbenp.prettier-vscode",
      "dbaeumer.vscode-eslint",
      "ms-python.python",
      "ms-python.black-formatter",
      "ms-vscode.vscode-typescript-next",
      "eamodio.gitlens",
      "github.copilot",
      "ms-azuretools.vscode-docker"
    ]
  },
  "launch": {
    "version": "0.2.0",
    "configurations": [
      {
        "type": "node",
        "request": "launch",
        "name": "Launch API Server",
        "program": "${workspaceFolder:API Server}/src/index.ts",
        "preLaunchTask": "Build API",
        "outFiles": ["${workspaceFolder:API Server}/dist/**/*.js"],
        "cwd": "${workspaceFolder:API Server}",
        "env": {
          "NODE_ENV": "development",
          "PORT": "3001"
        },
        "sourceMaps": true,
        "console": "integratedTerminal"
      },
      {
        "type": "chrome",
        "request": "launch",
        "name": "Launch Web Client",
        "url": "http://localhost:3000",
        "webRoot": "${workspaceFolder:Web Client}/src",
        "sourceMaps": true,
        "preLaunchTask": "Start Dev Server"
      },
      {
        "type": "node",
        "request": "attach",
        "name": "Attach to API",
        "port": 9229,
        "restart": true,
        "skipFiles": ["<node_internals>/**"]
      }
    ],
    "compounds": [
      {
        "name": "Full Stack Debug",
        "configurations": ["Launch API Server", "Launch Web Client"],
        "stopAll": true,
        "preLaunchTask": "Install Dependencies"
      }
    ]
  },
  "tasks": {
    "version": "2.0.0",
    "tasks": [
      {
        "label": "Install Dependencies",
        "type": "shell",
        "command": "npm",
        "args": ["install"],
        "options": {
          "cwd": "${workspaceFolder:API Server}"
        },
        "presentation": {
          "reveal": "always",
          "panel": "shared"
        },
        "problemMatcher": []
      },
      {
        "label": "Build API",
        "type": "shell",
        "command": "npm",
        "args": ["run", "build"],
        "options": {
          "cwd": "${workspaceFolder:API Server}"
        },
        "group": {
          "kind": "build",
          "isDefault": true
        },
        "problemMatcher": ["$tsc"],
        "presentation": {
          "reveal": "always",
          "panel": "shared"
        }
      },
      {
        "label": "Start Dev Server",
        "type": "shell",
        "command": "npm",
        "args": ["run", "dev"],
        "options": {
          "cwd": "${workspaceFolder:Web Client}",
          "env": {
            "BROWSER": "none"
          }
        },
        "isBackground": true,
        "problemMatcher": {
          "pattern": {
            "regexp": "ERROR in (.*)",
            "file": 1
          },
          "background": {
            "activeOnStart": true,
            "beginsPattern": "webpack.*compiling",
            "endsPattern": "webpack.*compiled"
          }
        }
      },
      {
        "label": "Test All",
        "type": "shell",
        "command": "npm",
        "args": ["test", "--", "--passWithNoTests"],
        "options": {
          "cwd": "${workspaceFolder:API Server}"
        },
        "group": "test",
        "presentation": {
          "reveal": "always",
          "panel": "dedicated"
        },
        "problemMatcher": []
      },
      {
        "label": "Lint & Format",
        "type": "shell",
        "command": "npm",
        "args": ["run", "lint:fix"],
        "options": {
          "cwd": "${workspaceFolder:Shared Libraries}"
        },
        "problemMatcher": ["$eslint-stylish"],
        "presentation": {
          "reveal": "silent",
          "panel": "shared"
        }
      },
      {
        "label": "Full Build Pipeline",
        "dependsOn": [
          "Install Dependencies",
          "Lint & Format",
          "Build API",
          "Test All"
        ],
        "dependsOrder": "sequence",
        "problemMatcher": []
      }
    ]
  }
}
```

---

## Reference Links

- [VS Code Multi-Root Workspaces](https://code.visualstudio.com/docs/editor/multi-root-workspaces)
- [VS Code Settings Schema](https://code.visualstudio.com/docs/getstarted/settings)
- [VS Code Debugging](https://code.visualstudio.com/docs/editor/debugging)
- [VS Code Tasks](https://code.visualstudio.com/docs/editor/tasks)
- [VS Code Variables Reference](https://code.visualstudio.com/docs/editor/variables-reference)

---

## Summary

This reference covers the complete `.code-workspace` schema with:

- **5 major properties**: folders (required), settings, extensions, launch, tasks
- **Detailed structure** and type information for each property
- **Working JSON examples** for all configurations
- **Validation rules** for structural requirements and constraints
- **Complete example** demonstrating all properties together
- **Best practices** for portable, maintainable workspace configurations

Use this reference when creating, modifying, or validating VS Code workspace files.
