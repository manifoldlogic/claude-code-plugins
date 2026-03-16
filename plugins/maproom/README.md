# Maproom Plugin

## Introduction

The Maproom plugin provides semantic code search capabilities powered by the maproom CLI. It enables Claude Code to search, analyze, and understand codebases using both full-text search (FTS) and vector-based semantic search. With Maproom, you can find code by concept rather than just exact text matches, explore relationships between code elements, and gain architectural insights across large codebases.

## Features

- **Full-Text Search (FTS)**: Fast, precise keyword-based search for exact matches, identifiers, and specific terms
- **Vector Semantic Search**: Find code by meaning and concept, even when exact keywords differ
- **Agent-Optimized Output**: Compact `--format agent` mode designed for LLM context efficiency
- **Hybrid Search**: Combines FTS and vector search for optimal relevance ranking
- **Context Expansion**: Automatically retrieve related code including imports, callers, callees, and tests
- **Graph Relationships**: Navigate code relationships through call graphs and dependency analysis
- **Multi-Repository Support**: Configuration template and agent guidance for searching across code and documentation repositories with repo-specific search strategies
- **Language Aware**: Leverages tree-sitter for syntax-aware indexing and search

## Multi-Repo Setup

Search across multiple repositories by configuring repo-specific search strategies and agent guidance.

1. Copy the configuration template to your workspace root:
   ```bash
   cp plugins/maproom/skills/maproom-search/templates/maproom-repos.yaml ./maproom-repos.yaml
   ```
2. Customize repo entries for your workspace (paths, descriptions, search guidance)
3. Set environment variables for path portability (`MAPROOM_REPOS_ROOT`, `MAPROOM_SPECS_ROOT`)
4. Index each repo with `maproom scan`

See [multi-repo-guide.md](skills/maproom-search/references/multi-repo-guide.md) for detailed setup instructions, search strategies by repo type, and cross-repo search patterns.

## Prerequisites

Before using the Maproom plugin, ensure you have:

1. **maproom CLI installed**: The plugin requires the `maproom` command-line tool to be available in your system PATH
2. **Minimum maproom version**: 0.1.0. Verify your version:
   ```bash
   maproom --version
   ```
3. **Indexed database**: Your codebase must be scanned using `maproom scan` before searching
4. **Database location**: The maproom database is typically located at `~/.maproom/maproom.db` (can be overridden with `MAPROOM_DATABASE_URL` environment variable)

To verify your setup:
```bash
# Check CLI is installed
maproom --version

# Index your repository
maproom scan

# Verify indexing succeeded
maproom status
```

## Installation

Install the Maproom plugin using the Claude Code plugin command:

```
/plugin install maproom@crewchief
```

Once installed, the plugin will automatically be available for use in your Claude Code sessions.

## Usage Examples

### Basic Semantic Search
```
Find authentication logic in the codebase
```
The plugin will use semantic search to find authentication-related code, even if it doesn't use the exact term "authentication".

### Finding Specific Functions
```
Search for the WebSocket disconnect handler
```
Locates WebSocket disconnect functionality using hybrid search.

### Exploring Error Handling
```
Show me how errors are handled in the checkout process
```
Finds error handling patterns in checkout-related code.

### Architecture Understanding
```
What components handle user sessions?
```
Identifies session management components and their relationships.

### Code Relationships
```
Find all callers of the validateCart function
```
Uses context expansion to show where validateCart is called throughout the codebase.

## Troubleshooting

### CLI Not Found
**Problem**: Plugin reports `maproom: command not found`

**Solution**:
- Verify the CLI is installed: `command -v maproom`
- Ensure it's in your PATH
- If using a development build, run `pnpm build` in the crewchief repository

### Database Not Indexed
**Problem**: Search returns "no repositories indexed" or empty results

**Solution**:
- Run `maproom scan` to index your codebase
- Check indexing status: `maproom status`
- Verify database exists: `ls -la ~/.maproom/maproom.db`

### No Results Found
**Problem**: Searches return no results or irrelevant matches

**Solution**:
- Try different search terms or phrasing
- Use more specific queries (2-3 core technical terms work best)
- Check if the repository is actually indexed: `maproom status`
- Verify file types are indexed (use `--file-type` filter if needed)
- Try different search modes: hybrid (default), fts, or vector
- For very recent code changes, re-index: `maproom scan --force`

