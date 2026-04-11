---
name: maproom-guide
description: |
  Interpret maproom search results, diagnose maproom errors, and learn maproom concepts.
  Use when the user asks what a maproom score means, encounters a maproom CLI error,
  wants to understand maproom chunk kinds, or asks conceptual questions about how
  maproom search works internally.

  Do NOT use for: running searches (use maproom-search), executing search tasks
  (use maproom-researcher), or setting up maproom (use maproom-search).
---

# Maproom Guide

> Tour guide for understanding maproom output. For command syntax and workflows, see **maproom-search**. For running searches, use **maproom-researcher**.

## When to Use This Skill

| User Question | Use This? | Alternative |
|---|---|---|
| "What does this score mean?" | **YES** | — |
| "Why is result X ranked above Y?" | **YES** | — |
| "What is a chunk kind?" | **YES** | — |
| "Explain this maproom error" | **YES** | — |
| "No results — what went wrong?" | **YES** | — |
| "What's the difference between FTS and vector?" | **YES** | — |
| "How do I search with maproom?" | NO | maproom-search |
| "Search for authentication code" | NO | maproom-researcher |
| "Set up maproom" | NO | maproom-search |
| "Find all error handlers" | NO | maproom-researcher |

**Activation rule:** This skill answers questions *about* maproom output. It never runs maproom commands.

---

## Reading Search Results

### Agent Format Structure

Every search produces a header line followed by result lines:

```
SEARCH query="..." | hits={n} | total_estimate={m} | mode=fts
{file_path}:{start_line} | {chunk_kind} {symbol_name} | {score} | {preview}...
```

**Header fields:**

| Field | Meaning |
|---|---|
| `hits` | Number of results returned (capped by `--k`) |
| `total_estimate` | Estimated total matching chunks in the index (before `--k` cap) |
| `mode` | Search algorithm used: `fts` or `vector` |

**Result fields:**

| Field | Meaning |
|---|---|
| `file_path:line` | Source file and starting line number |
| `chunk_kind` | Type of code element (see Chunk Kinds below) |
| `symbol_name` | Identifier name (function, class, heading text, etc.) |
| `score` | Relevance ranking — scale depends on search type |
| `preview` | First 120 characters of the chunk content |

### Score Interpretation

| Search Type | Scale | Good Match | Weak Match | Notes |
|---|---|---|---|---|
| FTS (`search`) | BM25, 0+ | > 5.0 | < 2.0 | Higher = more keyword hits. Multi-term queries can exceed 15.0. |
| Vector (`vector-search`) | Cosine, 0.0–1.0 | > 0.7 | < 0.5 | Closer to 1.0 = more semantically similar. |

**Important:** Scores are only comparable within a single search. An FTS score of 8.0 in one search is not "better" than 6.0 in a different search — the scales shift with query terms and corpus.

### Chunk Kinds

| Kind | What It Is |
|---|---|
| `func` | Function definition |
| `class` | Class definition |
| `struct` | Struct definition (Rust, Go) |
| `enum` | Enum definition (Rust) |
| `method` | Class/struct method |
| `constant` | Module-level constant assignment |
| `imports` | File-level import block |
| `heading_1` | Markdown # heading |
| `heading_2` | Markdown ## heading |
| `heading_3` | Markdown ### heading |
| `heading_4` | Markdown #### heading |
| `code_block` | Fenced code block in markdown |
| `markdown_section` | Markdown section (lists, tables, paragraphs) |
| `link` | Hyperlink reference |
| `json_key` | JSON key-value pair |

### Result Count Guidance

| Count | What It Suggests |
|---|---|
| 0 results | Wrong search type, filters too narrow, or repo not indexed |
| 1–3 results | Strong match — read these first |
| 4–10 results | Good coverage — review scores to prioritize |
| 10+ results | Query may be too broad — add `--kind`, `--lang`, or reduce `--k` |

The default `--k` is 10 (returns 10 results). Increase `--k` to see more results or decrease to see fewer. `total_estimate` in the output header shows how many matched before the `--k` cap.

For deeper explanation of scoring, ranking mechanics, and edge cases, see [result-interpretation.md](./references/result-interpretation.md).

---

## Error Triage

When maproom produces an error or unexpected output, match the symptom below.

| Symptom | Likely Cause | What to Do |
|---|---|---|
| "No results" (empty output) | Wrong search type, missing embeddings, or repo not indexed | Check search type fits your query; verify with `maproom status` |
| 0 results with `--kind` filter | Case-sensitive filter — `--kind Func` silently matches nothing | Use lowercase: `func`, `class`, `method`, etc. |
| Results seem off-topic | Partial term match — one query term matched unrelated code | Narrow query to more specific terms; try the other search type |
| "Failed to create embedding service" | Expired or missing Google ADC credentials | Not a code bug — run `gcloud auth application-default login` to refresh |
| "command not found: maproom" | CLI not installed or not on PATH | Install CLI or check PATH |
| "Repository not found" | Wrong `--repo` name or repo not scanned | Run `maproom status` to list indexed repos |
| "Failed to assemble context for chunk" | Invalid chunk ID passed to `maproom context` | Re-run search to get a valid chunk ID |
| Results reference deleted code | Stale index | Re-scan the repository |
| Scores seem wrong or random | Wrong search type for query intent | FTS for known terms, vector for concepts |
| "fts5: syntax error" | Empty or malformed query string | Ensure query is non-empty and properly quoted |
| "input token count is ... but the model supports up to 20000" | Embedding batch too large | Re-run with `--batch-size 25` |
| Scan shows "Embedding generation failed" warning | Missing credentials — scan succeeded, embeddings didn't | FTS works; skip embeddings with `--no-generate-embeddings` |

**Key principle:** Maproom errors fall into five categories (see [error-diagnosis.md](./references/error-diagnosis.md) for full taxonomy):
1. **Credential** — ADC/API key expired or misconfigured (not a bug)
2. **Index** — Repo not scanned, stale, or embeddings missing
3. **CLI** — Binary missing, wrong version, invalid flags
4. **Query** — Wrong search type, bad filters, or unquoted special characters
5. **Infrastructure** — Disk full, permissions, SQLite lock

For conceptual explanations of why each error category occurs, see [error-diagnosis.md](./references/error-diagnosis.md).
For step-by-step recovery commands, see [troubleshooting.md](../maproom-search/references/troubleshooting.md).

---

## Core Concepts

| Concept | One-Line Explanation |
|---|---|
| **FTS (Full-Text Search)** | Keyword matching using BM25 ranking — fast, exact, local-only |
| **Vector Search** | Semantic matching using embedding similarity — finds concepts, requires API |
| **Chunk** | A unit of indexed code: one function, class, heading, or code block |
| **Embedding** | Numerical vector representing a chunk's meaning in high-dimensional space |
| **Score** | Relevance measure — BM25 for FTS (unbounded), cosine for vector (0.0–1.0) |
| **Context** | The `maproom context` command — expands a chunk to show callers and callees |

**Rule of thumb:** Know the words? Use FTS. Know the concept? Use vector search.

For a progressive learning path covering these concepts in depth, see [concept-glossary.md](./references/concept-glossary.md).

---

## Related Skills

**Now that you understand maproom output**, use **maproom-search** to learn command syntax, filtering, and search workflows.

| Skill | Role |
|---|---|
| **maproom-search** | Command syntax, setup, workflows, filtering, multi-repo |
| **sdd-spec-search** | SDD specification search patterns |
| **maproom-guide-maintenance** | Procedures for updating this guide |
