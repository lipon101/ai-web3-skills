# Scientist Strategy — custom tooling development

> **Archetype**: Scientist (WhiteHatMage guide § "Scientist — the toolmaker")
> **Introduced in**: v0.6.0
> **When triggered**: User explicitly selects `--strategy scientist` at Stage 0, OR VERY-HIGH bug density + HIGH optimization signal (unsafe >5%, inline assembly, SIMD — candidate for custom verification)
> **Goal**: Build custom analysis tooling tailored to the specific codebase, then use that tooling to find bugs that generic tools miss.
> **Pairs with**: Lead Hunter (the Scientist builds the tooling; the Lead Hunter uses it for deep analysis)

## The Scientist insight

The WhiteHatMage guide describes the Scientist as a hunter who "builds custom tooling using everything available." The key observation: generic tools (Miri, Kani, cargo-fuzz, Slither, clippy) find generic bugs. Custom tooling finds bugs specific to the codebase's unique assumptions.

The guide notes that Scientist "requires expert Rust skills" and has "high upfront investment but massive returns on complex codebases." A custom fuzzer targeting a novel invariant will find bugs that no off-the-shelf tool can. A custom lint checking a project-specific invariant will catch regressions that pass CI.

Scientist formalizes this within Argus: a pre-Stage-2 phase that builds custom verification harnesses, custom lints, and custom fuzz targets, then feeds them into Stage 2/3 for finding generation.

## Pipeline modifications

### Pre-Stage 1: Tooling needs assessment

Before building anything, the Scientist assesses what custom tooling would have the highest ROI:

```
For each of the target's unique properties (from Stage 0.5 innovation/originality signals):
  1. Is this property verifiable with OFF-THE-SHELF tools?
     - Miri for unsafe blocks → YES, off-the-shelf works
     - Kani for arithmetic invariants → YES, off-the-shelf works
     - cargo-fuzz for input parsing → YES, off-the-shelf works
     - Custom consensus invariant → NO, needs custom harness
     - Custom serialization format → NO, needs custom fuzz target
     - Custom crypto primitive → NO, needs custom property test
  2. If NO to off-the-shelf: would custom tooling find bugs that manual analysis would miss?
     - YES → add to tooling plan
     - NO → skip (manual analysis is sufficient)

Output: tooling plan — list of custom tools to build, ordered by expected ROI.
Cap: 3 tools per Scientist run (Scientist has high upfront cost).
```

### Tool type catalogue

| Tool type | What it verifies | Effort | When to build |
|-----------|-----------------|--------|---------------|
| **Custom fuzz harness** | Novel invariant across random input sequences | Medium (50-150 lines of Rust) | Novel state machine, custom serialization, custom VM |
| **Custom Kani proof** | Arithmetic relationship between state variables | Low-Medium (20-80 lines of Rust + kani annotation) | Custom math (reward curves, fee formulas, conversion rates) |
| **Custom lint (Clippy/dylint)** | Project-specific pattern (e.g., "every X call must be preceded by Y check") | Medium (30-100 lines of Rust) | Recurring pattern that manual review would miss |
| **Custom Miri test** | Unsafe block soundness for a project-specific unsafe abstraction | Low (10-30 lines of Rust) | Project has custom unsafe abstractions (not just `unsafe` blocks for FFI) |
| **Custom property test (proptest)** | State round-trip invariant (serialize → deserialize → serialize matches) | Low-Medium (30-80 lines of Rust) | Custom serialization, custom crypto primitive, custom data structure |
| **Custom static analysis (regex/semgrep)** | Pattern match across the codebase (not Rust-semantic, just text pattern) | Low (5-20 lines of pattern) | Known-dangerous pattern specific to this codebase |

### Stage 1.5: Tool building

After Stage 1 (protocol mapping), before Stage 2 (finding generation), the Scientist builds the custom tools:

```
For each tool in the tooling plan:
  1. Read the relevant source code (the subsystem the tool targets)
  2. Build the tool:
     - Custom fuzz harness: write to $RUN_DIR/1-5-scientist/fuzz_<name>.rs
     - Custom Kani proof: write to $RUN_DIR/1-5-scientist/kani_<name>.rs
     - Custom lint: write to $RUN_DIR/1-5-scientist/lint_<name>.rs
     - Custom Miri test: write to $RUN_DIR/1-5-scientist/miri_<name>.rs
     - Custom property test: write to $RUN_DIR/1-5-scientist/proptest_<name>.rs
     - Custom static pattern: write to $RUN_DIR/1-5-scientist/pattern_<name>.txt
  3. Run the tool against the codebase (if applicable)
  4. If the tool finds bugs: write findings to $RUN_DIR/1-5-scientist/findings_<tool>.md
  5. If the tool is clean: note "no violations found" — the tool is ready for CI integration
  6. If the tool fails to build/run: log the failure, note for manual follow-up
```

### Tool output → finding pipeline

Tools that find violations produce findings that enter Stage 3 directly:

```
Custom tool finding → $RUN_DIR/1-5-scientist/findings_<tool>.md
                   → promoted to F-NN at Stage 2 by the orchestrator
                   → enters Stage 3 PoC generation (the tool's output IS the PoC evidence)
                   → standard pipeline from there
```

Tool-found findings carry `evidence: [SCIENTIST-TOOL]` and `tool: <tool-name>` metadata. The tool's output is primary evidence — stronger than manual code review but weaker than Tier-1 E2E PoC.

### Stage 2-8

