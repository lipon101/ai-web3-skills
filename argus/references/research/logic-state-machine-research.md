# Logic & State Machine Integrity — Research Dossier

> **Feeds**: hacking-agents/infra/logic-state-machine-agent.md
> **Last research pass**: 2026-06-05 · **Sources reviewed**: 9 primary (8 verified advisories/post-mortems + framework docs) · **Generic-pattern classes**: 5
> **Status**: drafted-verified — every retained real-world id was fetched from a primary source confirming BOTH identifier AND mechanism (section 7). Unconfirmable claims dropped or relabeled `[generic pattern]` with no id.
> **WEB-ACCESS: ok**

> **Anchor case (VERIFIED)**: Cosmos SDK `x/group` EndBlocker chain halt — **ISA-2025-002 / GHSA-47ww-ff84-4jrg** (High; affected ≤ v0.50.12 / ≤ v0.47.16; fixed v0.50.13 / v0.47.17). A malicious proposal drives the `x/group` module's **EndBlocker** (block-finalization hook) to return an error; the error during finalization halts the chain. Crucially: "Any set of users that can interact with the groups module could introduce this state." The defining infra state-machine pattern is here — a sub-operation inside the atomic block-finalization step fails, and because finalization is all-or-nothing, every honest validator fails identically on the same block → deterministic network-wide halt. A sibling advisory, **ASA-2025-003 / GHSA-x5vx-95h7-rv4p**, is the same class with a concrete arithmetic trigger: a malicious group proposal causes a **division by zero**, halting the chain. Two independent verified instances in the same module confirm the class is real and recurring, not theoretical.

---

## 0. Calibration headline

Logic & state-machine bugs are the most common infra finding class AND the hardest to detect mechanically. Unlike arithmetic (Kani finds overflow counterexamples) or memory safety (MIRI finds UB), logic bugs are about INVARIANTS — properties that should always hold but have no runtime assertion. They survive deterministic backends because no backend can check what was never encoded as a check.

The verified incident set clusters into three production-confirmed mechanisms:

1. **Error/panic inside an atomic block-finalization hook → deterministic halt.** The block producer and every validator run the same EndBlock/EndBlocker/finalization code on the same state. If that code can be driven to error or panic by attacker-supplied input, all nodes halt identically. VERIFIED: Cosmos ISA-2025-002 (EndBlocker error), ASA-2025-003 (div-by-zero in proposal handling), CometBFT ASA-2024-011 (out-of-bounds panic on a precommit), CometBFT ASA-2024-001 (governance param change panics validation).
2. **Unvalidated proposer-injected data trusted by consensus accounting.** A proposer injects data (vote extensions, voting power) that downstream consensus logic consumes WITHOUT re-checking against the canonical state machine. VERIFIED: Cosmos ASA-2024-006 (ValidateVoteExtensions infers voting power from proposer-injected extensions), CometBFT ASA-2024-011 (ValidatorIndex not re-validated → array OOB).
3. **State-transition timing / identity gaps.** A state object's identity or its transition window is modeled incorrectly, so two distinct things collapse to one (or a penalty window is escaped). VERIFIED: Solana Dec-2020 stall (two distinct blocks for one slot share a u64 slot-number identity → un-repairable partition), Cosmos ASA-2024-005 (redelegation moves a delegation out of the slashing window — CWE-372 incomplete internal state distinction), Ethereum May-2023 finality loss (old-target attestations at an epoch boundary force repeated state regeneration → resource exhaustion → finality stall, with cross-client divergence).

The tooling gap is critical: model checkers (stateright) exist but require the auditor to FORMALIZE the state machine, which is ~80% of the work. Most logic findings are manual-trace findings. The LLM's advantage is synthesizing the invariant from code + docs and checking it against the implementation — a task no static analyzer does, because static analyzers don't know what the code is supposed to do.

---

## 1. Bug-class taxonomy

Real-instance column rule: an id appears ONLY if section 7 has a fetched URL confirming both the id and the mechanism. Unconfirmed classes are labeled `[generic pattern]` with no id.

