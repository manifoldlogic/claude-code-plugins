# Multi-Repo Search Guide

## Repo Types and Their Content

Maproom indexes two distinct types of repositories: **code** repos containing source files and **docs** repos containing specifications, design documents, and project history. Each type produces different chunk kinds and responds best to different search strategies.

### Chunk Kinds by Repo Type

The following chunk kinds were verified by running `maproom search` against indexed repositories (crewchief for code, manifoldlogic/claude-code-plugins for mixed content).

| Chunk Kind | Found In | Description |
|---|---|---|
| `func` | code repos | Functions, standalone methods, closures |
| `class` | code repos | Class definitions (Python, TypeScript, etc.) |
| `struct` | code repos | Struct definitions (Rust, Go) |
| `enum` | code repos | Enum definitions |
| `method` | code repos | Class/struct methods (bound to a type) |
| `constant` | code repos | Module-level constant assignments |
| `imports` | code repos | Import blocks (`__imports__` per file) |
| `heading_1` | docs repos | Top-level headings (`#`) |
| `heading_2` | docs repos | Section headings (`##`) |
| `heading_3` | docs repos | Subsection headings (`###`) |
| `heading_4` | docs repos | Nested subsection headings (`####`) |
| `markdown_section` | docs repos | Lists, tables, and general prose sections |
| `code_block` | docs repos | Fenced code blocks (annotated with language) |
| `link` | docs repos | Hyperlinks within documents |
| `json_key` | both | Keys in JSON configuration files (e.g., plugin.json) |

### What Each Repo Type Contains

| Aspect | Code Repo (`type: code`) | Docs Repo (`type: docs`) |
|---|---|---|
| Primary content | Source code, tests, configs | Specs, plans, decisions, tickets |
| Answers the question | "How is it built?" | "Why was it built this way?" |
| Key identifiers | Function names, class names, variables | Ticket IDs, section headings, terms |
| Relationships | Call graphs, imports, type hierarchies | Document cross-references, links |
| Chunk density | Many small chunks (one per function) | Fewer, larger chunks (per section) |

## Code Repo Search Strategies

Code repos contain implementation details. Use these strategies depending on what you know about your target.

### Full-Text Search (FTS) -- When You Have Identifiers

Use FTS when you know specific names, strings, or identifiers. FTS excels at exact and partial matches against symbol names.

**Function/method names:**

```bash
maproom search --repo crewchief --query "extract_function_identifier" --kind func --format agent
```

**Class or struct names:**

```bash
maproom search --repo crewchief --query "ShadowMode" --kind class --format agent
```

**Error messages or string literals:**

```bash
maproom search --repo crewchief --query "Failed to create embedding" --format agent
```

**Configuration keys:**

```bash
maproom search --repo crewchief --query "MAPROOM_DATABASE_URL" --format agent
```

**Import paths:**

```bash
maproom search --repo crewchief --query "extract_standard_import" --format agent
```

### Vector Search -- When You Have Concepts

Use vector search when you have a concept or question but do not know the exact names. Vector search finds semantically similar code.

```bash
maproom vector-search --repo crewchief --query "authentication logic" --format agent
maproom vector-search --repo crewchief --query "error handling patterns" --format agent
maproom vector-search --repo crewchief --query "embedding generation pipeline" --format agent
```

Keep queries to 2-3 core technical terms (see search-best-practices.md for query transformation guidance).

### Context Command -- When You Need Relationships

Use the context command after finding a relevant chunk to understand how it connects to the rest of the codebase. Context reveals callers, callees, tests, and related configuration.

```bash
# Find a function first
maproom search --repo crewchief --query "extract_from_import" --kind func --format agent

# Then get its context (use chunk_id from search results)
maproom context --chunk-id 10833 --callers --callees
maproom context --chunk-id 10833 --callers --callees --tests --budget 8000
```

Context is particularly valuable for:
- Tracing call graphs to understand execution flow
- Finding test files that exercise a function
- Discovering configuration that affects behavior
- Understanding dependency chains between modules

