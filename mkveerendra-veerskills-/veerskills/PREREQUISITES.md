# VeerSkills Prerequisites Guide

VeerSkills is an active execution engine that requires local dependencies and tools to operate at its maximum potential. The prerequisites required scale depending on which of the 4 Audit Modes (`quick`, `standard`, `deep`, `beast`) you select.

---

## 🟢 Level 1: Core Essentials (Required for ALL Modes)

To run **Quick** and **Standard** modes effectively, the agent requires the following baseline tools installed on the host system:

### 1. Model Context Protocol (MCP) Servers
- **`sc-auditor` MCP**: Required to run static analysis (Slither, Aderyn) without configuring local toolchains, and to pull Cyfrin checklists.
- **`claudit` MCP**: Required to search the Solodit database for real-world finding patterns during Phase 3 (HUNT) and Phase 5 (VALIDATE).

### 2. Foundry (`forge`, `cast`, `anvil`)
The absolute backbone of the VeerSkills validation engine.
- **Purpose**: Used heavily in **Phase 5 (VALIDATE)** to compile the codebase and strictly verify all `[HUNT-*]` findings using the 11 PoC templates.
- **Install**: `curl -L https://foundry.paradigm.xyz | bash`

### 3. GNU Coreutils
- **Purpose**: Standard bash tools (`grep`, `find`, `wc`) are used heavily in **Phase 1.7 (AUTO-CHUNK)** to map interfaces and count codebase lines dynamically.

---

## 🟡 Level 2: Advanced Fuzzing (Required for DEEP Mode)

**Deep Mode** initiates **Phase 6 (FUZZ)**, where the agent moves beyond stateless PoCs and actively stress-tests the protocol's state transitions.

### 1. Echidna
- **Purpose**: Deep, property-based stateful fuzzing to hunt for complex broken invariants over 100,000+ transaction sequences.
- **Install**: Download pre-compiled binaries from Trail of Bits, or install via Haskell/Stack.
- **Dependency**: Requires `crytic-compile` (install via: python -m pip install crytic-compile) to parse the Solidity contracts.

### 2. Medusa (Optional Alternative)
- **Purpose**: A faster, Go-based alternative to Echidna. If installed, the agent can use this for concurrent fuzzing.
- **Install**: `go install github.com/crytic/medusa@latest`

---

## 🔴 Level 3: Formal Verification (Required for BEAST Mode)

**Beast Mode** activates the **NEMESIS CONVERGENCE LOOP** and formal verification (Phase 6.4), demanding absolute mathematical certainty.

### 1. Certora Prover (API & CLI)
- **Purpose**: Used by the agent to mathematically prove the Safety and Liveness invariants mapped in `invariant-framework.md`. 
- **Install**: `python -m pip install certora-cli`
- **Authentication**: **CRITICAL** — You must export a valid commercial/academic Certora API key in your environment: `export CERTORAKEY="your-api-key"`.

### 2. Halmos (Symbolic Execution)
- **Purpose**: Open-source symbolic execution to mathematically prove bounded Foundry tests without requiring CVL (Certora Verification Language) specs.
- **Install**: `python -m pip install halmos`
- **Dependency**: Requires an SMT Solver (like Z3 or CVC5) installed on the host OS.

### 3. Scribble
- **Purpose**: Used to inject invariant annotations directly into the Solidity AST prior to fuzzing.
- **Install**: `npm i -g eth-scribble`

---

## Summary Matrix

| Tool | Quick Mode (15-30m) | Standard Mode (2-4h) | Deep Mode (4-8h) | Beast Mode (8h+) |
|------|-----------|--------------|----------|----------|
| **sc-auditor MCP** | ✅ Required | ✅ Required | ✅ Required | ✅ Required |
| **claudit MCP** | ✅ Required | ✅ Required | ✅ Required | ✅ Required |
| **Foundry** | ✅ Required | ✅ Required | ✅ Required | ✅ Required |
| **Echidna** | ❌ Skipped | ❌ Skipped | ✅ Required | ✅ Required |
| **Certora CLI/API**| ❌ Skipped | ❌ Skipped | ❌ Skipped | ✅ Required |
| **Halmos** | ❌ Skipped | ❌ Skipped | ❌ Skipped | ✅ Required |
