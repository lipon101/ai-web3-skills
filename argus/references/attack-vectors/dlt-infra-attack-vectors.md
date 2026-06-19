# DLT Infrastructure Attack Vectors — `infra` mode catalogue

> Used in `infra` mode only (per `references/audit-modes.md`). Counterpart to `rust-attack-vectors.md` (V1-V132, `smart-contract` mode).
>
> **93 vectors across 10 groups (A–J)**. Each entry includes ID, vector title, detection tool, **golden signature** (the exact substring the tool emits when the bug is confirmed), and the DLT component most affected.

## Tool-confirmation model

This catalogue is **deterministic-backend-first**. Each vector specifies the tool that turns the LLM's hypothesis into a tool-confirmed finding. The Stage 3 orchestrator runs the specified tool, captures output, and matches against the golden signature substring. Match → **CONFIRMED**, the tool output is the evidence. No-match → **DISPROVED** or **INCONCLUSIVE**.

This replaces `smart-contract` mode's Pass C single-orchestrator-judge for the ~30-40% of bugs the tools cover. The remaining 60-70% (Group F logic bugs, some Group E crypto, all Group H supply-chain manual-review items) still go through the standard Pass A/B/C/D pipeline.

## Group A — Memory Corruption & UB (Miri primary)

Every vector confirmable under `cargo miri test [-- ARGS]` with `MIRIFLAGS` set appropriately. Owned by **Angle 1 — Memory Safety**.

| ID  | Vector | Detection Tool | Golden Signature | DLT Component |
|-----|--------|---------------|------------------|---------------|
| A01 | Transmute: size mismatch | Miri (`cargo miri test`) | `error: Undefined Behavior: type <T> has size X, but transmuted type has size Y` | any |
| A02 | Transmute: lifetime extension | Miri | `error: Undefined Behavior: encountered a reference that does not satisfy its lifetime` | any |
| A03 | Stacked Borrows violation (shared-mut conflict) | Miri `MIRIFLAGS="-Zmiri-tag-raw-pointers"` | `error: Undefined Behavior: write to <location> through mutable pointer, but the allocation is already borrowed as shared` | p2p networking (shared buffers), validator client |
| A04 | Invalid pointer arithmetic out of allocation | Miri | `error: Undefined Behavior: inbounds test failed: pointer computed with offset X is inbounds of allocation` | storage engine (custom buffers), wallet |
| A05 | Uninitialised memory read (`MaybeUninit::assume_init` without write) | Miri | `error: Undefined Behavior: type <T> is not valid for the memory it points to (uninitialized)` | any |
| A06 | Double free via manual `drop_in_place` | Miri | `error: Undefined Behavior: freeing memory with free but the allocation was already freed` | consensus engine (custom structures) |
| A07 | Use-after-free (dangling reference from temporary) | Miri | `error: Undefined Behavior: pointer to <location> was dereferenced after being freed` | p2p, RPC |
| A08 | Integer-to-pointer cast (provenance loss) | Miri | `error: Undefined Behavior: invalid pointer: 0x... is not a valid pointer` | bridge relayer, off-chain worker |
| A09 | Data race on `UnsafeCell` | Miri (`-Zmiri-detect-data-races`) | `error: Undefined Behavior: Data race detected on <location>` | consensus, peer threads |
| A10 | Incorrect alignment in raw reads/writes | Miri | `error: Undefined Behavior: accessing memory at <alignment X> but pointer requires alignment Y` | storage, serialization |

## Group B — Unsound Unsafe Abstractions (Rudra primary, Kani / Miri secondary)

Owned by **Angle 2 — Unsafe Trait Soundness**.

