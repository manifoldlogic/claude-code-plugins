---
name: plugin-skills-registration
description: Register skills in a plugin's plugin.json to enable skill discovery and loading by Claude Code
origin: ISKIM
created: 2026-02-08
tags: [plugin-system, skills, configuration]
---

# Plugin Skills Registration

## Overview

This skill documents how to register skill directories in a plugin's `plugin.json` file. The plugin framework requires each skill to be explicitly listed in the `skills` array for discovery and loading. Each registered skill directory must contain a `SKILL.md` file, or the plugin will fail to load.

This registration pattern is fundamental to the plugin system and must be followed when adding any new skill to any plugin.

## When to Use

Use this skill when:

- Adding a new skill to an existing plugin
- Creating a new plugin with skills
- Debugging why a skill is not being discovered by Claude Code
- Understanding the plugin skill loading mechanism
- A plugin fails to load due to missing SKILL.md for registered skills

## Pattern/Procedure

### Plugin.json Skills Array

Skills are registered in the `skills` array within `plugins/{name}/.claude-plugin/plugin.json`:

```json
{
  "name": "plugin-name",
  "version": "0.1.0",
  "description": "Plugin description",
  "skills": [
    "skills/skill-one",
    "skills/skill-two"
  ]
}
```

**Critical requirements:**

1. **Path format**: Relative path from plugin directory: `skills/{skill-name}`
2. **SKILL.md requirement**: Each listed skill directory MUST contain `SKILL.md`
3. **Directory structure**: `plugins/{plugin-name}/skills/{skill-name}/SKILL.md`
4. **Array format**: Simple string array of skill paths
5. **No wildcards**: Each skill must be explicitly listed

### Skill Directory Requirements

For each skill listed in the skills array:

```
plugins/{plugin-name}/skills/{skill-name}/
├── SKILL.md              # REQUIRED - skill documentation
├── scripts/              # OPTIONAL - executable scripts
├── tests/                # OPTIONAL - test files
└── references/           # OPTIONAL - reference documentation
```

**The plugin framework checks:**
- Does `SKILL.md` exist at `skills/{skill-name}/SKILL.md`?
- If NO: Plugin loading fails with error

### Registration Steps

1. **Create skill directory:**
   ```bash
   mkdir -p plugins/{plugin-name}/skills/{skill-name}
   ```

2. **Create SKILL.md:**
   ```bash
   # MUST exist before registering in plugin.json
   touch plugins/{plugin-name}/skills/{skill-name}/SKILL.md
   # Then populate with proper content (see skill-md-structure skill)
   ```

3. **Add skill to plugin.json:**
   ```bash
   # Edit plugins/{plugin-name}/.claude-plugin/plugin.json
   # Add "skills/{skill-name}" to skills array
   ```

4. **Version Bump (Required):**

   After modifying plugin content, bump the version in `plugins/{plugin-name}/.claude-plugin/plugin.json`:

   **Determine the bump type:**

   | Change Type | Bump | Example |
   |-------------|------|---------|
   | Bug fix, documentation update, internal refactoring | PATCH (0.0.x) | 0.2.0 -> 0.2.1 |
   | New skill, command, agent, or hook added | MINOR (0.x.0) | 0.2.1 -> 0.3.0 |
   | Breaking change (renamed/removed public interface) | MAJOR (x.0.0) | 0.3.0 -> 1.0.0 |

   **Default to PATCH** unless the change adds new capabilities (MINOR) or breaks existing interfaces (MAJOR).

   **Edit the version field:**
   ```json
   {
     "version": "0.2.1"  // <-- bump this
   }
   ```

   **Verify the bump:**
   ```bash
   jq -r '.version' plugins/{plugin-name}/.claude-plugin/plugin.json
   ```

5. **Validate registration:**
   ```bash
   # Check all registered skills have SKILL.md
   plugin_dir="plugins/{plugin-name}"
   jq -r '.skills[]' "$plugin_dir/.claude-plugin/plugin.json" | while read skill_path; do
     if test -f "$plugin_dir/$skill_path/SKILL.md"; then
       echo "✓ $skill_path/SKILL.md exists"
     else
       echo "✗ $skill_path/SKILL.md MISSING"
     fi
   done
   ```

### Skill Ordering Convention

From ISKIM ticket, skills are organized by type:

1. **Executable skills first** (skills with scripts that perform operations)
2. **Reference skills last** (documentation-only pattern skills)

Example from iTerm plugin:
```json
{
  "skills": [
    "skills/tab-management",                        // Executable
    "skills/pane-management",                       // Executable
    "skills/eleven-category-test-structure",        // Reference
    "skills/iterm-applescript-generation",          // Reference
    "skills/iterm-cross-skill-sourcing",            // Reference
    "skills/iterm-nine-section-structure"           // Reference
  ]
}
```

