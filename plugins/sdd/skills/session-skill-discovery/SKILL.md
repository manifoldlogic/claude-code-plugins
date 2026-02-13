---
name: session-skill-discovery
description: Analyze session transcript logs to identify genuine reusable skill candidates across multiple tickets and sessions
origin: SKILLLOG
created: 2026-02-13
tags: [skills, discovery, transcripts, analysis, cross-ticket]
---

# Session Skill Discovery

## Overview

Session transcripts contain a wealth of procedural patterns that agents follow repeatedly across tickets and projects. Phase 1 hooks (registered via `log-session-transcript.py`) capture transcript references to `${SDD_ROOT_DIR}/logs/session-transcripts/` whenever sessions compact or end. These logs form a raw dataset of agent behavior, but the vast majority of patterns within them are noise -- trivial commands, general knowledge application, and standard tool usage that would not benefit from formal documentation as a skill.

This skill guides agents through a structured methodology for mining those session transcript logs to identify genuine reusable skill candidates. The emphasis is on quality over quantity: a successful analysis session might yield zero new skill candidates, and that is a valid outcome. The goal is to surface only those patterns that meet strict quality gates -- patterns that are multi-step, cross-project, non-trivial, and not already covered by existing skills or standard documentation.

This is a Reference Skill (methodology/procedure). Agents read this skill and follow the procedure using their own tool access (Read, Grep, Glob) to analyze transcripts. There is no automation or executable script associated with this skill.

## When to Use

Apply this methodology when:

- **After archiving multiple tickets**: Analyze recent sessions to identify cross-ticket patterns that emerged during the work but were not captured as skills within any single ticket
- **During quarterly skill review**: Mine historical session data accumulated over weeks or months to find patterns with long-term reuse value
- **When exploring cross-project patterns**: Investigate patterns that span multiple plugins, repositories, or problem domains -- patterns not visible within the scope of a single ticket
- **When session log volume warrants analysis**: After 10+ session transcript logs have accumulated, indicating sufficient data for meaningful pattern extraction
- **After completing a multi-ticket epic**: Review all sessions from an epic to identify workflow patterns that emerged across the full lifecycle
- **When prompted by `/sdd:curate-skills` output**: If single-ticket curation identifies a pattern that appears to have broader applicability, use this skill to validate it against cross-session evidence

### When NOT to Use

- **During active ticket work**: Skill discovery is a post-completion activity. Do not interrupt ticket execution to mine transcripts.
- **For single-ticket patterns**: Use the existing `/sdd:curate-skills` workflow instead. That workflow handles within-ticket skill extraction and does not require cross-session analysis.
- **Expecting automated skill creation**: This skill documents an analysis methodology, not an automation pipeline. The output is a set of validated skill candidates that must be manually authored following `skill-creation-workflow.md`.

## Pattern/Procedure

### Step 1: Scan the Log Directory

Locate and inventory session transcript log files.

**Log directory:** `${SDD_ROOT_DIR}/logs/session-transcripts/`

**File naming convention:** `{session_id}_{event}_{timestamp}.json`

Where:
- `session_id` is the Claude Code session identifier (e.g., `abc123`)
- `event` is the hook event that triggered the log (e.g., `PreCompact`, `Stop`)
- `timestamp` is an ISO 8601 timestamp with microseconds (e.g., `2026-02-13T15:30:00.123456`)

**Procedure:**
```
Use Glob to list *.json files in the log directory:
  ${SDD_ROOT_DIR}/logs/session-transcripts/*.json

Sort by timestamp (embedded in filename) to prioritize recent sessions.
Filter by date range if analyzing a specific time period.
Count total files to gauge analysis scope.
```

### Log File Retention

Session transcript logs accumulate over time. Recommended retention policies:

**Active Retention (90 days):**
Logs from the past 90 days are useful for skill discovery - recent patterns are more likely to become reusable skills. This window balances disk usage with analysis value.

**Historical Retention (1 year):**
Older logs may have long-term analytical value but are unlikely to reveal new skills. Archive them for future reference without cluttering active storage.

**Deletion (after 90 days):**

To permanently delete logs older than 90 days:

```bash
find ${SDD_ROOT_DIR}/logs/session-transcripts/ -type f -name "*.json" -mtime +90 -delete
```

**Warning:** This is irreversible. Verify with dry-run first:

