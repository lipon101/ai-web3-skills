# 🟣 SOLANA CHAIN PLUGIN — Rust / Anchor

> **Auto-loaded when**: Rust (.rs) files with Anchor or Solana program macros detected.
> **Extends**: Universal Core Engine (SKILL.md)

This plugin adds Solana-specific intelligence to the universal analysis output.

---

## SOLANA-SPECIFIC DETECTION

```text
DETECTED:
  Chain:      Solana
  Language:   Rust
  Framework:  Anchor / Native Solana Program
  Code Unit:  Program
  Entrypoint: Instruction
  State Unit: Account + PDA
  Plugin:     solana.md
```

---

## 🔴 ACCOUNT CONSTRAINT MATRIX

For every instruction, map ALL required accounts with their constraints:

```text
### Account Constraint Matrix: [Instruction Name]

| # | Account | Signer? | Writable? | Owner Check | PDA Seeds | Constraint Notes |
|---|---------|---------|-----------|-------------|-----------|-----------------|
| 0 | authority | ✅ YES | ❌ NO | — | — | Must be vault.authority |
| 1 | vault | ❌ NO | ✅ YES | This program | ["vault", authority] | has_one = authority |
| 2 | token_account | ❌ NO | ✅ YES | Token Program | — | token::mint = mint |
| 3 | mint | ❌ NO | ❌ NO | Token Program | — | Read-only |
| 4 | token_program | ❌ NO | ❌ NO | — | — | address = TOKEN_PROGRAM_ID |
| 5 | system_program | ❌ NO | ❌ NO | — | — | address = SYSTEM_PROGRAM_ID |
```

### Missing Constraint Risks
```text
| Account | Missing Check | Impact |
|---------|-------------|--------|
| vault | No owner check | ⚠️ Attacker can pass fake vault account |
| token_account | No mint check | ⚠️ Wrong token deposited |
| authority | Not signer | 🔴 Anyone can execute instruction |
```

---

## 🔴 PDA DERIVATION TRACE

Map all PDA derivations with collision analysis:

```text
### PDA Map

| PDA Name | Seeds | Bump | Purpose | Collision Risk |
|----------|-------|------|---------|---------------|
| vault | ["vault", authority.key] | canonical | Main vault state | LOW (unique per authority) |
| user_account | ["user", vault.key, user.key] | canonical | User deposit state | LOW |
| reward_pool | ["reward"] | canonical | Global reward pool | ⚠️ MEDIUM (no unique seed) |

### PDA Risks
- Are canonical bumps enforced? [YES/NO]
- Can attacker derive alternative PDA with different bump? [YES/NO]
- Seed uniqueness: [per-user / per-vault / global]
- Seed collision: Can two different inputs produce same PDA? [YES/NO]
```

---

## 🔴 CPI SURFACE MAP (Cross Program Invocation)

Solana's equivalent of external calls:

```text
### CPI Targets

| Instruction | CPI Target | Program ID | Authority Passed | Signer Seeds? | Risk |
|------------|-----------|-----------|-----------------|--------------|------|
| deposit() | Token::transfer | TokenkegQ... | vault PDA | ["vault", bump] | ⚠️ Authority escalation if seeds wrong |
| withdraw() | Token::transfer | TokenkegQ... | vault PDA | ["vault", bump] | ✅ Correct authority |
| swap() | Jupiter::route | JUP4Fb2... | user authority | — | 🔴 Untrusted program, MEV risk |

### CPI Trust Analysis
| Risk | Details |
|------|---------|
| Authority passing | Is the correct PDA authority passed? Can attacker substitute? |
| Program ID validation | Is CPI target program_id validated or hardcoded? |
| Return data trust | Does caller trust CPI return data without validation? |
| Reentrant CPI | Can CPI callback re-invoke this program? |
```

---

## 🔴 SIGNER PRIVILEGE ANALYSIS

