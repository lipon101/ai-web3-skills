# Program-Specific Triage — Stage 6

Stage 6 enforces the *live* bounty page as the source of truth. Generic platform criteria from Stage 5 are not enough — programs override them.

Read this file at Stage 6 start.

## ⚠️ Per-finding output is MANDATORY (NEW v0.1.11)

Stage 6 produces `$RUN_DIR/6-program/F-NN.md` for every finding entering this stage with all 6 checks populated. A single `_summary.md` is INVALID. The whitelist-mode literal-impact-match (see § "Scope-mode classification") MUST be computed per finding.

Stage 7 entry requires: per-finding F-NN.md count matches Stage-5-ADVANCE+DOWNGRADE count.

## Scope-mode classification (NEW v0.1.11) — runs FIRST after WebFetch

Before any per-finding triage, classify the bounty's scope mode by reading the cached `bounty-page.md`:

### Whitelist mode

Bounty page has an explicit, enumerated **"Impacts in Scope"** list (Immunefi V2.3, some Cantina). Each item names a specific impact mechanism + severity tier:

```
Critical: Unintended, undocumented recovery of private spend keys
Critical: Signing of unintended messages
High:     Incompatibilities with the targeted Monero consensus protocol ...
Low:      Undocumented panic reachable from a public API
Low:      Non-constant-time implementation with regards to secret data
...
```

In **whitelist mode**, ONLY findings whose impact LITERALLY matches one of the listed items are in-scope. Everything else → KILL(impact-not-in-scope-list).

### Blacklist mode

Bounty page lists **"Out of Scope"** rules (Code4rena, Sherlock, generic Immunefi without enumerated in-scope-impacts). Findings are in-scope unless they match an exclusion.

### Hybrid mode

Bounty has BOTH an enumerated in-scope-impact list AND additional general categories ("any unintended fund loss", "any DoS-of-funds"). Hybrid mode is whitelist-mode for the enumerated items, plus blacklist-mode for the general categories.

### How to classify

Parse `bounty-page.md`. If it contains a section titled "Impacts in Scope" / "In-scope impacts" / "Severity Levels" with discrete items per severity tier:

- All listed items are explicit + bounded? → **whitelist mode**.
- List exists but with phrases like "any", "including but not limited to", "such as"? → **hybrid mode**.
- No enumerated list, only out-of-scope rules? → **blacklist mode**.

Record in a new file: `$RUN_DIR/6-program/scope-mode.md`:

```markdown
# Scope-mode classification

- **mode**: whitelist | blacklist | hybrid
- **enumerated in-scope impacts** (whitelist + hybrid only):

| Severity | Impact (verbatim quote from bounty page) |
|----------|------------------------------------------|
| Critical | "Unintended, undocumented recovery of private spend keys (or private spend key shares)" |
| High | "Incompatibilities with the targeted Monero consensus protocol which would require reimplementing notable sections of monero-oxide" |
| ... | ... |

- **general in-scope categories** (hybrid only): [list]
- **out-of-scope categories**: [list of exclusion rules]
- **DoS prohibition**: yes (Immunefi default) | no
- **Reasoning**: <2-3 sentences explaining the classification>
```

## Per-finding impact mapping (UPDATED v0.1.11 — strict literal match in whitelist mode)

### Check 2 — Impact category in scope (REWRITTEN)

For each finding, identify the most-specific impact mechanism from the writeup (e.g., "wallet credits attacker-fabricated outputs", "URL parser truncates password containing @").

#### In whitelist mode

For EACH enumerated in-scope impact item:

1. Quote the bounty's verbatim text for the item.
2. Quote the finding's claimed impact text.
3. Ask: does the finding's impact mechanism + harmed-party + severity tier LITERALLY match the bounty item?
   - **Mechanism match**: not a paraphrase. The bounty says "spend-key recovery"; the finding must literally enable spend-key recovery, not "credential leakage that could lead to..."
   - **Harmed-party match**: bounty says "wallet user"; finding's harmed party must be wallet user, not "any operator running the program."
   - **Severity-tier match**: finding's calibrated severity matches the tier of the bounty item.
4. Record yes/no.

If NO listed item literally matches → `KILL(impact-not-in-scope-list)`. Do NOT downgrade-to-refine; the bounty has explicitly enumerated what it pays for, and this finding is not on the list.

**Anti-fuzzy-match discipline**: phrases like "this could be classified as information disclosure", "this is a kind of state corruption", "borderline scope" are PROHIBITED in whitelist mode. Either the finding maps to an exact item with citation, or it is killed.