| ID  | Vector | Detection Tool | Golden Signature | DLT Component |
|-----|--------|---------------|------------------|---------------|
| B01 | `Send` impl on type containing `UnsafeCell` without synchronisation | Rudra (or manual Kani proof) | Rudra warning `unsafe_send`; Kani counterexample showing data race | any multithreaded component |
| B02 | `Sync` impl on type with interior mutability not behind lock | Rudra / Loom | `Data race detected under concurrent access` | p2p, validator |
| B03 | `TrustedLen` impl reporting length > actual elements | Kani harness + property test | Kani counterexample: `iterator.size_hint()` != actual `count()` | generic |
| B04 | Custom `Drop` leaking resources or double-free | Miri | UB at drop time: double-free or memory leak | storage, consensus |
| B05 | `ExactSizeIterator` with incorrect `len()` | Kani proptest | Fuzzer finds mismatch between `len()` and `count()` | any |
| B06 | Unsafe `impl Deref` violating provenance invariant | Miri | UB on dereference; Miri reports provenance violation | generic |
| B07 | Unsafe `impl From` that breaks type invariant | Kani + custom contract | Contract precondition violated after conversion | serialization |
| B08 | Custom allocator alignment violation | Miri | `alloc layout mismatch` error | storage engine |
| B09 | Unwind safety: panic in `unsafe` block leaving dangling state | Miri + custom test | UB on panic: destructor runs on partially-initialised memory | any |
| B10 | `repr(C)` struct with wrong field order for FFI | `cargo check` with Clippy `improper_ctypes` | Clippy warning `improper_ctypes_definitions` | FFI wrappers |

## Group C — Integer Overflow & Arithmetic (Kani primary)

Owned by **Angle 3 — Arithmetic**.

| ID  | Vector | Detection Tool | Golden Signature | DLT Component |
|-----|--------|---------------|------------------|---------------|
| C01 | Unchecked index from user input: `slice.get_unchecked(user_idx)` | Kani proof that `user_idx < slice.len()` fails | Kani counterexample: `assert!(idx < slice.len())` fails | p2p message parsing |
| C02 | `Vec::with_capacity(user_len * size)` overflow | Kani | CBMC overflow check: `arithmetic overflow` | any |
| C03 | Arithmetic underflow in subtraction used for bounds check | Kani | `(a - b) < limit` fails when `a < b` and underflows | consensus rewards, epoch math |
| C04 | Lossy cast `u64` → `usize` on 32-bit target | Kani with 32-bit configuration | `assert!(x as usize as u64 == x)` fails | off-chain worker |
| C05 | Wrapping multiplication for fee calculation | Kani | `fee = amount * rate` overflow detected | wallet, token transfers |
| C06 | Off-by-one due to exclusive range mishandling | Kani + property test | `for i in 0..len` vs `0..=len` mismatch | consensus logic |
| C07 | Incorrect size calculation for mmap / allocation | Kani | `Layout::from_size_align(size, align)` returns error | storage |
| C08 | Truncation of timestamp in arithmetic | Kani | Timestamp arithmetic wraps (`now + deadline` overflow) | consensus, bridge |

## Group D — Concurrency & Sync Primitives (Loom primary, Miri secondary)

Owned by **Angle 4 — Concurrency**.

| ID  | Vector | Detection Tool | Golden Signature | DLT Component |
|-----|--------|---------------|------------------|---------------|
| D01 | Lock ordering deadlock | Loom | Loom reports a deadlock schedule | p2p peer manager |
| D02 | Lost wake-up on `Condvar` | Loom | Test fails: thread never wakes | validator voting |
| D03 | `Arc` refcount overflow (e.g., 2^64 clones) | Kani (bounded) or fuzzing | Refcount wraps to 0 causing premature free | any heavily-cloned object |
| D04 | `Relaxed` ordering on shared flag used for synchronisation | Loom + manual review | Loom sees inconsistent values across threads | networking flags |
| D05 | `UnsafeCell` unprotected by any guard | Miri data-race detection | `Data race detected on <location>` | any |
| D06 | `mem::transmute` cast between `MutexGuard` lifetimes | Miri | UB due to aliasing | generic |
| D07 | `RwLock` writer starvation due to continuous readers | manual review (no tool) | Logic bug flagged with reproduction scenario | RPC node |
| D08 | Incorrect `Cell` / `RefCell` usage in `Send` context | Rudra / manual | Rudra `unsafe_send` or runtime panic on borrow | any |