```text
### Signer Escalation Check

| Instruction | Required Signer | What They Control | Escalation Risk |
|------------|----------------|------------------|----------------|
| initialize() | deployer | vault config, authority | LOW (one-time) |
| deposit() | user | their funds only | LOW |
| admin_withdraw() | authority | ALL vault funds | 🔴 HIGH (centralization) |
| update_config() | authority | fee rate, oracle | ⚠️ MEDIUM |
```

---

## 💰 LAMPORTS & RENT CUSTODY

```text
### Rent-Exemption Analysis

| Account | Size (bytes) | Min Rent-Exempt (lamports) | Funded By | Risk |
|---------|-------------|--------------------------|----------|------|
| vault | 256 | ~2,000,000 | deployer | LOW |
| user_account | 128 | ~1,500,000 | user | ⚠️ User must pay rent |

### Lamport Leak Check
- Can lamports be drained below rent-exempt minimum? [YES/NO]
- Are account closers properly refunding lamports? [YES/NO]
- Can attacker force account to be garbage-collected? [YES/NO]
```

---

## 📦 SOLANA STATE UNIT: ACCOUNT MAP

```text
### Account Map (State Units)

| Account | Type | Size | Seeds/PDA | Owner | Discriminator | Key Fields |
|---------|------|------|-----------|-------|--------------|-----------|
| Vault | Anchor Account | 256 | ["vault", auth] | Program | 8-byte hash | authority, total_deposited, fee_rate |
| UserState | Anchor Account | 128 | ["user", vault, user] | Program | 8-byte hash | deposited_amount, last_deposit_slot |

### Account Data Layout (byte-level)
| Offset | Size | Field | Type | Notes |
|--------|------|-------|------|-------|
| 0 | 8 | discriminator | [u8; 8] | Anchor auto-generated |
| 8 | 32 | authority | Pubkey | Signer for admin ops |
| 40 | 8 | total_deposited | u64 | Total lamports deposited |
| 48 | 8 | fee_rate | u64 | Basis points (1 = 0.01%) |
```

---

## 🔄 SOLANA UPGRADE ANALYSIS

```text
### Program Upgrade Check

| Check | Status | Details |
|-------|--------|---------|
| Upgradeable? | ✅/❌ | BPF Upgradeable Loader |
| Upgrade authority | <Pubkey> | Who can upgrade |
| Authority is multisig? | ✅/❌ | [Details] |
| Can authority be revoked? | ✅/❌ | set_upgrade_authority to None |
| Buffer account risks | ✅/❌ | Unauthorized buffer deployment |
```

---

## 📝 SOLANA INLINE COMMENT SYNTAX (PRODUCTION-READY)

**CRITICAL**: When outputting INLINE_COMMENTS mode for Solana code, follow these exact syntax rules:

### Comment Syntax by Type
| Purpose | Syntax | Location |
|---------|--------|----------|
| System-level header | `//` | Top of lib.rs |
| Instruction documentation | `///` | Immediately before handler function |
| Account struct docs | `///` | Before account struct fields |
| Inline notes | `//` | Within function body |
| Rust docs | `///` | Module-level items |

### System-Level Header (REQUIRED in lib.rs)

