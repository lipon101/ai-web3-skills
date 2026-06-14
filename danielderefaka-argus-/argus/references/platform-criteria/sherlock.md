# Sherlock — Competition — Judging Criteria

> Source: https://docs.sherlock.xyz/audits/judging/guidelines
> **Live page wins.**

## Severity definitions

Sherlock ONLY accepts **High** and **Medium**. Low and Informational are NOT rewarded. If finding is Low / Informational → INVALID.

### High
- Direct fund loss WITHOUT extensive external conditions
- Loss must be SIGNIFICANT:
  - Users lose >1% AND >$10 of principal
  - Users lose >1% AND >$10 of yield
  - Protocol loses >1% AND >$10 of fees

### Medium
- Fund loss requiring external conditions or specific states
- OR breaks CORE contract functionality
- Loss must be RELEVANT:
  - Users lose >0.01% AND >$10 of principal
  - Users lose >0.01% AND >$10 of yield
  - Protocol loses >0.01% AND >$10 of fees
- Note: if the attack repeats indefinitely with 0.01% per iteration → consider 100% loss

### DOS severity
- DOS Medium if: funds locked >1 week OR time-sensitive function affected
- DOS High if: BOTH conditions
- DOS <1 week → single occurrence; only valid if affects clearly time-sensitive function

**Likelihood is NOT considered in Sherlock. Only impact.**

## Automatic invalidators

| ID | Rule | Result |
|----|------|--------|
| AI-1 | Severity is Low / Informational | INVALID — Sherlock only pays H/M |
| AI-2 | Gas / CU / weight optimization without fund loss | INVALID |
| AI-3 | Event / log emitted with incorrect value (no on-chain impact) | INVALID |
| AI-4 | Zero / default-pubkey check | INVALID |
| AI-5 | User-input validation without significant loss to others | INVALID |
| AI-6 | Admin / authority incorrect call order | INVALID |
| AI-7 | Admin action that breaks assumptions (e.g. pausing collateral causes liquidations) | INVALID |
| AI-8 | Contract / Authority address blacklisting affects functionality | INVALID |
| AI-9 | Front-running initializers without irreversible damage or fund loss | INVALID |
| AI-10 | UX issue without fund loss | INVALID |
| AI-11 | User blacklisted by token, damage only to themselves | INVALID |
| AI-12 | Future opcode / CU repricing | INVALID |
| AI-13 | Accidental direct token transfer that only damages the user | INVALID |
| AI-14 | Loss of airdrops / rewards not part of original design | INVALID |
| AI-15 | Incorrect values in view / query functions (no impact on fund-handling) | INVALID — Low |
| AI-16 | Stale prices / Chainlink / Pyth round completeness — except pull-based oracles | INVALID |
| AI-17 | Finding in previous audit marked acknowledged / wontfix | INVALID |
| AI-18 | Chain re-org / network liveness | INVALID |
| AI-19 | Token unsafe-mint (recipient cannot accept due to unsupported impl) | INVALID |
| AI-20 | Future issues from integrations not mentioned in docs / README | INVALID |
| AI-21 | Non-standard / weird ERC-20 / CW20 / SPL Token (unless mentioned in README). Tokens with 6-18 decimals are NOT weird | INVALID |
| AI-22 | EVM / VM opcodes not working on the protocol's network | INVALID |
| AI-23 | Sequencer / leader downtime / misbehavior | INVALID |
| AI-24 | Design decision without fund loss | INVALID — Informational |
| AI-25 | Storage gaps in parent contracts (simple) | INVALID — Low |
| AI-26 | Front-running on chain with private mempool / Jito-style execution without explaining unintentional front-run | Downgrade: H→M, M→INVALID |
| AI-27 | Approval / ERC-20 / SPL race condition | INVALID |

## PoC requirements

PoC recommended but not strictly mandatory. Strongly recommended for:
- Complex attack paths
- Non-trivial input constraints
- Precision loss
- Re-entry (Solana CPI re-entry, CosmWasm submessage re-entry)
- CU / gas consumption / reverting calls

If finding does NOT include a PoC and CANNOT be clearly understood without one → INVALID.

## Quality signals

| Signal | Full credit | Partial / downgrade | Invalidation risk |
|--------|------------|---------------------|-------------------|
| Root cause | In-scope code, clearly identified | Symptom only | High |
| Loss quantification | Concrete math (>1%/$10 H, >0.01%/$10 M) | Loss claimed but unquantified | High — judges enforce thresholds |
| Attack path | Step-by-step or PoC | Partial | Moderate |
| External conditions | Stated and realistic | Unstated / unrealistic | High — extensive conditions downgrade H→M |
| Remediation | Present and correct | Wrong / missing | Low |
| Severity alignment | Matches Sherlock H/M only | Finding is Low/Info | Critical — auto-invalid |

Key emphasis:
- Quantify loss with real numbers. Judges check thresholds.
- Distinguish "no external conditions" (High) vs. "requires external conditions" (Medium).
- If attack is repeatable, state so. Repeatable 0.01% = 100% = potentially High.

## Source of truth

1. README (primary)
2. Code comments (overrideable by judge if outdated)
3. Default guidelines

Only README defines protocol invariants. Issues breaking README invariants can be Medium even if impact is low/unknown.

## Scope

- In-scope contract → all parents included
- Vulnerability in library used by in-scope → valid
- In-repo but out-of-scope → INVALID

## Duplicate rules

- Same root cause = duplicates, even across different contracts
- Fixing root cause makes both unexploitable

## Admin trust

- Admin functions assumed used correctly by default
- EXCEPTION: README defines explicit restrictions → bypassing them may be valid
- If admin UNKNOWINGLY causes issues → may be valid
- Internal protocol roles trusted by default; only untrusted if README says so OR user can obtain role without permission