## Documentation/Specs Repo Search Strategies

Docs repos contain design rationale, planning documents, architecture decisions, and project history. The chunk kinds are heading-based and section-based, which changes how you should search.

### Vector Search -- When You Need Intent or Rationale

Vector search is the default for docs repos because most queries seek conceptual understanding rather than exact terms.

```bash
maproom vector-search --repo crewchief-specs --query "plugin system design rationale" --format agent
maproom vector-search --repo crewchief-specs --query "why maproom uses SQLite" --format agent
maproom vector-search --repo crewchief-specs --query "architecture decisions embedding provider" --format agent
```

### Full-Text Search -- When You Have Specific Terms

Use FTS for ticket IDs, exact section names, specific terms, or document references.

**Ticket IDs:**

```bash
maproom search --repo crewchief-specs --query "MPRSKL" --format agent
maproom search --repo crewchief-specs --query "MAPMULTI" --format agent
```

**Section headings:**

```bash
maproom search --repo crewchief-specs --query "Risk Assessment" --format agent
maproom search --repo crewchief-specs --query "Acceptance Criteria" --format agent
```

**Specific technical terms:**

```bash
maproom search --repo crewchief-specs --query "incremental scanning" --format agent
```

### Exploration -- When You Need to Browse Structure

Use FTS with broad heading terms to discover document structure, then drill into specific sections.

```bash
# Find architecture documents
maproom search --repo crewchief-specs --query "architecture" --format agent

# Find planning documents
maproom search --repo crewchief-specs --query "planning analysis" --format agent

# Find decision records
maproom search --repo crewchief-specs --query "decision rationale" --format agent
```

Results from docs repos include `heading_1`, `heading_2`, `heading_3`, and `heading_4` chunks that reveal the document hierarchy. Use the `file_relpath` and line numbers to navigate to specific sections.

## Cross-Repo Patterns

These patterns combine searches across code and docs repos to answer questions that neither repo can answer alone. Each pattern starts in one repo type and follows up in the other.

### Pattern 1: Intent-Implementation Bridge

**Goal:** Understand *why* something was built the way it is, then find *how* it is implemented.

**When to use:** You encounter unfamiliar code and need to understand the design decisions behind it.

**Steps:**

1. Search the docs/specs repo for design intent:
   ```bash
   maproom vector-search --repo crewchief-specs --query "plugin system design" --format agent
   ```

2. Extract key terms from the design document (function names, patterns, architecture components).

3. Search the code repo for the implementation using those terms:
   ```bash
   maproom search --repo crewchief --query "PluginManager" --format agent
   maproom context --chunk-id <id> --callers --callees
   ```

**Query optimization:** Start with vector search in specs (broad concepts), then switch to FTS in code (specific identifiers found in the specs).

### Pattern 2: Requirements Tracing

**Goal:** Find where a specific requirement is implemented in code.

**When to use:** You need to verify that a requirement has been implemented, or you need to modify code that implements a specific requirement.

**Steps:**

1. Find the requirement in specs:
   ```bash
   maproom search --repo crewchief-specs --query "MPRSKL" --format agent
   ```

2. Read the requirement to identify what it specifies (e.g., "scan must support incremental mode").

3. Search the code repo for the implementation:
   ```bash
   maproom search --repo crewchief --query "incremental scan" --format agent
   maproom search --repo crewchief --query "tree SHA comparison" --format agent
   ```

4. Use context to verify completeness:
   ```bash
   maproom context --chunk-id <id> --tests
   ```

**Query optimization:** Use FTS in specs with the ticket ID (exact match), then use a mix of FTS (for identifiers mentioned in the requirement) and vector search (for concepts) in the code repo.

### Pattern 3: Historical Context

**Goal:** Understand the evolution of a piece of code by finding the decision history that led to its current state.

**When to use:** You are considering changing code and need to know if there are constraints or past decisions that would affect the change.

**Steps:**

1. Identify the code area:
   ```bash
   maproom search --repo crewchief --query "ShadowMode" --format agent
   ```

