# Watchman Strategy — upgrade diff monitoring

> **Archetype**: Watchman (WhiteHatMage guide § "Watchman — the sentinel")
> **Introduced in**: v0.6.0
> **When triggered**: Recent upgrade detected (< 14 days) OR user supplies `--prior-commit <sha>` at Stage 0
> **Goal**: Find bugs introduced by the upgrade itself — regressions, assumption breaks, and new attack surfaces in changed code.

## The Watchman insight

The WhiteHatMage guide describes a hunter who "monitors deployments and upgrades for diffs that enable previously-considered attack paths." The key case study: a small diff in a Scroll upgrade stood out because the hunter had already built a strong mental model of the codebase. The bug only existed in the diff.

Watchman formalizes this: given a prior commit (the "before" state) and the current commit (the "after" state), Watchman:

1. Computes the structural diff between the two states
2. Identifies every changed function, changed constant, changed dependency version
3. For each change, asks: "What assumption does this change, and what breaks if the old assumption was load-bearing?"
4. Applies the full angle set but ONLY to changed paths

## Pipeline modifications

### Pre-Stage 1: Diff computation

```
INPUT:  --prior-commit <sha> (user-supplied) OR auto-detected from git tags (most recent tag before current commit)
OPERATIONS:
  - git diff <prior-commit>..HEAD --stat → changed files
  - git diff <prior-commit>..HEAD -- <file> → changed functions per file
  - extract: added functions, removed functions, modified functions, changed constants, changed types/structs
  - classify each change: SIGNATURE_CHANGE (function signature), LOGIC_CHANGE (function body), CONST_CHANGE (constant value), TYPE_CHANGE (struct/enum), DEP_CHANGE (Cargo.toml version bump), REMOVED (deleted code)
OUTPUT: $RUN_DIR/watchman-diff.md
```

### Stage 1 (diff-aware protocol map)

Full 6-step threat model, but scoped to changed modules:

- **Actors**: Unchanged — the actor set rarely changes in upgrades
- **Trust boundaries**: Changed if new external calls added or old ones removed
- **Attack surface**: Full 10-point walk but ONLY for changed functions. A function unchanged since the prior commit is assumed to have the same surface.
- **Entry points**: New and modified entry points only
- **Invariants**: Flag invariants that TOUCH changed state variables — these are the ones the upgrade could break
- **Hot zones**: Changed files weighted 3×, callers of changed functions weighted 2×

### Stage 2 (scoped angle set)

All 10 angles run, but each angle's scope is restricted to the changed files + callers of changed functions. An angle analyzing a file untouched by the diff is wasting budget — the prior run already covered it.

Each angle prompt includes:
```
You are in Watchman mode. The following files and functions changed since the prior audit.
Focus ONLY on these changes and their downstream effects:
<diff-summary from watchman-diff.md>

For each changed function, ask:
1. What assumption does this change to the codebase?
2. What relied on the OLD behavior that might not hold after the NEW behavior?
3. Is the NEW behavior correct independently, or does it only make sense in the context of the OLD codebase?
```

### Diff-specific bug classes

Watchman angles prioritize diff-specific bug classes:

| Class | Signal | Example |
|-------|--------|---------|
| **Regression** | Removed check that was load-bearing | `require!(amount > 0)` removed; downstream code assumed non-zero |
| **Assumption break** | Changed constant that other code depends on | `MAX_VALIDATORS` doubled; array sizing in another module overflows |
| **Type width mismatch** | Changed type without updating consumers | `u32` → `u64` on a field; serialization in another crate reads `u32` |
| **New unchecked path** | Added function without auth checks | New `admin_set_fee()` without `require!(signer == authority)` |
| **Dependency drift** | Version bump in Cargo.toml | `ed25519-dalek 1.0` → `2.0`; signature verification API changed |
| **Dead code newly alive** | Old dead code path now reachable | Removed `#[cfg(feature = "unstable")]` guard; untested code now in production |
| **Side-effect addition** | New state write in a read-assumed function | `total_supply()` now also updates `last_access_ts`; breaks read-only assumption |

### Stage 3-8

Same as Digger. Changed paths get full PoC treatment. The scope restriction in Stage 2 means fewer findings to verify, so the pipeline runs faster despite full later-stage treatment.

## Watchman + prior Argus run

When the user has a prior Argus run at the prior commit:

1. Load `$PRIOR_RUN_DIR/8-final/submission-grade.md` — these were the findings at the prior commit
2. For each prior finding: check if the diff fixes, breaks, or is orthogonal to the finding
3. Findings fixed by the diff → note as "PRIOR-FIXED" in Stage 8 output
4. Findings worsened by the diff → flag as regression candidates
5. Findings orthogonal to the diff → carry forward as still-valid (if they survived all gates in the prior run)

This gives Watchman a unique advantage: it knows what was already confirmed at the prior commit and can focus entirely on what changed.

## Watchman output

Watchman findings carry a `strategy: watchman` metadata tag. Stage 8 surfaces:

> **Strategy note**: This run used the Watchman strategy (upgrade diff monitoring). Findings are scoped to changes since `<prior-commit>`. Unchanged code was not re-analyzed. For comprehensive coverage of the full codebase, re-run with the Digger strategy.

## Limitations

- Watchman assumes the prior commit was correctly audited. If it wasn't, bugs in unchanged code are invisible.
- Large diffs (>50% of codebase changed) defeat Watchman's efficiency advantage. If the diff is that large, default to Digger.
- Dependency version bumps are flagged but not deeply analyzed (that's the Differ angle's job to compare the dependency's source). Flag them for manual review.
