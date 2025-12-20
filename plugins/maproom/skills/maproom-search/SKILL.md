---
name: maproom-search
description: Semantic code search for exploring unfamiliar codebases and finding implementations by concept.
---

# Maproom Search

Semantic code search using SQLite FTS and optional vector embeddings.

## When to Use

| Tool | Use Case |
|------|----------|
| maproom | Find code by concept ("authentication", "error handling") |
| Grep | Exact text/regex matches |
| Glob | File path patterns |

## Quick Reference

```bash
# Check indexed repositories
crewchief-maproom status

# Full-text search
crewchief-maproom search --repo <repo> --query "<query>"

# Vector search (requires embeddings)
crewchief-maproom vector-search --repo <repo> --query "<query>"

# Get context for a chunk
crewchief-maproom context --chunk-id <id>
```

## Learn More

- [Search Best Practices](./references/search-best-practices.md) - Query patterns and strategies
- [CLI Reference](./references/cli-reference.md) - Complete command documentation
- [Troubleshooting](./references/troubleshooting.md) - Common errors and solutions
