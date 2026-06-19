# VeerSkills Anti-Pattern Library

_Consolidated dangerous code patterns to scan for during the HUNT phase. Each anti-pattern shows the WRONG way and the RIGHT way._

---

## 1. Reentrancy Anti-Patterns

### 1.1 Classic CEI Violation
```solidity
// ❌ WRONG: External call before state update
function withdraw(uint256 amount) external {
    require(balances[msg.sender] >= amount);
    (bool ok,) = msg.sender.call{value: amount}("");  // external call
    balances[msg.sender] -= amount;  // state update AFTER
}

// ✅ RIGHT: State update before external call (CEI)
function withdraw(uint256 amount) external {
    require(balances[msg.sender] >= amount);
    balances[msg.sender] -= amount;  // state update FIRST
    (bool ok,) = msg.sender.call{value: amount}("");
}
```

### 1.2 Cross-Function Reentrancy
```solidity
// ❌ WRONG: Function A calls external, Function B reads shared state
function deposit() external { /* updates totalShares */ }
function claimReward() external {
    uint256 reward = calcReward(totalShares);  // reads shared state
    token.transfer(msg.sender, reward);  // external call
    lastClaim[msg.sender] = block.timestamp;
}
// Attacker: deposit callback → claimReward reads stale totalShares

// ✅ RIGHT: Shared mutex across all functions touching shared state
```

### 1.3 Read-Only Reentrancy
```solidity
// ❌ WRONG: View function returns stale value during callback
function getVirtualPrice() external view returns (uint256) {
    return totalAssets / totalShares;  // stale during add_liquidity callback
}
// External protocol uses getVirtualPrice() for pricing → manipulated

// ✅ RIGHT: NonReentrant on view functions, or cross-contract lock
```

### 1.4 ERC777/ERC721/ERC1155 Callback Reentrancy
```solidity
// ❌ WRONG: safeTransferFrom before state update
token.safeTransferFrom(from, to, amount);  // triggers onERC721Received
updateState();

// ✅ RIGHT: Update state, then safe transfer
updateState();
token.safeTransferFrom(from, to, amount);
```

---

## 2. Oracle Anti-Patterns

### 2.1 Spot Price as Oracle
```solidity
// ❌ WRONG: Using AMM reserves for pricing
uint256 price = reserve0 / reserve1;  // manipulable via flash loan
uint256 price = router.getAmountsOut(1e18, path)[1];  // same problem

// ✅ RIGHT: TWAP >= 30 min or Chainlink/Pyth
```

### 2.2 Missing Staleness Check
```solidity
// ❌ WRONG: No validation on oracle data
(,int256 price,,,) = feed.latestRoundData();
return uint256(price);

// ✅ RIGHT: Full validation
(uint80 roundId, int256 price,, uint256 updatedAt, uint80 answeredInRound) = feed.latestRoundData();
require(price > 0, "Invalid price");
require(updatedAt > block.timestamp - MAX_STALENESS, "Stale price");
require(answeredInRound >= roundId, "Stale round");
```

### 2.3 Wrong Decimals
```solidity
// ❌ WRONG: Assuming 8 decimals
uint256 priceInUsd = uint256(answer) * 1e10;  // assumes 8 decimals

// ✅ RIGHT: Query decimals dynamically
uint8 decimals = feed.decimals();
uint256 priceInUsd = uint256(answer) * 10**(18 - decimals);
```

### 2.4 Missing L2 Sequencer Check
```solidity
// ❌ WRONG: No sequencer check on L2
(,int256 price,,,) = feed.latestRoundData();  // on Arbitrum/Optimism

// ✅ RIGHT: Check sequencer uptime first
(,int256 answer,, uint256 startedAt,) = sequencerFeed.latestRoundData();
require(answer == 0, "Sequencer down");
require(block.timestamp - startedAt > GRACE_PERIOD, "Grace period");
```

---

## 3. Access Control Anti-Patterns

### 3.1 Missing Modifier
```solidity
// ❌ WRONG: No access control on critical function
function setOracle(address _oracle) external {
    oracle = _oracle;  // anyone can change oracle
}

// ✅ RIGHT: Access controlled
function setOracle(address _oracle) external onlyOwner {
    oracle = _oracle;
}
```

### 3.2 Unprotected Initialize
```solidity
// ❌ WRONG: initialize callable by anyone, no disableInitializers
contract VaultV1 is Initializable {
    function initialize(address _owner) external initializer {
        owner = _owner;
    }
}

// ✅ RIGHT: _disableInitializers in constructor
constructor() { _disableInitializers(); }
```

