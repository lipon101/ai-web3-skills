# Rust Protocol-Type Threat Profiles

Use this file at Stage 1 (to classify the protocol) and at Stage 2 (each angle reads the matching profile to know what to look for).

This is a **threat-identification** library — not a prose template for the final report. The Stage 1 hot-zones and Stage 2 candidate findings reference it. It mirrors X-Ray's `threats.md` but covers Rust ecosystems.

## Protocol classification (Stage 1)

Detect protocol type from function signatures, state types, and architectural patterns found during Stage 1 source reading. A protocol may match **multiple types** (hybrid). Rank by signal density — the type with the most matches is primary.

| Type | Detection signals (Rust) |
|------|--------------------------|
| **Lending / Borrowing (Rust DeFi)** | `borrow`, `repay`, `liquidate`, `liquidation_bonus`, `health_factor`, `collateral_factor`, `ltv`, `debt_*`, `interest_rate`, collateral-ratio math, `Reserve` / `Obligation` (Solend pattern), `Position` with debt + collateral fields |
| **DEX / AMM** | `swap`, `add_liquidity`, `remove_liquidity`, constant-product math (`x_y_k`), stable-swap invariant, `tick`, LP token mint/burn, `fee_tier`, `get_amount_out`, `Pool::reserves`, `OrcaWhirlpool`/`Raydium`/`Astroport`/`Osmosis`-style modules |
| **Yield / Vault** | ERC-4626-equivalent (`deposit`/`withdraw`/`shares`/`assets` ratio), strategy pattern (deposit into external protocol + `harvest`), `total_assets()`, `auto_compound`, `Strategy` trait |
| **Stablecoin / Collateralized Mint** | peg mechanism, `collateral_ratio`, `stability_fee`, `debt_ceiling`, `redemption`, peg-stability module, `anchor`/`peg`/`target` price references |
| **Derivatives / Perps** | `open_position`, `close_position`, `increase_size`, `funding_rate`, `margin`, `leverage`, PnL calc, `mark_price` vs `index_price`, `Position` struct with size/collateral/entry |
| **Liquid Staking** | `stake` + derivative token mint, `unstake`/`request_withdrawal`, exchange rate, validator set, withdrawal queue, rebasing or share-based derivative |
| **Bridge / IBC / Cross-chain** | cross-chain message passing, `lock`/`unlock` or `burn`/`mint` pattern, relayer/validator set, message nonce, chain-id check, merkle / light-client proof verification, IBC `IbcChannel`, Wormhole / LayerZero adapter |
| **Governance** | `propose`, `vote`, `execute`, `queue`, quorum, voting-power snapshots, timelock, delegation, `proposal_threshold`, Substrate `pallet-democracy` / `pallet-collective` |
| **NFT marketplace / royalties** | mint, list, buy, royalty-recipient, `Metaplex`/`cw721`/`pallet-uniques` patterns, on-chain or off-chain metadata, royalty enforcement |
| **Solana program (generic)** | `#[program]` mod, `#[derive(Accounts)]`, `Account<'info, T>`, `Signer<'info>`, `system_program::transfer`, SPL Token CPI |
| **CosmWasm contract (generic)** | `#[entry_point]`, `instantiate`/`execute`/`query`/`migrate`/`reply`/`sudo`, `cosmwasm_std::*`, `cw_storage_plus::*`, `info.sender`, `MessageInfo` |
| **Substrate pallet (generic)** | `#[frame_support::pallet]`, `#[pallet::call]`, `#[pallet::storage]`, `#[pallet::hooks]`, `Config` trait, `Origin`, `frame_system`, `dispatch::DispatchResult` |
| **Generic Rust service / SDK** | `pub trait`, async fns, `tokio` / `async-std`, `axum` / `actix` / `tonic` handlers, `serde` JSON / Borsh boundaries, FFI exports |
| **ZK Prover / Verifier (Rust)** | `prover/`, `verifier/`, `circuit/`, `air/`, `constraints/`, `recursion/` directories; `prove`/`verify` fns, `Air` / `MachineAir` / `Chip` traits (Plonky3, Plonk), Plonky3/SP1/Risc0/Halo2/snarkjs/gnark FFI shims, `vk` / `verifying_key` / `vkey_hash` params, `BN254` / `Bn254` / `Groth16` / `Plonk` / `Blake3` / `Poseidon` helpers, `eval()` constraint blocks, `pack` / `split` / `commit` state-mutation, `public_values` deserialization, opcode-cost tables |

### Hybrid classification

