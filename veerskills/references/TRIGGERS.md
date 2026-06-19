# VeerSkills AI Trigger Mapping (TRIGGERS)

This file instructs the VeerSkills AI agent on which reference files to load into context based on user prompts, detected code patterns, or protocol types. 

---

## 1. Explicit User Instructions

If the user explicitly asks for a specific framework or tool:

| User Trigger Phrase (or similar intent) | Files to Load |
| :--- | :--- |
| "What are the common anti-patterns for..." | Load `anti-patterns-library.md` |
| "Show me how this was exploited in the past" | Load `exploit-forensics.md` |
| "What is the attack tree for..." | Load `attack-trees.md` |
| "Give me the playbook for [Uniswap/Aave/etc]"| Load `protocol-playbooks.md` |
| "How did reentrancy evolve?" | Load `evolution-timelines.md` |
| "What is the learning path for..." | Load `learning-paths.md` |
| "Show me the master checklist" | Load `master-checklist.md` |
| "Where can I find information on..." | Load `XREF.md` |

---

## 2. Protocol Type Detection

If the user provides code or asks for an audit of a specific protocol type, load the corresponding decision paths and playbooks:

| Detected Protocol Archetype | Files to Auto-Load (in priority order) |
| :--- | :--- |
| **Lending / Borrowing / CDP** | 1. `attack-trees.md` (Lending section)<br>2. `anti-patterns-library.md` (Oracle / Reentrancy)<br>3. `protocol-playbooks.md` (Aave/Compound/Maker) |
| **DEX / AMM / Swap** | 1. `attack-trees.md` (DEX section)<br>2. `protocol-playbooks.md` (Uniswap/Curve)<br>3. `anti-patterns-library.md` (Token/Rounding) |
| **Bridge / Cross-Chain** | 1. `attack-trees.md` (Bridge section)<br>2. `exploit-forensics.md` (Ronin/Poly/Wormhole/Nomad)<br>3. `protocol-playbooks.md` (LayerZero) |
| **Vault / Yield Optimizer** | 1. `attack-trees.md` (Vault section)<br>2. `protocol-playbooks.md` (ERC4626 standard) |

---

## 3. Code Smell / Keyword Detection

If the static analyzer or agent detects specific function calls or variable names in the target codebase, proactively load the associated anti-patterns:

| Detected Code Snippet / Keyword | Associated Vulnerability / File to Load |
| :--- | :--- |
| `latestRoundData()` or `aggregator` | Oracles -> Load `anti-patterns-library.md` (Anti-Pattern 1.A/1.B) |
| `getReserves()` (Uniswap V2) | AMM Spot Price Manipulation -> Load `anti-patterns-library.md` |
| `delegatecall` inside a `fallback` | Proxy Upgradeability -> Load `upgradeability.md` |
| `initialize()` or `Initializable` | Unprotected Init -> Load `anti-patterns-library.md` (Anti-Pattern 3.A) |
| `flashLoan` or `executeOperation` | Flash Loan Attack Vector -> Load `exploit-forensics.md` (Euler/Beanstalk) |
| `ecrecover` or `verifySignatures` | Crypto/Signatures -> Load `exploit-forensics.md` (Wormhole), `cryptography.md` |
| `balanceOf(address(this))` | Vault Inflation / Force Feed -> Load `protocol-playbooks.md` (ERC4626) |
| `transferFrom` without `balanceOut - balanceIn` | Fee-on-Transfer Tokens -> Load `anti-patterns-library.md` (Anti-Pattern 4.A) |

---

## 4. Multi-File Loading Sequencer (Macro Triggers)

For comprehensive "Deep" or "Beast" mode audits, trigger macro-sequences:

*   **Trigger: "Full Audit of a Lending Protocol" (DEEP MODE)**
    *   *Sequence:* 
        1. Parse code for `latestRoundData`.
        2. Load `attack-trees.md` (Lending).
        3. Load `anti-patterns-library.md` (Oracle).
        4. Load `exploit-forensics.md` (Euler).
*   **Trigger: "Verify this Bridge Implementation" (BEAST MODE)**
    *   *Sequence:*
        1. Load `attack-trees.md` (Bridge).
        2. Load `exploit-forensics.md` (Ronin, Poly Network, Nomad, Wormhole).
        3. Load `protocol-playbooks.md` (LayerZero).
        4. Trigger specialized Multi-Chain Agents if target is non-EVM.
