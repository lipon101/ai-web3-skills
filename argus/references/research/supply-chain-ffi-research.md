# Supply Chain, FFI & Build Integrity — Research Dossier

> **Feeds**: `hacking-agents/infra/supply-chain-ffi-agent.md`
> **Last research pass**: 2026-06-05 · **Sources reviewed**: 11 primary advisories/incidents + 4 toolchain-semantics references — every retained identifier re-fetched this pass (id AND mechanism)
> **Status**: drafted-verified

> **Anchor case**: **RUSTSEC-2022-0042 — malicious crate `rustdecimal`** (typosquat of `rust_decimal`). The legitimate source was copied verbatim except for `Decimal::new`, which checked the `GITLAB_CI` environment variable and, when set, downloaded a binary into `/tmp/git-updater.bin` and executed it (payload supported Linux + macOS, not Windows; the download URL was already dead at analysis time). SentinelOne's "CrateDepression" analysis confirms the second-stage binaries were Go 1.17.8 unsigned **Poseidon** payloads (agents for the **Mythic** post-exploitation framework), that the crates.io / Rust Security Response WG found **15 iterative malicious versions** (1.22.0–1.23.5), and that the attacker used a fake "Paul Masen" identity mimicking the real `rust_decimal` author Paul Mason, targeting CI pipelines to seed downstream supply-chain attacks. The defining pattern: a name one keystroke from a popular crate, malice gated on a CI env var so it stays dormant on dev laptops, payload fetched at runtime not embedded. Sources: <https://rustsec.org/advisories/RUSTSEC-2022-0042.html>, <https://blog.rust-lang.org/2022/05/10/malicious-crate-rustdecimal/>, <https://www.sentinelone.com/labs/cratedepression-rust-supply-chain-attack-infects-cloud-ci-pipelines-with-go-malware/>.

> **Provenance discipline**: Every real-world identifier below was fetched from a primary source confirming BOTH the id AND the mechanism (section 7 lists URLs + access date). Classes with no confirmed incident are labelled `[generic pattern — no specific incident]` and carry NO id. Two prior-draft errors were verified WRONG this pass and are excluded: `CVE-2022-31094` is a **ScratchTools browser-extension XSS** (NVD: affects ScratchTools 2.4.0–<2.5.2, Recently-Viewed-Projects feature), never a Substrate `memory_units` WASM-DoS — the WASM-DoS anchor was FABRICATED. `RUSTSEC-2023-0071` is the **RSA-crate Marvin-attack timing side-channel (CVE-2023-49092)**, not shlex — the real shlex advisory is **RUSTSEC-2024-0006**. See section 7 "Dropped / corrected".

---

## 0. Calibration headline

Supply-chain and FFI bugs are the hardest class to find by reading `src/`: the vulnerability lives in code you DIDN'T write (a dependency), at a boundary where Rust's guarantees stop (FFI), or in code that runs BEFORE your audit begins (`build.rs`, proc macros). An auditor who reads only the project's own modules misses them entirely.

Four sub-classes dominate, each with a verified anchor:

