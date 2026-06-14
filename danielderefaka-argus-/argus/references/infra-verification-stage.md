# Stage 3 — Deterministic Verification (`infra` mode)

> Replaces `poc-standards.md` Stage-3 tier-ladder + the entirety of Stage-4 Pass A/B/C/D for `infra` mode. In smart-contract mode, the original tier ladder + adversarial-review pipeline still apply.
>
> Source: DeepSeek `deep8.md` (Chunk 3 spec), integrated 2026-05-12 with adjustments for `audit-modes.md` routing, FINDING schema alignment, and toolchain-check integration.

## Purpose

Every candidate finding from Stage 2 (infra angles, per `references/hacking-agents/infra/`) is mapped to a verification tool. This stage:

1. Selects the correct tool for the finding's vector group (per `dlt-infra-attack-vectors.md`).
2. Generates a harness (LLM-assisted, but always compilable — orchestrator retries on `cargo check` failure).
3. Executes the tool and parses output for the **Golden Signature** declared in the vector catalogue.
4. Marks the finding as **CONFIRMED** (tool reports definitive violation), **DISPROVED** (tool proves absence within bounds), or **INCONCLUSIVE** (no successful run, ambiguous, or vector requires manual review).

**No adversarial judge. No severity re-grading at this stage.** The tool output is the evidence. This is the architectural step-change that distinguishes `infra` mode from SC mode: the verdict is mechanical, not judgmental.

## Prerequisites — toolchain check

Run `bash $SKILL_DIR/scripts/install-infra-deps.sh <project-root> --dry-run` at Stage 3 start. Required tools by vector group:

| Tool | Required for groups | Install command (dry-run flags inert) |
|------|---------------------|---------------------------------------|
| `cargo-miri` (nightly) | A, B (Miri-confirmable), D (data races) | `rustup +nightly component add miri` |
| `cargo-kani` | B (Kani harnesses), C, G, I | `cargo install --locked kani-verifier; cargo kani setup` |
| `cargo-fuzz` (nightly libfuzzer) | F, supplementary C/D | `cargo install cargo-fuzz; rustup install nightly` |
| `loom` (crate dep, not CLI) | D | added as `dev-dependency` per harness |
| `rudra` | B (primary lint pass) | (out-of-tree; flag MISSING if unavailable) |
| `cargo-audit` | H | `cargo install cargo-audit` |
| `cargo-deny` | H | `cargo install cargo-deny` |
| `cargo-geiger` | H (unsafe-density signal) | `cargo install cargo-geiger` |
| Clippy (stable) | B10, E01, E04, H02 | bundled with rustup; no install needed |

Exit code 2 (missing tools) → `AskUserQuestion`: install / skip-with-coverage-cap / cancel. **Skip-with-cap** means missing tools' groups are auto-INCONCLUSIVE.

Orchestrator sets:
```bash
export RUST_BACKTRACE=1
export PATH="$HOME/.cargo/bin:$PATH"
```

## Input — Stage-2 candidate finding format

Per finding, the Stage 2 angle subagent emits the standard FINDING block (per `shared-rules.md`) PLUS the infra-mode-specific verification-plan extension:

```yaml
# Standard FINDING fields (shared across modes)
crate: <name>
module: <path>
function: <function_name>
bug_class: <kebab-tag>
group_key: <crate>::<module>::<function>|<bug_class>
location: <file>:<line-range>
path: <caller> → <function> → <state change> → <impact>
proof: <concrete values, traces, or state sequences>
description: <one-sentence root cause>
fix: <one-sentence suggestion>
weaponization_check: { ... }      # mode-independent
reachability_check: { ... }       # mode-independent
code_comment_scan: { ... }        # mode-independent
docstring_disclaimer: <quote OR "none">
claimed_severity: <preliminary; Stage 4 will determinize via Impact × Reachability matrix>
confidence: 0..100

# infra-mode-specific verification plan
verification_plan:
  vector_id: <e.g., A01, C02, D01 — from dlt-infra-attack-vectors.md>
  vector_group: <A | B | C | D | E | F | G | H | I>
  primary_tool: miri | kani | loom | cargo-fuzz | cargo-audit | clippy | manual
  golden_signature: "<exact substring the tool must emit — copied from the vector catalogue entry>"
  miri_flags: ["-Zmiri-tag-raw-pointers", ...]  # if applicable
  kani_unwind: <N or null>                      # if applicable
  harness_suggestion: "<plain-English what the harness should do>"
```

