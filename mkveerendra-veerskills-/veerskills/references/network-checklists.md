# Multi-Network Security Checklists

Chain-specific vulnerability patterns and audit considerations across **7 networks**. Sourced from WEB3-AUDIT-SKILLS network scanners, exvul_solana_auditor (67 items/15 categories), solana-auditor-skills, move-auditor-skills, ton-auditor-skills, and Trail of Bits cosmos scanner. Auto-loaded by VeerSkills Phase 1 (RECON) based on detected platform.

---

## EVM / Solidity Checklist

### Compiler & Language
- [ ] Check `pragma solidity` version — <0.8.0 requires SafeMath verification
- [ ] Audit all `unchecked` blocks — trace value bounds for every operation inside
- [ ] Check for known compiler bugs: 0.8.13-0.8.14 (ABI encoder nested arrays), 0.8.15-0.8.19 (Yul optimizer)
- [ ] Verify `PUSH0` compatibility if deploying to L2s (0.8.20+ defaults to Shanghai)
- [ ] Check transient storage (`TSTORE`/`TLOAD`) usage if 0.8.24+ — new reentrancy patterns

### Token Handling
- [ ] `SafeERC20` used for ALL token transfers (handles USDT no-return, BNB quirks)
- [ ] Fee-on-transfer handling: balance-before/after pattern or token whitelist
- [ ] Rebasing token handling: internal accounting vs raw balance
- [ ] Token decimal assumptions: dynamic `decimals()` call, not hardcoded 18
- [ ] Approve race condition: use `safeIncreaseAllowance` or reset to 0 first
- [ ] Token blocklist handling (USDC, USDT can freeze addresses)

### DeFi-Specific (EVM)
- [ ] ERC-4626 vault: Virtual share offset or dead shares for inflation protection
- [ ] Oracle: Chainlink staleness + L2 sequencer uptime check
- [ ] AMM: Slippage protection + deadline on all swaps
- [ ] Lending: Liquidation threshold vs LTV ratio gap prevents bad debt
- [ ] Governance: Flash loan voting protection (snapshot-based voting power)
- [ ] Bridge: Message source + sender + nonce validated on receive

### EVM L2-Specific
- [ ] **Arbitrum/Optimism**: `block.number` semantics differ (returns L1 block on Arbitrum)
- [ ] **Arbitrum/Optimism**: Sequencer downtime → oracle stale price risk
- [ ] **zkSync Era**: `msg.value` behaves differently in system contracts
- [ ] **zkSync Era**: No `SELFDESTRUCT`, different CREATE address derivation
- [ ] **Blast**: ETH/USDB are rebasing by default — must set yield mode explicitly
- [ ] **Blast**: `balanceOf()` can change between transactions without transfers
- [ ] **Scroll/Linea**: zkEVM precompile/opcode cost differences

### Proxy / Upgrade
- [ ] `_disableInitializers()` in implementation constructor
- [ ] `__gap` arrays in all inherited upgradeable contracts
- [ ] ERC-1967 slot compliance for admin/implementation
- [ ] Storage layout consistency across upgrade versions
- [ ] UUPS: `_authorizeUpgrade` properly access-controlled
- [ ] Transparent proxy: Admin cannot call implementation functions

---

## Solana / Rust / Anchor Checklist

### Account Validation
- [ ] **Owner check**: Every account's `owner` field validated against expected program
- [ ] **Signer check**: All accounts requiring authorization have `is_signer` verification
- [ ] **PDA validation**: Seeds and bump verified for all Program Derived Addresses
- [ ] **Account type discrimination**: 8-byte discriminator checked (Anchor does this, native requires manual)
- [ ] **Data size**: Account data size validated before deserialization
- [ ] **Rent exemption**: Created accounts are rent-exempt or rent properly handled

### CPI (Cross-Program Invocation)
- [ ] **Privilege escalation**: CPI signer seeds cannot be guessed or replicated by attacker
- [ ] **Account substitution**: All accounts passed to CPI validated before invocation
- [ ] **Return data**: CPI return values checked (not all programs return success/failure)
- [ ] **Recursive CPI depth**: Maximum depth of 4 — verify stack doesn't overflow

