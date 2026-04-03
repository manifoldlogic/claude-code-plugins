# Webhooks & Events Reference — Mercury API

This document covers 8 Mercury API endpoints for webhook management and event
retrieval. Webhooks let you receive real-time notifications when things happen in
your Mercury account (transactions, balance changes). Events provide a queryable
log of past activity. Four endpoints are write operations (CONFIRM) and four are
read-only (SAFE). For authentication, see [authentication.md](authentication.md).

## Webhook Object Schema

Webhook endpoints return objects with these fields:

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Unique webhook identifier |
| url | string | The URL that receives webhook POST requests |
| eventTypes | array of strings | Event types this webhook is subscribed to |
| status | string | One of: active, paused, disabled |
| createdAt | ISO 8601 | Webhook creation timestamp |

## Event Object Schema

Event endpoints return objects with these fields:

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Unique event identifier |
| type | string | Event type (e.g., transaction.created) |
| createdAt | ISO 8601 | Timestamp when the event occurred |
| data | object | Event-specific payload (varies by event type) |

The `data` field contains context relevant to the event type. For transaction
events, it includes the transaction ID. For balance events, it includes the
account ID. The full event payload schema is documented in the Mercury developer
documentation.

## Available Event Types

These are the event types you can subscribe a webhook to:

| Event Type | Description |
|------------|-------------|
| transaction.created | A new transaction was created |
| transaction.updated | An existing transaction was updated (status change, etc.) |
| checkingAccount.balance.updated | A checking account balance changed |
| savingsAccount.balance.updated | A savings account balance changed |
| treasuryAccount.balance.updated | A treasury account balance changed |
| investmentAccount.balance.updated | An investment account balance changed |
| creditAccount.balance.updated | A credit account balance changed |

## Paginated Response Envelope

List endpoints return results inside a paginated envelope. The resource key is
`webhooks` for webhook lists or `events` for event lists.

```json
{
  "webhooks": [ ...array of Webhook Objects... ],
  "page": { "nextPage": "UUID or null", "previousPage": "UUID or null" }
}
```

Pass `nextPage` as `start_after` to page forward. When `nextPage` is `null`, all
results are shown.

---

## GET /api/v1/webhooks

**Description:** List all webhooks configured for your organization.
**Safety:** SAFE — execute directly without confirmation.

**Query Parameters:** Standard pagination: `limit`, `order`, `start_after`, `end_before`.

**Response:** Paginated envelope with array of Webhook Objects.

```bash
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  "https://api.mercury.com/api/v1/webhooks"
```

**Conversational Presentation:**
> "You have 2 webhooks configured:
>
> - https://your-server.example.com/webhooks — active, subscribed to
>   transaction.created, transaction.updated
> - https://your-server.example.com/balance — paused, subscribed to
>   checkingAccount.balance.updated"

Present the URL, status (active/paused/disabled), and subscribed event types for
each webhook.

---

## GET /api/v1/webhook/{webhookId}

**Description:** Get a single webhook by ID.
**Safety:** SAFE — execute directly without confirmation.

**Path Parameters:** `webhookId` (UUID, required) — the webhook to retrieve.

**Response:** Single Webhook Object (not wrapped in a paginated envelope).

```bash
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  "https://api.mercury.com/api/v1/webhook/550e8400-e29b-41d4-a716-446655440000"
```

**Conversational Presentation:**
> "Webhook: https://your-server.example.com/webhooks. Status: active. Subscribed
> to: transaction.created, transaction.updated. Created January 10, 2026."

---

## POST /api/v1/webhooks

**Description:** Create a new webhook endpoint.
**Safety:** CONFIRM — requires explicit user confirmation before execution.

Creating a webhook registers an external URL to receive POST requests from
Mercury whenever subscribed events occur. The URL must be reachable and return
a 200 OK response.

### CONFIRMATION REQUIRED

Before executing, present all details and ask for approval:

> "I'll create a webhook at https://your-server.example.com/webhooks subscribed
> to transaction.created, transaction.updated. Shall I proceed?"

Do not execute until the user confirms.

### Request Body

Content-Type: `application/json`

```json
{
  "url": "https://your-server.example.com/webhooks",
  "eventTypes": [
    "transaction.created",
    "transaction.updated",
    "checkingAccount.balance.updated"
  ],
  "status": "active"
}
```

### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| url | string | Yes | URL to receive webhook POST requests |
| eventTypes | array of strings | Yes | Event types to subscribe to (see Available Event Types above) |
| status | string | No | Initial status: active (default), paused, or disabled |

**Response:** Returns the created Webhook Object.

### curl Example

```bash
curl -s -X POST \
  -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://your-server.example.com/webhooks",
    "eventTypes": ["transaction.created", "transaction.updated"],
    "status": "active"
  }' \
  "https://api.mercury.com/api/v1/webhooks"
```

---

## POST /api/v1/webhook/{webhookId}

**Description:** Update an existing webhook endpoint.
**Safety:** CONFIRM — requires explicit user confirmation before execution.

### CONFIRMATION REQUIRED

Before executing, describe the changes and ask for approval:

> "I'll update your webhook at https://your-server.example.com/webhooks to add
> checkingAccount.balance.updated to its subscribed events. Shall I proceed?"

Do not execute until the user confirms.

**Path Parameters:** `webhookId` (UUID, required) — the webhook to update.

### Request Body

Content-Type: `application/json`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| url | string | No | Updated URL to receive webhook POST requests |
| eventTypes | array of strings | No | Updated list of subscribed event types |
| status | string | No | Updated status: active, paused, or disabled |

Only include fields being changed; omit unchanged fields.

**Response:** Returns the updated Webhook Object.

### curl Example

