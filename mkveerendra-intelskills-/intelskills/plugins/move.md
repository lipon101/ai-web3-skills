# 🟢 MOVE CHAIN PLUGIN — Aptos / Sui

> **Auto-loaded when**: Move (.move) files detected.
> **Extends**: Universal Core Engine (SKILL.md)

This plugin adds Move-specific intelligence (Aptos and Sui) to the universal analysis output.

---

## MOVE-SPECIFIC DETECTION

```text
DETECTED:
  Chain:      Aptos / Sui
  Language:   Move
  Framework:  Aptos Framework / Sui Framework
  Code Unit:  Module
  Entrypoint: Entry Function (public entry / public fun)
  State Unit: Resource (in Global Storage)
  Plugin:     move.md
```

### Aptos vs Sui Differences
| Concept | Aptos | Sui |
|---------|-------|-----|
| Object model | Account-based resources | Object-centric (UID) |
| Storage | Global storage (move_to, borrow_global) | Object ownership |
| Upgrade | Package upgrade policy | Upgrade Cap |
| Coin type | Coin\<CoinType\> | Coin\<T\> with Balance\<T\> |
| Entry point | `public entry fun` | `public entry fun` (with TxContext) |

---

## 🔴 RESOURCE FLOW GRAPH

Map all resource operations — the core of Move security:

```text
### Resource Flow: [Module Name]

| Function | Resource | Operation | From | To | Abilities Used |
|----------|----------|-----------|------|-----|---------------|
| initialize() | Vault<CoinType> | move_to | — | @deployer | store, key |
| deposit() | Coin<CoinType> | merge | user | vault.coins | store |
| withdraw() | Coin<CoinType> | extract | vault.coins | user | store |
| destroy_vault() | Vault<CoinType> | move_from | @deployer | destroyed | — |

### Resource Lifecycle
[CREATED: move_to] ──borrow_global_mut──▶ [MODIFIED] ──move_from──▶ [DESTROYED]

### Resource Safety Checks
| Check | Status | Details |
|-------|--------|---------|
| Can resource be duplicated? | ✅ NO (no copy ability) | Move type system prevents |
| Can resource be dropped? | ✅/❌ | Only if `drop` ability present |
| Can resource be leaked? | ✅/❌ | Returned but never stored? |
| Resource existence check before access? | ✅/❌ | exists<T>() called before borrow? |
```

### Visual Resource Flow
```text
deposit():
  👤 user calls deposit(vault_addr, coin)
    🟥 assert!(exists<Vault>(vault_addr))
    🔹 vault = borrow_global_mut<Vault>(vault_addr)
    🟦 coin::merge(&mut vault.coins, coin)     ← Resource absorbed into vault
    🟨 emit DepositEvent(...)
```

---

## 🔴 CAPABILITY MODEL

Move uses capability patterns for admin control:

```text
### Capability Map

| Capability | Type | Held By | Can It Leak? | Functions Guarded |
|-----------|------|---------|-------------|------------------|
| AdminCap | Resource (no copy, no drop) | deployer | ❌ NO (no copy) | update_fee(), pause() |
| MintCap | Resource (no copy, store) | treasury | ⚠️ YES (store ability) | mint() |
| UpgradeCap | Resource | deployer | ❌ NO | upgrade_package() |

### Capability Leak Analysis
| Capability | Ability | Leak Vector | Risk |
|-----------|---------|------------|------|
| AdminCap | key, store | Can be stored in shared object (Sui) | ⚠️ MEDIUM |
| MintCap | key, store | Can be transferred via public_transfer | 🔴 HIGH |

### Capability Recommendations
- AdminCap should NOT have `store` ability (prevents transfer)
- MintCap should be wrapped in a struct that limits usage
```

---

## 🔴 MODULE UPGRADE POLICY

