# Audit Readiness Report Template

Generate the report using this structure. Replace all placeholders with actual data.

---

```markdown
# Audit Readiness Report

**Project:** <project name>
**Date:** <generation date>
**Framework:** <Anchor / Native solana_program / Both>
**Rust Edition:** <edition detected>
**Anchor Version:** <version or N/A>
**Solana SDK Version:** <version detected>
**Programs in Scope:** <N files, M lines>

---

## Overall Score: <XX>/100 — <VERDICT>

| Phase | Score | Weight | Weighted |
|-------|-------|--------|----------|
| Test Coverage | <X>/100 | 30% | <X> |
| Documentation | <X>/100 | 15% | <X> |
| Code Hygiene | <X>/100 | 20% | <X> |
| Dependencies | <X>/100 | 15% | <X> |
| Best Practices | <X>/100 | 20% | <X> |

---

## 🎯 Quick Wins

The 5 highest-impact, lowest-effort fixes to improve your score:

1. <description> — <file:line> — <expected score impact>
2. ...
3. ...
4. ...
5. ...

---

## Phase 1: Test Coverage (<X>/100)

**Overall Coverage:** <X>% (lines) / <X>% (branches)
**Target:** 90% minimum, 100% ideal
**Method:** <measured via cargo-tarpaulin / estimated from test analysis>

### Worst-covered modules:

| Module | Lines | Branches | Test File |
|--------|-------|----------|-----------|
| <path> | <X>% | <X>% | <exists/missing> |
| ... | ... | ... | ... |

### Critical untested instruction handlers:

These handle value transfers or modify critical state and lack test coverage:

- `<program>::<instruction>()` — <file:line> — <reason this is critical>
- ...

---

## Phase 2: Documentation (<X>/100)

**Coverage:** <X>/<Y> public items documented (<Z>%)

### Missing documentation:

| File | Element | Missing |
|------|---------|---------|
| <path> | `pub fn deposit()` | `///` doc comment |
| <path> | `struct VaultState` | field-level `///` docs |
| ... | ... | ... |

---

## Phase 3: Code Hygiene (<X>/100)

### Findings by category:

| Category | Count | Severity |
|----------|-------|----------|
| TODOs/FIXMEs | <N> | Medium |
| println!/dbg! macros | <N> | High |
| Missing overflow-checks | <0/1> | High |
| Commented-out code | <N> | Low |
| unwrap() on user input | <N> | Medium |
| unsafe blocks | <N> | Varies |
| ... | ... | ... |

### Details:

<For each finding: file:line, description, suggested fix>

---

## Phase 4: Dependencies (<X>/100)

### Dependency inventory:

| Crate | Current | Latest | CVEs | Status |
|-------|---------|--------|------|--------|
| anchor-lang | <ver> | <ver> | <N> | <ok/outdated/yanked> |
| solana-program | <ver> | <ver> | <N> | <ok/outdated> |
| spl-token | <ver> | <ver> | <N> | <ok/outdated> |
| ... | ... | ... | ... | ... |

### Findings:

<Any outdated versions, known CVEs, duplicate deps — with severity and recommended action>

---

## Phase 5: Best Practices (<X>/100)

### Account validation findings:

| Finding | File | Line | Severity | Framework |
|---------|------|------|----------|-----------|
| Missing signer check | <path> | <N> | Critical | <Anchor/Native> |
| Missing owner check | <path> | <N> | Critical | <Anchor/Native> |
| ... | ... | ... | ... | ... |

### Arithmetic safety findings:

| Finding | File | Line | Severity |
|---------|------|------|----------|
| Direct arithmetic without checked_* | <path> | <N> | High |
| Division before multiplication | <path> | <N> | High |
| ... | ... | ... | ... |

### CPI safety findings:

| Finding | File | Line | Severity |
|---------|------|------|----------|
| Arbitrary CPI target | <path> | <N> | Critical |
| Missing reload after CPI | <path> | <N> | High |
| ... | ... | ... | ... |

### Token safety findings:

| Finding | File | Line | Severity |
|---------|------|------|----------|
| Token program as AccountInfo | <path> | <N> | Critical |
| Missing mint validation | <path> | <N> | High |
| ... | ... | ... | ... |

