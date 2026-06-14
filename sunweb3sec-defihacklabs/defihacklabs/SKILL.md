---
name: defihacklabs
description: Reference to DeFiHackLabs (SunWeb3Sec/DeFiHackLabs) — a large corpus of reproduced real-world DeFi exploits as runnable Foundry PoCs, organized by date and protocol. Points to the GitHub repo (large, not vendored) and explains how to mine it for attack patterns, PoC scaffolds, and post-mortems. Use when the user wants to study how a specific hack worked, find a Foundry PoC template for an attack class (reentrancy, price manipulation, flash loan), or learn exploit reproduction technique.
---

# DeFiHackLabs (reference)

The largest open collection of reproduced on-chain DeFi exploits, each as a self-contained Foundry test that forks mainnet at the incident block and replays the attack. Repo: https://github.com/SunWeb3Sec/DeFiHackLabs (~13MB, hundreds of PoCs — fetch specific files on demand).

## How to use

1. Find the incident by date/protocol in the repo's `src/test/` directory (filenames are `YYYY-MM/<Protocol>_exp.sol`).
2. Fetch the specific PoC via `webfetch` / raw GitHub URL to study the setup, the exploit steps, and the assertions.
3. Reuse the fork-test pattern as a template for your own PoC.

The companion `academy`/`reading` lists in the repo are good for attack-class theory. Pair with `cholakovvv-foundry-poc-mainnet-fork`, `context-skills/foundry-poc`, and `grimoire/write-poc` to build a reproduction for the contract under review.

Reference material — the Foundry tests run on the user's machine.
