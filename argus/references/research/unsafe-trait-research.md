# Unsafe Trait Soundness — Research Dossier

> **Feeds**: `hacking-agents/infra/unsafe-trait-agent.md`
> **Last research pass**: 2026-06-05 · **Sources reviewed**: 11 primary (9 RUSTSEC advisories with confirmed CVE aliases, 1 Rudra paper/secondary, 1 std-lib soundness thread)
> **Status**: drafted-verified — evidence layer rebuilt from primary sources (rustsec.org + Rudra OSDI 2021). Methodology/CHECK structure retained from prior draft; every advisory id below was fetched and confirmed for BOTH identifier AND mechanism on 2026-06-05.

> **Anchor case**: **RUSTSEC-2020-0101 / CVE-2020-36208 — conquer-once `OnceCell`.** The crate provided `unsafe impl Sync for OnceCell<T>` without a `T: Send` bound. A `Sync`-but-`!Send` type — the canonical example is `std::sync::MutexGuard` — could then be moved across threads via the shared `OnceCell`, which is undefined behavior. The fix: add the `Send` constraint. This is the defining shape of the unsafe-trait class — an `unsafe impl Send/Sync` whose generic bounds are weaker than the wrapped data's actual thread-safety contract, so the impl asserts a guarantee the contents do not satisfy. Source: https://rustsec.org/advisories/RUSTSEC-2020-0101.html (fetched 2026-06-05).

> **Provenance note for the prior anchor**: The earlier draft anchored on crossbeam `AtomicCell` and described it as "an `unsafe impl Sync` violation via spinlock TOCTOU." That is wrong. The real crossbeam advisory (RUSTSEC-2022-0041 / CVE-2022-23639) is an **alignment** bug: affected versions assumed `align_of::<u64>() == align_of::<AtomicU64>()`, which is false on some 32-bit targets, producing unaligned atomic access and a resulting data race. It is retained below only as a correctly-described anti-pattern, never as a Sync/spinlock example.

---

## 0. Calibration headline

Unsafe trait bugs are narrower than general memory safety but just as dangerous: an unsound `Send`/`Sync` impl silently enables data races in code that never wrote the word `unsafe`. The bug is invisible to the borrow checker — `unsafe impl Sync for T` tells the compiler "trust me, this is thread-safe," and the compiler obliges. Every subsequent safe-code `&T` shared across threads becomes a latent data race.

The empirical center of gravity is the **generic Send/Sync variance bug**: a wrapper type `W<T>` implements `Send`/`Sync` unconditionally (or with bounds weaker than `T` requires), so a caller can instantiate `W<Rc<_>>`, `W<Cell<_>>`, or `W<MutexGuard<_>>` and cross a thread boundary that the inner type forbids. This is not a theoretical class. The Rudra static analyzer (Bae et al., OSDI 2021) scanned all ~43,000 crates.io packages in 6.5 hours, found **264 new memory-safety bugs in 145 packages**, and those became **112 RustSec advisories and 76 CVEs**. Rudra's three detection patterns map almost exactly onto this angle: (1) **panic safety**, (2) **higher-order safety invariants**, (3) **propagating Send/Sync in generic types** (source: https://www.infoq.com/news/2021/11/rudra-rust-safety/). The 2020 RustSec advisory wave (beef, aovec, im, concread, reffers, conquer-once, lever, scottqueue, rcu_cell, tiny_future, …) is the Send/Sync-variance pattern landing in production crates.

Two failure shapes dominate the verified evidence:

1. **Send/Sync variance** — the wrapper's `Send`/`Sync` bound is weaker than the wrapped data demands. Six confirmed advisories below. The fix is always the same shape: add the missing `T: Send`/`T: Sync` bound.
2. **Panic safety in `unsafe` ownership code** — a user-controlled callback (`Default`, `Clone`, or `Drop`) panics mid-operation while the container's length/initialization bookkeeping is in a transient state, so unwinding double-drops or drops uninitialized memory. Two confirmed advisories below (arenavec, stack_dst). This is the operational reality behind the "unsafe Drop / unwind safety" sub-classes.

Rudra (`cargo rudra`) is the dedicated pre-seed tool for patterns (1) and (2). Its false positives (it flags `UnsafeCell` behind a real `Mutex`) and false negatives (it cannot reason about complex hand-rolled invariants) are where the model adds value: reading the `// SAFETY:` prose contract and checking it against the actual generic bounds and panic-unwind paths.