2. Search specs for related decisions and history:
   ```bash
   maproom vector-search --repo crewchief-specs --query "shadow mode AB testing decision" --format agent
   maproom search --repo crewchief-specs --query "shadow mode" --format agent
   ```

3. Look for risk assessments and constraints:
   ```bash
   maproom vector-search --repo crewchief-specs --query "AB testing risks constraints" --format agent
   ```

**Query optimization:** Start with FTS in code to get exact names, then search specs using both the exact names (FTS) and the conceptual area (vector search). Specs often use different terminology than code, so vector search catches conceptual matches that FTS would miss.

### Cross-Repo Query Optimization Summary

| Starting Point | Specs Search Mode | Code Search Mode | Why |
|---|---|---|---|
| Concept/question | vector-search | FTS (with names from specs) | Specs use natural language; code uses identifiers |
| Ticket ID | FTS | FTS + vector-search | Ticket IDs are exact; implementations may vary |
| Code change | FTS (with code names) | (already in code) | Find decisions about specific components |
| Architecture question | vector-search | context (with chunk IDs) | Understand intent, then trace implementation |

**General rule:** Search specs for *why*, then search code for *how*. Use the terms you find in one repo to refine your search in the other.

## Troubleshooting Searches

### Zero Results -- Check the Repo Name First

Before relaxing any filter, confirm that `--repo` names something that is actually indexed. `--repo` matches the **indexed repo name**, which is derived from the git origin -- not the directory name on disk -- and it matches on suffix. A directory called `django-olympics` whose origin indexes it as `django/django` is found by `--repo django`. `--repo django-olympics` returns **zero hits with no error**: maproom does not report that the repo filter matched nothing.

```bash
# Authoritative list of indexed repo names
maproom status

# Suffix match works; the on-disk directory name usually does not
maproom search --repo django --query "QuerySet" --format agent
```

Rule of thumb: if *every* query against one repo comes back empty, suspect a name mismatch. If only *some* queries come back empty, the name is fine -- move on to filter relaxation below.

### Zero Results -- Progressive Filter Relaxation

When a filtered search returns zero results, progressively relax filters to find relevant chunks. Remove one filter at a time to identify which constraint is too narrow.

**Scenario:** Searching for authentication functions in Python

```bash
# Initial attempt -- too narrow (both --kind and --lang filters)
maproom search --repo crewchief --query "authentication" --kind func --lang py --format agent
# Returns 0 results
```

**Step 1: Remove language filter** (keep `--kind`, search all languages for functions):

```bash
maproom search --repo crewchief --query "authentication" --kind func --format agent
# May find authentication functions in TypeScript, Rust, or other languages
```

**Step 2: Remove kind filter** (keep `--lang`, search all Python chunks):

```bash
maproom search --repo crewchief --query "authentication" --lang py --format agent
# May find authentication in class definitions, imports, or method bodies
```

**Step 3: Remove all filters** (broaden search completely):

```bash
maproom search --repo crewchief --query "authentication" --format agent
# Returns all chunks mentioning authentication across all files and languages
```

**Why this order:** Removing `--lang` first is usually more productive because the concept you are searching for may be implemented in a different language than expected. Removing `--kind` second catches cases where the logic lives in a class, method, or configuration rather than a standalone function. Removing all filters last gives the broadest view when earlier steps still return nothing.

## Configuration Setup Guide

This section explains how to configure maproom for multi-repo search in a new workspace.

### Step 1: Set Environment Variables

Add these to your shell profile or devcontainer configuration:

```bash
# For devcontainer environments
export MAPROOM_REPOS_ROOT=/workspace/repos
export MAPROOM_SPECS_ROOT=/workspace/_SPECS

# For local/laptop environments
export MAPROOM_REPOS_ROOT=~/git
export MAPROOM_SPECS_ROOT=~/_SPECS
```

