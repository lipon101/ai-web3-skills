# Immunefi — Report Template

> Source: https://immunefi.com/immunefi-vulnerability-severity-classification-system-v2-3/

## Format (per finding)

```markdown
# Title — root cause, names the in-scope impact category

## Severity

**Severity**: Critical / High / Medium / Low

**Mapped in-scope impact**: <quote the program's specific in-scope impact list entry, e.g. "Direct theft of user funds (at-rest or in-motion)" → Critical>

## Summary

<2-3 sentences. Include the affected contract / program ID and the entry point.>

## Vulnerability Details

<full technical description. Include the affected `crate::module::function` and `file:line`. Walk through the attack path step-by-step.>

```rust
// crate/src/file.rs:LN-LN
<verbatim code excerpt>
```

## Impact Details

<concrete, quantified impact matching the EXACT in-scope impact list. "Direct theft" is Critical. "Theft of unclaimed yield" is High. "Smart contract DoS" is Medium. Don't confuse them. Quote the program's published impact list and show how this finding matches.>

## Proof of Concept

> **MANDATORY — Immunefi rejects findings without a working PoC regardless of technical merit.**

PoC tier (Argus): <1-4>. File: `$RUN_DIR/3-poc/F-NN/poc.rs`

```rust
<inline PoC code>
```

Reproduction steps:
1. <step>
2. <step>
3. observe <expected output proving impact>

Expected output (against buggy code):
```
<paste real cargo test / anchor test output>
```

Expected output (against suggested fix):
```
<paste real output showing fix works>
```

## Recommended Mitigation

<concrete fix.>

```diff
- <buggy line(s)>
+ <fixed line(s)>
```

## Affected target

- **Program ID / contract address**: <if applicable, the deployed Solana program ID or CW contract address>
- **Repo / commit**: <github URL>@<commit SHA>
- **File**: `crate/src/file.rs:LN-LN`
```

## Discipline rules

- **PoC is mandatory at all severities.** No PoC = automatic rejection.
- **Match impact to the EXACT in-scope impact list** for the program. Each program can override the Immunefi defaults — Argus Stage 6 fetches the live bounty page; use that mapping.
- **Realistic preconditions only.** "Assumes infinite liquidity" / "assumes oracle is broken in a specific way Argus can't verify" → Stage 4 already downgraded; don't re-inflate at writeup time.
- **First reporter has priority** on duplicates. Submit promptly after manual validation.

## Anti-patterns

- "Theoretical" findings without realistic attack scenario (AI-37).
- Severity claimed at Critical for a Medium-impact issue. Immunefi judges check the impact list, not the report's severity claim.
- PoC that "would work like this" in English — Immunefi requires a runnable PoC.
- Findings dependent on out-of-scope assets — verify program scope before submitting.

## Program primacy

Immunefi programs override the default severity / impact lists. The formatted writeup MUST quote the program's specific impact list, not the generic Immunefi defaults. Argus Stage 6's `bounty-page.md` cache contains the program's in-scope impact mapping — use it.
