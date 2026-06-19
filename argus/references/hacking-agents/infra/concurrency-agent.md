# Concurrency & Atomics Agent (`infra` mode — Angle 4)

**Load also**: [`depth-methodology.md`](depth-methodology.md) — depth disciplines (attack-surface enum, pre-auth panic sweep, asymmetric-cost quantification, resource bounds, cross-domain deps, boundary checklist, §WRITE-THEN-VERIFY). Mandatory in Core + Thorough tiers; optional in Light.

**Research grounding**: [`concurrency-research.md`](../../research/concurrency-research.md) — 12-class bug taxonomy (D01–D12) anchored in production DLT incidents. Every CHECK below is traceable to a bug class in the dossier.

> **Calibration**: Concurrency bugs in DLT infrastructure split into three impact classes. **(1) Chain halt / validator deadlock** — a deadlock in consensus-critical code halts every validator that hits the same schedule; no blocks, no finality. This is the HIGHEST-IMPACT concurrency class. The anchor case is the Parity Ethereum `OnDemand` deadlock (2019): insertion thread held `Mutex<HashMap>` while waiting for a response that required the same lock → circular wait → every validator deadlocked. **(2) Data race → state corruption** — unsynchronized access to validator state; one thread writes while another reads; reader sees torn/inconsistent state → votes on wrong fork, signs wrong attestation, or computes wrong rewards. **(3) Lost wake-up → liveness failure** — a `Condvar` notification or channel signal is dropped; the waiting component never wakes; the subsystem stalls indefinitely.
>
> The modal bug is **lock-ordering deadlock** — two code paths acquire the same set of locks in different orders → cycle. Loom finds these mechanically. The second-most-common is **atomic ordering relaxation** — `Ordering::Relaxed` where `Acquire/Release` is needed; the code passes all tests under low contention on x86 but reads stale data on ARM (weak ordering). The deadliest is **`std::sync::Mutex` guard held across `.await` in multi-threaded tokio** — the guard IS `Send` so it compiles; the task migrates threads; the guard is dropped on the wrong thread → UB.
>
> Tool coverage is STRONG for deadlocks (Loom), MODERATE for data races (Miri, TSan), and WEAK for atomic ordering bugs — no production tool systematically detects under-synchronization. The LLM's advantage is systematic enumeration: every Relaxed atomic must be traced to the data it guards.

**Primary verification backends**: Loom for schedule exploration (deadlocks, races, lost wake-ups); Miri (`-Zmiri-detect-data-races`) for UB-class races; clippy `await_holding_lock` for async lock-hold; Kani for refcount overflow; Rudra for `Send`/`Sync` unsoundness. Vectors in **Group D** (`dlt-infra-attack-vectors.md`) are your catalogue.

---

## Phase 1: Pre-seed from tooling

Before manual analysis, seed with mechanical findings:

1. **Run clippy concurrency lints**:
   ```bash
   cargo clippy -- -W clippy::await_holding_lock \
                   -W clippy::mutex_atomic \
                   -W clippy::mutex_integer
   ```
   Every `await_holding_lock` warning is a seeded CHECK 6 candidate. `mutex_atomic` is style but flags potential contention hot-spots.

2. **Run `cargo rudra`** for `Send`/`Sync` soundness. Rudra finds `unsafe impl Send/Sync` violations that enable data races. Flag every `unsafe_send` or `panic_safety` warning.

3. **High-signal grep patterns** (deterministic to detect — LLM traces impact per context):
   ```bash
   # Every Relaxed atomic — manual CHECK 4 audit required
   rg 'Ordering::Relaxed' --type rust -l

   # Every UnsafeCell without explicit synchronization
   rg 'UnsafeCell' --type rust -l

   # Every Condvar usage — CHECK 2 audit
   rg 'Condvar' --type rust -l

   # Every tokio::select! — CHECK 8 audit
   rg 'select!' --type rust -l

   # Every std::sync::Mutex in async context — CHECK 6 UB candidate
   rg 'std::sync::Mutex' --type rust -l

   # Every block_in_place / spawn_blocking — CHECK 9 candidate
   rg 'block_in_place|spawn_blocking' --type rust -l

   # Custom Drop / steal on lock-free structures — CHECK 12 teardown audit
   rg 'impl.*Drop|Stealer|steal_batch|ManuallyDrop|defer' --type rust -l
   ```

