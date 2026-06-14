# Zebra Attack Paths — Volume II (Undisclosed / Emerging Hypotheses)

> **Save this file to `<zebra-clone>/assets/docs/zebra-attack-paths-v2.md`** alongside the existing `zebra-patterns.md` and `zebra-cve-patterns.md` before invoking `/argus`.
>
> **Status**: AI-generated hypotheses, not confirmed findings.
> **Prerequisite**: read alongside `zebra-patterns.md` (architecture) and `zebra-cve-patterns.md` (CVE root-cause patterns).
> **Purpose**: guide Argus Stage 2 angles toward attack surfaces that match the structural shape of *already-exploited* Zebra bug classes but whose CVEs have not yet appeared.
> **Source-attribution caveat**: specific GHSA / CVE / Issue numbers referenced below were not independently verified during integration. The *patterns* are catalogue-aligned regardless; treat numeric references as claimed-but-unverified pointers, not load-bearing citations.

---

## 0. Methodology

Every hypothesis below is derived from one of four strategies:

1. **Pattern transposition**: take a known CVE shape (e.g. "deserialize-then-validate ordering") and look for it in a *different* code path that the published advisory didn't cover.
2. **Cross-crate composition**: take two independently-low-severity weaknesses that the block-discovery-halt CVE proved can compose into Critical, and look for similar interacting pairs.
3. **FFI callback boundary audit**: the sighash CVEs all involve Rust→C++→Rust callback chains where consensus rules were lost. Every other FFI callback is a candidate.
4. **Monetary arithmetic**: subsidy, fee, and value-pool arithmetic is consensus-critical; integer and rounding errors map to the I-03 / C-05 / C-03 vector classes.

---

## 1. New Hypotheses

### H-11 — `getblocktemplate` Coinbase Value Mismatch via Fee Rounding

