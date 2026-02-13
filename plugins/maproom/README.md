# Maproom Plugin

## Introduction

The Maproom plugin provides semantic code search capabilities powered by the crewchief-maproom CLI. It enables Claude Code to search, analyze, and understand codebases using both full-text search (FTS) and vector-based semantic search. With Maproom, you can find code by concept rather than just exact text matches, explore relationships between code elements, and gain architectural insights across large codebases.

## Features

- **Full-Text Search (FTS)**: Fast, precise keyword-based search for exact matches, identifiers, and specific terms
- **Vector Semantic Search**: Find code by meaning and concept, even when exact keywords differ
- **Agent-Optimized Output**: Compact `--format agent` mode designed for LLM context efficiency
- **Hybrid Search**: Combines FTS and vector search for optimal relevance ranking
- **Context Expansion**: Automatically retrieve related code including imports, callers, callees, and tests
- **Graph Relationships**: Navigate code relationships through call graphs and dependency analysis
- **Multi-Repository Support**: Configuration template and agent guidance for searching across code and documentation repositories with repo-specific search strategies
- **Language Aware**: Leverages tree-sitter for syntax-aware indexing and search

## Multi-Repo Setup

Search across multiple repositories by configuring repo-specific search strategies and agent guidance.

1. Copy the configuration template to your workspace root:
   ```bash
   cp plugins/maproom/skills/maproom-search/templates/maproom-repos.yaml ./maproom-repos.yaml
   ```
2. Customize repo entries for your workspace (paths, descriptions, search guidance)
3. Set environment variables for path portability (`MAPROOM_REPOS_ROOT`, `MAPROOM_SPECS_ROOT`)
4. Index each repo with `crewchief-maproom scan`

See [multi-repo-guide.md](skills/maproom-search/references/multi-repo-guide.md) for detailed setup instructions, search strategies by repo type, and cross-repo search patterns.

## Prerequisites

Before using the Maproom plugin, ensure you have:

1. **crewchief-maproom CLI installed**: The plugin requires the `crewchief-maproom` command-line tool to be available in your system PATH
2. **Indexed database**: Your codebase must be scanned using `crewchief-maproom scan` before searching
3. **Database location**: The maproom database is typically located at `~/.maproom/maproom.db` (can be overridden with `MAPROOM_DATABASE_URL` environment variable)

To verify your setup:
```bash
# Check CLI is installed
crewchief-maproom --version

# Index your repository
crewchief-maproom scan

# Verify indexing succeeded
crewchief-maproom status
```

## Installation

Install the Maproom plugin using the Claude Code plugin command:

```
/plugin install maproom@crewchief
```

Once installed, the plugin will automatically be available for use in your Claude Code sessions.

## Usage Examples

### Basic Semantic Search
```
Find authentication logic in the codebase
```
The plugin will use semantic search to find authentication-related code, even if it doesn't use the exact term "authentication".

### Finding Specific Functions
```
Search for the WebSocket disconnect handler
```
Locates WebSocket disconnect functionality using hybrid search.

### Exploring Error Handling
```
Show me how errors are handled in the checkout process
```
Finds error handling patterns in checkout-related code.

### Architecture Understanding
```
What components handle user sessions?
```
Identifies session management components and their relationships.

### Code Relationships
```
Find all callers of the validateCart function
```
Uses context expansion to show where validateCart is called throughout the codebase.

## Troubleshooting

### CLI Not Found
**Problem**: Plugin reports `crewchief-maproom: command not found`

**Solution**:
- Verify the CLI is installed: `command -v crewchief-maproom`
- Ensure it's in your PATH
- If using a development build, run `pnpm build` in the crewchief repository

### Database Not Indexed
**Problem**: Search returns "no repositories indexed" or empty results

**Solution**:
- Run `crewchief-maproom scan` to index your codebase
- Check indexing status: `crewchief-maproom status`
- Verify database exists: `ls -la ~/.maproom/maproom.db`

### No Results Found
**Problem**: Searches return no results or irrelevant matches

**Solution**:
- Try different search terms or phrasing
- Use more specific queries (2-3 core technical terms work best)
- Check if the repository is actually indexed: `crewchief-maproom status`
- Verify file types are indexed (use `--file-type` filter if needed)
- Try different search modes: hybrid (default), fts, or vector
- For very recent code changes, re-index: `crewchief-maproom scan --force`

### Stale Results
**Problem**: Search results don't reflect recent code changes

**Solution**:
- Re-index the repository: `crewchief-maproom scan`
- The daemon auto-refreshes but may need manual reindexing for major changes

### Performance Issues
**Problem**: Searches are slow or timing out

**Solution**:
- Reduce the number of results requested (use `k` parameter)
- Use FTS mode for exact keyword matches (faster than semantic search)
- Check database size: large databases may need optimization
- Ensure SQLite isn't locked by another process