### Token-2022 extension findings:

| Finding | File | Line | Severity |
|---------|------|------|----------|
| Transfer Hook not validated | <path> | <N> | Critical |
| Permanent Delegate not checked | <path> | <N> | Critical |
| Missing extension enumeration | <path> | <N> | Medium |
| ... | ... | ... | ... |

### Compute optimization opportunities:

| Type | Count | Impact |
|------|-------|--------|
| Missing zero-copy | <N> | Reduced CU usage on large accounts |
| Redundant account loads | <N> | ~100 CU per redundant load |
| Excessive msg! calls | <N> | ~100 CU per msg! |
| ... | ... | ... |

---

## Phase 6: Vulnerability Scan (Optional)

<If a dedicated Solana vulnerability scanner was run (Soteria, Trident, Solazy, etc.),
include its findings here grouped by severity.>

<If no scanner was available, include this recommendation:>

> **Recommended next step:** Run a dedicated vulnerability scanner for deeper analysis.
> Suggested tools:
> - **Trident** (Ackee Blockchain) — fuzz testing framework (`cargo install trident-cli`)
> - **Soteria / sec3** — static analysis for Anchor programs
> - **Solazy** — SAST + reverse engineering CLI
> - **cargo-geiger** — unsafe Rust usage across dependency tree

---

## Appendix: Full Findings List

<Complete list of all findings, sorted by severity (Critical > High > Medium > Low > Info),
with file paths, line numbers, descriptions, and suggested fixes.>
```

---

## Scoring Rules

### Test Coverage Score
Direct mapping: coverage percentage = score.
If coverage tools failed to run (missing dependency, compilation error), score is 0.

### Documentation Score
`(fully_documented_pub_items / total_pub_items) * 100`
An item counts as "fully documented" only if it has a `///` doc comment.

### Code Hygiene Score
Start at 100. Deductions:
- println!/dbg! in production: -15 each
- Missing overflow-checks in release profile: -15
- TODO/FIXME: -3 each (cap at -30)
- Commented-out code blocks: -2 each (cap at -20)
- Dead code: -5 each
- unsafe without justification: -10 each

### Dependencies Score
Start at 100. Deductions:
- Known CVE in dependency: -20 each (critical), -10 (others)
- Outdated by major version: -15 each
- Yanked crate: -15 each
- Missing Cargo.lock: -10
- Outdated by minor version: -5 each
- Duplicate versions of same crate: -5 each

### Best Practices Score
Start at 100. Deductions:
- Missing signer check: -15 each
- Missing owner check: -15 each
- Pubkey-only authority (no signer): -15 each
- Arbitrary CPI target: -15 each
- Account revival after close: -15 each
- Transfer Hook not validated: -15 each
- Permanent Delegate not checked: -15 each
- AccountInfo as CPI program: -15 each
- Missing has_one/seed constraint: -10 each
- Shared PDA across domains: -10 each
- init_if_needed usage: -10 each
- Missing mint/authority validation: -10 each
- Token-2022 extension not enumerated: -10 each (cap at -30)
- Direct arithmetic without overflow protection: -10 each (cap at -30)
- Close without cleanup: -10 each
- PDA seed collision risk: -5 each
- Hardcoded lamports in create_account: -5 each
- as cast between int widths: -5 each (cap at -15)
- Missing event/log on state change: -3 each (cap at -30)
- unwrap() on user input: -3 each (cap at -15)
- Vec operations in loops (no pre-alloc): -2 each (cap at -10)

## Verdicts

- 90-100: ✅ **Audit Ready** — Your codebase meets the standard. Proceed with scheduling your audit.
- 75-89: ⚠️ **Almost Ready** — A few items to address. Most audit firms would accept this but you'd get cleaner results by fixing the flagged items first.
- 50-74: 🔶 **Needs Work** — Significant preparation needed. Address the findings before engaging auditors to avoid wasting their time on preventable issues.
- Below 50: ❌ **Not Ready** — Major gaps in testing, documentation, or code quality. Investing time here first will dramatically improve the value you get from an audit.