**Choose the storage backend before you scan anything.** maproom reads `MAPROOM_DATABASE_URL` at startup and picks its backend from the scheme: `sqlite://` (or a bare filesystem path) selects SQLite, the default at `~/.maproom/maproom.db`; `postgres://` or `postgresql://` selects PostgreSQL, which requires a binary built with `--features postgres`. A `--database-url` flag overrides the environment variable for a single invocation. Provider and feature availability differ between builds -- run `maproom --help` to confirm which subcommands and environment variables your binary actually supports before committing to a backend.

**A multi-repo fleet wants ONE shared Postgres.** Cross-repo search only works across repos that live in the same database, so every repo in the fleet points at a single Postgres instance. Per-repo SQLite files cannot be searched together.

```bash
# Every repo in the fleet shares this one database
export MAPROOM_DATABASE_URL=postgres://maproom:maproom@host.docker.internal:5433/maproom
```

**Devcontainer trap: `host.docker.internal`, never `localhost`.** The Postgres container runs on the *host* docker daemon, so from inside a devcontainer it is reachable only at `host.docker.internal`. Inside the container, `localhost:5433` is frequently a *different* Postgres -- for example a tmpfs-backed instance used for cargo tests -- whose data vanishes when the container stops. Pointing maproom at `localhost` raises no error: scans succeed, `maproom status` looks healthy, and the index is simply gone later. Verify the endpoint before the first scan:

```bash
pg_isready -h host.docker.internal -p 5433
psql postgres://maproom:maproom@host.docker.internal:5433/maproom -c 'select count(*) from chunks;'
```

### Step 2: Create the Configuration File

Copy the YAML template to your workspace root:

```bash
cp plugins/maproom/skills/maproom-search/templates/maproom-repos.yaml /workspace/maproom-repos.yaml
```

Edit the file to list your repositories. See the template for detailed field documentation. Each repo entry needs at minimum: `type`, `path`, and `description`.

### Step 3: Scan Each Repository

**IMPORTANT:** Scan each project directory separately. Do NOT scan a parent directory like `_SPECS/` -- this would merge all specs into a single repo index and make targeted searches impossible.

**Correct approach -- scan each project directory individually:**

```bash
# Scan the crewchief source code repo
maproom scan --path /workspace/repos/crewchief/crewchief --repo crewchief

# Scan the crewchief specs repo (separate index)
maproom scan --path /workspace/_SPECS/crewchief --repo crewchief-specs

# Scan the plugins repo
maproom scan --path /workspace/repos/claude-code-plugins --repo manifoldlogic/claude-code-plugins
```

**Incorrect approach -- do NOT do this:**

```bash
# WRONG: scanning the parent _SPECS directory merges all specs together
maproom scan --path /workspace/_SPECS --repo all-specs
```

Keep each `--repo` label aligned with the key used in your `maproom-repos.yaml` configuration file -- but the name that lands *in the index* is derived from the git origin, so it may not be the label you typed.

**The name in the index is the name you search under.** At search time `--repo` matches the *indexed* repo name -- derived from the git origin, not from the directory name on disk -- with suffix fuzzy-matching. Whatever `maproom status` prints is authoritative; see "Zero Results -- Check the Repo Name First" above.

**Do not wrap a scan in a timeout you have not measured.** A large repo on a slow mount (FUSE, virtiofs, a network share) can exceed a wrapping timeout mid-scan. That repo is left partially indexed while every other repo in the batch reports success, so the aggregate run looks clean. See "A clean-looking scan run can still leave one repo stale" below.

### Step 4: Verify Indexing

Confirm all repos are indexed, then check embedding coverage explicitly -- it is a separate question from whether chunks exist:

```bash
maproom status
```

Real output carries more than chunk counts. Each worktree reports coverage and a last-scan timestamp:

```
Repository: crewchief
  Worktree: main
    Chunks: 24,333
    Embeddings: 24,333 (100.0%)
    Last scan: 2026-04-11 09:22:41 UTC

Repository: crewchief-specs
  Worktree: main
    Chunks: 1,200
    Embeddings: 0 (0.0%)
    Last scan: 2026-08-30 17:04:08 UTC
```

**"Last scan" is not a freshness signal.** An incremental scan that finds the git tree SHA unchanged short-circuits: it logs

