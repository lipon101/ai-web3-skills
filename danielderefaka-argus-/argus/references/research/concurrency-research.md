# Concurrency & Atomics — Research Dossier

> **Feeds**: `hacking-agents/infra/concurrency-agent.md`
> **Last research pass**: 2026-06-05 · **Sources reviewed**: 8 verified advisories/incidents (each with a fetched primary URL in §7) + 1 cross-language (Go) precedent + 2 verified tools
> **Status**: drafted-verified

> **Verification note**: This dossier was re-built from primary sources after a prior model-memory draft failed verification (0/11). Every RUSTSEC/CVE id below was fetched from rustsec.org, github.com/rustsec/advisory-db, or the project's own issue/PR tracker; the URL is in §7. Mechanisms not tied to a fetched id are labelled `[generic pattern — no specific incident]`. No id is attached to an unverified mechanism.

> **Anchor case (lock-ordering deadlock — TIER 1, fetched)**: OpenEthereum/Parity Ethereum issue **#9952** (fixed by PR **#9954**, shipped in 2.2.2-beta). Two `RwLock`s in `blockchain.rs` — `best_ancient_block` and `best_block` — were acquired in opposite orders by two reachable paths: `commit` write-locked `best_ancient_block` then waited for `best_block`; concurrently `chain_info` read-locked `best_block` then waited for `best_ancient_block`. Circular wait → deadlock; the node stops importing blocks. The regression was introduced by an earlier PR (#8643). The fix reordered acquisition to a single canonical order, stopped waiting forever for the sync lock, and dropped `sync_channel` in favour of an async channel for block propagation. This is the defining DLT concurrency class: **two locks, two orders, one cycle, chain stalls** — and it is mechanically discoverable by lock-order graph construction + Loom.

> **Anchor case (atomic-ordering relaxation — TIER 3, fetched)**: **RUSTSEC-2022-0006** (`thread_local` < 1.1.4). `Iter::next` / `IterMut::next` "used a weaker memory ordering when loading values than what was required, exposing a potential data race." This is the canonical real instance of the D04 class — code that passes under low contention but is unsound because a `Relaxed`/under-strength load lacks the `Acquire` edge needed to observe a paired write. It proves the class is real in shipping infrastructure crates, not just textbook.

---

## 0. Calibration headline

Concurrency bugs in DLT infrastructure split into three impact classes. **(1) Deadlock / validator stall** — a lock cycle in import- or consensus-critical code halts a node; verified real instance: Parity #9952 (lock-order cycle in `blockchain.rs`). **(2) Data race → memory corruption or state corruption** — unsynchronized or under-synchronized access to shared state; verified real instances: tokio oneshot RUSTSEC-2021-0124 (memory corruption), crossbeam-deque RUSTSEC-2021-0093 (task popped twice → double-free), thread_local RUSTSEC-2022-0006 (weak-ordering race). **(3) Unsoundness via missing trait bound** — a `Send`/`Sync` gap lets a non-thread-safe value cross threads; verified real instance: tokio broadcast RUSTSEC-2025-0023 (parallel `clone` without `Sync`).

