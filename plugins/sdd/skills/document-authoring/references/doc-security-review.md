# Reference: security-review.md

This document provides complete guidance for creating and reviewing the security review document (`security-review.md`) in an SDD ticket. It is used by document agents spawned via initiation prompts.

## Creation Guide

### Purpose

The security review document provides a practical security assessment of the ticket's planned implementation. It identifies security-relevant aspects of the design, evaluates authentication and authorization approaches, data protection measures, input validation strategies, dependency security, and threat modeling. The security review ensures that no unmitigated security risks ship to production.

As a Level 3 document in the dependency graph, security-review.md depends on architecture.md (and transitively on prd.md and analysis.md). It is independent of plan.md and quality-strategy.md, which are also Level 3 documents and may be created concurrently.

### Prerequisites

The following must be complete before creating the security review document:

- **architecture.md** (Level 2): The architecture document must exist and contain a complete technical design with components, interfaces, design decisions, technology choices, data flow, and integration points. The security review evaluates the security posture of each architectural component, identifies attack surfaces at integration points, and assesses whether design decisions introduce security risks.

- **prd.md** (Level 1): The PRD must exist and contain specific requirements, acceptance criteria, and non-functional requirements. Security-related non-functional requirements (authentication, authorization, data privacy, compliance) define what the security review must evaluate. Acceptance criteria may include security-relevant conditions.

- **analysis.md** (Level 0): The analysis document must exist and contain the problem definition, constraints, existing codebase patterns, and research findings. The security review must respect existing security patterns in the codebase, leverage established security utilities, and account for constraints that affect security posture (e.g., platform limitations, third-party requirements).

Read the architecture document first, as it is the primary input to the security review. The component design, integration points, data flow, and technology choices define the attack surface that must be assessed. Then read the PRD for security-related requirements and the analysis for constraints and existing security patterns.

### Research Steps

Before writing the security review document, perform these steps:

1. **Read the architecture document** at the ticket planning path. Understand the component design, technology choices, integration points, data flow, and design decisions. Each component introduces an attack surface. Each integration point is a trust boundary. Each data flow may carry sensitive data that requires protection.

2. **Read the PRD** to understand security-related non-functional requirements and acceptance criteria. Identify any explicit security requirements such as authentication methods, authorization models, data encryption, or compliance mandates.

3. **Read the analysis document** to understand constraints, existing codebase security patterns, and research findings. Identify existing authentication/authorization mechanisms, input validation libraries, secrets management approaches, and security testing utilities already in the codebase.

4. **Read the ticket README.md** to understand the original ticket intent and verify alignment with the planned security assessment scope.

5. **Search the codebase for existing security patterns.** Use Grep and Glob to find how authentication, authorization, input validation, secrets management, and error handling are implemented in the codebase. The security review must follow established security patterns. Note existing middleware, validation libraries, access control mechanisms, and security-related configuration.

6. **Identify the authentication and authorization approach.** Determine how the ticket's implementation will authenticate users or services and authorize access to resources. Evaluate whether the approach aligns with existing auth patterns in the codebase. Assess token handling, session management, and credential storage.

7. **Identify sensitive data and data protection measures.** Catalog all sensitive data types that the implementation will handle (credentials, personal information, tokens, API keys, financial data). For each type, define the protection approach: encryption at rest, encryption in transit, access controls, masking in logs, and retention policies.

8. **Define the input validation strategy.** Determine all external inputs to the system (user input, API parameters, file uploads, webhook payloads, environment variables). For each input source, define what validation is required: type checking, range validation, format validation, sanitization, and encoding. Ensure validation occurs at trust boundaries.

9. **Assess dependency security.** Review third-party dependencies introduced by the architecture. Check for known vulnerabilities, evaluate the trustworthiness of sources, and determine whether dependencies are actively maintained. Note the approach for keeping dependencies updated.

10. **Perform threat modeling.** Identify assets worth protecting, threats to those assets, and attack vectors. For each threat, determine the likelihood and impact. Map threats to specific architectural components and integration points. This provides the foundation for the Known Gaps table and mitigation strategies.

11. **Define the initial release security scope.** Determine which security measures are required for the initial release and which can be deferred to future phases. Deferred measures must have explicit risk acceptance with documented rationale and timeline.

### Quality Criteria

The security review document meets quality standards when:

