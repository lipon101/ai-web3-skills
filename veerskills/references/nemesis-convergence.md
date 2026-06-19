# VeerSkills Nemesis Convergence Loop

_Language-agnostic iterative dual-agent audit methodology adapted from Nemesis. Identifies deep logic bugs and structural desyncs across Solidity, Rust, Move, Python, Go, and TypeScript. Used in **beast mode** for maximum bug coverage._

---

## Overview

The Nemesis Convergence Loop alternates between two complementary audit perspectives up to a maximum of 6 passes until no new findings emerge. Each perspective catches bugs the other misses. Feynman finds logic bugs; State Auditor finds structural desyncs. Together in a loop, they cross-feed and converge on bugs neither could find solo.

```
PASS 1: Feynman Auditor (full run)
  Questions every line. Exposes assumptions. Flags suspects.

        | feed forward |

PASS 2: State Inconsistency Auditor (full run, enriched by Pass 1)
  Maps coupled state. Finds mutation gaps. Uses Feynman suspects as targets.

        | feed forward |

PASS 3+: Alternating targeted passes until convergence
  Each pass interrogates the previous pass's new findings.
  Convergence: 2 consecutive passes with zero new findings.
  Hard limit: 6 passes maximum.
```

---

## Pass 1: Feynman Auditor

**Core technique**: Explain every code choice as if teaching a student. When you cannot explain WHY something is done a certain way, you have found a potential bug.

### Per-Function Questioning Protocol

For each function, ask these 7 questions:

1. **"Why is this ordering chosen?"** — Could any two operations be swapped safely? If swapping causes a different outcome, is the current order correct?

2. **"Why is this guard present?"** — What specific attack does this `require`/modifier prevent? Can I bypass the guard through a different entry point?

3. **"Why is this guard ABSENT?"** — What would happen if an attacker supplied unexpected values? Zero, max uint, msg.sender == address(0), empty bytes?

4. **"What if I call this function when the system is in state X?"** — For each reachable system state (paused, mid-liquidation, during rebalance, during flash loan callback), does this function behave correctly?

5. **"Who else reads/writes this state variable?"** — Trace ALL other functions that touch the same storage slot. Is there a window where the value is stale or inconsistent?

6. **"What does the caller assume about the return value?"** — Does every caller handle all possible return cases (zero, max, revert, empty)?

7. **"What would happen if this external call reverts/returns garbage?"** — Is there error handling? Does the contract end up in an inconsistent state?

### Feynman Output Format

For each suspicious answer:
```
[FQ-{N}] "{question asked}" → {what the answer reveals}
├── Location: {file}:{line}
├── Concern: {specific worry, e.g. "state not updated before external call"}
├── Hypothesis: {what bug this could be}
└── Priority: {High / Medium / Low to investigate}
```

---

## Pass 2: State Inconsistency Auditor

**Core technique**: Map every coupled state pair in the system. Find every mutation path where one side updates without the other.

### Step 2.1: Build State Coupling Map

For every state variable, identify ALL variables it is **coupled to** (invariant relationship):

```
┌─────────────────┬───────────────────────┬──────────────────────┐
│ Variable A      │ Variable B            │ Invariant            │
├─────────────────┼───────────────────────┼──────────────────────┤
│ totalSupply     │ sum(balances[*])      │ A == B always        │
│ totalBorrowed   │ sum(debts[*])         │ A == B always        │
│ totalShares     │ sum(shares[*])        │ A == B always        │
│ collateralValue │ sum(collateral[*])    │ A >= B always        │
│ lastRewardTime  │ rewardPerToken        │ A changes → B must   │
│ price           │ healthFactor          │ A changes → B stale  │
└─────────────────┴───────────────────────┴──────────────────────┘
```

### Step 2.2: Trace ALL Mutation Paths

For each coupled pair (A, B):
1. Find ALL functions that modify A
2. For each: does it also modify B? If not → **GAP**
3. Find ALL functions that modify B
4. For each: does it also modify A? If not → **GAP**
5. Check: is there a window between A and B updates where the invariant is violated and an external call or read happens?