| Class | One-line mechanism | Real instance (verified) | Argus coverage |
|-------|--------------------|--------------------------|----------------|
| **L1 Error/panic in atomic finalization hook → halt** | EndBlock/EndBlocker/finalization sub-step errors or panics on attacker input; all nodes fail identically → deterministic halt | Cosmos ISA-2025-002 EndBlocker error halt (GHSA-47ww-ff84-4jrg); Cosmos ASA-2025-003 div-by-zero in group proposal (GHSA-x5vx-95h7-rv4p) | **PARTIAL** — §Silent Result ignore (G01) covers `let _ =`, not the "panic/error inside finalization hook halts everyone" pattern |
| **L2 Unvalidated proposer-injected consensus data** | Proposer injects data consumed by consensus accounting without re-validation against canonical state | Cosmos ASA-2024-006 ValidateVoteExtensions voting-power inference (GHSA-95rx-m9m5-m94v); CometBFT ASA-2024-011 unvalidated ValidatorIndex (GHSA-p7mv-53f2-4cwj) | **NO** — not covered |
| **L3 Out-of-bounds / index panic on untrusted message field** | A message field used as an array/slice index is not bounds-checked before use → panic → node/chain halt | CometBFT ASA-2024-011 ValidatorIndex array access (GHSA-p7mv-53f2-4cwj) | **PARTIAL** — overlaps with Arithmetic/Memory; the consensus-halt impact is the new angle |
| **L4 Governance param change triggers halt** | A parameter-change proposal sets a value the validation/transition logic mishandles → panic at the activation height | CometBFT ASA-2024-001 VoteExtensionsEnableHeight (GHSA-qr8r-m495-7hc4) | **NO** — not covered; overlaps Economic Design |
| **L5 State-identity collision** | Two distinct objects map to one identifier (slot u64, key); the system cannot distinguish them → partition/repair failure | Solana Dec-2020 mainnet stall: two blocks per slot tracked by slot u64 (Solana Labs post-mortem) | **NO** — not covered |
| **L6 State-transition window escape** | An object moves between states such that a pending penalty/check window is skipped | Cosmos ASA-2024-005 slashing evasion via redelegation, CWE-372 (GHSA-86h5-xcpx-cfqc) | **NO** — not covered |
| **L7 Epoch-boundary state-regeneration exhaustion** | Validating boundary-spanning messages forces repeated re-computation of prior states; cache overflows → resource exhaustion → liveness loss | Ethereum May-2023 finality incident: old-target attestations, Prysm regenerates state, cache fills (Prysm post-mortem, fix v4.0.4) | **PARTIAL** — G08 covers epoch/slot truncation (arithmetic), not the regeneration-cost class |
| **L8 Cross-client / cross-impl divergence** | Two implementations of the same protocol handle an edge case differently → fork or differential liveness | Ethereum May-2023: Prysm kept all forks vs Lighthouse dropped attestations (Prysm post-mortem) | **NO** — not covered; needs differential reasoning |
| **L9 Out-of-order protocol-rule application (RPC/sim path)** | A simulation/RPC entrypoint lets caller apply protocol rules (EIPs/upgrades) in an invalid order, reaching a state the real chain never permits | geth `eth_call` out-of-order EIP (EIP2929 on / EIP150 off) → overflow → OOM (iosiro, fix geth v1.13.13). Cross-language: Go node client. | **NO** — not covered; this is the corrected former "Geth JSON-RPC re-entrancy" entry |
| **L10 Partial-state write on error** | Multi-step write commits A+B, errors before C; no rollback; downstream invariant broken | [generic pattern — no specific incident verified this pass; framework note: Cosmos `EndBlock` discards state on panic but pre-panic events/IBC commitments persist] | **PARTIAL** — G01 covers `let _ =`, not the general "writes A+B then errors at C" pattern |
| **L11 Swallowed error / silent default substitution** | `let _ = op()`, `.unwrap_or_default()`, `.ok()`, `if let Err(_) { return }` discards an error whose side effect the caller relies on | [generic pattern — Rust idiom class; no single attributable incident this pass] | **PARTIAL** — G01 covers `let _ =` only |
| **L12 Clock/timestamp-dependent consensus split** | Consensus decision reads wall-clock/block-timestamp; drift between honest nodes → divergent decisions | [generic pattern — BFT-time/median-timestamp mitigations exist; no verified Rust-node split incident this pass] | **PARTIAL** — G07 mentions block-time but no procedure |
| **L13 Delegated-execution / multi-hop error propagation** | A→B→C call chain; C's error is swallowed or remapped by B; A assumes success (e.g. IBC ack swallowed → funds locked, never minted) | [generic pattern — IBC ack semantics documented; no specific attributable advisory fetched this pass] | **NO** — not covered |

---

## 2. Per-class methodology

> Methodology, not patterns. Each procedure must find a NEW instance of the class without already knowing the answer.

### L1 — Error/panic in atomic finalization hook → halt  (VERIFIED class)

**Signal**: any code reachable from a block-finalization hook — Cosmos `EndBlocker`/`BeginBlocker`, CometBFT/Tendermint `FinalizeBlock`/`PrepareProposal`/`ProcessProposal`, Substrate `on_initialize`/`on_finalize`, a Solana bank-finalization path — that can `panic!`/`unwrap`/`expect`/return an error driven by attacker-controllable state.

**Procedure**:
1. Enumerate every function transitively reachable from a finalization hook. These run on EVERY node deterministically; a panic/error here halts the whole chain, not one request.
2. For each, find inputs an unprivileged actor can influence: proposal contents (`x/group`, `x/gov`), message fields, account state created by prior transactions.
3. Hunt fallible operations on those inputs: division (div-by-zero → ASA-2025-003), array/slice index (OOB → ASA-2024-011), `unwrap`/`expect`, integer ops that can overflow, `?` that returns an error the hook does not tolerate.
4. Ask: can the attacker move the system into a state where this op is reached with the failing value, and does the hook propagate the failure to a halt? The verified bar is "any user that can interact with the module can introduce the state."

**Mechanical evidence (tier-1 PoC shape)**: a unit/integration test that builds the malicious proposal/state, runs the finalization hook, and asserts it panics/errors (then asserts the patched code does not). ASA-2025-003's own advisory used "ran a patched node in a local testnet with the failing state and did not halt."

**Anti-pattern**: a hook that catches and logs sub-operation errors per item and continues (the corrective architecture). If each sub-operation failure is isolated and skipped, there is no system-wide halt — not this class.

**Source**: ISA-2025-002 (GHSA-47ww-ff84-4jrg); ASA-2025-003 (GHSA-x5vx-95h7-rv4p). See §7.

### L2 — Unvalidated proposer-injected consensus data  (VERIFIED class)

**Signal**: ABCI++/consensus code that consumes proposer-supplied structures — vote extensions, injected transactions, voting-power summaries — and uses them for accounting or authorization.

