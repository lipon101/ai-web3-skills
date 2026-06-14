# Systematic Attack Trees

This reference file contains deep, systematic decision paths (attack trees) to navigate vulnerability hunting across specific protocol types. By mapping these trees against target logic, you can systematically close the audit space.

---

## 1. Lending Protocols Attack Tree

Navigating the attack vector landscape of collateralized debt positions (CDPs) and isolated lending pools.

**[ROOT] GOAL: Extract Value from Lending Markets**
├── **[BRANCH A] Oracle Manipulation**
│   ├── [Leaf] Manipulate Spot Price via Flash Loan (e.g., Uniswap V2 reserve imbalance)
│   │   └── *Condition:* Protocol uses `getReserves()` instead of TWAP.
│   ├── [Leaf] Trigger Stale Price Disconnect (e.g., Sequencer downtime)
│   │   └── *Condition:* Protocol bypasses Chainlink latestRoundData `updatedAt` checks.
│   └── [Leaf] Exploit Oracle Precision
│       └── *Condition:* Decimals mismatch between USD oracle (8d) and Token oracle (18d).
├── **[BRANCH B] Liquidation Exploits**
│   ├── [Leaf] Front-run Liquidation
│   │   └── *Condition:* Liquidator can see mempool Tx and use higher gas to snipe bounty.
│   ├── [Leaf] Bad Debt Accumulation / Death Spiral
│   │   └── *Condition:* Liquidation incentive is lower than gas cost on high-throughput chains.
│   ├── [Leaf] Self-Liquidation Arbitrage (Euler style)
│   │   └── *Condition:* Attacker can intentionally diminish their own health factor via un-checked collat removal.
│   └── [Leaf] Liquidation Pause DOS
│       └── *Condition:* Reverting callback in ERC777/ERC721 transferred to the liquidator target blocks liquidation loop.
├── **[BRANCH C] Accounting / Invariant Manipulation**
│   ├── [Leaf] Vault Inflation Attack / First-Depositor Sniping
│   │   └── *Condition:* ERC4626 standard utilizes initial 1 wei deposit; attacker front-runs and donates 1000 ETH to snap share exchange rate.
│   ├── [Leaf] Precision Loss / Rounding Errors
│   │   └── *Condition:* Interest accrual uses `mulDivDown` instead of `mulDivUp` for debt.
│   ├── [Leaf] Reentrancy on Withdrawal
│   │   └── *Condition:* Token has `beforeTokenTransfer` hook; contract updates state after the hook execution.
│   └── [Leaf] Interest Rate Model Exploit
│       └── *Condition:* Kink curves allow massive localized borrowing to break APY math.

---

## 2. DEX / AMM Protocol Attack Tree

Navigating vulnerabilities in constant-product market makers (CPMMs) and concentrated liquidity pools.

**[ROOT] GOAL: Extract LP Funds or Drain Swaps**
├── **[BRANCH A] Pricing Math Exploits**
│   ├── [Leaf] K-Value Invariant Violation
│   │   └── *Condition:* Custom math library allows `reserve0 * reserve1` to decrease after a swap.
│   ├── [Leaf] Concentration Tick Manipulation
│   │   └── *Condition:* Uniswap V3 custom oracle rounding allows tick mapping exhaustion.
│   └── [Leaf] Fee Calculation Rounding
│       └── *Condition:* Zero-fee loop on micro-swaps extracts protocol liquidity token-by-token.
├── **[BRANCH B] Toxic Token Pairings**
│   ├── [Leaf] Fee-On-Transfer Imbalance
│   │   └── *Condition:* AMM tracks `balanceOf` instead of `amountReceived`; swap credits the pre-fee amount.
│   ├── [Leaf] Rebasing Token Drain
│   │   └── *Condition:* AMM doesn't call `sync()` internally when internal balances deflate/rebase.
│   └── [Leaf] ERC777 Reentrancy
│       └── *Condition:* Pair contract updates reserves after triggering sender's fallback.
├── **[BRANCH C] MEV & Arbitrage**
│   ├── [Leaf] Just-in-Time (JIT) Liquidity Provisioning
│   │   └── *Condition:* LP observes large pending swap, mints LP to intercept fees, then withdraws instantly.
│   └── [Leaf] Uncapped Slippage (Sandwich Attack)
│       └── *Condition:* `amountOutMinimum` or `deadline` checks are zeroed or hardcoded to block.timestamp.

---

## 3. Bridge / Cross-Chain Protocol Attack Tree

Navigating the attack space of wrapped token minting and cross-chain messaging.

**[ROOT] GOAL: Mint Unbacked Assets or Drain Escrow Vault**
├── **[BRANCH A] Cryptographic Verification Flaws**
│   ├── [Leaf] Hash Collisions / Replay Attacks
│   │   └── *Condition:* Nonces or ChainIDs are missing from the signed message hash payload.
│   ├── [Leaf] Forged Merkle Proofs
│   │   └── *Condition:* Uninitialized root hash allows empty bytes32 verification.
│   └── [Leaf] Signature Spoofing / Malleability
│       └── *Condition:* Protocol uses `ecrecover` directly and doesn't check for S-value malleability.
├── **[BRANCH B] Validator Compromise**
│   ├── [Leaf] Single-Point-of-Failure Storage
│   │   └── *Condition:* Keeper private keys stored in hot wallets or plaintext centralized environments.
│   └── [Leaf] Unsafe Administrative Upgrades
│       └── *Condition:* 1-of-1 multisig can upgrade the bridge implementation contract without a timelock.
├── **[BRANCH C] Interchain Message Decoupling**
│   ├── [Leaf] Phantom Mints
│   │   └── *Condition:* Contract allows `deposit()` without locking the corresponding target chain collateral.
│   └── [Leaf] Decimal Mismatch Extraction
│       └── *Condition:* Bridging from 18 decimal chain to 6 decimal chain truncates 12 zeroes maliciously.

---

## 4. Yield Aggregator / Vault Attack Tree

**[ROOT] GOAL: Steal Yield or Dilute Existing Users**
├── **[BRANCH A] Share Math Vulnerabilities**
│   ├── [Leaf] ERC4626 Inflation (Donation Attack)
│   │   └── *Condition:* Empty vault mints 1 share, attacker donates huge sum directly to vault, subsequent depositors get zero shares due to integer truncation.
│   └── [Leaf] Share Price Manipulation via External Oracles
│       └── *Condition:* Vault asset pricing relies on spot DEX balance rather than total assets locked in strategy.
├── **[BRANCH B] Strategy Flaws**
│   ├── [Leaf] Reward Token Sniping
│   │   └── *Condition:* Reward distribution lacks a time-weighted mechanism; user deposits right before harvest, takes rewards, and leaves.
│   └── [Leaf] Flash Loan Dilution
│       └── *Condition:* Vault updates yield checkpoints synchronously in the same block as deposits.
