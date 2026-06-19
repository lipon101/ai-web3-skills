# ai-web3-skills — Smart Contract Security Stack

**250 agent skills + full security toolchain** for smart contract bug bounty hunting on Immunefi, Code4rena, Sherlock, Cantina, and HackenProof.

## ⚡ One-Command Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/lipon101/ai-web3-skills/main/setup.sh)
```

Or clone and run:
```bash
git clone https://github.com/lipon101/ai-web3-skills && cd ai-web3-skills && bash setup.sh
```

After install, just say **"audit this contract"** and paste any Etherscan URL or contract address.

---

## 🛠️ Installed Tools

| Category | Tool | Purpose |
|---|---|---|
| **EVM Framework** | `forge` / `cast` / `anvil` / `chisel` | Testing, PoC building, tx simulation |
| **Static Analysis** | `slither` | Pattern-based Solidity vulnerability detection |
| **Static Analysis** | `aderyn` | Cyfrin's Rust-based AST scanner |
| **Static Analysis** | `semgrep` | Custom rule matching across codebases |
| **Static Analysis** | `solhint` | Solidity linter |
| **Fuzzing** | `medusa` | Trail of Bits stateful invariant fuzzer |
| **Fuzzing** | `echidna` | Property-based EVM fuzzer (via Docker) |
| **Symbolic Exec** | `halmos` | Symbolic EVM testing |
| **Audit Framework** | `wake` | Ackee Blockchain audit framework |
| **Node/EVM** | `hardhat` + `ganache` | Testing environment |
| **Compilers** | `solc` 0.6.12–0.8.28 | Multi-version Solidity compilation |
| **Language** | `vyper` | Vyper contract support |
| **Language** | `rust` + `cargo` | Rust/Solana program auditing |

---

## 📦 Skill Packs (250 skills)

| Pack | Skills | Coverage |
|---|---|---|
| Trail of Bits | 74 | Fuzzing, crypto, code graphs, Semgrep/CodeQL |
| Plamen | 145 | Multi-chain EVM/Solana/Sui/Aptos/Soroban |
| AuditMOS | 14 | Lending, liquidation, oracle, staking, slippage |
| Grimoire | 19 | Findings, PoC, cartography, librarian |
| QuillAI | 11 | Behavioral state analysis, threat engines |
| Pashov | 34 | Senior auditor SOP + 12 hacking agents |
| ShuvoSec | 10 | Full bug bounty workflow (web2 + web3) |
| OpenZeppelin | 9 | Secure dev + setup/upgrade for Solidity/Cairo |
| Weasel (slvdev) | 9 | Analyze, explain, gas, PoC, report, validate |
| SolidityGuard | 10 | 104 vuln patterns, DeFi, proxy, reporting |
| Drozer-lite | 22 | 180+ vulnerability patterns, 13 protocol profiles |
| VeerSkills | 110 | 300+ attack vectors, 50+ parallel agents |
| Krait | 47 | 4-phase pipeline, 101 heuristics, 8 kill gates |
| HackenProof | 33 | Triage, handoff, fix-verify, bulk-triage |
| + 37 more packs | ... | Argus, Cairo, Move, Starknet, Cosmos, Rust... |

---

## 🎯 Bug Bounty Workflow

```
1. "audit this contract: <etherscan URL>"
   → Agent fetches source, checks known findings, deep hunts

2. "build PoC for <finding>"
   → Foundry fork test against mainnet

3. "validate this finding"
   → Self-validation against Immunefi judging criteria

4. "write report for Immunefi"
   → Structured submission-ready report
```

---

## 📋 Skill Categories

- **Vulnerability Classes**: reentrancy, access control, oracle manipulation, flash loans, signature replay, proxy/upgrade, math/precision, slippage, liquidation, staking, auction, state validation, cross-chain
- **Audit Workflows**: pre-audit prep, scoping, cartography, finding drafting/review/dedup, PoC generation, report writing
- **Multi-Chain**: EVM, Solana/Anchor, Move (Sui/Aptos), Cairo (Starknet), CosmWasm, TON, Vyper
- **Fuzzing**: Foundry invariant, Echidna, Medusa, Halmos symbolic, AFL++, cargo-fuzz
- **Tooling**: CodeQL, Semgrep, Slither, Aderyn, Wake, Mythril, Radar

---

## 🔄 Updating Skills

```bash
cd ai-web3-skills
git pull
bash setup.sh
```

---

*Built for Gumloop AI Agent — 250 skills from 50+ top auditor toolkits*
