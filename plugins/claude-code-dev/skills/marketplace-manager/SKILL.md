---
name: marketplace-manager
description: Manages Claude Code plugin marketplaces. This skill should be used when adding new plugins, updating marketplace configuration, keeping documentation in sync, or scaffolding plugin directory structures. Activates for tasks involving marketplace.json, plugin.json, or plugin README files.
---

# Marketplace Manager

Guidance for managing Claude Code plugin marketplaces - adding plugins, updating configurations, and maintaining documentation consistency.

## Marketplace Structure

A Claude Code plugin marketplace has this structure:

```
marketplace-root/
├── .claude-plugin/
│   └── marketplace.json      # Registry of all plugins
├── plugins/
│   └── {plugin-name}/        # Individual plugins
│       ├── .claude-plugin/
│       │   └── plugin.json   # Plugin metadata
│       ├── README.md         # Plugin documentation
│       ├── agents/           # Agent definitions (.md files)
│       ├── commands/         # Slash commands (.md files)
│       └── skills/           # Skills (SKILL.md + resources)
├── README.md                 # Main marketplace README
└── docs/                     # Additional documentation
```

## Adding a New Plugin

To add a new plugin to the marketplace, follow these steps in order:

### Step 1: Scaffold the Plugin Directory

Run the initialization script:

```bash
python3 scripts/init_plugin.py <plugin-name> --path <marketplace>/plugins
```

This creates:
- `.claude-plugin/plugin.json` with metadata template
- `README.md` with documentation template
- Empty `agents/`, `commands/`, `skills/` directories

### Step 2: Configure plugin.json

Edit `.claude-plugin/plugin.json` with accurate metadata:

```json
{
  "name": "plugin-name",
  "version": "0.1.0",
  "description": "Clear description of what the plugin provides",
  "author": {
    "name": "Author Name",
    "email": "email@example.com",
    "url": "https://github.com/org/repo"
  },
  "repository": "https://github.com/org/repo",
  "keywords": ["relevant", "keywords", "for", "discovery"]
}
```

**Guidelines:**
- `name`: Lowercase, hyphen-separated (must match directory name)
- `version`: Semantic versioning (start with 0.1.0 for new plugins)
- `description`: 1-2 sentences explaining the plugin's purpose
- `keywords`: 5-10 relevant terms for discoverability

### Step 3: Write the Plugin README

The plugin README should include:

1. **Title and Overview** - What the plugin does
2. **Installation** - `/plugin install name@marketplace`
3. **Features** - Key capabilities (bullet list)
4. **Usage** - Commands, agents, or skills provided
5. **License** - Usually MIT for open source

See `references/plugin-readme-template.md` for a complete template.

### Step 4: Register in marketplace.json

Add the plugin to `.claude-plugin/marketplace.json`:

```json
{
  "plugins": [
    // ... existing plugins ...
    {
      "name": "new-plugin",
      "source": "./plugins/new-plugin",
      "description": "Brief description for marketplace listing"
    }
  ]
}
```

### Step 5: Update Main README

Update the marketplace's main `README.md`:

1. Add row to the "Available Plugins" table
2. Add a section describing the plugin's features
3. Update the repository structure diagram if needed

## Updating Documentation

When modifying plugins, keep documentation in sync:

### After Adding/Removing Components

When adding or removing agents, commands, or skills:

1. Update the plugin's `README.md` to reflect changes
2. If significant, update the main marketplace `README.md`
3. Bump the version in `plugin.json`

### Version Bump Guidelines

- **Patch (0.0.x)**: Bug fixes, documentation updates
- **Minor (0.x.0)**: New features, new agents/commands/skills
- **Major (x.0.0)**: Breaking changes, major restructuring

## Validation Checklist

Before committing marketplace changes, verify:

- [ ] Plugin directory name matches `name` in plugin.json
- [ ] All paths in marketplace.json are valid
- [ ] Plugin README documents all agents, commands, skills
- [ ] Main README table includes the plugin
- [ ] Main README structure diagram is current
- [ ] No duplicate plugin names in marketplace.json

## Common Tasks

### Rename a Plugin

1. Rename the plugin directory
2. Update `name` in plugin.json
3. Update `source` path in marketplace.json
4. Update all README references
5. Update any cross-references in other plugins

### Remove a Plugin

1. Remove entry from marketplace.json
2. Remove row from main README table
3. Remove section from main README
4. Update structure diagram
5. Delete the plugin directory

### Move a Skill Between Plugins

1. Copy skill directory to new plugin
2. Update source plugin's README
3. Update destination plugin's README
4. Delete skill from source plugin

## Resources

### scripts/

- `init_plugin.py` - Initialize new plugin directory structure

### references/

- `plugin-structure.md` - Detailed plugin directory structure reference
- `plugin-readme-template.md` - Template for plugin README files
