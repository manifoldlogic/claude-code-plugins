# Maproom Troubleshooting

Detailed error recovery for common maproom issues, including edge case handling for boundary conditions and concurrency scenarios. This is a companion to the quick-reference troubleshooting section in [SKILL.md](../SKILL.md) — start there for quick fixes, and use this file when you need root cause analysis or step-by-step recovery.

---

## First: Which Storage Backend Are You On?

Answer this before diagnosing anything else. maproom ships with **two storage backends**, and the
failure modes, the error strings and the fixes are different for each. Most of the older material
in this document was written against a single-repo SQLite database and is labelled accordingly.

**The backend is chosen at runtime from `MAPROOM_DATABASE_URL`:**

| Value of `MAPROOM_DATABASE_URL` | Backend |
|---|---|
| unset, a plain filesystem path, or `sqlite://...` | SQLite — the default, `~/.maproom/maproom.db` |
| `postgres://...` or `postgresql://...` | PostgreSQL — requires a build compiled with `--features postgres` |

A `--database-url` flag overrides the environment variable. Postgres support is a **build feature,
not a guarantee**: run `maproom --help` to see the subcommands and environment variables your build
actually supports before assuming it is available.

```bash
# What am I actually pointed at?
echo "$MAPROOM_DATABASE_URL"
maproom status
```

**Why it matters:** a SQLite database is a file you own, so permissions and local disk space are
real failure modes. A Postgres database is a server you reach over TCP, so *its* failure modes are
"container not running", "wrong host", "statement timeout" and "connection pool exhausted".
Applying a SQLite fix (`chmod`, deleting `maproom.db-wal`) to a Postgres problem accomplishes
nothing at all.

### Multi-repo fleets share one Postgres database

Cross-repo search only works when every repo is indexed into the **same** database, so a fleet
points every scanner, watcher and search at one shared Postgres instance:

```bash
export MAPROOM_DATABASE_URL="postgres://maproom:maproom@host.docker.internal:5433/maproom"
```

### Devcontainer trap: `localhost:5433` is not the fleet database

**This one destroys data silently and produces no error at all.** In a devcontainer the shared
Postgres container normally runs on the **host** docker daemon and must be reached at
`host.docker.internal`. Inside the container, `localhost:5433` may be a *different*, throwaway
Postgres — for example a tmpfs-backed instance used only by `cargo test` — whose data vanishes when
the container stops.

Pointing maproom at `localhost` indexes happily into that disposable database. Nothing errors. You
find out later, when searches come back empty and `maproom status` no longer lists repos you know
you scanned.

```bash
# Confirm the fleet database is reachable at the host address
pg_isready -h host.docker.internal -p 5433
```

### Postgres schema facts worth knowing before you debug

