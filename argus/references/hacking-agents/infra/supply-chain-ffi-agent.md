# Supply Chain, FFI & Build Integrity Agent (`infra` mode — Angle 8)

**Load also**: [`depth-methodology.md`](depth-methodology.md) — depth disciplines (attack-surface enum, pre-auth panic sweep, asymmetric-cost quantification, resource bounds, cross-domain deps, boundary checklist, §WRITE-THEN-VERIFY). Mandatory in Core + Thorough tiers; optional in Light.

**Research grounding**: [`supply-chain-ffi-research.md`](../../research/supply-chain-ffi-research.md) — 12-class bug taxonomy (H01–H12) anchored in the `rustdecimal` typosquat (RUSTSEC-2022-0042 — a malicious crate that downloaded and executed a payload), real RustSec advisory classes, and verified Rust supply-chain compromises. Every CHECK below is traceable to a bug class in the dossier.

> **Calibration**: Supply chain and FFI bugs are the hardest class to find by reading source code: the vulnerability lives in code you DIDN'T write (a dependency), at a boundary where Rust's safety guarantees don't apply (FFI), or in code that runs BEFORE your audit begins (`build.rs`, proc macros). The auditor who only reads the project's `src/` directory misses them entirely. The anchor case is the `rustdecimal` typosquat (RUSTSEC-2022-0042): a crate named one character away from `rust_decimal` checked for `GITLAB_CI` and, if set, downloaded and executed `/tmp/git-updater.bin` — a compromise no amount of reading the project's own `src/` would catch.
>
> Four sub-classes dominate: **(1) Known-vulnerable dependencies** — `Cargo.lock` pins a crate version matching a RustSec advisory, and the vulnerable function is reachable from the audited code. `cargo audit` finds the CVE; reachability analysis determines severity. **(2) FFI boundary unsoundness** — `extern "C"` signatures, `#[repr(C)]` layout mismatches, null-pointer dereference, allocator mismatch, and unwinding through C frames. These are Rust's "trust boundary" — the compiler can't verify them. **(3) Build-time compromise** — `build.rs` and proc macros execute arbitrary code at compile time. A compromised dependency's build script can exfiltrate secrets or embed backdoors. **(4) Supply-chain integrity** — typosquatted crate names, yanked versions, unaudited high-unsafe-density crates, and `#[no_mangle]` symbol collisions.
>
> Tool coverage is GOOD for detection but requires human judgment for reachability. `cargo audit` outputs a JSON list of CVEs; the LLM's job is to determine which are reachable and exploitable in the specific codebase. `cargo geiger` flags unsafe density but can't determine soundness. Clippy catches some FFI patterns (`improper_ctypes`) but not all. The LLM's advantage is reading actual FFI binding code and reasoning about ABI compatibility.

**Primary verification backends**: `cargo audit` (RustSec advisory DB), `cargo deny` (license / source / yanked / banned-crate policy), `cargo vet` (audit record gaps), `cargo supply-chain` (provenance / publisher trust), `cargo geiger` (unsafe footprint), Clippy `improper_ctypes` + `missing_safety_doc`, Miri with `-Zmiri-disable-isolation` for FFI UB. Vectors in **Group H** (`dlt-infra-attack-vectors.md`) are your catalogue.

---

## Phase 1: Pre-seed from tooling

Before manual analysis, seed with mechanical findings:

1. **Run `cargo audit`** (the single highest-ROI tool for this angle):
   ```bash
   cargo audit --json
   ```
   Every RustSec advisory match → seeded CHECK 1 candidate. For each: determine reachability from the audited codebase via call-graph analysis.

2. **Run `cargo deny`** (yanked crates, banned crates, license violations):
   ```bash
   cargo deny check
   ```
   Yanked crate versions → CHECK 9 candidate. Banned-crate violations → CHECK 1/5 candidate.

3. **Run `cargo geiger`** (unsafe density):
   ```bash
   cargo geiger --output-format Json
   ```
   High-unsafe-ratio transitive dependencies → CHECK 5 candidate (risk-tiering).

4. **Run Clippy security lints**:
   ```bash
   cargo clippy --all-targets -- -W clippy::improper_ctypes \
                                  -W clippy::improper_ctypes_definitions \
                                  -W clippy::missing_safety_doc
   ```

