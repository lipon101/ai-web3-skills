# VeerSkills Master Vulnerability Checklist

Comprehensive checklist distilled from **50,530+ real audit findings**, Cyfrin MCP (`mcp__sc-auditor__get_checklist`), Solodit/Claudit, Secureum, Quillhash, and community databases.

> **Severity Weighting (Based on 50K+ Findings):**
> 1. **Access Control** (Highest probability, highest impact)
> 2. **Reentrancy** ($2B+ historical losses)
> 3. **Oracle Manipulation** (Most common DeFi fatal flaw)
> 4. **Arithmetic & Precision** (Frequent High/Med severity)
> 5. **Token Integration** (Fee-on-transfer, callbacks)

> **Usage**: This is the MASTER checklist. The agent sweeps ALL applicable items per function during Phase 3 (HUNT). Items are grouped by vulnerability class with Cyfrin MCP IDs where available, enabling `mcp__sc-auditor__get_checklist` cross-reference. Check XREF.md for links to concrete exploit forensics for these classes.

---

## 1. REENTRANCY (RE)

### 1.1 Classic Reentrancy
- [ ] **RE-01**: State change AFTER external call? (CEI violation) `[SOL-AM-ReentrancyAttack-2]`
- [ ] **RE-02**: `nonReentrant` modifier on ALL entry points that touch balances?
- [ ] **RE-03**: Cross-function reentrancy via shared state between functions?
- [ ] **RE-04**: Cross-contract reentrancy via callbacks to OTHER contracts?

### 1.2 Read-Only Reentrancy
- [ ] **RE-05**: View functions readable during mid-execution inconsistent state? `[SOL-AM-ReentrancyAttack-1]`
- [ ] **RE-06**: Other protocols reading stale/inconsistent view values during callback?
- [ ] **RE-07**: Reentrancy guard extended to view functions relied on by external protocols?

### 1.3 Callback Reentrancy
- [ ] **RE-08**: ERC-777 `tokensReceived` hook callbacks during transfer?
- [ ] **RE-09**: ERC-721 `onERC721Received` callbacks during safeTransfer?
- [ ] **RE-10**: ERC-1155 `onERC1155Received` callbacks during safeTransfer?
- [ ] **RE-11**: Flash loan callback re-entering the protocol?
- [ ] **RE-12**: Uniswap/AMM swap callbacks re-entering?

---

## 2. ACCESS CONTROL (AC)

### 2.1 Missing Controls
- [ ] **AC-01**: All actors and interactions identified? `[SOL-Basics-AC-1]`
- [ ] **AC-02**: Functions lacking proper access controls? `[SOL-Basics-AC-2]`
- [ ] **AC-03**: Parent contract public functions exposed without override? `[SOL-Basics-AC-6]`
- [ ] **AC-04**: `tx.origin` used instead of `msg.sender`? `[SOL-Basics-AC-7]`

### 2.2 Privilege Management
- [ ] **AC-05**: Two-step ownership transfer implemented? `[SOL-Basics-AC-4]`
- [ ] **AC-06**: Protocol functions correctly during privilege transfer? `[SOL-Basics-AC-5]`
- [ ] **AC-07**: Admin can pull user assets directly? (rug pull risk) `[SOL-AM-RP-1]`
- [ ] **AC-08**: Missing role-based access for sensitive operations?

### 2.3 Initialization
- [ ] **AC-09**: `initializer` vs `onlyInitializing` used correctly? `[SOL-Basics-Initialization-2]`
- [ ] **AC-10**: Initializer front-runnable after deployment? `[SOL-Basics-Initialization-3]`
- [ ] **AC-11**: Implementation contract initialized (vs proxy only)? `[SP-20]`
- [ ] **AC-12**: Important state variables properly initialized? `[SOL-Basics-Initialization-1]`

---

## 3. ARITHMETIC & PRECISION (AR)