```bash
curl -s -X POST \
  -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"status": "paused"}' \
  "https://api.mercury.com/api/v1/webhook/550e8400-e29b-41d4-a716-446655440000"
```

---

## POST /api/v1/webhook/{webhookId}/verify

**Description:** Verify that a webhook endpoint is reachable.
**Safety:** CONFIRM — requires explicit user confirmation before execution.

This endpoint sends a test POST request to the configured webhook URL to confirm
it is reachable and returns a 200 OK response. Use this to validate webhook
configuration before relying on it for production events.

The confirmation gate applies because this endpoint triggers an outbound network
request to the configured URL, even though it does not modify webhook data.

### CONFIRMATION REQUIRED

Before executing, explain the verification and ask for approval:

> "I'll send a test request to your webhook at
> https://your-server.example.com/webhooks to verify it's reachable. Shall I
> proceed?"

Do not execute until the user confirms.

**Path Parameters:** `webhookId` (UUID, required) — the webhook to verify.

**Response:** Returns verification result indicating whether the URL responded
successfully.

### curl Example

```bash
curl -s -X POST \
  -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  "https://api.mercury.com/api/v1/webhook/550e8400-e29b-41d4-a716-446655440000/verify"
```

---

## DELETE /api/v1/webhook/{webhookId}

**Description:** Delete a webhook.
**Safety:** CONFIRM — requires explicit user confirmation before execution.

> **Warning: Permanent deletion.** Deleting a webhook is irreversible. Once
> deleted, the URL will stop receiving Mercury event notifications immediately.
> Any active subscriptions on this webhook will be permanently lost. This action
> cannot be undone.

### CONFIRMATION REQUIRED

Before executing, warn the user and ask for approval:

> "I'll delete the webhook at https://your-server.example.com/webhooks. Once
> deleted, this server will stop receiving Mercury events. This cannot be undone.
> Shall I proceed?"

Do not execute until the user confirms.

**Path Parameters:** `webhookId` (UUID, required) — the webhook to delete.

**Response:** Returns confirmation of deletion.

### curl Example

```bash
curl -s -X DELETE \
  -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  "https://api.mercury.com/api/v1/webhook/550e8400-e29b-41d4-a716-446655440000"
```

---

## GET /api/v1/events

**Description:** List all events across your organization.
**Safety:** SAFE — execute directly without confirmation.

Events are a log of things that happened in your Mercury account. Use this
endpoint to review past activity or troubleshoot webhook delivery issues.

**Query Parameters:** Standard pagination: `limit`, `order`, `start_after`, `end_before`.

**Response:** Paginated envelope with array of Event Objects (resource key: `events`).

```bash
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  "https://api.mercury.com/api/v1/events"
```

**Conversational Presentation:**
> "Found 3 recent events:
>
> - transaction.created — April 1, 2026 — transaction ending in ...4400
> - checkingAccount.balance.updated — April 1, 2026 — Operating Account
> - transaction.updated — March 31, 2026 — transaction ending in ...3300"

Present the event type, timestamp, and relevant context (transaction ID for
transaction events, account name for balance events). Format dates as
"Month DD, YYYY". Never show raw JSON or UUIDs to the user.

---

## GET /api/v1/event/{eventId}

**Description:** Get a single event by ID.
**Safety:** SAFE — execute directly without confirmation.

**Path Parameters:** `eventId` (UUID, required) — the event to retrieve.

**Response:** Single Event Object (not wrapped in a paginated envelope).

```bash
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  "https://api.mercury.com/api/v1/event/550e8400-e29b-41d4-a716-446655440000"
```

**Conversational Presentation:**
> "Event: transaction.created on April 1, 2026. Transaction ending in ...4400,
> amount -$1,500.00 to Acme Corp."

Include all relevant context from the event data payload.

---

## Common Patterns

### Set Up a Webhook for Transaction Notifications

1. Choose the URL that will receive webhook events.
2. Create a webhook subscribed to `transaction.created` and `transaction.updated`:
   `POST /api/v1/webhooks` with the URL and event types.
3. Verify the webhook is reachable: `POST /api/v1/webhook/{webhookId}/verify`.
4. Confirm the webhook is active: `GET /api/v1/webhook/{webhookId}`.

### Troubleshoot a Webhook

If your webhook is not receiving events:

1. Verify the webhook is reachable: `POST /api/v1/webhook/{webhookId}/verify`.
   If verification fails, the URL may be down or returning a non-200 response.
2. Check the webhook status: `GET /api/v1/webhook/{webhookId}`. Confirm the
   status is "active" (not "paused" or "disabled").
3. Check the events log: `GET /api/v1/events`. If events are being generated but
   not delivered, the issue is with your receiving server, not Mercury.

### Pause a Webhook Temporarily

To temporarily stop receiving events without deleting the webhook:

1. Update the webhook status to "paused":
   `POST /api/v1/webhook/{webhookId}` with `{"status": "paused"}`.
2. When ready to resume, update the status back to "active":
   `POST /api/v1/webhook/{webhookId}` with `{"status": "active"}`.

This preserves the webhook configuration, subscribed event types, and URL.

## Clarifying Questions

When the user asks to "set up a webhook", ask:
> "What URL should receive the events, and which event types are you interested
> in? Available types: transaction.created, transaction.updated,
> checkingAccount.balance.updated, savingsAccount.balance.updated,
> treasuryAccount.balance.updated, investmentAccount.balance.updated,
> creditAccount.balance.updated."

When the user asks to "check my webhooks" or "see my notifications", route to
`GET /api/v1/webhooks` and present the list conversationally.

When the user asks "why am I not getting notifications", follow the troubleshoot
pattern above: verify, check status, then check the events log.
