# Solidity Audit Skill

A Codex skill for formal Solidity security reviews across mixed-protocol
codebases.

This repo is not a standalone scanner. It is a reusable skill package that
orchestrates contract discovery, protocol classification, module
clustering, specialized child-agent audits, and final finding synthesis.

It is built for audits that are too broad, too compositional, or too
cross-domain for a single generic review pass.

## Quick Start

### Install via AI CLI

If your agent supports skill installation from GitHub, use the shortest
path:

```text
Install skill https://github.com/zpano/solidity-audit/
```

To update later:

```text
update the solidity-audit skill to latest version from https://github.com/zpano/solidity-audit/
```

### Manual Install

Clone and symlink into your local skills directory:

```bash
git clone git@github.com:zpano/solidity-audit.git
export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
mkdir -p "$CODEX_HOME/skills"
ln -s /absolute/path/to/solidity-audit \
  "$CODEX_HOME/skills/solidity-audit"
```

Or clone and copy:

```bash
git clone git@github.com:zpano/solidity-audit.git
export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
mkdir -p "$CODEX_HOME/skills"
cp -R /absolute/path/to/solidity-audit \
  "$CODEX_HOME/skills/solidity-audit"
```

Restart Codex after installation so the skill registry reloads.

## How To Use

Use this skill when the target is a non-trivial Solidity codebase and you
want a formal or near-formal security review rather than a quick bug
triage.

Example prompt:

```text
Use the solidity-audit skill to review ./contracts and ./src.
Discover in-scope contracts, classify them by protocol, cluster modules,
audit high-risk paths, and write the final report under assets/findings/.
```

If you name specific files or folders, the skill treats those as the
primary review scope.

## When To Use It

Good fit:

- multi-contract Solidity systems
- codebases mixing DEX, Lending, Staking, Bridge, Governance, Oracle, and
  Vault behavior
- audits that need both a global findings list and per-module conclusions
- reviews where cross-module interactions matter as much as single-contract
  logic

Bad fit:

- single-function bug triage
- linting or style review
- gas-only review
- simple one-contract questions

## What It Does

The orchestrator in [SKILL.md](./SKILL.md)
drives a staged audit flow:

1. Discover in-scope Solidity contracts.
2. Build a conservative contract dependency and interaction graph.
3. Classify each contract into one or more protocol labels.
4. Identify complexity-heavy and liveness-critical paths.
5. Check active-lifecycle mutability and live dependency reads.
6. Cluster the system into coherent modules.
7. Build per-contract audit bundles.
8. Dispatch specialized child agents.
9. Merge results by `root_cause_key`.
10. Render final findings and module conclusions.

The core design choice is narrow, specialized child agents plus a strict
orchestrator, instead of a single broad prompt trying to do everything at
once.

## Supported Labels

The classifier currently routes contracts into:

- `DEX`
- `Lending`
- `Staking`
- `Bridge`
- `Governance`
- `Oracle`
- `Vault`
- `Generic`

Multi-label classification is allowed and expected.

## Architecture

The repository is split into layers so the audit process stays modular,
reusable, and explainable.

### 1. Orchestrator

[SKILL.md](./SKILL.md) defines:

- scope rules
- the staged audit workflow
- bundle composition
- agent routing
- the final output contract

### 2. Workflow Layer

`references/workflow/` contains process rules:

- `classification-rubric.md`
- `module-clustering.md`
- `complexity-feasibility.md`
- `active-draw-mutability.md`
- `judging.md`
- `report-format.md`
- `research-triangulation.md`

This is the layer that tells the skill how to reason consistently, not
just what to read.

### 3. Common Security Layer

`references/common/` contains reusable cross-protocol review lenses:

- access control
- custody and callbacks
- external integrations
- math and accounting
- upgradeability
- generic Solidity checks
- vulnerability taxonomy

### 4. Protocol Layer

`references/protocols/` contains protocol-specific review guides for:

- DEX
- Lending
- Staking
- Bridge
- Governance
- Oracle
- Vault
- Generic

These references also include high-frequency category cross-checks derived
from protocol-specific audit findings.

### 5. Agent Layer

`references/agents/` defines narrow child-agent contracts:

- `classifier-agent`
- `protocol-auditor-agent`
- `generic-auditor-agent`
- `cross-module-agent`
- `complexity-auditor-agent`
- `mutable-dependency-agent`
- `module-summarizer-agent`
- `aggregator-agent`

Each one has a small, specific responsibility. That is deliberate. It
keeps classification, finding generation, summarization, and aggregation
from bleeding into each other.

### 6. Script Layer

`scripts/` contains helper utilities used by the orchestrator:

- `discover-contracts.sh`
- `build-contract-graph.py`
- `build-audit-bundles.py`
- `merge-findings.py`

## Repository Layout

```text
solidity-audit/
|-- SKILL.md
|-- README.md
|-- references/
|   |-- agents/
|   |-- common/
|   |-- protocols/
|   `-- workflow/
|-- scripts/
|   |-- discover-contracts.sh
|   |-- build-contract-graph.py
|   |-- build-audit-bundles.py
|   `-- merge-findings.py
`-- assets/
    `-- findings/
```

## External Knowledge Sources

This skill now absorbs four external sources into local documents instead
of relying on those sources at runtime.

### `pashov/skills`

Source:
[github.com/pashov/skills](https://github.com/pashov/skills)

Absorbed as:

- cleaner public-skill install and update ergonomics in this README
- a more direct “install -> run -> update” user path for public skill repos

### `smart-contract-vulnerabilities`

Source:
[github.com/kadenzipfel/smart-contract-vulnerabilities](https://github.com/kadenzipfel/smart-contract-vulnerabilities)

Absorbed as:

- generic vulnerability classes in
  [vulnerability-taxonomy.md](./references/common/vulnerability-taxonomy.md)
- stronger cross-protocol grounding for access control, reentrancy,
  accounting, DoS, data handling, and unsafe logic classes

### `protocol-vulnerabilities-index`

Source:
[github.com/kadenzipfel/protocol-vulnerabilities-index](https://github.com/kadenzipfel/protocol-vulnerabilities-index)

Absorbed as:

- protocol-specific “high-frequency category cross-check” sections inside
  the local protocol guides
- stronger priority ordering for what must get an explicit pass in Bridge,
  DEX, Lending, Oracle, Staking, Vault, Governance, and Generic reviews

### `evmresearch`

Source:
[evmresearch.io/index](https://evmresearch.io/index)

Absorbed as:

- exploit-mechanic and edge-case routing in
  [research-triangulation.md](./references/workflow/research-triangulation.md)
- more explicit handling for hidden callbacks, stale approvals, router
  calldata abuse, proxy initialization races, compiler footguns, and
  process-layer failures

## Why The Source Absorption Matters

The audit loop now triangulates three knowledge layers:

- protocol identity and high-risk entry points
- generic vulnerability taxonomy
- exploit-mechanic and edge-case research

That matters because protocol-specific heuristics alone miss generic bug
classes, while generic taxonomies alone miss which classes are most common
for a given protocol type.

## Helper Script Usage

These scripts are optional building blocks. The main audit logic still
lives in `SKILL.md`.

### Discover Contracts

```bash
./scripts/discover-contracts.sh contracts src
```

By default this excludes common noise paths such as `lib/`, `test/`,
`tests/`, `mocks/`, `interfaces/`, `script/`, and `broadcast/`.

### Build A Contract Graph

```bash
./scripts/discover-contracts.sh contracts src | \
  python3 scripts/build-contract-graph.py
```

This produces JSON with declared contracts, imports, inheritance, and
basic neighbor relationships.

### Build Audit Bundles

```bash
python3 scripts/build-audit-bundles.py \
  --tasks-json tasks.json \
  --references-root references \
  --output-dir bundles
```

This renders downstream review bundles for child agents.

### Merge Findings

```bash
python3 scripts/merge-findings.py findings/*.json > merged.json
```

This keeps the highest-confidence version of each root cause and collects
module conclusions.

## Output Model

Intermediate child agents return JSON only.

The final merged output contains:

- `final_findings`
- `module_conclusions`

Each finding is expected to include:

- `title`
- `root_cause_key`
- `module_id`
- `labels`
- `location`
- `confidence`
- `severity`
- `broken_invariant`
- `description`
- `fix`
- `evidence`

If file output is requested, the final rendered report can be written under
`assets/findings/`.

## Scope Defaults

By default, the skill includes `.sol` source files and excludes common
noise such as:

- `lib/`
- `test/`
- `tests/`
- `mocks/`
- `interfaces/`
- `script/`
- `broadcast/`
- `*.t.sol`
- `*Test*.sol`
- `*Mock*.sol`

External dependencies are treated as context by default, not as findings
scope, unless the user explicitly includes them.

## Requirements

- Codex with local skill loading enabled
- `bash`, `find`, and standard Unix shell tools
- `python3` for the helper scripts
- a runtime that supports multi-agent orchestration for full use

## Limitations

- This repo is an orchestration skill, not a standalone security product.
- It is not designed for linting, style review, or gas-only review.
- It works best when child-agent execution and report synthesis are both
  available in the runtime.
- Final audit quality still depends on model quality, scope definition, and
  evidence discipline.
