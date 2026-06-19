# Phase 4: ATTACK — Deep Exploit Validation

For each selected target, one at a time:

## 4.1 Trace Call Path

Read actual code. Trace variable values through execution. Map every external call, state change, and branch.

## 4.2 Construct Attack Narrative

- **Attacker role**: Who (any user, flash loan borrower, MEV bot)
- **Call sequence**: Exact transaction sequence to exploit
- **Broken invariant**: Which invariant violated
- **Extracted value**: What attacker gains (funds, shares, access)
- **Capital required**: Flash loan size, gas cost, timing constraints

## 4.3 Full 6-Check FP Gate — Deep Enforcement (MANDATORY)

Apply all 6 checks from `references/fp-gate.md` with **mandatory evidence artifacts and depth validation**:
1. **Concrete path** (4+ hops): Trace caller → function → state change → impact. Each hop must cite exact `file:line`. Impact quantified in units.
2. **Reachable** (grep-verified): Execute `grep -n "modifier\|onlyOwner\|onlyRole\|require(msg.sender"` on affected file and paste output. No grep = FAIL.
3. **No guard** (8-point sweep): Search ALL 8 guard categories (reentrancy lock, CEI pattern, SafeERC20, allowance/balance, input validation, compiler version, library protections, inherited protections). Log each with grep command + result count.
4. **Cross-file** (3+ file reads): Read ≥3 files beyond affected file. Grep function name across entire codebase. Trace full inheritance chain. List every file read.
5. **Dry-run** (dual trace): Perform TWO traces — realistic values AND adversarial edge cases (0, max_uint, 1 wei). Each trace must show ≥5 state checkpoints with variable values at each step.
6. **Solodit check** (mandatory tool call): Execute ≥2 `mcp__claudit__search_findings` queries (root cause pattern + impact pattern). Review ≥5 results. Address any matching invalidated findings.

**Anti-Rubber-Stamp Rule**: Any check with PASS evidence under 80 characters → entire gate FAILS. One-sentence passes are skips, not verification.

**Adversarial Meta-Check** (after all 6 pass): Write ≥3 sentences attempting to invalidate the finding as a skeptical judge. Rebut each with evidence from checks 1-6. If any rebuttal fails → DROP.

**Evidence Depth Validation**: Before finalizing, verify each check's evidence against the Evidence Depth Summary Table in `fp-gate.md`. Any check below minimum → finding moved to "Below Confidence Threshold".

Calculate confidence score with all applicable deductions. If score < 40 → DROP.

## 4.4 Adversarial Verification *(UPGRADED — from exvul methodology with isolated per-finding review)*

For each surviving finding, apply formal adversarial review with **mandatory isolation**:

**Core Stance (MANDATORY)**: "This is likely a false positive unless local evidence proves exploitability."

**Isolation Constraints (MANDATORY)**:  
Each finding must be verified by a fresh reviewer instance with NO carry-over context.

**Allowed input per finding**:
1. Finding payload (title, description, severity, attack path)
2. Local code excerpt around `file:line` (±20 lines of context)

**Disallowed**:
- Cross-finding memory (cannot reference other findings)
- Global conclusions imported from previous decisions
- Optimistic assumptions without direct local evidence

**Required Decision Schema**:
```json
{
  "decision": "false_positive | valid | valid_downgraded",
  "downgraded_severity": "Critical|High|Medium|Low|Informational|",
  "confidence": 0.0,
  "confidence_basis": "what evidence made confidence high/medium/low",
  "explanation": "short technical rationale"
}
```

**Confidence Rule**:  
Do not reuse fixed defaults. Set confidence from evidence quality:
- Exploit path complete + strong local proof → higher confidence (0.7-1.0)
- Missing preconditions or uncertain control flow → lower confidence (0.3-0.6)
- Speculative or requires extensive assumptions → very low confidence (0.0-0.2)

**Decision Application**:
- `false_positive`: Remove from final findings
- `valid`: Keep unchanged
- `valid_downgraded`: Keep with lower severity and explicit severity transition

**Output Format**:
```
[ADVERSARIAL-{N}] {Finding ID}
├── Decision: {false_positive | valid | valid_downgraded}
├── Original Severity: {Critical|High|Medium|Low}
├── Final Severity: {Critical|High|Medium|Low}
├── Confidence: {0.0-1.0}
├── Confidence Basis: {what evidence made confidence high/medium/low}
└── Explanation: {short technical rationale}
```

**Mandatory Summary**:
```
ADVERSARIAL VERIFICATION SUMMARY:
├── Valid: {N}
├── Valid Downgraded: {N}
├── False Positive Dropped: {N}
└── Total Reviewed: {N}
```

## 4.5 Economic Triager Validation *(NEW — from Forefy)*

