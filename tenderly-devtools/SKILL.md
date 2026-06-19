---
name: tenderly-devtools
description: >
  Use when working with Tenderly forks and need to manipulate chain state.
  Triggers on "fund address", "set balance", "set ERC20 balance",
  "inject code", "set storage", "tenderly cheat codes", "tenderly fork setup",
  "fund USDC", "fund UNI", "token address", "which chain".
---

# Tenderly DevTools

## Overview

Cheat codes for Tenderly forks — fund addresses, manipulate storage, inject bytecode. All operations use `cast rpc` via the Bash tool with Tenderly-specific RPC methods.

## Workflow

1. **Discover RPC** — Find the Tenderly fork URL (see RPC Discovery below)
2. **Detect chain** — `cast rpc eth_chainId --rpc-url $RPC_URL` → parse hex result → look up in `references/tokens.md`
   - If chain ID not in registry: likely a Tenderly custom ID. Check `CLAUDE.md` or ask user which chain is forked.
3. **Resolve token** — If the user names a token (e.g., "UNI"), load `references/tokens.md`, find the entry for detected chain + symbol → get address + decimals
   - If token not found on this chain: tell user and ask for address + decimals
4. **Compute hex amount** — `python3 -c "print(hex(int(<amount> * 10**<decimals>)))"`
5. **Load reference** — Read the appropriate reference file for detailed syntax
6. **Execute** — Run `cast rpc` via Bash tool
7. **Verify** — Confirm the mutation took effect (see Verification table below)

## RPC Discovery

Before any operation, determine the fork RPC URL:

1. **Check `.mcp.json`** in the project root for `mcpServers.foundry.env.RPC_URL`
2. **Check `.env`** files for `RPC_URL`, `TENDERLY_FORK_URL`, or similar
3. **Check `CLAUDE.md`** for documented fork URLs
4. **Ask the user** if none found

Store the RPC URL in a variable for reuse:
```bash
RPC_URL="<discovered-url>"
```

## Chain Detection

After discovering the RPC URL, always detect the chain before any token operation:

```bash
cast rpc eth_chainId --rpc-url $RPC_URL
```

The result is a hex string (e.g., `"0x2105"` = 8453 = Base). Convert to decimal and look up in `references/tokens.md`.

**Tenderly custom chain IDs**: Tenderly forks may have a custom chain ID different from the original chain (e.g., 845302 for a Base fork). If the detected chain ID is not in the token registry, check `CLAUDE.md` for documentation about which chain the fork targets, or ask the user.

## Token Resolution

When the user references a token by name (e.g., "fund 10 UNI"):

1. Read `references/tokens.md`
2. Find the section for the detected chain ID
3. Look up the token symbol → get address + decimals
4. If not found, tell the user and ask for the address + decimals

## Hex Amount Conversion

```bash
# Universal: works for any decimals
python3 -c "print(hex(int(<amount> * 10**<decimals>)))"

# ETH shortcut (18 decimals only)
cast to-wei <amount> ether
```

## Quick Reference

| Method | Syntax | Ref |
|--------|--------|-----|
| `tenderly_setBalance` | `cast rpc tenderly_setBalance '"<addr>"' '"<weiHex>"' --rpc-url $RPC` | `references/funding.md` |
| `tenderly_addBalance` | `cast rpc tenderly_addBalance '"<addr>"' '"<weiHex>"' --rpc-url $RPC` | `references/funding.md` |
| `tenderly_setErc20Balance` | `cast rpc tenderly_setErc20Balance '"<token>"' '"<wallet>"' '"<weiHex>"' --rpc-url $RPC` | `references/funding.md` |
| `tenderly_setMaxErc20Balance` | `cast rpc tenderly_setMaxErc20Balance '"<token>"' '"<wallet>"' --rpc-url $RPC` | `references/funding.md` |
| `tenderly_setStorageAt` | `cast rpc tenderly_setStorageAt '"<addr>"' '"<slot>"' '"<value>"' --rpc-url $RPC` | `references/storage.md` |
| `tenderly_setCode` | `cast rpc tenderly_setCode '"<addr>"' '"<bytecode>"' --rpc-url $RPC` | `references/code-injection.md` |

**Parameter format**: Each param is a separate shell-quoted string (`'"0x..."'`). Never pass a JSON array.

## Common Hex Values

See [funding.md](references/funding.md#common-hex-amounts) for pre-computed ETH and USDC hex values.

## Verification

**After every mutation, verify the state changed.** Use Bash commands as primary verification:

| Operation | Verification (Bash) |
|-----------|---------------------|
| ETH balance | `cast balance <addr> -e --rpc-url $RPC_URL` |
| ERC20 balance | `cast call <token> "balanceOf(address)(uint256)" <addr> --rpc-url $RPC_URL` |
| Storage slot | `cast storage <addr> <slot> --rpc-url $RPC_URL` |
| Code injection | `cast code <addr> --rpc-url $RPC_URL` (check length or prefix) |

Note: If Foundry MCP is available, `cast_balance` and `cast_call` MCP tools also work.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| JSON array params `'["0x...", "0x..."]'` | Each param is a separate shell-quoted string `'"0x..."' '"0x..."'` |
| Truncated hex amounts | Use `python3 -c "print(hex(int(amount * 10**decimals)))"` — don't hand-compute |
| Wrong token address for chain | Always detect chain via `eth_chainId` first, then look up in `references/tokens.md` |
| Skipping verification after mutation | Always verify — see Verification table above |
| Using Tenderly fork's custom chain ID as real chain ID | Tenderly forks may remap chain IDs — check CLAUDE.md or ask user for the source chain |

## Reference Routing

Load the appropriate reference when you need detailed guidance:

- **Token registry** (addresses, decimals per chain) → Read `references/tokens.md`
- **Funding** (ETH/ERC20 balances, hex amounts) → Read `references/funding.md`
- **Storage** (slot math, mappings, packed vars, copy patterns) → Read `references/storage.md`
- **Code injection** (bytecode extraction, EIP-170 bypass, mocks) → Read `references/code-injection.md`
