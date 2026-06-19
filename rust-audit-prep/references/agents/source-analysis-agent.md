# Source Analysis Agent — Phases 3 & 5

You have: framework, project_dir, in-scope file list, and Grep + Read tools.

**CRITICAL: Do NOT read all source files at once. Use targeted Grep queries for each check.**

## Output Format

```
PHASE <N> | <Name> | SCORE: <X>/100

FAIL | <check> | <-N> | <file:line or n/a>
desc: <one factual sentence>
fix: <one sentence>

PASS | <check>
note: <brief evidence>

END PHASE <N>
```

## Phase 3: Code Hygiene (20%)

Run each Grep on in-scope source files (from your bundle's file list):

### Check 1: TODO/FIXME/HACK/XXX
Pattern: `TODO|FIXME|HACK|XXX`
Deduction: -3 each (cap -30)

### Check 2: println!/dbg!/print! macros
Pattern: `println!\|dbg!\|print!`
Exclude matches inside `#[cfg(test)]` blocks — only flag production code.
Deduction: -15 if any found in production

### Check 3: Commented-out code
Pattern: `^\s*//\s*(pub fn |fn |let |if |for |while |return |match |struct |impl )`
Count blocks of 3+ consecutive commented lines nearby.
Deduction: -2 per block (cap -20)

### Check 4: Missing overflow-checks
Grep `Cargo.toml` files for `overflow-checks = true` in `[profile.release]`.
Deduction: -15 if missing

### Check 5: unsafe blocks
Pattern: `unsafe\s*\{` or `unsafe\s+fn` or `unsafe\s+impl`
For each, check if a `// SAFETY:` comment exists nearby.
Deduction: -10 per unjustified unsafe (cap -30)

### Check 6: unwrap() on user-controlled input
Pattern: `\.unwrap\(\)`
For each match, Read 5 lines of context. Skip: `find_program_address`, `try_to_vec`, `Pubkey::create_with_seed`.
Only flag unwrap() on operations that could fail from user input.
Deduction: -3 each (cap -15)

### Check 7: Dead code
Pattern: `#\[allow\(dead_code\)\]`
Deduction: -5 each

### Check 8: as casts between integer types
Pattern: `as u8\b|as u16\b|as u32\b|as u64\b|as u128\b|as i32\b|as i64\b|as i128\b`
Exclude safe widening casts (u32 -> u64, u64 -> u128). Only flag narrowing or sign-changing casts.
Deduction: -5 each (cap -15)

## Phase 5: Best Practices (35%)

This is the most critical phase. Use the checklist from your bundle for the full reference.
Apply Anchor checks for programs with `anchor-lang`, native checks for `solana-program` only.

### Account Validation (Anchor)

#### AV1: Signer checks
Grep: `AccountInfo.*authority\|AccountInfo.*admin\|AccountInfo.*owner`
Check if these use `Signer<'info>` or have `is_signer` validation.
Deduction: -15 per missing signer check

#### AV2: Owner/discriminator checks
Grep: `UncheckedAccount` — check each has `/// CHECK:` doc.
Grep: `AccountInfo` used for data accounts — should be `Account<'info, T>`.
Deduction: -15 per missing owner check

#### AV3: PDA constraints
Grep: account structs (`#[derive(Accounts)]`) for PDA accounts.
Check each PDA has `seeds` + `bump` constraints.
Deduction: -10 per missing PDA constraint

#### AV4: has_one constraints
For state accounts with stored Pubkey fields, check that passed accounts use `has_one` or `address =` or manual comparison.
Deduction: -10 per missing validation

### Account Validation (Native)

#### NV1: is_signer checks
Grep: `is_signer` — count vs number of authority-like parameters.
Deduction: -15 per missing

#### NV2: Owner checks
Grep: `account.owner` — verify owner validation before deserialization.
Deduction: -15 per missing

### CPI Safety

#### CPI1: Program ID verification
Grep: `invoke\(|invoke_signed\(`
For each, check that the target program key is verified (typed `Program<'info, T>` or explicit key check).
Deduction: -15 per arbitrary CPI target

#### CPI2: Post-CPI reload
Grep: `\.reload\(\)` near CPI calls.
If account data is used after a CPI without reload, flag it.
Deduction: -10 per missing reload

### Token & SPL Safety

#### T1: Token program typing
Grep: `AccountInfo` used for token program — should be `Program<'info, Token>` or `Interface<'info, TokenInterface>`.
Deduction: -15

#### T2: Mint/authority validation
Check token accounts have `token::mint` or `has_one` constraints binding them to expected mints.
Deduction: -10 per missing

### Token-2022 Extensions

#### T22-1: Extension enumeration
If the project accepts Token-2022 mints, check whether it validates or whitelists extensions.
Deduction: -10 if accepting arbitrary extensions without checks (cap -30)

#### T22-2: Transfer Hook / Permanent Delegate
Check if these dangerous extensions are explicitly handled or rejected.
Deduction: -15 each if unhandled

### Arithmetic Safety

#### M1: Overflow protection
If `overflow-checks = true` in Cargo.toml, direct arithmetic is safe — PASS.
Otherwise grep for `checked_add\|checked_sub\|checked_mul\|checked_div` usage.
Deduction: -10 per unprotected arithmetic path (cap -30)

#### M2: Division ordering
Grep for division followed by multiplication patterns.
Deduction: -10 per instance

#### M3: Rounding direction
Check if fee/withdrawal calculations use floor vs ceil appropriately.
Deduction: -10 if incorrect

### Rust Quality

#### R1: Event emissions
For each instruction handler, check if it emits an event (`emit!`).
Deduction: -3 per missing event (cap -30)

#### R2: Custom errors
Check if the program uses custom error types vs generic `ProgramError::Custom(N)`.
Deduction: -10 if using generic errors

#### R3: Emergency pause
For DeFi programs handling user funds, check for pause mechanism.
Deduction: -10 if holding user funds without pause

## Constraints
- Use Grep and Read ONLY — no Bash commands
- Do NOT read all source files at once — use targeted queries
- Do NOT perform vulnerability analysis or threat modeling
- Output ONLY the structured PHASE/FAIL/PASS format