- Authentication and authorization approaches are specifically defined, not vaguely described. The review states exactly which auth mechanism is used, how tokens or sessions are managed, and what roles or permissions are scoped. If the ticket does not involve auth, this is explicitly marked N/A with reasoning.
- Data protection measures are mapped to specific sensitive data types. Each type of sensitive data identified has a concrete protection approach (encryption, access control, masking). Generic statements like "data will be protected" are insufficient -- specific mechanisms must be named.
- Input validation strategy covers all external input sources identified in the architecture. Every integration point that receives external data has a defined validation approach. Validation occurs at trust boundaries, not deep within the application.
- Dependency security assessment references actual dependencies from the architecture's technology choices. Known vulnerability status is checked, not assumed. Dependency sources are evaluated for trustworthiness.
- The Known Gaps table includes realistic risk assessments with specific mitigation strategies and clear status tracking. Each gap has a risk level, a concrete mitigation (not "will be addressed later"), and a status. Mitigations are practical and achievable.
- The threat model (if included) identifies concrete assets, specific threats tied to the architecture, and actionable mitigations. Threats are not generic OWASP categories listed without context -- they are specific to this ticket's attack surface.
- Initial release security scope clearly separates what ships now from what is deferred. Deferred items have explicit risk acceptance and a rationale for deferral.
- The security checklist is completed with checkmarks or explicit N/A status for each item. No items are left unmarked without explanation.
- The security review is consistent with the architecture. Security measures correspond to actual components and integration points in architecture.md. There are no references to components that do not exist in the architecture.
- The overall assessment is practical, not aspirational. Security measures are achievable within the ticket scope. Over-scoping security (requiring enterprise-grade controls for a simple feature) is as much an anti-pattern as under-scoping.

### Template

The security review document uses the template at:

    {PLUGIN_ROOT}/skills/project-workflow/templates/ticket/security-review.md

The template defines these sections that must be filled in:

| Section | What to Write |
|---------|---------------|
| Security Assessment | Overall security context for this ticket |
| Authentication & Authorization | How auth is handled, roles/permissions scoped, token handling |
| Data Protection | Sensitive data types identified with specific protection approaches |
| Input Validation | Validation approach for all external inputs, boundary enforcement |
| Dependencies | Security posture of third-party dependencies, vulnerability status, update strategy |
| Known Gaps | Risk table with gap description, risk level, mitigation strategy, and status |
| Initial Release Security Scope | What ships now vs. what is deferred with rationale |
| Security Checklist | Completed checklist covering secrets, validation, error handling, dependencies, injection, XSS, path traversal, secure defaults |
| Threat Model (Optional) | Assets, threats, and mitigations specific to the ticket architecture |
| Conclusion | Summary of security posture and ship-readiness assessment |

## Review Guide

### Review Focus Areas

When reviewing a security review document, evaluate it from the perspective of a senior security engineer who needs to determine whether this implementation can ship without unmitigated security risks. The reviewer should be asking: "Are all security-relevant aspects of this architecture assessed with practical, achievable mitigations?"

**Authentication and Authorization Adequacy**
- Is the auth approach specific to this ticket, not a generic description of auth concepts?
- Are roles and permissions scoped appropriately for the functionality being built?
- Is token or session handling addressed with concrete mechanisms?
- If the ticket does not involve auth, is this explicitly stated with reasoning?

**Data Protection Completeness**
- Are all sensitive data types identified (credentials, PII, tokens, API keys, financial data)?
- Does each data type have a specific protection approach (not generic "will be encrypted")?
- Are protection measures appropriate for the sensitivity level (not over-engineered or under-protected)?
- Is data protection addressed both at rest and in transit?

**Input Validation Coverage**
- Are all external input sources from the architecture covered?
- Does validation occur at trust boundaries (not buried deep within application logic)?
- Are validation approaches specific (type, range, format, sanitization) rather than vague?
- Do error messages avoid leaking sensitive information?

**Dependency Security Assessment**
- Are actual dependencies from the architecture's technology choices evaluated?
- Is vulnerability status based on real checks, not assumptions?
- Is there a strategy for keeping dependencies updated?
- Are dependency sources trusted and actively maintained?

**Threat Model Quality**
- Are threats specific to this ticket's architecture, not generic OWASP listings?
- Are assets concretely identified with reference to architectural components?
- Do mitigations address the specific threats identified, not just general best practices?
- Is the threat model proportionate to the ticket's risk profile?