The verdict file's Check-2 section MUST contain:

```
check_2_impact_in_scope:
  scope_mode: whitelist | blacklist | hybrid
  finding_impact_mechanism: <one sentence>
  finding_harmed_party: <wallet user | DAO | LP | bridge user | etc.>
  candidates_evaluated:
    - bounty_text: "<verbatim>"
      severity_tier: Critical | High | Low
      mechanism_match: yes | no
      harmed_party_match: yes | no
      tier_match: yes | no
      result: MATCH | NO_MATCH (mechanism / harmed-party / tier mismatch)
  best_match: <bounty_text or "no match">
  verdict: MATCH (in-scope) | NO_MATCH (KILL impact-not-in-scope-list) | DOWNGRADE_TO_<tier> (matches lower tier than claimed)
```

#### In blacklist mode

Use the existing v0.1.0 logic: if finding's impact does NOT match any in-scope category and does match an out-of-scope rule → KILL. Otherwise ADVANCE.

#### In hybrid mode

Apply whitelist matching first (literal items). If no whitelist match, fall to blacklist matching (does it fit a general in-scope category like "fund loss"? does it match an out-of-scope rule?).

### Why this matters — the F-11 monero-oxide failure

The v0.1.10 run on monero-oxide produced F-11 ("URL parser truncates password containing @") as a SUBMIT candidate. The Judge running standalone correctly killed it: monero-oxide's bounty has 10 enumerated in-scope impacts (spend-key recovery, signing of unintended messages, consensus-protocol incompatibility, undocumented panic, etc.) — and "credential mishandling" or "URL-parser correctness" maps to NONE of them. The closest match is "Best practice recommendations" — explicitly out-of-scope.

Argus's Stage 6 said "borderline scope, refine" instead of "no match, KILL". The whitelist-mode strict literal-match rule fixes this: there is no "borderline" in whitelist mode. Either an enumerated item literally covers the finding, or the finding is out of scope.

## Source of truth: the live bounty page (PLUS extended scope sources, NEW v0.1.10)

The bounty page URL was collected at run start. Do not use a cached or remembered version. WebFetch the URL fresh at Stage 6 start.

```
WebFetch(url=$BOUNTY_URL, prompt="Extract: in-scope assets/components (with addresses or repo paths), in-scope impact categories per severity tier, severity-to-payout map, automatic exclusions, PoC requirements, specific in-scope/out-of-scope rules, known-issues list, prior-audit references, applicable commit/tag")
```

Cache the extraction to `$RUN_DIR/6-program/bounty-page.md` with a header showing the URL and the UTC fetch time.

If WebFetch fails, retry once. If it fails again, write `bounty-page.md` with the failure note and continue with `program-mode = generic` — Stage 8 will reduce final confidence on every Stage-6-touched finding.

### Deep scope search (NEW v0.1.10)

Scope exclusions are frequently buried in places the bounty page doesn't surface. Stage 6 now extracts scope from FOUR additional sources beyond the bounty page:

#### Source 1 — Repository documents

Fetch from the GitHub repo:
- `README.md` (root)
- `CONTRIBUTING.md`
- `SECURITY.md`
- `audits/` directory (PDFs from prior audits if checked in)
- `docs/` directory (search for files matching `*scope*`, `*known-issues*`, `*limitations*`)

Use Read (if repo is cloned locally) or WebFetch on `https://raw.githubusercontent.com/<owner>/<repo>/<branch>/<path>`.

#### Source 2 — Closed-as-wontfix issues

```bash
gh issue list --repo <owner>/<repo> --label 'wontfix' --state all --limit 50
gh issue list --repo <owner>/<repo> --label 'wont-fix' --state all --limit 50
gh issue list --repo <owner>/<repo> --label 'out-of-scope' --state all --limit 50
gh search issues --repo <owner>/<repo> 'is:closed reason:not-planned' --limit 50
```

Read each hit; extract any text describing why the issue was rejected. These are often de-facto exclusions even when not in the bounty page.

#### Source 3 — Pinned issues / discussions

```bash
gh issue list --repo <owner>/<repo> --search 'pinned:true' --limit 10
gh api repos/<owner>/<repo>/discussions --jq '.[] | select(.pinned == true)' --paginate
```

Pinned issues / discussions often contain known-limitations announcements.

#### Source 4 — Bounty-page links

Re-WebFetch URLs explicitly linked from the bounty page (often docs.protocol.io or specific Notion/GitBook pages). The bounty page itself only summarizes; deep links carry the actual exclusion text.

