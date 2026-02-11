---
name: document-authoring
description: Per-document agent spawning for SDD ticket planning. Decomposes monolithic ticket-planner into individually spawnable agents with approval workflows, enabling focused context and incremental review for complex tickets.
---

# Document Authoring Skill

**Last Updated:** 2026-02-11
**Plugin:** sdd
**Prompts Location:** `plugins/sdd/skills/document-authoring/prompts/`
**References Location:** `plugins/sdd/skills/document-authoring/references/`

## Overview

This skill provides an alternative to the monolithic `ticket-planner` agent for creating SDD ticket planning documents. Instead of one agent writing all seven documents in a single session, this skill decomposes the work into individually spawnable per-document agents -- each focused on a single document with fresh context.

**Key Capabilities:**
- Spawn focused agents for each of the 7 planning documents (analysis, PRD, architecture, plan, quality-strategy, security-review, README)
- Approve or request revisions on each document individually via a standardized approval workflow
- Maintain consistent quality across all documents by giving each agent full context
- Execute document creation in dependency order using the document dependency graph
- Manage agent tabs/panes via existing iTerm plugin infrastructure

**When to Use This Skill vs Monolithic ticket-planner:**

| Factor | Monolithic ticket-planner | Per-Document Agents (this skill) |
|--------|---------------------------|----------------------------------|
| Ticket complexity | Low to medium | High (multi-domain, deep research) |
| Quality requirements | Standard quality sufficient | Maximum quality critical |
| User preference | Minimal interaction desired | Willing to approve each document |
| Context sensitivity | Later documents can be lighter | All documents need full context |
| Total time | 30-40 minutes | 50-90 minutes |
| Manual interactions | 2 (plan + review) | 14 (7 spawns + 7 approvals) |

This skill complements the existing `ticket-planner` agent -- it does not replace it. The monolithic approach remains the default for most tickets. Use per-document agents only when the quality and control benefits justify the additional time and interaction overhead.

## Prerequisites

### Required for All Modes

- **iTerm2**: Must be running on the macOS host. All tab/pane operations target iTerm2.
- **Claude CLI**: `claude` command must be available in the execution environment. Agents are spawned via `echo "prompt" | claude --dangerously-skip-permissions`.
- **spawn-agent.sh**: Located at `/workspace/.devcontainer/scripts/spawn-agent.sh`. Provides the wrapper for spawning Claude agents in iTerm tabs or panes.
- **iTerm plugin**: The iterm plugin must be installed with both tab-management and pane-management skills:
  - `plugins/iterm/skills/tab-management/scripts/iterm-open-tab.sh`
  - `plugins/iterm/skills/tab-management/scripts/iterm-close-tab.sh`
  - `plugins/iterm/skills/pane-management/scripts/iterm-split-pane.sh`
  - `plugins/iterm/skills/pane-management/scripts/iterm-close-pane.sh`
- **SDD plugin**: The sdd plugin must be installed with the project-workflow skill (provides document templates).
- **Ticket structure**: A ticket must already be scaffolded via `scaffold-ticket.sh` with a valid `README.md`.

### Container Mode Additional Requirements

- **HOST_USER**: Environment variable must be set (configured in `devcontainer.json` `remoteEnv`).
- **SSH access**: Container must have SSH connectivity to `host.docker.internal` for AppleScript execution on the macOS host.

### macOS Host Mode

- No additional requirements beyond the above. Scripts execute directly via `osascript`.

## Decision Tree

Use this tree to decide whether to use per-document agents or the monolithic ticket-planner:

```
Is this a complex ticket?
  |
  +-- NO (straightforward, < 3 dependencies, < 8 hour estimate)
  |     |
  |     +-- Use monolithic ticket-planner (/sdd:plan-ticket)
  |         - 30-40 min total
  |         - 2 interactions (plan + review)
  |         - High quality for first 3-4 documents, may degrade for later ones
  |
  +-- YES (multi-domain, deep research, security-critical)
        |
        +-- Do you need per-document approval gates?
              |
              +-- NO --> Use monolithic ticket-planner
              |          (quality is "good enough" for the use case)
              |
              +-- YES --> Use per-document agents (this skill)
                          - 50-90 min total
                          - 14 interactions (7 spawns + 7 approvals)
                          - Consistently high quality for ALL documents
                          - Each agent starts with fresh context
```

**Time Comparison:**

| Approach | Sessions | Time per Session | Approvals | Total Time | Total Interactions |
|----------|----------|-----------------|-----------|------------|-------------------|
| Monolithic ticket-planner | 1 plan + 1 review | 20-30 min + 10 min | 1 | 30-40 min | 2 |
| Per-document agents | 7 sequential | 5-10 min each | 7 | 50-90 min | 14 |

**Quality Comparison:**

