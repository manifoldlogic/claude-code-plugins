#!/usr/bin/env bash
#
# Scaffold Epic Structure
# Creates the folder structure for a new epic
#
# Usage:
#   bash scaffold-epic.sh <name> [jira_id] [vision]
#
# Arguments:
#   name    - Epic name (kebab-case)
#   jira_id - Optional Jira epic ID (e.g., UIT-444, BE-1234)
#   vision  - Optional vision statement
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
TEMPLATE_DIR="$SCRIPT_DIR/../templates/epic"
SDD_ROOT_DIR="${SDD_ROOT_DIR:-/app/.sdd}"

error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }

usage() {
    cat << EOF
Usage: $(basename "$0") <name> [jira_id] [vision]

Arguments:
  name     Epic name (kebab-case, e.g., "api-redesign")
  jira_id  Optional Jira epic ID (e.g., "UIT-444", "BE-1234", "PROJ-123")
  vision   Optional vision statement for the epic

Examples:
  $(basename "$0") api-redesign
  $(basename "$0") user-profile-update UIT-444
  $(basename "$0") api-redesign "" "Redesign the public API for better developer experience"
  $(basename "$0") best-epic-name UIT-444 "Epic vision statement"

Output:
  JSON object with created structure

Folder naming:
  Without Jira ID: {DATE}_{name}          (e.g., 2025-12-22_api-redesign)
  With Jira ID:    {DATE}_{jira_id}_{name} (e.g., 2025-12-22_UIT-444_best-epic-name)
EOF
    exit 1
}

validate_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]] && [[ ! "$name" =~ ^[a-z]$ ]]; then
        error "Invalid name format. Use lowercase letters, numbers, and hyphens."
        error "Example: api-redesign, performance-optimization"
        exit 1
    fi
}

