# Generic / Self-Hosted — Strict Defaults

When no platform is specified at run start, OR the bounty URL points at a self-hosted page, OR the program-mode is `generic`, Argus applies the strictest defaults to bias toward rejection. **Err on the side of rejection — under-grading is recoverable, over-grading is not.**

## Severity definitions (Sherlock-Competition baseline + Cantina matrix)

We adopt Sherlock's strict thresholds for principal-loss and Cantina's Impact × Likelihood matrix for everything else.

### High
- Direct fund loss without extensive external conditions, OR
- Impact High + Likelihood ≥ Medium per Cantina matrix
- Quantifiable as >1% AND >$10 of principal / yield / fees (Sherlock-style)

### Medium
- Fund loss requiring external conditions, OR
- Breaks core functionality, OR
- Impact High + Likelihood Low (Cantina matrix), OR
- Impact Medium + Likelihood ≥ Medium
- Quantifiable as >0.01% AND >$10 of principal / yield / fees

### Low
- Impact Low + Likelihood ≥ Medium, OR
- Impact Medium + Likelihood Low, OR
- Bounded dust / rounding harm

### Informational
- Impact Low + Likelihood Low
- Design issues without fund loss
- Best-practice / clarity recs

## Automatic invalidators (union of strict rules)

Apply ANY rule that triggers, taking the strictest verdict:

| Category | Rules | Result |
|----------|-------|--------|
| **PoC** | No PoC AND finding cannot be clearly understood without one | INVALID |
| **PoC** | PoC doesn't compile or doesn't demonstrate impact | INVALID |
| **AI** | AI-generated finding without manual validation | INVALID + flag |
| **Severity** | Finding is Low / Informational and target program is competition-style | INVALID |
| **Scope** | Out-of-scope target | INVALID |
| **Scope** | Out-of-scope library root cause (not how in-scope code uses it) | INVALID |
| **Trust** | Admin direct misuse of privileges (reckless admin mistake) | QA / INVALID |
| **Trust** | Admin action that breaks code assumptions (covered by program design intent) | INVALID |
| **Quality** | Stale prices / round-completeness (except pull-based oracles) | INVALID |
| **Quality** | Future-opcode / CU repricing | INVALID |
| **Quality** | Sequencer / leader downtime / network liveness | INVALID |
| **Quality** | Chain re-org without attacker control | INVALID |
| **Tokens** | Non-standard tokens (unless mentioned). 6-18 decimals NOT weird | INVALID |
| **Theory** | Theoretical vulnerabilities without proof / impact | INVALID |
| **Self-harm** | Damage only to attacker themselves | INVALID |
| **Best-practice** | Recommendations without concrete impact | INVALID |
| **Optimizations** | Gas / CU / weight optimizations without fund loss | INVALID |
| **Naming** | Variable names, comments, NatSpec, doc-comments | INVALID |

## PoC requirements

**Treat as mandatory.** Even where the target platform technically allows PoC-less submissions, generic-mode applies the strictest interpretation.

A Stage-3 verdict of `exempt-N` (allowlist marker, no runnable PoC) results in a generic-mode `DOWNGRADE(refine)` automatically. The user must construct a runnable PoC before resubmitting.

## Quality signals

Apply Sherlock-style quantification AND Cantina-style Impact × Likelihood justification. Strictest signal wins:

| Signal | Standard | Threshold |
|--------|----------|-----------|
| Root cause | Clearly in-scope, mechanism named | Hard requirement |
| Impact × Likelihood | Both dimensions argued | Hard requirement (Cantina) |
| Loss quantification | >1%/$10 H, >0.01%/$10 M | Hard requirement (Sherlock) |
| PoC | Compiles + demonstrates | Hard requirement (generic-mode) |
| Attack path | Step-by-step with realistic conditions | Hard requirement |
| Severity alignment | Matches strictest tier | Hard requirement |

## Mode warning

When `program-mode = generic`, Stage 8 caps every SUBMIT finding's headline confidence at 75 (regardless of Stage 5 score) to surface that the analysis ran without a verified live source of truth. The user is responsible for re-validating against the actual program rules before submission.

## When to use generic-mode

- Bounty URL not supplied at Stage 1
- Bounty URL points at a self-hosted, unfamiliar page
- WebFetch fails twice on the bounty URL at Stage 6 start
- The user explicitly requests generic-mode

In all other cases, prefer the platform-specific criteria file.
