# Template — `advisory.md` (vendor-coordinated path)

Used when Stage 5 selects `vendor-coordinated`: CRITICAL severity in core protocol scope, private disclosure to security team, CVE requested, 90-day embargo.

Stage 8 substitutes the placeholders with content from `$RUN_DIR/4-impact/F-NN.md`, `$RUN_DIR/5-disclosure/F-NN.md`, and `$RUN_DIR/6-cve/F-NN.md`.

---

```markdown
# Security Advisory for <CRATE NAME>

**Severity**: <CRITICAL | HIGH>
**CVE ID**: <CVE-YYYY-NNNNN> (requested via <MITRE | GitHub Security Advisory>)
**RUSTSEC ID**: <RUSTSEC-YYYY-NNNN if filed> (or "pending")
**Date**: <YYYY-MM-DD>
**Reporter**: <Name / Handle / Org>
**Embargo**: <90 days from disclosure, until YYYY-MM-DD, or fix-release whichever earlier>

## Affected Versions

<crate> versions < X.Y.Z (specifically: <semver range>)

## Vulnerability Description

<One paragraph summary in plain language. State the bug shape, the affected component within the crate, and the worst-case impact.>

## Technical Details

**Affected function**: `<crate>::<module>::<function>` at `<file>:<line-range>`

**Vector**: <vector_id from `dlt-infra-attack-vectors.md`, e.g., A01 — transmute size mismatch>

**Root cause**: <Detailed explanation of the defect — how the code reaches the unsafe state, what invariant is violated.>

**Attack trigger**: <How an attacker forces the vulnerable code path to execute. Cite the entry point from Stage 4's reachability analysis.>

**Tool evidence** (Stage 3 CONFIRMED verdict):

```
<Captured stderr from Miri / Kani / Loom / cargo-fuzz / etc.>
```

The exact golden signature matched is: `<golden_signature substring from the vector catalogue entry>`.

## Impact

- **Tier**: <System Compromise | Data Corruption | Funds At Risk | Denial of Service | Confidentiality Breach | Integrity Weakening>
- **Reachability**: <Remote | Authenticated | Local>
- **Worst case**: <e.g., Remote code execution on validator nodes; consensus fork via state corruption; private key recovery via nonce reuse>
- **Affected operators**: <e.g., All nodes running affected crate versions in production>

## Proof of Concept

Minimal harness to reproduce the bug deterministically:

```rust
<Inline harness file content — same harness used at Stage 3>
```

Run:

```bash
cd <crate-root>
<exact command from $RUN_DIR/3-verification/F-NN/verdict.md>
```

Expected output: `<golden_signature>`

## Mitigation

**Immediate**: <Stop-gap users can apply pre-fix — e.g., disable feature flag, restrict listening interface to localhost, drop external connections.>

**Permanent fix**: <The actual code change. Provide a unified diff if available.>

```diff
- <vulnerable code>
+ <fixed code>
```

**Operator action required**: <e.g., upgrade to X.Y.Z+1; restart validators; rotate keys exposed during embargo window.>

## Acknowledgments

Thanks to <name / handle / org> for reporting this vulnerability and to the <project> maintainers for the prompt fix.

## Timeline

- **<YYYY-MM-DD>**: Reported privately to <vendor security contact>
- **<YYYY-MM-DD>**: CVE ID requested
- **<YYYY-MM-DD>**: Fix landed in <commit / PR>
- **<YYYY-MM-DD>**: Patched versions released
- **<YYYY-MM-DD>**: Advisory published (embargo lifted)

## References

- Vendor advisory: <URL>
- CVE record: <URL>
- Patch: <commit URL>
- Tool evidence (Argus internal): <path or hash>

## AI-provenance disclosure

This vulnerability was discovered using Argus, an AI-assisted Rust security audit pipeline. The deterministic verification (Stage 3 tool-confirmation via <Miri / Kani / Loom>) and the call-graph reachability analysis (Stage 4) are tool-driven and reproducible by any reviewer. The bug-hypothesis-generation step at Stage 2 used an LLM; the validation chain is mechanical from there.

The reporter has manually:
- Re-read the cited code at the cited line numbers
- Independently re-derived the exploit path
- Run the PoC and confirmed the output matches the verdict claim
- Re-written this writeup
```
