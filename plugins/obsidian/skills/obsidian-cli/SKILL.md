---
name: obsidian-cli
description: Manage Obsidian vault notes using obsidian-cli from a devcontainer environment via SSH to macOS host
---

# Obsidian CLI Skill

**Last Updated:** 2026-01-15
**CLI Tool:** obsidian-cli (Yakitrak)

## Overview

The obsidian-cli tool provides command-line access to Obsidian vaults, enabling note creation, search, content retrieval, and vault management without opening the Obsidian GUI application.

This skill enables Claude Code to interact with Obsidian vaults on the macOS host from within a devcontainer environment. Commands are executed via SSH tunneling using the established host-communication pattern.

**Capabilities:**
- Create new notes with specified content and frontmatter
- Search notes by filename or content patterns
- Retrieve note content for analysis or modification
- Manage vault defaults
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

**Note on PATH:** Non-interactive SSH sessions may not load the full shell profile, so Homebrew's PATH may not be available. If `obsidian-cli` is not found, use the full path:
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "/opt/homebrew/bin/obsidian-cli <command> [arguments]"
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

# Search note content (search by filename is interactive-only)
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli search-content 'keyword'"

# Print note content
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli print 'My Note'"

# Check default vault
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli print-default"
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

### Workflow 2: Search Note Content

**Use Case:** Find notes containing specific text when you need to locate existing content or verify if information exists in the vault.

**Important:** The `search` command (filename search) is interactive-only and cannot be used over SSH. Use `search-content` for programmatic searching.

**Example:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli search-content 'architecture'"
```

**Result:** Returns notes containing "architecture" in their content, then opens an interactive selector. Over SSH, this will find matches but may not complete interactively.

**Alternative - Direct File Search:**
If you know the vault path, you can search files directly:
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "grep -rl 'architecture' '/Users/username/Obsidian/VaultName'"
```

**Using Search Results:** Once you identify a note name, use print to read it:
```bash
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
  "obsidian-cli frontmatter 'Project Roadmap' --edit --key status --value 'in-progress'"
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
  "obsidian-cli frontmatter 'Feature Spec' --edit --key status --value 'review'"

# Set priority
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli frontmatter 'Feature Spec' --edit --key priority --value 'high'"

# Set assignee
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli frontmatter 'Feature Spec' --edit --key assignee --value 'alice'"
```

**Adding Tags via Frontmatter:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli frontmatter 'Meeting Notes' --edit --key tags --value '[meeting, backend, q1]'"
```

**Escaping Note:** For values with special characters:
```bash
# Value containing quotes: "John's Team"
value="John's Team"
escaped_value="${value//\'/\'\\\'\'}"
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli frontmatter 'Team Doc' --edit --key owner --value '${escaped_value}'"
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
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli search-content 'keyword'"
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli print 'Existing Note'"
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli daily"
```

### Explicit Vault Targeting with --vault Flag

When you need to access a vault other than the default, use the `--vault` flag.

**Find Available Vaults:**
Obsidian stores vault information in `~/Library/Application Support/obsidian/obsidian.json` on macOS:
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "cat ~/Library/Application\ Support/obsidian/obsidian.json"
```

**Create Note in Specific Vault:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli create 'Q1 Planning' --vault 'Work Projects' --content '# Q1 Planning\n\nObjectives...'"
```

**Search Content in Specific Vault:**
```bash
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal \
  "obsidian-cli search-content 'architecture' --vault 'Work Projects'"
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

## Limitations

### Interactive Commands Over SSH

Commands that require interactive input (fuzzy finders, prompts) do not work over SSH non-interactive sessions. The SSH connection from the devcontainer is non-interactive, meaning it cannot display or receive input from terminal UI elements.

**Not Available Over SSH:**
- `obsidian-cli search` - Always launches interactive fuzzy finder (does NOT accept a search pattern argument)
- `obsidian-cli search-content` - Also interactive; while it accepts a pattern, it opens a fuzzy finder to select from matches
- Interactive vault selection prompts
- Any command that requires user confirmation prompts

**Alternatives:**
- Use `search-content "pattern"` to find matches (may partially work for finding matches, but selection is interactive)
- Use direct file search with `grep` if you know the vault path
- Use the `--vault "Name"` flag to target specific vaults explicitly
- Configure a default vault with `set-default` to avoid vault selection prompts

**Why SSH Limits Interactivity:**
SSH sessions from the devcontainer do not allocate a pseudo-terminal (PTY) by default, which is required for interactive TUI components like fuzzy finders. Adding `-t` to force PTY allocation does not resolve this since the container-side terminal cannot display the host's TUI.

## Error Handling

This section documents common error scenarios, their causes, and resolution steps. Each error includes the error message pattern to help identify the issue.

### SSH Connection Refused

**Error Pattern:**
```
ssh: connect to host host.docker.internal port 22: Connection refused
```

