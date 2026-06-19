# Memory Safety & Provenance Agent (`infra` mode — Angle 1)

**Load also**: [`depth-methodology.md`](depth-methodology.md) — depth disciplines (attack-surface enum, pre-auth panic sweep, asymmetric-cost quantification, resource bounds, cross-domain deps, boundary checklist, §WRITE-THEN-VERIFY). Mandatory in Core + Thorough tiers; optional in Light.

**Research grounding**: [`memory-safety-research.md`](../../research/memory-safety-research.md) — 12-class bug taxonomy (A01–A12) anchored in Rust CVEs and production DLT memory-safety incidents. Every CHECK below is traceable to a bug class in the dossier.

> **Calibration**: Rust eliminates ~70% of C/C++ memory safety bugs at compile time (bounds checking, borrow checking, no use-after-free in safe code). The bugs that REMAIN are concentrated in three zones: **(1) `unsafe` blocks that violate their documented safety contract** — the developer wrote `// SAFETY:` claiming an invariant holds; it doesn't → UB. This accounts for the majority of Rust CVEs in DLT infrastructure. **(2) FFI boundary unsoundness** — Rust calls C with incorrect type layouts or lifetime assumptions; C corrupts Rust-owned memory → UB on next access. **(3) Aliasing / provenance violations** — violating Stacked Borrows (current Miri default) or Tree Borrows (stricter upcoming model) when creating references from raw pointers. The deadliest class is **pointer provenance violation** — using a pointer after its allocation was freed, or deref'ing a pointer created from an integer.
>
> Two memory models govern UB detection: **Stacked Borrows** (Miri default) and **Tree Borrows** (newer, catches a superset). Run Miri under BOTH. A pass under Stacked Borrows doesn't mean the code is sound — Tree Borrows catches more aliasing violations.
>
> The LLM's advantage is systematic enumeration: every `unsafe` block must have its safety contract verified; every `transmute` must have size/alignment/lifetime checked; every raw-pointer access must have provenance traced to a live allocation.

**Primary verification backends**: Miri (`cargo miri test`) for UB detection; Miri with `-Zmiri-tree-borrows` for stricter aliasing; Miri with `-Zmiri-tag-raw-pointers` for provenance; Kani for bounded safety proofs; ASan/Valgrind for runtime detection in FFI code. Vectors in **Group A** (`dlt-infra-attack-vectors.md`) are your catalogue.

---

## Phase 1: Pre-seed from tooling

Before manual analysis, seed with mechanical findings:

1. **`cargo geiger`** — unsafe footprint per crate. Crates with high unsafe ratios get priority manual review.
   ```bash
   cargo geiger
   ```

2. **`cargo audit`** — known-vuln crate versions (RustSec advisory DB). Flag every advisory with "memory", "unsound", "UB", "buffer", "overflow", "use-after-free", or "unsafe" keywords.
   ```bash
   cargo audit
   ```

3. **Clippy unsafe lints**:
   ```bash
   cargo clippy -- -W clippy::missing_safety_doc \
                   -W clippy::undocumented_unsafe_blocks \
                   -W clippy::transmute_ptr_to_ptr \
                   -W clippy::transmute_int_to_float \
                   -W clippy::transmute_int_to_bool \
                   -W clippy::cast_ptr_alignment
   ```

4. **High-signal grep patterns**:
   ```bash
   # Every unsafe block — CHECK 0 audit
   rg 'unsafe\s*\{' --type rust -l
   # Every transmute — CHECK 8 audit
   rg 'transmute' --type rust -l
   # Every MaybeUninit::assume_init — CHECK 5 audit
   rg 'assume_init\(' --type rust -l
   # Every *mut T cast — CHECK 6 provenance audit
   rg 'as \*mut' --type rust -l
   # Every extern "C" — CHECK 12 unwinding audit
   rg 'extern\s+"C"' --type rust -l
   # Every union definition — CHECK 9 audit
   rg '^union\s' --type rust -l
   # Every ptr::drop_in_place — CHECK 2/3 audit
   rg 'drop_in_place' --type rust -l
   # Every ptr::copy/copy_nonoverlapping — CHECK 4 audit
   rg 'ptr::copy' --type rust -l
   ```

