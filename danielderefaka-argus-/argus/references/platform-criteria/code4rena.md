# Code4rena — Judging Criteria

> Source: https://docs.code4rena.com/competitions/judging-criteria
> Source: https://docs.code4rena.com/competitions/severity-categorization
> **Live page wins.** WebFetch the docs page at Stage 5 start; if it diverges from this file, follow the live page.

## Severity definitions

### High (3)
- Assets (funds, NFTs, data, authorization) can be **stolen / lost / compromised DIRECTLY**
- OR indirectly, but ONLY with a valid attack path — no hand-wavy hypotheticals
- Loss of matured yield at real amounts → High
- Loss of dust → QA/Low regardless

### Medium (2)
- Assets NOT at direct risk
- BUT function of protocol or availability is impacted
- OR leaks value with hypothetical attack path with STATED assumptions and external requirements
- Privilege escalation may be Medium depending on likelihood + impact
- Any privileged function scenario with reasonable assumptions → up to Medium

### QA / Low
- Assets not at risk
- State-handling issues
- Function incorrect as to spec
- Governance / centralization risk (admin privileges)
- Informational (code style, clarity, syntax, versioning, events)

## Automatic invalidators

| ID | Rule | Result |
|----|------|--------|
| AI-1 | Root cause is in an out-of-scope library (not in how the in-scope code uses it) | INVALID — OOS |
| AI-2 | Finding requires the user to make a mistake or enter wrong input | INVALID or QA |
| AI-3 | Non-standard / weird ERC-20 / CW20 / SPL Token, unless explicitly listed as supported in scope (USDC / USDT generally in scope on Code4rena Solidity audits; Rust audits depend on program scope) | INVALID |
| AI-4 | Admin / owner / authority direct misuse of privileges (reckless admin mistake) | QA — not Medium / High |
| AI-5 | Approve / delegate-authority front-run race condition | INVALID |
| AI-6 | Unused view function finding | QA / Low |
| AI-7 | Faulty event / log emission with no broader on-chain impact | Capped Low |
| AI-8 | Speculation on future code not in scope | INVALID unless root cause is demonstrably in scope |
| AI-9 | Loss of dust only (rounding errors, marginal fee variations) | QA / Low |
| AI-10 | Loss of unmatured yield or yield in motion | Capped Medium |
| AI-11 | Finding published in a prior audit report listed in README (acknowledged / wontfix) | OOS / Known issue |
| AI-12 | Phishing or improper user caution | INVALID |

## PoC requirements

PoC is **not strictly mandatory** on Code4rena, but strongly recommended.

A finding without a PoC can still be accepted if root cause and impact are clearly explained. However, a coded PoC significantly increases acceptance, especially for:
- Complex attack paths
- Precision loss or rounding issues
- Re-entry vectors (Solana CPI re-entry, CosmWasm submessage re-entry, SPL Token-2022 transfer-hook re-entry)
- Any finding where the burden of proof is non-trivial

A PoC that does not pass burden-of-proof → insufficient quality → grounds for downgrade or invalidation.

## Quality signals

| Signal | Full credit | Partial / downgrade | Invalidation risk |
|--------|------------|---------------------|-------------------|
| Root cause | Clearly identified | Missing or unclear | High — may invalidate |
| Maximum impact | Worst-case demonstrated with realistic numbers | Mentioned but not maximized | Moderate — downgrade likely |
| Attack path | Step-by-step from root cause to impact, or coded PoC | Hand-wavy or partial | High — insufficient quality |
| Code snippets | Relevant code referenced with line numbers | Generic references | Low — but weakens credibility |
| Remediation | Present and correct | Wrong or missing | Low — does not invalidate but loses credit |
| Severity alignment | Matches C4 definitions exactly | Inflated by 1 level | High — inflation heavily penalized |

Grounds for invalidation despite technical validity:
- Finding does not add value to the sponsor
- Finding appears to be a direct copy of another report in the same audit
- Severity is clearly and deliberately inflated

## Source of truth

1. Contest README and scope (primary)
2. Code comments
3. C4 default judging criteria

## Scope

- Root cause IN out-of-scope library → finding is OOS (INVALID)
- Root cause in how IN-SCOPE code incorrectly uses an OOS library → VALID
- Code not listed in scope → INVALID

## Duplicate rules

- Findings are duplicates if they share the same ROOT CAUSE
- Fixing root cause makes both unexploitable
- When similar exploits show different impacts → highest, most-irreversible impact used for scoring

## Centralization

- All privileged roles ASSUMED to be trustworthy
- Reckless admin mistakes → INVALID
- Direct misuse of privileges → QA only
- Mistakes in code only reachable through admin mistakes → QA only
- Privilege escalation → judged by likelihood + impact, up to Medium