**Likely Cause:** The `HOST_USER` environment variable is not set or the SSH server on the macOS host is not running/accessible.

**Resolution:**
1. Verify HOST_USER is set in your devcontainer configuration:
   ```bash
   echo $HOST_USER
   ```
2. If empty, add to `.devcontainer/devcontainer.json` under `remoteEnv`:
   ```json
   "remoteEnv": {
     "HOST_USER": "${localEnv:USER}"
   }
   ```
3. Rebuild the container: **Dev Containers: Rebuild Container**
4. Verify SSH is enabled on macOS: **System Preferences > Sharing > Remote Login**
5. Test connectivity:
   ```bash
   ssh -o BatchMode=yes -o ConnectTimeout=5 ${HOST_USER}@host.docker.internal "echo OK"
   ```

---

### SSH Permission Denied

**Error Pattern:**
```
Permission denied (publickey,password).
```
or
```
Warning: Identity file /home/vscode/.ssh/id_ed25519 not accessible: No such file or directory.
```

**Likely Cause:** SSH keys are not mounted into the container, or the key file has incorrect permissions.

**Resolution:**
1. Verify SSH key exists in the container:
   ```bash
   ls -la ~/.ssh/id_ed25519
   ```
2. If missing, ensure keys are mounted in `.devcontainer/devcontainer.json`:
   ```json
   "mounts": [
     "source=${localEnv:HOME}/.ssh,target=/home/vscode/.ssh,type=bind,readonly"
   ]
   ```
3. Check key permissions (must be 600):
   ```bash
   chmod 600 ~/.ssh/id_ed25519
   ```
4. Verify the key is authorized on the host:
   ```bash
   # On macOS host, ensure your public key is in:
   cat ~/.ssh/authorized_keys
   ```
5. Rebuild container after mount configuration changes

---

### Command Not Found: obsidian-cli

**Error Pattern:**
```
bash: obsidian-cli: command not found
```
or
```
zsh: command not found: obsidian-cli
```

**Likely Cause:** The obsidian-cli tool is not installed on the macOS host.

**Resolution:**
1. Install obsidian-cli on the **macOS host** (not in the container):
   ```bash
   # Run these commands directly on macOS, not through SSH
   brew tap yakitrak/yakitrak
   brew install yakitrak/yakitrak/obsidian-cli
   ```
2. Verify installation:
   ```bash
   ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "which obsidian-cli"
   ```
3. If `which` returns a path, the installation succeeded
4. If using a non-standard shell on macOS, ensure the PATH includes Homebrew binaries

---

### No Default Vault Set

**Error Pattern:**
```
Error: No default vault set
```
or
```
Error: Please specify a vault or set a default vault
```

**Likely Cause:** obsidian-cli requires a default vault to be configured when not using the `--vault` flag.

**Resolution:**
1. Find available vaults from Obsidian config:
   ```bash
   ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "cat ~/Library/Application\ Support/obsidian/obsidian.json"
   ```
2. Set a default vault (use the vault name from the path):
   ```bash
   ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli set-default 'Your Vault Name'"
   ```
3. Verify the default is set:
   ```bash
   ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli print-default"
   ```
4. Alternative: Use `--vault "Name"` flag with each command instead of setting a default

---

### Note Not Found

**Error Pattern:**
```
Error: Note not found
```
or
```
Error: Note 'NoteName' does not exist
```

**Likely Cause:** The specified note does not exist in the vault, or the path/name is incorrect.

**Resolution:**
1. Search for the note using grep on the vault directory:
   ```bash
   ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "find /path/to/vault -name '*partial-name*' -type f"
   ```
2. Check if the note is in a subfolder (include the path):
   ```bash
   # Instead of 'MyNote', try:
   ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli print 'Folder/Subfolder/MyNote'"
   ```
3. Verify you're targeting the correct vault:
   ```bash
   ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli print-default"
   ```
4. Note names are case-sensitive - ensure exact capitalization

---

### Vault Not Found

**Error Pattern:**
```
Error: Vault not found
```
or
```
Error: Vault 'VaultName' does not exist
```

**Likely Cause:** The specified vault name in the `--vault` flag does not match any registered Obsidian vault.

**Resolution:**
1. Find available vaults from Obsidian config:
   ```bash
   ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "cat ~/Library/Application\ Support/obsidian/obsidian.json"
   ```
2. Use the exact vault name (the folder name from the path, case-sensitive)
3. If the vault was recently created, ensure Obsidian has been opened to register it
4. Check for typos or extra spaces in the vault name

---

### Permission Denied on Vault

**Error Pattern:**
```
Error: Permission denied
```
or
```
Error: EACCES: permission denied, open '/path/to/vault/note.md'
```

**Likely Cause:** The user account on macOS does not have read/write access to the vault directory.

