# Accounts Receivable Reference — Mercury API

**Last Updated:** 2026-04-02

This document covers 13 Mercury API endpoints for invoices, customers, and AR
attachments. Invoices and customers form a self-contained accounts receivable
workflow: create a customer, then create invoices for that customer. All write
endpoints (POST and DELETE) are classified CONFIRM — they require explicit user
confirmation before execution. No endpoints in this domain are CRITICAL because
AR operations do not directly move money out of the account.

For authentication, see [authentication.md](authentication.md).

## Invoice Object

Endpoints that return invoices use this schema. The `status` field tracks the
invoice lifecycle from creation through payment or cancellation.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Unique invoice identifier |
| invoiceNumber | string | Payer-facing invoice identifier |
| status | string | One of: pending, sent, paid, cancelled |
| customerId | UUID | Customer this invoice belongs to |
| destinationAccountId | UUID | Mercury account that receives payment |
| invoiceDate | date | Date the invoice was issued |
| dueDate | date | Payment due date |
| amount | decimal | Total invoice amount |
| lineItems | array | Array of line item objects (see Create Invoice schema) |
| ccEmails | array | CC email addresses |
| creditCardEnabled | boolean | Whether credit card payment is accepted |
| achDebitEnabled | boolean | Whether ACH debit payment is accepted |
| useRealAccountNumber | boolean | Whether to show real account number to payer |
| payerMemo | string or null | Customer-visible memo |
| internalNote | string or null | Internal-only note |
| sendEmailOption | string | DontSend or SendNow |
| createdAt | ISO 8601 | Timestamp when the invoice was created |

## Customer Object

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Unique customer identifier |
| name | string | Customer name |
| email | string | Customer email address |
| createdAt | ISO 8601 | Timestamp when the customer was created |

## Paginated Response Envelope

List endpoints return results inside a paginated envelope. The resource key
varies: `invoices` for invoice lists, `customers` for customer lists. Pass
`nextPage` as `start_after` to page forward. Standard pagination query
parameters (`limit`, `order`, `start_after`, `end_before`) apply to all list
endpoints in this domain.

---

## GET /api/v1/ar/invoices

**Description:** List all invoices across all customers.
**Safety:** SAFE — execute directly without confirmation.

### curl Example

```bash
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  "https://api.mercury.com/api/v1/ar/invoices?limit=25"
```

### Conversational Presentation

Summarize the count and list each invoice with its number, customer, amount,
status, and due date. Format amounts as "$X,XXX.XX" and dates as
"Month DD, YYYY". Show invoice status (pending, sent, paid, cancelled).

> Found 3 invoices:
>
> - Invoice #1042 — Acme Corp — $5,250.00 — sent — due March 15, 2026
> - Invoice #1041 — Widget LLC — $1,800.00 — paid — due February 28, 2026
> - Invoice #1040 — Acme Corp — $3,000.00 — cancelled

Never show raw JSON or UUIDs to the user.

---

## POST /api/v1/ar/invoices

**Description:** Create a new invoice for a customer.
**Safety:** CONFIRM — requires explicit user confirmation before execution.

**Important:** The `sendEmailOption` field defaults to `SendNow`, which
immediately emails the invoice to the customer upon creation. If the user has
not explicitly asked to send the invoice, set this field to `DontSend`.

### CONFIRMATION REQUIRED

Before executing this request, present the invoice details and ask for approval:

> "CONFIRMATION REQUIRED: I'll create an invoice for [Customer Name] for
> $[total amount] due [due date]. The invoice will be [sent immediately / saved
> as draft] via email. Shall I proceed?"

Do not execute until the user confirms.

### Request Body

