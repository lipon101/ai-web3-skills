# VeerSkills Attack Vector Library

_280 attack vectors with Detection (D) and False-Positive (FP) markers. Sourced from real audit findings across Code4rena, Sherlock, Cyfrin, and 20+ platforms. V171-V210: Extended EVM from solidity-auditor-skills. V211-V255: Chain-specific vectors (see chain-deep-*.md for deep methodology). V256-V280: Permit2, V4 Hooks, AA, Composability (2024-2026 findings)._

## Table of Contents

- [How to Use](#how-to-use)
- [Agent 1: Reentrancy + Access Control + Proxy/Upgrade (V1–V42)](#agent-1-vectors-v1v42-reentrancy--access-control--proxyupgrade)
- [Agent 2: Arithmetic + Oracle + Token Standards (V43–V84)](#agent-2-vectors-v43v84-arithmetic--oracle--token-standards)
- [Agent 3: DoS + Economic + Flash Loan + Cross-Chain (V85–V126)](#agent-3-vectors-v85v126-dos--economic--flash-loan--cross-chain)
- [Agent 4: Signature + Encoding + Assembly + Protocol-Specific (V127–V170)](#agent-4-vectors-v127v170-signature--encoding--assembly--protocol-specific)
- [Agent 5: Extended EVM — DeFi, L2, Staking (V171–V210)](#agent-5-vectors-v171v210-extended-evm--defi-lending-l2-staking-behavioral)
- [Agent 6: Chain-Specific — Solana/Move/TON/Cosmos/Cairo (V211–V255)](#agent-6-vectors-v211v255-chain-specific--solana--move--ton--cosmos--cairo)
- [Agent 7: Extended — Permit2, Hooks, AA, Composability (V256–V280)](#agent-7-vectors-v256v280-extended--permit2-hooks-aa-composability)

## How to Use

Each agent is assigned a vector range. During the **HUNT** phase:
1. **Triage**: Classify each vector as Skip / Borderline / Survive
2. **Deep pass**: Only analyze surviving vectors using the structured one-liner format
3. **Confirm**: Apply the FP Gate from `fp-gate.md` before reporting

---

## Agent 1 Vectors (V1–V42): Reentrancy + Access Control + Proxy/Upgrade

---

**V1. Signature Malleability** — D: Raw `ecrecover` without `s <= 0x7FFF...20A0` validation. Both `(v,r,s)` and `(v',r,s')` recover same address. Bypasses signature-based dedup. FP: OZ `ECDSA.recover()` used. Message hash used as dedup key.

**V2. ERC721Consecutive Balance Corruption** — D: OZ `ERC721Consecutive` (<4.8.2) + `_mintConsecutive(to, 1)` — size-1 batch fails to increment balance. FP: OZ >= 4.8.2. Batch size always >= 2.

**V3. Same-Block Deposit-Withdraw Exploiting Snapshot Benefits** — D: Protocol calculates yield/rewards/voting power based on single snapshot point. No minimum lock period. Flash-loan deposit → snapshot → withdraw in one tx. FP: `getPastVotes(block.number - 1)`. Minimum holding period enforced.

**V4. Token Decimal Mismatch in Cross-Token Arithmetic** — D: Cross-token math uses hardcoded `1e18` or assumes identical decimals without per-token `decimals()` normalization. FP: Amounts normalized to canonical precision using `decimals()`.

**V5. Block Timestamp Dependence** — D: `block.timestamp` used for game outcomes, randomness, or auction timing where ~15s manipulation changes outcome. FP: Timestamp used only for hour/day-scale periods.

**V6. Beacon Proxy Single-Point-of-Failure Upgrade** — D: Multiple proxies read implementation from single Beacon. Compromising Beacon owner upgrades all proxies at once. FP: Beacon owner is multisig + timelock.

**V7. lzCompose Sender Impersonation** — D: `lzCompose` does not validate `msg.sender == endpoint` or `_from` parameter against expected OFT address. FP: Both endpoint and OFT address validated.

**V8. Invariant/Cap Enforced on One Path But Not Another** — D: A constraint (pool cap, max supply, position limit) is enforced during normal operation but not during settlement, reward distribution, or emergency paths. FP: Invariant check in shared modifier called by all paths.

**V9. msg.value Reuse in Loop/Multicall** — D: `msg.value` read inside a loop or `delegatecall`-based multicall. Each iteration sees full original value — credits `n * msg.value` for one payment. FP: `msg.value` captured to local variable, decremented per iteration.

**V10. Zero-Amount Transfer Revert** — D: `token.transfer(to, amount)` where `amount` can be zero. Some tokens (LEND, early BNB) revert on zero-amount transfers, DoS-ing distribution loops. FP: `if (amount > 0)` guard before all transfers.

**V11. ERC1155 safeBatchTransferFrom Unchecked Array Lengths** — D: Custom `_safeBatchTransferFrom` iterates without `require(ids.length == amounts.length)`. FP: OZ ERC1155 base used unmodified.

**V12. ERC721/ERC1155 Callback Reentrancy** — D: `safeTransferFrom`/`safeMint` called before state updates. Callbacks enable reentry. FP: All state committed before safe transfer. `nonReentrant` applied.

**V13. Depeg of Pegged Asset Breaking Protocol Assumptions** — D: Protocol assumes 1:1 peg (stETH:ETH, WBTC:BTC) without depeg tolerance or independent oracle. FP: Independent price feed per asset. Configurable depeg threshold.

**V14. Missing onERC1155BatchReceived Causes Token Lock** — D: Contract implements `onERC1155Received` but not `onERC1155BatchReceived`. FP: Both callbacks implemented. Inherits OZ `ERC1155Holder`.

**V15. Missing or Incorrect Access Modifier** — D: State-changing function has no access guard or modifier references uninitialized variable. FP: Function is intentionally permissionless with non-critical impact.

**V16. extcodesize Zero in Constructor** — D: `require(msg.sender.code.length == 0)` as EOA check. Contract constructors bypass it. FP: Protected by merkle proof or signed permit.

**V17. Solmate SafeTransferLib Missing Contract Existence Check** — D: Protocol uses Solmate's `SafeTransferLib`. Unlike OZ, Solmate does not verify target contains code. FP: OZ `SafeERC20` used. Manual code length check present.

**V18. Re-initialization Attack** — D: V2 uses `initializer` instead of `reinitializer(2)`. Or upgrade resets initialized counter. FP: `reinitializer(version)` with correctly incrementing versions.

**V19. ERC1155 uri() Missing {id} Substitution** — D: `uri(uint256 id)` returns fully resolved URL instead of template with `{id}` placeholder. FP: Returns string containing literal `{id}`.

**V20. Immutable Variable Context Mismatch** — D: Implementation uses `immutable` variables embedded in bytecode. Proxy `delegatecall` gets implementation's hardcoded values. FP: Immutable values intentionally identical across all proxies.

**V21. validateUserOp Signature Not Bound to nonce/chainId** — D: `validateUserOp` reconstructs digest manually omitting `userOp.nonce` or `block.chainid`. Enables replay. FP: Digest from `entryPoint.getUserOpHash(userOp)`.

**V22. Blacklistable/Pausable Token in Critical Payment Path** — D: Push-model transfer with USDC/USDT. Blacklisted recipient reverts entire function. FP: Pull-over-push pattern. Skip-on-failure `try/catch`.

**V23. Improper Flash Loan Callback Validation** — D: `onFlashLoan` callback doesn't verify `msg.sender == lendingPool` or check `initiator`/`token`/`amount`. FP: Both `msg.sender` and `initiator` validated.

**V24. Cross-Chain Deployment Replay** — D: Deployment tx replayed on another chain. Same deployer nonce produces same CREATE address. FP: EIP-155 signatures. `CREATE2` via deterministic factory.

**V25. DoS via Unbounded Loop** — D: Loop over user-growable unbounded array. Eventually hits block gas limit. FP: Array length capped at insertion.

**V26. Precision Loss — Division Before Multiplication** — D: `(a / b) * c` — truncation before multiplication amplifies error. FP: `a` provably divisible by `b`.

**V27. ecrecover Returns address(0) on Invalid Signature** — D: Raw `ecrecover` without `require(recovered != address(0))`. FP: OZ `ECDSA.recover()` used.

**V28. Function Selector Clash in Proxy** — D: Proxy and implementation share a 4-byte selector collision. FP: Transparent proxy pattern. UUPS with no custom proxy functions.

**V29. CREATE2 Address Squatting** — D: CREATE2 salt not bound to `msg.sender`. Attacker precomputes and deploys first. FP: Salt incorporates `msg.sender`.

**V30. Return Bomb (Returndata Copy DoS)** — D: `(bool success, bytes memory data) = target.call(payload)` with user-supplied target returns huge returndata. FP: Returndata not copied. Callee is hardcoded trusted.

**V31. Immutable/Constructor Argument Misconfiguration** — D: Constructor sets `immutable` values that can't change post-deploy. No post-deploy verification. FP: Deployment script reads back and asserts values.

**V32. Small-Type Arithmetic Overflow Before Upcast** — D: Arithmetic on `uint8`/`uint16` before assigning to wider type. Overflow in narrow type. FP: Operands explicitly upcast before operation.

**V33. ERC4626 Missing Allowance Check in withdraw/redeem** — D: `withdraw`/`redeem` where `msg.sender != owner` but no allowance check. FP: `_spendAllowance` called unconditionally when `caller != owner`.

**V34. mstore8 Partial Write Leaving Dirty Bytes** — D: `mstore8` writes single byte; subsequent `mload` reads full 32-byte word with stale bytes. FP: Full word zeroed before byte-level writes.

**V35. Batch Distribution Dust Residual** — D: Loop distributes proportionally with cumulative rounding leaving dust locked in contract. FP: Last recipient gets `total - sumOfPrevious`.

**V36. Arbitrary delegatecall in Implementation** — D: Implementation exposes `delegatecall` to user-supplied address. FP: Target is hardcoded immutable.

**V37. Commit-Reveal Scheme Not Bound to msg.sender** — D: Commitment hash does not include `msg.sender`. Attacker copies victim's commitment. FP: Commitment includes sender.

**V38. Delegate Privilege Escalation** — D: `setDelegate()` appoints address that can manage OApp configurations including DVNs, Executors. FP: Delegate == owner or governance timelock.

**V39. Cross-Chain Supply Accounting Invariant Violation** — D: `total_locked_source >= total_minted_destination` invariant violated via decimal errors or race conditions. FP: Invariant monitored. Rate limits cap exposure.

**V40. ERC1155 onERC1155Received Return Value Not Validated** — D: Custom ERC1155 calls `onERC1155Received` but doesn't check returned `bytes4`. FP: OZ ERC1155 base validates selector.

**V41. Small Positions Unliquidatable (Bad Debt)** — D: Positions below threshold cost more gas to liquidate than the reward. Accumulate bad debt. FP: Minimum position size enforced at borrow time.

**V42. Ordered Message Channel Blocking (Nonce DoS)** — D: Ordered nonce execution — if one message permanently reverts, ALL subsequent messages blocked. FP: Unordered nonce mode. `NonblockingLzApp` pattern.

---

## Agent 2 Vectors (V43–V84): Arithmetic + Oracle + Token Standards

---

**V43. Self-Liquidation Profit Extraction** — D: Borrower liquidates own position from second address, collecting liquidation bonus. FP: `require(msg.sender != borrower)`. Penalty exceeds bonus.

**V44. State-Time Lag Exploitation (lzRead Stale State)** — D: `lzRead` queries remote chain state with latency window. Protocol makes irreversible decisions on stale data. FP: Read targets immutable state. Result re-validated on-chain.

**V45. Integer Overflow/Underflow** — D: Arithmetic in `unchecked {}` (>=0.8) without bounds check. Any arithmetic in <0.8 without SafeMath. FP: Range provably bounded by earlier checks.

**V46. Function Selector Clashing (Proxy Backdoor)** — D: Proxy contains function whose 4-byte selector collides with implementation function. FP: Transparent proxy. UUPS with no custom functions.

**V47. OFT Shared Decimals Truncation** — D: OFT converts between local/shared decimals. `uint64` cast silently truncates amounts exceeding ~18.4e18. FP: Standard OFT with default decimals. Transfer amounts validated.

**V48. UUPS Upgrade Logic Removed in New Implementation** — D: New UUPS implementation doesn't inherit `UUPSUpgradeable`. Proxy permanently loses upgrade capability. FP: Every version inherits `UUPSUpgradeable`.

**V49. ERC721 onERC721Received Arbitrary Caller Spoofing** — D: `onERC721Received` uses parameters to update state without verifying `msg.sender` is expected NFT contract. FP: `require(msg.sender == address(nft))`.

**V50. ERC1155 totalSupply Inflation via Reentrancy** — D: `totalSupply[id]` incremented AFTER `_mint` callback. During callback, `totalSupply` is stale-low. FP: OZ >= 4.3.2. `nonReentrant` on all mint functions.

**V51. Missing Nonce (Signature Replay)** — D: Signed message has no per-user nonce, or nonce never incremented after use. FP: Monotonic per-signer nonce. `usedSignatures` mapping.

**V52. Single-Function Reentrancy** — D: External call before state update — check-external-effect instead of CEI. FP: State updated before call. `nonReentrant` modifier.

**V53. Diamond Proxy Cross-Facet Storage Collision** — D: EIP-2535 facets declare storage without EIP-7201 namespaced storage. Multiple facets write same slots. FP: All facets use single `DiamondStorage` struct at namespaced position.

**V54. Force-Feeding ETH via selfdestruct/Coinbase/CREATE2** — D: Contract uses `address(this).balance` for accounting or gates on exact balance. Force-fed ETH breaks invariants. FP: Internal accounting only (`totalDeposited` state variable).

**V55. Wrong Price Feed for Derivative/Wrapped Asset** — D: Protocol uses ETH/USD feed to price stETH collateral. During depeg, mispricing enables undercollateralized borrows. FP: Dedicated feed for the derivative asset.

**V56. ERC4626 Preview Rounding Direction Violation** — D: `previewDeposit` returns more shares than `deposit` mints. Wrong `Math.mulDiv` rounding direction. FP: OZ ERC4626 without overriding conversion functions.

**V57. Block Number as Timestamp Approximation** — D: Time computed as `(block.number - startBlock) * 13`. Variable across chains. FP: `block.timestamp` used for all time-sensitive calculations.

**V58. Transparent Proxy Admin Routing Confusion** — D: Admin address used for regular protocol interactions. Calls from admin silently fail. FP: Dedicated `ProxyAdmin` contract.

**V59. Cross-Chain Address Ownership Variance** — D: Same address has different owners on different chains. Cross-chain logic assumes same address = same owner. FP: `CREATE2`-deployed contracts with same factory + salt.

**V60. Read-Only Reentrancy** — D: Protocol calls `view` function on external contract within a callback. View functions return transitional/manipulated value mid-execution. FP: External view functions are `nonReentrant`. TWAP used instead.

**V61. Bytecode Verification Mismatch** — D: Verified source doesn't match deployed bytecode. Different compiler settings or obfuscated constructor args. FP: Deterministic build with pinned compiler. Sourcify full match.

**V62. Scratch Space Corruption Across Assembly Blocks** — D: Scratch space (`0x00`–`0x3f`) written in one assembly block expected to persist across intervening Solidity code that overwrites it. FP: All reads occur within same contiguous assembly block.

**V63. ERC1155 Custom Burn Without Caller Authorization** — D: Public `burn(address from, uint256 id, uint256 amount)` callable by anyone without verifying authorization. FP: `require(from == msg.sender || isApprovedForAll(from, msg.sender))`.

**V64. ERC721 Unsafe Transfer to Non-Receiver** — D: `_transfer()`/`_mint()` used instead of `_safeTransfer()`/`_safeMint()`. NFTs locked in non-receiver contracts. FP: All paths use `safeTransferFrom`/`_safeMint`.

**V65. ERC1155 Fungible/Non-Fungible Token ID Collision** — D: ERC1155 with no enforcement preventing additional copies of supply-1 IDs. FP: `require(totalSupply(id) + amount <= maxSupply(id))`.

**V66. ERC4626 Deposit/Withdraw Share-Count Asymmetry** — D: `_convertToShares` uses `Rounding.Floor` for both deposit and withdraw. FP: `deposit` uses `Floor`, `withdraw` uses `Ceil`.

**V67. ERC4626 Mint/Redeem Asset-Cost Asymmetry** — D: `redeem(s)` returns more assets than `mint(s)` costs — cycling yields profit. FP: `redeem` uses `Floor`, `mint` uses `Ceil`.

**V68. ERC1155 Batch Transfer Partial-State Callback Window** — D: Custom batch mint updates and calls callback per ID in loop instead of committing all first. FP: All updates committed before any callback (OZ pattern).

**V69. Chainlink Staleness/No Validity Checks** — D: `latestRoundData()` called without: `answer > 0`, `updatedAt > block.timestamp - MAX_STALENESS`, `answeredInRound >= roundId`, fallback. FP: All four checks present.

**V70. Unsafe Downcast/Integer Truncation** — D: `uint128(largeUint256)` without bounds check. Solidity >= 0.8 silently truncates on downcast. FP: `require(x <= type(uint128).max)`. OZ `SafeCast` used.

**V71. Missing enforcedOptions — Insufficient Gas for lzReceive** — D: OApp does not call `setEnforcedOptions()` to mandate minimum gas. User-supplied options specify insufficient gas. FP: `enforcedOptions` configured with tested gas limits.

**V72. Nonce Gap from Reverted Transactions** — D: Deployment script uses `CREATE` and pre-computes addresses from deployer nonce. Reverted tx advances nonce. FP: `CREATE2` used. Addresses from deployment receipts.

**V73. Fee-on-Transfer Token Accounting** — D: Deposit records `deposits[user] += amount` then `transferFrom(..., amount)`. Contract receives less than recorded. FP: Balance measured before/after transfer. `received` used for accounting.

**V74. Assembly Delegatecall Missing Return/Revert Propagation** — D: Proxy fallback omits copying return data or branching on result. Silent failures. FP: Complete proxy pattern with `returndatacopy` and `switch`. OZ Proxy.sol.

**V75. Merkle Tree Second Preimage Attack** — D: `MerkleProof.verify` where leaf derived without double-hashing. 64-byte input passes as intermediate node. FP: Leaves double-hashed. OZ MerkleProof >= v4.9.2.

**V76. Dirty Higher-Order Bits on Sub-256-Bit Types** — D: Assembly loads full 32-byte word but treats as smaller type without masking upper bits. FP: Explicit bitmask applied immediately after load.

**V77. Griefing via Dust Deposits Resetting Timelocks** — D: Timelock resets on any deposit with no minimum. Attacker calls `deposit(1)` to reset victim's lock. FP: Minimum deposit enforced. Lock assessed independently.

**V78. Returndatasize-as-Zero Assumption** — D: Assembly uses `returndatasize()` as gas-cheap substitute for `push 0`. Prior external call made it nonzero. FP: Used only at very start before any external calls.

**V79. tx.origin Authentication** — D: `require(tx.origin == owner)` used for auth. Phishable via intermediary contract. FP: `tx.origin == msg.sender` as anti-contract check only.

**V80. ERC20 Non-Compliant Return Values/Events** — D: Custom `transfer()`/`transferFrom()` doesn't return `bool` or always returns `true` on failure. FP: OZ `ERC20.sol` base with no custom overrides.

**V81. ERC721Enumerable Index Corruption on Burn/Transfer** — D: Override of `_beforeTokenTransfer` without calling `super`. Index structures become stale. FP: Override always calls `super` as first statement.

**V82. Block Stuffing/Gas Griefing** — D: Time-sensitive function blockable by filling blocks. FP: Window long enough that stuffing is economically infeasible.

**V83. ERC777 tokensToSend/tokensReceived Reentrancy** — D: Token transfer before state updates on ERC777-compatible token. Hooks fire on ERC20-style calls. FP: CEI. `nonReentrant`. Token whitelist excludes ERC777.

**V84. Rebasing/Elastic Supply Token Accounting** — D: Contract caches `balanceOf(this)` for rebasing tokens. After rebase, cached value diverges. FP: Rebasing tokens blocked. Wrapper tokens (wstETH) used.

---

## Agent 3 Vectors (V85–V126): DoS + Economic + Flash Loan + Cross-Chain

---

**V85. Assembly Arithmetic Silent Overflow and Division-by-Zero** — D: Arithmetic inside `assembly {}` wraps like `unchecked` and `div` by zero returns 0. FP: Manual overflow checks in assembly. Denominator checked before `div`.

**V86. Flash Loan-Assisted Price Manipulation** — D: Function reads price from on-chain source manipulable atomically via flash loan. FP: TWAP >= 30min. Multi-block cooldown.

**V87. Non-Standard Approve Behavior** — D: USDT-style `approve()` reverts when changing non-zero to non-zero. Some tokens revert on `approve(type(uint256).max)`. FP: OZ `SafeERC20.forceApprove()` or `safeIncreaseAllowance()` used.

**V88. Missing Chain ID Validation in Deployment** — D: Deploy script reads `$RPC_URL` without `eth_chainId` assertion. FP: `require(block.chainid == expectedChainId)` at script start.

**V89. Array delete Leaves Zero-Value Gap** — D: `delete array[index]` resets element to zero but doesn't shrink array. Iteration treats zero as valid. FP: Swap-and-pop pattern used.

**V90. Governance Flash-Loan Upgrade Hijack** — D: Proxy upgrades via current-block vote weight. No timelock. Flash-borrow, vote, execute upgrade in one tx. FP: `getPastVotes(block.number - 1)`. Timelock 24-72h.

**V91. Write to Arbitrary Storage Location** — D: `sstore(slot, value)` where `slot` derived from user input without bounds. FP: Assembly is read-only. Solidity >= 0.6.

**V92. Insufficient Return Data Length Validation** — D: Assembly `staticcall` writes to fixed buffer then reads without checking `returndatasize() >= 32`. FP: `if lt(returndatasize(), 32) { revert(0,0) }` checked.

**V93. Chainlink Feed Deprecation/Wrong Decimal Assumption** — D: Chainlink aggregator hardcoded/immutable with no update path. Assumes `feed.decimals() == 8`. FP: Feed address updatable. `feed.decimals()` called and used.

**V94. Upgrade Race Condition/Front-Running** — D: `upgradeTo(V2)` and config calls are separate txs in public mempool. FP: `upgradeToAndCall()` bundles upgrade + init. Private mempool.

**V95. Missing/Expired Deadline on Swaps** — D: `deadline = block.timestamp` (always valid) or `type(uint256).max`. FP: Deadline is calldata parameter not derived from `block.timestamp`.

**V96. Deployment Transaction Front-Running** — D: Deployment tx in public mempool. Attacker extracts bytecode and deploys first. FP: Private relay. Owner passed as constructor arg.

**V97. Duplicate Items in User-Supplied Array** — D: Function accepts array without duplicate check. User passes same ID multiple times claiming repeatedly. FP: Duplicate check via mapping. Sorted-unique enforced.

**V98. Transient Storage Low-Gas Reentrancy (EIP-1153)** — D: Contract uses `transfer()` (2300-gas) as reentrancy guard + `TSTORE`/`TLOAD`. Post-Cancun, `TSTORE` succeeds under 2300 gas. FP: `nonReentrant` backed by regular storage slot.

**V99. Calldataload Out-of-Bounds Read** — D: `calldataload(offset)` where offset exceeds actual calldata length. Returns zero-padded bytes silently. FP: `calldatasize()` validated before assembly block.

**V100. Banned Opcode in Validation Phase** — D: `validateUserOp` references `block.timestamp`, `block.number`, `block.coinbase`. Per ERC-7562, banned in validation. FP: Banned opcodes only in execution phase.

**V101. Deployer Privilege Retention Post-Deployment** — D: Deployer EOA retains owner/admin/minter after deployment. FP: Script includes `transferOwnership(multisig)`.

**V102. Non-Atomic Multi-Contract Deployment** — D: Interdependent contracts deployed across separate transactions. Midway failure leaves half-deployed state. FP: Single broadcast block. Factory deploys+wires all in one tx.

**V103. CREATE/CREATE2 Deployment Failure Silently Returns Zero** — D: Assembly `create`/`create2` returns `address(0)` on failure but code doesn't check. FP: `if iszero(addr) { revert(0, 0) }` after create.

**V104. ERC721/ERC1155 Type Confusion in Dual-Standard Marketplace** — D: Shared `buy` function accepts `quantity` for ERC721 without requiring == 1. `price * quantity` with `quantity = 0` yields zero payment. FP: ERC721 branch `require(quantity == 1)`.

**V105. Cross-Contract Reentrancy** — D: Two contracts share logical state. A makes external call before syncing state B reads. A's `ReentrancyGuard` doesn't protect B. FP: State synchronized before A's call.

**V106. Non-Atomic Proxy Initialization** — D: Proxy deployed in one tx, `initialize()` in separate tx. Front-runnable. FP: Proxy constructor receives init calldata atomically.

**V107. EIP-2981 Royalty Signaled But Never Enforced** — D: `royaltyInfo()` implemented but transfer logic never calls it. FP: Settlement contract reads `royaltyInfo()` and transfers royalty.

**V108. Paymaster Gas Penalty Undercalculation** — D: Paymaster prefund formula omits 10% penalty on unused execution gas. FP: Prefund explicitly adds unused-gas penalty.

**V109. ERC721 Approval Not Cleared in Custom Transfer** — D: Custom `transferFrom` override skips `super._transfer()`, missing approval clear. FP: Override calls `super.transferFrom`.

**V110. DoS via Push Payment to Rejecting Contract** — D: ETH distribution in loop via `recipient.call{value:}("")`. Any reverting recipient blocks loop. FP: Pull-over-push pattern. Loop uses `try/catch`.

**V111. Weak On-Chain Randomness** — D: Randomness from `block.prevrandao`, `blockhash`, `block.timestamp`. Validator-influenceable. FP: Chainlink VRF v2+.

**V112. Delegatecall to Untrusted Callee** — D: `address(target).delegatecall(data)` where `target` is user-provided. FP: `target` is hardcoded immutable.

**V113. UUPS _authorizeUpgrade Missing Access Control** — D: `function _authorizeUpgrade(address) internal override {}` with empty body. Anyone can upgrade. FP: Has `onlyOwner`.

**V114. Insufficient Block Confirmations/Reorg Double-Spend** — D: DVN relays message before source chain finality. Attacker reverses deposit via reorg. FP: Confirmation count matches finality guarantees.

**V115. Nested Mapping Inside Struct Not Cleared on delete** — D: `delete myMapping[key]` on struct containing `mapping`. `delete` zeroes primitives but not nested mappings. FP: Nested mapping manually cleared.

**V116. ERC721A Lazy Ownership — ownerOf Uninitialized** — D: Batch mint only writes ownership for first token. Mid-batch IDs return `address(0)`. FP: Explicit transfer initializes before ownership check.

**V117. Cross-Chain Message Spoofing** — D: Receiver accepts messages without verifying `msg.sender == endpoint` and `_origin.sender == registeredPeer`. FP: `onlyPeer` modifier validates both.

**V118. Proxy Admin Key Compromise** — D: `ProxyAdmin.owner()` returns EOA, not multisig. No timelock on `upgradeTo`. FP: Multisig + timelock.

**V119. Unauthorized Peer Initialization (Fake Peer Attack)** — D: `setPeer()` lacks proper access control. Attacker registers fraudulent peer. FP: `setPeer` protected by multisig + timelock.

**V120. Rounding in Favor of the User** — D: `shares = assets / pricePerShare` rounds down for deposit but up for redeem. FP: `Math.mulDiv` with explicit vault-favorable rounding. Dead shares at init.

**V121. Arbitrary External Call with User-Supplied Target** — D: `target.call{value: v}(data)` where `target` or `data` are caller-supplied. Attacker crafts calldata to steal assets. FP: Target restricted to whitelisted address.

**V122. Paymaster ERC-20 Payment Deferred to postOp** — D: `validatePaymasterUserOp` doesn't transfer tokens — deferred to `postOp`. User revokes allowance between steps. FP: Tokens transferred during validation.

**V123. Minimal Proxy (EIP-1167) Implementation Destruction** — D: EIP-1167 clones `delegatecall` a fixed implementation. If implementation destroyed, all clones locked. FP: No `selfdestruct`. Post-Dencun: code not destroyed.

**V124. Spot Price Oracle from AMM** — D: Price from AMM reserves: `reserve0 / reserve1`. Flash-loan exploitable. FP: TWAP >= 30 min. Chainlink/Pyth as primary source.

**V125. Missing Slippage Protection (Sandwich Attack)** — D: Swap with `minAmountOut = 0`, or computed on-chain from manipulable source. FP: `minAmountOut` set off-chain by user.

**V126. NFT Staking Records msg.sender Instead of ownerOf** — D: `depositor[tokenId] = msg.sender` without checking `nft.ownerOf(tokenId)`. Operator credited instead of owner. FP: `nft.ownerOf(tokenId)` read and recorded.

---

## Agent 4 Vectors (V127–V170): Signature + Encoding + Assembly + Protocol-Specific

---

**V127. Missing chainId (Cross-Chain Replay)** — D: Signed payload omits `chainId`. Replayable on forks/other chains. FP: EIP-712 domain separator includes dynamic `block.chainid`.

**V128. Non-Standard ERC20 Return Values (USDT-style)** — D: `require(token.transfer(to, amount))` reverts on tokens returning nothing. FP: OZ `SafeERC20.safeTransfer()` used.

**V129. Front-Running Zero Balance Check with Dust** — D: `require(token.balanceOf(address(this)) == 0)` gates state. Dust transfer DoS. FP: Threshold check instead of `== 0`.

**V130. Diamond Proxy Facet Selector Collision** — D: Two facets register same 4-byte selector. Malicious facet hijacks calls. FP: `diamondCut` validates no collisions.

**V131. Flash Loan Governance Attack** — D: Voting uses `token.balanceOf(msg.sender)` or current-block snapshot. FP: `getPastVotes(block.number - 1)`. Timelock between snapshot and vote.

**V132. Hardcoded Network-Specific Addresses** — D: Literal `address(0x...)` constants for external dependencies. Wrong on different chains. FP: Per-chain config keyed by chain ID.

**V133. ERC4626 Round-Trip Profit Extraction** — D: `redeem(deposit(a)) > a` from rounding errors favoring user. FP: Rounding per EIP-4626 spec. OZ ERC4626 with `_decimalsOffset()`.

**V134. ERC1155 ID-Based Role Access Control with Mintable Role Tokens** — D: Access control via `balanceOf(msg.sender, ROLE_ID)` where `mint` for role IDs ungated. FP: Minting role-token IDs gated. Role tokens non-transferable.

**V135. Off-By-One in Bounds/Range Checks** — D: `i <= arr.length` in loop (OOB). `>= vs >` confusion in financial logic. FP: Loop uses `<` with fixed-length array.

**V136. ERC4626 Caller-Dependent Conversion Functions** — D: `convertToShares()` branches on `msg.sender`-specific state. EIP-4626 requires caller-independence. FP: Implementation reads only global vault state.

**V137. Multi-Block TWAP Oracle Manipulation** — D: TWAP window < 30 minutes. Post-Merge validators can hold manipulated state across blocks. FP: TWAP >= 30 min. Chainlink as price source.

**V138. Merkle Proof Reuse — Leaf Not Bound to Caller** — D: Merkle leaf doesn't include `msg.sender`. Proof front-runnable. FP: Leaf encodes `msg.sender`. Proof recorded as consumed.

**V139. Uninitialized Implementation Takeover** — D: Implementation behind proxy has `initialize()` but constructor lacks `_disableInitializers()`. FP: Constructor contains `_disableInitializers()`.

**V140. Missing chainId/Message Uniqueness in Bridge** — D: Bridge processes messages without replay check or chain ID validation. FP: Unique nonce per sender. Hash includes source/dest chain.

**V141. Missing Oracle Price Bounds** — D: Oracle returns extreme price (flash crash). No min/max sanity bound. FP: Circuit breaker with MIN/MAX. Deviation check against secondary oracle.

**V142. DVN Collusion/Insufficient Diversity** — D: OApp with single DVN (`1/1/1` security stack). FP: Diverse DVN set with `2/3+` threshold. Independent verification methods.

**V143. Missing Cross-Chain Rate Limits/Circuit Breakers** — D: Bridge has no per-transaction or time-window caps. Single exploit drains everything. FP: Per-tx and per-window rate limits. `whenNotPaused`. Guardian multisig.

**V144. Staking Reward Front-Run by New Depositor** — D: Reward checkpoint updated AFTER new stake recorded. New staker earns rewards for unstaked period. FP: `updateReward(account)` executes before any balance update.

**V145. L2 Sequencer Uptime Not Checked** — D: L2 contract uses Chainlink feeds without querying Sequencer Uptime Feed. Stale data during downtime. FP: Sequencer uptime feed queried with grace period.

**V146. Insufficient Gas Forwarding / 63/64 Rule** — D: External call without minimum gas budget. 63/64 rule leaves subcall with insufficient gas. FP: `require(gasleft() >= minGas)` before subcall.

**V147. Accrued Interest Omitted from Health Factor** — D: Health factor computed from principal debt without accrued interest. Delays liquidations. FP: `getDebt()` includes accrued interest.

**V148. ERC1155 setApprovalForAll Grants All-Token Access** — D: Protocol requires `setApprovalForAll` for deposits. No per-ID granularity. FP: Protocol uses direct `safeTransferFrom` with user as `msg.sender`.

**V149. Storage Layout Collision Between Proxy and Implementation** — D: Proxy declares state variables at sequential slots. Implementation also starts at slot 0. FP: EIP-1967 slots. OZ Transparent/UUPS pattern.

**V150. validateUserOp Missing EntryPoint Caller Restriction** — D: `validateUserOp` is `public`/`external` without `require(msg.sender == entryPoint)`. FP: `onlyEntryPoint` modifier present.

**V151. Diamond Shared-Storage Cross-Facet Corruption** — D: EIP-2535 facets declare top-level state variables. Multiple facets corrupt slot 0. FP: All facets use namespaced storage (EIP-7201).

**V152. Stale Cached ERC20 Balance from Direct Transfers** — D: Contract tracks holdings in state variable updated only through protocol functions. Direct `token.transfer` inflates real balance. FP: Accounting reads `balanceOf(this)` live. Cached value reconciled.

**V153. Cross-Function Reentrancy** — D: Two functions share state. Function A makes external call before updating; Function B reads that state. FP: Both share same contract-level mutex.

**V154. Slippage Enforced at Intermediate Step, Not Final Output** — D: Multi-hop swap checks `minAmountOut` on first hop but not final output. FP: `minAmountOut` validated against final received balance.

**V155. Non-Atomic Proxy Deployment Enabling CPIMP Takeover** — D: Non-atomic deploy+init. Attacker inserts malicious middleman implementation. FP: Atomic init calldata in constructor. `_disableInitializers()`.

**V156. Cross-Chain Reentrancy via Safe Transfer Callbacks** — D: Cross-chain receive calls `_safeMint` before updating supply counters. Callback re-enters for duplicate tokens. FP: State updates before safe transfer. `nonReentrant`. `_mint` instead of `_safeMint`.

**V157. abi.encodePacked Hash Collision with Dynamic Types** — D: `keccak256(abi.encodePacked(a, b))` with two+ dynamic types. No length prefix → collision. FP: `abi.encode()` used. Only one dynamic type.

**V158. Signed Integer Mishandling (signextend/sar/slt)** — D: Assembly uses unsigned opcodes for signed integers. `shr` instead of `sar`. `lt` instead of `slt`. FP: Consistently uses `sar`/`slt`/`sgt`. `signextend` applied.

**V159. Missing _debit Authorization in OFT** — D: Custom OFT `_debit` omits authorization check. Anyone can bridge tokens from any holder. FP: Standard LayerZero OFT. `_debit` only callable via `send()`.

**V160. Default Message Library Hijack** — D: OApp relies on endpoint's mutable default library without pinning. Compromised default silently applies to all unpinned OApps. FP: OApp explicitly sets library versions.

**V161. ERC-1271 isValidSignature Delegated to Untrusted Module** — D: `isValidSignature` delegated to externally-supplied contract without whitelist. Always returns valid. FP: Delegation only to owner-controlled whitelist.

**V162. Proxy Storage Slot Collision** — D: Proxy stores `implementation`/`admin` at sequential slots 0,1. Implementation also writes from slot 0. FP: EIP-1967 randomized slots.

**V163. Counterfactual Wallet Initialization Parameters Not Bound** — D: Factory `createAccount` salt doesn't incorporate all init params. Attacker deploys wallet they control to user's address. FP: Salt derived from all init params.

**V164. Oracle Price Update Front-Running** — D: On-chain oracle update tx visible in mempool. Attacker front-runs favorable update. FP: Pull-based oracle. Private mempool.

**V165. Metamorphic Contract via CREATE2 + SELFDESTRUCT** — D: `CREATE2` where deployer can `selfdestruct` and redeploy different bytecode. Post-Dencun: largely mitigated. FP: Post-Dencun. Not deployed via `CREATE2` from mutable deployer.

**V166. Free Memory Pointer Corruption** — D: Assembly writes to memory at fixed offsets without updating free memory pointer at `0x40`. Subsequent Solidity code overwrites assembly data. FP: Assembly reads `mload(0x40)`, writes above, updates pointer.

**V167. ERC4626 Inflation Attack (First Depositor)** — D: `shares = assets * totalSupply / totalAssets`. When `totalSupply == 0`, deposit 1 wei + donate inflates share price. FP: OZ ERC4626 with `_decimalsOffset()`. Dead shares.

**V168. Storage Layout Shift on Upgrade** — D: V2 inserts new state variable in middle. Subsequent variables shift slots. FP: New variables only appended. OZ storage layout validation.

**V169. Hardcoded Calldataload Offset Bypass** — D: Assembly reads field at hardcoded offset assuming standard ABI layout. Non-canonical encoding bypasses. FP: `abi.decode()` used. No hardcoded offsets.

**V170. Calldata Input Malleability** — D: Contract hashes raw calldata for uniqueness. Dynamic-type ABI encoding ambiguity bypasses dedup. FP: Uniqueness check hashes decoded parameters. Nonce-based replay protection.

---

## Agent 5 Vectors (V171–V210): Extended EVM — DeFi Lending, L2, Staking, Behavioral

_Sourced from solidity-auditor-skills. These vectors cover deep DeFi protocol patterns, L2-specific issues, and behavioral vulnerabilities not covered by V1-V170._

---

**V171. L2 Sequencer Grace Period Missing** — D: On L2 chains, when sequencer restarts after downtime, contracts immediately liquidate positions without grace period. Users solvent before downtime get unfairly liquidated. FP: Explicit grace period after sequencer restart. L1-only deployment. Chainlink L2 Sequencer Uptime Feed with grace window.

**V172. Liquidation Incentive Insufficient for Dust Positions** — D: Liquidation reward (bonus %) doesn't cover gas for small positions. No one profitably liquidates, leading to bad debt accumulation. FP: Minimum position size enforced at borrow. Protocol-operated liquidation bot. Dynamic incentive scaled to position.

**V173. Collateral Withdrawal While Position Underwater** — D: User withdraws partial collateral even when position is underwater, as long as specific collateral's PNL is positive. Removes liquidation incentive. FP: Withdrawal blocked when overall health factor < 1.

**V174. Dust Loan Griefing (Minimum Loan Size Bypass)** — D: Attacker creates many tiny loans individually too small to profitably liquidate. Gas cost > recovered value, accumulating bad debt. FP: `require(borrowAmount >= MIN_BORROW)`. Batch liquidation mechanism.

**V175. Unfair Liquidation via Cherry-Picked Collateral** — D: Liquidator selects most liquid/stable collateral, leaving volatile collateral. Position becomes unhealthier post-liquidation. FP: Collateral seizure follows defined priority. `healthFactorAfter > healthFactorBefore` enforced.

**V176. Interest Accrual During Emergency Pause** — D: Admin pauses repayments but interest continues accruing. Debt grows, forcing liquidation of positions healthy before pause. FP: Pause halts interest accrual. Symmetric pause. Grace period after unpause.

**V177. Repayment Paused While Liquidation Active** — D: Admin pauses repayments but liquidations remain active. Asymmetric freeze benefits protocol at user expense. FP: Synchronized pause (repay + liquidate together).

**V178. Liquidation Leaves Borrower Unhealthier** — D: After partial liquidation, health factor is lower than before due to incorrect close factor or bonus exceeding surplus. FP: `require(healthAfter >= healthBefore || healthAfter >= 1)`. Full liquidation when partial worsens.

**V179. No LTV Gap Between Borrow and Liquidation Threshold** — D: Liquidation threshold equals max borrow LTV. Positions immediately liquidatable with zero buffer. FP: Explicit gap (e.g., borrow 75%, liquidate 80%). Per-asset configurable thresholds.

**V180. First Depositor Reward Stealing (Staking)** — D: First depositor front-runs initial reward distribution with 1-wei deposit, capturing 100% of initial rewards. FP: Minimum stake amount. Admin initial deposit. Time-weighted reward calculation.

**V181. Reward Dilution via Direct Token Transfer** — D: Attacker transfers staking tokens directly (bypassing `stake()`), inflating `totalSupply` in balance-based calculations. Dilutes legitimate stakers. FP: Separate `totalStaked` variable via `stake()`/`unstake()` only.

**V182. Flash Deposit/Withdraw Reward Griefing** — D: Large deposit right before reward distribution dilutes per-token rate. Withdraw immediately after. FP: Minimum stake duration. Time-weighted rewards. `require(block.number > depositBlock)`.

**V183. Stale Reward Index After Distribution** — D: Reward distribution updates pool but not `rewardPerTokenStored`. Stale index causes incorrect rewards for all users. FP: `updateReward()` in all reward-distributing functions.

**V184. Balance Caching Issues During Reward Claims** — D: Claiming reads balance, performs transfer, uses cached balance for further calculations. Reentrancy risk. FP: `nonReentrant`. CEI pattern. Balance read after transfer.

**V185. Liquidation Bonus Exceeds Available Collateral** — D: Fixed bonus exceeds actual collateral when deeply underwater. Liquidation reverts, leaving bad debt stuck. FP: Dynamic bonus capped at available: `min(bonus, availableCollateral)`.

**V186. Incorrect Decimal Handling in Multi-Token Liquidations** — D: Liquidation assumes 18 decimals but collateral/debt differ (USDC=6, WETH=18). Order-of-magnitude errors. FP: Per-token `decimals()` normalization.

**V187. Interest Accrual During Liquidation Auction** — D: During auction, debt keeps accruing interest. Long auctions make proceeds insufficient. FP: Interest frozen at auction start. Auction bounded.

**V188. No Liquidation Slippage Protection** — D: Liquidator calls `liquidate()` without `minCollateralReceived`. MEV sandwiches the tx. FP: `minCollateralReceived` parameter. Private mempool.

**V189. L2 Sequencer Downtime in Interest Accrual** — D: Interest uses `block.timestamp` delta without accounting for sequencer downtime. Post-restart block has massive gap. FP: Capped `maxTimeDelta`. Sequencer uptime checked.

**V190. Precision Loss in Reward-to-Token Conversion** — D: `rewardRate * timeElapsed / totalStaked` where small stakes produce zero. FP: Scaling factor (1e18). Minimum stake above precision threshold.

**V191. Time Unit Confusion in Interest Calculations** — D: `block.timestamp` (seconds) in formula expecting days/blocks. Interest rates off by orders of magnitude. FP: Documented `SECONDS_PER_YEAR` constant. Unit tests.

**V192. Oracle Manipulation via Self-Liquidation** — D: Manipulate oracle via flash loan, self-liquidate at manipulated price. Profitable when manipulation cost < bonus. FP: TWAP > manipulation cost. Self-liquidation blocked.

**V193. On-Chain Quoter-Based Slippage Calculation** — D: `minAmountOut` calculated from current spot price. Flash loan manipulates spot before tx. FP: `minAmountOut` supplied as calldata from off-chain.

**V194. Fixed Fee Tier Assumption in Multi-Pool DEX** — D: Router hardcodes fee tier but liquidity migrates. Swaps against low-liquidity pool. FP: Fee tier as parameter. Router queries multiple tiers.

**V195. Multi-Hop Swap Intermediate-Only Protection** — D: Multi-hop protects intermediate amount but not final output. MEV on final hop. FP: `minFinalAmountOut` validated against balance delta.

**V196. block.timestamp as Swap Deadline** — D: `deadline = block.timestamp` always satisfied. Tx held indefinitely. FP: Deadline from calldata (e.g., `now + 300s`). Private mempool.

**V197. Zero minAmountOut on DEX Swap** — D: Hardcoded zero minimum output. Unprotected from MEV/sandwich. FP: `minAmountOut` from oracle or caller parameter.

**V198. Transient Storage Reentrancy Guard in Delegatecall Context** — D: `TSTORE`/`TLOAD` guard in delegatecall proxy. Transient storage is per-address — shared across facets. One facet's guard doesn't protect reentry into another. FP: Shared transient slot across all facets. Regular storage guard.

**V199. Uniswap V4 Hook Callback Authorization** — D: Hook callbacks don't validate `msg.sender == poolManager`. Anyone calls hooks directly. FP: `onlyPoolManager` modifier. `BaseHook` from V4 periphery.

**V200. Uniswap V4 Cached State Desynchronization** — D: Hook caches pool state in `beforeSwap` but state changes during swap. `afterSwap` reads stale values. FP: State re-read in `afterSwap`. No cross-hook state dependency.

**V201. Custom Access Control Without Two-Step Transfer** — D: Single-step `setOwner(newOwner)`. Typo permanently locks admin. FP: OZ `Ownable2Step`. Multisig. Timelock with cancel.

**V202. Inconsistent Pausable Coverage** — D: `whenNotPaused` applied inconsistently. Some fund-moving ops lack protection. FP: All state-changing functions paused. Intentional exceptions documented.

**V203. OpenZeppelin v4 vs v5 Hook Confusion** — D: Override `_beforeTokenTransfer` (v4) while importing v5 (uses `_update`). Override silently never executes. FP: OZ version consistency confirmed.

**V204. Approval to Arbitrary User-Supplied Address** — D: Router approves `MAX_UINT` to user-supplied `pool` address without allowlist. Attacker drains via `transferFrom`. FP: Pool validated against factory. Approval limited to exact amount.

**V205. External Call Failure DoS in Batch Operations** — D: Batch reverts entirely if one call fails. Blacklisted address blocks all users. FP: Per-item `try/catch`. Pull-over-push. Failed items queued.

**V206. Storage Bloat Attack (Unbounded Growth)** — D: Attacker fills user-controlled arrays without economic limits. Functions iterating hit gas limit. FP: Array bounded. Economic deterrent. Pagination.

**V207. Timestamp Griefing (Lock Period Reset by Third Party)** — D: Anyone can `deposit(victim, 1 wei)` resetting victim's lock timer. FP: Lock only updatable by locked user. `max(existing, new)` pattern.

**V208. Self-Destruct Force-Feed Breaking Strict Equality** — D: `require(balance == expected)` broken by force-fed ETH. FP: Internal accounting. `>=` comparisons.

**V209. Inconsistent Guard Coverage Across Equivalent Functions** — D: `transfer` has guard but `transferFrom` doesn't. Attacker uses unguarded variant. FP: Shared internal function with guards. Modifier applied uniformly.

**V210. Missing Initialization of Inherited State in Upgradeable** — D: `__Ownable_init()` called but `__ReentrancyGuard_init()` forgotten. Guard state is 0 (uninitialized). FP: All `__*_init()` called. Tests verify post-deployment state.

---

## Agent 6 Vectors (V211–V255): Chain-Specific — Solana / Move / TON / Cosmos / Cairo

_These vectors are loaded from the corresponding `chain-deep-*.md` files. Only vectors matching the detected chain are actively scanned. See each chain-deep file for detection patterns, grep commands, and PoC templates._

---

### Solana Vectors (V211–V225)
_Full details in `chain-deep-solana.md`_

**V211. Missing Account Owner Check** — D: Account deserialized without owner validation. Attacker passes fake account. FP: Anchor `Account<'info, T>` auto-checks.

**V212. PDA Bump Seed Canonicalization** — D: Non-canonical bump allows multiple valid PDAs. FP: Canonical bump stored and enforced.

**V213. Missing Signer Check on Privileged Instruction** — D: Authority not marked as signer. FP: Anchor `Signer<'info>`.

**V214. Account Resurrection After Close** — D: Closed account re-funded with crafted data. FP: Anchor `close` sets CLOSED discriminator.

**V215. CPI Privilege Escalation via Signer Seeds** — D: Reconstructable signer seeds. FP: Program-specific salt in seeds.

**V216. Account Data Realloc Overflow** — D: Realloc exceeds 10,240 bytes/instruction. FP: Size validated. Freed bytes zeroed.

**V217. Token-2022 Transfer Hook Reentrancy** — D: Transfer hook reenters calling program. FP: State before transfer. Hook whitelisted.

**V218. Duplicate Account Injection** — D: Same account in multiple positions = double-credit. FP: `source.key() != destination.key()`.

**V219. Missing Rent Exemption Check** — D: Non-exempt account gets garbage collected. FP: Rent exemption enforced.

**V220. Arithmetic Overflow in Release Mode** — D: Rust wraps in release. FP: `checked_*` arithmetic.

**V221. Account Data Type Confusion** — D: Deserialized as wrong type. FP: 8-byte discriminator validated.

**V222. Stale Account Data After CPI** — D: Pre-CPI data used after CPI modifies account. FP: `reload()` after CPI.

**V223. Missing Instruction Introspection** — D: No validation of instruction sequence. FP: `sysvar::instructions` checked.

**V224. Permanent Delegate Token Extension** — D: Permanent delegate allows unauthorized transfers. FP: Extension list checked on deposit.

**V225. Solana Clock Manipulation** — D: Validator clock skew affects time-sensitive logic. FP: Day-scale time. Slot number for ordering.

---

### Move Vectors (V226–V235)
_Full details in `chain-deep-move.md`_

**V226. Shared Object Front-Running (Sui)** — D: Shared object access front-runnable by validator. FP: Owned objects for time-sensitive ops.

**V227. Hot Potato Object Misuse** — D: No valid consumption path. FP: Tested consumption paths.

**V228. Dynamic Field Type Confusion** — D: Borrow as wrong type. FP: Type marker in keys.

**V229. Object Ownership Bypass via Transfer** — D: `public_transfer` bypasses restrictions. FP: Custom `TransferPolicy`.

**V230. Package Upgrade Capability Leak** — D: `UpgradeCap` in shared/untrusted object. FP: Admin-owned, multi-sig controlled.

**V231. Missing Ability Constraints** — D: Generic `T` with `copy` allows asset duplication. FP: Minimal abilities enforced.

**V232. Aptos Resource Account Signer Cap Exposure** — D: `SignerCapability` publicly accessible. FP: Module-private struct.

**V233. Move Math Precision** — D: Integer division truncation in fixed-point. FP: Established library, explicit rounding.

**V234. Coin Registration Race (Aptos)** — D: Send to unregistered address fails. FP: `is_account_registered` checked.

**V235. Event Replay / Missing Authentication** — D: Events replayable off-chain. FP: Nonce/txHash in event data.

---

### TON Vectors (V236–V242)
_Full details in `chain-deep-ton.md`_

**V236. Unbounced Message Fund Loss** — D: Message to non-existing contract without bounce. FP: `bounce: true` + bounce handler.

**V237. Storage Fee Depletion Attack** — D: Inflated storage drains balance → contract frozen. FP: Bounded growth. Admin top-up.

**V238. Message Ordering Assumption Violation** — D: Out-of-order delivery breaks multi-step. FP: Sequence numbers. Order-independent state machine.

**V239. Cell Depth/Size Overflow** — D: Exceeds 1023 bits/4 refs per cell. FP: Bounds checked. Pagination.

**V240. External Message Replay** — D: No seqno replay protection. FP: Monotonic seqno incremented on success.

**V241. Gas Forwarding Exhaustion** — D: Insufficient TON_VALUE in message. FP: Minimum forward gas enforced.

**V242. Tact Map Iteration Limitation** — D: Map enumeration impossible at runtime. FP: Explicit key tracking array.

---

### Cosmos Vectors (V243–V248)
_Full details in `chain-deep-cosmos.md`_

**V243. Unvalidated IBC Channel/Denomination** — D: Accepts tokens from rogue chain. FP: Channel allowlist. Denom path validated.

**V244. SubMsg Reply Handler State Desync** — D: Reply assumes pre-execute state. FP: Fresh state read in reply.

**V245. CosmWasm Reentrancy via SubMsg** — D: SubMsg to untrusted contract reenters. FP: State before SubMsg. Trusted targets only.

**V246. Cosmos SDK Keeper Privilege Escalation** — D: Keeper methods callable by unauthorized modules. FP: Caller module validated.

**V247. Governance Proposal Parameter Injection** — D: Dangerous params without validation. FP: `Params.Validate()` with bounds.

**V248. Delegation Reward Siphoning** — D: Stake just before distribution, claim, unstake. FP: Epoch-start snapshot.

---

### Cairo/Starknet Vectors (V249–V255)
_Full details in `chain-deep-cairo.md`_

**V249. felt252 Arithmetic Overflow at Prime** — D: Wrap at Stark prime ~2^251. FP: Bounded types (`u128`, `u256`).

**V250. Starknet Reentrancy via call_contract** — D: External call before state update. FP: CEI pattern. Custom reentrancy flag.

**V251. Sequencer Censorship/Ordering Manipulation** — D: Single sequencer controls ordering. FP: L1 escape hatch. Timelock windows.

**V252. L1↔L2 Message Hash Collision** — D: Felt packing without length prefixing. FP: Poseidon hash. Nonce enforced.

**V253. Storage Address Computation Mismatch** — D: EVM-style slot assumptions wrong in Cairo. FP: Compiler storage macros.

**V254. Cairo Steps Gas Limit Exhaustion** — D: Exceeds step limit. FP: Bounded complexity. Worst-case gas tested.

**V255. Missing Contract Class Hash Validation** — D: Factory deploys without validating class hash. FP: Hardcoded hash with governance update.

---

## Agent 7 Vectors (V256–V280): Extended — Permit2, Hooks, AA, Composability

_These vectors cover emerging attack surfaces from Permit2, Uniswap V4 hooks, ERC-4337 Account Abstraction, transient storage, and advanced DeFi composability patterns. Sourced from 2024-2026 contest findings._

---

**V256. ERC4626 maxDeposit Returns Wrong Value When Paused** — D: `maxDeposit()` returns `type(uint256).max` when vault is paused. Caller deposits and funds lock. FP: `maxDeposit` returns 0 when paused. `deposit` also checks paused.

**V257. ERC4626 maxWithdraw Ignores Queued Withdrawals** — D: `maxWithdraw()` returns total balance ignoring pending withdrawal queue. Over-commitment. FP: `maxWithdraw` accounts for queued amounts.

**V258. Permit2 Allowance Inheritance** — D: User approves Permit2 for Protocol A. Protocol B (also using Permit2) can spend user tokens via inherited allowance without user consent. FP: Protocol uses `permit2.lockdown()` on unused protocols. Per-protocol allowance isolation.

**V259. Permit2 Batch Transfer Manipulation** — D: `permit2.permitTransferFrom` batch operation where attacker manipulates order of transfers to extract value. FP: Batch amounts validated against expected totals.

**V260. EIP-2612 Permit Front-Running** — D: Permit signature visible in mempool. Attacker front-runs `permit()` call — victim's subsequent `permit()` reverts (nonce consumed). `transferFrom` still works but gas wasted. FP: `try/catch` around `permit()` call. Protocol gracefully handles permit failure.

**V261. EIP-2612 Permit Deadline Set to Max** — D: `permit(owner, spender, value, type(uint256).max, v, r, s)` — permanent authorization. Leaked signature = permanent drain. FP: Deadline enforced to reasonable period. Signature scoped per-transaction.

**V262. Uniswap V4 Hook beforeSwap State Manipulation** — D: Hook's `beforeSwap` modifies pool state (liquidity, tick). `afterSwap` reads from pool assuming normal swap occurred. Stale or manipulated values. FP: `afterSwap` re-reads pool state. Hook is stateless.

**V263. Uniswap V4 Hook Missing PoolManager Authorization** — D: Hook callbacks callable by anyone, not just PoolManager. Attacker calls `afterSwap` directly with fake data. FP: `onlyPoolManager` modifier on all hooks. `BaseHook` used from V4 periphery.

**V264. Uniswap V4 Hook Dynamic Fee Manipulation** — D: Hook sets dynamic fee in `beforeSwap` based on manipulable on-chain data. Flash loan → manipulate data → swap at zero fee → restore. FP: Fee computed from TWAP or off-chain source. Minimum fee floor enforced.

**V265. Transient Storage Cross-Function Leak (EIP-1153)** — D: Function A writes `tstore(slot, value)`. Function B reads `tload(slot)` expecting zero. Within same transaction, A's transient data leaks to B. FP: Each function uses unique transient slot. Guard clears slot after use.

**V266. Transient Storage Not Cleared After Delegatecall** — D: `delegatecall` to external contract writes transient storage in caller's context. Caller reads stale transient data. FP: Transient storage cleared after delegatecall returns. No transient reads after external interaction.

**V267. Diamond Proxy Facet Removal Orphans Storage** — D: Facet removed via `diamondCut(FacetCutAction.Remove)`. Facet's storage data persists but becomes inaccessible. If facet re-added with different storage layout → corruption. FP: Storage migration on facet replacement. Namespaced storage (EIP-7201).

**V268. Diamond Proxy diamondCut Missing Access Control** — D: `diamondCut()` callable by non-owner — anyone can add/replace/remove facets. FP: `onlyOwner` or multisig + timelock on `diamondCut`.

**V269. AA Paymaster postOp Token Drain** — D: Paymaster's `postOp` transfers tokens but doesn't verify user still has balance. Between `validatePaymasterUserOp` and `postOp`, user operation drains tokens. FP: Tokens escrowed during validation. `postOp` operates on escrowed amount.

**V270. AA UserOp Nonce Channel Manipulation** — D: ERC-4337 uses nonce channels (upper 192 bits = key, lower 64 bits = sequence). Attacker uses different key to bypass sequence check. FP: Protocol validates specific nonce key. Sequential nonce enforcement per channel.

**V271. AA Bundler Gas Manipulation** — D: Bundler provides less `callGasLimit` than UserOp specifies. Operation fails but nonce consumed. FP: On-chain gas validation against UserOp limits. Bundler reputation system.

**V272. L2 Sequencer Timestamp Manipulation** — D: L2 sequencer controls `block.timestamp` within bounds. Manipulates timestamp to trigger time-sensitive operations favorably. FP: Time-sensitive operations use epoch-scale (hours/days). Protocol tolerant of ±15 minute drift.

**V273. L2 Force-Inclusion Delay Exploitation** — D: On L2, forced txs from L1 have delayed inclusion. Protocol assumes tx executes immediately but it enters delay queue. FP: Protocol accounts for inclusion delay. State checks are relative, not absolute time.

**V274. Multi-Token Pool Decimal Mismatch in Liquidation** — D: Multi-collateral liquidation computes penalty using `1e18` for all tokens. USDC (6 decimals) penalty off by 10^12. FP: Per-token `decimals()` normalization in liquidation math.

**V275. Multi-Token Pool Share Computation Rounding** — D: Multi-asset pool computes shares using sum of normalized values. Rounding on each asset compounds — total rounds wrong direction. FP: Final rounding step after aggregation. Protocol-favorable direction enforced.

**V276. Interest Rate Model Jump Exploitation** — D: Interest rate model has kink at utilization threshold. Attacker deposits/borrows to push utilization just past kink — massive rate jump affects all borrowers. FP: Smooth rate curve. Rate change bounded per block. Admin adjustable kink.

**V277. Interest Rate Retroactive Application** — D: Rate updated AFTER accrual calculation. New rate retroactively applied to past period. FP: `accrueInterest()` called BEFORE rate update.

**V278. Permit Front-Running Griefing** — D: Attacker sees victim's `permit + transferFrom` in mempool. Attacker front-runs just the `permit()`. Victim's `permit()` reverts (nonce already consumed), entire tx fails. FP: `try/catch` around `permit()`. Fallback to `approve()`. Check existing allowance first.

**V279. ERC1155 Batch Mint Authorization Gap** — D: `_mintBatch` authorized for some token IDs but not all in the batch. Batch succeeds without per-ID validation. FP: Per-ID authorization in batch loop. Batch operation validates each element.

**V280. Composability Assumption Violation After External Upgrade** — D: Protocol A hardcodes behavior assumptions about Protocol B (return values, token behavior, fee structure). B upgrades → A's assumptions break silently. FP: Interface compliance checked at runtime. Adapter pattern with version checks.

---

## Triage Output Template

After triage, output exactly:
```
Skip: V2, V19, V61, ...
Borderline: V44, V78, ... (with 1-sentence relevance check each)
Survive: V9, V52, V73, ...
Total: 280 classified
```

## Deep Pass Output Template

For each surviving vector:
```
V52: path: deposit() → _transfer() → transferFrom | guard: none | verdict: CONFIRM [85]
V73: path: deposit() → transferFrom | guard: balance-before-after present | verdict: DROP (FP gate 3: guarded)
```
