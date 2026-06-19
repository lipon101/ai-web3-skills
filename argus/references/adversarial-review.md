# Adversarial Review — Stage 4

This stage is the false-positive killer. By the time a finding reaches Stage 4 it has a runnable PoC; Stage 4 challenges whether the PoC actually proves the claim under realistic conditions, and whether a guard or invariant elsewhere in the codebase blocks the attack the PoC demonstrates in isolation.

Read this file at Stage 4 start.

## ⚠️ Per-finding output is MANDATORY (NEW v0.1.11 — procedural enforcement)

**One file per finding.** Stage 4 produces `$RUN_DIR/4-adversarial/F-NN.md` for EVERY finding entering this stage. A single `_summary.md` covering multiple findings is **INVALID** and rejected at orchestrator validation.

**Why this rule exists**: the v0.1.10 monero-oxide run produced `_summary.md` for Stages 4/5/6/7 instead of per-finding files. As a result:
- Pre-Pass External Research never fired per finding → F-11's "credential leak via digest-auth" claim went unchallenged (it's wrong: digest-auth uses MD5 hashes, plaintext password never on wire).
- 3-judge Pass C panel never ran per finding → F-11's "connection redirection" impact claim went unchallenged (it's wrong: hyper extracts host:port independently of userinfo).
- Per-finding rubric scoring at Stage 5 collapsed to platform-wide commentary.
- Stage 6 in-scope-impact mapping ran as prose summary instead of literal enumerated-list match.

The Judge running standalone caught both findings as INVALID. The Argus pipeline produced them as REFINE-bucket SUBMIT candidates. Single-summary verdicts cause this divergence.

### Compactness anti-pattern (REJECTED)

If you find yourself writing:

```markdown
# Stage 4 summary
## F-06: passes (cryptographic check refutes impact)
## F-11: refines (borderline scope)
## F-04: ...
```

**STOP.** That is not Stage 4. That is a tracking sheet. Produce per-finding files first; then optionally write a `_summary.md` index pointing at them.

### Validator check before advancing to Stage 5

Stage 5 entry requires: `find $RUN_DIR/4-adversarial -name 'F-*.md' | wc -l` ≥ count of findings entering Stage 4. If fewer per-finding files exist than Stage-3-ADVANCE+DOWNGRADE findings, the orchestrator MUST re-run Stage 4 producing the missing files before Stage 5 begins.

The same per-finding-file rule applies to Stages 5, 6, 7 (see their respective reference files).

## Mindset

You are not the auditor. You are the **defending engineer's strongest counterargument**. Your job is to disprove the finding. If you cannot disprove it, the finding survives — and a finding that survives a serious adversarial pass is a strong finding.

Three banned phrases:
- "this looks like" / "this seems like" — give a code citation or stay silent.
- "in theory" / "could in principle" — show the path or drop the challenge.
- "should" — code does what it does; "should" is opinion.

## Pre-Pass — Scope carve-out + code-comment re-check (MANDATORY, runs FIRST)

**NEW in v0.1.9.** Stage 2 angles now run `scope_carveout_check` and `code_comment_scan` on every FINDING (see `references/hacking-agents/shared-rules.md`). Stage 4 re-runs both as the cheapest possible kill — before any other Pre-Pass, before Pass A, before any subagent dispatch. Reasoning: a finding that lands inside a documented scope carve-out OR is documented-as-design by an inline `// NOTE` is invalid regardless of how strong its PoC is. Killing here saves the Wave-2 checker dispatch budget for findings that actually need adversarial review.

### Scope carve-out re-check

Read the FINDING's `scope_carveout_check` field. Independently verify:

1. **Open the project README and any `assets/docs/` files Stage 1 captured.** Re-read the scope-exclusion sections cited in the field (or scan from scratch if the field is empty / `no_scope_sections_in_readme` and you can find sections the angle missed).
2. **Re-quote each carve-out section that touches the bug area.** Compare verbatim text to what's in the FINDING field — angles sometimes paraphrase, which can hide a closer fit.
3. **Independently classify the match**: WITHIN / PARTIAL / OUTSIDE. Trust your own read over the angle's classification.
4. **Evaluate the rebuttal**:
   - Does the writeup quote the carve-out's literal words and show the bug's mechanism falls outside them?
   - "The carve-out is meant for X" without textual support is **interpretive**, not textual — rebuttal_quality = `weak-interpretive`.
   - "The carve-out covers admin actions with malformed args; this finding's args are well-formed" is **textual** if the writeup quotes the literal "malformed" word and shows the args don't fit — rebuttal_quality = `strong-textual`.
5. **Run the carve-out validity check (NEW in v0.1.10)**. Before applying KILL on `WITHIN + weak/absent rebuttal`, decompose the carve-out into actor + mechanism and compare to the finding's actor + mechanism. The KILL only fires if BOTH match.

   For each carve-out that matches WITHIN, identify two axes:

   - **Carve-out actor**: which role does the carve-out's literal text cover? Common values: `admin`, `protocol DAO`, `trusted relayer`, `keeper`, `governance`, `permissionless` (when the carve-out covers behavior accessible to anyone).
   - **Carve-out mechanism**: which specific behavior does the carve-out justify? Common values: `malformed args`, `stale data`, `manual mistake`, `centralization risk`, `MEV`, `dust loss`.

   For the finding, identify two parallel axes:

   - **Finding actor**: which role does the exploit path require? Read the finding's `path:` field and determine who must act.
   - **Finding mechanism**: what is the bug's underlying behavior? Read the finding's `description:` and `proof:` fields.

   Then apply the validity matrix:

| Carve-out actor matches finding actor? | Carve-out mechanism matches finding mechanism? | Action |
|----------------------------------------|------------------------------------------------|--------|
| yes | yes | KILL fires (carve-out fully reaches the bug) |
| yes | no | finding SURVIVES — the carve-out covers this actor but not this mechanism |
| no | yes | finding SURVIVES — the carve-out covers this mechanism but not this actor |
| no | no | finding SURVIVES — the carve-out doesn't reach the bug at all |

   Record in the verdict file:

```
scope_carveout_validity:
  carveout_actor: <quoted role from carve-out>
  finding_actor: <role from finding's path>
  carveout_mechanism: <quoted behavior from carve-out>
  finding_mechanism: <behavior from finding>
  actor_match: yes | no
  mechanism_match: yes | no
  validity_action: KILL_FIRES | SURVIVE_ACTOR_MISMATCH | SURVIVE_MECHANISM_MISMATCH | SURVIVE_BOTH_MISMATCH
```

   The classic case the v0.1.9 rule mishandled (the validity check now catches):

   - README: "Administrator Mistakes — admin can invoke admin-level functions with malformed args."
   - Finding: "Any non-admin caller can trigger the admin path via `init_if_needed` race."
   - v0.1.9: WITHIN (admin function in carve-out) + weak rebuttal → KILL.
   - v0.1.10: actor mismatch (carve-out covers `admin`; finding's actor is `permissionless`) → SURVIVE_ACTOR_MISMATCH.

6. **Apply the verdict matrix**:

| Stage 4 match | Rebuttal-quality | Validity-check result | Action |
|---------------|------------------|------------------------|--------|
| OUTSIDE | n/a | n/a | proceed to External-research Pre-Pass |
| WITHIN | strong-textual | n/a | record; Pass C MUST fire in `CLOSE_CALL_REVIEW (scope-carveout)` mode |
| WITHIN | weak-interpretive OR absent | KILL_FIRES | **KILL** — `STATUS: KILL(scope-carveout-<section>)`. Skip all remaining Pre-Passes and Pass A/B/C/D. |
| WITHIN | weak-interpretive OR absent | SURVIVE_* | record validity reason; proceed to External-research; Pass C MUST fire in `CLOSE_CALL_REVIEW (scope-carveout-validity)` mode |
| PARTIAL | strong-textual | n/a | apply Pass D severity cap = `min(claimed, Low)`; proceed |
| PARTIAL | weak-interpretive OR absent | KILL_FIRES | apply Pass D cap = `min(claimed, Low)` AND Pass C MUST fire |
| PARTIAL | weak-interpretive OR absent | SURVIVE_* | record validity reason; proceed without cap; Pass C MUST fire in `CLOSE_CALL_REVIEW (scope-carveout-validity)` mode |

The KILL action is appropriate ONLY when actor AND mechanism both match — the carve-out is the project's published scope statement *for that actor and that behavior*. When either axis mismatches, the carve-out's authority does not reach the bug and the finding survives to adversarial review.

### Code-comment re-check

Read the FINDING's `code_comment_scan` field. Independently verify:

1. **Re-read the cited file at the bug location ±10 lines.** Quote any inline `//` or `/* */` comments using the marker tokens (`TODO`, `FIXME`, `XXX`, `HACK`, `NOTE`, `SAFETY`, `INVARIANT`) or the prose patterns ("by design", "intentional", "we don't validate", "should be", "may not"). Trust your own read — angles sometimes miss multi-line comments.
2. **Re-classify each comment**: SUPPORTS_FINDING / DOCUMENTS_AS_DESIGN / NEUTRAL.
3. **Apply the verdict matrix**:

| Stage 4 strongest match | Action |
|------------------------|--------|
| `DOCUMENTS_AS_DESIGN` HIGH relevance, citation supports the angle's classification | **KILL** — `STATUS: KILL(code-comment-documents-as-design)`. The dev flagged the gap as intentional — equivalent to a docstring disclaimer; SC-2 applies. |
| `SUPPORTS_FINDING` HIGH relevance | record in verdict file; the comment becomes corroborating evidence quoted in Pass D's attack-path summary. Run an extra dup-check signal at Stage 7 (search the project's GitHub issues / commits for the comment text). |
| Only `NEUTRAL` OR no matches | proceed to External-research Pre-Pass |

### Why this Pre-Pass runs FIRST

The other Pre-Passes (External research wave, Mitigation viability check) and Pass A's Wave-2 checker dispatch each cost agent-minutes of compute. The scope-carveout + code-comment re-check costs one orchestrator file-read. Running it first ensures we don't pay the Wave-2 cost on findings that are already invalid by published-scope rules or by the developer's own self-flagging.

This Pre-Pass produces NO subagent dispatch. It is purely the orchestrator re-reading and re-classifying.

### Output (added to F-NN.md verdict file at Stage 4 — see schema below)

```
## Pre-Pass: Scope carve-out + code-comment re-check (MANDATORY)

### Scope carve-out
| Section | Quoted text | Match | Rebuttal quality |
|---------|-------------|-------|------------------|
| <name> | "..." | WITHIN / PARTIAL / OUTSIDE | strong-textual / weak-interpretive / absent / n/a |
- **action**: KILL(scope-carveout-<section>) | DOWNGRADE_CAP_LOW | PROCEED | PROCEED_PASS_C_FIRES

### Code-comment scan
| File:line | Comment | Classification |
|-----------|---------|----------------|
| <file:L> | "<verbatim>" | SUPPORTS_FINDING / DOCUMENTS_AS_DESIGN / NEUTRAL |
- **action**: KILL(code-comment-documents-as-design) | STRENGTHEN_AND_PROCEED | PROCEED
```

