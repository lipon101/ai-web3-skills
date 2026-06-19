# PDA Seed-Space Audit (v0.4.2)

> **Loads when**: any `Pubkey::find_program_address`, `Pubkey::create_program_address`, or Anchor `seeds = [..]` constraint in scope.
> **Primary vectors**: V3 (seed/bump confusion), V40 (init front-run).
> **Coordinates with**: [`anchor-account-validation.md`](anchor-account-validation.md), [`anchor-cpi-safety.md`](anchor-cpi-safety.md).

## What this surface is

A Program-Derived Address (PDA) is a deterministic address computed from a list of seeds and a program ID. PDAs aren't private keys — the program "signs" for them via `invoke_signed` using the same seeds. Three failure classes:

1. **Seed-space collisions**: two different intent strings derive the same PDA → state confusion / authority confusion.
2. **Non-canonical bump**: an attacker derives a PDA with a non-canonical bump, then convinces the program to accept it.
3. **Attacker-controlled seeds**: a seed component comes from attacker input, letting the attacker pick which PDA gets created / acted upon.

## When to load this skill

Trigger on **any** of:

- `Pubkey::find_program_address(...)`.
- `Pubkey::create_program_address(...)`.
- `#[account(seeds = [..], bump)]` Anchor constraint.
- `#[account(seeds = [..], bump = <value>)]` Anchor constraint with explicit bump.
- A function whose name contains `derive_*` returning a `Pubkey`.

## Step-by-step audit procedure

### 1. Enumerate the project's PDA universe

For every PDA derivation, record in a per-PDA row:

| PDA purpose | Seeds | Bump source | Derivation site | Where consumed |
|-------------|-------|-------------|-----------------|----------------|
| User vault | `[VAULT_SEED, user.key().as_ref()]` | canonical (stored in `vault.bump`) | `init_vault.rs:42` | `withdraw.rs:88`, `deposit.rs:55` |
| Treasury | `[TREASURY_SEED]` | canonical | `init.rs:23` | many |

Group by program. Each program has a finite seed-space that should be **disjoint** across PDA purposes.

### 2. Audit seed-space disjointness

For every pair of PDA purposes within the same program, ask: can the seed lists ever produce the same PDA?

Common collisions:

- `[USER_SEED, user.key().as_ref()]` vs `[USER_SEED, attacker_signature_bytes]` where `attacker_signature_bytes` is a fixed-size byte array and `user.key()` is also 32 bytes. If `attacker_signature_bytes` happens to equal a real `user.key()`, the PDA collides.
- `[b"user", user.key().as_ref()]` vs `[b"user-archive", user.key().as_ref()]` — disjoint by prefix length and content; SAFE.
- `[b"vault", mint.key().as_ref()]` vs `[mint.key().as_ref(), b"vault"]` — DIFFERENT PDAs (seeds are order-sensitive), but if BOTH derivation paths exist in the program, attacker may be able to pivot between them.

**The disjointness rule**: every PDA's seed list must include either (a) a unique string-literal prefix or (b) a unique constant byte sequence that no other PDA path uses. `user.key().as_ref()` alone is NOT a disjointness guarantee.

Findings:

- Two PDA-derivation sites with identical seed shape and unequal intent → V40-class candidate (state confusion).
- A PDA seed-shape that's a permutation of another → review for pivot attack.

### 3. Audit canonical-bump enforcement

`Pubkey::find_program_address` walks bumps from 255 downward and returns the first one that produces a valid (off-curve) PDA. That bump is the **canonical** bump. `Pubkey::create_program_address` accepts a specific bump and produces a PDA for that bump if valid — for any seed list, multiple bumps may yield valid PDAs.

Bug class: program accepts an account whose address derives from the canonical seeds but a NON-canonical bump:

```rust
// VULNERABLE — accepts any valid bump:
let pda = Pubkey::create_program_address(
    &[USER_SEED, user.key().as_ref(), &[user_supplied_bump]],
    &program_id,
)?;
if pda != passed_account.key() { return Err(..) }
// Attacker can find a non-255 bump that satisfies the check, then derive a parallel
// account for the same logical "user" — duplicate accounts, state confusion.
```

Fixed pattern:

```rust
// SAFE — derive canonical:
let (pda, bump) = Pubkey::find_program_address(
    &[USER_SEED, user.key().as_ref()],
    &program_id,
);
if pda != passed_account.key() { return Err(..) }
// Or with Anchor:
//   #[account(seeds = [USER_SEED, user.key().as_ref()], bump)]   // canonical
//   #[account(seeds = [USER_SEED, user.key().as_ref()], bump = stored.bump)]   // stored, validated at init
```

Findings:

- `create_program_address` with attacker-supplied bump → V3 HIGH.
- Anchor `bump = <user_input>` → V3 HIGH.
- Anchor `bump` (no value) is canonical and SAFE.
- Anchor `bump = stored_bump` is SAFE IF `stored_bump` was canonically derived at init.

### 4. Audit attacker-controlled seed components

For each PDA derivation, classify each seed component:

| Seed source | Trust level |
|-------------|-------------|
| String literal (`b"vault"`) | Constant — safe |
| `program_id` / `system_program::ID` | Constant — safe |
| `signer.key().as_ref()` where `signer: Signer<'info>` | Authenticated — safe |
| `account.key().as_ref()` where `account: Account<'info, T>` | Account address, typed — safe |
| `account.key().as_ref()` where `account: AccountInfo<'info>` | Unverified — **attacker-controlled** |
| `instruction_data` slice | **Attacker-controlled** |
| `Clock::get()?.slot.to_le_bytes()` | Quasi-attacker-controlled (slot known) |

If any seed component is attacker-controlled AND the PDA controls authority for funds / state → V40 HIGH.

If any seed component is attacker-controlled but the PDA is only a "cache key" (no privilege) → LOW or NO finding.

### 5. Audit `init` paths

For `#[account(init, ..., seeds = [...], bump)]`, the first transaction to invoke that instruction with a given seed-shape wins the PDA. If the seed-shape is attacker-influenceable, attacker front-runs init and claims the slot:

| Init seed shape | Front-run risk |
|-----------------|----------------|
| `[USER_SEED, user.key().as_ref()]` where `user` is `Signer` | None — user must sign |
| `[CONFIG_SEED]` (singleton) | First-deployer race — usually handled at deployment, not bounty-relevant |
| `[VAULT_SEED]` (singleton) | First-init race; if init confers admin powers, HIGH |
| `[POOL_SEED, mint_a, mint_b]` where mints are public | LOW (anyone can init, but the value flows by design) |

Findings: V40 candidates for any `init` whose seed shape doesn't require the legitimate party to sign.

### 6. Audit cross-program seed assumptions

When program A uses program B's expected PDA seeds to sign for an account, program A must use the EXACT seed list and bump program B canonicalizes on. Mismatch leads to silent CPI failures or, worse, signer-confusion.

Example: integrating with a vault program whose seeds are `[VAULT_SEED, user.key().as_ref()]`. The caller must:

- Use the same literal seed prefix.
- Use the same byte representation (`as_ref()`, not `to_bytes()` — they differ for some types).
- Use the canonical bump (re-derive via `find_program_address` or look up from the vault account itself).

Cross-skill: if the audited program CPIs into another, the seeds passed to `invoke_signed` are scrutinized by both this skill and [`anchor-cpi-safety.md`](anchor-cpi-safety.md).

## What counts as a finding

| Finding shape | Vector | Severity floor |
|---------------|--------|----------------|
| `create_program_address` with attacker-supplied bump on an authority PDA | V3 | HIGH |
| Two PDA paths in the same program with seed-space collision potential | V40 (new variant) | MEDIUM–HIGH |
| `init` PDA with attacker-controllable seed component | V40 | MEDIUM–HIGH (depends on confer) |
| Anchor `bump = <expr>` where `<expr>` reads from an attacker-mutable field | V3 | HIGH |
| Seed prefix non-unique across distinct logical PDAs | V40 | MEDIUM |

## What does NOT count (SC-2 / known design)

- Singleton PDAs (`[CONFIG_SEED]`) with first-deployer init — handled at deployment.
- "Cache key" PDAs that don't confer authority or hold funds — collision is a logic bug, not a security bug, unless the cache poisons downstream state.
- `create_program_address` with hardcoded bump constant (e.g. `&[255]`) — not attacker-controlled.

## Comparator citations

| Claim | Comparator |
|-------|------------|
| "find_program_address returns the canonical bump (highest valid)" | `solana-program/src/pubkey.rs:Pubkey::find_program_address` |
| "create_program_address accepts any valid bump for given seeds" | `solana-program/src/pubkey.rs:Pubkey::create_program_address` |
| "Anchor `seeds + bump` enforces canonical" | `anchor-syn/src/codegen/program/handlers.rs` |

## Common false-positive shapes

- `seeds = [signer.key().as_ref()]` with `signer: Signer<'info>` — signer is authenticated; the seed is effectively constant from the attacker's perspective per identity.
- Hardcoded bumps in test code — Stage 1's `reachability_check` should classify these test-only.
- PDA-shape that LOOKS attacker-controlled but the controlling input is a typed `Account<'info, T>` whose discriminator is enforced at deserialization.
