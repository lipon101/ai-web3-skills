---
name: solidity-audit
description: Use when performing a formal Solidity security review across mixed-protocol codebases, especially when contracts may belong to multiple protocol types and the review must produce a consolidated findings list and module-level audit conclusions.
---

# Solidity Formal Audit

## Overview

You are the orchestrator of a formal Solidity security audit. Your job is to:

1. discover in-scope contracts
2. classify each contract with one or more protocol labels
3. identify complexity, callback, and liveness-critical paths
4. identify mutable active-draw dependencies and unsnapshotted configuration
5. cluster contracts into modules using the contract dependency subgraph
6. spawn specialized audit agents per `contract x label`
7. merge results into a single findings list plus module-level conclusions

Do not try to perform the full audit alone if the codebase is non-trivial. This skill is built around specialized agents with narrow responsibilities.

## When To Use

Use this skill when:

- the target is a Solidity codebase with multiple contracts
- the review is intended to be a formal or near-formal security assessment
- the protocol may mix multiple domains such as DEX, Lending, Staking, Bridge, Governance, Oracle, or Vault
- the output must include both a global findings list and per-module conclusions

Do not use this skill for:

- a quick single-function bug triage
- linting, style review, or gas-only review
- small one-off code questions answerable from one contract

## Scope Rules

- Include Solidity source files with `.sol` suffix.
- Exclude common noise by default: `lib/`, `test/`, `tests/`, `mocks/`, `interfaces/`, `script/`, `broadcast/`.
- Also exclude files matching `*.t.sol`, `*Test*.sol`, `*Mock*.sol`, unless the user explicitly asks to include them.
- If the user names specific files or folders, treat those as the primary scope.
- Treat external dependencies as context, not findings scope, unless the user explicitly includes them.

## References

Read only what is needed at each stage:

- research routing stage:
  `references/workflow/research-triangulation.md`
- generic class mapping stage:
  `references/common/vulnerability-taxonomy.md`
- classification stage:
  `references/workflow/classification-rubric.md`
- module clustering stage:
  `references/workflow/module-clustering.md`
- feasibility stage:
  `references/workflow/complexity-feasibility.md`
- active lifecycle mutability stage:
  `references/workflow/active-draw-mutability.md`
- finding validation stage:
  `references/workflow/judging.md`
- final rendering stage:
  `references/workflow/report-format.md`
- protocol-specific analysis stage:
  `references/protocols/<label>.md`
- generic baseline analysis stage:
  `references/common/*.md`
- agent contracts:
  `references/agents/*.md`

## Workflow

### Stage 1: Discover

- Find in-scope Solidity contracts.
- Prefer `scripts/discover-contracts.sh` if present.
- Build a contract list with file path, declared contract names, and basic role hints from names.

### Stage 2: Graph Build

- Build a contract dependency and interaction graph.
- Prefer `scripts/build-contract-graph.py` if present.
- Capture direct imports, inheritance, constructor wiring, external contract fields, library usage, and obvious call edges.
- Keep the graph conservative: direct relationships first, not speculative long chains.

### Stage 3: Classification

- For each contract, run `classifier-agent`.
- Allowed labels:
  `DEX`, `Lending`, `Staking`, `Bridge`, `Governance`, `Oracle`, `Vault`
- Multi-label is allowed and expected.
- If no label is strong enough, route the contract to `Generic`.
- Classification must be evidence-based, not name-based alone.

### Stage 4: Feasibility And Complexity

- Identify settlement, callback, matching, liquidation, or queue-processing paths that may fail to execute at realistic chain gas limits.
- Treat keeper, oracle, bridge, and randomness callbacks as liveness-critical paths.
- Prefer `references/workflow/complexity-feasibility.md`.
- A gas finding is reportable only when it can break settlement, callback completion, withdrawals, governance actions, or another critical invariant.

### Stage 5: Active-Draw Mutability

