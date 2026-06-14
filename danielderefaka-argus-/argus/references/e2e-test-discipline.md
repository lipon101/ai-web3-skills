# E2E Test Discipline (`infra` mode, NEW v0.3.3)

> Defines what "live E2E" means per DLT-infra component type. Every Stage 3 CONFIRMED finding in `infra` mode MUST produce a Tier-1-live-e2e artifact per this discipline.
>
> **Motivating failure**: F-07 in the 2026-05-12 monero-oxide run was declared CONFIRMED by cargo-audit + dep-graph match, then refuted by Codex's live TLS-handshake test (the codebase never configures CRLs, so the cited bug is unreachable through the wallet path). cargo-audit verdict ≠ exploit reachability. This file closes that gap by requiring every CONFIRMED to ship with a live reproducer.

## What "live E2E" means

**Tier-1-live-e2e** is a runnable test that:

1. **Imports the actual in-scope crate** as a dependency (not just the cited vulnerable crate in isolation).
2. **Invokes the actual code path** the in-scope code uses — same API, same configuration, same dispatch.
3. **Reproduces the bug's observable effect** against that code path: panic / crash / state corruption / DoS / leak / unauthorized state change.
4. **Saves a captured artifact** under `$RUN_DIR/3-verification/F-NN/e2e/` containing: the test source, the build command, the run command, the captured stdout/stderr, and a verdict (REPRODUCED / UNREACHABLE / INCONCLUSIVE).

What it is NOT:

- ❌ A standalone test against the underlying buggy library in isolation, divorced from how the codebase uses it. (F-07's mistake: the rustls-webpki panic reproduced standalone but was unreachable through `simple-request → hyper-rustls → rustls` because no CRL is configured.)
- ❌ A cargo-audit JSON match. (That's step 1 of Group H, not the verdict.)
- ❌ A Kani proof that the property holds in isolation, without checking the in-scope code reaches the proven-buggy state.
- ❌ A Miri trace from a hand-constructed harness that doesn't exercise the in-scope entry-point chain.
- ❌ An English derivation. ("In theory the wallet calls `with_crls()`" — show it.)

## Per-component-type E2E patterns

### Validator client / node

Stage 1 component-type: `validator-client`. Examples: `solana-validator`, `polkadot-sdk-node`, `cometbft-rs`, `lighthouse`.

**E2E discipline**: spawn the actual validator binary (or a stripped-down test harness importing the validator crate). Feed crafted input via the real entry-point (p2p message, RPC call, mempool tx, block import). Observe the bug's effect on the running process.

**Minimum harness**:

```rust
// $RUN_DIR/3-verification/F-NN/e2e/src/main.rs
use validator_crate::Node;

fn main() {
    let node = Node::new(test_config());
    node.start();
    let crafted_msg = build_attack_message();  // exercise the cited vector
    node.handle_p2p_message(crafted_msg);
    // Observe: panic, crash, state corruption, etc.
}
```

Run with `cargo run --bin e2e 2>&1 | tee e2e-output.txt`. Verdict from output.

### Consensus engine

Stage 1 component-type: `consensus-engine`. Examples: `sp-consensus-grandpa`, BFT round logic.

**E2E discipline**: use `stateright` or a hand-rolled model that exercises the consensus state machine with a crafted message sequence. The model imports the in-scope consensus crate; it does NOT re-implement the protocol.

```rust
use stateright::*;
use consensus_crate::{State, Action, transition};

struct ConsensusModel;
impl Model for ConsensusModel {
    type State = State;  // imported from in-scope crate
    type Action = Action;
    fn next_state(&self, s: &Self::State, a: Self::Action) -> Option<Self::State> {
        transition(s, a)  // imported from in-scope crate
    }
    fn properties(&self) -> Vec<Property<Self>> {
        vec![Property::always("no_conflicting_finalize", |_, s| !s.has_conflicting_finalized_blocks())]
    }
}
```

stateright finds the counterexample trace → Tier-1-live-e2e CONFIRMED.

### P2P networking

Stage 1 component-type: `p2p-networking`. Examples: `libp2p` consumers, custom gossip layers.

**E2E discipline**: spawn two peer instances (`libp2p::Swarm` or equivalent), connect them, send the crafted message from peer-A, observe peer-B's panic / OOM / state corruption.

```rust
let mut swarm_a = build_swarm_with_in_scope_behavior();
let mut swarm_b = build_swarm_with_in_scope_behavior();
swarm_a.dial(swarm_b.local_peer_id())?;
swarm_a.behaviour_mut().send_message(crafted_attack_payload);
// Drive swarm_b until panic / OOM observed
```

### Cryptographic library

Stage 1 component-type: `crypto-library`. Examples: `curve25519-dalek`, custom signature schemes.

**E2E discipline**: call the actual public API (signing fn, verification fn, key derivation fn) with crafted inputs. Observe nonce reuse / signature malleability / key leak.

```rust
use crypto_crate::{sign, verify, KeyPair};

let kp = KeyPair::generate(&mut SeededRng::from_seed([0u8; 32]));
let sig1 = sign(&kp, b"msg1");
let sig2 = sign(&kp, b"msg2");
// If nonce reuse: extract private key from (sig1, sig2)
let leaked_key = recover_key_from_nonce_reuse(sig1, sig2, b"msg1", b"msg2");
assert_eq!(leaked_key, kp.private_key);  // CONFIRMED
```

### Storage engine

Stage 1 component-type: `storage-engine`. Examples: custom RocksDB wrappers, Merkle tree storage.

**E2E discipline**: instantiate the in-scope storage layer with a temp directory. Write crafted state, simulate crash (kill mid-write or use a panic injector), restart, observe corruption.

```rust
let temp_dir = tempfile::tempdir()?;
let storage = StorageEngine::open(temp_dir.path())?;
storage.begin_tx();
storage.write(crafted_corrupting_input);
std::panic::set_hook(...);  // simulate crash mid-WAL
drop(storage);

let storage2 = StorageEngine::open(temp_dir.path())?;  // recovery path
let observed = storage2.read(key);
// CONFIRMED if observed reveals corruption
```

### RPC / API node

Stage 1 component-type: `rpc-api-node`. Examples: `jsonrpsee` / `tonic` / `axum` handlers.

**E2E discipline**: spawn the RPC server, send the crafted request via real HTTP client, observe response / crash / leak.

```rust
let server = RpcServer::start("127.0.0.1:0", in_scope_handler).await?;
let port = server.local_addr().port();

let client = reqwest::Client::new();
let crafted_payload = build_payload_with_attack_vector();
let response = client.post(format!("http://127.0.0.1:{}/rpc", port))
    .body(crafted_payload)
    .send().await;

// CONFIRMED if response is panic / crash / leak / unauthorized data
```

### Bridge / cross-chain relayer

Stage 1 component-type: `bridge-relayer`. Examples: IBC relayers, Wormhole guardians, custom bridge logic.

**E2E discipline**: simulate the source-chain event (crafted block / finality proof / validator set) using mock chain state. Feed to the relayer's in-scope verification function. Observe forge-acceptance / replay / supply-invariant violation.

```rust
let source_chain_mock = MockChain::new();
source_chain_mock.append_crafted_block(forged_validator_signatures);
let proof = source_chain_mock.get_finality_proof(block_height);

let relayer = BridgeRelayer::new(known_validator_set);
let result = relayer.verify_and_process(proof);

// CONFIRMED if result = Ok(processed) for a forged proof
```

### Wallet / signing library

Stage 1 component-type: `wallet-library`. Examples: monero-oxide wallet, hardware wallet drivers.

**E2E discipline**: instantiate the wallet, perform the actual signing / key-derivation / address operation. For side-channel claims, run under `dudect-bencher` or `criterion` with two input classes.

```rust
let wallet = Wallet::from_seed(test_seed);
let (key, addr) = wallet.derive_account(0);

// For nonce-reuse / signature-malleability:
let sig1 = wallet.sign(&key, b"tx1");
let sig2 = wallet.sign(&key, b"tx1");  // same message
// CONFIRMED if extractable: signatures should differ; if r==r, k was reused
assert_ne!(sig1.r, sig2.r);  // fails → CONFIRMED nonce-reuse bug
```

### Smart-contract execution VM

Stage 1 component-type: `smart-contract-vm`. Examples: `solana_rbpf`, custom Wasm execution.

**E2E discipline**: spawn the VM, load a crafted contract bytecode that exercises the cited vector, observe sandbox escape / metering bypass / nondeterminism.

```rust
let vm = SmartContractVM::new();
let crafted_bytecode = build_bytecode_with_attack_vector();
let result = vm.execute(crafted_bytecode, host_state);

// CONFIRMED if vm leaks host state / bypasses metering / executes forbidden syscall
```

### Generic Rust DLT crate / supply-chain (Group H)

When the finding is a Group H supply-chain advisory (e.g., RUSTSEC), the E2E test MUST:

1. Build a project that **depends on the in-scope crate** (not just the underlying buggy library).
2. Invoke the actual code path the in-scope crate uses (same API, same config — read from the in-scope crate's source).
3. Construct attacker-controlled input that would trigger the cited advisory IF reachable.
4. Run; observe whether the bug fires.

**Reference case — F-07**: 
- `repro-0104/` proves the rustls-webpki panic is real in isolation (build with `rustls-webpki = "=0.103.10"`, feed crafted CRL DER, observe panic).
- `reach-0104/live-client-test/` proves the panic is UNREACHABLE through `simple-request` (build with the actual `simple-request` dep, make HTTPS request to local server serving the crafted cert, observe NO panic — client returns normal cert-validation error).

Both artifacts are required for Group H CONFIRMED. The first proves the bug exists; the second proves it's reachable through the in-scope code.

## E2E artifact schema

Every Stage 3 CONFIRMED finding writes `$RUN_DIR/3-verification/F-NN/e2e/`:

```
e2e/
├── Cargo.toml          # depends on the in-scope crate at the audit-pinned commit
├── src/                # harness source code
│   └── main.rs OR tests/F-NN.rs
├── run.sh              # exact build + run commands (re-runnable)
├── output.txt          # captured stdout/stderr from the run
├── verdict.md          # REPRODUCED | UNREACHABLE | INCONCLUSIVE + rationale
└── timing.txt          # wall-clock + cost of the run
```

`verdict.md` schema:

```markdown
# F-NN E2E verdict

- **vector_id**: <e.g. H01, A01, D01>
- **component_type**: <validator-client | consensus-engine | ...>
- **e2e_verdict**: REPRODUCED | UNREACHABLE | INCONCLUSIVE
- **harness_path**: src/main.rs OR tests/F-NN.rs
- **build_command**: cargo build --release ...
- **run_command**: ./target/release/e2e-F-NN OR cargo test --test F-NN
- **observed_output**: <verbatim snippet showing the bug firing OR not firing>
- **expected_for_REPRODUCED**: <what output proves the bug>
- **expected_for_UNREACHABLE**: <what output proves the bug can't fire here>
- **rationale**: <2-4 sentences>
```

REPRODUCED → Stage 3 CONFIRMED, advance to Stage 4.
UNREACHABLE → Stage 3 INCONCLUSIVE with reason `e2e_proved_unreachable`. Routes to `manual-queue.md` for human override OR DISCARD.
INCONCLUSIVE → Stage 3 INCONCLUSIVE with reason `e2e_did_not_terminate` / `harness_build_failed` / `output_ambiguous`. Manual review.

## When E2E is genuinely infeasible

The pipeline acknowledges three classes where Tier-1-live-e2e is not achievable in pure CI:

1. **Requires mainnet state** the audit lab can't reproduce (e.g., a bug that only fires when total network stake exceeds X). Fall back to **Tier-1-prop** (proptest / property-based) with the assumption explicitly stated. Note in verdict: `e2e_infeasible_reason: requires-mainnet-state`.

2. **Requires real hardware** (HSM, secure enclave, FPGA accelerator). Fall back to **Tier-1-formal** (Kani proof) or **Tier-2-prop**. Note: `e2e_infeasible_reason: requires-hardware`.

3. **Multi-node distributed scenarios** that need >2 nodes (e.g., consensus liveness violations requiring 4+ validators). Fall back to **stateright model** (counts as Tier-1-live-e2e per consensus-engine E2E pattern above). Note: `e2e_modeled_via: stateright`.

**These are the ONLY acceptable fallbacks.** Every other class — Group H supply-chain, panic / crash, integer-overflow exploit, TLS-handshake bug, RPC injection, key-derivation flaw — MUST have a live runnable E2E. No more cargo-audit-only verdicts.

## Coordination with other references

- **`infra-verification-stage.md`** Stage 3 spec now references this file for the E2E artifact requirement. Tool-only verdicts (cargo-audit, Miri-standalone, Kani-isolated) are INCONCLUSIVE pending E2E, not CONFIRMED.
- **`refine-loop.md`** consumes the verdict.md output: REPRODUCED → SUBMIT, UNREACHABLE → DISCARD, INCONCLUSIVE → manual queue.
- **`dlt-infra-types.md`** component-type profiles inform which E2E pattern from this file to use.
- **`scripts/install-infra-deps.sh`** already installs the test harnesses each pattern needs (cargo, cargo-fuzz, stateright via Cargo.toml dep).

## Cost budget per finding

Tier-1-live-e2e adds ~5-15 min wall-clock per finding for harness build + run. For a 10-finding run, that's ~50-150 min added to Stage 3. This is the cost of correctness vs the cost of shipping false positives like F-07.

Findings whose E2E genuinely can't run in CI (the 3 fallback classes above) skip the cost. Most can.
