---
name: aflplusplus
description: Reference for AFL++ (American Fuzzy Lop plus plus), a state-of-the-art coverage-guided native fuzzer for C/C++/Rust and binary-only targets. AFL++ is a NATIVE toolchain (compiler wrappers + fuzzer binaries) that runs in the user's own environment or a Docker container, NOT inside Sauna. Use this skill when the user wants to fuzz native code, set up afl-clang-fast / CMPLOG instrumentation, build a harness, run a fuzzing campaign, triage crashes, or asks how to install/use AFL++. Sauna helps write harnesses, build commands, and triage crash output; the campaign runs on the user's machine.
---

# AFL++ (reference)

AFL++ is a superior fork of Google's AFL: more speed, better mutations, better instrumentation, custom-module support. Licensed AGPL-3.0-or-later. Repo: https://github.com/AFLplusplus/AFLplusplus · Docs: `docs/fuzzing_in_depth.md` in the repo.

## Important: this is a native tool, not a Sauna capability

AFL++ compiles and runs target binaries. It cannot run inside Sauna's sandbox. The user runs it locally or in Docker. Sauna helps author harnesses, instrument builds, design dictionaries/seed corpora, and triage crashes the user reports.

## Install (on the user's machine)

Docker (easiest, x86_64 + arm64):
```bash
docker pull aflplusplus/aflplusplus
docker run -ti -v /path/to/your/target:/src aflplusplus/aflplusplus
```
Build from source: follow `docs/INSTALL.md` in the repo (recommended for best performance).

## Quick start (source available)

```bash
# 1. Instrument the target
export CC=afl-clang-fast CXX=afl-clang-fast++
./configure && make            # or your build system
# 2. (Optional) build a second CMPLOG binary for better coverage
AFL_LLVM_CMPLOG=1 make -o target.cmplog
# 3. Fuzz
afl-fuzz -i seeds/ -o findings/ -- ./target @@
```

- `@@` is replaced with the input file path; drop it for stdin targets.
- Use `-c target.cmplog` to enable CMPLOG (RedQueen-style input-to-state).
- Parallel: one `-M` main + multiple `-S` secondary instances.

## Notes for relevance

- For smart-contract work, AFL++ matters mainly because ItyFuzz / LibAFL build on the AFL++ ecosystem, and for fuzzing native off-chain components (sequencers, indexers, parsers, cryptographic libs, Rust node clients).
- For binary-only targets see `docs/fuzzing_binary-only_targets.md` (QEMU/FRIDA modes).

## How Sauna assists

1. Write a fuzz harness (`LLVMFuzzerTestOneInput`-style or argv/stdin) for the target.
2. Produce the instrumented build commands and a parallel-campaign launch script.
3. Suggest seed corpus + dictionary content.
4. Triage `findings/crashes/` output and minimize repros (`afl-tmin`, `afl-cmin`).
