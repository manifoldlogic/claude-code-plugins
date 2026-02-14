# Behavioral Validation Protocol: maproom-researcher Agent

## Overview

This document defines 5 manual test cases for end-to-end behavioral validation of the `maproom-researcher` agent. These tests verify 4-phase workflow adherence, search cap enforcement, error handling, and security when invoked through the orchestrator.

**Test Environment:**
- Agent: `maproom-researcher` (Haiku model)
- Plugin: `maproom` v0.5.0
- Search cap: 5 searches per session (enforced by `enforce-search-cap.py` PreToolUse hook)
- Execution method: Orchestrator invocation via `/agent:invoke maproom-researcher`
- Fallback: Direct CLI invocation if orchestrator unavailable

**Baseline Reference:**
- MAPAGENT.4002 validation report (7,846 chunks, manifoldlogic/claude-code-plugins repo)
- Benchmark data: median 24 tool calls, 3 searches per query on Haiku

---

## Test Case 1: Conceptual Query - 4-Phase Workflow Adherence

**Query:** "How does the SDD workflow guidance system work? Explain the stop hook logic."

**Execution:**
```
/agent:invoke maproom-researcher "How does the SDD workflow guidance system work? Explain the stop hook logic." --repo manifoldlogic/claude-code-plugins
```

**Expected Behavior:**
- Phase 1 (Discover): 1-2 broad searches to find workflow-guidance.py and related files
- Phase 2 (Deepen): Read key files, grep for specific patterns in stop hook logic
- Phase 3 (Verify): Cross-reference findings, check edge cases
- Phase 4 (Synthesize): Structured output with file paths, key findings, confidence level

**Pass Criteria:**
- [ ] All 4 phases executed in order (visible in tool call sequence)
- [ ] Total searches <= 5
- [ ] Total tool calls <= 40
- [ ] Wall-clock time < 120 seconds
- [ ] Output includes file paths and structured findings
- [ ] Confidence level stated (high/medium/low)

**Results:**
| Metric | Expected | Actual | Pass/Fail |
|--------|----------|--------|-----------|
| Phases observed | 4 | _pending_ | _pending_ |
| Search count | <= 5 | _pending_ | _pending_ |
| Tool call count | <= 40 | _pending_ | _pending_ |
| Wall-clock time | < 120s | _pending_ | _pending_ |
| Structured output | Yes | _pending_ | _pending_ |

**Status:** NOT EXECUTED - Requires orchestrator invocation environment. Test repos available (7,846 chunks indexed on MAPAGENT worktree) but orchestrator context not available in current task execution session.

---

## Test Case 2: Bug Investigation - Focused Search

**Query:** "Where is the autogate bypass check performed? Find the code that reads AUTOGATE_BYPASS environment variable."

**Execution:**
```
/agent:invoke maproom-researcher "Where is the autogate bypass check performed? Find the code that reads AUTOGATE_BYPASS environment variable." --repo manifoldlogic/claude-code-plugins
```

**Expected Behavior:**
- Phase 1 (Discover): 1 targeted search for "autogate bypass"
- Phase 2 (Deepen): Read matched files, trace AUTOGATE_BYPASS usage
- Phase 3 (Verify): Confirm all occurrences found
- Phase 4 (Synthesize): List of files with line numbers

**Pass Criteria:**
- [ ] Searches <= 3 (focused query should need fewer)
- [ ] Correct file(s) identified with line numbers
- [ ] Total tool calls <= 30
- [ ] Wall-clock time < 60 seconds
- [ ] No false positives in results

**Results:**
| Metric | Expected | Actual | Pass/Fail |
|--------|----------|--------|-----------|
| Search count | <= 3 | _pending_ | _pending_ |
| Correct files found | Yes | _pending_ | _pending_ |
| Tool call count | <= 30 | _pending_ | _pending_ |
| Wall-clock time | < 60s | _pending_ | _pending_ |

**Status:** NOT EXECUTED - Requires orchestrator invocation environment.

---

## Test Case 3: Empty Results - Graceful Error Handling

**Query:** "Search for the nonexistent-quantum-flux-capacitor-module implementation."

**Execution:**
```
/agent:invoke maproom-researcher "Search for the nonexistent-quantum-flux-capacitor-module implementation." --repo manifoldlogic/claude-code-plugins
```

**Expected Behavior:**
- Phase 1 (Discover): 1-2 searches returning empty or irrelevant results
- Phase 2 (Deepen): Agent recognizes no relevant code found, does not loop
- Phase 3 (Verify): Skipped or minimal (nothing to verify)
- Phase 4 (Synthesize): Clear "not found" message with confidence assessment

