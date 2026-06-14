# Tools Integration Reference

Configuration and invocation reference for all static analysis, dynamic analysis, formal verification, and coverage tools used by VeerSkills.

---

## Static Analysis Tools

### Slither (via MCP)

**Invocation:**
```
Call: mcp__sc-auditor__run-slither
Args: { "rootDir": "." }
```

**Key Detectors:**
| Detector | Severity | What It Finds |
|----------|----------|---------------|
| `reentrancy-eth` | High | ETH-based reentrancy |
| `reentrancy-no-eth` | Medium | Token-based reentrancy |
| `reentrancy-benign` | Low | Non-exploitable reentrancy patterns |
| `uninitialized-state` | High | Uninitialized state variables |
| `arbitrary-send-eth` | High | Unrestricted ETH transfer |
| `controlled-delegatecall` | High | User-controlled delegatecall |
| `suicidal` | High | Unprotected selfdestruct |
| `unprotected-upgrade` | High | Missing access control on upgrade |
| `unchecked-transfer` | Medium | Unchecked ERC-20 transfer return |
| `divide-before-multiply` | Medium | Precision loss in division |
| `tx-origin` | Medium | Authentication via tx.origin |
| `missing-zero-check` | Low | Missing zero-address validation |

**Printers (for Phase 2 MAP):**
```bash
# State variable inventory
slither . --print vars-and-auth 2>/dev/null

# Function summary
slither . --print function-summary 2>/dev/null

# Inheritance graph
slither . --print inheritance-graph 2>/dev/null

# Call graph
slither . --print call-graph 2>/dev/null

# Storage layout (for upgrade analysis)
slither . --print variable-order 2>/dev/null
```

### Aderyn (via MCP)

**Invocation:**
```
Call: mcp__sc-auditor__run-aderyn
Args: { "rootDir": "." }
```

**Key Detectors:**
| Detector | Severity | What It Finds |
|----------|----------|---------------|
| `centralization-risk` | High | Single point of failure in admin |
| `unsafe-oz-access-control` | High | OpenZeppelin AccessControl misuse |
| `solmate-auth-not-safe` | High | Solmate auth vulnerabilities |
| `push-0-opcode` | Medium | PUSH0 incompatibility on L2s |
| `unsafe-erc20-functions` | Medium | Direct ERC-20 calls without SafeERC20 |
| `ecrecover-no-check` | Medium | ecrecover without zero-address check |
| `weak-randomness` | Medium | Predictable randomness sources |
| `missing-events` | Low | State changes without events |
| `dead-code` | Low | Unreachable code |

### 4naly3er (CLI)

```bash
# Run 4naly3er for gas optimizations and common patterns
cd /path/to/project
python3 4naly3er.py ./src
```

### Semgrep (Custom Rules)

```bash
# Run Solidity-specific rules
semgrep --config "p/solidity" ./src/

# Common custom rules
semgrep -e 'tx.origin' --lang solidity ./src/
semgrep -e 'selfdestruct' --lang solidity ./src/
semgrep -e 'delegatecall' --lang solidity ./src/
```

---

## Dynamic Analysis / Fuzzing Tools

### Foundry Fuzz Testing

```bash
# Stateless fuzz testing
forge test --match-path "test/fuzz/*" --fuzz-runs 10000 -vvv

# Invariant (stateful) fuzz testing
forge test --match-path "test/invariant/*" --fuzz-runs 1000 -vvv

# Attack-specific fuzzing
forge test --match-path "test/fuzz/attacks/*" --fuzz-runs 50000 -vvv

# Edge case fuzzing
forge test --match-path "test/fuzz/edge/*" --fuzz-runs 20000 -vvv
```

**foundry.toml configuration for fuzzing:**
```toml
[fuzz]
runs = 10000
max_test_rejects = 65536
seed = "0x0"
dictionary_weight = 40

[invariant]
runs = 1000
depth = 100
fail_on_revert = false
call_override = false
dictionary_weight = 80
```

### Echidna

```bash
# Installation check
echidna --version

# Run with config
echidna-test . --config echidna.config.yaml

# Quick run
echidna-test . --test-limit 10000 --seq-len 50

# Deep run (beast mode)
echidna-test . --test-limit 100000 --seq-len 100

# With corpus directory for coverage tracking
echidna-test . --test-limit 100000 --corpus-dir corpus/
```

**echidna.config.yaml:**
```yaml
testMode: assertion
testLimit: 100000
seqLen: 100
corpusDir: corpus
deployer: "0x1000000000000000000000000000000000000000"
sender:
  - "0x2000000000000000000000000000000000000000"
  - "0x3000000000000000000000000000000000000000"
  - "0x4000000000000000000000000000000000000000"
shrinkLimit: 5000
multi-abi: true
```

### Medusa

```bash
# Run Medusa fuzzer
medusa fuzz --target . --test-limit 100000

# With config
medusa fuzz --config medusa.json
```

**medusa.json:**
```json
{
  "fuzzing": {
    "targetContracts": ["Target"],
    "maxBlockDelay": 60480,
    "maxBlockNumberDelay": 1000,
    "testLimit": 100000,
    "callSequenceLength": 100,
    "corpusDirectory": "medusa-corpus"
  }
}
```

### ItyFuzz