**Why this order?**
- Improves readability (operational capabilities listed first)
- Makes it clear which skills have executable components
- Order does not affect loading behavior (all skills load regardless)

## Examples

### Example 1: Adding Pane-Management Skill (ISKIM.1002)

**Initial state (plugin.json):**
```json
{
  "name": "iterm",
  "version": "0.2.0",
  "description": "iTerm2 tab management for macOS host and Linux container environments",
  "skills": [
    "skills/tab-management"
  ]
}
```

**After adding pane-management and 4 pattern skills:**
```json
{
  "name": "iterm",
  "version": "0.3.0",
  "description": "iTerm2 tab and pane management for macOS host and Linux container environments",
  "skills": [
    "skills/tab-management",
    "skills/pane-management",
    "skills/eleven-category-test-structure",
    "skills/iterm-applescript-generation",
    "skills/iterm-cross-skill-sourcing",
    "skills/iterm-nine-section-structure"
  ]
}
```

**Verification that all SKILL.md files exist:**
```bash
cd plugins/iterm
jq -r '.skills[]' .claude-plugin/plugin.json | while read skill; do
  test -f "$skill/SKILL.md" && echo "✓ $skill" || echo "✗ $skill MISSING"
done

# Output:
# ✓ skills/tab-management
# ✓ skills/pane-management
# ✓ skills/eleven-category-test-structure
# ✓ skills/iterm-applescript-generation
# ✓ skills/iterm-cross-skill-sourcing
# ✓ skills/iterm-nine-section-structure
```

### Example 2: Validation Script for All Plugins

Check all plugins have valid skill registrations:

```bash
# For each plugin in marketplace.json
jq -r '.plugins[].source' .claude-plugin/marketplace.json | while read plugin_dir; do
  echo "Checking $plugin_dir..."

  # Get plugin name
  plugin_name=$(jq -r '.name' "$plugin_dir/.claude-plugin/plugin.json")

  # Check each registered skill
  jq -r '.skills[]' "$plugin_dir/.claude-plugin/plugin.json" 2>/dev/null | while read skill_path; do
    if test -f "$plugin_dir/$skill_path/SKILL.md"; then
      echo "  ✓ $plugin_name: $skill_path"
    else
      echo "  ✗ $plugin_name: $skill_path MISSING SKILL.md"
    fi
  done
done
```

### Example 3: Common Registration Errors

**Error 1: SKILL.md missing**
```json
// plugin.json lists the skill
{
  "skills": ["skills/new-feature"]
}
```
```bash
# But SKILL.md doesn't exist
$ ls plugins/my-plugin/skills/new-feature/
scripts/  tests/  # No SKILL.md!

# Result: Plugin fails to load
```

**Fix:**
```bash
# Create SKILL.md before registering
touch plugins/my-plugin/skills/new-feature/SKILL.md
# Populate with proper content (see skill-md-structure skill)
```

**Error 2: Wrong path format**
```json
// ✗ WRONG: Absolute path
{
  "skills": ["/plugins/my-plugin/skills/feature"]
}

// ✗ WRONG: Missing "skills/" prefix
{
  "skills": ["feature"]
}

// ✓ CORRECT: Relative path from plugin directory
{
  "skills": ["skills/feature"]
}
```

**Error 3: Skill directory doesn't exist**
```json
{
  "skills": ["skills/typo-in-name"]  // Directory is "skills/correct-name"
}
```

**Fix:** Ensure directory name matches exactly:
```bash
# Check registered skills
jq -r '.skills[]' .claude-plugin/plugin.json

# Check actual directories
ls plugins/my-plugin/skills/

# Fix typo in either plugin.json or directory name
```

## Validation Checklist

Before committing plugin.json changes:

- [ ] JSON syntax is valid (use `jq .` to verify)
- [ ] Every skill in skills array has corresponding directory under `skills/`
- [ ] Every skill directory contains `SKILL.md` file
- [ ] Skill paths use format `skills/{name}` (not absolute paths)
- [ ] No duplicate entries in skills array
- [ ] Skill names follow kebab-case convention
- [ ] Executable skills are listed before reference skills (optional convention)
- [ ] Plugin version bumped per Version Bump step above

## References

- Ticket: ISKIM (registered 6 skills in iTerm plugin)
- Related files:
  - `plugins/{name}/.claude-plugin/plugin.json` (plugin configuration)
  - `plugins/{name}/skills/{skill}/SKILL.md` (required skill documentation)
- Related skills:
  - plugin-marketplace-registration (registering plugins in marketplace)
  - skill-md-structure (SKILL.md documentation structure)
