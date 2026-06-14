# Deployed-Code Verification — Stage 1 supplement

> **Introduced in**: v0.6.0. Runs during Stage 1 (protocol mapping), after attack surface enumeration.
> **Purpose**: Verify that the repository source code matches what is actually deployed on-chain. Catch dead-code audits (auditing repo code that doesn't match deployed bytecode) and proxy-behind-implementation divergence.
> **When to skip**: Never. Verification is cheap (build + hash comparison). A mismatch is a critical pre-condition failure for the entire audit.

## Why this exists

The WhiteHatMage guide explicitly warns against two related failure modes:

1. **"Auditing repository code that doesn't match deployed code"** — the repo has been updated post-deployment but the on-chain program hasn't been re-deployed. You're auditing code nobody is running.
2. **"Old contract implementations sitting behind proxies"** — the proxy points at an old implementation, but the repo has the new implementation. You're auditing the upgrade but the live system runs the old code.

Both result in wasted pipeline budget on dead code, and worse — false confidence that a bug was found (or not found) in code that isn't deployed.

Argus has no check for this. Stage 7 (duplication triage) checks GitHub issues/PRs for known bugs but never verifies that the code being audited is the code that's running.

## Stage contract

```
DEPLOYED-CODE VERIFICATION — Stage 1 supplement
INPUT:    Stage 1 attack surface (entry points, program IDs, contract addresses),
          build artifacts (from enumerate.sh or manual build)
OPERATIONS:
  1. Extract on-chain identifiers from Stage 1: program IDs, contract addresses, code IDs
  2. For each identifier, attempt to fetch on-chain bytecode/metadata
  3. Compute hash of local build artifact
  4. Compare against on-chain hash
  5. If mismatch: classify as STALE_REPO, PROXY_DIVERGENCE, or UNVERIFIED
  6. For mismatches: attempt to locate the deployed source (git tag, release artifact, upgrade authority)
OUTPUT:   $RUN_DIR/1-protocol-map/deployed-code-report.md
VERDICT:  VERIFIED (repo matches deployed) / MISMATCH (divergence detected) / UNVERIFIABLE (no on-chain reference)
EXIT CONDITION: report written with per-identifier verification status.
```

## Per-chain verification procedures

### Solana (Anchor / native programs)

```
INPUT: program ID (base58 string, e.g., "GovER5Lthms3bLBqWub97yVrMmEogzX7xNjdXpPPCVF")
STEPS:
  1. Attempt: solana program dump <PROGRAM_ID> /tmp/argus-verify-<id>.so
     - If "AccountNotFound": program not deployed on selected cluster → UNVERIFIABLE
     - If success: dumped to temp file
  2. Build the program locally: anchor build (or cargo build-sbf for native)
  3. Compute SHA256 of both:
     - sha256sum target/deploy/<program>.so
     - sha256sum /tmp/argus-verify-<id>.so
  4. Compare hashes:
     - Match → VERIFIED
     - Mismatch → MISMATCH (STALE_REPO: deployed is older; or PROXY_DIVERGENCE: deployed is different)
  5. Cleanup: rm /tmp/argus-verify-<id>.so
NOTES:
  - Solana program IDs may be on mainnet, devnet, or testnet. The cluster is determined
    from Anchor.toml [provider] cluster field or solana config get.
  - Upgradeable programs (BPFLoaderUpgradeable) may have a different deployed version
    than the repo. Check the upgrade authority to determine if the repo controls the deployment.
  - If the program is closed (solana program show <ID> returns "Closed"), the repo code
    is dead — flag as STALE_REPO with HIGH severity (entire audit scope is invalid).
```

### CosmWasm

```
INPUT: contract address (cosmos1... or code ID)
STEPS:
  1. Query on-chain code: wasmd query wasm code <CODE_ID> code.wasm
     - If "code not found": UNVERIFIABLE
     - If success: downloaded to temp file
  2. Build locally: cargo wasm (or workspace optimizer)
  3. Compute SHA256 of both .wasm files
  4. Compare:
     - Match → VERIFIED
     - Mismatch → MISMATCH (see classification below)
  5. Cleanup
NOTES:
  - CosmWasm uses code IDs, not addresses. Extract code ID from the contract's
    instantiate message or from the repo's documented deployment.
  - The optimizer (rust-optimizer) produces deterministic builds only when using
    the same Docker image version. A hash mismatch may be an optimizer version
    mismatch rather than a genuine code divergence. Flag as UNVERIFIED, not MISMATCH,
    if the optimizer version is unknown.
```

### Substrate pallets

```
INPUT: runtime WASM hash (from chain state)
STEPS:
  1. Query on-chain runtime: chain_getBlockHash → state_getMetadata → extract runtime hash
     Or: state_getStorage("0x3a636f6465") (":code" key)
  2. Build locally: cargo build --release -p <runtime>
  3. Extract WASM blob from build: target/release/wbuild/<runtime>/<runtime>.compact.wasm
  4. Compute Blake2-256 of local WASM (Substrate runtime uses Blake2, not SHA256)
  5. Compare against on-chain runtime hash:
     - Match → VERIFIED
     - Mismatch → MISMATCH (runtime upgrade since repo commit)
NOTES:
  - Substrate runtimes are upgraded via governance. The on-chain runtime may be
    newer or older than the repo. Identify the on-chain spec_version and compare
    against the repo's runtime/src/lib.rs spec_version.
  - For pallets (not full runtimes): the runtime WASM embeds all pallets. If the
    runtime hash matches, all pallets match. Individual pallet verification is
    not possible from on-chain data alone.
```

### Generic Rust services (non-blockchain)

```
INPUT: git tag / release version from repo
STEPS:
  1. Check if the repo has a deployed version indicator: git tags, Cargo.toml version,
     release artifacts, Docker image tags, CI deploy logs
  2. If a deployed version is identifiable:
     - git tag → compare HEAD against tag. If HEAD == tag → VERIFIED.
       If HEAD > tag → STALE_REPO (repo ahead of deployed).
       If HEAD < tag → PROXY_DIVERGENCE (deployed ahead of repo — less common).
  3. If no deployed version indicator: UNVERIFIABLE
NOTES:
  - Generic Rust services have no on-chain source of truth. The best we can do
    is git-tag-to-HEAD comparison. Flag as UNVERIFIABLE if the repo has no tags.
  - Docker images are a stronger signal than git tags. If CI builds and pushes
    images, check if the image tag matches a git tag.
```

## Mismatch classification

| Classification | Meaning | Audit impact |
|----------------|---------|-------------|
| **STALE_REPO** | Repo code is newer than deployed code. The on-chain program is behind. | Audit the deployed version, not the repo. The repo's new code is not live. Flag Stage 2 scope to exclude post-deployment changes. |
| **PROXY_DIVERGENCE** | Proxy points at an old implementation; repo has the new one. Or the repo has diverged from the deployed bytecode for an unknown reason. | Audit BOTH if possible. The deployed version is live; the repo version is intended. Bugs in either matter. |
| **PROGRAM_CLOSED** | Solana program is closed (no executable data). | CRITICAL — the entire audit scope is dead. Halt the pipeline and inform the user. |
| **UNVERIFIED** | Could not determine deployed version (no RPC access, no on-chain data, no tags). | Continue audit but flag every finding with `deployed-code: UNVERIFIED`. Stage 8 surfaces this as a confidence reduction. |
| **BUILD_NON_DETERMINISTIC** | Build produces different bytecode on different machines (common with non-optimizer CosmWasm builds). | Flag as UNVERIFIED. The hash mismatch may be a build artifact, not a code divergence. |

## Output format

`$RUN_DIR/1-protocol-map/deployed-code-report.md`:

```markdown
# Deployed-Code Verification — <project>

**Date**: <date>
**Cluster/Network**: <mainnet / devnet / testnet / N/A>

## Verification results

| Identifier | Type | On-Chain Hash | Local Hash | Status | Classification |
|------------|------|--------------|------------|--------|---------------|
| GovER5Lt... | Solana program | a1b2c3... | d4e5f6... | MISMATCH | STALE_REPO |
| cosmos1abc... | CosmWasm contract | — | — | UNVERIFIED | No RPC endpoint configured |

## Mismatch details

### GovER5Lt... — STALE_REPO
- **On-chain**: Deployed at slot 312,000,000, last upgraded slot 290,000,000
- **Repo**: HEAD is 45 commits ahead of the deployed version's tag (v1.2.0 vs v1.5.0)
- **Impact**: 3 new instruction handlers in repo are NOT deployed. Stage 2 scope excludes:
  - `instructions/v2/advanced_swap.rs`
  - `instructions/v2/flash_loan.rs`
  - `state/v2_orderbook.rs`
- **Action**: Audit scope reduced to v1.2.0 API surface. User should re-deploy before auditing v1.5.0.

## Pipeline impact

- **Scope adjustment**: {list of files/modules excluded from Stage 2 if STALE_REPO}
- **Confidence flag**: {UNVERIFIED for all findings if any identifier is UNVERIFIED}
- **Halt condition**: {if PROGRAM_CLOSED — halt and inform user}
```

## Halt conditions

If **any** in-scope program/contract is PROGRAM_CLOSED or fully unverified (no on-chain data AND no git tags AND no build artifacts), Stage 1 halts and surfaces a `deployed-code-failure` error:

> **DEPLOYED-CODE VERIFICATION FAILED**: {N} in-scope programs could not be verified against deployed bytecode. The audit cannot proceed without a verified source of truth. Options:
> 1. Provide an RPC endpoint for on-chain verification
> 2. Provide a deployment transaction/address to verify against
> 3. Proceed with UNVERIFIED confidence (all findings will carry a deployed-code uncertainty flag)

## What this stage must NOT do

- Do not audit code that is confirmed STALE_REPO without explicitly scoping it out of Stage 2
- Do not treat hash mismatches as automatic KILL conditions for findings — a mismatch means "verify scope," not "abort."
- Do not fabricate on-chain data. If RPC is unavailable, mark UNVERIFIED — do not guess.
- Do not spend more than 5 minutes on verification. This is a quick check, not a deep investigation.