Scientist runs ALONGSIDE the standard pipeline, not replacing it:

1. Stage 1.5: Build custom tools, run them, collect findings
2. Stage 2: Standard 10-angle set runs in parallel
3. Stage 2 post-processing: Scientist tool findings are merged into the finding pool
4. Stage 3-8: Standard pipeline on ALL findings (manual + tool-found)

The Scientist tools amplify the manual angles. A bug found by BOTH a custom fuzzer AND the Invariant angle has much higher confidence than either alone.

## Scientist tool templates

### Custom fuzz harness template

```rust
// $RUN_DIR/1-5-scientist/fuzz_<name>.rs
// Fuzz target for: <what this fuzzes>

#![no_main]
use libfuzzer_sys::fuzz_target;
use <target_crate>::<module>;

fuzz_target!(|data: &[u8]| {
    // 1. Parse input from fuzzer bytes
    // 2. Set up the preconditions the subsystem expects
    // 3. Call the target function(s) in varying sequences
    // 4. Assert the invariant holds after every call

    // Example:
    // let Ok(input) = <InputType>::deserialize(data) else { return };
    // let mut state = State::initial();
    // state.apply(input);
    // assert!(state.invariant_holds(), "invariant violated: {:?}", state);
});
```

### Custom Kani proof template

```rust
// $RUN_DIR/1-5-scientist/kani_<name>.rs
// Kani proof for: <what this proves>

#[kani::proof]
fn prove_<invariant_name>() {
    // 1. Create symbolic inputs
    let a: u64 = kani::any();
    let b: u64 = kani::any();

    // 2. Constrain to realistic ranges
    kani::assume(a <= MAX_VALUE);
    kani::assume(b > 0);  // avoid division by zero

    // 3. Apply the target computation
    let result = <target_crate>::compute(a, b);

    // 4. Assert the invariant
    assert!(result <= a + b, "result {} exceeds sum of inputs", result);
}
```

### Custom Clippy lint template

```rust
// $RUN_DIR/1-5-scientist/lint_<name>.rs
// Custom lint: <what this detects>

// Example: detect calls to `update_state()` not preceded by `validate_input()`
//
// Pattern to match in the codebase (semgrep-style):
// ```
// fn $FUNC(...) {
//   ...
//   $CRATE::update_state($ARGS);
//   ...
// }
// ```
// And check that the same function does NOT contain `validate_input(`.
//
// This can also be a simple grep + awk pipeline for quick checks:
// grep -l 'update_state(' **/*.rs | while read f; do
//   grep -q 'validate_input(' "$f" || echo "MISSING: $f"
// done
```

## Scientist output

`$RUN_DIR/1-5-scientist/tooling-report.md`:

```markdown
# Scientist Tooling Report — <project>

## Tooling plan

| # | Tool type | Target | Rationale | Built? | Findings |
|---|-----------|--------|-----------|--------|----------|
| 1 | Custom fuzz harness | Staking rewards formula | Novel EMA-based reward curve; no off-the-shelf fuzzer covers this | YES | F-XX (arithmetic overflow), F-YY (EMA division by zero) |
| 2 | Custom Kani proof | Fee conversion | Custom decimal conversion between 6-decimal and 18-decimal tokens | YES | No violations (proof passed) |
| 3 | Custom lint | State update ordering | Every `transfer()` must be preceded by `update_balances()` | YES | 3 sites flagged, 2 false positives, 1 real finding (F-ZZ) |

## Tool artifacts

- `$RUN_DIR/1-5-scientist/fuzz_staking_rewards.rs` — fuzz harness (57 lines)
- `$RUN_DIR/1-5-scientist/kani_fee_conversion.rs` — Kani proof (34 lines)
- `$RUN_DIR/1-5-scientist/pattern_state_update.txt` — static pattern (12 lines)

## Integration recommendation

Tools that passed cleanly (kani_fee_conversion.rs) are candidates for CI integration. Add to the target's CI pipeline to catch regressions:
```yaml
# .github/workflows/argus-scientist.yml
- name: Run Kani proof (fee conversion)
  run: cargo kani --proof prove_fee_conversion_invariant
```
```

## When Scientist is the right choice

- **VERY-HIGH bug density + HIGH optimization signal** — unsafe >5%, custom math, custom serialization. Custom tooling catches what generic tools miss.
- **Target has a novel mechanism** — new consensus, new crypto, new state machine. No off-the-shelf tool covers it.
- **You're pairing with Lead Hunter** — the Scientist builds the tooling; the Lead Hunter uses it for novel class discovery.
- **You intend to audit this target repeatedly** — the tooling investment amortizes across multiple runs.

## When Scientist is the wrong choice

- **Standard Anchor program / CosmWasm contract** — off-the-shelf tools (Anchor tests, cosmwasm-std) already cover the verification surface
- **You have limited time** — Scientist's upfront investment is high. If this is a one-time audit, the tools won't amortize.
- **The target has no novel properties** — if everything is verifiable with Miri/Kani/cargo-fuzz, custom tooling adds cost without signal.

## Scientist output in Stage 8

Stage 8 surfaces the Scientist contribution:

> **Strategy note**: This run used the Scientist strategy (custom tooling development). {N} custom tools were built: {list}. {M} findings were discovered by custom tooling and carry `[SCIENTIST-TOOL]` evidence tags. Custom tools that passed cleanly are candidates for CI integration — see `$RUN_DIR/1-5-scientist/tooling-report.md` for details.
