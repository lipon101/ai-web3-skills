# Finding Validation

## FP Gate

A finding must pass all three checks before it can be reported.

### 1. Concrete Exploit Path

You must be able to explain:

- who triggers the path
- which entry point is used
- which state changes matter
- what invariant breaks
- what user or protocol impact follows

### 2. Reachable Entry

The attack path must be reachable in the actual trust model.

Check:

- modifiers
- role checks
- caller restrictions
- governance or timelock constraints
- initialization state

### 3. No Existing Guard

Drop the finding if an existing control already blocks it:

- validation checks
- replay protection
- accounting bounds
- reentrancy guards
- pause checks
- sequencing guarantees

### 4. Operational Feasibility

For liveness or complexity findings, you must also explain:

- which execution path fails in practice
- why the required gas, callback budget, or operational assumption is unrealistic
- why failure leaves funds, state, or control flow stuck or unsafe

## Confidence

Confidence measures how certain the finding is real and exploitable.

Start at `100` and deduct as needed:

- privileged caller required: `-25`
- attack path partially inferred: `-20`
- impact is narrow or self-contained: `-15`
- dependency behavior assumption is material but unverified: `-10`
- chain or provider feasibility assumption is material but unverified: `-10`

## Severity

Severity measures impact, not certainty.

Suggested buckets:

- `CRITICAL`
- `HIGH`
- `MEDIUM`
- `LOW`

## Do Not Report

Do not report:

- style or readability issues
- gas-only notes
- missing comments or events
- centralization observations without a concrete exploit path
- broad worries without a broken invariant
- self-harm only flows with no protocol spillover

Do not drop a finding only because it is gas-related if the gas issue breaks liveness of a critical path.

## Merge Rule

If two findings share the same root cause:

- keep the higher-confidence version
- preserve wider scope if the evidence is equally strong
- note composability only when the interaction is concrete
