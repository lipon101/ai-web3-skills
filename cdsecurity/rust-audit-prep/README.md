# rust-audit-prep — Rust/Solana Audit Preparation

Prepare a Rust on-chain program for a security audit. Runs a 5-phase automated readiness check and produces a scored report with actionable findings.

Supports **Anchor** and **native `solana_program`** projects.

## Phases

| Phase | What it checks |
|-------|---------------|
| 1. Test Coverage | Inline #[cfg(test)], external test suites (TS/JS/Rust), handler-to-test mapping |
| 2. Documentation | /// doc comments on handlers, state structs, calc functions, error enums |
| 3. Code Hygiene | TODOs, println!/dbg!, unsafe blocks, unwrap() on user input, overflow-checks, as casts |
| 4. Dependencies | CVEs via cargo audit, Cargo.lock, yanked crates, forked deps, version analysis |
| 5. Best Practices | Account validation, CPI safety, Token/SPL checks, Token-2022 extensions, arithmetic safety, events |

## Architecture

3 parallel agents for focused analysis and fast results:

| Agent | Phases | Focus |
|-------|--------|-------|
| A — Testing | 1, 2 | Test coverage across all sources + documentation quality |
| B — Source Analysis | 3, 5 | Code hygiene + best practices (Grep-based, targeted queries per check) |
| C — Infrastructure | 4 | Dependencies, Cargo.lock, CVEs, version health |

## Usage

Run the full pipeline:

```
/rust-audit-prep
```

Or use natural language:

```
prepare this Solana project for audit
```

The skill will ask you to select a source:

- **Current directory** — use the cwd
- **Local path** — provide a path to a local project
- **GitHub repo** — provide a URL, the skill clones it automatically

### Single Phase

```
/rust-audit-prep coverage
/rust-audit-prep docs
/rust-audit-prep hygiene
/rust-audit-prep deps
/rust-audit-prep practices
```

### Options

Save the report to a file:

```
/rust-audit-prep --report audit-prep-report.md
```

Auto-fix common issues (doc stubs, println! removal, overflow-checks addition):

```
/rust-audit-prep --fix
```

Run static analysis only:

```
/rust-audit-prep scan
```

### Static Analyzers

After the report, the skill offers to run:

- **Trident** — fuzz testing framework for Solana programs
- **Soteria** — static analysis for Anchor programs
- **cargo-geiger** — measure unsafe Rust usage across the dependency tree

Scanner findings are informational and do not affect the audit-prep score.

## Best Practices Checklist

Phase 5 checks every item from a comprehensive checklist covering:

**Account Validation (Anchor):** Signer checks, owner/discriminator checks, PDA seed constraints, has_one validation, init_if_needed, UncheckedAccount justification, pubkey-without-signer anti-pattern

**Account Validation (Native):** is_signer, owner checks, discriminator validation, canonical PDA bumps, account revival prevention

**CPI Safety:** Program ID verification, post-CPI reload, signer privilege forwarding

**Token & SPL:** Typed token program accounts, mint/authority validation, close cleanup

**Token-2022 Extensions:** Transfer Hook validation, Permanent Delegate rejection, Confidential Transfer gaps, Transfer Fee accounting, extension enumeration

**Arithmetic Safety:** Overflow protection, division ordering, cast safety (as narrowing), floating-point rejection, rounding direction

**Rust Quality:** unwrap() on user input, stack size, array indexing, custom errors, event emissions, emergency pause

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
ln -s ~/cdsecurity-skills/rust-audit-prep ~/.claude/skills/rust-audit-prep
```