```text
### Upgrade Analysis

#### Aptos Package Upgrade
| Check | Status | Details |
|-------|--------|---------|
| Upgrade policy | <compatible / immutable / custom> | |
| Who controls upgrade? | <address/multisig> | |
| Can upgrade change resource layout? | ✅/❌ | Compatible upgrades cannot |
| Can upgrade add entry functions? | ✅/❌ | |
| Can upgrade remove functions? | ❌ NO | Compatible policy prevents |

#### Sui Upgrade Cap
| Check | Status | Details |
|-------|--------|---------|
| UpgradeCap exists? | ✅/❌ | |
| UpgradeCap holder | <address> | |
| Upgrade policy | <compatible / additive / dep_only / immutable> | |
| Can UpgradeCap be destroyed? | ✅/❌ | make_immutable() |
```

---

## 🔴 GLOBAL STORAGE ACCESS MAP

```text
### Global Storage Operations

| Function | Operation | Resource | Address | Mut? | Existence Check? |
|----------|-----------|----------|---------|------|-----------------|
| deposit() | borrow_global_mut | Vault | @vault_addr | ✅ YES | ✅ assert exists |
| get_balance() | borrow_global | Vault | @vault_addr | ❌ NO | ✅ assert exists |
| initialize() | move_to | Vault | @deployer | — | ✅ assert !exists |
| destroy() | move_from | Vault | @vault_addr | — | ✅ assert exists |

### Missing Existence Checks
| Function | Operation | Address | Risk |
|----------|-----------|---------|------|
| claim() | borrow_global_mut | @user | 🔴 ABORT if not exists |
```

---

## 🔴 ABORT CODE ANALYSIS

```text
### Abort Codes

| Code | Constant Name | Triggered By | Meaning |
|------|-------------|-------------|---------|
| 1 | E_NOT_AUTHORIZED | assert!(signer == admin) | Caller not admin |
| 2 | E_INSUFFICIENT_BALANCE | assert!(balance >= amount) | Not enough funds |
| 3 | E_VAULT_NOT_EXISTS | assert!(exists<Vault>(addr)) | Vault not initialized |
| 4 | E_ALREADY_INITIALIZED | assert!(!exists<Vault>(addr)) | Double init attempt |

### Abort Path Safety
| Function | Abort At | State Modified Before Abort? | Risk |
|----------|---------|---------------------------|------|
| deposit() | Line 45 | NO (checks first) | ✅ Safe |
| withdraw() | Line 78 | YES (balance updated) | 🔴 FUNDS AT RISK |
```

---

## 📦 MOVE STATE UNIT: RESOURCE MAP

```text
### Resource Map (State Units)

| Resource | Type Parameters | Abilities | Stored At | Key Fields |
|----------|----------------|-----------|-----------|-----------|
| Vault\<CoinType\> | CoinType: store | key, store | @vault_addr | coins: Coin\<CoinType\>, total_shares: u64 |
| UserPosition | — | key, store | @user_addr | shares: u64, last_deposit: u64 |
| AdminCap | — | key | @deployer | — |

### Ability Analysis
| Resource | copy | drop | store | key | Security Implication |
|----------|------|------|-------|-----|---------------------|
| Vault | ❌ | ❌ | ✅ | ✅ | Cannot duplicate, cannot accidentally destroy |
| Coin | ❌ | ❌ | ✅ | ❌ | Must be explicitly handled (no silent loss) |
| AdminCap | ❌ | ❌ | ❌ | ✅ | Cannot transfer, non-copyable — good |
```

---

## 📝 MOVE INLINE COMMENT SYNTAX (PRODUCTION-READY)

**CRITICAL**: When outputting INLINE_COMMENTS mode for Move code, follow these exact syntax rules:

### Comment Syntax by Type
| Purpose | Syntax | Location |
|---------|--------|----------|
| Module-level header | `//` | After module declaration |
| Function documentation | `///` | Immediately before function |
| Spec block docs | `///` | Before spec fun or spec module |
| Inline notes | `//` | Within function body |

### Module-Level Header (REQUIRED)