### Cross-reference and aggregate

For every finding, the scope-classifier MUST run against ALL aggregated sources:

```
SOURCES = [bounty-page.md, README.md, CONTRIBUTING.md, SECURITY.md,
           audit reports, wontfix issues, pinned discussions, deep-linked docs]

for source in SOURCES:
  for exclusion_text in extract_exclusion_language(source):
    if exclusion_text describes finding's mechanism:
      record match in extended-scope-hits.md
```

If a finding's mechanism matches an exclusion in ANY source → `KILL(out-of-scope-extended)` with citation of source + verbatim exclusion quote.

### Output

`$RUN_DIR/6-program/extended-scope.md`:

```markdown
# Extended scope sources — Stage 6 deep scan

- Bounty page: <URL> — fetched 2026-05-08T12:34:00Z
- README.md: <URL> — fetched ...
- CONTRIBUTING.md: <URL or "not found">
- SECURITY.md: <URL or "not found">
- Wontfix issues: <count> read
- Pinned discussions: <count> read
- Deep links: <list>

## Aggregated exclusions

| Source | Section / Issue | Exclusion text | Mechanism keywords |
|--------|----------------|----------------|--------------------|
| README.md | "Out of scope" | "MEV-related findings are not eligible" | mev, frontrun, sandwich |
| issue #142 (wontfix) | (closed 2026-03) | "We accept oracle-staleness as a known limitation" | oracle, staleness |
| ... | | | |
```

`$RUN_DIR/6-program/F-NN.md` Check 3 section now compares the finding against the aggregated exclusions, not just the bounty page exclusions.

## Required extractions

```yaml
program:
  name: <program name>
  platform: <Immunefi | HackenProof | Cantina | Sherlock | Code4rena | self-hosted>
  url: <fetched URL>
  fetched_at: <UTC ISO-8601>

scope:
  in_scope_assets:
    - <repo path or contract address or component name>
  in_scope_impacts:
    critical: [<impact list>]
    high: [<impact list>]
    medium: [<impact list>]
    low: [<impact list>]
  out_of_scope_assets: [...]
  out_of_scope_impacts: [...]
  exclusions: [<full exclusion bullet>]

requirements:
  poc_required: yes | no | severity-conditional
  poc_format: anchor | cosmwasm | substrate | cargo-test | arbitrary
  reproducible_steps_required: yes | no
  primary_chain: <solana | cosmos | substrate | other>
  applicable_commit_or_tag: <git ref or "latest main" or "audited commit X">
  # NEW v0.2.4 — per-program PoC clause extraction (Drift / Marinade / Compound style)
  poc_clause_verbatim: <quoted text from bounty page; e.g., "For critical and moderate bugs, we require a proof of concept done on a privately deployed mainnet contract." OR "All smart contract bug reports must come with a PoC..." OR "n/a — no specific clause">
  poc_clause_severity: <which severity tiers the clause applies to: all | critical-only | critical-and-high | informational-only>
  poc_clause_overrides_platform_default: yes | no | unclear
  immunefi_test_suite_fallback_endorsed: yes | no | unclear  # only relevant when target_platform == Immunefi

payout:
  critical: <range>
  high: <range>
  medium: <range>
  low: <range>
  bonus_rules: [<bullets>]

known_issues:
  - <bullet>

prior_audits:
  - <link or "none referenced">
```

If any field is missing on the page, mark it `unspecified` rather than guessing.

## Per-finding triage

Run these checks in order. The first KILL or DOWNGRADE result short-circuits.

### Check 1 — Asset / target in scope

Is the file/module/contract/program the finding cites in `scope.in_scope_assets`?

- For repo-based programs: match the file path against the in-scope path globs.
- For address-based programs: match the program ID / contract address the file deploys to (if metadata available).

If NO → `KILL(out-of-scope-asset)`.

If asset is *unspecified* on the bounty page → mark `scope-unverifiable` and continue with reduced confidence.

### Check 2 — Impact category in scope

Map the finding's *post-Stage-5* impact to the in-scope impact list. Examples:

- "drain user funds" → typically Critical-tier in-scope for DeFi programs
- "permanent freeze of locked funds" → typically Critical
- "denial-of-service requiring re-deployment" → typically High but check program — many programs explicitly list "smart-contract DoS without funds at risk" as Low or out-of-scope
- "griefing requiring whale action" → often out-of-scope or Low
- "MEV / front-running" → many programs explicitly exclude

