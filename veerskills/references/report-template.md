# Report Template & Finding Classification

Finding severity classification, validation protocol, report structure, and quality assurance checks.

---

## Module 13: Finding Classification

### P0 — CRITICAL
```
Impact:         Complete fund loss, protocol insolvency, unauthorized total drain
Exploitability: Exploitable by any user or flash loan attacker in single transaction
Capital:        $0 (flash loan) to low capital
Skill:          Low-moderate (known patterns, reproducible)
Required:       Working PoC MANDATORY
Examples:       Reentrancy drain, unprotected initialize, infinite mint, oracle manipulation
```

### P1 — HIGH
```
Impact:         Significant fund loss (10-50% of TVL), major state corruption
Exploitability: Moderate conditions required (specific token type, timing, capital)
Capital:        $10k-$1M required
Skill:          Moderate (custom exploit development)
Required:       Working PoC MANDATORY
Examples:       Share inflation, fee-on-transfer accounting, unsafe downcast, access bypass
```

### P2 — MEDIUM
```
Impact:         Minor fund loss (<10% TVL), temporary DoS, value leak under edge conditions
Exploitability: Specific conditions required (unlikely but possible)
Capital:        Variable
Skill:          Moderate-High
Required:       PoC RECOMMENDED
Examples:       Rounding exploitation, stale oracle, unbounded loop DoS, missing slippage
```

### P3 — LOW
```
Impact:         Minimal financial impact, best practice violations, theoretical risk
Exploitability: Requires unusual conditions or provides minimal benefit
Required:       Code reference + explanation
Examples:       Missing events, gas inefficiency, code quality, unchecked zero-address
```

### P4 — INFORMATIONAL
```
Impact:         No direct security impact
Purpose:        Code quality, optimization opportunities, documentation gaps
Required:       Brief description + recommendation
Examples:       Unused variables, floating pragma, missing NatSpec, redundant storage reads
```

### Severity Decision Tree
```
Is there direct fund loss?
├── YES → How much?
│   ├── >50% TVL or total drain → CRITICAL (P0)
│   ├── 10-50% TVL → HIGH (P1)
│   └── <10% TVL → MEDIUM (P2)
├── POSSIBLE (with conditions) → What conditions?
│   ├── Easily achievable (flash loan, any user) → HIGH (P1)
│   ├── Moderate difficulty (specific state, timing) → MEDIUM (P2)
│   └── Unlikely (governance attack, near-impossible) → LOW (P3)
└── NO → Is there state corruption?
    ├── YES → Can it be exploited later for funds? → Escalate severity
    └── NO → LOW (P3) or INFO (P4)
```

---

## Module 14: Finding Validation Protocol

### Step 1: Reproducibility (3/3 required)
```
Test 1: Default parameters
  Command: forge test --match-test test_exploit -vvv
  Input:   Standard amounts (1e18, 100e18)
  Result:  ✅ / ❌

Test 2: Edge case parameters
  Command: forge test --match-test test_exploit -vvv
  Input:   Extreme values (1 wei, type(uint256).max - 1)
  Result:  ✅ / ❌

Test 3: Different block/timestamp
  Command: forge test --match-test test_exploit --fork-block-number {N} -vvv
  Input:   Different chain state
  Result:  ✅ / ❌
```

### Step 2: Impact Quantification
```markdown
| Metric | Value |
|--------|-------|
| TVL at risk | $X |
| % of TVL | X% |
| Users affected | X |
| Attacker profit | $X |
| Attack cost (gas) | X gwei |
| Attack cost (capital) | $X |
| Recovery possible | Yes/No |
| Time to exploit | X minutes/hours |
```

### Step 3: Exploit Feasibility Assessment
```markdown
| Factor | Score (1-5) | Notes |
|--------|------------|-------|
| Capital required | X | Flash loan = 1, $10M+ = 5 |
| Technical skill | X | Script kiddie = 1, zero-day = 5 |
| Time window | X | Instant = 1, needs governance vote = 5 |
| Detection probability | X | Invisible = 1, obvious = 5 |
| Repeatability | X | Once only = 5, infinite = 1 |
```

