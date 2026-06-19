# Aptos Move Attack Vectors Catalog

Known attack vectors for Aptos Move smart contracts, organized by category. Each vector includes detection patterns.

---

## 1. Ability Exploitation

### 1.1 Asset Duplication via `copy`
- **Severity**: CRITICAL
- **Pattern**: Struct representing value has `copy` ability
- **Impact**: Unlimited fund duplication
- **Detection**: `rg "public struct.*(Coin|Token|Asset|Balance).*has.*copy" sources/`

### 1.2 Silent Loss via `drop`
- **Severity**: CRITICAL
- **Pattern**: Struct representing value has `drop` ability
- **Impact**: Funds silently discarded
- **Detection**: `rg "public struct.*(Coin|Token|Asset|Balance).*has.*drop" sources/`

---

## 2. Access Control Bypass

### 2.1 Ungated Entry Functions
- **Severity**: CRITICAL
- **Pattern**: `public entry fun` without signer validation
- **Impact**: Unauthorized privileged operations
- **Detection**: `rg "public entry fun" sources/ | grep -v "signer"`

### 2.2 Signer Validation Bypass
- **Severity**: CRITICAL
- **Pattern**: `&signer` parameter used without validating the address
- **Impact**: Unauthorized operations on behalf of any account
- **Detection**: `rg "public entry fun.*signer" sources/` then check for `assert!` on signer address

### 2.3 Capability Claiming
- **Severity**: HIGH
- **Pattern**: Function creates and transfers capability without authorization
- **Impact**: Anyone gains admin/minter privileges
- **Detection**: `rg "public.*fun.*claim\|public.*fun.*create.*Cap.*transfer" sources/`

---

## 3. Witness and Type System Abuse

### 3.1 Forgeable Witness
- **Severity**: CRITICAL
- **Pattern**: Witness struct can be instantiated outside module `init`
- **Impact**: Unauthorized type creation, token minting
- **Detection**: `rg "public struct.*has drop" sources/` then verify struct is not OTW

### 3.2 Witness Reuse
- **Severity**: HIGH
- **Pattern**: Witness has `store` or `copy`, allowing it to be saved and reused
- **Impact**: Witness consumed in init but copy retained for later abuse
- **Detection**: `rg "public struct.*Witness.*has.*(store|copy)" sources/`

### 3.3 Generic Type Confusion
- **Severity**: HIGH
- **Pattern**: Generic functions without proper ability constraints
- **Impact**: Store/extract unauthorized types
- **Detection**: `rg "public fun.*<T>" sources/ | grep -v "phantom\|store\|key"`

---

## 4. Concurrency and State Issues

### 4.1 Stale Parameters
- **Severity**: MEDIUM
- **Pattern**: Parameters read from storage at beginning of multi-step operation, but state may change between steps
- **Impact**: Operations based on stale data
- **Detection**: Look for sequential `borrow_global` calls or multi-step operations

---

## 5. Economic Attacks

### 5.1 Flash Loan Attack
- **Severity**: HIGH
- **Pattern**: Price/oracle manipulation within a single transaction using borrowed funds
- **Impact**: Draining liquidity pools, manipulating prices
- **Detection**: `rg "flash\|loan\|borrow.*deposit" sources/`

### 5.2 First Depositor / Zero-State Issue
- **Severity**: MEDIUM
- **Pattern**: Division by zero or rate manipulation when vault/pool has zero or near-zero deposits
- **Impact**: First depositor gets inflated share ratio
- **Detection**: `rg "shares.*total_supply\|balance.*\.value.*/" sources/`

### 5.3 Rounding Exploitation
- **Severity**: MEDIUM
- **Pattern**: Integer division truncation that can be exploited for small gains at scale
- **Impact**: Systematic value extraction
- **Detection**: `rg " \/ " sources/` in financial calculation contexts

### 5.4 Share Inflation Attack
- **Severity**: HIGH
- **Pattern**: Attacker deposits dust, donates inflated tokens, then redeems for disproportionate share
- **Impact**: Theft of other depositors' funds
- **Detection**: Look for vault deposit/withdraw without minimum deposit or offset

---

## 6. Storage and State Management

### 6.1 Unbounded Storage Growth
- **Severity**: MEDIUM
- **Pattern**: Vectors or tables that can grow without limit
- **Impact**: DoS via gas exhaustion, storage bloat
- **Detection**: `rg "vector::push_back\|table::add" sources/` without size checks

### 6.2 Missing `exists` Check
- **Severity**: HIGH
- **Pattern**: `borrow_global` without prior `exists` check
- **Impact**: Runtime abort, potential DoS
- **Detection**: `rg "borrow_global" sources/` then verify preceding `exists` or `assert!`

---

## 7. Aptos-Specific Attack Vectors

### 7.1 Reentrancy via FA Hooks (Move 2.2+)
- **Severity**: HIGH
- **Pattern**: FungibleAsset dispatch hooks allow callbacks during transfer/mint
- **Impact**: Reentrancy-style attacks
- **Detection**: `rg "dispatch\|hook\|FungibleAsset" sources/`

### 7.2 Ref Lifecycle Abuse
- **Severity**: HIGH
- **Pattern**: MintRef, BurnRef, TransferRef not properly secured or stored
- **Impact**: Unauthorized minting, burning, or transfers
- **Detection**: `rg "MintRef\|BurnRef\|TransferRef" sources/`

### 7.3 SignerCapability Leakage
- **Severity**: CRITICAL
- **Pattern**: SignerCapability stored in accessible resource or transferred
- **Impact**: Attacker can act as any account
- **Detection**: `rg "SignerCapability\|signer_capability" sources/`

---

## Attack Vector Matrix (Aptos)

| Vector | Severity |
|--------|----------|
| Asset `copy` ability | CRITICAL |
| Asset `drop` ability | CRITICAL |
| Forgeable Witness | CRITICAL |
| Ungated entry function | CRITICAL |
| Signer bypass | CRITICAL |
| SignerCapability leakage | CRITICAL |
| Capability leakage | HIGH |
| Flash loan manipulation | HIGH |
| Generic type confusion | HIGH |
| FA hook reentrancy | HIGH |
| Ref lifecycle abuse | HIGH |
| Unbounded storage | MEDIUM |
| Stale parameters | MEDIUM |
| First depositor | MEDIUM |
| Rounding exploitation | MEDIUM |