---

## Phase 2: Concurrency surface inventory

Enumerate the concurrency surface:

- **Lock inventory**: every `Mutex`, `RwLock`, `tokio::sync::Mutex`, `tokio::sync::RwLock` in the codebase. For each: what does it guard? Which threads/tasks access it? Build a lock-acquisition graph: **node = lock identity at FIELD granularity, not type** — Parity #9952's cycle was between two `RwLock` fields (`best_ancient_block`, `best_block`) of the SAME struct; a type-only graph misses it. Directed edge A→B = "lock A is acquired while lock B is held." Any cycle → deadlock candidate (CHECK 1).
- **Atomic inventory**: every `AtomicBool`, `AtomicUsize`, `AtomicU64`, `AtomicPtr`. For each: what data does it guard? Is it a flag (signals "data ready"), a counter, or a pointer? What ordering does the store and load use? Every `Relaxed` flags a CHECK 4 candidate.
- **Condvar inventory**: every `Condvar`. For each: what condition does it signal? Is `wait()` in a `while` loop? Is `notify_one()` sufficient or should it be `notify_all()`?
- **Channel inventory**: every `mpsc`, `oneshot`, `broadcast`, `watch` channel. For each receiver: what's the exit condition? Does it handle disconnect/close?
- **select! inventory**: every `tokio::select!` site. For each branch: what resources are held? Is the branch cancellation-safe?
- **Thread/task spawn inventory**: every `thread::spawn`, `tokio::spawn`, `rayon::spawn`. For each: what shared state does the spawned task access?
- **Teardown inventory**: every `Drop` impl and manual teardown (`discard_all_messages`, epoch-GC `defer`, `Stealer::steal*`) on lock-free / wait-free structures holding heap nodes (CHECK 12).
- **Reentrancy inventory**: every `RwLock::read()` whose live range spans a callee that may `read()` the same lock — fair-policy self-deadlock candidate (CHECK 15).

---

## Phase 3: Per-class checks

### CHECK 1 — Lock-ordering deadlock (D01)

**Signal**: ≥2 distinct locks acquired in different orders across ≥2 code paths.

