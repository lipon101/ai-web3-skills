# ITERATE Mode — Stage 4 → Stage 2 feedback loop

ITERATE mode is a feedback arc that fires when Stage 4 produces a KILL whose rationale identifies a *different* bug — usually at a different location or in a different mechanism. Without ITERATE mode, that information was lost: the Stage 4 challenger had implicitly discovered a new finding, but Argus had no path to surface it. ITERATE captures the insight and runs a targeted re-audit.

This was a v0.1.10 addition driven by DeepSeek's external review.

## Trigger

Stage 4 emits a verdict with `STATUS: KILL(<reason>)` AND the verdict file's Pass C `justification` or Pass D `attack_path_summary` contains a phrase matching one of these patterns:

- "however, a different bug exists at <file:line>"
- "the actual defect is in <file:line>"
- "the cited function is fine; the caller at <file:line> is broken"
- "the existing guard works against the cited mechanism but a parallel mechanism at <file:line> bypasses it"
- "the carve-out covers the admin path but the public path at <file:line> reaches the same state"

The orchestrator scans the verdict file post-Pass-C for these structural cues. If matched, ITERATE fires.

## Cap

- ITERATE may fire **at most 5 times per run** (across all findings) to prevent infinite loops.
- A single F-NN's KILL may fire ITERATE at most **once** — the rescan output (F-NN') is not eligible to itself trigger ITERATE.
- If the cap is hit, log `iterate_cap_reached: yes` in `$RUN_DIR/_iterate-log.md` and continue without further iterations.

## Operations

When ITERATE fires for finding F-NN:

1. **Extract the new bug location** from the Stage 4 verdict file. Specifically the file:line citation in the matched pattern.
2. **Identify the angle** that originally produced F-NN (read F-NN.md's source angle from Stage 2 metadata).
3. **Construct a focused hot-zone** combining:
   - The file:line region from step 1 (±20 lines)
   - The original F-NN's location (for context)
   - The Stage 4 verdict's rationale text (verbatim)
4. **Re-dispatch the originating angle** as a single-angle subagent with this hot-zone. The angle prompt prefixes:
   ```
   ITERATE MODE: Stage 4 of finding F-NN identified a parallel defect at <file:line>
   that the original Stage 2 audit missed. Re-audit ONLY the cited region with the
   original Stage 4 challenger's rationale below as a hot-zone. Produce 0-3 new
   FINDING blocks at this region. Do not re-derive anything outside it.

   <Stage 4 challenger rationale verbatim>
   <hot-zone code excerpt>
   ```
5. **Output processing**: re-dispatched angle's findings enter the pipeline at Stage 3. They carry an `iterated_from: F-NN` field for provenance. Their F-NN' identifiers are assigned in sequence after the highest existing F-NN.

## ITERATE-log

`$RUN_DIR/_iterate-log.md` records every firing:

```markdown
# ITERATE-mode log

## Iteration 1
- triggered_by: F-03 Stage 4 verdict
- trigger_pattern: "the cited function is fine; the caller at recover.rs:142 is broken"
- new_finding_id: F-19
- new_finding_at: recover.rs:142
- new_finding_status: <ADVANCE | DOWNGRADE | KILL after running through pipeline>

## Iteration 2
...
```

Stage 8 surfaces the iterate-log in the final terminal print:

```
ITERATE: 3 iterations triggered, 2 produced new SUBMIT-bucket findings
```

## What ITERATE does NOT do

- Does NOT trigger on every KILL. Most kills are clean ("EG-1 holds; finding invalid") and do not name a different defect — those don't fire ITERATE.
- Does NOT re-run the full Stage 2 pipeline. It re-runs ONE angle on ONE region.
- Does NOT recursively iterate. F-NN' findings from ITERATE are pipeline-eligible but cannot themselves trigger ITERATE.
- Does NOT change F-NN's verdict. F-NN remains KILL'd as Stage 4 decided. ITERATE just *adds* F-NN'.

## Cost

Each iteration: ~one angle's worth of token budget (Stage 2 angles cost varies; rough estimate 30k tokens). Capped at 5 iterations × 30k = ~150k tokens additional per run worst case. Stage 0 cost preview is updated to add this to the per-run estimate (small line item).

## When to disable ITERATE

User can disable via Stage 0's run-config:

```
ITERATE_MODE: disabled
```

Disabled mode: Stage 4 verdicts are recorded as-is; the structural-cue scan is skipped; no rescans occur.

Default: ITERATE enabled, cap=5.
