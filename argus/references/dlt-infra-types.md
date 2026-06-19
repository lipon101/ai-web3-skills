# DLT Infrastructure Threat Profiles

> Used at Stage 1 (classify the infra component) and Stage 2 (each angle reads the matching profile).
>
> Counterpart to `rust-protocol-types.md` (which covers smart-contract protocol types). This file covers **DLT infrastructure** — the systems-Rust code that runs the chain, not the applications on top.

## Component classification (Stage 1)

Detect component type from function signatures, dependency set, and architectural patterns. A codebase may match **multiple** types (hybrid); rank by signal density.

| Type | Detection signals (Rust) |
|------|--------------------------|
| **Validator client / node** | `tokio` runtime, RPC server (`jsonrpsee` / `tonic`), block-import pipeline, transaction pool, peer manager, slot/epoch scheduler, validator-key custody. Examples: `solana-validator`, `polkadot-sdk-node`, `cometbft-rs`, `lighthouse`. |
| **Consensus engine** | Vote types, fork-choice rule, finality logic, equivocation detection, signature aggregation, view-change / round transitions, leader rotation. Examples: `solana-vote-program`, `sp-consensus-grandpa`, BFT round logic, Tendermint state machine. |
| **P2P networking** | `libp2p` integration, peer scoring, gossip topic management, request-response protocols, encryption / handshake, NAT traversal, peer-discovery (Kademlia / mDNS). Examples: `libp2p-gossipsub` consumers, `quinn` (QUIC), `snow` (Noise). |
| **Cryptographic library** | Curve arithmetic (`curve25519-dalek`, `secp256k1`, `ark-*`, `arkworks`), BLS aggregation, hash functions, signature schemes, MPC primitives, constant-time operations, secret zeroization. |
| **ZK proof circuit** | `halo2_proofs` / `halo2_gadgets` / `halo2curves` circuit definitions (`Circuit` trait, `Chip` structs, `configure()` with custom gates, lookup arguments), `ark-relations` / `ark-r1cs-std` constraint systems, `bellpepper` / `bellman` synthesis, `plonky2` / `plonky3` gate definitions. Detection: files in `circuits/`, `gadgets/`, `chips/`, `constraints/`; `impl Circuit<F>` blocks; `create_gate` / `create_lookup` invocations; `ConstraintSystem` allocations. |
| **Storage engine** | `rocksdb` / `sled` bindings, custom MVCC, write-ahead log, snapshot management, pruning, state-tree (Merkle / Verkle / IAVL), DB-encoding (Borsh / Bincode / SCALE). |
| **RPC / API node** | `jsonrpsee` / `axum` / `tonic` handlers, request rate-limiting, subscription management, websocket streaming, response serialization, query-cost accounting. |
| **Off-chain worker / oracle / relayer** | Periodic poll loop, external HTTP fetch, signed payload submission, retry/backoff, on-chain submission via signed tx. |
| **Bridge / IBC / cross-chain relayer** | Light-client verification, validator-set tracking, message-relay queue, finality-proof verification, replay protection, packet-timeout handling. |
| **Wallet / signing library** | Key derivation (BIP32/SLIP10), key storage (encrypted, hardware-backed), transaction signing, address generation, mnemonic handling. |
| **Smart-contract execution VM** | BPF / Wasm / EVM interpreter, instruction metering, syscall dispatch, memory management, sandboxing, deterministic execution guarantees. Examples: `solana_rbpf`, `wasmtime`-on-Substrate, custom Move VM. |
| **Generic Rust DLT crate** | Async services, FFI to C consensus / crypto, custom allocator usage, `unsafe` blocks for performance, networking middleware. |

## Threat profiles by component type

Each profile: **primary adversaries** (ranked), **dominant attack patterns**, **critical invariants**, **what to look for first**.

### Validator client / node

**Primary adversaries**:
1. **Remote peer (untrusted network)** — anyone who can connect; gossip + RPC + p2p surface.
2. **Malicious validator in the set** — can sign messages, propose blocks, equivocate.
3. **Block-author attacker** — controls one slot per epoch (or similar).
4. **Local attacker with access to validator keys** — if key custody is weak.
5. **Compromised dependency** — supply chain.