```
No changes detected (tree SHA match), skipping scan
```

and leaves the previous timestamp untouched. A months-old "Last scan" therefore usually means *nothing has changed since then*, not *the index is stale*. Treating that field as staleness leads to pointless full re-scans of repos that were already current.

To actually check freshness, ask the index about something you know is recent, or compare HEAD against what the index recorded:

```bash
# Does the index know about a symbol you added this week?
maproom search --repo crewchief --query "name_of_a_recently_added_symbol" --format agent

# Or compare the working tree against what the index recorded for that worktree
git -C /workspace/repos/crewchief/crewchief rev-parse HEAD
psql "$MAPROOM_DATABASE_URL" -c 'select * from worktrees;'
```

**Zero embeddings never errors.** With no embeddings at all, `maproom search` still returns results by falling back to full-text and structural ranking; only `maproom vector-search` and semantic ranking are unavailable. So "search works" proves nothing about coverage. Check it directly: `maproom status` shows `Embeddings: 0 (0.0%)` per repo, and on Postgres the `encoding_runs` table stays empty when nothing has ever been embedded.

Per-repo coverage, straight from the database:

```sql
select r.name, count(distinct c.blob_sha) blobs, count(distinct e.blob_sha) embedded
from repos r join worktrees w on w.repo_id=r.id
join chunk_worktrees cw on cw.worktree_id=w.id
join chunks c on c.id=cw.chunk_id
left join code_embeddings e on e.blob_sha=c.blob_sha group by 1 order by 2 desc;
```

If coverage is short, generate embeddings -- but treat this as the *first* run of a recurring job, not a one-time fix. Bound every pass and loop; see "Keeping the Index Fresh" below for why an unbounded run dies exactly when it is closest to finishing, and for the scheduled job that keeps coverage from decaying.

```bash
# Bound every pass. Run `maproom generate-embeddings --help` for the flag your build
# uses to cap chunks per pass (and for provider selection); ~10,000 is a measured-safe
# value against the 5s statement_timeout. An unbounded run dies late -- see below.
maproom generate-embeddings --repo crewchief
maproom generate-embeddings --repo crewchief-specs
```

### Step 5: Test Searches

Run a test search against each repo to confirm they work:

```bash
# Test code repo FTS
maproom search --repo crewchief --query "scan" --k 3 --format agent

# Test docs repo FTS
maproom search --repo crewchief-specs --query "architecture" --k 3 --format agent

# Test vector search (requires embeddings)
maproom vector-search --repo crewchief --query "error handling" --k 3 --format agent
```

### No Config File Fallback

If `maproom-repos.yaml` is not present in the workspace, use `maproom status` to discover which repos are already indexed. The status output lists all repositories, worktrees, and chunk counts, providing enough information to construct search commands manually.

## Keeping the Index Fresh

### Watchers keep chunks fresh -- they do NOT keep embeddings fresh

This is the fleet's quietest failure. The incremental processor **deletes** the embeddings belonging to changed chunks and never regenerates them. Nothing in the watch path calls the embedding provider. So as people work, embedding coverage decays continuously and silently -- silently because `maproom search` keeps returning results the whole time (it falls back to full-text and structural ranking), while `maproom vector-search` quietly loses reach over exactly the code that is being worked on most.

Any documentation claiming "watch keeps the index fresh" is true for chunks and **false for embeddings**.

A periodic `maproom generate-embeddings` job is therefore **required**, not optional. Schedule it however the fleet is already managed. With cron:

```cron
# Watchers handle chunks. Nothing handles embeddings unless you schedule it.
17 * * * * /usr/local/bin/maproom-embed-topup >> /home/vscode/.maproom/embed-topup.log 2>&1
```

Or, alongside the per-repo pm2 watchers, as a scheduled one-shot:

```js
// pm2 ecosystem entry, next to the maproom:<repo>:<worktree> watchers
{ name: "maproom:embed-topup", script: "/usr/local/bin/maproom-embed-topup",
  autorestart: false, cron_restart: "17 * * * *" }
```

