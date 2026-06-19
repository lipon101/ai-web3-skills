# ONRE Finance — Audit hypothesis map (Argus pre-input)

> **Save this file to `<onre-sol-clone>/assets/docs/onre-patterns.md`** before invoking `/argus` against the ONRE Finance repo.
>
> Argus reads `assets/docs/*` at Stage 1 as project-context input. The hypotheses below are treated as priority targets for Stage 2 angles, not as confirmed findings — every claim still goes through the full Stages 2-8 pipeline (FINDING schema → Pass A/B/C/D adversarial → Stage 5/6/7 gates).
>
> **Audit context**:
> - Target: ONRE Finance — `onreuGhHHgVzMWSkj2oQDLDtvvGvoepBPkqyaubFcwe` (Solana)
> - Repo: `github.com/onre-finance/onre-sol`
> - Bounty: Immunefi (Smart Contract category) → Argus runs in `smart-contract` mode (v0.3.1 recommendation rule).
> - Argus version this file targets: v0.3.3+
> - Vector catalogue: `references/attack-vectors/rust-attack-vectors.md` (V1–V132)

---

## 1. Critical audit targets (priority hypotheses)

These are concrete code locations and bug-class hypotheses derived from a manual read of the ONRE codebase. Each lists the **corrected** V-ID from the actual catalogue (the prior `ore.md` draft had wrong mappings; this is the fix).

### H-1 — Immutable-program boss takeover

- **Location**: `instructions/initialization/initialize.rs:71-76`
- **Bug class**: missing authorization gate when `upgrade_authority == None`
- **Primary V-ID**: **V4** (Account-substitution via missing owner / discriminator check) — the `initialize` handler's identity check is gated inside `if let Some(upgrade_authority) = ...` and skipped when the program is immutable.
- **Secondary V-ID**: **V40** (Anchor `init` front-run on shared PDA) — same family; the `init` handler accepts attacker-supplied `boss` after the canonical authority is removed.
- **Cited code**:
  ```rust
  let upgrade_authority = match UpgradeableLoaderState::from_keyed_account(&program)? {
      UpgradeableLoaderState::ProgramData {
          upgrade_authority_address,
          slot: _,
      } => upgrade_authority_address,
  };
  if let Some(upgrade_authority) = upgrade_authority {
      require_keys_eq!(upgrade_authority, boss.key(), ONREError::InitializationFailed);
  }
  // None branch: no check → anyone can become boss
  ```
- **Suspected severity**: Critical (if confirmed) — full admin takeover, `close_state` callable, kill-switch togglable.
- **Stage 2 angle**: **Auth/Account/Signer/Origin** (primary), **First Principles** (secondary — assumption "upgrade_authority is always Some" violated when program is immutable).
- **What Argus Stage 3 should build**: an `anchor-test` harness that deploys the program with `--final` (immutable), then invokes `initialize` from a non-deployer keypair. If `state.boss == attacker_pubkey` after the call, CONFIRMED.
- **Reachability_check expectation**: `initialize` is `pub fn` in the program module, reachable from any signer via `program.methods.initialize()` — definitely production-reachable.

### H-2 — Permissionless approval bypass

- **Location**: `instructions/offer/take_offer_permissionless.rs` (handler body)
- **Bug class**: privileged validation skipped in alternative code path
- **Primary V-ID**: **V1** (Missing `signer` constraint on Anchor authority account) — applied to the *approval gate*, not the signer slot. The `take_offer` handler calls `verify_offer_approval` when `offer.needs_approval`; `take_offer_permissionless` may omit that call.
- **Secondary V-ID**: **V58** (Empty swap-data path bypasses input-token validation) — by analogy: alternative entry point skips a guard the canonical path enforces.
- **What to verify**: does `take_offer_permissionless` have a branch like:
  ```rust
  if offer.needs_approval {
      verify_offer_approval(/* ... */)?;
  }
  ```
  If absent (or gated by `allow_permissionless && !needs_approval`), the bug fires.
