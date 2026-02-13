---
name: sdd-spec-search
description: Search SDD spec directories using maproom for tickets, epics, planning docs, and architecture decisions.
origin: MAPSPEC
created: 2026-02-13
tags: [maproom, sdd, spec-search, documentation-search]
---

# SDD Spec Search

## Overview

This skill documents how to use maproom to search SDD (Spec-Driven Development) specification directories for tickets, epics, planning documents, and architecture decisions. It extends the general-purpose `maproom-search` skill with SDD-specific patterns, directory structure knowledge, and search strategies tailored to spec content.

SDD specs live in a separate directory tree from source code, pointed to by the `SDD_ROOT_DIR` environment variable. When this directory has been indexed by maproom, agents can use semantic search to find design rationale, ticket history, planning context, and architecture decisions without reading every file manually.

This skill does not duplicate general maproom command syntax or setup instructions. For command reference, first-time setup, and troubleshooting, see the `maproom-search` skill referenced below.

## When to Use

Apply this skill when:

- Searching for a ticket's planning documents (analysis, architecture, PRD) during task execution
- Looking up design rationale or architecture decisions before modifying code
- Finding related tickets or epics that cover a similar domain
- Searching for acceptance criteria or quality strategy across multiple tickets
- Checking if a similar problem was already addressed in a prior ticket
- Needing historical context about why a feature was designed a certain way

**Decision: maproom vs Grep vs Glob for specs**

| Situation | Tool | Why |
|-----------|------|-----|
| Know the ticket ID exactly | Grep or Glob | Direct file lookup is faster than search |
| Know the exact file path | Read | No search needed |
| Looking for a concept across specs | maproom `vector-search` | Semantic match across all indexed spec content |
| Looking for a specific term in specs | maproom `search` (FTS) | Exact term matching across indexed chunks |
| Spec repo not indexed in maproom | Grep + Glob | Fallback to file-level search tools |
| Searching within a single known ticket directory | Grep | Scoped search is more efficient |

## Pattern/Procedure

### Prerequisites

Before using maproom for SDD spec search, verify two conditions:

**Step 1: Verify `SDD_ROOT_DIR` is set**

```bash
echo "$SDD_ROOT_DIR"
```

If empty, `SDD_ROOT_DIR` was not configured. The SDD plugin's `setup-sdd-env.js` hook sets this at session start. It defaults to `/app/.sdd` but is typically overridden in `.claude/settings.json` to point to the project's spec directory (e.g., `/workspace/_SPECS/claude-code-plugins`).

**Step 2: Verify the spec repo is indexed in maproom**

```bash
crewchief-maproom status
```

Look for a repository entry whose path matches or contains `SDD_ROOT_DIR`. If no matching repository appears, the spec directory has not been scanned. See the Fallback section below.

**Step 3: Identify the maproom repo name**

The maproom repo name is assigned during `crewchief-maproom scan --repo <name>`. It does not follow a fixed formula. Use `crewchief-maproom status` to find the repo name whose worktree path matches `SDD_ROOT_DIR`.

Example: If `SDD_ROOT_DIR=/workspace/_SPECS/claude-code-plugins` and status shows:
```
Repository: claude-code-plugins-specs
  Worktree: main
    Path: /workspace/_SPECS/claude-code-plugins
    Chunks: 850
```
Then use `--repo claude-code-plugins-specs` in search commands.

### SDD Directory Structure

The spec directory under `SDD_ROOT_DIR` contains the following structure:

<!-- KEEP IN SYNC WITH: scaffold-ticket.sh, scaffold-epic.sh -->
```
{SDD_ROOT_DIR}/
├── epics/
│   └── {DATE}_{name}/                    # or {DATE}_{jira_id}_{name}/
│       ├── overview.md                    # Vision, scope, success signals
│       ├── decisions.md                   # Running decision log
│       ├── backlog.md                     # Ideas not yet tickets
│       ├── analysis/
│       │   ├── opportunity-map.md         # Problem spaces, goals, constraints
│       │   ├── domain-model.md            # Core entities and boundaries
│       │   └── research-synthesis.md      # Key findings, open questions
│       ├── decomposition/
│       │   ├── multi-ticket-overview.md   # Ticket execution order
│       │   └── ticket-summaries/          # Per-ticket summaries
│       └── reference/                     # External reference materials
├── tickets/
│   └── {TICKET_ID}_{name}/
│       ├── README.md                      # Ticket overview and status
│       ├── planning/
│       │   ├── analysis.md                # Problem analysis
│       │   ├── prd.md                     # Product Requirements Document
│       │   ├── architecture.md            # Solution design and decisions
│       │   ├── plan.md                    # Execution plan with phases
│       │   ├── quality-strategy.md        # Testing approach and coverage
│       │   └── security-review.md         # Security assessment
│       ├── tasks/
│       │   └── {TASK_ID}_{name}.md        # Individual task files
│       └── deliverables/                  # Work products
├── archive/
│   ├── tickets/                           # Completed tickets
│   └── epics/                             # Completed epics
├── reference/                             # Shared reference templates
├── research/                              # Research materials
├── scratchpad/                            # Working notes
└── logs/                                  # Execution logs
```

