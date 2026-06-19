# ZK Circuit Soundness — Methodology Change Proposals

> **Date**: 2026-06-05
> **Based on**: research dossier v0.6.2 (24 bug classes, 70+ sources)
> **Target agent**: `references/hacking-agents/infra/zk-circuit-soundness-agent.md` (336 lines, CHECK 1-19, J01-J16)

---

## Coverage Audit (pre-proposal)

Of the 24 bug classes in the dossier, most are now covered by CHECK 1-19 (added in v0.6.2). This audit identifies ONLY the genuinely uncovered methodology:

| Dossier Class | Current Coverage | Gap |
|---------------|-----------------|-----|
| C1 (assigned-not-constrained) | CHECK 1 — multi-framework table + UCP | None |
| C2 (decorative gadget output) | CHECK 7 | None |
| C3 (range/canonical) | CHECK 6 + CHECK 13 (subgroup scalar) | **Three-step limb-loop procedure not stated** |
| C4 (missing binary/selector) | CHECK 2 | None |
| C5 (output not instance-bound) | CHECK 10 | None |
| C6 (custom gate unenforced) | CHECK 2 | None |
| C7 (unconstrained inverse) | CHECK 8 | None |
| C8 (host-assertion) | CHECK 9 | None |
| C9 (non-unique output) | CHECK 12 | None |
| C10 (TCCT operand-set diff) | CHECK 11 | None |
| C11 (Frozen Heart FS) | CHECK 15 | None |
| C12 (stale-state/recursion ordering) | CHECK 3 (conditional gaps) | **Recursion-layer completeness flags not explicit** |
| C13 (commitment fold-to-zero) | CHECK 17 | None |
| C14 (PCS/FRI verifier) | CHECK 18 | None |
| C15 (sponge domain separation) | None | **Entirely absent** |
| C16 (zkVM operand aliasing) | None | **Entirely absent** |
| C17 (unused public input) | CHECK 10 (included) | None |
| C18 (EC exceptional-case) | CHECK 14 | None |
| C19 (point validity 3-leg) | CHECK 13 | None |
| C20 (subgroup scalar aliasing) | CHECK 13 (included) | None |
| C21 (VK degeneracy) | CHECK 19 | None |
| C22 (unverified eval) | CHECK 16 | None |
| C23 (over-constraint) | None — anti-patterns even say "panics → no finding" | **Entirely absent; anti-pattern is wrong for Argus targets** |
| C24 (Noir Brillig) | CHECK 1 (operator table row only) | **No procedure: branch elimination, binding assert completeness** |
| Tooling | Phase 5 knows only MockProver | **Decision rule + golden signatures per framework absent** |
| Dep-tree audit | None | **cargo-audit pre-filter absent** |

6 proposals follow. Total estimated line impact: +95 / -5.

---

### Proposal 1: Limb-loop binding sub-procedure (extend CHECK 6)

- **Type**: extend-check
- **Evidence**: OpenVM CVE-2025-46723 (AUIPC top-limb kept 8-bit not 6-bit → BabyBear field-wrap; first-party `auipc/core.rs` verified this pass); 0xPARC #1/#2/#9/#18; RareSkills AliasCheck; ICME small-fields background
- **What changes**: Add a sub-section under CHECK 6 titled "Limb-loop binding (re-derive, do not grep)" with the three independent steps from the dossier §C3:
  1. **Index-domain re-derivation**: for a per-limb loop using `.enumerate()`, write down the actual index sequence produced, accounting for `skip`/`rev`/`filter`/`zip` transformations. If a selector keyed on `i == last` is never reached, the MSB limb falls through to the default (full-width) check.
  2. **Residual-width binding**: independently compute `MSB_WIDTH = TARGET_BITS - (NUM_LIMBS-1) * CELL_BITS`. Confirm a check of exactly that width is applied to the MSB limb. Check for a scale-factor multiply (`2^(NUM_LIMBS*CELL_BITS - TARGET_BITS)`) feeding a shared CELL_BITS lookup — verify the exponent is exact.
  3. **Max-sum < modulus**: set every limb to its CHECKED maximum, compute `max_sum`, and assert `max_sum < 2^TARGET_BITS` AND `max_sum < p` (the native field modulus). On small fields (BabyBear ~31b, Mersenne31 ~31b, Goldilocks ~64b) there is almost no slack.
