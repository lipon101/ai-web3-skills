# VeerSkills Protocol-Specific Audit Routes

_9 protocol types with required reading paths, severity tables, and conditional checklists. Adapted from WEB3-AUDIT-SKILLS route map._

---

## Quick Protocol Router

```
┌─────────────────────────────────────────────────────────────────┐
│                    WHAT ARE YOU AUDITING?                        │
├─────────────────────────────────────────────────────────────────┤
│  1. LENDING       2. DEX/AMM         3. BRIDGE                  │
│  4. VAULT/YIELD   5. STAKING         6. NFT MARKETPLACE         │
│  7. GOVERNANCE    8. PERPS/OPTIONS   9. INTENT SYSTEM            │
└─────────────────────────────────────────────────────────────────┘
```

**Auto-detection**: Identify protocol type from:
- Import patterns (`ILendingPool`, `IUniswapV2Router`, `IERC4626`)
- Function names (`borrow`, `liquidate`, `swap`, `addLiquidity`, `stake`)
- State variables (`totalBorrowed`, `reserves`, `totalShares`, `validators`)
- Contract inheritance patterns

---

## 1. Lending Protocol

**Matches**: Aave-like, Compound-like, any borrow/lend system

### Critical Path (check these FIRST)
| Priority | Area | Key Vectors |
|----------|------|-------------|
| P0 | Oracle manipulation → bad debt | V55, V69, V86, V93, V124, V137, V141 |
| P0 | First depositor attack | V120, V133, V167 |
| P1 | Liquidation DoS / manipulation | V41, V43, V147 |
| P1 | Interest accrual before health check | V147, V144 |
| P2 | Stale oracle prices | V69, V93, V145 |

### Required Checks
- [ ] Oracle: staleness, bounds, depeg handling, L2 sequencer
- [ ] Liquidation: self-liquidation, accrued interest, dust positions
- [ ] Share math: first depositor, rounding direction, inflation attack
- [ ] Flash loan: price manipulation, governance attack, collateral manipulation
- [ ] Interest: accrual timing, rate model edge cases, utilization gaming

### Conditional
| If Protocol Has... | Also Check |
|---------------------|-----------|
| Governance tokens | V90, V131 — flash loan governance |
| Isolated markets | Cross-market interactions, shared oracles |
| Cross-chain lending | V117, V119, V140, V142 |
| NFT collateral | V49, V64, V109 |

---

## 2. DEX / AMM

**Matches**: Uniswap-like, Curve-like, any swap system

### Critical Path
| Priority | Area | Key Vectors |
|----------|------|-------------|
| P0 | K value / reserve manipulation | V86, V124 |
| P0 | Missing slippage protection | V95, V125, V154 |
| P1 | Callback reentrancy (swap hooks) | V12, V52, V60, V105 |
| P1 | Sandwich attacks | V125, V95 |
| P2 | Fee calculation / precision | V26, V35, V73 |

### Required Checks
- [ ] Slippage: `amountOutMin` present, user-set, not on-chain derived
- [ ] Deadline: present and validated (not `block.timestamp`)
- [ ] Reentrancy: CEI on all swap paths, callback safety
- [ ] Price oracle: not using spot reserves for pricing
- [ ] Token compatibility: fee-on-transfer, rebasing, decimals

### Conditional
| If DEX Has... | Also Check |
|---------------|-----------|
| Concentrated liquidity | V26, V70 — precision loss in tick math |
| Hooks (V4 style) | Arbitrary code execution in hook callbacks |
| Stable swaps | Depeg handling, amplification parameter bounds |
| Limit orders | V51, V127, V138 — signature/replay |

---

## 3. Bridge

**Matches**: Cross-chain bridge, token bridge, message passing

### Critical Path
| Priority | Area | Key Vectors |
|----------|------|-------------|
| P0 | Message spoofing / signature bypass | V1, V117, V119 |
| P0 | Replay across chains | V24, V127, V140 |
| P0 | Fake peer / unauthorized mint | V119, V159 |
| P1 | DVN collusion / insufficient diversity | V142, V143 |
| P1 | Rate limits / circuit breakers missing | V143 |
| P2 | Reorg double-spend | V114 |

### Required Checks
- [ ] Message verification: endpoint, peer, chain ID all validated
- [ ] Nonce management: monotonic, gap-free, DoS-resistant
- [ ] Supply invariant: `total_locked_source >= total_minted_destination`
- [ ] Rate limits: per-tx caps, per-window caps, pause mechanism
- [ ] Finality: sufficient block confirmations per chain

### Conditional
| If Bridge Has... | Also Check |
|-----------------|-----------|
| Optimistic verification | Challenge period, fraud proof completeness |
| ZK proofs | Proof verification, circuit soundness |
| LayerZero | V7, V38, V42, V47, V71, V160 |
| Token wrapping | V4, V73, V128 |

---

## 4. Vault / Yield Aggregator

**Matches**: ERC4626 vault, yield optimizer, auto-compounder

### Critical Path
| Priority | Area | Key Vectors |
|----------|------|-------------|
| P0 | Share price manipulation | V120, V133, V167 |
| P0 | First depositor / inflation attack | V167, V56 |
| P1 | Rounding direction violations | V56, V66, V67, V136 |
| P1 | Donation attack via direct transfer | V54, V152 |
| P2 | Strategy loss attribution | V26, V35 |

