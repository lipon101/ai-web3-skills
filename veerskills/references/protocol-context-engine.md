# VeerSkills Protocol Context Engine

_21 protocol-specific security context files derived from 10,600+ real audit findings. Each bug class has preconditions, detection heuristics, false positives, and historical exploits specific to the protocol type._

_Adapted from Forefy's PROTOCOL CONTEXT system._

---

## How to Use

During **Phase 2 (MAP)**, after detecting the protocol type:
1. Load the matching protocol context file below
2. For each bug class listed in the context file, extract:
   - **Preconditions**: Does this protocol have the conditions for this bug class?
   - **Detection Heuristics**: Exact grep patterns and code reading checks
   - **False Positives**: What would make a finding NOT a bug in this specific context?
   - **Historical Findings**: Real-world precedent — what similar protocols got hit with
3. Feed these into the HUNT phase as **targeted search instructions** for each agent

This replaces generic checklist scanning with protocol-aware, history-informed analysis.

---

## Protocol Context File Index

| Protocol Type | Auto-Detection Signals | File |
|---|---|---|
| **Lending** | `borrow`, `liquidate`, `healthFactor`, `ILendingPool`, `collateralFactor` | `$FOREFY/protocols/lending.md` |
| **DEX/AMM** | `swap`, `addLiquidity`, `getReserves`, `IUniswapV2Router`, `slot0` | `$FOREFY/protocols/dexes.md` |
| **Derivatives/Perps** | `openPosition`, `leverage`, `fundingRate`, `markPrice`, `indexPrice` | `$FOREFY/protocols/derivatives.md` |
| **Yield/Vault** | `ERC4626`, `totalAssets`, `convertToShares`, `harvest`, `compound` | `$FOREFY/protocols/yield.md` |
| **Staking** | `stake`, `unstake`, `rewardPerToken`, `notifyRewardAmount`, `slashing` | `$FOREFY/protocols/staking.md` |
| **Bridge** | `sendMessage`, `receiveMessage`, `relayer`, `chainId`, `lzReceive` | `$FOREFY/protocols/bridges.md` |
| **Governance** | `propose`, `castVote`, `quorum`, `timelock`, `execute` | `$FOREFY/protocols/governance.md` |
| **NFT Marketplace** | `listItem`, `buyItem`, `cancelListing`, `royalty`, `ERC721` | `$FOREFY/protocols/nft-marketplace.md` |
| **NFT/Gaming** | `mint`, `tokenURI`, `totalSupply`, `randomness`, `VRF` | `$FOREFY/protocols/nft-gaming.md` |
| **Insurance** | `coverage`, `claim`, `premium`, `underwriter`, `pool` | `$FOREFY/protocols/insurance.md` |
| **Synthetics** | `synth`, `debt`, `debtShare`, `SNX`, `collateralizationRatio` | `$FOREFY/protocols/synthetics.md` |
| **Launchpad** | `presale`, `vestingSchedule`, `tokenDistribution`, `claimTokens` | `$FOREFY/protocols/launchpad.md` |
| **Stablecoin (Algo)** | `peg`, `rebase`, `seigniorage`, `expansionRate` | `$FOREFY/protocols/algo-stables.md` |
| **Stablecoin (Decentralized)** | `CDP`, `vault`, `stabilityPool`, `redemption` | `$FOREFY/protocols/decentralized-stablecoin.md` |
| **Index/Basket** | `setToken`, `rebalance`, `componentUnit`, `issuance` | `$FOREFY/protocols/indexes.md` |
| **Liquidity Manager** | `rebalance`, `tickRange`, `positionManager`, `NonfungiblePositionManager` | `$FOREFY/protocols/liquidity-manager.md` |
| **Privacy** | `deposit`, `withdraw`, `nullifier`, `commitment`, `MerkleTree` | `$FOREFY/protocols/privacy.md` |
| **Reserve Currency** | `bonding`, `staking`, `rebasing`, `OHM`, `sOHM` | `$FOREFY/protocols/reserve-currency.md` |
| **RWA Lending** | `RWA`, `tokenization`, `compliance`, `creditRating` | `$FOREFY/protocols/rwa-lending.md` |
| **RWA Tokenization** | `tokenize`, `fractional`, `deed`, `KYC` | `$FOREFY/protocols/rwa-tokenization.md` |
| **Services** | `registry`, `resolver`, `subscription`, `payment` | `$FOREFY/protocols/services.md` |