| Metric | Monolithic | Per-Document |
|--------|-----------|-------------|
| First 3 documents (analysis, PRD, architecture) | High | High |
| Later documents (plan, quality-strategy, security-review) | May degrade (context exhaustion) | High (fresh context) |
| README (final synthesis) | Variable | High (all inputs approved) |
| Consistency across documents | Medium (single pass) | High (each reviewed individually) |

## Usage Patterns

### Pattern 1: Manual Power-User Workflow

A power user spawns each document agent manually, reviews and approves each document, then proceeds to the next:

1. Read the dependency graph to determine document order
2. Fill placeholders in the initiation prompt for the first document
3. Spawn the agent via `spawn-agent.sh` or directly via iTerm plugin scripts
4. Wait for the agent to complete and present the approval prompt
5. Approve or request changes
6. Close the tab/pane
7. Repeat for the next document in dependency order

### Pattern 2: Orchestrating Agent Workflow

An orchestrating agent (running in its own session) automates the spawning, monitoring, and cleanup:

1. Read the dependency graph programmatically
2. For each document in order:
   a. Fill prompt placeholders with ticket-specific values
   b. Spawn the document agent in a named tab or pane
   c. Monitor for the `DOCUMENT_AGENT_COMPLETE` signal
   d. Close the tab/pane via iTerm plugin scripts
   e. Proceed to the next document
3. Report completion of all documents

### Pattern 3: Selective Document Creation

A user or agent spawns agents only for specific documents that need focused attention, using the monolithic ticket-planner for the rest:

1. Run `/sdd:plan-ticket` to create all documents via the monolithic approach
2. Identify documents that need deeper research or revision
3. Spawn per-document agents only for those specific documents
4. The per-document agent reads the existing document and rewrites it with deeper research

## Spawning Procedures

### Prompt Construction

Each document type has two initiation prompts (creation and review) in the prompts directory:

```
plugins/sdd/skills/document-authoring/prompts/
  create/
    analysis.md
    prd.md
    architecture.md
    plan.md
    quality-strategy.md
    security-review.md
    readme.md
  review/
    analysis.md
    prd.md
    architecture.md
    plan.md
    quality-strategy.md
    security-review.md
    readme.md
```

Each prompt contains placeholders that must be filled before spawning:

| Placeholder | Description | Example Value |
|-------------|-------------|---------------|
| `{TICKET_ID}` | The ticket identifier | `APIV2` |
| `{TICKET_PATH}` | Absolute path to the ticket directory | `/app/.sdd/tickets/APIV2_api-redesign` |
| `{PLUGIN_ROOT}` | Absolute path to the sdd plugin root | `/workspace/repos/claude-code-plugins/plugins/sdd` |

**Filling placeholders:**

Read the prompt file, substitute all three placeholders with actual values, and use the resulting text as the agent's task description.

Example -- reading and filling the analysis creation prompt:

```
# Original prompt (from prompts/create/analysis.md):
You are a document creation agent. Your task is to create the analysis.md
planning document for ticket {TICKET_ID}.

Read the ticket README at {TICKET_PATH}/README.md to understand the ticket intent.

Read the creation guide in {PLUGIN_ROOT}/skills/document-authoring/references/doc-analysis.md
for detailed instructions, research steps, quality criteria, and the template reference.

Research the codebase thoroughly before writing. Fill in every section of the template
with specific, well-researched content. Cite actual files and patterns found during research.

Write the completed document to {TICKET_PATH}/planning/analysis.md

When complete, follow the approval workflow in
{PLUGIN_ROOT}/skills/document-authoring/references/approval-workflow.md

# After filling placeholders:
You are a document creation agent. Your task is to create the analysis.md
planning document for ticket APIV2.

Read the ticket README at /app/.sdd/tickets/APIV2_api-redesign/README.md
to understand the ticket intent.

Read the creation guide in /workspace/repos/claude-code-plugins/plugins/sdd/skills/document-authoring/references/doc-analysis.md
for detailed instructions, research steps, quality criteria, and the template reference.

Research the codebase thoroughly before writing. Fill in every section of the template
with specific, well-researched content. Cite actual files and patterns found during research.

Write the completed document to /app/.sdd/tickets/APIV2_api-redesign/planning/analysis.md

When complete, follow the approval workflow in
/workspace/repos/claude-code-plugins/plugins/sdd/skills/document-authoring/references/approval-workflow.md
```

### Placeholder Validation

Before filling placeholders, validate that `TICKET_ID`, `TICKET_PATH`, and `PLUGIN_ROOT` values are well-formed using the centralized validation script:

```sh
plugins/sdd/skills/document-authoring/scripts/validate-prompt-placeholders.sh \
  "$TICKET_ID" "$TICKET_PATH" "$PLUGIN_ROOT"
```

The script validates:
- **TICKET_ID**: Non-empty, matches `^[A-Z0-9_-]+$` (e.g., `DOCAGENT`, `UIT-9819`)
- **TICKET_PATH**: Non-empty, absolute path (starts with `/`), directory exists
- **PLUGIN_ROOT**: Non-empty, absolute path (starts with `/`), directory exists

