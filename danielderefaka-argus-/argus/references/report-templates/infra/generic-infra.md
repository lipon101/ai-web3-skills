# Template — `generic-infra.md` (public-issue path)

Used when Stage 5 selects `generic-infra`: LOW severity in any scope. Public GitHub issue or PR. No embargo. No CVE.

Stage 8 substitutes placeholders.

---

```markdown
# Issue: <Title summarizing the bug shape, e.g., "Integer underflow in reward calculation when stake < proposer_bond">

**Crate**: <crate> <version>
**Severity**: <LOW | MEDIUM>
**Vector**: <vector_id from `dlt-infra-attack-vectors.md`, e.g., C03 — arithmetic underflow>
**Reporter**: <Name / Handle>
**Date**: <YYYY-MM-DD>

## Description

<Short paragraph describing the bug. Plain language, no embargo concerns since this is public from the start.>

## Details

**Location**: `<crate>::<module>::<function>` at `<file>:<line-range>`

<2-3 paragraphs: what the code does wrong, when it's triggered, what happens.>

**Tool evidence** (Stage 3 CONFIRMED):

```
<tool stderr — Miri / Kani / Loom / cargo-fuzz output excerpt>
```

## Steps to Reproduce

```bash
cd <crate-root>
<exact command>
```

Expected output: `<golden_signature>`

Optionally inline harness:

```rust
<harness file content>
```

## Suggested Fix

<Concrete code change. Provide a diff if available; otherwise describe the approach.>

```diff
- <vulnerable code>
+ <fixed code>
```

## Impact (LOW context)

- **Tier**: <Integrity Weakening | Confidentiality Breach | Denial of Service> (LOW per matrix)
- **Bounded by**: <what limits the worst-case impact — single-user, bounded amount, only-in-test-config, etc.>
- **Why this is LOW not MEDIUM**: <if downgrade rule applied: cite TRUSTED-ROLE-REQUIRED / PRACTICAL-DIFFICULTY / BOUNDED-IMPACT / UPGRADEABLE>

## Additional Context

- Related issues / PRs: <links if any>
- RustSec / NVD / GHSA cross-check: <result from Stage 6, likely "none" for LOW severity>
- Reachability path: `<entry → ... → vulnerable_function>` (from Stage 4)

## AI-provenance note

Reported using Argus (Rust audit pipeline, `infra` mode). Stage 3 deterministic-tool verification was used; bug is mechanically reproducible. Reporter has manually re-read the cited code and confirmed the reproduction.
```
