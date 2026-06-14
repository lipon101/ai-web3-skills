# Code Injection

Replace the bytecode at any address on a Tenderly fork.

## Set Code

```bash
cast rpc tenderly_setCode '"<address>"' '"<bytecode>"' --rpc-url $RPC_URL
```

`<bytecode>` is the deployed bytecode (runtime bytecode), prefixed with `0x`.

## Extracting Bytecode

### From a local Foundry project

```bash
forge inspect <ContractName> deployedBytecode
```

Returns the runtime bytecode as a hex string (no `0x` prefix — add it when passing to `tenderly_setCode`).

### From a live chain

```bash
cast code <address> --rpc-url <rpcUrl>
```

Returns the deployed bytecode at that address (with `0x` prefix).

### From a Forge broadcast JSON

```bash
jq -r '.deployedBytecode.object' out/<ContractName>.sol/<ContractName>.json
```

Or from a broadcast run:
```bash
jq -r '.transactions[0].transaction.input' broadcast/<Script>.s.sol/<chainId>/run-latest.json
```

Note: `.transaction.input` is the creation bytecode (includes constructor). For runtime bytecode, prefer `forge inspect` or `cast code` from a deployed instance.

## Verify

Compare code length before and after:

```bash
# Before
cast code <address> --rpc-url $RPC_URL | wc -c

# After injection
cast rpc tenderly_setCode '"<address>"' '"<bytecode>"' --rpc-url $RPC_URL
cast code <address> --rpc-url $RPC_URL | wc -c
```

Or compare the full bytecode:
```bash
DEPLOYED=$(cast code <address> --rpc-url $RPC_URL)
echo "$DEPLOYED" | head -c 100  # Spot-check the prefix
```

## Use Cases

### EIP-170 bypass for oversized contracts

Contracts exceeding 24,576 bytes cannot be deployed normally. On a Tenderly fork, inject the bytecode directly:

```bash
# Get the bytecode from Foundry
BYTECODE=$(forge inspect OversizedContract deployedBytecode)

# Inject at the desired address
cast rpc tenderly_setCode '"0xTargetAddress"' "\"0x$BYTECODE\"" --rpc-url $RPC_URL
```

### Replace a deployed contract with a modified version

Useful for testing patches against existing state:

```bash
# Build the modified contract
forge build

# Extract the new bytecode
BYTECODE=$(forge inspect ModifiedContract deployedBytecode)

# Inject over the existing deployment
cast rpc tenderly_setCode '"0xExistingDeployment"' "\"0x$BYTECODE\"" --rpc-url $RPC_URL
```

The storage at that address is preserved — only the code changes.

### Inject a mock or stub

Replace a dependency with a mock for testing:

```bash
MOCK_BYTECODE=$(forge inspect MockOracle deployedBytecode)
cast rpc tenderly_setCode '"0xRealOracleAddress"' "\"0x$MOCK_BYTECODE\"" --rpc-url $RPC_URL
```

### Copy a contract from one chain to another

```bash
# Extract from source chain
BYTECODE=$(cast code 0xContractOnMainnet --rpc-url $MAINNET_RPC)

# Inject on fork
cast rpc tenderly_setCode '"0xTargetAddress"' "\"$BYTECODE\"" --rpc-url $RPC_URL
```

Note: This copies only code, not storage. Combine with `tenderly_setStorageAt` to replicate full state.

## Important Notes

- **Storage is preserved**: `tenderly_setCode` only replaces the bytecode. Existing storage slots remain unchanged. This is useful for upgrading logic while keeping state, but be careful with storage layout changes.
- **Constructor not executed**: Since you're injecting runtime bytecode directly, the constructor does not run. Any initialization done in the constructor must be handled manually via storage manipulation.
- **Immutables are baked in**: Solidity immutables are embedded in the runtime bytecode at deploy time. If you `forge inspect` a contract with immutables, the bytecode will have placeholder values. Use `cast code` from a real deployment instead, or set the immutable slots manually.