### Step 2.3: Cross-Feed from Feynman

Use Feynman suspects as **targeted starting points**:
- For each FQ flagged as High/Medium, map the state coupling around that code location
- Check if the Feynman concern relates to a state coupling gap
- A Feynman "why is this order chosen?" + a state coupling gap = strong finding candidate

### State Inconsistency Output Format

```
[SI-{N}] {State variable A} ↔ {State variable B} — GAP in {function}
├── Invariant: {A == B / A >= B / A changes implies B changes}
├── Mutation path: {function that updates A without B}
├── Window: {line range where invariant is violated}
├── Exploitable: {yes/no — can external call or read happen in window?}
├── Cross-feed: {related Feynman finding FQ-X or "none"}
└── Priority: {Critical / High / Medium}
```

---

## Convergence Rules

### Pass Alternation

| Pass | Agent | Scope | Input |
|------|-------|-------|-------|
| 1 | Feynman | Full codebase | None (cold start) |
| 2 | State Inconsistency | Full codebase | Pass 1 suspects |
| 3 | Feynman (targeted) | New SI findings only | Pass 2 new findings |
| 4 | State Inconsistency (targeted) | New FQ findings only | Pass 3 new findings |
| 5 | Feynman (targeted) | New SI findings only | Pass 4 new findings |
| 6 | State Inconsistency (targeted) | New FQ findings only | Pass 5 new findings |

### Convergence Criteria

**Stop when ANY of these is true**:
1. Two consecutive passes produce **zero new findings** (converged)
2. Maximum of **6 passes** reached (hard limit)
3. All new findings in a pass are duplicates of existing findings

### Finding Deduplication

Between passes:
- Same root cause = same finding (keep higher-confidence version)
- Same code location but different manifestation = separate findings
- Cross-feed confirmation (FQ + SI on same code) = merge with boosted confidence (+10)

---

## Agent Prompts

### Agent 6 (State Inconsistency): Spawn Prompt
```
You are a State Inconsistency Auditor. Your job is to find bugs caused by
coupled state variables that get out of sync. Map every state variable pair
that has an invariant relationship. For each pair, trace ALL mutation paths.
Find gaps where one variable updates without the other. When a gap exists
AND an external call or read happens in the window, you have found a bug.

You MUST use the Feynman suspects from the previous pass as targeted
starting points. Focus your state coupling analysis around code locations
flagged by the Feynman auditor.

Previous Feynman findings to cross-reference:
{paste FQ findings here}
```

### Agent 7 (Feynman, beast mode): Spawn Prompt
```
You are a Feynman Auditor. Your job is to find bugs by questioning every
code choice. For each function, ask the 7 Feynman questions. When you
cannot explain WHY something is done a certain way, you have found a
potential bug. Do not accept "it works" as an explanation — demand the
specific reason for every ordering, every guard, and every absence of a guard.

You MUST use the State Inconsistency findings from the previous pass as
targeted starting points. Focus your questioning around state coupling gaps
identified by the State Inconsistency auditor.

Previous State Inconsistency findings to cross-reference:
{paste SI findings here}
```

---

## Integration with VeerSkills Pipeline

The Nemesis Convergence Loop runs **after Phase 4 (ATTACK)** and **before Phase 5 (VALIDATE)** in beast mode only.

```
Phase 3: HUNT (vector scanning + systematic analysis)
Phase 4: ATTACK (deep exploit validation)
   ↓
Phase 4.5: NEMESIS CONVERGENCE LOOP (beast mode only)
   Pass 1: Feynman full sweep
   Pass 2: State Inconsistency full sweep + FQ cross-feed
   Pass 3-6: Alternating targeted passes until convergence
   Merge with Phase 4 findings (deduplicate by root cause)
   ↓
Phase 5: VALIDATE (PoC + reproducibility for all findings)
```

This ensures:
- Vector scanning (Phase 3) catches pattern-based bugs
- Deep analysis (Phase 4) catches context-specific bugs
- Nemesis loop (Phase 4.5) catches **logic bugs that neither pattern scanning nor single-pass analysis can find**
- All findings go through the same validation pipeline (Phase 5)
