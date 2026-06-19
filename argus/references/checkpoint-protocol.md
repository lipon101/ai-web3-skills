# Checkpoint Protocol (v0.5.0)

Every Argus run writes a **manifest file** at `$RUN_DIR/_manifest.json` that records which pipeline stages completed and where their outputs live. The manifest is the source of truth for two things:

1. **Resumability** — a run interrupted mid-pipeline (network drop, model timeout, user-cancel, hitting a 5-hour subscription window) can be picked up at the last completed stage rather than re-run from Stage 0.
2. **Audit trail** — every stage's completion is timestamped, sized, and tagged with the model + version that produced it. Stage 8's final report cross-references the manifest to surface drift between estimated and actual work.

Both `/argus` (Claude Code) and Codex CLI invocations write the same manifest format; this file specifies the schema and the per-stage write protocol.

## Where the manifest lives

```
$RUN_DIR/
  _manifest.json              # the manifest (this file's subject)
  _todos.md                   # optional: Codex's TodoWrite-equivalent (per codex-compat.md)
  0-cost-preview/preview.md
  1-protocol-map/...
  2-candidate-findings/...
  ...
```

The manifest is **append-only** during a run: stages add entries, never modify prior entries (except `status` transitions, never the timestamp or output_path). When a stage retries after a failure, it appends a new entry rather than overwriting.

## Schema

```json
{
  "argus_version": "0.5.0",
  "run_id": "<UUID>",
  "run_dir": "<absolute path>",
  "started_utc": "<ISO-8601>",
  "platform": "claude" | "codex",
  "mode": "smart-contract" | "infra",
  "depth_tier": "light" | "core" | "thorough",
  "target": {
    "project_root": "<absolute path>",
    "git_commit": "<sha or 'uncommitted'>",
    "bounty_url": "<URL or null>"
  },
  "stages": [
    {
      "stage": 0,
      "name": "cost-preview",
      "status": "completed" | "failed" | "in-progress" | "skipped",
      "started_utc": "<ISO-8601>",
      "ended_utc": "<ISO-8601 or null if in-progress>",
      "output_path": "<relative to run_dir>",
      "output_files": ["preview.md", "depth-tier.txt", "cap.txt"],
      "tokens_in_estimated": 0,
      "tokens_out_estimated": 0,
      "tokens_in_actual": null,
      "tokens_out_actual": null,
      "model_mix": {"sonnet": 0.7, "opus": 0.3, "haiku": 0},
      "notes": ["user picked depth=core", "user picked option A"]
    },
    {
      "stage": 1,
      "name": "protocol-map",
      "status": "completed",
      "started_utc": "...",
      "ended_utc": "...",
      "output_path": "1-protocol-map/",
      "output_files": ["overview.md", "attack-surface.md", "trust-model.md", "entry-points.md", "invariants.md", "hot-zones.md", "callgraph.json"],
      "tokens_in_estimated": 80000,
      "tokens_out_estimated": 12000,
      "tokens_in_actual": 78421,
      "tokens_out_actual": 11003,
      "model_mix": {"sonnet": 0.7, "opus": 0.3, "haiku": 0},
      "notes": ["callgraph_source: scip"]
    }
  ],
  "current_stage": 2,
  "last_completed_stage": 1,
  "resume_hint": "Stage 2 in-progress at angle 5/8 — see 2-candidate-findings/_partial.json"
}
```

### Field discipline

- **`argus_version`** — the version string that produced this manifest. Reading a manifest written by a different major version requires an explicit `--force` flag on `argus_resume.py`; minor versions are compatible.
- **`run_id`** — a UUID generated at Stage 0. Used to deduplicate when a run is partially copied between hosts.
- **`platform`** — set by the orchestrator at Stage 0. `claude` if invoked from Claude Code (`CLAUDE_PROJECT_DIR` env var present); `codex` if invoked from Codex CLI (`CODEX_HOME` env var present). Resume on a different platform than the original IS supported; the new platform's tool-translation kicks in for remaining stages.
- **`mode` / `depth_tier`** — fixed at Stage 0; cannot change mid-run. A resume that wants to change either must start a new `$RUN_DIR`.
- **`stages[]`** — chronologically ordered, append-only. Entries with `status: failed` are kept; the next entry for the same stage number marks the retry.
- **`current_stage`** — the stage the orchestrator is currently working on (in-progress) OR the next stage to be started.
- **`last_completed_stage`** — the highest stage number with `status: completed`. Resume picks up at `last_completed_stage + 1`.
- **`resume_hint`** — free-text breadcrumb that helps the orchestrator restore in-stage state. Stage 2's parallel-angle dispatch writes a partial-completion record so resume can skip already-completed angles.

## Per-stage write protocol

When a stage starts:

1. Append a `stages[]` entry with `status: in-progress`, `started_utc: <now>`, `ended_utc: null`, `output_path: <relative>`, `output_files: []`, `tokens_*_actual: null`.
2. Set `current_stage: <stage_number>`.