If finding's impact does NOT match any in-scope category → `KILL(impact-not-in-scope)`.

If finding's impact maps to a *lower* in-scope tier than Stage 5 predicted → `DOWNGRADE(impact-mapping)` to that tier and adjust severity to match the program's payout for that impact.

### Check 3 — Exclusion rules

Walk the program's `exclusions` list. For each, ask: does this finding fall under it?

Common exclusions:
- "centralization risks where admin can rug" → matches if Stage 4 trust-model cap was DOWNGRADE not KILL
- "issues already submitted" / "known issues at <link>" → cross-check known-issues
- "issues found in dependencies not in scope" → matches if bug is in a third-party crate the project pins
- "loss requiring user error / phishing" → matches social-engineering findings
- "issues without realistic attack scenario" → matches Tier-4-PoC findings

Hard exclusion match → `KILL(exclusion: <quoted exclusion>)`.

### Check 4 — Commit / version match

Does finding cite source at the program's currently-applicable commit/tag?

```bash
git log --oneline -5 <file>
git show <applicable_commit>:<file>
```

If finding is at HEAD but program is pinned to an older commit, verify bug existed at that commit too.

If bug does not exist at applicable commit → `KILL(version-mismatch)`.

### Check 5 — PoC requirement match

If `requirements.poc_required = yes` and finding's Stage 3 verdict is `exempt-N` → `DOWNGRADE(refine)` with note: must produce runnable PoC of cited tier before resubmitting.

If `requirements.poc_required = severity-conditional` (e.g., "Critical and High require PoC") and finding's Stage 5 severity meets threshold without runnable PoC → same DOWNGRADE.

### Check 6 — Known issues

Compare finding's mechanism against `program.known_issues`. If a known issue covers the same root cause at the same location → `KILL(known-issue)` and cite the matching bullet.

Coarse text match here. Stage 7 does the deeper duplicate probe against the actual repo.

## Impact-chain reachability check (NEW v0.1.11 — Check 2.5)

After Check 2 maps the finding to an in-scope impact, run an explicit "does the exploit chain ACTUALLY reach the impact?" check. This is distinct from `reachability_check` (which is about reaching the buggy code from a public entry) — this checks reaching the CLAIMED IMPACT from the buggy code, through every guard / cryptographic check / state validation in between.

The F-06 case: F-06 mapped to "reportedly received funds which weren't actually received" (Critical in scope). Mechanically, a malicious daemon could fabricate a non-genesis block range. But the exploit chain to "wallet credits attacker outputs" passes through `Scanner::scan_transaction`, which performs:

1. Cryptographic ownership check via `view_priv * tx_pub_key`.
2. View-tag check.
3. Spend-key derivation.
4. Pedersen commitment rebuild.

A malicious daemon **without the wallet's view key cannot construct outputs that pass these checks**. The "wallet credits attacker outputs" impact is mechanically blocked. F-06's claimed in-scope impact is unreachable through the cryptographic guard.

### How to perform the impact-chain reachability check

For every finding mapped to an in-scope impact in whitelist mode:

1. **Decompose the exploit chain into steps**:
   - Step 1: attacker's initial action (e.g., "malicious daemon returns fabricated block range").
   - Step 2..N-1: intermediate state changes / system responses.
   - Step N: the claimed in-scope impact (e.g., "wallet credits attacker outputs as received funds").
2. **Identify every guard / check / cryptographic verification between Step 1 and Step N**:
   - Cryptographic checks (signature verification, view-key checks, Pedersen commitments).
   - Access control gates.
   - Invariant checks (require!/ensure!/if-let-Err return paths).
   - State validation (sequence number checks, version checks, freshness checks).
3. **For each guard, determine**: does the attack scenario clear this guard?
   - Yes → guard is bypassed; impact reachable through this step.
   - No → guard blocks; impact NOT reachable via this exploit chain.
4. **Apply the verdict**:

| Result | Action |
|--------|--------|
| All guards cleared by attack → impact reachable | proceed to Check 3 |
| One guard blocks → impact NOT reachable | KILL(impact-chain-blocked-by-<guard>) |
| Bypass requires capability the attacker doesn't have (e.g., view key) | KILL(impact-chain-requires-attacker-capability) |
| Bypass plausible but requires assumptions not in the writeup | DOWNGRADE(refine) — strengthen exploit chain |

Record in the verdict file:

