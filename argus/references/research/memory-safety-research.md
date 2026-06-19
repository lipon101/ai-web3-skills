# Memory Safety & Provenance — Research Dossier

> **Feeds**: `hacking-agents/infra/memory-safety-agent.md`
> **Last research pass**: 2026-06-05 · **Sources reviewed**: 14 primary advisories fetched + 2 cross-language analogies (labeled)
> **Status**: drafted-verified
>
> **Verification discipline**: Every RUSTSEC/CVE id below was fetched from its primary advisory page (URLs in section 7) and confirmed for BOTH identifier AND mechanism. Anything not confirmable to a primary source is labeled `[generic pattern — no specific incident]` and carries NO id. Cross-language (C) precedents are labeled `(C)`.

> **Prior-draft corrections folded in (do NOT reintroduce)**:
> - The "Substrate `memory_units` / `Vec::from_raw_parts` / CVE-2022-31094" story was FABRICATED. CVE-2022-31094 is a ScratchTools browser-extension stored-XSS (GHSA-6r45-jjw6-q39x). Removed entirely.
> - CVE-2021-38194 is a ZK under-constraint soundness bug (arkworks `mul_by_inverse`, RUSTSEC-2021-0075), NOT a memory-safety panic. Removed as memory-safety anchor.
> - CVE-2022-23639 / RUSTSEC-2022-0041 (crossbeam-utils) is an ALIGNMENT bug, NOT a Stacked-Borrows aliasing bug. Used below as the alignment anchor only.
> - Heartbleed (CVE-2014-0160) is OpenSSL C. Used ONLY as a clearly-labeled cross-language analogy, never as a Rust anchor.

---

## 0. Calibration headline

Rust's borrow checker eliminates use-after-free, double-free, and data races in *safe* code at compile time. Every advisory in section 7 lives in one of three residual zones — and the empirical lesson from the RustSec memory-corruption category is that **most of these bugs surface through a *safe* public API**: the `unsafe` is buried in the crate, and a caller writing ordinary safe Rust triggers the UB. The audit target is therefore not "find the `unsafe` block" but "find the safe API whose soundness depends on an `unsafe` invariant the caller can violate."

1. **`unsafe` blocks whose safety contract is violated by a reachable safe API.** The crate author wrote `unsafe` assuming an invariant (a length matches, a lifetime is bounded, a pointer is unique). A safe caller breaks the invariant. Confirmed instances: `smallvec::insert_many` trusts a `size_hint` lower bound and writes past the buffer (RUSTSEC-2021-0003); `bytes::BytesMut::reserve` does unchecked `new_cap + offset` arithmetic and hands a corrupted capacity to safe `spare_capacity_mut()` (RUSTSEC-2026-0007); `vmm-sys-util::FamStructWrapper::deserialize` never checks that the header length matches the flexible-array length (RUSTSEC-2024-0002).

2. **Lifetime / aliasing unsoundness in container & iterator APIs.** A reference or iterator outlives the allocation it points into, or two references alias the same memory mutably. Confirmed: `lru`'s `iter`/`iter_mut` hand out references that `pop()` can free (UAF, RUSTSEC-2021-0130); `lru::IterMut::next` creates an exclusive reference to a node key while the `HashMap` still holds a shared pointer to it (Stacked Borrows violation, RUSTSEC-2026-0002); `bumpalo`'s `Vec::into_iter()` iterator is not lifetime-bound to its `Bump`, so it can be used after the arena drops (UAF, RUSTSEC-2022-0078); `secp256k1::preallocated_gen_new` had incorrect lifetime bounds letting the context outlive its backing buffer (UAF, RUSTSEC-2022-0070).

3. **FFI / layout / transmute unsoundness at the C boundary or via type punning.** Panics unwinding into C, `#[repr(packed)]` field-order assumptions, and `transmute` onto uninitialized or wrong-layout memory. Confirmed: `libpulse-binding` callbacks let Rust panics unwind through C frames (RUSTSEC-2019-0038); `zerovec-derive` assumed `#[repr(packed)]` guarantees field order — Rust 1.80 began reordering and broke it (RUSTSEC-2024-0346); `ouch`'s `convert_zip_date_time` `transmute`s a value so its address points into uninitialized memory → segfault (RUSTSEC-2024-0374).

