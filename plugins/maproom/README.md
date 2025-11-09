# Maproom Plugin

Semantic code search with PostgreSQL, pgvector, and tree-sitter.

## Overview

The Maproom plugin enables intelligent code search across repositories using semantic embeddings and full-text search. It provides:

- **Semantic code search** - Find code by concept, not just keywords
- **Repository indexing** - Scan and index codebases with tree-sitter parsing
- **Continuous monitoring** - Watch for file changes and auto-update indices
- **MCP integration** - Full Model Context Protocol server for code search tools
- **Multi-language support** - TypeScript, Rust, Python, Go, JavaScript, Markdown

## Installation

### Prerequisites

1. **PostgreSQL with pgvector**
   - Running via Docker Compose: `docker compose up -d maproom-postgres`
   - Connection: `postgresql://maproom:maproom@maproom-postgres:5432/maproom`

2. **Maproom binary**
   - Located at `packages/cli/bin/<platform>/crewchief-maproom`
   - Built automatically with `pnpm build`

3. **Embedding provider** (choose one):
   - Ollama (local, default)
   - OpenAI (requires API key)
   - Google Vertex AI (requires GCP credentials)

### Install Plugin

```bash
# Add marketplace (if not already added)
/plugin marketplace add /workspace/.crewchief/claude-code-plugins

# Install maproom plugin
/plugin install maproom@crewchief
```

After installation, restart Claude Code to activate the plugin.

## Components

### MCP Server

Provides semantic search tools via Model Context Protocol:

- `mcp__maproom__status` - Check index status
- `mcp__maproom__search` - Search code semantically
- `mcp__maproom__open` - Retrieve specific code sections
- `mcp__maproom__context` - Get contextually related code
- `mcp__maproom__scan` - Index a repository
- `mcp__maproom__upsert` - Update specific files

See `.mcp.json` for full configuration.

### Skill: maproom

Provides repository indexing capabilities with scripts and documentation:

**Scripts:**
- `scripts/scan.sh` - Index a repository for semantic search
- `scripts/watch.sh` - Continuously monitor and update index

**References:**
- `references/maproom-mcp-docs.md` - Complete MCP tool reference
- `references/search-modes.md` - FTS, vector, and hybrid search guide

**To use the skill:**
```bash
# Scan current directory
bash scripts/scan.sh

# Watch for changes
bash scripts/watch.sh

# Scan specific path
bash scripts/scan.sh /path/to/repo
```

### Hooks

Automated workflow assistance:

- **Before search** - Reminds to ensure repository is indexed
- **After scan** - Suggests running watch for continuous updates

## Quick Start

1. **Start PostgreSQL**
   ```bash
   cd /workspace/packages/maproom-mcp/config
   docker compose up -d maproom-postgres
   ```

2. **Index your repository**
   ```bash
   # Using the skill scripts
   bash scripts/scan.sh /workspace

   # Or using MCP tool
   mcp__maproom__scan({ path: "/workspace", repo: "crewchief" })
   ```

3. **Search code**
   ```typescript
   mcp__maproom__search({
     repo: "crewchief",
     query: "error handling",
     mode: "hybrid"
   })
   ```

4. **Keep index fresh** (optional)
   ```bash
   bash scripts/watch.sh /workspace
   ```

## Search Modes

- **FTS (Full-Text Search)** - Fast keyword matching (5-15ms)
- **Vector (Semantic)** - Concept-based search (50-100ms)
- **Hybrid (Recommended)** - Combined approach for best results

## Best Practices

### Indexing
- Always run `scan` before first search
- Use `watch` during active development
- Re-scan after major changes or branch switches

### Searching
- Keep queries simple (1-3 words)
- Use concepts, not exact identifiers
- Check `status` if searches return no results
- Use `debug: true` to understand ranking

### Performance
- Hybrid mode is best for general use
- Use FTS for exact term searches
- Filter by file type or recency to narrow results

## Troubleshooting

### "Relation does not exist" error
- Run migrations: `cargo run --bin crewchief-maproom -- db`
- Verify PostgreSQL is running
- Check MAPROOM_DATABASE_URL environment variable

### No search results
- Check if repository is indexed: `mcp__maproom__status`
- Run `scan` if repository not indexed
- Try different search mode (fts vs vector vs hybrid)

### Search too slow
- Use `filter` parameter to narrow scope
- Reduce `k` parameter (fewer results)
- Try `fts` mode for faster results

## Configuration

### Environment Variables

```bash
# Database connection
MAPROOM_DATABASE_URL=postgresql://maproom:maproom@maproom-postgres:5432/maproom

# Embedding provider (choose one)
EMBEDDING_PROVIDER=ollama  # or 'openai' or 'google'

# OpenAI (if using)
OPENAI_API_KEY=sk-...

# Google Vertex AI (if using)
GOOGLE_PROJECT_ID=your-project
GOOGLE_APPLICATION_CREDENTIALS=/path/to/credentials.json
```

### MCP Configuration

The plugin's `.mcp.json` automatically configures the maproom MCP server. No manual setup required.

## Version

Current version: **0.1.0**

## Keywords

`search`, `semantic`, `code-search`, `indexing`, `mcp`, `pgvector`, `tree-sitter`, `embeddings`

## Links

- [Repository](https://github.com/danielbushman/claude-code-plugins)
- [Database Architecture](/workspace/docs/architecture/DATABASE_ARCHITECTURE.md)
- [Maproom MCP Documentation](/workspace/packages/maproom-mcp/README.md)
- [Maproom Rust Indexer](/workspace/crates/maproom/README.md)
