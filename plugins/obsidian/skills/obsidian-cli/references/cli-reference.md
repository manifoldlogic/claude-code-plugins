# Obsidian CLI Reference

Complete command reference for obsidian-cli (Yakitrak). All commands are executed via SSH from the devcontainer to the macOS host.

**SSH Command Template:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli <command> [options] [arguments]"
```

## Command Summary

| Command | Purpose | Interactive |
|---------|---------|-------------|
| `create` | Create a new note with optional content | No |
| `print` | Read and output note contents | No |
| `search` | Search notes by filename pattern | Yes (without pattern) |
| `delete` | Remove a note from vault | No |
| `move` | Move or rename a note | No |
| `append` | Add content to end of existing note (via create --append) | No |
| `frontmatter` | View and modify YAML metadata fields | No |
| `open` | Open note in Obsidian application | No (requires GUI) |
| `daily` | Create or open today's daily note | No |
| `print-default` | Show the default vault name and path | No |
| `set-default` | Change the default vault | No |

**Interactive Column:** Commands marked "Yes" launch interactive fuzzy finders when used without a search pattern. These do not work over SSH non-interactive sessions.

---

## Global Options

These options are available for most commands:

| Option | Description |
|--------|-------------|
| `--vault <name>` | Target a specific vault instead of the default |
| `--help` | Display help information for the command |
| `--version` | Display obsidian-cli version |

---

## Note Management

### create

**Purpose:** Create a new note with optional content in the vault.

**Syntax:**
```
obsidian-cli create <note-name> [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--content <text>` | Initial content for the note |
| `--vault <name>` | Target vault (uses default if not specified) |
| `--overwrite` | Replace existing note with same name |
| `--open` | Open note in Obsidian after creation |
| `--editor` / `-e` | Open note in default text editor |

**Example 1: Basic note creation**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli create 'Project Plan' --content '# Project Plan\n\nObjectives:\n- Item 1\n- Item 2'"
```
**Result:** Creates note with markdown header and bullet list

**Example 2: Multi-vault note creation**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli create 'Q1 Goals' --vault 'Work Projects' --content '# Team Objectives\n\nQuarterly goals for the engineering team'"
```
**Result:** Creates note in "Work Projects" vault instead of the default vault

**Example 3: Note name with special characters**
```bash
note_name="John's Meeting Notes"
escaped="${note_name//\'/\'\\\'\'}"
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli create '${escaped}' --content '# Meeting Notes\n\nAttendees: John, Sarah'"
```
**Escaping Note:** Single quotes in note names require escaping. See [SKILL.md Shell Escaping section](../SKILL.md#shell-escaping-critical).

**Creating in Subfolder:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli create 'Projects/Backend/API Design' --content '# API Design'"
```

**Error Scenario - Note Already Exists:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli create 'Existing Note' --content 'New content'"
```
**Result:** May return error if note exists. Use `--overwrite` flag to replace, or use `--append` to add to existing note.

---

### print

**Purpose:** Read and output the contents of an existing note to stdout.

**Syntax:**
```
obsidian-cli print <note-name> [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--vault <name>` | Target vault (uses default if not specified) |

**Example 1: Basic note reading**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli print 'Meeting Notes'"
```
**Result:** Outputs full note contents including frontmatter to stdout

**Example 2: Multi-vault note reading**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli print 'Team Roadmap' --vault 'Work Projects'"
```
**Result:** Reads note from "Work Projects" vault instead of the default vault

**Example 3: Note name with special characters**
```bash
note_name="John's API Notes"
escaped="${note_name//\'/\'\\\'\'}"
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli print '${escaped}'"
```

**Reading from Subfolder:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli print 'Projects/Backend/API Design'"
```

**Capturing Content for Processing:**
```bash
content=$(ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli print 'Project Requirements'" 2>/dev/null)

# Use content in script
if [ -n "$content" ]; then
  echo "Note found with $(echo "$content" | wc -l) lines"
fi
```

**Error Scenario - Note Not Found:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli print 'Nonexistent Note'"
```
**Result:** Returns `Note not found` error. Use `search` first to verify note name exists.

**Escaping Note:** Apply shell escaping to note names containing special characters.

---

### delete

**Purpose:** Permanently remove a note from the vault.

**Syntax:**
```
obsidian-cli delete <note-name> [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--vault <name>` | Target vault (uses default if not specified) |

**Example 1: Basic deletion**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli delete 'Old Draft'"
```
**Result:** Permanently removes note from the vault

**Example 2: Multi-vault deletion**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli delete 'Archived Spec' --vault 'Work Projects'"
```
**Result:** Deletes note from "Work Projects" vault instead of the default vault

**Example 3: Deleting note with special characters**
```bash
note_name="John's Old Notes"
escaped="${note_name//\'/\'\\\'\'}"
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli delete '${escaped}'"
```

**Deleting from Subfolder:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli delete 'Archive/Deprecated/Old API Spec'"
```

**Warning:** This operation is permanent. The note is deleted from the filesystem, not moved to trash.

**Error Scenario - Note Not Found:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli delete 'Nonexistent Note'"
```
**Result:** Returns `Note not found` error. Use `search` first to verify note exists before deletion.

**Escaping Note:** Apply shell escaping to note names containing special characters.

---

### move

**Purpose:** Move or rename a note within the vault. Automatically updates internal vault links.

**Syntax:**
```
obsidian-cli move <current-path> <new-path> [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--vault <name>` | Target vault (uses default if not specified) |
| `--open` | Open note in Obsidian after moving |
| `--editor` / `-e` | Open note in default text editor after moving |

**Example 1: Simple rename**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli move 'Draft Document' 'Final Document'"
```
**Result:** Renames note and updates all `[[Draft Document]]` links to `[[Final Document]]`

**Example 2: Multi-vault move with folder reorganization**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli move 'Inbox/New Idea' 'Projects/Active/New Idea' --vault 'Work Projects'"
```
**Result:** Moves note from Inbox folder to Projects/Active folder within "Work Projects" vault

**Example 3: Note name with special characters**
```bash
old_name="John's Meeting Notes"
new_name="John's Meeting Notes (Archived)"
old_escaped="${old_name//\'/\'\\\'\'}"
new_escaped="${new_name//\'/\'\\\'\'}"
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli move '${old_escaped}' '${new_escaped}'"
```
**Escaping Note:** Both source and destination paths require escaping if they contain special characters.

**Link Updates:** When moving notes, obsidian-cli automatically updates any internal links (`[[Note Name]]`) that reference the moved note.

**Error Scenario - Source Not Found:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli move 'Nonexistent Note' 'New Location'"
```
**Result:** Returns `Note not found` error. Use `search` to verify source note exists.

**Error Scenario - Destination Exists:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli move 'Source Note' 'Existing Note'"
```
**Result:** May return error if destination note already exists. Rename the destination first or choose a different name.

---

## Content Operations

### append

**Purpose:** Add content to the end of an existing note.

**Syntax:**
```
obsidian-cli create <note-name> --append --content <text> [options]
```

**Note:** Append is implemented via the `create` command with the `--append` flag.

**Options:**

| Option | Description |
|--------|-------------|
| `--content <text>` | Content to append (required) |
| `--append` | Append mode flag (required) |
| `--vault <name>` | Target vault (uses default if not specified) |

**Example 1: Basic append**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli create 'Meeting Notes' --append --content '\n\n## New Section\n\nAdditional content here'"
```
**Result:** Adds new section at the end of the note

**Example 2: Multi-vault append with timestamp**
```bash
# Generate timestamp on local machine before SSH
timestamp=$(date +%H:%M)
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli create 'Activity Log' --vault 'Work Projects' --append --content '\n\n### ${timestamp}\n\nCompleted task review'"
```
**Result:** Appends timestamped entry to log in "Work Projects" vault. Note: timestamp is captured locally before the SSH command.

**Example 3: Long content with multiple paragraphs**
```bash
content="## API Review Summary

### Endpoints Reviewed
- /api/users - OK
- /api/products - Needs refactoring
- /api/orders - OK

### Next Steps
1. Refactor products endpoint
2. Add rate limiting
3. Update documentation"

# Escape newlines for SSH transport
escaped_content="${content//$'\n'/\\n}"

ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli create 'Sprint Notes' --append --content '\n\n${escaped_content}'"
```
**Result:** Appends multi-paragraph content with preserved formatting

**Example with Special Characters:**
```bash
content="John's notes: \"Important\" findings & conclusions"
escaped="${content//\'/\'\\\'\'}"
escaped="${escaped//\"/\\\"}"
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli create 'Research Log' --append --content '\n\n${escaped}'"
```
**Escaping Note:** Multiple special characters require sequential escaping. See [SKILL.md Shell Escaping section](../SKILL.md#shell-escaping-critical).

**Error Scenario - Note Does Not Exist:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli create 'Nonexistent Note' --append --content 'New content'"
```
**Result:** Behavior depends on CLI version - may create new note or return error. Use `search` first to verify note exists, or use `create` without `--append` if note does not exist.

---

### frontmatter

**Purpose:** Update or add YAML frontmatter fields in a note.

**Syntax:**
```
obsidian-cli frontmatter <note-name> --edit --key <field> --value <value> [options]
```

**Alias:** `fm`

**Options:**

| Option | Description |
|--------|-------------|
| `--edit` | Enable edit mode (required for updates) |
| `--key <field>` | Frontmatter field name to update |
| `--value <value>` | New value for the field |
| `--print` | Display current frontmatter |
| `--delete` | Delete a frontmatter field (use with `--key`) |
| `--vault <name>` | Target vault (uses default if not specified) |

**Example 1: Set a simple field**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli frontmatter 'Project Spec' --edit --key status --value 'in-progress'"
```
**Result:** Sets `status: in-progress` in the note's frontmatter

**Example 2: Multi-vault frontmatter update**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli frontmatter 'Team OKRs' --vault 'Work Projects' --edit --key quarter --value 'Q1-2024'"
```
**Result:** Updates frontmatter in note within "Work Projects" vault

**Example 3: Value with special characters**
```bash
value="John's API Design: Phase 1"
escaped="${value//\'/\'\\\'\'}"
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli frontmatter 'Project Spec' --edit --key description --value '${escaped}'"
```
**Escaping Note:** Single quotes in values require special handling to avoid shell interpretation.

**View Frontmatter:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli frontmatter 'Project Spec' --print"
```
**Output:**
```yaml
---
status: in-progress
tags: [api, backend]
created: 2024-01-15
---
```

**Delete Field:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli frontmatter 'Project Spec' --delete --key deprecated"
```

**Setting Tags (Array Value):**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli frontmatter 'Meeting Notes' --edit --key tags --value '[meeting, backend, q1]'"
```

**Setting Multiple Fields:** Run separate commands for each field:
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli frontmatter 'Feature Spec' --edit --key status --value 'review'"

ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli frontmatter 'Feature Spec' --edit --key priority --value 'high'"
```

**Error Scenario - Note Not Found:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli frontmatter 'Nonexistent Note' --edit --key status --value 'done'"
```
**Result:** Returns `Note not found` error. Use `search` to verify the note exists before updating.

---

## Search and Discovery

### search

**Purpose:** Search for notes by filename pattern.

**Syntax:**
```
obsidian-cli search [pattern] [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--vault <name>` | Target vault (uses default if not specified) |
| `--editor` / `-e` | Open selected note in text editor |

**Example 1: Basic filename search**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli search 'architecture'"
```
**Result:** Returns all notes with "architecture" in the filename

**Output Format:**
```
Notes matching 'architecture':
- System Architecture
- Projects/Backend/Architecture Decisions
- Archive/Old Architecture
```

**Example 2: Multi-vault search**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli search 'meeting' --vault 'Work Projects'"
```
**Result:** Searches only in "Work Projects" vault instead of the default vault

**Example 3: Search pattern with special characters**
```bash
pattern="Q1/Q2 Review"
escaped="${pattern//\//\\/}"
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli search '${escaped}'"
```
**Escaping Note:** Forward slashes may be interpreted as path separators; escape them if searching for literal characters.

**Interactive Mode Limitation:** When called without a pattern, `search` launches an interactive fuzzy finder. This does **NOT** work over SSH non-interactive sessions. Always provide a search pattern when using SSH.

**Content Search:** Use `search-content` for searching within note contents:
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli search-content 'API endpoint'"
```

**Error Scenario - No Matches:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli search 'nonexistent-pattern'"
```
**Result:** Returns empty result set (no error, just no matches). Check spelling or try broader search terms.

---

## Workflow Commands

### daily

**Purpose:** Create or open today's daily note using the vault's daily notes configuration.

**Syntax:**
```
obsidian-cli daily [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--vault <name>` | Target vault (uses default if not specified) |
| `--open` | Open daily note in Obsidian application |

**Example 1: Create/access today's daily note**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli daily"
```
**Result:** Creates today's daily note if it does not exist, or returns path to existing note. Uses vault's daily notes configuration for naming and templates.

**Example 2: Multi-vault daily notes**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli daily --vault 'Work Projects'"
```
**Result:** Creates/accesses daily note in "Work Projects" vault (useful for keeping personal and work daily notes separate)

**Example 3: Open daily note in Obsidian**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli daily --open"
```
**Result:** Creates daily note if needed and opens it in the Obsidian application

**Note:** The `--open` flag requires the Obsidian application to be running on the macOS host.

**Daily Note Format:** Uses the vault's configured daily notes format (typically `YYYY-MM-DD.md` in the daily notes folder). Templates are applied if configured.

**Appending to Daily Note:**
To add content to today's daily note, combine with append:
```bash
# First ensure daily note exists
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli daily"

# Get today's date in your vault's format (example: YYYY-MM-DD)
today=$(date +%Y-%m-%d)

# Append to it
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli create '${today}' --append --content '\n\n## New Entry\n\nContent here'"
```
**Note:** Daily note naming depends on vault configuration. Adjust date format to match.

---

### open

**Purpose:** Open a specific note in the Obsidian application.

**Syntax:**
```
obsidian-cli open <note-name> [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--vault <name>` | Target vault (uses default if not specified) |

**SSH Example:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli open 'Project Roadmap'"
```

**Opening from Subfolder:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli open 'Projects/Active/Sprint Planning'"
```

**Requirement:** The Obsidian application must be running on the macOS host for this command to work. If Obsidian is not running, it will be launched.

**Escaping Note:** Apply shell escaping to note names containing special characters.

---

## Vault Configuration

### print-default

**Purpose:** Display the currently configured default vault name and path.

**Syntax:**
```
obsidian-cli print-default [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--path-only` | Output only the vault directory path |

**SSH Example:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli print-default"
```

**Output Format:**
```
Default vault: Personal Notes
Path: /Users/username/Documents/Obsidian/Personal Notes
```

**Path Only:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli print-default --path-only"
```

**Output:**
```
/Users/username/Documents/Obsidian/Personal Notes
```

---

### set-default

**Purpose:** Change the default vault used by obsidian-cli commands.

**Syntax:**
```
obsidian-cli set-default <vault-name>
```

**SSH Example:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli set-default 'Work Projects'"
```

**Output:**
```
Default vault set to: Work Projects
```

**Note:** Use the vault name, not the full path. List available vaults with:
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli list-vaults"
```

**Escaping Note:** Apply shell escaping to vault names containing special characters.

---

## Additional Commands

### list-vaults

**Purpose:** Display all registered Obsidian vaults.

**Syntax:**
```
obsidian-cli list-vaults
```

**SSH Example:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli list-vaults"
```

**Output Format:**
```
Available vaults:
- Personal Notes (default)
- Work Projects
- Reference Library
```

---

### search-content

**Purpose:** Search for notes by content (full-text search).

**Syntax:**
```
obsidian-cli search-content <pattern> [options]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--vault <name>` | Target vault (uses default if not specified) |

**SSH Example:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli search-content 'API endpoint'"
```

**Output:** Returns matching notes with line numbers and content snippets.

**Interactive Mode:** When called without a pattern, launches an interactive fuzzy finder. This does **NOT** work over SSH.

---

## Shell Escaping Quick Reference

For commands with user input (note names, content, values), always escape special characters:

**Escaping Single Quotes:**
```bash
note="John's Meeting Notes"
escaped="${note//\'/\'\\\'\'}"
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli create '${escaped}'"
```

**Characters Requiring Escaping:**
- `'` (single quote)
- `"` (double quote)
- `;` (semicolon)
- `$` (dollar sign)
- `` ` `` (backtick)
- `\` (backslash)
- `|` (pipe)
- `&` (ampersand)

**Full Documentation:** See [SKILL.md Shell Escaping section](../SKILL.md#shell-escaping-critical) for complete patterns and anti-examples.

---

## Error Reference

| Error | Likely Cause | Resolution |
|-------|--------------|------------|
| `Note not found` | Note does not exist | Use `search` to verify name |
| `Vault not found` | Invalid vault name | Use `list-vaults` to check names |
| `No default vault set` | Default not configured | Run `set-default` |
| `Permission denied` | File access issue | Check vault directory permissions |
| `command not found: obsidian-cli` | CLI not installed on host | Install via Homebrew |

---

## Related Documentation

- [SKILL.md](../SKILL.md) - Main skill documentation with workflows and troubleshooting
- [SSH Command Pattern](../SKILL.md#ssh-command-pattern) - Template for all commands
- [Shell Escaping](../SKILL.md#shell-escaping-critical) - Critical security guidance
- [Error Handling](../SKILL.md#error-handling) - Detailed error resolution