### 3.1 Math Errors
- [ ] **AR-01**: Division before multiplication? (precision loss) `[SOL-Basics-Math-4]`
- [ ] **AR-02**: Rounding direction correct? (in favor of protocol) `[SOL-Basics-Math-5]`
- [ ] **AR-03**: Division by zero possible? `[SOL-Basics-Math-6]`
- [ ] **AR-04**: `unchecked{}` blocks verified safe? `[SOL-Basics-Math-9]`
- [ ] **AR-05**: Off-by-one errors in `<` vs `<=`? `[SOL-Basics-Math-10]`
- [ ] **AR-06**: Inline assembly math doesn't revert on overflow/division-by-zero? `[SOL-Basics-Math-11]`
- [ ] **AR-07**: Min/max boundary values produce correct results? `[SOL-Basics-Math-12]`
- [ ] **AR-08**: Negative value assigned to unsigned integer? `[SOL-Basics-Math-8]`

### 3.2 Precision & Decimals
- [ ] **AR-09**: Token decimal mismatch between tokens (6 vs 18)? `[Solodit: Decimals]`
- [ ] **AR-10**: `1 day` expressions cast to `uint24` causing overflow? `[SOL-Basics-Math-3]`
- [ ] **AR-11**: Precision loss in time calculations? `[SOL-Basics-Math-2]`
- [ ] **AR-12**: Summing vs individual calculations diverge? `[SOL-Basics-AL-6]`
- [ ] **AR-13**: Low decimal tokens (e.g., USDC with 6) causing rounding to zero? `[SOL-AM-DOSA-5]`

---

## 4. ORACLE & PRICE FEED (OR)

### 4.1 Price Manipulation
- [ ] **OR-01**: Price calculated from token balance ratio? (donation/flash loan attack) `[SOL-AM-PMA-1]`
- [ ] **OR-02**: Spot price from DEX used as oracle? (flash loan manipulable) `[SOL-AM-PMA-2]`
- [ ] **OR-03**: AMM spot price used instead of TWAP/external oracle? `[D3]`
- [ ] **OR-04**: LP token virtual price used without protection?

### 4.2 Oracle Configuration
- [ ] **OR-05**: Stale price check missing? (Chainlink `updatedAt` check) `[Solodit: Stale Price]`
- [ ] **OR-06**: Chainlink `latestRoundData()` return values validated? (price > 0, timestamp recent)
- [ ] **OR-07**: Chainlink oracle revert causes DoS? `[SOL-AM-DOSA-6]`
- [ ] **OR-08**: Multiple oracle fallback if primary fails?
- [ ] **OR-09**: Oracle decimals handled correctly across different feeds?
- [ ] **OR-10**: Sequencer uptime check for L2s? (Arbitrum/Optimism)

---

## 5. DENIAL OF SERVICE (DO)

### 5.1 Gas Exhaustion
- [ ] **DO-01**: Unbounded loops iterating over user-controlled arrays? `[SOL-Basics-AL-9]`
- [ ] **DO-02**: External call in loop causing DoS if one fails? `[SOL-Basics-AL-10]`
- [ ] **DO-03**: `msg.value` reused inside loops? `[SOL-Basics-AL-11]`
- [ ] **DO-04**: Queue processing exploitable with dust entries? `[SOL-AM-DOSA-4]`

### 5.2 Revert-Based DoS
- [ ] **DO-05**: Pull pattern used for withdrawals? (not push) `[SOL-AM-DOSA-1]`
- [ ] **DO-06**: Minimum transaction amount enforced? `[SOL-AM-DOSA-2]`
- [ ] **DO-07**: Blacklistable tokens (USDC) blocking critical operations? `[SOL-AM-DOSA-3]`
- [ ] **DO-08**: ETH `transfer()` limited to 2300 gas — fails with contract receivers? `[SP-9]`
- [ ] **DO-09**: Receiver can deny payment via fallback revert? `[SOL-Basics-Payment-1]`

### 5.3 Block Stuffing & Timing
- [ ] **DO-10**: Time-sensitive operations exploitable via block stuffing?
- [ ] **DO-11**: Block reorganization risks with CREATE opcode? `[SOL-Basics-BR-1]`

---

## 6. FRONT-RUNNING & MEV (FR)