**Known Gaps and Risk Acceptance**
- Is each gap described with a specific risk level and concrete mitigation?
- Are mitigations actionable and achievable (not vague "will be addressed")?
- Are gap statuses tracked (Open vs. Accepted)?
- Is the risk acceptance proportionate (not accepting high risks without justification)?

**Architecture Consistency**
- Does the security review reference actual components and integration points from architecture.md?
- Are there architectural features with security implications that the review does not address?
- Do technology choices from the architecture have their security implications assessed?
- Is the security scope consistent with the overall ticket scope?

**OWASP Alignment**
- Are common vulnerability categories addressed: injection, XSS, path traversal, insecure deserialization, security misconfiguration?
- Are the specific categories relevant to this ticket's technology stack assessed (e.g., SQL injection for database-backed services, XSS for web frontends)?
- Are irrelevant categories explicitly marked N/A rather than silently omitted?

### Common Issues

These problems frequently appear in security review documents:

1. **Generic security boilerplate.** The document lists standard security concerns without connecting them to the ticket's specific architecture, components, or data flows. Fix: reference specific architectural components, integration points, and data types from this ticket. Every security statement should be traceable to the architecture.

2. **Missing data classification.** Sensitive data types are not identified, or the "Data Protection" section is vague about what data needs protection. Fix: catalog every type of sensitive data the implementation handles and define a specific protection approach for each type.

3. **Input validation at wrong boundaries.** The validation strategy describes validation deep within the application rather than at trust boundaries where external data enters the system. Fix: identify every integration point that receives external data and ensure validation occurs at that boundary.

4. **Aspirational mitigations.** The Known Gaps table lists mitigations like "will be addressed in a future sprint" or "should be reviewed later" without concrete plans. Fix: define specific, actionable mitigation strategies with clear owners and timelines. If a gap is accepted, state the risk acceptance rationale explicitly.

5. **Security checklist left incomplete.** Checklist items are unmarked or only partially completed, with no indication of which items are N/A. Fix: every checklist item must be checked, unchecked with a remediation plan, or explicitly marked N/A with reasoning.

6. **Over-scoped security requirements.** The review demands enterprise-grade security controls (e.g., full RBAC, SOC 2 compliance, HSM key management) for a simple feature that does not warrant that level of protection. Fix: match security measures to the actual risk profile and scope of the ticket. Security should be proportionate.

7. **Threat model disconnected from architecture.** The threat model lists generic threats (SQL injection, DDoS) without mapping them to specific components or integration points in the architecture. Fix: tie each threat to a specific architectural element and explain the attack vector in the context of this design.

8. **Dependency assessment by assumption.** The dependencies section states "no known vulnerabilities" without evidence of checking. Fix: reference the specific method used to assess dependency security (audit tools, vulnerability databases, version checks).

### Review Checklist

Use this checklist when reviewing a security review document. Every item should be satisfied before approval.

- Authentication/authorization approach is specific to this ticket (or explicitly marked N/A with reasoning)
- Roles and permissions are scoped appropriately for the functionality
- Token or session handling is addressed with concrete mechanisms
- All sensitive data types are identified and cataloged
- Each sensitive data type has a specific protection approach (not generic statements)
- Data protection covers both at-rest and in-transit scenarios
- All external input sources from the architecture are covered by validation
- Input validation occurs at trust boundaries
- Validation approaches are specific (type, range, format, sanitization)
- Error messages do not leak sensitive information
- Dependencies from the architecture are assessed for known vulnerabilities
- Dependency sources are evaluated for trustworthiness and maintenance status
- Known Gaps table includes realistic risk levels and concrete mitigation strategies
- Gap mitigations are actionable (not vague "will be addressed later")
- Initial release security scope clearly separates shipped vs. deferred measures
- Deferred security measures have explicit risk acceptance with rationale
- Security checklist is fully completed (checked, unchecked with plan, or N/A with reasoning)
- Threat model (if included) ties threats to specific architectural components
- Threat mitigations are specific to the identified threats (not generic best practices)
- OWASP-relevant categories for this technology stack are addressed
- Security review references actual components and integration points from architecture.md
- Security measures are proportionate to the ticket's risk profile (not over-scoped or under-scoped)
- All template sections are addressed (filled or marked N/A with reasoning)
- Content is specific to this ticket (no boilerplate or generic statements)
- Security review is consistent with constraints from analysis.md
- Security review addresses security-related requirements from prd.md
