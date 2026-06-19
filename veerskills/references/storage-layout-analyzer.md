# Storage Layout Analyzer

_Systematic storage layout analysis protocol for proxy/upgradeable contracts. Catches slot collisions, struct packing gaps, and upgrade-breaking layout changes._

---

## When to Use

Mandatory for any codebase with:
- Proxy patterns (Transparent, UUPS, Beacon, Diamond/EIP-2535)
- Upgradeable contracts (any `Initializable` usage)
- Assembly `sstore`/`sload` with computed slots
- `delegatecall` to external contracts

---

## Module 1: Storage Slot Computation Rules

### Sequential Storage
```
Slot 0: first state variable
Slot 1: second state variable
...
Struct members packed left-to-right within 32-byte slots
```

### Mapping Storage
```
mapping(keyType => valueType) at slot p:
  value location = keccak256(abi.encode(key, p))

mapping(k1 => mapping(k2 => valueType)) at slot p:
  value location = keccak256(abi.encode(k2, keccak256(abi.encode(k1, p))))
```

### Dynamic Array Storage
```
array at slot p:
  length = sload(p)
  element[i] = sload(keccak256(p) + i)
```

### EIP-1967 Standard Slots
```solidity
// Implementation slot
bytes32 constant IMPLEMENTATION_SLOT = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
// = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc

// Admin slot
bytes32 constant ADMIN_SLOT = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1);
// = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103

// Beacon slot
bytes32 constant BEACON_SLOT = bytes32(uint256(keccak256("eip1967.proxy.beacon")) - 1);
// = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50
```

### EIP-7201 Namespaced Storage
```solidity
// Namespaced storage location
bytes32 constant NAMESPACE = keccak256(abi.encode(uint256(keccak256("namespace.id")) - 1)) & ~bytes32(uint256(0xff));
```

---

## Module 2: Automated Extraction Commands

### Forge Storage Layout
```bash
# Get full storage layout for a contract
forge inspect ContractName storage-layout --pretty

# Compare V1 vs V2 layouts
forge inspect V1 storage-layout --pretty > /tmp/v1_layout.txt
forge inspect V2 storage-layout --pretty > /tmp/v2_layout.txt
diff /tmp/v1_layout.txt /tmp/v2_layout.txt
```

### Slither Storage Layout
```bash
# Print storage layout
slither . --print variable-order 2>/dev/null

# Print all variables and their authorization
slither . --print vars-and-auth 2>/dev/null
```

### Manual Slot Verification
```bash
# Read a specific slot from deployed contract (via cast)
cast storage <contract_address> <slot_number> --rpc-url <rpc>

# Verify EIP-1967 implementation slot
cast storage <proxy_address> 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
```

---

## Module 3: Struct Packing Analysis

### Rules
- Variables < 32 bytes are packed left-to-right within a slot
- A new slot starts when the next variable doesn't fit in the remaining space
- `mapping` and `dynamic array` always start a new slot
- Struct members follow the same packing rules

### Gap Detection Checklist
- [ ] **GP-01**: Are there any `uint256` between two small types? (wastes gas, potential padding issue)
- [ ] **GP-02**: Are `bool` variables grouped together? (8 bools can share 1 slot)
- [ ] **GP-03**: Are `address` (20 bytes) paired with types ≤ 12 bytes? (optimal packing)
- [ ] **GP-04**: Does a struct cross a 32-byte boundary unnecessarily?
- [ ] **GP-05**: Is there a storage gap (`__gap`) for upgrade safety? (usually `uint256[50] __gap`)

### Common Packing Patterns
```solidity
// ✅ GOOD: Packed (1 slot)
address owner;      // 20 bytes
bool paused;        // 1 byte
uint8 version;      // 1 byte
// Total: 22 bytes → fits in 1 slot

// ❌ BAD: Wasted space (3 slots)
bool paused;        // Slot 0: 1 byte (31 bytes wasted)
address owner;      // Slot 1: 20 bytes (12 bytes wasted)
uint8 version;      // Slot 2: 1 byte (31 bytes wasted)
```

---

## Module 4: Upgrade Safety Checklist

