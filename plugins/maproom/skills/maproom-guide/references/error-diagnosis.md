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
| **Infrastructure** | Disk full, permissions, SQLite lock | Yes — fix environment | Permission denied, database locked |

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

Maproom's vector search and embedding generation call external APIs (Google Vertex AI by default, or OpenAI). These APIs require authentication tokens that expire periodically as a security measure.

- **Google ADC tokens** expire after ~1 hour and are automatically refreshed — but the refresh token itself can expire after extended periods of inactivity
- **OpenAI API keys** don't expire by time, but can be revoked or rate-limited

### How to Recognize Credential Errors

Credential errors contain one of these patterns in the error message:
- "Failed to create embedding service" (top-level error for all credential failures)
- "Failed to create token provider from ADC" (appears in the `Caused by` chain)
- "No Google credentials found" (appears in the `Caused by` chain)
- "invalid_rapt"
- "quota_project_id is required"
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
2. **Fall back to FTS** — `maproom search` works entirely locally, no credentials needed
3. **Refresh credentials** when convenient — see [ADC setup guide](../../maproom-search/references/adc-setup.md)

---

## Index Freshness Explained

### What "Stale Index" Means

Maproom maintains a local SQLite database containing indexed "chunks" of your codebase. This index is a **snapshot** — it reflects the code as it was when you last ran `maproom scan`. Code changes after the scan are invisible to maproom until the next scan.

### When Does the Index Become Stale?

| Event | Index Impact | Action Needed |
|---|---|---|
| Editing a few files | Slightly stale — minor risk | Optional re-scan |
| Switching branches | Potentially very stale | Re-scan recommended |
| Large merge or rebase | Likely stale | Re-scan recommended |
| Major refactor (renames, moves) | Definitely stale | Re-scan required |
| No code changes | Fresh | No action |

### Scanning vs Embedding Generation

These are two distinct operations:
- **Scan** (`maproom scan`) — parses code with tree-sitter, extracts chunks, stores in SQLite. Fast (~2 seconds for small repos). Required for FTS search.
- **Embedding generation** (`maproom generate-embeddings`) — creates vector representations of each chunk via API. Slower (minutes for large repos). Required for vector search. Check progress with `maproom encoding-progress`.

After a scan, FTS search works immediately. Vector search requires embeddings to also be up to date. Use `maproom encoding-progress` to monitor embedding generation completion percentage.

### The Watch Alternative

`maproom watch` auto-indexes on file changes, keeping the index fresh without manual re-scanning. Useful during active development.

---

## Search Quality Explained

### "No Results" Is Not Always an Error

Zero results can mean:
1. **The code genuinely doesn't exist** — a valid outcome, not a failure
2. **Wrong search type** — using FTS for a concept that needs vector search, or vice versa
3. **Filters too restrictive** — `--kind` or `--lang` excluding valid matches
4. **Query too specific** — too many terms diluting the search signal

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
3. Both return nothing? → Verify repo is indexed, check filters, consider Grep fallback

---

## Error Escalation Guide

### User-Actionable Errors

These errors have clear remediation steps the user can take:
- Credential expiry → refresh ADC or set API key
- Missing index → run `maproom scan`
- Missing embeddings → run `maproom generate-embeddings`
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
