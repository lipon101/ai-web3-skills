# Generic Markdown — Report Template

Sensible default when the target platform is not in the bundled set, or the user wants a portable Markdown report. Optimized for human readability + AI-provenance disclosure.

## Format (per finding)

```markdown
# Title — root cause, names the affected component

**Severity**: Critical / High / Medium / Low / Informational
**Confidence**: <Argus Stage 8 confidence, 0-100>
**Affected**: `crate::module::function` — `crate/src/file.rs:LN-LN`

## Summary

<2-3 sentences: what's wrong, where, who's affected, what the impact is.>

## Root cause

<one paragraph identifying the underlying defect, not just the symptom. Cite specific lines.>

```rust
// crate/src/file.rs:LN-LN
<verbatim code excerpt>
```

## Exploit path

<numbered steps, concrete, citing either code lines or PoC operations. No English placeholders.>

1. <step — `crate/src/file.rs:LN`>
2. <step — PoC operation>
3. <step — observation>

## Impact

<concrete: who loses, how much, under what conditions. If the impact is bounded by a parameter or rate limit, state the bound.>

## Proof of concept

- **Tier (Argus)**: <1-4 or exempt-N>
- **PoC file**: `$RUN_DIR/3-poc/F-NN/poc.rs`
- **Reproduction**: see `$RUN_DIR/3-poc/F-NN/repro.md`

```rust
<inline PoC code excerpt — first ~30 lines>
```

Run:
```bash
<exact reproduction command>
```

Expected output (against buggy code):
```
<paste real output>
```

## Recommendation

<concrete code-level fix.>

```diff
- <buggy line(s)>
+ <fixed line(s)>
```

If the fix is multi-step, list every step with file:line.

## Validation summary (Argus pipeline trace)

| Stage | Verdict | Note |
|-------|---------|------|
| 2 — Audit angle | <which angle found it> | <brief> |
| 3 — PoC | ADVANCE / DOWNGRADE — tier <N> | <brief> |
| 4 — Adversarial Pass D | calibrated <severity> (divergence: <CONFIRMED / UPGRADED N-tier / DOWNGRADED N-tier>) | strongest surviving challenge: <name> |
| 5 — Platform | <if applicable> | |
| 6 — Program | <if applicable> | |
| 7 — Duplication | no hard duplicates | <brief> |

## AI-provenance disclosure

This finding was produced using Argus, a Rust-first AI audit pipeline. The author has:
- Manually re-read the cited code at the cited line numbers
- Independently re-derived the exploit path
- Run the PoC and confirmed the output matches the claim
- Verified the impact against the program's scope
- Rewritten this writeup in their own words

(Required disclosure for Cantina; recommended for all platforms.)
```

## Discipline rules

- **Severity is Argus Stage 4 Pass D calibrated value, after clamps.** If you want to deviate, justify the deviation in the writeup.
- **AI-provenance section is non-optional.** Even on platforms that don't require it, disclosure builds trust and matches modern submission norms.
- **Code citations always file:line.** Prose alone is not evidence.
- **Recommendation is concrete.** Diff-block fixes for small changes; numbered steps for multi-file fixes.

## Anti-patterns

- Skipping the AI-provenance section — looks like undisclosed AI output.
- Severity claims unsupported by the validation table.
- "It is recommended to consider implementing additional input validation" — generic advice; cite the specific check needed and where.
