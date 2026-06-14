# Argus Changelog

All notable changes to Argus are recorded here. Versioning follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- **README presentation pass** (no behavior change). Restructured `README.md` for readability: centered hero with version/license/runtime badges and a quick-nav line; converted the dense two-mode opening blockquote into a `Two modes` comparison table; surfaced Install/Usage earlier; collapsed the repository-layout tree behind a `<details>` block. All facts, links, and section content preserved verbatim.

## [0.6.5] — 2026-06-05

**Wire all 8 verified infra dossiers' §6 methodology into their agent files.** Each `drafted-verified` dossier's `## 6. Gaps → angle changes` proposals were applied to the matching `*-agent.md` — methodology only; the CVE/advisory citations were verified and corrected in v0.6.4 and left untouched here. Anti-bloat respected per proposal: "extend" merged into an existing CHECK, "new-check" added only where genuinely absent. Net +398 lines across 8 agent files. Each angle below lists its new CHECKs, extends, and skipped (already-implemented) proposals.

### Added — `references/hacking-agents/infra/logic-state-machine-agent.md`
- **CHECK 14 — Error/panic inside an atomic finalization hook → deterministic halt** (NEW, L1): fallible ops (div, index, `unwrap`, overflow) reachable from `EndBlocker`/`FinalizeBlock`/`ProcessProposal`/`on_finalize` on attacker-influenced state → identical failure on every node → chain halt. VERIFIED: Cosmos ISA-2025-002 (GHSA-47ww-ff84-4jrg), ASA-2025-003 (GHSA-x5vx-95h7-rv4p); CometBFT ASA-2024-011, ASA-2024-001.
- **CHECK 15 — Unvalidated proposer-injected consensus data** (NEW, L2): proposer-supplied vote extensions / injected txs / voting-power summaries consumed for accounting or indexing without re-validation against canonical state. VERIFIED: Cosmos ASA-2024-006 (GHSA-95rx-m9m5-m94v), CometBFT ASA-2024-011 (GHSA-p7mv-53f2-4cwj).
- **CHECK 16 — Positional state-identity collision** (NEW, L5): maps/indexes keyed by slot/height/sequence for multi-variant content → two distinct objects collapse to one identity → partition/repair failure. Require content-hash keying or an intake-layer singleton invariant. VERIFIED: Solana Dec-2020 mainnet-beta stall.
- **CHECK 17 — State-transition window escape** (NEW, L6): re-homing ops (redelegation/migration/transfer) during a deferred-penalty window let an object escape liability. VERIFIED: Cosmos ASA-2024-005, CWE-372 (GHSA-86h5-xcpx-cfqc).
- **CHECK 18 — Cross-client / cross-impl divergence** (NEW, L8, depth-agent): spec-discretionary behaviors (drop/keep under load, ambiguous-fork resolution) reasoned differentially against spec/second impl. VERIFIED: Prysm vs Lighthouse, Ethereum May-2023.
- **CHECK 19 — Out-of-order protocol-rule application via sim/RPC path** (NEW, L9): sim/RPC entrypoints with per-feature/EIP overrides reaching states the real chain never permits; ports to reth/revm `eth_call` overrides. VERIFIED: geth iosiro Feb-2024 (fixed v1.13.13) — corrects the prior "JSON-RPC re-entrancy" framing.

### Changed — `references/hacking-agents/infra/logic-state-machine-agent.md`
- **CHECK 3 (epoch/slot boundary)** — added regeneration-cost sub-point (L7): boundary-spanning-message validation that regenerates prior state with a finite cache → flood overflows cache → finality/liveness loss; cross-ref Resource-Exhaustion. VERIFIED: Ethereum May-2023 (Prysm fix v4.0.4).
- **CHECK 10 (governance ordering)** — added consensus-param activation-halt sub-check (L4): treat the activation block as a distinct transition; values passing steady-state validation may panic at the boundary; activation-halt via unprivileged-passable proposal is NOT trust-downgraded. Cross-ref Arithmetic CHECK 10 + Economic Design. VERIFIED: CometBFT ASA-2024-001 (GHSA-qr8r-m495-7hc4).
- Output-field enum extended (`check_number` CHECK 1-19).

### Skipped as already-implemented
- **L10 partial-state write** — CHECK 1 already covers multi-write functions with error paths between writes + rollback check.
- **L11 swallowed-error variants** — CHECK 4 already covers `.unwrap_or_default()`, `.ok()`, `if let Err(_) { return }`.
- **L12 clock-dependence** — CHECK 11 already covers consensus clock-split with full procedure + N-second skew reasoning.
- **L13 multi-hop error propagation** — CHECK 12 already covers A→B→C error type mapping incl. IBC ack swallow.

### Added — `references/hacking-agents/infra/arithmetic-agent.md` (394 → 428, +34)
- **CHECK 14 — Wrapping where panic was expected** (NEW, A5): per-op overflow contract on "checked" big-int types — `cosmwasm-std` `Uint{256,512}::pow`/`Int{256,512}::pow`/`Int::neg` wrap regardless of `overflow-checks`; require explicit `checked_pow`. Anchors RUSTSEC-2024-0338.
- **CHECK 15 — `overflow-checks = true` becomes the DoS** (NEW, A8): after confirming the hardening flag is on, re-scan hot/crypto/serialization arithmetic for attacker-reachable panic-DoS; recommend per-op `wrapping_*`/`checked_*` over the global flag. Anchors RUSTSEC-2025-0009.

### Changed — `references/hacking-agents/infra/arithmetic-agent.md`
- **CHECK 2 (A4)** — broadened from multiply-only to add-AND-multiply size math; `new_cap + offset` overflows an allocation the same way `len * elem_size` does. Anchors RUSTSEC-2026-0007 (add), RUSTSEC-2017-0004 / CVE-2018-1000810 (multiply).
- **CHECK 4 (A3)** — added the addition-overflow-inside-guard shape (`cap >= new + offset`) alongside the existing subtraction-underflow guard-bypass. Anchors RUSTSEC-2026-0007.
- **CHECK 5 (A2)** — added `try_from`-over-`as` fix recommendation and round-trip golden signature; trace unwrapped `try_from` to panic-DoS (→ CHECK 6).
- **CHECK 7 (A6)** — added the two-step stored-rate round-trip invariant (`redeem(deposit(x)) <= x`); round-down rate then round-up redeem → value extraction; prefer single-floor Mul-Div. Anchors Kamino/Certora.
- **CHECK 8 (A13)** — added the signed `i::MIN / -1` always-panics edge (panics even with `overflow-checks` off; not covered by a zero-divisor guard).
- Phase 1 clippy seed list extended with `arithmetic_side_effects`; CosmWasm §Phase 4 noted the `pow`/`neg` exception; `check_number` output enum now CHECK 1-15.
- **Skipped as already-implemented**: A1 `a*b/c` value-math (CHECK 1 covers it), A7 `checked_*().unwrap()` panic-DoS (CHECK 6 covers it with call-site severity), and the Phase-1 `overflow-checks` profile read (Phase 1 step 3 already does it).

### Added — `references/hacking-agents/infra/concurrency-agent.md` (352 → 433, +81)
- **CHECK 12 — Teardown-path-symmetry double-free** (NEW, G-02 / D02–D03): per-element, enumerate every freeing path on lock-free `Drop`/epoch-GC/steal teardown; assert idempotent take + null/swap; Loom + Miri. Anchors RUSTSEC-2025-0024 (crossbeam-channel), -2021-0093 (crossbeam-deque steal), -2018-0009 (crossbeam epoch-GC).
- **CHECK 13 — Data race after channel close / use-after-close** (NEW, G-04 / D05): test the {close, send, recv} interleaving for shared-memory data race — distinct from CHECK 7's hang-on-drop liveness check. Anchors RUSTSEC-2021-0124 / CVE-2021-45710 (tokio oneshot).
- **CHECK 14 — Send-without-Sync on a parallel operation** (NEW, G-05 / D06): parallel same-value `clone`/read ⇒ require `Sync`, not just `Send`; proof is a witness `Send`-not-`Sync` type compiling against the API. Anchors RUSTSEC-2025-0023 (tokio broadcast); cross-refs Angle 2.
- **CHECK 15 — Reentrant read-lock deadlock on fair RwLock** (NEW, G-07 / D11): trace `read()`-guard live ranges for same-lock recursion; task-fair parking_lot blocks the second reader behind a queued writer → self-deadlock.

### Changed — `references/hacking-agents/infra/concurrency-agent.md`
- **CHECK 1 + Phase 2 lock inventory (G-01 / D01)** — lock-order graph now tracks node identity at FIELD granularity, not type; Parity #9952's cycle was between two `RwLock` fields of one struct and a type-only graph misses it. CHECK 1 Source anchored to OpenEthereum #9952 / PR #9954.
- Phase 1 grep pre-seed extended (Drop/Stealer/ManuallyDrop/defer for CHECK 12); Phase 2 inventory extended (teardown + reentrancy); Stage-3 PoC backend table + `violation_class` output enum extended for CHECK 12–15.
- **Skipped as already-implemented**: G-03 (CHECK 4 already has the per-`Relaxed`-atom data-guarding publish/consume trace) and G-06 (CHECK 6 already covers the `std::sync::Mutex`-across-`.await` migrated-thread-drop UB, not just the DoS angle).

### Added — `references/hacking-agents/infra/crypto-misuse-agent.md` (454 → 493, +39)
- **CHECK 12 — Signer-API oracle / decoupled public key** (NEW, C9): detect deterministic signers that accept a caller-supplied/decoupled public key (ed25519-dalek < 2.0 double-public-key oracle, RUSTSEC-2022-0093) → same `R`, differing `S` → key extraction. FP guard for signers that derive the pubkey from the secret.
- **CHECK 13 — AEAD plaintext-on-failure (in-place decrypt)** (NEW, C11): `decrypt_in_place*` leaves unauthenticated plaintext in the buffer on tag failure (aes-gcm 0.10.0–0.10.2, RUSTSEC-2023-0096; fixed 0.10.3). Version- and usage-gated.

### Changed — `references/hacking-agents/infra/crypto-misuse-agent.md`
- **CHECK 8 (malleability)** — added DER-canonicalisation step (non-canonical DER admits a second valid encoding even under low-S; python-ecdsa CVE-2019-14859 mechanism), per-crate (`k256`/`secp256k1` strict vs hand-rolled).
- **CHECK 7 (side-channel)** — added nonce-bit-length leak procedure (C10): identify variable-length scalar-mult before dudect; Minerva/TPM-FAIL signature-count thresholds; distinguish short- vs full-length-nonce signing in dudect.
- **CHECK 11 (Merkle proof)** — added prefix-equality (Dragonberry) constraint: exact-equality + length bounds on attacker-influenced structural proof fields, not substring/`contains`; corrected the "missing subkey verification" framing to the verified under-constrained-leaf-prefix mechanism; pin post-Dragonberry `ics23`.
- Output-field enums extended (`misuse_class` +signer-api-oracle/aead-plaintext-on-failure; `check_number` CHECK 1-13).
- **Skipped as already-implemented**: C6 per-curve three-check table (CHECK 6 already has it) and Phase 1 `cargo audit`/`cargo deny` + grep pre-seed (Phase 1 already covers it).

### Added / Changed — `references/hacking-agents/infra/memory-safety-agent.md` (387 → 416, +29)
- **CHECK 13 — Deserialization layout unsoundness (ZST / header-vs-array length)** (NEW, A10): header length not checked against flexible-array length; cross-ref Angle 8. VERIFIED RUSTSEC-2024-0002.
- **CHECK 0** extended with the "start from the safe API surface, trace inward to the violable invariant" dominant-pattern framing; **CHECK 2 (UAF)** extended with iterator/lifetime-escape (bumpalo/lru/secp256k1); **CHECK 4 (OOB)** extended with `get_unchecked`/`size_hint`/capacity-overflow; **CHECK 1** extended with `#[repr(C, packed)]` reorder + 32-bit primitive-vs-atomic alignment.
- Skipped as already-implemented: Stacked/Tree-Borrows (CHECK 7), FFI-panic/`catch_unwind` (CHECK 12), `cargo audit`/`geiger` pre-seed (Phase 1).

### Added / Changed — `references/hacking-agents/infra/resource-exhaustion-agent.md` (341 → 361, +20)
- **CHECK 2b — Rapid-reset / cheap-transition cap bypass** (NEW): client transitions that bypass concurrency caps and create lazily-cleaned server work. VERIFIED RUSTSEC-2023-0034 / -2024-0003 (h2).
- **CHECK 1 (unbounded growth)** extended with producer/drain asymmetry, back-pressure drain (yamux receive-window stall), and monotonic-key/no-eviction (ckb `SessionId` map); **CHECK 11 (pre-auth)** extended with the reflection/amplification endpoint-proof sub-check (devp2p discv4 — the fix is the proof, not a size cap).
- Skipped as already-implemented: length-prefix allocation (CHECK 5), HashDoS (CHECK 7), slowloris/overall-deadline (CHECK 12).

### Added / Changed — `references/hacking-agents/infra/supply-chain-ffi-agent.md` (387 → 445, +58)
- **CHECK 13 — Safe wrapper over `from_raw_parts`** (NEW, H05): a safe fn casting arbitrary bytes to `&[T]` (type confusion). VERIFIED RUSTSEC-2024-0431 (xous).
- **CHECK 14 — Variadic / out-param `&` vs `&mut`** (NEW, H04): `improper_ctypes` blind spot; `--release` drops the C-side write → NULL deref. VERIFIED RUSTSEC-2024-0429 (glib).
- **CHECK 15 — Panic-safety half-updated `len`** (NEW, H07): manual-drop loop updating `len` after the loop → re-drop under `catch_unwind`. VERIFIED RUSTSEC-2026-0122 (rkyv).
- **CHECK 10 (panic-across-FFI)** extended toolchain-aware (pre-1.81 UB vs 1.81+ abort vs `C-unwind`); **CHECK 4 (build.rs)** extended with the CI-env-var-gated dormant-malware signal (`rustdecimal`).
- Skipped as already-implemented: `cargo audit` reachability discipline (CHECK 1).

### Added / Changed — `references/hacking-agents/infra/unsafe-trait-agent.md` (266 → 295, +29)
- **CHECK 9 — Panic window in raw-memory ownership code** (NEW, B03/B04): name the window between bookkeeping-says-live and memory-initialized; require ordering-fix or drop-guard. VERIFIED RUSTSEC-2021-0040 (arenavec), -2021-0033 (stack_dst). Plus a **B05 init-panic sub-check** (lazy/once types using `unreachable_unchecked` after a panicking init; once_cell `Lazy` RUSTSEC-2019-0017).
- **CHECK 1/2** extended with the escape-API trace (a construction-only `Send`/`Sync` bound defeated by a later `.map()`/`get_mut()`/`Deref`/iterator re-exposing inner `T`; reffers RUSTSEC-2020-0094) + explicit bound-direction step.
- Skipped as already-implemented: bound-direction in CHECK 2 (prior pass), Rudra pre-seed (Phase 1), B06–B08 generic-pattern labeling.

### Docs
- README refreshed to v0.6.5: infra mode's 9 evidence-grounded angles + ZK circuit soundness, the research-dossier / verification-mandate story, dual-target (Claude Code + Codex CLI) install, and the `/argus-doctor` + `/argus-resume` commands.

## [0.6.4] — 2026-06-05

**Primary-source verification + re-research of all 8 non-ZK infra dossiers.** The v0.6.3 dossiers were authored from model memory and never verified. An adversarial verification pass (8 agents, every CVE/incident claim fetched against NVD/RUSTSEC/GHSA) found **only 38% of real-world claims verified (30/71)** — with a fabricated anchor (CVE-2022-31094 cited as a "Substrate `memory_units` buffer overflow"; it is actually a ScratchTools browser-extension XSS), 7 misattributions (CVE-2019-14858 is Ansible not python-ecdsa; CVE-2018-20990 is `tar` not smallvec; RUSTSEC-2023-0071 is the RSA Marvin attack not shlex; CVE-2022-31173 is a recursion DoS not a zeroization bug), and marquee incidents described with invented mechanisms (Wormhole framed as integer truncation — it was a signature-verification bypass; Binance Bridge as an overflow — it was an IAVL Merkle-proof forgery; the Parity "OnDemand" deadlock and devp2p amplification mechanisms were fabricated). All 8 dossiers were then **re-researched from primary sources** and are now born-verified.

### Added
- `references/research/VERIFICATION-REPORT-v0.6.3.md` — full adversarial verification report: per-dossier scorecard, confirmed-error worklist with correct facts + primary-source URLs, pattern analysis, recommendation.
- `references/research/README.md` — **verification mandate** section (MANDATORY): no dossier may reach `drafted-verified` or feed an `*-agent.md` until every CVE/incident is confirmed by a fetched primary source; no advisory id on an unverified mechanism; status ladder `scaffold → drafted → drafted-verified → wired-into-angle`. Cites this episode (38% → 0 errors) as the reason.

### Changed — re-researched dossiers (all now `drafted-verified`, primary-source-anchored)
- `arithmetic-research.md` (8 verified advisories), `concurrency-research.md` (8), `crypto-misuse-research.md` (15), `logic-state-machine-research.md` (9, real CometBFT/Cosmos-SDK GHSAs + correct Solana post-mortem), `memory-safety-research.md` (14), `resource-exhaustion-research.md` (9), `supply-chain-ffi-research.md` (11), `unsafe-trait-research.md` (9 RUSTSEC advisories + Rudra OSDI 2021). Every retained advisory carries a fetched URL; unverifiable classes are labeled `[generic pattern — no specific incident]` with no id attached.

### Fixed — agent files (wrong CVEs propagated from the v0.6.3 dossiers)
- `memory-safety-agent.md` — replaced fabricated CVE-2022-31094 anchor (UAF/OOB sources) with real advisories (lru RUSTSEC-2021-0130/2026-0002, bumpalo RUSTSEC-2022-0078, smallvec RUSTSEC-2021-0003, vmm-sys-util RUSTSEC-2024-0002, bytes RUSTSEC-2026-0007); Heartbleed demoted to labeled cross-language analogy.
- `resource-exhaustion-agent.md` — replaced CVE-2018-20990 (it is `tar`, not smallvec) with rust-libp2p RUSTSEC-2022-0084 / ckb RUSTSEC-2021-0108 / h2 RUSTSEC-2023-0034; added misattribution guard.
- `supply-chain-ffi-agent.md` — replaced fabricated CVE-2022-31094 + misattributed RUSTSEC-2023-0071 with `rustdecimal` RUSTSEC-2022-0042, shlex RUSTSEC-2024-0006, glib RUSTSEC-2024-0429.
- `unsafe-trait-agent.md` — replaced the CVE-2022-23639 "spinlock TOCTOU Sync" anchor (it is an *alignment* bug) with the conquer-once `OnceCell` Sync-without-Send bug (RUSTSEC-2020-0101); added bound-direction methodology and a do-not-conflate guard.

## [0.6.3] — 2026-06-05

> **CORRECTION (superseded by v0.6.4):** the dossiers described in this section were authored from model memory and **failed primary-source verification (38% of claims verified)**. The CVE anchors named below are unreliable — e.g. CVE-2022-31094 ("memory_units") is fabricated, and CVE-2021-31525 / CVE-2023-44487 / CVE-2024-24576 / CVE-2021-21299 were never present in the actual dossiers. v0.6.4 re-researched all 8 dossiers from primary sources and corrected the agent files. Treat the CVE citations in this 0.6.3 entry as historical/unverified; see v0.6.4 and `VERIFICATION-REPORT-v0.6.3.md`.

**Research dossier sweep: 5 angles grounded in evidence.** Each of the remaining 5 infra angles now has a research dossier (real-vulnerability-anchored methodology) and a restructured Phase 1-3 agent with calibration headline, pre-seed tooling, per-class CHECKs with golden signatures, PoC discipline, and coordination boundaries. All 9 infra angles now have research dossiers. Headline pattern: every CHECK is traceable to a specific bug class in the dossier; every bug class is anchored in at least one real CVE or production post-mortem.

### Added — research dossiers (5 new)

- `references/research/concurrency-research.md` — 10-class taxonomy (D11–D20) anchored in CVE-2021-31525 (net/http header timeout), CVE-2023-44487 (HTTP/2 Rapid Reset), and production DLT concurrency bugs. 5 gaps identified → 5 proposals applied.
- `references/research/memory-safety-research.md` — 11-class taxonomy (D01–D11) anchored in CVE-2024-24576 (Windows `Command` args), CVE-2021-21299 (hyper `Transfer` header), and production DLT UB. 7 gaps identified → 7 proposals applied.
- `references/research/unsafe-trait-research.md` — 10-class taxonomy (B01–B10) anchored in CVE-2022-23639 (crossbeam `AtomicCell`) and production DLT trait soundness violations. 5 gaps identified → 5 proposals applied.
- `references/research/resource-exhaustion-research.md` — 12-class taxonomy (F01–F12) anchored in CVE-2018-20990 (rust-smallvec) and Ethereum devp2p packet amplification. 5 gaps identified → 5 proposals applied.
- `references/research/supply-chain-ffi-research.md` — 12-class taxonomy (H01–H12) anchored in CVE-2022-31094 (Substrate `memory_units`), RustSec advisory classes, and production DLT supply-chain compromises. 6 gaps identified → 6 proposals applied.

### Changed — `references/hacking-agents/infra/concurrency-agent.md`

Research-grounded depth pass — all 5 dossier proposals applied. 92 lines → ~350 lines (+258). Changes:

- **Calibration headline** added — Go's "share by communicating" vs Rust's "fearless concurrency"; three damage classes (data race → UB, deadlock → chain halt, channel close → message loss).
- **Phase 1 pre-seed** — `cargo clippy -- -W clippy::await_holding_lock -W clippy::mutex_atomic -W clippy::redundant_clone`; Go race detector (`go test -race`); Loom model checker for Rust.
- **Reorganized as 10 numbered CHECKs** — each with signal, step-by-step procedure, golden signature, and real-instance source:
  - CHECK 1 — Channel close + receive (D11): send-on-closed-channel panic, Go channel close receivers, tokio `oneshot` cancellation
  - CHECK 2 — Shared-map data race (D12): Go `map` without `sync.Mutex`/`sync.Map`, Rust `HashMap` without `Mutex`/`RwLock`
  - CHECK 3 — Atomic ordering (D13): `Ordering::Relaxed` on data-guarding atomics, Go `sync/atomic` vs `sync.Mutex`
  - CHECK 4 — Lock ordering / deadlock (D14): `Mutex` acquisition order mismatch, `try_lock` vs blocking `.lock()`
  - CHECK 5 — Select / channel fairness (D15): Go `select` non-determinism, `tokio::select!` bias, starvation
  - CHECK 6 — Lock held across await (D16): std `Mutex` held across `.await`, `RwLock` write starvation, `tokio::sync::Mutex` vs `std::sync::Mutex`
  - CHECK 7 — Send/Sync in multi-thread context (D17): `Rc`/`RefCell` crossing thread boundary, `!Send` type in tokio task
  - CHECK 8 — Goroutine/task leak (D18): spawned goroutine/task with no cancellation path, channel send without receiver, `JoinHandle` not awaited
  - CHECK 9 — Once / init ordering (D19): `Once` deadlock via recursive `call_once`, Go `sync.Once` re-entry, `lazy_static` / `once_cell` circular deps
  - CHECK 10 — Atomic cell / lock-free structure (D20): `AtomicCell<T>` soundness, spinlock TOCTOU (crossbeam class), lock-free queue ABA
- **Go-specific notes** throughout — race detector invocation, `sync.Map` vs `map+Mutex`, `select` non-determinism, goroutine leak patterns
- **Stage-3 PoC discipline table** — per-class backend mapping (Loom, Go race detector, Miri, Tokio-console, stress test)
- **Coordination boundaries** — with Memory Safety (Miri UB from races), Unsafe Trait (Sync impl soundness), Resource Exhaustion (lock-DoS)

### Changed — `references/hacking-agents/infra/memory-safety-agent.md`

Research-grounded depth pass — all 7 dossier proposals applied. 57 lines → ~450 lines (+393). Changes:

- **Calibration headline** added — unsafe Rust's trust contract; the most concentrated attack surface in DLT infrastructure; three sub-classes dominate (raw pointer ops in network parsing, uninitialized memory in consensus hot paths, transmute-based lifetime/type violations).
- **Phase 1 pre-seed** — exhaustive unsafe-block grep, transmute/ptr::read/cast/Mem::uninitialized/maybe_uninit/ManuallyDrop enumeration as seed list. Miri flag: `MIRIFLAGS="-Zmiri-tag-raw-pointers" cargo miri test`.
- **Reorganized as 13 numbered CHECKs** — each with signal, step-by-step procedure, golden signature, and real-instance source:
  - CHECK 0 — Unsafe block safety-contract verification (ground-level check: every `unsafe {}` must document its safety contract and satisfy it)
  - CHECK 1 — Raw pointer dereference without provenance check (D01): `unsafe { *ptr }` where `ptr` is from FFI, transmute, or `Vec::as_ptr()`
  - CHECK 2 — Use of uninitialized memory (D02): `MaybeUninit::assume_init()` without written-to proof, `std::mem::uninitialized()` (deprecated), `std::mem::zeroed()` on non-`MaybeUninit` types
  - CHECK 3 — Transmute unsoundness (D03): `std::mem::transmute::<A, B>()` where `size_of::<A>() != size_of::<B>()` or alignment differs — and the subtler padding-byte/padding-in-array UB
  - CHECK 4 — Out-of-bounds access (D04): `slice::get_unchecked()` / `Vec::get_unchecked()` without bounds verification, raw pointer offset arithmetic without bounds check
  - CHECK 5 — Integer overflow in unsafe (D05): wrapping arithmetic in unsafe context that feeds a `get_unchecked` index or a raw pointer offset — the overflow creates an OOB access
  - CHECK 6 — Dangling pointer / use-after-free (D06): `Vec::as_ptr()` outliving the Vec, reference derived from freed allocation, `ManuallyDrop` then access
  - CHECK 7 — Mutable aliasing violation (D07): `&mut T` and `&T` (or `&mut T` and `&mut T`) coexisting — UB per Stacked Borrows / Tree Borrows
  - CHECK 8 — Unsafe function contract violation (D08): every `unsafe fn` documents preconditions in `# Safety`; verify every call site satisfies them
  - CHECK 9 — Pointer-to-reference conversion UB (D09): `&*ptr` or `&mut *ptr` on null, misaligned, or dangling raw pointers — references MUST be non-null and aligned
  - CHECK 10 — Type-punning via union (D10): union field access of non-`Copy` types, union with invalid bit patterns for the accessed variant
  - CHECK 11 — FFI pointer lifetime (D11): `extern "C"` raw pointer outliving the Rust allocation — Miri can't catch cross-language UAF
- **Stage-3 PoC discipline table** — per-class backend mapping (Miri, ASan, Kani, Valgrind, manual contract verification)
- **Coordination boundaries** — with Unsafe Trait (Sync impls enabling races), Concurrency (Loom demonstrates the race that UAFs from), Supply Chain & FFI (FFI binding soundness), Arithmetic (overflow degradation in unsafe context)

### Changed — `references/hacking-agents/infra/unsafe-trait-agent.md`

Research-grounded depth pass — all 5 dossier proposals applied. 252 lines → ~265 lines (+13). Changes:

- **Calibration headline** added — unsound `Sync` impl silently enables data races in safe code; CVE-2022-23639 crossbeam `AtomicCell` as anchor case.
- **Phase 1 pre-seed** — `cargo rudra` as the single highest-ROI tool; Clippy `missing_safety_doc` + `undocumented_unsafe_blocks`; high-signal grep for `unsafe impl Send/Sync`, `unsafe impl TrustedLen`, `unsafe impl Deref`, `#[global_allocator]`, `impl GlobalAlloc`, `impl Drop`, `AssertUnwindSafe`.
- **Phase 2 inventory** — unsafe trait enumeration (Send, Sync, TrustedLen, Deref, custom allocator, custom Drop).
- **CHECK 0 added** — `unsafe trait` safety-contract verification: every `unsafe impl` must have `// SAFETY:` comment; each claimed invariant must be verified against implementation.
- **CHECK 4 (Drop) + CHECK 9 (unwind) reorganized** — B09 (unwind safety) split into its own CHECK 9 with `catch_unwind` test procedure; B04 (Drop soundness) deepened with `std::mem::forget` safety, double-free, and Miri verification.
- **Stage-3 PoC discipline table** — per-class backend mapping (Rudra, Loom, Kani, Miri, unit test).

### Changed — `references/hacking-agents/infra/resource-exhaustion-agent.md`

Research-grounded depth pass — all 5 dossier proposals applied. 87 lines → ~340 lines (+253). Changes:

- **Calibration headline** added — resource exhaustion is the most asymmetric attack class; devp2p packet amplification as anchor case.
- **Phase 1 pre-seed** — high-signal grep patterns for `.push()` / `.insert()` / `.with_capacity()` / `vec![]` / `FxHash` / decompression / clone chains / regex / recursive functions / subscription leaks.
- **Reorganized as 12 numbered CHECKs** — each with signal, step-by-step procedure, golden signature, and real-instance source:
  - CHECK 1 — Unbounded queue/collection growth (F01)
  - CHECK 2 — Quadratic / superlinear complexity (F02)
  - CHECK 3 — Deep recursion / stack overflow (F03)
  - CHECK 4 — Lock held across I/O causing DoS (F04, joint with Concurrency)
  - CHECK 5 — Large allocation from attacker-controlled capacity (F05, the devp2p class: Borsh/scale-codec/serde length prefix allocation)
  - CHECK 6 — Memory amplification via clone chains (F06)
  - CHECK 7 — HashDoS (F07, FxHash/BuildHasherDefault/fixed-seed ahash audit)
  - CHECK 8 — Regex catastrophic backtracking (F08, `regex` crate = safe, `fancy-regex` = attackable)
  - CHECK 9 — Decompression/decoding bomb (F09, zstd/flate2/snap without max-size cap)
  - CHECK 10 — Subscription/connection leak (F10)
  - CHECK 11 — Pre-auth resource consumption (F11, the devp2p intersection: length-prefix allocation BEFORE auth)
  - CHECK 12 — Slowloris / slow-read attack (F12, per-read vs per-connection timeout audit)
- **Stage-3 PoC discipline table** — per-class backend mapping (cargo-fuzz, ASan, criterion, stress test, Loom).

### Changed — `references/hacking-agents/infra/supply-chain-ffi-agent.md`

Research-grounded depth pass — all 6 dossier proposals applied. 87 lines → ~310 lines (+223). Changes:

- **Calibration headline** added — supply chain bugs live in code you didn't write, at boundaries where Rust can't help, or in code that runs before audit begins; CVE-2022-31094 as anchor case.
- **Phase 1 pre-seed** — `cargo audit --json`, `cargo deny check`, `cargo geiger --output-format Json`, Clippy security lints, high-signal grep patterns (`extern "C"`, `#[no_mangle]`, `unsafe impl Send/Sync`, `AssertUnwindSafe`, proc-macro enumeration).
- **Phase 2 inventory** — `Cargo.toml`/`Cargo.lock` deps, `extern "C"` blocks, `#[no_mangle]` exports, `build.rs` files, proc-macro deps, FFI wrapper types.
- **Reorganized as 12 numbered CHECKs** — each with signal, step-by-step procedure, golden signature, and real-instance source:
  - CHECK 1 — Known-vulnerable dependency (H01, reachability-weighted severity)
  - CHECK 2 — FFI null-pointer dereference (H02)
  - CHECK 3 — Allocator mismatch across FFI (H03)
  - CHECK 4 — Malicious / fragile build.rs (H04, capability audit)
  - CHECK 5 — Unsafe in unaudited third-party (H05, `cargo geiger` + `cargo vet` risk-tiering)
  - CHECK 6 — Typosquatted crate (H06, name-distance check)
  - CHECK 7 — `repr(C)` layout mismatch (H07, side-by-side struct comparison)
  - CHECK 8 — `#[no_mangle]` symbol collision (H08, systematic export scan)
  - CHECK 9 — Yanked crate in lockfile (H09)
  - CHECK 10 — Unwinding through FFI / C-unwind (H10, NEW: Rust panic unwinding through C frames = UB)
  - CHECK 11 — Thread-safety of FFI types (H11, C library thread-safety label audit)
  - CHECK 12 — Proc-macro supply chain (H12, NEW: compile-time arbitrary code execution audit)
- **Stage-3 PoC discipline table** — per-class backend mapping (cargo audit + cargo tree, Miri, manual audit, cargo geiger, cargo deny, strace).
- **Stage-0.5 sweep preserved** — the deterministic supply-chain backend sweep (cargo audit, cargo deny, cargo geiger, clippy) remains as Phase 1.

### Changed — `references/research/RESEARCH-INDEX.md`

All 9 infra angles now marked Complete with dossier filenames, taxonomy sizes, real-instance anchors, and agent line-count deltas. Remaining work: primary-source verification pass for all [model-knowledge] claims, and smart-contract mode angles.

## [0.6.2] — 2026-06-05

**ZK Circuit Soundness angle — research-grounded depth pass + dossier framework.** First application of a new research-dossier discipline: rather than writing angle methodology from intuition, build an evidence base from real vulnerabilities first, then distill it into checks. A multi-agent research pass (5 source-tier researchers → synthesis → adversarial completeness critic → 8 gap backfills → finalize) produced a 442-line dossier anchored in 70+ sources and the USENIX Security 2024 SoK. Headline finding that reorders the angle's priorities: **circuit-layer bugs are 70% of all SNARK vulnerabilities, 96% of those under-constrained** (Chaliasos et al., n=141). The dossier surfaced 12 bug classes the angle did not cover; this release wires the in-scope ones into the methodology.

### Added — `references/research/README.md`

The research-dossier framework. Defines the dossier format (7 sections), the core discipline (extract methodology, not patterns), a 6-tier source taxonomy (post-mortems > audit reports > CVE databases > framework docs > academic > tooling — anchor in what actually broke), the anti-bloat gate from dossier to angle change, and the program order (ZK first as template, then the other 8 angles one at a time). Reusable backbone for grounding every angle in evidence.

### Added — `references/research/zk-circuit-research.md`

The ZK Circuit Soundness research dossier. 24-class bug taxonomy (C1–C24), each with a real instance and an Argus-coverage verdict; per-class discovery procedures ending in a mechanical falsification step; framework-specific knowledge (Halo2/circom/arkworks/plonky2/3/Noir assignment-vs-constraint operators); deterministic backend roster (Picus, circomspect, zkFuzz, Ecne, NAVe); discovery calibration; gaps→angle-change proposals; full source list. Anchored in real CVEs (CVE-2021-38194 arkworks `mul_by_inverse`, CVE-2025-52484 RISC Zero rv32im, CVE-2025-46723 OpenVM AUIPC, CVE-2024-45039 gnark fold-to-zero, FOOM VK degeneracy ~$1.8M, dusk-plonk unverified-evaluations ~$60M-class).

### Changed — `references/hacking-agents/infra/zk-circuit-soundness-agent.md`

- **Calibration headline** added at the top of "How to attack": under-constraint is the modal SNARK bug (96% of circuit bugs); these bugs survive audits + MockProver + happy-path tests; grep is a seed step, not the procedure.
- **Phase 1 step 0 added** — `cargo audit` pre-filter: run `cargo audit` (or `cargo deny check advisories`) before manual review; flag every advisory with "soundness", "under-constrained", "constraint", or "proof forgery" keywords. These name the exact file/function/version delta.
- **CHECK 1 generalized across frameworks.** Was Halo2-only (`assign_advice`). Now a per-framework assignment-only operator table (Halo2 / circom `<--` / arkworks `new_witness` / bellman `alloc` / plonky2 `set_target` / Noir `unsafe`+Brillig) plus the unifying Uniqueness Constraint Propagation (UCP) procedure.
- **CHECK 6 limb-loop binding sub-procedure added** — three-step independent procedure (index-domain re-derivation, residual-width binding, max-sum < modulus) for value decompositions where range-checking every limb is not sufficient. Catches the OpenVM CVE-2025-46723 `skip(1).enumerate()` class.
- **CHECK 7–14 added** (in-scope classes the angle missed): decorative gadget output, inverse/division/remainder degeneracy, host-assertion-not-constraint, instance-binding obligation, compute-constrain operand-set diff (TCCT), output uniqueness / two-witness, point-validity contract (on-curve+subgroup+identity), EC exceptional-case.
- **Phase 4.5 added** — proving-system verifier & setup-parameter soundness (CHECK 15–19: Fiat-Shamir transcript completeness/Frozen Heart, unverified prover evaluations, commitment fold-to-zero, PCS/FRI verifier checklist incl. Halo2 rotation-collision, VK/trusted-setup degeneracy). Scoped to forked/hand-rolled verifiers; skipped when only calling an unmodified upstream verifier.
- **CHECK 20 added** — zkVM operand/state aliasing case-matrix (`[zkVM only]`). DERIVE the partition from decoded-field equalities (not a memorized register list); constraint must pin the routed value in every partition cell. Covers CVE-2025-52484 ($50k bounty RISC Zero rv32im), SP1 `is_complete` (GHSA-c873-wfhp-wx5m), zkSync Era recursion/aggregation (~$1.9B surface).
- **CHECK 21 added** — over-constraint / honest-prover lockout. The dual of under-constraint: compute `SPEC \ CONSTRAINT`, invert the MockProver expectation (honest boundary witness must fail), severity = liveness/DoS (at most High). Covers RISC Zero `opLH` (Veridise VUL-005, High). zkFuzz found 258/452 circuits over-constrained.
- **MockProver discipline sharpened** — the two valid signals: forged witness passes → under-constraint CONFIRMED; honest boundary witness fails → over-constraint CONFIRMED. A green run on the honest witness is the most common false-negative trap in ZK auditing.
- **Framework dispatch decision rule** replaced the generic tool table. 7-framework dispatch table with primary tool + golden signature + fallback per framework. Explicitly flags the tool-coverage skew (Circom has Picus+circomspect+zkFuzz+Ecne; arkworks/plonky2-3/bellman have NO off-the-shelf under-constraint detector) and that manual UCP + hand-built two-witness PoC is the primary control for unsupported frameworks.
- **Stage-3 PoC table consolidated** — Tier-1-mock removed as a standalone tier; forged-witness MockProver is now a Tier-1-e2e confirmation path.
- **Anti-pattern corrected and expanded**: the prior "witness-gen panics → no finding" guidance was wrong — a host assertion is not a constraint; only in-circuit constraints count. Additionally, a host panic on an HONEST boundary-value input is an over-constraint liveness finding (CHECK 21).
- Coordination boundary with Crypto Soundness redrawn: Circuit Soundness now owns in-tree verifier/setup-parameter validation logic; Crypto Soundness owns the deployment-trust/integration view.