For each surviving finding, apply **budget-conscious triager** that actively tries to disprove:

**Default stance**: "This finding is likely invalid. Prove otherwise."

**4 Triager Checks** (each must pass or finding is downgraded/dismissed):

1. **Technical Disproof Attempt**: Actively try to prove the finding is NOT exploitable
   - Test the attack path with concrete values
   - Check if protocol protections exist that initial analysis missed
   - Verify contract locations and line numbers are accurate
   - Log result in `audit-debug.md`

2. **Economic Feasibility Check**: Calculate realistic attack economics
   - Gas cost of the attack at current gas prices
   - Flash loan fees required (typically 0.09% on Aave)
   - Capital requirements and opportunity cost
   - Sandwich/MEV profitability threshold
   - Is the attack **economically rational** for a real attacker?
   - Log calculation in `audit-debug.md`: `[TRIAGER] {finding-id}: gas=$X, flash_loan_fee=$Y, profit=$Z → rational/irrational`

3. **Evidence Chain Validation**: Every link must be verified
   ```
   Code Pattern Observed → Vulnerability Type → Attack Vector → Business Impact → Risk Assessment
   ```
   Missing link = finding is downgraded.

4. **Cross-Finding Consistency**: Check all findings for logical contradictions
   - Does Finding A's exploit assume a protection that Finding B says is missing?
   - Are severity levels consistent across similar finding types?

**Triager Verdict Classification**:
| Verdict | Criteria | Action |
|---|---|---|
| **VALID** | Cannot be disproved. Economically rational. Full evidence chain. | Keep with severity |
| **QUESTIONABLE** | Technical issue exists but economic viability unclear. | Mark for additional proof |
| **OVERCLASSIFIED** | Valid but severity exaggerated. | Downgrade severity |
| **DISMISSED** | Disproved technically or economically. | Remove with documented reasoning |

## 4.6 Severity Formula *(from Forefy — conservative)*

Apply quantitative severity scoring:
```
Base Score = Impact × Likelihood × Exploitability
Final Score = Base Score (if borderline, round DOWN)
```

| Factor | Score 3 (High) | Score 2 (Medium) | Score 1 (Low) |
|---|---|---|---|
| **Impact** | Complete compromise, TVL >$1M at risk | Significant loss >$100k, major disruption | Limited loss <$100k, minor impact |
| **Likelihood** | In core user flows, easily discoverable | Requires moderate knowledge + specific conditions | Requires expert knowledge + perfect timing |
| **Exploitability** | Single tx, flash-loan enabled, guaranteed profit | Multi-tx, requires capital, timing dependent | Requires governance, extensive setup |

| Score Range | Severity |
|---|---|
| 18-27 | CRITICAL |
| 8-17 | HIGH |
| 4-7 | MEDIUM |
| 1-3 | LOW |

**Conservative rule**: When uncertain between two severity levels, ALWAYS choose the LOWER one.

## 4.7 Verdict

**NO VULNERABILITY**: Document refutation steps, specific constraints preventing exploit, confidence level.

**VULNERABILITY CONFIRMED**: Produce finding in output format, then proceed to Phase 4.8 for iterative depth.

## 4.8 Iterative Depth Loop with Anti-Dilution *(NEW — from Plamen's adaptive depth architecture)*

**MANDATORY for deep/beast modes. Recommended for standard.**

After Phase 4 initial analysis completes, run iterative depth to catch what confirmation bias prevented in the first pass.

### Iteration Model
- **Iteration 1**: Full coverage depth analysis (already completed in Phase 4.1-4.7)
- **Iteration 2**: Targeted Devil's Advocate re-analysis of UNCERTAIN findings (composite score 0.40-0.69)
- **Iteration 3**: Final targeted pass if ANY uncertain finding remains at Medium+ severity
- **Hard cap**: Maximum 3 iterations total

### Convergence Criteria
1. **Zero uncertain**: If 0 findings score < 0.70 after any iteration → exit loop
2. **No progress**: If NO finding's confidence improved in an iteration → exit loop early
3. **Iteration 2 skip policy**: May ONLY be skipped if ALL uncertain findings are Low/Info severity. If ANY uncertain finding is Medium+ → iteration 2 is **MANDATORY**
4. **Forced CONTESTED**: After all iterations, any finding still < 0.40 → forced to CONTESTED verdict

### Anti-Dilution Rules *(from Plamen — prevents reasoning contamination between iterations)*

**Rule AD-1: Evidence-Only Carryover**
Between iterations, carry forward ONLY:
- Finding ID, title, location, evidence code references (file:line)
- Evidence source tags (`[CODE]`, `[PROD-ONCHAIN]`, etc.)
- Current confidence score
- A focused investigation question
- **Analysis path summary** (1-2 sentences): What the previous agent analyzed and HOW it reasoned — NOT what it concluded. Example: *"Iteration 1 traced numerator manipulation via supply inflation; did not explore divisor staleness or timestamp anchor."*