```rust
// ═══════════════════════════════════════════════════════════════
// 🧠 SYSTEM INTELLIGENCE — <ProgramName>
// ═══════════════════════════════════════════════════════════════
//
// Protocol:       <Protocol Name>
// Chain:          Solana
// Language:       Rust
// Framework:      <Anchor / Native Solana Program>
// Anchor Version: <0.x.x> (if applicable)
//
// Program ID:     <Pubkey> (mainnet) / <Pubkey> (devnet)
// Upgradeable:    <YES/NO> (<Upgrade Authority>)
//
// 🎯 Purpose:
//    <Concise 1-2 sentence description>
//    <Example: "Lending protocol enabling collateralized borrowing">
//
// ═══════════════════════════════════════════════════════════════
// 📦 ACCOUNT STRUCTURE (PDAs and Key Accounts)
// ═══════════════════════════════════════════════════════════════
//
//   ┌──────────────────┬─────────────────────────────────────────┬─────────────┐
//   │ Account          │ PDA Seeds                               │ Size        │
//   ├──────────────────┼─────────────────────────────────────────┼─────────────┤
//   │ Vault            │ ["vault", authority.key()]              │ 256 bytes   │
//   │ UserState        │ ["user", vault.key(), user.key()]       │ 128 bytes   │
//   │ Reserve          │ ["reserve", mint.key()]                 │ 512 bytes   │
//   │ Token Account    │ <ATA derivation>                          │ 165 bytes   │
//   └──────────────────┴─────────────────────────────────────────┴─────────────┘
//
// ═══════════════════════════════════════════════════════════════
// 🎭 ACTORS & SIGNER REQUIREMENTS
// ═══════════════════════════════════════════════════════════════
//
//   👤 User (UNTRUSTED): deposit, withdraw, borrow, repay
//      - Must sign: user account, user token account
//      - Constraint: token account owner == user
//
//   👤 Admin (PRIVILEGED): initialize, set_params, emergency_pause
//      - Must sign: admin key (stored in vault.admin)
//      - Constraint: signer == vault.admin
//
//   👤 Keeper (TRUSTED): liquidate, accrue_interest
//      - Must sign: keeper account (whitelisted)
//      - Permissionless: Anyone can call (incentivized)
//
// ═══════════════════════════════════════════════════════════════
// 🔐 ACCESS CONTROL MATRIX
// ═══════════════════════════════════════════════════════════════
//
//   Instruction          │ Signer Required    │ Account Constraints
//   ─────────────────────┼────────────────────┼─────────────────────────────
//   initialize()          │ deployer           │ vault not initialized
//   deposit()             │ user               │ user_token.owner == user
//   withdraw()            │ user               │ user_state.balance >= amount
//   liquidate()           │ keeper/anyone      │ health_factor < 1.0
//   admin_withdraw()      │ admin              │ signer == vault.admin
//
// ═══════════════════════════════════════════════════════════════
// 🔗 CPI TARGETS (External Program Calls)
// ═══════════════════════════════════════════════════════════════
//
//   Target Program            │ Program ID              │ Purpose
//   ──────────────────────────┼─────────────────────────┼───────────────────────
//   Token Program              │ TokenkegQfeZyiNwAJbN... │ Transfers, mints, burns
//   Associated Token Program   │ ATokenGPvbdGVxr1b2hv... │ ATA creation
//   System Program             │ 11111111111111111111... │ Account creation
//   <External Protocol>        │ <Pubkey>                │ <Purpose>
//
// ═══════════════════════════════════════════════════════════════
// 🧨 HIGH-RISK INSTRUCTIONS (Audit Priority)
// ═══════════════════════════════════════════════════════════════
//
//   🔴 deposit(): CPI to token program — authority passing risk
//   🔴 withdraw(): PDA signer seeds validation critical
//   🔴 liquidate(): Price oracle dependency — manipulation risk
//   🔴 borrow(): Collateral calculation — precision loss risk
//
// ═══════════════════════════════════════════════════════════════
// 💸 VALUE CUSTODY (Lamports & SPL Tokens)
// ═══════════════════════════════════════════════════════════════
//
//   Custody Locations:
//     - SPL Tokens: Program-associated token accounts (PDA-owned)
//     - SOL/Lamports: Accounts owned by program PDAs
//
//   🧮 Custody Invariants:
//     (1) reserve.token_balance >= Σ user.deposited_amount
//     (2) vault.total_borrows <= vault.borrow_cap
//     (3) All token accounts remain rent-exempt after operations
//
// ═══════════════════════════════════════════════════════════════

use anchor_lang::prelude::*;
use anchor_spl::token::{self, Token, TokenAccount, Transfer};
// ... other imports

declare_id!("<PROGRAM_ID>");

#[program]
pub mod <program_name> {
    use super::*;
    // ... instructions
}
```

