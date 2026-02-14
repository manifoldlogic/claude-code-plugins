# Dependency Audit: {NAME}

## Overview

[High-level description of the dependency changes in this ticket. What new packages are being added? What existing packages are being upgraded? Why are these changes needed?]

**Total New Dependencies:** [Number]
**Total Upgraded Dependencies:** [Number]
**Total Removed Dependencies:** [Number]
**Package Manager:** [npm / pip / cargo / go mod / Other]

## New Dependencies

[List every new dependency being introduced. Each dependency must be individually justified.]

### [Package Name 1]

| Attribute | Value |
|-----------|-------|
| **Version** | [e.g., ^2.3.0] |
| **License** | [e.g., MIT] |
| **Weekly Downloads** | [e.g., 5.2M] |
| **Last Published** | [e.g., 2 weeks ago] |
| **Maintainers** | [e.g., 3 active maintainers] |
| **Open Issues** | [e.g., 45 open / 1200 closed] |
| **Bundle Size** | [e.g., 12KB minified + gzipped (if frontend)] |
| **Transitive Dependencies** | [e.g., 4 dependencies] |

**Purpose:** [Why this dependency is needed -- what problem it solves]

**Justification:** [Why this package was chosen over alternatives or building in-house]

**Risk Assessment:** [Low / Medium / High -- based on maintenance health, security track record, community size]

### [Package Name 2]

[Continue pattern for each new dependency...]

## Licenses

[License compatibility analysis for all new and modified dependencies.]

### License Summary

| Dependency | License | Compatible | Notes |
|------------|---------|------------|-------|
| [package-1] | [MIT] | [Yes] | [Permissive, no concerns] |
| [package-2] | [Apache-2.0] | [Yes] | [Requires attribution in notices] |
| [package-3] | [GPL-3.0] | [Check] | [Copyleft -- may require source disclosure] |
| [package-4] | [BSD-3-Clause] | [Yes] | [Permissive with non-endorsement clause] |

### License Policy Compliance

- [ ] All new dependencies use approved licenses (per project/org license policy)
- [ ] No copyleft licenses introduced without legal review (GPL, AGPL, LGPL)
- [ ] Attribution requirements documented for licenses that require it (Apache-2.0, BSD)
- [ ] No "unknown" or custom licenses without review
- [ ] Transitive dependency licenses also checked

### License Categories

**Permissive (generally safe):** MIT, BSD-2-Clause, BSD-3-Clause, ISC, Apache-2.0, Unlicense, CC0

**Weak Copyleft (review required):** LGPL-2.1, LGPL-3.0, MPL-2.0, EPL-2.0

**Strong Copyleft (legal review required):** GPL-2.0, GPL-3.0, AGPL-3.0

**Non-Open (block without approval):** SSPL, BSL, proprietary, "Commons Clause"

## Security

[Security assessment of new and upgraded dependencies.]

### Vulnerability Scan

- [ ] `npm audit` / `pip audit` / `cargo audit` run with zero critical/high findings
- [ ] Snyk / Dependabot / Socket scan completed
- [ ] No known CVEs in pinned versions

### Vulnerability Report

| Dependency | CVE/Advisory | Severity | Status | Mitigation |
|------------|-------------|----------|--------|------------|
| [package] | [CVE-XXXX-XXXXX] | [Critical/High/Medium/Low] | [Fixed/Accepted/Mitigated] | [Action taken] |

*If no vulnerabilities found, state: "No known vulnerabilities detected as of [date]."*

### Supply Chain Risk

[Assessment of supply chain security risks.]

- [ ] Package published by verified maintainer (not a typosquat)
- [ ] Package source matches published artifact (if verifiable)
- [ ] No install scripts that execute arbitrary code (`preinstall`, `postinstall`)
- [ ] No network calls during installation
- [ ] Package not recently transferred to new maintainer (check for ownership changes)
- [ ] No unpinned dependencies that could introduce malicious transitive updates

### Security History

[Has this package had security incidents in the past?]

- [Package 1]: [Clean history / Had CVE-XXXX in v1.2, fixed in v1.3 -- we use v2.0]
- [Package 2]: [Maintainer account compromised in YYYY -- recovered, now has 2FA]

