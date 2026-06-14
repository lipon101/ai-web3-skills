# Stage 3.6 — Witness Builder

Stage 3.6 is the **architectural fix** for Argus's primary failure mode (high adjacent recall, ~0% direct recall on novel targets). It runs between Stage 3 (PoC gate) and Stage 4 (Adversarial review). Its job is **not** to gate findings by confidence score — it's to **build minimal, falsifiable bug witnesses** for LEADs that have the right surface signal but can't yet be promoted to FINDINGs.

This stage was designed in v0.2.0 driven by external review (ChatGPT-class reasoning model) which diagnosed Argus's gap as a *representation failure*: the system was producing free-form "suspicious surface" outputs and asking a confidence threshold to decide promotion, but never producing the structured object — a witness — that distinguishes "real specific-instance bug at file:line with attacker control + path + impact" from "pattern matched somewhere nearby."

Read this file at Stage 3.6 start.

## When Stage 3.6 fires

Stage 3.6 fires for every LEAD with confidence in **30-49** AND a tag matching one of the **registered witness-validator classes** below. LEADs above 50 are already FINDINGs (proceed to Stage 4). LEADs below 30 are dropped.

The pipeline:

```
Stage 3 PoC verdict
  ↓
Stage 3.5 Automated Verification (optional, opt-in)
  ↓
Stage 3.6 Witness Builder ← NEW v0.2.0
  ├─ For each LEAD at 30-49 with registered class:
  │     run validator → produce witness OR fail
  │     witness produced → promote to FINDING (confidence becomes 50+)
  │     no witness → LEAD stays at 30-49
  ↓
Stage 4 Adversarial review (only on FINDINGs)
```

Stage 3.6 is **additive**: it cannot demote a FINDING to a LEAD. It only converts LEADs upward.

## The witness contract

Every witness produced by Stage 3.6 is a structured object with these fields:

```yaml
witness:
  finding_id: F-NN
  bug_class: <one of the registered classes below>
  validator: <which Stage 3.6 validator built this>

  # The five canonical witness edges (ChatGPT-style):
  source: <attacker-controlled entry point — file:line + the input field>
  sink: <security-relevant operation — file:line + the unsafe effect>
  path: <ordered list of intermediate steps from source to sink>
  preconditions: <state requirements that must hold for the path to fire>
  guard_status: <"absent" | "bypassable: <why>" | "present-but-flawed: <how>">

  # Falsification:
  falsifier_questions:
    - <question that would invalidate the witness if answered the wrong way>
  falsifier_answers:
    - <orchestrator's answer + cited evidence>
  survived_falsification: yes | no

  # Provenance:
  evidence: [<file:line citations supporting each edge>]
  unknowns: [<any edge the validator couldn't substantiate>]
```

A witness with `survived_falsification: yes` AND no unknowns on critical edges is sufficient to promote the LEAD to FINDING at confidence 60. A witness with survived_falsification but unknowns is FINDING at confidence 50. A witness that fails falsification leaves the LEAD at its original confidence.

## Registered validators (v0.2.0 ships 3; extensible)

### Validator 1 — Critical-Fallback Dead-Code Reverse-Trace

**When to fire**: LEAD has `bug_class: dead-code-fallback` (V101 territory) AND originating angle is Crypto Soundness OR First Principles. The cited "fallback" or "alternative path" is named (function/branch contains `fallback`, `backup`, `alt`, `legacy_v1`, `else_*`, or appears in a `match` between two crypto primitives).

**Operation**:
```
block = LEAD.location  // the cited branch / arm / function

// Build call graph for the cited block
callers = call_graph.query(block, direction=INCOMING, max_depth=WORKSPACE)

// Filter callers to reachable-from-public-entry
public_entries = []
for caller in callers:
    chain = trace_to_public_entry(caller)
    if chain is not None:
        // Walk the chain UP and check every caller's pre-checks
        early_returns_blocking_branch = false
        for c in chain:
            for pre_check in c.early_returns:
                if pre_check.condition implies !block.activating_condition:
                    early_returns_blocking_branch = true
                    break
        if not early_returns_blocking_branch:
            public_entries.push(chain)

if public_entries.is_empty():
    // The branch is unreachable through every public-entry path.
    // The cited "fallback" is dead code.
    witness = {
        source: <documented assumption that this fallback is reachable>,
        sink: <function/feature that documentation claims this fallback enables>,
        path: <every caller-chain traced + the specific pre-check that blocks each>,
        preconditions: <activating_condition>,
        guard_status: "blocked at every caller path",
        falsifier_questions: ["Is there a dynamic dispatch site that reaches this branch?",
                              "Is there a macro-generated caller not in the call graph?"],
    }
    promote LEAD to FINDING with severity=Medium and witness attached
```