The `vector_id` MUST match an entry in `dlt-infra-attack-vectors.md`. The `golden_signature` MUST be the exact string from that catalogue entry — angles do not invent signatures.

## Tool Selection Table (by Vector Group)

| Group | Primary tool(s) | Fallback | Automation level |
|-------|----------------|----------|------------------|
| **A — Memory Corruption & UB** | Miri (nightly) | Kani for arithmetic-related UB | Fully automatic via `cargo miri test` |
| **B — Unsound Abstractions** | Rudra (if available); else Kani + manual contracts | Loom for Send/Sync issues | Semi-automatic; harness needed |
| **C — Integer Overflow** | Kani with `--unwind` | libfuzzer with overflow-checks | Fully automatic harness-gen |
| **D — Concurrency** | Loom (or Miri `-Zmiri-detect-data-races`) | Manual schedule injection | Automatic for small models |
| **E — Cryptography** | Custom test harness + Clippy lints | `dudect` for timing | Harness-gen + manual script |
| **F — DoS / Resource Exhaustion** | libfuzzer (`cargo-fuzz`) + `timeout` | Static analysis (manual) | Fuzzer harness auto-generated |
| **G — Error Handling & State Machine** | Kani for state invariants | Loom for re-entrancy | Harness needed |
| **H — Supply Chain** | `cargo audit`, `cargo deny`, Clippy | Manual call-graph reachability | Fully automatic |
| **I — DLT-Specific Logic** | `proptest` or Kani model (`stateright` optional) | Fuzzer | Harness needed |

## Harness Generation (LLM-assisted, orchestrator-verified)

For each finding, the orchestrator spawns a Sonnet subagent with this template:

```
You are generating a Rust verification harness for Argus Stage 3 (infra mode).

## Target finding
{FINDING block}

## Vector + golden signature
Vector: {vector_id} — {vector_title}
Detection tool: {primary_tool}
Golden signature: "{golden_signature}"

## Requirements
1. Harness MUST compile via `cargo check` against the target crate.
2. Harness MUST call the target function with inputs designed to trigger the bug.
3. Harness format depends on tool:
   - Miri: #[test] inside a `#[cfg(test)]` module. May use unsafe. Include `#![feature(...)]` only if needed.
   - Kani: #[kani::proof] function with `kani::any()` for symbolic inputs and `kani::assert!` / `assert!` for properties.
   - Loom: `loom::model(|| { ... })` wrapper around the test body.
   - cargo-fuzz: `libfuzzer_sys::fuzz_target!(|input: &[u8]| { ... })`.
   - cargo-audit / cargo-deny: NO harness; the tool runs against Cargo.toml directly.
4. The expected outcome under buggy code: the tool emits the golden signature.
5. The expected outcome under fixed code (if known): the tool reports clean / passes.

## Output
A single Rust file (and any `Cargo.toml` additions like `dev-dependencies`) saved to:
  $RUN_DIR/3-verification/F-NN/harness.rs
  $RUN_DIR/3-verification/F-NN/Cargo.toml.fragment (if any)

Return only the file contents.
```

The orchestrator writes the harness, runs `cargo check` against it. If it fails, retry **once** with the compiler error as feedback. After three total failures, mark the finding **INCONCLUSIVE** with reason `harness_compilation_failed`. The finding moves to `manual-queue.md`; the harness so far is saved for the human reviewer.

## Execution Templates

All commands run with `RUST_BACKTRACE=1` and stderr captured separately from stdout. Output is saved to `$RUN_DIR/3-verification/F-NN/{tool}.stderr` and `.stdout`.

### Miri (Group A, parts of B, D-data-races)

```bash
cd <crate-root>
cargo +nightly miri test -- <test_function_name> \
    --nocapture
# with MIRIFLAGS set per finding (most common flags):
MIRIFLAGS="-Zmiri-tag-raw-pointers -Zmiri-check-number-validity -Zmiri-detect-data-races -Zmiri-symbolic-alignment-check" \
    cargo +nightly miri test -- <test_function_name> --nocapture
