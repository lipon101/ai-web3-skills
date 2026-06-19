# Zebra Audit Pattern Map (Argus infra mode)

> **Save this file to `<zebra-clone>/assets/docs/zebra-patterns.md`** before invoking `/argus` against the Zebra repo.
>
> Argus reads `assets/docs/*` at Stage 1 as project-context input. The hypotheses below are treated as priority targets for Stage 2 angles, not as confirmed findings. Every claim still goes through Stages 2-8 with deterministic-backend verification at Stage 3.

**Repository**: [`ZcashFoundation/zebra`](https://github.com/ZcashFoundation/zebra) · latest `main`
**Target type**: DLT infrastructure — Zcash full node
**Argus mode**: `infra` (v0.3.3+; live-E2E mandatory for CONFIRMED, REFINE auto-loop active)
**Vector catalogue**: `references/attack-vectors/dlt-infra-attack-vectors.md` (Groups A–I)

---

## 1. Codebase overview

Zebra is a full Zcash node in Rust with C FFI for Equihash. NU5 (Sapling + Orchard) support. Multi-crate workspace; each crate maps to a `dlt-infra-types.md` component type:

| Crate | Role | DLT-infra component type |
|-------|------|--------------------------|
| `zebrad` | Binary entry, config, shutdown | validator-client |
| `zebra-network` | Peer discovery, message serialisation, protocol state machines | p2p-networking |
| `zebra-consensus` | Block/tx verification, chain-state tracking | consensus-engine |
| `zebra-state` | Persistent chain state (RocksDB) | storage-engine |
| `zebra-chain` | Core data types, block/tx structures, serialisation | (shared data model — feeds every component) |
| `zebra-script` | Script verification for transparent inputs | smart-contract-vm (script interpreter) |
| `zebra-rpc` | JSON-RPC endpoint | rpc-api-node |
| `zebra-node-services` | Mempool, syncer, long-running services | off-chain-worker |
| `tower-*` crates | Service middleware | generic-rust-dlt |

**Key deps**: `orchard`, `halo2` / `pasta_curves`, `zcash_primitives`, `equihash` (C binding), `rocksdb`, `tokio`, `tower`.

**Primary adversaries**:
1. Remote unauthenticated attacker (p2p network messages)
2. Malicious peer (eclipse, transaction censorship, gossip amplification)
3. Memory-corruption attacker via crafted blocks / transactions
4. Attacker with partial hash power (selfish mining, fork attacks)

---

## 2. Attack hypotheses (V-IDs corrected against `dlt-infra-attack-vectors.md`)

### H-1 — Equihash FFI memory corruption

- **Location**: `equihash` crate (Rust→C FFI), called from `zebra-consensus` during block verification.
- **Primary V-IDs**: **A-04** (invalid pointer arithmetic out of allocation), **A-07** (use-after-free via dangling reference from temporary)
- **Secondary V-IDs**: **H-02** (FFI missing null pointer check), **H-03** (allocation-contract mismatch: Rust allocates, C frees)
- **Bug class**: variable-length Equihash solution; C-side boundary mishandling read/written through Rust binding.
- **Stage 2 angles**: memory-safety (primary) + supply-chain-ffi (secondary)
- **Stage 3 verification**:
  - Miri on the Rust binding only (Miri can't run on C). For C-side: cargo-fuzz the wrapper with the Rust↔C boundary as the surface.
  - **Live-E2E (v0.3.3 requirement)**: build a harness that imports `equihash`, feeds crafted solution bytes through the actual `verify_equihash_solution` entry point used by `zebra-consensus`, observes panic / OOB / corruption.
- **Expected severity**: Critical if RCE-class reachable from remote peer

### H-2 — Unsound `Send`/`Sync` on shared mempool / chain tip

- **Location**: `zebra-node-services::mempool`, `zebra-consensus::chain_tip`
- **Primary V-ID**: **B-01** (`Send` impl on type containing `UnsafeCell` without synchronisation)
- **Secondary V-IDs**: **B-02** (`Sync` impl with interior mutability not behind lock), **D-05** (`UnsafeCell` unprotected)
- **Bug class**: mempool and latest chain tip shared across multiple `tokio` tasks; missing lock or wrong atomic ordering → data corruption or silent chain divergence.
- **Stage 2 angles**: unsafe-trait (primary) + concurrency (secondary)
- **Stage 3 verification**: Rudra (`cargo rudra`) for `unsafe_send` lint; Loom for schedule-dependent race; Miri with `-Zmiri-detect-data-races` on stress harness.
- **Live-E2E**: Loom model importing the shared-state types; if Loom finds a failing schedule, that's the artifact.
- **Expected severity**: High → Critical depending on data-corruption scope

### H-3 — Block subsidy / difficulty arithmetic overflow

- **Location**: `zebra-chain` subsidy calculations, `zebra-consensus` difficulty adjustment
- **Primary V-ID**: **C-05** (wrapping multiplication for fee calculation — generalize to subsidy/reward)
- **Secondary V-IDs**: **C-02** (`Vec::with_capacity(user_len * size)` overflow if difficulty buffers are sized from chain history), **C-08** (timestamp arithmetic wrap in difficulty adjustment windows)
- **Bug class**: monetary arithmetic that wraps in release mode → mints infinite ZEC or crashes node.
- **Stage 2 angle**: arithmetic
- **Stage 3 verification**: Kani harness with `kani::any()` block-height + difficulty-target; assert `compute_subsidy(h).checked_add(other).is_some()` and `apply_difficulty_adjustment(...).is_ok()`. Counterexample = CONFIRMED.
- **Live-E2E**: integration test feeding extreme block heights / difficulty targets through the actual `zebra-consensus` verify path.
- **Expected severity**: Critical if it allows infinite-mint; High if crashes the node

### H-4 — Weak randomness in key generation

- **Location**: `orchard` / `zcash_primitives` usage in `zebra-chain`
- **Primary V-ID**: **E-01** (`rand::random` for key material instead of `OsRng`)
- **Secondary V-ID**: **E-05** (nonce reuse in Ed25519 / spend-authorisation signing)
- **Bug class**: predictable RNG for key derivation → key recovery.
- **Stage 2 angle**: crypto-misuse
- **Stage 3 verification**: grep for `rand::random` / `thread_rng` in key-derivation paths; Clippy security lints; if found, unit test demonstrating predictable output.
- **Live-E2E**: instantiate the real key-derivation function with controlled seed, observe deterministic key (which is correct behavior if `OsRng` *not* used, indicating the bug).
- **Expected severity**: Critical (key recovery is fund-theft)

### H-5 — DoS via unbounded allocation in network message deserialisation

- **Location**: `zebra-network` message types (`GetBlocks`, `Transactions`, etc.); `zebra-chain` serialisation
- **Primary V-ID**: **F-01** (unbounded `Vec::push` from network input)
- **Secondary V-IDs**: **F-05** (large allocation from attacker-controlled capacity), **F-06** (string allocation amplification)
- **Bug class**: large size-prefix in p2p message → OOM.
- **Stage 2 angle**: resource-exhaustion
- **Stage 3 verification**: cargo-fuzz harness on each `Deserialize` impl for network messages; run under `cgroups` memory cap; observe OOM.
- **Live-E2E**: spawn two `zebra-network` peer instances, send crafted size-prefix message from peer A, observe peer B's RSS growth / OOM.
- **Expected severity**: High (remote DoS without authentication)

### H-6 — Block-header POW verification bypass

- **Location**: `zebra-consensus::block::verify` (or equivalent in current codebase)
- **Primary V-ID**: **catalogue gap** (proposed **V133**: "consensus-rule check skipped in alternative verification path"). Nearest current matches: **G-04** (state corruption after early return in match arm), **G-01** (silent `Result` ignore — e.g., `let _ = check_pow(...)`)
- **Bug class**: POW check skipped in one code path (e.g., header relay vs full block import) → fork the chain with minimal work.
- **Stage 2 angles**: logic-state-machine (primary) + invariant
- **Stage 3 verification**:
  - **`weaponization_check` is the key gate here**: grep for every `check_pow` call site; verify every block-verification entry calls it. Mismatch = the bug.
  - Stateright model: model the verification state machine; property "every block accepted must have passed POW"; counterexample if violated.
- **Live-E2E**: craft a block with invalid POW, feed through every block-import path (`zebra-consensus`, `zebra-network` block-relay), observe whether any path accepts.
- **Note**: this is a **V133 catalogue-gap candidate**. If Argus confirms on Zebra, propose to add as new vector entry.
- **Expected severity**: Critical (chain split / inflation)

### H-7 — RocksDB state corruption via unsafe iterator use

- **Location**: `zebra-state` (RocksDB column-family iteration)
- **Primary V-IDs**: **A-07** (use-after-free) or **A-05** (uninitialised memory read) depending on how `unsafe` interacts with `rocksdb` raw pointer APIs
- **Secondary V-IDs**: **H-03** (Rust↔C allocation contract), **B-04** (custom `Drop` leak / double-free)
- **Bug class**: `rocksdb` crate exposes raw pointers for iterators; mishandling → UB.
- **Stage 2 angles**: memory-safety + supply-chain-ffi
- **Stage 3 verification**: Miri (if it can run on the `rocksdb` wrapper paths; some FFI calls Miri won't execute) — fall back to AddressSanitizer or Valgrind on real binary.
- **Live-E2E**: build a stress harness that opens a `zebra-state` DB, iterates while concurrent writes happen, observe crash / corruption.
- **Expected severity**: High → Critical depending on observability

### H-8 — Missing shielded-proof verification in block transactions

- **Location**: `zebra-consensus` transaction verification (Orchard / Sapling proofs)
- **Primary V-ID**: **catalogue gap** (proposed **V134**: "cryptographic-proof verification skipped in alternative validation path"). Nearest current matches: **G-01** (silent Result ignore), **G-04** (early-return state corruption)
- **Secondary V-ID**: **E-07** (improper error handling in signature verification — accepts `Ok` for invalid sig)
- **Bug class**: malicious peer sends block with fake shielded tx; if some validation code path skips proof verification on error, state becomes inconsistent. Distinct from H-6 (POW) — this is about shielded-tx proof, not block header.
- **Stage 2 angles**: logic-state-machine + crypto-misuse
- **Stage 3 verification**:
  - `weaponization_check` across every shielded-tx verification entry; all must call `verify_orchard_proof` / `verify_sapling_proof`.
  - Unit test: craft a tx with deliberately invalid Orchard proof, feed through every validation path, expect Err on each.
- **Live-E2E**: integration test importing a block containing one valid and one invalid-proof tx; observe whether the block is rejected.
- **Note**: **V134 catalogue-gap candidate**. If confirmed, propose new vector.
- **Expected severity**: Critical (privacy break / unbacked-fund mint)

### H-9 — Unsafe deserialisation in `zcash_encoding` / custom traits

- **Location**: `zebra-chain` serialisation macros + custom `zcash_encoding` `ZcashDeserialize` impls
- **Primary V-IDs**: **A-03** (Stacked Borrows violation if raw pointers used), **C-01** (unchecked index from deserialised length field)
- **Secondary V-IDs**: **A-04** (out-of-allocation pointer arithmetic), **F-03** (deep recursion from recursive data structure)
- **Bug class**: custom deserialisation often uses `unsafe` for performance; length field could cause OOB reads or attacker-controlled recursion depth.
- **Stage 2 angle**: memory-safety + resource-exhaustion (for recursion)
- **Stage 3 verification**: Miri on deserialise functions (run via unit test in a Miri-friendly subset); cargo-fuzz the `ZcashDeserialize` impls.
- **Live-E2E**: cargo-fuzz target on each `Deserialize` impl with 5-min budget; crash artifact = CONFIRMED.
- **Expected severity**: High → Critical depending on whether OOB read leaks memory or enables RCE

### H-10 — Vulnerable dependency CVE

- **Location**: `Cargo.lock`, transitive deps including `orchard`, `halo2`, `zcash_primitives`, `rocksdb`, `librocksdb-sys`, `tokio`, `hyper`, `rustls-*`
- **Primary V-ID**: **H-01** (vulnerable dependency with known CVE)
- **Bug class**: a CVE in a cryptographic dependency (e.g., a `halo2` soundness bug) could enable proof forgery; in a networking dep (`tokio`, `rustls`) could enable DoS / panic / leak.
- **Stage 2 angle**: supply-chain-ffi
- **Stage 3 verification** (v0.3.2+ Group H 3-step gate):
  - Step 1: `cargo audit --json`, match cited RUSTSEC ID.
  - Step 2: `cargo tree -i <crate>` shows non-dev reachability.
  - Step 3: **Advisory-body caveat check** — fetch the advisory, parse for "Applications that do not X are not affected" caveats, grep Zebra for the cited trigger API. **This is the gate that catches F-07-class over-claims.**
  - Step 4: **Tier-1-live-e2e** — build a project depending on the in-scope Zebra crate, exercise the cited API in the way Zebra uses it, observe whether the bug fires.
- **Expected severity**: variable by CVE; likely Medium to Critical

---

## 3. Cross-cutting invariants (Stage 1 → `invariants.md` extraction primer)

1. **POW validation before state changes** — every block-import path calls `check_pow` before committing to chain state.
2. **Shielded proof verification on every input** — Orchard `Action`s and Sapling `Spend`s have their zk-SNARK / Groth16 proofs verified before fund movement.
3. **No unbounded allocation from network input** — every `Deserialize` impl with a length field validates against a documented max.
4. **Atomic chain-tip + mempool updates** — peer message handlers acquire correct locks / use correct atomic ordering.
5. **`OsRng` for all security-critical randomness** — no `thread_rng` / `rand::random` in key-gen or signing nonces.
6. **`unsafe` blocks have safety documentation** and `# Safety:` invariants preserved by callers.
7. **FFI null-pointer checks + ownership clarity** — `extern "C"` functions explicitly document Rust↔C ownership.
8. **Transaction value balance** — `sum(transparent_inputs) + sum(shielded_input_values) == sum(outputs) + fee` per Zcash consensus.
9. **Consensus rules enforced identically across all paths** — header relay, block import, mempool, re-validation must all apply the same checks.

---

## 4. Stage 2 angle priority (infra mode, 8 angles)

| Angle | Priority | Rationale |
|-------|---------:|-----------|
| **crypto-misuse** | **Highest** | Shielded transactions + zk-SNARK proofs + key generation. Subtle misuse = catastrophic privacy / fund loss. |
| **memory-safety** | **Highest** | Equihash FFI, custom serialisation, RocksDB raw pointers. Largest RCE surface. |
| **logic-state-machine** | **High** | Consensus rules, chain-tip update, block verification. Bypass = chain split / inflation. |
| **resource-exhaustion** | **High** | p2p message parsing, mempool, block-relay. Easy remote DoS surface. |
| **supply-chain-ffi** | **Medium-High** | Many crypto deps + Equihash C FFI + `rocksdb` C FFI. Group H + B10 + H02/H03 active. |
| **concurrency** | **Medium** | Shared state across async tasks (chain tip, mempool). Race conditions could corrupt state. |
| **arithmetic** | **Medium** | Subsidy + difficulty adjustment. Bounded surface but high-impact if overflow. |
| **unsafe-trait** | **Lower** | Mostly stdlib usage; few custom unsafe traits. |

---

## 5. Expected Stage-3 PoC tiers

Per v0.3.3, every CONFIRMED requires Tier-1-live-e2e per `e2e-test-discipline.md`. Component-type → E2E pattern mapping for Zebra:

| Hypothesis | Component type | E2E pattern | Expected tier |
|------------|----------------|-------------|---------------|
| H-1 Equihash FFI | crypto-library | direct API + cargo-fuzz | Tier-1-fuzz |
| H-2 Send/Sync | concurrency | Loom model | Tier-1-runtime |
| H-3 Arithmetic overflow | consensus-engine | Kani proof + integration test | Tier-1-formal + Tier-1-live-e2e |
| H-4 Weak randomness | crypto-library | direct API call with seeded RNG | Tier-3-unit |
| H-5 DoS allocation | p2p-networking | two-peer swarm test | Tier-1-live-e2e |
| H-6 POW bypass | consensus-engine | stateright model + integration test | Tier-1-live-e2e |
| H-7 RocksDB UB | storage-engine | real DB + concurrent stress | Tier-1-live-e2e (or Tier-3 if Miri can't cross FFI) |
| H-8 Missing proof check | consensus-engine | crafted invalid proof + integration test | Tier-1-live-e2e |
| H-9 Deserialisation UB | crypto-library | cargo-fuzz on `Deserialize` impl | Tier-1-fuzz |
| H-10 Dep CVE | supply-chain | Group H 3-step + Tier-1-live-e2e | Tier-1-live-e2e |

---

## 6. Pre-Pass 1 scope-carveout expectations

Zebra is a **full node**. Typical bounty-scope exclusions to expect:

- **51% / majority hash-power attacks** — usually OUT of scope.
- **Privacy bugs requiring traffic analysis at ISP level** — typically OUT.
- **Bugs requiring `--regtest` or development-mode flags** — OUT.
- **In scope (typically)**: remote RCE, memory corruption from network input, theft of shielded funds, chain-split with minimal hash power, remote DoS with low resource cost.

H-1 / H-5 / H-6 / H-8 / H-10 are clearly in scope. H-2 / H-3 / H-4 / H-7 / H-9 likely in scope subject to reachability.

**Pre-Pass 1 should NOT kill any of these on a "validator-required" centralisation carve-out — Zcash doesn't have a validator-trust model.**

---

## 7. Severity mapping

Zcash Foundation runs a bug bounty (verify exact program + payouts at the **live bounty page** — Argus Stage 5/6 will WebFetch this; do not hardcode dollar amounts from this file).

Approximate mapping:

| Stage 4 final severity | Impact | Zcash Foundation tier (verify live) |
|------------------------|--------|--------------------------------------|
| CRITICAL | Remote RCE, shielded-fund theft, chain split with trivial work | Top tier |
| HIGH | Node crash with memory corruption, privacy leak | High tier |
| MEDIUM | DoS under specific conditions, integrity issue | Medium tier |
| LOW | Error handling without direct impact | Low / informational |

The Stage 4 `infra-impact-analysis.md` matrix produces the deterministic severity. Manual reviewer maps to the bounty's published tiers post-pipeline.

---

## 8. Practical notes

### Cost preview

Zebra is large (~100k+ LoC across ~15 crates). Expect Stage 0 cost preview to be substantial:
- Stage 1 mapping: ~10-15 min wall-clock (large workspace)
- Stage 2 (8 angles in parallel): ~20-30 min
- Stage 3 (Tier-1-live-e2e per finding): ~5-15 min per finding × ~10-20 findings = 1-5 hours
- Total: likely 3-6 hours, $50-$150 API cost range

Use Stage 0's cap option if you want to limit scope. Pinning to a subset (e.g., `--scope zebra-network` to audit only the p2p crate) is reasonable for the first pass.

### Equihash FFI special handling

Miri cannot execute C code. For H-1, Stage 3 will:
- Run Miri on the Rust binding's pre/post-FFI code (catches Rust-side bugs).
- Run cargo-fuzz on the wrapper with crafted Equihash solutions (catches behavior boundary issues without needing to instrument C).
- Real C-side memory bugs require AddressSanitizer or fuzzing of the C library independently — out of Argus's deterministic-backend scope. Document as a known gap; consider running `libfuzzer` against the C library separately.

### RocksDB FFI special handling

Same constraint as Equihash. Miri won't run RocksDB native calls. Fallback: AddressSanitizer or Valgrind on real binary. Argus will likely mark H-7 INCONCLUSIVE at Stage 3 if Miri can't cross the FFI; the REFINE auto-loop (R3 pattern) will attempt to build a stress harness; if Miri rejects, route to manual queue.

### Catalogue gaps to file

H-6 (POW bypass) and H-8 (missing proof check) don't have clean V-ID matches. If Argus confirms either, propose new vectors:
- **V133** — "Consensus-rule check skipped in alternative verification path"
- **V134** — "Cryptographic-proof verification skipped in alternative validation path"

The pattern is the same for both: a consensus-critical check exists in one code path but not all paths. The `weaponization_check` field across all verification entry points is the structural detection mechanism.

---

## 9. AI-provenance

This file is AI-drafted hypotheses, not findings. Argus runs full Stages 2-8 with deterministic-backend verification (v0.3.3) on every hypothesis. Submission to the Zcash Foundation bounty requires:
1. Manual re-read of cited code at the cited lines.
2. Independent re-derivation of the exploit path.
3. Re-run the Tier-1-live-e2e artifact.
4. Re-verify scope against the live Zcash Foundation bounty page.
5. Rewrite the writeup in your own words.

---

## 10. How to use

```bash
# Clone Zebra
cd ~/Documents/Dev
git clone https://github.com/ZcashFoundation/zebra.git
cd zebra

# Drop the pattern map
mkdir -p assets/docs
cp ~/Documents/Dev/argus/examples/zebra-patterns.md assets/docs/zebra-patterns.md

# Run Argus in Claude Code
/argus
```

Argus will:
1. Detect `generic-rust` project shape (Zebra is not Anchor / CosmWasm / Substrate-pallet)
2. Check Zcash Foundation bounty page category; the rule-1 mode recommendation should land on **`infra`** (DLT/Blockchain category, not Smart Contract)
3. Read `assets/docs/zebra-patterns.md` at Stage 1 as project context
4. Multi-crate workspace: `enumerate.sh` will identify all crates; Stage 1 produces a `cpi-graph.md` for cross-crate flows
5. Stage 2 dispatches 8 infra angles in parallel with this pattern map as priority hypotheses
6. Stage 3 deterministic backends + Tier-1-live-e2e per finding
7. Stage 4 Impact × Reachability matrix → final severity
8. Stage 5 disclosure path (likely `vendor-coordinated` for Critical, `vendor-report` for High/Medium)
9. Stage 6 CVE triage if dep-class
10. Output at `<zebra>/argus/<UTC-timestamp>/`

Run from the workspace root; Argus handles the multi-crate layout automatically.
