# Cantina — Report Template

> Source: https://docs.cantina.xyz/evaluations-and-standards/severity-classifications

> ⚠️ **AI-PROVENANCE GATE.** Cantina rule AI-3 bans unverified AI-generated findings. Argus's Stage 5 already enforces a manual-validation acknowledgment for Cantina targets. The formatted report here MUST reflect that the user has manually validated each finding — including re-reading the code, re-deriving the exploit, running the PoC, and rewriting in their own words.

## Format (per finding)

```markdown
# Title — root cause, no severity prefix (severity stated below)

## Severity

**Impact**: High / Medium / Low — <one sentence justifying the impact dimension>
**Likelihood**: High / Medium / Low — <one sentence justifying the likelihood dimension, with realistic preconditions>
**Severity (per Impact × Likelihood matrix)**: Critical / High / Medium / Low / Informational

| | Impact: High | Impact: Medium | Impact: Low |
|---|---|---|---|
| **Likelihood: High** | High | High | Medium |
| **Likelihood: Medium** | High | Medium | Low |
| **Likelihood: Low** | Medium | Low | Informational |

## Summary

<2-3 sentences.>

## Description

<full technical description with code citations.>

```rust
// crate/src/file.rs:LN-LN
<verbatim code excerpt>
```

## Proof of Concept

<runnable PoC — Cantina mandatory for H/M findings (researcher rep < 80) and recommended for all. Argus PoC tier <N>.>

```rust
// PoC content from $RUN_DIR/3-poc/F-NN/poc.rs
```

Reproduction:
- See `$RUN_DIR/3-poc/F-NN/repro.md`

## Recommendation

<concrete fix that aligns with the protocol's design philosophy. Cantina rule AI-9 caps at Informational if the fix contradicts protocol design.>

```diff
- <buggy line(s)>
+ <fixed line(s)>
```

---

**Manual validation acknowledgment**: I have manually re-read the cited code, independently re-derived the exploit path, run the PoC and confirmed the output, and rewritten this writeup in my own words. (Required for Cantina submissions per AI-3.)
```

## Discipline rules

- **Both Impact AND Likelihood MUST be argued.** A High-impact + Low-likelihood finding is Medium, not High. Don't anchor on the higher dimension.
- **PoC MUST compile and demonstrate the impact.** AI-8 invalidates PoCs that don't.
- **Recommendation MUST align with protocol design.** AI-9 caps at Informational if fix contradicts design philosophy.
- **AI provenance acknowledgment is mandatory.** Cantina enforces AI-3 aggressively.

## Anti-patterns

- Impact stated, likelihood assumed — Cantina judges recalculate severity if both dimensions aren't justified.
- PoC references in repo without inline code in the report.
- Fix that breaks the protocol's invariants in a different way.
- Submitting without manual validation — risk of disqualification + ban.