On success the script exits 0 and prints an `OK` confirmation. On failure it exits 1 and prints clear error messages to stderr describing which value failed and what was expected. Always run this validation before proceeding with placeholder substitution and agent spawning.

### Input Validation

Before passing the filled prompt to `spawn-agent.sh`, the prompt text must pass input validation. The `spawn-agent.sh` script's Input Validation section rejects task descriptions containing:

- **Newlines**: Task descriptions cannot contain literal newline characters
- **Backticks**: No backtick characters allowed (prevents command injection)
- **Command substitution**: No `$(...)` patterns allowed
- **Variable expansion**: No `${...}` patterns allowed

See spawn-agent.sh for current implementation.

After placeholder substitution, verify that `{TICKET_ID}`, `{TICKET_PATH}`, and `{PLUGIN_ROOT}` values do not introduce any of these forbidden patterns. In practice, standard ticket IDs and file paths will not trigger these validations.

**Important:** The filled prompt must be a single line or be passed in a way that avoids literal newlines in the task argument. When using `spawn-agent.sh`, the multi-line prompt is passed as a single argument with the content concatenated. Alternatively, use the iTerm plugin scripts directly and pipe the prompt via `echo`.

### Tab Mode: Spawning via spawn-agent.sh

The simplest spawning method uses `spawn-agent.sh` to create a new iTerm tab:

```sh
/workspace/.devcontainer/scripts/spawn-agent.sh \
  /path/to/worktree \
  "filled prompt text (single line)"
```

`spawn-agent.sh` delegates to `iterm-open-tab.sh` (via wrapper-with-fallback pattern) and names the tab using the task description.

For document agents, use the naming convention `Doc: {document-type}`:

```sh
/workspace/.devcontainer/scripts/spawn-agent.sh \
  /workspace/repos/my-project \
  "Doc: analysis - You are a document creation agent..."
```

### Pane Mode: Spawning via spawn-agent.sh --pane

To spawn in a split pane instead of a new tab (requires an existing iTerm window):

```sh
/workspace/.devcontainer/scripts/spawn-agent.sh \
  /path/to/worktree \
  "filled prompt text" \
  --pane --direction vertical
```

The `--direction` flag accepts `vertical` (default) or `horizontal`.

### Direct iTerm Plugin Spawning

For more control, use the iTerm plugin scripts directly instead of `spawn-agent.sh`:

**Tab mode:**

```sh
plugins/iterm/skills/tab-management/scripts/iterm-open-tab.sh \
  --directory /workspace/repos/my-project \
  --profile Devcontainer \
  --name "Doc: analysis" \
  --command "echo 'filled prompt text' | claude --dangerously-skip-permissions"
```

**Pane mode:**

```sh
plugins/iterm/skills/pane-management/scripts/iterm-split-pane.sh \
  -d vertical \
  -p Devcontainer \
  -n "Doc: analysis" \
  -c "echo 'filled prompt text' | claude --dangerously-skip-permissions"
```

### Command Escaping

The `spawn-agent.sh` script's `build_claude_cmd()` function handles escaping for the transport layer. See spawn-agent.sh for current implementation.

```sh
build_claude_cmd() {
    local worktree_path="$1"
    local task="$2"
    local escape_mode="${3:-double}"  # "double", "single", or "none"

    local escaped_task=""
    if [[ -n "$task" ]]; then
        if [[ "$escape_mode" == "double" ]]; then
            escaped_task="${task//\"/\\\"}"
        elif [[ "$escape_mode" == "single" ]]; then
            escaped_task="${task//\'/\'\\\'\'}"
        elif [[ "$escape_mode" == "none" ]]; then
            escaped_task="$task"
        fi
    fi

    if [[ -n "$task" ]]; then
        echo "cd \"$worktree_path\" && echo \"$escaped_task\" | claude --dangerously-skip-permissions"
    else
        echo "cd \"$worktree_path\" && claude --dangerously-skip-permissions"
    fi
}
```

**Escape modes:**
- `double`: Escapes double quotes (for SSH transport to macOS host). Used in container/remote mode.
- `single`: Escapes single quotes (for direct osascript). Used in local macOS mode.
- `none`: No escaping (for plugin delegation). Used when delegating to iTerm plugin scripts.

When using `spawn-agent.sh`, escaping is handled automatically based on the execution context (container vs host). When using iTerm plugin scripts directly, pass the command with appropriate escaping for the context.

## Linear Execution Workflow

### Document Creation Order

The document dependency graph (see `references/document-dependency-graph.md`) defines the required order:

| Step | Level | Document | Dependencies |
|------|-------|----------|-------------|
| 1 | 0 | `analysis.md` | None |
| 2 | 1 | `prd.md` | analysis.md |
| 3 | 2 | `architecture.md` | prd.md |
| 4 | 3 | `plan.md` | architecture.md |
| 5 | 3 | `quality-strategy.md` | architecture.md |
| 6 | 3 | `security-review.md` | architecture.md |
| 7 | 4 | `README.md` | All others |

