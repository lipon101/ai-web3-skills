# Chain Deep-Dive: Move (Sui / Aptos)

_Loaded when Phase 1.1 detects `.move` files with `module`, `public entry fun`, `use sui::` or `use aptos_framework::`. Sourced from move-auditor-skills, Trail of Bits Move scanner, and WEB3-AUDIT-SKILLS move-scanner._

---

## Move-Specific Attack Vectors (V226–V235)

**V226. Shared Object Front-Running (Sui)** — D: Shared object access requires consensus ordering. Transaction that reads/writes shared object can be front-run by validator or observed in mempool. Time-sensitive operations (auctions, liquidations) exploitable. FP: Owned objects used for time-sensitive actions. Commit-reveal scheme. Clock-based minimum windows.

**V227. Hot Potato Object Misuse** — D: Object without `drop` ability must be consumed by another function. If consumption function has a vulnerability, hot potato forces dangerous execution path. Or hot potato created but no valid consumption path exists — permanent lock. FP: All hot potato types have tested consumption paths. Destruction function has proper validation.

**V228. Dynamic Field Type Confusion** — D: `dynamic_field::borrow<K, V>()` doesn't check type at compile time. Attacker stores Type A under key, reader borrows as Type B. Malformed data interpretation. FP: Dynamic field keys include type marker. Schema enforced at write time. BCS deserialization validates structure.

**V229. Object Ownership Bypass via Transfer** — D: Sui `transfer::transfer` moves object to attacker. Function that should restrict ownership uses `transfer::public_transfer` instead of custom transfer policy. FP: Custom `TransferPolicy` enforced. Object uses shared/frozen ownership model.

**V230. Package Upgrade Capability Leak** — D: `UpgradeCap` stored in shared object or transferred to untrusted address. Anyone with cap can upgrade package, replacing module logic. FP: `UpgradeCap` stored in admin-owned object. Multi-sig controls upgrade. Cap destroyed to make immutable.

**V231. Missing Ability Constraints** — D: Generic type `T` used without proper ability constraints. Type with `copy` ability bypasses move semantics — asset doubled. Type with `drop` allows silent destruction — asset burned without accounting. FP: Generic parameters have minimal abilities: `T: key + store` (no copy, no drop).

**V232. Aptos Resource Account Signer Cap Exposure** — D: `create_resource_account` returns `SignerCapability`. If stored in a publicly accessible resource, anyone can obtain signer and drain account. FP: `SignerCapability` stored in module-private struct with access control.

**V233. Move Math Precision via Fixed-Point Libraries** — D: Custom fixed-point math uses integer division losing precision. `a * b / c` truncates differently than `a / c * b`. No rounding direction specification. FP: Established fixed-point library used. Rounding direction explicitly chosen per operation (floor for user cost, ceil for protocol benefit).

**V234. Coin Registration Race (Aptos)** — D: `coin::register<CoinType>(&user)` must be called before receiving coins. If protocol sends coins to unregistered address, transaction fails bricking the operation. FP: Protocol checks `coin::is_account_registered` before transfer. Auto-registration on first transfer.

**V235. Event Replay / Missing Event Authentication** — D: Protocol reads events off-chain to trigger actions (oracle updates, governance). Events can be replayed or spoofed if not bound to transaction hash. FP: Event data includes unique nonce/txHash. Off-chain consumer tracks processed events.

---

## Move Scanning Methodology

### Entry Point Discovery
```bash
# Find all public functions
grep -rn "public fun\|public entry fun\|public(friend) fun" --include="*.move" | grep -v test
# Find resource access patterns
grep -rn "borrow_global\|borrow_global_mut\|move_from\|move_to" --include="*.move"
# Find Sui object operations
grep -rn "transfer::\|dynamic_field::\|object::new\|share_object" --include="*.move"
# Find ability declarations that are too permissive
grep -rn "has copy\|has drop\|has key, store, copy, drop" --include="*.move"
```

### Critical Checks
- Every `public entry fun` must validate signer/capability for privileged operations
- All coin arithmetic checked for precision loss (division truncation)
- Shared object access patterns assessed for front-running risk
- `UpgradeCap` custody verified — must be in admin-controlled object
- Hot potato objects have valid, tested consumption paths
- Generic type parameters have minimal necessary abilities
