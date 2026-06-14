# 🟣 EVM CHAIN PLUGIN — Solidity / Vyper

> **Auto-loaded when**: Solidity (.sol) or Vyper (.vy) files detected.
> **Extends**: Universal Core Engine (SKILL.md)

This plugin adds EVM-specific intelligence to the universal analysis output.

---

## EVM-SPECIFIC DETECTION

```text
DETECTED:
  Chain:      Ethereum / L2 (Arbitrum, Optimism, Base, Polygon, etc.)
  Language:   Solidity / Vyper
  Framework:  Foundry / Hardhat / Brownie
  Code Unit:  Contract
  Entrypoint: Function (external/public)
  State Unit: Storage Slot + Mapping
  Plugin:     evm.md
```

---

## 🗄️ EVM STATE UNIT: STORAGE SLOT MAP

Simulate `forge inspect <contract> storage` output. Every state variable must have exact slot + offset:

```text
### Slot Map: [Contract Name]
*(Simulating `forge inspect <contract> storage`)*

| Slot # | Offset | Type | Variable Name | Bytes | Packed With / Notes |
|--------|--------|------|---------------|-------|---------------------|
| 0      | 0      | address | _owner | 20 | _initialized (Slot 0, offset 20) |
| 0      | 20     | bool | _initialized | 1 | _owner |
| 1      | 0      | uint256 | _totalSupply | 32 | — |
| 2      | 0      | mapping(address => uint256) | _balances | 32 | — |
| 3      | 0      | mapping(address => mapping(...)) | _allowances | 32 | — |
```

### Struct Packing Analysis
```text
| Struct | Fields | Total Slots | Wasted Bytes | Optimized Layout |
|--------|--------|------------|-------------|-----------------|
| Request | address user, uint256 amount, uint64 timestamp | 3 slots | 12 bytes | Reorder: amount (32), user+timestamp (28) → 2 slots |
```

### Immutables & Constants
```text
| Name | Type | Value/Set At | Storage? |
|------|------|-------------|----------|
| DECIMALS | uint8 | 18 | NO (constant, in bytecode) |
| token | address | constructor | NO (immutable, in bytecode) |
```

---

## 🛡️ PROXY SAFETY CHECK

```text
| Check | Status | Details |
|-------|--------|---------|
| Proxy pattern | <UUPS / Transparent / Beacon / Diamond / None> | |
| Storage gap present? | ✅/❌ | __gap[50] in base contracts |
| Initializer used? | ✅/❌ | initialize() with initializer modifier |
| No constructor state? | ✅/❌ | All state set in initialize() |
| Slot collision risk? | ✅/❌ | [Overlapping slots between proxy and logic] |
| selfdestruct present? | ✅/❌ | [Location if found] |
| delegatecall to untrusted? | ✅/❌ | [Location if found] |
```

---

## 🪃 EVM REENTRANCY SURFACE

Classic EVM reentrancy analysis:

```text
REENTRANCY ANALYSIS

| Function | External Call | Type | State Modified After? | Guard | Risk |
|----------|-------------|------|----------------------|-------|------|
| deposit() | transferFrom() | ERC20 | YES (totalSupply) | nonReentrant | ⚠️ MEDIUM |
| withdraw() | transfer() | ERC20 | NO (CEI pattern) | nonReentrant | ✅ SAFE |
| flashLoan() | callback() | Arbitrary | YES | — | 🔴 HIGH |
```

### Token Callback Vectors
```text
| Token Standard | Callback Mechanism | Risk |
|---------------|-------------------|------|
| ERC777 | tokensReceived() hook | 🔴 Reentrancy before state update |
| ERC721 | onERC721Received() | ⚠️ Callback in safeTransferFrom |
| ERC1155 | onERC1155Received() | ⚠️ Callback in safeTransferFrom |
| ERC4626 | — | No callback but share inflation risk |
```

---

## 🪙 ERC TOKEN COMPATIBILITY CHECKLIST

For every function that interacts with tokens:

```text
TOKEN COMPATIBILITY CHECKLIST

| Behavior | Impact | Handled? |
|----------|--------|---------|
| Fee-on-transfer | Received < expected, accounting drift | ✅/❌ |
| Rebasing (up/down) | Balance changes without transfer | ✅/❌ |
| ERC777 hooks | Reentrancy via tokensReceived() | ✅/❌ |
| Non-standard return | No bool return (USDT) | ✅/❌ |
| Pausable token | Transfers blocked | ✅/❌ |
| Blacklistable (USDC) | Address frozen, funds stuck | ✅/❌ |
| Upgradeable token | Behavior can change | ✅/❌ |
| Multiple entry points | Double-counting risk | ✅/❌ |
| Low decimals (USDC=6) | Precision loss in math | ✅/❌ |
| High decimals (>18) | Overflow risk in multiplication | ✅/❌ |
```