Within Level 3, the order of `plan.md`, `quality-strategy.md`, and `security-review.md` is flexible. The order shown above (plan, quality-strategy, security-review) is the recommended default.

### Step-by-Step Procedure

For each document in order:

1. **Read the initiation prompt** from `prompts/create/{document}.md`
2. **Fill placeholders** with `{TICKET_ID}`, `{TICKET_PATH}`, `{PLUGIN_ROOT}` values
3. **Validate the filled prompt** against the input validation rules (no newlines, backticks, `$(`, `${` in the final text)
4. **Spawn the agent** via `spawn-agent.sh` or iTerm plugin scripts
5. **Wait for the agent** to complete its work and present the approval prompt
6. **Approve or request changes** via the AskUserQuestion interaction:
   - "Approve and close tab/pane" -- proceed to next document, close the tab
   - "Approve" -- proceed to next document, keep the session open
   - "Suggest changes" -- provide feedback, agent revises, re-presents approval
7. **Close the tab/pane** (if "Approve and close" was selected, or manually)
8. **Proceed to the next document** in the dependency order

### Worked Example: Creating analysis.md then prd.md for ticket APIV2

This example demonstrates the complete workflow for the first two documents.

**Setup:**
- Ticket ID: `APIV2`
- Ticket path: `/app/.sdd/tickets/APIV2_api-redesign`
- Plugin root: `/workspace/repos/claude-code-plugins/plugins/sdd`
- Worktree: `/workspace/repos/my-project`

---

**Step 1: Read the dependency graph**

Read `references/document-dependency-graph.md` and determine that `analysis.md` is Level 0 (no dependencies). It is the first document to create.

**Step 2: Read the analysis creation prompt**

Read `prompts/create/analysis.md`:

```
You are a document creation agent. Your task is to create the analysis.md planning document for ticket {TICKET_ID}.

Read the ticket README at {TICKET_PATH}/README.md to understand the ticket intent.

Read the creation guide in {PLUGIN_ROOT}/skills/document-authoring/references/doc-analysis.md for detailed instructions, research steps, quality criteria, and the template reference.

Research the codebase thoroughly before writing. Fill in every section of the template with specific, well-researched content. Cite actual files and patterns found during research.

Write the completed document to {TICKET_PATH}/planning/analysis.md

When complete, follow the approval workflow in {PLUGIN_ROOT}/skills/document-authoring/references/approval-workflow.md
```

**Step 3: Fill placeholders**

Replace `{TICKET_ID}` with `APIV2`, `{TICKET_PATH}` with `/app/.sdd/tickets/APIV2_api-redesign`, and `{PLUGIN_ROOT}` with `/workspace/repos/claude-code-plugins/plugins/sdd`:

```
You are a document creation agent. Your task is to create the analysis.md planning document for ticket APIV2. Read the ticket README at /app/.sdd/tickets/APIV2_api-redesign/README.md to understand the ticket intent. Read the creation guide in /workspace/repos/claude-code-plugins/plugins/sdd/skills/document-authoring/references/doc-analysis.md for detailed instructions, research steps, quality criteria, and the template reference. Research the codebase thoroughly before writing. Fill in every section of the template with specific, well-researched content. Cite actual files and patterns found during research. Write the completed document to /app/.sdd/tickets/APIV2_api-redesign/planning/analysis.md When complete, follow the approval workflow in /workspace/repos/claude-code-plugins/plugins/sdd/skills/document-authoring/references/approval-workflow.md
```

(Note: Collapsed to a single line for `spawn-agent.sh` compatibility. Sentences are separated by spaces.)

**Step 4: Validate**

Check the filled prompt:
- No newlines: pass (collapsed to single line)
- No backticks: pass
- No `$(`: pass
- No `${`: pass

**Step 5: Spawn the analysis agent**

```sh
/workspace/.devcontainer/scripts/spawn-agent.sh \
  /workspace/repos/my-project \
  "You are a document creation agent. Your task is to create the analysis.md planning document for ticket APIV2. Read the ticket README at /app/.sdd/tickets/APIV2_api-redesign/README.md to understand the ticket intent. Read the creation guide in /workspace/repos/claude-code-plugins/plugins/sdd/skills/document-authoring/references/doc-analysis.md for detailed instructions, research steps, quality criteria, and the template reference. Research the codebase thoroughly before writing. Fill in every section of the template with specific, well-researched content. Cite actual files and patterns found during research. Write the completed document to /app/.sdd/tickets/APIV2_api-redesign/planning/analysis.md When complete, follow the approval workflow in /workspace/repos/claude-code-plugins/plugins/sdd/skills/document-authoring/references/approval-workflow.md"
```

The agent spawns in a new iTerm tab. It reads the reference document, researches the codebase, writes `analysis.md`, and presents the approval prompt.

**Step 6: Approve**

