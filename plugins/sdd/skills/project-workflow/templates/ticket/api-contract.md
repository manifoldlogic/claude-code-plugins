# API Contract: {NAME}

## Overview

[High-level description of the API being defined or modified. What is the purpose of this API? Who are the consumers? Is this a new API or changes to an existing one?]

**API Style:** [REST / GraphQL / gRPC / WebSocket / Other]
**Base URL:** [e.g., `https://api.example.com/v1`]
**Authentication:** [e.g., Bearer token, API key, OAuth 2.0, None]
**Target Consumers:** [e.g., Frontend SPA, Mobile apps, External partners, Internal services]

## Endpoints

[List all endpoints defined or modified by this ticket.]

### Overview Table

| Method | Path | Description | Auth Required |
|--------|------|-------------|---------------|
| [GET] | [/resource] | [List resources] | [Yes/No] |
| [GET] | [/resource/:id] | [Get single resource] | [Yes/No] |
| [POST] | [/resource] | [Create resource] | [Yes/No] |
| [PUT] | [/resource/:id] | [Update resource] | [Yes/No] |
| [DELETE] | [/resource/:id] | [Delete resource] | [Yes/No] |

### Endpoint 1: [Method] [Path]

**Description:** [What this endpoint does]

**Authorization:** [Required permissions or roles]

**Rate Limit:** [e.g., 100 requests/minute per API key]

**Path Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| [id] | [string/uuid] | [Yes] | [Resource identifier] |

**Query Parameters:**

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| [page] | [integer] | [No] | [1] | [Page number for pagination] |
| [limit] | [integer] | [No] | [20] | [Items per page (max 100)] |
| [sort] | [string] | [No] | [created_at] | [Sort field] |
| [order] | [string] | [No] | [desc] | [Sort direction: asc or desc] |

### Endpoint 2: [Method] [Path]

[Continue pattern for additional endpoints...]

## Request Schema

[Define request body schemas for POST/PUT/PATCH endpoints.]

### [Endpoint Name] Request

```json
{
  "field_name": "string (required) -- Description of field",
  "field_name_2": 42,
  "nested_object": {
    "sub_field": "string (optional) -- Description"
  },
  "array_field": ["string -- Description of array items"]
}
```

**Validation Rules:**

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| [field_name] | [string] | [Yes] | [1-255 chars, alphanumeric] |
| [field_name_2] | [integer] | [No] | [Min: 0, Max: 1000] |
| [nested_object.sub_field] | [string] | [No] | [Valid email format] |

### Content Types

- **Request:** [e.g., `application/json`]
- **Multipart:** [If file uploads supported, describe multipart format]

## Response Schema

[Define response body schemas for each endpoint.]

### Success Response

**Status:** [200 OK / 201 Created / 204 No Content]

```json
{
  "data": {
    "id": "uuid -- Resource identifier",
    "field_name": "string -- Description",
    "created_at": "ISO 8601 datetime",
    "updated_at": "ISO 8601 datetime"
  },
  "meta": {
    "request_id": "uuid -- Trace correlation ID"
  }
}
```

### List Response (Paginated)

**Status:** 200 OK

```json
{
  "data": [
    {
      "id": "uuid",
      "field_name": "string"
    }
  ],
  "pagination": {
    "page": 1,
    "limit": 20,
    "total_items": 150,
    "total_pages": 8,
    "has_next": true,
    "has_prev": false
  },
  "meta": {
    "request_id": "uuid"
  }
}
```

### Response Headers

| Header | Value | Description |
|--------|-------|-------------|
| [Content-Type] | [application/json] | [Response content type] |
| [X-Request-Id] | [uuid] | [Request correlation ID] |
| [X-RateLimit-Remaining] | [integer] | [Remaining requests in window] |
| [Cache-Control] | [e.g., max-age=300] | [Caching directive] |

## Error Handling

[How errors are communicated to consumers.]

