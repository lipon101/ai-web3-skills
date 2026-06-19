# PoC Standards — Stage 3 gate

This is the most important gate in the pipeline. A finding without a runnable PoC has not earned the right to advance. Read this file at Stage 3 start.

## Pre-flight: toolchain check

Before attempting any PoC, run the toolchain check:

```bash
bash $SKILL_DIR/scripts/install-deps.sh <project-root> --dry-run
```

The script auto-detects project shape (Anchor / CosmWasm / Substrate / Solana-native / generic-Rust) and reports which of `rustup`, `cargo`, `solana`, `anchor`, `avm`, `node`, `yarn`, and the `wasm32-unknown-unknown` target are missing.

**Exit codes:**
- `0` → all required tools present, proceed to Tier 1
- `2` → missing tools, action required

If exit code is `2`, use `AskUserQuestion` to ask the user:

> "Argus needs to install missing toolchain dependencies to run Tier 1-2 PoCs (`<list of missing tools>`). All installs are user-space (no sudo) via rustup / cargo / solana-install / avm. How should I proceed?"

Options:
- `Install everything — run install-deps.sh --install` → run `bash $SKILL_DIR/scripts/install-deps.sh <project-root> --install`, then re-run `--dry-run` to confirm. Continue to Tier 1.
- `Skip install — proceed without Tier 1-2` → set `poc-tier-cap = 3` for the entire run; Tier 4 written derivation becomes the maximum. Surface as a mode warning in Stage 8 output.
- `Cancel run` → abort the pipeline.

**Discipline rules:**
- Never auto-install without the explicit user choice. Even in auto-mode, Stage 3 stops to ask once.
- The `--install` mode runs only user-space installs (rustup, cargo, solana-install-init, avm, npm). System-package installs (clang, protobuf, cmake) are *suggested* in the script's output for the user to handle separately — Argus never sudo-installs.
- After install, re-run `--dry-run` and verify exit code `0` before proceeding. If still `2`, surface the failure to the user with the script's stderr; do not silently proceed.

If the user picks "skip install", every Stage 3 verdict file must record `toolchain-skipped: yes` and the maximum reachable PoC tier is 3. Tier-3 PoCs in this mode are written-derivation only since no test harness can run.

## PoC tier preference

**Tier-1 E2E is THE PRIMARY TARGET for every finding.** Stage 3 attempts Tier-1 first, exhaustively, including discovering and configuring any RPC dependency. Tier-2/3 are fallbacks that require explicit justification of why Tier-1 was infeasible. Tier-4 written derivation is restricted to cases where the 8-question Tier-3-buildable self-audit confirms infeasibility on every question.

## Mandatory captured output (NEW v0.2.3 — empirical-research finding)

**The single strongest signal in public contest-judging data is "execution with captured output" vs. "description alone".** Across Solana / CosmWasm / Substrate research streams, judges accepted PoCs at significantly higher rates when the writeup included:

- Captured stdout/stderr from the test run
- Transaction hash / signature / block height (for real-validator runs)
- Quoted assertion failures from the buggy build + assertion successes from the fixed build
- Real numeric values (gas used, CU consumed, weight applied) — not "expected"

Conversely, written-derivation PoCs (no execution) get downgraded even when the math is correct.

**Stage 3 verdict.md MUST include captured output for every Tier-1, Tier-2, and Tier-3 PoC.** No exceptions. A PoC that compiles but doesn't have captured output caps at Tier-3 certainty (60-79). A PoC with captured output that demonstrates the buggy behavior AND verifies the fix lands in the upper half of its tier.

For Tier-4 (written derivation), no output exists — but the verdict MUST cite specific code lines AND quote real numeric inputs / on-chain data with sources.

## Bug-class × harness matrix (NEW v0.2.3 — empirical-research finding)

The "Tier 1 = any real harness" rule conflates two different things. Research across ~30+ contests showed acceptance rates differ by **bug class**, not just by harness type. Some bug classes accept mocked-runtime harnesses; others systematically require real-node execution.

| Bug class | Mocked-runtime harness sufficient? | Real-node required? | Mainnet-fork required? |
|-----------|-----------------------------------|---------------------|-----------------------|
| Math / arithmetic / overflow / rounding | yes (`solana-program-test`, `cw-multi-test`, mock.rs) | no | no |
| State-machine logic / access control / signer checks | yes | no | no |
| Borsh / serde / scale-codec deserialization | yes | no | no |
| Storage mutation (state-not-saved, V-class) | yes | no | no |
| Pure circuit-constraint / ZK soundness | yes (unit test on circuit) | no | no |
| Cross-program CPI integrity (V7, V8) | partial (mocked CPI may not catch all) | **yes** for non-trivial CPI graphs | no |
| Re-entry via callbacks (V8, V26, V35) | partial | **yes** (CW20 / Token-2022 hooks need real runtime) | no |
| **IBC packet handling / cross-chain ordering** | **NO** | **yes** (`wasmd` localnet, multi-chain) | maybe |
| **Fee-on-transfer / Token-2022 transfer-hook math** | **NO** | **yes** (real SPL Token-2022 / CW20 with hooks) | no |
| **Oracle staleness / liquidity-dependent** | partial (math part only) | **yes** | **yes** for live oracle / pool state |
| **MEV / sandwich / frontrun ordering** | **NO** | **yes** (Jito bundle / mempool) | maybe |
| **Runtime-upgrade / migration / set_code timing** | **NO** | **yes** (`try-runtime --execution wasm`) | **yes** for pre-state-uri |
| **Validator-set / consensus / finality** | **NO** | **yes** | **yes** |
| **Bridge / cross-chain supply** | partial | **yes** | **yes** |
| **Custom Cosmos message dispatch / sudo** | **NO** | **yes** (`wasmd` localnet) | no |
| **Gas metering / mispricing / non-determinism (CW)** | **NO** (per Hacken MANTRA Chain audit: outdated CosmWasm risks "stack overflow, gas mispricing, and non-deterministic queries" — cw-multi-test misses these) | **yes** (`wasmd` localnet) | no |
| **Source-modified-with-injected-output (any ecosystem)** | n/a | n/a | n/a — **near-automatic kill** |
| **Target = Immunefi bug bounty (any bug class)** | n/a | varies | **yes** (per Immunefi PoC Guidelines default) |

