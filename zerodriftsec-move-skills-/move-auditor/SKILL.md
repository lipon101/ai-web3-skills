---
name: move-auditor
description: Security audit of Move code (Sui / Aptos). Auto-detects platform. Trigger on "audit", "check this contract", "review for security". Modes - default (full repo) or a specific filename.
---

# Move Smart Contract Security Audit

You are the orchestrator of a parallelized Move security audit.

## Mode Selection

**Exclude pattern:** skip directories `tests/`, `examples/`, `doc/`, `scripts/` and files matching `*_test.move`, `*Test*.move` or `*Mock*.move`.

- **Default** (no arguments): scan all `.move` files using the exclude pattern. Use Bash `find` (not Glob).
- **`$filename ...`**: scan the specified file(s) only.

**Flags:**

- `--file-output` (off by default): also write the report to a markdown file (path per `skills/validation/SKILL.md`). Never write a report file unless explicitly passed.

## Orchestration Flow

### Turn 0 — Banner

Print the banner:

```bash
bash scripts/banner.sh
```

### Turn 1 — Detect Platform

Run the detection script:

```bash
python3 scripts/detect-platform.py <project_path>
```

This recursively scans for `Move.toml` files and checks their dependencies:
- `MystenLabs/sui.git` → `sui`
- `aptos-labs/aptos-core.git` → `aptos`

Store the result as `{platform}`.

### Turn 2 — Discover

Make these parallel tool calls in one message:

a. Bash `find` for in-scope `.move` files per mode selection and exclude pattern.
b. Read `skills/validation/SKILL.md`
c. Bash `mktemp -d /tmp/move-audit-XXXXXX` → store as `{bundle_dir}`

If no `.move` files found, print: `No Move source files found.` and stop.

### Turn 3 — Prepare

Build all bundles in a single Bash command using `cat`:

1. `{bundle_dir}/source.md` — ALL in-scope `.move` files, each with a `### path/to/file.move` header and fenced code block.

2. Agent bundles = `source.md` + common references + agent definition + platform-specific skill modules:

Every bundle includes the two common references:
- `skills/move-auditor/references/common/move-language.md`
- `skills/move-auditor/references/common/move-vulnerabilities.md`

**Common bundles (all platforms):**

| Bundle | Agent Definition | Appended skill modules (relative to `skills/move-auditor/references/{platform}/`) |
|--------|-----------------|---------------------------------------------------------------------|
| `agent-1-bundle.md` | `agents/ability-type-safety-agent.md` | `ability-analysis.md` + `type-safety.md` |
| `agent-3-bundle.md` | `agents/flash-loan-allocation-agent.md` | `flash-loan-interaction.md` + `share-allocation-fairness.md` |
| `agent-4-bundle.md` | `agents/token-flow-zero-state-agent.md` | `token-flow-tracing.md` + `zero-state-return.md` |
| `agent-5-bundle.md` | `agents/centralization-roles-agent.md` | `centralization-risk.md` + `semi-trusted-roles.md` |
| `agent-6-bundle.md` | `agents/oracle-staleness-agent.md` | `oracle-analysis.md` + `temporal-parameter-staleness.md` |
| `agent-8-bundle.md` | `agents/migration-crosschain-agent.md` | `migration-analysis.md` + `cross-chain-timing.md` |

**Platform-specific bundles:**

| Bundle | Platform | Agent Definition | Appended skill modules (relative to `skills/move-auditor/references/`) |
|--------|----------|-----------------|----------------------------------------------------------------------|
| `agent-2-bundle.md` | **Sui** | `agents/ownership-composability-agent.md` | `sui/object-ownership.md` + `sui/ptb-composability.md` |
| `agent-2-bundle.md` | **Aptos** | `agents/ownership-composability-agent.md` | `aptos/reentrancy-analysis.md` + `aptos/ref-lifecycle.md` |
| `agent-7-bundle.md` | **Sui** | `agents/dependency-ecosystem-agent.md` | `sui/dependency-audit.md` + `sui/package-version-safety.md` |
| `agent-7-bundle.md` | **Aptos** | `agents/dependency-ecosystem-agent.md` | `aptos/dependency-audit.md` + `aptos/fungible-asset-security.md` |

```
cat source.md references/common/move-language.md references/common/move-vulnerabilities.md references/{platform}/CORE_VULNERABILITIES.md references/{platform}/{platform-vuln-file}.md agents/{agent-file}.md references/{platform}/{skill-1}.md references/{platform}/{skill-2}.md agents/shared-rules.md > agent-N-bundle.md
```

