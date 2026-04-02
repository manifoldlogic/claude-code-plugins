# Mercury API Endpoint Index

**Last Updated:** 2026-04-02

> OAuth2 endpoints (`/auth/authorize`, `/auth/token`) are excluded from this index. These endpoints require Mercury pre-approval and are documented as out of scope in prd.md.

This document contains the complete inventory of all 52 Mercury API endpoints organized by domain group. Each row links to the appropriate domain reference document for full request/response schemas.

## Accounts & Treasury (11 endpoints)

| Method | Path | Description | Safety | Reference |
|--------|------|-------------|--------|-----------|
| GET | /api/v1/accounts | List all accounts | SAFE | [accounts-and-treasury.md](accounts-and-treasury.md) |
| GET | /api/v1/account/{accountId} | Get account by ID | SAFE | [accounts-and-treasury.md](accounts-and-treasury.md) |
| GET | /api/v1/account/{accountId}/cards | Get cards for account | SAFE | [accounts-and-treasury.md](accounts-and-treasury.md) |
| GET | /api/v1/account/{accountId}/statements | Get account statements | SAFE | [accounts-and-treasury.md](accounts-and-treasury.md) |
| GET | /api/v1/account/{accountId}/transactions | List account transactions | SAFE | [accounts-and-treasury.md](accounts-and-treasury.md) |
| GET | /api/v1/account/{accountId}/transaction/{transactionId} | Get transaction by ID (account-scoped) | SAFE | [accounts-and-treasury.md](accounts-and-treasury.md) |
| GET | /api/v1/treasury | List all treasury accounts | SAFE | [accounts-and-treasury.md](accounts-and-treasury.md) |
| GET | /api/v1/treasury/{treasuryId}/transactions | Get treasury transactions | SAFE | [accounts-and-treasury.md](accounts-and-treasury.md) |
| GET | /api/v1/treasury/{treasuryId}/statements | Get treasury statements | SAFE | [accounts-and-treasury.md](accounts-and-treasury.md) |
| GET | /api/v1/credit | List all credit accounts | SAFE | [accounts-and-treasury.md](accounts-and-treasury.md) |
| GET | /api/v1/account/{accountId}/statement/{statementId}/pdf | Download statement PDF | SAFE | [accounts-and-treasury.md](accounts-and-treasury.md) |

## Transactions (4 endpoints)

| Method | Path | Description | Safety | Reference |
|--------|------|-------------|--------|-----------|
| GET | /api/v1/transactions | List all transactions | SAFE | [transactions.md](transactions.md) |
| GET | /api/v1/transaction/{transactionId} | Get transaction by ID | SAFE | [transactions.md](transactions.md) |
| PATCH | /api/v1/transaction/{transactionId} | Update transaction metadata | CONFIRM | [transactions.md](transactions.md) |
| POST | /api/v1/transaction/{transactionId}/attachment | Upload transaction attachment | CONFIRM | [transactions.md](transactions.md) |

## Recipients & Payments (9 endpoints)

| Method | Path | Description | Safety | Reference |
|--------|------|-------------|--------|-----------|
| GET | /api/v1/recipients | List all recipients | SAFE | [recipients-and-payments.md](recipients-and-payments.md) |
| GET | /api/v1/recipient/{recipientId} | Get recipient by ID | SAFE | [recipients-and-payments.md](recipients-and-payments.md) |
| POST | /api/v1/recipient | Add a new recipient | CONFIRM | [recipients-and-payments.md](recipients-and-payments.md) |
| POST | /api/v1/recipient/{recipientId} | Edit recipient information | CONFIRM | [recipients-and-payments.md](recipients-and-payments.md) |
| POST | /api/v1/recipient/{recipientId}/attachment | Upload recipient attachment | CONFIRM | [recipients-and-payments.md](recipients-and-payments.md) |
| POST | /api/v1/account/{accountId}/request-send-money | Request to send money | CRITICAL | [recipients-and-payments.md](recipients-and-payments.md) |
| POST | /api/v1/transfer | Create internal transfer | CRITICAL | [recipients-and-payments.md](recipients-and-payments.md) |
| GET | /api/v1/request-send-money/{requestId} | Get send money approval request | SAFE | [recipients-and-payments.md](recipients-and-payments.md) |
| GET | /api/v1/request-send-money | List send money approval requests | SAFE | [recipients-and-payments.md](recipients-and-payments.md) |