**Resolution:**
1. Check vault path permissions on macOS:
   ```bash
   ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "ls -la '/path/to/vault'"
   ```
2. Verify your user owns or has access to the vault directory
3. If the vault is on an external drive, ensure it's mounted and accessible
4. For iCloud-synced vaults, ensure the files are downloaded (not cloud-only)
5. Fix permissions if needed:
   ```bash
   # On macOS host
   chmod -R u+rw "/path/to/vault"
   ```

---

### Shell Escaping Failures

**Error Pattern:**
- Unexpected command output
- "hacked" or other injected text appearing in terminal
- Note created with truncated or wrong name
- Errors about unexpected tokens

**Likely Cause:** User-provided input (note names, content) contains special characters that weren't properly escaped.

**Resolution:**
1. Always escape single quotes in user input:
   ```bash
   escaped="${var//\'/\'\\\'\'}"
   ```
2. Test escaping with the validation command:
   ```bash
   note="Test'; echo hacked"
   escaped="${note//\'/\'\\\'\'}"
   ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli create '${escaped}' --content 'Test content'"
   # SUCCESS: Should create note literally named "Test'; echo hacked"
   # FAILURE: If you see "hacked" printed to terminal, escaping failed
   ```
3. Review the Shell Escaping section above for proper patterns
4. Never interpolate user input directly into commands without escaping

### Handling Output Programmatically

```bash
# Capture output and check for errors
output=$(ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "obsidian-cli create 'MyNote' --content 'Content'" 2>&1)
if [[ $? -ne 0 ]]; then
    echo "Error: ${output}"
else
    echo "Success: Note created"
fi
```

## Troubleshooting

This section organizes common issues by symptom for quick diagnosis.

### SSH Issues

**Symptom: "Connection refused" when running any command**
- Cause: SSH server not running on macOS or HOST_USER not set
- Solution: See [SSH Connection Refused](#ssh-connection-refused) above

**Symptom: "Permission denied" immediately after SSH attempt**
- Cause: SSH keys not mounted or incorrect permissions
- Solution: See [SSH Permission Denied](#ssh-permission-denied) above

**Symptom: SSH hangs without response**
- Cause: Network connectivity issue or firewall blocking
- Solution: Check Docker network configuration; verify `host.docker.internal` resolves:
  ```bash
  ping -c 1 host.docker.internal
  ```

### CLI Issues

**Symptom: Commands work on macOS but fail from container**
- Cause: Different shell environment or PATH issues
- Solution: Use full path to obsidian-cli:
  ```bash
  ssh ... "/opt/homebrew/bin/obsidian-cli print-default"
  ```

**Symptom: Note content appears garbled or truncated**
- Cause: Special characters in content not properly escaped
- Solution: Apply escaping patterns from Shell Escaping section; use single quotes

**Symptom: Command runs but nothing happens (silent failure)**
- Cause: Command succeeded but output not captured, or note created in unexpected location
- Solution: Add error checking to capture stderr:
  ```bash
  output=$(ssh ... "obsidian-cli create 'Note'" 2>&1)
  echo "$output"
  ```

### Vault Issues

**Symptom: "No default vault set" on every command**
- Cause: Default vault not configured
- Solution: See [No Default Vault Set](#no-default-vault-set) above

**Symptom: Notes appear in wrong vault**
- Cause: Default vault is different than expected
- Solution: Always verify current default before operations:
  ```bash
  ssh ... "obsidian-cli print-default"
  ```

**Symptom: Vault shows in Obsidian but obsidian-cli can't find it**
- Cause: obsidian-cli uses the vault name (folder name), not the full path
- Solution: Check Obsidian's config for exact vault names:
  ```bash
  ssh ... "cat ~/Library/Application\ Support/obsidian/obsidian.json"
  ```

### Quick Diagnostic Commands

Run these commands to quickly diagnose common issues:

```bash
# 1. Check HOST_USER is set
echo "HOST_USER: $HOST_USER"

# 2. Test basic SSH connectivity
ssh -o BatchMode=yes -o ConnectTimeout=5 ${HOST_USER}@host.docker.internal "echo SSH OK"

# 3. Verify SSH key exists and has correct permissions
ls -la ~/.ssh/id_ed25519

# 4. Check obsidian-cli is installed (use full path if 'which' fails)
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "which obsidian-cli || /opt/homebrew/bin/obsidian-cli --version"

# 5. Verify default vault
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "/opt/homebrew/bin/obsidian-cli print-default"

# 6. Find available vaults from Obsidian config
ssh -i ~/.ssh/id_ed25519 ${HOST_USER}@host.docker.internal "cat ~/Library/Application\ Support/obsidian/obsidian.json"
```

## Reference

For complete command documentation including all options and parameters, see:
`references/cli-reference.md`

## Related

- **worktree-spawn** - SSH command pattern reference
- **maproom-search** - Documentation-based skill pattern
