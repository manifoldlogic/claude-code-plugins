---
name: mercury-api
description: >
  Use when the user asks to check their balance, see account info, review recent
  transactions, show who they paid, look up a payment, send money, create a transfer,
  manage recipients, create or send an invoice, check invoice status, manage webhooks,
  or perform any Mercury banking operation. Trigger phrases: "check my balance",
  "how much is in my account", "show recent transactions", "who did I pay",
  "send money to", "pay [person]", "create an invoice", "what invoices are outstanding".
---

# Mercury API Skill

**Last Updated:** 2026-04-02
**Mercury API Version:** v1
**Base URL:** `https://api.mercury.com/api/v1`
**Full Endpoint Index:** [references/endpoint-index.md](references/endpoint-index.md) (52 endpoints)

## Overview

This skill provides structured access to the Mercury banking API. Read this document first for every Mercury interaction. It routes user intent to the correct domain reference document, provides authentication and pagination patterns, and defines safety gates for financial operations.

All Mercury endpoints share the same base URL, authentication, pagination, and error patterns. Use the decision tree below to identify the correct domain, then read the linked reference document for full endpoint schemas.

## Authentication Quick Reference

All requests require a Mercury API token via the `MERCURY_TOKEN` environment variable. Before making any API call, verify the token is set:

```sh
echo ${MERCURY_TOKEN}
```

If the variable is empty, instruct the user to generate a token in their Mercury dashboard and set it in their environment.

**Bearer Auth (preferred):**

```sh
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  "https://api.mercury.com/api/v1/accounts"
```

**Basic Auth (alternative):**

```sh
curl -s -u "${MERCURY_TOKEN}:" \
  "https://api.mercury.com/api/v1/accounts"
```

Mercury tokens have three tiers: Read Only (GET operations only), Read and Write (all operations, requires IP whitelisting), and Custom (selected scopes). If a request returns 403, the token may lack required permissions or the IP may not be whitelisted.

For full authentication details including token setup, IP whitelisting, rotation, and auto-downgrade policies, read [references/authentication.md](references/authentication.md).

## Safety Classifications

Every Mercury endpoint carries one of three safety tiers. Follow these behavioral rules strictly.

### SAFE (All GET Endpoints)

Execute the request directly without asking the user for permission. Present results in conversational language. Do not dump raw JSON.

### CONFIRM (Non-Financial Write Operations)

These operations modify data but do not move money. Before executing:

1. Describe the operation in plain language, showing all details.
2. Ask the user for explicit confirmation.
3. Execute only after receiving approval.

Examples: create or edit a recipient, create or update an invoice, manage webhooks, update transaction metadata, upload attachments, create or delete a customer.

Gate language example: "I'll create a new recipient named 'Acme Corp' with ACH routing to the account ending in 4321. Should I go ahead?"

### CRITICAL (Money Movement Operations)

These operations send real money and cannot be undone. Before executing:

1. Display ALL operation details: amount, source account, destination, payment method.
2. Present details in human-readable format with formatted currency.
3. Ask for explicit confirmation with a clear warning.
4. Execute only after receiving an explicit "yes."

Only two endpoints carry this tier:
- `POST /account/{accountId}/request-send-money` -- sends money to a recipient
- `POST /transfer` -- moves money between Mercury accounts

Gate language example: "CRITICAL: This will send $5,000.00 from your Operating Account to Acme Corp via ACH. This moves real money and cannot be undone. Please confirm by replying 'yes' to proceed."

**Cowork Policy:** Never execute any write operation silently. Agents must always present full operation details and wait for explicit user approval before executing CONFIRM or CRITICAL operations. This is a hard requirement aligned with Cowork's financial safety policy.

## Decision Tree

Use this tree to route user requests to the correct domain and reference document.

**If the user asks about money in their account, account balances, cards, statements, treasury, or credit:**
Read [references/accounts-and-treasury.md](references/accounts-and-treasury.md)

**If the user asks about recent transactions, payment history, transaction details, or wants to tag or annotate a transaction:**
Read [references/transactions.md](references/transactions.md)