- **Stage 2 angle**: **Vector Scan** (V1 pattern) + **Auth/Account/Signer/Origin** (approval-gate weaponization across handlers) + **Execution Trace** (cross-handler invariant gap).
- **`weaponization_check` expectation**: Stage 2 angle MUST grep for `verify_offer_approval` and confirm whether it's called in `take_offer_permissionless`. If `take_offer` calls it but `take_offer_permissionless` doesn't, that's the bug.
- **What Argus Stage 3 should build**: integration test creating an Offer with `needs_approval=true, allow_permissionless=true`, then invoking `take_offer_permissionless` *without* a valid approval signature. If the tx succeeds, CONFIRMED.
- **Suspected severity**: High — token theft from maker without approval.

### H-3 — Token account destination substitution

- **Location**: `instructions/offer/take_offer_permissionless.rs` — `#[derive(Accounts)]` struct
- **Bug class**: Anchor account-validation gap on destination token account
- **Primary V-ID**: **V4** (Account-substitution via missing owner / discriminator check) — `token_out_user_account` accepted without `constraint = token_out_user_account.owner == user.key()`.
- **Cited pattern**:
  ```rust
  // VULNERABLE
  #[derive(Accounts)]
  pub struct TakeOfferPermissionless<'info> {
      pub token_in_user_account: Account<'info, TokenAccount>,
      pub token_out_user_account: Account<'info, TokenAccount>,
      pub user: Signer<'info>,
      // ...
  }

  // FIXED
  #[derive(Accounts)]
  pub struct TakeOfferPermissionless<'info> {
      pub token_in_user_account: Account<'info, TokenAccount>,
      #[account(
          constraint = token_out_user_account.owner == user.key() @ ONREError::TokenAccountOwnerMismatch
      )]
      pub token_out_user_account: Account<'info, TokenAccount>,
      pub user: Signer<'info>,
  }
  ```
- **Stage 2 angle**: **Auth/Account/Signer/Origin** (primary owner-check). Pure `#[derive(Accounts)]` read.
- **What Argus Stage 3 should build**: integration test where attacker (signer = `attacker_kp`) passes victim's token account as `token_in_user_account` and attacker's token account as `token_out_user_account`. If tokens move victim→attacker, CONFIRMED.
- **Suspected severity**: High — direct token theft.
- **Sister-handler check**: `take_offer.rs` may have the same gap or may have the constraint — `weaponization_check` should compare.

### H-4 — Clock-based price-vector selection

- **Location**: `instructions/offer/offer_state.rs` — `find_active_vector_at` (or equivalent)
- **Bug class**: timestamp-driven selection of pricing vector without TWAP / leader-resistance
- **Primary V-ID**: **V19** (Single-block oracle manipulation — AMM spot price as oracle) — generalized: the *active pricing vector* is the "oracle" here; a leader manipulating `Clock::get()?.unix_timestamp` can select a favorable vector.
- **Secondary V-ID**: **V32** (Mid-operation config mutation) — if pricing vectors can be added mid-flight while a tx is being processed.
- **Suspected severity**: Likely Medium → Low after Pass D calibration. Solana validator timestamp drift is bounded (~400ms typical, ~1.5s outlier). Practical exploit requires leader-slot control + favorable inter-vector price gap. Pass A UP-3 (precise block-timestamp control) may downgrade.
- **What Argus Stage 3 should build**: unit test that constructs an `Offer` with 2+ pricing vectors spanning a slot boundary, then calls the pricing function with mocked `Clock` values across the boundary. Demonstrate the vector switches favorably with attacker-chosen timestamp.
- **Pre-Pass note for Stage 4**: scope-carveout check — the ONRE README may document timestamp-based vector selection as intentional. If yes, finding caps at Informational (SC-2).

### H-5 — Missing account closures in `close_state`

- **Location**: `instructions/state/close_state.rs` — `close_state` handler
- **Bug class**: finality-flow incomplete-closure (orphaned PDA token accounts after state closure)
- **Primary V-ID**: **no clean V-match** — closest is V22 (Missing `rent_exempt` check) by analogy, but the real shape is "close-state-style finality flow doesn't close all associated PDA token accounts."
- **Catalogue gap candidate**: if Argus confirms this on ONRE, propose **V133** — "Close-state / finality flow leaves orphaned PDA token accounts." Worth filing back to the Argus catalogue.
- **Stage 2 angle**: **Invariant** (state-coupling: state-closed ↔ all associated accounts closed) + **Periphery** (the close-state handler often lives in a utility module).
- **What to check**: enumerate every PDA token account created by other handlers (vault PDA, permissionless authority PDA, etc.). For each, verify `close_state` includes it in the close-set. Any orphan → CONFIRMED.
- **Suspected severity**: Medium (locked funds) → could be Low if the orphan is recoverable via another instruction.