---

## Phase 2: Unsafe surface inventory

Enumerate every memory-safety surface:

- **Unsafe block inventory**: every `unsafe { }` block in the codebase. For each: extract the `// SAFETY:` comment (or note its absence — missing safety doc is itself a finding). Enumerate the claimed safety invariant. Verify each element (CHECK 0).
- **Raw pointer inventory**: every `*const T` and `*mut T`. For each: what allocation is it derived from? Is that allocation still live? What operations are performed on it (read, write, offset, drop)?
- **Transmute inventory**: every `mem::transmute`. Source type, target type, sizes, alignments, lifetimes.
- **FFI boundary inventory**: every `extern "C" fn` (both directions). Does Rust call C? Does C call Rust? Are there callbacks?
- **Allocation/deallocation inventory**: every custom allocator, `alloc`, `dealloc`, `realloc`, `Box::from_raw`, `Vec::from_raw_parts`, `ptr::drop_in_place`.
- **Union inventory**: every `union` definition and access site.

---

## Phase 3: Per-class checks

### CHECK 0 — Unsafe block safety-contract verification (all classes)

**Signal**: Every `unsafe { }` block. This is the GROUND-LEVEL check — all other CHECKs are specializations of this one.

**Dominant pattern — safe API over unsafe invariant** (highest-yield framing): Most advisory-grade Rust memory bugs surface through a *safe* public API whose soundness depends on an `unsafe` invariant the caller can violate (smallvec, bytes, vmm-sys-util, lru, bumpalo, borsh). For EACH public safe `fn`/method, ask: *which `unsafe` invariant does its soundness rest on (a length matches, a lifetime is bounded, a pointer is unique), and can an ordinary safe caller break it?* Auditing `unsafe` blocks in isolation misses this class — start from the public API surface, then trace inward to the invariant.

**Procedure**:
1. For every `unsafe` block: does it have a `// SAFETY:` comment? If not → `clippy::undocumented_unsafe_blocks` violation. The finding is: "undocumented unsafe block — safety invariant not stated."
2. If it DOES have a `// SAFETY:` comment: extract the claimed invariant(s). Each invariant is a proposition like "the pointer `p` is valid for reads of size `n`" or "this raw pointer was derived from a `&T` that is still live."
3. For each claimed invariant: verify it against the code.
   a. **Pointer validity**: is the pointer non-null, aligned, and pointing to a live allocation of sufficient size?
   b. **No-aliasing**: does the creation of a `&mut` reference invalidate other references to the same data? (CHECK 7)
   c. **Lifetime**: does any reference created inside the `unsafe` block outlive the allocation it points to?
   d. **Initialization**: is all memory read inside the block guaranteed to be initialized? (CHECK 5)
   e. **Send/Sync**: if the block deals with thread-bound types, are `Send`/`Sync` contracts maintained?
4. If ANY invariant element fails → CONFIRMED UB. The `// SAFETY:` comment is wrong.

**Golden signature**: Miri test exercising the unsafe block. The exact Miri error identifies which invariant element failed.

**Severity**: Critical if the UB is reachable from untrusted input (consensus, p2p). High if reachable from authenticated/role-gated paths. Medium if test-only or behind feature flags.

**Source**: Rust unsafe code guidelines [model-knowledge]; every Rust CVE involves a violated safety invariant.

---

### CHECK 1 — Alignment violation (A01)

**Signal**: `ptr::read()` / `ptr::write()` on potentially misaligned address; `#[repr(packed)]` field access via pointer; `transmute` to stricter-alignment type.

