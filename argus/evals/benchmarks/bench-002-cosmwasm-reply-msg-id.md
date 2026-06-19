---
repo_url: <fill-in: CosmWasm project with planted V69 reply-msg-id bug>
repo_ref: main
project_path: contracts/<name>
project_shape: cosmwasm
bounty_url: none
target_repo: none
---

# Benchmark 002 — CosmWasm reply handler not validating msg.id (V69)

Reply handler matches on `msg.result` but ignores `msg.id` — replies for handler A processed as if for handler B.

## Ground truth

```
FINDING | severity: High | crate: <crate> | module: contract::reply | function: reply | bug_class: reply-msg-id-not-checked | group_key: <crate>::contract::reply::reply|reply-msg-id-not-checked
location: contracts/<name>/src/contract.rs:<line-range>
expect_in: submit
expected_vector_id: V69
expected_severity: High
expected_poc_tier: 3
```

(scaffold; see bench-001 for filling-in instructions)
