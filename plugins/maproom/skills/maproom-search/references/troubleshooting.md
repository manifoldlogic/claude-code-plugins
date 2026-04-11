# Maproom Troubleshooting

Detailed error recovery for common maproom issues, including edge case handling for boundary conditions and concurrency scenarios. This is a companion to the quick-reference troubleshooting section in [SKILL.md](../SKILL.md) — start there for quick fixes, and use this file when you need root cause analysis or step-by-step recovery.

## Debugging Workflow

When a search command fails or produces unexpected results, follow this systematic workflow:

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
- Repository name (must match indexed name exactly)

---

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

**Prevention:** Use `--batch-size 25` when generating embeddings for repositories with large files or code chunks.

### Vector Search Returns No Results

**Symptom:** `maproom vector-search` completes without errors but returns an empty result set.

**Root Cause:** Embeddings have not been generated for the repository. Vector search requires pre-computed embeddings; without them, there is nothing to match against.

**Fix:**
1. Check embedding status:
   ```bash
   maproom status
   ```
2. If embeddings are missing, generate them:
   ```bash
   maproom generate-embeddings
   ```
3. Re-run your vector search after embeddings complete.

**Prevention:** Always run `maproom status` before your first vector search to confirm embeddings are available.

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

**Prevention:** When investigating search quality issues, always start with `--debug` to get objective scoring data before adjusting queries or filters. See also the [Debugging Workflow](#debugging-workflow) at the top of this document (Step 5) for the full systematic troubleshooting sequence.

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

### Error: "Failed to create token provider from ADC"

```
Error: Failed to create embedding service.

Caused by:
    0: Configuration error: Invalid configuration value for credentials:
       Failed to create token provider from ADC
```

**Cause:** Google Application Default Credentials (ADC) have expired. This is a **credential issue, not a code bug**. The `vector-search` subcommand requires valid credentials to call the embedding API (Vertex AI by default). When ADC tokens expire, the CLI cannot authenticate with the embedding provider.

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
2. If the variable is unset or set to `vertex-ai`, this is an ADC credential issue. Follow the ADC recovery steps above.
3. If set to `openai`, set the API key:
   ```bash
   export OPENAI_API_KEY="<your-key>"
   ```
4. If you see `OPENAI_API_KEY` in the error but are not using OpenAI, the provider may be misconfigured. See [Embedding Providers](./embedding-providers.md) for correct configuration.

**Reference:** See [Embedding Providers](./embedding-providers.md) for the full list of supported providers and their required environment variables.

### Network Timeout During Vector Search

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

This is **not a code bug**. It is a credential expiry issue. Refresh credentials with:
```bash
gcloud auth application-default login --no-launch-browser
gcloud auth application-default set-quota-project YOUR_PROJECT_ID
```

See [ADC Setup Guide](./adc-setup.md) for detailed instructions.

### text-embedding-004 Is Not Available via Gemini REST API

The `text-embedding-004` model used by maproom for embeddings is only available through the **Vertex AI API**, not through the Gemini REST API. Attempting to use the Gemini REST API endpoint for embeddings will fail. This means:
- ADC credentials (Google Cloud authentication) are required for the default embedding provider.
- The `GOOGLE_API_KEY` environment variable (used for Gemini REST API) is **not sufficient** for embedding generation.
- You must use either the Vertex AI provider (with ADC) or the OpenAI provider (with `OPENAI_API_KEY`).

See [Embedding Providers](./embedding-providers.md) for supported providers and configuration.

### Cross-Provider Re-indexing Required When Switching Providers

Embeddings generated by one provider (e.g., Vertex AI with `text-embedding-004`) are **not compatible** with embeddings from another provider (e.g., OpenAI with `text-embedding-ada-002`). If you switch embedding providers, you must regenerate all embeddings:

```bash
maproom generate-embeddings
```

Failure to re-index after switching providers will cause vector-search to return poor or zero results, because the query embedding (from the new provider) will be compared against stored embeddings (from the old provider) that exist in a different vector space.

See [Embedding Providers](./embedding-providers.md) for details on provider switching.

---

## Edge Case Handling

This section documents boundary conditions, resource errors, and concurrency scenarios tested against `maproom` version 0.1.0. Each entry records empirical CLI behavior observed during testing.

### SQLite Lock Contention (GAP-006) -- HIGH PRIORITY

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

**Note:** Full threshold range validation could not be tested empirically because `vector-search` requires `OPENAI_API_KEY` which was not available in the test environment. The parser accepts the values, but runtime behavior with actual embeddings is untested.

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
