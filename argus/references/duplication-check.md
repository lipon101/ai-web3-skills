# Duplication Triage — Stage 7

Stage 7 is the last filter before final output. It checks the *target project's GitHub repo* for signals that this finding is already known. A finding that is real but already filed, already fixed, or actively under PR review is a finding the program will reject.

Read this file at Stage 7 start.

## ⚠️ Per-finding output is MANDATORY (NEW v0.1.11)

Stage 7 produces `$RUN_DIR/7-duplication/F-NN.md` for every finding entering this stage with the full 7-probe trace populated. A single `_summary.md` is INVALID — duplicate-check probes are not skippable per finding even when prior stages produced collapsed output.

Stage 8 entry requires: per-finding F-NN.md count matches Stage-6-ADVANCE+DOWNGRADE count. If short, the orchestrator re-runs Stage 7.

## Source of truth: the GitHub repo

The repo URL was collected at run start. Stage 7 probes the repo using `gh` (GitHub CLI) where possible, with WebFetch fallback for unauthenticated lookups.

If the repo URL was not supplied, Stage 7 runs in `dup-mode = local-only`: it can still check the *local* git history (`git log`, `git blame`) but cannot probe issues, PRs, or comments. Stage 8 reduces final confidence on every Stage-7-touched finding accordingly.

## Probe set (run for every finding)

Run probes 1-5 for every finding. Probes 6-7 only fire if probes 1-5 turn up partial signals.

### Probe 1 — Local git history at the cited file

```bash
git log --oneline -20 -- <file>
git log -p --since="6 months ago" -S "<short keyword from finding>" -- <file>
```

Look for: recent commits whose message describes the same fix (e.g., "fix: validate signer in claim_rewards"), commits that touch the exact lines the finding cites, recent reverts.

If a commit fixes the exact bug at the cited location → `KILL(already-fixed)` with the commit SHA.

### Probe 2 — Blame on the cited lines

```bash
git blame -L <start>,<end> <file>
```

