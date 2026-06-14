---
name: move-fuzzer
description: Reference for move-fuzzer, an early-stage (WIP) fuzzer for Move smart contracts built on LibAFL, by fuzzland. It's a native Rust tool the user builds and runs locally, NOT inside Sauna. Use when the user wants to fuzz Aptos/Move contracts with move-fuzzer, run the Aptos fuzzing demo, or asks how to set it up. Sauna helps build it, run demos, and interpret output. The project is at a very early stage.
---

# move-fuzzer (reference)

WIP fuzzer for Move smart contracts, built on [LibAFL](https://github.com/AFLplusplus/libafl). By fuzzland (authors of ItyFuzz). Repo: https://github.com/fuzzland/move-fuzzer

## Important: native WIP tool, not a Sauna capability

move-fuzzer is a Rust project at a very early stage. It builds and runs on the user's machine. Sauna helps build it, run the demo, and interpret findings.

## Run the demo

```sh
./scripts/setup_aptos.sh -c fuzzing-demo -t 30
```

(`-c` selects the demo contract, `-t` the time budget in seconds.) See the repo's `scripts/` for the skip-rebuild flag and other options.

## Notes

- Built on LibAFL, same lineage as ItyFuzz (see `fuzzing-reference/ityfuzz`).
- Expect rough edges; check open issues before relying on it.
- Run `cargo clippy -- -D warnings` before contributing.

## How Sauna assists

1. Help build the project and run the Aptos demo.
2. Pair with the Plamen Aptos/Move skills (`plamen/aptos/*`) and `cdsecurity/rust-audit-prep` for the manual side.
3. Interpret crashes and turn them into Move unit-test repros (see `plamen/aptos/verification-protocol`).
