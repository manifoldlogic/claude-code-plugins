---
name: maproom-search
description: Semantic code search for finding implementations by concept.
---

# Maproom Search

## When to Use
| Tool | Use Case |
|------|----------|
| maproom | Find code by concept |
| Grep | Exact text/regex |
| Glob | File paths |

## Workflow
1. `crewchief-maproom status` (check indexed repos)
2. `crewchief-maproom search --repo <repo> --query "<query>"`
3. `crewchief-maproom context --chunk-id <id>` (explore relationships)

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