```bash
find ${SDD_ROOT_DIR}/logs/session-transcripts/ -type f -name "*.json" -mtime +90 -print
```

**Archival (after 90 days):**

To compress and archive logs older than 90 days:

```bash
# Create archive directory
mkdir -p ${SDD_ROOT_DIR}/logs/archives

# Find and archive old logs
archive_date=$(date +%Y%m%d)
find ${SDD_ROOT_DIR}/logs/session-transcripts/ -type f -name "*.json" -mtime +90 -print0 | \
    tar -czf ${SDD_ROOT_DIR}/logs/archives/session-transcripts-${archive_date}.tar.gz --null -T -

# After verifying archive, delete originals
find ${SDD_ROOT_DIR}/logs/session-transcripts/ -type f -name "*.json" -mtime +90 -delete
```

Archived logs can be extracted later for historical analysis:

```bash
tar -xzf ${SDD_ROOT_DIR}/logs/archives/session-transcripts-YYYYMMDD.tar.gz -C /tmp/
```

**Custom Retention:**

Adjust retention based on your needs:
- High disk usage: 30-day active retention
- Historical analysis: 180-day or longer retention
- Compliance requirements: Never delete, archive only

### Step 2: Read and Triage Transcripts

For each log file, extract the transcript reference and assess availability.

**Log entry format (JSON):**
```json
{
  "session_id": "abc123",
  "schema_version": "1.0",
  "transcript_path": "/home/user/.claude/projects/.../session.jsonl",
  "cwd": "/workspace/repos/project",
  "hook_event_name": "PreCompact",
  "timestamp": "2026-02-13T15:30:00.123456",
  "trigger": "auto",
  "custom_instructions": "",
  "status": "ok"
}
```

**Procedure:**
1. Read each log JSON file to extract the `transcript_path` field
2. Check whether the transcript file still exists (Claude Code may delete session files during cleanup)
3. If the transcript file exists, read it as JSONL (each line is a separate JSON object)
4. If the transcript file does not exist, log the missing path and skip transcript analysis but retain the metadata (session_id, cwd, timestamp) for cross-referencing

**JSONL transcript format:**

Each line of a `.jsonl` transcript file is a self-contained JSON object representing one message or tool invocation in the session:

```json
{"role": "user", "content": "Please implement feature X", "timestamp": "..."}
{"role": "assistant", "content": "I'll help with that...", "timestamp": "..."}
{"role": "tool_use", "tool": "Read", "parameters": {"file_path": "/path/to/file"}, "timestamp": "..."}
{"role": "tool_result", "content": "...", "timestamp": "..."}
```

Key fields:
- `role`: One of `user`, `assistant`, `tool_use`, `tool_result`
- `content`: The message text or tool output
- `tool`: (tool_use only) The tool name invoked
- `parameters`: (tool_use only) The parameters passed to the tool
- `timestamp`: When the message occurred

The exact schema may vary between Claude Code versions. Parse defensively and skip lines that do not match expected structure.

**Focus areas during triage:**
- Assistant messages containing multi-step procedures
- Sequences of tool_use invocations that form a coherent workflow
- Patterns that repeat across different sessions or projects (check `cwd` field in log entries)

### Step 3: Extract Candidate Patterns

Identify patterns with potential reuse value from the triaged transcripts.

**What to look for:**
- **Recurring multi-step procedures**: Sequences of 3+ steps that appear in multiple sessions, especially when the steps follow the same order
- **Multi-tool workflows**: Patterns that span multiple tools (e.g., Grep then Read then Edit) in a specific combination that solves a particular class of problem
- **Cross-project patterns**: Procedures observed in different `cwd` directories or different plugin contexts, indicating the pattern is not project-specific
- **Non-obvious integrations**: Patterns where two or more tools or systems are combined in a way that is not documented in standard tool references

**What to ignore:**
- Single-command invocations (no procedural value)
- Standard tool usage following documented patterns
- Project-specific configurations that do not generalize
- Conversational exchanges without procedural content

### Step 4: Apply Quality Gates

Evaluate each candidate pattern against the quality gates table. A candidate must pass ALL gates to proceed.

