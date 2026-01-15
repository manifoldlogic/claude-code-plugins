---
name: obsidian-cli
description: Manage Obsidian vault notes using obsidian-cli from a devcontainer environment via SSH to macOS host
---

# Obsidian CLI Skill

**Last Updated:** 2025-01-15
**CLI Tool:** obsidian-cli (Yakitrak)

## Overview

The obsidian-cli tool provides command-line access to Obsidian vaults, enabling note creation, search, content retrieval, and vault management without opening the Obsidian GUI application.

This skill enables Claude Code to interact with Obsidian vaults on the macOS host from within a devcontainer environment. Commands are executed via SSH tunneling using the established host-communication pattern.

**Capabilities:**
- Create new notes with specified content and frontmatter
- Search notes by filename or content patterns
- Retrieve note content for analysis or modification
- List and manage vaults
- Move notes between folders
- Open notes in Obsidian (GUI)

## Decision Tree

### Use obsidian-cli skill when:
- User wants to create, read, search, or manage Obsidian notes
- Task involves knowledge management in an Obsidian vault
- User mentions "vault", "obsidian", or "note" in the context of knowledge management
- Need to programmatically access note content from the devcontainer
- Creating notes from code analysis, documentation, or research

### Use alternative approaches when:
- **Direct file operations**: If you already know the exact vault path and just need to read/write markdown files, use the Read/Write tools directly
- **Git-tracked vaults**: For version-controlled vault changes, use git commands
- **Obsidian GUI required**: For commands like `open` that require the Obsidian app to be running

### NOT available over SSH:
- Interactive commands requiring GUI input
- Plugin-specific operations (obsidian-cli works at filesystem level)
- Real-time sync status (Obsidian app feature)

## Prerequisites

### Environment Requirements

- Running inside a devcontainer with SSH access to macOS host
- `HOST_USER` environment variable configured in devcontainer.json
- SSH keys mounted at `~/.ssh/id_ed25519`
- obsidian-cli installed on the macOS host via Homebrew

### Verification Commands

Before using obsidian-cli commands, verify the environment is properly configured:

```bash
# 1. Verify SSH connectivity to host
ssh -o BatchMode=yes -o ConnectTimeout=5 ${HOST_USER}@host.docker.internal "echo OK"

# 2. Verify obsidian-cli is installed on host
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "which obsidian-cli"

# 3. Verify default vault is configured
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli print-default"
```

**If verification fails:**

- **SSH fails**: Check HOST_USER is set in devcontainer.json, rebuild container if needed
- **CLI not found**: Install on host with `brew tap yakitrak/yakitrak && brew install yakitrak/yakitrak/obsidian-cli`
- **No default vault**: Set default with `obsidian-cli set-default "VaultName"`

## SSH Command Pattern

**CRITICAL:** All obsidian-cli commands must be executed via SSH to the macOS host.

### Template

```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli <command> [arguments]"
```

### Pattern Components

| Component | Value | Purpose |
|-----------|-------|---------|
| SSH key | `~/.ssh/id_ed25519` | Authentication to host |
| Host user | `${HOST_USER}` | macOS username from devcontainer.json |
| Host address | `host.docker.internal` | Docker DNS for host machine |
| CLI | `obsidian-cli` | Obsidian CLI tool on host |

### Example Commands

```bash
# Create a note
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli create 'My Note' --content 'Note content here'"

# Search notes
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli search 'keyword'"

# Print note content
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli print 'My Note'"

# List vaults
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli list-vaults"
```

## Shell Escaping (CRITICAL)

**WARNING:** User-provided input (note names, content, search terms) must be properly escaped before inclusion in SSH commands to prevent command injection.

### Special Characters Requiring Attention

The following characters require careful escaping when passed through SSH:
- `'` (single quote)
- `"` (double quote)
- `;` (semicolon)
- `$` (dollar sign)
- `` ` `` (backtick)
- `\` (backslash)
- `|` (pipe)
- `&` (ampersand)

### Safe Escaping Patterns

**For single quotes (recommended for most cases):**

```bash
# Escape single quotes by replacing ' with '\''
escaped="${var//\'/\'\\\'\'}"

# Use in command
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli create '${escaped}' --content 'Safe content'"
```

**For double quotes:**

```bash
# Escape double quotes by replacing " with \"
escaped="${var//\"/\\\"}"

