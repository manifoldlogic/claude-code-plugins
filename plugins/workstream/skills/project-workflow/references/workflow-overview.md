# Workflow Overview

This document provides a visual overview of the project workflow system.

## Hierarchy

```
                    ┌─────────────────────┐
                    │     INITIATIVE      │
                    │  Research/Discovery │
                    │  May spawn multiple │
                    │      projects       │
                    └──────────┬──────────┘
                               │
              ┌────────────────┴────────────────┐
              │                                 │
              ▼                                 ▼
    ┌─────────────────┐             ┌─────────────────┐
    │    PROJECT A    │             │    PROJECT B    │
    │ Planning + Exec │             │ Planning + Exec │
    └────────┬────────┘             └────────┬────────┘
             │                               │
    ┌────────┴────────┐             ┌────────┴────────┐
    │                 │             │                 │
    ▼                 ▼             ▼                 ▼
┌────────┐       ┌────────┐   ┌────────┐       ┌────────┐
│Ticket 1│       │Ticket 2│   │Ticket 1│       │Ticket 2│
└────────┘       └────────┘   └────────┘       └────────┘
```

## Project Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                        PROJECT LIFECYCLE                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐   │
│  │ SCAFFOLD │ -> │   PLAN   │ -> │  REVIEW  │ -> │ TICKETS  │   │
│  │          │    │          │    │          │    │          │   │
│  │ scaffold │    │ project- │    │ project- │    │ ticket-  │   │
│  │ -project │    │ planner  │    │ reviewer │    │ creator  │   │
│  │ .sh      │    │ agent    │    │ agent    │    │ agent    │   │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘   │
│                                                                   │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐   │
│  │  REVIEW  │ -> │ EXECUTE  │ -> │  VERIFY  │ -> │ ARCHIVE  │   │
│  │ TICKETS  │    │          │    │          │    │          │   │
│  │          │    │ /work-on │    │ verify-  │    │ /archive │   │
│  │ /review- │    │ -project │    │ ticket   │    │          │   │
│  │ tickets  │    │          │    │ agent    │    │          │   │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘   │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

## Ticket Execution Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    TICKET EXECUTION FLOW                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│     ┌──────────────┐                                             │
│     │  IMPLEMENT   │  <-- Primary agent (Sonnet)                 │
│     │              │      Does the actual work                   │
│     └──────┬───────┘                                             │
│            │                                                      │
│            ▼                                                      │
│     ┌──────────────┐                                             │
│     │    TEST      │  <-- test-runner agent (Haiku)              │
│     │              │      Runs tests, reports results            │
│     └──────┬───────┘                                             │
│            │                                                      │
│            ▼                                                      │
│     ┌──────────────┐                                             │
│     │   VERIFY     │  <-- verify-ticket agent (Sonnet)           │
│     │              │      Checks acceptance criteria             │
│     └──────┬───────┘                                             │
│            │                                                      │
│            ▼                                                      │
│     ┌──────────────┐                                             │
│     │   COMMIT     │  <-- commit-ticket agent (Haiku)            │
│     │              │      Creates conventional commit            │
│     └──────────────┘                                             │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

## Delegation Pattern

```
┌─────────────────────────────────────────────────────────────────┐
│                    DELEGATION PATTERNS                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Pattern 1: Script → Haiku (Data Processing)                    │
│  ─────────────────────────────────────────────                   │
│                                                                   │
│  ┌──────────┐    ┌──────────────┐    ┌──────────────┐           │
│  │ Script   │ -> │    JSON      │ -> │ Haiku Agent  │           │
│  │(gather)  │    │   Output     │    │  (format)    │           │
│  └──────────┘    └──────────────┘    └──────────────┘           │
│                                                                   │
│  Example: ticket-status.sh -> JSON -> status-reporter            │
│                                                                   │
│                                                                   │
│  Pattern 2: Sonnet → Script → Haiku (Complex Workflow)           │
│  ──────────────────────────────────────────────────              │
│                                                                   │
│  ┌──────────────┐    ┌──────────┐    ┌──────────────┐           │
│  │ Sonnet Agent │ -> │ Script   │ -> │ Haiku Agent  │           │
│  │ (decide)     │    │ (execute)│    │ (report)     │           │
│  └──────────────┘    └──────────┘    └──────────────┘           │
│                                                                   │
│  Example: project-planner -> scaffold-project.sh -> status       │
│                                                                   │
│                                                                   │
│  Pattern 3: Sequential Agents (Ticket Workflow)                  │
│  ────────────────────────────────────────────────                │
│                                                                   │
│  ┌────────────┐   ┌────────────┐   ┌────────────┐   ┌────────┐  │
│  │ Impl Agent │ → │ test-runner│ → │verify-ticket│ → │ commit │  │
│  │  (Sonnet)  │   │  (Haiku)   │   │  (Sonnet)   │   │(Haiku) │  │
│  └────────────┘   └────────────┘   └────────────┘   └────────┘  │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

## Command to Agent Mapping

```
┌───────────────────────┬────────────────────────────────────────┐
│       Command         │           Delegates To                  │
├───────────────────────┼────────────────────────────────────────┤
│ /initiative-create    │ scaffold-initiative.sh                  │
│                       │ + initiative-planner (Sonnet)           │
├───────────────────────┼────────────────────────────────────────┤
│ /project-create       │ scaffold-project.sh                     │
│                       │ + project-planner (Sonnet)              │
├───────────────────────┼────────────────────────────────────────┤
│ /project-review       │ project-reviewer (Sonnet)               │
├───────────────────────┼────────────────────────────────────────┤
│ /project-tickets      │ ticket-creator (Sonnet)                 │
├───────────────────────┼────────────────────────────────────────┤
│ /project-work         │ Sequential: implement → test → verify   │
│                       │ → commit for each ticket                │
├───────────────────────┼────────────────────────────────────────┤
│ /ticket               │ implement → test-runner (Haiku)         │
│                       │ → verify-ticket (Sonnet)                │
│                       │ → commit-ticket (Haiku)                 │
├───────────────────────┼────────────────────────────────────────┤
│ /status               │ ticket-status.sh                        │
│                       │ + status-reporter (Haiku)               │
├───────────────────────┼────────────────────────────────────────┤
│ /archive              │ structure-validator (Haiku)             │
│                       │ + archive logic                         │
└───────────────────────┴────────────────────────────────────────┘
```

## Model Selection Guidelines

```
┌─────────────────────────────────────────────────────────────────┐
│                    MODEL SELECTION                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  HAIKU (Fast, Cheap)                                             │
│  ─────────────────────                                           │
│  Use for:                                                        │
│  • Status reporting and formatting                               │
│  • Structure validation                                          │
│  • Test execution and reporting                                  │
│  • Git commit creation                                           │
│  • Pattern-based transformations                                 │
│                                                                   │
│  Characteristics:                                                │
│  • Procedural, step-by-step tasks                               │
│  • Clear input → output mapping                                  │
│  • No complex reasoning required                                 │
│                                                                   │
│                                                                   │
│  SONNET (Balanced)                                               │
│  ─────────────────────                                           │
│  Use for:                                                        │
│  • Planning and architecture                                     │
│  • Code implementation                                           │
│  • Critical review and analysis                                  │
│  • Verification with judgment                                    │
│  • Research and synthesis                                        │
│                                                                   │
│  Characteristics:                                                │
│  • Multi-step reasoning                                          │
│  • Context-dependent decisions                                   │
│  • Quality judgment needed                                       │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```