**Dominant attack patterns**:
- Crash via crafted p2p message (panic-DoS → validator down → reduced security).
- Crash via crafted RPC payload (deserialization panic).
- Memory exhaustion via unbounded buffer / queue.
- CPU exhaustion via quadratic processing.
- State corruption via malformed block accepted into local DB.
- Validator key extraction via memory disclosure / side channel.
- Fork-choice manipulation via crafted finality message.

**Critical invariants**:
- No panics reachable from untrusted input (`p2p`, RPC, mempool).
- Bounded queues; no unbounded `Vec::push` from peer input.
- Validator keys never in plaintext memory beyond signing operation; zeroized after use.
- Block-acceptance is deterministic — same block produces same state across nodes.
- Equivocation is locally detectable and slashable.

**What to look for first**:
- Every `unwrap()` / `expect()` / slice-index in a p2p / RPC handler path.
- Bounded-vs-unbounded queues at every network input.
- Validator-key lifetime — when allocated, when used, when zeroized.
- Borsh / SCALE / Bincode deserialization of untrusted bytes (length-prefix DoS, canonical-form drift).
- Async cancellation safety on every `select!` involving partial state.

### Consensus engine

**Primary adversaries**:
1. **Byzantine validators** — up to f or 1/3 collude.
2. **Network-partition exploiter** — induces partition, exploits view-change.
3. **Equivocator** — signs conflicting votes.
4. **Slow / silent validator** — denial of progress.

**Dominant attack patterns**:
- Safety violation: two conflicting blocks finalized.
- Liveness violation: progress stalls indefinitely.
- Fork-choice manipulation via vote-counting bug.
- View-change / round-transition skip allowing leader hijack.
- Signature-aggregation soundness gap (BLS pubkey-set malformation).
- Equivocation-detection gap (missed conflicting vote).

**Critical invariants**:
- Safety: never finalize conflicting blocks at the same height.
- Liveness: under partial synchrony with > 2/3 honest, progress is guaranteed.
- Validity: only valid blocks finalize.
- Accountability: every safety violation is provably attributable.

**What to look for first**:
- Vote-counting arithmetic (off-by-one in quorum, threshold rounding direction).
- View / round transition: every guard, every state machine edge.
- Signature aggregation: pubkey-set well-formedness checks (`pop_verify`).
- Equivocation detection: every signed message vs prior signed message at same height/round.
- Random-beacon / leader-rotation determinism.

### P2P networking

**Primary adversaries**:
1. **Sybil attacker** — many cheap peer identities.
2. **Eclipse attacker** — surrounds a target peer.
3. **DoS attacker** — floods with traffic.
4. **Malicious gossip publisher** — crafts payload to amplify or crash.

**Dominant attack patterns**:
- Resource exhaustion via slow-loris connections, oversized messages, unbounded subscription state.
- Peer-table poisoning (Eclipse).
- Gossip-amplification (one message → exponential fan-out).
- Handshake-state-machine confusion (Noise / TLS edge cases).
- Encryption-key extraction via timing / side channel.
- Connection-limit bypass (resource budget per peer not enforced).

**Critical invariants**:
- Per-peer resource budget (memory, CPU, connections) enforced.
- Message size bounded at the wire level.
- Peer scoring is monotonic-on-bad-behavior.
- Handshake state machine has no `unwrap()` / panic on attacker bytes.

**What to look for first**:
- Inbound message size limits at every protocol boundary.
- Per-peer connection accounting; no leak on disconnect.
- Handshake / cipher-state lifecycles for memory disclosure.
- Gossip-amplification factor (how many neighbors get a forwarded message).
- QUIC / TCP stream cancellation safety.

### Cryptographic library

**Primary adversaries**:
1. **Side-channel attacker** — timing, memory access, branch prediction.
2. **Chosen-input attacker** — picks worst-case inputs to verify functions.
3. **Implementation-bug exploiter** — finds non-constant-time path, missing zeroization, edge case in curve arithmetic.

