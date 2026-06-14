# VeerSkills Master Cross-Reference Index (XREF)

This document maps vulnerability types to their abstract patterns, real-world exploit forensics, and concrete anti-pattern code examples. It acts as the central navigation hub for the VeerSkills knowledge base.

---

## 1. By Vulnerability Type

| Vulnerability Type | Abstract Pattern Guide | Real-World Exploit | Concrete Anti-Pattern (Vulnerable vs Good code) |
| :--- | :--- | :--- | :--- |
| **Oracle Manipulation (Spot Price)** | `oracle-manipulation.md` | Harvest Finance ($34M), bZx ($8M) | `anti-patterns-library.md` (Anti-Pattern 1.A) |
| **Oracle Staleness / Failure** | `oracle-manipulation.md` | Venus Protocol ($200M), Cream ($130M) | `anti-patterns-library.md` (Anti-Pattern 1.B) |
| **Reentrancy (Classic)** | `reentrancy.md` | The DAO ($60M), Lendf.Me ($25M) | `anti-patterns-library.md` (Anti-Pattern 2.A) |
| **Reentrancy (Read-Only / Cross-Contract)** | `reentrancy.md` | Curve / Vyper Compiler Bug ($70M) | `anti-patterns-library.md` (Anti-Pattern 2.A) |
| **Access Control (Missing Init)** | `access-control.md` | Parity ($150M), Nomad ($190M) | `anti-patterns-library.md` (Anti-Pattern 3.A) |
| **Access Control (Validator Compromise)** | `cross-chain.md` | Ronin ($625M), Harmony ($100M) | N/A (OpSec failure) |
| **Token Arithmetic (Rounding/Dust)** | `precision-loss.md` | Aave V2 (Dust accumulation) | `anti-patterns-library.md` (Anti-Pattern 4.A) |
| **Token Deflation (Fee-on-Transfer)** | `token-standards.md` | Balancer V1 (deflationary tokens) | `anti-patterns-library.md` (Anti-Pattern 4.A) |
| **Lending (Missing Health Check)** | `lending-math.md` | Euler Finance ($197M) | `exploit-forensics.md` (Euler Case Study) |
| **Governance (Flash Loan Voting)** | `governance-attacks.md` | Beanstalk ($182M) | `exploit-forensics.md` (Beanstalk Case Study) |
| **Vaults (ERC4626 Inflation/Donation)** | `vault-math.md` | Yearn V1 (Early iterations) | `protocol-playbooks.md` (ERC4626 Playbook) |
| **Signature Spoofing / Replay** | `cryptography.md` | Wormhole ($326M) | `exploit-forensics.md` (Wormhole Case Study) |

---

## 2. By Real-World Exploit

| Exploit | Year | Loss | Core Vulnerability | VeerSkills Vector Map | Detailed Post-Mortem |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Ronin Bridge** | 2022 | $625M | Validator Key Compromise | External Threat Modeling | `exploit-forensics.md` #1 |
| **Poly Network** | 2021 | $611M | Unprotected Init + Hash Collision | Phase 3: Arbitrary Calls | `exploit-forensics.md` #2 |
| **Wormhole** | 2022 | $326M | Signature Validation (Sysvar spoofing) | Phase 11: Multi-chain (Solana) | `exploit-forensics.md` #3 |
| **Euler Finance** | 2023 | $197M | Logic Error: Missing Health Check | Phase 5: Invariant Mapping | `exploit-forensics.md` #4 |
| **Nomad Bridge** | 2022 | $190M | Zero-Value Collision in Merkle | Phase 7: Storage Collision | `exploit-forensics.md` #5 |
| **Beanstalk** | 2022 | $182M | Flash Loan Governance Bypass | Phase 4: Flash Loan Susceptibility| `exploit-forensics.md` #6 |
| **Cream Finance** | 2021 | $130M | Oracle Manipulation (Price * Quantity) | Phase 5: Economic Value | internal tracker |
| **Mango Markets**| 2022 | $116M | Oracle Manipulation (Low Liquidity) | Phase 11: Multi-chain (Solana) | internal tracker |
| **The DAO** | 2016 | $60M | Classic Reentrancy | Phase 3: Reentrancy | `exploit-forensics.md` #7 |

---

## 3. By Protocol Type

| Protocol Archetype | Primary Navigation Path | Key Concept Checks | Threat Modeling Tree |
| :--- | :--- | :--- | :--- |
| **Lending / CDP** | `protocol-playbooks.md#Aave` | Oracle freshness, Health factor updates, Liquidation math | `attack-trees.md#1-Lending` |
| **DEX / AMM** | `protocol-playbooks.md#UniswapV3` | Slippage tolerance, K-value invariants, Fee math | `attack-trees.md#2-DEX` |
| **Bridge** | `protocol-playbooks.md#LayerZero` | Merkle proofs, Nonce replay, ChainID validation, Validators | `attack-trees.md#3-Bridge` |
| **Vault / Yield** | `protocol-playbooks.md#ERC4626` | First-depositor inflation, Share math rounding, Fee dilution | `attack-trees.md#4-Vault` |
| **Governance** | `governance-attacks.md` | Snapshot blocks, Timelocks, Quorum threshold, Flash loans | N/A |
