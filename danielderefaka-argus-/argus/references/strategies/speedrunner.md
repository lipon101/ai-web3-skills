# Speedrunner Strategy — quick post-launch / low-signal triage

> **Archetype**: Speedrunner + Scavenger (WhiteHatMage guide § "Speedrunner — the launcher" + "Scavenger — the ghost")
> **Introduced in**: v0.6.0
> **When triggered**: Fresh launch (< 30 days old) OR low bug-density prediction (composite < 1.5)
> **Goal**: Find bugs that take minutes, not hours. Surface auth mistakes, common attack vectors, operational errors — the bugs that exist in the first hours-to-days of a launch.

## What Speedrunner optimizes for

The WhiteHatMage guide identifies that **freshly-launched programs have a different bug profile** than mature ones:

1. **Auth mistakes** — wrong signer checks, missing authority validation, over-permissioned admin keys
2. **Operational errors** — misconfigured parameters, wrong addresses, broken initialization
3. **Known patterns in new wrappers** — someone forked an AMM and forgot to change the fee receiver
4. **Off-by-default protections** — reentrancy guards not enabled, overflow checks disabled, fee-on-transfer tokens not handled

Speedrunner explicitly does NOT hunt for:
- Deep state machine violations (takes hours of mental model construction — Digger territory)
- Novel vulnerability classes (Lead Hunter territory — separate strategy)
- Cross-contract invariant breaks (requires full protocol mapping)

## Pipeline modifications

### Stage 1 (reduced)

Skip the full 6-step threat model. Instead:

1. **Actor enumeration** (Step 1 only — who can call what?)
2. **Surface points 1-4 only**:
   - (1) Access control — every privileged function, every signer check
   - (2) Input validation — every `unwrap()`, every unchecked parameter, every array/slice access
   - (3) Authentication — every signature verification, every origin check
   - (4) Authorization — every role gate, every admin-only path
3. **Skip**: Surface points 5-10 (state management, token handling, external calls, crypto, time/randomness, economic incentives), entry point completeness, invariants

Output only: `actors.md`, `entry-points.md` (privileged only), `attack-surface.md` (surface points 1-4 only)

### Stage 2 (reduced angle set)

Run only these 4 angles (in parallel):

| Angle | Why |
|-------|-----|
| **Auth / Account / Signer / Origin** | Fresh launches have auth bugs. This angle alone finds 40-60% of first-week exploits. |
| **Vector Scan** | Pattern-matched known bug classes from the V1-V132 catalogue. Fast. |
| **Execution Trace** | Quick function-call trace — does `deposit()` actually update `total_deposits`? |
| **First Principles** | Violate the most obvious assumptions. Not the deep ones — the obvious ones. |

Skip: Math Precision, Economic Security, Invariant, Periphery, Crypto Soundness, Concurrency, FFI Boundary.

### Stage 3 (relaxed PoC floor)

- **Target**: Tier-2 integration test
- **Floor**: Tier-3 minimal reproducer (same as Digger)
- **Tier-1 E2E**: Not required for Speedrunner findings. If a finding advances on Tier-2, it advances.
- **Certainty floor**: 60 (down from 80 in Digger). Speedrunner accepts lower proof quality because the target is low-signal — spending Tier-1 effort on a low-signal target is misallocated budget.

### Stage 4 (reduced adversarial)

- **Pass A only**: Quick invalidity check against the 4 default invalidator categories (EG/US/OS/SC). Skip Pass B/C/D.
- **Kill rule**: If Pass A returns HIGH-confidence HOLDS in EG/US/OS/SC → KILL. If LOW-confidence or different category → ADVANCE at claimed severity.
- **Rationale**: Speedrunner findings don't warrant a 3-judge Pass C panel. The user can manually review borderline cases.

### Stages 5-8 (full)

These are fast post-pass stages. Run them fully regardless of strategy — they're cheap compared to Stage 2/3/4.

## When Speedrunner is the wrong choice

- **High bug-density prediction + mature target (> 180 days)**: Use Digger. Speedrunner will miss the complex bugs that high-complexity mature targets have.
- **Target has known fork ancestry**: Use Differ supplement. Fork context-loss bugs are invisible to Speedrunner's reduced angle set.
- **User explicitly requested comprehensive audit**: Respect the user. Speedrunner is a bug-hunting strategy, not an audit strategy.

## Speedrunner output

Speedrunner findings carry a `strategy: speedrunner` metadata tag. Stage 8 surfaces this in the output header:

> **Strategy note**: This run used the Speedrunner strategy (quick post-launch triage). Findings cover auth, access control, input validation, and obvious assumption violations only. Complex state-machine, economic, and cross-contract vulnerabilities may exist but were not targeted. For comprehensive coverage, re-run with the Digger strategy.