### 6.1 Transaction Ordering
- [ ] **FR-01**: Get-or-create patterns front-runnable? `[SOL-AM-FrA-1]`
- [ ] **FR-02**: Two-transaction actions front-runnable between calls? `[SOL-AM-FrA-2]`
- [ ] **FR-03**: Dust front-running to grief other users? `[SOL-AM-FrA-3]`
- [ ] **FR-04**: commit-reveal scheme properly user-bound? `[SOL-AM-FrA-4]`
- [ ] **FR-05**: `block.timestamp` manipulation by miners (~15s)? `[SOL-AM-MA-1, SP-13]`
- [ ] **FR-06**: Transaction ordering exploitable? `[SOL-AM-MA-3]`

### 6.2 Sandwich Attacks
- [ ] **FR-07**: Explicit slippage protection on swaps/deposits? `[SOL-AM-SandwichAttack-1]`
- [ ] **FR-08**: Deadline parameter on DeFi interactions?
- [ ] **FR-09**: Oracle updates sandwichable?

---

## 7. TOKEN INTERACTION (TI)

### 7.1 ERC20 Edge Cases
- [ ] **TI-01**: `SafeERC20` / return value checked for `transfer/transferFrom`? `[V1]`
- [ ] **TI-02**: Fee-on-transfer tokens handled? `[D8, Solodit: Fee On Transfer]`
- [ ] **TI-03**: Rebasing tokens handled/documented? `[D6]`
- [ ] **TI-04**: ERC-777 hook callbacks accounted for? `[D7]`
- [ ] **TI-05**: Tokens that return `false` instead of reverting? (non-standard ERC20)
- [ ] **TI-06**: Tokens with non-18 decimals handled correctly? `[D9]`
- [ ] **TI-07**: Tokens with multiple entry points? (proxy tokens)
- [ ] **TI-08**: Pausable tokens that can freeze operations?
- [ ] **TI-09**: Blacklistable tokens that can block addresses? (USDC, USDT)
- [ ] **TI-10**: Tokens with approval race conditions? `[SP-11]`
- [ ] **TI-11**: Missing return value bug (at least 130 tokens affected)?
- [ ] **TI-12**: Upgradeable tokens that can change behavior?
- [ ] **TI-13**: Flash-mintable tokens that can spike supply?
- [ ] **TI-14**: Low-supply tokens where rounding has outsized impact?

### 7.2 Token Accounting
- [ ] **TI-15**: Internal accounting vs raw `balanceOf()` mixing? `[D2, SOL-AM-DA-1]`
- [ ] **TI-16**: Approval target contracts not making arbitrary calls from user input? `[D11]`
- [ ] **TI-17**: `msg.value` vs `amount` parameter mismatch? `[SOL-Basics-Payment-2]`

---

## 8. SIGNATURE & REPLAY (SR)

- [ ] **SR-01**: Replay protection for failed transactions? `[SOL-AM-ReplayAttack-1]`
- [ ] **SR-02**: Cross-chain replay protection (chain ID in domain separator)? `[SOL-AM-ReplayAttack-2]`
- [ ] **SR-03**: `ecrecover` returns `address(0)` — checked? `[SP-12]`
- [ ] **SR-04**: Signature malleability (EIP-2 `s` value check)?
- [ ] **SR-05**: Nonce-based protection against signature replay?
- [ ] **SR-06**: EIP-712 domain separator includes contract address + chain ID?
- [ ] **SR-07**: `abi.encodePacked` hash collision with dynamic types? `[SP-7]`

---

## 9. UPGRADE & PROXY (UP)

- [ ] **UP-01**: Initializer can only be called once?
- [ ] **UP-02**: Storage layout preserved across upgrades? (no slot collision)
- [ ] **UP-03**: Implementation contract has `_disableInitializers()` in constructor?
- [ ] **UP-04**: UUPS `_authorizeUpgrade()` has access control?
- [ ] **UP-05**: Transparent proxy admin is separate from protocol admin?
- [ ] **UP-06**: No `selfdestruct` or `delegatecall` in implementation?
- [ ] **UP-07**: State variables not reordered/removed between versions?
- [ ] **UP-08**: New variables only added at END of storage layout?

