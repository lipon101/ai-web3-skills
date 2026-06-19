# Invariant Framework

Templates for state variable inventory, state transition graphs, and core invariant definitions. Use during Phase 2 (MAP) of the VeerSkills audit pipeline.

---

## Module 1: State Variable Inventory

For each contract, create `notes/state/{ContractName}_state.md`:

```markdown
# {ContractName} State Variables

| Variable | Type | Visibility | Mutability | Dependencies | Invariant Role |
|----------|------|-----------|-----------|-------------|---------------|
| totalSupply | uint256 | public | mutable | mint/burn calls | Core: must equal sum(balances) |
| totalAssets | uint256 | public | mutable | deposits/withdrawals + yield | Safety: solvency check |
| owner | address | public | mutable | transferOwnership | Access Control |
| paused | bool | public | mutable | pause/unpause | Safety: emergency stop |
| balances[addr] | mapping | private | mutable | transfers, mint, burn | Core: individual accounting |

### External Dependencies
- Oracle price feed at {address}: used in {function} for {purpose}
- Token contract at {address}: assumed to be standard ERC-20
- External protocol at {address}: called in {function}

### Auto-Extraction
Run Slither's `vars-and-auth` printer for automated extraction:
```bash
slither . --print vars-and-auth 2>/dev/null
```
```

---

## Module 2: State Transition Graph

### State Space Definition
```
S = (s₁, s₂, ..., sₙ) where:
  s₁ = totalSupply
  s₂ = totalAssets
  s₃ = paused
  s₄ = owner
  s₅ = balances[]
  ...
```

### Per-Function Transition Table

```markdown
## Function: deposit(uint256 assets, address receiver)

### Pre-conditions
- [ ] !paused
- [ ] assets > 0
- [ ] msg.sender has approved contract for ≥ assets
- [ ] receiver != address(0)

### State Changes
- balances[receiver] += shares
- totalSupply += shares
- totalAssets += assets
- Token transferred: msg.sender → contract

### Post-conditions
- [ ] totalSupply increased by exactly shares
- [ ] totalAssets increased by exactly assets (after fee-on-transfer check)
- [ ] balances[receiver] increased by exactly shares
- [ ] Event Deposit(msg.sender, receiver, assets, shares) emitted

### Invariant Preservation
- [ ] SOLVENCY: totalAssets_after >= totalSupply_after (with share/asset ratio)
- [ ] CONSISTENCY: sum(balances) == totalSupply
- [ ] NO_FREE_LUNCH: shares ≤ assets * totalSupply / totalAssets (depositor doesn't gain unearned shares)
```

### Transition Graph Visualization
```
[Idle] --deposit()--> [Active]
[Active] --withdraw()--> [Active|Idle]
[Active] --pause()--> [Paused]
[Paused] --unpause()--> [Active]
[Paused] --emergencyWithdraw()--> [Paused]
[*] --upgradeProxy()--> [Upgraded]
```

---

## Module 3: Core Invariant Definitions

### SAFETY Invariants

#### S1: Solvency
```
INVARIANT: totalAssets >= totalLiabilities
WHERE: totalLiabilities = sum(user_claimable_amounts)
RATIONALE: Protocol must always have enough assets to honor all withdrawals
VIOLATION IMPACT: User fund loss, bank run
ECHIDNA TEST: function echidna_solvency() public returns (bool) {
    return vault.totalAssets() >= _computeTotalLiabilities();
}
```

#### S2: Balance Consistency
```
INVARIANT: sum(balances[all_holders]) == totalSupply
RATIONALE: Total supply must exactly match individual balances
VIOLATION IMPACT: Phantom tokens, inflation, accounting corruption
ECHIDNA TEST: function echidna_balance_consistency() public returns (bool) {
    return _sumAllBalances() == token.totalSupply();
}
```

#### S3: Access Control Integrity
```
INVARIANT: owner can only change via transferOwnership() + acceptOwnership()
RATIONALE: Ownership must follow two-step transfer for safety
VIOLATION IMPACT: Protocol takeover, unauthorized admin actions
```

#### S4: No Unauthorized Minting
```
INVARIANT: totalSupply can only increase via authorized deposit/mint paths
RATIONALE: Tokens must be backed by proportional assets
VIOLATION IMPACT: Dilution, theft via inflation
```

### LIVENESS Invariants

#### L1: Withdrawal Availability
```
INVARIANT: If user has balance > 0, withdraw(balance) must eventually succeed
RATIONALE: Users must always be able to exit
VIOLATION IMPACT: Locked funds, protocol death spiral
EXCEPTION: Paused state (must be time-limited)
```

#### L2: Protocol Progress
```
INVARIANT: No function sequence can permanently deadlock the protocol
RATIONALE: Protocol must always be able to reach a productive state
VIOLATION IMPACT: Permanent fund lock
```

### ECONOMIC Invariants

#### E1: No Free Lunch
```
INVARIANT: net_value_extracted(user) <= value_deposited(user) + earned_yield(user)
RATIONALE: Users cannot extract more value than they contributed + earned
VIOLATION IMPACT: Theft from other users or protocol reserves
ECHIDNA TEST: function echidna_no_free_lunch() public returns (bool) {
    return _getUserTotalWithdrawn(attacker) <= _getUserTotalDeposited(attacker) + _getUserEarnings(attacker);
}
```

#### E2: Share Price Monotonicity (for yield vaults)
```
INVARIANT: sharePrice(t2) >= sharePrice(t1) for t2 > t1 (excluding loss events)
RATIONALE: Share price should only increase from yield, never decrease from user actions
VIOLATION IMPACT: Value extraction via share price manipulation
```