| Gate | Criteria | Pass Condition |
|------|----------|----------------|
| Reuse Potential | Pattern observed across sessions or projects | 3+ sessions AND cross-project applicability (session-derived skills must meet BOTH criteria) |
| Complexity | Pattern is non-trivial | Pattern involves multiple steps or non-obvious integration (single commands or general knowledge are insufficient) |
| Distinctiveness | Not already covered by existing skills | Check `.claude/skills/` and `plugins/*/skills/` for overlap |
| Documentability | Can be expressed as a SKILL.md | Fits either executable or reference pattern from `skill-md-structure` |
| Teachability | Agent would benefit from having this documented | Not common knowledge; requires domain insight or repo-specific context |
| Non-Triviality | Pattern is not general developer knowledge | Not covered by standard tool docs (man pages, MDN, official guides) or common StackOverflow patterns |

**Gate evaluation order:** Apply Reuse Potential and Non-Triviality first, as these are the most common rejection reasons. If a candidate fails either of these, skip remaining gates.

### Anti-Patterns: What Is NOT a Skill Candidate

The following examples illustrate patterns that should be rejected during quality gate evaluation. These represent the triviality boundary -- patterns that are either single commands, general knowledge, or standard tool usage.

1. **Running `git status`**: Trivial single command. Standard workflow documented in `git --help`. No multi-step procedure or domain insight.

2. **Using `ls -la` to list files**: Basic shell command. Documented in man pages. Every developer knows this without a skill document.

3. **Reading MDN documentation for `Array.prototype.map`**: General JavaScript knowledge. Covered comprehensively by official documentation. Not repo-specific or procedural.

4. **Installing npm packages with `npm install`**: Standard tool usage. The `npm install` command and its flags are fully documented in npm's official documentation.

5. **Searching StackOverflow for common error messages**: General debugging practice. Not a reusable pattern -- each error message and solution is unique.

6. **Using `grep -r "pattern" .` for code search**: Standard tool usage with no multi-step procedure. Grep usage is documented in man pages and tutorials.

7. **Committing changes with `git commit -m "message"`**: Basic git workflow. No non-obvious integration or domain-specific procedure.

**Contrast with valid candidates:** A valid candidate might be "verifying identical content blocks across multiple markdown files using grep, extraction, hash comparison, and diff" -- this is multi-step, requires a specific procedure, and is not covered by any single tool's documentation.

### Step 5: Validate Against Existing Criteria

Cross-reference candidates that pass all quality gates against the existing skill-curation infrastructure.

**Procedure:**
1. Review `skill-quality-criteria.md` from the skill-curation infrastructure to confirm the candidate meets the project's established quality bar
2. Check `.claude/skills/` for existing repo-local skills that might already cover the pattern (compare by purpose, not just name)
3. Check `plugins/*/skills/` for existing plugin-scoped skills with overlapping coverage
4. Verify the candidate aligns with the SKILL.md structure patterns documented in `.claude/skills/skill-md-structure/SKILL.md` (determine whether it would be an executable or reference skill)

### Step 6: Propose Skills

For candidates that survive all gates and validation, prepare skill proposals.

**Procedure:**
1. Document each candidate with:
   - Proposed skill name (kebab-case)
   - One-line description (under 200 characters)
   - Pattern type: executable or reference
   - Evidence: list the sessions and projects where the pattern was observed
   - Draft outline of the SKILL.md sections
2. Follow `skill-creation-workflow.md` from the skill-curation infrastructure for the formal creation process
3. Store the completed skill at `.claude/skills/{name}/SKILL.md` (same location as ticket-curated skills)
4. If the skill is plugin-specific, also consider placement under `plugins/{plugin}/skills/{name}/SKILL.md`

## Examples

### Example 1: Multi-File Documentation Sync Pattern

**Observed in:** SKILLLOG, TOOLS, RECIPES tickets (across 5+ sessions)

**Pattern:** Verifying identical content blocks across multiple markdown files. The procedure involves grepping for block markers, extracting content sections, comparing hashes or using diff, and reporting inconsistencies with specific line numbers.

**Procedure observed in transcripts:**
1. Use `grep -n` to locate content block markers across all target files
2. Extract content between markers using line-range reads
3. Normalize whitespace (strip leading indentation for nested contexts)
4. Compare extracted blocks using `diff`
5. Report results with file paths and line numbers