**Procedure**:
1. Find every read of proposer-injected data (`VoteExtension`, injected txs, `ExtendedCommit`).
2. For each field consumed, ask: is this field re-validated against the canonical state machine, or trusted as-is? ASA-2024-006's flaw: `ValidateVoteExtensions` "infers total voting power based off the injected `VoteExtension`" rather than reading power from state.
3. Specifically check identity/index fields that index into a set: is `ValidatorIndex` bounds-checked against the actual `ValidatorSet` BEFORE use? ASA-2024-011's flaw was that 0.38.x vote-extension handling "does not double-check the validity of the `ValidatorIndex` field," enabling array OOB.
4. Construct the adversarial proposer: mutate the injected value (inflate a validator's power, point an index out of range) and trace whether any check rejects it before it affects state or causes a panic.

**Mechanical evidence**: a test that submits a proposer payload with a mutated power value / out-of-range index and asserts the code accepts it (vulnerable) or rejects it (patched).

**Anti-pattern**: code that re-derives values from state and only uses the injected data as a hint/optimization, discarding it if it disagrees with state. ASA-2024-006's fix did exactly this: "validation on injected `VoteExtension` data was added to confirm voting power against the state machine."

**Source**: ASA-2024-006 (GHSA-95rx-m9m5-m94v); ASA-2024-011 (GHSA-p7mv-53f2-4cwj). See §7.

### L4 — Governance parameter change triggers halt  (VERIFIED class)

**Signal**: any consensus-critical parameter that is settable via on-chain governance (`x/params`, `x/gov`, `ConsensusParams`), especially activation-height / enable-height style params.

**Procedure**:
1. List governance-settable consensus parameters and the validation that runs when a change proposal executes or activates.
2. For each, enumerate the value domain governance can set (including 0, current height, past height, far-future height) and trace the validation/transition that fires at the activation block.
3. Find values where the validation logic panics or transitions inconsistently. ASA-2024-001: a `VoteExtensionsEnableHeight` change passed via governance hit faulty validation logic and "nodes ... may panic, halting the network."
4. Treat the activation moment as a distinct state transition (steady-state validation may pass but boundary validation fails).

**Mechanical evidence**: integration test that passes the param-change proposal and advances to the activation height, asserting no panic.

**Anti-pattern**: param changes that are range-checked at proposal-submission time AND re-checked at activation. If both gates exist and agree, this class does not apply.

**Source**: ASA-2024-001 (GHSA-qr8r-m495-7hc4). See §7.

### L5 — State-identity collision  (VERIFIED class)

**Signal**: an internal map/index keyed by a value that is NOT guaranteed unique for the thing it identifies — slot number, height, a non-hash key for content that can legitimately exist in multiple variants.

**Procedure**:
1. Enumerate the keys used to track distinct protocol objects (blocks, shreds, votes). For each, ask: can two genuinely-different objects share this key?
2. Solana Dec-2020: blocks (and computed state) were keyed by the PoH **slot number (u64)**, "a legacy and incorrect mapping," so two different blocks for one slot collapsed to one identity — "their block intake code had no way to distinguish block A vs block B for the same slot," so partitions could not repair from each other.
3. For each collision-capable key, trace what breaks when two objects collide: repair/sync, dedup, equivocation detection, fork choice.
4. The fix shape is "key by content hash, not by position/sequence." Flag any position-keyed identity for content that is not provably singleton.

**Mechanical evidence**: construct two valid-but-distinct objects with the same positional key and assert the code treats them as one (vulnerable) or distinguishes them (patched).

**Anti-pattern**: keys that are content hashes, or positional keys with a separately-enforced one-object-per-position invariant (e.g., equivocation slashing makes duplicates non-viable). Verify the enforcing invariant actually holds at the intake layer, not just at consensus.

**Source**: Solana Labs Dec-4-2020 mainnet-beta stall post-mortem. See §7.

### L6 — State-transition window escape  (VERIFIED class)

**Signal**: a penalty/check that applies to objects in state X, plus an operation that moves an object from X to Y (redelegation, migration, transfer) while a pending check on X has not yet fired.

**Procedure**:
1. Identify deferred checks: penalties evaluated lazily (slashing applied at evidence-processing time, not at misbehavior time), windows, grace periods.
2. For each, enumerate operations that re-home the object to a new owner/validator/account during the deferred window.
3. Ask: does the re-homed object remain liable for the pending check, or does it escape? ASA-2024-005: a delegation that "contributed to byzantine behavior of a validator, and the validator has not yet been slashed" could redelegate before slashing applied — CWE-372 "Incomplete Internal State Distinction." Fix: "additional validation logic ... to restrict this behavior."
4. The invariant to assert: liability is bound to the period of misbehavior, not to the object's current location.

**Mechanical evidence**: test that (a) creates liability, (b) re-homes the object before the penalty fires, (c) triggers the penalty, and asserts it still lands on the original object.

**Anti-pattern**: protocols that snapshot liability at misbehavior time and carry it through re-homing. If liability travels with the object's history, this class does not apply.

**Source**: ASA-2024-005 (GHSA-86h5-xcpx-cfqc). See §7.

### L7 — Epoch-boundary state-regeneration exhaustion  (VERIFIED class)

**Signal**: validation that, for a boundary-spanning message (an attestation/vote referencing an object from a prior epoch), recomputes or regenerates a historical state, backed by a finite cache.

**Procedure**:
1. Find validation paths that may regenerate prior states (replaying blocks/slots to reconstruct a checkpoint state).
2. For each, identify the cache that is supposed to avoid repeat regeneration, and its eviction behavior under load.
3. Ask: can an attacker (or normal but adversarial conditions) flood messages that each force a distinct/repeated regeneration, overflowing the cache → unbounded recomputation? Ethereum May-2023: "many attestations voting to an old beacon block ... forced Prysm to regenerate the same state multiple times" once "this cache was quickly filled up"; with a growing validator registry the node could not keep up → finality loss.
4. Treat the epoch boundary as the worst case (old-target attestations are valid precisely across the boundary).

**Mechanical evidence**: load test that submits boundary-spanning valid messages at scale and measures per-message regeneration cost / cache hit rate.

**Anti-pattern**: validation that uses the current head state for recent-canonical targets instead of regenerating (the actual fix in Prysm v4.0.4: "use the head state when validating attestations for a recent canonical block as target root").

**Source**: Prysm mainnet post-mortem, May 2023. See §7.

### L8 — Cross-client / cross-impl divergence  (VERIFIED class)

**Signal**: a protocol with multiple independent implementations (consensus clients, validator/full-node forks) handling the same edge case, where the spec underspecifies behavior under stress.

**Procedure**:
1. Identify behaviors the spec leaves to implementer discretion (what to do when overloaded, how to resolve ambiguous forks, eviction/drop policy).
2. For each, ask: do two reasonable implementations make DIFFERENT choices that produce divergent liveness/safety? Ethereum May-2023: under the attestation flood, "Lighthouse opted to drop attestations in order to stay live" while "Prysm opted to keep many forks" — divergent liveness; Lighthouse stayed up, Prysm stalled.
3. Where you only have one implementation in scope, reason differentially against the reference spec: would a spec-faithful alternative implementation behave the same? A divergence is a finding even without a second codebase to diff.
4. Prioritize edge cases under resource pressure and ambiguous-fork resolution — historically the highest-divergence surface.

**Mechanical evidence**: differential test harness feeding the same adversarial input to two implementations (or to the impl and a spec model) and asserting identical state transitions.

**Anti-pattern**: behavior fully pinned by the spec (deterministic transition functions) where all implementations must agree by construction.

**Source**: Prysm post-mortem (Prysm vs Lighthouse behavior), May 2023. See §7.

### L9 — Out-of-order protocol-rule application via sim/RPC path  (VERIFIED class)

**Signal**: a simulation or read RPC entrypoint that lets the caller override chain parameters/feature flags independently (`eth_call` block overrides, `debug_traceCall`, custom fork configs in a simulation API).

**Procedure**:
1. Enumerate every entrypoint that lets a caller set protocol-version/feature flags or block context independently of the canonical chain.
2. For each pair of features with an activation-ORDER dependency, ask: can the caller enable a later feature while disabling an earlier one it depends on? geth: enabling EIP2929 (via the merge-rules `random` field) while disabling EIP150 (via block number 0x5) produced an inconsistent ruleset.
3. Trace the codepath reached by the impossible combination for unguarded arithmetic/allocation. geth: `makeCallVariantGasCallEIP2929()` — with EIP150 off, `callGas()` returns the stack gas unchecked, `gas + coldCost` overflows `uint64`, the `CALL` is severely undercharged, and the undercharged call allocates ~128GB → OOM crash. Zero-cost via `eth_call`, affecting most public RPC providers.
4. The invariant: feature flags must be applied in canonical activation order; out-of-order combinations the real chain can never reach must be rejected, not executed.

**Mechanical evidence**: send the crafted `eth_call`/sim request with the out-of-order override and assert the node rejects it (patched) vs crashes/over-allocates (vulnerable).

**Anti-pattern**: simulation endpoints that derive the full ruleset from a single canonical fork schedule and forbid per-feature toggling. If features cannot be independently toggled, the ordering can't be violated.

**Note (corrects prior draft)**: this is the real geth `eth_call` bug. It is **out-of-order EIP application**, NOT JSON-RPC re-entrancy. There is no verified geth JSON-RPC re-entrancy incident. Cross-language precedent (Go node client) — the METHODOLOGY (reject impossible cross-feature states at sim entrypoints) ports to Rust simulation/RPC surfaces (e.g. revm/reth `eth_call` with state & block overrides).

**Source**: iosiro disclosure, Feb 2024, geth fixed v1.13.13. See §7.

### L10 — Partial-state write on error  (generic pattern — methodology retained)

**Signal**: any function that writes to 2+ state variables with an early-exit (`?`, `return Err`, `bail!`, `ensure!`) BETWEEN the writes.

**Procedure**:
1. For every function with ≥2 state-mutating writes, enumerate the writes in order.
2. Identify every early-exit between the first and last write.
3. For each: is there rollback (`Drop`/`defer`, `mem::replace` restore, an explicit revert)? Or does state remain half-written?
4. If no rollback, trace downstream consumers of the half-written state — which invariant now fails?
5. **Cosmos framework note**: `EndBlock` discards in-block state on panic, but events emitted and IBC packet commitments written BEFORE the panic are NOT rolled back — a documented architectural seam, not a single attributable advisory.

**Anti-pattern**: every early-exit explicitly restores state. Correct defensive code, not a bug.

**Source**: `[generic pattern]` — no specific incident verified this pass. Framework semantics from Cosmos SDK docs (§3).

### L11 — Swallowed error / silent default substitution  (generic pattern)

**Signal**: `let _ = op()`, `.unwrap_or_default()`, `.unwrap_or(...)`, `.ok()`, `if let Err(_) { return }` without observable handling.

**Procedure**:
1. Grep these discard sites.
2. For each, does the caller rely on a side effect of the operation? Discarding the error means "don't care if it ran," but the next line may assume it did.
3. `.unwrap_or_default()` is the most dangerous: silently substitutes a default (a `0` fee, a `false` flag) — the caller then operates on fabricated state.
4. Severity triage by what the unwritten state controls (balances → financial; validator state → consensus).

**Anti-pattern**: discards where the default IS the intended fallback and is documented as such.

**Source**: `[generic pattern]` — Rust idiom class, no single attributable incident this pass.

### L12 — Clock/timestamp-dependent consensus split  (generic pattern)

**Signal**: consensus-affecting decisions reading `Instant::now`, `SystemTime::now`, a `Clock`, or a block timestamp (not just logging/metrics).

**Procedure**:
1. Enumerate clock/timestamp reads on consensus-critical paths.
2. For each, ask: if two honest nodes read clocks N seconds apart, do they reach different decisions? A 2s timeout with 2s skew gives one node 4s and another 0s.
3. Block timestamps: if fork-choice or validity trusts a proposer-set timestamp within a tolerance, the proposer gains influence within that band.
4. **Framework note**: CometBFT mitigates with BFT-time (median of validator timestamps) and penalizes extreme values — but within tolerance the proposer still has influence.

**Anti-pattern**: clocks used only for local timeouts that do not affect agreed state, or timestamps reduced to a Byzantine-fault-tolerant median.

**Source**: `[generic pattern]` — mitigations documented (§3); no verified Rust-node consensus-split incident this pass.

### L13 — Delegated-execution / multi-hop error propagation  (generic pattern)

**Signal**: an A→B→C call chain where C's error must propagate correctly through B to A's handler.

**Procedure**:
1. Trace multi-hop chains. At each intermediate hop, does it transform/swallow the error?
2. Failure modes: B maps C's specific error to a generic one (A can't distinguish recoverable vs fatal); B catches C's error and returns `Ok(default)` (A assumes success); a `?` whose `From` impl loses information.
3. **IBC framework note**: a packet acknowledgement is `Ok(Ack)` or `Err`. If the receiving chain swallows the error and acks success, the sending chain assumes success — tokens locked on source, never minted on destination. (Documented IBC semantics; no single attributable advisory fetched this pass.)