```

**Golden-signature check**: `grep -F "<golden_signature>" stderr`. Exact substring; the vector catalogue stores the canonical Miri error string per A-vector.

Timeout: 10 minutes default.

### Kani (Groups B, C, G, I)

```bash
cd <crate-root>
cargo kani --harness <harness_function_name> \
    --enable-unstable \
    --unwind <N>          # N from verification_plan.kani_unwind
    --restrict-vtable     # optional perf flag
```

**Golden-signature check**: Kani output contains `Failed Checks:` followed by an assertion-violation counterexample. Verdict: CONFIRMED. If Kani output contains `VERIFICATION:- SUCCESSFUL`, verdict: DISPROVED (within unwind bound).

Timeout: 10 minutes default. If Kani exhausts unwinding without verdict, INCONCLUSIVE with reason `kani_unwind_exhausted`.

### Loom (Group D, plus B Send/Sync schedule-dependent cases)

```bash
cd <crate-root>
RUSTFLAGS="--cfg loom" cargo test --test <loom_test_name> --release -- --nocapture
```

Loom panics on detected deadlock or assertion failure. Check stderr for `deadlock` or `panicked at`. Loom exhausts schedules deterministically; if no failure found within the schedule budget (controllable via `LOOM_MAX_PREEMPTIONS` env var), verdict: DISPROVED.

Timeout: 2 minutes default. Wider preemption budgets push timeout to 10 min.

### libfuzzer (Group F primary; supplementary for C/D)

1. Subagent generates `fuzz/fuzz_targets/<name>.rs` with `libfuzzer_sys::fuzz_target!`.
2. Build + run:
```bash
cd <crate-root>
cargo +nightly fuzz run <fuzz_target_name> -- -max_total_time=300 -timeout=10
```

**Golden-signature check**: stderr contains `ERROR: libFuzzer: deadly signal` (panic), `out-of-memory` (OOM), or `timeout` (slow path). The crashing input is saved to `fuzz/artifacts/<target>/crash-<hash>`.

Default time budget: 5 minutes per target. CONFIRMED requires a crash artifact present.

### cargo-audit / cargo-deny (Group H — no harness)

```bash
cd <crate-root>
cargo audit --json > $RUN_DIR/3-verification/F-NN/cargo-audit.json
cargo deny check 2>&1 > $RUN_DIR/3-verification/F-NN/cargo-deny.txt
```

**Golden-signature check** (3 sub-steps, ALL required for CONFIRMED — tightened v0.3.2):

**Step 1 — Dep-graph match**. JSON output contains `"id": "RUSTSEC-YYYY-NNNN"` for the cited advisory ID. Pass → step 2. No match → DISPROVED.

**Step 2 — Reachable from non-dev path**. `cargo tree -i <crate>` shows the vulnerable crate is reachable from a non-`[dev-dependencies]` path. Pass → step 3. Test-only / dev-dep-only → INFORMATIONAL severity cap.

**Step 3 — Advisory-body caveat check (MANDATORY, new in v0.3.2)**. Fetch the advisory body from `https://rustsec.org/advisories/RUSTSEC-YYYY-NNNN.html` (or `https://github.com/rustsec/advisory-db/blob/main/crates/<crate>/RUSTSEC-YYYY-NNNN.md`). Parse for **affected/unaffected conditions**. Common caveat patterns:

- *"Applications that do not use X are not affected"* → grep the in-scope code for `X` callers. Zero hits → **INCONCLUSIVE**, not CONFIRMED.
- *"Only triggers when feature flag Y is enabled"* → check `Cargo.toml` `[features]` + dependency feature sets. Feature off → **INCONCLUSIVE**.
- *"Requires config option Z"* → grep for the config setter. Default config → **INCONCLUSIVE**.
- *"Only impacts users who call API W with attacker-controlled input"* → trace the API's call sites + attacker-control via `reachability.py`. No path → **INCONCLUSIVE**.

Only when **no caveat applies OR the codebase falls into the "affected" partition** is the verdict **CONFIRMED**.

**Canonical motivating case**: F-07 in the 2026-05-12 monero-oxide run cited RUSTSEC-2026-0104 (rustls-webpki CRL-parse panic). cargo-audit matched (step 1), dep-graph showed `monero-oxide → simple-request → hyper-rustls → rustls-webpki 0.103.10` from `[dependencies]` not `[dev-dependencies]` (step 2). The pre-v0.3.2 spec declared CONFIRMED here. But the advisory body said *"Applications that do not use CRLs are not affected"* — and a grep of the dep tree for `with_crls` / `RevocationList` / `verify_crl` / `crl_provider` returned **zero hits**. The bug was unreachable; the F-07 verdict was over-claim. Live E2E verification by Codex confirmed the over-claim and refuted submission. v0.3.2 adds step 3 to catch this class before SUBMIT.