- **Lines added/removed**: +15 / -0
- **Framework scope**: all (especially crucial for small-field provers: Plonky2/3, OpenVM)
- **Anti-bloat gates**:
  - [x] Methodology not pattern — teaches HOW to re-derive limb binding, not to look for a specific `skip(1)` bug
  - [x] Evidence-backed — OpenVM CVE-2025-46723 + 0xPARC catalogue
  - [x] No duplication — CHECK 6 covers generic range-check discipline but does not state the three-step limb-loop procedure; CHECK 13 covers subgroup-order scalar bound (C20) which is a different bound (l < r)
  - [x] Line budget OK — 336 + 15 = 351, still reasonable
  - [x] Generalizable — applies to every circuit with value decomposition into limbs

---

### Proposal 2: zkVM operand/state aliasing case-matrix (new CHECK 20 in Phase 2)

- **Type**: new-check
- **Evidence**: RISC Zero CVE-2025-52484 ($50k bounty — missing rs1==rs2 constraint in any 3-register instruction → full soundness break); SP1 recursion `is_complete` unconstrained in first layer (GHSA-c873-wfhp-wx5m); zkSync Era recursion/aggregation soundness bug (~$1.9B forged-withdrawal surface, ChainLight); ARGUZZ differential fuzz methodology (arXiv 2509.10819)
- **What changes**: Add CHECK 20 under Phase 2 with this procedure (from dossier §C16):
  ```
  Do NOT start from a memorized register list. DERIVE the case matrix from the decoder:
  1. For every value the decoder routes based on a decoded field, partition the
     input space by which decoded fields CAN BE EQUAL (rs1==rs2, rd==rs1, address
     collisions, opcode boundaries).
  2. For each partition cell, verify a constraint pins the routed value (not just
     the case where all fields differ). The bug hides in the partition cell where
     the uniform witness generator handles correctly but the constraint set omits.
  3. For recursion/aggregation verifiers: confirm a permutation index used to SET
     a bitmask is not also used to CHECK it (no-op); array accesses by
     prover-chosen index are bounds-constrained; a completeness flag is ASSERTED
     (assert_complete), not assumed, in EVERY layer.
  ```
  Mechanical evidence: differential fuzz (ARGUZZ-style) — run the honest VM and a constraint-only model on the same program where two decoded fields alias; constraint-system acceptance of a trace the reference VM rejects = soundness break.
- **Lines added/removed**: +25 / -0
- **Framework scope**: zkVM circuits only (RISC-V, EVM, Move VM, custom ISAs). Tag as **[zkVM only]**.
- **Anti-bloat gates**:
  - [x] Methodology not pattern — teaches HOW to derive the case matrix from the decoder (partition input space by field equality), not what to look for ("check rs1==rs2"). The RISC-V register list is never named.
  - [x] Evidence-backed — CVE-2025-52484 + SP1 GHSA-c873-wfhp-wx5m + zkSync Era
  - [x] No duplication — CHECK 3 covers generic conditional/selector gaps but the VM-decode partition matrix and recursion-layer completeness flags are a distinct discipline not addressed by any existing check
  - [x] Line budget OK — 336 + 25 = 361
  - [x] Generalizable (or correctly scoped) — correctly tagged as [zkVM only]

---

### Proposal 3: Over-constraint / honest-prover lockout (new CHECK 21 + anti-pattern fix)

