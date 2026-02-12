#!/usr/bin/env python3
"""
Plugin Initializer - Creates a new Claude Code plugin from template

Usage:
    init_plugin.py <plugin-name> --path <path>

Examples:
    init_plugin.py my-plugin --path plugins
    init_plugin.py code-analyzer --path /path/to/marketplace/plugins
"""

import sys
import json
from pathlib import Path


PLUGIN_JSON_TEMPLATE = """{
  "name": "{plugin_name}",
  "version": "0.1.0",
  "description": "[TODO: Clear description of what the plugin provides]",
  "author": {
    "name": "[TODO: Author Name]",
    "email": "[TODO: email@example.com]",
    "url": "[TODO: https://github.com/org/repo]"
  },
  "repository": "[TODO: https://github.com/org/repo]",
  "keywords": [
    "{plugin_name}",
    "[TODO: add relevant keywords]"
  ]
}
"""

README_TEMPLATE = """# {plugin_title} Plugin

[TODO: Brief description of what this plugin provides]

## Installation

```bash
/plugin install {plugin_name}@crewchief
```

## Features

[TODO: List key features]
- Feature 1
- Feature 2
- Feature 3

## Agents

[TODO: List agents if any, or remove section]

## Commands

[TODO: List commands if any, or remove section]

## Skills

[TODO: List skills if any, or remove section]

## License

MIT License - see LICENSE for details.
"""


def title_case_name(name):
    """Convert hyphenated name to Title Case."""
    return ' '.join(word.capitalize() for word in name.split('-'))


def init_plugin(plugin_name, path):
    """
    Initialize a new plugin directory structure.

    Args:
        plugin_name: Name of the plugin (lowercase, hyphenated)
        path: Path where the plugin directory should be created

    Returns:
        Path to created plugin directory, or None if error
    """
    plugin_dir = Path(path).resolve() / plugin_name

    # Check if directory already exists
    if plugin_dir.exists():
        print(f"Error: Plugin directory already exists: {plugin_dir}")
        return None

    # Create directory structure
    try:
        plugin_dir.mkdir(parents=True)
        (plugin_dir / '.claude-plugin').mkdir()
        (plugin_dir / 'agents').mkdir()
        (plugin_dir / 'commands').mkdir()
        (plugin_dir / 'skills').mkdir()
        print(f"Created plugin directory: {plugin_dir}")
    except Exception as e:
        print(f"Error creating directories: {e}")
        return None

    # Create plugin.json
    plugin_json_path = plugin_dir / '.claude-plugin' / 'plugin.json'
    try:
        content = PLUGIN_JSON_TEMPLATE.format(plugin_name=plugin_name)
        plugin_json_path.write_text(content)
        print("Created .claude-plugin/plugin.json")
    except Exception as e:
        print(f"Error creating plugin.json: {e}")
        return None

    # Create README.md
    readme_path = plugin_dir / 'README.md'
    try:
        plugin_title = title_case_name(plugin_name)
        content = README_TEMPLATE.format(
            plugin_name=plugin_name,
            plugin_title=plugin_title
        )
        readme_path.write_text(content)
        print("Created README.md")
    except Exception as e:
        print(f"Error creating README.md: {e}")
        return None

    print(f"\nPlugin '{plugin_name}' initialized at {plugin_dir}")
    print("\nNext steps:")
    print("1. Edit .claude-plugin/plugin.json - fill in metadata")
    print("2. Edit README.md - document your plugin")
    print("3. Add agents/, commands/, or skills/ as needed")
    print("4. Register in marketplace.json")
    print("5. Update main README.md")
    print("6. Remember: version bump required after modifications (see plugin-skills-registration skill)")

    return plugin_dir


def main():
    if len(sys.argv) < 4 or sys.argv[2] != '--path':
        print("Usage: init_plugin.py <plugin-name> --path <path>")
        print("\nPlugin name requirements:")
        print("  - Lowercase letters, digits, and hyphens only")
        print("  - Must match directory name exactly")
        print("\nExamples:")
        print("  init_plugin.py my-plugin --path plugins")
        print("  init_plugin.py code-analyzer --path /path/to/marketplace/plugins")
        sys.exit(1)

    plugin_name = sys.argv[1]
    path = sys.argv[3]

    # Validate plugin name
    if not all(c.islower() or c.isdigit() or c == '-' for c in plugin_name):
        print("Error: Plugin name must be lowercase letters, digits, and hyphens only")
        sys.exit(1)

    print(f"Initializing plugin: {plugin_name}")
    print(f"Location: {path}")
    print()

    result = init_plugin(plugin_name, path)
    sys.exit(0 if result else 1)


if __name__ == "__main__":
    main()
