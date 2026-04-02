# Transactions Reference — Mercury API

**Last Updated:** 2026-04-02

This document covers 4 Mercury API endpoints for transaction listing, retrieval,
metadata updates, and attachment uploads. Transactions are the most-queried
Mercury domain. Two endpoints are read-only (SAFE) and two are write operations
(CONFIRM) that require explicit user confirmation before execution.

## Transaction Object

Every endpoint in this document returns or operates on the Transaction Object.
The `amount` field is negative for debits and positive for credits.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Unique transaction identifier |
| amount | decimal | Transaction amount; negative values are debits, positive values are credits |
| status | string | Current transaction status |
| note | string or null | User-supplied note attached to the transaction |
| categoryId | UUID or null | ID of the assigned custom category |
| createdAt | ISO 8601 | Timestamp when the transaction was created |
| postedAt | ISO 8601 or null | Timestamp when the transaction posted; null if pending |
| bankDescription | string | Description provided by the bank |
| externalMemo | string | External-facing memo on the transaction |
| estimatedDeliveryDate | date or null | Estimated delivery date for pending transactions |
| failedAt | ISO 8601 or null | Timestamp when the transaction failed; null if not failed |
| reasonForFailure | string or null | Explanation of why the transaction failed; null if not failed |
| mercuryCategory | object or null | Mercury-assigned category with `id` (UUID) and `name` (string) fields |
| customCategory | object or null | User-assigned custom category with `id` (UUID) and `name` (string) fields |

## Paginated Response Envelope

The list endpoint returns transactions inside a paginated envelope:

```json
{
  "transactions": [ ...array of Transaction Objects... ],
  "page": {
    "nextPage": "UUID or null",
    "previousPage": "UUID or null"
  }
}
```

When `page.nextPage` is `null`, there are no more results. Pass the `nextPage`
value as the `start_after` query parameter to fetch the next page.

---

## GET /api/v1/transactions

**Description:** List all transactions across all accounts.
**Safety:** SAFE — execute directly without confirmation.

### Query Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| limit | integer | No | varies | Number of results per page |
| order | string | No | varies | Sort order (asc or desc) |
| start_after | UUID | No | none | Cursor: return results after this ID |
| end_before | UUID | No | none | Cursor: return results before this ID |
| start | date | No | none | Filter: transactions on or after this date (YYYY-MM-DD) |
| end | date | No | none | Filter: transactions on or before this date (YYYY-MM-DD) |
| status | string | No | none | Filter: transaction status |
| search | string | No | none | Filter: search by description or memo |

### Response

Returns a paginated response envelope containing an array of Transaction Objects.

### curl Example

```bash
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  "https://api.mercury.com/api/v1/transactions?limit=25"
```

### Conversational Presentation

Summarize the count before listing items. Format each transaction on its own
line with the date, description, and amount. Negative amounts are debits;
positive amounts are credits.

Example output:

> Found 3 transactions:
>
> - January 15, 2026 — Acme Corp — -$1,500.00
> - January 14, 2026 — Wire Deposit — +$10,000.00
> - January 13, 2026 — Office Supplies — -$245.99

Format currency as "$X,XXX.XX" and dates as "Month DD, YYYY". Never show raw
JSON or UUIDs to the user.

---

## GET /api/v1/transaction/{transactionId}

**Description:** Get a single transaction by ID.
**Safety:** SAFE — execute directly without confirmation.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| transactionId | UUID | Yes | The transaction ID to retrieve |

### Response

Returns a single Transaction Object (not wrapped in a paginated envelope).

### curl Example

```bash
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  "https://api.mercury.com/api/v1/transaction/550e8400-e29b-41d4-a716-446655440000"
```

### Conversational Presentation

Present the transaction details in plain language:

> Transaction on January 15, 2026: -$1,500.00 to Acme Corp.
> Status: posted. Note: "Monthly retainer payment."

Include the note and category if they are set. If the transaction failed, show
the failure timestamp and reason.

---

## PATCH /api/v1/transaction/{transactionId}