#### Implementation notes

- WebFetch the advisory URL ONCE per finding; cache result keyed by RUSTSEC ID.
- LLM extracts the caveat clause from the advisory's "Description" / "Patched" / "Workaround" / "Aliases" sections — looks for phrases matching the patterns above.
- The cited trigger API (e.g., `with_crls`) becomes a new mandatory `verification_plan.caveat_check` field:

```yaml
verification_plan:
  vector_id: H01
  vector_group: H
  primary_tool: cargo-audit
  rustsec_id: RUSTSEC-2026-0104
  golden_signature: '"id": "RUSTSEC-2026-0104"'
  caveat_check:
    advisory_caveat: "Applications that do not use CRLs are not affected"
    trigger_apis: ["with_crls", "RevocationList", "verify_crl", "crl_provider"]
    grep_command: "grep -rn -E '(with_crls|RevocationList|verify_crl|crl_provider)' --include='*.rs' --include='Cargo.toml'"
    grep_hits_required_for_CONFIRMED: yes
    grep_hits_observed: <count>
    caveat_verdict: AFFECTED | UNAFFECTED | UNCLEAR
```

`caveat_verdict: UNAFFECTED` → finding marked **INCONCLUSIVE** with reason `advisory_caveat_excludes_codebase`, NOT CONFIRMED. The finding routes to `_inconclusive.md` + `manual-queue.md`, not SUBMIT.

#### Verdict matrix for Group H

| Step 1 | Step 2 | Step 3 | Verdict |
|--------|--------|--------|---------|
| match | reachable | AFFECTED | CONFIRMED |
| match | reachable | UNAFFECTED | INCONCLUSIVE (`advisory_caveat_excludes_codebase`) |
| match | reachable | UNCLEAR | INCONCLUSIVE (`advisory_caveat_unclear`) — route to manual queue |
| match | dev-only / test-only | any | INFORMATIONAL severity cap |
| no match | n/a | n/a | DISPROVED |

#### Why this matters

Without step 3, Group H produces submission-grade false positives on every supply-chain CVE whose advisory has a caveat. RustSec advisories routinely contain caveats — feature flags, API call requirements, config-dependent triggers, deployment-mode exclusions. Treating cargo-audit match + dep-graph reachability as sufficient evidence is the same class of error as treating Miri's "the unsafe block compiled" as evidence the unsafe block is sound. Tool output requires interpretation against the advisory's stated affected/unaffected partition.

#### What this does NOT close

- Advisories without explicit affected/unaffected clauses default to AFFECTED (assume worst case). This is conservative — better to over-CONFIRM and let the user manually rule out than to under-CONFIRM and miss a real CVE.
- LLM extraction of caveat clauses is best-effort. Ambiguous advisory text → `caveat_verdict: UNCLEAR` → manual queue.
- The trigger-API grep is naive (same caveat as `reachability_check` in Stage 2 — misses macro / trait-object / FFI dispatch). For high-stakes findings, fall back to `rust-analyzer` callgraph (Stage 4 scripts/reachability.py).

### Cryptography harnesses (Group E)

Custom Rust test executed under `timeout 30`:
- **Constant-time** (E02, E08): use `dudect-bencher` or custom `criterion` benchmark comparing two input classes (matching vs near-matching). Flag if mean timing difference exceeds threshold (default: 5% with 99% confidence).
- **Zeroisation** (E03): after the secret-holding type drops, scan a buffer for the key pattern (platform-specific via `mprotect` + `memchr`; flag INCONCLUSIVE if not feasible on the target platform).
- **Nonce reuse** (E05): static-analyze the signing fn for RNG provenance; if non-deterministic and not RFC 6979, run with controlled RNG and check for `(r)` collision across signatures.

**Golden-signature check**: per-test pass/fail; CONFIRMED if the test asserts the misuse.

### Clippy security lints (B10, E01, E04, H02)