### Arithmetic & Data
- [ ] **Integer overflow**: Rust panics on overflow in debug but wraps in release — use `checked_*` or `saturating_*`
- [ ] **Lamport accounting**: `from.lamports -= amount; to.lamports += amount;` must be atomic
- [ ] **Remaining accounts**: If using `remaining_accounts`, validate each account's program/owner
- [ ] **Account realloc**: `realloc` can only grow by 10240 bytes per top-level instruction

### Solana-Specific Attacks
- [ ] **Closing accounts**: `close` must zero data AND transfer lamports (prevent resurrection attack) `[CL-VI-02]`
- [ ] **Sysvar deprecation**: Use `Sysvar::get()` instead of passing sysvars as accounts `[CL-II-06]`
- [ ] **Priority fees**: MEV on Solana works differently — validators can reorder within blocks
- [ ] **Duplicate accounts**: Same account passed in multiple positions in instruction `[CL-VII-01]`
- [ ] **Orphan accounts**: Parent account deleted but child references remain — stale state `[CL-II-13]`
- [ ] **Account reloading**: CPI changes account state but caller uses stale pre-CPI data `[CL-IV-04]`

### Token-2022 / Token Extensions `[CAT-XII]`
- [ ] **Transfer hooks**: Token-2022 transfer hooks can execute arbitrary logic during transfer — reentrancy risk
- [ ] **Transfer fees**: Token extensions can deduct fees — actual received amount differs from transferred
- [ ] **Non-transferable tokens**: Soulbound/non-transferable extensions may break escrow/vault logic
- [ ] **Confidential transfers**: Encrypted amounts break balance assertions and math checks
- [ ] **Permanent delegate**: Extension allows infinite delegation — security assumption broken
- [ ] **Close authority**: Token-2022 close authority can delete mint — supply becomes unrecoverable
- [ ] **Metadata pointer**: Metadata can reference arbitrary external data — validation required

### Data Encoding / Decoding `[CAT-XIV]`
- [ ] **Borsh deserialization**: Untrusted data deserialized without validation — type confusion
- [ ] **Account discriminator manipulation**: 8-byte discriminator spoofable if not verified
- [ ] **Variable-length data**: Vec/String data exceeds account allocation — truncation or panic
- [ ] **Remaining bytes**: Extra trailing data in account after deserialization ignored silently

### Transaction-Level Security `[CAT-XIII]`
- [ ] **Instruction introspection**: `sysvar::instructions` can be used to enforce instruction ordering
- [ ] **Flashbots/Jito bundles**: Atomic bundles can manipulate multiple accounts in single slot

---

## Move / Aptos / Sui Checklist

### Resource Safety
- [ ] **Move semantics**: Resources cannot be copied or dropped unless ability granted
- [ ] **Ability constraints**: `key`, `store`, `copy`, `drop` — verify each type has minimal abilities
- [ ] **Hot potato pattern**: Objects without `drop` must be consumed — check anti-patterns
- [ ] **Object ownership**: Sui shared vs owned objects — shared objects have different consistency

### Sui-Specific
- [ ] **Shared objects**: Consensus ordering for shared object transactions — front-running risk
- [ ] **Transfer policies**: Custom transfer policies can restrict object movement
- [ ] **Dynamic fields**: Dynamic field access doesn't check type at compile time
- [ ] **Clock object**: `Clock` access for timestamps — single source of time truth
- [ ] **Package upgrades**: Upgrade caps control who can upgrade — verify proper custody

### Aptos-Specific
- [ ] **Resource account**: `create_resource_account` signer cap management
- [ ] **Coin registration**: `coin::register` required before receiving any coin type
- [ ] **Table vs SimpleMap**: Performance and gas implications for data structure choice
- [ ] **Events**: Event handle creation and emission for all state changes
- [ ] **Module publishing**: Module replacement vs upgrade semantics

### Common Move Patterns
- [ ] **Reentrancy**: Move's linear type system prevents most classic reentrancy, but cross-module callbacks possible
- [ ] **Integer overflow**: Move has checked arithmetic by default — `unchecked_*` must be audited
- [ ] **Access control**: `signer` validation for all privileged operations
- [ ] **Math precision**: Fixed-point math libraries — verify rounding direction
- [ ] **Capability pattern**: Capability creation, storage, and validation

---

## TON / FunC / Tact Checklist

### Message Handling
- [ ] **Bounce handling**: Messages that fail bounce back — handle bounced messages properly
- [ ] **Internal messages**: Validate source address for privileged operations
- [ ] **External messages**: Replay protection (seqno) for external messages
- [ ] **Message ordering**: TON doesn't guarantee message ordering — handle out-of-order
- [ ] **Gas forwarding**: Verify sufficient gas forwarded with messages

