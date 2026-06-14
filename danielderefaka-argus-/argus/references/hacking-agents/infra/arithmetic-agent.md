# Arithmetic & Overflow Agent (`infra` mode — Angle 3)

**Load also**: [`depth-methodology.md`](depth-methodology.md) — depth disciplines (attack-surface enum, pre-auth panic sweep, asymmetric-cost quantification, resource bounds, cross-domain deps, boundary checklist, §WRITE-THEN-VERIFY). Mandatory in Core + Thorough tiers; optional in Light.

> **Calibration**: Arithmetic bugs in DLT infrastructure split into three damage classes. **(1) Financial loss** — wrapping/truncation in token amounts, fee calculations, reward distributions. A `u64` amount that overflows silently becomes a tiny (or zero) amount; division truncation leaks fractional value every operation. **(2) Chain halt / DoS** — `unwrap()` on `checked_*` in validator code (Cosmos SDK `Coins.Add`, Tendermint BeginBlock). One bad arithmetic op → every validator panics → chain halts. **(3) Memory corruption** — overflow in allocation size → undersized buffer → OOB write (bridges to Angle 1).
>
> The modal bug class is **unchecked multiplication before division** — `amount * fee / DIVISOR` overflows the intermediate product even when the final result fits. The second-most-common is **silent truncation on cast** — especially at cross-chain boundaries (u256→u64). The deadliest class is **"this can't overflow in practice"** reasoning — governance parameters, user-controlled amounts, and accumulated sums make any bound that isn't mechanically enforced a candidate.
>
> **Tool coverage is strong** — Kani and cargo-fuzz can find overflow counterexamples mechanically. The LLM's advantage is tracing overflow to IMPACT (allocation→OOB, balance→loss, validator→halt), which tools don't do.

**Primary verification backend**: Kani (`cargo kani`). Group C vectors are bounded-model-checking-decidable: write a harness asserting the property holds for all bounded inputs, Kani finds a counterexample or proves absence. Vectors in **Group C** (`dlt-infra-attack-vectors.md`) are your catalogue.

---

## Phase 1: Pre-seed from tooling

Before manual analysis, seed your audit with mechanical findings:

1. **Run `cargo clippy`** with cast lints:
   ```
   cargo clippy -- -W clippy::cast_possible_truncation -W clippy::cast_sign_loss -W clippy::cast_precision_loss -W clippy::cast_abs_to_unsigned -W clippy::arithmetic_side_effects
   ```
   Every warning is a seeded cast site — you verify each one for reachability from untrusted input. `arithmetic_side_effects` additionally flags every unchecked `+`/`-`/`*` so the wrap-capable ops surface alongside the casts.

2. **Run `cargo audit`** (or `cargo deny check advisories`). Flag every advisory with "overflow", "arithmetic", "checked", "wrapping", "truncation", or "cast" keywords. These name exact file/function/version deltas.

3. **Profile check**: read `Cargo.toml` `[profile.release]`. If `overflow-checks = false` (or absent — the default for release) AND the target is Solana BPF → wrapping is the runtime contract. Every `+`/`-`/`*` on untrusted input is a candidate.

---

## Phase 2: Arithmetic surface inventory

Enumerate every arithmetic surface:

- **Untrusted-input origin**: `u64`/`u128`/`usize` values from network input, RPC parameters, deserialized messages (`#[derive(BorshDeserialize)]`), or untrusted callers.
- **Governance-settable parameters**: fee rates, timeouts, multipliers, caps, reward rates — any value a governance proposal can change.
- **Accumulator variables**: `total_*`, `cumulative_*`, `sum_*` — any state variable that only increases.
- **Cross-boundary casts**: every `as` converting between integer widths, especially at chain/bridge boundaries.
- **Division sites**: every `/` and `%` in value-distribution paths (fees, rewards, shares, exchange rates).

Trace each surface through every arithmetic op until it (a) bounds an index, (b) computes an allocation size, (c) computes a balance/reward/epoch/slot, or (d) is stored as state.

---

## Phase 3: Per-class checks

### CHECK 1 — Multiplication overflow before division (`a * b / c`)