---

## 10. COMPOSABILITY & INTEGRATION (CO)

### 10.1 External Calls
- [ ] **CO-01**: External contract call actually needed? `[X1]`
- [ ] **CO-02**: External call error could cause DoS? `[X2]`
- [ ] **CO-03**: External call using all gas? `[X6]`
- [ ] **CO-04**: Massive return data causing out-of-gas? `[X7]`
- [ ] **CO-05**: `success` check doesn't verify function exists? (phantom functions) `[X8]`

### 10.2 Protocol Integration
- [ ] **CO-06**: Flash loan interactions can manipulate protocol state?
- [ ] **CO-07**: Cross-contract view reentrancy via price feeds?
- [ ] **CO-08**: Composability with unknown tokens (arbitrary ERC20)?
- [ ] **CO-09**: Assumptions about external contract behavior documented? `[D1]`

---

## 11. GRIEFING & SYBIL (GS)

- [ ] **GS-01**: External state dependency that others can change? `[SOL-AM-GA-1]`
- [ ] **GS-02**: Precise gas limit manipulation for execution path control? `[SOL-AM-GA-2]`
- [ ] **GS-03**: Sybil attack on user-count-dependent mechanisms? `[SOL-AM-SybilAttack-1]`
- [ ] **GS-04**: First depositor / share inflation attack? `[Solodit: First Depositor]`
- [ ] **GS-05**: Dust amounts used to grief other users?

---

## 12. DATA HANDLING (DH)

### 12.1 Arrays & Loops
- [ ] **DH-01**: First/last iteration edge cases? `[SOL-Basics-AL-1]`
- [ ] **DH-02**: Array deletion resetting but not rearranging? `[SOL-Basics-AL-4]`
- [ ] **DH-03**: Array index passed as argument stale after modification? `[SOL-Basics-AL-5]`
- [ ] **DH-04**: Duplicate items in arrays unchecked? `[SOL-Basics-AL-7]`
- [ ] **DH-05**: `break`/`continue` in loop creating edge cases? `[SOL-Basics-AL-13]`
- [ ] **DH-06**: Batch transfer dust handling for last element? `[SOL-Basics-AL-12]`

### 12.2 Storage & Mapping
- [ ] **DH-07**: Nested structure `delete` not clearing inner fields? `[SOL-Basics-Map-1]`
- [ ] **DH-08**: Uninitialized storage pointers? `[SP-2]`
- [ ] **DH-09**: Write to arbitrary storage location?
- [ ] **DH-10**: Dirty high bits in `msg.data`? `[SP-8]`

---

## 13. CODE QUALITY & COMPILER (CQ)

- [ ] **CQ-01**: Events emitted for all state changes? `[SOL-Basics-Event-1, SP-10]`
- [ ] **CQ-02**: Function visibility appropriate? (public vs external vs internal) `[SOL-Basics-Function-7]`
- [ ] **CQ-03**: Comments match implementation? `[SOL-Basics-Function-4]`
- [ ] **CQ-04**: Correct inheritance order (C3 linearization)? `[SP-15]`
- [ ] **CQ-05**: Interface fully implemented? `[SOL-Basics-Inheritance-3]`
- [ ] **CQ-06**: Locked pragma version? (not floating)
- [ ] **CQ-07**: Known compiler bugs for the used version? (check `docs.soliditylang.org/en/latest/bugs.html`)
- [ ] **CQ-08**: `selfdestruct` protected? `[SP-6]`
- [ ] **CQ-09**: Locked ether — contract receives ETH but no withdrawal? `[SP-4]`
- [ ] **CQ-10**: Shadowed state variables? (parent vs child)
- [ ] **CQ-11**: Forcibly sent ETH (via selfdestruct/coinbase) handle? (Unexpected balance)

---

## 14. RANDOMNESS (RN)

- [ ] **RN-01**: `block.timestamp`/`blockhash`/`block.difficulty` as randomness source? `[SOL-AM-MA-2]`
- [ ] **RN-02**: Chainlink VRF or commit-reveal used instead?
- [ ] **RN-03**: VRF callback secured against unauthorized callers?
- [ ] **RN-04**: Randomness seed predictable or manipulable by miners?