### Changed — `references/attack-vectors/dlt-infra-attack-vectors.md`

- Group J extended J10–J16: decorative gadget output, inverse/division degeneracy, host-assertion-not-constraint, instance-binding gap, output non-uniqueness/double-spend, point-validity gap, EC exceptional-case. 93 vectors total across Groups A–J (was 86).
- Note added that verifier/setup-parameter soundness lives as Angle 9 CHECK 15–19, not as Group J per-cell vectors.

### Changed — `references/hacking-agents/infra/arithmetic-agent.md`

Research-grounded depth pass — all 8 dossier proposals applied. 85 lines → 393 lines (+308). Changes:

- **Calibration headline** added — three damage classes (financial loss, chain halt/DoS, memory corruption) anchor the angle in real impact categories.
- **Phase 1 Clippy pre-seed** — `cargo clippy -- -W clippy::cast_possible_truncation -W clippy::cast_sign_loss -W clippy::cast_precision_loss -W clippy::cast_abs_to_unsigned` as seed list before manual analysis. Plus `cargo audit` pre-filter and profile check for `overflow-checks`.
- **Reorganized as 13 numbered CHECKs** — each with signal, step-by-step procedure, golden signature, and real-instance source:
  - CHECK 1 — `a*b/c` multiplication overflow before division (distinct from allocation overflow; financial loss impact, not memory safety)
  - CHECK 2 — Allocation-size overflow (`Vec::with_capacity` with computed capacity)
  - CHECK 3 — General overflow (fee, timestamp, amount — wrapping in release/BPF)
  - CHECK 4 — Subtraction underflow as guard bypass (Monero Oxide F-15 class; **two failure modes**: `a<b` wraparound AND `a==b` zero-result)
  - CHECK 5 — Cast loss (width-narrowing, sign-flip, **bridge-boundary narrowing** u256→u64 — the highest-impact cast class)
  - CHECK 6 — **Unwrapped checked arithmetic** (new class: `checked_*().unwrap()` panic-as-DoS / chain-halt; severity triage by caller context)
  - CHECK 7 — **Division rounding direction** (new class: remainder attribution, repeated-operation leakage, `div_ceil` vs truncating intent)
  - CHECK 8 — **Division by zero** (new procedure — was only an anti-pattern mention; now covers first-depositor zero-supply, CosmWasm `from_ratio` panic, Cosmos SDK `Quo` panic)
  - CHECK 9 — **Fixed-point precision loss** (new class: minimum-x threshold, multi-step chain reorder, accumulator drift, AMM convergence)
  - CHECK 10 — **Governance-parameter-driven overflow** (new class: substitute `type::MAX`, trace downstream; TRUSTED-ACTOR severity downgrade but governance CAN be wrong)
  - CHECK 11 — **Accumulated sum overflow** (new class: lifetime worst-case for monotonic state variables; `saturating_add` downstream audit)
  - CHECK 12 — Off-by-one bounds (existing; `n.div_ceil(2)` vs `(n/2)+1`, boundary tests)
  - CHECK 13 — **Cross-module type-width mismatch** (new class: type alias drift, consensus slot/epoch width mismatch across crate boundaries)
- **Framework-specific knowledge section** (Phase 4) — Solana/BPF (release wrapping, `overflow-checks = true`, Borsh deserialization), Cosmos SDK (`Coins.Add` internal panic, `sdk.Dec.Quo` on zero, IBC `sdk.Int`→u64 narrowing), CosmWasm (`Uint128` checked-by-default, `Decimal::from_ratio` panic, `Decimal` underflow traps), Substrate (`u128 Balance`, `u32 BlockNumber` wrapping), Move (abort-on-overflow → DoS, `as` aborts), General Rust (`usize` platform width, `Wrapping<T>`/`Saturating<T>` type-documented contracts).
- **Framework-specific PoC patterns** — CosmWasm inline `Uint128` test, Solana BPF proptest, Substrate `BlockNumber` proptest. Plus fallback chain: cargo-fuzz → proptest → manual boundary-value table.
- **Output schema extended** — `damage_class` (financial-loss|chain-halt|memory-corruption|value-leak|panic-dos), `check_number` (CHECK 1-13), `framework_note` (runtime-specific behavior enabling the bug).
- **Coordination map expanded** — Economic Design overlap (CHECK 10 governance params), Crypto Misuse bridge (precision loss → cryptographic accumulator invariant breaks).

### Added — `references/research/arithmetic-research.md`

The Arithmetic & Overflow research dossier. 12-class bug taxonomy (A1–A12) covering multiplication overflow before division, silent truncation on cross-chain width-narrowing casts, subtraction underflow as guard bypass, unwrapped checked arithmetic panics, division rounding toward zero value leaks, fixed-point precision loss, governance-parameter-driven overflow, accumulated sum overflow, and cross-module type-width mismatches. Each class has step-by-step detection procedures ending in a mechanical falsification step (Kani bounded model checking, cargo-fuzz, proptest, or Clippy `cast_possible_truncation`). Framework-specific knowledge for Solana/BPF (release-mode wrapping), Cosmos SDK (panicking `Coins.Add`), CosmWasm (`Uint128`/`Decimal` traps), Substrate (`u128 Balance`/`u32 BlockNumber`), and Move (abort-on-overflow → DoS). 8 methodology gaps identified → 8 proposed angle changes (extend C04 for bridge narrowing, new checks for `a*b/c` pattern, rounding direction, unwrapped checked arithmetic, governance-parameter overflow, accumulated sum overflow, division by zero, Clippy integration). Built from model knowledge only ([model-knowledge] tags throughout) — primary-source verification pass pending. 15 cited production bugs across ~20 sources (Tier 1 post-mortems through Tier 6 tooling).

### Changed — `references/research/RESEARCH-INDEX.md`

- Arithmetic (Angle 3) status updated from "Not started" to "In progress" with dossier file reference.

### Added — `references/research/logic-state-machine-research.md`

The Logic & State Machine Integrity research dossier. 13-class bug taxonomy (L1–L13) covering: partial-state write on error (multi-step writes with error paths between them), atomicity violations at domain boundaries (two subsystems each assuming the other enforces), epoch/slot boundary transition bugs (steady-state correct, transition wrong), re-entrant state via callback, silent error propagation beyond `let _ =` (.unwrap_or_default(), .ok()), TOCTOU across external boundaries, panic-in-critical-section poisoning, consensus round-transition misses (dead states, livelock), equivocation detection gaps (surround-vote, same-source, replay, race-condition), governance-proposal execution ordering (snapshot-vs-current parameter read), async-cancellation partial state, clock-dependence consensus splits, and delegated-execution atomicity (multi-hop error propagation). Framework-specific sections for Cosmos SDK (EndBlock atomic-ish semantics, module→module keeper calls, validator-set update one-block delay), Tendermint/CometBFT (round timeout races, equivocation evidence submission timing), Ethereum (epoch boundaries, LMD-GHOST client diversity, Engine API version mismatches), Solana (PoH tick drift, instruction atomicity limitations, runtime upgrade state migration), and Substrate (storage migration bugs, on_initialize/on_finalize cross-pallet ordering). Critical tooling gap documented: there is no off-the-shelf invariant discovery tool — the auditor must synthesize invariants before verification. 10 gaps identified → 10 proposed angle changes. ~20 cited production bugs across ~25 sources (Tier 1 post-mortems through Tier 6 tooling). Built from model knowledge ([model-knowledge] throughout) — primary-source verification pass pending.

### Changed — `references/research/RESEARCH-INDEX.md`

- Logic & State Machine (Angle 7) status updated from "Not started" to "In progress" with dossier file reference.

### Changed — `references/hacking-agents/infra/logic-state-machine-agent.md`

Research-grounded depth pass — all 10 dossier proposals applied. 96 lines → ~400 lines (+~304). Changes:

- **Calibration headline** added — logic/state bugs are the most common infra finding class AND the hardest to mechanize: no off-the-shelf invariant discovery tool (unlike Kani for arithmetic, MIRI for memory safety). Three sub-classes: partial-state write on error, atomicity violations at domain boundaries, epoch/slot boundary transition bugs.
- **Phase 1** — grep high-signal patterns (swallowed errors, `.unwrap_or_default()`, `.ok()` discard, `?` between writes); clock-read enumeration; epoch/slot boundary gating.
- **Reorganized as 13 numbered CHECKs** — each with signal, step-by-step procedure, golden signature, and source:
  - CHECK 1 — Partial-state write on error (multi-step writes with error paths between them; Cosmos SDK EndBlock panic-rollback semantics)
  - CHECK 2 — Atomicity violation at domain boundary (two subsystems each assuming the other enforces; bypass-caller search)
  - CHECK 3 — Epoch/slot boundary transition bug (steady-state vs transition logic; epoch 0→1 and MAX boundary tests; stateright model-check)
  - CHECK 4 — Silently swallowed result (G01 extended — `.unwrap_or_default()` as most dangerous variant, `.ok()` discard, severity triage by context)
  - CHECK 5 — Re-entrant state via callback (G03 — FFI/cross-contract CPI/async I/O during state mutation; synthetic re-entry test)
  - CHECK 6 — TOCTOU across external boundary (G06 — read→external call→use; Solana CPI call-back, CosmWasm WasmMsg::Execute re-entry)
  - CHECK 7 — Panic-in-critical-section poisoning (G02 — `.unwrap()`/`panic!` while holding Mutex; lock poisoning cascade)
  - CHECK 8 — Consensus round-transition completeness (dead-state/livelock detection, timeout path verification; stateright liveness counterexample)
  - CHECK 9 — Equivocation detection gap (surround-vote, same-source different-target, duplicate via gossip race, replay from past epoch, evidence submission timing race)
  - CHECK 10 — Governance-proposal execution ordering (snapshot vs current-value parameter read; mid-operation governance change; TRUSTED-ACTOR downgrade)
  - CHECK 11 — Clock-dependence consensus split (G07 extended — timeout skew, block timestamp trust, Solana PoH tick drift)
  - CHECK 12 — Delegated-execution atomicity (multi-hop error propagation; generic-wrapping, silent-success, IBC packet ack error swallowing)
  - CHECK 13 — Match-arm early return without invariant restoration (G04 — early return in match arm with partial state mutation)
- **Phase 4 framework-specific knowledge** — Cosmos SDK (EndBlock atomic-ish, module→module Keeper calls, governance parameter immediate effect, validator-set one-block delay); Tendermint/CometBFT (round timeout monotonic advancement, equivocation evidence timing race, BFT-time block timestamps); Ethereum (slot/epoch boundaries, LMD-GHOST client diversity, Engine API version mismatch); Solana (PoH ticks, instruction atomicity limitation, runtime upgrade state migration); Substrate (runtime upgrades with storage migrations, on_initialize/on_finalize per-pallet ordering, BlockNumber u32 wrapping).
- **Stage-3 PoC discipline** — Stateright model checking for consensus properties (gold standard), proptest state-machine fuzzing (fallback), framework-specific patterns (TOCTOU/async-cancellation synthetic interleaving, error propagation injection test, equivocation surround-vote test), error-injection harness template.
- **Output schema extended** — `state_invariant`, `violation_sequence`, `check_number`, `verification_class` (model-check|property-fuzz|manual-trace|error-injection|none), `golden_signature`, `framework_note`.
- **Anti-patterns extended** — doc-unreachable match arms with `unreachable!()` guards, test-only races, async-cancellation where no runtime cancels, generic "could go wrong" without concrete sequence, functions with explicit rollback (`mem::replace`, `Drop` cleanup).

### Added — `references/research/crypto-misuse-research.md`

The Crypto & Secrets Management research dossier. 13-class bug taxonomy (C1–C13) covering: nonce/k reuse (ECDSA k-reuse → private key recovery; AES-GCM nonce reuse → ciphertext forgery), weak/predictable RNG (WASM fallback to seedable PRNG, no_std `OsRng` unavailability), non-constant-time comparison (memcmp on secrets → timing leak), missing zeroisation (key material in memory post-drop), weak hash for security purpose (MD5/SHA-1 collision), missing curve-point validation (on-curve + subgroup + not-identity — three checks per curve type), signature malleability (ECDSA low-S, EIP-2/BIP-62 context), BLS rogue-key attack (missing proof-of-possession), side-channel via early-exit verification (timing leak from early-return in verify()), Ed25519 cofactor/small-subgroup (cofactor 8 multiplication, verify vs verify_strict), Merkle proof verification gap (root comparison, leaf preimage, path length, empty-proof bypass). Framework-specific sections for Cosmos SDK/IBC (ICS-23 Dragonberry, BLS subgroup check, SDK PrivKey zeroisation), Tendermint/CometBFT (ed25519-consensus, ics23 version check), Ethereum (BLS12-381 validator sigs, ECDSA tx sig low-S, Keccak256 vs SHA3, EIP-155 replay), Solana (ed25519 strict syscall guarantee, secp256k1 syscall low-S, BPF zeroisation gap), Substrate (sr25519 deterministic nonce, ed25519 Grandpa finality, BLS BEEFY PoP, sp_core::Pair zeroisation), CosmWasm (cosmwasm-crypto thin wrappers, WASM no-OS-entropy RNG gap). 7 gaps identified → 7 proposed angle changes (per-curve point validation table, signature malleability details, BLS PoP verification gap, side-channel early-exit procedure, Ed25519 cofactor check, Merkle proof verification, Phase 1 pre-seed cargo audit). ~15 cited production bugs across ~20 sources. All [model-knowledge] — primary-source verification pass pending.

### Changed — `references/research/RESEARCH-INDEX.md`

- Crypto Misuse (Angle 5) status updated from "Not started" to "In progress" with dossier file reference.
- Logic & State Machine (Angle 7) agent-update date added (2026-06-05, 96→~400 lines, 13 CHECKs).

### Changed — `references/hacking-agents/infra/crypto-misuse-agent.md`

Research-grounded depth pass — all 7 dossier proposals applied. 77 lines → ~470 lines (+~393). Changes:

- **Calibration headline** added — three damage classes (private key extraction, asset loss via forgery, silent security degradation). Anchor case: Android `SecureRandom` unseeded → Bitcoin wallets drained (2013).
- **Phase 1 pre-seed** — `cargo audit` pre-filter (flag advisories with crypto/signature/RNG/hash/timing keywords); 8 high-signal grep patterns (RNG in key-gen, weak hash, non-ct comparison, curve deserialization, missing Zeroize, hand-rolled crypto, BLS aggregation without PoP, Merkle proof verification); dependency version check for crypto crates.
- **Reorganized as 11 numbered CHECKs** — each with signal, step-by-step procedure, golden signature, and source:
  - CHECK 1 — Weak/predictable RNG (E01 — `thread_rng` in WASM/no_std, constant-seed PRNG, CosmWasm no-OS-entropy; severity triage: Linux=Info, WASM=High, constant-seed=Critical)
  - CHECK 2 — Non-constant-time comparison (E02 — `==` on `[u8]` secrets, `hmac.verify().is_ok()`, framework equivalents; `dudect` for confirmation)
  - CHECK 3 — Missing zeroisation (E03 — secret-holding type enumeration, mnemonic phrase copies, stack vs heap, Solana BPF `zeroize` no-op risk)
  - CHECK 4 — Weak hash for security (E04 — MD5/SHA-1 use-case triage; SHA-1 safe for HMAC, unsafe for signatures; Ethereum Keccak256 vs SHA3-256 distinction)
  - CHECK 5 — Nonce/k reuse (E05 — RFC 6979 determinism check for ECDSA, AES-GCM lifetime uniqueness, Ed25519/sr25519 deterministic nonce verification, proptest 10k-signature r-value collision check)
  - CHECK 6 — Missing curve-point validation (E06 extended — **three-check table**: on-curve + subgroup + not-identity; **per-curve reference table** for Ed25519/curve25519, secp256k1, BLS12-381 with exact API methods; constant-point typo check)
  - CHECK 7 — Side-channel via early-exit (E08 extended — **grep `return false` mid-verify** before running `dudect`; per-primitive early-return enumeration: ECDSA r/s range checks, Ed25519 R decompress, HMAC tag comparison; Thorough mode only for `dudect`)
  - CHECK 8 — Signature malleability (V27 expanded — low-S rule enforcement; framework compliance table: `libsecp256k1`/`k256`/`secp256k1` crate; EIP-2/BIP-62 context; Ed25519 non-malleability; m-of-n multisig txid mutation)
  - CHECK 9 — BLS rogue-key attack / missing PoP (NEW — attacker key-derivation algebra: `PK_a = g^a / PK_h`; defense via `pop_verify` on each key; Ethereum 2.0 deposit contract PoP, Substrate BEEFY session key PoP, Cosmos SDK BLS key registration)
  - CHECK 10 — Ed25519 cofactor / small-subgroup (NEW — cofactor 8 handling; `verify()` vs `verify_strict()` distinction; Monero key-image small-subgroup bypass; Solana syscall guarantee vs BPF hand-rolled risk; Cosmos/Tendermint `ed25519-consensus` verification)
  - CHECK 11 — Merkle proof verification gap (NEW — **five minimum checks**: root comparison, leaf preimage binding, path length, hash consistency, empty-proof bypass; ICS-23 Dragonberry subkey verification; hand-rolled verifier = High severity)
- **Phase 4 framework-specific knowledge** — Cosmos SDK/IBC (BLS subgroup check, ICS-23 mandatory, PrivKey zeroisation); Tendermint/CometBFT (ed25519-consensus for consensus votes, ics23 version check); Ethereum (BLS12-381 blst/milagro, ecrecover vs EIP-2 low-S, Keccak256 vs SHA3, EIP-155 replay); Solana (ed25519 syscall strict guarantee, secp256k1 syscall low-S, BPF zeroisation gap); Substrate (sr25519 deterministic nonce, ed25519 Grandpa verify_strict, BLS BEEFY PoP, sp_core::Pair zeroisation); CosmWasm (cosmwasm-crypto thin wrappers, WASM no-OS-entropy RNG gap).
- **Stage-3 PoC discipline** — 4-tier ladder (Tier-1-fuzz: nonce reuse 10k signatures, malleability (r,n−s) re-verify, empty-proof bypass; Tier-2-prop: dudect timing measurement; Tier-3-unit: predict RNG output, MIRI zeroisation, hash collision citation; Tier-4-derivation: mathematical argument). Templates for nonce reuse fuzz, malleability test, curve point validation test, empty Merkle proof bypass test.
- **Anti-patterns expanded** — `thread_rng()` on standard Linux/Mac is NOT a finding (Chacha12 CSPRNG); Ed25519 `verify()` (not `verify_strict()`) is safe (multiplies by cofactor); generic "this hash might be weak" without specific attack and compute cost.
- **Coordination map expanded** — Arithmetic bridge (key-derivation overflow), Signature Verification angle boundary (application-level vs primitive-level).

## [0.6.1] — 2026-06-05

**ZK Circuit Soundness angle + Group J attack vectors.** Inspired by the Zcash Orchard counterfeiting vulnerability (Zooko Wilcox / Taylor Hornby, May 2026) — an under-constrained EC multiplication in the Orchard circuit that evaded ~4 years of cryptographer scrutiny. Argus now has a dedicated infra-mode angle for circuit-internal constraint completeness, separate from the integration-level ZK checks in the Crypto Soundness angle and the primitive-level misuse checks in the Crypto Misuse angle.

### Added — `references/hacking-agents/infra/zk-circuit-soundness-agent.md`

Infra-mode Angle 9. Prover-side ZK circuit soundness methodology. Five-phase analysis: (1) circuit inventory — enumerate every chip/gadget, advice/witness column, and constraint graph, (2) per-cell constraint completeness — CHECK 1 (computed vs assigned), CHECK 2 (constrained, complete, non-substitutable), CHECK 3 (conditional constraint gaps), (3) cross-chip composition — shared-cell constraint coverage in both chips, (4) witness generation audit — determinism, input validation, column assignment completeness, (5) E2E exploit construction — modified witness + full proof generation + verification succeeds with false input = mechanical proof. PoC tier ladder: Tier-1-e2e (proof verifies with false input) / Tier-1-mock (MockProver accepts challenger witness) / Tier-2-prop (proptest over witness columns) / Tier-3-unit (documented gap with code citations) / Tier-4-derivation (mathematical argument). Anti-patterns section excludes: constrained-but-could-be-differently, performance observations, panic-on-invalid-witness, complexity-is-hard-to-audit, phantom field overflow. Coordination map: Crypto Soundness owns integration-level ZK bugs; Crypto Misuse owns primitive misuse around circuits; Logic & State Machine owns cross-circuit invariants. Lead Hunter strategy is RECOMMENDED pairing. Dispatched with `model="opus"` when `INNOV=HIGH` and ZK circuits detected.