### 3.3 tx.origin Auth
```solidity
// ❌ WRONG: tx.origin for authentication
require(tx.origin == owner, "Not owner");  // phishable

// ✅ RIGHT: msg.sender for authentication
require(msg.sender == owner, "Not owner");
```

---

## 4. Token Handling Anti-Patterns

### 4.1 Fee-on-Transfer Not Handled
```solidity
// ❌ WRONG: Assumes received == amount
token.transferFrom(msg.sender, address(this), amount);
deposits[msg.sender] += amount;  // may be more than received

// ✅ RIGHT: Measure actual received
uint256 before = token.balanceOf(address(this));
token.transferFrom(msg.sender, address(this), amount);
uint256 received = token.balanceOf(address(this)) - before;
deposits[msg.sender] += received;
```

### 4.2 USDT Approve Pattern
```solidity
// ❌ WRONG: Direct approve (fails for USDT)
token.approve(spender, amount);  // USDT reverts if allowance != 0

// ✅ RIGHT: SafeERC20 forceApprove or approve(0) first
SafeERC20.forceApprove(token, spender, amount);
```

### 4.3 Unchecked Return Value
```solidity
// ❌ WRONG: Ignoring transfer return value
token.transfer(to, amount);  // silent failure possible

// ✅ RIGHT: SafeERC20
SafeERC20.safeTransfer(token, to, amount);
```

### 4.4 Rebasing Token Caching
```solidity
// ❌ WRONG: Caching balance of rebasing token
cachedBalance = stETH.balanceOf(address(this));  // becomes stale after rebase

// ✅ RIGHT: Use wrapper (wstETH) or read live balance
```

---

## 5. Math/Precision Anti-Patterns

### 5.1 Division Before Multiplication
```solidity
// ❌ WRONG: Truncation amplified
uint256 fee = (amount / 10000) * bps;  // loses precision

// ✅ RIGHT: Multiply first
uint256 fee = (amount * bps) / 10000;
```

### 5.2 Unsafe Downcast
```solidity
// ❌ WRONG: Silent truncation
uint128 smallAmount = uint128(largeUint256);  // truncates if > 2^128

// ✅ RIGHT: SafeCast
uint128 smallAmount = SafeCast.toUint128(largeUint256);
```

### 5.3 Wrong Rounding Direction
```solidity
// ❌ WRONG: Rounding in user's favor
shares = assets * totalSupply / totalAssets;  // rounds DOWN on deposit (user gets less — correct)
assets = shares * totalAssets / totalSupply;  // rounds DOWN on withdraw (user gets less — WRONG, should round UP for vault safety)

// ✅ RIGHT: Vault-favorable rounding
// Deposit: Math.mulDiv(assets, totalSupply, totalAssets, Math.Rounding.Floor)
// Withdraw: Math.mulDiv(shares, totalAssets, totalSupply, Math.Rounding.Ceil)
```

---

## 6. Flash Loan Anti-Patterns

### 6.1 Spot-Price Dependency
```solidity
// ❌ WRONG: Reading reserves (manipulable in same tx)
uint256 price = uniPair.getReserves();  // flash loan → swap → read → exploit

// ✅ RIGHT: TWAP or external oracle
```

### 6.2 Current-Block Snapshot
```solidity
// ❌ WRONG: Voting with current balance
uint256 votes = token.balanceOf(msg.sender);  // flash-loan borrowable

// ✅ RIGHT: Historical snapshot
uint256 votes = token.getPastVotes(msg.sender, block.number - 1);
```

---

## 7. Proxy/Upgrade Anti-Patterns

### 7.1 Non-Atomic Initialize
```solidity
// ❌ WRONG: Deploy and init in separate txs
proxy = new TransparentUpgradeableProxy(impl, admin, "");  // empty data
proxy.initialize(owner);  // separate tx — front-runnable

// ✅ RIGHT: Atomic init
proxy = new TransparentUpgradeableProxy(impl, admin, abi.encodeCall(Impl.initialize, (owner)));
```

### 7.2 Storage Layout Shift
```solidity
// ❌ WRONG: Inserting variable in middle of V2
contract V1 { uint256 a; uint256 b; uint256 c; }
contract V2 { uint256 a; uint256 NEW; uint256 b; uint256 c; }  // b,c shifted!

// ✅ RIGHT: Append only
contract V2 { uint256 a; uint256 b; uint256 c; uint256 NEW; }
```