---

## 15. GOVERNANCE & VOTING (GV)

- [ ] **GV-01**: Flash loan voting power acquisition? (snapshot-based voting required) `[Solodit: Vote]`
- [ ] **GV-02**: Voting power double-counted via delegation transfer?
- [ ] **GV-03**: Proposal execution can revert and block queue?
- [ ] **GV-04**: Timelock between approval and execution?
- [ ] **GV-05**: Governance parameters bounded to safe ranges?

---

## 16. FLASH LOAN (FL)

- [ ] **FL-01**: Protocol state manipulable via flash loans? `[Solodit: Flash Loan]`
- [ ] **FL-02**: Checkpoint/snapshot manipulation via flash-borrow?
- [ ] **FL-03**: Share price inflatable via flash loan + donation?
- [ ] **FL-04**: Liquidation threshold gameable via flash loan?
- [ ] **FL-05**: Flash loan fee correctly enforced on repayment?

---

## 17. ERC4626 VAULT (VT)

*Sources: devdacian ERC4626 primer (366+ vulns), OpenZeppelin inflation defense, paragraph.com vault bugs, Cyfrin `Vault` category*

### 17.1 Share/Asset Accounting
- [ ] **VT-01**: First depositor / share inflation attack mitigated? (virtual shares/offset) `[Solodit: First Depositor Issue]`
- [ ] **VT-02**: Deposit/withdraw rounding direction correct? (deposit rounds UP, withdraw rounds DOWN — favors protocol)
- [ ] **VT-03**: `totalAssets()` includes all protocol-managed assets (staked, lent, pending rewards)?
- [ ] **VT-04**: Share price manipulable via direct token donation to vault? `[Solodit: ERC4626]`
- [ ] **VT-05**: Zero-share minting possible from positive deposits (dust)?

### 17.2 Vault Operations
- [ ] **VT-06**: `maxDeposit`, `maxMint`, `maxWithdraw`, `maxRedeem` correctly implemented per EIP-4626?
- [ ] **VT-07**: Preview functions (`previewDeposit`, `previewRedeem`) match actual execution within 1 wei?
- [ ] **VT-08**: Vault decimals >= underlying asset decimals? (precision loss otherwise)
- [ ] **VT-09**: Fee-on-transfer tokens cause accounting mismatch in vault deposits?
- [ ] **VT-10**: Strategy return value confusion (assets returned vs shares minted)?

### 17.3 Yield & Reward
- [ ] **VT-11**: Reward calculation updated before state changes (claim before transfer)?
- [ ] **VT-12**: Reward rate dilutable by attacker depositing before distribution?
- [ ] **VT-13**: Compounding interest calculation includes accrued but unclaimed interest?
- [ ] **VT-14**: Yield position liquidation bypassable by partial position manipulation?

---

## 18. NFT & ERC721 (NF)

*Sources: Quillhash NFT-Attack-Vectors (25), 0xvolodya NFT attacks, electisec ERC721*

- [ ] **NF-01**: `tokenId` uniqueness guaranteed? (formula-based IDs can collide)
- [ ] **NF-02**: `safeMint` / `safeTransfer` callbacks checked for reentrancy?
- [ ] **NF-03**: Royalty bypass via custom marketplace or `transferFrom` (skipping `safeTransferFrom`)?
- [ ] **NF-04**: Unlimited approval on NFT marketplace contract exploitable?
- [ ] **NF-05**: Metadata URI manipulation (off-chain metadata can be changed post-mint)?
- [ ] **NF-06**: ERC721 enumerable gas DoS with large collections?
- [ ] **NF-07**: Lazy minting price manipulation (front-running mint transaction)?
- [ ] **NF-08**: Airdrop/free-mint Sybil attack via multiple wallets?

---

## 19. BRIDGE & CROSS-CHAIN (BR)

*Sources: Quillhash Cross-chain-Attacks, OfficerCIA bridge blog, electisec, secureum*