- **Type**: new-check + guidance-update
- **Evidence**: RISC Zero `opLH` typed 16-bit half-word as `NondetU8Reg` → honest loads >255 unprovable (Veridise VUL-005, High); zkFuzz Algorithm 1: 258/452 circuits over-constrained under `--constraint_assert_disabled`; the dossier explicitly states Argus targets (Halo2/arkworks/bellman) permit over-constraint by construction (assignment and constraint authored as separate statements), unlike Circom default (`===` auto-asserts)
- **What changes**:
  1. Add CHECK 21 under Phase 2 with the dual-of-under-constraint procedure (dossier §C23):
     ```
     Recover the SPEC domain for the cell independently (what values must it represent?).
     Recover the CONSTRAINT domain (what values satisfy the actual range/width/equality?).
     Compute SPEC \ CONSTRAINT. If non-empty, name a concrete honest value in the gap
     (the boundary value just above the constraint's max is strongest).
     Mechanical: INVERT the MockProver expectation — assign an HONEST boundary witness;
     Err(ConstraintNotSatisfied) on an honest witness = over-constraint PROOF.
     Severity discipline: liveness/DoS (at most High), NEVER soundness/counterfeiting.
     ```
  2. Fix the anti-patterns section: replace "panics → no finding" with the correct framing — a host panic on an honest witness is a liveness finding; only a panic on a path a correct prover never executes is benign.
- **Lines added/removed**: +20 / -5 (replacing one anti-pattern bullet)
- **Framework scope**: Halo2/arkworks/bellman/plonky2-3 (all Argus targets). Circom DEFAULT is immune (`===` auto-inserts matching assignment).
- **Anti-bloat gates**:
  - [x] Methodology not pattern — `SPEC \ CONSTRAINT` is a general procedure applicable to any range/width/enforcement, not a specific `NondetU8Reg` check
  - [x] Evidence-backed — RISC Zero VUL-005 (High, verified), zkFuzz 258/452 circuits
  - [x] No duplication — No existing CHECK evaluates over-constraint; the anti-patterns section currently treats it as not-a-finding. This is a CORRECTION, not a duplicate.
  - [x] Line budget OK — 336 + 20 - 5 = 351
  - [x] Generalizable — applies to every circuit where assignment and constraint are separate code paths

---

### Proposal 4: MockProver guidance sharpening (tune Phase 5 + Stage-3 PoC discipline)

- **Type**: guidance-update
- **Evidence**: The dossier §4 states this explicitly — "MockProver cannot detect a MISSING constraint. A green MockProver on the honest witness is ZERO evidence of soundness." This is the single most-cited tooling footgun across all ZK audit reports (ToB Axiom, Veridise, zkSecurity). The current agent says MockProver is "NOT a soundness oracle" in Phase 5 but doesn't explicitly frame the two valid uses: ACCEPT forged witness (under-constraint proof) and REJECT honest boundary witness (over-constraint proof).
- **What changes**: Replace the MockProver caveat paragraph in Phase 5 with tighter guidance:
  ```
  MockProver is a forged-witness ACCEPTANCE oracle and an honest-witness REJECTION
  oracle — NOTHING else. Two valid signals and only two:
  1. UNDER-CONSTRAINT: honest witness passes (meaningless). Forged witness passes → CONFIRMED.
  2. OVER-CONSTRAINT (CHECK 21): forged witness may pass or fail (meaningless).
     Honest boundary witness FAILS → CONFIRMED.
  Any other use of MockProver produces ZERO soundness evidence. A green run on the
  honest witness is the most common false-negative trap in ZK auditing.
  ```
  Also update the Stage-3 PoC table to remove "Tier-1-mock" as a stand-alone target and recast it as a confirmation step within Tier-1-e2e's forged-witness path.
- **Lines added/removed**: +10 / -5 (replacing existing caveat paragraph)
- **Framework scope**: all (Halo2 primarily)
- **Anti-bloat gates**:
  - [x] Methodology not pattern — teaches the correct experimental design (what to vary and what the result means), not a specific check
  - [x] Evidence-backed — ToB Axiom audit, Veridise reports, zkSecurity, dossier §4
  - [x] No duplication — the current text warns MockProver "cannot detect missing constraints" but doesn't enumerate the two valid uses or the over-constraint inversion
  - [x] Line budget OK — net +5 lines
  - [x] Generalizable — applies to all MockProver usage

