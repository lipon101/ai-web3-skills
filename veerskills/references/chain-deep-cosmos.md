# Chain Deep-Dive: Cosmos (CosmWasm / SDK Modules)

_Loaded when Phase 1.1 detects `.rs` files with `#[entry_point]`, `cosmwasm_std`, or `.go` files with Cosmos SDK patterns. Sourced from Trail of Bits cosmos-vulnerability-scanner and WEB3-AUDIT-SKILLS cosmos-scanner._

---

## Cosmos-Specific Attack Vectors (V243–V248)

**V243. Unvalidated IBC Channel/Denomination** — D: Contract accepts tokens via IBC without validating channel/port/denomination path. Attacker sends worthless tokens from rogue chain via unauthorized channel. Contract treats them as legitimate assets. FP: `ibc_channel_open` validates counterparty chain/port. Denomination includes full IBC path validation. Allowlisted channels only.

**V244. SubMsg Reply Handler State Desync** — D: `SubMsg` with `ReplyOn::Success` modifies state in the main execute, but reply handler assumes pre-execute state. Or `ReplyOn::Error` handler doesn't rollback main execute state changes. FP: Reply handler reads fresh state. Atomic execute+reply via `SubMsg::reply_always`. State changes in reply only.

**V245. CosmWasm Reentrancy via SubMsg** — D: Contract sends `SubMsg` to untrusted contract via `WasmMsg::Execute`. Callback in `reply` handler re-enters original contract before state finalized. FP: State committed before `SubMsg`. Reply handler uses only response data, not contract state. `SubMsg` only to trusted contracts.

**V246. Cosmos SDK Module Keeper Privilege Escalation** — D: Module's `Keeper` exposed with too-broad interface. Other modules call privileged keeper methods (e.g., `MintCoins`, `BurnCoins`) without proper authorization checks at the keeper level. FP: Keeper methods validate caller module. Authorization delegated to governance. Keeper interface minimal and audited.

**V247. Governance Proposal Parameter Injection** — D: `ParameterChangeProposal` modifies module parameters without validation. Attacker submits governance proposal setting dangerous parameters (zero slashing, infinite inflation, zero minimum deposit). FP: Parameter bounds enforced in `Params.Validate()`. Critical params have additional governance threshold. Emergency governance halt.

**V248. Staking/Delegation Reward Siphoning** — D: Delegation rewards calculated based on validator commission and stake proportion. If reward distribution doesn't account for delegation changes within an epoch, attacker adds stake just before distribution, claims disproportionate rewards, then undelegates. FP: Reward distribution uses epoch-start stake snapshot. `BeginBlocker` updates are atomic with reward claims. Minimum stake duration.

---

## Cosmos Scanning Methodology

### Entry Point Discovery
```bash
# CosmWasm entry points
grep -rn "#\[entry_point\]\|pub fn instantiate\|pub fn execute\|pub fn query\|pub fn migrate" --include="*.rs"
# IBC handlers
grep -rn "ibc_channel_open\|ibc_channel_connect\|ibc_packet_receive\|ibc_packet_ack" --include="*.rs"
# SubMsg usage
grep -rn "SubMsg\|ReplyOn\|Reply" --include="*.rs" | grep -v test
# SDK module entry points (Go)
grep -rn "func.*Keeper.*Msg\|BeginBlocker\|EndBlocker" --include="*.go"
```

### Critical Checks
- All IBC channels validated against allowlist
- SubMsg reply handlers handle both success and error paths
- CosmWasm execute handlers validate `info.sender` for privileged operations
- Token denomination paths fully validated (not just denom string)
- Module keepers expose minimal interface
- Governance parameter changes have bounds validation
- Staking reward distribution uses epoch-consistent snapshots
