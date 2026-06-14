# W3SA + Scout Eval Runner — empirical Rust-chain calibration

Runs Argus against the two public labeled Rust-chain finding datasets that exist (as of v0.2.6) and produces calibration metrics the C4-historical-severity heuristic + Stage 5 scoring weights + confidence-model deductions can be tuned against.

## Status

**Stub — not yet runnable end-to-end.** This file documents the dataset shape, the comparison procedure, and what gets recorded. Wire-up to fetch the datasets and execute requires per-dataset adapters (W3SA HF dataset format ≠ benchmark frontmatter format used by `runner.md`).

## Why these datasets

The empirical-corpus gap for Rust-chain audit findings is documented in `ARGUS_PLAYBOOK.md` §14. The two datasets below are the closest available ground truth:

| Dataset | Source | Projects | Findings | Ecosystem | URL |
|---------|--------|---------:|---------:|-----------|-----|
| **W3SA Solana Benchmark** | Hugging Face (`almanax/w3sa-bm-solana`) | 7 | 42 audit bugs + 19 injected | Anchor / Solana | `huggingface.co/datasets/almanax/w3sa-bm-solana` |
| **Scout Substrate Dataset** | Polkadot Alliance Legion (LAFHIS / UBA) | varies | audit reports + mapped issues + remediated code | Substrate / FRAME | `forum.polkadot.network/t/learning-from-audit-findings-to-scout-with-llms/10834` |

Each carries severity labels and (W3SA) detection rates already computed for GPT-4o / Claude-3.5 / o1-mini. Argus's per-stage outputs can be compared to those numbers to anchor calibration.

## W3SA project list (Anchor / Solana)

- Invariant
- Ellipsis Labs
- Synthetify
- Clone
- Haven
- Drift
- Port Sundial

Each project ships ground-truth in W3SA's schema: `(project, file, line, vulnerability_class, severity, injected: bool)`.

## Adapter (TODO)

Convert W3SA's HF parquet rows to Argus benchmark frontmatter format so `runner.md`'s loop consumes them. Sketch:

```python
# scripts/w3sa-adapter.py (to be written)
# For each W3SA project:
#   1. clone the source repo at the project's pinned commit
#   2. emit evals/benchmarks/w3sa-<project>.md with:
#        ---
#        repo_url: <project URL>
#        repo_ref: <pinned commit>
#        project_path: <Cargo workspace member>
#        project_shape: anchor
#        bounty_url: none
#        target_repo: <project URL>
#        ground_truth_source: w3sa
#        ---
#      followed by per-finding FINDING lines from the parquet
```

## Scout adapter (TODO)

Polkadot Alliance Legion publishes the dataset via forum-linked Git LFS. Adapter:

```python
# scripts/scout-adapter.py (to be written)
# 1. Clone the Scout dataset repo
# 2. For each pallet finding: emit evals/benchmarks/scout-<pallet>-<id>.md
# 3. project_shape: substrate; ground_truth_source: scout
```

## Run

Once adapters exist, the existing `evals/runner.md` loop handles execution. The differentiator is the **comparison step**:

```bash
# Override comparison in evals/compare.md to also emit per-stage metrics:
#   - Stage 2: recall@k for k ∈ {findings_in_SUBMIT, findings_in_SUBMIT+REFINE}
#   - Stage 3: PoC-tier distribution vs ground-truth severity
#   - Stage 4 Pass D: severity-calibration confusion matrix (Argus vs ground truth)
#   - Stage 5: score distribution vs ground-truth-judged-valid
#   - Stage 8: SUBMIT-bucket precision (TP / (TP + FP))
```

Compare against W3SA's published per-model detection rates:

| Model | W3SA recall |
|-------|-------------|
| GPT-4o | (published in HF README) |
| Claude-3.5 Sonnet | (published) |
| o1-mini | (published) |
| **Argus (target)** | TBD — first run will set baseline |

## What this calibrates

The current Argus heuristics tuned without empirical ground truth (and the tighter ones that should be revisited once W3SA + Scout numbers are in):

| Heuristic | File | Currently calibrated against |
|-----------|------|------------------------------|
| **C4 historical-severity heuristic** (7 bug-shapes default to Medium) | `references/adversarial-review.md` Pass D | swafe (2/7 → 6/7) + Reflector (1/2 over-grade) = ~10 data points |
| **80% Stage 3 certainty floor** | `references/poc-standards.md` | hand-set; never measured |
| **Stage 5 subtractive scoring deductions** | `references/platform-validation.md` | hand-set; never measured |
| **Confidence-model deductions** (-20 partial path, -25 unverified external claim, etc.) | `references/hacking-agents/shared-rules.md` | hand-set; never measured |
| **Phase 8a-pre dedupe overlap thresholds** (0.5 / 0.3 / 0.15) | `references/output-format.md` | lowered v0.1.6 from one swafe data point |

A W3SA + Scout run produces enough data points to either confirm or shift each of these. v0.2.x roadmap calls this the "empirical calibration pass."

## Output schema

For each benchmark run, in addition to the standard `summary.md`, emit `calibration.md`:

```markdown
# Calibration metrics — <project> @ <timestamp>-<commit>

## Severity calibration confusion matrix

|              | GT: Critical | GT: High | GT: Medium | GT: Low |
|--------------|--------------|----------|------------|---------|
| Argus: Critical | <n> | <n> | <n> | <n> |
| Argus: High     | <n> | <n> | <n> | <n> |
| Argus: Medium   | <n> | <n> | <n> | <n> |
| Argus: Low      | <n> | <n> | <n> | <n> |
| Argus: missed   | <n> | <n> | <n> | <n> |

## Stage-3 PoC tier distribution by ground-truth severity

| GT severity | Tier 1 | Tier 2 | Tier 3 | Tier 4 | exempt | DOWNGRADE(refine) |
|-------------|-------:|-------:|-------:|-------:|-------:|------------------:|
| Critical | | | | | | |
| High     | | | | | | |
| Medium   | | | | | | |
| Low      | | | | | | |

## Stage-5 score distribution by Stage-8 outcome

| Stage 8 outcome | n | mean(stage5_score) | median |
|-----------------|---:|-------------------:|-------:|
| SUBMIT  | | | |
| REFINE  | | | |
| DISCARD | | | |

## Calibration deltas (recommended adjustments)

<For each heuristic flagged misaligned, write a 2-3 sentence proposed adjustment with the data backing it.>
```

## Caveats

- **W3SA's 19 injected bugs** are synthetic and may skew distribution toward easier-to-find patterns. Report metrics with and without injected bugs.
- **Single-run variance**: LLM output is non-deterministic. Run each benchmark ≥3 times and use median for headline metrics; report the spread.
- **Scope drift**: W3SA's pinned commits may differ from Argus's `Stage 6` "applicable commit" semantics. Force `bounty_url: none` so Stage 6 runs in generic mode; the comparison stays apples-to-apples with W3SA's no-bounty assumption.
- **Severity-label mismatch**: W3SA uses a single severity per finding; Argus tracks both `claimed_severity` (Stage 2) and `final_severity` (Pass D). Compare against `final_severity` for the headline metric; surface divergence as a separate column.

## References

- W3SA dataset: `huggingface.co/datasets/almanax/w3sa-bm-solana`
- Scout dataset: `forum.polkadot.network/t/learning-from-audit-findings-to-scout-with-llms/10834`
- Empirical-corpus gap analysis: `ARGUS_PLAYBOOK.md` §14 (acknowledged open gaps).
