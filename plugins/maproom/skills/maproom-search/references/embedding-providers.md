# Embedding Provider Comparison

Maproom supports three embedding providers for vector search: Google Vertex AI, OpenAI, and Ollama. This guide helps you choose the right provider and configure it for your environment.

## Overview

Embedding providers convert code chunks into numerical vectors (embeddings) that enable semantic search. The provider you choose affects search quality, cost, and setup complexity.

**Important:** All code indexed with one provider must be searched with the same provider. Embeddings from different providers occupy incompatible vector spaces due to differing dimensions and training data. Switching providers requires re-indexing your entire repository.

## Provider Comparison Table

| Provider | Authentication | Setup Steps | Cost | Dimensions | Pros | Cons | When to Use |
|----------|---------------|-------------|------|------------|------|------|-------------|
| Google Vertex AI | ADC or service account (`GOOGLE_APPLICATION_CREDENTIALS`) | [ADC setup guide](./adc-setup.md) | Free tier available, then per-character pricing ([pricing](https://cloud.google.com/vertex-ai/pricing)) | 768 (`text-embedding-004`) | High quality embeddings; free tier; Google ecosystem integration | Requires GCP project; ADC credentials expire and need refresh | Teams already using Google Cloud; production environments with GCP infrastructure |
| OpenAI | API key (`OPENAI_API_KEY`) | Set environment variable | ~$0.02 per 1M tokens ([pricing](https://openai.com/api/pricing/)) | 1536 (`text-embedding-3-small`) | Simple API key setup; widely used; high quality | Requires paid API key; higher dimensions increase storage; network-dependent | Quick setup; teams already using OpenAI; when simplicity is preferred |
| Ollama | None (local) | Install Ollama and pull model | Free (runs locally) | Varies by model (768 for `nomic-embed-text`, 1024 for `mxbai-embed-large`) | Free; fully offline; no credentials needed; data stays local | Requires local compute resources; quality varies by model; slower on CPU | Air-gapped environments; cost-sensitive workflows; local development without API keys |

> **Pricing disclaimer:** Costs shown are approximate as of Feb 2026 and are subject to change. Always check the linked pricing pages for current rates.

## Detailed Setup Instructions

### Google Vertex AI

**Model:** `text-embedding-004`
**Dimensions:** 768
**Endpoint:** `REGION-aiplatform.googleapis.com` (e.g., `us-central1-aiplatform.googleapis.com`)

Google Vertex AI uses Application Default Credentials (ADC) for authentication. See the [ADC Setup Guide](./adc-setup.md) for complete step-by-step instructions.

**Environment variables:**

```bash
# Set the embedding provider
export MAPROOM_EMBEDDING_PROVIDER=google

# Set your Google Cloud project ID
export MAPROOM_GOOGLE_PROJECT_ID=YOUR_PROJECT_ID

# Optional: override model (default: text-embedding-004)
export MAPROOM_EMBEDDING_MODEL=text-embedding-004

# Optional: override dimensions (default: 768)
export MAPROOM_EMBEDDING_DIMENSION=768
```

**Authentication options:**

1. **ADC (recommended for development):** Run `gcloud auth application-default login` and set a quota project. See [ADC Setup Guide](./adc-setup.md).
2. **Service account JSON:** Set `GOOGLE_APPLICATION_CREDENTIALS` to the path of a service account key file.

```bash
# Service account authentication
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account-key.json
```

**Generate embeddings:**

```bash
maproom generate-embeddings
```

### OpenAI

**Model:** `text-embedding-3-small`
**Dimensions:** 1536
**Endpoint:** `api.openai.com/v1/embeddings`

OpenAI uses a simple API key for authentication.

**Environment variables:**

```bash
# Set the embedding provider
export MAPROOM_EMBEDDING_PROVIDER=openai

# Set your OpenAI API key (use MAPROOM_ prefix or standard name)
export MAPROOM_OPENAI_API_KEY=YOUR_OPENAI_API_KEY
# or
export OPENAI_API_KEY=YOUR_OPENAI_API_KEY

# Optional: override model (default: text-embedding-3-small)
export MAPROOM_EMBEDDING_MODEL=text-embedding-3-small

# Optional: override dimensions (default: 1536)
export MAPROOM_EMBEDDING_DIMENSION=1536
```

**Generate embeddings:**

```bash
maproom generate-embeddings
```

### Ollama

**Models:** `nomic-embed-text` (768 dimensions), `mxbai-embed-large` (1024 dimensions), and others
**Dimensions:** Auto-detected from model name
**Endpoint:** `localhost:11434/api/embed` (auto-detects Docker networking)

Ollama runs embedding models locally and requires no authentication.

**Step 1: Install Ollama**

```bash
# macOS / Linux
curl -fsSL https://ollama.com/install.sh | sh
```

See the [Ollama installation guide](https://ollama.com/download) for other platforms.

**Step 2: Pull an embedding model**

```bash
# Recommended: nomic-embed-text (768 dimensions, good quality-to-size ratio)
ollama pull nomic-embed-text

# Alternative: mxbai-embed-large (1024 dimensions, higher quality, more resources)
ollama pull mxbai-embed-large
```

**Step 3: Set environment variables**

```bash
# Set the embedding provider
export MAPROOM_EMBEDDING_PROVIDER=ollama

# Set the model name
export MAPROOM_EMBEDDING_MODEL=nomic-embed-text

# Optional: override dimensions (auto-detected from model name)
export MAPROOM_EMBEDDING_DIMENSION=768
```

**Step 4: Generate embeddings**

```bash
# Ensure Ollama is running
ollama serve &

# Generate embeddings
maproom generate-embeddings
```

**Docker networking note:** The CLI auto-detects Docker environments and adjusts the Ollama endpoint accordingly. If Ollama runs on the Docker host and the CLI runs inside a container, the CLI resolves the endpoint automatically.

## Re-Indexing When Switching Providers

Switching embedding providers requires regenerating all embeddings because:

1. **Different dimensions:** Google produces 768-dimensional vectors, OpenAI produces 1536-dimensional vectors, and Ollama dimensions vary by model. These vectors cannot be compared.
2. **Different vector spaces:** Even if dimensions matched, each provider's model maps concepts to different coordinates. Cosine similarity scores between vectors from different providers are meaningless.

**To switch providers:**

```bash
# 1. Set the new provider environment variables (see provider sections above)
export MAPROOM_EMBEDDING_PROVIDER=openai
export OPENAI_API_KEY=YOUR_OPENAI_API_KEY

# 2. Regenerate all embeddings with the new provider
maproom generate-embeddings

# 3. Verify vector search works with the new provider
maproom vector-search --repo YOUR_REPO --query "test query" --format agent
```

**Warning:** Until embeddings are regenerated, vector search results will be unreliable or empty. Full-text search (`maproom search`) is unaffected by provider changes since it does not use embeddings.

## Environment Variable Summary

| Variable | Description | Example |
|----------|-------------|---------|
| `MAPROOM_EMBEDDING_PROVIDER` | Provider selection | `ollama`, `openai`, `google` |
| `MAPROOM_EMBEDDING_MODEL` | Model override | `text-embedding-004`, `text-embedding-3-small`, `nomic-embed-text` |
| `MAPROOM_EMBEDDING_DIMENSION` | Dimension override | `768`, `1536`, `1024` |
| `OPENAI_API_KEY` | OpenAI API key | `sk-...` (placeholder) |
| `MAPROOM_OPENAI_API_KEY` | OpenAI API key (prefixed) | `sk-...` (placeholder) |
| `GOOGLE_APPLICATION_CREDENTIALS` | Path to service account JSON | `/path/to/key.json` |
| `GOOGLE_PROJECT_ID` | Google Cloud project ID | `YOUR_PROJECT_ID` |
| `MAPROOM_GOOGLE_PROJECT_ID` | Google Cloud project ID (prefixed) | `YOUR_PROJECT_ID` |

## FAQ

### Can I switch providers after indexing?

No, not without re-indexing. Embeddings from different providers are incompatible because they use different dimensions and map to different vector spaces. You must regenerate all embeddings after switching providers. See [Re-Indexing When Switching Providers](#re-indexing-when-switching-providers).

### Can I use multiple providers simultaneously?

Not for the same repository. Each repository's embeddings must be generated with a single provider. However, you can use different providers for different repositories by setting the appropriate environment variables before running `generate-embeddings` for each repository.

### Does the provider affect full-text search (FTS)?

No. Full-text search uses SQLite FTS5 indexes and does not involve embeddings at all. Provider configuration only affects `vector-search` and `generate-embeddings` commands.

### Which provider should I choose if I am unsure?

- If you have no API keys and want to get started quickly, use **Ollama** (free, local, no setup beyond installation).
- If you already have an OpenAI API key, use **OpenAI** (simplest cloud setup).
- If your team uses Google Cloud, use **Google Vertex AI** (best integration with GCP tooling).

### Do higher dimensions mean better search quality?

Not necessarily. Dimension count reflects the model's internal representation, not search quality directly. OpenAI's 1536-dimensional embeddings and Google's 768-dimensional embeddings both produce high-quality semantic search results. Higher dimensions do increase storage requirements and may slightly increase search latency.

### What happens if my API key or credentials expire during embedding generation?

The `generate-embeddings` command will fail mid-process. Refresh your credentials (see [ADC Setup Guide](./adc-setup.md) for Google, or update your API key for OpenAI), then re-run `generate-embeddings`. The CLI will resume or regenerate as needed.

## Related Documentation

- [ADC Setup Guide](./adc-setup.md) - Google Application Default Credentials setup for DevContainer
- [Troubleshooting](./troubleshooting.md) - Common error messages and recovery steps
- [Search Best Practices](./search-best-practices.md) - Query optimization techniques
- [Google Vertex AI Pricing](https://cloud.google.com/vertex-ai/pricing) - Official Google Cloud pricing
- [OpenAI API Pricing](https://openai.com/api/pricing/) - Official OpenAI pricing
- [Ollama](https://ollama.com/) - Official Ollama website and documentation

---

*Last Updated: Feb 2026*
