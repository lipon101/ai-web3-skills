---
repo_url: <fill-in: a real Anchor project with a planted V1 missing-signer bug>
repo_ref: main
project_path: programs/<name>
project_shape: anchor
bounty_url: none
target_repo: none
---

# Benchmark 001 — Anchor missing signer (V1)

A canonical Anchor V1 case: `#[derive(Accounts)]` struct gates a privileged operation but the authority account is `AccountInfo` rather than `Signer<'info>`.

This benchmark validates that:
- Vector Scan and/or Auth/Account angle catch the missing constraint
- Stage 3 produces a Tier-1 or exempt-allowlist PoC (V1 is on the exempt allowlist)
- Stage 4 calibrates severity to High (privileged op is fund-moving)
- Stage 5/6/7 advance to SUBMIT
- Final SUBMIT bucket contains exactly this finding

## Ground truth

```
FINDING | severity: High | crate: <crate> | module: instructions::transfer_authority | function: handler | bug_class: missing-signer-constraint | group_key: <crate>::instructions::transfer_authority::handler|missing-signer-constraint
location: programs/<name>/src/instructions/transfer_authority.rs:<line-range>
expect_in: submit
expected_vector_id: V1
expected_severity: High
expected_poc_tier: exempt-2
```

## Scaffold note (v0.1.10)

This benchmark is a SCAFFOLD. The real Rust source must be authored or imported from an existing audit run. Steps:

1. Replace `repo_url` with a real GitHub repo URL containing this bug shape.
2. Verify ground-truth via manual audit; pin `repo_ref` to a commit where the bug is present.
3. Run Argus against the benchmark; capture output.
4. Compare with `evals/scripts/score-eval.sh` to compute precision / recall.

The eval runner harness in `evals/scripts/run-eval.sh` (NEW v0.1.10) wraps this loop.
