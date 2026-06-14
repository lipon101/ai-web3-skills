---
name: suizero
description: Reference for SUIZERO, a static analysis engine for Sui Move smart contracts (330+ detectors over compiled bytecode + semantic execution patterns). SUIZERO is a standalone tool the user runs in their own environment, NOT inside Sauna. Use when the user wants to scan Sui Move contracts for phantom authorization, temporal/race bugs, economic invariant breaks, oracle/randomness manipulation, state-machine violations, or upgradeability issues, or asks how to install/run SUIZERO. Sauna helps install it, shape scans, and interpret findings.
---

# SUIZERO (reference)

Static analysis engine purpose-built for the Sui Move ecosystem. Analyzes compiled bytecode and semantic execution patterns (beyond linting), with 330+ specialized detectors. Repo: https://github.com/kaveyjoe/SUIZERO

## Important: standalone tool, not a Sauna capability

SUIZERO runs in the user's environment. Sauna's role: help install it, choose what to scan, and interpret/triage the JSON findings.

## Detection highlights

- Phantom authorization (params that look like checks but are ignored)
- Temporal bugs / race conditions between object inspection and mutation
- Economic invariant breaks (deposit/withdraw asymmetries)
- Predictable randomness, single-point oracle manipulation
- Invalid state-machine transitions
- Upgradeability issues (missing init guards, unauthorized upgrade access)
- MEV / front-running (auction & slippage manipulation)

## Usage

Install per the repo README (system dependencies + build), then run its analyzer against a compiled Sui Move package. Check the repo's `docs/` for CLI flags and the validation report.

## How Sauna assists

1. Walk through install/build from the README.
2. Help select target packages and interpret detector output.
3. Cross-reference findings with the Plamen Sui skills and `context-skills/smart-contract-audit`, and draft findings via `grimoire/finding-draft`.