**Rule**: when the finding's bug class is in a row with "**NO**" or "**yes** required", Stage 3 MUST escalate the harness to the required tier. Finding the bug at Tier-3 in the "math" class is fine; finding the bug at Tier-3 in the "IBC" class is a procedural failure — the harness doesn't have the surface to demonstrate the bug.

Stage 2 angles MUST tag each finding with its `bug_class`. Stage 3 reads the matrix and demands the right harness tier.

### When the matrix forces an escalation

If the matrix says "real-node required" and the toolchain is missing, Stage 3 stops and asks via `AskUserQuestion`:

> "F-NN is a {bug_class} bug. Per the bug-class × harness matrix, this requires a real {wasmd / try-runtime / solana-test-validator} harness. The toolchain is currently missing. How should I proceed?"
>
> - `Install required tool and proceed (recommended)`
> - `Skip Tier-1; demote to Tier-3 with explicit caveat in writeup that the harness is insufficient for this bug class`
> - `Cancel finding`

Demoting to Tier-3 in this case is a STRONG SIGNAL the writeup MUST surface — the user reading the SUBMIT bucket knows that a manual real-node PoC is required before submission. Stage 8 mode-warning: "harness-mismatch — N findings demoted from required real-node to Tier-3; user MUST re-validate with real harness before submission."

**The certainty floor for `ADVANCE`**:

- **Normal mode** (toolchain available): floor = **80**. Tier-1/Tier-2 PoCs reachable; the 80 floor reflects "real test executed" quality.
- **Toolchain-skipped mode** (UPDATED in v0.2.1): floor = **60**. Tier-3 is the structural maximum; Tier-3 ceiling is 79. The 80 floor in this mode is unreachable by construction and would `DOWNGRADE(refine)` every finding regardless of merit.

**Why the v0.2.1 fix**: the swafe Code4rena 2025-11 shadow-audit run had M-01 (guardian-share replay) and M-04 (replayable recovery requests) at certainties 70-78. Both were genuine Mediums per the C4 result. Both got stuck in REFINE because the 80 floor was unclearable. Lowering to 60 in toolchain-skipped mode aligns the floor with the Tier-3 ceiling — same gate logic, just a reachable threshold.

**This is not loosening strictness** — the floor still discriminates by quality within the achievable tier (60 is the Tier-3 minimum; 79 is the Tier-3 maximum). What changes is that the gate is no longer self-fulfilling.

Stage 3 verdict file MUST record:

```
certainty_floor_applied: 80 | 60
floor_rationale: "normal-mode" | "toolchain-skipped: Tier-3 ceiling at 79; floor lowered to 60 per v0.2.1"
```

Stage 8 final output adds a mode warning when ANY SUBMIT finding cleared the 60 floor (rather than 80):

> ⚠️ Mode warning: shadow-mode-promotion — N findings advanced under the toolchain-skipped floor (60). User MUST run a real PoC before any platform submission; the standard AI-provenance discipline applies with extra weight here.

Below the applicable floor → `DOWNGRADE(refine)` with a note about what additional proof is needed; the finding does NOT advance to Stage 4 with weak proof.

Certainty rubric (UPDATED v0.2.4 — Tier 1+2 collapsed for contests; platform-aware tiering):

- **Tier 0 — Mainnet-Fork / Live-State E2E**: **95-100** (real validator + real on-chain state via `--clone` / `try-runtime --pre-state-uri` / `wasmd genesis import-state`)
- **Tier 1 — Validated Integration**: **88-94** (any harness running the project's real program code unmodified — `anchor test --localnet`, BanksClient/`solana-program-test`/bankrun, `cw-multi-test`'s `App`, `wasmd` localnet, Substrate `mock!`/`ExtBuilder`, Soroban `Env` test-utils, `try-runtime` against synthetic state)
- **Tier 2 — Unit Test**: 75-87 (Rust `#[test]` exercising program logic without entrypoint dispatch)
- **Tier 3 — Written Derivation**: 40-70 (numbered attack steps + code refs + worked numeric example, no executed code)
- **Exempt allowlist** (citation-only): 75 baseline (capped; no execution)

**Tier-1+2 collapse rationale (NEW v0.2.4 — empirical research finding)**:

Claude Web's empirical research across ~115 catalogued findings on Code4rena / Sherlock / Cantina Rust contests showed:

| Harness | Acceptance rate at filed severity |
|---------|------------------------------------|
| solana-mainnet-fork | 91.7% (small N=12, Immunefi-skewed) |
| substrate-mock (`mock!`/`ExtBuilder`) | 90.9% |
| cw-multi-test | 92.7% |
| anchor-test-localnet | 92.5% |
| **BanksClient / SolanaProgramTest / bankrun** | **90.0%** |
| try-runtime | 100% (small N=4) |
| wasmd-localnet | 100% (small N=6) |
| unit-test-only | 73.7% |
| **written-derivation** | **57.6%** |
| exempt-citation-only | 20.0% |

