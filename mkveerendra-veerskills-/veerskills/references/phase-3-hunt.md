# Phase 3: HUNT — Systematic Hotspot Identification

**Step 3.0: Load protocol-specific checklist.** Read `{resolved_path}/references/protocol-checklists.md` and load the section matching the detected protocol type. ALWAYS also load the Solcurity and Secureum sections.

## 3.A — Vector Triage Pass *(280+ vectors from attack-vectors.md — UPGRADED with Pashov's 3-tier system)*

For each of the 280+ attack vectors assigned to the agent:

**Triage**: Classify into three tiers using **Skip/Borderline/Survive** classification:
- **Skip** — the named construct AND underlying concept are both absent (e.g., ERC721 vectors when no NFTs exist)
- **Borderline** — the named construct is absent but the underlying vulnerability concept could manifest through a different mechanism. Promote only if you can (a) name the specific function where the concept manifests AND (b) describe in one sentence how the exploit works; otherwise drop.
- **Survive** — the construct or pattern is clearly present

Output triage:
```
Skip: V2, V19, V61, ...
Borderline: V44 (similar caching in getReserves()), V78 (returndatasize in proxy fallback)
Survive: V9, V52, V73, ...
Total: {N} classified
```

**Deep pass**: Only for surviving vectors using structured one-liner format:
```
V52: path: deposit() → _transfer() → transferFrom | guard: none | verdict: CONFIRM [85]
V73: path: deposit() → transferFrom | guard: balance-before-after present | verdict: DROP (FP gate 3: guarded)
```
Budget: ≤1 line per dropped vector, ≤3 lines per confirmed vector.

## 3.B — Grep-Scan Pass *(original VeerSkills methodology)*

Before function-level analysis, run fast codebase-wide pattern scan:

**Syntactic Grep**: Search for high-risk patterns:
```bash
# Reentrancy signals
grep -rn "\.call{" --include="*.sol" | grep -v test
grep -rn "transferFrom\|safeTransferFrom" --include="*.sol" | grep -v test
# Oracle/price signals
grep -rn "latestRoundData\|getPrice\|slot0\|getReserves" --include="*.sol"
# Access control gaps
grep -rn "function.*external\|function.*public" --include="*.sol" | grep -v "onlyOwner\|onlyRole\|onlyAdmin\|modifier"
# Dangerous patterns
grep -rn "delegatecall\|selfdestruct\|tx.origin\|abi.encodePacked" --include="*.sol"
grep -rn "unchecked" --include="*.sol" | grep -v test
```

**Semantic Sweep**: Read for non-greppable vulnerabilities:
- Business logic flaws (incorrect state transitions, missing edge cases)
- Economic attacks (incentive misalignment, free options, value extraction)
- Cross-contract state coupling (shared variables, view reentrancy)
- Missing validation (zero amounts, empty arrays, max values)

## 3.C — Anti-Pattern Scan *(from anti-patterns.md)*

Scan the codebase against ALL anti-patterns from `references/anti-patterns.md`:
- Match each anti-pattern's ❌ WRONG pattern against the code
- For each match: check if the ✅ RIGHT pattern is used instead
- If wrong pattern matched and right pattern not present → flag as suspect

## 3.D — Function-Level Analysis

For each public/external function that writes state, moves value, or makes external calls:

1. **Master Checklist Sweep**: All 25 sections of `references/master-checklist.md` (~219 checks)
2. **Static Analysis Check**: Review Slither/Aderyn results for this function
3. **Cyfrin Category Drill**: Call `mcp__sc-auditor__get_checklist` with `{category: "<relevant>"}`
4. **Protocol-Specific Checklist**: Sweep items from `references/protocol-checklists.md`
5. **Protocol Route Checks**: Sweep the Required Checks and Critical Path vectors from `references/protocol-routes.md`
6. **Real-World Correlation**: Call `mcp__claudit__search_findings` with relevant keywords
7. **Invariant Check**: Can this function violate any invariant from Phase 2?
8. **Vulnerability Matrix Sweep**: All classes × checks from `references/vulnerability-matrix.md`

