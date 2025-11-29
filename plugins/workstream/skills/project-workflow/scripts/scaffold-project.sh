#!/usr/bin/env bash
#
# Scaffold Project Structure
# Creates the folder structure for a new project
#
# Usage:
#   bash scaffold-project.sh <SLUG> <name>
#
# Arguments:
#   SLUG  - Project identifier (4-8 uppercase chars)
#   name  - Project name (kebab-case)
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
TEMPLATE_DIR="$SCRIPT_DIR/../templates/project"
CREWCHIEF_DIR="${CREWCHIEF_DIR:-.crewchief}"

error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }

usage() {
    cat << EOF
Usage: $(basename "$0") <SLUG> <name>

Arguments:
  SLUG  Project identifier (4-8 uppercase characters)
  name  Project name (kebab-case, e.g., "api-redesign")

Examples:
  $(basename "$0") APIV2 api-version-2
  $(basename "$0") DKRHUB docker-hub-publishing

Output:
  JSON object with created structure
EOF
    exit 1
}

validate_slug() {
    local slug="$1"
    if [[ ! "$slug" =~ ^[A-Z][A-Z0-9]{3,7}$ ]]; then
        error "Invalid SLUG format. Must be 4-8 uppercase letters/numbers."
        error "Example: APIV2, DKRHUB, SEARCH"
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

check_slug_unique() {
    local slug="$1"
    # Check active projects
    if ls -d "$CREWCHIEF_DIR/projects/${slug}_"* 2>/dev/null | grep -q .; then
        error "SLUG '$slug' already exists in active projects"
        exit 1
    fi
    # Check archived projects
    if ls -d "$CREWCHIEF_DIR/archive/projects/${slug}_"* 2>/dev/null | grep -q .; then
        warn "SLUG '$slug' exists in archived projects - proceeding with caution"
    fi
}

main() {
    if [[ $# -lt 2 ]]; then
        usage
    fi

    local slug="$1"
    local name="$2"
    local folder_name="${slug}_${name}"
    local project_path="$CREWCHIEF_DIR/projects/$folder_name"

    validate_slug "$slug"
    validate_name "$name"
    check_slug_unique "$slug"

    # Check if already exists
    if [[ -d "$project_path" ]]; then
        error "Project already exists: $project_path"
        exit 1
    fi

    info "Creating project: $folder_name"

    # Create directory structure
    mkdir -p "$project_path"/{planning,tickets}

    # Create README.md
    cat > "$project_path/README.md" << EOF
# Project: ${name//-/ }

**Slug:** $slug
**Status:** Planning
**Created:** $(date +%Y-%m-%d)

## Summary

[Brief description of the project]

## Problem Statement

[What problem does this project solve?]

## Proposed Solution

[High-level approach to solving the problem]

## Relevant Agents

- project-planner (planning phase)
- ticket-creator (ticket generation)
- [implementation agents]
- verify-ticket (verification)
- commit-ticket (commit)

## Planning Documents

- [analysis.md](planning/analysis.md) - Problem analysis
- [architecture.md](planning/architecture.md) - Solution design
- [plan.md](planning/plan.md) - Execution plan
- [quality-strategy.md](planning/quality-strategy.md) - Testing approach
- [security-review.md](planning/security-review.md) - Security assessment

## Tickets

See [tickets/](tickets/) for all project tickets.
EOF

    # Create analysis.md template
    cat > "$project_path/planning/analysis.md" << EOF
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

[How will we know this project succeeded?]
EOF

    # Create architecture.md template
    cat > "$project_path/planning/architecture.md" << EOF
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
    cat > "$project_path/planning/plan.md" << EOF
# Plan: ${name//-/ }

## Overview

This document outlines the execution plan for the project.

## Phases

### Phase 1: [Foundation]

**Objective:** [What this phase achieves]

**Deliverables:**
- [Deliverable 1]
- [Deliverable 2]

**Agent Assignments:**
- [agent-name]: [responsibility]

### Phase 2: [Core Implementation]

**Objective:** [What this phase achieves]

**Deliverables:**
- [Deliverable 1]
- [Deliverable 2]

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
    cat > "$project_path/planning/quality-strategy.md" << EOF
# Quality Strategy: ${name//-/ }

## Testing Philosophy

[Approach to testing - pragmatic, focused on confidence]

## Test Types

### Unit Tests

**Scope:** [What's covered]
**Tools:** [Testing frameworks]
**Coverage Target:** [Pragmatic target, not 100%]

### Integration Tests

**Scope:** [What's covered]
**Approach:** [How integration is tested]

### End-to-End Tests

**Scope:** [Critical paths only]
**Approach:** [E2E testing strategy]

## Critical Paths

The following paths MUST be tested:

1. [Critical path 1]
2. [Critical path 2]

## Test Data Strategy

[How test data is managed]

## Quality Gates

Before verification:
- [ ] Unit tests pass
- [ ] Integration tests pass (if applicable)
- [ ] No linting errors
- [ ] Code review complete (if applicable)
EOF

    # Create security-review.md template
    cat > "$project_path/planning/security-review.md" << EOF
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

## MVP Security Scope

[What security is in scope for MVP vs future]

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
  "project": {
    "slug": "$slug",
    "name": "$name",
    "folder": "$folder_name",
    "path": "$project_path"
  },
  "created": [
    "$project_path/README.md",
    "$project_path/planning/analysis.md",
    "$project_path/planning/architecture.md",
    "$project_path/planning/plan.md",
    "$project_path/planning/quality-strategy.md",
    "$project_path/planning/security-review.md"
  ],
  "directories": [
    "$project_path/planning",
    "$project_path/tickets"
  ],
  "next_steps": [
    "Delegate to project-planner agent to fill planning docs",
    "Run /project-review $slug before creating tickets",
    "Run /project-tickets $slug to create tickets"
  ]
}
EOF

    info "Project created at: $project_path"
}

main "$@"