The modal *deadlock* bug is **lock-ordering** — two paths take the same locks in different orders (Parity #9952 is exactly this; Loom finds it mechanically). The modal *memory-safety* concurrency bug in the Rust ecosystem is **a race in `Drop`/teardown of a channel or queue** — three separate crossbeam/tokio advisories (RUSTSEC-2025-0024, -2021-0093, -2018-0009) are teardown/steal/GC double-frees. The most insidious is **atomic ordering relaxation** — RUSTSEC-2022-0006 shows it ships in production and survives ordinary testing; no production tool systematically detects under-synchronization, so manual trace + Loom is the only control.

Tool coverage: **STRONG for deadlocks and ordering violations** (Loom — explores interleavings under the C11 memory model with state-reduction, catches data races and ordering violations); **MEDIUM for large async systems** (AWS Shuttle — *randomized*, not sound, not exhaustive; scales where Loom cannot); **MEDIUM for data races on `UnsafeCell`** (Miri `-Zmiri-detect-data-races`); **WEAK for atomic under-synchronization** (no tool systematically flags it; Loom helps only if you write the harness).

---

## 1. Bug-class taxonomy

> "Real instance" column is a fetched advisory/issue URL (see §7) or `[generic pattern]`. No id is attached to an unverified mechanism.

| Class | One-line mechanism | Real instance (fetched) | Argus coverage |
|-------|--------------------|-------------------------|----------------|
| **D01 Lock-ordering deadlock** | Path A takes lock X→Y; Path B takes Y→X; concurrent execution deadlocks | **VERIFIED**: OpenEthereum/Parity #9952 — `commit` (best_ancient_block→best_block) vs `chain_info` (best_block→best_ancient_block) circular wait → import stall (fixed PR #9954) | **YES** — Loom-verified graph cycle detection |
| **D02 Race in channel/queue teardown (Drop/GC)** | Teardown path frees an element/block that another path also frees; double-free / UB | **VERIFIED**: RUSTSEC-2025-0024 (crossbeam-channel `discard_all_messages` reads `head.block` on two paths, swaps on one → `Channel::drop` frees twice); RUSTSEC-2018-0009 (crossbeam MsQueue/SegQueue: popped element also dropped by epoch GC) | **PARTIAL** — agent flags double-free but no teardown-path-symmetry procedure |
| **D03 Work-stealing / queue steal race** | Steal logic pops a task twice (or forgets one) under concurrent steal | **VERIFIED**: RUSTSEC-2021-0093 (crossbeam-deque `Stealer::steal*` — task popped twice → double-free / leak / logic bug) | **NO** — not covered |
| **D04 Atomic ordering under-synchronization** | A load/store uses a weaker ordering than the happens-before it relies on; reader sees flag but not the guarded write | **VERIFIED**: RUSTSEC-2022-0006 (thread_local `Iter/IterMut::next` weaker-than-required load ordering → data race) | **PARTIAL** — agent mentions Release/Acquire mismatch but no per-atom data-guarding trace |
| **D05 Data race after channel close (use-after-close)** | `send` races `recv`/`await`/`try_recv` after `close`; both halves touch shared memory | **VERIFIED**: RUSTSEC-2021-0124 / CVE-2021-45710 (tokio oneshot: `Sender::send` vs `Receiver::await`/`try_recv` after `Receiver::close` → shared-memory data race → memory corruption) | **PARTIAL** — agent covers channel-close race but no close-then-use trace |
| **D06 Missing Send/Sync bound on parallel operation** | An operation runs `clone`/access in parallel across threads but only bounds `Send`, not `Sync`; non-`Sync` value escapes | **VERIFIED**: RUSTSEC-2025-0023 (tokio broadcast clones stored value in parallel on receive, requires only `Send` → unsoundness for `Send`-not-`Sync` types) | **NO** — not covered |
| **D07 Lock held across `.await`** | `MutexGuard` alive across `.await`; `std::sync::Mutex` guard is `Send`, so it compiles but can drop on a migrated thread (UB) or block the runtime | `[generic pattern — no specific incident]` (clippy `await_holding_lock` exists precisely because this class is common; no fetched DLT advisory) | **PARTIAL** — agent mentions DoS angle, not the `std::sync::Mutex`-in-async unsoundness |
| **D08 Channel-hang on sender drop** | Receiver loop treats channel-closed (`None`/`RecvError`) as transient; subsystem stalls when all senders drop | `[generic pattern — no specific incident]` | **NO** — no detection procedure |
| **D09 `select!` cancellation unsafety** | A losing `select!` branch is dropped mid-operation; partially-written state already published to another task | `[generic pattern — no specific incident]` (cross-ref Logic/State Machine) | **PARTIAL** — covered by Logic/State, not concurrency agent |
| **D10 Thread-pool / blocking-call exhaustion deadlock** | All workers block on work scheduled to the same pool → circular resource wait (`block_in_place`/`spawn_blocking`/rayon `scope`) | `[generic pattern — no specific incident]` | **NO** — not covered |
| **D11 Reentrant read-lock deadlock (fair RwLock)** | A thread holding a read lock takes the same read lock again while a writer waits; fair policy blocks the second reader → self-deadlock | `[documented footgun]` — `parking_lot::RwLock` docs explicitly warn recursive read-lock may deadlock under task-fair policy (not a RUSTSEC advisory) | **NO** — not covered |
| **D12 Cross-language precedent: concurrent-map race (Go)** | Two goroutines read/write a shared map without a lock; Go runtime aborts ("concurrent map read and map write") | **VERIFIED (Go)**: go-ethereum #2650 — `TxPool.GetTransaction` unsynchronized map access under load → fatal runtime abort | N/A — methodology precedent, not a Rust check |

---

## 2. Per-class methodology

> Each procedure answers: "what systematic step finds this **without already knowing the answer**?"

### D01 — Lock-ordering deadlock

**Signal**: ≥2 distinct locks (`Mutex`, `RwLock`, `tokio::sync::Mutex`) acquired in different orders across ≥2 reachable code paths. In Parity #9952 the two locks were two `RwLock` fields on the same struct (`best_ancient_block`, `best_block`).

**Procedure**:
1. Enumerate every acquisition site: `.lock()`, `.write()`, `.read()` (std, parking_lot, tokio).
2. Build a directed graph: node = lock identity (prefer field-level identity, not just type — Parity's cycle was between two fields of the *same* struct, invisible if you only track types); edge A→B = "A acquired while B still held."
3. Any cycle = deadlock candidate.
4. Confirm both paths are concurrently reachable (not both under one outer lock). Parity's were: `commit` (block import) and `chain_info` (informant status print) run on different threads.
5. Write a Loom test driving both paths; Loom permutes interleavings under the C11 model and surfaces the deadlocked schedule.

**Mechanical evidence**: Loom panics with a deadlock / no-progress schedule. **Golden signature**: Loom reports a stuck schedule where each thread waits on the lock the other holds.

**Anti-pattern (false-positive guard)**: two locks always taken under a third outer lock cannot cycle; a cycle on locks that are provably never concurrently live (e.g., init-only vs steady-state) is not a bug.

**Source**: Parity #9952 / PR #9954 (T1, fetched).

### D02 — Race in channel/queue teardown (Drop / GC double-free)

**Signal**: a teardown/cleanup function (`Drop`, `discard_all_messages`, epoch-GC `defer`) that frees or drops elements which another path may also free.

**Procedure**:
1. Find every `Drop` impl and every manual teardown on a type holding raw pointers / `Box`/heap nodes (channels, queues, arenas).
2. For each, enumerate **every path that can free a given element**. RUSTSEC-2025-0024's root cause: two paths read `head.block` but only one swapped it to null → the other path and `Channel::drop` both free it.
3. Assert teardown is idempotent: once an element is taken, the slot must be nulled/swapped on **every** path before another consumer or the destructor runs.
4. For epoch-GC types (crossbeam-style), verify a popped element is wrapped so the collector does not also drop it (RUSTSEC-2018-0009 fix wrapped elements in `ManuallyDrop`).
5. Loom/Shuttle a producer + consumer + drop interleaving and run under Miri to catch the second free.

**Mechanical evidence**: Miri `error: Undefined Behavior: double free` under the interleaving; Loom-driven Drop schedule.

**Anti-pattern**: a single-owner teardown with no concurrent consumer is not D02 (no second freeing path).

**Source**: RUSTSEC-2025-0024, RUSTSEC-2018-0009 (T3, fetched).

### D03 — Work-stealing / steal race

**Signal**: a `Stealer`/work-stealing queue where `steal`, `steal_batch`, or `pop` can run concurrently with another steal/pop.

**Procedure**:
1. Identify every concurrent consumer of the same deque/queue (stealers + owner).
2. Trace the index/epoch arithmetic that decides which slot a steal claims. The RUSTSEC-2021-0093 bug: under a specific interleaving, one task is claimed by two stealers (popped twice) while another is skipped.
3. Property to assert (Loom/Shuttle): **each enqueued item is dequeued exactly once across all consumers** — no double-pop, no lost item.
4. If items are heap-allocated, double-pop ⇒ double-free; assert under Miri.

**Mechanical evidence**: Loom property "every item observed exactly once" fails; Miri double-free.

**Anti-pattern**: single-consumer queue (no stealers) cannot exhibit a steal race.

**Source**: RUSTSEC-2021-0093 (T3, fetched).

### D04 — Atomic ordering under-synchronization

**Signal**: any `Atomic*` load/store whose `Ordering` is weaker than the happens-before the surrounding code relies on. RUSTSEC-2022-0006 is exactly this — an iterator `next` loaded with weaker ordering than required.

**Procedure**:
1. Enumerate every `Atomic*` op and record its `Ordering`. Flag every `Relaxed` and every "lone" `Release`/`Acquire` with no pair.
2. For each, answer: **what non-atomic data does this atomic gate?** If the atomic is a readiness/version flag, identify the data write it is supposed to publish and the data read it is supposed to guard.
3. Trace the publish side: is the data write ordered-before the flag store? A `Relaxed` store cannot publish a prior write to an `Acquire` reader.
4. Trace the consume side: a `Relaxed` load cannot establish happens-before for the subsequent data read (RUSTSEC-2022-0006's exact failure: load too weak → race).
5. Fix shape: writer `Release`, reader `Acquire` (or matched fences). Verify fence sidedness.
6. Cross-platform: a `Relaxed` bug benign on x86 (TSO) can manifest on ARM (weak). For any `Relaxed` atomic on a consensus/state-critical path, assume reorder on ARM.

**Mechanical evidence**: no tool systematically detects this. Loom catches ordering violations *if you write a harness exercising both sides* (note Loom treats `SeqCst` as `AcqRel` and under-explores load-buffering → some false positives, some misses). Manual trace is the primary control.

**Anti-pattern**: a `Relaxed` counter that gates nothing (pure statistic, never used to publish/consume data) is not D04.

**Source**: RUSTSEC-2022-0006 (T3, fetched — the only verified instance; generalize the *procedure*, not this crate).

### D05 — Data race after channel close (use-after-close)

**Signal**: a channel/oneshot whose `close()` (or receiver-drop) can be concurrent with a `send`/`recv`/`await`/`try_recv` on the other half.

**Procedure**:
1. For every channel type, list the operations on each half and which can run concurrently across threads.
2. Specifically test the **close-then-use** ordering: receiver calls `close`, then sender `send`s while receiver `await`s or `try_recv`s. RUSTSEC-2021-0124's exact race: both halves then touch the same memory → corruption.
3. Loom/Shuttle the {close, send, recv} interleaving; assert no shared-location data race (run under Miri for the UB).
4. For application code *using* such a channel: ensure the protocol forbids send-after-close, or upgrade the dependency past the patched version.

**Mechanical evidence**: Miri data-race / memory-corruption diagnostic under the close-then-use schedule.

**Anti-pattern**: a channel where one half is provably dropped before the other is ever touched cannot race.

**Source**: RUSTSEC-2021-0124 / CVE-2021-45710 (T3, fetched).

### D06 — Missing Send/Sync bound on a parallel operation

**Signal**: an API that performs `clone`/read of a stored value **in parallel** across receivers/threads but its bound is only `Send` (or unbounded), not `Sync`.

**Procedure**:
1. Find data structures that fan a value out to multiple consumers concurrently (broadcast channels, shared caches, parallel iterators that `clone`).
2. Ask: does the consumer-side touch (clone/read) happen on multiple threads **simultaneously** for the **same** value? If yes, the value must be `Sync`, not merely `Send`.
3. RUSTSEC-2025-0023's exact gap: tokio broadcast clones the stored value in parallel on receive but bounded only `T: Send` — a `Send`-but-not-`Sync` type with thread-local invariants is then cloned concurrently → unsound.
4. For your own such API: assert the bound matches the access pattern (parallel same-value access ⇒ `Sync`). For dependency use: pin past the patched tokio version.

**Mechanical evidence**: this is a *type-bound* soundness gap — the proof is the trait-bound mismatch + a witness `Send`-not-`Sync` type, not a runtime tool. Construct a witness type whose `Clone` relies on `!Sync` invariants and show it compiles.

**Anti-pattern**: a structure that only ever `clone`s on one thread at a time (e.g., single-consumer) needs only `Send`.

**Source**: RUSTSEC-2025-0023 (T3, fetched).

### D07 — Lock held across `.await`

**Signal**: a `std`/`parking_lot` `MutexGuard`/`RwLock*Guard` alive across an `.await`.

**Procedure**:
1. Enable `#[warn(clippy::await_holding_lock)]`; it catches the obvious cases.
2. For misses (guard in a struct field, guard from an unnamed temporary): find every `.await` with a lock guard in scope.
3. Multi-threaded tokio: a `std::sync::MutexGuard` is `Send`, so holding it across `.await` **compiles** but can drop on a migrated worker thread (unsound) or block a runtime worker. `tokio::sync::Mutex` guard is `!Send` → the same mistake is a compile error.
4. Rule: hold `std::sync::Mutex` only for non-`.await` critical sections; use `tokio::sync::Mutex` when the guard must cross `.await`.

**Mechanical evidence**: clippy `await_holding_lock`; otherwise manual audit (no fetched DLT advisory anchors this — it is a `[generic pattern]`).

**Anti-pattern**: a guard explicitly dropped (or scoped) before the `.await` is fine.

**Source**: `[generic pattern — no specific incident]`; clippy lint exists because the class is prevalent.

### D08 — Channel-hang on sender drop

**Signal**: a `recv()` loop whose only exit is `Ok(msg)`; channel-closed is treated as transient.

**Procedure**: for every receiver loop, confirm the closed signal (`None` from tokio `recv`, `Err(RecvError)` from std) is a **terminal** branch that shuts the subsystem down, not a `continue`/retry. Test: drop all senders mid-`recv`; assert the loop exits.

**Mechanical evidence**: a unit test dropping all senders; assert termination. **Source**: `[generic pattern — no specific incident]`.

### D09 — `select!` cancellation unsafety

**Signal**: `tokio::select!` where a branch performs a multi-step mutation or publishes partial state before it can be cancelled.

**Procedure**: per branch, ask "if this branch is dropped mid-flight, is any partially-written state already visible to another task?" Guard ranges/buffers behind cancellation-safe primitives (oneshot, `CancellationToken`) or make each branch atomic. **Cross-reference Logic/State Machine** (partial-state). **Source**: `[generic pattern — no specific incident]`.

### D10 — Thread-pool / blocking-call exhaustion deadlock

**Signal**: `block_in_place` / `spawn_blocking` / rayon `scope()` inside a worker that waits on work scheduled to the same pool.

**Procedure**: find each such call; check whether it (transitively) waits on tasks needing the same pool; if all workers can be parked this way → deadlock. Stress test by saturating the pool with self-dependent tasks. **Source**: `[generic pattern — no specific incident]`.

### D11 — Reentrant read-lock deadlock (fair RwLock)

**Signal**: a thread acquires a `read()` guard, then (directly or via a callee) acquires `read()` on the **same** `RwLock` while it still holds the first.

**Procedure**: trace each `read()` guard's live range; if a re-entrant `read()` on the same lock can occur while a writer may be queued, a task-fair `RwLock` (parking_lot) will block the second reader → self-deadlock. Prefer non-reentrant designs or re-architect to take the lock once. **Source**: parking_lot `RwLock` docs (documented footgun, fetched in §7) — not a RUSTSEC advisory.

---

## 3. Framework-specific knowledge

- **`std::sync::Mutex` guard is `Send`; `tokio::sync::Mutex` guard is `!Send`.** This single fact decides D07: the std guard held across `.await` compiles but is unsound on a multi-threaded runtime; the tokio guard is a compile error. (Rust async semantics.)
- **tokio `mpsc::Receiver::recv()` returns `None` on all-senders-dropped + empty**; `std::sync::mpsc` returns `Err(RecvError)`. D08 turns on whether code treats these as terminal. (tokio/std docs.)
- **crossbeam epoch GC defers Drop.** A popped element can be dropped twice (pop + deferred GC) unless wrapped (`ManuallyDrop`) — the literal RUSTSEC-2018-0009 fix. Any epoch-based structure (crossbeam-epoch, seize-style) is a D02 hotspot.
- **Field-level lock identity matters for D01.** Parity #9952's cycle was between two `RwLock` *fields of one struct*; a type-only lock graph would have missed it. Track lock identity at field granularity.
- **parking_lot `RwLock` is task-fair**: a recursive read-lock can deadlock when a writer is queued (D11). std `RwLock` reentrancy is also unspecified — never rely on read-lock recursion.
- **ARM vs x86 memory model**: x86 is TSO (strong); ARM/AArch64 is weakly ordered. A `Relaxed` bug (D04) can be invisible on x86 CI and only break on ARM validators — relevant for multi-arch validator fleets.

---

## 4. Tooling

| Tool | What it finds | Scheduling model | Soundness | Invoke / golden signature |
|------|---------------|------------------|-----------|---------------------------|
| **Loom** (tokio-rs/loom) | Deadlocks, data races, ordering violations | Permutes interleavings under the **C11 memory model**, with state-reduction to avoid combinatorial blow-up | **Sound-ish but partial**: treats `SeqCst` as `AcqRel` (false positives), under-explores load-buffering (some misses) | `cargo test` with `--cfg loom`; panic / stuck-schedule report |
| **AWS Shuttle** (awslabs/shuttle) | Most non-adversarial concurrency bugs in larger async systems (deadlocks, races, cancellation) | **Randomized** thread scheduling, deterministically replayable | **Not sound** (passing test ≠ correct); scales far past Loom — explicit soundness↔scalability trade-off | `#[shuttle::test]` / `shuttle::check_random`; deterministic failing seed |
| **Miri** (`-Zmiri-detect-data-races`) | Data races on `UnsafeCell`/raw ptrs, double-free, UB under the tested interleaving | Executes the one interleaving it runs | Detects UB it observes; does not explore all schedules | `cargo +nightly miri test`; `error: Undefined Behavior: Data race detected` |
| **Clippy `await_holding_lock`** | D07 obvious cases | static lint | lint-level | `cargo clippy`; lint hit |
| **Kani** | Bounded model-checking of concurrency invariants / refcount bounds | bounded | sound within bound | `#[kani::proof]`; counterexample |

> Loom = exhaustive-ish + sound-ish but small; Shuttle = randomized + unsound but large. They are complementary, **not interchangeable** — do not equate them. AWS used Shuttle (randomized) on the **ShardStore S3 storage backend** to prevent 16 issues from reaching production; it is not an exhaustive checker and was not run on "S3/DynamoDB clients."

---

## 5. Discovery calibration

- **Lock-ordering deadlocks (D01)** are the highest-yield/most-mechanical class: a field-granular lock-order graph + Loom finds them without prior knowledge of the bug. Directed prompting ("build the lock-order graph, then Loom each cycle") should dominate free-form review.
- **Atomic ordering (D04)** has the weakest tooling: there is no scanner. Yield depends entirely on the per-atom data-guarding trace in §2-D04. Expect low recall from generic review; budget explicit per-`Relaxed`-atom analysis.
- **Teardown double-frees (D02/D03)** cluster in custom channels/queues/arenas with manual `Drop` or epoch GC. Three of the verified advisories are this shape — prioritize any custom lock-free/wait-free data structure.
- **Type-bound soundness (D06)** is found by reading trait bounds against the access pattern, not by running a tool — cheap and high-signal where a value is fanned out in parallel.

---

## 6. Gaps → angle changes

| Gap | Missing in current agent | Severity | Proposal | Anti-bloat: existing coverage? |
|-----|--------------------------|----------|----------|-------------------------------|
| **G-01** | No field-granular lock-order graph + Loom cycle procedure (Parity #9952 needs field identity) | HIGH (chain stall) | CHECK: enumerate acquisitions → field-level graph → Loom each cycle | Agent mentions deadlock; lacks the graph procedure |
| **G-02** | No teardown-path-symmetry check for channel/queue `Drop`/GC (D02/D03 — 3 verified advisories) | HIGH (double-free/UB) | CHECK: per-element, enumerate every freeing path; assert idempotent take + null/swap; Miri | Agent flags double-free; no procedure |
| **G-03** | D04 procedure is vague; no per-`Relaxed`-atom data-guarding trace (RUSTSEC-2022-0006) | HIGH (ARM-only failures) | CHECK: list every atomic+ordering → "what data does it gate" → publish/consume trace | Mentions Release/Acquire; no per-atom trace |
| **G-04** | D05 close-then-use ordering not traced (RUSTSEC-2021-0124) | MEDIUM (corruption) | CHECK: for each channel, test {close, send, recv} interleaving | Mentions close race; no trace |
| **G-05** | D06 Send-vs-Sync-on-parallel-op not covered (RUSTSEC-2025-0023) | MEDIUM (unsoundness) | CHECK: parallel same-value access ⇒ require `Sync`; construct witness type | Not covered |
| **G-06** | D07 `std::sync::Mutex`-across-`.await` unsoundness (vs DoS-only) | MEDIUM | CHECK: clippy lint + std-guard-in-async audit | Partial (DoS angle only) |
| **G-07** | D11 reentrant read-lock deadlock (parking_lot fair policy) | LOW–MED | CHECK: trace read-guard live ranges for same-lock recursion | Not covered |

---

## 7. Sources

> Access date for all: 2026-06-05. Each entry was fetched (WebFetch/WebSearch) and confirmed for **both** identifier and mechanism before inclusion.

**Verified advisories / CVEs (Rust):**
1. **RUSTSEC-2025-0024** — crossbeam-channel, "double free on Drop", affected 0.5.12–0.5.14 (patched ≥0.5.15). Race in `discard_all_messages`: two paths read `head.block`, one swaps → `Channel::drop` frees twice. https://rustsec.org/advisories/RUSTSEC-2025-0024.html
2. **RUSTSEC-2021-0093** — crossbeam-deque, "Data race in crossbeam-deque", affected <0.7.4 and 0.8.0 (patched ≥0.7.4 / ≥0.8.1). `Stealer::steal*` can pop a task twice (others skipped) → double-free / leak / logic bug. https://rustsec.org/advisories/RUSTSEC-2021-0093.html
3. **RUSTSEC-2018-0009** — crossbeam, "MsQueue and SegQueue suffer from double-free", affected <0.4.1. Popped element also dropped by epoch GC; fixed by wrapping in `ManuallyDrop`. https://github.com/rustsec/advisory-db/blob/main/crates/crossbeam/RUSTSEC-2018-0009.md
4. **RUSTSEC-2022-0006** — thread_local, "Data race in `Iter` and `IterMut`", affected <1.1.4. `Iter/IterMut::next` used weaker-than-required load ordering → data race. https://rustsec.org/advisories/RUSTSEC-2022-0006.html
5. **RUSTSEC-2021-0124 / CVE-2021-45710** — tokio, "Data race when sending and receiving after closing a `oneshot` channel", affected ≤1.13.0 ≥0.1.14 (patched ≥1.8.4/<1.9.0 and ≥1.13.1). `Sender::send` vs `Receiver::await`/`try_recv` after `Receiver::close` → shared-memory data race → memory corruption. https://rustsec.org/advisories/RUSTSEC-2021-0124.html
6. **RUSTSEC-2025-0023** — tokio, "Broadcast channel calls clone in parallel, but does not require `Sync`", affected <1.38.2 / 1.39.0–1.42.0 / 1.43.0 / 1.44.0–1.44.1. Parallel `clone` on receive bounded only `Send` → unsoundness for `Send`-not-`Sync` types. https://rustsec.org/advisories/RUSTSEC-2025-0023.html

**Verified production incident (Rust, DLT — anchor):**
7. **OpenEthereum/Parity Ethereum #9952** (fix PR **#9954**, shipped 2.2.2-beta) — lock-ordering deadlock between `best_ancient_block` and `best_block` `RwLock`s in `blockchain.rs` (`commit` vs `chain_info` circular wait); fix reorders acquisition, stops waiting forever on the sync lock, drops `sync_channel`. Issue: https://github.com/openethereum/parity-ethereum/issues/9952 — PR: https://github.com/openethereum/parity-ethereum/pull/9954

**Verified cross-language precedent (Go — methodology only, labelled):**
8. **go-ethereum #2650** — "fatal error: concurrent map read and map write" in `TxPool.GetTransaction` (tx_pool.go); unsynchronized shared-map access under load aborts the node. Go runtime race-abort, not a Rust advisory. https://github.com/ethereum/go-ethereum/issues/2650

**Verified tooling:**
9. **AWS Shuttle** (awslabs/shuttle) — **randomized** (not sound, not exhaustive) concurrency-testing library; used on the **ShardStore S3 storage backend** to prevent **16** issues from reaching production. https://github.com/awslabs/shuttle · ShardStore context: https://aws.amazon.com/blogs/storage/how-automated-reasoning-helps-us-innovate-at-s3-scale/
10. **Loom** (tokio-rs/loom) — permutes interleavings under the **C11 memory model** with state-reduction; catches data races and ordering violations; treats `SeqCst` as `AcqRel` and under-explores load-buffering. https://github.com/tokio-rs/loom

**Documented footgun (not an advisory, labelled):**
11. **parking_lot `RwLock`** — task-fair policy; recursive read-lock may deadlock when a writer is queued (D11). https://docs.rs/parking_lot/latest/parking_lot/type.RwLock.html

---

> **AI-provenance reminder**: This dossier was assembled by an AI agent from primary sources fetched on 2026-06-05. Every advisory id, CVE, version range, and mechanism above must be re-confirmed against the cited URL before it is used as evidence in a submission — advisory text and affected-version ranges change, and a human must validate that the cited mechanism still matches the linked source. Generic-pattern classes (D07–D11 where labelled) carry **no** advisory id by design; do not attach one without a fresh fetched source. Treat this file as a lead-generator, not a citation of record.
