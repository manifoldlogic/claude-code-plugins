# Maproom Concept Glossary

A progressive learning path for understanding maproom. Organized by conceptual dependency — start at Foundation and work down. Each section builds on the previous one.

---

## Foundation Concepts

### What Is Maproom?

Maproom is a **semantic code search engine** that runs locally. It parses your code into searchable units, stores them in a local SQLite database, and lets you find code by keyword or concept. It is a CLI tool invoked as `maproom` or `crewchief maproom`.

### What Is Indexing?

Indexing is the process of scanning your repository and breaking code into searchable pieces. Maproom uses **tree-sitter** (a syntax-aware parser) to understand code structure, so it knows where functions, classes, and methods begin and end — rather than treating files as plain text.

### What Is a Chunk?

A **chunk** is the atomic unit of search in maproom. Each chunk represents one meaningful code element:
- A function definition (kind: `func`)
- A class definition (kind: `class`)
- A method within a class (kind: `method`)
- A module-level constant assignment (kind: `constant`)
- A file-level import block (kind: `imports`)
- A markdown heading and its content (kind: `heading_1`, `heading_2`, `heading_3`, `heading_4`)
- A fenced code block (kind: `code_block`)
- A markdown section — lists, tables, paragraphs (kind: `markdown_section`)
- A hyperlink reference (kind: `link`)
- A JSON key-value pair (kind: `json_key`)

When you search, maproom returns matching chunks — not files, not lines.

### What Is a Repository (in Maproom)?

A maproom "repository" is a named collection of indexed chunks. It usually maps to a git repository but is identified by name in the maproom database. You specify which repository to search with `--repo <name>`. Run `maproom status` to see indexed repository names.

---

## Search Concepts

### Full-Text Search (FTS)

FTS matches your query **keywords** against the text content of indexed chunks. It uses the **BM25 algorithm** (the same ranking system as Elasticsearch) to score results by keyword relevance.

- **Strengths**: Fast, precise, works offline, great for known identifiers
- **Weaknesses**: Misses semantic relationships, requires knowing the right words
- **Command**: `maproom search`

### Vector Search

Vector search matches your query by **meaning** rather than exact keywords. It converts both your query and each chunk into numerical vectors (embeddings) and finds chunks whose vectors are most similar.

- **Strengths**: Finds concepts even when vocabulary differs, handles natural language
- **Weaknesses**: Slower, requires API credentials, less precise for exact identifiers
- **Command**: `maproom vector-search`

### What Is `--k`?

The `--k` flag controls the **maximum number of results** returned by a search. It defaults to 10. Increasing `--k` returns more results (lower-ranked ones); decreasing it returns only the top matches. The `--k` value does not affect how the index is scanned — it only caps the output.

### What Is `total_estimate`?

Every search result header includes `total_estimate` — the search engine's estimate of how many chunks match the query *before* the `--k` cap is applied. For example, `hits=10 | total_estimate=2007` means 10 results were returned out of an estimated 2007 matches. This is an estimate, not an exact count.

### The Rule of Thumb

> Know the words? Use **FTS**. Know the concept? Use **vector search**.

- "Where is the `validateSchema` function?" → FTS
- "How does the authentication flow work?" → Vector search

### Hybrid Search Strategy

FTS and vector search are complementary. When one returns poor results, try the other. Many research tasks benefit from starting with one type and refining with the other.

---

## Embedding Concepts

### What Is an Embedding?

An **embedding** is a list of numbers (a vector) that represents the meaning of a piece of text. Two chunks with similar meaning will have similar embeddings, even if they use completely different words. Maproom generates embeddings for each indexed chunk to power vector search.

### What Is Cosine Similarity?

**Cosine similarity** measures how similar two embeddings are by computing the angle between them:
- **1.0** = identical direction = identical meaning
- **0.75+** = strong conceptual match
- **0.60–0.75** = related content, worth reviewing
- **0.50** = loosely related
- **0.0** = completely unrelated

This is the score you see in vector search results. See [result-interpretation.md](./result-interpretation.md) for the full score breakdown table.

### Provider Incompatibility

Different embedding providers (Google Vertex AI, OpenAI, Ollama) produce vectors in different mathematical spaces. Embeddings from one provider **cannot be compared** with embeddings from another. If you switch providers, you must regenerate all embeddings with `maproom generate-embeddings`.

---

## Infrastructure Concepts

### SQLite Database

Maproom stores all indexed chunks and embeddings in a local **SQLite database** (default: `~/.maproom/maproom.db`). SQLite is a file-based database that requires no server. It supports concurrent reads via WAL (Write-Ahead Logging) mode but serializes writes.

### Tree-Sitter

**Tree-sitter** is the parser maproom uses to understand code structure. It produces a syntax tree for each file, allowing maproom to extract functions, classes, and methods as discrete chunks rather than splitting files arbitrarily. It supports Python, TypeScript, JavaScript, Rust, Go, Markdown, JSON, YAML, and TOML.

### Application Default Credentials (ADC)

**ADC** is Google Cloud's mechanism for authenticating API calls. Maproom uses ADC to call the Vertex AI embedding API for vector search and embedding generation. ADC tokens expire periodically and must be refreshed via `gcloud auth application-default login`. FTS search does not require ADC — it is entirely local.

### The Context Command

`maproom context` is a post-search tool that expands a single chunk to show its **callers** (what calls this code) and **callees** (what this code calls). It navigates the code's call graph, which maproom builds during indexing. Use it after finding a relevant chunk via search to understand how that code connects to the rest of the codebase.

---

## Maproom vs Other Tools

| Dimension | Maproom | Grep | Glob |
|---|---|---|---|
| **Searches by** | Concept or keyword | Exact text/regex | File path pattern |
| **Returns** | Code chunks with scores | Matching lines | File paths |
| **Understands code structure** | Yes (tree-sitter) | No | No |
| **Requires indexing** | Yes | No | No |
| **Speed for known terms** | Fast (FTS) | Fast | N/A |
| **Finds by concept** | Yes (vector) | No | No |

### When to Use Each

- **Maproom FTS**: Finding code by known terms when you want ranked, structured results with chunk context
- **Maproom vector search**: Finding code when you know the concept but not the exact terminology
- **Grep**: Quick exact text search when you know exactly what string you're looking for and don't need ranking
- **Glob**: Finding files by name or path pattern (not content)

### When Not to Use Maproom

- Simple string lookups where Grep is faster and sufficient
- File discovery where Glob is the right tool
- When the maproom CLI is unavailable or the database is not indexed
- When you need regex pattern matching (maproom doesn't support regex queries)
