---
description: Display epic-level status showing checkpoint progress
argument-hint: [EPIC_FOLDER or empty for all]
---

# Epic Status Check

## Context

Epic: $ARGUMENTS (optional - if empty, shows all epics)

## Workflow

**IMPORTANT: Use scripts for data gathering, format output directly.**

### Step 1: Gather Epic Status Data

**Run epic status script:**

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/scripts/epic-status.sh ${ARGUMENTS}
```

This returns JSON with:
- Epic names and paths
- Checkpoint checkbox states (research, analysis, decomposition, tickets_created)
- Progress as fraction (e.g., "2/4")

### Step 2: Format Report

Parse JSON directly and format output.

**For single epic:**

```
=== EPIC STATUS ===

Epic: {epic_name}
Progress: {progress} checkboxes complete

{✓ or ☐} Research complete
{✓ or ☐} Analysis complete
{✓ or ☐} Decomposition complete
{✓ or ☐} Tickets created
```

**For all epics:**

```
=== EPIC STATUS ===

Epic: api-redesign (2025-12-11_api-redesign)
Progress: 2/4 checkboxes complete

✓ Research complete
✓ Analysis complete
☐ Decomposition complete
☐ Tickets created

---

Epic: cache-optimization (2025-12-10_cache-optimization)
Progress: 4/4 checkboxes complete

✓ Research complete
✓ Analysis complete
✓ Decomposition complete
✓ Tickets created

---

Summary: 2 epics found
```

**Empty state:**

If no epics exist or epics array is empty:

```
No active epics found.

Use /sdd:start-epic [name] to create one.
```

### Step 3: Error Handling

**If script fails:**
```
Error: Failed to retrieve epic status.

Check that:
- SDD_ROOT_DIR is set correctly (default: /app/.sdd)
- Epic directories exist in ${SDD_ROOT_DIR}/epics/
- Epic overview.md files are present

Try: /sdd:setup to initialize SDD environment
```

**If specific epic not found:**
```
Error: Epic "{epic_folder}" not found.

Available epics:
- {epic1}
- {epic2}

Use /sdd:start-epic [name] to create a new epic.
```

## Output Symbols

- Use ✓ for checked boxes (true)
- Use ☐ for unchecked boxes (false)

## Key Constraints

- Use epic-status.sh for data (don't scan files manually)
- Keep reports concise and scannable
- Show clear progress indicators
- Display actionable next steps for empty states
- Handle missing overview.md files gracefully
