# Protocol Playbooks

This reference document contains specific, battle-tested playbooks for securely integrating with or auditing atop the most dominant DeFi building blocks. 

---

## 1. Uniswap V3 Playbook

**Architecture TL;DR:** Concentrated liquidity, tick mathematics, dynamic fees, NFTs representing positions instead of fungible ERC20 tokens.

### Security Checklist for V3 Integrations:
- [ ] **Slippage Deadlines:** Are `deadline` parameters hardcoded to `block.timestamp`? (BAD). They must be user-provided to prevent validators from holding the tx and executing it when the price shifts unfavorably.
- [ ] **amountOutMinimum Check:** Ensure `amountOutMinimum` is calculated appropriately via a reliable off-chain oracle or TWAP (not 0).
- [ ] **TWAP Manipulation:** If using `observe()`, is the `secondsAgos` parameter large enough? Intervals under 5 minutes on low-liquidity pools can be manipulated across multiple blocks by an organized MEV miner.
- [ ] **Callback Reentrancy:** Does the integrating contract perform state updates *after* `uniswapV3SwapCallback`? (BAD). Ensure all state is locked or committed prior.
- [ ] **Tick Math Precision:** Are you using Uniswap's official `TickMath` library, or custom derivations? Custom float/int rounding logic frequently leads to overflow/underflow exploits.
- [ ] **Just-In-Time (JIT) Flash Liquidity:** Does the protocol rely on spot LP fees? JIT attackers can observe a huge swap, flash-mint concentrated liquidity covering the exact tick, capture 99% of the fee, and instantly withdraw.

**Common Exploit:** Reentrancy via ERC777 tokens during the callback or failing to implement a slippage lock, allowing a MEV bot to sandwich a huge router trade.

---

## 2. Aave V3 Playbook

**Architecture TL;DR:** E-Mode (Efficiency Mode), Isolation Mode, Siloed borrowing, FlashLoans, optimized L2 ports.

### Security Checklist for Aave Integrations:
- [ ] **Flash Loan Origin Assumption:** Have you assumed flash loans only execute once? A nested flash loan (flashloaning from pool A, calling pool B, which flashloans from pool A again) can break internal state snapshots if not carefully written.
- [ ] **E-Mode Correlation Failure:** E-Mode groups highly correlated assets (e.g., wstETH and ETH) with up to 97% LTV. If you build a protocol on top of Aave E-Mode, are you prepared for the de-peg risk? A 3% oracle de-peg results in instant liquidation.
- [ ] **Interest Rate Explosion:** Borrowing math can theoretically result in a geometric explosion of debt if `variableBorrowIndex` behaves unexpectedly due to artificial 100% utilization.
- [ ] **A-Token Rebase Hooks:** A-Tokens actively increase in balance. If your protocol rigidly caches balances via a single reading and later tries to move the full cached amount, rounding errors or dust will trap the yield. Always use `type(uint256).max` to clear A-Token balances.
- [ ] **Liquidation MEV Profiling:** Aave V3 liquidators operate in highly competitive mempool environments. Does your integration inadvertently restrict who can liquidate, potentially leading to bad debt accumulation if the single liquidator is DOS'd?

---

## 3. Lido Playbook

**Architecture TL;DR:** Liquid staking derivatives, `stETH` (rebasing), `wstETH` (wrapped, value-accruing), off-chain node operator registries.

### Security Checklist for Lido Integrations:
- [ ] **stETH vs wstETH Mismatch:** `stETH` is a *rebasing* token (1 stETH = 1 ETH constantly, but your `balanceOf(stETH)` goes up daily). Integrating `stETH` into a constant-product AMM or a rigid vault breaks accounting. You *must* use `wstETH` for integration, which is a standard ERC20 where the balance stays static but the underlying exchange rate climbs.
- [ ] **1-2 Wei Corner Cases:** Lido's internal share-to-amount math (`getPooledEthByShares`) suffers from inherent 1-2 wei rounding errors during conversions. If your protocol requires exact 1:1 mathematical equivalence (e.g., `deposit(amount) -> withdraw(exact_amount)`), the tx will revert. Always leave a variance buffer (`dust`).
- [ ] **Exchange Rate Oracle:** Does your protocol price `wstETH` exactly as `stETH`? No. You must invoke `wstETH.getStETHByWstETH(1 ether)` or use Chainlink's dedicated `wstETH/USD` feed.
- [ ] **Withdrawal Queue Locking:** Ethereum Shanghai enabled withdrawals, meaning `stETH` can be burned for `ETH` via Lido's WithdrawalQueue. These withdrawals take days. If your protocol requires instant liquidity, you must swap via Curve instead of using the official burn endpoint.

---

## 4. ERC4626 Tokenized Vaults Playbook

**Architecture TL;DR:** Yield-bearing vault standard utilizing an asset/share relationship.

### Security Checklist for ERC4626 Integrations:
- [ ] **First-Deposit Inflation (Inflation Attack):** An attacker deposits 1 wei to get 1 share. They then manually transfer (donate) 1,000,000 Tokens (100k USD) to the vault. The vault now has 1,000,000 Tokens backing 1 Share. The next legitimate user deposits 500,000 Tokens. Due to standard integer rounding (`500k * 1 / 1M = 0.5 -> 0 shares`), the new user receives ZERO shares, and their 500k deposit is absorbed into the value of the attacker's 1 share.
    - *Fix:* Check if the vault implements "Virtual Shares" (OpenZeppelin >v4.9) or mints initial dead shares to address `0x000...000`.
- [ ] **totalAssets() Manipulation:** Is `totalAssets()` calculated using purely `ERC20.balanceOf(address(this))`? If so, anyone can inflate the share price by sending tokens directly to the vault.
- [ ] **Slippage on redeem / withdraw:** The standard does not natively enforce min-out slippage checks for withdraws. Depending on strategy yield generation, `previewRedeem()` may differ drastically from reality if fees slash the position.

---

## 5. LayerZero V2 Playbook

**Architecture TL;DR:** OApp, DVNs (Decentralized Verifier Networks), Executors, specific message payloads.

### Security Checklist for LayerZero V2:
- [ ] **Trusted DVN Configuration:** Have you overridden the default config? If using default settings, LayerZero labs controls the DVN. You must securely select independent DVNs.
- [ ] **Payload Ordering (`compose` vs `lzReceive`):** Does your logic assume ordered execution across multiple chains? LayerZero messaging is asynchronous and payloads can fail or be stalled by lack of executor gas. Do you have a manual retry mechanism?
- [ ] **Gas Grieving:** Ensure you enforce a strict minimum `gasLimit` on the destination chain execution wrapper so an attacker cannot grief the target chain processor by executing with perfectly tuned insufficient gas, trapping the payload in the `retryPayload` queue permanently.