**Anti-pattern**: error types that preserve the failing variant end-to-end and a terminal handler that matches all upstream cases.

**Source**: `[generic pattern]` — IBC ack semantics documented; no specific advisory verified this pass.

---

## 3. Framework-specific knowledge

### Cosmos SDK (Go; methodology ports to CosmWasm/Rust modules)

- **EndBlocker / BeginBlocker run on every node deterministically.** An error or panic reachable here from attacker-influenced state halts the entire chain, not one request. VERIFIED via ISA-2025-002 (EndBlocker error) and ASA-2025-003 (div-by-zero in group proposal handling). This is the single highest-value infra signal.
- **`EndBlock` rollback is partial.** On panic, in-block state transitions are discarded, but events emitted and IBC packet commitments written before the panic persist — a documented seam (L10).
- **ABCI++ proposer-injected data must be re-validated.** `ValidateVoteExtensions` historically inferred voting power from proposer-injected extensions; the fix confirms power against the state machine (ASA-2024-006). Treat any proposer-injected value used for accounting as untrusted until re-derived from state.
- **Governance can set consensus params, including activation heights.** A param-change proposal can drive validation logic into a panic at activation (the same class as CometBFT ASA-2024-001).
- **Slashing is deferred (lazy).** Penalties apply at evidence-processing time, not misbehavior time, opening a window where redelegation can escape liability (ASA-2024-005, CWE-372).
- Validator-set updates happen in `EndBlock` and take effect in the NEXT block — a one-block window where the old set is still active.

