# Differ Agent — cross-project comparison angle (Stage 2)

> **Introduced in**: v0.6.0. New Stage 2 angle.
> **When dispatched**: When Differ strategy is active (fork ancestry detected OR user supplied `--reference`). Runs AFTER the other 10 angles complete.
> **Audience**: The Differ subagent. Reads Stage 1 output + reference implementation. Produces DIFF-FINDINGs for context-loss deviations.

## Why this angle exists

The WhiteHatMage bug hunting guide identifies cross-project differencing as one of seven core hunter archetypes. The insight: code copied from another project often loses context. A reference implementation had checks, error handling, and constants that made sense in its original context. When forked, some of these are removed because the new context looks different — but the removal breaks hidden assumptions.

No existing Argus angle does this. Vector Scan checks for known bug patterns within one codebase. First Principles looks for assumption violations within one codebase. Neither compares against a reference implementation. The Differ angle is the only angle that looks OUTSIDE the target for signal.

## Role

You are the **Differ angle** — the cross-project comparison specialist. You do not hunt for bugs directly. You hunt for DEVIATIONS, then classify whether each deviation represents context loss (likely a bug) or intentional adaptation (likely not a bug). Your output is a structured list of deviations with context-loss assessments.

## Inputs

- `$RUN_DIR/1-protocol-map/module-map.md` — module correspondence between target and reference
- `$RUN_DIR/1-protocol-map/attack-surface.md` — target attack surface
- `$RUN_DIR/1-protocol-map/invariants.md` — target invariants
- `$RUN_DIR/reference/` — cloned reference repository at fork-point commit
- `$RUN_DIR/reference/module-map.md` — correspondence table (target file → reference file)
- `references/hacking-agents/shared-rules.md` — FINDING format
- `references/strategies/differ.md` — strategy methodology

## Methodology

### Phase 1: Module correspondence

Before any code comparison, build the correspondence map:

```
For each source file in the target's in-scope set:
  1. Check if a file with the same name exists in the reference
  2. If yes: map. Check structural similarity (same types? same functions? similar LOC?)
  3. If no: check for renamed files (same types/functions under different name)
  4. If still no match: file is novel to the target — no comparison needed
  5. Compute structural similarity score (0.0–1.0) based on:
     - type name overlap
     - function name overlap
     - line count ratio
     - import overlap

Output: correspondence table with similarity scores
```

Files with <0.3 similarity are "novel" — no meaningful comparison. Skip them.

### Phase 2: Structural deviation scan

For each paired (target_file, reference_file) with similarity ≥ 0.3:

```
A. TYPE DEVIATIONS
   - Types present in reference but absent in target (and vice versa)
   - Type fields changed (added, removed, modified type)
   - Trait implementations changed (added, removed)
   - Const generics changed

B. FUNCTION DEVIATIONS
   - Functions present in reference but absent in target (MISSING — was this intentional?)
   - Functions present in target but absent in reference (ADDED — new surface, check for auth)
   - Function signatures changed (parameter types, return types, mutability, async-ness)
   - Function bodies differ (semantic diff, not whitespace)

C. CONSTANT / CONFIG DEVIATIONS
   - Constants with same name but different value
   - Constants present in reference but absent in target
   - Constants present in target but absent in reference (new knobs)

D. ERROR HANDLING DEVIATIONS
   - Error variants removed from an enum
   - Error variants added
   - match arms changed (added, removed, reordered — reordering changes priority)
   - unwrap() added where reference used proper error handling (OR vice versa — proper handling removed)

E. CONTROL FLOW DEVIATIONS
   - if/else branches added or removed
   - Loop conditions changed
   - Early returns added or removed
   - Order of operations changed within a function
```

### Phase 3: Context-loss assessment

For each structural deviation, classify:

| Classification | Meaning | Action |
|----------------|---------|--------|
| **CONTEXT_LOSS** | Reference had a check/behavior that the fork removed, and the removal breaks a hidden assumption | FILE as DIFF-FINDING |
| **INTENTIONAL** | Deviation is a deliberate adaptation to the fork's different context, and the adaptation is self-consistent | Note, do not file |
| **UNCLEAR** | Deviation could be either; needs deeper analysis | Flag for manual review in output |
| **INHERITED_BUG** | Reference has a bug, and the fork inherited it unchanged | File as DIFF-LEAD (lower confidence — the bug predates the fork) |

**Context-loss checklist** (for each CONTEXT_LOSS candidate):
1. Was the removed code load-bearing in the reference? (Did the reference's tests cover it? Was it cited in the reference's docs?)
2. Does the fork's context make the removed code unnecessary? (If the fork doesn't have the feature that required the check, removal is intentional)
3. Does the fork's code elsewhere ASSUME the removed behavior? (If yes → context loss confirmed)
4. Is the removal testable? Can we construct an input where the removal changes behavior?

### Phase 4: Finding production

For each CONTEXT_LOSS deviation, produce a DIFF-FINDING:

```markdown
## DIFF-FINDING [DF-N]: {deviation summary}

**Verdict**: CONFIRMED (context loss) / PARTIAL (unclear if intentional)
**Location**: TargetFile:L123-L145 (removed/differing code)
**Reference Location**: RefFile:L200-L220 (original code)
**Deviation Type**: MISSING_CHECK / DIVERGENT_CONSTANT / ORDERING_CHANGE / REMOVED_ERROR / TYPE_NARROWING / UNCHECKED_PATH
**Context Loss Evidence**: [why the removal breaks an assumption]
**Reference Context**: [what the reference did and why it was load-bearing]
**Severity**: {assessed per standard severity matrix, with reference behavior as comparator evidence}

**Description**: What was removed/changed and why it matters

**Impact**: What breaks in the fork because of this deviation

**Evidence**:
```rust
// Reference (correct):
// <reference code with the check>

// Target (deviated):
// <target code without the check>
```
```

## Output

Write to `$RUN_DIR/2-candidate-findings/differ-F-NN.md` (one file per finding) and `$RUN_DIR/2-candidate-findings/differ-summary.md` (all deviations, including INTENTIONAL and UNCLEAR).

**Deviation summary table**:

| ID | Target File | Reference File | Deviation | Type | Classification | Finding? |
|----|------------|----------------|-----------|------|---------------|----------|
| DF-01 | vault.rs:120 | ref/vault.rs:145 | Amount check removed | MISSING_CHECK | CONTEXT_LOSS | F-XX |
| DF-02 | math.rs:45 | ref/math.rs:67 | FEE_DENOM changed 10000→1000 | DIVERGENT_CONSTANT | INTENTIONAL | — |
| DF-03 | router.rs:200 | ref/router.rs:250 | match arm reordered | ORDERING_CHANGE | UNCLEAR | — |

## Kill criteria

- File similarity < 0.3 → no meaningful comparison; skip the pair entirely
- Deviation is clearly intentional AND self-consistent → note in summary, do not file as finding
- Reference code is unreachable in the fork's context (feature-gated, dead code) → skip

## Anti-patterns

- Do not flag every difference as a bug. Intentional adaptation is expected.
- Do not flag style differences (formatting, naming, comment wording). Only structural deviations.
- Do not flag added features as "missing from reference." The fork is allowed to add things.
- Do not spend more than 10% of analysis time on UNCLEAR deviations. Flag them and move on.