Most non-trivial protocols combine types. When multiple types match:
1. Rank by signal count — more matches = higher weight.
2. The **primary type** determines adversary ranking order.
3. **Secondary types** add their unique threats (de-duplicating overlapping ones).
4. State the classification: `Protocol classified as: [Primary] with [Secondary] characteristics.`

Example: an Anchor program with `swap`, `add_liquidity`, `borrow`, `liquidate` → Primary: DEX/AMM, Secondary: Lending/Borrowing.

## Threat profiles by protocol type

Each profile contains: **primary adversaries** (ranked), **dominant attack patterns**, **critical invariants**, and **what to look for first**. Use this in Stage 2 to weight angles toward the right surfaces.

### Lending / Borrowing (Rust DeFi)

**Primary adversaries** (ranked):
1. **Flash-loan attacker** — borrows unlimited capital in a single tx (Solend / Mango / Mars), manipulates oracle, drains borrow capacity.
2. **Oracle manipulator** — manipulates Pyth / Switchboard / Band / on-chain TWAP price feeds. Oracle is single source of truth for solvency.
3. **Liquidation MEV searcher** — front-runs / back-runs liquidations on Solana via Jito bundles, on Cosmos via priority gas. If MEV makes liquidation unprofitable, bad debt accrues.
4. **First-depositor (share-based pools)** — vault inflation attack on supply / debt token shares.
5. **Compromised admin / DAO** — can change `collateral_factor`, oracle program ID, interest model, pause liquidations.

**Dominant attack patterns**:
- Oracle manipulation → inflated collateral → max borrow → drain pool.
- Flash-loan borrow → manipulate spot price → liquidate victim at wrong price → profit from liquidation bonus.
- Bad-debt accumulation through unliquidatable positions (oracle lag, CU price spikes, illiquid collateral).
- Interest-rate manipulation via large deposit/withdraw cycles to move utilization.
- `collateral_factor` misconfiguration allowing undercollateralized borrowing.

**Critical invariants**:
- `total_borrows ≤ total_collateral * ltv` always, every market, every account.
- Every position is liquidatable before bad-debt threshold.
- Liquidation must be profitable for liquidators (otherwise silent bad-debt accrues).
- Oracle price reflects fair value within deviation + freshness bounds.
- Interest accrual is monotonic.

**What to look for first**:
1. Complete price calculation path: oracle read → normalization → collateral value → health factor. Every step is a manipulation point.
2. Can a single tx borrow + manipulate price + liquidate? If yes, flash-loan attack viable.
3. Liquidation math: bonus sufficient to cover CU + slippage? What if collateral is illiquid?
4. Share-price calculation: what at `total_supply == 0`?
5. What can admin change instantly vs. via timelock?

---

### DEX / AMM

**Primary adversaries**:
1. **MEV / sandwich attacker** — Jito bundles on Solana, MEV-share-equivalents on Cosmos / Substrate.
2. **Flash-loan price manipulator**.
3. **Malicious first LP / empty-pool attacker** — concentrated-liquidity tick manipulation, donation-before-first-deposit share inflation.
4. **Liquidity-manipulation attacker** — strategic add/remove to extract from other LPs.
5. **Compromised admin** — fee changes, pause, route whitelisting.

**Dominant attack patterns**:
- Sandwich: front-run swap → victim swaps at worse price → back-run.
- LP-share inflation on empty pools.
- Token callback re-entry on transfer hooks (SPL Token-2022 transfer hooks, CW20 send hooks).
- Price-oracle exploitation: external protocols read AMM spot, attacker manipulates pool in same tx.
- Concentrated-liquidity tick manipulation.
- Fee-on-transfer / Token-2022 transfer-fee accounting errors.

**Critical invariants**:
- Pool invariant holds before and after every operation (`x*y=k` or curve-specific).
- LP-share value monotonically non-decreasing from fees.
- No tokens extractable without proportional LP burn or valid swap math.
- Reserves in state == actual token balance (no donation-attack surface).

**What to look for first**:
1. Swap math: invariant correctly maintained? Rounding consistently favors one direction?
2. LP mint/burn: what at `total_supply == 0`? Minimum-liquidity enforcement?
3. Does pool expose `get_price` / oracle? External blast radius if manipulated.
4. Slippage protection: enforced where? Bypassable?
5. Re-entry guards: state updates before token transfers (CEI / equivalent)?

---

### Yield / Vault

