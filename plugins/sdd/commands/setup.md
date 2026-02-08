---
description: Initialize SDD environment and reference templates
argument-hint: [force to reinitialize]
---

# Initialize SDD Environment

## Context

User input: "$ARGUMENTS"

## Workflow

**IMPORTANT: You are an orchestrator. You verify and report status. You do NOT modify system configuration yourself.**

### Step 1: Resolve SDD Root

Get the SDD data directory:

```bash
echo ${SDD_ROOT_DIR:-/app/.sdd}
```

Store the result as `SDD_ROOT`.

### Step 2: Check Directory Structure

Verify the required directories exist:

```bash
required_dirs=(
  "${SDD_ROOT}/epics"
  "${SDD_ROOT}/tickets"
  "${SDD_ROOT}/archive/tickets"
  "${SDD_ROOT}/archive/epics"
  "${SDD_ROOT}/reference"
  "${SDD_ROOT}/research"
  "${SDD_ROOT}/scratchpad"
  "${SDD_ROOT}/logs"
)

missing=()
for dir in "${required_dirs[@]}"; do
  if [[ ! -d "$dir" ]]; then
    missing+=("$dir")
  fi
done

if [[ ${#missing[@]} -eq 0 ]]; then
  echo "STATUS: All directories present"
else
  echo "MISSING: ${missing[*]}"
fi
```

### Step 3: Check Reference Templates

Verify reference templates are in place:

```bash
if [[ -f "${SDD_ROOT}/reference/work-task-template.md" ]]; then
  echo "TEMPLATE: work-task-template.md present"
else
  echo "TEMPLATE: work-task-template.md MISSING"
fi
```

### Step 4: Force Reinitialize (if requested)

If user passes "force" argument AND there are missing components:

```bash
# Recreate directory structure
mkdir -p "${SDD_ROOT}"/{epics,tickets,archive/tickets,archive/epics,reference,research,scratchpad,logs}

# Copy reference template from plugin
if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
  cp "${CLAUDE_PLUGIN_ROOT}/skills/project-workflow/templates/ticket/task-template.md" \
     "${SDD_ROOT}/reference/work-task-template.md" 2>/dev/null || true
fi
```

### Step 5: Report Status

Report to user:

```
SDD ENVIRONMENT STATUS

Root Directory: ${SDD_ROOT}

Directory Structure:
  epics/           [EXISTS | MISSING]
  tickets/              [EXISTS | MISSING]
  archive/tickets/      [EXISTS | MISSING]
  archive/epics/   [EXISTS | MISSING]
  reference/             [EXISTS | MISSING]
  research/              [EXISTS | MISSING]
  scratchpad/            [EXISTS | MISSING]
  logs/                  [EXISTS | MISSING]

Reference Templates:
  work-task-template.md  [EXISTS | MISSING]

Overall Status: [READY | NEEDS INITIALIZATION]

{If NEEDS INITIALIZATION}
Run: /sdd:setup force
```

### Next Step Prompt

After displaying the report above, use the **AskUserQuestion** tool to present next steps to the user:

**Question:** "What would you like to do next?"
**Header:** "Next step"
**multiSelect:** false

**Options:**
- Label: "/sdd:plan-ticket" | Description: "Create your first ticket"
- Label: "/sdd:start-epic" | Description: "Start with an epic for research and discovery"

## Decision Points

- **Status check**: Default behavior, just reports current state
- **Force reinitialize**: If user passes "force", recreate missing components

## Key Constraints

- The SessionStart hook (setup-sdd-env.sh) should have already created the structure
- This command is for verification and manual repair if needed
- DO NOT modify environment variables yourself
- DO NOT alter plugin configuration
