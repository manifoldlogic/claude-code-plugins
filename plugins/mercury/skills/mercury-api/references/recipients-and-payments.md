# Recipients & Payments Reference — Mercury API

This document covers 9 Mercury API endpoints for recipient management and payment
operations. It contains the two highest-risk endpoints in the entire Mercury API:
request-send-money and internal transfer, both classified as **CRITICAL** (money
movement). Three endpoints are CONFIRM (data modification) and four are SAFE
(read-only). For authentication, see [authentication.md](authentication.md).

## Recipient Object Schema

Recipient endpoints return objects with these fields:

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Unique recipient identifier |
| name | string | Recipient display name |
| nickname | string or null | User-assigned nickname |
| emails | array of strings | Email addresses for notifications |
| contactEmail | string | Primary contact email |
| createdAt | ISO 8601 | Recipient creation timestamp |
| electronicRoutingInfo | object or null | ACH routing details (see nested schema below) |
| domesticWireRoutingInfo | object or null | Wire routing details (see nested schema below) |
| checkInfo | object or null | Physical check mailing details (see nested schema below) |

### electronicRoutingInfo Object

| Field | Type | Description |
|-------|------|-------------|
| accountNumber | string | Bank account number |
| routingNumber | string | Bank routing number (9 digits) |
| electronicAccountType | string | One of: businessChecking, businessSavings, personalChecking, personalSavings |
| address | object | Recipient address (see Address Object below) |

### domesticWireRoutingInfo Object

| Field | Type | Description |
|-------|------|-------------|
| accountNumber | string | Bank account number |
| routingNumber | string | Bank routing number (9 digits) |
| defaultForBenefitOf | string or null | Default "for benefit of" line on the wire |
| address | object | Recipient address (see Address Object below) |

### checkInfo Object

| Field | Type | Description |
|-------|------|-------------|
| address | object | Mailing address for physical checks (see Address Object below) |

### Address Object

Used within electronicRoutingInfo, domesticWireRoutingInfo, and checkInfo:

| Field | Type | Description |
|-------|------|-------------|
| address1 | string | Street address |
| city | string | City |
| region | string | 2-letter state code (e.g., "CA") |
| postalCode | string | ZIP or postal code |
| country | string | 2-letter country code (e.g., "US") |

## Paginated Response Envelope

List endpoints return results inside a paginated envelope. The resource key is
`recipients` for recipient lists or varies for payment request lists.

```json
{
  "recipients": [ ...array of Recipient Objects... ],
  "page": { "nextPage": "UUID or null", "previousPage": "UUID or null" }
}
```

Pass `nextPage` as `start_after` to page forward. When `nextPage` is `null`, all
results are shown.

---

## GET /api/v1/recipients

**Description:** List all recipients.
**Safety:** SAFE — execute directly without confirmation.

**Query Parameters:** Standard pagination: `limit`, `order`, `start_after`, `end_before`.

**Response:** Paginated envelope with array of Recipient Objects.

```bash
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  "https://api.mercury.com/api/v1/recipients"
```

**Conversational Presentation:**
> "Found 4 recipients: Acme Corp (ACH), Smith Consulting (wire), City Landlord
> (check), Cloud Services Inc (ACH)."

---

## GET /api/v1/recipient/{recipientId}

**Description:** Get a single recipient by ID.
**Safety:** SAFE — execute directly without confirmation.

**Path Parameters:** `recipientId` (UUID, required) — the recipient to retrieve.

**Response:** Single Recipient Object (not wrapped in a paginated envelope).

```bash
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  "https://api.mercury.com/api/v1/recipient/550e8400-e29b-41d4-a716-446655440000"
```

**Conversational Presentation:**
> "Recipient: Acme Corp. Contact: billing@example.com. ACH routing to account
> ending in 4321, routing number ending in 7890. Created January 10, 2026."

Mask full account and routing numbers — show only the last four digits.

---

## POST /api/v1/recipient

**Description:** Add a new recipient.
**Safety:** CONFIRM — requires explicit user confirmation before execution.

Creating a recipient with incorrect bank details can cause misdirected payments.
Display all banking details for user review before creating.

### CONFIRMATION REQUIRED

Before executing, present all recipient details and ask for approval:

> "I'll create a new recipient named 'Acme Corp' with ACH routing to account
> ending in 4321 at routing number ending in 7890 (business checking), address:
> 123 Main St, San Francisco, CA 94105. Should I go ahead?"

Do not execute until the user confirms.

### Request Body