```bash
cd <crate-root>
cargo clippy --all-targets --message-format=json -- \
    -W clippy::improper_ctypes \
    -W clippy::missing_safety_doc \
    -W clippy::cast_possible_truncation \
    -W clippy::cast_sign_loss \
    -W clippy::cast_possible_wrap \
    -W clippy::transmute_int_to_float \
    -W clippy::transmute_ptr_to_ref \
    > $RUN_DIR/3-verification/F-NN/clippy.json
```

**Golden-signature check**: JSON parse; the cited lint name appears with `level: warning` or `error`.

## Verdict Assignment Rules (TIGHTENED v0.3.3 — Tier-1-live-e2e mandatory for CONFIRMED)

**v0.3.3 architectural change**: tool output alone is no longer sufficient for CONFIRMED. Every CONFIRMED verdict requires a **Tier-1-live-e2e artifact** per `references/e2e-test-discipline.md` — a runnable test that exercises the in-scope codebase's actual code path (not just the cited buggy library in isolation) and observes the bug's effect.

| Verdict | Conditions |
|---------|-----------|
| **CONFIRMED** | (1) Tool output contains the exact `golden_signature` substring AND (2) no false-positive pattern is matched (`infra-fp-allowlist.md`) AND (3) advisory-body caveat check passes (Group H — `caveat_verdict: AFFECTED`) AND **(4) Tier-1-live-e2e artifact exists at `$RUN_DIR/3-verification/F-NN/e2e/` with `e2e_verdict: REPRODUCED`** per `e2e-test-discipline.md`. All four required. |
| **DISPROVED** | Kani returns `VERIFICATION:- SUCCESSFUL` within the cited unwind bound, OR Loom exhausts all schedules without failure, OR cargo-audit returns no advisories matching the cited ID, OR Miri runs the harness without emitting UB, OR Tier-1-live-e2e artifact reports `e2e_verdict: UNREACHABLE` (the bug is real in isolation but the in-scope code never reaches the cited trigger). **Bounded correctness only** — DISPROVED in Kani means "no violation within unwind = N", not absolute. |
| **INCONCLUSIVE** | Any of: harness compilation failure (after 3 retries), tool timeout, golden signature not found but tool reports unrelated error, finding's primary_tool is `manual` (E02, I10, etc.), required tool was unavailable at toolchain check, Tier-1-live-e2e artifact reports `e2e_verdict: INCONCLUSIVE`, OR advisory caveat-check returned UNCLEAR. |

If a finding is **CONFIRMED**, both the tool's raw output (`tool-evidence.log`) AND the Tier-1-live-e2e artifact directory (`e2e/`) are saved and linked from the Stage 8 submission report.

### The cargo-audit-only verdict is no longer CONFIRMED

Pre-v0.3.3, Group H findings could reach CONFIRMED on cargo-audit match + dep-graph reachability alone. v0.3.2 added the advisory-caveat check (step 3). v0.3.3 adds the live E2E check (step 4): a project that depends on the in-scope crate, exercises the cited API, and observes whether the bug fires.

For the F-07 / RUSTSEC-2026-0104 motivating case:
- Step 1 (cargo-audit RUSTSEC match) ✓
- Step 2 (dep-graph reachable from `[dependencies]`) ✓
- Step 3 (caveat: "Applications that do not use CRLs are not affected" → grep for `with_crls` → zero hits) ✗ → INCONCLUSIVE under v0.3.2, before reaching step 4
- Step 4 would be: build a test project depending on `simple-request` exactly as monero-oxide depends on it, make a TLS handshake against a malicious server, observe whether the panic fires. The E2E pattern from `e2e-test-discipline.md` § "RPC / API node" or § "Wallet / signing library" applies depending on classification.

Under v0.3.3, F-07 is DISPROVED at step 3 (zero-hit caveat check). If step 3 had been ambiguous, step 4 would have given the definitive verdict. Either way the user is protected from the over-claim.

### Resolution of pre-v0.3.3 INCONCLUSIVE-and-needs-E2E findings

Findings that were INCONCLUSIVE pre-v0.3.3 because harness writing wasn't required automatically — these are picked up by the **REFINE auto-loop** at Stage 8.5 (see `references/refine-loop.md` Pattern R3). The loop builds the E2E harness, runs it, and resolves the finding:

- E2E REPRODUCED → re-enters pipeline at Stage 4 with the harness as evidence; auto-advances to SUBMIT.
- E2E UNREACHABLE → DISCARD with reason `e2e-proved-unreachable`.
- E2E INCONCLUSIVE → stays in REFINE with the loop's note; manual review.

