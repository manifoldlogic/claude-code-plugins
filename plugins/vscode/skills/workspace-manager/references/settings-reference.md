# VS Code Settings Reference

## Overview

This reference documents commonly configured VS Code settings at the workspace level. While VS Code provides hundreds of settings, this guide focuses on settings that teams frequently customize for their projects to ensure consistent development environments across team members.

Settings are stored in JSON format in `.vscode/settings.json` files and control everything from editor behavior to extension configuration.

## Settings Hierarchy

VS Code applies settings in a hierarchical order with more specific scopes overriding more general ones:

```
User Settings (global) < Workspace Settings < Folder Settings
```

- **User Settings**: Global preferences stored in your user profile. Apply to all VS Code instances.
- **Workspace Settings**: Stored in `.vscode/settings.json` at the workspace root. Apply to all folders in the workspace.
- **Folder Settings**: Stored in `.vscode/settings.json` within a specific folder in a multi-root workspace. Apply only to that folder.

**Precedence Rule**: Folder Settings override Workspace Settings, which override User Settings. The most specific setting wins.

**Example**:
```
User:      editor.tabSize = 4
Workspace: editor.tabSize = 2  (wins for this workspace)
Folder:    editor.tabSize = 8  (wins for this specific folder only)
```

## Editor Settings

Settings that control code editing behavior and appearance.

### editor.tabSize

- **Type**: `number`
- **Default**: `4` (varies by language mode)
- **Description**: Controls the number of spaces a tab character represents in the editor.

**Example**:
```json
{
  "editor.tabSize": 2
}
```

### editor.insertSpaces

- **Type**: `boolean`
- **Default**: `true`
- **Description**: When true, pressing Tab inserts spaces. When false, inserts tab characters.

**Example**:
```json
{
  "editor.insertSpaces": true
}
```

### editor.formatOnSave

- **Type**: `boolean`
- **Default**: `false`
- **Description**: Automatically format the file when saving. Requires a formatter extension for the file type.

**Example**:
```json
{
  "editor.formatOnSave": true
}
```

### editor.rulers

- **Type**: `array` of numbers or objects
- **Default**: `[]`
- **Description**: Renders vertical rulers at specified column positions to show line length guidelines.

**Example**:
```json
{
  "editor.rulers": [80, 120]
}
```

### editor.wordWrap

- **Type**: `string`
- **Default**: `"off"`
- **Description**: Controls how lines wrap. Options: `"off"`, `"on"`, `"wordWrapColumn"`, `"bounded"`.

**Example**:
```json
{
  "editor.wordWrap": "on"
}
```

### editor.defaultFormatter

- **Type**: `string` or `null`
- **Default**: `null`
- **Description**: Specifies the default formatter extension ID to use. Can be overridden per language.

**Example**:
```json
{
  "editor.defaultFormatter": "esbenp.prettier-vscode"
}
```

### editor.codeActionsOnSave

- **Type**: `object`
- **Default**: `{}`
- **Description**: Run code actions (like auto-fix) when saving a file.

**Example**:
```json
{
  "editor.codeActionsOnSave": {
    "source.fixAll.eslint": true,
    "source.organizeImports": true
  }
}
```

### editor.bracketPairColorization.enabled

- **Type**: `boolean`
- **Default**: `true`
- **Description**: Controls whether bracket pairs are colorized for easier visual matching.

**Example**:
```json
{
  "editor.bracketPairColorization.enabled": true
}
```

## File Settings

Settings that control file handling, associations, and exclusions.

### files.exclude

- **Type**: `object`
- **Default**: Varies (typically includes `.git`, `.DS_Store`, etc.)
- **Description**: Configure glob patterns for files and folders to exclude from the file explorer. Patterns are relative to workspace root.

**Example**:
```json
{
  "files.exclude": {
    "**/.git": true,
    "**/node_modules": true,
    "**/.DS_Store": true,
    "**/dist": true,
    "**/*.log": true
  }
}
```

### files.associations

- **Type**: `object`
- **Default**: `{}`
- **Description**: Map file patterns to language modes. Useful for non-standard file extensions.

**Example**:
```json
{
  "files.associations": {
    "*.env.*": "properties",
    "*.config": "json",
    "Dockerfile.*": "dockerfile"
  }
}
```

### files.encoding

- **Type**: `string`
- **Default**: `"utf8"`
- **Description**: Default character set encoding for files. Options include `"utf8"`, `"utf8bom"`, `"utf16le"`, `"utf16be"`, `"iso88591"`, etc.

