# Pre-Hunt Vetting — Stage 0 supplement

> **Introduced in**: v0.6.0. Runs during Stage 0 (cost preview), after enumerate.sh but before user authorization.
> **Purpose**: Assess whether a bounty program is worth the audit investment. Evaluate reputation, treasury, rules fairness, payout history, and dispute record. Prevent pipeline budget waste on programs that don't pay out.
> **When to skip**: When no bounty URL is supplied AND `program-mode = generic`. When user explicitly opts out via `--skip-vetting`.

## Why this exists

The WhiteHatMage guide identifies pre-hunt vetting as a critical step most hunters skip: "Find a smaller bug first, report it, observe how the process goes, only then hunt deeper." The guide's ROI equation is explicit:

```
bounty income = P(exploit exists) × damage magnitude × P(fair treatment)
```

Argus's signal assessment (Stage 0.5) addresses the first term (P(exploit exists)). The cost preview (Stage 0) addresses the second term (damage magnitude) via depth-tier selection. But **nothing** addresses the third term: P(fair treatment). A program with a history of disputes, slow payouts, or scope games can nullify the ROI of a perfect audit.

This stage assesses P(fair treatment) before the pipeline commits serious budget.

## Stage contract

```
PRE-HUNT VETTING — Stage 0 supplement
INPUT:    bounty URL (user-supplied), program name, platform
OPERATIONS:
  1. Fetch bounty page (WebFetch) — extract rules, scope, payout ranges, response times
  2. Assess program reputation signals:
     - Payout history (published payouts, leaderboard presence)
     - Dispute history (search for "{program} dispute" on platform forums/social)
     - Response time patterns (from platform stats or community reports)
     - Scope change history (have they narrowed scope after receiving reports?)
  3. Assess treasury signals:
     - Public treasury size (if on-chain, query it)
     - Bounty budget (from program page: max payout × number of tiers)
     - Funding history (recent raises, runway indicators)
  4. Compute P(fair treatment) score
  5. Compute composite vetting score
  6. Surface red flags to user before Stage 0 authorization
OUTPUT:   $RUN_DIR/0-cost-preview/vetting.md
VERDICT:  GREEN (fair treatment likely) / YELLOW (some concerns) / RED (high risk — user must confirm)
EXIT CONDITION: vetting.md written with composite score and red flags surfaced.
```

## Vetting signals

### 1. Program reputation (REP)

| Level | Criteria |
|--------|----------|
| **GREEN** | Published payout leaderboard with amounts, ≥10 resolved reports, median payout time < 30 days, no public disputes, active program manager responding to reports |
| **YELLOW** | Some published payouts but < 10, payout times unclear, one or two minor disputes (resolved), program is new (< 6 months) |
| **RED** | No published payouts, known public disputes (unresolved or resolved against researcher), reports of scope-narrowing post-submission, program manager unresponsive, program is abandoned (no activity in 3+ months) |

**Signal sources** (in priority order):
1. Platform bounty page leaderboard / payout feed
2. Public reports on the platform (search for program name → resolved reports)
3. Social media search: "site:twitter.com {program} bounty dispute"
4. Forum search: platform's community forum for program complaints
5. Immunefi / HackenProof published stats (if available)

### 2. Scope clarity (SCOPE)

| Level | Criteria |
|--------|----------|
| **GREEN** | Explicit in-scope assets table with contract addresses / program IDs, explicit impact categories with examples, explicit exclusions, severity-to-payout table |
| **YELLOW** | Assets listed but no on-chain identifiers, impact categories described but no examples, exclusions vague ("other issues at our discretion") |
| **RED** | No in-scope assets listed (just "our smart contracts"), no severity-to-payout mapping, "at our sole discretion" language throughout, scope has changed ≥2 times in the last 6 months |

### 3. Payout structure (PAY)

| Level | Criteria |
|--------|----------|
| **GREEN** | Published severity-to-payout table with minimum payouts, Critical pays ≥$50k, High pays ≥$10k, known case studies of fair payouts |
| **YELLOW** | Published ranges but wide ("Critical: $5k-$100k"), minimum not specified, "based on our assessment" language |
| **RED** | No payout information, "competitive rewards", "swag + recognition" as primary reward, known cases of lowball downgrades (Critical → Medium with $500 payout) |

### 4. Trust establishment (EST)

| Level | Criteria |
|--------|----------|
| **GREEN** | Clear report → triage → payout pipeline, public security contact, past reports have public post-mortems, bug bounties are part of the project's culture (not a checkbox) |
| **YELLOW** | Security contact exists but no public post-mortems, program is new, process is undefined |
| **RED** | No security contact, no prior reports, program created "because the platform required it," GitHub issues asking "is this a bug?" go unanswered |

### 5. Treasury / sustainability (TRES)