### Step 4: Root Cause Analysis
```markdown
Root Cause: [Category from vulnerability matrix: RE/AC/AR/OR/DO/EC/UP/CO]
Code Location: [file.sol:L{start}-L{end}]
Violated Assumption: "[What the developer assumed that isn't true]"
Why Existing Mitigations Failed: "[What was supposed to prevent this]"
Pattern Match: [matching-vulnerability-matrix-id, e.g., RE-1, OR-2]
```

### Step 5: Mitigation Analysis
```markdown
| Factor | Assessment |
|--------|-----------|
| Fix complexity | Low / Medium / High |
| Breaking changes | Yes / No |
| Gas impact | +X% / negligible |
| Backward compatibility | Compatible / Breaking |
| Recommended fix | [Specific code change] |
| Alternative fix | [If primary fix has trade-offs] |
| Verification | [How to verify fix works] |
```

### Step 6: False Positive Elimination
```markdown
Devil's Advocate Checklist:
- [ ] Searched all files for preventing constraints
- [ ] Checked inherited contracts and libraries
- [ ] Verified against protocol documentation
- [ ] Dry-ran with concrete values (at least 3 scenarios)
- [ ] Checked if similar findings were invalidated on Solodit
- [ ] Confirmed no governance parameters prevent this
- [ ] Verified compiler version implications
Conclusion: [CONFIRMED / FALSE POSITIVE]
If FP: [Reason for dismissal]
```

---

## Module 15: Report Structure

### Section 1: Executive Summary
```markdown
# VeerSkills Security Audit Report

## Executive Summary

**Protocol:** [Name]
**Version:** [Commit hash]
**Audit Date:** [YYYY-MM-DD]
**Auditor:** VeerSkills Automated Audit Engine
**Network:** [EVM/Solana/Move/TON/Starknet/Cosmos]
**Scope:** [List of contracts/files in scope]

### Methodology
12-phase pipeline: RECON → CONTEXT → THREAT → MAP → HUNT (incl. REVERSE, DATA_FLOW, BOUNDARY) → ATTACK → NEMESIS → VALIDATE → FUZZ → REPORT → SELF-AUDIT
- Static analysis: Slither + Aderyn + Storage Layout Analyzer
- Dynamic analysis: Foundry fuzz + Echidna
- Formal verification: Certora/Halmos (if beast mode)
- Manual review: Multi-agent vulnerability matrix sweep

### Risk Assessment
| Overall Risk | [LOW / MEDIUM / HIGH / CRITICAL] |
|---|---|
| Critical findings | X |
| High findings | X |
| Medium findings | X |
| Low findings | X |
| Informational | X |

### Findings Summary Table
| ID | Title | Severity | Status |
|----|-------|----------|--------|
| OG-1 | [title] | CRITICAL | Open |
| OG-2 | [title] | HIGH | Open |
| ... | ... | ... | ... |
```

### Sections 2-5: Findings by Severity

Each finding follows this format:
```markdown
## OG-{N}: [Title]

**Severity:** CRITICAL / HIGH / MEDIUM / LOW / INFO
**Category:** [RE/AC/AR/OR/DO/EC/UP/CO]
**Confidence:** Confirmed / Likely / Possible
**Location:** [file.sol:L{start}-L{end}](file:///path/to/file.sol#L{start}-L{end})

### Description
[What is vulnerable and why. Technical details.]

### Impact
[What attacker gains. Quantified impact.]

### Attack Scenario
1. Attacker does X
2. Due to Y, state becomes Z
3. Attacker extracts W

### Proof of Concept
\`\`\`solidity
// PoC code or reference to PoC file
\`\`\`

### Root Cause
[Underlying assumption violated]

### Recommendation
\`\`\`diff
- vulnerable code
+ fixed code
\`\`\`

### Evidence Sources
- Slither detector `{id}`: [description]
- Cyfrin checklist `{id}`: [description]
- Solodit finding: [URL]

### Falsification Attempts
- [What was checked to ensure this is not a false positive]
```