- `code_embeddings` holds **one row per `blob_sha`**, with a `UNIQUE` constraint on `blob_sha`. A
  blob that already has a row is skipped by incremental runs — this is the root of the model
  switching corruption described in
  [Switching Embedding Models Requires Deleting the Old Rows](#switching-embedding-models-requires-deleting-the-old-rows).
- Vectors live in **fixed per-dimension columns** — `embedding_768`, `embedding_1024` and
  `embedding_1536`, each with its own HNSW index. A model emitting any other dimension has nowhere
  to be stored.
- `code_embeddings` has **no foreign key to `chunks`**, so deleting chunks leaves orphan embedding
  rows behind. They are harmless, but they accumulate.

---

## Debugging Workflow

When a search command fails or produces unexpected results, follow this systematic workflow:

**0. Identify the storage backend** — every branch below depends on it
```bash
echo "$MAPROOM_DATABASE_URL"
# empty, or a path -> SQLite (~/.maproom/maproom.db); permissions and disk are in play
# postgres://...   -> shared Postgres; connectivity and timeouts are in play, not permissions
```
See [First: Which Storage Backend Are You On?](#first-which-storage-backend-are-you-on).

**1. Verify CLI installed**
```bash
command -v maproom
# Expected: /path/to/maproom
```

**2. Check CLI version**
```bash
maproom --version
# Expected: >= 0.1.0 (minimum version for this documentation)
```
Behavior differs between builds. The edge-case tables at the end of this document were measured on
CLI v0.1.0 against SQLite; the Postgres and embedding-pipeline material was measured on CLI 0.3.0
against Postgres 16 with pgvector. Provider and feature availability is **not** uniform across
builds — confirm anything load-bearing against your own binary with `maproom --help` rather than
trusting a list in any document.

**3. Verify database status**
```bash
maproom status
# Expected: List of indexed repositories
```

**4. Test basic search**
```bash
maproom search --repo <repo> --query "test" --format agent
# Expected: At least some results (if repo is indexed and non-empty)
```

**5. Enable debug mode** (score breakdown may not appear in CLI v0.1.0 — see [Unexpected Results or Scores](#unexpected-results-or-scores))
```bash
# Add --debug flag (intended to show scoring breakdown)
maproom search --repo <repo> --query "test" --format agent --debug
```

If all steps pass but your specific search still fails, check:
- Query syntax (special characters may need quoting)
- Filter values (case-sensitive: `func` not `Func`, `py` not `PY`)
- Repository name — `--repo` matches the **indexed** name (derived from the git origin) with suffix
  fuzzy-matching, not the directory name on disk; see
  [Silent Zero Hits from a Repo-Name Mismatch](#silent-zero-hits-from-a-repo-name-mismatch)

---

### Connection Pool Timeout or "Connection refused" (Postgres backend)

**Symptom:** maproom fails with a pool timeout. From maproom:

```
pool timed out while waiting for an open connection
```

and `psql` or `pg_isready` against the same URL reports:

```
Connection refused
```

**Root Cause:** On a Postgres setup this almost always means the **Postgres container is not
running**, or you are pointed at the wrong host. It is **not** a file-permissions problem. The
`chmod` recovery under [Permission Denied on Database (GAP-005)](#permission-denied-on-database-gap-005)
applies to the **SQLite backend only** — on Postgres there are no database files to `chmod` and
running those commands changes nothing.

The same pool timeout also appears **transiently** when something else is saturating the database's
CPU: a runaway `ANALYZE`, a heavy hand-written query, a large scan. Rule that out before concluding
the server is down.

**Fix:**
1. Is the server reachable at all?
   ```bash
   pg_isready -h host.docker.internal -p 5433
   ```
2. If the connection is refused, start the Postgres container **on the host docker daemon** (not
   inside the devcontainer), then retry.
3. If `pg_isready` succeeds but maproom still times out, the pool is being starved. Look for
   long-running statements before restarting anything:
   ```sql
   select pid, now() - query_start as runtime, state, left(query, 120)
   from pg_stat_activity
   where state <> 'idle'
   order by runtime desc;
   ```
   Wait for or cancel the offending statement, then retry.
4. Confirm you are pointed at the fleet database and not a throwaway one — see
   [Devcontainer trap: `localhost:5433` is not the fleet database](#devcontainer-trap-localhost5433-is-not-the-fleet-database).

**Prevention:** Keep the shared Postgres container on a restart policy such as `unless-stopped`, and
serialize heavy maintenance (full re-scans, `ANALYZE`, bulk embedding passes) so it does not overlap
with interactive searching.

### The Entire Watcher Fleet Disappeared

**Symptom:** `pm2 list` prints an empty table. Every per-repo maproom watcher is gone at once, yet
the pm2 God daemon is still alive and answering.

**Root Cause:** pm2 lost its in-memory process list. This is a pm2-level event, not a maproom one —
the watchers did not fail individually, the whole fleet vanished together.

**Fix:**
```bash
pm2 resurrect   # restores every watcher from ~/.pm2/dump.pm2
pm2 list        # confirm the fleet is back
```

**Prevention:** Run `pm2 save` after adding or changing watchers so `~/.pm2/dump.pm2` is current —
`pm2 resurrect` can only restore what was saved. Without knowing about `resurrect`, the obvious but
wrong recovery is to hand-rebuild N watchers one at a time, losing their original configuration.

### Scan Run Reports Success but One Repo Is Only Half Indexed

**Symptom:** A fleet-wide scan finishes and the aggregate run looks clean — every repo reports
success. Later, searches against one particular repo miss files you know exist.

**Root Cause:** Scanning a large repo on a slow mount (FUSE, virtiofs, a network filesystem) can
exceed a wrapping timeout **mid-scan**. That repo is left partially refreshed while every other repo
in the run succeeds, so the run-level summary hides the failure. Measured example: a 1,328-file docs
repo died at roughly 30% under a 1800s cap, and needed about 2,326s to finish when run unbounded.

**Fix:**
1. Re-scan the affected repo on its own, with no timeout wrapper (or a far larger one), and let it
   run to completion.
2. Confirm coverage afterwards by searching for a file or symbol you know sits late in the traversal.

**Prevention:** Budget scan timeouts against the *slowest* repo on the *slowest* mount, not the
average one. Treat any per-repo scan that ends at almost exactly your timeout value as a failure,
even when the surrounding job reports success.

### Silent Zero Hits from a Repo-Name Mismatch

**Symptom:** A search that should obviously match returns **zero results, with no error and exit
code 0**.

**Root Cause:** `--repo` matches the **indexed repo name** — derived from the git origin, not the
directory name on disk — with suffix fuzzy-matching. A directory named `django-olympics` whose
origin is `django/django` is indexed as `django/django`: `--repo django` finds it, while
`--repo django-olympics` returns zero hits and says nothing at all.

**Fix:**
```bash
# List the indexed names, then search using one of those
maproom status
maproom search --repo django --query "middleware" --format agent
```

**Prevention:** When a search comes back silently empty, suspect the repo name before you suspect
the index. A name that fuzzy-matches nothing can return an empty result set rather than
`Error: Repository not found`, so empty results are never proof that a repo is indexed and healthy.
See also [Zero Results with Valid Query](#zero-results-with-valid-query) for case-sensitive filter
values, which fail the same silent way.

### generate-embeddings Stalls Near the Finish Line

**Symptom:** Embedding generation ran fine for hours, then every pass began failing — and the closer
coverage gets to complete, the more reliably it dies:

```
Failed to fetch chunks ... canceling statement due to statement timeout
```

**Root Cause:** The pending-chunk query is a `NOT IN` subquery whose cost grows with the size of
`code_embeddings`, and maproom pins `statement_timeout` to **5000ms** on every connection (set in
`after_connect`; there is no environment override). The job therefore gets **slower as it succeeds**,
until the pending-chunk fetch alone exceeds 5 seconds.

Measured on ~195k chunks with ~113k rows already embedded: fetching **40,000** pending chunks blew
the 5s timeout and every pass died. Bounding the pass to **10,000** completed the same fetch in
about 0.73s.

**Fix:**
1. **Bound every pass** — on the order of 10,000 chunks — and loop until the pending count reaches
   zero. Run `maproom generate-embeddings --help` to see the flag that bounds a pass on your binary.
2. Run bounded passes in a loop rather than trying to finish in one shot. Each pass is independent;
   chunks that were not embedded simply stay pending for the next one.
3. Recognise the shape of the failure: it appears **late**, exactly when the job is closest to
   finishing. A pass that worked yesterday failing today is expected behavior at scale, not a
   regression, and not a reason to rebuild the index.

**Do not reproduce this by hand in `psql` and trust what you see.** maproom sets `work_mem` itself
(256MB) on its own connections, and this query is exquisitely sensitive to it: the same `NOT IN`
query planned at **cost 218,119,741** (Materialize plus a per-row Seq Scan) under a small `work_mem`
versus **101,635** (a hashed SubPlan) at 64MB and above — three orders of magnitude apart. A stock
`psql` session will show you a far worse problem than maproom actually has. If you must plan it by
hand, match the setting first:

```sql
set work_mem = '256MB';
-- then EXPLAIN (ANALYZE, BUFFERS) the pending-chunk query
```

**Prevention:** Treat bounded-pass-plus-loop as the normal way to run `generate-embeddings` on a
large index, not as a workaround reached for after the first failure.

### One Failing Sub-Batch Fails the Whole Batch

**Symptom:** An embedding pass reports a batch failure that names a *sub-batch*:

```
Sub-batch 2 failed: API error: Bad request: Batch of 50 texts rejected: {"error":"Post \"http://127.0.0.1:51950/tokenize\": EOF"}
```

**Root Cause:** Providers are called in sub-batches (Ollama default 50, concurrency 8). If **one**
sub-batch errors, maproom marks the **entire pipeline batch** failed — every chunk in that batch is
lost for the pass, not just the 50 in the failing sub-batch. The error above is the Ollama model
runner dropping the connection mid-request.

Blast radius scales with batch size: with `--batch-size 1000` each incident cost 1,000 chunks; at
500 it cost 500.

**Fix:**
1. Do nothing dramatic. These failures are **transient and self-heal on the next pass** — the lost
   chunks simply stay pending — so a loop of bounded passes converges on full coverage.
2. Lower `--batch-size` to limit the blast radius per incident, but keep it **above** the sub-batch
   size (default 50), or sub-batch parallelism never engages and the pass runs fully serialized.
3. Tune parallelism with the environment variables below, confirming they are honored by your build
   (`maproom --help` lists the environment variables your build supports):
   - `MAPROOM_EMBEDDING_PARALLEL_ENABLED`
   - `MAPROOM_EMBEDDING_PARALLEL_SUB_BATCH_SIZE` (default 50)
   - `MAPROOM_EMBEDDING_PARALLEL_MAX_CONCURRENCY` (default 8)

   Measured against a local Ollama, throughput improved as concurrency rose to ~8 and got **worse**
   at 16. Eight was the sweet spot.

**Prevention:** Pick a batch size comfortably above the sub-batch size but well below "the whole
job" — 500 against Ollama's default sub-batch of 50 is a good starting point — and always run
embedding generation as a loop rather than a single heroic pass.

### Token Limit Exceeded

**Symptom:** Embedding generation fails with an error containing:
```
Failed to generate code embeddings: Api(BadRequest("input token count is 20633 but the model supports up to 20000"))
```

**Root Cause:** The default embedding batch size groups too many chunks together, causing the total token count to exceed the Google embedding API limit of 20,000 tokens.

**Fix:**
1. Re-run embedding generation with a smaller batch size:
   ```bash
   maproom generate-embeddings --batch-size 25
   ```
2. Verify embeddings completed:
   ```bash
   maproom status
   ```

**Prevention:** Lower the batch size when generating embeddings against the Google API for
repositories with large files or code chunks. Mind the trade-off: a batch size at or below the
parallel sub-batch size (default 50) runs fully serialized — see
[One Failing Sub-Batch Fails the Whole Batch](#one-failing-sub-batch-fails-the-whole-batch).

**Note:** this limit is provider-specific — it is the Google embedding API rejecting an oversized
request, not maproom. Other providers fail differently: Ollama truncates oversized inputs instead of
rejecting them (a ~107KB chunk embedded fine in testing), and Cohere v3 models on Bedrock silently
truncate beyond 512 tokens. A provider-side rejection of a whole batch is also distinct from
[One Failing Sub-Batch Fails the Whole Batch](#one-failing-sub-batch-fails-the-whole-batch), where a
transient connection error loses the batch and self-heals on the next pass.

### Vector Search Returns No Results (Zero Embeddings)

**Symptom:** `maproom vector-search` completes without errors but returns an empty result set —
while `maproom search` keeps returning perfectly good results.

**Root Cause:** Embeddings have not been generated. **Zero embeddings never raises an error.** With
no embeddings at all, `maproom search` still returns results by falling back to full-text and
structural ranking; only vector search and semantic ranking are actually unavailable. Never infer
embedding coverage from "search works" — that is precisely the signal this failure mode fakes.

**Fix:**
1. Check coverage **explicitly**. `maproom status` reports it per repo, e.g. `Embeddings: 0 (0.0%)`:
   ```bash
   maproom status
   ```
   On Postgres, an empty `encoding_runs` table confirms no generation run has ever happened, and
   coverage can be measured per repo directly:
   ```sql
   select r.name, count(distinct c.blob_sha) blobs, count(distinct e.blob_sha) embedded
   from repos r join worktrees w on w.repo_id=r.id
   join chunk_worktrees cw on cw.worktree_id=w.id
   join chunks c on c.id=cw.chunk_id
   left join code_embeddings e on e.blob_sha=c.blob_sha group by 1 order by 2 desc;
   ```
2. Generate embeddings in **bounded passes, looped until the pending count reaches zero** — an
   unbounded pass dies at scale, see
   [generate-embeddings Stalls Near the Finish Line](#generate-embeddings-stalls-near-the-finish-line):
   ```bash
   maproom generate-embeddings --batch-size 500
   ```
   Run `maproom generate-embeddings --help` for the bounding and batching flags your binary exposes.
3. Re-run your vector search once coverage is non-zero.

**Prevention:** Check embedding coverage explicitly before your first vector search, and on a
schedule afterwards — coverage **decays as you work**, silently, see
[Watchers Do Not Maintain Embeddings](#watchers-do-not-maintain-embeddings).

### No Repositories Indexed

**Symptom:** `maproom status` shows no repositories, or search returns "no repositories indexed."

**Root Cause:** The repository has not been scanned. Maproom requires an initial scan to discover and index code chunks before any search works.

**Fix:**
1. Initialize the database (first time only):
   ```bash
   maproom db migrate
   ```
2. Scan the repository:
   ```bash
   maproom scan
   ```
3. Verify the scan succeeded:
   ```bash
   maproom status
   ```

**Prevention:** Follow the First-Time Setup workflow in SKILL.md whenever starting with a new repository.

### Stale Results After Code Changes

**Symptom:** Search results reference old, renamed, or deleted code that no longer exists in the repository.

**Root Cause:** The maproom index is out of date. Code changes are not automatically reflected until the repository is re-scanned.

**Fix:**
1. Re-scan the repository to pick up changes:
   ```bash
   maproom scan
   ```
2. If embeddings also need refreshing:
   ```bash
   maproom generate-embeddings
   ```

**Note — "Last scan" is not a freshness signal.** `maproom status` prints a per-worktree "Last
scan" timestamp that is **not** updated when an incremental scan finds the git tree SHA unchanged;
the scan logs `No changes detected (tree SHA match), skipping scan` and leaves the old timestamp in
place. A months-old "Last scan" therefore usually means "nothing has changed since then", **not**
"the index is stale". Judging staleness by this field leads to pointless full re-scans. To actually
test freshness, search for a symbol you know was added recently, or compare the repo's current HEAD
against what the index recorded.

**Note — re-scanning does not restore embeddings, it removes them.** The incremental processor
**deletes** embeddings for changed chunks and never regenerates them, so a re-scan improves chunk
freshness while *reducing* embedding coverage. Follow any significant re-scan with bounded
`generate-embeddings` passes. See
[Watchers Do Not Maintain Embeddings](#watchers-do-not-maintain-embeddings).

**Prevention:** Re-scan after significant code changes (branch switches, large merges, refactors) to keep the index current.

### Irrelevant Results

**Symptom:** Search returns results that don't match what you're looking for, or results seem unrelated to the query.

**Root Cause:** Either the wrong search type is being used (FTS vs. vector) or the query contains too many terms, diluting the search signal.

**Fix:**
1. Check whether you're using the right search type:
   - Know the exact words? Use `search` (FTS)
   - Know the concept but not the terms? Use `vector-search`
2. Reduce your query to 2-3 core technical terms. Remove filler words like "how", "what", "show me".
3. If using vector search, verify embeddings are available:
   ```bash
   maproom status
   ```

**Prevention:** Consult the Choosing Search Type section in SKILL.md to pick the right search mode. Review [search-best-practices.md](./search-best-practices.md) for query optimization techniques, especially anti-patterns 4 and 5.

### Zero Results with Valid Query

**Symptom:** Search returns empty results despite matching code existing in the repository.

**Root Cause:** Filter values passed to `--kind` or `--lang` use incorrect case. All filter values are case-sensitive — uppercase or mixed-case values silently match nothing.

**Incorrect examples:**
- `--kind Func` (should be `func`)
- `--kind Function` (should be `func`)
- `--lang PY` (should be `py`)

**Correct examples:**
- `--kind func` (lowercase)
- `--kind class` (lowercase)
- `--lang py` (lowercase extension)

**Fix:**
1. Check your `--kind` and `--lang` values for uppercase characters.
2. Replace with the exact lowercase values from the tables below:
   - **Kind values:** `func`, `class`, `method`, `heading_2`, `heading_3`, `code_block`, `markdown_section`, `json_key`
   - **Lang values:** `py`, `ts`, `rs`, `go`, `md`, `json`

**Prevention:** Use lowercase values for all filter flags. See the Filtering and Tuning section in [SKILL.md](../SKILL.md) for the complete valid value tables.

### Unexpected Results from Special Characters in Query

**Symptom:** Search fails, returns no results, or returns unexpected results when `--query` contains special characters such as `#`, `$`, `!`, or `|`. The command may also behave differently than expected when `--query` is passed an empty string (`""`).

**Root Cause:** Shell metacharacters in the query value are interpreted by the shell before reaching the CLI. For example:
- `#` starts an inline comment in zsh/bash — everything after it is silently dropped
- `$` triggers variable expansion — `$name` becomes the value of the `name` variable (often empty)
- `!` triggers history expansion in interactive shells — `!test` tries to expand the last command starting with "test"
- `|` creates a pipe — `auth|login` pipes the output of `maproom search ... auth` into a `login` command

An empty string query (`--query ""`) causes an FTS5 SQL syntax error (`Error: fts5: syntax error near ""`) and exits with code 1.

**Fix:**
1. Always wrap `--query` values in quotes. Double quotes protect against most metacharacters:
   ```bash
   # Correct - double quotes protect # and |
   maproom search --repo <repo> --query "function#handler" --format agent
   maproom search --repo <repo> --query "auth|login" --format agent
   ```
2. For queries containing `$` or `!`, use single quotes to prevent all shell expansion:
   ```bash
   # Correct - single quotes protect $ from variable expansion
   maproom search --repo <repo> --query '$variable_name' --format agent

   # Correct - single quotes protect ! from history expansion
   maproom search --repo <repo> --query '!important_function' --format agent
   ```
3. Alternatively, escape individual characters with a backslash inside double quotes:
   ```bash
   # Correct - backslash escapes $ inside double quotes
   maproom search --repo <repo> --query "\$variable_name" --format agent
   ```
4. Never pass an empty query. Empty strings cause an FTS5 SQL error (`fts5: syntax error near ""`):
   ```bash
   # Wrong - empty query causes SQL error (exit code 1)
   maproom search --repo <repo> --query "" --format agent

   # Correct - always provide at least one search term
   maproom search --repo <repo> --query "config" --format agent
   ```

**Common incorrect patterns:**
```bash
# Wrong - unquoted query; | creates a pipe
maproom search --repo <repo> --query auth|login --format agent

# Wrong - unquoted query; # starts a comment, everything after is dropped
maproom search --repo <repo> --query test#handler --format agent

# Wrong - double quotes with bare $; shell expands $name to empty string
maproom search --repo <repo> --query "$name_pattern" --format agent
```

**Prevention:** When constructing `--query` values programmatically, always wrap the value in single quotes to prevent all shell interpretation. If the query itself must contain single quotes, use double quotes with backslash escaping for `$` and `!`. Before executing a search, validate that the query string is non-empty.

### Unexpected Results or Scores

**Symptom:** Search returns results but they seem poorly ranked, irrelevant to the query intent, or the scores don't match expectations.

**Root Cause:** The default search output shows only final results without the underlying scoring details. Without visibility into how results are scored and ranked, it is difficult to determine whether the issue is query formulation, search type selection, or index staleness.

**Fix:**
1. Re-run your search with the `--debug` flag to see score breakdown details:
   ```bash
   maproom search --repo <repo> --query "your query" --format agent --debug
   ```
   **Note (CLI v0.1.0):** The `--debug` flag is advertised to show `base_fts`, `kind_multiplier`, `exact_match_multiplier`, and `final` breakdown fields, but as of v0.1.0 these fields do not appear in the output. The flag is accepted without error but produces output identical to non-debug mode. This is a known CLI issue. Until it is fixed, use the score interpretation guidance in the maproom-guide skill to understand relative scores.
2. Use the final score to identify the issue:
   - If scores are uniformly low, refine your query to use more specific terms
   - If irrelevant results score high, check whether a different search type (`search` vs. `vector-search`) is more appropriate
   - If expected results are missing entirely, verify the repository index is up to date with `maproom status`

**Prevention:** When investigating search quality issues, use the score interpretation tables in the maproom-guide skill to understand relative scores. Once the `--debug` CLI issue is resolved, the flag will provide objective scoring breakdowns. See also the [Debugging Workflow](#debugging-workflow) at the top of this document (Step 5) for the full systematic troubleshooting sequence.

---

## Common Error Messages

This section catalogs verbatim CLI error messages with their causes and recovery steps. Match the error text you see against the entries below.

### Repository Not Found

```
Error: Repository not found: <repo-name>
```

**Cause:** The `--repo` value does not match any repository name in the maproom database. The name may be misspelled, or the repository has not been scanned.

**Recovery:**
```bash
# List all indexed repositories and their names
maproom status

# If the repository is not listed, scan it
maproom scan
```

### Command Not Found

```
command not found: maproom
```

**Cause:** The `maproom` binary is not installed or is not on the shell `PATH`.

**Recovery:**
```bash
# Check if the binary exists anywhere
command -v maproom

# If not found, verify installation method (npm or cargo)
# The binary may also be available via the crewchief CLI alias:
command -v crewchief
```

### No Repositories Indexed

```
No repositories indexed (example)
```

**Cause:** The maproom database is empty. No repositories have been scanned, so there is nothing to search against. This error appears when running `search` or `vector-search` before any `scan` has been performed.

**Recovery:**
```bash
# Check current database state
maproom status

# Initialize the database if needed
maproom db migrate

# Scan the repository to populate the index
maproom scan

# Verify the scan succeeded
maproom status
```

See also the [No Repositories Indexed](#no-repositories-indexed) scenario earlier in this document for full root cause analysis and prevention steps.

### Missing Required Arguments

```
error: the following required arguments were not provided:
  --repo <REPO>
  --query <QUERY>

Usage: maproom search --repo <REPO> --query <QUERY>

For more information, try '--help'.
```

**Cause:** One or more required flags were omitted from the command. Both `--repo` and `--query` are required for `search` and `vector-search`.

**Recovery:**
```bash
# Include both required flags
maproom search --repo <repo-name> --query "<search terms>"

# Check help for the full flag list
maproom search --help
```

### Pool Timed Out While Waiting for an Open Connection

```
pool timed out while waiting for an open connection
```

**Cause:** Depends entirely on the backend. On **Postgres** the server is unreachable (container not
running, wrong host) or its connections are saturated by a long-running statement. On **SQLite** it
is the tail end of a permissions problem, after ~25 seconds of `unable to open database file`
retries.

**Recovery:** See
[Connection Pool Timeout or "Connection refused" (Postgres backend)](#connection-pool-timeout-or-connection-refused-postgres-backend)
for Postgres, or [Permission Denied on Database (GAP-005)](#permission-denied-on-database-gap-005)
for SQLite. Do not apply the SQLite `chmod` recovery to a Postgres deployment.

### Canceling Statement Due to Statement Timeout

```
Failed to fetch chunks ... canceling statement due to statement timeout
```

**Cause:** Postgres backend only. maproom pins `statement_timeout` to 5000ms per connection, and the
pending-chunk query for `generate-embeddings` grows more expensive as `code_embeddings` fills up.

**Recovery:** Bound each embedding pass and loop — see
[generate-embeddings Stalls Near the Finish Line](#generate-embeddings-stalls-near-the-finish-line).

### Error: "Reauthentication failed" (ADC expired, non-interactive)

```
Reauthentication failed. cannot prompt during non-interactive execution
```

**Cause:** Google Application Default Credentials have expired, and the embedding pass is running
somewhere it cannot prompt you to log in — cron, pm2, CI, a background loop. Every pass dies at
config time, before any chunk is embedded.

**Recovery:**
```bash
# Interactive sessions: refresh ADC
gcloud auth application-default login

# Unattended jobs: use a service-account key instead of user ADC
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
# (MAPROOM_GOOGLE_APPLICATION_CREDENTIALS is also honored)
```

A user-ADC refresh token that expires every few hours is the wrong credential for a scheduled
embedding job; move unattended work to a service account rather than re-running `gcloud auth` by
hand each morning.

### Error: "Failed to create token provider from ADC"

```
Error: Failed to create embedding service.

Caused by:
    0: Configuration error: Invalid configuration value for credentials:
       Failed to create token provider from ADC
```

**Cause:** Google Application Default Credentials (ADC) have expired. This is a **credential issue, not a code bug**. The `vector-search` subcommand requires valid credentials to call the embedding API (Google/Vertex when that is the configured provider). When ADC tokens expire, the CLI cannot authenticate with the embedding provider.

**Recovery:**
1. Refresh ADC credentials:
   ```bash
   gcloud auth application-default login --no-launch-browser
   gcloud auth application-default set-quota-project YOUR_PROJECT_ID
   ```
2. Verify credentials are valid:
   ```bash
   gcloud auth application-default print-access-token
   ```
3. Retry the vector-search command:
   ```bash
   maproom vector-search --repo <repo-name> --query "<search terms>" --format agent
   ```
4. If you cannot refresh credentials immediately, fall back to FTS search:
   ```bash
   maproom search --repo <repo-name> --query "<search terms>" --format agent
   ```

**Related Errors:**
- `Reauthentication failed. cannot prompt during non-interactive execution` is the same expiry seen
  from a non-interactive context (cron, pm2, CI). See
  [Error: "Reauthentication failed" (ADC expired, non-interactive)](#error-reauthentication-failed-adc-expired-non-interactive).
- `invalid_rapt` in error output also indicates expired ADC credentials; use the same resolution steps above.
- `quota_project_id is required` indicates the quota project is not configured; run `gcloud auth application-default set-quota-project YOUR_PROJECT_ID`.

**Security:** Do not share ADC credentials or access tokens. Do not commit credential files to git.

**Reference:** See [ADC Setup Guide](./adc-setup.md) for detailed setup and refresh instructions. See [Embedding Providers](./embedding-providers.md) for provider configuration details.

### Embedding Provider Misconfiguration

```
Error: Failed to create embedding service. Ensure OPENAI_API_KEY is set.
```

**Cause:** The CLI error message references `OPENAI_API_KEY`, but this may be misleading if you are using a different embedding provider (e.g., Vertex AI with ADC). The actual cause depends on which provider is configured:
- If using **Vertex AI** (default): ADC credentials are expired or not configured. See [Error: "Failed to create token provider from ADC"](#error-failed-to-create-token-provider-from-adc) above.
- If using **OpenAI**: The `OPENAI_API_KEY` environment variable is not set or is invalid.

**Recovery:**
1. Check which embedding provider is configured:
   ```bash
   echo "$MAPROOM_EMBEDDING_PROVIDER"
   ```
2. If the variable is unset, or set to the Google/Vertex provider (current builds accept
   `MAPROOM_EMBEDDING_PROVIDER=google`; older builds may use a different value — check
   `maproom --help`), this is an ADC credential issue. Follow the ADC recovery steps above.
3. If set to `openai`, set the API key:
   ```bash
   export OPENAI_API_KEY="<your-key>"
   ```
4. If you see `OPENAI_API_KEY` in the error but are not using OpenAI, the provider may be misconfigured. See [Embedding Providers](./embedding-providers.md) for correct configuration.

**Provider quick facts — confirm every one against your own binary, availability differs between
builds (`maproom --help`):**

- **`ollama`** (local, free). Endpoint from `OLLAMA_URL` (also `MAPROOM_OLLAMA_URL`). **In a
  devcontainer this must be `http://host.docker.internal:11434`** — `localhost:11434` is not the
  host's Ollama. Default model `mxbai-embed-large` is 1024-dimensional (fits `embedding_1024`);
  `nomic-embed-text` is 768. Oversized inputs are truncated rather than rejected.
- **`google`** (Vertex). Requires `GOOGLE_PROJECT_ID` (also `MAPROOM_GOOGLE_PROJECT_ID`) plus
  **Application Default Credentials — not an API key**. Setting `GEMINI_API_KEY` or `GOOGLE_API_KEY`
  does **nothing** for this provider; this is a common and confusing mistake, because the variables
  look plausible and the failure arrives as an authentication error rather than a configuration one.
- **`openai`**: `OPENAI_API_KEY` (also `MAPROOM_OPENAI_API_KEY`). Cohere direct uses
  `MAPROOM_COHERE_API_KEY`.
- **`bedrock`** (AWS): default model `amazon.titan-embed-text-v2:0` at 1024 dimensions with a
  **maximum batch of 1**, so throughput comes from concurrency rather than batch size (see
  [One Failing Sub-Batch Fails the Whole Batch](#one-failing-sub-batch-fails-the-whole-batch));
  `amazon.titan-embed-text-v1` is 1536-dimensional, also max batch 1; `cohere.embed-english-v3` and
  `cohere.embed-multilingual-v3` are 1024-dimensional with max batch 96 and **silently truncate**
  beyond 512 tokens. Credentials resolve through the standard AWS chain (static env keys, shared
  config/credentials files honoring `AWS_PROFILE`, web identity / IRSA, container credentials).
  **Bedrock support is not present in every maproom build** — verify with `maproom --help` and by
  checking whether `MAPROOM_EMBEDDING_PROVIDER=bedrock` is accepted before planning around it.
  Configuration details live in [Embedding Providers](./embedding-providers.md).

Whichever provider you pick, its output dimension must match a stored column — see
[Embedding Dimension Must Match a Stored Column](#embedding-dimension-must-match-a-stored-column).

**Reference:** See [Embedding Providers](./embedding-providers.md) for the full list of supported providers and their required environment variables.

### Network Timeout During Vector Search

**Scope — this and the two sections that follow assume a *remote* embedding provider.** They were
measured against OpenAI; the same shapes apply to any hosted provider (Google/Vertex, Bedrock,
Cohere) with that provider's endpoint and credentials substituted. A local `ollama` provider has no
internet dependency and no rate limit at all — in a devcontainer it is reached at
`http://host.docker.internal:11434`, and it fails in the ways described under
[One Failing Sub-Batch Fails the Whole Batch](#one-failing-sub-batch-fails-the-whole-batch).

**Symptom:** `maproom vector-search` hangs or times out during embedding generation. The command does not return results or an error within the expected time frame.

**Root Cause:** The OpenAI API is unreachable due to network connectivity issues. Vector search requires a live API call to generate query embeddings — unlike FTS search, it cannot operate offline.

**Fix:**
1. Check network connectivity to the OpenAI API:
   ```bash
   curl -sf https://api.openai.com/v1/models -H "Authorization: Bearer $OPENAI_API_KEY" > /dev/null && echo "API reachable" || echo "API unreachable"
   ```
2. Retry the vector-search command (max 3 retries with 2-4-8 second exponential backoff):
   ```bash
   # Retry after a short wait
   sleep 2
   maproom vector-search --repo <repo> --query "<terms>" --format agent
   ```
3. If retries fail, fall back to FTS search which requires no API connectivity:
   ```bash
   # FTS search works entirely offline against the local index
   maproom search --repo <repo> --query "<terms>" --format agent
   ```

**Prevention:** Before running vector-search, verify network connectivity is stable. If working in an environment with intermittent network access, prefer FTS search (`search`) over `vector-search` for reliability. See the Choosing Search Type section in [SKILL.md](../SKILL.md) for guidance on when each search type is appropriate.

### Rate Limit Exceeded

**Symptom:** `maproom vector-search` fails with a rate limit error, such as a 429 status code or a message indicating too many requests.

**Root Cause:** The OpenAI API is throttling requests because the rate limit has been exceeded. This can happen when running many vector searches in quick succession or when other applications share the same API key.

**Fix:**
1. Wait before retrying. Use exponential backoff (max 3 retries with 2-4-8 second delays):
   ```bash
   # Wait for the rate limit window to reset, then retry
   sleep 4
   maproom vector-search --repo <repo> --query "<terms>" --format agent
   ```
2. If immediate results are needed, fall back to FTS search which does not call the OpenAI API:
   ```bash
   # FTS search is not subject to OpenAI rate limits
   maproom search --repo <repo> --query "<terms>" --format agent
   ```
3. If rate limiting persists, check whether other processes are consuming the same API quota.

**Prevention:** Monitor API usage to avoid hitting rate limits. Space out vector-search calls when running multiple searches in sequence. For batch search workflows, prefer FTS search to avoid API dependency entirely.

### OpenAI API Degraded Performance

**Symptom:** `maproom vector-search` completes but takes significantly longer than normal (e.g., 10+ seconds instead of 1-2 seconds for query embedding generation).

**Root Cause:** The OpenAI API is experiencing degraded service. The API is reachable and responding, but response times are elevated beyond normal operating parameters.

**Fix:**
1. Switch to FTS search for faster results that do not depend on the API:
   ```bash
   # FTS search operates against the local index with no API latency
   maproom search --repo <repo> --query "<terms>" --format agent
   ```
2. Retry vector-search later when API performance has recovered (max 3 retries with 2-4-8 second backoff):
   ```bash
   # Check if performance has improved
   sleep 8
   maproom vector-search --repo <repo> --query "<terms>" --format agent
   ```
3. If degraded performance persists, use FTS search for the remainder of the session.

**Prevention:** Monitor the [OpenAI Status Page](https://status.openai.com/) for service degradation notices. When latency is elevated, switch proactively to FTS search rather than waiting for timeouts. See the [Debugging Workflow](#debugging-workflow) at the top of this document (Step 5) for enabling debug mode to measure response times.

### Invalid Flag Value

```
error: invalid value 'invalid' for '--format <FORMAT>'
  [possible values: json, agent]

For more information, try '--help'.
```

**Cause:** A flag was given a value outside its allowed set. The CLI validates enum-type flags (`--format`) and rejects unrecognized values.

**Recovery:**
```bash
# Check valid values for the flag in question
maproom search --help

# Use one of the accepted values
maproom search --repo <repo-name> --query "<terms>" --format agent
```

**Note on silent failures:** Some invalid values do not produce errors but return empty results. In particular, `--kind` and `--lang` accept any string without validation — an incorrect value like `--kind Func` (uppercase) silently matches nothing. See [Zero Results with Valid Query](#zero-results-with-valid-query) above for details.

---

## Known Limitations

This section documents known constraints and behaviors that are not bugs but may cause confusion.

### Expired ADC Credentials Cause "Failed to create embedding service"

Google Application Default Credentials (ADC) expire periodically and must be refreshed. When they expire, any `vector-search` or `generate-embeddings` command that uses Vertex AI will fail with:

```
Error: Failed to create embedding service.

Caused by:
    0: Configuration error: Invalid configuration value for credentials:
       Failed to create token provider from ADC
```

From a non-interactive context — cron, pm2, CI, an overnight embedding loop — the same expiry
surfaces as:

```
Reauthentication failed. cannot prompt during non-interactive execution
```

This is **not a code bug**. It is a credential expiry issue. Refresh credentials with:
```bash
gcloud auth application-default login --no-launch-browser
gcloud auth application-default set-quota-project YOUR_PROJECT_ID
```

For unattended jobs, prefer a service-account key over user ADC:
`GOOGLE_APPLICATION_CREDENTIALS` (also `MAPROOM_GOOGLE_APPLICATION_CREDENTIALS`).

See [ADC Setup Guide](./adc-setup.md) for detailed instructions.

### text-embedding-004 Is Not Available via Gemini REST API

The `text-embedding-004` model used by maproom for embeddings is only available through the **Vertex AI API**, not through the Gemini REST API. Attempting to use the Gemini REST API endpoint for embeddings will fail. This means:
- ADC credentials (Google Cloud authentication) are required whenever the Google/Vertex provider is
  configured.
- The `GOOGLE_API_KEY` environment variable (used for Gemini REST API) is **not sufficient** for embedding generation.
- For this model specifically, use the Vertex AI provider with ADC. It is not the only embedding
  provider available — `ollama` (local), `openai`, `bedrock` and Cohere are separate options with
  their own models and credentials; see the provider quick facts under
  [Embedding Provider Misconfiguration](#embedding-provider-misconfiguration), and confirm what your
  build accepts with `maproom --help`.

See [Embedding Providers](./embedding-providers.md) for supported providers and configuration.

### Cross-Provider Re-indexing Required When Switching Providers

Embeddings generated by one provider (e.g., Vertex AI with `text-embedding-004`) are **not compatible** with embeddings from another provider (e.g., OpenAI with `text-embedding-ada-002`). If you switch embedding providers, you must regenerate all embeddings — on a large index as bounded
passes looped until the pending count reaches zero, not one unbounded run (see
[generate-embeddings Stalls Near the Finish Line](#generate-embeddings-stalls-near-the-finish-line)):

```bash
maproom generate-embeddings --batch-size 500
```

Failure to re-index after switching providers will cause vector-search to return poor or zero results, because the query embedding (from the new provider) will be compared against stored embeddings (from the old provider) that exist in a different vector space.

**On the Postgres backend, re-running `generate-embeddings` is not sufficient** — the old rows must
be deleted first. See the next entry.

See [Embedding Providers](./embedding-providers.md) for details on provider switching.

### Switching Embedding Models Requires Deleting the Old Rows

`code_embeddings` is `UNIQUE` on `blob_sha`, so a blob that was already embedded at the old
dimension **keeps its row**. Incremental runs see that a row exists and skip the blob, while vector
search at the new dimension cannot see it. Switching model or provider without deleting the rows at
the old dimension **silently corrupts coverage** — no error, no warning, just a growing set of
chunks that are quietly unreachable by vector search.

Verify homogeneity before and after any model change:

```sql
select embedding_dim, model_version, count(*) from code_embeddings group by 1,2;
```

More than one `(embedding_dim, model_version)` pair means the index is mixed. Delete the rows at the
old dimension/model, then run bounded `generate-embeddings` passes until the pending count reaches
zero.

Related housekeeping: `code_embeddings` has no foreign key to `chunks`, so deleting chunks leaves
orphan embedding rows behind. They are harmless, but they accumulate and they inflate the `NOT IN`
subquery described in
[generate-embeddings Stalls Near the Finish Line](#generate-embeddings-stalls-near-the-finish-line).

### Embedding Dimension Must Match a Stored Column

Only **768, 1024 and 1536** have columns (`embedding_768`, `embedding_1024`, `embedding_1536`) and
HNSW indexes. A model emitting any other dimension **cannot be stored at all** — for example Ollama's
`qwen3-embedding:4b` at 2560 dimensions. Model choice is constrained by the schema, not by taste.

Where a model offers configurable output sizes, the same constraint applies: Titan v2 can emit 256-
and 512-dimensional vectors, but with no column set for those sizes they are rejected by a dimension
validation step rather than failing after a full scan.

### Watchers Do Not Maintain Embeddings

A per-repo watcher keeps **chunks** fresh. It does **not** keep embeddings fresh: the incremental
processor **deletes** embeddings for changed chunks and never regenerates them. Embedding coverage
therefore **decays continuously as you work** — silently, because search keeps returning results the
whole time by falling back to full-text ranking (see
[Vector Search Returns No Results (Zero Embeddings)](#vector-search-returns-no-results-zero-embeddings)).

Holding coverage requires a **periodic `maproom generate-embeddings` job** — cron, a process-manager
schedule, or an equivalent — running bounded passes in a loop. Documentation elsewhere claiming
"watch keeps the index fresh" is true for chunks and **false for embeddings**.

---

## Edge Case Handling

This section documents boundary conditions, resource errors, and concurrency scenarios tested against `maproom` version 0.1.0. Each entry records empirical CLI behavior observed during testing.

**Backend scope:** these were measured against the **SQLite backend**, and the storage-related
entries (GAP-004, GAP-005, GAP-006) describe SQLite failure modes only. On the Postgres backend
there is no local database file, so file permissions, WAL files and `~/.maproom/` disk usage are not
in play at all — see
[First: Which Storage Backend Are You On?](#first-which-storage-backend-are-you-on) and
[Connection Pool Timeout or "Connection refused" (Postgres backend)](#connection-pool-timeout-or-connection-refused-postgres-backend).
The flag-behavior entries (GAP-001, GAP-002, GAP-003, GAP-007) are backend-independent, but were
measured on v0.1.0 — check your own binary with `maproom search --help` before relying on the exact
values below.

### SQLite Lock Contention (GAP-006) -- HIGH PRIORITY

**Applies to: SQLite backend only.** Postgres handles concurrent readers and writers with MVCC and
does not produce `SQLITE_BUSY`; a pool timeout there means something else entirely (see
[Connection Pool Timeout or "Connection refused" (Postgres backend)](#connection-pool-timeout-or-connection-refused-postgres-backend)).
A shared Postgres fleet is in fact the standard way to run many concurrent watchers and searches.

**Symptom:** When multiple agents or processes run `maproom search` or `maproom scan` concurrently against the same repository, commands may fail with SQLite lock errors such as `SQLITE_BUSY` or connection pool timeouts.

**Root Cause:** The maproom database uses SQLite, which has limited write concurrency. Concurrent read-only operations (searches) are handled well by SQLite's WAL mode. However, concurrent write operations (scan while searching) or access to a locked database can cause contention.

**Observed behavior (tested 2026-02-13, CLI v0.1.0):**
- **10 concurrent searches:** All 10 processes completed successfully (exit code 0, no stderr). SQLite WAL mode handles concurrent reads without contention.
- **Scan + 5 concurrent searches:** All 6 processes (1 scan + 5 searches) completed successfully (exit code 0, no stderr). The CLI handles mixed read/write concurrency gracefully at this scale.
- **No `SQLITE_BUSY` errors observed** in any concurrent test scenario with up to 10 simultaneous processes.

**Fix:**
1. If you encounter a `SQLITE_BUSY` or connection pool timeout error during concurrent operations, retry the failed command after a short delay:
   ```bash
   sleep 2
   maproom search --repo <repo> --query "<terms>" --format agent
   ```
2. Avoid running multiple `scan` commands against the same repository simultaneously. Concurrent reads (searches) are safe.
3. If contention persists, serialize write operations (scan, generate-embeddings) and allow only read operations (search, vector-search) to run concurrently.

**Prevention:** Do not launch multiple `scan` or `generate-embeddings` commands for the same repository in parallel. Concurrent `search` commands are safe at typical agent workloads (tested up to 10 simultaneous processes). If running batch search workflows with very high concurrency, add a small delay between launches.

### Invalid `--k` Values (GAP-001)

**Symptom:** The `--k` flag accepts boundary values that produce unexpected results: zero returns no output silently, negative values with space syntax cause a parse error, and negative values with equals syntax silently return all matching results.

**Root Cause:** The CLI parses `--k` as a numeric type without validating the semantic range. Different syntax patterns produce different behaviors:

**Observed behavior (tested 2026-02-13, CLI v0.1.0):**

| Input | Behavior | Exit Code | Output |
|-------|----------|-----------|--------|
| `--k 0` | Silent success, no results | 0 | Empty stdout, no stderr |
| `--k -1` (space) | Parse error: `unexpected argument '-1' found` | 2 | Usage hint on stderr |
| `--k=-1` (equals) | Silent success, returns **all** matching results (910 for "test" query) | 0 | All matching chunks |
| `--k=-2` (equals) | Same as `--k=-1` — returns all matching results | 0 | All matching chunks |
| `--k 10000` | Success, returns all matching results (910, capped by index size) | 0 | All matching chunks |
| `--k 1` | Success, returns exactly 1 result | 0 | 1 result |

**Fix:**
1. Always use positive integer values for `--k`. The default is 10 if omitted.
2. If you accidentally pass `--k 0` and get no results, the command succeeded but returned nothing — increase `--k` to a positive value.
3. Do not rely on `--k=-1` to mean "return all results" — while it works in practice (due to unsigned integer wrapping), this is undocumented behavior. Use a large explicit value like `--k 10000` instead.
   ```bash
   # Correct - explicit positive value
   maproom search --repo <repo> --query "<terms>" --k 20 --format agent

   # Avoid - undocumented wrapping behavior
   maproom search --repo <repo> --query "<terms>" --k=-1 --format agent
   ```

**Prevention:** Validate that `--k` is a positive integer (>= 1) before executing search commands. The practical upper bound is the total number of indexed chunks (check with `maproom status`). Values above the chunk count simply return all results.

### Invalid `--threshold` Values (GAP-002)

**Symptom:** The `--threshold` flag (available only on `vector-search`, not `search`) rejects negative values with a parse error, while values above 1.0 are accepted syntactically but may produce no results.

**Root Cause:** The `--threshold` flag is exclusive to the `vector-search` subcommand. Passing `--threshold` to `search` produces an "unexpected argument" error. Negative values with space syntax trigger a parse error because the shell interprets `-0` as a separate flag.

**Observed behavior (tested 2026-02-13, CLI v0.1.0):**

| Input | Subcommand | Behavior | Exit Code |
|-------|------------|----------|-----------|
| `--threshold -0.5` (space) | `search` | `error: unexpected argument '--threshold' found` | 2 |
| `--threshold 1.5` | `search` | `error: unexpected argument '--threshold' found` | 2 |
| `--threshold -0.5` (space) | `vector-search` | `error: unexpected argument '-0' found` | 2 |
| `--threshold=-0.5` (equals) | `vector-search` | Accepted by parser (fails at API key check before validation) | 1 |
| `--threshold=1.5` (equals) | `vector-search` | Accepted by parser (fails at API key check before validation) | 1 |

**Note:** Full threshold range validation could not be tested empirically because `vector-search` needs working credentials for the configured embedding provider (`OPENAI_API_KEY` in that test environment), which were not available. The parser accepts the values, but runtime behavior with actual embeddings is untested.

**Fix:**
1. Only use `--threshold` with the `vector-search` subcommand, never with `search`:
   ```bash
   # Correct - threshold with vector-search
   maproom vector-search --repo <repo> --query "<terms>" --threshold 0.7 --format agent

   # Wrong - threshold is not a search flag
   maproom search --repo <repo> --query "<terms>" --threshold 0.7 --format agent
   ```
2. Use values in the documented range of 0.0 to 1.0 (cosine similarity score).
3. When passing negative values, use equals syntax (`--threshold=-0.5`) to avoid shell parse ambiguity — though negative thresholds are semantically meaningless for cosine similarity.

**Prevention:** Only pass `--threshold` to `vector-search`. Keep values between 0.0 and 1.0. A threshold of 0.0 returns all results (no filtering); a threshold of 1.0 requires exact matches only.

### Invalid `--preview-length` Values (GAP-003)

**Symptom:** The `--preview-length` flag rejects negative values but accepts zero, which produces results with truncated previews showing only an ellipsis (`...`).

**Root Cause:** The CLI parses `--preview-length` as an unsigned integer. Negative values are rejected at the parser level. Zero is accepted but produces minimal output (just the `...` truncation marker).

**Observed behavior (tested 2026-02-13, CLI v0.1.0):**

| Input | Behavior | Exit Code | Output |
|-------|----------|-----------|--------|
| `--preview-length 0` | Success, previews show only `...` | 0 | Results with truncated previews |
| `--preview-length -100` (space) | `error: unexpected argument '-1' found` | 2 | Parse error on stderr |
| `--preview-length -1` (space) | `error: unexpected argument '-1' found` | 2 | Parse error on stderr |
| `--preview-length=-100` (equals) | `error: invalid value '-100' for '--preview-length <PREVIEW_LENGTH>': invalid digit found in string` | 2 | Validation error on stderr |
| `--preview-length=-1` (equals) | `error: invalid value '-1' for '--preview-length <PREVIEW_LENGTH>': invalid digit found in string` | 2 | Validation error on stderr |
| `--preview-length 1` | Success, previews show 1 character + `...` | 0 | Single-char previews |
| `--preview-length 99999` | Success, full content shown (no truncation) | 0 | Full chunk content |

**Fix:**
1. Use a positive integer for `--preview-length`. The default is 200 for JSON format or 120 for agent format.
2. If previews appear as only `...`, check that `--preview-length` is not set to 0.
   ```bash
   # Correct - reasonable preview length
   maproom search --repo <repo> --query "<terms>" --preview-length 150 --format agent

   # Avoid - zero produces empty previews
   maproom search --repo <repo> --query "<terms>" --preview-length 0 --format agent
   ```

**Prevention:** Use positive values for `--preview-length`. Omit the flag to use the format-appropriate default (120 for `--format agent`, 200 for `--format json`). Very large values are safe but produce verbose output.

### Disk Full During Scan (GAP-004)

**Applies to: SQLite backend only.** On Postgres, disk exhaustion is a property of the database
server's host and volume, not of `~/.maproom/`; the recovery below (deleting `maproom.db*` and
re-migrating) has no Postgres equivalent and must not be attempted there.

**Note:** This edge case has not been tested empirically due to the risk of destabilizing the shared development environment. Simulating disk-full conditions requires filling the filesystem, which could affect other processes and services.

**Symptom (predicted):** `maproom scan` fails mid-operation when the filesystem runs out of space. The SQLite database may be left in an inconsistent state if the write-ahead log (WAL) cannot be flushed.

**Root Cause (predicted):** SQLite requires disk space to maintain the WAL file (`maproom.db-wal`) and shared memory file (`maproom.db-shm`) alongside the main database. During `scan`, the CLI writes new chunks to the database. If disk space is exhausted, SQLite write operations fail.

**Expected error pattern:**
```
Error: disk I/O error
```
or
```
Error: database or disk is full
```

**Fix:**
1. Free disk space and re-run the scan:
   ```bash
   # Check available disk space
   df -h ~/.maproom/

   # Free space, then re-scan
   maproom scan
   ```
2. If the database is corrupted after a disk-full event, delete and rebuild:
   ```bash
   rm ~/.maproom/<repo>/maproom.db*
   maproom db migrate
   maproom scan
   ```

**Prevention:** Ensure at least 2x the expected database size is available before running `scan` or `generate-embeddings`. Check the current database size with `ls -lh ~/.maproom/<repo>/maproom.db*`. For reference, a repository with 6,450 chunks produces a ~67 MB database with a ~40 MB WAL file.

### Permission Denied on Database (GAP-005)

**Applies to: SQLite backend only.** This is the entry most often misapplied. On the Postgres
backend there is no database file to `chmod`, and an identical-looking connection pool timeout means
the server is unreachable or saturated — see
[Connection Pool Timeout or "Connection refused" (Postgres backend)](#connection-pool-timeout-or-connection-refused-postgres-backend).
Distinguish them by the accompanying log lines: repeated `unable to open database file` before the
timeout means SQLite permissions; `Connection refused` from `psql` or `pg_isready` means Postgres.

**Symptom:** Search or scan commands fail with repeated `ERROR unable to open database file` messages followed by a connection pool timeout. The CLI retries with exponential backoff for approximately 25 seconds before giving up.

**Root Cause:** The maproom database file (`~/.maproom/<repo>/maproom.db`) or its directory has insufficient filesystem permissions. SQLite requires read access for searches and write access for scans. SQLite also needs access to the WAL file (`maproom.db-wal`) and shared memory file (`maproom.db-shm`) in the same directory.

**Observed behavior (tested 2026-02-13, CLI v0.1.0):**

| Scenario | Behavior | Exit Code |
|----------|----------|-----------|
| Read-only database file (`chmod 444`) + `search` | **Success** — SQLite can read from read-only files | 0 |
| Read-only database file (`chmod 444`) + `scan` | `Error: attempt to write a readonly database` (Error code 8) | 1 |
| No permissions on directory (`chmod 000`) + `search` | Repeated `ERROR unable to open database file` with exponential backoff (~25 sec), then `Error: Failed to create SQLite connection pool` / `timed out waiting for connection` | 1 |
| No permissions on WAL file (`chmod 000`) + `search` | Same connection pool timeout as directory denial (~25 sec retry loop) | 1 |

**Verbatim error for scan with read-only database:**
```
Error: scan failed for <worktree>

Caused by:
    0: attempt to write a readonly database
    1: Error code 8: Attempt to write a readonly database
```

**Verbatim error for directory/WAL permission denial:**
```
ERROR unable to open database file: /home/<user>/.maproom/<repo>/maproom.db
...
Error: Failed to create SQLite connection pool

Caused by:
    timed out waiting for connection: unable to open database file: /home/<user>/.maproom/<repo>/maproom.db
```

**Fix:**
1. Restore correct permissions on the database files:
   ```bash
   chmod 644 ~/.maproom/<repo>/maproom.db
   chmod 644 ~/.maproom/<repo>/maproom.db-wal
   chmod 644 ~/.maproom/<repo>/maproom.db-shm
   chmod 755 ~/.maproom/<repo>/
   ```
2. Verify the fix:
   ```bash
   maproom search --repo <repo> --query "test" --format agent --k 1
   ```

**Prevention:** Do not modify permissions on the `~/.maproom/` directory or its contents. If running in a container or restricted environment, ensure the database directory is writable by the user running `maproom`. The CLI will retry database connections with exponential backoff for approximately 25 seconds before timing out — a long-running `ERROR unable to open database file` log stream is the primary symptom of permission issues.

### Large `--k` Values and Memory (GAP-007)

**Symptom:** Passing very large `--k` values returns all matching results without error but may produce large output volumes and longer execution times.

**Root Cause:** The CLI does not impose an upper limit on `--k` beyond the integer parsing boundary. Values exceeding the total number of matching chunks simply return all matches. The CLI parses `--k` as a signed 64-bit integer, so the maximum accepted value is 9,223,372,036,854,775,807 (i64 max). Values at or above u64 max (18,446,744,073,709,551,615) are rejected with a parse error.

**Observed behavior (tested 2026-02-13, CLI v0.1.0):**

| Input | Results | Duration | Exit Code |
|-------|---------|----------|-----------|
| `--k 10` (default) | 10 | <1 sec | 0 |
| `--k 10000` | 910 (all matches for "test") | <1 sec | 0 |
| `--k 999999` | 3,499 (all matches for "the"), ~750 KB output | ~25 sec | 0 |
| `--k 9999999` | 3,499 (same, capped by index) | ~25 sec | 0 |
| `--k 9223372036854775807` (i64 max) | All matches | varies | 0 |
| `--k 18446744073709551615` (u64 max) | `error: invalid value: number too large to fit in target type` | n/a | 2 |

**Fix:**
1. Use reasonable `--k` values. For most search workflows, `--k 10` to `--k 50` is sufficient.
2. If you need all results, use `--k 10000` rather than extreme values — this avoids unnecessary processing time.
3. If the CLI rejects a value with "number too large to fit in target type", reduce `--k` to a value within the i64 range.
   ```bash
   # Correct - practical upper bound
   maproom search --repo <repo> --query "<terms>" --k 100 --format agent

   # Avoid - unnecessarily large, slower execution
   maproom search --repo <repo> --query "<terms>" --k 999999 --format agent
   ```

**Prevention:** Keep `--k` values proportional to the expected result set size. Check `maproom status` to see total chunk counts per repository. For a repository with 6,450 chunks, `--k 100` covers the top 1.5% of results. Very large `--k` values (999,999+) cause longer execution times (~25 seconds vs. <1 second) and produce large output volumes (~750 KB) without improving result quality, since all additional results are lower-relevance matches.
