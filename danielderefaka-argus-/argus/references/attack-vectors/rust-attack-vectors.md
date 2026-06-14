# Rust Attack Vectors — Library

Vector library for the Vector Scan agent. Each entry: a concrete failure pattern with a description (D), a "fixed pattern" (FP) signal, and where applicable a `Fix:` recommendation.

This library covers Solana / Anchor, CosmWasm, Substrate, and generic Rust on-chain code. **Adopt the same convention as Solidity Auditor's attack-vectors.md**: extend the library when a new vector is encountered in a real codebase. Each new entry gets the next `Vn` ID.

---

**V1. Missing `signer` constraint on Anchor authority account**

- **D:** `#[derive(Accounts)]` struct gates a privileged operation but the authority account is `AccountInfo` / `UncheckedAccount` instead of `Signer<'info>`, OR a `#[account(...)]` constraint is missing the `signer` keyword. Attacker passes any account in place of the authority and the program performs the action.
- **FP:** Privileged authority is `Signer<'info>` and the constraint validates ownership / address. Or `#[account(..., signer = authority)]` constraint present.

**V2. Missing `ensure_signed` / `ensure_root` on Substrate dispatchable**

- **D:** `#[pallet::call]` function omits `ensure_signed(origin)` / `ensure_root(origin)` / `T::EnsureOrigin::ensure_origin(origin)` — anyone can dispatch with any origin.
- **FP:** Dispatchable's first line is the appropriate ensure call.

**V3. PDA seed/bump confusion (`find_program_address` vs `create_program_address`)**

- **D:** Program uses `Pubkey::create_program_address(&[seeds, &[bump]], &program_id)` with attacker-supplied bump or attacker-supplied seeds — does not enforce canonical bump. Attacker can derive any address with the right bump search.
- **FP:** Uses `Pubkey::find_program_address(&[seeds], &program_id).0` (canonical). Anchor `seeds = [..]` + `bump` constraint enforces canonical.

**V4. Account-substitution via missing owner / discriminator check**

- **D:** Solana program reads an account's data without validating `account.owner == program_id` or without checking the Anchor discriminator. Two account types with overlapping Borsh layout can be swapped — attacker passes an account of type B where type A is expected.
- **FP:** `Account<'info, T>` (Anchor — auto-validates discriminator + owner). Native: explicit `if account.owner != program_id { return Err(..) }` + discriminator byte check.

**V5. Unchecked Borsh deserialization → length-prefix DoS**

- **D:** `T::try_from_slice(data)` where `T` has a `Vec<U>` / `String` field. Attacker provides a length prefix indicating GBs of allocations — program panics or runs out of CU during allocation.
- **FP:** Bounded length check before deserialization, OR custom `BorshDeserialize` impl with explicit max-length enforcement.

**V6. Borsh canonical-form collision**

- **D:** Two distinct byte sequences deserialize to the same `T` (via redundant `Option<None>` encoding, padding, or non-canonical enum tags). Used as a message-uniqueness key (signature replay, dedup), the collision breaks uniqueness.
- **FP:** Re-serialize after deserialize and compare; reject inputs that don't round-trip canonically.

**V7. CPI integrity — passing user-controlled program ID**

- **D:** `solana_program::program::invoke(&instruction, &accounts)` where `instruction.program_id` came from user input or an unverified account field. Attacker substitutes a malicious program ID.
- **FP:** Hard-coded program ID, OR validation against an allowlist before `invoke`.

**V8. Solana CPI re-entry**

- **D:** Program A invokes program B via CPI before A has finished updating state. Program B (controlled by attacker via V7 or naturally) calls back into A — A's state is inconsistent.
- **FP:** State updates committed before CPI (CEI-equivalent). Or explicit re-entry-guard storage flag.

**V9. CosmWasm submessage `reply_on` mishandling**

- **D:** `SubMsg::new(...).reply_on(ReplyOn::Always)` but `reply` handler doesn't check `SubMsgResult::Err` — failures pass silently. Or `ReplyOn::Success` skipped when error path mattered.
- **FP:** `reply` handler matches on `SubMsgResult` and propagates errors / handles failures explicitly.

**V10. Substrate dispatchable calling unbounded extrinsic without weight accounting**

- **D:** A `#[pallet::call]` function calls another pallet's extrinsic via `dispatch_as` without including its weight in the calling function's `#[pallet::weight]`. Attacker triggers the path → block-author DoS.
- **FP:** Weight calculated from worst-case nested dispatch via `Weight::from_parts(...)` with proper accounting.

**V11. `unwrap()` / `expect()` on caller-controlled input**

- **D:** Public entry point calls `borsh::from_slice::<T>(data).unwrap()` (or similar `Result::unwrap` / `Option::unwrap` / `slice[idx]`) on caller-controlled data. Forced panic → instruction failure → liveness break (Solana CU exhaustion / Substrate block-author panic / CosmWasm tx abort).
- **FP:** All `Result` / `Option` from caller data is propagated via `?` with explicit error mapping.

**V12. Unchecked integer arithmetic (Solana BPF default no-overflow-panic)**

- **D:** `u64` / `u128` arithmetic via `+ - * /` without `checked_*` / `saturating_*` / `overflowing_*`. Solana BPF programs do NOT panic on overflow in non-debug builds by default — silent wrap-around.
- **FP:** Every arithmetic op uses `checked_add` / `checked_sub` / `checked_mul` / `checked_div`. Or `overflow-checks = true` in `Cargo.toml` profile (slower but safer).

**V13. Truncation downcast (`as u32` from `u64`)**

- **D:** `let x: u32 = some_u64 as u32` — silent truncation. Common in price feeds, share calculations, timestamps. No bounds check.
- **FP:** `u32::try_from(some_u64).map_err(|_| ...)?`

**V14. Order-of-operations precision loss**

- **D:** `(a / b) * c` where `b > c` — division truncates first, multiplication amplifies the truncation. Common in fee formulas and reward calcs.
- **FP:** `(a * c) / b` (multiply first), with overflow check on `a * c`.

**V15. Wrong rounding direction**

- **D:** Vault `deposit` rounds shares UP (favoring depositor); `withdraw` rounds assets UP (favoring withdrawer); `borrow` rounds debt DOWN; `fee` rounds DOWN. Each wrong direction is a drain candidate; compoundable wrong direction is critical.
- **FP:** Deposits round shares DOWN, withdrawals round assets DOWN, debt rounds UP, fees round UP.

**V16. Zero-rounding theft**

- **D:** Minimum input (1 lamport / 1 unit / 1 share) into `fee = amount * fee_bps / 10_000` truncates to zero. Or `reward = stake * reward_per_share / SCALE` becomes zero with large `total_staked`.
- **FP:** Explicit `if amount > 0 && fee == 0 { fee = 1 }` minimum, OR the fee is collected on aggregate flows not per-call.

**V17. First-depositor / vault share inflation**

- **D:** Vault has `if total_supply == 0 { shares = amount }` path. Attacker `deposit(1)` then directly transfers a large amount to the vault, inflating `total_assets`. Next depositor receives 0 shares due to rounding.
- **FP:** Virtual offset on `total_supply` (e.g., 1e6 phantom shares), OR enforced minimum first-deposit, OR dead-shares burn.

**V18. Missing oracle staleness check**

- **D:** Pyth / Switchboard / Band oracle read without validating `pub_slot` / `updated_at` against a max-staleness threshold appropriate for the asset's volatility.
- **FP:** `if current_slot - price.pub_slot > MAX_STALENESS_SLOTS { return Err(..) }`

**V19. Single-block oracle manipulation (AMM spot price as oracle)**

- **D:** Code reads `pool.reserves` to compute price for valuation / liquidation / mint without TWAP. Flash-loanable manipulation in same tx.
- **FP:** TWAP with ≥ 30-min window; or external Pyth/Chainlink/Band oracle.

**V20. Replay — missing nonce / domain / chain-id**

- **D:** Signed payload (off-chain signature, governance vote, bridge message) omits a nonce, domain separator, or chain-id. Same signature reusable across messages, contracts, or chains.
- **FP:** EIP-712-equivalent domain separator with `chain_id` + `verifying_contract` + monotonic nonce.

**V21. Force-transfer via direct `lamports +=`**

- **D:** Solana program manipulates `**account.try_borrow_mut_lamports()? += amount` instead of via SPL Token CPI — bypasses Token-program's accounting. Attacker can force-fund accounts; `total_supply` desync.
- **FP:** All token movement via SPL Token CPI; lamport-level ops only for native SOL accounts and only via `system_program::transfer`.

**V22. Missing `rent_exempt` check**

- **D:** Account holds lamports but program doesn't enforce rent-exempt minimum balance. Account can be force-closed by rent collection, losing data.
- **FP:** `account.is_exempt(rent.minimum_balance(account.data_len()))` checked at creation and after every withdrawal.

**V23. Anchor `init_if_needed` race**

- **D:** Two instructions in same tx use `init_if_needed` for the same account — first init sets attacker-controlled state, second sees existing account and trusts its state.
- **FP:** Plain `init` (not `init_if_needed`); or explicit state-validity check after `init_if_needed`.

**V24. CosmWasm query mutating state via interior mutability tricks**

- **D:** Query handlers (which must be read-only) using `RefCell<T>` / `Cell<T>` / `Mutex<T>` patterns to bypass the immutable-borrow rule on `Deps`. Behavior: state mutated during a "query".
- **FP:** Queries strictly read-only; any mutation goes through `execute`.

**V25. Substrate `Hooks::on_initialize` unbounded work**