**Primary adversaries**:
1. **Share-inflation attacker (first depositor)** — canonical vault inflation attack.
2. **Malicious / compromised strategy** — strategies hold the actual funds.
3. **Re-entry through external-protocol callbacks** — vault deposits into external protocol that has callbacks.
4. **Donation / direct-transfer attacker** — sends tokens directly to vault to manipulate `total_assets`.
5. **Compromised admin** — adds malicious strategies, changes allocation, sets harvester.

**Dominant attack patterns**:
- Inflation: `deposit(1)` → `donate(large)` → next depositor rounds to 0 shares → redeem all.
- Strategy reports fake gain → inflated share price → attacker deposits → strategy reports real value → previous depositors diluted.
- Strategy retains token approval / SPL delegate authority post-migration.
- Harvest sandwich: front-run `harvest()` with deposit (cheap shares), back-run with withdraw (higher share price).
- Vault accounting desync: strategy real balance differs from vault recorded allocation due to external rebasing / slashing / reward accrual.

**Critical invariants**:
- `total_assets()` accurately reflects underlying value.
- `convert_to_shares(convert_to_assets(s)) ≤ s` and reverse.
- Strategy cannot extract more than allocated.
- Share price can only increase from yield, never from manipulation.

**What to look for first**:
1. Share-price calc: virtual offset / minimum deposit to prevent inflation?
2. Strategy interface: arbitrary gain/loss reportable? Who adds/removes strategies?
3. `total_assets()` reads program-account balance or internal accounting? Donation possible if balance.
4. Re-entry protection on deposit/withdraw paths.
5. Strategy migration: old strategy loses approvals? Cooldown?

---

### Stablecoin / Collateralized Mint

**Primary adversaries**:
1. **Oracle manipulator** — collateral price up → mint at inflated value; down → unfair liquidations.
2. **Economic / governance attacker** — gain governance to change collateral params.
3. **Bank-run attacker** — strategic redemption drains best collateral.
4. **Flash-loan minter** — flash-loans, mints, manipulates collateral, profits.
5. **Compromised admin** — change collateral types, oracle, debt ceiling, pause.

**Dominant attack patterns**:
- Collateral manipulation → mint at inflated value → sell stablecoins → undercollateralization.
- Algorithmic death spiral: sell pressure → depeg → collateral drops → more liquidations → more sell pressure.
- Redemption DOS to drain liquid collateral.
- Governance attack to lower collateral ratio.
- Oracle staleness exploit: mint at stale (high) price, redeem at real (low) price.

**Critical invariants**:
- Every stablecoin unit ≥ 1:1 collateral value (or ≥ configured ratio).
- Mint and redeem are inverse operations.
- Peg mechanism is convergent under sell pressure.
- Liquidation can always restore individual position collateralization.
- `total_supply ≤ total_debt_ceiling` across all collateral types.

**What to look for first**:
1. Mint path: collateral → valuation (oracle) → ratio. Ratio changeable?
2. Redemption: priority queue under stress? What happens at full simultaneous redemption?
3. Liquidation: profitable? What if collateral drops faster than liquidations execute?
4. What does governance change? How quickly?
5. Death-spiral analysis: 10% depeg — does mechanism push back or amplify?

---

### ZK Prover / Verifier (Rust) (NEW v0.1.12)

**Driving signal**: SP1 / Succinct Code4rena 2026-04 contest. Argus's v0.1.10 run on this contest scored 0% direct recall and 17% adjacent recall on 5 in-scope C4 Mediums. Lessons informed this profile.

**Primary adversaries** (ranked):