---

## 1. Bug-class taxonomy

| Class | One-line mechanism | Real instance (verified source) | Argus coverage |
|-------|--------------------|---------------------------------|----------------|
| **B01 Unsound Send impl (weak bound)** | `unsafe impl Send for W<T>` lacks the `T: Send` (and often `T: Sync`) bound the contents require | aovec `Aovec<T>` — unconditional Send/Sync, lets `Rc`/`Cell` cross threads — **RUSTSEC-2020-0099 / CVE-2020-36207**; concread `ARCache<K,V>` missing `V: Send+Sync` — **RUSTSEC-2020-0092 / CVE-2020-35928** | **YES** — Rudra `send_sync_variance` + field/bound audit |
| **B02 Unsound Sync impl (weak/missing bound)** | `unsafe impl Sync for W<T>` lacks the `T: Send`/`T: Sync` bound; `Sync`-but-`!Send` or `Send`-but-`!Sync` contents escape their thread | conquer-once `OnceCell<T>` Sync w/o `Send` → `MutexGuard` crosses threads — **RUSTSEC-2020-0101 / CVE-2020-36208**; beef `Cow` Send w/o `T: Sync` → `Cell`/`RefCell` data race — **RUSTSEC-2020-0122 / CVE-2020-36442**; im `TreeFocus` unconditional Send/Sync — **RUSTSEC-2020-0096 / CVE-2020-36204**; reffers `ARefss` unconditional via `.map()` — **RUSTSEC-2020-0094 / CVE-2020-36203** | **YES** — Rudra + bound audit |
| **B03 Panic-safety: drop-uninitialized on unwind** | A user callback (`Default`/`Clone`) panics while `unsafe` code has already extended a length or reserved a slot but not yet initialized it; unwinding drops uninitialized memory | arenavec — panic in `T::default()` drops uninitialized `T` — **RUSTSEC-2021-0040 / CVE-2021-29930**; stack_dst — `push_inner` bumps length then `val.clone()` panics → drops uninitialized memory — **RUSTSEC-2021-0033 / CVE-2021-28034** | **PARTIAL** — needs systematic unwind-path procedure |
| **B04 Panic-safety: double-drop on unwind** | A user `Drop` (or `Clone`) panics mid-resize/move, so the same element is dropped twice during unwinding | arenavec — panic in `T::drop()` double-drops during `resize`/`resize_with` — **RUSTSEC-2021-0040 / CVE-2021-29931**; stack_dst double-drop variant — **RUSTSEC-2021-0033 / CVE-2021-28035** | **PARTIAL** — needs systematic detection |
| **B05 Init-panic → later-UB (`unreachable_unchecked`)** | An initialization closure panics; the type records "initialized" state incorrectly, so a later access hits `unreachable_unchecked` / reads uninit | once_cell `Lazy` — panic in first deref of `Lazy` makes subsequent derefs hit `std::hint::unreachable_unchecked` — **RUSTSEC-2019-0017 / CVE-2019-16141** | **NO** — not covered |
| **B06 Unsound `TrustedLen`/`ExactSizeIterator`** | `size_hint()`/`len()` over-reports; `unsafe` consumers pre-allocate or `set_len` on the lie → uninit read / OOB | `[generic pattern — no specific incident]` — demonstrated only as an internal std soundness discussion (rust-lang/rust #89948, `SpecExtend`+`MaybeTrusted`), no CVE/advisory | **PARTIAL** — Kani harness, no production instance |
| **B07 Custom allocator contract violation** | `GlobalAlloc`/`Allocator` returns under-aligned, null, wrong-size, or mismatched-`Layout` pointer | `[generic pattern — no specific incident]` — alignment-assumption class is real (cf. crossbeam-utils alignment bug, RUSTSEC-2022-0041 / CVE-2022-23639, *not itself an allocator*); no verified custom-allocator advisory found this pass | **PARTIAL** — Kani/Miri contract proof, no production instance |
| **B08 Unsafe `Deref`/`Borrow`/`AsRef` lifetime** | `deref()` hands out a reference that outlives the data it points to, or transmutes a lifetime | `[generic pattern — no specific incident]` — no verified RUSTSEC instance found this pass | **PARTIAL** — Miri drop-while-borrowed test, no production instance |

> **Anti-pattern reference (do not cite as a Sync bug)**: crossbeam-utils `AtomicCell` — **RUSTSEC-2022-0041 / CVE-2022-23639** — is an **alignment** unsoundness: "incorrectly assumed that the alignment of {i,u}64 was always the same as Atomic{I,U}64," which is false on some 32-bit targets, causing unaligned atomic access and a data race. It is included only to anchor B07's alignment-assumption methodology, never as a `Send`/`Sync`-impl example. Source: https://rustsec.org/advisories/RUSTSEC-2022-0041.html.

---

## 2. Per-class methodology

### B01 / B02 — Unsound Send/Sync impl (generic variance)

**Signal**: `unsafe impl Send for W<T>` or `unsafe impl Sync for W<T>` on a generic wrapper, where the `where` clause is absent or weaker than the inner data's thread-safety contract. Highest-signal wrappers: anything containing `UnsafeCell<T>`, `*mut T`, `*const T`, `T` behind a hand-rolled lock/arena/cache, or a `T` reachable through a `map`/`get`/`into_inner` API.

**Procedure** (this is the variance check, runnable without knowing the answer):
1. Enumerate every `unsafe impl Send`/`unsafe impl Sync` in scope.
2. For each, write the *implied contract*: `Sync for W<T>` is sound only if every way to obtain shared/owned access to `T` through `&W<T>`/`W<T>` from another thread is itself sound for that `T`. Then check the `where` clause against it:
   - `Send for W<T>` that exposes shared `&T` across threads needs **`T: Sync`** (beef CVE-2020-36442 — missing `T: Sync` let `Cell`/`RefCell` race).
   - `Sync for W<T>` that lets `T` be *moved out* on another thread needs **`T: Send`** (conquer-once CVE-2020-36208 — missing `Send` let `MutexGuard` move).
   - A type with two generics needs the bound on **every** parameter the contents expose (concread CVE-2020-35928 — `V` bound was missing).
3. Hunt the "unconditional impl" smell: `unsafe impl<T> Send for W<T> {}` with *no* `where` clause is the modal bug (aovec CVE-2020-36207, im CVE-2020-36204, reffers CVE-2020-36203). Treat a missing `where` on a generic `Send`/`Sync` as guilty-until-proven-innocent.
4. Check escape hatches that re-introduce `T`: a `.map()`, `.get_mut()`, `Deref`, or iterator that returns `&T`/`T` defeats a bound placed only on construction (reffers — unsoundness was through `ARefss::map()`, not the constructor).
5. Read the `// SAFETY:` comment. If it claims "only used on one thread" or "atomic ops synchronize," trace **every** public method that touches the inner data and confirm the claim holds for all of them — not just the happy path.

**Mechanical evidence**: Rudra `send_sync_variance` warning, then a Loom or thread-based PoC that instantiates the wrapper with the forbidden inner type (`Rc`, `Cell`, `MutexGuard`) and exhibits the race/move under `cargo +nightly miri test` or a stress loop. The fix-shape is the proof: if adding `T: Send`/`T: Sync` makes the offending instantiation fail to compile, the impl was unsound.

**Anti-pattern (false-positive guard)**: A wrapper whose only inner access is through a real `std::sync::Mutex`/atomic with a correct bound is sound even though it contains `UnsafeCell` — Rudra flags it; the model should clear it by confirming the synchronization actually gates every access path. Bound that is present and correct = not a finding.

**Source**: RUSTSEC-2020-0099/0092/0101/0122/0096/0094 (all fetched 2026-06-05, CVE aliases confirmed); Rudra OSDI 2021 Send/Sync variance checker.

### B03 / B04 — Panic safety in `unsafe` ownership code (drop-uninit / double-drop)

**Signal**: `unsafe` code that (a) calls a *user-controlled* function — `T::default()`, `T::clone()`, `T::drop()`, a closure — while (b) the container's bookkeeping is in a transient invalid state: a length already incremented, a slot reserved with `ptr::write` pending, a value moved with `ptr::read` but the source not yet `forget`-ten, or `set_len` called before initialization. Hot spots: arena/`Vec`-like `resize`/`resize_with`/`push`/`extend`/`map` over raw memory.

**Procedure**:
1. Enumerate every block that combines a raw-memory operation (`ptr::write`, `ptr::read`, `set_len`, `MaybeUninit`, `alloc`) with a call into generic `T` code (`T::default`, `T::clone`, `Drop`, user closure).
2. For each, identify the **panic window**: between the moment bookkeeping says "this slot is live/owned" and the moment it is actually initialized/disowned. Ask: if the user function panics *here*, what does the destructor (or the rest of unwinding) do with this slot?
   - Length bumped *before* `clone()` → unwind drops an uninitialized/half-moved slot (stack_dst CVE-2021-28034: `push_inner` increments length, then `val.clone()` panics).
   - `default()`/`clone()` panics while constructing → uninitialized `T` is dropped (arenavec CVE-2021-29930).
   - A user `Drop` panics mid-`resize` → the same element is dropped again on unwind (arenavec CVE-2021-29931; stack_dst CVE-2021-28035).
3. Verify the order-of-operations fix is present: bookkeeping that marks a slot live must happen **after** the fallible user call, or a drop-guard / `ScopeGuard` must disarm only on success. Absence of either across a panic window = finding.

**Mechanical evidence**: a `#[should_panic]`-free test that installs a `T` whose `Default`/`Clone`/`Drop` panics on the Nth call, runs the operation inside `std::panic::catch_unwind`, and asserts no double-drop (drop counter) / no uninit read under Miri. Miri reliably catches both drop-of-uninit and double-free.

**Anti-pattern (false-positive guard)**: Code that uses `MaybeUninit` plus a drop-guard that only counts *initialized* elements, or that does all fallible work before touching length, is unwind-safe even though it looks scary. The presence of a correctly-scoped guard clears the window.

**Source**: RUSTSEC-2021-0040 (arenavec, CVE-2021-29930/29931), RUSTSEC-2021-0033 (stack_dst, CVE-2021-28034/28035), both fetched 2026-06-05; Rudra OSDI 2021 panic-safety pattern.

### B05 — Init-panic poisons a "trust-me" later access

**Signal**: A lazy/once cell, memoization wrapper, or cached-init type whose initialization closure is user-controlled, and whose *post-init* read path uses an "I know it's initialized" unchecked primitive (`unreachable_unchecked`, `assume_init`, `get_unchecked`, `Option::unwrap_unchecked`).

**Procedure**:
1. For each lazy/once/cached type, find the state transition: what marks the cell "initialized"?
2. Determine whether the init closure can panic, and whether that panic is observed *before or after* the cell is marked initialized.
3. If the cell can be left in a "looks-initialized-but-isn't" state after a panicking init, and any later read uses an unchecked primitive → UB (once_cell `Lazy`, CVE-2019-16141: panic in first deref → later derefs hit `std::hint::unreachable_unchecked`).
4. The sound pattern records *failure* (or re-runs init) on panic, or marks initialized only after the value is written. Confirm one of those exists.

**Mechanical evidence**: a test whose init closure panics once, caught with `catch_unwind`, followed by a second access; under Miri the unchecked path surfaces as UB.

**Source**: RUSTSEC-2019-0017 (once_cell, CVE-2019-16141), fetched 2026-06-05.

### B06 — Unsound `TrustedLen` / `ExactSizeIterator`  `[generic pattern — no specific incident]`

**Signal**: `unsafe impl TrustedLen for I` or `impl ExactSizeIterator for I` where `size_hint().0` / `len()` is derived from something that can diverge from the true remaining count (a cached field, a `Vec::len()` that mutates, a count excluding tombstones).

**Procedure**:
1. Enumerate every `unsafe impl TrustedLen` and `impl ExactSizeIterator`.
2. Identify what computes the reported length `n`; confirm `next()` cannot return `None` before yielding `n` items, and cannot yield *more* than `n`.
3. Trace `unsafe` consumers that trust the bound (`Vec::with_capacity` + `set_len`, `collect` specialization). The danger is only real when a consumer turns the claimed length into uninitialized capacity it then reads.
4. Kani: `#[kani::proof] fn trusted_len_honest() { let it = make(); let (lo, hi) = it.size_hint(); let n = it.count(); assert!(lo <= n && hi == Some(n)); }`

**Mechanical evidence**: Kani counterexample where `size_hint().0 > actual_count`.

**Status**: No production RUSTSEC/CVE instance found this pass. The only confirmed demonstration is an internal std-library discussion (rust-lang/rust #89948: a `Liar` iterator defeats `SpecExtend` via the `MaybeTrusted` wrapper, segfaulting on `collect`) — a soundness thread, **not** a published advisory. Keep this class methodology-only and do not attach an advisory id.

**Source**: https://github.com/rust-lang/rust/issues/89948 (internal discussion, no CVE), fetched 2026-06-05.

### B07 — Custom allocator / alignment contract  `[generic pattern — no specific incident]`

**Signal**: `#[global_allocator]`, `impl GlobalAlloc`, `impl Allocator`, or any hand-rolled code that *assumes* the alignment of a type equals the alignment of a related/atomic type.

**Procedure**:
1. For each allocator impl, verify the contract per `std::alloc`: `alloc(layout)` returns a pointer aligned to `layout.align()` and sized `>= layout.size()`; `dealloc(ptr, layout)` receives the **same** `Layout` used for `alloc`; `realloc` handles null-`ptr` and `new_size == 0`; zero-size `Layout` still yields a non-null, well-aligned pointer.
2. For alignment assumptions outside allocators: flag any `align_of::<A>() == align_of::<B>()` reasoning (explicit or implicit via `transmute`/`cast`/pointer arithmetic) across primitive↔atomic or 32-bit/64-bit boundaries. This is the exact class of the crossbeam-utils alignment bug.
3. Kani/Miri: prove returned alignment ≥ requested across the platform `Layout` space; Miri's strict-provenance + alignment checks catch under-alignment on access.

**Mechanical evidence**: Kani harness over `Layout` proving `ptr as usize % layout.align() == 0`; Miri access test on the returned pointer.

**Status**: No verified *custom-allocator* RUSTSEC instance found this pass. The alignment-assumption *mechanism* is confirmed real via crossbeam-utils **RUSTSEC-2022-0041 / CVE-2022-23639** (which is a `crossbeam` internal-alignment bug, not a `GlobalAlloc` impl). Cite that advisory only for the alignment mechanism, not as an allocator advisory.

**Source**: https://rustsec.org/advisories/RUSTSEC-2022-0041.html (alignment mechanism); `std::alloc::GlobalAlloc`/`Allocator` contract docs.

### B08 — Unsafe `Deref` / `Borrow` / `AsRef` lifetime  `[generic pattern — no specific incident]`

**Signal**: `Deref::deref`, `Borrow::borrow`, or `AsRef::as_ref` whose body uses `unsafe` to produce `&Target` from a raw pointer, transmuted lifetime, or cached reference.

**Procedure**:
1. For each impl, confirm the returned reference's lifetime is genuinely tied to `&self` and the pointed-to data is owned by (or outlives) `self`.
2. Flag any lifetime `transmute`/`mem::transmute::<&'a _, &'b _>` extending `'b` beyond the data's true lifetime.
3. Flag a `deref()` that returns a reference into data freed/replaced by another `&self`/`&mut self` method.

**Mechanical evidence**: Miri test that drops/replaces the container while a `deref`'d reference is live; UB surfaces as use-after-free.

**Status**: No verified RUSTSEC/CVE instance found this pass — methodology-only.

**Source**: `std::ops::Deref` / `Borrow` contract docs.

---

## 3. Framework-specific knowledge

- **The "unconditional `unsafe impl`" smell is the single highest-yield signal.** Every 2020-wave Send/Sync advisory above is a generic `unsafe impl<T> Send/Sync for W<T> {}` with no `where` clause, or with a clause missing one parameter. Grep target: `unsafe impl` … `Send`/`Sync` … `for` … `<` (generic) and inspect the `where`.
- **Direction matters.** `Send for W<T>` exposing shared `&T` needs `T: Sync` (beef). `Sync for W<T>` allowing `T` to move out needs `T: Send` (conquer-once). Getting the direction wrong is itself the bug; the audit must reason about *which* access the impl enables, not just "add a bound."
- **`Sync`-but-`!Send` types are the sneaky payload.** `MutexGuard<T>` is `Sync` yet `!Send` — it is the textbook trigger for a missing-`Send` bound (conquer-once). The reverse payloads are `Rc`/`Cell`/`RefCell` (`Send`-but-`!Sync` or neither) for missing-`Sync` bounds (aovec, beef).
- **Escape APIs defeat constructor-only bounds.** A bound enforced only at construction is moot if `map`/`get`/`Deref`/`IntoIterator` later hands the inner `T` back out (reffers `.map()`).
- **Panic-safety windows live in raw-memory containers.** arena/`SliceVec`/`stack_dst`-style types that manually manage length + `ptr::write`/`clone` are where drop-uninit and double-drop concentrate. The fix is always ordering (fallible call before bookkeeping) or a drop-guard.
- **`unreachable_unchecked`/`assume_init` after a fallible init is a poison primitive.** once_cell `Lazy` shows a panicking init can leave a "trust me" read path that is now UB.
- **Alignment is not portable.** `align_of::<u64>()` is *not* guaranteed equal to `align_of::<AtomicU64>()` on all targets (crossbeam-utils). Any code that assumes equal alignment across primitive↔atomic or width boundaries is suspect on 32-bit targets.

---

## 4. Tooling

| Tool | What it finds for this angle | Invoke | Golden signature |
|------|------------------------------|--------|------------------|
| **Rudra** (`cargo rudra`) | Send/Sync variance (B01/B02), panic-safety drop-uninit/double-drop (B03/B04) — the two algorithms behind 112 RustSec advisories | `cargo rudra` (nightly pin per Rudra README) | `send_sync_variance` / `unsafe_dataflow` warning on the impl/function |
| **Miri** | drop-of-uninitialized, double-free on unwind (B03/B04), Deref lifetime UB (B08), under-aligned access (B07) | `cargo +nightly miri test` | UB report: "constructing invalid value" / "deallocating already deallocated" / "accessing memory with insufficient alignment" |
| **Kani** | `TrustedLen`/`ExactSizeIterator` honesty (B06), allocator/alignment contract (B07) | `#[kani::proof]` harness | counterexample where `size_hint().0 > count` or `ptr % align != 0` |
| **Loom** | data race exposed by an unsound `Sync` impl (B01/B02) under exhaustive interleaving | `#[test]` under `loom::model` | assertion failure on a shared-state interleaving |
| **Clippy** | `missing_safety_doc` — every `unsafe impl`/`unsafe fn` must carry a `// SAFETY:` contract to audit | `cargo clippy` | lint hit pinpoints undocumented `unsafe impl` |

Pre-seed order: **Rudra first** (it directly targets B01–B04), then read every flagged `unsafe impl`'s `// SAFETY:` prose, then Miri/Loom/Kani to turn a suspected violation into a PoC.

---

## 5. Discovery calibration

- **Rudra-directed vs blind**: Rudra reduces the Send/Sync + panic-safety search to a flagged candidate list (the same algorithms produced 112 advisories on crates.io). The model's job is *adjudication*, not discovery: for each flag, confirm the missing/weak bound by constructing the forbidden instantiation, or clear it by confirming a correct lock/guard. Treat Rudra flags as high-precision-but-not-perfect; expect false positives on `UnsafeCell`-behind-`Mutex`.
- **Bound-direction reasoning is the failure mode for under-directed runs.** A model told only "check Send/Sync impls" tends to demand `T: Send + Sync` everywhere (over-fix) instead of reasoning about which access the impl enables. Direct it with the B01/B02 procedure (which access → which bound) to keep precision.
- **Panic-safety needs the panic window named explicitly.** Models miss B03/B04 unless prompted to locate the exact line where bookkeeping says "live" but memory isn't. Give the dispatch the "identify the panic window between length-bump and initialization" instruction.
- No model hit-rate dataset specific to this angle was located this pass; calibration above is procedural, not numeric.

---

## 6. Gaps → angle changes

| Methodology | New CHECK / vector / tool | Change type | Anti-bloat: existing coverage? |
|-------------|---------------------------|-------------|--------------------------------|
| B01/B02 bound-direction variance audit (which access → which bound; escape-API recheck) | Strengthen CHECK 1/2 with the "which access the impl enables → which bound is required" step + escape-API trace | extend (existing CHECK) | Partially — existing agent enumerates impls but does not reason about bound *direction* or escape APIs. Extend, don't add. |
| B03/B04 panic-window procedure for raw-memory containers | New CHECK: "locate the panic window between bookkeeping and initialization; require ordering-fix or drop-guard" | extend | Prior draft B04/B09 mention unwind safety but give no panic-window procedure. This replaces them with one concrete check. |
| B05 init-panic → unchecked-read poison | New sub-check under the panic-safety CHECK: lazy/once/cached types with `unreachable_unchecked`/`assume_init` on the post-init path | extend (sub-check) | Not covered. Single sub-check, not a new agent. |
| Rudra as mandatory pre-seed | Wire `cargo rudra` as the angle's pre-seed step; feed flags as candidate list | trigger-fix (tool wiring) | Tooling table lists Rudra; ensure the agent actually *runs* it as step 0. |
| B06/B07/B08 retained as Kani/Miri harnesses only | Keep as methodology with `[generic pattern]` label; no advisory id attached | no change (methodology already present) | Already present; correct the evidence labeling so no false advisory id is attached. |

Anti-bloat conclusion: **no new standalone agent**. The whole gap closes via (a) extending the Send/Sync CHECK with bound-direction + escape-API steps, (b) replacing the vague unwind-safety bullets with one panic-window CHECK plus the B05 sub-check, and (c) wiring Rudra as the pre-seed. B06–B08 stay as honest methodology-only classes.

---

## 7. Sources

All URLs fetched 2026-06-05. Each advisory below was confirmed for **both** the identifier and the mechanism described above.

**Verified real instances (advisory + CVE confirmed):**
1. conquer-once `OnceCell` Sync-without-Send → `MutexGuard` crosses threads — RUSTSEC-2020-0101 / CVE-2020-36208 — https://rustsec.org/advisories/RUSTSEC-2020-0101.html
2. beef `Cow` Send-without-`T: Sync` → `Cell`/`RefCell` data race — RUSTSEC-2020-0122 / CVE-2020-36442 — https://rustsec.org/advisories/RUSTSEC-2020-0122.html
3. aovec `Aovec<T>` unconditional Send/Sync → `Rc`/`Cell` cross threads — RUSTSEC-2020-0099 / CVE-2020-36207 — https://rustsec.org/advisories/RUSTSEC-2020-0099.html
4. im `TreeFocus` unconditional Send/Sync data race — RUSTSEC-2020-0096 / CVE-2020-36204 — https://rustsec.org/advisories/RUSTSEC-2020-0096.html
5. concread `ARCache<K,V>` missing `V: Send+Sync` — RUSTSEC-2020-0092 / CVE-2020-35928 — https://rustsec.org/advisories/RUSTSEC-2020-0092.html
6. reffers `ARefss` unconditional Send/Sync via `.map()` — RUSTSEC-2020-0094 / CVE-2020-36203 — https://rustsec.org/advisories/RUSTSEC-2020-0094.html
7. arenavec drop-uninit on `default()` panic + double-drop on `drop()` panic — RUSTSEC-2021-0040 / CVE-2021-29930, CVE-2021-29931 — https://rustsec.org/advisories/RUSTSEC-2021-0040.html
8. stack_dst `push_cloned` drop-uninit / double-drop on `clone()` panic — RUSTSEC-2021-0033 / CVE-2021-28034, CVE-2021-28035 — https://rustsec.org/advisories/RUSTSEC-2021-0033.html
9. once_cell `Lazy` init-panic → later `unreachable_unchecked` UB — RUSTSEC-2019-0017 / CVE-2019-16141 — https://rustsec.org/advisories/RUSTSEC-2019-0017.html

**Anti-pattern reference (correctly characterized, alignment — NOT a Sync/spinlock bug):**
10. crossbeam-utils `AtomicCell` alignment assumption (`align_of::<u64>() == align_of::<AtomicU64>()` false on 32-bit) — RUSTSEC-2022-0041 / CVE-2022-23639 — https://rustsec.org/advisories/RUSTSEC-2022-0041.html

**Generic pattern / methodology-only (no advisory id attached):**
11. `TrustedLen`/`SpecExtend` soundness — internal std-library discussion, no CVE/advisory — https://github.com/rust-lang/rust/issues/89948

**Secondary (tooling + ecosystem scale):**
12. Rudra: "Finding Memory Safety Bugs in Rust at the Ecosystem Scale," Bae et al., OSDI/SOSP 2021 — 264 bugs / 145 packages → 112 RustSec advisories + 76 CVEs; three patterns: panic safety, higher-order safety invariants, Send/Sync variance — https://www.infoq.com/news/2021/11/rudra-rust-safety/ · paper: https://taesoo.kim/pubs/2021/bae:rudra.pdf · tool: https://github.com/sslab-gatech/Rudra

> **AI-provenance reminder**: This dossier was assembled by an AI agent from primary sources. Every advisory id above was fetched and confirmed for identifier + mechanism on 2026-06-05, but a human auditor must re-validate before any id is cited in a delivered finding — advisory text and CVE aliases can be amended upstream.
