# Error Diagnosis

Conceptual explanations of why maproom errors occur and what they mean. This document helps you *understand* errors. For step-by-step recovery commands, see [troubleshooting.md](../../maproom-search/references/troubleshooting.md).

---

## Error Category Map

Every maproom error falls into one of five categories. Identifying the category is the first step to understanding the error.

| Category | Caused By | User-Actionable? | Examples |
|---|---|---|---|
| **Credential** | Expired tokens, missing API keys, wrong provider | Yes — refresh or configure | ADC expiry, missing OPENAI_API_KEY |
| **Index** | Repo not scanned, stale data, missing embeddings | Yes — scan or regenerate | "No repositories indexed", stale results |
| **CLI** | Binary missing, wrong version, invalid flags | Yes — install or fix syntax | "command not found", invalid flag value |
| **Query** | Wrong search type, bad filters, special chars | Yes — reformulate query | Zero results, irrelevant results |
| **Infrastructure** | Database unreachable, disk full, permissions, SQLite lock | Yes — fix environment | `pool timed out while waiting for an open connection`, `Connection refused`, database locked |

**If you can't categorize the error** and it mentions panics, segfaults, or stack traces, it may be a **CLI bug** rather than a user-actionable issue.

### Exit Code Quick Reference

| Exit Code | Meaning | Retry? |
|---|---|---|
| **0** | Success (including empty result sets) | N/A |
| **1** | Runtime error (transient: database lock, network timeout, file not found) | Yes — may succeed on retry |
| **2** | Configuration error (persistent: missing API key, invalid provider, bad arguments) | No — fix config first |

---

## Credential Errors Explained

### Why Credentials Expire

Maproom's vector search and embedding generation call an embedding provider chosen at runtime by `MAPROOM_EMBEDDING_PROVIDER` — Google/Vertex, OpenAI, Cohere, Ollama, Bedrock. Which providers your build actually accepts varies between builds, so confirm against your own binary (`maproom --help`) rather than assuming. Every remote provider needs credentials, and credentials expire or get revoked.

- **Google ADC tokens** expire after ~1 hour and are automatically refreshed — but the refresh token itself can expire after extended periods of inactivity
- **OpenAI API keys** don't expire by time, but can be revoked or rate-limited

### How to Recognize Credential Errors

Credential errors contain one of these patterns in the error message:
- "Failed to create embedding service" (top-level error for all credential failures)
- "Failed to create token provider from ADC" (appears in the `Caused by` chain)
- "No Google credentials found" (appears in the `Caused by` chain)
- "invalid_rapt"
- "quota_project_id is required"
- `Reauthentication failed. cannot prompt during non-interactive execution` — ADC expired and no human is present to re-consent
- References to `OPENAI_API_KEY` when you're not using OpenAI

**Note:** The top-level error message is usually "Failed to create embedding service". The specific credential detail (ADC, token provider, etc.) appears in the `Caused by` chain below it. An agent scanning only the first line of error output should match on "Failed to create embedding service" as the primary pattern.

### Credential Error vs Code Bug

| Signal | Credential Issue | CLI Bug |
|---|---|---|
| Error mentions "ADC", "token", "API key" | Yes | No |
| Error mentions code paths, panics, segfaults | No | Yes |
| FTS search (`search`) still works | Yes — FTS doesn't need credentials | Possibly — depends on the bug |
| Error appeared after a period of inactivity | Yes — tokens expired | Unlikely |
| Error appeared immediately after CLI update | Unlikely | Possible |

### What to Do

1. **Don't investigate maproom source code** — credential errors are expected operational events
2. **Fall back to FTS** — `maproom search` needs no embedding-provider credentials at all; full-text and structural ranking answer straight out of whichever backend you are on (local SQLite, or the shared Postgres a fleet points at)
3. **Refresh credentials** when convenient — see [ADC setup guide](../../maproom-search/references/adc-setup.md)

### Google/Vertex Uses ADC — an API Key Does Nothing

