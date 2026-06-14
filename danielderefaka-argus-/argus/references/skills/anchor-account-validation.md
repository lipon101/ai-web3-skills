# Anchor Account Validation (v0.4.2)

> **Loads when**: project has `Anchor.toml` OR any `#[derive(Accounts)]` struct in scope.
> **Primary vectors**: V1, V4, V40 (from `references/attack-vectors/rust-attack-vectors.md`).
> **Coordinates with**: [`pda-seed-space.md`](pda-seed-space.md), [`anchor-cpi-safety.md`](anchor-cpi-safety.md).

## What this surface is

Anchor's `#[derive(Accounts)]` macro generates instruction-account validation code at expansion time. Every constraint a developer omits is enforcement absent at runtime — the program runs without the check. Most Solana program bugs reduce to a missing or wrong `#[account(...)]` constraint, not to logic bugs in the instruction body.

## When to load this skill

Trigger on **any** of:

- `Anchor.toml` present at workspace root.
- `use anchor_lang::prelude::*;` import.
- `#[derive(Accounts)]` attribute on any struct.
- `#[program]` attribute on any module.
- `programs/<name>/Cargo.toml` containing `anchor-lang = ...`.

## Step-by-step audit procedure

### 1. Enumerate every `#[derive(Accounts)]` struct

For each instruction handler, the corresponding `Accounts` struct is the **complete** authorization surface. List every field with its type and every constraint that field carries:

```bash
# Enumerate (cite this in attack-surface.md):
grep -nB1 -A40 '#\[derive(Accounts)\]' programs/*/src/**/*.rs
```

For each field, record in a per-instruction table:

| Field | Field type | Constraints | What this gates |
|-------|------------|-------------|-----------------|
| `authority` | `Signer<'info>` | (none) | Caller-identity check |
| `vault` | `Account<'info, Vault>` | `has_one = authority` | Vault belongs to authority |
| `mint` | `Account<'info, Mint>` | `address = vault.mint` | Mint matches vault's mint |

If any field is `AccountInfo<'info>` or `UncheckedAccount<'info>` and gates a privileged operation, that field is a suspect — proceed to step 2.

### 2. Audit each `AccountInfo` / `UncheckedAccount`

Anchor's `Account<'info, T>` type auto-validates the discriminator and the account owner. `AccountInfo` and `UncheckedAccount` do **not**. Every use must be justified by an explicit constraint OR by manual validation in the instruction body.

For each `AccountInfo`/`UncheckedAccount` field:

| Check | If MISSING → |
|-------|--------------|
| `#[account(signer)]` constraint OR explicit `if !field.is_signer { return Err(..) }` | V1 candidate FINDING |
| `#[account(owner = ...)]` OR explicit `if field.owner != &expected_program { return Err(..) }` | V4 candidate FINDING |
| `#[account(address = ...)]` for known pubkeys (e.g. sysvar, fixed admin) | depends on context — may be V1 (auth) or V4 (substitution) |
| Discriminator check for Anchor-typed data (`*field.data.borrow()[0..8] == EXPECTED::DISCRIMINATOR`) | V4 candidate FINDING |

### 3. Audit `has_one` / `constraint` directives

`has_one = authority` checks that `field.authority == authority.key()` — only valid if the field holds a verified-type account (`Account<'info, T>`), since otherwise the deserialization is on attacker bytes.

`constraint = <bool expr>` runs the expression at validation time. Common bugs:

- The expression uses `.unwrap()` (V25 panic candidate).
- The expression compares signed-integer fields without an underflow guard.
- The expression checks a NULLABLE / `Option` field's `.is_some()` but not the variant's value.
- The expression accesses `pre-init` state on an `init`/`init_if_needed` account (state is zero before the discriminator is written — the bytes are NOT yet a valid `T`).

For each `constraint`, ask: does this fire **after** the deserialization is sound? If `init` is in the same struct, the answer for the just-init'd account is **no**.

### 4. Audit `init` / `init_if_needed` accounts

`init` constraints with attacker-controllable `payer` or attacker-controllable `space` are V40 candidates:

| Field shape | Risk | Finding |
|-------------|------|---------|
| `#[account(init, payer = user, space = ...)]` where `user` is `Signer` but unrelated to the account's purpose | Front-run init: any signer can claim the seat | V40 |
| `#[account(init_if_needed, payer = user, ...)]` without idempotency guards in the instruction body | First-call vs re-call divergence | V40 |
| `#[account(init, ..., space = USER_CONTROLLED)]` | Rent + DoS griefing | V25 + bounded-DoS |
| `init` on a PDA whose seeds include only attacker inputs | Attacker controls which PDA gets initialized | V40 + PDA-substitution |