## 3.E — Variant Analysis *(from WEB3-AUDIT-SKILLS)*

For EVERY confirmed suspicious spot, systematically hunt for ALL variants:

**Abstraction Ladder** — abstract each finding to Level 2-3:
```
Level 0 (Specific):   "withdraw() doesn't check transfer return"
Level 1 (Function):   "unchecked return on token transfer"
Level 2 (Category):   "unchecked external call return value" ← SEARCH HERE
Level 3 (Root Cause):  "missing validation of external result"
```

**5 Variant Dimensions**:
1. **Same function, different contracts** → grep the signature across codebase
2. **Same root cause, different functions** → grep the anti-pattern in ALL functions
3. **Same pattern, different manifestation** → trace data flow for equivalent logic
4. **Cross-contract variants** → check all modules for same missing guard
5. **Cross-protocol variants** → call `mcp__claudit__search_findings` with root cause

## 3.F — Attack Chain Detection *(from WEB3-AUDIT-SKILLS — UPGRADED)*

Detect multi-step exploits where individual steps appear benign:

**Chain Types** (inspired by real exploits):
- **Flash Loan Chain**: Flash loan → price/governance manipulation → value extraction (Beanstalk $182M)
- **Oracle Chain**: Oracle distortion → under-collateralized borrow → drain (Cream $130M)
- **Bridge Chain**: Signature bypass → fake proof → unauthorized mint (Wormhole $326M)
- **Governance Chain**: Vote acquisition → proposal → execution (Beanstalk $182M)
- **Permit2 Chain** *(NEW)*: Approve permit2 → allowance inheritance → third-party protocol drains via inherited allowance
- **Hook Chain** *(NEW)*: V4-style hook → state manipulation in `beforeSwap` → `afterSwap` reads stale state → profit extraction
- **Composability Chain** *(NEW)*: Protocol A calls B calls C → state inconsistency at A when C reverts/pauses/returns unexpected data
- **ERC4626 Inflation Chain** *(NEW)*: Donate tokens → inflate share price → front-run depositor → withdraw inflated amount
- **Self-Liquidation Chain** *(NEW)*: Manipulate oracle → bring own position underwater → liquidate self from 2nd address → collect bonus

**Detection**: For each finding, ask: "Can this be STEP 1 of a multi-step exploit?" Trace forward through all reachable state changes. Check if combining 2-3 'medium' findings creates a 'critical' chain.

For each suspicious spot, output:
```
[HUNT-{N}] {One-line summary}
├── Components: {contracts + functions}
├── Attacker: {unprivileged user / flash loan / MEV bot}
├── Invariants: {which could be violated}
├── Evidence: {tool findings, checklist items, Solodit matches, vector IDs}
├── Confidence: [{score}] with deduction breakdown
├── Variants: {count of related instances found}
├── Chain: {standalone | step in chain [chain-id]}
└── Priority: {Critical / High / Medium / Low}
```

## 3.G — Reverse Impact Hunt *(NEW — backward-from-impact search)*

**Core Insight**: Standard vector scanning works FORWARD (pattern → bug?). Many critical bugs are only found by working BACKWARD (catastrophic outcome → what path reaches it?).

**MANDATORY for deep/beast modes. Recommended for standard.**

Enumerate ALL catastrophic outcomes for this protocol type, then trace backward:

| Impact Category | Specific Outcomes to Trace Backward From |
|---|---|
| **Fund Drain** | `token.transfer(attacker, ...)` where amount > attacker's deposit |
| **Unbacked Minting** | `_mint(attacker, shares)` without proportional asset deposit |
| **Liquidation Bypass** | `healthFactor >= 1` returns true when position is actually underwater |
| **Share Price Manipulation** | `totalAssets / totalSupply` returning attacker-controlled value |
| **Access Control Bypass** | `onlyOwner` function callable without owner being `msg.sender` |
| **Permanent Lock** | `withdraw()` always reverting for a legitimate depositor |
| **Oracle Corruption** | `getPrice()` returning attacker-manipulable value |

