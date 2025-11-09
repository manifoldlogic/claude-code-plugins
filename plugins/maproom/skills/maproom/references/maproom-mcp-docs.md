# Maproom MCP Server Documentation

Quick reference for the Maproom Model Context Protocol (MCP) server tools.

## Available MCP Tools

### mcp__maproom__status

Get maproom index status - **ALWAYS USE THIS FIRST** before searching!

Shows indexed repos, worktrees, statistics, and last update times. Tells you what's searchable and helps diagnose why searches might fail.

```typescript
mcp__maproom__status({
  repo: "crewchief" // Optional: filter to specific repo
})
```

**Returns:**
- List of indexed repositories
- Worktrees per repository
- Chunk counts
- Last indexed timestamps
- Embedding statistics

### mcp__maproom__search

Semantic code search - BEST FOR finding functions/classes by concept, understanding code relationships, exploring unfamiliar codebases.

```typescript
mcp__maproom__search({
  repo: "crewchief",        // Required: repository name
  query: "error handling",  // Required: search query (1-3 words works best)
  mode: "hybrid",           // Optional: "fts", "vector", or "hybrid" (default)
  k: 10,                    // Optional: number of results (default 10, max 20)
  debug: false,             // Optional: enable score breakdowns
  worktree: "main",         // Optional: limit to specific worktree
  filter: "code",           // Optional: "all", "code", "docs", "config"
  filters: {                // Optional: advanced filters
    file_type: "ts",
    recency_threshold: "7 days"
  }
})
```

**Query best practices:**
- Keep it simple: 1-3 words works best
- Use concepts: "auth" not "authentication_service_implementation_v2"
- Think "what does this do" not "what is it called"
- Good: "error handling", "message bus", "state management"
- Avoid: "TODO comments", "find all ⚠️ markers", exact file paths

**When NOT to use:**
- Exact string matching (use Grep instead)
- Special characters or symbols in query
- File paths or file names (use Glob instead)
- Very long queries (>4 words)

### mcp__maproom__open

Retrieve specific code from indexed files.

**USE AFTER** getting search results. Requires exact relpath and worktree from search results.

```typescript
mcp__maproom__open({
  relpath: "src/index.ts",   // Required: exact path from search results
  worktree: "main",          // Required: worktree from search results
  range: {                   // Optional: line range
    start: 10,
    end: 50
  },
  context: 5                 // Optional: context lines around range
})
```

**Supports:**
- Line ranges from search results (start_line/end_line)
- Context lines before/after
- Full file retrieval

### mcp__maproom__context

Retrieve contextually relevant code sections around a chunk.

Assembles a ContextBundle with the target chunk plus related context (imports, callers, tests, etc.) within a token budget.

```typescript
mcp__maproom__context({
  chunk_id: "uuid",          // Required: from search results
  budget_tokens: 6000,       // Optional: max tokens (default 6000, range 1000-20000)
  expand: {                  // Optional: expansion config
    callers: true,           // Include chunks that call this
    callees: true,           // Include chunks called by this
    tests: true,             // Include test chunks
    docs: false,             // Include documentation
    config: false,           // Include config files
    max_depth: 2             // Traversal depth (1-5)
  }
})
```

**Best for:**
- Understanding code in context
- Gathering related functionality
- Following call chains
- Finding tests for specific code

### mcp__maproom__scan

Scan and index an entire repository or worktree with automatic embedding generation.

**USE FOR:**
- Initial indexing of a new repository
- Re-indexing after major changes
- Ensuring all files are indexed

```typescript
mcp__maproom__scan({
  path: "/workspace",        // Optional: defaults to current directory
  repo: "crewchief",         // Optional: auto-detect from git remote
  worktree: "main",          // Optional: auto-detect from git branch
  commit: "HEAD",            // Optional: defaults to HEAD
  languages: ["typescript", "rust"], // Optional: limit languages
  exclude: ["node_modules/**", "*.test.ts"], // Optional: glob patterns
  concurrency: 4,            // Optional: workers (default 4, max 16)
  parallel: false            // Optional: parallel batch processing
})
```

**Multi-provider support:**
Automatically detects and uses available embedding provider (Ollama, OpenAI, or Google Vertex AI).

### mcp__maproom__upsert

Index/update specific files in maproom with automatic embedding generation.

**USE WHEN:**
- Files have changed and need reindexing
- Targeted updates of a few specific files

**FOR FULL REPO:** use "scan" instead.

```typescript
mcp__maproom__upsert({
  paths: ["src/index.ts", "src/utils.ts"], // Required: files to index
  commit: "HEAD",          // Required: commit SHA
  repo: "crewchief",       // Required: repository name
  worktree: "main",        // Required: worktree name
  root: "/workspace"       // Required: repository root
})
```

### mcp__maproom__explain

Generate a detailed symbol card for a code chunk (EXPERIMENTAL).

Provides markdown-formatted explanation with metadata, relationships, code preview, and usage examples.

```typescript
mcp__maproom__explain({
  chunk_id: "uuid"          // Required: from search results
})
```

**Note:** Must be enabled in configuration. Uses intelligent caching for performance.

## Quick Workflow

1. **Check status**: `mcp__maproom__status({ repo: "crewchief" })`
2. **Search**: `mcp__maproom__search({ repo: "crewchief", query: "agent spawn" })`
3. **Get code**: `mcp__maproom__open({ relpath: "path", worktree: "main" })`
4. **Get context**: `mcp__maproom__context({ chunk_id: "uuid" })`
5. **Update**: `mcp__maproom__upsert({ repo, worktree, root, commit: "HEAD", paths: [...] })`

## Troubleshooting

### No search results
1. Check `status` to verify repo is indexed
2. Try different search mode (`fts` vs `vector` vs `hybrid`)
3. Simplify query to 1-3 words
4. Verify database connection

### Search too slow
1. Use `filter` parameter to narrow scope
2. Reduce `k` parameter (fewer results)
3. Use `fts` mode for faster results
4. Check database performance

### Stale results
1. Run `scan` to re-index repository
2. Run `upsert` for specific changed files
3. Check `last_indexed` timestamp in `status`

## Database Connection

Default: `postgresql://maproom:maproom@maproom-postgres:5432/maproom`

Override with `DATABASE_URL` environment variable.

Ensure PostgreSQL with pgvector extension is running before using maproom tools.
