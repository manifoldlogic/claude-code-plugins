---
name: maproom-search
description: Semantic code search for exploring unfamiliar codebases and finding implementations by concept.
---

# Maproom Search

## When to Use
| Tool | Use Case |
|------|----------|
| maproom | Find code by concept |
| Grep | Exact text/regex |
| Glob | File paths |

## The `--help` Contract

**The binary is the source of truth for flags. This skill is the source of truth for decisions.**

maproom builds differ. Subcommands, flag names, defaults, storage backends, and
supported embedding providers all vary between versions and between builds compiled
with different feature sets. This skill and its reference files deliberately do **not**
mirror flag lists, because a copied flag list rots silently — it keeps looking correct
long after the binary changed. They explain concepts, the decisions you face, and the
failure modes.

So before you rely on any flag or environment variable named anywhere in this skill,
confirm it against the binary you actually have:

```bash
maproom --help                        # subcommands + environment variables this build supports
maproom --version
maproom search --help                 # flags for one subcommand
maproom vector-search --help
maproom scan --help
maproom generate-embeddings --help
maproom context --help
```

Reach for `--help` by reflex when:

- a flag is rejected as unknown, or a flag you remember does not appear
- a default matters to your decision (batch size, preview length, traversal depth)
- you need the exact environment variable name for a setting
- you are checking whether a **feature exists in your build at all** — a Postgres
  backend needs a build compiled with `--features postgres`, and provider support
  (notably `MAPROOM_EMBEDDING_PROVIDER=bedrock`) is not present in every build

Never assume "maproom supports X" from documentation alone, including this document.
Verify, then proceed.

## Where to Look Next

This file is the entry point. It covers setup, choosing a search type, and the
first-line fixes. Everything deeper lives in one of these:

| If you need to... | Read |
|---|---|
| Run a **multi-repo fleet**, set up **shared Postgres**, search across repos, understand indexed repo names | [multi-repo-guide.md](./references/multi-repo-guide.md) |
| Choose and configure an **embedding provider** (Ollama, Google/Vertex, OpenAI, Cohere, AWS Bedrock), pick a model, understand dimension constraints, switch models safely | [embedding-providers.md](./references/embedding-providers.md) |
| Fix **expired Google ADC** (`Reauthentication failed`) or set up service-account credentials | [adc-setup.md](./references/adc-setup.md) |
| **Diagnose a failure** — dead index, connection pool timeouts, empty results, embedding passes dying, lost watchers | [troubleshooting.md](./references/troubleshooting.md) |
| Write better **queries**, avoid query anti-patterns | [search-best-practices.md](./references/search-best-practices.md) |

Routing by symptom:

| Symptom | Go to |
|---|---|
| `pool timed out while waiting for an open connection` | [troubleshooting.md](./references/troubleshooting.md) — Postgres container/host, not file permissions |
| `canceling statement due to statement timeout` during embedding generation | [Generate embeddings](#4-generate-embeddings-separate-recurring-and-bounded) below, then [troubleshooting.md](./references/troubleshooting.md) |
| `Reauthentication failed. cannot prompt during non-interactive execution` | [adc-setup.md](./references/adc-setup.md) |
| `Sub-batch N failed: API error: ...` | [embedding-providers.md](./references/embedding-providers.md) |
| Search returns zero hits for a repo you know is indexed | [Multi-Repo Search](#multi-repo-search) below — usually a repo-name mismatch |
| `Embeddings: 0 (0.0%)` in `maproom status`, but search still works | [Embeddings fail silently](#embeddings-fail-silently) below |

## First-Time Setup

### 1. Choose a storage backend

maproom has **two** backends and picks one at runtime from `MAPROOM_DATABASE_URL`:

| `MAPROOM_DATABASE_URL` | Backend |
|---|---|
| unset, a plain filesystem path, or `sqlite://...` | SQLite (default, `~/.maproom/maproom.db`) |
| `postgres://...` or `postgresql://...` | PostgreSQL — **requires a build compiled with `--features postgres`** |

A `--database-url` flag overrides the environment variable. Run `maproom --help` to
confirm both are present on your build.

**Single repo on a laptop:** SQLite. Nothing to configure.

**A fleet of repos where you want cross-repo search:** one shared Postgres serving all
repos. In a devcontainer that typically looks like:

```bash
export MAPROOM_DATABASE_URL=postgres://maproom:maproom@host.docker.internal:5433/maproom
pg_isready -h host.docker.internal -p 5433
```

> **DevContainer trap — read this before you scan anything.** The Postgres container
> runs on the **host** docker daemon and must be reached at `host.docker.internal`.
> Inside the container, `localhost:5433` is frequently a *different*, throwaway
> Postgres (for example a tmpfs-backed instance used by `cargo test`) whose data
> vanishes when the container stops. Pointing maproom at `localhost` produces **no
> error** — it happily indexes into a disposable database, and you discover the loss
> hours later as missing data. Check the host, not just the port.

Setup details for a shared fleet are in
[multi-repo-guide.md](./references/multi-repo-guide.md).

### 2. Initialize Database
```bash
maproom db migrate
```
Run once per database to create the schema.

### 3. Scan Repository
```bash
maproom scan
```
Takes ~2s for small repos. A scan populates **chunks** — the full-text and structural
index. Whether a scan also produces embeddings for new chunks depends on your build's
defaults; check `maproom scan --help`. Do not rely on it: see step 4.

For large repos, run in the background:
```bash
nohup maproom scan > /tmp/maproom-scan.log 2>&1 &
```

> **Do not wrap a scan in a short timeout.** Scanning a large repo on a slow mount
> (FUSE, virtiofs, a network share) can exceed a wrapping timeout *mid-scan*. The repo
> is left partially indexed while every other repo in the same run reports success, so
> the aggregate run looks clean and nothing tells you a repo is half-indexed. Measured
> example: a 1,328-file docs repo died at 30% under an 1800s cap and needed ~2,326s to
> finish when run unbounded. If you must bound it, bound it generously and check each
> repo's result individually.

### 4. Generate embeddings (separate, recurring, and bounded)

**Scanning does not keep embeddings current.** This is the single most misunderstood
part of maproom. The incremental processor that watchers use **deletes** the embeddings
for changed chunks and never regenerates them. Embedding coverage therefore **decays
continuously as you work**, silently, because search keeps returning results the whole
time (see [Embeddings fail silently](#embeddings-fail-silently)).

"Watch keeps the index fresh" is true for **chunks** and false for **embeddings**. A
periodic `maproom generate-embeddings` job — cron, pm2 schedule, whatever you have — is
**required** to hold coverage.

**Bound every pass.** An unbounded `generate-embeddings` dies at scale, and gets worse
the more successful it has been. Its pending-chunk query is a `NOT IN` subquery whose
cost grows with the number of rows already embedded, and maproom pins
`statement_timeout` to 5000ms on every connection (set in `after_connect`, with no
environment override). Measured on ~195k chunks with ~113k already embedded, asking for
40,000 pending chunks blew past 5s and every pass died with:

```
Failed to fetch chunks ... canceling statement due to statement timeout
```

Bounding the same fetch to 10,000 measured ~0.73s. The failure appears **late** — the
job stalls exactly when it is closest to finishing.

So: cap the work per pass and loop until the pending count reaches zero, in the
background. Get the flag names for capping and batching from
`maproom generate-embeddings --help` on your binary, then run it detached:

```bash
nohup maproom generate-embeddings > /tmp/maproom-embeddings.log 2>&1 &
```

Batch sizing, provider sub-batch behaviour, concurrency tuning
(`MAPROOM_EMBEDDING_PARALLEL_*`), and what happens when you switch models are all in
[embedding-providers.md](./references/embedding-providers.md). Two facts worth carrying
in your head now:

- A pipeline batch size **at or below the sub-batch size (default 50) runs fully
  serialized** — provider parallelism never engages.
- **Switching embedding models requires deleting the old rows.** Embeddings are stored
  one row per blob with a unique constraint, so a blob already embedded at the old
  dimension keeps its row, incremental runs skip it, and vector search at the new
  dimension cannot see it. Coverage is silently corrupted.

### 5. Verify
```bash
maproom status
```
Confirm three separate things:

1. **Your repo is listed** — and note the **indexed repo name**, which is derived from
   the git origin and is often not the directory name (see
   [Multi-Repo Search](#multi-repo-search)).
2. **Embedding coverage** — the per-repo `Embeddings: N (P%)` line. `Embeddings: 0
   (0.0%)` means vector search has nothing to work with.
3. **Not "Last scan"** — that timestamp is not a freshness signal. See below.

FTS search works immediately after a scan. Vector search requires embeddings.

#### Embeddings fail silently

Zero embeddings **does not error**. With no embeddings, `maproom search` still returns
results by falling back to full-text and structural ranking; only vector search and
semantic ranking are unavailable. `maproom status` shows `Embeddings: 0 (0.0%)` and the
`encoding_runs` table stays empty.

Never infer embedding health from "search works". Check coverage explicitly. On
Postgres you can check it per repo directly:

```sql
select r.name, count(distinct c.blob_sha) blobs, count(distinct e.blob_sha) embedded
from repos r join worktrees w on w.repo_id=r.id
join chunk_worktrees cw on cw.worktree_id=w.id
join chunks c on c.id=cw.chunk_id
left join code_embeddings e on e.blob_sha=c.blob_sha group by 1 order by 2 desc;
```

#### "Last scan" is not a freshness signal

`maproom status` prints a per-worktree **Last scan** timestamp that is **not updated**
when an incremental scan finds the git tree SHA unchanged — it logs
`No changes detected (tree SHA match), skipping scan` and leaves the old timestamp in
place. A months-old "Last scan" therefore usually means *nothing changed since then*,
not *the index is stale*. Judging staleness by this field leads to pointless full
re-scans.

To actually test freshness: search for a symbol you know was added recently, or compare
the repo's current HEAD against what the index recorded.

## Choosing Search Type

| You Have | Use | Example |
|----------|-----|---------|
| Exact function/variable name | `search` | `--query "validate_state_file_schema"` |
| Known terminology | `search` | `--query "autogate ready block"` |
| Conceptual question | `vector-search` | `--query "how to pause automated work"` |
| Exploring unfamiliar code | `vector-search` | `--query "authentication flow"` |
| Finding code patterns | `search` | `--query "try except json"` |

**Rule of thumb:** Know the words? Use `search`. Know the concept? Use `vector-search`.

### Vector Search Syntax
```bash
maproom vector-search --repo <repo> --query "<query>" --format agent
```
Requires embeddings (see First-Time Setup step 4).

### Evidence from Testing

| Query | FTS (`search`) | Vector (`vector-search`) |
|-------|----------------|--------------------------|
| `"autogate gate ready"` | Found exact function | Related concepts, less precise |
| `"mechanism to pause automated work"` | Poor results | Found relevant documentation |
| `"validate schema json"` | Found exact functions | Found related validation concepts |

For query optimization, see [search-best-practices.md](./references/search-best-practices.md).

## Output Formats

The `search` and `vector-search` commands support two output formats via `--format`:

**JSON (default):** Verbose structured output with full metadata. Preview requires explicit `--preview` flag.
**Agent (`--format agent`):** Compact one-line-per-result optimized for agent context windows. Preview is implicit.

### JSON Format Example
```bash
$ maproom search --repo <repo> --query "test" --format json --k 2
```
```
{"hits":[{"chunk_id":4722,"end_line":159,"file_relpath":"plugins/.../README.md","kind":"code_block","score":3.60,"start_line":150,"symbol_name":"Code: text"}]}
```

### Agent Format Example
```bash
$ maproom search --repo <repo> --query "test" --format agent
```
```
plugins/.../README.md:150 | code_block Code: text | 3.60 | ```text tests/ ├── integration-test-sdd-loop.sh...
```
Structure: `{file}:{line} | {kind} {symbol} | {score} | {preview}...`

### Preview Behavior
Agent format implicitly enables preview — adding `--preview` is redundant. For JSON format, preview must be explicitly requested before a `"preview"` field appears. The preview length is adjustable and its default differs per format; `maproom search --help` carries the current values for your build.

### Recommendation
For agent use, always pass `--format agent`. It conserves context window tokens while preserving essential location, kind, score, and preview information.

## Filtering and Tuning

All filter values are **case-sensitive**. Combine multiple values with commas for OR logic. Filters are AND-combined across flags: `--kind func --lang py` returns only Python functions.

> **The list below is orientation, not a specification.** Chunk kinds and language
> tags come from the parser in *your* build and change between versions. Run
> `maproom search --help` for the values your binary accepts, and check what is
> actually present in your index rather than assuming a kind exists:
> `maproom search --repo <repo> --query <term> --format json | jq -r '.hits[].kind' | sort -u`

| Flag | Value | Matches |
|------|-------|---------|
| `--kind` | `func` | Function definitions |
| `--kind` | `class` | Class definitions |
| `--kind` | `struct` | Struct definitions (Rust, Go) |
| `--kind` | `enum` | Enum definitions (Rust) |
| `--kind` | `method` | Class/struct methods |
| `--kind` | `constant` | Module-level constant assignments |
| `--kind` | `imports` | File-level import blocks |
| `--kind` | `heading_1` / `heading_2` / `heading_3` / `heading_4` | Markdown headings |
| `--kind` | `code_block` | Fenced code blocks |
| `--kind` | `markdown_section` | Markdown sections (lists, tables) |
| `--kind` | `link` | Hyperlink references |
| `--kind` | `json_key` | JSON key-value pairs |
| `--lang` | `py` | Python (.py) |
| `--lang` | `ts` | TypeScript (.ts) |
| `--lang` | `rs` | Rust (.rs) |
| `--lang` | `go` | Go (.go) |
| `--lang` | `md` | Markdown (.md) |
| `--lang` | `json` | JSON (.json) |

The vocabulary above is a *taxonomy*, not a flag reference — the authoritative list of
filter flags and their defaults for your build is `maproom search --help`.

```bash
$ maproom search --repo <repo> --query "auth" --kind func --lang py --format agent
$ maproom vector-search --repo <repo> --query "error handling" --threshold 0.7 --format agent
```

Beyond kind and language there are three more decisions worth knowing about.
**Similarity cut-off** is vector-search only: `--threshold` takes a cosine similarity
between 0.0 and 1.0 and drops everything below it — raise it when a concept query keeps
returning plausible-but-wrong neighbours, omit it to see the full ranking.
**Worktree scope** matters in a multi-worktree checkout: results can be narrowed to a
single worktree, and by default a chunk present in several worktrees collapses to one
hit — turn deduplication off only when you specifically need to know which worktrees
contain a match. **Preview length** trades context-window tokens for readable snippets
(see [Output Formats](#output-formats)).

Exact spellings and current defaults for all of these come from `maproom search --help`
and `maproom vector-search --help`.

| Task | Recommended Flags |
|------|-------------------|
| Find Python functions | `--kind func --lang py --format agent` |
| Find TypeScript classes | `--kind class --lang ts --format agent` |
| Browse markdown docs | `--kind heading_2 --lang md --format agent` |
| High-precision semantic | `--threshold 0.8 --format agent` (vector-search) |
| Find all class hierarchies | `--kind class --format agent` |
| Scan JSON config keys | `--kind json_key --lang json --format agent` |

## Context Command Reference

Explore a chunk's relationships after finding it via search:
```bash
maproom context --chunk-id <id> [flags]
```

Context expansion involves two decisions. **What to pull in** — the relationship axes:
the call graph around the chunk (its callers, its callees), plus related tests, docs and
configuration. Ask only for the axes you will actually read; each one widens the bundle.
**How far and how much** — a traversal depth and a token budget for the assembled
bundle. Depth is what you raise when tracing a call chain up to its entry point; budget
is what you lower when the bundle starts crowding out your context window.

Run `maproom context --help` for the flag names and defaults on your binary — depth and
budget defaults in particular differ between older and newer builds.

**Note:** The `--chunk-id` requires a numeric ID from `--format json` output, not the `file:line` format from `--format agent`.

Flags combine freely: `context --chunk-id <id> --callers --callees --max-depth 3`

## Common Workflows

### Understand a Feature's Implementation
Find a feature and trace its call relationships (depth-first).
1. Search by concept:
```bash
maproom vector-search --repo <repo> --query "authentication login flow" --format agent
```
2. Expand context around a relevant result:
```bash
maproom context --chunk-id <id> --callers --callees
```
_(Vector search because we know the concept but not exact function names.)_

### Find All Error Handlers
Locate error handling patterns across the codebase.
1. Search for error-related terms:
```bash
maproom search --repo <repo> --query "error exception handler" --format agent
```
2. Get context with a constrained budget:
```bash
maproom context --chunk-id <id> --budget 4000
```
_(FTS appropriate since "error" and "exception" are known keywords.)_

### Trace Call Chains
Follow a function's callers up the call stack to find entry points.
1. Find the function:
```bash
maproom search --repo <repo> --query "process_payment" --kind func --format agent
```
2. Trace callers with increased depth:
```bash
maproom context --chunk-id <id> --callers --max-depth 3
```
_(FTS used to locate an exact function name.)_

### Onboard to Unfamiliar Code
Explore iteratively (breadth-first) when you don't know the terminology yet.
1. Broad concept search:
```bash
maproom vector-search --repo <repo> --query "data processing pipeline" --format agent
```
2. Read context on an interesting result:
```bash
maproom context --chunk-id <id>
```
3. Refine using terms discovered in step 2:
```bash
maproom vector-search --repo <repo> --query "transform stage batch worker" --format agent
```
_(Vector search for exploring concepts when terminology is unknown.)_

### Find Configuration and Settings
Locate where configuration values are defined and how they're consumed.
1. Search for config terms:
```bash
maproom search --repo <repo> --query "config settings env" --format agent
```
2. See what the config drives:
```bash
maproom context --chunk-id <id> --callees
```
_(FTS because configuration keywords are known terms.)_

## Multi-Repo Search

> All workflows above use `--repo <repo>` placeholders. This section explains how to choose which repo to use.

Cross-repo search requires that every repo lives in **one shared database** — in
practice, one shared Postgres for the fleet (see
[First-Time Setup step 1](#1-choose-a-storage-backend)). Repos indexed into separate
SQLite files cannot be searched together.

### `--repo` matches the indexed name, not the directory

`--repo` matches the **indexed repo name**, which is derived from the git origin, with
suffix fuzzy-matching. It is **not** the directory name on disk. A directory named
`django-olympics` whose origin makes it `django/django` is found by `--repo django`;
`--repo django-olympics` returns **zero hits with no error message**.

Silent empty results are usually this. Before blaming the query or the embeddings, list
the actual indexed names:

```bash
maproom status
```

### Choosing the Right Repo

| Question Type | Search In | Why |
|---|---|---|
| "How does X work?" | Code repo | Implementation details live in source code |
| "Why was X built this way?" | Specs repo | Design rationale in planning documents |
| "What was the plan for X?" | Specs repo | Tickets, epics, and architecture docs |
| "Where is X implemented?" | Code repo | Function and class locations |
| "What are the requirements for X?" | Specs repo | Ticket acceptance criteria and epic goals |
| "What changed in X?" | Code repo | Recent modifications and git history |

### Reading the Config File

The workspace config file `maproom-repos.yaml` (in the workspace root) lists all available repos and their roles. Check it to find repo names and paths:
```bash
cat maproom-repos.yaml
```

A template is available at `./templates/maproom-repos.yaml` for reference.

### No-Config Fallback

If `maproom-repos.yaml` is not found, discover indexed repos directly:
```bash
maproom status
```
This lists all repos that have been scanned and are available for search.

### Cross-Repo Search Workflow

When a question spans both design and implementation, search across repos sequentially.

**Example: Understanding why and how authentication works**

1. Check the specs repo for design rationale:
```bash
maproom vector-search --repo specs --query "authentication design decisions" --format agent
```
2. Then check the code repo for implementation:
```bash
maproom vector-search --repo code --query "authentication login flow" --format agent
```
3. Expand context on a relevant code result:
```bash
maproom context --chunk-id <id> --callers --callees
```
_(Vector search across repos: specs for "why", code for "how".)_

For detailed multi-repo strategies, shared-Postgres setup, cross-repo patterns, and chunk kind information, see [multi-repo-guide.md](./references/multi-repo-guide.md).

## Troubleshooting

Start here; full error recovery steps are in [troubleshooting.md](./references/troubleshooting.md).

**`pool timed out while waiting for an open connection`** (Postgres backend; `psql`
also reports `Connection refused`):
The Postgres **container is not running**, or you are pointed at the wrong host. This
is *not* a file-permissions problem — that diagnosis only applies to SQLite. Check
`pg_isready -h host.docker.internal -p 5433`, then start the host container. The same
error appears transiently when something is saturating the database's CPU (a runaway
`ANALYZE`, a heavy manual query), so check `pg_stat_activity` for long-running
statements before concluding the container is down.

**`Failed to fetch chunks ... canceling statement due to statement timeout`** (during
`generate-embeddings`):
The pending-chunk query exceeded maproom's hard-pinned 5000ms `statement_timeout`.
Bound each pass to a smaller number of chunks (~10,000 measured ~0.73s where 40,000
timed out) and loop until pending reaches zero. See
[First-Time Setup step 4](#4-generate-embeddings-separate-recurring-and-bounded).

**`Reauthentication failed. cannot prompt during non-interactive execution`**
(Google/Vertex provider):
Application Default Credentials expired. Re-run `gcloud auth application-default login`
interactively, or use a service-account key for unattended runs. Note that
`GEMINI_API_KEY` / `GOOGLE_API_KEY` do nothing for this provider. See
[adc-setup.md](./references/adc-setup.md).

**`Sub-batch N failed: API error: ...`** (one sub-batch errors, whole batch marked
failed):
These are usually transient provider hiccups and self-heal on the next pass, so a
bounded loop converges. A smaller pipeline batch size limits the blast radius per
incident — but keep it **above** the sub-batch size (default 50) or provider
parallelism never engages. See
[embedding-providers.md](./references/embedding-providers.md).

**Token limit exceeded** (`input token count is ... but the model supports up to 20000`):
The payload sent to the provider is too large. Reduce the provider sub-batch size
(`MAPROOM_EMBEDDING_PARALLEL_SUB_BATCH_SIZE`, default 50) rather than dropping the
pipeline batch size to a tiny value — a pipeline batch at or below the sub-batch size
runs fully serialized. Check `maproom generate-embeddings --help` for the batch flags
on your build.

**Vector search returns no results** (search completes but returns empty):
Check embedding coverage explicitly — `maproom status`, per-repo
`Embeddings: N (P%)`. Zero embeddings never raises an error; `search` keeps working via
full-text fallback while `vector-search` has nothing to match. If coverage is low, run a
bounded `maproom generate-embeddings` loop. If coverage is fine, suspect the repo name
(see [`--repo` matches the indexed name](#--repo-matches-the-indexed-name-not-the-directory)).

**Zero hits from a repo you know is indexed:**
Almost always a `--repo` name mismatch — the indexed name comes from the git origin,
not the directory. Run `maproom status` and use the listed name.

**No repositories indexed** (status shows no repositories):
Run First-Time Setup above. On Postgres, first confirm you are pointed at the shared
database and not a throwaway `localhost` instance.

**Stale results after code changes** (results reference old or deleted code):
Re-scan the repository with `maproom scan`. Do **not** use the `Last scan` timestamp as
evidence of staleness — it is not updated when an incremental scan finds the tree SHA
unchanged. And remember that re-scanning restores **chunks only**; embeddings for
changed chunks were deleted and need a separate `generate-embeddings` pass.

**Embedding coverage keeps dropping while watchers run:**
Expected, not a bug. Watchers delete embeddings for changed chunks and never regenerate
them. Schedule a recurring bounded `generate-embeddings` job.

**Every watcher disappeared** (`pm2 list` shows an empty table, pm2 daemon still alive):
Run `pm2 resurrect` — it restores the whole fleet from `~/.pm2/dump.pm2`. Do not
hand-rebuild watchers one by one.

**Irrelevant results** (results don't match intent):
Check Choosing Search Type above — FTS for exact terms, vector for concepts. Use 2-3 core terms.

## Query Tips
Extract 2-3 terms from questions. See [search-best-practices.md](./references/search-best-practices.md).
