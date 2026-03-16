# CLAUDE.md

######## IMPORTANT! SHELL TARGET: ZSH ######## IMPORTANT! SHELL TARGET: ZSH ########
All commands execute in ZSH. Use POSIX-compatible syntax. Never use bash-only syntax.
Avoid: $RANDOM, [[ ]], bash arrays, `which`. Use: command -v, [ ], grep -E, portable syntax.
######## IMPORTANT! SHELL TARGET: ZSH ######## IMPORTANT! SHELL TARGET: ZSH ########

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CrewChief Plugins for Claude Code - a collection of plugins for development workflows, project management, and CI/CD automation. This is a **plugin repository**, not a compiled application.

## Testing

Run hook tests manually from the plugin directory:

```bash
# SDD plugin hook tests
bash plugins/sdd/hooks/test-workflow-guidance.sh
bash plugins/sdd/hooks/test-setup-sdd-env.sh
bash plugins/sdd/hooks/test-block-dangerous-git.sh
bash plugins/sdd/hooks/test-warn-sdd-refs.sh

# iTerm tab-management tests
bash plugins/iterm/skills/tab-management/scripts/test-iterm-open-tab.sh
bash plugins/iterm/skills/tab-management/scripts/test-iterm-close-tab.sh
bash plugins/iterm/skills/tab-management/scripts/test-iterm-list-tabs.sh
bash plugins/iterm/skills/tab-management/scripts/test-iterm-utils.sh

# iTerm pane-management tests
bash plugins/iterm/skills/pane-management/tests/test-split-pane.sh
bash plugins/iterm/skills/pane-management/tests/test-list-panes.sh
bash plugins/iterm/skills/pane-management/tests/test-close-pane.sh
bash plugins/iterm/skills/pane-management/tests/test-iterm-send-text.sh
```

No automated CI/CD - tests are executed manually.

## Architecture

### Plugin Structure

Each plugin follows this pattern:

```
plugins/{name}/
├── .claude-plugin/plugin.json    # Metadata, hooks registration
├── agents/                       # Agent definitions (markdown)
├── commands/                     # Slash commands (markdown)
├── hooks/                        # Python/JS hooks
├── skills/                       # Reusable capabilities
│   └── {skill-name}/
│       ├── SKILL.md              # Skill documentation
│       ├── scripts/              # Shell scripts
│       ├── templates/            # Document templates
│       └── references/           # Reference docs
└── README.md
```

### Hook System

Hooks are registered in `plugin.json` and execute at specific lifecycle points:

| Type | Purpose | Exit Codes |
|------|---------|------------|
| SessionStart | Environment setup | 0=success |
| PreToolUse | Input validation/blocking | 0=allow, 2=block |
| PostToolUse | Output warnings | 0=success |
| Stop | Workflow guidance | 0=allow, 2=block stop |

### Agent Model Strategy

- **Haiku**: Mechanical/structured tasks (status reports, commits, test execution)
- **Sonnet**: Reasoning work (planning, review, verification)
- **Opus**: Complex decisions (ticket planning with research)

### Orchestrator Pattern

Commands are orchestrators that delegate work - they coordinate but don't do work directly:

- Scripts handle mechanical tasks (scaffolding, inventory)
- Agents handle judgment (planning, verification)
- Preserves context and extends session longevity

## SDD Plugin Core Workflow

### Key Commands

| Command | Description |
|---------|-------------|
| `/sdd:plan-ticket [description]` | Create ticket with planning docs |
| `/sdd:review [TICKET_ID]` | Critical review before task creation |
| `/sdd:create-tasks [TICKET_ID]` | Generate tasks from plan |
| `/sdd:do-task [TASK_ID]` | Complete single task with verification |
| `/sdd:do-all-tasks [TICKET_ID]` | Execute all tasks systematically |
| `/sdd:status` | Check epic/ticket/task status |
| `/sdd:archive [TICKET_ID]` | Archive completed ticket |

## Configuration

### Marketplace Registration

Plugins are registered in `.claude-plugin/marketplace.json`. The marketplace name is "crewchief".

### Environment

- `SDD_ROOT_DIR`: Location of SDD data directory (epics, tickets, tasks)
- `SDD_DISABLE_STOP_HOOK=1`: Disable workflow guidance
- `AUTOGATE_BYPASS=true`: Bypass work gates

### Work Gates

`.autogate.json` files in ticket/epic directories control autonomous work:

```json
{"ready": false}                    // Block all autonomous work
{"ready": true, "stop_at_phase": 1} // Stop after Phase 1
```

## Version Bumping (Required After Plugin Changes)

After modifying plugin files, bump the version in `.claude-plugin/plugin.json` using semver:
- **PATCH**: Bug fixes, docs, refactoring (e.g., 0.2.0 → 0.2.1)
- **MINOR**: New skill, command, agent, or hook (e.g., 0.2.0 → 0.3.0)
- **MAJOR**: Breaking changes to existing interfaces (e.g., 0.2.0 → 1.0.0)

Verify with: `jq -r '.version' plugins/{name}/.claude-plugin/plugin.json`

## Adding a New Plugin

1. Create directory: `plugins/{name}/`
2. Add `.claude-plugin/plugin.json` with metadata
3. Register in `.claude-plugin/marketplace.json`
4. Add agents in `agents/` (markdown with frontmatter)
5. Add commands in `commands/` (markdown with workflow instructions)
6. Add skills in `skills/{skill-name}/` with SKILL.md

## Skill Documentation Guidelines

When writing SKILL.md for executable skills, cross-verify all documented flags, defaults, and exit codes against source code. Use cross-references to authoritative SKILL.md docs (e.g., tab-management) instead of duplicating shared prerequisites or execution context content. For CLI tools with multiple operations, include decision trees and natural-language-to-command mapping tables.