`$FOREFY` = `/home/web3/web3_tools/skills/forefy-context/skills/smart-contract-audit/reference/solidity`

---

## Bug Class Registry (FV-SOL Taxonomy)

Each protocol context file references these bug classes. The FV-SOL taxonomy provides deep theory and Bad/Good code examples:

### Core Vulnerability Taxonomy

| ID | Category | Subcases | Reference |
|---|---|---|---|
| **FV-SOL-1** | Reentrancy | 9 variants (single, cross-function, cross-contract, cross-chain, dynamic, read-only, ERC721/1155 callback, ERC777 hook, transient storage) | `$FOREFY/fv-sol-1-reentrancy/` |
| **FV-SOL-2** | Precision Errors | 7 variants (decimals, floating-point, rounding, div-by-zero, time-based, ERC4626, special token accounting) | `$FOREFY/fv-sol-2-precision-errors/` |
| **FV-SOL-3** | Arithmetic Errors | 6 variants (overflow/underflow, sign extension, truncation, environment vars, assembly arithmetic, assembly memory/calldata) | `$FOREFY/fv-sol-3-arithmetic-errors/` |
| **FV-SOL-4** | Bad Access Control | 11 variants (tx.origin, unrestricted roles, missing multisig, signature flaws, callback bypass, arbitrary call, ERC1271, arbitrary storage, CREATE2 squat, commit-reveal binding, hash collision) | `$FOREFY/fv-sol-4-bad-access-control/` |
| **FV-SOL-5** | Logic Errors | 11 variants (boundary, conditionals, state transitions, misordered calcs, event misreporting, same-block snapshot, msg.value reuse, force ETH, deployment config, data structure integrity, weak RNG) | `$FOREFY/fv-sol-5-logic-errors/` |
| **FV-SOL-6** | Unsafe External Interactions | Token transfers, approvals, return values, low-level calls | `$FOREFY/fv-sol-6-unsafe-external-interactions/` |
| **FV-SOL-7** | Proxy Insecurities | Upgrade, initialization, storage collision, UUPS | `$FOREFY/fv-sol-7-proxy-insecurities/` |
| **FV-SOL-8** | Slippage & MEV | Front-running, sandwich, deadline, minAmountOut | `$FOREFY/fv-sol-8-slippage-mev/` |
| **FV-SOL-9** | Denial of Service | Unbounded loops, push payment griefing, gas limit | `$FOREFY/fv-sol-9-dos/` |
| **FV-SOL-10** | Oracle Manipulation | 7 variants (incorrect compounding, price drift, external market manipulation, time lags, Chainlink validity, L2 sequencer, missing bounds) | `$FOREFY/fv-sol-10-oracle-manipulation/` |

### Protocol-Specific Bug Classes (No FV-SOL Equivalent)

These are classes discovered from real audit data that don't fit into the standard taxonomy:

| Bug Class | Commonly Found In | Key Pattern |
|---|---|---|
| **Accounting Share Mismatch** | Lending, Vaults | Treasury mint inversion, liquidation fee miscounting |
| **Bad Debt / Protocol Insolvency** | Lending | Dust positions, min borrow bypass, unsocialized debt |
| **Liquidation Logic Errors** | Lending, Perps | Ordering bugs, front-run repayment, stale index |
| **Interest Accrual Errors** | Lending | Timestamp advance without increment, retroactive rate change |
| **Interest Rate Update Ordering** | Lending | Rate update before balance update |
| **Position Health Check Errors** | Lending | Missing accrued interest, wrong weighting formula |
| **Reward Distribution Errors** | Staking, Lending, Yield | Accumulator before transfer, missing liquidation checkpoint |
| **Treasury/Fee Accounting** | All DeFi | Sign error in mint, fee not burned |
| **Vault Share Inflation** | Vault, ERC4626 | First depositor, donation attack |
| **External Protocol Integration** | All DeFi | Wrong join/exit kind, stale interface, peg assumption |
| **ERC-4626 Compliance** | Vault | Preview/actual divergence, max return wrong when paused |
| **Depeg of Pegged Assets** | Lending, Vault | 1:1 assumption, no independent oracle |

---

## Per-Bug-Class Analysis Template

When scanning each bug class for a specific protocol, use this structure:

```markdown
### [Bug Class Name] (ref: FV-SOL-X)

**Preconditions met?** [YES/NO — does this codebase have the conditions?]
If NO → SKIP (log in debug trace)

**Detection checks performed:**
- [ ] [Detection heuristic 1 from protocol context file]
- [ ] [Detection heuristic 2]
- [ ] [Detection heuristic 3]

**Suspects found:** [count]
For each suspect:
- File:line: [location]
- Pattern: [what triggered it]
- FP check: [result of applying FP criteria from protocol context file]
- Historical match: [similar finding from notable historical findings section]

**Verdict:** SUSPECT → [move to ATTACK phase] | CLEAR [log why]
```

---

## Loading Protocol Context During Audit

### Step 1: Detect Protocol Type
```python
# Pseudo-code for auto-detection
for signal in protocol_signals:
    count = grep(codebase, signal.pattern)
    if count >= signal.threshold:
        protocol_type = signal.type
        break
```

### Step 2: Read Protocol Context File
```bash
cat $FOREFY/protocols/{protocol_type}.md
```

### Step 3: Extract Per-Bug-Class Checklist
For each bug class section in the protocol context file:
- Extract **Protocol-Specific Preconditions**
- Extract **Detection Heuristics** (the exact grep commands and code reading checks)
- Extract **False Positives** (what makes it NOT a bug)
- Extract **Notable Historical Findings** (what similar protocols were hit with)
- Extract **Remediation Notes** (standard fixes)

### Step 4: Build Agent Bundle
Combine into an agent-specific bundle:
- Agent 1-4 (vector scan): Merge FV-SOL taxonomy + protocol context detection heuristics with their assigned vector range
- Agent 5 (adversarial): Full protocol context file for independent adversarial review
- Agent 6 (state inconsistency): Protocol-specific state coupling patterns from context file
- Agent 7 (Feynman, beast): Protocol-specific preconditions as questioning targets

---

## Triager Economic Validation

After the FP Gate, apply **economic triager validation** (from Forefy) to every surviving finding:

### Budget-Protection Checks
For each finding, the triager must validate:

1. **Technical Disproof Attempt**: Actively try to prove the finding is NOT exploitable
   - Test the attack path with concrete values
   - Check if protocol protections exist that the initial analysis missed
   - Verify contract locations and line numbers are accurate

2. **Economic Feasibility**: Calculate realistic attack economics
   - Gas cost of the attack at current gas prices
   - Flash loan fees required
   - Capital requirements and opportunity cost
   - Sandwich/MEV profitability threshold
   - Is the attack economically rational for a real attacker?

3. **Evidence Chain Validation**:
   ```
   Code Pattern Observed → Vulnerability Type → Attack Vector → Business Impact → Risk Assessment
   ```
   Every link in this chain must be verified. A missing link = finding is downgraded or dismissed.

4. **Cross-Finding Consistency**: Check all findings for logical contradictions
   - Does Finding A's exploit path assume protection that Finding B says is missing?
   - Are severity levels consistent across similar finding types?

### Triager Verdict Classification
| Verdict | Criteria |
|---|---|
| **VALID** | Cannot be disproved. Economically rational attack. Full evidence chain. |
| **QUESTIONABLE** | Technical issue exists but economic viability unclear. Needs additional proof. |
| **OVERCLASSIFIED** | Valid vulnerability but severity was exaggerated. Downgrade recommended. |
| **DISMISSED** | Disproved technically or economically. Specific reasoning documented. |

---

## Severity Formula (Conservative)

```
Base Score = Impact × Likelihood × Exploitability
Final Score = Base Score (if borderline, round DOWN)
```

| Factor | Score 3 (High) | Score 2 (Medium) | Score 1 (Low) |
|---|---|---|---|
| **Impact** | Complete compromise, TVL >$1M at risk | Significant loss >$100k, major disruption | Limited loss <$100k, minor impact |
| **Likelihood** | In core user flows, easily discoverable | Requires moderate knowledge + conditions | Requires expert knowledge + timing |
| **Exploitability** | Single tx, flash-loan enabled, guaranteed profit | Multi-tx, requires capital, timing dependent | Requires governance, extensive setup |

| Score Range | Severity |
|---|---|
| 18-27 | CRITICAL |
| 8-17 | HIGH |
| 4-7 | MEDIUM |
| 1-3 | LOW |

**Conservative rule**: When uncertain between two severity levels, ALWAYS choose the LOWER one.