### FTS vs Vector Search for Spec Content

| Content Type | Recommended Search | Why |
|---|---|---|
| Ticket by ID (e.g., `APIV2`) | FTS `search` | Ticket IDs are exact identifiers |
| Section headings (`Risk Assessment`) | FTS `search` | Heading text is literal |
| Architecture decisions | `vector-search` | Decisions use varied natural language |
| Design rationale ("why was X built this way") | `vector-search` | Intent-based queries need semantic matching |
| Acceptance criteria for a feature | `vector-search` | Criteria phrasing varies across tickets |
| Planning doc by known term | FTS `search` | Known terms match directly |
| Quality strategy patterns | `vector-search` | Testing approaches described conceptually |
| Task files for a specific ticket | FTS `search` | Task IDs are exact identifiers |
| Cross-ticket dependency analysis | `vector-search` | Dependencies described in natural language |

**Rule of thumb:** If you have an ID or exact term, use FTS. If you have a question or concept, use vector search. This mirrors the general guidance in `maproom-search` but applies specifically to spec document types.

### Search Workflow

1. **Read** `SDD_ROOT_DIR` from environment
2. **Check** maproom status for the spec repo name
3. **Choose** FTS or vector search based on the content type table above
4. **Run** the search with the spec repo name
5. **Read** the matching file for full context (search results show chunks, not full documents)

### Fallback: When Spec Repo Is Not Indexed

If `crewchief-maproom status` does not show the spec directory, fall back to Grep and Glob:

**Find a ticket by ID:**
```bash
# Using Glob to find the ticket directory
# Pattern: {SDD_ROOT_DIR}/tickets/{TICKET_ID}_*
```
Use the Glob tool with pattern `tickets/APIV2_*/**/*.md` under `SDD_ROOT_DIR`.

**Search across all planning docs:**
Use the Grep tool with the search pattern across `SDD_ROOT_DIR`, filtering to `*.md` files.

**Find architecture decisions:**
Use the Grep tool searching for "Decision" or "Rationale" in `planning/architecture.md` files under `SDD_ROOT_DIR`.

The fallback approach is slower and less precise than maproom search but works without any indexing setup.

#### Multiple Spec Repositories

If `crewchief-maproom status` shows multiple repos with overlapping paths:

1. Use the repo with the **longest matching path prefix** for your `SDD_ROOT_DIR`
2. Example:
   - Repo A indexed at: `/workspace/_SPECS/`
   - Repo B indexed at: `/workspace/_SPECS/claude-code-plugins/`
   - Your SDD_ROOT_DIR: `/workspace/_SPECS/claude-code-plugins`
   - **Use Repo B** (most specific match)

See [multi-repo-guide.md](../maproom-search/references/multi-repo-guide.md) for advanced path resolution patterns.

### Troubleshooting Common Issues

#### "command not found: crewchief-maproom"

- **Symptom**: Shell returns "command not found" when running `crewchief-maproom`
- **Cause**: CLI not installed or not in PATH
- **Solution**: Install via npm (`npm install -g @crewchief/maproom`) or use fallback Grep/Glob search as described in the Fallback section above. See `maproom-search` skill (`plugins/maproom/skills/maproom-search/SKILL.md`) for full installation and setup guidance.

#### "repository not found" or "repository 'X' not found"

- **Symptom**: Search returns a "repository not found" error
- **Cause**: Incorrect repo name or repo not indexed
- **Solution**: Run `crewchief-maproom status` to list all indexed repositories and find the correct name matching your `SDD_ROOT_DIR` path. The repo name is assigned during `crewchief-maproom scan --repo <name>` and does not follow a fixed formula.

#### "no results found" / empty results

- **Symptom**: Search returns no matches for a query that should have results
- **Cause**: Query too specific, wrong search mode, or content not yet indexed
- **Solution**: Try `vector-search` instead of FTS (or vice versa) based on the FTS vs Vector Search table above. Broaden query terms, remove overly specific identifiers, and verify the repo is indexed with `crewchief-maproom status`. If the repo shows zero chunks, re-run `crewchief-maproom scan`.

#### SDD_ROOT_DIR unset or incorrect