**Procedure**:
1. For every `ptr::read(p)` and `ptr::write(p, v)`: verify `p` is aligned to `align_of::<T>()`. Source of `p` must be from `Layout::from_size_align(_, align)` with correct alignment, or derived from `&T` (guaranteed).
2. **Packed struct fields**: `#[repr(packed)]` fields are potentially misaligned. Code must use `ptr::addr_of!(packed.field).read_unaligned()` — never `&packed.field` (compile error) or `ptr::read(&packed.field)` (compiles but UB).
3. **Field-order assumption**: bare `#[repr(packed)]` does NOT guarantee field order — only `#[repr(C, packed)]` does. rustc 1.80 began reordering bare-`packed` fields, breaking unsafe access keyed on offsets (zerovec-derive). Confirm any offset-keyed packed access uses `#[repr(C, packed)]`.
4. **32-bit atomic alignment**: never assume a primitive and its atomic share alignment. On 32-bit targets `align_of::<u64>()` can be 4 while `align_of::<AtomicU64>()` is 8 (crossbeam-utils) → unaligned atomic + data race. Check the *smallest* supported target, not the dev machine.
5. **`transmute::<[u8; N], T>()`**: `T` may need alignment > 1. If the byte buffer is on the stack or heap with default alignment, it may be under-aligned for `T`. Use `T::try_from_bytes()` or equivalent.
6. Miri catches alignment UB automatically; cross-compile and run the suite for a 32-bit target (`cargo test --target i686-unknown-linux-gnu`) to surface target-specific cases.

**Golden signature**: Miri: `error: Undefined Behavior: accessing memory based on pointer with alignment X but alignment Y is required`.

**Severity**: High — alignment UB is usually a crash. Medium on x86 (x86 tolerates some misalignment for non-SIMD types).

**Source**: Rust reference on type layout [model-knowledge].

---

### CHECK 2 — Use-after-free (A02)

**Signal**: Raw pointer retained past deallocation; `ManuallyDrop<T>` where `T` is accessed after manual drop; `Vec::set_len(0)` followed by pointer access.

