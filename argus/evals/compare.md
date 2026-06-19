# Eval Compare

Compare an Argus run output against ground truth findings.

You will be given multiple files from a single benchmark run:

1. **Ground truth** — `{run_dir}/ground-truth.md` with the benchmark's known findings
2. **Argus submit** — `{run_dir}/8-final/submission-grade.md` (the SUBMIT bucket)
3. **Argus refine** — `{run_dir}/8-final/refine.md` (the REFINE bucket)
4. **Argus discard** — `{run_dir}/8-final/discard.md` (the DISCARD bucket)

## Steps

1. Read the ground truth file. Parse each `FINDING` line and its `description:` line. Note the `expect_in:` field if present (defaults to `submit`).
2. Read each Argus output file. Identify finding IDs (`F-NN`), titles, and `crate::module::function` locations.
3. For each ground truth finding, determine which bucket Argus placed it in. Use semantic matching — Argus doesn't need to use the exact same words, but must describe the same vulnerability in the same crate / module / function. Classify each as:
   - **CORRECT_SUBMIT** — appears in `submission-grade.md` with the same root cause AND `expect_in: submit`
   - **CORRECT_REFINE** — appears in `refine.md` AND `expect_in: refine`
   - **CORRECT_DISCARD** — appears in `discard.md` AND `expect_in: discard`
   - **OVER_GRADED** — appears in a stricter bucket than expected (e.g., expected `submit`, got `refine`)
   - **UNDER_GRADED** — appears in a looser bucket than expected (e.g., expected `discard`, got `submit`)
   - **MISSED** — not present in any of the three Argus output files

## Output

Write `summary.md` to the run directory with this exact format:

```markdown
## Eval Results — <benchmark-name>

| Metric | Value |
|--------|-------|
| Recall on submit-expected | {n} / {total} ({pct}%) |
| Recall on refine-expected | {n} / {total} ({pct}%) |
| Recall on discard-expected | {n} / {total} ({pct}%) |
| Over-graded (Argus too strict) | {count} |
| Under-graded (Argus too lax) | {count} |
| Missed | {count} |
| Argus SUBMIT count | {count from submission-grade.md} |
| Argus REFINE count | {count from refine.md} |
| Argus DISCARD count | {count from discard.md} |

### Severity-divergence pattern (Stage 4 Pass D)

| Direction | Count |
|-----------|-------|
| CONFIRMED | {n} |
| UPGRADED 1-tier | {n} |
| UPGRADED 2-tier | {n} |
| DOWNGRADED 1-tier | {n} |
| DOWNGRADED 2-tier | {n} |
| DOWNGRADED 3+-tier | {n} |

### Per-finding breakdown

| Status | Severity (gt) | ID (gt) | Crate.Module.Function | Bug Class | Argus bucket | Argus F-ID |
|--------|---------------|---------|------------------------|-----------|--------------|------------|
| CORRECT_SUBMIT | High | H-1 | crate::module::function | bug-class | submit | F-03 |
| OVER_GRADED | Medium | M-2 | crate::module::function | bug-class | refine | F-07 |
| MISSED | Medium | M-3 | crate::module::function | bug-class | — | — |
```

## Rules

- Match semantically, not by keyword grep. "Missing signer constraint on stake pool authority" matches "auth-missing-signer-on-pool-authority" even without identical words.
- A LEAD in `2-candidate-findings/leads.md` is NOT a finding for recall purposes — Argus explicitly didn't promote it. If a ground-truth finding only appears as a LEAD, mark it MISSED for recall but note "lead-only" in the breakdown.
- If Argus merges two ground-truth findings into one, count both as the merged bucket.
- The OVER_GRADED count tells you Argus is too strict on this codebase (kills real findings); UNDER_GRADED tells you Argus is too lax (promotes weak findings). Both should be tracked as separate metrics — neither is automatically a bug.
- A high MISSED count signals Stage 2 angle coverage gaps. Cross-reference MISSED findings against the 8 hacking angles to identify which angle should have caught it.