```bash
# Run ItyFuzz for advanced coverage
ityfuzz evm -t ./src/ --onchain-block-number latest
```

---

## Formal Verification Tools

### Certora (CVL Specs)

```bash
# Run Certora verification
certoraRun certora/conf/verify.conf

# Example conf
certoraRun src/Vault.sol \
  --verify Vault:certora/specs/VaultSpec.spec \
  --rule solvencyInvariant accessControlRule \
  --msg "Vault safety verification"
```

**Example Certora Spec:**
```cvl
// VaultSpec.spec
methods {
    function totalAssets() external returns (uint256) envfree;
    function totalSupply() external returns (uint256) envfree;
    function balanceOf(address) external returns (uint256) envfree;
}

// SAFETY: Solvency invariant
invariant solvencyInvariant()
    totalAssets() >= totalSupply()

// ACCESS CONTROL: Only owner can set fee
rule onlyOwnerCanSetFee(env e, uint256 newFee) {
    address caller = e.msg.sender;
    address currentOwner = owner();

    setFee(e, newFee);

    assert caller == currentOwner, "Non-owner changed fee";
}

// DEPOSIT CORRECTNESS: Shares proportional to assets
rule depositCorrectness(env e, uint256 assets, address receiver) {
    uint256 totalSupplyBefore = totalSupply();
    uint256 totalAssetsBefore = totalAssets();

    uint256 shares = deposit(e, assets, receiver);

    assert shares <= assets * totalSupplyBefore / totalAssetsBefore + 1,
           "Shares exceed proportional amount";
}
```

### Halmos (Symbolic Execution)

```bash
# Run Halmos
halmos --contract VaultTest --function test_solvency --solver-timeout-smt 600

# With specific test targets
halmos --match-test "check_" --solver-timeout-smt 300
```

**Halmos Test Pattern:**
```solidity
function check_solvency(uint256 depositAmount) public {
    vm.assume(depositAmount > 0 && depositAmount < type(uint128).max);

    vault.deposit(depositAmount, address(this));

    assert(vault.totalAssets() >= vault.totalSupply());
}
```

### Scribble (Annotation-Based)

```bash
# Annotate and instrument
scribble --arm src/Vault.sol -o src/Vault.instrumented.sol

# Run tests on instrumented contracts
forge test --match-path "test/scribble/*"
```

**Scribble Annotations:**
```solidity
/// #if_succeeds {:msg "solvency"} totalAssets() >= totalSupply();
function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
    // ...
}
```

---

## Coverage Tools (Module 11: Code Coverage Analysis)

### Forge Coverage

```bash
# Summary report
forge coverage --report summary

# LCOV report (for visualization)
forge coverage --report lcov --report summary

# Filter to specific contracts
forge coverage --match-path "test/*" --report summary

# Coverage for attack tests only
forge coverage --match-path "test/attacks/*" --report summary
```

**Coverage Thresholds:**
| Contract Type | Line | Branch | Function |
|--------------|------|--------|----------|
| Critical (vault, core) | 100% | 95%+ | 100% |
| Core (helpers, libs) | 95%+ | 90%+ | 100% |
| Overall | 95%+ | 90%+ | 100% |

### Gambit (Mutation Testing)

```bash
# Generate mutants
gambit mutate --solc-remappings "@openzeppelin=node_modules/@openzeppelin" src/Vault.sol

# Run tests against mutants
gambit test --timeout 30
```

---

## Solodit / Finding Database (via MCP)

### Search for Similar Vulnerabilities

```
# Via claudit MCP (preferred — more features)
Call: mcp__claudit__search_findings
Args: {
  "keywords": "oracle manipulation stale price",
  "severity": ["HIGH", "CRITICAL"],
  "tags": ["Oracle"],
  "page_size": 10,
  "sort_by": "Quality"
}

# Via sc-auditor MCP
Call: mcp__sc-auditor__search_findings
Args: {
  "query": "oracle manipulation stale price",
  "severity": "High",
  "limit": 10
}
```

### Get Finding Details
```
Call: mcp__claudit__get_finding
Args: { "identifier": "64195" }
```

### Audit Checklist
```
# Full checklist
Call: mcp__sc-auditor__get_checklist
Args: {}

# Category-specific
Call: mcp__sc-auditor__get_checklist
Args: { "category": "Reentrancy" }
```

---

## Tool Execution Order

### Phase 1 (RECON) — Automated, Parallel:
1. `mcp__sc-auditor__run-slither` + `mcp__sc-auditor__run-aderyn` (parallel)
2. `mcp__sc-auditor__get_checklist` (parallel with above)
3. `bash: find` for scope discovery (parallel)

### Phase 3 (HUNT) — Per Function:
1. Review Slither/Aderyn results for specific function
2. `mcp__sc-auditor__get_checklist` with category filter
3. `mcp__claudit__search_findings` for similar real-world bugs

### Phase 5 (VALIDATE) — Per Finding:
1. Write PoC using poc-templates
2. `forge test --match-test test_exploit -vvv`
3. `mcp__claudit__search_findings` for supporting evidence

### Phase 6 (FUZZ) — Deep/Beast Only:
1. `forge test --match-path "test/fuzz/*" --fuzz-runs 10000`
2. `forge coverage --report summary`
3. `echidna-test . --test-limit 100000` (beast mode)