Content-Type: `application/json`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| name | string | Yes | Recipient name |
| emails | array of strings | No | Email addresses for payment notifications |
| electronicRoutingInfo | object | No | ACH routing — see electronicRoutingInfo Object schema above |
| domesticWireRoutingInfo | object | No | Wire routing — see domesticWireRoutingInfo Object schema above |
| checkInfo | object | No | Check mailing — see checkInfo Object schema above |

At least one routing info section should be provided to make the recipient usable.
All nested object fields match the Recipient Object Schema at the top of this
document. When a routing section is included, all its fields are required except
`defaultForBenefitOf` (wire only, optional).

### curl Example

```bash
curl -s -X POST \
  -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Acme Corp",
    "emails": ["billing@example.com"],
    "electronicRoutingInfo": {
      "accountNumber": "1234567890",
      "routingNumber": "021000021",
      "electronicAccountType": "businessChecking",
      "address": {"address1": "123 Main St", "city": "San Francisco", "region": "CA", "postalCode": "94105", "country": "US"}
    }
  }' \
  "https://api.mercury.com/api/v1/recipient"
```

**Response:** Returns the created Recipient Object.

---

## POST /api/v1/recipient/{recipientId}

**Description:** Edit recipient information.
**Safety:** CONFIRM — requires explicit user confirmation before execution.

### CONFIRMATION REQUIRED

Before executing, describe the changes and ask for approval:

> "I'll update the recipient 'Acme Corp' to change the ACH account number ending
> in 4321 to the new account ending in 8765. Should I go ahead?"

Do not execute until the user confirms.

**Path Parameters:** `recipientId` (UUID, required) — the recipient to edit.

**Request Body:** Same fields as Add Recipient (above). Only include fields being
changed; omit unchanged fields.

**Response:** Returns the updated Recipient Object.

---

## POST /api/v1/recipient/{recipientId}/attachment

**Description:** Upload a file attachment to a recipient.
**Safety:** CONFIRM — requires explicit user confirmation before execution.

### CONFIRMATION REQUIRED

Before executing, describe the upload and ask for approval:

> "I'll attach the file 'w9-acme.pdf' to the recipient Acme Corp. Shall I proceed?"

Do not execute until the user confirms.

**Path Parameters:** `recipientId` (UUID, required) — the recipient to attach to.

**Request Body:** Content-Type: `multipart/form-data`. Field: `file` (binary, required).

```bash
curl -s -X POST \
  -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  -F "file=@/path/to/w9-form.pdf" \
  "https://api.mercury.com/api/v1/recipient/550e8400-e29b-41d4-a716-446655440000/attachment"
```

**Response:** Returns confirmation of the attachment upload.

---

## POST /api/v1/account/{accountId}/request-send-money

**Description:** Request to send money from a Mercury account to a recipient.
**Safety:** CRITICAL — money movement, requires explicit "yes" confirmation.

> **CRITICAL:** Display amount, source account, recipient, and payment method.
> Format as "$X,XXX.XX". Wait for explicit "yes" before executing. Example:
> "CRITICAL: This will send $5,000.00 from Operating Account to Acme Corp via
> ACH. This moves real money and cannot be undone. Reply 'yes' to proceed."

**Path Parameters:** `accountId` (UUID, required) — the account to send from.

### Request Body

Content-Type: `application/json`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| recipientId | UUID | Yes | Target recipient ID (must be an existing recipient) |
| amount | decimal | Yes | Amount to send; positive, up to 2 decimal places |
| paymentMethod | string | Yes | `ach` (1-3 business days), `domesticWire` (same day), or `check` (mailed) |
| idempotencyKey | string | Yes | Unique key to prevent duplicate payments (see below) |
| note | string | No | Internal payment memo |
| externalMemo | string | No | External-facing memo visible to the recipient |

### Idempotency Key

The `idempotencyKey` prevents duplicate payments on retry. Same key sent twice
returns the original result. Rules: unique per request, recommended format
`"payment-{date}-{random}"`, reuse the SAME key only when retrying a failed
request. Never reuse a key across different payments — doing so silently returns
the first payment's result.

**Timeout handling:** If a request times out (no response received), do NOT assume
the payment failed. Retry using the same idempotency key — Mercury will return the
original result if the payment already succeeded. Never generate a new idempotency
key for a timed-out request, as this risks creating a duplicate payment.

### curl Example