- [ ] **BR-01**: Message replay across chains (chain ID + nonce in message hash)?
- [ ] **BR-02**: Source chain validation — only accepted bridge contract can submit messages?
- [ ] **BR-03**: Token accounting mismatch between source and destination chains?
- [ ] **BR-04**: Bridge relayer can censor or reorder messages?
- [ ] **BR-05**: Finality assumptions — source chain reorg after destination processes message?
- [ ] **BR-06**: Fee token different on each chain — fee calculation errors?
- [ ] **BR-07**: Wrapped asset depeg risk when bridge pauses/fails?

---

## 20. COMPOUND FORKS (CF)

*Sources: electisec CommonWeb3SecurityIssues, Cyfrin `Liquidation` category*

- [ ] **CF-01**: Compound CEI violation — callback tokens (ERC777/721) re-enter during interest accrual?
- [ ] **CF-02**: Non-whitelisted tokens with fee-on-transfer breaking accounting?
- [ ] **CF-03**: cToken exchange rate manipulable via direct transfer to market?
- [ ] **CF-04**: Liquidation incentive calculation correct for edge cases (100% liquidation)?
- [ ] **CF-05**: Interest rate model jumps exploitable at utilization boundaries?

---

## 21. DEFI-SPECIFIC PATTERNS (DF)

*Sources: 0xprinc checks-while-hacks, Quillhash DeFi-Attack-Vectors, dacian.me, samczsun oracle*

### 21.1 Swap & Liquidity
- [ ] **DF-01**: One-sided swap before LP deposit leaves dust due to price impact?
- [ ] **DF-02**: Swap deadline set to `block.timestamp` provides no protection?
- [ ] **DF-03**: Expected swap output calculated from stale or manipulable data?

### 21.2 Staking & Rewards
- [ ] **DF-04**: Reward distribution denominator include inactive/exited stakes?
- [ ] **DF-05**: Staking reward accrual timing — rewards lost during transfer/unstake?
- [ ] **DF-06**: Minimum deposit enforced to prevent zero-amount privilege?

### 21.3 Liquidation
- [ ] **DF-07**: Liquidation penalty correctly applied to seized collateral? `[dacian.me]`
- [ ] **DF-08**: Self-liquidation possible to extract protocol incentives? `[dacian.me]`
- [ ] **DF-09**: Bad debt handling — who absorbs losses when collateral < debt? `[dacian.me]`
- [ ] **DF-10**: Liquidation DoS — can borrower front-run liquidation to block it? `[dacian.me]`

---

## MCP Integration Map

### `mcp__sc-auditor__get_checklist`
The Cyfrin checklist provides **200+ items** across categories. During Phase 3, call:
```
mcp__sc-auditor__get_checklist({category: "<category>"})
```
Key categories: `Denial-Of-Service(DOS) Attack`, `Front-running Attack`, `Reentrancy Attack`, `Price Manipulation Attack`, `Sandwich Attack`, `Sybil Attack`, `Replay Attack`, `Griefing Attack`, `Donation Attack`, `Access Control`, `Math`, `Array / Loop`, `Payment`, `Initialization`, `Inheritance`, `Block Reorganization`, `Map`, `Event`, `Function`, `ERC20`, `ERC721`, `Staking`, `Swap`, `Oracle`, `Liquidation`, `Bridge`, `Governor`, `Vault`

### `mcp__claudit__search_findings`
Solodit has **48,000+ findings**. Search by vulnerability tag for real-world examples:
```
mcp__claudit__search_findings({keywords: "<pattern>", severity: ["HIGH"], tags: ["<tag>"]})
```
Top tags: `Business Logic`, `Validation`, `Wrong Math`, `Front-Running`, `DOS`, `Fee On Transfer`, `Oracle`, `Reentrancy`, `Access Control`, `Decimals`, `Liquidation`, `Overflow/Underflow`, `Slippage`, `Rounding`, `Stale Price`, `ERC4626`, `First Depositor Issue`, `Flash Loan`, `Weird ERC20`, `Fund Lock`, `Vote`