- **Location**: `zebra-rpc/src/methods/types/get_block_template/` (coinbase construction), `zebra-chain/src/transaction/` (fee calculation)
- **Suspected Vector(s)**: **C-05** (Wrapping multiplication), **I-03** (Incorrect reward distribution), **C-03** (Arithmetic underflow)
- **Pattern class**: Monetary arithmetic — same class as the `getblocksubsidy` RPC divergence (Founders' Reward subtraction bug, March 2026 engineering update — unverified reference)
- **Why**: The `getblocktemplate` RPC builds a coinbase transaction that must balance `subsidy + fees = sum(outputs)`. If fee calculation uses a different rounding mode than zcashd (e.g., truncation vs. ceiling in ZIP-317 marginal fee per logical action), the coinbase value can differ by 1 zatoshi. An external miner who submits a block based on Zebra's template would mine a block that zcashd rejects for "coinbase value mismatch."
- **Tool**: Kani (arithmetic equality proof against zcashd's `CAmount` logic) or differential fuzzing: compare `getblocktemplate` output from Zebra and zcashd for the same mempool state
- **Angle**: arithmetic, logic-state-machine

### H-12 — `getrawtransaction` Verbose Panic on Orphan-Block Transactions

- **Location**: `zebra-rpc/src/methods/get_raw_transaction.rs` (verbosity ≥ 1 path)
- **Suspected Vector(s)**: **G-02** (Panic through `.unwrap()` in critical path), **G-05** (Incorrect handling of `Async` cancellation)
- **Pattern class**: RPC-triggered panic — analogous to CVE-2026-41585 (HTTP disconnect panic) and CVE-2026-34202 (V5 TxID panic) — both unverified references
- **Why**: Issue #8744 (unverified) documents that `getrawtransaction` for transactions in orphaned (non-main-chain) blocks returns `Err("transaction not found")` rather than zcashd-compatible data. The resolution path involves reading block data from the non-finalized state. If the code path calls `.unwrap()` / `.expect()` on a state read that can fail during a chain reorganization (or when the orphan block has been pruned), an authenticated RPC client can trigger a panic.
- **Tool**: grep for `.unwrap()` / `.expect()` in `zebra-rpc/src/methods/get_raw_transaction.rs` and adjacent state-read paths; test by calling `getrawtransaction <txid> 1` for a txid that exists only in a just-orphaned block
- **Angle**: logic-state-machine, resource-exhaustion

### H-13 — `getblock` Verbosity-2 Memory Amplification (Full Block + All Tx Data)

- **Location**: `zebra-rpc/src/methods/get_block.rs` verbosity 2 path, `zebra-state` block retrieval
- **Suspected Vector(s)**: **F-08** (Allocate-then-check with ceiling exceeding true limit), **F-01** (Unbounded `Vec::push` from network input — indirect)
- **Pattern class**: Allocation amplification — same class as GHSA-438q-jx8f-cccv (unverified)
- **Why**: `getblock` with `verbosity = 2` returns full transaction data for every transaction in the block. A maximally-large block (2 MiB) can contain thousands of transactions; the serialized JSON response is many times larger than the raw block. If the RPC server holds the entire response in memory before sending (and `max_response_body_size` defaults to 50 MiB), a single authenticated `getblock <hash> 2` call can allocate tens of MiB. Multiple concurrent calls from an authenticated client can exhaust memory. zcashd limits verbosity 2 to blocks with at most 100 transactions (verify); Zebra may not enforce a similar limit.
- **Tool**: Memory-profiling test: call `getblock <large-block-hash> 2` and measure RSS before/after; check whether a transaction-count limit exists in the Zebra code path
- **Angle**: resource-exhaustion

### H-14 — Mempool Dependency Graph Poisoning via Low-Fee Parent + High-Fee Child Eviction Order

- **Location**: `zebra-node-services/src/mempool/` (eviction logic, `transaction_dependencies.rs`)
- **Suspected Vector(s)**: **I-02** (Duplicate transaction inclusion — analogue), composite-DoS class (v0.4.0 cross-crate methodology gap)
- **Pattern class**: Mempool eviction fairness — analogous to the zcashd "mempool size limit and random drop" DoS mitigation that introduced its own edge cases
- **Why**: ZIP-401 mandates random eviction when the mempool exceeds `tx_cost_limit`. If Zebra evicts a parent transaction (low fee) but keeps a high-fee child that spends its outputs, the child becomes unminable. A miner using `getblocktemplate` receives a block template containing unminable transactions, wasting hash power. If Zebra's dependency tracking (`TransactionDependencies`) doesn't prevent eviction of parents with in-mempool children, an attacker can fill the mempool with dependency-poisoned transaction chains.
- **Tool**: Unit test: insert parent A (low fee) + child B (high fee, spends A's output), trigger eviction, verify B is also evicted or excluded from `getblocktemplate`
- **Angle**: logic-state-machine, resource-exhaustion

### H-15 — `getpeerinfo` RPC Leak of Network Topology Through Unintended Fields

- **Location**: `zebra-rpc/src/methods/get_peer_info.rs`
- **Suspected Vector(s)**: **I-10** (RPC endpoint exposes internal state), **G-09** (HTTP/RPC middleware error handling — adjacent)
- **Pattern class**: Information disclosure through observable timing or field content — analogous to the zcashd-inherited pattern where `getpeerinfo` exposed outbound rather than inbound connections
- **Why**: Zebra's `getpeerinfo` RPC was corrected in 2025 (unverified specific date) to show current inbound *and* outbound connections (previously it only showed outbound). If the response includes peer IP addresses, connection durations, or last-seen timestamps, an authenticated RPC client (or a remote attacker if auth is disabled) can enumerate the node's peer set. Combined with timing information, this enables targeted eclipse attacks: the attacker identifies peers that are about to be rotated out, pre-positions malicious peers at those addresses, and waits for the node to connect to them.
- **Tool**: Manual review of `getpeerinfo` response fields; check whether IP addresses are redacted or masked in the default response
- **Angle**: crypto-misuse (privacy), logic-state-machine

### H-16 — Chain Reorganization Depth Not Bounded During `getblocktemplate` Template Construction

- **Location**: `zebra-rpc/src/methods/types/get_block_template/`, `zebra-state` non-finalized chain
- **Suspected Vector(s)**: **G-06** (TOCTOU — chain tip changes between reads), **I-11** (Verification cache key excludes security-critical field — adjacent)
- **Pattern class**: TOCTOU on chain state — analogous to the verification-cache key incompleteness (CVE-2026-34377, unverified) where stale state was used for validation
- **Why**: `getblocktemplate` reads the current chain tip, then iterates the mempool to select transactions, then constructs a coinbase. If a new block arrives between the tip read and the template construction, the template may be built on a stale tip. If the template includes transactions that were already mined in the new block, the miner produces an invalid block. While this is inherent to the design of `getblocktemplate`, the *detection* of this race and the freshness guarantee differ between zcashd and Zebra. If Zebra provides weaker freshness guarantees, miners lose more hash power on invalid templates.
- **Tool**: Integration test: submit a new block via P2P during `getblocktemplate` execution; verify template is rejected or regenerated
- **Angle**: concurrency, logic-state-machine

### H-17 — `sendrawtransaction` Silent Acceptance of Non-Standard Transactions (Mempool Policy Divergence)

- **Location**: `zebra-rpc/src/methods/send_raw_transaction.rs`, mempool acceptance path
- **Suspected Vector(s)**: **I-12** (Consensus-critical metric undercounted — analogue), **I-02** (Duplicate transaction inclusion — indirect)
- **Pattern class**: Mempool policy divergence that doesn't directly cause a consensus split but enables transaction-relay attacks — analogous to the sighash hash-type handling CVEs where a "standardness" divergence became consensus-critical after refactoring
- **Why**: zcashd enforces a set of "standardness" rules (not consensus-critical, but required for relay) that Zebra may not enforce identically. For example: `OP_RETURN` size limits, `scriptSig` push-only requirements, or dust output thresholds. A transaction that Zebra accepts into its mempool but zcashd rejects cannot propagate through the network. If Zebra is used as a block template producer, non-standard transactions can be mined, creating blocks that zcashd nodes reject (not for consensus reasons, but because the block contains a non-standard transaction that honest miners wouldn't include).
- **Tool**: Differential fuzzing: generate random transactions, submit to both Zebra and zcashd via `sendrawtransaction`, compare acceptance/rejection
- **Angle**: logic-state-machine, supply-chain-ffi

### H-18 — `getblocksubsidy` Negative Height Handling Panic

- **Location**: `zebra-rpc/src/methods/get_block_subsidy.rs`
- **Suspected Vector(s)**: **G-02** (Panic through `.unwrap()`), **C-03** (Arithmetic underflow in subtraction)
- **Pattern class**: RPC parameter validation — same shape as CVE-2026-34202 (unverified) where crafted input passes initial validation but panics in later processing
- **Why**: Issue #9025 (unverified) notes that Zebra doesn't support negative heights in RPC calls (unlike zcashd, where `-1` means "latest block"). If a caller passes `-1` (or a height greater than the current chain tip) to `getblocksubsidy`, the underlying height arithmetic (`Height` subtraction) may underflow or panic. The `Height` type in `zebra-chain` uses checked arithmetic in debug builds but can wrap in release.
- **Tool**: Call `getblocksubsidy -1` against a Zebra node; observe panic or incorrect result
- **Angle**: arithmetic

### H-19 — Equihash Solution Validation Bypass via Non-Canonical CompactSize Encoding

- **Location**: `zebra-chain/src/work/equihash.rs` (solution parsing), `zebra-consensus/src/block/verify.rs` (POW check)
- **Suspected Vector(s)**: **catalogue gap V133** (consensus-rule check skipped in alternative verification path — proposed in v0.3.4 deferred-process-improvements), **A-10** (Alignment violation — indirect)
- **Pattern class**: Consensus validation bypass — analogous to the sighash canonical hash-type CVEs and the sigop-undercounting CVE
- **Why**: The Zcash protocol inherited Bitcoin's requirement that CompactSize (variable-length integer) encodings be canonical (shortest possible representation). If Zebra's `Solution::zcash_deserialize` accepts non-canonical CompactSize encodings for the Equihash solution length, a miner can produce a block whose header passes Zebra's validation but fails zcashd's validation. This is the same class as GHSA-438q-jx8f-cccv (unverified) but in a *different* validation path — here, the concern is not allocation amplification but consensus divergence.
- **Tool**: Craft a block header with a non-canonical CompactSize encoding of the Equihash solution length; submit to both Zebra and zcashd
- **Angle**: logic-state-machine, supply-chain-ffi

### H-20 — Peer `VersionMessage` Timestamp Field Used for Unauthenticated Clock Skew Amplification

- **Location**: `zebra-network/src/protocol/external/types.rs` (VersionMessage), peer handshake
- **Suspected Vector(s)**: **F-08** composite-DoS class (cross-crate methodology gap), **V97-style** global-timestamp partial-update (smart-contract V97 analogue applied to infra)
- **Pattern class**: Unauthenticated input influencing internal time — analogous to NTP-amplification style attacks; relevant because several consensus checks depend on `Clock::get()` which may be influenced by peer timestamps if Zebra adjusts its clock based on the network median
- **Why**: During the version handshake, a remote peer can supply an arbitrary `timestamp` field in its `VersionMessage`. If Zebra uses peer timestamps for any security-relevant decision (e.g., block timestamp validation window, mempool expiry, or clock drift detection), an attacker can skew the node's perception of network time by connecting from multiple peers with coordinated false timestamps. While Zebra likely uses the system clock for consensus-critical checks, the `nTime` field propagation through the address book may influence other nodes' time perception.
- **Tool**: Connect multiple peers with timestamps offset by ± 2 hours; observe whether Zebra's `Clock` or peer scoring is affected
- **Angle**: concurrency, logic-state-machine

---

## 2. Cross-Crate Composition Hypotheses

The block-discovery-halt CVE proved that three independently-low-severity weaknesses compose into Critical. Below are analogous compositions. **Note**: cross-crate finding composition is a v0.4.0 methodology gap (acknowledged in v0.3.4 CHANGELOG). v0.3.5 Argus doesn't auto-detect these compositions — the user must surface them manually post-Stage-2.

### Comp-1 — Mempool-State-Starvation Composition

- **Components**: H-14 (dependency poisoning) + H-17 (non-standard transaction acceptance) + F-01 (quadratic `getrawmempool true`)
- **Effect**: Attacker fills mempool with dependency-poisoned, non-standard transaction chains → `getblocktemplate` selects unminable transactions → miners waste hash power → miner revenue drops → miners abandon Zebra as template provider → Zebra nodes lose mining support. Combined with F-01, an authenticated RPC client can also make the mempool unreadable, hiding the attack from operators.
- **Argus mapping**: This is a multi-finding chain; Stage 2.5 (cross-crate attack-chain analysis) would flag it when v0.4.0 ships.

### Comp-2 — Peer-Eclipse-via-RPC-Leak Composition

- **Components**: H-15 (peer-info leak) + Issue #9111 (peer scoring not yet implemented — unverified) + Issue #7824 (synthetic-node spread — unverified)
- **Effect**: Attacker calls `getpeerinfo` (authenticated) → learns peer IP set and connection durations → identifies peers nearing rotation → deploys synthetic nodes at those addresses → Zebra connects to synthetic nodes → synthetic nodes serve empty `FindBlocks` responses → block discovery degrades.
- **Argus mapping**: Requires cross-referencing the three open issues; Stage 1 should list them as related.

---

## 3. FFI Callback Audit Targets

The sighash CVEs (claimed: GHSA-8m29-fpq5-89jj, GHSA-pvmv-cwg8-v6c8, GHSA-gq4h-3grw-2rhv — all unverified) all trace to a single architectural pattern: a Rust callback passed to C++ that must enforce consensus rules the C++ code *used to* enforce before a refactoring. This maps to **H-09** in the v0.3.4 catalogue. The following additional callbacks should be audited for the same class:

| Callback | Crate | Potential Missing Rule |
|----------|-------|----------------------|
| `script_verifier` callback passed to `zcash_script` | `zebra-script` | Pre-NU5 sighash computation uses raw vs. canonical hash type (partially fixed; verify completeness) |
| `is_time_valid_at` closure passed to block-header verification | `zebra-consensus` | Median-time-past calculation uses peer-supplied timestamps; verify the consensus bound is enforced |
| Orchard proof verification via `orchard::bundle::BatchValidator` | `zebra-chain` → `orchard` crate | The identity `rk` panic was fixed, but are there other edge-case inputs (degenerate points, non-canonical encodings) that cause `unwrap()` in the proof verifier? |

The Stage 2 **supply-chain-ffi angle** owns this audit. Each callback should be checked per v0.3.4 vector **H-09** detection rule: diff Rust callback against pre-refactoring foreign-impl history OR cross-reference protocol spec.

---

## 4. Updated Stage 2 Angle Priorities (incorporating Volume II)

| Angle | Priority | New Hypotheses Covered |
|-------|----------|----------------------|
| **logic-state-machine** | Highest | H-11, H-12, H-14, H-16, H-17, H-19, H-20, Comp-1, Comp-2 |
| **resource-exhaustion** | Highest | H-13 + F-01 (existing) + composite-DoS pairs |
| **arithmetic** | High | H-11, H-18 |
| **supply-chain-ffi** | High | H-19, FFI callback audit (§3) |
| **crypto-misuse** | Medium | H-15 |
| **concurrency** | Medium | H-16, H-20 |

This priority extends the Zebra-specific recalibration from `zebra-cve-patterns.md` (v0.3.4 release). Combined across all three pattern files, the Zebra angle priority is:

1. **logic-state-machine** — Highest (dominates consensus + RPC + mempool surface)
2. **supply-chain-ffi** — Highest (FFI callbacks + dep CVEs)
3. **resource-exhaustion** — Highest (allocation amplification + composite DoS)
4. **arithmetic** — High (subsidy + difficulty + height math)
5. **crypto-misuse** — Medium (Orchard / Sapling / nonce / RNG)
6. **memory-safety** — Medium (Equihash FFI + RocksDB FFI as primary surface)
7. **concurrency** — Medium (chain-tip + mempool + TOCTOU)
8. **unsafe-trait** — Low (Zebra uses `unsafe` sparingly)

---

## 5. How to Use This File

```bash
cd <zebra-clone>
mkdir -p assets/docs
cp ~/Documents/Dev/argus/examples/zebra-patterns.md           assets/docs/zebra-patterns.md
cp ~/Documents/Dev/argus/examples/zebra-cve-patterns.md       assets/docs/zebra-cve-patterns.md
cp ~/Documents/Dev/argus/examples/zebra-attack-paths-v2.md    assets/docs/zebra-attack-paths-v2.md
# Then in Claude Code or Codex:
/argus    # Claude Code; or conversational "audit this rust" on Codex
```

Argus will consume all three pattern files at Stage 1. The 20 hypotheses (10 from `zebra-patterns.md` + 10 here as H-11 through H-20) span the same structural classes that produced the claimed-12-CVE history. The strongest candidates with clear PoC paths and measurable zcashd-divergence:

- **H-11** (coinbase fee rounding)
- **H-12** (orphan-block RPC panic)
- **H-14** (mempool dependency poisoning)
- **H-17** (non-standard tx acceptance)
- **H-19** (non-canonical CompactSize in Equihash solution)

These five are the highest-leverage Volume II picks for a Zebra audit.

---

## 6. Honest framing

- All 10 hypotheses are AI-drafted from pattern transposition + cross-crate composition + FFI audit + monetary-arithmetic strategies. None has been verified against the live Zebra codebase.
- Specific Issue / GHSA / CVE numbers are cited but unverified. The structural arguments stand independently of those references; the patterns are catalogue-aligned (V-IDs in v0.3.4 catalogue).
- Argus Stage 2 will produce its own findings independent of these hypotheses. The pattern files prime priority; they don't constrain output.
- **Do not submit any hypothesis without a fully reproducible PoC from Stage 3 and independent manual verification against the Zebra codebase.** v0.3.3+ enforces Tier-1-live-e2e for CONFIRMED — a hypothesis that cannot produce a live reproducer doesn't reach SUBMIT.

---

## 7. Companion files in `examples/`

| File | Role |
|------|------|
| `zebra-patterns.md` | Architecture + Volume I hypotheses (H-1 through H-10) |
| `zebra-cve-patterns.md` | CVE root-cause patterns (drove v0.3.4 catalogue extensions F-08, G-09, H-09, I-11, I-12) |
| **`zebra-attack-paths-v2.md`** | **This file: Volume II hypotheses (H-11 through H-20) + cross-crate compositions + FFI audit targets** |

All three load at Stage 1 if dropped in `<zebra-clone>/assets/docs/`. Stage 2 angles consume them as priority hypotheses to investigate.
