# VeerSkills Reference Index

**`<system_notice>`**
This directory contains the 21 reference frameworks that power the VeerSkills audit engine.
Agents MUST use this index to locate the correct file when instructed by the main `SKILL.md` pipeline. 
**`</system_notice>`**

---

## 1. Core Threat Intelligence
Files loaded during the HUNT phase for vector scanning and pattern matching.
- **`attack-vectors.md`**: The master library of 280+ attack vectors with Detection (D) and False-Positive (FP) markers.
- **`master-checklist.md`**: 25 vulnerability categories and ~219 specific code checks.
- **`anti-patterns.md`**: 14 categories of dangerous code implementation patterns (with WRONG vs RIGHT code examples).
- **`vulnerability-matrix.md`**: Severity calculation and impact assessment framework.

## 2. Validation & Quality Control
Files loaded during the ATTACK and VALIDATE phases to eliminate false positives.
- **`fp-gate.md`**: The mandatory 6-Check Deep FP Gate + Anti-Rubber-Stamp rules.
- **`poc-templates.md`**: 11 scaffolded Foundry PoC templates covering reentrancy, inflation, oracle, access control, flash loan, cross-function, reverse impact, boundary value, state desync, token integration, and signature replay.
- **`report-template.md`**: The structured format for the final audit deliverable.

## 3. Deep Analysis Frameworks
Files loaded during Deep/Beast modes for specialized analysis.
- **`invariant-framework.md`**: Templates for Safety, Liveness, Economic, and Composability invariants.
- **`nemesis-convergence.md`**: The language-agnostic iterative cross-feed loop for deep logic bugs. Features the Feynman Auditor ("questions every line") and State Inconsistency Auditor alternating up to a max of 6 passes until convergence (Beast mode only).
- **`storage-layout-analyzer.md`**: Upgrade safety, slot computation, and struct packing checks for proxies.
- **`attack-modeling.md`**: Threat actor profiling and attack surface mapping.
- **`tools-integration.md`**: Commands for static/dynamic analysis (Slither, Aderyn, Echidna).

## 4. Context & Protocol Engines
Files loaded during the MAP phase to give the agent context on what they are auditing.
- **`protocol-context-engine.md`**: Derives bug preconditions from 10,600+ real audit findings across 21 protocol types.
- **`protocol-routes.md`**: Prescribes exact audit paths depending on the protocol type (e.g. AMM vs Lending).
- **`protocol-checklists.md`**: A fast checklist of common gotchas per protocol type.

## 5. Multi-Chain & L2 Modules
Files loaded when the target codebase is not standard EVM L1.
- **`network-checklists.md`**: Nuances for L2s (Arbitrum, Optimism) and sidechains (Polygon, BSC).
- **`chain-deep-solana.md`**: Solana/Rust specific vectors and account validation checks.
- **`chain-deep-move.md`**: Sui/Aptos Move specific vectors and capability checks.
- **`chain-deep-ton.md`**: TON/FunC specific vectors and message passing checks.
- **`chain-deep-cosmos.md`**: Cosmos SDK/Go specific vectors and IBC checks.
- **`chain-deep-cairo.md`**: Starknet/Cairo specific vectors and syscall checks.

## 6. Exploit Intelligence
Files loaded to provide massive historical context on real-world hacks.
- **`exploit-forensics.md`**: 30 transaction-level forensic breakdowns of major DeFi exploits (The DAO, Ronin, Euler, etc.).
- **`evolution-timelines.md`**: Tracks how vulnerabilities (like reentrancy or oracle manipulation) evolved from 2016 through today.

## 7. Decision Trees
Files loaded to systematically eliminate vulnerability branches.
- **`attack-trees.md`**: Systematic decision paths and root-goal mapping for 6 protocol archetypes (Lending, DEX, Bridge, Vault, Governance, Stablecoin).

## 8. Anti-Pattern Education
Files loaded to show agents exactly what BAD code looks like versus GOOD code.
- **`anti-patterns-library.md`**: 42 concrete anti-patterns across 6 categories, providing VULNERABLE code, the Attack PoC, and the CORRECT code.

## 9. Protocol Integration Guides
Files loaded when auditing protocols built *on top* of existing DeFi legos.
- **`protocol-playbooks.md`**: Specific security checklists for integrating with Uniswap V3, Aave V3, Lido, Chainlink, Compound V3, Curve, MakerDAO, and LayerZero.

## 10. Navigation & Cross-Reference
Files loaded to map intents to data and vulnerabilities to files.
- **`XREF.md`**: Master cross-reference index mapping vulnerability types to their abstract patterns, real-world exploits, and anti-patterns.
- **`TRIGGERS.md`**: AI trigger phrase mapping, instructing the agent which files to load based on user prompts or code smells.

## 11. Learning & Development
Files loaded to structure human or agent upskilling.
- **`learning-paths.md`**: Structured curricula for Beginner (20hrs), Intermediate (40hrs), and Advanced (80hrs) auditor development.
