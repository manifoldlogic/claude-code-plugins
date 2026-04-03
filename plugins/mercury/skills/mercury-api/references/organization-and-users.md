# Organization & Users Reference — Mercury API

This document covers 7 read-only endpoints for organization metadata, user
management, transaction categories, and SAFEs (Simple Agreements for Future
Equity). All endpoints are SAFE — execute directly and present results
conversationally. For authentication, see [authentication.md](authentication.md).

## Organization Object Schema

The organization endpoint returns an object with these fields:

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Unique organization identifier |
| name | string | Organization display name |
| legalBusinessName | string | Legal business name on file |
| ein | string | Employer Identification Number (sensitive — see handling note below) |
| address | object | Organization address with street, city, state, zip fields |
| status | string | Organization status |

**EIN Handling:** The `ein` field is a sensitive tax identifier. Always mask the
EIN when presenting organization data (e.g., "XX-XXX1234"). Never display the
full EIN in conversational summaries. If the user explicitly requests the full
EIN, confirm they understand it is sensitive before displaying it. Default to
the masked format in all other cases.

## User Object Schema

User endpoints return objects with these fields:

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Unique user identifier |
| firstName | string | User's first name |
| lastName | string | User's last name |
| email | string | User's email address |
| role | string | User's role in the organization |
| createdAt | ISO 8601 | When the user was added |

## Category Object Schema

The categories endpoint returns objects with these fields:

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Category identifier |
| name | string | Category display name (e.g., "Software", "Payroll", "Marketing") |

Mercury provides a predefined list of transaction categories. The `categoryId`
field on transaction objects refers to these categories. Use GET /categories to
retrieve the full taxonomy when you need to display category names alongside
transactions.

## SAFE Object Schema

SAFE endpoints return objects with these fields:

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | SAFE identifier |
| name | string | SAFE name or description |
| amount | decimal | Investment amount |
| status | string | SAFE status |
| createdAt | ISO 8601 | When the SAFE was created |

**What is a SAFE?** A SAFE (Simple Agreement for Future Equity) is a common
early-stage investment instrument. It represents an agreement where an investor
provides capital in exchange for the right to receive equity at a future date.
Not all Mercury accounts have SAFEs — if the list endpoint returns an empty
array, inform the user that no SAFEs are associated with their account.

---

## GET /api/v1/organization

**Description:** Get organization info.
**Safety:** SAFE — execute directly without confirmation.

### Response

Returns a single Organization Object (not wrapped in a paginated envelope).

### curl Example

```bash
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  https://api.mercury.com/api/v1/organization
```

### Conversational Presentation

Present the organization name and legal business name. Acknowledge the EIN is
on file without displaying it:

> "Your organization is [Organization Name] (legal name: [Legal Business Name]).
> Your EIN is on file with Mercury."

---

## GET /api/v1/users

**Description:** List all users in the organization.
**Safety:** SAFE — execute directly without confirmation.

### Response

Returns a paginated response envelope with key `users` containing an array of
User Objects.

### curl Example

```bash
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  https://api.mercury.com/api/v1/users
```

### Conversational Presentation

Summarize the count and list each user:

> "Found [N] users in your organization:
>
> - Jane Smith (jane@example.com) — Admin
> - John Doe (john@example.com) — Member"

---

## GET /api/v1/user/{userId}

**Description:** Get a single user by ID.
**Safety:** SAFE — execute directly without confirmation.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| userId | UUID | Yes | The user ID to retrieve |

### Response

Returns a single User Object.

### curl Example

```bash
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  https://api.mercury.com/api/v1/user/550e8400-e29b-41d4-a716-446655440000
```

### Conversational Presentation

> "[First Name] [Last Name] ([email]) — role: [role]. Added on [Month DD, YYYY]."

---

## GET /api/v1/categories

**Description:** List all transaction categories.
**Safety:** SAFE — execute directly without confirmation.

This endpoint returns Mercury's predefined transaction category taxonomy. These
categories are referenced by the `categoryId` field on transaction objects. Use
this endpoint to look up category names when displaying transaction details or
when the user wants to categorize a transaction.

### Response

Returns a paginated response envelope with key `categories` containing an array
of Category Objects.

### curl Example

```bash
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  https://api.mercury.com/api/v1/categories
```

### Conversational Presentation

> "Mercury has [N] transaction categories available: Software, Payroll,
> Marketing, Office Supplies, ..."

List the category names. These are useful when the user wants to filter or
tag transactions by category.

---

## GET /api/v1/safes

**Description:** List all SAFEs associated with the account.
**Safety:** SAFE — execute directly without confirmation.

### Response

Returns a paginated response envelope with key `safes` containing an array of
SAFE Objects. If the account has no SAFEs, the array will be empty.

### curl Example

```bash
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  https://api.mercury.com/api/v1/safes
```

### Conversational Presentation

If SAFEs exist:
> "Found [N] SAFEs on your account: [SAFE Name] for $X,XXX.XX (status: [status])..."

If no SAFEs:
> "No SAFEs are associated with your Mercury account."

---

## GET /api/v1/safe/{safeId}

**Description:** Get a single SAFE by ID.
**Safety:** SAFE — execute directly without confirmation.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| safeId | UUID | Yes | The SAFE ID to retrieve |

### Response

Returns a single SAFE Object.

### curl Example

```bash
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  https://api.mercury.com/api/v1/safe/550e8400-e29b-41d4-a716-446655440000
```

### Conversational Presentation

> "SAFE: [SAFE Name] — $X,XXX.XX, status: [status]. Created [Month DD, YYYY]."

---

## GET /api/v1/safe/{safeId}/document

**Description:** Download the SAFE document.
**Safety:** SAFE — execute directly without confirmation.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| safeId | UUID | Yes | The SAFE whose document to download |

### Response

Returns binary PDF data with **Content-Type:** `application/pdf` (not JSON).
Save the response to a file rather than attempting to parse it as JSON.

### curl Example

```bash
curl -s -H "Authorization: Bearer ${MERCURY_TOKEN}" \
  -o safe-document.pdf \
  https://api.mercury.com/api/v1/safe/550e8400-e29b-41d4-a716-446655440000/document
```

### Conversational Presentation

> "Downloaded the SAFE document as safe-document.pdf."

---

## Common Patterns

- **Look up a user's name from their user ID:** When you have a `userId` from
  another API response (e.g., a transaction or activity log), call
  GET /api/v1/user/{userId} to retrieve the user's first name, last name, and
  email. Present the name instead of the raw UUID.

- **Get the category name for a transaction:** When a transaction has a
  `categoryId`, call GET /api/v1/categories to retrieve the full category list,
  then find the matching category by ID. Present the category name (e.g.,
  "Software") instead of the UUID.

- **Organization overview:** Call GET /api/v1/organization for business details,
  then GET /api/v1/users to list team members. This provides a complete picture
  of the account's organizational setup.

- **Check SAFE portfolio:** Call GET /api/v1/safes to list all SAFEs. For
  details on a specific SAFE, call GET /api/v1/safe/{safeId}. To download the
  agreement document, call GET /api/v1/safe/{safeId}/document and save the PDF.

## Clarifying Questions

When the user asks about "team members" or "who has access," this maps to the
users endpoint:
> "I can look up all users on your Mercury account. Would you like to see the
> full list?"

When the user mentions "categories" without context, clarify the intent:
> "Are you looking for the list of available transaction categories, or do you
> want to categorize a specific transaction?"
