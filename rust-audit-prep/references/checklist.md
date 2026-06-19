# Solana Audit Prep Checklist

Compact reference for all checks. Each item = one potential finding.
Covers both **Anchor** and **native `solana_program`** patterns.

## Documentation Requirements

| Element | Required | Optional |
|---------|----------|----------|
| Module (`lib.rs`, etc.) | `//!` top-level doc | — |
| Public function | `///` with description | Params, returns |
| Anchor instruction handler | `///` with description | Params, error conditions |
| Public struct / enum | `///` with description | Field docs |
| Anchor `#[derive(Accounts)]` struct | `///` per field | Constraint explanation |
| Public trait | `///` with description | Method docs |
| Custom error enum | `///` per variant | Error context |

## Hygiene Checks

| Check | Severity | Auto-fix? |
|-------|----------|-----------|
| `TODO`/`FIXME`/`HACK`/`XXX` comments | MED | remove |
| `println!` / `print!` / `dbg!` macros | HIGH | remove |
| `msg!` overuse (>10 per function) | INFO | reduce |
| Commented-out code (3+ lines) | LOW | — |
| Missing `overflow-checks = true` in release profile | HIGH | add |
| `#[allow(dead_code)]` in production | LOW | — |
| Dead/unused functions | LOW | — |
| Test helpers in program code (`#[cfg(test)]` leaks) | MED | — |
| Functions >60 lines | INFO | — |
| Magic numbers without named constants | INFO | — |
| `unsafe` blocks without `// SAFETY:` comment | MED | — |
| Leftover `solana_program::log::sol_log` debug strings | LOW | remove |

## Account Validation Checks (Anchor)

| Pattern | Severity | What to look for |
|---------|----------|-----------------|
| `AccountInfo` for authority | CRITICAL | Should be `Signer<'info>` — auto-checks `is_signer` |
| Pubkey comparison without signer check | CRITICAL | Comparing `account.key()` to a stored pubkey but not requiring `Signer<'info>` — attacker can pass the right pubkey as an unsigned account |
| `AccountInfo` for data accounts | CRITICAL | Should be `Account<'info, T>` — auto-checks owner + discriminator |
| `UncheckedAccount` for data | HIGH | Only valid for accounts you don't deserialize — add `/// CHECK:` doc |
| Missing `has_one` | HIGH | Stored `Pubkey` field not validated against passed account |
| Missing `seeds` + `bump` on PDA | HIGH | PDA accounts without seed derivation constraint |
| Shared PDA across authority domains | HIGH | Same PDA used for multiple unrelated authority scopes — use domain-specific seed prefixes to prevent cross-domain access |
| PDA seed collision risk | MED | Same seed prefix used for different account types — include a type discriminator or unique prefix per account kind to prevent derivation collisions |
| Missing `mut` on modified accounts | MED | Changes won't persist — instruction silently uses stale state |
| `init_if_needed` usage | HIGH | Reinitialization risk — always flag for manual review |
| Missing `close` on disposable accounts | MED | Rent not reclaimed (~0.002 SOL per account) |
| Missing `realloc::zero = true` | MED | Stale data leaks if account is shrunk then expanded |
| Missing `constraint` for uniqueness | HIGH | Duplicate mutable accounts enable double-counting |
| `AccountInfo` as CPI target program | CRITICAL | Should be `Program<'info, T>` or `Interface<'info, T>` |
| Missing `/// CHECK:` on unchecked accounts | LOW | Anchor requires documented safety justification |

## Account Validation Checks (Native)

| Pattern | Severity | What to look for |
|---------|----------|-----------------|
| Missing `is_signer` check | CRITICAL | Authority accounts without `if !account.is_signer` |
| Pubkey-only authority check | CRITICAL | Comparing `account.key` to a stored pubkey without verifying `account.is_signer` — anyone can pass the correct pubkey as an unsigned account |
| Missing owner check | CRITICAL | `account.owner != program_id` not verified before deserialization |
| Missing discriminator check | CRITICAL | `try_from_slice` without first-8-byte discriminator comparison |
| `create_program_address` usage | HIGH | Should use `find_program_address` for canonical bumps |
| User-supplied bump parameter | HIGH | Allows non-canonical PDA derivation (shadow accounts) |
| Missing `is_writable` check | LOW | `borrow_mut()` on accounts without writable verification |
| Missing `is_initialized` guard | CRITICAL | Initialize instruction without checking existing data |
| Account revival after close | CRITICAL | Closed account (zeroed lamports) can be revived within the same transaction — combine `is_initialized` guard with discriminator check AND data zeroing on close to prevent re-initialization attacks |
| Hardcoded lamports in `create_account` | MED | Should use `Rent::get()?.minimum_balance(data_len)` |

