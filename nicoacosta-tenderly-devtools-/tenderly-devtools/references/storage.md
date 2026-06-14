# Storage Manipulation

Read and write arbitrary storage slots on Tenderly forks.

## Set Storage Slot

```bash
cast rpc tenderly_setStorageAt '"<contractAddress>"' '"<slot>"' '"<value>"' --rpc-url $RPC_URL
```

All three params are hex-encoded, 32-byte padded.

## Read Before Write

Always read the current value first to understand what you're overwriting:

```bash
cast storage <contractAddress> <slot> --rpc-url $RPC_URL
```

This uses the standard `eth_getStorageAt` RPC method (not Tenderly-specific).

## Verify After Write

Read the slot again after writing to confirm the change took effect:

```bash
cast storage <contractAddress> <slot> --rpc-url $RPC_URL
```

## Slot Calculation

### Simple variables

Storage slot = declaration index in the contract. First `uint256` is slot 0, second is slot 1, etc.

```solidity
contract Example {
    uint256 public value;    // slot 0
    address public owner;    // slot 1
    bool public paused;      // slot 2
}
```

To set `owner` to `0xNewOwner`:
```bash
cast rpc tenderly_setStorageAt '"<contractAddr>"' '"0x1"' '"0x000000000000000000000000<NewOwnerWithout0x>"' --rpc-url $RPC_URL
```

Note: addresses are left-padded to 32 bytes (right-aligned in the slot).

### Packed variables

Multiple small variables can share a slot. `bool` (1 byte), `uint8` (1 byte), `address` (20 bytes) may pack together. Use `forge inspect <Contract> storage-layout` to see exact slot assignments.

### Mappings

For `mapping(KeyType => ValueType)` at base slot `s`, the slot for key `k` is:

```
slot = keccak256(abi.encode(k, s))
```

Compute with cast:
```bash
cast keccak256 $(cast abi-encode "f(address,uint256)" "0xKeyAddress" "0xBaseSlot")
```

Example — `mapping(address => uint256) public balances` at slot 3, key `0xABCD...`:
```bash
SLOT=$(cast keccak256 $(cast abi-encode "f(address,uint256)" "0xABCD..." "3"))
cast rpc tenderly_setStorageAt '"<contractAddr>"' "\"$SLOT\"" '"0x0000000000000000000000000000000000000000000000000DE0B6B3A7640000"' --rpc-url $RPC_URL
```

### Nested mappings

For `mapping(A => mapping(B => V))` at base slot `s`, key pair `(a, b)`:

```
innerSlot = keccak256(abi.encode(a, s))
finalSlot = keccak256(abi.encode(b, innerSlot))
```

### Dynamic arrays

For `uint256[] public items` at slot `s`:
- Length stored at slot `s`
- Element `i` stored at `keccak256(s) + i`

```bash
# Get base data slot
BASE=$(cast keccak256 $(cast abi-encode "f(uint256)" "0xSlotNumber"))
# Element 0 is at $BASE, element 1 is at $BASE + 1, etc.
```

### Strings and bytes

Short strings (< 32 bytes) store data and length in the same slot. Long strings store length at slot `s` and data starting at `keccak256(s)`.

## Copy Pattern

Read state from a live chain and replicate it on the fork:

```bash
# Read from mainnet
VALUE=$(cast storage <contractAddr> <slot> --rpc-url $MAINNET_RPC)

# Write to fork
cast rpc tenderly_setStorageAt '"<contractAddr>"' '"<slot>"' "\"$VALUE\"" --rpc-url $FORK_RPC
```

## Storage Layout Inspection

Use Foundry to inspect a contract's storage layout:

```bash
forge inspect <ContractName> storage-layout
```

This shows each variable's slot, offset, and type. Essential for computing the right slot to modify.

## Examples

### Set an ERC20 balance via storage (when `tenderly_setErc20Balance` doesn't work)

Some tokens have non-standard storage layouts. Find the balances mapping slot, then set directly:

```bash
# 1. Find the balances slot (usually slot 0 or slot 2 for OZ ERC20)
forge inspect MyToken storage-layout

# 2. Compute the slot for the target address
SLOT=$(cast keccak256 $(cast abi-encode "f(address,uint256)" "0xTargetAddr" "0"))

# 3. Set the value (e.g., 1M tokens with 18 decimals)
cast rpc tenderly_setStorageAt '"<tokenAddr>"' "\"$SLOT\"" '"0x00000000000000000000000000000000000000000000D3C21BCECCEDA1000000"' --rpc-url $RPC_URL
```

### Toggle a boolean (e.g., unpause a contract)

```bash
# Set slot 2 (paused) to false (0)
cast rpc tenderly_setStorageAt '"<contractAddr>"' '"0x2"' '"0x0000000000000000000000000000000000000000000000000000000000000000"' --rpc-url $RPC_URL

# Set to true (1)
cast rpc tenderly_setStorageAt '"<contractAddr>"' '"0x2"' '"0x0000000000000000000000000000000000000000000000000000000000000001"' --rpc-url $RPC_URL
```
