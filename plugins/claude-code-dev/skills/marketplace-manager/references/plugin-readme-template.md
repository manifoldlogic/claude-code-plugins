# Plugin README Template

Use this template when creating README.md for a new plugin.

---

# {Plugin Title} Plugin

{One paragraph description of what the plugin provides and who it's for.}

## Installation

```bash
/plugin install {plugin-name}@{marketplace-name}
```

## Features

{List the main capabilities of the plugin.}

- **Feature 1** - Brief description
- **Feature 2** - Brief description
- **Feature 3** - Brief description

## Agents

{List agents provided by the plugin. Remove section if none.}

### @{agent-name}

{Brief description of the agent's purpose and expertise.}

**Use for:**
- Task type 1
- Task type 2

## Commands

{List slash commands provided. Remove section if none.}

| Command | Description |
|---------|-------------|
| `/{plugin}:{command1}` | What it does |
| `/{plugin}:{command2}` | What it does |

## Skills

{List skills provided. Remove section if none.}

### {skill-name}

{Brief description of what the skill enables.}

**Activates when:** {Describe trigger conditions}

## Configuration

{Optional: Document any configuration options or settings.}

## Examples

{Optional: Show concrete usage examples.}

```bash
# Example command usage
/{plugin}:{command} argument
```

## Troubleshooting

{Optional: Common issues and solutions.}

### Issue: {Problem}

**Solution:** {How to fix it}

## Contributing

{Optional: Instructions for contributors.}

## License

MIT License - see LICENSE for details.

---

## Template Usage Notes

**Required sections:**
- Title and description
- Installation
- Features

**Conditional sections** (include if applicable):
- Agents (if plugin has agents)
- Commands (if plugin has commands)
- Skills (if plugin has skills)

**Optional sections:**
- Configuration
- Examples
- Troubleshooting
- Contributing

**Writing tips:**
- Keep descriptions concise
- Use bullet points for scannability
- Include concrete examples
- Document all public interfaces
