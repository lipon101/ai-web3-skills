# Anchor CPI Safety (v0.4.2)

> **Loads when**: any `CpiContext::new`, `CpiContext::new_with_signer`, `invoke`, or `invoke_signed` call site in scope.
> **Primary vectors**: V3 (PDA seed/bump confusion), V36 (CPI to attacker-controlled program), V42 (CPI return-data trust).
> **Coordinates with**: [`pda-seed-space.md`](pda-seed-space.md), [`anchor-account-validation.md`](anchor-account-validation.md).

## What this surface is

Cross-Program Invocation (CPI) is Solana's mechanism for one program to call another mid-transaction. Three things go wrong:

1. **Wrong callee**: the CPI dispatches to a program ID the attacker influenced, executing arbitrary code with the caller's signer authority.
2. **Wrong signer seeds**: the `signer_seeds` slice doesn't match the PDA the caller is claiming to be, so the callee sees a different signer than intended (or none).
3. **Wrong return-data trust**: the caller acts on `get_return_data()` without verifying which program produced it.

Anchor's `CpiContext` mitigates (1) when the target is a typed `Program<'info, T>` field, but bypasses are common.

## When to load this skill

Trigger on **any** of:

- `solana_program::program::invoke` / `invoke_signed`.
- `anchor_lang::context::CpiContext::new` / `CpiContext::new_with_signer`.
- `anchor_spl::token::transfer` / `transfer_checked` / `mint_to` / `burn`.
- `anchor_spl::token_2022::*`.
- Any function ending in `_cpi` or starting with `cpi_`.
- A field in `#[derive(Accounts)]` of type `Program<'info, X>`.

## Step-by-step audit procedure

### 1. Enumerate every CPI call site

```bash
grep -rnE 'invoke\(|invoke_signed\(|CpiContext::new' programs/*/src/ --include='*.rs'
```

For each call site, record in a per-site row:

| Site | Callee program | Caller authority | Signer seeds | Account list |
|------|----------------|------------------|--------------|--------------|
| `vault.rs:142` | `Program<'info, Token>` | `vault_pda` | `[VAULT_SEED, mint.key().as_ref(), &[bump]]` | `from, to, authority, mint` |

The callee program is either:

- An `AccountInfo` / `UncheckedAccount` — **attacker-controllable**, audit step 2.
- A typed `Program<'info, X>` — Anchor enforces `field.key() == X::id()`, safe.
- A hardcoded `Pubkey` constant — audit step 3.

### 2. Audit attacker-controllable callee program

If the callee is `AccountInfo` / `UncheckedAccount`:

- Is there an explicit `if program.key() != &EXPECTED_PROGRAM_ID { return Err(..) }` check? If NO → V36 candidate FINDING.
- Is the program key validated against a list of allowed callees (e.g. `if !ALLOWED.contains(&program.key()) { return Err(..) }`)? If the list is attacker-influenceable (stored in attacker-writable state) → V36 + V4 (state-controlled trust).
- Is there a `#[account(executable)]` constraint? This only checks that the account is a program — NOT that it's a specific program. Insufficient alone.

### 3. Audit signer seeds correctness

For every `invoke_signed` or `CpiContext::new_with_signer`:

- **Seeds match a derivable PDA**: Re-derive the PDA from the seeds using `Pubkey::find_program_address` and confirm it equals the account passed as authority. If the seeds list is `[arbitrary_attacker_bytes]`, the resulting "signer" PDA is attacker-derivable — V3 + V1.
- **Bump is canonical**: Either the bump comes from a stored `bump` field that was canonically derived at init time, OR `find_program_address` is called in-line. A user-supplied bump argument is V3.
- **Signer count**: `signer_seeds.len()` matches the number of PDA signers expected by the callee. CPIs that pass more or fewer signer sets than the callee instruction expects fail in surprising ways.

### 4. Audit account-list shape

The CPI's account-list (the `&[AccountInfo]` slice) must include every account the callee instruction declares — in order. Anchor's typed `CpiContext` enforces this when the call is via `anchor_spl::token::transfer(CpiContext::new(...), amount)`, but raw `invoke` calls don't:

```rust
// SAFE — Anchor enforces shape:
token::transfer(CpiContext::new_with_signer(
    token_program.to_account_info(),
    Transfer { from, to, authority },
    signer_seeds,
), amount)?;

// SUSPECT — raw invoke, audit the manual account-list:
invoke_signed(
    &spl_token::instruction::transfer(...)?,
    &[from.to_account_info(), to.to_account_info(), authority.to_account_info(), token_program.to_account_info()],
    signer_seeds,
)?;
```

