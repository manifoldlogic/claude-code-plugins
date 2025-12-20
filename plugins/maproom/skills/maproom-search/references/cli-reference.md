# Maproom CLI Reference

Complete reference for all `crewchief-maproom` commands and options.

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `MAPROOM_DATABASE_URL` | Path to SQLite database | `~/.maproom/maproom.db` |
| `MAPROOM_EMBEDDING_PROVIDER` | Embedding provider (openai, ollama, google) | `openai` |
| `MAPROOM_EMBEDDING_MODEL` | Model name for embeddings | Provider-specific (e.g., `text-embedding-3-small` for OpenAI, `mxbai-embed-large` for Ollama) |
| `MAPROOM_EMBEDDING_DIMENSION` | Vector dimension (768, 1024, 1536) | Auto-inferred from model |
| `RUST_LOG` | Logging level (info, debug, trace) | Not set |
| `RUST_BACKTRACE` | Enable Rust backtraces (0 or 1) | `0` |
| `OPENAI_API_KEY` | OpenAI API key (required for OpenAI provider) | Not set |
| `GOOGLE_PROJECT_ID` | Google Cloud project ID (required for Google provider) | Not set |
| `GOOGLE_APPLICATION_CREDENTIALS` | Path to Google Cloud credentials JSON | Not set |
| `OLLAMA_URL` | Ollama server URL | `http://localhost:11434` |

## Search Commands

### search

Full-text search against indexed chunks using SQLite FTS5 with BM25 ranking.

**Usage:**
```bash
crewchief-maproom search --repo <REPO> --query "<QUERY>" [OPTIONS]
```

**Flags:**
- `--repo <REPO>` - Repository name to search (required)
- `--worktree <WORKTREE>` - Worktree name to filter results (optional)
- `--query <QUERY>` - Search query string (required)
- `--k <K>` - Maximum number of results to return (default: `10`)
- `--debug` - Include score breakdown (base_fts, kind_multiplier, exact_match_multiplier, final)
- `--deduplicate <DEDUPLICATE>` - Deduplicate results across worktrees (default: `true`). Set to `false` to see all results including duplicates
- `-h, --help` - Print help information

**Examples:**
```bash
# Basic search
crewchief-maproom search --repo myproject --query "authentication"

# Search with more results
crewchief-maproom search --repo myproject --query "error handling" --k 20

# Search specific worktree with debug info
crewchief-maproom search --repo myproject --worktree main --query "validation" --debug

# See duplicate results across worktrees
crewchief-maproom search --repo myproject --query "config" --deduplicate false
```

### vector-search

Semantic search using vector embeddings and cosine similarity.

**Usage:**
```bash
crewchief-maproom vector-search --repo <REPO> --query "<QUERY>" [OPTIONS]
```

**Flags:**
- `--repo <REPO>` - Repository name to search (required)
- `--worktree <WORKTREE>` - Worktree name to filter results (optional)
- `--query <QUERY>` - Search query text, will be converted to embedding (required)
- `--k <K>` - Number of results to return (default: `10`)
- `--threshold <THRESHOLD>` - Similarity threshold (0.0-1.0, optional). Only return results with similarity >= threshold
- `-h, --help` - Print help information

**Examples:**
```bash
# Basic semantic search
crewchief-maproom vector-search --repo myproject --query "authentication logic"

# Search with similarity threshold
crewchief-maproom vector-search --repo myproject --query "error handling" --threshold 0.7

# Search specific worktree with more results
crewchief-maproom vector-search --repo myproject --worktree main --query "database connection" --k 20
```

## Indexing Commands

### scan

Scan and index a worktree with real-time progress display. By default, uses incremental scanning to only process changed files based on git tree SHA comparison.

**Usage:**
```bash
crewchief-maproom scan [OPTIONS]
```

