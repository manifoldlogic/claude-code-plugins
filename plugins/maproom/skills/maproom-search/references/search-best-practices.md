# Maproom Search Best Practices

## Introduction

Maproom provides semantic code search that understands code concepts and relationships, not just exact text matches. The key to effective searches is transforming natural language questions into 2-3 core technical terms that capture the essence of what you are looking for. This reference documents query transformation principles and common anti-patterns to avoid.

## Query Transformation Principles

1. **Extract core concepts**: Remove filler words like "how", "what", "where", "show me", "find the" - these add noise without improving search results
2. **Keep it short**: 2-3 words maximum produces optimal results; longer queries dilute the semantic signal
3. **Use technical terms**: Prefer code-like terminology over descriptions (e.g., "authentication" not "logging in")
4. **Preserve identifiers**: Keep camelCase and snake_case names intact as they help identify specific code patterns
5. **Trust auto-detection**: Let SearchMode determine the optimal search type automatically based on your query pattern

## Anti-Patterns to Avoid

### 1. Full Sentence Queries

"How do I authenticate users in this application?" dilutes the signal with noise words like "How", "do", "I", "in", "this". **Fix**: Extract the core concept to `"authentication"` or `"user authentication"`.

### 2. Over-Specific Queries

"UserAuthenticationServiceImplV2Factory" might miss related implementations with different naming. **Fix**: Start broader with `"authentication"`, then narrow using context and file exploration.

### 3. Multiple Unrelated Concepts

"authentication database logging middleware" mixes unrelated concerns and confuses the search. **Fix**: Search each concept separately (`"authentication"`, then `"logging middleware"`), then correlate results.

### 4. No Status Check Before Search

Vector search requires embeddings to be available. Without checking, searches may fail or return poor results. **Fix**: Always run `status` first to verify embeddings are available for your repository.

### 5. Ignoring SearchMode Signals

Forcing `mode: "fts"` for conceptual queries like "error patterns" misses semantic variations that vector search would find. **Fix**: Trust auto-detection which selects the right mode for your query type.

### 6. Using Maproom for Exact Strings

Searching for `"TODO: fix this"` or `"FIXME"` is slow and inaccurate with semantic search. **Fix**: Use Grep tool for exact string matching, comments, and literal text searches.

### 7. Using Maproom for File Patterns

Searching `"*.test.ts"` or `"src/components/*.tsx"` fails because Maproom searches code content, not file paths. **Fix**: Use Glob tool for file pattern matching and path-based discovery.

### 8. Too Many Results Without Filtering

Broad conceptual searches return 100+ results, making it hard to find relevant code. **Fix**: Use filters like `filters: {file_type: "ts"}` to narrow scope, or `k: 5` to limit result count.

### 9. Not Using Context for Understanding

Reading individual chunks misses how code fits together with its callers, dependencies, and tests. **Fix**: Use `context` tool on relevant chunks to see relationships and understand the code structure.

### 10. Searching Without Deduplication

Duplicate code indexed across multiple worktrees clutters results with redundant matches. **Fix**: Use `deduplicate: true` (default) to group duplicates, or specify a `worktree` filter.

## Summary

Effective Maproom search requires extracting 2-3 core technical terms from questions and trusting SearchMode auto-detection. Remember the right tool for the job: use Grep for exact strings, Glob for file patterns, and Maproom for semantic code understanding. Always check status before vector search, and use the context tool to understand code relationships. Run `maproom search --help` for complete command details and available options.