### Instruction Handler Documentation (REQUIRED)

```rust
/// ═══════════════════════════════════════════════════════════════
/// 🧠 ENTRYPOINT INTELLIGENCE — <Program>::deposit
/// ═══════════════════════════════════════════════════════════════
///
/// 🎯 Purpose: Deposit SPL tokens into vault and mint position tokens
///
/// Context: DepositContext — 8 accounts required
/// Anchor Constraint: has_one = vault_authority on user_vault
///
/// ═══════════════════════════════════════════════════════════════
/// 🎯 ATTACK SURFACE CLASSIFICATION
/// ═══════════════════════════════════════════════════════════════
///
///   [X] Capital Entry Point      — Token transfer into program
///   [ ] Capital Exit Point
///   [X] Accounting Mutation      — Updates user position, vault totals
///   [ ] Price-Dependent Logic
///   [X] External Interaction Hub — CPI to Token Program
///   [ ] Privileged Power
///   [ ] State Machine Transition
///
/// ═══════════════════════════════════════════════════════════════
/// 🧨 THREAT SURFACE ANALYSIS
/// ═══════════════════════════════════════════════════════════════
///
///   ┌─────────────────────────┬────────┬─────────────────────────────┐
///   │ Vector                  │ YES/NO │ Details                     │
///   ├─────────────────────────┼────────┼─────────────────────────────┤
///   │ CPI TRUST               │ [YES]  │ Token program assumed honest  │
///   │ SIGNER PRIVILEGE        │ [YES]  │ PDA signer seeds critical   │
///   │ ACCOUNT CONFUSION       │ [YES]  │ Wrong token account passed  │
///   │ RENT EXEMPTION          │ [NO]   │ Rent sysvar auto-calculated │
///   │ INTEGER OVERFLOW        │ [NO]   │ Rust checked math (u64)     │
///   │ COMPUTE UNIT EXHAUSTION │ [NO]   │ ~15k CU, well under limit   │
///   └─────────────────────────┴────────┴─────────────────────────────┘
///
/// ═══════════════════════════════════════════════════════════════
/// 📋 REQUIRED ACCOUNTS (8 accounts in order)
/// ═══════════════════════════════════════════════════════════════
///
///   ┌──┬─────────────────────┬────────┬─────────┬────────────────────────────┐
///   │# │ Account             │ Signer │ Writable│ Constraints                │
///   ├──┼─────────────────────┼────────┼─────────┼────────────────────────────┤
///   │0 │ depositor           │ ✅ YES │ ❌ NO   │ Must pay for TX            │
///   │1 │ depositor_token     │ ❌ NO  │ ✅ YES  │ owner = depositor          │
///   │2 │ vault_token         │ ❌ NO  │ ✅ YES  │ owner = vault_authority    │
///   │3 │ vault_authority     │ ❌ NO  │ ❌ NO   │ PDA seeds = ["auth"]       │
///   │4 │ user_position       │ ❌ NO  │ ✅ YES  │ PDA seeds = ["pos", dep..]  │
///   │5 │ vault_state         │ ❌ NO  │ ✅ YES  │ program-owned              │
///   │6 │ token_program       │ ❌ NO  │ ❌ NO   │ = TOKEN_PROGRAM_ID         │
///   │7 │ system_program      │ ❌ NO  │ ❌ NO   │ = SYSTEM_PROGRAM_ID      │
///   └──┴─────────────────────┴────────┴─────────┴────────────────────────────┘
///
/// ═══════════════════════════════════════════════════════════════
/// 🔐 ACCESS CONTROL
/// ═══════════════════════════════════════════════════════════════
///
///   Eligible Callers:
///     ✅ Anyone with valid token account (UNTRUSTED)
///     ✅ Must own depositor_token account (Anchor validates)
///
///   Guards (Anchor constraints):
///     - depositor_token.owner == depositor.key()
///     - user_position seeds valid: ["pos", depositor.key(), vault.key()]
///     - vault_authority seeds valid: ["auth", vault.key()]
///
/// ═══════════════════════════════════════════════════════════════
/// 💸 VALUE FLOW
/// ═══════════════════════════════════════════════════════════════
///
///   Inflow:  amount (SPL tokens) from depositor_token → vault_token
///            [Mechanism: CPI to token::transfer]
///   Outflow: position shares to user_position account
///            [Mechanism: Direct account data update]
///   Fee:     0 (deposits have no fee)
///
///   Lamport Changes:
///     - depositor: -~5000 lamports (TX fee)
///     - user_position: unchanged (data size constant)
///
/// ═══════════════════════════════════════════════════════════════
/// 🔗 EXECUTION PATH
/// ═══════════════════════════════════════════════════════════════
///
///   👤 depositor invokes deposit(ctx, amount)
///     ├─ 🟥 Anchor validates all account constraints
///     ├─ 🟥 Check: amount > 0 — returns Err(InvalidAmount) if not
///     ├─ 🟦 Read: user_position.shares (current)
///     ├─ 🟦 Read: vault_state.total_deposits (current)
///     ├─ 🔹 Calculate: shares_to_mint = amount * total_shares / total_deposits
///     ├─ 🔺 CPI: token::transfer(depositor_token → vault_token, amount)
///     │   [EXTERNAL | Token Program | SIGNER: vault_authority PDA]
///     │   └─ Signer seeds: ["auth", vault.key()] passed to token program
///     ├─ 🟦 Write: user_position.shares += shares_to_mint
///     ├─ 🟦 Write: vault_state.total_deposits += amount
///     ├─ 🟦 Write: vault_state.total_shares += shares_to_mint
///     └─ 🟨 emit DepositEvent { depositor, amount, shares: shares_to_mint }
///
/// ═══════════════════════════════════════════════════════════════
/// 🪃 CPI TRUST WINDOW ANALYSIS
/// ═══════════════════════════════════════════════════════════════
///
///   CPI Call Location: Step 7 (token::transfer)
///   State Updates Before CPI:
///     - None (reads only)
///   State Updates After CPI:
///     - user_position.shares += shares_to_mint
///     - vault_state.total_deposits += amount
///
///   ⚠️ Checks-Effects-Interactions Pattern: ✅ CORRECT
///     - CPI happens BEFORE any state mutations
///     - If CPI fails, function returns error before state changes
///
///   Risk Assessment: LOW
///     - Token program is trusted system program
///     - No reentrancy possible (CPI depth limited, no callbacks)
///
/// ═══════════════════════════════════════════════════════════════
/// 📌 CONCRETE EXAMPLE TRACE
/// ═══════════════════════════════════════════════════════════════
///
///   Input: amount = 1_000_000_000 (1 USDC, 6 decimals)
///
///   Initial State:
///     - vault_state.total_deposits = 10_000_000_000 (10 USDC)
///     - vault_state.total_shares = 10_000_000_000
///     - user_position.shares = 0
///
///   Computation:
///     shares_to_mint = amount * total_shares / total_deposits
///     shares_to_mint = 1_000_000_000 * 10_000_000_000 / 10_000_000_000
///     shares_to_mint = 1_000_000_000 shares
///
///   Final State:
///     - vault_state.total_deposits: 10B → 11B (+1B USDC)
///     - vault_state.total_shares: 10B → 11B (+1B shares)
///     - user_position.shares: 0 → 1_000_000_000
///
///   CPI Details:
///     - Program: TokenkegQfeZyiNwAJbN...
///     - Instruction: Transfer { amount: 1_000_000_000 }
///     - Signers: vault_authority (PDA with seeds ["auth", vault])
///
/// ═══════════════════════════════════════════════════════════════
/// ⚠️ FAILURE MODES
/// ═══════════════════════════════════════════════════════════════
///
///   ┌─────────────────────────┬──────────────────────────┬─────────────────┐
///   │ Condition               │ Error                  │ Source          │
///   ├─────────────────────────┼──────────────────────────┼─────────────────┤
///   │ amount == 0             │ InvalidAmount            │ Program check   │
///   │ Invalid account owner   │ ConstraintOwner        │ Anchor validate │
///   │ Invalid PDA seeds       │ ConstraintSeeds          │ Anchor validate │
///   │ Insufficient balance    │ InsufficientFunds        │ Token program   │
///   │ Invalid token program   │ InvalidProgramId         │ Anchor validate │
///   │ Compute limit exceeded  │ ExceededMaxComputeUnits  │ Runtime         │
///   └─────────────────────────┴──────────────────────────┴─────────────────┘
///
/// ═══════════════════════════════════════════════════════════════
/// 🧪 EDGE CASES
/// ═══════════════════════════════════════════════════════════════
///
///   - amount = 0: Returns InvalidAmount
///   - amount = 1: 0 shares (rounding loss in integer division)
///   - total_deposits = 0: 1:1 ratio (first depositor)
///   - PDA not yet created: Anchor auto-initializes (init_if_needed)
///   - Account not rent-exempt: TX fails before program execution
///
/// ═══════════════════════════════════════════════════════════════
/// 🔥 COMPUTE UNIT ANALYSIS
/// ═══════════════════════════════════════════════════════════════
///
///   Unbounded iteration? [NO] — O(1) operations
///   CPI calls: 1 (token::transfer)
///   Account data reads: 3 accounts
///   Account data writes: 2 accounts
///   Estimated CU: ~12,000 (well under 200k limit)
///
/// ═══════════════════════════════════════════════════════════════
/// 🔗 RELATED INSTRUCTIONS
/// ═══════════════════════════════════════════════════════════════
///
///   Opposite: withdraw() — Burn shares, return tokens
///   Depends On: vault_state properly initialized
///   Called By: Frontend, keeper bots, liquidation flows
///
/// ═══════════════════════════════════════════════════════════════
pub fn deposit(ctx: Context<DepositContext>, amount: u64) -> Result<()> {
    // ... implementation preserved exactly as original ...
}
```