### Required Checks
- [ ] Rounding: deposit/mint round DOWN, withdraw/redeem round UP (vault-favorable)
- [ ] First depositor: dead shares, `_decimalsOffset()`, minimum deposit
- [ ] `totalAssets()`: not manipulable by direct token transfer
- [ ] Preview functions match actual behavior (no divergence)
- [ ] `maxDeposit/maxMint/maxRedeem/maxWithdraw`: return correct limits

### Conditional
| If Vault Has... | Also Check |
|-----------------|-----------|
| Strategies | Strategy migration, loss socialization |
| Multiple assets | V4 — decimal mismatch |
| Timelocks | V77 — griefing via dust deposits |
| Withdrawal queues | V110 — DoS via rejecting contract |

---

## 5. Staking / Restaking

**Matches**: Staking pool, liquid staking, restaking (EigenLayer-like)

### Critical Path
| Priority | Area | Key Vectors |
|----------|------|-------------|
| P0 | Reward front-running | V3, V144 |
| P0 | Slashing amount manipulation | Cross-function interactions |
| P1 | Unbonding bypass | V77, V89 |
| P1 | Reward calculation overflow | V45, V70 |
| P2 | Dust reward griefing | V10, V35, V77 |

### Required Checks
- [ ] Reward checkpoint: `updateReward()` BEFORE any balance change
- [ ] Minimum stake: prevents dust position griefing
- [ ] Unbonding period: cannot be bypassed or reset
- [ ] Slashing: correctly applied, cannot be gamed
- [ ] Delegation: operator selection safety, validator management

---

## 6. NFT Marketplace

**Matches**: NFT trading, auction, royalty system

### Critical Path
| Priority | Area | Key Vectors |
|----------|------|-------------|
| P0 | Signature replay → free NFTs | V1, V51, V127, V138 |
| P0 | Type confusion (ERC721/1155 quantity) | V104 |
| P1 | Auction manipulation | V5, V95 |
| P1 | Callback reentrancy | V12, V49 |
| P2 | Royalty bypass | V107 |

### Required Checks
- [ ] Signatures: nonce, chainId, expiry, msg.sender binding
- [ ] Callbacks: `onERC721Received` / `onERC1155Received` safety
- [ ] Quantity: ERC721 always quantity==1
- [ ] Approval: cleared on transfer, no lingering approvals
- [ ] Price: payment matches listing, no zero-payment paths

---

## 7. Governance / DAO

**Matches**: On-chain governance, voting, timelock

### Critical Path
| Priority | Area | Key Vectors |
|----------|------|-------------|
| P0 | Flash loan voting | V131 |
| P0 | Governance takeover via upgrade | V90 |
| P1 | Timelock bypass | V94 |
| P1 | Proposal spam / DoS | V25, V82 |
| P2 | Quorum manipulation | V3 |

### Required Checks
- [ ] Voting: uses `getPastVotes(block.number - 1)`, not current balance
- [ ] Timelock: present, >= 24h, cannot be bypassed
- [ ] Quorum: high enough to prevent flash loan attacks
- [ ] Proposal execution: bounded gas, cannot drain treasury
- [ ] Delegate: privilege escalation checks

---

## 8. Perpetuals / Options

**Matches**: Perp DEX, options protocol, derivatives

### Critical Path
| Priority | Area | Key Vectors |
|----------|------|-------------|
| P0 | Oracle manipulation → liquidation cascade | V86, V124, V137, V141 |
| P0 | Mark/index price divergence | V55, V69 |
| P1 | Funding rate manipulation | Cross-function interactions |
| P1 | ADL (auto-deleverage) abuse | V97, V135 |
| P2 | Insurance fund drain | V35, V120 |

### Required Checks
- [ ] Oracle: multi-source, circuit breaker, bounded updates
- [ ] Liquidation: cascade limits, self-liquidation prevention
- [ ] Funding rate: bounded, time-weighted, manipulation-resistant
- [ ] Position limits: per-user caps, open interest caps
- [ ] Settlement: rounding favors protocol, dust handling

---

## 9. Intent Systems

**Matches**: Intent-based protocol, solver network, CoW-style

### Critical Path
| Priority | Area | Key Vectors |
|----------|------|-------------|
| P0 | Intent forgery / signature bypass | V1, V51, V127, V138 |
| P1 | Solver collusion | V97, V121 |
| P1 | Front-running intent execution | V95, V125 |
| P2 | Partial fill manipulation | V26, V35 |

### Required Checks
- [ ] Intent signing: EIP-712, nonce, chainId, expiry, msg.sender
- [ ] Solver validation: whitelist/stake, result verification
- [ ] Slippage: user-specified minimum, checked at settlement
- [ ] Cancellation: effective before execution, no race condition
- [ ] Ordering: fair ordering, no preferential execution

---

## Universal Checks (ALWAYS Apply)

Regardless of protocol type, **always** check:

| Category | Key Vectors | Description |
|----------|-------------|-------------|
| Access Control | V15, V101, V113 | Missing modifiers, deployer retention |
| Reentrancy | V12, V52, V60, V83, V98, V105, V153 | All variants |
| Overflow | V32, V45, V70, V85 | Unchecked, downcasts, assembly |
| DoS | V10, V25, V82, V110 | Loops, push payments, block stuffing |
| Upgrade Safety | V18, V48, V106, V139, V149, V168 | All proxy patterns |
| Token Handling | V73, V84, V87, V128 | Fee-on-transfer, rebasing, non-standard |