The 2.5pp gap between anchor-test-localnet and BanksClient is **statistical noise**, not signal. The **35pp cliff** sits between runnable harnesses and written-derivation. v0.2.3's separation of "Tier 1 (real validator) vs Tier 2 (integration test)" was empirically wrong on contest platforms. v0.2.4 collapses them.

**The harness type does NOT predict acceptance.** What predicts acceptance:
1. Captured output present in writeup (+20-25pp)
2. Program-under-test source unmodified (+15pp; modified-with-`panic!` is near-automatic kill)
3. Realistic preconditions (+10pp)
4. Runnable code present at all vs written-derivation (+30pp cliff)

**Platform-aware escalation rule (NEW v0.2.4)**:

When `target_platform == Immunefi`, the rubric SHIFTS:
- Tier 1 (Validated Integration) is the FALLBACK, not default. Per Immunefi PoC Guidelines: *"The smart contract PoC should always be made by forking the mainnet using tools like Hardhat or Foundry. No unit test PoCs will be accepted."*
- Tier 0 (Mainnet-Fork) is the DEFAULT for Immunefi targets.
- A Tier-1 PoC against an Immunefi target is acceptable ONLY when the program's bounty page explicitly endorses test-suite fallback (the conditional clause: *"If forking the mainnet state is not feasible, using the project's existing test suite is an acceptable alternative"*).

Detect platform from the bounty URL collected at run start. Stage 6 records `target_platform` in `bounty-page.md`; Stage 3 reads it and applies the rubric shift.

**Drift-class per-program override (NEW v0.2.4)**:

Some programs have stricter clauses than Immunefi's default. Drift Protocol's bounty page: *"For critical and moderate bugs, we require a proof of concept done on a privately deployed mainnet contract."* Marinade: *"All smart contract bug reports must come with a PoC in order to be considered for a reward."* Compound: *"Proof of concept is always required for all severities."*

Stage 6 MUST extract these clauses verbatim from the bounty page and inject as `target_program_poc_clause` into Stage 3. When a program-specific clause is stricter than Immunefi's default, the program clause wins.

Findings below 80 get DOWNGRADE(refine) at Stage 3. The defaults invert: assume every finding can reach Tier-1 with enough RPC-config work; the orchestrator's job is to actually do the config work, not to bail to a lower tier.

## Per-tier verdict.md evidence checklist (NEW v0.2.4 — MANDATORY)

Stage 3 verdict.md MUST tick each box for the claimed tier. Missing any item caps certainty at the next-lower-tier ceiling. Driven by Output 7 of the empirical research.

### Tier 0 — Mainnet-Fork / Live-State

- [ ] Clone command verbatim (e.g. `solana-test-validator --clone <ID> --url mainnet-beta --slot <N>`)
- [ ] Captured stdout from harness boot showing program loaded
- [ ] Target program ID (Solana) / contract address (CosmWasm/Substrate) explicit
- [ ] Fork block / slot / RPC URI pinned (so reviewer can reproduce)
- [ ] Exploit tx signature (local-validator sig acceptable) included
- [ ] Pre-state diff (account balances, storage values) captured before exploit
- [ ] Post-state diff captured after exploit, with deltas explicit
- [ ] Re-run with fix applied → exploit fails (revert message captured)

### Tier 1 — Validated Integration

- [ ] Test invocation command verbatim (e.g. `anchor test`, `cargo test --package <X> -- --nocapture <test_name>`, `pnpm test:bankrun`, `wasmd start && wasmd tx wasm execute ...`)
- [ ] Captured stdout including:
  - `running N tests` line
  - intermediate balance / state output from PoC code (NOT from program-under-test source)
  - final `PASS` / `test result: ok` line
- [ ] Cargo.toml / package.json deps listed verbatim (so judge can `cargo test` it themselves)
- [ ] Setup procedure (account creation, mints, initial state) shown
- [ ] Attack tx sequence enumerated (each instruction / message / dispatch listed in order)
- [ ] Post-exploit assertion (`assert_eq!` / `expect()` / `assert!`) explicit in PoC body
- [ ] **Program-under-test source UNMODIFIED** — explicit statement + commit hash. Modified source with injected `panic!` / `println!` / `eprintln!` is near-automatic kill (KF-3a from research).
- [ ] Precondition list with realism note (e.g. "any user can call this; no admin required")
- [ ] Fix-applied re-run captured (run the test after applying the recommendation; show the test now reverts / fails the exploit assertion)

### Tier 2 — Unit Test

- [ ] `cargo test` command verbatim with `--package <X> -- --nocapture <test_name>`
- [ ] Captured stdout
- [ ] Explicit assertion (failed assertion or unexpected success path)
- [ ] Bridge narrative: "this unit test demonstrates X; the entrypoint path that exposes X to attackers is Y" with code refs
- [ ] No `#[ignore]` annotation; test runs by default

### Tier 3 — Written Derivation

- [ ] Numbered attack steps
- [ ] Code references with line numbers AND commit hash
- [ ] Worked numeric example with explicit pre/post values
- [ ] Justification for not providing runnable PoC (e.g. "logic-only invariant; no state interaction")

## Source-modification discipline (NEW v0.2.4 — near-automatic kill)

Empirical finding: PoCs that modify the program-under-test by injecting `panic!` / `println!` / `eprintln!` / `dbg!` / `print!` to demonstrate the bug are routinely killed. Cantina blog (Zigtur): *"Rust integers have fixed sizes. […] Rust checks for these issues in debug mode, it does not in release mode, which Solana uses by default."* — a PoC that shows the bug only via debug-mode panic but not under release-mode wrap is downgraded.

