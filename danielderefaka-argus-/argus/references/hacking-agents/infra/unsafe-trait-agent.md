# Unsafe Trait Soundness Agent (`infra` mode — Angle 2)

**Load also**: [`depth-methodology.md`](depth-methodology.md) — depth disciplines (attack-surface enum, pre-auth panic sweep, asymmetric-cost quantification, resource bounds, cross-domain deps, boundary checklist, §WRITE-THEN-VERIFY). Mandatory in Core + Thorough tiers; optional in Light.

**Research grounding**: [`unsafe-trait-research.md`](../../research/unsafe-trait-research.md) — 10-class bug taxonomy (B01–B10) anchored in real Rust unsound-Send/Sync advisories (the conquer-once `OnceCell` Sync-without-Send bug, RUSTSEC-2020-0101) and the Rudra ecosystem-scale soundness study (112 RustSec advisories). Every CHECK below is traceable to a bug class in the dossier.

> **Calibration**: Unsafe trait bugs are narrower than memory safety but just as dangerous — an unsound `Sync` impl silently enables data races in safe code. The bug is invisible to the borrow checker: `unsafe impl Sync` tells the compiler "trust me, this is thread-safe," and the compiler trusts you. Every subsequent safe-code `&T` access from multiple threads is a data race waiting to happen. The anchor case is the conquer-once `OnceCell` bug (RUSTSEC-2020-0101 / CVE-2020-36208): `unsafe impl Sync for OnceCell<T>` lacked a `T: Send` bound, so a `Sync`-but-`!Send` value like `MutexGuard` could be moved across threads through a shared `OnceCell` → UB. The fix is the missing `Send` bound. (Note: crossbeam `AtomicCell`'s RUSTSEC-2022-0041 is a separate *alignment* bug, not a Sync-impl bug — do not conflate them.)
>
> Three sub-classes dominate: **(1) `Send`/`Sync` impls on types with interior mutability** — the type contains `UnsafeCell`, raw pointers, or `!Send`/`!Sync` primitives; the safety contract claims external synchronization that's missing or buggy. **(2) `TrustedLen` impls that lie about `size_hint`** — returning `(n, Some(n))` but yielding fewer than `n` items; downstream safe code pre-allocates buffers of size `n` → OOB write. **(3) Custom Drop / unwind safety** — `Drop` panics during another panic → abort; `unsafe` code relies on Drop for soundness → broken by `std::mem::forget`.
>
> Rudra (`cargo rudra`) is the dedicated static analyzer for `Send`/`Sync` soundness — it finds every `unsafe impl Sync for T` where `T` contains `UnsafeCell`. But Rudra can't reason about complex invariants. The LLM's advantage is reading the `// SAFETY:` contract and systematically verifying each invariant element against the implementation.

**Primary verification backends**: Rudra (`cargo rudra`) for `Send`/`Sync` soundness linting; Kani for `TrustedLen`/`ExactSizeIterator` counterexample proofs; Loom for `Sync`-impl race demonstrations; Miri for Drop/Deref UB. Vectors in **Group B** (`dlt-infra-attack-vectors.md`) are your catalogue.

---

## Phase 1: Pre-seed from tooling

Before manual analysis, seed with mechanical findings:

1. **Run `cargo rudra`** (the single highest-ROI tool for this angle):
   ```bash
   cargo rudra
   ```
   Every `unsafe_send`, `unsafe_sync`, `panic_safety`, or `unsafe_drop` warning → seeded CHECK 1/2/4/9 candidate. Rudra catches ~80% of `Send`/`Sync` soundness bugs mechanically.

2. **Run clippy trait-safety lints**:
   ```bash
   cargo clippy -- -W clippy::missing_safety_doc \
                   -W clippy::undocumented_unsafe_blocks
   ```
   Every `unsafe impl` without a `// SAFETY:` comment → informational finding.

3. **High-signal grep patterns**:
   ```bash
   # Every unsafe impl Send/Sync — CHECK 1/2 audit
   rg 'unsafe\s+impl\s+Send\b' --type rust -l
   rg 'unsafe\s+impl\s+Sync\b' --type rust -l
   # Every unsafe impl TrustedLen/ExactSizeIterator — CHECK 3/5 audit
   rg 'unsafe\s+impl\s+TrustedLen' --type rust -l
   rg 'unsafe\s+impl\s+ExactSizeIterator' --type rust -l
   # Every unsafe impl Deref/AsRef/Borrow — CHECK 6 audit
   rg 'unsafe\s+impl\s+Deref\b' --type rust -l
   # Every custom allocator — CHECK 7 audit
   rg '#\[global_allocator\]' --type rust -l
   rg 'impl\s+GlobalAlloc\b' --type rust -l
   rg 'impl\s+Allocator\b' --type rust -l
   # Every custom Drop — CHECK 4 audit
   rg 'impl\s+Drop\s+for\b' --type rust -l
   # Every AssertUnwindSafe — CHECK 9 audit
   rg 'AssertUnwindSafe' --type rust -l
   ```

---

## Phase 2: Unsafe trait inventory

Enumerate every unsafe trait impl:

- **`unsafe impl Send` inventory**: every type that claims `Send` via `unsafe impl`. For each: list all fields. Flag any `!Send` field (`Rc`, `*mut`, `RefCell`, `UnsafeCell` without sync, raw pointers).
- **`unsafe impl Sync` inventory**: every type that claims `Sync` via `unsafe impl`. For each: list all fields with interior mutability (`UnsafeCell`, `Cell`, `RefCell`, atomics, `Mutex`). For each `UnsafeCell`: what synchronization mechanism guards it?
- **`unsafe impl TrustedLen` inventory**: every iterator claiming exact-length knowledge. For each: trace `size_hint()` and `next()` to verify the count is exact.
- **`unsafe impl Deref` inventory**: every custom deref. For each: verify the returned reference's lifetime and provenance.
- **Custom allocator inventory**: every `GlobalAlloc`/`Allocator` impl.
- **Custom `Drop` inventory**: every `impl Drop`. For each: does it have fallible operations? Does unsafe code depend on it running?

---

## Phase 3: Per-class checks

### CHECK 0 — Unsafe trait safety-contract verification

**Signal**: Every `unsafe impl Trait for Type`. This is the GROUND-LEVEL check.

**Procedure**:
1. For every `unsafe impl`: does it have a `// SAFETY:` comment? If not → informational finding (undocumented safety contract).
2. If it DOES: extract the claimed safety invariants. Each invariant is a proposition like "this type is Send because all fields are Send" or "this type is Sync because the UnsafeCell is guarded by a Mutex."
3. For each claimed invariant: verify it against the implementation.
   a. **Send impl**: every field of `T` must be `Send`, OR documented as never accessed across threads.
   b. **Sync impl**: every field accessible via `&T` must be `Sync`. `UnsafeCell` fields MUST be guarded by synchronization.
   c. **TrustedLen impl**: `size_hint().0 == size_hint().1 AND size_hint().0 >= actual_count`.
   d. **Deref impl**: returned reference must be derived from `&self` data with correct lifetime.

**Golden signature**: Rudra flags for Send/Sync; Kani counterexample for TrustedLen.

**Source**: Rust unsafe code guidelines [model-knowledge].

---

### CHECK 1 — Unsound Send impl (B01)

**Signal**: `unsafe impl Send for T` where `T` contains `!Send` types.

**Procedure**:
1. From Phase 2's Send inventory: for each `unsafe impl Send`, enumerate every field type.
2. **Automatic fail**: `Rc<T>` in a `Send` type — `Rc` is `!Send` by design. The impl can only be sound if the `Rc` is NEVER accessed from another thread. Trace every method — is there a path where another thread holds a clone of this `Rc`? If the type is in a multithreaded context → CONFIRMED unsound.
3. **`*mut T` fail**: raw pointer in a `Send` type — `*mut T` is `!Send`. The impl must document that the pointer is only accessed from the owning thread AND the data is never made visible to other threads.
4. **`UnsafeCell` in `Send`**: `UnsafeCell` IS `Send` (if `T: Send`), so this is NOT a Send violation. But it's a strong signal the type has interior mutability and its `Sync` impl should also be audited.
5. **Bound direction**: `Send for W<T>` that exposes shared `&T` across threads needs `T: Sync` (beef RUSTSEC-2020-0122 — missing `T: Sync` let `Cell`/`RefCell` race). A two-generic wrapper needs the bound on EVERY exposed parameter (concread RUSTSEC-2020-0092 — `V` bound missing). An unconditional `unsafe impl<T> Send for W<T> {}` with no `where` clause is guilty-until-proven-innocent (aovec, im, reffers).
6. **Escape-API recheck**: a bound enforced only at construction is moot if a later `.map()`, `.get_mut()`, `Deref`, iterator, or `into_inner` hands the inner `T`/`&T` back out on another thread. Trace every public accessor that returns the inner data, not just the constructor (reffers RUSTSEC-2020-0094 — unsoundness was through `ARefss::map()`, not the constructor).

**Golden signature**: Rudra `unsafe_send` + manual verification that the `!Send` field can be accessed from another thread.

**Source**: Rudra documentation [model-knowledge]; Rust `Send` trait docs [model-knowledge].

---

### CHECK 2 — Unsound Sync impl (B02)

**Signal**: `unsafe impl Sync for T` where `T` contains interior mutability (`UnsafeCell`, `Cell`, `RefCell`) without correct synchronization.

**Procedure**:
1. From Phase 2's Sync inventory: for each `unsafe impl Sync`, enumerate every `UnsafeCell` field. For each: what synchronization mechanism guards it?
2. **Synchronization & bound-direction audit**:
   a. Is there a Mutex/RwLock wrapping the `UnsafeCell`? Standard pattern, usually correct.
   b. Is there a spinlock implemented via `AtomicBool` + `compare_exchange`? AUDIT THE SPINLOCK: is the compare-exchange correct? Does a TOCTOU window exist where two threads both read the unlocked state? (Generic spinlock-soundness check — no specific advisory anchors this.)
   c. Are atomic operations used directly on the data (not a lock)? Verify ordering: every write must have `Release` semantics and every read must have `Acquire`. `Relaxed` on data-guarding atomics → unsound Sync (relaxed doesn't establish happens-before).
   d. **Bound direction (the real modal bug)**: a `Sync for W<T>` that lets `T` move out on another thread needs `T: Send`; missing it lets a `Sync`-but-`!Send` type (e.g. `MutexGuard`) cross threads — the conquer-once `OnceCell` bug (RUSTSEC-2020-0101). Check the `where` clause against which access the impl actually enables.
   e. **Escape-API recheck**: a `T: Send`/`T: Sync` bound enforced only at construction is defeated if a later `.map()`, `.get_mut()`, `Deref`, iterator, or `into_inner` re-exposes the inner `T`/`&T` across threads. Trace every public accessor that returns the inner data — the unsound path may bypass the constructor entirely (reffers RUSTSEC-2020-0094 — unsoundness was through `ARefss::map()`).
3. **Non-UnsafeCell interior mutability**: `Cell<T>` and `RefCell<T>` are `!Sync`. A type containing them CANNOT be `Sync`. Rudra catches this statically.
4. Write a Loom test for the Sync impl: spawn N threads, each doing concurrent reads and writes through `&T`. Loom explores all interleavings. A data race → CONFIRMED unsound.

**Golden signature**: Rudra `unsafe_sync` + Loom race detection. Miri supplement for data-race detection.

**Source**: conquer-once `OnceCell` Sync-without-Send → `MutexGuard` crosses threads — RUSTSEC-2020-0101 / CVE-2020-36208. **Misattribution guard**: crossbeam `AtomicCell` (RUSTSEC-2022-0041 / CVE-2022-23639) is an **alignment** bug (`align_of::<u64>()` ≠ `align_of::<AtomicU64>()` on 32-bit → unaligned access + data race), NOT a spinlock-TOCTOU or unsound-Sync-impl bug — do not cite it as one. See `unsafe-trait-research.md`.

---

### CHECK 3 — Unsound TrustedLen impl (B03)

**Signal**: `unsafe impl TrustedLen for I` where `size_hint()` overstates the actual count.

**Procedure**:
1. For every `unsafe impl TrustedLen`: the contract is `size_hint()` returns `(n, Some(n))` where `n` is the EXACT number of remaining items. `next()` must not return `None` before `n` items are yielded.
2. Trace `size_hint()`: how is `n` computed? From a `Vec::len()`? Static length? Counter field?
3. Trace `next()`: what causes it to return `None`? Can the condition be met before `n` items are yielded?
4. **Common failure modes**:
   - `n` from `map.len()` which skips removed entries
   - `n` from `vec.len()` but `next()` pops conditionally based on a filter
   - `n` computed at construction but the underlying collection is mutated during iteration
5. Kani harness: `#[kani::proof] fn check_trusted_len() { let iter = ...; let (n, _) = iter.size_hint(); let actual = iter.count(); assert!(n <= actual); }`

**Golden signature**: Kani counterexample where `size_hint().0 > count()`.

**Source**: Rust `TrustedLen` documentation [model-knowledge].

---

### CHECK 4 — Custom Drop soundness (B04)

**Signal**: `impl Drop for T` where the Drop has fallible operations OR `unsafe` code depends on Drop running.

**Procedure**:
1. For every `impl Drop`: scan for fallible ops — `.unwrap()`, `.expect()`, `panic!()`, `assert!()`, indexing `[]`, division `/`. Each is a panic-in-drop risk.
2. **std::mem::forget safety**: can `forget` cause UB? If `unsafe` code depends on `Drop::drop()` releasing a resource → unsound. The standard says: "safe code cannot rely on Drop being called for soundness." Unsafe code must handle the case where Drop never runs.
3. **Double-free in Drop**: does the Drop free memory that could also be freed elsewhere? Check for `ManuallyDrop` wrapping — it suppresses Drop; if the wrapper is forgotten, the inner value's Drop never runs (intentional). If the wrapper is then dropped manually AND the wrapper also drops → double-free.
4. Write a Miri test that calls `std::mem::forget` on the type and then uses the resource; Miri catches UAF if the resource was freed by Drop.

**Golden signature**: Miri UAF when Drop is skipped; `RUST_BACKTRACE=1` on double-panic.

**Source**: Rust Drop documentation [model-knowledge]; `std::mem::forget` safety docs [model-knowledge].

---

### CHECK 5 — Unsound ExactSizeIterator impl (B05)

**Signal**: `impl ExactSizeIterator for T` where `len()` doesn't equal the actual remaining count.

**Procedure**:
1. Same as CHECK 3 — `ExactSizeIterator` is a safe trait, but implementing it incorrectly violates the trait contract. The primary test: `assert_eq!(iter.len(), iter.clone().count())` for all reachable states.
2. Kani harness: prove `len() == count()` for all states.

**Golden signature**: Kani counterexample.

**Source**: Rust `ExactSizeIterator` documentation [model-knowledge].

---

### CHECK 6 — Unsafe Deref/AsRef/Borrow impl (B06)

**Signal**: `unsafe impl Deref for T` or `unsafe impl DerefMut for T`.

**Procedure**:
1. For every `unsafe impl Deref`: verify the returned reference's TARGET data is actually owned by `self` and lives at least as long as the returned reference.
2. **Lifetime extension**: `deref(&'a self) -> &'a Target` — the returned reference has lifetime `'a`. Verify the Target data lives for at least `'a`. Common bug: Target data is a `static` that was allocated and freed before the Deref container was dropped → the reference is valid during `'a` but the container outlives the data.
3. **Transmute-based Deref**: `deref()` uses `transmute` to extend a lifetime → immediate CANDIDATE. Check the transmute with CHECK 8 from Memory Safety agent.

**Golden signature**: Miri UAF if Target data is freed before the Deref reference.

**Source**: Rust `Deref` documentation [model-knowledge].

---

### CHECK 7 — Custom allocator contract violation (B07, B08)

**Signal**: `#[global_allocator]`, `impl GlobalAlloc`, or `impl Allocator`.

**Procedure**:
1. **Alignment contract**: `alloc(layout)` MUST return a pointer aligned to `layout.align()`. Verify the allocator honors this. `malloc` guarantees alignment to `max(alignof(max_align_t), size)`; custom bump allocators may not.
2. **Layout match**: `dealloc(ptr, layout)` MUST use the SAME layout as `alloc`. Verify callers pass the correct layout. Miri checks layout congruence.
3. **Zero-size**: `alloc(Layout::new::<()>())` returns a 0-size allocation. Must return a non-null, well-aligned dangling pointer. Must NOT return null (unless explicitly documented).
4. **Realloc contract**: `realloc(ptr, old_layout, new_size)` — if `new_size == 0`, equivalent to `dealloc`. If `ptr == null`, equivalent to `alloc`. Verify both edge cases are handled.

**Golden signature**: Miri with `-Zmiri-check-alignments`; Kani harness proving the contract.

**Source**: Rust `GlobalAlloc` documentation [model-knowledge].

---

### CHECK 8 — Unwind safety in unsafe trait impls (B09)

**Signal**: `unsafe impl` that mutates state without ensuring unwind safety; `AssertUnwindSafe` wrapper.

**Procedure**:
1. For every `unsafe impl` that mutates state: what happens if a panic occurs mid-mutation? Does the state remain valid?
2. **AssertUnwindSafe audit**: every `AssertUnwindSafe(|| { ... })` wrapper is a claim that the closure is unwind-safe. Verify:
   a. The closure doesn't leave dangling pointers on panic.
   b. The closure doesn't leave invalid enum discriminants on panic.
   c. Any shared state is restored to a valid state (even if not the intended state).
3. **`panic = "abort"` interaction**: if `Cargo.toml` sets `panic = "abort"`, panics never unwind → unwind safety is irrelevant. But the Drop-not-called problem remains (CHECK 4).
4. Write a test: `catch_unwind(AssertUnwindSafe(|| { suspect_operation() }))`. After catching, assert the state is valid.

**Golden signature**: Test that catches a panic after mid-mutation and asserts state validity; failure = corrupted state.

**Source**: Rust unwind safety documentation [model-knowledge].

---

### CHECK 9 — Panic window in raw-memory ownership code (B03, B04)

**Signal**: `unsafe` code that calls a *user-controlled* function (`T::default()`, `T::clone()`, `T::drop()`, a closure) while the container's bookkeeping is in a transient invalid state — a length already bumped, a slot reserved via `ptr::write` pending, a value `ptr::read` out but the source not yet `forget`-ten, or `set_len` called before initialization. Hot spots: arena/`Vec`-like `resize`/`resize_with`/`push`/`extend`/`map` over raw memory.

**Procedure**:
1. Enumerate every block that pairs a raw-memory op (`ptr::write`, `ptr::read`, `set_len`, `MaybeUninit`, `alloc`) with a call into generic `T` code (`T::default`, `T::clone`, `Drop`, user closure).
2. **Name the panic window**: the exact span between the moment bookkeeping says "this slot is live/owned" and the moment it is actually initialized/disowned. If the user function panics *inside* this window, what does unwinding do with the slot?
   - Length bumped *before* `clone()` → unwind drops an uninitialized/half-moved slot (stack_dst RUSTSEC-2021-0033: `push_inner` increments length, then `val.clone()` panics → drop-uninit / double-drop).
   - `default()`/`clone()` panics while constructing → uninitialized `T` is dropped (arenavec RUSTSEC-2021-0040, drop-uninit).
   - A user `Drop` panics mid-`resize`/`resize_with` → the same element is dropped twice on unwind (arenavec RUSTSEC-2021-0040, double-drop).
3. **Require the fix to be present**: bookkeeping that marks a slot live must happen *after* the fallible user call, OR a drop-guard / `ScopeGuard` must disarm only on success. Absence of either across a live panic window = CONFIRMED finding.

**Sub-check B05 — init-panic poisons a "trust-me" later access**: for lazy/once/cached-init types (`OnceCell`, `Lazy`, memoization wrappers) whose init closure is user-controlled AND whose post-init read path uses an unchecked primitive (`unreachable_unchecked`, `assume_init`, `get_unchecked`, `unwrap_unchecked`):
1. Find the state transition that marks the cell "initialized".
2. Determine whether a panic in the init closure is observed *before or after* that transition.
3. If a panicking init can leave a "looks-initialized-but-isn't" state and a later read uses an unchecked primitive → UB (once_cell `Lazy` RUSTSEC-2019-0017: panic in first deref → later derefs hit `unreachable_unchecked`).
4. The sound pattern records *failure* (or re-runs init) on panic, or marks initialized only after the value is written. Confirm one exists.

**Anti-pattern (false-positive guard)**: `MaybeUninit` plus a drop-guard that counts only *initialized* elements, or code that completes all fallible work before touching length, is unwind-safe even though it looks scary — a correctly-scoped guard clears the window.

**Golden signature**: a `catch_unwind` test with a `T` whose `Default`/`Clone`/`Drop` panics on the Nth call, asserting no double-drop (drop counter) and no uninit read under Miri; for B05, an init closure that panics once followed by a second access surfaces UB under Miri.

**Source**: arenavec RUSTSEC-2021-0040 / CVE-2021-29930,29931; stack_dst RUSTSEC-2021-0033 / CVE-2021-28034,28035; once_cell `Lazy` RUSTSEC-2019-0017 / CVE-2019-16141.

---

## Stage-3 PoC discipline

| Class | Backend | Command |
|-------|---------|---------|
| B01 (Send) | Rudra + manual | `cargo rudra` |
| B02 (Sync) | Rudra + Loom | `cargo rudra` + `cargo test --features loom` |
| B03 (TrustedLen) | Kani | `cargo kani --harness check_trusted_len_<ID>` |
| B04 (Drop) | Miri + unit test | `cargo miri test` |
| B05 (ExactSizeIterator) | Kani | `cargo kani --harness check_exact_size_<ID>` |
| B06 (Deref) | Miri | `cargo miri test` |
| B07 (Allocator) | Miri + Kani | `cargo miri test` + `cargo kani` |
| B09 (Unwind) | Unit test + catch_unwind | `cargo test test_unwind_<ID>` |
| Panic window / B03,B04,B05 (CHECK 9) | Rudra + Miri + catch_unwind | `cargo rudra` + `cargo +nightly miri test test_panic_window_<ID>` |

**Tier-1-formal**: Rudra finding + Loom/Miri/Kani confirmation. Without mechanical confirmation: max CONTESTED.

## Output fields beyond shared FINDING schema

```yaml
unsafe_trait: Send | Sync | TrustedLen | ExactSizeIterator | Deref | DerefMut | GlobalAlloc | Allocator
type_name: <the type implementing the unsafe trait>
claimed_invariant: <the safety claim from // SAFETY: comment>
violation: <which element of the claim is false>
field_at_fault: <the specific field that breaks the invariant>
rudra_flag: <unsafe_send | unsafe_sync | panic_safety | unsafe_drop | none>
verification_backend: Rudra | Loom | Kani | Miri | Manual
```

## Anti-patterns (do NOT report)

- `unsafe impl Send for T` where ALL fields are provably `Send` — the impl is unnecessary (Send would be auto-derived) but not unsound.
- `unsafe impl Sync` on a type where the only interior mutability is behind a correctly-implemented Mutex — safe by construction, not a finding.
- `TrustedLen` impl where `size_hint()` correctly reports the exact count — the impl is sound.
- `AssertUnwindSafe` used on a closure that is provably unwind-safe (no state mutation, no unsafe blocks) — correct usage, not a finding.
- `unsafe impl` with a `// SAFETY:` comment that correctly documents ALL safety invariants AND the implementation satisfies all of them — this is the gold standard, not a bug.

## Coordination with other angles

- **Memory Safety (Angle 1)** owns the UB that results from an unsound Sync impl (Miri race detection). Angle 2 owns the impl-level determination of why it's wrong.
- **Concurrency (Angle 4)** owns the runtime evidence (Loom failing schedule). Angle 2 identifies the impl as the root cause; Angle 4 demonstrates the exploit.
- **Supply Chain & FFI (Angle 8)** owns FFI repr checks for B10. Angle 2 owns the trait-boundary implications (e.g., `unsafe impl Send` on FFI wrapper types).
