# HackenProof — Report Template

> Source: https://docs.hackenproof.com/

HackenProof's distinguishing feature is the **mandatory pre-validation gates** (commit/version, scope, dup, PoC). The formatted report MUST satisfy all four before submission.

## Format (per finding)

```markdown
# Title — root cause

## Vulnerability type

<select from HackenProof's classification: Smart Contract / Blockchain Protocol / Web & Mobile. For Rust on-chain code, almost always "Smart Contract".>

## Severity

<Critical / High / Medium / Low — per HackenProof's classification or the program-specific override.>

## Affected target

- **Repo**: <github URL>
- **Commit / version**: <SHA or tag — REQUIRED for Gate 1>
- **Component / asset**: <which crate / module / program ID is in scope>
- **File**: `crate/src/file.rs:LN-LN`

## Description

<technical description. Include the affected `crate::module::function`. Walk through the attack path.>

```rust
// crate/src/file.rs:LN-LN
<verbatim code excerpt>
```

## Steps to reproduce

> **MANDATORY for Gate 4.** At least one usable PoC artifact (steps + payload + tx hash + logs + attachment).

PoC tier (Argus): <1-4>. File: `$RUN_DIR/3-poc/F-NN/poc.rs`

1. <setup step>
2. <execution step>
3. <observation step>

Reproduction commands:
```bash
<exact commands>
```

Expected output (against buggy code):
```
<paste real test output>
```

## Impact

<concrete impact. Match to HackenProof's severity baseline or the program's specific impact list.>

## Suggested fix

<concrete code-level fix.>

```diff
- <buggy line(s)>
+ <fixed line(s)>
```
```

## Pre-validation gate self-check

Before submission, verify all four HackenProof gates pass:

- [ ] **Gate 1 — Commit/version match**: the report cites a concrete commit SHA / tag in scope per the program rules
- [ ] **Gate 2 — Scope match**: target asset AND impact category are both in scope (Argus Stage 6 verified this — confirm `bounty-page.md` mapping)
- [ ] **Gate 3 — Duplicate check**: no equivalent prior report (Argus Stage 7 verified — confirm no `hard-dup` flagged)
- [ ] **Gate 4 — PoC presence**: at least one usable artifact attached

## Discipline rules

- **Reversibility preferred**: HackenProof responders prefer "Need more info" over premature invalidation. If your PoC is borderline, attach what you have — they'll ask for more rather than reject.
- **Concrete commit/version is non-negotiable**. "Latest main" is acceptable only if the program rules say so. Otherwise cite a specific SHA.
- **Reputation may matter**: some HackenProof programs require minimum reputation. Argus Stage 6 should have surfaced this from the bounty page.

## Anti-patterns

- Missing commit SHA → Gate 1 fail → "Need more info" status.
- Out-of-scope target / impact → Gate 2 fail → "Out of scope" status.
- Same root cause as a prior triaged report → Gate 3 fail → "Duplicate" status.
- English-only repro steps without an attachment → Gate 4 fail.