---

## 📝 EVM INLINE COMMENT SYNTAX (PRODUCTION-READY)

**CRITICAL**: When outputting INLINE_COMMENTS mode for EVM code, follow these exact syntax rules:

### Comment Syntax by Type
| Purpose | Syntax | Location |
|---------|--------|----------|
| System-level header | `//` | After SPDX, before contract |
| Function documentation | `///` | Immediately before function |
| Inline notes | `//` | End of line or separate line |
| NatSpec tags | `/// @` | For automated docs (optional) |

### System-Level Header (REQUIRED)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ═══════════════════════════════════════════════════════════════
// 🧠 SYSTEM INTELLIGENCE — <ContractName>.sol
// ═══════════════════════════════════════════════════════════════
//
// Protocol:       <Protocol Name>
// Chain:          EVM (Ethereum / <L2 Name>)
// Language:       Solidity
// Framework:      <Foundry/Hardhat/Brownie>
// Compiler:       ^0.8.19
//
// Contract Type:  <ERC20/ERC721/ERC4626/Custom>
// Upgradeable:    <YES/NO> (<UUPS/Transparent/Beacon/Diamond>)
// Trust Model:    <Trustless/Admin-Controlled/Timelock>
//
// 🎯 Purpose:
//    <1-2 sentence description>
//
// ═══════════════════════════════════════════════════════════════
// 🗄️ STORAGE LAYOUT (EIP-7201 / Standard Layout)
// ═══════════════════════════════════════════════════════════════
//
//   Slot # | Offset | Variable          | Type        | Size | Packed With
//   ───────┼────────┼───────────────────┼─────────────┼──────┼─────────────
//   0      | 0      | _owner            | address     | 20   | _initialized (offset 20)
//   0      | 20     | _initialized      | bool        | 1    | _owner
//   1      | 0      | _totalSupply      | uint256     | 32   | —
//   2      | 0      | _balances         | mapping     | 32   | — (keccak256 slot)
//   3      | 0      | _allowances       | mapping     | 32   | — (nested mapping)
//   4      | 0      | _name             | string      | 32   | — (dynamic)
//   5      | 0      | _symbol           | string      | 32   | — (dynamic)
//
//   Total Slots: <N> | Immutable Variables: <N> | Constants: <N>
//
// ═══════════════════════════════════════════════════════════════
// 🎭 ACTORS & ACCESS CONTROL
// ═══════════════════════════════════════════════════════════════
//
//   👤 User (UNTRUSTED): deposit, withdraw, transfer
//   👤 Admin (PRIVILEGED): setFee, pause, upgrade (onlyOwner)
//   👤 Keeper (TRUSTED): harvest, compound (onlyKeeper)
//
//   Access Matrix:
//     ┌──────────────┬─────────────────────────────────────────┐
//     │ onlyOwner    │ setFee(), setOracle(), upgrade()        │
//     │ onlyKeeper   │ harvest(), rebalance(), compound()       │
//     │ whenNotPaused│ deposit(), withdraw(), transfer()       │
//     │ Public       │ view functions, emergencyExit()          │
//     └──────────────┴─────────────────────────────────────────┘
//
// ═══════════════════════════════════════════════════════════════
// 💸 VALUE CUSTODY & INVARIANTS
// ═══════════════════════════════════════════════════════════════
//
//   Custody: Assets held at address(this)
//
//   🧮 Global Invariants (MUST always hold):
//     (1) totalSupply == Σ balanceOf[user] for all users
//     (2) totalAssets() >= totalSupply * convertToAssets(1)
//     (3) address(this).balance == 0 (no ETH accepted)
//
// ═══════════════════════════════════════════════════════════════
// 🧨 HIGH-RISK ZONES (Audit Priority)
// ═══════════════════════════════════════════════════════════════
//
//   🔴 deposit() — External call before state update [Reentrancy]
//   🔴 withdraw() — CEI pattern critical [Reentrancy]
//   🔴 harvest() — Delegatecall to strategy [Arbitrary code]
//   🔴 upgrade() — UUPS pattern [Admin privilege]
//
// ═══════════════════════════════════════════════════════════════

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// ... other imports

