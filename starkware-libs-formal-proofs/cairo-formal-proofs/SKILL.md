---
name: cairo-formal-proofs
description: Reference for starkware-libs/formal-proofs, a repository of Lean formal verification of the Cairo language and STARK/AIR encodings (Cairo CPU semantics, VM semantics, AIR encoding soundness, S-two prover soundness). It's a Lean proof project compiled with lake/Lean on the user's machine, NOT inside Sauna. Use when the user is reasoning about Cairo VM semantics, STARK soundness, AIR encoding correctness, or wants to read/extend these Lean proofs. Sauna helps navigate the proofs and explain the semantics.
---

# Cairo Formal Proofs (reference)

Formal verification of the Cairo programming language and its STARK proving stack, written in Lean. By StarkWare. Repo: https://github.com/starkware-libs/formal-proofs

## Important: Lean proof project, not a Sauna capability

These are Lean 4 proofs compiled and checked with `lake`/Lean on the user's machine. Sauna helps read, explain, and extend them — it does not run the proof checker for you.

## Contents

- `Stwo/` — soundness proof of the AIR encoding used by the Cairo S-two prover (see `Stwo/README.md` to compile/check).
- `Verification/Semantics/` — specification of the Cairo VM semantics and correctness proof of the older Cairo Stone AIR encoding:
  - `Cpu.lean` — execution semantics of the Cairo CPU (soundness of programs + STARK encoding correctness).
  - `Vm.lean` — abstracted Cairo VM semantics (completeness of Cairo programs).
  - `AirEncoding/` — correctness of the algebraic encoding of execution traces used to generate STARK certificates.

## How Sauna assists

1. Explain Cairo CPU/VM semantics and the AIR encoding soundness arguments.
2. Help navigate, read, or extend the Lean proofs (statement structure, lemma dependencies).
3. Connect to auditing Cairo/StarkNet contracts (pair with `trailofbits-skills/cairo-vulnerability-scanner` and `openzeppelin-openzeppelin-skills/setup-cairo-contracts`).

Reference material — proof compilation runs on the user's machine via Lean/lake.