**Flags:**
- `--repo <REPO>` - Repository name (defaults to git remote origin name)
- `--worktree <WORKTREE>` - Worktree name (defaults to current branch name)
- `--path <PATH>` - Path to scan (defaults to current directory)
- `--commit <COMMIT>` - Git commit hash (defaults to `HEAD`)
- `--concurrency <CONCURRENCY>` - Number of concurrent file processing threads (default: `4`)
- `--languages <LANGUAGES>` - Comma-separated list of languages to index (optional)
- `--exclude <EXCLUDE>` - Patterns to exclude from indexing (optional)
- `--force` - Force full scan, bypassing incremental tree SHA optimization
- `--generate-embeddings <GENERATE_EMBEDDINGS>` - Automatically generate embeddings after scanning (default: `true`). Values: `true`, `false`
- `--embedding-batch-size <EMBEDDING_BATCH_SIZE>` - Embedding batch size for generation (default: `50`)
- `--provider <PROVIDER>` - Embedding provider: `ollama`, `openai`, or `google` (overrides `MAPROOM_EMBEDDING_PROVIDER` env var)
- `--verbose` - Show detailed output
- `--json` - Output progress as JSON events for programmatic consumption
- `-h, --help` - Print help information

**Examples:**
```bash
# Incremental scan (changed files only)
crewchief-maproom scan

# Scan specific path
crewchief-maproom scan --path /path/to/repo

# Force full scan (all files)
crewchief-maproom scan --force

# Scan without generating embeddings
crewchief-maproom scan --generate-embeddings false

# Scan with custom embedding provider
crewchief-maproom scan --provider ollama --embedding-batch-size 100

# JSON output for programmatic use
crewchief-maproom scan --json
```

### upsert

Upsert a set of files at a given commit. Useful for updating specific files without scanning the entire repository.

**Usage:**
```bash
crewchief-maproom upsert --commit <COMMIT> --repo <REPO> --worktree <WORKTREE> --root <ROOT> [OPTIONS]
```

**Flags:**
- `--paths <PATHS>` - Comma-separated list of file paths to upsert
- `--commit <COMMIT>` - Git commit hash (required)
- `--repo <REPO>` - Repository name (required)
- `--worktree <WORKTREE>` - Worktree name (required)
- `--root <ROOT>` - Repository root path (required)
- `--generate-embeddings <GENERATE_EMBEDDINGS>` - Automatically generate embeddings after upserting (default: `true`). Values: `true`, `false`
- `--embedding-batch-size <EMBEDDING_BATCH_SIZE>` - Embedding batch size for generation (default: `50`)
- `--provider <PROVIDER>` - Embedding provider: `ollama`, `openai`, or `google` (overrides `MAPROOM_EMBEDDING_PROVIDER` env var)
- `-h, --help` - Print help information

**Examples:**
```bash
# Upsert specific files
crewchief-maproom upsert --paths src/main.rs,src/lib.rs --repo myproject --worktree main --root /path/to/repo --commit HEAD

# Upsert without generating embeddings
crewchief-maproom upsert --paths src/config.ts --repo myproject --worktree main --root /path/to/repo --commit HEAD --generate-embeddings false
```

### watch

Watch a worktree for changes and incrementally upsert. Auto-detects the current branch and watches for branch switches. Emits NDJSON events to stdout.

**Usage:**
```bash
crewchief-maproom watch [OPTIONS]
```

**Flags:**
- `--repo <REPO>` - Repository name (defaults to git remote origin name)
- `--worktree <WORKTREE>` - Worktree name (deprecated: auto-detected from current branch)
- `--path <PATH>` - Path to watch (defaults to current directory)
- `--throttle <THROTTLE>` - Throttle interval for file change detection (default: `2s`)
- `--json` - Output as JSON events only, suppress human-readable messages
- `-h, --help` - Print help information

**Examples:**
```bash
# Watch current directory
crewchief-maproom watch

# Watch specific path
crewchief-maproom watch --path /path/to/repo

# JSON output for programmatic use
crewchief-maproom watch --json

# Custom throttle interval
crewchief-maproom watch --throttle 5s
```

### generate-embeddings

Generate embeddings for indexed chunks. By default, only processes chunks where embeddings are NULL (incremental mode).