**Pointer provenance / aliasing model.** Two models govern UB detection in Miri: **Stacked Borrows** (current default) and **Tree Borrows** (stricter, catches a superset). RUSTSEC-2026-0002 (lru `IterMut`) is a *real, advisory-grade* Stacked-Borrows violation — the canonical anchor for this class. Every `unsafe` block that re-derives a `&mut` from a raw pointer while another reference is live is a candidate; run Miri under both models.

**DLT relevance is direct.** `secp256k1` is the ECDSA backbone of Bitcoin and Ethereum (RUSTSEC-2022-0070). `borsh` is the canonical Solana/NEAR serialization format and mis-handles zero-sized types → segfault (RUSTSEC-2023-0033). `bytes` underlies the networking stack of essentially every Rust node client (RUSTSEC-2026-0007). `vmm-sys-util` underlies VM-monitor / enclave infra (RUSTSEC-2024-0002). These are not toy crates.

**Cross-language anchors (analogy only, never a Rust id):** Heartbleed (CVE-2014-0160, OpenSSL C) is the canonical "trust an untrusted length field and read past the buffer" pattern; the Rust analogue is any custom Borsh/serde deserializer that trusts a length prefix — see RUSTSEC-2024-0002 and RUSTSEC-2023-0033 for the *Rust* instances. CVE-2024-24576 ("BatBadBut", Rust std `Command` batch-file arg escaping) is a real maximum-severity Rust-std CVE but is a command-injection/escaping bug, **not** memory-safety UB — do not list it as a memory-safety anchor.

---

## 1. Bug-class taxonomy

| Class | One-line mechanism | Real instance (verified source) | Argus coverage |
|-------|--------------------|---------------------------------|----------------|
| **A01 Alignment / layout assumption** | Code assumes an alignment or field order that the target / compiler does not guarantee → unaligned access or wrong-offset access | crossbeam-utils `AtomicCell<u64>`: `align_of::<u64>() < align_of::<AtomicU64>()` on 32-bit → unaligned access + data race (RUSTSEC-2022-0041); zerovec-derive assumed `#[repr(packed)]` field order, broken by rustc 1.80 reordering (RUSTSEC-2024-0346) | **PARTIAL** — agent mentions alignment in transmute context; no systematic alignment/layout-assumption procedure |
| **A02 Use-after-free (lifetime / iterator)** | A reference or iterator outlives the allocation it points into | lru `iter`/`iter_mut` reference freed by `pop()` (RUSTSEC-2021-0130); bumpalo `Vec::into_iter()` not bound to `Bump` lifetime (RUSTSEC-2022-0078); secp256k1 `preallocated_gen_new` incorrect lifetime bound (RUSTSEC-2022-0070) | **PARTIAL** — `drop_in_place` mentioned; no iterator/lifetime-escape UAF procedure |
| **A03 Double-free / drop unsoundness** | Same allocation freed twice, often via wrong type on downcast or panic-during-drop | (Rust) covered by the lifetime-bound UAF class above; panic-in-drop double-free is `[generic pattern — no specific incident]` in this pass | **PARTIAL** — in anti-patterns; no detection procedure |
| **A04 Out-of-bounds write/read** | Unchecked index / length / arithmetic lets a write or read cross the allocation boundary | grcov `get_coverage` uses `get_unchecked_mut` without a bounds check → OOB write (RUSTSEC-2025-0005); vmm-sys-util `FamStructWrapper::deserialize` header-vs-array length unchecked (RUSTSEC-2024-0002); smallvec `insert_many` trusts `size_hint` lower bound, writes past buffer (RUSTSEC-2021-0003); bytes `BytesMut::reserve` `new_cap + offset` overflow → corrupted capacity → OOB slice (RUSTSEC-2026-0007) | **NO** — agent mentions pointer arithmetic past bounds; no length-prefix / size_hint / overflow-to-OOB procedure |
| **A05 Uninitialized memory read / drop** | Memory read or dropped before it is written | ouch `convert_zip_date_time` `transmute` repositions value onto uninitialized region → segfault (RUSTSEC-2024-0374); memoffset `offset_of` dereferenced uninitialized / address-0 data (RUSTSEC-2023-0045) | **PARTIAL** — single sentence; no per-`assume_init` / per-`transmute` audit |
| **A06 Invalid pointer provenance** | Pointer from integer or carried across realloc has no/stale provenance | `[generic pattern — no specific incident in this pass]` — the closest *verified* primary is the aliasing/Stacked-Borrows class (A07); provenance-from-integer had no confirmable RustSec anchor this pass | **NO** — provenance concept absent |
| **A07 Stacked / Tree Borrows aliasing violation** | `&mut` created while a `&` (or raw ptr derived from `&`) to the same memory is live | lru `IterMut::next`/`next_back` create an exclusive ref to a node key while the `HashMap` still holds a shared pointer (RUSTSEC-2026-0002) — **the real Stacked-Borrows anchor** | **NO** — aliasing model not mentioned |
| **A08 Transmute / type-punning unsoundness** | `transmute` (or a transmute-equivalent) onto wrong-size, wrong-layout, or invalid-bit-pattern memory | ouch transmute-to-uninit (RUSTSEC-2024-0374); zerovec-derive repr(packed) layout punning (RUSTSEC-2024-0346); `totally-safe-transmute` achieves transmute from *safe* Rust via `/proc/self/mem` (RUSTSEC-2025-0030 — **PoC/toy crate, soundness demo, not a production bug**) | **PARTIAL** — mentioned in "How to attack"; no per-transmute procedure |
| **A09 FFI panic / unwinding across boundary** | A Rust panic unwinds through a C frame (or vice versa) → UB | libpulse-binding callbacks failed to `catch_unwind` panics crossing into C (RUSTSEC-2019-0038) | **NO** — not covered |
| **A10 Deserialization layout unsoundness (ZST / length)** | Deserializing untrusted bytes produces invalid references or wrong counts | borsh creates invalid references when deserializing non-Copy/Clone ZSTs (e.g. 1000 ZST instances → segfault on access) (RUSTSEC-2023-0033); vmm-sys-util length mismatch (RUSTSEC-2024-0002) | **NO** — split between this angle and the supply-chain/FFI angle; needs coordination |

