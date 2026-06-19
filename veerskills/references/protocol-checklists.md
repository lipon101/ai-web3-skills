# Protocol-Specific Vulnerability Checklists

Protocol-type-specific vulnerability patterns sourced from 460+ real audit findings across 31 protocol types (Protocol Vulnerabilities Index), Decurity checklists, Solcurity standard, Secureum mindmaps, and community databases. Auto-loaded during Phase 3 (HUNT) based on detected protocol type.

> **Source**: [Protocol Vulnerabilities Index](https://github.com/kadenzipfel/protocol-vulnerabilities-index) (460 vulns, 31 types), [Decurity](https://github.com/Decurity/audit-checklists), [Solcurity](https://github.com/transmissions11/solcurity), [Secureum](https://github.com/x676f64/secureum-mind_map)

---

## Lending Protocol Checklist

### Liquidation Logic
- [ ] Can a position be liquidated and still leave bad debt (underwater after liquidation)?
- [ ] Is there a liquidation incentive/bonus that's bounded? (too high = drains protocol, too low = no one liquidates)
- [ ] Can self-liquidation be used to game the system (liquidate yourself for the bonus)?
- [ ] Does the health factor check happen BEFORE or AFTER the liquidation? (must be before)
- [ ] Can a borrower front-run liquidation with a small repay to grief the liquidator?
- [ ] What happens when collateral price drops > liquidation bonus in one block? (bad debt)
- [ ] Is there a bad debt socialization mechanism?
- [ ] Can flash loans be used to manipulate health factor for liquidation avoidance?

### Interest Rate
- [ ] Is interest accrued BEFORE state changes in borrow/repay/liquidate?
- [ ] Can interest rate be manipulated by flash-loaning huge amounts?
- [ ] Is the interest rate model correct at boundary values (0% utilization, 100% utilization)?
- [ ] Does compounding math use the correct time base? (seconds vs blocks vs epochs)
- [ ] Are there rounding exploits in interest calculations at very small or very large positions?

### Position Health
- [ ] Can a user borrow against collateral and withdrawal collateral in the same transaction?
- [ ] Is the health check performed after EVERY state-changing action?
- [ ] Can price oracle delay create a window where unhealthy positions aren't liquidatable?
- [ ] Are all collateral types properly valued with appropriate LTV ratios?

### Accounting
- [ ] Do share/asset conversions match between deposit, withdrawal, borrow, and repay?
- [ ] Can precision loss in share calculations create free tokens over many small operations?
- [ ] Is the total borrow tracked correctly across partial repayments?
- [ ] Can the total supply of debt tokens diverge from actual debt?
- [ ] Are bad debts properly accounted for and socialized?

---

## DEX / AMM Checklist

### Swap Mechanics
- [ ] Is the constant product (x*y=k) or CPMM formula correctly implemented?
- [ ] Can reserves be manipulated by direct token transfer (donation attack on price)?
- [ ] If using forked code (Uniswap), has contract-diff.xyz comparison been done?
- [ ] Are rounding errors in product constant formulas exploitable?
- [ ] Is the CEI pattern followed when updating reserves? (prevents callback reentrancy)

### Fee & Slippage
- [ ] Are fees deducted BEFORE or AFTER the swap calculation? (must be consistent)
- [ ] Does the protocol support fee-on-transfer tokens? Is the fee accounted for in swap math?
- [ ] Is `minAmountOut` enforced on ALL swap paths?
- [ ] Is there a `deadline` parameter to prevent pending transaction exploitation?
- [ ] Can sandwich attacks extract value from swaps without slippage protection?

### Liquidity Provision
- [ ] First depositor / initial liquidity manipulation: can attacker inflate share price?
- [ ] Is minimum liquidity locked to prevent total share manipulation?
- [ ] Can LP token minting/burning create rounding exploits?
- [ ] Are there imbalanced deposit/withdrawal attacks on multi-asset pools?

### Flash Swaps / Loans
- [ ] Is the callback function called AFTER token transfer, not before?
- [ ] Can the callback be used to manipulate reserves during the swap?
- [ ] Is the fee correctly calculated and enforced on flash loan repayment?

### TWAMM / Concentrated Liquidity
- [ ] Does the TWAMM handle rebasing tokens during long-term swaps?
- [ ] Is there a liquidity check before executing long-term orders?
- [ ] For concentrated liquidity: can positions be manipulated at tick boundaries?

### Integration
- [ ] Do callback functions (e.g., `uniswapV3SwapCallback`) verify the calling contract address?
- [ ] Is `minAmountOut` calculated using external oracles, not spot price?

---

## CDP / Stablecoin Checklist

### Collateral Management
- [ ] Can collateral value be manipulated through oracle or donation attacks?
- [ ] Are all supported collateral types tested (ERC20, LP tokens, yield tokens, NFTs)?
- [ ] Is collateral valuation correct for tokens with non-18 decimals?
- [ ] For LP collateral: is the virtual price attack vector mitigated?
- [ ] For yield-bearing collateral: is the exchange rate manipulable?

### Debt Management
- [ ] Can debt be taken without proper collateral backing?
- [ ] Is the collateralization ratio enforced at all entry points?
- [ ] Can flash loans be used to bypass collateralization requirements?
- [ ] Is there a minimum debt amount to prevent dust positions?

### Liquidation (CDP-specific)
- [ ] In auction-based liquidations: can the auction be griefed or blocked?
- [ ] Is there a grace period that can be exploited?
- [ ] Can the liquidation keeper front-run other keepers to extract MEV?
- [ ] What happens if no one bids in an auction? Is there a fallback?

### Peg Stability
- [ ] Can the stablecoin be minted without proper collateral?
- [ ] Is the peg mechanism robust to large market moves?
- [ ] Can governance parameters be manipulated to destabilize the peg?

---

## Yield / Vault Checklist

### Share Price & Inflation
- [ ] First depositor attack: virtual share offset or dead shares implemented?
- [ ] Can donation attack manipulate share price?
- [ ] Is share price monotonically increasing (excluding loss events)?
- [ ] Are deposit/redeem rounding directions correct? (deposit rounds DOWN shares, redeem rounds UP assets)

### Strategy Integration
- [ ] What happens if a strategy reports a loss? Is it properly propagated to share price?
- [ ] Can an attacker manipulate strategy returns via flash loans?
- [ ] Are strategy harvest timestamps exploitable for share price manipulation?
- [ ] Can a strategy be sandwiched around harvest/compound calls?

### Withdrawal Queue
- [ ] Can withdrawal requests be blocked by a grief attack?
- [ ] Is there a maximum queue length or minimum withdrawal amount?
- [ ] What happens if the vault doesn't have enough liquid assets?
- [ ] Can prioritized withdrawals bypass the queue unfairly?

### Fee Accounting
- [ ] Are performance fees calculated on actual profit, not total assets?
- [ ] Can management fees compound to drain the vault?
- [ ] Are fee recipient addresses validated (non-zero)?
- [ ] Is fee precision loss exploitable?

---

## Staking / Rewards Checklist

### Reward Distribution
- [ ] Is the reward per token accumulator updated BEFORE any state change?
- [ ] Can a user stake 0 or dust amounts to claim disproportionate rewards?
- [ ] Is there a minimum staking duration? Can flash-stake claim rewards?
- [ ] Are rewards calculated correctly across multiple reward periods?
- [ ] Can unused rewards be recovered? Or are they locked forever?

### Staking Mechanics
- [ ] Is there a cooldown/unbonding period? Can it be bypassed?
- [ ] Can slashing be avoided by unstaking before the slash event?
- [ ] Is the reward rate update atomic with deposit/withdrawal?
- [ ] Can a large stake/unstake sandwich the reward distribution?

### Delegation (Liquid Staking)
- [ ] Can delegation be front-run to claim someone else's rewards?
- [ ] Is the exchange rate (staked token ↔ liquid token) manipulable?
- [ ] Are validator selection/rotation mechanisms fair?
- [ ] What happens if a validator is slashed? Is the loss proportional?

---

## Governance Checklist

### Voting Power
- [ ] Can flash loans be used to acquire voting power? (snapshot-based voting required)
- [ ] Is vote delegation properly tracked and non-exploitable?
- [ ] Can voting power be double-counted through transfers during voting?
- [ ] Is there a minimum quorum that prevents low-participation attacks?

### Proposal Execution
- [ ] Is there a timelock between proposal passing and execution?
- [ ] Can the timelock be bypassed through multiple proposals?
- [ ] Is there a grace period after timelock that could be missed?
- [ ] Can proposal execution revert and block the queue?

### Parameter Changes
- [ ] Are governance-changeable parameters bounded?
- [ ] Can fee parameters be set to 100% through governance?
- [ ] Can oracle addresses be changed to malicious ones?
- [ ] Is there a guardian/emergency role that can bypass governance?

---

## Bridge / Cross-Chain Checklist

### Message Validation
- [ ] Is the source chain validated before processing messages?
- [ ] Is the sender address verified on the source chain?
- [ ] Is there nonce-based replay protection?
- [ ] Can the same message be replayed across different chains?

### Token Handling
- [ ] Are token mappings (source ↔ destination) correctly maintained?
- [ ] Can unmapped tokens be bridged to cause loss of funds?
- [ ] Are native ETH and wrapped ETH handled correctly?
- [ ] Is the flow rate/rate limiting implemented to cap maximum bridged amount?

### Relayer/Sequencer
- [ ] What happens if the relayer goes offline? Can users still withdraw?
- [ ] Can the relayer censor or reorder messages?
- [ ] Is there a fallback mechanism for stuck messages?
- [ ] Is the gas estimation correct for cross-chain execution?

---

## NFT / Marketplace Checklist

### Transfer & Ownership
- [ ] Is `safeTransferFrom` used and does it trigger callback reentrancy?
- [ ] Can `transferFrom` bypass approval checks?
- [ ] Are royalty fees correctly calculated and distributed (EIP-2981)?
- [ ] Can NFT attributes be manipulated by the owner after listing?

### Auction & Listing
- [ ] Can bids be front-run or sandwiched?
- [ ] Is there a minimum bid increment to prevent griefing?
- [ ] Can a listing be created for an NFT the seller doesn't own?
- [ ] What happens if the NFT is transferred while a listing is active?

### Randomness (Gaming/NFT)
- [ ] Is Chainlink VRF or commit-reveal used for randomness? (not block.timestamp/hash)
- [ ] Can the randomness request be manipulated by rerolling?
- [ ] Is the VRF callback secured against unauthorized callers?

---

## Insurance Protocol Checklist

- [ ] Is the claim validation process decentralized and fair?
- [ ] Can claim payouts exceed the insurance pool?
- [ ] Are premium calculations correct and not exploitable?
- [ ] Is premium pricing front-runnable?
- [ ] Can the withdrawal queue for premium redemption be DoS'd?
- [ ] Are covered events properly defined and not ambiguous?

---

## Launchpad / Token Sale Checklist

- [ ] Is the vesting cliff and linear vesting correctly calculated?
- [ ] Can cliff be bypassed through contract interaction?
- [ ] Is there snapshot-based checkpoint manipulation via flash loans?
- [ ] Are allocation caps enforced and not bypassable by multiple accounts (Sybil)?
- [ ] Is the auction mechanism (Dutch/English) correctly implemented at boundaries?
- [ ] Can ETH overpayment be lost? (missing refund logic)
- [ ] Is the selfdestruct of temporary contracts handled safely?

---

## Perpetuals / Derivatives Checklist

*Source: WEB3-AUDIT-SKILLS perpetuals-checklist*

- [ ] Funding rate calculation: correctly reflects imbalance between longs and shorts?
- [ ] Mark price vs index price: manipulation of mark price for liquidation attacks?
- [ ] ADL (Auto-Deleveraging): profitable positions forcibly reduced — ordering fair?
- [ ] Position size limits: can one trader dominate the open interest?
- [ ] PnL settlement: realized PnL uses correct mark/index price at time of close?
- [ ] Leverage: maximum leverage bounded and enforced at position open AND updates?
- [ ] Insurance fund: adequately funded to cover cascading liquidations?
- [ ] Fee structure: maker/taker fees calculated on correct notional value?

---

## Restaking / LRT Checklist

*Source: WEB3-AUDIT-SKILLS restaking-lrt-checklist*

- [ ] Slashing propagation: AVS slashing event correctly reduces LRT share value?
- [ ] AVS registration: operator cannot register for incompatible AVS combinations?
- [ ] Withdrawal queue: restaked assets subject to both EigenLayer AND protocol unbonding?
- [ ] Operator delegation: withdrawing user receives correct pro-rata of operator rewards?
- [ ] Double slashing: same event cannot slash across multiple AVS registrations?
- [ ] Share accounting: LRT accurately reflects underlying restaked ETH minus slashing?
- [ ] Strategy integration: adding/removing strategies doesn't corrupt existing positions?
- [ ] Withdrawal credential: withdrawal address set to protocol, not operator?

---

## Liquid Staking Checklist

*Source: WEB3-AUDIT-SKILLS liquid-staking-checklist*

- [ ] Exchange rate: totalPooledETH / totalShares updated ONLY by oracle report?
- [ ] Oracle report bounded: rate cannot change by more than X% per report?
- [ ] Validator withdrawal credentials: set to protocol contract, not operator?
- [ ] Validator key uniqueness: same BLS key cannot be registered twice?
- [ ] Slashing loss: distributed pro-rata across all LST holders?
- [ ] Operator exit: protocol can force validator exit via signed exit message?
- [ ] stETH rebase: balances update correctly — integrations must use wstETH or rate?
- [ ] Exchange rate attack: large deposit BEFORE oracle report cannot steal pending rewards?
- [ ] Beacon chain balance reconciliation: protocol accounting matches on-chain validators?
- [ ] Oracle quorum: multiple reporters must agree on beacon state?

---

## Options / Structured Products Checklist

*Source: WEB3-AUDIT-SKILLS options-structured-checklist*

- [ ] Black-Scholes or pricing model: IV input source validated (can't be manipulated)?
- [ ] Settlement oracle: returns price at EXACT expiry timestamp, not latest?
- [ ] Exercise logic: options only exercisable after expiry and before deadline?
- [ ] Collateral locking: writer's collateral locked until expiry regardless of price?
- [ ] IV manipulation: option purchase cannot front-run IV update to get better premium?
- [ ] Payout calculation: max payout bounded by collateral (writer can't owe more than deposited)?
- [ ] Auto-exercise: in-the-money options auto-exercised at expiry if no claim?
- [ ] Binary/digital options: payout is fixed amount or zero — no partial payout bugs?

---

## Intent-Based Protocol Checklist

*Source: WEB3-AUDIT-SKILLS intent-based-checklist*

- [ ] Solver competition: intent settled by best solver offer, not first submitted?
- [ ] Intent expiry: stale intents cannot be filled after deadline at outdated price?
- [ ] Solver bond: solvers post collateral that can be slashed for malicious fills?
- [ ] Fill validation: settled tokens match user's intent specification exactly?
- [ ] Partial fills: user's intent can't be partially filled leaving dust unfillable?
- [ ] MEV protection: solver cannot extract value beyond specified slippage?
- [ ] Cross-chain intents: execution verified on both source and destination chains?

---

## Solcurity Standard Integration

### Code-Level Checks (from Solcurity)
- [ ] **V1**: Is `SafeERC20` used for ALL token interactions?
- [ ] **V3**: Can any variable be set to a value that would render the contract ineffective? (e.g., fee = 100%)
- [ ] **V5**: For auth functions, verify `msg.sender == owner` not `tx.origin == owner`
- [ ] **V7**: If variable packing is used, are values read together actually accessed together?
- [ ] **V8**: Are re-assignable state variables event-emitted on change?

### External Call Checks (from Solcurity)
- [ ] **X3**: Would reentrancy through THIS function be harmful?
- [ ] **X4**: Would reentrancy through ANOTHER function be harmful?
- [ ] **X6**: What if the external call uses all provided gas?
- [ ] **X7**: Can the return data cause out-of-gas in the calling contract?
- [ ] **X8**: Do not assume `success` implies the function exists (phantom functions)

### DeFi Checks (from Solcurity)
- [ ] **D2**: Don't mix internal accounting with raw `balanceOf()` calls
- [ ] **D3**: Don't use AMM spot price as oracle
- [ ] **D6**: Watch for rebasing tokens — document if unsupported
- [ ] **D7**: Watch for ERC-777 callback reentrancy even on trusted tokens
- [ ] **D10**: Don't rely on raw token balance for share price calculations
- [ ] **D11**: If contract is target for approvals, don't make arbitrary calls from user input

---

## Secureum Pitfalls Integration

### Top Missing Patterns (from Secureum 101/201)
- [ ] **SP-1**: Incorrect constructor name or visibility in Solidity <0.4.22
- [ ] **SP-2**: Uninitialized storage pointers in older Solidity versions
- [ ] **SP-3**: Missing `payable` on functions that should receive ETH
- [ ] **SP-4**: Locked ether — contract receives ETH but has no withdrawal function
- [ ] **SP-5**: Incorrect function state mutability (marked `view` but modifies state)
- [ ] **SP-6**: Unprotected `selfdestruct` allows anyone to destroy contract
- [ ] **SP-7**: Hash collision with `abi.encodePacked` of dynamic types
- [ ] **SP-8**: Dirty high bits in `msg.data` can affect logic
- [ ] **SP-9**: `transfer()` and `send()` limited to 2300 gas — may fail with contract recipients
- [ ] **SP-10**: Missing events for critical state changes
- [ ] **SP-11**: ERC-20 `approve()` race condition
- [ ] **SP-12**: `ecrecover` returns `address(0)` for invalid signatures — must check
- [ ] **SP-13**: Using `block.timestamp` for critical logic (can be manipulated ~15s by miners)
- [ ] **SP-14**: Short address attack with `msg.data` padding
- [ ] **SP-15**: Incorrect inheritance order (C3 linearization)
- [ ] **SP-16**: Missing `delete` for storage references (stale data)
- [ ] **SP-17**: Account existence check before `transfer` — low-level calls to EOAs succeed
- [ ] **SP-18**: Unexpected `msg.value` in loops (reused across iterations)
- [ ] **SP-19**: Incorrect function selector collision from function overloading
- [ ] **SP-20**: Uninitialized proxy implementations allowing takeover

---

## Usage

During Phase 3 (HUNT), detect protocol type and load the appropriate section:

```
Protocol Detection → Checklist Loaded:
├── Lending → "Lending Protocol Checklist"
├── DEX/AMM → "DEX / AMM Checklist"
├── CDP/Stablecoin → "CDP / Stablecoin Checklist"
├── Vault/Yield → "Yield / Vault Checklist"
├── Staking → "Staking / Rewards Checklist"
├── Governance → "Governance Checklist"
├── Bridge → "Bridge / Cross-Chain Checklist"
├── NFT/Marketplace → "NFT / Marketplace Checklist"
├── Insurance → "Insurance Protocol Checklist"
├── Launchpad → "Launchpad / Token Sale Checklist"
├── Perpetuals → "Perpetuals / Derivatives Checklist"
├── Restaking/LRT → "Restaking / LRT Checklist"
├── Liquid Staking → "Liquid Staking Checklist"
├── Options → "Options / Structured Products Checklist"
├── Intent-Based → "Intent-Based Protocol Checklist"
└── ALL → "Solcurity + Secureum Integration" (always loaded)
```

Always load the Solcurity and Secureum sections regardless of protocol type.

