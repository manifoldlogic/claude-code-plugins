#!/usr/bin/env bash
#
# Scaffold Ticket Structure
# Creates the folder structure for a new ticket
#
# Usage:
#   bash scaffold-ticket.sh <TICKET_ID> <name>
#
# Arguments:
#   TICKET_ID  - Ticket identifier (4-12 chars, uppercase with optional dashes for Jira IDs like UIT-9819)
#   name       - Ticket name (kebab-case)
#
# Output:
#   JSON with created structure

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../templates/ticket"
SDD_ROOT_DIR="${SDD_ROOT_DIR:-/app/.sdd}"

error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }

usage() {
    cat << EOF
Usage: $(basename "$0") <TICKET_ID> <name>

Arguments:
  TICKET_ID  Ticket identifier (e.g., APIV2, DKRHUB, or Jira ID like UIT-9819)
  name       Ticket name (kebab-case, e.g., "api-redesign")

Examples:
  $(basename "$0") APIV2 api-version-2
  $(basename "$0") DKRHUB docker-hub-publishing
  $(basename "$0") UIT-9819 user-profile-update    # Jira-based ticket ID

Output:
  JSON object with created structure
EOF
    exit 1
}

validate_ticket_id() {
    local ticket_id="$1"
    # Allow formats like: APIV2, DKRHUB (4-8 uppercase) OR UIT-9819, PROJ-123 (Jira-style)
    # Pattern: Start with uppercase letter, then alphanumeric, optionally followed by dash + alphanumeric segments
    if [[ ! "$ticket_id" =~ ^[A-Z][A-Z0-9]*(-[A-Z0-9]+)*$ ]]; then
        error "Invalid TICKET_ID format."
        error "Valid formats: APIV2, DKRHUB (uppercase) or UIT-9819, PROJ-123 (Jira-style)"
        exit 1
    fi
    # Check reasonable length (2-12 chars)
    if [[ ${#ticket_id} -lt 2 ]] || [[ ${#ticket_id} -gt 12 ]]; then
        error "TICKET_ID must be 2-12 characters. Got: ${#ticket_id}"
        exit 1
    fi
}

validate_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]] && [[ ! "$name" =~ ^[a-z]$ ]]; then
        error "Invalid name format. Use lowercase letters, numbers, and hyphens."
        error "Example: api-redesign, docker-hub-publishing"
        exit 1
    fi
}

check_ticket_id_unique() {
    local ticket_id="$1"
    # Check active tickets
    if ls -d "$SDD_ROOT_DIR/tickets/${ticket_id}_"* 2>/dev/null | grep -q .; then
        error "TICKET_ID '$ticket_id' already exists in active tickets"
        exit 1
    fi
    # Check archived tickets
    if ls -d "$SDD_ROOT_DIR/archive/tickets/${ticket_id}_"* 2>/dev/null | grep -q .; then
        warn "TICKET_ID '$ticket_id' exists in archived tickets - proceeding with caution"
    fi
}

