# Module Clustering Rules

## Goal

Cluster contracts into review modules using direct dependency and direct interaction edges.

## Core Idea

A module is a coherent contract-centered subgraph, not just a folder or naming convention.

Each module should contain:

- one or more core contracts
- direct dependencies required to reason about them
- direct interaction partners required to assess safety of state transitions

## Edge Types

Treat the following as module edges:

- import and inheritance edges
- constructor or initializer wiring of contract addresses
- persistent external contract references stored in state
- direct external calls to named contracts or interfaces
- mint/burn/transfer authority relationships

Do not expand indefinitely beyond direct edges unless the user explicitly requests deep graph expansion.

## Core Contract Heuristics

A contract is more likely to be a module core if it:

- exposes important external state-changing entry points
- owns or moves funds
- orchestrates multiple collaborators
- maintains key accounting state
- contains upgrade, governance, liquidation, or settlement logic

## Clustering Rules

- Start from candidate core contracts.
- Pull in direct dependencies and direct interaction partners.
- Merge clusters when two candidate modules share the same dominant accounting or control surface.
- Keep modules separate when the shared edge is narrow and auditable as a boundary.

## Cross-Module Boundaries

Preserve edges between modules for later review by `cross-module-agent`.

High-priority boundaries include:

- Lending <-> Oracle
- Vault <-> Strategy
- Bridge <-> Message Verifier
- Governance <-> Upgrade or Executor
- DEX <-> Oracle

## Output Schema

Return JSON with:

- `modules`: array of
  - `module_id`
  - `core_contracts`
  - `contracts`
  - `labels_present`
  - `boundary_edges`
