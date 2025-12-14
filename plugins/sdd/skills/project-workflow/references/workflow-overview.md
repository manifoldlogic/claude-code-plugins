# Workflow Overview

This document provides a visual overview of the ticket workflow system.

## Hierarchy

```
                    ┌─────────────────────┐
                    │     EPIC      │
                    │  Research/Discovery │
                    │  May spawn multiple │
                    │      tickets        │
                    └──────────┬──────────┘
                               │
              ┌────────────────┴────────────────┐
              │                                 │
              ▼                                 ▼
    ┌─────────────────┐             ┌─────────────────┐
    │    TICKET A     │             │    TICKET B     │
    │ Planning + Exec │             │ Planning + Exec │
    └────────┬────────┘             └────────┬────────┘
             │                               │
    ┌────────┴────────┐             ┌────────┴────────┐
    │                 │             │                 │
    ▼                 ▼             ▼                 ▼
┌────────┐       ┌────────┐   ┌────────┐       ┌────────┐
│Task 1  │       │Task 2  │   │Task 1  │       │Task 2  │
└────────┘       └────────┘   └────────┘       └────────┘
```

## Ticket Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                        TICKET LIFECYCLE                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐   │
│  │ SCAFFOLD │ -> │   PLAN   │ -> │  REVIEW  │ -> │  TASKS   │   │
│  │          │    │          │    │          │    │          │   │
│  │ scaffold │    │ ticket-  │    │ ticket-  │    │  task-   │   │
│  │ -ticket  │    │ planner  │    │ reviewer │    │ creator  │   │
│  │ .sh      │    │ agent    │    │ agent    │    │ agent    │   │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘   │
│                                                                   │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐   │
│  │  REVIEW  │ -> │ EXECUTE  │ -> │  VERIFY  │ -> │ ARCHIVE  │   │
│  │  TASKS   │    │          │    │          │    │          │   │
│  │          │    │ /sdd:    │    │ verify-  │    │ /sdd:    │   │
│  │ /sdd:    │    │ do-all-  │    │ task     │    │ archive  │   │
│  │ review   │    │ tasks    │    │ agent    │    │          │   │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘   │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

## Task Execution Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    TASK EXECUTION FLOW                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│     ┌──────────────┐                                             │
│     │  IMPLEMENT   │  <-- Primary agent (Sonnet)                 │
│     │              │      Does the actual work                   │
│     └──────┬───────┘                                             │
│            │                                                      │
│            ▼                                                      │
│     ┌──────────────┐                                             │
│     │    TEST      │  <-- unit-test-runner agent (Haiku)         │
│     │              │      Runs tests, reports results + coverage │
│     └──────┬───────┘                                             │
│            │                                                      │
│            ▼                                                      │
│     ┌──────────────┐                                             │
│     │   VERIFY     │  <-- verify-task agent (Sonnet)           │
│     │              │      Checks acceptance criteria             │
│     └──────┬───────┘                                             │
│            │                                                      │
│            ▼                                                      │
│     ┌──────────────┐                                             │
│     │   COMMIT     │  <-- commit-task agent (Haiku)            │
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
│  Example: task-status.sh -> JSON -> status-reporter            │
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
│  Example: ticket-planner -> scaffold-ticket.sh -> status       │
│                                                                   │
│                                                                   │
│  Pattern 3: Sequential Agents (Task Workflow)                    │
│  ────────────────────────────────────────────────                │
│                                                                   │
│  ┌────────────┐   ┌────────────┐   ┌────────────┐   ┌────────┐  │
│  │ Impl Agent │ → │unit-test-  │ → │verify-task│ → │ commit │  │
│  │  (Sonnet)  │   │runner(Haiku│   │  (Sonnet)   │   │(Haiku) │  │
│  └────────────┘   └────────────┘   └────────────┘   └────────┘  │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

## Command to Agent Mapping

```
┌───────────────────────┬────────────────────────────────────────┐
│       Command         │           Delegates To                  │
├───────────────────────┼────────────────────────────────────────┤
│ /sdd:start-epic       │ scaffold-epic.sh                  │
│                       │ + epic-planner (Sonnet)           │
├───────────────────────┼────────────────────────────────────────┤
│ /sdd:plan-ticket      │ scaffold-ticket.sh                     │
│                       │ + ticket-planner (Sonnet)              │
├───────────────────────┼────────────────────────────────────────┤
│ /sdd:review           │ ticket-reviewer (Sonnet)               │
├───────────────────────┼────────────────────────────────────────┤
│ /sdd:create-tasks     │ task-creator (Sonnet)                 │
├───────────────────────┼────────────────────────────────────────┤
│ /sdd:do-all-tasks     │ Sequential: implement → test → verify   │
│                       │ → commit for each task                  │
├───────────────────────┼────────────────────────────────────────┤
│ /sdd:do-task          │ implement → unit-test-runner (Haiku)    │
│                       │ → verify-task (Sonnet)                │
│                       │ → commit-task (Haiku)                 │
├───────────────────────┼────────────────────────────────────────┤
│ /sdd:tasks-status     │ task-status.sh                        │
│                       │ + status-reporter (Haiku)               │
├───────────────────────┼────────────────────────────────────────┤
│ /sdd:archive          │ structure-validator (Haiku)             │
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
