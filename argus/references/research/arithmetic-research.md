# Arithmetic & Overflow — Research Dossier

> **Feeds**: hacking-agents/infra/arithmetic-agent.md
> **Last research pass**: 2026-06-05 · **Sources reviewed**: 8 verified advisories/incidents (primary-fetched) + 2 cross-language precedents (labeled) + 2 academic references
> **Status**: drafted-verified — every advisory id below was fetched against its primary source (rustsec.org / NVD-CVE / vendor post-mortem) confirming BOTH the identifier AND the mechanism. Unverifiable claims dropped or carried as `[generic pattern — no specific incident]` with no id.

> **Anchor case (Rust-native, verified)**: **RUSTSEC-2026-0007** (`bytes` < 1.11.1). `BytesMut::reserve` used an **unchecked `new_cap + offset`** in the unique-reclaim path. In a release build with overflow-checks set to wrap, that addition overflows, the `if v_capacity >= new_cap + offset` guard wrongly passes, the internal capacity field is set past the real allocation, and `spare_capacity_mut()` then hands out an **out-of-bounds slice → UB**. This is the canonical shape: an *unchecked add inside a guard condition* that flips the guard's truth value. It is invisible in debug (panics) and only triggers in the configuration most DLT release profiles actually ship. Source: https://rustsec.org/advisories/RUSTSEC-2026-0007.html

---

## 0. Calibration headline (read first)

Arithmetic bugs in Rust DLT infrastructure split into three damage classes, each confirmed by a fetched primary source:

1. **Memory corruption** — overflow in a *size/capacity* calculation produces an undersized buffer, then unsafe code writes past it. Verified: `base64::encode_config_buf` size overflow (RUSTSEC-2017-0004, CVSS 9.8), `std::str::repeat` capacity overflow (CVE-2018-1000810, CVSS 9.8), `bytes::BytesMut::reserve` capacity overflow (RUSTSEC-2026-0007). This is the deadliest class and bridges to the Memory-Safety angle.
2. **Wrong-value / financial** — wrapping or rounding silently produces a wrong number that downstream accounting trusts. Verified: `cosmwasm-std` `pow`/`neg` wrapping instead of panicking (RUSTSEC-2024-0338); Kamino Lending exchange-rate rounding letting a depositor redeem more than deposited (Certora post-mortem).
3. **Panic / chain-halt DoS** — a `checked_*().unwrap()`, a `/`-by-`-1` on `MIN`, an underflow, or an overflow-check-enabled arithmetic op panics on attacker-reachable input. Verified: `untrusted` integer underflow → panic (RUSTSEC-2018-0001); `ring` AES/QUIC arithmetic panic when `overflow-checks = true` (RUSTSEC-2025-0009) — the *inverse* footgun, where the standard hardening flag becomes the DoS.

