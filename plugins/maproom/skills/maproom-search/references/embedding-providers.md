# Embedding Provider Comparison

Maproom can embed code chunks with several providers: Google Vertex AI, OpenAI, Ollama, AWS Bedrock, and (in some builds) Cohere directly. This guide helps you choose one, configure it, and — critically — switch between them without silently corrupting your index.

**Provider availability differs between builds.** Do not assume a provider exists because it is documented here. Confirm against the binary you actually have: `maproom --help` lists the subcommands and environment variables your build supports, and the fastest check for a specific provider is to set `MAPROOM_EMBEDDING_PROVIDER=<name>` and see whether a small run is accepted at config time.

## Read This First: Dimension Is a Hard Schema Constraint

**Only 768, 1024, and 1536 dimensional vectors can be stored. There is no fourth option.**

The Postgres schema has fixed per-dimension columns — `embedding_768`, `embedding_1024`, `embedding_1536` — each with its own HNSW index. A model that emits any other dimension cannot be stored **at all**. Ollama's `qwen3-embedding:4b` (2560 dimensions), for example, is unusable no matter how good it is. Amazon Titan v2 can emit 256- or 512-dimensional vectors; those are rejected by a dimension validation step rather than failing after a full scan.

So model choice is constrained by the schema, not by taste. Before you pull a model or point at a new endpoint, answer one question: *does it emit 768, 1024, or 1536?* If not, stop.

`MAPROOM_EMBEDDING_DIMENSION` is **not** a free override. It does not reshape a model's output — a 2560-dimensional model does not become a 1024-dimensional model because you asked. Treat it as a declaration that must agree with both the model's real output width and the stored column set.

## Overview

Embedding providers convert code chunks into numerical vectors (embeddings) that enable semantic search. The provider you choose affects search quality, cost, throughput, and setup complexity.