5. **High-signal grep patterns**:
   ```bash
   # Every extern "C" block — CHECK 2/3/7/10/11 audit
   rg 'extern "C"' --type rust -l
   # Every #[no_mangle] export — CHECK 8 audit
   rg '#\[no_mangle\]' --type rust -l
   # Every build.rs — CHECK 4 audit
   find . -name build.rs
   # Every unsafe impl Send/Sync on FFI wrapper types — CHECK 11 audit
   rg 'unsafe\s+impl\s+(Send|Sync)' --type rust -l
   # Every proc-macro dependency — CHECK 12 audit
   cargo metadata --format-version=1 | jq '.packages[] | select(.targets[].kind[] | contains("proc-macro")) | {name, version, source}'
   # Every AssertUnwindSafe on FFI paths — CHECK 10 audit
   rg 'AssertUnwindSafe' --type rust -l
   # Catch-unwind wrappers near FFI — CHECK 10 positive signal
   rg 'catch_unwind' --type rust -l
   ```

---

## Phase 2: Supply chain + FFI surface inventory

Enumerate every surface where untrusted code or non-Rust code meets the codebase:

- **`Cargo.toml` + `Cargo.lock` inventory**: every direct dependency, every transitive dependency, every proc-macro dependency, every git-source dependency. For each: version, source (crates.io / git / local), audit status (`cargo vet`), yanked status (`cargo deny`).
- **`extern "C"` block inventory**: every `extern "C"` function declaration (C→Rust boundary), every `extern "C" fn` (Rust→C boundary). For each: parameter types (nullability, `repr(C)` layout requirements), return types, safety documentation.
- **`#[no_mangle]` export inventory**: every exported symbol. Check for name collisions within the workspace AND against common C library symbols (`malloc`, `free`, `memcpy`).
- **`build.rs` inventory**: every build script. For each: does it execute arbitrary commands? Access files outside `OUT_DIR`? Read environment variables? Make network requests?
- **Proc-macro dependency inventory**: every proc-macro crate. For each: well-known (serde-derive, thiserror, derive_more) vs obscure; crates.io vs git source; audit record.
- **FFI wrapper type inventory**: every Rust type wrapping a C pointer/handle. For each: does it implement `Send`/`Sync`? Is the C library documented as thread-safe?

---

## Phase 3: Per-class checks

### CHECK 1 — Known-vulnerable dependency (H01)

**Signal**: `cargo audit` returns a RustSec advisory for a crate version in `Cargo.lock`.

**Procedure**:
1. For every advisory hit: determine reachability. `cargo tree -i <crate> --depth <N>` shows the inverse-dependency chain from the audited codebase to the vulnerable crate.
2. **Reachability classes**:
   - **Directly reachable from in-scope code**: the vulnerable function is called from a public API, request handler, or consensus path → FINDING (severity per advisory impact).
   - **Reachable via trait impl or type instantiation**: the crate's types are constructed/consumed → FINDING (severity per advisory, possibly downgraded if the vulnerable code path is condition-specific).
   - **Present in dependency tree but unreachable**: the crate is linked but the vulnerable function is never called → INFORMATIONAL at most.
   - **Test-only dependency** (`[dev-dependencies]`): informational only — not deployed.
3. **Sub-crate impact**: the advisory may apply to a sub-crate of a monorepo dependency. `cargo tree` shows which sub-crate is pulled in.
4. Severity: per RustSec advisory impact, downgraded by reachability. DIRECT-reachable = advisory severity. CONDITIONAL-reachable = advisory − 1 tier. UNREACHABLE = Informational.

**Golden signature**: `cargo audit --json` hit + `cargo tree -i <crate>` showing reachable path.

**Source**: `rustdecimal` — malicious typosquat of `rust_decimal` that downloads and executes a payload when `GITLAB_CI` is set — RUSTSEC-2022-0042; `shlex` <1.3.0 command/argument injection (unescaped `{`, `\xa0`, control chars) — RUSTSEC-2024-0006 / CVE-2024-58266; `glib` variadic-FFI NULL-pointer deref via `g_variant_get_child` out-param — RUSTSEC-2024-0429. **Misattribution guard**: the prior draft's `RUSTSEC-2023-0071` is the RSA Marvin-attack crate (not shlex), and `CVE-2022-31094` is a ScratchTools browser-extension XSS (not "Substrate memory_units") — both removed. See `supply-chain-ffi-research.md` §H01.

---

### CHECK 2 — FFI null-pointer dereference (H02)

**Signal**: `extern "C" fn` receives `*const T` or `*mut T`; Rust caller dereferences without null check.

**Procedure**:
1. For every `extern "C" fn` receiving a raw pointer: does the Rust caller (or the function body itself) check `ptr.is_null()` BEFORE dereferencing?
2. **Auto-deref pattern**: `unsafe { &*ptr }` — this immediately creates a reference from a potentially-null raw pointer. References MUST NOT be null per Rust's safety rules; creating a null reference is UB EVEN IF NEVER ACCESSED.
3. **Option-wrapping**: `if ptr.is_null() { None } else { Some(unsafe { &*ptr }) }` — the safe pattern. Verify it's used consistently.
4. Severity: HIGH if a network-facing FFI call can supply a null pointer and the code dereferences it. MEDIUM if the FFI call is only from trusted internal code.