**Dominant attack patterns**:
- Timing leak in scalar multiplication / signature verification.
- Branch-dependent on secret bit (`if secret_bit { do_x }`).
- Memory not zeroized after secret use.
- Curve-point validation skipped (small-subgroup attack).
- Signature malleability (high-S, missing nonce binding).
- Hash function collision (downgraded usage of MD5/SHA1).
- RNG misuse (`rand` instead of `OsRng` for keys).

**Critical invariants**:
- All operations on secrets are constant-time.
- All secret-bearing types implement `Zeroize` + `Drop`.
- Curve points validated as on-curve and in subgroup before use.
- Signature verification rejects malleable signatures.
- Random number generator is `OsRng` or a documented CSPRNG.

**What to look for first**:
- Every `if x == y` where `x` or `y` is secret-derived (replace with constant-time `subtle::Choice`).
- Every `secret_bytes.iter()` (replace with constant-time iteration).
- `Drop` implementations on secret-holding structs — zeroize before drop.
- Every curve-point construction: validated?
- RNG choice at every key-generation site.

### ZK proof circuit

**Primary adversaries**:
1. **Malicious prover** — constructs witness that satisfies all stated constraints but violates unstated invariants.
2. **Circuit-author error** — constraint system is incomplete by construction; every prover is potentially adversarial.
3. **Cross-chip composition gap** — two chips pass a value via copy-constraint but neither fully constrains it.
4. **Spec-to-circuit drift** — the spec says "X must be a valid EC point in the correct subgroup" but the circuit only checks "X is on the curve" (missing subgroup check) or doesn't check X at all.

**Dominant attack patterns**:
- Under-constrained witness cell: cell allocated, never read by any gate, prover sets to arbitrary value (J02).
- Missing constraint on structured input: EC point, hash preimage, or secret scalar accepted without domain validation (J01, J03, J04, J05).
- Custom gate missing a term: gate declares `f(a,b,c) = 0` but the spec requires `f(a,b,c) = 0 AND g(a,b,c) = 0` (J06).
- Lookup argument bypassed: prover controls the enable selector, disables lookup, sets cell out-of-table (J07).
- Copy-constraint omission: two cells should be equal but no copy constraint links them (J08).
- Selector-condition gap: one selector path constrains the cell, another path doesn't, prover takes the unconstrained path (J09).

**Critical invariants**:
- Every advice/witness cell is read by at least one gate.
- Every assigned (non-computed) cell is constrained to a valid domain (range, boolean, point-on-curve, canonical-encoding).
- Every cross-chip copy-constraint pair constrains the shared cell in both chips.
- Every lookup argument's enable selector is forced to 1 (not prover-controllable) unless the lookup is genuinely optional.
- The circuit's constraints enforce the spec's invariants, not just the author's intent.

**What to look for first**:
- Every `assign_advice` / `alloc` call where the assigned value is a structured input (point, scalar, hash) — trace to verify domain constraint.
- Every custom gate expression in `configure()` — derive the intended relationship from comments/docs, check for missing terms.
- Every copy-constraint between chips — read both chips' constraint sets for the shared cell.
- Every `bool_check` / `range_check` gate — verify it fires unconditionally for the relevant cell.
- Every `from_bytes` / `from_repr` in witness generation — verify canonical-encoding check in circuit.

**Canonical example**: Zcash Orchard circuit (vulnerability discovered May 2026 by Taylor Hornby using Opus 4.8). An EC multiplication in the circuit accepted an arbitrary point as input; the gate verified `s · P = Q` was computed correctly but did not constrain `P` to be the specific point it should have been. A malicious prover could supply a false `P` and produce a valid proof → undetectable counterfeiting. Present from Orchard activation (May 2022) until emergency fix (June 2026). The vulnerability evaded ~4 years of cryptographer scrutiny because circuit-level constraint soundness is a distinct threat model from integration-level ZK bugs (public-input pollution, verifying-key swap) and from primitive-level crypto misuse (RNG, constant-time, zeroization).

### Storage engine