#### E3: Fee Bounds
```
INVARIANT: 0 <= fee_rate <= MAX_FEE (e.g., 10%)
RATIONALE: Fees must be bounded to prevent extraction
VIOLATION IMPACT: Excessive fee extraction from users
```

### COMPOSABILITY Invariants *(NEW)*

#### C1: External Protocol Survival
```
INVARIANT: If external_protocol.paused() == true, this protocol must NOT revert on user withdrawals
RATIONALE: Integration dependencies must not lock user funds
VIOLATION IMPACT: Permanent fund lock when external protocol pauses/upgrades/rugs
CHECK: For each external call, simulate: what if it reverts? Does the caller handle it?
```

#### C2: Token Standard Compliance
```
INVARIANT: Protocol handles ALL ERC-20 edge cases:
  - fee-on-transfer (actual received != amount argument)
  - rebasing (balance changes without transfer)
  - missing return value (USDT, BNB)
  - permit (EIP-2612) front-running
  - ERC-777 hooks (reentrancy via tokensReceived)
RATIONALE: Protocol must not break with any compliant token
CHECK: grep for raw transferFrom without balance-before-after measurement
```

#### C3: Oracle Freshness
```
INVARIANT: price_feed.updatedAt >= block.timestamp - MAX_STALENESS
RATIONALE: Stale prices enable under-collateralized borrows, wrong liquidations
VIOLATION IMPACT: Protocol insolvency, user fund loss
CHECK: grep for Chainlink latestRoundData() without staleness check
ECHIDNA TEST: function echidna_oracle_fresh() public returns (bool) {
    (, , , uint256 updatedAt, ) = oracle.latestRoundData();
    return block.timestamp - updatedAt <= MAX_STALENESS;
}
```

#### C4: Approval Safety
```
INVARIANT: No user approval (approve/permit/permit2) grants access beyond intended scope
RATIONALE: Inherited allowances (especially via Permit2) can drain users across protocols
VIOLATION IMPACT: Cross-protocol user fund drain
CHECK: Does protocol use Permit2? If so, is allowance scoped to THIS protocol only?
```

---

## Module 4: Invariant Violation Search

### Rounding Exploitation Vectors
```solidity
// Test: Can tiny deposits exploit rounding?
function test_rounding_exploit() public {
    // Attacker deposits 1 wei
    vault.deposit(1, attacker);
    // Attacker donates large amount directly
    token.transfer(address(vault), 1e18);
    // Victim deposits reasonable amount
    vm.prank(victim);
    vault.deposit(1e18, victim);
    // Check: victim should NOT get 0 shares
    assertGt(vault.balanceOf(victim), 0, "First depositor inflation!");
}
```

### Fee-on-Transfer Vectors
```solidity
// Test: Does protocol handle FoT tokens correctly?
function test_fot_accounting() public {
    uint256 depositAmount = 1000e18;
    uint256 balanceBefore = feeToken.balanceOf(address(vault));
    vault.deposit(depositAmount, user);
    uint256 balanceAfter = feeToken.balanceOf(address(vault));
    uint256 actualReceived = balanceAfter - balanceBefore;
    // Protocol should credit actualReceived, not depositAmount
    assertEq(vault.totalAssets(), actualReceived, "FoT accounting mismatch!");
}
```

### Oracle Manipulation Vectors
```solidity
// Test: Can flash loan manipulate oracle price?
function test_oracle_manipulation() public {
    uint256 priceBefore = oracle.getPrice(token);
    // Simulate flash loan: massive swap to move price
    vm.prank(attacker);
    router.swap(address(token), address(usdc), flashLoanAmount, 0, block.timestamp);
    uint256 priceAfter = oracle.getPrice(token);
    // Oracle price should NOT change dramatically in one block
    assertApproxEqRel(priceAfter, priceBefore, 0.05e18, "Oracle manipulable!");
}
```

### Reentrancy Drain Vectors
```solidity
// Test: Can reentrancy drain funds?
contract ReentrancyAttacker {
    uint256 public attackCount;
    function attack(IVault vault) external {
        vault.deposit{value: 1 ether}(1 ether, address(this));
        vault.withdraw(1 ether, address(this), address(this));
    }
    receive() external payable {
        if (attackCount < 5) {
            attackCount++;
            IVault(msg.sender).withdraw(1 ether, address(this), address(this));
        }
    }
}
```

---

## Echidna Configuration Template

```yaml
# echidna.config.yaml
testMode: assertion
testLimit: 100000
seqLen: 100
corpusDir: corpus
deployer: "0x1000000000000000000000000000000000000000"
sender: ["0x2000000000000000000000000000000000000000",
         "0x3000000000000000000000000000000000000000"]
balanceAddr: 0xffffffff
balanceContract: 0xffffffff
shrinkLimit: 5000
```

## Foundry Invariant Test Template

```solidity
contract InvariantTest is Test {
    Handler handler;

    function setUp() public {
        // Deploy protocol
        // Deploy handler that wraps protocol calls
        handler = new Handler(protocol);
        targetContract(address(handler));
    }

    // SAFETY: Solvency
    function invariant_solvency() public {
        assertGe(vault.totalAssets(), vault.totalSupply());
    }

    // SAFETY: Balance consistency
    function invariant_balance_consistency() public {
        assertEq(handler.ghost_totalDeposited() - handler.ghost_totalWithdrawn(),
                 token.balanceOf(address(vault)));
    }

    // ECONOMIC: No free lunch
    function invariant_no_free_lunch() public {
        assertLe(handler.ghost_totalWithdrawn(), handler.ghost_totalDeposited() + handler.ghost_totalYield());
    }
}
```
