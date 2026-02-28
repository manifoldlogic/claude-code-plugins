# Multi-Repo Search Guide

## Repo Types and Their Content

Maproom indexes two distinct types of repositories: **code** repos containing source files and **docs** repos containing specifications, design documents, and project history. Each type produces different chunk kinds and responds best to different search strategies.

### Chunk Kinds by Repo Type

The following chunk kinds were verified by running `maproom search` against indexed repositories (crewchief for code, manifoldlogic/claude-code-plugins for mixed content).

| Chunk Kind | Found In | Description |
|---|---|---|
| `func` | code repos | Functions, standalone methods, closures |
| `class` | code repos | Class definitions (Python, TypeScript, etc.) |
| `struct` | code repos | Struct definitions (Rust, Go) |
| `enum` | code repos | Enum definitions |
| `method` | code repos | Class/struct methods (bound to a type) |
| `imports` | code repos | Import blocks (`__imports__` per file) |
| `heading_1` | docs repos | Top-level headings (`#`) |
| `heading_2` | docs repos | Section headings (`##`) |
| `heading_3` | docs repos | Subsection headings (`###`) |
| `markdown_section` | docs repos | Lists, tables, and general prose sections |
| `code_block` | docs repos | Fenced code blocks (annotated with language) |
| `link` | docs repos | Hyperlinks within documents |
| `json_key` | both | Keys in JSON configuration files (e.g., plugin.json) |

### What Each Repo Type Contains

| Aspect | Code Repo (`type: code`) | Docs Repo (`type: docs`) |
|---|---|---|
| Primary content | Source code, tests, configs | Specs, plans, decisions, tickets |
| Answers the question | "How is it built?" | "Why was it built this way?" |
| Key identifiers | Function names, class names, variables | Ticket IDs, section headings, terms |
| Relationships | Call graphs, imports, type hierarchies | Document cross-references, links |
| Chunk density | Many small chunks (one per function) | Fewer, larger chunks (per section) |

## Code Repo Search Strategies

Code repos contain implementation details. Use these strategies depending on what you know about your target.

### Full-Text Search (FTS) -- When You Have Identifiers

Use FTS when you know specific names, strings, or identifiers. FTS excels at exact and partial matches against symbol names.

**Function/method names:**

```bash
maproom search --repo crewchief --query "extract_function_identifier" --kind func --format agent
```

**Class or struct names:**

```bash
maproom search --repo crewchief --query "ShadowMode" --kind class --format agent
```

**Error messages or string literals:**

```bash
maproom search --repo crewchief --query "Failed to create embedding" --format agent
```

**Configuration keys:**

```bash
maproom search --repo crewchief --query "MAPROOM_DATABASE_URL" --format agent
```

**Import paths:**

```bash
maproom search --repo crewchief --query "extract_standard_import" --format agent
```

### Vector Search -- When You Have Concepts

Use vector search when you have a concept or question but do not know the exact names. Vector search finds semantically similar code.

```bash
maproom vector-search --repo crewchief --query "authentication logic" --format agent
maproom vector-search --repo crewchief --query "error handling patterns" --format agent
maproom vector-search --repo crewchief --query "embedding generation pipeline" --format agent
```

Keep queries to 2-3 core technical terms (see search-best-practices.md for query transformation guidance).

### Context Command -- When You Need Relationships

Use the context command after finding a relevant chunk to understand how it connects to the rest of the codebase. Context reveals callers, callees, tests, and related configuration.

```bash
# Find a function first
maproom search --repo crewchief --query "extract_from_import" --kind func --format agent

# Then get its context (use chunk_id from search results)
maproom context --chunk-id 10833 --callers --callees
maproom context --chunk-id 10833 --callers --callees --tests --budget 8000
```

Context is particularly valuable for:
- Tracing call graphs to understand execution flow
- Finding test files that exercise a function
- Discovering configuration that affects behavior
- Understanding dependency chains between modules

## Documentation/Specs Repo Search Strategies

Docs repos contain design rationale, planning documents, architecture decisions, and project history. The chunk kinds are heading-based and section-based, which changes how you should search.

### Vector Search -- When You Need Intent or Rationale

Vector search is the default for docs repos because most queries seek conceptual understanding rather than exact terms.

```bash
maproom vector-search --repo crewchief-specs --query "plugin system design rationale" --format agent
maproom vector-search --repo crewchief-specs --query "why maproom uses SQLite" --format agent
maproom vector-search --repo crewchief-specs --query "architecture decisions embedding provider" --format agent
```

