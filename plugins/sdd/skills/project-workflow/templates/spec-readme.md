# Project Specification

This directory contains the accumulated requirements and design decisions for this project, organized by domain area. Each Markdown file represents a single domain (e.g., `caching.md`, `authentication.md`, `api-design.md`) and contains formal requirement statements that have been extracted from completed, merged work.

The spec grows incrementally. When a ticket is archived after its work has been merged to the main branch, the archiving process extracts key requirements and appends them to the appropriate domain file -- or creates a new domain file if no existing one covers the topic. Over time, this directory becomes the authoritative record of what the system is required to do.

## RFC 2119 Conventions

Every domain spec file in this directory uses uppercase keywords with precise meanings defined by [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt). These keywords are:

- **MUST** / **MUST NOT** / **REQUIRED** / **SHALL** / **SHALL NOT** -- Absolute requirements. There are no exceptions.
- **SHOULD** / **SHOULD NOT** / **RECOMMENDED** -- There may be valid reasons to ignore these in particular circumstances, but the full implications must be understood and carefully weighed.
- **MAY** / **OPTIONAL** -- The item is truly optional. Implementations may include or omit the feature.

These keywords matter because they remove ambiguity. When a spec file says "The system MUST validate input before processing," that is a hard requirement, not a suggestion. When it says "The system SHOULD cache responses," that is a strong recommendation that can be overridden with justification.

Example requirement statement:

> - The system MUST authenticate all API requests before processing. [Source: AUTH-001]

The `[Source: ...]` annotation traces the requirement back to the ticket that established it.

## File Naming Conventions

Domain spec files follow these rules:

- **Kebab-case names** -- Use lowercase words separated by hyphens (e.g., `error-handling.md`, `data-validation.md`).
- **No spaces** -- File names never contain spaces.
- **`.md` extension** -- All spec files are Markdown.
- **Semantic domain names** -- The file name describes the domain area it covers, not the ticket or feature that created it. For example, use `caching.md` rather than `CACHE-ticket.md`.
- **Prefer extending existing files** -- Before creating a new domain file, check whether an existing file already covers a related topic. For example, if `auth.md` exists, do not create `authentication.md`.

## How to Read the Spec

Each domain file is **self-contained**. You do not need to read any other file to understand it. Every file includes the RFC 2119 boilerplate at the top, which establishes the meaning of uppercase keywords within that file.

To get an overview of the project's requirements:

1. List the files in this directory to see which domains are covered.
2. Open any domain file and read its requirement statements. Each statement is a single bullet point using RFC 2119 language.
3. The `[Source: ...]` annotation on each requirement tells you which ticket established it, if you need to trace the history or rationale.

There is no required reading order. Each file stands on its own.

## How Requirements Are Added

Requirements are added to this directory through the `/sdd:archive` process, not by manual editing. When a completed ticket is archived:

1. The archive process verifies that the ticket's work has been merged to the main branch.
2. An agent reads the ticket's planning documents and implementation decisions.
3. The agent identifies requirements that should be part of the project specification.
4. Those requirements are written in RFC 2119 format and appended to the appropriate domain file (or a new domain file is created if needed).

This process ensures that only verified, merged work contributes to the spec. The spec reflects what the project actually does, not what was planned but never implemented.
