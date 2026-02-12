---
name: multi-file-documentation-sync
description: Ensure identical content blocks appear consistently across multiple documentation files, including verification procedures
origin: VERBUMP
created: 2026-02-12
tags: [documentation, consistency, verification]
---

# Multi-File Documentation Sync

## Overview

This skill covers the pattern for embedding standardized content blocks across multiple documentation files and verifying that they remain consistent. This is critical for the claude-code-plugins repository where skills exist in two locations (plugin-scoped under `plugins/` and repo-local under `.claude/skills/`) and standardized guidance (like semver tables or version bump procedures) must appear identically in multiple files.

The VERBUMP ticket demonstrated this pattern: Variant A and Variant B version bump blocks were embedded in 8 files, then verified for consistency using grep and diff.

## When to Use

Use this pattern when:

- Adding standardized procedural guidance to multiple SKILL.md files (e.g., version bump instructions, security checks, testing procedures)
- Updating content blocks that must remain identical across files (e.g., semver classification tables, validation checklists)
- Synchronizing plugin-scoped and repo-local copies of skills
- Ensuring consistency of reference content across documentation that serves different agent workflows

## Pattern/Procedure

### Phase 1: Embed Standardized Content

1. **Define the canonical content block** in a planning document (e.g., architecture.md). Include:
   - The exact text/markdown to embed
   - Any variants needed for different contexts (e.g., Variant A for plugin.json, Variant B for marketplace.json)
   - Integration points (where in each file the content should appear)

2. **Create tasks for each file** that needs the content block:
   - One task per file ensures clear accountability
   - Task should specify exact integration point (e.g., "Add as Step 4 in Registration Steps")
   - Task should preserve all existing content (additive change only)

3. **Apply the content block consistently**:
   - Copy from the canonical definition (no paraphrasing)
   - Maintain identical formatting (headings, code blocks, tables)
   - If context-specific adjustments are needed, document them clearly

### Phase 2: Verify Consistency

4. **Create presence verification task**:
   ```bash
   # Verify all files contain the expected pattern
   grep -i -n "pattern identifier" file1.md file2.md file3.md
   ```

   Expected output: All files should show matches. Count matches to ensure completeness.

5. **Create copy consistency verification task** (for duplicate files):
   ```bash
   # Verify plugin-scoped and repo-local copies are identical
   diff plugins/{plugin-name}/skills/{skill-name}/SKILL.md \
        .claude/skills/{skill-name}/SKILL.md
   ```

   Expected output: Empty (exit code 0) means files are byte-for-byte identical.

6. **Create content consistency verification task** (for standardized blocks):
   ```bash
   # Extract and compare specific content blocks across files
   grep -A 10 "Section Header" file1.md > /tmp/file1_section.txt
   grep -A 10 "Section Header" file2.md > /tmp/file2_section.txt
   diff /tmp/file1_section.txt /tmp/file2_section.txt
   ```

   Or for tables:
   ```bash
   # Count rows in semver tables
   grep -c "PATCH\|MINOR\|MAJOR" file1.md file2.md
   ```

   Expected output: Same row counts and identical content after whitespace normalization.

### Phase 3: Document Results

7. **Create a verification report** in `deliverables/verification-report.md`:
   - Summary table with file counts and results
   - Full output of verification commands
   - PASS/FAIL recommendation with rationale
   - Any detected inconsistencies with specific line numbers

## Examples

### Example 1: VERBUMP Version Bump Instructions

**Context:** Add version bump procedural steps to 8 documentation files.

**Canonical content defined in:** `architecture.md` lines 68-126 (Variant A and Variant B)

**Files updated:**
- `plugins/claude-code-dev/skills/plugin-skills-registration/SKILL.md` (Variant A)
- `.claude/skills/plugin-skills-registration/SKILL.md` (Variant A)
- `plugins/claude-code-dev/skills/plugin-marketplace-registration/SKILL.md` (Variant B)
- `.claude/skills/plugin-marketplace-registration/SKILL.md` (Variant B)
- `plugins/claude-code-dev/skills/marketplace-manager/SKILL.md` (both variants)
- `plugins/claude-code-dev/skills/skill-creator/SKILL.md` (note reference)
- `plugins/sdd/skills/skill-curation/references/promotion-guide.md` (both variants)
- `plugins/claude-code-dev/skills/marketplace-manager/scripts/init_plugin.py` (print reminder)

