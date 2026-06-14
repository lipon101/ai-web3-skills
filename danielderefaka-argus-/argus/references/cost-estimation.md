# Cost Estimation — Stage 0

Stage 0 runs after the user supplies inputs (target, bounty URL, repo URL) and before Stage 1 begins. It produces a per-stage cost breakdown specific to the target codebase, then asks the user to confirm before proceeding.

Read this file at Stage 0 start.

## Why Stage 0 exists

Argus runs are not cheap. Real costs vary by 100x across codebases — a 500-line Anchor program is a $5 audit; a 50,000-line CosmWasm protocol is a $300 audit. A flat estimate hides this and burns trust on the first surprise. Stage 0 forces the model to compute a real estimate from the actual codebase metrics before the user authorizes the run.

## Named depth tiers (NEW v0.4.0)

Stage 0 selects a **depth tier** before computing the estimate. The tier is the user-visible knob that trades audit thoroughness against cost. Internally the tier toggles which Stage 2 angles run, which deterministic backends fire, and whether Stage 3 mandates Tier-1-live-e2e or accepts a lower PoC tier.

| Tier | Mode | Stage 2 angles | Deterministic backends | Stage 3 PoC tier | Stage 4 passes | Indicative cost |
|------|------|----------------|------------------------|------------------|----------------|-----------------|
| **Light** | smoke | 4 fast angles: Vector Scan, Periphery, First Principles, Math Precision | Clippy security-lints only | Tier-3 (state-only sim) accepted | Pass A + Pass D only | ~30% of Core |
| **Core** | default | All 8 angles | Clippy + cargo-audit + cargo-deny + cargo-geiger | Tier-2 (in-process reproducer) MINIMUM | Pass A/B/C/D full | 1.0× (baseline) |
| **Thorough** | maximum | All 8 angles + 4 cross-cutting depth re-runs (consensus-invariant, network-surface, storage-state, runtime-config) | All Core backends + Miri (UB) + Kani (bounded MC) + Loom (concurrency) + Rudra (unsafe-trait) + cargo-fuzz (24h budget) | Tier-1 (live e2e) MANDATORY for CONFIRMED | Pass A/B/C/D full + Devil's-Advocate self-rebuttal loop ×2 | ~3.0× Core |

### Tier selection at Stage 0

When asking the user how to proceed, present the tier choice BEFORE the proceed/cap/cancel choice:

```
Depth tier (affects cost ~3× across Light/Thorough):

[L] Light    — smoke audit, 4 angles, Clippy only, no fuzz       (~$X)
[C] Core     — default, 8 angles, +cargo-audit/deny/geiger        (~$Y)
[T] Thorough — Core + Miri/Kani/Loom/Rudra/fuzz + 2× rebuttal     (~$Z)
```

The tier choice writes to `$RUN_DIR/0-cost-preview/depth-tier.txt`. Every downstream stage reads this file to decide which work to perform. Stage 1 doesn't change shape; tiers diverge starting at Stage 2.

### Tier × Mode interaction

Depth tier is **orthogonal** to audit mode (smart-contract vs infra). The cross-cutting depth re-runs in Thorough tier only fire when `mode == infra`; in smart-contract mode Thorough simply runs the Stage 2 8-angle set against a 2nd LLM ensemble (Sonnet + Opus) for the same vector pool.

### When the user does not specify

Default is **Core**. The cost preview shows all three tiers side-by-side; the user picks one before authorizing the run.

### Tier mapping for `estimate-cost.py`

The estimator accepts `--depth-tier {light|core|thorough}` (default `core`). The tier multiplies per-stage formulas:

| Stage | Light multiplier | Core multiplier | Thorough multiplier |
|-------|------------------|-----------------|---------------------|
| 1 | 1.0 | 1.0 | 1.0 |
| 2 | 0.5 (4 angles vs 8) | 1.0 | 1.6 (8 angles + 4 depth re-runs ÷ 2 for cache hit) |
| 3 | 0.7 (Tier-3 PoC cheaper) | 1.0 | 1.5 (Tier-1 live e2e mandatory) |
| 4 | 0.4 (Pass A+D only) | 1.0 | 1.8 (full 4-pass + 2× rebuttal) |
| 5/6/7/8 | 1.0 | 1.0 | 1.0 (no shape change) |
| Deterministic backends | 0.0 (Clippy only) | 0.1 (audit/deny/geiger fast) | 1.0 (Miri/Kani/Loom/Rudra/fuzz dominate) |

## The estimation procedure

### Step 1 — Run enumerate.sh

If `1-protocol-map/_enumerate.txt` doesn't exist yet, run `bash $SKILL_DIR/scripts/enumerate.sh <project-root>` and capture its output to a temp file. The cost estimator parses the labeled sections (`=== nSLOC ===`, `=== test_functions ===`, etc.).