**Rule**: every Tier-1 verdict.md MUST contain:

```
program_under_test_unmodified:
  statement: "Source of <crate>::<module>::<function> is unmodified at commit <SHA>"
  evidence: <git log/diff command output showing no changes between audit commit and PoC harness build>
  exception: <if absolutely necessary, document the modification and the equivalent release-mode behavior>
```

Output coming only from the PoC code (the test wrapper), not from injected statements in the program crate, is acceptable.

### Tier 0 — Mainnet-fork / live-state E2E (NEW v0.2.3 — for state-dependent bugs)

The gold-standard tier for bugs that depend on real on-chain state: oracle staleness against actual Pyth/Switchboard/Band feeds, liquidity-dependent attacks against real pool reserves, validator-set behavior against actual stake distributions, bridge / IBC against real packet sequences.

**Tier 0 means**: the test runs against state cloned from or derived from a real mainnet/testnet, not synthetic data.

**Per-ecosystem Tier 0 patterns**:

- **Solana** — `solana-test-validator --clone <PROGRAM_ID> --clone-account <FEED_ACCT> --url mainnet`. The validator boots with mainnet program state and account state; the test exercises the exploit against real conditions. Boot script in verdict.md MUST quote the `--clone` parameters and the cloned-from cluster.
- **CosmWasm / Cosmos** — fork via `wasmd export` from mainnet snapshot, or use `osmosisd` / chain-specific equivalents with state-import. Multi-chain IBC bugs require simultaneously running `wasmd` instances representing both chains.
- **Substrate** — `try-runtime execute-block --execution wasm --runtime <chain>-runtime.wasm --pre-state-uri ws://archive.<chain>.io:443 --block-number <recent>`. The `--pre-state-uri` against a live archive node is what makes this Tier 0.
- **ZK** — replay an actual prover invocation against a deployed verifier; capture the proof + public inputs + verifier accept/reject.

**Certainty rubric**: Tier 0 = **95-100**. The highest possible.

**Required verdict.md fields for Tier 0**:

```markdown
## Tier-0 boot
- cluster: mainnet | mainnet-fork at slot/block <N>
- clone command: <verbatim, e.g. solana-test-validator --clone <ID> --clone-account <ACCT> --url https://api.mainnet-beta.solana.com>
- live state captured: <description: which programs, which accounts, at what slot>
- exploit transaction sequence: <captured tx hashes / sigs from the local fork>
- buggy-build result: <pass/fail + observed values>
- fix-applied result: <pass/fail + observed values>
- mainnet equivalence: <argument that fork behavior matches what would happen on real mainnet — typically guaranteed by --clone preserving program code>
```

**When Tier 0 is mandatory** (per the bug-class × harness matrix above): oracle staleness, liquidity-dependent, validator-set, bridge, runtime-upgrade-with-real-state. **PLUS** any target on Immunefi (per platform-aware escalation rule above).

**When Tier 0 is excessive**: math/state/access-control/Borsh — those are deterministic in synthetic environments. Tier-0 setup time is high (10-30 min boot per run); use only when the bug genuinely depends on real-chain state OR target=Immunefi.

### Ready-to-paste Tier-0 boot scripts (NEW v0.2.4)

Copy and adapt these verbatim. Each is sourced from research-validated patterns used in accepted bounty disclosures.

**Solana — oracle / liquidity-dependent (full validator clone)**:

```bash
solana-test-validator \
  --reset \
  --url mainnet-beta \
  --clone <PYTH_ORACLE_ACCOUNT> \
  --clone <SWITCHBOARD_AGGREGATOR> \
  --clone <PROGRAM_TO_AUDIT> \
  --clone <PDA_OF_INTEREST> \
  --slot <REPRODUCTION_SLOT>
# In another terminal:
anchor test --skip-local-validator --provider.cluster localhost
```

**Solana — Bankrun fork-lite (lighter-weight; for state-shape bugs)**:

```typescript
const realMint = await connection.getAccountInfo(
  new PublicKey("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v") // USDC mainnet
);
context = await startAnchor("",
  [{ name: "program_under_audit", programId: PROGRAM_ID }],
  [
    { address: USDC_MINT, info: realMint },
    { address: USER_ATA, info: realAta }
  ]
);
```

**CosmWasm — wasmd-localnet with mainnet state import**:

```bash
# 1. Snapshot mainnet contract state
wasmd query wasm contract-state all <CONTRACT_ADDR> \
  --node https://rpc.osmosis.zone:443 \
  -o json > state.json

# 2. Init local audit chain
wasmd init audit --chain-id audit
# (import state.json into genesis manually)

# 3. Boot
wasmd start
```

**Substrate — try-runtime against live state (Acala canonical)**:

```bash
# Create snapshot from live RPC
cargo run --features with-acala-runtime --features try-runtime -- \
  try-runtime --runtime existing create-snapshot \
  --uri wss://acala.api.onfinality.io:443/public-ws acala-latest.snap

# Replay against the snapshot with new runtime wasm
./target/release/acala try-runtime \
  --runtime ./target/release/wbuild/karura-runtime/karura_runtime.compact.compressed.wasm \
  --chain=karura-dev on-runtime-upgrade snap -s karura-latest.snap
```

**Substrate — chopsticks alternative (faster setup)**:

```bash
npx @acala-network/chopsticks try-runtime \
  --endpoint <wss://remote.endpoint> \
  --runtime <wasm_runtime_path> \
  --checks PreAndPost
```