## Group E — Cryptographic Failures (Manual + Clippy + targeted tests)

Owned by **Angle 5 — Crypto Misuse**. Most Group E vectors are not directly tool-confirmable; the "golden signature" is the test result or the dependency match.

| ID  | Vector | Detection Tool | Golden Signature | DLT Component |
|-----|--------|---------------|------------------|---------------|
| E01 | `rand::random` for key material instead of `OsRng` | Clippy `no_stdlib_rand` lint or grep | `rand::random` invoked in key-generation path | wallet, crypto lib |
| E02 | Non-constant-time comparison (`==` on secrets) | manual review + `dudect` | Timing leak > threshold | crypto library |
| E03 | Missing zeroisation of `[u8; KEY_LEN]` on drop | grep for `#[derive(Zeroize)]` absence | Memory dump shows key remains after use | wallet, key management |
| E04 | MD5 or SHA-1 used for security | grep + Clippy `deprecated_crypto` | Hash function deprecated for collision-resistance | bridge, consensus |
| E05 | Nonce reuse in Ed25519 / ECDSA signing | static analysis of nonce generation | Two signatures with same `(r)` value → key recovery | consensus, wallet |
| E06 | Weak prime in DH / RSA | dependency check + manual | Strong-curve recommendation not followed | bridge, p2p |
| E07 | Improper error handling in signature verification (accepts `Ok` for invalid sig) | unit test with invalid signature | Test expects error but gets `Ok(())` | validator, wallet |
| E08 | Side-channel via early-exit in verifier | dudect or manual | Timing varies with input | crypto library |

## Group F — Resource Exhaustion & DoS (Fuzzing + Static)

Owned by **Angle 6 — Resource Exhaustion**.

| ID  | Vector | Detection Tool | Golden Signature | DLT Component |
|-----|--------|---------------|------------------|---------------|
| F01 | Unbounded `Vec::push` from network input | `cargo-fuzz` / `afl.rs` | Memory grows without bound; OOM crash | p2p message handlers |
| F02 | Quadratic complexity in nested loops over user input | Fuzzer + time measurement | Execution time grows quadratically with input size | transaction validation |
| F03 | Deep recursion from recursive data structure | Fuzzer with deeply-nested input | Stack overflow | parser, deserializer |
| F04 | Long-held locks during async I/O | manual review + Loom | Lock held across `.await`; runtime stalls | RPC node |
| F05 | Large allocation from attacker-controlled capacity | Kani or fuzz: `with_capacity(attacker_val)` | `panic` or OOM | any |
| F06 | Repeated string allocation & cloning (memory amplification) | Fuzzer | RSS grows disproportionate to input | p2p gossip |
| F07 | HashDoS: untrusted keys in `HashMap` with predictable hasher | grep for `BuildHasherDefault` over user-keyed maps | Deterministic collisions → O(n²) lookups | any |
| F08 | Allocate-then-check with ceiling exceeding true protocol limit (Zebra `addr` / `headers` / `TrustedPreallocate` class) | compare `max_allocation()` / `TrustedPreallocate` bound against documented spec limit; flag any >2× gap | Memory allocation spike before rejection; bound is from transport ceiling (2 MiB) or block-size ceiling, not the protocol-spec limit | p2p networking, serialization (added v0.3.4 from Zebra CVE pattern E) |

## Group G — Error Handling & State Machine Integrity (Model checking + Fuzzing)

Owned by **Angle 7 — Logic & State Machine**.

