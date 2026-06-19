# Release Gates — convergence vs. divergence diagnostics

**Driving signal**: ChatGPT Deep Thinking (extended-reasoning external review, 2026-05-09) explicitly warned that Argus's catalogue-growth strategy is **converging as a prior, diverging as a verdict engine**. The system can keep adding named contest-pattern vectors and treat exact-pattern retrieval as evidence of quality — but that drifts into benchmark-shaped overfitting. The fact pattern of v0.1.12's SP1 run (4 exact matches on calibrated items, 0 on clean ones) is the early-warning signature of that drift.

This file defines the **release gates** that distinguish convergence (the catalogue is asymptotically covering real attack patterns) from divergence (the catalogue is encoding more historical aliases for the same retrieval failure).

## The four diagnostic tests

Every Argus minor-version release MUST report these four buckets separately. Top-line "direct recall" without this breakdown is misleading.

### Test 1 — Family hold-out

Split the eval corpus by **latent violated invariant**, not by contest or repo. If a release was calibrated on examples of `vk_root binding` (V98), `dead-code fallback` (V101), `cost-table mismatch` (V102) — hold out the entire **family**, not just the specific contest.

Run Argus on contests that touch unseen-invariant families. Report direct recall on the held-out families separately from the calibrated families.

**Convergence signal**: held-out direct recall rises over time with each release.
**Divergence signal**: calibrated direct recall rises; held-out flat or falling.

### Test 2 — Time-split

Freeze the catalogue + profile state at date T. Run only against contests / findings disclosed AFTER T. This is what LiveCodeBench does for code-reasoning models — no benchmark contamination because the data didn't exist when the model was trained.

For Argus, T is the date of the most-recent VERSION bump. Eval corpus is contests published after T.

**Convergence signal**: post-T direct recall is comparable to pre-T calibrated recall.
**Divergence signal**: post-T direct recall is much lower than pre-T calibrated recall.

### Test 3 — Name-blind

Strip named pattern labels from `references/rust-protocol-types.md` (e.g., remove "SP1 M-01..M-06 patterns" by-name references) and `references/attack-vectors/rust-attack-vectors.md` (remove "Solves SP1 M-XX" / "Solves Reflector M-YY" annotations). Replace with invariant-only descriptions. Re-run on the same eval corpus.

**Convergence signal**: name-blind recall is comparable to named-recall (the catalogue is reasoning from invariants, not labels).
**Divergence signal**: name-blind recall collapses (the catalogue is matching on memorized labels).

### Test 4 — Semantic perturbation robustness

Take known-positive findings and apply semantics-preserving rewrites:
- Helper extraction (move logic to a sub-function)
- Variable renaming (`vk_root` → `verifying_root_hash`)
- Guard inversion (`if !x` → `if x { ... } else { return Err }`)
- Reordering of independent statements
- Conditional refactoring (match → if/else chain)

Re-run Argus. Direct recall should remain stable.

**Convergence signal**: perturbation-stable recall ≥ 80% of un-perturbed recall.
**Divergence signal**: perturbation-stable recall drops > 30%.

ChatGPT cites recent vulnerability-reasoning research showing 26.7% average reasoning drop under semantics-preserving perturbations; Argus must do better than that.

## Per-release report format

Every release notes section in CHANGELOG.md MUST include:

```markdown
## Release-gate evaluation — v0.X.Y

| Test | Metric | Value | Threshold | Pass? |
|------|--------|-------|-----------|-------|
| Family hold-out | Direct recall on unseen-family | <N>% | ≥ 25% | yes/no |
| Time-split | Direct recall on post-cutoff contests | <N>% | ≥ 25% | yes/no |
| Name-blind | Direct recall with labels stripped / un-stripped | <N>% / <M>% (delta <D>%) | delta ≤ 15% | yes/no |
| Perturbation-stable | Recall on perturbed corpus / un-perturbed | <N>% / <M>% (delta <D>%) | delta ≤ 25% | yes/no |

**Primary KPI**: post-cut-off unseen-family witness recall.
**Release-blocking gates**: name-blind delta and perturbation-stable delta.
```

A release that passes the calibrated benchmark but FAILS the name-blind or perturbation-stable gate is **not** shipped. It is a memorization regression.

## Bucket separation in `_argus-vs-c4-comparison.md`

Every contest comparison report (the kind produced for the SP1 run) MUST report direct recall in four sub-buckets:

1. **Calibrated families × familiar domains** (e.g., SP1 ZK patterns Argus's v0.1.12 ZK profile literally lists). Expected: high recall, but treat as memorization not generalization.
2. **Unseen families × familiar domains** (e.g., a NEW Solana DeFi pattern that v0.1.12 doesn't list, but the project is Solana-Anchor which Argus is calibrated for).
3. **Unseen families × unfamiliar domains** (e.g., a NEW pattern in a project ecosystem Argus has minimal calibration for, like Substrate pallets which have <25 findings in the corpus).
4. **Post-cut-off fresh contests** (date AFTER current release VERSION).

The honest direct-recall-on-novel-targets headline number is bucket 4. Bucket 1 is interesting only as a sanity check that the calibration set is recoverable.

## Drift indicator (cheap, runs every release)

ChatGPT cites contamination-detection work showing that **output-distribution peakedness** is a tell for memorization. When the model is over-certain on familiar bug stories it produces sharply-peaked confidence distributions; on held-out families the distributions are diffuse.

Argus's per-release diagnostic should plot:

```
Confidence distribution histogram for SUBMIT-bucket findings:
- on calibrated families: <histogram>
- on held-out families: <histogram>
```

If both histograms are peaked at high confidence, that's healthy. If only the calibrated-family histogram is peaked while the held-out histogram is diffuse, that's the memorization smell — log a warning in CHANGELOG and require investigation before shipping.

## When to admit the architectural ceiling

ChatGPT's hardest pushback: "if after v0.2.0 + v0.2.1 + v0.2.2 the clean-target direct recall is still ≤30%, the architectural ceiling is real." Argus's role is then triage-not-replacement.

Argus commits to:
- After v0.3.0, if bucket-4 direct recall < 30% on a fresh contest, **the README and Stage 8 final terminal print MUST explicitly state**: "Argus is a triage tool. It surfaces ~85% of contest findings as some level of signal but produces only ~30% as ready-to-submit. Manual review of the LEAD bucket is the user's responsibility."
- This isn't a failure mode; it's an honest framing. The 87.5% adjacent recall is genuinely useful — the user gets a curated list of code surfaces × bug classes worth investigating.

The release gates above are how Argus knows whether to keep iterating or to formally re-scope.

## Process

For every release:

1. **Pre-release**: run all 4 tests on the v0.X.Y candidate.
2. **Gate check**: if name-blind or perturbation-stable thresholds fail, do not ship; iterate or revert.
3. **CHANGELOG**: add the release-gate evaluation table.
4. **Post-release**: monitor a fresh post-release contest for bucket-4 direct recall; report in next release notes.

## Initial gate values (v0.2.0 baseline)

Argus has not yet run formal hold-out tests. v0.2.0 ships with **baseline=unknown** for all four tests. v0.2.1 establishes the baseline by running on a fresh post-cutoff contest. v0.2.2 onward must show non-decreasing performance on held-out and post-cutoff buckets.

If v0.2.1's baseline shows held-out direct recall < 25%, that's the signal that Argus has been over-fitting all along and the architectural ceiling is closer than the team hoped. Plan for the triage-tool reframing in that case.
