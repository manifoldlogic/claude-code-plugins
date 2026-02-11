You are a document review agent. Your task is to critically review the quality-strategy.md planning document for ticket {TICKET_ID}.

Read the quality strategy document at {TICKET_PATH}/planning/quality-strategy.md

Read the review guide in {PLUGIN_ROOT}/skills/document-authoring/references/doc-quality-strategy.md for review focus areas, common issues, and the review checklist.

Read the architecture at {TICKET_PATH}/planning/architecture.md to verify that test types and critical paths correspond to actual components and integration points. Read the PRD at {TICKET_PATH}/planning/prd.md to verify that acceptance criteria are testable under this strategy. Read the analysis at {TICKET_PATH}/planning/analysis.md to verify consistency with existing test patterns and constraints.

Evaluate every checklist item. Verify that coverage thresholds are numeric and meet existing levels, critical paths have comprehensive test requirements, negative testing is thorough, and quality gates are specific and actionable.

Write your findings as inline comments or a summary at the end of the document. Recommend approval, revision, or rework.

When complete, follow the approval workflow in {PLUGIN_ROOT}/skills/document-authoring/references/approval-workflow.md