| ID  | Vector | Detection Tool | Golden Signature | DLT Component |
|-----|--------|---------------|------------------|---------------|
| G01 | Missing `?` causing `Result` silently ignored | Clippy `try_err` or manual | Error not propagated; downstream state corrupt | any |
| G02 | Panic via `.unwrap()` in critical path that leaves locked mutex | Fuzzer + Loom | Poisoned mutex; subsequent lock attempts fail | consensus, p2p |
| G03 | Re-entrancy via FFI callback that modifies shared state | Kani or manual model | Invariant broken after callback | bridge relayer |
| G04 | State corruption after early return in `match` arm | Fuzzer with state comparison | State differs after function vs expected | consensus state machine |
| G05 | Incorrect handling of async cancellation leaving partial writes | `tokio::select!` analysis + fuzz with cancellation | Partial update to storage | RPC, wallet |
| G06 | TOCTOU: read value, external call, use stale value | Kani harness with interleaving | Value changed between time-of-check and time-of-use | validator, bridge |
| G07 | Timing assumption: relying on block time for critical decisions | manual review (no tool) | Flagged with reproduction scenario | consensus |
| G08 | Integer truncation causing incorrect epoch/slot calculation | Kani | Epoch/slot computed incorrectly due to cast | consensus engine |
| G09 | HTTP/RPC middleware converts client-side error into fatal server abort (panic / `abort()` / `process::exit()`) | review all `hyper` / `axum` / `actix` / `tonic` error handlers in RPC server stack | `hyper::Error` (client disconnect, partial body, TCP RST) reachable to `panic!` / `abort()` / `process::exit()` instead of returning an error response | rpc-api-node (added v0.3.4 from Zebra CVE pattern G) |

## Group H — Supply Chain & FFI (cargo-audit + manual)

Owned by **Angle 8 — Supply Chain & FFI**.

| ID  | Vector | Detection Tool | Golden Signature | DLT Component |
|-----|--------|---------------|------------------|---------------|
| H01 | Vulnerable dependency with known CVE | `cargo audit` | `RUSTSEC-YYYY-NNNN` or `CVE-YYYY-NNNNN` matched; reachability via call graph | any |
| H02 | Unsound FFI: missing null pointer check | Clippy `missing_safety_doc` + manual | Potential segfault if null passed | bridge, wallet |
| H03 | Incorrect allocation contract (Rust allocates, C frees, or vice versa) | manual + valgrind | Double-free or allocator mismatch | storage, networking |
| H04 | Build script executing arbitrary commands | `cargo deny check-scripts` | Warning: malicious / fragile `build.rs` | any |
| H05 | Use of `unsafe` in third-party code without audit | `cargo geiger` | High unsafe-code-density in transitive deps | any |
| H06 | Typosquatted crate imported | `cargo supply-chain` or `cargo vet` | Mismatch between expected and actual crate source | any |
| H07 | Memory unsafety due to `repr(C)` struct with `bool` in incorrect position | Miri or valgrind | UB on C side due to padding | FFI wrappers |
| H08 | `#[no_mangle]` function collision | linker warning; `cargo check` may warn | Two symbols with same name | generic |
| H09 | FFI callback fails to enforce domain-specific validation previously performed on the foreign side (Zebra sighash / SIGHASH_SINGLE pattern) | diff Rust callback against pre-refactoring foreign-language version OR cross-reference protocol spec; for every `extern "C"` callback passed to FFI verification, enumerate consensus rules the foreign code historically enforced + verify Rust callback enforces them | Rust callback returns `Ok` / `Some` for input the foreign code's prior version would have rejected; consensus split between Rust impl and reference impl | supply-chain (added v0.3.4 from Zebra CVE pattern D) |

## Group I — Logic Bugs Specific to DLT Infrastructure (Model checking)

Owned by **Angle 7 — Logic & State Machine** (DLT-specific subset).

