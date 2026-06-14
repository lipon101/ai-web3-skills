# Attack Modeling

Attacker capability profiles, attack tree construction, and cross-function interaction analysis. Use during Phase 3 (HUNT) and Phase 4 (ATTACK) of the VeerSkills pipeline.

---

## Module 5: Attacker Capability Profiles

### Profile 1: Retail Attacker ($1k-$100k)
```
Capital:        $1,000 – $100,000
Tools:          Etherscan, MEV bots (borrowed/rented), standard flash loans via UI
Skill Level:    Can deploy contracts from templates, use existing exploit scripts
Flash Loans:    Via interfaces (Aave, dYdX, Balancer)
Time Horizon:   Single transaction or small sequence
Detection Risk: Low (standard transactions blend in)
Motivation:     Direct profit from known vulnerability patterns
```
**What to test**: Can any known vulnerability be exploited with < $100k and standard tooling?

### Profile 2: Whale Attacker ($100k-$10M)
```
Capital:        $100,000 – $10,000,000
Tools:          Custom contracts, private flash loan providers, oracle manipulation
Skill Level:    Reverse engineering, custom exploit development
Flash Loans:    Direct protocol interactions, multi-step flash loans
Time Horizon:   Hours to days of preparation, multi-tx attack sequences
Detection Risk: Medium (unusual activity may be noticed)
Motivation:     Large-scale DeFi exploitation, market manipulation
```
**What to test**: Can oracle prices be moved? Can governance be attacked? Can multi-step sequences extract value?

### Profile 3: Nation-State / Organized Crime ($10M+)
```
Capital:        $10,000,000+
Tools:          Zero-day exploitation, social engineering, insider compromise
Skill Level:    World-class, access to unreleased vulnerabilities
Flash Loans:    Unlimited via own liquidity + lending protocols
Time Horizon:   Weeks to months of preparation
Detection Risk: Managed (operational security, laundering infrastructure)
Motivation:     Strategic disruption, massive theft, sanctions evasion
```
**What to test**: Bridge exploits, consensus-level attacks, compound vulnerability chains

### Profile 4: MEV Bot (Flash Loan Backed)
```
Capital:        Functionally unlimited (flash loans)
Tools:          Searcher infrastructure, private mempools, block builder relationships
Skill Level:    Automated, optimized for speed and gas efficiency
Flash Loans:    Integrated into every transaction
Time Horizon:   Single transaction (atomic)
Detection Risk: Negligible (looks like normal DeFi activity)
Motivation:     Risk-free arbitrage, sandwich attacks, liquidation sniping
```
**What to test**: Sandwich vulnerability, frontrunning, transaction ordering dependence

---

## Threat Matrix Template

```markdown
| # | Threat | Attacker Profile | Likelihood | Impact | Risk Score | Mitigation | Status |
|---|--------|-----------------|------------|--------|------------|------------|--------|
| T1 | Share inflation | Retail | High | Critical | 🔴 P0 | Virtual offset | ❌ Missing |
| T2 | Oracle manipulation | Whale | Medium | High | 🟠 P1 | TWAP + bounds | ✅ Present |
| T3 | Sandwich attack | MEV Bot | High | Medium | 🟡 P2 | Slippage check | ⚠️ Partial |
| T4 | Governance takeover | Nation-State | Low | Critical | 🟡 P2 | Timelock + quorum | ✅ Present |
| T5 | Reentrancy drain | Retail | Medium | Critical | 🟠 P1 | ReentrancyGuard | ✅ Present |
```

---

## Module 6: Attack Tree Construction

### Branch 1: Direct Exploits
```
GOAL: Extract funds without authorization
├── 1.1 Reentrancy
│   ├── 1.1.1 Classic single-function [RE-1]
│   ├── 1.1.2 Cross-function [RE-2]
│   ├── 1.1.3 Cross-contract [RE-3]
│   ├── 1.1.4 Read-only [RE-4]
│   └── 1.1.5 Callback-triggered [RE-5]
├── 1.2 Access Control Bypass
│   ├── 1.2.1 Missing modifier [AC-1]
│   ├── 1.2.2 tx.origin phishing [AC-2]
│   ├── 1.2.3 Unprotected initialize [AC-3]
│   ├── 1.2.4 Role escalation [AC-4]
│   └── 1.2.5 Signature replay [AC-5]
├── 1.3 Arithmetic Exploits
│   ├── 1.3.1 Overflow in unchecked [AR-1]
│   ├── 1.3.2 Precision loss in division [AR-2]
│   ├── 1.3.3 Rounding direction abuse [AR-3]
│   ├── 1.3.4 Truncation on downcast [AR-4]
│   └── 1.3.5 Division by zero [AR-5]
└── 1.4 Proxy/Upgrade Exploits
    ├── 1.4.1 Storage collision [UP-1]
    ├── 1.4.2 Implementation takeover [UP-2]
    ├── 1.4.3 UUPS auth bypass [UP-3]
    ├── 1.4.4 Init front-running [UP-4]
    └── 1.4.5 Migration corruption [UP-5]
```

