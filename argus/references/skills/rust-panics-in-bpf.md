# Rust Panics in BPF (v0.4.2)

> **Loads when**: every Anchor or Solana-native program (always — every BPF target where a panic aborts the transaction).
> **Primary vectors**: V25 (panic-on-malformed-input), V26 (slice index panic), V81 (arithmetic over/underflow).
> **Coordinates with**: [`anchor-account-validation.md`](anchor-account-validation.md), infra-mode `resource-exhaustion-agent`.

## What this surface is

On Solana, any panic inside a program — `.unwrap()`, `.expect()`, slice index out-of-bounds, integer overflow in debug mode, arithmetic overflow in release with overflow-checks, division by zero, `unreachable!()`, `todo!()`, `assert!`/`debug_assert!` — aborts the **transaction** with `ProgramError::ProgramFailedToComplete`. The program's state changes roll back; the calling client sees a hard failure.

From an attacker's perspective, that's a **DoS primitive** when:

- The panic is reachable from a public instruction without a prior auth gate.
- The panic occurs in a critical path (e.g. liquidations that anyone can trigger).
- The panic causes a step to NEVER complete (any input choice fails).

From the user perspective, panics are also **footguns** — a user transaction reverts entirely instead of returning a typed error, leaving them confused about what failed.

## When to load this skill

Trigger on **always** for Anchor/Solana-native programs. (BPF panic = transaction abort, regardless of project shape.)

## Step-by-step audit procedure

### 1. Enumerate every panic source

```bash
# Direct panic primitives:
grep -rnE '\.unwrap\(\)|\.expect\(' programs/*/src/ --include='*.rs' | grep -v '//'

# Slice indexing (panics if OOB):
grep -rnE '\[[a-zA-Z_][a-zA-Z0-9_]*\]' programs/*/src/ --include='*.rs' | grep -v '//' | grep -E '\.\.|\.\.='

# Explicit panics:
grep -rnE 'panic!|unreachable!|todo!|unimplemented!' programs/*/src/ --include='*.rs' | grep -v '//'

# Assertions:
grep -rnE 'assert!|debug_assert!|assert_eq!|assert_ne!' programs/*/src/ --include='*.rs' | grep -v '//'

# Try-into without error propagation:
grep -rnE 'try_into\(\)\.unwrap\(\)|TryInto::try_into.*\.unwrap' programs/*/src/ --include='*.rs'
```

For each hit, classify in a per-hit row:

| Site | Panic type | Reachable from | Input that triggers |
|------|------------|----------------|---------------------|
| `vault.rs:88` | `.unwrap()` on `Option<Account>` | public `withdraw` instruction | malformed account list |
| `math.rs:42` | slice index `data[8]` | any deserialize path | input shorter than 8 bytes |

### 2. Audit `.unwrap()` / `.expect()` reachability

`.unwrap()` is acceptable when:

- The expression's `Option` / `Result` variant is proven `Some` / `Ok` by structural invariant (e.g. `vec![1,2,3].first().unwrap()` — non-empty literal).
- The expression is in test code (Stage 1's `reachability_check` flags these test-only).
- The crate uses `unwrap_unchecked` on a path where the safety invariant is documented and the audit traced it.

`.unwrap()` is a finding when:

- The `Option` / `Result` comes from a fallible operation on attacker input (Borsh deserialize, slice index, integer conversion, account lookup).
- The `Result` is `Err`-propagated by `?` in 95% of the codebase but `.unwrap()` slipped in at one site (inconsistency suggests forgotten ?).
- The `.unwrap()` is on a `RefCell::borrow_mut()` or `Mutex::lock()` — second-borrow panic possible (V83 class).

Finding: V25 candidate. Severity depends on reachability:

- Pre-auth reachable → HIGH (DoS-as-anyone).
- Post-auth, post-validation → MEDIUM.
- Privileged-only → LOW or INFORMATIONAL.

### 3. Audit slice indexing

`data[N]` panics when `data.len() <= N`. `data[a..b]` panics when `a > b` or `b > data.len()`.

Patterns to flag:

| Pattern | Risk |
|---------|------|
| `account.data.borrow()[0..8]` without prior length check | Panic if account data < 8 bytes (un-init account) |
| `instruction_data[1..]` without checking `instruction_data.len() >= 1` | Panic on empty `instruction_data` |
| `let (a, b) = data.split_at(N)` without bounds check | Panic if `data.len() < N` |
| `vec[index]` where `index` is attacker-supplied or attacker-influenced | V26 panic |
| `array[idx as usize]` after a `try_from(attacker_input)` | Panic on out-of-bounds idx |

Fix patterns to recognize as SAFE:

- `data.get(N).ok_or(InvalidLength)?` — proper bounds check.
- `data.first().ok_or(...)?` / `data.last().ok_or(...)?`.
- `data.split_first().ok_or(...)?`.
- `array_ref![data, 0, 8]` (the `arrayref` crate) — compile-time bounds.

Findings: V26 candidates. Severity by reachability (same as step 2).

### 4. Audit arithmetic overflow

Solana programs run in two modes:

- **Debug build**: arithmetic operators (`+`, `-`, `*`) panic on overflow.
- **Release build (deployed)**: arithmetic operators **wrap silently** unless the crate has `overflow-checks = true` in `Cargo.toml`.

Find the project's overflow-checks setting:

```bash
grep -nE 'overflow-checks' programs/*/Cargo.toml
```

If `overflow-checks = true` in the deployed release profile: arithmetic panics → DoS findings. (Modern Anchor templates set this by default.)
If absent or `false`: arithmetic silently wraps → state-corruption findings (V81 silent-wrap class, often worse than panic-DoS).

For each arithmetic site in financial-impact code (balance, supply, share math), check:

| Pattern | Check |
|---------|-------|
| `a + b` | Use `checked_add` or `saturating_add`; bare `+` is suspect |
| `a - b` | Use `checked_sub` or guard `a >= b`; bare `-` underflows |
| `a * b` | Use `checked_mul` or pre-compute bounds; bare `*` overflows quickly with u64 |
| `a / b` | Guard `b != 0`; division panics on zero in both debug and release |
| `a % b` | Guard `b != 0`; same |
| `a << n` / `a >> n` | Guard `n < BITS`; `1u64 << 64` panics in debug, wraps in release |
| `a.pow(n)` | `pow` can overflow silently; `checked_pow` for any attacker-influenced `n` |

Findings:

- Bare arithmetic on attacker-influenced values in critical paths → V81. Severity:
  - With `overflow-checks = true`: DoS (panic) — MEDIUM–HIGH by reachability.
  - Without `overflow-checks`: state corruption (silent wrap) — HIGH by reachability + financial impact.

### 5. Audit `assert!` / `debug_assert!`

| Macro | Behavior in release | Audit implication |
|-------|--------------------|--------------------|
| `assert!(cond)` | Panics if `!cond` | DoS surface — V25 |
| `assert_eq!(a, b)` | Panics if `a != b` | DoS surface — V25 |
| `debug_assert!(cond)` | **Compiled out** in release | Not a runtime check; relying on it for security is V25-class invariant gap |
| `if !cond { panic!(...) }` | Same as `assert!` | DoS surface — V25 |

Findings:

- `assert!` reachable from public input → V25 DoS.
- `debug_assert!` used to enforce a security invariant → the invariant is NOT enforced in production; finding-class: "missing release-build check".

### 6. Audit `try_into().unwrap()`

`try_into()` returns `Result<T, _>` for conversions that may fail (e.g. `u64 → usize`, `usize → u32`, signed↔unsigned, larger int → smaller int). `.unwrap()` on this is a panic primitive whenever the value is out-of-range for the target type.

Common findings:

- `value.try_into::<u32>().unwrap()` where `value: u64` and `value` can exceed `u32::MAX` → V81 + V25.
- `(amount as i64).try_into::<u64>().unwrap()` where `amount` can be negative.
- Conversions inside arithmetic chains: `(a + b).try_into::<u32>().unwrap()` panics on both overflow AND truncation.

### 7. Audit panic-paths inside `Drop` / `Borrow` / iterator methods

Less common but real:

- Panics inside a `Drop` impl during unwinding cause an abort (worse than a normal panic).
- Panics inside `RefCell::borrow_mut()` — second-borrow.
- Panics inside iterator `for` loops on a `Vec` whose underlying buffer can be re-entered.

For Anchor programs, these are rare. Surface only if the project has custom `Drop` / interior-mutability.

## What counts as a finding

| Finding shape | Vector | Severity floor |
|---------------|--------|----------------|
| `.unwrap()` on Result from attacker-input deserialization, pre-auth reachable | V25 | HIGH (DoS-as-anyone) |
| Slice index OOB reachable from public instruction | V26 | HIGH (DoS-as-anyone) |
| Bare arithmetic on financial values with `overflow-checks = true` | V81 | MEDIUM–HIGH |
| Bare arithmetic on financial values WITHOUT `overflow-checks` | V81 (silent-wrap variant) | HIGH (state corruption) |
| `assert!` on attacker-controlled bool in critical path | V25 | MEDIUM |
| `debug_assert!` enforcing a security invariant | new (missing-release-check) | MEDIUM–HIGH |
| `try_into().unwrap()` with attacker-influenced operand | V25+V81 | MEDIUM–HIGH |
| Division by attacker-supplied zero | V81 | MEDIUM (DoS) |

## What does NOT count (SC-2 / known design)

- `.unwrap()` on a literal expression whose variant is provably `Some`/`Ok` (e.g. `Some(x).unwrap()`).
- `.unwrap()` on constants (e.g. parsing a hard-coded `Pubkey`).
- `assert!` on an internal invariant that is provably true by structural construction (Stage-2 angle should prove unreachability per `bug_reachability_proof`).
- Panics only reachable from `#[cfg(test)]` code.
- Arithmetic on amounts bounded by struct fields that themselves are bounded (e.g. `a + b` where both `a` and `b` are `u64::MAX / 4`).

## Comparator citations

| Claim | Comparator |
|-------|------------|
| "Solana program panics abort the transaction" | `solana-program-runtime/src/invoke_context.rs` (the panic-unwinding path) |
| "Anchor's default `Cargo.toml` sets `overflow-checks = true` for `[profile.release]`" | `anchor-cli/templates/.../Cargo.toml` |
| "Debug-assert is no-op in release" | Rust reference, `debug_assert!` macro definition |

## Common false-positive shapes

- `.unwrap()` immediately after `assert!(opt.is_some())` — the assert serves as the safety contract.
- `arr[const_index]` where `const_index < arr.len()` is enforced at compile-time by a `const` assertion.
- Arithmetic where both operands are typed-narrow (e.g. `u8 + u8 → u16` after explicit widening).
- `try_into()` on a runtime-bounded value: `usize::try_into::<u32>()` where the codebase asserts `value < u32::MAX` upstream.

## Tier-specific behavior

- **Light tier**: skip §7 (Drop/Borrow audit) — too rare to justify the time.
- **Core tier**: all 7 steps.
- **Thorough tier**: all 7 steps + cargo-fuzz harness per panic site (per [`infra-verification-stage.md`](../infra-verification-stage.md)) to mechanically confirm reachability.