### Section 6: Statistical Analysis
```markdown
## Statistical Analysis

### Code Metrics
| Metric | Value |
|--------|-------|
| Total Contracts | X |
| Total Lines (nSLOC) | X |
| External Functions | X |
| State Variables | X |
| External Calls | X |
| Complexity Score | X |

### Vulnerability Distribution
| Class | Checked | Issues | Coverage |
|-------|---------|--------|----------|
| Reentrancy (RE) | 5/5 | X | 100% |
| Access Control (AC) | 5/5 | X | 100% |
| ... | ... | ... | ... |
| **Total** | **40/40** | **X** | **100%** |
```

### Section 7: Security Posture (SWOT)
```markdown
## Security Posture Assessment

### Strengths
- [What the protocol does well]

### Weaknesses
- [Where the protocol is vulnerable]

### Opportunities
- [What could improve security]

### Threats
- [External factors that could affect security]
```

### Section 8: Testing Summary
```markdown
## Testing Summary

### Static Analysis
| Tool | Findings | High | Medium | Low |
|------|----------|------|--------|-----|
| Slither | X | X | X | X |
| Aderyn | X | X | X | X |

### Dynamic Analysis
| Suite | Runs | Failures | Coverage |
|-------|------|----------|----------|
| Invariant fuzz | 10,000 | 0 | 95%+ |
| Attack fuzz | 50,000 | 0 | 90%+ |
| Edge case fuzz | 20,000 | 0 | 85%+ |

### Manual Review
| Phase | Duration | Findings |
|-------|----------|----------|
| MAP | Xh | System map |
| HUNT | Xh | X suspects |
| ATTACK | Xh | X confirmed |
```

### Section 9: Appendix
```markdown
## Appendix

### Tools Used
| Tool | Version | Purpose |
|------|---------|---------|
| Slither | X.Y.Z | Static analysis |
| Aderyn | X.Y.Z | Static analysis |
| Foundry | X.Y.Z | Testing + fuzzing |
| Echidna | X.Y.Z | Property testing |

### Coverage Reports
[Attached LCOV report or summary]

### PoC Code
[All PoCs with running instructions]

### Commit Hash
`{commit_hash}` on branch `{branch}`

### Disclaimer
This report represents findings at a point in time. It does not guarantee
the absence of all vulnerabilities. Smart contract security is an ongoing process.
```

---

## Module 16: Quality Assurance Checklist

Before delivering the report, verify ALL of these:

### QA-1: Completeness
- [ ] All findings have: title, severity, description, location, recommendation
- [ ] All Critical/High findings have working PoCs
- [ ] All Medium+ findings have impact quantification
- [ ] Executive summary reflects all findings
- [ ] All 40 vulnerability matrix checks are marked (checked + safe or found issue)
- [ ] Appendix includes tools, versions, commit hash

### QA-2: Accuracy
- [ ] Severity consistent with decision tree
- [ ] Impact properly quantified (not just "funds at risk")
- [ ] Technical details verified against actual code
- [ ] Line references correct and up-to-date
- [ ] No copy-paste errors from templates

### QA-3: Clarity
- [ ] Non-technical executive summary
- [ ] Terms defined on first use
- [ ] Attack scenarios use concrete values (not abstract)
- [ ] Logical flow: vulnerability → impact → fix
- [ ] No ambiguous language ("might", "could possibly")

### QA-4: Actionability
- [ ] Every finding has specific fix recommendation
- [ ] Fix complexity estimated (low/medium/high)
- [ ] Code examples for recommended fixes (diff format)
- [ ] Verification steps for each fix
- [ ] Priority order for remediation

### QA-5: Zero False Positives
- [ ] Every finding survived Devil's Advocate protocol
- [ ] 3x reproducibility for all Critical/High
- [ ] Falsification attempts documented per finding
- [ ] No findings based solely on static analysis without manual verification
- [ ] No "admin could rug" type findings (P4 protocol enforced)