- **Symptom**: Cannot determine the spec directory path; `echo "$SDD_ROOT_DIR"` returns empty or an incorrect path
- **Cause**: Environment variable not configured by the SDD plugin's `setup-sdd-env.js` hook
- **Solution**: Check `.claude/settings.json` for the `SDD_ROOT_DIR` setting. The hook (`plugins/sdd/hooks/setup-sdd-env.js`) reads this value at session start and exports it. If the setting is missing, ask the developer to add it to their project's `.claude/settings.json`.

#### Permission denied on spec directory

- **Symptom**: Error accessing spec files when reading search results or browsing the spec directory
- **Cause**: File permission issue on the spec directory or its contents
- **Solution**: Check directory permissions with `ls -la "$SDD_ROOT_DIR"`. Ensure the current user has read access to the directory tree. In containerized environments, verify the volume mount includes appropriate permissions.

## Examples

### Example 1: Find a Ticket's Planning Documents by ID

**Context:** You need to review the architecture decisions for ticket APIV2 before implementing a task.

**Search:**
```bash
crewchief-maproom search --repo claude-code-plugins-specs --query "APIV2"
```

**What this finds:** All chunks containing the ticket ID, including the README, planning documents, and task files. Results include `heading_1`, `heading_2`, and `markdown_section` chunks from the ticket's directory.

**Follow-up:** Read the `architecture.md` file from the search results to get the full design context:
```bash
crewchief-maproom search --repo claude-code-plugins-specs --query "APIV2 architecture decision rationale"
```

> **Note:** Example repo names like `claude-code-plugins-specs` are placeholders. Replace with your actual repo name from `crewchief-maproom status`. The repo name must match your `SDD_ROOT_DIR` path.

### Example 2: Search for Design Rationale Across All Tickets

**Context:** You are about to redesign the plugin system and want to find any prior architecture decisions related to plugins.

**Search:**
```bash
crewchief-maproom vector-search --repo claude-code-plugins-specs --query "plugin system design decisions"
```

**Why vector search:** The query describes a concept. Different tickets may use varied terminology ("plugin architecture", "extension system", "hook framework") that vector search can match semantically.

**Narrowing results:** If results span too many tickets, add more specific terms:
```bash
crewchief-maproom vector-search --repo claude-code-plugins-specs --query "plugin loading registration lifecycle"
```

### Example 3: Find All Tickets Related to a Domain

**Context:** You want to find all tickets that dealt with authentication or authorization to understand the evolution of the auth system.

**Search:**
```bash
crewchief-maproom vector-search --repo claude-code-plugins-specs --query "authentication authorization security access control"
```

**Follow-up with FTS:** After identifying relevant ticket IDs from vector search results, use FTS to find their specific task files:
```bash
crewchief-maproom search --repo claude-code-plugins-specs --query "AUTHZ"
```

### Example 4: Search Epic Analysis Documents

**Context:** You are starting a new epic and want to see how previous epics structured their research and domain analysis.

**Search:**
```bash
crewchief-maproom vector-search --repo claude-code-plugins-specs --query "domain model entities boundaries research synthesis"
```

**What this finds:** Chunks from `analysis/domain-model.md` and `analysis/research-synthesis.md` files across epics, showing how prior work structured domain analysis.

**Alternative with FTS for specific epic content:**
```bash
crewchief-maproom search --repo claude-code-plugins-specs --query "opportunity map constraints"
```

### Example 5: Find Quality Strategy Patterns

**Context:** You need to write a quality strategy for a new ticket and want to reference how testing was approached in similar tickets.

**Search:**
```bash
crewchief-maproom vector-search --repo claude-code-plugins-specs --query "testing strategy coverage requirements quality gates"
```

**What this finds:** Chunks from `planning/quality-strategy.md` files across tickets, showing testing approaches, coverage thresholds, and quality gate definitions used in prior work.

## References

- Origin: MAPSPEC (SDD Spec Search skill creation)
- Related skills:
  - `maproom-search` (`plugins/maproom/skills/maproom-search/SKILL.md`) - General maproom command reference, first-time setup, search type guidance, troubleshooting, and multi-repo search patterns
  - `multi-repo-guide` (`plugins/maproom/skills/maproom-search/references/multi-repo-guide.md`) - Cross-repo search strategies, chunk kinds by repo type, and configuration setup guide
- Related files:
  - `plugins/sdd/hooks/setup-sdd-env.js` - How `SDD_ROOT_DIR` is set at session start
  - `plugins/sdd/skills/project-workflow/scripts/scaffold-ticket.sh` - Ticket directory structure and planning doc templates
  - `plugins/sdd/skills/project-workflow/scripts/scaffold-epic.sh` - Epic directory structure and analysis doc templates
  - `.claude/settings.json` - Where `SDD_ROOT_DIR` is configured per-project
