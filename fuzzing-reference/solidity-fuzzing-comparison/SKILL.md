---
name: solidity-fuzzing-comparison
description: Reference and worked examples for comparing Solidity fuzzing tools (Foundry, Echidna, Medusa, etc.) on the same target contracts. Source from devdacian/solidity-fuzzing-comparison. Use when the user wants to learn or set up property-based / invariant / stateful fuzzing in Solidity, compare Foundry vs Echidna vs Medusa, write fuzz tests for a contract, or understand fuzzing patterns by example. The example Foundry project is copied to documents/personal-ZUp1aMpW/audit-references/solidity-fuzzing-comparison.
---

# Solidity Fuzzing Comparison (reference)

A teaching repo by devdacian that fuzzes the same example contracts with multiple tools so you can see equivalent setups side by side. Repo: https://github.com/devdacian/solidity-fuzzing-comparison

## Local copy

The full Foundry project (src/, test/, foundry.toml, lib/) is at:
`documents/personal-ZUp1aMpW/audit-references/solidity-fuzzing-comparison/`

Read the `README.md` there and the paired tests under `test/` to see how each example is fuzzed with Foundry's built-in fuzzer, Echidna, and Medusa.

## When to use

- The user asks "how do I write a fuzz/invariant test for this contract?"
- They want to choose between Foundry, Echidna, and Medusa.
- They want stateful invariant testing patterns (handlers, ghost variables, bounding inputs).

## How Sauna assists

1. Pull the relevant example from the local copy and adapt it to the user's contract.
2. Write Foundry invariant tests (`invariant_*`, handler contracts) or Echidna/Medusa property files.
3. Pair with the `foundry-poc` skill to turn a fuzzing failure into a clean PoC, and with the `ityfuzz` reference for hybrid fuzzing.

These tools (Foundry/Echidna/Medusa) run on the user's machine, not in Sauna. Sauna writes the tests and interprets results.
