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

Cross-repo search also needs every repo indexed into **one shared database** — in practice
one shared Postgres, because repos indexed into separate SQLite files can only be searched
one at a time. Export the same `MAPROOM_DATABASE_URL` for every repo before you scan (see
[Which backend?](#which-backend)).

1. Copy the configuration template to your workspace root:
   ```bash
   cp plugins/maproom/skills/maproom-search/templates/maproom-repos.yaml ./maproom-repos.yaml
   ```
2. Customize repo entries for your workspace (paths, descriptions, search guidance)
3. Set environment variables for path portability (`MAPROOM_REPOS_ROOT`, `MAPROOM_SPECS_ROOT`)
4. Index each repo with `maproom scan`, with that same shared `MAPROOM_DATABASE_URL` set

See [multi-repo-guide.md](skills/maproom-search/references/multi-repo-guide.md) for detailed setup instructions, search strategies by repo type, and cross-repo search patterns.

## Prerequisites

Before using the Maproom plugin, ensure you have:

1. **maproom CLI installed**: The plugin requires the `maproom` command-line tool to be available in your system PATH
2. **Minimum maproom version**: 0.1.0. Verify your version:
   ```bash
   maproom --version
   ```
   Builds differ in which features and embedding providers they include, so treat
   `maproom --help` — which lists the subcommands and environment variables your build
   supports — as the source of truth rather than any doc, this one included.
3. **A database, on one of two backends**: maproom chooses its backend at runtime from
   `MAPROOM_DATABASE_URL` (a `--database-url` flag overrides the env var):
   - `sqlite://…` — or a plain filesystem path — selects **SQLite**. This is the default,
     at `~/.maproom/maproom.db`.
   - `postgres://…` / `postgresql://…` selects **PostgreSQL**. This requires a binary built
     with `--features postgres`.
4. **Indexed content**: your codebase must be scanned with `maproom scan` before searching

### Which backend?

One repo on one machine: SQLite is fine — set nothing.

A multi-repo fleet: point **every** repo at **one shared Postgres**. That single shared
database is what makes cross-repo search work; repos indexed into separate SQLite files
can only ever be searched one at a time. A typical devcontainer URL:

```bash
export MAPROOM_DATABASE_URL=postgres://maproom:maproom@host.docker.internal:5433/maproom
```

### Devcontainer trap: `host.docker.internal`, never `localhost`

The shared Postgres container runs on the **host** docker daemon, so from inside a
devcontainer it must be reached at `host.docker.internal`. Inside the container,
`localhost:5433` is frequently a *different*, throwaway Postgres — for example a
tmpfs-backed instance used by `cargo test` — whose data vanishes when the container stops.

Pointing maproom at `localhost` raises no error. Scans succeed, `maproom status` looks
healthy, and the data is simply missing later. If indexed content keeps disappearing,
check the host in your URL first:

```bash
echo $MAPROOM_DATABASE_URL
pg_isready -h host.docker.internal -p 5433
```

To verify your setup:
```bash
# Check CLI is installed
maproom --version

# Index your repository
maproom scan

# Verify indexing succeeded (also lists the indexed repo names)
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
- Confirm which database you are actually talking to: `echo $MAPROOM_DATABASE_URL`. On
  SQLite, `ls -la ~/.maproom/maproom.db`; on Postgres,
  `pg_isready -h host.docker.internal -p 5433` (see the devcontainer trap above)

### No Results Found
**Problem**: Searches return no results or irrelevant matches

**Solution**:
- Try different search terms or phrasing
- Use more specific queries (2-3 core technical terms work best)
- Check if the repository is actually indexed: `maproom status`
- Verify file types are indexed (use `--file-type` filter if needed)
- Try different search modes: hybrid (default), fts, or vector
- `--repo` matches the **indexed repo name** (derived from the git origin, suffix
  fuzzy-matched), not the directory name on disk. A directory called `django-olympics`
  indexed as `django/django` is found by `--repo django`; `--repo django-olympics`
  returns zero hits with no error. List the indexed names with `maproom status`
- For very recent code changes, re-index: `maproom scan --force`

### Stale Results
**Problem**: Search results don't reflect recent code changes

**Solution**:
- Re-index the repository: `maproom scan`
- The daemon auto-refreshes but may need manual reindexing for major changes
- Scanning and watching refresh **chunks only**. Embeddings are a separate, scheduled
  job — see [Index Maintenance](#index-maintenance)

### Performance Issues
**Problem**: Searches are slow or timing out

**Solution**:
- Reduce the number of results requested (use `k` parameter)
- Use FTS mode for exact keyword matches (faster than semantic search)
- Check database size: large databases may need optimization
- On the SQLite backend, ensure the database isn't locked by another process
- On the Postgres backend, `pool timed out while waiting for an open connection` from
  maproom (with `Connection refused` from `psql`) almost always means the Postgres
  container is not running, or you are pointed at the wrong host — it is *not* a file
  permissions problem. Check `pg_isready -h host.docker.internal -p 5433`, then start
  the host container. The same error appears transiently when something else is
  saturating the database, so check `pg_stat_activity` for long-running statements
  before concluding the container is down. See
  [maproom-guide](skills/maproom-guide/SKILL.md) for the full diagnosis path

## Skills & Agents

The maproom plugin includes specialized skills and agents for different tasks:

| Component | Type | Purpose |
|---|---|---|
| [maproom-search](skills/maproom-search/SKILL.md) | Skill | Command syntax, setup, filtering, multi-repo workflows |
| [maproom-guide](skills/maproom-guide/SKILL.md) | Skill | Interpret search results, diagnose errors, learn concepts |
| [sdd-spec-search](skills/sdd-spec-search/SKILL.md) | Skill | SDD specification search patterns |
| [maproom-guide-maintenance](skills/maproom-guide-maintenance/SKILL.md) | Skill | Procedures for maintaining the guide |
| [maproom-researcher](agents/maproom-researcher.md) | Agent (Haiku) | 4-phase research workflow for code exploration |
| [maproom-cleric](agents/maproom-cleric.md) | Agent (Haiku) | Documentation accuracy auditing |

**New to maproom?** Start with [maproom-guide](skills/maproom-guide/SKILL.md) to understand search output, then use [maproom-search](skills/maproom-search/SKILL.md) for command reference.

## Index Maintenance

Keeping the index healthy takes **two** jobs, and only one of them is scanning. Scanning
maintains chunks. It does not maintain embeddings.

### 1. Chunks: periodic scanning

**Recommended scan frequency:**
- **Active repositories** (daily commits): Run `maproom scan` daily or before research sessions
- **Stable repositories** (weekly/monthly updates): Run `maproom scan` weekly
- **One-time analysis**: Run `maproom scan` once before invoking maproom-researcher agent

**Scan command:**
```bash
maproom scan [--repo-path /path/to/repo]
```

### 2. Embeddings: a periodic `generate-embeddings` job (required)

Neither `maproom scan` nor a file watcher regenerates embeddings. The incremental
processor **deletes** the embeddings for chunks that changed and never recreates them, so
embedding coverage decays continuously as you work. Documentation anywhere claiming that
"watch keeps the index fresh" is true for chunks and **false** for embeddings.

The decay is silent, because losing embeddings does not break search: with zero
embeddings `maproom search` still returns results by falling back to full-text and
structural ranking. Only vector search and semantic ranking quietly go away. Never infer
coverage from "search still works" — check it:

```bash
maproom status   # per repo, e.g. "Embeddings: 0 (0.0%)"
```

Hold coverage by scheduling `maproom generate-embeddings` on cron or your process
manager. Two things to know before you write that job:

- **Bound each pass and loop until pending reaches zero.** An unbounded pass dies at
  scale — and gets worse the more chunks you have already embedded — with
  `Failed to fetch chunks ... canceling statement due to statement timeout`. The failure
  therefore shows up *late*, just as the job is closest to finishing.
- **Batch size is a blast-radius decision.** A single failed provider sub-batch fails the
  whole pipeline batch; these failures are transient and self-heal on the next pass, so a
  bounded loop converges.

Run `maproom generate-embeddings --help` for the current flags on your binary. For
provider configuration (Ollama, Google/Vertex, OpenAI, and — where your build includes it
— Bedrock), batch and concurrency tuning, and the model/dimension constraints on
switching embedding models, see
[maproom-guide](skills/maproom-guide/SKILL.md).

### Index freshness check

```bash
maproom status
```

**"Last scan" is not a freshness signal.** `maproom status` prints a per-worktree
"Last scan" timestamp that is *not* updated when an incremental scan finds the git tree
SHA unchanged — it logs `No changes detected (tree SHA match), skipping scan` and leaves
the old timestamp alone. A months-old "Last scan" therefore usually means "nothing has
changed since then", not "the index is stale"; judging staleness by this field leads to
pointless full re-scans. To really test freshness, search for a symbol you know was added
recently, or compare the repo's current HEAD against what the index recorded.

**Note:** The maproom-researcher agent does NOT automatically trigger index scans. Users must ensure the index is current before invoking the agent for accurate semantic search results.

## Maintenance

### Monthly CLI Verification

**Purpose:** Detect maproom CLI flag deprecation or behavior changes before agents encounter failures. The CLI is pre-1.0, where breaking changes are allowed per semver. 52 command examples across plugin documentation depend on 6 CLI flags; if any flag is renamed or removed, agents will learn deprecated syntax and encounter command failures.

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
- [ ] Run `maproom --version` and record it; if it has moved since the last verification, treat every flag check below as required:
  ```bash
  maproom --version
  ```
- [ ] Run `maproom search --help` and check the flags it prints against the baseline
  deliverable named below — the baseline is where the expected flag list lives, so it is
  not duplicated here:
  ```bash
  maproom search --help
  ```
- [ ] Run `maproom vector-search --help` and check it against the same baseline:
  ```bash
  maproom vector-search --help
  ```
- [ ] Compare output against the baseline verification deliverable and check for any discrepancies (new flags, removed flags, renamed flags, changed defaults, changed accepted values):
  - **Baseline deliverable:** `planning/deliverables/cli-flag-verification.md` (located at the ticket level in your specs directory)
  - **Full path:** `/path/to/specs/tickets/<ticket-name>/planning/deliverables/cli-flag-verification.md`
- [ ] Record the verification result:
  - **No discrepancies:** Mark this month's verification as complete. No further action needed.
  - **Discrepancies found:** Create a ticket to update all affected documentation (SKILL.md, multi-repo-guide.md, README.md, and the baseline deliverable itself).

**Task Reference:** The verification procedure follows the steps originally defined in the verify-cli-flags task. Consult your specs directory for the full task file path.

**Success Criteria:** CLI drift is detected within 30 days of occurrence, before a significant number of agent sessions encounter deprecated flags.

**Escalation Path:** If discrepancies are found between the current CLI output and the baseline deliverable, create a new ticket under the maproom plugin to update all documentation files that reference the affected flags. The ticket should enumerate every file and line that needs updating.