**Signal**: any expression of shape `amount * factor / divisor` where `amount` and `factor` are both u64 (or smaller unsigned) and neither is provably bounded. This is distinct from CHECK 2 (allocation overflow) — the impact here is financial loss or value corruption, not memory safety.

**Procedure**:
1. For every `a * b / c`: compute `max_product = max(a) * max(b)`. If `max_product > type::MAX` → overflow possible.
2. Check if the intermediate is widened: `(a as u128) * (b as u128) / (c as u128)` → safe (max `u64·u64` fits in u128). `a * b / c` without widening → unsafe.
3. Check if `checked_mul` + `checked_div` is used: `a.checked_mul(b).and_then(|x| x.checked_div(c))` → safe.
4. For fee computations: `amount * fee_bps / DENOM`. Even if `DENOM = 10_000`, `fee_bps * amount` can exceed `u64::MAX` for large amounts. The fix is `(amount as u128) * (fee_bps as u128) / (DENOM as u128) as u64` with a post-cast assertion that the result fits.

**Golden signature**: Kani counterexample `(a=X, b=Y)` where `a.checked_mul(b).is_none()` but the final result would fit in the type.

**Source**: SPL Token-2022 fee pattern [model-knowledge]; Wormhole bridge amount scaling [model-knowledge].

---

### CHECK 2 — Allocation-size overflow (multiply AND add)

**Signal**: `Vec::with_capacity(n)`, `reserve(n)`, manual `alloc`, or a pre-sized buffer where `n` is computed by `*` OR `+` from untrusted input, followed by `unsafe`/`set_len`/`spare_capacity_mut`/raw-pointer writes.

**Procedure**:
1. `Vec::with_capacity(user_len * elem_size)` — if `user_len * elem_size > usize::MAX`, wraps to a small value; allocation succeeds at tiny size; subsequent writes go past the allocation (C02).
2. `vec![0u8; user_len]` — panics if `user_len * size_of::<u8>() > isize::MAX`, but the panic is a DoS, not UB.
3. **Additive size math**: `new_cap + offset` or `len + extra` feeding a `reserve`/capacity field overflows the same way a multiply does — the wrap yields an undersized buffer. Check `checked_add`/widening on every `+` in size/capacity computation, not just `*`.
4. For each: can the size math exceed `usize::MAX` (multiply) or wrap (add)? If yes → flag. The deadly case is a wrapped size that is SMALLER than the data later written via `unsafe` → OOB write (escalate to Angle 1).

**Golden signature**: Kani counterexample where `user_len.checked_mul(elem_size).is_none()` or `cap.checked_add(offset).is_none()`.

**Source**: `base64::encode_config_buf` size multiply (RUSTSEC-2017-0004, CVSS 9.8); `std::str::repeat` capacity multiply (CVE-2018-1000810, CVSS 9.8); `bytes::BytesMut::reserve` `new_cap + offset` add (RUSTSEC-2026-0007); C02 in attack vectors.

---

### CHECK 3 — General overflow (fee, timestamp, amount)

**Signal**: `let fee = amount * rate;` on u64 — wraps silently in release mode (C05). `now + deadline` in timestamp arithmetic (C08).

**Procedure**:
1. For every `a + b` / `a * b` on untrusted `a`/`b` in release mode (or BPF): check whether `checked_add`/`checked_mul` is used. If not → overflow possible.
2. For timestamps: `now + timeout` where `timeout` is user-controlled or far-future. `u64` timestamps overflow ~584 billion years from epoch, but `i64` timestamps at `i64::MAX + 1` overflow. Check the epoch type.
3. For `saturating_add` / `saturating_mul`: the operation is safe but downstream consumers must handle the saturated value correctly — trace forward.
4. **BPF-specific**: Solana programs compiled with `cargo build-sbf` in release wrap on overflow by default. Check `Cargo.toml` `[profile.release]` for `overflow-checks = true`.

**Golden signature**: Kani or proptest finds input pair where operation wraps (result < max(a, b) for addition; result mod MAX ≠ a·b for multiplication).

---

### CHECK 4 — Arithmetic inside a guard flips the guard (underflow OR overflow)

**Signal**: an arithmetic expression INSIDE a comparison — `(a - b) < limit` (subtraction underflow) or `cap >= new + offset` (addition overflow). The inner op wraps in release mode and flips the guard's truth value.

