# Maproom Troubleshooting

Detailed error recovery for the five most common maproom issues. This is a companion to the quick-reference troubleshooting section in [SKILL.md](../SKILL.md) — start there for quick fixes, and use this file when you need root cause analysis or step-by-step recovery.

### Token Limit Exceeded

**Symptom:** Embedding generation fails with an error containing:
```
Failed to generate code embeddings: Api(BadRequest("input token count is 20633 but the model supports up to 20000"))
```

**Root Cause:** The default embedding batch size groups too many chunks together, causing the total token count to exceed the Google embedding API limit of 20,000 tokens.

**Fix:**
1. Re-run embedding generation with a smaller batch size:
   ```bash
   crewchief-maproom generate-embeddings --batch-size 25
   ```
2. Verify embeddings completed:
   ```bash
   crewchief-maproom status
   ```

**Prevention:** Use `--batch-size 25` when generating embeddings for repositories with large files or code chunks.

### Vector Search Returns No Results

**Symptom:** `crewchief-maproom vector-search` completes without errors but returns an empty result set.

**Root Cause:** Embeddings have not been generated for the repository. Vector search requires pre-computed embeddings; without them, there is nothing to match against.

**Fix:**
1. Check embedding status:
   ```bash
   crewchief-maproom status
   ```
2. If embeddings are missing, generate them:
   ```bash
   crewchief-maproom generate-embeddings
   ```
3. Re-run your vector search after embeddings complete.

**Prevention:** Always run `crewchief-maproom status` before your first vector search to confirm embeddings are available.

### No Repositories Indexed

**Symptom:** `crewchief-maproom status` shows no repositories, or search returns "no repositories indexed."

**Root Cause:** The repository has not been scanned. Maproom requires an initial scan to discover and index code chunks before any search works.

**Fix:**
1. Initialize the database (first time only):
   ```bash
   crewchief-maproom db migrate
   ```
2. Scan the repository:
   ```bash
   crewchief-maproom scan
   ```
3. Verify the scan succeeded:
   ```bash
   crewchief-maproom status
   ```

**Prevention:** Follow the First-Time Setup workflow in SKILL.md whenever starting with a new repository.

### Stale Results After Code Changes

**Symptom:** Search results reference old, renamed, or deleted code that no longer exists in the repository.

**Root Cause:** The maproom index is out of date. Code changes are not automatically reflected until the repository is re-scanned.

**Fix:**
1. Re-scan the repository to pick up changes:
   ```bash
   crewchief-maproom scan
   ```
2. If embeddings also need refreshing:
   ```bash
   crewchief-maproom generate-embeddings
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
   crewchief-maproom status
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