- Identify global variables and external dependencies whose values can change during an active lifecycle window.
- For jackpot-like systems this includes draw-time, settlement-time, callback-time, claim-time, and emergency-time dependencies.
- Prefer `references/workflow/active-draw-mutability.md`.
- Explicitly check whether ticket pricing, fee parameters, payout calculators, entropy providers, bridge routes, and callback targets are snapshotted or read live.

### Stage 6: Module Clustering

- Group contracts into modules using the contract dependency subgraph.
- A module is a contract-centered cluster with core contracts plus direct dependencies and direct interaction partners.
- Prefer fewer, coherent modules over many tiny fragments.
- Keep cross-module edges so a later cross-module review can analyze them.

### Stage 7: Bundle Preparation

- For each `contract x label`, prepare a bundle containing:
  - the target contract
  - its direct dependency/interaction subgraph
  - `research-triangulation.md`
  - `vulnerability-taxonomy.md`
  - relevant common references
  - one protocol reference
  - feasibility and mutability workflow references when relevant
  - `judging.md`
- For unlabelled contracts, prepare a Generic bundle.
- For high-risk module edges, prepare a cross-module bundle.

### Stage 8: Audit Dispatch

- Spawn one `protocol-auditor-agent` per `contract x label`.
- Spawn one `generic-auditor-agent` for Generic contracts.
- Spawn `cross-module-agent` for risky module boundaries.
- Spawn `complexity-auditor-agent` for settlement, callback, matching, or queue-heavy paths.
- Spawn `mutable-dependency-agent` for active lifecycle systems where admin or provider changes can affect current state.
- Spawn `module-summarizer-agent` after findings exist for each module.
- Spawn `aggregator-agent` only after all prior results are available.

### Stage 9: Merge

- Merge by `root_cause_key`.
- Keep the highest-confidence version of duplicate findings.
- If two findings share a root cause but differ in scope, preserve the broader, better-evidenced version.
- Keep `confidence` separate from `severity`.
- Do not invent new findings during aggregation.

### Stage 10: Render

- Produce a final findings list.
- Produce module-level audit conclusions.
- Use `references/workflow/report-format.md`.
- If the user asks for file output, write the report under `assets/findings/`.

## Agent Routing Rules

- `classifier-agent` only classifies.
- `protocol-auditor-agent` only audits one `contract x label`.
- `generic-auditor-agent` audits Generic infrastructure contracts.
- `cross-module-agent` audits risky interactions between modules or labels.
- `complexity-auditor-agent` audits gas, callback, and liveness feasibility of critical paths.
- `mutable-dependency-agent` audits unsnapshotted globals and replaceable dependencies during active protocol lifecycles.
- `module-summarizer-agent` summarizes one module and adds no new findings.
- `aggregator-agent` only deduplicates, sorts, groups, and prepares report-ready output.

## Output Contract

All intermediate agents should return JSON only.

Every finding object must include:

- `title`
- `root_cause_key`
- `module_id`
- `labels`
- `location`
- `confidence`
- `severity`
- `broken_invariant`
- `description`
- `fix`
- `evidence`

## Hard Rules

- Do not skip Generic coverage for unclassified contracts.
- Do not collapse multiple labels into one if evidence supports multiple labels.
- Do not treat user-controlled external call targets as benign if the contract also custodies tokens, NFTs, approvals, or execution authority.
- Do not dismiss gas findings if they can block settlement, callback execution, claims, governance, or liveness.
- Do not assume admin changes are future-only; verify whether the active lifecycle reads snapshotted or live values.
- Do not report style issues, gas-only notes, or generic centralization observations without an exploit path.
- Do not ignore compiler, proxy-deployment, or hidden-callback classes when the bundle contains proxies, routers, token hooks, or version-sensitive code.
- Do not rewrite child-agent findings during merge unless normalization is strictly required for formatting.
- Do not treat confidence as severity.