**Primary adversaries**:
1. **State-corruption attacker** — crafts inputs that desync DB from canonical state.
2. **DoS attacker** — fills DB, blocks pruning, exhausts disk.
3. **Snapshot-poisoner** — provides malicious snapshot to a syncing node.

**Dominant attack patterns**:
- WAL corruption via crash mid-write; not replayed correctly on restart.
- Merkle-tree integrity violation via key collision (V127-style).
- Pruning skipping live data → orphaned state.
- Snapshot deserialization panic (length-prefix DoS).
- Compaction-ordering bug producing tombstone resurrection.

**Critical invariants**:
- DB state = canonical chain state at all finalized heights.
- Pruning removes only data beyond finality.
- Snapshot deserialization is bounded-CPU and bounded-memory.
- Encoding round-trips: `decode(encode(x)) == x` for all `x`.

**What to look for first**:
- WAL replay logic on crash recovery.
- Pruning boundary conditions (finalized height transitions).
- Snapshot byte-format validation (size limits, schema version).
- Borsh / SCALE / Bincode decoder for untrusted snapshot input.

### RPC / API node

**Primary adversaries**:
1. **Unauthenticated HTTP / WS attacker**.
2. **Authenticated but rate-unlimited client**.
3. **Subscription-spam attacker** (long-lived subscriptions exhaust state).

**Dominant attack patterns**:
- Crafted JSON-RPC payload causes deserialization panic.
- Unbounded query (e.g., `getBlockRange(0, latest)`) exhausts CPU.
- Subscription leak (sub created, client disconnects, state retained).
- Response amplification (1-byte request → MB response).
- Cache poisoning via crafted request.

**Critical invariants**:
- Every public RPC method has a per-request CU / weight / gas budget.
- Every subscription has a TTL and is cleaned on disconnect.
- Response size is bounded per request.
- Authentication failures are constant-time.

**What to look for first**:
- Every public RPC handler: input size limit, processing-cost limit.
- Subscription state: who owns the state, when is it freed.
- WebSocket lifecycle: graceful close, abrupt-close cleanup.
- Cache eviction policy under adversarial fill.

### Bridge / IBC / cross-chain relayer