### TON-Specific
- [ ] **Storage fees**: State storage has ongoing fees — contracts can be frozen if balance depleted
- [ ] **Contract destruction**: Low balance → contract destroyed → state lost
- [ ] **Workchain isolation**: Messages between workchains have different routing
- [ ] **Sharding**: Account state split across shards — cross-shard consistency
- [ ] **Cell overflow**: Data packed into cells — verify cell depth and size limits (1023 bits/cell, max 4 refs)

### Tact-Specific
- [ ] **Trait implementation**: Verify trait functions properly override base behavior
- [ ] **String handling**: String operations in Tact have different gas costs than FunC
- [ ] **Map operations**: Map iteration not supported — design around this limitation
- [ ] **Optional types**: `null` handling for optional values

---

## Starknet / Cairo Checklist

### Cairo-Specific
- [ ] **Felt252 overflow**: felt252 arithmetic wraps at the prime — verify bounds
- [ ] **Storage proofs**: Storage proof verification for cross-contract reads
- [ ] **Contract class hash**: Validate class hash of deployed contracts
- [ ] **Reentrancy**: Cairo's execute-then-verify model — reentrancy possible during `call_contract`
- [ ] **Nonce management**: Transaction nonce for replay protection

### Starknet-Specific
- [ ] **Sequencer centralization**: Single sequencer can censor or reorder transactions
- [ ] **L1-L2 messaging**: Message hash verification for cross-layer communication
- [ ] **Storage layout**: Storage address computation differs from EVM
- [ ] **Block timestamps**: Sequencer controls timestamps — less reliable than L1
- [ ] **Gas estimation**: Cairo steps != EVM gas — different optimization strategies

---

## Fuel / Sway Checklist

*Source: WEB3-AUDIT-SKILLS fuel-scanner*

### Fuel-Specific
- [ ] **UTXO model**: Fuel uses UTXO model not account model — state assumptions differ
- [ ] **Predicate scripts**: Predicates are stateless — cannot store data between calls
- [ ] **Message passing**: L1↔L2 message relay — verify message sender and nonce
- [ ] **Storage slots**: Storage access is explicit via `storage` keyword — uninitialized slots return zero
- [ ] **Contract ID**: Validate contract identity before cross-contract calls
- [ ] **Asset system**: Native asset support (not just ETH) — multi-asset accounting critical
- [ ] **Script vs Contract**: Script context has different capabilities than contract context
- [ ] **Reentrancy**: Sway has no built-in reentrancy guard — must implement manually

## Cosmos / CosmWasm Checklist

### CosmWasm-Specific
- [ ] **Instantiate vs Execute**: Initialization logic separation and protection
- [ ] **Query handlers**: View functions must not modify state
- [ ] **SubMsg replies**: Reply handling for cross-contract call results
- [ ] **Bank module integration**: Coin send/receive validation
- [ ] **IBC transfers**: Channel and denomination validation for cross-chain assets

### Cosmos SDK
- [ ] **Module keeper access**: Keeper interface permissions and scope
- [ ] **Governance proposals**: Parameter change proposal validation
- [ ] **Staking interactions**: Delegation/undelegation timing and slashing
- [ ] **Auth module**: Account sequence numbers for replay protection
- [ ] **Crisis module**: Invariant checking and halt conditions

---

## Universal Checks (All Networks)

These apply regardless of blockchain:

### Logic Errors
- [ ] Off-by-one in loops and boundary conditions
- [ ] Incorrect operator (< vs <=, && vs ||)
- [ ] Missing edge case: zero amount, max value, empty collection
- [ ] State not reset after operation (stale flags, counters)
- [ ] Return value ignored or inverted

### Economic Logic
- [ ] Fees calculated correctly and bounded
- [ ] Interest/reward calculations use correct time base
- [ ] Exchange rate calculations handle edge cases
- [ ] Liquidation mechanics prevent bad debt accumulation
- [ ] Withdrawal limits and cooldowns function correctly

### Governance & Admin
- [ ] Admin functions protected by timelock
- [ ] Multi-sig required for critical operations
- [ ] Role grants/revocations properly logged
- [ ] Emergency pause doesn't lock user funds permanently
- [ ] Upgrade path doesn't brick the protocol
