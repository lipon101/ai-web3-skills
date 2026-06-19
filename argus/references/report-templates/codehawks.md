# CodeHawks (incl. First Flights) — Report Template

> Source: https://docs.codehawks.com/

CodeHawks (Cyfrin) format is similar to Code4rena but with stricter title prefix discipline and a focus on First Flights' AI-judge auto-matching.

## Format (per finding)

```markdown
# [H-N] / [M-N] / [L-N] — Title that names the root cause precisely

## Summary

<1-2 sentence summary. The auto-judge (First Flights) does semantic matching on summaries — be specific about the location and mechanism, not just the symptom.>

## Vulnerability Details

<full technical description. Quote the affected code with file:line. The auto-judge looks for `crate::module::function` references and bug-class keywords.>

```rust
// crate/src/file.rs:LN-LN
<verbatim code excerpt>
```

## Impact

<concrete, specific impact. Who loses, how much, under what conditions.>

## Tools Used

Manual review.

## Recommendations

<concrete code-level fix.>

```diff
- <buggy line(s)>
+ <fixed line(s)>
```
```

## Discipline rules — First Flights AI-judge

The First Flights auto-judge does semantic matching against ground-truth findings. To maximize match probability:

- **Title MUST cite the affected function or invariant clearly.** "Withdraw uses cached balance" matches; "Vulnerability in withdraw flow" doesn't.
- **Bug-class keywords help**: "missing signer check", "unchecked arithmetic", "PDA confusion", "share inflation", "stale read", "re-entry", "replay" — use the standard names if they apply.
- **One root cause per submission.** If you bundle two distinct bugs into one report, the auto-judge may match only one of them and the other counts as missed.
- **The Summary field carries the most weight.** Lead with the precise mechanism in plain language.

## Discipline rules — competitive contests

For full CodeHawks competitions (not First Flights), human judges read the full Vulnerability Details and Impact sections. Optimize for clarity over brevity.

- Severity prefix `[H-N]` / `[M-N]` / `[L-N]` per Code4rena convention — CodeHawks judges follow C4-style discipline.
- Match severity to actual asset-loss impact: H = direct loss, M = indirect with assumptions, L = QA/style.

## Anti-patterns

- Vague titles like "logic error in claim function" — the auto-judge can't match these.
- Multiple bugs in one report — match only the strongest, the others miss.
- Severity claims unsupported by impact magnitude — both auto-judge and human judges discount.
- Pasting Argus output verbatim — the AI-provenance discipline applies. Rewrite in your own words.

## Cyfrin Updraft / First Flights specifics

If the target is a Cyfrin Updraft First Flight:

- The submission UI provides text fields for title, severity, summary, vulnerability details, recommendations, and code paths (file:line).
- The auto-judge runs after the contest ends and matches your submissions to a published ground-truth list.
- Reset & Try Again is allowed if you want to refine before final submission.

## Sorting + IDs

When formatting multiple findings, assign IDs in severity order: H-1, H-2, M-1, M-2, L-1. Argus's internal F-NN IDs map to CodeHawks `[H-N]` / `[M-N]` / `[L-N]` in the formatted output.
