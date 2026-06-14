---
name: hunt-summary
description: >-
  This skill should be used when the user says "hunt-summary", "/hunt-summary",
  "summarize the hunt", "summarize this session", "session summary", "hunt
  summary", "checkpoint the hunt", "wrap up this session", "snapshot where we
  are", "what did we find so far", "save progress before I stop", or wants a
  durable record of a security research session. It analyzes the conversation
  transcript up to this point and writes a comprehensive hunt summary to
  grimoire/hunt-summary-<datetime>.md in the audit workspace — capturing what
  was discovered, dead ends, new leads, conclusive finds, and next actions so a
  future Grimoire run can pick up exactly where this one left off.
user_invocable: true
---

# Hunt Summary

Analyze the current session's transcript and write a durable, self-contained checkpoint to
`grimoire/hunt-summary-<datetime>.md` in the audit workspace. The summary is the handoff: a future
hunt — run by you or another researcher — should be able to read it cold and continue without
re-deriving everything this session learned.

## Philosophy

**A hunt is a long game across many sessions.** Context windows end; the engagement doesn't. The
expensive part of security research is not the writing — it is the discovery, the ruling-out, and
the half-formed hypotheses that live only in this conversation. When the session closes, that state
evaporates unless it is captured. This skill captures it.

**Dead ends are findings too.** The most valuable thing one session gives the next is often *what
not to bother with*. Record why a path was ruled out, not just that it was — otherwise the next
run re-walks it.

**Be honest about confidence.** A conclusive find is proven with an artifact. A lead is a
hypothesis. Do not promote leads to finds, and do not bury a real find as a lead. Calibrated
status is what makes the summary trustworthy enough to act on.

**Mine the transcript; do not invent.** Everything in the summary must trace to something that
actually happened this session — a file you read, a behavior you confirmed, a hypothesis you
raised. If the session was thin, the summary should be short. Padding destroys the document's value.

## Workflow

When this skill is activated, create a todo list from the following steps. Mark each task
in_progress before starting it and completed when done.

```
- [ ] 1. Locate the audit workspace and resolve the output path + timestamp
- [ ] 2. Mine the transcript — extract discoveries, finds, leads, dead ends, open questions, next actions
- [ ] 3. Reconcile against on-disk artifacts (findings/, sigil-findings/, tomes/, spells/, cartography)
- [ ] 4. Draft the hunt summary from the template
- [ ] 5. Write grimoire/hunt-summary-<datetime>.md
- [ ] 6. Present the summary and offer to fold key items into GRIMOIRE.md
```

---

### 1. Locate the Audit Workspace and Resolve the Output Path

The summary belongs in the engagement's `grimoire/` workspace directory — the one created by
`summon`, sibling to `GRIMOIRE.md` and the `findings/`, `tomes/`, `spells/` subdirectories. It is
**not** related to the Grimoire plugin's own source tree.

Determine the workspace:
- If a `grimoire/` directory exists at or above the current working directory (typically next to
  `GRIMOIRE.md`), use it.
- If `GRIMOIRE.md` exists but no `grimoire/` directory does, write the summary next to
  `GRIMOIRE.md` and note that this does not look like a fully initialized workspace (suggest
  `/summon`).
- If neither exists, this session is not running inside a Grimoire workspace. Tell the user, and
  ask whether to (a) write the summary to the current directory anyway, or (b) stop. Do not
  silently create a workspace.

Resolve the timestamp with bash so the filename is sortable and collision-free:

```
date +%Y-%m-%d-%H%M%S
```

The output path is `grimoire/hunt-summary-<datetime>.md` (e.g.
`grimoire/hunt-summary-2026-06-02-143052.md`). Never overwrite an existing summary — each run is a
new checkpoint, preserving the trail.

### 2. Mine the Transcript

Review the conversation from the start of this session to now. This is the core of the skill —
extract the research state into the five categories below. Work from what actually occurred; quote
file paths and `file:line` references wherever the session produced them.

- **Conclusive finds** — issues confirmed this session, ideally with a proof artifact (PoC,
  failing invariant, reproduced behavior). For each: title, severity, exact location, one-line
  impact, and the path to the proof / finding document.
- **Discovered** — what was *learned* about the system: behaviors, mechanisms, trust boundaries,
  invariants confirmed or broken, surprising couplings. Not necessarily bugs — this is the context
  that primes the next run.
- **Interesting leads** — promising hypotheses raised but **not yet verified**. For each: why it's
  interesting, where to look next, what evidence would confirm or refute it, and a confidence
  level (low / medium / high).
