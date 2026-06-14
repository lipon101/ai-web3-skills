---
repo_url: <fill-in>
repo_ref: main
project_path: <path>
project_shape: anchor
bounty_url: none
target_repo: none
---

# Benchmark 003 — Math Precision arithmetic overflow (V12)

Solana BPF program with `u64::checked_add` missing on a value-moving function. This benchmark also validates Stage 3.5 Kani integration: Kani should find a counterexample.

## Ground truth

```
FINDING | severity: High | crate: <crate> | module: instructions::deposit | function: handler | bug_class: unchecked-arithmetic-overflow | group_key: ...|unchecked-arithmetic-overflow
location: programs/<name>/src/instructions/deposit.rs:<line-range>
expect_in: submit
expected_vector_id: V12
expected_severity: High
expected_poc_tier: 1
expected_stage_3_5: kani-counterexample-found
```

(scaffold)
