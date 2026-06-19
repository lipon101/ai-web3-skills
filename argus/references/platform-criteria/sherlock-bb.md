# Sherlock — Bug Bounty — Judging Criteria

> Source: https://docs.sherlock.xyz/bug-bounties/criteria-for-bug-bounty-reports-validity
> **Live page wins. Each program may override defaults.**

## Severity definitions

| Level | Impacts |
|-------|---------|
| **Critical** | Direct theft of user funds (at-rest or in-motion); direct theft of NFTs; permanent freeze of funds/NFTs; unauthorized mint/burn; governance hijack with direct outcome change; protocol insolvency; unintended NFT representation alteration |
| **High** | Theft of unclaimed yield / royalties; permanent freeze of unclaimed yield / royalties; temporary freeze of funds/NFTs; oracle manipulation with on-chain price-feed influence |
| **Medium** | Smart contract unable to operate due to lack of token funds; block stuffing; griefing (no profit motive, but damage); theft of gas / CU; unbounded gas / CU consumption; gas limit / OOG / CU exhaustion; DoS via state or gas abuse |
| **Low** | Contract fails to deliver promised returns but does not lose value; uninitialized storage variables (potential privilege escalation but frequently low risk) |

If issue does not fit any category, CVSS fallback.

## Automatic invalidators

| ID | Rule | Result |
|----|------|--------|
| AI-1 | Reporter already exploited the issue causing damage | INVALID |
| AI-2 | Requires access to leaked keys / credentials | INVALID |
| AI-3 | Requires access to privileged addresses (admin / authority) without additional privilege escalation | INVALID |
| AI-4 | External stablecoin depeg without attacker directly causing depeg through code bug | INVALID |
| AI-5 | Secrets / API keys / private keys on Github without proof of production use | INVALID |
| AI-6 | Best-practice recommendations without concrete impact | INVALID |
| AI-7 | Feature requests | INVALID |
| AI-8 | Incorrect data from third-party oracles (does not exclude oracle manipulation / flash-loan) | INVALID |
| AI-9 | Basic economic / governance attacks (51%) | INVALID |
| AI-10 | Lack of liquidity impacts | INVALID |
| AI-11 | Sybil-attack impacts | INVALID |
| AI-12 | Centralization risks (per default) | INVALID |
| AI-13 | Gas / CU optimizations | INVALID |
| AI-14 | Incorrect values in emitted events / logs | INVALID |
| AI-15 | Zero / default-pubkey checks | INVALID |
| AI-16 | User-input validation to prevent user mistakes (unless significant loss to others) | INVALID |
| AI-17 | Admin incorrect call order | INVALID |
| AI-18 | Admin action breaking code assumptions | INVALID |
| AI-19 | Contract / authority blacklisting affects protocol functionality | INVALID |
| AI-20 | Front-running initializers without irreversible damage | INVALID |
| AI-21 | UX issues without fund loss | INVALID |
| AI-22 | User blacklisted by token, damage only to themselves | INVALID |
| AI-23 | Future opcode / CU repricing | INVALID |
| AI-24 | Accidental direct token transfer damaging only the user | INVALID |
| AI-25 | Loss of airdrops / rewards not part of original design | INVALID |
| AI-26 | Incorrect values in view / query functions (unless feeding fund-handling functions with real loss) | INVALID |
| AI-27 | Stale prices / round completeness (except pull-based oracles like Pyth) | INVALID |
| AI-28 | Findings from previous audits marked acknowledged / wontfix | INVALID |
| AI-29 | Chain re-org / network liveness (unless attacker can force) | INVALID |
| AI-30 | Token unsafe-mint (recipient cannot accept) | INVALID |
| AI-31 | Future issues from integrations not mentioned in program | INVALID |
| AI-32 | Non-standard tokens (unless mentioned in program). 6-18 decimals NOT weird | INVALID |
| AI-33 | EVM / VM opcodes incompatible with network | INVALID |
| AI-34 | Sequencer / leader downtime | INVALID |
| AI-35 | Design decisions without fund loss | INVALID |
| AI-36 | Lack of storage gaps (simple) | INVALID |
| AI-37 | Theoretical vulnerabilities without proof or impact demonstration | INVALID |

## PoC requirements

**PoC is MANDATORY for all severities.** Without PoC → finding will not be considered, regardless of technical merit.

PoC must:
- Compile and execute successfully
- Demonstrate concrete impact (not just prove a function can be called)
- Use realistic conditions

## Quality signals

| Signal | Full credit | Partial / downgrade | Invalidation risk |
|--------|------------|---------------------|-------------------|
| PoC | Compiles, executes, demonstrates real impact | Compiles but unrealistic / partial | Critical — no PoC = auto-reject |
| Root cause | In-scope code | Symptom only | High |
| Impact demonstration | Concrete numbers showing economic damage | Unquantified | High |
| Severity alignment | Matches specific impact list | Lower-tier impact claimed at higher tier | High |
| Attack path | Step-by-step with realistic conditions | Partial / unrealistic | Moderate |
| Remediation | Present and correct | Wrong / missing | Low |

Key emphasis:
- **The PoC is everything.** Perfect writeup without PoC will be rejected.
- Match impact to EXACT impact list for severity claimed.
- Each program can override defaults — always check program-specific scope.

## Sherlock BB platform-specific

- **Timestamp priority**: first submission wins. Duplicates are NOT rewarded.
- **Bug Bounty page is source of truth**, not README.
