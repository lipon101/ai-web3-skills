# SPL Token-2022 Extensions Audit (v0.4.2)

> **Loads when**: project imports `spl-token-2022` OR uses Token-2022 mint accounts OR handles arbitrary user-supplied mints.
> **Primary vectors**: V89, V90 (extension-aware variants).
> **Coordinates with**: [`anchor-cpi-safety.md`](anchor-cpi-safety.md), [`anchor-account-validation.md`](anchor-account-validation.md).

## What this surface is

SPL Token-2022 (program ID `TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb`) is the successor to classic SPL Token (`TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA`). Both expose the same core instructions (`Transfer`, `MintTo`, `Burn`, ...), but Token-2022 supports **extensions** — opt-in features attached to a mint or token account that change transfer/balance semantics:

| Extension | Behavior change | Risk if unmodeled |
|-----------|-----------------|-------------------|
| **TransferFeeConfig** | Each `Transfer` deducts a fee, recipient gets less than sent | Constant-product invariants break; "amount sent == amount received" assumption false |
| **TransferHook** | Each `Transfer` invokes a user-defined program after balance update | Reentry surface; hook program can call back into the original caller |
| **ConfidentialTransferMint** | Balances are zero-knowledge-encrypted | Off-chain accounting can't read balances; `Account.amount` is zero-or-meaningless |
| **NonTransferable** | Token can be minted/burned but not transferred | Transfer-based withdraw paths fail silently |
| **PermanentDelegate** | A fixed pubkey can move any token in any account | Custody assumptions broken |
| **InterestBearingMint** | UI amount differs from raw amount based on accrued interest | Math on raw amounts is correct; math on `ui_amount` is time-sensitive |
| **DefaultAccountState** | New accounts are frozen by default | Token accounts may exist but be unusable |
| **MintCloseAuthority** | Mint can be closed → supply revoked | Long-term integrations may see the mint disappear |
| **ImmutableOwner** | Token account owner can't change | Used by ATAs; checking owner-equality is now stable |
| **CpiGuard** | Blocks the account from being used in CPIs | Programs that CPI with this account as source/dest hit unexpected errors |

A program that "supports SPL tokens" but doesn't enumerate which extensions it tolerates is implicitly trusting attacker-mint creators not to enable problematic extensions.

## When to load this skill

Trigger on **any** of:

- `use spl_token_2022::...` import.
- `use anchor_spl::token_2022::...` import.
- `mint.to_account_info().owner == &spl_token_2022::id()` runtime check.
- The program accepts a user-supplied mint (i.e. mint is `Account<'info, Mint>` or `InterfaceAccount<'info, Mint>` with no `address = <const>` constraint).
- The program uses `anchor_spl::token_interface::*` (the token-program-agnostic interface).

## Step-by-step audit procedure

### 1. Inventory which mints the program touches

For each instruction, classify each mint:

| Mint origin | Token-2022 risk |
|-------------|------------------|
| Hardcoded constant (`address = STABLECOIN_MINT`) | Whatever extensions that mint has, by design. Document them. |
| Derived from a config account written by admin | Admin-trusted; risk if admin compromised. |
| User-supplied (no constraint) | **Attacker-controlled** — must handle every Token-2022 extension or refuse the mint. |

If the program accepts user-supplied mints, proceed to step 2. If all mints are hardcoded or admin-config'd, audit the documented set against the extensions table above.

### 2. Audit the program-id dispatch

The two token programs have different mint-owner pubkeys. Programs handling both must dispatch via the `mint.to_account_info().owner`:

```rust
let token_program = if mint.to_account_info().owner == &spl_token_2022::id() {
    token_2022_program_account
} else {
    token_program_account
};
```

Findings:

- Hardcoded `spl_token::id()` use with user-supplied mints → silently fails on Token-2022 mints; medium-severity logic bug.
- No mint-owner check → attacker passes a Token-2022 mint, program calls into classic `spl_token`, which rejects, but the program may have already mutated state. CEI-violation candidate.

### 3. Audit per-extension assumptions

For each extension the program could encounter, check whether the program's accounting invariants survive:

#### TransferFeeConfig

The recipient receives `amount - fee` for a given `Transfer`. Programs that assume `pre_balance + transferred == post_balance` are wrong:

```rust
let pre = vault.amount;
token::transfer(ctx, amount)?;
// SUSPECT: assuming vault.amount == pre + amount; if mint has TransferFee,
// the actual increase is amount - fee.
self.shares += amount;          // <-- inflates shares vs actual deposit
```