**Procedure**:
1. `(highest - len) < ring_len` — when `len > highest`, wraps to huge positive, comparison passes. Monero Oxide F-15 class.
2. `total_reward - claimed` — underflows if `claimed > total_reward`, computes a phantom giant reward.
3. **Addition-overflow-inside-`>=` shape**: `if cap >= new_cap + offset` — when `new_cap + offset` wraps to a tiny number, the `>=` passes for ANY `cap`, the capacity field is set past the real allocation, and the next `unsafe` read/write goes OOB. RUSTSEC-2026-0007 (`bytes::BytesMut::reserve`) shape. Check whether the inner add is `checked_add`.
4. **Two failure modes, not one**: check BOTH `a < b` (wraparound → guard passes for giant result) AND `a == b` (zero result → `0 < limit` passes for any positive limit. If the intent was "has enough elements," zero available also satisfies).
5. For every guard with `+`/`-` on untrusted operands: evaluate the guard at the wrap/zero boundary, then add `assert!(b <= a)` / `checked_sub` (underflow) or `checked_add` (overflow).

**Golden signature**: `[BOUNDARY]` — set the inner-expression operands to the wrap/zero boundary; assert the guard takes the unintended branch.

**Source**: `bytes::BytesMut::reserve` add-overflow guard flip (RUSTSEC-2026-0007, verified Rust-native anchor); Monero Oxide F-15 (Kudelski Security) [model-knowledge]; Monero wallet2 ring-size guard [model-knowledge].

---

### CHECK 5 — Cast loss (width-narrowing, sign-flip, bridge-boundary)

**Signal**: `as` on integer types where the source is wider, signed→unsigned, or at a chain boundary.