**Golden signature**: Miri with `-Zmiri-disable-isolation` feeding a null pointer to the FFI function.

**Source**: Various `-sys` crate bindings [model-knowledge]; winapi/runtime null-ptr crashes [model-knowledge].

---

### CHECK 3 — Allocator mismatch across FFI (H03)

**Signal**: Rust allocates a buffer, passes pointer to C; C calls `free()` — or C `malloc`s, Rust receives pointer and drops it.

**Procedure**:
1. For every FFI function that accepts a pointer from Rust: does the C side deallocate it? If C calls `free()` on a Rust-allocated pointer → allocator mismatch (Rust uses `std::alloc::Global`, C uses libc's `malloc` family).
2. For every FFI function that returns a pointer to Rust: does Rust deallocate it? If Rust calls `std::alloc::dealloc` or `drop` on a libc-allocated pointer → mismatch. The safe pattern: C provides a `free_thing()` companion function that uses libc's `free`; Rust calls that instead of its own deallocation.
3. **Rust Vec → C**: passing `&mut Vec<u8>` to C as `*mut u8` + `len` is safe IF C only reads/writes WITHIN the bounds (no realloc/free). If C calls `realloc` or `free` on the pointer → disaster.
4. Severity: HIGH if allocator mismatch is reachable and the system allocator differs from libc (common on non-glibc platforms). MEDIUM if the system allocator IS glibc's `malloc` (de facto compatible but still UB).

**Golden signature**: Miri with `-Zmiri-disable-isolation` and `-Zmiri-check-abi` on allocator-mismatch test.

**Source**: Rust-C allocator boundary bugs [model-knowledge]; glibc malloc vs jemalloc [model-knowledge].

---

### CHECK 4 — Malicious / fragile build.rs (H04)

**Signal**: `build.rs` files in dependencies that: execute `std::process::Command`, read files outside `OUT_DIR`, access environment variables, or make network requests.

**Procedure**:
1. For EVERY `build.rs` in the dependency tree (not just the project's own): audit the operations.
2. **Malicious signals** (elevated risk):
   - `std::process::Command::new("...")` — executing arbitrary commands at build time
   - File reads from outside `CARGO_MANIFEST_DIR` or `OUT_DIR`
   - `std::env::var("HOME")` or `std::env::var("SSH_AUTH_SOCK")` — accessing user environment
   - Network operations (`std::net::TcpStream`, `reqwest`, `ureq`) in build scripts
   - Writing to paths outside `OUT_DIR` — could modify source or inject compiled artifacts
   - **CI-env-var-gated behavior** — branches keyed on `GITLAB_CI`, `CI`, or `GITHUB_ACTIONS` that change what the script does. This is the dormant-by-design signature: malware stays inert on dev laptops and casual `cargo test`, detonating only inside CI. `rg 'GITLAB_CI|GITHUB_ACTIONS|"CI"' build.rs` across the dependency tree, and check runtime code for the same gate (the `rustdecimal` payload gated on `GITLAB_CI`).
3. **Legitimate signals** (not findings):
   - Reading files in `CARGO_MANIFEST_DIR` for code generation (`.proto`, `.fbs`, etc.)
   - Writing generated code to `OUT_DIR` (standard practice)
   - `println!("cargo:rustc-link-lib=...")` — standard linker directive
   - `cc::Build` / `pkg-config` invocations — standard C-library detection
4. Severity: CRITICAL if a transitive dependency's `build.rs` makes network calls or reads secrets. HIGH if it executes arbitrary commands. MEDIUM if it accesses user environment variables unnecessarily. Informational for standard build-script patterns.

**Golden signature**: Manual audit of `build.rs` content. `strace -f cargo build 2>&1 | grep -E 'connect|open|sendto'` for runtime confirmation.

**Source**: Supply-chain attack vector in cargo docs [model-knowledge]; real-world cratejack incidents [model-knowledge].

---

### CHECK 5 — Unsafe in unaudited third-party (H05)

**Signal**: Transitive dependencies with high `cargo geiger` unsafe ratio AND no audit record (`cargo vet`).

**Procedure**:
1. Run `cargo geiger --output-format Json`. Extract `unsafe_ratio` per crate.
2. Run `cargo vet` to check which crates have audit records. Crates with NO audit record AND `unsafe_ratio > 0.1` → elevated risk.
3. **Risk tiers**:
   - **HIGH RISK**: unaudited + `unsafe_ratio > 0.3` + reachable from security-critical path (consensus, crypto, network message parsing).
   - **MEDIUM RISK**: unaudited + `unsafe_ratio > 0.1` + reachable from any public API.
   - **INFORMATIONAL**: unaudited + `unsafe_ratio > 0.1` but only used in CLI tooling (not runtime).
   - **NOISE**: audited crate OR `unsafe_ratio < 0.01` — skip.
4. For each HIGH/MEDIUM risk crate: manually audit the unsafe blocks in the crate's source. Are they sound? If any unsoundness found → finding. If all appear sound → still report the dependency as a supply-chain risk (no guarantee of soundness from unaudited sources).
5. Severity: HIGH for unaudited high-unsafe crate in consensus/crypto path. MEDIUM for unaudited high-unsafe crate in other runtime paths.

**Golden signature**: `cargo geiger` + `cargo vet` output; cross-reference with call-graph reachability.

**Source**: cargo-geiger [model-knowledge]; Substrate dependency unsafe footprints [model-knowledge].

---

### CHECK 6 — Typosquatted crate (H06)

**Signal**: Crate name visually similar to a well-known crate; single-character differences, underscore-for-hyphen swaps, or transposed letters.

**Procedure**:
1. For every dependency: compute Levenshtein distance to the top 500 crates.io crates. Distance of 1-2 with no audit record → elevated suspicion.
2. **Hyphen/underscore confusion**: Rust normalizes `-` to `_` in crate names during resolution. `my-crate` and `my_crate` resolve to the SAME crate. But `serde` vs `serde_core` — the attacker publishes `serde_core` as a distinct crate; a typo in `Cargo.toml` pulls the wrong one.
3. `cargo vet` / `cargo supply-chain` indicates audit status. Unaubited crate with a typosquat-similar name to a well-known crate → FINDING.
4. Severity: HIGH if the squatted crate is in the dependency tree AND has no audit record. CRITICAL if the squatted crate contains suspicious build scripts or proc-macros.

**Golden signature**: Name similarity check against top crates; manual verification.

**Source**: crates.io typosquatting incidents [model-knowledge]; npm/rust package registry squatting research [model-knowledge].

---

### CHECK 7 — `repr(C)` layout mismatch (H07)

**Signal**: `#[repr(C)]` struct on the Rust side differs from the C-side struct in field order, type size, alignment, or padding.

**Procedure**:
1. For every `#[repr(C)]` struct used in FFI (passed to or returned from `extern "C"`): find the C-side definition. Compare field-by-field.
2. **Common mismatches**:
   - `bool` — Rust: 1 byte. C `_Bool`: 1 byte (C99), but `BOOL` (Windows) is `int` (4 bytes).
   - `enum` — Rust `#[repr(C)] enum` has a tag + payload union; C enums are just integers. Never pass a Rust enum to C without `#[repr(u32)]` or equivalent.
   - `usize`/`isize` — width is platform-dependent (32 vs 64 bit). Use fixed-width types (`u32`, `u64`).
   - `*const T` / `*mut T` — pointer width is platform-dependent. Thin pointers (no vtable) are equivalent to `void*`.
   - Field ordering: Rust `#[repr(C)]` lays out in declaration order; C lays out in declaration order. If order differs → mismatch.
   - Padding/alignment: different compilers may insert different padding between fields. Use `#[repr(C, packed)]` if exact layout is required, but this may be UB if fields are not naturally aligned.
3. **Tool coverage**: Clippy `improper_ctypes` catches SOME cases (passing non-C-compatible types across FFI) but does NOT catch field-order mismatches or enum layout issues.
4. Severity: HIGH if the mismatch causes UB (misaligned read, wrong field accessed). MEDIUM if the mismatch causes logic errors without UB. LOW if Clippy already flags it.

**Golden signature**: Side-by-side Rust `#[repr(C)]` struct vs C struct definition comparison.

**Source**: Rust-C ABI mismatch [model-knowledge]; 32-vs-64-bit field width divergence [model-knowledge].

---

### CHECK 8 — `#[no_mangle]` symbol collision (H08)

**Signal**: Multiple `#[no_mangle]` exports across the workspace or transitive deps with potential name collision.

**Procedure**:
1. Enumerate every `#[no_mangle]` export in the entire workspace:
   ```bash
   rg '#\[no_mangle\]' --type rust -A1
   ```
2. Build a name-to-definition map. Check for:
   - **Name conflicts within the workspace**: two workspace crates exporting the same symbol → linker picks one nondeterministically. UB if the two functions have different behavior.
   - **Collision with system library symbols**: `#[no_mangle] pub extern "C" fn malloc(...)` would shadow libc `malloc` in certain linking configurations.
   - **Collision with common C library entry points**: `_start`, `main`, `__cxa_*`, `pthread_*` — shadowing these causes undefined process behavior.
3. Severity: HIGH if a collision is found between functions with different behavior. MEDIUM if collision is theoretical (same workspace but different features gate one).

**Golden signature**: `rg '#\[no_mangle\]' --type rust` across workspace + manual name-comparison table.

**Source**: Symbol collision at link time [model-knowledge]; Cargo workspace with duplicate exports [model-knowledge].

---

### CHECK 9 — Yanked crate in lockfile (H09)

**Signal**: `Cargo.lock` pins a yanked crate version. `cargo deny check` flags these.

**Procedure**:
1. Run `cargo deny check`. Every yanked-version advisory → candidate.
2. For each: check WHY the crate was yanked. The crates.io yank reason is often just "yanked" — search RustSec advisories for the crate version. Common reasons: security vulnerability, unsoundness, packaging error.
3. **Security yank**: the crate was yanked for a vulnerability → upgrade to the fixed version. Severity per the advisory.
4. **Packaging yank**: the crate was yanked for a non-security reason (wrong version, metadata error) → still upgrade, but severity is Informational.
5. **Transitive yanked dep**: `cargo update <crate>` to bump the lockfile. If the yanked version is pinned because a newer semver-compatible version doesn't exist → investigate the ecosystem for a fork/alternative.
6. Severity: per advisory if security-related. Informational if packaging-related.

**Golden signature**: `cargo deny check` output + crates.io yank status.

**Source**: Yanked crate CVEs [model-knowledge]; crates.io yank policy [model-knowledge].

---

### CHECK 10 — Unwinding through FFI (C-unwind) (H10)

**Signal**: `extern "C"` function called from Rust that could panic — or `extern "C" fn` called by C where Rust code could panic. Unwinding through C frames is UB.

**Procedure**:
1. Enumerate every Rust function called FROM C (every `extern "C" fn`) and every C function called from Rust (every `extern "C" { fn ... }` block).
2. **Rust→C calls**: the Rust caller exists while a C frame is on the stack. If the Rust code AFTER the C call can panic → UB on unwind. Fix: wrap the C call + subsequent code in `catch_unwind`.
3. **C→Rust calls**: the Rust callee's body executes. If it can panic → the panic tries to unwind THROUGH the C caller's frame → UB. Fix: wrap the entire function body in `catch_unwind`.
4. **The "C-unwind" ABI timeline — branch severity on the build's actual toolchain, do NOT assume**:
   - **Rust < 1.71**: `extern "C"` means "cannot unwind"; any panic through it → UB.
   - **Rust 1.71**: `extern "C-unwind"` (RFC 2945) stabilizes for *intentional* cross-language unwinding, but `"C"` is unchanged — unwinding across `"C"` remains UB.
   - **Rust 1.81+**: non-unwind ABIs (incl. `"C"`) now *abort* on an uncaught unwind, closing the soundness hole → worst case is a process abort (DoS), NOT memory-corruption UB.
   - **Read the build's toolchain/MSRV before grading**: pre-1.81 panic-across-`"C"` = UB (HIGH+); 1.81+ = controlled abort (DoS, downgrade unless DoS itself is the impact).
5. **`panic = "abort"`**: if `Cargo.toml` sets `panic = "abort"`, panics never unwind → this check is moot. But DLT infrastructure often uses `panic = "unwind"` to allow recovery.
6. Severity: HIGH if an attacker-reachable panic-through-C path exists on a pre-1.81 toolchain (UB). On 1.81+ the same path is a defined abort → grade as DoS (MEDIUM unless the abort itself denies a consensus/network-critical service). MEDIUM if the panic is unlikely (only on invalid internal state, not attacker-controlled input).

**Golden signature**: `rg 'extern "C(-unwind)?"' --type rust` + manual trace for panic sites (`unwrap()`, `expect()`, `panic!()`, `assert!`, array indexing, division) in the function body — both directions (Rust→C callers and `pub extern "C" fn` callbacks invoked from C).

**Source**: `rust-secp256k1` #354 — `default_illegal_callback_fn` panicked across the boundary into `libsecp256k1` (UB); fix = `abort` (PR #358) — DLT-critical signing crate; RFC 2945 + Rust 1.71/1.81 ABI semantics. See `supply-chain-ffi-research.md` §H06.

---

### CHECK 11 — Thread-safety of FFI types (H11)

**Signal**: Rust wrapper type around a C library handle implements `Send` and/or `Sync` via `unsafe impl` without verifying the C library's thread-safety documentation.

**Procedure**:
1. Enumerate every Rust type that wraps a C pointer/handle (database connections, crypto context, parser state, file handles).
2. For each: check for `unsafe impl Send` / `unsafe impl Sync`. If present AND the C library is not documented as thread-safe → the impl is unsound.
3. **C library thread-safety audit** (check the C library's documentation):
   - `libsecp256k1`: thread-safe (signing context can be shared; verification context is read-only).
   - `BLS12-381` C libraries: varies — check docs.
   - `libp2p` C components: varies.
   - `LevelDB` / `RocksDB`: thread-safe with restrictions (one DB handle can be shared; read-only snapshots; write batches must be single-threaded).
   - `LMDB`: `MDB_env` is thread-safe with `MDB_NOTLS`; cursor operations are NOT.
4. **No explicit documentation**: if the C library docs don't say "thread-safe" → assume NOT thread-safe. `unsafe impl Send + Sync` is unsound.
5. Severity: HIGH if the C library is NOT thread-safe and the wrapper type `impl Sync` → data race in C code. MEDIUM if only `Send` (less likely to cause races but still UB).

**Golden signature**: `rg 'unsafe impl Send'` / `rg 'unsafe impl Sync'` on FFI wrapper types + C library thread-safety label audit.

**Source**: FFI wrapper unsound Send/Sync [model-knowledge]; OpenSSL/libssl thread-safety [model-knowledge].

---

### CHECK 12 — Proc-macro supply chain (H12)

**Signal**: `[dependencies]` with proc-macro crates (crates with `[lib] proc-macro = true` in their `Cargo.toml`). Proc macros execute at compile time with full filesystem and network access.

**Procedure**:
1. Enumerate every proc-macro dependency:
   ```bash
   cargo metadata --format-version=1 | jq '.packages[] | select(.targets[].kind[] | contains("proc-macro")) | {name, version, source}'
   ```
2. For each: classify:
   - **Well-known + audited**: `serde_derive`, `thiserror`, `derive_more`, `darling`, `async-trait` — standard ecosystem, low risk.
   - **Obscure + unaudited**: crate with few downloads, no `cargo vet` record, no prominent maintainers — elevated risk.
   - **Git-source proc macros**: `[dependencies]` pointing to a git URL — can change without version bumps. Review the pinned commit.
3. **Proc-macro capabilities** (any proc macro CAN do these; the audit checks whether they DO):
   - Read/write any file the build user can access
   - Make network requests (exfiltrate env vars, source code)
   - Execute arbitrary commands (`std::process::Command`)
   - Embed backdoors in the generated token stream (modify the compiled binary)
4. **Capability audit**: For each obscure proc macro, review the source:
   - Does it open files beyond `OUT_DIR`?
   - Does it read environment variables?
   - Does it make network calls?
   - Does it execute commands?
   If YES to any → elevated risk, potentially a finding.
5. **Sandboxing**: cargo lacks built-in proc-macro sandboxing. `cargo careful` provides some isolation but is not a default. If the project uses `cargo careful` in CI → mitigation. If not → the raw capability is available.
6. Severity: CRITICAL if a proc macro from an unaudited source makes network calls or reads files outside `OUT_DIR`. HIGH if from an obscure crate with no audit history. MEDIUM if from a well-known crate but with unnecessarily broad capabilities.

**Golden signature**: `cargo metadata` + manual audit of proc-macro source. `strace -f cargo build 2>&1 | grep -E 'connect|open|sendto'` for runtime observation.

**Source**: Proc-macro security model documentation [model-knowledge]; cargo sandboxing discussions [model-knowledge].

---

### CHECK 13 — Safe wrapper over a raw C slice

**Signal**: a NON-`unsafe` method that returns `&[T]`/`&mut [T]` by calling `core::slice::from_raw_parts{,_mut}` (or `Vec::from_raw_parts`) over a pointer whose provenance, length, or type it does not itself validate.

**Procedure**:
1. `rg 'from_raw_parts' --type rust`. For each hit, check the *visibility/safety of the enclosing fn* — `from_raw_parts` is a *safe-function smell*, not just an `unsafe`-block smell.
2. If the enclosing fn is NOT `unsafe` but the pointer/len comes from outside (FFI out-param, user-set field, transmuted handle) → unsound safe interface. Verify the three obligations are enforced INSIDE the safe fn: pointer non-null + aligned for `T`, `len * size_of::<T>()` does not overflow the allocation, bytes are a valid `T`. Any obligation pushed onto the caller without `unsafe` → finding (fix: mark the fn `unsafe`).
3. **Type-confusion check**: if the method is generic over the output `T` with no layout guard (e.g. `as_slice::<U>()`), the caller picks the type → direct type confusion.
4. Severity: HIGH if a misaligned/wrong-type pointer reaches the safe call from attacker-influenced state. MEDIUM if provenance is internal-only.

**Golden signature**: Miri test constructing the wrapper from a misaligned/wrong-type pointer, showing the safe call produces an invalid `&[T]`.

**Anti-pattern**: `from_raw_parts` inside a genuinely `unsafe fn` with a documented `# Safety` contract is correct-by-construction — not a finding.

**Source**: `xous` <0.9.51 — safe `MemoryRange::as_slice{,_mut}` cast any bit pattern to a slice of arbitrary `T`; fix = mark both functions `unsafe` (RUSTSEC-2024-0431). See `supply-chain-ffi-research.md` §H05.

---

### CHECK 14 — Variadic / out-param `&` vs `&mut` mismatch

**Signal**: an `extern "C"` binding to a **variadic** C function (`...`), or any C function that writes through a pointer out-argument, where the Rust side passes a shared `&T` instead of `&mut T`.

**Procedure**:
1. List every `extern "C"` declaration whose C counterpart is variadic or has out-parameters. `improper_ctypes` does NOT flag `&` vs `&mut` on a variadic signature — the type checker can't see through `...`. This needs manual header diffing.
2. For each out-param, confirm the Rust call site passes `&mut`. A shared `&` lets LLVM assume the pointee is unmodified and optimize the C-side write away → Rust then reads the stale (often NULL) value, e.g. into `CStr::from_ptr` → NULL deref.
3. Cross-check the declared Rust signature against the actual C header (`-sys` crate or system header), field-by-field, including pointer mutability and width.
4. Severity: HIGH if the optimized-away write yields a NULL/stale deref reachable from untrusted input. MEDIUM if internal-only.

**Golden signature**: integration test under `--release` (so the optimization fires) asserting the out-value is observed, not NULL.

**Anti-pattern**: non-variadic, non-out-param bindings already checked by `improper_ctypes` are low-priority here.

**Source**: `glib` ≥0.15.0,<0.20.0 — shared `&p` passed to variadic `g_variant_get_child` out-param → C-side write dropped → NULL `*mut c_char` into `CStr::from_ptr` (RUSTSEC-2024-0429). See `supply-chain-ffi-research.md` §H04.

---

### CHECK 15 — Panic-safety: half-updated length leaves UAF

**Signal**: a manual-drop loop (`drop_in_place`, `ptr::drop`, element teardown) that updates the length/occupancy counter AFTER the loop rather than per-element, inside `clear`/`truncate`/`drain`/`Drop`.

**Procedure**:
1. `rg 'drop_in_place|ManuallyDrop|set_len|from_raw_parts' --type rust` inside teardown methods.
2. For each: if a caller-supplied `T::drop` panics mid-loop, is the container left in a state where a SECOND teardown re-touches freed elements? Invariant: length/occupancy must be decremented *before or as* each element is dropped, never only at the end.
3. **Reachability gate**: the panic must originate in caller-supplied `Drop`, so the bug is observable only if a `catch_unwind` boundary sits above the audited path (otherwise the first panic aborts). Confirm such a boundary exists.
4. Severity: HIGH if the container deserializes attacker-supplied data and a `catch_unwind` boundary exists (UAF/double-free). MEDIUM if the panic source is internal-only.

**Golden signature**: test with a `T` whose `Drop` panics on the k-th element inside `catch_unwind`, then re-invokes teardown and asserts no double-drop (run under Miri/ASan).

**Anti-pattern**: code compiled `panic = "abort"` end-to-end cannot observe this — the first panic aborts. Downgrade accordingly.

**Source**: `rkyv` ≥0.8.0,<0.8.16 — `InlineVec::clear`/`SerVec::clear` update `self.len` after the drop loop → re-drop on panicking `Drop` (CWE-415/416, RUSTSEC-2026-0122). See `supply-chain-ffi-research.md` §H07.

---

## Stage-3 PoC discipline

| Class | Backend | Command |
|-------|---------|---------|
| H01 (known-vuln dep) | cargo audit + cargo tree | `cargo audit --json` + `cargo tree -i <crate>` |
| H02 (FFI null) | Miri + manual test | `MIRIFLAGS="-Zmiri-disable-isolation" cargo miri test test_ffi_null_<ID>` |
| H03 (alloc mismatch) | Miri | `MIRIFLAGS="-Zmiri-disable-isolation -Zmiri-check-abi" cargo miri test` |
| H04 (malicious build.rs) | Manual audit | Read build.rs source + `strace -f cargo build` |
| H05 (unsafe third-party) | cargo geiger + cargo vet + manual | `cargo geiger --output-format Json` + manual unsafe-block audit |
| H06 (typosquat) | Name distance check + manual | Manual comparison to top-500 crates |
| H07 (repr(C) mismatch) | Side-by-side struct comparison | Compare Rust #[repr(C)] vs C header definition |
| H08 (symbol collision) | grep + manual | `rg '#\[no_mangle\]' --type rust` + name table |
| H09 (yanked crate) | cargo deny | `cargo deny check` |
| H10 (C-unwind) | Manual trace + Miri | `rg 'extern "C"' --type rust` + panic-site audit |
| H11 (FFI thread-safety) | Manual audit | `rg 'unsafe impl Send'` + C library docs |
| H12 (proc-macro) | cargo metadata + manual | `cargo metadata --format-version=1` + proc-macro source audit |
| CHECK 13 (safe raw-slice wrapper) | Miri | `MIRIFLAGS="-Zmiri-disable-isolation" cargo +nightly miri test` on misaligned/wrong-type pointer |
| CHECK 14 (variadic out-param `&`/`&mut`) | `--release` integration test + header diff | run binding under `--release`, assert out-value observed not NULL |
| CHECK 15 (panic-safety len UAF) | Miri/ASan + `catch_unwind` test | panic in `T::drop` at k-th element inside `catch_unwind`, assert no double-drop |

**Tier-1-formal**: For H02 (FFI null): Miri confirmation of UB. For H01: RustSec advisory + `cargo tree` reachability chain. For H10/CHECK 14: Miri / `--release` observation of the optimized-away write. For CHECK 13/CHECK 15: Miri/ASan trace of the UB. Without mechanical confirmation: max CONTESTED.

---

## Output fields beyond shared FINDING schema

```yaml
supply_chain_class: H01 | H02 | H03 | H04 | H05 | H06 | H07 | H08 | H09 | H10 | H11 | H12
cve_id: <CVE-YYYY-NNNNN | RUSTSEC-YYYY-NNNN | none>
dependency_chain: <output of `cargo tree -i <crate>`>
reachability_evidence: <the in-scope function that calls into the vulnerable code, with file:line>
ffi_boundary: <rust_function → c_function or c_function → rust_function>
fix_recommendation: <upgrade to vX.Y.Z | remove dep | add null check | add catch_unwind | replace with alternative>
verification_backend: cargo-audit | miri | manual | cargo-geiger | cargo-deny
```

---

## Anti-patterns (do NOT report)

- Dependency CVEs in test-only deps (`[dev-dependencies]`) that are not compiled into the deployed binary → Informational at most.
- CVEs that are matched but the vulnerable function is provably unreachable from in-scope code (file as Informational with reachability evidence, not High).
- "This crate has unsafe in it" without a specific unsoundness — that's `cargo geiger` output, not a finding. Use CHECK 5's risk-tiering; don't report every crate with `unsafe_ratio > 0`.
- `build.rs` that emits standard cargo directives (`cargo:rustc-link-lib=`, `cargo:rerun-if-changed=`) — legitimate build-system plumbing, not a finding.
- `extern "C" fn` with `// SAFETY:` comment that correctly documents all preconditions AND the caller satisfies them — safe by design, not a finding.
- `unsafe impl Send for T` on an FFI wrapper where the C library is DOCUMENTED as thread-safe — safe by construction.
- Well-known proc macros (`serde_derive`, `thiserror`, `derive_more`) from crates.io — ecosystem-standard, not findings per se. Only flag if the specific version has a known advisory.
- `std::collections::HashMap` in dependency code (SipHash → HashDoS-safe) — not a finding (different angle entirely).

---

## Coordination with other angles

- **Memory Safety (Angle 1)** picks up FFI bugs that produce concrete UB (Miri trace). Angle 8 finds the FFI binding pattern; Angle 1 confirms the UB.
- **Unsafe Trait Soundness (Angle 2)** owns `unsafe impl Send/Sync` in third-party code and in the audited codebase. Angle 8 reports the dependency's unsafe traits; Angle 2 determines soundness. CHECK 11 (FFI thread-safety) is split — Angle 8 owns the C library thread-safety label audit; Angle 2 owns the Rust trait impl soundness.
- **Concurrency (Angle 4)** owns the runtime race conditions that result from incorrect `Sync` impls (Loom). Angle 8 identifies the FFI wrapper; Angle 4 demonstrates the race.
- **Crypto Misuse (Angle 5)** owns vulnerable-crypto-dependency CVEs at the protocol level. Angle 8 reports the dependency; Angle 5 reports the protocol-level impact.
- **Resource Exhaustion (Angle 6)** owns the decompression-bomb and unbounded-allocation dimensions of vulnerable deps. Angle 8 reports the dependency; Angle 6 determines whether the vulnerability is reachable AND whether size caps mitigate it.
