# Immunefi — Bug Bounty — Judging Criteria

> Source: https://immunefi.com/immunefi-vulnerability-severity-classification-system-v2-3/
> **Live page wins. Each program defines its own scope/impacts and overrides defaults.**

## Severity definitions

| Level | Impacts |
|-------|---------|
| **Critical** | Direct theft of user funds (at-rest or in-motion); direct theft of NFTs; permanent freeze of funds/NFTs; unauthorized mint/burn; governance manipulation with direct outcome change; protocol insolvency; unintended alteration of NFT representation |
| **High** | Theft of unclaimed yield / royalties; permanent freeze of unclaimed yield / royalties; temporary freeze of funds / NFTs; oracle manipulation (on-chain price-feed influence) |
| **Medium** | Smart contract unable to operate due to lack of token funds; block stuffing; griefing without profit motive; theft of gas / CU; unbounded consumption; OOG / CU exhaustion; DoS via state or gas abuse |
| **Low** | Contract fails to deliver promised returns without value loss; uninitialized storage (potential privilege escalation, low risk frequently) |

CVSS fallback if no category fits.

## Automatic invalidators

(Subset — full Immunefi list is per-program; many programs add extras.)

| ID | Rule | Result |
|----|------|--------|
| AI-1 | Reporter already exploited the issue causing damage | INVALID |
| AI-2 | Requires leaked keys / credentials | INVALID |
| AI-3 | Requires admin / authority access without additional escalation | INVALID |
| AI-4 | External stablecoin depeg without attacker causing depeg via code bug | INVALID |
| AI-5 | Secrets on Github without proof of production use | INVALID |
| AI-6 | Best-practice recs without concrete impact | INVALID |
| AI-7 | Feature requests | INVALID |
| AI-8 | Incorrect data from third-party oracles (does not exclude oracle-manipulation / flash-loan attacks) | INVALID |
| AI-9 | Basic economic / governance attacks (51%) | INVALID |
| AI-10 | Lack of liquidity impacts | INVALID |
| AI-11 | Sybil-attack impacts | INVALID |
| AI-12 | Centralization risks (per default) | INVALID |
| AI-13 | Gas / CU optimizations | INVALID |
| AI-14 | Incorrect values in emitted events / logs | INVALID |
| AI-15 | Zero / default-address checks | INVALID |
| AI-16 | User-input validation against user mistakes (unless significant loss to others) | INVALID |
| AI-17 | Admin incorrect call order | INVALID |
| AI-18 | Admin action breaking assumptions | INVALID |
| AI-19 | Contract/Authority blacklisting affects protocol | INVALID |
| AI-20 | Front-running initializers without irreversible damage | INVALID |
| AI-21 | UX issues without fund loss | INVALID |
| AI-22 | User blacklisted by token, damage only to themselves | INVALID |
| AI-23 | Future opcode / CU repricing | INVALID |
| AI-24 | Accidental direct token transfer damaging only user | INVALID |
| AI-25 | Loss of airdrops / rewards not part of original design | INVALID |
| AI-26 | Incorrect values in view / query (unless feeding fund-handling) | INVALID |
| AI-27 | Stale prices / Chainlink / Pyth round completeness (except pull-based) | INVALID |
| AI-28 | Findings from previous audits acknowledged / wontfix | INVALID |
| AI-29 | Chain re-org / network liveness (unless attacker can force) | INVALID |
| AI-30 | Token unsafe-mint (recipient cannot accept) | INVALID |
| AI-31 | Future issues from integrations not mentioned in program | INVALID |
| AI-32 | Non-standard tokens (unless mentioned). 6-18 decimals NOT weird | INVALID |
| AI-33 | EVM / VM opcodes incompatible with network | INVALID |
| AI-34 | Sequencer / leader downtime | INVALID |
| AI-35 | Design decisions without fund loss | INVALID |
| AI-36 | Lack of storage gaps (simple) | INVALID |
| AI-37 | Theoretical vulnerabilities without proof / impact | INVALID |

## PoC requirements

**MANDATORY for all severities.** No PoC → no consideration, regardless of technical merit.

PoC must:
- Compile and execute successfully
- Demonstrate concrete impact
- Use realistic conditions (no arbitrary balances or impossible states)

## Quality signals

| Signal | Full credit | Partial / downgrade | Invalidation risk |
|--------|------------|---------------------|-------------------|
| PoC | Compiles, executes, real impact, realistic | Compiles but unrealistic | Critical — no PoC = auto-reject |
| Root cause | In-scope code | Symptom only | High |
| Impact demonstration | Concrete numbers | Unquantified | High |
| Severity alignment | Matches specific impact list | Lower-tier impact claimed higher | High |
| Attack path | Step-by-step with realistic conditions | Partial | Moderate |
| Remediation | Present and correct | Wrong / missing | Low |

Key emphasis:
- **PoC is everything.** Perfect writeup without PoC → reject.
- Match impact to EXACT impact list for the severity. "Direct theft" is Critical. "Theft of unclaimed yield" is High. Don't confuse them.
- Each program can override defaults. Always check program-specific scope.

## Immunefi platform-specific

### Program primacy
Each program can define its own severity levels and impact lists overriding defaults. Some programs only accept Critical / High. Always review the specific program page before submitting.

### First-reporter priority
First reporter has priority on duplicates.
