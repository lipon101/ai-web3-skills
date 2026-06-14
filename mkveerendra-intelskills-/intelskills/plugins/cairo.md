# 🟠 CAIRO CHAIN PLUGIN — Starknet

> **Auto-loaded when**: Cairo (.cairo) files detected.
> **Extends**: Universal Core Engine (SKILL.md)

This plugin adds Cairo/Starknet-specific intelligence to the universal analysis output.

---

## CAIRO-SPECIFIC DETECTION

```text
DETECTED:
  Chain:      Starknet (L2 on Ethereum)
  Language:   Cairo
  Framework:  Starknet Contracts / OpenZeppelin Cairo
  Code Unit:  Contract (marked with #[starknet::contract])
  Entrypoint: External Function (#[external(v0)] / #[abi(embed_v0)])
  State Unit: Storage Key (contract_address + variable key)
  Plugin:     cairo.md
```

---

## 🔴 STORAGE KEY MAP

Cairo storage is key-value based — map every variable to its storage address:

```text
### Storage Key Map: [Contract Name]

| Variable | Type | Storage Key Formula | Encoding | Notes |
|----------|------|-------------------|----------|-------|
| owner | ContractAddress | sn_keccak("owner") | felt252 | Single value |
| total_supply | u256 | sn_keccak("total_supply") | 2 felts (low, high) | u256 spans 2 storage slots |
| balances | Map<ContractAddress, u256> | h(sn_keccak("balances"), key) | 2 felts per entry | Pedersen hash for map |
| allowances | Map<(addr, addr), u256> | h(h(sn_keccak("allowances"), owner), spender) | 2 felts | Nested map |

### Storage Collision Check
| Risk | Details |
|------|---------|
| Key collision between contracts? | ❌ NO (contract_address scoped) |
| Key collision within contract? | ⚠️ Check custom storage keys |
| u256 split correctly (low/high)? | ✅/❌ |
```

---

## 🔴 FELT252 MATH RISK MAP

Cairo uses felt252 (prime field element) — different overflow behavior than integers:

```text
### Felt252 Math Analysis

| Operation | Location | Operand Types | Overflow Behavior | Risk |
|-----------|----------|--------------|------------------|------|
| a + b | line 45 | felt252 | Wraps modulo P | ⚠️ Silent wrap |
| a * b | line 52 | felt252 | Wraps modulo P | ⚠️ Silent wrap |
| a - b | line 60 | felt252 | Wraps (huge number) | 🔴 Underflow → large value |
| a / b | line 67 | felt252 | Field inverse (NOT integer div) | 🔴 NOT what you expect |
| a + b | line 70 | u256 | Panics on overflow | ✅ Safe (checked) |
| a * b | line 75 | u128 | Panics on overflow | ✅ Safe (checked) |

### Type Safety Recommendations
| Pattern | Risk Level | Recommendation |
|---------|-----------|---------------|
| felt252 arithmetic for balances | 🔴 HIGH | Use u256 instead |
| felt252 comparison | ⚠️ MEDIUM | Field elements have no natural ordering |
| felt252 → u128 casting | ⚠️ MEDIUM | Value may exceed u128 range |
| u256 for all accounting | ✅ SAFE | Checked arithmetic by default |

### Numeric Boundaries (Cairo)
| Type | Min | Max | Overflow? |
|------|-----|-----|----------|
| felt252 | 0 | P-1 (≈ 2^251) | Wraps silently |
| u8 | 0 | 255 | Panics |
| u128 | 0 | 2^128 - 1 | Panics |
| u256 | 0 | 2^256 - 1 | Panics |
```

---

## 🔴 L1 ↔ L2 MESSAGE FLOW

Starknet's unique L1-L2 messaging system:

```text
### L1 ↔ L2 Message Map

| Direction | Handler | Trigger | Payload | Risk |
|-----------|---------|---------|---------|------|
| L1 → L2 | #[l1_handler] deposit_from_l1 | L1 contract sends message | (user, amount) | ⚠️ Message replay? |
| L2 → L1 | send_message_to_l1_syscall | withdraw() calls | (user, amount) | ⚠️ L1 must consume |

### L1 Handler Security
| Check | Status | Details |
|-------|--------|---------|
| from_address validated? | ✅/❌ | Must verify L1 sender is trusted bridge |
| Replay protection? | ✅/❌ | Starknet handles nonce, but check logic |
| Message ordering dependency? | ✅/❌ | Does correctness depend on message order? |
| L1 failure handling? | ✅/❌ | What if L1 tx reverts after L2 state change? |

### Message Flow Diagram
```text
[L1 Bridge Contract]
      │
      ├── sendMessage(starknet_contract, selector, payload)
      │         │
      │    [Starknet Sequencer]
      │         │
      │    [L2 Contract: #[l1_handler] fn deposit_from_l1()]
      │         ├── 🟥 assert(from_address == L1_BRIDGE)
      │         ├── 🟦 balances[user] += amount
      │         └── 🟨 emit DepositFromL1(user, amount)
      │
[L2 Contract: fn withdraw()]
      ├── 🟦 balances[user] -= amount
      ├── 🔺 send_message_to_l1(L1_BRIDGE, [user, amount])
      └── 🟨 emit WithdrawToL1(user, amount)
           │
      [L1 Bridge Contract: consumeMessage()]
           └── transfer(user, amount)
```

---

## 🔴 CALL_CONTRACT TRUST SURFACE

Cairo's external call mechanism:

```text
### External Call Surface

| Caller | Target | Selector | Trust Level | Risk |
|--------|--------|----------|------------|------|
| vault.deposit() | IERC20.transferFrom() | selector!("transfer_from") | ⚠️ Token contract | Reentrancy via __default__ |
| vault.swap() | IAMm.swap() | selector!("swap") | ⚠️ External AMM | MEV / sandwich |
| proxy.__default__() | impl.* | dynamic | 🔴 Untrusted if impl changeable | Upgrade risk |

### Reentrancy in Cairo
Cairo contracts CAN be reentered (no built-in reentrancy guard like Solidity):
| Function | External Call | State After? | Reentrancy Guard? | Risk |
|----------|-------------|-------------|------------------|------|
| deposit() | IERC20.transfer_from() | YES | ❌ NO | 🔴 HIGH |
| withdraw() | IERC20.transfer() | NO (CEI) | — | ✅ SAFE |
```

---

## 🔴 UPGRADEABLE CONTRACT ANALYSIS

```text
### Upgrade Pattern Analysis

| Pattern | Details |
|---------|---------|
| Type | <Proxy/Dispatcher/Library Call/Non-upgradeable> |
| Proxy contract | <address> |
| Implementation class hash | <stored in storage key X> |
| Who can upgrade? | <admin address / multisig> |
| upgrade() function | <protected by what guard?> |

### Upgrade Safety Checklist
| Check | Status | Details |
|-------|--------|---------|
| Storage layout preserved? | ✅/❌ | New impl must keep same storage keys |
| Initializer pattern used? | ✅/❌ | initialized flag prevents re-init |
| Class hash validated? | ✅/❌ | Is new class hash checked before replace? |
| Admin can't brick contract? | ✅/❌ | Upgrade to invalid class hash? |
```

---

## 📝 CAIRO INLINE COMMENT SYNTAX (PRODUCTION-READY)

**CRITICAL**: When outputting INLINE_COMMENTS mode for Cairo code, follow these exact syntax rules:

### Comment Syntax by Type
| Purpose | Syntax | Location |
|---------|--------|----------|
| Module-level header | `//` | After imports, before contract |
| Function documentation | `///` | Immediately before function |
| Trait impl docs | `///` | Before impl block |
| Inline notes | `//` | Within function body |
| Starknet component docs | `///` | Before component definitions |

### Module-Level Header (REQUIRED)

```cairo
// ═══════════════════════════════════════════════════════════════
// 🧠 SYSTEM INTELLIGENCE — <contract_name>.cairo
// ═══════════════════════════════════════════════════════════════
//
// Protocol:       <Protocol Name>
// Chain:          Starknet (L2 on Ethereum)
// Language:       Cairo
// Framework:      <Starknet Contracts / OpenZeppelin Cairo>
// Cairo Version:  <2.x.x>
//
// Contract Type: <ERC20/ERC721/Account/Custom>
// Upgradeable:    <YES/NO> (<Proxy/Dispatcher/None>)
//
// 🎯 Purpose:
//    <Concise 1-2 sentence description>
//    <Example: "ERC20 token with minting and burning capabilities">
//
// ═══════════════════════════════════════════════════════════════
// 📦 STORAGE LAYOUT (Starknet K-V Storage)
// ═══════════════════════════════════════════════════════════════
//
//   ┌────────────────────────┬───────────┬──────────────────────────┬────────┐
//   │ Variable               │ Type      │ Storage Key Formula    │ Size   │
//   ├────────────────────────┼───────────┼──────────────────────────┼────────┤
//   │ owner                  │ felt252   │ sn_keccak("owner")       │ 1 felt │
//   │ total_supply           │ u256      │ sn_keccak("total_supply")│ 2 felts│
//   │ balances[addr]         │ u256      │ h(sn_keccak("balances"), addr)│ 2 felts│
//   │ allowances[owner][spend│ u256      │ h(h(sn_keccak("allowances"), owner), spender)│ 2 felts│
//   └────────────────────────┴───────────┴──────────────────────────┴────────┘
//
//   Key Collision Risk: [NO] — contract_address scope provides isolation
//   u256 Layout: [low: felt252, high: felt252] — 2 consecutive storage slots
//
// ═══════════════════════════════════════════════════════════════
// 🎭 ACTORS & CALLER IDENTIFICATION
// ═══════════════════════════════════════════════════════════════
//
//   👤 User (UNTRUSTED): transfer, approve, transfer_from
//      - Identification: get_caller_address()
//      - Constraints: balances[caller] >= amount
//
//   👤 Admin (PRIVILEGED): mint, burn, pause, upgrade
//      - Identification: caller == owner (stored in storage)
//      - Constraints: onlyOwner modifier enforced
//
//   👤 L1 Handler (TRUSTED): deposit_from_l1
//      - Identification: #[l1_handler] attribute
//      - Constraints: from_address == L1_BRIDGE_ADDRESS
//
// ═══════════════════════════════════════════════════════════════
// 🔐 ACCESS CONTROL MATRIX
// ═══════════════════════════════════════════════════════════════
//
//   ┌────────────────────┬─────────────────┬────────────────────────┐
//   │ Function             │ Guard           │ Caller Check           │
//   ├────────────────────┼─────────────────┼────────────────────────┤
//   │ constructor()        │ Once            │ No restrictions        │
//   │ transfer()           │ None            │ Implicit via balance   │
//   │ mint()                 │ onlyOwner       │ assert(caller == owner)│
//   │ burn()                 │ onlyOwner       │ assert(caller == owner)│
//   │ upgrade()              │ onlyOwner       │ assert(caller == owner)│
//   │ deposit_from_l1()      │ from_address    │ assert(from == L1_BRIDGE)│
//   └────────────────────┴─────────────────┴────────────────────────┘
//
// ═══════════════════════════════════════════════════════════════
// 🔗 EXTERNAL CALL TARGETS (call_contract syscall)
// ═══════════════════════════════════════════════════════════════
//
//   Target Contract         │ Usage                    │ Risk Level
//   ────────────────────────┼──────────────────────────┼─────────────
//   ERC20 token             │ transfer_from, transfer  │ ⚠️ REENTRANCY
//   ERC721 token            │ safe_transfer_from       │ ⚠️ CALLBACK
//   AMM/Router              │ swap, add_liquidity      │ 🔴 MEV RISK
//   Oracle                  │ get_price, latest_round  │ 🔴 PRICE MANIP
//
// ═══════════════════════════════════════════════════════════════
// ⚠️ FELT252 MATH WARNINGS (CRITICAL)
// ═══════════════════════════════════════════════════════════════
//
//   ⚠️ NEVER use felt252 for accounting — wraps silently modulo P
//   ⚠️ NEVER compare felt252 values — no natural ordering
//   ✅ ALWAYS use u256 for token amounts — panics on overflow
//   ✅ ALWAYS use u128 for intermediate values — panics on overflow
//
//   Numeric Type Safety:
//     - felt252: Field arithmetic, wraps silently — ⚠️ DANGEROUS for accounting
//     - u8/u16/u32/u64/u128: Panic on overflow/underflow — ✅ SAFE
//     - u256: Panic on overflow/underflow — ✅ SAFE for all accounting
//
// ═══════════════════════════════════════════════════════════════
// 🔗 L1 ↔ L2 MESSAGE FLOW
// ═══════════════════════════════════════════════════════════════
//
//   L1 → L2: #[l1_handler] deposit_from_l1(from_address, user, amount)
//     - Validates: from_address == L1_BRIDGE
//     - Action: Credits user balance on L2
//
//   L2 → L1: send_message_to_l1_syscall(L1_BRIDGE, [user, amount])
//     - Triggered by: withdraw_to_l1()
//     - Action: Initiates L1 withdrawal
//
// ═══════════════════════════════════════════════════════════════
// 🧨 HIGH-RISK FUNCTIONS (Audit Priority)
// ═══════════════════════════════════════════════════════════════
//
//   🔴 transfer_from(): call_contract to token — reentrancy risk
//   🔴 deposit_from_l1(): L1 handler validation — spoofing risk
//   🔴 upgrade(): Class hash replacement — total logic change
//   🔴 any felt252 math: Silent wrap — catastrophic accounting errors
//
// ═══════════════════════════════════════════════════════════════
// 💸 VALUE CUSTODY (u256 tokens)
// ═══════════════════════════════════════════════════════════════
//
//   Custody Location: contract storage (balances mapping)
//   Accounting Unit: u256 (never felt252!)
//
//   🧮 Global Invariants:
//     (1) total_supply == sum(balances[addr] for all addr)
//     (2) balances[addr] >= 0 (u256 unsigned guarantees this)
//     (3) allowance[owner][spender] <= balances[owner]
//
// ═══════════════════════════════════════════════════════════════

#[starknet::contract]
mod <ContractName> {
    // ... contract body ...
}
```

### Function Documentation (REQUIRED for every external function)

```cairo
    /// ═══════════════════════════════════════════════════════════════
    /// 🧠 ENTRYPOINT INTELLIGENCE — <Contract>::transfer
    /// ═══════════════════════════════════════════════════════════════
    ///
    /// 🎯 Purpose: Transfer u256 tokens from caller to recipient
    ///
    /// Signature: #[external(v0)] fn transfer(
    ///                ref self: ContractState,
    ///                recipient: ContractAddress,
    ///                amount: u256
    ///            ) -> bool
    ///
    /// ═══════════════════════════════════════════════════════════════
    /// 🎯 ATTACK SURFACE CLASSIFICATION
    /// ═══════════════════════════════════════════════════════════════
    ///
    ///   [ ] Capital Entry Point
    ///   [X] Capital Exit Point      — Value leaves caller's balance
    ///   [X] Accounting Mutation      — Updates balances mapping
    ///   [ ] Price-Dependent Logic
    ///   [X] External Interaction Hub — call_contract if ERC777
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
    ///   │ REENTRANCY              │ [YES]  │ call_contract callback      │
    ///   │ INTEGER OVERFLOW        │ [NO]   │ u256 panics on overflow     │
    ///   │ ACCESS CONTROL BYPASS   │ [NO]   │ balance check enforced      │
    ///   │ ADDRESS(0) TRANSFER     │ [NO]   │ checked in validation       │
    ///   │ SELF-TRANSFER           │ [YES]  │ allowed but no-op risk      │
    ///   │ CALLBACK HOOK           │ [YES]  │ ERC777 tokensReceived       │
    ///   └─────────────────────────┴────────┴─────────────────────────────┘
    ///
    /// ═══════════════════════════════════════════════════════════════
    /// 🎭 ACCESS CONTROL
    /// ═══════════════════════════════════════════════════════════════
    ///
    ///   Eligible Callers:
    ///     ✅ Anyone with positive balance (UNTRUSTED)
    ///     ✅ Contracts via transfer_from pattern
    ///
    ///   Guards:
    ///     - assert(!recipient.is_zero(), Errors::ZERO_ADDRESS)
    ///     - assert(self.balances.read(caller) >= amount, Errors::INSUFFICIENT_BALANCE)
    ///
    ///   Preconditions:
    ///     (1) caller balance >= amount — panic with INSUFFICIENT_BALANCE
    ///     (2) recipient != address(0) — panic with ZERO_ADDRESS
    ///
    /// ═══════════════════════════════════════════════════════════════
    /// 💸 VALUE FLOW
    /// ═══════════════════════════════════════════════════════════════
    ///
    ///   Inflow:  None (this is a transfer, not mint)
    ///   Outflow: amount from caller.balance → recipient.balance
    ///   Fee:     0 (transfers have no fee)
    ///
    ///   ⚠️ If recipient is ERC777 contract: callback triggered
    ///      Risk: Reentrancy before state fully updated
    ///
    /// ═══════════════════════════════════════════════════════════════
    /// 🔗 EXECUTION PATH
    /// ═══════════════════════════════════════════════════════════════
    ///
    ///   👤 caller invokes transfer(recipient, amount)
    ///     ├─ 🟥 assert(!recipient.is_zero(), Errors::ZERO_ADDRESS)
    ///     ├─ 🟦 caller_balance = self.balances.read(caller) // 0 gas (warm)
    ///     ├─ 🟥 assert(caller_balance >= amount, Errors::INSUFFICIENT_BALANCE)
    ///     ├─ 🟦 self.balances.write(caller, caller_balance - amount)
    ///     ├─ 🟦 recipient_balance = self.balances.read(recipient)
    ///     ├─ 🟦 self.balances.write(recipient, recipient_balance + amount)
    ///     ├─ 🔺 (IF ERC777) call_contract to recipient.tokensReceived(...)
    ///     │   [EXTERNAL | Recipient Contract | CALLBACK RISK]
    ///     └─ 🟨 self.emit(Transfer { from: caller, to: recipient, amount })
    ///
    /// ═══════════════════════════════════════════════════════════════
    /// 🪃 REENTRANCY ANALYSIS
    /// ═══════════════════════════════════════════════════════════════
    ///
    ///   External Call Location: Optional callback (ERC777 only)
    ///   State Updates Before Callback:
    ///     - caller balance: decreased
    ///     - recipient balance: increased
    ///
    ///   ⚠️ CEI Pattern: ✅ CORRECT for standard tokens
    ///     - All state updates complete before any external call
    ///     - ERC777 callback happens AFTER balances updated
    ///
    ///   Risk Assessment:
    ///     - Standard ERC20: [NONE] — no callbacks
    ///     - ERC777 tokens: [MEDIUM] — tokensReceived hook
    ///
    /// ═══════════════════════════════════════════════════════════════
    /// 📌 CONCRETE EXAMPLE TRACE
    /// ═══════════════════════════════════════════════════════════════
    ///
    ///   Input: recipient = 0xRecipient, amount = 1000 u256 (18 decimals)
    ///
    ///   Initial State:
    ///     - balances[caller] = 5000 u256
    ///     - balances[recipient] = 2000 u256
    ///
    ///   Computation:
    ///     caller_new = 5000 - 1000 = 4000 u256
    ///     recipient_new = 2000 + 1000 = 3000 u256
    ///
    ///   Final State:
    ///     - balances[caller]: 5000 → 4000 (-1000)
    ///     - balances[recipient]: 2000 → 3000 (+1000)
    ///     - total_supply: unchanged (5000 + 2000 = 7000 total)
    ///
    ///   Events:
    ///     - Transfer { from: caller, to: recipient, amount: 1000 }
    ///
    /// ═══════════════════════════════════════════════════════════════
    /// ⚠️ FAILURE MODES (Panic Conditions)
    /// ═══════════════════════════════════════════════════════════════
    ///
    ///   ┌─────────────────────────┬────────────────────────┬────────┐
    ///   │ Condition               │ Error                  │ Line   │
    ///   ├─────────────────────────┼────────────────────────┼────────┤
    ///   │ recipient == 0          │ Errors::ZERO_ADDRESS   │ 45     │
    ///   │ balance < amount        │ Errors::INSUFFICIENT   │ 48     │
    ///   │ underflow in subtraction│ implicit u256 panic    │ 50     │
    ///   │ overflow in addition    │ implicit u256 panic    │ 52     │
    ///   └─────────────────────────┴────────────────────────┴────────┘
    ///
    /// ═══════════════════════════════════════════════════════════════
    /// 🧪 EDGE CASES
    /// ═══════════════════════════════════════════════════════════════
    ///
    ///   - amount = 0: Succeeds, no-op (valid but wastes gas)
    ///   - amount = max u256: Panic if balance insufficient
    ///   - caller == recipient: Balance unchanged, event emitted (valid)
    ///   - recipient = contract: Depends on contract acceptance
    ///   - to non-ERC721 receiver: Valid (no safe transfer check)
    ///
    /// ═══════════════════════════════════════════════════════════════
    /// 🔗 RELATED FUNCTIONS
    /// ═══════════════════════════════════════════════════════════════
    ///
    ///   Complementary: transfer_from() — Spender-initiated transfer
    ///   Dependent On: balances mapping being accessible
    ///   Used By: Wallets, DEX contracts, aggregators
    ///
    /// ═══════════════════════════════════════════════════════════════
    #[external(v0)]
    fn transfer(
        ref self: ContractState,
        recipient: ContractAddress,
        amount: u256
    ) -> bool {
        // ... implementation preserved exactly as original ...
    }
```

---

## 🔴 CAIRO MODE: L1_L2_FLOW

Dedicated mode for L1↔L2 message analysis:

```text
## 📡 L1 ↔ L2 Flow: [Contract Name]

### Message Endpoints
| Direction | Function | Selector | Payload | Auth |
|-----------|----------|----------|---------|------|

### Message Lifecycle
L1 → L2: [Send on L1] → [Sequencer picks up] → [l1_handler executes on L2]
L2 → L1: [send_message_to_l1 on L2] → [Prove on L1] → [consumeMessage on L1]

### Failure Scenarios
| Scenario | Impact | Recovery |
|----------|--------|---------|
| L1 message never consumed | Funds stuck on L2 | Timeout/cancel mechanism? |
| L2 handler reverts | Message lost? Retry? | Depends on sequencer |
| L1 reorg after message sent | L2 state inconsistent | |
```

---

## 🔴 CAIRO AUDIT CHECKLIST (Plugin Additions)

```text
CAIRO-SPECIFIC AUDIT POINTS

[ ] All accounting uses u256 (not felt252) for checked arithmetic
[ ] felt252 arithmetic only used where field math is intentional
[ ] felt252 comparisons avoided (no natural ordering)
[ ] Storage keys correctly computed (especially for maps and u256)
[ ] #[l1_handler] validates from_address (L1 sender)
[ ] L1↔L2 message replay protection verified
[ ] Reentrancy protection implemented (no built-in guard in Cairo)
[ ] External calls via Dispatcher follow CEI pattern
[ ] Upgrade mechanism properly guarded
[ ] Storage layout compatible between proxy and implementation
[ ] Component storage doesn't collide with contract storage
[ ] get_caller_address() used correctly for access control
[ ] contract_address_const for hardcoded addresses (not felt literals)
[ ] Serialization/deserialization of complex types verified
[ ] Snapshot vs reference usage correct (gas implications)
```