Fix pattern: use `Transfer Checked With Fee` (Token-2022's fee-aware transfer) AND read `post_balance - pre_balance` to compute actual received amount.

Finding: V89-variant (fee-on-transfer breaks constant-product or share-accounting).

#### TransferHook

Each `Transfer` triggers a CPI to the hook program after the balance update. The hook program receives the source, destination, and amount, and can do anything — including CPI back into the original caller.

Audit:

- The audited program must not rely on no-reentry assumptions during Token-2022 transfers.
- The hook program is attacker-installable on user-supplied mints. Treat as full attacker code execution inside the transfer call window.

Finding: reentry-via-hook → CEI-violation if program's pre-CPI state is mid-update.

#### NonTransferable

Mints with this extension reject every `Transfer` (only `MintTo` / `Burn` work). Programs that assume tokens are fungible-and-transferable break:

- Withdraw flows fail (can't transfer out).
- Vault accounting becomes inconsistent (mint succeeds, transfer reverts).

Finding: depending on the program's structure, MEDIUM–HIGH.

#### PermanentDelegate

A pubkey on the mint can transfer/burn any token. If the audited program assumes a token in a vault PDA can't move without the PDA's signature, that assumption is false for mints with PermanentDelegate.

Finding: HIGH (custody assumption broken).

#### ConfidentialTransferMint

Balance fields on token accounts are encrypted. `token_account.amount` is zero or meaningless. Programs that read `amount` to compute shares / payouts will compute wrong values.

Finding: HIGH on programs that read `amount` for accounting.

### 4. Audit `InterfaceAccount<'info, TokenAccount>` usage

Anchor's `anchor_spl::token_interface::*` types are token-program-agnostic (they accept both classic and Token-2022 accounts). When the audited program uses `InterfaceAccount` but downstream logic hardcodes `spl_token::id()` for CPIs, the dispatch is broken.

```rust
#[derive(Accounts)]
pub struct Withdraw<'info> {
    pub mint: InterfaceAccount<'info, Mint>,            // accepts both
    pub vault: InterfaceAccount<'info, TokenAccount>,   // accepts both
    pub token_program: Interface<'info, TokenInterface>, // must be the matching program
    // ...
}
```

The `token_program: Interface<'info, TokenInterface>` field must be passed by the caller and MUST match the mint's owner. Audit:

- `if token_program.key() != mint.to_account_info().owner { return Err(..) }` — required.
- All downstream CPIs use `token_program.to_account_info()`, not a hardcoded program id.

### 5. Audit extension parsing for unexpected types

`StateWithExtensions::<Mint>::unpack(&mint.to_account_info().data.borrow())?` parses the mint's extension data. If the program walks extensions, it must handle unknown extension types gracefully (return-error, not panic):

```rust
let state = StateWithExtensions::<Mint>::unpack(&data)?;
for ext_type in state.get_extension_types()? {
    match ext_type {
        ExtensionType::TransferFeeConfig => { ... }
        ExtensionType::TransferHook => { ... }
        // SUSPECT: missing arm + `_ => panic!()` or `_ => unreachable!()`
        _ => { /* must handle or explicitly reject */ }
    }
}
```

Finding: V25 panic-on-unknown-extension if user-supplied mint can have arbitrary extensions.

## What counts as a finding

| Finding shape | Severity floor |
|---------------|----------------|
| User-supplied mint accepted without mint-owner check | MEDIUM (logic) |
| User-supplied mint accepted without TransferFee handling on accounting paths | HIGH (V89-variant) |
| User-supplied mint accepted without TransferHook reentry consideration | HIGH (CEI-variant) |
| User-supplied mint with PermanentDelegate without acknowledgement | HIGH (custody) |
| `InterfaceAccount` used but CPI hardcodes a specific token program | MEDIUM (dispatch bug) |
| Extension-type match without exhaustive arm → panic on unknown | MEDIUM (DoS) |

## What does NOT count (SC-2 / known design)

- Programs that explicitly hardcode classic `spl_token::id()` and reject any other mint by design (with a clear `if mint.owner != &spl_token::id() { Err } `).
- Programs that whitelist mints (each whitelisted mint's extensions are auditor's responsibility, not the program's).
- Programs that operate on `mint.amount` as opaque integer with no semantic interpretation (e.g. counting deposits without computing share ratios).

## Comparator citations

| Claim | Comparator |
|-------|------------|
| "Token-2022 program ID" | `spl-token-2022/src/lib.rs` (the `id` macro) |
| "TransferFeeConfig deducts fee on Transfer" | `spl-token-2022/src/extension/transfer_fee/instruction.rs` |
| "TransferHook invokes program after transfer" | `spl-token-2022/src/extension/transfer_hook/instruction.rs` |
| "Anchor's `Interface<'info, TokenInterface>` accepts both program IDs" | `anchor-spl/src/token_interface.rs` |

## Common false-positive shapes

- Programs that accept only classic-token mints AND validate `mint.owner == &spl_token::id()` — Token-2022 isn't reachable.
- Programs that hold tokens but never call `Transfer` (mint/burn-only) — TransferFee and TransferHook don't apply.
- Programs whose accounting is in shares / LP-tokens whose mint they themselves create — they control which extensions exist.
