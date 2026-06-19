# Argus Benchmarks

Each `.md` file in this directory is one benchmark.

## Format

Benchmark frontmatter:

```yaml
---
repo_url: https://github.com/<owner>/<repo>
repo_ref: <commit-or-tag>            # optional, defaults to main
project_path: programs/my-program    # optional, Cargo workspace member path
project_shape: anchor | cosmwasm | substrate | generic-rust
bounty_url: <bounty page or "none">
target_repo: <github URL or "none">
---
```

Benchmark body lists ground-truth findings, one per stanza:

```
FINDING | severity: High | crate: my-program | module: instructions::stake | function: claim_rewards | bug_class: auth-missing-signer
description: claim_rewards trusts the authority account without `Signer` constraint, allowing anyone to claim on behalf of any user.
expect_in: submit
```

The `expect_in` field is one of `submit | refine | discard`. It tells the eval runner which Argus bucket the finding should land in. Default is `submit`.

## Suggested benchmark sources

- Past audit reports from public Rust DeFi projects (Solana / CosmWasm / Substrate)
- Code4rena Solana / Cosmos audits
- Cantina audits with public reports
- Sherlock audits with public reports
- HackenProof public bounty reports
- Immunefi public Solana / Cosmos disclosures

When adding a new benchmark, ensure:

1. The codebase is publicly cloneable (or otherwise reproducible).
2. Ground-truth findings are sourced from a published audit / disclosure, not derived from running Argus on the codebase.
3. The `expect_in` field reflects what the source audit considered valid (`submit`), needs-more-evidence (`refine`), or rejected (`discard`).

## Running

See `../runner.md`.