```bash
curl -s -X POST \
  -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "recipientId": "550e8400-e29b-41d4-a716-446655440000",
    "amount": 5000.00,
    "paymentMethod": "ach",
    "idempotencyKey": "payment-20260402-x7k9m",
    "note": "March consulting invoice"
  }' \
  "https://api.mercury.com/api/v1/account/660f9511-e29b-41d4-a716-446655440001/request-send-money"
```

**Response:** Returns the payment approval request object with status, amount,
recipient, and creation timestamp.

**Conversational Presentation:**
> "Payment request submitted: $5,000.00 to Acme Corp via ACH. Status: pending
> approval. Created April 2, 2026."

---

## POST /api/v1/transfer

**Description:** Transfer money between two Mercury accounts owned by the same organization.
**Safety:** CRITICAL — money movement, requires explicit "yes" confirmation.

> **CRITICAL:** Display amount, source account, and destination account. Format as
> "$X,XXX.XX". Wait for explicit "yes" before executing. Example: "CRITICAL: This
> will transfer $10,000.00 from Operating Account to Savings Account. This moves
> real money and cannot be undone. Reply 'yes' to proceed."

### Request Body

Content-Type: `application/json`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| fromAccountId | UUID | Yes | Source Mercury account ID |
| toAccountId | UUID | Yes | Destination Mercury account ID |
| amount | decimal | Yes | Amount to transfer; positive, up to 2 decimal places |
| idempotencyKey | string | Yes | Unique key to prevent duplicate transfers (same rules as send-money above) |

**Idempotency:** Same rules as send-money above. Unique key per transfer; reuse
only on retry. If a transfer request times out, do NOT assume it failed — retry
with the same idempotency key. Never generate a new key for a timed-out request.

### curl Example

```bash
curl -s -X POST \
  -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "fromAccountId": "550e8400-e29b-41d4-a716-446655440000",
    "toAccountId": "660f9511-e29b-41d4-a716-446655440001",
    "amount": 10000.00,
    "idempotencyKey": "transfer-20260402-m3p8q"
  }' \
  "https://api.mercury.com/api/v1/transfer"
```

**Response:** Returns the transfer object with status, amount, source/destination
accounts, and creation timestamp.

**Conversational Presentation:**
> "Transfer complete: $10,000.00 moved from Operating Account to Savings Account.
> Status: completed. April 2, 2026."

---

## GET /api/v1/request-send-money/{requestId}

**Description:** Get the status of a send money approval request.
**Safety:** SAFE — execute directly without confirmation.

**Path Parameters:** `requestId` (UUID, required) — the send money request to retrieve.

**Response:** Returns the payment approval request object including status, amount,
recipient, payment method, and timestamps.

```bash
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  "https://api.mercury.com/api/v1/request-send-money/550e8400-e29b-41d4-a716-446655440000"
```

**Conversational Presentation:**
> "Payment request status: $5,000.00 to Acme Corp via ACH — pending approval.
> Created April 2, 2026."

---

## GET /api/v1/request-send-money

**Description:** List all send money approval requests.
**Safety:** SAFE — execute directly without confirmation.

**Query Parameters:** Standard pagination: `limit`, `order`, `start_after`, `end_before`.

**Response:** Paginated envelope with array of payment approval request objects.

```bash
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  "https://api.mercury.com/api/v1/request-send-money"
```

**Conversational Presentation:**
> "Found 3 pending payment requests:
>
> - $5,000.00 to Acme Corp via ACH — pending (April 1, 2026)
> - $2,500.00 to Smith Consulting via wire — approved (March 28, 2026)
> - $750.00 to City Landlord via check — completed (March 15, 2026)"

---

## Common Patterns

- **Find a recipient before sending money:** Call `GET /recipients`, filter by
  `name` client-side (no server-side filter), then use the ID in send-money.
- **Check pending approvals:** Call `GET /request-send-money` and filter by status.
- **Add a new recipient:** Gather name, email, and bank details from user. Present
  all details for review (wrong routing numbers cause misdirected payments). Only
  after CONFIRM gate approval, execute `POST /recipient`.

## Clarifying Questions

When the user asks to "send money" without full details, ask:
> "Who should receive it, how much, and which payment method — ACH (1-3 business
> days), wire (same day), or check (mailed)?"

When the user asks to "pay someone" and the recipient does not exist, ask:
> "I don't see that recipient in your Mercury account. Would you like me to add
> them first? I'll need their name, bank account number, routing number, and
> account type."

When the user asks to "transfer" without specifying accounts, ask:
> "Which account should the funds come from, and which account should receive them?"