# Use in command (wrap outer command in single quotes)
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal 'obsidian-cli search "'"${escaped}"'"'
```

### Anti-Examples (DO NOT USE)

**DO NOT USE - Direct variable interpolation without escaping:**
```bash
# UNSAFE - DO NOT USE
note="User's Note; rm -rf ~"
ssh ... "obsidian-cli create '${note}'"
# This could execute arbitrary commands!
```

**DO NOT USE - Unescaped backticks:**
```bash
# UNSAFE - DO NOT USE
content="Note about `whoami` user"
ssh ... "obsidian-cli create 'Test' --content '${content}'"
# Backticks will be evaluated as command substitution!
```

**DO NOT USE - Unescaped dollar signs:**
```bash
# UNSAFE - DO NOT USE
note="Cost: $100"
ssh ... "obsidian-cli create '${note}'"
# $100 will be interpreted as variable expansion!
```

### Test Command for Escaping Validation

Use this command to verify escaping is working correctly:

```bash
# Test with potentially dangerous input
note="Test'; echo hacked"
escaped="${note//\'/\'\\\'\'}"
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli create '${escaped}' --content 'Test content'"
# SUCCESS: Should create note literally named "Test'; echo hacked"
# FAILURE: If you see "hacked" printed to terminal, escaping failed
```

### Escaping Best Practices

1. **Always escape user input** - Never trust input directly in commands
2. **Use single-quoted strings** - Single quotes prevent most shell interpretation
3. **Test with special characters** - Verify commands handle edge cases
4. **Escape before building command** - Apply escaping to variables, not after concatenation
5. **Check output for injection signs** - Unexpected output may indicate escaping failure

## Common Workflows

The following workflows demonstrate the most frequent operations with obsidian-cli. Each example uses the established SSH command pattern. For complete command documentation, see `references/cli-reference.md`.

### Workflow 1: Create Note with Content

**Use Case:** Create a new note with initial content for capturing ideas, meeting notes, or documentation.

**Example:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli create 'Project Ideas' --content '# Project Ideas\n\nBrainstorm for Q1 initiatives:\n- API redesign\n- Performance optimization'"
```

**Result:** Creates note "Project Ideas.md" in the default vault with the specified markdown content.

**Creating Note in a Folder:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli create 'Projects/Backend/API Redesign' --content '# API Redesign\n\nPlanning document for v2 API'"
```

**Result:** Creates note at `Projects/Backend/API Redesign.md`, creating parent folders if needed.

**Escaping Note:** If the note name contains single quotes, escape them using the pattern from the Shell Escaping section:
```bash
# Note name: "John's Meeting Notes"
note="John's Meeting Notes"
escaped="${note//\'/\'\\\'\'}"
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli create '${escaped}' --content 'Meeting notes content'"
```

---

### Workflow 2: Search Notes by Name

**Use Case:** Find notes matching a search term when you need to locate existing content or verify if a note exists.

**Example:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli search 'architecture'"
```

**Result:** Returns a list of notes with "architecture" in their filename:
```
Notes matching 'architecture':
- System Architecture
- Projects/Backend/Architecture Decisions
- Archive/Old Architecture
```

**Narrowing Search:**
```bash
# Search for more specific term
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli search 'API architecture'"
```

**Using Search Results:** Combine with print to read matching notes:
```bash
# First search
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli search 'meeting'"

# Then print specific note from results
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli print 'Weekly Meeting Notes'"
```

---

### Workflow 3: Read Note Contents

**Use Case:** Retrieve the contents of an existing note for analysis, reference, or incorporation into other work.

**Example:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli print 'Weekly Meeting Notes'"
```

**Result:** Outputs the full markdown content of the note:
```markdown
# Weekly Meeting Notes

## 2025-01-15

### Attendees
- Alice
- Bob

