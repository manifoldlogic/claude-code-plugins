# Accounts & Treasury Reference — Mercury API

This document covers 11 read-only endpoints across the Accounts, Treasury, Credit,
and Statements domains. All endpoints are SAFE — execute directly and present
results conversationally. For authentication, see [authentication.md](authentication.md).

## Account Object Schema

All account endpoints return objects with these fields:

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Unique account identifier |
| accountNumber | string | Bank account number |
| routingNumber | string | Bank routing number |
| name | string | Account display name |
| nickname | string (nullable) | User-assigned nickname |
| status | string | One of: active, deleted, pending, archived |
| type | string | One of: mercury, external, recipient |
| kind | string | Account kind (e.g., checking, savings) |
| legalBusinessName | string | Legal name of the business |
| currentBalance | decimal | Current ledger balance |
| availableBalance | decimal | Available balance for transactions |
| canReceiveTransactions | boolean | Whether the account can receive funds |
| dashboardLink | URL | Link to the account in the Mercury dashboard |
| createdAt | ISO 8601 | Account creation timestamp |

## Pagination (All List Endpoints)

List endpoints accept these query parameters and return a cursor-based envelope:

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| limit | integer | No | Number of results per page |
| order | string | No | Sort order |
| start_after | UUID | No | Cursor: return results after this ID |
| end_before | UUID | No | Cursor: return results before this ID |

Response envelope:
```json
{
  "{resourceName}": [ ...results... ],
  "page": { "nextPage": "UUID or null", "previousPage": "UUID or null" }
}
```

Pass `nextPage` as `start_after` to page forward; pass `previousPage` as
`end_before` to page backward. When `nextPage` is `null`, all results are shown.

## Endpoints

### List All Accounts
- **Method:** GET
- **Path:** /api/v1/accounts
- **Safety:** SAFE

**Query Parameters:** See Pagination above. **Response Envelope key:** `accounts`

**Response Schema:** Returns an array of Account Objects (see schema above).

**Example:**
```bash
curl -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  https://api.mercury.com/api/v1/accounts
```

**Conversational Presentation:**
> "Found [N] accounts: Your [Account Name] ([kind]) has a balance of $X,XXX.XX available..."

### Get Account by ID
- **Method:** GET
- **Path:** /api/v1/account/{accountId}
- **Safety:** SAFE

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| accountId | UUID | The account to retrieve |

**Response Schema:** Returns a single Account Object.

**Example:**
```bash
curl -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  https://api.mercury.com/api/v1/account/550e8400-e29b-41d4-a716-446655440000
```

**Conversational Presentation:**
> "Your [Account Name] account (status: [status]) has a current balance of $X,XXX.XX and $X,XXX.XX available."

### Get Cards for Account
- **Method:** GET
- **Path:** /api/v1/account/{accountId}/cards
- **Safety:** SAFE

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| accountId | UUID | The account whose cards to list |

**Response Schema:**

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Card identifier |
| name | string | Cardholder or card name |
| status | string | Card status |
| lastFourDigits | string | Last four digits of the card number |

**Example:**
```bash
curl -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  https://api.mercury.com/api/v1/account/550e8400-e29b-41d4-a716-446655440000/cards
```

**Conversational Presentation:**
> "Found [N] cards on this account: [Card Name] ending in [lastFourDigits] (status: [status])..."

### Get Account Statements
- **Method:** GET
- **Path:** /api/v1/account/{accountId}/statements
- **Safety:** SAFE

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| accountId | UUID | The account whose statements to list |

**Response Schema:**

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Statement identifier |
| month | integer | Statement month (1-12) |
| year | integer | Statement year |
| startDate | date | Statement period start |
| endDate | date | Statement period end |

**Example:**
```bash
curl -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  https://api.mercury.com/api/v1/account/550e8400-e29b-41d4-a716-446655440000/statements
```

**Conversational Presentation:**
> "Found [N] statements. Most recent: [Month] [Year], covering [startDate] through [endDate]."

### List Account Transactions
- **Method:** GET
- **Path:** /api/v1/account/{accountId}/transactions
- **Safety:** SAFE

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| accountId | UUID | The account whose transactions to list |

**Query Parameters:** See Pagination above. **Response Envelope key:** `transactions`

**Response Schema:**

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Transaction identifier |
| amount | decimal | Transaction amount (negative for debits) |
| status | string | Transaction status |
| note | string (nullable) | User-added note |
| bankDescription | string | Bank-provided description |
| externalMemo | string | External-facing memo |
| createdAt | ISO 8601 | Transaction creation timestamp |
| postedAt | ISO 8601 (nullable) | When the transaction posted |
| estimatedDeliveryDate | date (nullable) | Estimated delivery for pending transactions |
| mercuryCategory | object (nullable) | Mercury-assigned category (id, name) |
| customCategory | object (nullable) | User-assigned category (id, name) |

**Example:**
```bash
curl -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  "https://api.mercury.com/api/v1/account/550e8400-e29b-41d4-a716-446655440000/transactions?limit=25"
```

**Conversational Presentation:**
> "Found [N] transactions. Recent: [bankDescription] for $X,XXX.XX on [Month DD, YYYY]..."

For full transaction operations including filtering, metadata updates, and
attachments, see [transactions.md](transactions.md).