main() {
    if [[ $# -lt 2 ]]; then
        usage
    fi

    local ticket_id="$1"
    local name="$2"
    local folder_name="${ticket_id}_${name}"
    local ticket_path="$SDD_ROOT_DIR/tickets/$folder_name"

    validate_ticket_id "$ticket_id"
    validate_name "$name"
    check_ticket_id_unique "$ticket_id"

    # Check if already exists
    if [[ -d "$ticket_path" ]]; then
        error "Ticket already exists: $ticket_path"
        exit 1
    fi

    info "Creating ticket: $folder_name"

    # Create directory structure
    mkdir -p "$ticket_path"/{planning,tasks,deliverables}

    # Create README.md
    cat > "$ticket_path/README.md" << EOF
# Ticket: ${name//-/ }

**Ticket ID:** $ticket_id
**Status:** Planning
**Created:** $(date +%Y-%m-%d)

## Summary

[Brief description of the ticket]

## Problem Statement

[What problem does this ticket solve?]

## Proposed Solution

[High-level approach to solving the problem]

## Relevant Agents

- ticket-planner (planning phase)
- task-creator (ticket generation)
- [implementation agents]
- verify-task (verification)
- commit-task (commit)

## Deliverables

Work products created during ticket execution (if applicable):

See [deliverables/](deliverables/) for analysis reports, findings documents, and verification artifacts.

## Planning Documents

- [analysis.md](planning/analysis.md) - Problem analysis
- [PRD](planning/prd.md) - Product Requirements Document
- [architecture.md](planning/architecture.md) - Solution design
- [plan.md](planning/plan.md) - Execution plan
- [quality-strategy.md](planning/quality-strategy.md) - Testing approach
- [security-review.md](planning/security-review.md) - Security assessment

## Tasks

See [tasks/](tasks/) for all ticket tasks.
EOF

    # Create analysis.md template
    cat > "$ticket_path/planning/analysis.md" << EOF
# Analysis: ${name//-/ }

## Problem Definition

[Clear statement of the problem being solved]

## Context

[Background information and why this work is needed]

## Existing Solutions

[What solutions exist in the industry or codebase?]

## Current State

[If applicable, describe current implementation]

## Research Findings

[Key insights from research and exploration]

## Constraints

[Technical, business, or resource constraints]

## Success Criteria

[How will we know this ticket succeeded?]
EOF

    # Create prd.md template (Product Requirements Document)
    cat > "$ticket_path/planning/prd.md" << 'EOF'
# PRD: {NAME}

## Product Vision

[Brief problem statement and proposed solution. What problem are we solving and why does it matter? Keep this concise - 2-3 sentences maximum.]

*Mark as N/A if this is a technical refactoring or internal improvement ticket.*

## Target Users

[Who will use this feature? Describe the primary user personas and their context. Include both direct users and any secondary stakeholders.]

- **Primary Users:** [Description of main users]
- **Secondary Users:** [Description of secondary users, if any]

*Mark as N/A if this is infrastructure or internal tooling with no direct users.*

## Functional Requirements

[What must the system do? List the core functionality required. Each requirement should be specific and verifiable.]

- [ ] [Requirement 1: specific behavior the system must exhibit]
- [ ] [Requirement 2: specific behavior the system must exhibit]
- [ ] [Requirement 3: specific behavior the system must exhibit]

## Non-Functional Requirements

[Quality attributes and constraints. Include performance, scalability, security, accessibility, and reliability requirements as applicable.]

### Performance
- [Performance requirement, e.g., "Response time under 200ms"]

### Security
- [Security requirement, e.g., "Input validation on all user-provided data"]

### Reliability
- [Reliability requirement, e.g., "Graceful degradation when external services unavailable"]

*Mark individual subsections as N/A if not applicable to this ticket.*

## User Stories

[Describe how users will interact with this feature. Use the format: "As a [user type], I want [goal] so that [benefit]".]

- As a [user type], I want [goal] so that [benefit].
- As a [user type], I want [goal] so that [benefit].

*Mark as N/A for technical tickets without user-facing changes.*

## Acceptance Criteria

[Specific, testable conditions that must be met for this work to be considered complete. These should be unambiguous and verifiable.]

- [ ] [Criterion 1: specific testable condition]
- [ ] [Criterion 2: specific testable condition]
- [ ] [Criterion 3: specific testable condition]

## Out of Scope

[Explicitly list what this ticket will NOT include. This prevents scope creep and sets clear boundaries.]

- [Item explicitly excluded from this work]
- [Feature or enhancement deferred to future work]

*Mark as N/A if scope is self-evident and no clarification needed.*

## Assumptions

[List assumptions being made that could affect the implementation or success of this work.]

- [Assumption 1: condition assumed to be true]
- [Assumption 2: dependency assumed to be available]

*Mark as N/A if no significant assumptions.*

## Success Metrics

[How will we measure if this work achieved its goals? Include both immediate deliverables and longer-term impact metrics where applicable.]

- [ ] [Metric 1: specific, measurable outcome]
- [ ] [Metric 2: specific, measurable outcome]

*Mark as N/A if success is binary (feature works or does not work).*
EOF
    # Substitute {NAME} placeholder with ticket name
    sed -i "s/{NAME}/${name//-/ }/g" "$ticket_path/planning/prd.md"

    # Create architecture.md template
    cat > "$ticket_path/planning/architecture.md" << EOF
# Architecture: ${name//-/ }

## Overview

[High-level description of the solution architecture]

## Design Decisions

### Decision 1: [Title]

**Context:** [Why this decision was needed]
**Decision:** [What was decided]
**Rationale:** [Why this choice]

## Technology Choices

| Component | Choice | Rationale |
|-----------|--------|-----------|
| [Component] | [Tech] | [Why] |

## Component Design

### Component 1

[Description, responsibilities, interfaces]

## Data Flow

[How data moves through the system]

## Integration Points

[How this integrates with existing systems]

## Performance Considerations

[Performance requirements and approach]

## Maintainability

[How the design enables long-term maintenance]
EOF

    # Create plan.md template
    cat > "$ticket_path/planning/plan.md" << EOF
# Plan: ${name//-/ }

## Overview

This document outlines the execution plan for the ticket.

## Phases

### Phase 1: [Foundation]

**Objective:** [What this phase achieves]

**Deliverables:**
<!-- Disposition syntax: "extract: path/to/dest", "archive", or "external: Location Description" -->
| Deliverable | Purpose | Disposition |
|-------------|---------|-------------|
| audit-report.md | Gap analysis findings | extract: docs/decisions/ |
| verification-report.md | Phase completion proof | archive |
| design-notes.md | Context documentation | external: Wiki: Project/Design |

**Agent Assignments:**
- [agent-name]: [responsibility]

### Phase 2: [Core Implementation]

**Objective:** [What this phase achieves]

**Deliverables:**
<!-- Disposition syntax: "extract: path/to/dest", "archive", or "external: Location Description" -->
| Deliverable | Purpose | Disposition |
|-------------|---------|-------------|
| {file.md} | {purpose} | {extract: path/ | archive | external: Location} |

**Agent Assignments:**
- [agent-name]: [responsibility]

## Dependencies

[Cross-phase and external dependencies]

## Risk Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| [Risk] | Low/Med/High | Low/Med/High | [Strategy] |

## Success Metrics

- [ ] [Metric 1]
- [ ] [Metric 2]
EOF

    # Create quality-strategy.md template
    cat > "$ticket_path/planning/quality-strategy.md" << EOF
# Quality Strategy: ${name//-/ }

## Testing Philosophy

[Approach to testing - enterprise-grade, comprehensive coverage]

## Coverage Requirements

**Minimum Thresholds:**
- Line coverage: [X]% (must meet or exceed existing thresholds)
- Branch coverage: [X]%

## Test Types

### Unit Tests

**Scope:** [What's covered]
**Tools:** [Testing frameworks]
**Coverage Target:** [Must meet or exceed ticket thresholds]

**What to Test:**
- All public interfaces
- Business logic and transformations
- Error handling paths
- Edge cases and boundary conditions

### Integration Tests

**Scope:** [What's covered]
**Approach:** [How integration is tested]

### End-to-End Tests

**Scope:** [Critical user paths]
**Approach:** [E2E testing strategy]

## Critical Paths

The following paths MUST have comprehensive test coverage:

1. [Critical path 1] - happy path, error cases, edge cases
2. [Critical path 2] - happy path, error cases, edge cases

## Negative Testing Requirements

- Invalid inputs and malformed data
- Error handling paths
- Authorization failures
- Resource not found scenarios

## Test Data Strategy

[How test data is managed]

## Quality Gates

Before verification:
- [ ] Unit tests pass
- [ ] Coverage thresholds met
- [ ] Integration tests pass (if applicable)
- [ ] No linting errors
- [ ] Critical paths tested (happy path AND error cases)
- [ ] Edge cases covered
EOF

    # Create security-review.md template
    cat > "$ticket_path/planning/security-review.md" << EOF
# Security Review: ${name//-/ }

## Security Assessment

### Authentication & Authorization

[How auth is handled]

### Data Protection

[How sensitive data is protected]

### Input Validation

[Input validation approach]

### Known Gaps

| Gap | Risk Level | Mitigation | Status |
|-----|------------|------------|--------|
| [Gap] | Low/Med/High | [Mitigation] | Open/Accepted |

## Initial Release Security Scope

[What security is in scope for initial release vs future phases]

## Security Checklist

- [ ] No hardcoded secrets
- [ ] Input validation on external inputs
- [ ] Proper error handling (no info leakage)
- [ ] Dependencies are up to date
- [ ] No SQL injection vulnerabilities
- [ ] No XSS vulnerabilities (if applicable)
EOF

    # Output JSON
    cat << EOF
{
  "success": true,
  "ticket": {
    "ticket_id": "$ticket_id",
    "name": "$name",
    "folder": "$folder_name",
    "path": "$ticket_path"
  },
  "created": [
    "$ticket_path/README.md",
    "$ticket_path/planning/analysis.md",
    "$ticket_path/planning/prd.md",
    "$ticket_path/planning/architecture.md",
    "$ticket_path/planning/plan.md",
    "$ticket_path/planning/quality-strategy.md",
    "$ticket_path/planning/security-review.md"
  ],
  "directories": [
    "$ticket_path/planning",
    "$ticket_path/tasks",
    "$ticket_path/deliverables"
  ],
  "next_steps": [
    "Delegate to ticket-planner agent to fill planning docs",
    "Run /sdd:review $ticket_id before creating tasks",
    "Run /sdd:create-tasks $ticket_id to create tasks"
  ]
}
EOF

    info "Ticket created at: $ticket_path"
}

main "$@"