The agent presents:
- Question: "How would you like to proceed with analysis.md?"
- Options: "Approve and close tab/pane", "Approve", "Suggest changes"

Select "Approve and close tab/pane". The agent outputs the completion signal:

```
---
DOCUMENT_AGENT_COMPLETE
document: analysis.md
ticket: APIV2
status: approved
path: /app/.sdd/tickets/APIV2_api-redesign/planning/analysis.md
---
```

**Step 7: Close the tab**

Close the tab manually or via:

```sh
plugins/iterm/skills/tab-management/scripts/iterm-close-tab.sh --force "Doc: analysis"
```

**Step 8: Proceed to prd.md**

Now that `analysis.md` is approved, `prd.md` (Level 1) can be created. Read `prompts/create/prd.md`, fill placeholders, validate, and spawn:

```sh
/workspace/.devcontainer/scripts/spawn-agent.sh \
  /workspace/repos/my-project \
  "You are a document creation agent. Your task is to create the prd.md planning document for ticket APIV2. Read the ticket README at /app/.sdd/tickets/APIV2_api-redesign/README.md to understand the ticket intent. Read the completed analysis document at /app/.sdd/tickets/APIV2_api-redesign/planning/analysis.md first. The PRD must be consistent with the problem definition, constraints, and success criteria established there. Read the creation guide in /workspace/repos/claude-code-plugins/plugins/sdd/skills/document-authoring/references/doc-prd.md for detailed instructions, research steps, quality criteria, and the template reference. Translate analysis findings into concrete, testable requirements. Define clear scope boundaries and measurable acceptance criteria. Distinguish what the system must do from how it will be built. Write the completed document to /app/.sdd/tickets/APIV2_api-redesign/planning/prd.md When complete, follow the approval workflow in /workspace/repos/claude-code-plugins/plugins/sdd/skills/document-authoring/references/approval-workflow.md"
```

The prd.md agent reads the approved `analysis.md`, writes the PRD, and presents the approval prompt. Approve and proceed to `architecture.md`, continuing through all 7 documents.

---

This pattern repeats for all subsequent documents: architecture.md, plan.md, quality-strategy.md, security-review.md, and README.md. Each agent reads its prerequisites (the already-approved documents from earlier levels) and produces its document with fresh context.

## Approval Handling

### The Approval Workflow

Every document agent follows the standardized approval workflow defined in `references/approval-workflow.md`. Upon completing its document, the agent presents three choices via the AskUserQuestion tool:

| Choice | Description | Agent Behavior |
|--------|-------------|----------------|
| Approve and close tab/pane | Document is complete. Signal readiness to close. | Outputs completion signal, stops working. |
| Approve | Document is complete. Keep session open. | Outputs completion signal, remains available. |
| Suggest changes | Provide feedback for revision. | Accepts feedback, revises, re-presents choices. |

### Completion Signal

When approved (choice 1 or 2), the agent outputs:

```
---
DOCUMENT_AGENT_COMPLETE
document: {document_name}
ticket: {TICKET_ID}
status: approved
path: {TICKET_PATH}/planning/{document_name}
---
```

This signal is plain text output (stdout). An orchestrating agent can detect this signal to know when to proceed.

### Handling Rejections

When the user selects "Suggest changes":

1. The user provides freeform text describing the requested changes
2. The agent reads the feedback and identifies specific revisions
3. The agent applies revisions to the document
4. The agent re-presents the approval choices
5. This cycle repeats until the user approves

There is no limit on revision cycles. Each cycle consumes additional agent context, but since each agent is focused on a single document, context exhaustion is unlikely.

### Orchestrator Monitoring

An orchestrating agent monitors spawned agents by watching for the `DOCUMENT_AGENT_COMPLETE` signal in the tab/pane output. Upon detecting the signal:

1. Record that the document is complete
2. Close the tab/pane via iTerm plugin scripts
3. Check the dependency graph for the next available document
4. Spawn the next agent

## Error Recovery

### Agent Fails to Start

**Symptom:** Tab opens but Claude CLI does not start, or the tab closes immediately.

**Recovery:**
1. Check that `claude` is available in the worktree environment
2. Verify the prompt text passes input validation (no forbidden characters)
3. Check SSH connectivity (container mode): `ssh -o ConnectTimeout=5 ${HOST_USER}@host.docker.internal echo ok`
4. Retry the spawn with the same prompt

### Agent Produces Invalid Output

**Symptom:** The document is created but does not follow the template, is incomplete, or has incorrect content.

**Recovery:**
1. Select "Suggest changes" in the approval prompt and provide specific feedback
2. If the agent cannot fix the issues after 2-3 revision cycles, select "Approve and close tab/pane" and then spawn a new agent for the same document
3. The new agent will overwrite the existing document file

### Agent Hangs or Becomes Unresponsive

**Symptom:** The agent stops producing output and does not present the approval prompt.

**Recovery:**
1. Close the tab/pane manually or via `iterm-close-tab.sh --force "Doc: {document_type}"`
2. Re-spawn the agent with the same prompt
3. The new agent will start fresh and create the document from scratch

