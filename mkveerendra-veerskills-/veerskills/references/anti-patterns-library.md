# Anti-Patterns Library

This library contains explicit examples of vulnerable code, how it is exploited in the wild, and the correct mitigation pattern. It goes deeper than abstract concepts by providing exact code implementations.

---

## 1. Oracle Integration Anti-Patterns

### Anti-Pattern 1.A: Spot Price as Oracle
Using the immediate reserve ratio of an AMM (e.g., Uniswap V2) to price assets. This allows a flash loan to skew the ratio in a single transaction, tricking the protocol into reading a massively inflated/deflated price.

**VULNERABLE CODE (BAD):**
```solidity
function getPrice() public view returns (uint256) {
    (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
    // Vulnerable: Spot price easily manipulated in 1 tx
    return (uint256(reserve1) * 1e18) / reserve0; 
}
```

**ATTACK PoC:**
```solidity
// 1. Flash loan 10,000 ETH from Aave
// 2. Swap 10,000 ETH for target token in Uniswap V2 (massively inflates ETH price in pool)
// 3. Call target protocol `borrow()`. It reads `getPrice()` which now says 1 token = 10,000 ETH.
// 4. Borrow all funds from the target protocol using a single token as collateral.
// 5. Swap back on Uniswap, repay flash loan, keep extracted protocol funds.
```

**CORRECT PATTERN (GOOD):**
```solidity
// Use Uniswap V3 TWAP (Time-Weighted Average Price)
function getPriceTWAP(uint32 twapInterval) public view returns (uint256) {
    uint32[] memory secondsAgos = new uint32[](2);
    secondsAgos[0] = twapInterval; // e.g., 1800 seconds (30 mins)
    secondsAgos[1] = 0;

    (int56[] memory tickCumulatives, ) = pool.observe(secondsAgos);
    int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
    int24 timeWeightedAverageTick = int24(tickCumulativesDelta / int32(twapInterval));
    
    // Convert tick to price (or better yet, use Chainlink)
    return OracleLibrary.getQuoteAtTick(timeWeightedAverageTick, 1e18, token0, token1);
}
```

### Anti-Pattern 1.B: Unchecked Chainlink Stale Prices
Assuming Chainlink `latestRoundData()` always returns a fresh and accurate price. During extreme volatility or network congestion, the feed may halt.

**VULNERABLE CODE (BAD):**
```solidity
function getOraclePrice() public view returns (uint256) {
    // Vulnerable: Ignores timestamp and roundID
    (, int256 price, , ,) = priceFeed.latestRoundData();
    require(price > 0, "Invalid price");
    return uint256(price);
}
```

**ATTACK PoC:**
```solidity
// (Observed during Terra/LUNA crash)
// 1. Protocol hardcodes Chainlink LUNA oracle minimum price deviation check.
// 2. LUNA drops from $1.00 to $0.0001, but the oracle is circuit-broken at $0.10.
// 3. Attacker buys LUNA at $0.0001 on the open market.
// 4. Attacker deposits LUNA to protocol. Protocol reads stale $0.10 price.
// 5. Attacker drains 1000x value in stablecoins. 
```

**CORRECT PATTERN (GOOD):**
```solidity
function getOraclePrice() public view returns (uint256) {
    (
        uint80 roundID, 
        int256 price, 
        , 
        uint256 updatedAt, 
        uint80 answeredInRound
    ) = priceFeed.latestRoundData();
    
    require(price > 0, "Negative or zero price");
    require(answeredInRound >= roundID, "Stale round");
    require(block.timestamp - updatedAt <= HEARTBEAT_TIME, "Stale price timestamp");
    
    return uint256(price);
}
```

---

## 2. Reentrancy Anti-Patterns

### Anti-Pattern 2.A: Read-Only Reentrancy
A protocol secures its primary functions with `nonReentrant` but exposes a high-value state reader (like exchange rate or internal price) without a lock. An attacker re-enters the protocol while state is inconsistent, but only *reads* from it to exploit a *third-party* protocol that relies on that reader.

**VULNERABLE CODE (BAD - TARGET PROTOCOL):**
```solidity
contract TargetPool {
    // Balances are up to date, but totalsupply isn't yet!
    function getVirtualPrice() public view returns (uint256) {
        // Vulnerable: Total supply is updated AFTER external calls in removeLiquidity
        return (totalAssets() * 1e18) / totalSupply(); 
    }

    function removeLiquidity(uint amount) external nonReentrant {
        uint toSend = (amount * totalAssets()) / totalSupply();
        token.transfer(msg.sender, toSend); // <-- External call, state is dirty!
        _burn(msg.sender, amount); // State update happens AFTER
    }
}
```

**CORRECT PATTERN (GOOD):**
```solidity
function removeLiquidity(uint amount) external nonReentrant {
    uint toSend = (amount * totalAssets()) / totalSupply();
    _burn(msg.sender, amount); // Update state FIRST (CEI)
    token.transfer(msg.sender, toSend); // External call LAST
}
// Alternatively, if the protocol must break CEI, the `getVirtualPrice` reader must also use `nonReentrant` to enforce sequential locks.
```

---

## 3. Access Control Anti-Patterns

### Anti-Pattern 3.A: Missing Initializer / Upgradeable Proxy Sniping
A logic contract for an upgradeable proxy is deployed but left uninitialized. An attacker calls `initialize()`, becomes the owner of the logic contract, and executes a `delegatecall` to deeply alter the logic contract's self-destruct mechanism, breaking all proxies pointing to it.

**VULNERABLE CODE (BAD):**
```solidity
contract VaultLogic {
    bool public initialized;
    address public owner;
    
    // Vulnerable: No `initializer` modifier or lock on the logic contract itself
    function initialize(address _owner) public {
        require(!initialized, "Already initialized");
        owner = _owner;
        initialized = true;
    }
}
```

**CORRECT PATTERN (GOOD):**
```solidity
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract VaultLogic is Initializable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // Good: Immediately locks the logic contract upon deployment
        _disableInitializers(); 
    }

    function initialize(address _owner) public initializer {
        owner = _owner;
    }
}
```

---

## 4. Token Integration Anti-Patterns

### Anti-Pattern 4.A: Fee-On-Transfer Imbalance
Assuming that calling `token.transferFrom(A, B, 100)` means that B will receive exactly 100 tokens. If the token takes a 5% transfer fee, B only receives 95. If the protocol rigidly accounts for 100, an insolvency gap is created.

**VULNERABLE CODE (BAD):**
```solidity
function deposit(uint256 amount) external {
    // Vulnerable: Assumes `amount` arrives intact
    token.transferFrom(msg.sender, address(this), amount);
    userBalance[msg.sender] += amount; // Accounts for 100, despite only 95 arriving
}
```

**CORRECT PATTERN (GOOD):**
```solidity
function deposit(uint256 amount) external {
    uint256 balanceBefore = token.balanceOf(address(this));
    token.transferFrom(msg.sender, address(this), amount);
    uint256 balanceAfter = token.balanceOf(address(this));
    
    // Good: Accounts only for exactly what arrived
    uint256 actualReceived = balanceAfter - balanceBefore; 
    userBalance[msg.sender] += actualReceived;
}
```