**Example**:
```json
{
  "files.encoding": "utf8"
}
```

### files.eol

- **Type**: `string`
- **Default**: `"auto"`
- **Description**: Default end-of-line character. Options: `"auto"` (uses OS default), `"\n"` (LF), `"\r\n"` (CRLF).

**Example**:
```json
{
  "files.eol": "\n"
}
```

### files.autoSave

- **Type**: `string`
- **Default**: `"off"`
- **Description**: Controls auto-save of files. Options: `"off"`, `"afterDelay"`, `"onFocusChange"`, `"onWindowChange"`.

**Example**:
```json
{
  "files.autoSave": "afterDelay",
  "files.autoSaveDelay": 1000
}
```

### files.watcherExclude

- **Type**: `object`
- **Default**: Varies (typically includes `node_modules`, `.git`, etc.)
- **Description**: Configure glob patterns for files/folders to exclude from file watchers. Improves performance.

**Example**:
```json
{
  "files.watcherExclude": {
    "**/.git/objects/**": true,
    "**/.git/subtree-cache/**": true,
    "**/node_modules/**": true,
    "**/.hg/store/**": true
  }
}
```

## Search Settings

Settings that control search behavior and exclusions.

### search.exclude

- **Type**: `object`
- **Default**: Inherits from `files.exclude`
- **Description**: Configure glob patterns for files and folders to exclude from text search. Patterns are relative to workspace root.

**Example**:
```json
{
  "search.exclude": {
    "**/node_modules": true,
    "**/bower_components": true,
    "**/*.code-search": true,
    "**/dist": true,
    "**/build": true,
    "**/.next": true,
    "**/.nuxt": true
  }
}
```

### search.useIgnoreFiles

- **Type**: `boolean`
- **Default**: `true`
- **Description**: Controls whether to use `.gitignore` and `.ignore` files when searching.

**Example**:
```json
{
  "search.useIgnoreFiles": true
}
```

### search.useGlobalIgnoreFiles

- **Type**: `boolean`
- **Default**: `false`
- **Description**: Controls whether to use global `.gitignore` files (from `core.excludesFile` git config) when searching.

**Example**:
```json
{
  "search.useGlobalIgnoreFiles": false
}
```

### search.followSymlinks

- **Type**: `boolean`
- **Default**: `true`
- **Description**: Controls whether to follow symbolic links when searching.

**Example**:
```json
{
  "search.followSymlinks": true
}
```

## Terminal Settings

Settings that configure the integrated terminal.

### terminal.integrated.cwd

- **Type**: `string`
- **Default**: Workspace root
- **Description**: Sets the working directory for new terminal instances.

**Example**:
```json
{
  "terminal.integrated.cwd": "${workspaceFolder}/src"
}
```

### terminal.integrated.env.linux

- **Type**: `object`
- **Default**: `{}`
- **Description**: Environment variables to add to the terminal on Linux. Also available: `terminal.integrated.env.osx`, `terminal.integrated.env.windows`.

**Example**:
```json
{
  "terminal.integrated.env.linux": {
    "NODE_ENV": "development",
    "API_URL": "http://localhost:3000"
  }
}
```

### terminal.integrated.shell.linux

- **Type**: `string` or `null`
- **Default**: System default shell
- **Description**: Path to shell executable to use in terminal on Linux. Also available: `terminal.integrated.shell.osx`, `terminal.integrated.shell.windows`.

**Example**:
```json
{
  "terminal.integrated.shell.linux": "/bin/zsh"
}
```

### terminal.integrated.defaultProfile.linux

- **Type**: `string` or `null`
- **Default**: `null`
- **Description**: The default terminal profile on Linux. Also available: `terminal.integrated.defaultProfile.osx`, `terminal.integrated.defaultProfile.windows`.

**Example**:
```json
{
  "terminal.integrated.defaultProfile.linux": "zsh"
}
```

### terminal.integrated.fontSize

- **Type**: `number`
- **Default**: Inherits from `editor.fontSize`
- **Description**: Controls the font size in pixels of the terminal.

**Example**:
```json
{
  "terminal.integrated.fontSize": 14
}
```

## Extension-Specific Settings

Extensions contribute their own settings using the pattern `extensionId.settingName`. Extension IDs are typically in the format `publisher.extensionName`.

### Pattern

Extension-specific settings always follow this naming convention:

```
extensionId.settingName
```

