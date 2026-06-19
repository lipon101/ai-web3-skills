# Depth-First Critical Path Mode

> **Archetype**: The WhiteHatMage guide's core methodology — "obsess over ONE execution path at a time, checking every assumption and every branch"
> **Introduced in**: v0.6.0 (experimental, opt-in via `--critical-path-first` at Stage 0)
> **Status**: EXPERIMENTAL. This mode inverts Argus's breadth-first architecture. It is documented here as a design reference; full implementation is post-v0.6.0.

## The architectural inversion

Argus's standard Stage 2 fans out to 8-10 angles in parallel. Each angle covers a broad surface area with domain-specific checklists. Cross-angle synthesis happens late (Stage 4.5 combination attack). This is an audit methodology — comprehensive, breadth-first.

The WhiteHatMage guide describes a different approach: **depth-first on one critical path**. The hunter picks the single highest-value execution path (e.g., deposit → stake → earn rewards → unstake → withdraw), then obsessively checks every assumption at every step. Only after exhausting the critical path does the hunter expand to secondary paths.

Critical-path-first mode implements this approach within Argus's pipeline.

## When to use

Critical-path-first is the right strategy when:

- **You have limited time budget** and want the highest-ROI bugs first
- **The target has a dominant user flow** (deposit→withdraw is 90% of volume; everything else is edge cases)
- **The target is complex** and a breadth-first approach would spread attention too thin
- **You're revisiting a previously-audited target** and want to focus on what changed on the main path

## How it works

### Stage 1: Critical path identification

Instead of exhaustive protocol mapping, Stage 1 identifies the single highest-value critical path:

1. **Actor enumeration** (as standard)
2. **Entry point prioritization**: Rank entry points by: (a) TVL exposure, (b) user-facing frequency, (c) complexity (LOC touched), (d) external integration count
3. **Critical path selection**: The connected sequence of entry points touching the highest-ranked entry point
4. **Assumption extraction**: For the critical path ONLY — extract every assumption (value ranges, ordering, identity, arithmetic, state invariants) at every step
5. **Skip**: Surface points 5-10 for non-critical paths, full invariants for the whole system

Output: A focused briefing — the critical path, its entry points, and its assumptions. ~50 lines, not 500.

### Stage 2: Single deep angle

Instead of 8 parallel angles, dispatch ONE "First Principles Critical Path" subagent:

```
You are the Critical Path Depth Agent. Your scope is EXACTLY one execution path:
<critical path description with entry points and assumptions>

For EACH step in this path, in order:
1. List every assumption the code makes at this step (input validation, state precondition, authorization, arithmetic invariant, ordering invariant)
2. For EACH assumption: try to violate it. What actor can violate it? What input can violate it? What ordering can violate it?
3. For EACH violation: trace the downstream effect. Does it cascade? What's the terminal outcome?
4. For EACH terminal outcome: classify as EXPLOITABLE / DEGRADATION / COSMETIC / SAFE

Do NOT move to the next step until every assumption at the current step is exhausted.

After the main path: identify 2-3 variant paths (different parameter values, different ordering, error-recovery sequences) and repeat for those.
```

This single agent gets ~4× the context budget of a standard angle. It produces fewer but deeper findings.

### Stage 3-8

Standard pipeline. The findings from the critical-path agent are often higher-severity than standard breadth findings because they come from the highest-value path.

### After critical path: breadth expansion (optional)

If time budget remains after the critical path is exhausted:

1. Re-run Stage 2 with the standard 8-angle set, but with the critical-path findings as an exclusion list
2. This gives you the best of both: depth-first on what matters most, breadth on everything else

## Comparison with Digger strategy

| Aspect | Digger (standard) | Critical-Path-First |
|--------|-------------------|---------------------|
| Stage 1 cost | High (exhaustive mapping) | Low (focused on one path) |
| Stage 2 angles | 8-10 parallel | 1 deep |
| Finding count | 15-30 | 3-8 |
| Finding quality | Mixed (some low-severity) | Generally higher severity (comes from the critical path) |
| Coverage | Broad | Deep on one path, zero on others |
| Risk | Missing a bug on a secondary path | Missing a bug on the critical path (but unlikely given depth) |
| Best for | Comprehensive audit, mature target, submission-grade | Time-limited hunt, high-ROI bug bounty, revisit |

## Limitations

- **Blind to secondary paths**: A bug on a rarely-used admin function is invisible in critical-path-first mode (until breadth expansion, if run)
- **Requires accurate path identification**: If Stage 1 picks the wrong critical path, the entire strategy is misallocated
- **Not a replacement for Digger**: Critical-path-first is a hunting strategy, not an audit strategy. If the user needs comprehensive coverage (e.g., for a pre-launch audit), use Digger.
