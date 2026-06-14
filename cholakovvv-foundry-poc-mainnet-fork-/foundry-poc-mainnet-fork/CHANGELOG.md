# Changelog

All notable changes to this skill will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-04-23

Initial public release.

### Skill

- Six hard rules governing Foundry-only, real-contract, mainnet-fork, end-to-end execution
- Three-category classification system (frozen historical / forward-looking / both) with mandatory out-loud classification before any code is written
- Reading Order protection to prevent anchoring on stale PoC files
- Proof-shape guidance by impact type (theft, drain, freeze, DoS, access control)
- Rule 5 shortcut-documentation pattern for genuinely infeasible pipeline steps
- Style rules covering banned phrases, em-dashes, filler comments, and assertion message length
- Self-review checklist with 18 items

### Examples

- `Example_FreezeHistorical.t.sol`: category (a) reference, rewarder timelock bug shape
- `Example_RoutingDoS.t.sol`: category (b) reference, adapter logic error producing DoS and fund stranding
- `Example_PoolDrainTheft.t.sol`: category (b) reference, decimals-mismatch share inflation and pool drain

### Validation

- Three production bounty findings across four different codebases and three different bounty platforms
- Three structurally distinct bug shapes covered
- Last two validation runs produced submission-ready PoCs with zero skill revisions

[1.0.0]: https://github.com/your-handle/foundry-poc-mainnet-fork/releases/tag/v1.0.0
