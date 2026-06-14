# Sui Move Attack Vectors Catalog

Known attack vectors for Sui Move smart contracts, organized by category. Each vector includes detection patterns.

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

### 1.3 Unauthorized Storage via `store`
- **Severity**: HIGH
- **Pattern**: Sensitive capability has `store`, can be embedded in attacker objects
- **Impact**: Capability extracted and used from wrapper
- **Detection**: `rg "public struct.*Cap.*has.*store" sources/`

---

## 2. Access Control Bypass

### 2.1 Ungated Entry Functions
- **Severity**: CRITICAL
- **Pattern**: `public entry fun` without capability check
- **Impact**: Unauthorized privileged operations
- **Detection**: `rg "public entry fun" sources/ | grep -v "Cap\|TxContext"`

### 2.2 Object Theft
- **Severity**: CRITICAL
- **Pattern**: `public_transfer` without ownership or capability check
- **Impact**: Anyone can transfer any object passed to them
- **Detection**: `rg "public_transfer" sources/`

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

### 4.1 Shared Object Race
- **Severity**: CRITICAL
- **Pattern**: Shared object modified without status flag or consistency check
- **Impact**: Double-spending, inconsistent state
- **Detection**: `rg "share_object\|shared_object" sources/` then check for status tracking

### 4.2 PTB Composition Attack
- **Severity**: HIGH
- **Pattern**: Functions that should be atomic but can be composed maliciously in a PTB
- **Example**: Deposit → Borrow → Withdraw in same transaction without health check
- **Detection**: Look for separate deposit/borrow/withdraw functions that lack post-operation health verification

### 4.3 Stale Parameters
- **Severity**: MEDIUM
- **Pattern**: Parameters read from storage at beginning of multi-step operation, but state may change between steps
- **Impact**: Operations based on stale data
- **Detection**: Look for sequential `borrow_global` calls or multi-step operations on shared objects

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
- **Pattern**: Vectors, tables, or dynamic fields that can grow without limit
- **Impact**: DoS via gas exhaustion, storage bloat
- **Detection**: `rg "vector::push_back\|table::add\|dynamic_field::add" sources/` without size checks

### 6.2 Dynamic Field Abuse
- **Severity**: HIGH
- **Pattern**: Dynamic fields modified without access control
- **Impact**: Unauthorized metadata or state changes
- **Detection**: `rg "dynamic_field::add\|dynamic_field::remove" sources/`

---

## 7. Sui-Specific Attack Vectors

### 7.1 Kiosk Bypass
- **Severity**: HIGH
- **Pattern**: Assets that should only be traded through kiosk have direct transfer paths
- **Impact**: Bypass transfer policies, royalty evasion
- **Detection**: `rg "transfer::public_transfer" sources/` for types also used in kiosk

### 7.2 Transfer Policy Bypass
- **Severity**: HIGH
- **Pattern**: TransferPolicy not enforced or can be skipped
- **Impact**: Bypass KYC/AML, transfer restrictions
- **Detection**: `rg "TransferPolicy\|TransferRequest" sources/`

### 7.3 UpgradeCap Mishandling
- **Severity**: HIGH
- **Pattern**: UpgradeCap transferred to unauthorized party or not properly managed
- **Impact**: Unauthorized code upgrades, backdoor insertion
- **Detection**: `rg "UpgradeCap\|package::upgrade" sources/`

---

## Attack Vector Matrix (Sui)

| Vector | Severity |
|--------|----------|
| Asset `copy` ability | CRITICAL |
| Asset `drop` ability | CRITICAL |
| Forgeable Witness | CRITICAL |
| Ungated entry function | CRITICAL |
| Object theft | CRITICAL |
| Shared object race | CRITICAL |
| Capability leakage | HIGH |
| PTB composition | HIGH |
| Flash loan manipulation | HIGH |
| Generic type confusion | HIGH |
| Dynamic field abuse | HIGH |
| Kiosk bypass | HIGH |
| Transfer policy bypass | HIGH |
| UpgradeCap mishandling | HIGH |
| Unbounded storage | MEDIUM |
| Stale parameters | MEDIUM |
| First depositor | MEDIUM |
| Rounding exploitation | MEDIUM |