**Procedure**:
1. **Width-narrowing**: `u128 as u64`, `u64 as u32`, `usize as u32`. Trace source range — if it can exceed `dest::MAX`, high bits are silently dropped.
2. **Sign-flip**: `i64 as u64` — negative → huge positive (two's complement). Flag every `i64 as u64` / `i32 as u64` where the source can be negative.
3. **Bridge-boundary narrowing** (highest-impact special case): cross-chain amounts traverse different width types. Ethereum amounts are u256, Solana SPL Token amounts are u64, Cosmos IBC amounts are `sdk.Int`. Every bridge point where a wider type narrows to a narrower one IS a truncation site. Trace the full type chain from source chain to destination chain. The narrowest point is the vulnerability.
4. **Platform-width**: `u64 as usize` on 32-bit targets → truncation. DLT off-chain workers, light clients, and embedded validators may be 32-bit.
5. **Fix is `try_from`, not `as`**: recommend `Dest::try_from(x)` (returns `Err` on loss) over `x as Dest`. Then trace whether the surrounding code handles the `Err` or just `.unwrap()`s it — an unwrapped `try_from` converts truncation into a panic-DoS (→ CHECK 6).

**Golden signature**: Kani harness: `assert!((value as Dest) as Source == value)` (round-trip) → counterexample where the cast loses information.

**Source**: Wormhole bridge u256→u64 [model-knowledge]; Cosmos IBC transfer amount narrowing [model-knowledge]; Rust Reference "Type cast expressions."

---

### CHECK 6 — Unwrapped checked arithmetic (panic-as-DoS / chain-halt)

**Signal**: `checked_add(a, b).unwrap()`, `checked_mul(...).unwrap()`, `x.checked_sub(y).expect("...")`, or any `unwrap()`/`expect()` on an `Option`/`Result` from `checked_*`.

**Procedure**:
1. Grep for `checked_add`/`checked_mul`/`checked_sub`/`checked_div` followed by `.unwrap()` or `.expect(...)`.
2. For each, determine the caller context:
   - **`BeginBlock`/`EndBlock`** → chain-halting (every validator panics simultaneously) → Critical.
   - **Transaction handler** → griefing DoS (attacker submits tx that panics, wastes gas, no chain halt) → High.
   - **View/query function** → no impact (informational at most).
3. If the inputs are untrusted → flag. The `unwrap()` converts a recoverable (and logged) overflow into an unrecoverable panic.
4. **Cosmos SDK specific**: `sdk.Coins.Add()` panics INTERNALLY on overflow — the outer code appears safe but the SDK panics. Check SDK function internals for hidden `unwrap()`s.

**Golden signature**: Kani counterexample where overflow → `unwrap()` panics on a reachable code path.

**Source**: Cosmos SDK `sdk.Coins` [model-knowledge]; Tendermint validator set rotation [model-knowledge].

---

### CHECK 7 — Division rounding direction (value leak)

**Signal**: any `a / b` used to compute a per-user allocation, fee share, reward distribution, or exchange rate. Integer division in Rust truncates toward zero (for unsigned: floor).

**Procedure**:
1. For each `a / b` in token/reward/fee distribution paths: **who gets `a % b`?**
2. If `a % b` accumulates in a contract balance or protocol treasury with no withdrawal mechanism → value is trapped (permanent loss in aggregate).
3. If `a % b` is claimed by the last withdrawer or a front-runner → MEV leakage.
4. Check rounding direction intent: `div_ceil` (rounds up, benefits protocol) vs truncating `/` (rounds down, benefits user). The choice must be explicit and documented.
5. **Repeated operation leakage**: if the same division is applied N times, cumulative leakage = `N · avg_remainder`. Compute worst-case bound.
6. **Two-step stored-rate round-trip (value extraction, not leak)**: when a rate is stored from one division and consumed by a second (`rate = supply / liquidity` rounds DOWN, then `out = amount / rate` rounds UP), the composed rounding can return MORE than deposited. Assert the round-trip invariant `redeem(deposit(x)) <= x` (and `shares→assets→shares <= x`) across the input range; the smallest `x` that violates it is the proof. Prefer the single-floor **Mul-Div** form `amount * total_liquidity / total_supply` over a pre-divided stored rate — fewer rounding sites, all in the protocol's favor. Compute the threshold magnitude before assigning severity (Kamino required collateral > 2^59) — don't assume "unreachable."
7. **CosmWasm note**: `Decimal::from_ratio(a, b)` computes `a * 10^18 / b` — panics on `b == 0` (CHECK 8) and precision loss for small `a`/large `b` (CHECK 9).

**Mechanical evidence**: execute the operation N times with random amounts; assert `sum(outputs) ≤ input - accumulated_remainder`; for the round-trip, property-test `redeem(deposit(x)) <= x` and report the smallest violating `x`.

**Anti-pattern**: one-time divisions (protocol initialization) where remainder is negligible. Repeated per-user operations are the concern.

**Source**: Kamino Lending KLend `Fraction::from(supply)/total_liquidity` round-down then `collateral/rate` round-up → redeem > deposit (Certora, verified, Solana-native); Compound exchangeRate [model-knowledge]; Lido stETH `getPooledEthByShares` [model-knowledge].

---

### CHECK 8 — Division panic (zero divisor AND signed `MIN / -1`)

**Signal**: `a / divisor` or `a % divisor` where `divisor` is attacker-controlled, state-derived (total supply, total stake), or governance-settable — and can be zero; OR a SIGNED `/`/`%` where the dividend can be `i::MIN` and the divisor can be `-1`.

**Procedure**:
1. Enumerate every `/` and `%` with a denominator that is NOT a compile-time literal.
2. For each: synthesize a path where the denominator = 0. Is there a prior `assert_ne!(divisor, 0)` or `NonZeroU64` type? If not → flag.
3. **First-depositor pattern**: `amount / total_supply` in a vault/staking contract where the first depositor can make `total_supply == 0` via donation attack or initial state.
4. **CosmWasm specific**: `Decimal::from_ratio(amount, total_supply)` panics if `total_supply == 0` — this is a known DoS in CosmWasm vaults.
5. **Cosmos SDK specific**: `sdk.Dec.Quo(divisor)` panics on zero divisor.
6. **Signed `i::MIN / -1` always-panics edge**: for every SIGNED `/`/`%` reachable from untrusted input, supply `(i::MIN, -1)`. This overflow panics in EVERY profile — even with `overflow-checks` off (Rust Reference) — so it cannot be silenced by build flags. Confirm a guard exists; if not → panic-DoS. Distinct from zero-divisor: a `NonZeroU64`/`assert_ne!(d,0)` guard does NOT cover it.

**Golden signature**: proptest input where divisor = 0, OR signed `(i::MIN, -1)`, and the code does not guard before dividing.

---

### CHECK 9 — Fixed-point precision loss

**Signal**: `(x * SCALE) / y` patterns where `SCALE` is a fixed scaling factor (1e9, 1e18). The numerator `x * SCALE` may have inadequate precision for small `x`.

**Procedure**:
1. For each fixed-point operation `result = x * SCALE / y`: compute the MINIMUM `x` that produces `result > 0`. Any `x` below this threshold → `result = 0` (dust loss on every operation).
2. For multi-step fixed-point chains (`r1 = a * SCALE / b`, `r2 = r1 * c / SCALE`): each step loses precision. Reorder to defer division: `(a * c * d) / (b * e)`. Check if the combined intermediate fits.
3. For AMMs/curves: verify Newton-Raphson convergence loop has iteration cap + error tolerance. Unbounded loop can diverge or consume all gas.
4. For accumulators: `total = total + per_user_share` where `per_user_share` is computed imprecisely → accumulator drifts from true sum over time.

**Mechanical evidence**: run computation at extremes (minimum x, maximum y, ratio near SCALE) and assert result within tolerance of true rational value.

**Source**: Curve stableswap Newton-Raphson [model-knowledge]; constant-product AMM precision at extreme ratios [model-knowledge].

---

### CHECK 10 — Governance-parameter-driven overflow

**Signal**: any arithmetic operation where one operand comes from a governance-settable parameter (fee rate, timeout, reward multiplier, bond, cap, epoch length).

**Procedure**:
1. List every governance-settable parameter that participates in arithmetic. Read governance parameter definitions — they're typically in `config.rs`, `params.rs`, or a `Params`/`Config` struct.
2. For each parameter: substitute `type::MAX` (or the type's plausible maximum if bounded by another constraint) and trace downstream arithmetic until it reaches a `checked_*` or a bound assertion.
3. If ANY operation panics/wraps at the extreme governance value → flag.
4. Check whether the governance parameter has a value-range assertion: `assert!(fee_bps <= 10_000)`. If no assertion (or too wide: `assert!(fee_bps > 0)` with no upper bound) → governance can set the dangerous value.
5. **Severity**: governance is trusted → downgrade per `[ASSUMPTION-DEP: TRUSTED-ACTOR]`. But governance CAN be wrong — report at Medium with a governance-trust note. The impact is real: if governance sets a bad parameter, the damage happens before a corrective proposal can pass.

**Golden signature**: no tool signature — this is a semantic check. The signal is: governance parameter × user amount with no intermediate widening and no parameter bound assertion.

**Source**: Binance Bridge parameter amplification [model-knowledge]; any protocol with governance-set multipliers applied to user amounts.

---

### CHECK 11 — Accumulated sum overflow

**Signal**: any state variable that monotonically increases across transactions/blocks: `total_fees`, `total_staked`, `cumulative_rewards`, `total_supply_via_mints`.

**Procedure**:
1. Enumerate every `+=` site for `total_*` / `cumulative_*` / `sum_*` state variables.
2. Compute: `max_per_op_increment × max_lifetime_operations`. If `> type::MAX` → overflow possible.
3. Check if `checked_add` or `saturating_add` is used:
   - `checked_add` → safe (returns `None`, caller handles).
   - `saturating_add` → clamps at MAX. Verify downstream consumers handle saturated values correctly (most don't — a saturated `total_fees` breaks fee distribution math).
   - Bare `+=` → wrapping overflow possible.
4. For `u64` accumulators in high-throughput contexts (DEX fees, staking rewards, frequent mints): `u64::MAX ≈ 1.8 × 10^19`. With values in millions and millions of operations, this can overflow within protocol lifetime.

**Golden signature**: compute `ceil(type::MAX / max_per_op_increment)` = operations-to-overflow. If this is less than the protocol's plausible lifetime operation count → flag.

**Source**: fee/reward accumulators across Solana programs [model-knowledge]; SPL Token mint supply tracking.

---

### CHECK 12 — Off-by-one bounds

**Signal**: `for i in 0..len` vs `0..=len`; `index >= max` vs `index > max`; `n/2` vs `(n/2)+1` for majority.

**Procedure**:
1. `for i in 0..len` — correct (exclusive end). `0..=len` — one past the last valid index, panics on access (C06).
2. `&slice[start..end]` panics if `end > slice.len()`. If `start`/`end` are user-controlled → panic-DoS.
3. Majority threshold: `n.div_ceil(2)` = exactly 50% for even N (V61). Strict majority requires `(n / 2) + 1`.
4. Quorum math: `ceil(N * 2/3)` vs `floor(N * 2/3)` — a 1-vote difference passes/fails a proposal at the boundary.

**Golden signature**: boundary-value test at N, N±1, N/2, N/2±1.

---

### CHECK 13 — Cross-module type-width mismatch

**Signal**: a value of type `T` in module A is compared/added/multiplied against a value of type `U` in module B where `T ≠ U`.

**Procedure**:
1. For every cross-module arithmetic/comparison: trace the type chain. Module A stores epoch as `u64`; module B stores it as `u32`. The comparison `epoch_A > epoch_B` implicitly promotes — where does the cast happen?
2. Widening (`u32 as u64`) → safe. Narrowing (`u64 as u32`) → truncation possible.
3. Type alias drift: if `type Slot = u64` in crate A but `type Slot = u32` in crate B, the types appear identical but have different widths. This is a semantic drift bug — not caught by the compiler.
4. **Consensus-specific**: slot numbers, epoch numbers, round numbers — these cross every component boundary in a consensus client. A mismatch between the consensus engine (`u64` slot) and the execution layer (`u32` slot, post-merge Ethereum) → truncation after slot ~4.29 billion.

**Golden signature**: non-mechanical — grep type alias definitions and cross-reference usage across crate boundaries.

**Source**: Ethereum consensus client type mismatches [model-knowledge]; Tendermint/Cosmos SDK version drift [model-knowledge].

---

### CHECK 14 — Wrapping where panic was expected (per-op contract on "checked" types)

**Signal**: arithmetic on a fixed-precision big-int type marketed as checked-by-default (`Uint256`, `Int512`, custom `Fraction`) — specifically `pow`/`neg`/`<<` on a value that can be large. The type's "checked" reputation does NOT mean every op is checked.

**Procedure**:
1. Identify the type's per-op overflow contract — not its general reputation. `cosmwasm-std` `Uint{256,512}::pow` / `Int{256,512}::pow` / `Int{256,512}::neg` wrap REGARDLESS of `overflow-checks`; the 64/128 variants wrap only when the flag is unset.
2. For each such op on attacker-influenced magnitude, ask whether downstream accounting assumes it panicked-on-overflow (i.e., trusts the result is exact). A wrap then produces a wrong-but-accepted value — silent financial corruption, not a panic.
3. Recommend explicit `checked_pow` / `checked_*` at the op rather than relying on the type or the profile flag, because the 256/512 variants ignore both.

**Mechanical evidence**: call the op at the documented-wrapping magnitude; assert the result ≠ the true mathematical value.

**Source**: `cosmwasm-std` `Uint/Int{256,512}::pow`/`neg` wrap regardless of profile (RUSTSEC-2024-0338, patched 1.4.4 / 1.5.4 / 2.0.2).

---

### CHECK 15 — `overflow-checks = true` becomes the DoS (hardening inversion)

**Signal**: `[profile.release] overflow-checks = true` (good hygiene) PLUS arithmetic on a large attacker-controlled magnitude in a hot, crypto, or serialization path. The hardening flag converts every reachable wrap into a panic.

**Procedure**:
1. After confirming `overflow-checks = true` (Phase 1 step 3), do NOT conclude "safe" — re-scan the same arithmetic for attacker-reachable LARGE inputs. Each reachable wrap is now a panic-DoS, not a silent value.
2. RUSTSEC-2025-0009 shape: `ring::aead::quic::HeaderProtectionKey::new_mask()` panics on a crafted QUIC packet, and AES-GCM panics near a 64 GiB single chunk — solely because overflow-checks turned an internal overflow into a panic.
3. Recommend `wrapping_*`/`saturating_*`/`checked_*` at the specific hot op rather than relying on the global flag — so hardening one path doesn't open a DoS on another. Severity follows call-site (consensus/block = Critical, tx = High) per CHECK 6.

**Mechanical evidence**: build with `overflow-checks = true`, feed the crafted large input, observe the panic; build without, observe the wrap — the two profiles diverge. This divergence IS the proof.

**Source**: `ring` AES/QUIC arithmetic panic under overflow-checks (RUSTSEC-2025-0009, < 0.17.12).

---

## Phase 4: Framework-specific knowledge

### Solana / BPF

- **Release mode = wrapping arithmetic.** Solana BPF programs (compiled with `cargo build-sbf` in release) wrap on overflow. `overflow-checks = true` in `Cargo.toml` `[profile.release]` IS the fix — check the profile config BEFORE flagging individual operations as vulnerable.
- `u64` is the native SPL Token amount type. `u64::MAX = 18,446,744,073,709,551,615` (~18.4 billion with 9 decimals). A malicious token with 0 decimals hits this with amounts in the billions.
- `Msg` deserialization: any amount field in `#[derive(BorshDeserialize)]` can be `u64::MAX`. No runtime bounds it — the program owns its overflow checks.
- `entrypoint!` passes raw account data. Deserialization and arithmetic safety are the program's responsibility.

### Cosmos SDK (Go patterns, applicable to Rust IBC/relayer implementations)

- `sdk.Coins.Add()` panics if sum overflows. Any `BeginBlock`/`EndBlock` calling it with unbounded amounts → chain halt (Critical).
- `sdk.Dec` (decimal, 18 precision) — `Quo()` panics on zero; `Mul()` can exceed max precision.
- IBC amounts are `sdk.Int` (big.Int, arbitrary precision). Narrowing to `u64` (WASM, light client) → truncation site. Flag every `Int64()` / `Uint64()` call.

### CosmWasm (Rust SDK)

- `Uint128`, `Uint256`, `Uint512` — checked by default for `+`/`-`/`*`. `checked_add` returns `Result`, not `Option`. **Exception (CHECK 14)**: `Uint{256,512}::pow` / `Int{256,512}::pow` / `Int{256,512}::neg` wrap regardless of `overflow-checks` (RUSTSEC-2024-0338); use explicit `checked_pow`.
- `Decimal` / `Decimal256` — fixed-point, 18 decimal places. `Decimal::from_ratio(a, b)` → panics if `b == 0`.
- `Decimal::one() - Decimal::percent(1)` → underflows if not guarded. Decimal traps on underflow.

### Substrate / Polkadot

- `Balance` is `u128` — very hard to overflow (max ~3.4×10^38), but `u128 as u64` in bridge/external code exists.
- `BlockNumber` / `BlockNumberFor<T>` is `u32` in most runtimes. `current_block + N` where `N > 4_294_967_295` wraps in release. Check for `overflow-checks = true` in runtime `Cargo.toml`.

### Move (Aptos / Sui)

- Move arithmetic **aborts on overflow** (no wrapping). Prevents silent loss, but creates abort-DoS vectors.
- `balance::add(&mut a, b)` aborts on overflow — attacker who triggers it repeatedly can grief.
- `as` in Move **aborts** if value doesn't fit. Safer than Rust's silent truncation. DoS vector still present.

### General Rust

- `usize` varies by platform: 64-bit on most chains, 32-bit on embedded/light clients. `u64 as usize` on 32-bit → truncation.
- `debug`: panics on overflow. `release`: wraps silently (default). `overflow-checks = true` in `[profile.release]` → panics in release.
- `Wrapping<T>` / `Saturating<T>` — intentional, type-documented contracts. Do NOT flag; the type system IS the guard.

---

## Stage-3 PoC discipline

### Kani (primary — bounded model checking)

```rust
#[kani::proof]
fn check_no_overflow_CHECK1() {
    let amount: u64 = kani::any();
    let fee_bps: u64 = kani::any();
    kani::assume(amount < 1_000_000_000_000);  // reasonable domain bound
    kani::assume(fee_bps <= 10_000);            // fee basis points
    let product = amount.checked_mul(fee_bps);
    assert!(product.is_some(), "overflow in fee computation: amount={}, fee_bps={}", amount, fee_bps);
}
```

Kani's counterexample: `amount = X, fee_bps = Y` → product overflows. This IS the mechanical proof.

### Framework-specific test patterns

**CosmWasm** (inline unit test, no Kani needed — `Uint128` is checked by default):
```rust
#[test]
fn test_no_overflow_in_fee_computation() {
    let amount = Uint128::new(u128::MAX);
    let fee_bps = Uint128::new(10_000);
    let result = amount.checked_mul(fee_bps);
    assert!(result.is_err(), "overflow should be caught by checked_mul");
}
```

**Solana BPF** (proptest — no Kani for BPF target):
```rust
proptest! {
    #[test]
    fn test_no_wrapping_overflow(amount in 0u64..u64::MAX, fee in 0u64..10_000u64) {
        let product = (amount as u128) * (fee as u128) / 10_000;
        prop_assert!(product <= u64::MAX as u128, "result doesn't fit in u64");
    }
}
```

**Substrate** (proptest for `BlockNumber` overflow):
```rust
proptest! {
    #[test]
    fn test_blocknumber_no_overflow(current in 0u32..u32::MAX, delta in 0u32..u32::MAX) {
        let _ = current.checked_add(delta).expect("BlockNumber overflow");
    }
}
```

### Fallback chain

If Kani is infeasible (too many paths, unbounded loops, FFI):
1. `cargo-fuzz` with `arbitrary` → feed random inputs, assert no panic/wrap.
2. `proptest` → feed extreme values (`u64::MAX`, `0`, `1`, `usize::MAX`, `type::MAX`, `type::MAX - 1`), assert no panic/invalid state.
3. Manual boundary-value table — 5+ concrete values covering min, typical, max for each untrusted parameter.

---

## Output fields beyond shared FINDING schema

```yaml
arithmetic_op: <expression that overflows/underflows/truncates>
input_source: <where the attacker-controlled value enters (file:line of public API)>
damage_class: financial-loss | chain-halt | memory-corruption | value-leak | panic-dos
check_number: <CHECK 1-15>
kani_harness: <inline Rust code of the proof harness, or "N/A">
kani_command: cargo kani --harness <name> --unwind <N>
kani_counterexample: <captured output, or "not yet run">
framework_note: <BPF/CosmosSDK/CosmWasm/Substrate/Move/General — specific runtime behavior that enables the bug>
```

---

## Anti-patterns (do NOT report)

- Arithmetic in test-only code (Stage-1 reachability flags as test-only).
- Overflow on inputs that are provably bounded by earlier validation (read the function's preconditions before flagging).
- Overflow on `Wrapping<T>` / `Saturating<T>` — the type system documents the contract. Do NOT flag operations on these types.
- Casts that are intentionally lossy with a documented bound (e.g., truncating a timestamp to a 32-bit slot ID where the slot ID is the canonical chain representation AND the truncation is documented).
- `debug`-mode overflow panics — `debug` mode panics are intended. Only flag if the same code wraps silently in release/BPF.
- One-time division remainder (initialization) where the remainder is a single negligible dust amount. Repeated per-user operations are the concern.

---

## Coordination with other angles

- **Memory Safety (Angle 1)**: Angle 3 finds the overflow; Angle 1 finds the UB it enables (OOB write, use-after-free from undersized allocation). File jointly when overflow → allocation → UB chain is confirmed.
- **Resource Exhaustion (Angle 6)**: Angle 3 finds the overflow → giant allocation; Angle 6 finds the OOM/DoS. File jointly when both fire.
- **Logic & State Machine (Angle 7)**: Angle 3 identifies the arithmetic wrap/truncation; Angle 7 identifies the consensus-state corruption it causes. If the impact is consensus divergence (not financial loss or memory corruption) → file under Angle 7 with Angle 3 as a contributing analysis.
- **Economic Design (smart-contract mode)**: Governance-parameter overflow (CHECK 10) overlaps. Angle 3 owns the overflow mechanism; Economic Design owns the governance-process risk. File under Angle 3 with Economic Design cross-reference.
- **Crypto Misuse (Angle 5)**: Fixed-point precision loss in cryptographic accumulators (Merkle tree sums, nullifier queues) bridges to Angle 5 if the precision loss breaks a cryptographic invariant.
