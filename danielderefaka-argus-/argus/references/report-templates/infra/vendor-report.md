# Template — `vendor-report.md` (vendor-direct path)

Used when Stage 5 selects `vendor-report`: CRITICAL in independent-implementation scope, or HIGH/MEDIUM in any scope. Private disclosure to maintainer via email or GitHub private security advisory. CVE optional (decided in Stage 6 per CVE matrix).

Stage 8 substitutes the placeholders with content from `$RUN_DIR/4-impact/F-NN.md`, `$RUN_DIR/5-disclosure/F-NN.md`, and `$RUN_DIR/6-cve/F-NN.md`.

---

```markdown
# Vulnerability Report — <Crate> <Version>

**Severity**: <HIGH | MEDIUM>
**CVE**: <YES — CVE-YYYY-NNNNN requested | OPTIONAL — see decision below | NO>
**Vector**: <vector_id, e.g., C02 — Vec::with_capacity overflow>
**Reporter**: <Name / Handle / Email>
**Date**: <YYYY-MM-DD>

## Summary

<One paragraph: the bug shape, the affected function, the worst-case impact.>

## Location

**Function**: `<crate>::<module>::<function>`
**File**: `<path>:<line-range>`
**Reachable from**: `<entry-point function from Stage 4 reachability analysis>`

## Technical Details

<2-4 paragraph explanation. Cover:
- The defect (what the code does wrong)
- The trigger conditions (what attacker input or state leads to it)
- The propagation (how the immediate effect becomes a security impact)
- Any preconditions the attacker must satisfy>

**Tool evidence** (Stage 3):

```
<captured tool stderr — Miri error, Kani counterexample, fuzz crash, etc.>
```

## Reachability

- **Bucket**: <Remote | Authenticated | Local>
- **Call path**: `<entry → ... → vulnerable_function>`
- **Attacker control**: <which arguments / fields / bytes the attacker controls along the path>
- **Dynamic-dispatch over-approximation**: <yes (any-implementor reachable) | no>

## Impact

- **Tier**: <System Compromise | Data Corruption | Funds At Risk | Denial of Service | Confidentiality Breach | Integrity Weakening>
- **Concrete consequence**: <e.g., DoS lasting until process restart, leak of N bytes of adjacent stack memory, fork of consensus state>
- **Affected scope**: <single node / all nodes running the crate / specific component types>

## Reproduction

```bash
cd <crate-root>
<exact command from $RUN_DIR/3-verification/F-NN/verdict.md>
```

Expected output: `<golden_signature substring>`

Harness file: <inline below or path to attached file>

```rust
<harness content>
```

## Suggested Fix

<Concrete code change. Provide a unified diff or pseudocode. If the fix has design implications (API break, perf regression), note them.>

```diff
- <vulnerable code>
+ <fixed code>
```

**Side effects of the fix**: <any backwards-compat or perf consideration>

## CVE Recommendation

- **Decision**: <YES | OPTIONAL | NO>
- **Reasoning**: <one paragraph citing the CVE matrix row from Stage 6>
- **Existing duplicate**: <RUSTSEC-YYYY-NNNN or "none" from Stage 6 cross-check>

If YES or OPTIONAL: see `$RUN_DIR/6-cve/F-NN.cve-request.json` for pre-filled CVE request.

## Contact

- **Reporter**: <name + email>
- **Preferred communication**: <encrypted email / private GitHub advisory / Signal>
- **Disclosure timeline preference**: <happy to coordinate / 90-day embargo / immediate>

## AI-provenance disclosure

Vulnerability discovered using Argus (Rust security audit pipeline, `infra` mode). Stage 3 verification was tool-driven (<Miri / Kani / Loom / cargo-fuzz / etc.>); the bug is mechanically reproducible. The reporter has manually re-read the cited code, re-derived the exploit, and confirmed the PoC output.
```