Where `extensionId` is the unique identifier for the extension (visible in the Extensions view).

### Common Extension Settings Examples

#### ESLint

```json
{
  "eslint.enable": true,
  "eslint.workingDirectories": ["./packages/*"],
  "eslint.validate": ["javascript", "javascriptreact", "typescript", "typescriptreact"]
}
```

#### Prettier

```json
{
  "prettier.enable": true,
  "prettier.configPath": "./.prettierrc",
  "prettier.requireConfig": true
}
```

#### Python

```json
{
  "python.defaultInterpreterPath": "${workspaceFolder}/.venv/bin/python",
  "python.linting.enabled": true,
  "python.linting.pylintEnabled": true,
  "python.formatting.provider": "black"
}
```

#### TypeScript/JavaScript

```json
{
  "typescript.tsdk": "node_modules/typescript/lib",
  "typescript.enablePromptUseWorkspaceTsdk": true,
  "javascript.suggest.autoImports": true,
  "typescript.suggest.autoImports": true
}
```

#### GitLens

```json
{
  "gitlens.hovers.currentLine.over": "line",
  "gitlens.currentLine.enabled": true,
  "gitlens.codeLens.enabled": false
}
```

### Language-Specific Settings

You can scope settings to specific programming languages using the `[language]` key:

```json
{
  "[javascript]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "editor.formatOnSave": true
  },
  "[python]": {
    "editor.tabSize": 4,
    "editor.insertSpaces": true
  },
  "[markdown]": {
    "editor.wordWrap": "on",
    "editor.quickSuggestions": false
  }
}
```

## Common Workspace Configuration Examples

### Frontend Project (React/TypeScript)

```json
{
  "editor.tabSize": 2,
  "editor.insertSpaces": true,
  "editor.formatOnSave": true,
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "editor.codeActionsOnSave": {
    "source.fixAll.eslint": true,
    "source.organizeImports": true
  },
  "files.exclude": {
    "**/node_modules": true,
    "**/dist": true,
    "**/.next": true,
    "**/build": true
  },
  "search.exclude": {
    "**/node_modules": true,
    "**/dist": true,
    "**/.next": true,
    "**/build": true,
    "**/*.lock": true
  },
  "typescript.tsdk": "node_modules/typescript/lib",
  "eslint.workingDirectories": ["."],
  "prettier.configPath": "./.prettierrc"
}
```

### Python Project

```json
{
  "editor.tabSize": 4,
  "editor.insertSpaces": true,
  "editor.rulers": [79, 120],
  "editor.formatOnSave": true,
  "files.exclude": {
    "**/__pycache__": true,
    "**/*.pyc": true,
    "**/.pytest_cache": true,
    "**/.venv": true
  },
  "python.defaultInterpreterPath": "${workspaceFolder}/.venv/bin/python",
  "python.linting.enabled": true,
  "python.linting.pylintEnabled": true,
  "python.formatting.provider": "black",
  "python.testing.pytestEnabled": true
}
```

### Monorepo Project

```json
{
  "editor.tabSize": 2,
  "editor.formatOnSave": true,
  "files.exclude": {
    "**/node_modules": true,
    "**/dist": true
  },
  "search.exclude": {
    "**/node_modules": true,
    "**/dist": true,
    "**/packages/*/build": true
  },
  "eslint.workingDirectories": ["./packages/*"],
  "typescript.tsdk": "node_modules/typescript/lib",
  "typescript.enablePromptUseWorkspaceTsdk": true
}
```

## Best Practices

1. **Keep it Minimal**: Only include settings that differ from reasonable defaults or are critical for team consistency.

2. **Use Comments**: JSON doesn't support comments, but VS Code's `settings.json` does. Use them to explain non-obvious configurations:
   ```json
   {
     // Use 2 spaces for consistency with frontend code
     "editor.tabSize": 2
   }
   ```

3. **Language-Specific Over Global**: Prefer language-specific settings when behavior should differ by file type.

4. **Extension Settings**: Document required extensions in your README if workspace settings depend on them.

5. **Gitignore Sync**: Ensure `files.exclude` and `search.exclude` align with your `.gitignore` patterns.

6. **Team Agreement**: Workspace settings should reflect team consensus, especially for formatting and linting.

## References

- [VS Code Settings Documentation](https://code.visualstudio.com/docs/getstarted/settings)
- [VS Code Variables Reference](https://code.visualstudio.com/docs/editor/variables-reference)
- For schema details, see `workspace-schema.md` in this directory
