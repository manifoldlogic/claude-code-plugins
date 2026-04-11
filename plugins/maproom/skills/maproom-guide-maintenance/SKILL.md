---
name: maproom-guide-maintenance
description: |
  Procedures for maintaining the maproom-guide skill documentation.
  Use when updating guide content after maproom CLI changes, adding new error
  case explanations, or auditing guide accuracy. Not for using maproom or
  interpreting results — use maproom-guide or maproom-search for those.
---

# Maproom Guide Maintenance

Procedures for keeping the maproom-guide skill accurate and up to date.

## When to Use

- After maproom CLI version changes (new flags, changed behavior, removed features)
- After discovering a new error pattern that users encounter
- When the maproom-cleric agent identifies accuracy issues
- During periodic (monthly) documentation audits

---

## Adding a New Error Case

1. **Add conceptual explanation** to `maproom-guide/references/error-diagnosis.md` in the appropriate category section (Credential, Index, CLI, Query, or Infrastructure)
2. **Add triage row** to the Error Triage table in `maproom-guide/SKILL.md` — one row with symptom, likely cause, and what to do
3. **If step-by-step recovery is needed**, add an entry to `maproom-search/references/troubleshooting.md` (that document covers "how to fix", the guide covers "why it happens")
4. **Run** `bash plugins/maproom/scripts/verify-docs.sh` to check cross-reference integrity

## Updating After CLI Changes

1. **Detect drift**: Run `bash plugins/maproom/scripts/monthly-cli-verification.sh` for full audit, or `bash plugins/maproom/scripts/compare-cli-flags.sh` for quick flag diff
2. **Identify affected guide content**: Check if changed flags or behaviors are referenced in:
   - `maproom-guide/SKILL.md` (score ranges, chunk kinds, error symptoms)
   - `maproom-guide/references/result-interpretation.md` (scoring, format anatomy)
   - `maproom-guide/references/error-diagnosis.md` (error patterns, CLI behaviors)
   - `maproom-guide/references/concept-glossary.md` (infrastructure descriptions)
3. **Update affected sections** in the guide references
4. **Update maproom-search SKILL.md** if command syntax changed (that is the authoritative command reference)
5. **Run** `bash plugins/maproom/scripts/verify-docs.sh` to validate consistency

## Adding a New Concept

1. **Add to** `maproom-guide/references/concept-glossary.md` in the appropriate learning-path section (Foundation, Search, Embeddings, Infrastructure, or Comparison)
2. **If the concept affects result interpretation**, also update `maproom-guide/references/result-interpretation.md`
3. **Only add to main SKILL.md** if the concept is daily-use-level fundamental (like FTS, vector, chunk, embedding, score). The main SKILL.md stays compact; depth lives in references.

## Verification Scripts

| Script | Purpose | When to Run |
|---|---|---|
| `scripts/verify-docs.sh` | Cross-reference integrity, format consistency | After any doc change |
| `scripts/monthly-cli-verification.sh` | Full CLI flag audit against baseline | Monthly (first Friday) |
| `scripts/compare-cli-flags.sh` | Quick flag diff against baseline | After CLI updates |

## Maintaining Complementary Boundaries

The guide system has a strict division of responsibility. When adding content, ensure it goes to the right document:

| Content Type | Belongs In |
|---|---|
| "What does this mean?" | maproom-guide (SKILL.md or references/) |
| "How do I fix this?" | maproom-search/references/troubleshooting.md |
| "How do I use this command?" | maproom-search SKILL.md |
| "How do I maintain the guide?" | This document |

## Related

| Resource | Role |
|---|---|
| **maproom-guide** | The skill being maintained |
| **maproom-search** | Authoritative command reference (guide must complement, not duplicate) |
| **maproom-cleric** agent | Automated accuracy auditing companion |
