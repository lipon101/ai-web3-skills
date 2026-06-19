# Hunting Strategies — strategy-driven pipeline routing

> **Introduced in**: v0.6.0. Selected at Stage 0.5 based on signal assessment.
> **Audience**: The orchestrator. Each strategy modifies the pipeline's behavior — which angles run, how deep Stage 1 goes, what PoC tier is accepted.
> **Relationship to audit modes**: Strategies are orthogonal to `smart-contract` vs `infra` modes. Any strategy can run in either mode.

## The four strategies

Argus ships with four hunting strategies derived from the WhiteHatMage bug hunting guide's seven hunter archetypes. Each strategy modifies the pipeline's behavior:

| Strategy | Archetype | When to use | Pipeline change |
|----------|-----------|-------------|-----------------|
| **Digger** | Digger | Mature target, high bug-density prediction, want comprehensive coverage | Full pipeline as-is (default) |
| **Speedrunner** | Speedrunner + Scavenger | Fresh launch (< 30 days), or low bug-density prediction | Skip Stage 1 completeness, run only essential angles, accept Tier-2 PoC |
| **Watchman** | Watchman | Recent upgrade detected (< 14 days), or user-supplied prior-commit | Diff against prior commit, analyze only changed paths |
| **Differ** | Differ | Known fork ancestry detected in Stage 1, or user-supplied reference | Load reference implementation, compare critical paths, flag context-loss deviations |

## Strategy selection logic

Decisions are made at Stage 0.5, driven by signal assessment:

```
bug_density = signal-report.bug_density_prediction
days_old = git_history.first_commit_age_in_days
days_since_upgrade = git_tags.most_recent_tag_age_in_days
has_fork_ancestry = Stage-1 fork-ancestry check (from attack-surface.md)

strategy:
  if user_explicitly_picked_strategy:
      use user's choice, log divergence from recommendation
  elif bug_density >= HIGH:
      Digger (with Differ supplement if has_fork_ancestry)
  elif days_old < 30:
      Speedrunner
  elif days_since_upgrade < 14:
      Watchman (run as supplement, not replacement)
  elif bug_density == LOW:
      Speedrunner
  else:
      Digger (default)
```

## Strategy behavior matrix

| Pipeline component | Digger | Speedrunner | Watchman | Differ |
|-------------------|--------|-------------|----------|--------|
| **Stage 1 depth** | Full threat model (6-step) | Actor enumeration + surface points 1-4 only | Diff-aware protocol map (changed modules only) | Full + reference import |
| **Stage 2 angles** | All 10 | Auth + Input Validation + Vector Scan + First Principles only | All angles, but scope = changed paths only | All 10 + Differ angle |
| **Stage 2 parallel?** | Yes (>10 source files) | Yes (cheap angles, no threshold) | Yes (narrow scope, runs fast) | Yes + Differ (sequential after others) |
| **Stage 3 PoC floor** | Tier-1 target, Tier-3 floor | Tier-2 acceptable, Tier-3 floor | Tier-1 target for regression-introduced bugs | Tier-2 floor (reference behavior is comparator) |
| **Stage 3.5 (auto-verify)** | Opt-in | Skip (too expensive for quick triage) | Run only on changed paths | Run if reference has verification artifacts |
| **Stage 4 adversarial** | Full Pre-Pass + Pass A/B/C/D | Pass A only (quick invalidity check, skip Pass B/C/D) | Full on changed paths | Pass B augmented with reference-behavior comparators |
| **Stage 4.5 combination** | Full pairwise | Skip | Skip (narrow scope limits cross-finding chains) | Cross-project pair analysis |
| **Stage 5-8** | Full | Full (these are fast post-pass) | Full | Full |
| **Expected wall time** | 100% (baseline) | ~25% of Digger | ~35% of Digger | ~130% of Digger (reference fetch + comparison) |

## Strategy supplements

A supplement strategy runs ALONGSIDE the primary strategy, not instead of it:

- **Differ supplement**: Digger + Differ angle enabled. The pipeline runs all 10 angles plus the differ agent.
- **Watchman supplement**: Digger + diff-aware Stage 1. The protocol map is aware of what changed.

## The revisit advantage (all strategies)

Every strategy benefits from temporal context. When the signal assessment detects a stale prior audit (> 180 days), the orchestrator:

1. Surfaces the prior run's `hot-zones.md` and `discard.md` (if available)
2. Flags prior-discarded findings for reconsideration
3. Notes production-age evidence: "protocol has processed $X volume since last audit without incident — suggests prior findings were correctly dismissed" OR "protocol has experienced Y incidents since last audit — suggests gaps in prior coverage"

## Advanced strategies (explicit trigger only)

Two additional strategies are available but never auto-selected — the user must explicitly invoke them via `--strategy`:

| Strategy | Archetype | When to use | Pipeline change | Reference |
|----------|-----------|-------------|-----------------|-----------|
| **Lead Hunter** | Lead Hunter | Very-high bug density + novel consensus/crypto/VM | Single-subsystem depth-first, exhaustive assumption mapping, novel class discovery | `references/strategies/lead-hunter.md` |
| **Scientist** | Scientist | Very-high bug density + high optimization signal (unsafe >5%, inline assembly, SIMD) | Custom tooling phase (fuzz harness, Kani proof, custom lint), merged into Stage 2 | `references/strategies/scientist.md` |

These are the WhiteHatMage guide's highest-ROI but highest-investment archetypes. Lead Hunter discovers entirely new vulnerability classes through deep understanding of one system. Scientist builds custom verification tooling tailored to the specific codebase. Both require expert Rust skills and pair naturally — the Scientist builds the tooling; the Lead Hunter uses it for novel class discovery. See `references/strategies/lead-hunter.md` and `references/strategies/scientist.md` for full methodology including pipeline modifications, when they're the right/wrong choice, and output formats.

## What this file does NOT cover

- Per-strategy detailed methodology (these live in `references/strategies/{speedrunner,watchman,differ,lead-hunter,scientist}.md`)
- Stage-specific reference routing (that's `audit-modes.md`)
- The Differ angle methodology (that's `hacking-agents/differ-agent.md`)
- Signal extraction (that's `signal-assessment.md`)
