# Result Interpretation

Deep reference for understanding maproom search output. The [maproom-guide SKILL.md](../SKILL.md) has a compact quick-reference — use this document when you need to understand *why* results look the way they do.

---

## FTS Score Interpretation

Maproom FTS uses **BM25 ranking**, the same algorithm behind Elasticsearch and SQLite FTS5.

### How BM25 Works

BM25 scores measure how relevant a chunk is to your query based on:
- **Term frequency** — how often query terms appear in the chunk (more = higher score, with diminishing returns)
- **Inverse document frequency** — how rare the term is across all chunks (rarer terms carry more weight)
- **Document length normalization** — shorter chunks with the same term count score higher than longer ones

### Score Ranges

| Range | Interpretation |
|---|---|
| 15.0+ | Exceptional match — multi-term queries with rare, concentrated terms |
| 5.0–15.0 | Strong match — good keyword overlap with the query |
| 2.0–5.0 | Moderate match — some term overlap, may be tangential |
| 1.0–2.0 | Weak match — minimal keyword presence |
| < 1.0 | Very weak — likely only partial term match or common terms |

**Note:** Multi-term queries (3+ words) can produce scores above 15.0 because BM25 sums per-term scores. A four-term query where all terms are rare and concentrated in a short chunk can score 17+ or higher.

### Cross-Search Comparison Caveat

BM25 scores are **not comparable across different searches**. A score of 8.0 for query "validate schema" has no relationship to a score of 8.0 for query "authentication flow". The scale shifts because:
- Different queries have different IDF (inverse document frequency) weights
- The corpus statistics change relative to each query's terms
- A common word like "config" produces lower per-term scores than a rare word like "defragment"

**Within a single search**, higher scores reliably indicate better keyword relevance.

---

## Vector Score Interpretation

Maproom vector search returns **cosine similarity** scores between the query embedding and each chunk embedding.

### How Cosine Similarity Works

Cosine similarity measures the angle between two vectors in embedding space:
- **1.0** = vectors point in exactly the same direction (identical meaning)
- **0.0** = vectors are perpendicular (unrelated)
- Values below 0 are theoretically possible but extremely rare in practice

### Score Ranges

| Range | Interpretation | Action |
|---|---|---|
| 0.90+ | Near-exact semantic match | High confidence — read these first |
| 0.75–0.90 | Strong conceptual match | Good results — likely relevant |
| 0.60–0.75 | Related content | Worth reviewing — may be tangential |
| 0.50–0.60 | Loosely related | Borderline — check if relevant to intent |
| < 0.50 | Weak or unrelated | Usually noise — consider filtering with `--threshold` |

### Score Clustering

Vector search results often cluster in a narrow band (e.g., many results between 0.65–0.75). This is normal — it means several chunks are roughly equally related to the query concept. When this happens:
- Rely on **chunk kind** and **file path** to prioritize, not just score
- A result at 0.72 is not meaningfully different from one at 0.70

### Using --threshold

The `--threshold` flag filters out results below a cosine similarity cutoff:
- `--threshold 0.8` — strict, only strong semantic matches
- `--threshold 0.7` — balanced, filters noise while keeping related content
- `--threshold 0.5` — permissive, useful with high `--k` values to prevent pure noise
- Omitted — no filtering, returns top k results regardless of score

**Guideline:** Use `--threshold 0.7` as a starting point. Lower to 0.5 if results are too few; raise to 0.8 if results are too noisy.

---

## Chunk Kind Deep Reference

Each chunk kind represents a specific type of code element extracted by maproom's tree-sitter parser during indexing.

### Code Chunk Kinds

| Kind | What Gets Indexed | Produced By | Typical Use |
|---|---|---|---|
| `func` | Entire function body including signature, docstring, and implementation | `.py`, `.ts`, `.rs`, `.go`, `.js` | Finding function implementations |
| `class` | Class definition including docstring and method signatures | `.py`, `.ts`, `.js` | Finding class hierarchies, data models |
| `method` | Individual class method body | `.py`, `.ts`, `.js` | Finding specific behavior within a class |
| `constant` | Module-level constant assignment (e.g., `HOOK_PATH = ...`) | `.py`, `.ts`, `.js` | Finding configuration constants |
| `imports` | File-level import/require block | `.py`, `.ts`, `.js` | Finding module dependencies |

### Documentation Chunk Kinds