Content-Type: `application/json`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| customerId | UUID | Yes | Customer receiving the invoice |
| destinationAccountId | UUID | Yes | Mercury account that will receive payment; clarify with user if they have multiple accounts |
| invoiceDate | date (YYYY-MM-DD) | Yes | Invoice issue date |
| dueDate | date (YYYY-MM-DD) | Yes | Payment due date |
| lineItems | array | Yes | Array of line item objects (see below) |
| ccEmails | array of strings | No | CC email addresses for invoice notifications |
| creditCardEnabled | boolean | No | Allow credit card payment (default: true) |
| achDebitEnabled | boolean | No | Allow ACH debit payment (default: true) |
| useRealAccountNumber | boolean | No | Show real account number to payer (default: false) |
| invoiceNumber | string | No | Payer-facing invoice identifier; auto-generated if omitted |
| payerMemo | string | No | Customer-visible memo on the invoice |
| internalNote | string | No | Internal-only note (not visible to customer) |
| sendEmailOption | string | No | `DontSend` or `SendNow` (default: `SendNow`) — controls whether the invoice is emailed immediately |

### lineItems Array Schema

Each element in the `lineItems` array describes one line on the invoice:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| name | string | Yes | Line item description (e.g., "Consulting — March 2026") |
| unitPrice | decimal | Yes | Price per unit in dollars (e.g., 150.00) |
| quantity | integer | Yes | Number of units (e.g., 10) |
| salesTaxRate | decimal | No | Tax rate as a decimal (e.g., 0.08 for 8%); defaults to 0 if omitted |

### Full Request Example

```json
{
  "customerId": "550e8400-e29b-41d4-a716-446655440000",
  "destinationAccountId": "660f9511-f3ac-52e5-b827-557766551111",
  "invoiceDate": "2026-04-01",
  "dueDate": "2026-04-30",
  "lineItems": [
    {
      "name": "Consulting — March 2026",
      "unitPrice": 150.00,
      "quantity": 10,
      "salesTaxRate": 0.08
    },
    {
      "name": "Hosting fees — March 2026",
      "unitPrice": 50.00,
      "quantity": 1
    }
  ],
  "ccEmails": ["accounting@example.com"],
  "creditCardEnabled": true,
  "achDebitEnabled": true,
  "useRealAccountNumber": false,
  "invoiceNumber": "INV-2026-042",
  "payerMemo": "Payment due within 30 days",
  "internalNote": "Q1 retainer, final month",
  "sendEmailOption": "SendNow"
}
```

### curl Example

```bash
curl -s -X POST \
  -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": "550e8400-e29b-41d4-a716-446655440000",
    "destinationAccountId": "660f9511-f3ac-52e5-b827-557766551111",
    "invoiceDate": "2026-04-01",
    "dueDate": "2026-04-30",
    "lineItems": [{"name": "Consulting", "unitPrice": 150.00, "quantity": 10}],
    "sendEmailOption": "SendNow"
  }' \
  "https://api.mercury.com/api/v1/ar/invoices"
```

### Response

Returns the created Invoice Object with its assigned `id` and `status`
(typically `sent` if `sendEmailOption` was `SendNow`, or `pending` if
`DontSend`).

---

## GET /api/v1/ar/invoice/{invoiceId}

**Description:** Get a single invoice by ID.
**Safety:** SAFE — execute directly without confirmation.

**Path Parameters:** `invoiceId` (UUID, required) — the invoice to retrieve.

**Response:** Returns a single Invoice Object.

```bash
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  "https://api.mercury.com/api/v1/ar/invoice/550e8400-e29b-41d4-a716-446655440000"
```

**Conversational Presentation:**
> Invoice #1042 for Acme Corp: $5,250.00, status: sent, due March 15, 2026.
> Memo: "Q1 consulting services."

---

## POST /api/v1/ar/invoice/{invoiceId}

**Description:** Update an existing invoice.
**Safety:** CONFIRM — requires explicit user confirmation before execution.

### CONFIRMATION REQUIRED

> "CONFIRMATION REQUIRED: I'll update invoice #[invoiceNumber] for [Customer
> Name] with the following changes: [describe changes]. Shall I proceed?"

