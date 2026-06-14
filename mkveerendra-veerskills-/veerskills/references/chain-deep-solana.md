# Chain Deep-Dive: Solana / Rust / Anchor

_Loaded when Phase 1.1 detects `.rs` files with `use anchor_lang`, `#[program]`, or `entrypoint!`. Sourced from exvul_solana_auditor (67 items/15 categories), solana-auditor-skills, and Trail of Bits Solana vulnerability scanner._

---

## Solana-Specific Attack Vectors (V211–V225)

**V211. Missing Account Owner Check** — D: Account deserialized without `owner == expected_program_id`. Attacker passes fake account owned by system program or malicious program with crafted data. FP: Anchor `Account<'info, T>` with `#[account]` attribute (auto-checks owner). Manual `if account.owner != &program_id { return Err(...) }`.

**V212. PDA Bump Seed Canonicalization** — D: `find_program_address` uses any bump (not canonical). Multiple valid PDAs for same seeds. Attacker creates lower-bump PDA with different data. FP: Anchor `seeds` + `bump` constraint stores canonical. Manual code uses `create_program_address` with stored canonical bump only.

**V213. Missing Signer Check on Privileged Instruction** — D: Authority account not marked as signer. Anyone can invoke admin functions. FP: Anchor `Signer<'info>` or `#[account(signer)]`. Manual `if !account.is_signer { return Err(...) }`.

**V214. Account Resurrection After Close** — D: Account closed (data zeroed, lamports drained) but program doesn't check `data_len() == 0` on subsequent use. Attacker re-funds account with crafted data. FP: Anchor `close = recipient` (sets discriminator to CLOSED). Manual close zeros discriminator + checks on read.

**V215. CPI Privilege Escalation via Signer Seeds** — D: Program passes signer seeds to CPI that an attacker can reconstruct. Attacker calls CPI-target program directly with same seeds. FP: PDA seeds include program-specific salt. CPI target validates `invoke_signed` origin.

**V216. Account Data Realloc Overflow** — D: `realloc` used to grow account beyond 10,240 bytes per instruction. Silently fails or panics. Or shrinks account without zeroing freed bytes — data leak. FP: Size validated before realloc. Freed bytes zeroed. Multi-instruction realloc with proper accounting.

**V217. Token-2022 Transfer Hook Reentrancy** — D: Token transfer triggers arbitrary transfer hook program. Hook can reenter calling program with manipulated state. FP: State updates before transfer. Hook program whitelisted. `invoke_signed` uses dedicated PDA per operation.

**V218. Duplicate Account Injection** — D: Same account passed in multiple positions (e.g., `source` and `destination`). Self-transfer creates double-credit. FP: `require!(source.key() != destination.key())`. Anchor `#[account(constraint = ...)]`.

**V219. Missing Rent Exemption Check** — D: Created account not rent-exempt. Gets garbage collected after ~2 years (or sooner with low balance). Protocol state vanishes. FP: `require!(account.lamports() >= rent.minimum_balance(data_len))`. Anchor `init` enforces rent exemption.

**V220. Arithmetic Overflow in Release Mode** — D: Rust wraps integers in `--release` (overflow doesn't panic). `checked_*` or `saturating_*` not used. FP: All arithmetic uses `checked_add/sub/mul/div` with proper error handling.

**V221. Account Data Type Confusion** — D: Account data deserialized as Type A when it was initialized as Type B. No discriminator check or wrong discriminator. FP: Anchor 8-byte discriminator auto-checked. Manual code validates discriminator bytes.

**V222. Stale Account Data After CPI** — D: Program reads account data, performs CPI (which modifies the account), then uses stale pre-CPI data. FP: Account re-read after CPI via `reload()`. Data dependency tracked.

**V223. Missing Instruction Introspection Validation** — D: Program should only execute as part of a specific instruction sequence (e.g., after a price oracle update) but doesn't validate via `sysvar::instructions`. FP: `load_instruction_at_checked()` verifies preceding instruction program ID and data.

**V224. Permanent Delegate Token Extension Abuse** — D: Token-2022 `permanent_delegate` extension allows holder's tokens to be transferred without approval. Protocol accepts such tokens without checking extensions. FP: Extension list checked on deposit. Permanent delegate tokens rejected.

**V225. Solana Clock Manipulation Risk** — D: `Clock::get()?.unix_timestamp` used for time-sensitive logic. Validators can slightly skew clock within bounds. FP: Time used for day-scale operations only. Slot number used for ordering guarantees.

---

## Solana Scanning Methodology

### Entry Point Discovery
```bash
# Find all instruction handlers
grep -rn "pub fn\|#\[instruction\]" --include="*.rs" | grep -v test
# Find CPI calls
grep -rn "invoke\|invoke_signed\|CpiContext" --include="*.rs" | grep -v test
# Find account validation
grep -rn "has_one\|constraint\|seeds\|bump\|signer" --include="*.rs" | grep -v test
```

### Critical Patterns to Grep
```bash
# Missing owner checks
grep -rn "AccountInfo" --include="*.rs" | grep -v "Account<\|Signer<\|Program<"
# Unsafe arithmetic
grep -rn "[\+\-\*\/]" --include="*.rs" | grep -v "checked_\|saturating_\|test"
# Account closing
grep -rn "close\|lamports" --include="*.rs" | grep -v test
# Token operations without extension checks
grep -rn "transfer\|mint_to\|burn" --include="*.rs" | grep -v test
```

### Solana PoC Template (Anchor)
```rust
use anchor_lang::prelude::*;
use anchor_lang::InstructionData;

#[cfg(test)]
mod exploit_test {
    use super::*;
    use solana_program_test::*;
    use solana_sdk::{signature::Keypair, signer::Signer, transaction::Transaction};

    #[tokio::test]
    async fn test_exploit() {
        let program_id = Pubkey::new_unique();
        let mut program_test = ProgramTest::new("target_program", program_id, None);
        let (mut banks_client, payer, recent_blockhash) = program_test.start().await;

        // 1. Setup attacker accounts
        // 2. Craft malicious instruction
        // 3. Submit transaction
        // 4. Assert exploit success
    }
}
```