### 7.3 Missing _authorizeUpgrade
```solidity
// ❌ WRONG: Empty authorization
function _authorizeUpgrade(address) internal override {}  // ANYONE can upgrade

// ✅ RIGHT: Proper access control
function _authorizeUpgrade(address) internal override onlyOwner {}
```

---

## 8. Signature Anti-Patterns

### 8.1 Missing Nonce
```solidity
// ❌ WRONG: No nonce in signed data
bytes32 hash = keccak256(abi.encode(action, amount, deadline));

// ✅ RIGHT: Include nonce + chainId
bytes32 hash = keccak256(abi.encode(action, amount, deadline, nonces[signer]++, block.chainid));
```

### 8.2 abi.encodePacked Collision
```solidity
// ❌ WRONG: Dynamic types with encodePacked
keccak256(abi.encodePacked(string1, string2));  // "ab","c" == "a","bc"

// ✅ RIGHT: abi.encode for dynamic types
keccak256(abi.encode(string1, string2));
```

### 8.3 Missing Sender Binding
```solidity
// ❌ WRONG: Merkle leaf without msg.sender
bytes32 leaf = keccak256(abi.encodePacked(amount));  // front-runnable

// ✅ RIGHT: Bind to caller
bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));
```

---

## 9. Cross-Chain Anti-Patterns

### 9.1 Missing Peer Validation
```solidity
// ❌ WRONG: No origin validation
function lzReceive(Origin calldata _origin, bytes calldata _message) external {
    _processMessage(_message);  // anyone can call with fake message
}

// ✅ RIGHT: Validate endpoint + peer
require(msg.sender == address(endpoint), "Not endpoint");
require(_origin.sender == peers[_origin.srcEid], "Unknown peer");
```

### 9.2 Missing Rate Limits
```solidity
// ❌ WRONG: Unlimited cross-chain transfers
function _credit(address to, uint256 amount) internal {
    _mint(to, amount);  // no cap — single exploit drains everything
}

// ✅ RIGHT: Rate-limited with circuit breaker
require(amount <= maxPerTx, "Exceeds per-tx limit");
require(windowTotal + amount <= maxPerWindow, "Exceeds window limit");
```

---

## 10. DoS Anti-Patterns

### 10.1 Unbounded Loop
```solidity
// ❌ WRONG: User-growable array
for (uint i = 0; i < users.length; i++) { /* process */ }

// ✅ RIGHT: Bounded with MAX or pagination
require(users.length <= MAX_USERS);
```

### 10.2 Push Payment to Unknown Address
```solidity
// ❌ WRONG: Reverting recipient blocks everyone
for (uint i = 0; i < recipients.length; i++) {
    payable(recipients[i]).transfer(amounts[i]);  // one revert blocks all
}

// ✅ RIGHT: Pull pattern or try/catch
mapping(address => uint256) pendingWithdrawals;
function claim() external { /* pull pattern */ }
```

---

## 11. Assembly Anti-Patterns

### 11.1 Missing Return Data Check
```solidity
// ❌ WRONG: No returndatasize check
assembly {
    let success := staticcall(gas(), token, ptr, 4, ptr, 32)
    let result := mload(ptr)  // reads stale memory if returndatasize < 32
}

// ✅ RIGHT: Check returndatasize
assembly {
    let success := staticcall(gas(), token, ptr, 4, ptr, 32)
    if lt(returndatasize(), 32) { revert(0, 0) }
    let result := mload(ptr)
}
```

### 11.2 Free Memory Pointer Corruption
```solidity
// ❌ WRONG: Writing to fixed offset without updating fmp
assembly { mstore(0x80, value) }  // overwrites Solidity allocation region

// ✅ RIGHT: Use free memory pointer
assembly {
    let ptr := mload(0x40)
    mstore(ptr, value)
    mstore(0x40, add(ptr, 0x20))  // update fmp
}
```

### 11.3 Dirty Higher-Order Bits
```solidity
// ❌ WRONG: No mask on address from calldata
assembly { let addr := calldataload(4) }  // upper 96 bits may be dirty

// ✅ RIGHT: Mask to 160 bits
assembly { let addr := and(calldataload(4), 0xffffffffffffffffffffffffffffffffffffffff) }
```

---

## 12. DeFi Composability Anti-Patterns