**Usage:**
```bash
crewchief-maproom generate-embeddings [OPTIONS]
```

**Flags:**
- `--incremental` - Only process chunks where embeddings are NULL (default: `true`)
- `--batch-size <BATCH_SIZE>` - Batch size for processing (default: `100`)
- `--dry-run` - Dry run mode, don't write to database
- `--sample <SAMPLE>` - Process only a sample of N chunks
- `--batch-delay <BATCH_DELAY>` - Delay between batches in milliseconds (default: `100`)
- `--max-cost <MAX_COST>` - Maximum cost ceiling in USD
- `--force` - Force regeneration of all embeddings (overrides `--incremental`)
- `-h, --help` - Print help information

**Examples:**
```bash
# Generate embeddings for chunks without embeddings
crewchief-maproom generate-embeddings

# Force regenerate all embeddings
crewchief-maproom generate-embeddings --force

# Dry run to see what would be processed
crewchief-maproom generate-embeddings --dry-run

# Process with custom batch size and delay
crewchief-maproom generate-embeddings --batch-size 50 --batch-delay 200

# Process sample with cost limit
crewchief-maproom generate-embeddings --sample 1000 --max-cost 5.00
```

## Management Commands

### status

Show status of indexed repositories and worktrees, including statistics about chunks and embeddings.

**Usage:**
```bash
crewchief-maproom status [OPTIONS]
```

**Flags:**
- `--repo <REPO>` - Filter by repository name (optional)
- `--worktree <WORKTREE>` - Filter by worktree name (requires `--repo`)
- `--json` - Output as JSON instead of human-readable text
- `-h, --help` - Print help information

**Examples:**
```bash
# Show all indexed repositories
crewchief-maproom status

# Show specific repository
crewchief-maproom status --repo myproject

# Show specific worktree
crewchief-maproom status --repo myproject --worktree main

# JSON output for scripting
crewchief-maproom status --json
```

### context

Retrieve context bundle for a chunk, including related code (callers, callees, tests, docs, config) within a token budget.

**Usage:**
```bash
crewchief-maproom context --chunk-id <CHUNK_ID> [OPTIONS]
```

**Flags:**
- `--chunk-id <CHUNK_ID>` - Chunk ID to retrieve context for (required)
- `--budget <BUDGET>` - Maximum tokens for the bundle (default: `6000`)
- `--callers` - Include caller functions
- `--callees` - Include callee functions
- `--tests` - Include test files
- `--docs` - Include documentation
- `--config` - Include configuration files
- `--max-depth <MAX_DEPTH>` - Maximum traversal depth for graph relationships (default: `2`)
- `--json` - Output as JSON instead of human-readable format
- `-h, --help` - Print help information

**Examples:**
```bash
# Basic context retrieval
crewchief-maproom context --chunk-id 12345

# Include caller and callee functions
crewchief-maproom context --chunk-id 12345 --callers --callees

# Custom token budget
crewchief-maproom context --chunk-id 12345 --budget 4000

# Include all relationship types with JSON output
crewchief-maproom context --chunk-id 12345 --callers --callees --tests --docs --config --json

# Deep traversal for complex relationships
crewchief-maproom context --chunk-id 12345 --callers --callees --max-depth 3
```

### clean-ignored

Delete indexed chunks matching patterns in `.maproomignore`. Useful for cleaning up stale entries after adding new ignore patterns.

**Usage:**
```bash
crewchief-maproom clean-ignored --repo <REPO> --worktree <WORKTREE> [OPTIONS]
```

**Flags:**
- `--repo <REPO>` - Repository name (required)
- `--worktree <WORKTREE>` - Worktree name (required)
- `--dry-run` - Dry run mode, show what would be deleted without deleting
- `-h, --help` - Print help information

**Examples:**
```bash
# Preview what will be deleted
crewchief-maproom clean-ignored --repo myproject --worktree main --dry-run

# Actually delete matching chunks
crewchief-maproom clean-ignored --repo myproject --worktree main
```

## Database Commands

### db migrate

Apply SQL migrations to the configured database. Creates tables and indexes if they don't exist.