**The single most important calibration fact**: in Rust, **overflow behavior is a build-profile property, not a language guarantee**. The Rust Reference is explicit — integer operators "panic when they overflow when compiled in debug mode," and `-C overflow-checks` controls this; in release mode without that flag, `+`, `*`, binary `-` **wrap** (two's complement). Solana BPF, and most production DLT release profiles, ship without overflow checks. So an auditor must (a) read the actual `[profile.release]` `overflow-checks` setting, and (b) recognize that *enabling* the flag (RUSTSEC-2025-0009) converts every reachable wrap into a panic-DoS — neither default is automatically safe.

**Three traps the model must not fall into** (each is a fabrication the prior draft made — corrected here):
- Wormhole's $326M loss was a **guardian signature-verification bypass** (`load_instruction_at` spoofing in `verify_signatures`), **not** a u256→u64 amount truncation. Do **not** cite Wormhole for arithmetic.
- Binance Bridge / BSC Token Hub's $570M loss was an **IAVL Merkle-proof forgery** (proof verification ignored the right-hand leaf), **not** a governance-parameter overflow. Do **not** cite it for arithmetic.
- The SPL **Token-2022** transfer-fee bug was **fee-not-subtracted** (pre-fee amount used in a verification step), **not** an `amount * fee_bps` overflow-before-division; the `TransferFee` math uses `u128`/checked internally. Do **not** describe Token-2022 fee math as an overflow.

---

## 1. Bug-class taxonomy

| Class | One-line mechanism | Real instance (verified source) | Argus coverage |
|-------|--------------------|----------------------------------|----------------|
| **A1 Unchecked multiply before division** | `amount * factor / divisor` — intermediate product overflows the type before division brings it back in range | `[generic pattern — no specific Rust incident verified]`; cross-language: BeautyChain BEC `cnt * _value` (Solidity, arXiv:2504.07419) | **PARTIAL** — C02 covers `len * elem_size` allocation only, not the `a*b/c` value-math shape |
| **A2 Width-narrowing cast truncation** | `u128 as u64`, `u64 as u32`, `usize as u32` — high bits silently dropped (Rust Reference: "casting from a larger integer to a smaller integer will truncate") | `[generic pattern]` — bridge 256→64 amount narrowing; no specific Rust advisory fetched | **YES** — C04 covers `u64 as usize`/`u64 as u32`; extend to wider sources |
| **A3 Subtraction underflow flips a guard** | `a - b` wraps to a huge value when `b > a`, so a `< limit` guard wrongly passes; or `a == b → 0`, and `0 < limit` also passes | **RUSTSEC-2026-0007** `bytes` (`new_cap + offset` overflow flips `>=` guard) — verified; `[generic pattern]` Monero `(highest - len) < ring_size` (no numbered finding) | **YES** — angle §Underflow already cites the guard-flip shape |
| **A4 Size/capacity-calc overflow → OOB write** | overflow in a buffer-size multiply/add yields an undersized allocation; unsafe write goes past it | **RUSTSEC-2017-0004** `base64` (CVSS 9.8), **CVE-2018-1000810** `str::repeat` (CVSS 9.8), **RUSTSEC-2026-0007** `bytes` — all verified | **PARTIAL** — C02 is the closest; broaden to add *and* multiply in size math |
| **A5 Wrapping where panic was expected** | a math op silently wraps for large inputs instead of panicking, so callers get a wrong result with no error | **RUSTSEC-2024-0338** `cosmwasm-std` `Uint/Int{256,512}::pow`, `::neg` always wrap; `{64,128}` variants wrap when `overflow-checks` unset — verified | **NO** — angle has no "wrapping-vs-panic contract" check |
| **A6 Division rounding direction (value leak)** | integer `/` truncates; redeem/exchange-rate math that rounds the *wrong way* lets a user extract more than owed | Kamino Lending KLend: `Fraction::from(supply)/total_liquidity` rounds **down**, then `collateral / rate` rounds **up** → redeem > deposit (Certora, verified); cross-language: Abracadabra MIM rebase rounding (Solidity) | **NO** — no rounding-direction methodology |
| **A7 `checked_*().unwrap()` panic DoS** | the `Option`/`Result` from a checked op is unwrapped, converting a recoverable overflow into an unrecoverable panic | **RUSTSEC-2018-0001** `untrusted` underflow→panic (verified, DoS); `[generic pattern]` Cosmos `Coins.Add` panics (Go, cross-language) | **NO** — no panic-as-DoS class |
| **A8 Overflow-check flag becomes the DoS** | enabling `overflow-checks = true` makes a previously-wrapping op *panic* on attacker-reachable large input | **RUSTSEC-2025-0009** `ring` AES/QUIC `new_mask()` panics with overflow-checks on (verified) | **NO** — not covered; subtle, important for DLT release profiles |
| **A9 Out-of-bounds index → panic** | attacker-controlled index used unchecked; Rust bounds-checks and panics (DoS, not OOB read) | **RUSTSEC-2023-0039** out-of-bounds array access → panic (verified via RustSec summary) | **PARTIAL** — overlaps memory/DoS angles |
| **A10 Signed→unsigned reinterpretation** | `-1_i64 as u64 == u64::MAX` (Rust Reference: same-size cast is a 2's-complement no-op) — a negative delta becomes a huge positive | `[generic pattern — no specific incident]` | **NO** — detection procedure absent |
| **A11 Governance-parameter-driven overflow** | a governance-settable multiplier/timeout/cap set to an extreme value overflows downstream math | `[generic pattern — no specific incident]` (do NOT cite Binance Bridge — that was Merkle forgery) | **NO** — no systematic substitute-MAX trace |
| **A12 Accumulated-sum overflow** | a monotonic `total_* += x` accumulator overflows after many operations | `[generic pattern — no specific incident]` | **NO** — angle covers per-op overflow only |
| **A13 `/` or `%` by `MIN / -1`** | signed `i::MIN / -1` overflows; Rust Reference: this panics "even when `-C overflow-checks` is disabled" | Rust Reference (language semantics, verified) | **NO** — distinct from div-by-zero; always-panics edge |

---

## 2. Per-class methodology

> Each procedure is written to find the bug **without already knowing the answer**. The `[BOUNDARY]`/`[TRACE]` tags mark the mechanical evidence shape.

### A1 — Unchecked multiply before division
- **Signal**: expression of shape `a * b / c` where `a`, `b` are both ≤ the same unsigned width and neither is provably bounded.
- **Procedure**:
  1. For each `a * b / c`: compute `max(a) * max(b)`. If it exceeds `type::MAX`, the product overflows *before* division ever runs.
  2. Check the intermediate width: `(a as u128) * (b as u128) / (c as u128)` is safe (u64·u64 fits u128); `a * b / c` at u64 is not.
  3. Check for `a.checked_mul(b).and_then(|x| x.checked_div(c))` — present ⇒ safe.
  4. Confirm the divisor genuinely shrinks the result; if the code reuses the *intermediate* product elsewhere, the widening doesn't help there.
- **Mechanical evidence**: Kani harness over `kani::any()` for `a`,`b` → counterexample where `a*b > u64::MAX` and no `checked_mul`/`u128` widening.
- **Anti-pattern (false-positive guard)**: if `[profile.release] overflow-checks = true` is set, the wrap becomes a panic — reclassify as A8 (DoS), not silent-value. Always read the profile first.
- **Source**: Rust Reference "overflow" (https://doc.rust-lang.org/reference/expressions/operator-expr.html#overflow); cross-language overflow-before-op precedent BeautyChain BEC in arXiv:2504.07419 (Solidity — labeled).

### A2 — Width-narrowing cast truncation
- **Signal**: `as` from a wider integer to a narrower one (`u128 as u64`, `u64 as u32`, `usize as u32`, any `as` at a chain/protocol boundary).
- **Procedure**:
  1. Enumerate every narrowing `as`. For each, establish the source's plausible range (user-supplied? a cumulative sum? a cross-chain amount?).
  2. If the source can exceed `dest::MAX`, the high bits are silently dropped — Rust Reference: `0xabcdu16 as u8 == 0xcdu8`.
  3. Replace with `u64::try_from(x)` (returns `Err` on loss) and check whether the surrounding code would handle that error or just `.unwrap()` it (→ A7).
  4. For bridge/IBC amounts, trace the *narrowest* integer type along the whole value path; that point is the vulnerability.
- **Mechanical evidence**: assert `(src as Dest) as Src == src`; Kani finds the smallest `src` that violates it.
- **Anti-pattern**: source provably bounded (loop counter < `u32::MAX`). Don't flag a value the type system or a prior assertion already bounds.
- **Source**: Rust Reference "type cast expressions" (verified). Bridge 256→64 carried as `[generic pattern]` — no specific Rust advisory confirmed.

### A3 — Subtraction underflow / addition overflow flips a guard
- **Signal**: an arithmetic expression *inside* a comparison: `if a - b < limit`, `if cap >= new + offset`.
- **Procedure**:
  1. For each guard with arithmetic in it, ask: can the inner expression overflow/underflow under attacker input? If yes, evaluate the guard at the wrap value.
  2. **RUSTSEC-2026-0007 shape**: `if v_capacity >= new_cap + offset` — when `new_cap + offset` wraps to a tiny number, the `>=` passes for *any* capacity. Check whether the addition is `checked_add`.
  3. **Underflow shape**: `if (highest - len) < ring_size` — when `len > highest`, `highest - len` wraps huge and `< ring_size` fails-closed *or* passes depending on direction; also test `len == highest` (`0 < ring_size` is true).
  4. Trace **both** the comparison result and the arithmetic result — a guard can fail at the wrap value *and* at the zero-result boundary.
- **Mechanical evidence**: `[BOUNDARY]` substitution — set the inner expression operands to the wrap/zero boundary and assert the guard takes the unintended branch.
- **Source**: RUSTSEC-2026-0007 (verified, Rust-native anchor). Monero ring-size guard carried as `[generic pattern — no numbered finding]`.

### A4 — Size/capacity-calc overflow → OOB write
- **Signal**: any `Vec::with_capacity(...)`, `reserve(...)`, manual `alloc` size, or pre-sized buffer where the size is computed by `*` or `+` from non-constant inputs, followed by `unsafe` writes.
- **Procedure**:
  1. Find every buffer-size computation feeding an allocation that is later written via `unsafe`/`set_len`/`spare_capacity_mut`/raw pointer.
  2. Check whether the size math is `checked_*` or widened. `len * copies` (str::repeat), `input_len → encoded_len` (base64), `new_cap + offset` (bytes) all overflowed because the size math wasn't checked.
  3. If the size can wrap to a value smaller than the data actually written → OOB write → memory corruption (escalate to Memory-Safety angle; these were CVSS 9.8).
- **Mechanical evidence**: MIRI under the overflowing input — OOB write surfaces as UB; or a unit test that writes the true length into the under-sized buffer and observes corruption.
- **Source**: RUSTSEC-2017-0004 (base64), CVE-2018-1000810 (str::repeat), RUSTSEC-2026-0007 (bytes) — all verified.

### A5 — Wrapping where a panic was expected
- **Signal**: arithmetic on a fixed-precision big-int type (`Uint256`, `Int512`, custom `Fraction`), or any `pow`/`neg`/`<<` on a value that can be large; *and* a `[profile.release]` without `overflow-checks = true`.
- **Procedure**:
  1. Identify the type's documented overflow contract. `cosmwasm-std` `Uint{256,512}::pow` / `Int{256,512}::pow` / `::neg` **wrap regardless of the profile flag** (RUSTSEC-2024-0338); the 64/128 variants wrap only when `overflow-checks` is unset.
  2. For each such op on attacker-influenced magnitude, ask whether downstream accounting assumes it panicked-on-overflow (i.e., trusts the result is exact). If so, the wrap produces a wrong-but-accepted value.
  3. Recommend `checked_pow`/`checked_*` explicitly rather than relying on the profile flag, because the 256/512 variants ignore it.
- **Mechanical evidence**: call the op at the documented-wrapping magnitude and assert the result ≠ the true mathematical value.
- **Source**: RUSTSEC-2024-0338 (verified). This is the class the prior draft missed entirely.

### A6 — Division rounding direction (value leak)
- **Signal**: any integer `/` (or fixed-point divide) in a redeem / exchange-rate / share / fee-distribution path.
- **Procedure**:
  1. For a two-step rate flow (`rate = supply / liquidity`, then `out = amount / rate`), determine the rounding direction of *each* step. Kamino's bug: step 1 rounds **down** (stored rate slightly low), step 2 divides by the low rate and rounds **up** → output too high → redeem > deposit.
  2. The invariant to assert: a round-trip (deposit → redeem, or shares → assets → shares) must never return *more* than the user put in. If any composition of rounding directions can violate this, it's a leak.
  3. Prefer the **Mul-Div** form `amount * total_liquidity / total_supply` with a single floor at the end (Kamino's fix) over a pre-divided stored rate — fewer rounding sites, all in the protocol's favor.
  4. Establish the precondition magnitude: Kamino required collateral > 2^59 (≈ $216M), currently infeasible — so severity is gated by reachable magnitudes. Always compute the threshold input, don't assume "unreachable."
- **Mechanical evidence**: property test of the round-trip invariant `redeem(deposit(x)) <= x` across the input range; report the smallest `x` that breaks it.
- **Source**: Kamino Lending / Certora (verified, Solana-native). Abracadabra MIM rebase rounding carried as cross-language (Solidity, labeled).

### A7 — `checked_*().unwrap()` panic DoS
- **Signal**: `checked_add`/`checked_sub`/`checked_mul`/`checked_div` immediately followed by `.unwrap()` / `.expect()`; or any subtraction that can underflow in a code path reachable from untrusted input.
- **Procedure**:
  1. Grep `checked_\w+\(.*\)\.(unwrap|expect)`. For each, classify the call site: consensus/block-production code (chain-halt = Critical), tx handler (griefing DoS = High), view/query (informational).
  2. Confirm the operands are attacker-influenced; if so, the `unwrap()` converts a recoverable `None` into an unrecoverable panic.
  3. For Substrate/CosmWasm runtime code, a panic in on-chain execution aborts the block/extrinsic — assess whether that halts liveness.
- **Mechanical evidence**: `[TRACE]` the untrusted input to the `unwrap()` and supply the value that yields `None`.
- **Source**: RUSTSEC-2018-0001 `untrusted` underflow→panic (verified). Cosmos `Coins.Add` panic carried as cross-language `[generic pattern]` (Go).

### A8 — The `overflow-checks` flag itself becomes the DoS
- **Signal**: `[profile.release] overflow-checks = true` (good hygiene) **plus** arithmetic on a large attacker-controlled magnitude in hot/crypto/serialization paths.
- **Procedure**:
  1. After confirming overflow-checks is on, do NOT stop — now every reachable wrap is a *panic*. Re-scan the same arithmetic for attacker-reachable large inputs.
  2. RUSTSEC-2025-0009 shape: `ring::aead::quic::HeaderProtectionKey::new_mask()` panics on a crafted QUIC packet only because overflow-checks turn the internal arithmetic overflow into a panic; AES-GCM panics near 64 GiB single-chunk.
  3. Recommend `wrapping_*`/`saturating_*`/`checked_*` *at the specific hot op* rather than relying on the global flag, so hardening one path doesn't open a DoS on another.
- **Mechanical evidence**: build with `overflow-checks = true`, feed the crafted large input, observe panic; build without, observe wrap — the two profiles diverge.
- **Source**: RUSTSEC-2025-0009 (verified). This inversion is the subtlest class and is unique to Rust's profile-dependent overflow model.

### A11 — Governance-parameter-driven overflow
- **Signal**: an arithmetic operand sourced from a governance-settable value (fee rate, timeout-epochs, reward multiplier, cap).
- **Procedure**:
  1. List every governance-settable parameter that participates in arithmetic.
  2. Substitute each with `type::MAX` (or its widest admitted value) and `[TRACE]` downstream until the value hits a `checked_*`, a clamp, or a bound assertion.
  3. If any op wraps/panics at the extreme and there is no range assertion on the setter (or a too-wide one like `assert!(fee_bps > 0)`), flag it.
- **Severity**: governance is trusted → apply TRUSTED-ACTOR downgrade, but report at Medium with a governance-trust note (a fat-fingered or compromised setter is realistic).
- **Source**: `[generic pattern — no specific incident verified]`. Explicitly **not** Binance Bridge (that was a Merkle-proof forgery, not arithmetic).

### A12 — Accumulated-sum overflow
- **Signal**: a monotonically increasing state field: `total_fees`, `total_staked`, `cumulative_rewards`, mint-tracked `total_supply`.
- **Procedure**: for each `+=` site, bound `max_increment * max_operations_over_lifetime`; if it can exceed `type::MAX`, flag. Confirm `checked_add`/`saturating_add`; if `saturating_add`, verify downstream consumers tolerate a pinned-at-MAX accumulator.
- **Source**: `[generic pattern — no specific incident verified]`.

### A13 — `/` or `%` by `MIN / -1` (always-panics edge)
- **Signal**: signed division/remainder where the dividend can be `i::MIN` and the divisor can be `-1`.
- **Procedure**: the Rust Reference states this overflow is checked "even when `-C overflow-checks` is disabled" — i.e., it **always panics**, in every profile. For any signed `/`/`%` reachable from untrusted input, supply `(i::MIN, -1)` and confirm a guard exists.
- **Source**: Rust Reference "overflow" (verified language semantics).

---

## 3. Framework-specific knowledge

### Rust language / build profile (the root fact)
- Overflow behavior is **profile-dependent**, not guaranteed: debug panics; release **wraps** unless `-C overflow-checks` / `[profile.release] overflow-checks = true` is set (Rust Reference, verified).
- `as` narrowing **truncates silently** (`1234u16 as u8 == 210`); same-size signed↔unsigned is a 2's-complement no-op (`-1i8 as u8 == 255`); widening zero-/sign-extends (Rust Reference, verified).
- Signed `i::MIN / -1` and `i::MIN % -1` panic **regardless** of overflow-checks (Rust Reference, verified) — the one overflow you can't disable.
- Enabling overflow-checks is good hygiene but converts every reachable wrap into a panic-DoS — see RUSTSEC-2025-0009. Neither default is automatically safe.

### Solana / BPF
- BPF release builds inherit Rust's release wrapping; `[profile.release] overflow-checks = true` is the standard fix and its cost is "almost negligible in Solana" (Sec3, citing real `jet-v1` and Solana-runtime `checked_*`/`saturating_*` fixes — verified).
- `u64` is the native SPL token amount; deserialized amount fields are unbounded by the runtime — the program owns its own checks.
- Precision-loss in fixed-point rate types is the Solana-native financial-loss shape: Kamino's `Fraction` (60-bit fractional) round-down→divide round-up (Certora, verified). The fix is Mul-Div with a single trailing floor.
- **Do not** describe SPL **Token-2022** transfer-fee math as an overflow — the documented bug was fee-not-subtracted; the `TransferFee` arithmetic uses `u128`/checked internally.

### CosmWasm (Rust)
- `Uint128/256/512`, `Int*` provide checked ops, **but** `Uint{256,512}::pow` / `Int{256,512}::pow` / `Int{256,512}::neg` **wrap silently regardless of `overflow-checks`**, and the 64/128 `pow`/`neg` wrap when the flag is unset (RUSTSEC-2024-0338, verified). Patched in 1.4.4 / 1.5.4 / 2.0.2. Recommend explicit `checked_pow`.
- `Decimal`/`Decimal256` are 18-dp fixed-point; `Decimal::from_ratio(a, b)` computes `a * 10^18 / b` and panics on `b == 0` — a div-by-zero DoS surface if `b` is state-derived.

### Substrate / Polkadot
- `Balance` is typically `u128` (max ≈ 3.4e38 — hard to overflow), but `BlockNumber` is commonly `u32`; `current_block + N` with large `N` wraps in release without overflow-checks. Runtime arithmetic should use `checked_*`/`saturating_*` (FRAME idiom) precisely because a panic in block execution affects liveness.
- `[generic pattern]`: no Substrate-runtime arithmetic RUSTSEC advisory was confirmed in this pass; treat Substrate arithmetic findings as pattern-driven, not precedent-anchored.

### Move (Aptos / Sui) — contrast
- Move arithmetic and `as` **abort** on overflow/loss rather than wrapping. This eliminates the silent-value class but introduces an abort-DoS class symmetric to A7/A8.

---

## 4. Tooling

| Tool | What it checks | Golden signature | Invoke |
|------|---------------|------------------|--------|
| **Read the profile FIRST** | `[profile.release] overflow-checks` decides whether a wrap is silent (A1/A5) or a panic (A8) | the literal line in `Cargo.toml` | `grep -A5 'profile.release' Cargo.toml` |
| **Kani** | bounded proof of no-overflow, or a concrete counterexample | `VERIFICATION FAILED` + concrete `(a,b)` | `cargo kani --harness h --unwind N` |
| **MIRI** | UB from overflow-driven OOB write (A4) | MIRI error on the OOB write | `cargo +nightly miri test` |
| **Clippy** | `cast_possible_truncation`, `cast_sign_loss`, `arithmetic_side_effects` | warning lines on `as`/arithmetic | `cargo clippy -- -W clippy::cast_possible_truncation -W clippy::cast_sign_loss -W clippy::arithmetic_side_effects` |
| **Proptest / cargo-fuzz** | round-trip and no-overflow properties over random inputs (A6 leak, A1/A12) | minimized failing input | `cargo test` (proptest) / `cargo +nightly fuzz run t` |
| **overflow-checks = true (as a test)** | flips silent wraps to panics so a fuzzer can *find* them — but ship-time it's the A8 trade-off | runtime panic at the wrap | set in `[profile.release]` |

---

## 5. Discovery calibration

- **Tooling is strong for the mechanical half**: Kani/cargo-fuzz find "this can overflow" reliably for bounded functions. They do **not** know whether it matters.
- **The LLM's job is the impact trace and the profile read**: classify each reachable overflow into memory-corruption (A4 → CVSS-9.8 class), financial (A5/A6), or DoS (A7/A8/A9/A13), and — critically — read `overflow-checks` to know whether a given wrap is silent or a panic. The same code is class A1 with the flag off and class A8 with it on.
- **Highest-ROI manual checks**: A6 rounding-direction (one round-trip invariant catches Kamino-class leaks that fuzzers miss without the right property), A8 overflow-checks inversion (a one-line `Cargo.toml` read changes every other verdict), and A5 wrapping-contract per big-int type (RUSTSEC-2024-0338 shows even "safe" types have wrapping ops).
- **False-positive discipline**: never flag `Wrapping<T>`/`Saturating<T>` (the type encodes intent), a cast on a provably-bounded source, or a wrap that the profile turns into a checked panic.

---

## 6. Gaps → angle changes

| Methodology | Change type | Anti-bloat: does an existing check cover it? |
|-------------|-------------|----------------------------------------------|
| **A5 wrapping-vs-panic contract** — per big-int type, identify ops that wrap regardless of `overflow-checks` (e.g. cosmwasm `Uint256::pow`); require explicit `checked_*` | new-check | Nothing covers "the type is checked but *this op* isn't." NOT covered. Anchored by RUSTSEC-2024-0338. |
| **A8 overflow-checks inversion** — after confirming `overflow-checks = true`, re-scan hot/crypto/serialization arithmetic for attacker-reachable panic-DoS | new-check | No check treats the hardening flag as a DoS source. NOT covered. Anchored by RUSTSEC-2025-0009. |
| **A6 rounding-direction round-trip invariant** — assert `redeem(deposit(x)) <= x` across the range; flag any composition where stored-rate rounding lets output round up | new-check | No rounding-direction methodology exists. NOT covered. Anchored by Kamino/Certora. |
| **A4 size-calc overflow (add *and* multiply)** — broaden C02 from `len*elem_size` to any `+`/`*` feeding an allocation later written via unsafe | extend C02 | C02 is multiply-only and allocation-shape-specific; RUSTSEC-2026-0007 was an *add*, base64/str::repeat were size *multiplies*. Extend. |
| **A3 guard-flip via inner arithmetic** — when a comparison contains `+`/`-`, evaluate the guard at the wrap/zero boundary | extend underflow §| Angle covers subtraction underflow; add the addition-overflow-inside-`>=` shape (RUSTSEC-2026-0007). Small extend. |
| **A1 `a*b/c` value-math** — distinct from C02 allocation overflow: check widening/`checked_mul` for fee/share math | new-check | C02 is allocation-only. The value-math fix (u128 intermediate / checked) and impact (wrong value) differ. NOT covered. |
| **A7 `checked_*().unwrap()` panic-DoS** — grep + reachability + call-site severity (consensus vs tx vs query) | new-check | No panic-as-DoS class. NOT covered. Anchored by RUSTSEC-2018-0001. |
| **A2 narrowing-cast + `try_from` fix** — extend C04 to wider sources (u128→u64) and recommend `try_from` over `as` | extend C04 | C04 stops at `u64 as u32`. Extend, don't add. |
| **A13 `i::MIN / -1` always-panics edge** — one targeted check for signed `/`/`%` on untrusted input | new-check (small) | Distinct from div-by-zero; panics even with overflow-checks off (Rust Reference). NOT covered. |
| **Profile read as Phase-1 step** — `grep overflow-checks Cargo.toml` seeds every other arithmetic verdict | tool-integration | No current step reads the profile; it changes the silent-vs-panic classification globally. +2 lines to Phase 1. |
| **Clippy seed list** — `cast_possible_truncation`, `cast_sign_loss`, `arithmetic_side_effects` as a pre-seeded manual-audit list | tool-integration | No tool step currently. +2 lines to Phase 1. |

---

## 7. Sources

> Every id below was fetched against a primary source confirming **both** the identifier **and** the mechanism on the access date. Cross-language precedents are labeled. Unverifiable claims appear only as `[generic pattern — no specific incident]` in sections 1–2 with no id attached.

**Tier 1/2 — verified advisories & post-mortems with root cause + fix** (accessed 2026-06-05)
- **RUSTSEC-2026-0007 / CVE-2026-25541** — `bytes` < 1.11.1, `BytesMut::reserve` unchecked `new_cap + offset` overflow flips a `>=` guard → corrupted capacity → OOB slice via `spare_capacity_mut()` → UB. https://rustsec.org/advisories/RUSTSEC-2026-0007.html
- **RUSTSEC-2017-0004 / CVE-2017-1000430** — `base64` < 0.5.2, integer overflow in `encode_config_buf`/`encode_config` buffer-size calc → undersized buffer → unsafe OOB write → memory corruption / possible code exec. CVSS 9.8. Fix: checked arithmetic for buffer size. https://rustsec.org/advisories/RUSTSEC-2017-0004.html
- **CVE-2018-1000810** — Rust `std::str::repeat` (std 1.26.0–1.29.0), capacity = `len * copies` multiply overflow → undersized buffer → OOB write. CVSS 9.8. https://rustsec.org/advisories/CVE-2018-1000810.html
- **RUSTSEC-2024-0338 / CVE-2024-58263** — `cosmwasm-std`, `Uint{256,512}::pow`/`Int{256,512}::pow`/`Int{256,512}::neg` wrap on overflow **regardless** of profile; `Uint/Int{64,128}::pow`/`neg` wrap when `overflow-checks` unset → wrong contract calculations. Patched 1.4.4 / 1.5.4 / 2.0.2. https://rustsec.org/advisories/RUSTSEC-2024-0338.html
- **RUSTSEC-2025-0009 / CVE-2025-4432** — `ring` < 0.17.12, AES/QUIC arithmetic panics **when `overflow-checks` is enabled**: `quic::HeaderProtectionKey::new_mask()` via crafted QUIC packet; AES-GCM near 64 GiB single-chunk → panic DoS. https://rustsec.org/advisories/RUSTSEC-2025-0009.html
- **RUSTSEC-2018-0001 / CVE-2018-20989** — `untrusted` < 0.6.2, error-handling mistake → integer underflow → panic (DoS) when callers mis-check errors. https://rustsec.org/advisories/RUSTSEC-2018-0001.html
- **RUSTSEC-2023-0039** — out-of-bounds array index from attacker-controlled input → panic (DoS). https://rustsec.org/advisories/RUSTSEC-2023-0039.html
- **Kamino Lending (KLend) precision-loss** — Certora post-mortem: exchange-rate `Fraction::from(supply)/total_liquidity` rounds **down**, then redeem `collateral/rate` rounds **up** → redeem > deposit; precondition collateral > 2^59 (≈ $216M, currently infeasible on Solana); fix = Mul-Div `collateral * total_liquidity / total_collateral_supply` with trailing floor. https://www.certora.com/blog/securing-kamino-lending

**Cross-language precedents (labeled — weaker, never a primary Rust anchor)**
- **BeautyChain (BEC) token, Apr 2018** — Solidity `batchTransfer`: `uint256(cnt) * _value` multiply overflow → unbacked token mint. Cited in arXiv:2504.07419 as the overflow exemplar. (Solidity.) https://arxiv.org/html/2504.07419v1
- **Abracadabra "Magic Internet Money" (MIM) rebase rounding** — Solidity cauldron-v4 rebase library mishandled elastic==0/base≠0 → repeated rounding exploit. (Solidity; reported by Blockworks.) https://blockworks.com/news/rounding-exploit-magic-internet-money

**Tier 4 — language/framework references (verified semantics)**
- The Rust Reference — Operator expressions: integer overflow (debug-panic / release-wrap / `overflow-checks`), `i::MIN / -1` always-panics, numeric `as` truncation/extension semantics. https://doc.rust-lang.org/reference/expressions/operator-expr.html
- Sec3 — "Understanding Arithmetic Overflow/Underflows in Rust and Solana Smart Contracts" — release-mode wrapping, `overflow-checks` negligible cost on Solana, real `jet-v1` / Solana-runtime `checked_*`/`saturating_*` fixes. https://sec3.dev/blog/understanding-arithmetic-overflow-underflows-in-rust-and-solana-smart-contracts

**Tier 5 — academic (existence + relevant content verified; full-text where free)**
- arXiv:2504.07419 — "Exploring Vulnerabilities and Concerns in Solana Smart Contracts" — classifies arithmetic overflow/underflow and floating-point precision as distinct classes; notes accumulating rounding/truncation error; references "Blockworks Checked Math" tool. (Attack table lists oracle/flash-loan/operational incidents, **not** arithmetic — so do not cite that table for arithmetic losses.) https://arxiv.org/html/2504.07419v1
- VRust (CCS 2022) — "VRust: Automated Vulnerability Detection for Solana Smart Contracts," Cui et al. — automated detector that models integer overflow as one of its vulnerability classes; reported 12 previously-unknown vulnerabilities incl. 3 critical confirmed in the official Solana Program Library. (Full text paywalled at ACM; claims confirmed via the ACM DOI listing/index.) https://dl.acm.org/doi/10.1145/3548606.3560552

**Tier 6 — tooling**
- Kani: https://github.com/model-checking/kani
- cargo-fuzz: https://github.com/rust-fuzz/cargo-fuzz
- proptest: https://github.com/proptest-rs/proptest
- RustSec advisory database (index of all of the above): https://rustsec.org/advisories/

---

## 8. Immediate action items

1. Wire **A5 (wrapping-vs-panic contract)** and **A8 (overflow-checks inversion)** into the arithmetic agent — both are new classes with verified Rust-native anchors (RUSTSEC-2024-0338, RUSTSEC-2025-0009) that the prior draft missed.
2. Add **A6 rounding-direction round-trip invariant** (Kamino/Certora anchor) — a single property test catches a financial-loss class no overflow detector finds.
3. Make **"read `[profile.release] overflow-checks`"** a Phase-1 step — it reclassifies every other arithmetic verdict between silent-value and panic-DoS.
4. Extend **C02** to add-and-multiply size math (RUSTSEC-2026-0007 was an add; base64/str::repeat were multiplies) and **C04** to wider narrowing casts with a `try_from` recommendation.
5. Add **A7 `checked_*().unwrap()` panic-DoS** and **A13 `i::MIN / -1`** as small targeted checks.
6. Mark Arithmetic as `drafted-verified` in RESEARCH-INDEX.md.

---

> **AI-provenance reminder**: This dossier was assembled by an AI agent from web-fetched primary sources. Every advisory id and incident was verified against rustsec.org / NVD-CVE / the vendor post-mortem on 2026-06-05, but **a human must independently re-confirm each citation, version range, and mechanism against the live primary source before this dossier informs an agent file or a delivered finding.** Advisory contents and live pages can change; the live source wins. Do not treat any claim here as ground truth without manual validation.
