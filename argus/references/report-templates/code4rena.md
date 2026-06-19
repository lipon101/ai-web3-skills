# Code4rena — Report Template

> Source: https://docs.code4rena.com/competitions/submission-guidelines

## Format (per finding)

```markdown
# [H-N] / [M-N] / [L-N] Title — short, specific, names the root cause not the symptom

## Vulnerability Details

<one-paragraph technical description of the root cause: what the code does, what it should do, and why the divergence is exploitable. Quote the relevant code snippet with file:line citations.>

```rust
// crate/src/file.rs:LN-LN
<verbatim code excerpt showing the bug>
```

## Impact

<concrete, quantified impact. Who loses, how much, under what conditions. C4 High = direct asset loss; C4 Medium = indirect with stated assumptions. Match the severity claim to the impact described.>

## Tools Used

Manual review (Argus pipeline — Stage 2 angle: <which angle found it>; PoC tier <N>; Stage 4 calibrated severity: <severity>)

## Recommendations

<concrete code-level fix. Include a diff if the fix is small enough to fit:>

```diff
- <buggy line(s)>
+ <fixed line(s)>
```

<if the fix is multi-step or spans multiple files, list every step with file:line.>
```

## Discipline rules

- Title MUST start with `[H-N]` / `[M-N]` / `[L-N]` per C4 convention.
- Severity claim MUST match Argus Stage 4 Pass D calibrated severity (after clamps). If the user wants to deviate, surface the divergence as a writeup-time decision.
- Code snippets MUST quote with file:line. Generic references like "in the deposit function" without a line are insufficient.
- The `Tools Used` line MUST disclose Argus AI provenance — Code4rena allows AI-assisted findings but disclosure is good practice.
- The fix MUST address the root cause, not just the specific exploit path. If multiple instances of the same pattern exist, list them all.

## Anti-patterns

- Inflated severity (C4 invalidates inflated findings).
- Symptoms in the title ("function reverts unexpectedly" instead of "missing length check on user-supplied vec").
- "Theoretical" impact without a quantified loss path.
- Recommendations that go against the protocol's design philosophy.

## Sorting + IDs

When formatting multiple findings, assign IDs in severity order then submission order: H-1, H-2, M-1, M-2, L-1, L-2. Argus's F-NN IDs are internal; the C4 IDs are the user-facing ones in the formatted report.