### Step 2 — Run estimate-cost.py

```bash
python3 $SKILL_DIR/scripts/estimate-cost.py <project-root> \
    --enumerate-output <enumerate-output-file> \
    --dup-mode <local-only | full> \
    --depth-tier <light | core | thorough> \
    [--bounty-url-set]
```

Flags:
- `--enumerate-output <file>`: path to the captured enumerate.sh output. Without this, the estimator falls back to a direct walk of `*.rs` files (less accurate).
- `--dup-mode local-only | full`: defaults to local-only. Pass `full` only when the user supplied a GitHub repo URL.
- `--depth-tier light | core | thorough`: v0.4.0 — selects audit depth (default `core`). See § Named depth tiers above.
- `--bounty-url-set`: pass when the user supplied a bounty URL at run start. Increases Stage 6 estimate (WebFetch + per-finding mapping).
- `--findings-est N`: optional override of the heuristic finding-count estimate.

The script outputs a structured cost-preview block to stdout. Argus reads it directly.

### Step 3 — Present to the user

Use `AskUserQuestion` to present the estimate and ask the user how to proceed:

```
<paste the estimate output>

How would you like to proceed?

[A] Yes — proceed with the full audit (estimated $X-$Y, ~Z minutes)
[B] Cap at Stage N — stop after a specific stage if cost-tracking exceeds estimates by >20%
[C] Reduce scope — re-run with --scope flag pointing at a subset of files
[D] Cancel — abort before Stage 1 begins
```

If the user picks `Cap at Stage N`, ask which stage and write the cap to `$RUN_DIR/0-cost-preview/cap.txt`. Stage 8 will surface the cap as a mode warning.

If the user picks `Reduce scope`, ask which crate / module / file glob to focus on. Re-run estimate-cost.py with the reduced scope and present a fresh estimate.

If the user picks `Cancel`, abort the run before Stage 1 begins. Do not write any output to `$RUN_DIR`.

### Step 4 — Write the preview to disk

After the user confirms (option A, B, or C), write the full cost-preview text plus the user's choice to `$RUN_DIR/0-cost-preview/preview.md`. This becomes part of the audit trail; Stage 8's final terminal print compares estimated vs actual cost.

## Pricing tables (per million tokens)

Argus uses Anthropic API list pricing as the cost basis. The per-stage model mix is calibrated for the actual Argus workload:

| Model | Input ($/M) | Output ($/M) | Cached input ($/M) |
|-------|-------------|--------------|--------------------|
| Sonnet 4.5 / 4.6 | 3.00 | 15.00 | 0.30 |
| Opus 4.x | 15.00 | 75.00 | 1.50 |
| Haiku 4.5 | 1.00 | 5.00 | 0.10 |

The estimator uses list rates (no cache discount applied) because Argus's actual cache hit rate is run-dependent — better to over-estimate than under-estimate.

## Per-stage model mix

| Stage | Sonnet | Opus | Haiku | Why |
|-------|--------|------|-------|-----|
| 1 — Mapping | 70% | 30% | 0% | Mostly read-and-summarize; orchestrator uses Opus |
| 2 — Audit angles | 50% | 50% | 0% | 4 angles each (Vector Scan, Math, Periphery, First Principles use Sonnet; Auth, Economic, Execution Trace, Invariant use Opus) |
| 3 — PoC | 60% | 40% | 0% | Sonnet for orchestration, Opus for hard PoCs |
| 4 — Adversarial | 30% | 70% | 0% | **Opus-heaviest stage**: generator + judge + close-call review all use Opus |
| 5 — Platform validation | 100% | 0% | 0% | Rule-application; Sonnet sufficient |
| 6 — Program triage | 100% | 0% | 0% | WebFetch + structured mapping |
| 7 — Duplication | 80% | 20% | 0% | gh CLI + JSON parsing; Opus only for adjacent-vs-exact judgment |
| 8 — Output | 100% | 0% | 0% | Aggregation + per-template formatting |

## Per-stage token formulas

These are the formulas the estimator uses. They are calibrated against real Argus runs and assume average prompt-cache hit rates. Real cost varies ±30%.

### Stage 1
- `input = nSLOC × 3 + 50,000`
- `output = 25,000 + nSLOC / 2`
- `wall_clock = 1 + nSLOC / 5,000` minutes

### Stage 2 (8 parallel angles)
- per-angle input: `nSLOC × 3 + 60,000`
- per-angle output: `8,000 + (findings_est / 8) × 4,000`
- total: `per_angle × 8 + 30,000` (dedupe overhead)
- `wall_clock = 4 + nSLOC / 8,000` minutes

### Stage 3 (PoC per finding)
- per-finding input: `35,000`
- per-finding output: `8,000`
- total: `findings × (input + output)`
- `wall_clock = 3 + findings × 1` minutes (compile-and-run cycles)