Look for: when the buggy code was introduced. If it was introduced in the last commit by a known-throwaway branch (e.g., a WIP that's not yet on `main`), the bug may not be live.

If the bug-introducing commit is not yet on the deployed branch → `DOWNGRADE(refine)` with note: confirm bug exists on the deployed branch before submission.

### Probe 3 — GitHub Issues search

```bash
gh issue list --repo <owner>/<repo> --search "<short keyword> in:title,body" --limit 20 --state all
gh issue list --repo <owner>/<repo> --search "<file basename> <failure mode>" --limit 20 --state all
```

Compose 2-4 search queries per finding, each combining: a distinctive keyword from the finding title, the affected file or function, and a vulnerability-class word (e.g., "underflow", "signer", "panic", "deserialize").

For each hit, read the issue with `gh issue view <num>`. Classify:
- **exact match** (same root cause + same location) → KILL candidate
- **adjacent** (same file or same vulnerability class but different specific bug) → DOWNGRADE candidate
- **unrelated** → ignore

### Probe 4 — GitHub Pull Requests search

```bash
gh pr list --repo <owner>/<repo> --search "<short keyword>" --limit 20 --state all
gh pr list --repo <owner>/<repo> --search "<file basename> fix OR security" --limit 20 --state all
```

For each hit, run `gh pr view <num>` and check whether the PR's diff touches the cited file/lines. A merged PR fixing the same root cause at the same location → KILL. An open PR doing the same → KILL with note: fix in flight.

### Probe 5 — GitHub Commit search (Search API)

```bash
gh api -X GET search/commits -f q="repo:<owner>/<repo> <short keyword>" --jq '.items[] | {sha,message:.commit.message,html_url}'
```

This catches direct-to-main fix commits that were not gated by a PR. Same classification: exact / adjacent / unrelated.

### Probe 6 — Comment search (only if 3-5 turned up adjacent hits)

If probes 3-5 found adjacent hits but no exact match, check comments on those adjacent items for whether the exact finding has already been discussed:

```bash
gh issue view <num> --comments
gh pr view <num> --comments
```

Look for reviewers / maintainers raising the same concern Argus would raise.

### Probe 7 — Linked audit reports (only if program references prior audits)

If `program.prior_audits` from Stage 6 contains links, fetch each audit report and search for the finding's mechanism. A prior audit that found the same issue and the project marked as "fixed" / "acknowledged" / "won't fix" → KILL.

## Search-query construction

Good queries are 2-4 words long with at least one *distinctive* term (the bug's specific name, an unusual function name, an error message). Avoid generic terms ("bug", "fix", "security") as the only keyword — they swamp results.

Examples of good queries (adapt to your finding):
- `claim_rewards signer missing` — specific function + specific failure
- `BorshDeserialize unwrap` — specific encoding + specific panic mode
- `find_program_address bump` — Solana PDA failure mode

Run multiple queries per finding to compensate for terminology variance.

## Verdict mapping

| Strongest signal across probes | Stage 7 verdict |
|--------------------------------|-----------------|
| Probe 1 or 4 found exact-match merged fix | KILL(hard-dup-fixed) |
| Probe 4 found exact-match open PR | KILL(hard-dup-pr-in-flight) |
| Probe 3 found exact-match open issue | KILL(hard-dup-known) |
| Probe 5 found exact-match commit | KILL(hard-dup-fixed) |
| Probe 7 found exact match in prior audit (acknowledged or won't-fix) | KILL(hard-dup-prior-audit) |
| Adjacent hits only (related but not exact) | RESCAN (NEW v0.1.10 — see below) |
| Probe 2 shows bug not on deployed branch | DOWNGRADE(refine) — confirm deployment |
| No hits | ADVANCE |

### Adjacent-hit rescan (NEW v0.1.10)

When a probe returns adjacent hits (related discussion or partial fix at the cited file but NOT exact match for the finding's mechanism), do NOT immediately DOWNGRADE(refine). The adjacent prior fix may have addressed only one variant of the bug class while the cited finding describes a parallel variant — or the prior issue may have been closed without a fix at all.

The rescan procedure:

1. **Identify the adjacent hit's mechanism**. Read the issue / PR / commit body. Extract: the function it describes, the fix it applied (if any), and what it did NOT cover.

2. **Spawn a lightweight Stage-2 single-angle re-run** with these constraints:
   - Single angle: the one that originally produced F-NN.
   - Single module: the module containing the cited file.
   - Hot-zone: the file:line region of F-NN's location AND the file:line region of the adjacent fix's diff.
   - Injected context: the adjacent hit's full body + the prior fix's diff (if any).

3. **Process rescan output**:

| Rescan result | Stage 7 verdict |
|--------------|-----------------|
| Rescan re-confirms F-NN's mechanism is still exploitable post-adjacent-fix | ADVANCE F-NN with note: "adjacent issue #X covers a different variant" |
| Rescan finds a new related-but-distinct candidate (different from F-NN) | Emit F-NN' as new candidate; F-NN goes to DOWNGRADE(refine) for re-framing |
| Rescan confirms the adjacent fix DOES cover F-NN's mechanism | KILL(adjacent-issue-covers-finding) |
| Rescan inconclusive | DOWNGRADE(refine) — original v0.1.9 default |

4. **Cap**: at most 3 rescans per Stage 7 run. Beyond that, fall back to the default DOWNGRADE(refine).

### Rescan output

`$RUN_DIR/7-duplication/F-NN-rescan.md`:

```markdown
# F-NN Stage 7 adjacent-hit rescan

- adjacent hit: <issue/PR URL>
- adjacent fix diff: <quoted, if any>
- rescan angle: <which Stage 2 angle>
- rescan hot-zone: <file:line ranges>
- rescan output: <NEW_CANDIDATE | F_NN_STILL_HOLDS | F_NN_COVERED_BY_FIX | INCONCLUSIVE>
- new candidate (if any): F-NN' at <file:line>
```

### Why this matters

The Reflector / swafe data showed multiple cases where Argus's prior issue match was over-broad: a prior fix covered the cited mechanism in *one* parameter but not the parallel parameter the finding described. The DOWNGRADE(refine) default lost those findings to the user's overhead burden. The rescan automates the "did the prior fix actually cover it?" check.

A KILL at Stage 7 is allowed even with weak signals — being wrong about a duplicate at submission time is more expensive than being wrong about it here. But if the signal is "adjacent" only, default to DOWNGRADE rather than KILL.

## Anti-overclaim rule

Do not classify a hit as a duplicate from weak semantic similarity alone. Required for `hard-dup`:

- the matching item names the same root cause (not just the same file)
- the matching item references the same trigger conditions (not just the same vulnerability class)
- if the matching item is a fix, the fix's diff touches the cited lines (verify with the actual diff, not just the PR title)

If the match is fuzzy, mark it `adjacent` and DOWNGRADE — never KILL on fuzzy.

## Per-finding output schema

`$RUN_DIR/7-duplication/F-NN.md`:

```markdown
# F-NN Stage 7 verdict

- **finding**: <title>
- **target repo**: <url>
- **dup-mode**: full | local-only
- **status**: ADVANCE | DOWNGRADE(refine: <reason>) | KILL(<dup-type>)

## Probes run

### Probe 1 — Local git history
- **command**: <command>
- **hits**: <count>
- **classification**: <exact | adjacent | none>
- **evidence**: <SHA + commit message excerpt or "—">

### Probe 2 — Blame
- **introduced in**: <SHA on branch <name>>
- **on deployed branch?**: yes / no

### Probe 3 — Issues
- **queries**: <list>
- **hits**: [<#num: title — classification>, ...]

### Probe 4 — PRs
- **queries**: <list>
- **hits**: [<#num: title — state — classification>, ...]

### Probe 5 — Commits
- **queries**: <list>
- **hits**: [<sha: message — classification>, ...]

### Probe 6 — Comments (if run)
- **hits**: [...]

### Probe 7 — Prior audits (if run)
- **reports checked**: [<urls>]
- **hits**: [...]

## Verdict reasoning

<one paragraph: strongest matching probe, why it qualifies as exact / adjacent / unrelated, with link>
```

## When `gh` is unavailable

If `gh` is not installed or unauthenticated, fall back to:

```bash
WebFetch(url="https://github.com/<owner>/<repo>/issues?q=<query>", prompt="List the top 10 issues matching this query with their state and one-line summary")
WebFetch(url="https://github.com/<owner>/<repo>/pulls?q=<query>", prompt="...")
WebFetch(url="https://github.com/<owner>/<repo>/commits/main", prompt="...")
```

WebFetch results are coarser (no structured JSON) — record this as reduced-signal and prefer DOWNGRADE over KILL on borderline matches.

## Subagent decomposition

For projects with many findings entering Stage 7 (>10), spawn one general-purpose subagent per finding to run the probe set and return a draft verdict. The orchestrator verifies any KILL(hard-dup) by independently reading the cited issue/PR/commit before accepting the verdict. Subagent results are advisory.