### Prerequisite Document Missing

**Symptom:** An agent for a Level 1+ document cannot find a required prerequisite document.

**Recovery:**
1. Verify that all prerequisite documents exist at the expected paths
2. Check that prerequisite documents were approved (not just created)
3. If missing, spawn the prerequisite document agent first and complete it before retrying

### spawn-agent.sh Exits with Error

**Exit codes from spawn-agent.sh:**

| Code | Meaning | Recovery |
|------|---------|----------|
| 0 | Success | No action needed |
| 1 | Input validation failure or general error | Fix the prompt text and retry |
| 2 | No iTerm windows open (pane mode only) | Open an iTerm window first, then retry |

## Cleanup

### Manual Cleanup

Close individual tabs or panes after each document is approved:

**Close a specific document tab:**
```sh
plugins/iterm/skills/tab-management/scripts/iterm-close-tab.sh --force "Doc: analysis"
```

**Close a specific review pane:**
```sh
plugins/iterm/skills/pane-management/scripts/iterm-close-pane.sh --force "Review: analysis"
```

**Close all document tabs at once:**
```sh
plugins/iterm/skills/tab-management/scripts/iterm-close-tab.sh --force "Doc:"
```

**Close all review tabs at once:**
```sh
plugins/iterm/skills/tab-management/scripts/iterm-close-tab.sh --force "Review:"
```

### Orchestrator Cleanup

An orchestrating agent closes tabs/panes programmatically after detecting the `DOCUMENT_AGENT_COMPLETE` signal:

1. After approval signal detected, close the tab/pane:
   ```sh
   iterm-close-tab.sh --force "Doc: {document_type}"
   ```
2. Verify the tab is closed:
   ```sh
   iterm-list-tabs.sh | grep "Doc: {document_type}"
   ```
   If no output, the tab is closed.

### End-of-Session Cleanup

After all 7 documents are created and approved, clean up any remaining tabs:

```sh
# Close all remaining document and review tabs
plugins/iterm/skills/tab-management/scripts/iterm-close-tab.sh --force "Doc:"
plugins/iterm/skills/tab-management/scripts/iterm-close-tab.sh --force "Review:"
```

## Troubleshooting

### Issue 1: Prompt Escaping Failures

**Symptoms:** spawn-agent.sh exits with error code 1 when spawning an agent. Error message references newlines, backticks, or command substitution.

**Cause:** The filled prompt text contains characters that fail the Input Validation section in spawn-agent.sh.

**Solution:**
1. Collapse the prompt to a single line (replace newlines with spaces)
2. Verify no backtick characters exist in the prompt
3. Verify no `$(` or `${` patterns exist in the prompt
4. Check that `{TICKET_PATH}` and `{PLUGIN_ROOT}` values do not contain special characters

### Issue 2: SSH Connection Failures (Container Mode)

**Symptoms:** "Failed to spawn agent" error. SSH connection timeout or permission denied.

**Cause:** Container cannot reach the macOS host via SSH.

**Solution:**
1. Verify `HOST_USER` is set: `echo $HOST_USER`
2. Test SSH connectivity: `ssh -o ConnectTimeout=5 ${HOST_USER}@host.docker.internal echo ok`
3. Check SSH keys are configured for passwordless access
4. Verify Docker's host.docker.internal DNS resolution

### Issue 3: Agent Cannot Find Reference Documents

**Symptoms:** The spawned agent reports it cannot read the reference document or approval workflow file.

**Cause:** The `{PLUGIN_ROOT}` placeholder was filled with an incorrect path.

**Solution:**
1. Verify the sdd plugin root path exists: `ls plugins/sdd/skills/document-authoring/references/`
2. Confirm the path used for `{PLUGIN_ROOT}` matches the actual plugin location
3. Check that the worktree contains the expected plugin files

### Issue 4: Agent Does Not Present Approval Prompt

**Symptoms:** The agent writes the document but does not invoke AskUserQuestion.

**Cause:** The agent did not read or follow the approval workflow reference.

**Solution:**
1. Check that the initiation prompt includes the line: "When complete, follow the approval workflow in {PLUGIN_ROOT}/skills/document-authoring/references/approval-workflow.md"
2. Verify the approval-workflow.md file exists at the referenced path
3. If the agent still does not present the prompt, close the tab and re-spawn

### Issue 5: No iTerm Windows Open (Pane Mode)

**Symptoms:** spawn-agent.sh exits with code 2 when using `--pane` flag.

**Cause:** Pane mode requires an existing iTerm window to split.

**Solution:**
1. Open an iTerm window first (manually or via `iterm-open-tab.sh`)
2. Then re-run the spawn command with `--pane`
3. Alternatively, use tab mode (omit `--pane`) which creates a new window if needed

### Issue 6: Document Dependency Violation

**Symptoms:** An agent writes a document that references missing prerequisite documents.

