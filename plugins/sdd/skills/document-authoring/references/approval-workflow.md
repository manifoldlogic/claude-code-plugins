# Approval Workflow

This document defines the standardized approval interaction that every document agent uses upon completing its work. All per-document agents (creation and review) follow this same pattern to provide a consistent user experience.

## Overview

When a document agent finishes creating or reviewing a document, it presents the user with three choices via the **AskUserQuestion** tool. The user's response determines whether the agent exits, continues its session, or revises the document.

This workflow is referenced by all initiation prompts in `{PLUGIN_ROOT}/skills/document-authoring/prompts/` and should be followed exactly as specified.

## AskUserQuestion Invocation

After the agent completes its document work (creation or review), it invokes AskUserQuestion with the following parameters:

**Question:** "How would you like to proceed with {document_name}?"
**Header:** "Document approval"
**multiSelect:** false

**Options:**
- Label: "Approve and close tab/pane" | Description: "Document is complete. Signal readiness to close this session."
- Label: "Approve" | Description: "Document is complete. Keep this session open for further work."
- Label: "Suggest changes" | Description: "Provide feedback for revision."

Where `{document_name}` is the specific document being worked on (e.g., "analysis.md", "prd.md", "architecture.md").

## Behavior for Each Choice

### Choice 1: "Approve and close tab/pane"

The user has approved the document and wants this agent session to end.

**Agent behavior:**
1. Write the completion signal (see Completion Signal Format below)
2. Output a final status summary confirming the document is approved
3. Stop working -- do not take further actions

The agent does **not** close the tab or pane itself. Closing the tab/pane is the responsibility of:
- **Manual/power-user mode:** The user closes the tab/pane manually, or runs the appropriate iterm plugin script (e.g., `iterm-close-tab.sh --force "Doc: analysis"`)
- **Orchestrator mode:** The orchestrating agent detects the completion signal and closes the tab/pane using iterm plugin scripts

### Choice 2: "Approve"

The user has approved the document but wants to keep this agent session open.

**Agent behavior:**
1. Write the completion signal (see Completion Signal Format below)
2. Output a status summary confirming the document is approved
3. Remain active and available for follow-up questions or additional work in the same session

This choice is useful when the user wants to:
- Ask the agent about the document content
- Have the agent assist with a related follow-up task
- Keep the session open while they review the document manually

### Choice 3: "Suggest changes"

The user wants to provide feedback and have the agent revise the document.

**Agent behavior:**
1. Accept the user's freeform text input describing the requested changes
2. Read the feedback carefully and identify specific revisions needed
3. Apply the revisions to the document
4. Present the updated document or a summary of changes made
5. Re-invoke the AskUserQuestion approval workflow (repeat from the top)

The revision loop continues until the user selects "Approve and close tab/pane" or "Approve". There is no limit on the number of revision cycles.

## Completion Signal Format

When the user approves a document (either choice 1 or choice 2), the agent outputs a standardized completion signal. This signal allows an orchestrating agent to detect that the document work is finished.

**Format:**

```
---
DOCUMENT_AGENT_COMPLETE
document: {document_name}
ticket: {TICKET_ID}
status: approved
path: {TICKET_PATH}/planning/{document_name}
---
```

**Example:**

```
---
DOCUMENT_AGENT_COMPLETE
document: analysis.md
ticket: APIV2
status: approved
path: /app/.sdd/tickets/APIV2_api-redesign/planning/analysis.md
---
```

The completion signal is plain text output (not written to a file). It is emitted to stdout so that an orchestrator monitoring the agent's output can detect it.

## Tab/Pane Closing: Responsibility Model

The agent running inside a tab or pane cannot close its own tab. Tab/pane lifecycle management is handled externally.

### Manual / Power-User Mode

When a user manually spawns document agents (without an orchestrator), they are responsible for closing tabs and panes themselves:

- Close via iTerm UI (click the close button or use keyboard shortcut)
- Close via CLI: `iterm-close-tab.sh --force "Doc: {document_type}"`
- Close pane via CLI: `iterm-close-pane.sh --force "Doc: {document_type}"`

The agent's "Approve and close tab/pane" choice signals intent but does not perform the close action.

### Orchestrator Mode

When an orchestrating agent spawns document agents, the orchestrator is responsible for monitoring and cleanup:

1. Orchestrator spawns the document agent in a named tab/pane (e.g., "Doc: analysis")
2. Orchestrator monitors agent output for the `DOCUMENT_AGENT_COMPLETE` signal
3. Upon detecting the signal, the orchestrator closes the tab/pane using iterm plugin scripts:
   - Tab: `iterm-close-tab.sh --force "Doc: {document_type}"`
   - Pane: `iterm-close-pane.sh --force "Doc: {document_type}"`
4. Orchestrator proceeds to the next document in the dependency graph

This follows the existing pattern documented in the pane-management SKILL.md (Scenario 5: "Pane Cleanup After Agents Complete").

## Integration with Document Agents

Every per-document initiation prompt (in `{PLUGIN_ROOT}/skills/document-authoring/prompts/create/` and `{PLUGIN_ROOT}/skills/document-authoring/prompts/review/`) includes an instruction to follow this approval workflow upon completion. The prompt references this file by path:

```
When complete, follow the approval workflow in:
{PLUGIN_ROOT}/skills/document-authoring/references/approval-workflow.md
```

The agent reads this document at the appropriate time and follows the invocation pattern exactly.

## Example: Full Approval Interaction

**Scenario:** Agent has finished creating `analysis.md` for ticket APIV2.

1. Agent presents AskUserQuestion:
   - Question: "How would you like to proceed with analysis.md?"
   - Options: "Approve and close tab/pane", "Approve", "Suggest changes"

2. User selects "Suggest changes" and types: "Add more detail about the existing API versioning strategy"

3. Agent revises analysis.md with additional detail about API versioning

4. Agent re-presents AskUserQuestion with the same three options

5. User selects "Approve and close tab/pane"

6. Agent outputs:
   ```
   ---
   DOCUMENT_AGENT_COMPLETE
   document: analysis.md
   ticket: APIV2
   status: approved
   path: /app/.sdd/tickets/APIV2_api-redesign/planning/analysis.md
   ---
   ```

7. Agent outputs final status: "analysis.md approved and complete. This session is ready to close."

8. Agent stops working

9. (Orchestrator or user closes the tab/pane externally)
