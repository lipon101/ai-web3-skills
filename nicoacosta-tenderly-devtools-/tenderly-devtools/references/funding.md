# Funding Operations

ETH and ERC20 balance manipulation on Tenderly forks.

## ETH Balance

### Set exact ETH balance

```bash
cast rpc tenderly_setBalance '"<address>"' '"<amountWei>"' --rpc-url $RPC_URL
```

Replaces the current balance entirely.

### Add to ETH balance

```bash
cast rpc tenderly_addBalance '"<address>"' '"<amountWei>"' --rpc-url $RPC_URL
```

Adds to the existing balance (does not replace).

### Verify ETH balance

```bash
cast balance <address> -e --rpc-url $RPC_URL
```

If Foundry MCP is available, `cast_balance` with `formatEther=true` also works.

## ERC20 Balance

### Set exact ERC20 balance

```bash
cast rpc tenderly_setErc20Balance '"<tokenAddress>"' '"<walletAddress>"' '"<amountWei>"' --rpc-url $RPC_URL
```

Note the parameter order: **token first, then wallet, then amount**.

### Max out ERC20 balance

```bash
cast rpc tenderly_setMaxErc20Balance '"<tokenAddress>"' '"<walletAddress>"' --rpc-url $RPC_URL
```

Sets balance to `type(uint256).max`. Useful when the exact amount doesn't matter.

### Verify ERC20 balance

```bash
cast call <tokenAddress> "balanceOf(address)(uint256)" <walletAddress> --rpc-url $RPC_URL
```

If Foundry MCP is available, `cast_call` with `functionSignature="balanceOf(address)(uint256)"` also works.

## Token Address Resolution

Token addresses vary by chain. Use `references/tokens.md` to look up the correct address and decimals for the detected chain. Always detect the chain first via `eth_chainId`.

## Hex Amount Conversion

### Universal (any decimals)

```bash
python3 -c "print(hex(int(<amount> * 10**<decimals>)))"
```

Examples:
```bash
# 10,000 USDC (6 decimals)
python3 -c "print(hex(int(10000 * 10**6)))"
# → 0x2540be400

# 50 UNI (18 decimals)
python3 -c "print(hex(int(50 * 10**18)))"
# → 0x2b5e3af16b1880000
```

### ETH shortcut (18 decimals only)

```bash
cast to-wei <amount> ether
```

This returns the decimal wei value. To get hex, pipe through:
```bash
python3 -c "print(hex($(cast to-wei <amount> ether)))"
```

## Parameter Format

**Critical**: Each parameter is a separate shell-quoted string. Do NOT pass a JSON array.

Correct:
```bash
cast rpc tenderly_setBalance '"0x1234..."' '"0xDE0B6B3A7640000"' --rpc-url $RPC_URL
```

Wrong:
```bash
# DO NOT do this
cast rpc tenderly_setBalance '["0x1234...", "0xDE0B6B3A7640000"]' --rpc-url $RPC_URL
```

## Common Hex Amounts

### ETH (18 decimals)

| Amount | Hex |
|--------|-----|
| 0.1 ETH | `0x16345785D8A0000` |
| 1 ETH | `0xDE0B6B3A7640000` |
| 10 ETH | `0x8AC7230489E80000` |
| 100 ETH | `0x56BC75E2D63100000` |
| 1,000 ETH | `0x3635C9ADC5DEA00000` |

### USDC (6 decimals)

| Amount | Hex |
|--------|-----|
| 100 USDC | `0x5F5E100` |
| 1,000 USDC | `0x3B9ACA00` |
| 10,000 USDC | `0x2540BE400` |
| 100,000 USDC | `0x174876E800` |
| 1,000,000 USDC | `0xE8D4A51000` |

### USDT / DAI (varies)

USDT uses 6 decimals (same hex as USDC). DAI uses 18 decimals (same hex as ETH amounts).

## Examples

### Fund an address with 100 ETH

```bash
cast rpc tenderly_setBalance '"0xYourAddress"' '"0x56BC75E2D63100000"' --rpc-url $RPC_URL
```

Verify:
```bash
cast balance 0xYourAddress -e --rpc-url $RPC_URL
```

### Give an address 10,000 USDC (after resolving address from tokens.md)

```bash
# 1. Detect chain
cast rpc eth_chainId --rpc-url $RPC_URL

# 2. Look up USDC address for that chain in references/tokens.md

# 3. Compute hex: python3 -c "print(hex(int(10000 * 10**6)))" → 0x2540be400

# 4. Execute
cast rpc tenderly_setErc20Balance '"<USDC_ADDRESS>"' '"0xYourAddress"' '"0x2540BE400"' --rpc-url $RPC_URL
```

Verify:
```bash
cast call <USDC_ADDRESS> "balanceOf(address)(uint256)" 0xYourAddress --rpc-url $RPC_URL
```