**If the user asks to send money, pay someone, set up a payee, transfer funds between accounts, or manage payment recipients:**
Read [references/recipients-and-payments.md](references/recipients-and-payments.md)

**If the user asks to create an invoice, check invoice status, manage customers, or handle accounts receivable:**
Read [references/accounts-receivable.md](references/accounts-receivable.md)

**If the user asks about webhooks, event notifications, or integration callbacks:**
Read [references/webhooks-and-events.md](references/webhooks-and-events.md)

**If the user asks about their organization, team members, spending categories, or SAFEs:**
Read [references/organization-and-users.md](references/organization-and-users.md)

**If the user asks about authentication, token setup, permissions, or IP whitelisting:**
Read [references/authentication.md](references/authentication.md)

## Domain Summary

| Domain | Endpoints | Example Triggers | Reference |
|--------|-----------|------------------|-----------|
| Accounts & Treasury | 11 | "check my balance", "show my accounts", "treasury balances" | [references/accounts-and-treasury.md](references/accounts-and-treasury.md) |
| Transactions | 4 | "show recent transactions", "transaction details", "tag a payment" | [references/transactions.md](references/transactions.md) |
| Recipients & Payments | 9 | "send money to", "pay Acme Corp", "who did I pay", "transfer funds" | [references/recipients-and-payments.md](references/recipients-and-payments.md) |
| Accounts Receivable | 13 | "create an invoice", "what invoices are outstanding", "add a customer" | [references/accounts-receivable.md](references/accounts-receivable.md) |
| Webhooks & Events | 8 | "set up notifications", "list webhooks", "recent events" | [references/webhooks-and-events.md](references/webhooks-and-events.md) |
| Organization & Users | 7 | "who is on my team", "show categories", "organization info" | [references/organization-and-users.md](references/organization-and-users.md) |
| Authentication | ref | "set up my API token", "check permissions", "IP whitelist" | [references/authentication.md](references/authentication.md) |

For the complete 52-endpoint table with HTTP methods, paths, and safety classifications, see [references/endpoint-index.md](references/endpoint-index.md).

## Pagination Pattern

All list endpoints use cursor-based pagination. The response envelope includes a `page` object with `nextPage` and `previousPage` cursor values.

**First page:**

```sh
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  "https://api.mercury.com/api/v1/transactions?limit=25"
```

**Next page (using cursor from previous response):**

```sh
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  "https://api.mercury.com/api/v1/transactions?limit=25&start_after=CURSOR_UUID"
```

Replace `CURSOR_UUID` with the `page.nextPage` value from the previous response. When `page.nextPage` is `null`, there are no more results. Supported parameters: `limit`, `order`, `start_after`, `end_before`.

## Common Scenarios

### Scenario 1: "Check my balance"

1. Execute: `GET /accounts`
2. Present results conversationally:
   - "You have 2 Mercury accounts:"
   - "Operating Account (checking): balance $50,000.00, available $49,500.00"
   - "Savings Account: balance $125,000.00, available $125,000.00"
3. If multiple accounts exist and the user asked about a specific one, filter by name or type.
4. If only one account exists, present it directly without asking which one.

### Scenario 2: "Show recent transactions"

1. Ask a clarifying question if needed: "Would you like transactions from all accounts or a specific one? And for what time period?"
2. Execute: `GET /transactions?limit=10` (or account-scoped variant)
3. Present as a formatted list:
   - "Here are your 10 most recent transactions:"
   - "January 15, 2026 -- Acme Corp -- -$1,500.00 (ACH)"
   - "January 14, 2026 -- Deposit -- +$10,000.00 (Wire)"
4. Offer to export: "Would you like me to save these as a spreadsheet (.xlsx)?"

### Scenario 3: "Send $500 to Acme Corp"

1. This is a CRITICAL operation. Look up the recipient first: `GET /recipients` to find Acme Corp.
2. If the recipient is not found, inform the user and offer to create one (CONFIRM gate).
3. If multiple accounts exist, ask: "Which account should I send from -- checking or savings?"
4. Present full details before executing:
   - "CRITICAL: This will send $500.00 from your Operating Account to Acme Corp via ACH. This moves real money and cannot be undone. Please confirm by replying 'yes' to proceed."
