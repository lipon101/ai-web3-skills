---
name: tamarin-prover
description: Reference for the Tamarin prover (trailofbits fork), a symbolic-model security-protocol verification tool. Tamarin is a native Haskell tool the user installs and runs locally, NOT inside Sauna. Use when the user wants to formally verify a cryptographic/security protocol (key exchange, authentication, handshake) in the symbolic model, write or check .spthy models, or asks how to install/run Tamarin. Sauna helps author models, lemmas, and interpret proofs/attack traces.
---

# Tamarin Prover (reference)

Symbolic-model verification tool for cryptographic protocols (proves secrecy/authentication or finds attack traces). Repo (fork): https://github.com/trailofbits/tamarin-prover · Upstream: https://tamarin-prover.github.io

## Important: native tool, not a Sauna capability

Tamarin is a Haskell application (install via the upstream instructions / Homebrew / nix). It runs on the user's machine. Sauna helps write `.spthy` theory files, formulate lemmas, and read proof results / attack graphs.

## How Sauna assists

1. Author Tamarin models: rules, facts, restrictions, and security lemmas (secrecy, agreement, injective agreement).
2. Interpret results — closed proofs vs. found attacks (counterexample traces).
3. Bridge from diagrams: pair with the trailofbits `crypto-protocol-diagram` and `mermaid-to-proverif` skills to go spec → model → proof.

For EVM/contract formal verification instead, see `lfglabs-dev-verity` and `starkware-libs-formal-proofs`.