1. **Untrusted-input crafter** — submits malformed proofs, truncated public_values, malformed deferred-events bytes; targets panic / livelock / decoded-into-unintended-shape paths.
2. **vk-root manipulator** — supplies an unsanctioned verifying key (or vk-hash, or sub-circuit-vk binding) that the verifier accepts. The proof verifies under the malicious vk; the protocol's trust contract is bypassed.
3. **State-corrupter via packing** — exploits `split` / `pack` / `flatten` / `partition` functions on degenerate options (zero, empty, max), forcing nonce-clobber, page-prot replay, page-walk-cache desync.
4. **Cost / weight oracle** — exploits opcode-cost-table mismatches (`StoreDouble` charged at `StoreWord` rate); inflates weight budget; underpays for protocol's actual work.
5. **Dead-code-path-ghost** — claims a "fallback" branch active when the call chain has an early-return that makes the branch unreachable. (Distinct from a real bug — Argus's wrong-direction risk class.)
6. **Compromised admin / DAO** — verifying-key swap mid-flight; vk_root ceremony parameters changed; trusted-setup parameters from the wrong ceremony.

**Dominant attack patterns**:

- **vk_root binding bypass**: `verify_groth16_bn254(proof, public_values, vkey_hash)` and `verify_plonk_bn254` accept proofs without binding `vk_root` to the caller's expected program-vkey. (SP1 M-01 pattern.)
- **Truncated-bytes panic in `verify_public_values`**: deserialization of `public_values` from `&[u8]` panics on truncated input — public API entry, no length-check before slice access. (SP1 M-02 pattern.)
- **Degenerate-options livelock in `split`**: `record.split(&SplitOpts { ..::default() })` with zero options reaches infinite-loop state. Reachable from public API. (SP1 M-03 pattern.)
- **Verifier panics on malformed input** (in addition to truncation): out-of-range field elements, invalid Borsh tags, mismatched buffer lengths, etc. (SP1 M-04 pattern.)
- **Dual-hash-fallback dead code**: a `Blake3` (or other) hash branch documented as a fallback but unreachable because callers early-return on `vkey.is_groth16/plonk()`. (SP1 M-05 pattern — Argus's F-05 misread this in reverse direction.)
- **Pack-clobber-in-deferred-events**: when packing deferred page-prot / register events into the public-input commitment, proof nonce is clobbered or two events alias. (SP1 M-06 pattern.)
- **Opcode-cost-table mismatch**: `StoreDouble` instruction billed at `StoreWord` cost rate; under-charging for actual protocol work. (SP1 QA pattern.)

**Critical invariants**:

- `verify(proof, pub_inputs, vk_hash) → ok` IMPLIES `vk_hash == known_root_for_program`.
- Every `pub fn` accepting a byte-slice from untrusted source has length-checked access (no panic / no infinite loop) on EVERY input shape.
- `record.split(opts)` is total: every (non-default) `SplitOpts` value produces a finite split or returns Err.
- If a hash-algorithm fallback is documented as supported, the call chain to it must NOT have an early-return blocking it.
- `pack(events)` produces a unique commitment with no nonce-collision across legitimate event vectors.
- Cost tables are total: every reachable opcode has its own cost row; no opcode silently uses a sibling opcode's cost.

**What to look for first**:

1. Open the `verify*.rs` files in `prover/`/`verifier/` and trace EVERY public-entry verifier function. For each, find the call to internal `verify_*` helpers; check whether vk-binding occurs at the entry or only inside.
2. Open EVERY `pub fn` that accepts `&[u8]` / `Vec<u8>` / Borsh-decoded structs. Check first-line length validation. For the deserialization failure path, follow the panic — is it a `?` propagation or a panic / unwrap?
3. Open EVERY `split` / `pack` / `partition` / `flatten` function in `record/` / `state/` / `program/`. Test mentally: zero options? max options? identical options? out-of-range options?
4. Open the cost / opcode tables. For every opcode the project supports, verify its cost is its own (not sibling-opcode-derived).
5. Read every documented "fallback" or "alternative" hash / verification algorithm path. For each, trace the call chain UP — is there an early-return in any caller blocking it?

**Hot-zone bias warning**: ZK projects tempt the auditor to focus on `Air::eval()` constraint blocks and AIR `WIDTH` / `column` definitions. The SP1 contest taught us that real bugs lived in **imperative non-AIR Rust** (`verify.rs`, `record.rs::split`, `cost.rs`, `pack`/`commit` paths). Stage 1 hot-zone ranking for ZK projects MUST include imperative state-mutation and untrusted-byte-decode paths even when those files don't have AIR `eval()` blocks.

---

### Derivatives / Perps

**Primary adversaries**:
1. **Oracle manipulator** — leverage amplifies oracle errors.
2. **Liquidation MEV searcher**.
3. **Funding-rate manipulator**.
4. **Position-size attacker** — opens positions exceeding protocol payout capacity.
5. **Compromised admin** — change max leverage, funding params, oracle, pause liquidations.

**Dominant attack patterns**:
- Oracle manipulation → cascade liquidations → profit.
- Funding-rate manipulation via concentrated one-sided OI.
- Position size exceeding payout capacity.
- Stale oracle → risk-free directional bet.
- Cross-margin exploit: loss in one position liquidates another.
- ADL manipulation.

**Critical invariants**:
- `sum(PnL) == 0` (zero-sum minus fees).
- Available liquidity ≥ max payout under worst-case price movement.
- Liquidation triggers before bad debt.
- Funding rate converges OI imbalance.
- Mark price can't deviate from index beyond bounds.

**What to look for first**:
1. PnL calc: correct under all conditions including leverage limits?
2. Liquidation threshold vs. insolvency: enough margin?
3. Mark vs. index price: how computed? Manipulable in a block?
4. Max OI / position-size limits enforced?
5. Funding rate: cap? Manipulable?

---

### Liquid Staking

**Primary adversaries**:
1. **Exchange-rate manipulator** — derivative token's value depends on rate.
2. **Validator-set attacker** — compromise validators the protocol delegates to.
3. **Withdrawal-queue attacker** — front-run pending unstakes / loss events.
4. **Oracle / rate arbitrageur** — exploits lag between on-chain rate and real underlying.
5. **Compromised admin** — change validator set, fee, oracle, withdrawal mech.

**Dominant attack patterns**:
- Reward / slashing reporting manipulation.
- Withdrawal-queue griefing.
- Rebasing-token integration bugs in protocols using the derivative as collateral.
- Validator collusion withholding rewards / MEV.
- Share-price manipulation via direct transfer.

**Critical invariants**:
- Exchange rate reflects true underlying value.
- `total_derivative_supply * exchange_rate ≤ total_underlying_staked`.
- Withdrawal queue processes fairly.
- Validator performance doesn't disadvantage stakers.
- Slashing reflected in rate before any user can exit at stale rate.

**What to look for first**:
1. Exchange-rate calc: who reports rewards/slashing? How often? Manipulable?
2. Withdrawal: queue? Delay? Griefing surface?
3. Validator selection: who chooses?
4. Derivative rebases or shares? Integrating protocols handle correctly?
5. Massive slashing: loss socialized fairly?

---

### Bridge / IBC / Cross-chain

**Primary adversaries**:
1. **Validator / relayer set attacker** — #1 bridge exploit by total value lost.
2. **Message-replay attacker** — replay valid message on different chain or multiple times.
3. **Race-condition exploiter** — finality gaps between source and destination.
4. **Fake-message crafter** — passes validation but contains malicious data.
5. **Compromised admin** — change validator set, pause, upgrade contracts to drain.

**Dominant attack patterns**:
- Validator-key compromise → forge messages → mint unbacked tokens on destination.
- Replay (missing nonce or nonce-overflow).
- Proof verification bypass (merkle / light-client edge case).
- Chain-ID confusion.
- Reorg exploitation: source-chain reverted but destination already minted.

**Critical invariants**:
- Locked source = minted destination (1:1).
- Every message processed exactly once.
- Message can't be forged without validator-threshold consensus.
- Bridge accounting consistent across chains (no cross-chain double-spend).

**What to look for first**:
1. Validator/relayer trust: count? Threshold? Changeable?
2. Replay protection: nonce checked? Overflow possible?
3. Proof verification: merkle / signature edge cases?
4. Finality assumptions: waits for source finality?
5. Admin powers: drain locked? Change validators instantly?

---

### Governance

**Primary adversaries**:
1. **Flash-loan governance attacker** — borrow tokens, vote, return — only if voting power = current block.
2. **Governance-capture attacker** — slow accumulation of voting power.
3. **Proposal-spam / griefing**.
4. **Timelock-exploitation attacker** — position before queued proposal executes.
5. **Compromised admin / guardian**.

**Dominant attack patterns**:
- Flash-loan vote-and-return.
- Bribe attacks (Votium-equivalent).
- Proposal obfuscation (malicious calldata in benign-looking proposal).
- Timelock front-run.
- Guardian abuse.

**Critical invariants**:
- Voting power snapshotted at proposal creation, not vote time.
- Quorum prevents minority capture.
- Timelock provides exit window.
- No single role bypasses governance.
- Proposal calldata matches description (verifiable).

**What to look for first**:
1. Voting power: snapshot or current balance? If current, flash-loan attack trivial.
2. Quorum + threshold high enough to prevent capture?
3. Timelock nonzero + sufficient for users to react?
4. What does governance control? Enumerate every parameter / action.
5. Emergency powers: who has them? What can they do?

---

## Temporal threat dimension

DeFi-on-Rust protocols have a lifecycle. Different threats dominate at different phases. Detect which phases are relevant from code signals; include applicable phases in Stage 1's hot-zones output.

| Phase | Include when |
|-------|--------------|
| **Deployment & Initialization** | Always — every protocol has it |
| **Steady State** | Always — baseline |
| **Market Stress** | Oracle integration, liquidation logic, collateral/debt tracking, any price-dependent calc |
| **Governance / Upgrade** | Timelock, governance contract, Anchor `program_upgrade_authority`, Substrate `set_code`, CosmWasm `migrate`, proxy pattern |
| **Deprecation / Wind-down** | V2/migration in module names or comments, `migrate` function, deprecated module references, multi-version architecture |
| **Chain Reorg Window** (NEW v0.1.10) | Always — every chain has reorgs. Specific signals: bridge programs, light-client verification, cross-chain message handlers, finality wait counts, validator-set change paths, "confirmations >= N" code |

### Deployment & Initialization

Most dangerous 24-48 hours.

**Threats**:
- **Initialization front-running**: attacker watches mempool for `initialize` / `instantiate` / `init` and front-runs with malicious params.
- **Parameter misconfiguration**: deployed with testing params (zero timelock, test oracle addresses).
- **Authority not transferred**: deployer EOA / single key still owns; intended multisig hasn't taken over.
- **Empty-state exploitation**: protocols behave differently when empty (first-depositor inflation, initial-price setting).
- **Deployment ordering**: programs deployed in wrong order, missing CPI authorities, circular dependencies, proxy pointing at wrong implementation.

**What to look for**:
- Anchor `init` / `init_if_needed` constraint missing on a function intended one-shot.
- CosmWasm `instantiate` parameters without validation (zero, default, max).
- Substrate `Config::initialize` callable without `ensure_root`.
- Constructor-style code paths still callable post-deployment (look for "init" + no permission gate).
- Hardcoded constants that look like test values (zero delays, max-uint fees, known test addresses).

### Market Stress

**Threats**:
- **Oracle latency under volatility**: heartbeat windows mean prices can be stale during rapid moves.
- **Liquidation cascade**: liquidation dumps collateral on-market → price drops → more liquidations.
- **Liquidity evaporation**: LPs withdraw, liquidation bots can't swap, bad debt accumulates.
- **Correlated asset depeg**: hardcoded `1:1` assumptions break (USDC = $1, stETH = ETH).
- **CU / weight spikes**: critical operations become prohibitively expensive; keepers stop.
- **Withdrawal stampede**: limited liquid reserves → early withdrawers drain, late ones stuck.

**What to look for**:
- Pyth / Switchboard / Band staleness threshold appropriate for asset volatility?
- Liquidation profitability assumptions valid under thin liquidity?
- Hardcoded equivalences (1:1, decimal alignment) without depeg-aware oracle?
- Keeper-dependent flows: fallback if keeper fails?
- Withdrawal queue rate-limit?

### Governance / Upgrade

**Threats**:
- **Timelock-exploitation window**: queued proposal known publicly, attackers position before execution.
- **Upgrade storage collision**: Anchor account-layout change, CosmWasm migration breaking storage, Substrate runtime upgrade with incompatible storage.
- **Flash-loan governance**: trivial if voting power measured at current block.
- **Slow governance capture**: token accumulation over time.
- **Migration window**: V1→V2 transition has approval chains and partial-state exposure.

**What to look for**:
- Voting-power source: snapshot or current?
- Anchor `program_upgrade_authority`: who? Timelock? Multisig?
- Substrate `set_code` / `set_storage` paths: ensure-root? Timelock?
- CosmWasm `migrate`: schema changes? Migration validates old state → new state mapping?
- Governance-controlled params: enumerate; what can each break?

### Deprecation / Wind-down

**Threats**:
- **Residual funds in deprecated programs**: no monitoring, oracles go stale, exploitable paths become free-money.
- **Abandoned approval chains**: SPL delegate-authority still active, old CosmWasm `Allowance` still valid.
- **Dependent protocol breakage**: integrators don't know it's deprecated.
- **Frozen-state exploitation**: governance stops, params can't be updated, market changes.

**What to look for**:
- Multi-version architecture: old versions still accessible? Funds inside?
- `permit` / `approve` / SPL delegate without revocation mechanism?
- Protocol serves as oracle/data source for others — deprecation flag?
- What if no governance for 6 months — what breaks?

### Chain Reorg Window (NEW v0.1.10)

**Threats**:
- **Source-chain reorg invalidates relayed message**: bridge deposit observed by relayer at block N, source chain reorgs to remove block N, destination already credited → unbacked tokens (V60 / V91).
- **Finality assumption too short**: code waits for `K` confirmations where `K` is below the source chain's known reorg depth. Ethereum post-Merge: 12 min finality; Polygon: 32+ blocks; Solana: ~12.8 seconds for finalized commitment level. A bridge with `K=1` on Polygon is unsafe.
- **Validator-set change during reorg**: reorg crosses an epoch boundary; a deposit's signatures were valid for the pre-reorg validator set but the post-reorg view has a different set (V91).
- **Pending-withdrawal corruption**: reorg of own chain rolls back state writes the protocol assumed permanent (request queue popped pre-reorg, re-pushed post-reorg → double withdrawal).
- **Light-client header-chain confusion**: light-client pallet accepts a header proven valid on a fork that loses to canonical chain.

**What to look for**:
- Configured confirmation depth vs source chain's known reorg depth.
- Finality semantics: does the code wait for `Finalized` commitment (Solana) / `Justified` (Ethereum) / `K` blocks (PoW chains)?
- Reorg-detection paths: does the code subscribe to reorg events? What does it do when one fires?
- Validator-set rotation logic during cross-chain message verification.
- Withdrawal-queue / request-state mutations: are they idempotent across reorgs?

**Critical invariants**:
- Cross-chain credit (lock-source → mint-destination) only after source-chain finality.
- Validator-set version is bound to each cross-chain message; verification accepts ANY recently-active set within the rotation grace window.
- Own-chain state mutations either are reorg-safe (idempotent) or are deferred until reorg-window passes.

---

## Per-protocol-type Stage-1 attack-surface checklists (NEW v0.1.10)

Stage 1's `attack-surface.md` MUST inject these checklists into the hot-zones list when the protocol classifier identifies the type. Each checklist enumerates protocol-specific surfaces beyond the general adversaries above.

### Lending — additional surfaces
- Interest-rate model manipulation via flash-loan-borrowed price spike.
- Collateral-asset addition with `liquidation_threshold < 1/(1-liquidation_bonus_pct)` enabling self-liquidation profit (V94).
- `liquidate()` profitability under thin-liquidity conditions: does the bonus exceed cost on illiquid collateral?
- Reserve / treasury accounting: V96-style donate-and-redeem.

### DEX/AMM — additional surfaces
- Tick-spacing manipulation post pool creation (V89).
- Fee-on-transfer token interaction breaking `x * y = k` (V90).
- LP-share inflation on `total_supply == 0` (V17).
- Read-only reentrancy via `get_virtual_price` / `convert_to_assets` queried by integrators mid-update (V45).

### Bridge — additional surfaces
- Validator-set update race with finalized in-flight deposit (V91).
- Source-chain reorg depth vs configured confirmation count (Reorg Window phase).
- Storage-proof header verification (V76).
- Relayer signature replay across (source_chain_id, dest_chain_id, nonce) tuples (V20 / V60).

### Governance — additional surfaces
- Vote-delegate-vote same-block double-counting (V92).
- Quorum calculation including escrow-locked / vested tokens that can't actually vote.
- Flash-loan governance vote (V95) — voting power must snapshot strictly before proposal-creation block.
- Proposal calldata vs description mismatch (obfuscated malicious payload).

### Liquid Staking — additional surfaces
- Exchange-rate front-run during reward-claim (V93).
- Reward / slashing reporting frequency vs derivative-token mint/redeem cadence.
- Withdrawal queue griefing.

### Stablecoin — additional surfaces
- Algorithmic death-spiral simulation: 10% depeg test.
- Redemption priority queue under stress.
- Death-spiral re-entry path: each redemption increases `total_supply / total_collateral_value` ratio?

### Derivatives / Perps — additional surfaces
- Oracle-staleness × leverage amplification.
- ADL (auto-deleveraging) ordering manipulation.
- Funding-rate manipulation via concentrated one-sided OI.

## Composability threats

Layer 1 (direct dependency), Layer 2 (shared state), Layer 3 (temporal). Apply during Stage 2 to every external integration found in Stage 1's `attack-surface.md`.

### Layer 1 — Direct dependency

For every external call (CPI, IBC, cross-pallet `dispatch`, HTTP/gRPC), classify:
1. Target type (oracle, DEX, lending, yield, token, governance, bridge, other).
2. Assumptions about return value (correct price, exact amount, success, format).
3. Validation present (bounds check, staleness check, zero check, success check).
4. Mutability of external behavior (upgradeable? governed?).
5. Fallback on failure (revert, silent fail, fallback value, try-catch fail-open?).

#### Oracle dependency chain

Pyth / Switchboard / Band / Chainlink / on-chain TWAP. Look for:
- Aggregation method (median, TWAP, VWAP).
- Staleness check (`updated_at`, threshold appropriate for asset).
- Deviation check (price bounded against reference).
- Zero / negative check.
- Sequencer-uptime equivalent (on Solana: leader rotation; on rollups: sequencer feed).
- Fallback oracle if primary fails.
- Admin can change oracle program ID? Instantly or timelocked?

#### Yield-strategy dependency

Look for:
- External protocols strategies deposit into (Marinade, Kamino, Mars, Astroport, etc.).
- External protocol upgradeability + timelock.
- External pause-withdrawals path.
- Strategy emergency-withdrawal capability.
- Loss reporting + socialization.
- Migration: old strategy retains delegate / approval?
- Re-entry via external callbacks.

#### Token-behavior assumptions

Apply this assumption matrix for **every** token the protocol handles:

| Assumption | Standard | Violating | Impact if violated |
|------------|----------|-----------|--------------------|
| Transfer sends exact amount | SPL Token, CW20 | SPL Token-2022 transfer-fee, transfer-hook | Internal accounting > real balance, insolvency |
| Balance doesn't change without transfer | SPL Token, CW20 | rebasing tokens, interest-bearing | Accounting drift, share-price manipulation |
| Transfer always succeeds (or reverts) | SPL Token | CW20 with hooks that fail silently | Silent transfer failure, lost funds |
| No callback on transfer | SPL Token | SPL Token-2022 transfer hooks, CW20 `Send` hooks | Re-entry through transfer callback |
| Decimals known + fixed | most | non-standard (token-2022 with mint-extension changing decimals) | Math errors, massive over/under-valuation |
| Token can't block specific addresses | most | freeze authority on SPL Token, blocked accounts on pallet-assets | Withdrawal blocked, funds trapped |
| Token can't be paused | most | freeze authority on SPL Token, paused state on pallet-assets | All protocol ops blocked |
| Token program is immutable | SPL Token (canonical) | upgradeable wrapper / CosmWasm migrating CW20 | Behavior changes post-deployment |

What to look for:
- `balanceOf(before) - balanceOf(after)` pattern (handles transfer fees).
- SPL Token-2022 transfer-hook awareness.
- Decimals dynamic (`Mint::decimals`) or hardcoded?
- Rebasing handled?
- Token whitelist or arbitrary tokens allowed?

#### Callback re-entry

External calls can trigger callbacks that re-enter before state is finalized.

What to look for:
- State changes after external calls (violates CEI).
- Solana CPI callback: re-entrancy via target program calling back.
- CosmWasm submessage `reply` re-entering caller.
- SPL Token-2022 transfer hook invoking arbitrary program.
- CW20 `Send` hook → recipient executes → recipient calls back.
- Substrate `dispatch_as` re-entering pallet during nested dispatch.

### Layer 2 — Shared state

#### Liquidity coupling

Two protocols using the same pool. Large action in A moves price, affecting B in same block.

What to look for:
- Does protocol swap through public pools (Orca, Raydium, Astroport)? Which?
- Significant TVL relative to swap size?
- Could a large liquidation here move the pool enough to affect another protocol?

#### Oracle sharing

Multiple protocols using same feed. Market event triggers liquidations across all simultaneously.

What to look for:
- Which feeds does this protocol use?
- Same feeds as major lending / derivatives protocols?
- Could liquidations here create sell pressure affecting the oracle?

#### Approval / delegate-authority chain

Users grant SPL delegate authority / CW20 `Allowance` to protocol contracts.

What to look for:
- Unlimited approvals (`u64::MAX`)?
- Approvals scoped or broad?
- If protocol upgradeable, an upgrade could add a function draining approved tokens.
- Deprecated programs still hold user delegates?

### Layer 3 — Temporal composability

#### Governance-induced behavior change

External protocol changes a parameter this protocol depends on.

What to look for:
- Hardcoded assumptions about external parameter values?
- Read dynamically or hardcoded?
- Parameter change in external requires update here?

#### Upgrade-induced interface change

External protocol upgrades implementation. Signatures same, behavior different.

What to look for:
- External dependencies behind upgradeable proxies / `migrate`?
- Error handling assumes specific revert reasons that may change?
- CU / weight estimates hardcoded that may break with external upgrades?

#### Deprecation without notification

External protocol deprecates an oracle / pool / endpoint. Returns stale data silently or starts reverting.

What to look for:
- Freshness checks on all external data?
- try / catch / `Result::ok_or` fallback behavior — fail-open or fail-closed?
- Monitoring for external-dependency health?

#### Dependency-of-dependency upgrade

This → A → B. B upgrades. A's behavior changes. This protocol's behavior changes. No visibility.

What to look for:
- Map full dependency chain 2-3 levels deep.
- For each level: upgradeable? Governed? Behavior changeable without consent?
- Flag chains deeper than 2 levels.
