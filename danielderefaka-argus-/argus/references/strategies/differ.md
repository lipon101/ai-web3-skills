# Differ Strategy — cross-project comparison

> **Archetype**: Differ (WhiteHatMage guide § "Differ — the detective")
> **Introduced in**: v0.6.0
> **When triggered**: Known fork ancestry detected in Stage 1 OR user supplies `--reference <repo-url> [--reference-commit <sha>]` at Stage 0
> **Goal**: Find bugs caused by context loss during forking — missing checks, wrong constants, broken assumptions that were valid in the reference but not in the fork.

## The Differ insight

The WhiteHatMage guide describes the Differ as a hunter who "compares how a mechanism works in one project vs. another." The core observation: code is often copied from another project, and context gets lost during copying. The reference had a check that made sense in its context; the fork removed it because the context looked different — but the check was actually load-bearing.

Differ formalizes this: given a reference implementation (the "source of truth"), Differ:

1. Identifies every module that was copied or adapted from the reference
2. For each copied module, diffs structure and logic against the reference
3. Flags every deviation: missing checks, different constants, different error handling, different state transition ordering
4. For each deviation, asks: "Was this intentional adaptation, or did context get lost?"

## Pipeline modifications

### Pre-Stage 1: Reference acquisition

```
INPUT:  --reference <url> (user-supplied) OR auto-detected from fork-ancestry check in Stage 1
OPERATIONS:
  - Clone reference repo at the identified fork point (commit where the target diverged)
  - If user supplied --reference-commit <sha>, use that; otherwise use the fork-point commit
  - Extract the reference's attack surface (surface points 1-4 only — enough for comparison)
  - Build a module correspondence map: which files in the target correspond to which files in the reference
OUTPUT: $RUN_DIR/reference/ (cloned reference repo)
        $RUN_DIR/reference/module-map.md (correspondence)
```

### Stage 1 (reference-aware protocol map)

Full 6-step threat model, augmented with:

- **Module map**: For each module in the target, is there a corresponding module in the reference? What's the structural overlap?
- **Deviation inventory**: Quick surface-level comparison — different constant values, missing functions, added functions, different type signatures
- **Invariant comparison**: Does the reference state invariants that the target's docs don't? Does the target's code enforce them anyway or not?

### Stage 2: +Differ angle

All 10 standard angles run plus the Differ angle. The Differ angle:

1. Reads the module correspondence map
2. For each paired module, compares the implementations side-by-side
3. Produces FINDINGs for deviations where context appears lost

Full Differ angle methodology: `references/hacking-agents/differ-agent.md`.

### Differ-specific bug classes

| Class | Signal | Example |
|-------|--------|---------|
| **Missing check** | Check present in reference, absent in fork | Reference validates `amount <= max_supply - total_supply`; fork doesn't |
| **Divergent constant** | Same constant name, different value | `MAX_FEE_BPS = 500` in reference, `MAX_FEE_BPS = 1000` in fork — but downstream code assumes 500 |
| **Ordering change** | Operations in different order | Reference: `update_state(); transfer();` Fork: `transfer(); update_state();` — reentrancy window |
| **Removed error case** | Error variant removed but still possible | Reference handles `Error::InsufficentBalance`; fork removed it but the condition still occurs |
| **Type narrowing** | Type made stricter without handling | Reference: `amount: u64`; Fork: `amount: u32` — overflow on large inputs no longer caught |
| **Doc comment rot** | Comment from reference kept but code diverged | Reference comment says "reverts if X" but fork's code no longer checks X — reader assumes it does |
| **Missing dependency feature** | Reference uses a dependency feature the fork forgot to enable | Reference: `serde = { features = ["derive"] }`; Fork: `serde = "1.0"` without derive |
| **Untested adaptation** | Fork changed logic near a test but the test wasn't updated | Reference test covers `lock()` → fork added a state check in `lock()` but test still passes (doesn't test new check) |

### Stage 3-8

Same as Digger. Differ findings carry both the target's code reference AND the reference's code reference as a comparator.

## Differ + Digger interaction

Differ is normally a SUPPLEMENT, not a replacement. When both run:

1. Digger angles run first, producing their standard findings
2. Differ angle runs after, consuming the module map + Digger findings
3. Differ cross-references: for each Digger finding, does the reference have the same bug? If yes → the bug was inherited, not introduced. If no → the bug was introduced in the fork — higher severity (it was avoidable).
4. Dedup: if Differ finds the same root cause as a Digger angle, merge into one finding with the Differ analysis as additional evidence

## When Differ is the wrong choice

- **No fork ancestry**: If the target is an original implementation, Differ has nothing to compare against. Skip it.
- **Reference is unavailable**: If the reference repo is private, deleted, or in a different language, Differ can't run. Flag for manual comparison.
- **Too much divergence**: If >80% of modules have no clear correspondence, Differ produces mostly noise. Default to Digger.

## Differ output

Differ findings carry a `strategy: differ` metadata tag and a `reference: <url>@<sha>` field. Stage 8 surfaces:

> **Strategy note**: This run used the Differ supplement (cross-project comparison against `<reference>`). Differ findings flag deviations between the target and its reference implementation. Not every deviation is a bug — some are intentional adaptations. Deviations with missing checks, changed error handling, or type narrowing are the highest-priority for manual review.
