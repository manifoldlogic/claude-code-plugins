# Authentication Reference — Mercury API

This document covers all authentication methods, token types, security practices,
and troubleshooting for the Mercury banking API. Use this reference when
constructing any authenticated Mercury API request.

## Token Types

Mercury issues API tokens through the Mercury dashboard. Each token belongs to
one of three permission tiers. Start with Read Only tokens and upgrade only when
write access is required (minimum privilege principle).

| Tier | Capabilities | IP Whitelist Required |
|------|-------------|----------------------|
| Read Only | GET endpoints only — list accounts, view transactions, download statements | No |
| Read and Write | All endpoints — read operations plus send money, create recipients, manage invoices | Yes |
| Custom | Selected scopes chosen during token creation | Depends on selected scopes |

**Recommendation:** Use a Read Only token unless the operation explicitly requires
write access. Read Only tokens do not require IP whitelisting, reducing setup
friction and limiting blast radius if the token is compromised.

## Bearer Auth

Pass the token in the `Authorization` header with the `Bearer` scheme. This is
the primary authentication method.

```bash
curl -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  https://api.mercury.com/api/v1/accounts
```

Use Bearer auth for all standard API requests. The token value comes from the
`MERCURY_TOKEN` environment variable — never inline a raw token in the command.

### Bearer Auth with POST Body

For write operations, include the `Content-Type` header alongside the Bearer
token:

```bash
curl -X POST \
  -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"name": "Vendor Name", "emails": ["vendor@example.com"]}' \
  https://api.mercury.com/api/v1/recipient
```

## Basic Auth

Mercury also accepts Basic Auth with the token as the username and an empty
password. The `-u` flag in curl handles the encoding automatically.

```bash
curl -u "${MERCURY_TOKEN}:" \
  https://api.mercury.com/api/v1/accounts
```

The trailing colon after `${MERCURY_TOKEN}:` indicates an empty password. This is
equivalent to sending the following header:

```
Authorization: Basic $(echo -n "${MERCURY_TOKEN}:" | base64)
```

Use Basic Auth when Bearer auth is inconvenient for the client or tooling in use.
Both methods are fully equivalent in terms of permissions and access.

## Token Setup

Tokens are created exclusively through the Mercury dashboard. There is no API
endpoint for generating or managing tokens.

### Create a New Token

1. Log into the Mercury dashboard at https://app.mercury.com.
2. Navigate to **Settings > API Tokens** (or **Developer Settings > API**).
3. Select the desired token tier (Read Only, Read and Write, or Custom).
4. If creating a Read and Write token, configure IP whitelisting before the token
   becomes active for write operations (see IP Whitelisting below).
5. Copy the generated token immediately. Mercury displays the full token only once
   at creation time.
6. Store the token in a secure location (password manager, secrets vault, or
   encrypted environment file). Do not store it in version control.

### Token Permissions

- **Read Only:** Grants access to all GET endpoints. No IP whitelisting required.
  Suitable for dashboards, reporting, and data retrieval.
- **Read and Write:** Grants access to all endpoints including money movement.
  Requires IP whitelisting. Suitable for full automation workflows.
- **Custom:** Grants access to a selected subset of scopes. IP whitelisting
  requirement depends on whether write scopes are included.

## IP Whitelisting

Read and Write tokens require IP whitelisting before write operations become
active. This is a security measure that restricts API write access to known
network addresses.

### Configuration Steps

1. In the Mercury dashboard, navigate to the API token settings.
2. Locate the Read and Write token that needs whitelisting.
3. Add each authorized IP address or CIDR range.
4. Save the configuration. Write operations become available immediately for
   requests originating from whitelisted IPs.

### Key Rules

- **Read Only tokens:** IP whitelisting is not required and not enforced.
- **Read and Write tokens:** IP whitelisting is mandatory. Write requests from
  non-whitelisted IPs receive a `403 Forbidden` response.
- **Custom tokens:** IP whitelisting is required if any write scopes are selected.
- If the calling machine's IP address changes (e.g., dynamic IP, VPN switch),
  update the whitelist in the Mercury dashboard before making write requests.

## Token Security

Mercury enforces automatic token lifecycle policies to reduce risk from unused or
underutilized credentials.

### Auto-Downgrade

Read and Write tokens that have not been used for any write operation within 45
consecutive days are automatically downgraded to Read Only. This means:

- The token continues to work for GET requests.
- POST, PATCH, and DELETE requests begin returning `403 Forbidden`.
- To restore write access, generate a new Read and Write token from the Mercury
  dashboard.

### Auto-Delete

Tokens that have had no activity of any kind (no read or write requests) for 45
consecutive days are automatically deleted. After deletion:

- All requests using the token return `401 Unauthorized`.
- The token cannot be recovered. Generate a new token from the dashboard.

### Token Revocation

If a token is compromised, revoke it immediately:

1. Log into the Mercury dashboard at https://app.mercury.com.
2. Navigate to **Settings > API Tokens**.
3. Locate the compromised token.
4. Delete the token. Revocation takes effect immediately — all subsequent
   requests using that token return `401 Unauthorized`.
5. Audit recent API activity for unauthorized operations, especially any
   CRITICAL-tier endpoints (send money, internal transfers).