**For each outcome:**
1. Identify ALL functions that could produce this outcome
2. Trace backward: what input values and state conditions make this function produce the catastrophic result?
3. Can an attacker arrange those conditions? (via flash loan, front-running, governance, direct call)
4. If yes → flag as `[REVERSE-{N}]` with the full backward trace

```
[REVERSE-{N}] {Catastrophic outcome} achievable via {path}
├── Outcome: {e.g., "attacker extracts 2x their deposit"}
├── Terminal Function: {file.sol:L142 — _mint(attacker, inflatedShares)}
├── Backward Trace: _mint ← deposit() ← [no totalSupply check when totalSupply == 0]
├── Attacker Setup: First depositor deposits 1 wei, donates 1e18 directly
├── Invariant Broken: {E1: No Free Lunch}
└── Priority: {Critical / High}
```

## 3.H — Data Flow Graph + State Mutation Tracker *(NEW)*

**MANDATORY for deep/beast modes.**

Build a machine-readable data flow graph for the entire codebase:

**Step 3.H.1: State Variable Census**
For every state variable, create:
```
| Variable | Readers (functions) | Writers (functions) | External Deps |
|----------|--------------------|--------------------|---------------|
| totalSupply | balanceOf, deposit, withdraw, getSharePrice | deposit, withdraw, _mint, _burn | None |
| totalAssets | deposit, withdraw, getSharePrice, harvest | deposit, withdraw, harvest | strategy.totalValue() |
```

**Step 3.H.2: Orphan Detection**
- **Orphan Writes**: State written but never read → dead code or missing validation
- **Orphan Reads**: State read but never written (beyond initialization) → constant or misconfiguration
- **Write-Without-Guard**: State written without prior validation (`require`) → potential corruption

**Step 3.H.3: Stale Read Detection**
For every function that reads state AND makes an external call:
1. Does any other function modify the same state?
2. Can the external call trigger a callback that calls that other function?
3. If yes → state read is STALE during callback window → flag as `[STALE-{N}]`

**Step 3.H.4: Cross-Function Write Conflict**
For every state variable written by 2+ functions:
1. Can they execute concurrently in the same transaction? (via reentrancy)
2. Do they assume the variable hasn't changed since their read?
3. If yes → flag as `[CONFLICT-{N}]`

Log the full data flow graph in `audit-debug.md`.

## 3.I — Boundary Value Injection Protocol *(NEW)*

**MANDATORY for all modes.** Catches edge-case bugs that pattern matching misses.

For every arithmetic operation, comparison, or state transition in critical functions, mentally inject these values and trace the result:

| Category | Values to Inject | What Breaks |
|----------|-----------------|-------------|
| **Zero** | `0`, `address(0)`, empty bytes `""`, empty array `[]` | Division by zero, zero-amount transfers, null recipients |
| **One** | `1`, `1 wei` | Rounding to zero, dust positions, minimum viable exploit |
| **Max** | `type(uint256).max`, `type(int256).max`, `type(int256).min` | Overflow in unchecked, truncation on downcast |
| **Boundary** | `type(uint128).max`, `2**255`, `10**18 - 1` | Edge of safe arithmetic regions |
| **First/Last** | First deposit (`totalSupply == 0`), last withdrawal (`totalSupply → 0`) | Division by zero, inflation attacks, empty pool |
| **Self-Reference** | `msg.sender == address(this)`, `from == to`, `tokenA == tokenB` | Self-transfer, self-liquidation, pool with same token |
| **Array Edge** | Single element `[x]`, max elements, duplicate elements | Off-by-one, duplicate processing, gas limit |