---

## 2. Per-class methodology

> Methodology = a systematic procedure that finds the bug **without already knowing the answer**. Patterns ("look for exactly this") belong in RAG, not here.

### A01 — Alignment / layout assumption

- **Signal**: `ptr::read`/`ptr::write` on a pointer that may be misaligned; `#[repr(packed)]` field access; any `align_of`/`size_of`-based assumption that one type's alignment matches another's; atomic types on 32-bit targets.
- **Procedure**:
  1. For every `#[repr(packed)]` struct, confirm `#[repr(C, packed)]` (explicit field order) is used — bare `#[repr(packed)]` does NOT guarantee field order and was reordered by rustc 1.80 (RUSTSEC-2024-0346). Then confirm field reads use `addr_of!(...).read_unaligned()`, never `&packed.field`.
  2. For every "alignment of A equals alignment of B" assumption (especially `{i,u}64` vs `Atomic{I,U}64`), check the *smallest* supported target: on 32-bit, `align_of::<u64>()` can be 4 while `align_of::<AtomicU64>()` is 8 (RUSTSEC-2022-0041). Verify the code does not place a 64-bit atomic at an only-4-aligned offset.
  3. For `transmute::<[u8; N], T>()` / `bytemuck`-style casts: confirm the byte source is aligned to `align_of::<T>()`.
- **Mechanical evidence**: `cargo miri test` (alignment errors); cross-compile and run the test suite for a 32-bit target (`i686-unknown-linux-gnu`).
- **Anti-pattern**: alignment that *happens* to be satisfied on x86-64 but not on the smallest supported target — must test the worst target, not the dev machine.
- **Source**: RUSTSEC-2022-0041, RUSTSEC-2024-0346.

### A02 — Use-after-free (lifetime / iterator escape)