- **D:** `fn on_initialize(_: BlockNumber) -> Weight` does work proportional to the size of a storage map / iter that can grow without bound (user accounts, pending requests). Block-author DoS as the map grows.
- **FP:** `on_initialize` has constant or O(log n) work; pagination via `on_idle` for unbounded scans.

**V26. Missing re-entry guard on CW20 send-receive callback**

- **D:** `cw20::Cw20ExecuteMsg::Send { contract, msg, .. }` invokes the recipient contract's `Cw20ReceiveMsg` handler; if the sender contract hasn't committed state, the receive handler can re-enter.
- **FP:** Sender commits state before `Send`, OR `Storage::Item<bool>` guard checked at start of every entry point.

**V27. ECDSA without low-S normalization**

- **D:** Signature verification with `secp256k1` accepts both s and (n-s); attacker normalizes a valid signature to its complement and resubmits — replay-as-distinct-signature.
- **FP:** Enforce `s < n/2` after verify; reject high-S signatures.

**V28. Domain separation missing — same key for two purposes**

- **D:** A single signing key is used for both governance votes and bridge messages without per-purpose domain bytes. Sign-once-replay-twice.
- **FP:** Per-purpose domain prefix in the signed bytes (`b"vote:" | proposal_id | ...` vs `b"bridge:" | ...`).

**V29. `unsafe impl Send for X` with non-Send fields**

- **D:** `unsafe impl Send for X {}` where X holds `Rc<T>` / non-Send raw pointers / interior `RefCell` — data races / UB in async or multi-threaded callers.
- **FP:** Remove the `unsafe impl`; let auto-trait determine. If actually safe, document why with a comment citing the invariant that holds.

**V30. Lock ordering deadlock**

- **D:** Code path 1 acquires `Arc<Mutex<A>>` then `Arc<Mutex<B>>`; code path 2 acquires B then A. Both paths reachable concurrently → deadlock.
- **FP:** Single global lock-acquisition order; or a single combined `Mutex<(A, B)>`.

**V31. Async cancellation safety**

- **D:** `async fn` holds an invariant across `.await` (e.g., partial state update). Future is dropped mid-await — invariant left broken (lock not released, resource leaked, accounting half-applied).
- **FP:** Drop guards (`scopeguard::defer!`); `tokio::select!` with explicit cancellation handling; structured concurrency where cancellation = full rollback.

**V32. Mid-operation config mutation**

- **D:** Admin setter (`set_oracle`, `set_fee_receiver`, `change_authority`, `migrate`) is called while a multi-step operation is in flight. Operation reads stale or unexpectedly-new config.
- **FP:** Snapshot config at operation start; or pause critical operations during config changes.

**V33. SPL delegate authority residual**

- **D:** User SPL `delegate` to program for unlimited approval; program is later replaced via `program_upgrade` but old approvals are still valid for the new program.
- **FP:** Limited per-call delegations only; or migration path that revokes delegates as part of upgrade.

**V34. State-machine togglable flag treated as one-shot**

- **D:** Code assumes `state = Active → Closed` is irreversible; but a separate function `unfreeze` flips it back. Path that depends on closed-state being permanent is exploitable.
- **FP:** No reverse-path function; or downstream paths read a sub-state that captures whether the close was final.

**V35. SPL Token-2022 transfer-hook re-entry**

- **D:** Token-2022 mint has a transfer hook that invokes an arbitrary program on every transfer. Code does not anticipate the hook — transfer triggers attacker-controlled program → re-enters caller.
- **FP:** Token allowlist excluding hook-bearing mints; or full re-entry guard around any transfer to a Token-2022 mint with extensions.

**V36. Mismatched discount paths in liquidation**

- **D:** Lending protocol calculates debt at face value in one path, applies liquidation discount in another. Mismatch causes underflow or leaves residual bad debt unaccounted. Common in Anchor / CosmWasm lending where multiple instructions touch debt state.
- **FP:** Discount applied consistently across all liquidation paths. Single source of truth for discounted value (a shared internal helper).

**V37. Merkle proof not bound to signer / `info.sender` / signed authority**

- **D:** Airdrop / claim verifier uses `merkle::verify(&proof, &root, &leaf)` where `leaf` is `hash(amount)` only — not bound to the claimant. Anyone copying the proof from chain / mempool can claim from a different address.
- **FP:** Leaf encodes the claimant: `hash(claimant_pubkey | amount)` or `hash(info.sender.as_bytes() | amount)`. Mark proof consumed after first use (`Item<bool>` per leaf, or an Anchor PDA flag account).

**V38. Live-supply quorum (Substrate / governance)**

- **D:** Quorum = `total_issuance() * quorum_pct / 100` reads current `pallet-balances::TotalIssuance`. Attacker mints / borrows tokens after proposal creation, lowering effective quorum percentage and pushing through a malicious proposal.
- **FP:** Quorum snapshotted at proposal creation. Or fixed absolute quorum. Substrate `pallet-democracy` snapshots; verify custom governance pallets do the same.

**V39. CosmWasm migrate removes the migrate capability**

- **D:** New contract version's `migrate` handler is empty / accepts but does not preserve the admin authority. Contract becomes permanently locked at the new version with no future upgrade path. Can be intentional; can also be a bug.
- **FP:** `migrate` validates that the new version preserves the admin's ability to migrate again (or the team explicitly intends to lock — doc comments must say so).

**V40. Anchor `init` front-run on shared PDA**

- **D:** Two distinct paths can `init` the same PDA (different instruction handlers, or `init_if_needed` racing with explicit `init`). First initializer sets attacker-controlled state; second path reads stale state believing it is fresh.
- **FP:** Single canonical init path; explicit `require!(account.is_initialized == false)` before initializing; PDA seeds bind to a unique-per-init parameter.

**V41. CPI return-data bomb (Solana)**

- **D:** Program calls `solana_program::program::invoke` on a caller-supplied program ID. Target program returns a huge return-data buffer. The caller's CU budget is exhausted parsing / copying it.
- **FP:** Hardcoded target program ID; or explicit `solana_program::program::set_return_data` size cap; or `get_return_data` with bounded copy.

**V42. CosmWasm submessage push-payment DoS in batch**

- **D:** Loop sends `BankMsg::Send` to a list of recipients via submessages. One reverting recipient (frozen, paused-token, malicious receiver) reverts the whole tx. All other recipients lose their distribution.
- **FP:** Pull-payment pattern (each recipient withdraws individually); or `SubMsg::reply_on(ReplyOn::Always)` with `reply` handler skipping failures.

**V43. Solana flash-loan callback missing caller / initiator validation**

- **D:** Two independent checks, BOTH required:
  (a) `flash_loan_receive` callback does not validate `accounts.lender == known_pool_program_id`. Attacker calls callback directly without a real flash loan.
  (b) Callback does not validate `initiator == self_program_id` or the borrowed token / amount. Attacker triggers a real flash loan from the pool but with crafted parameters to hijack the callback logic.
- **FP:** Both (a) and (b) present. Standard Solend / Mango / Mars flash-loan callback patterns enforce these.

**V44. Nonce not incremented on reverted execution (meta-tx)**

- **D:** Solana / CosmWasm meta-tx pattern checks signed nonce, executes inner call, increments nonce only on success. Reverted inner call leaves nonce unchanged — same signed message replayable until it succeeds (or until nonce expires).
- **FP:** Nonce incremented before inner call (CEI). Or incremented in both success and failure paths. Deadline-based expiry.

**V45. Read-only reentrancy via `query` / view function**

- **D:** Protocol A queries a `view` / `query` function on protocol B (e.g., `Pool::get_virtual_price`, `Vault::convert_to_assets`) from within a callback when B's state is mid-update. The query returns a transitional / manipulated value and A makes a decision based on it.
- **FP:** Protected `view` / `query` with a re-entry guard storage flag. Or A reads from an oracle / cached value, not B's live state. Or A's interaction with B is fully synchronized.

**V46. Withdrawal queue blocked by zeroed / cancelled entry**

- **D:** FIFO withdrawal queue (Solana validator unstake, Anchor vault withdraw queue, Substrate `pallet-staking` unbonding) hits a cancelled / zeroed entry that causes `break` or revert instead of `continue` — permanently blocking all subsequent withdrawals.
- **FP:** Queue iteration skips zero-amount / cancelled entries. Cancellation removes the entry instead of zeroing it. Linked-list structure allows mid-queue removal.

**V47. Same-block vote-transfer-vote (Substrate / governance)**

- **D:** Governance reads voting power at current block (`Balances::free_balance(who)`). User votes from address A, transfers tokens to address B in the same block, votes again from B. Voting power counted twice.
- **FP:** Snapshot voting power at proposal creation block (`pallet-democracy::ReferendumInfo`). Or lock tokens for the voting period.

**V48. Self-delegation doubles voting power**

- **D:** Substrate `pallet-democracy` / custom delegation: self-delegation adds the delegator's votes to the delegate (self) without subtracting the un-delegated direct balance — power counted twice.
- **FP:** Delegation subtracts from the holder's direct balance (or self-delegation is a no-op). Standard `pallet-conviction-voting` handles this.

**V49. Expired oracle silently returns last valid price**

- **D:** Pyth / Switchboard / Band wrapper code: when the requested update is expired or unfulfilled, the wrapper returns the last cached price instead of erroring. Pending orders / liquidations execute at stale prices.
- **FP:** Expired oracle returns `Err(StalePrice)`, forcing the caller to revert or queue. Per-call staleness threshold. Fallback oracle.

