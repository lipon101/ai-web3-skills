# Evolution Timelines

This document tracks the historical evolution of major smart contract vulnerability classes. Understanding *how* attacks evolved helps predict the *next* iteration of the exploit.

---

## 1. The Evolution of Reentrancy (2016 - Present)

*   **Gen 1: Single-Function Reentrancy (2016)**
    *   *The Dawn:* The DAO ($60M). A simple fallback function re-enters `withdraw()` before the balance state is updated.
    *   *The Defense:* Checks-Effects-Interactions (CEI) pattern introduced.
*   **Gen 2: Cross-Function Reentrancy (2018-2019)**
    *   *The Shift:* `withdraw()` is protected by CEI, but the attacker re-enters `transfer()` while the balance is temporarily inflated.
    *   *The Defense:* Introduction of the OpenZeppelin `ReentrancyGuard` (`nonReentrant` modifier) to create contract-wide mutex locks.
*   **Gen 3: Token Hook Reentrancy (2020-2021)**
    *   *The Catalyst:* ERC777 introduces `tokensReceived` hooks. 
    *   *The Exploit:* Uniswap V1/Lendf.Me. Protocols integrated ERC777 assuming standard ERC20 behavior (no external calls during `transferFrom`). The hook allowed bypassing the lock.
    *   *The Defense:* Blanket bans on ERC777 integration in DeFi; strict token whitelisting.
*   **Gen 4: Read-Only Reentrancy & Cross-Contract (2022-2023)**
    *   *The Paradigm Shift:* Attackers realize they don't need to mutate state during the reentrancy window—they only need to *read* inconsistent state from a third-party contract. Curve Finance/Vyper exploit.
    *   *The Defense:* Introducing independent view locks; calling `updateState()` before `getVirtualPrice()`.
*   **Gen 5: Transient Storage & Multi-Chain Callbacks (2024+)**
    *   *The Frontier:* EIP-1153 introduces transient storage (`TSTORE`/`TLOAD`), leading to custom, highly optimized reentrancy locks that reset per transaction. Emerging vectors involve bridging messages where the "callback" happens asynchronously on an L2 hours later, breaking standard mutex assumptions.

---

## 2. The Evolution of Oracle Manipulation

*   **Gen 1: Spot Price Math (2020)**
    *   *The Wild West:* Protocols read Uniswap V1/V2 reserve ratios directly (`reserveX / reserveY`). bZx and Harvest Finance are drained by flash loans skewing the ratio in a single transaction.
    *   *The Defense:* Move to Time-Weighted Average Prices (TWAPs).
*   **Gen 2: TWAP Manipulation (2021-2022)**
    *   *The Long Con:* TWAPs are harder to manipulate, but on low-liquidity Alt-L1 pairs, an attacker can push the price, wait out the TWAP window (or bribe miners for multi-block sequences), and then exploit.
    *   *The Defense:* Massive shift to Chainlink push-based decentralized oracle networks (DONs).
*   **Gen 3: Oracle Halts & Edge Cases (2022-2023)**
    *   *The Black Swan:* Chainlink is robust against manipulation, but protocols assume it *always* returns a valid price. During extreme volatility (LUNA crash), Chainlink hits hard-coded minimum circuit breakers, returning stale $0.10 prices for a $0.0001 asset. Venus Protocol is drained.
    *   *The Defense:* Enforcing strict `updatedAt` and bounds-checking (`minAnswer`/`maxAnswer`) on all `latestRoundData` calls.
*   **Gen 4: L2 Sequencer Awareness (2023+)**
    *   *The Rollup Era:* On L2s, if the sequencer goes offline, the oracle price instantly becomes stale. When the sequencer comes back online, a backlog of transactions executes against the stale price before the oracle can update.
    *   *The Defense:* Integration of the Chainlink L2 Sequencer Uptime Feed to block liquidations/borrowing if the sequencer was recently restarted.

---

## 3. The Evolution of Bridge Attacks

*   **Gen 1: Cryptographic Logic Flaws (2021)**
    *   *The Flaws:* Poly Network ($611M). Attackers find hash collisions or parameter un-packing bugs to forge valid cross-chain messages.
    *   *The Defense:* Hardening verification logic, moving to standardized messaging buses (LayerZero, Axelar).
*   **Gen 2: Centralized Validator Compromise (2022)**
    *   *The Pivot:* Smart contracts are secure, so attackers target operational security. Ronin ($625M) and Harmony ($100M). Social engineering and private key theft of multisig validators.
    *   *The Defense:* Increasing validator counts, eliminating single-entity control, enforcing hardware security modules (HSMs).
*   **Gen 3: Implementation Mismatches (2023+)**
    *   *The Subtlety:* Decimal mismatches (18e on ETH vs 6e on USDC), phantom deposits (emitting a deposit event without actually locking funds), and uninitialized proxies (Nomad).
    *   *The Defense:* Invariant monitoring bridging volume caps, and strict canonical token registries.