---

## 🔴 SOLANA MODE: ACCOUNT_GRAPH

Dedicated mode for deep account analysis:

```text
## 📊 Account Graph: [Program Name]

### Instruction → Account Dependencies
<instruction_name>
  ├─ 👤 authority [SIGNER]
  ├─ 🟦 vault [WRITABLE | PDA("vault", authority) | OWNER=program]
  ├─ 🟦 token_account [WRITABLE | OWNER=token_program]
  ├─ 📖 mint [READ-ONLY | OWNER=token_program]
  └─ ⚙️ token_program [PROGRAM]

### Account Lifecycle
| Account | Created By | Closed By | Can Be Recreated? |
|---------|-----------|----------|------------------|

### Authority Flow
[deployer] ──initialize()──▶ [vault.authority = deployer]
[deployer] ──transfer_authority()──▶ [vault.authority = new_auth]
```

---

## 🔴 SOLANA AUDIT CHECKLIST (Plugin Additions)

```text
SOLANA-SPECIFIC AUDIT POINTS

[ ] All accounts have proper owner checks
[ ] All PDAs use canonical bumps (or bumps are stored and reused)
[ ] Signer constraints correctly applied
[ ] Writable constraints minimal (principle of least privilege)
[ ] Account discriminators validated (Anchor does this, native doesn't)
[ ] CPI authority/signer_seeds correct
[ ] CPI target program_id validated
[ ] No account confusion (type A account passed where type B expected)
[ ] Rent-exemption maintained after all operations
[ ] Account closure properly zeroes data and refunds lamports
[ ] No remaining account injection attacks
[ ] Integer overflow checked (Rust panics on overflow in debug, wraps in release)
[ ] Clock/slot dependency analyzed for manipulation
[ ] Reinitialization prevented (init_if_needed risks)
```
