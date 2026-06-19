# VeerSkills False-Positive Elimination Gate (Deep Enforcement)

_Adapted from Pashov's judging system. Every finding MUST pass this gate before inclusion in the report._

> **ANTI-RUBBER-STAMP RULE (MANDATORY):** Any check whose PASS evidence text is under 80 characters → automatic gate FAIL. One-sentence passes are not passes — they are skips. The FP Gate exists to CATCH false positives, not to confirm hunches. Every check must ACTIVELY TRY TO DISPROVE the finding.

---

## The 3-Check FP Gate (Minimum — Quick Mode)

Every finding must pass **ALL THREE** checks. If any check fails → **DROP** the finding immediately. Do not score or report it.

### Check 1: Concrete Attack Path — Deep Trace Required

You can trace a **concrete** attack path with **minimum 4 hops**, each citing exact `file:line`:
```
caller [who] → function(args) [file.sol:L42] → state_change [variable X: old→new] → impact [quantified]
```

**Mandatory Evidence Artifact:**
<output_format>
```
CHECK-1 EVIDENCE:
├── Hop 1: Attacker (any EOA) calls Vault.deposit(1000e18) [Vault.sol:142]
├── Hop 2: deposit() calls token.transferFrom(msg.sender, address(this), 1000e18) [Vault.sol:155]
├── Hop 3: Callback re-enters deposit() before shares minted [Vault.sol:158 — state: shares[attacker] still 0]
├── Hop 4: Second deposit() mints shares again for same tokens [Vault.sol:160 — shares[attacker] = 2000]
├── State Changed: shares[attacker] 0 → 2000 (should be 1000)
├── Impact: Attacker extracts 1000 extra tokens on withdraw ≈ $X at current price
└── PASS [167 chars evidence]
```
</output_format>

**FAIL conditions:**
- ❌ Path has fewer than 4 hops
- ❌ Any hop lacks `file:line` reference
- ❌ Impact is not quantified in units (tokens, ETH, USD, %)
- ❌ Path uses "could" or "might" instead of concrete steps
- ❌ Evidence text under 80 characters

**Rules:**
- Evaluate what the code **allows**, not what the deployer **might choose**
- Must be a specific path, not a theoretical concern
- Must result in measurable impact (fund loss, DoS, invariant violation)

### Check 2: Reachable Entry Point — Grep-Verified

The entry point is **reachable** by the attacker, verified by **mandatory grep search**.

**Mandatory Grep (must execute and paste results):**
```bash
# Search for access control on the affected function
grep -n "modifier\|onlyOwner\|onlyRole\|onlyAdmin\|require(msg.sender\|_checkRole\|hasRole\|auth\|onlyAuthority" {affected_file}
# Search for visibility
grep -n "function {function_name}" {affected_file}
# Search if function is called only internally
grep -rn "{function_name}" --include="*.sol" | grep -v test | grep -v mock
```

**Mandatory Evidence Artifact:**
<output_format>
```
CHECK-2 EVIDENCE:
├── Function: deposit() at Vault.sol:142
├── Visibility: external ✓ (grep: "function deposit(uint256) external")
├── Access Control Grep: grep -n "modifier\|onlyOwner..." Vault.sol → 3 results:
│   ├── L22: modifier onlyOwner — NOT on deposit()
│   ├── L85: modifier nonReentrant — NOT on deposit()
│   └── L100: require(msg.sender == keeper) — only on harvest(), NOT deposit()
├── Callers Grep: grep -rn "deposit" → called externally by users, no internal-only restriction
├── Preconditions: None (no whitelist, no minimum stake, no timelock)
└── PASS: Attacker (any EOA) can call deposit() directly [289 chars evidence]
```
</output_format>