| Level | Criteria |
|--------|----------|
| **GREEN** | On-chain treasury ≥$1M or known VC backing with public raise, active fee generation, ≥12 months runway |
| **YELLOW** | Treasury size unknown, recent raise but amount undisclosed, no on-chain treasury (points-based or off-chain protocol) |
| **RED** | Known treasury <$100k, project has no revenue, grants-based funding only, recent layoffs or team departures, token price in sustained decline |

## Composite vetting score

```
VETTING_SCORE = REP×0.35 + SCOPE×0.25 + PAY×0.20 + EST×0.15 + TRES×0.05

where GREEN=3, YELLOW=2, RED=1
```

| Score | Rating | Pipeline behavior |
|-------|--------|-------------------|
| ≥ 2.5 | **GREEN** — program is trustworthy | Proceed normally |
| 1.8–2.4 | **YELLOW** — some concerns | Proceed, but Stage 8 surfaces vetting flags; user should "test the waters with a small bug first" per the guide |
| < 1.8 | **RED** — high risk | AskUserQuestion to confirm: "This program has {N} red flags. Proceeding risks unrewarded effort. Continue?" |

## The "test the waters" strategy (GREEN and YELLOW programs)

For GREEN and YELLOW programs, the output recommends the guide's strategy:

> **Recommendation**: Before investing full pipeline budget, find and report ONE small bug (Low/Medium severity, clear impact, easy to verify). Observe the program's response: speed, fairness, communication quality. If the response is positive → proceed with full pipeline. If the response is negative or absent → the program failed the trust test at low cost to you.

This strategy is surfaced in the vetting output but not enforced — the user decides.

## Red flag categories

Each red flag gets a specific label so the user knows what they're accepting:

| Flag | Meaning |
|------|---------|
| `NO_PAYOUT_HISTORY` | Zero published payouts — no evidence the program ever paid anyone |
| `DISPUTE_HISTORY` | Known public disputes with researchers |
| `SCOPE_UNCLEAR` | Scope is vague, undefined, or has changed recently |
| `PAYOUT_UNCLEAR` | No published severity-to-payout mapping |
| `LOW_TREASURY` | Treasury/sustainability concerns |
| `PROGRAM_ABANDONED` | No program activity in ≥3 months |
| `SCOPE_GAMES` | Reports of post-submission scope narrowing |
| `LOWBALL_DOWNGRADES` | Known cases of severe downgrades with tiny payouts |
| `PROCESS_OPAQUE` | No published triage/resolution process |

## Output format

`$RUN_DIR/0-cost-preview/vetting.md`:

```markdown
# Pre-Hunt Vetting — <program-name>

**Date**: <date>
**Bounty URL**: <url>
**Platform**: <Immunefi / HackenProof / Cantina / Sherlock / Code4rena / Generic>

## Signal extraction

| Signal | Score | Evidence |
|--------|-------|----------|
| Reputation | YELLOW | 6 published payouts, median payout time 45 days, no disputes found, program is 8 months old |
| Scope clarity | GREEN | Explicit asset table with on-chain addresses, clear impact categories, severity-to-payout table published |
| Payout structure | YELLOW | Published ranges: Critical $25k-$100k, High $5k-$25k. No minimum specified. "Based on our assessment" language present. |
| Trust establishment | YELLOW | Security contact exists (security@project.io), no public post-mortems, program is relatively new |
| Treasury | GREEN | On-chain treasury $2.8M (solscan.io/account/...), active fee generation ~$15k/month |

## Composite

- **Vetting score**: 2.30 (YELLOW — some concerns)
- **Red flags**: None
- **Recommendation**: Proceed. The program has a moderate track record and clear scope. Recommend the "test the waters" strategy: report one Low/Medium finding first, observe the response, then commit full pipeline budget.

## Red flags

(None detected)

## Test-the-waters recommendation

Before investing full pipeline budget, consider finding and reporting ONE small bug first:
1. A Low-severity finding with clear impact and easy verification
2. Report it through the program's standard channel
3. Observe: response speed, communication quality, payout fairness
4. If positive → full pipeline. If negative → the program failed the trust test at low cost.
```

## Interaction with Stage 0 authorization

The vetting report is written BEFORE the Stage 0 AskUserQuestion:

1. Run enumerate.sh → cost preview
2. Run pre-hunt vetting (if bounty URL supplied)
3. Present AskUserQuestion with: cost preview + vetting score + red flags
4. User decides to proceed / reduce scope / cancel

This ensures the user has full information — cost AND trustworthiness — before authorizing the pipeline.

## What this stage must NOT do

- Do not refuse to audit RED programs. Flag them, but the user decides.
- Do not fabricate payout history. If data is unavailable, mark UNKNOWN — do not guess.
- Do not substitute platform reputation for program reputation. A program on Immunefi is not automatically trustworthy.
- Do not spend more than 3 WebFetch calls + 2 WebSearch calls on vetting. If the data isn't findable in 5 queries, mark UNKNOWN and move on.