**Solves**: SP1 M-05 (Blake3 fallback unreachable in `verify_public_values` because callers `verify_plonk_bn254` / `verify_groth16_bn254` early-return on `!vkey.is_plonk()` / `!vkey.is_groth16()`).

**Risk**: dynamic dispatch (`Box<dyn Trait>`) and macro-generated callers can fool the call-graph check. Mitigation: when dynamic dispatch is detected in any chain, mark `survived_falsification: partial` and route through Stage 4 Pass C instead of auto-promoting.

### Validator 2 — Write-Site Enumeration on Security-Critical Variables

**When to fire**: LEAD mentions clobber/race/overwrite on a variable whose name or struct-field name matches `nonce` / `proof` / `entropy` / `challenge` / `seed` / `witness` / `public_inputs` / `vk_root` / `vkey_hash` / `commit*`. Originating angle: First Principles or Crypto Soundness.

**Operation**:
```
var = LEAD.suspect_variable
write_sites = find_assignments(var, scope=full_workspace)

// Filter: ignore AddAssign on counter types unless explicitly flagged
write_sites = write_sites.filter(site => not is_safe_counter_pattern(site))

if len(write_sites) >= 2:
    // Check: are 2+ writes reachable in same call flow with no read between?
    for (s1, s2) in pairs(write_sites):
        path = find_call_path(s1, s2)
        if path is not None:
            reads_between = find_reads(var, between=path)
            if len(reads_between) == 0:
                // Two writes, no reads between, same call flow → clobber
                witness = {
                    source: <input that triggers the call flow>,
                    sink: var.name + " final value used at " + var.consumer_site,
                    path: [s1, ...path..., s2],
                    preconditions: <activating call sequence>,
                    guard_status: "absent — no read of " + var.name + " before clobber",
                    falsifier_questions: ["Is the second write semantically intended (e.g., re-init after consume)?",
                                          "Is there an external consumer that observes the intermediate value?"],
                }
                promote LEAD to FINDING with severity per Pass D and witness attached
```

**Solves**: SP1 M-06 (proof_nonce clobber at `record.rs:288-291` when packing deferred page-prot events).

**Risk**: legitimate accumulator patterns (counter += delta, then counter *= scale) look like 2 writes. Mitigation: the `is_safe_counter_pattern` filter checks for `+=`/`-=`/`*=` on a `u64`/`u128`/numeric type and skips; an actual nonce-clobber overwrites with an unrelated value.

### Validator 3 — Boundary-Fuzz-Guided DoS Promotion

**When to fire**: LEAD has `bug_class ∈ {EXHAUSTION, CPU_DOS, PUBLIC_API_PANIC}` AND surface is an FFI boundary (`extern "C"`, `wasm-bindgen`, gnark-Go, `unsafe` calling non-Rust) OR an untrusted-input parser (decimal, hex, Base64, Borsh).

**Operation**:
```
fuzzer = init_fuzzer(LEAD.surface.input_type)
strategies = [
    "decimal_length_expansion",
    "invalid_hex_chars",
    "truncated_byte_slice",
    "max_value_at_each_position",
    "alternating_pattern",
]

for strategy in strategies:
    fuzzer.set_strategy(strategy)
    for _ in range(200):  // budget: ~30s wall-clock per strategy
        payload = fuzzer.generate()
        start = now()
        result = run_with_timeout(payload, timeout=2s)
        elapsed = now() - start
        if result.timeout or (elapsed > 0.5s and len(payload) < 100):
            witness = {
                source: <FFI input parameter or untrusted-byte field>,
                sink: <observed CPU exhaustion / panic / OOM>,
                path: [<call to FFI/parser>, <parsing inner loop site>],
                preconditions: <input format constraints>,
                guard_status: "absent — no length / format / time-bound validation",
                falsifier_questions: ["Is this protected by upstream rate limiting?",
                                      "Is the input length bounded by an earlier validation?"],
                evidence: [<crash payload>, <captured stderr>, <timing log>],
            }
            promote LEAD to FINDING with severity per bounty-in-scope-impacts and witness attached
            return
```