**Description:** Update transaction metadata (note and category only).
**Safety:** CONFIRM — requires explicit user confirmation before execution.

This endpoint updates metadata only. It does not modify the transaction amount,
status, or any financial data. The only updatable fields are `note` and
`categoryId`.

### CONFIRMATION REQUIRED

Before executing this request, present the update details and ask for approval:

> "I'll update the note on transaction ending in ...4400 to 'Q1 consulting
> retainer'. Shall I proceed?"

Do not execute until the user confirms.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| transactionId | UUID | Yes | The transaction ID to update |

### Request Body

Content-Type: `application/json`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| note | string or null | No | Updated note text; set to null to clear |
| categoryId | UUID or null | No | Updated custom category ID; set to null to remove |

At least one field must be provided. Both fields are optional individually, but
the request body must not be empty.

```json
{
  "note": "Q1 consulting retainer",
  "categoryId": "660f9511-f3ac-52e5-b827-557766551111"
}
```

### Response

Returns the updated Transaction Object.

### curl Example

```bash
curl -s -X PATCH \
  -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"note": "Q1 consulting retainer"}' \
  "https://api.mercury.com/api/v1/transaction/550e8400-e29b-41d4-a716-446655440000"
```

---

## POST /api/v1/transaction/{transactionId}/attachment

**Description:** Upload a file attachment to a transaction.
**Safety:** CONFIRM — requires explicit user confirmation before execution.

This endpoint uses `multipart/form-data` to upload a file. Attachments are
primarily used for reconciliation workflows (receipts, invoices, supporting
documents). Most transactions do not require attachments.

### CONFIRMATION REQUIRED

Before executing this request, describe the upload and ask for approval:

> "I'll attach the file 'receipt-january.pdf' to the transaction ending in
> ...4400. Shall I proceed?"

Do not execute until the user confirms.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| transactionId | UUID | Yes | The transaction ID to attach the file to |

### Request Body

Content-Type: `multipart/form-data`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| file | binary | Yes | The file to upload |

### Response

Returns confirmation of the attachment upload.

### curl Example

```bash
curl -s -X POST \
  -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  -F "file=@/path/to/receipt.pdf" \
  "https://api.mercury.com/api/v1/transaction/550e8400-e29b-41d4-a716-446655440000/attachment"
```

Note the `-F` flag, which sets the content type to `multipart/form-data`
automatically. Do not add a `Content-Type: application/json` header for this
endpoint.

---

## Common Patterns

### Filter Transactions by Date Range

Use the `start` and `end` query parameters to restrict results to a specific
date range. Both parameters accept dates in YYYY-MM-DD format.

```bash
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  "https://api.mercury.com/api/v1/transactions?start=2026-01-01&end=2026-01-31&limit=50"
```

This returns transactions from January 1 through January 31, 2026.

### Iterate Through Pages

Use cursor-based pagination to retrieve all transactions. Fetch the first page,
then pass `page.nextPage` as the `start_after` parameter for each subsequent
request. Stop when `page.nextPage` is `null`.

```bash
# First page
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  "https://api.mercury.com/api/v1/transactions?limit=25"

# Next page (replace CURSOR_UUID with page.nextPage from previous response)
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  "https://api.mercury.com/api/v1/transactions?limit=25&start_after=CURSOR_UUID"
```

### Distinguish Debits from Credits

The `amount` field sign indicates the direction of money movement:

- **Negative amount** (e.g., -1500.00): money left the account (debit). Present
  as "-$1,500.00".
- **Positive amount** (e.g., 10000.00): money entered the account (credit).
  Present as "+$10,000.00".

Always include the sign when presenting amounts to make the direction clear.

## Clarifying Questions

When the user asks to "update" a transaction, the request is ambiguous. Ask:

> "Do you want to add a note, change the category, or upload an attachment?"

This clarification routes to the correct operation:
- **Add or change a note:** PATCH with `note` field
- **Change the category:** PATCH with `categoryId` field
- **Upload an attachment:** POST to the attachment endpoint