**Cause:** Documents were created out of order, or a prerequisite was not approved before proceeding.

**Solution:**
1. Refer to the dependency graph in `references/document-dependency-graph.md`
2. Verify all prerequisite documents exist and are approved
3. Re-spawn the failing agent after all prerequisites are complete

### SSH Connectivity Issues (Container Mode)

When running inside a devcontainer, agent spawning relies on SSH to reach the macOS host (where iTerm2 runs). If SSH is misconfigured, all `spawn-agent.sh` and iTerm plugin calls will fail. Use the steps below to diagnose and resolve SSH issues.

#### Testing SSH Connectivity

Run the following command from inside the container to verify basic connectivity:

```sh
ssh host.docker.internal
```

**Expected results:**
- **Success:** You are connected to the macOS host shell (or prompted for a password).
- **Failure indicators:** `Connection refused`, `No route to host`, `Connection timed out`, or `Permission denied (publickey)`.

For a more targeted test that exits immediately:

```sh
ssh -o ConnectTimeout=5 ${HOST_USER}@host.docker.internal echo ok
```

If this prints `ok`, SSH is working. Any other output indicates a problem -- continue with the diagnostic steps below.

#### Common SSH Failure Modes

| Failure Mode | Error Message | Likely Cause |
|--------------|---------------|--------------|
| SSH keys not configured in container | `Permission denied (publickey)` | Private key is missing from the container's `~/.ssh/` directory, or the corresponding public key is not in the host's `~/.ssh/authorized_keys`. |
| host.docker.internal unreachable | `No route to host` or `Could not resolve hostname` | Docker Desktop networking is misconfigured, or `host.docker.internal` DNS is not available (common on older Docker versions or Linux hosts without Docker Desktop). |
| SSH daemon not running on host | `Connection refused` on port 22 | The macOS host does not have Remote Login enabled. Enable it in System Settings > General > Sharing > Remote Login. |
| Firewall blocking SSH port 22 | `Connection timed out` | A firewall on the host or between the container and host is blocking port 22. Check macOS firewall settings and any network-level firewalls. |
| Docker Desktop SSH forwarding not enabled | `Connection refused` or timeout | Docker Desktop may need explicit configuration to allow SSH from containers to the host. Verify Docker Desktop settings under Resources > Network. |
| Wrong HOST_USER value | `Permission denied` or connection to wrong account | The `HOST_USER` environment variable does not match the macOS username. Verify with `echo $HOST_USER` in the container and `whoami` on the host. |

#### Verification Steps

Work through these steps in order. Each step builds on the previous one.

**Step 1: Verify HOST_USER is set**

```sh
echo $HOST_USER
```

If empty, set it in `devcontainer.json` under `remoteEnv` or export it manually:

```sh
export HOST_USER="your-macos-username"
```

**Step 2: Verify host.docker.internal resolves**

```sh
ping -c 1 host.docker.internal
```

Expected: A response from an IP address (typically `192.168.65.254` or similar). If this fails, Docker Desktop networking is not providing the `host.docker.internal` DNS entry. Restart Docker Desktop or check its network configuration.

**Step 3: Check SSH key exists and has correct permissions**

```sh
ls -la ~/.ssh/id_rsa ~/.ssh/id_ed25519 2>/dev/null
```

At least one private key file should exist. Verify permissions:

```sh
# Private key must be 600 (owner read/write only)
stat -c '%a %n' ~/.ssh/id_rsa 2>/dev/null || stat -c '%a %n' ~/.ssh/id_ed25519 2>/dev/null
```

If permissions are wrong, fix them:

```sh
chmod 600 ~/.ssh/id_rsa 2>/dev/null
chmod 600 ~/.ssh/id_ed25519 2>/dev/null
```

**Step 4: Check SSH config for host.docker.internal entry**

```sh
grep -A 3 "host.docker.internal" ~/.ssh/config 2>/dev/null
```

If no entry exists, SSH will use defaults. For explicit configuration, add to `~/.ssh/config`:

```
Host host.docker.internal
    User your-macos-username
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no
```

**Step 5: Run verbose SSH test**

```sh
ssh -v host.docker.internal 2>&1 | grep -E "(connect|auth|identity|Offering)"
```

This shows the connection and authentication flow. Look for:
- `Connection established` -- network connectivity is working
- `Offering public key` -- SSH is attempting key authentication
- `Authentication succeeded` -- login was successful

If authentication fails, verify the public key is in the host's `~/.ssh/authorized_keys`.

**Step 6: Test the full spawn chain**

```sh
ssh ${HOST_USER}@host.docker.internal "osascript -e 'tell application \"iTerm\" to get name of current window'"
```

This confirms SSH works, `osascript` is accessible, and iTerm2 is running. If this succeeds, agent spawning should work.

#### Fallback: Use Task Tool When SSH Is Unavailable

If SSH cannot be established (for example, on a remote server without Docker Desktop, or in a CI environment), you can still create planning documents by using the Task tool instead of spawning iTerm agents. The Task tool runs a sub-agent inline within the current session -- no SSH or iTerm required.