**Important:** All code indexed with one provider must be searched with the same provider. Embeddings from different providers occupy incompatible vector spaces due to differing dimensions and training data. Switching providers requires regenerating embeddings **and deleting the old rows first** — see [Switching Providers or Models](#switching-providers-or-models). Skipping the delete does not error; it silently leaves blobs stranded at the old dimension.

## Provider Comparison Table

| Provider | Authentication | Setup Steps | Cost | Dimensions | Pros | Cons | When to Use |
|----------|---------------|-------------|------|------------|------|------|-------------|
| Google Vertex AI | Application Default Credentials or service account — **not an API key** | [ADC setup guide](./adc-setup.md) | Free tier available, then per-character pricing ([pricing](https://cloud.google.com/vertex-ai/pricing)) | 768 (`text-embedding-004`) | High quality embeddings; free tier; Google ecosystem integration | Requires GCP project; ADC expires and kills unattended runs | Teams already using Google Cloud; production environments with GCP infrastructure |
| OpenAI | API key (`OPENAI_API_KEY`) | Set environment variable | ~$0.02 per 1M tokens ([pricing](https://openai.com/api/pricing/)) | 1536 (`text-embedding-3-small`) | Simple API key setup; widely used; high quality | Requires paid API key; higher dimensions increase storage; network-dependent | Quick setup; teams already using OpenAI; when simplicity is preferred |
| Ollama | None (local) | Install Ollama, pull model, set `OLLAMA_URL` | Free (runs locally) | 1024 (`mxbai-embed-large`, default), 768 (`nomic-embed-text`) — other models only if they emit 768/1024/1536 | Free; fully offline; no credentials needed; data stays local | Requires local compute; model runner drops connections under load (see [Batching](#batching-parallelism-and-blast-radius)); devcontainer endpoint trap | Air-gapped environments; cost-sensitive workflows; local development without API keys |
| AWS Bedrock | AWS credential chain (env, profile, IRSA, container creds) | Set region + credentials | Per-token AWS pricing | 1024 (Titan v2, Cohere v3), 1536 (Titan v1) | Fits existing AWS IAM/VPC posture; no new credential system; managed scaling | **Not in every build**; Titan max batch is 1; Cohere silently truncates at 512 tokens | Teams already on AWS; environments where egress must stay inside a VPC |
| Cohere (direct) | API key (`MAPROOM_COHERE_API_KEY`) | Set environment variable | Per-token Cohere pricing | 1024 (v3 models) | Direct access without AWS | Availability varies by build; same 512-token truncation behavior as on Bedrock | You want Cohere v3 without an AWS account |

> **Pricing disclaimer:** Costs shown are approximate as of Feb 2026 and are subject to change. Always check the linked pricing pages for current rates.

## Detailed Setup Instructions

### Google Vertex AI

**Model:** `text-embedding-004`
**Dimensions:** 768 (stored in `embedding_768`)
**Endpoint:** `REGION-aiplatform.googleapis.com` (e.g., `us-central1-aiplatform.googleapis.com`)

Google Vertex AI uses **Application Default Credentials (ADC)**, not an API key. See the [ADC Setup Guide](./adc-setup.md) for complete step-by-step instructions.

> **The most common Google mistake:** setting `GEMINI_API_KEY` or `GOOGLE_API_KEY` does **nothing** for this provider. Neither variable is consulted. If you set one and embedding still fails to authenticate, that is why.

**Environment variables:**

```bash
# Set the embedding provider
export MAPROOM_EMBEDDING_PROVIDER=google

# Set your Google Cloud project ID (either name works)
export GOOGLE_PROJECT_ID=YOUR_PROJECT_ID
export MAPROOM_GOOGLE_PROJECT_ID=YOUR_PROJECT_ID

# Optional: override model (default: text-embedding-004)
export MAPROOM_EMBEDDING_MODEL=text-embedding-004
```

**Authentication options:**

1. **ADC (for interactive development):** Run `gcloud auth application-default login` and set a quota project. See [ADC Setup Guide](./adc-setup.md).
2. **Service account JSON (for unattended runs):** Set `GOOGLE_APPLICATION_CREDENTIALS` (or `MAPROOM_GOOGLE_APPLICATION_CREDENTIALS`) to the path of a service account key file.

```bash
# Service account authentication — required for cron/pm2 embedding jobs
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account-key.json
```

**ADC expires, and it fails loudly at config time.** When the refresh token has lapsed, every embedding pass dies immediately with:

```
Reauthentication failed. cannot prompt during non-interactive execution
```

This is not a network, quota, or model problem — it means nothing can prompt you for a browser login. Fix it by running `gcloud auth application-default login` in an interactive shell, or by switching the job to a service-account key. Any scheduled embedding job authenticating with user ADC **will** eventually stop with this error.

**Generate embeddings:**

```bash
maproom generate-embeddings
```

Run `maproom generate-embeddings --help` for the current flags on your binary.

### OpenAI

**Model:** `text-embedding-3-small`
**Dimensions:** 1536 (stored in `embedding_1536`)
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
```

**Cohere direct:** builds with a direct Cohere provider read `MAPROOM_COHERE_API_KEY`. The Cohere v3 models are the same ones offered through Bedrock, including the 512-token truncation behavior described below. Confirm your build accepts the provider value before planning around it.

**Generate embeddings:**

```bash
maproom generate-embeddings
```

### Ollama

**Models:** `mxbai-embed-large` (1024 dimensions, the default) and `nomic-embed-text` (768 dimensions)
**Dimensions:** determined by the model — and it must land on 768, 1024, or 1536 to be storable
**Endpoint:** from `OLLAMA_URL` (also `MAPROOM_OLLAMA_URL`)

Ollama runs embedding models locally and requires no authentication.

> **Do not pick an arbitrary embedding model.** Anything outside 768/1024/1536 cannot be stored — `qwen3-embedding:4b` at 2560 dimensions is the usual trap. Check the model's output width before you pull it.

**Step 1: Install Ollama**

```bash
# macOS / Linux — install on the HOST if you are working in a devcontainer
curl -fsSL https://ollama.com/install.sh | sh
```

See the [Ollama installation guide](https://ollama.com/download) for other platforms.

**Step 2: Pull an embedding model**

```bash
# Default: mxbai-embed-large (1024 dimensions -> embedding_1024)
ollama pull mxbai-embed-large

# Alternative: nomic-embed-text (768 dimensions -> embedding_768)
ollama pull nomic-embed-text
```

**Step 3: Set environment variables**

```bash
# Set the embedding provider
export MAPROOM_EMBEDDING_PROVIDER=ollama

# Set the model name
export MAPROOM_EMBEDDING_MODEL=mxbai-embed-large

# Endpoint — IN A DEVCONTAINER THIS MUST BE host.docker.internal
export OLLAMA_URL=http://host.docker.internal:11434
```

**Devcontainer endpoint trap.** Inside a container, `localhost:11434` is *not* the host's Ollama — it is the container's own empty loopback. There is no auto-detection to rely on: set `OLLAMA_URL` (or `MAPROOM_OLLAMA_URL`) to `http://host.docker.internal:11434` explicitly. If embedding fails to connect at all, check this before anything else:

```bash
curl -s http://host.docker.internal:11434/api/tags | head
```

**Step 4: Generate embeddings**

Ollama has to be running **on the host** — start it there (`ollama serve`), not inside the container. A server started in the container answers on the container's own `localhost:11434`, which is exactly the endpoint trap above. Confirm the host's Ollama is reachable, then run the pass:

```bash
# Verify the host's Ollama answers at the configured endpoint
curl -s http://host.docker.internal:11434/api/tags | head

# Generate embeddings
maproom generate-embeddings
```

**Oversized chunks:** Ollama's own context limits apply, and oversized inputs are **truncated rather than rejected**. A ~107 KB chunk embedded without error in testing — it was simply cut off. You will not get a warning about lost tail content.

### AWS Bedrock

**Provider value:** `MAPROOM_EMBEDDING_PROVIDER=bedrock`

> **Availability caveat — read before planning around this.** Bedrock support is **not present in every maproom build**. Confirm against your own binary (`maproom --help`, and whether `MAPROOM_EMBEDDING_PROVIDER=bedrock` is accepted) rather than assuming. Treat it as a provider *option*, not a guaranteed feature.

#### Models

| Model ID | Dimensions | Max batch | Notes |
|----------|-----------|-----------|-------|
| `amazon.titan-embed-text-v2:0` | 1024 | 1 | **Default.** Stored in `embedding_1024`. |
| `amazon.titan-embed-text-v1` | 1536 | 1 | Stored in `embedding_1536`. |
| `cohere.embed-english-v3` | 1024 | 96 | Embeds at most 512 tokens; silently truncates. |
| `cohere.embed-multilingual-v3` | 1024 | 96 | Embeds at most 512 tokens; silently truncates. |

(Dimensions and batch limits are from the provider's own documentation.)

**Titan v2's 256 and 512 dimensional modes are unusable.** The model can emit them, but maproom has column sets only for 768/1024/1536, so a dimension validation step rejects them up front — you find out at configuration time rather than after a full scan. Use 1024.

**Cohere v3 silently truncates at 512 tokens.** Anything longer is embedded from its first 512 tokens with no error and no warning. For code chunks that routinely exceed that, the tail of the chunk contributes nothing to the vector, and search quality degrades in a way that looks like "semantic search is just bad here" rather than like a bug. If your chunks are large, prefer Titan or a provider without the limit.

**Titan's max batch of 1 means there is no request batching.** One HTTP request per chunk. Throughput comes entirely from concurrency (see [Batching, Parallelism, and Blast Radius](#batching-parallelism-and-blast-radius)), not from raising the pipeline batch size. Cohere v3's max batch of 96 does batch, so it can amortize request overhead across chunks; that difference has not been measured here, so treat it as a reason to test rather than a promised speedup.

#### Configuration

```bash
export MAPROOM_EMBEDDING_PROVIDER=bedrock

# Region — falls back to AWS_REGION, then AWS_DEFAULT_REGION
export MAPROOM_BEDROCK_REGION=us-east-1

# Model (default: amazon.titan-embed-text-v2:0)
export MAPROOM_EMBEDDING_MODEL=amazon.titan-embed-text-v2:0

# Optional: custom endpoint for VPC endpoints or local testing.
# Also honored: AWS_ENDPOINT_URL_BEDROCK_RUNTIME, AWS_ENDPOINT_URL
export MAPROOM_BEDROCK_ENDPOINT_URL=https://vpce-....bedrock-runtime.us-east-1.vpce.amazonaws.com

# Optional: use FIPS endpoints
export MAPROOM_BEDROCK_USE_FIPS=true

# Optional: select a named profile (also AWS_PROFILE)
export MAPROOM_AWS_PROFILE=my-profile
```

#### Credentials

Credentials resolve through a standard AWS chain, so an environment that already runs AWS CLI or SDK workloads generally needs no new configuration:

1. **Static environment keys** — `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`.
2. **Shared config and credentials files** — `AWS_CONFIG_FILE`, `AWS_SHARED_CREDENTIALS_FILE`, honoring `AWS_PROFILE`.
3. **Web identity / IRSA** — `AWS_WEB_IDENTITY_TOKEN_FILE` together with `AWS_ROLE_ARN` and `AWS_ROLE_SESSION_NAME`. This is the Kubernetes/EKS path.
4. **Container credentials** — `AWS_CONTAINER_CREDENTIALS_FULL_URI` or `AWS_CONTAINER_CREDENTIALS_RELATIVE_URI`, with `AWS_CONTAINER_AUTHORIZATION_TOKEN` or `AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE`. This is the ECS/Fargate path.

If a run fails to authenticate, work down that list and confirm which step you *intended* to supply credentials — a stale `AWS_PROFILE` shadowing IRSA is the usual surprise.

#### Request handling

- **30 s** per-request timeout.
- **90 s** batch timeout.
- Up to **4 retries** with exponential backoff from a **500 ms** base.

Throttling from Bedrock is therefore absorbed silently up to a point; if a pass is much slower than expected without failing, you are probably being throttled and retried rather than stalled.

**Generate embeddings:**

```bash
maproom generate-embeddings
```

## Batching, Parallelism, and Blast Radius

Providers are called in **sub-batches** inside each pipeline batch. Three environment variables control this:

| Variable | Default | Effect |
|----------|---------|--------|
| `MAPROOM_EMBEDDING_PARALLEL_ENABLED` | — | Turns sub-batch parallelism on or off. |
| `MAPROOM_EMBEDDING_PARALLEL_SUB_BATCH_SIZE` | 50 | Texts per provider request group. |
| `MAPROOM_EMBEDDING_PARALLEL_MAX_CONCURRENCY` | 8 | In-flight sub-batches. |

**The rule that catches people: the pipeline batch size must EXCEED the sub-batch size, or parallelism never engages.** With the default sub-batch size of 50, a batch size of 50 or below runs fully serialized — you get no concurrency and no explanation. If throughput looks like one request at a time, check this ratio first.

Measured against local Ollama, throughput improved up to **~8 concurrent requests** and got **worse at 16**. Eight is the sweet spot; raising `MAPROOM_EMBEDDING_PARALLEL_MAX_CONCURRENCY` past it is not free.

**One bad sub-batch fails the whole batch.** If a single sub-batch errors, maproom marks the **entire pipeline batch** failed — every chunk in it, not just the 50 that failed. Observed with Ollama when the model runner drops the connection:

```
Sub-batch 2 failed: API error: Bad request: Batch of 50 texts rejected: {"error":"Post \"http://127.0.0.1:51950/tokenize\": EOF"}
```

These failures are **transient and self-heal on the next pass**, so a loop converges — but batch size sets the blast radius. With `--batch-size 1000` each incident cost 1,000 chunks; at 500 it cost 500. Pick a batch size that is comfortably above the sub-batch size (so parallelism engages) but not so large that one flaky sub-batch throws away a huge pass.

Separately, keep each pass **bounded**: the pending-chunk query runs under a 5 s statement timeout that unbounded passes eventually exceed at scale. Bound the pass and loop until the pending count reaches zero. Run `maproom generate-embeddings --help` for the current flags on your binary.

## Switching Providers or Models

Switching embedding providers — **or just switching models within one provider** — requires regenerating embeddings, because:

1. **Different dimensions:** Google produces 768-dimensional vectors, OpenAI 1536, Ollama `mxbai-embed-large` 1024, Bedrock Titan v1 1536 and Titan v2 / Cohere v3 1024. Vectors of different widths live in different columns and cannot be compared.
2. **Different vector spaces:** even at matching dimensions, each model maps concepts to different coordinates. Cosine similarity between vectors from different models is meaningless.

### You MUST delete the old rows first

`code_embeddings` holds **one row per `blob_sha`, with a UNIQUE constraint on `blob_sha`**. A blob that already has a row at the old dimension **keeps it**: incremental runs see a row exists and skip the blob, while vector search at the new dimension cannot see it. The blob is stranded — embedded, but invisible.

Nothing errors. Coverage numbers still look plausible. Search still returns results (non-vector ranking is unaffected). You simply get worse semantic results forever.

**To switch:**

```bash
# 1. Check what you currently have. Healthy = exactly one row of output.
psql "$MAPROOM_DATABASE_URL" -c \
  "select embedding_dim, model_version, count(*) from code_embeddings group by 1,2;"

# 2. Set the new provider environment variables (see provider sections above)
export MAPROOM_EMBEDDING_PROVIDER=openai
export OPENAI_API_KEY=YOUR_OPENAI_API_KEY

# 3. DELETE the rows at the old dimension / old model. This step is mandatory.
psql "$MAPROOM_DATABASE_URL" -c \
  "delete from code_embeddings where embedding_dim = 1024;"
# (or, when staying at the same width but changing model:)
psql "$MAPROOM_DATABASE_URL" -c \
  "delete from code_embeddings where model_version = 'OLD_MODEL_VERSION';"

# 4. Regenerate, in bounded passes, until the pending count reaches zero
maproom generate-embeddings

# 5. Verify homogeneity again — one row, the new dimension and model
psql "$MAPROOM_DATABASE_URL" -c \
  "select embedding_dim, model_version, count(*) from code_embeddings group by 1,2;"

# 6. Verify vector search works with the new provider
maproom vector-search --repo YOUR_REPO --query "test query" --format agent
```

The verification query in steps 1 and 5 is the whole game:

```sql
select embedding_dim, model_version, count(*) from code_embeddings group by 1,2;
```

**More than one row means your index is mixed** — some blobs are still at the old dimension or old model, and vector search silently ignores them. Delete and regenerate until this query returns a single row.

Two notes on step 6: `--repo` matches the *indexed* repo name (derived from the git origin), not the directory on disk, so a zero-hit result may be a name mismatch rather than a bad switch — list indexed names with `maproom status`. And embedding coverage decays on its own as watchers process changes, so a fresh gap after a switch is not necessarily a switch problem; re-run `generate-embeddings` on a schedule regardless.

**Warning:** until embeddings are regenerated, vector search results will be unreliable or empty. Non-vector search (`maproom search`) is unaffected by provider changes since it does not use embeddings.

## Environment Variable Summary

`maproom --help` lists the subcommands and environment variables your build supports; treat that as authoritative over this table.

| Variable | Description | Example |
|----------|-------------|---------|
| `MAPROOM_EMBEDDING_PROVIDER` | Provider selection | `ollama`, `openai`, `google`, `bedrock` |
| `MAPROOM_EMBEDDING_MODEL` | Model override | `mxbai-embed-large`, `text-embedding-004`, `amazon.titan-embed-text-v2:0` |
| `MAPROOM_EMBEDDING_DIMENSION` | Declared dimension — must be 768, 1024, or 1536 **and** match what the model emits | `768`, `1024`, `1536` |
| `MAPROOM_EMBEDDING_PARALLEL_ENABLED` | Enable sub-batch parallelism | `true` |
| `MAPROOM_EMBEDDING_PARALLEL_SUB_BATCH_SIZE` | Texts per sub-batch (default 50) | `50` |
| `MAPROOM_EMBEDDING_PARALLEL_MAX_CONCURRENCY` | In-flight sub-batches (default 8) | `8` |
| `OLLAMA_URL` / `MAPROOM_OLLAMA_URL` | Ollama endpoint — `host.docker.internal` in a devcontainer | `http://host.docker.internal:11434` |
| `OPENAI_API_KEY` / `MAPROOM_OPENAI_API_KEY` | OpenAI API key | `sk-...` (placeholder) |
| `MAPROOM_COHERE_API_KEY` | Cohere API key (direct, not via Bedrock) | placeholder |
| `GOOGLE_PROJECT_ID` / `MAPROOM_GOOGLE_PROJECT_ID` | Google Cloud project ID | `YOUR_PROJECT_ID` |
| `GOOGLE_APPLICATION_CREDENTIALS` / `MAPROOM_GOOGLE_APPLICATION_CREDENTIALS` | Path to service account JSON | `/path/to/key.json` |
| `MAPROOM_BEDROCK_REGION` | Bedrock region (falls back to `AWS_REGION`, `AWS_DEFAULT_REGION`) | `us-east-1` |
| `MAPROOM_BEDROCK_ENDPOINT_URL` | Custom Bedrock endpoint (also `AWS_ENDPOINT_URL_BEDROCK_RUNTIME`, `AWS_ENDPOINT_URL`) | VPC endpoint URL |
| `MAPROOM_BEDROCK_USE_FIPS` | Use FIPS endpoints | `true` |
| `MAPROOM_AWS_PROFILE` / `AWS_PROFILE` | AWS profile selection | `my-profile` |

Note that `GEMINI_API_KEY` and `GOOGLE_API_KEY` are **not** in this table on purpose — they do nothing for the Google provider.

## FAQ

### Can I switch providers after indexing?

Not without regenerating — and not by regenerating alone. You must **delete the existing `code_embeddings` rows at the old dimension/model first**, because the UNIQUE constraint on `blob_sha` means an existing row causes the blob to be skipped rather than re-embedded. See [Switching Providers or Models](#switching-providers-or-models).

### Can I use any Ollama model I like?

No. The model must emit 768, 1024, or 1536 dimensions — those are the only stored columns. `mxbai-embed-large` (1024) and `nomic-embed-text` (768) work. Models like `qwen3-embedding:4b` (2560) cannot be stored at all.

### Can I use multiple providers simultaneously?

Not within one searchable set of embeddings. Every blob must be embedded by the same model at the same dimension; the verification query in [Switching Providers or Models](#switching-providers-or-models) should return exactly one row. Mixing providers strands whichever half does not match the current search dimension.

### Does the provider affect non-vector search?

No. Full-text and structural ranking do not involve embeddings at all — that is why an index with zero embeddings still returns search results. Provider configuration only affects `vector-search` and `generate-embeddings`. Do not infer embedding health from search working; check coverage explicitly.

### Which provider should I choose if I am unsure?

- No API keys, want to start now: **Ollama** (free, local — just remember the `OLLAMA_URL` devcontainer trap).
- Already have an OpenAI key: **OpenAI** (simplest cloud setup).
- Team on Google Cloud: **Google Vertex AI** (but use a service account for any scheduled job).
- Team on AWS, egress must stay in a VPC: **Bedrock**, if your build has it.

### Do higher dimensions mean better search quality?

Not necessarily. Dimension count reflects the model's internal representation, not search quality directly. OpenAI's 1536-dimensional embeddings and Google's 768-dimensional embeddings both produce high-quality semantic search results. Higher dimensions do increase storage requirements and may slightly increase search latency. Dimension is mostly a *storage compatibility* question here, not a quality dial.

### What happens if my API key or credentials expire during embedding generation?

The run fails. For Google, an expired ADC session fails at config time with `Reauthentication failed. cannot prompt during non-interactive execution` — refresh with `gcloud auth application-default login`, or move the job to a service-account key (see [ADC Setup Guide](./adc-setup.md)). For OpenAI/Cohere, update the key. For Bedrock, check which step of the credential chain was supposed to supply credentials. Then re-run `generate-embeddings`; already-embedded blobs are skipped, so a re-run picks up where it left off.

### Why did one bad chunk kill 1,000 chunks?

Because a failed sub-batch fails the entire pipeline batch. See [Batching, Parallelism, and Blast Radius](#batching-parallelism-and-blast-radius) — the failures are transient, so looping converges, but a smaller batch size limits the damage per incident.

## Related Documentation

- [ADC Setup Guide](./adc-setup.md) - Google Application Default Credentials setup for DevContainer
- [Troubleshooting](./troubleshooting.md) - Common error messages and recovery steps
- [Search Best Practices](./search-best-practices.md) - Query optimization techniques
- [Google Vertex AI Pricing](https://cloud.google.com/vertex-ai/pricing) - Official Google Cloud pricing
- [OpenAI API Pricing](https://openai.com/api/pricing/) - Official OpenAI pricing
- [Ollama](https://ollama.com/) - Official Ollama website and documentation
- [Amazon Bedrock](https://docs.aws.amazon.com/bedrock/) - Official Bedrock documentation

---

*Last Updated: Sep 2026 — provider behavior verified against maproom CLI 0.3.0 with a PostgreSQL 16 + pgvector backend. Confirm provider availability against your own binary.*
