# VeerSkills Learning Paths

This document outlines structured curricula for developing smart contract auditing expertise, from beginner to advanced levels.

---

## 1. Beginner Path: Foundation (20-30 Hours)

**Prerequisites:** Basic programming knowledge, understanding of blockchain fundamentals.

**Phase 1: Solidity Mechanics**
1. Read the Solidity Documentation (focus: types, visibility, modifiers, memory vs storage).
2. Complete CryptoZombies or Speed Run Ethereum.
3. Understand the EVM execution model (Stack, Memory, Storage, Calldata).

**Phase 2: Common Vulnerabilities (The Classics)**
1. Study `reentrancy.md` (Read: The DAO case study).
2. Study `access-control.md` (Read: Parity Multisig hack).
3. Study `integer-overflow.md` (Understand SafeMath and Solidity ^0.8.0 native checks).
4. Review Unchecked Return Values and `tx.origin` vs `msg.sender`.

**Phase 3: Basic Tooling & First Steps**
1. Learn to run basic static analysis: Slither and Aderyn.
2. Read 5 past audit reports from top firms (Spearbit, Consensys, Trail of Bits) on *simple* protocols.
3. Attempt Ethernaut (OpenZeppelin) levels 1-10.

---

## 2. Intermediate Path: DeFi Architecture (40-60 Hours)

**Prerequisites:** Completion of Beginner Path, ability to write and deploy basic smart contracts.

**Phase 1: DeFi Primitives**
1. Deep dive into AMMs: Read the Uniswap V2 Whitepaper. Understand `x * y = k` math.
2. Deep dive into Lending: Study Aave V2/V3 architecture (eTokens, debtTokens, Interest Rate Models).
3. Deep dive into Vaults: Study the ERC4626 standard and Yearn V2 architecture.

**Phase 2: Advanced Attack Vectors**
1. Study `oracle-manipulation.md` (Read `anti-patterns-library.md` Anti-Pattern 1.A/1.B).
2. Study Flash Loan attack mechanics (Read Euler and Beanstalk case studies).
3. Understand Precision Loss, Rounding Erasures, and Dust Accumulation (`precision-loss.md`).
4. Master Read-Only Reentrancy and Cross-Contract execution flows.

**Phase 3: Deep Tooling & Fuzzing**
1. Transition from Hardhat/Truffle to Foundry.
2. Write Foundry PoCs (Proof of Concepts) strictly in Solidity.
3. Learn Property-Based Fuzzing (Foundry `forge test --fuzz`). Define invariants.
4. Attempt older Code4rena or Sherlock contests in a local environment.

---

## 3. Advanced Path: The Edge (100+ Hours)

**Prerequisites:** Consistent bug-finding in actual codebases, mastery of Foundry and DeFi primitives.

**Phase 1: Complex System Synergies**
1. Study Bridge Architectures (Read `protocol-playbooks.md` LayerZero). Analyze Ronin/Wormhole forensics.
2. Cross-Chain Messaging MEV and Gas Grieving.
3. Layer 2 specific risks (Sequencer downtime, Arbitrum/Optimism L1-to-L2 bridging delays).
4. Advanced Cryptography flaws (Signature Malleability, ECDSA recovery manipulation).

**Phase 2: Economic & Game Theory Attacks**
1. Liquidation manipulation (Self-liquidation loops, liquidation DOS).
2. Governance attacks (Flash loan voting, proposal execution hijacking).
3. Incentive misalignment (Yield farming reward dilution).

**Phase 3: Expert Methodologies**
1. Invariant mapping for complete systems (Echidna/Medusa).
2. Formal Verification basics (Halmos, Certora).
3. Yul / EVM Assembly profiling and exploitation.
4. Read Vyper-specific vulnerabilities (e.g., the nonReentrant lock failure).