If the raw-invoke variant is in use, verify each account passed is the account the instruction needs (use `spl-token-instruction.rs` as the comparator).

### 5. Audit return-data handling

Solana programs can read the previous instruction's return data via `get_return_data()`. The return data carries the producing program's ID — callers MUST verify it:

```rust
let (program_id, data) = get_return_data().ok_or(...)?;
if program_id != EXPECTED { return Err(..) }   // <-- required
let parsed: Foo = Foo::try_from_slice(&data)?;
```

Findings:

- `get_return_data()` consumed without checking `program_id` → V42 (any program in the transaction can spoof the data).
- Return data parsed into a type without bounds-checking → V25 (panic on malformed bytes) + DoS.

### 6. Audit reentry windows

Solana doesn't have synchronous reentrancy in the EVM sense, but CPIs CAN re-invoke the calling program if:

- The CPI target is itself the caller's program (self-CPI).
- The CPI target is allowed to CPI back into the caller (cross-program reentry).

Look for state writes that occur BEFORE the CPI returns. If the CPI's callee can re-enter and observe inconsistent state, that's a CEI-violation finding:

```rust
// SUSPECT pattern:
*self.balance -= amount;                   // state change BEFORE CPI
token::transfer(...)?;                     // CPI — if callee re-enters here, balance is stale-low
self.last_action = Clock::get()?.slot;     // state change AFTER CPI
```

The CEI invariant (Checks → Effects → Interactions) applies: read state and validate, write state to a consistent post-action snapshot, THEN CPI. Anchor's account-mutation discipline (`Account<T>` writes to the borrow buffer that's flushed at instruction exit) makes mid-instruction reentry on the same account difficult but not impossible.

### 7. Audit Token vs Token-2022 dispatch

Two SPL token programs exist with the same instruction layout but different account constraints. A CPI that's hardcoded to `spl_token::id()` will fail on Token-2022 mints; a CPI that's hardcoded to `spl_token_2022::id()` will fail on classic Token mints. Programs that handle both must dispatch based on the mint's owner:

```rust
let token_program_id = mint.to_account_info().owner;
match *token_program_id {
    id if id == &spl_token::id() => ...
    id if id == &spl_token_2022::id() => ...
    _ => return Err(InvalidMint)
}
```

Mis-dispatch lets the attacker pass a Token-2022 mint to a Token-only path (or vice versa) and trigger silent failures or, worse, state changes that the actual token program rejects but the audited program records as success.

Cross-skill load: [`spl-token-2022-extensions.md`](spl-token-2022-extensions.md).

## What counts as a finding

| Finding shape | Vector | Severity floor |
|---------------|--------|----------------|
| CPI callee is `AccountInfo` with no program-id verification | V36 | CRITICAL (arbitrary code execution under caller's authority) |
| `invoke_signed` with attacker-controllable seeds | V3 + V1 | HIGH |
| User-supplied bump in `invoke_signed` | V3 | HIGH |
| `get_return_data()` used without `program_id` check | V42 | HIGH |
| State write before CPI that callee can observe inconsistent | CEI-violation | MEDIUM–HIGH |
| Token vs Token-2022 mis-dispatch | new | MEDIUM (logic bug + potential silent token loss) |

## What does NOT count (SC-2 / known design)

- Anchor's typed `Program<'info, X>` field — Anchor's macro enforces `key() == X::id()` and the audit is satisfied.
- CPI to a known sysvar address (Clock, Rent, etc.) without explicit check — sysvars are address-pinned by Solana runtime.
- `get_return_data()` consumed by a wrapper that immediately delegates to a different verified program — the verification is one layer out.

## Comparator citations

| Claim | Comparator |
|-------|------------|
| "Anchor's `Program<'info, X>` validates `key() == X::id()`" | `anchor-lang/src/accounts/program.rs:Program::try_accounts` |
| "spl-token transfer instruction account layout" | `spl-token/src/instruction.rs:transfer` (the canonical account-list shape) |
| "Solana runtime sets return-data program_id automatically" | `solana-program/src/program.rs:set_return_data` |

## Common false-positive shapes

- Self-CPI to the program's own ID for the explicit purpose of replaying state changes through Anchor's discipline — intentional pattern in some governance programs.
- Raw `invoke` to a constant-address program (e.g. `system_program::ID`) — the program ID is hardcoded, no substitution possible.
- `signer_seeds` arrays that look attacker-controlled but are derived from `Account<'info, T>` fields whose Borsh bytes are already validated.
