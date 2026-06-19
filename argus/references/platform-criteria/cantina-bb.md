# Cantina — Bug Bounty — Judging Criteria

> Source: https://docs.cantina.xyz/evaluations-and-standards/severity-classifications/competition-finding-severity
> **Live page wins.**

## Severity — Impact × Likelihood matrix (same as Competition)

|  | Impact: High | Impact: Medium | Impact: Low |
|---|---|---|---|
| **Likelihood: High** | High | High | Medium |
| **Likelihood: Medium** | High | Medium | Low |
| **Likelihood: Low** | Medium | Low | Informational |

Tiebreak: protocol catastrophic if not fixed and triggerable by anyone → very likely High. Protocol functions fine without fix → likely Low.

## Automatic invalidators

| ID | Rule | Result |
|----|------|--------|
| AI-1 | User error manageable from frontend | Informational at most |
| AI-2 | Requires admin access (unless protocol designed to be resilient) | Low at most |
| AI-3 | **AI-generated finding without manual validation** | INVALID + risk of ban |
| AI-4 | Approval / race condition | INVALID |
| AI-5 | Non-standard tokens (unless in program scope) | Low at most |
| AI-6 | Dust / rounding | Low at most |
| AI-7 | Acknowledged in previous report | INVALID |
| AI-8 | PoC doesn't compile or demonstrate impact | INVALID |
| AI-9 | Suggested fix against protocol design | Informational at most |

## ⚠️ AI-generated content policy

Same as Cantina Competition. **Argus is AI tooling. Manual validation required before submission.**

Stage 5 enforces a manual-validation acknowledgment gate when the platform target is Cantina (BB or Competition). See `platform-validation.md`.

## PoC requirements

There is no universal mandatory PoC rule for Cantina BB like in competitions. However:
- Coded PoC that compiles and demonstrates impact significantly increases acceptance
- PoC that doesn't compile / demonstrate → INVALID (AI-8)
- Findings must contribute to significant security changes

For practical purposes, always include a PoC. A finding without one is much harder to accept.

## Quality signals

| Signal | Full credit | Partial / downgrade | Invalidation risk |
|--------|------------|---------------------|-------------------|
| Root cause | In-scope code, clearly identified | Symptom only | High |
| Impact × Likelihood | Both argued with evidence | Only impact | High |
| PoC | Compiles, executes, demonstrates | Doesn't fully prove | Moderate |
| Attack path | Step-by-step with realistic conditions | Partial | Moderate |
| Remediation | Aligned with protocol design | Against design | Moderate |
| Severity alignment | Matches matrix | Misaligned | High |

Key emphasis:
- MUST justify Impact AND Likelihood explicitly. The matrix determines severity, not intuition.
- Even though PoC not universally mandatory for BB, finding without one is much weaker.
- Fix against design → entire finding capped Informational.
- AI-generated without manual validation → disqualification + potential ban. Enforced aggressively.

## Source of truth

The specific BB program defines its own in-scope impacts. README is the primary reference for protocol behavior.

## Scope

- In-scope → parents included
- Library used by in-scope → valid
- Out-of-scope → INVALID

## Duplicate rules

- Same root cause = duplicates
- Fixing root cause makes both unexploitable