1. **Malicious / known-vulnerable dependencies** — a crate name or version in `Cargo.lock`/`Cargo.toml` matches a RustSec advisory. Verified malicious instances: `rustdecimal` (RUSTSEC-2022-0042), `finch-rst` (RUSTSEC-2025-0150). Verified known-vulnerable instance with a reachable code path: `shlex` command/argument injection (RUSTSEC-2024-0006). `cargo audit` finds the match; the LLM determines reachability.
2. **FFI boundary unsoundness** — `extern "C"` signature / `#[repr(C)]` / null-pointer / raw-slice mismatch the compiler cannot verify. Verified anchors: glib's variadic-FFI null-pointer UB (RUSTSEC-2024-0429); xous's safe-wrapper-over-`from_raw_parts` type confusion (RUSTSEC-2024-0431).
3. **Unwinding across the FFI boundary** — a Rust panic crossing an `extern "C"` frame was historically UB; Rust 1.81 made non-unwind ABIs (incl. `"C"`) abort instead. Verified anchor: `rust-secp256k1` panicked across the boundary into `libsecp256k1` (issue #354, fix PR #358). Panic-safety bug that surfaces the same way: rkyv UAF on Drop-panic (RUSTSEC-2026-0122).
4. **Build-time / proc-macro execution** — `build.rs` and proc macros run arbitrary code at compile time. No clean *weaponized* malicious-proc-macro advisory was confirmable this pass (the `rustdecimal` payload triggers at runtime, not build time); the closest verified dependency-hygiene anchor is the unmaintained, widely transitively-pulled `proc-macro-error` (RUSTSEC-2024-0370). The compile-time arbitrary-execution capability itself is documented Cargo behavior; specific weaponization is `[generic pattern — no specific incident]`.

Tool coverage is GOOD for detection, weak for judgment. `cargo audit`/`cargo deny` emit advisory matches; the LLM decides which are reachable. `cargo geiger` flags unsafe density but not soundness. Clippy's `improper_ctypes` catches some ABI mismatches but not field-ordering or variadic-signature errors (the glib bug escaped compilation precisely because the C function was variadic).

---

## 1. Bug-class taxonomy

| Class | One-line mechanism | Real instance (verified source) | Argus coverage |
|-------|--------------------|---------------------------------|----------------|
| **H01 Malicious typosquatted crate** | Attacker publishes a crate one keystroke from a popular one; malicious code gated on a CI env var; payload fetched at runtime | **RUSTSEC-2022-0042** `rustdecimal` (typosquat of `rust_decimal`; `Decimal::new` checks `GITLAB_CI`, fetches `/tmp/git-updater.bin`) — "CrateDepression" by SentinelOne | YES — `cargo audit`/`cargo deny` name-match |
| **H02 Credential-exfiltration typosquat** | Typosquat steals local credential files instead of fetching a payload | **RUSTSEC-2025-0150** `finch-rst` (typosquat of `finch`; steals credentials from local files) | YES — `cargo audit` |
| **H03 Known-vulnerable dependency (reachable)** | Pinned version matches an advisory; vulnerable function reachable from audited code | **RUSTSEC-2024-0006** `shlex` <1.3.0 — `quote`/`join` leave `{`, `\xa0` (and, pre-1.3.0, nul + control chars) unescaped → argument/command injection (CVE-2024-58266, GHSA-r7qv-8r2h-pg27) | YES — `cargo audit` + reachability |
| **H04 FFI null-pointer / out-arg unsoundness** | A `&T` passed where the C function mutates the pointer in place; compiler optimizes away the unobserved write → null deref in `CStr::from_ptr` | **RUSTSEC-2024-0429** `glib` ≥0.15.0,<0.20.0 — variadic `g_variant_get_child` out-arg passed `&p` not `&mut p` (affects `VariantStrIter::next`/`next_back`/`nth`/`nth_back`/`last`; GHSA-wrw7-89jp-8q8g) | YES |
| **H05 Safe wrapper over raw-slice from C** | `as_slice`/`as_slice_mut` cast an arbitrary C pointer to `&[T]` without `unsafe`, no alignment/size/validity check → type confusion | **RUSTSEC-2024-0431** `xous` <0.9.51 — `MemoryRange::as_slice{,_mut}` over `core::slice::from_raw_parts` casts any bit pattern to a slice of arbitrary `T` (GHSA-gv7f-5qqh-vxfx) | PARTIAL — needs explicit raw-slice-wrapper check |
| **H06 Panic across the FFI boundary** | A Rust panic unwinds through a C frame; the C frame cannot unwind → UB (pre-1.81) | **rust-secp256k1 #354** — `default_illegal_callback_fn` panicked across the boundary into `libsecp256k1`; fix = `abort` (PR #358). DLT-critical (secp256k1 underpins Bitcoin/Ethereum signing) | NO — not covered |
| **H07 Panic-safety UAF surfacing via unwind** | A loop drops elements then updates `len` only after; a panicking `Drop` leaves `len` stale → next `clear` re-drops freed elements | **RUSTSEC-2026-0122** `rkyv` ≥0.8.0,<0.8.16 — `InlineVec::clear`/`SerVec::clear` update `self.len` after the drop loop (CWE-415/416); needs `catch_unwind` to exploit (GHSA-vfvv-c25p-m7mm) | NO — adjacent to H06; not covered |
| **H08 Unmaintained transitive (proc-macro) dep** | A widely transitively-pulled crate is abandoned (no fix channel, stale `syn 1.x`) → latent supply-chain risk | **RUSTSEC-2024-0370** `proc-macro-error` — unmaintained (no commits ~2y, no release ~4y), depends on outdated `syn 1.x` (INFO/maintenance) | PARTIAL — covered by `cargo deny` but no proc-macro-specific tiering |
| **H09 Allocator / layout mismatch across FFI** | Memory allocated by one allocator and freed/reinterpreted by another, or `Vec::from_raw_parts` reused at a different type/alignment → heap corruption | `[generic pattern — no specific incident verified this pass]` (xous H05 is the nearest confirmed raw-slice case; allocator-pairing UB itself is documented in the Rustonomicon) | YES — covered, but anchor is generic |
| **H10 `#[repr(C)]` field-order / padding mismatch** | Rust `#[repr(C)]` struct disagrees with the C-side struct in field order, width, or padding → reads cross-field garbage | `[generic pattern — no specific incident verified this pass]` (glib H04 is the verified *signature*-mismatch cousin) | YES — covered, generic anchor |
| **H11 Compile-time arbitrary execution (build.rs / proc-macro)** | `build.rs` or a proc macro runs arbitrary code at compile time with full FS/network access (read env vars, exfiltrate, inject into the token stream) | Documented Cargo capability (build-scripts reference); no *confirmed weaponized* build-time advisory this pass — `[generic pattern — no specific incident]` | PARTIAL — capability noted, no systematic proc-macro enumeration |
| **H12 Thread-safety of FFI wrapper types** | Rust wrapper around a non-thread-safe C handle does `unsafe impl Send/Sync` → data race in C | `[generic pattern — no specific incident verified this pass]` | PARTIAL — split with Unsafe-Trait angle |

> **Cross-language precedent note**: typosquatting and CI-gated payloads are not Rust-specific — npm and PyPI have the same class (e.g. the npm/PyPI typosquat waves, and the xz-utils `liblzma` backdoor as a clearly-labeled cross-ecosystem build-system-compromise precedent — none used as a Rust anchor here). The Rust-native facts are the registry primitives (`Cargo.lock` exact pins, `cargo yank`, build-script/proc-macro compile-time execution, the `extern "C"` vs `extern "C-unwind"` ABI distinction) and the `cargo audit`/`deny`/`vet`/`geiger` tool surface. Where a class is a generic cross-ecosystem pattern, the *methodology* below operationalizes it through Rust's own mechanisms, not a Solidity-style transliteration.

---

## 2. Per-class methodology (novel / under-covered classes)

### H06 — Panic across the FFI boundary (verified: rust-secp256k1 #354)

**Signal**: a Rust function reachable from C (`pub extern "C" fn …`), or a Rust caller holding a C frame on the stack, that can panic — `unwrap()`, `expect()`, `[]` indexing, integer division, `assert!`, or an explicit `panic!`. The rust-secp256k1 case was a `default_illegal_callback_fn` that panicked instead of aborting.

**Procedure**:
1. Enumerate boundary functions: `rg 'extern "C(-unwind)?"' --type rust` — both Rust→C (`extern "C" { fn … }`) and C→Rust (`pub extern "C" fn …`) directions.
2. For each Rust function called *from* C (callbacks, FFI exports): trace the body for any panic site. A panic here unwinds through the C caller's frame.
3. **Pin the ABI and the toolchain**: read the crate MSRV / edition. `extern "C"` was historically UB-on-unwind; **Rust 1.81 changed non-unwind ABIs (e.g. `"C"`) to *abort* on an uncaught unwind**, closing the soundness hole — so on a 1.81+ toolchain the worst case is a process abort (a DoS), not arbitrary UB. `extern "C-unwind"` (stabilized in **Rust 1.71**, RFC 2945; 1.71 left `"C"` unchanged → still UB-on-unwind in 1.71) is the opt-in for *intentional* cross-language unwinding. The finding's severity depends on which of these applies — confirm the build's toolchain, don't assume.
4. Fix shape: wrap the panicking body in `std::panic::catch_unwind` and convert to an error/abort at the boundary (the rust-secp256k1 fix was exactly "change this to `abort`").

**Mechanical evidence**: a unit test that drives the boundary function with the panic-triggering input under a `panic = "unwind"` profile and asserts abort/`catch_unwind` containment; `cargo +nightly miri test` with FFI isolation off for the boundary call where feasible.

**Anti-pattern (false-positive guard)**: a panic that is *only* reachable from internal, non-attacker-controlled invariants AND the crate builds on Rust 1.81+ is at most a controlled abort — note it, do not grade it as memory-corruption UB.

**Source**: rust-secp256k1 issue #354 (tier-1, real DLT crate); RFC 2945 + Rust 1.71 + Rust 1.81 release blogs (tier-4, ABI semantics).

### H07 — Panic-safety leaving a half-updated state (verified: rkyv RUSTSEC-2026-0122)

**Signal**: a loop that calls `drop_in_place`, `ptr::drop`, manual deallocation, or element teardown and updates the length/occupancy counter *after* the loop rather than per-element. rkyv's `clear()` set `self.len` only after iterating.

**Procedure**:
1. Find manual-drop loops: `rg 'drop_in_place|ManuallyDrop|set_len|from_raw_parts' --type rust` inside `clear`/`truncate`/`drain`/`Drop` implementations.
2. For each, ask: if a user `Drop` panics mid-loop, is the container left in a state where a *second* teardown re-touches freed elements? The invariant: length/occupancy must be decremented *before or as* each element is dropped, never only at the end.
3. Reachability: the panic must originate in caller-supplied `T::drop`, so the bug needs a `catch_unwind` boundary above to be observable (otherwise the panic aborts). Confirm such a boundary exists in the audited code path.

**Mechanical evidence**: a test with a `T` whose `Drop` panics on the k-th element inside `catch_unwind`, then re-invokes `clear()`/drops the container and asserts no double-drop (run under Miri/ASan to catch the UAF).

**Anti-pattern**: code compiled `panic = "abort"` end-to-end cannot observe this — the first panic aborts. Downgrade accordingly.

**Source**: RUSTSEC-2026-0122 (tier-3).

### H05 — Safe wrapper over a raw C slice (verified: xous RUSTSEC-2024-0431)

**Signal**: a *safe* method that returns `&[T]`/`&mut [T]` by calling `core::slice::from_raw_parts{,_mut}` (or `Vec::from_raw_parts`) over a pointer whose provenance/length/type the method does not itself validate. xous's `MemoryRange::as_slice` was safe but cast any bit pattern to a slice of arbitrary `T`.

**Procedure**:
1. `rg 'from_raw_parts' --type rust`, then for each hit check the *visibility/safety of the enclosing fn*. If the function is **not** `unsafe` but the pointer/len comes from outside (FFI out-param, user-set field, transmuted handle) → unsound safe interface.
2. Verify the three `from_raw_parts` obligations are enforced *inside* the safe fn: pointer is non-null + correctly aligned for `T`, `len * size_of::<T>()` does not overflow the allocation, and the bytes are a valid `T`. If any obligation is pushed onto the caller without `unsafe`, the fix is to mark the fn `unsafe` (xous's exact remediation — two functions marked `unsafe`).
3. Type-confusion check: can the caller pick `T`? If `as_slice::<U>()` is generic over the output type with no layout guard, that is direct type confusion.

**Mechanical evidence**: a test that constructs the wrapper from a misaligned/wrong-type pointer and shows the safe call produces an invalid `&[T]` (Miri flags the UB).

**Anti-pattern**: a `from_raw_parts` inside a genuinely `unsafe fn` with a documented `# Safety` contract is correct-by-construction — not a finding.

**Source**: RUSTSEC-2024-0431 (tier-3).

### H04 — Variadic / out-argument FFI signature mismatch (verified: glib RUSTSEC-2024-0429)

**Signal**: an `extern "C"` binding to a **variadic** C function, or any C function that writes through a pointer out-argument, where the Rust side passes a shared `&T` instead of `&mut T`. The glib bug escaped compilation *because* the C function was variadic — the type checker could not flag the mutability error. The leaked write surfaced as a NULL `*mut c_char` reaching `CStr::from_ptr` → NULL deref.

**Procedure**:
1. List every `extern "C"` declaration whose C counterpart has out-parameters or is variadic (`...`). `improper_ctypes` will NOT catch the `&` vs `&mut` error on a variadic signature — this needs manual review.
2. For each out-param, confirm the Rust call site passes `&mut`. A shared `&` lets LLVM assume the pointee is unmodified and optimize the C-side write away → the Rust code then reads the stale (often NULL) value, e.g. into `CStr::from_ptr` → null deref.
3. Cross-check the declared Rust signature against the actual C header (`-sys` crate or system header), field-by-field, including pointer mutability and width.

**Mechanical evidence**: an integration test exercising the binding under `--release` (so the optimization fires) asserting the out-value is observed, not NULL.

**Anti-pattern**: non-variadic, non-out-param bindings already checked by `improper_ctypes` are low-priority here.

**Source**: RUSTSEC-2024-0429 (tier-3).

### H11 — Compile-time execution surface (capability documented; no confirmed weaponized advisory this pass)

**Signal**: any `build.rs`, or any dependency with `[lib] proc-macro = true`. Both run with the build user's full privileges at compile time.

**Procedure**:
1. Enumerate proc-macro deps: `cargo metadata --format-version=1 | jq '.packages[] | select(.targets[].kind[] | contains("proc-macro")) | {name,version,source}'`. Flag `git`-sourced ones (mutable without a version bump) and obscure publishers.
2. Read every in-tree `build.rs`. Flag: `std::process::Command`, network (`reqwest`/`std::net`/`ureq`), reads of env vars beyond the documented Cargo set, or file access outside `OUT_DIR`.
3. Dependency hygiene as a proxy for risk: an *unmaintained* proc-macro dep has no patch channel if a problem is later found — treat per **RUSTSEC-2024-0370** (`proc-macro-error`) as a concrete, verified example of this hygiene gap, not as evidence of active malware.

**Mechanical evidence**: `strace -f -e trace=network,open,openat cargo build 2>&1 | grep -E 'connect|/etc|\.ssh|\.cargo/credentials'` to observe build-time syscalls. This is a capability audit, not proof of malice.

**Anti-pattern**: a `build.rs` that only reads `OUT_DIR`, `CARGO_*`, and `TARGET` and shells out to a vendored, in-repo tool is normal. Do NOT attach any CVE/RUSTSEC id to a build-script finding unless a real advisory matches — label compile-time-execution concerns `[generic pattern — no specific incident]`.

**Source**: Cargo reference (build scripts, tier-4); RUSTSEC-2024-0370 (tier-3, the hygiene anchor only).

---

## 3. Framework / ecosystem-specific knowledge

- **`extern "C"` ABI timeline (get this right — the prior draft did not).** `extern "C-unwind"` and the other `-unwind` ABIs stabilized in **Rust 1.71** (RFC 2945); the 1.71 notes state explicitly that *no change* was made to the existing ABIs (e.g. `"C"`) and "unwinding across them remains undefined behavior." **Rust 1.81** then made the non-unwind ABIs (incl. `"C"`) **abort** on an uncaught unwind, "closing the longstanding soundness problem." So: pre-1.81 → unwind across `"C"` is UB; 1.81+ → it is a defined abort; intentional cross-language unwinding requires `extern "C-unwind"`. Always confirm the target's toolchain before grading an FFI-panic finding.
- **Malware lives behind environment gates.** `rustdecimal` only detonated when `GITLAB_CI` was set, staying dormant on developer machines and during casual `cargo test`. Audit `build.rs` and runtime code for env-var-conditioned branches (`GITLAB_CI`, `CI`, `GITHUB_ACTIONS`) that change behavior.
- **Typosquats need only a handful of downloads to matter.** `finch-rst` (RUSTSEC-2025-0150) was published once and pulled ~21 times before removal; `rustdecimal` shipped 15 iterative versions under a fake "Paul Masen"/"MarcMayzl" identity. Name-similarity to a popular crate is the whole attack — `cargo audit` matches the exact name, but a *new* typosquat not yet in the DB is caught only by reviewing unfamiliar dependency names against their popular near-neighbors.
- **`cargo audit` matches by name+version against the RustSec DB; it does not prove reachability.** A `shlex` (RUSTSEC-2024-0006) hit only matters if `quote`/`join` are actually called on untrusted input — use `cargo tree -i shlex` for reachability, then trace the call. Note the precise range: <1.3.0 is affected; 1.2.1 carried only a minimal fix (the brace/`\xa0` escape), nul + control chars remained until 1.3.0.
- **`improper_ctypes` has blind spots.** It does not flag `&` vs `&mut` on variadic out-params (the glib bug) nor `#[repr(C)]` field-order divergence. Those need manual header diffing.
- **`from_raw_parts` is a *safe-function smell*, not just an `unsafe`-block smell.** The xous bug was a *safe* method wrapping it. Grep for `from_raw_parts` and check the enclosing fn's `unsafe` keyword and the provenance of its pointer/len.
- **Panic-safety is a supply-chain surface too.** rkyv's UAF needed only a user `Drop` that panics inside a `catch_unwind` — relevant to any node that deserializes attacker-supplied data with rkyv 0.8.0–0.8.15.

---

## 4. Tooling

| Tool | What it finds | Readiness | Invoke / golden signature |
|------|---------------|-----------|---------------------------|
| `cargo audit` | RustSec advisory name+version matches (H01/H02/H03/H08) | HIGH | `cargo audit --json` → match against the ids in §1 |
| `cargo deny` | yanked/banned/duplicate/license/source policy (H08 + yanked) | HIGH | `cargo deny check advisories bans sources` |
| `cargo vet` / `cargo supply-chain` | crates with no audit record / provenance | MEDIUM | `cargo vet suggest` |
| `cargo geiger` | unsafe-code ratio per crate (risk-tiering input) | MEDIUM | `cargo geiger --output-format Json` |
| `cargo tree -i <crate>` | inverse dependency tree → reachability of a flagged crate | HIGH | `cargo tree -i shlex` |
| Clippy `improper_ctypes` | some ABI mismatches (NOT variadic out-params, NOT field order) | HIGH (limited) | `cargo clippy -- -W clippy::improper_ctypes` |
| Miri (isolation off) | FFI/raw-slice UB at runtime (H04/H05/H07) | MEDIUM | `MIRIFLAGS="-Zmiri-disable-isolation" cargo +nightly miri test` |
| `strace -f cargo build` | build-time / proc-macro syscalls (H11 capability) | LOW (manual) | `strace -f -e trace=network,open cargo build` |
| `cargo metadata` + `jq` | proc-macro dependency enumeration (H11) | HIGH | filter `targets[].kind[] == "proc-macro"` |

---

## 5. Discovery calibration

- **Detection is cheap; judgment is the work.** `cargo audit` finds H01/H02/H03/H08 mechanically — the LLM's value is reachability (H03 `shlex` only matters if `quote`/`join` touch untrusted input) and severity-by-toolchain (H06 is UB pre-1.81, a defined abort after).
- **Directed beats undirected for FFI.** Hand the agent the boundary inventory (`rg 'extern "C'`, `rg 'from_raw_parts'`, `cargo metadata` proc-macro list) rather than "audit the FFI" — the glib and xous bugs are invisible to a generic read because the *safe* surface looks fine; the unsoundness is in the contract beneath it.
- **The hardest misses are dormant-by-design.** `rustdecimal`'s CI-gated payload would pass any test run that doesn't set `GITLAB_CI`. Static review of env-var-conditioned branches in deps/`build.rs` is the only reliable catch.

---

## 6. Gaps → angle changes

| Gap | Missing in current agent | Severity of gap | Proposal | Anti-bloat: existing cover? |
|-----|--------------------------|-----------------|----------|-----------------------------|
| **G-01** | H06 panic-across-FFI, toolchain-aware (pre-1.81 UB vs 1.81+ abort vs `C-unwind`) | HIGH | CHECK: enumerate `extern "C"` boundary fns, trace panic sites, branch severity on MSRV. Anchor: rust-secp256k1 #354 | No FFI-unwind check exists |
| **G-02** | H05 safe-wrapper-over-`from_raw_parts` (visibility check, not just `unsafe`-block scan) | MEDIUM | CHECK: grep `from_raw_parts`, assert enclosing fn `unsafe`-ness + pointer provenance. Anchor: xous RUSTSEC-2024-0431 | Partial — unsafe scan exists, no safe-wrapper angle |
| **G-03** | H04 variadic/out-param `&` vs `&mut` (Clippy blind spot) | MEDIUM | CHECK: header-diff variadic/out-param bindings for mutability. Anchor: glib RUSTSEC-2024-0429 | No — `improper_ctypes` misses it |
| **G-04** | H07 panic-safety half-updated-len UAF | MEDIUM | CHECK: manual-drop loops that update `len` after the loop, under `catch_unwind`. Anchor: rkyv RUSTSEC-2026-0122 | No |
| **G-05** | H11 proc-macro/`build.rs` enumeration + env-var-gated-behavior scan | MEDIUM | CHECK: `cargo metadata` proc-macro list + `build.rs` capability/`GITLAB_CI`-gate scan. Anchor: rustdecimal behavior + RUSTSEC-2024-0370 hygiene | Partial — covered, no systematic enumeration |
| **G-06** | Reachability discipline for `cargo audit` hits (don't grade by name-match alone) | LOW | Tie each advisory hit to `cargo tree -i` + call-trace before severity. Anchor: shlex RUSTSEC-2024-0006 | Partial |

---

## 7. Sources

All URLs fetched 2026-06-05; each confirms BOTH the identifier AND the mechanism cited above.

1. **RUSTSEC-2022-0042** — malicious crate `rustdecimal` (typosquat of `rust_decimal`; `Decimal::new` checks `GITLAB_CI`, downloads `/tmp/git-updater.bin`, executes it; Linux+macOS payload; no patched version, removed from registry); aliases GHSA-7pwq-f4pq-78gm, MAL-2022-1. <https://rustsec.org/advisories/RUSTSEC-2022-0042.html> · Rust Blog corroboration (same mechanism, verbatim): <https://blog.rust-lang.org/2022/05/10/malicious-crate-rustdecimal/>
2. **CrateDepression** (SentinelOne Labs) — same `rustdecimal` incident; second-stage = Go 1.17.8 unsigned **Poseidon**/**Mythic** payloads; **15** malicious versions (1.22.0–1.23.5); fake "Paul Masen"/"MarcMayzl" maintainer; CI-pipeline targeting. <https://www.sentinelone.com/labs/cratedepression-rust-supply-chain-attack-infects-cloud-ci-pipelines-with-go-malware/>
3. **RUSTSEC-2024-0006** — `shlex` <1.3.0 command/argument injection: `quote`/`join`/`bytes::quote`/`bytes::join` leave `{` and `\xa0` (and pre-1.3.0 nul + control chars) unescaped; CVE-2024-58266, GHSA-r7qv-8r2h-pg27; patched ≥1.3.0 (1.2.1 = minimal fix). *(Corrects prior draft's misattributed `RUSTSEC-2023-0071`, which is the RSA Marvin-attack crate.)* <https://rustsec.org/advisories/RUSTSEC-2024-0006.html>
4. **RUSTSEC-2025-0150** — `finch-rst` malicious typosquat of `finch`; steals credentials from local files; published once (~21 downloads), no patched version; GHSA-xp79-9mxw-878j. <https://rustsec.org/advisories/RUSTSEC-2025-0150.html>
5. **RUSTSEC-2024-0429** — `glib` ≥0.15.0,<0.20.0 FFI unsoundness: shared `&p` passed to variadic `g_variant_get_child` out-param → compiler drops the C-side write → NULL `*mut c_char` reaches `CStr::from_ptr` → NULL-pointer deref; affects `VariantStrIter::{next,next_back,nth,nth_back,last}`; GHSA-wrw7-89jp-8q8g; patched ≥0.20.0. <https://rustsec.org/advisories/RUSTSEC-2024-0429.html>
6. **rust-secp256k1 issue #354** — `default_illegal_callback_fn` panicked across the FFI boundary into `libsecp256k1` (UB); recommended/implemented fix = `abort` (PR #358). DLT-critical crate. <https://github.com/rust-bitcoin/rust-secp256k1/issues/354>
7. **RFC 2945 — `C-unwind` ABI** (stabilized Rust 1.71; introduces `"C-unwind"`/`"system-unwind"`/etc. for intentional cross-language unwinding; `"C"` unchanged in 1.71, still UB-on-unwind). <https://rust-lang.github.io/rfcs/2945-c-unwind-abi.html> · Rust 1.71 release ("no change… unwinding across them remains undefined behavior"): <https://blog.rust-lang.org/2023/07/13/Rust-1.71.0/>
8. **Rust 1.81 release** — non-unwind ABIs (incl. `"C"`) now **abort** on uncaught unwind, "closing the longstanding soundness problem." <https://blog.rust-lang.org/2024/09/05/Rust-1.81.0/>
9. **RUSTSEC-2024-0370** — `proc-macro-error` unmaintained (no commits ~2y, no release ~4y, stale `syn 1.x`); INFO/maintenance; alternatives manyhow/proc-macro-error2/proc-macro2-diagnostics. <https://rustsec.org/advisories/RUSTSEC-2024-0370.html>
10. **RUSTSEC-2026-0122** — `rkyv` ≥0.8.0,<0.8.16 use-after-free/double-free (CWE-415/416): `InlineVec::clear`/`SerVec::clear` update `self.len` after the drop loop → re-drop of freed elements when a `Drop` panics; requires unwind + `catch_unwind`; GHSA-vfvv-c25p-m7mm; patched ≥0.8.16. <https://rustsec.org/advisories/RUSTSEC-2026-0122.html>
11. **RUSTSEC-2024-0431** — `xous` <0.9.51: safe `MemoryRange::as_slice{,_mut}` wrap `core::slice::from_raw_parts` → any bit pattern cast to a slice of arbitrary `T` (type confusion); fix = mark the two functions `unsafe`; GHSA-gv7f-5qqh-vxfx; patched ≥0.9.51. <https://rustsec.org/advisories/RUSTSEC-2024-0431.html>

**Dropped / corrected from prior draft (do not reintroduce):**
- `CVE-2022-31094` as a "Substrate `memory_units` WASM-DoS" anchor — **FABRICATED**: CVE-2022-31094 is a ScratchTools browser-extension XSS (affects ScratchTools 2.4.0–<2.5.2 via the Recently-Viewed-Projects feature; fixed 2.5.2), unrelated to Rust/Substrate. Verified via NVD/cvedetails. Removed; no replacement WASM-DoS anchor was verifiable this pass.
- `RUSTSEC-2023-0071` as the shlex advisory — **MISATTRIBUTED**: that id is the RSA-crate Marvin-attack timing side-channel (CVE-2023-49092; GHSA-c38w-74pg-36hr). Verified via rustsec.org. Real shlex id is RUSTSEC-2024-0006 (source #3).
- `cve-rs` (RUSTSEC-2025-0028) and `grcov` (RUSTSEC-2025-0005) were examined and excluded: cve-rs is a deliberate joke/demonstration crate ("should never be used"), and grcov's OOB write is a parsing bug, not an FFI/supply-chain class.
- `xz-utils`/`liblzma` backdoor (CVE-2024-3094) — a real, marquee build-system-compromise incident, but **C/autotools, not Rust**; retained only as a clearly-labeled cross-ecosystem precedent in §1, never as a Rust anchor.

---

> **AI-provenance reminder**: This dossier was assembled by an AI agent from primary sources fetched 2026-06-05. Every retained identifier was confirmed against the cited URL for BOTH id and mechanism, but advisory pages and ABI semantics evolve — a human auditor MUST re-fetch the section-7 URLs and re-confirm affected/patched version ranges and the target's exact Rust toolchain before relying on any claim here in a submission. Classes labelled `[generic pattern — no specific incident]` carry NO identifier by design; do not attach one without a verified primary source. Treat this as a research lead, not ground truth.