### Stage 4 (Adversarial 4-pass per finding) — Opus-heaviest
- per-finding input: `45,000`
- per-finding output: `25,000`
- total: `findings × (input + output)`
- `wall_clock = 4 + findings × 1` minutes

### Stage 5 (Platform validation)
- per-finding input: `25,000`
- per-finding output: `10,000`
- total: `findings × (input + output)`

### Stage 6 (Program triage)
- WebFetch + per-finding mapping: `30,000 + findings × 12,000`
- (without bounty URL: `findings × 5,000`, no WebFetch)

### Stage 7 (Duplication probes)
- `dup_mode = full`: `findings × 25,000` (gh CLI + per-pair classification)
- `dup_mode = local-only`: `findings × 5,000` (git log only)

### Stage 8 (Output + formatting)
- Triage files: `50,000 + findings × 8,000`
- Phase 8b template formatting: `findings × 6,000` output

## Subscription tier envelopes

These are rough 5-hour windows for each Claude subscription tier:

| Tier | Monthly cost | 5h token budget |
|------|--------------|------------------|
| Claude Pro | ~$20 | ~5M tokens |
| Claude Max-5x | ~$100 | ~25M tokens |
| Claude Max-20x | ~$200 | ~100M tokens |

The estimator computes "% of one 5-hour window" by dividing total tokens by the budget. This is approximate — real Anthropic limits are message-based with rolling windows; the estimator is a useful heuristic, not a contract.

## Finding-count heuristic

Real finding count is hard to predict. The estimator uses:

```
findings_low  = max(3,  nSLOC / 100)
findings_high = min(35, max(8, nSLOC / 50))
```

This produces:
- 500 nSLOC → 5–10 candidates
- 3,000 nSLOC → 30–35 candidates (capped)
- 15,000 nSLOC → 35 candidates (capped)
- 50,000 nSLOC → 35 candidates (capped)

For very large codebases (>15k nSLOC), the cap kicks in and the estimate becomes pessimistic on PoC + Stage 4 work. Real findings often number 25-50 across the full pipeline. The user should override `--findings-est` if they have a better prior.

## Cost drivers (surfaced to user)

The estimator outputs a "Cost drivers in this run" section listing factors that materially affect the estimate:

- **Anchor project shape** → Stage 3 RPC discovery adds ~30% to Stage 3.
- **Large codebase (>5k nSLOC)** → Stage 2's 8 parallel angles each read full source → Stage 2 dominates.
- **High finding count (>20)** → Stages 3-7 scale linearly per finding; suggest `--scope` to focus.
- **Many unsafe blocks (>5)** → Periphery + First Principles angles deepen review.
- **No bounty URL** → Stage 6 generic-mode (cheaper, no WebFetch); Stage 8 caps confidence at 65.
- **Local-only dup-mode** → Stage 7 cheaper but reduced confidence cap at 75.
- **Zero tests detected (Anchor)** → Stage 3 scaffolds from scratch → ~20% Stage 3 surcharge.

The driver list is the user's signal for whether the cost is justified. Many drivers indicate a complex audit; few drivers indicate a routine one.

## Real-time tracking (future v0.1.6+)

The current implementation is upfront-only. Future versions will:

1. Track actual token usage per stage (via Anthropic API metadata if available).
2. Compare to estimate at end of each stage.
3. Warn if any stage exceeds its estimate by >20%.
4. Surface the overrun to the user via AskUserQuestion: "Stage 4 is over budget (estimated 500k, actual 800k). Continue or cap further stages?"

This is not yet implemented. The current Stage 0 is upfront only; the user should monitor the stage-by-stage `[Stage N: X advanced, Y downgraded, Z killed]` summary lines as a proxy for "is the run going as estimated?"

## Calibration history

The formulas above are calibrated against:

- vault-protocol run (901 nSLOC, 7 planted bugs, 24 candidates → 6 SUBMIT) — Stage 4 was the dominant cost.
- monero-oxide run (~3000 nSLOC, complex domain) — Stage 2 + Stage 3 dominated.

Calibration is updated as Argus runs against more targets. Submit a calibration data-point to `evals/cost-calibration.md` after a real run by recording: project shape, nSLOC, finding count, actual API cost (if available from Anthropic console), and stage-by-stage wall-clock breakdown.

## Anti-patterns

- **Telling the user "this will be cheap" without running the estimator.** Always run estimate-cost.py — even on small targets.
- **Skipping Stage 0 in auto-mode.** Even in auto-mode, Stage 0 stops to ask. Cost authorization is not delegated.
- **Inflating estimates "to be safe."** Conservative estimates are fine; padded estimates burn user trust. Use the formulas, then mention the ±30% range honestly.
- **Hiding the per-stage breakdown.** The breakdown is the most useful part — it lets the user cap or reduce scope rationally.