## CPI Safety Checks

| Pattern | Severity | What to look for |
|---------|----------|-----------------|
| Arbitrary CPI target | CRITICAL | `invoke()` without verifying target program key |
| Missing `.reload()` after CPI | HIGH | Stale deserialized copy after CPI modifies shared account |
| Signer privilege forwarding | HIGH | PDA seeds should include caller's key to prevent escalation |
| Missing post-CPI balance check | MED | Verify lamport balances haven't changed unexpectedly |
| CPI to unverified program with forwarded signer | CRITICAL | Combined with arbitrary CPI = drain vector |

## Token & SPL Checks

| Pattern | Severity | What to look for |
|---------|----------|-----------------|
| Token program as `AccountInfo` | CRITICAL | Should be `Program<'info, Token>` or `Interface<'info, TokenInterface>` |
| Missing mint validation | HIGH | Token account's `.mint` not compared to expected mint |
| Missing token authority check | HIGH | Token account's `.owner` not validated |
| Token account vs Mint confusion | MED | Both owned by Token Program — use typed wrappers |
| Close without data zeroing | HIGH | Closed accounts can be revived in same transaction (see Account Revival below) |
| Missing associated token account derivation | LOW | Using raw token accounts instead of ATAs |

### Token-2022 Extension Checks

| Pattern | Severity | What to look for |
|---------|----------|-----------------|
| Transfer Hook not validated | CRITICAL | Token with Transfer Hook extension allows arbitrary code execution on every transfer — verify hook program ID is expected and trusted |
| Permanent Delegate not checked | CRITICAL | Permanent Delegate can transfer/burn any holder's tokens without their signature — reject mints with this extension unless explicitly supported |
| Confidential Transfer validation gap | HIGH | No validation that source/destination differ for deposits/withdrawals — allows fee circumvention; no check for non-transferable extension on deposit |
| Transfer Fee not accounted for | HIGH | Token transfers may deduct fees silently — calculate net amounts using `transfer_fee_basis_points` from the mint's extension data |
| Variable account size not handled | HIGH | Mint/TokenAccount size varies by number of extensions — code that checks account type by data length will break; use `spl_token_2022::extension::StateWithExtensions` |
| Non-Transferable extension bypass | MED | Tokens marked non-transferable can still be moved via Confidential Transfer if not explicitly blocked |
| Missing extension enumeration | MED | Protocol accepts any SPL token without checking which extensions are active — whitelist safe extensions or explicitly reject dangerous ones |
| Interest-Bearing extension ignored | LOW | Display amounts may differ from stored amounts if interest-bearing extension is active |

## Arithmetic Safety Checks

| Pattern | Severity | What to look for |
|---------|----------|-----------------|
| Direct `+` `-` `*` `/` (no overflow-checks) | HIGH | Silent wrapping in release mode — use `checked_*` |
| Division before multiplication | HIGH | Precision loss — multiply first, divide last |
| `as` cast between int widths | MED | `256u16 as u8 = 0` — use `try_from()` |
| `as` cast signed ↔ unsigned | MED | `-1i64 as u64 = 18446744073709551615` |
| `f32` / `f64` in financial math | HIGH | Non-deterministic, precision loss — use fixed-point |
| Missing rounding direction | HIGH | Floor for payouts/withdrawals, ceil for fees/deposits |
| `saturating_*` in value-critical path | MED | Silently caps at max instead of erroring |
| Missing `u128` intermediate for large multiply | MED | `u64 * u64` can overflow before assignment |
| Division by zero possible | HIGH | `checked_div` or explicit zero-guard required |

## Rust Quality Checks

| Pattern | Severity | What to look for |
|---------|----------|-----------------|
| `unwrap()` on user input | MED | Panic = DoS vector — use `ok_or(ProgramError::...)` |
| `unwrap()` after `find_program_address` | OK | Guaranteed success — acceptable |
| Large stack allocation | HIGH | >4KB per frame causes AccessViolation on mainnet |
| Direct array indexing `data[i]` | MED | Panics on OOB — use `.get(i).ok_or(...)` |
| `unsafe` without justification | HIGH | Must have `// SAFETY:` comment explaining why |
| Missing custom error types | LOW | `ProgramError::Custom(0)` provides no context |
| Missing event/log on state change | MED | Indexers and UIs need instruction events |
| Panic paths from malicious input | HIGH | Division by zero, slice operations, array indexing |
| `#[allow(clippy::...)]` suppressions | INFO | Each suppression should have a justification comment |