- **Dead ends** — paths explored and ruled out. Record *the reasoning* — what was checked and why
  it is not exploitable or not a bug — so the next run does not repeat the work.
- **Open questions & next actions** — unresolved questions (especially those needing the user,
  external docs, or scope clarification), and concrete prioritized next steps.

If the transcript is genuinely sparse in a category, write "None this session." Do not fabricate.

### 3. Reconcile Against On-Disk Artifacts

The transcript is the primary source, but the workspace may contain artifacts the conversation
produced or touched. Cross-check so the summary's references are accurate and nothing is dropped:

- `grimoire/findings/` and `grimoire/sigil-findings/` — finding documents written this session.
- `grimoire/tomes/` — detailed notes or flow analyses added or updated.
- `grimoire/spells/` — scripts, PoCs, or detection modules created.
- Cartography files (if the cartography skills were used) — flows mapped this session.
- `GRIMOIRE.md` — note anything the session learned that contradicts or extends it (used in step 6).

List the artifacts touched with their paths. Where a conclusive find has a finding document, link
to it with an Obsidian-style wiki link (e.g. `[[findings/reentrancy-withdraw]]`) to match the
workspace's cross-linking convention.

### 4. Draft the Hunt Summary

Assemble the extracted state into the template below. Keep it scannable — bullets over prose,
specifics over generalities. The document must stand alone: a reader with no access to this
conversation should understand the state of the hunt.

```markdown
# Hunt Summary — [Target] — [date]

> Hunt date: [YYYY-MM-DD HH:MM]
> Session focus: [one line — what this session set out to do]

## Scope of This Session

[2-4 sentences: which components / flows / contracts were examined, and what prompted the work.]

## Conclusive Finds

[Confirmed issues, proven with an artifact. For each:
- **[Title]** — [severity]. Location: `path:line`. Impact: [one line]. Proof: [path / [[findings/...]]].
If none: "None this session."]

## Discovered

[What was learned about the system — behaviors, mechanisms, invariants, trust boundaries. Context
for the next run, not necessarily bugs. Bulleted.]

## Interesting Leads

[Promising but UNVERIFIED hypotheses. For each:
- **[Lead]** — why it matters; where to look; what would confirm/refute it. Confidence: low/med/high.
If none: "None this session."]

## Dead Ends

[Paths ruled out, WITH reasoning so they are not re-walked. For each:
- **[Path / hypothesis]** — what was checked; why it is not exploitable / not a bug.
If none: "None this session."]

## Open Questions

[Unresolved questions, especially those blocked on the user, external docs, or scope.]

## Artifacts Touched

[Files created or modified this session — findings, tomes, spells/PoCs, cartography. Bulleted, with paths.]

## Next Actions

[Prioritized, concrete next steps for the next hunt run — ordered by expected impact. Each should
be actionable: "Investigate X in `path` because Y." Reference the leads above where relevant.]
```

### 5. Write the File

Write the drafted summary to `grimoire/hunt-summary-<datetime>.md`. Do not overwrite an existing
file. Confirm the path back to the user.

### 6. Present and Offer to Update GRIMOIRE.md

Show the user a brief recap: the output path and a one-line count per section (e.g. "2 conclusive
finds, 4 leads, 3 dead ends, 5 next actions").

`GRIMOIRE.md` is the engagement's living memory. If the session produced durable context — a new
crown jewel, a corrected flow, a trust-boundary insight, or a conclusive find — offer to fold a
concise version into the relevant GRIMOIRE.md section (e.g. Attack Surface Notes, Crown Jewels).
Keep GRIMOIRE.md concise; the full detail lives in the hunt summary. Only update GRIMOIRE.md with
the user's confirmation, and never duplicate the entire summary into it.

---

## Guidelines

- **Self-contained handoff.** Assume the next reader has none of this conversation. Spell out
  paths, locations, and reasoning rather than referring to "the function we looked at."
- **Calibrated status over optimism.** Finds are proven; leads are hypotheses; dead ends are
  closed with a reason. Mislabeling any of these makes the next run waste time.
- **Dead ends earn their place.** A ruled-out path with clear reasoning is worth more to the next
  session than a vague lead. Do not omit them to make the hunt look more productive.
- **Brevity scales with substance.** A short session yields a short summary. Resist padding —
  every line should help the next run act.
- **Append, never overwrite.** Each invocation is a timestamped checkpoint. The series of
  summaries is itself the hunt's history.