**Explicitly excluded**: All prior verdicts, confidence assessments, and cross-references.

**Rule AD-2: Hard Devil's Advocate Role**
Iteration 2+ agents receive this STRUCTURAL adversarial framing (research shows soft "think critically" instructions produce <50% divergence; hard DA role produces >99%):

> *"You are the Devil's Advocate Depth Agent. Your PRIMARY job is to find what the previous analysis MISSED — not to re-confirm what it found. For each finding you investigate:*
> *1. Read the analysis path summary (what was explored). Your job is to explore what was NOT.*
> *2. For each CONFIRMED conclusion: ask 'what adjacent bug does this analysis OBSCURE?'*
> *3. For each REFUTED conclusion: ask 'what enabler makes this exploitable after all?'*
> *4. You MUST produce at least one finding or observation that CONTRADICTS or EXTENDS the previous analysis."*

**Rule AD-3: Focused Input Cap**
Each iteration 2+ agent receives at most **5 uncertain findings** in its domain. Prioritize by lowest confidence score.

**Rule AD-4: Fresh Tool Calls Mandatory**
Iteration 2+ agents MUST make their own MCP tool calls (`mcp__claudit__search_findings`, `mcp__sc-auditor__run-slither`) rather than relying on summaries from iteration 1.

**Rule AD-5: New-Evidence-Only Re-Scoring**
Re-scoring after iteration 2+ only upgrades confidence if the agent produced **NEW evidence** — a new code reference, a new MCP tool output, or a new production verification result. Merely restating the same analysis = zero confidence change.

### Finding Card Format for Iteration 2+
```markdown
## Finding [XX-N]: Title
- **Location**: SourceFile:L45-L67
- **Evidence**: [CODE] — validation check at L45; [CODE] — state update at L52
- **Confidence**: 0.42
- **Evidence Gap**: [What specific evidence is missing]
- **Prior Path**: [1-2 sentence analysis path summary — what was explored, not concluded]
- **Investigate**: [Focused question for the DA agent]
```

---

## Phase 4.85: SEMANTIC INVARIANT DUAL-PASS *(NEW — from Plamen's semantic invariant architecture)*

**MANDATORY for deep/beast modes. Skip for light/quick/standard.**

This phase is distinct from the invariant framework defined in Phase 2.3. Phase 2.3 categorizes invariants (Safety, Liveness, Economic, Composability). This phase **exhaustively traces** each invariant across ALL code paths to prove or disprove preservation.

### Pass 1: Invariant Extraction
Extract ALL invariants from:
- **Code**: require/assert statements, comments mentioning "should always", "must never", "invariant"
- **Documentation**: Protocol docs, README, specification files
- **Economic**: Token supply conservation, exchange rate monotonicity, fee collection completeness
- **Structural**: Storage layout assumptions, initialization completeness, access control hierarchy
- **Phase 2.3 categories**: Expand each Safety/Liveness/Economic/Composability category into concrete testable properties

For each invariant, produce:
```
[SEMANTIC-INV-{N}] {Invariant statement}
├── Source: {code comment / documentation / economic property}
├── Variables: {state variables involved}
├── Functions: {all functions that could violate}
└── Category: {Safety / Liveness / Economic / Composability}
```

### Pass 2: Recursive Trace (MANDATORY)
For EACH invariant from Pass 1, perform a **recursive function trace**:

1. **List ALL functions** that read or write ANY variable in the invariant
2. **For EACH function**:
   a. Pre-condition: Is the invariant guaranteed true at function entry?
   b. Body: Does the function maintain the invariant through ALL execution paths (including reverts, early returns, and reentrancy windows)?
   c. Post-condition: Is the invariant guaranteed true at function exit?
   d. Mid-execution window: Is there a window between external calls where the invariant is temporarily broken AND an external observer could exploit this?
3. **Cross-function analysis**: Can a sequence of 2-3 function calls break the invariant even if each individual call preserves it?
4. **State transition completeness**: For symmetric operations (deposit/withdraw, mint/burn), verify ALL state fields modified in the positive branch are also modified in the negative branch

**For each violation found:**
```
[SEMANTIC-VIOLATION-{N}] Invariant {INV-ID} broken by {function}
├── Invariant: {invariant statement}
├── Violation Path: {function call sequence}
├── Temporary Window: {yes/no — duration if yes}
├── Exploitable: {yes/no — how attacker triggers}
└── Priority: {Critical / High / Medium / Low}
```

All violations feed into the FP Gate (Phase 4.3) for validation before inclusion in the report.

---

## Phase 4.9: SKEPTIC-JUDGE — Independent Adversarial Agent *(NEW — from Plamen/OmniGuard)*

