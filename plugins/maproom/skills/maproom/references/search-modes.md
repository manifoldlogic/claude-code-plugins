# Maproom Search Modes

Maproom provides three search modes, each optimized for different use cases.

## FTS (Full-Text Search)

PostgreSQL tsvector keyword matching using GIN indexes.

**Best for:**
- Exact keyword matches
- Identifier searches
- Specific terms
- Known function/variable names

**How it works:**
- Tokenizes query and code
- Uses PostgreSQL's full-text search
- Ranks by text relevance and tf-idf scores
- Very fast (typically <10ms)

**Example queries:**
- `getUserById`
- `handleError`
- `database connection`

**Limitations:**
- Requires exact or similar terms
- No concept understanding
- May miss semantically similar code

## Vector (Semantic Search)

pgvector cosine similarity using HNSW indexes and embeddings.

**Best for:**
- Conceptual searches
- Finding similar code
- Understanding intent
- Exploring unfamiliar codebases

**How it works:**
- Converts query to embedding vector
- Performs approximate nearest neighbor search
- Ranks by cosine similarity
- Understands semantic relationships

**Example queries:**
- `authentication flow`
- `error handling`
- `data validation`
- `API integration`

**Limitations:**
- Slower than FTS (typically 50-100ms)
- Requires embeddings to be generated
- May surface semantically similar but functionally different code

## Hybrid (Recommended)

Combines FTS and vector search using Reciprocal Rank Fusion (RRF).

**Best for:**
- General code search
- Balancing precision and recall
- Most real-world queries
- When unsure which mode to use

**How it works:**
- Runs both FTS and vector search in parallel
- Merges results using RRF algorithm
- Applies additional scoring signals:
  - Text relevance
  - Vector similarity
  - Recency (newer code ranked higher)
  - Symbol importance (exports, public functions)
  - Chunk type (functions > comments)

**Example queries:**
- `message queue implementation`
- `user authentication`
- `state management`
- `error logging`

**Benefits:**
- Best of both worlds
- More robust to query variations
- Better overall results in practice
- Default mode for good reason

## Scoring Signals

All search modes apply these additional signals:

### Recency
- Newer code ranked higher
- Based on git commit timestamps
- Configurable weight

### Symbol Importance
- Exported symbols ranked higher
- Public functions > private functions
- Main entry points boosted

### Chunk Type Hierarchy
1. Function definitions
2. Class definitions
3. Type definitions
4. Comments
5. Other code

## Performance Characteristics

| Mode | Typical Latency | Index Type | Memory Usage |
|------|----------------|------------|--------------|
| FTS | 5-15ms | GIN | Low |
| Vector | 50-100ms | HNSW | High |
| Hybrid | 50-120ms | Both | High |

## Choosing a Mode

**Use FTS when:**
- You know the exact term
- Searching for specific identifiers
- Performance is critical
- Working with small codebases

**Use Vector when:**
- Exploring concepts
- Finding similar patterns
- Understanding architecture
- Working with unfamiliar code

**Use Hybrid when:**
- General-purpose search
- Balancing precision and recall
- Unsure which mode to use
- Want best overall results (recommended)

## Configuration

Modes are specified when calling maproom MCP tools:

```typescript
// FTS search
mcp__maproom__search({
  repo: "crewchief",
  query: "getUserById",
  mode: "fts"
})

// Vector search
mcp__maproom__search({
  repo: "crewchief",
  query: "authentication flow",
  mode: "vector"
})

// Hybrid search (default)
mcp__maproom__search({
  repo: "crewchief",
  query: "message handling",
  mode: "hybrid"
})
```

## Debug Mode

Enable debug mode to see score breakdowns and understand ranking:

```typescript
mcp__maproom__search({
  repo: "crewchief",
  query: "error handling",
  debug: true
})
```

Debug output includes:
- FTS score components
- Vector similarity scores
- Graph signal contributions
- Fusion method used
- Final ranking explanations