```move
module <address>::<module_name> {
    // ═══════════════════════════════════════════════════════════════
    // 🧠 SYSTEM INTELLIGENCE — <module_name>.move
    // ═══════════════════════════════════════════════════════════════
    //
    // Protocol:       <Protocol Name>
    // Chain:          <Aptos/Sui>
    // Language:       Move
    // Framework:      <Aptos Framework / Sui Framework>
    // Move Version:   <compiler version>
    //
    // Module Type:    <Entry Module / Library / Resource Definition>
    // Upgradeable:    <YES/NO> (<Upgrade Policy>)
    //
    // 🎯 Purpose:
    //    <Concise 1-2 sentence description>
    //    <Example: "Lending vault with fungible position shares">
    //
    // ═══════════════════════════════════════════════════════════════
    // 📦 RESOURCE DEFINITIONS (State Units)
    // ═══════════════════════════════════════════════════════════════
    //
    //   ┌────────────────────┬─────────────────┬───────────┬─────────────┐
    //   │ Resource           │ Type Parameters │ Abilities │ Stored At   │
    //   ├────────────────────┼─────────────────┼───────────┼─────────────┤
    //   │ Vault<CoinType>    │ CoinType: store   │ key, store│ @protocol   │
    //   │ UserPosition       │ —                 │ key, store│ @user_addr  │
    //   │ AdminCap           │ —                 │ key       │ @deployer   │
    //   └────────────────────┴─────────────────┴───────────┴─────────────┘
    //
    //   Ability Analysis:
    //     - Vault<CoinType>: copy=❌ drop=❌ store=✅ key=✅ (non-duplicable, non-droppable)
    //     - UserPosition: copy=❌ drop=❌ store=✅ key=✅ (safe for user funds)
    //     - AdminCap: copy=❌ drop=❌ store=❌ key=✅ (non-transferable admin power)
    //
    // ═══════════════════════════════════════════════════════════════
    // 🎭 ACTORS & SIGNER REQUIREMENTS
    // ═══════════════════════════════════════════════════════════════
    //
    //   👤 User (UNTRUSTED): deposit, withdraw, borrow, repay
    //      - Signer requirement: &signer parameter
    //      - Permission: Owns UserPosition at their address
    //
    //   👤 Admin (PRIVILEGED): update_params, emergency_pause, upgrade
    //      - Signer requirement: Must hold AdminCap resource
    //      - Permission: friend functions or AdminCap proof
    //
    //   👤 Keeper (TRUSTED): liquidate, accrue_interest
    //      - Signer requirement: None (public entry function)
    //      - Permission: Anyone can call with valid liquidation params
    //
    // ═══════════════════════════════════════════════════════════════
    // 🔐 ACCESS CONTROL MATRIX
    // ═══════════════════════════════════════════════════════════════
    //
    //   Function               │ Visibility      │ Guards / Constraints
    //   ───────────────────────┼─────────────────┼─────────────────────────────
    //   initialize()            │ public entry    │ signer == deployer (once)
    //   deposit<CoinType>()     │ public entry    │ exists<Vault<CoinType>>
    //   withdraw<CoinType>()    │ public entry    │ exists<UserPosition>
    //   update_fee()             │ public(friend)  │ friend modules only
    //   liquidate()              │ public entry    │ health_factor < 10000
    //
    // ═══════════════════════════════════════════════════════════════
    // 🔗 MODULE DEPENDENCIES
    // ═══════════════════════════════════════════════════════════════
    //
    //   ┌────────────────────────┬────────────────────────────────────────┐
    //   │ Module                 │ Usage                                  │
    //   ├────────────────────────┼────────────────────────────────────────┤
    //   │ aptos_framework::coin  │ Coin transfers, merge, extract         │
    //   │ aptos_framework::signer│ Signer address extraction              │
    //   │ aptos_framework::event   │ Event emission                         │
    //   │ aptos_std::type_info   │ Type validation for CoinType           │
    //   └────────────────────────┴────────────────────────────────────────┘
    //
    // ═══════════════════════════════════════════════════════════════
    // 💸 RESOURCE CUSTODY & INVARIANTS
    // ═══════════════════════════════════════════════════════════════
    //
    //   Custody Model:
    //     - Coins: Held in Vault<CoinType>.coins (Coin<CoinType>)
    //     - Positions: Tracked per-user in UserPosition resources
    //
    //   🧮 Global Invariants (MUST always hold):
    //     (1) sum_of_all_user_shares == vault.total_shares
    //     (2) Coin::value(vault.coins) >= vault.total_deposited
    //     (3) vault.total_borrows <= vault.borrow_cap
    //
    // ═══════════════════════════════════════════════════════════════
    // 🧨 HIGH-RISK FUNCTIONS (Audit Priority)
    // ═══════════════════════════════════════════════════════════════
    //
    //   🔴 deposit<CoinType>(): borrow_global_mut on user account — abort risk
    //   🔴 withdraw<CoinType>(): coin::extract — value validation critical
    //   🔴 liquidate(): Price dependency — oracle manipulation risk
    //   🔴 upgrade compatibility(): Resource layout changes — data loss risk
    //
    // ═══════════════════════════════════════════════════════════════

    // ... module body with functions ...
}
```