### Bound every embedding pass, then loop until pending hits zero

An unbounded `generate-embeddings` run dies at scale, and it gets *worse the more it succeeds*. Its pending-chunk query is a `NOT IN` subquery whose cost grows with the size of `code_embeddings`, and maproom pins `statement_timeout` to 5000ms on every connection it opens (set in `after_connect`; there is no environment override). Measured on a ~195k-chunk database: with ~113k blobs already embedded, asking for 40,000 pending chunks blew past 5s and every pass died with

```
Failed to fetch chunks ... canceling statement due to statement timeout
```

Bounding the same pass to 10,000 chunks measured ~0.73s. The failure appears **late** -- the job stalls exactly when it is closest to finishing, which is why it reads as "embeddings are broken" rather than "that pass was too big".

So: cap every pass, and loop until nothing is pending. Looping also absorbs transient provider failures -- one bad sub-batch marks the whole pipeline batch failed, but those chunks are simply picked up again on the next pass.

```sh
#!/bin/sh
# maproom-embed-topup -- hold embedding coverage across the fleet.
set -u
DB="postgres://maproom:maproom@host.docker.internal:5433/maproom"

# Cap on chunks per pass. Run `maproom generate-embeddings --help` to see what
# your build calls this flag; the number matters more than the spelling, and
# ~10,000 is a measured-safe working value against the 5s statement_timeout.
BOUND="--<per-pass-chunk-cap> 10000"

pending() {
  psql "$DB" -tAc "select count(distinct c.blob_sha) from chunks c
                   left join code_embeddings e on e.blob_sha = c.blob_sha
                   where e.blob_sha is null;"
}

# pending() is fleet-wide, so sweep the whole fleet once per pass and re-check.
pass=0
while [ "$(pending)" -gt 0 ] && [ "$pass" -lt 50 ]; do
  for repo in crewchief crewchief-specs manifoldlogic/claude-code-plugins; do
    maproom generate-embeddings --repo "$repo" $BOUND || true
  done
  pass=$((pass + 1))
done
```

One caveat if you go query-hunting yourself: maproom sets `work_mem` (256MB) on its own connections, and that same `NOT IN` query plans at cost ~101,635 (hashed SubPlan) at 64MB+ versus ~218,119,741 (Materialize plus a per-row Seq Scan) under a small `work_mem`. Running it by hand in `psql` with default settings reproduces a problem maproom does not have.

### The pm2 watcher fleet vanished

**Symptom:** `pm2 list` prints an empty table. The pm2 God daemon is still alive, nothing errored, and no repo is being scanned any more -- so the index silently stops tracking new commits across the whole fleet.

**Fix:** do not hand-rebuild N watchers.

```bash
pm2 resurrect     # restores every watcher from ~/.pm2/dump.pm2
pm2 list          # expect one maproom:<repo>:<worktree> watcher per repo
```

Keep `~/.pm2/dump.pm2` current (`pm2 save`) after intentionally adding or removing watchers, since that dump is what `resurrect` replays. Note that resurrecting watchers restores *chunk* freshness only -- embeddings still depend on the scheduled top-up job above.

### A clean-looking scan run can still leave one repo stale

**Symptom:** a batch scan reports success for every repo, but one repo's results are missing code you know landed. Nothing in the run output points at it.

**Cause:** a wrapping timeout killed that repo's scan partway through. The repo is left partially refreshed; the other repos succeeded, so the aggregate run looks clean. Slow mounts (FUSE, virtiofs, network shares) make this routine on large repos. Measured example: a 1,328-file docs repo died at 30% under an 1800s cap and needed ~2,326s to finish unbounded.

**Fix:** re-scan the suspect repo on its own with no cap (or a cap you have measured against that repo on that mount), then confirm with a recent-symbol search -- not with "Last scan", which the tree-SHA short-circuit leaves stale on purpose.

```bash
maproom scan --path /workspace/_SPECS/crewchief --repo crewchief-specs
maproom search --repo crewchief-specs --query "a_heading_added_recently" --format agent
```