### `mcp__claudit__get_finding`
For detailed PoC and mitigation of a specific finding:
```
mcp__claudit__get_finding({identifier: "<finding_id>"})
```

### Deduplication Note
`mcp__sc-auditor__search_findings` and `mcp__claudit__search_findings` BOTH query Solodit but with different features:
- **Use `claudit`** for: advanced filters (quality_score, rarity_score, protocol_category, firm, finders count), detailed content, pagination
- **Use `sc-auditor`** for: quick searches with severity filter, simpler interface
- **Recommendation**: Use `claudit` as primary, `sc-auditor` as fallback

---

## 22. PERMIT & EIP-2612 (PM)

*Sources: OpenZeppelin advisories, Code4rena/Sherlock 2024-2025 permit-related findings*

- [ ] **PM-01**: Permit signature includes `msg.sender` binding? (prevent front-running proof reuse)
- [ ] **PM-02**: Permit deadline reasonable? (not `type(uint256).max` — leaked sig = permanent drain)
- [ ] **PM-03**: Permit nonce correctly incremented on use? (replay prevention)
- [ ] **PM-04**: `try/catch` around `permit()` call? (front-running griefing DoS protection)
- [ ] **PM-05**: Domain separator includes `address(this)` + `block.chainid`? (cross-chain + cross-contract replay)
- [ ] **PM-06**: Permit2 allowance inheritance checked? (Protocol A approval ≠ Protocol B authorization)
- [ ] **PM-07**: Permit used with non-standard tokens that don't support EIP-2612?

---

## 23. TIMELOCK & DELAY (TL)

*Sources: Compound Governor, OpenZeppelin TimelockController, real governance attacks*

- [ ] **TL-01**: Timelock present on all privileged operations? (upgrade, oracle change, fee change)
- [ ] **TL-02**: Timelock duration sufficient? (≥ 24h for admin, ≥ 48h for upgrades)
- [ ] **TL-03**: Timelock bypasable via emergency function without proper safeguards?
- [ ] **TL-04**: Queue poisoning — can attacker fill queue with junk proposals blocking legitimate ones?
- [ ] **TL-05**: Timelock cancel function has proper access control? (prevent admin from canceling after reveal)
- [ ] **TL-06**: Delay manipulation — can admin set delay to 0 and immediately execute?

---

## 24. MULTI-TOKEN ACCOUNTING (MT)

*Sources: Curve Finance, Balancer, Aave V3 multi-collateral, contest findings*

- [ ] **MT-01**: Per-token decimal normalization in ALL cross-token operations? (6 vs 8 vs 18)
- [ ] **MT-02**: Fee-on-transfer tokens in multi-token pools handled with balance-before-after?
- [ ] **MT-03**: Rebasing tokens in multi-asset pools — share computation stable after rebase?
- [ ] **MT-04**: Pool share invariant: `sum(token_values) >= total_shares * share_price`?
- [ ] **MT-05**: Rounding in multi-token operations compounds favorably for protocol?
- [ ] **MT-06**: Token addition/removal from pool doesn't break existing accounting?

---

## 25. ACCOUNT ABSTRACTION (AA)

*Sources: ERC-4337, ERC-7579, Biconomy, Safe Smart Account, contest findings*

- [ ] **AA-01**: `validateUserOp` restricts `msg.sender == entryPoint`? `[V150]`
- [ ] **AA-02**: Validation-phase banned opcodes avoided? (`block.timestamp`, `block.number`, etc.) `[V100]`
- [ ] **AA-03**: UserOp nonce validated per key channel? (no cross-channel nonce bypass)
- [ ] **AA-04**: Paymaster prefund includes unused-gas penalty? `[V108]`
- [ ] **AA-05**: Paymaster token payment not deferred to `postOp` without escrow? `[V122]`
- [ ] **AA-06**: UserOp signature bound to nonce and chainId? `[V21]`
- [ ] **AA-07**: Module/plugin installation gated by owner? (no unauthorized module injection)
- [ ] **AA-08**: Execution-phase reentrancy into wallet protected? (callback → re-enter wallet)