## Accounts Receivable (13 endpoints)

| Method | Path | Description | Safety | Reference |
|--------|------|-------------|--------|-----------|
| GET | /api/v1/ar/invoices | List all invoices | SAFE | [accounts-receivable.md](accounts-receivable.md) |
| POST | /api/v1/ar/invoices | Create an invoice | CONFIRM | [accounts-receivable.md](accounts-receivable.md) |
| GET | /api/v1/ar/invoice/{invoiceId} | Get an invoice | SAFE | [accounts-receivable.md](accounts-receivable.md) |
| POST | /api/v1/ar/invoice/{invoiceId} | Update an invoice | CONFIRM | [accounts-receivable.md](accounts-receivable.md) |
| POST | /api/v1/ar/invoice/{invoiceId}/cancel | Cancel an invoice | CONFIRM | [accounts-receivable.md](accounts-receivable.md) |
| GET | /api/v1/ar/invoice/{invoiceId}/attachments | List invoice attachments | SAFE | [accounts-receivable.md](accounts-receivable.md) |
| GET | /api/v1/ar/invoice/{invoiceId}/pdf | Download invoice PDF | SAFE | [accounts-receivable.md](accounts-receivable.md) |
| GET | /api/v1/ar/customers | List all customers | SAFE | [accounts-receivable.md](accounts-receivable.md) |
| POST | /api/v1/ar/customers | Create a customer | CONFIRM | [accounts-receivable.md](accounts-receivable.md) |
| GET | /api/v1/ar/customer/{customerId} | Get a customer | SAFE | [accounts-receivable.md](accounts-receivable.md) |
| POST | /api/v1/ar/customer/{customerId} | Update a customer | CONFIRM | [accounts-receivable.md](accounts-receivable.md) |
| DELETE | /api/v1/ar/customer/{customerId} | Delete a customer | CONFIRM | [accounts-receivable.md](accounts-receivable.md) |
| GET | /api/v1/ar/attachment/{attachmentId} | Get an attachment | SAFE | [accounts-receivable.md](accounts-receivable.md) |

## Webhooks & Events (8 endpoints)

| Method | Path | Description | Safety | Reference |
|--------|------|-------------|--------|-----------|
| GET | /api/v1/webhooks | List all webhooks | SAFE | [webhooks-and-events.md](webhooks-and-events.md) |
| GET | /api/v1/webhook/{webhookId} | Get webhook by ID | SAFE | [webhooks-and-events.md](webhooks-and-events.md) |
| POST | /api/v1/webhooks | Create webhook endpoint | CONFIRM | [webhooks-and-events.md](webhooks-and-events.md) |
| POST | /api/v1/webhook/{webhookId} | Update webhook endpoint | CONFIRM | [webhooks-and-events.md](webhooks-and-events.md) |
| POST | /api/v1/webhook/{webhookId}/verify | Verify webhook endpoint | CONFIRM | [webhooks-and-events.md](webhooks-and-events.md) |
| DELETE | /api/v1/webhook/{webhookId} | Delete webhook | CONFIRM | [webhooks-and-events.md](webhooks-and-events.md) |
| GET | /api/v1/events | Get all events | SAFE | [webhooks-and-events.md](webhooks-and-events.md) |
| GET | /api/v1/event/{eventId} | Get event by ID | SAFE | [webhooks-and-events.md](webhooks-and-events.md) |

## Organization, Users & Metadata (7 endpoints)

| Method | Path | Description | Safety | Reference |
|--------|------|-------------|--------|-----------|
| GET | /api/v1/organization | Get organization info | SAFE | [organization-and-users.md](organization-and-users.md) |
| GET | /api/v1/users | List all users | SAFE | [organization-and-users.md](organization-and-users.md) |
| GET | /api/v1/user/{userId} | Get user by ID | SAFE | [organization-and-users.md](organization-and-users.md) |
| GET | /api/v1/categories | List all categories | SAFE | [organization-and-users.md](organization-and-users.md) |
| GET | /api/v1/safes | List all SAFEs | SAFE | [organization-and-users.md](organization-and-users.md) |
| GET | /api/v1/safe/{safeId} | Get SAFE by ID | SAFE | [organization-and-users.md](organization-and-users.md) |
| GET | /api/v1/safe/{safeId}/document | Download SAFE document | SAFE | [organization-and-users.md](organization-and-users.md) |
