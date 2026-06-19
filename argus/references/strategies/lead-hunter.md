# Lead Hunter Strategy — novel vulnerability class research

> **Archetype**: Lead Hunter (WhiteHatMage guide § "Lead Hunter — the trailblazer")
> **Introduced in**: v0.6.0
> **When triggered**: User explicitly selects `--strategy lead-hunter` at Stage 0, OR VERY-HIGH bug density prediction on a target with novel consensus/crypto/VM
> **Goal**: Discover entirely new classes of vulnerabilities through deep understanding of one system, then generalize to a reusable attack pattern.
> **Pairs with**: Scientist (custom tooling amplifies the Lead Hunter's deep analysis)

## The Lead Hunter insight

The WhiteHatMage guide describes the Lead Hunter as the hardest but highest-ROI archetype: a hunter who "discovers entirely new classes of vulnerabilities" through "deep understanding of one system" that generalizes to "a new attack class." This is not about finding instances of known bug patterns — it's about creating the pattern.

The guide notes that Lead Hunter "only works with Scientist-type support" — the custom tooling amplifies the deep analysis. A Lead Hunter without tooling is just a Digger with more ambition. A Lead Hunter with a Scientist partner finds bugs nobody else can.

Lead Hunter formalizes this within Argus: a strategy that takes ONE system, builds a deep mental model, identifies its unique assumptions, and then asks "what else makes these same assumptions?" This is the opposite of Argus's standard breadth-first approach — it's depth-first on one system, then breadth on the class.

## Pipeline modifications

### Pre-Stage 1: System selection

Lead Hunter picks ONE subsystem to go deep on. Not the whole codebase — one component with novel properties:

```
SELECT the single most novel subsystem in the target:
  1. Does it implement a mechanism with no prior-art deployments? → THIS IS THE TARGET
  2. Does it use a novel cryptographic primitive? → THIS IS THE TARGET
  3. Does it implement a consensus variant that differs from standard (Tendermint, Nakamoto, HotStuff)? → THIS IS THE TARGET
  4. Does it handle cross-domain state (L1↔L2, chain↔off-chain) with a novel relay/verification scheme? → THIS IS THE TARGET
  5. Otherwise: the subsystem with the highest innovation score from Stage 0.5
```

Everything else in the codebase is secondary — the Lead Hunter exhausts the selected subsystem first.

### Stage 1: Deep threat model (single subsystem)

Full 6-step threat model, but ONLY for the selected subsystem:

1. **Actors**: Only actors that interact with this subsystem
2. **Trust boundaries**: Only boundaries this subsystem crosses
3. **Attack surface**: All 10 surface points, but scoped to this subsystem's code
4. **Entry points**: Every entry point into this subsystem (including internal calls from other subsystems)
5. **Invariants**: Every invariant this subsystem maintains — doc-stated AND inferred from code structure
6. **Hot zones**: Every function in this subsystem is a hot zone

The key addition: **Assumption extraction**. For each invariant, extract:
- What other code relies on this invariant?
- What would break if this invariant were violated?
- Is this invariant also assumed by OTHER systems (outside the target)?

### Stage 2: Deep single-angle analysis

A single "Lead Hunter" agent, NOT the standard 10-angle set. The agent gets 4× the context budget of a standard angle:

```
You are the Lead Hunter. Your mission is to discover a NOVEL vulnerability class
in <subsystem>. This is not about finding bugs — it's about understanding the
system deeply enough to see what EVERYONE ELSE missed.

## Phase 1: Exhaustive assumption mapping

For EVERY state-changing function in this subsystem, enumerate:
1. Input assumptions (what must be true about parameters?)
2. State assumptions (what must be true about current state?)
3. Ordering assumptions (what must happen before/after?)
4. Identity assumptions (who must call this? who must NOT call this?)
5. Arithmetic assumptions (what relationships between values are maintained?)
6. External assumptions (what does this function assume about external state?)

## Phase 2: Assumption violation

For EACH assumption:
1. Violate it. What actor? What input? What ordering?
2. Trace the violation. Does it cascade? Where does it terminate?
3. Classify the terminal outcome:
   - EXPLOITABLE: fund loss, state corruption, privilege escalation
   - NOVEL_CLASS: this pattern does not exist in any known vulnerability taxonomy
   - KNOWN_CLASS: this is an instance of a known pattern (list which one)
   - DEGRADATION: liveness/availability impact only
   - COSMETIC: no impact
   - SAFE: violation is caught elsewhere

## Phase 3: Class generalization

For each NOVEL_CLASS outcome:
1. What is the ABSTRACT pattern? (Not "bug in function X with parameter Y" —
   "systems that {assumption} fail to account for {violation mechanism}")
2. What language features / runtime behaviors enable this class?
3. What prior art is CLOSEST to this class? (Search RAG for similar patterns)
4. How would you DETECT this class in another codebase? (What would you grep for?)
5. Can you write a STATIC CHECK that catches instances of this class?

## Phase 4: Cross-system search

For each generalized class:
1. Search the rest of the target codebase for instances of the same class
2. If found: the class generalizes within this codebase
3. If the class is novel AND generalizable: propose as a new Stage 2 vector
```

### Stage 3-8: Standard pipeline

Lead Hunter findings get full PoC Treatment (Tier-1 target). No compromises on proof quality — a novel class needs stronger evidence, not weaker.

### Post-Stage 8: Vector proposal

If the Lead Hunter discovers a genuinely novel vulnerability class:

1. Write a vector proposal (`$RUN_DIR/8-final/novel-vector-proposal.md`):
   - Abstract pattern description
   - Detection methodology (what to grep for)
   - Code-citation pattern
   - Language/runtime features enabling the class
   - Prior art (closest known patterns)
2. The proposal is a candidate for the attack vector catalogue (`V133+` in `rust-attack-vectors.md` or `dlt-infra-attack-vectors.md`)

## When Lead Hunter is the right choice

- **Target has a genuinely novel subsystem** — new consensus, new crypto, new cross-domain mechanism, new VM
- **You have deep Rust expertise** — Lead Hunter requires understanding Rust semantics at the language level
- **You have a Scientist partner** — custom tooling amplifies the deep analysis
- **The target is mature and well-audited** — standard bug classes have already been found; only novel classes remain

## When Lead Hunter is the wrong choice

- **The target is standard/commodity** — an Anchor program, a CosmWasm contract, a basic AMM. Lead Hunter overfits to novelty; there's nothing novel here.
- **You have limited time** — Lead Hunter is 2-3× the cost of Digger for potentially zero findings (novel classes are rare by definition)
- **You want reliable findings** — Digger produces predictable output. Lead Hunter might produce nothing. Or it might produce the most valuable finding of your career. There is no middle ground.

## Lead Hunter output

Lead Hunter findings carry a `strategy: lead-hunter` metadata tag and a `novel-class: true` field. The finding format includes an additional "Class Generalization" section:

```markdown
### Class Generalization
**Abstract pattern**: Systems that cache validator set hashes without epoch-bounding
  are vulnerable to cross-epoch replay when the hash collides after a validator rotation.
**Detection**: Grep for `hash.*validator.*set` or `keccak.*validators` where the hash
  is stored without an epoch/height/nonce binding.
**Enabling features**: Deterministic validator ordering + hash-as-identity + epoch-bounded rotation.
**Prior art**: Closest pattern is CVE-2023-XXXXX (Tendermint validator set hash replay, different mechanism).
```

Stage 8 surfaces:

> **Strategy note**: This run used the Lead Hunter strategy (novel vulnerability class research). Findings target one novel subsystem in depth. The strategy optimizes for discovering new bug classes, not comprehensive coverage. Standard bug classes may exist elsewhere in the codebase but were not targeted.