### Function Documentation (REQUIRED for every public entry function)

```move
    /// ═══════════════════════════════════════════════════════════════
    /// 🧠 ENTRYPOINT INTELLIGENCE — <module>::deposit<CoinType>
    /// ═══════════════════════════════════════════════════════════════
    ///
    /// 🎯 Purpose: Deposit Coin<CoinType> and mint position shares
    ///
    /// Signature: public entry fun deposit<CoinType>(
    ///                user: &signer,
    ///                vault_addr: address,
    ///                coin: Coin<CoinType>
    ///            )
    /// Visibility: public entry
    /// Type Parameter: CoinType — Must have store ability
    ///
    /// ═══════════════════════════════════════════════════════════════
    /// 🎯 ATTACK SURFACE CLASSIFICATION
    /// ═══════════════════════════════════════════════════════════════
    ///
    ///   [X] Capital Entry Point      — Coin<CoinType> absorbed into vault
    ///   [ ] Capital Exit Point
    ///   [X] Accounting Mutation      — Mints shares, updates totals
    ///   [ ] Price-Dependent Logic
    ///   [ ] External Interaction Hub — No external calls in Move
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
    ///   │ RESOURCE DUPLICATION    │ [NO]   │ No copy ability on Coin     │
    ///   │ RESOURCE LEAK           │ [NO]   │ coin consumed by merge      │
    ///   │ ABORT ON EXISTS CHECK   │ [YES]  │ aborts if Vault missing     │
    ///   │ TYPE SAFETY BYPASS      │ [NO]   │ CoinType enforced at compile│
    ///   │ PRECISION LOSS          │ [YES]  │ Integer division, DOWN      │
    ///   │ SIGNER IMPOSTER         │ [NO]   │ &signer prevents spoofing   │
    ///   └─────────────────────────┴────────┴─────────────────────────────┘
    ///
    /// ═══════════════════════════════════════════════════════════════
    /// 🎭 ACCESS CONTROL
    /// ═══════════════════════════════════════════════════════════════
    ///
    ///   Eligible Callers:
    ///     ✅ Anyone with valid signer reference (UNTRUSTED)
    ///     ✅ Must hold Coin<CoinType> (enforced by type system)
    ///
    ///   Guards:
    ///     - assert!(exists<Vault<CoinType>>(vault_addr), EVAULT_NOT_EXISTS)
    ///     - Coin<CoinType> parameter — type system validates ownership
    ///
    ///   Preconditions (abort if not met):
    ///     (1) Vault<CoinType> exists at vault_addr — abort code: 1
    ///     (2) Coin<CoinType> value > 0 — abort code: 2 (program check)
    ///
    /// ═══════════════════════════════════════════════════════════════
    /// 💸 VALUE FLOW (Resource Operations)
    /// ═══════════════════════════════════════════════════════════════
    ///
    ///   Inflow:  coin (Coin<CoinType>) from user → vault via coin::merge
    ///            [Mechanism: coin::merge(&mut vault.coins, user_coin)]
    ///   Outflow: shares to user_position (UserPosition.shares += minted)
    ///            [Mechanism: Direct struct field update]
    ///   Fee:     0 (deposits have no fee)
    ///
    ///   Resource Lifecycle:
    ///     [EXISTING] vault.coins ←── merge ── [MOVING] user_coin
    ///     [EXISTING] user_position.shares += minted_shares
    ///     [DESTROYED] user_coin (consumed, not dropped)
    ///
    /// ═══════════════════════════════════════════════════════════════
    /// 🔗 EXECUTION PATH
    /// ═══════════════════════════════════════════════════════════════
    ///
    ///   👤 user invokes deposit(user_signer, vault_addr, coin)
    ///     ├─ 🟥 assert!(exists<Vault<CoinType>>(vault_addr), EVAULT_NOT_EXISTS)
    ///     ├─ 🟥 assert!(coin::value(&coin) > 0, EINVALID_AMOUNT)
    ///     ├─ 🟦 vault = borrow_global_mut<Vault<CoinType>>(vault_addr)
    ///     ├─ 🟦 user_addr = signer::address_of(user_signer)
    ///     ├─ 🟦 shares_to_mint = calculate_shares(
    ///     │      coin_value * vault.total_shares / vault.total_coins)
    ///     ├─ 🟦 🟦 coin::merge(&mut vault.coins, coin) ←── coin CONSUMED here
    ///     │   [Coin<CoinType> merged into vault — resource move complete]
    ///     ├─ 🔹 ensure_user_position_exists(user_addr, vault_addr)
    ///     │   └─ 🟦 if !exists<UserPosition>(user_addr): move_to(...)
    ///     ├─ 🟦 user_pos = borrow_global_mut<UserPosition>(user_addr)
    ///     ├─ 🟦 user_pos.shares += shares_to_mint
    ///     ├─ 🟦 vault.total_shares += shares_to_mint
    ///     └─ 🟨 event::emit(DepositEvent { user: user_addr, ... })
    ///
    /// ═══════════════════════════════════════════════════════════════
    /// 📌 CONCRETE EXAMPLE TRACE
    /// ═══════════════════════════════════════════════════════════════
    ///
    ///   Input: coin = Coin<USDC> with value = 1_000_000 (6 decimals, $1.00)
    ///          vault_addr = @0xProtocol
    ///
    ///   Initial State:
    ///     - Vault<USDC>.total_coins = 10_000_000
    ///     - Vault<USDC>.total_shares = 10_000_000
    ///     - UserPosition.shares = 0
    ///
    ///   Computation:
    ///     shares_to_mint = 1_000_000 * 10_000_000 / 10_000_000
    ///     shares_to_mint = 1_000_000 (integer division, exact)
    ///
    ///   Resource State Changes:
    ///     - vault.coins.value: 10M → 11M (+1M USDC)
    ///     - vault.total_shares: 10M → 11M (+1M shares)
    ///     - user_position.shares: 0 → 1M (+1M shares)
    ///     - coin (input): DESTROYED (consumed by merge)
    ///
    /// ═══════════════════════════════════════════════════════════════
    /// 🧮 POSTCONDITIONS & INVARIANTS
    /// ═══════════════════════════════════════════════════════════════
    ///
    ///   [SCOPE: GLOBAL] vault.total_coins increased by deposited amount
    ///   [SCOPE: FUNCTION] user_position.shares increased by minted amount
    ///   [SCOPE: GLOBAL] vault.total_shares == sum(user_position.shares for all users)
    ///
    /// ═══════════════════════════════════════════════════════════════
    /// ⚠️ FAILURE MODES (Abort Conditions)
    /// ═══════════════════════════════════════════════════════════════
    ///
    ///   ┌─────────────────────────┬───────────┬──────────────────────────┐
    ///   │ Condition               │ Abort Code│ Abort Location           │
    ///   ├─────────────────────────┼───────────┼──────────────────────────┤
    ///   │ Vault<CoinType> !exists │ 1         │ borrow_global_mut        │
    ///   │ coin.value == 0         │ 2         │ user assertion check     │
    ///   │ Overflow in shares calc │ implicit  │ u64 arithmetic (panics)  │
    ///   │ User has no position    │ N/A       │ Auto-creates if needed   │
    ///   └─────────────────────────┴───────────┴──────────────────────────┘
    ///
    /// ═══════════════════════════════════════════════════════════════
    /// 🧪 EDGE CASES
    /// ═══════════════════════════════════════════════════════════════
    ///
    ///   - coin.value = 0: Aborts with EINVALID_AMOUNT
    ///   - coin.value = 1: 0 shares (rounding loss to integer division)
    ///   - vault.total_coins = 0: First depositor gets 1:1 ratio
    ///   - UserPosition doesn't exist: Auto-initialized via ensure_user_position
    ///   - CoinType mismatch: Compile-time type error (cannot happen at runtime)
    ///
    /// ═══════════════════════════════════════════════════════════════
    /// 🔗 RELATED FUNCTIONS
    /// ═══════════════════════════════════════════════════════════════
    ///
    ///   Opposite: withdraw<CoinType>() — Burn shares, return Coin
    ///   Depends On: initialize_vault<CoinType>() — Must be called first
    ///   Called By: Frontend, aggregator contracts, keeper bots
    ///
    /// ═══════════════════════════════════════════════════════════════
    public entry fun deposit<CoinType>(
        user: &signer,
        vault_addr: address,
        coin: Coin<CoinType>
    ) acquires Vault, UserPosition {
        // ... implementation preserved exactly as original ...
    }
```