### Full-Text Search -- When You Have Specific Terms

Use FTS for ticket IDs, exact section names, specific terms, or document references.

**Ticket IDs:**

```bash
maproom search --repo crewchief-specs --query "MPRSKL" --format agent
maproom search --repo crewchief-specs --query "MAPMULTI" --format agent
```

**Section headings:**

```bash
maproom search --repo crewchief-specs --query "Risk Assessment" --format agent
maproom search --repo crewchief-specs --query "Acceptance Criteria" --format agent
```

**Specific technical terms:**

```bash
maproom search --repo crewchief-specs --query "incremental scanning" --format agent
```

### Exploration -- When You Need to Browse Structure

Use FTS with broad heading terms to discover document structure, then drill into specific sections.

```bash
# Find architecture documents
maproom search --repo crewchief-specs --query "architecture" --format agent

# Find planning documents
maproom search --repo crewchief-specs --query "planning analysis" --format agent

# Find decision records
maproom search --repo crewchief-specs --query "decision rationale" --format agent
```

Results from docs repos include `heading_1`, `heading_2`, and `heading_3` chunks that reveal the document hierarchy. Use the `file_relpath` and line numbers to navigate to specific sections.

## Cross-Repo Patterns

These patterns combine searches across code and docs repos to answer questions that neither repo can answer alone. Each pattern starts in one repo type and follows up in the other.

### Pattern 1: Intent-Implementation Bridge

**Goal:** Understand *why* something was built the way it is, then find *how* it is implemented.

**When to use:** You encounter unfamiliar code and need to understand the design decisions behind it.

**Steps:**

1. Search the docs/specs repo for design intent:
   ```bash
   maproom vector-search --repo crewchief-specs --query "plugin system design" --format agent
   ```

2. Extract key terms from the design document (function names, patterns, architecture components).

3. Search the code repo for the implementation using those terms:
   ```bash
   maproom search --repo crewchief --query "PluginManager" --format agent
   maproom context --chunk-id <id> --callers --callees
   ```

**Query optimization:** Start with vector search in specs (broad concepts), then switch to FTS in code (specific identifiers found in the specs).

### Pattern 2: Requirements Tracing

**Goal:** Find where a specific requirement is implemented in code.

**When to use:** You need to verify that a requirement has been implemented, or you need to modify code that implements a specific requirement.

**Steps:**

1. Find the requirement in specs:
   ```bash
   maproom search --repo crewchief-specs --query "MPRSKL" --format agent
   ```

2. Read the requirement to identify what it specifies (e.g., "scan must support incremental mode").

3. Search the code repo for the implementation:
   ```bash
   maproom search --repo crewchief --query "incremental scan" --format agent
   maproom search --repo crewchief --query "tree SHA comparison" --format agent
   ```

4. Use context to verify completeness:
   ```bash
   maproom context --chunk-id <id> --tests
   ```

**Query optimization:** Use FTS in specs with the ticket ID (exact match), then use a mix of FTS (for identifiers mentioned in the requirement) and vector search (for concepts) in the code repo.

### Pattern 3: Historical Context

**Goal:** Understand the evolution of a piece of code by finding the decision history that led to its current state.

**When to use:** You are considering changing code and need to know if there are constraints or past decisions that would affect the change.

**Steps:**

1. Identify the code area:
   ```bash
   maproom search --repo crewchief --query "ShadowMode" --format agent
   ```

2. Search specs for related decisions and history:
   ```bash
   maproom vector-search --repo crewchief-specs --query "shadow mode AB testing decision" --format agent
   maproom search --repo crewchief-specs --query "shadow mode" --format agent
   ```

3. Look for risk assessments and constraints:
   ```bash
   maproom vector-search --repo crewchief-specs --query "AB testing risks constraints" --format agent
   ```

**Query optimization:** Start with FTS in code to get exact names, then search specs using both the exact names (FTS) and the conceptual area (vector search). Specs often use different terminology than code, so vector search catches conceptual matches that FTS would miss.

### Cross-Repo Query Optimization Summary

| Starting Point | Specs Search Mode | Code Search Mode | Why |
|---|---|---|---|
| Concept/question | vector-search | FTS (with names from specs) | Specs use natural language; code uses identifiers |
| Ticket ID | FTS | FTS + vector-search | Ticket IDs are exact; implementations may vary |
| Code change | FTS (with code names) | (already in code) | Find decisions about specific components |
| Architecture question | vector-search | context (with chunk IDs) | Understand intent, then trace implementation |

