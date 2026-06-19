# HackenProof — Judging + Triage Criteria

> Source: https://docs.hackenproof.com/bug-bounty/vulnerability-classification
> **Live page wins. Program-specific rules override these defaults.**

HackenProof's distinctive trait is its **mandatory triage gates**: PoC presence, scope match, commit/version match, and duplicate check happen *before* technical validation. A finding can be technically real and still rejected at triage if it fails any gate.

## Pre-validation gates (apply BEFORE technical validation)

### Gate 1 — Commit / version match
- Submission references a concrete commit hash, tag, or release
- Commit/version maps to in-scope repo / branch / deployment / audit target
- Mismatch → triage state `Need more info`, request exact commit evidence

### Gate 2 — Scope match
- Target asset in scope
- Reported impact category in scope for bounty eligibility
- Finding matches the equivalent classification track for the program type
- Excluded → mark `Out of scope` with explicit rule reference

### Gate 3 — Duplicate check
- Search for same root cause + same impacted component before deep validation
- Treat as duplicate only when BOTH root cause AND impact match an existing report
- Add `dup-{report_id}` label when marking `Duplicate`

### Gate 4 — PoC presence
- At least one usable PoC artifact (steps, payload, tx hash, video, logs, attachment)
- Missing → `Need more info`, request concrete PoC evidence

## Severity definitions

### Smart contract

| Level | Impacts |
|-------|---------|
| **Critical** | Direct theft, permanent freeze of funds/NFTs, governance manipulation, protocol insolvency, unauthorized mint/burn |
| **High** | Temporary freeze of funds/NFTs, theft / permanent freeze of unclaimed funds, high-impact oracle manipulation |
| **Medium** | Gas-theft patterns, OOG / CU exhaustion causing disruption / loss, DoS via state or gas abuse, griefing / no-profit attacks with protocol harm |
| **Low** | Under-delivery of promised returns due to logic flaws, low-risk uninitialized storage |

Privileged / admin-only attack paths may justify severity downgrade or disqualification.

### Blockchain protocol

| Level | Impacts |
|-------|---------|
| **Critical** | Protocol-level theft, permanent fund freeze, total network shutdown, consensus manipulation / chain split, hard-fork-required resolution |
| **High** | Node-crash DoS, temporary network tx freeze, temporary fund freeze |
| **Medium** | Subset-node DoS, protocol edge-case affecting dApps, timestamp / time manipulation, minor reorg abuse |
| **Low** | Non-critical shutdown of minority node set, low-impact fee miscalculation, low-impact gossip-layer issues |

### Web / mobile

| Level | Impacts |
|-------|---------|
| **Critical** | Payments manipulation, SQLi, RCE, command injection, business-logic causing fund/asset loss |
| **High** | Stored XSS, SSRF, wallet-linked subdomain takeover, major sensitive-data leakage, auth bypass, impactful IDOR / privilege escalation |
| **Medium** | Reflected XSS, non-wallet subdomain takeover, 2FA bypass, moderate sensitive-data leakage, CSRF with meaningful impact |
| **Low** | HTML injection, low-impact subdomain takeover, no-rate-limit on low-sensitivity endpoints, content spoofing, broken-link hijacking |

## Triage state taxonomy

| State | Use when |
|-------|----------|
| `New` | Not yet triaged |
| `In review` | Triager is actively validating |
| `Need more info` | A gate failed (commit, scope, dup, PoC) and is recoverable; reporter must supply evidence |
| `Triaged` | All gates passed and technical validation succeeded; severity assigned |
| `Out of scope` | Gate 2 failed and is not recoverable |
| `Duplicate` | Gate 3 found prior report with matching root cause + impact |
| `Informative` / `Not applicable` | Weak-impact findings that don't meet bounty criteria |
| `Spam` | Low-effort or auto-generated submissions without manual validation |

## Reversibility rule

**Prefer reversible actions (`Need more info`) over premature invalidation when uncertainty is material.** This is HackenProof-distinct discipline. Stage 6 in Argus inherits this — when the bounty page is HackenProof and the finding is borderline, default to `DOWNGRADE(refine)` over `KILL`.

## PoC requirements

Mandatory per Gate 4. The PoC must:
- Be readable / executable
- Demonstrate the impact
- Reference the in-scope commit/version

## Source of truth

1. Program rules from `get_program_info` / program page (primary)
2. HackenProof global classification baseline
3. CVSS fallback if classification ambiguous

## HackenProof platform-specific

### Reputation gating
Some programs require minimum reputation points to submit. Some use paid submissions (fee per report). Top researchers may receive special consideration.

### Dual Defence
Some programs are Dual Defence — only Critical with PoC pays.

### Audit contests
HackenProof also runs audit contests with pool-based payouts; rules differ from BB.