**Procedure**:
1. For every explicit `dealloc` or `Box::from_raw` → `drop`: enumerate ALL pointers derived from the same allocation. Are any stored in other data structures? Check for cached raw pointers, saved indices, `Weak<T>` that was upgraded.
2. `Vec::set_len(0)` + `Vec::as_ptr()`: the allocation is still alive but elements are logically freed. Reading from indices ≥ 0 after `set_len(0)` is logically-UAF even if not Miri-detectable.
3. `ManuallyDrop::drop()`: after this, the memory is freed. Verify no subsequent code accesses the `ManuallyDrop` wrapper or the contained value.
4. **Iterator / lifetime escape** (the safe-API UAF archetype): for every public method returning a reference or iterator, confirm the return type's lifetime is bounded to the allocation/owner. A returned `IntoIter` with NO `'a` parameter can outlive its store (bumpalo `Vec::into_iter()`). For `iter`/`iter_mut` handing out references into nodes, enumerate which *other* methods (`pop`, `remove`, `clear`) can free those nodes while the iterator is live — if any can, the references dangle (lru). For constructors `fn new(buf: &mut T) -> Ctx`, confirm `Ctx`'s lifetime is bounded by `buf` and `Ctx::drop` does not free a borrowed `buf` (secp256k1 `preallocated_gen_new`).
5. Write a Miri test simulating the suspect sequence: get the iterator/ref, perform the freeing op or drop the owner, then access the iterator/ref.

**Golden signature**: Miri: `error: Undefined Behavior: dereferencing pointer to allocation <id> which has been freed`.

**Source**: lru `iter`/`iter_mut` hand out references freed by `pop()` — RUSTSEC-2021-0130; lru `IterMut::next` Stacked-Borrows violation — RUSTSEC-2026-0002; bumpalo `Vec::into_iter()` not lifetime-bound to its `Bump` — RUSTSEC-2022-0078; secp256k1 `preallocated_gen_new` incorrect lifetime bound — RUSTSEC-2022-0070. See `memory-safety-research.md` §A02.

---

### CHECK 3 — Double-free (A03)

**Signal**: Two deallocation calls on the same pointer; `Box::from_raw` called twice on same pointer; `drop_in_place` + Drop.

**Procedure**:
1. For every allocation site: map all deallocation paths. Do they converge on the same pointer? Use a graph: each `dealloc(p)`, `drop(Box::from_raw(p))`, or `ptr::drop_in_place(p)` is a node. If two nodes have the same `p` (by value) and can both execute → double-free.
2. **Panic paths**: a `dealloc` in the success path and a `dealloc` in the panic handler → double-free if both execute. Check for missing guards.
3. Miri catches double-free at runtime.

**Golden signature**: Miri: `error: Undefined Behavior: deallocating memory at <addr> which has already been freed`.

**Source**: Rust std::alloc documentation [model-knowledge].

---

### CHECK 4 — Out-of-bounds pointer arithmetic / buffer overflow (A04)

**Signal**: `ptr.add(offset)` with unbounded offset; `ptr::copy` / `ptr::copy_nonoverlapping` with untrusted count; length-prefix-trusted deserialization.

**Procedure**:
1. For every `ptr.add(n)`: verify `n ≤ allocated_size - offset_of(ptr)` where both values are known. If `n` comes from untrusted input → HARD CANDIDATE.
2. For every `ptr::copy(src, dst, count)`: verify `count * size_of::<T>() ≤ bytes_remaining(src)` AND `count * size_of::<T>() ≤ bytes_remaining(dst)`. If `count` is from a length prefix in deserialized data → Heartbleed pattern.
3. **Deserialization special case** (the Heartbleed pattern):
   ```rust
   // VULNERABLE: trusts length prefix without verifying against remaining buffer
   let len = u32::from_le_bytes(buf[0..4].try_into().unwrap()) as usize;
   let data = buf.as_ptr().add(4);
   let out = slice::from_raw_parts(data, len); // if len > buf.len() - 4 → OOB
   ```
   The fix: assert `len <= buf.len() - 4` before `from_raw_parts`.
4. **FFI special case**: C function writes `n` bytes to a Rust buffer. Verify `n ≤ buffer.len()`. If `n` is from the C side and NOT verified → OOB write candidate.
5. **Unchecked index**: for every `get_unchecked[_mut](i)`, trace `i` to its source. If `i` can derive from untrusted input with no prior `i < len` check on the *same* buffer → OOB write/read (grcov).
6. **`size_hint` trust**: for any allocation sized from `iter.size_hint().0` (the *lower* bound) followed by unchecked per-item writes, confirm the buffer grows per-item rather than pre-sizing to the hint — a lying `size_hint` overflows it (smallvec `insert_many`).
7. **Capacity-arithmetic overflow**: for every `a + b` capacity check (`new_cap + offset`, `len + additional`) gating an `unsafe` write, confirm `checked_add`/`saturating_add` — unchecked `usize` overflow makes the gate pass and corrupts capacity, exposing OOB via the safe API (bytes `BytesMut::reserve` → `spare_capacity_mut()`).
8. **Release-path discipline**: a bound checked only in debug (`debug_assert!`, implicit `[]` panic) but elided in the `unsafe` release path is NOT a defense — audit the release path.

**Golden signature**: Miri: `error: Undefined Behavior: dereferencing pointer at offset X past the end of allocation`. ASan: `heap-buffer-overflow`.

**Source**: smallvec `insert_many` trusts a `size_hint` lower bound and writes past the buffer — RUSTSEC-2021-0003; vmm-sys-util `FamStructWrapper::deserialize` never checks header length vs flexible-array length — RUSTSEC-2024-0002; bytes `BytesMut::reserve` unchecked `new_cap + offset` → corrupted capacity → OOB slice — RUSTSEC-2026-0007. The "trust an untrusted length prefix" archetype is Heartbleed (CVE-2014-0160, OpenSSL C — cross-language analogy only, never a Rust id). See `memory-safety-research.md` §A04.

---

### CHECK 5 — Uninitialized memory read (A05)

**Signal**: `MaybeUninit::uninit().assume_init()`; `set_len(new_len)` where `new_len > old_len` without initializing; reading padding bytes; `std::mem::uninitialized()`.

**Procedure**:
1. Grep for `assume_init()`. For every call: trace backward to the `MaybeUninit`'s creation. Was it `MaybeUninit::uninit()` or `MaybeUninit::zeroed()`? If `uninit()`: was EVERY byte written before `assume_init`? If the writes are conditional → UB possible when the write path is skipped.
2. `Vec::set_len(new_len)` where `new_len > self.len()`: the new elements are uninitialized. Verify there are `ptr::write` calls or copy operations for every new element BEFORE any read.
3. **Padding bytes**: `#[repr(C)] struct` byte-transmuted from a buffer — padding bytes are read as part of the transmute. Not UB (padding bytes are initialized) but can leak data if the struct is serialized/sent over network.
4. Miri catches uninit reads.

