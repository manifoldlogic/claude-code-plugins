# Maproom Troubleshooting

Detailed error recovery for the five most common maproom issues. This is a companion to the quick-reference troubleshooting section in [SKILL.md](../SKILL.md) — start there for quick fixes, and use this file when you need root cause analysis or step-by-step recovery.

## Debugging Workflow

When a search command fails or produces unexpected results, follow this systematic workflow:

**1. Verify CLI installed**
```bash
command -v crewchief-maproom
# Expected: /path/to/crewchief-maproom
```

**2. Check CLI version**
```bash
crewchief-maproom --version
# Expected: >= 0.1.0 (minimum version for this documentation)
```

**3. Verify database status**
```bash
crewchief-maproom status
# Expected: List of indexed repositories
```

**4. Test basic search**
```bash
crewchief-maproom search --repo <repo> --query "test" --format agent
# Expected: At least some results (if repo is indexed and non-empty)
```

**5. Enable debug mode**
```bash
# Add --debug flag to see detailed scoring and ranking information
crewchief-maproom search --repo <repo> --query "test" --format agent --debug
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
crewchief-maproom status

# If the repository is not listed, scan it
crewchief-maproom scan
```

### Command Not Found

```
command not found: crewchief-maproom
```

**Cause:** The `crewchief-maproom` binary is not installed or is not on the shell `PATH`.

**Recovery:**
```bash
# Check if the binary exists anywhere
command -v crewchief-maproom

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
crewchief-maproom status

# Initialize the database if needed
crewchief-maproom db migrate

# Scan the repository to populate the index
crewchief-maproom scan

# Verify the scan succeeded
crewchief-maproom status
```

See also the [No Repositories Indexed](#no-repositories-indexed) scenario earlier in this document for full root cause analysis and prevention steps.

### Missing Required Arguments

```
error: the following required arguments were not provided:
  --repo <REPO>
  --query <QUERY>

Usage: crewchief-maproom search --repo <REPO> --query <QUERY>

For more information, try '--help'.
```

**Cause:** One or more required flags were omitted from the command. Both `--repo` and `--query` are required for `search` and `vector-search`.

**Recovery:**
```bash
# Include both required flags
crewchief-maproom search --repo <repo-name> --query "<search terms>"

# Check help for the full flag list
crewchief-maproom search --help
```

### Embedding Service Configuration Error

```
Error: Failed to create embedding service. Ensure OPENAI_API_KEY is set.

Caused by:
    0: Configuration error: Invalid configuration value for credentials:
       Failed to create token provider from ADC
```

**Cause:** The `vector-search` subcommand requires an embedding API key to convert queries into vectors. Either `OPENAI_API_KEY` is not set or GCP Application Default Credentials (ADC) are not configured.

**Recovery:**
```bash
# Check if the environment variable is set
echo "$OPENAI_API_KEY"

# Set it for the current session
export OPENAI_API_KEY="<your-key>"

# If you do not have an API key, use full-text search instead
crewchief-maproom search --repo <repo-name> --query "<search terms>"
```

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
crewchief-maproom search --help

# Use one of the accepted values
crewchief-maproom search --repo <repo-name> --query "<terms>" --format agent
```

**Note on silent failures:** Some invalid values do not produce errors but return empty results. In particular, `--kind` and `--lang` accept any string without validation — an incorrect value like `--kind Func` (uppercase) silently matches nothing. See [Zero Results with Valid Query](#zero-results-with-valid-query) above for details.