**Solves**: SP1 M-07 (decimal-parsing CPU DoS in Go gnark FFI).

**Risk**: cheap fuzz won't trigger pathological inputs requiring complex shapes. Mitigation: failure to produce a crash leaves the LEAD unpromoted (no false positive); user reads the LEAD manually.

### Future validators (v0.2.1+)

Stage 3.6 is extensible. New bug classes get new validators added to this file. Candidates for v0.2.1:

- **Validator 4 — Asset-identity binding check** (V103): for every LEAD claiming "asset/mint/denom mismatch", trace whether the function actually compares `key()`s on the asset across cited instructions.
- **Validator 5 — Underconstrained witness column** (V104): for ZK LEADs flagging an unconstrained advice column, count `assert_eq` / `cs.constrain` calls vs. column count; if 0, build witness.
- **Validator 6 — Truncation-by-design rounding** (V105): for any `checked_div` or `Decimal::from_ratio` flagged in fee/share math, verify the truncation-to-zero case and check for `if result == 0 { result = 1 }` follow-up.
- **Validator 7 — Cost/fee-records-cap mismatch** (V107): for any function that charges a per-unit fee AND returns a Vec/Option, walk both code paths and verify `len(returned) == unit_count_used_in_fee_math`.

## Witness-failure handling

When a validator fires but cannot build a complete witness:

- **No witness produced (validator returned None)**: LEAD stays at original confidence. Stage 3.6 verdict file records "validator <N> attempted; no witness possible because <reason>."
- **Partial witness (some unknowns on non-critical edges)**: LEAD promotes to FINDING at confidence 50, marked `partial_witness: true`. Stage 4 Pass C MUST fire to fill the unknowns.
- **Falsifier-failed witness**: LEAD demotes to **dropped** (not just stays). The falsifier proved the LEAD wrong; the bug doesn't exist as described.

## Output schema

`$RUN_DIR/3-6-witness-builder/F-NN.md`:

```markdown
# F-NN Stage 3.6 verdict

- **finding**: <title>
- **input confidence (Stage 3 verdict)**: <30-49>
- **registered validators that fired**: [<list>]
- **witness built**: yes (full) | yes (partial) | no
- **survived falsification**: yes | no | partial
- **status**: PROMOTE_TO_FINDING (conf 50/60) | LEAD_STAYS | DROPPED_VIA_FALSIFIER

## Witness

[YAML witness object per the contract above]

## Validator runs

### Validator <N>: <name>

- **fired**: yes / no
- **input**: <LEAD properties consumed>
- **operation log**: <pseudocode trace>
- **output**: witness | no_witness(<reason>)

## Falsification

| Question | Answer | Cited evidence | Holds? |
|----------|--------|----------------|--------|
| <q1> | <a1> | <file:line> | yes/no |
| ... |

## Promotion decision

<2-4 sentences explaining the verdict>
```

## Why this isn't just "another gate"

The fundamental design insight: **promotion isn't a confidence question; it's a witness question.** A LEAD with confidence 45 might be a real bug whose witness is one call-graph trace away (M-05). A LEAD with confidence 65 might be a hallucination that survives the threshold because the orchestrator's prose was eloquent. The confidence score conflates these two cases.

Stage 3.6 separates them. A LEAD with no witness stays a LEAD regardless of how high its confidence climbs through prose alone. A LEAD with a witness produces a structured FINDING that Stage 4 can challenge with concrete evidence rather than philosophical objections.

This also addresses ChatGPT's hardest pushback: that catalogue growth without architectural change is "converging as a prior, diverging as a verdict engine." Stage 3.6 is the verdict engine. New vectors (V103+) become better priors. Both grow; neither subsumes the other.

## Cost note

Stage 3.6 fires only on LEADs in 30-49 with registered classes. Per-validator budget: ~30-60 seconds wall-clock + ~10-20k tokens. For a typical run with 5-10 LEADs eligible, total Stage 3.6 cost is roughly equal to one Stage 4 invocation. Stage 0 cost preview should add a Stage 3.6 line.

## Skip mode

User may disable via Stage 0 run-config: `WITNESS_BUILDER: disabled`. In that mode, LEADs at 30-49 stay at 30-49 (legacy v0.1.x behavior). Surfaced in Stage 8 mode-warnings.

Default: enabled with all 3 validators registered.
