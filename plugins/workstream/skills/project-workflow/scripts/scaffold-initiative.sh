#!/usr/bin/env bash
#
# Scaffold Initiative Structure
# Creates the folder structure for a new initiative
#
# Usage:
#   bash scaffold-initiative.sh <name> [vision]
#
# Arguments:
#   name    - Initiative name (kebab-case)
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
TEMPLATE_DIR="$SCRIPT_DIR/../templates/initiative"
CREWCHIEF_DIR="${CREWCHIEF_DIR:-.crewchief}"

error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }

usage() {
    cat << EOF
Usage: $(basename "$0") <name> [vision]

Arguments:
  name    Initiative name (kebab-case, e.g., "api-redesign")
  vision  Optional vision statement for the initiative

Examples:
  $(basename "$0") api-redesign
  $(basename "$0") api-redesign "Redesign the public API for better developer experience"

Output:
  JSON object with created structure
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

main() {
    if [[ $# -lt 1 ]]; then
        usage
    fi

    local name="$1"
    local vision="${2:-}"
    local date=$(date +%Y-%m-%d)
    local folder_name="${date}_${name}"
    local init_path="$CREWCHIEF_DIR/initiatives/$folder_name"

    validate_name "$name"

    # Check if already exists
    if [[ -d "$init_path" ]]; then
        error "Initiative already exists: $init_path"
        exit 1
    fi

    info "Creating initiative: $folder_name"

    # Create directory structure
    mkdir -p "$init_path"/{reference,analysis,decomposition/project-summaries}

    # Create overview.md
    cat > "$init_path/overview.md" << EOF
# Initiative: ${name//-/ }

Created: $date

## Vision Statement

${vision:-[To be defined - describe the purpose and long-term goal]}

## Conceptual Frame

[Define the problem space, context, and why this initiative exists]

## Domain Coherence

**Core Domain Concepts:**
- [Concept 1]
- [Concept 2]

## Directional Clarity

**Desired End State:**
"When this initiative succeeds, [X] will be true."

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

## Derived Projects

(To be generated during decomposition phase)

## Status

- [ ] Research complete
- [ ] Analysis complete
- [ ] Decomposition complete
- [ ] Projects created

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| [Risk 1] | [Impact] | [Mitigation] |
EOF

    # Create opportunity-map.md
    cat > "$init_path/analysis/opportunity-map.md" << EOF
# Opportunity Map: ${name//-/ }

## Problem Spaces

[What problems does this initiative address?]

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

    # Create multi-project-overview.md
    cat > "$init_path/decomposition/multi-project-overview.md" << EOF
# Multi-Project Overview: ${name//-/ }

## Context

Initiative created: $date
Reference: $init_path/

## Projects (in execution order)

(To be populated during decomposition)

## Dependencies

[Cross-project dependencies and ordering rationale]
EOF

    # Create decisions.md
    cat > "$init_path/decisions.md" << EOF
# Decisions: ${name//-/ }

Running log of key decisions made during this initiative.

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

Ideas identified during research but not yet ready for project creation.

## Ideas

| Idea | Source | Notes | Status |
|------|--------|-------|--------|
| [Idea] | [Where it came from] | [Context] | Captured |
EOF

    # Output JSON
    cat << EOF
{
  "success": true,
  "initiative": {
    "name": "$name",
    "date": "$date",
    "folder": "$folder_name",
    "path": "$init_path"
  },
  "created": [
    "$init_path/overview.md",
    "$init_path/analysis/opportunity-map.md",
    "$init_path/analysis/domain-model.md",
    "$init_path/analysis/research-synthesis.md",
    "$init_path/decomposition/multi-project-overview.md",
    "$init_path/decisions.md",
    "$init_path/backlog.md"
  ],
  "directories": [
    "$init_path/reference",
    "$init_path/analysis",
    "$init_path/decomposition",
    "$init_path/decomposition/project-summaries"
  ]
}
EOF

    info "Initiative created at: $init_path"
}

main "$@"