### 12.1 Hardcoded External Protocol Behavior
```solidity
// ❌ WRONG: Assumes external protocol never changes
uint256 fee = IProtocol(PROTOCOL).fee();  // hardcoded assumption: fee <= 1%
uint256 netAmount = amount - (amount * fee / 10000);
// Protocol upgrades fee to 5% → netAmount calculation breaks

// ✅ RIGHT: Validate external return values
uint256 fee = IProtocol(PROTOCOL).fee();
require(fee <= MAX_EXPECTED_FEE, "Fee exceeds safety bound");
```

### 12.2 Unvalidated External Return Data
```solidity
// ❌ WRONG: Trusting external protocol return value
(bool success, bytes memory data) = externalProtocol.call(payload);
require(success);
uint256 returnedAmount = abi.decode(data, (uint256));
deposits[user] += returnedAmount;  // blindly trusts external value

// ✅ RIGHT: Measure actual balance change
uint256 before = token.balanceOf(address(this));
(bool success,) = externalProtocol.call(payload);
require(success);
uint256 after = token.balanceOf(address(this));
deposits[user] += after - before;  // verify actual received
```

### 12.3 External Protocol Pause/Upgrade Survival
```solidity
// ❌ WRONG: No fallback when external protocol pauses
function withdraw() external {
    uint256 assets = IStrategy(strategy).redeem(shares);  // reverts if strategy paused
    token.transfer(msg.sender, assets);  // never reached
}

// ✅ RIGHT: Graceful degradation
function withdraw() external {
    try IStrategy(strategy).redeem(shares) returns (uint256 assets) {
        token.transfer(msg.sender, assets);
    } catch {
        // Fallback: return deposited amount minus fee
        _emergencyWithdraw(msg.sender, shares);
    }
}
```

---

## 13. Permit Anti-Patterns

### 13.1 No try/catch on Permit (Front-Running Griefing)
```solidity
// ❌ WRONG: Permit reverts entire tx if front-run
function depositWithPermit(uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
    token.permit(msg.sender, address(this), amount, deadline, v, r, s);  // reverts if front-run
    token.transferFrom(msg.sender, address(this), amount);
}

// ✅ RIGHT: Graceful permit handling
function depositWithPermit(uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
    try token.permit(msg.sender, address(this), amount, deadline, v, r, s) {} catch {}
    // Permit may have been front-run, but allowance might already exist
    token.transferFrom(msg.sender, address(this), amount);
}
```

### 13.2 Permit with Max Deadline
```solidity
// ❌ WRONG: Permanent authorization
token.permit(owner, spender, amount, type(uint256).max, v, r, s);
// Leaked signature = permanent drain authority

// ✅ RIGHT: Short-lived permit
token.permit(owner, spender, amount, block.timestamp + 1 hours, v, r, s);
```

---

## 14. ERC4626 Anti-Patterns

### 14.1 Wrong maxDeposit When Paused
```solidity
// ❌ WRONG: Reports max deposit even when paused
function maxDeposit(address) public view returns (uint256) {
    return type(uint256).max;  // always reports max, even when paused
}
// Integrating protocol calls maxDeposit → gets max → calls deposit → reverts

// ✅ RIGHT: Respect paused state
function maxDeposit(address) public view returns (uint256) {
    return paused() ? 0 : type(uint256).max;
}
```

### 14.2 Missing Dead Shares (First Depositor Attack)
```solidity
// ❌ WRONG: No inflation protection
function _convertToShares(uint256 assets) internal view returns (uint256) {
    return totalSupply == 0 ? assets : assets * totalSupply / totalAssets;
    // First depositor: deposit 1 wei → donate 1e18 → next depositor gets 0 shares
}

// ✅ RIGHT: Virtual shares offset (OZ approach)
function _convertToShares(uint256 assets) internal view returns (uint256) {
    return Math.mulDiv(assets + 1, totalSupply + 10 ** _decimalsOffset(), totalAssets + 1);
}
```

### 14.3 Preview/Actual Divergence
```solidity
// ❌ WRONG: previewDeposit doesn't match deposit
function previewDeposit(uint256 assets) public view returns (uint256) {
    return _convertToShares(assets);  // doesn't account for fees
}
function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
    uint256 fee = assets * feeRate / 10000;
    shares = _convertToShares(assets - fee);  // fee applied here but not in preview!
}

// ✅ RIGHT: Preview matches actual
function previewDeposit(uint256 assets) public view returns (uint256) {
    uint256 fee = assets * feeRate / 10000;
    return _convertToShares(assets - fee);  // same logic as deposit
}
```