## Maintenance

[Assessment of each dependency's long-term maintenance health.]

### Maintenance Health Matrix

| Dependency | Last Release | Release Frequency | Open Issues | Bus Factor | Health |
|------------|-------------|-------------------|-------------|------------|--------|
| [package-1] | [2 weeks ago] | [Monthly] | [45 / 1200] | [3+ maintainers] | [Healthy] |
| [package-2] | [8 months ago] | [Quarterly] | [120 / 300] | [1 maintainer] | [At Risk] |
| [package-3] | [2 days ago] | [Weekly] | [10 / 500] | [Foundation-backed] | [Healthy] |

### Health Criteria

- **Healthy:** Active releases, responsive maintainers, growing community, funded/backed
- **At Risk:** Infrequent releases, single maintainer, growing issue backlog, no funding
- **Unmaintained:** No releases in 12+ months, unresponsive maintainers, archived repo

### Maintenance Concerns

[Flag any dependencies with maintenance risks.]

- [Package]: [Concern -- e.g., "Single maintainer with declining commit frequency. Fork plan: [alternative] if abandoned."]
- [Package]: [Concern -- e.g., "Last release 6 months ago but project is considered stable/feature-complete. Acceptable risk."]

## Alternatives Considered

[For each new dependency, document what alternatives were evaluated and why they were rejected.]

### [Package Name 1] vs Alternatives

| Option | Pros | Cons | Decision |
|--------|------|------|----------|
| **[Chosen package]** | [Pro 1, Pro 2] | [Con 1] | **Selected** |
| [Alternative A] | [Pro 1] | [Con 1, Con 2] | [Rejected: reason] |
| [Alternative B] | [Pro 1] | [Con 1] | [Rejected: reason] |
| Build in-house | [Full control, no dependency] | [Development time, maintenance burden] | [Rejected: not justified for scope] |

### [Package Name 2] vs Alternatives

[Continue pattern for each new dependency...]

### Build vs Buy Analysis

[For significant dependencies, justify why using an external package is preferable to building the functionality in-house.]

- **Estimated build effort:** [Time to implement equivalent functionality]
- **Ongoing maintenance cost:** [Who maintains custom implementation vs community]
- **Decision:** [Use package / Build in-house -- with rationale]

## Dependency Graph Impact

[How do the new dependencies affect the overall dependency tree?]

### Tree Size Impact

- **Before:** [e.g., 1,247 packages in lockfile]
- **After:** [e.g., 1,253 packages in lockfile (+6)]
- **New transitive dependencies:** [List notable transitive dependencies introduced]

### Duplicate / Conflicting Versions

- [ ] No duplicate package versions introduced (check lockfile)
- [ ] No version conflicts with existing dependencies
- [ ] Peer dependency requirements satisfied

### Bundle Size Impact (frontend only)

- **Before:** [e.g., 245KB gzipped]
- **After:** [e.g., 257KB gzipped (+12KB)]
- **Tree-shakeable:** [Yes / No -- does the package support ES modules?]

## Update Strategy

[How will these dependencies be kept up to date?]

- [ ] Dependabot / Renovate configured for automated PRs
- [ ] Version pinning strategy defined: [Exact / Range / Latest]
- [ ] Breaking update policy: [Review and test before adopting major versions]
- [ ] Security update policy: [Apply critical/high patches within 48 hours]

## Audit Checklist

- [ ] All new dependencies individually listed and justified
- [ ] License compatibility verified for all new packages
- [ ] Security vulnerability scan completed with no unmitigated critical/high findings
- [ ] Maintenance health assessed for each new dependency
- [ ] Alternatives evaluated and documented
- [ ] Supply chain risk assessment completed
- [ ] Dependency tree impact measured
- [ ] Update strategy defined
- [ ] No unnecessary dependencies (each one serves a clear purpose)

## N/A Sign-Off (If Not Applicable)

If this document is not applicable to the current ticket, complete this section instead:

**Status:** N/A
**Assessed:** {date}

### Assessment
{1-3 sentence justification}

### Re-evaluate If
{Condition that would make this document applicable}
