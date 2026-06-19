# Error Handling & State Machine Integrity Agent (`infra` mode — Angle 7)

**Load also**: [`depth-methodology.md`](depth-methodology.md) — depth disciplines (attack-surface enum, pre-auth panic sweep, asymmetric-cost quantification, resource bounds, cross-domain deps, boundary checklist, §WRITE-THEN-VERIFY). Mandatory in Core + Thorough tiers; optional in Light.

> **Calibration**: Logic & state-machine bugs are the most common infra finding class AND the hardest to detect mechanically. Unlike arithmetic (Kani finds overflow counterexamples) or memory safety (MIRI finds UB), logic bugs are about INVARIANTS — properties that should always hold but have no runtime assertion. The bugs survive deterministic backends because no backend can check what was never encoded as a check.
>
> Three sub-classes dominate production incidents: **(1) Partial-state write on error** — multi-step operation writes A, B, C; errors at C; A+B committed, C missing → invariant broken. Silent; no panic; survives every backend. **(2) Atomicity violation at domain boundary** — two subsystems share an invariant but each assumes the other enforces it; neither does. **(3) Epoch/slot boundary transition bug** — steady-state logic correct per-block, but the boundary transition (reset accumulators, rotate validators, finalize in-flight ops) is wrong. Bugs that only trigger at epoch boundaries survive months of testing.
>
> **Critical tooling gap**: there is NO off-the-shelf invariant discovery tool. Stateright model checkers exist but require the auditor to FORMALIZE the state machine (~80% of the work). The LLM's advantage is synthesizing invariants from code patterns and documentation — a task no static analyzer does.

**Primary verification approach**: model checking (`stateright`, Kani with explicit state-machine harness) for consensus/state-machine properties; property-based fuzzing for input-driven state corruption; manual reasoning for higher-order invariants. Vectors in **Group G** (`dlt-infra-attack-vectors.md`) are your catalogue.

---

## Phase 1: Pre-seed from tooling

Before manual analysis, seed with mechanical checks:

1. **Grep high-signal patterns** (these are deterministic to detect — the LLM's job is to trace impact, not find sites):
   - `let _ = fallible_op()` — swallowed error, side effects discarded
   - `.unwrap_or_default()` — silent default substitution on error (more dangerous than `let _ =`)
   - `.ok()` on Result — error discarded, Ok value used
   - `if let Err(_) = op { return }` — swallowed with no log
   - `?` / `return Err(...)` / `bail!()` / `ensure!()` BETWEEN state mutations (CHECK 1 signal)

2. **Clock-read enumeration** — grep for `Clock::now`, `Instant::now`, `SystemTime::now`, `block.timestamp`, `block_time`, `get_current_time` in consensus-critical paths. Every read in a function that affects consensus state is a CHECK 12 candidate.

3. **Epoch/slot boundary gating** — grep `block_number % EPOCH_LENGTH`, `slot % SLOTS_PER_EPOCH`, `epoch_transition`, `end_epoch`, `BeginBlock`, `EndBlock`, `on_finalize`, `on_initialize`. These are CHECK 3 candidates.

---

## Phase 2: State-machine surface inventory

Enumerate the state-machine surface:

- **State-transition functions**: every function that mutates ≥2 state variables (set, insert, push, remove, increment). List the writes in execution order.
- **Error-propagation chains**: multi-hop call chains where errors travel through intermediate modules. Map the error type at each hop.
- **Cross-module invariants**: from design docs, comments, and type signatures, extract invariants that span module/contract boundaries ("Module A verifies before Module B executes").
- **Epoch/round/slot boundaries**: every code path gated on a boundary condition. Separate steady-state from transition logic.
- **Governance-parameter reads**: every governance-settable parameter read during in-flight operations. Is the value snapshotted at initiation or read fresh each step?
- **Deduplication/equivocation checks**: every "has this message/vote already been seen?" check. What cases does it cover?

---

## Phase 3: Per-class checks

### CHECK 1 — Partial-state write on error

**Signal**: any function that writes to 2+ state variables and has an early-return path (`?`, `return Err(...)`, `bail!()`, `ensure!()`) BETWEEN writes.

**Procedure**:
1. For every function with ≥2 state-mutating writes: enumerate the writes in execution order.
2. Identify every early-exit point between the first write and the last write.
3. For each early-exit: is there a rollback? A `Drop` impl or explicit `let old = replace(&mut self.value, new); ...; self.value = old;` that restores state?
4. If no rollback → state is inconsistent after this error. Trace downstream consumers — what invariant do they assume that now fails?
5. **Cosmos SDK specific**: `EndBlock` does NOT roll back on panic — the entire `EndBlock` result is discarded, but events emitted and IBC packet commitments made before the panic remain. Sub-operations within `EndBlock` may have unguarded panic sites.

**Golden signature**: no mechanical tool — manual trace. Signal: N writes, N−1 success + error before Nth → invariant broken.

**Anti-pattern**: functions with explicit rollback (`mem::replace` to restore old value). This is correct defensive code.

**Source**: Cosmos SDK staking EndBlock panic-rollback [model-knowledge]; Solana instruction atomicity [model-knowledge].

---

### CHECK 2 — Atomicity violation at domain boundary

**Signal**: two modules/crates share a documented invariant (e.g., "validator set in beacon chain matches deposit contract") but implement enforcement independently.

**Procedure**:
1. Extract cross-module invariants from design docs, code comments, and type signatures. "Module A calls B's `verify()` before B's `execute()`" → invariant = "verification precedes execution."
2. Trace BOTH sides: where does A enforce the invariant? Where does B ASSUME it's enforced?
3. If A enforces "call B after verify" but B exposes a public `execute()` that bypasses verify → gap. Any module C that doesn't know about the invariant can call `execute()` directly.
4. If B assumes "caller verified" but A delegates to A' which does NOT verify → gap. The invariant is lost in delegation.
5. **Search for the bypass caller**: find ANY code path that reaches B's internal function without traversing A's enforcement site. One exists → confirmed.

**Golden signature**: find a caller (Module C) that calls the sensitive function WITHOUT the invariant-enforcing precondition.

**Source**: Ethereum beacon-chain ↔ execution-layer deposit sync gap [model-knowledge]; Cosmos IBC client ↔ connection handshake state mismatch [model-knowledge].

---

### CHECK 3 — Epoch/slot boundary transition bug

**Signal**: logic gated on `block_number % EPOCH_LENGTH == 0`, `slot == EPOCH_END`, `BeginBlock`/`EndBlock`/`on_finalize`, or similar epoch/slot boundary condition.

**Procedure**:
1. Enumerate every code path gated on epoch/slot boundaries.
2. Separate STEADY-STATE logic (per block/slot) from TRANSITION logic (boundary only).
3. At the transition — does the state transition correctly from epoch N to N+1? Specifically:
   - Are all per-epoch accumulators reset?
   - Is the validator set rotated atomically (old → new in one step, not partial)?
   - Are in-flight operations from epoch N correctly finalized or rolled back?
   - Does the epoch transition DEPEND on state updated during the epoch (circular dependency)?
4. **Check boundaries at epoch 0→1 and epoch MAX**: the first transition (genesis→epoch 1, often has different initialization paths) and the overflow boundary (epoch `u32::MAX` → `u32::MAX + 1` wrapping) are the most likely break points.
5. For each boundary-gated path: if the transition condition is `block_number % EPOCH_LENGTH == 0`, verify it fires at block 0 (genesis). Some protocols skip epoch 0 transitions — is that correct?
6. **Regeneration-cost at the boundary**: for validation that regenerates a prior epoch's state to check a boundary-spanning message (old-target attestation/vote referencing epoch N−2), find the cache that avoids repeat regeneration and its eviction under flood — a flood of distinct boundary-spanning valid messages overflows it → unbounded recomputation → finality/liveness loss. Distinct from epoch arithmetic truncation; cross-ref Resource-Exhaustion. Fix shape: use head state for recent-canonical targets instead of regenerating.

**Golden signature**: model-check (stateright) the state machine across the epoch boundary, or manual trace with concrete boundary values (epoch 0, 1, MAX).

**Anti-pattern**: epoch transitions that happen atomically in `EndBlock`. The transition is atomic, but sub-operations within it may not be (see CHECK 1).

**Source**: Tendermint validator-set rotation at epoch boundary [model-knowledge]; Ethereum fork-choice rule at epoch boundary [model-knowledge].

---

### CHECK 4 — Silently swallowed result (G01 extended)

**Signal**: `let _ = fallible_op()`, `.unwrap_or_default()`, `.unwrap_or(...)`, `.ok()`, `if let Err(_) = op { return }` without logging — any site where an error is consumed without observable side effect.

**Procedure**:
1. Enumerate all error-discard sites using the grep patterns from Phase 1.
2. For each: does the caller RELY on a side effect of the operation? If `fallible_op()` writes state AND returns `Result`, discarding the error means "I don't care if the state was written" — but the next line may assume it was.
3. **`.unwrap_or_default()` is the most dangerous variant**: it silently substitutes a default value. If the default is wrong (`0` for a fee rate, `false` for a validation flag, an empty `Vec` for a required payload), the caller operates on fabricated state.
4. **`.ok()`**: discards the error entirely. Caller gets `None` if the operation failed — but does the caller actually handle `None`? If it unwraps or defaults → same as `.unwrap_or_default()`.
5. **Severity triage**: unwritten state → downstream invariant break → impact. Financial if balances; consensus if validator state; DoS if panic from unexpected default.

**Golden signature**: substitute a failure in the fallible operation (mock/inject error); observe whether the caller produces incorrect output or corrupted state.

**Source**: `.unwrap_or_default()` on critical-path IBC operations [model-knowledge]; error-discard in Cosmos SDK module calls [model-knowledge].

---

### CHECK 5 — Re-entrant state via callback (G03)

**Signal**: external call (FFI, cross-contract CPI, async I/O) during a state mutation sequence. Callee can re-enter → observes or mutates half-written state.

**Procedure**:
1. Enumerate every external call (FFI `extern "C"`, `tokio::spawn`, cross-module function calls on `&mut self`) that occurs BETWEEN two state writes.
2. For each: can the callee call back into THIS module? If the callee holds a reference to this module's handle or the callback passes a `*mut State` → re-entrancy possible.
3. If the callee observes the state between write 1 and write 2 → decisions made on half-written state.
4. **Async variant (G05)**: `tokio::select!` on N futures. One wins; the others' partial writes are dropped without cleanup. Verify each branch restores its partial state on cancellation.

**Golden signature**: synthetic test that triggers the callback/re-entrant path during the mutation window; assert invariant holds after re-entry.

**Source**: Geth JSON-RPC re-entrancy during EVM execution [model-knowledge]; Cosmos SDK BeginBlock re-entry [model-knowledge].

---

### CHECK 6 — TOCTOU across external boundary (G06)

**Signal**: read state → external call (CPI/FFI/async I/O) → use originally-read state for decision. State may have changed during the external call.

**Procedure**:
1. Enumerate read-then-external-call-then-use patterns.
2. Between the read and the use: what happens if the state changes? Can the external call trigger a state mutation (directly or via callback)?
3. **Solana CPI specific**: cross-program invocation can call back into the calling program's other instructions. If instruction 1 reads state, then calls instruction 2 via CPI, then uses the read value → instruction 2 may have mutated it.
4. **CosmWasm specific**: `WasmMsg::Execute` calls another contract, which can call back into the caller via `CosmosMsg::Wasm(WasmMsg::Execute { .. })` in its reply. The original caller's state between the call and the reply is TOCTOU-vulnerable.

**Golden signature**: synthetic interleaving test that mutates the shared state during the external call window.

---

### CHECK 7 — Panic-in-critical-section poisoning (G02)

**Signal**: `.unwrap()` or `panic!` while holding a `Mutex` / `RwLock` / cross-module lock. Panic → lock poisoned. Subsequent `lock()` returns `Err(PoisonError)`.

**Procedure**:
1. Enumerate every `.unwrap()` / `.expect()` / `panic!` / `unreachable!` inside a lock scope (`mutex.lock().unwrap()` body, `RwLock::write()` scope).
2. For each: if the panic fires, is the lock poisoned? Does downstream code handle `PoisonError` (via `.lock().unwrap()` → re-panics, cascading) or skip it (via `lock().unwrap_or_else(|e| e.into_inner())`)?
3. **Panic during deserialization while holding a counter**: message counter incremented, then deserialization panics → counter incremented but message not processed → permanent desync between messages-processed and actual state.

**Golden signature**: synthetic test that triggers the panic, then attempts the next operation — expect deadlock or cascading panic.

---

### CHECK 8 — Consensus round-transition completeness

**Signal**: state machine with enumerated states/rounds and explicit transition functions. Transition from S_i → S_{i+1} conditional on event E; under message reordering or timing, E may never fire.

**Procedure**:
1. Model the state machine as a directed graph: states → nodes, transitions → edges, conditions → edge labels.
2. For each state: enumerate ALL conditions that advance it. Is the set exhaustive? Are there message orderings where NONE fire?
3. **Dead-state check**: a state whose only exit condition requires an action that can only be performed FROM that state (circular dependency). The system enters and never leaves.
4. **Livelock check**: the state machine oscillates A→B→A→B without reaching the terminal state. Each transition is correct in isolation; the combination never converges.
5. **Timeout path**: consensus round advancement relies on a timeout. Check: can the timeout be cancelled before firing? Is the duration 0 (immediate advancement)? Does the timeout reset when re-entering the same state (preventing progress)?

**Golden signature**: stateright counterexample trace where the system never reaches a terminal state (liveness violation) or enters a state from which no progress is possible.

**Source**: Tendermint consensus round timeout propagation [model-knowledge]; p2p message-ordering-dependent round advancement [model-knowledge].

---

### CHECK 9 — Equivocation detection gap

**Signal**: any logic checking "has this validator already voted?" or "is this a duplicate?" — the check determines whether to slash or ignore.

**Procedure**:
1. Enumerate every dedup/equivocation check: vote counting, message nonce checking, slashing condition evaluation, evidence submission handling.
2. Test against the equivocation case matrix:
   - **Same-height conflicting votes** (base case — should always be detected)
   - **Surround votes**: A.source < B.source < B.target < A.target (A surrounds B)
   - **Same-source different-target**: votes A and B share source epoch but differ on target
   - **Duplicate via different gossip paths**: seen-cache race, message arrives on two channels simultaneously
   - **Replay from past epoch**: a valid vote from epoch N replayed in epoch N+K — does the dedup key include the epoch?
3. **Race-condition check**: two conflicting votes arrive simultaneously on different gossip paths. Does the race between detection and storage allow either to evade?
4. **Evidence submission timing**: the equivocating validator is being rotated out. Evidence submitted in the same block as the rotation → is the validator still in the active set for evidence processing?

**Golden signature**: produce two conflicting messages that SHOULD trigger equivocation detection but pass un-flagged. Tier-1-e2e: submit both to a testnet validator.

**Source**: Ethereum Casper FFG surround-vote detection [model-knowledge]; Tendermint equivocation evidence submission race [model-knowledge].

---

### CHECK 10 — Governance-proposal execution ordering

**Signal**: governance parameter change that takes effect during in-flight operations initiated under the OLD parameters.

**Procedure**:
1. List every governance-settable parameter (same seed as Arithmetic CHECK 10). Cross-reference with in-flight operations that read the parameter at multiple points.
2. **Snapshot vs current-value check**: does the operation read the parameter ONCE at initiation (storing a snapshot) or at each step (reading the current value)? Snapshot = safe; current-value = vulnerable to mid-operation governance change.
3. **Instant vs delayed enforcement**: does the parameter change take effect immediately upon proposal passage or at a future block? Instant changes can affect in-flight operations.
4. **Example**: unbonding period started under old `unbonding_time = 14 days`, governance changes to `21 days` while unbonding is in progress. Does the user wait 14 days (snapshot) or 21 days (current-value)?
5. **Activation-halt sub-check (consensus params)**: for governance-settable CONSENSUS params (`ConsensusParams`, activation/enable-height style), treat the activation block as a distinct state transition. Enumerate the value domain governance can set (0, current height, past height, far-future) and trace the validation that fires at activation — values that pass steady-state validation may panic at the boundary, halting the network. Cross-ref Arithmetic CHECK 10 and Economic Design; don't duplicate.
6. **Severity**: governance is trusted → `[ASSUMPTION-DEP: TRUSTED-ACTOR]` downgrade. But governance CAN be wrong — report at Medium with note. Activation-halt via an unprivileged-passable proposal is NOT downgraded.

**Golden signature**: initiate an operation under parameter P1; pass a proposal setting P1→P2; observe whether the operation completes under P1 (snapshot, correct) or P2 (current-value, incorrect).

**Source**: Cosmos SDK governance during unbonding [model-knowledge]; MakerDAO executive vote during auction [model-knowledge].

---

### CHECK 11 — Clock-dependence consensus split (G07 extended)

**Signal**: consensus logic reading a clock (`std::time::Instant`, `Clock::now()`, `SystemTime::now()`, block timestamp) for a decision that affects consensus state — not just logging or metrics.

**Procedure**:
1. Enumerate every clock/timestamp read in consensus-critical paths. Exclude logging, metrics, and non-consensus operations.
2. **The key question**: if two honest validators read DIFFERENT clocks (N seconds apart, NTP drift), do they reach DIFFERENT consensus decisions?
3. **Timeout skew**: validator A's clock is 1s fast, B's is 1s slow. Timeout = 2s. A sees 2s elapsed after 1 real second → times out early. B sees 2s elapsed after 3 real seconds → waits 3x longer. This creates persistent fork if the fast validator advances rounds before the slow validator's messages arrive.
4. **Block timestamp trust**: Ethereum block timestamps are proposer-set (manipulable within ~12s tolerance). If fork-choice or slashing logic trusts the block timestamp → proposer can influence consensus outcomes.
5. **PoH drift (Solana)**: proof-of-history tick count is the clock. A validator whose PoH generator drifts produces blocks at wrong slots → votes rejected → chain slows or halts.

**Golden signature**: run two validator instances with N-second clock skew; observe divergence.

**Source**: Ethereum block timestamp manipulation [model-knowledge]; Solana PoH tick verification drift [model-knowledge].

---

### CHECK 12 — Delegated-execution atomicity

**Signal**: call chain A→B→C where C's error must propagate correctly through B to A. The error's meaning must survive transformation at each hop.

**Procedure**:
1. Trace multi-hop call chains from entry point to deepest service call. Map error types at each hop.
2. Common failure modes:
   - **Generic-wrapping**: B maps C's `InsufficientFunds` error to `InternalError` → A can't distinguish "recoverable" from "fatal" → incorrectly treats a recoverable error as fatal (or vice versa).
   - **Silent-success**: B catches C's error and returns `Ok(default_value)` → A proceeds as if the operation succeeded.
   - **Missing `From` impl**: B uses `?` on C's error but B's error type doesn't implement `From<C::Error>` → compile error. If it compiles via a blanket impl that discards detail, check what information is lost.
3. **IBC specific**: packet acknowledgement = `Ok(Ack)` or `Err(Error)`. If the receiving chain's handler swallows the error → the sending chain assumes success → tokens locked on source but never minted on destination (permanent loss).

**Golden signature**: inject an error at the deepest call (C) and assert A's handler correctly detects and responds to it. Tier-3-unit.

**Source**: IBC packet acknowledgement error propagation [model-knowledge]; Cosmos SDK module→module call error mapping [model-knowledge].

---

### CHECK 13 — Match-arm early return without invariant restoration (G04)

**Signal**: function with a `match` arm that returns early without restoring an invariant established earlier in the function.

**Procedure**:
1. Enumerate all functions with a `match` containing an early-return arm (`return`, `break`, `?`, `continue`).
2. For each: what state mutations happen BEFORE the match? Does the early-return arm undo them?
3. Does the early-return arm share a state-restoration block with other arms (deferred cleanup)? If not → state may be left partially mutated.
4. **Pattern to watch for**: `let old = self.field; self.field = new_value; match op() { Ok(_) => {}, Err(e) => return Err(e), // self.field is still set to new_value! }`

**Golden signature**: trigger the early-return path and assert the invariant holds after the function exits.

---

### CHECK 14 — Error/panic inside an atomic finalization hook → deterministic halt

**Signal**: any code reachable from a block-finalization hook — Cosmos `EndBlocker`/`BeginBlocker`, CometBFT/Tendermint `FinalizeBlock`/`PrepareProposal`/`ProcessProposal`, Substrate `on_initialize`/`on_finalize`, a Solana bank-finalization path — that can `panic!`/`unwrap`/`expect`/return an error driven by attacker-controllable state.

**Procedure**:
1. Enumerate every function transitively reachable from a finalization hook. These run on EVERY node deterministically — a panic/error here halts the whole chain, not one request.
2. For each, find inputs an unprivileged actor can influence: proposal contents (`x/group`, `x/gov`), message fields, account state created by prior transactions.
3. Hunt fallible ops on those inputs: division (div-by-zero), array/slice index (OOB), `unwrap`/`expect`, overflow-capable integer ops, `?` returning an error the hook does not tolerate.
4. Confirm the attacker can move the system into a state where the op is reached with the failing value AND the hook propagates failure to a halt. The bar: "any user that can interact with the module can introduce the state."

**Golden signature**: integration test that builds the malicious proposal/state, runs the finalization hook, asserts it panics/errors (and the patched code does not) — the PoC shape the Cosmos advisories' own validation used (patched node + failing state → no halt).

**Anti-pattern**: a hook that catches/logs each sub-operation error per item and continues — isolated, skipped failures produce no system-wide halt. Not this class.

**Source**: Cosmos SDK ISA-2025-002 EndBlocker error halt (GHSA-47ww-ff84-4jrg); ASA-2025-003 group-proposal div-by-zero (GHSA-x5vx-95h7-rv4p); CometBFT ASA-2024-011 (GHSA-p7mv-53f2-4cwj); ASA-2024-001 (GHSA-qr8r-m495-7hc4).

---

### CHECK 15 — Unvalidated proposer-injected consensus data

**Signal**: ABCI++/consensus code consuming proposer-supplied structures — vote extensions, injected transactions, voting-power summaries, `ExtendedCommit` — and using them for accounting or authorization.

**Procedure**:
1. Find every read of proposer-injected data (`VoteExtension`, injected txs, `ExtendedCommit`).
2. For each consumed field: is it re-validated against the canonical state machine, or trusted as-is? The flaw class: inferring total voting power FROM the injected extensions rather than reading power from state.
3. For identity/index fields that index into a set: is `ValidatorIndex` bounds-checked against the live `ValidatorSet` BEFORE use? An out-of-range index → array OOB → panic → halt.
4. Build the adversarial proposer: inflate a validator's power / point an index out of range and trace whether any check rejects it before it affects state or panics.

**Golden signature**: test submitting a proposer payload with a mutated power value / out-of-range index; assert the code accepts it (vulnerable) or rejects it (patched).

**Anti-pattern**: code that re-derives values from state and uses the injected data only as a hint/optimization, discarding it on disagreement.

**Source**: Cosmos SDK ASA-2024-006 ValidateVoteExtensions voting-power inference (GHSA-95rx-m9m5-m94v); CometBFT ASA-2024-011 unvalidated ValidatorIndex (GHSA-p7mv-53f2-4cwj).

---

### CHECK 16 — Positional state-identity collision

**Signal**: an internal map/index keyed by a value NOT guaranteed unique for the thing it identifies — slot number, height, sequence, any non-hash key for content that can legitimately exist in multiple variants.

**Procedure**:
1. Enumerate keys used to track distinct protocol objects (blocks, shreds, votes, computed state). For each: can two genuinely-different objects share this key?
2. Trace what breaks when two objects collide under one key: repair/sync, dedup, equivocation detection, fork choice. Positional keying means the intake code "has no way to distinguish object A vs B at the same position" → partitions cannot repair from each other.
3. For each collision-capable key, require either content-hash keying or a separately-enforced one-object-per-position invariant — and verify that invariant holds at the INTAKE layer, not just at consensus.

**Golden signature**: construct two valid-but-distinct objects with the same positional key; assert the code treats them as one (vulnerable) or distinguishes them (patched).

**Anti-pattern**: content-hash keys, or positional keys with a proven singleton invariant (e.g., equivocation slashing makes duplicates non-viable) enforced at intake.

**Source**: Solana Labs Dec-2020 mainnet-beta stall — two blocks per slot keyed by PoH slot number (u64).

---

### CHECK 17 — State-transition window escape

**Signal**: a deferred penalty/check that applies to objects in state X, plus an operation that re-homes an object from X to Y (redelegation, migration, transfer) while a pending check on X has not yet fired.

**Procedure**:
1. Identify deferred checks: penalties evaluated lazily (slashing applied at evidence-processing time, not misbehavior time), windows, grace periods.
2. For each, enumerate operations that re-home the object to a new owner/validator/account during the deferred window.
3. Ask: does the re-homed object remain liable for the pending check, or escape? A delegation that contributed to byzantine behavior, not yet slashed, redelegating before slashing applies → escapes the window (CWE-372 incomplete internal state distinction).
4. Invariant to assert: liability is bound to the period of misbehavior, not the object's current location.

**Golden signature**: test that (a) creates liability, (b) re-homes the object before the penalty fires, (c) triggers the penalty — assert it still lands on the original object.

**Anti-pattern**: protocols that snapshot liability at misbehavior time and carry it through re-homing. If liability travels with the object's history, not this class.

**Source**: Cosmos SDK ASA-2024-005 slashing evasion via redelegation, CWE-372 (GHSA-86h5-xcpx-cfqc).

---

### CHECK 18 — Cross-client / cross-impl divergence (depth-agent)

**Signal**: a protocol with multiple independent implementations (consensus clients, validator/full-node forks) handling the same edge case the spec underspecifies under stress.

**Procedure**:
1. Identify behaviors the spec leaves to implementer discretion: what to do when overloaded, how to resolve ambiguous forks, eviction/drop policy.
2. For each: do two reasonable implementations make DIFFERENT choices producing divergent liveness/safety? Under an attestation flood one client dropped attestations to stay live while another kept all forks and stalled — divergent liveness.
3. With only one implementation in scope, reason differentially against the reference spec: would a spec-faithful alternative behave the same? A divergence is a finding even without a second codebase to diff.
4. Prioritize edge cases under resource pressure and ambiguous-fork resolution.

**Golden signature**: differential harness feeding the same adversarial input to two impls (or impl vs spec model); assert identical state transitions.

**Anti-pattern**: behavior fully pinned by the spec (deterministic transition functions) where all implementations must agree by construction.

**Source**: Prysm vs Lighthouse divergence, Ethereum May-2023 finality incident (Prysm post-mortem, fix v4.0.4).

---

### CHECK 19 — Out-of-order protocol-rule application via sim/RPC path

**Signal**: a simulation or read RPC entrypoint that lets the caller override chain parameters/feature flags independently (`eth_call` block overrides, `debug_traceCall`, custom fork configs in a sim API). In Rust: revm/reth `eth_call` with state+block overrides.

**Procedure**:
1. Enumerate every entrypoint letting a caller set protocol-version/feature flags or block context independently of the canonical chain.
2. For each pair of features with an activation-ORDER dependency: can the caller enable a later feature while disabling an earlier one it depends on? (e.g. enable EIP2929 via merge-rules `random` while disabling EIP150 via block number.)
3. Trace the codepath reached by the impossible combination for unguarded arithmetic/allocation: a missing earlier-EIP gas check lets `gas + coldCost` overflow → undercharged CALL → ~128GB allocation → OOM.
4. Invariant: feature flags must be applied in canonical activation order; out-of-order combinations the real chain can never reach must be rejected, not executed.

**Golden signature**: send the crafted `eth_call`/sim request with the out-of-order override; assert the node rejects it (patched) vs crashes/over-allocates (vulnerable).

**Anti-pattern**: sim endpoints that derive the full ruleset from a single canonical fork schedule and forbid per-feature toggling. If features can't be independently toggled, ordering can't be violated.

**Source**: geth out-of-order EIP application DoS (iosiro Feb-2024, fixed v1.13.13). Corrects the prior "JSON-RPC re-entrancy" framing — no such re-entrancy incident exists.

---

## Phase 4: Framework-specific knowledge

### Cosmos SDK

- **`EndBlock` is atomic-ish.** State transitions in `EndBlock` roll back on panic, but events emitted and IBC commitments made BEFORE the panic do not. Sub-operations may have unguarded panic sites.
- **Module→module calls** use `Keeper` references. Error propagation depends on the specific keeper method's return type — not all keepers return structured errors.
- **Governance parameter changes** via `x/params` take effect immediately upon proposal execution unless the module reads and caches the parameter at block start (which most do — check `BeginBlock`).
- **Validator-set updates** happen in `EndBlock` and take effect next block's `BeginBlock`. One-block delay = old set active for one more block.

### Tendermint / CometBFT

- **Consensus rounds** advance monotonically via timeout. Timeout that fires during an already-completed step is discarded. No reverse-round advancement.
- **Equivocation evidence** via `MsgSubmitEvidence`. If evidence submitted same-block as validator rotation removing the equivocator → evidence may be rejected (validator not in active set). Timing race.
- **Block timestamps** are BFT-time: median of validator timestamps, extreme values penalized but the proposer has influence within the tolerance band.

### Ethereum (execution + consensus)

- **Slot/epoch boundaries** are explicit. Epoch transitions recalculate validator set, process attestations, update fork-choice. Bugs only at boundaries survive long testnet runs.
- **LMD-GHOST fork-choice** is client-implemented (not spec-code-generated). Different clients (Lighthouse, Prysm, Teku, Nimbus, Lodestar) have had divergent implementations → missed slots, temporary forks.
- **Engine API** (execution↔consensus): JSON-RPC boundary. Version mismatch → consensus calls method execution doesn't implement → block production halts.

### Solana

- **PoH ticks** are the clock. Validator PoH generator drift → wrong-slot blocks → rejected votes.
- **Instruction atomicity**: multi-instruction tx → instruction N fails → 1..N−1 rolled back. But a SINGLE instruction that panics mid-execution: VM catches and rolls back account writes, but CPI/event side effects in other runtimes may persist.
- **Runtime upgrades** at epoch boundary: old runtime finishes epoch, new runtime starts next. New runtime misinterpreting old-runtime state is a distinct bug class.

### Substrate / Polkadot

- **Runtime upgrades** via `set_code`: new WASM blob replaces old. Storage migrations run as part of the upgrade — migration bugs transforming old→new state format are a distinct class.
- **`on_initialize` / `on_finalize`** per pallet, ordered by pallet index. Cross-pallet invariants spanning the hook boundary are manual — no compiler enforcement.
- **`BlockNumber` is `u32`** in most runtimes. Epoch arithmetic at `u32::MAX` wraps; CHECK 3 must test this boundary.

---

## Stage-3 PoC discipline

### Stateright (gold standard — model checking)

```rust
use stateright::*;

struct ConsensusModel { /* state, actions */ }
impl Model for ConsensusModel {
    type State = State;
    type Action = Action;
    fn init_states(&self) -> Vec<Self::State> { /* genesis state */ }
    fn actions(&self, s: &Self::State, actions: &mut Vec<Self::Action>) { /* enabled transitions */ }
    fn next_state(&self, s: &Self::State, a: Self::Action) -> Option<Self::State> {
        /* state transition — None if action invalid in this state */
    }
    fn properties(&self) -> Vec<Property<Self>> {
        vec![
            Property::always("no_conflicting_finalize", |_, s| !s.has_conflicting_finalized_blocks()),
            Property::always("eventually_terminates", |_, s| s.round < MAX_ROUNDS),
        ]
    }
}
```

`stateright` finds a counterexample trace → Tier-1-formal-equivalent.

### proptest state-machine (fallback)

```rust
proptest! {
    #[test]
    fn test_state_invariant_holds(actions in proptest::collection::vec(any::<Action>(), 0..100)) {
        let mut state = State::genesis();
        for action in actions {
            state = state.apply(action).unwrap_or(state);
            assert!(state.invariant_holds(), "invariant broken after {:?}", action);
        }
    }
}
```

### Framework-specific patterns

**For TOCTOU / async-cancellation (CHECK 5, 6)**:
```rust
#[tokio::test]
async fn test_no_toctou_on_reentry() {
    let mut state = TestState::new();
    let handle = spawn_reentrant_task(&mut state);
    // interleave mutation during external call window
    state.mutate_shared_field();
    handle.await;
    assert!(state.invariant_holds());
}
```

**For error propagation (CHECK 12)**:
```rust
#[test]
fn test_error_propagates_through_chain() {
    let mut deepest = MockC::new().with_error(Injection::Fail);
    let result = entry_point_a(&mut deepest);
    assert!(result.is_err(), "error from C should reach A");
    assert!(matches!(result.unwrap_err(), Error::InsufficientFunds), "error type preserved");
}
```

**For equivocation (CHECK 9)**:
```rust
#[test]
fn test_surround_vote_detected() {
    let vote_a = Vote { source: Epoch(1), target: Epoch(4) };
    let vote_b = Vote { source: Epoch(2), target: Epoch(3) }; // surrounded by A
    let result = equivocation_detector.check(&vote_a, &vote_b);
    assert!(result.is_slashable(), "surround vote not detected");
}
```

### Fallback chain

If stateright/proptest infeasible (complex state, external deps):
1. Manual boundary-value trace with concrete inputs at epoch 0, 1, MAX.
2. Error-injection test: mock the deepest call, verify error reaches the top.
3. Invariant-synthesis-only: document the invariant, the code path that breaks it, and the concrete input sequence → Tier-3-unit.

---

## Output fields beyond shared FINDING schema

```yaml
state_invariant: <the property that should hold>
violation_sequence: <the operation sequence that breaks it>
check_number: <CHECK 1-19>
verification_class: model-check | property-fuzz | manual-trace | error-injection | none
poc_file: <path to harness or test>
golden_signature: <counterexample trace | shrunken input | error-injection result | cited code lines>
framework_note: <CosmosSDK/Tendermint/Ethereum/Solana/Substrate — specific semantics enabling the bug>
```

---

## Anti-patterns (do NOT report)

- "This `match` doesn't handle every variant" — if the variants are documented as unreachable and `unreachable!()` guards them, it's not a finding.
- Race conditions on test-only state or in test harness code.
- Async-cancellation concerns where the runtime never triggers cancellation (single-threaded, no timeout).
- Generic "this could go wrong" without a concrete violation sequence — state the operation sequence and the broken invariant explicitly.
- Functions with explicit rollback (`mem::replace`, `Drop` cleanup) — these are correct defensive patterns, not partial writes.
- Clock reads that affect ONLY logging/metrics — these don't affect consensus state.

---

## Coordination with other angles

- **Concurrency (Angle 4)**: deadlock/data race. When a logic bug is enabled by a race, both fire. Angle 4 produces Loom evidence; Angle 7 produces the state-machine invariant violation.
- **Arithmetic (Angle 3)**: overflow/truncation. When overflow corrupts epoch/slot arithmetic, Angle 3 finds the overflow; Angle 7 frames the consensus impact. CHECK 3 (epoch boundary) bridges to Arithmetic CHECK 3 (epoch truncation).
- **Crypto Misuse (Angle 5)**: primitive-level crypto. When a protocol mishandles BLS aggregation or sig verification ordering, Angle 5 owns primitive misuse; Angle 7 owns the protocol integration. CHECK 9 (equivocation) bridges to crypto signature verification.
- **Economic Design (smart-contract mode)**: governance-parameter ordering (CHECK 10) overlaps. Angle 7 owns the state-machine ordering; Economic Design owns governance-process risk. File under Angle 7 with Economic Design cross-reference.
- **Memory Safety (Angle 1)**: when partial-state write leads to use-after-free or double-free. Angle 7 identifies the partial write; Angle 1 finds the UB.
- **First Principles** (no longer a separate angle in `infra` mode) — Angle 7 absorbs the "find bugs no other angle owns" mandate.
