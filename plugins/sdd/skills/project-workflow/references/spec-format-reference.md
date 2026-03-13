# Spec Format Reference

This document is the authoritative reference for agents performing spec extraction (during archive) and spec consultation (during planning). It defines the format, conventions, and rules for domain spec files in `${SDD_ROOT_DIR}/spec/`.

## RFC 2119 Boilerplate

Every domain spec file MUST include the following boilerplate immediately after the top-level heading. This text MUST be reproduced verbatim -- do not paraphrase or abbreviate it:

```
The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD",
"SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be
interpreted as described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).
```

This boilerplate establishes that uppercase keywords in the file carry their RFC 2119 meanings. Including it per file ensures each file is self-contained and interpretable independently.

## Domain Spec File Format

A domain spec file has three structural elements:

1. **Top-level heading** -- `# {Domain Name} Specification`
2. **RFC 2119 boilerplate** -- The verbatim block above
3. **Subsections** -- `## {Subsection}` headings containing requirement bullet points

### Complete Example

```markdown
# Authentication Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD",
"SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be
interpreted as described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).

## Request Authentication

- The system MUST require a valid authentication token on all API requests. [Source: AUTH-001]
- The system MUST reject requests with expired tokens and return a 401 status code. [Source: AUTH-001]
- The system SHOULD support token refresh without requiring re-authentication. [Source: AUTH-003]

## Session Management

- The system MUST invalidate all active sessions when a user changes their password. [Source: SEC-012]
- The system MAY allow users to view and revoke individual sessions. [Source: SEC-012]
```

## Requirement Statement Format

Each requirement is a single bullet point following this pattern:

```
- The system MUST/MUST NOT/SHOULD/SHOULD NOT/MAY {requirement}. [Source: {TICKET_ID}]
```

Rules for requirement statements:

- Each statement MUST use exactly one RFC 2119 keyword (MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT, RECOMMENDED, MAY, OPTIONAL).
- Each statement MUST be a single, testable assertion. Do not combine multiple requirements into one bullet.
- Each statement MUST end with a `[Source: {TICKET_ID}]` annotation identifying the ticket that established or last modified the requirement.
- If a later ticket modifies an existing requirement, UPDATE the statement text and append the new ticket ID: `[Source: AUTH-001, AUTH-007]`.
- Use the strongest applicable keyword. Prefer MUST over SHOULD when the requirement is truly mandatory.
- Capture WHAT the system does, not HOW it implements it. Avoid implementation details.

## Domain Naming Conventions

Domain files are named by the area of concern they cover. The following rules apply:

- **Kebab-case** -- Lowercase words separated by hyphens (e.g., `error-handling.md`, `data-validation.md`).
- **No spaces** -- File names MUST NOT contain spaces.
- **`.md` extension** -- All domain spec files use the Markdown extension.
- **Semantic names** -- The file name describes the domain, not the ticket. Use `caching.md`, not `CACHE-001-ticket.md`.
- **No synonymous files** -- Before creating a new file, list existing files with `ls ${SDD_ROOT_DIR}/spec/*.md` and check for semantically related names. If `auth.md` exists, do not create `authentication.md`. Append to the existing file instead.

## File Size Guideline

Each domain spec file SHOULD stay under 500 lines. This keeps files within a comfortable range for agent context windows and human readability.

If a domain file approaches or exceeds 500 lines, split it into sub-domain files:

- `api-design.md` (490 lines) might split into `api-design-rest.md` and `api-design-graphql.md`
- `error-handling.md` (520 lines) might split into `error-handling-client.md` and `error-handling-server.md`

When splitting, preserve the RFC 2119 boilerplate in each new file and update `[Source: ...]` annotations to remain accurate.

## Append vs. Create Rules

When writing requirements during archive extraction, follow this decision process:

1. **List existing files first** -- Always run `ls ${SDD_ROOT_DIR}/spec/*.md` before deciding where to write.
2. **Match to existing file** -- If an existing file covers a semantically related domain, append requirements to the appropriate subsection in that file.
3. **Create new subsection** -- If the existing file covers the domain but lacks a relevant subsection, add a new `## {Subsection}` heading and write the requirements under it.
4. **Create new file** -- Only create a new domain file when no existing file is semantically related. Include the top-level heading, RFC 2119 boilerplate, at least one subsection, and the requirement statements.

The goal is to consolidate related requirements rather than scatter them across many small files. A well-organized spec has fewer, more comprehensive domain files rather than one file per ticket.
