# Sherlock — Report Template

> Source: https://docs.sherlock.xyz/audits/judging/guidelines

## Format (per finding)

```markdown
# Title — names the root cause, severity-claim-implicit

## Summary

<2-3 sentence summary: what's wrong, where, who's affected.>

## Vulnerability Detail

<full technical description. Include the affected function and line numbers. Walk through the attack path step-by-step. Sherlock judges read this section first.>

```rust
// crate/src/file.rs:LN-LN
<verbatim code excerpt>
```

## Impact

<MUST quantify against Sherlock's thresholds:
- High: >1% AND >$10 of principal / yield / fees
- Medium: >0.01% AND >$10 of principal / yield / fees

Show the math with realistic numbers. If the attack is repeatable, state so explicitly — Sherlock treats repeatable 0.01% as 100% loss.>

## Code Snippet

<file:line reference, optionally with a permalink to the GitHub source at the audited commit.>

`crate/src/file.rs:LN-LN`

## Tool used

Manual review (Argus pipeline — Stage 2 angle: <which angle>; PoC tier <N>; Stage 4 calibrated: <severity>; AI-provenance: manual validation completed before submission)

## Recommendation

<concrete fix.>

```diff
- <buggy line(s)>
+ <fixed line(s)>
```
```

## Discipline rules

- **Severity is encoded in impact quantification, not the title.** Sherlock only pays H/M; if Argus calibrated to L/I, do NOT submit unless the writeup can credibly argue for M+.
- **Likelihood is NOT considered.** Don't argue likelihood; argue impact magnitude.
- **README is source of truth.** If this finding contradicts something documented in the README, the README wins unless the finding shows a code bug independent of the documented behavior.
- **External conditions matter for tier.** "Without extensive external conditions" → High; "with external conditions" → Medium. State which.
- **Repeatability moves the tier.** If 0.01% per call repeatable indefinitely, claim High with the repeatability argument explicit.

## Anti-patterns

- Loss claimed but not quantified — Sherlock judges enforce thresholds strictly.
- Findings that are actually Low/Informational under Sherlock's H/M-only model — submit only if the impact actually crosses the M threshold.
- Admin-action-breaks-assumptions findings (AI-7) — Sherlock invalidates these unless the README defines explicit admin restrictions that the finding bypasses.