**Why it passes quality gates:**
- Reuse Potential: Observed in 5+ sessions across 3 different tickets
- Complexity: Multi-step procedure involving grep, extraction, normalization, and diff
- Distinctiveness: No existing skill covered this specific workflow
- Non-Triviality: Not documented in any single tool's reference material

**Deliverable:** `.claude/skills/multi-file-documentation-sync/SKILL.md`

### Example 2: Shell Script Input Validation Pattern

**Observed in:** iterm plugin, sdd plugin, github-actions plugin development (across 4+ sessions)

**Pattern:** Rejecting dangerous input patterns in shell scripts that accept user-provided strings. The procedure involves regex-based validation for newlines, backticks, command substitution (`$(...)`), and variable expansion (`${...}`), with consistent error messaging and exit codes.

**Procedure observed in transcripts:**
1. Place validation block after argument parsing, before main logic
2. Check each dangerous pattern with regex matching
3. Emit clear error messages identifying the rejected pattern
4. Exit with code 1 for validation failures
5. Ensure normal input (spaces, punctuation, paths) passes validation

**Why it passes quality gates:**
- Reuse Potential: Observed in 4+ sessions across 3 different plugin codebases
- Complexity: Multiple regex checks with specific ordering and error handling
- Distinctiveness: No existing skill covered shell input sanitization
- Non-Triviality: Security-critical pattern requiring domain knowledge of injection vectors

**Deliverable:** `.claude/skills/shell-script-input-validation/SKILL.md`

### Example 3: Stale-Path Handling

**Scenario:** A session log entry at `${SDD_ROOT_DIR}/logs/session-transcripts/abc123_PreCompact_2026-02-10T14:22:00.000000.json` contains a `transcript_path` pointing to `/tmp/session-abc123.jsonl`.

**Problem:** The transcript file no longer exists. Claude Code periodically cleans up session files, and `/tmp` is volatile across container restarts.

**Procedure for graceful handling:**
1. Read the log entry JSON and extract `transcript_path`
2. Attempt to read the transcript file
3. If the file does not exist:
   - Log the missing path (note it in analysis output, do not treat as an error)
   - Retain available metadata from the log entry: `session_id`, `cwd`, `timestamp`, `hook_event_name`
   - Skip transcript content analysis for this entry
   - Continue processing remaining log entries
4. Do not fail the entire analysis due to a single missing transcript

**Why this matters:** Graceful degradation prevents analysis failures when transcript files have been cleaned up. The metadata alone (which project, when, what hook event) can still contribute to cross-referencing patterns identified in other sessions.

### Example 4: Wrapper-with-Fallback Delegation Pattern

**Observed in:** worktree plugin, maproom plugin, vscode plugin development (across 6+ sessions)

**Pattern:** Implementing plugin commands that delegate to an external CLI tool with graceful fallback when the tool is unavailable. The procedure involves checking tool availability with `command -v`, constructing the delegation command with proper argument forwarding, capturing exit codes, and providing meaningful error messages when the tool is missing.

**Procedure observed in transcripts:**
1. Check if the external CLI tool exists using `command -v`
2. If available, construct the delegated command with forwarded arguments
3. Capture the exit code and output
4. If the tool is not available, emit a fallback message explaining how to install it
5. Ensure the wrapper script's exit code reflects the delegated command's result

**Why it passes quality gates:**
- Reuse Potential: Observed in 6+ sessions across 3 different plugin codebases
- Complexity: Multi-step procedure with conditional logic, argument forwarding, and exit code propagation
- Distinctiveness: Covered the specific pattern of plugin-to-CLI delegation
- Non-Triviality: Requires understanding of shell exit code semantics and graceful degradation

**Deliverable:** `.claude/skills/wrapper-with-fallback-pattern/SKILL.md`

### Example 5: SKILL.md Structure Selection

**Observed in:** ISKIM, SKILLLOG, PANE tickets (across 8+ sessions)

**Pattern:** Choosing between executable and reference skill patterns when creating SKILL.md documentation. The procedure involves evaluating whether the skill includes scripts, determining the appropriate section count (5 vs 12+), and validating frontmatter fields against the pattern requirements.

**Why it was NOT proposed as a standalone skill:** This pattern was already captured as `.claude/skills/skill-md-structure/SKILL.md` during the ISKIM ticket. This example demonstrates that Step 5 (Validate Against Existing Criteria) correctly filters out duplicates, even when the pattern is observed frequently in transcripts.