---

### Proposal 5: cargo-audit pre-filter in Phase 1 inventory

- **Type**: extend-phase
- **Evidence**: RUSTSEC-2021-0075 / CVE-2021-38194 (arkworks `mul_by_inverse` enforced no constraints, fixed 0.3.1); the RustSec advisory-db tracks ZK soundness advisories (halo2 query-collision, gnark CVE-2024-45039, bellperson advisories)
- **What changes**: Add a step 0 to Phase 1 (Circuit inventory):
  ```
  0. Run `cargo audit` (or `cargo deny check advisories`) on the project's
     dependency tree. Flag every advisory with "soundness", "under-constrained",
     "constraint", "proof forgery", or ZK-framework keywords. These advisories
     name the EXACT file/function/version delta — they are the highest-signal
     starting point for manual audit, not background noise.
  ```
- **Lines added/removed**: +5 / -0
- **Framework scope**: all Rust ZK projects
- **Anti-bloat gates**:
  - [x] Methodology not pattern — teaches to pre-filter with `cargo audit`, not to look for a specific advisory
  - [x] Evidence-backed — RUSTSEC-2021-0075, halo2 query-collision advisory
  - [x] No duplication — no existing step runs `cargo audit` or checks the dep tree for known ZK advisories
  - [x] Line budget OK — +5 lines
  - [x] Generalizable — `cargo audit` applies to every Rust project

---

### Proposal 6: Deterministic backend roster with framework decision rule (extend Phase 5)

- **Type**: tool-integration
- **Evidence**: Dossier §4 documents 14 tools with golden signatures; the SoK (USENIX Sec 2024) reports only 5/75 audits used any automated SNARK tool; Picus found an under-constrained SP1 op human audit missed; framework coverage skew is severe (Circom has Picus/circomspect/zkFuzz/Ecne; arkworks/bellman/plonky2-3 have NO off-the-shelf under-constraint detector)
- **What changes**: Replace the current minimal tool table in Phase 5 with a framework-scoped decision rule that tells the agent WHICH tool to invoke per framework and WHAT golden signature to look for:
  ```
  Framework dispatch (pick the strongest available backend):
  - Circom/R1CS: Picus --run → "exit code 9" + counterexample witness pair
    (strongest; mechanizes UCP). Fallback: circomspect (seed-only).
  - Halo2: quantstamp/halo2-analyzer (SMT under-constrained cell); MockProver
    forged-witness for confirmation. Fallback: manual UCP + forged-witness PoC.
  - Noir/ACIR: NAVe (cvc5 SAT model = second valid witness). No other tool exists.
  - arkworks: manual `is_satisfied()` forged-witness PoC (NO off-the-shelf tool).
  - plonky2-3/bellman: manual two-witness PoC (NO off-the-shelf tool).
  - Groth16 verifier: forged-proof harness (A=α, B=β, C=−vk_x) + VK-independence
    assertions.
  ```
  Also add gnark-crypto off-subgroup test vectors (v0.17.0) as ready adversarial inputs for subgroup checks.
- **Lines added/removed**: +20 / -10 (replacing the current 6-row tool table with a 10-row decision table + dispatch logic)
- **Framework scope**: all
- **Anti-bloat gates**:
  - [x] Methodology not pattern — the framework-skew table changes dispatch behavior (the agent now knows which tool to reach for and what its fallback is), not what bugs to find
  - [x] Evidence-backed — dossier §4 (14 tools with golden signatures), SoK data on tool usage rates
  - [x] No duplication — the current table is incomplete and doesn't include a dispatch rule; this replaces it
  - [x] Line budget OK — 336 + 20 - 10 = 346 net
  - [x] Generalizable — dispatches correctly per framework and tells the agent when to expect no tool support