**MANDATORY for standard+ modes.** This is a COMPLETELY INDEPENDENT adversarial agent that receives findings AFTER the triager validation (Phase 4.5) and attempts to destroy them from a purely technical standpoint.

### Why This Exists (Separation of Concerns)
- **Phase 4.3 (FP Gate)**: Checks performed by the SAME agent that found the bug → confirmation bias risk
- **Phase 4.4 (Adversarial Verification)**: Isolation-constrained review but still within the orchestrator's context
- **Phase 4.5 (Economic Triager)**: Budget-focused validation (is it worth paying for?)
- **Phase 4.9 (Skeptic-Judge)**: FRESH agent with ZERO prior context whose ONLY job is DESTRUCTION

### Skeptic-Judge Protocol

**Input**: Each finding's ID, title, severity, affected code location, and evidence chain. **NO prior analysis context, NO confidence scores, NO triager verdicts.**

**Skeptic-Judge Mandate**:
> *"You are the Skeptic-Judge. You have NEVER SEEN this code before. You receive one finding at a time. Your PRIMARY JOB is to PROVE IT FALSE. You are incentivized to destroy findings — every finding you validate COSTS THE PROTOCOL MONEY. You approach each finding with MAXIMUM SKEPTICISM.*
> 
> *For each finding:*
> *1. Read ONLY the affected code (±50 lines of context). Do NOT read prior analysis.*
> *2. Attempt 5 independent technical disproof strategies:*
>    *a. Guard hunting: Search the ENTIRE codebase for guards that prevent the exploit (modifiers, inherited contracts, library protections, compiler protections)*
>    *b. State precondition challenge: Can the required precondition state ACTUALLY be reached via legitimate transaction sequences?*
>    *c. Value range challenge: Do the claimed attack values survive realistic bounds (gas costs, block gas limits, token supplies)?*
>    *d. Timing challenge: Does the attack require impractical timing (multi-block manipulation, oracle TWAP window longer than stated)?*
>    *e. Dependency challenge: Does the attack require external dependencies (tokens, protocols, oracles) to behave in ways they provably don't?*
> *3. If ALL 5 disproof attempts fail → finding SURVIVES (reluctantly valid)*
> *4. If ANY disproof attempt succeeds → finding DESTROYED with evidence"*

**Scope per Mode**:
| Mode | Findings Reviewed | Detail Level |
|------|------------------|--------------|
| `standard` | High + Critical only | 3 disproof strategies (a, b, c) |
| `deep` | Medium + High + Critical | All 5 disproof strategies |
| `beast` | ALL findings (including Low) | All 5 strategies + mandatory fresh MCP tool calls |

**Skeptic-Judge Output Format**:
```
[SKEPTIC-{N}] Finding {ID}: {Title}
├── Disproof (a) Guard Hunt: {PASS/FAIL} — {evidence}
├── Disproof (b) State Precondition: {PASS/FAIL} — {evidence}
├── Disproof (c) Value Range: {PASS/FAIL} — {evidence}
├── Disproof (d) Timing: {PASS/FAIL} — {evidence} (deep+ only)
├── Disproof (e) Dependency: {PASS/FAIL} — {evidence} (deep+ only)
├── Verdict: {DESTROYED | SURVIVED | DOWNGRADED}
├── Confidence Adjustment: {+0.10 if survived all 5 | -0.15 per failed strategy}
└── Reasoning: {1-2 sentences explaining why finding lives or dies}
```

**Integration with Pipeline**:
- Findings DESTROYED by Skeptic-Judge are removed from the report (logged in `audit-debug.md`)
- Findings SURVIVED get a +0.10 confidence boost (survived independent adversarial review)
- Findings DOWNGRADED have severity reduced with documented reasoning
- Skeptic-Judge statistics logged in Audit Trace Summary

---

## Phase 4.5: NEMESIS CONVERGENCE LOOP *(beast mode only)*

Read `{resolved_path}/references/nemesis-convergence.md` for full loop instructions.

### Pass 1: Feynman Auditor
Question every line using the 7 Feynman questions. Expose assumptions. Flag suspects with [FQ-N] format.

### Pass 2: State Inconsistency Auditor
Map every coupled state pair. Find mutation gaps. Use Feynman suspects as targets. Flag with [SI-N] format.

### Pass 3-6: Alternating Targeted Passes
Each pass interrogates the previous pass's NEW findings only.
**Convergence**: Stop when 2 consecutive passes produce zero new findings, or 6 passes reached.

### Merge with Phase 4 Findings
- Deduplicate by root cause (keep higher-confidence version)
- Cross-feed confirmation (FQ + SI on same code) = merge with +10 confidence boost
- All merged findings enter Phase 5 for validation