### Action Items
- Complete API review
- Schedule follow-up
```

**Capturing Content for Processing:**
```bash
# Capture note content to a variable
content=$(ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli print 'Project Requirements'" 2>/dev/null)

# Use content in subsequent processing
echo "$content" | grep "Priority:"
```

**Reading Note in Subfolder:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli print 'Projects/Backend/API Spec'"
```

**Escaping Note:** For notes with special characters in the name:
```bash
# Note name: "FAQ's & Tips"
note="FAQ's & Tips"
escaped="${note//\'/\'\\\'\'}"
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli print '${escaped}'"
```

---

### Workflow 4: Create/Open Daily Note

**Use Case:** Create or access today's daily note for journaling, task tracking, or daily standups.

**Example:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli daily"
```

**Result:** Creates today's daily note if it doesn't exist, or confirms it exists. The note is created using the vault's configured daily notes format (typically `YYYY-MM-DD.md` in the daily notes folder).

**Opening Daily Note in Obsidian GUI:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli daily --open"
```

**Result:** Creates (if needed) and opens the daily note in the Obsidian application.

**Note:** The `--open` flag requires the Obsidian application to be running on the macOS host. Use without `--open` when only CLI access is needed.

---

### Workflow 5: Update Frontmatter Field

**Use Case:** Modify metadata in a note's YAML frontmatter, such as status, tags, or custom properties.

**Example:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli set-frontmatter 'Project Roadmap' --key status --value 'in-progress'"
```

**Result:** Updates or adds the `status` field in the note's frontmatter:
```yaml
---
status: in-progress
---
# Project Roadmap
...
```

**Setting Multiple Fields:** Run separate commands for each field:
```bash
# Set status
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli set-frontmatter 'Feature Spec' --key status --value 'review'"

# Set priority
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli set-frontmatter 'Feature Spec' --key priority --value 'high'"

# Set assignee
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli set-frontmatter 'Feature Spec' --key assignee --value 'alice'"
```

**Adding Tags via Frontmatter:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli set-frontmatter 'Meeting Notes' --key tags --value '[meeting, backend, q1]'"
```

**Escaping Note:** For values with special characters:
```bash
# Value containing quotes: "John's Team"
value="John's Team"
escaped_value="${value//\'/\'\\\'\'}"
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli set-frontmatter 'Team Doc' --key owner --value '${escaped_value}'"
```

---

## Multi-Vault Usage

Obsidian CLI supports multiple vaults. By default, commands operate on the configured default vault. You can target specific vaults or change the default as needed.

### Default Vault Workflow (Primary Approach)

Most commands work on the default vault without requiring any vault specification. This is the recommended approach when working primarily with one vault.

**Check Current Default Vault:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli print-default"
```

**Result:**
```
Default vault: Personal Notes
Path: /Users/username/Documents/Obsidian/Personal Notes
```

**Commands Using Default Vault:**
```bash
# All of these use the default vault automatically
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli create 'New Note'"
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli search 'keyword'"
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli print 'Existing Note'"
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli daily"
```

### Explicit Vault Targeting with --vault Flag

When you need to access a vault other than the default, use the `--vault` flag.

**List Available Vaults:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli list-vaults"
```

**Result:**
```
Available vaults:
- Personal Notes (default)
- Work Projects
- Reference Library
```

**Create Note in Specific Vault:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli create 'Q1 Planning' --vault 'Work Projects' --content '# Q1 Planning\n\nObjectives...'"
```

**Search in Specific Vault:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli search 'architecture' --vault 'Work Projects'"
```

**Read Note from Specific Vault:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli print 'API Documentation' --vault 'Reference Library'"
```

**Escaping Vault Names:** If the vault name contains special characters:
```bash
# Vault name: "John's Notes"
vault="John's Notes"
escaped_vault="${vault//\'/\'\\\'\'}"
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli create 'Test Note' --vault '${escaped_vault}'"
```

### Changing Default Vault with set-default

When you need to switch your primary working vault, use the `set-default` command.

**Set New Default Vault:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli set-default 'Work Projects'"
```

**Result:**
```
Default vault set to: Work Projects
```

**Verify Change:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli print-default"
```

**Use Case Scenarios:**
- **Project Context Switching:** When starting work on a project that uses a different vault, set it as default to avoid repeating `--vault` flags
- **Personal vs Work:** Switch default between personal and work vaults based on current focus
- **One-time Access:** Use `--vault` flag for quick access to another vault without changing the default

### Multi-Vault Decision Guide

| Scenario | Approach |
|----------|----------|
| 90% of work in one vault | Set as default, use `--vault` for exceptions |
| Frequent vault switching | Use `--vault` flag explicitly |
| Starting extended work in different vault | Use `set-default` to change default |
| Quick lookup in another vault | Use `--vault` flag |
| Scripting across multiple vaults | Always use explicit `--vault` flag |

## Error Handling

### Common Errors and Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| `ssh: connect to host ... port 22: Connection refused` | SSH not configured | Verify HOST_USER and SSH keys |
| `command not found: obsidian-cli` | CLI not installed on host | Install via Homebrew |
| `Error: No default vault set` | Default vault not configured | Run `obsidian-cli set-default "VaultName"` on host |
| `Error: Note not found` | Note doesn't exist or wrong path | Check note name and folder path |
| `Error: Vault not found` | Invalid vault name | List vaults with `list-vaults` command |

### Handling Output

```bash
# Capture output and check for errors
output=$(ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli create 'MyNote' --content 'Content'" 2>&1)
if [[ $? -ne 0 ]]; then
    echo "Error: ${output}"
else
    echo "Success: Note created"
fi
```

## Reference

For complete command documentation including all options and parameters, see:
`references/cli-reference.md`

## Related

- **worktree-spawn** - SSH command pattern reference
- **maproom-search** - Documentation-based skill pattern
