# Google ADC Setup for DevContainer

Step-by-step guide for configuring Google Application Default Credentials (ADC) in a DevContainer environment. ADC is required when using Google Vertex AI as the embedding provider for maproom vector search.

## Prerequisites

- **gcloud CLI** installed (already available in the DevContainer)
- **Google Cloud project** with the Vertex AI API enabled
- **Project ID** (find yours at [console.cloud.google.com](https://console.cloud.google.com/))

To verify gcloud is installed:

```bash
command -v gcloud
# Expected: /usr/bin/gcloud or similar path
```

## Initial Setup

### Step 1: Login to Google Cloud

```bash
gcloud auth application-default login --no-launch-browser
```

The `--no-launch-browser` flag is required in DevContainer and SSH sessions where a browser cannot be opened automatically. The command will print a URL and prompt you to:

1. Open the URL in a browser on your local machine
2. Authenticate with your Google account
3. Copy the authorization code
4. Paste the code back into the terminal

After successful login, credentials are saved to:

```
~/.config/gcloud/application_default_credentials.json
```

### Step 2: Set Quota Project

Google API calls require a quota project for billing and rate limiting. Set it with:

```bash
gcloud auth application-default set-quota-project YOUR_PROJECT_ID
```

Replace `YOUR_PROJECT_ID` with your actual Google Cloud project ID.

**Why this is needed:** Without a quota project, API calls to Vertex AI will fail with a "quota_project_id is required" error. The quota project determines which project is billed for API usage and which project's quotas apply.

### Step 3: Set Environment Variables

Configure maproom to use Google Vertex AI as the embedding provider:

```bash
export MAPROOM_EMBEDDING_PROVIDER=google
export MAPROOM_GOOGLE_PROJECT_ID=YOUR_PROJECT_ID
```

### Step 4: Verify Credentials

```bash
gcloud auth application-default print-access-token
```

If this prints a long token string (starting with `ya29.`), ADC is configured correctly. If it prints an error, see the [Troubleshooting](#troubleshooting) section below.

### Step 5: Test Vector Search

```bash
crewchief-maproom vector-search --repo YOUR_REPO --query "test query" --format agent
```

If this returns search results without credential errors, setup is complete.

## Refreshing Expired Credentials

ADC tokens expire after a period of time. When they expire, vector search will fail with credential errors.

**Symptoms of expired ADC:**

```
Error: Failed to create embedding service.

Caused by:
    0: Configuration error: Invalid configuration value for credentials:
       Failed to create token provider from ADC
```

or errors containing `invalid_rapt`.

**Resolution:**

Re-run the login and quota project commands:

```bash
# Step 1: Re-authenticate
gcloud auth application-default login --no-launch-browser

# Step 2: Re-set quota project (required after re-login)
gcloud auth application-default set-quota-project YOUR_PROJECT_ID

# Step 3: Verify
gcloud auth application-default print-access-token
```

## Troubleshooting

### Error: "Failed to create token provider from ADC"

**Full error:**

```
Error: Failed to create embedding service.

Caused by:
    0: Configuration error: Invalid configuration value for credentials:
       Failed to create token provider from ADC
```

**Root cause:** ADC credentials are missing or have expired.

**Resolution:**

1. Check if the credentials file exists:
   ```bash
   ls -la ~/.config/gcloud/application_default_credentials.json
   ```
2. If the file is missing, run the initial setup (Step 1 and Step 2 above).
3. If the file exists but the error persists, the token has expired. Refresh credentials:
   ```bash
   gcloud auth application-default login --no-launch-browser
   gcloud auth application-default set-quota-project YOUR_PROJECT_ID
   ```

### Error: "invalid_rapt"

**Root cause:** The RAPT (Re-Auth Policy Token) has expired. This is the same as token expiry but specific to organizations with re-authentication policies.

**Resolution:** Re-run the login command:

```bash
gcloud auth application-default login --no-launch-browser
gcloud auth application-default set-quota-project YOUR_PROJECT_ID
```

### Error: "quota_project_id is required"

**Root cause:** The quota project was not set, or the credentials file does not contain a `quota_project_id` field.

**Resolution:**

```bash
gcloud auth application-default set-quota-project YOUR_PROJECT_ID
```

Verify the quota project is set by inspecting the credentials file:

```bash
grep quota_project_id ~/.config/gcloud/application_default_credentials.json
# Expected output: "quota_project_id": "YOUR_PROJECT_ID"
```

### Error: "Could not find default credentials"

**Root cause:** No ADC credentials file exists. The `gcloud auth application-default login` command has not been run, or the credentials file was deleted.

**Resolution:** Run the full initial setup starting at [Step 1](#step-1-login-to-google-cloud).

### Error: "Permission denied" on Vertex AI API

**Root cause:** The Vertex AI API is not enabled for your project, or your account does not have the required IAM permissions.

**Resolution:**

1. Enable the Vertex AI API:
   ```bash
   gcloud services enable aiplatform.googleapis.com --project=YOUR_PROJECT_ID
   ```
2. Verify your account has the `aiplatform.endpoints.predict` permission (typically granted through the "Vertex AI User" role).

## Security Notes

**Credential file location:**

```
~/.config/gcloud/application_default_credentials.json
```

**File permissions:** The credentials file should be readable only by your user:

```bash
chmod 600 ~/.config/gcloud/application_default_credentials.json
```

**Do NOT commit credentials to git.** The `~/.config/gcloud/` directory should never be added to version control. If your `.gitignore` does not already exclude it, add:

```
.config/gcloud/
```

**Token rotation:** ADC tokens expire periodically. Re-run `gcloud auth application-default login` when tokens expire. There is no way to set a permanent, non-expiring ADC token (this is a security feature).

**Service account keys:** If using service account JSON keys (`GOOGLE_APPLICATION_CREDENTIALS`), store them securely, rotate them regularly, and never commit them to version control.

## DevContainer-Specific Notes

- **No browser access:** DevContainers and SSH sessions cannot open a browser. Always use the `--no-launch-browser` flag with `gcloud auth application-default login`.
- **Credential persistence:** ADC credentials are stored at `~/.config/gcloud/application_default_credentials.json` inside the container. If the container is rebuilt, credentials will need to be refreshed.
- **Volume mounts:** If your DevContainer mounts `~/.config/gcloud/` from the host, credentials set on the host will be available inside the container without re-authentication. Check your `devcontainer.json` for volume mount configuration.
- **gcloud CLI availability:** The DevContainer post-create script installs gcloud CLI. Verify with `command -v gcloud` after container creation.

## Verification Checklist

Use this checklist to confirm ADC is fully configured:

- [ ] ADC credentials file exists: `ls ~/.config/gcloud/application_default_credentials.json`
- [ ] Credentials file contains quota project: `grep quota_project_id ~/.config/gcloud/application_default_credentials.json`
- [ ] Access token is valid: `gcloud auth application-default print-access-token` (prints a token, not an error)
- [ ] Vector search works: `crewchief-maproom vector-search --repo YOUR_REPO --query "test" --format agent` (returns results without credential errors)

## Related Documentation

- [Embedding Provider Comparison](./embedding-providers.md) - Compare Google Vertex AI, OpenAI, and Ollama providers
- [Troubleshooting](./troubleshooting.md) - Common maproom error messages and recovery steps
- [Google Cloud ADC Documentation](https://cloud.google.com/docs/authentication/provide-credentials-adc) - Official Google documentation
- [Vertex AI Pricing](https://cloud.google.com/vertex-ai/pricing) - Google Cloud pricing for embedding API calls

---

*Last Updated: Feb 2026*