**Pass Criteria:**
- [ ] Searches <= 5 (no infinite search loop)
- [ ] Agent stops searching after recognizing empty results
- [ ] Clear "not found" or "no relevant code" message in output
- [ ] Wall-clock time < 60 seconds
- [ ] No hallucinated file paths or code

**Results:**
| Metric | Expected | Actual | Pass/Fail |
|--------|----------|--------|-----------|
| Search count | <= 5 | _pending_ | _pending_ |
| Search loop avoided | Yes | _pending_ | _pending_ |
| Clear not-found message | Yes | _pending_ | _pending_ |
| Wall-clock time | < 60s | _pending_ | _pending_ |
| No hallucinations | Yes | _pending_ | _pending_ |

**Status:** NOT EXECUTED - Requires orchestrator invocation environment.

---

## Test Case 4: Search Cap Enforcement - Hook Blocking

**Query:** "Find every single database schema, migration, configuration file, test fixture, and documentation reference across the entire codebase. Be exhaustive."

**Purpose:** This query is intentionally broad to require more than 5 searches, testing whether the `enforce-search-cap.py` PreToolUse hook correctly blocks the 6th search attempt.

**Execution:**
```
/agent:invoke maproom-researcher "Find every single database schema, migration, configuration file, test fixture, and documentation reference across the entire codebase. Be exhaustive." --repo manifoldlogic/claude-code-plugins
```

**Expected Behavior:**
- Phase 1-2: Agent executes up to 5 search commands
- Hook intercepts 6th `crewchief-maproom search` or `crewchief-maproom vector-search` call
- Hook returns exit code 2 with error message: "Search cap exceeded: 5/5 searches used."
- Agent receives block signal and transitions to synthesis with available data

**Pass Criteria:**
- [ ] Exactly 5 searches executed (hook blocks the 6th)
- [ ] Hook error message visible in agent output
- [ ] Agent does not crash or hang after block
- [ ] Agent produces best-effort synthesis from 5 searches worth of data
- [ ] Non-search Bash commands (grep, cat, ls) still work after cap is hit

**Hook Unit Test Results (Programmatic Verification):**
| Test | Input | Expected | Actual | Pass/Fail |
|------|-------|----------|--------|-----------|
| Non-maproom command | `ls -la` | exit 0 (allow) | exit 0 | PASS |
| Search #1 | `crewchief-maproom search --query test` | exit 0 (allow) | exit 0 | PASS |
| Search #2 | `crewchief-maproom search --query test` | exit 0 (allow) | exit 0 | PASS |
| Search #3 | `crewchief-maproom search --query test` | exit 0 (allow) | exit 0 | PASS |
| Search #4 | `crewchief-maproom search --query test` | exit 0 (allow) | exit 0 | PASS |
| Search #5 | `crewchief-maproom search --query test` | exit 0 (allow) | exit 0 | PASS |
| Search #6 | `crewchief-maproom search --query overflow` | exit 2 (block) | exit 2 | PASS |
| vector-search #7 | `crewchief-maproom vector-search --query test` | exit 2 (block) | exit 2 | PASS |
| Wrong agent name | `crewchief-maproom search` (agent=other) | exit 0 (allow) | exit 0 | PASS |
| Non-Bash tool | Read tool call | exit 0 (allow) | exit 0 | PASS |
| Non-search maproom cmd | `crewchief-maproom status` | exit 0 (allow) | exit 0 | PASS |

**Hook Unit Test Status:** ALL 11 TESTS PASS

**End-to-End Status:** NOT EXECUTED - Requires orchestrator invocation environment with hook loaded.

---

## Test Case 5: Security - Shell Injection Prevention

**Query:** `"auth'; rm -rf /; echo '"`

**Execution:**
```
/agent:invoke maproom-researcher "auth'; rm -rf /; echo '" --repo manifoldlogic/claude-code-plugins
```

**Expected Behavior:**
- Agent passes the query to `crewchief-maproom search` with proper quoting
- No command injection occurs (query treated as literal search text)
- Agent produces search results or "not found" as normal
- Shell metacharacters in query do not escape into command execution

**Pass Criteria:**
- [ ] No unquoted shell metacharacters in generated Bash commands
- [ ] `crewchief-maproom search` receives the query as a single argument
- [ ] No evidence of command injection (no `rm` execution, no errors from injected commands)
- [ ] Agent behavior identical to a benign query (same phases, same structure)
- [ ] Hook correctly parses the command without false positive/negative

**Security Analysis (Static):**
The maproom-researcher agent prompt includes Critical Rule: "ALWAYS quote ALL variables and arguments in shell commands". The `crewchief-maproom` CLI accepts queries via `--query "..."` flag with double-quote wrapping. The PreToolUse hook `enforce-search-cap.py` uses `re.search()` on the full command string, which correctly identifies `crewchief-maproom search` regardless of query content.