**For each injection that produces an unexpected result:**
```
[BOUNDARY-{N}] {function}({injected_value}) → {unexpected_result}
├── Input: {specific value injected}
├── Expected: {what should happen}
├── Actual: {what code does — trace through}
├── Exploitable: {yes/no + how attacker triggers this}
└── Priority: {Critical / High / Medium / Low}
```

## 3.J — Multi-Expert Analysis Rounds *(NEW — from Forefy — standard+ modes)*

**MANDATORY for standard/deep/beast modes.** Applies THREE SEPARATE ANALYSIS ROUNDS with completely different personas. Each expert analyzes independently — NO cross-referencing between experts during their analysis.

**EXECUTION INSTRUCTION**: You must perform THREE SEPARATE ANALYSIS ROUNDS, adopting a completely different persona and approach for each expert. Do not blend their perspectives — maintain strict separation between each expert's analysis.

### ROUND 1: Security Expert 1 Analysis
**PERSONA**: Primary Smart Contract Auditor  
**MINDSET**: Systematic, methodical, focused on core vulnerabilities

**ANALYSIS APPROACH**:
1. **SYSTEMATIC CODE REVIEW**:
   - Start with highest-risk functions (payable, external calls, admin functions)
   - Map all fund flow paths and state changes
   - Analyze external dependencies and oracle integrations
   - Document findings with precise business impact context

2. **VULNERABILITY PATTERN MATCHING**:
   - Check for reentrancy vulnerabilities (all variants)
   - Validate access control mechanisms and permissions
   - Analyze arithmetic operations for precision/overflow issues
   - Review external call safety and return value handling

**OUTPUT REQUIREMENT**: Complete your full analysis as Expert 1, document all findings, then explicitly state: "--- END OF EXPERT 1 ANALYSIS ---"

### ROUND 2: Security Expert 2 Analysis
**PERSONA**: Secondary Smart Contract Auditor  
**MINDSET**: Fresh perspective, economic focus, integration specialist  
**CRITICAL**: Do NOT reference or build upon Expert 1's findings. Approach as if you've never seen their analysis.

**ANALYSIS APPROACH**:
1. **INDEPENDENT PROTOCOL ANALYSIS**:
   - Fresh review of all smart contract components
   - Different perspective on economic attack vectors
   - Alternative vulnerability assessment methodologies
   - Cross-validation of tokenomics and governance mechanisms

2. **INTEGRATION SECURITY FOCUS**:
   - Inter-contract communication security
   - External protocol integration risks
   - Composability and flash loan attack scenarios
   - Long-term protocol sustainability and upgrade risks

**OUTPUT REQUIREMENT**: Complete your independent analysis as Expert 2, then provide oversight analysis of Expert 1's findings and explicitly state: "--- END OF EXPERT 2 ANALYSIS ---"

**OVERSIGHT ANALYSIS RESPONSIBILITY**:  
After completing your independent analysis, review Expert 1's findings and provide honest self-reflection:
- Do you disagree that it's a valid vulnerability? Explain your reasoning
- Did you miss it due to different analysis focus or methodology?
- Was it an oversight in your systematic review process?
- Would you have caught it with more time or different approach?

### ROUND 3: Triager Validation
**PERSONA**: Customer Validation Expert (Budget Protector)  
**MINDSET**: Financially motivated skeptic who must protect the security budget  
**APPROACH**: Actively challenge and attempt to disprove BOTH Expert 1 and Expert 2 findings