### 5. Audit `seeds` / `bump` constraints

Anchor's `seeds = [...]` + `bump` constraint validates that the passed account address equals the canonical PDA. Read the seeds list against the [`pda-seed-space.md`](pda-seed-space.md) audit procedure. Common bugs:

- `bump` without an explicit stored bump or canonical re-derivation (attacker passes non-canonical bump).
- `seeds = [user.key().as_ref()]` where `user` is `AccountInfo` (unverified) — attacker controls the seed.
- Same seeds derive multiple distinct PDAs across instruction handlers — collision space.

### 6. Audit `realloc` / `close` constraints

- `realloc` with `realloc::zero = false` and attacker-controlled new size: stale memory leaks into the resized region.
- `close = receiver` without verifying `receiver` is authorized to receive the lamports.
- `close` on an account that holds an SPL-token authority for live tokens: orphaned authority.

### 7. Cross-check the instruction body

Even when constraints are present, the body may bypass them. For each instruction:

- Search for `**account.lamports.borrow_mut() -= …` direct lamport edits — these don't go through Anchor's account-mutation discipline.
- Search for `account.to_account_info()` followed by raw byte writes — bypasses type validation.
- Search for `Account::<T>::try_from(&account_info)?` re-deserialization — if the discriminator wasn't checked first, this trusts attacker bytes.

## What counts as a finding

| Finding shape | Vector | Severity floor |
|---------------|--------|----------------|
| Privileged operation gated by `AccountInfo`/`UncheckedAccount` with no manual `is_signer` check | V1 | HIGH (auth bypass) |
| Account-substitution path: deserializes typed data without owner OR discriminator check | V4 | HIGH (state corruption) |
| `init` on user-controlled PDA without disambiguating seed | V40 | MEDIUM–HIGH (depending on what the init confers) |
| `constraint = <expr>` containing `.unwrap()` on attacker-influenced data | V25 | MEDIUM (DoS by panic) |
| Direct lamport edit bypassing typed-account discipline | varies | MEDIUM–HIGH |

## What does NOT count (SC-2 / known design)

- `UncheckedAccount` on a sysvar address pinned by `#[account(address = sysvar::clock::ID)]` — the address constraint replaces type-based validation.
- `AccountInfo` on a "receiver" account in a `close = receiver` clause where receiver is verified separately.
- `init_if_needed` is enabled feature-flag-only and the codebase explicitly opts in for idempotency reasons — check `Anchor.toml`'s `feature` block and the project README before flagging.
- `has_one = authority` without a separate `signer` constraint on `authority` is fine IF `authority` is `Signer<'info>` (the type already enforces signer-ness).

## Comparator citations

For the `comparator_citation` FINDING field, cite from the canonical Anchor source (use the version pinned in the audited project's `Cargo.toml`):

| Claim | Comparator |
|-------|------------|
| "Anchor's `Account<'info, T>` validates discriminator + owner" | `anchor-lang/src/accounts/account.rs:Account::try_accounts` |
| "Anchor's `Signer<'info>` validates `is_signer == true`" | `anchor-lang/src/accounts/signer.rs:Signer::try_accounts` |
| "Anchor's `seeds + bump` validates canonical PDA" | `anchor-syn/src/codegen/program/handlers.rs:gen_seeds_constraint` |

## Common false-positive shapes

- `AccountInfo<'info>` on an account that the instruction never reads or mutates (pure passthrough to a CPI — the CPI target enforces its own validation).
- Missing `signer` constraint on a field that's then passed to `Token::transfer` with the same field as authority — `spl-token::transfer` enforces `is_signer` internally.
- `init` without `seeds`/`bump` when the account is a vanilla `Keypair` the user must generate off-chain — front-running creates an unrelated account, not a substitution.
- `has_one = <field>` instead of `has_one = <field> @ ErrorCode::...` — the custom-error variant is for UX; absence is not a bug.

## Cross-skill triggers

If this skill fires AND any of these are true, also load:

- Project does CPI → load [`anchor-cpi-safety.md`](anchor-cpi-safety.md).
- Project uses PDAs → load [`pda-seed-space.md`](pda-seed-space.md).
- Project handles SPL tokens → check Token-2022 surface; load [`spl-token-2022-extensions.md`](spl-token-2022-extensions.md) if so.
