# Contract Classification Rubric

## Goal

Assign one or more protocol labels to each contract based on behavior, state, and interactions.

Allowed labels:

- `DEX`
- `Lending`
- `Staking`
- `Bridge`
- `Governance`
- `Oracle`
- `Vault`

If none is sufficiently supported, use `Generic`.

## Evidence Rules

- Base labels on functions, state variables, accounting flows, and direct dependencies.
- Contract name is supporting evidence only, never enough by itself.
- A contract may receive multiple labels.
- Prefer precision over recall; weak hints should lower confidence, not force a label.

## Label Signals

### DEX

Strong signals:

- swap, route, quote, pool, reserve, pair, liquidity management
- price path computation
- slippage or deadline handling
- reserve accounting or pool share logic

### Lending

Strong signals:

- collateral, debt, borrow, repay, liquidation, health factor
- utilization or interest rate model
- debt shares, borrow shares, insolvency logic

### Staking

Strong signals:

- stake, unstake, queue, cooldown, reward accrual
- share minting tied to deposited assets or voting power
- reward distribution over time

### Bridge

Strong signals:

- message verification, remote chain IDs, bridge proof handling
- mint/burn or lock/release across chains
- nonce, replay protection, rate limiting

### Governance

Strong signals:

- propose, vote, queue, execute, quorum, timelock
- delegated voting or checkpoint snapshots
- privileged execution via proposal flow

### Oracle

Strong signals:

- price feed reads or price aggregation
- freshness checks, heartbeat, decimals normalization
- price publication or external data ingestion

### Vault

Strong signals:

- asset/share conversion
- deposit, mint, withdraw, redeem semantics
- strategy accounting or ERC4626-like behavior

## Multi-Label Rules

- Keep all labels with meaningful evidence.
- If one label is primary and another is supporting, keep both.
- Use confidence to indicate strength, not to suppress valid multi-label cases.

Examples:

- `LendingPool` reading liquidation prices from a feed can be `Lending + Oracle`.
- `StakingVault` with deposit/redeem shares can be `Staking + Vault`.
- `BridgeGovernor` can be `Bridge + Governance`.

## Generic Fallback

Use `Generic` when the contract is core infrastructure but does not cleanly fit a protocol label, for example:

- access managers
- registries
- configuration holders
- helper routers
- treasury and fee collectors
- upgrade admins or proxy tooling

## Output Schema

Return JSON with:

- `contract_name`
- `labels`: array of `{label, confidence, evidence}`
- `fallback_label`
