# Infra Depth-Agent Methodology (NEW v0.4.0)

All 8 infra-mode angles (`memory-safety`, `unsafe-trait`, `concurrency`, `crypto-misuse`, `arithmetic`, `logic-state-machine`, `resource-exhaustion`, `supply-chain-ffi`) load this file alongside `../shared-rules.md` and their angle-specific definition. Codifies the depth-pass disciplines (attack-surface enumeration, devil's-advocate sweep, pre-auth panic check, asymmetric-cost quantification, bounded-resource walk) at the Rust + Anchor/Solana scope.

## The 8 disciplines (apply in order)

### 1. Attack-surface enumeration

Before any per-finding analysis, enumerate the surface this angle owns. Write the enumeration to `$RUN_DIR/2-candidate-findings/_surface_<angle>.md`. Each surface entry has:

```yaml
entry: <file:line> | <function signature>
trust_level_at_entry: <pre-auth | post-auth | role-gated | privileged>
data_source: <Borsh instruction | account data | sysvar | CPI return | RPC param | env | ...>
upstream_callers: [<file:line>, ...]
```

Cite at minimum from Stage 1's `attack-surface.md` § 10-point walk. Add anything the 10-point walk missed.

### 2. Devil's-Advocate sweep

For every candidate FINDING, write the strongest one-paragraph rebuttal AGAINST the finding. Rule: never write "nothing" — if you cannot rebut, you have not understood the bug. Specifically test:

- Oversized input (>MAX_LEN)
- Undersized input (<MIN_LEN, empty)
- Malformed encoding (truncated Borsh, missing discriminant)
- Boundary values (0, 1, MAX-1, MAX)
- Timing (duplicate, stale, future, same-slot replay)

If the rebuttal survives a single round of self-rebuttal, mark `verdict_state: CONTESTED` (per shared-rules.md § Verdict states).

### 3. Pre-auth panic sweep

For every handler reachable BEFORE the authentication ceremony completes (signer check, PDA verification, JWT validation, handshake completion):

- `ast-grep` (or `grep`) for `.unwrap()`, `.expect(`, `panic!(`, `unreachable!()`, slice-index `[`, `try_into().unwrap()`, `assert!`.
- Each hit is a potential single-packet node-kill primitive.
- Trace back: is there a bounds / type / nonce check earlier in the call chain?
- Pre-auth panics get `PRE-AUTH-PANIC` modifier (floor HIGH).

For Anchor: pre-auth = before the `#[derive(Accounts)]` block deserialises. Anchor reports most pre-auth panics as `ProgramError::AccountDidNotDeserialize`, but custom decoders inside `instruction_data` parsing can panic earlier.

For RPC / network services: pre-auth = before the JWT / TLS handshake completes.

### 4. Asymmetric-cost quantification

For every admission check, message handler, or insertion path:

```
ratio = (attacker_state_or_work) / (defender_state_or_work)
```

Examples:
- Mempool insertion: bytes attacker pays vs bytes mempool stores
- Connection accept: bytes attacker sends vs sockets defender consumes
- Cache write: queries attacker issues vs entries cache stores
- CPI gas: CU attacker pays vs CU callee burns

`ratio < 1.0` = symmetric (not interesting). `ratio ≥ 100` and permissionless = DETER-class HIGH. Record `mandatory_checks.asymmetric_cost.ratio` per finding (shared-rules.md schema).

### 5. Resource-bounds check

For every handler / decoder / loop / allocation site:

| Bound type | Required? | If missing → |
|------------|-----------|---------------|
| Size bound (input length) | yes | unbounded-input DoS candidate |
| Element-count bound (vec/array max items) | yes | memory-exhaustion candidate |
| Recursion-depth bound (recursive decoders) | yes | stack-overflow candidate |
| Allocation bound (per-handler memory cap) | yes | OOM candidate |
| CPU bound (loop iteration cap, CU budget) | yes | CPU-exhaustion candidate |
| Time bound (timeout / deadline) | for network handlers | slowloris candidate |

Each missing bound is a candidate FINDING.

### 6. Eclipse / peer-table analysis (if applicable)

Applies only to angles touching P2P / discovery / gossip code. If your angle does not touch network code, skip with `n/a — not a network-layer angle` and proceed.

Peer-table / eclipse audit checklist:
- Peer-table data structure + eviction policy (LRU? Random? FIFO?)
- Bucket IP/ASN diversity enforcement
- Bootstrap-list integrity
- Discovery-record signature verification

### 7. Cross-domain-dependency tag

Identify 2-3 assumptions OUTSIDE the angle's own domain that the bug relies on. Tag in the finding as `[CROSS-DOMAIN-DEP: <domain>]`. Examples:

- A memory-safety bug that requires the user to be a validator (`[CROSS-DOMAIN-DEP: economic / role gating]`)
- A panic bug that requires a specific consensus-state precondition (`[CROSS-DOMAIN-DEP: consensus]`)
- A resource exhaustion bug that requires a specific fee-market state (`[CROSS-DOMAIN-DEP: economic]`)

Record in `mandatory_checks.cross_domain_deps` (shared-rules.md schema). If any dep cannot be verified in production, trigger downgrade via `BOUNDED-IMPACT` or `PRACTICAL-DIFFICULTY` modifier.

### 8. Always-on boundary checklist

For every numeric limit, cache size, queue depth, or array length touched by your target:

| Probe | Expected behavior | Bug if not |
|-------|-------------------|------------|
| `value = 0` | safe-reject or no-op | underflow / div-by-zero |
| `value = 1` | normal | edge case |
| `value = boundary - 1` | normal | off-by-one |
| `value = boundary` | reject or saturate | over-by-one |
| `value = boundary + 1` | hard-reject | overflow / panic |
| `value = MAX` | hard-reject | overflow |
| `container empty` | safe-no-op | crash |

State for each whether the result is `drop | panic | unbounded-work | safe-reject | undefined`.

## §WRITE-THEN-VERIFY (file-output discipline)

For long outputs (>~500 tokens), write the full FINDING content to `$RUN_DIR/2-candidate-findings/F-<NN>.md` using the Write tool and return ONLY a one-line summary to the orchestrator. Returning the full finding inline burns orchestrator context budget.

Return-line format:
```
DONE: <N> findings for <angle> ({X confirmed, Y refined, Z refuted, W contested})
```

The orchestrator verifies each `F-NN.md` exists after every angle returns. Missing file → re-dispatch.

## Evidence-tag floor (per shared-rules.md)

Reminder: `[CODE-TRACE]`-only on a HIGH/CRITICAL claim is REJECTED at Stage 4 Pass D. The angle must produce at least one of `[FUZZ-PASS]`, `[LSP-TRACE]`, `[NON-DET-PASS]`, `[CONFORMANCE-PASS]`, `[DIFF-PASS]`. Plan for the verification artifact at finding-emit time, not later.

## Coordination with `references/infra-verification-stage.md`

Stage 3 PoC generation in infra mode uses the deterministic backends (Miri / Kani / Loom / cargo-fuzz / cargo-audit). Your FINDING's `evidence_tags` should name which backend Stage 3 should run; for example, a memory-safety FINDING names `[FUZZ-PASS]` if cargo-fuzz can reach the panic, or `[MIRI-PASS]` (a sub-class of `[NON-DET-PASS]`) if the bug is a UB-class issue Miri detects.

## Tier × angle gating

Per cost-estimation.md § Named depth tiers:

- **Light tier**: only 4 angles run (`memory-safety`, `arithmetic`, `logic-state-machine`, `resource-exhaustion`). Other 4 angles skipped.
- **Core tier**: all 8 angles. This methodology runs.
- **Thorough tier**: all 8 + Devil's-Advocate runs TWICE per finding (second pass attempts to rebut the first rebuttal).

## Telemetry header (mandatory in Thorough tier)

When running under Thorough tier, each angle's output file MUST begin with a YAML header for orchestrator telemetry:

```yaml
---
agent: <angle-name>
mode: infra
tier: thorough
iteration: 1
started: <ISO-8601>
ended: <ISO-8601>
primitive_calls:
  grep: <count of grep invocations>
  ast_grep: <count, 0 if not used>
  rust_analyzer: <count, 0 if LSP not used>
fallback_to_grep: <true | false — true if LSP/SCIP unavailable>
---
```

Light + Core tiers may omit this header. Stage 4 Pre-Pass parses it when present.
