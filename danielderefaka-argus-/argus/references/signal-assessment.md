# Stage 0.5 — Signal Assessment

> **Introduced in**: v0.6.0. Runs after cost preview (Stage 0), before protocol mapping (Stage 1).
> **Purpose**: Extract bug-density signals from the codebase to guide strategy selection. Derived from the WhiteHatMage bug hunting guide's four target-selection signals.
> **When to skip**: Never. Signal extraction is cheap (< 2% of pipeline budget) and gates strategy selection.

## Why signal assessment exists

Audit pipelines waste budget on low-signal targets. A 500-line single-contract Anchor program with two prior audits gets the same treatment as a 50,000-line multi-component bridge with zero prior audits. This stage fixes that by extracting four predictive signals — Complexity, Innovation, Optimization, Code Quality — and outputting a composite bug-density prediction that drives strategy selection for the rest of the pipeline.

Signal assessment asks what the WhiteHatMage guide asks: **"Is this target worth the investment?"**. If the answer is "marginally," the pipeline should bias toward speed (Speedrunner strategy) rather than completeness (Digger strategy).

## Stage contract

```
STAGE 0.5 — Signal Assessment
INPUT:    Stage 0 output (cost preview, project root, git SHA), source tree
OPERATIONS:
  - run scripts/extract-signals.sh <project-root> (mechanical extraction)
  - classify each of 4 signals on a 3-point scale (LOW / MEDIUM / HIGH)
  - compute composite bug-density prediction
  - select recommended hunting strategy
  - if target has known fork ancestry, flag for Differ strategy
  - if target is < 30 days old, flag for Speedrunner strategy
  - if target has recent upgrade (< 14 days), flag for Watchman supplement
OUTPUT:   $RUN_DIR/0-5-signal/signal-report.md
VERDICT:  STRATEGY = <digger | speedrunner | differ | watchman>
          BUG_DENSITY = <low | medium | high | very-high>
EXIT CONDITION: signal-report.md written with all 4 signals scored and strategy selected.
```

## The four signals

### 1. Complexity (CMPLX)

| Level | Criteria |
|-------|----------|
| **HIGH** | >50 nSLOC, ≥5 crates with cross-dependencies, multi-component architecture (bridge relay + validator + contract), ≥3 external integration surfaces (oracles, cross-chain, off-chain workers), async runtime (tokio task spawns, channels), custom serialization formats |
| **MEDIUM** | 10-50 nSLOC, 2-4 crates, 1-2 external integrations, moderate internal state machine |
| **LOW** | <10 nSLOC, single crate, no external integrations, linear / single-entry-point control flow |

**Guide insight**: "Simple programs rarely have meaningful exploit paths." Complexity is the primary signal.

### 2. Innovation (INNOV)

| Level | Criteria |
|-------|----------|
| **HIGH** | Novel consensus mechanism, **ZK proving system or circuit definitions** (Halo2 circuits, arkworks constraint systems, custom gates — triggers ZK Circuit Soundness angle + Lead Hunter recommendation), new VM / execution target, custom crypto (curve, hash, commitment scheme), protocol mechanism with no prior-art deployments, hand-rolled concurrent data structures |
| **MEDIUM** | Fork of a known protocol with substantive changes, novel DeFi mechanism on a standard runtime, multi-party computation with established primitives |
| **LOW** | Standard Anchor program / CosmWasm contract / Substrate pallet, well-known mechanism (ERC-20, staking, basic AMM), simple wrapper around established libraries |

**Guide insight**: Innovation creates bugs. "New things break." The innovation signal is the second-strongest predictor.

### 3. Optimization (OPT)

| Level | Criteria |
|-------|----------|
| **HIGH** | `unsafe` density >5% of total lines, inline assembly, manual memory management (alloc/dealloc not from a standard allocator), hand-written math (not from a crate), SIMD intrinsics, `#[no_std]` with custom allocator, FFI into C/asm for performance |
| **MEDIUM** | `unsafe` density 1-5%, custom `UnsafeCell` usage, `MaybeUninit` for hot-path optimization, type-punning via `transmute`, custom iterator implementations with manual pointer tracking |
| **LOW** | No `unsafe` beyond standard library wrappings, no `transmute`, standard allocator, standard math crate |

**Guide insight**: Optimization is a proxy for bug surface. Every `unsafe` block, every manual optimization, is a potential UB site.

### 4. Code Quality / Audit History (QUAL)

| Level | Criteria |
|-------|----------|
| **HIGH** (high bug density signal) | Sloppy comments / no comments, inconsistent naming, test coverage <30%, >20 Clippy warnings, `unwrap()` density >5% of fallible calls, no prior audits, no security contact, no bounty program history, abandoned dependencies |
| **MEDIUM** | Mixed documentation quality, test coverage 30-70%, some Clippy warnings, one prior audit >6 months old, active maintenance, some dependencies out of date |
| **LOW** (low bug density signal) | Thorough documentation, test coverage >70%, clean Clippy, ≥2 prior audits with public reports, active security contact, regular dependency updates, fuzz targets present |