Do not execute until the user confirms.

**Path Parameters:** `invoiceId` (UUID, required) — the invoice to update.

**Request Body:** Content-Type: `application/json`. Same fields as Create
Invoice. Include only the fields to update.

**Response:** Returns the updated Invoice Object.

---

## POST /api/v1/ar/invoice/{invoiceId}/cancel

**Description:** Cancel an invoice. This action cannot be undone.
**Safety:** CONFIRM — requires explicit user confirmation before execution.

### CONFIRMATION REQUIRED

> "CONFIRMATION REQUIRED: I'll cancel invoice #[invoiceNumber] for [Customer
> Name]. This action cannot be undone. Shall I proceed?"

Do not execute until the user confirms.

**Path Parameters:** `invoiceId` (UUID, required) — the invoice to cancel.

**Request Body:** No request body required. Send an empty POST.

**Response:** Returns the cancelled Invoice Object with `status` set to
`cancelled`.

**Warning:** Cancellation is permanent. A cancelled invoice cannot be re-sent
or reopened. If the user needs to re-issue the invoice, they must create a new
one.

---

## GET /api/v1/ar/invoice/{invoiceId}/attachments

**Description:** List all attachments for an invoice.
**Safety:** SAFE — execute directly without confirmation.

**Path Parameters:** `invoiceId` (UUID, required) — the invoice whose
attachments to list.

**Response:** Returns an array of attachment objects with `id`, `filename`, and
`contentType` fields.

```bash
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  "https://api.mercury.com/api/v1/ar/invoice/550e8400-e29b-41d4-a716-446655440000/attachments"
```

**Conversational Presentation:**
> Found 2 attachments on invoice #1042:
>
> - contract.pdf (application/pdf)
> - scope-of-work.docx (application/vnd.openxmlformats)

---

## GET /api/v1/ar/invoice/{invoiceId}/pdf

**Description:** Download an invoice as a PDF file.
**Safety:** SAFE — execute directly without confirmation.

**Path Parameters:** `invoiceId` (UUID, required) — the invoice to download.

**Response:** Binary PDF data with **Content-Type:** `application/pdf` (not
JSON). Save the response to a file rather than attempting to parse it as JSON.

```bash
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  -o invoice.pdf \
  "https://api.mercury.com/api/v1/ar/invoice/550e8400-e29b-41d4-a716-446655440000/pdf"
```

Note the `-o` flag to save binary output. Without it, binary PDF data will be
written to the terminal.

---

## GET /api/v1/ar/customers

**Description:** List all AR customers.
**Safety:** SAFE — execute directly without confirmation.

**Response:** Paginated envelope with key `customers`.

```bash
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  "https://api.mercury.com/api/v1/ar/customers"
```

**Conversational Presentation:**
> Found 4 customers:
>
> - Acme Corp (acme@example.com)
> - Widget LLC (billing@widget.co)
> - Startup Inc (ap@startup.io)
> - Freelancer Jane (jane@freelance.dev)

---

## POST /api/v1/ar/customers

**Description:** Create a new AR customer.
**Safety:** CONFIRM — requires explicit user confirmation before execution.

### CONFIRMATION REQUIRED

> "CONFIRMATION REQUIRED: I'll create a new customer '[Customer Name]' with
> email [email]. Shall I proceed?"

Do not execute until the user confirms.

### Request Body

Content-Type: `application/json`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| name | string | Yes | Customer name |
| email | string | Yes | Customer email address (used for invoice delivery) |

```bash
curl -s -X POST \
  -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"name": "Acme Corp", "email": "billing@acme.com"}' \
  "https://api.mercury.com/api/v1/ar/customers"
```

**Response:** Returns the created Customer Object with its assigned `id`.

---

## GET /api/v1/ar/customer/{customerId}

**Description:** Get a single customer by ID.
**Safety:** SAFE — execute directly without confirmation.