6. Generate a new replacement token if continued API access is needed.

### Best Practices

- Rotate tokens periodically, even if not compromised.
- Use Read Only tokens for all read-only workflows.
- Monitor the 45-day auto-downgrade and auto-delete windows to avoid unexpected
  access loss.
- Never store tokens in source code, commit history, shell history files, or
  plain-text configuration files checked into version control.
- Use a secrets manager or encrypted environment file for token storage.

## Environment Variable Setup

All curl examples and agent-constructed API calls use the `MERCURY_TOKEN`
environment variable. Set it before making any Mercury API request.

### Set for Current Shell Session

```bash
export MERCURY_TOKEN="your-token-value-here"
```

Replace `your-token-value-here` with the actual token copied from the Mercury
dashboard. This persists for the duration of the shell session.

### Set from a Secrets File

Store the token in a file excluded from version control, then source it:

```bash
# .env file (add to .gitignore)
MERCURY_TOKEN=your-token-value-here
```

```bash
# Load only MERCURY_TOKEN safely
export MERCURY_TOKEN="$(grep -E '^MERCURY_TOKEN=' .env | head -n1 | cut -d= -f2-)"
```

### Verify the Variable Is Set

```bash
# Confirm the variable is set (does not print the token value)
[ -n "${MERCURY_TOKEN}" ] && echo "MERCURY_TOKEN is set" || echo "MERCURY_TOKEN is NOT set"
```

### Agent Usage

When constructing API calls, always reference `${MERCURY_TOKEN}` in the
Authorization header or `-u` flag. Never substitute the raw token value into the
command string. This prevents token leakage into command history, logs, and
context windows.

## OAuth2 Acknowledgment

Mercury provides OAuth2 endpoints for authorization code flows:

- `/auth/authorize` — Authorization endpoint
- `/auth/token` — Token exchange endpoint

**These endpoints require Mercury pre-approval.** Organizations must apply to
Mercury for OAuth2 access before these endpoints become available. The Mercury API
skill covers token-based authentication only (Bearer and Basic Auth as documented
above). OAuth2 request and response schemas are not documented in this skill.

If OAuth2 access is needed, contact Mercury support to begin the approval process.
Until approved, use token-based authentication for all API interactions.

## Troubleshooting

### 401 Unauthorized — Invalid or Expired Token

**Symptoms:** API returns HTTP 401 with `"Invalid or expired API token"`.

**Causes:**
- `MERCURY_TOKEN` environment variable is not set or is empty.
- The token value is incorrect (truncated, extra whitespace, wrong token).
- The token was auto-deleted after 45 days of inactivity.
- The token was manually revoked in the Mercury dashboard.

**Resolution:**
1. Verify the environment variable is set:
   ```bash
   [ -n "${MERCURY_TOKEN}" ] && echo "Set" || echo "Not set"
   ```
2. Confirm the token value matches what is stored in the Mercury dashboard.
3. If the token was auto-deleted or revoked, generate a new token from the
   dashboard.
4. Test with a simple read request:
   ```bash
   curl -s -o /dev/null -w "%{http_code}" \
     -H "Authorization: Bearer ${MERCURY_TOKEN}" \
     https://api.mercury.com/api/v1/accounts
   ```

### 403 Forbidden — Permission Denied or IP Not Whitelisted

**Symptoms:** API returns HTTP 403.

**Causes:**
- The token's tier does not permit the requested operation (e.g., Read Only token
  attempting a POST).
- The requesting IP address is not whitelisted for a Read and Write token.
- A Read and Write token was auto-downgraded to Read Only after 45 days without
  write usage.

**Resolution:**
1. Check the token tier in the Mercury dashboard.
2. If using a Read and Write token, verify the calling machine's IP address is
   on the whitelist.
3. If the token was auto-downgraded, generate a new Read and Write token and
   configure IP whitelisting.
4. If a Read Only token was used for a write operation, either upgrade to a Read
   and Write token or use a Custom token with the appropriate scopes.

### Token Tier Mismatch — Read Only Token Cannot Write

**Symptoms:** Write operations (POST, PATCH, DELETE) return 403 even though the
token appears valid for read operations.

**Causes:**
- A Read Only token is being used for an operation that requires Read and Write
  or Custom tier permissions.
- The token was originally Read and Write but was auto-downgraded to Read Only
  after 45 days of write underutilization.

**Resolution:**
1. Confirm the token tier in the Mercury dashboard under API token settings.
2. If a higher tier is needed, create a new Read and Write or Custom token.
3. For Read and Write tokens, configure IP whitelisting before attempting write
   operations.
4. Use the minimum tier necessary — if only GET requests are needed, Read Only
   is correct and no change is required.

### Common Diagnostic Commands

Verify connectivity and authentication in a single request:

```bash
curl -s -w "\nHTTP Status: %{http_code}\n" \
  -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  https://api.mercury.com/api/v1/accounts
```

Check whether the issue is authentication (401) or authorization (403):

- **401** indicates the token itself is invalid — focus on the token value and
  environment variable.
- **403** indicates the token is valid but lacks permission — focus on the token
  tier and IP whitelist settings.
