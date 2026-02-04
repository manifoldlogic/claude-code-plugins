---
name: maproom-search
description: Semantic code search for exploring unfamiliar codebases and finding implementations by concept.
---

# Maproom Search

## When to Use
| Tool | Use Case |
|------|----------|
| maproom | Find code by concept |
| Grep | Exact text/regex |
| Glob | File paths |

## Workflow

### 1. Check Status First
```bash
crewchief-maproom status
```

If the repository is not indexed, you'll see "No repositories indexed yet."

### 2. Initial Indexing (if needed)
If the repo isn't indexed, run the scan in the background:
```bash
# Get repo name and branch
REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
BRANCH=$(git branch --show-current)

# Run scan in background (can take several minutes for large repos)
nohup crewchief-maproom scan --repo "$REPO_NAME" --worktree "$BRANCH" > /tmp/maproom-scan.log 2>&1 &
echo "Scan started in background. Check progress: tail -f /tmp/maproom-scan.log"
```

The scan indexes code chunks. Embeddings for semantic search are generated separately:
```bash
# After scan completes, generate embeddings (also background-safe)
nohup crewchief-maproom generate-embeddings > /tmp/maproom-embeddings.log 2>&1 &
```

### 3. Search
```bash
crewchief-maproom search --repo <repo> --query "<query>"
```

### 4. Explore Context
```bash
crewchief-maproom context --chunk-id <id>
```

## Configuration & Troubleshooting
For config, flags, and troubleshooting:
```bash
crewchief-maproom --help
```

Consult --help when:
- Binary not found errors
- Configuration issues
- First time using a command

## Query Tips
Extract 2-3 terms from questions. See [search-best-practices.md](./references/search-best-practices.md).
