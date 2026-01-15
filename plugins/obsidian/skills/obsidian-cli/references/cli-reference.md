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
| `append` | Add content to end of existing note | No |
| `prepend` | Add content to beginning of existing note | No |
| `set-frontmatter` | Update YAML metadata fields | No |
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

**SSH Example:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli create 'Project Plan' --content '# Project Plan\n\nObjectives:\n- Item 1\n- Item 2'"
```

**Creating in Subfolder:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli create 'Projects/Backend/API Design' --content '# API Design'"
```

**Escaping Note:** Apply shell escaping to note names and content containing special characters. See [SKILL.md Shell Escaping section](../SKILL.md#shell-escaping-critical).

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

**SSH Example:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli print 'Meeting Notes'"
```

**Reading from Subfolder:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli print 'Projects/Backend/API Design'"
```

**Capturing Content:**
```bash
content=$(ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli print 'Project Requirements'" 2>/dev/null)
```

**Error Handling:** Returns error if note does not exist. Use `search` first to verify note name.

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

**SSH Example:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli delete 'Old Draft'"
```

**Deleting from Subfolder:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli delete 'Archive/Deprecated/Old API Spec'"
```

**Warning:** This operation is permanent. The note is deleted from the filesystem, not moved to trash.

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

**SSH Example (Rename):**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli move 'Draft Document' 'Final Document'"
```

**SSH Example (Move to Folder):**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli move 'Inbox/New Idea' 'Projects/Active/New Idea'"
```

**Link Updates:** When moving notes, obsidian-cli automatically updates any internal links (`[[Note Name]]`) that reference the moved note.

**Escaping Note:** Apply shell escaping to paths containing special characters.

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

**SSH Example:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli create 'Meeting Notes' --append --content '\n\n## New Section\n\nAdditional content here'"
```

**Appending with Timestamp:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli create 'Daily Log' --append --content '\n\n### $(date +%H:%M)\n\nNew entry'"
```

**Escaping Note:** Apply shell escaping to note names and content containing special characters. See [SKILL.md Shell Escaping section](../SKILL.md#shell-escaping-critical).

---

### prepend

**Purpose:** Add content to the beginning of an existing note (after frontmatter if present).

**Syntax:**
```
obsidian-cli create <note-name> --prepend --content <text> [options]
```

**Note:** Prepend functionality may be implemented via the `create` command with a `--prepend` flag. Verify availability with `obsidian-cli create --help`.

**Options:**

| Option | Description |
|--------|-------------|
| `--content <text>` | Content to prepend (required) |
| `--prepend` | Prepend mode flag (required) |
| `--vault <name>` | Target vault (uses default if not specified) |

**SSH Example:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli create 'Project Log' --prepend --content '## Latest Update\n\nNew content at top\n\n'"
```

**Alternative Approach:** If `--prepend` is not available, read the note content with `print`, prepend content manually, and use `create --overwrite` to replace.

**Escaping Note:** Apply shell escaping to note names and content containing special characters.

---

### set-frontmatter

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

**SSH Example (Set Field):**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli frontmatter 'Project Spec' --edit --key status --value 'in-progress'"
```

**SSH Example (View Frontmatter):**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli frontmatter 'Project Spec' --print"
```

**SSH Example (Delete Field):**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli frontmatter 'Project Spec' --delete --key deprecated"
```

**Setting Tags:**
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

**Escaping Note:** Apply shell escaping to note names, keys, and values containing special characters.

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

**SSH Example:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli search 'architecture'"
```

**Interactive Mode:** When called without a pattern, `search` launches an interactive fuzzy finder. This does **NOT** work over SSH non-interactive sessions.

**Output Format:**
```
Notes matching 'architecture':
- System Architecture
- Projects/Backend/Architecture Decisions
- Archive/Old Architecture
```

**Content Search:** Use `search-content` for searching within note contents:
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli search-content 'API endpoint'"
```

**Escaping Note:** Apply shell escaping to search patterns containing special characters.

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

**SSH Example:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli daily"
```

**Opening in Obsidian:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli daily --open"
```

**Note:** The `--open` flag requires the Obsidian application to be running on the macOS host.

**Daily Note Format:** Uses the vault's configured daily notes format (typically `YYYY-MM-DD.md` in the daily notes folder). Templates are applied if configured.

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