contract <ContractName> {
    // Contract body...
}
```

### Function-Level Documentation (REQUIRED for every external function)

```solidity
/// ═══════════════════════════════════════════════════════════════
/// 🧠 ENTRYPOINT INTELLIGENCE — <Contract>.<function>(<params>)
/// ═══════════════════════════════════════════════════════════════
///
/// 🎯 Purpose: <what this function does>
///
/// Signature: function <name>(<param types>) external|public <mutability>
/// Visibility: external | public
/// State Mutability: pure | view | payable | nonpayable
///
/// ═══════════════════════════════════════════════════════════════
/// 🎯 ATTACK SURFACE CLASSIFICATION
/// ═══════════════════════════════════════════════════════════════
///
///   [X] Capital Entry Point — ERC20.transferFrom receives tokens
///   [ ] Capital Exit Point
///   [X] Accounting Mutation — Mints shares, updates totalSupply
///   [ ] Price-Dependent Logic
///   [X] External Interaction Hub — Calls external token contract
///   [ ] Privileged Power
///   [ ] State Machine Transition
///
/// ═══════════════════════════════════════════════════════════════
/// 🧨 THREAT SURFACE ANALYSIS
/// ═══════════════════════════════════════════════════════════════
///
///   ┌─────────────────────────┬────────┬──────────────────────────┐
///   │ Vector                  │ YES/NO │ Details                  │
///   ├─────────────────────────┼────────┼──────────────────────────┤
///   │ REENTRANCY              │ [YES]  │ transferFrom callback    │
///   │ ORACLE MANIPULATION     │ [NO]   │ No price dependency      │
///   │ ACCESS CONTROL BYPASS   │ [NO]   │ Public function          │
///   │ INTEGER OVERFLOW        │ [NO]   │ Solidity 0.8+ checked    │
///   │ PRECISION LOSS          │ [YES]  │ Division rounds DOWN     │
///   │ ERC777 REENTRY          │ [YES]  │ tokensReceived hook      │
///   │ DOS / GAS LIMIT         │ [NO]   │ O(1) operations          │
///   └─────────────────────────┴────────┴──────────────────────────┘
///
/// ═══════════════════════════════════════════════════════════════
/// 🎭 ACCESS CONTROL
/// ═══════════════════════════════════════════════════════════════
///
///   Eligible Callers:
///     ✅ Anyone (UNTRUSTED) — No restrictions
///     ✅ EOA and Contracts — Both allowed
///
///   Guards:
///     - whenNotPaused — Reverts with "Pausable: paused" if paused
///     - nonReentrant — Prevents reentrancy (if applied)
///
///   Preconditions:
///     (1) assets > 0 — Reverts: "ZeroDeposit" at line <#>
///     (2) receiver != address(0) — Reverts: "ZeroAddress" at line <#>
///
/// ═══════════════════════════════════════════════════════════════
/// 💸 VALUE FLOW
/// ═══════════════════════════════════════════════════════════════
///
///   Inflow:  assets (ERC20) from msg.sender → address(this)
///            [Mechanism: IERC20(asset).transferFrom()]
///   Outflow: shares (internal) minted to receiver
///            [Mechanism: _mint(receiver, shares)]
///   Fee:     0 (deposits are fee-free)
///
///   Stuck Value Risk:
///     - Fee-on-transfer tokens: Accounting mismatch (NOT HANDLED)
///     - Rebasing tokens: Balance changes break shares calculation
///
/// ═══════════════════════════════════════════════════════════════
/// 🔗 EXECUTION PATH
/// ═══════════════════════════════════════════════════════════════
///
///   👤 caller invokes deposit(assets, receiver)
///     ├─ 🟥 require(assets > 0, "ZeroDeposit") — line 245
///     ├─ 🟥 require(receiver != address(0), "ZeroAddress") — line 246
///     ├─ 🟥 whenNotPaused modifier check — line 247
///     ├─ 🟦 uint256 shares = previewDeposit(assets) — line 248
///     │   └─ 🔹 _convertToShares(assets, Math.Rounding.Down)
///     ├─ 🟦 _mint(receiver, shares) — line 249
///     │   ├─ 🟦 _totalSupply += shares
///     │   └─ 🟦 _balances[receiver] += shares
///     ├─ 🔺 IERC20(asset).transferFrom(msg.sender, address(this), assets)
///     │   [EXTERNAL | Token Contract | REENTRANCY WINDOW OPEN]
///     │   └─ 🟨 if token is ERC777: tokensReceived callback triggered
///     └─ 🟨 emit Deposit(msg.sender, receiver, assets, shares)
///
/// ═══════════════════════════════════════════════════════════════
/// 🪃 REENTRANCY ANALYSIS
/// ═══════════════════════════════════════════════════════════════
///
///   External Call Location: Step 5 (transferFrom)
///   State Changes Before Call: shares minted (totalSupply, balanceOf)
///   State Changes After Call: None
///
///   ⚠️ CRITICAL: CEI Pattern VIOLATED
///     - State updated BEFORE external call
///     - shares minted before tokens received
///     - Risk: Inflation attack via reentrancy
///
///   Reentrancy Window: Step 5 (external call entry) → Step 6 (function end)
///   Risk Level: HIGH — Classic ERC4626 inflation attack vector
///   Mitigation: nonReentrant modifier prevents reentry
///
/// ═══════════════════════════════════════════════════════════════
/// 📌 CONCRETE EXAMPLE TRACE
/// ═══════════════════════════════════════════════════════════════
///
///   Input: assets = 1_000_000 USDC (6 decimals = $1.00), receiver = 0xUser
///
///   Initial State:
///     - totalSupply = 5_000 shares
///     - totalAssets() = 10_500_000 USDC
///     - balanceOf[receiver] = 0 shares
///
///   Computation:
///     shares = assets * totalSupply / totalAssets()
///     shares = 1_000_000 * 5_000 / 10_500_000
///     shares = 476 shares (rounding down)
///
///   Final State:
///     - totalSupply: 5_000 → 5_476 (+476)
///     - balanceOf[receiver]: 0 → 476 (+476)
///     - USDC balance: 10_500_000 → 11_500_000 (+1_000_000)
///
///   Events:
///     - Deposit(msg.sender=0xCaller, receiver=0xUser, assets=1000000, shares=476)
///
/// ═══════════════════════════════════════════════════════════════
/// ⚠️ FAILURE MODES
/// ═══════════════════════════════════════════════════════════════
///
///   ┌─────────────────────────┬─────────────────────┬──────┐
///   │ Condition               │ Revert Message      │ Line │
///   ├─────────────────────────┼─────────────────────┼──────┤
///   │ assets == 0             │ "ZeroDeposit"       │ 245  │
///   │ receiver == address(0)  │ "ZeroAddress"       │ 246  │
///   │ paused == true          │ "Pausable: paused"  │ 247  │
///   │ insufficient allowance  │ ERC20: allowance    │ 250  │
///   │ insufficient balance    │ ERC20: balance      │ 250  │
///   └─────────────────────────┴─────────────────────┴──────┘
///
/// ═══════════════════════════════════════════════════════════════
/// 🧪 EDGE CASES
/// ═══════════════════════════════════════════════════════════════
///
///   - assets = 0: Reverts with "ZeroDeposit"
///   - assets = 1: 0 shares minted (complete loss to rounding)
///   - totalSupply = 0: 1:1 ratio (first depositor gets assets = shares)
///   - receiver = address(this): Vault holds its own shares
///   - fee-on-transfer token: Accounting records more than received
///
/// ═══════════════════════════════════════════════════════════════
/// 🪙 ERC TOKEN CONSIDERATIONS
/// ═══════════════════════════════════════════════════════════════
///
///   SafeERC20: ✅ Used (handles non-standard returns)
///   Fee-on-transfer: ❌ NOT handled — assumed 1:1 transfer
///   Rebasing tokens: ❌ NOT supported — balance changes break accounting
///   ERC777: ⚠️ Hook calls tokensReceived — reentrancy risk
///   ERC721/1155: N/A — Only ERC20 assets supported
///
/// ═══════════════════════════════════════════════════════════════
/// 🔗 RELATED FUNCTIONS
/// ═══════════════════════════════════════════════════════════════
///
///   Opposite: withdraw(), redeem() — Burn shares, return assets
///   Depends On: previewDeposit(), _convertToShares() — Math accuracy
///   Called By: Frontend, aggregators, keeper bots
///
/// ═══════════════════════════════════════════════════════════════
function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
    // ... implementation preserved exactly as original ...
}
```

---

## ⛽ EVM-SPECIFIC GAS ANALYSIS

```text
GAS ANALYSIS