- **Signal**: an iterator or reference whose type lacks a lifetime parameter tying it to its backing store; `iter`/`iter_mut`/`into_iter` on a custom container; a constructor that takes `&mut buf` and returns a value holding that reference.
- **Procedure**:
  1. For every public method returning a reference or iterator, ask: *is the returned type's lifetime bounded to the allocation/owner?* If the return type has NO lifetime parameter (e.g. an `IntoIter` with no `'a`), the iterator can outlive the store → UAF (bumpalo `Vec::into_iter()`, RUSTSEC-2022-0078).
  2. For every `iter`/`iter_mut` that hands out references into nodes, enumerate which *other* methods can free those nodes while the iterator is live (`pop`, `remove`, `clear`). If any can, the references dangle (lru, RUSTSEC-2021-0130).
  3. For every constructor of the shape `fn new(buf: &mut T) -> Ctx`: confirm `Ctx`'s lifetime is bounded by `buf`'s, and that `Ctx`'s `Drop` does not free `buf` when `Ctx` was built from a borrow (secp256k1 `preallocated_gen_new`, RUSTSEC-2022-0070).
- **Mechanical evidence**: write a Miri test that (a) gets the iterator/ref, (b) performs the freeing op or drops the owner, (c) accesses the iterator/ref. Miri: `pointer to allocation was deallocated`.
- **Anti-pattern**: a reference that *looks* unbounded but is actually constrained by an elided lifetime the compiler already enforces — confirm the elision actually ties it, don't assume.
- **Source**: RUSTSEC-2021-0130, RUSTSEC-2022-0078, RUSTSEC-2022-0070.

### A04 — Out-of-bounds write/read

- **Signal**: `get_unchecked`/`get_unchecked_mut`; `ptr.add`/`copy_nonoverlapping`/`set_len`; a length or count read from input; `size_hint`-driven allocation; `a + b` capacity arithmetic without `checked_add`.
- **Procedure**:
  1. **Unchecked index**: for every `get_unchecked[_mut](i)`, trace `i` to its source. If `i` can derive from untrusted input without a prior `i < len` check on the *same* buffer → OOB (grcov, RUSTSEC-2025-0005).
  2. **Length-prefix trust** (the Rust Heartbleed (C) analogue): for `let n = decode_len(buf); read n bytes` — confirm `n` is validated against *remaining* buffer size, not just non-zero. A header field that is trusted to match a flexible-array length without a cross-check is OOB (vmm-sys-util, RUSTSEC-2024-0002).
  3. **`size_hint` trust**: for any allocation sized from `iter.size_hint().0` (the *lower* bound) followed by unchecked writes per item, confirm the buffer is grown per-item, not pre-sized to the hint — a lying `size_hint` overflows the buffer (smallvec `insert_many`, RUSTSEC-2021-0003).
  4. **Capacity arithmetic overflow**: for every `cap_check = a + b` (`new_cap + offset`, `len + additional`) used to gate an `unsafe` write, confirm `checked_add`/`saturating_add` in release builds — unchecked `usize` overflow makes the gate pass and corrupts capacity (bytes `BytesMut::reserve`, RUSTSEC-2026-0007).
- **Mechanical evidence**: Miri (`dereferencing pointer ... past the end of allocation`); ASan (`RUSTFLAGS="-Zsanitizer=address"`) for heap OOB; a fuzz harness feeding adversarial lengths / size_hints.
- **Anti-pattern**: a bound that is checked in debug (`debug_assert!`, implicit `[]` panic) but elided in the `unsafe` release path — the release path is the audit target.
- **Source**: RUSTSEC-2025-0005, RUSTSEC-2024-0002, RUSTSEC-2021-0003, RUSTSEC-2026-0007.

### A05 — Uninitialized memory read / drop

- **Signal**: `MaybeUninit::assume_init`, `mem::uninitialized` (deprecated), `transmute` whose result is read before write, `offset_of`-style field projection through a fake/uninit base, `set_len` growing past initialized length.
- **Procedure**:
  1. For every `assume_init()`, confirm an unconditional prior write to the *same* `MaybeUninit`. Conditional/partial init → candidate.
  2. For every `transmute` that *moves* a value, confirm the destination type's invariants hold for the source bytes AND that no temporary repositions the value onto uninitialized stack (ouch `convert_zip_date_time` segfault, RUSTSEC-2024-0374).
  3. For offset/field-projection helpers, confirm they use `ptr::addr_of!` (computes address without dereferencing), not a dereference of an uninitialized or address-0 base (memoffset pre-fix used `mem::uninitialized` then projected → UB, RUSTSEC-2023-0045).
- **Mechanical evidence**: Miri (`reading from uninitialized memory`). Note Miri is nondeterministic-tolerant: run repeatedly.
- **Anti-pattern**: reading initialized *padding* bytes of a `#[repr(C)]` struct — not UB by itself, but a data-leak if serialized; classify as info, not UB.
- **Source**: RUSTSEC-2024-0374, RUSTSEC-2023-0045.