### H-6 — Cross-offer approval message replay

- **Location**: `instructions/offer/take_offer.rs` — `verify_offer_approval` body
- **Bug class**: signed-message replay across offers due to missing domain separation
- **Primary V-ID**: **V20** (Replay — missing nonce / domain / chain-id) — approval message must bind to `(offer_pda, user_pubkey, expiry)`. If it only signs `(amount, user_pubkey, expiry)`, the same approval is valid for any offer.
- **Secondary V-ID**: **V28** (Domain separation missing — same key for two purposes) — by analogy if the approver key is shared across approval contexts.
- **What to check**: read the `verify_offer_approval` source. The signed message bytes MUST include the offer's PDA (or another offer-unique identifier). If they don't, the bug fires.
- **Stage 2 angle**: **First Principles** (assumption "approval is bound to this offer") + **Vector Scan** (V20 pattern).
- **What Argus Stage 3 should build**: integration test creating two offers (A, B), getting a valid approval for offer A from the approver, then invoking `take_offer` on offer B with the offer-A approval. If accepted, CONFIRMED.
- **Suspected severity**: Medium → High depending on what offers can be cross-replayed (only same-user offers vs any-user offers).

---

## 2. Cross-cutting invariants to verify

Stage 1 should extract these as `invariants.md` entries. Stage 2 angles should test each:

1. **CPI program-ID verification**: every `invoke` / `invoke_signed` must use a hard-coded or PDA-validated `program_id`. Never accept from user input.
2. **Token-account owner check**: every token account passed as a fund source MUST have its `owner` field checked against the signer or an authorized PDA via `#[account(constraint = ...)]`.
3. **Approval-message domain binding**: signed approval messages MUST bind to `(offer_pda, user_pubkey, expiry, nonce)` — anything weaker is replay-class.
4. **Kill-switch coverage**: `kill_switch_enabled` MUST be checked in ALL offer / redemption / vault paths, not just the permissionless variants.
5. **`close_state` is final**: there is no recovery once invoked. The handler MUST be gated behind boss-level authorization AND close every associated PDA token account in one atomic action.
6. **Zero-copy discriminator check**: `Offer` uses `#[account(zero_copy)]` + `AccountLoader`. Before `AccountLoader::load*()`, the Anchor discriminator MUST be verified (the framework does this; verify the program isn't using `try_borrow_mut_data` directly to bypass).

---

## 3. Stage-2 angle dispatch (suggested priorities)

When Argus dispatches the 8 angles in parallel at Stage 2, the following priorities apply for ONRE:

| Angle | Priority | Why |
|-------|----------|-----|
| **Auth/Account/Signer/Origin** | **highest** | 4 of 6 hypotheses (H-1, H-2, H-3, partial H-5) are auth-class. Anchor `#[derive(Accounts)]` is the primary attack surface. |
| **Vector Scan** | highest | V1, V4, V19, V20, V40, V58 all map cleanly to ONRE hypotheses. Run the full catalogue scan. |
| **First Principles** | high | H-1's `if let Some(...)` assumption + H-6's domain-binding assumption both fit. |
| **Execution Trace** | high | H-2 is a cross-handler invariant gap (`take_offer` vs `take_offer_permissionless`). |
| **Invariant** | high | The 6 invariants in §2 above. |
| **Math Precision** | medium | H-4 is borderline arithmetic (timestamp selection); no other obvious math classes. |
| **Economic Security** | medium | H-4 has economic dimension (pricing arbitrage); other findings are non-economic auth/state issues. |
| **Periphery** | low | ONRE codebase appears self-contained; helper-module-only bugs less likely. |

---

## 4. Expected Stage-3 PoC tiers

| Hypothesis | Expected tier | Notes |
|------------|---------------|-------|
| H-1 boss takeover | **Tier-1 E2E** | `anchor test` with `--final` deployment; observable state.boss change |
| H-2 approval bypass | **Tier-1 E2E** | `anchor test`; tx succeeds without approval signature |
| H-3 destination substitution | **Tier-1 E2E** | `anchor test`; tokens move to attacker account |
| H-4 clock manipulation | **Tier-3** (math + mocked Clock) — Tier-1 infeasible without slot-leader control | Cite Stage-3 limitation |
| H-5 missing closures | **Tier-2 integration** — observe rent-exempt orphan accounts post-`close_state` |
| H-6 approval replay | **Tier-1 E2E** | Two offers, replay approval, observe acceptance |

H-1, H-2, H-3, H-6 should all be runnable via `anchor test` against `solana-test-validator` on localnet. The user-notes file flags this to Stage 3 so it doesn't waste effort on Tier-3 fallbacks when Tier-1 is achievable.

---

## 5. Pre-Pass-1 scope check expectations

Stage 4 Pre-Pass 1 will check ONRE's README + scope docs for carve-outs. Expected findings:

- **Centralization risks** — most likely a section exists ("boss has full control"). H-1 is NOT covered by this carve-out because it allows *anyone* to become boss, not "trusted boss does X."
- **Time-sensitivity** — H-4 may be partially covered if README documents timestamp-based pricing as intentional. Expect `scope_carveout_check: PARTIAL` for H-4.
- **All other hypotheses** — expected `OUTSIDE` carve-out.

---

## 6. Expected Stage-6 program-triage outcome

ONRE is Immunefi-tagged **Smart Contract**, so SC mode applies. Immunefi smart-contract bounty payouts:

- **Critical**: direct theft of user funds, permanent freeze, governance manipulation with direct outcome change.
- **High**: theft of unclaimed yield, temporary freeze, oracle manipulation.
- **Medium**: smart-contract DoS, griefing, OOG / CU exhaustion.
- **Low**: contract fails to deliver promised returns without value loss.

Expected severity mapping:

| Hypothesis | Suspected severity | Immunefi tier |
|------------|---------------------|----------------|
| H-1 | Critical | Critical (governance manipulation w/ direct outcome) |
| H-2 | High | High (theft of maker's tokens) |
| H-3 | High | High (direct theft) |
| H-4 | Medium → Low | Low (limited value extraction on permissionless network) |
| H-5 | Medium | Medium (DoS / fund-lock) |
| H-6 | Medium-High | High if cross-user replay, Medium if same-user only |

---

## 7. AI-provenance discipline

All findings produced by Argus on ONRE are AI-generated drafts. Before submitting to Immunefi:

1. Manually re-read the cited code at the cited line numbers.
2. Independently re-derive the exploit path.
3. Run the Stage-3 PoC and confirm the output.
4. Re-verify scope against the live Immunefi ONRE bounty page.
5. Rewrite the writeup in your own words.

Cantina AI-3 doesn't apply to Immunefi, but Immunefi's submission discipline expects original writing and reproducible PoCs.

---

## 8. What this file is NOT

- Not a finding list. Each hypothesis above is a *priority candidate* for Stage 2 to investigate, not a confirmed bug.
- Not a substitute for Argus's pipeline. Stages 2-8 still run in full. Stage 4 adversarial review may KILL several of these hypotheses with HIGH-conf HOLDS.
- Not a vector-catalogue authority. The V-IDs cited are best-effort mappings to `references/attack-vectors/rust-attack-vectors.md`; Stage 2 Vector Scan may pick different / additional V-IDs based on the actual code.

---

## Usage

1. Save this file as `<onre-sol>/assets/docs/onre-patterns.md` after cloning the ONRE repo.
2. In Claude Code, `cd <onre-sol>` and invoke `/argus`.
3. Argus will detect the Anchor project shape, route to `smart-contract` mode (per v0.3.1 recommendation rules), and read this file at Stage 1.
4. Output lands at `<onre-sol>/argus/<UTC-timestamp>/`.

For SC mode Argus runs, Stage 3 uses the standard Tier-1/2/3/4 ladder (Tier-1 E2E `anchor test` preferred). The v0.3.3 Tier-1-live-e2e mandatory rule is `infra` mode only; SC mode keeps its existing tier ladder + Pass A/B/C/D adversarial chain.