| ID  | Vector | Detection Tool | Golden Signature | DLT Component |
|-----|--------|---------------|------------------|---------------|
| I01 | Consensus round progression stall due to missing timeout reset | `stateright` or Kani model | Liveness property violation: round never advances | consensus engine |
| I02 | Duplicate transaction inclusion in block via non-unique identifier | property-based test | Two identical transactions in block; balance deducted twice | validator client |
| I03 | Incorrect reward distribution formula overflow | Kani | Reward sum exceeds expected | consensus |
| I04 | Peer score not updated on protocol violation, allowing eclipse | model checking of peer scoring | Attacker remains in peer table after misbehavior | p2p networking |
| I05 | Storage key collision between two data structures | Kani: two logical keys hash to same storage key | Corruption or overwrite | storage engine |
| I06 | Bridge relayer double-claim via replay attack | property test: same event cannot be processed twice | Event processed twice, funds lost | bridge relayer |
| I07 | Off-chain worker makes state change based on stale on-chain data | fuzzer with time manipulation | Contradictory state update | off-chain worker |
| I08 | Wallet incorrectly derives addresses for multi-sig | unit test against known vectors | Address mismatch | wallet |
| I09 | Smart-contract VM sandbox escape via improper host-function context check | fuzzing of wasm inputs | Host function called with invalid context | smart-contract VM |
| I10 | RPC endpoint exposes internal state enabling social engineering | manual review | Information leak | RPC node |
| I11 | Verification cache key excludes a security-critical field that is checked outside the cache (Zebra V5 authorization-data-root pattern) | find every `HashMap` / `BTreeMap` keyed by a type whose `Hash`/`Eq` impl excludes fields validated elsewhere in the call chain; verify cache lookups re-validate the excluded fields on hit | Cache returns "already verified" for an object whose cache-key matches but whose excluded-field has changed; second-impl reference rejects the same object | consensus engine, mempool (added v0.3.4 from Zebra CVE pattern B) |
| I12 | Consensus-critical metric undercounted / not accumulated during block validation (Zebra sigops-per-block pattern) | for every Bitcoin-inherited consensus metric (sigops, weight, fees) verify Zebra's block validator accumulates identically to the reference impl (zcashd / bitcoind); requires Stage-1 extraction of "Bitcoin-inherited rules" from spec §7.6 catch-all + zcashd source diff | Block with metric > limit accepted by Zebra, rejected by reference impl | consensus engine (added v0.3.4 from Zebra CVE pattern F) |

## Group J — ZK Circuit Soundness (Manual review + MockProver + E2E exploit)

Owned by **Angle 9 — ZK Circuit Soundness**. All Group J vectors are circuit-internal — they audit the constraint system that defines what a valid proof is, not the Rust code that invokes the verifier. The "detection tool" is systematic per-cell constraint enumeration (see agent methodology Phase 2); the "golden signature" is the mechanical result: a modified witness producing a valid proof (Tier-1-e2e) or MockProver reporting zero failing constraints with a challenger witness (Tier-1-mock).