**Procedure**:
1. Build the lock-acquisition graph from Phase 2's lock inventory.
2. Run cycle detection: every lock at FIELD granularity (`self.best_block`, `self.best_ancient_block` — not just `RwLock<T>`) is a node; every acquisition-while-held is a directed edge. Two fields of one struct CAN cycle (Parity #9952) — track field identity, not type.
3. For each cycle: confirm both paths can execute concurrently. If they share a common outermost lock that prevents interleaving → not a deadlock. If they can run in different threads/tasks without a common guard → CONFIRMED.
4. Write a Loom test:
   ```rust
   #[test]
   fn test_no_deadlock_cycle_<ID>() {
       loom::model(|| {
           let lock_a = Arc::new(loom::sync::Mutex::new(()));
           let lock_b = Arc::new(loom::sync::Mutex::new(()));
           let a1 = lock_a.clone(); let b1 = lock_b.clone();
           let a2 = lock_a.clone(); let b2 = lock_b.clone();
           loom::thread::spawn(move || { let _g1 = a1.lock().unwrap(); let _g2 = b1.lock().unwrap(); });
           loom::thread::spawn(move || { let _g1 = b2.lock().unwrap(); let _g2 = a2.lock().unwrap(); });
       });
   }
   ```
5. **Tokio variant**: if locks are `tokio::sync::Mutex`, write a Loom test using `loom::thread::spawn` with `block_on` — Loom works on async locks mapped to loom sync primitives.

**Golden signature**: Loom panics with deadlock detection or hangs (timeout).

**Severity**: Critical if in consensus path (chain halt); High if in p2p/RPC path (service degradation); Medium if in non-critical subsystem.

**Source**: OpenEthereum/Parity #9952 (field-level `best_ancient_block`↔`best_block` cycle, fix PR #9954) — see dossier §2-D01; Loom test suite [model-knowledge].

---

### CHECK 2 — Lost wake-up on Condvar (D02)

**Signal**: `Condvar::wait()` not guarded by `while`, or `notify_one()` where `notify_all()` is required.

**Procedure**:
1. For every `Condvar` from Phase 2: inspect the wait pattern.
2. **Predicate check**: `if !predicate { cv.wait(lock) }` → BUG. The fix is `while !predicate { cv.wait(lock) }`. Why: (a) spurious wake-up — the OS can wake the thread even without a notify; (b) stolen notification — another thread could consume the condition state between notify and this thread acquiring the lock; (c) lost notification — notify fired before wait was armed.
3. **notify_one vs notify_all**: count the waiters. If ≥2 threads wait on the same `Condvar` and each notification should wake ALL waiting threads (not just one), `notify_one()` → BUG. Only one thread wakes; others sleep forever.
4. Write a Loom test with 3 waiters + 1 notifier; assert all waiters make progress.

**Golden signature**: Loom hangs — one or more threads stuck in `wait()` after notification.

**Severity**: High if the stuck thread is consensus-critical (liveness failure); Medium otherwise.

**Source**: `std::sync::Condvar` documentation [model-knowledge]; Loom condvar test patterns [model-knowledge].

---

### CHECK 3 — Arc refcount overflow (D03)

**Signal**: `Arc::clone()` in a hot loop or unbounded task-spawn path.

**Procedure**:
1. For every `Arc::clone()` in a per-request/per-message/per-block path: estimate the maximum clone count per operation.
2. If the count is unbounded (driven by user input, network messages, task spawn flood) → candidate.
3. Kani harness: prove that strong_count never overflows within a bounded iteration count.
4. **Practicality assessment**: 2^64 clones is effectively impossible. The finding is Informational unless the Arc guards consensus-critical data where a premature free would lose finality.
5. **Alternative**: `Arc::strong_count()` can be observed; if a tight loop clone-spams, it can theoretically hit the limit on 128-bit systems (where usize is 32 bits — a practical concern for embedded/WASM validators, not x86-64).

**Golden signature**: Kani finds a counterexample at strong_count = u32::MAX. Informational in practice.

**Source**: Rust `std::sync::Arc` documentation [model-knowledge].

---

### CHECK 4 — Atomic ordering under-synchronization (D04)

**Signal**: `Ordering::Relaxed` on an `AtomicBool`/`AtomicUsize` that guards data visibility, OR `Release` store without matching `Acquire` load.

**Procedure**:
1. From Phase 2's atomic inventory, for every `Relaxed` store or load:
   a. Identify the non-atomic data this atomic GUARDS. "Is there data written before/after the atomic store that another thread reads after the atomic load?"
   b. If the atomic is a flag ("data ready", "initialization complete", "shutdown"): the writer needs `Release` and the reader needs `Acquire`. Relaxed on either side → no happens-before → reader can see flag=true but still-stale data.
   c. If the atomic is a counter (not guarding data): Relaxed MAY be acceptable (counters don't need happens-before for correctness). Verify there is no data dependency on the counter value.
2. **Fence audit**: `fence(Release)` + `Relaxed` store is equivalent to `Release` store — verify the fence is BEFORE the Relaxed store. `Relaxed` load + `fence(Acquire)` is equivalent to `Acquire` load — verify the fence is AFTER the Relaxed load.
3. **ARM vs x86 note**: x86 TSO makes every store a Release and every load an Acquire by default — Relaxed bugs are INVISIBLE on x86. On ARM (weak ordering), writes can be reordered arbitrarily. Any consensus-critical Relaxed atomic is a consensus-split risk between x86 and ARM validators. Flag as: "Consensus-critical Relaxed atomic — may diverge on ARM validators."

**Golden signature**: No mechanical tool. Manual trace from atomic store to guarded data to atomic load. Write a stress test with rapid concurrent access; run on ARM hardware or under QEMU ARM emulation.

**Severity**: High if in consensus-critical path (cross-platform divergence); Medium if single-platform deployment; Low if the guarded data is diagnostic-only.

**Source**: Mara Bos, Rust Atomics and Locks [model-knowledge]; C++ memory model preshing.com [model-knowledge]; Solana Labs AccountsDB findings [model-knowledge].

---

### CHECK 5 — Data race on UnsafeCell / unsynchronized access (D05)

**Signal**: `UnsafeCell` accessed from ≥2 threads without a synchronization guard, or `unsafe impl Sync` on a type containing `Cell<U>`.

**Procedure**:
1. From Phase 2's `UnsafeCell` inventory: for each cell, what synchronization mechanism (Mutex, RwLock, Atomic) guards access? If NONE → CONFIRMED candidate.
2. For `unsafe impl Sync for T`: check every field of T. Does any field lack interior synchronization (`Cell`, `RefCell`, `UnsafeCell`, raw pointer)? If yes AND the impl doesn't document external synchronization → unsound.
3. Write a Miri test:
   ```rust
   #[test]
   fn test_race_<ID>() {
       let shared = Arc::new(UnsafeCell::new(0u64));
       let s1 = shared.clone();
       let h1 = std::thread::spawn(move || unsafe { *s1.get() = 1 });
       let s2 = shared.clone();
       let h2 = std::thread::spawn(move || unsafe { *s2.get() = 2 });
       h1.join().unwrap(); h2.join().unwrap();
   }
   ```
   Run: `cargo miri test -- -Zmiri-detect-data-races test_race_<ID>`
4. **Loom variant** for consensus-critical code: Loom explores ALL interleavings, catching races Miri might miss with its single-schedule-per-run.

**Golden signature**: Miri: `error: Undefined Behavior: Data race detected`. Loom: panic with race diagnostic.

**Severity**: Critical if the raced data is consensus-critical; High if validator state; Medium otherwise.

**Source**: Miri race detector [model-knowledge]; Loom documentation [model-knowledge].

---

### CHECK 6 — Lock held across .await (D06)

**Signal**: `std::sync::MutexGuard` / `std::sync::RwLockReadGuard` / `std::sync::RwLockWriteGuard` alive across an `.await` point in multi-threaded async runtime.

**Procedure**:
1. **Clippy first pass**: `cargo clippy -- -W clippy::await_holding_lock`. Every hit → HARD BUG. Fix immediately. This catches `let guard = mutex.lock(); ... .await; drop(guard);`.
2. **Subtler patterns clippy misses**: guard stored in struct field that's alive during `.await`; guard obtained from function whose return value is then held across `.await`; implicit guard via `Mutex::lock().map(|g| ...)` closure that contains `.await`.
3. **The `std::sync::Mutex` + tokio footgun** (distinct from simple performance complaint):
   - `std::sync::MutexGuard<T>` implements `Send` (by design — it's a pointer to the mutex, not a thread-bound token).
   - Multi-threaded tokio can migrate tasks between worker threads at `.await` points.
   - If a task holds a `std::sync::MutexGuard` across `.await`, the guard travels with the task to a different thread.
   - The guard is `Drop`'d on the new thread — which calls `Mutex::unlock()` from a thread that DIDN'T acquire the lock → UB (the unlock call itself is a data race on the mutex internals).
   - **Fix**: `tokio::sync::Mutex` — its guard is NOT `Send` by design, so the task can't be migrated. Use `tokio::sync::Mutex` for locks that must be held across `.await`; `std::sync::Mutex` for locks NOT held across `.await`.
4. **Sub-pattern in single-threaded runtimes**: if `#[tokio::main(flavor = "current_thread")]` is used, holding a lock across `.await` blocks the ENTIRE runtime (no other tasks can run). This is a DoS, not UB, but still a finding.

**Golden signature**: clippy `await_holding_lock` for obvious cases; manual audit for struct-field-guard and function-return-guard patterns.

**Severity**: Critical for `std::sync::Mutex` + multi-threaded tokio (UB, unsound). Medium for single-threaded block (DoS only). Low for `tokio::sync::Mutex` across `.await` (intentional, not a bug).

**Source**: Tokio documentation [model-knowledge]; Rust async book [model-knowledge].

---

### CHECK 7 — MPSC channel hang on sender drop (D07)

**Signal**: `Receiver::recv()` in a loop that doesn't handle channel closure as a terminal exit condition.

**Procedure**:
1. For every `Receiver` in a loop (Phase 2 channel inventory):
   a. **tokio::sync::mpsc**: `recv()` returns `None` when all senders drop AND buffer drains. Verify the loop treats `None` as terminal, not transient. Anti-pattern: `while let Some(msg) = rx.recv().await { ... }` — this handles `None` correctly (exits). Bug pattern: `loop { let msg = rx.recv().await.unwrap(); ... }` — panics on `None`.
   b. **std::sync::mpsc**: `recv()` returns `Err(RecvError)` on disconnect. Same logic — verify the error path exits, doesn't log-and-spin.
   c. **tokio::sync::broadcast**: `recv()` returns `Err(Lagged/Closed)`. Lagged is recoverable (skip messages); Closed is terminal. Verify both are handled.
2. **Timeout-based polling pattern**: `recv_timeout(Duration)` in a `loop` — does the loop exit when `Err(RecvTimeoutError::Disconnected)` is returned? If it continues → spin loop consuming 100% CPU after channel close.
3. Write a test: spawn tasks, drop all senders, assert the receiver exits within a timeout.

**Golden signature**: receiver task hangs after sender drop — observable as a CPU-spin or a never-returning task.

**Severity**: Medium — liveness failure in a subsystem; process continues but that component is dead.

**Source**: tokio mpsc documentation [model-knowledge]; Substrate gossip stream handling [model-knowledge].

---

### CHECK 8 — select! cancellation unsafety (D08)

**Signal**: `tokio::select!` where a branch performs multi-step state mutations and doesn't handle cancellation (the branch being DROP'd when another wins).

**Procedure**:
1. From Phase 2's `select!` inventory: for each branch, classify whether the branch is *cancellation-safe*:
   - Channel send/recv: SAFE — dropping an in-flight `send`/`recv` is correct.
   - Mutex acquisition + state write: UNSAFE if the branch acquires the mutex, writes partial state, and gets cancelled before finishing the remaining writes. The mutex is released (Drop on guard), but the state is now half-written.
   - I/O read/write: PARTIAL — dropping a `read` future may lose buffered data; dropping a `write` future leaves the stream in an undefined position.
   - Oneshot channel: SAFE — dropping the sender notifies the receiver.
2. For each UNSAFE branch: what partial state can be left behind? Cross-reference with Logic/State Machine L1 (partial-state write on error) — the concurrency angle identifies the `select!` mechanism; the logic angle traces the state corruption impact.
3. **Cancellation-safe wrapper pattern**: use `tokio_util::sync::CancellationToken` or wrap multi-step operations in a transaction that rolls back on Drop.

**Golden signature**: Manual trace — no off-the-shelf tool for async cancellation safety. The test: `tokio::select!` with a guaranteed-to-win branch (e.g., `sleep(Duration::ZERO)`) that kills the other branch mid-operation; assert state consistency.

**Severity**: High if the partial state causes invariant corruption; Medium if only diagnostic state affected.

**Source**: Tokio select! documentation [model-knowledge]; Rust async cancellation patterns [model-knowledge].

---

### CHECK 9 — Thread-pool exhaustion deadlock (D09)

**Signal**: `block_in_place`, `spawn_blocking`, or `rayon::scope()` inside a worker thread that waits on work scheduled to the same pool.

**Procedure**:
1. Find every `tokio::task::block_in_place` and `tokio::task::spawn_blocking` call.
2. For each: is it inside a tokio worker thread (not a dedicated blocking thread)? If the call is in `#[tokio::main]` or `tokio::spawn` → yes, it's a worker thread.
3. Check: does the blocking work wait (directly or transitively) for work queued to the SAME tokio runtime? Classic case: `block_in_place(|| { let rt = Handle::current(); rt.block_on(async { ... }); })` — this blocks the worker thread waiting for async work that needs a worker thread → deadlock if all workers do this.
4. **Rayon + tokio nesting**: `block_in_place(|| { rayon::scope(|s| { ... }); })` — the Rayon scope uses all worker threads; if ALL tokio workers are inside Rayon scopes, the tokio runtime cannot make progress.
5. **spawn_blocking exhaustion**: if `max_blocking_threads` (default 512) is exhausted and new `spawn_blocking` tasks queue, and existing blocking tasks are waiting on async work → circular wait.

**Golden signature**: stress test with `N = worker threads` tasks each doing the suspicious nested-block pattern; observe hang.

**Severity**: Medium — hard to trigger deterministically; requires specific load conditions. High only if a single attacker-controlled request path can trigger it.

**Source**: Tokio runtime documentation [model-knowledge]; Rayon FAQ [model-knowledge].

---

### CHECK 10 — Double-checked locking / lazy-init ordering (D10)

**Signal**: `Ordering::Relaxed` on an `AtomicBool` used as an initialization guard, OR manual `OnceLock`/`OnceCell` reimplementation.

**Procedure**:
1. Grep for `AtomicBool` + `Ordering::Relaxed` in the same function as a compute-and-store pattern.
2. Check: does the code check a flag, compute a value, then set the flag? If both flag store AND load are Relaxed → BUG (no happens-before for the computed data).
3. The correct pattern is `Release` on the store, `Acquire` on the load. Better: use `OnceLock<T>` which is correct by construction.
4. **Code smell**: manual lazy-init with atomics. Recommendation: replace with `std::sync::OnceLock` (stabilized in Rust 1.70).

**Golden signature**: `grep 'Ordering::Relaxed'` at lazy-init sites. Kani can verify the happens-before edge for specific patterns.

**Severity**: Medium — data race on initialized data; once initialization completes, subsequent reads are safe. Low if `OnceLock` is available as a drop-in fix.

**Source**: Rust atomics documentation [model-knowledge]; Mara Bos, Rust Atomics and Locks [model-knowledge].

---

### CHECK 11 — Weak-memory-model consensus divergence (D12)

**Signal**: `Ordering::Relaxed` on atomics read in consensus-critical paths (block finalization, fork choice, attestation voting), especially on codebases deployed on both x86 and ARM.

**Procedure**:
1. From Phase 2's atomic inventory: filter to atomics in consensus-critical paths (block processing, vote counting, fork choice, validator set rotation, attestation aggregation).
2. For each Relaxed store or load in these paths: trace what happens if the store/load is seen in different orders by different validator threads.
3. **Specific risk**: consensus requires ALL validators to reach the SAME decision on the same inputs. A Relaxed atomic that affects a decision boundary (e.g., "is this block finalized?") and reorders differently on ARM vs x86 → consensus split between ARM and x86 validator populations.
4. **Assessment**: if the codebase is deployed on both architectures AND the Relaxed atomic is on the path to a boolean consensus decision → HIGH. If single-architecture deployment → Low (x86 TSO is strong enough that most Relaxed bugs are latent).

**Golden signature**: Run the same consensus workload on ARM and x86 validators; compare decisions. Divergence = confirmed.

**Severity**: High if multi-architecture deployment AND consensus-critical. Low if single-architecture. Informational if the atomic guards non-consensus data.

**Source**: Mara Bos, Rust Atomics and Locks [model-knowledge]; C++ memory model [model-knowledge].

---

### CHECK 12 — Teardown-path-symmetry double-free (D02 / D03)

**Signal**: a `Drop` impl or manual teardown (`discard_all_messages`, epoch-GC `defer`, `steal`/`pop`) on a type holding raw pointers / `Box` / heap nodes (channels, queues, arenas, work-stealing deques).

**Procedure**:
1. Find every `Drop` impl and manual teardown on lock-free / wait-free structures holding heap nodes.
2. For each element, enumerate EVERY path that can free or take it. The defect shape: one path reads a node (`head.block`) but does not null/swap it, so a second path AND the destructor both free it.
3. Assert the take is idempotent: once an element is claimed, the slot is nulled/swapped on EVERY path before another consumer or the destructor runs.
4. **Epoch-GC variant**: a popped element wrapped so the collector does not also drop it (`ManuallyDrop`) — verify the pop path removes it from GC's reach.
5. **Steal variant**: assert "each enqueued item is dequeued exactly once across all consumers" — no double-pop, no skip.
6. Loom/Shuttle a producer + consumer + drop interleaving; run under Miri to catch the second free.

**Golden signature**: Miri `error: Undefined Behavior: double free` under the interleaving; Loom-driven Drop schedule with a doubly-freed node.

**Severity**: Critical if the freed node is consensus/validator state; High otherwise (UB, exploitable).

**Source**: RUSTSEC-2025-0024 (crossbeam-channel `discard_all_messages`), RUSTSEC-2021-0093 (crossbeam-deque steal), RUSTSEC-2018-0009 (crossbeam epoch-GC) — see dossier §2-D02/D03.

---

### CHECK 13 — Data race after channel close / use-after-close (D05)

**Signal**: a channel/oneshot whose `close()` (or receiver-drop) can run concurrently with a `send`/`recv`/`await`/`try_recv` on the other half. Distinct from CHECK 7 (hang on drop) — this is a data race on shared memory, not a liveness stall.

**Procedure**:
1. For each channel type, list operations on each half and which can run concurrently across threads.
2. Test the close-then-use ordering specifically: receiver calls `close`, then sender `send`s while the receiver `await`s/`try_recv`s — do both halves then touch the same memory?
3. Loom/Shuttle the {close, send, recv} interleaving; run under Miri for the UB.
4. **Dependency case**: if the channel is a third-party crate, pin past the patched version rather than re-deriving the race.

**Golden signature**: Miri data-race / memory-corruption diagnostic under the close-then-use schedule.

**Severity**: High — shared-memory corruption; Critical if the corrupted memory is consensus/validator state.

**Source**: RUSTSEC-2021-0124 / CVE-2021-45710 (tokio oneshot) — see dossier §2-D05.

---

### CHECK 14 — Send-without-Sync on a parallel operation (D06)

**Signal**: an API that `clone`s or reads a stored value IN PARALLEL across receivers/threads but bounds only `T: Send`, not `T: Sync` (broadcast channels, shared caches, parallel iterators that clone).

**Procedure**:
1. Find structures that fan one value out to multiple consumers concurrently.
2. Ask: does the consumer-side touch (clone/read) of the SAME value happen on multiple threads simultaneously? If yes, the bound must be `Sync`, not merely `Send`.
3. The defect shape: parallel `clone` on receive bounded only `T: Send` → a `Send`-but-not-`Sync` type with thread-local invariants is cloned concurrently → unsound.
4. Proof is a type-bound mismatch + a witness `Send`-not-`Sync` type whose `Clone` relies on `!Sync` invariants and compiles under the API. For dependency use: pin past the patched version.

**Golden signature**: no runtime tool — the witness type compiling against the API is the proof.

**Severity**: Medium — unsoundness; the bug requires a `Send`-not-`Sync` value to be supplied.

**Source**: RUSTSEC-2025-0023 (tokio broadcast) — see dossier §2-D06. Coordinate with Angle 2 (owns the `unsafe impl` declaration; this CHECK owns the parallel-access-vs-bound mismatch).

---

### CHECK 15 — Reentrant read-lock deadlock on fair RwLock (D11)

**Signal**: a thread acquires a `read()` guard, then (directly or via a callee) acquires `read()` on the SAME `RwLock` while still holding the first.

**Procedure**:
1. Trace each `read()` guard's live range; flag any re-entrant `read()` on the same lock within that range.
2. If a writer can be queued between the two reads, a task-fair `RwLock` (parking_lot) blocks the second reader behind the queued writer → self-deadlock.
3. std `RwLock` read-recursion is also unspecified — never rely on it. Fix: take the lock once, or re-architect to a non-reentrant design.

**Golden signature**: thread stuck on the second `read()` with a writer queued — reproducible with a 1-reader-holding-2-reads + 1-queued-writer test.

**Severity**: High if the stuck thread is consensus-critical (liveness); Low–Medium otherwise.

**Source**: parking_lot `RwLock` task-fair docs (documented footgun) — see dossier §2-D11.

---

## Stage-3 PoC discipline

Approved per-class backends:

| Class | Backend | Command |
|-------|---------|---------|
| D01 (deadlock) | Loom | `cargo test --features loom test_deadlock_<ID>` |
| D02 (lost wake-up) | Loom | `cargo test --features loom test_wakeup_<ID>` |
| D03 (Arc overflow) | Kani | `cargo kani --harness check_arc_overflow_<ID>` |
| D04 (ordering) | Manual trace + stress test on ARM | Runtime stress test |
| D05 (data race) | Miri or Loom | `cargo miri test -Zmiri-detect-data-races test_race_<ID>` |
| D06 (lock-across-await) | Clippy + manual | `cargo clippy -- -W await_holding_lock` |
| D07 (channel hang) | Unit test | `cargo test test_channel_close_<ID>` |
| D08 (select! cancel) | Unit test + manual trace | Manual trace benchmark |
| D09 (pool exhaustion) | Stress test | Integ test with N concurrent tasks |
| D10 (double-check lock) | Kani + manual | Kani harness for happens-before |
| weak-memory (CHECK 11) | Cross-arch stress test | ARM QEMU vs x86 native |
| D02/D03 (teardown double-free, CHECK 12) | Loom/Shuttle + Miri | `cargo miri test test_teardown_<ID>` (expect double-free) |
| D05 (close-then-use race, CHECK 13) | Loom/Shuttle + Miri | `cargo miri test test_close_use_<ID>` |
| D06 (send-without-sync, CHECK 14) | Witness type + compile | Witness `Send`-not-`Sync` type compiles against the API |
| D11 (reentrant read-lock, CHECK 15) | Unit test | `cargo test test_reentrant_read_<ID>` (writer queued) |

**Tier-1-live-e2e** (mandatory for CONFIRMED): the Loom, Miri, Kani, or cross-arch result matching the Golden Signature. Without it: max CONTESTED per shared-rules.md.

## Output fields beyond shared FINDING schema

```yaml
shared_state_location: <file:line of the shared variable>
threads_involved: [thread1, thread2, ...]  # or async task names
synchronization_primitive: Mutex | RwLock | Condvar | Atomic | UnsafeCell | Channel | select!
violation_class: deadlock | data-race | lost-wakeup | atomic-ordering | refcount-overflow | lock-across-await | channel-hang | select-cancellation | pool-exhaustion | double-check-lock | weak-memory | teardown-double-free | close-then-use-race | send-without-sync | reentrant-read-deadlock
verification_backend: Loom | Miri | Kani | Clippy | Manual | Stress
verification_harness: <inline code or test name>
golden_signature: <matched Group D signature or tool-specific output substring>
cross_arch_risk: <true | false — true if this bug is invisible on x86 but active on ARM>
```

## Anti-patterns (do NOT report)

- `Mutex` contention as a performance concern (not a security finding unless it's the mechanism for DoS).
- `Send`/`Sync` impl analysis — Angle 2's domain (cross-reference, don't duplicate).
- Lock-ordering "bad practice" without a reachable concurrent execution path (single-threaded context, common outermost lock). The cycle must be demonstrated concurrent for CONFIRMED.
- Relaxed on pure counters with no data dependency — Relaxed is correct for `fetch_add` on a stats counter where the value isn't used for decisions.
- `tokio::sync::Mutex` held across `.await` — this is intentional design; the non-Send guard prevents thread migration. It's a perf concern, not a bug.

## Coordination with other angles

- **Unsafe Trait Soundness (Angle 2)** owns the `unsafe impl Send/Sync` declaration. Angle 4 owns the runtime evidence (Loom failing schedule, Miri race) that the impl is wrong.
- **Memory Safety (Angle 1)** owns the UB the race produces (Miri trace under Tree Borrows). Angle 4 owns the schedule that triggers it (Loom).
- **Logic & State Machine (Angle 7)** owns the state corruption from CHECK 8 (select! + partial-state). Cross-reference: Angle 7's L1 (partial-state write on error) is the IMPACT; Angle 4's CHECK 8 is the MECHANISM.
- **Resource Exhaustion (Angle 6)** owns `block_in_place` DoS (F04). Angle 4's CHECK 6 covers the UB variant; Angle 6 covers the resource-exhaustion variant.
