# Phase 6: FUZZ — Invariant Fuzz Generator *(UPGRADED — from Plamen's LLM-driven invariant test architecture)*

**MANDATORY for deep/beast modes. Skip for quick/standard.**

## 6.0 Invariant Derivation *(NEW — from Plamen)*

**Do NOT use generic test templates.** Derive invariants from the actual audit artifacts:

| Source | Category | What to Derive |
|--------|----------|---------------|
| Phase 1.5 (Business Context) | Protocol-specific economic | Core protocol guarantees (e.g., `totalBorrows <= totalDeposits`, `sharePrice monotonically increasing`) |
| Phase 3.5 (Findings Inventory) | Finding-derived | For each Medium+ finding: "What invariant would CATCH this bug mechanically?" |
| Phase 2 (Function Map) | Lifecycle invariants | For each lifecycle (deposit→withdraw, borrow→repay): verify net token deltas are zero minus fees |
| Phase 3.H (Data Flow) | Structural invariants | Mirror variables synchronized, accumulators bounded, conditional writes not stale |
| Phase 4.3 (FP Gate) | Boundary invariants | Constraint variables stay within documented bounds after any operation sequence |

**No cap on invariant count** — Forge execution is zero token cost regardless of count. Write as many `invariant_` functions as the protocol has meaningful properties.

## 6.1 Generate Handler Contract *(UPGRADED — from Plamen)*

Write a Foundry test file to `test/invariant/InvariantFuzz.t.sol`:

**Handler Rules** *(from Plamen)*:
- Include ALL public/external state-mutating functions — no cap on handler count
- Use `try/catch` for external calls — handlers must not revert (reverts hide bugs)
- Include `vm.warp(bound(dt, 1, 365 days))` handlers for time-dependent protocols
- Include `vm.prank(user)` for multi-actor scenarios — at least 2 distinct users
- **Lifecycle sequence handlers** (MANDATORY): Execute full create→use→close flows atomically
- **Partial lifecycle handlers**: Enter position but don't exit — tests abandoned positions

**Value bounds** — use protocol-realistic ranges:
- Token amounts: `bound(amount, 1, 1_000_000 * 10**decimals)`
- Fees/rates: `bound(fee, 0, 10_000)` for BPS, `bound(rate, 0, 1e18)` for WAD
- Time deltas: `bound(dt, 1, 365 days)` for interest, `bound(dt, 0, 7 days)` for operational
- Read constraint variables from Phase 2 for protocol-specific bounds

## 6.2 Compile and Run Campaign

```bash
# Compile (max 5 retry attempts on failure)
forge build 2>&1 | tail -30

# Run — 256 runs × depth 25 (3-10 minutes, zero token cost)
timeout 600 forge test --match-contract InvariantFuzz --invariant-runs 256 --invariant-depth 25 --fail-on-revert false -vv 2>&1 | head -300
```

## 6.3 PoC Fuzz Variants *(NEW — from Plamen)*

For every Medium+ confirmed finding from Phase 4, write a SECOND test with key parameters fuzzed:
```bash
forge test --match-test testFuzz_{finding_id} -vvv
```
This explores the neighborhood around each finding mechanically — catching attack variants the agent didn't manually consider. If the specific PoC failed but the fuzz variant finds a violation → report the working variant.

## 6.4 Multi-Chain Fuzz Support *(NEW — from Plamen)*

| Chain | Tool | Command | Notes |
|-------|------|---------|-------|
| **EVM (Foundry)** | Forge invariant | `forge test --match-contract InvariantFuzz --invariant-runs 256 --invariant-depth 25` | Primary |
| **EVM (Echidna)** | Echidna | `echidna-test . --test-limit 100000 --seq-len 100` | beast mode only |
| **EVM (Medusa)** | Medusa stateful | `medusa fuzz --target ./src --seq-len 100 --test-limit 50000 --timeout 900` | beast mode — parallel with Forge |
| **Solana (Anchor)** | Trident (preferred) | `cd trident-tests && trident fuzz run fuzz_0` | v0.11+ uses built-in TridentSVM. Found Critical bugs in Kamino, Marinade, Wormhole |
| **Solana (native)** | proptest (fallback) | `cargo test test_fuzz_* -- --nocapture` | Use `proptest!` macro with bounded inputs |
| **Aptos / Sui** | Parameterized tests | Multiple `#[test]` with boundary values | No fuzzer — test min/mid/max concrete values |

## 6.5 Results Report

Write to output directory:
```markdown
# Invariant Fuzz Results
| # | Invariant | Category | Source | Status | Counterexample | Related Finding |
|---|-----------|----------|--------|--------|---------------|----------------|
```

Violations become depth agent input — they provide concrete counterexamples. Evidence tag: `[POC-PASS]` (mechanical proof).