## Integration with Stage 4 (Impact Analysis)

Only **CONFIRMED** findings advance to Stage 4. **DISPROVED** findings are recorded in `$RUN_DIR/3-verification/_disproved.md` with the tool output. **INCONCLUSIVE** findings are listed in `$RUN_DIR/3-verification/_inconclusive.md` + `$RUN_DIR/manual-queue.md` for optional human review; they never auto-advance.

This is the load-bearing simplification vs SC mode: there is no Pass A invalidator scan, no Pass B issue-specific generation, no Pass C symmetric judge for tool-confirmable findings. The tool's output IS the verdict.

For groups where tool coverage is incomplete (Group F partial — some logic DoS isn't fuzzer-confirmable; Group E partial — some side-channels aren't tool-detectable; Group I partial — some DLT-specific properties need `stateright` models not auto-generatable), the INCONCLUSIVE bucket is the honest answer. A human reviewer decides whether to escalate.

## Cost / Time Budget (per finding)

| Step | Subagent calls | Tool wall-clock | Notes |
|------|----------------|-----------------|-------|
| Harness generation | 1-2 Sonnet | n/a | retries cost 1 extra call each, capped at 3 |
| Miri | 0 | 30s – 3 min | Group A typical |
| Kani | 0 | up to 10 min | Group C / G / I; depends on unwind |
| Loom | 0 | up to 2 min | Group D; LOOM_MAX_PREEMPTIONS=3 default |
| libfuzzer | 0 | 5 min | Group F; configurable via `max_total_time` |
| cargo-audit | 0 | < 10s | Group H |
| Cryptography custom | 0-1 Sonnet | 30s – 5 min | Group E; some manual |

**Total Stage 3 wall-clock for 10 findings, parallelised**: ~20-30 min.

## Gap: Manual-Only Vectors

The following vectors are not fully automatable as of v0.3.0-alpha; they default to INCONCLUSIVE and route to manual review:

- **E02** non-constant-time comparison (requires `dudect` setup + platform-specific timing)
- **E03** missing zeroisation (platform-specific memory scan after drop)
- **E08** side-channel via early-exit (timing-distinguisher setup)
- **G07** timing assumption on block time (judgmental)
- **I09** smart-contract VM sandbox escape (requires custom Wasm fuzzing harness per VM)
- **I10** RPC info-leak (subjective social-engineering analysis)

The tool will not make a claim it cannot prove. Manual queue exists for these cases.

## False-positive allowlist

`references/infra-fp-allowlist.md` (to be populated during v0.3.0 calibration runs) holds known Miri / Kani false positives — e.g., Miri's noisy reports on FFI boundaries that are sound by external `# Safety` contract. When the golden signature matches one of these patterns, verdict is INCONCLUSIVE not CONFIRMED.

This file starts empty; entries are added based on real run experience. Each entry: `tool`, `signature_substring`, `false_positive_reason`, `confirmed_by`.

## Per-finding output schema

`$RUN_DIR/3-verification/F-NN/verdict.md`:

```markdown
# F-NN Stage 3 verdict (infra mode)

- **finding**: <title>
- **vector_id**: <A01 | C02 | ...>
- **primary_tool**: <miri | kani | loom | cargo-fuzz | cargo-audit | clippy | manual>
- **status**: CONFIRMED | DISPROVED | INCONCLUSIVE
- **harness_path**: $RUN_DIR/3-verification/F-NN/harness.rs (if applicable)
- **tool_command**: <exact invocation run>
- **golden_signature**: "<from vector catalogue>"
- **golden_signature_matched**: yes | no
- **evidence_path**: $RUN_DIR/3-verification/F-NN/tool-evidence.log (if CONFIRMED)
- **inconclusive_reason**: <if INCONCLUSIVE: harness_compilation_failed | tool_timeout | tool_unavailable | manual_vector | other>

## Tool output excerpt (first 200 lines of stderr)

```
<tool stderr captured>
```

## Reproduction

```bash
cd <crate-root>
<exact tool command>
```

## Next stage

If CONFIRMED → Stage 4 (Impact × Reachability matrix; see `infra-severity-matrix.md`, Chunk 4).
If DISPROVED → terminal; finding dropped with evidence preserved.
If INCONCLUSIVE → manual review queue; not auto-submitted.
```

## SCIP-backed callgraph (v0.4.1)