### Error Response Format

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Human-readable error description",
    "details": [
      {
        "field": "field_name",
        "message": "Field-specific error message",
        "code": "REQUIRED"
      }
    ]
  },
  "meta": {
    "request_id": "uuid"
  }
}
```

### Error Codes

| HTTP Status | Error Code | Description | Consumer Action |
|-------------|-----------|-------------|-----------------|
| 400 | `VALIDATION_ERROR` | [Request body validation failed] | [Fix request payload] |
| 400 | `INVALID_PARAMETER` | [Query or path parameter invalid] | [Check parameter format] |
| 401 | `UNAUTHORIZED` | [Missing or invalid auth token] | [Authenticate and retry] |
| 403 | `FORBIDDEN` | [Insufficient permissions] | [Request access from admin] |
| 404 | `NOT_FOUND` | [Resource does not exist] | [Verify resource ID] |
| 409 | `CONFLICT` | [Resource state conflict] | [Resolve conflict and retry] |
| 422 | `UNPROCESSABLE` | [Valid syntax but semantic error] | [Fix business logic issue] |
| 429 | `RATE_LIMITED` | [Too many requests] | [Back off and retry with exponential backoff] |
| 500 | `INTERNAL_ERROR` | [Unexpected server error] | [Retry, report if persistent] |
| 503 | `SERVICE_UNAVAILABLE` | [Temporary service outage] | [Retry with backoff] |

### Error Design Principles

- [ ] Error messages are safe to display to end users (no internal details)
- [ ] Error codes are machine-readable (constant strings, not HTTP status alone)
- [ ] Validation errors list ALL failed fields, not just the first
- [ ] 500 errors never expose stack traces, SQL queries, or internal paths
- [ ] Request ID included in every error response for support correlation

## Versioning

[How is the API versioned? What happens when breaking changes are introduced?]

### Versioning Strategy

- **Method:** [URL path versioning (`/v1/`) / Header (`Accept: application/vnd.api.v1+json`) / Query param (`?version=1`)]
- **Current Version:** [e.g., v1]
- **Deprecation Policy:** [e.g., Previous version supported for 6 months after new version release]

### Breaking Change Policy

A breaking change is any change that could cause existing consumers to fail:

- Removing or renaming a field from the response
- Changing a field's type
- Adding a new required field to the request
- Changing error response format
- Removing an endpoint
- Changing authentication requirements

**Breaking changes require:**
- [ ] Version increment (e.g., v1 to v2)
- [ ] Deprecation notice with timeline
- [ ] Migration guide for consumers
- [ ] Parallel support for old version during transition

### Non-Breaking Changes (Safe to Deploy)

- Adding optional fields to request
- Adding new fields to response
- Adding new endpoints
- Adding new error codes
- Relaxing validation constraints
- Adding new query parameters with defaults

## Examples

[Concrete request/response examples for key operations.]

### Example 1: [Operation Name]

**Request:**
```http
[METHOD] [/path] HTTP/1.1
Host: api.example.com
Authorization: Bearer eyJhbGc...
Content-Type: application/json

{
  "field": "example_value"
}
```

**Response (Success):**
```http
HTTP/1.1 [200 OK]
Content-Type: application/json

{
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "field": "example_value",
    "created_at": "2025-01-15T10:30:00Z"
  }
}
```

### Example 2: [Operation Name]

[Continue pattern for additional examples, including error response cases.]

## API Checklist

- [ ] All endpoints documented with method, path, and description
- [ ] Request schemas defined with validation rules
- [ ] Response schemas defined with field descriptions
- [ ] Error codes and response format documented
- [ ] Authentication and authorization requirements specified
- [ ] Pagination strategy defined for list endpoints
- [ ] Rate limiting documented
- [ ] Versioning strategy defined
- [ ] Breaking vs non-breaking change policy documented
- [ ] Examples provided for key operations
- [ ] Consumer migration path clear (if modifying existing API)

## N/A Sign-Off (If Not Applicable)

If this document is not applicable to the current ticket, complete this section instead:

**Status:** N/A
**Assessed:** {date}

### Assessment
{1-3 sentence justification}

### Re-evaluate If
{Condition that would make this document applicable}