**Guide insight**: Poor code quality is a direct signal. "Sloppy comments and inconsistent naming" directly predict bug density. Prior audits reduce the remaining bug surface — especially if they found real bugs (which means they were competent).

## Composite bug-density prediction

```
BUG_DENSITY = weighted_sum(CMPLX×0.40, INNOV×0.30, OPT×0.15, QUAL×0.15)

where HIGH=3, MEDIUM=2, LOW=1
```

| Score | Prediction |
|-------|-----------|
| ≥ 2.5 | **VERY-HIGH** — expect Critical/High findings; full Digger strategy |
| 2.0–2.4 | **HIGH** — expect several Medium+ findings; core pipeline |
| 1.5–1.9 | **MEDIUM** — likely some Low/Medium findings; consider Speedrunner |
| < 1.5 | **LOW** — few findings expected; Speedrunner or skip |

## Strategy selection

Based on composite score + temporal signals + fork ancestry:

| Conditions | Strategy |
|------------|----------|
| VERY-HIGH or HIGH bug density + ZK circuits detected | **Digger + ZK Circuit Soundness angle** — full pipeline with circuit constraint analysis. Consider Lead Hunter if any single circuit >30 columns. |
| VERY-HIGH or HIGH bug density | **Digger** — full pipeline |
| MEDIUM bug density, no temporal flags | **Digger-light** — full pipeline, light depth tier |
| MEDIUM bug density, < 30 days old | **Speedrunner** — quick triage, auth + access control + input validation |
| Any density, recent upgrade (< 14 days) | **Watchman** supplement — diff against prior commit |
| Any density, known fork ancestry | **Differ** supplement — load reference implementation |
| LOW bug density | **Speedrunner** — quick pass only; full pipeline unjustified |

**Combining strategies**: If a target has high bug density AND is < 30 days old, run Speedrunner first (fast auth/config/operational check), THEN Digger. If a target has fork ancestry AND high bug density, Digger runs with the Differ angle enabled.

## Output format

`$RUN_DIR/0-5-signal/signal-report.md`:

```markdown
# Signal Assessment — <project-name>

**Date**: <YYYY-MM-DD>
**Git SHA**: <commit>

## Signal extraction

| Signal | Score | Evidence |
|--------|-------|----------|
| Complexity | HIGH | 127 nSLOC, 8 crates, bridge relay + validator + contract, 3 external integrations |
| Innovation | MEDIUM | Fork of X with modified consensus (see git log for substantive changes) |
| Optimization | LOW | 0.3% unsafe density, no inline assembly, standard allocator |
| Code Quality | MEDIUM | Test coverage 45%, 12 Clippy warnings, one prior audit 8 months ago |

## Composite

- **Bug-density prediction**: HIGH (2.45)
- **Selected strategy**: Digger + Differ supplement (fork ancestry detected)
- **Reasoning**: High complexity (multi-component bridge) drives high bug density.
  Fork ancestry (reference: upstream repo at commit X) enables cross-project differencing.
  Code quality is adequate but prior audit is stale; expect rot since then.

## Temporal signals

- **Project age**: 14 months (first commit: 2025-04-02)
- **Days since last audit**: 243 days
- **Days since last upgrade**: 47 days
- **Revisit advantage**: ACTIVE (stale audit → fresh perspective opportunity)

## Strategy routing

| Stage | Effect |
|-------|--------|
| Stage 1 | Protocol mapping — focused on high-complexity surfaces (bridge relay, cross-component invariants) |
| Stage 2 | Angles: all 10 + Differ angle enabled (fork ancestry) |
| Stage 3 | PoC: Tiers unchanged (Tier-1 target) |
| Stage 4 | Adversarial: Pass C uses cross-project precedent when available |
```

## The revisit advantage

The WhiteHatMage guide describes a specific temporal advantage: returning to a codebase after weeks yields fresh perspective. Argus's signal assessment flags this:

- If `days-since-last-audit > 180` AND the prior audit was also Argus: Surface the prior run's `hot-zones.md` and `discard.md`. Previously-discarded findings may be right after all — the revisit advantage means fresh eyes catch what stale eyes missed.
- If `days-since-last-audit > 180` AND the prior audit was external (not Argus): Flag that the protocol has weathered months of production but the audit's assumptions may have rotted. Focus Stage 1 on what changed since the audit (new features, new dependencies, parameter changes).

## What this stage must NOT do

- Do not inflate signals. "Everything is HIGH" defeats the purpose. Use the scale honestly.
- Do not skip signal extraction because "the codebase is small." Even small codebases benefit from honesty about expected bug density.
- Do not override user strategy choice. If the user explicitly picks a strategy at Stage 0, the signal report notes the divergence but respects the user's choice.