**Golden signature**: Miri: `error: Undefined Behavior: reading from uninitialized memory at <location>`.

**Source**: Rust MaybeUninit documentation [model-knowledge].

---

### CHECK 6 — Invalid pointer provenance (A06)

**Signal**: `(addr as *mut T)` where `addr` wasn't obtained from a live pointer; pointer used after `realloc`; `ptr::dangling()` deref.

**Procedure**:
1. **Integer-to-pointer**: every `addr as *mut T` or `ptr::from_exposed_addr(addr)`. Trace the origin of `addr` — was it from `ptr as usize` where `ptr` was valid? If `addr` is from an FFI source (C code passes an integer as a "pointer") → it has no Rust provenance → deref is UB even if the address is "correct." Use `ptr::with_exposed_provenance(addr)` and document why the provenance transfer is sound.
2. **Realloc**: `alloc::realloc(old_ptr, layout, new_size)` returns a new pointer. `old_ptr` MUST NOT be used — its provenance is consumed. Verify no code caches `old_ptr` and derefs it after `realloc`.
3. **Dangling**: `ptr::dangling()` returns a well-aligned, non-null pointer with NO provenance. Verify it's never deref'd — it's only for `Vec::as_ptr()` on empty Vecs.
4. **Null pointer**: `ptr::null()` and `NonNull::dangling()` — deref is UB. Check for missing null checks before ptr deref.
5. Miri with `-Zmiri-tag-raw-pointers` tracks provenance.

**Golden signature**: Miri: `error: Undefined Behavior: dereferencing pointer with no provenance` or `pointer to allocation <id> which has been freed`.

**Source**: Rust Strict Provenance RFC [model-knowledge]; Miri provenance tracking [model-knowledge].

---

### CHECK 7 — Stacked Borrows / Tree Borrows aliasing violation (A07)

**Signal**: Creating `&mut` while another reference to overlapping memory is live; writing through raw pointer derived from `&T`; `&mut` aliasing.

