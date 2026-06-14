---
name: ityfuzz
description: Reference for ItyFuzz, a fast EVM + MoveVM hybrid fuzzer (fuzzing + symbolic execution) for finding smart-contract bugs on/offchain. ItyFuzz is a NATIVE binary that runs in the user's own dev/audit environment, NOT inside Sauna. Use this skill when the user wants to fuzz a contract, generate exploits, run invariant tests with ItyFuzz, fork a chain to fuzz a deployed contract, or asks how to install/use ItyFuzz. Sauna can help write configs, invariant tests, and interpret results, but the actual fuzzing must run on the user's machine.
---

# ItyFuzz (reference)

ItyFuzz is a blazing-fast EVM and MoveVM smart-contract **hybrid fuzzer** that combines symbolic execution and fuzzing to find bugs offchain and onchain. Backed by LibAFL. Repo: https://github.com/fuzzland/ityfuzz · Docs: https://docs.ityfuzz.rs

## Important: this is a native tool, not a Sauna capability

ItyFuzz is a compiled binary. It cannot run inside Sauna's sandbox. The user installs and runs it locally. Sauna's job here is to: scaffold invariant tests, build JSON/Foundry setup configs, choose flags, and interpret crash/exploit output the user pastes back.

## Install (on the user's machine)

```bash
curl -L https://ity.fuzz.land/ | bash
ityfuzzup
```

## Common usage

Fuzz a deployed contract by forking a chain:
```bash
ETH_RPC_URL=https://polygon-rpc.com ityfuzz evm \
    -t 0xTARGET1,0xTARGET2 \
    -c polygon \
    --flashloan \
    --onchain-block-number 35718198 \
    --onchain-etherscan-api-key YOUR_KEY
```

Run a Foundry invariant test (drop-in for `forge test --mc`):
```bash
ityfuzz evm -m test/Invariant.sol:Invariant -- forge test
```

## Key features to leverage when advising

- Chain forking at any block; decompilation support for source-less contracts.
- Flashloan + liquidation simulation (assumes attacker has infinite funds).
- Reentrancy-aware path exploration; symbolic execution for deeper coverage.
- Exploit generation for precision loss, integer overflow, fund stealing, Uniswap pair misuse.
- Init via Foundry setup script, forked Anvil RPC, or JSON config.

## How Sauna assists

1. Write/refine `Invariant` contracts and `setUp()` for Foundry-mode fuzzing.
2. Recommend flags for the target (flashloan, onchain block, chain id).
3. Interpret reported violations and draft a Foundry PoC reproducing them (pair with the `foundry-poc` skill).
4. Cross-reference findings against `solodit` and the audit-reference corpus.
