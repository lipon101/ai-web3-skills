---
name: trident-fuzz
description: Guide setting up invariant-driven stateful fuzz tests for Solana/Anchor programs using Trident (v0.12.0). Use when the user wants to build a Trident fuzz harness, derive invariants, write fuzz flows, or run/triage a Trident campaign on a Solana program. Triggers on "trident", "fuzz my solana program", "anchor fuzz test", "invariant fuzzing solana". The full 5-phase methodology lives in reference/.
---

# Trident Fuzz (Solana/Anchor stateful fuzzing)

Source: han-sec/trident-fuzz-skill. Builds invariant-driven stateful fuzz harnesses for Solana/Anchor programs with [Trident](https://github.com/Ackee-Blockchain/trident) v0.12.0. Not a crash fuzzer — it proves properties hold across all reachable states.

## How to use

Work the phases in order; read the matching file in `reference/` for each:

1. `reference/trident-fuzz.md` — entry point, methodology overview, sufficiency checklist. **Read this first.**
2. `reference/trident-phase-1-setup.md` — map account dependencies, scaffold, write setup modules (≈60% of the work).
3. `reference/trident-phase-2-invariants.md` — derive testable invariants at multiple detection scopes.
4. `reference/trident-phase-3-construction.md` — write modular flows + invariant assertions.
5. `reference/trident-phase-4-validation.md` — compile, run a short campaign, verify flows execute.
6. `reference/trident-phase-5-analysis.md` — interpret output, assess coverage, decide next steps.
7. `reference/trident-api-v0.12.md` — version-pinned API reference (prevents method-signature hallucination). Swap when Trident updates.

## Note

Trident itself runs on the user's machine (Rust/Anchor toolchain). Sauna authors the harness, invariants, and flows, and interprets campaign output. Pairs well with the `cdsecurity/rust-audit-prep` and Plamen Solana skills.