**General rule:** Search specs for *why*, then search code for *how*. Use the terms you find in one repo to refine your search in the other.

## Troubleshooting Searches

### Zero Results -- Progressive Filter Relaxation

When a filtered search returns zero results, progressively relax filters to find relevant chunks. Remove one filter at a time to identify which constraint is too narrow.

**Scenario:** Searching for authentication functions in Python

```bash
# Initial attempt -- too narrow (both --kind and --lang filters)
maproom search --repo crewchief --query "authentication" --kind func --lang py --format agent
# Returns 0 results
```

**Step 1: Remove language filter** (keep `--kind`, search all languages for functions):

```bash
maproom search --repo crewchief --query "authentication" --kind func --format agent
# May find authentication functions in TypeScript, Rust, or other languages
```

**Step 2: Remove kind filter** (keep `--lang`, search all Python chunks):

```bash
maproom search --repo crewchief --query "authentication" --lang py --format agent
# May find authentication in class definitions, imports, or method bodies
```

**Step 3: Remove all filters** (broaden search completely):

```bash
maproom search --repo crewchief --query "authentication" --format agent
# Returns all chunks mentioning authentication across all files and languages
```

**Why this order:** Removing `--lang` first is usually more productive because the concept you are searching for may be implemented in a different language than expected. Removing `--kind` second catches cases where the logic lives in a class, method, or configuration rather than a standalone function. Removing all filters last gives the broadest view when earlier steps still return nothing.

## Configuration Setup Guide

This section explains how to configure maproom for multi-repo search in a new workspace.

### Step 1: Set Environment Variables

Add these to your shell profile or devcontainer configuration:

```bash
# For devcontainer environments
export MAPROOM_REPOS_ROOT=/workspace/repos
export MAPROOM_SPECS_ROOT=/workspace/_SPECS

# For local/laptop environments
export MAPROOM_REPOS_ROOT=~/git
export MAPROOM_SPECS_ROOT=~/_SPECS
```

### Step 2: Create the Configuration File

Copy the YAML template to your workspace root:

```bash
cp plugins/maproom/skills/maproom-search/templates/maproom-repos.yaml /workspace/maproom-repos.yaml
```

Edit the file to list your repositories. See the template for detailed field documentation. Each repo entry needs at minimum: `type`, `path`, and `description`.

### Step 3: Scan Each Repository

**IMPORTANT:** Scan each project directory separately. Do NOT scan a parent directory like `_SPECS/` -- this would merge all specs into a single repo index and make targeted searches impossible.

**Correct approach -- scan each project directory individually:**

```bash
# Scan the crewchief source code repo
maproom scan --path /workspace/repos/crewchief/crewchief --repo crewchief

# Scan the crewchief specs repo (separate index)
maproom scan --path /workspace/_SPECS/crewchief --repo crewchief-specs

# Scan the plugins repo
maproom scan --path /workspace/repos/claude-code-plugins --repo manifoldlogic/claude-code-plugins
```

**Incorrect approach -- do NOT do this:**

```bash
# WRONG: scanning the parent _SPECS directory merges all specs together
maproom scan --path /workspace/_SPECS --repo all-specs
```

Each `--repo` name should match the key used in your `maproom-repos.yaml` configuration file.

### Step 4: Verify Indexing

Confirm all repos are indexed and embeddings are available:

```bash
maproom status
```

Expected output shows each repository with its worktree and chunk count:

```
Repository: crewchief
  Worktree: main
    Chunks: 24,333

Repository: crewchief-specs
  Worktree: main
    Chunks: 1,200
```

If embeddings are missing (needed for vector-search), generate them:

```bash
maproom generate-embeddings --repo crewchief
maproom generate-embeddings --repo crewchief-specs
```

### Step 5: Test Searches

Run a test search against each repo to confirm they work:

```bash
# Test code repo FTS
maproom search --repo crewchief --query "scan" --k 3 --format agent

# Test docs repo FTS
maproom search --repo crewchief-specs --query "architecture" --k 3 --format agent

# Test vector search (requires embeddings)
maproom vector-search --repo crewchief --query "error handling" --k 3 --format agent
```

### No Config File Fallback

If `maproom-repos.yaml` is not present in the workspace, use `maproom status` to discover which repos are already indexed. The status output lists all repositories, worktrees, and chunk counts, providing enough information to construct search commands manually.
