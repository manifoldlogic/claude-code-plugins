# Maproom Troubleshooting

Common errors and solutions for crewchief-maproom.

## Quick Diagnostics

Check your current configuration:

```bash
# View current status
crewchief-maproom status

# Check database location
echo $MAPROOM_DATABASE_URL

# Check embedding configuration
env | grep MAPROOM_EMBEDDING
```

## Common Errors

### Dimension Mismatch

**Error Message:**
```
Error: Dimension mismatch: expected 1536 but got 1024
```

**Cause:**
Embedding provider configuration doesn't match the actual provider being used. This commonly occurs when:
- Ollama is auto-detected but config assumes OpenAI defaults
- Environment variables specify one provider but another is detected
- Model was changed but dimension wasn't updated

**Solution:**

1. **Set provider explicitly** (recommended):
   ```bash
   export MAPROOM_EMBEDDING_PROVIDER=ollama
   crewchief-maproom scan --path /your/repo
   ```

2. **Match dimension to your model**:
   ```bash
   export MAPROOM_EMBEDDING_DIMENSION=1024  # For Ollama mxbai-embed-large
   crewchief-maproom scan --path /your/repo
   ```

3. **Skip embeddings if not needed**:
   ```bash
   crewchief-maproom scan --path /your/repo --generate-embeddings=false
   ```

**Note:** As of MPRSKL.1001-1002, auto-detected Ollama should correctly infer dimension without manual configuration. If you're seeing this error with auto-detected Ollama, ensure you're using the latest version of crewchief-maproom.

**Prevention:**
- Use explicit `MAPROOM_EMBEDDING_PROVIDER` env var
- Let dimension be inferred from provider/model combination
- Only set `MAPROOM_EMBEDDING_DIMENSION` for custom models

---

### Repository Not Found

**Error Message:**
```
Error: Repository 'myproject' not found in index
```

**Cause:**
The repository hasn't been scanned yet, or was scanned with a different name.

**Solution:**

1. **List indexed repositories**:
   ```bash
   crewchief-maproom status
   ```

2. **Scan the repository**:
   ```bash
   crewchief-maproom scan --path /path/to/myproject --repo myproject
   ```

3. **Check exact repository name** - names are case-sensitive.

**Prevention:**
- Use consistent repository names across scans
- Check `crewchief-maproom status` before searching
- Use auto-detected names (based on git remote) when possible

---

### Vector Search Unavailable

**Error Message:**
```
Vector search not available for repository 'myproject'
```

**Cause:**
- Repository was scanned without embeddings (`--generate-embeddings=false`)
- Embedding generation failed during scan
- sqlite-vec extension not available

**Solution:**

1. **Rescan with embeddings**:
   ```bash
   crewchief-maproom scan --path /your/repo --generate-embeddings=true
   ```

2. **Check embedding configuration**:
   ```bash
   env | grep MAPROOM_EMBEDDING
   ```

3. **Verify embedding provider is accessible**:
   - For Ollama: `curl http://localhost:11434/api/tags`
   - For OpenAI: `echo $OPENAI_API_KEY`

4. **Use full-text search instead**:
   ```bash
   crewchief-maproom search --repo myproject --query "your query"
   ```

**Fallback:** Full-text search works without embeddings and covers many use cases. See [search-best-practices.md](./search-best-practices.md) for effective FTS strategies.

**Prevention:**
- Ensure embedding provider is running before scanning
- Set environment variables correctly for your provider
- Use `--generate-embeddings=true` when scanning (default)

---

## Configuration Verification

### Check Current Setup

```bash
# Database location
ls -lh ~/.maproom/maproom.db

# Embedding provider status
env | grep MAPROOM_EMBEDDING

# Indexed repositories
crewchief-maproom status
```

### Validate Embedding Provider

For Ollama:
```bash
curl http://localhost:11434/api/tags
# Should return list of models including mxbai-embed-large
```

For OpenAI:
```bash
echo $OPENAI_API_KEY
# Should be set with valid API key
```

For Google:
```bash
echo $GOOGLE_PROJECT_ID
echo $GOOGLE_APPLICATION_CREDENTIALS
# Both should be set correctly
```

### Test Search Functionality

```bash
# Test FTS search
crewchief-maproom search --repo myproject --query "test"

# Test vector search (requires embeddings)
crewchief-maproom vector-search --repo myproject --query "test functionality"
```

---

## Getting Help

If issues persist:
1. Check [CLI Reference](./cli-reference.md) for command syntax
2. Review [Search Best Practices](./search-best-practices.md) for usage patterns
3. Check logs for detailed error messages (set `RUST_LOG=debug`)
4. Verify embedding provider is accessible
5. Ensure database is not corrupted (try `crewchief-maproom db migrate`)