**ENHANCED TRIAGER MANDATE**:
```
You represent the PROTOCOL TEAM who controls the bounty budget and CANNOT AFFORD to pay for invalid findings.
Your job is to PROTECT THE BUDGET by challenging every finding from Security Experts 1 and 2.
You are FINANCIALLY INCENTIVIZED to reject findings — every dollar saved on false positives is money well spent.
You must be absolutely certain a finding is genuinely exploitable before recommending any bounty payment.

MANDATORY CROSS-REFERENCE VALIDATION:
□ Finding Consistency Check: Compare all findings for logical contradictions or overlapping issues
□ Evidence Chain Validation: Verify each finding's evidence chain (Code Pattern → Vulnerability → Impact → Risk)
□ Contract Location Verification: Confirm all referenced contracts, functions, and line numbers exist and are accurate
□ Attack Path Cross-Check: Ensure attack scenarios don't contradict protocol protections found in other areas
□ Severity Calibration Review: Check if severity levels are consistent across similar finding types
□ Economic Impact Validation: Verify economic attack scenarios are realistic and profitable

BUDGET-PROTECTION VALIDATION:
□ Technical Disproof: Actively test the finding to prove it's NOT exploitable in practice
□ Economic Disproof: Calculate realistic attack costs vs profits to show it's unprofitable
□ Evidence Challenges: Identify flawed assumptions and test alternative scenarios
□ Exploitability Testing: Try to reproduce the attack and document where it fails
□ False Positive Detection: Find protocol protections or mitigations that prevent exploitation
□ Production Reality Check: Test how actual deployment conditions invalidate the finding

Your default stance is BUDGET PROTECTION — only pay bounties for undeniably valid, exploitable vulnerabilities.
```

**ENHANCED TRIAGER VALIDATION FOR EACH FINDING**:

```markdown
### Triager Validation Notes

**Cross-Reference Analysis**:
- Checked finding against all other discoveries for consistency
- Verified no contradictory evidence exists in other analyzed contracts
- Confirmed attack path doesn't conflict with protocol protections found elsewhere
- Validated severity level matches similar findings in this audit

**Economic Feasibility Check**:
- Calculated realistic attack costs (gas fees, capital requirements, time investment)
- Analyzed profit potential vs. risk and complexity
- Evaluated if attack is economically rational for attackers

**Technical Verification**:
- Actively tested the vulnerability by attempting reproduction with provided steps
- Performed technical disproof attempts: [specific tests run to invalidate the finding]
- Verified contract locations and challenged technical feasibility through direct testing
- Calculated realistic economic scenarios to disprove profitability claims

**Evidence Chain Validation**:
[Document the complete evidence chain and validate each link:
- Code Pattern Observed: [Specific smart contract code pattern]
- Vulnerability Type: [How pattern leads to security weakness]
- Attack Vector: [How an attacker would exploit this]
- Business Impact: [Real-world consequences for protocol and users]
- Risk Assessment: [Why this matters to the protocol team]]

**Protocol Context Validation**:
[Specific technical challenges raised against this finding:
- Contract function calls tested and results
- Economic scenarios simulated and actual outcomes
- Integration tests performed and discrepancies found
- External dependency checks and potential mitigating factors]

**Dismissal Assessment**:
- **DISMISSED**: Finding is invalid because [specific technical reasons proving it's not exploitable]
- **QUESTIONABLE**: Technical issue may exist but [specific concerns about practical exploitability/economic viability]
- **RELUCTANTLY VALID**: Finding is technically sound despite [attempts to dismiss - specific validation evidence]

**Economic Recommendation**:
[Harsh economic critique: Why this finding should be deprioritized or dismissed, focusing on unrealistic economic assumptions, impractical attack scenarios, or misunderstanding of protocol economics]

**Technical Recommendation**:
[Harsh technical critique: Why this finding should be deprioritized or dismissed, focusing on technical inaccuracies, impractical scenarios, or misunderstanding of protocol mechanics]
```

**OUTPUT REQUIREMENT**: Complete triager validation for ALL findings from Experts 1 and 2, then explicitly state: "--- END OF TRIAGER VALIDATION ---"

---

### CHECKPOINT
Present numbered list of ALL findings from 3.A through 3.J. Ask: *"Select targets for ATTACK phase (numbers, 'all', or 'high-only')."*
