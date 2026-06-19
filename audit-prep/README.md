# audit-prep — Solidity Audit Preparation

Prepare a Solidity project for a security audit. Runs an 8-phase automated readiness check across your codebase and produces a scored report with actionable findings.

Supports **Foundry** and **Hardhat** projects.

## Phases

| Phase | What it checks |
|-------|---------------|
| 1. Test Coverage | Branch/line coverage, untested contracts, compiler warnings |
| 2. Test Quality | Assertion density, edge cases, negative tests, integration tests |
| 3. Documentation | NatSpec coverage, stale @param tags, missing @return |
| 4. Code Hygiene | TODOs, console imports, floating pragmas, unused imports, error consistency |
| 5. Dependencies | Outdated packages, CVEs, uninitialized submodules, patched deps |
| 6. Best Practices | SafeERC20, CEI pattern, reentrancy guards, access control, upgradeable patterns |
| 7. Deployment | Build/test pass, deploy scripts, verification setup, .env.example |
| 8. Project Docs | Architecture overview, trust assumptions, invariants, known issues, scope definition |

## Architecture

3 parallel agents for focused analysis and fast results:

| Agent | Phases | Focus |
|-------|--------|-------|
| A — Testing | 1, 2 | Test coverage and quality metrics |
| B — Source Analysis | 3, 4, 6 | NatSpec, hygiene, best practices (Grep-based, no full source in context) |
| C — Infrastructure | 5, 7, 8 | Dependencies, deployment, project documentation |

## Usage

Run the full pipeline:

```
/audit-prep
```

Or use natural language:

```
prepare this project for audit
```

### Single Phase

```
/audit-prep coverage
/audit-prep quality
/audit-prep docs
/audit-prep hygiene
/audit-prep deps
/audit-prep practices
/audit-prep deploy
/audit-prep context
```

### Options

Auto-fix common issues (NatSpec stubs, console removal, pragma locking, SafeERC20 wrapping):

```
/audit-prep --fix
```

Save the report to a file:

```
/audit-prep --report audit-prep-report.md
```

Run static analysis only:

```
/audit-prep scan
```

Skip the static analysis prompt:

```
/audit-prep --no-scan
```

CI mode (JSON output, exits with score check):

```
/audit-prep --ci --min-score 75
```

Scope to recent changes only:

```
/audit-prep --diff main
```

### Static Analyzers

After the report, the skill offers to run:

- **Slither** — static analysis for Solidity
- **Aderyn** — Rust-based static analyzer
- **Pashov Solidity Auditor** — AI-powered audit skill

Scanner findings are informational and do not affect the audit-prep score.

## Scoring

Each phase scores 0-100. The overall score is a weighted average:

| Verdict | Score |
|---------|-------|
| Audit Ready | 90-100 |
| Almost Ready | 75-89 |
| Needs Work | 50-74 |
| Not Ready | < 50 |

## Install

```bash
ln -s ~/cdsecurity-skills/audit-prep ~/.claude/skills/audit-prep
```
