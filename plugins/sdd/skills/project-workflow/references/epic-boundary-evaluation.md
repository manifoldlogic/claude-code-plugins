# Epic Boundary Evaluation

The Role of an Epic in Agent-Based Development

An epic represents a higher-order context from which one or more tickets emerge.
It is the strategic synthesis layer — where discovery, research, and analysis converge into a coherent mission that can be decomposed into multiple stable, agent-executable tickets.

If a ticket defines a stable context for execution,
an epic defines a stable frame for meaning.

            🌍 Conceptual Stability
                  ╱        ╲
                  ╱          ╲
                ╱            ╲
      🧠 Domain Coherence   🎯 Directional Clarity
                ╲            ╱
                  ╲          ╱
                  ╲        ╱
                ✅ Valid Epic

⸻

The Three Core Criteria

1. Conceptual Stability 🌍

The Golden Rule: The epic must define a stable problem space, not a moving target.

What This Means:
• The core vision and value proposition are defined and will not pivot midstream.
• The “why” of the epic remains constant even if the “how” evolves.
• Documents under the epic reference the same conceptual frame of purpose.

Why It's Critical:
Without conceptual stability, downstream tickets fragment into incompatible worldviews. Agents lose alignment on the epic's underlying logic, resulting in incoherent ticket definitions and competing interpretations of value.

How to Verify:
• Write a concise epic vision statement (<150 words).
• Ensure all reference materials reinforce that same vision.
• Check that differences between documents are about approaches, not definitions.

⸻

2. Domain Coherence 🧠

The Scope Rule: All tickets derived from an epic should live in a single conceptual domain.

What This Means:
• The epic operates within a shared ontology — one domain language.
• The problems addressed are tightly related and reference the same entities.
• Tickets differ by implementation boundary, not by world.

Why It's Critical:
An epic that spans multiple unrelated domains ("payment infra," "user growth," "documentation platform") creates incoherent ticket decomposition.
Agents cannot cluster related documents effectively or build a unified model of value.

How to Verify:
• Identify the core domain concepts (<30 total).
• Test: Can they all be described in one system diagram?
• If multiple ontologies appear, split the epic before proceeding.

⸻

3. Directional Clarity 🎯

The Navigation Rule: The epic defines where we’re going, not how to get there.

What This Means:
• There is a clear desired end state or transformation.
• The path to reach it is open for exploration and decomposition.
• Each ticket should move the system measurably closer to this end state.

Why It’s Critical:
Agents need a directional compass when proposing or ordering tickets. Without clarity of direction, they cannot rationally prioritize or derive dependency order.

How to Verify:
• Write a single measurable outcome statement (“When this epic succeeds, X will be true.”)
• List 3–5 success signals observable across tickets.
• Ensure none of these require defining implementation details yet.

⸻

Secondary Criteria

Temporal Elasticity

Epics typically span multiple weeks to months, not days. Their work should survive the lifecycle of individual tickets. If your "epic" completes in two weeks, it's probably just a large ticket.

Research Completeness

An epic should be backed by sufficient discovery materials — research, analysis, or architecture sketches. If you’re inventing the context as you go, it’s too early to formalize it as an epic.

Cross-Ticket Synergy

Each ticket under the epic should reinforce others, not compete with or invalidate them.
Redundancy or orthogonal goals are warning signs of poor epic definition.

⸻

Epic Boundary Patterns

Pattern 1: Strategic Transformation

Structure: A major shift in system architecture, workflow, or product direction
Examples:
• “Migrate to fully agent-managed CI/CD”
• “Adopt federated identity across all products”

Boundaries:
• Shared transformation goal
• Tickets: platform redesigns, adapters, and migrations

⸻

Pattern 2: Capability Expansion

Structure: Introduce a new horizontal or vertical capability to the ecosystem
Examples:
• “Add AI-driven insights to all dashboards”
• “Implement self-healing infrastructure”

Boundaries:
• One capability theme
• Multiple tickets: service module, UX, observability, integration

⸻

Pattern 3: Domain Consolidation

Structure: Merge fragmented or redundant systems into a unified domain
Examples:
• “Unify notification systems”
• “Centralize data access layer”

Boundaries:
• Common conceptual core
• Tickets: API consolidation, data normalization, service retirement

⸻

Quick Decision Tests

The Vision Drift Test

“Would new discoveries change the epic’s purpose?”
• ✅ No → Good boundary
• ❌ Yes → Define narrower scope or rephrase purpose

The Domain Split Test

"Can all derived tickets share one domain model?"
• ✅ Yes → Good boundary
• ❌ No → Split epic

The Direction Ambiguity Test

"Could an agent sequence tickets logically toward the goal?"
• ✅ Yes → Clear direction
• ❌ No → Goal too vague or conflicting

⸻

Epic Evaluation Checklist

## Core Requirements (All Required)

conceptual_stability:
  ☐ Stable definition of purpose
  ☐ Core value proposition consistent across docs
  ☐ No competing problem statements

domain_coherence:
  ☐ Common ontology / domain language
  ☐ <30 domain entities total
  ☐ All subtopics fit one conceptual model

directional_clarity:
  ☐ Measurable end state
  ☐ 3–5 observable success signals
  ☐ Tickets can be ordered toward outcome

## Secondary Factors (Recommended)

temporal_elasticity:
  ☐ Expected duration >1 month
  ☐ Survives multiple ticket cycles

research_completeness:
  ☐ Includes discovery materials
  ☐ Sufficient context for decomposition

cross_ticket_synergy:
  ☐ Tickets reinforce shared goals
  ☐ No conflicting deliverables

⸻

Common Anti-Patterns

❌ The Wishlist

Example: “All the cool features we want next year”
Problem: No conceptual or directional unity
Fix: Group by capability or transformation

❌ The Committee Scope

Example: “Everything Marketing requested”
Problem: Multiple unrelated domains and purposes
Fix: Split into domain-specific epics

❌ The Moving Target

Example: “Whatever improves retention this quarter”
Problem: Goal pivots with metrics, causing ticket churn
Fix: Define a stable conceptual theory of improvement first

❌ The Ticket-in-Disguise

Example: "Build the API Gateway"
Problem: Single concrete deliverable — just a ticket, not an epic
Fix: Move directly to /sdd:plan-ticket

⸻

Epic Definition Template

# Epic: [NAME]

## Vision Statement

[Brief, stable description of the purpose and long-term goal]

## Conceptual Frame

[Define the problem space, context, and why this epic exists]

## Domain Coherence

**Core Domain Concepts (≤30):**

- Concept 1
- Concept 2
- ...

## Directional Clarity

**Desired End State:**  
“When this epic succeeds, [X] will be true.”

**Success Signals:**

- [ ] Signal 1
- [ ] Signal 2
- [ ] Signal 3

## Derived Tickets

(List to be generated by `/create-epic`)

## Risks

| Risk | Impact | Mitigation |
|------|---------|-------------|
| Concept drift | Tickets lose alignment | Define fixed purpose statement |
| Domain confusion | Context overlap | Separate epic domains |
| Vague goal | Agents can't order work | Define measurable end state |

⸻

Key Insights

1. Epics create meaning; tickets create outcomes.
2. The epic boundary is philosophical, not technical — it defines coherence, not code.
3. Epics should be big enough to unify multiple tickets, small enough to remain cognitively stable.
4. Once decomposition begins, epic boundaries must remain fixed until completion.
5. A stable epic is the highest leverage point in agent-based orchestration — it shapes every ticket downstream.