---

## NOT Proposed (with rationale)

| Candidate | Why not proposed |
|-----------|-----------------|
| **C15 sponge/permutation-chip domain separation + terminal anchoring** (Plonky3 PaddingFreeSponge, OpenVM SHA/Keccak terminal) | The methodology to detect this is "read the sponge impl and check domain-sep padding + terminal-row anchoring." This collapses to CHECK 2 (constraint completeness) applied to the sponge chip. The two specific CVEs (GHSA-3g92-f9ch-qjcm, GHSA-9jfx-4f4f-497j) are framework-version-specific implementation bugs, not a generalizable methodology. The dossier's §C15 entry is retained for case law, but a dedicated CHECK would overfit. |
| **C24 Noir/Brillig full procedure** (branch elimination, `is_unconstrained()` compile-time analysis) | CHECK 1's multi-framework table already includes the Noir/Brillig row with the core procedure ("every `unsafe`/`#[oracle]`/`is_unconstrained()` return needs a binding assert that UNIQUELY determines it"). The branch-elimination nuance (`is_unconstrained()` statically deletes the dead branch at compile time) is a ~2-line guidance detail, not a separate CHECK. Add as a brief note to CHECK 1's Noir row if space permits. |
| **C12 recursion-layer completeness flags as standalone CHECK** | CHECK 3 (conditional constraint gaps) covers this generically. The recursion-layer pattern (SP1 `is_complete`, zkSync Era) is a specialization, not a distinct methodology. Proposal 2's zkVM CHECK 20 already captures the key recursion-layer flag in part 3. |
| **New J-series vectors** (J17+) | None of the uncovered classes represent genuinely new attack SURFACES — they represent new DETECTION PROCEDURES for surfaces the vectors already identify. J10-J16 (added v0.6.2) cover the full attack-vector taxonomy. New CHECKs do not require new vectors. |
| **Noir framework section** | Noir is already in the CHECK 1 framework table. A dedicated framework section would duplicate the operator table and the C24 nuances are light enough to stay as inline notes. |

---

## Summary

| # | Proposal | Type | Lines | Priority | Recommended for immediate? |
|---|----------|------|-------|----------|---------------------------|
| 1 | Limb-loop binding sub-procedure | extend CHECK 6 | +15 | High | YES |
| 2 | zkVM operand aliasing (CHECK 20) | new-check | +25 | High | YES |
| 3 | Over-constraint (CHECK 21 + anti-pattern fix) | new-check + fix | +20 / -5 | High | YES |
| 4 | MockProver guidance sharpening | guidance-update | +10 / -5 | Critical | YES |
| 5 | cargo-audit pre-filter | extend Phase 1 | +5 | Medium | YES |
| 6 | Backend roster + framework dispatch | extend Phase 5 | +20 / -10 | Medium | YES |

**Total line impact**: +95 / -20, net ~75 new lines. Final file: ~411 lines.

**All 6 proposals are recommended for immediate implementation.** Rationale:

1. **Proposal 4 is the single highest-ROI change** (8 lines of text to prevent the most common ZK auditing false-negative). Fix it first.
2. **Proposals 2 and 3 add coverage for two entire bug classes** (C16, C23) that currently have ZERO detection procedure. Both are backed by published CVEs with bounties >$50k and published audit reports.
3. **Proposal 1 makes CHECK 6 actionable on the OpenVM class** — without the three-step procedure, the agent would see per-limb range checks and mark them "done."
4. **Proposals 5 and 6 change dispatch behavior** (what the agent reaches for, in what order). They don't add methodology but they make existing methodology tractable by telling the agent what tools exist per framework and what their golden signatures are.

The file grows from 336 to ~411 lines (+75, ~22% growth). This is within bounds for a domain this deep (24 bug classes, 6 frameworks, 14 tools). Future consolidation candidates: the multi-framework table in CHECK 1 could be compressed by a ~8-line framework-operator summary line if space is tight.