### Stale Results
**Problem**: Search results don't reflect recent code changes

**Solution**:
- Re-index the repository: `maproom scan`
- The daemon auto-refreshes but may need manual reindexing for major changes

### Performance Issues
**Problem**: Searches are slow or timing out

**Solution**:
- Reduce the number of results requested (use `k` parameter)
- Use FTS mode for exact keyword matches (faster than semantic search)
- Check database size: large databases may need optimization
- Ensure SQLite isn't locked by another process

## Index Maintenance

The maproom semantic index requires periodic scanning to stay current with codebase changes.

**Recommended scan frequency:**
- **Active repositories** (daily commits): Run `maproom scan` daily or before research sessions
- **Stable repositories** (weekly/monthly updates): Run `maproom scan` weekly
- **One-time analysis**: Run `maproom scan` once before invoking maproom-researcher agent

**Scan command:**
```bash
maproom scan [--repo-path /path/to/repo]
```

**Index freshness check:**
```bash
maproom status  # Shows last scan timestamp
```

**Note:** The maproom-researcher agent does NOT automatically trigger index scans. Users must ensure the index is current before invoking the agent for accurate semantic search results.

## Maintenance

### Monthly CLI Verification

**Purpose:** Detect maproom CLI flag deprecation or behavior changes before agents encounter failures. The CLI is at v0.1.0 (pre-release), where breaking changes are allowed per semver. 52 command examples across plugin documentation depend on 6 CLI flags; if any flag is renamed or removed, agents will learn deprecated syntax and encounter command failures.

**Automation:** This procedure is automated via GitHub Actions (see `.github/workflows/monthly-cli-verification.yml`). The workflow runs on the first Friday of each month and creates a GitHub issue if drift is detected. Manual execution is still supported for ad-hoc verification using the `workflow_dispatch` trigger or by running the script directly:
```bash
bash plugins/maproom/scripts/monthly-cli-verification.sh
```

**Automated Baseline Diff:** Run `bash plugins/maproom/scripts/compare-cli-flags.sh` to automatically detect flag drift against the baseline verification document. The script extracts flags from both the baseline (`cli-flag-verification.md`) and the current CLI help output, then reports any added or removed flags. Exit 0 = no drift, exit 1 = drift detected, exit 2 = usage error.

**Cadence:** First Friday of each month

**Owner:** Maproom plugin maintainer

**Procedure:**

- [ ] Navigate to the maproom plugin directory:
  ```bash
  cd plugins/maproom
  ```
- [ ] Run `maproom --version` and verify the version matches the documented version (currently 0.1.0):
  ```bash
  maproom --version
  ```
- [ ] Run `maproom search --help` and verify all expected flags are present:
  ```bash
  maproom search --help
  ```
  Confirm these 5 flags exist in the `search` subcommand: `--format`, `--kind`, `--lang`, `--preview`, `--preview-length`
- [ ] Run `maproom vector-search --help` and verify all expected flags are present:
  ```bash
  maproom vector-search --help
  ```
  Confirm all 6 flags exist in the `vector-search` subcommand: `--format`, `--kind`, `--lang`, `--preview`, `--preview-length`, `--threshold`
- [ ] Compare output against the baseline verification deliverable and check for any discrepancies (new flags, removed flags, renamed flags, changed defaults, changed accepted values):
  - **Baseline deliverable:** `planning/deliverables/cli-flag-verification.md` (located at the ticket level in your specs directory)
  - **Full path:** `/path/to/specs/tickets/<ticket-name>/planning/deliverables/cli-flag-verification.md`
- [ ] Record the verification result:
  - **No discrepancies:** Mark this month's verification as complete. No further action needed.
  - **Discrepancies found:** Create a ticket to update all affected documentation (SKILL.md, multi-repo-guide.md, README.md, and the baseline deliverable itself).

**Task Reference:** The verification procedure follows the steps originally defined in the verify-cli-flags task. Consult your specs directory for the full task file path.

**Success Criteria:** CLI drift is detected within 30 days of occurrence, before a significant number of agent sessions encounter deprecated flags.

**Escalation Path:** If discrepancies are found between the current CLI output and the baseline deliverable, create a new ticket under the maproom plugin to update all documentation files that reference the affected flags. The ticket should enumerate every file and line that needs updating.