```
impact_chain_reachability:
  claimed_impact: <in-scope impact item>
  exploit_chain_steps:
    - step: <description>
      guards_traversed: [<guard name + file:line>]
      attacker_passes_guard: yes | no | unclear
      passes_via: <what capability or input lets the attacker through>
  blocking_guard: <guard name and reason, or "none">
  verdict: REACHABLE | BLOCKED_BY_<guard> | UNCLEAR
```

This check is **MANDATORY in whitelist mode** because that's where impact-mapping is strict. In blacklist mode, run it best-effort — blacklist scope is more permissive about chain-completeness.

## Reversibility rule (HackenProof-inherited)

When the bounty page is HackenProof OR the finding is borderline:

**Prefer reversible actions (`DOWNGRADE(refine)` requesting more evidence) over premature `KILL` when uncertainty is material.**

Specifically:
- If a check produces a borderline result with `LOW` confidence → default to `DOWNGRADE(refine)` rather than `KILL`.
- If WebFetch returned a partial bounty page (missing some fields), default to `DOWNGRADE(refine)` for findings that touch the missing-field area.
- A `KILL` at Stage 6 should be reserved for clear-cut cases (bug at out-of-scope path, exclusion clearly applies, version mismatch confirmed by git diff).

This is HackenProof's `Need more info` discipline applied generally — it costs little to ask the user to refine a finding and a lot to incorrectly kill a real finding.

## Per-finding output schema

`$RUN_DIR/6-program/F-NN.md`:

```markdown
# F-NN Stage 6 verdict

- **finding**: <title>
- **program**: <name>
- **bounty URL**: <url>
- **status**: ADVANCE | DOWNGRADE(<reason>) | KILL(<reason>)

## Check 1 — Asset / target in scope

- **finding location**: <file:line>
- **matched in-scope entry**: <quoted from bounty page> | **unmatched**
- **verdict**: in-scope | out-of-scope | scope-unverifiable

## Check 2 — Impact in scope

- **finding impact (post Stage 5)**: <description>
- **mapped program impact category**: <category, severity tier, payout range>
- **verdict**: in-scope | downgrade-to-<tier> | out-of-scope

## Check 3 — Exclusions

- **rules walked**: <count>
- **matched exclusion**: <quoted bullet> | none
- **verdict**: not-excluded | excluded(<bullet>)

## Check 4 — Commit / version

- **applicable commit/tag (per program)**: <git ref>
- **finding cites**: <commit or HEAD>
- **bug exists at applicable commit?**: yes / no — <evidence>

## Check 5 — PoC requirement

- **program requires PoC?**: yes / no / conditional
- **finding has runnable PoC (Stage 3 verdict)?**: tier <N> / exempt-<N>
- **verdict**: meets-requirement | needs-runnable-poc

## Check 6 — Known issues

- **matches a known issue?**: yes / no
- **matched bullet (if yes)**: <quoted>

## Reversibility note

- **borderline?**: yes / no
- **applied reversibility rule?**: yes (downgraded to refine instead of killing) / no — <reason>

## Final verdict

<one paragraph: which check produced the verdict, with quoted bounty-page text as evidence>
```

## When the program is "generic" (no URL supplied)

Skip Checks 1-3 and 6 (no source of truth). Run Check 4 against HEAD only and Check 5 using platform defaults from Stage 5. Mark every finding's verdict as `ADVANCE-with-warning(generic-mode)` so Stage 8 reduces final confidence.

## Triage comment templates

When the user asks Argus to draft a communication to the program (e.g., a clarification request after `DOWNGRADE(refine)`), use these templates as starting points. Adapt — never paste verbatim.

### "Need more info" — when Argus needs the user to confirm something before submission

```md
Before submitting, please confirm:
- <missing piece — e.g., the exact in-scope commit, an attachment, an oracle config>
- <expected vs actual behavior, with specific evidence>
- <PoC artifact, logs, or transaction links>

Once confirmed, this finding will be ready for the platform.
```

### "Out of scope" explanation — when Stage 6 KILL'd a finding for scope

```md
After review, this issue is currently out of scope for this program because:
- <specific scope/rule reference quoted from the bounty page>

If a different in-scope target is affected, please update the location and re-run.
```

### "Duplicate likely" — when Stage 7 found a hard duplicate

```md
This issue matches an existing public reference with the same root cause and impact:
- <link>

Recommended action: discard, or differentiate framing materially before resubmission.
```

## Anti-pattern

Do **not** accept the user's verbal description of scope as substitute for the page. The page is source of truth — even if the user thinks they remember a rule, the page wins. Argus is a defense against the auditor's wishful memory of the bounty rules.