### Get Transaction by ID (Account-Scoped)
- **Method:** GET
- **Path:** /api/v1/account/{accountId}/transaction/{transactionId}
- **Safety:** SAFE

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| accountId | UUID | The account containing the transaction |
| transactionId | UUID | The transaction to retrieve |

**Response Schema:** Same as the transaction object in List Account Transactions.

**Example:**
```bash
curl -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  https://api.mercury.com/api/v1/account/550e8400-e29b-41d4-a716-446655440000/transaction/660f9511-f3ac-52e5-b827-557766551111
```

**Conversational Presentation:**
> "Transaction [bankDescription]: $X,XXX.XX, status [status], posted [Month DD, YYYY]."

This is the account-scoped lookup. For cross-account search and PATCH operations,
see [transactions.md](transactions.md).

### List All Treasury Accounts
- **Method:** GET
- **Path:** /api/v1/treasury
- **Safety:** SAFE

**Response Schema:**

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Treasury account identifier |
| name | string | Treasury account name |
| currentBalance | decimal | Current balance |
| status | string | Account status |
| createdAt | ISO 8601 | Creation timestamp |

**Example:**
```bash
curl -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  https://api.mercury.com/api/v1/treasury
```

**Conversational Presentation:**
> "Found [N] treasury accounts: [Treasury Name] with a balance of $X,XXX.XX..."

### Get Treasury Transactions
- **Method:** GET
- **Path:** /api/v1/treasury/{treasuryId}/transactions
- **Safety:** SAFE

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| treasuryId | UUID | The treasury account whose transactions to list |

**Query Parameters:** See Pagination above. **Response Envelope key:** `transactions`

**Example:**
```bash
curl -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  "https://api.mercury.com/api/v1/treasury/550e8400-e29b-41d4-a716-446655440000/transactions?limit=25"
```

**Conversational Presentation:**
> "Found [N] transactions in your [Treasury Name] account. Recent: $X,XXX.XX on [Month DD, YYYY]..."

### Get Treasury Statements
- **Method:** GET
- **Path:** /api/v1/treasury/{treasuryId}/statements
- **Safety:** SAFE

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| treasuryId | UUID | The treasury account whose statements to list |

**Response Schema:**

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Statement identifier |
| month | integer | Statement month (1-12) |
| year | integer | Statement year |
| startDate | date | Statement period start |
| endDate | date | Statement period end |

**Example:**
```bash
curl -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  https://api.mercury.com/api/v1/treasury/550e8400-e29b-41d4-a716-446655440000/statements
```

**Conversational Presentation:**
> "Found [N] statements for your treasury account. Most recent: [Month] [Year]."

### List All Credit Accounts
- **Method:** GET
- **Path:** /api/v1/credit
- **Safety:** SAFE

**Response Schema:**

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Credit account identifier |
| name | string | Credit account name |
| currentBalance | decimal | Current balance (amount owed) |
| status | string | Account status |
| createdAt | ISO 8601 | Creation timestamp |

**Example:**
```bash
curl -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  https://api.mercury.com/api/v1/credit
```

**Conversational Presentation:**
> "Found [N] credit accounts: [Credit Account Name] with a current balance of $X,XXX.XX..."

### Download Statement PDF
- **Method:** GET
- **Path:** /api/v1/account/{accountId}/statement/{statementId}/pdf
- **Safety:** SAFE

**Path Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| accountId | UUID | The account owning the statement |
| statementId | UUID | The statement to download |

**Response:** Binary PDF data with **Content-Type:** `application/pdf` (not JSON).
Save the response to a file rather than attempting to parse it as JSON.

**Example:**
```bash
curl -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  -o statement.pdf \
  https://api.mercury.com/api/v1/account/550e8400-e29b-41d4-a716-446655440000/statement/660f9511-f3ac-52e5-b827-557766551111/pdf
```

**Conversational Presentation:**
> "Downloaded the statement as statement.pdf for [Month] [Year]."

## Common Patterns

- **Check balances across all account types:** Call GET /api/v1/accounts for
  checking and savings, then GET /api/v1/treasury and GET /api/v1/credit.
  Summarize totals across all types.

- **Find a specific account by name:** Call GET /api/v1/accounts and filter the
  results by `name` or `nickname` client-side. No server-side name filter exists.

- **Get a full account picture:** Call GET /account/{accountId} for balances,
  GET /account/{accountId}/transactions for recent activity, and
  GET /account/{accountId}/statements for available statements.

- **Download a statement:** First call GET /account/{accountId}/statements to
  find the statement ID, then GET /account/{accountId}/statement/{statementId}/pdf.
  Save output with the `-o` flag.

- **Transaction domain overlap:** The account-scoped transaction endpoints are
  documented here for convenience. For cross-account search, advanced filtering,
  PATCH, and attachments, see [transactions.md](transactions.md).

## Clarifying Questions

When the user asks about "my account" without specifying a type, ask:
> "Which account are you referring to -- checking, savings, treasury, or credit?"

When the user asks for a statement without specifying a period, ask:
> "Which statement period would you like? I can list all available statements first."

When the user asks for transactions without specifying an account, ask:
> "Which account's transactions would you like to see? I can list your accounts first."