**Usage:**
```bash
crewchief-maproom db migrate
```

**Flags:**
- `-h, --help` - Print help information

**Examples:**
```bash
# Initialize database schema
crewchief-maproom db migrate
```

### db cleanup-stale

Clean up stale worktree data from the database. By default, runs in dry-run mode showing what would be deleted.

**Usage:**
```bash
crewchief-maproom db cleanup-stale [OPTIONS]
```

**Flags:**
- `--confirm` - Actually delete stale data (default is dry-run)
- `-v, --verbose` - Show detailed information
- `-h, --help` - Print help information

**Examples:**
```bash
# Dry-run mode (show what would be deleted)
crewchief-maproom db cleanup-stale

# Actually delete stale data
crewchief-maproom db cleanup-stale --confirm

# Verbose output with details
crewchief-maproom db cleanup-stale --verbose
```

## Daemon Commands

### serve

Start the Maproom daemon for JSON-RPC communication over stdio or Unix socket.

**Usage:**
```bash
crewchief-maproom serve [OPTIONS]
```

**Flags:**
- `--socket` - Use Unix socket mode instead of stdio (experimental)
- `--socket-path <SOCKET_PATH>` - Socket path (default: `/tmp/maproom-{uid}.sock`)
- `--idle-timeout <IDLE_TIMEOUT>` - Idle timeout in seconds (default: `300` = 5 minutes)
- `-h, --help` - Print help information

**Examples:**
```bash
# Start daemon with stdio (default)
crewchief-maproom serve

# Start daemon with Unix socket
crewchief-maproom serve --socket

# Custom socket path with longer timeout
crewchief-maproom serve --socket --socket-path /tmp/my-maproom.sock --idle-timeout 600
```

## Cache Commands

### cache stats

Show cache statistics, including hit rates and memory usage.

**Usage:**
```bash
crewchief-maproom cache stats [OPTIONS]
```

**Flags:**
- `-d, --detailed` - Show detailed per-layer statistics
- `-h, --help` - Print help information

**Examples:**
```bash
# Show basic cache statistics
crewchief-maproom cache stats

# Show detailed per-layer statistics
crewchief-maproom cache stats --detailed
```

### cache clear

Clear cache layers to free memory or force re-computation.

**Usage:**
```bash
crewchief-maproom cache clear [OPTIONS]
```

**Flags:**
- `-l, --layer <LAYER>` - Cache layer to clear: `l1`, `l2`, `l3`, `parse`, or `all` (default: `all`)
- `-h, --help` - Print help information

**Examples:**
```bash
# Clear all cache layers
crewchief-maproom cache clear

# Clear specific cache layer
crewchief-maproom cache clear --layer l1

# Clear parse cache only
crewchief-maproom cache clear --layer parse
```

### cache warm

Warm cache with queries from a file or command-line arguments.

**Usage:**
```bash
crewchief-maproom cache warm [OPTIONS]
```

**Flags:**
- `-q, --queries-file <QUERIES_FILE>` - Path to file containing queries (one per line)
- `--query <QUERY>` - Individual queries to warm (can be repeated)
- `-h, --help` - Print help information

**Examples:**
```bash
# Warm cache from queries file
crewchief-maproom cache warm --queries-file queries.txt

# Warm cache with individual queries
crewchief-maproom cache warm --query "authentication" --query "error handling"

# Combine file and individual queries
crewchief-maproom cache warm --queries-file common-queries.txt --query "additional query"
```

### cache invalidate

Invalidate cache entries by pattern, layer, or file change.

**Usage:**
```bash
crewchief-maproom cache invalidate [OPTIONS]
```

**Flags:**
- `-a, --all` - Invalidate all caches
- `-p, --pattern <PATTERN>` - Invalidate by pattern
- `-l, --layer <LAYER>` - Invalidate specific cache layers
- `-f, --file <FILE>` - Invalidate for file change
- `-h, --help` - Print help information