**V50. Insufficient confirmations / reorg double-mint (bridge)**

- **D:** Cross-chain bridge / IBC relayer credits destination after N source-chain confirmations where N is below the source chain's known reorg depth. Attacker deposits on source, gets minted on destination, then triggers / waits for a reorg on source that reverses the deposit.
- **FP:** Confirmation count meets or exceeds source chain's finality guarantees (e.g., post-Merge Ethereum 12 min, Polygon 32+ blocks). Or bridge waits for finalized blocks per the source chain's finality definition.

**V51. Algorithmic-complexity DoS (CU / weight exhaustion)**

- **D:** Function loops / recursion / nested matching has superlinear complexity (O(n²), O(2ⁿ)) in attacker-controlled input length. At production scale, execution exceeds Solana CU budget (200k per ix) / Substrate weight budget / CosmWasm gas budget — bricks the function.
- **FP:** O(n) or O(n log n). Input capped (`require!(n <= MAX)` benchmarked against CU/weight). Computation paginated across multiple instructions / extrinsics. Off-chain computation with on-chain verification.

**V52. Profit tracking underflow blocks withdrawals**

- **D:** Vault tracks cumulative profit as `u64` / `u128`. Strategy loss exceeding recorded profit causes `total_profit -= loss` to underflow → panic in debug, silent wrap in release. Either way, withdrawals are bricked or accounting is corrupted.
- **FP:** `total_profit.checked_sub(loss)` with explicit handling. Or signed `i128` for net profit. Or per-strategy tracking.

**V53. Pause modifier blocks liquidation**

- **D:** A `whenNotPaused`-equivalent check is applied to all entry points including `liquidate`. During a pause (often triggered by an oracle issue, the very situation requiring liquidation), interest accrues and prices move but positions can't be liquidated. Bad debt accumulates.
- **FP:** `liquidate` exempt from pause. Separate `liquidations_paused` flag with its own admin authority. Interest accrual also paused so the position state freezes at pause-start.

**V54. Permissionless `accrue_interest` griefing**

- **D:** Permissionless `accrue_interest` callable at short intervals — each computes zero interest (rounding) but advances `last_accrual_time`. Attacker spams to systematically suppress interest accumulation.
- **FP:** Minimum accrual interval enforced (`require!(now >= last_accrual + MIN_INTERVAL)`). Precision sufficient that per-block interest > 0 at realistic rates. Or restrict to a keeper role.

**V55. MEV withdrawal before bad-debt socialization**

- **D:** External event (liquidation, oracle update, depeg) causes vault loss. MEV searcher observes pending loss-causing tx (Solana: Jito bundle visibility; Cosmos: priority gas) and front-runs a withdrawal at pre-loss share price. Remaining depositors absorb the full loss.
- **FP:** Withdrawals require time-delayed request queue (epoch-based or cooldown). Loss realization and share-price update are atomic. Private mempool / Jito-bundle-only path for loss-realizing operations.

**V56. Self-liquidation profit extraction**