**Procedure**:
1. For every `unsafe` block that creates a `&mut` from a raw pointer:
   a. Is the raw pointer derived from `&T` (shared ref) or `*const T`? Creating `&mut` from shared provenance → UB (can't upgrade read-only to mutable).
   b. Is there another reference (`&`, `&mut`, or raw ptr from `&`) to overlapping memory still in scope? If yes → aliasing violation.
2. **Two `&mut` to same data**: `let r1 = &mut *p; let r2 = &mut *p;` — both live simultaneously → UB. The second `&mut` creation invalidates the first.
3. **Write through shared-provenance raw pointer**: `let r = &x; let p = r as *const T as *mut T; *p = new_value;` → UB (writing through read-only provenance).
4. **UnsafeCell is the only legal route**: shared-mutable access must go through `UnsafeCell`/`Cell`/atomics — a bare `&mut` while a `&` (or raw ptr derived from `&`) to the same memory is live is UB regardless of runtime behavior. Confirm the cell before flagging; code routing through `UnsafeCell` is legal, not a finding.
5. **Run Miri under BOTH models**:
   ```bash
   # Default: Stacked Borrows
   cargo miri test
   # Stricter: Tree Borrows
   MIRIFLAGS="-Zmiri-tree-borrows" cargo miri test
   ```
   A pass under Stacked Borrows but UB under Tree Borrows → STILL A BUG. Tree Borrows is the upcoming model; fix for both.

**Golden signature**: Miri (Stacked Borrows): `error: Undefined Behavior: attempting a write access using <TAG> but <OTHER> is also live`. Miri (Tree Borrows): `error: Undefined Behavior: read access through <TAG> is forbidden`.

**Source**: Stacked Borrows paper (Jung et al., PLDI 2020) [model-knowledge]; Tree Borrows proposal (Toman 2023) [model-knowledge].

---

### CHECK 8 — Transmute unsoundness (A08)

**Signal**: Every `mem::transmute::<T, U>()` call.

**Procedure**:
1. **Compile-time size check**: verify `size_of::<T>() == size_of::<U>()`. If sizes differ → immediate UB. Use `const_assert_eq!(size_of::<T>(), size_of::<U>())` before transmute.
2. **Alignment check**: `align_of::<T>() >= align_of::<U>()`. If `T` is less aligned than `U` → UB. Alternative: use transmute via `[u8; N]` intermediate — byte arrays have alignment 1.
3. **Lifetime extension**: `transmute::<&'a T, &'static T>` — extends lifetime; allows use-after-free. Any transmute between reference types → CANDIDATE.
4. **Invalid values**: transmuting integers to `bool` (only 0/1 valid), to `char` (only valid Unicode), to `NonNull` (non-null), or to enums with discriminant checking. If the source value can be out-of-range → UB.
5. **Prefer safe alternatives**: `bytemuck::cast()`, `zerocopy::FromBytes`, `std::mem::size_of`+`align_of` checks, or safe pointer casts.

**Golden signature**: Miri catches invalid bool/enum values at runtime. Size/alignment mismatches: compile-time `const_assert` fails.

**Source**: Rust nomicon on transmutes [model-knowledge]; `bytemuck` crate documentation [model-knowledge].

---

### CHECK 9 — Unsound union field access (A09)

**Signal**: Reading a union field that wasn't the last-written field, especially for non-Copy types.

**Procedure**:
1. For every `union`: list all fields. For each field: is it `Copy`? Fields without `Copy` AND with `Drop` → reading wrong variant is UB.
2. For every field access `u.field`: verify the union was last written via `u.field = value`. Check for a discriminant/tag enum that guards the access.
3. **ManuallyDrop usage**: non-Copy union fields should be wrapped in `ManuallyDrop<T>` — this makes them safe to have in a union (suppresses Drop on the inactive variant).
4. **C union pattern mismatch**: Rust union rules are STRICTER than C. FFI code mirroring C union access where "any field can be read" → likely UB in Rust.

**Golden signature**: Miri (nightly with union tracking): `error: Undefined Behavior: read from union field <f1> but the union was last written to <f2>`.

**Source**: Rust reference on unions [model-knowledge].

---

### CHECK 10 — Invalid drop / panic-in-drop (A10)

**Signal**: `.unwrap()`, `.expect()`, `panic!()`, `assert!()` inside `Drop::drop()`; `unsafe` code relying on Drop for soundness.

**Procedure**:
1. For every `Drop::drop()` impl: scan for any operation that could panic. If the program is already unwinding → double-panic → `abort()` → process death. In a validator, this halts the chain.
2. **`panic = "abort"` check**: read `Cargo.toml` for `panic = "abort"`. In abort mode, panics NEVER call Drop. Any `unsafe` code relying on Drop for cleanup → UB when a panic occurs. Verify ALL `unsafe` blocks are sound without Drop.
3. **std::mem::forget safety**: `forget` is safe to call. `unsafe` code MUST NOT rely on Drop for soundness — because `forget` can always skip Drop. If an unsafe block's safety depends on a Drop impl running → unsound.

**Golden signature**: Double-panic → `abort()`. Run with `RUST_BACKTRACE=1` to observe.

**Source**: Rust Drop documentation [model-knowledge]; `std::mem::forget` safety docs [model-knowledge].

---

### CHECK 11 — Type confusion via repr(C) / FFI layout mismatch (A11)

**Signal**: `#[repr(C)]` struct passed across FFI boundary where Rust and C definitions differ.

**Procedure**:
1. For every `#[repr(C)]` struct in FFI code: find the corresponding C struct definition. Verify field-for-field: same types, same order, same ABI widths.
2. **C type mapping**: use `std::os::raw::c_*` or `libc::c_*` types. Never use Rust native types (`i32`, `u32`, `bool`) for FFI — their C ABI may differ on some platforms.
3. **Bool**: C `_Bool` (1 byte) and Rust `bool` (1 byte) are the same size but different ABI types. Use `libc::c_bool` for FFI.
4. **Padding**: check that Rust `#[repr(C)]` padding matches the target platform's C padding. When in doubt, add explicit padding fields: `_pad: [u8; 3]`.
5. Cross-reference with Angle 8 (Supply Chain & FFI): Angle 8 owns the C-side contract audit; Angle 1 owns the Rust-side UB from layout mismatch.

**Golden signature**: Manual comparison of Rust and C struct definitions. No mechanical tool — the failure is C writing to wrong Rust offset → logic error, not crash.

**Source**: Rust FFI documentation [model-knowledge]; C ABI specs per platform [model-knowledge].

---

### CHECK 12 — Unwinding through FFI boundary (A12)

**Signal**: `extern "C" fn` that may panic (directly or transitively) without `catch_unwind` wrapper.

**Procedure**:
1. For every `extern "C" fn` defined in Rust (called FROM C):
   a. Does it call (directly or transitively) any Rust function that could panic?
   b. If yes: is the body wrapped in `std::panic::catch_unwind(AssertUnwindSafe(|| { ... }))`?
   c. If NOT wrapped → UB when C calls this function and a panic occurs. The fix: wrap in `catch_unwind`, convert panic to error code.
2. **Callback case**: C function calls Rust callback; callback panics. The callback signature must include `catch_unwind`. If the callback is `extern "C"` and doesn't catch → UB.
3. **`extern "C-unwind"`** (stabilized Rust 2024): this ABI ALLOWS unwinding through C frames. If the codebase uses it, panics through FFI are safe. Check for `#![feature(c_unwind)]` or `extern "C-unwind"` usage — if present, CHECK 12 is N/A for those functions.

**Golden signature**: Write a test that panics inside the `extern "C"` function; observe crash/corruption. No mechanical tool — this is a code-pattern audit.

**Source**: Rust FFI unwinding documentation [model-knowledge]; `extern "C-unwind"` RFC [model-knowledge].

---

### CHECK 13 — Deserialization layout unsoundness: ZST / length (A10)

**Signal**: a `Deserialize`/decode impl for a custom container, especially one handling zero-sized types, flexible-array members, or a length header.

**Procedure**:
1. **ZST handling**: for every count-driven element loop, ask what `size_of::<T>() == 0` does. A deserializer that produces N copies of a non-`Copy`/`Clone` ZST can create invalid references that segfault on access (borsh — Solana/NEAR serialization).
2. **Header/length cross-check**: confirm a decoded length is validated against the *remaining* buffer, not just non-zero, before any `unsafe` write (cross-references CHECK 4 step 3; vmm-sys-util header-vs-flexible-array mismatch).
3. Confirm the rejecting check runs *before* the `unsafe` write, not after.

**Golden signature**: Miri on the decode of a crafted buffer (`reading from uninitialized memory` / freed-allocation); a fuzz/property harness over the decode path with ZST and adversarial-length inputs.

**Coordination**: Angle 8 (Supply Chain & FFI) owns the deserializer's external-contract audit; Angle 1 owns the Rust-side UB from ZST/length layout. Cross-reference both.

**Severity**: Critical if the decode path is reachable from untrusted input (consensus, p2p, RPC). High if behind authenticated paths.

**Source**: `borsh` non-Copy ZST invalid references — RUSTSEC-2023-0033; `vmm-sys-util` length mismatch — RUSTSEC-2024-0002. See `memory-safety-research.md` §A10.

---

## Phase 4: Cross-model verification

For every `unsafe` block flagged in CHECK 0, run Miri under ALL applicable backends:

```bash
# 1. Default Stacked Borrows (current model)
cargo miri test

# 2. Tree Borrows (stricter upcoming model — catches more aliasing UB)
MIRIFLAGS="-Zmiri-tree-borrows" cargo miri test

# 3. Raw-pointer provenance tracking
MIRIFLAGS="-Zmiri-tag-raw-pointers" cargo miri test

# 4. Data-race detection (for unsafe blocks dealing with Send/Sync)
MIRIFLAGS="-Zmiri-detect-data-races" cargo miri test

# 5. AddressSanitizer (for FFI code — catches heap UAF/OOB not in pure Rust)
RUSTFLAGS="-Zsanitizer=address" cargo +nightly test
```

A pass under Step 1 but UB under Steps 2-3 → STILL A BUG. Fix for the strictest model that fires. Document which model caught what.

---

## Stage-3 PoC discipline

Every FINDING in this angle MUST propose a Miri-runnable test case:

| Class | Backend | Command |
|-------|---------|---------|
| A01 (alignment) | Miri | `cargo miri test test_align_<ID>` |
| A02 (UAF) | Miri | `cargo miri test test_uaf_<ID>` |
| A03 (double-free) | Miri | `cargo miri test test_df_<ID>` |
| A04 (OOB) | Miri or ASan | `cargo miri test test_oob_<ID>` |
| A05 (uninit) | Miri | `cargo miri test test_uninit_<ID>` |
| A06 (provenance) | Miri `-Zmiri-tag-raw-pointers` | `MIRIFLAGS="-Zmiri-tag-raw-pointers" cargo miri test test_prov_<ID>` |
| A07 (aliasing) | Miri + Tree Borrows | `MIRIFLAGS="-Zmiri-tree-borrows" cargo miri test test_alias_<ID>` |
| A08 (transmute) | Compile-time or Miri | `cargo miri test test_transmute_<ID>` |
| A09 (union) | Miri nightly | `cargo +nightly miri test test_union_<ID>` |
| A10 (drop panic) | Unit test | `cargo test test_drop_panic_<ID>` |
| A11 (FFI layout) | Manual comparison | Side-by-side Rust vs C struct audit |
| A12 (FFI unwind) | Manual audit | `extern "C"` panic trace |
| A10 (deser ZST/length) | Miri or fuzz | `cargo miri test test_deser_<ID>` over a crafted ZST/adversarial-length buffer |

**Tier-1-formal**: Miri returns the cited Golden Signature. Without it: max CONTESTED per shared-rules.md. Tier-4-derivation (English-only) is forbidden in infra mode for Group A vectors — Miri is the cheapest verification on the planet for this class.

## Output fields beyond shared FINDING schema

```yaml
unsafe_block_location: <file:line of the unsafe { ... } block>
safety_comment: <the claimed invariant, or "none provided">
violated_invariant: <which element of the safety contract fails>
memory_model: StackedBorrows | TreeBorrows | Both
miri_command: <exact Miri invocation that triggers the UB>
miri_expected_output: <Golden Signature substring from the matched Group A vector>
miri_actual_output: <captured output, or "not yet run">
provenance_claim: <what the dev assumes about pointer/reference lifetimes>
```

## Anti-patterns (do NOT report)

- `unsafe` block that is provably sound by a verified safety invariant (every element of `// SAFETY:` holds).
- UB only reachable in test code (Stage-1 `reachability_check` classifies these as test-only).
- Performance-motivated `unsafe` (e.g., `unsafe { core::hint::unreachable_unchecked() }` after an exhaustive match) — unless the `unreachable_unchecked` is wrong.
- Clippy lints without a demonstrated UB path — lint presence is a signal, not a finding.
- Safe-code-only functions with no `unsafe` blocks AND no FFI boundary — the borrow checker guarantees memory safety; logic bugs belong to Angle 7.

## Coordination with other angles

- **Unsafe Trait Soundness (Angle 2)** owns `unsafe impl Send/Sync` soundness. When UB fires from Angle 1's CHECK 7 in code guarded by an `unsafe impl`, cross-reference: Angle 2 determines whether the impl is wrong; Angle 1 determines the UB mechanism.
- **Concurrency (Angle 4)** owns Loom-verifiable schedule bugs. Miri's race detector (CHECK 0 Step 4) catches the obvious races; Loom catches schedule-dependent races.
- **Supply Chain & FFI (Angle 8)** owns the C-side contract for FFI boundaries (H02, H03). Angle 1 owns the Rust-side UB (CHECKs 11, 12).
- **ZK Circuit Soundness (Angle 9)** — memory safety bugs in ZK proving/verification code (circuit witness generation, proof serialization) belong to Angle 1, not Angle 9.