---

## 🔴 MOVE MODE: RESOURCE_FLOW

Dedicated mode for deep resource analysis:

```text
## 🔄 Resource Flow: [Module Name]

### Resource Lifecycle Diagram
[CREATED: move_to(@addr, Resource{})]
      │
      ├── [BORROWED: borrow_global<R>(@addr)] (read-only)
      ├── [MUTATED: borrow_global_mut<R>(@addr)] (writable)
      │
[DESTROYED: move_from<R>(@addr)] or [TRANSFERRED: move_to(@new_addr, r)]

### Cross-Module Resource Movement
| Resource | From Module | To Module | Mechanism | Risk |
|----------|-----------|----------|-----------|------|
| Coin<APT> | user module | vault module | function param | ✅ Safe (type checked) |
| AdminCap | admin module | — | Never transferred | ✅ Safe |
```

---

## 🔴 MOVE AUDIT CHECKLIST (Plugin Additions)

```text
MOVE-SPECIFIC AUDIT POINTS

[ ] All resources properly handled (no silent drops without `drop` ability)
[ ] Existence checks (exists<T>) before borrow_global / borrow_global_mut
[ ] No resource duplication possible (no `copy` on value-bearing resources)
[ ] Capability types have minimal abilities (no unnecessary `store` on admin caps)
[ ] Abort codes properly defined and documented
[ ] No state modification before abort in critical paths
[ ] Module upgrade policy appropriate (immutable for high-value contracts)
[ ] Friend declarations minimal (principle of least privilege)
[ ] Coin operations use correct merge/extract patterns
[ ] Signer checks on all privileged entry functions
[ ] Global storage access patterns safe (no TOCTOU between exists and borrow)
[ ] Type parameters constrained appropriately
[ ] Phantom type parameters not misused
[ ] Object ownership correct (Sui: shared vs owned vs frozen)
```