| Kind | What Gets Indexed | Produced By | Typical Use |
|---|---|---|---|
| `heading_1` | Markdown `#` heading and its content | `.md` | Finding top-level document titles |
| `heading_2` | Markdown `##` heading and its content until the next heading | `.md` | Finding documentation sections |
| `heading_3` | Markdown `###` heading and its content | `.md` | Finding sub-sections within docs |
| `heading_4` | Markdown `####` heading and its content | `.md` | Finding nested sub-sections |
| `code_block` | Fenced code block (``` delimited) | `.md` | Finding code examples in documentation |
| `markdown_section` | Non-heading markdown content (lists, tables, paragraphs) | `.md` | Finding structured documentation content |
| `link` | Hyperlink reference | `.md` | Finding cross-references and URLs |

### Data Chunk Kinds

| Kind | What Gets Indexed | Produced By | Typical Use |
|---|---|---|---|
| `json_key` | Top-level or significant key-value pairs | `.json` | Finding configuration values, package metadata |

### Symbol Name Conventions

The `symbol_name` field in results means different things for different chunk kinds:
- **func/method**: The function or method name (e.g., `validate_schema`)
- **class**: The class name (e.g., `AuthMiddleware`)
- **constant**: The constant name (e.g., `HOOK_PATH`)
- **heading_2/heading_3**: The heading text (e.g., `Installation Guide`)
- **code_block**: `Code: {first_word}` from the code block (e.g., `Code: bash`)
- **json_key**: The key path (e.g., `scripts.build`)
- **markdown_section**: First few words of the content

---

## Agent Format Anatomy

### Output Header

Every search produces a header line before the results:

```
SEARCH query="workflow guidance" | hits=10 | total_estimate=1913 | mode=fts
```

| Field | Meaning | Notes |
|---|---|---|
| `query` | The search query submitted | Quoted for clarity |
| `hits` | Number of results in this response | Capped by `--k` (default 10) |
| `total_estimate` | Estimated total matching chunks | Before `--k` filtering. This is an estimate, not exact. |
| `mode` | Search algorithm used | `fts` for full-text, `vector` for semantic |

**`total_estimate` is not exact.** It reflects the search engine's estimated match count, which may differ slightly from the true count. Do not rely on it for precise totals.

### Result Lines

A complete agent format result line:

```
plugins/sdd/hooks/workflow-guidance.py:913 | func validate_state_file_schema | 3.91 | def validate_state_file_schema(schema_data):...
```

### Field-by-Field Breakdown

| Position | Field | Example | Notes |
|---|---|---|---|
| 1 | File path + line | `plugins/.../file.py:42` | Relative to repo root. Line is where the chunk starts. |
| 2 | Kind + symbol | `func validate_input` | Chunk kind followed by symbol name, separated by space. |
| 3 | Score | `8.32` | BM25 for FTS, cosine for vector. See scoring sections above. |
| 4 | Preview | `def validate_input(data...` | First 120 chars of chunk content. Truncated with `...` |

### Preview Truncation

- Default length: 120 characters for agent format, 200 for JSON format
- Adjustable via `--preview-length N`
- Truncation marker: `...` appended when content exceeds the limit
- Preview always starts at the beginning of the chunk (not at the matched term)

### Context Command Output Format

The `maproom context` command produces a different header than search:

```
CONTEXT chunk_id=2852 | tokens=202/6000 | items=1 | truncated=no
primary | plugins/sdd/README.md:126-149 | 202 | Primary chunk: Integration with Workflow Guidance (heading_4) | ...
```

| Field | Meaning |
|---|---|
| `chunk_id` | The numeric chunk ID queried |
| `tokens` | Token count used / budget limit (default 6000) |
| `items` | Number of context items returned (1 = primary chunk only, >1 = callers/callees found) |
| `truncated` | Whether results were truncated to fit the token budget |

Context result lines show: `relationship | file:lines | tokens | description | preview`
- `primary` = the queried chunk itself
- `caller` = code that calls this chunk
- `callee` = code called by this chunk

---

## Result Count Patterns

### Zero Results

Zero results from a search means one of:
1. **Wrong search type** — FTS for a concept (use vector instead) or vector for an exact identifier (use FTS)
2. **Filters too narrow** — `--kind` or `--lang` is excluding matches. Remove filters and retry.
3. **Repo not indexed** — Run `maproom status` to verify the repo has chunks
4. **Embeddings missing** — Vector search requires pre-generated embeddings. Check `maproom status`.
5. **Case-sensitive filter** — `--kind Func` silently matches nothing (should be `func`)
6. **Code genuinely doesn't exist** — Not every query will find something. This is a valid outcome.

### Few Results (1–3)

Usually indicates a strong, specific match. These are often the most useful results. Read them before broadening the search.

### Many Results (10+)

Indicates a broad query that matches widely. To focus:
- Add `--kind func` to limit to functions only
- Add `--lang py` to limit to a specific language
- For vector search, add `--threshold 0.7` to filter weak matches
- Reduce to 2–3 core search terms

### Partial-Term Match False Positives

FTS scores results when *any* query term matches, not all. A multi-term query like "defragmentation optimizer" may return results matching only "optimizer" in unrelated code. When results seem off-topic:
- Check which query term actually matched (look at the preview)
- Narrow the query to more unique or specific terms
- Try vector search, which matches on overall meaning rather than individual terms

### Duplicate-Looking Results

If multiple results point to the same file at different lines, they represent **different chunks within the same file** (e.g., multiple functions). This is normal — each chunk is indexed independently.

Results at adjacent line numbers (e.g., `:913` and `:914`) may represent overlapping chunk windows for the same function. This is a known indexing behavior — the chunks overlap slightly at boundaries.
