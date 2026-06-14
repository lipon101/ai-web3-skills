# Chain Deep-Dive: Starknet / Cairo

_Loaded when Phase 1.1 detects `.cairo` files with `#[starknet::contract]`, `#[external(v0)]`. Sourced from WEB3-AUDIT-SKILLS cairo-scanner, starknet-scanner, and Trail of Bits cairo-vulnerability-scanner._

---

## Cairo/Starknet-Specific Attack Vectors (V249–V255)

**V249. felt252 Arithmetic Overflow at Prime** — D: `felt252` values wrap at the Stark prime (~2^251). Arithmetic produces valid but unexpected results near the prime boundary. Comparison operators misbehave for values close to the prime (negative numbers in felt are actually huge positives). FP: Bounded integer types (`u128`, `u256`) used for all arithmetic. `felt252` used only for identifiers/hashes. Explicit range checks before arithmetic.

**V250. Starknet Reentrancy via call_contract** — D: Cairo's `call_contract_syscall` to untrusted external contract before state updates. Unlike EVM, there's no global reentrancy lock mechanism. FP: State updated before external call (CEI pattern). External calls only to trusted/whitelisted contracts. Custom reentrancy flag in storage.

**V251. Sequencer Censorship / Ordering Manipulation** — D: Single Starknet sequencer controls transaction ordering and inclusion. Time-sensitive operations (liquidations, auctions, governance votes) can be censored or reordered. FP: Protocol doesn't rely on execution ordering. Timelock windows account for potential censorship. L1 escape hatch for critical operations.

**V252. L1↔L2 Message Hash Collision** — D: Cross-layer message handler validates message hash but hash construction allows collision. Different messages produce same hash due to felt packing without length prefixing. FP: Message hash includes all fields with proper length encoding. `poseidon_hash` used for collision resistance. Nonce enforced for uniqueness.

**V253. Storage Address Computation Mismatch** — D: Cairo storage addresses computed via `sn_keccak(variable_name)` + struct field offsets. If contract assumes EVM-style sequential slots, storage reads/writes target wrong addresses. Mapping storage uses `h(key, variable_address)`. FP: Storage macros from Starknet compiler used. No manual storage address computation. Component-based storage with `#[storage]` attribute.

**V254. Cairo Steps Gas Limit Exhaustion** — D: Transaction exceeds Starknet's step limit (different from EVM gas). Complex computations silently truncated or fail. Cairo VM charges by computational step, not by opcode — loops with many iterations more expensive than EVM equivalent. FP: Function complexity bounded. Loop iterations capped. Gas estimation tested for worst case.

**V255. Missing Contract Class Hash Validation** — D: Contract factory deploys instances without validating class hash. Attacker substitutes malicious class hash. Or protocol interacts with contract without verifying its class hash matches expected implementation. FP: `class_hash` validated against registered hash before interaction. Factory uses hardcoded class hash with governance-controlled updates.

---

## Cairo Scanning Methodology

### Entry Point Discovery
```bash
# Find all external functions
grep -rn "#\[external\|#\[abi\|fn " --include="*.cairo" | grep -v test
# Find storage access
grep -rn "self\.\|storage_read\|storage_write\|StorageAccess" --include="*.cairo"
# Find external calls
grep -rn "call_contract_syscall\|ICoreDispatcher\|IDispatcher" --include="*.cairo"
# Find felt arithmetic
grep -rn "felt252\|felt_" --include="*.cairo" | grep -v test
```

### Critical Checks
- All arithmetic uses bounded integer types, not raw `felt252`
- External calls follow CEI pattern (state before call)
- L1↔L2 messages include proper hash construction with nonce
- Storage access uses Starknet compiler macros (no manual address computation)
- Contract class hashes validated before interaction
- Gas costs estimated for worst-case step count
- Sequencer dependency minimized for critical operations