**FAIL conditions:**
- ❌ No grep output pasted — claiming "no access control" without search evidence
- ❌ Function is `internal`/`private` and no exploitable caller chain shown
- ❌ Access control modifier found but not addressed (explain why it doesn't prevent attack)
- ❌ Evidence text under 80 characters

### Check 3: No Existing Guard — 8-Point Guard Sweep

No existing guard **already prevents** the attack. Must search for **ALL 8 guard categories**:

**Mandatory 8-Point Guard Search (log each with result):**

| # | Guard Category | Grep Command | Must Log |
|---|---------------|--------------|----------|
| 1 | Reentrancy Lock | `grep -rn "nonReentrant\|ReentrancyGuard\|_locked\|mutex" {file}` | Result count + which functions |
| 2 | CEI Pattern | Manual check: does state update happen BEFORE external call? | Yes/No + line numbers |
| 3 | SafeERC20 / SafeCast | `grep -rn "using Safe\|safeTransfer\|safeCast\|SafeMath" {file}` | Result count |
| 4 | Allowance/Balance Checks | `grep -rn "require.*balance\|require.*allowance\|balanceOf" {file}` | Result count + relevance |
| 5 | Input Validation | `grep -rn "require.*> 0\|require.*!=\|require.*amount\|if.*revert" {file}` | Result count + relevance |
| 6 | Compiler Version | `grep -n "pragma solidity" {file}` — is overflow checked? | Version + unchecked blocks |
| 7 | Library Protections | `grep -rn "using.*for\|import.*OpenZeppelin\|import.*solmate" {file}` | Libraries used |
| 8 | Inherited Protections | Check parent contracts for guards on overridden functions | Parents checked + result |

**Mandatory Evidence Artifact:**
<output_format>
```
CHECK-3 EVIDENCE (8-Point Guard Sweep):
├── [1] Reentrancy: grep → 0 results. No reentrancy guard on deposit(). ✗ ABSENT
├── [2] CEI Pattern: State update (shares[msg.sender] += X) at L160 AFTER transferFrom at L155. ✗ VIOLATED
├── [3] SafeERC20: grep → "using SafeERC20 for IERC20" at L8. BUT: transferFrom at L155 uses raw .transferFrom(), not .safeTransferFrom(). ✗ NOT APPLIED HERE
├── [4] Allowance/Balance: grep → 3 results. L45: balanceOf check in withdraw(). NOT in deposit(). ✗ IRRELEVANT
├── [5] Input Validation: grep → 2 results. L143: require(amount > 0). Prevents zero but not reentrancy. ✗ IRRELEVANT
├── [6] Compiler: pragma solidity ^0.8.19 → overflow checked. But reentrancy ≠ overflow. ✗ IRRELEVANT
├── [7] Libraries: OpenZeppelin SafeERC20 imported but not used on the vulnerable call. ✗ NOT APPLIED
├── [8] Inherited: Vault inherits BaseVault (L3). BaseVault has no reentrancy guard. ✗ ABSENT
└── PASS: 0/8 guards prevent the reentrancy attack path [485 chars evidence]
```
</output_format>

**FAIL conditions:**
- ❌ Fewer than 8 guard categories checked
- ❌ Any guard category without grep/search evidence
- ❌ Guard found but not explained why it doesn't prevent the attack
- ❌ Evidence text under 80 characters

---

## Confidence Scoring

Every finding that passes the FP Gate starts at **100**. Apply ALL applicable deductions:

| Condition | Deduction | Rationale |
|-----------|-----------|-----------| 
| Privileged caller required (owner, admin, multisig, governance) | **-25** | Less likely exploitable in practice |
| Attack path is partial (general idea sound but cannot write exact caller → call → state change → outcome) | **-20** | Uncertainty in exploitability |
| Impact is self-contained (only affects the attacker's own funds, no spillover to other users) | **-15** | Limited blast radius |
| Requires specific token type (fee-on-transfer, rebasing, ERC777) | **-10** | Only exploitable with specific tokens |
| Requires specific timing (block.timestamp, multi-block manipulation) | **-10** | Harder to execute reliably |
| Requires flash loan with significant capital (>$10M) | **-5** | Capital barrier |

### Confidence Classification

| Score | Classification | Action |
|-------|---------------|--------|
| **80-100** | **Confirmed** | Full finding with PoC, fix, and detailed description |
| **60-79** | **Likely** | Full finding with description. Fix recommended. PoC if feasible |
| **40-59** | **Possible** | Include in report below confidence threshold. Description only, no fix section |
| **Below 40** | **Drop** | Remove from report entirely. Too speculative |

---

## "Do Not Report" List

These are NEVER valid findings regardless of how they look:

### Absolutely Never Report
- ❌ Anything a linter, compiler, or seasoned developer would dismiss — INFO-level notes, gas micro-optimizations, naming, NatSpec, redundant comments
- ❌ Owner/admin can set fees, parameters, or pause — these are **by-design privileges**, not vulnerabilities (per P5: Privileged Roles Are Honest)
- ❌ Missing event emissions or insufficient logging
- ❌ Centralization observations without a concrete exploit path (e.g., "owner could rug" with no specific mechanism beyond trust assumptions)
- ❌ Theoretical issues requiring implausible preconditions (e.g., compromised compiler, corrupt block producer, >50% token supply held by attacker)

### Exceptions to "Do Not Report"
- **Fee-on-transfer, rebasing, blacklisting, pausing tokens**: If the code accepts arbitrary tokens, these are VALID attack surfaces
- **Admin error scenarios**: P5 says ignore admin malice, but DO check admin error scenarios (wrong parameter, accidental misconfiguration)
- **Governance timelock bypass**: If specific mechanism exists, this IS a vulnerability

---

## VeerSkills Extended Deep Checks (Checks 4-6 — Standard+ Modes)

These ADD to the 3-check gate and enforce even deeper verification. **ALL are mandatory for standard, deep, and beast modes.**

### Check 4: Cross-File Validation — Minimum 3-File Read

Search ALL files for constraints that prevent the exploit. **Must read at minimum 3 files** beyond the directly affected file.

**Mandatory Search Protocol:**
1. **Inheritance chain**: Read ALL parent contracts. `grep -rn "contract.*is " {file}` to find parents. Read each parent.
2. **Function callers**: `grep -rn "{function_name}" --include="*.sol" | grep -v test` — who else calls this function? Any wrapper with guards?
3. **Shared state guardians**: `grep -rn "{state_variable}" --include="*.sol" | grep -v test` — does any other contract validate or constrain this state?
4. **Protocol parameters**: `grep -rn "constant\|immutable\|MAX_\|MIN_\|LIMIT\|CAP" --include="*.sol" | grep -v test` — any protocol-level caps preventing the exploit?
5. **Governance/Admin guards**: Does governance set parameters that would constrain the exploit path?

**Mandatory Evidence Artifact:**
```
CHECK-4 EVIDENCE (Cross-File Validation):
├── Files Read Beyond Affected:
│   ├── [1] BaseVault.sol (parent) — no guards on deposit pattern, no reentrancy protection
│   ├── [2] VaultFactory.sol — creates Vault, no post-creation guards relevant to deposit
│   ├── [3] Strategy.sol — called by harvest(), not in deposit path
│   └── [4] FeeController.sol — manages fees, no interaction with deposit flow
├── Function Callers: grep → deposit() called only externally, no wrapper contract with guards
├── State Guardians: grep "shares" → shares modified only in deposit() and withdraw(), no external validator
├── Protocol Parameters: MAX_DEPOSIT = 1e24 — does not prevent reentrancy, just caps amount
├── Governance: No governance parameter affects deposit() execution path
└── PASS: No cross-file constraint prevents the attack [523 chars evidence]
```

**FAIL conditions:**
- ❌ Fewer than 3 files read beyond the affected file
- ❌ No inheritance chain check performed
- ❌ No grep for the function name across the codebase
- ❌ Constraint found in another file but not addressed
- ❌ Evidence text under 80 characters

### Check 5: Dry-Run with Concrete Values — Dual Trace Required

Pick specific numbers and trace through code. **Must perform TWO separate traces:**
1. **Realistic trace**: Normal production values (mid-range amounts, typical users)
2. **Adversarial trace**: Edge-case values designed to break assumptions (0, 1, `type(uint256).max`, 1 wei, maximum array length)

**Each trace must show ≥ 5 state checkpoints** — the value of key state variables at each step.

**Mandatory Evidence Artifact:**
```
CHECK-5 EVIDENCE (Dual Dry-Run):

TRACE A — Realistic Values:
├── Initial: shares[attacker] = 0, vault.totalSupply = 1000e18, vault.totalAssets = 1000e18
├── Step 1: attacker calls deposit(100e18) → transferFrom executes [Vault.sol:155]
│   State: token.balanceOf(vault) = 1100e18 ✓
├── Step 2: Callback fires during transferFrom (ERC-777 hook) → re-enters deposit(100e18) [Vault.sol:142]
│   State: shares[attacker] still = 0 (not yet updated), totalSupply still = 1000e18
├── Step 3: Inner deposit() calculates shares = 100e18 * 1000 / 1000 = 100e18 [Vault.sol:159]
│   State: shares[attacker] = 100e18, totalSupply = 1100e18
├── Step 4: Inner deposit() returns. Outer deposit() resumes, calculates shares = 100e18 * 1000 / 1000 = 100e18 [Vault.sol:159]
│   State: shares[attacker] = 200e18, totalSupply = 1200e18 ← DOUBLE CREDITED
├── Step 5: attacker calls withdraw(200e18) → receives 200e18 * 1100 / 1200 = 183.3e18 tokens
│   State: Profit = 183.3 - 100 = 83.3e18 tokens ← STOLEN
└── EXPLOITABLE ✓ (profit: 83.3 tokens for 100 token deposit)

TRACE B — Adversarial Values:
├── Initial: shares[attacker] = 0, vault.totalSupply = 0, vault.totalAssets = 0 (empty vault)
├── Step 1: attacker calls deposit(1 wei) → transferFrom executes
│   State: token.balanceOf(vault) = 1
├── Step 2: Callback re-enters deposit(1 wei)
│   State: shares[attacker] = 0, totalSupply = 0
├── Step 3: Inner deposit() — totalSupply == 0, so shares = amount = 1 [Vault.sol:157 firstDeposit branch]
│   State: shares[attacker] = 1, totalSupply = 1
├── Step 4: Outer deposit() resumes — totalSupply = 1 now, shares = 1 * 1 / 1 = 1
│   State: shares[attacker] = 2, totalSupply = 2 ← DOUBLE CREDITED even at 1 wei
├── Step 5: Works even with minimum values. No minimum deposit prevents this.
└── EXPLOITABLE ✓ (confirms attack works at all scales)

PASS [1,247 chars evidence]
```

**FAIL conditions:**
- ❌ Only one trace performed (must have both realistic AND adversarial)
- ❌ Fewer than 5 state checkpoints per trace
- ❌ No concrete numbers — using "X" or "some amount" instead of actual values
- ❌ Trace doesn't show state variable values at each step
- ❌ Economic viability not assessed (gas cost vs profit)
- ❌ Evidence text under 80 characters

### Check 6: Solodit Invalidation Check — Mandatory Tool Call

Search Solodit for similar findings that were **invalidated** by judges. **Must execute actual MCP tool call** and paste evidence.

**Mandatory Tool Call Protocol:**
1. Call `mcp__claudit__search_findings` with the root cause pattern (e.g., "reentrancy deposit vault")
2. Call `mcp__claudit__search_findings` with the impact pattern (e.g., "double mint shares")
3. Review top 5 results from each search
4. For any invalidated findings with similar root cause: explain why this finding is different

**Mandatory Evidence Artifact:**
```
CHECK-6 EVIDENCE (Solodit Invalidation Check):
├── Search 1: mcp__claudit__search_findings(keywords="reentrancy deposit vault", severity=["HIGH", "MEDIUM"])
│   ├── Results: 12 findings returned
│   ├── Relevant Match: "Deposit reentrancy in Sushi Trident" — severity HIGH, CONFIRMED ✓
│   ├── Relevant Match: "Vault deposit callback reentrancy" — severity HIGH, CONFIRMED ✓
│   └── No invalidated findings with same root cause pattern
├── Search 2: mcp__claudit__search_findings(keywords="double mint shares callback")
│   ├── Results: 8 findings returned
│   ├── Relevant Match: "Share inflation via reentrancy" — severity MEDIUM, CONFIRMED ✓
│   └── Invalidated Match: "ERC-777 reentrancy in fee collection" — INVALIDATED because fee collection had nonReentrant ← DOES NOT APPLY (our target lacks nonReentrant)
├── Invalidation Analysis:
│   └── The one invalidated finding was rejected because the function HAD a reentrancy guard. Our target LACKS a reentrancy guard (Check 3 confirmed). Different context → invalidation reason does not apply.
└── PASS: No applicable invalidation found. Similar confirmed findings support validity. [687 chars evidence]
```

**FAIL conditions:**
- ❌ No `mcp__claudit__search_findings` call made — claiming "no similar findings" without tool evidence
- ❌ Only one search query used (must use at minimum 2: root cause + impact pattern)
- ❌ Fewer than 5 results reviewed across both searches
- ❌ Invalidated finding found with same root cause but not addressed
- ❌ Evidence text under 80 characters

---

## Adversarial Meta-Check (MANDATORY — runs AFTER all 6 checks pass)

After all 6 checks pass, the agent MUST write one paragraph (minimum 3 sentences) **actively attempting to invalidate the entire finding**. The agent takes the stance: *"I am a skeptical judge who thinks this is a false positive. Here is why..."*

**Format:**
```
ADVERSARIAL META-CHECK:
"This finding could be a false positive because [reason 1]. Furthermore, [reason 2] might prevent
exploitation in practice. Additionally, [reason 3] suggests the attack may not be economically viable.

REBUTTAL: [reason 1] does not apply because [evidence]. [reason 2] is addressed by Check [N] which
showed [evidence]. [reason 3] is refuted by Check 5's economic analysis showing [profit/cost ratio].

VERDICT: Finding survives adversarial meta-check. All invalidation attempts rebutted with evidence."
```

**If any invalidation attempt cannot be rebutted** → the finding is DROPPED or downgraded, regardless of confidence score.

**FAIL conditions:**
- ❌ Meta-check is missing entirely
- ❌ Meta-check contains fewer than 3 invalidation attempts
- ❌ Rebuttal does not reference evidence from Checks 1-6
- ❌ Meta-check text under 150 characters total

---

## Evidence Depth Summary Table

Every finding's `fp_gate_results` JSON field must contain evidence meeting these minimums:

| Check | Minimum Evidence | Required Artifacts | Min Characters |
|-------|-----------------|-------------------|---------------|
| 1. Concrete Path | 4+ hops with file:line | State change + impact quantified | 80 |
| 2. Reachable | Grep output for access control | Pasted grep results | 80 |
| 3. No Guard | 8 guard categories searched | Result per category | 80 |
| 4. Cross-File | 3+ files read beyond affected | File list + findings per file | 80 |
| 5. Dry-Run | 2 traces × 5+ checkpoints | Variable values at each step | 80 |
| 6. Solodit | 2+ search queries executed | Query + result count + analysis | 80 |
| Meta-Check | 3+ invalidation attempts | Rebuttals referencing checks | 150 |

**If ANY check's evidence falls below its minimum → the ENTIRE gate fails.** The finding is moved to "Below Confidence Threshold" in the report.

---

## Applying the FP Gate

### During HUNT Phase (Quick Triage — 3 checks)
For each suspicious pattern found via attack vectors:
1. Apply Check 1 (Concrete Path with 4-hop minimum) → if fails → Skip
2. Apply Check 2 (Reachable with grep evidence) → if fails → Skip
3. Apply Check 3 (No Guard with 8-point sweep) → if fails → Skip
4. If all pass → Calculate confidence score → Include if >= 40

### During ATTACK Phase (Full Gate — 6 checks + meta-check)
For each finding selected for deep analysis:
1. Re-apply all 6 checks with full code context and **full evidence artifacts**
2. Run adversarial meta-check
3. Recalculate confidence with all applicable deductions
4. If confidence drops below 40 → Remove
5. If confidence drops below previous estimate → Downgrade severity
6. **Validate evidence depth**: Check each evidence artifact against the Evidence Depth Summary Table

### During VALIDATE Phase
Before including in final report:
1. Verify concrete values from Check 5 work in PoC
2. Verify PoC reproduces 3 times with different inputs
3. If PoC fails → Remove regardless of confidence score

---

## Structured One-Liner Format

For each vector during deep pass, use exactly this format:
```
V{N}: path: {entry} → {call chain} | guard: {what prevents it or "none"} | verdict: CONFIRM [{score}]
V{N}: path: {entry} → {call chain} | guard: {what prevents it} | verdict: DROP (FP gate {1|2|3}: {reason})
```

Budget: ≤1 line per dropped vector, ≤3 lines per confirmed vector before its formatted finding.