**When to use the Task tool fallback:**
- SSH connectivity cannot be restored after following the verification steps above
- Running in an environment where iTerm2 is not available (Linux host, CI/CD, remote server)
- Temporary workaround while SSH issues are being resolved

**Example Task tool usage for document creation:**

```
Task: Create analysis.md for ticket DOCAGENT
Use the initiation prompt from prompts/create/analysis.md
Fill placeholders: TICKET_ID=DOCAGENT, TICKET_PATH=/path/to/ticket, PLUGIN_ROOT=/path/to/plugin
Write output to /path/to/ticket/planning/analysis.md
```

**Differences from iTerm agent spawning:**
- The Task tool runs within the current session's context budget, not in a fresh session
- There is no separate tab/pane to manage (no cleanup needed)
- The approval workflow still applies -- the sub-agent presents the same approval choices
- Multiple documents consume cumulative context, similar to the monolithic ticket-planner approach

For best results with the Task tool fallback, create documents one at a time and keep the prompts focused. If context becomes exhausted, start a new session and continue with the next document.

## Future Enhancements

### Parallel Execution

The document dependency graph supports concurrent execution of independent documents. Level 3 documents (plan.md, quality-strategy.md, security-review.md) are independent of each other and could be spawned simultaneously:

1. Spawn Level 0-2 documents sequentially (analysis, PRD, architecture)
2. After architecture.md is approved, spawn all three Level 3 documents concurrently
3. Wait for all three to be approved
4. Spawn README.md

This would reduce total time from 50-90 minutes to approximately 35-60 minutes for the 7-document workflow. Parallel execution is planned for a future iteration.

### Orchestrator Command

A future `/sdd:plan-ticket-parallel` command could automate the entire per-document workflow:

1. Scaffold the ticket (using existing scaffold-ticket.sh)
2. Spawn document agents in dependency order
3. Present approvals to the user
4. Track completion via `DOCUMENT_AGENT_COMPLETE` signals
5. Report final status

### Automated Quality Comparison

Future instrumentation could automatically compare document quality between the monolithic ticket-planner and per-document agents for the same ticket, providing data to inform the decision tree.

## Integration

### With Existing SDD Workflow

This skill integrates with the existing SDD workflow at the ticket planning stage:

```
/sdd:plan-ticket (monolithic)     OR     Per-document agents (this skill)
         |                                        |
         v                                        v
/sdd:review                              (each document reviewed individually)
         |                                        |
         v                                        v
/sdd:create-tasks                        /sdd:create-tasks
         |                                        |
         v                                        v
/sdd:do-all-tasks                        /sdd:do-all-tasks
```

Both paths produce the same planning documents. The per-document approach adds more review interaction but produces higher-quality output for complex tickets.

### With iTerm Plugin

This skill relies on existing iTerm plugin capabilities:

| Operation | Script | Skill |
|-----------|--------|-------|
| Open tab | `iterm-open-tab.sh` | tab-management |
| Close tab | `iterm-close-tab.sh` | tab-management |
| List tabs | `iterm-list-tabs.sh` | tab-management |
| Split pane | `iterm-split-pane.sh` | pane-management |
| Close pane | `iterm-close-pane.sh` | pane-management |

No new iTerm scripts are required. All agent spawning delegates to these existing scripts (directly or via `spawn-agent.sh`).

### With spawn-agent.sh

The `spawn-agent.sh` script at `/workspace/.devcontainer/scripts/spawn-agent.sh` is the primary spawning wrapper. Key integration points:

- **Input validation** (Input Validation section): Validates task descriptions before spawning
- **build_claude_cmd** (build_claude_cmd function): Builds the Claude CLI command with appropriate escaping
- **Tab mode** (spawn_agent_tab function): Delegates to iterm-open-tab.sh or falls back to original AppleScript
- **Pane mode** (spawn_agent_pane function): Delegates to iterm-split-pane.sh or falls back to original AppleScript

## Related

- **project-workflow** skill: Provides the document templates that per-document agents fill. Located at `plugins/sdd/skills/project-workflow/`.
- **tab-management** skill (iterm plugin): Tab open/close/list operations. Located at `plugins/iterm/skills/tab-management/`.
- **pane-management** skill (iterm plugin): Pane split/close/list operations. Located at `plugins/iterm/skills/pane-management/`.
- **ticket-planner** agent: The monolithic alternative. Located at `plugins/sdd/agents/ticket-planner.md`.
- **ticket-reviewer** agent: Reviews all documents at once. Located at `plugins/sdd/agents/ticket-reviewer.md`.
- **document-dependency-graph.md**: Defines creation order. Located at `plugins/sdd/skills/document-authoring/references/document-dependency-graph.md`.
- **approval-workflow.md**: Defines the approval interaction pattern. Located at `plugins/sdd/skills/document-authoring/references/approval-workflow.md`.
