# Phase 7: REPORT — Final Deliverable

## 7.1 Finding Classification

| Level | Label | Criteria |
|-------|-------|----------|
| P0 | CRITICAL | Complete fund loss, exploitable by anyone, working PoC required |
| P1 | HIGH | Significant loss (10-50% TVL), moderate capital/skill, PoC required |
| P2 | MEDIUM | Minor loss (<10%), specific conditions, PoC recommended |
| P3 | LOW | Minimal impact, best practice violations |
| P4 | INFO | Gas optimizations, code quality, documentation |

## 7.2 Report Structure *(UPGRADED — from Forefy + solidity-auditor-skills)*

Generate `VEERSKILLS_AUDIT_REPORT.md` in the versioned output directory with:

1. **Executive Summary** *(enhanced from Forefy)*:
   - **Protocol Overview**: What DeFi problem does this solve? Industry vertical, unique features
   - **User Profile**: Primary users, interaction patterns, funds at stake
   - **Total Value Locked**: Current or expected TVL
   - **Security Budget**: Estimated budget range based on TVL (~10% of TVL)
   - **Threat Model Summary**: Primary threats identified (from Phase 1.6)
     - Economic attackers targeting [specific mechanisms]
     - Flash loan exploits affecting [specific functions]
     - Governance attacks on [specific parameters]
     - Oracle manipulation risks in [specific feeds]
   - **Security Posture Assessment**: Overall Risk Level (High/Medium/Low)
   - **Findings Summary Table**: Count by severity (X Critical, Y High, Z Medium, W Low)
   - **Key Risk Areas**: Top 3 numbered risk areas with protocol context

2. **Scope Table** *(NEW — from solidity-auditor-skills)*:
   Present in-scope contracts in a clean table format:
   ```markdown
   | Contract | SLOC | Purpose | Libraries |
   |----------|------|---------|-----------|
   | Vault.sol | 342 | Core deposit/withdraw logic | OpenZeppelin, Solmate |
   | Strategy.sol | 156 | Yield generation | Uniswap V3 |
   | Oracle.sol | 89 | Price feeds | Chainlink |
   ```
   - **SLOC**: Source Lines of Code (excluding comments/blanks)
   - **Purpose**: One-sentence description
   - **Libraries**: Key external dependencies

3. **Table of Contents — Findings** *(from Forefy)*:
   Include triager status for each finding:
   ```
   ### Critical Findings
   - C-1 [Impact] via [Weakness] in [Feature] (VALID)
   - C-2 [Impact] via [Weakness] in [Feature] (QUESTIONABLE)
   ### High Findings
   - H-1 [Impact] via [Weakness] in [Feature] (VALID)
   - H-2 [Impact] via [Weakness] in [Feature] (DISMISSED)
   ### Medium / Low / Info ...
   ```

4. **Critical Findings**: Full details + PoC + attack scenario + mitigation + triager validation (sorted by confidence)
5. **High Findings**: Full details + PoC + attack scenario + mitigation + triager validation
6. **Medium Findings**: Description, impact, recommended fix, triager verdict
7. **Low/Informational**: Description, best practice reference, triager verdict

8. **Confidence Threshold Separator** *(NEW — from solidity-auditor-skills)*:
   Insert a clear visual separator before findings with confidence < 80:
   ```markdown
   ---
   ## Below Confidence Threshold (60-79)
   
   The following findings have confidence scores between 60-79. They represent potential issues that require additional validation or have uncertain exploitability. These are included for completeness but should be prioritized lower than confirmed findings above.
   
   ---
   ```

9. **Below Confidence Threshold**: Findings with confidence 40-79 (description only, no fix)
10. **Statistical Analysis**: Code metrics, vulnerability distribution by class, vector triage summary
11. **Security Posture (SWOT)**: Strengths, weaknesses, opportunities, threats
12. **Coverage Analysis**: Protocol layer coverage (from Phase 2.4 Coverage Plan)
13. **Testing Summary**: Static analysis results, dynamic analysis, manual review, vector coverage
14. **Appendix**: Tools used, coverage reports, PoC code, commit hash, debug log summary

---

## Phase 7.5: MISSED-BUG SELF-AUDIT *(NEW — mandatory all modes)*

**MANDATORY** — prevents coverage blind spots from going undetected. The most dangerous audit failure is not a false positive — it's a missed bug.

### 7.5.1 Coverage Verification
For each protocol component identified in Phase 2, verify:
```
□ Component was read and analyzed by at least one agent
□ At least one attack vector was triaged for relevance
□ Static analysis tools scanned the component
□ If complex: function-level analysis completed
```

### 7.5.2 Missed Pattern Cross-Check
Compare against known missed-bug patterns from `references/missed-bug-patterns.md`:
```
□ Complex state transitions with multiple conditions
□ Permissionless functions with economic externalities
□ View functions that affect state elsewhere
□ Constructor/initialization edge cases
□ Upgradeable contract state migration
□ Cross-contract composability edge cases
```

### 7.5.3 Self-Audit Output
Include in the report appendix:
```
## Missed-Bug Self-Audit Results
- Components Verified: {N}/{Total}
- Coverage Gaps Identified: {N} (with remediation)
- Missed-Pattern Cross-Check: {PASS/FAIL — which patterns}
- Confidence in Coverage: {0-100%} — remaining uncertainty areas
```

If coverage gaps are identified → log them and note as "areas requiring additional review" in the report.
