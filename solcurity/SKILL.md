---
name: solcurity
description: The Solcurity Standard — an opinionated security and code-quality checklist for Solidity smart contracts (by transmissions11/Rari Capital). Use as a systematic line-by-line review checklist when auditing or hardening Solidity, covering variables, structs, functions, modifiers, code, external calls, static calls, events, contract-level, project-level, and general review approach. The full checklist is in reference/SOLCURITY.md.
---

# Solcurity Standard

Opinionated security + code-quality checklist for Solidity, widely used as an audit baseline. Repo: https://github.com/transmissions11/solcurity

## How to use

Read `reference/SOLCURITY.md` and walk its sections against the target contract:
- **General Review Approach** — docs/spec first, build a mental model, threat-model value-exchange functions (`transfer`, `call`, `delegatecall`, `selfdestruct`).
- Per-construct checklists: Variables, Structs, Functions, Modifiers, Code, External Calls, Static Calls, Events, Contract, Project, plus a general checklist.

Use it as a completeness backstop alongside the deeper engines (`context-skills/smart-contract-audit`, `pashov/solidity-auditor`, `plamen/evm/*`). Each item is a yes/no check; record misses as candidate findings and route them through `grimoire/finding-draft`.