## Troubleshooting

If log files are not being created in `${SDD_ROOT_DIR}/logs/session-transcripts/`, follow these verification steps:

### 1. Verify SDD_ROOT_DIR is Set

Check that the environment variable is configured:

```bash
echo "SDD_ROOT_DIR=${SDD_ROOT_DIR}"
```

Expected output: `/path/to/sdd/root` (not empty)

If empty, the `setup-sdd-env.js` SessionStart hook may not have run. Check that the SDD plugin is installed.

### 2. Verify Log Directory Exists and is Writable

Check directory permissions:

```bash
ls -ld ${SDD_ROOT_DIR}/logs/session-transcripts/
```

Expected: Directory exists and is writable by current user.

If directory is missing, create it manually:

```bash
mkdir -p ${SDD_ROOT_DIR}/logs/session-transcripts
chmod 700 ${SDD_ROOT_DIR}/logs/session-transcripts
```

### 3. Verify Hook Registration

Check that the hook is registered in plugin.json:

```bash
jq '.hooks.PreCompact, .hooks.SessionEnd' plugins/sdd/.claude-plugin/plugin.json
```

Expected: Both hooks list `log-session-transcript.py` with timeout 10.

If missing, hook registration (SKILLLOG.1003) was not completed successfully.

### 4. Test Hook Manually

Execute the hook with test input to check for Python errors:

```bash
export SDD_ROOT_DIR=/path/to/your/sdd/root
echo '{"session_id": "test123", "transcript_path": "/tmp/test.jsonl", "cwd": "/workspace", "hook_event_name": "SessionEnd", "reason": "test"}' | python3 plugins/sdd/hooks/log-session-transcript.py
echo "Exit code: $?"
```

Expected: Exit code 0, no output. Check for new file in `${SDD_ROOT_DIR}/logs/session-transcripts/`.

If Python errors appear, the hook script has a bug.

### 5. Common Causes of Silent Failures

- **Empty transcript_path**: PreCompact hook has known bug (#13668) where `transcript_path` is sometimes empty. Log entry is created with `status: "empty_path"`.
- **Hook timeout**: If hook takes >10s (very unlikely), Claude Code kills it. Check for extremely slow disk I/O.
- **Python not available**: Hook requires Python 3 in PATH. Check: `python3 --version`
- **Permissions issue**: Hook creates files with 0600 permissions. If umask is restrictive, verify with: `umask`
- **Disk full**: If disk is full, file creation fails silently. Check: `df -h ${SDD_ROOT_DIR}`

If none of these steps reveal the issue, check Claude Code's internal logs for hook execution errors.

## References

- **Skill curation infrastructure:**
  - `skill-quality-criteria.md` -- Established quality criteria for skill candidates (located in skill-curation infrastructure, may be in other worktrees)
  - `skill-creation-workflow.md` -- Step-by-step workflow for creating new skills from validated candidates (located in skill-curation infrastructure, may be in other worktrees)

- **Skill structure documentation:**
  - `.claude/skills/skill-md-structure/SKILL.md` -- Reference Skill pattern documentation defining the 5-section and 12-section structures

- **Session transcript log directory:**
  - `${SDD_ROOT_DIR}/logs/session-transcripts/` -- Location where Phase 1 hooks write session transcript log entries
  - File naming: `{session_id}_{event}_{timestamp}.json`
  - Format: JSON log entries containing `session_id`, `schema_version`, `transcript_path`, `cwd`, `hook_event_name`, `timestamp`, `trigger`, `status`

- **Transcript format:**
  - JSONL (JSON Lines) with one JSON object per line
  - Key fields per line: `role`, `content`, `timestamp` (plus `tool` and `parameters` for tool_use entries)

- **Existing repo-local skills (examples of discovered patterns):**
  - `.claude/skills/multi-file-documentation-sync/SKILL.md` -- Pattern for verifying content consistency across files
  - `.claude/skills/shell-script-input-validation/SKILL.md` -- Pattern for rejecting dangerous input in shell scripts
  - `.claude/skills/skill-md-structure/SKILL.md` -- Two SKILL.md documentation patterns
  - `.claude/skills/wrapper-with-fallback-pattern/SKILL.md` -- Plugin delegation with graceful fallback

- **Origin ticket:** SKILLLOG (Session Skill Discovery epic)