### CometBFT / Tendermint (Go)

- **Vote-extension handling (0.38.x) added a pre-validation code path** that did not re-check `ValidatorIndex`; an out-of-range index caused array OOB → panic → halt (ASA-2024-011, fixed 0.38.15). Any message field used as an index must be bounds-checked against the live set before use.
- **`VoteExtensionsEnableHeight`** is governance-settable and historically panicked the network when changed via proposal (ASA-2024-001, fixed v0.38.3).
- Multiple advisories show malformed-message → network-halt is the dominant consensus-layer bug shape (e.g. invalid-BitArray halt ASA-2025-003 / GHSA-hrhf-2vcr-ghch; malicious block-parts stall ASA-2025-002 / GHSA-r3r4-g7hq-pq4f — listed but not deep-fetched this pass; treat as corroborating breadth, cite the index page).
- Consensus rounds advance via timeout; round transitions are monotonic; a late timeout for an already-completed step is discarded.

### Ethereum consensus layer (Lighthouse = Rust; Prysm/Teku/Nimbus/Lodestar other langs)

- **Old-target attestations** (referencing a block from epoch N-2 during epoch N) are valid across an epoch boundary and historically forced repeated state regeneration; the regeneration cache overflowed under load → resource exhaustion → finality loss (May-2023, Prysm fix v4.0.4: use head state for recent-canonical targets). Lighthouse, being Rust, is the in-scope reference for porting this check.
- **Client diversity is a safety property**: implementations diverge under stress (Prysm kept all forks; Lighthouse dropped attestations to stay live). Behaviors the spec leaves to implementer discretion are divergence surfaces (L8).
- Epoch transitions recompute the validator set, process attestations, and update fork-choice weights; boundary-only bugs survive long testing because testnets rarely cross many epoch boundaries.