## Compute & Gas Optimization Checks

| Pattern | Severity | What to look for |
|---------|----------|-----------------|
| Redundant account loads | INFO | Same account deserialized multiple times |
| Unnecessary `.clone()` on large data | INFO | Borrow instead of clone where possible |
| Missing `Box<Account<'info, T>>` | INFO | Large accounts should be heap-allocated |
| Missing zero-copy (`#[account(zero_copy)]`) | INFO | Accounts >1KB benefit from zero-copy deserialization |
| `pub` functions that should be `pub(crate)` | INFO | Reduces external API surface |
| Excessive `msg!()` in hot paths | INFO | Each `msg!` consumes ~100 CU |
| `String` instead of fixed-size arrays | LOW | Heap allocation in BPF is expensive |
| `Vec` operations in loops | INFO | Pre-allocate with `Vec::with_capacity()` |

## Scoring Deductions

| Finding | Category | Deduction | Cap |
|---------|----------|-----------|-----|
| `println!`/`dbg!` in production | Hygiene | -15 | — |
| Missing `overflow-checks` in release | Hygiene | -15 | — |
| TODO/FIXME | Hygiene | -3 | -30 |
| Commented-out code | Hygiene | -2 | -20 |
| Dead code | Hygiene | -5 | — |
| `unsafe` without justification | Hygiene | -10 | — |
| Known CVE in dependency | Deps | -20 (critical) / -10 (other) | — |
| Major version outdated (unpinned) | Deps | -10 | — |
| Major version outdated (pinned/audited) | Deps | INFO only | — |
| Minor version outdated | Deps | INFO only | — |
| Missing `Cargo.lock` | Deps | -10 | — |
| Yanked crate | Deps | -15 | — |
| Duplicate versions of same crate | Deps | -5 | — |
| Forked git dep without documentation | Deps | -10 | — |
| Missing signer check | Practices | -15 | — |
| Missing owner check | Practices | -15 | — |
| Missing `has_one` / seed constraint | Practices | -10 | — |
| Arbitrary CPI target | Practices | -15 | — |
| `init_if_needed` usage | Practices | -10 | — |
| Direct arithmetic (no overflow protection) | Practices | -10 | -30 |
| Missing event/log on state change | Practices | -3 | -30 |
| `unwrap()` on user input | Practices | -3 | -15 |
| Missing mint/authority validation | Practices | -10 | — |
| `as` cast between int widths | Practices | -5 | -15 |
| `AccountInfo` as CPI program | Practices | -15 | — |
| Close without cleanup | Practices | -10 | — |
| Account revival after close | Practices | -15 | — |
| Pubkey-only authority (no signer) | Practices | -15 | — |
| Shared PDA across domains | Practices | -10 | — |
| PDA seed collision risk | Practices | -5 | — |
| Hardcoded lamports in `create_account` | Practices | -5 | — |
| Transfer Hook not validated | Practices | -15 | — |
| Permanent Delegate not checked | Practices | -15 | — |
| Token-2022 extension not enumerated | Practices | -10 | -30 |
| `Vec` operations in loops (no pre-alloc) | Optimization | -2 | -10 |

## Dependency Checks

**Anchor projects:**
```bash
# Check Anchor version
grep 'anchor-lang' Cargo.toml    # compare with latest release
grep 'anchor_version' Anchor.toml

# Cargo tools
cargo outdated 2>&1              # version comparison
cargo audit 2>&1                 # known CVEs
cargo tree -d 2>&1               # duplicate dependencies
```

**Native projects:**
```bash
cargo outdated 2>&1
cargo audit 2>&1
cargo tree -d 2>&1
```

**High-risk patterns:**
- Anchor <0.31.0 (missing security patches; 0.32.0 introduced breaking changes around error codes and `#[account(associated)]`)
- `solana-program` version mismatch with deployed cluster version
- Multiple versions of `solana-program` or `spl-token` in dependency tree
- Missing `Cargo.lock` (non-deterministic builds)
- Yanked crate versions in `Cargo.lock`
- Forked/patched dependencies without documentation
