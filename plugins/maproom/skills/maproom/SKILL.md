---
name: maproom
description: Provides semantic code search capabilities for indexed repositories. Use this skill when searching code by concept, exploring architecture, or understanding code relationships. Always ensure the repository is scanned before attempting searches.
---

# Maproom - Semantic Code Search

## Overview

Maproom enables semantic code search across repositories using PostgreSQL with pgvector and tree-sitter. This skill provides scripts to index repositories and maintain up-to-date search indices, along with guidance on when and how to use semantic search effectively.

## Core Capabilities

### 1. Repository Indexing (Scan)

Index a repository to enable semantic search. Scanning parses code using tree-sitter, generates embeddings, and stores them in PostgreSQL.

**When to scan:**
- First time working with a repository
- After significant code changes
- Before running semantic searches

**How to scan:**

```bash
# Scan current directory
bash scripts/scan.sh

# Scan specific path
bash scripts/scan.sh /path/to/repo

# Scan with specific worktree
bash scripts/scan.sh /path/to/repo main
```

**What scanning does:**
- Discovers and parses code files (TypeScript, Rust, Python, Go, JavaScript, Markdown)
- Generates semantic embeddings for code chunks
- Stores in PostgreSQL database for fast retrieval
- Creates indexes for FTS and vector search

### 2. Continuous Indexing (Watch)

Watch a repository for changes and automatically re-index modified files. This keeps the search index current as code evolves.

**When to watch:**
- During active development
- After initial scan to maintain index freshness
- When working on long-running tasks

**How to watch:**

```bash
# Watch current directory
bash scripts/watch.sh

# Watch specific path
bash scripts/watch.sh /path/to/repo

# Watch with specific worktree
bash scripts/watch.sh /path/to/repo main
```

**What watching does:**
- Monitors file system for code changes
- Automatically re-indexes modified files
- Maintains index freshness without manual intervention

### 3. Semantic Search

Use maproom MCP tools to search indexed code by concept rather than exact text matches.

**When to use semantic search:**
- Finding code by concept: "authentication flow", "error handling"
- Exploring architecture: "main classes", "entry points"
- Understanding relationships: "what calls this function"
- Navigating unfamiliar codebases

**When NOT to use semantic search:**
- Exact text matches (use Grep instead)
- Known filename patterns (use Glob instead)
- Simple string searches (use Grep instead)

**Available search modes:**
- `fts` - Full-text search (keyword matching)
- `vector` - Semantic search (concept-based)
- `hybrid` - Combined FTS + vector (default, best overall)

## Workflow Decision Tree

```
Are you trying to search code?
├─ Yes
│  ├─ Is repository indexed?
│  │  ├─ Yes → Proceed with search
│  │  └─ No → Run scan first (scripts/scan.sh)
│  └─ Do you need continuous updates?
│     ├─ Yes → Run watch (scripts/watch.sh)
│     └─ No → Single scan sufficient
└─ No
   └─ Use standard code navigation tools
```

## Best Practices

### Before Searching
1. **Always check index status** using `mcp__maproom__status`
2. **Run scan if needed** - Search will fail if repository isn't indexed
3. **Verify database connection** - Ensure PostgreSQL is running

### Query Tips
1. **Keep queries simple** - 1-3 words works best
2. **Use concepts, not keywords** - "auth" not "authentication_service_implementation_v2"
3. **Think "what does this do"** not "what is it called"
4. **Good examples**: "error handling", "message bus", "state management"
5. **Avoid**: "TODO comments", "find all ⚠️ markers", exact file paths

### Maintaining Index Freshness
1. **Run watch during active development** - Keeps index current automatically
2. **Re-scan after major changes** - Branch switches, large merges
3. **Monitor database size** - Large repositories may require periodic cleanup

## Technical Details

### Database Requirements
- PostgreSQL 14+ with pgvector extension
- Connection: `postgresql://maproom:maproom@maproom-postgres:5432/maproom`
- Managed via Docker Compose in `packages/maproom-mcp/config/`

### Embedding Providers
Maproom supports multiple embedding providers:
- **Ollama** (local, default)
- **OpenAI** (requires API key)
- **Google Vertex AI** (requires GCP credentials)

Configuration via environment variables or MCP settings.

### Performance Considerations
- **Initial scan time**: Depends on repository size (minutes for large repos)
- **Watch overhead**: Minimal, uses file system events
- **Search speed**: Hybrid search typically <100ms for indexed repos
- **Database size**: Roughly 10-50MB per 1000 files indexed

## Resources

This skill includes:

### scripts/
- `scan.sh` - Index a repository for semantic search
- `watch.sh` - Continuously monitor and update index

### references/
- `maproom-mcp-docs.md` - Comprehensive MCP server documentation
- `search-modes.md` - Detailed explanation of FTS, vector, and hybrid search

### Usage Notes

**Scripts execution**: Both scan and watch scripts use the Rust maproom binary located at `packages/cli/bin/<platform>/crewchief-maproom`. They handle platform detection automatically.

**Error handling**: Scripts check for database connectivity and provide clear error messages. If database connection fails, ensure Docker Compose is running.

**Integration with agents**: Hooks in this plugin automatically ensure scanning happens before searches and watching starts after scanning.