If both sub-checks fire KILL, record both reasons but report the scope-carveout reason as primary (it's the harder-to-rebut platform-rules kill).

## Pre-Pass — Bug-state reachability proof verification (NEW v0.2.5 — MANDATORY, runs SECOND after scope/code-comment Pre-Pass)

**Driving signal**: Argus run on Monero Oxide (2026-05-09) advanced F-15 (`select_n` underflow) to SUBMIT. Pass B-2 had captured the invalidation reasoning verbatim ("the inner while loop spins indefinitely before the outer underflow can fire") but Pass C/D treated it as severity-softening. The Judge skill, run post-pipeline, correctly traced the loop induction and verdicted INVALID. The methodology gap was that Argus had no structural reachability proof for the specific bug state — only function-level (v0.1.8) and branch-level (v0.1.12) checks.

This Pre-Pass closes that gap. It runs BEFORE Pass A's invalidator selector and BEFORE the External Research wave.

### What this Pre-Pass does

For every finding where `bug_reachability_proof` is in the FINDING block (mandatory per `shared-rules.md` § Bug-state reachability proof for any code-location bug claim):

1. **Read the proof's four components** verbatim from the FINDING:
   - `bug_state_predicate`
   - `function_entry_predicate`
   - `loop_progression_model`
   - `reachability_argument`

2. **Independently re-verify the proof** by reading the cited code:
   - Confirm the function-entry predicate against actual function entry (parameter types, parameter validation, caller-supplied bounds).
   - Confirm the loop-progression model against the actual loop structure (loop variable updates, exit conditions, iteration bounds).
   - Trace the reachability argument step-by-step against the actual code.

3. **Apply the same-line protection-check special case** if the cited bug expression is part of a guard expression on the same line. See `shared-rules.md` § Same-line protection-check special case for the recognition patterns.

4. **Independent worst-case trace.** Pick worst-case attacker-controlled inputs for the function and trace the loop / branch / path manually. Identify the iteration / branch where the guard fires.

5. **Verdict**:

| Independent verification result | Action |
|---------------------------------|--------|
| Proof holds — bug genuinely reachable | proceed to External Research Pre-Pass; finding stays |
| Proof fails — bug structurally unreachable | **KILL** — `STATUS: KILL(structurally-unreachable: <which guard fires before bug, with cited line>)`. Pass A/B/C/D skipped. |
| Proof inconclusive on independent re-trace (e.g., orchestrator can't model the loop) | proceed to Pass A/B/C/D; force Pass C in `CLOSE_CALL_REVIEW (reachability-inconclusive)` mode |
| FINDING claims same-line-guard pattern but `proof_outcome: REACHABLE` | demand counter-proof; if counter-proof absent → KILL |

### Output schema in verdict file

```
## Pre-Pass: Bug-state reachability proof verification (MANDATORY for code-location bug claims)

- **finding's claimed bug_state_predicate**: <quoted from FINDING>
- **finding's claimed function_entry_predicate**: <quoted>
- **finding's claimed loop_progression_model**: <quoted, or "n/a — straight-line code">
- **finding's claimed reachability_argument**: <quoted>
- **finding's proof_outcome (per FINDING)**: REACHABLE | UNREACHABLE | INCONCLUSIVE

### Independent re-verification

- **function-entry predicate confirmed?**: yes | no | partial — <evidence>
- **loop-progression model confirmed?**: yes | no | n/a | partial — <evidence>
- **same-line protection-check pattern present?**: yes (pattern: <quoted>) | no
- **independent worst-case trace** (orchestrator-built):
  - input scenario: <attacker-controlled values>
  - iter 0: <state>
  - iter 1: <state>
  - ...
  - iter K: <which guard fires, citing line>
- **conclusion**: bug genuinely reachable | bug structurally unreachable | re-verification inconclusive

- **action**: PROCEED | KILL(structurally-unreachable: <which guard>) | CLOSE_CALL_REVIEW (reachability-inconclusive)
```

If KILL fires here, the verdict file ends after this section. Pass A/B/C/D are skipped. Stage 5/6/7 receive a KILL'd finding which discard.md surfaces.

### Why this is upstream of Pass A

Pass A's catalogue includes EG (existing-guard) which COULD catch same-line protection patterns — but Pass A's selector picks 4 entries from 15 categories, and the orchestrator may not pick EG when the bug claim looks like an arithmetic / logic / panic class that doesn't surface "guard" as a candidate invalidator. The structural reachability proof runs unconditionally, before the selector has the option to overlook EG. It catches the F-15 class of failure regardless of which Pass A invalidators are picked.

### Why this is upstream of External Research

The reachability proof is a function-internal question — it depends on the cited code's loop structure and same-line guards, not on external-protocol behavior. There's no point spending External Research budget on a finding whose bug state is structurally unreachable by induction alone.

### What this Pre-Pass does NOT do

- It does not catch bugs whose unreachability depends on EXTERNAL state (e.g., "the bug only fires if the on-chain oracle returns value V, which Pyth never returns"). Those are caught by External Research.
- It does not catch bugs whose unreachability depends on EARLIER CALLERS' validation (those are caught by `branch_reachability_check` / function-level `reachability_check`).
- It does not catch bugs whose unreachability depends on PROJECT INVARIANTS documented in README/spec. Those are caught by `readme_invariant_check`.

This Pre-Pass owns: structural unreachability internal to the cited function, including loop bounds, same-line guards, inductive invariants on loop variables, and earlier-iteration returns.

### Stage 2 / Stage 4 split

Stage 2 angles produce the proof. Stage 4 Pre-Pass verifies it. This split exists because:

1. Stage 2 angles have the bug-class context (math angle knows what an underflow proof needs; auth angle knows what an access-control proof needs). They produce the proof natively.
2. Stage 4 Pre-Pass operates with adversarial mindset — re-verifies the proof against the actual code, looking for errors the angle might have made under the bias of "I found a bug."
3. The orchestrator running Stage 4 Pre-Pass is NOT the same subagent that produced the FINDING in Stage 2 — independent re-verification, not self-review.

## Pre-Pass — External research wave (MANDATORY when applicable)

**Adapted from The Judge's Step 1.5.** Before Pass A fires, scan the finding for claims about external protocols or libraries (`Anchor`, `OpenZeppelin`, `Pendle`, `Pyth`, `Switchboard`, `wallet2`, `cw20`, `pallet-balances`, `SPL Token`, `SPL Token-2022`, etc.). If found AND the finding's impact case depends on the external system's behavior, run the research wave **before** Pass A.

### Cache-first lookup

The orchestrator maintains `EXTERNAL_RESEARCH_CACHE` keyed by `"{external_system}::{first 80 chars of normalized claim}"`. Before spawning a research agent, check the cache. Cache hits skip the WebSearch.

### Research-agent dispatch

Spawn one general-purpose subagent (Sonnet) with this prompt template:

```
You are an External Protocol Research Agent for Argus Stage 4.

## Your task
Verify the following claim about an external protocol's behavior by searching the web for
authoritative documentation, source code, or on-chain evidence.

## Claim to verify
{EXTERNAL_CLAIM}  -- one sentence extracted from the finding's impact case

## External system
{EXTERNAL_NAME}   -- e.g. "Anchor framework", "OpenZeppelin SafeERC20", "Pyth pull-oracle"

## Instructions
1. Use WebSearch to find the system's official documentation on this behavior.
   Try: "{system} {function} documentation", "{system} {topic} source",
        "site:docs.{system}.* {topic}".
2. If WebSearch fails, use WebFetch on the system's official docs URL if known.
3. If a comparator-source citation is in scope (e.g. wallet2.cpp on disk, OZ contracts in Cargo.toml),
   Read it directly and cite file:line.

## Output
**Claim**: {claim}
**Verified**: TRUE / FALSE / UNVERIFIABLE
**Evidence**: <links, quoted docs, file:line citations>
**Summary**: <2-3 sentences on what the external system actually does>

SCOPE: research only. Return findings and stop.
```

### Result handling

Cache the result. Inject into all Pass A and Pass B checker prompts with the instruction:

> "External Protocol Research has been conducted. Use these VERIFIED facts over your own training-data assumptions. If this research contradicts what you would otherwise assert, trust the research."

**Critical rule**: if the claim is `UNVERIFIABLE`, all subsequent checker verdicts depending on that claim MUST return `UNCERTAIN`, not `HOLDS` or `FAILS`. Forces Pass C judge to fire and weigh the unverifiable claim explicitly.

### Why this matters

Without external research, Pass A/B checkers fall back to training-data assumptions. The swafe v0.1.5 run produced false positives that asserted external system behavior (wallet2, Anchor) without citation; the research wave forces those claims into the open.

## Pre-Pass — Mitigation viability check (background, runs in parallel with Pass A)

**Adapted from The Judge's Step 2.5.** Determines whether the reported issue has a clean fix or represents an inherent design trade-off where any mitigation introduces equivalent downsides. Trade-off issues (cure ≈ disease) are capped at Low at Pass D.

### Mitigation extraction

Scan the finding for a recommended fix. Common markers: "Recommendation", "Mitigation", "Fix", "Remediation". Extract as `MITIGATION_TEXT`. If no mitigation is in the finding, set `MITIGATION_TEXT = "No mitigation was proposed; identify the most natural fix for this vulnerability class."`.

### Spawn agent (background, non-blocking)

Spawn one Sonnet subagent in background with this prompt:

```
You are a Mitigation Viability Checker for Argus Stage 4.

## Your task
Determine whether the security issue below has a clean fix, or whether it represents
an inherent design trade-off where any mitigation introduces equivalent downsides.

## Issue
{F-NN.md content}

## Proposed mitigation
{MITIGATION_TEXT}

## Protocol context
{Stage-1 trust-model.md + invariants.md}

## Instructions
1. Read the source code at the referenced location(s).
2. If a mitigation was proposed, evaluate it. If not, identify the most natural fix.
3. Evaluate:
   - Does the mitigation fully resolve the root cause without introducing new problems
     of comparable magnitude?
   - Or does it create a trade-off of similar severity?
     Examples of TRADE_OFFs:
     * Fixing griefing by adding a whitelist that centralizes control
     * Fixing front-run by adding commit-reveal that adds heavy UX friction
     * Fixing rounding by adding precision that proportionally raises gas/CU
     * Fixing MEV by adding a delay that equally degrades UX
   - These are NOT trade-offs (clean fixes with negligible downside):
     * Standard input validation, access control, re-entry guards
     * Bounds checking, overflow protection
     * Correct ordering / arithmetic fixes
     * Adding a cnt-bump or nonce to a signed message

## Output
**Mitigation**: <1-2 sentence description>
**Verdict**: SOLVABLE / TRADE_OFF / UNCERTAIN
**Confidence**: HIGH / MEDIUM / LOW
**Reasoning**: <3-5 sentences>
**If TRADE_OFF, suggested cap**: Low / Informational
**If TRADE_OFF, downside of fix**: <what the mitigation costs>

SCOPE: evaluate the mitigation only. Return verdict and stop.
```

### Result handling (consumed by Pass D)

Store as `MITIGATION_CHECK`. At Pass D severity calibration:

| Verdict | Confidence | Action |
|---------|------------|--------|
| `TRADE_OFF` | HIGH | apply `MAX_SEVERITY = max(Low, existing MAX_SEVERITY)` cap |
| `TRADE_OFF` | MEDIUM | inject as advisory note in Pass C judge prompt; no auto-cap |
| `SOLVABLE` | any | no severity impact |
| `UNCERTAIN` | any | no severity impact |
| Agent failure / timeout | — | treat as `UNCERTAIN`, no impact |

### Why this matters

The swafe v0.1.5 run promoted M-3 (shared `msk_ss_rik`) as Medium when it's arguably a documented design trade-off (RIK leak is in the threat model; "rotate `msk_ss_rik` per-association" introduces M-of-N reconstruction complexity). Mitigation check would have caught it with `TRADE_OFF` HIGH → cap at Low.

## Four-pass structure

Stage 4 runs four passes per finding. The first three challenge validity. The fourth re-grades severity from the verified attack path (not from the original claim).

### Pass A — Generic invalidator scan

For each finding, walk the catalogue below. For each entry that plausibly applies, look in the code for the specific evidence the catalogue calls for. Record `HOLDS | FAILS | UNCERTAIN` per applicable entry, with `HIGH | MEDIUM | LOW` confidence.

**Selector discipline**: Do not check every entry. Read the finding, pick the 4 most plausibly applicable IDs ranked top-to-bottom (matching the Judge's Selector pattern), check the top 2 with code reads, and pass the bottom 2 to Pass C as "considered alternatives" the judge will weigh without independently verifying.

**The catalogue (Rust-tuned, 15 categories — CR and IL added in v0.1.10; EG expanded with EG-7 / EG-8 in v0.2.5)**:

#### UP — UNREALISTIC_PRECONDITIONS

- **UP-1: Requires extreme token decimals.** Attack only works with tokens that have unusual decimals (>24 or 0). Most tokens use 6 or 18.
- **UP-2: Requires attacker to hold majority of supply.** Acquiring >50% of a token's circulating supply is prohibitively expensive and itself moves price.
- **UP-3: Requires precise block timestamp / slot.** Validators have limited control over timestamps (~400ms drift on Solana, slot-bound on Substrate). Exact targeting is impractical.
- **UP-4: Requires unrealistic initial deposit / position size.** First-depositor-only attack where the attacker would need more capital than exists.
- **UP-5: Requires multiple low-probability events to coincide.** Combined probability makes the attack practically infeasible.
- **UP-6: Requires impossible PDA collision** (Solana). Attack assumes a `find_program_address` collision that is computationally infeasible.

#### CP — COST_EXCEEDS_PROFIT

- **CP-1: CU / gas cost exceeds extracted value.** Solana CU budget × CU price, or Substrate weight × tip rate, vs. profit. If cost ≥ profit at normal market rates, attack is economically irrational.
- **CP-2: Flash-loan / borrow fees make attack unprofitable.** Common in DeFi-on-Rust ecosystems with flash loans (Solend, Mango).
- **CP-3: Slippage on required swaps exceeds profit.** Real DEX liquidity (Orca, Raydium, Osmosis) has finite depth; report ignores it.
- **CP-4: Capital lockup cost exceeds grief value.** Opportunity cost of locked capital (vs. staking, lending) exceeds damage.
- **CP-5: Attack requires sustained spending across multiple slots / blocks.** Cumulative cost grows; extractable value is fixed.
- **CP-6: Actor-in-system zero-cost extraction (NEW v0.1.10).** Standard CP-1..CP-5 assume the attacker is a regular user paying gas / CU / weight. When the attacker IS the cost-bearer (validator including own bundle on Solana via Jito; sequencer reordering on rollups; block-author including own tx on Substrate at zero priority), the ordinary cost-vs-profit calculus does not apply — extraction is free. **HOLDS-CP-6 does NOT downgrade**; instead it escalates the finding to dedicated Economic Security review for game-theoretic analysis. Do not fire CP-1..CP-5 against an attack class that reduces to MEV-extractable-by-validator without first ruling out CP-6.

#### DT — DESIGN_TRADEOFF

- **DT-1: Behavior is intentional CU / gas optimization.** Pattern saves compute; alternative costs significantly more. Practical impact negligible.
- **DT-2: No alternative with better security properties.** Inherent to the model used; every alternative has the same or worse tradeoff.
- **DT-3: Known limitation documented in protocol design.** Doc comments, README, or design docs explicitly acknowledge as known.
- **DT-4: Fixing would break composability or core functionality.** Suggested fix would break protocol's composability with other protocols.

#### EG — EXISTING_GUARD

- **EG-1: Access control prevents unauthorized caller.** Anchor `signer` constraint, `has_one`, `seeds` + `bump`, CosmWasm `OWNER.assert_admin()`, Substrate `ensure_signed_or_root()`, etc., blocks the attacker.
- **EG-2: Reentrancy / re-execution guard blocks the path.** A `nonce`, a one-shot latch, a Substrate transaction-level guard, or a CosmWasm storage-flag prevents the re-entry sequence.
- **EG-3: Minimum amount / threshold check blocks dust.** Function enforces a minimum that prevents the dust manipulation.
- **EG-4: Pause mechanism provides emergency mitigation.** Protocol has a pause/emergency switch that bounds the maximum exploitable window.
- **EG-5: Validation check on input parameters prevents the vector.** `require!`, `ensure!`, `if … return Err`, or pattern-matching exhaustiveness blocks the specific input the attack requires.
- **EG-6: Account-ownership / discriminator check blocks substitution** (Solana). Anchor `#[account]` discriminator, `account.owner == program_id`, or `account.key()` equality check blocks the substitution.
- **EG-7: Same-line / same-statement protection check (NEW v0.2.5).** The cited bug expression is part of a guard expression on the same line or within the same statement. Examples: `if a >= b { a - b }` where bug is "a - b underflows"; `if idx < array.len() { array[idx] }` where bug is "OOB read"; `if iters >= MAX { return }` inside the loop containing the bug; `checked_*` followed by `?` propagating Err. The guard's existence IS the protection. Near-automatic HOLDS at HIGH confidence unless the orchestrator can prove the guard itself fails (e.g., guard-internal overflow, attacker bypass via different path).
- **EG-8: Inductive loop-bound prevents bug state (NEW v0.2.5).** A loop iterating over an attacker-influenced input contains the cited bug, but the loop has either (a) a per-iter check that fires before the bug-state predicate becomes true, (b) a `MAX_ITERS` early-return, or (c) a loop-variable invariant that bounds the bug state. Confirmed via independent worst-case trace. Argus's Stage 4 Pre-Pass bug-state reachability proof verification (NEW v0.2.5) catches this class upstream; EG-8 exists as a backup when the proof was missing or wrong.

#### US — UNREACHABLE_STATE

- **US-1: Required state combination prevented by invariant.** Two state vars must have specific values simultaneously, but a maintained invariant makes the combination impossible.
- **US-2: Previous operation always resets the vulnerable variable.** The "stale state" the attack depends on is never actually stale.
- **US-3: Initialization prevents the zero-state attack.** Constructor / `initialize` / factory always sets the state to a safe non-zero value before any user interaction.
- **US-4: Sequence of operations blocked by intermediate check.** Multi-step sequence has an intermediate check that fails given the state produced by the previous step.

#### SH — SELF_HARM_ONLY

- **SH-1: Attacker can only reduce own balance.** Manipulation only affects the attacker's own position. No third-party loss.
- **SH-2: Grief requires attacker to lock own funds permanently.** Attacker sacrifices funds ≥ damage caused. Economically irrational.
- **SH-3: Attack outcome equivalent to donation.** Net effect is value transferred to other users / protocol without return.

#### Cost-bearer-is-protocol distinguisher (NEW v0.2.1 — MANDATORY before applying ANY SH-*)

**Driving signal**: swafe Code4rena 2025-11 M-05 (unbounded `assoc: Vec<>` → linear-time recovery). Argus v0.2.0 classified this as SH-* "self-harm only" because the writer (account owner) chose to add associations. C4 awarded **Medium** because the linear scan executes inside `verify_update`, paid for by **block authors / the protocol** — not just the writer.

The SH-* catalogue tacitly assumed "the actor who triggers the action is the only one bearing the cost." That's frequently false. A writer can inflate state cheaply once; the linear-scan cost is then paid by every verifier processing that state — block authors, relayers, every read path. The cost-bearer is the **protocol**, not the writer.

**Before applying ANY SH-* HOLDS**, decompose:

```
cost_bearer_check:
  triggering_actor: <who initiates the action>
  resource_consumed: <CU / weight / gas / time / state-storage>
  consumer_path: <function(s) that pay the cost downstream of the trigger>
  consumer_callers: [<who runs each consumer: protocol / block author / relayer / verifier / attacker_themselves>]
  cost_bearer_class: writer-only | protocol-and-writer | protocol-only | market-externality
  verdict:
    cost_bearer_class == "writer-only"  → SH-* HOLDS may apply
    cost_bearer_class != "writer-only"  → SH-* HOLDS DOES NOT apply (bug imposes externality)
```

**Examples**:

| Pattern | Triggering actor | Cost-bearer | SH-* applies? |
|---------|------------------|-------------|----------------|
| Account holder inflates own `assoc: Vec<>` (swafe M-05) | account owner | block author / protocol | **NO — externality** |
| User triggers refund-loop on own escrow paying only own gas | user | user | yes |
| Attacker spams NFT minting; pays own gas; raises others' fees | attacker | attacker + market | **NO — block-space externality** |
| User exhausts own rate-limit quota | user | user | yes |
| Validator inflates own delegation history scanned during slashing | validator | protocol slashing path | **NO — externality** |

**Default**: when in doubt, SH-* HOLDS does NOT apply. Externalized costs are the most-frequently-mis-classified category. The cost-bearer must be provably writer-only for the SH-* kill to fire.

This is a logic correctness fix, not a strictness change. SH-* still kills genuinely self-harm bugs (user reducing only their own balance with no externality). It no longer kills bugs where the externality was missed.

#### DI — DUST_IMPACT

- **DI-1: Rounding bounded to 1 unit per operation.** Maximum discrepancy is 1 lamport / 1 wei / smallest unit per op; doesn't compound.
- **DI-2: Impact does not compound across operations.** Each op independently rounds; subsequent ops absorb or correct the error.
- **DI-3: Loss below minimum transferable amount.** Theoretical loss < protocol's min transfer; user can't even realize the loss.
- **DI-4: Precision loss within domain tolerance.** <0.01% — standard for DeFi.

#### TI — TIMING_IMPOSSIBLE

- **TI-1: Attack requires same-block / same-slot multi-tx ordering control.** Without being block proposer / slot leader or paying extreme MEV bribes, ordering not guaranteed.
- **TI-2: MEV / priority-fee protection makes frontrunning impractical.** Protocol uses Jito bundles / private mempool / commit-reveal that prevents frontrun.
- **TI-3: Timelock / delay exceeds the attack window.** Parameter change takes longer than the attack window allows.
- **TI-4: Oracle update frequency prevents stale-price exploit.** Heartbeat + deviation threshold ensure prices are fresh enough that the manipulation window doesn't exist.

#### SC — SPEC_COMPLIANT

- **SC-1: Behavior matches standard / spec exactly.** SPL Token / CW20 / ERC-20-on-Substrate spec mandates this behavior; changing it breaks compliance.
- **SC-2: Documentation explicitly describes this behavior.** Whitepaper, docs, or `///` doc comments explicitly describe the flagged behavior.
- **SC-3: Behavior standard across major implementations.** Pattern (e.g., share inflation in vault first deposit, rounding direction) is standard across all major Rust DeFi protocols.

#### IM — INCORRECT_MATH

- **IM-1: Profit calculation ignores fees.** Report's claimed profit/loss omits transaction fees, protocol fees, swap fees that significantly reduce or eliminate the impact.
- **IM-2: Linear scaling assumed but function is capped.** Actual function has a cap, ceiling, or diminishing returns that bound the impact below the claimed amount.
- **IM-3: Wrong decimal / precision in calculation.** PoC or impact calc uses incorrect decimals, token precision, or unit conversion.
- **IM-4: Theoretical max conflated with realistic impact.** Report presents absolute worst-case as expected impact. Realistic conditions produce orders of magnitude smaller impact.

#### AM — ALREADY_MITIGATED

- **AM-1: Separate function resets the vulnerable state.** Periodic settlement / sync / rebalance call resets the state. Vulnerable state is transient.
- **AM-2: Timelock / governance delay allows defensive response.** Attack requires governance action; timelock gives monitoring + governance time to counter.
- **AM-3: Circuit breaker / rate limit bounds maximum damage.** Rate limit or per-tx cap bounds extractable value per period.
- **AM-4: Monitoring + emergency pause can halt the attack.** Active monitoring with pause capability significantly reduces practical impact window.

#### OS — OUT_OF_SCOPE

- **OS-1: Affected code only in test / mock / example.** Vulnerable code only in `#[cfg(test)]`, `mocks/`, or example crates. Not deployed.
- **OS-2: Vulnerability in external dependency.** Issue is in a `Cargo.toml` dependency the protocol doesn't control. Protocol uses the dep correctly per its API.
- **OS-3: Code path unreachable from any entry point.** Vulnerable function is internal/private and never reached from any `#[program]` / `#[pallet::call]` / public handler.
- **OS-4: Deprecated or decommissioned component.** Affected module is being phased out; no funds flow through it.

#### TR — TRUSTED_ROLE_REQUIRED

- **TR-1: Attack requires TRUSTED authority to act maliciously.** Per Stage 1 trust model, the only actor that can execute is fully trusted (e.g., the protocol DAO, Stage-1-classified TRUSTED admin). The "they choose to misbehave" reduction without other dimensions = killable. **NOTE (v0.1.10)**: TR-1 now reads `trust_threshold.layers_bypassed_by_finding == trust_threshold.level` (full trust set must act maliciously) instead of the legacy binary TRUSTED. See `shared-rules.md § Numeric trust threshold` for the verdict mapping.
- **TR-2: Attack requires legitimate admin action with unintended code behavior.** Distinct from TR-1. The admin takes a *correct* action; the *code* misbehaves. This is a code bug, NOT a trust issue. Do NOT apply this kill — it is the negation of TR-1, surfaced here so reviewers don't conflate them.

#### CR — CRYPTO_WEAKNESS (NEW in v0.1.10)

Owned by the Crypto Soundness angle (Stage 2 angle 9). Use these invalidators when the finding's claim depends on a cryptographic primitive being weak.

- **CR-1: Cryptographic primitive correctly used.** The finding claims weak crypto (e.g., "ECDSA without low-S"). Verify the implementation: is `s` actually checked? Is the nonce actually deterministic per RFC-6979? Is the verify call actually being made on the cited path?
- **CR-2: Strong randomness source.** The finding claims weak RNG. Verify: is the source actually `getrandom` / `OsRng` / on-chain VRF / verifiable beacon? Block-hash / slot-hash / unix-timestamp would HOLD; secure source FAILS.
- **CR-3: Domain separation present.** The finding claims same key reused across domains. Verify: is the signed payload actually prefixed with a unique domain tag (`b"vote:" | ...` vs `b"bridge:" | ...`)?
- **CR-4: Low-S enforced where it matters.** The finding claims signature malleability replay. Verify: is `s < n/2` checked at verify time?
- **CR-5: Threshold parameters non-degenerate.** The finding claims `t = 0` or `n = 0` produces trivial output. Verify: is the public-API call site actually able to pass `0`? Or does the caller enforce `t >= 1` upstream?

Verdict mapping: CR-1 / CR-3 / CR-4 / CR-5 HIGH HOLDS → KILL (the crypto is correct). CR-2 HIGH HOLDS → DOWNGRADE (the RNG is acceptable for this use case).

#### IL — INFO_LEAK (NEW in v0.1.10)

Use these invalidators when the finding describes information leakage rather than fund / state corruption. Most platforms have explicit thresholds for what counts as material info-leak vs cosmetic.

- **IL-1: Information leaked is already public.** The finding claims a leak; verify that the leaked data is observable on-chain anyway (transaction logs, account state, block-explorer-visible).
- **IL-2: Leak has no downstream economic consequence.** The information leaks but no MEV / front-run / privacy break follows.
- **IL-3: Privacy property never claimed.** The protocol's docs do not claim the property the finding says is broken.

Verdict mapping: IL-1 HIGH HOLDS → DOWNGRADE to Informational. IL-2 HIGH HOLDS → DOWNGRADE one tier. IL-3 HIGH HOLDS → KILL (no claimed property to violate).

When IL-* all FAIL (i.e., the leak IS material AND has consequence AND the protocol DOES claim privacy), the finding's severity is determined by Pass D rubric without IL-cap.

### Pass A verdict mapping

| Catalogue HOLDS | Action |
|-----------------|--------|
| EG-* (any), US-* (any), OS-* (any), AM-1, AM-3, SC-* (any) | KILL — guard / unreachability / out-of-scope is concrete |
| TR-1 | KILL with reason `trusted-role-required` (only when `layers_bypassed == level`) |
| SH-* (any) | KILL — self-harm or donation only |
| UP-* (any), CP-1..CP-5, TI-1, TI-3, TI-4 | DOWNGRADE — bounded conditions reduce severity |
| CP-6 (NEW v0.1.10) | DO NOT DOWNGRADE — escalate to Economic Security review (validator MEV / sequencer-rewrite zero-cost) |
| DI-* (any), IM-2, IM-4, AM-2, AM-4 | DOWNGRADE — impact bounded |
| DT-1, DT-3 | KILL — intentional design |
| DT-2, DT-4 | DOWNGRADE — limited fixability |
| IM-1, IM-3, TI-2 | DOWNGRADE — math or timing reduces impact |
| CR-1, CR-3, CR-4, CR-5 (NEW v0.1.10) | KILL — crypto primitive correctly used |
| CR-2 (NEW v0.1.10) | DOWNGRADE — RNG strong enough for use case |
| IL-1 (NEW v0.1.10) | DOWNGRADE to Informational — leak is already public |
| IL-2 (NEW v0.1.10) | DOWNGRADE one tier — leak has no economic consequence |
| IL-3 (NEW v0.1.10) | KILL — protocol never claimed the privacy property |

A **HIGH-confidence** HOLDS triggers the action immediately. A **MEDIUM-confidence** HOLDS feeds Pass C for the judge to weigh. A **LOW-confidence** HOLDS is treated like UNCERTAIN.

UNCERTAIN never causes KILL or DOWNGRADE on its own — but it does fire the symmetric Pass C judge.

### Partial-coverage rebuttal discipline (NEW v0.2.1 — MANDATORY)

**Driving signal**: swafe Code4rena 2025-11 contest M-03 (`majority_threshold = div_ceil(n, 2)` — 50% threshold for even N). Argus v0.2.0 found the bug correctly (F-10) but Stage 4 Pass A wrongly killed it via a "Pedersen-check covers most cases" rebuttal. The Pedersen check DID cover most threshold-related concerns — but the off-by-one bug exists *in the specific case the Pedersen check doesn't cover* (the even-N edge). C4 awarded it Medium; Argus capped it at QA.

This was not a strictness win — it was a **logic error in rebuttal evaluation**. A guard that "covers most cases" does not invalidate a finding for the case it doesn't cover.

#### The rule

When a Pass A invalidator HOLDS based on the cited guard "covering" the bug, the verdict file MUST decompose the coverage:

```
partial_coverage_check:
  guard_cited: <file:line of the supposed guard>
  guard_mechanism: <what the guard actually checks>
  finding_attack_path: <full sequence of conditions required for the bug>
  cases_covered_by_guard: <enumerated set, e.g., "odd N: ✓ covered">
  cases_NOT_covered_by_guard: <enumerated set, e.g., "even N: ✗ not covered">
  finding_resides_in: covered | uncovered | mixed
  verdict:
    finding_in_covered_case → KILL holds
    finding_in_uncovered_case → KILL DOES NOT hold (rebuttal is partial-coverage; finding survives)
    finding_in_mixed_case → DOWNGRADE one tier (some attack instances killed, others survive)
```

#### When this fires

Apply the partial-coverage check on EVERY Pass A HOLDS in categories EG (existing-guard), US (unreachable-state), and AM (already-mitigated). For SC (spec-compliant) and OS (out-of-scope) HOLDS, the check is N/A — those are full-coverage by definition.

The check is mandatory on HIGH-confidence HOLDS in those categories. On MEDIUM-confidence, the check feeds Pass C judging.

#### Worked example — the swafe M-03 case

```
guard_cited: pedersen_commitment.rs:147 (Pedersen verification on share polynomial)
guard_mechanism: verifies that the Lagrange interpolation reconstructs to the committed secret
finding_attack_path: even N + exactly N/2 collusion + reconstruct via div_ceil(N,2) threshold
cases_covered_by_guard:
  - odd N (any threshold): Pedersen rejects under-threshold reconstruction — covered ✓
  - even N + (N/2 + 1) signers: above threshold, valid reconstruction — covered ✓
cases_NOT_covered_by_guard:
  - even N + exactly N/2 signers: div_ceil rule says "majority", but Pedersen only checks polynomial reconstruction — not the off-by-one in the threshold ✗
finding_resides_in: uncovered
verdict: KILL DOES NOT hold; rebuttal is partial-coverage; M-03 survives Pass A
```

With the partial-coverage check, F-10 would have stayed at Medium through Stage 4 instead of dropping to QA.

#### Why this isn't loosening strictness

The strictness rule is preserved: a HIGH-confidence HOLDS still kills when applicable. The change is only that a HOLDS based on a "guard that covers most cases" is now correctly evaluated against *the specific case the bug occupies*. If the bug is in the covered region, KILL still fires. If the bug is in the uncovered region, the rebuttal was wrong — the finding survives.

This is a logic correctness fix, not a calibration looseness. The pre-v0.2.1 behavior was incorrect: it killed a finding for being weak in cases that aren't the bug.

### Pass A procedural floor (MANDATORY)

The Selector MUST rank exactly **4** invalidators (top-2 checked, advisory 3-4 passed to Pass C). If the Selector returns fewer than 4 ranked entries — even because "only 2 plausibly apply" — that is a procedural-thinness failure: Pass C MUST fire on procedural-thinness grounds (judge mode `CLOSE_CALL_REVIEW (procedural)`) regardless of any other trigger. The Pass A table in the verdict file MUST list 4 rows; if a slot is empty, the verdict file is invalid.

Reasoning: thin Pass A is the failure mode that produced 2/3 false positives in the v0.1.3-era vault-protocol run. Selectors that return only 2 entries are systematically missing alternatives that catch the bug. SC-3 ("standard across major implementations") and SC-2 ("documentation explicitly describes this behavior") are the most-frequently missed invalidators in real runs — when reviewing comparator claims or behaviors-with-docstring-disclaimers, you MUST consider both even if other categories appear more relevant.

### Pass A — Wave 2 dispatch: parallel checker subagents (MANDATORY)

**Adapted from The Judge's Wave 2 (lines 628-845 of judge SKILL.md).** The single-orchestrator-judge approach in v0.1.5 produced confirmation bias on the swafe run (F-03 false positive: orchestrator self-rationalized SC-2 evidence as LOW FAILS). v0.1.6 fixes this by dispatching **independent parallel checker subagents** for the top-2 selected invalidators.

After the Selector returns its 4 ranked invalidators:

1. **Top-2** are dispatched to **3 parallel checker subagents each** (UPDATED in v0.1.10: was 2; now 3 = 6 total). Mix: **2 Sonnet + 1 Opus per invalidator** (cross-model diversity guards against single-model hallucination).
2. **Bottom-2** are passed to Pass C as advisory-only — never independently checked.

Each checker subagent uses this prompt template:

```
You are an Invalidation Checker Agent for Argus Stage 4 Pass A.

## Your task
Determine whether this invalidation reason HOLDS against the actual code, INDEPENDENTLY
of any other agent's reasoning.

## Finding
{F-NN.md content}

## Stage 3 PoC verdict
{3-poc/F-NN/verdict.md content}

## Invalidation reason to check
**{REASON_ID}**: {REASON_TITLE_FROM_CATALOGUE}
{Full text of the catalogue entry}
**Why selector picked this**: {SELECTOR_JUSTIFICATION}

## Stage 1 trust model
{1-protocol-map/trust-model.md content}

## External Protocol Research (if any was conducted)
{EXTERNAL_RESEARCH cache result, or "No external research relevant to this reason."}

## Instructions
1. Read the source code files referenced in the finding's location field.
2. Trace the specific claim made by this invalidation reason against the actual code.
3. Look for concrete evidence: does a guard exist? Is the state reachable? Does the math
   check out? Is there a docstring disclaimer that documents this behavior?
4. Determine your verdict.

## ANTI-HALLUCINATION RULE (CRITICAL)
Numeric / behavioral claims must be grounded in EVIDENCE, not training-data assumptions.
If your verdict depends on any of the following AND you cannot cite a concrete source
for it, your verdict MUST be UNCERTAIN (not HOLDS, not FAILS):

1. External protocol behavior (return values, scaling, exchange rates) — use the External
   Protocol Research above; if unverified, UNCERTAIN.
2. Numeric claims (gas / CU costs, oracle heartbeats, token decimals, fee rates, real
   liquidity) — must reference actual deployed values, not "typically".
3. Market / economic claims ("attacker can move price by X%") — must be supported by
   liquidity data or in-scope code.

"I believe X is Y" or "typically Z" is NOT evidence. On-chain data, official docs, code
citations from in-scope files, or numbers in protocol docs ARE evidence.

When in doubt: UNCERTAIN. UNCERTAIN does not bias the pipeline; it correctly signals
that this checker could not resolve the question.

## Output format
**Reason**: {REASON_ID} — {title}
**Verdict**: HOLDS / FAILS / UNCERTAIN
**Confidence**: HIGH / MEDIUM / LOW
**Evidence**: {file:line citations + quoted code}
**Explanation**: {3-5 sentences on why this verdict, citing the evidence}
**Severity Impact**: INVALIDATE / DOWNGRADE_TO_{severity} / NO_CHANGE

SCOPE: check ONLY this one invalidation reason. Return your verdict and stop.
```

#### Majority rule for early kill (UPDATED in v0.1.10 — was unanimity)

After all 6 checker subagents return (3 per top-2 invalidator):

1. **For each top-2 invalidator**: aggregate the 3 checkers' verdicts.
   - **All 3 HOLDS at HIGH confidence**: this invalidator passes the gate cleanly. Proceed to verdict mapping.
   - **2-of-3 HIGH HOLDS** (with at least one being from a different model than the other): majority gate passes; auto-kill eligible. The orchestrator's independent verification still runs (next step).
   - **1-of-3 HOLDS only**: minority verdict — Pass C MUST fire in `CLOSE_CALL_REVIEW (uncertain)` mode.
   - **All 3 FAILS**: invalidator does NOT hold; advance to next.
   - **Any UNCERTAIN that flips the count below 2-of-3 HIGH HOLDS**: Pass C MUST fire.

2. **Auto-kill requires 2-of-3 HIGH-confidence HOLDS** on the same KILL-class invalidator (EG/US/OS/SC/DT-1/DT-3/SH/TR-1/CR-1/CR-3/CR-4/CR-5/IL-3). The 2-vote majority must include at least one *different model* than the dissenting checker (e.g., 2 Sonnet HOLDS + 1 Opus FAILS is acceptable; 2 Sonnet HOLDS + 1 Sonnet FAILS where all three saw same evidence is suspect — orchestrator independent verification is required either way).

3. **Migration path from v0.1.9**: existing 2-checker output is treated as a 2-of-2 unanimity case (both HOLDS = pass gate). v0.1.10 dispatch uses 3 checkers; v0.1.9 verdict files are still valid but lower-confidence.

3. **Independent verification by orchestrator** is mandatory before accepting any auto-kill. The orchestrator reads the cited file:line itself; if the cited evidence does not support HOLDS, the verdict is downgraded to UNCERTAIN regardless of what the checker subagents said. This is the X-Ray "code reading wins over subagent summaries" principle, applied here.

#### Why parallel checkers matter

The single-orchestrator approach has confirmation bias: once the orchestrator picks 4 invalidators, it rationalizes them in sequence with full memory of prior verdicts. Two parallel checkers each see only their own assigned invalidator + the finding + the code, with no shared reasoning thread. Disagreement between them is signal that the question is ambiguous — exactly the case where Pass C should fire, not where the orchestrator's confidence should grow.

#### Checker model selection

- Sonnet for the 4 Pass A checkers (the work is "read code, verify a specific claim" — sonnet is sufficient and 5x cheaper per token than Opus)
- Pass C judge stays Opus (broader synthesis required); v0.1.10 dispatches 3 Opus subagents with diversified prompts (steel-manning / devil's-advocate / balanced)

### Branch-reachability check (NEW v0.1.12 — MANDATORY when finding cites an if/else branch or match arm)

Distinct from the existing `reachability_check` (which asks "is the cited function reachable from a public entry?"), the **branch-reachability check** asks: "is the cited *branch* (specific arm of an if/else, specific match arm, specific code path inside a function) reachable through the caller chain WITHOUT being blocked by an early-return?"

This is the v0.1.12 addition driven by Argus's F-05 wrong-direction read on the SP1 / Succinct contest. F-05 claimed a Blake3 fallback branch in `verify_public_values` was active and exploitable. The branch existed in source. But the branch is unreachable: every caller (`verify_plonk_bn254`, `verify_groth16_bn254`) early-returns Err on `!vkey.is_plonk()` / `!vkey.is_groth16()` before reaching `verify_public_values`. The Blake3 branch is dead code.

#### How to perform the branch-reachability check

For every finding whose `location:` cites a specific arm of an if/else, a specific match arm, or a specific block inside a larger function:

1. **Identify the activating condition** for the cited branch. Examples:
   - `if vkey.use_blake3 { ... <BUG HERE> ... }` → activating condition: `vkey.use_blake3 == true`
   - `match algo { Blake3 => { <BUG HERE> }, ... }` → activating condition: `algo == Algo::Blake3`
   - `if !condition_a && condition_b { <BUG HERE> }` → activating condition: `condition_a == false && condition_b == true`
2. **Trace the call chain UP** from the cited function to a public entry point. For each caller, identify ALL branches and early-returns.
3. **Determine whether ANY caller's pre-check makes the activating condition unreachable**. Examples of blocking pre-checks:
   - `if !vkey.is_plonk() { return Err(...); }` in a caller would block any branch downstream that requires `vkey.is_plonk() == true` AND `vkey.use_blake3 == true` (since `is_plonk()` and `use_blake3` may be mutually exclusive).
   - A type-state pattern that ensures only Groth16 vkeys reach the function would block Blake3 branches.
   - A factory function that constructs only one variant blocks branches handling the other.
4. **Apply the verdict matrix**:

| Branch reachability through callers | Action |
|--------------------------------------|--------|
| Reachable on at least one path with no blocking pre-check | proceed (finding stands) |
| Blocked on EVERY path by caller early-return | **KILL(branch-unreachable-via-caller-early-return)** |
| Blocked on most paths but reachable on one rare path | DOWNGRADE(refine) — frame the rare path explicitly |
| Cannot determine | UNCERTAIN; Pass C MUST fire on `branch-reachability` |

Record in the verdict file:

```
branch_reachability_check:
  cited_branch: <file:line of the specific arm>
  activating_condition: <pseudocode condition that activates the branch>
  caller_chain:
    - caller: <fn name> (<file:line>)
      pre_checks: [<each pre-check + does it block activating condition?>]
      blocks_branch: yes | no | partial
  blocking_caller (if any): <fn name + cited pre-check>
  verdict: REACHABLE | UNREACHABLE_VIA_CALLER | RARE_PATH_ONLY | UNCERTAIN
```

#### Wrong-direction risk class

If `verdict == UNREACHABLE_VIA_CALLER`, the finding is making the wrong directional claim — it says "this code is active and exploitable" when it's actually dead code. Wrong-direction findings are particularly damaging because:
- They look plausible on isolated code-read.
- They survive Pass A invalidator scan (no EG/US/OS guard catches "branch unreachable from caller chain").
- They submit to platforms as legitimate findings; the platform's judge does the trace and rejects.

The branch-reachability check is the primary defense. When the finding's `location:` cites a specific branch (not the whole function), the check is MANDATORY and KILL fires on UNREACHABLE_VIA_CALLER without going through the standard A/B/C/D rigor.

### Docstring-disclaimer pre-check (MANDATORY before Pass A)

Before running Pass A, for each cited function in the finding's `location`:

1. Read the function's own `///` doc comment.
2. Quote any behavior disclaimer verbatim into the verdict file's new field `docstring_disclaimer`. Disclaimers are statements like:
   - "may error" / "may not enforce" / "may return"
   - "not guaranteed to" / "no guarantees about"
   - "best effort" / "permissive"
   - "the result is not guaranteed to follow X"
3. If a disclaimer is present and the finding's claim is "this function should enforce X", **SC-2 is a top-2 Pass A candidate by default**. Forgetting to select SC-2 in this case is the failure mode that produced the F-03 false positive.

If no disclaimer is present, write `docstring_disclaimer: none at <file>:<line>` in the verdict file. Absence is itself signal — it weakens the SC-2 case.

### Pass B — Issue-specific adversarial generation

Generate **3 to 5** new challenges that go beyond the catalogue. The minimum is 3 — not aspirational, hard floor. Read the actual code paths the PoC depends on and look for:

- implicit invariants enforced by code outside the function the PoC targets
- exact economic analysis with realistic numbers
- atomicity / front-running / MEV / consensus-ordering constraints
- intentional design clues (`///` doc comments on neighbouring functions, calling-context constraints, internal-only helpers used only by trusted callers)
- interaction effects with other entry points (a permissionless `crank()` / `keeper()` that runs every slot and undoes the attacker's setup)
- **comparator-verification challenges** — when the finding makes a claim about how *another* system (wallet2, Anchor framework, OZ library, Pyth, etc.) behaves differently, the obvious challenge is "does that other system actually do this differently?" — formulated as: "verify against `<comparator>::<function>:<line>` that the comparator enforces what this finding claims it does." This is the F-10-class challenge that was missed in the vault-protocol run.

For each challenge, attempt a verdict: HOLDS / FAILS / UNCERTAIN, with code citations and a confidence label.

### Pass B — Wave 2 dispatch: parallel checker subagents (MANDATORY)

Same pattern as Pass A's Wave 2. After the Pass B generator produces 3-5 challenges:

1. **Filter against Pass A**: drop any Pass B challenge whose mechanism overlaps with a Pass A invalidator already checked (e.g., a Pass B challenge "EG-1-style guard at line X" duplicates a Pass A EG-1 check).
2. **Top-2 surviving challenges by gen-confidence**: dispatch **2 parallel checker subagents per challenge** (4 checker subagents total, Opus model — these are issue-specific and benefit from broader reasoning).

Each Pass B checker uses the same prompt template as Pass A but substituting:
- "Invalidation reason to check" → "Issue-specific challenge to check"
- The catalogue entry → the full Pass B challenge text + cited code refs from generator
- Output format adds: `Severity Impact` field maps to ADVANCE / DOWNGRADE / KILL_CHALLENGE.

**Majority rule (v0.1.10)**: identical to Pass A. 2-of-3 checkers must agree at HIGH confidence to auto-act on a HOLDS. Pass B uses **3 Opus checkers per top-2 challenge** (Opus across the board because issue-specific challenges benefit from broader reasoning; no model-mixing on Pass B).

**Independent verification**: orchestrator re-reads the cited code on every HIGH HOLDS before accepting it. The F-03 false-positive came from accepting a Pass B HIGH HOLDS challenge ("F-03 is the parser-side mirror of F-01") without independent verification — the verification step would have caught that "parser-side mirror" is not a finding-killing relationship (different code paths, different fixes).

### Pass B procedural floor (MANDATORY)

Pass B MUST generate at least **3 challenges**. If fewer than 3 are produced:

1. **Pass C MUST fire** on procedural-thinness grounds (judge mode `CLOSE_CALL_REVIEW (procedural)`).
2. The verdict file's Pass B section MUST list each missing slot with a sentence explaining why no challenge could be generated for that angle. Acceptable reasons are narrow: "no economic dimension to this finding", "no atomicity surface", etc. "I couldn't think of more" is NOT acceptable.

Reasoning: 1-of-3 challenges is what the F-10 false positive looked like. The wallet2-comparison challenge was the obvious missing one. The procedural floor forces explicit accounting for what was and wasn't challenged.

### Pass C — Symmetric Neutral Judge (UPDATED in v0.1.10 — 3-judge deliberative panel)

**v0.1.10 change**: Pass C is no longer a single Opus call. It is a 3-judge deliberative panel — three Opus subagents with diversified system prompts run in parallel; majority rules.

#### The three judges

- **Judge 1 — Steel-manning**: assume the finding is valid; what would invalidate it? Looks for the strongest case AGAINST the finding. Strict reviewer.
- **Judge 2 — Devil's-advocate**: assume the finding is invalid; what would validate it? Looks for the strongest case FOR the finding despite the challenges. Lenient reviewer.
- **Judge 3 — Balanced**: apply the rubric mechanically; do not pre-commit either way. Neutral reviewer.

Each judge receives the same input bundle (finding F-NN.md, Stage 3 verdict.md, Pass A/B verdicts, External Research cache, Mitigation Viability result, scope-carveout validity-check result).

#### Aggregation rule

Aggregate the three verdicts:

- **3-of-3 same verdict**: that's the Pass C verdict.
- **2-of-3 majority**: majority verdict applies; the dissenting judge's reasoning is recorded in the verdict file under `dissent:`.
- **1-1-1 split** (one VALID, one INVALID, one DOWNGRADE): resolve toward conservatism — verdict = DOWNGRADE one tier from Pass D's calibrated severity. Record all three reasonings in `three_way_split:`.

#### `high_holds_overrides` field (v0.1.10 update)

When the panel's verdict is VALID despite a HIGH-conf HOLDS in Pass A or Pass B:

- The override field MUST be confirmed by **Judge 3 (the balanced judge) specifically**. Steel-manning Judge 1 cannot unilaterally override (its bias is to invalidate, so a steel-manning override toward VALID is over-strong evidence). Devil's-advocate Judge 2 cannot unilaterally override (its bias is to validate).
- If the panel verdict is VALID via 2-of-3 majority but Judge 3 voted INVALID or DOWNGRADE, the verdict is downgraded to whatever Judge 3 said. Judge 3's vote is dispositive on overrides.

#### Cost note

Pass C now costs ~3× v0.1.9. Argus's overall Stage 4 cost increases by ~30% as a result, but the v0.1.10 Pre-Pass scope-carveout validity check kills more findings before reaching Pass C, partially offsetting.

### Pass C — when the judge fires

The judge fires when **any** of the following is true (NOT only when invalidation looks likely — uncertainty itself triggers final review):

1. **HOLDS_REVIEW**: any Pass A or Pass B challenge returned HOLDS with HIGH or MEDIUM confidence.
2. **CLOSE_CALL_REVIEW (uncertain)**: no challenge returned HOLDS, but at least one returned UNCERTAIN.
3. **CLOSE_CALL_REVIEW (rejected-high)**: every challenge returned FAILS, but at least one rejected challenge had Pass-A/B confidence = HIGH at generation time. A checker dismissing a HIGH-confidence reason is itself a signal worth a final review.
4. **CLOSE_CALL_REVIEW (procedural)**: Pass A returned fewer than 4 ranked invalidators OR Pass B returned fewer than 3 challenges. Procedural-thinness alone forces the judge to fire — even on otherwise-clean walks. Reasoning: thin walks systematically miss invalidators; the judge re-examines on procedural grounds.
5. **CLOSE_CALL_REVIEW (comparator-claim)**: the finding's impact case relies on a claim about how an external system (wallet2, Anchor framework, OZ, Pyth, another protocol) behaves, AND that claim is not cited to the comparator's source code. Forces the judge to weigh whether the comparator claim is verifiable.
6. **CLOSE_CALL_REVIEW (scope-carveout)**: Pre-Pass scope carve-out re-check returned WITHIN with strong-textual rebuttal, OR PARTIAL with any rebuttal quality. The judge weighs whether the rebuttal discharges the burden of proof against the carve-out's literal text.

Skip the judge ONLY when ALL of: every challenge returned FAILS, none was HIGH-confidence at generation, Pass A returned 4 ranked invalidators, Pass B returned ≥3 challenges, the finding makes no uncited comparator claim, AND the Pre-Pass scope carve-out re-check returned OUTSIDE_CARVEOUT. In that case the finding is confirmed VALID and proceeds to Pass D.

The judge process:

1. Read the original finding F-NN.md and its Stage 3 verdict.md.
2. Read every Pass A / Pass B challenge with full evidence — including the UNCERTAINs (the pattern of UNCERTAINs tells you where evidence is genuinely ambiguous).
3. Read the rank 3-4 advisory selections from Pass A's selector.
4. Independently read the cited code (do not trust subagent summaries). **Verify any HIGH-confidence HOLDS challenge by reading the exact cited lines yourself** — if the orchestrator's read does not support the HOLDS, downgrade that challenge to UNCERTAIN before judging.
5. Render: VALID | INVALID | DOWNGRADE.

#### HIGH-confidence HOLDS handling (NEW MANDATORY RULE)

If any Pass A or Pass B challenge returned **HIGH-confidence HOLDS** with code-cited evidence, the judge has exactly three legitimate responses:

1. **INVALID** — agree the HOLDS is correct; the finding is killed.
2. **DOWNGRADE** — agree the HOLDS partially holds; reduce severity to match.
3. **VALID with explicit override justification** — disagree with the HOLDS. The verdict file MUST contain a new field `high_holds_overrides` listing every HIGH-conf HOLDS challenge that was overridden, with a sentence explaining what specific evidence makes the orchestrator's reading wrong. **No silent overrides.** A `high_holds_overrides` field with content "Stage 8 may merge" or "let later stages handle" is invalid; the verdict file is rejected and Pass C re-runs.

Reasoning: the F-03 false positive came from Pass C producing VALID despite a HIGH-conf HOLDS Pass B challenge ("F-03 is the parser-side mirror of F-01 — they're the same finding"). The orchestrator deferred the conflict to Stage 8 instead of resolving it. The override-justification field forces the conflict to be resolved at Pass C, not deferred.

Standard:
- **INVALID**: invalidation reason(s) clearly hold AND no plausible way the issue manifests despite them. In CLOSE_CALL mode, INVALID requires cumulative weight of partial invalidations to render the issue effectively non-exploitable.
- **DOWNGRADE**: issue is real but constraints significantly limit severity / scope.
- **VALID**: invalidation reasons do not hold or are insufficient to negate the issue. **If any HIGH-conf HOLDS exists, `high_holds_overrides` field is mandatory.**

Do NOT default to VALID out of caution. Do NOT default to INVALID out of skepticism. Follow the evidence. A well-evidenced INVALID is correct; a well-evidenced VALID is correct.

#### Confidence-aware verdict mapping (NEW v0.2.2 — HARD RULE)

The judge emits `(verdict, confidence, reasoning)`. The FINAL action depends on BOTH dimensions, not just the verdict. The 3-judge panel's majority verdict is the input to this table; the panel's aggregated confidence (low if 1-1-1 split, high if 3-of-3, medium otherwise) is the second input:

| Judge verdict | Judge confidence | FINAL action |
|---------------|------------------|--------------|
| INVALID | HIGH | **KILL** (move to discard.md) |
| INVALID | MEDIUM | **DOWNGRADE to Low** (move to refine.md) — NOT KILL |
| INVALID | LOW | **DOWNGRADE to Low** (move to refine.md) — NOT KILL |
| DOWNGRADE | any | DOWNGRADE per judge proposal |
| VALID | HIGH | VALID at original severity (subject to Pass D + Stage 5/6/7 caps) |
| VALID | MEDIUM | VALID at original severity |
| VALID | LOW | VALID at original severity + record `judge_low_confidence_note: true` in verdict file |

**Rationale**: a low-confidence INVALID verdict from the judge panel is NOT sufficient evidence to kill a real finding. Downgrading to Low preserves the finding for human review while signaling weak conviction. The asymmetric treatment (low-conf INVALID downgrades but low-conf VALID is kept) reflects the cost asymmetry: incorrectly killing a real bug is more expensive than incorrectly preserving a non-bug.

**Why this matters**: Argus's pre-v0.2.2 standard mapping treated INVALID as a kill regardless of confidence. The 3-judge panel can produce an INVALID majority via, e.g., (steel-manning INVALID HIGH, devil's-advocate VALID MED, balanced INVALID LOW) → majority INVALID but panel-aggregate confidence is LOW. Pre-v0.2.2 this killed the finding; post-v0.2.2 it downgrades to Low for human review. This is the same family of fix as v0.2.1's partial-coverage rebuttal discipline (don't let weak rebuttals kill real findings).

**Origin**: HARD RULE inherited from upstream `heavyw8t/The-Judge` SKILL.md §Step 4C Output A. The original Argus design archive (Claude-works/15a-rust-judge-gap-closure.md §1.1) flagged this rule as critical and Argus v0.1.0 partially absorbed it but didn't preserve the LOW/MED-INVALID downgrade row. v0.2.2 ships the missing rows.

**Output schema requirement**: `judge-summary.json` (or the verdict file's Pass C section) MUST record `judge_verdict`, `judge_confidence`, and `final_action` — so downstream consumers (Stage 5 / Stage 8) can audit the mapping.

#### Procedural-thinness mode

When Pass C fires in `CLOSE_CALL_REVIEW (procedural)` mode, the judge MUST:

1. Generate the missing Pass A invalidators (bring count to 4) and verify them against code.
2. Generate the missing Pass B challenges (bring count to ≥3) and verify them against code.
3. Then render the verdict.

This is recovery work, not optional. The judge cannot rubber-stamp a thin Pass A/B; it must complete the missing analysis.

### Pass D — Severity Calibration (independent re-grade)

This is the asymmetry-fix. Earlier passes can only downgrade. Pass D independently grades severity from the verified attack path — and is allowed to **upgrade** as well as downgrade.

Why: an issue filed at Medium may, on inspection, allow direct theft of arbitrary user funds (Critical). An issue filed at Critical may, on inspection, only affect the attacker's own balance (Informational). Without Pass D, the original claimed severity becomes a ceiling that hides under-grading.

Build the calibrator input from pipeline state:

```
ATTACK_PATH_SUMMARY (≤200 words, orchestrator-built):
  - the precondition (state required, role required, market conditions required)
  - the mechanism (call sequence that triggers the bug)
  - the direct effect (what state changes, what value moves)
  - the harmed party (whose funds, whose access, whose state)
  - any boundary Pass C identified (downgrade reason)
```

Apply the rubric:

- **CRITICAL** — direct unconditional theft / loss of user funds, OR permanent freeze of material funds, OR catastrophic invariant break (infinite mint, total collateral drainable). No unrealistic preconditions.
- **HIGH** — theft / loss requiring non-trivial but realistic preconditions, OR temporary freeze of material funds, OR significant invariant break with user-impact propagation.
- **MEDIUM** — material harm to a subset of users under specific conditions, OR loss bounded by a parameter / rate limit, OR loss requires victim error / non-default usage, OR theft of fees / yield (not principal), OR DoS of an important function with viable workaround.
- **LOW** — small economic harm (rounding, dust), OR griefing with high attacker cost, OR DoS of non-critical function, OR informational leak with minor consequences.
- **INFORMATIONAL** — no economic harm, OR self-harm only, OR purely cosmetic, OR design trade-off where any fix has equivalent downside.

### C4-style historical-severity heuristic (UPDATED in v0.1.10 — overridable suggestion, not clamp)

The rubric above is rule-text. C4 judges in practice apply a *narrower* interpretation of "indirect with valid attack path." On the swafe run, Pass D upgraded H-1 and H-3 from Medium to High based on the literal rule wording — but C4's actual judgment was Medium for both.

The following bug-shapes, even when "indirectly compromise assets via a valid attack path," historically land at **Medium** in C4 / Sherlock / Cantina judging — not High. They are suggestions, not caps:

| Bug shape | C4 historical severity (suggestion) | Reason |
|-----------|------------------------------------|--------|
| Off-by-one in threshold / quorum math (`div_ceil(n) / 2`, etc.) | Medium | Bounded; requires specific N parity |
| Replay-without-version-binding on signed messages | **High (RECALIBRATED v0.2.0)** | Claude Web 4-stream empirics: 55% High, 38% Medium, 7% Critical across 310 findings. Argus's prior Medium default was empirically too low. |
| Missing `cnt` increment / one-shot latch broken | Medium | DoS / griefing primary; takeover requires chain with [other H findings] |
| Wrong-field reference (recover_backups, getter mismatch) | **High (RECALIBRATED v0.2.0)** | Claude Web empirics: 67% High, 28% Medium. Same recalibration. |
| Linear-time scan with attacker-controlled length | Medium | DoS without fund loss |
| Single-point-of-failure auth where readme expects multi-party | Medium | Deviation from documented invariant; not direct theft |
| Stale-state window / race between client and chain | Medium | Bounded by mining time; requires attacker monitoring |
| **Auth missing-signer / privilege check** (NEW v0.2.0) | **High** | Claude Web: 70% High, 18% Medium, 12% Critical. Argus's prior Medium default for `auth-missing-signer` class was empirically wrong. |
| **Account-substitution (V4-class)** (NEW v0.2.0) | **High** | Claude Web: 67% High, 28% Medium. |
| **Cross-instruction-id binding missing (V103)** (NEW v0.2.0) | **High** | Claude Web: 73% High, 18% Medium, 9% Critical. |
| **Underconstrained witness column (V104)** (NEW v0.2.0) | **High** | ZK soundness; defaults to High when reachable from public proof verification. |
| **Fiat-Shamir transcript incomplete (V106)** (NEW v0.2.0) | **Critical** | Claude Web: 67% Critical, 33% High. June-2025 Solana ZK ElGamal zero-day was Critical (mainnet feature disabled). |

#### Mandatory value-at-stake check (NEW v0.1.10) — before applying the suggestion

Before defaulting to Medium per the table, Pass D MUST estimate the dollar value at risk:

```
value_at_stake_check:
  estimated_value_at_risk_usd: <number or "unbounded">
  estimation_source: <PoC observation | TVL data | program treasury | "speculative">
  one_tx_drain_demonstrated: yes | no    # PoC shows direct fund-drain in one tx with no preconditions
  override_threshold_breached: yes | no  # >$1M unconditional drain → suggested override upward
```

Estimation sources:
- **PoC observation**: Tier-1/2 PoC moved or could-have-moved $X. Highest-quality source.
- **TVL data**: protocol's published TVL × proportion at risk per the exploit path.
- **Program treasury**: total balance of program-controlled accounts × proportion drainable.
- **Speculative**: orchestrator's estimate without quoted evidence. Lowest-quality; flag in verdict file.

#### Override matrix

| Bug shape match | Value at stake | One-tx drain? | Action |
|-----------------|----------------|---------------|--------|
| yes (table row) | < $100K | no | apply suggestion → Medium |
| yes | $100K–$1M | no | apply suggestion → Medium; record `value_at_stake_low` |
| yes | > $1M | no | **OVERRIDE UPWARD** to High; record `value_at_stake_override: yes` with PoC citation |
| yes | any | yes | **OVERRIDE UPWARD** to High or Critical per direct rubric (one-tx drain breaks the "bounded" assumption) |
| no | any | any | apply direct rubric without table consultation |

Override applied: write `severity_table_override:` with direction (upward), magnitude (one tier or two), and cited evidence (PoC tx hash / TVL link / quoted program treasury).

#### Why this changes vs v0.1.6

The v0.1.6 table was a hard clamp: "if shape matches, severity = Medium". This produced under-grading on Reflector (3 of 6 findings undergraded). v0.1.10 makes the table a *default suggestion* that is overridden when value-at-stake or one-tx drain evidence demands it. The historical bias toward Medium is preserved for the bounded cases the table was calibrated against; the override rule prevents the bias from clamping Critical fund-drains to Medium.

Write `CALIBRATED_SEVERITY` and `CALIBRATION_CONFIDENCE` to the verdict file. Then **clamp**:

```
final_severity = CALIBRATED_SEVERITY
if Stage-1 trust-model cap = TRUSTED-required: final_severity = min(final_severity, INFORMATIONAL)
if Pass-A IM/AM cap was MEDIUM-confidence trade-off: final_severity = min(final_severity, LOW)
if Pass C said DOWNGRADE with a stricter target than CALIBRATED_SEVERITY: final_severity = the stricter
```

Compute `SEVERITY_DIVERGENCE` = how `final_severity` compares to the original Stage-2 claimed severity:
- `CONFIRMED` (no change)
- `UPGRADED 1-tier`, `UPGRADED 2-tier`, `UPGRADED 3+-tier`
- `DOWNGRADED 1-tier`, `DOWNGRADED 2-tier`, `DOWNGRADED 3+-tier`

If `CALIBRATION_CONFIDENCE = LOW` AND `SEVERITY_DIVERGENCE ≥ 2-tier`, log a `SEVERITY_DIVERGENCE_WARNING` in the verdict file — calibration applies, but the trace flags it for human review.

The `final_severity` from Pass D is what advances to Stage 5.

## Anti-hallucination rule

Adapted from The Judge's evidence rule.

When a challenge depends on a numeric or external-behavior claim, the verdict for that challenge is `UNCERTAIN` unless the claim is grounded in:

- a code citation in scope (`<file>:<line>`)
- a Stage-1 protocol-map line that itself cites the project's docs
- on-chain data the auditor pasted into the run
- the PoC's own observable output

"Typically the heartbeat is 3600s" is not evidence. "The Cargo.toml pins `pyth-sdk-solana = '...'` and the deployed feed at address X has a heartbeat of 60s per its on-chain config" is evidence.

UNCERTAIN never KILLs and never DOWNGRADEs on its own — but it triggers the symmetric Pass C judge.

The same rule applies to Pass D: if calibrated severity depends on a numeric claim that is unverifiable, pick the more conservative tier. Don't upgrade severity based on training-data assumptions.

## Trust-model integration (UPDATED in v0.1.10 — numeric trust threshold)

Stage 4 enforces Stage 1's trust model. The legacy binary TRUSTED / SEMI-TRUSTED / UNTRUSTED model is replaced by `trust_threshold.level` (1-5) and `trust_threshold.layers_bypassed_by_finding` (count). See `shared-rules.md § Numeric trust threshold` for definitions.

For every finding:

1. From the PoC's repro steps, identify the actor(s) required to execute the attack.
2. Read Stage 1's `trust-model.md` to determine `trust_threshold.level` (the protocol's trust-architecture depth).
3. Read the finding's `path:` to count `layers_bypassed_by_finding` (how many trust layers the attack circumvents).
4. Apply the verdict matrix:

| layers_bypassed | Action |
|-----------------|--------|
| 0 | no severity impact (attack is permissionless OR uses a public role) |
| 1 | keep claimed severity — single-key compromise IS bug-bounty-relevant on most platforms |
| 2 ≤ N < level | DOWNGRADE one tier per additional layer (multi-key compromise is escalating-improbable) |
| N == level | INFORMATIONAL cap — entire trust set must act maliciously simultaneously (legacy TR-1 case) |

5. **TR-1 mapping**: legacy TR-1 fires when `layers_bypassed == level`. Pass A's TR-1 catalogue entry now reads this field.
6. **TR-2 distinction** (UNCHANGED): if the role takes a *legitimate* admin action and the *code* behaves *unexpectedly* (action correct, code buggy), this is a code bug not a trust issue. Do not apply the cap regardless of `layers_bypassed`.

### Worked example

- Protocol: governance + 2-of-3 multisig + 24h timelock. `trust_threshold.level = 4`.
- Finding A: "Anyone can call `claim_rewards` to drain the rewards pool." `layers_bypassed = 0` → keep severity.
- Finding B: "If the signer key on multisig position 1 leaks, attacker can change the oracle." `layers_bypassed = 1` → keep severity (single-key compromise is bug-bounty-relevant).
- Finding C: "If 2 of 3 multisig signers AND timelock executor collude, oracle change instant." `layers_bypassed = 2` → DOWNGRADE one tier (multi-key collusion is improbable but possible).
- Finding D: "If governance, all 3 multisig signers, and timelock executor act maliciously, funds drain." `layers_bypassed = 4 = level` → INFORMATIONAL cap (out of bounty scope).

## Per-finding output schema

`$RUN_DIR/4-adversarial/F-NN.md`:

```markdown
# F-NN Stage 4 verdict

- **finding**: <title>
- **claimed severity (Stage 2)**: <severity>
- **calibrated severity (Pass D)**: <severity>
- **final severity (post clamps)**: <severity>
- **severity divergence**: CONFIRMED | UPGRADED N-tier | DOWNGRADED N-tier
- **status**: ADVANCE | DOWNGRADE(<sev>) | KILL(<challenge ID or reason>)

## Pre-Pass: Scope carve-out + code-comment re-check (MANDATORY, runs FIRST)

### Scope carve-out
| Section | Quoted text | Match | Rebuttal quality |
|---------|-------------|-------|------------------|
| <name> | "..." | WITHIN / PARTIAL / OUTSIDE | strong-textual / weak-interpretive / absent / n/a |

- **scope-carveout action**: KILL(scope-carveout-<section>) | DOWNGRADE_CAP_LOW | PROCEED | PROCEED_PASS_C_FIRES

### Code-comment scan
| File:line | Comment | Classification |
|-----------|---------|----------------|
| <file:L> | "<verbatim>" | SUPPORTS_FINDING / DOCUMENTS_AS_DESIGN / NEUTRAL |

- **code-comment action**: KILL(code-comment-documents-as-design) | STRENGTHEN_AND_PROCEED | PROCEED

If KILL fires here, the verdict file ends after this section. Pass A/B/C/D are skipped.

## Docstring-disclaimer pre-check (MANDATORY)

For each cited function in the finding's `location`:

| Function | File:Line | Docstring disclaimer (verbatim) | SC-2 candidate? |
|----------|-----------|--------------------------------|-----------------|
| <fn> | <file:line> | <quote OR "none found"> | yes / no |

If "yes" for any row, SC-2 MUST appear in Pass A's top-4 selections.

## Comparator-claim audit (MANDATORY)

Does the finding's impact case rely on comparison to an external system (wallet2, Anchor, OZ, Pyth, etc.)?

- **comparator claim present?**: yes / no
- **if yes — claim**: <quote from F-NN.md>
- **if yes — comparator cited?**: yes (citation: `<repo>/<file>:<line>` or URL) / no
- **if uncited**: Pass C will fire in `CLOSE_CALL_REVIEW (comparator-claim)` mode.

## Pass A — Generic invalidator scan

Selector MUST rank 4 entries. Empty rows = procedural-thinness failure.

Selector top-2 (checked):
| Rank | ID | Confidence | Verdict | Evidence |
|------|----|------------|---------|----------|
| 1 | XX-N | HIGH/MED/LOW | HOLDS/FAILS/UNCERTAIN | <citation> |
| 2 | XX-N | ... | ... | ... |

Selector advisory rank 3-4 (passed to Pass C as considered alternatives, not independently checked):
| Rank | ID | Confidence | Why this might apply |
|------|----|------------|----------------------|
| 3 | XX-N | HIGH/MED/LOW | <2-3 sentences> |
| 4 | XX-N | ... | ... |

If any rank is missing: `pass_a_procedural_thinness: yes` — and Pass C MUST fire.

## Pass B — Issue-specific challenges

Minimum 3 challenges. If fewer: `pass_b_procedural_thinness: yes` — and Pass C MUST fire. The verdict file MUST account for each missing challenge slot with an explicit reason.

### Challenge 1: <title>
- **gen confidence**: HIGH/MED/LOW
- **verdict**: HOLDS / FAILS / UNCERTAIN
- **mechanism**: <how the challenge would invalidate>
- **evidence**: <code citation>
- **explanation**: <2-4 sentences>

### Challenge 2: ...

### Challenge 3 (or "skipped because <reason>"): ...

## Pass C — Symmetric neutral judge

- **judge mode**: HOLDS_REVIEW | CLOSE_CALL_REVIEW (uncertain) | CLOSE_CALL_REVIEW (rejected-high) | CLOSE_CALL_REVIEW (procedural) | CLOSE_CALL_REVIEW (comparator-claim) | SKIPPED (clean VALID — all gates passed)
- **judge verdict**: VALID | INVALID | DOWNGRADE
- **judge confidence**: HIGH | MEDIUM | LOW
- **judge target severity (if DOWNGRADE)**: <sev>
- **justification**: <5-10 sentences. In CLOSE_CALL mode, explicitly address what UNCERTAINs or rejected-HIGH reasons signaled and why that did or did not change the conclusion.>
- **high_holds_overrides** (MANDATORY if any HIGH-conf HOLDS exists in Pass A or Pass B AND the verdict is VALID):
  | Challenge | HOLDS evidence | Override justification |
  |-----------|----------------|------------------------|
  | <Pass A/B reference> | <quoted evidence> | <specific reason the orchestrator's reading is wrong; "let Stage 8 handle" is REJECTED> |
- **procedural recovery** (MANDATORY if mode is `(procedural)`):
  - missing Pass A invalidators added: <list>
  - missing Pass B challenges added: <list>

## Pass D — Severity calibrator

- **attack path summary**: <≤200 words: precondition, mechanism, effect, harmed party>
- **calibrated severity**: <Critical/High/Medium/Low/Informational>
- **calibration confidence**: HIGH | MEDIUM | LOW
- **divergence from Stage-2 claim**: NONE | UPGRADED N-tier | DOWNGRADED N-tier
- **clamps applied**:
  - trusted-role cap → INFORMATIONAL: yes / no
  - trade-off cap → LOW: yes / no
  - judge stricter-DOWNGRADE: yes (target = <sev>) / no
- **severity_divergence_warning**: yes (low confidence + ≥2-tier divergence) / no

## Trust-model match

- **actor required**: <name>
- **trust level (per Stage 1)**: TRUSTED | SEMI-TRUSTED | UNTRUSTED
- **TR-1 applied?**: yes / no — <reason>
- **TR-2 applies?**: yes / no — <action correct, code buggy distinction>
```

## Subagent decomposition

For >10 surviving findings entering Stage 4: spawn one general-purpose subagent per finding to draft Pass A + Pass B verdicts in parallel. The orchestrator then runs Pass C + Pass D and verifies decisive HIGH-confidence HOLDS evidence by reading the cited code itself before accepting the verdict.

**Subagent results are advisory** — if the orchestrator's own read of the cited code does not support a HOLDS, downgrade that challenge to UNCERTAIN.

For ≤10 findings, run sequentially in the orchestrator. Subagent dispatch overhead exceeds the speed-up at small N.

## Pass D edge cases

| Case | Handling |
|------|----------|
| Calibrator times out / fails | Log `Pass D: FALLBACK`. Use legacy `min(claimed, MAX_SEVERITY, judge_DOWNGRADE)` logic. |
| LOW confidence + 2+ tier divergence | Apply calibrated severity but tag verdict file `SEVERITY_DIVERGENCE_WARNING`. Surface in Stage 8 final output. |
| Pass C said INVALID | Skip Pass D entirely. Severity = N/A. KILL the finding. |
| Original Stage 2 claim was missing | Calibrator runs without anchor — uses rubric only. Mark `Stage-2 unclaimed`. |
| Trusted-role cap fires | Calibrate first, then clamp to INFORMATIONAL. Surface both numbers in verdict file. |