5. Only after explicit confirmation, execute: `POST /account/{accountId}/request-send-money`

### Scenario 4: "Create an invoice for Jane Doe"

1. This is a CONFIRM operation. Check if Jane Doe exists as a customer: `GET /ar/customers`
2. If not found, offer to create the customer first (also CONFIRM).
3. Gather required details: invoice amount, line items, due date, destination account.
4. Present full details before executing:
   - "I'll create an invoice for Jane Doe: 1 item -- 'Consulting Services' at $2,500.00, due February 15, 2026, payment deposited to your Operating Account. Should I go ahead?"
5. Only after confirmation, execute: `POST /ar/invoices`

## Presentation Guidelines

Follow these rules when presenting Mercury API results to the user.

**Currency:** Format all monetary values as "$X,XXX.XX" with commas and two decimal places. Negative amounts represent debits: "-$1,500.00".

**Dates:** Format all dates as "Month DD, YYYY" (e.g., "January 15, 2026"). Do not use ISO timestamps in user-facing output.

**Lists:** Summarize the count before listing items: "Found 3 accounts:" or "Here are your 10 most recent transactions:".

**UUIDs:** Never show raw UUIDs to the user. Refer to resources by name, account nickname, or other human-readable identifiers.

**Ambiguity:** When a request is ambiguous, ask a clarifying question before proceeding:
- "Which account -- checking or savings?"
- "For what time period -- last 7 days, last 30 days, or a custom range?"
- "Did you mean the recipient named 'Acme Corp' or 'Acme LLC'?"

**Raw JSON:** Never present raw JSON API responses to the user. Always parse and format results into conversational language.

## Document Output Guidance

Cowork has built-in document creation capabilities. Offer to save results as documents when appropriate:

| Output Type | Format | When to Offer |
|-------------|--------|---------------|
| Transaction exports | .xlsx | When listing more than 5 transactions, or when user asks for an export |
| Account statements | .pdf | When user requests a statement or account summary |
| Spending reports | .docx | When user asks for a spending breakdown or financial summary |
| Invoice lists | .xlsx | When listing multiple invoices or AR summaries |

Mention that outputs can be saved to the workspace folder for the user to download or share.

## Error Handling Quick Reference

When a Mercury API call returns an error, interpret the status code and present a helpful message to the user. Do not show raw error JSON.

| Status | Meaning | What to Tell the User |
|--------|---------|----------------------|
| 400 | Bad Request | "The request had invalid parameters. Let me fix that and try again." |
| 401 | Unauthorized | "The API token appears to be missing or invalid. Please check that MERCURY_TOKEN is set correctly." |
| 403 | Forbidden | "The token does not have permission for this operation. This may require a Read and Write token, or the IP address may need to be whitelisted." |
| 404 | Not Found | "That resource was not found. It may have been deleted or the ID may be incorrect." |
| 409 | Conflict | "There was a conflict -- this may be a duplicate request. I'll use a new idempotency key and retry." |
| 422 | Unprocessable Entity | "The request was valid but Mercury rejected it due to a business rule. Let me check the details." |
| 429 | Too Many Requests | "Mercury is rate-limiting requests. I'll wait a moment and try again." |
| 500 | Server Error | "Mercury is experiencing a server issue. I'll retry in a moment." |

Mercury error responses follow the format `{"errors": [{"message": "..."}]}`. Use the `message` field to provide specific context when available.

## Observability

When executing Mercury API operations on behalf of the user, follow these reporting guidelines:

- Log which endpoint was called and whether it succeeded or failed.
- For failed requests, include the HTTP status code and error message in the report.
- Redact sensitive data from any logs or reports: never include full account numbers, routing numbers, token values, or recipient bank details.
- For CRITICAL operations, log the confirmation exchange (that confirmation was requested and received).

## Last Updated

- **Document Date:** April 2, 2026
- **Mercury API Version:** v1 (`/api/v1/`)
- **Endpoint Count:** 52 (OAuth2 endpoints excluded; see [references/endpoint-index.md](references/endpoint-index.md))