**Verification approach:**

1. **Presence verification** (VERBUMP.2001):
   ```bash
   grep -i "version bump" <all 8 files>
   ```
   Result: All 8 files matched (7 with full blocks, 1 with reminder message).

2. **Copy consistency verification** (VERBUMP.2002):
   ```bash
   diff plugins/claude-code-dev/skills/plugin-skills-registration/SKILL.md \
        .claude/skills/plugin-skills-registration/SKILL.md
   diff plugins/claude-code-dev/skills/plugin-marketplace-registration/SKILL.md \
        .claude/skills/plugin-marketplace-registration/SKILL.md
   ```
   Result: Both diffs returned empty (byte-for-byte identical).

3. **Content consistency verification** (VERBUMP.2003):
   - Confirmed all Variant A tables have 3 rows (PATCH, MINOR, MAJOR)
   - Confirmed all Variant B tables have 3 rows (PATCH, MINOR, MAJOR)
   - Compared table content across files after whitespace normalization
   Result: All 8 table instances consistent within their variants.

**Outcome:** All 8 files updated with consistent content; no drift detected.

### Example 2: Whitespace Normalization for Table Comparisons

**Issue:** Files with tables inside numbered list items use 3-space indentation, while top-level tables have no indentation.

**Solution:** Strip leading whitespace before comparison:
```bash
# Extract table from indented context (File 1)
grep -A 5 "| Change Type |" file1.md | sed 's/^   //' > /tmp/table1.txt

# Extract table from top-level context (File 2)
grep -A 5 "| Change Type |" file2.md > /tmp/table2.txt

# Compare normalized content
diff /tmp/table1.txt /tmp/table2.txt
```

**Result:** Tables are identical after normalization (formatting difference is cosmetic, not semantic).

## Anti-Patterns to Avoid

1. **Paraphrasing canonical content**: Do not rewrite content blocks in your own words. Copy exactly from the canonical definition to ensure byte-for-byte consistency.

2. **Skipping verification**: Do not assume content is consistent because you applied it carefully. Always run verification commands (grep, diff) to confirm.

3. **Manual visual inspection instead of diff**: Do not compare files by reading them side-by-side. Use `diff` to detect even single-character differences.

4. **One-time verification**: Do not verify consistency only at initial creation. Re-verify after any future edits to ensure copies haven't drifted.

5. **Ignoring whitespace differences**: Do not dismiss whitespace differences as "cosmetic" without analyzing context. Markdown rendering can be affected by indentation and line breaks.

## Troubleshooting

**Problem:** `diff` reports differences but files look identical when viewed.

**Solution:** Check for trailing whitespace, line ending differences (CRLF vs LF), or invisible Unicode characters. Use `diff -w` to ignore whitespace or `cat -A` to show all characters.

**Problem:** `grep` count is higher than expected (e.g., 15 matches instead of 7).

**Solution:** Pattern may match multiple contexts. Use `grep -n` to show line numbers and verify matches are in the intended sections. Refine pattern to be more specific (e.g., `grep "^### Version Bump"` to match heading only).

**Problem:** Content blocks are semantically identical but not byte-for-byte identical.

**Solution:** Extract and normalize both versions (strip whitespace, convert to lowercase), then compare. If semantic equivalence is acceptable, document the allowed formatting variations in the verification report.

## References

- Ticket: VERBUMP
- Related files:
  - `/workspace/_SPECS/claude-code-plugins/tickets/VERBUMP_auto-version-bumps/planning/architecture.md` (canonical content definitions)
  - `/workspace/_SPECS/claude-code-plugins/tickets/VERBUMP_auto-version-bumps/planning/verification-report.md` (verification procedures and results)
  - `/workspace/_SPECS/claude-code-plugins/tickets/VERBUMP_auto-version-bumps/tasks/VERBUMP.2001_verify-version-bump-instructions.md` (presence verification)
  - `/workspace/_SPECS/claude-code-plugins/tickets/VERBUMP_auto-version-bumps/tasks/VERBUMP.2002_verify-copy-consistency.md` (copy sync verification)
  - `/workspace/_SPECS/claude-code-plugins/tickets/VERBUMP_auto-version-bumps/tasks/VERBUMP.2003_verify-semver-table-consistency.md` (content consistency verification)