- `{platform-vuln-file}` = `SUI_VULNERABILITIES.md` for Sui, `APTOS_VULNERABILITIES.md` for Aptos.

Append `agents/shared-rules.md` to every bundle.

Print line counts for every bundle and `source.md`. Do NOT inline file content into agent prompts.

### Turn 4 — Run Specialists

In one message, spawn all 8 specialists as parallel foreground Agent calls. Prompt template:

```
Your bundle file is {bundle_dir}/agent-N-bundle.md (XXXX lines).
The bundle contains all in-scope source code, your agent instructions, specialized methodology, and shared rules.
Read the bundle fully before producing findings.
Focus on {platform}-specific ability and type safety / ownership / flash loan / token flow / access control / oracle / dependency / migration.
```

Each agent reads its bundle and independently produces FINDINGs and LEADs per the specialist output format.

### Turn 5 — Depth Analysis

After all breadth agents return, assess which findings warrant deeper analysis. For each breadth finding that meets depth trigger criteria:

| Depth Agent | Trigger |
|-------------|---------|
| `depth-token-flow-agent` | Token balance, transfer, withdrawal, accounting patterns |
| `depth-state-trace-agent` | Multi-function state mutation, constraint violations |
| `depth-edge-case-agent` | Boundary conditions, zero-state, dust, first/last participant |
| `depth-external-agent` | External calls, cross-chain, oracle dependencies, MEV |

Spawn relevant depth agents in parallel. Each receives source + specific findings + agent definition from `agents/`.

If no breadth findings meet depth trigger criteria, skip this turn entirely.

### Turn 6 — Deduplicate, Validate & Report

Single-pass: deduplicate all breadth + depth results, gate-evaluate, and produce the final report in one turn.

#### 1. Deduplicate

Parse every FINDING and LEAD from all agents. Group by `group_key` field (format: `Module | function | bug-class`). Exact-match first; then merge synonymous bug_class tags. Keep best version per group, number sequentially, annotate `[agents: N]`.

#### 2. Gate Evaluation

Run each finding through the four gates defined in `skills/validation/SKILL.md`.

#### 3. Confidence Scoring

Apply confidence scoring per `skills/validation/SKILL.md`.

#### 4. Lead Promotion

- Promote LEAD → FINDING (confidence 75) if: complete exploit chain traced, OR `[agents: 2+]` flagged same issue, OR depth agent confirmed.
- No deployer-intent reasoning — evaluate what the code _allows_.

#### 5. Fix Verification (confidence >= 80 only)

Trace the attack with fix applied; verify no new DoS, reentrancy, or broken invariants.

#### 6. Format and Print

Format per `skills/validation/SKILL.md`. Exclude rejected items. If `--file-output`: also write to file.

## Vulnerability Categories

### Sui-Specific (S1–S10)

| ID | Category | Severity | Description |
|----|----------|----------|-------------|
| S1 | Object Ownership Bypass | CRITICAL | Unauthorized object transfer via public_transfer |
| S2 | Shared Object Manipulation | CRITICAL | Race conditions in shared objects |
| S3 | PTB Composition Attacks | HIGH | Malicious transaction block composition |
| S4 | Kiosk Exploitation | HIGH | Bypass kiosk rules/policies |
| S5 | Dynamic Field Abuse | HIGH | Unauthorized field access/modification |
| S6 | Transfer Policy Bypass | HIGH | Circumventing transfer restrictions |
| S7 | Capability Leakage | HIGH | AdminCap/OwnerCap transferred to unauthorized parties |
| S8 | Witness Pattern Abuse | CRITICAL | Improper one-time witness validation |
| S9 | Improper Abilities | CRITICAL | copy/drop on asset types |
| S10 | Upgrade Cap Mishandling | HIGH | Package upgrade authorization issues |

### Aptos-Specific (A1–A10)