### Storage Layout Preservation
- [ ] **UG-01**: New state variables ONLY appended at the END — never inserted in the middle
- [ ] **UG-02**: No existing state variables removed or reordered between versions
- [ ] **UG-03**: No type changes that alter slot size (e.g., `uint128` → `uint256`)
- [ ] **UG-04**: Storage gap (`__gap`) reduced by exactly the number of new variables added
- [ ] **UG-05**: Inherited contract storage order preserved (C3 linearization unchanged)
- [ ] **UG-06**: No new inheritance added BEFORE existing inherited contracts

### Proxy-Specific Checks
- [ ] **UG-07**: Proxy storage doesn't overlap implementation storage (EIP-1967 slots used)
- [ ] **UG-08**: `_disableInitializers()` called in implementation constructor
- [ ] **UG-09**: `reinitializer(version)` with correct incrementing version number
- [ ] **UG-10**: No `immutable` variables in upgradeable contracts (they live in bytecode, not storage)
- [ ] **UG-11**: No `selfdestruct` in implementation (Dencun changes behavior)
- [ ] **UG-12**: UUPS `_authorizeUpgrade()` has proper access control

### Diamond/EIP-2535 Specific
- [ ] **UG-13**: All facets use namespaced storage (EIP-7201) — NOT sequential slots
- [ ] **UG-14**: No two facets write to the same storage namespace
- [ ] **UG-15**: Facet removal doesn't orphan storage (data still accessible after re-adding)
- [ ] **UG-16**: `diamondCut` validates no selector collisions between facets

---

## Module 5: Common Storage Bugs

### Bug SL-01: Slot Collision Between Proxy and Implementation
```solidity
// ❌ WRONG: Both start at slot 0
contract Proxy {
    address implementation;  // Slot 0
}
contract Implementation {
    address owner;  // Slot 0 — COLLISION with proxy's implementation
}

// ✅ RIGHT: EIP-1967 randomized slots
contract Proxy {
    // implementation stored at EIP-1967 slot, not sequential
}
```

### Bug SL-02: Storage Gap Not Updated on Upgrade
```solidity
// V1: gap = 50
uint256[50] __gap;

// V2 WRONG: Added 2 variables but gap still 50
uint256 newVar1;
uint256 newVar2;
uint256[50] __gap;  // Should be [48]!

// V2 RIGHT:
uint256 newVar1;
uint256 newVar2;
uint256[48] __gap;  // Reduced by 2
```

### Bug SL-03: Inheritance Order Change
```solidity
// V1: A, B → A at slot 0, B after A
contract V1 is A, B { }

// V2 WRONG: B, A → B at slot 0, A after B — ALL slots shifted!
contract V2 is B, A { }
```

### Bug SL-04: Immutable in Upgradeable
```solidity
// ❌ WRONG: immutable lives in bytecode — proxy sees implementation's value
contract VaultImpl {
    address immutable ORACLE;  // Hardcoded in implementation bytecode
}
// Proxy delegates to VaultImpl but ORACLE was set during implementation deploy
// not during proxy deploy — users get wrong oracle

// ✅ RIGHT: Use regular state variable or constructor parameter
```

### Bug SL-05: Assembly sstore to Wrong Slot
```solidity
// ❌ WRONG: Hardcoded slot assumption
assembly { sstore(0, newOwner) }  // Assumes owner is at slot 0

// ✅ RIGHT: Compute slot properly
bytes32 slot = keccak256("owner.storage.slot");
assembly { sstore(slot, newOwner) }
```

---

## Integration with VeerSkills Pipeline

**Phase 2 (MAP)**: Run `forge inspect` and `slither --print variable-order` for all contracts. Document storage layout in `notes/state/`.

**Phase 3 (HUNT)**: For any proxy/upgradeable contract:
1. Run Module 4 checklist (UG-01 through UG-16)
2. Compare V1/V2 layouts if upgrade exists
3. Check all assembly `sstore`/`sload` against computed slots

**Phase 4 (ATTACK)**: For any storage layout finding:
1. Verify slot computation with `cast storage` against deployed contract
2. Demonstrate collision/corruption with concrete values
3. Show impact: what state gets corrupted and what's the exploit path