### A07 — Stacked / Tree Borrows aliasing violation

- **Signal**: an `unsafe` block that re-derives `&mut T` from a raw pointer (`&mut *p`) while another reference or raw pointer to the same/overlapping memory is live; an iterator that materializes `&mut` to data a parallel structure also references.
- **Procedure**:
  1. For each such `&mut` re-derivation, identify *every other* live reference/pointer to that memory at that program point. If a shared `&`/`*const` to the same location is live, the `&mut` is a Stacked Borrows violation (lru `IterMut::next` dereferences an internal node pointer to make a `&mut key` while the `HashMap` still holds a shared pointer to that key — RUSTSEC-2026-0002).
  2. Confirm shared-mutable access goes through `UnsafeCell` — it is the only legal route; a bare `&mut` while `&` is live is UB regardless of runtime behavior.
  3. Run Miri under BOTH models — Tree Borrows catches a superset:
     - `cargo miri test`
     - `MIRIFLAGS="-Zmiri-tree-borrows" cargo miri test`
- **Mechanical evidence**: Miri (`attempting a write access using <TAG> but the tag <OTHER> is also live` / Tree Borrows `... is forbidden`).
- **Anti-pattern**: code that *looks* like aliasing but routes through `UnsafeCell`/`Cell`/atomics — legal; confirm the cell before flagging.
- **Source**: RUSTSEC-2026-0002.

### A08 — Transmute / type-punning unsoundness