**Examples:**
```bash
# Invalidate all caches
crewchief-maproom cache invalidate --all

# Invalidate by pattern
crewchief-maproom cache invalidate --pattern "src/*.rs"

# Invalidate specific layer
crewchief-maproom cache invalidate --layer l1

# Invalidate for a file change
crewchief-maproom cache invalidate --file src/main.rs
```

### cache maintenance

Run cache maintenance cycle to optimize memory usage and performance.

**Usage:**
```bash
crewchief-maproom cache maintenance [OPTIONS]
```

**Flags:**
- `-c, --continuous` - Run continuously
- `--interval <INTERVAL>` - Interval in seconds for continuous mode (default: `60`)
- `-h, --help` - Print help information

**Examples:**
```bash
# Run single maintenance cycle
crewchief-maproom cache maintenance

# Run continuously with default 60s interval
crewchief-maproom cache maintenance --continuous

# Run continuously with custom interval
crewchief-maproom cache maintenance --continuous --interval 120
```

## Migration Commands

### migrate markdown

Migrate markdown chunks from regex parser to tree-sitter parser.

**Usage:**
```bash
crewchief-maproom migrate markdown [OPTIONS]
```

**Flags:**
- `-h, --help` - Print help information

**Examples:**
```bash
# Migrate markdown chunks to tree-sitter parser
crewchief-maproom migrate markdown
```

### migrate rollback

Rollback markdown migration from a backup table.

**Usage:**
```bash
crewchief-maproom migrate rollback --backup <BACKUP>
```

**Flags:**
- `--backup <BACKUP>` - Backup table name (e.g., `chunks_backup_20250124_120000`) (required)
- `-h, --help` - Print help information

**Examples:**
```bash
# Rollback to a specific backup
crewchief-maproom migrate rollback --backup chunks_backup_20250124_120000
```

### migrate list-backups

List available backup tables from previous migrations.

**Usage:**
```bash
crewchief-maproom migrate list-backups
```

**Flags:**
- `-h, --help` - Print help information

**Examples:**
```bash
# List all available backup tables
crewchief-maproom migrate list-backups
```

### migrate delete-backup

Delete a backup table to free up database space.

**Usage:**
```bash
crewchief-maproom migrate delete-backup --backup <BACKUP>
```

**Flags:**
- `--backup <BACKUP>` - Backup table name to delete (required)
- `-h, --help` - Print help information

**Examples:**
```bash
# Delete a backup table
crewchief-maproom migrate delete-backup --backup chunks_backup_20250124_120000
```

### migrate verify

Verify migration integrity for a repository.

**Usage:**
```bash
crewchief-maproom migrate verify --repo <REPO>
```

**Flags:**
- `--repo <REPO>` - Repository name (required)
- `-h, --help` - Print help information

**Examples:**
```bash
# Verify migration integrity
crewchief-maproom migrate verify --repo myproject
```

## Global Options

All commands support the following global options:

- `-h, --help` - Print help information for the command
- `-V, --version` - Print version information

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | General error (database connection failed, invalid arguments, etc.) |
| `2` | No data found (e.g., no stale worktrees in cleanup-stale) |

## Common Workflows

### Initial Setup

```bash
# 1. Initialize database
crewchief-maproom db migrate

# 2. Index a repository
crewchief-maproom scan --path /path/to/repo

# 3. Check status
crewchief-maproom status
```

### Searching Code

```bash
# Full-text search
crewchief-maproom search --repo myproject --query "authentication"

# Semantic search (requires embeddings)
crewchief-maproom vector-search --repo myproject --query "user login flow"

# Get context for a result
crewchief-maproom context --chunk-id 12345 --callers --callees
```

### Maintenance

```bash
# Clean up stale worktrees
crewchief-maproom db cleanup-stale --confirm

# Clean up ignored files
crewchief-maproom clean-ignored --repo myproject --worktree main

# Clear cache
crewchief-maproom cache clear
```

### Development Workflow

```bash
# Start file watcher for incremental indexing
crewchief-maproom watch --path /path/to/repo

# In another terminal, check indexing status
crewchief-maproom status --repo myproject
```