| Function | Warm (SLOAD cached) | Cold (first access) | Unbounded Loop? |
|----------|-------------------|-------------------|----------------|
| deposit() | ~45k | ~65k | NO |
| withdraw() | ~50k | ~70k | NO |
| rebalance() | ~120k | ~180k | YES ⚠️ (positions[]) |
```

---

## 🔗 EVM-SPECIFIC EXTERNAL CALLS

```text
DELEGATECALL SURFACE
| Source | Target | Trust Level | Risk |
|--------|--------|------------|------|
| Proxy.fallback() | Implementation | Trusted (admin-set) | Slot collision |

LOW-LEVEL CALL SURFACE
| Source | Target | Checks Return? | Risk |
|--------|--------|---------------|------|
| Vault._send() | user | NO ⚠️ | Silently fails |
```

---

## 🔴 EVM AUDIT CHECKLIST (Plugin Additions)

Add these to AUDIT_PREP output:

```text
EVM-SPECIFIC AUDIT POINTS

[ ] Storage slot layout verified against `forge inspect`
[ ] Proxy storage gap sufficient (typically __gap[50])
[ ] No selfdestruct in logic contract
[ ] No delegatecall to user-controlled address
[ ] SafeERC20 used for external token interactions
[ ] Reentrancy guards on all state-changing external-calling functions
[ ] ERC777/721/1155 callback vectors checked
[ ] Low-level call return values checked
[ ] msg.value checked in non-payable functions
[ ] Front-running / sandwich attack vectors analyzed
[ ] Flash loan attack vectors analyzed
```