**Solana — block-replay (post-incident reconstruction)**:

```bash
solana-test-validator --reset \
  --url mainnet-beta \
  --slot <BLOCK_BEFORE_ATTACK> \
  --clone <ATTACKER_PUBKEY> \
  --clone <VICTIM_PUBKEY> \
  --clone <PROGRAM_ID>
# Then replay the attacker's transaction sequence locally
```

### Tier 1 — End-to-end test against the real harness (PRIMARY TARGET)

The project's own test infrastructure is the ground truth. Tier 1 means: a runnable test that exercises the actual instruction / message / extrinsic against a real (mocked or local) chain runtime, observes the unsafe state on real accounts, and verifies the fix patches the behavior.

- **Anchor**: `anchor test` against `solana-test-validator` (localnet) OR a `solana-program-test` BanksClient test in `tests/<feature>.rs`. Argus picks based on the project's existing test pattern — if the repo has `tests/*.ts` Anchor tests, mirror that style; if it uses `solana-program-test` directly, mirror that.
- **CosmWasm**: `cw-multi-test` test that instantiates the contract and the cosmos modules it depends on; calls real `execute` / `query` / `reply` paths.
- **Substrate pallet**: `mock.rs` runtime + `tests.rs` test exercising the real extrinsic via `Pallet::<T>::call`.
- **Solana native**: `solana-program-test` `BanksClient` invocation.
- **Generic Rust service**: integration test under `tests/` with the real binary started or the public API surface called.

The test must:
1. Compile against the project's real `Cargo.toml`.
2. Fail (or emit the unsafe state) when run against the buggy code.
3. Pass when the suggested fix is applied (verification step — actually patch the code locally and re-run).
4. **Actually run** — `cargo test --package <project> --test <name>` produces output. "Test was written but not run" → certainty caps at 60, equivalent to Tier 3.

If Tier 1 succeeds AND the test was run AND output observed, certainty is 90+. The verdict is `ADVANCE` at the claimed severity (subject to the impact-match rule below).

#### RPC discovery (MANDATORY for Tier 1 when the bug requires real chain state)

Some bugs require actual RPC calls to fire — oracle-staleness checks, account-state from a deployed program, fork-of-mainnet for liquidity-dependent bugs, on-chain randomness, IBC packet behavior. For these, do NOT bail to Tier 2 — find the correct RPC path:

**Discovery order**:

1. **Project config first**: read `Anchor.toml [provider]` for `cluster` (`Localnet` / `Devnet` / `Mainnet`), `wallet` for the keypair path. Read `solana config get` if installed for the user's current default cluster. Read `Cargo.toml` `[package.metadata]` or any custom test-config for RPC URLs.
2. **Localnet for state-controllable bugs**: if the bug fires from controllable on-chain state (account balances, PDAs, mints), spin up `solana-test-validator` locally:
   ```bash
   solana-test-validator --reset --quiet &
   solana config set --url localhost
   anchor deploy
   anchor test --skip-local-validator
   ```
   Argus runs these commands. If `solana-test-validator` isn't installed, refer to `install-deps.sh`.