`scripts/build-callgraph.sh` produces a semantic callgraph from `rust-analyzer scip` (or `scip-rust`) output that `scripts/reachability.py` consumes. When this script is the callgraph source, downstream FINDINGs are eligible for the `[LSP-TRACE]` evidence tag (per shared-rules.md § Evidence-quality tags), which clears the `[CODE-TRACE]`-only floor on HIGH / CRITICAL infra findings.

See [`scip-callgraph.md`](scip-callgraph.md) for full schema, usage, and limitations.

### Quick reference

```bash
# Stage 1 Phase B (surface enumeration) builds the callgraph:
bash $SKILL_DIR/scripts/build-callgraph.sh <project-root> \
     --output $RUN_DIR/1-protocol-map/callgraph.json
```

Requires one of:
- `rustup component add rust-analyzer` (preferred, bundled with rustup)
- `cargo install scip-rust` (standalone)

`scripts/doctor.sh --check-rust` reports SCIP-indexer availability.

### Optional external vulnerability-RAG corpus

Argus can also opt into a local vulnerability-RAG endpoint for Stage 4 close-call review, Stage 7 dup-check enrichment, and Stage 6 program triage. Set `ARGUS_EXT_VULN_RAG` to the path of a local RAG server or endpoint script; absent the env var, Argus uses its built-in comparator-citation discipline (`comparator_citation` field per shared-rules.md).

### Degradation behavior

Vanilla Argus (no SCIP indexer installed, no external RAG):

- Stage 3 verification works as documented in this file (Miri / Kani / Loom / cargo-fuzz / cargo-audit) with no external dependency.
- Stage 4 close-call review uses Argus's existing manual comparator-citation discipline.
- Stage 7 dup-check uses Argus's local-only or gh-CLI mode.
- Reachability uses `scripts/reachability.py` against a grep-extracted callgraph (no `_meta.source: scip` flag) — FINDINGs carry only `[CODE-TRACE]`, so HIGH / CRITICAL infra claims must produce a different mechanical-evidence tag (`[FUZZ-PASS]` / `[NON-DET-PASS]` / `[CONFORMANCE-PASS]` / `[DIFF-PASS]`).

Argus runs are reproducible without either capability; they accelerate and enrich them when present.

## Coordination with `audit-modes.md`

This file is loaded in `infra` mode only. In SC mode, Stage 3 reads `poc-standards.md` (Tier-1/2/3/4 ladder + RPC discovery) and Stage 4 runs the full Pass A/B/C/D adversarial review per `adversarial-review.md`. The two modes do not share Stage-3/4 implementations; they share only the mode-independent FINDING schema and the Stage 0/1/7/8 routing.

## What this design closes from `ARGUS_AUDIT.md`

- **C-2** (judge-acceptability not truth) — replaced by tool-confirmation for ~30-40% of bugs; the remaining 60-70% route to manual queue rather than receive a judged verdict.
- **C-3** (orchestrator single-point-of-failure) — tools are independent of orchestrator confirmation; harness compilation is the only orchestrator-judgment step, and that's a binary `cargo check` outcome.
- **S2-8** (`bug_reachability_proof` unverifiable) — the tool's golden-signature match IS the reachability proof for tool-confirmable vectors.
- **S3-1** (80% certainty floor arbitrary) — replaced by CONFIRMED / DISPROVED / INCONCLUSIVE; certainty is binary or unknown, not graded.
- **S4-1** through **S4-9** (every Pass A/B/C/D weakness) — N/A in infra mode; those passes are not run.

## What this design does NOT close

- **C-1** (calibration uncalibrated) — only partially closed. Stage 4 Impact × Reachability matrix (Chunk 4) replaces Pass D English rubric, but the matrix itself is hand-built; until run against the W3SA + Scout + future-infra-corpus, it's heuristic-calibrated.
- **H-1** (vector library organization) — the new 9-group / 77-vector catalogue is more orthogonal than V1-V132 but is still hand-curated; no guarantee a real codebase's bugs map cleanly.
- **S2-4** (`reachability_check` naive grep) — still applies. Caller-graph extraction via `rust-analyzer` is a v0.3.0+ candidate, not closed by Stage-3 verification.
- Manual-vector gap (E02, E03, E08, G07, I09, I10) — INCONCLUSIVE is honest but doesn't generate findings for these classes automatically.