- **D:** Borrower liquidates their own undercollateralized position from a second wallet, collecting the liquidation bonus on their own collateral. Profitable whenever `liquidation_bonus_pct > undercollateralization_pct` plus gas / CU.
- **FP:** `require!(liquidator != borrower)` (and the same for any of borrower's known associated accounts). Or liquidation penalty exceeds any collateral bonus.

**V57. Borrower front-runs liquidation with minimal repayment**

- **D:** Borrower observes pending `liquidate` in mempool / Jito bundle, front-runs with a tiny repayment / collateral top-up that pushes health just above threshold. Liquidator's tx reverts. Borrower repeats indefinitely; bad-debt-bound positions are never liquidated.
- **FP:** Cooldown after any borrower-initiated health-affecting action (no liquidate immediately after own deposit). Dutch-auction liquidation. Flash-loan-resistant health check (excludes same-block deposits).

**V58. Empty swap-data path bypasses input-token validation**

- **D:** Routing contract: `if swap_data.is_empty() { return Ok(amount_in) }` — function returns the input amount without swapping AND without validating that `input_token == output_token`. Attacker passes empty swap data with `input_token = cheap` and `output_token = valuable` to drain the contract's balance of valuable tokens.
- **FP:** Empty path enforces `require!(input_token == output_token)`. Or empty path reverts. Or post-swap balance-delta check on the output token.

**V59. State-record overwrite without existence check**

- **D:** Mapping entry (refund record, withdrawal request, pending order) written without checking if the key is occupied. `records[key] = new_data` clobbers an existing record. In Anchor: `account.field = new_value` without checking the field is uninitialized; in CosmWasm: `MAP.save(deps.storage, &key, &v)` without a prior `MAP.may_load`.
- **FP:** Existence check before write (`require!(map.may_load(&key)?.is_none())`). Or nonce/hash-based keys that prevent collision. Or append-only structure.

**V60. Cross-chain supply-invariant violation**

- **D:** Wormhole / LayerZero / IBC peer pair: `total_locked_source` should equal `total_minted_destination`. Bug allows minting without locking — `_credit` callable without a corresponding `_debit`, decimal-conversion error between chains, race in multi-chain deployment, or unauthorized peer setting. Minted tokens become partially or fully unbacked.
- **FP:** `_credit` only callable from the verified `lzReceive` / IBC packet handler. Decimal conversion tested across all supported chains. Per-window rate limit caps maximum exposure. Peer addresses verified against a known deployment registry.

**V61. Majority / quorum threshold off-by-one (`div_ceil` vs strict-majority)**

- **D:** Threshold computed as `n.div_ceil(2)` or `(n + 1) / 2` to obtain "majority." For odd N this happens to equal `(N/2)+1` (correct strict majority), but for **even N** it equals `N/2` — exactly 50%, not strict majority. A 4-node consensus where 2 nodes agree passes the threshold; the protocol's "majority" guarantee is broken. Pattern: `let majority_threshold = v0_records.len().div_ceil(2);`. Most-frequently appears in M-of-N consensus reconstruction, governance quorum calculation, multi-sig threshold, validator-set majority checks.
- **FP:** `let majority_threshold = (n / 2) + 1;` — strict majority for any N. Or `let strict_majority = n.checked_div(2).and_then(|h| h.checked_add(1)).ok_or(...)?;` for overflow-safe.
- **Fix:** Replace every `div_ceil(2)` used as a "majority" calculation with `(n / 2) + 1`. Search the codebase for `div_ceil` near words like "majority", "quorum", "threshold", "consensus" — weaponize across every site.

**V62. Cryptographic / consensus primitive accepts degenerate parameter (`threshold = 0`, `count = 0`, `n = 0`)**

- **D:** Function accepts a parameter that should be ≥ 1 (Shamir threshold, polynomial degree, signer count, share count) and silently produces degenerate output when the parameter is 0 — typically a constant secret, an empty share list, or a function that always succeeds. Pattern: `if t == 0 { return (Fr::ZERO, vec![]); }` for SSS share. Caller-controlled `t` (or `t` derived from doc-stated default of zero) leaves the primitive trivially recoverable. Often appears in initial-account-state generation where the developer set `threshold = 0` to defer the actual sharing for later — but the on-chain artifact ships with the degenerate state visible to anyone.
- **FP:** Function rejects `t == 0` (or `n == 0`) with `Err(InvalidParameter)`. Public API enforces `threshold ≥ 1` at every call-site. Initial-state generation uses `threshold = 1` (intentionally unrecoverable) rather than `threshold = 0` (trivially recoverable).
- **Fix:** Audit every cryptographic / threshold-setting primitive for the degenerate-input branch. If the branch exists, ensure the public-API caller cannot reach it with `0`. If degenerate state must ship in initial artifacts, use `threshold = 1` so the artifact is unrecoverable rather than trivially-derivable.

**V63. Unbounded `Vec<T>` storage with attacker-controllable length and per-element cost**

- **D:** A storage field declared as `Vec<T>` (or `BTreeMap<K, V>`, `HashMap<K, V>`) with no `MAX_*` cap, where (a) at least one append/insert is reachable from a public entry point, (b) the field's length is consumed by a hot-path linear scan elsewhere (signature verification loop, decryption attempt loop, recovery initiation, etc.). Pattern: `pub assoc: Vec<AssociationsV0>` declared without a cap; `add_association` appends without a length check; `initiate_recovery` linear-scans `self.assoc.iter().find_map(|a| ...).ok_or(...)` doing a full decryption per element. Attacker (or compromised owner) inflates the Vec to `n` elements, making every recovery initiation O(n) cryptographic operations → block-author DoS / CU exhaustion / weight-budget overrun.
- **FP:** Storage field has a documented `MAX_*` cap. Append-side validates `current_len < MAX_*` and rejects with `Err(TooMany*)`. Read-side that linear-scans is either O(log n) via indexed lookup (`HashMap<key, value>`) or paginated.
- **Fix:** Add `pub const MAX_<FIELD>: usize = N;`. Reject appends past cap. If the field's natural access pattern is keyed lookup, replace `Vec<T>` with `HashMap<Key, T>` or require callers to pass the index.

**V64. Anchor `close` constraint without beneficiary signer check**

- **D:** `#[account(close = beneficiary)]` redirects an account's lamports to `beneficiary` on close, but `beneficiary` is `AccountInfo` / `UncheckedAccount` rather than a `Signer<'info>` and no `has_one`/address-equality guard ties it to a known authority. Attacker passes their own pubkey as `beneficiary` and drains the closed account's rent-exempt balance.
- **FP:** `beneficiary: Signer<'info>`, OR `#[account(..., has_one = beneficiary)]` linking to authority field, OR explicit `beneficiary.key() == known_addr` check.

**V65. `realloc` without post-realloc length validation**

- **D:** Anchor `account.realloc(new_size, zero_init)` or solana_program `AccountInfo::realloc(...)` called with attacker-influenced `new_size`. Subsequent code writes assuming a specific layout but the post-realloc `data.len()` is not re-validated. Either out-of-bounds write or trusted-layout assumption broken on shrink.
- **FP:** After every `realloc`, `require!(account.data_len() == EXPECTED, ...)` or recompute layout offsets from `account.data_len()`.

**V66. `try_borrow_mut_data()` aliasing via `remaining_accounts`**

- **D:** Handler iterates `ctx.remaining_accounts` and calls `account.try_borrow_mut_data()` on multiple accounts simultaneously, assuming each refers to a distinct account. Solana does not enforce uniqueness on `remaining_accounts` — attacker passes the same `AccountInfo` twice; `try_borrow_mut_data` returns Err on the second borrow OR (if the runtime allows aliasing) two `RefMut`s point at the same buffer and writes are corrupted.
- **FP:** Deduplicate `remaining_accounts` by pubkey before borrowing, OR require all writes to land on a single primary account, OR validate `accounts.iter().map(|a| a.key()).collect::<HashSet<_>>().len() == accounts.len()`.

**V67. Upgradeable proxy `program_upgrade_authority` not validated**

- **D:** Program is deployed as upgradeable (`solana program deploy --program-id ...`). The protocol's "implementation pointer" pattern stores a target program ID in PDA state and dispatches user instructions to it via CPI. The dispatch path does not verify the target program's `program_upgrade_authority` matches the protocol's expected authority — a malicious upgrade of the implementation steals funds.
- **FP:** On every dispatch, `require!(BpfLoaderUpgradeable::program_data(target).upgrade_authority_address == EXPECTED)`, OR pin the target program's data account hash, OR pin to a non-upgradeable program ID.

**V68. SPL Token-2022 transfer-fee not subtracted from received-amount accounting**

- **D:** Mint with `TransferFeeConfig` extension. Code transfers `amount` and credits the recipient with `amount` in internal accounting (`user.balance += amount`). The actual amount that arrives is `amount − fee`. Internal `total_supply` / per-user balance drifts above real token balance; eventual withdrawals fail with insolvency.
- **FP:** `let pre = recipient_token_account.amount; transfer(...)?; recipient_token_account.reload()?; let actual = recipient_token_account.amount - pre; user.balance += actual;`. Or refuse mints with `TransferFeeConfig` extension if not designed to handle them.

**V69. CosmWasm reply handler not validating `msg.id`**

- **D:** Contract emits multiple submessages with `SubMsg::reply_on_*` and ID tags (`SubMsg::reply_on_success(msg, REPLY_ID_A)` and `... REPLY_ID_B`). The `reply` entry-point matches on `msg.result` but not on `msg.id` — a reply intended for handler A is processed as if for handler B (or vice versa). State written for A is overwritten or tagged incorrectly.
- **FP:** `match msg.id { REPLY_ID_A => handle_a(deps, msg), REPLY_ID_B => handle_b(deps, msg), _ => Err(ContractError::UnknownReplyId) }` with explicit panic / error on unknown IDs.

**V70. IBC packet timeout handler missing or trivial**

- **D:** Contract sends ICS-20 / generic IBC packets via `IbcMsg::SendPacket` but `ibc_packet_timeout` entry point is missing or only logs without restoring state. A packet that times out (counterparty offline, channel closed) leaves locked funds permanently inaccessible — sender's balance was debited, no rollback path.
- **FP:** `ibc_packet_timeout` mirrors `ibc_packet_ack` with reverse semantics: refund the sender, restore state. Symmetric with the success path.

**V71. CosmWasm `sudo` callable via raw entry-point bypass**

- **D:** Contract exposes a `sudo(deps, env, msg: SudoMsg)` entry-point intended for chain-governance-only invocation. The same logic is *also* reachable via `execute(SudoMsg::Privileged{..})` because the ExecuteMsg enum was extended without restricting the new variant — any caller can invoke the sudo path.
- **FP:** Privileged actions only in `sudo` (Cosmos SDK enforces caller is governance for `sudo`). Audit ExecuteMsg variants for any that should be `sudo`-only and remove them from the public enum.

**V72. CW20 Send/Receive callback recursion not rate-limited**

- **D:** Token contract A's `Receive` handler invokes contract B; B's logic sends back to A via `Send`; A's `Receive` runs again. Distinct from V26 (which is single-step re-entry); V72 is *unbounded recursion* depth limited only by gas. Combined with a low per-invocation gas cost and a 1.0 callback ratio, the recursion exhausts block gas — block-author DoS or full tx revert leaving partial state.
- **FP:** Per-tx recursion-depth counter in storage (`Item<u8>`); reject when depth > threshold (typically 1 or 2). Or migrate to pull-payment / queue-based settlement.

**V73. CosmWasm `migrate` accepting unsafe migrations resetting params**

- **D:** `migrate(deps, env, msg: MigrateMsg)` accepts a `MigrateMsg` whose fields rewrite contract config (`admin`, `oracle`, `fee_recipient`, `pause_state`). No validation that the new config is consistent with on-chain state OR matches the team's intended migration. A compromised admin (or wrong-version migrate) silently swaps these to attacker-controlled values.
- **FP:** Migrate validates each field against an allowlist OR requires `MigrateMsg::version` to match a hard-coded current-version constant. Or migrate is a no-op stub and config changes go through a separate timelocked flow.

**V74. Substrate `ValidateUnsigned` not enforced on unsigned tx**

- **D:** Pallet defines an unsigned extrinsic via `#[pallet::call] pub fn submit_unsigned(...)`. The `impl ValidateUnsigned` block is missing OR only checks signature presence (always true for `Origin::None`) — node forwards arbitrary unsigned txs as valid. Attacker spams the mempool with no cost.
- **FP:** `impl ValidateUnsigned for Pallet<T>` with proper `validate_unsigned` returning `Err(InvalidTransaction::Call)` for any unauthorized payload, AND `pre_dispatch` enforcing the same checks.

**V75. Substrate `offchain_worker` fetching attacker-controlled URL into signed payload**

- **D:** `fn offchain_worker(_block: BlockNumberFor<T>)` fetches data via `sp_runtime::offchain::http::Request::get(url)` where `url` is read from on-chain storage (and storage is settable by anyone via a permissionless extrinsic). Attacker sets URL to an attacker-controlled endpoint. The OCW signs the response and submits a transaction — node signs attacker-controlled data with the validator's offchain key.
- **FP:** OCW URL is a hard-coded constant OR governance-gated. Response is validated against an on-chain commitment / merkle root before signing.

**V76. Substrate storage proof not verified against block header**

- **D:** Bridge / light-client pallet accepts a `(state_root, key, proof, value)` quadruple via extrinsic and verifies `proof` against `state_root` — but does NOT verify that `state_root` is the legitimate state root of any block on the canonical source chain. Attacker provides a self-signed `state_root` and matching proof; the light-client accepts a proof that verifies under arbitrary roots.
- **FP:** `state_root` must be derived from a verified block header (validator signatures over header, finality proof, etc.). Proof verification chain: `block_header → state_root → key/value`.

**V77. `pallet-treasury` double-spend without `proposal_index` tracking**

- **D:** Custom treasury extension's `pay_proposal(origin, proposal_id)` extrinsic transfers the approved amount but does NOT mark `proposal_id` as paid. Same proposal can be paid multiple times until governance revokes it.
- **FP:** `Storage::Paid: Map<ProposalIndex, ()>` checked-and-set atomically. Or remove the proposal from `Approvals` storage when paid.

**V78. Substrate `on_initialize` weight annotation mismatch with actual work**

- **D:** `#[pallet::hooks] fn on_initialize(_: BlockNumberFor<T>) -> Weight` is annotated `Weight::from_parts(10_000, 0)` (constant) but iterates a `StorageMap` whose size grows without bound. Block-author executes the work without paying real weight; eventually one block's actual work exceeds `BlockWeights::max_block` and the chain stalls.
- **FP:** Weight annotation must reflect worst-case work. For unbounded iteration, move work to `on_idle` (which has explicit weight budget) or paginate via cursor stored in `StorageValue`.

**V79. `unsafe` reading `*const T` from `Vec<u8>` without bounds check**

- **D:** Code uses `unsafe { std::ptr::read_unaligned(bytes.as_ptr() as *const MyStruct) }` where `MyStruct` is larger than `bytes.len()`. Out-of-bounds read of adjacent memory; on Solana BPF this can cross account-data boundaries and leak adjacent account state.
- **FP:** `if bytes.len() < size_of::<MyStruct>() { return Err(...) }` before any unsafe read. Prefer `bytemuck::try_from_bytes` (does the check) or `borsh::BorshDeserialize` (length-aware).

**V80. `unsafe transmute` between types with different alignment**

- **D:** `unsafe { std::mem::transmute::<&[u8; 32], &MyAlignedStruct>(buf) }` where `MyAlignedStruct` requires alignment 8 but `buf`'s underlying allocation has alignment 1. Behavior is UB; in release builds this typically reads garbage; in debug builds with `cfg(debug_assertions)` it may abort.
- **FP:** `bytemuck::Pod` / `bytemuck::AnyBitPattern` derives + `bytemuck::cast_slice` (does alignment check). Or copy bytes into a stack-allocated `MyAlignedStruct` via `core::ptr::read_unaligned`.

**V81. `serde` deserialize without `deny_unknown_fields` trusting attacker-controlled fields**

- **D:** `#[derive(Deserialize)] struct Request { action: String, amount: u64 }` accepts JSON / msgpack payloads. Attacker includes additional fields the struct doesn't list. Without `#[serde(deny_unknown_fields)]`, serde silently drops them. If the protocol's contract is "what you sign is what executes" (signature over a JSON canonicalization), the attacker's extra fields are signed-but-not-enforced — semantic ambiguity bug.
- **FP:** `#[serde(deny_unknown_fields)]` on all deserialize-from-untrusted structs. Or canonical-form re-serialization-and-comparison after deserialize.

**V82. `HashMap` iteration-order dependence in deterministic state transitions**

- **D:** On-chain state transition iterates a `HashMap` (`for (k, v) in map.iter() { state.apply(k, v) }`). Rust's `HashMap` iteration order depends on insertion order AND the (random) hasher seed. In a deterministic context (consensus, multi-validator agreement), validators with different seeds compute different state transitions — chain split.
- **FP:** Use `BTreeMap` (deterministic ordering by `Ord`) for any state-affecting iteration. Or sort the keys explicitly: `let mut keys: Vec<_> = map.keys().collect(); keys.sort();`.

**V83. `Ord`/`PartialOrd` inconsistent with `Eq` breaking `BTreeMap` ordering**

- **D:** Custom struct's `impl Ord` returns `Ordering::Equal` for distinct values that `Eq` says are unequal (or vice versa). `BTreeMap<MyKey, V>` may then store distinct keys at the same logical position OR fail to find an inserted key. Used as a state map → silent collision / "lost" entries.
- **FP:** `#[derive(Ord, PartialOrd, Eq, PartialEq)]` whenever possible. If hand-implementing, ensure `a == b ⇔ a.cmp(b) == Ordering::Equal` and that `Ord` is total.

**V84. `assert!` instead of `require!` in Solana BPF / Substrate dispatchable**

- **D:** Solana BPF code uses `assert!(invariant)` inside an instruction handler. On BPF, `assert!` panics; the panic is caught by the runtime and turns into a `ProgramError::Custom(0)` — but the surrounding tx may still succeed if the panicking function was speculatively called (e.g., during account introspection that the runtime tolerates). On Substrate dispatchables, `assert!` panics the runtime — entire block fails, validators slashed for invalid block.
- **FP:** `require!(invariant, AppError::SomeError)` (Anchor) / `ensure!(invariant, AppError::SomeError)` (CosmWasm / Substrate). Never `assert!` / `unwrap()` / `panic!` in handler code paths.

**V85. Missing `#[repr(C)]` / `#[repr(packed)]` in FFI-shared structs**

- **D:** A struct passed across FFI boundaries (Solana program ↔ host runtime, Substrate Wasm runtime ↔ native, CosmWasm Wasm ↔ chain host) is declared `#[repr(Rust)]` (the default). Rust does not guarantee field ordering or padding for `repr(Rust)` — different compiler versions or targets may lay out the struct differently. Caller and callee disagree on layout → silent field-corruption.
- **FP:** `#[repr(C)]` for FFI-shared structs (stable C-ABI layout). `#[repr(packed)]` only when alignment-1 is required and you've audited every read path for misaligned-access UB.

**V86. Unbounded mapping iteration callable from public entry (V63 extension)**

- **D:** Companion to V63. A `Map<K, V>` (CosmWasm `cw_storage_plus::Map`) or `BTreeMap` is iterated inside a public-entry handler: `MAP.range(deps.storage, None, None, Order::Ascending).collect::<Result<Vec<_>, _>>()?`. Attacker has any control over Map size (permissionless inserter) → handler's gas cost grows linearly with attacker insertions → block DoS / handler bricked at scale.
- **FP:** Paginate (`MAP.range(..).take(LIMIT)`) and accept a cursor parameter. Or maintain an indexed lookup so iteration is unnecessary.

**V87. Cumulative-growth `Vec` across multiple txs (each bounded; collectively unbounded)**

- **D:** Per-tx push enforces `require!(self.entries.len() < MAX_PER_TX, ...)` but no cap on `self.entries.len()` *after* multiple txs. A patient attacker submits N txs each pushing `MAX_PER_TX − current_len` entries → cumulative `entries.len()` is unbounded. Hot-path consumer (V63-style linear scan) bricks.
- **FP:** Cap on absolute container size, not per-tx. `require!(self.entries.len() + new_count <= MAX_TOTAL, ...)`.

**V88. Accumulator with attacker-controlled granularity overflow**

- **D:** A counter / running total has its update granularity set by an attacker-controllable parameter. Pattern: `pub fn set_rate(rate: u64) { self.rate_per_second = rate }` (no upper bound) followed by `self.cumulative += self.rate_per_second * elapsed`. Attacker sets `rate = u64::MAX`; first tick overflows `cumulative` (silent wrap on Solana BPF release builds; panic in debug).
- **FP:** Bound `rate` at `set` time (`require!(rate <= MAX_RATE, ...)`). Use `checked_mul` / `checked_add` in the update path. Use `i128` / `u128` if the natural rate × elapsed product is large.

**V89. Concentrated-liquidity tick-spacing manipulation post pool creation**

- **D:** AMM pool created with `tick_spacing = T`. The protocol later allows the *creator* (or governance with timelock) to change `tick_spacing` — but existing positions encoded in the old spacing aren't migrated. After a tick-spacing change, in-range checks and fee accounting reference the new spacing while position metadata uses the old. LPs withdraw with corrupted balances.
- **FP:** `tick_spacing` is immutable post pool creation. Or migration explicitly re-tick-binds all positions atomically.

**V90. Fee-on-transfer token interaction silently breaking constant-product**

- **D:** AMM accepts an SPL Token-2022 mint with `TransferFeeConfig` (or CW20 with hooks that reduce delivered amount). Pool's `add_liquidity(amount_in)` records `pool.reserve += amount_in` — but actual received is `amount_in − fee`. Constant-product invariant `x * y = k` no longer holds: `k` jumps after every FoT-token deposit. Subsequent swaps trade against an inflated reserve that doesn't exist.
- **FP:** Refuse FoT tokens in pool whitelist, OR `pool.reserve += (post_balance − pre_balance)`, OR maintain a `phantom_reserve` separate from `actual_reserve`.

**V91. Validator-set update race with finalized in-flight deposit**

- **D:** Bridge's source-chain finality module updates the validator set at block N. A user's deposit, whose proof references validator set N−1, is in flight (relayer hasn't yet relayed). The destination-chain verification rejects the proof because it now expects set N's signatures; the deposit is locked on source but unmintable on destination. OR the reverse: destination accepts set N−1 signatures because it hasn't updated yet — attacker-controlled set N−1 keys (e.g., recently-rotated-out validators that turned malicious) forge messages.
- **FP:** Each finality message carries the validator-set-version it belongs to; verification accepts ANY recently-active set within the rotation grace window. Source chain commits to "deposit was made under set version V" in the deposit log.

**V92. Vote-delegate-vote same-block double-counting**

- **D:** Custom governance: at block B, address A votes (uses voting power P). Same block: A delegates to B (transfers P). Same block: B votes (uses power P + B's own). Voting power P counted twice.
- **FP:** Snapshot voting power at proposal creation block, NOT at vote time. Or lock delegations during active vote periods.

**V93. Liquid-staking exchange-rate front-run during reward claim**

- **D:** LST protocol's `claim_rewards()` increments the underlying-staked total before recomputing the exchange rate. Attacker observes `claim_rewards` in the mempool, front-runs with `mint(small_amount)` at the *pre-claim* exchange rate, then back-runs with `redeem(shares)` at the *post-claim* rate — captures a slice of the reward.
- **FP:** Reward distribution and exchange-rate update are atomic (single tx, single state mutation). Or claim is restricted to a permissioned keeper that batches.

**V94. Self-liquidation profit on newly-added collateral with wrong threshold**

- **D:** Lending protocol adds a new collateral asset via `add_collateral_asset(asset, ltv, liquidation_threshold, liquidation_bonus)`. Misconfigured `liquidation_threshold` lower than the LTV at which a position can be opened, OR `liquidation_bonus` exceeds the under-collateralization gap. Attacker self-liquidates from a second wallet at zero risk → free profit.
- **FP:** Invariant: `liquidation_bonus_pct < (1 - 1/liquidation_threshold) - safety_margin`. Validated at `add_collateral_asset` time. `require!(liquidator != borrower)` and check known-associated wallets (multi-wallet attacker counter).

**V95. Governance-token flash-loan vote manipulation (Beanstalk pattern)**

- **D:** Governance reads voting power from current `balanceOf` (or a single-block snapshot taken at proposal CREATION but proposal can be self-created in the same flash-loan tx). Attacker flash-borrows governance tokens, creates a malicious proposal, votes with borrowed power, executes (if no timelock or timelock bypassable), returns the loan — all atomic. Beanstalk lost $182M to this exact pattern.
- **FP:** Voting power snapshotted at a block STRICTLY EARLIER than proposal creation (e.g., `proposal_block - 1`). Proposal creation requires a separate prerequisite tx that flash-loans cannot satisfy. Mandatory non-zero timelock between vote-passes and execute.

**V96. Donate-to-reserves rounding (Euler pattern; distinct from V16)**

- **D:** Lending protocol exposes a `donate(amount)` function intended to socialize losses or boost reserves. The function increases `total_reserves` without minting corresponding shares — but the price-of-share calculation rounds in a way that benefits the donor on subsequent redeem (attacker donates X, then redeems and receives back X plus a slice). Distinct from V16 (zero-rounding theft on fee math) — V96 is round-up on share-price recomputation.
- **FP:** `donate` either burns equivalent shares from the donor OR is permissioned. Round-down on share-price after donate so the donor cannot recapture donated value.

**V97. Global timestamp partial-update across multi-asset oracle data**

- **D:** Oracle stores a single `last_update_ts` field shared across N assets (`prices[asset_id]`). An update path that touches K < N assets writes the new prices but ALSO bumps `last_update_ts` — the N-K untouched assets now appear "fresh" via the global timestamp despite their prices being stale. Stage-1 invariants table lists this as a candidate when a single timestamp gates multiple asset reads. **The C4 M-05 Reflector miss** that v0.1.9 didn't catch.
- **FP:** Per-asset `last_update_ts[asset_id]`. Or staleness check uses both global ts AND a per-asset version-counter bump.

**V98. Verifier accepts proof without binding `vk_root` to caller's expected program-vkey (ZK)**

- **D:** A `verify(proof, public_inputs, vk_hash)` function checks the proof under the supplied `vk_hash` but does NOT verify that `vk_hash` is the caller's expected program-vkey. The caller then trusts the verified output without binding the vk used. An attacker submits a proof verified under their own vk; the protocol accepts it as if it were a proof of the protocol's actual program. **The SP1 M-01 pattern** (Code4rena 2026-04).
- **FP:** Caller passes `expected_vk_root` and the verifier first-line-checks `require!(vk_hash == expected_vk_root, ...)` before invoking the proof check. Or the verifier's signature is `verify(proof, expected_vk_root, public_inputs)` where the expected vk is unconditionally bound.

**V99. Public API deserializer panics on truncated / malformed input (verifier-class)**

- **D:** `pub fn verify_public_values(input: &[u8])` (or any `pub fn` accepting untrusted byte input) accesses `input[i]` / slices via index without first checking `input.len() >= required_len`. Truncated input → slice panic / OOB / unwrap propagates → tx-level panic. Bug-bounty-eligible whenever the protocol's in-scope-impacts list includes "Undocumented panic reachable from a public API". **The SP1 M-02 / M-04 pattern** (Code4rena 2026-04).
- **FP:** Length validation on the very first line: `if input.len() < EXPECTED { return Err(InvalidInput); }`. Or use a length-aware decoder (`borsh::BorshDeserialize`, length-prefixed Borsh, or a custom decoder that returns Err on underflow).

**V100. State-split / partition / pack function panics or livelocks on degenerate options**

- **D:** A `split(opts: SplitOpts)` / `partition(buckets: usize)` / `pack(events: &[T])` / `flatten(layers: usize)` function reachable from a public API has unhandled degenerate cases: zero options (`SplitOpts::default()` with all-zero fields), zero buckets, empty input, max-input. Default-construction triggers infinite loop, division-by-zero, slice OOB, or nonce-clobber. **The SP1 M-03 / M-06 pattern** (Code4rena 2026-04).
- **FP:** Reject degenerate inputs at function entry: `require!(opts.is_valid(), ...)`, `require!(buckets > 0, ...)`. Or document the degenerate case as a no-op (return Ok(empty)) with a test asserting it.

**V101. Documented fallback / alternative path that is unreachable due to caller early-return**

- **D:** A function (often a verifier helper) is documented as supporting an alternative algorithm / hash / config (e.g., "PLONK accepts both Groth16 and Blake3 hashes via fallback in `verify_public_values`"). Reading the function in isolation confirms the fallback exists. But the CALLER chain has an early-return that blocks the fallback: every caller of `verify_public_values` is `verify_plonk_bn254` (which returns Err if `!vkey.is_plonk()`) or `verify_groth16_bn254` (returns Err if `!vkey.is_groth16()`). The fallback branch is dead code — yet the docs claim it's active. The bug is the documentation, not the code (or, equivalently, the bug is the caller's early-return when documentation promised the fallback). **The SP1 M-05 pattern** (Code4rena 2026-04). Distinct from V101's reverse: the bug here is that the documented behavior is BLOCKED, not that an unintended path is reachable.
- **FP:** Either (a) document the fallback as not-yet-reachable / planned-but-not-implemented, or (b) remove the caller's early-return so the fallback IS active. Argus must trace the caller chain UP from the supposed-active branch to detect this case.

**V102. Cost / weight / opcode table mismatch — sibling-opcode-derived cost**

- **D:** A cost table maps opcodes to per-execution costs (CU on Solana, weight on Substrate, gas on EVM-equivalents). Some entries are missing and silently defaulted to a sibling opcode's cost. Example: `Opcode::cost(StoreDouble)` returns the same as `Opcode::cost(StoreWord)`, even though `StoreDouble` does 2× the work. Under-charged execution → block-author DoS (running unpaid work) or under-paying gas / weight. **The SP1 QA pattern** (Code4rena 2026-04).
- **FP:** Cost table is exhaustive: every reachable opcode has its own cost row. Or `match` is total with `_ => unimplemented!()` triggering a hard fail rather than a silent sibling-derived default.

---

## v0.2.0 expansion — V103-V123 (calibrated against 4-stream external research)

**V103. Asset-identity / cross-instruction-id binding missing (Solana, cross-program)**

- **D:** A multi-instruction operation (deposit + withdraw, borrow + repay, swap + settle) treats independent accounts/identities as if they were the same logical entity, but the program does not enforce that the two sides reference the same `key()` or PDA seed. Attacker triggers the second instruction with a different identity than the first. Pattern: `random_account_as_id` or `position_account.key()` checked at one instruction but not at its pair. **Solves Lavarage H-01 (swapback `borrow_collateral` vs `repay_sol`), Orderly Solana Vault recipient ID, Pump-Science 2-step migration.** Codex V103 + Claude Web V105.
- **FP:** All cross-instruction references use the same PDA seed OR an explicit `require_keys_eq!(ix1.account.key(), ix2.account.key())` at every cross-ix boundary.

**V104. Underconstrained witness column (ZK)**

- **D:** A circuit advice column is computed in-witness (prover assigns a value) but the verifier circuit has no algebraic constraint binding it. Prover can substitute any value; soundness break. Common: lookup-table results not constrained back to query, intermediate hash outputs not constrained to inputs, hint-cells not constrained to source-cells. Detection: count `cs.constrain` / `assert_eq` / `gate.eval` calls per advice column; column with zero direct constraints is a candidate. **Solves Veridise/Picus SP1 determinism findings, Risc0 ARGUZZ $50k bounty, Codex SP1 H-01 advice-not-bound.** Multi-stream agreement (internal + Codex + Claude Web).
- **FP:** Every advice column has either a direct constraint (e.g., `cs.assert_eq(advice, expected_expression)`) or is a documented public-input column.

**V105. Truncation-by-design rounding (CosmWasm + Solana)**

- **D:** Distinct from V14 (operation-order precision loss) and V15 (wrong rounding direction). V105 is the case where integer division rounds a fee/share/ratio down to **zero** for legitimate small amounts. CosmWasm `Decimal::checked_div` and `checked_div` on `Uint128` truncate; if not paired with a `if result == 0 { result = 1 }` minimum, fees / interest / shares are bypassed for dust amounts. **Solves MANTRA DEX H (0.16% slippage skew), Astroport Incentive duplicate-LP rewards, Marinade mSOL rounding.** Claude Web rec #4.
- **FP:** After every `checked_div` in fee/share math, an explicit `if result == 0 && operands_nonzero { result = 1 }` minimum, OR the calculation rounds in protocol's favor explicitly.

**V106. Fiat-Shamir transcript incomplete (ZK)**

- **D:** A Fiat-Shamir-style hash is invoked to derive a challenge, but not every algebraic component of the proof statement is absorbed into the transcript before the challenge is sampled. Attacker can vary the omitted components and forge proofs valid under multiple statements. **Solves Solana Token-22 ZK ElGamal Proof June-2025 zero-day (Critical, mainnet feature disabled), Halo2-KZG Fiat-Shamir variants, Risc0 ARGUZZ paper bugs.** Claude Web V106 + internal V126.
- **FP:** For every `transcript.append(...)` invocation, cross-reference against the `Proof` struct's fields; ensure every field is absorbed before challenge sampling. Fix: absorb every commitment, public input, and auxiliary group element before `transcript.challenge()`.

**V107. Cost / fee-records-cap mismatch (oracles, ZK, generic)**

- **D:** Distinct from V102 (opcode cost). V107 is user-facing: a function charges a per-unit fee based on `requested_count` but caps the actual returned data at `MIN(requested_count, MAX)`. User pays for N records, gets up to MAX. **Solves Reflector V3 M-01 (charge for N, return capped at 20 = 333% overcharge for N=100), M-04 (twap passes literal 1 instead of `records`), M-03 (load_prices decrements records when `get_price_fn` returns None).** Claude Web rec #1, top-priority lift.
- **FP:** Charge `actual_returned.len()` AFTER load completes, OR cap `records_to_charge = records.min(MAX)` BEFORE charging.

**V108. Lifecycle / state-flag bypass (Coded-Estate-class, CW + generic)**

- **D:** A state-machine flag (`isListed`, `rentalActive`, `disabled`, `paused`, `migrated`) is checked on the "happy path" function but not on a parallel function that mutates the same underlying state. Attacker uses the unguarded path. Distinct from V34 (which is about flag-toggle reversibility); V108 is about INCONSISTENT flag enforcement across siblings. **Solves Coded-Estate H-02 / H-07, Superposition M-08.** Codex V104.
- **FP:** Every public function that depends on the lifecycle invariant checks the flag at entry; `match` on the state enum is exhaustive with `_ => Err(...)`.

**V109. NFT / CW721 approval residue after state change**

- **D:** Token approvals (Solana SPL delegate, NFT operator-approval, CW721 send approval) are not cleared on state transitions where the approved party should no longer have authority: token transfer to a new owner, bid cancellation, listing/sale-state transition. Previous approved party retains transfer authority over an asset they no longer own. Generalizes V33 (SPL delegate residual). **Solves Superposition H-02, Coded-Estate H-05 / H-08.** Codex V105.
- **FP:** Every state transition that changes the asset's owner / state explicitly clears prior approvals.

**V110. User price-bound / slippage / deadline missing (AMM, LP, withdrawal)**

- **D:** Public AMM swap, LP mint/burn, or protocol withdrawal accepts user funds without a user-supplied min-out / max-in / deadline parameter. Attacker (or MEV searcher) sandwiches the call; user receives less than expected with no recourse. **Solves HydraDX M-03, Superposition H-07, Superposition H-03.** Codex V106.
- **FP:** Every value-moving public function accepts and enforces `min_amount_out` (or analogous slippage param) AND a `deadline` timestamp. The function reverts if either is breached.

**V111. Wasm host import resource gap (CosmWasm, generic Wasm)**

- **D:** Wasm runtime exposes host functions (stdout, stderr, import-write, memory-grow) that are NOT metered or capped. Malicious contract floods host buffers / triggers unbounded memory growth on the host. **Solves SEDA H-13 / H-14 / H-16.** Codex V112.
- **FP:** Every host function metered with explicit gas / weight cost AND has an output-size cap. Memory-grow has a per-tx maximum.

**V112. Address validation / normalization missing (CosmWasm)**

- **D:** Cosmos contracts accept `String` fields for addresses but do not pass them through `deps.api.addr_validate` before storage / use. Invalid bech32, mismatched chain prefix, or denormalized form (mixed case) is accepted; later operations on stored addresses fail or misbehave. **Solves Oak Spotlight #3, recurring CW pattern.** Claude Web V111.
- **FP:** Every `String` address field passes through `deps.api.addr_validate(...)?` at message boundary, OR the type is `Addr` (already validated).

**V113. Forgot-to-save state (CosmWasm)**

- **D:** Function loads state from `deps.storage`, mutates the in-memory copy, and returns Ok without calling `.save(deps.storage, &updated_state)`. Mutation is lost. **Solves Oak Spotlight #1 (`update_name` not persisted) and recurring CW pattern.** Claude Web V109.
- **FP:** Every function that loads-and-mutates state calls `.save()` on every Ok return path. Or use an RAII guard that auto-saves on drop.

**V114. Submsg-reply-trust (CosmWasm)**

- **D:** Parent contract sends `SubMsg::reply_on_error` (or `reply_on_*`) to a contract-controlled callee. Malicious callee reverts intentionally; the parent's reply handler treats failure-to-deliver as a bug-state, bricking parent functionality (reward processing, batch settlement). **Solves MANTRA DEX malicious-pool brick.** Claude Web V110.
- **FP:** `reply_on_error` only used for admin-curated callees; for arbitrary-callee paths, use `reply_always` and handle failures gracefully OR allowlist callees.

**V115. Lamport-transfer / rent-exemption edge case (Solana)**

- **D:** Solana program directly compares `account.lamports()` to an internal SOL counter; the lamports include rent-exempt minimum, the internal counter doesn't (or vice versa). Invariant check passes when funds are actually misallocated. **Solves Pump-Science H (sol_escrow_lamports vs real_sol_reserves).** Claude Web V112.
- **FP:** Subtract `Rent::get()?.minimum_balance(account.data_len())` from `account.lamports()` before comparing to internal counter.

**V116. Wrong-slot or ineffective admin config setter**

- **D:** An admin setter function (`set_oracle`, `set_fee_recipient`, `set_param`) writes to a different storage slot than the one the read-side queries. Setter appears to work but state is never updated. Or: setter exposed but missing from the live-critical setter inventory. **Solves Superposition H-01, M-12, Andromeda M-1.** Codex V110.
- **FP:** Every setter writes to the SAME storage slot the reader reads. Test: read-after-write must observe the new value across separate transactions.

**V117. Same-account alias accounting (Solana, Substrate, CosmWasm)**

- **D:** A function accepts two account/role parameters that should be distinct (sender + recipient, borrower + liquidator, depositor + delegator) but does not check `key1 != key2`. Attacker uses the same account as both roles to bypass invariants (self-transfer counts as zero net change but increments a counter, self-liquidation collects bonus on own collateral). **Solves Acala H-01, WOOFi M-3, Orderly H-2.** Codex V118.
- **FP:** Every multi-role function enforces `require!(role_a.key() != role_b.key(), AppError::SameAccountAlias)` at entry.

**V118. Cross-chain withdrawal recipient not bound to verified message**

- **D:** Cross-chain bridge / OApp / IBC handler verifies the source-chain message authenticity but does not bind the verified message's `recipient` field to the destination-side caller's `key()`. Attacker observes a victim's pending withdrawal message, calls the destination handler with their own credentials; funds delivered to attacker. **Solves Orderly Solana Vault H-2, SEDA H-8, Terra IBC-hooks exploit.** Codex V114.
- **FP:** Verifier checks `verified_message.recipient == ctx.accounts.caller.key()` AND consumes the message nonce before the transfer.

**V119. Cross-chain message ordering / idempotency missing**

- **D:** Cross-chain protocol does not enforce ordered delivery of messages AND the receiver is not order-independent / idempotent. Attacker (relayer) reorders or replays messages; receiver applies them in wrong order, corrupting state. **Solves Orderly M-1 / H-2, Terra IBC-hooks variants.** Codex V115.
- **FP:** Either enforce ordered delivery via sequence numbers (rejecting out-of-order), OR design the receiver to be commutative + idempotent (state is per-message-keyed, not sequential).

**V120. Oracle update hook / TWAP desync (AMM, lending)**

- **D:** TWAP (time-weighted average price) or EMA (exponential moving average) is updated only on `swap()` paths but not on `mint()` / `burn()` / direct-transfer paths. State that affects spot price (`reserve`, `liquidity`) changes without TWAP update. Attacker manipulates spot via the un-hooked path; readers observe a stale TWAP that doesn't reflect the manipulation. **Solves HydraDX M-01 / M-07, Loopscale exploit.** Codex V116.
- **FP:** Every state-mutation that affects spot price calls the TWAP-update hook before returning. Direct-transfer detection blocks reads from un-validated reserves.

**V121. Public API panic on truncated / malformed input (split into 4 sub-shapes)**

- **D:** Refinement of V99. Split V99 into specific shapes for clearer detection:
  - **V121a**: truncated slice/borrow — `slice[N..M]` panic when M > slice.len().
  - **V121b**: unwrap on decoder failure — `BorshDeserialize::try_from_slice(...).unwrap()`.
  - **V121c**: zero-option / livelock — division by zero, infinite loop on default options.
  - **V121d**: oversized decimal/BigInt parse — naive O(n²) parsing exhausts CPU.
  Distinct from V99 because each sub-shape requires a different fix and a different fuzz strategy in Stage 3.6 Validator 3. **Solves SP1 M-02 (V121a/b), M-03 (V121c), M-07 (V121d).** Codex V119, V120.
- **FP:** Per sub-shape: V121a length-check first; V121b use `?` not `.unwrap()`; V121c reject zero options at function entry; V121d cap input length.

**V122. Proof / shard metadata clobber on pack / merge (ZK)**

- **D:** When packing or merging proof shards, deferred events, or sub-circuit outputs, metadata fields (proof nonce, vk root, public-values hash) are clobbered or aliased between shards. Two distinct shards' proofs become indistinguishable; verifier accepts wrong-shard's proof. **Solves SP1 M-06.** Codex V122 + internal V128.
- **FP:** Pack/merge functions explicitly preserve every metadata field with `chain.append(shard.metadata)`; nonce uniqueness checked before merge.

**V123. ZK advice/hint value not bound to constrained value**

- **D:** A circuit hint (out-of-band-computed value injected into the witness) is used as input to subsequent constraints but the constraint chain doesn't enforce that the hint matches its definitional source. Distinct from V104 (unconstrained column entirely); V123 is constrained-but-not-bound-to-source. **Solves SP1 H-01 (KoalaBearRangeCheck recomp gap), generic Plonk hint patterns.** Codex V121.
- **FP:** Every hint-cell has an explicit constraint relating it to its source: `cs.assert_eq(hint, source_expression)`.

**V124. Interest-bearing / rebasing token accounting drift**

- **D:** Token-2022 `InterestBearingConfig` (or any wrapper whose displayed balance accrues without an explicit `transfer`) mutates `account.amount` over time. Protocol stored `user.deposited = balance_at_deposit_time` and later compares it to `account.amount` assuming equality, OR a shares-based vault computes `total_assets()` by reading `account.amount` live — share price inflates with accrued interest the vault didn't authorize, and withdrawals over-distribute. Distinct from V68 (transfer-fee accounting at deposit time): V124 is *passive* mid-life balance drift.
- **FP:** `total_assets()` reads a *snapshotted* accounting variable updated only on explicit deposit / withdraw. Or refuse mints with `InterestBearingConfig` from the allowlist. Or pin deposits to the underlying `ui_amount_to_amount` rate at deposit time and convert on read.
- **Fix:** Decouple stored accounting from `account.amount` for any mint carrying `InterestBearingConfig`. Validate allowlist at deposit acceptance: `require!(!mint.has_extension::<InterestBearingConfig>(), ErrorCode::UnsupportedExtension)` unless explicitly handled.
- **Refs:** OtterSec Token-2022 Audit (`solana-labs/security-audits/spl/OtterSecToken2022Audit-2023-11-03.pdf`); SPL Token-2022 extension spec.

**V125. SPL Token-2022 permanent-delegate authority abuse**

- **D:** Token-2022 mint sets `PermanentDelegate` — an authority that can `transfer` or `burn` from any holder without consent. Protocol allowlist accepts the mint without disclosing or constraining the delegate; the delegate (or whoever compromises that key) clawbacks user balances. Or protocol *is* the permanent delegate and its admin / upgrade path can be hijacked to drain every depositor.
- **FP:** Mint allowlist rejects any mint with `PermanentDelegate` unless the delegate is a project-owned PDA whose authority path is gated by timelock + multisig. Trust model documents the delegate's authority chain explicitly.
- **Fix:** Read `MintExt::PermanentDelegate` at deposit. Reject if not the explicit project PDA. Surface the delegate's authority chain in `trust-model.md`.
- **Refs:** OtterSec Token-2022 Audit; SPL Token-2022 extension spec.

**V126. Multisig signer-threshold replay (Squads / Serum pattern)**

- **D:** On-chain multisig stores a `Vec<Approval>` keyed by `(signer, proposal_id)`. Either (a) approvals are not marked consumed atomically with execution, OR (b) the multisig's nonce is not bumped post-execution, OR (c) re-proposing produces the same proposal hash without a fresh nonce. Same approval set re-executes against a logically-identical re-proposal. Adjacent to V61 (off-by-one majority on even N) when the multisig's threshold math itself is wrong.
- **FP:** Each `Approval` carries `(proposal_id, multisig_nonce, signer)` and is `consumed: bool` flipped atomically with execution. Multisig nonce strictly monotonic; proposal hash binds the nonce.
- **Fix:** Add `consumed` field. Bump nonce inside the executing instruction. Reject any approval where `multisig_nonce != current_nonce`.
- **Refs:** OtterSec formal verification of Squads Protocol v3/v4 (`osec.io/blog/2023-01-26-formally-verifying-solana-programs`, `docs.squads.so/security/formal-verifications`).

**V127. Substrate `StorageMap` non-cryptographic hasher collision**

- **D:** Pallet declares `StorageMap<_, Twox64Concat, Key, Value>` (or `Blake2_128Concat`) over an attacker-controllable `Key`. `Twox64Concat` is non-cryptographic (8-byte XXHash prefix + concat); an attacker who controls key generation finds a colliding pair whose hashed prefix collides with another live entry's, overwriting it via the write path or reading another user's value via the iteration path. `Blake2_128Concat` is cryptographically secure but its concat scheme still allows targeted-prefix attacks on very short keys.
- **FP:** Use `Identity` hasher only for non-attacker keys (e.g., `BlockNumber`). Use `Blake2_128Concat` for user-controlled keys. For high-stakes maps, prefer `Blake2_256` (full domain separation) or wrap the key in a domain-tagged tuple `(b"namespace", user_key)` before hashing.
- **Fix:** Audit every `Twox64Concat` use against the threat model; replace with `Blake2_128Concat` for user-controlled keys; domain-prefix high-value maps.
- **Refs:** Trail of Bits "Not So Smart Pallets" (`secure-contracts.com/not-so-smart-contracts/substrate/index.html`).

**V128. XCM barrier bypass / asset-trap injection**

- **D:** Parachain's `XcmConfig::Barrier` composition includes a permissive filter (e.g., `AllowUnpaidExecutionFrom<Everything>` mistakenly shipped from test config), OR the barrier chain admits a malformed message that lands in the `AssetTrap` via `ClaimAsset` from a different chain context than the original holder. Attacker drains trapped assets or executes unpaid XCM logic.
- **FP:** Barrier composition is deny-by-default: `DenyThenTry<DenyReserveTransferToRelayChain, ...>` first, then `TakeWeightCredit`, then narrow `AllowTopLevelPaidExecutionFrom<KnownOrigins>`. No `Everything` filters outside test config. `AssetTrap::claim` is gated by original-sender location proof.
- **Fix:** Replace `Everything` filters; tighten `AssetTrap` claim path to require origin equality with the trapping message's sender.
- **Refs:** Trail of Bits Not So Smart Pallets; Polkadot forum "Common Vulnerabilities in Substrate/Polkadot Development".

**V129. BEEFY / GRANDPA validator-set handoff race**

- **D:** Bridge light-client (BEEFY commitments, GRANDPA justifications, Tendermint headers) processes a finality proof under the *previous* validator set after the destination chain has already advanced to a new set, OR accepts a proof signed by the new set before locally finalizing the transition. Distinct from V91 (general validator-set rotation race) — V129 is the BEEFY/GRANDPA-specific era-boundary failure where `authority_set_id` is not strict-equality-checked.
- **FP:** Light-client state pins `(current_authority_set_id, current_validators)`; verification rejects any proof whose `authority_set_id` does not equal current. Era-boundary transitions are atomic — the boundary message itself is the only proof that can transition the set; subsequent messages must use the new set.
- **Fix:** Strict equality on `authority_set_id`. TTL on rotated-out sets that expires the moment the new set is finalized. Reject "lagging-set" messages.
- **Refs:** Trail of Bits publications (`github.com/trailofbits/publications`); Polkadot Alliance Legion forum.

**V130. Read → CPI → re-read TOCTOU on the same account**

- **D:** Instruction reads `account.field`, performs a CPI (or CosmWasm submessage that re-enters via `reply`), then re-reads `account.field` (or relies on the pre-CPI snapshot) without acknowledging the CPI mutated it. Two reads diverge; post-CPI logic acts on a stale or inconsistent snapshot. Distinct from V8 (CPI re-entry — different program re-enters caller) and V45 (read-only re-entrancy — cross-protocol query during mid-update); V130 is single-program inconsistency *within* one instruction across the CPI boundary.
- **FP:** CEI ordering — state read and used entirely before CPI. Or explicit post-CPI re-read with invariant assertion `require!(account.field == pre_field, ...)` on values expected unchanged.
- **Fix:** Move CPI to the end of the instruction. If sequencing requires reads on both sides, re-read post-CPI and assert expected non-change.
- **Refs:** Neodyme common pitfalls (`neodyme.io/de/blog/solana_common_pitfalls/`); Trail of Bits Not So Smart Contracts Solana (`secure-contracts.com/not-so-smart-contracts/solana/index.html`).

**V131. SPL Token-2022 confidential-transfer ZK proof soundness gap**

- **D:** Token-2022 `ConfidentialTransfer` uses ElGamal-encrypted balances + ZK range / equality proofs. Protocol integrates confidential transfers but mishandles one of: (a) ciphertext malleability (accepts re-randomized ciphertext as distinct), (b) range-proof bit-width mismatch (accepts a 32-bit-range proof where the field is 64-bit), (c) auditor-key bypass (skips the auditor-decryptable-ciphertext check on a flagged mint).
- **FP:** Always call SPL's batched `ConfidentialTransferInstruction::verify_*` helpers; never roll a custom verifier. Hardcode expected proof bit-width per asset. Enforce auditor-ciphertext presence on every confidential-extension mint.
- **Fix:** Standardize on SPL's verifier. Per-mint config pins proof bit-width and auditor-key requirement. Reject re-randomized ciphertexts via a `seen_nullifier` set or by binding ciphertext to a per-tx nonce.
- **Refs:** OtterSec Token-2022 Audit; Solana Foundation confidential-transfer spec.

**V132. Cancelable vesting clawback / cliff-truncation rounding**

- **D:** Vesting schedule computes `vested = (amount * elapsed) / total` with integer truncation toward zero (favoring the protocol). Cancel-and-clawback path uses `clawback = amount - vested` reading the truncated `vested`, clawing back more than the beneficiary's entitlement. Or the clawback formula fails to subtract `already_claimed`, double-counting prior claims and clawing back legitimately-vested-and-claimed tokens. Cliff-boundary off-by-one: `if elapsed < cliff { vested = 0 }` flips at the exact-equal case differently than the schedule assumes.
- **FP:** Vesting math is computed once per call and propagated consistently to both claim and clawback paths. Rounding direction explicitly favors the beneficiary on partial periods. Clawback formula: `clawback = amount.saturating_sub(vested_at_cancel).saturating_sub(already_claimed)`.
- **Fix:** Refactor to a single `compute_vested(amount, start, cliff, total, now) -> (vested, claimable)` helper used by every entry point. Property test the cliff boundary and partial-period edges.
- **Refs:** Public Solana / CosmWasm vesting-protocol audits in `2501babe/solana-security-audits` corpus.

---

## How to extend

When you find a new vector in a real codebase, append a new entry with:

- The next `Vn` ID
- A concise **Title**
- **D:** description of the failure pattern
- **FP:** the fixed-pattern signal
- **Fix:** (optional) the recommended remediation if non-obvious

Vector entries should be 2-4 lines. If a pattern needs more explanation, it's probably two vectors — split it.

Vectors are language-aware: Solana / Anchor, CosmWasm, Substrate, and generic Rust. Cross-ecosystem vectors (replay, low-S, domain separation) get tagged in the description.
