# Security Review: {NAME}

## Security Assessment

### Authentication & Authorization

[How auth is handled in this ticket]

- [ ] Auth approach defined
- [ ] Roles/permissions scoped
- [ ] Token handling secure

### Data Protection

[How sensitive data is protected]

**Sensitive Data Identified:**
- [Data type 1]: [Protection approach]
- [Data type 2]: [Protection approach]

### Input Validation

[Input validation approach]

- [ ] All external inputs validated
- [ ] Validation happens at boundaries
- [ ] Error messages don't leak info

### Dependencies

[Security considerations for dependencies]

- [ ] Dependencies up to date
- [ ] No known vulnerabilities
- [ ] Trusted sources only

## Known Gaps

| Gap | Risk Level | Mitigation | Status |
|-----|------------|------------|--------|
| [Gap 1] | Low/Med/High | [Mitigation] | Open/Accepted |
| [Gap 2] | Low/Med/High | [Mitigation] | Open/Accepted |

## Initial Release Security Scope

**In Scope for Initial Release:**
- [Security measure 1]
- [Security measure 2]

**Deferred to Future Phases:**
- [Future security measure 1]
- [Future security measure 2]

## Security Checklist

- [ ] No hardcoded secrets
- [ ] Secrets via environment variables
- [ ] Input validation on external inputs
- [ ] Proper error handling (no info leakage)
- [ ] Dependencies are up to date
- [ ] No SQL injection vulnerabilities
- [ ] No XSS vulnerabilities (if applicable)
- [ ] No path traversal vulnerabilities
- [ ] Secure defaults

## Threat Model (Optional)

**Assets:**
- [Asset 1]

**Threats:**
- [Threat 1]: [Mitigation]

## Conclusion

[Summary of security posture]

**Ship Ready:** [Yes/No with brief rationale]