### geth / execution layer (Go; revm/reth = Rust)

- **`eth_call` block overrides let a caller toggle individual EIPs/feature flags out of canonical activation order.** Enabling a later EIP while disabling an earlier dependency reaches a state the real chain never permits; geth's `makeCallVariantGasCallEIP2929` then overflowed gas accounting → undercharged CALL → ~128GB allocation → OOM (iosiro Feb-2024, fixed v1.13.13). Port the methodology to Rust simulation/RPC surfaces (reth/revm `eth_call` with state+block overrides): reject impossible cross-feature combinations rather than executing them.

### Solana (Rust; Agave/validator client)

- **Block (and computed-state) identity was keyed by the PoH slot number (u64), not by hash** — "a legacy and incorrect mapping." When a doubly-booted validator produced two distinct blocks for one slot, the intake code could not distinguish them and partitions could not repair from each other → 6-hour stall (Dec-2020). Positional/sequence keys for content that can legitimately have multiple variants are an identity-collision signal. (NOTE: this corrects the prior draft's "PoH-generator clock drift → wrong slot → votes rejected" — the post-mortem attributes the stall to slot-number identity collision propagated by a Turbine fault, not clock drift.)
- **Instruction atomicity is VM-level**: if instruction N fails, instructions 1..N-1 roll back. But cross-program (CPI) side effects in OTHER runtimes are not guaranteed to roll back — logic-level (not VM-level) atomicity must be reasoned about separately.

### Substrate / Polkadot (Rust)

- **Runtime upgrades via `set_code`** replace the WASM blob; storage migrations transform old→new state format. Migration bugs are a distinct class. **No specific advisory was verified this pass** — treat storage-migration correctness as a `[generic pattern]` to investigate, not an attributed incident. `on_initialize`/`on_finalize` ordering between pallets is by pallet index; cross-pallet invariant enforcement across the hook boundary is manual.

---

## 4. Tooling

| Tool | What it checks | Golden signature | Invoke |
|------|---------------|------------------|--------|
| **stateright** | Model checking — counterexample traces violating a user-defined state invariant | `Exploration::into_counterexample()` returns a trace where `always(property)` fails | `cargo test --test model_test` |
| **Kani (state-machine harness)** | Bounded model checking for state-machine properties | Kani counterexample trace | `cargo kani --harness check_state_invariant --unwind N` |
| **proptest state-machine tests** | Random action sequences, assert invariant after each | shrunken action sequence that breaks the invariant | `cargo test` with `proptest!` state-machine pattern |
| **Loom** | Concurrency model checking — race-path discovery | Loom counterexample with thread interleaving | `cargo test --test loom_test` (`loom::model`) |
| **Integration test against finalization hook** | Drive EndBlocker/FinalizeBlock with malicious state; assert no panic/error → no halt | the exact PoC shape ASA-2025-003 used ("ran a patched node ... did not halt") | framework test harness (e.g. `simapp` / local testnet) |
| **Differential harness** | Feed identical adversarial input to two impls (or impl vs spec); assert identical transition | divergent state transition between impls | custom; compares L8 behavior |
| **Manual invariant enumeration** | Auditor synthesizes invariants from docs + code + types | documented invariant + violated path + concrete input sequence | — |

**Critical gap**: no off-the-shelf tool discovers state-machine invariants from code. The auditor must SYNTHESIZE the invariant and then verify it. Logic/state bugs are harder than arithmetic (Kani finds the overflow; you only write the assertion) — here you must first discover WHAT to assert. The highest-yield tier-1 PoC for the verified halt classes (L1/L3/L4) is an integration test that drives the finalization/consensus hook with the malicious input and asserts panic/error, exactly as the Cosmos advisories' own validation did.

---

## 5. Discovery calibration

- **Hardest angle to mechanize.** Arithmetic→Kani, memory→MIRI, concurrency→Loom; logic/state→stateright, but stateright needs you to MODEL the machine, which is the hard part. The LLM edge is synthesizing invariants from code + advisories + docs.
- **Highest-ROI mechanical screens (lead to the VERIFIED classes):**
  1. **Finalization-hook fallible ops (L1/L3/L4)** — grep finalization/consensus paths (`EndBlocker`, `FinalizeBlock`, `ProcessProposal`, `on_finalize`) for division, indexing, `unwrap`/`expect`, overflow-capable arithmetic on attacker-influenced inputs. Every verified Cosmos/CometBFT halt this pass lives here.
  2. **Proposer-injected reads (L2)** — grep `VoteExtension`, injected-tx handling, voting-power summaries; check each consumed field is re-validated against state.
  3. **Positional identity keys (L5)** — find maps/indexes keyed by slot/height/sequence for content that can have multiple valid variants.
  4. **Swallowed errors (L11)** — grep `let _ =`, `.unwrap_or_default()`, `.ok()`, `if let Err(_)`.
- **Hardest classes (depth-agent territory)**: L6 (window escape), L7 (regeneration exhaustion), L8 (cross-client divergence), L13 (multi-hop error propagation) — all require understanding the PROTOCOL, not just the code.
- **False-positive risk is highest for L10/L11** — many functions intentionally leave partial state cleaned up later, or use defaults as intended fallbacks. Always trace the cleanup/fallback path before reporting.
- **Cross-language precedents are the norm here.** 7 of 8 verified incidents are Go (Cosmos/CometBFT/geth) or multi-client; only Solana and Lighthouse are Rust. The dossier's value is porting the METHODOLOGY (not the line-level pattern) to Rust node clients — every per-class procedure above is written framework-agnostic for exactly this reason.

---

## 6. Gaps → angle changes

| Methodology | Change type | Anti-bloat check |
|-------------|-------------|------------------|
| **L1 Finalization-hook halt** — enumerate fallible ops (div, index, unwrap, overflow) reachable from EndBlocker/FinalizeBlock/on_finalize on attacker-influenced state; assert no panic/error | new-check | G01 covers `let _ =`; G02 covers Mutex poison. Neither covers "panic/error inside a deterministic finalization hook halts every node." NOT covered. VERIFIED by 2 Cosmos + 2 CometBFT advisories — highest priority. |
| **L2 Proposer-injected validation** — for each proposer-injected field used in accounting/indexing, verify re-validation against state before use | new-check | Not covered. VERIFIED (ASA-2024-006, ASA-2024-011). |
| **L4 Governance-param activation halt** — for governance-settable consensus params, check the activation-height transition validation for panic on attacker-chosen values | new-check + cross-ref Economic Design | Not covered. VERIFIED (ASA-2024-001). Overlaps Arithmetic CHECK 10 (governance-params) and Economic Design — cross-reference, don't duplicate. |
| **L5 Positional-identity collision** — flag maps/indexes keyed by slot/height/sequence for multi-variant content; require content-hash keying or a proven singleton invariant | new-check | Not covered. VERIFIED (Solana Dec-2020). |
| **L6 Transition-window escape** — for each deferred penalty/check, enumerate re-homing ops and verify liability survives the move | new-check | Not covered. VERIFIED (ASA-2024-005, CWE-372). |
| **L7 Epoch-boundary regeneration cost** — find validation that regenerates prior state for boundary-spanning messages; check cache eviction under flood | extend G08 | G08 covers epoch/slot arithmetic truncation; the regeneration-cost/exhaustion class is different. VERIFIED (Ethereum May-2023). |
| **L8 Cross-client divergence** — for spec-discretionary behaviors (drop/keep under load, ambiguous-fork resolution), reason differentially against spec/second impl | new-check (depth-agent) | Not covered. VERIFIED (Prysm vs Lighthouse, May-2023). |
| **L9 Out-of-order rule application at sim/RPC** — for sim/RPC entrypoints with per-feature/EIP overrides, reject combinations violating canonical activation order | new-check | Not covered. VERIFIED (geth iosiro, corrects prior "JSON-RPC re-entrancy" entry). Ports to reth/revm `eth_call` overrides. |
| **L10 Partial-state write** — multi-write functions with error paths between writes, rollback-or-flag | new-check | G01 covers `let _ =` only. `[generic pattern]` — keep methodology, no attributed id. |
| **L11 Swallowed-error variants** — extend G01 with `.unwrap_or_default()`, `.ok()`, `if let Err(_) { return }` | extend G01 | G01 covers only `let _ =`. `[generic pattern]`. |
| **L12 Clock-dependence** — enumerate consensus-path clock reads; N-second skew reasoning | extend G07 | G07 flags block-time but has no procedure. `[generic pattern]`. |
| **L13 Multi-hop error propagation** — trace A→B→C error type mapping; verify terminal handler catches all upstream errors (IBC ack swallow) | new-check | Not covered. `[generic pattern]`. |

---

## 7. Sources

Every id below was fetched this pass; the URL confirms BOTH the identifier AND the mechanism described in sections 1–6. Access date: 2026-06-05.

**Tier 1 — post-mortems / advisories with root-cause + fix (VERIFIED)**

- **Cosmos SDK ISA-2025-002 — x/group can halt when erroring in EndBlocker** (High; affected ≤ v0.50.12 / ≤ v0.47.16; fixed v0.50.13 / v0.47.17). Mechanism: malicious proposal drives the `x/group` EndBlocker to error during finalization → chain halt; "any set of users that can interact with the groups module could introduce this state." — https://github.com/cosmos/cosmos-sdk/security/advisories/GHSA-47ww-ff84-4jrg
- **Cosmos SDK ASA-2025-003 — Groups module can halt chain when handling a malicious proposal** (High; affected ≤ v0.47.15 / ≤ v0.50.11; fixed v0.47.16 / v0.50.12). Mechanism: malicious group proposal causes a **division by zero**, halting the chain. — https://github.com/cosmos/cosmos-sdk/security/advisories/GHSA-x5vx-95h7-rv4p
- **Cosmos SDK ASA-2024-006 — ValidateVoteExtensions voting-power inference** (High, CVSS 7.1, CWE-20; affected ≤ 0.50.4; fixed 0.50.5). Mechanism: default `ValidateVoteExtensions` infers total voting power from proposer-injected `VoteExtension`s; a dishonest proposer can mutate per-validator voting power. Fix re-validates injected power against the state machine. — https://github.com/cosmos/cosmos-sdk/security/advisories/GHSA-95rx-m9m5-m94v
- **Cosmos SDK ASA-2024-005 — Potential slashing evasion during re-delegation** (Low, CWE-372; affected ≤ 0.50.4 / ≤ 0.47.9; fixed 0.50.5 / 0.47.10). Mechanism: a delegation that contributed to byzantine behavior, not yet slashed, redelegates before slashing applies → escapes the penalty window. Fix adds validation restricting this. — https://github.com/cosmos/cosmos-sdk/security/advisories/GHSA-86h5-xcpx-cfqc
- **CometBFT ASA-2024-011 — Vote Extensions: panic on Precommit with invalid data** (High; introduced 0.38.x; fixed 0.38.15). Mechanism: vote-extension handling added in 0.38.x does not re-validate the `ValidatorIndex` field; an out-of-range index causes array out-of-bounds access → panic → halt. — https://github.com/cometbft/cometbft/security/advisories/GHSA-p7mv-53f2-4cwj
- **CometBFT ASA-2024-001 — VoteExtensionsEnableHeight validation can cause chain halt** (High; fixed v0.38.3). Mechanism: a governance param-change proposal modifying `VoteExtensionsEnableHeight` on an ABCI2 chain hits faulty validation logic → nodes panic → network halt. Fix improves the validation. — https://github.com/cometbft/cometbft/security/advisories/GHSA-qr8r-m495-7hc4
- **Solana Labs — Mainnet Beta Stall Post-Mortem (Dec 4, 2020)**. Mechanism: a doubly-booted validator transmitted two distinct blocks for one slot; blocks/computed-state were keyed by the PoH **slot number (u64)** — "a legacy and incorrect mapping" — so intake "had no way to distinguish block A vs block B for the same slot"; partitions could not repair from each other; a Turbine shred-propagation optimization propagated the fault. 6-hour stall, ~393 validators restarted. (Corrects prior draft's clock-drift framing.) — https://medium.com/solana-labs/mainnet-beta-stall-postmortem-ba0c6064e3
- **Prysm (Offchain Labs) — Mainnet Post-Mortem, Ethereum finality incident May 11–12, 2023** (fix Prysm v4.0.4). Mechanism: old-target attestations (referencing epoch N-2 during epoch N) forced Prysm to regenerate prior beacon state; the dedup cache filled and the same state was regenerated repeatedly; with a growing validator registry the node could not keep up → ~18.5% missed-slot rate, finality loss, ~382 ETH in lost rewards. Cross-client divergence: Lighthouse dropped attestations to stay live; Prysm kept all forks and stalled. Fix: use head state for recent-canonical target roots. — https://prysm.offchainlabs.com/docs/misc/mainnet-postmortems/
- **geth out-of-order EIP application DoS (iosiro, disclosed to EF Feb 15, 2024; fixed geth v1.13.13)**. Mechanism (NOT re-entrancy): `eth_call` block overrides enable EIP2929 (via `random`/merge rules) while disabling EIP150 (block number 0x5); `makeCallVariantGasCallEIP2929()` then overflows `gas + coldCost` (uint64) because EIP150's `callGas()` check is absent → severely undercharged `CALL` → ~128GB allocation → OOM crash; zero-cost, affected most public RPC providers. — https://iosiro.com/blog/geth-out-of-order-eip-application-denial-of-service

**Tier 3 — advisory index pages (breadth corroboration, listing-level confirmation)**

- Cosmos SDK security advisories index (confirms the ids above plus related halt-class advisories) — https://github.com/cosmos/cosmos-sdk/security/advisories
- CometBFT security advisories index (additional consensus-halt/liveness advisories: invalid-BitArray halt GHSA-hrhf-2vcr-ghch, malicious block-parts stall GHSA-r3r4-g7hq-pq4f, state-sync chain-split GHSA-g5xx-c4hv-9ccc — listed-level only this pass) — https://github.com/cometbft/cometbft/security/advisories

**Tier 4 — framework references (semantics, not incidents)**

- Cosmos SDK BeginBlock/EndBlock semantics — https://docs.cosmos.network/main/build/building-modules/beginblock-endblock
- Tendermint consensus protocol — https://arxiv.org/abs/1807.04938
- Ethereum consensus specs — https://github.com/ethereum/consensus-specs

**Tier 6 — tooling**

- stateright — https://github.com/stateright/stateright
- proptest state-machine tests — https://docs.rs/proptest/latest/proptest/state_machine/index.html

**Dropped from prior draft (could not be verified to a primary source this pass — NOT cited as incidents):**
- "Geth JSON-RPC re-entrancy" — no such incident exists; the real geth `eth_call` bug is out-of-order EIP application (now L9, verified above).
- "Solana PoH-generator clock drift → wrong slot → votes rejected" — the Dec-2020 stall was slot-number identity collision, not clock drift (corrected in L5).
- "Aptos consensus mutex ordering", "Substrate runtime storage race", "Cosmos IBC client↔connection handshake state mismatch", "Ethereum beacon↔execution deposit sync gap", "MakerDAO executive vote during auction", "Tendermint round-timeout propagation bug", "Casper FFG surround-vote detection gap" — no primary source fetched confirming both id and mechanism this pass. Methodology retained where generalizable; relabeled `[generic pattern]` with no id in sections 1–2.

---

## 8. AI-provenance reminder

This dossier was assembled by an AI agent (Argus). Every real-world advisory id and mechanism in sections 1–7 was fetched from the primary source cited at the same line and confirmed for BOTH identifier AND mechanism; unconfirmable claims were dropped or labeled `[generic pattern]` with no id. Nonetheless, advisory text is sometimes redacted and post-mortems are summaries — a human reviewer MUST independently re-read each cited URL before relying on any id, severity, version range, or mechanism for a real audit submission. Do not present any line below as ground truth without that manual validation. No finding derived from this dossier should be submitted to a bounty/contest platform without independent human verification of the underlying code and the cited source.