`MAPROOM_EMBEDDING_PROVIDER=google` authenticates with **Application Default Credentials** plus a project id in `GOOGLE_PROJECT_ID` (or `MAPROOM_GOOGLE_PROJECT_ID`). Setting `GEMINI_API_KEY` or `GOOGLE_API_KEY` has **no effect whatsoever** on this provider. This is the most common and most confusing misconfiguration in the whole tool: the variables look like they should work, nothing complains that they are set, and the failure looks like a credential outage rather than a wiring mistake.

ADC also expires. When it does, every embedding pass dies at config time — before a single chunk is processed:

```text
Reauthentication failed. cannot prompt during non-interactive execution
```

Which fix you want depends on who runs the job:

- **Interactive:** `gcloud auth application-default login`
- **Unattended** (cron, watcher, CI): set `GOOGLE_APPLICATION_CREDENTIALS` or `MAPROOM_GOOGLE_APPLICATION_CREDENTIALS` to a service-account key. A scheduled embedding job riding on a human's ADC will keep dying with the string above, on a cadence set by however long that ADC lasts.

Other providers follow the same env-var shape: `openai` reads `OPENAI_API_KEY` (or `MAPROOM_OPENAI_API_KEY`), Cohere direct reads `MAPROOM_COHERE_API_KEY`, `ollama` needs no credentials at all, and `bedrock` resolves the standard AWS chain — static env keys, shared config/credentials files with `AWS_PROFILE`, web identity/IRSA, container credentials. Bedrock is not compiled into every maproom build; check that your binary accepts `MAPROOM_EMBEDDING_PROVIDER=bedrock` before planning around it.

---

## Infrastructure Errors Explained

Which infrastructure can break depends on which backend you are running, and maproom supports two. The store is chosen at runtime from `MAPROOM_DATABASE_URL`: a `sqlite://` URL or a plain filesystem path selects SQLite (the default, `~/.maproom/maproom.db`); a `postgres://` or `postgresql://` URL selects Postgres, which requires a build compiled with the `postgres` feature. A `--database-url` argument overrides the environment variable. `maproom --help` lists the subcommands and environment variables your build supports.

### "pool timed out" / "Connection refused" — the Database Is Not There

```text
pool timed out while waiting for an open connection
```

and, from `psql` against the same URL:

```text
Connection refused
```

On a Postgres-backed install this pair almost always means **the Postgres container is not running**, or maproom is pointed at the wrong host. It is *not* a file-permissions problem — permission errors and `database is locked` belong to the SQLite backend, and reaching for `chmod` here spends the incident on the wrong system entirely.

```bash
pg_isready -h host.docker.internal -p 5433
```

If that fails, start the database container and retry. If it *succeeds* and maproom still times out, the pool is starving rather than absent: something is saturating the database's CPU — a runaway `ANALYZE`, a heavy hand-run query, several embedding jobs at once. Look before restarting anything:

```sql
select pid, state, now() - query_start as runtime, left(query, 120)
from pg_stat_activity
where state <> 'idle'
order by runtime desc;
```

### The Devcontainer `localhost` Trap

In a devcontainer the shared Postgres normally runs on the **host** docker daemon, and must be reached at `host.docker.internal`:

```text
postgres://maproom:maproom@host.docker.internal:5433/maproom
```

Inside the container, `localhost:5433` may be a *different*, throwaway Postgres — for example a tmpfs-backed instance used by cargo tests — whose data vanishes when the container stops. Pointing maproom there raises **no error at all**: scans report success and the data is simply gone later. The symptom surfaces downstream instead, as repos that "were definitely indexed" reporting zero chunks, or cross-repo search that only ever sees whatever was scanned most recently. Check the URL maproom is actually using before you re-scan anything.

A local Ollama endpoint has the same shape of trap: `OLLAMA_URL` (also `MAPROOM_OLLAMA_URL`) must be `http://host.docker.internal:11434` from inside a container, because `localhost:11434` is not the host's Ollama.

---

## Reading `maproom status` Output

Many troubleshooting steps say "run `maproom status`" — here's what to look for:

| Field | Healthy Value | Problem Indicator |
|---|---|---|
| Chunks | > 0 | 0 chunks = repo not scanned |
| Embeddings % | > 0% (for vector search) | 0% = embeddings not generated; FTS still works and says nothing |
| Last scan | Any value, including months old | **Not a freshness signal** — see the note below |
| Languages | Expected languages listed | Missing languages = incomplete scan |
| Repo name | The name your searches must filter on | Differs from the directory name on disk — the usual cause of silent zero hits |

`maproom status --json` gives you output you can parse; `maproom status --help` lists the filtering flags your binary supports.

**`Last scan` does not measure staleness.** An incremental scan that finds the git tree SHA unchanged logs `No changes detected (tree SHA match), skipping scan` and leaves the previous timestamp untouched. A months-old `Last scan` on a quiet worktree therefore means "nothing has changed since then", *not* "this index has rotted". Judging staleness by this field is how people end up running long, pointless full re-scans of repos that were already current. See [Index Freshness Explained](#index-freshness-explained) for checks that actually mean something.

---

## Index Freshness Explained

### What "Stale Index" Means

The index is **not** a single point-in-time snapshot of one local SQLite file, and modelling it that way is the source of most bad staleness calls. Two things vary independently.

**The backend.** SQLite or Postgres, chosen from `MAPROOM_DATABASE_URL` (see [Infrastructure Errors](#infrastructure-errors-explained)). A multi-repo fleet normally points every repo at one shared Postgres, which is exactly what makes cross-repo search work — so a "missing" repo there is often a repo indexed into a *different* database, not a stale one.

**The two halves of freshness.** Chunks and embeddings age by different mechanisms, at different rates, and only one of them is refreshed by scanning:

| Half of the index | Refreshed by | How it actually goes stale |
|---|---|---|
| Chunks (FTS, structure, `context`) | `maproom scan`, or a running `maproom watch` watcher | Only when code changes and nothing scans afterward |
| Embeddings (vector search) | `maproom generate-embeddings`, and nothing else | **Continuously, while you work** — the incremental processor deletes embeddings for changed chunks and never regenerates them |

"Is my index fresh?" is therefore two questions with two different answers, and the second one degrades on its own even in a worktree that is being watched perfectly. See [The Watch Alternative](#the-watch-alternative).

### When Does the Index Become Stale?

For the **chunk** half, assuming no watcher is running on the worktree:

| Event | Index Impact | Action Needed |
|---|---|---|
| Editing a few files | Slightly stale — minor risk | Optional re-scan |
| Switching branches | Potentially very stale | Re-scan recommended |
| Large merge or rebase | Likely stale | Re-scan recommended |
| Major refactor (renames, moves) | Definitely stale | Re-scan required |
| No code changes | Fresh | No action |

### How to Actually Check Freshness

Do **not** use the `Last scan` timestamp. An incremental scan that finds the git tree SHA unchanged logs:

```text
No changes detected (tree SHA match), skipping scan
```

and leaves the old timestamp in place, so a perfectly current worktree can report a `Last scan` from months ago. Three checks that carry real information:

1. **Search for a symbol you know is recent.** A function you added this week either comes back or it doesn't. Fastest honest answer for the chunk half.
2. **Compare the repo's current `HEAD` against the commit the index recorded** for that worktree. Different commit, genuinely behind; same commit, the chunks are current no matter what the timestamp says.
3. **Check embedding coverage explicitly.** `maproom status` reports it per repo as `Embeddings: N (X%)`. Never infer it from "search works" — see below.

### Zero Embeddings Never Errors

With no embeddings at all, `maproom search` still returns results: it falls back to full-text and structural ranking. Nothing fails, nothing warns, exit code is 0 — only vector search and semantic ranking are quietly unavailable. `maproom status` shows `Embeddings: 0 (0.0%)` for the repo and the `encoding_runs` table stays empty.

That is why "search is returning hits, so the index is fine" is an unsafe inference, and why coverage has to be measured rather than assumed. On Postgres you can measure it directly:

```sql
select r.name, count(distinct c.blob_sha) blobs, count(distinct e.blob_sha) embedded
from repos r
join worktrees w on w.repo_id = r.id
join chunk_worktrees cw on cw.worktree_id = w.id
join chunks c on c.id = cw.chunk_id
left join code_embeddings e on e.blob_sha = c.blob_sha
group by 1 order by 2 desc;
```

### Scanning vs Embedding Generation

These are two distinct operations:
- **Scan** (`maproom scan`) — parses code with tree-sitter, extracts chunks, stores them in whichever backend is configured (SQLite or Postgres). Fast (~2 seconds for small repos). Required for FTS search.
- **Embedding generation** (`maproom generate-embeddings`) — creates vector representations of each chunk via API. Slower (minutes for large repos). Required for vector search. Check progress with `maproom encoding-progress`.

After a scan, FTS search works immediately. Vector search requires embeddings to also be up to date. Use `maproom encoding-progress` to monitor embedding generation completion percentage.

### Partial Scan Success (Scan OK, Embeddings Fail)

By default, `maproom scan` attempts embedding generation after indexing. If credentials are missing, you'll see:

```text
✅ Scan completed successfully!
...
⚠️  Warning: Embedding generation failed: Configuration error: Missing required configuration: No Google credentials found.
```

**This is a partial success, not a failure.** The scan itself succeeded — FTS search works immediately. Only vector search is affected. The scan exits with code 0. Embedding generation can also be skipped deliberately; run `maproom scan --help` for the flag that disables it on your binary.

### Partial Scan From a Timeout on a Slow Mount

A nastier partial success: scanning a large repo on a slow mount (FUSE, virtiofs, a network share) can blow through a *wrapping* timeout — a `timeout` command, a job runner's cap — part-way through. That repo is left partially refreshed while every other repo in the run reports success, so the aggregate output looks clean. Nothing in the summary says "repo 7 only got 30% of the way".

Measured example: a 1,328-file docs repo died at roughly 30% under an 1800s cap, and needed about 2,326s to finish when run unbounded. If one repo's results feel half-there after a batch scan, re-scan that repo on its own with the cap raised or removed, and watch it run to completion.

### `generate-embeddings` Dies at Scale — and Gets Worse as It Succeeds

```text
Failed to fetch chunks ... canceling statement due to statement timeout
```

This is the most confusing embedding failure, because it shows up *late* — the job stalls exactly when it is closest to finishing.

The pending-chunk query is a `NOT IN` subquery whose cost grows with the size of `code_embeddings`, and maproom pins `statement_timeout` to 5000ms on every connection it opens (set in `after_connect`, with no environment override). So the more chunks you have successfully embedded, the more expensive it becomes just to ask "what is still pending" — until that question alone exceeds five seconds and every pass dies before embedding anything at all.

Measured on ~195k chunks with ~113k rows already embedded: asking for 40,000 pending chunks blew the 5s timeout on every pass; asking for 10,000 took about 0.73s.

**The fix is to bound each pass and loop until the pending count reaches zero**, instead of trying to drain the backlog in one unbounded run. Run `maproom generate-embeddings --help` for the flags that bound a pass on your binary, and see the batch-size tradeoff below.

**Do not "reproduce" this by hand in psql and trust what you see.** maproom sets `work_mem` (256MB) on its own connections, and that changes this query's plan by three orders of magnitude: the same `NOT IN` plans at cost 218,119,741 (Materialize plus a per-row Seq Scan) under a small `work_mem`, versus 101,635 (a hashed SubPlan) at 64MB and above. A hand-run query in a default psql session looks catastrophically worse than what maproom actually executes — that is a measurement artifact, not the bug.

### One Bad Sub-Batch Fails the Whole Batch

```text
Sub-batch 2 failed: API error: Bad request: Batch of 50 texts rejected: {"error":"Post \"http://127.0.0.1:51950/tokenize\": EOF"}
```

Embedding requests go out in sub-batches (Ollama: 50 texts per sub-batch, 8 concurrent by default). If one sub-batch errors — the example above is the Ollama model runner dropping the connection — maproom marks the **entire pipeline batch** failed, not just those 50 texts.

Your batch size is therefore the blast radius: at `--batch-size 1000` one dropped connection costs 1,000 chunks, at 500 it costs 500. These failures are **transient and self-healing** — the lost chunks are simply still pending next time — so a bounded loop converges regardless. A smaller batch just wastes less work per incident.

Do not shrink it too far, though: sub-batch parallelism engages only when the pipeline batch size **exceeds** the sub-batch size, so a batch of 50 or below runs fully serialized. The knobs are `MAPROOM_EMBEDDING_PARALLEL_ENABLED`, `MAPROOM_EMBEDDING_PARALLEL_SUB_BATCH_SIZE` (default 50) and `MAPROOM_EMBEDDING_PARALLEL_MAX_CONCURRENCY` (default 8). Against a local Ollama, throughput improved up to 8 concurrent requests and got *worse* at 16.

### Switching Embedding Models Corrupts Coverage Silently

On Postgres, `code_embeddings` holds one row per `blob_sha` with a UNIQUE constraint on it, and fixed per-dimension columns `embedding_768` / `embedding_1024` / `embedding_1536`, each with its own HNSW index. Two consequences are worth knowing before they become an incident:

- A blob already embedded at the old dimension **keeps its row** when you switch models. Incremental runs skip it (a row exists) and vector search at the new dimension cannot see it. Switching provider or model without first deleting the old-dimension rows raises no error and silently degrades recall. Verify homogeneity:
  ```sql
  select embedding_dim, model_version, count(*) from code_embeddings group by 1, 2;
  ```
- Only 768, 1024 and 1536 have columns. A model emitting any other dimension (Ollama `qwen3-embedding:4b` at 2560, or Titan v2's optional 256/512) cannot be stored at all, and is rejected by a dimension validation step rather than failing after a full run. Model choice is constrained by the schema, not by taste.

`code_embeddings` also has no foreign key to `chunks`, so deleting chunks leaves orphan embedding rows behind. They are harmless in themselves, but they accumulate — and they inflate the `NOT IN` query described above.

### The Watch Alternative

`maproom watch` auto-indexes on file changes, keeping the **chunk** half of the index fresh without manual re-scanning. Useful during active development.

**It does not keep embeddings fresh — it consumes them.** The incremental processor *deletes* the embeddings belonging to changed chunks and never regenerates them. Coverage therefore decays continuously and silently for as long as you keep working, and nothing surfaces it, because search keeps returning results the whole way down (see [Zero Embeddings Never Errors](#zero-embeddings-never-errors)).

Any documentation — including earlier revisions of this page — that says watching "keeps the index fresh without manual re-scanning" is describing chunks only. For embeddings the opposite is true. A watched fleet still needs a periodic `maproom generate-embeddings` job (cron, or a process-manager schedule), bounded and looped as described above, or coverage trends toward zero.

### When the Watcher Fleet Disappears

Where watchers run under a process manager — typically one watcher per repo under pm2 — the entire fleet can vanish while the manager itself is still alive and healthy: `pm2 list` prints an empty table, no watcher is running, and scanning silently stops for every repo at once.

Recovery is one command, not N:

```bash
pm2 resurrect
```

It restores every watcher from `~/.pm2/dump.pm2`. Without knowing that, the fix looks like hand-rebuilding each watcher from scratch.

---

## Search Quality Explained

### "No Results" Is Not Always an Error

Zero results can mean:
1. **The code genuinely doesn't exist** — a valid outcome, not a failure
2. **Wrong search type** — using FTS for a concept that needs vector search, or vice versa
3. **Filters too restrictive** — `--kind` or `--lang` excluding valid matches
4. **Query too specific** — too many terms diluting the search signal
5. **`--repo` doesn't match the indexed repo name** — the most common cause of a silent, error-free zero-hit result (below)

### Silent Zero Hits From a `--repo` Mismatch

`--repo` matches the **indexed repo name**, which is derived from the git origin, with suffix fuzzy-matching. It does not match the directory name on disk. A checkout living in `django-olympics` but indexed as `django/django` is found by `--repo django` (suffix match), while:

```text
maproom search --repo django-olympics --query "..."
```

returns **zero hits, exit code 0, and no error message at all**. Nothing in that output distinguishes it from "this code does not exist".

So when a search returns nothing and you expected hits, check the name before you re-scan anything: `maproom status` lists every indexed repo name, and those are the strings `--repo` accepts.

### Why FTS Misses Things Vector Search Finds

FTS matches exact keywords. If the code uses different terminology than your query, FTS won't find it:
- Query: "pause automated work" → FTS misses code that uses "gate", "block", "autogate"
- Vector search understands semantic similarity and bridges this vocabulary gap

### Why Vector Search Misses Things FTS Finds

Vector search matches concepts, not exact text. Precision suffers with very specific queries:
- Query: "validate_state_file_schema" → Vector search returns conceptually related validation code, but may rank the exact function lower than FTS would
- FTS excels at exact identifier lookup

### Partial-Term False Positives

FTS can return results that appear off-topic because BM25 scores when *any* query term matches. A query like "defragmentation optimizer" may return results matching only "optimizer" in unrelated code. This is not zero results — it's results that match on the wrong term.

Distinguish from truly irrelevant results:
- **Partial match**: Some results are relevant, others aren't — one query term is matching noise
- **Wrong search type**: All results are irrelevant — the concept needs vector search, not FTS
- **Stale index**: Results reference code that no longer exists — re-scan needed

### Context Command Errors

The `maproom context` command can fail with:
- `"Failed to assemble context for chunk N"` — the chunk ID doesn't exist in the index. Re-run `maproom search` to get a valid chunk ID.
- Context errors use a different format than search errors (raw error chain instead of structured `ERROR | type=... | message=...`). This is a known CLI inconsistency.
- Context on a `json_key` or `heading` chunk with `--callers` may return only the primary chunk (items=1) because documentation and configuration chunks don't have callers in the code graph.

**Common pitfall:** The context command requires **numeric chunk IDs** (e.g., `--chunk-id 4207`). The `--format agent` output shows `file:line` format, which is *not* a valid chunk ID. To get numeric IDs, run the search with `--format json` — the JSON output includes a `chunk_id` integer field for each result. Passing a file path or `file:line` string to `--chunk-id` will fail with a parse error.

### The Complementary Search Strategy

When one search type returns poor results, try the other:
1. FTS returns nothing? → Try vector search with a conceptual rephrasing
2. Vector search returns noise? → Try FTS with specific identifiers from the results
3. Both return nothing? → Verify the indexed repo *name* first (see above), then that the repo is indexed, then filters, then fall back to Grep

---

## Error Escalation Guide

### User-Actionable Errors

These errors have clear remediation steps the user can take:
- Credential expiry → refresh ADC or set API key
- Missing index → run `maproom scan`
- Missing embeddings → run `maproom generate-embeddings`, bounded per pass and looped
- Embedding pass dying on `canceling statement due to statement timeout` → bound the pass, don't re-run it unbounded
- Zero hits with no error → check the indexed repo name, not the directory name
- `pool timed out` / `Connection refused` → start the database container; check the URL is not `localhost`
- Bad query → reformulate with better terms
- Wrong search type → switch between FTS and vector
- Case-sensitive filters → use lowercase values

### Possible CLI Bugs

Escalate if the error:
- Contains a stack trace or panic
- References internal code paths
- Occurs with valid credentials and a fresh index
- Is reproducible across different queries
- First appeared after a CLI version update

### Fallback to Standard Tools

When maproom is unavailable or broken, fall back gracefully:
- **Instead of FTS** → use Grep for exact text search
- **Instead of vector search** → use the Explore agent for conceptual code exploration
- **Instead of context** → use Read to manually trace callers/callees

The fallback trades efficiency for availability. Maproom finds things faster, but Grep and Read always work.