When a stage finishes (success):

1. Find the in-progress entry for this stage (the last entry with `stage == N && status == 'in-progress'`).
2. Set `status: completed`, `ended_utc: <now>`, `output_files: [<list of actual files>]`, `tokens_*_actual: <actual counts if available>`.
3. Set `last_completed_stage: <stage_number>`.
4. Set `current_stage: <stage_number + 1>`.

When a stage fails or aborts:

1. Find the in-progress entry.
2. Set `status: failed`, `ended_utc: <now>`, `notes: [<+failure reason>]`.
3. Do **not** advance `last_completed_stage`.
4. `current_stage` remains the failed stage number — resume will retry from here.

When a user cancels mid-stage (Ctrl-C, `argus_cancel`):

1. Set the in-progress entry to `status: failed` with `notes: ['user-cancelled at <iso-8601>']`.
2. Exit cleanly.

## Atomicity

The manifest is written via a write-rename pattern:

```python
tmp = f"{manifest_path}.tmp"
with open(tmp, 'w') as fh:
    json.dump(manifest, fh, indent=2)
os.replace(tmp, manifest_path)
```

This ensures readers never observe a half-written manifest. The orchestrator MUST use this pattern; direct overwrites are forbidden.

## Stage-2 partial-completion

Stage 2 runs 8 attacker angles in parallel. To resume mid-Stage-2, each angle writes a per-angle completion marker as soon as it returns:

```
$RUN_DIR/2-candidate-findings/_partial.json
{
  "angles_completed": ["vector-scan", "auth-account", "math-precision"],
  "angles_in_progress": ["periphery"],
  "angles_pending": ["execution-trace", "invariant", "economic-security", "first-principles"]
}
```

When Stage 2 starts (fresh or resume), the orchestrator reads `_partial.json` (if present) and skips already-completed angles. The manifest's `resume_hint` field points at this partial-completion record.

## Stage-3-8 partial-completion

Stages 3–8 process findings serially. The partial-completion pattern is one file per finding:

```
$RUN_DIR/3-verification/F-NN/verdict.md           # written when this finding's verification completes
$RUN_DIR/4-impact/F-NN/verdict.md
$RUN_DIR/5-platform/F-NN/verdict.md
...
```

Resume reads the per-finding verdict files and resumes at the first finding without a verdict for the current stage.

## Resume entry-points

Two ways to resume:

1. **Slash command** (`/argus-resume <run-dir>`) — Claude Code only. Reads the manifest, presents a summary of completed stages, asks the user to confirm before continuing.
2. **Script** (`python3 scripts/argus_resume.py <run-dir>`) — platform-agnostic. Prints the resume plan (which stage, which sub-tasks remain) and exits with a code indicating whether resume is possible (0=resumable, 1=not resumable, 2=manifest missing/corrupt).

Both inspect the manifest using `scripts/argus_resume.py`'s parsing logic; the slash command is a UX wrapper.

## Cross-platform resume

A run started on Claude Code can be resumed on Codex CLI (and vice versa) if both have access to the same `$RUN_DIR`. The manifest's `platform` field records the **last writer**, not the run's history; on resume, the new platform appends new stage entries with its own platform stamp.

The tool-translation map (`assets/codex-tool-map.json`, see [`codex-compat.md`](codex-compat.md)) is consulted only by the platform currently running. If a Stage 5 PoC was built on Claude using `WebFetch` and the resume happens on Codex, Stage 6's `WebFetch`-equivalent (`web.run` or graceful skip) handles the new work; the Stage 5 output is read as-is.

## Manifest validation

`scripts/argus_resume.py --validate <run-dir>` checks the manifest for:

- JSON well-formedness.
- Required fields present.
- `stages[]` chronological ordering (no out-of-order timestamps).
- No two `completed` entries for the same stage number.
- `last_completed_stage` matches the actual data.
- All listed `output_files` actually exist on disk.

Invalid manifests are reported with field-level diagnostics; the user can choose to repair (`--repair`) or abandon.

## Anti-patterns

- **Modifying prior stage entries**: stage entries are append-only after `status: completed`. To re-run a completed stage, append a fresh entry; do not overwrite.
- **Setting `status: completed` before output files are flushed to disk**: the protocol guarantee is that any `status: completed` entry has its `output_files` durably present. Orchestrator must `fsync` (or rely on the write-rename atomicity) before marking complete.
- **Skipping the manifest on small runs**: Stage 0 always writes the manifest, even for a `--dry-run` cost preview. The manifest is the artifact that proves a run happened at all.

## Cross-references

- [`pipeline-overview.md`](pipeline-overview.md) — defines each stage's INPUT / OPERATIONS / OUTPUT contract; the manifest's `output_files` lists must match each stage's OUTPUT.
- [`codex-compat.md`](codex-compat.md) — the platform-detection logic at Stage 0 + the tool-translation map.
- `scripts/argus_resume.py` — the implementation.