### Branch 2: Economic Exploits
```
GOAL: Extract value through economic manipulation
├── 2.1 Oracle Manipulation
│   ├── 2.1.1 Spot price flash loan [OR-1]
│   ├── 2.1.2 Stale price exploitation [OR-2]
│   ├── 2.1.3 Oracle failure exploitation [OR-3]
│   ├── 2.1.4 Heartbeat mismatch [OR-4]
│   └── 2.1.5 Donation attack on price [OR-5]
├── 2.2 Flash Loan Amplification
│   ├── 2.2.1 Share inflation attack [EC-2]
│   ├── 2.2.2 Balance-based price manipulation [EC-1]
│   └── 2.2.3 Collateral ratio manipulation
├── 2.3 MEV Extraction
│   ├── 2.3.1 Sandwich attacks [EC-3]
│   ├── 2.3.2 Frontrunning liquidations
│   └── 2.3.3 Just-in-time liquidity
└── 2.4 Incentive Gaming
    ├── 2.4.1 Free option exploitation [EC-5]
    ├── 2.4.2 Fee-on-transfer arbitrage [EC-4]
    └── 2.4.3 Reward farming without risk
```

### Branch 3: Governance Attacks
```
GOAL: Take control of protocol parameters or funds
├── 3.1 Proposal Manipulation
│   ├── 3.1.1 Flash loan voting
│   ├── 3.1.2 Vote buying
│   └── 3.1.3 Proposal spam DoS
├── 3.2 Upgrade Attacks
│   ├── 3.2.1 Malicious implementation
│   ├── 3.2.2 Timelock bypass
│   └── 3.2.3 Proxy admin takeover
└── 3.3 Parameter Attacks
    ├── 3.3.1 Fee parameter manipulation
    ├── 3.3.2 Oracle address swap
    └── 3.3.3 Whitelist manipulation
```

### Branch 4: Systemic Risks
```
GOAL: Exploit cross-protocol or ecosystem-level vulnerabilities
├── 4.1 Cross-Protocol Contagion
│   ├── 4.1.1 Composability failure cascade
│   ├── 4.1.2 Shared oracle dependency
│   └── 4.1.3 Correlated liquidation spiral
├── 4.2 Cross-Chain Attacks
│   ├── 4.2.1 Bridge message forgery [CO-3]
│   ├── 4.2.2 Replay across chains
│   └── 4.2.3 Sequencer manipulation (L2)
└── 4.3 Infrastructure Risks
    ├── 4.3.1 RPC manipulation
    ├── 4.3.2 Block builder censorship
    └── 4.3.3 MEV supply chain attacks
```

---

## Module 8: Cross-Function Interaction Sequences

### Critical Sequences to Test

Every DeFi protocol must be tested with these multi-call sequences:

#### Sequence 1: Deposit → Price Manipulation → Withdraw
```
1. User deposits assets, receives shares
2. Attacker manipulates asset price (oracle, donation, flash loan)
3. User withdraws — do they get correct value?
TESTS: Does share/asset ratio survive manipulation?
```

#### Sequence 2: Multiple Deposits → Rounding → Withdraw All
```
1. User makes N small deposits
2. Each deposit rounds down by 1 wei in shares
3. User withdraws all shares
TESTS: Is accumulated rounding loss > dust threshold?
```

#### Sequence 3: Deposit → Upgrade → Withdraw
```
1. User deposits before proxy upgrade
2. Admin upgrades implementation
3. User withdraws after upgrade
TESTS: Does storage layout change corrupt user balances?
```

#### Sequence 4: Deposit → Pause → Emergency Withdraw
```
1. User deposits during normal operation
2. Admin pauses protocol
3. User attempts emergency withdrawal
TESTS: Can user recover funds during pause?
```

#### Sequence 5: Flash Loan → Deposit → Borrow → Repay
```
1. Attacker flash loans large amount
2. Deposits into protocol (inflates collateral)
3. Borrows against inflated collateral
4. Repays flash loan
TESTS: Does protocol check pre-flash-loan balances?
```

#### Sequence 6: Grant Role → Execute → Revoke Role
```
1. Admin grants role to address
2. Address executes privileged action
3. Role is revoked
TESTS: Is there a timelock? Can action be front-run? Is revocation effective?
```

### Sequence Test Template (Foundry)
```solidity
function test_sequence_deposit_manipulate_withdraw() public {
    // Phase 1: Normal deposit
    vm.prank(user);
    vault.deposit(1000e18, user);
    uint256 sharesBefore = vault.balanceOf(user);

    // Phase 2: Manipulation attempt
    vm.prank(attacker);
    token.transfer(address(vault), 1000000e18); // Donation attack

    // Phase 3: Withdrawal
    vm.prank(user);
    uint256 assetsReceived = vault.redeem(sharesBefore, user, user);

    // Verify: User should get proportional assets, not be sandwiched
    assertGe(assetsReceived, 1000e18, "User lost funds to manipulation!");
}
```

### Leaf Node Analysis Template
For each attack tree leaf node:
```
| Leaf | Feasibility | Capital | Complexity | Detection | Mitigation | Priority |
|------|------------|---------|------------|-----------|------------|----------|
| 1.1.1 | High | $0 (flash) | Low | Low | ReentrancyGuard | P0 |
| 2.1.1 | Medium | $1M+ | Medium | Medium | TWAP oracle | P1 |
```