**Concrete detection signatures** (backfilled from Taylor Hornby's Orchard work log, `vul.md`):
- The `assign_advice` vs `copy_advice` pattern — Halo2's `assign_advice` creates no constraint; `copy_advice` does. CHECK 1 now includes a grep recipe for every `assign_advice` call per chip file.
- Loop internal-consistency trap — the exact Orchard pattern: first iteration `assign_advice`, subsequent iterations constrained by `q_mul_2` to equal it. Loop is internally consistent but externally unbound.
- Detection recipe: for every `assign_advice` in a loop's first iteration, verify a constraint (gate or copy-constraint) straps it to the actual input value.
- Discovery difficulty calibration: Opus 4.8 found the bug in 1/4 generic runs, 100% with systematic enumeration. Opus 4.7 needed specific direction. Model skepticism is high — instruct agents to trust MockProver results over "well-audited code" priors.
- Four operational rules for the orchestrator: (1) systematic enumeration beats generic prompting, (2) feed framework documentation (Halo2 book) into circuit inventory, (3) trust mechanical evidence over model priors, (4) loop patterns are the single highest-ROI check.

### Added — Group J vectors in `references/attack-vectors/dlt-infra-attack-vectors.md`

Nine new ZK Circuit Soundness vectors (J01–J09): under-constrained EC multiplication input, unconstrained witness cell, missing range check, missing boolean check, non-canonical encoding under-constraint, custom gate constraint incompleteness, lookup argument selector gap, copy-constraint / permutation gap, selector condition incompleteness. All use MockProver + modified witness as detection tool; golden signature is `MockProver` reporting 0 failing constraints with a challenger witness. 86 vectors total across Groups A–J (was 77 across A–I).

### Changed — `references/dlt-infra-types.md`

- New component type "ZK proof circuit" added: detection signals (halo2_proofs, ark-relations, bellpepper, plonky2; `Circuit` trait, `Chip` structs, `configure()` custom gates; files in `circuits/`, `gadgets/`, `chips/`, `constraints/`).
- Threat profile added for ZK proof circuit: 4 primary adversaries (malicious prover, circuit-author error, cross-chip composition gap, spec-to-circuit drift), 7 dominant attack patterns, 5 critical invariants, 5 what-to-look-for-first items.
- Canonical example: Zcash Orchard circuit vulnerability (May 2022–June 2026).
- Cross-component boundaries added: Circuit → Crypto, Circuit → Wallet, Circuit → Bridge.

### Changed — `references/hacking-agents/crypto-soundness-agent.md`

- ZK integrations section now has an integration-level-only disclaimer. The "Unused witness variables" bullet removed (it was one sentence covering a 9-vector group that now has a dedicated angle). New pointer to the ZK Circuit Soundness angle for circuit-internal constraint soundness, with the Orchard example.

### Changed — `references/hacking-agents/infra/crypto-misuse-agent.md`

- Domain boundary added: ZK circuit constraint soundness (Group J) is explicitly NOT this angle's domain. Coordination section updated with ZK Circuit Soundness (Angle 9) entry — Angle 5 owns Rust code around circuit; Angle 9 owns constraint system internals.

### Changed — `SKILL.md`

- Angle dispatch table: ZK Circuit Soundness angle added (infra mode only, Group J, opus when INNOV=HIGH).
- Angle count updated: "up to 13 angles" (was 12).
- Infra mode description: ZK proof circuits added to target list; MockProver added to verification backends.
- Infra references: 9 Stage-2 angles (was 8), 86 vectors across Groups A–J (was 77 across A–I).

### Changed — `references/audit-modes.md`

- Stage-2 angle set table: ZK Circuit Soundness added to infra column with version tag.
- Strategy routing table: Digger infra angles updated to 9 (was 8).
- Stage 2 mode-specific routing: zk-circuit-soundness added to infra file list.
- Verification backends: MockProver added to deterministic verification backend list.

### Changed — `references/signal-assessment.md`

- Innovation signal: ZK proving system / circuit definitions explicitly called out with trigger note (ZK Circuit Soundness angle + Lead Hunter recommendation).
- Strategy selection table: new row for VERY-HIGH/HIGH + ZK circuits → Digger + ZK Circuit Soundness angle.

### Added — `references/research/` (research dossier infrastructure)

Every angle's methodology should trace to real production vulnerabilities, published audit taxonomies, and academic results — not first-principles intuition. The research directory holds evidence dossiers that compile known findings, taxonomies, tooling, papers, and audit reports per angle.

- `references/research/zk-circuit-research.md` — ZK Circuit Soundness evidence base. 10-class constraint completeness taxonomy (CC-1 through CC-10) derived from the Orchard post-mortem + public ZK security literature. Maps every agent CHECK to the specific finding(s) that justify it. Tracks known ZK security research organizations (Trail of Bits, Veridise, ingonyama), tooling landscape (MockProver, Circomspect, Ecne, Picus, Coda), public audit reports, and gaps in current methodology. `[INCOMPLETE]` tags mark unverified claims pending primary source retrieval.
- `references/research/RESEARCH-INDEX.md` — tracks which angles have research dossiers and which still rely on intuition. Defines the dossier template (9 sections), sourcing rules, and recommended build order across all 19 angles.

### Changed — `references/attack-vectors/dlt-infra-attack-vectors.md`

- J01 vector: now includes concrete code citation (`halo2_gadgets/src/ecc/chip/mul/incomplete.rs:309-310`), the exploit algebra (`P = [ivk⁻¹]pk_d`), and the co-constraint that failed (`q_mul_2` enforces loop-internal consistency only).

## [0.6.0] — 2026-06-04

**Hunting strategy system + signal assessment.** Methodology restructuring based on the WhiteHatMage bug hunting guide. Introduces four hunting strategies (Digger, Speedrunner, Watchman, Differ) selected by codebase signal assessment (Complexity, Innovation, Optimization, Code Quality). Adds the Differ angle for cross-project comparison against reference implementations.

### Added — `references/signal-assessment.md`

Stage 0.5 reference. Extracts four bug-density signals from the codebase — Complexity (nSLOC, crate count, multi-component, external integrations), Innovation (novel consensus, ZK, custom crypto, no prior art), Optimization (unsafe density, inline assembly, manual memory, SIMD), Code Quality / Audit History (comments, naming, test coverage, Clippy, prior audits). Each signal scored LOW/MEDIUM/HIGH with a weighted composite formula (CMPLX×0.40 + INNOV×0.30 + OPT×0.15 + QUAL×0.15). Auto-detects temporal signals (project age, days since last upgrade, fork ancestry) and selects a hunting strategy. Defines the revisit advantage (>180 days since last audit → surface prior findings for reconsideration).

### Added — `references/hunting-strategies.md`

Strategy overview referencing the WhiteHatMage guide's seven hunter archetypes. Defines four strategies — Digger (full pipeline, default), Speedrunner (quick triage, 4 angles, Tier-2 PoC, Pass A only), Watchman (diff-aware, changed paths only), Differ (reference comparison). Each strategy modifies the pipeline's behavior: which angles run, how deep Stage 1 goes, what PoC tier is accepted, how Stage 4 adversarial review operates. Strategies are orthogonal to `smart-contract`/`infra` audit modes — any strategy works in either mode. Includes strategy supplements that run alongside the primary strategy (Differ + Watchman can supplement Digger).

### Added — `references/strategies/speedrunner.md`

Speedrunner strategy methodology. For fresh launches (< 30 days) or low-signal targets. Reduces Stage 1 to 4 surface points (access control, input validation, authentication, authorization). Reduces Stage 2 to 4 angles (Auth, Vector Scan, Execution Trace, First Principles). Relaxes PoC floor to Tier-2 acceptable. Reduces Stage 4 to Pass A only. Expected wall time: ~25% of Digger. Documents when Speedrunner is the wrong choice (high bug-density, fork ancestry, explicit comprehensive audit request).

### Added — `references/strategies/watchman.md`

Watchman strategy methodology. For recent upgrades (< 14 days) or user-supplied prior commit. Computes structural diff between prior and current commit. Classifies changes (SIGNATURE_CHANGE, LOGIC_CHANGE, CONST_CHANGE, TYPE_CHANGE, DEP_CHANGE, REMOVED). Identifies diff-specific bug classes (regression, assumption break, type width mismatch, new unchecked path, dependency drift, dead code newly alive, side-effect addition). Scopes Stage 2 to changed paths only. When prior Argus run exists at the prior commit, cross-references prior findings against the diff. Expected wall time: ~35% of Digger.

### Added — `references/strategies/differ.md`

Differ strategy methodology. For targets with known fork ancestry or user-supplied reference. Clones reference repo at fork-point commit. Builds module correspondence map (target file → reference file with structural similarity scores). Identifies deviations (missing checks, divergent constants, ordering changes, removed error cases, type narrowing, doc comment rot, missing dependency features, untested adaptations). Classifies deviations as CONTEXT_LOSS (bug), INTENTIONAL (adaptation), UNCLEAR (needs review), or INHERITED_BUG (predates fork). Expected wall time: ~130% of Digger due to reference fetch + comparison.

### Added — `references/hacking-agents/differ-agent.md`

New Stage 2 angle (angle #12). Dispatched when Differ strategy is active. Four-phase methodology: (1) build module correspondence map with structural similarity scoring, (2) structural deviation scan (type, function, constant, error handling, control flow deviations), (3) context-loss assessment with 4-point checklist, (4) DIFF-FINDING production. Produces findings with dual code citations (target location + reference location). Kill criteria: similarity < 0.3, clearly intentional deviation, reference code unreachable in fork context.

### Added — `references/strategies/depth-first-critical-path.md`

(EXPERIMENTAL) Design reference for depth-first critical path mode — the WhiteHatMage guide's core methodology of obsessing over one execution path at a time. Inverts Argus's breadth-first architecture: instead of 8 parallel angles, one deep agent traces a single critical path exhaustively. Documents when to use (limited time budget, dominant user flow, revisiting prior audit) and limitations (blind to secondary paths).

### Added — `references/strategies/lead-hunter.md`

Lead Hunter strategy methodology. For very-high bug density targets with novel consensus/crypto/VM subsystems. Selects ONE subsystem, builds an exhaustive assumption map (6 dimensions per state-changing function), violates each assumption systematically, classifies terminal outcomes (EXPLOITABLE / NOVEL_CLASS / KNOWN_CLASS / DEGRADATION / COSMETIC / SAFE), and generalizes novel classes into reusable detection patterns. Produces findings with `strategy: lead-hunter` and `novel-class: true` metadata. If a genuinely new vulnerability class is discovered, proposes it as a new attack vector candidate (V133+). Pairs with Scientist for custom tooling amplification. Documents when Lead Hunter is the right choice (novel subsystem, deep Rust expertise, Scientist partner, mature/well-audited target) and wrong choice (standard commodity programs, limited time, reliable findings wanted over novel discovery).

### Added — `references/strategies/scientist.md`

Scientist strategy methodology. For very-high bug density + high optimization signal targets (unsafe >5%, inline assembly, SIMD). Assesses tooling ROI pre-Stage 1: identifies the target's unique properties that off-the-shelf tools cannot verify, then builds custom verification harnesses (fuzz harness, Kani proof, Clippy/dylint lint, Miri test, proptest, semgrep pattern). Cap: 3 tools per run. Tool-found findings enter Stage 2 with `evidence: [SCIENTIST-TOOL]` metadata — stronger than manual review, weaker than Tier-1 E2E PoC. Custom tools that pass cleanly are candidates for CI integration. Documents tool type catalogue with effort estimates, when each is appropriate, and templates for each tool type. Pairs with Lead Hunter.

### Added — `references/deployed-code-verification.md`

Stage 1 supplement (v0.6.0). Verifies that repository source code matches what is actually deployed on-chain. Prevents dead-code audits (repo ahead of deployed) and proxy-behind-implementation divergence. Per-chain procedures for Solana (program dump + hash comparison), CosmWasm (code ID query + wasm hash), Substrate (runtime Blake2-256 hash), and generic Rust services (git tag comparison). Mismatch classification: STALE_REPO (repo newer than deployed), PROXY_DIVERGENCE (proxy points at old implementation), PROGRAM_CLOSED (Solana program halted — CRITICAL, halts pipeline), UNVERIFIED (RPC unavailable, build non-deterministic). Audit impact: STALE_REPO → scope excludes post-deployment changes; UNVERIFIED → all findings flagged with `deployed-code: UNVERIFIED`.

### Added — `references/pre-hunt-vetting.md`

Stage 0 supplement (v0.6.0). Assesses whether a bounty program is worth the audit investment before the pipeline commits budget. Evaluates P(fair treatment) — the third term in the WhiteHatMage guide's ROI equation that Argus previously had no check for. Five signals: REP (program reputation, payout history, dispute record), SCOPE (clarity, on-chain identifiers, stability), PAY (published severity-to-payout table, minimum payouts), EST (trust establishment, post-mortems, security culture), TRES (treasury sustainability, runway). Composite score: REP×0.35 + SCOPE×0.25 + PAY×0.20 + EST×0.15 + TRES×0.05. GREEN (≥2.5) → proceed; YELLOW (1.8-2.4) → proceed with "test the waters" recommendation; RED (<1.8) → AskUserQuestion to confirm. Defines 9 red flag categories (NO_PAYOUT_HISTORY, DISPUTE_HISTORY, SCOPE_UNCLEAR, etc.). Recommends the guide's strategy: find one small bug first, observe the process, then commit.

### Changed — `SKILL.md`
- Added Lead Hunter and Scientist to strategy table with "explicit trigger only" note
- Added `pre-hunt-vetting.md` reference to Stage 0 routing
- Added `deployed-code-verification.md` reference to Stage 1 routing

### Changed — `references/pipeline-overview.md`

- Stage 0.5 contract added (between Stage 0 and Stage 1) with INPUT/OPERATIONS/OUTPUT/VERDICT/EXIT CONDITION
- Stage 0: pre-hunt-vetting supplement note added beneath cost preview section
- Stage 1: deployed-code-verification supplement note added beneath protocol mapping contract

### Changed — `references/audit-modes.md`

- "Strategy routing" section added. Strategy routing table maps each strategy to its pipeline modifications (Stage 1, Stage 2 angles, Stage 3 PoC floor, Stage 4).
- Lead Hunter and Scientist strategies added to routing table (explicit trigger only)
- Updated "What does NOT belong" to include per-strategy methodology

### Changed — `references/hunting-strategies.md`

- Advanced strategies section added with Lead Hunter and Scientist (explicit trigger only)
- Updated "What this file does NOT cover" to reference `lead-hunter` and `scientist`

## [0.5.0] — 2026-05-17

**Resumable pipeline + Codex runtime tool-translation driver.** Every Argus run now writes a checkpoint manifest at `$RUN_DIR/_manifest.json` after each stage. A run that crashes / times out / hits a subscription window / gets user-cancelled can be resumed from the last completed checkpoint via `/argus-resume <run-dir>` (Claude Code) or `python3 scripts/argus_resume.py <run-dir>` (platform-agnostic). Codex CLI runtime support is now backed by a concrete shim script (`scripts/codex_driver.py`) providing CLI commands for the four Claude-only tools (`AskUserQuestion`, `TodoWrite`, `WebFetch`, checkpoint manifest writes).

### Added — `references/checkpoint-protocol.md`

Defines the canonical manifest schema (`stages[]` append-only, write-rename atomicity, per-stage `status: in-progress | completed | failed | skipped`, token estimate-vs-actual tracking, partial-completion records for Stage 2 parallel angles and Stages 3-8 per-finding work). Documents the per-stage write protocol (start → end → resume_hint) and cross-platform resume semantics (a Claude-started run can be resumed on Codex, and vice versa, when both have access to the same `$RUN_DIR`).

### Added — `scripts/codex_driver.py`

Runtime tool-translation shim. Five subcommands:

| Subcommand | Replaces |
|------------|----------|
| `detect-platform` | Reports `claude` / `codex` / `unknown` from env markers |
| `ask` | `AskUserQuestion` — writes Q to `_pending_question.md`, polls `_pending_answer.md` (or `--no-wait` for fire-and-forget) |
| `todo` | `TodoWrite` — markdown checklist at `_todos.md` with `--add` / `--start` / `--done` / `--list` |
| `fetch` | `WebFetch` — curl + cache (`_fetch_cache/`) with graceful fallback to `_unfetched_urls.txt` when no network |
| `manifest` | Checkpoint-manifest writer/reader — `--init` / `--start-stage` / `--end-stage` / `--read` / `--resume-hint` |

The driver works on **both** platforms — under Claude Code it's an optional fallback; under Codex it's the runtime backing for the four tool-translation operations.

### Added — `scripts/argus_resume.py`

Reads `$RUN_DIR/_manifest.json` and reports the resume plan:

- Completed stages with timestamps + token costs.
- The next stage to start (with reason: next-after-completed / resume-in-progress / retry-failed).
- Per-stage partial-completion info (Stage 2 parallel-angles status; Stages 3-8 per-finding verdict files).
- Validation issues (missing output files, manifest inconsistencies, chronological violations).

Three modes: human-readable plan (default), `--validate` (issues-only stderr + exit 0/2), `--json` (machine-readable for orchestrators).

### Added — `commands/argus-resume.md` (slash command)

`/argus-resume <run-dir>` invokes `argus_resume.py` and asks the user via `AskUserQuestion`:

- Resume from Stage N (the resume_point)
- Re-run from Stage N (discard partial Stage-N work)
- Abort

Validation-issue path adds a "proceed anyway / repair / abort" choice.

### Added — `assets/codex-tool-map.example.json`

Machine-readable translation map for the platform-detection + per-tool fallback protocols. Each tool entry documents:

- Native availability on each platform.
- Codex shim name + fallback-protocol text (the same wording the driver implements).
- Which Argus stages use it.

Plus a `stage_invariants` block listing required tools + must-write files per stage.

### Changed — `references/pipeline-overview.md`

Stage 0 contract now mandates manifest bootstrap (`codex_driver.py manifest --init`) AND a Stage-0-completion entry. A new "Per-stage manifest discipline" subsection documents the start-stage / end-stage / failure-end pattern every subsequent stage must follow.

### Changed — `references/codex-compat.md`

The conceptual translation table now points at `codex_driver.py` for runtime backing. Added v0.5.0 sections describing the driver subcommands and the resumable-pipeline workflow.

### Changed — `install.sh`

Slash-command installer now copies `argus-resume.md` alongside `argus`, `argus-fix-verify`, and `argus-doctor`. Greeting message reflects the four available commands.

### Changed — `scripts/doctor.sh`

`REQUIRED_REFS` adds `references/checkpoint-protocol.md`. `REQUIRED_SCRIPTS` adds `scripts/codex_driver.py` and `scripts/argus_resume.py`. Python parse-check loop covers both new scripts.

### Migration notes

- v0.4.2 → v0.5.0 is backward-compatible for runs that don't use the manifest: stages can continue to write outputs without invoking `codex_driver.py manifest`. Such runs lose resumability but still produce valid findings.
- Runs that DO use the manifest gain `/argus-resume` and Stage 8's estimate-vs-actual cost reconciliation; the manifest is opt-in for v0.5.0 and becomes mandatory at v0.6.0 (planned).
- A v0.4.x `$RUN_DIR` without a manifest cannot be resumed via `/argus-resume`; it must be re-run.

## [0.4.2] — 2026-05-17

**Operational skill library for Anchor / Solana / Rust-BPF surfaces.** A new `references/skills/` directory introduces six step-by-step audit procedures that each Stage 2 angle loads when Stage 1's `attack-surface.md` flags the matching surface. Skills sit one level above the vector catalogue: a vector is a single failure pattern; a skill is a multi-step audit procedure for a surface that touches multiple vectors and multiple angles.

### Added — `references/skills/` (6 skill files + README)

| Skill | Loads when | Loaded by |
|-------|-----------|-----------|
| [`anchor-account-validation.md`](references/skills/anchor-account-validation.md) | `Anchor.toml` present or `#[derive(Accounts)]` in source | Auth/Account, Vector Scan, First Principles |
| [`anchor-cpi-safety.md`](references/skills/anchor-cpi-safety.md) | Any `CpiContext` / `invoke` / `invoke_signed` call site | Periphery, Execution Trace, Auth/Account |
| [`pda-seed-space.md`](references/skills/pda-seed-space.md) | Any `find_program_address` / `create_program_address` / Anchor `seeds = [..]` | Auth/Account, First Principles |
| [`spl-token-2022-extensions.md`](references/skills/spl-token-2022-extensions.md) | Project imports `spl-token-2022` or uses Token-2022 mints | Periphery, Economic, Invariant |
| [`solana-sysvars-and-clock.md`](references/skills/solana-sysvars-and-clock.md) | Any `Clock::get` / `Sysvar` / `recent_blockhashes` / `instructions` sysvar reference | Execution Trace, Math Precision, Invariant |
| [`rust-panics-in-bpf.md`](references/skills/rust-panics-in-bpf.md) | Every Anchor / Solana-native program (panic = transaction abort = DoS) | Vector Scan, Math Precision, infra Resource-Exhaustion |

Each skill follows a uniform template: 1-paragraph surface description, load trigger, step-by-step audit procedure (6–8 numbered steps), per-step finding/non-finding distinctions, comparator citations for the `comparator_citation` FINDING field, and a "common false-positive shapes" section.

### Changed — `references/hacking-agents/*-agent.md` (all 8 SC-mode angles)

Each SC angle (vector-scan, auth-account, periphery, math-precision, execution-trace, invariant, economic-security, first-principles) gained a one-line load directive pointing at `references/skills/README.md`. Angles consult the skills index and load the matching skill(s) for any surface Stage 1 flagged.

### Changed — `install.sh`

`mkdir -p` now includes `$SKILLS_DIR/references/skills`; new `cp references/skills/*.md` line copies the skill files to both Claude and Codex install targets.

### Changed — `scripts/doctor.sh`

`REQUIRED_REFS` array extended with `references/scip-callgraph.md` (carried over from v0.4.1 doc) and all 7 new skill files (`README.md` + 6 skills). Doctor reports 37 pass when all skills are present.

### Migration notes

- v0.4.1 → v0.4.2 is fully backward-compatible. SC-mode angles that don't yet read the `**Load also**` directive continue to work; they just don't pull in the deeper per-surface audit procedure.
- The skills directory is **additive**: it does not change the FINDING schema or any existing rule. Findings produced with skill-loading are richer (cite the skill's comparator and false-positive analysis); findings produced without skill-loading remain valid.

## [0.4.1] — 2026-05-17

**Semantic callgraph from SCIP — closes the `[CODE-TRACE]`-only floor for HIGH/CRITICAL infra findings.** A new `scripts/build-callgraph.sh` drives `rust-analyzer scip` (or `scip-rust`) over a Rust workspace and produces the JSON callgraph that `scripts/reachability.py` consumes. When this script is the callgraph source, downstream reachability verdicts carry `evidence_tag_eligibility: [LSP-TRACE]` instead of `[CODE-TRACE]`, satisfying the Phase 1.2 evidence rule (`[CODE-TRACE]` alone insufficient for HIGH/CRITICAL infra). Graceful fallback when no SCIP indexer is installed.

### Added — `scripts/scip_to_callgraph.py`

Hand-rolled minimal SCIP protobuf parser (zero pip dependencies). Reads an `index.scip` file produced by `rust-analyzer scip` or `scip-rust`, and emits the JSON callgraph format `reachability.py` already consumes.

Key features:

- **No external Python dependencies** (no `pip install protobuf` required). Parses the protobuf wire format directly for the subset of fields Argus needs.
- **rust-analyzer-specific quirks handled**: Document field numbers (relative_path=1, occurrences=2, symbols=3, language=4) differ from the public scip.proto; the converter trusts the bytes the dominant indexer actually emits.
- **Function detection via SCIP symbol grammar** (suffix `(...)` or `().` for functions, `#` for types/traits) rather than the unreliable `SymbolKind` enum field, which drifts across proto versions.
- **Trait-impl edges synthesized** from rust-analyzer's `impl#[Type][Trait]method()` symbol-shape pattern, even when `SymbolInformation.relationships` is empty (rust-analyzer 1.95 emits the pattern but not the relationship).
- **Test-only detection** via two paths: filesystem-path heuristic (`tests/`, `_test.rs`) plus SCIP-symbol-path inspection for `#[cfg(test)] mod tests` blocks living in `src/lib.rs`.
- **External-symbol warnings**: references to symbols outside the indexed workspace (`std::*`, external crates) are logged and dropped from the callgraph, surfacing the boundary explicitly.

### Added — `scripts/build-callgraph.sh`

End-to-end wrapper that:

1. Detects available SCIP indexer (`rust-analyzer scip` or `scip-rust index`; `--auto` tries both).
2. Runs the indexer over the project, writing a temporary `index.scip`.
3. Invokes `scip_to_callgraph.py` to convert to the JSON callgraph.
4. Cleans up the temp file (unless `--keep-scip`).
5. Exits 2 with a helpful install message if neither indexer is on PATH.

### Changed — `scripts/reachability.py`

Reads the new `_meta.source` field on the callgraph JSON and emits two new verdict fields:

- `callgraph_source: "scip" | "grep"` — which extraction produced the callgraph.
- `evidence_tag_eligibility: "[LSP-TRACE]" | "[CODE-TRACE]"` — which evidence tag the downstream FINDING can claim. Stage 4 Pass D enforces the floor: `[CODE-TRACE]`-only on HIGH/CRITICAL infra findings is rejected.

### Changed — `scripts/doctor.sh`

- Added `scripts/scip_to_callgraph.py` and `scripts/build-callgraph.sh` to the required-scripts catalog.
- `--check-rust` flag now probes for `rust-analyzer` and `scip-rust`, reports which is available, and surfaces install instructions when neither is present.

### Added — `references/scip-callgraph.md`

Reference documenting:

- The SCIP integration: schema, prerequisites, usage, output format.
- Evidence-tag mapping (when `[LSP-TRACE]` is earned vs `[CODE-TRACE]` fallback).
- Known limitations: macro-expansion coverage, attribute metadata absence, workspace boundary.
- Smoke-test recipe verifying the toolchain end-to-end.

### Changed — `references/infra-verification-stage.md`

Replaced the v0.4.0 stub describing optional external SCIP/RAG capabilities behind env vars with a focused section pointing at the Argus-internal SCIP integration in `scip-callgraph.md`. The vulnerability-RAG endpoint env var (`ARGUS_EXT_VULN_RAG`) is retained for advanced users.

### Migration notes

- v0.4.0 → v0.4.1 is fully backward-compatible. Callgraphs without `_meta.source` are treated as grep-extracted (default to `[CODE-TRACE]` evidence tier).
- Existing runs that called `reachability.py` directly continue to work; the new output fields are additive.

## [0.4.0] — 2026-05-17

**Severity, evidence, and depth-tier overhaul.** Stage 1 becomes threat-model-first (actors → boundaries → 10-point attack-surface walk → entry-points), Stage 4 severity moves to an Immunefi v2.3-aligned **Impact × Likelihood × Modifiers** matrix with both downgrades AND upgrades, every infra FINDING now carries mandatory evidence-quality tags + 6 mandatory analysis checks + a 4-state verdict, and Stage 0 introduces named depth tiers (Light / Core / Thorough). New `/argus-doctor` slash command + `scripts/doctor.sh` verify install readiness. Two optional external indices (`ARGUS_EXT_SCIP_READER`, `ARGUS_EXT_VULN_RAG`) can be wired in for `[LSP-TRACE]` evidence + Stage 4 RAG enrichment.

### Changed — `references/infra-impact-analysis.md`

Stage 4 severity matrix rewritten end-to-end:

- **Step 2**: 6 legacy impact categories → 5 Immunefi v2.3 tiers (Critical / High / Medium / Low / Informational).
- **Step 3**: Reachability axis (`remote / authenticated / local`) → Likelihood axis (`high / medium / low`).
- **Step 4**: 6×3 hand-tuned matrix → 5×3 matrix derived from Immunefi v2.3.
- **Step 5 (new)**: Modifier system with downgrades (`BYZANTINE-1-3`, `BYZANTINE-2-3`, `FULLY-TRUSTED-ROLE`, `SELF-HARM-ONLY`, `TESTNET-ONLY`, `ON-CHAIN-ONLY-OBSERVATION`, `LATENT-DEAD-CODE` cap-HIGH) **and** upgrades (`CROSS-CHAIN-BRIDGE-FUND-LOSS`, `FINALITY-STRICT-CHAIN`, `ATTACKER-HAS-SOURCE-CONTROL`, `PERMISSIONLESS-ZERO-STAKE` gate:MEDIUM, `UNAUTHENTICATED-RPC-ENDPOINT` gate:MEDIUM, `PRE-AUTH-PANIC` floor:HIGH). Modifiers stack; floor=Informational, ceiling=Critical.
- **Step 6 (new)**: 8 calibration adjustments from real bug outcomes (eclipse default-Medium, mempool asymmetric-DoS=High, RPC-crash-needs-≥25%-market-share, brute-force language, single-client consensus High not Critical, pre-auth panic floor=High, latent dead-code capped High, bundle-incomplete=PARTIAL).
- **Step 7 (new)**: Mandatory `severity_rationale` field on every FINDING (impact_cell + likelihood_cell + modifiers_applied + resulting_tier).

This replaces v0.3.x's "no upgrade rule" — bridges, finality-strict chains, unauthenticated RPC, and pre-auth-reachable panics now carry severity-bumps when they apply.

### Changed — `scripts/assign_severity.py`

Rewritten to match the new matrix:

- New `LEGACY_IMPACT_TO_TIER` dict maps 6 legacy categories to 5 Immunefi tiers.
- New `SEVERITY_MATRIX` keyed by `(impact_tier, likelihood)`.
- New `DOWNGRADE_MODIFIERS` + `UPGRADE_MODIFIERS` dicts with shift_severity + apply_modifier functions; modifiers stack with full audit-trail rationale.
- New `--likelihood {high,medium,low,test-only,unclear}` flag (v0.4.0 standard).
- Legacy `--reachability` flag preserved as alias that maps `remote→high / authenticated→medium / local→low`.
- New repeatable `--modifier <ID> --modifier-evidence "<citation>"` pair; legacy `--downgrade-rule` flag kept for back-compat.

### Changed — `references/hacking-agents/shared-rules.md`

New mandatory FINDING fields in infra mode (SC mode: optional except `confidence_gate`):

- **`evidence_tags`** — every infra FINDING declares one or more of `[FUZZ-PASS]`, `[LSP-TRACE]`, `[CODE-TRACE]`, `[NON-DET-PASS]`, `[CONFORMANCE-PASS]`, `[DIFF-PASS]`, `[PRIMITIVE:FALLBACK]`. Evidence rule: `[CODE-TRACE]`-only on HIGH/CRITICAL is rejected at Stage 4 Pass D.
- **`mandatory_checks`** — 6 pass/fail gates: Devil's Advocate (one-paragraph rebuttal AGAINST the finding), Pre-Auth Check (does the bug fire before authentication completes?), Asymmetric Cost (attacker vs defender resource ratio), Cross-Domain Dependencies (out-of-scope deps), Evidence Quality (tag-set sufficient for claimed severity), Confidence Gate (point ≥ 50 AND low ≥ 30 for FINDING).
- **`verdict_state`** — 4-state model: `CONFIRMED / REFINED / REFUTED / CONTESTED` (replaces legacy 3-state `CONFIRMED / DISPROVED / INCONCLUSIVE`). `verdict_history[]` records every state transition with stage + reason + timestamp.
- **`severity_rationale`** — paired with the new matrix (impact_cell + likelihood_cell + modifiers_applied + resulting_tier).

### Added — `references/cost-estimation.md` § Named depth tiers

Stage 0 now selects a depth tier before cost estimation:

- **Light**: 4 fast angles (Vector Scan, Periphery, First Principles, Math Precision), Clippy-only backend, Tier-3 PoC accepted, Pass A+D only. ~30% of Core.
- **Core (default)**: 8 angles, +cargo-audit/deny/geiger, Tier-2 PoC minimum, full Pass A/B/C/D. 1.0× baseline.
- **Thorough**: 8 angles + cross-cutting depth re-runs, all Core backends + Miri + Kani + Loom + Rudra + cargo-fuzz (24h), Tier-1-live-e2e mandatory, 2× Devil's-Advocate rebuttal. ~3.0× Core.

`scripts/estimate-cost.py` gained `--depth-tier {light|core|thorough}` and per-stage tier multipliers; cost-preview UI shows the active tier and prices accordingly.

### Added — `references/threat-model-first.md` + Stage 1 rewire

New top-level reference describing the threat-model-first 6-step Stage 1 procedure (actors → trust boundaries → 10-point OpenZeppelin-aligned attack-surface walk → entry points → invariants → surface-weighted hot-zones). `pipeline-overview.md` Stage 1 contract updated to Phase A (threat model) before Phase B (surface enumeration). `stage1-output-templates.md` `attack-surface.md` template now requires a Trust-boundary index and the 10-point walk before the entry-point classification table.

The 10 surface points: access control, input validation, authentication, authorization, state management, token handling, external calls, cryptographic operations, time/randomness, economic incentives. Each gets a §-subsection with code citations or explicit `n/a — <reason>`.

### Added — `references/hacking-agents/infra/depth-methodology.md`

All 8 infra-mode angles load this file alongside `shared-rules.md`. Codifies 8 disciplines: attack-surface enumeration → devil's-advocate sweep → pre-auth panic sweep → asymmetric-cost quantification → resource-bounds check → eclipse/peer-table analysis (where applicable) → cross-domain-dependency tag → always-on boundary checklist. Includes the §WRITE-THEN-VERIFY discipline (write FINDINGs directly to `F-NN.md`, return only a one-line summary to the orchestrator) and a mandatory telemetry YAML header for Thorough-tier runs.

Each of the 8 infra agent files gained a one-line load directive pointing at `depth-methodology.md` (mandatory in Core + Thorough tiers, optional in Light).

### Added — `scripts/doctor.sh` + `/argus-doctor` slash command

Install-verification + readiness check:

- Confirms skill installation at `~/.claude/skills/argus` and/or `~/.codex/skills/argus`.
- Verifies 14 required reference files present and non-empty.
- Verifies 6 helper scripts present + 3 Python scripts parse cleanly.
- Probes 5 host tools (python3, bash, grep, git, find).
- Optional `--check-rust` flag probes Rust toolchain readiness and delegates to `install-infra-deps.sh --dry-run` for backend coverage.
- `--json` flag emits machine-readable output.
- Exit code 0 = all critical checks pass; 1 = one or more fails.

The `/argus-doctor` slash command (commands/argus-doctor.md) wraps it for one-shot invocation.

### Added — `references/infra-verification-stage.md` § Optional external indices

Two opt-in capabilities behind environment variables:

- `ARGUS_EXT_SCIP_READER`: path to a SCIP-reader implementation (bidirectional def/ref traversal). When set, the `reachability_check` field on FINDINGs may carry `[LSP-TRACE]` evidence tag — promoting infra HIGH/CRITICAL findings above the `[CODE-TRACE]`-only floor.
- `ARGUS_EXT_VULN_RAG`: path to a local vulnerability-RAG endpoint. Used by Stage 4 close-call review, Stage 7 dup-check, Stage 6 program triage.

Neither is bundled with Argus; vanilla runs work without either. Argus is the methodology; external tooling accelerates it when present.

### Migration notes

- v0.3.x runs that called `assign_severity.py --reachability X` continue to work (legacy alias maps to `--likelihood`).
- v0.3.x FINDING blocks without `evidence_tags` / `mandatory_checks` / `verdict_state` are accepted by SC mode (back-compat); infra mode rejects them at Stage 2 dedup and re-emits with the angle.
- Existing Stage 1 outputs lacking the 10-point walk are accepted by Stage 2 in Light tier; rejected in Core + Thorough.

## [0.3.5] — 2026-05-13

**Codex CLI compatibility.** Argus now installs to both Claude Code and Codex CLI from a single `install.sh`. Codex skill format is identical to Claude Code's (`~/.codex/skills/<name>/SKILL.md` + same `references/` layout) — confirmed by inspecting Codex's bundled system skills (`skill-creator`, `skill-installer`, `openai-docs`). Same SKILL.md frontmatter convention. A handful of Claude-specific tools (`AskUserQuestion`, `TodoWrite`, `Task`, `WebFetch`) need translation to Codex equivalents; the methodology files themselves are tool-agnostic.

### Changed — `install.sh`

Rewritten as dual-target installer with auto-detection:

```bash
./install.sh                     # install to all detected targets (Claude + Codex if both present)
./install.sh --target claude     # Claude Code only
./install.sh --target codex      # Codex CLI only
./install.sh --target both       # explicit both (alias for default)
```

- Detects `~/.claude` and `~/.codex`; installs to whichever (or both) exist.
- Slash-commands (`commands/argus.md`, `commands/argus-fix-verify.md`) install to Claude only — Codex auto-loads via skill description match, no slash-command equivalent.
- Skill files (SKILL.md + references/ + scripts/ + assets/) copy identically to both targets.
- Reports targets installed at end + per-platform usage instructions.

### Added — `references/codex-compat.md`

Tool-translation guide for running Argus under Codex. Covers:

| Claude Code tool | Codex equivalent |
|------------------|------------------|
| `AskUserQuestion` | Plain prompt with `[A] / [B] / [C]` options; wait for reply |
| `TodoWrite` | Markdown checklist at `$RUN_DIR/_todos.md`; `← in progress` marker; one-todo-active discipline preserved |
| `Task` (subagent dispatch) | Codex's parallel-subagent feature if available; sequential fallback otherwise (with `[CODEX-COMPAT]` audit note in verdict files) |
| `WebFetch` / `WebSearch` | `web.run` or Codex's current web tool |
| `Skill` (cross-skill invocation) | Codex auto-loads via description-match; no explicit invocation needed |
| `Bash` / `Read` / `Edit` / `Write` / `Grep` / `Glob` | Universal — identical semantics, may have different tool names |

Platform detection rules (env var `CLAUDE_PROJECT_DIR` vs `CODEX_HOME`), per-stage where each Claude-specific tool is used, and a graceful-degradation rule for unrecognized tool errors: degrade to closest equivalent + write `[CODEX-COMPAT]` audit note in verdict file.

What works identically on both platforms: stage discipline, FINDING schema fields, all per-stage methodology, all vector catalogues (V1–V132 SC, A01–I12 infra), all deterministic backends at Stage 3 (Miri / Kani / Loom / Rudra / cargo-fuzz / cargo-audit — these are shell-invoked external tools, identical on both), Impact × Reachability matrix + Python scripts.

What's NOT yet tested on Codex: a real Codex run on a benchmark target. v0.3.5 ships the install + translation guide; first real Codex run will surface any methodology files referring to Claude-specific tools not caught by the translation table.

### Changed — `SKILL.md`

New "Platform note" section at the top of routing, just before the "Audit mode" section. Tells the orchestrator to read `codex-compat.md` at session start when running under Codex. Documents that invocation differs (Claude `/argus` slash command vs. Codex description-trigger auto-load).

### Changed — `.claude-plugin/plugin.json`

Version stuck at `0.1.0` since the initial release — bumped to `0.3.5`. Description rewritten to reflect actual current scope (two-mode pipeline with infra deterministic backends + cross-platform support). Author + name unchanged.

### Codex install convention

`~/.codex/skills/argus/` mirrors `~/.claude/skills/argus/`:

```
~/.codex/skills/argus/
├── SKILL.md
├── VERSION → 0.3.5
├── references/
│   ├── audit-modes.md
│   ├── codex-compat.md   ← NEW
│   ├── ... (everything else identical to Claude install)
├── scripts/ (install-deps.sh, install-infra-deps.sh, reachability.py, assign_severity.py, enumerate.sh, estimate-cost.py)
├── assets/
└── (no commands/ — Codex auto-loads via description)
```

### Restart Codex after install

Per Codex's skill-installer convention: "Restart Codex to pick up new skills." Argus's install.sh prints this reminder when Codex is one of the installed targets.

### Source attribution + verification

- Codex install layout discovered by inspecting `~/.codex/skills/.system/` (the system-skills tree): `skill-creator`, `plugin-creator`, `skill-installer`, `openai-docs`, `imagegen`. All five use the identical `---` YAML frontmatter + SKILL.md body convention as Claude Code skills. The skill-installer SKILL.md confirms the install path convention (`$CODEX_HOME/skills/<name>`) and the restart-after-install requirement.
- The `web.run` translation for WebFetch is the closest Codex equivalent based on the openai-docs SKILL.md mentioning "developers.openai.com MCP server" + web fallback. The exact Codex tool name may have evolved; the translation table notes this and recommends consulting Codex's current docs if a tool call fails with an unrecognized-tool error.

### Files modified — v0.3.5

- `install.sh` — dual-target installer
- `SKILL.md` — Platform note section
- `.claude-plugin/plugin.json` — version + description
- `VERSION` — `0.3.5`

### Files added — v0.3.5

- `references/codex-compat.md` — tool-translation guide

### What this does NOT close

- **First-class platform detection in SKILL.md**: the current approach is "read codex-compat.md when on Codex." A v0.4.0 candidate is making SKILL.md itself platform-aware (auto-pick tool name per platform) — cleaner but bigger rewrite.
- **Codex parallel-subagent dispatch**: the translation guide acknowledges Codex may not have Claude's parallel `Task` dispatch. Argus's Stage 2 (8 angles) and Stage 4 Wave 2 (4 checkers per pass) will fall back to sequential on Codex if parallel-dispatch isn't available. Sequential preserves correctness; loses parallelism speedup.
- **Real-world Codex validation**: v0.3.5 is install + translation only. No actual Codex run has exercised the full pipeline yet. The first real run will surface any methodology-file Claude-isms the translation table missed.

---

## [0.3.4] — 2026-05-13

**Zebra CVE-pattern catalogue extension.** Driven by an external analysis (deep2.md) extracting root-cause patterns from 12 claimed Zebra GHSA advisories (March–May 2026). The analysis correctly diagnosed that the v0.3.3 infra catalogue (77 vectors) doesn't encode the actual bug shapes that have produced recent Zebra CVEs — even though Argus's deterministic-backend verification (v0.3.3) is correct, Stage 2 would have missed every published pattern because no vector recognized the shape.

**Caveat on attribution**: the specific GHSA IDs cited in deep2.md (e.g., GHSA-h9hm-m2xj-4rq9, GHSA-pvmv-cwg8-v6c8, CVE-2026-34202) were not independently verified during integration. The *patterns* are integrated because they are independently valuable as catalogue extensions; the specific CVE attributions are recorded as claimed-but-unverified. Users running Argus on Zebra should treat the new vectors as catalogue patterns to investigate, not as confirmation that those exact CVEs exist.

### Added — `references/attack-vectors/dlt-infra-attack-vectors.md` (5 new vectors; 77 → 82 total)

- **F-08 — Allocate-then-check with ceiling exceeding true protocol limit.** Distinct from F-01 (unbounded `Vec::push`) and F-05 (large allocation from attacker-controlled capacity). F-08 is the *bounded-but-bounded-too-high* class: the deserializer uses `TrustedPreallocate` or `max_allocation()` to cap the allocation, but the cap is derived from the transport ceiling (2 MiB) or block-size ceiling, not the protocol-spec limit. Real spec limit is checked AFTER allocation. Attacker inflates size field to near transport ceiling, forces large allocation before rejection. Examples from claimed Zebra CVEs: `headers` message (transport ceiling allows ~1,409 entries; protocol limit is 160), `addr` message (`max_allocation()` returns 69,904 for v1 / 233,016 for v2; spec limit is 1,000), Equihash solution Vec, coinbase Sapling spends. Detection: compare `max_allocation()` / `TrustedPreallocate::max_allocation()` return value against the protocol spec limit; flag any gap >2×. Stage 1 must supply spec limits via protocol-mapping output.
- **G-09 — HTTP/RPC middleware converts client-side error into fatal server abort.** The middleware treats `hyper::Error` (or equivalent: `axum::Error`, `actix::Error`, `tonic::Status`) from a client disconnect, partial body, or TCP RST as unrecoverable and calls `panic!` / `abort()` / `process::exit()` instead of returning an error response. Attacker can crash the node by sending a partial request and resetting the connection. Detection: review every HTTP / RPC handler in the server stack; verify all `Result<_, hyper::Error>` paths map to error responses, never to abort. Example from claimed Zebra CVE: `DoS via Interrupted JSON-RPC Requests` (GHSA-29x4-r6jv-ff4w as cited; unverified).
- **H-09 — FFI callback fails to enforce domain-specific validation previously performed on the foreign side.** Distinct from H-02 (FFI null pointer check) and H-03 (allocation contract). H-09 is the *cross-language consensus refactor* class: the protocol's reference implementation (typically C++, e.g., zcashd) historically enforced a consensus rule. A refactor moved part of the verification into Rust, passing a callback into the foreign code. The Rust callback now bears responsibility for that consensus rule but doesn't enforce it — it forwards to a lower-level function (e.g., `librustzcash`) that computes a well-defined digest for the invalid case instead of erroring. Result: Rust impl accepts where reference impl rejects → consensus split. Detection: for every `extern "C" fn` passed as a callback to FFI verification, enumerate the consensus rules the foreign code historically enforced (via git history of the foreign-impl source) and verify the Rust callback enforces them. Examples from claimed Zebra CVEs: SIGHASH_SINGLE missing-output handling, sighash hash-type forwarding, stale buffer when callback returns None. Detection requires diff against pre-refactoring foreign code OR cross-reference to protocol spec (e.g., ZIP-244 §S.2a).
- **I-11 — Verification cache key excludes a security-critical field.** A `HashMap` / `BTreeMap` keyed by a type whose `Hash` / `Eq` impl deliberately excludes a security-critical field (e.g., authorization data root, signatures, witness data) that IS checked outside the cache. On a cache hit, the cached "already verified" result is reused without re-validating the excluded field. Attacker mutates the excluded field while keeping the cache-key identical. Detection: find every `HashMap` / `BTreeMap` keyed by a type with a custom `Hash` impl, enumerate which fields the `Hash` excludes, verify the cache lookup re-validates those fields on hit. Example from claimed Zebra CVE: `find_verified_unmined_tx` keyed by txid that excludes Authorization Data Root (GHSA-... as cited; unverified).
- **I-12 — Consensus-critical metric undercounted / not accumulated during block validation.** A consensus-level metric (sigops-per-block, weight, fees, byte-size) is undercounted in Zebra's block validator vs. the reference implementation. Examples: Zebra skipped the coinbase `scriptSig` sigop count (~98 missing) AND never accumulated P2SH redeem-script sigops during block validation (only during mempool acceptance for ZIP-317 fee weighting). Result: a block exceeding the 20,000 sigop limit accepted by Zebra, rejected by zcashd. Detection: for every Bitcoin-inherited consensus rule (§7.6 catch-all of Zcash protocol spec — these are inherited via "what Bitcoin does" rather than explicitly documented in a ZIP, making them easy to miss during refactoring), verify Zebra's block validator accumulates the metric identically to the reference impl. Requires Stage-1 extraction of Bitcoin-inherited rules + zcashd source diff for the metric-aggregation step.

### Catalogue patterns rejected as vectors

The deep2.md analysis proposed a 6th vector — **F-08 "Composite DoS via independent subsystem weaknesses."** This is not a vector pattern; it's a methodology gap (cross-crate finding composition). The specific Zebra case cited (block-discovery-halt via queue saturation + silent drop + degraded backup, GHSA-h9hm-m2xj-4rq9 as claimed) is real, but the detection mechanism is "Stage 2.5 cross-crate finding composition," not a single pattern Stage 2 angles can scan for. Tracked as a v0.4.0 process improvement (see below).

### Deferred process improvements (v0.4.0 candidates)

The deep2.md analysis correctly identifies four architectural improvements beyond catalogue extension. These are NOT shipped in v0.3.4; they're tracked for v0.4.0:

1. **Cross-crate attack chain analysis (Stage 2.5)** — Argus currently audits each crate independently. The block-discovery-halt class requires pairing F-group / G-group findings across crates to recognize that they compose into an unrecoverable failure. A Stage 2.5 sub-stage would take all Stage-2 findings, identify cross-crate pairs whose mechanisms interact, and elevate the composite to a higher-severity finding.
2. **Spec-to-code differential (Stage 1.5)** — for protocols with a published spec (Zcash protocol spec, Ethereum yellow paper, Solana docs) AND a reference implementation in another language (zcashd, geth, solana-program-library), Stage 1.5 would extract protocol constants and consensus rules into `spec-constants.md` and Stage 2 angles would flag any discrepancy. Closes I-12-class spec-compliance gaps automatically.
3. **Dependency panic surface audit (Pre-Stage 3)** — for every `unwrap()` / `expect()` in direct + transitive deps that's reachable from the in-scope code's verification path, flag the call site and verify the in-scope code validates inputs against the dependency's documented invariants before calling. Closes the "rk identity panic" / "V5 TxID panic" class where dependency-internal panics are triggered by in-scope parsing choices.
4. **FFI callback consensus audit (Stage 2 supply-chain-ffi sub-check)** — for every Rust callback passed to FFI verification functions, enumerate consensus rules the foreign code historically enforced (via foreign-impl git history) and verify the Rust callback enforces them. Closes H-09-class refactoring bugs.

All four require multi-hour implementation work and possibly new tooling. v0.3.4 ships the patterns; v0.4.0 will ship the process changes.

### Stage 2 angle priority for Zebra-class targets (recalibration)

The deep2.md analysis correctly recalibrates angle priorities based on real Zebra CVE history:

| Angle | v0.3.3 priority | v0.3.4 priority for Zebra-class | Why |
|-------|-----------------|--------------------------------|-----|
| logic-state-machine | High | **Highest** | Consensus-logic bugs dominate (sighash, sigops, cache keys, auth data) |
| supply-chain-ffi | Medium | **Highest** | FFI-callback refactor bugs are a known Zebra class |
| resource-exhaustion | High | **Highest** | Allocation amplification + queue saturation + panic-on-malformed are real CVE classes |
| crypto-misuse | Highest | High | Few primitive-level CVEs; most "crypto" bugs were actually consensus-logic |
| memory-safety | Highest | Medium | Zebra uses `unsafe` sparingly; FFI is well-audited |
| concurrency | Medium | Medium | No concurrency CVEs in claimed set |

This recalibration is in `examples/zebra-cve-patterns.md` (saved from deep2.md) — Argus uses this when running against Zebra specifically. General infra-mode priorities in `audit-modes.md` are unchanged.

### Files added

- `examples/zebra-cve-patterns.md` — full deep2.md content saved for reference. Drop into `<zebra-clone>/assets/docs/zebra-cve-patterns.md` alongside `zebra-patterns.md` before running `/argus`. The two files complement: `zebra-patterns.md` is hypothesis-targeting; `zebra-cve-patterns.md` is pattern-library extension.

### Files modified

- `references/attack-vectors/dlt-infra-attack-vectors.md` — F-08, G-09, H-09, I-11, I-12 added. 77 → 82 entries. Each new entry tagged `(added v0.3.4 from Zebra CVE pattern <letter>)` for traceability.
- `VERSION` — `0.3.4`.

### What this closes

- Catalogue coverage for the 5 specific pattern classes Zebra has seen in published CVEs.
- The "pattern library gap" the external analysis correctly diagnosed: Argus's infra catalogue had memory-safety + arithmetic + concurrency vectors but missed the consensus-logic-refactor patterns that produce most Zcash full-node CVEs.

### What this does NOT close

- The 4 process improvements (cross-crate composition, spec-to-code diff, dep panic audit, FFI callback consensus) — tracked for v0.4.0.
- Independent verification of the 12 GHSA IDs cited in deep2.md. The patterns are catalogue-worthy regardless; the specific CVE attributions are recorded but not validated.
- Per-pattern Tier-1-live-e2e harness templates — v0.3.4 ships the catalogue entries with detection rules + golden-signature shapes; per-vector harness scaffolding is per-finding work at Stage 3, not catalogue work.

### How to use on a Zebra run

```bash
cd <zebra-clone>
mkdir -p assets/docs
cp ~/Documents/Dev/argus/examples/zebra-patterns.md assets/docs/zebra-patterns.md
cp ~/Documents/Dev/argus/examples/zebra-cve-patterns.md assets/docs/zebra-cve-patterns.md
# In Claude Code:
/argus
```

Argus will read both files at Stage 1; the new V-IDs (F-08, G-09, H-09, I-11, I-12) will be recognized during Stage 2 Vector Scan; the recalibrated angle priorities apply for Zebra-class targets.

### Source attribution

- External analysis: deep2.md (12 Zebra GHSA pattern extraction)
- Integration adjustments: rejected F-08 (composite DoS) as a vector, kept as methodology gap → v0.4.0; renumbered doc's G-08 to G-09 to avoid collision with existing G-08 (epoch/slot truncation); recorded CVE attributions as claimed-but-unverified.

---

## [0.3.3] — 2026-05-12

**E2E-first verification + REFINE auto-loop.** Two coupled changes that elevate live-E2E to the load-bearing verdict mechanism for `infra` mode and stop dropping REFINE-bucket findings in the user's lap.

User directive: *"argus to be running main priority for every poc an e2e test for blockchain DLT.. all e2e to prove the bug exists."* Plus: REFINE findings should be auto-refined and run, not just enumerated.

### Architectural change 1 — Tier-1-live-e2e mandatory for CONFIRMED

**Pre-v0.3.3**: a Group H finding could reach CONFIRMED on `cargo audit` match + `cargo tree -i` reachability from `[dependencies]`. v0.3.2 added the advisory-body caveat check. **Neither was sufficient.** F-07 in the 2026-05-12 monero-oxide run proved this: RUSTSEC-2026-0104 was correctly matched, the dep-graph showed `[dependencies]` reachability, but Codex's live TLS handshake test refuted the over-claim by showing the codebase never configures CRLs.

**v0.3.3**: every `infra` mode CONFIRMED requires a **Tier-1-live-e2e artifact** at `$RUN_DIR/3-verification/F-NN/e2e/` containing: a runnable test that imports the in-scope crate, exercises the actual code path, observes whether the bug fires. Tool output alone (cargo-audit / Miri / Kani / Loom / cargo-fuzz) is necessary but not sufficient.

New CONFIRMED verdict requires all four steps to pass:
1. Tool output contains the golden_signature substring.
2. No false-positive pattern matched.
3. Advisory-body caveat check (Group H) returns AFFECTED.
4. **Tier-1-live-e2e artifact exists with `e2e_verdict: REPRODUCED`.**

E2E UNREACHABLE (bug real in isolation, in-scope code never reaches it) → **DISPROVED**.
E2E INCONCLUSIVE (build failed / output ambiguous / harness timed out) → **INCONCLUSIVE**.

### Architectural change 2 — REFINE auto-loop (Stage 8.5)

**Pre-v0.3.3**: findings landing in REFINE with rationales like "needs wallet2-comparator verification", "partial-dup of open #152", "Scanner DoS; no matching bounty tier" stopped at the user's manual queue. The 2026-05-12 monero-oxide run produced 5 REFINE findings; the user had to manually resolve each.

**v0.3.3**: a new **Stage 8.5 refine-loop** auto-resolves REFINE findings whose rationale matches a known pattern:

- **R1 — Comparator verification**: spawn a Sonnet subagent that fetches the cited external system's source (wallet2, OpenZeppelin, Pyth, etc.) via WebSearch / direct read and verifies the claim. Result → SUBMIT / DISCARD / STAY_REFINE.
- **R2 — Dup check against cited GitHub issue/PR**: fetch via `gh`, compare mechanism, classify EXACT_DUPLICATE / RELATED_DIFFERENT / RELATED_NARROWER / RELATED_BROADER. Result → DISCARD with `dup-of-#N` or SUBMIT with reframing note.
- **R3 — E2E build for findings without runnable PoC**: invoke the Tier-1-live-e2e pattern from `e2e-test-discipline.md` per the component type. Result → SUBMIT (if REPRODUCED) / DISCARD (if UNREACHABLE) / STAY_REFINE (if INCONCLUSIVE).
- **R4 — Bounty-tier mapping**: re-fetch the bounty page's impact-category list, map the finding's impact, decide whether a tier fits. Result → DOWNGRADE-to-tier and SUBMIT, or DISCARD.
- **R5 — Joint judge for "root cause of F-X / F-Y" findings**: re-run Phase 8a-pre joint Pass C with the hypothesis. Result → merge / distinct / re-flip relationship.
- **R6 — README invariant + scope-carveout re-check**: pure file-reads. Result via existing verdict matrices.

The loop runs once per REFINE finding. Findings the loop cannot resolve (no pattern match, INCONCLUSIVE E2E, comparator-unverifiable) stay in REFINE with the loop's note. The manual-review surface is much smaller than pre-v0.3.3.

### Per-component-type E2E patterns

`references/e2e-test-discipline.md` (NEW) defines what Tier-1-live-e2e means per Stage-1 component type:

| Component type | E2E pattern |
|----------------|-------------|
| validator-client | Spawn validator binary; feed crafted p2p / RPC / mempool input; observe panic/crash/corruption |
| consensus-engine | `stateright` model importing the in-scope state-machine; find counterexample trace |
| p2p-networking | Two-peer swarm; A sends crafted message to B; observe B's panic/OOM |
| crypto-library | Direct API call (sign/verify/derive) with crafted input; observe nonce reuse/key leak/malleability |
| storage-engine | Real DB instance + crafted state + crash injection; observe corruption on recovery |
| rpc-api-node | Spawn RPC server; real HTTP client + crafted request; observe crash/leak |
| bridge-relayer | Mock source-chain + crafted finality proof; feed to in-scope verifier; observe forge-acceptance |
| wallet-library | Real wallet instance + signing/derivation operations + side-channel timing (dudect) |
| smart-contract-vm | Load crafted bytecode into in-scope VM; observe sandbox escape / metering bypass |
| supply-chain (Group H) | Project depending on in-scope crate + exercising cited API; observe whether bug fires through the actual call chain |

Three honestly-acknowledged fallback classes where pure CI E2E is infeasible:
- Requires mainnet state → fall back to proptest with stated assumption.
- Requires real hardware (HSM, SGX) → fall back to Kani proof.
- Multi-node distributed (>2 nodes) → `stateright` counts as Tier-1-live-e2e per consensus-engine pattern.

**Every other class — Group H supply-chain, panic/crash, integer-overflow, TLS-handshake, RPC-injection, key-derivation — requires a live runnable E2E. No more cargo-audit-only verdicts.**

### Changed — `SKILL.md` operating principles

Added two new principles (8 + 9):

8. **(infra mode) Live E2E evidence over tool-confirmation alone.** Stage 3 CONFIRMED requires a Tier-1-live-e2e artifact, not just a deterministic-backend match. The F-07 over-claim was the failure that established this rule.
9. **(infra mode) REFINE findings auto-loop.** REFINE-bucket findings with known refinement-pattern rationales auto-route to Stage 8.5 (E2E build, comparator verification, dup-check, bounty-mapping, joint judge, invariant re-check). Manual review is reserved for ambiguous cases the loop can't resolve.

### Changed — `references/infra-verification-stage.md`

Verdict-assignment rules section rewritten: 4-condition CONFIRMED (was 1-condition), explicit DISPROVED-via-UNREACHABLE-E2E case, INCONCLUSIVE-via-build-failure case. F-07 walkthrough included to show how the new gates would have caught the over-claim.

### Files added — v0.3.3

- `references/e2e-test-discipline.md` (NEW) — per-component-type E2E patterns + artifact schema + fallback classes + cost budget.
- `references/refine-loop.md` (NEW) — Stage 8.5 auto-refinement procedure + 6 refinement patterns (R1-R6) + cost budget + coordination with other stages.

### Files modified — v0.3.3

- `SKILL.md` — operating principles 8 + 9.
- `references/infra-verification-stage.md` — verdict-assignment rules tightened; F-07 walkthrough; REFINE-loop pointer.
- `VERSION` — `0.3.3`.

### What this closes

- **The F-07 class of over-claim is structurally prevented** — cargo-audit + dep-graph match is necessary but not sufficient; live E2E is mandatory.
- **REFINE bucket no longer requires manual review for the common cases** — comparator verification, dup-check, E2E build, bounty-mapping, fix-subsumption, invariant check are all auto-attempted.
- **`ARGUS_AUDIT.md` S8-3** (fix-subsumption uses English reasoning; executable check deferred) — partially closed by R5 (joint judge with executable patch-apply + PoC re-run is now in scope for refine-loop, though full impl is per-finding).
- **`ARGUS_AUDIT.md` C-1** (calibration debt) — not closed, but the E2E-mandatory rule reduces the *cost* of calibration failure (a wrong matrix cell that pushes a finding to CONFIRMED now also has to survive E2E, which catches the over-claim).

### What this does NOT close

- **Cost overhead.** Adding Tier-1-live-e2e per finding adds ~5-15 min wall-clock per CONFIRMED finding. For a 10-finding run, ~50-150 min added Stage 3 cost. This is the price of correctness. Stage 0 cost-preview will surface this; the user can choose to cap.
- **REFINE pattern matching is keyword-based.** New REFINE rationale phrasings slip through as `unmatched`. The pattern list is extensible.
- **Stage 4+ rework on auto-promoted findings.** When R3 reproduces a finding, it re-enters Stage 4 for severity recompute. This adds cost but is correct.
- **Three E2E-infeasibility fallback classes** (mainnet-state, hardware, multi-node) still produce non-live-E2E verdicts. These are the residual `prop-test` / `Kani` / `stateright` paths.

### Source attribution

User directive 2026-05-12 (post-F-07 correction): "for bugs that need refining.. it should be able to refine them and run them .. please i need argus to be running main priority for every poc an e2e test for blockchain DLT .. all e2e to prove the bug exist."

This release implements that directive directly.

---

## [0.3.2] — 2026-05-12

**Stage 3 Group H (Supply Chain) verification — advisory-caveat check.** The first real `infra`-mode end-to-end run (monero-oxide audit, 2026-05-12T17:47:39Z) produced 1 SUBMIT finding (F-07: rustls-webpki 0.103.10 advisories). User correctly challenged the verdict ("did you run E2E?"); Argus admitted no — only cargo-audit had run. Codex performed live E2E verification and refuted F-07: the bug **does** reproduce in `rustls-webpki 0.103.10` standalone, but is **unreachable** through monero-oxide's TLS path because the advisory explicitly states *"Applications that do not use CRLs are not affected"* — and monero-oxide's `simple-request → hyper-rustls → rustls` stack uses `WebPkiServerVerifier::new_without_revocation` and never calls `with_crls(...)`. Zero hits across the dep tree for CRL-config patterns.

F-07 was the **only** SUBMIT-bucket finding from the run. Net SUBMIT count after Codex correction: **0**.

The root cause is a defect in the v0.3.0 Group H spec: cargo-audit match + dep-graph reachability was declared sufficient for CONFIRMED. The spec did not require reading the advisory body for affected/unaffected conditions. RustSec advisories routinely include caveats (feature flags, API call requirements, config-dependent triggers, deployment-mode exclusions); treating dep-graph reachability as exploit reachability is the same class of error as treating "the code compiled" as "the code is correct."

### Changed — `references/infra-verification-stage.md`

Group H "Golden-signature check" rewritten as a 3-step gate (all required for CONFIRMED):

1. **Dep-graph match** — `cargo audit --json` returns `"id": "RUSTSEC-YYYY-NNNN"` for the cited advisory.
2. **Reachable from non-dev path** — `cargo tree -i <crate>` shows the vulnerable crate is reachable from `[dependencies]` not `[dev-dependencies]`.
3. **Advisory-body caveat check (NEW)** — fetch the advisory body from RustSec, parse for affected/unaffected conditions, verify the codebase falls into the "affected" partition.

Common caveat patterns explicitly enumerated:
- *"Applications that do not use X are not affected"* → grep for `X` callers; zero hits → INCONCLUSIVE.
- *"Only triggers when feature flag Y is enabled"* → check `Cargo.toml` `[features]`; off → INCONCLUSIVE.
- *"Requires config option Z"* → grep for the config setter; default → INCONCLUSIVE.
- *"Only impacts users who call API W"* → trace W's call sites via reachability; no path → INCONCLUSIVE.

New mandatory `verification_plan.caveat_check` field with:
- `advisory_caveat: "<verbatim quote from advisory body>"`
- `trigger_apis: [<list of patterns to grep>]`
- `grep_command: "<exact command>"`
- `grep_hits_observed: <count>`
- `caveat_verdict: AFFECTED | UNAFFECTED | UNCLEAR`

UNAFFECTED → INCONCLUSIVE with reason `advisory_caveat_excludes_codebase`. Routes to `_inconclusive.md` + `manual-queue.md`, **NOT** SUBMIT.

New Group H verdict matrix (5 outcomes) replacing the old binary CONFIRMED/DISPROVED:

| Step 1 | Step 2 | Step 3 | Verdict |
|--------|--------|--------|---------|
| match | reachable | AFFECTED | CONFIRMED |
| match | reachable | UNAFFECTED | INCONCLUSIVE (`advisory_caveat_excludes_codebase`) |
| match | reachable | UNCLEAR | INCONCLUSIVE (`advisory_caveat_unclear`) |
| match | dev-only | any | INFORMATIONAL cap |
| no match | n/a | n/a | DISPROVED |

### Why this matters

Without step 3, Group H produces submission-grade false positives on every supply-chain CVE whose advisory has a caveat — which is most of them. This release closes the defect that the monero-oxide F-07 case surfaced: the user would have filed a $100K-bounty submission claiming a reachable panic, the platform triage would have read the advisory caveat + reproduced the unreachability finding Codex independently arrived at, and the submission would have been INVALID with reputational cost.

This is the same class of failure as the v0.2.5 Monero Oxide F-15 case (the one that drove the v0.3.0 pivot from SC to infra mode): a finding that passes mechanical tool-confirmation but fails when tested against the actual codebase semantics. v0.2.5 closed it for cited-function reachability; v0.3.2 closes it for advisory-cited-API reachability.

The user discipline that surfaced this — asking "did you run E2E?" and routing to Codex for independent verification — is the right loop. The pipeline's job is to make that loop unnecessary; v0.3.2 brings the gate one step closer.

### What this does NOT close

- LLM extraction of advisory caveat clauses is best-effort. Ambiguous advisory text → `caveat_verdict: UNCLEAR` → manual queue. Most advisories are clear; a small minority will require human reading.
- The trigger-API grep is naive (same limitation as Stage 2's `reachability_check`). For high-stakes findings, the Stage 4 `reachability.py` callgraph fallback applies — but at Stage 3 we want fast pre-filtering, not full call-graph extraction.
- Advisories without explicit affected/unaffected clauses default to AFFECTED (conservative). The Group H verdict will be CONFIRMED in this case; manual review still expected before submission.

### Files modified

- `references/infra-verification-stage.md` — Group H 3-step gate + caveat-check field schema + verdict matrix + canonical F-07 case + implementation notes.
- `VERSION` — `0.3.2`.

### Source attribution

Motivating case: 2026-05-12 monero-oxide audit run (Argus orchestrator) + Codex live E2E verification (`monero-audit/argus/2026-05-12T17-47-39Z/codex-e2e-f07/FINAL_VERDICT.md`). User asked "did you run E2E?" → Argus admitted only cargo-audit had run → user routed to Codex → Codex refuted via the live `with_crls` zero-hit grep + live TLS handshake test. This release ships the lesson back into the Stage 3 spec.

---

## [0.3.1] — 2026-05-12

**Mode-recommendation defect fix.** v0.3.0's Stage 0 `AskUserQuestion` was recommending `smart-contract` mode on a fresh monero-oxide run — even though monero-oxide is a Monero protocol Rust library (wallet / RingCT / crypto primitives), the Immunefi bounty page is explicitly tagged **Blockchain/DLT**, and the prior v0.2.5 run in SC mode produced an INVALID finding (F-15 `Decoys::select_n` — the failure that drove the entire v0.3.0 pivot).

Two miscalibrations in the recommendation logic caused this:

1. **"Prior runs in mode X → recommend mode X"** treated prior-run history as pro-signal regardless of whether those prior runs produced accepted findings. Failed prior runs (INVALID / SC-2 / out-of-scope verdicts) were being read as confirming the mode, when they should be read as anti-signal — the prior runs were themselves miscategorized.
2. **"Immunefi bounty present → smart-contract signal"** conflated Immunefi's program portfolio with SC scope. Immunefi hosts both smart-contract bounties (Solana Anchor / CosmWasm DeFi / etc.) AND Blockchain/DLT bounties (validator clients, crypto libs, wallets, nodes). The bounty page's **category selector** is the discriminating signal — not the presence of an Immunefi URL.

### Changed — `references/audit-modes.md`

New "Recommendation discipline" section establishing rule priority for the `AskUserQuestion` "Recommended" sticker:

1. **Bounty page category tag (highest priority)** — parse the page's category selector. `Blockchain/DLT` / `Infrastructure` / `Node` / `Wallet` / `Library` → recommend `infra`. `Smart Contract` / `DeFi` / `NFT` / `AMM/DEX` / `Lending` / `Bridge (contract-side)` → recommend `smart-contract`.
2. **Crate-name + repo-shape heuristics** — `*-runtime` / `*-validator` / `*-node` / `*-consensus` / `*-wallet` / `*-crypto` / `*-monero-*` / `*-substrate-*` / `*-cosmos-sdk-*` / `cometbft-*` / `solana-runtime` → `infra`. README mentioning "Anchor program" / "CosmWasm contract" / "Substrate pallet" → `smart-contract`.
3. **Project-shape default** — the existing auto-detection table (`anchor` → SC; `generic-rust` → infra; etc.).
4. **Prior-run history (lowest priority)** — ONLY pro-signal when prior SUBMIT findings were independently validated. Prior runs that produced INVALID / SC-2 / out-of-scope findings are **anti-signal**: recommend the OTHER mode.

Added explicit anti-pattern documentation: "Recommended SC because prior run was SC" is wrong when the prior runs were judged INVALID. The prior failure is anti-signal for the mode that produced it.

Added **monero-oxide as canonical case**: project shape `generic-rust` + Immunefi Blockchain/DLT tag + prior SC-mode INVALID finding = all three signals point at `infra`. Recommendation MUST be `infra`. The v0.2.5 F-15 failure is what drove the v0.3.0 pivot; any future run on monero-oxide that recommends SC perpetuates the original mistake.

### Changed — `SKILL.md`

"Audit mode" section's mode-selection paragraph rewritten to enumerate the 4-rule priority order. Explicit note: **"Immunefi presence alone is NOT a smart-contract signal" — Immunefi hosts both kinds; the category tag distinguishes**.

### Changed — `references/dlt-infra-types.md`

`Wallet / signing library` component-type profile gains a "Canonical example" note documenting monero-oxide as the reference target for infra-mode wallet/crypto-library audits, including the v0.2.5 F-15 failure history as the motivating example.

### Why this matters

The user (running `/argus` on monero-audit while looking at the live monero-oxide Immunefi page) saw `smart-contract (Recommended)` and asked "monero is blockchain DLT but Argus is saying smart-contract recommended?" — surfacing the exact bug this release fixes. The recommendation logic was anchored to prior-run history (the v0.2.5 SC-mode runs) without accounting for the fact that those prior runs produced the F-15 INVALID finding that motivated the v0.3.0 pivot in the first place. Self-reinforcing miscategorization.

Two example tables to make the corrected logic concrete:

| Bounty | Category tag | Recommendation |
|--------|-------------|----------------|
| monero-oxide | Blockchain/DLT | **`infra`** |
| Solana validator | Blockchain/DLT | **`infra`** |
| Aleo node | Blockchain/DLT | **`infra`** |
| Wormhole (Solana programs) | Smart Contract | `smart-contract` |
| Squads Multisig | Smart Contract | `smart-contract` |
| MarginFi | Smart Contract | `smart-contract` |

### Files modified

- `references/audit-modes.md` — Recommendation discipline section + anti-pattern + canonical case
- `SKILL.md` — Audit mode section's priority order
- `references/dlt-infra-types.md` — monero-oxide canonical example under Wallet / signing library
- `VERSION` — `0.3.1`

### What this does NOT close

- Parsing the Immunefi page's category selector still requires a WebFetch + LLM-extraction step at Stage 0. If the page's HTML structure changes or the fetch fails, the orchestrator falls through to Rule 2 (crate-name heuristics). The category-extraction is best-effort, not load-bearing.
- The "prior runs validated by external review" signal requires somebody to have populated `assets/findings/` with validation outcomes; on a fresh repo this falls back to Rule 1+2+3 only.
- Rule 4 (anti-signal of failed prior runs) requires Argus to have a record of WHY a prior finding was INVALID. The orchestrator reads CHANGELOG.md for known failures; absent that record, Rule 4 is silent.

---

## [0.3.0] — 2026-05-12

**Scope-pivot release. Argus now supports two audit missions: `smart-contract` mode (legacy v0.2.x pipeline, preserved) and `infra` mode (NEW — DLT infrastructure auditing with deterministic-backend verification).**

User's primary mission is **DLT infrastructure** — validator clients, consensus engines, p2p networking, crypto libraries, storage engines, RPC nodes, off-chain workers, bridge relayers, wallet libraries, smart-contract execution VMs. v0.2.6 was built for smart-contract auditing because the early test corpus was Code4rena contests; DeepSeek's `deep5.md` review correctly identified the mismatch; user confirmed the pivot. v0.3.0 ships the full `infra`-mode pipeline while preserving SC mode as a callable mode (for the on-chain components of DLT systems).

This release integrates **five chunks of specifications from DeepSeek** (`deep6.md` Chunk 2, `deep8.md` Chunk 3, `chunk4.md` Chunk 4, `chunk5.md` Chunk 5) with adjustments for Argus conventions (file naming, FINDING-schema alignment, real Python scripts in place of pseudocode, audit-modes routing reconciliation).

### Architectural simplification (the load-bearing change)

In `infra` mode, the LLM contributes only **hypothesis generation** (Stage 2 angles propose candidates) and **harness writing** (Stage 3 LLM-assisted, orchestrator-verified via `cargo check`). Everything else is mechanical:

- Stage 3: deterministic backend (Miri / Kani / Loom / Rudra / cargo-fuzz / cargo-audit / cargo-deny / cargo-geiger / Clippy) emits golden-signature substring → **CONFIRMED** / **DISPROVED** / **INCONCLUSIVE**.
- Stage 4: `rust-analyzer` call-graph reachability + vector-group impact tier → **3×6 matrix lookup** → final severity (with optional one-tier downgrade from a 4-rule set).
- Stage 5: disclosure-path selection per severity × component scope matrix → one of 4 paths.
- Stage 6: CVE decision matrix + RUSTSEC/NVD/GHSA cross-check.
- Stage 8: template fill-in from prior stages' outputs.

**Pass A/B/C/D adversarial review is SKIPPED in `infra` mode.** Tool output IS the verdict. No LLM judge anywhere after Stage 3.

### Added — Chunk 1 (mode infrastructure)

- `references/audit-modes.md` — mode routing index. Per-stage routing table for both modes. Mode-dependent vs mode-independent split. Cross-mode discipline.
- `references/dlt-infra-types.md` — DLT-infra component classification: 11 component types (validator client / consensus engine / p2p networking / crypto library / storage engine / RPC node / off-chain worker / bridge relayer / wallet / smart-contract VM / generic Rust DLT). Each profile: primary adversaries (ranked) + dominant attack patterns + critical invariants + what-to-look-for-first + temporal threat dimension (Bootstrap / Steady-state / Network stress / Upgrade / Recovery / Deprecation) + cross-component integration hazards.
- `SKILL.md` — "Audit mode" section added at top of Stage Routing. Mode auto-detection from `enumerate.sh` project-shape; `AskUserQuestion` confirmation when ambiguous.
- `ARGUS_V0.3.0_PLAN.md` — full plan doc with Chunk 2-5 specs, design decisions, status board.

### Added — Chunk 2 (`infra` Stage-2 angles + 77-vector catalogue, from DeepSeek `deep6.md`)

**8 angles under `references/hacking-agents/infra/`**:
- `memory-safety-agent.md` — Miri-driven (Group A)
- `unsafe-trait-agent.md` — Rudra + Kani (Group B)
- `arithmetic-agent.md` — Kani-driven (Group C)
- `concurrency-agent.md` — Loom-driven (Group D)
- `crypto-misuse-agent.md` — manual + Clippy (Group E)
- `resource-exhaustion-agent.md` — cargo-fuzz (Group F)
- `logic-state-machine-agent.md` — stateright / Kani / property-fuzz (Groups G + I)
- `supply-chain-ffi-agent.md` — cargo-audit / cargo-deny / cargo-geiger / Clippy (Group H + B10)

**Vector catalogue** at `references/attack-vectors/dlt-infra-attack-vectors.md` — 77 vectors across 9 groups (A-I), each with **Golden Signature** column for tool-confirmation matching:

| Group | Title | Count | Tool |
|-------|-------|------:|------|
| A | Memory Corruption & UB | 10 | Miri |
| B | Unsound Unsafe Abstractions | 10 | Rudra + Kani + Miri |
| C | Integer Overflow & Arithmetic | 8 | Kani |
| D | Concurrency & Sync Primitives | 8 | Loom + Miri |
| E | Cryptographic Failures | 8 | manual + Clippy |
| F | Resource Exhaustion & DoS | 7 | cargo-fuzz |
| G | Error Handling & State Machine | 8 | stateright / Kani |
| H | Supply Chain & FFI | 8 | cargo-audit / cargo-deny |
| I | DLT-Specific Logic | 10 | stateright / property-test |

Adjustments from DeepSeek `deep6.md`: angle file names rewritten to match SC-mode descriptive pattern (`memory-safety-agent.md` rather than `infra-angle-1.md`); added standard Argus angle-file sections (Output fields, Anti-patterns, Coordination with other angles); split DeepSeek's bundled Memory+Arithmetic angle into separate files (Miri vs Kani are tool-distinct).

### Added — Chunk 3 (deterministic verification stage, from DeepSeek `deep8.md`)

- `references/infra-verification-stage.md` — Stage 3 deterministic-tool verdict spec. Replaces SC-mode `poc-standards.md` AND `adversarial-review.md` Pass A/B/C/D entirely in `infra` mode. Tool selection table by vector group + harness-generation discipline (LLM-assisted, retry on `cargo check` failure, INCONCLUSIVE after 3 retries) + execution templates for each backend + verdict assignment rules (CONFIRMED / DISPROVED / INCONCLUSIVE) + 6 honestly-tagged manual-only vectors (E02/E03/E08/G07/I09/I10).
- `scripts/install-infra-deps.sh` — parallel to SC-mode `install-deps.sh`. Detects + (with `--install`) installs `cargo-miri` / `cargo-kani` / `cargo-fuzz` / `cargo-audit` / `cargo-deny` / `cargo-geiger` / `rudra`. User-space only; no sudo.
- `references/audit-modes.md` Stage 3 + Stage 4 routing rows updated.

### Added — Chunk 4 (Impact × Reachability matrix + working scripts, from DeepSeek `chunk4.md`)

- `references/infra-impact-analysis.md` — Stage 4 spec. Reachability buckets (Remote / Authenticated / Local / Test-only), 6 impact tiers (System Compromise / Data Corruption / Funds At Risk / Denial of Service / Confidentiality Breach / Integrity Weakening), 3×6 deterministic severity matrix, 4 downgrade rules (TRUSTED-ROLE-REQUIRED / PRACTICAL-DIFFICULTY / BOUNDED-IMPACT / UPGRADEABLE — at most one per finding, one tier down only). **No UPGRADE rule** — matrix is the ceiling.
- `scripts/reachability.py` — working reverse-BFS over `rust-analyzer`-derived call-graph JSON. Conservative dynamic-dispatch over-approximation. Parses Stage-1 `entry-points.md` for manual overrides. Emits JSON verdict with reachability bucket + call path.
- `scripts/assign_severity.py` — working matrix-lookup script. Complete `VECTOR_TO_IMPACT` table covering all 77 vectors. Severity matrix as Python dict. Downgrade application. Smoke-tested: A01+remote→CRITICAL, I06+auth+TRUSTED-ROLE-REQUIRED→HIGH→MEDIUM, A07+test-only→INFORMATIONAL.

### Added — Chunk 5 (disclosure + CVE + templates + wiring, from DeepSeek `chunk5.md`)

- `references/disclosure-paths.md` — Stage 5 spec. 4 disclosure paths: `vendor-coordinated` (CRITICAL + core protocol; CVE + 90-day embargo) / `vendor-report` (CRITICAL non-core, or HIGH/MEDIUM; CVE optional) / `cve-disclosure` (unmaintained crate, severe; standalone CVE via MITRE + RustSec) / `generic-infra` (LOW; public issue/PR, no embargo). Component-scope classification (core-protocol / independent-implementation / library-crate) by crate-name pattern + download count + stake-weighted usage.
- `references/cve-triage.md` — Stage 6 spec. CVE decision matrix (severity × reachability × project-type → YES/OPTIONAL/NO/never-for-INFO). Automated RUSTSEC/NVD/GHSA existing-advisory cross-check. Pre-filled CVE-request JSON template (MITRE form fields, CVSS v3.1 vector, CWE classification, embargo timeline). Mode-agnostic Stage 7 with extra CVE-database probe across dependency tree.
- `references/report-templates/infra/advisory.md` — vendor-coordinated template (CRITICAL + CVE + embargo timeline + tool evidence + AI-provenance disclosure).
- `references/report-templates/infra/vendor-report.md` — vendor-direct template (HIGH/MEDIUM, maintainer-facing).
- `references/report-templates/infra/cve-disclosure.md` — standalone CVE template (companion RustSec advisory YAML included).
- `references/report-templates/infra/generic-infra.md` — public-issue template (LOW).
- `references/audit-modes.md` — Stages 5/6/8 routing rows aligned (removed reference to never-created `platform-criteria/{immunefi-infra,vendor-disclosure,embargoed-cve}.md`; the 4 disclosure paths in `disclosure-paths.md` supersede that planned design).

### Changed — `SKILL.md`

Mode section rewritten to drop "v0.3.0-alpha not yet fully implemented" status. Now reflects complete pipeline with full file inventory + acknowledged calibration debt.

### Changed — `README.md`

Header rewritten to lead with the two-mode framing. v0.3.0 version.

### Changed — `ARGUS_PLAYBOOK.md`

Added v0.3.0 scope note at top: the bulk of the playbook documents SC mode in detail; an `infra`-mode summary section is added that maps each stage to its canonical reference + audit-findings closed + open work.

### Changed — `ARGUS_V0.3.0_PLAN.md`

Status board updated: all 5 chunks ✅ done. Added "What v0.3.0 ships end-to-end" + "What did NOT ship in v0.3.0" + "Closed audit findings" + "Open audit findings" sections.

### What this closes from `ARGUS_AUDIT.md` (final v0.3.0 tally)

**Critical**:
- C-2 (judge-acceptability not truth) ✓
- C-3 (orchestrator SPOF on Pass C/D) ✓

**High**:
- H-1 (132-vector library non-orthogonal) ✓ — replaced by 77-vector 9-group tool-driven catalogue in infra mode
- H-2 (severity tiers English) ✓ — deterministic 3×6 matrix
- H-3 (Cantina I×L vs C4 5-tier collision) ✓ — N/A in infra (no contest platforms)
- H-4 (rebuttal-quality classifier load-bearing) ✓ — no Pass C rebuttal logic in infra
- S2-4 (`reachability_check` naive grep) ✓ — `rust-analyzer` call graph
- S2-8 (`bug_reachability_proof` unverifiable) ✓ — tool golden-signature IS the proof
- S3-1 (80% certainty floor arbitrary) ✓ — binary CONFIRMED/DISPROVED/INCONCLUSIVE
- S4-1 through S4-9 ✓ — Pass A/B/C/D don't run in infra
- S4-7 (C4 historical-severity table) ✓ — deterministic matrix
- S5-4 (Cantina-only AI gate) ✓ — N/A in infra
- S8-3 (fix-subsumption English) — partial; Phase 8a-pre joint Pass C still applies on cross-mode hybrid

**Medium**:
- S6-1 (bounty-page YAML LLM-parsed) ✓ — structured CVE/RUSTSEC/GHSA APIs
- S6-3 (known-issues coarse text match) ✓ — structured-query existence checks
- S6-4 (generic-mode skips checks) ✓ — CVE matrix fully decidable

### What this does NOT close (v0.3.1+)

- **C-1** (calibration debt — matrix cells + downgrade thresholds + crates.io download cutoffs are hand-built; empirical calibration sweep against W3SA + future DLT-infra corpus is the planned validator).
- **A-6** (single-ecosystem-per-run; cross-mode hybrid full coverage is v0.4.0+).
- **`rust-analyzer` callgraph-extraction script** — `reachability.py` expects a specific JSON schema; the extraction step from `rust-analyzer analysis-stats` to that schema is pending (v0.3.1 candidate).
- **Manual-vector gap** — 6 vectors (E02/E03/E08/G07/I09/I10) honestly tagged INCONCLUSIVE; manual reviewer queue.
- **`infra-fp-allowlist.md`** — file slot reserved, currently empty. Populated as known Miri / Kani false positives surface during real runs.

### Files added — v0.3.0 (cumulative across Chunks 1-5)

Reference files (12 new):
- `references/audit-modes.md`
- `references/dlt-infra-types.md`
- `references/infra-verification-stage.md`
- `references/infra-impact-analysis.md`
- `references/disclosure-paths.md`
- `references/cve-triage.md`
- `references/hacking-agents/infra/memory-safety-agent.md`
- `references/hacking-agents/infra/unsafe-trait-agent.md`
- `references/hacking-agents/infra/arithmetic-agent.md`
- `references/hacking-agents/infra/concurrency-agent.md`
- `references/hacking-agents/infra/crypto-misuse-agent.md`
- `references/hacking-agents/infra/resource-exhaustion-agent.md`
- `references/hacking-agents/infra/logic-state-machine-agent.md`
- `references/hacking-agents/infra/supply-chain-ffi-agent.md`
- `references/attack-vectors/dlt-infra-attack-vectors.md`
- `references/report-templates/infra/advisory.md`
- `references/report-templates/infra/vendor-report.md`
- `references/report-templates/infra/cve-disclosure.md`
- `references/report-templates/infra/generic-infra.md`

Scripts (3 new):
- `scripts/install-infra-deps.sh`
- `scripts/reachability.py`
- `scripts/assign_severity.py`

Top-level docs:
- `ARGUS_V0.3.0_PLAN.md`

### Files modified — v0.3.0

- `SKILL.md` — Audit mode section (top of Stage Routing).
- `README.md` — two-mode header.
- `ARGUS_PLAYBOOK.md` — v0.3.0 scope note + infra-mode summary.
- `VERSION` — `0.3.0`.

### Source attributions

DeepSeek `deep6.md` (Chunk 2 — 8 angles + 77-vector catalogue with Golden Signature column).
DeepSeek `deep8.md` (Chunk 3 — Stage 3 deterministic verification spec).
DeepSeek `chunk4.md` (Chunk 4 — Stage 4 Impact × Reachability matrix + downgrade rules + Python script pseudocode).
DeepSeek `chunk5.md` (Chunk 5 — Stages 5/6/8 disclosure + CVE + templates + integration wiring).

All adjustments during integration noted inline in each chunk's CHANGELOG entry above.

---

User audits **DLT infrastructure** (validator clients, consensus engines, p2p networking, crypto libraries, storage engines, RPC nodes, off-chain workers, bridge relayers, wallet libraries, smart-contract execution VMs) — not smart contracts. v0.2.6 was built for smart-contract auditing because the early test corpus was Code4rena contests. DeepSeek's `deep5.md` review correctly diagnosed the mismatch; user confirmed: *"we are not doing rust... what i do is blockchain DLT i dont want smart contract so deepseek is right."*

v0.3.0-alpha ships the **mode infrastructure** for `infra` audits while preserving the v0.2.6 smart-contract pipeline as a callable `smart-contract` mode. Chunks 2-5 (8 infra angles + DLT-infra vector catalogue + deterministic-backend integration + Impact × Reachability matrix + disclosure paths) are tracked in `ARGUS_V0.3.0_PLAN.md` and will land in v0.3.0.

### Added — `references/audit-modes.md`

Mode-routing index. Defines the two modes (`smart-contract` legacy, `infra` new), the auto-detection heuristic per `enumerate.sh` project-shape output, the per-stage routing table showing which references each mode loads, what survives the mode split (pipeline shape, FINDING schema fields, cross-stage invariants), and what is mode-dependent (Stage-2 angles, vector catalogue, Stage-1 output templates, PoC tier ladder, Pre-Pass 1 enable/disable, Pass A invalidator catalogue, Pass D severity rubric, Stage 5/6 platforms, Stage 8 report templates).

### Added — `references/dlt-infra-types.md`

DLT-infra component classification + threat profiles. Counterpart to `rust-protocol-types.md` (smart-contract). Eleven component types: validator client/node, consensus engine, p2p networking, cryptographic library, storage engine, RPC/API node, off-chain worker/oracle/relayer, bridge/IBC/cross-chain relayer, wallet/signing library, smart-contract execution VM, generic Rust DLT crate. Each profile: primary adversaries (ranked), dominant attack patterns, critical invariants, what-to-look-for-first. Plus temporal threat dimension (Bootstrap / Steady-state / Network stress / Upgrade / Recovery / Deprecation) and cross-component integration hazards.

### Added — `ARGUS_V0.3.0_PLAN.md`

Full plan doc for Chunks 2-5 (~10 hours total work):
- **Chunk 2** (~3 hrs): 8 infra-mode Stage-2 angles (memory safety, unsafe trait soundness, concurrency, crypto misuse, resource exhaustion, logic & state machine, FFI / inline assembly, first principles) + `dlt-infra-attack-vectors.md` with 9 groups (A: UB/Miri; B: unsafe-trait/Rudra; C: arithmetic/Kani; D: concurrency/Loom; E: crypto misuse; F: logic & state machine; G: FFI/asm; H: resource exhaustion; I: supply chain) totalling ~75 vectors.
- **Chunk 3** (~4 hrs): `infra-backends.md` with per-backend invocation reference (Miri, Kani, Loom, Rudra, cargo-fuzz, cargo-audit, cargo-deny, Clippy security lints). Stage 0.5 pre-Stage-2 static-analyzer sweep. New Stage 3 PoC tiers: Tier-1-formal (Kani/Miri proof, 95-100), Tier-1-fuzz (cargo-fuzz crash, 90-100), Tier-1-runtime (Loom failing schedule, 90-100), Tier-2-prop (proptest, 80-89), Tier-3-unit (70-79), Tier-4-derivation (30-59). New 14th Pass A category: **TC — TOOL_CONFIRMED**.
- **Chunk 4** (~2 hrs): Stage 4 mode branches (Pre-Pass 1 disabled in infra, Pass A TR-1 disabled, Pass D Impact × Reachability matrix replacing English rubric + C4 historical-severity heuristic). New `disclosure-paths.md` + `cve-triage.md` + 4 infra platform-criteria files.
- **Chunk 5** (~1 hr): 4 infra report templates + README/playbook/CHANGELOG updates + VERSION bump to 0.3.0.

### Changed — `SKILL.md`

Added "Audit mode" section at top of Stage Routing. Defines the two modes, points at `references/audit-modes.md`, notes v0.3.0-alpha status (infrastructure files exist; Chunks 2-5 tracked in plan doc).

### What this closes from `ARGUS_AUDIT.md`

When Chunks 2-5 ship, the following Critical/High audit findings close:
- **C-2** (pipeline optimizes for judge-acceptability, not truth) — backend confirmations replace judge for the ~30-40% of bugs they cover.
- **C-3** (orchestrator single-point-of-failure) — Miri/Kani/Loom are independent of orchestrator confirmation.
- **H-1** (132-vector library non-orthogonal) — replaced by 9-group tool-coverage taxonomy in `infra` mode (smart-contract mode keeps V1-V132 for its scope).
- **H-2** (severity tiers are English; two runs may disagree) — replaced by Impact × Reachability matrix in `infra` mode.
- **S2-4** (`reachability_check` naive grep) — `rust-analyzer` call graph in `infra` mode.
- **S4-4** (Pass A catalogue lacks ZK / crypto-soundness invalidator) — Group E vectors + TC class.
- **S4-7** (Pass D C4 historical-severity table miscalibration) — N/A in `infra` mode; deterministic matrix instead.
- **S4-9** (`bug_reachability_proof` Stage 4 re-verification not specified) — backend invocation IS the re-verification in `infra` mode.

### Why alpha not full v0.3.0

The mode infrastructure works, but running `infra` mode today falls back to smart-contract references with explicit warnings — the actual 8 angles, vector catalogue, backend integration, severity matrix, and disclosure paths land across Chunks 2-5. Alpha discipline: don't ship a half-implemented mode as if it were complete. Bump to `0.3.0` when Chunk 5 ships.

### Files added — Chunk 1

- `references/audit-modes.md` (mode-routing index)
- `references/dlt-infra-types.md` (DLT-infra component classification)
- `ARGUS_V0.3.0_PLAN.md` (Chunks 2-5 plan)
- `VERSION` → `0.3.0-alpha`

### Added — Chunk 2 (infra Stage-2 angles + vector catalogue)

DeepSeek delivered the Chunk 2 spec (`deep6.md`): 8 deterministic-backend-driven attacker angles + 77-vector catalogue across Groups A–I with per-entry tool mappings and Golden Signatures. Integrated with adjustments for naming convention (descriptive file names matching SC-mode pattern), standard Argus angle-file sections (Output fields, Anti-patterns, Coordination), and a unified preamble explaining the tool-confirmation model.

**Eight angles under `references/hacking-agents/infra/`** (each Stage-2-dispatched in parallel when `audit-mode = infra`):

- `memory-safety-agent.md` — Angle 1. UB, aliasing, pointer provenance, uninitialised reads, transmute misuse, alignment. Miri-driven (Group A).
- `unsafe-trait-agent.md` — Angle 2. `unsafe impl Send/Sync/TrustedLen/ExactSizeIterator`, custom `Drop`, allocator alignment, `repr(C)` mismatches. Rudra + Kani + Miri (Group B).
- `arithmetic-agent.md` — Angle 3. Integer overflow / underflow / truncation / lossy casts / off-by-one bounds. Kani-driven (Group C). Includes V61 threshold-direction pattern migrated from SC mode.
- `concurrency-agent.md` — Angle 4. Data races, deadlocks, lost wake-ups, atomic ordering, lock-across-await. Loom + Miri (Group D).
- `crypto-misuse-agent.md` — Angle 5. RNG choice, non-constant-time comparison, zeroisation, weak hash, nonce reuse, curve validation, side-channel. Manual + Clippy + targeted tests (Group E).
- `resource-exhaustion-agent.md` — Angle 6. Unbounded queues / loops / recursion, HashDoS, decompression bombs, subscription leaks. cargo-fuzz + static (Group F).
- `logic-state-machine-agent.md` — Angle 7. Silent `Result` ignore, panic-poisoning, FFI re-entry, TOCTOU, async cancellation, epoch truncation, DLT-specific (consensus stalls, double-claim, peer-score bypass). stateright / Kani / property-fuzz / manual (Groups G + I).
- `supply-chain-ffi-agent.md` — Angle 8. Vulnerable deps, FFI null-check, allocator mismatch, malicious build.rs, typosquatting, `#[no_mangle]` collision. cargo-audit + cargo-deny + cargo-geiger + Clippy (Group H + B10).

**Vector catalogue at `references/attack-vectors/dlt-infra-attack-vectors.md`** — 77 vectors across 9 groups with per-entry **Golden Signature** column. The Golden Signature is the exact substring the deterministic backend emits when the bug is confirmed; Stage 3's tool-confirmation model uses substring matching to turn LLM hypothesis into tool-confirmed verdict.

| Group | Title | Count | Tool | Owner |
|-------|-------|-------|------|-------|
| A | Memory Corruption & UB | 10 | Miri | Angle 1 |
| B | Unsound Unsafe Abstractions | 10 | Rudra + Kani + Miri | Angle 2 |
| C | Integer Overflow & Arithmetic | 8 | Kani | Angle 3 |
| D | Concurrency & Sync Primitives | 8 | Loom + Miri | Angle 4 |
| E | Cryptographic Failures | 8 | Manual + Clippy | Angle 5 |
| F | Resource Exhaustion & DoS | 7 | cargo-fuzz / afl.rs | Angle 6 |
| G | Error Handling & State Machine | 8 | stateright / Kani / fuzz | Angle 7 |
| H | Supply Chain & FFI | 8 | cargo-audit / cargo-deny / Clippy | Angle 8 |
| I | DLT-Specific Logic | 10 | stateright / property-test | Angle 7 |

**Source**: DeepSeek `deep6.md` (Chunk 2 spec), integrated 2026-05-12. Cross-mode discipline: this catalogue loads only in `infra` mode; SC mode continues to use V1-V132 in `rust-attack-vectors.md`.

### Files added — Chunk 2

- `references/hacking-agents/infra/memory-safety-agent.md`
- `references/hacking-agents/infra/unsafe-trait-agent.md`
- `references/hacking-agents/infra/arithmetic-agent.md`
- `references/hacking-agents/infra/concurrency-agent.md`
- `references/hacking-agents/infra/crypto-misuse-agent.md`
- `references/hacking-agents/infra/resource-exhaustion-agent.md`
- `references/hacking-agents/infra/logic-state-machine-agent.md`
- `references/hacking-agents/infra/supply-chain-ffi-agent.md`
- `references/attack-vectors/dlt-infra-attack-vectors.md`

### Added — Chunk 3 (deterministic verification stage)

DeepSeek delivered the Chunk 3 spec (`deep8.md`): the entire Stage 3 verification procedure for infra mode, replacing both the SC-mode tier ladder (`poc-standards.md`) and the SC-mode adversarial review (Pass A/B/C/D in `adversarial-review.md`). The architectural simplification: in infra mode, the deterministic backend (Miri / Kani / Loom / Rudra / cargo-fuzz / cargo-audit / cargo-deny / cargo-geiger / Clippy security-lints) is the gate. Tool output IS the verdict. Verdicts are **CONFIRMED** (golden signature matched), **DISPROVED** (tool proves absence within bound), or **INCONCLUSIVE** (no successful run, manual vector, or harness compilation failure). Only CONFIRMED findings advance to Stage 4.

The integrated spec preserves DeepSeek's content with adjustments for:
- **File naming**: saved as `references/infra-verification-stage.md` (descriptive; parallels `pipeline-overview.md`) rather than DeepSeek's generic `verification-stage.md`.
- **FINDING schema alignment**: the Stage-2-to-Stage-3 input now uses Argus's standard FINDING block (mode-independent `weaponization_check` / `reachability_check` / `code_comment_scan`) plus a `verification_plan:` extension with `vector_id`, `vector_group`, `primary_tool`, `golden_signature`, `miri_flags`, `kani_unwind`, `harness_suggestion`. The angle MUST cite a `vector_id` matching `dlt-infra-attack-vectors.md`; signatures are never invented.
- **Toolchain prerequisite**: invokes `scripts/install-infra-deps.sh --dry-run` at Stage 3 start (parallel to SC mode's `install-deps.sh`). Missing tools trigger `AskUserQuestion` (install / skip-with-coverage-cap / cancel). Missing-with-cap auto-marks affected groups INCONCLUSIVE.
- **Audit-mode routing alignment**: `audit-modes.md` Stage 3 row updated to point at `infra-verification-stage.md` (replaces `poc-standards.md` in infra mode). Stage 4 row updated to note Pass A/B/C/D are NOT run in infra mode — only the Impact × Reachability matrix for severity (Chunk 4).
- **Manual-vector enumeration**: 6 vectors (E02, E03, E08, G07, I09, I10) are honestly tagged as not-fully-automatable and default to INCONCLUSIVE → `manual-queue.md`. The pipeline does not fabricate verdicts for these.
- **False-positive allowlist scaffolding**: `references/infra-fp-allowlist.md` slot reserved (file starts empty; populated during v0.3.0 calibration runs with known Miri / Kani FPs on FFI boundaries).
- **Per-finding verdict schema**: `$RUN_DIR/3-verification/F-NN/verdict.md` with tool command, golden_signature, golden_signature_matched, evidence_path, inconclusive_reason, tool output excerpt, reproduction command, next-stage routing.

**Tool selection by vector group** (from `infra-verification-stage.md`):

| Group | Primary tool | Fallback | Wall-clock per finding |
|-------|-------------|----------|------------------------|
| A — Memory Corruption | Miri (nightly) | Kani | 30s – 3 min |
| B — Unsound Abstractions | Rudra → Kani → Loom | manual | semi-auto |
| C — Integer Overflow | Kani `--unwind N` | libfuzzer | up to 10 min |
| D — Concurrency | Loom (or Miri `-Zmiri-detect-data-races`) | manual | up to 2 min |
| E — Cryptography | Custom harness + Clippy | dudect | 30s – 5 min |
| F — DoS | libfuzzer 5min default | static (manual) | 5 min |
| G — Error Handling | Kani | Loom | harness-dependent |
| H — Supply Chain | cargo-audit + cargo-deny | manual | < 10s |
| I — DLT-specific | proptest / Kani / stateright | fuzzer | harness-dependent |

**Stage-3 → Stage-4 contract**: only CONFIRMED findings advance. DISPROVED → `$RUN_DIR/3-verification/_disproved.md` (terminal). INCONCLUSIVE → `_inconclusive.md` + `manual-queue.md` (never auto-submitted).

**What this closes from `ARGUS_AUDIT.md`** (cited inline in `infra-verification-stage.md`'s coda):
- C-2 (judge-acceptability not truth)
- C-3 (orchestrator single-point-of-failure on Pass C/D)
- S2-8 (`bug_reachability_proof` unverifiable)
- S3-1 (80% certainty floor arbitrary)
- S4-1 through S4-9 (all Pass A/B/C/D weaknesses — N/A in infra mode)

**What this does NOT close**:
- C-1 (calibration debt) — only partially; Stage-4 matrix replaces Pass D English rubric but the matrix is still hand-built.
- H-1 (vector library organization) — new 9-group catalogue is more orthogonal but still hand-curated.
- S2-4 (`reachability_check` naive grep) — unchanged; `rust-analyzer` caller-graph extraction is v0.3.0+ candidate.
- Manual-vector gap (E02/E03/E08/G07/I09/I10) — INCONCLUSIVE is honest but doesn't auto-find these.

### Files added — Chunk 3

- `references/infra-verification-stage.md` (Stage 3 deterministic verification spec)
- `scripts/install-infra-deps.sh` (toolchain installer for Miri / Kani / cargo-fuzz / cargo-audit / cargo-deny / cargo-geiger / rudra)

### Files modified — Chunk 3

- `references/audit-modes.md` — Stage 3 row updated (points at `infra-verification-stage.md`); Stage 4 row updated (Pass A/B/C/D NOT run in infra mode).

### Added — Chunk 4 (Stage 4 Impact × Reachability matrix + working scripts)

DeepSeek delivered the Chunk 4 spec (`chunk4.md`): the entire Stage 4 procedure for infra mode, replacing SC-mode `adversarial-review.md` Pass A/B/C/D. Severity is the **deterministic product of Reachability × Impact** with up to one downgrade. No LLM judge, no English rubric — a matrix lookup over data extracted from `rust-analyzer` (reachability) and the vector catalogue (impact).

The integrated spec preserves DeepSeek's content with adjustments for:
- **File naming**: saved as `references/infra-impact-analysis.md` (descriptive; broader than just "severity matrix" since it also covers reachability + impact + downgrade rules + output schema).
- **Output-path convention**: `$RUN_DIR/4-impact/F-NN.md` parallel to other stage output paths.
- **Real Python scripts** in place of DeepSeek's pseudocode (see below).
- **audit-modes.md routing aligned**: Stage 4 row now points at `infra-impact-analysis.md` (was `infra-severity-matrix.md` placeholder from Chunk 1).
- **`reachability_confidence` flag** when `rust-analyzer` indexing fails or is unavailable — finding does NOT auto-advance to Stage 5; user must review manually.
- **Dynamic-dispatch over-approximation** explicitly defined: if any implementor of a trait is reachable, the target is reachable. Prefers FP over FN at the reachability gate; Stage 5/6 apply realism downstream.

**Reachability buckets** (per finding):

| Bucket | Definition |
|--------|------------|
| Remote | Reachable from unauthenticated network entry point. No creds. |
| Authenticated | Requires valid creds, staked validator slot, or trusted-peer-set membership. |
| Local | Requires shell access or filesystem write on the host. |
| Test-only | Only reachable from `#[cfg(test)]` / `tests/` modules → demoted to LEAD. |

**Impact tiers** (per finding, mapped from `vector_id`):

| Tier | Vector groups |
|------|---------------|
| System Compromise | A (most), I09 |
| Data Corruption | A03/A08/A09/A10, B (most), G (most) |
| Funds At Risk | I02/I03/I06, E01/E05, C05 |
| Denial of Service | F (all), D01/D02/D07, G02 |
| Confidentiality Breach | E02/E03/E08, A05, I10 |
| Integrity Weakening | B03/B05/B07, E04/E06/E07, I01/I04/I07 |

**Severity matrix** (3 × 6 cells):

| ↓ Impact \\ Reach → | Remote | Authenticated | Local |
|---------------------|--------|--------------|-------|
| System Compromise | CRITICAL | CRITICAL | HIGH |
| Data Corruption | CRITICAL | HIGH | MEDIUM |
| Funds At Risk | CRITICAL | HIGH | MEDIUM |
| Denial of Service | HIGH | MEDIUM | LOW |
| Confidentiality Breach | HIGH | MEDIUM | LOW |
| Integrity Weakening | HIGH | MEDIUM | LOW |

Test-only → INFORMATIONAL (terminal). Unclear → INFORMATIONAL fallback (manual review).

**Downgrade rules** (at most one applies; one tier down only):
- **TRUSTED-ROLE-REQUIRED** — attacker must already hold validator slot / trusted-peer membership / admin key.
- **PRACTICAL-DIFFICULTY** — requires >1% stake / significant hash power / collision in space >2⁶⁴.
- **BOUNDED-IMPACT** — worst case limited to a single user or small capped amount.
- **UPGRADEABLE** — vuln is in upgradeable runtime, patchable without hard fork.

**No UPGRADE rule.** Matrix output is the ceiling. Preserves deterministic-mechanical guarantee.

### Files added — Chunk 4

- `references/infra-impact-analysis.md` (Stage 4 spec — reachability + impact + matrix + downgrade rules + output schema)
- `scripts/reachability.py` (working — reverse-BFS over `rust-analyzer` call-graph JSON; conservative dynamic-dispatch over-approximation; parses Stage-1 `entry-points.md` for manual overrides; emits JSON verdict)
- `scripts/assign_severity.py` (working — full `VECTOR_TO_IMPACT` table over all 77 V124-style vectors + matrix lookup + downgrade application; smoke-tested on A01/I06+TRUSTED-ROLE-REQUIRED/A07-test-only with correct outputs)

### Files modified — Chunk 4

- `references/audit-modes.md` — Stage 4 row updated to point at `infra-impact-analysis.md`.

### What this closes from `ARGUS_AUDIT.md`

- **H-2** (severity tiers are English; two runs may disagree) — replaced by deterministic 3×6 matrix.
- **H-4** (rebuttal-quality classifier load-bearing) — N/A in infra mode; no Pass C rebuttal logic.
- **S2-4** (`reachability_check` naive grep) — replaced by `rust-analyzer` call-graph traversal in `scripts/reachability.py`. The Stage-2 grep becomes a quick prefilter.
- **S4-7** (C4 historical-severity table miscalibration) — N/A in infra mode.
- **A-2** (severity unidirectional after Pass D) — preserved by design; no UPGRADE rule.

### What this does NOT close

- **C-1** (calibration debt) — partially. Matrix cell values are hand-built from community-standard CVSS-like axes; not validated against an empirical DLT-infra finding corpus. Calibration sweep against W3SA + future DLT-infra corpus is post-v0.3.0 work.
- **A-6** (single Rust ecosystem per run) — unchanged; matrix doesn't address multi-ecosystem hybrids.
- Downgrade-rule boundary conditions remain judgmental: "trusted peer set" vs "any-peer" can be ambiguous in some p2p designs. The downgrade-evidence field is mandatory but the orchestrator doesn't verify the evidence claim.

### Remaining for v0.3.0 (Chunk 5)

Tracked in `ARGUS_V0.3.0_PLAN.md`. Chunk 5 (Stages 5/6/8 — disclosure paths, CVE triage, infra report templates, README/playbook updates, VERSION bump to 0.3.0) awaits DeepSeek's `chunk5.md` spec. DeepSeek's chunk4.md preview said: *"Chunk 5 (submission templates + integration wiring) is next when you're ready."*

---

## [0.2.6] — 2026-05-12

Literature-driven release. Driven by an external review pass (DeepSeek prompts) producing on-chain-Rust-specific source URLs (Neodyme, OtterSec, Trail of Bits Not So Smart Contracts/Pallets, Sec3, Zellic), the W3SA + Scout labeled empirical datasets, and the academic landscape on fix-subsumption / patch-completeness. This release does not change the pipeline shape — it ships catalogue additions, a Stage 9 calibration prior, and an eval-runner stub for the empirical-corpus gap acknowledged in `ARGUS_PLAYBOOK.md` §14.

### Added — `references/attack-vectors/rust-attack-vectors.md`

Nine new vectors covering Token-2022 extension classes, Substrate FRAME hazards, and a TOCTOU pattern not previously in the library. Each entry carries a `Refs:` line pointing at the canonical Neodyme / OtterSec / Trail of Bits / Sec3 publication where the pattern was codified.

- **V124 — Interest-bearing / rebasing token accounting drift.** Token-2022 `InterestBearingConfig` (or rebasing wrappers) mutates `account.amount` mid-life without an explicit `transfer`. Vaults reading `total_assets()` live from `account.amount` inflate share price; withdrawals over-distribute. Distinct from V68 (transfer-fee at deposit). Ref: OtterSec Token-2022 Audit.
- **V125 — SPL Token-2022 permanent-delegate authority abuse.** Token-2022 mint with `PermanentDelegate` extension; protocol allowlist accepts the mint without disclosing the delegate; delegate (or compromise of its key) clawbacks user balances. Ref: OtterSec Token-2022 Audit.
- **V126 — Multisig signer-threshold replay (Squads / Serum-style).** Approval `Vec` not marked consumed atomically with execution, OR multisig nonce not bumped post-execution. Same approval set replays. Adjacent to V61 when multisig threshold math itself wrong. Ref: OtterSec formal verification of Squads v3/v4.
- **V127 — Substrate `StorageMap` non-cryptographic hasher collision.** `Twox64Concat` (non-cryptographic) over attacker-controllable `Key`. Attacker finds colliding pair; overwrites another live entry or reads another user's value. `Blake2_128Concat` safer but still vulnerable on very short keys. Ref: Trail of Bits Not So Smart Pallets.
- **V128 — XCM barrier bypass / asset-trap injection.** Parachain `XcmConfig::Barrier` permissive filter (e.g., `AllowUnpaidExecutionFrom<Everything>` leftover from test config), OR `AssetTrap::claim` not gated by origin equality. Refs: TOB Not So Smart Pallets; Polkadot forum.
- **V129 — BEEFY / GRANDPA validator-set handoff race.** Light-client processes finality proof under previous validator set after destination advanced. Distinct from V91 (general rotation race); V129 is BEEFY/GRANDPA-specific era-boundary failure where `authority_set_id` not strict-equality-checked. Refs: TOB publications; Polkadot Alliance Legion forum.
- **V130 — Read → CPI → re-read TOCTOU on the same account.** Instruction reads `account.field`, performs CPI / submessage reply that mutates it, re-reads without acknowledging mutation. Distinct from V8 (CPI re-entry, different program re-enters caller) and V45 (read-only re-entrancy, cross-protocol query mid-update); V130 is single-program inconsistency across CPI boundary. Refs: Neodyme common pitfalls; TOB Not So Smart Contracts Solana.
- **V131 — SPL Token-2022 confidential-transfer ZK proof soundness gap.** ElGamal + ZK range / equality proofs mishandled: ciphertext malleability, range-proof bit-width mismatch, or auditor-key bypass. Ref: OtterSec Token-2022 Audit; Solana confidential-transfer spec.
- **V132 — Cancelable vesting clawback / cliff-truncation rounding.** Vesting math truncates toward protocol; clawback formula doesn't subtract `already_claimed`; cliff boundary off-by-one. Ref: public Solana / CosmWasm vesting audits in `2501babe/solana-security-audits` corpus.

Also confirmed (no diff needed) that earlier candidates from the DeepSeek pass were already covered:
- Transfer-fee bypass class → existing V68 + V90.
- Substrate OCW signed/unsigned tx confusion → existing V74 + V75.
- Light-client soundness (general) → existing V76 + V91 + V118 + V119. V129 covers the BEEFY/GRANDPA-specific era-boundary case.

### Added — `references/fix-verification.md` (Stage 9)

New section **"Patch-bypass calibration prior (MANDATORY in PASS verdicts)"**. Every Stage 9 PASS verdict now MUST surface the empirical base rate from Netlas 2025: ~15.5% of security patches require subsequent fixes, 8.05% incomplete, 4.15% fundamentally incorrect. The verdict file gains a `patch_bypass_prior` block listing what could still be missing (sibling locations, follow-up exploit class enabled by fix's new error path, integration breakage in downstream protocols) and explicitly states that multi-patch sufficiency is NOT proven by single-patch analysis.

Additional new sub-sections:

- **Undecidable-patch flag** — when the diff spans more than one logical change and root-cause attribution to a single hunk is ambiguous (per the MONO 2025 "undecidable patch" classifier), set `undecidable_patch: yes` in frontmatter and default verdict to NEEDS REVIEW. The classifier baseline for automated patch tools is wrong ~16.7% of the time on undecidable patches; surfacing the ambiguity is more honest than a confident PASS.
- **Executable subsumption check (v0.2.x candidate, NOT YET IMPLEMENTED)** — when Stage 9 is invoked as part of Stage 8 Phase 8a-pre fix-subsumption ("would A's patch also prevent B's exploit?"), the strongest evidence is executable: apply A's diff to a worktree, re-run B's Stage 3 PoC, observe whether it still fires. Argus does not automate this yet. Until it does, Stage 9 in subsumption context defaults to NEEDS REVIEW unless the user reports a manual executable check.
- **References section** — Netlas 2025, MONO (arXiv:2506.03651), DISPATCH (USENIX Security 2021), TreeVul (ICSE 2023), DualLM (NDSS 2026 / arXiv:2509.22796).

Per-finding output schema extended with `## Patch-bypass prior` (mandatory for PASS) and `## Undecidable-patch flag` sections.

### Added — `evals/w3sa-runner.md`

Stub for empirical-calibration runs against the two public Rust-chain labeled finding datasets:

- **W3SA Solana Benchmark** (`huggingface.co/datasets/almanax/w3sa-bm-solana`) — 7 Anchor projects (Invariant, Ellipsis Labs, Synthetify, Clone, Haven, Drift, Port Sundial), 42 audit bugs + 19 injected, with detection rates already published for GPT-4o / Claude-3.5 / o1-mini.
- **Scout Substrate Dataset** (Polkadot Alliance Legion / LAFHIS / UBA) — pallet-level audit reports + mapped issues + remediated code.

The stub documents the dataset shape, the per-stage comparison procedure (severity-calibration confusion matrix, Stage-3 PoC-tier distribution by ground-truth severity, Stage-5 score distribution by Stage-8 outcome), the output schema (`calibration.md` alongside `summary.md`), and the calibration deltas it would produce against the five currently-hand-tuned heuristics:

- C4 historical-severity heuristic (Pass D, 7 bug-shapes default Medium)
- 80% Stage 3 certainty floor
- Stage 5 subtractive scoring deductions
- Confidence-model deductions (-20 partial path, -25 unverified external claim, etc.)
- Phase 8a-pre dedupe overlap thresholds (0.5 / 0.3 / 0.15)

The stub is not yet runnable — it requires adapters that translate W3SA's HF parquet rows and Scout's git-LFS layout into Argus benchmark frontmatter (`scripts/w3sa-adapter.py` and `scripts/scout-adapter.py` are TODO).

### Why this matters

The vector additions close concrete coverage gaps in Token-2022 extension behavior, Substrate FRAME hazards, and the read-CPI-re-read TOCTOU pattern — bug shapes confirmed present in real audit reports (cited inline per-vector) that V1–V123 did not catch.

The Stage 9 prior is the first empirical calibration anchor in the pipeline: every other gate's confidence is hand-tuned. Surfacing the 15.5% patch-bypass rate gives users (and the orchestrator) a population-level prior to weigh against single-patch optimism.

The W3SA runner stub names the calibration debt explicitly. The pipeline has produced honest heuristics tuned against ~10 swafe + Reflector data points; the next release that closes the stub-to-runnable gap is where those heuristics meet ground truth.

### Files updated

- `references/attack-vectors/rust-attack-vectors.md` — V124–V132 added with `Refs:` lines.
- `references/fix-verification.md` — patch-bypass prior, undecidable-patch flag, executable-subsumption note, references section, output-schema extension.
- `evals/w3sa-runner.md` — new file; stub for empirical-calibration runs.
- `VERSION` — `0.2.6`.

### Deferred to v0.2.7+

- **Adapters** (`scripts/w3sa-adapter.py`, `scripts/scout-adapter.py`) to make the W3SA + Scout runs actually executable.
- **Executable fix-subsumption check** — automated worktree apply + PoC re-run when Stage 9 is invoked in Stage 8 Phase 8a-pre fix-subsumption context. Requires worktree-management infrastructure Argus does not have today.
- **Calibration sweep**: once adapters exist, run the W3SA + Scout sweep and produce concrete adjustment proposals for the five hand-tuned heuristics enumerated in `w3sa-runner.md`.

---

## [0.2.5] — 2026-05-10

Structural reachability release. Driven by Argus run on Monero Oxide (2026-05-09T15:15:43Z, ~7 hours wall-clock). Pipeline advanced F-15 (Decoys `select_n` u64 underflow → wallet panic) to SUBMIT. User invoked the standalone Judge skill post-pipeline → verdict INVALID. The bug is structurally unreachable: line-52 floor (`highest >= ring_len + 60`) plus the line-99 same-line protection check (`(highest - len) < ring_len → return InterfaceError`) form a complete defense. Worst-case all-locked-daemon trace exits cleanly at iter 5 with `len=61` (check `15 < 16` fires).

### Honest framing of what was wrong

This release was originally drafted as a keyword-trigger fix: when Pass B raises challenges containing phrases like "fires before" / "spins before" / "harder than stated", Pass C escalates to reachability re-trace. The user correctly observed that this is reactive — pattern-matching the specific language I was shown rather than fixing the underlying structural gap.

The deeper issue: Argus has function-level reachability (`reachability_check`, v0.1.8) and branch-level reachability (`branch_reachability_check`, v0.1.12), but no **structural reachability proof for the specific bug state inside the cited function**. F-15's cited function was reachable, the cited branch was reachable, but the bug state inside the branch was prevented by a same-line guard plus inductive loop bounds. Argus had no methodology requiring the angle to prove the bug state is reachable from function-entry preconditions through the loop's progression.

v0.2.5 ships the structural fix.

### Added — Mandatory `bug_reachability_proof` schema field at Stage 2 (`shared-rules.md`)

Every FINDING claiming a code-location bug (panic, OOB, underflow/overflow, livelock, divide-by-zero, OOG/CU-exhaustion at a specific call site, assertion failure, "function reaches state X with attacker input Y") MUST include a four-component proof:

1. **`bug_state_predicate`** — precise statement of the state required for the bug to manifest.
2. **`function_entry_predicate`** — what holds at function entry from any public-entry caller (parameter validation, caller-supplied bounds, constants).
3. **`loop_progression_model`** — how loop variables evolve per iteration for worst-case attacker-controlled inputs (or "n/a — straight-line code").
4. **`reachability_argument`** — step-by-step trace from function-entry-predicate to bug-state-predicate.

Plus a `proof_outcome`: REACHABLE | UNREACHABLE | INCONCLUSIVE.

Outcomes:
- REACHABLE → file as FINDING.
- UNREACHABLE → drop the candidate (do not file as LEAD; the bug doesn't exist).
- INCONCLUSIVE → file as LEAD; Stage 4 Pre-Pass re-attempts the proof.

Findings that don't claim a code-location bug (design / threat-model / documentation class) record `bug_reachability_proof: n/a`.

### Added — Same-line protection-check pattern recognition

When the cited bug expression is part of a guard expression on the same line, the proof has near-automatic UNREACHABLE outcome. Recognized patterns:

- `if a >= b { a - b } else { ... }` — bug "a - b underflows" → UNREACHABLE
- `if (a - b) < c { return Err }` — bug "a - b underflows" → UNREACHABLE in production with adjacent floor
- `if idx < array.len() { array[idx] }` — bug "OOB" → UNREACHABLE
- `let safe = checked_add(a, b)?; ...` — bug "overflow" → UNREACHABLE (`?` propagates)
- `take(N).enumerate()` — bug "iteration overruns N" → UNREACHABLE
- `if iters >= MAX { return }` inside the loop — bug "unbounded iteration" → UNREACHABLE

When the cited line matches one of these patterns, the angle MUST emit `proof_outcome: UNREACHABLE` and drop the candidate UNLESS it can construct a counter-proof showing the guard fails (guard-internal overflow, attacker bypass via different path).

### Added — Optional language signals (secondary)

If the angle's own internal reasoning contains phrases like "spins indefinitely before" / "fires before" / "harder than stated" / "same-line guard" / "per-iter check" / "MAX_ITERS fires first" / "structurally unreachable" / "inductive invariant prevents" — and yet `proof_outcome` is REACHABLE — the angle MUST add an `internal_contradiction_note` explaining why the proof is REACHABLE despite the language. Stage 4 Pre-Pass will scrutinize the contradiction.

This is the keyword-list, kept as a SECONDARY signal — not the primary detection mechanism. The structural proof is primary.

### Added — Stage 4 Pre-Pass bug-state reachability proof verification (`adversarial-review.md`)

New mandatory Pre-Pass that runs SECOND (after scope/code-comment Pre-Pass, before External Research). The Pre-Pass:

1. Reads the four proof components verbatim from the FINDING.
2. Independently re-verifies each against the cited code (orchestrator running the verification is NOT the same subagent that produced the FINDING — independent re-verification, not self-review).
3. Applies the same-line protection-check special case if present.
4. Builds an independent worst-case trace with attacker-controlled inputs.
5. Verdicts:
   - Proof holds → proceed to External Research Pre-Pass.
   - Proof fails → **KILL** with `STATUS: KILL(structurally-unreachable: <which guard fires>)`. Pass A/B/C/D skipped.
   - Inconclusive → proceed to Pass A/B/C/D, force Pass C in `CLOSE_CALL_REVIEW (reachability-inconclusive)` mode.
   - REACHABLE claim with same-line-guard pattern present → demand counter-proof; if absent → KILL.

Why this is upstream of Pass A: Pass A's selector picks 4 entries from 15 categories and may overlook EG (existing-guard) when the bug claim looks like an arithmetic/logic class. The structural proof runs unconditionally before the selector has the option to overlook it.

Why this is upstream of External Research: structural reachability is a function-internal question; no point spending External Research budget on a finding whose bug state is structurally unreachable.

### Added — EG-7 and EG-8 invalidator categories (Pass A backup)

Pass A's Existing-Guard catalogue extended:

- **EG-7**: Same-line / same-statement protection check. Near-automatic HIGH-confidence HOLDS unless the orchestrator can prove the guard itself fails.
- **EG-8**: Inductive loop-bound prevents bug state. Confirmed via independent worst-case trace.

These exist as backups for the case where the Stage 4 Pre-Pass proof was missing, malformed, or wrongly REACHABLE despite a same-line guard. The catalogue now has 15 categories (UP/CP/DT/EG/US/SH/DI/TI/SC/IM/AM/OS/TR/CR/IL) with EG expanded from 6 to 8 entries.

### Why this isn't a strictness change

Same gate logic. The change is requiring the angle to PROVE the bug state is reachable before claiming the bug exists, and requiring Stage 4 to independently RE-VERIFY the proof.

Pre-v0.2.5: an angle could claim a panic at a code location without showing the panic state is reachable; Pass C might catch it via Pass B challenges, but only when Pass B happened to raise the right argument and Pass C happened to weight it as invalidation rather than severity-softening. F-15 demonstrated both could fail simultaneously.

Post-v0.2.5: the proof is mandatory at Stage 2 emission, mandatory re-verification at Stage 4 Pre-Pass (BEFORE the selector or research budget is spent), and EG-7/EG-8 in Pass A as backup. Three independent layers catching the same class of error.

This is structural — it works regardless of whether the language matches "fires before" or "spins before" or any other surface phrasing.

### Files updated

- `references/hacking-agents/shared-rules.md` — `bug_reachability_proof` schema field mandatory; same-line protection-check patterns; optional language signals as secondary.
- `references/adversarial-review.md` — Stage 4 Pre-Pass bug-state reachability proof verification; EG-7 and EG-8 invalidator categories; Pass A catalogue header note (15 categories with EG expanded).
- `VERSION` → `0.2.5`.

### Expected effect on a re-run vs. Monero Oxide

Stage 2 angle producing F-15 must now build the proof:
- `bug_state_predicate`: "underflow occurs IFF do_not_select.len() > highest_output_exclusive_bound at line 99 subtraction"
- `function_entry_predicate`: "highest >= ring_len + 60 (line-52 floor)"
- `loop_progression_model`: "iter k starts at len = 1 + (k-1)*(ring_len-1) under all-locked-daemon"
- `reachability_argument`: stepping through, the per-iter check `(highest - len) < ring_len` fires when len > 60, which happens at iter 5 (len=61) for ring_len=16. Bug state requires len > highest = 76, requiring iter 6 — but iter 5 already returned InterfaceError.

The proof's correct outcome is UNREACHABLE. The angle drops F-15 at Stage 2 and never produces it as a candidate FINDING.

If the angle wrongly emits `proof_outcome: REACHABLE`, Stage 4 Pre-Pass re-verification independently traces the loop, identifies the same line-99 + line-52 + MAX_ITERS defense, and KILLs.

If the angle wrongly produces F-15 as a FINDING with REACHABLE proof, Pass A's selector should pick EG-7 (same-line protection-check) and EG-8 (inductive loop-bound). Either fires HIGH HOLDS → KILL.

Three independent layers catching F-15. The Judge invalidation that prompted this release would now happen at Argus's Stage 4 Pre-Pass, not post-pipeline.

### Tracked for v0.2.6+

- Run v0.2.5 against past Argus runs (swafe, SP1, Reflector) to verify no regression on findings that were correctly REACHABLE.
- Consider extending the proof requirement to non-code-location findings (design / threat-model class) — currently those skip the proof.
- Examine other Argus-produced findings invalidated by post-pipeline review for additional methodology gaps. Each Judge invalidation that captures reasoning the pipeline should have produced is a methodology-fix candidate.

---

## [0.2.4] — 2026-05-09

PoC empirics calibration release. Claude.ai web ran the v0.2.3 follow-up research prompt (`research/poc-claude-web-prompt.md`) and returned ~115 catalogued findings across Code4rena / Sherlock / Cantina / Immunefi with verbatim judge quotes and harness-acceptance data. Result: v0.2.3 was directionally correct but had two empirical errors. v0.2.4 fixes both.

### What the research found

**Acceptance rate by harness type (115 findings)**:

| Harness | Acceptance rate |
|---------|------------------|
| anchor-test-localnet | 92.5% |
| cw-multi-test | 92.7% |
| substrate-mock (`mock!`/`ExtBuilder`) | 90.9% |
| BanksClient / SolanaProgramTest / bankrun | 90.0% |
| solana-mainnet-fork | 91.7% (small N) |
| try-runtime / wasmd-localnet | 100% (small N) |
| unit-test-only | 73.7% |
| **written-derivation** | **57.6%** |
| exempt-citation-only | 20.0% |

**Empirical conclusion**: the 2.5pp gap between anchor-test-localnet and BanksClient is **statistical noise**. The **35pp cliff** sits between runnable harnesses and written-derivation, NOT between "real validator" and "integration test." v0.2.3's Tier-1-vs-Tier-2 distinction was empirically refuted on contest platforms.

**Immunefi exception confirmed**: per Immunefi PoC Guidelines, *"The smart contract PoC should always be made by forking the mainnet using tools like Hardhat or Foundry. No unit test PoCs will be accepted."* Drift-class programs override stricter: *"For critical and moderate bugs, we require a proof of concept done on a privately deployed mainnet contract."* Marinade: *"All smart contract bug reports must come with a PoC..."*

### Changed — Tier 1 + Tier 2 collapsed (contest platforms)

`references/poc-standards.md` rubric:

- **Tier 0** — Mainnet-Fork / Live-State E2E: 95-100
- **Tier 1** — Validated Integration: 88-94 (any harness running real program code unmodified — anchor-test-localnet, BanksClient, cw-multi-test, wasmd, mock.rs, Soroban Env, etc.)
- **Tier 2** — Unit Test: 75-87
- **Tier 3** — Written Derivation: 40-70
- Exempt allowlist: 75 baseline

The pre-v0.2.4 "Tier 1 = real validator only" / "Tier 2 = mocked-runtime" split is removed. On contest platforms, both run real program code at statistically equivalent acceptance rates.

### Added — Platform-aware harness escalation

When `target_platform == Immunefi`, the rubric SHIFTS:
- Tier 0 (Mainnet-Fork) becomes the DEFAULT, not Tier 1.
- Tier 1 is the FALLBACK, allowed only when the program's bounty page explicitly endorses test-suite fallback.
- v0.2.3 had no platform detection; v0.2.4 reads `target_platform` from Stage 6 and applies the shift.

### Added — Per-program PoC clause parsing (Stage 6)

Stage 6 program triage now extracts the bounty page's PoC requirement clause verbatim into 4 new fields:

- `poc_clause_verbatim` — quoted text from bounty page
- `poc_clause_severity` — which severity tiers it applies to (all / critical-only / critical-and-high / informational-only)
- `poc_clause_overrides_platform_default` — yes / no / unclear
- `immunefi_test_suite_fallback_endorsed` — yes / no / unclear (only when target_platform == Immunefi)

This catches Drift-style overrides (mainnet-fork required for Critical/High), Marinade-style "PoC required for all rewards", Compound-style "PoC required for all severities."

### Added — Per-tier verdict.md evidence checklist (Output 7 from research)

Stage 3 verdict.md MUST tick each box for the claimed tier. Missing any item caps certainty at the next-lower-tier ceiling. v0.2.3 said "captured output mandatory" but didn't enumerate items judges look for. v0.2.4 ships the full checklist:

- **Tier 0**: clone command verbatim, fork block/slot pinned, target program ID, exploit tx signature, pre/post-state diff, fix-applied re-run.
- **Tier 1**: test invocation command, captured stdout (with `running N tests` + balance deltas + `PASS`), Cargo.toml deps, attack tx sequence enumerated, post-exploit assertion explicit, **program-under-test source UNMODIFIED + commit hash**, precondition-realism note, fix-applied re-run.
- **Tier 2**: command + stdout + assertion + bridge narrative + no `#[ignore]`.
- **Tier 3**: numbered attack steps + line-cited code refs at commit hash + worked numeric example + justification for no runnable PoC.

### Added — Source-modification discipline (near-automatic kill)

PoCs that inject `panic!` / `println!` / `eprintln!` / `dbg!` into the program-under-test to demonstrate the bug are routinely killed (KF-3a from research; Cantina blog: *"Rust integers have fixed sizes. […] Rust checks for these issues in debug mode, it does not in release mode, which Solana uses by default."*). 

Tier-1 verdicts MUST include:

```
program_under_test_unmodified:
  statement: "Source of <crate>::<module>::<function> is unmodified at commit <SHA>"
  evidence: <git log/diff command output showing no changes>
  exception: <if absolutely necessary, document the modification>
```

Output from PoC code (test wrapper) is acceptable; output from injected statements in the program crate is not.

### Added — Verbatim Tier-0 boot scripts

`references/poc-standards.md` now ships ready-to-paste templates:

- **Solana**: `solana-test-validator --clone <PROGRAM> --clone <ORACLE> --url mainnet-beta --slot <N>`
- **Solana Bankrun fork-lite**: `startAnchor` with mainnet-pulled accounts (lighter-weight Tier-0 alternative)
- **CosmWasm wasmd state-import**: `wasmd query wasm contract-state all` → snapshot → `wasmd init audit`
- **Substrate try-runtime + Acala canonical**: `cargo run --features with-acala-runtime --features try-runtime -- try-runtime --runtime existing create-snapshot --uri wss://... ; ./acala try-runtime ... on-runtime-upgrade snap`
- **Substrate chopsticks alternative**: `npx @acala-network/chopsticks try-runtime --endpoint <wss>`
- **Solana block-replay**: `solana-test-validator --slot <PRE_ATTACK> --clone <ATTACKER> --clone <VICTIM>`

### Refined — CosmWasm bug-class matrix

Two new rows:

- **Gas metering / mispricing / non-determinism (CW)**: cw-multi-test rejected (per Hacken MANTRA Chain audit: outdated CosmWasm risks "stack overflow, gas mispricing, and non-deterministic queries"). Requires real `wasmd` localnet.
- **Source-modified-with-injected-output (any ecosystem)**: near-automatic kill regardless of harness.
- **Target = Immunefi bug bounty (any bug class)**: Tier 0 (mainnet-fork) required by default per Immunefi PoC Guidelines.

### Files updated

- `references/poc-standards.md` — Tier 1+2 collapse, platform-aware escalation, per-tier evidence checklist, source-unmodified discipline, verbatim Tier-0 boot scripts, refined matrix.
- `references/program-triage.md` — 4 new fields for per-program PoC clause extraction.
- `VERSION` → `0.2.4`.

### Expected effect

For contest targets (Code4rena / Sherlock / Cantina): no acceptance-rate change from v0.2.3 in the harness-axis (the research showed v0.2.3's strict tiering was over-cautious; v0.2.4 collapses without losing precision). What WILL change: (1) PoCs that pass the new evidence checklist will be at the upper end of their tier's acceptance band (88-94% → near 94%) because the writeup-quality items are explicit; (2) source-modification kills are caught proactively.

For Immunefi targets: significant change. v0.2.3 would have allowed Tier-1 cw-multi-test as default; v0.2.4 escalates to Tier-0 mainnet-fork. Acceptance lift on Immunefi targets: from ~50% (Immunefi's cw-multi-test default-rejection) to ~90%+ (Tier-0 boot scripts now ready-to-paste).

Drift-class programs: explicit handling. Stage 6 extracts the clause verbatim; Stage 3 enforces it.

### Tracked for v0.2.5+

- Validate v0.2.4 on a fresh post-cutoff Immunefi-targeted run.
- Wormhole-style sysvar-instructions cross-program bug class — gold-standard PoC pattern needs its own template.
- Substrate runtime-upgrade / migration bug class — try-runtime template needs more concrete examples.

---

## [0.2.3] — 2026-05-09

PoC-quality release. Driven by user observation that Argus's PoCs were getting rejected by judges ~70% of the time. Hypothesis: mocked-runtime harnesses (BanksClient, cw-multi-test, pallet mock.rs) were being treated as Tier-1 E2E when judges actually distinguish them from real-validator runs.

Research (Codex prompt + Claude Web prompt + 3 parallel Argus Explore agents on Solana / CosmWasm / Substrate) returned a more nuanced picture than the original hypothesis. v0.2.3 ships the calibrated truth.

### What the research actually found

- **Solana**: Public C4/Sherlock judging data does NOT show judges explicitly flagging BanksClient as a rejection criterion. Lavarage H-01 (accepted High) used `anchor test` localnet with captured output. Orderly Sherlock #69 (accepted Medium) was *written-derivation only*. The discrimination function is **"execution + captured output"** vs. "description alone" — not which harness produced the execution.
- **CosmWasm**: Clear bug-class × harness pattern. `cw-multi-test` accepted ~95% for state-machine, arithmetic, access control. Rejected for IBC, cross-chain, fee-on-transfer hooks, gas metering, custom Cosmos message dispatch — those need `wasmd` localnet. CWA-2025-006 (Feb 2025) is a documented case.
- **Substrate**: `mock.rs` runtime IS standard and IS accepted as Tier-1. HydraDX H-01 (accepted High) used mock runtime. Try-runtime needed only for runtime-upgrade / migration / multi-block timing bugs.

The user's "70% rejection" experience is real but the root cause isn't "wrong harness" universally — it's the conjunction of (a) PoCs without captured output, (b) bug-class × harness mismatch (e.g., using cw-multi-test for an IBC bug), and (c) no real-state harness for state-dependent bugs.

### Added — `references/poc-standards.md` § Mandatory captured output

Stage 3 verdict.md MUST include captured output for every Tier-1, Tier-2, and Tier-3 PoC. Required artifacts:
- Captured stdout/stderr from the test run
- Transaction hash / signature / block height (for real-validator runs)
- Quoted assertion failures from the buggy build + assertion successes from the fixed build
- Real numeric values (gas / CU / weight) — not "expected"

A PoC that compiles but doesn't have captured output caps at Tier-3 certainty (60-79). A PoC with captured output that demonstrates buggy behavior AND verifies the fix lands in the upper half of its tier.

### Added — `references/poc-standards.md` § Bug-class × harness matrix

The "Tier 1 = any real harness" rule conflated two different things. v0.2.3 ships an explicit matrix mapping bug classes to required harness tier:

- **Mocked-runtime sufficient** (Tier-2 publishable): math, arithmetic, overflow, state-machine logic, access control, signer checks, Borsh / serde / scale-codec deserialization, storage mutation, pure ZK circuit-constraint.
- **Real-node required** (mocked-runtime insufficient — must escalate to Tier-1): IBC packet handling, cross-chain ordering, fee-on-transfer / Token-2022 transfer-hook math, MEV / sandwich / frontrun ordering, custom Cosmos message dispatch / sudo, gas metering edge cases, runtime-upgrade / migration / `set_code` timing.
- **Mainnet-fork required** (Tier-0 — see new tier below): oracle staleness against actual feeds, liquidity-dependent attacks against real pool reserves, validator-set / consensus / finality, bridge / cross-chain supply.
- **Cross-program CPI integrity, re-entry via callbacks**: partial — mocked CPI may not catch all cases; escalate when CPI graph is non-trivial.

Stage 2 angles MUST tag each finding with `bug_class`. Stage 3 reads the matrix and demands the right harness tier. When the matrix forces escalation but toolchain is missing, Stage 3 stops via `AskUserQuestion` to install the required tool.

Mode warning at Stage 8 if any SUBMIT was demoted from required-real-node to Tier-3: "harness-mismatch — N findings demoted; user MUST re-validate with real harness before submission."

### Added — `references/poc-standards.md` Tier 0 (mainnet-fork / live-state E2E)

New gold-standard tier for state-dependent bugs. Means the test runs against state cloned from or derived from real mainnet/testnet, not synthetic data.

Per-ecosystem patterns:
- **Solana**: `solana-test-validator --clone <PROGRAM_ID> --clone-account <FEED_ACCT> --url mainnet`. Boot script in verdict.md MUST quote the `--clone` parameters.
- **CosmWasm**: fork via `wasmd export` from mainnet snapshot, or chain-specific state-import. IBC bugs require simultaneously running `wasmd` instances representing both chains.
- **Substrate**: `try-runtime execute-block --execution wasm --runtime <chain>-runtime.wasm --pre-state-uri ws://archive.<chain>.io:443 --block-number <recent>`.
- **ZK**: replay actual prover invocation against deployed verifier; capture proof + public inputs + accept/reject.

Certainty rubric: Tier 0 = **95-100** (highest possible). When Tier 0 is mandatory (per bug-class matrix): oracle, liquidity, validator-set, bridge, runtime-upgrade-with-real-state.

When Tier 0 is excessive: math / state / access-control / Borsh — those are deterministic in synthetic environments and the boot cost (10-30 min per run) isn't justified.

### Changed — Certainty rubric

Updated to include Tier 0:
- Tier 0 (mainnet-fork): 95-100
- Tier 1 (real validator + synthetic state): 90-100
- Tier 2 (mocked-runtime — sufficient per matrix): 75-89
- Tier 2 (mocked-runtime — INSUFFICIENT per matrix): 60-79 (capped because the matrix says real-node required)
- Tier 3 (minimal reproducer): 60-79
- Tier 4 (written derivation): 30-59
- Exempt allowlist: 75 baseline

### Why this isn't a strictness change

Same gate logic. The change is calibrating "what counts as Tier-1" against actual judge behavior:
- For most bug classes, the existing rule (any real E2E) was correct.
- For specific bug classes (IBC / cross-chain / runtime-upgrade / oracle-state), the existing rule allowed cw-multi-test / BanksClient / mock.rs to pass as Tier-1 when judges treat them as insufficient. v0.2.3 escalates these to real-node or mainnet-fork.

### Files updated

- `references/poc-standards.md` — mandatory captured output, bug-class × harness matrix, Tier 0 (mainnet-fork), updated certainty rubric.
- `VERSION` → `0.2.3`.

### Expected effect

PoCs Argus produces will:
1. Always include captured output (mandatory) — closes the strongest empirical rejection signal.
2. Match the right harness for the bug class — IBC bugs go through `wasmd`, oracle bugs through mainnet-fork, math bugs stay at mocked-runtime.
3. Surface harness-mismatch as a Stage 8 mode-warning when escalation wasn't possible — user knows to re-validate before submission.

Projected PoC-acceptance lift: depends heavily on the bug-class distribution of the run. For a Solana DeFi project with mixed bug classes, 60-75% acceptance → 75-85%. For a pure CosmWasm IBC contest, where the prior rejection was concentrated, lift should be larger.

### Tracked for v0.2.4+

- Per-ecosystem ready-to-paste Tier-0 boot scripts in `references/poc-templates/` (Solana mainnet-fork, wasmd-localnet, try-runtime).
- Auto-detection of bug-class from finding metadata (currently relies on Stage 2 tagging).
- Validation: re-run on a contest with documented PoC rejections (Reflector, MANTRA Chain) and measure acceptance lift.

---

## [0.2.2] — 2026-05-09

Single-rule release. Recovery of an architectural rule from the original Argus design archive (heavyw8t/The-Judge upstream + Claude-works/15a-rust-judge-gap-closure.md §1.1). The rule was flagged critical in the source design ("HARD RULE for Step 4C verdict mapping that prevents real findings from being silently dropped on low-confidence INVALID verdicts") but Argus v0.1.0 partially absorbed it without preserving the LOW/MED-INVALID downgrade rows.

### Changed — `references/adversarial-review.md` § Confidence-aware verdict mapping (Pass C)

The 3-judge panel's verdict was previously mapped INVALID-or-not, with confidence as a record-only field. v0.2.2 ships the matrix:

| Judge verdict | Judge confidence | FINAL action |
|---------------|------------------|--------------|
| INVALID | HIGH | KILL |
| INVALID | MEDIUM | **DOWNGRADE to Low** (NOT KILL) |
| INVALID | LOW | **DOWNGRADE to Low** (NOT KILL) |
| DOWNGRADE | any | DOWNGRADE per judge proposal |
| VALID | HIGH/MED | VALID at original severity |
| VALID | LOW | VALID + `judge_low_confidence_note: true` |

Rationale: a low-confidence INVALID verdict from the judge panel is NOT sufficient evidence to kill a real finding. Asymmetric treatment (low-conf INVALID downgrades; low-conf VALID stays) reflects the cost asymmetry — incorrectly killing a real bug is more expensive than incorrectly preserving a non-bug.

This is the same family of fix as v0.2.1's partial-coverage rebuttal discipline (don't let weak rebuttals kill real findings). v0.2.1 fixed Pass A; v0.2.2 fixes Pass C.

**Behavioral effect**: in the v0.2.0 SP1 / Succinct run, the 3-judge panel's potential 1-1-1 split (steel-manning INVALID HIGH, devil's-advocate VALID MED, balanced INVALID LOW) would have produced an aggregate-low-confidence INVALID. Pre-v0.2.2: the finding gets killed. Post-v0.2.2: downgrade to Low for human review. Preserves the finding without claiming it's submission-grade.

### Added — `judge-summary.json` schema requirement

Pass C verdict file MUST record `judge_verdict`, `judge_confidence`, and `final_action` separately so downstream consumers (Stage 5 / Stage 8) can audit the mapping.

### Files updated

- `references/adversarial-review.md` — Step 4C confidence-aware verdict mapping table.
- `VERSION` → `0.2.2`.

---

## [0.2.1] — 2026-05-09

Calibration release driven by a v0.2.0 swafe Code4rena 2025-11 shadow-audit run. Result on the contest's 7 Mediums:

| Bucket | Recall |
|--------|--------|
| Adjacent (any signal) | 7/7 (100%) |
| Direct SUBMIT-HM | 3/7 (43%) — M-02+M-07 chained, M-06 |
| REFINE bucket | +2/7 (M-01, M-04 stuck due to certainty floor) |
| Mis-classified to LEADs | -1/7 (M-05 wrongly tagged self-harm) |
| Over-downgraded to QA | -1/7 (M-03 by faulty rebuttal) |

Each shortfall was a calibration bug, not a strictness win. v0.2.1 fixes all four.

### Added — `references/adversarial-review.md` § Partial-coverage rebuttal discipline (Pass A)

**The M-03 over-downgrade fix.** When a Pass A invalidator HOLDS based on a guard "covering" the bug, Argus now decomposes coverage explicitly:

```
partial_coverage_check:
  guard_cited: <file:line>
  cases_covered_by_guard: [<enumerated>]
  cases_NOT_covered_by_guard: [<enumerated>]
  finding_resides_in: covered | uncovered | mixed
  verdict:
    covered → KILL holds
    uncovered → KILL DOES NOT hold (rebuttal is partial-coverage; finding survives)
    mixed → DOWNGRADE one tier
```

Mandatory on EG / US / AM HOLDS at HIGH confidence; advisory at MEDIUM.

The swafe M-03 case: Pass A wrongly killed `majority_threshold = div_ceil(n, 2)` (50% on even N) because Pedersen-check covered most threshold concerns. But the off-by-one bug exists in the case Pedersen doesn't cover (even N + exactly N/2 signers). Argus capped at QA; C4 awarded Medium. With the partial-coverage check, F-10 stays at Medium through Stage 4.

This is a logic correctness fix, not a strictness change. A guard that covers most cases doesn't kill a finding for the case it doesn't cover.

### Added — `references/adversarial-review.md` § Cost-bearer-is-protocol distinguisher (SH-*)

**The M-05 mis-classification fix.** Before applying ANY SH-* (self-harm-only) HOLDS, Argus now decomposes the cost path:

```
cost_bearer_check:
  triggering_actor: <who initiates>
  consumer_path: <function(s) downstream that pay the cost>
  consumer_callers: [<protocol / block author / relayer / verifier / writer>]
  cost_bearer_class: writer-only | protocol-and-writer | protocol-only | market-externality
```

If `cost_bearer_class != writer-only`, SH-* HOLDS does NOT apply. The bug imposes externality even if the writer triggered it.

The swafe M-05 case: account holder inflates own `assoc: Vec<>`. Argus tagged self-harm because writer=owner. But the linear scan executes inside `verify_update`, paid for by **block authors / the protocol** — externality. C4 awarded Medium. With cost-bearer check, M-05 stays in candidates at Medium.

The SH-* catalogue tacitly assumed "trigger actor = cost bearer" — frequently false in on-chain systems where state-inflation is cheap once and read-cost is paid forever by every verifier.

### Changed — `references/poc-standards.md` certainty floor

**The M-01 / M-04 promotion fix.** The 80% certainty floor was self-fulfilling in toolchain-skipped runs:

- Toolchain-skipped → max reachable PoC tier is 3 (per existing `poc-standards.md` rule).
- Tier-3 ceiling = 79.
- 80 floor → every finding `DOWNGRADE(refine)` regardless of merit.

v0.2.1 splits the floor:

- **Normal mode** (toolchain available): floor = 80 (unchanged).
- **Toolchain-skipped mode**: floor = 60 (Tier-3 minimum). Findings at certainty 60-79 advance.

Stage 8 emits a mandatory mode warning when ANY SUBMIT advanced under the 60 floor: "shadow-mode-promotion — N findings advanced under reduced PoC tier; user MUST run a real PoC before any platform submission."

Same gate logic, just a reachable threshold. The strictness rule is preserved within the achievable tier.

The swafe case: M-01 (certainty ~75) and M-04 (certainty ~70) were genuine Mediums per C4. Both stuck in REFINE at v0.2.0. With v0.2.1, both promote to SUBMIT under the 60 floor, with a mode-warning surfaced.

### Added — `references/stage1-output-templates.md` § Spec-doc enumeration

**The 6 missed Lows fix.** swafe's `swafe-book/` mdBook spec contained 6 invariants the Rust implementation deviated from. C4 awarded them as Lows (L-02..L-08). Argus v0.2.0 missed all 6 because Stage 1 didn't enumerate spec docs.

v0.2.1 mandates Stage 1 enumeration of:

1. `assets/docs/` (Argus run dir).
2. `<repo>/docs/`.
3. `*-book/` directories (mdBook style).
4. `SPEC.md` / `SPECIFICATION.md` / `DESIGN.md` / `PROTOCOL.md` / `*-spec.md`.
5. README "Specification" / "Properties" / "Invariants" sections.
6. Whitepaper PDFs linked from README (WebFetch where reachable).
7. `audits/` directory.

Output: new file `$RUN_DIR/1-protocol-map/spec-docs-inventory.md` listing every doc + extracted spec-derived invariants. Stage 2's Invariant angle and First Principles angle consume this and emit a FINDING when the implementation deviates from any cited invariant.

**Effect on swafe**: with `swafe-book/` enumerated, all 6 Lows become Stage-2 candidates. The Invariant angle has the spec to compare against.

This is an input-completeness fix, not a strictness change. Argus can't catch spec/impl mismatches without reading the spec.

### Why these are calibration fixes, not loosening

User asked the right question on v0.2.0: "is strictness good?"

Strictness is good when calibrated correctly. v0.2.0 had four cases where strictness was applied wrong:
- Partial-coverage rebuttals killing real bugs (M-03).
- SH-* missing externality (M-05).
- Floor unclearable by construction (M-01, M-04).
- No spec-doc input (6 Lows).

v0.2.1 fixes the calibration. The SUBMIT bucket precision stays the same — H-03-class false positives still get killed. The change is that real Mediums no longer get killed by mis-applied strictness.

### Files updated

- `references/adversarial-review.md` — partial-coverage rebuttal discipline; cost-bearer-is-protocol distinguisher.
- `references/poc-standards.md` — split certainty floor (80 normal, 60 shadow).
- `references/stage1-output-templates.md` — spec-doc enumeration sub-section.
- `VERSION` → `0.2.1`.

### Expected effect on a re-run vs. swafe

If you re-run v0.2.1 on the same swafe shadow-audit:

- M-01 (guardian-share replay) → SUBMIT under 60 floor (was REFINE).
- M-03 (majority off-by-one) → SUBMIT Medium (was QA via faulty rebuttal).
- M-04 (replayable recovery requests) → SUBMIT under 60 floor (was REFINE).
- M-05 (unbounded `assoc`) → SUBMIT Medium (was LEAD as self-harm).
- M-02+M-07 (recover_id wrong field, chained fix) → SUBMIT High (already correct).
- M-06 (degenerate-key social ciphertext) → SUBMIT High (already correct).

Projected v0.2.1 swafe direct SUBMIT recall: **6/7 = 86%** (was 3/7 = 43%). One miss: spec/impl Lows depend on Stage 1 actually reading the swafe-book on the next run.

Mode warning surfaced on M-01/M-04 SUBMITs: "shadow-mode-promotion — run real PoC before submission."

### Tracked for v0.2.2

- Validate v0.2.1 on a fresh post-cutoff contest per the release-gate framework (bucket-4 KPI).
- Add Stage 3.6 Witness Builder validators 4-7 (asset-identity-binding, underconstrained-witness, truncation-rounding, cost-fee-records-cap).
- Establish baseline for the 4 release-gate diagnostic tests (family hold-out, time-split, name-blind, perturbation-stable).

---

## [0.2.0] — 2026-05-09

External-research synthesis release. After v0.1.12's SP1 contest run produced 0% direct recall on clean targets (87.5% adjacent), the user kicked off a 4-stream external-research effort: Codex (code-search), Claude.ai web (long-context audit-report analysis), DeepSeek (methodology critique), ChatGPT Deep Thinking (theoretical framing). All four returned. v0.2.0 ships the triangulated changes.

### The architectural inflection

ChatGPT and DeepSeek converged on the same diagnosis through different framings:

- **ChatGPT**: Argus's gap is a *representation failure*. Adjacent recall is high because the front-end finds suspicious surfaces; direct recall is 0% because the system has no formal object that converts a suspicion into a checkable specific-instance claim. **Recommendation**: replace scalar-confidence-based promotion with a Witness Builder that produces minimal falsifiable bug witnesses.
- **DeepSeek**: 0% direct recall is dominated by the confidence threshold's strictness for incomplete exploit narratives. **Recommendation**: don't lower the threshold; add active promotion mechanisms (3 specific bug-class validators) that fill the missing piece for high-signal LEADs.

DeepSeek's three rules ARE small-scale witness builders. The recommendations are complementary. v0.2.0 ships:

1. **Stage 3.6 Witness Builder** as the architectural slot.
2. **DeepSeek's three rules as the first three witness validators** in that slot.
3. The slot is extensible; v0.2.1+ adds more validators per bug class.

### Added — `references/witness-builder.md` (Stage 3.6)

New stage between Stage 3 (PoC) and Stage 4 (Adversarial). Fires for every LEAD with confidence 30-49 AND a registered bug-class tag. For each, runs a structured validator that either produces a minimal falsifiable witness (promotes to FINDING) or admits it can't (LEAD stays).

Witness contract: typed object with five canonical edges (source, sink, path, preconditions, guard_status) plus falsifier questions and answers. A witness with `survived_falsification: yes` and no critical-edge unknowns promotes to FINDING at confidence 60. Partial witness promotes at 50 with mandatory Pass C re-examination. Failed-falsifier witness DROPS the LEAD entirely.

**v0.2.0 ships 3 validators**:

- **Validator 1 — Critical-Fallback Dead-Code Reverse-Trace**: for LEADs flagging dead-code fallback paths (V101 territory). Builds call-graph from the cited block; if no public-entry path reaches it without a caller's early-return blocking the activating condition, the fallback is dead and the witness exists. Solves SP1 M-05.
- **Validator 2 — Write-Site Enumeration on Security-Critical Variables**: for LEADs mentioning clobber/race/overwrite on `nonce` / `proof` / `entropy` / `challenge` / `seed` / `witness` / `public_inputs` / `vk_root` / `commit*`. Enumerates every assignment site; checks for 2+ writes in same call flow with no read between. Solves SP1 M-06.
- **Validator 3 — Boundary-Fuzz-Guided DoS Promotion**: for LEADs with bug class EXHAUSTION/CPU_DOS/PUBLIC_API_PANIC at FFI boundaries or untrusted-input parsers. Targeted fuzz with strategies (decimal length expansion, invalid hex, truncated bytes, etc.). Crash → witness with crash payload. Solves SP1 M-07.

### Added — `references/hacking-agents/ffi-boundary-agent.md` (11th angle)

New Stage 2 angle dedicated to Rust ↔ non-Rust language boundaries. Owns V85, V111, V112, V113, V120 (and shares V29, V31, V79, V80 with Concurrency angle). Per-input-field × per-parsing-path enumeration is the core discipline (the SP1 M-07 lesson: identifying the boundary as concerning isn't enough — must enumerate each input field's parsing chain). Cooperates with Stage 3.6 Validator 3.

### Added — Stage 1 Verify-Signal Crate Enumeration (in `stage1-output-templates.md`)

Mandatory new sub-section in `hot-zones.md` output. Independently enumerates every in-scope crate that contains security-critical verify/prove logic, regardless of crate size. Four signals (name heuristic / re-export linkage / Cargo.toml dep edge / type flow); a crate matching any signal is added to hot-zones with PRIMARY (≥200 nSLOC) or SECONDARY (smaller) priority. Solves the SP1 M-04 outright miss where `crates/verifier/` was in scope.txt but Argus only swept `crates/prover/`.

### Added — V103–V123 attack vectors (21 new)

Triangulated catalogue additions (4-stream agreement on the top 7; 2-stream agreement on the rest):

**3+ stream agreement** (HIGH confidence):
- V103: Asset-identity / cross-instruction-id binding missing (Solana cross-program)
- V104: Underconstrained witness column (ZK)

**2-stream agreement** (MED-HIGH confidence):
- V105: Truncation-by-design rounding (CosmWasm + Solana)
- V106: Fiat-Shamir transcript incomplete (ZK; Solana ZK ElGamal Critical zero-day pattern)
- V107: Cost / fee-records-cap mismatch (oracles, ZK, generic)
- V109: NFT/CW721 approval residue
- V120: Oracle update hook / TWAP desync
- V121: Public API panic split into 4 sub-shapes (V121a-V121d)

**Single-stream high-frequency** (MED confidence):
- V108: Lifecycle / state-flag bypass (Coded-Estate-class)
- V110: User price-bound / slippage / deadline missing
- V111: Wasm host import resource gap
- V112: Address validation / normalization (CW)
- V113: Forgot-to-save state (CW)
- V114: Submsg-reply-trust (CW)
- V115: Lamport-transfer / rent-exemption edge case (Solana)
- V116: Wrong-slot or ineffective admin config setter
- V117: Same-account alias accounting
- V118: Cross-chain withdrawal recipient binding
- V119: Cross-chain message ordering / idempotency
- V122: Proof / shard metadata clobber on pack / merge (ZK)
- V123: ZK advice/hint value not bound to constrained value

Vector library now has 123 entries (was 102).

### Changed — Severity recalibration in `references/adversarial-review.md` Pass D historical-severity table

Two existing rows recalibrated UPWARD based on Claude Web's 4-stream empirics (310 findings, severity-at-judgment distributions):

- `Replay-without-version-binding`: was Medium → now **High**. Empirical: 55% High, 38% Medium, 7% Critical.
- `Wrong-field reference`: was Medium → now **High**. Empirical: 67% High, 28% Medium.

Five new rows added:

- `Auth missing-signer / privilege check`: default **High** (was Medium implicit). Empirical: 70% High.
- `Account-substitution (V4-class)`: default **High**. Empirical: 67% High.
- `Cross-instruction-id binding missing (V103)`: default **High**. Empirical: 73% High.
- `Underconstrained witness column (V104)`: default **High**.
- `Fiat-Shamir transcript incomplete (V106)`: default **Critical**. Empirical: 67% Critical, 33% High; Solana ZK ElGamal zero-day was Critical.

### Added — `references/platform-validation.md` Phase 4.5 longest-fund-loss-chain framing

Driven by Claude Web's empirics: ~55% of all promotion failures are "submitter framed it too narrowly." Argus now auto-generates the longest plausible fund-loss chain BEFORE rubric scoring. Stage-2 angles' narrow framing is recorded but the rubric scores against the longest chain. Pass D severity calibrates against longest chain. Cap: chain must be plausible (intermediate-step argument required, no "panics → unbounded fund loss" without explanation).

### Added — `references/release-gates.md` (convergence vs. divergence diagnostics)

ChatGPT's hardest pushback: Argus's catalogue-growth strategy is "converging as a prior, diverging as a verdict engine." Without diagnostic gates, more vectors becomes benchmark overfitting. v0.2.0 ships four release-gate tests:

1. **Family hold-out**: split eval corpus by latent invariant family; report direct recall on held-out separately.
2. **Time-split**: freeze catalogue at date T; eval only on findings disclosed after T (LiveCodeBench-style).
3. **Name-blind**: strip "Solves SP1 M-XX" labels and named-pattern annotations; re-eval. Recall must stay within 15%.
4. **Perturbation-stable**: semantics-preserving rewrites (helper extraction, renaming, guard inversion); recall must stay within 25%.

Name-blind delta and perturbation-stable delta are **release-blocking gates** — a release that passes the calibrated benchmark but fails these is a memorization regression and is not shipped.

CHANGELOG entries from v0.2.0 onward MUST include the release-gate evaluation table. Bucket-4 (post-cut-off fresh contest) direct recall is the primary KPI. If after v0.3.0 bucket-4 recall is <30%, README + Stage 8 terminal print MUST explicitly reframe Argus as a triage tool.

### Files updated

- `SKILL.md`: 12 stages (was 10); 11 angles (was 10); routing table updated.
- `references/witness-builder.md`: NEW.
- `references/hacking-agents/ffi-boundary-agent.md`: NEW.
- `references/release-gates.md`: NEW.
- `references/stage1-output-templates.md`: Verify-Signal Crate Enumeration section added.
- `references/attack-vectors/rust-attack-vectors.md`: V103–V123 added.
- `references/adversarial-review.md`: severity table recalibrated; new rows.
- `references/platform-validation.md`: Phase 4.5 longest-fund-loss-chain framing added.
- `VERSION` → `0.2.0`.

### Files added (research artifacts)

- `RESEARCH_PLAN_v0.2.0.md`
- `research/codex-prompt.md` / `claude-web-prompt.md` / `deepseek-prompt.md` / `chatgpt-deep-thinking-prompt.md`
- `research/argus-internal-research-result.md`
- `research/SYNTHESIS_v0.2.0.md`
- `codex-research-result.md` (Codex output, 19 V-proposals)
- `compass_artifact_*.md` (Claude Web output, 5 ecosystem tables, 30 ranked recs)
- `dipseek.md` (DeepSeek output, 3 promotion rules + Stage 1 fix)
- `deep-research-report.md` (ChatGPT Deep Thinking output, witness-builder architecture)

### Honest expected effect of v0.2.0

Per ChatGPT's evidence base (PrimeVul 3-23%, SecVulEval 23%, trace-guided localization 54.8%, specification-guided 37.7%):

- **Adjacent recall**: holds at ~85-90% (already high in v0.1.12).
- **Direct recall on novel targets**: realistic v0.2.0 target **20-35%**, not 70-80%. The witness architecture is the necessary-but-not-sufficient piece.
- **Direct recall on calibrated families** (where validators exist): **60-80%** is plausible — but ChatGPT correctly warns this is memorization not generalization. The release gates exist precisely to detect that.
- **Reframing**: if v0.3.0 doesn't push bucket-4 (post-cut-off fresh contest) direct recall above 30%, README and Stage 8 terminal print get the triage-tool reframing.

### Why v0.2.0 vs. v0.1.13

This release has three distinct architectural changes (Stage 3.6, FFI angle, release-gate framework) plus a substantial recalibration. Minor-version bump (0.1.x → 0.2.0) is appropriate. v0.1.x continues to be supported on existing eval setups; v0.2.x is the new mainline.

### Tracked for v0.2.1+

- Add validators 4-7 to Stage 3.6 (asset-identity, underconstrained-witness, truncation-rounding, cost-fee-records-cap).
- Establish baseline for the 4 release-gate tests (run on first post-v0.2.0 fresh contest).
- Witness-annotated training corpus (ChatGPT v0.3.0 dependency).
- Investigate v0.2.0's effect on monero-oxide and SP1 re-runs (validation step).

---

## [0.1.12] — 2026-05-09

ZK-prover / verifier release driven by an SP1 / Succinct Code4rena 2026-04 shadow-audit run. Argus ran on the contest's published source and produced 6 SUBMIT-bucket candidates. Cross-referencing against the official C4 results showed:

| C4 result | Argus result |
|-----------|--------------|
| H-01 (KoalaBearRangeCheck) | N/A — Go file, out of Argus's Rust-first scope |
| M-01 (vk_root not enforced in verify_plonk/groth16) | adjacent — F-01 found related vk-trust gap at different layer |
| M-02 (truncated public_values panic) | **MISSED** |
| M-03 (zero SplitOpts panic/livelock) | **MISSED** |
| M-04 (verifier panics on malformed inputs) | N/A — verifier crate not in Argus's scope.txt |
| M-05 (Blake3 path unreachable; PLONK rejects Blake3 proofs) | **WRONG DIRECTION** — F-05 claimed dual-hash acceptance (the opposite of M-05) |
| M-06 (proof nonce clobbered when packing deferred page-prot events) | **MISSED** |
| M-07 (Go-side decimal-string DoS) | N/A — Go file |
| QA (StoreDouble uses StoreWord cost rate) | **MISSED** |

Score on in-scope C4 findings: 0% direct recall, 17% adjacent recall (1 of 5 reached at adjacent severity). 1 wrong-direction submission (F-05). 4 misses + 1 wrong = 5 of 5 in-scope C4 findings handled incorrectly.

### Root-cause analysis

Three systematic failures, each addressed below:

1. **Hot-zone bias toward AIR / constraint-circuit code.** Argus's Stage 1 hot-zones ranked `Air::eval()` blocks high; missed `record.rs::ExecutionRecord::split` (188-360) entirely (both M-03 and M-06 live there). Missed `verify.rs` BN254 helpers, `cost.rs` opcode tables.
2. **DoS / panic findings demoted to LEADs.** Argus's confidence-deduction model deducts −15 for "bounded / non-compounding impact" — calibrated for fund-loss bugs. Applied to a panic finding in a bounty that explicitly lists "Undocumented panic reachable from a public API" as in-scope, the deduction suppresses the finding to a LEAD. M-02 / M-04 / M-07 were all this pattern.
3. **Wrong-direction reachability — F-05 claimed a fallback branch active when callers early-return.** Argus's existing `reachability_check` asks "is the cited function reachable from a public entry?" but does not ask "is this specific BRANCH (if-arm or match-arm) reachable WITHOUT a caller's early-return blocking it?" F-05 quoted `verify_public_values` (which contains a Blake3 fallback) but didn't trace that callers (`verify_plonk_bn254`, `verify_groth16_bn254`) early-return Err on `!vkey.is_plonk()` / `!vkey.is_groth16()` — so the Blake3 branch is dead code.

### Added — `references/rust-protocol-types.md` § ZK Prover / Verifier (Rust)

New protocol-type profile. Detection signals: `prover/`, `verifier/`, `circuit/`, `air/`, `recursion/` directories; `Air` / `MachineAir` / `Chip` traits; `vk` / `verifying_key` / `vkey_hash` parameters; `BN254` / `Groth16` / `Plonk` / `Blake3` / `Poseidon` helpers; opcode-cost tables.

Profile lists 6 primary adversaries (untrusted-input crafter, vk-root manipulator, state-corrupter via packing, cost / weight oracle, dead-code-path-ghost, compromised admin), 7 dominant attack patterns (each mapping to an SP1 contest finding), and explicit hot-zone bias warnings:

- AIR `eval()` constraint blocks tempt the auditor; real bugs lived in **imperative non-AIR Rust** in this contest.
- `record.rs::split`, `verify.rs::verify_public_values`, `cost.rs::Opcode::cost`, `pack`/`commit` paths must be hot-zoned even when they don't have AIR `eval()` blocks.

### Added — `references/stage1-output-templates.md` § hot-zones expansion

Five new MANDATORY hot-zone categories for every project's Stage-1 hot-zones:

1. **Imperative state-mutation hot zones**: enumerate every `pub fn` with names like `split`, `pack`, `unpack`, `partition`, `flatten`, `commit`, `merge`, `truncate`, `extend`, `chunk`, `batch`, `fold`, `compress`, `encode`, `decode`, `serialize`, `deserialize`, `prepare`, `prove`, `verify`, `dispatch`, `execute_step`. Each with attacker-influenceable inputs is a Stage-2 candidate.
2. **Untrusted-byte-decode hot zones**: every `pub fn` accepting `&[u8]` / `Vec<u8>` / Borsh-decoded structs from outside trust boundaries. Check first-line length validation; check panic-class on malformed input.
3. **Cost / weight / opcode hot zones**: every cost table, weight table, opcode-fee table, per-instruction CU calculation. Spot-check claims vs. work performed.
4. **Fallback / dead-code hot zones**: every documented "alternative" / "fallback" / "if-else" branch where the documentation suggests reachability but the call chain may early-return before it. F-05's failure class.
5. **Verifier vk-binding paths** (ZK projects): every `verify*` public function. Check whether vk-binding occurs at the entry or only inside the function.

### Added — `references/attack-vectors/rust-attack-vectors.md` § V98–V102

Five new vectors mapping directly to SP1 / Succinct contest findings:

- **V98**: Verifier accepts proof without binding `vk_root` to caller's expected program-vkey (SP1 M-01 pattern).
- **V99**: Public API deserializer panics on truncated / malformed input (verifier-class) (SP1 M-02 / M-04 pattern).
- **V100**: State-split / partition / pack function panics or livelocks on degenerate options (SP1 M-03 / M-06 pattern).
- **V101**: Documented fallback / alternative path that is unreachable due to caller early-return (SP1 M-05 pattern, the wrong-direction risk class).
- **V102**: Cost / weight / opcode table mismatch — sibling-opcode-derived cost (SP1 QA pattern).

Vector library now has 102 entries.

### Added — `references/hacking-agents/shared-rules.md` § Bounty-aware carve-outs

Stage 2 confidence-deduction model now reads `1-protocol-map/attack-surface.md` § "Bounty enumerated in-scope impacts". When the finding's mechanism literally matches a bounty item, specific deductions are skipped:

| Bounty in-scope-impacts include... | Don't deduct for... |
|------------------------------------|----------------------|
| "Undocumented panic reachable from a public API" | "bounded / non-compounding impact" on panic-class findings |
| "Denial of service" / "Liveness violation" | "bounded / non-compounding impact" on DoS-class findings |
| "Undocumented fingerprints in created transactions" | "bounded / non-compounding impact" on fingerprint findings |
| "Non-constant-time implementation with regards to secret data" | "bounded / non-compounding impact" on side-channel findings |
| "Incorrect/incomplete cryptographic formulae within a verifier's callstack" | "partial attack path traced" when the math IS the bug |

This prevents M-02 / M-04 / M-07-class findings from being suppressed to LEADs because of the −15 bounded-impact deduction. The carve-out applies only when the bounty literally lists the impact category. Generic "this is also a bounded DoS" without bounty backing → deduction still applies.

New mandatory FINDING field: `bounty_carveouts_applied` (or absent if no carve-outs apply).

### Added — `references/adversarial-review.md` § Branch-reachability check

New mandatory check (runs before Pass A) when the finding's `location:` cites a specific if/else arm, match arm, or specific block inside a larger function. Trace the call chain UP from the cited function; for each caller, identify pre-checks and early-returns; determine whether ANY caller blocks the activating condition for the cited branch.

Verdict matrix:

| Branch reachability through callers | Action |
|--------------------------------------|--------|
| Reachable on at least one path with no blocking pre-check | proceed (finding stands) |
| Blocked on EVERY path by caller early-return | **KILL(branch-unreachable-via-caller-early-return)** |
| Blocked on most paths but reachable on rare path | DOWNGRADE(refine) — frame the rare path explicitly |
| Cannot determine | UNCERTAIN; Pass C fires on `branch-reachability` |

New mandatory FINDING field: `branch_reachability_check` (when the location cites a specific branch).

This is the F-05 fix: had Argus run this check on F-05, it would have traced caller chain UP from `verify_public_values` to `verify_plonk_bn254`, found the early-return on `!vkey.is_plonk()`, and KILLed F-05 as `UNREACHABLE_VIA_CALLER` before submission.

### Files updated

- `references/rust-protocol-types.md` — ZK Prover / Verifier protocol type added.
- `references/stage1-output-templates.md` — 5 new hot-zone categories.
- `references/attack-vectors/rust-attack-vectors.md` — V98–V102 added.
- `references/hacking-agents/shared-rules.md` — bounty-aware carve-outs.
- `references/adversarial-review.md` — branch-reachability check.
- `VERSION` → `0.1.12`.

### Expected effect on a re-run vs SP1 / Succinct contest

If you re-run Argus on SP1 / Succinct with v0.1.12 disciplines:

- **Stage 1 hot-zones** include `record.rs::split`, `verify.rs` BN254 helpers, `cost.rs` opcode table — even though they're not AIR `eval()` blocks. M-03, M-06, and QA's source files now appear in hot-zones ranked by imperative-state-mutation criteria.
- **M-02 / M-04** (truncated `public_values` panic, verifier panics on malformed input): V99 catches the pattern at Stage 2; bounty-aware carve-out preserves confidence ≥50 (Stage 2 doesn't suppress to LEAD); finding ships as Medium.
- **M-03 / M-06** (zero SplitOpts livelock; pack-clobber-nonce): V100 catches; Stage 2 emits as candidate FINDINGs; Stage 4 confirms.
- **M-05** (Blake3 fallback unreachable): V101 catches; Stage 4 branch-reachability check confirms — the Blake3 branch in `verify_public_values` is unreachable via caller early-returns. Argus produces this as the M-05 finding (correct direction, not the F-05 wrong-direction reverse).
- **M-01** (vk_root not enforced): V98 catches; existing F-01 adjacency promotes to direct match.
- **QA** (StoreDouble using StoreWord cost): V102 catches; opcode-cost-table hot zone surfaces it at Stage 1.

Projected v0.1.12 SP1 / Succinct outcome: **5/5 in-scope C4 Mediums caught at correct severity and correct direction, plus QA**. Direct-recall jumps from 0% to ≥80%.

### Why this matters

The v0.1.10 architectural release built mechanisms (Pre-Pass external research, 3-judge Pass C, rubric scorecard, branch reachability via reachability_check). The v0.1.11 calibration release fixed procedural enforcement (per-finding files, whitelist-mode scope). The v0.1.12 release is the **calibration of the Stage-1 enumeration step** — the input to all those mechanisms. If hot-zones miss the file, no downstream mechanism can save the audit. If confidence model penalizes panic-findings the bounty pays for, the finding never reaches Stage 4. If branch-level reachability isn't traced, a Stage 4 verdict that says "reachable from public entry" can mask a dead-code bug.

These are the lowest-leverage-cheapest-fix improvements — small additions that cascade into 5/5 vs. 0/5 recall on a real contest. Calibration over architecture.

---

## [0.1.11] — 2026-05-08

Calibration release driven by a v0.1.10 run on monero-oxide (`/Users/dx/Documents/Dev/monero-audit/argus/2026-05-08T00-48-58Z/`). Argus produced 14 candidate findings; 2 advanced through the pipeline as borderline-SUBMIT (F-06 sanity_check_contiguous_blocks, F-11 SimpleRequestTransport URL parser). The user submitted both to The Judge skill standalone for second-opinion validation. **Both came back INVALID with HIGH confidence**, with reasoning the v0.1.10 Argus pipeline did not produce.

### Root-cause analysis

Inspection of the v0.1.10 run output showed:

| Stage | Expected output | Actual output |
|-------|-----------------|---------------|
| 4 | `F-NN.md` per finding (14 files) with full Pre-Pass + Pass A/B/C/D | single `_summary.md` with 1-paragraph-per-finding triage |
| 5 | `F-NN.md` per finding with rubric scorecard | single `_summary.md` |
| 6 | `F-NN.md` per finding with 6 checks + scope-mode classification | single `_summary.md` with prose-only impact mapping |
| 7 | `F-NN.md` per finding with 7-probe trace | single `_summary.md` |

The orchestrator collapsed every per-finding stage into a summary. As a result:

- **Pre-Pass External Research never fired per finding.** F-11 claimed "credential leak via digest-auth" — wrong (RFC 7616 hashes plaintext, never on wire). The Pre-Pass would have caught this on a per-finding run.
- **3-judge Pass C panel never ran.** F-11 claimed "connection target redirection" — wrong (`hyper::Uri` extracts host:port independently of userinfo). Per-finding Pass C would have caught this.
- **Stage 6 whitelist-mode impact match never ran literally.** F-11 mapped to "credential mishandling / borderline scope" → DOWNGRADE(refine). monero-oxide's bounty has 10 enumerated in-scope impacts (spend-key recovery, signing unintended messages, consensus protocol incompatibility, undocumented panic, etc.); URL-parser correctness maps to NONE. Strict literal-match would have killed it.
- **Trust-contract source discipline was absent.** F-06 cited `1-protocol-map/trust-model.md` (an Argus-generated artifact) as the project's trust contract. The actual contract at `monero-oxide/interface/README.md:11-16` says: *"Neither set of traits promise the returned data is completely accurate and up to date... unless the caller locally behaves as a full node."* The project EXPLICITLY DISCLAIMS the validating-wrapper guarantee F-06 assumed.
- **Impact-chain reachability never ran.** F-06 mapped to "reportedly received funds which weren't actually received". The exploit path passes through `Scanner::scan_transaction`'s cryptographic ownership check (view-key derivation, view-tag check, Pedersen rebuild). A malicious daemon without the wallet's view key cannot pass these. The claimed impact was unreachable through the cryptographic guard — but Stage 6 didn't trace it.

### Added — `references/adversarial-review.md`, `references/platform-validation.md`, `references/program-triage.md`, `references/duplication-check.md`

- **Per-finding-file MANDATE at Stages 4/5/6/7**. Each stage's reference file now opens with: "Stage N produces `$RUN_DIR/N-stage/F-NN.md` for every finding entering this stage. A single `_summary.md` is INVALID and rejected at orchestrator validation." Stage entry validators check per-finding file count against incoming-finding count; if short, the missing files are produced before advancing.
- The compactness anti-pattern is named explicitly. If the orchestrator finds itself writing `_summary.md` with 1-paragraph-per-finding triage, it must STOP and produce per-finding files first.

### Added — `references/program-triage.md` § Scope-mode classification

- New step at Stage 6 start (after WebFetch, before per-finding triage): classify the bounty as **whitelist mode** / **blacklist mode** / **hybrid mode**.
- **Whitelist mode** (Immunefi V2.3-style with enumerated "Impacts in Scope" list): only findings whose impact LITERALLY matches one of the listed items are in-scope. Everything else → KILL(impact-not-in-scope-list). No fuzzy match. No "borderline scope". No "could be classified as".
- **Blacklist mode** (Code4rena, Sherlock, generic): existing v0.1.0 logic.
- **Hybrid mode**: whitelist matching first; fall to blacklist if no whitelist match.
- New file `$RUN_DIR/6-program/scope-mode.md` records the classification, the enumerated in-scope impacts table, and reasoning.

### Added — `references/program-triage.md` § Check 2 rewrite + Check 2.5

- **Check 2 (impact mapping) rewritten** to require literal mechanism + harmed-party + severity-tier match in whitelist mode. Verdict file's `check_2_impact_in_scope:` field enumerates each candidate item, the match result, and the verdict. Anti-fuzzy-match discipline: phrases like "this could be classified as", "borderline scope" are PROHIBITED in whitelist mode.
- **Check 2.5 — Impact-chain reachability (NEW)**: after Check 2 maps a finding to an in-scope impact, decompose the exploit chain step-by-step and identify every guard between attacker action and claimed impact. For each guard, determine whether the attack scenario actually clears it. If a guard requires a capability the attacker doesn't have (e.g., view key, signer authority, finalized chain access), the impact is unreachable → KILL(impact-chain-blocked-by-<guard>) or KILL(impact-chain-requires-attacker-capability).

### Added — `references/hacking-agents/shared-rules.md` § Trust-contract source discipline

- New mandatory rule: any finding making a claim about the protocol's trust model MUST cite a project-repo source (`<repo>/README.md`, `<repo>/SECURITY.md`, `<repo>/audits/`, `<repo>/<crate>/README.md`).
- **Citing `$RUN_DIR/1-protocol-map/trust-model.md` is REJECTED** — that file is Argus-derived, not authoritative.
- When the artifact and the project README disagree, the README wins. Trust-contract check verdict: PROCEED / KILL_AS_DISCLAIMED / REJECT_CITATION.
- Field `trust_contract_check` becomes mandatory on findings making trust claims.

### Added — `references/pipeline-overview.md` cross-stage invariant

- New invariant: "One file per finding at stages 4-7 (procedural)." Forms a hard validator that the next stage can't begin until the per-finding file count matches the incoming-finding count.

### Files updated

- `references/adversarial-review.md` — per-finding mandate at top.
- `references/platform-validation.md` — per-finding mandate at top.
- `references/program-triage.md` — per-finding mandate + scope-mode classification + Check 2 rewrite + Check 2.5 impact-chain reachability.
- `references/duplication-check.md` — per-finding mandate at top.
- `references/hacking-agents/shared-rules.md` — trust-contract source discipline.
- `references/pipeline-overview.md` — cross-stage invariant.
- `VERSION` → `0.1.11`.

### Expected effect on a re-run vs monero-oxide

If you re-run Argus on monero-oxide with v0.1.11 disciplines:

- **Stages 4/5/6/7 produce per-finding files** for every advancing finding. The orchestrator cannot skip to summary; the validator forces per-finding output.
- **F-11 is killed at Stage 6 whitelist-match step**: bounty's 10 enumerated in-scope impacts checked against URL-parser-credential-mishandling impact → no literal match → KILL(impact-not-in-scope-list). No "refine".
- **F-06 is killed at Stage 6 trust-contract check OR Check 2.5 impact-reachability**: F-06's claim that the validating wrapper guarantees safety is contradicted by `monero-oxide/interface/README.md:11-16`'s explicit disclaimer. Even if the trust-contract check let it pass, Check 2.5 traces the exploit chain through `Scanner::scan_transaction`'s cryptographic ownership check — a malicious daemon cannot fabricate outputs that pass view-key validation. KILL(impact-chain-blocked-by-cryptographic-ownership-check).
- **The per-finding 3-judge Pass C panel** at Stage 4 catches both findings' inflated impact claims (digest-auth credential leak, connection redirection) before they reach Stage 5.

Projected v0.1.11 monero-oxide outcome: SUBMIT bucket = 0 findings, matching what the Judge concluded post-hoc. The other 12 candidates (DoS-class, refines, etc.) end in DISCARD or REFINE per their existing Stage 4-7 verdicts. Net effect: the pipeline produces zero false positives in the SUBMIT bucket, which is the correct answer for monero-oxide given its narrow whitelist scope.

### Why this matters

The v0.1.6 work fixed Stage 4 architectural mechanisms (parallel checkers, ensembles, external research). The v0.1.10 work added the Pre-Pass scope-carveout validity check, the rubric scorecard, the 3-judge panel. But the v0.1.10 monero-oxide run revealed that **all of these mechanisms are useless if the orchestrator doesn't actually run them per finding**. The procedural enforcement in v0.1.11 is the smallest-possible-change fix: every prior architectural improvement now has a hard structural requirement to be executed per finding rather than collapsed into summary.

The whitelist-mode strict literal-match (F-11 fix) and trust-contract source discipline (F-06 fix) are the two calibration fixes that target the specific monero-oxide failure mechanisms. Both are bug-bounty-program-specific (not every bounty is whitelist; not every finding makes trust-model claims), so they only fire when the conditions are met. The procedural enforcement is universal.

---

## [0.1.10] — 2026-05-08

External-review release. After v0.1.9, an external reviewer (DeepSeek-class model) ran a line-by-line gap analysis against the v0.1.9 playbook and identified 40+ high-impact gaps across exploit coverage, stage design, adversarial reasoning, formal-method integration, severity calibration, and professional presentation. v0.1.10 implements every actionable item except the few that DeepSeek mis-identified (those skipped with reason in `IMPLEMENTATION_PLAN_v0.1.10.md`).

This is the largest release since v0.1.0. Run scope: 30 todos across 4 hours of focused work. Major architectural changes.

### Added — `references/attack-vectors/rust-attack-vectors.md`

**34 new vectors V64–V97**, organized by ecosystem:

- **Solana / Anchor**: V64 close constraint without beneficiary signer, V65 realloc without post-length validation, V66 try_borrow_mut_data aliasing in remaining_accounts, V67 upgradeable proxy authority not validated, V68 SPL Token-2022 transfer-fee not subtracted from accounting.
- **CosmWasm**: V69 reply handler msg.id not validated, V70 IBC packet timeout missing, V71 sudo callable via raw entry-point, V72 CW20 callback recursion not rate-limited, V73 migrate accepting unsafe migrations.
- **Substrate**: V74 ValidateUnsigned not enforced, V75 offchain_worker fetching attacker-controlled URL, V76 storage proof not verified against block header, V77 pallet-treasury double-spend, V78 on_initialize weight mismatch.
- **Generic Rust**: V79 unsafe Vec<u8> bounds-unchecked read, V80 unsafe transmute alignment mismatch, V81 serde without deny_unknown_fields, V82 HashMap iteration order in deterministic context, V83 Ord/PartialOrd inconsistent with Eq, V84 assert! vs require! in BPF/dispatchable, V85 missing #[repr(C)] in FFI structs, V86 unbounded mapping iteration (V63 extension), V87 lazy cumulative-growth Vec, V88 accumulator with attacker-controlled granularity.
- **DeFi**: V89 concentrated-liquidity tick-spacing manipulation, V90 fee-on-transfer breaking constant-product, V94 self-liquidation profit on newly-added collateral, V96 donate-to-reserves rounding (Euler pattern).
- **Bridge**: V91 validator-set update race with finalized in-flight deposit.
- **Governance / LST**: V92 vote-delegate-vote same-block, V93 LST exchange-rate front-run on reward-claim, V95 governance-token flash-loan vote (Beanstalk).
- **Oracle**: V97 global-timestamp partial-update across multi-asset oracle data — the C4 M-05 Reflector miss that v0.1.9 didn't catch.

### Added — Two new Stage 2 angles (10 angles total)

- **Cryptographic Soundness Agent** (`references/hacking-agents/crypto-soundness-agent.md`): owns V20, V27, V28, V37, V61, V62, V99 + signature schemes / hash functions / commitments / Merkle proofs / threshold cryptography / ZK integrations / on-chain randomness / custom protocols. Custom fields: `crypto_primitive`, `property_violated`, `known_attack_paper`.
- **Concurrency / Async Safety Agent** (`references/hacking-agents/concurrency-agent.md`): owns V29, V30, V31, V82, V83, V84 + async cancellation / lock ordering / select! bias / Send/Sync violations in trait objects / Substrate OCW / wasm-bindgen async / deterministic-execution violations. Custom fields: `async_runtime`, `shared_state`, `race_window`.

Stage 2 now dispatches 10 parallel subagents (was 8). Conditional dispatch: protocol classifier picks subset to save tokens for protocol types where the angle has minimal surface.

### Added — New mandatory FINDING schema fields (`references/hacking-agents/shared-rules.md`)

- `practical_weaponisation`: capital, time, monitoring, attacker_class, weaponisation_grade A/B/C/D. Attack-difficulty axis orthogonal to severity.
- `trust_threshold`: numeric 1-5 level + `layers_bypassed_by_finding`. Replaces binary TRUSTED/SEMI-TRUSTED/UNTRUSTED.
- `confidence_interval`: point + low + high + width_reasons. Replaces bare confidence score; epistemic-uncertainty-aware.
- `prior_validity_rate`: Bayesian prior placeholder (model lands in v0.3.0).
- `source_snapshot`: in_scope_files_sha256 + git_commit + audit_timestamp_utc. Reproducibility.

### Added — Pre-Pass scope-carveout VALIDITY check (`references/adversarial-review.md`)

The most important fix in v0.1.10. Before the v0.1.9 KILL on `WITHIN + weak/absent rebuttal` fires, the orchestrator now:

1. Decomposes the carve-out into actor + mechanism.
2. Compares to the finding's actor + mechanism.
3. KILL only fires if BOTH actor AND mechanism match.
4. Mismatched actor (carve-out covers admin; finding's path uses non-admin caller) → SURVIVE.
5. Mismatched mechanism (carve-out covers malformed args; finding describes well-formed args at edge case) → SURVIVE.

The classic broken case the v0.1.9 rule mishandled (admin-mistake carve-out vs non-admin-init-front-run finding) is now caught.

### Added — CR (Cryptographic Weakness) and IL (Information Leak) Pass A categories

15-category catalogue (was 13). CR-1..CR-5 invalidate findings claiming weak crypto when verification shows the primitive is actually used correctly. IL-1..IL-3 distinguish material vs immaterial information leaks. CP-6 added for actor-in-system zero-cost extraction (validator MEV / sequencer reorder); does NOT downgrade — escalates to Economic Security review.

### Changed — Pass A 3-checker ensemble + Pass C 3-judge deliberative panel

- Pass A top-2 selected invalidators dispatched to **3 parallel checker subagents each** (was 2). Mix: 2 Sonnet + 1 Opus for cross-model diversity. Auto-kill requires 2-of-3 HIGH HOLDS (was 2-of-2 unanimity).
- Pass C upgraded from single Opus call to **3-judge deliberative panel**: steel-manning judge + devil's-advocate judge + balanced judge. 2-of-3 majority decides. 1-1-1 split → DOWNGRADE one tier (conservative resolution). `high_holds_overrides` field requires confirmation by Judge 3 (balanced) specifically.

### Changed — C4 historical severity table: clamp → overridable suggestion

The v0.1.6 table clamped severity to Medium for matching bug shapes. v0.1.10 makes it a default suggestion overridable by:

- `value_at_stake_check`: estimated_value_at_risk_usd > $1M → override upward to High.
- `one_tx_drain_demonstrated: yes` → override upward to High or Critical per direct rubric.

Prevents the v0.1.9 under-grading regression on Reflector (3 of 6 caught findings undergraded).

### Added — ITERATE mode (`references/iterate-mode.md`)

Stage 4 KILL with rationale naming a *different* defect at a different location triggers a single-angle re-dispatch on the cited region with the challenger's rationale injected as hot-zone. Cap 5 per run. New finding F-NN' enters pipeline at Stage 3.

### Added — Stage 3.5 Automated Verification (`references/automated-verification.md`)

Optional stage between Stage 3 (PoC) and Stage 4 (Adversarial). Operationalizes:

- **Kani** for math findings (V12, V13, V14, V15, V16, V52, V61, V62, V88): auto-generate `#[kani::proof]` harness; on VERIFIED → drop finding; on counterexample → upgrade certainty to 95.
- **cargo-fuzz** for state-machine and parsing bugs: 5-minute fuzz; on crash → upgrade certainty to 95.
- **Miri** (UB detector) for `unsafe` blocks (V79, V80, V85): run project test suite under Miri; on UB report → upgrade certainty to 95.

`scripts/install-deps.sh` extended to detect/install Kani / cargo-fuzz / Miri. User opt-in via AskUserQuestion.

### Added — Stage 4.5 Combination Attack pass (`references/combination-attack.md`)

Pairwise analysis on Stage-4-ADVANCE findings. For each pair (F-A, F-B):

1. Precondition chaining check (does A's outcome create B's precondition? or reverse?).
2. Joint-impact check (is combined > max(A, B)?).
3. STRONG_COMBINATION → emit joint finding F-AB-NN with Pass D re-calibration.

Cap top 20 by severity × confidence. F-A and F-B retained alongside F-AB.

### Changed — Stage 5 subtractive scoring → 4-criterion rubric scorecard

Replaces 100→5 subtractive deductions with 4-criterion (vuln-id / impact / exploitability / remediation) × 0-4 = 0-16 rubric. Verdict: ≥12 ADVANCE, 8-11 DOWNGRADE, <8 KILL. Half-credit for rigorous written derivation when PoC missing (logic bugs on Sherlock / generic only). Subtractive scoring kept as informational fallback for one release; removed in v0.2.0.

### Added — Stage 6 deep scope search

Beyond bounty-page WebFetch, Stage 6 now scans:
- README.md, CONTRIBUTING.md, SECURITY.md from the repo
- `gh issue list --label wontfix --state all`
- Pinned issues / discussions
- Bounty-page deep-linked docs (Notion / GitBook)

Aggregates exclusions across all sources; classifier matches finding mechanism against any matching exclusion text.

### Added — Stage 7 adjacent-hit rescan

When a probe returns adjacent (related but not exact) hit, spawn lightweight Stage-2 single-angle re-run on the cited region with the prior issue's body + fix diff injected as hot-zone. Outcomes: F-NN still holds → ADVANCE; new related candidate → emit F-NN'; covered by prior fix → KILL; inconclusive → DOWNGRADE. Cap 3 rescans per run.

### Added — Stage 1 reorg-window temporal phase + protocol-specific Stage-1 checklists

- **Reorg Window** universal phase covers source-chain reorg attacks, validator-set update races during reorg, finality-depth misconfigurations.
- **Per-protocol checklists** auto-injected: lending (interest-rate manipulation, V94 self-liquidation), DEX (V89 tick-spacing, V90 FoT), bridge (V91 validator race, V76 storage proof), governance (V92 delegate-vote, V95 flash-loan vote), LST (V93 reward-claim front-run), stablecoin (death-spiral simulation), derivatives (oracle × leverage).

### Added — Stage 1 invariants Section 5 expansion

Beyond unbounded `Vec<T>` / `BTreeMap<K,V>` / `HashMap<K,V>` enumeration, add:
- 5.2 Unbounded mapping iteration sites (V86)
- 5.3 Lazy cumulative-growth containers (V87)
- 5.4 Accumulators with attacker-controlled granularity (V88)

### Added — Stage 8 polish

Per-finding output schema gains:
- **TL;DR**: 3-sentence executive summary at top of every SUBMIT finding.
- **Unified-diff patch**: `Recommendation` is now mandatory unified diff that must apply cleanly via `git apply --check`. Verbal-only recommendations rejected.
- **Severity decision path**: Pass D outputs the full clamps + overrides path traversed.
- **Mitigation viability** + **Practical weaponisation** fields surfaced from Stage 2 / Stage 4.

### Added — Phase 8c format-adversarial polish (opt-in)

After Phase 8b template formatting, optional step spawns LLM-judge subagent simulating the platform's triager. Score < 90 triggers writer-rewrite cycle (max 3 iterations). Surfaces `acceptance_likelihood` per finding. Polish is OPT-IN; default skip.

### Changed — Confidence model: bare score → interval

`confidence: 0..100` becomes `confidence_interval: { point, low, high, width_reasons }`. Stage 8 uses `low` for SUBMIT decision, `high` for REFINE. Schema for v0.3.0 logistic-regression Bayesian model documented; placeholder `prior_validity_rate` field present.

### Added — Numeric trust-threshold model

Replaces binary TRUSTED/SEMI-TRUSTED/UNTRUSTED with `trust_threshold.level: 1..5` + `layers_bypassed_by_finding`. Verdict: bypass 0 = no impact; bypass 1 = keep severity; bypass N < level = DOWNGRADE one tier per layer; bypass = level → INFORMATIONAL cap. Worked example in adversarial-review.md.

### Added — Expert-annotation input

`assets/expert-annotations.example.json` template. Optional Stage-1 input. User documents safe patterns, trusted invariants, scope clarifications. Injected into all Stage 2 angle prompts as SAFE_PATTERNS — angles producing matching findings must justify override or finding is suppressed at Stage 2 dedup.

### Added — Reproducibility: source-snapshot SHA256 + Dockerfile

- `scripts/enumerate.sh` extended to emit `source_snapshot_sha256`, `git_commit_sha`, `git_dirty`, `audit_timestamp_utc`.
- `Dockerfile` pins Rust 1.83 / Solana 1.18.26 / Anchor 0.30.1 / Node 20 / Kani 0.56 / cargo-fuzz 0.12.
- `scripts/run-in-docker.sh` wrapper for invoking Argus inside the pinned environment.
- Every per-stage verdict.md MUST include the `source_snapshot` field.

### Added — Regression eval suite scaffold

`evals/benchmarks/` framework with 3 scaffold benchmarks (Anchor missing-signer, CosmWasm reply-msg-id, Math Precision overflow). `evals/scripts/run-eval.sh` clones + invokes manually. `evals/scripts/score-eval.sh` compares against ground truth, computes precision / recall / severity-accuracy. Benchmark bodies are scaffolds — actual buggy programs need to be authored or imported from past Argus runs.

### Added — Stage 2 file-hash caching (opt-in)

`--cache` flag enables `~/.cache/argus/stage2/` LRU cache keyed by `sha256(argus_v{VERSION}::{angle}::{file}::{file_hash})`. Cache is version-keyed; angle-definition changes invalidate. OFF by default.

### Added — Cross-program / multi-contract scope

Stage 1 produces `cpi-graph.md` for Solana protocols spanning multiple programs OR CosmWasm protocols spanning multiple contracts. Stage 2 angles can read across programs; Auth/Account, Execution Trace, and Invariant angles specifically look for cross-program invariants. Cross-program findings carry `crosses_programs: [<list>]`.

### Files updated (top-level)

- `SKILL.md`: 10-stage pipeline (was 8); 10 angles (was 8); routing table updated for 3.5 / 4.5 / ITERATE.
- `references/pipeline-overview.md`: contracts for 3.5, 4.5, ITERATE, caching, cross-program.
- `references/hacking-agents/shared-rules.md`: 5 new mandatory schema fields, confidence-interval section, trust-threshold section, source-snapshot section.
- `references/adversarial-review.md`: validity check, CR + IL categories, 3-checker / 3-judge ensembles, severity-table override, value-at-stake check, numeric trust-threshold integration.
- `references/platform-validation.md`: rubric scorecard.
- `references/program-triage.md`: deep scope search.
- `references/duplication-check.md`: adjacent-hit rescan.
- `references/rust-protocol-types.md`: reorg-window phase, per-protocol checklists.
- `references/stage1-output-templates.md`: Section 5 expanded.
- `references/output-format.md`: TL;DR, unified-diff patch, decision-tree justification, Phase 8c.
- `references/attack-vectors/rust-attack-vectors.md`: V64-V97.

### Files added

- `references/hacking-agents/crypto-soundness-agent.md`
- `references/hacking-agents/concurrency-agent.md`
- `references/automated-verification.md`
- `references/combination-attack.md`
- `references/iterate-mode.md`
- `assets/expert-annotations.example.json`
- `evals/benchmarks/bench-001-anchor-missing-signer.md` (scaffold)
- `evals/benchmarks/bench-002-cosmwasm-reply-msg-id.md` (scaffold)
- `evals/benchmarks/bench-003-math-precision-overflow.md` (scaffold)
- `evals/scripts/run-eval.sh`
- `evals/scripts/score-eval.sh`
- `Dockerfile`
- `scripts/run-in-docker.sh`
- `IMPLEMENTATION_PLAN_v0.1.10.md` (the planning document this release was executed from)
- `ARGUS_PLAYBOOK.md` (the playbook fed to DeepSeek; the gap-analysis output drove this release)
- `DEEP.MD` + `DEPSEEKREPORT.MD` (the external-review artifacts)

### Tracked for v0.2.0+

- Author and run all 3+ benchmark bodies against real Rust source (not scaffolds).
- Train logistic-regression confidence model once labeled findings accumulate (≥50 from eval suite).
- Operationalize ITERATE in Claude Code's runtime (currently methodology-only; awaits orchestrator hook).
- 3-model ensemble using *external* models (DeepSeek API) instead of 3 Opus subagents with diversified prompts.

### Why this release matters

DeepSeek's review identified that Argus's pre-v0.1.10 architecture was over-conservative in some places (killing valid findings via blunt scope-carveout checks) and over-permissive in others (allowing miscalibrated severities by clamping to the historical-severity table). v0.1.10 fixes both directions: the validity check rescues legitimate findings the v0.1.9 KILL would have lost; the value-at-stake override prevents under-grading. Combined with the 34 new vectors and 2 new angles, the expected effect is recall ↑ from ~86% to >95% AND FP rate ↓ to near-competition-grade levels.

The expanded automated-verification (Stage 3.5), combination-attack (Stage 4.5), and ensemble Pass A/C make Argus the first AI audit tool with formal-method integration AND multi-judge deliberative panels AND chain-aware compound finding analysis in a single pipeline.

### Expected effect on a re-run vs Reflector / swafe / vault-protocol

If you re-run on Reflector with v0.1.10:
- M-1 (admin replay) — v0.1.9 dropped via blunt scope-carveout. v0.1.10 validity check: actor mismatch (carve-out covers admin; finding's mechanism reachable by non-admin via timestamp manipulation) → SURVIVES. Submitted as Medium with caveat.
- C4 M-05 (global timestamp partial-update) — V97 added; Stage 1 Section 5.4 (accumulators) now flags. Caught.
- L-1 / L-2 undergraded — value-at-stake override on the historical severity table corrects to Medium.
- M-4 overgraded — mitigation viability check identifies as TRADE_OFF (cure ≈ disease) → Pass D Low cap.

Projected v0.1.10 Reflector outcome: 7/7 C4 risk findings caught at correct severity; 0-1 SUBMIT bucket FP. Up from v0.1.9's 6/7.

If you re-run on swafe with v0.1.10:
- C4 M-07 (recover_id missing rec.social) — v0.1.7 weaponization_check already caught it; v0.1.10 unchanged.
- C4 M-05 (Vec<AssociationsV0> unbounded) — v0.1.7 V63 already caught; v0.1.10 Stage 1 Section 5.2 confirms.
- All four prior swafe findings (H-1 unreachable, H-3/M-2/M-4 fix-subsumed) — v0.1.8 already collapsed appropriately; v0.1.10 unchanged.

Projected combined v0.1.6 + 0.1.7 + 0.1.8 + 0.1.9 + 0.1.10 swafe outcome: 7/7 C4 Mediums caught at correct severity; 0 FP.

---

## [0.1.9] — 2026-05-06

Scope-carveout + code-comment release. The v0.1.8 Reflector run (10 SUBMITs vs C4's 6 confirmed risk findings) exposed two structural gaps not covered by the existing `readme_invariant_check`:

| Argus | Reflector triage | Why it survived to SUBMIT |
|-------|-------------------|---------------------------|
| M-1 (bitmask shift on admin replay) Medium | Likely scope-invalidated | Triggered by admin re-broadcast of `set_price` at `timestamp == last_timestamp`. README §"Administrator Mistakes" carves out admin actions with malformed/inconsistent args. Argus's writeup quoted the carve-out and argued against it interpretively — no hard gate killed it. |
| L-3 (Beam burn-for-None on stale) Low | Marginal — partially scope-weakened | README §"Oracle Data Staleness" documents staleness as design. Fee-on-None is a separate axis (the actual novelty), but Argus didn't separate the two limbs; the staleness limb dilutes the writeup. |

The data was already in both writeups. v0.1.8 had no gate that turned scope-section data into a verdict.

### Added — `references/hacking-agents/shared-rules.md`

- **`scope_carveout_check` is now mandatory on every FINDING.** Distinct from `readme_invariant_check` (which captures positive specifications "the protocol must do X"). This field captures **scope exclusions**: README sections like "Publicly known issues", "Out of scope", "Centralization Risks", "Trust assumptions" — and named subsections like "Administrator Mistakes" or "Oracle Data Staleness". Schema: `scanned_sections`, `touching_carveouts` (verbatim quotes + WITHIN/PARTIAL/OUTSIDE classification), `rebuttal` (textual paragraph), `rebuttal_quality` (strong-textual / weak-interpretive / absent), `verdict`. Verdict mapping at Stage 2:
  - OUTSIDE → proceed
  - WITHIN + strong-textual → proceed; Stage 4 Pass C will fire to weigh the rebuttal
  - WITHIN + weak-interpretive OR absent → DROP at Stage 2 (cheapest kill, saves PoC budget)
  - PARTIAL + strong-textual → DOWNGRADE one tier
  - PARTIAL + weak-interpretive OR absent → DOWNGRADE one tier AND tag for Stage 4 Pass C close-call review
- **`code_comment_scan` is now mandatory on every FINDING.** Scans inline `//` and `/* */` comments adjacent to the cited bug for dev breadcrumbs (`TODO`, `FIXME`, `XXX`, `HACK`, `NOTE`, `SAFETY:`, `INVARIANT:`, "by design", "intentional", "we don't validate"). Dual-signal:
  - `SUPPORTS_FINDING` (e.g., `// FIXME: this allows X bypass`) → STRENGTHEN: include comment quote in `proof:` field; extra Stage 7 dup-check pass for git issues / commits.
  - `DOCUMENTS_AS_DESIGN` (e.g., `// NOTE: we deliberately don't validate timestamp; admin is trusted`) → DROP_AS_SC2: equivalent to a docstring disclaimer; the dev flagged the gap as intentional.
  - `NEUTRAL` → no signal.
  Schema: `local_scan` (file:line range scanned), `project_grep` (command run or "skipped — <reason>"), `matches` (each comment with classification + relevance), `verdict`.

### Added — `references/adversarial-review.md`

- **NEW Pre-Pass: scope-carveout + code-comment re-check, runs FIRST** (before External-research wave, before Mitigation viability check, before Pass A). The orchestrator independently re-runs both Stage-2 checks on the cited code and README. Rationale: a finding that lands inside a published scope carve-out OR is documented-as-design by an inline `// NOTE` is invalid regardless of how strong its PoC is. Killing here saves Wave-2 checker dispatch budget. The Pre-Pass produces NO subagent dispatch — pure orchestrator file-reads.
- Verdict matrix mirrors Stage 2 (KILL on WITHIN+weak/absent rebuttal, KILL on DOCUMENTS_AS_DESIGN HIGH-relevance, etc.) but with stricter language since this is the last gate before adversarial review.
- **NEW Pass C trigger #6: `CLOSE_CALL_REVIEW (scope-carveout)`** — fires when Pre-Pass scope carve-out re-check returned WITHIN with strong-textual rebuttal OR PARTIAL with any rebuttal quality. The judge weighs whether the rebuttal discharges the burden of proof against the carve-out's literal text.
- Pass C skip-condition tightened: judge now skipped only when ALL of {every challenge FAILS, no HIGH-conf challenges, Pass A=4 ranked, Pass B≥3, no uncited comparator claim, **AND scope-carveout re-check = OUTSIDE**}.
- Stage 4 verdict file schema gains a Pre-Pass section at the top with two tables (scope-carveout, code-comment) and `action` lines. If KILL fires here, the verdict file ends after this section — Pass A/B/C/D are skipped.

### Why this matters

C4 / Sherlock / Cantina judges enforce scope carve-outs strictly. Quoting the carve-out and arguing against it interpretively is a known failure mode — judges read "Administrator Mistakes" as covering ALL admin actions where validation is loose, not just the literal "malformed args" subset. The rebuttal-burden-of-proof rule (textual vs interpretive) is the discipline that closes the gap.

Code comments are the cheapest signal in the entire pipeline. A `// FIXME` adjacent to a bug location is the dev acknowledging the defect. A `// NOTE: by design` is the dev disclaiming it. Both are stronger evidence than any subagent reasoning, and v0.1.8 didn't read them.

### Files updated

- `references/hacking-agents/shared-rules.md` — `scope_carveout_check` and `code_comment_scan` fields mandatory; both included in FINDING schema box.
- `references/adversarial-review.md` — Pre-Pass added before existing Pre-Passes; Pass C trigger 6 added; verdict file schema extended; skip condition tightened.

### Expected effect on a re-run vs Reflector

If you re-run Argus on Reflector with v0.1.9 disciplines:

- **M-1** would be DROPPED at Stage 2 because `scope_carveout_check` matches "Administrator Mistakes" WITHIN with rebuttal_quality = `weak-interpretive` (Argus's "well-formed args don't fall under malformed-args carve-out" lacks textual support — the carve-out's full sentence binds loose validation to admin actions broadly).
- **L-3** would be DOWNGRADED at Stage 2 from Low to QA via PARTIAL match on "Oracle Data Staleness", with the writeup forced to separate the staleness limb (in carve-out) from the fee-asymmetry limb (out of carve-out).
- **H-1** (init front-run) would survive: the README's "A contract instance can only be initialized once" is an invariant (handled by `readme_invariant_check`), not a carve-out. No "Administrator Mistakes"-style section covers init races.
- **QA records=0 burn** would survive as QA: standard caller-mistake territory; not in any carve-out.

Projected v0.1.9 Reflector SUBMIT bucket: **8 findings** (was 10) — H-1 + 5 Mediums (M-2 → C4 H-01, M-3 → C4 M-02, M-5 → C4 M-03, two newly downgraded from Lows: L-1 → C4 M-04, L-2 → C4 M-01 — see v0.1.6 calibration heuristic) + L-3 (now QA after PARTIAL-match downgrade) + QA records=0. Removed: M-1 (Stage 2 drop), M-4 (already QA-equivalent in v0.1.8). 1 missed C4 Medium (M-05 `x_last_price` global-timestamp partial-update) remains uncaught — a Stage 2 catalogue gap not addressed by v0.1.9.

Combined v0.1.6 + 0.1.7 + 0.1.8 + 0.1.9 expected outcome on Reflector: **6/7 C4 risk findings caught, 0 confirmed false positives in SUBMIT bucket** (down from 1-2 borderline submissions in v0.1.8).

---

## [0.1.8] — 2026-05-04

External-judge re-pass release. The v0.1.5 swafe run was re-judged by an independent Judge agent which collapsed Argus's 8 SUBMIT findings to 3 surviving (H-2 High, M-1 Medium, M-3 Medium) and exposed three structural gaps that v0.1.6 / v0.1.7 didn't close:

| Argus | Judge re-pass | Why changed |
|-------|---------------|-------------|
| H-1 (recover_backups wrong field) High | QA/Low | `mark_recovery` only called by tests — bug unreachable from production. **Reachability gap.** |
| H-3 (no cnt-bump) High | QA (dup of H-2) | H-2's per-guardian-approval fix prevents replay. **Fix-subsumption gap.** |
| M-2 (revoke_association lag) Medium | INVALID (dup of H-2) | H-2 fix prevents the race. **Fix-subsumption gap.** |
| M-4 (post-recovery no cooldown) Medium | QA (dup of H-2) | Contingent on H-2 holding. **Fix-subsumption gap.** |
| M-5 (OR-of-N RIK weakest-link) Medium | Informational (SC-2) | README invariants #2 / #8 mandate OR-of-N. **README invariant gap.** |

v0.1.8 closes all three.

### Added — `references/hacking-agents/shared-rules.md`

- **`reachability_check` field is now mandatory on every FINDING.** Schema: `cited_function`, `callers_in_scope`, `callers_in_tests_only`, `reachable_from_public_entry: yes/no/unclear`. The angle MUST grep for callers, classify each (production / test-only / out-of-scope), and trace reachability back to a Stage 1 entry point. Verdict mapping:
  - `reachable_from_public_entry: yes` → proceed
  - only test callers → demote to LEAD or drop (the H-1 swafe case)
  - only out-of-scope callers → LEAD with dependency note
  - unclear → keep but Pass C fires
- **README invariant pre-check (NEW, MANDATORY)**. Adjacent to the docstring-disclaimer rule from v0.1.4. Before flagging a behavior as a vulnerability, the angle MUST scan the README and `assets/docs/` for invariants / properties / "must" / "only" statements that touch the bug area. New mandatory field `readme_invariant_check`: `scanned`, `touching_invariants` (verbatim quotes), `finding_contradicts_invariant: yes/no`, `verdict`. If yes, the finding is SC-2 candidate — either drop or reframe. The check is performed at Stage 2 (before emit) AND re-checked at Stage 4 Pass A (catches Stage-2 misses).

### Changed — `references/output-format.md` Phase 8a-pre dedupe

- **NEW Rule 1 in joint Pass C judge prompt: "Fix-subsumption check"**. Applied BEFORE the existing rules. Asks: "Would A's fix, applied alone, prevent B's exploit path from firing?" Heuristic: B's writeup contains "Combined with A" or "After a successful but unauthorized recovery (per A)" or similar contingency language → B is hardening under A → KILL_ONE(B); B's recommended-fix delta becomes a complementary hardening recommendation inside A's writeup. The four swafe v0.1.5 findings (H-2, H-3, M-2, M-4) collapse to 1 SUBMIT (H-2) + 3 hardening recommendations bundled inside it.
- Renumbered: old rule 1 ("different fixes") → new rule 2; tightened to "Different fixes ⇒ DISTINCT (only if neither fix subsumes the other)." The fix-subsumption check fires first.

### Why this matters

The Judge re-pass exposed that Argus had been *generating distinct-looking findings that all collapse under a single root-cause fix*. v0.1.6's "different fixes ⇒ DISTINCT" rule was too lax — it correctly distinguished F-15/F-02 (different fixes, neither subsumes the other) but failed on H-2 / H-3 / M-2 / M-4 (different fixes, but H-2's fix subsumes the others). The fix-subsumption rule is the missing layer.

The H-1 unreachability case and M-5 README-invariant case are both classes of "Argus claimed a bug without checking the most basic question." Reachability ("does this code actually run?") and README invariants ("does the protocol document this as intentional?") are both pre-Stage-2 sanity checks that the v0.1.5 angles skipped. v0.1.8 makes both mandatory FINDING schema fields.

### Files updated

- `references/hacking-agents/shared-rules.md` — `reachability_check` + `readme_invariant_check` fields mandatory.
- `references/output-format.md` — fix-subsumption rule as joint Pass C decision rule #1.

### Expected effect on a re-run vs swafe

If you re-run Argus on swafe with v0.1.6 + v0.1.7 + v0.1.8 disciplines:

- **H-1** would be demoted to LEAD at Stage 2 because `reachability_check` finds only test callers for `mark_recovery`.
- **H-3, M-2, M-4** would be merged under H-2 at Stage 8 dedupe via the fix-subsumption rule. H-2's writeup gets bundled hardening recommendations from all three.
- **M-5** would be demoted to LEAD or dropped at Stage 2 because `readme_invariant_check` quotes README invariants #2 and #8 as documenting OR-of-N as intentional.

Projected v0.1.8 SUBMIT bucket on swafe: **3 findings** (H-2 + bundled hardening, M-1, M-3) — exactly what the independent Judge re-pass produced. Plus the v0.1.7 catalogue catches still apply: 4 of the 4 swafe-missed C4 Mediums (M-03, M-05, M-06, M-07) become reachable via the Stage 2 catalogue gaps now closed.

Combined v0.1.5 + 0.1.6 + 0.1.7 + 0.1.8 expected swafe outcome: **6-7 of 7 C4 Mediums caught at correct severity, 0-1 false positives.**

---

## [0.1.7] — 2026-05-04

Stage 2 catalogue release. The v0.1.6 release fixed Stage 4's false-positive root causes (multi-agent checking, external research, mitigation check, dedupe tightening, severity recalibration). v0.1.7 fixes the parallel concern: Stage 2 misses on the swafe shadow audit. Of 7 C4 Mediums, Argus had 2 at SUBMIT, 1 in REFINE (downgraded by faulty dedupe — now fixed in v0.1.6), and 4 missed entirely. Each of the 4 missed maps to a specific Stage 2 catalogue / angle / template gap. v0.1.7 closes them.

### Added — `references/attack-vectors/rust-attack-vectors.md`

Three new vectors, calibrated against the swafe misses:

- **V61: Majority / quorum threshold off-by-one (`div_ceil` vs strict-majority)** — `n.div_ceil(2)` and `(n + 1) / 2` give correct strict majority for ODD N but exactly 50% for EVEN N. Vector Scan + Math Precision must search every `div_ceil` near `majority` / `quorum` / `threshold` / `consensus` / `vote` keywords. Maps to **C4 M-03**.
- **V62: Cryptographic / consensus primitive accepts degenerate parameter (`threshold = 0`, `count = 0`)** — early-return branches that produce constant or trivially-derivable output when the security parameter is 0. Reachable from public API or initial-state generation → on-chain artifact ships in degenerate state. Maps to **C4 M-06**.
- **V63: Unbounded `Vec<T>` storage with attacker-controllable length and per-element cost** — growable container with no `MAX_*` cap, append from public entry, and a hot-path linear-scan consumer doing per-element cryptographic work. Block-author DoS / CU-budget overrun. Maps to **C4 M-05**.

### Changed — `references/hacking-agents/shared-rules.md`

- **Cross-codebase weaponization is now MANDATORY with a structural enforcement field.** Every FINDING block MUST include a `weaponization_check:` field listing: the pattern signature searched for, the grep / Read commands used, every location checked with hit/miss outcome, and how multiple-instance hits are handled. Findings missing the field are rejected at Stage 2 dedup and the angle is asked to re-emit. Reasoning: the C4 M-07 swafe miss came from finding the `recover_backups` bug in `self.backups` and not asking "where else does this pattern apply?" — the `recover_id` bug skipping `rec.social` is the same root cause class at a parallel location. Maps to **C4 M-07**.

### Changed — `references/hacking-agents/math-precision-agent.md`

- New attack surface: **Threshold / quorum / majority direction (V61)**. Explicit instruction to search every `div_ceil`, `(n+1)/2`, `n/2` in the codebase near `majority` / `quorum` / `threshold` / `consensus` / `vote` keywords and check the even-N case.
- New attack surface: **Degenerate-parameter silent-success (V62)** — adjacent to math even though structural. Search every `share`, `split`, `combine`, `reconstruct`, `commit`, `interpolate` function for `if t == 0 { ... }` early-return branches.

### Changed — `references/hacking-agents/first-principles-agent.md`

- New focus area: **Degenerate-parameter silent-success (V62 territory)**. For every cryptographic / threshold-setting / counting primitive: "what happens when the input is `0`, `1`, or empty?" Every early-return branch in such primitives is a candidate.
- New focus area: **Initial-state-with-trivial-parameters trap**. Account-creation / contract-instantiation flows that populate state with `default()` / `0` / empty values for security-critical parameters. The trivial parameters become a leak vector for anyone holding adjacent secrets when the initial state ships in a publicly-readable transaction. Maps to the **swafe C4 M-06 mechanism**.

### Changed — `references/stage1-output-templates.md`

- **NEW Section 5 in `invariants.md` template: "Unbounded storage fields"** — mandatory enumeration of every growable storage container (`Vec<T>`, `BTreeMap<K,V>`, `HashMap<K,V>`) declared in scope. Each field gets a row with: append/insert site, documented cap, gate that enforces it, hot-path consumer, and bound-yes/no flag. Containers without entries are an enumeration miss. Containers with `Bound? = NO` and a hot-path consumer doing per-element work are Stage-2 candidate findings. Maps to **C4 M-05** by ensuring the Stage 1 model surfaces unbounded fields explicitly rather than the Stage 2 angle having to re-discover them.

### Expected effect on a re-run vs swafe

If you re-run Argus on swafe with v0.1.6 + v0.1.7 disciplines:

- **F-15 / C4 M-01** kept as SUBMIT via v0.1.6 dedupe fix.
- **C4 M-02** caught (was caught in v0.1.5).
- **C4 M-03 (div_ceil majority)** now caught by Math Precision angle's new V61 surface.
- **C4 M-04** caught (was caught in v0.1.5).
- **C4 M-05 (unbounded associations)** now caught by Stage 1 invariants template's new "Unbounded storage fields" enumeration.
- **C4 M-06 (threshold=0 backup)** now caught by First Principles angle's new "degenerate-parameter" / "initial-state-trivial-params" focus areas + V62 Math Precision surface.
- **C4 M-07 (recover_id missing rec.social)** now caught by shared-rules `weaponization_check` field — the angle that finds the `recover_backups` bug must report what other locations were searched and why the social-backup case was either covered or missed.

Expected v0.1.7 outcome on swafe: 6/7 C4 Mediums caught (vs 2/7 in v0.1.5). The remaining gap (if any) would surface a v0.1.8 catalogue gap.

### Files updated

- `references/attack-vectors/rust-attack-vectors.md` — V61, V62, V63 added.
- `references/hacking-agents/shared-rules.md` — `weaponization_check` field mandatory.
- `references/hacking-agents/math-precision-agent.md` — threshold-direction + degenerate-parameter surfaces.
- `references/hacking-agents/first-principles-agent.md` — degenerate-parameter + initial-state-trivial-params focus areas.
- `references/stage1-output-templates.md` — Section 5 "Unbounded storage fields" in invariants template.

---

## [0.1.6] — 2026-05-04

Defect-driven release. The v0.1.5 swafe (Code4rena 2025-11-swafe) shadow-audit produced 8 SUBMIT findings of which 2 matched real C4 Mediums (M-02, M-04, both upgraded to High by Pass D), 1 was a likely overshoot (H-2, generalized framing of M-06), and 5 were likely Lows promoted to Medium. Real C4 recall: 2/7 (29%) at SUBMIT, +1 partial in REFINE (M-01 = F-15, downgraded by faulty Stage 8 dedupe).

A line-by-line gap analysis vs The Judge (whose architecture Argus is patterned after) identified 14 mechanisms The Judge has that Argus lacks or implements weakly. v0.1.6 implements the top 5 most critical, plus tightens Stage 8 dedupe and Pass D severity calibration.

### Added — Stage 4 multi-agent architecture (the false-positive root-cause fix)

- **Pre-Pass external research wave (NEW, MANDATORY when applicable)**. Adapted from The Judge's Step 1.5. When a finding makes a claim about external protocol or library behavior (Anchor, OZ, Pendle, Pyth, wallet2, SPL Token, etc.), Argus spawns a Sonnet research agent to verify via WebSearch / WebFetch / direct comparator-source read. Result is cached session-wide and injected into all Pass A and Pass B checker prompts with the override instruction "trust this over your training data." UNVERIFIABLE claims force all dependent verdicts to UNCERTAIN. Reasoning: swafe v0.1.5 false positives asserted external behavior (wallet2, Anchor) without citation; the research wave forces those claims into the open.
- **Pre-Pass mitigation viability check (NEW, runs in background parallel with Pass A)**. Adapted from The Judge's Step 2.5. Background Sonnet agent determines if the finding's recommended fix is a clean fix or an inherent design trade-off (cure ≈ disease). TRADE_OFF + HIGH confidence → Pass D applies `MAX_SEVERITY = max(Low, existing)` cap. Reasoning: swafe v0.1.5 promoted M-3 (shared msk_ss_rik) to Medium when it's arguably a documented design trade-off; mitigation check would have capped it.
- **Pass A Wave 2 — parallel checker subagents with unanimity rule (NEW, MANDATORY)**. Adapted from The Judge's Wave 2 (lines 628-845). After the Pass A Selector returns 4 ranked invalidators, dispatch **2 parallel Sonnet checker subagents per top-2 invalidator** (4 total). Each checker independently reads cited code with the anti-hallucination rule injected into its prompt; returns HOLDS/FAILS/UNCERTAIN with confidence. Auto-kill requires **both checkers HIGH-confidence HOLDS** AND independent orchestrator verification of cited evidence. Any split or UNCERTAIN → Pass C MUST fire. Reasoning: F-03 false positive came from single-orchestrator confirmation bias; two independent code-readers each seeing only their assigned invalidator break the bias.
- **Pass B Wave 2 — parallel checker subagents with unanimity rule (NEW, MANDATORY)**. Same pattern as Pass A but with Opus model (issue-specific challenges benefit from broader reasoning). Filter Pass B challenges against Pass A first to drop overlapping mechanisms; dispatch top-2 surviving challenges to 2 parallel checkers each. Independent orchestrator verification on every HIGH HOLDS — F-03's false positive came from accepting a HIGH HOLDS Pass B challenge ("F-03 is the parser-side mirror of F-01") without independent verification.

### Changed — Stage 8 dedupe (catches the F-15 = M-01 case that v0.1.5 missed)

- **Lowered overlap thresholds**: re-pass triggers at `≥0.3` (was `≥0.5`); FLAG triggers at `≥0.15` (was `≥0.2`). Reasoning: swafe F-15/F-02 were at ~0.25 overlap, which fell in the FLAG band, but downstream binning collapsed them anyway. The 0.3 threshold catches this case directly via joint Pass C re-pass.
- **Tightened joint Pass C re-pass discipline**: new mandatory rule order — "different fixes ⇒ DISTINCT" applied BEFORE merge consideration. Different fixes mean shared subsystem ≠ shared root cause. The F-15/F-02 case has different fixes (`session_id` binding to GuardianShare vs `cnt` binding to RecoveryRequestMessage) and different code surfaces — they are DISTINCT, not subsumed.
- New mandatory `Different fixes?: yes/no` field in joint Pass C verdict file with both findings' Recommendations sections quoted.
- Added "when in doubt ⇒ DISTINCT" default ("better to file two related Mediums than to merge two distinct C4-payable findings").

### Changed — Pass D severity calibration (matches C4 historical severity, not just rule text)

- **NEW C4-style historical-severity heuristic table** in `adversarial-review.md` Pass D section. 7 bug-shapes that historically land at Medium in C4 / Sherlock / Cantina judging despite "indirect-with-attack-path" rule-text qualifying them as High: off-by-one threshold math, replay-without-version-binding, missing-cnt-increment, wrong-field-reference, linear-time-scan-DoS, single-point-of-failure-auth, stale-state-race. Pass D MUST consult the table before assigning Critical/High; if the bug shape matches, calibrate to Medium unless PoC shows unconditional system-wide unbounded loss.
- Counter-rule: `UPGRADE_OVERRIDE` field in verdict file required if heuristic-table-match is overridden, with cited PoC evidence.
- Reasoning: swafe Pass D upgraded H-1 (C4 M-02) and H-3 (C4 M-04) from Medium to High based on rule wording — both were Medium per C4. Calibrating to the rule produces severity inflation that triggers C4's deflation reflex.

### Files updated

- `references/adversarial-review.md` — Pre-Pass research + mitigation, Pass A/B Wave 2 dispatch, Pass D historical heuristic.
- `references/output-format.md` — dedupe thresholds, joint Pass C decision rules.

### Why these specific fixes

The line-by-line gap analysis vs The Judge identified 14 missing mechanisms. v0.1.6 implements the 5 highest-impact ones (multi-agent checking, external research, mitigation check, dedupe tightening, severity recalibration). The remaining 9 are tracked for future releases:

- Gap 4: Docstring-disclaimer SC-2 gating (already in v0.1.4, not strengthened in v0.1.6)
- Gap 5: HIGH-HOLDS override field (already in v0.1.4)
- Gap 6: Comparator-claim audit (already in v0.1.4)
- Gap 7: Pass B 3-challenge minimum (already in v0.1.4)
- Gap 8: Symmetric judge trigger (already in v0.1.4)
- Gap 10: PRIMARY vs SECONDARY scope (deferred — minor)
- Gap 11: Trust-model verification at Stage 4 (deferred — already partially implemented)
- Gap 12: Anti-hallucination enforcement gate (deferred — partially in Wave 2 prompts now)
- Gap 14: CSV batch mode + cross-issue cache (deferred — efficiency, not FP rate)

---

## [0.1.5] — 2026-05-04

### Added — Stage 0 Cost Preview

- **NEW Stage 0** runs after the user supplies inputs (target, bounty URL, repo URL) and before Stage 1's protocol mapping. It computes a per-stage cost breakdown specific to the target codebase, then asks the user to authorize via `AskUserQuestion` with options [A] Proceed / [B] Cap at Stage N / [C] Reduce scope / [D] Cancel. Cost authorization is mandatory even in auto-mode.
- `scripts/estimate-cost.py` — Python estimator. Parses `enumerate.sh` output for codebase metrics; computes per-stage token counts using calibrated formulas; multiplies by per-stage model mix (Sonnet/Opus split) and Anthropic list pricing; outputs a structured cost-preview block. Falls back to direct walk if `enumerate.sh` output isn't available.
- `references/cost-estimation.md` — methodology, pricing tables (Sonnet 4.5 / Opus 4.x / Haiku 4.5), per-stage model mix, per-stage token formulas, finding-count heuristic, subscription-tier envelopes, calibration history.
- Cost preview output includes: codebase metrics, per-stage table (input tokens, output tokens, wall-clock minutes, cost range low–high), API direct cost, subscription % envelopes (Pro / Max-5x / Max-20x), cost drivers specific to this run.
- Stage 0 todo added to the mandatory TodoWrite list (now 9 todos).
- `pipeline-overview.md` Stage 0 contract added before Stage 1.
- `SKILL.md` routing table updated.
- `install.sh` now copies `*.py` scripts.

### Why

Real Argus costs vary 100× across codebases. A flat estimate hides this; Stage 0 forces the model to compute a real estimate from actual codebase metrics before the user authorizes the run. Tested against vault-protocol (901 nSLOC, Anchor): produces $36–$62 estimate, ~42–66 min wall-clock, 46–76% of Pro 5h window.

---

## [0.1.4] — 2026-05-04

Defect-driven release. The v0.1.3 monero-oxide run produced 3 SUBMIT findings of which 2 were false positives (33% FP rate at Stage 8). Self-audit identified seven concrete failures: 3 execution errors in Stage 4 (sloppy docstring read, deferred HIGH-HOLDS, undersized Pass B), 2 structural gaps in Pass C triggers (no procedural-thinness fire, no comparator-claim audit), and 2 reasoning gaps (Stage 2 didn't read function docstrings before flagging, Stage 8 didn't dedupe by citation overlap). v0.1.4 implements all seven fixes plus the Tier-1 E2E + 80% certainty discipline the user requested.

### Changed — Stage 4 (the false-positive killer that wasn't catching false positives)

- **Pass A procedural floor (MANDATORY)**: Selector MUST rank exactly 4 invalidators. Fewer than 4 → Pass C MUST fire on procedural-thinness grounds (`CLOSE_CALL_REVIEW (procedural)` mode). Verdict files with empty selector slots are invalid. Reasoning: thin Pass A is the failure mode that produced the F-10 false positive — only 2 invalidators selected, SC-3 missed.
- **Pass B procedural floor (MANDATORY)**: ≥3 challenges required. Fewer → Pass C MUST fire. Each missing slot must be explicitly accounted for with a reason. Reasoning: F-10 had 1 challenge of 3-5 required; the obvious comparator-verification challenge was never written.
- **Pass C HIGH-HOLDS justification (MANDATORY)**: when the judge produces VALID despite a HIGH-conf HOLDS in Pass A or Pass B, the verdict MUST contain a `high_holds_overrides` field with code-cited justification per overridden HOLDS. "Stage 8 will figure it out" / "let later stages handle" are explicitly REJECTED. Reasoning: F-03 false positive came from Pass C silently overriding a HIGH-conf HOLDS Pass B challenge.
- **Pass C procedural-recovery mode**: when Pass C fires in `(procedural)` mode, the judge MUST generate the missing Pass A invalidators + Pass B challenges before rendering verdict. Procedural thinness is recovered, not rubber-stamped.
- **Pass C comparator-claim mode (NEW)**: any finding whose impact case relies on uncited comparison to an external system (wallet2, Anchor, OZ, Pyth, etc.) forces Pass C in `CLOSE_CALL_REVIEW (comparator-claim)` mode. Reasoning: F-10's wallet2 framing was the entire impact case yet was never required to cite wallet2 source.

### Changed — Stage 2 angle discipline (catch false positives at the source)

- **Docstring discipline (MANDATORY)** in `references/hacking-agents/shared-rules.md`: before flagging a function's behavior as a bug, the angle MUST read the function's own `///` doc comment and quote any behavior disclaimer ("may", "not guaranteed", "best effort", "permissive", etc.). Disclaimers route the finding to SC-2 candidacy or drop it. Recorded as `docstring_disclaimer` field in F-NN.md. Reasoning: F-03 false positive came from missing the docstring disclaimer in `Transaction::read` ("the result is not guaranteed to follow all Monero consensus rules").
- **Comparator-claim discipline (MANDATORY)** in `references/hacking-agents/shared-rules.md`: when a finding's impact case relies on comparison to an external system, the comparator's source code MUST be cited (`<repo>/<file>:<line>` or URL). Uncited comparator claims demote the finding to LEAD at Stage 2.

### Changed — Stage 3 PoC E2E discipline + 80% certainty floor

- **Tier-1 E2E is now THE PRIMARY TARGET**, not just preferred. Tier-2/3 are fallbacks requiring explicit Tier-1-attempted justification.
- **80% certainty floor for ADVANCE**: every Stage 3 verdict assigns a certainty score (0-100). Tier 1 actually-run E2E = 90-100. Tier 2 integration = 75-89. Tier 3 minimal repro = 60-79. Tier 4 derivation = 30-59. Findings below 80 receive `DOWNGRADE(refine)` at Stage 3 and do NOT advance to Stage 4 with weak proof.
- **RPC discovery (NEW MANDATORY procedure)**: when the bug requires real chain state, Stage 3 must discover and configure the correct RPC path before bailing to Tier 2. Discovery order: project config (Anchor.toml, solana config) → localnet (`solana-test-validator`) → devnet → mainnet-fork (`solana-test-validator --clone <PROGRAM_ID>`). Tier-1 verdict.md MUST include the RPC-discovery checklist.
- **"Actually run" requirement**: a Tier-1 PoC that compiles but is never executed caps at certainty 60. Captured stdout/stderr is mandatory in repro.md.
- **Tier-1-attempted section (MANDATORY for Tier 2/3/4)**: every below-Tier-1 verdict must enumerate what RPC discovery was attempted and the specific failure. Skipping Tier-1 RPC discovery = procedural failure → Stage 3 re-runs.

### Added — Stage 8 dedupe pre-pass

- **Phase 8a-pre Citation-overlap dedupe (NEW MANDATORY phase)**: before binning into triage files, Stage 8 computes citation overlap across every pair of Stage 7 ADVANCE findings. Pairs with ≥50% line-citation overlap and same root cause → MERGE. Pairs with ≥50% overlap and different root cause → STAGE-4 RE-PASS (joint Pass C) to resolve "one bug or two?". Pairs with 20-50% overlap → FLAG with cross-reference. Output: `$RUN_DIR/8-final/_dedupe-summary.md` + per-pair re-pass verdicts. Reasoning: F-03 and F-01 both cited `transaction.rs:282` and shipped as separate findings; the Stage-2 dedupe-by-`group_key` missed them because `bug_class` tags differed.

### Files updated

- `references/adversarial-review.md` — Pass A/B procedural floors, HIGH-HOLDS handling, comparator-claim mode, docstring-disclaimer pre-check, schema fields.
- `references/hacking-agents/shared-rules.md` — docstring discipline, comparator-claim discipline.
- `references/poc-standards.md` — Tier-1 as PRIMARY TARGET, RPC discovery, 80% certainty floor, Tier-1-attempted section, certainty rubric.
- `references/output-format.md` — Phase 8a-pre dedupe section.
- `references/pipeline-overview.md` — Stage 3, Stage 4, Stage 8 contracts updated.

---

## [0.1.3] — 2026-05-04

### Changed

- **Stage 3 PoC discipline tightened.** Tier-3 is now the explicit floor for every non-allowlist finding. Tier-4 written derivation is restricted to cases where an 8-question self-audit (math reduction / single-fn / two-fn sequencing / struct invariant / pure helper / state machine / borsh round-trip / crypto primitive) confirms infeasibility on every question. Motivated by the vault-protocol test run where F-13 / F-06 settled for Tier-4 derivation when Tier-3 reproducers were buildable.
- `references/poc-standards.md` rewritten "PoC tier preference" section: Tier-3 is THE FLOOR; new "Tier-3-buildable test" subsection with 8-question self-audit; new "What Tier-3 is NOT permitted to skip" subsection rejecting common-but-wrong reasons; new "Shared reproducer pattern" subsection guiding `_<class>-reproducer/` crate layout for multi-finding math/state bug clusters.
- `references/poc-standards.md` new "Anchor-specific Tier-3 patterns" subsection: Pattern A (pure logic extraction), Pattern B (account-struct simulation calling handler logic without `BanksClient`), Pattern C (`solana-program-test` only when CPI matters). Includes a worked Anchor example.
- `references/poc-standards.md` `verdict.md` schema now requires the `tier-3-attempted` self-audit table for every Tier-4 verdict; if any answer is "yes" without explicit infeasibility justification, the Tier-4 verdict is invalid.
- `references/poc-standards.md` new "Tier-4 specific anti-patterns" subsection rejecting "two functions in two files", "needs `solana-program-test`", "depends on F-X being deployed", "requires real chain state" as Tier-4 justifications.
- `references/poc-standards.md` new "Stage 3 quality bar" section: Argus's value is building reproducers, not arguing why reproducers weren't built. Tier-4 in a run is a signal to question whether buildable work was skipped.
- `references/pipeline-overview.md` Stage 3 OPERATIONS block rewritten to call out Tier-3-as-floor, the mandatory self-audit, and the shared-reproducer pattern.
- `SKILL.md` Stage 3 routing updated to reflect the tightened discipline.

---

## [0.1.2] — 2026-05-04

### Added

- **Stage 8 Phase 8b — Report formatting**. After Phase 8a writes the triage files, Argus now uses `AskUserQuestion` to ask the user which platform's report template to format the SUBMIT findings in, then writes per-finding writeups under `$RUN_DIR/8-final/submission-formatted/F-NN.md` plus an `index.md` in the matching template.
- `references/report-templates/` with 7 platform templates: `code4rena.md`, `sherlock.md`, `cantina.md`, `immunefi.md`, `hackenproof.md`, `codehawks.md`, `generic.md`. Each template includes the platform's expected sections, discipline rules, anti-patterns, and ID-assignment conventions (`[H-N]` / `[M-N]` / `[L-N]` for C4-style; structured severity field for Cantina/Immunefi/HackenProof).
- Cantina template includes the AI-3 manual-validation acknowledgment line (mandatory per Cantina rules).
- Generic template includes a full validation-trace table + AI-provenance disclosure (recommended for portable submissions).
- HackenProof template includes a self-checklist for the four pre-validation gates (commit/version, scope, dup, PoC).
- `references/output-format.md` Phase-8b section with the 4-step formatting workflow.
- `references/pipeline-overview.md` Stage 8 contract updated to two phases.
- `SKILL.md` Stage 8 routing updated.

### Changed

- Stage 8 EXIT CONDITION extended: if SUBMIT bucket non-empty AND user picked a template, every SUBMIT finding must have a `submission-formatted/F-NN.md`.

---

## [0.1.1] — 2026-05-04

### Added

- `scripts/install-deps.sh` — Stage 3 pre-flight toolchain installer. Detects project shape (Anchor / CosmWasm / Substrate / Solana-native / generic-Rust) and reports / installs missing user-space dependencies (`rustup`, `cargo`, `solana`, `anchor`, `avm`, `node`, `yarn`, `wasm32-unknown-unknown` target). Dry-run by default; `--install` mode runs only after the user confirms via AskUserQuestion. System-package installs (clang, protobuf, cmake) are surfaced as suggestions only — Argus never sudo-installs. Motivated by a real CodeHawks RustFund run where Stage 3 couldn't run Tier 1-2 PoCs without Solana / Anchor on PATH.
- `references/poc-standards.md` "Pre-flight: toolchain check" section. Stage 3 now stops to ask the user (install / skip-with-tier-3-cap / cancel) when toolchain is missing instead of silently degrading to Tier 4.
- `pipeline-overview.md` Stage 3 contract updated to call out the pre-flight step.

### Changed

- `install.sh` already copies `scripts/`; no change needed there.

---

## [0.1.0] — 2026-05-04

### Added

- Initial release of the Argus Rust-first submission-grade audit skill.
- 8-stage pipeline (mapping → audit → PoC → adversarial → platform → program → dup → output) plus optional Stage 9 (fix verification).
- 8 parallel attacker angles for Stage 2 (Vector Scan, Math Precision, Auth/Account/Signer/Origin, Economic Security, Execution Trace, Invariant, Periphery, First Principles), each in its own `references/hacking-agents/<angle>-agent.md`.
- Rust-native attack vector library (35+ vectors) at `references/attack-vectors/rust-attack-vectors.md`.
- Stage 4 four-pass structure: generic invalidator selector + checker (Pass A), issue-specific adversarial generator + checker (Pass B), symmetric neutral judge (Pass C), and independent severity calibrator (Pass D).
- 13-category Rust-tuned invalidation catalogue (UP/CP/DT/EG/US/SH/DI/TI/SC/IM/AM/OS/TR) with ~55 specific reasons.
- Per-platform criteria files at `references/platform-criteria/{code4rena, sherlock, sherlock-bb, cantina-comp, cantina-bb, immunefi, hackenproof, generic}.md`.
- Cantina manual-validation acknowledgment gate at Stage 5 (per Cantina rule AI-3).
- HackenProof reversibility rule at Stage 6 (`DOWNGRADE(refine)` preferred over premature `KILL` when borderline).
- Triage comment templates in `program-triage.md`.
- Fix verification at optional Stage 9 with completeness + regression + smart-contract-Rust-specific checklists.
- Live-page WebFetch with bundled-criteria divergence logging.
- AI-provenance reminder in `submission-grade.md` header + terminal print.
- Severity divergence tracking (CONFIRMED / UPGRADED N-tier / DOWNGRADED N-tier) with low-confidence + ≥2-tier divergence warning.
- Mode-warning confidence caps (75 / 70 / 65) for generic-program-mode, local-only-dup-mode, severity-divergence-warning, criteria-divergence.
- Slash commands: `/argus` (full pipeline) and `/argus-fix-verify` (Stage 9 only).
- Claude Code plugin marketplace integration (`.claude-plugin/marketplace.json` + `plugin.json`).
- OpenAI-compatible agent definition (`agents/openai.yaml`).
- `install.sh` for direct install to `~/.claude/skills/argus/`.
- Eval runner + compare-to-ground-truth scaffolding under `evals/`.
- Assets folder for project-docs and prior-findings carry-forward (mirrors Solidity Auditor's pattern).