**Primary adversaries**:
1. **Forged-message attacker** (compromised validator set or signature gap).
2. **Replay attacker** (same message processed twice).
3. **Reorg attacker** (source chain reverts, destination doesn't).
4. **Light-client-soundness attacker** (forges header / proof).

**Dominant attack patterns**:
- Signature aggregation soundness gap.
- Era / epoch boundary race (V129-style).
- Validator-set handoff mishandled.
- Replay protection missing or per-chain nonce gap.
- Timeout-handler missing → locked funds.
- Decimal-conversion error between source / destination.

**Critical invariants**:
- `total_locked_source == total_minted_destination` modulo in-flight.
- Every message processed exactly once.
- Light-client only accepts headers signed by quorum of canonical validator set.
- Reorg-safety: only finalized source blocks credit destination.

**What to look for first**:
- Validator-set rotation logic at every era boundary.
- Replay-set: bounded? Per-chain? Eviction policy?
- Light-client header acceptance: every field validated.
- Decimal conversion: tested across every supported chain pair.

### Wallet / signing library

**Primary adversaries**:
1. **Local attacker with process access**.
2. **Malicious caller via FFI / API**.
3. **Side-channel attacker** (timing, memory pattern, branch prediction).

**Dominant attack patterns**:
- Private key in plaintext memory beyond signing.
- Key derivation misuse (wrong path, attacker-controlled seed).
- Signature randomness reuse (k reuse → key extraction).
- Mnemonic-handling memory leak.
- Address-derivation collision (wrong encoding, missing checksum).

**Critical invariants**:
- Private keys zeroized on Drop; never traversed in non-constant-time.
- Signing randomness is deterministic (RFC 6979) or CSPRNG, never reused.
- Mnemonic bytes zeroized after key derivation.
- Address checksums validated on import.

**What to look for first**:
- Every key-holding struct: `Drop` + `Zeroize`.
- Signing path: randomness source, k uniqueness.
- BIP32/SLIP10 derivation: hardened-only at top levels.
- Address parsing: checksum validation.

**Canonical example**: `monero-oxide` (Monero protocol Rust libraries — wallet, RingCT, crypto primitives, address derivation). Project shape `generic-rust`, Immunefi bounty tagged Blockchain/DLT, $100K max bounty. This is the reference target for `infra` mode wallet/crypto-library audits. Prior Argus runs (v0.1.3, v0.2.5) attempted SC mode and produced the F-15 `Decoys::select_n` false positive (externally judged INVALID for structural unreachability), which drove the v0.3.0 pivot. Per `audit-modes.md` recommendation discipline, all future monero-oxide runs MUST be `infra` mode.

### Smart-contract execution VM

**Primary adversaries**:
1. **Malicious contract author** — uploads bytecode to exploit interpreter bugs.
2. **Network attacker** — feeds crafted bytecode via gossip / RPC.
3. **VM-escape attacker** — escapes sandbox to access host.

**Dominant attack patterns**:
- Instruction-metering bypass (cheap opcode that does expensive work).
- Memory-bounds bypass in interpreter (out-of-bounds read in guest → leaks host memory).
- Syscall-dispatch confusion (call wrong syscall by ID).
- Deterministic-execution violation (same input, different output across nodes).
- Non-terminating program acceptance (gas / weight runs out, but the bug is the metering itself).

**Critical invariants**:
- Every instruction's cost reflects worst-case work.
- Guest memory accesses are bounded by guest's allocation, not host's.
- Syscall dispatch is total (every ID handled or rejected).
- Execution is deterministic across all validator targets.

**What to look for first**:
- Cost table: every opcode mapped, sibling-opcode-derived costs flagged (V102-style).
- Memory bounds in every guest→host call.
- Syscall dispatch: total function over ID space.
- Floating-point usage in guest path (nondeterministic by default).

## Temporal threat dimension (DLT infra lifecycle)

Different threats dominate at different phases. Include applicable phases in Stage 1's hot-zones.

| Phase | Include when |
|-------|--------------|
| **Bootstrap** | Genesis loading, initial validator-set setup, first-epoch transition |
| **Steady-state** | Always |
| **Network stress** | DoS scenarios, partition handling, validator churn, gossip storms |
| **Upgrade / hard-fork** | Runtime upgrade, migration, schema-version change, validator-set rotation |
| **Recovery** | Reorg, equivocation detection, slashing, mass-unstake, emergency halt |
| **Deprecation** | Old-version-still-running, migration window, deprecated-message handling |

## Composability threats (cross-component within a node)

A validator client integrates: consensus + p2p + storage + crypto + RPC + VM. Bugs straddle these boundaries.

| Boundary | Typical hazard |
|----------|----------------|
| p2p → consensus | Crafted block message reaches consensus before validation |
| RPC → mempool | Crafted tx causes mempool corruption |
| Consensus → storage | Finalization triggers DB write that fails partway |
| VM → storage | Contract syscall corrupts host DB state |
| Crypto → consensus | Aggregate signature with malformed pubkey set accepted |
| Circuit → crypto | Circuit assumes primitive validates input; crypto library assumes circuit constrains it — neither does |
| Circuit → wallet | Wallet trusts proof output without verifying the circuit that produced it |
| Circuit → bridge | Bridge accepts proof from circuit as valid state-transition evidence; under-constrained circuit enables counterfeit state transition |
| Storage → RPC | Pending DB write read by RPC before commit |

These are the **integration bugs** the per-component profiles miss; Stage 2's Logic & State Machine angle owns them, except circuit-boundary bugs which are owned by the ZK Circuit Soundness angle (Angle 9).

## What's NOT in this file

- Per-vector descriptions (those live in `attack-vectors/dlt-infra-attack-vectors.md`, coming in Chunk 2).
- Per-angle methodology (those live in `hacking-agents/infra/*-agent.md`, coming in Chunk 2).
- Backend tool invocation (Miri / Kani / Loom / Rudra / cargo-fuzz — those live in `infra-backends.md`, coming in Chunk 3).