# Validate Jira ID format (e.g., UIT-444, BE-1234, PROJ-123)
# Supports both custom IDs (APIV2) and Jira-style IDs (UIT-9819)
validate_jira_id() {
    local jira_id="$1"

    # Empty is OK (optional parameter)
    if [[ -z "$jira_id" ]]; then
        return 0
    fi

    # Must match: uppercase letter, followed by uppercase letters/numbers,
    # optionally followed by dash+alphanumeric segments (for Jira IDs)
    # Pattern: ^[A-Z][A-Z0-9]*(-[A-Z0-9]+)*$
    if [[ ! "$jira_id" =~ ^[A-Z][A-Z0-9]*(-[A-Z0-9]+)*$ ]]; then
        error "Invalid Jira ID format: $jira_id"
        error "Must be uppercase letters/numbers, optionally with dashes."
        error "Examples: UIT-444, BE-1234, PROJ-123, APIV2"
        exit 1
    fi

    # Length check (2-12 characters)
    local len=${#jira_id}
    if [[ $len -lt 2 || $len -gt 12 ]]; then
        error "Jira ID must be 2-12 characters: $jira_id (got $len)"
        exit 1
    fi
}

main() {
    if [[ $# -lt 1 ]]; then
        usage
    fi

    local name="$1"
    local jira_id="${2:-}"
    local vision="${3:-}"
    local date=$(date +%Y-%m-%d)

    # Build folder name: DATE_NAME or DATE_JIRAID_NAME
    local folder_name
    if [[ -n "$jira_id" ]]; then
        folder_name="${date}_${jira_id}_${name}"
    else
        folder_name="${date}_${name}"
    fi
    local init_path="$SDD_ROOT_DIR/epics/$folder_name"

    validate_name "$name"
    validate_jira_id "$jira_id"

    # Check if already exists
    if [[ -d "$init_path" ]]; then
        error "Epic already exists: $init_path"
        exit 1
    fi

    info "Creating epic: $folder_name"

    # Create directory structure
    # IMPORTANT: If structure changes, update plugins/maproom/skills/sdd-spec-search/SKILL.md
    mkdir -p "$init_path"/{reference,analysis,decomposition/ticket-summaries}

    # Create overview.md
    cat > "$init_path/overview.md" << EOF
# Epic: ${name//-/ }

Created: $date

## Vision Statement

${vision:-[To be defined - describe the purpose and long-term goal]}

## Conceptual Frame

[Define the problem space, context, and why this epic exists]

## Domain Coherence

**Core Domain Concepts:**
- [Concept 1]
- [Concept 2]

## Directional Clarity

**Desired End State:**
"When this epic succeeds, [X] will be true."

**Success Signals:**
- [ ] Signal 1
- [ ] Signal 2
- [ ] Signal 3

## Scope Boundaries

**In Scope:**
- [Area 1]
- [Area 2]

**Out of Scope:**
- [Area 1]
- [Area 2]

## Derived Tickets

(To be generated during decomposition phase)

## Status

- [ ] Research complete
- [ ] Analysis complete
- [ ] Decomposition complete
- [ ] Tickets created

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| [Risk 1] | [Impact] | [Mitigation] |
EOF

    # Create opportunity-map.md
    cat > "$init_path/analysis/opportunity-map.md" << EOF
# Opportunity Map: ${name//-/ }

## Problem Spaces

[What problems does this epic address?]

## Goals

[What outcomes are we seeking?]

## Constraints

[What limitations must we work within?]

## Opportunities

[What possibilities exist?]
EOF

    # Create domain-model.md
    cat > "$init_path/analysis/domain-model.md" << EOF
# Domain Model: ${name//-/ }

## Core Entities

[Key concepts and their relationships]

## Boundaries

[Where does this domain end and others begin?]

## Interactions

[How do entities relate to each other?]
EOF

    # Create research-synthesis.md
    cat > "$init_path/analysis/research-synthesis.md" << EOF
# Research Synthesis: ${name//-/ }

## Key Findings

[Distilled insights from reference materials]

## Open Questions

[Areas requiring further exploration]

## Assumptions

[What are we assuming to be true?]
EOF

    # Create multi-ticket-overview.md
    cat > "$init_path/decomposition/multi-ticket-overview.md" << EOF
# Multi-Ticket Overview: ${name//-/ }

## Context

Epic created: $date
Reference: $init_path/

## Tickets (in execution order)

(To be populated during decomposition)

## Dependencies

[Cross-ticket dependencies and ordering rationale]
EOF

    # Create decisions.md
    cat > "$init_path/decisions.md" << EOF
# Decisions: ${name//-/ }

Running log of key decisions made during this epic.

---

## Decisions

(Entries added as decisions are made)

---

## Decision Template

### [DATE] Decision Title

**Context:** [Why this decision was needed]

**Decision:** [What was decided]

**Rationale:** [Why this choice]

**Alternatives Considered:**
- [Option A]: [Why rejected]
- [Option B]: [Why rejected]
EOF

    # Create backlog.md
    cat > "$init_path/backlog.md" << EOF
# Backlog: ${name//-/ }

Ideas identified during research but not yet ready for ticket creation.

## Ideas

| Idea | Source | Notes | Status |
|------|--------|-------|--------|
| [Idea] | [Where it came from] | [Context] | Captured |
EOF

    # Output JSON
    cat << EOF
{
  "success": true,
  "epic": {
    "name": "$name",
    "jira_id": "${jira_id:-null}",
    "date": "$date",
    "folder": "$folder_name",
    "path": "$init_path"
  },
  "created": [
    "$init_path/overview.md",
    "$init_path/analysis/opportunity-map.md",
    "$init_path/analysis/domain-model.md",
    "$init_path/analysis/research-synthesis.md",
    "$init_path/decomposition/multi-ticket-overview.md",
    "$init_path/decisions.md",
    "$init_path/backlog.md"
  ],
  "directories": [
    "$init_path/reference",
    "$init_path/analysis",
    "$init_path/decomposition",
    "$init_path/decomposition/ticket-summaries"
  ]
}
EOF

    info "Epic created at: $init_path"
}

main "$@"