**Path Parameters:** `customerId` (UUID, required) — the customer to retrieve.

**Response:** Returns a single Customer Object.

```bash
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  "https://api.mercury.com/api/v1/ar/customer/550e8400-e29b-41d4-a716-446655440000"
```

**Conversational Presentation:**
> Customer: Acme Corp (acme@example.com), created January 10, 2026.

---

## POST /api/v1/ar/customer/{customerId}

**Description:** Update an existing customer.
**Safety:** CONFIRM — requires explicit user confirmation before execution.

### CONFIRMATION REQUIRED

> "CONFIRMATION REQUIRED: I'll update customer '[Customer Name]' with the
> following changes: [describe changes]. Shall I proceed?"

Do not execute until the user confirms.

**Path Parameters:** `customerId` (UUID, required) — the customer to update.

**Request Body:** Content-Type: `application/json`. Same fields as Create
Customer. Include only the fields to update.

**Response:** Returns the updated Customer Object.

---

## DELETE /api/v1/ar/customer/{customerId}

**Description:** Delete a customer. This action cannot be undone.
**Safety:** CONFIRM — requires explicit user confirmation before execution.

### CONFIRMATION REQUIRED

> "CONFIRMATION REQUIRED: I'll delete customer '[Customer Name]'. This action
> cannot be undone and will also affect associated invoices. Shall I proceed?"

Do not execute until the user confirms.

**Path Parameters:** `customerId` (UUID, required) — the customer to delete.

**Response:** Returns a confirmation of deletion.

**Warning:** Deletion is permanent. A deleted customer cannot be recovered. Any
invoices associated with this customer may also be affected. Verify with the
user before proceeding.

---

## GET /api/v1/ar/attachment/{attachmentId}

**Description:** Get a single attachment by ID.
**Safety:** SAFE — execute directly without confirmation.

**Path Parameters:** `attachmentId` (UUID, required) — the attachment to
retrieve.

**Response:** Returns the attachment object with `id`, `filename`,
`contentType`, and a download URL or binary content depending on the type.

```bash
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  "https://api.mercury.com/api/v1/ar/attachment/550e8400-e29b-41d4-a716-446655440000"
```

---

## Common Patterns

### Create an Invoice (Full Workflow)

1. **Find or create the customer.** Call GET /api/v1/ar/customers to check if
   the customer already exists. If not, create one with POST /api/v1/ar/customers.
2. **Identify the destination account.** Call GET /api/v1/accounts to get the
   Mercury account ID where payment should be deposited. If the user has multiple
   accounts, ask which one to use.
3. **Create the invoice.** Call POST /api/v1/ar/invoices with the customer ID,
   destination account ID, dates, and line items. Set `sendEmailOption` to
   `SendNow` only if the user explicitly asks to send it immediately.

### Check Outstanding Invoices

Call GET /api/v1/ar/invoices and look for invoices with status `sent` or
`pending`. Present a summary with amounts and due dates:

> "You have 3 outstanding invoices totaling $12,050.00:
>
> - Invoice #1042 — Acme Corp — $5,250.00 — due March 15, 2026
> - Invoice #1043 — Widget LLC — $4,000.00 — due March 20, 2026
> - Invoice #1044 — Startup Inc — $2,800.00 — due April 1, 2026"

### Download an Invoice PDF

Call GET /api/v1/ar/invoice/{invoiceId}/pdf with the `-o` flag to save the
binary response. The Content-Type is `application/pdf` — do not parse as JSON.

## Clarifying Questions

When the user asks to "send an invoice", ask:
> "To which customer, for what amount, and what's the due date?"

When the user says "invoice" without specifying an action, ask:
> "Would you like to create a new invoice, check the status of an existing one,
> or list all invoices?"

When the user asks to create an invoice without specifying a destination account
and they have multiple Mercury accounts, ask:
> "Which Mercury account should receive the payment? I can list your accounts
> first."