| ID  | Vector | Detection Tool | Golden Signature | DLT Component |
|-----|--------|---------------|------------------|---------------|
| J01 | Under-constrained EC multiplication input: circuit accepts arbitrary point as input to scalar multiplication; gate verifies `s · P = Q` but `P` is unconstrained — prover computes `P = [s⁻¹]Q` for any desired `Q` | Manual: per-cell constraint enumeration (CHECK 1/2) + grep for `assign_advice` (not `copy_advice`) in loop first-iterations. Canonical: `halo2_gadgets/src/ecc/chip/mul/incomplete.rs:309-310` — `assign_advice(|| "x_p", ...)` / `assign_advice(|| "y_p", ...)` with no constraint binding to actual input `g_d`; `q_mul_2` enforces loop-internal consistency only | `MockProver` returns 0 failing constraints when point `P` is replaced with adversarially-chosen alternative point calculated as `[ivk⁻¹]pk_d` | ZK proof circuit |
| J02 | Unconstrained witness cell: advice column allocated but no gate reads it or gates that read it are conditional on a prover-controllable selector | Manual: enumerate every advice allocation, verify at least one gate reads it unconditionally OR every selector path constrains it | Modified witness with challenger value in the unconstrained cell → proof verifies successfully | ZK proof circuit |
| J03 | Missing range check: field element expected to represent a bounded integer (e.g., u64) is not range-constrained; prover can set it to any field element including values >> bound that wrap mod p | Manual: for every field element documented as bounded, verify a range-check gate or lookup argument constrains it | `MockProver` accepts witness with cell value = `p - 1` (max field element) where bound was e.g. `u64::MAX` | ZK proof circuit |
| J04 | Missing boolean check: cell documented as 0/1 flag is not constrained with `bool_check` gate; prover can set it to any field element | Manual: grep for "flag", "is_", "has_", "enabled" in circuit docs; verify `bool_check` gate or `(1 - x) * x = 0` constraint | `MockProver` accepts witness with flag = 42 | ZK proof circuit |
| J05 | Non-canonical encoding under-constraint: struct encoded as field element is not constrained to canonical representation; prover can use non-canonical encoding that represents same "value" but bypasses equality checks | Manual: for every `from_bytes` / `from_repr` in witness gen, verify the circuit enforces canonical encoding (e.g., coordinate < field modulus, Montgomery → affine conversion constrained) | Modified witness with non-canonical encoding → proof verifies; canonical verifier rejects but proof verifier accepts | ZK proof circuit |
| J06 | Custom gate constraint incompleteness: custom gate expression is missing a term; gate verifies `f(x, y, z) = 0` but the intended relationship is `f(x, y, z) = 0 AND g(x, y, z) = 0` — `g` is missing | Manual: for each custom gate, derive the intended relationship from comments/docs/spec; compare against the gate expression in `configure()` | `MockProver` accepts witness that satisfies `f = 0` but violates the intended `g = 0` | ZK proof circuit |
| J07 | Lookup argument selector gap: cell is constrained to a table via lookup argument, but the lookup is gated by a selector the prover controls; prover disables the lookup and sets the cell to an out-of-table value | Manual: for every lookup argument, check whether the enable flag is prover-controllable (not forced to 1 by a constraint) | `MockProver` accepts witness with lookup disabled + cell value outside table | ZK proof circuit |
| J08 | Copy-constraint / permutation gap: two cells SHOULD be equal (represent the same logical value) but no copy constraint links them; prover can set them to different values | Manual: for every logical value that appears in multiple regions/chips, verify a copy constraint or permutation link exists between all occurrences | `MockProver` accepts witness with divergent values in unlinked cells that should be equal | ZK proof circuit |
| J09 | Selector condition incompleteness: selector condition for a constraint is missing a case; e.g., constraint only fires when `sel_a = 1` but should also fire when `sel_b = 1` — the `sel_b` path has no constraint | Manual: enumerate all selector combinations; for each, verify the set of active constraints covers all required invariants | `MockProver` accepts witness on the unconstrained selector path with a value that violates the invariant | ZK proof circuit |
| J10 | Decorative gadget output: a comparator/validator gadget (`LessThan`/`IsZero`/range-check/on-curve) is instantiated and its output read, but never equated to its required value (`out === 1`) — the check does nothing | Manual: list every comparator/validator call; locate the line constraining its output; if absent → decorative. Picus/circomspect seed | Forged witness with the gadget's predicate FALSE verifies; or Picus reports the output signal underconstrained (circom-pairing `CoreVerifyPubkeyG1`, 10 unconstrained `BigLessThan.out`) | ZK proof circuit |
| J11 | Inverse/division/remainder degeneracy: `out <-- a/b` bound only by `out·b === a` is free at `b=0` (`0===0`); inverse hint never asserted `d·d_inv===1`; division-with-remainder missing `remainder < divisor` | Manual: enumerate every division/modular-reduction/inverse; substitute degenerate input (`b=0`) and check `out` still pinned. arkworks in-scope | Forged witness with `b=0` and arbitrary `out` verifies (arkworks `mul_by_inverse`, CVE-2021-38194 / RUSTSEC-2021-0075) | ZK proof circuit |
| J12 | Host-assertion masquerading as constraint: a security check enforced only by `assert!`/`debug_assert!`/`panic!`/`require!` in synthesize/witness-gen — emits NO circuit constraint (`debug_assert!` also stripped in release) | grep constraint-building code for host assertions guarding a security property; each is a gap (prover supplies own witness, never runs your Rust) | Release-build prover supplies an out-of-range/invalid witness and the proof verifies (Axiom `range_check` via `debug_assert`) | ZK proof circuit |
| J13 | Instance-binding gap: a computed result is never tied to a public-input/instance column (verifier checks a prover-controlled advice cell), or a declared public input is unreferenced and optimizer-stripped | Manual: every instance column must have an equality tie to a computed cell; every output cell must reach an instance; flag unused public inputs | Forged witness with a different output value verifies against the same public inputs (missing `replica_id`; unused-public-input-optimized-out) | ZK proof circuit |
| J14 | Output non-uniqueness / two-witness double-spend: constraints satisfied but ≥2 distinct valid witnesses exist for one logical statement (±root, malleable sig, truncating hash, sub-bit-width index) | Manual: per public output, inject ambiguity per operation; if a second witness validates → uniqueness gap | Two distinct witnesses both verify and yield distinct nullifiers/claims for one note (Aztec note-index <32-bit; teddav `sroot` ±r; StealthDrop) | ZK proof circuit |
| J15 | Point validity gap: prover/caller-supplied EC point used in pairing/MSM without on-curve AND prime-order-subgroup AND identity-consistency; or scalar on cofactor>1 base bound `< r`/`< 2^N` not `< l` (subgroup order) | Manual: per witnessed point, verify all three legs; per scalar on cofactor>1 base, verify `< l` bound | Forged in-curve-but-out-of-subgroup point (or identity) verifies (Symbiotic BLS subgroup, Sherlock #233; Aztec "0 bug"; Hexens Baby-Jubjub `k` vs `k+l`) | ZK proof circuit |
| J16 | EC exceptional-case under-constraint: affine add/double slope `λ <-- num/den` bound only by `λ·den === num`; at `den=0` (coincident/`P+(−P)`/order-2/identity) constraint degenerates to `0===0`, output point free | Manual: per affine add/double, enumerate exceptional inputs; check a constraint or switch-to-complete-add guards them | Forged witness at an exceptional input with an arbitrary output point verifies (circomlib `MontgomeryAdd`/`MontgomeryDouble`, Veridise Critical) | ZK proof circuit |

> **Verifier/setup-parameter vectors** (Frozen Heart transcript ordering, unverified prover evaluations, commitment fold-to-zero, PCS/FRI verifier checklist, VK/setup degeneracy) are owned by Angle 9 Phase 4.5 and documented in `hacking-agents/infra/zk-circuit-soundness-agent.md` + the research dossier §6. They are verifier-Rust soundness, not per-cell circuit vectors, so they live as CHECK 15–19 rather than Group J rows.

---

## How to extend

When you find a new infra vector in a real codebase, append a new entry with:

- The next ID in the appropriate group (or open a new group letter K/L/... with a description).
- A concise vector title.
- **Detection Tool**: name the deterministic backend if one applies; otherwise `manual review`.
- **Golden Signature**: the exact substring the tool outputs on confirmation. If manual, describe the evidence pattern.
- **DLT Component**: which `dlt-infra-types.md` component type this most affects.

Vectors are language-aware: most apply to systems-Rust on any chain (Solana validator, Polkadot node, Cosmos-rs, custom Rust DLT). Cross-chain vectors get tagged in the description.

## Coordination with `audit-modes.md`

In `infra` mode:
- Stage 0.5 runs `cargo audit` / `cargo deny` / `cargo geiger` / Clippy security lints (Group H + B10).
- Stage 2 dispatches 9 angles (`memory-safety` / `unsafe-trait` / `arithmetic` / `concurrency` / `crypto-misuse` / `resource-exhaustion` / `logic-state-machine` / `supply-chain-ffi` / `zk-circuit-soundness`), each owning its group(s) of vectors above.
- Stage 3 runs the appropriate backend per finding; **CONFIRMED** if golden signature matches.
- Stage 4 Pass A adds **TC — TOOL_CONFIRMED** as the 14th invalidator class.
- Stage 4 Pass D uses the Impact × Reachability matrix (`infra-severity-matrix.md`, Chunk 4).

In `smart-contract` mode: **this catalogue is NOT loaded**. The SC pipeline uses `rust-attack-vectors.md` (V1-V132) and the smart-contract Stage-2 angles.