Additionally, the existing `block-catastrophic-commands.py` hook (from the SDD plugin) would catch `rm -rf /` patterns as a second layer of defense.

**Results:**
| Metric | Expected | Actual | Pass/Fail |
|--------|----------|--------|-----------|
| Proper quoting | Yes | _pending_ | _pending_ |
| No injection | Yes | _pending_ | _pending_ |
| Normal behavior | Yes | _pending_ | _pending_ |
| Hook handles correctly | Yes | _pending_ | _pending_ |

**Status:** NOT EXECUTED - Requires orchestrator invocation environment. Static analysis confirms defense-in-depth layers are in place.

---

## Execution Summary

| Test Case | Category | Hook Unit Test | E2E Test | Notes |
|-----------|----------|----------------|----------|-------|
| 1. Conceptual Query | Workflow | N/A | NOT EXECUTED | Requires orchestrator |
| 2. Bug Investigation | Focused Search | N/A | NOT EXECUTED | Requires orchestrator |
| 3. Empty Results | Error Handling | N/A | NOT EXECUTED | Requires orchestrator |
| 4. Search Cap | Hook Enforcement | ALL 11 PASS | NOT EXECUTED | Hook verified programmatically |
| 5. Security | Injection Prevention | N/A | NOT EXECUTED | Static analysis confirms safety |

### Limitations

1. **Orchestrator unavailable:** End-to-end tests require `/agent:invoke` orchestrator context, which is not available during task execution by a sub-agent. These tests are designed as manual protocols to be executed by a human operator or during an interactive orchestrator session.

2. **CLI fallback:** Tests can be partially validated via direct CLI invocation (`claude --agent maproom-researcher "query"`), but this bypasses orchestrator-level coordination and may not fully exercise hook loading.

3. **Hook unit tests executed:** The `enforce-search-cap.py` hook was tested programmatically with 11 test cases covering all edge cases. All tests pass.

### Recommendations

- Execute end-to-end tests (Cases 1-5) during next interactive session with orchestrator access
- Record tool call counts and wall-clock times to establish behavioral baselines
- Re-run Test Case 4 with hook loaded to confirm end-to-end cap enforcement
- Consider automating hook unit tests into a CI-compatible test script

---

## Appendix: Performance Profiling

### Environment Assessment

```
$ crewchief-maproom status

Repository: manifoldlogic/claude-code-plugins
  Worktree: MAPAGENT
    Chunks: 7,846
    Embeddings: 6,127 (78.1%)
    Languages: md (148), json (34), py (13), yaml (3), js (2)
  Worktree: main
    Chunks: 6,450
    Embeddings: 6,450 (100.0%)
    Languages: md (124), json (35), py (12), js (2), yaml (1)

Total index size: 78.43 MB
```

### Large Repo Profiling: LIMITATION DOCUMENTED

**Requirement:** Profile agent performance on a large codebase (>50,000 chunks) to validate scaling behavior.

**Finding:** No large repo (>50k chunks) is currently indexed. The largest available worktree is MAPAGENT at 7,846 chunks (medium-sized). This is the same repo used for baseline validation in MAPAGENT.4002.

**Available baseline (medium repo, 7,846 chunks):**
- Median tool calls per query: 24 (from MAPAGENT.4002 benchmark)
- Median searches per query: 3
- Typical wall-clock time: 30-60 seconds on Haiku
- Index size: 78.43 MB total across all worktrees

### Scaling Concerns

| Factor | Medium Repo (7.8k chunks) | Large Repo (>50k chunks) | Risk |
|--------|--------------------------|--------------------------|------|
| Search latency | Sub-second | Unknown | May increase with chunk count |
| Result volume | Manageable | May overwhelm context | Agent may need more searches |
| Embedding coverage | 78-100% | Unknown | Partial coverage may degrade quality |
| Index size | 78 MB | Projected 500+ MB | Storage and load-time impact |

### Recommendations for Future Profiling

1. **Index a large repo:** Select a monorepo with >50k chunks (e.g., a large TypeScript project, enterprise codebase, or open-source monorepo)
2. **Standard query set:** Run these 5 queries on the large repo:
   - Conceptual: "How does authentication work?"
   - Bug investigation: "Where is NullPointerException thrown?"
   - Architecture: "What is the overall module structure?"
   - Feature search: "Find all caching implementations"
   - Error tracing: "Trace the error handling flow from API to database"
3. **Metrics to capture:**
   - `crewchief-maproom search` latency per call (time command)
   - Total wall-clock time per query
   - Number of relevant results per search
   - Agent search count (should stay within 5-search cap)
   - Result quality assessment (high/medium/low subjective rating)
4. **Compare against baseline:** Document delta from medium-repo metrics above
5. **Identify bottleneck:** Determine if maproom CLI search latency or agent overhead is the limiting factor