3. **Devnet for shared-state bugs**: if the bug requires a real deployed program (someone else's), use Devnet:
   ```bash
   solana config set --url devnet
   solana airdrop 2  # if test wallet is empty
   anchor test --provider.cluster devnet
   ```
4. **Mainnet fork for liquidity / oracle bugs**: use `solana-test-validator --clone <PROGRAM_ID>` to clone real mainnet program state into local validator. For Pyth / Switchboard / Chainlink oracles, clone the feed account and replay against it.
5. **CosmWasm**: `wasmd` localnet for full integration; `cw-multi-test` for unit-test-style integration without RPC.
6. **Substrate**: `try-runtime --runtime <chain>-runtime --execution wasm <op>` for fork-of-live testing.

**The RPC-discovery checklist** (mandatory for Tier-1 verdict.md when the bug requires chain state):

- [ ] Cluster identified: localnet | devnet | testnet | mainnet | mainnet-fork
- [ ] Cluster source: `Anchor.toml` / `solana config` / inferred from finding
- [ ] Validator started: yes (command: `<X>`) | no (using existing)
- [ ] Test keypair funded: yes (airdrop 2) | n/a (localnet preset)
- [ ] Test command run: `<full command>`
- [ ] Output captured: yes — see `repro.md` | partial | failed
- [ ] If failed: failure mode (compile error / runtime error / RPC unreachable)

If Tier-1 RPC discovery genuinely fails (e.g., the bug needs a closed-source mainnet contract not clonable to local), document the specific failure and fall to Tier 2 — but `tier-1-attempted` field in the verdict.md must enumerate the discovery steps tried.

#### What "actually run" means

A Tier-1 PoC that compiles but is never executed is a Tier-2 PoC at best. The verdict.md MUST include:

- The exact `cargo test` / `anchor test` invocation with `--package` / `--test` flags.
- The captured stdout/stderr showing the test running.
- The pass/fail status against buggy code.
- The pass/fail status against the suggested fix applied (rebuild + rerun).

Without these four artifacts, the certainty score caps at 60 and the verdict is `DOWNGRADE(refine)`.

### Tier 2 — Custom integration-test PoC

When the project's harness exists but doesn't cover the path you need, write a new integration test module in the same style as the project's existing tests. Same harness, just a new test file.

This is still Tier 2 — not Tier 1 — because the test was written by Argus, not by the project. The integration is real; the test is bespoke. Certainty caps at 89.

**Tier-2 vs Tier-1 distinction**: if the test runs against `solana-program-test` / `cw-multi-test` / `pallet-mock-runtime` (NOT a real validator / wasmd / live chain), it's Tier 2. If the test runs against `solana-test-validator` / `wasmd` / `try-runtime` against real-chain state, it's Tier 1.

**Tier-2 is a fallback, not a default.** Use it ONLY if Tier-1 RPC discovery genuinely failed (documented in verdict.md). The orchestrator's first attempt is always Tier 1.

### Tier 3 — Minimal reproducer (THE FLOOR)

A `#[test]` or `main.rs` harness that exercises the affected function or struct in isolation. **This is the default for every finding that doesn't reach Tier 1-2.**

Tier 3 PoCs isolate the bug from its surrounding protections. The verdict.md must explicitly enumerate which surrounding protections were *not* exercised, and Stage 4 will challenge whether one of those protections actually blocks the attack.

#### The Tier-3-buildable test (MANDATORY before falling to Tier 4)

Before writing a Tier-4 derivation, run this self-audit. **If you answer "yes" to ANY question, Tier-3 is buildable and Tier-4 is not permitted.**

1. **Math reduction**: does the bug reduce to deterministic arithmetic on `u64` / `u128` / `i64` / `i128` values? (overflow, wrong rounding direction, precision loss, off-by-one)
2. **Single-function logic**: is the bug fully contained in one `pub fn` whose inputs you can construct in pure Rust? (signature is `(args) -> Result<T>` with no on-chain side effects required to fire the bug)
3. **Two-function sequencing**: is the bug a sequencing issue across two functions whose state can be modeled with a plain Rust struct? (e.g., "function A writes X then function B reads X stale" — buildable as `let mut state = ...; fn_a(&mut state, args); fn_b(&mut state, other_args); assert!(...)`)
4. **Struct-level invariant**: is the bug a property of a struct (`#[account]`, `#[derive(BorshDeserialize)]`, plain `struct`) whose values you can construct directly?
5. **Pure helper or library function**: is the bug in a `pub fn` in a library / helper module, callable from a unit test?
6. **State machine**: can the bug be triggered by constructing a sequence of struct mutations that violate the claimed invariant?
7. **Borsh / serde / scale-codec round-trip**: does the bug fire on `T::try_from_slice(bytes)` or `T::serialize` of constructible bytes?
8. **Cryptographic primitive**: does the bug fire from calling the verify / hash / signature function directly?

**If any of these is yes**, write the Tier-3 reproducer. Do not write a Tier-4 derivation. The model's job is to *try* the reproducer, not to argue why one wasn't tried.

#### What Tier-3 is NOT permitted to skip

These are common-but-wrong reasons to skip Tier-3 — they are explicitly REJECTED:

- "The bug spans two files." → Two functions in two files are still Tier-3-buildable. Build a test crate that imports both.
- "I can't run `anchor test` without a validator." → Tier-3 doesn't need a validator. Build a `#[test]` in a separate Cargo crate that imports the program crate as a library and calls the handler logic on hand-constructed `Account` structs.
- "The instruction handler depends on `Sysvar<'info, Clock>`." → Construct a `Clock` value directly: `Clock { slot: 100, .. }`.
- "I'd need to mock SPL Token CPI calls." → If the bug is in the math/state *before* the CPI, the CPI is irrelevant — assert on the pre-CPI state. If the bug *is* the CPI, mock it (and document the mock — Stage 4 will challenge whether the mock is realistic).
- "The bug requires a real `Pubkey`." → `Pubkey::new_unique()` is fine for unit tests. PDA-derivation tests can use `Pubkey::find_program_address` directly.
- "The reward subsystem isn't deployed." → Build the reward-pool struct in memory and test the math. The dependency on F-18 (or equivalent scope-meta) is recorded separately in Stage 6, not used to skip Tier-3.

#### Shared reproducer pattern (when multiple findings share a class)

When 2+ findings reduce to math/state on the same struct family (e.g., reward-subsystem accounting, share-price arithmetic, fee calculation), put their tests in a single shared reproducer crate at `$RUN_DIR/3-poc/_<class>-reproducer/`:

- One `Cargo.toml` declaring the affected program crate as a path dependency.
- One `src/lib.rs` per bug-class with `#[test]` functions named `f01_<short_description>`, `f06_<short_description>`, `f11_<short_description>`, etc.
- Each test asserts on the bug — passes when the bug fires (proving it), fails when the suggested fix is applied (verifying the fix).
- One `repro.md` listing the run command per F-NN.

This avoids per-finding boilerplate and makes the reproducer auditable in one place.

#### Anchor-specific Tier-3 patterns

Most Anchor instruction handlers are testable without `solana-program-test` / `litesvm` / `BanksClient` if the bug is math or state-mutation. Use one of these patterns:

**Pattern A — Pure logic extraction**: if the handler's bug-relevant math lives in a separate `fn` (or can be refactored into one), call it directly in a `#[test]` with hand-built inputs.

**Pattern B — Account-struct simulation**: construct the `#[account]` structs directly and pass them to the handler logic. The handler signature `pub fn handler(ctx: Context<X>, ...)` doesn't need a real `Context` — for math-bug tests, build a wrapper that exercises only the state-mutation lines:

```rust
#[test]
fn f01_reward_overemission() {
    use crate::state::{RewardPool, UserPosition};
    use crate::instructions::claim_rewards::accrue_rewards;

    let mut pool = RewardPool {
        rate_per_second: 1000,
        last_update_slot: 0,
        reward_per_share_acc: 0,
        // ... rest
    };
    accrue_rewards(&mut pool, /* current_slot */ 100).unwrap();
    let acc_delta = pool.reward_per_share_acc;

    let user_shares: u128 = 100;
    let total_shares: u128 = 1000;
    let pending = acc_delta * user_shares / RewardPool::PRECISION;

    // The bug: pending should equal `total_rewards * user_shares / total_shares`
    // = R * elapsed * 100 / 1000 = small. Buggy code gives R * elapsed * 100 (huge).
    let true_emission = pool.rate_per_second as u128 * 40; // elapsed_seconds = 40
    assert!(
        pending > true_emission * 10,
        "expected at least 10× over-emission; got pending={} true_emission={}",
        pending, true_emission
    );
}
```

**Pattern C — `solana-program-test` only when CPI matters**: if the bug requires a real SPL Token CPI to fire (e.g., re-entry through a Token-2022 transfer hook), then `BanksClient` is justified. For math/state bugs, Pattern A or B is faster and equally proving.

**Anti-pattern**: skipping Tier-3 because "it would require setting up `BanksClient`." That's only true if the bug genuinely requires runtime CPI behavior. For 80% of Anchor bugs (math, state, sequencing, account validation), Pattern A or B works.

### Tier 4 — Property / symbolic / written derivation (RESTRICTED)

Tier-4 is permitted ONLY when the Tier-3-buildable test above answers "no" to all 8 questions. Acceptable Tier-4 forms:

- A `proptest` or `kani` harness that explores the state space and finds the violation. (This is technically still a runnable test — preferred over written derivation.)
- A written derivation grounded in code line citations, ONLY when no Tier-3 path exists.

#### Tier-4 justification (MANDATORY)

Every Tier-4 verdict.md must include a `tier-3-attempted` section that enumerates:

- **Each of the 8 self-audit questions**, with a yes/no answer.
- **For every "yes" answer**: an explicit explanation of why the Tier-3 reproducer was still infeasible. Acceptable reasons are narrow: external-protocol behavior the auditor can't reproduce, runtime-determined values that no in-memory simulation can produce, on-chain randomness the test can't mock without changing the bug.
- **For every "no" answer**: brief evidence (1-2 sentences) of why the question doesn't apply.

If every self-audit answer is "no" with evidence, Tier-4 is justified. If any answer is "yes" without an acceptable infeasibility explanation, the Tier-4 verdict is invalid — return to Tier-3.

#### Tier-4 still requires every assumption listed

A Tier-4 written derivation must list every assumption made and every code path not exercised. Stage 4 will challenge it harder than runnable tiers — assumptions in Tier-4 are challenge surface, not invisible glue.

## When PoC cannot be built

If no tier succeeds, the finding is `KILL(no-poc)` UNLESS it falls into the **poc-exempt allowlist** below. The allowlist is short and not extensible inside this pipeline — if you find a case that should be exempt and is not in the list, do not exempt it; downgrade or kill the finding.

### PoC-exempt allowlist (kept short on purpose)

1. **Direct denial-of-service via a public panic that ANY caller can trigger** — e.g., `unwrap()` on a `BorshDeserialize` of caller-controlled bytes in a public entry point with no auth gate. The PoC requirement is satisfied by *citing the unwrap line and the entry point* — the panic is mechanically obvious. The verdict.md must include both citations.
2. **Missing `signer` check on a privileged Anchor account** — the absence of the constraint is the bug; the PoC requirement is satisfied by quoting the `#[derive(Accounts)]` struct showing no `Signer` constraint and pointing at the privileged operation it gates. Severity must reflect what the privileged op does (e.g., transferring funds → High; pause/unpause only → Medium).
3. **Missing `ensure_signed` / `ensure_root` on a Substrate dispatchable** — same logic as #2.
4. **Hard-coded constant violating the program's claimed invariant** — e.g., README says fee is capped at 10%, code stores `pub const FEE: u16 = 1500;` (15%). Citation of doc + citation of constant is sufficient.
5. **Cryptographic primitive used incorrectly in a documented dangerous way** — e.g., ECDSA without low-S normalization where signature malleability matters for replay, with citation of the verify call and absence of normalization.

Anything not on this list goes through Tier 1-4 or it is killed.

## Impact-match rule

A PoC must prove the *exact* claimed impact. If it only proves a weaker version, the finding is `DOWNGRADE` to the proven impact's severity, and the F-NN file's severity field is rewritten in place.

Examples:
- Claimed: "attacker drains all funds." PoC proves: "attacker steals 1 token at a time, costs more gas than the token is worth." → DOWNGRADE to Low/Informational.
- Claimed: "Liquidity pool can be permanently bricked." PoC proves: "Pool is bricked for 24 hours then self-recovers." → DOWNGRADE to Medium / temporary DoS.
- Claimed: "Any user can mint unlimited tokens." PoC proves: "Only the protocol fee recipient (privileged role) can mint extra tokens during the fee-claim path." → DOWNGRADE to Informational (TRUSTED-role-required) or KILL if Stage 1 trust model has the role as fully trusted.

## verdict.md schema (per finding)

Every `$RUN_DIR/3-poc/F-NN/verdict.md` MUST have these fields:

```markdown
# F-NN Stage 3 verdict

- **finding**: <title>
- **PoC tier**: 1 | 2 | 3 | 4 | exempt-{N}
- **certainty**: <0-100 score per the rubric>
- **status**: ADVANCE | DOWNGRADE(<new severity>) | KILL(<reason>)
  - certainty < 80 → status MUST be DOWNGRADE(refine) regardless of tier
- **proven impact**: <one paragraph, concrete, what the PoC actually demonstrated>
- **claimed impact (Stage 2)**: <quoted from F-NN.md>
- **gap (if any)**: <if proven < claimed, what's missing>
- **assumptions made**: <enumerate every assumption in the PoC harness>
- **untouched protections**: <surrounding protections not exercised by the PoC>
- **reproduction**: see `repro.md`

## Tier-1 RPC-discovery checklist (MANDATORY for Tier-1 verdicts)

- [ ] Cluster identified: localnet | devnet | testnet | mainnet-fork
- [ ] Cluster source: `Anchor.toml` / `solana config` / inferred from finding
- [ ] Validator started: yes (command: `<X>`) | no (using existing)
- [ ] Test keypair funded: yes | n/a
- [ ] Test command run: `<full command>`
- [ ] Output captured: yes (in repro.md) | partial | failed
- [ ] Buggy-code result: <pass/fail + brief>
- [ ] Fix-applied result: <pass/fail + brief>

If any box is unchecked, the verdict is NOT Tier 1 — drop to Tier 2 and re-grade certainty.

## Tier-1 attempted (MANDATORY for Tier 2/3/4 verdicts)

If the verdict is below Tier 1, the verdict.md MUST list:

- **What Tier-1 RPC discovery was attempted**: <enumeration of steps from the discovery order>
- **What failed and why**: <specific error / blocker>
- **Why the failure justifies skipping Tier 1**: <1-2 sentences; "I didn't try" is not acceptable>

If the orchestrator skipped Tier-1 RPC discovery entirely (e.g., went straight to a Tier-3 minimal reproducer), this section is a procedural failure — Stage 3 must re-attempt Tier 1 before accepting the verdict.

## Tier-3-attempted self-audit (MANDATORY for tier 4)

| # | Question | Answer | Evidence |
|---|----------|--------|----------|
| 1 | Math reduction to u64/u128/i64/i128? | yes/no | <if yes: why infeasible / if no: 1 sentence why not> |
| 2 | Single-function logic? | yes/no | ... |
| 3 | Two-function sequencing? | yes/no | ... |
| 4 | Struct-level invariant? | yes/no | ... |
| 5 | Pure helper / library fn? | yes/no | ... |
| 6 | State machine? | yes/no | ... |
| 7 | Borsh / serde / scale round-trip? | yes/no | ... |
| 8 | Cryptographic primitive direct call? | yes/no | ... |

If any answer is "yes" without an explicit infeasibility justification, this verdict is invalid — return to Tier 3 and write the reproducer.

For tier 1-3 verdicts, omit this section.

## Verdict

<single paragraph rationale>
```

If `status` is `KILL(no-poc)`, the verdict.md must also explain why no tier succeeded — what was tried, why each tier failed (the same self-audit table above, with no "yes" answers permitted).

## repro.md schema

```markdown
# F-NN reproduction

## Setup
<commands to install toolchain, deps>

## Steps
1. <command>
2. <command>
3. observe <expected output>

## Expected output (buggy code)
<exact stderr / stdout snippet showing the bug fires>

## Expected output (with suggested fix applied)
<exact stderr / stdout snippet showing the bug is gone>
```

The repro must be runnable by a different engineer with no Argus context.

## Anti-patterns

These produce verdict files that look like PoCs but aren't:

- "The PoC would work like this: ..." (English description only — KILL)
- A PoC that requires the suggested fix to be applied to compile (the PoC must demonstrate the bug, not the fix)
- A PoC that mocks away the protection it claims is missing
- A PoC that uses a non-standard test harness the project doesn't have, citing reasons like "the project's harness is too complex"
- A PoC that proves a strictly different bug than the one in F-NN.md

When you spot any of these, KILL the finding (or DOWNGRADE if a weaker PoC tier still works).

### Tier-4 specific anti-patterns

These tier-4-flavored verdicts are explicitly REJECTED — return to Tier-3 if you see yourself writing one:

- "The math derivation shows the bug is real" — without first running the 8-question self-audit. If any question is "yes", a Tier-3 test is required.
- "Setting up `solana-program-test` would be too complex" — this is not a Tier-4 justification. Anchor patterns A and B above bypass `solana-program-test` for math/state bugs.
- "The bug depends on F-X being deployed" — F-X dependency is a Stage 6 scope concern, not a Stage 3 PoC blocker. Tier-3 tests the math/state assuming F-X holds; Stage 6 separately handles the scope question.
- "Requires real chain state" — only valid for runtime-randomness, on-chain liquidity, oracle-feed values, or external-program behavior. State-mutation, math, sequencing, and account-validation bugs do not require real chain state.
- "Two functions in two files" — Tier-3 reproducers can import as many modules as needed.
- "The instruction handler takes `Context<'info, T>`" — handler logic can be extracted to a pure fn (Pattern A) or wrapper-tested (Pattern B). Tier-4 is not the answer.

If any of these reasoning patterns appears in a verdict.md's `tier-3-attempted` section as an "infeasibility justification", reject the Tier-4 classification and require a Tier-3 reproducer.

## Stage 3 quality bar

Argus's value at Stage 3 is *building reproducers, not writing arguments about why reproducers weren't built*. The default response to any non-allowlist finding is "write the test." The default response to "I'm about to write a Tier-4 derivation" is "run the 8-question self-audit first, and write the test if any answer is yes."

Findings whose reproducers cannot be built are rare. When you see Tier-4 in a run, treat it as a signal to question whether the orchestrator skipped buildable work — not as evidence that the bug is hard to prove.