| ID | Category | Severity | Description |
|----|----------|----------|-------------|
| A1 | Signer Validation Bypass | CRITICAL | Missing signer checks in privileged functions |
| A2 | Account Resource Abuse | HIGH | Unauthorized move_to/borrow_global access |
| A3 | Event Handle Manipulation | MEDIUM | Missing or forged event emissions |
| A4 | FungibleAsset Vulnerabilities | HIGH | Improper FA handling, Ref leakage |
| A5 | Table/SmartVector Issues | MEDIUM | Unbounded storage, DoS vectors |
| A6 | Multi-Signature/Auth Key | MEDIUM | Auth key rotation, replay attacks |
| A7 | Capability Leakage | HIGH | SignerCapability transfer issues |
| A8 | Witness Pattern Abuse | CRITICAL | Improper witness validation |
| A9 | Improper Abilities | CRITICAL | copy/drop on asset types |
| A10 | Reentrancy (Move 2.2+) | HIGH | Dynamic dispatch, FA hooks |

## Detection Commands

### Sui

```bash
# Find object definitions and transfers
rg "public struct.*has key" sources/
rg "sui::transfer::public_transfer|public_share_object" sources/

# Find shared objects
rg "sui::transfer::share_object|shared_object" sources/

# Find kiosk operations
rg "sui::kiosk" sources/

# Find dynamic fields
rg "sui::dynamic_field|dynamic_object_field" sources/

# Find capabilities
rg "AdminCap|OwnerCap|UpgradeCap" sources/

# Find witness patterns
rg "Witness|witness|has drop" sources/
```

### Aptos

```bash
# Find signer usage
rg "signer|signer::address_of" sources/

# Find entry functions
rg "public entry fun|entry fun" sources/

# Find resource operations
rg "move_to|move_from|borrow_global|exists" sources/

# Find FungibleAsset operations
rg "fungible_asset::|FungibleAsset" sources/

# Find event emissions
rg "event::emit|emit_event" sources/

# Find capabilities
rg "SignerCapability|MintRef|BurnRef|TransferRef" sources/

# Find witness patterns
rg "Witness|witness|has drop" sources/
```

## Skill Modules Reference

The following specialized skill modules are available. Files in `references/common/` apply to all platforms; files in `references/{platform}/` are loaded based on detected platform.

### Common (always loaded)

| Module | Location | Purpose |
|--------|----------|---------|
| move-language | `references/common/` | Comprehensive Move language reference |
| move-vulnerabilities | `references/common/` | Cross-platform Move vulnerability catalog (M1–M8) |

### Per-Platform Modules (`references/{platform}/`)

| Module | Trigger | Purpose |
|--------|---------|---------|
| CORE_VULNERABILITIES | Always | 8 core Move vulnerabilities with vulnerable/secure code |
| {PLATFORM}_VULNERABILITIES | Always | Platform-specific vulnerability categories |
| ability-analysis | Always | Analyze struct abilities (copy/drop/key/store) |
| attack-vectors | Always | Attack vector catalog with detection patterns |
| bit-shift-safety | Always | Check shift operations for DoS |
| centralization-risk | Capabilities detected | Analyze privilege concentration |
| cross-chain-timing | Bridge patterns | Cross-chain message validation |
| dependency-audit | External deps | Third-party dependency audit |
| economic-design-audit | Monetary params | Economic parameter analysis |
| external-precondition-audit | External calls | External module precondition analysis |
| flash-loan-interaction | Flash loan patterns | Flash loan attack surface |
| fork-ancestry | Recon phase | Known fork vulnerability patterns |
| migration-analysis | Upgrade patterns | Package upgrade / migration safety |
| oracle-analysis | Oracle usage | Oracle staleness/manipulation |
| semi-trusted-roles | Keeper/operator roles | Role-based attack vectors |
| share-allocation-fairness | Share minting | Allocation fairness analysis |
| temporal-parameter-staleness | Multi-step ops | Cached parameter staleness |
| token-flow-tracing | Balance operations | Token flow accounting |
| type-safety | Generics usage | Generic type constraints |
| verification-protocol | Verification phase | Move test verification |
| zero-state-return | First depositor | Zero state edge cases |

### Sui-Only Modules (`references/sui/`)

| Module | Trigger | Purpose |
|--------|---------|---------|
| object-ownership | Always | Object lifecycle audit |
| ptb-composability | Always (Sui) | PTB atomic composition risks |
| package-version-safety | UpgradeCap | Package upgrade risks |

### Aptos-Only Modules (`references/aptos/`)

| Module | Trigger | Purpose |
|--------|---------|---------|
| reentrancy-analysis | Dynamic dispatch | Move 2.2+ reentrancy vectors |
| ref-lifecycle | Ref types | Object Ref lifecycle audit |
| fungible-asset-security | FA patterns | FungibleAsset standard audit |