- **Signal**: any `mem::transmute`, `transmute_copy`, byte-cast onto a typed view, or "safe transmute" that bypasses the type system.
- **Procedure**:
  1. For every `transmute::<A, B>()`: `size_of::<A>() == size_of::<B>()` AND `align_of::<A>() >= align_of::<B>()` (compile-time assert), AND every bit pattern of A is valid for B (no invalid `bool`/`enum`/`NonZero` discriminants).
  2. Reference-type transmutes (`&'a T → &'static T`) are lifetime laundering → treat as A02 UAF.
  3. Layout punning across `#[repr(packed)]` / `#[repr(C)]` boundaries: see A01.
  4. Note the limit: type safety can be subverted from *safe* Rust on Linux via `/proc/self/mem` (RUSTSEC-2025-0030, `totally-safe-transmute` — a deliberate toy/PoC, "should never be used", soundness demo per rust-lang/rust#32670, **not** a production-bug pattern). Flag any dependency on `/proc/self/mem`-style self-modification as a soundness red flag, but do not cite it as an exploitable production finding.
- **Mechanical evidence**: prefer `bytemuck`/`zerocopy` safe wrappers (they encode these checks); Miri for invalid-value transmutes.
- **Anti-pattern**: a `transmute` already replaced by `bytemuck::cast`/`.to_ne_bytes()` — not a finding.
- **Source**: RUSTSEC-2024-0374, RUSTSEC-2024-0346, RUSTSEC-2025-0030.

### A09 — FFI panic / unwinding across boundary

- **Signal**: an `extern "C"` Rust function invoked as a C callback; any Rust closure handed to a C library as a function pointer.
- **Procedure**:
  1. For every Rust function reachable from C (callbacks especially), confirm the body is wrapped in `std::panic::catch_unwind` and converts the panic to an error code/abort — an uncaught panic unwinding into a C frame is UB (libpulse-binding, RUSTSEC-2019-0038).
  2. Check whether the boundary uses `extern "C-unwind"` (stabilized 2024) — if so, unwinding is defined; if plain `extern "C"`, it is not.
- **Mechanical evidence**: no single tool — a code-pattern audit; the test is to feed an input that panics inside the callback and observe abort/UB.
- **Anti-pattern**: an `extern "C"` function whose body is provably panic-free (no indexing, no `unwrap`, no allocation) — lower priority, but document the reasoning.
- **Source**: RUSTSEC-2019-0038.

### A10 — Deserialization layout unsoundness (ZST / length)

- **Signal**: a `Deserialize`/decode impl for a custom container, especially one handling zero-sized types, flexible-array members, or a length header.
- **Procedure**:
  1. **ZST handling**: confirm the deserializer treats N copies of a non-`Copy`/`Clone` ZST correctly — borsh produced invalid references that segfaulted on access when 1000 non-Copy ZSTs were deserialized (RUSTSEC-2023-0033). For every count-driven element loop, ask what `size_of::<T>() == 0` does.
  2. **Header/length cross-check**: see A04 step 2 (vmm-sys-util, RUSTSEC-2024-0002).
- **Mechanical evidence**: a fuzz/property harness over the decode path with ZST and adversarial-length inputs; Miri on the decode of a crafted buffer.
- **Anti-pattern**: a decoder that already rejects unknown/oversized lengths up front — confirm the check is before the `unsafe` write, not after.
- **Source**: RUSTSEC-2023-0033, RUSTSEC-2024-0002.

---

## 3. Framework-specific knowledge

- **Stacked Borrows vs Tree Borrows**: Miri's default is Stacked Borrows; Tree Borrows (`-Zmiri-tree-borrows`) is stricter and catches a superset. A real advisory-grade Stacked-Borrows bug exists in the wild (lru `IterMut`, RUSTSEC-2026-0002) — this class is not theoretical.
- **`#[repr(packed)]` does not guarantee field order.** Only `#[repr(C, packed)]` does. rustc 1.80 began reordering bare-`packed` fields and broke real crates (zerovec-derive, RUSTSEC-2024-0346). Any unsafe access keyed on packed field offsets is a candidate.
- **32-bit alignment surprises.** `align_of::<u64>()` can be 4 on 32-bit while `align_of::<AtomicU64>()` is 8 (crossbeam-utils, RUSTSEC-2022-0041). Never assume primitive and atomic alignments match; test the smallest target.
- **DLT-relevant primitives that have had real memory-safety advisories**: `secp256k1` (Bitcoin/Ethereum ECDSA, RUSTSEC-2022-0070), `borsh` (Solana/NEAR serialization, RUSTSEC-2023-0033), `bytes` (node networking buffers, RUSTSEC-2026-0007). When these appear in a target's dependency tree, pin versions against `cargo audit`.
- **`/proc/self/mem` defeats the type system from safe Rust** (rust-lang/rust#32670, demonstrated by `totally-safe-transmute`, RUSTSEC-2025-0030). It is a known, wontfix soundness hole — relevant as a red flag, not as a finding generator.
- **Cross-language footgun (C)**: the Heartbleed (CVE-2014-0160) "trust the length field" pattern recurs in Rust deserializers (the *Rust* instances are RUSTSEC-2024-0002 and RUSTSEC-2023-0033).

---

## 4. Tooling landscape

| Tool | What it finds | Readiness | Invoke |
|------|---------------|-----------|--------|
| **Miri (Stacked Borrows, default)** | UAF, double-free, OOB, uninit read, alignment, aliasing | HIGH (nightly component) | `cargo +nightly miri test` |
| **Miri (`-Zmiri-tree-borrows`)** | Stricter aliasing — superset of Stacked Borrows | MEDIUM (experimental, real bugs found) | `MIRIFLAGS="-Zmiri-tree-borrows" cargo +nightly miri test` |
| **Kani** | Bounded proof of safety invariants for bounded inputs | HIGH (AWS/Firecracker) | `cargo kani` + `#[kani::proof]` |
| **AddressSanitizer** | Heap/stack OOB, UAF at runtime (incl. FFI/C) | HIGH | `RUSTFLAGS="-Zsanitizer=address" cargo +nightly test` |
| **cargo-audit** | Dependency versions matching RustSec advisories (all ids in §7) | HIGH | `cargo audit` |
| **cargo-geiger** | Unsafe footprint per crate (signal, not proof) | MEDIUM | `cargo geiger` |
| **Clippy unsafe lints** | `missing_safety_doc`, `undocumented_unsafe_blocks`, transmute lints | HIGH | `cargo clippy -- -W clippy::undocumented_unsafe_blocks` |
| **bytemuck / zerocopy** | Safe transmute wrappers encoding size/align/validity checks (refactor target, not a scanner) | HIGH | replace raw `transmute` |
| **32-bit cross-test** | Surfaces alignment-assumption bugs (A01) | HIGH | `cargo test --target i686-unknown-linux-gnu` |

The first audit action on any `unsafe`-bearing target is `cargo audit` — it mechanically catches every advisory in §7 if the vulnerable version is present, before any manual review.

---

## 5. Discovery calibration

- **Most of these bugs are reachable from a *safe* API** (smallvec, bytes, vmm-sys-util, lru, bumpalo, borsh). Directing the agent to "audit `unsafe` blocks" alone misses them. The high-yield prompt is: *"for each public safe API, what `unsafe` invariant does its soundness depend on, and can a caller violate it?"*
- **Miri is the ground-truth backend** for A02/A04/A05/A07. A finding without a Miri (or ASan/Kani) repro is a hypothesis, not a confirmed UB. The PoC shape is a `#[test]` that performs the violating sequence and is run under Miri.
- **Run both borrow models.** Tree Borrows fired on real code (RUSTSEC-2026-0002 class); a Stacked-Borrows-clean result is not a clean bill.
- **Test the worst target, not the dev machine.** A01 bugs (RUSTSEC-2022-0041) are invisible on x86-64.

---

## 6. Gaps → angle changes

| Gap ID | Missing in current agent | Severity | Proposal (change type) | Anti-bloat check |
|--------|--------------------------|----------|------------------------|------------------|
| **G-01** | No "safe-API-over-unsafe-invariant" framing — the dominant real pattern | CRITICAL | Add CHECK 0: for each public safe API, enumerate the `unsafe` invariant its soundness rests on and whether a caller can break it | New framing; no existing CHECK covers it |
| **G-02** | No iterator/lifetime-escape UAF procedure (A02) | HIGH | Add CHECK: return-type-lifetime-bounding audit for `iter`/`into_iter`/borrow-taking constructors | extends existing `drop_in_place` mention |
| **G-03** | No length-prefix / size_hint / capacity-overflow OOB procedure (A04) | HIGH | Add CHECK: untrusted-length and unchecked-capacity-arithmetic audit (the Rust Heartbleed-analogue) | new; current agent only says "past bounds" |
| **G-04** | No real Stacked/Tree Borrows model or anchor (A07) | HIGH | Add CHECK + run Miri under both models; anchor on RUSTSEC-2026-0002 | new; replaces fabricated crossbeam-aliasing claim |
| **G-05** | No `#[repr(packed)]` field-order / 32-bit alignment procedure (A01) | MEDIUM | Add CHECK: `repr(C, packed)` confirmation + smallest-target alignment test | extends transmute alignment mention |
| **G-06** | No FFI-panic / `catch_unwind` boundary check (A09) | MEDIUM | Add CHECK: every C-reachable Rust fn wrapped in `catch_unwind` or `extern "C-unwind"` | coordinate with supply-chain/FFI angle |
| **G-07** | No ZST / deserialization-layout check (A10) | MEDIUM | Add CHECK: decode-path ZST + header-length audit | coordinate with supply-chain/FFI angle |
| **G-08** | No "run `cargo audit` first" pre-seed step | LOW | Add Phase 1 pre-seed: `cargo audit` + `cargo geiger` | trivially additive |

---

## 7. Sources

All URLs fetched 2026-06-05; each confirmed for both identifier AND mechanism before inclusion.

**Verified Rust advisories (anchors):**

1. RUSTSEC-2021-0130 — `lru` use-after-free: `iter`/`iter_mut` give references that `pop()` frees. https://rustsec.org/advisories/RUSTSEC-2021-0130.html
2. RUSTSEC-2026-0002 — `lru` Stacked Borrows: `IterMut::next`/`next_back` make an exclusive ref to a node key while `HashMap` holds a shared pointer. https://rustsec.org/advisories/RUSTSEC-2026-0002.html
3. RUSTSEC-2022-0078 — `bumpalo` UAF: `Vec::into_iter()` iterator not lifetime-bound to its `Bump`. https://rustsec.org/advisories/RUSTSEC-2022-0078.html
4. RUSTSEC-2022-0070 — `secp256k1` UAF: `preallocated_gen_new` incorrect lifetime bound lets context outlive its backing buffer (Bitcoin/Ethereum ECDSA). https://rustsec.org/advisories/RUSTSEC-2022-0070.html
5. RUSTSEC-2022-0041 — `crossbeam-utils` alignment: `align_of::<u64>() < align_of::<AtomicU64>()` on 32-bit → unaligned access + data race. https://rustsec.org/advisories/RUSTSEC-2022-0041.html
6. RUSTSEC-2024-0346 — `zerovec-derive` layout: assumed `#[repr(packed)]` field order; rustc 1.80 reordering → wrong-offset access. https://rustsec.org/advisories/RUSTSEC-2024-0346.html
7. RUSTSEC-2025-0005 — `grcov` OOB write: `get_unchecked_mut` without bounds check on crafted coverage data. https://rustsec.org/advisories/RUSTSEC-2025-0005.html
8. RUSTSEC-2024-0002 — `vmm-sys-util` OOB: `FamStructWrapper::deserialize` header-vs-flexible-array length unchecked. https://rustsec.org/advisories/RUSTSEC-2024-0002.html
9. RUSTSEC-2021-0003 — `smallvec` buffer overflow: `insert_many` trusts iterator `size_hint` lower bound, writes past buffer. https://rustsec.org/advisories/RUSTSEC-2021-0003.html
10. RUSTSEC-2026-0007 — `bytes` integer overflow: `BytesMut::reserve` `new_cap + offset` overflow → corrupted capacity → OOB slice via safe `spare_capacity_mut()`. https://rustsec.org/advisories/RUSTSEC-2026-0007.html
11. RUSTSEC-2024-0374 — `ouch` uninitialized memory: `convert_zip_date_time` `transmute` repositions value onto uninitialized region → segfault. https://rustsec.org/advisories/RUSTSEC-2024-0374.html
12. RUSTSEC-2023-0045 — `memoffset` uninitialized read: `offset_of` dereferenced uninitialized/address-0 data; fixed by `ptr::addr_of`. https://rustsec.org/advisories/RUSTSEC-2023-0045.html
13. RUSTSEC-2019-0038 — `libpulse-binding` FFI unwinding: callbacks failed to `catch_unwind` panics crossing into C. https://rustsec.org/advisories/RUSTSEC-2019-0038.html
14. RUSTSEC-2023-0033 — `borsh` ZST unsoundness: deserializing non-Copy/Clone zero-sized types creates invalid references → segfault on access (Solana/NEAR serialization). https://rustsec.org/advisories/RUSTSEC-2023-0033.html

**Soundness demonstration (PoC/toy, NOT a production bug — labeled in-text):**

15. RUSTSEC-2025-0030 — `totally-safe-transmute`: transmute from safe Rust via `/proc/self/mem` (rust-lang/rust#32670); explicitly "a toy, should never be used". https://rustsec.org/advisories/RUSTSEC-2025-0030.html

**Index source:**

16. RustSec memory-corruption category index (used to enumerate candidates). https://rustsec.org/categories/memory-corruption.html

**Cross-language analogies (C) — labeled, never used as Rust anchors:**

17. CVE-2014-0160 (Heartbleed, OpenSSL C) — trust-the-length-field over-read; Rust analogues are sources 8 and 14. https://nvd.nist.gov/vuln/detail/CVE-2014-0160
18. CVE-2024-24576 ("BatBadBut", Rust std `Command` batch-file arg escaping) — real maximum-severity Rust-std CVE but a command-injection/escaping bug, NOT memory-safety UB. Listed only to mark the boundary. https://blog.rust-lang.org/2024/04/09/cve-2024-24576/

---

> **AI-provenance reminder**: This dossier was assembled by an AI agent from primary advisory sources. Every retained CVE/RUSTSEC id was fetched and confirmed for both identifier and mechanism against the URL listed in section 7. Before any claim here is wired into angle methodology or cited in a finding, a human auditor MUST independently re-read the cited advisory and confirm the mechanism still matches the code under audit. AI output is a starting point for verification, not a substitute for it. Do not attach any id in this file to a new mechanism without re-fetching its primary source.
