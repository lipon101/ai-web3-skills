# Codex CLI Compatibility — tool-translation guide

> Argus was originally built for Claude Code. As of v0.3.5 it also installs to `~/.codex/skills/argus/`. The methodology files (SKILL.md + per-stage references) are mostly tool-agnostic, but a handful of Claude Code tools used in SKILL.md have different shapes in Codex CLI. This file is the translation guide.
>
> **When running under Codex CLI**: read this file at session start (the Codex orchestrator should auto-load it when the Argus skill is triggered). Apply the translation rules below in place of the Claude Code tool calls SKILL.md describes.

## Platform detection

The orchestrator can detect platform at session start:

- **Claude Code**: `CLAUDE_PROJECT_DIR` or `CLAUDE_CONFIG_DIR` env vars set; tools `AskUserQuestion`, `TodoWrite`, `Task`, `WebFetch`, `WebSearch`, `Skill` available.
- **Codex CLI**: `CODEX_HOME` env var set; the Codex tool surface (typically `bash`, `read`, `edit`, `write`, `web.run` or similar) available; no `AskUserQuestion` / `TodoWrite` as first-class tools.

If neither set of indicators matches, assume Claude Code (the original target) and surface a warning.

## Tool-by-tool translation

### `AskUserQuestion` → plain prompt + structured choice

Claude Code's `AskUserQuestion` is a structured-options tool. Codex doesn't have it as a first-class tool. Equivalent behavior:

```
ASK THE USER VIA PLAIN OUTPUT:

  "<question>"

  Options:
  [A] <label> — <description>
  [B] <label> — <description>
  [C] Other (please describe)

  Reply with A / B / C / your choice.
```

Then wait for the user's reply before proceeding. Don't auto-select.

**Stages that use this in Argus**:
- Stage 0 — cost-preview authorization (A Proceed / B Cap at Stage N / C Reduce scope / D Cancel)
- Stage 0 — audit-mode selection when ambiguous (`smart-contract` vs `infra`)
- Stage 3 — toolchain install prompt (`install` / `skip-with-cap` / `cancel`)
- Stage 5 — Cantina manual-validation acknowledgment (smart-contract mode only)
- Stage 8 — platform template selection (`Code4rena` / `Sherlock` / `Cantina` / `Immunefi` / `HackenProof` / `CodeHawks` / `Generic` / `Skip`)
- (infra) Stage 5 — disclosure-path confirmation when borderline (`vendor-coordinated` / `vendor-report` / `cve-disclosure` / `generic-infra`)
- (infra) Stage 6 — CVE decision when matrix says OPTIONAL

For each, print the question + options to the user; wait; proceed on reply.

### `TodoWrite` → markdown checklist file

Claude Code's `TodoWrite` maintains an in-context todo list with one-todo-in-progress-at-a-time discipline. Codex doesn't have this as a first-class tool. Equivalent behavior:

Write a file at `$RUN_DIR/_todos.md` with the following format:

```markdown
# Argus run todo list — <timestamp>

- [x] Stage 0: Cost preview + user authorization
- [ ] Stage 1: Protocol mapping  ← in progress
- [ ] Stage 2: Candidate finding generation (8 parallel angles)
- [ ] Stage 3: PoC generation (gate)
- [ ] Stage 4: Adversarial challenge + severity calibration
- [ ] Stage 5: Platform validation
- [ ] Stage 6: Program-specific triage
- [ ] Stage 7: Duplication triage
- [ ] Stage 8: Final submission-grade output
```

- Mark `[x]` when complete.
- Mark `← in progress` on the currently-active stage.
- Exactly one stage `← in progress` at a time.
- Update the file at each stage transition (mark prior `[x]`, add `← in progress` to next).
- Print the current list state to the user at each transition.

This satisfies the same discipline SKILL.md requires for Claude Code.

### `Task` (subagent dispatch) → Codex sub-conversations or sequential dispatch

Claude Code's `Task` tool dispatches general-purpose subagents in parallel. Codex's equivalent depends on Codex's current subagent feature:

- **If Codex has parallel-subagent dispatch** (e.g., a `dispatch_subagent` or equivalent): use it. Same semantics — each angle / checker runs in its own context with its own prompt.
- **If not** (default conservative assumption): run the angles **sequentially** in the main conversation. Cost the same number of tokens; lose the parallelism speedup.

**Where Argus dispatches subagents**:
- Stage 2 — 8 angles in parallel (>10 in-scope files). Fallback: sequential.
- Stage 4 Wave 2 — 4 Sonnet checkers per Pass A + 4 Opus checkers per Pass B per finding. Fallback: sequential. Or skip Wave 2 entirely on Codex and rely on the orchestrator's single-pass verification (note: this weakens the unanimity rule).
- Stage 4 External research wave — 1 Sonnet research agent per external-system claim. Fallback: orchestrator-internal WebSearch + WebFetch in main conversation.
- Stage 4 Mitigation viability check — 1 background Sonnet agent. Fallback: synchronous orchestrator analysis.
- Phase 8a-pre joint Pass C judge — 1 Pass C judge per overlapping pair. Fallback: synchronous.
- Stage 8.5 REFINE loop — 1 subagent per refine-pattern. Fallback: synchronous per pattern.

Sequential fallback: the run takes longer but produces the same per-stage artifacts.

### `WebFetch` → `web.run` (or equivalent Codex web tool)

Codex has web access via its own tool surface (commonly `web.run` or a `fetch_url` action). Same semantics: pass URL, get content. Use whatever Codex's current web tool is named.

**Where Argus uses WebFetch**:
- Stage 4 External research wave — fetch comparator docs / source.
- Stage 5 — fetch live platform criteria URL.
- Stage 6 — fetch the bounty page (the single highest-leverage WebFetch in the pipeline).
- Stage 7 — fall back to WebFetch on GitHub URLs if `gh` CLI isn't installed.
- Stage 9 (infra Group H) — fetch RustSec advisory body for the caveat check.

### `WebSearch` → Codex's web search tool

Same translation as WebFetch. Codex's equivalent is typically `web.run` with a query parameter.

**Where Argus uses WebSearch**:
- Stage 4 External research wave — search for authoritative docs on external-system behavior.

### `Skill` (Claude Code skill loader) → Codex auto-load

Claude Code can explicitly invoke another skill via the `Skill` tool. Codex auto-loads skills based on description-match. Translation: don't try to invoke other skills explicitly under Codex — let the orchestrator description-match handle it. Argus doesn't currently invoke other skills, so this is informational only.

### `Bash` / `Read` / `Edit` / `Write` / `Grep` / `Glob` — universal

These work identically on both platforms. The actual tool names may differ slightly (e.g., Codex may use `shell.run` instead of `Bash`) but the semantics are the same. SKILL.md instructions referring to these work as-is.

## Codex-specific notes

### Restart Codex after install

Per Codex's skill-installer docs: "Restart Codex to pick up new skills." After running `./install.sh` (which copies to `~/.codex/skills/argus/`), the user must restart their Codex session for Argus to be available.

### No slash-command equivalent

Codex doesn't have Claude Code's `/argus` slash command. Invocation is conversational:

- "audit this rust codebase with argus"
- "run argus on this"
- "find rust bugs"
- "rust security review"
- "submission-grade audit"
- "verify this fix" (Stage 9)

These trigger phrases are in the Argus SKILL.md `description:` field. Codex's description-matching auto-loads Argus when the user's message hits one of them.

### Sandbox / network escalation

Codex skills' scripts that need network access (e.g., `scripts/install-deps.sh`, `scripts/install-infra-deps.sh`) may need to request sandbox escalation when running in Codex's default sandboxed mode. The skill-installer SKILL.md notes: "in the sandbox, request escalation when running them."

If a script fails with a sandbox-permission error, the orchestrator should:
1. Notify the user: "this script needs network access; please grant sandbox escalation."
2. Wait for confirmation.
3. Retry.

### Model differences

Codex uses GPT-5 / GPT-5-Codex models; Claude Code uses Claude. The methodology in SKILL.md is model-agnostic, but specific calibrations may differ:

- The `Pass C / Pass D` Opus-judge specification (in `adversarial-review.md`) assumes a strong synthesis-capable model. GPT-5 is a strong analog; behavior should be comparable. Calibration debt acknowledged in `ARGUS_AUDIT.md` C-1 applies equally.
- The Wave-2 unanimity rule (2 Sonnet checkers / 2 Opus checkers) — on Codex, substitute "2 fast-model checkers / 2 deep-model checkers" using whatever model tiering Codex offers. Behavioral discipline (unanimity required for auto-kill) stays the same.
- The infra-mode Tier-1-live-e2e requirement (v0.3.3) is deterministic-backend-driven (Miri / Kani / Loom / cargo-fuzz / cargo-audit); model choice is irrelevant for the verification verdict.

### Tool-name normalization

If the orchestrator needs to write tool-invocation instructions to the user, prefer **generic action language** ("run cargo audit", "fetch the bounty URL", "ask the user", "save the verdict file") over **platform-specific tool names** ("call WebFetch with URL X"). The user-facing language is the same on both platforms.

## What's NOT translated

These Argus mechanics work identically on both platforms (no translation needed):

- Stage discipline (acyclic pipeline, per-stage verdict files)
- FINDING schema fields (`weaponization_check`, `reachability_check`, `code_comment_scan`, etc.)
- Confidence model + scoring
- All `references/*.md` per-stage methodology
- All vector catalogues (V1–V132 SC, A01–I12 infra)
- All Stage-3 deterministic backends (Miri / Kani / Loom / Rudra / cargo-fuzz / cargo-audit) — these are external tools invoked via shell, identical on both platforms
- Stage 4 Impact × Reachability matrix (infra mode) + Python scripts (`reachability.py`, `assign_severity.py`)
- All Stage-1-8 file paths under `$RUN_DIR/`

## What's NOT yet tested on Codex

- The full v0.3.x infra-mode pipeline has been validated on Claude Code (monero-oxide F-07 case, etc.). Codex validation is pending — first real Codex run will surface tool-translation gaps not covered above.
- The exact tool-call format Codex's GPT-5 expects for shell invocation, web fetches, and structured prompts may have evolved since this file was written. If a tool call fails with an unrecognized-tool error, consult Codex's current docs and update this translation table.

## v0.5.0 — Runtime tool-translation driver

The conceptual translation table in this file is now backed by a runtime helper script: [`scripts/codex_driver.py`](../scripts/codex_driver.py). When running under Codex CLI (detected via `CODEX_HOME` env var), the orchestrator invokes the driver to perform the four Claude-only operations:

| Operation | Driver subcommand |
|-----------|-------------------|
| `AskUserQuestion` | `codex_driver.py ask --run-dir $RUN_DIR --question "..." --options "A,B,C"` (writes question to `_pending_question.md`, polls `_pending_answer.md`) |
| `TodoWrite` | `codex_driver.py todo --run-dir $RUN_DIR --add "..."` / `--start "..."` / `--done "..."` / `--list` (markdown checklist at `_todos.md`) |
| `WebFetch` | `codex_driver.py fetch --run-dir $RUN_DIR --url "..." --out body.html` (curl + cache; records URL in `_unfetched_urls.txt` on failure) |
| Checkpoint manifest | `codex_driver.py manifest --run-dir $RUN_DIR --start-stage N` / `--end-stage N` (per [`checkpoint-protocol.md`](checkpoint-protocol.md)) |

Both platforms can use the driver — under Claude Code, it's a fallback that works identically to native tools. Under Codex, it's required.

The machine-readable translation map is at [`assets/codex-tool-map.example.json`](../assets/codex-tool-map.example.json). Copy to `assets/codex-tool-map.json` and customize for your Codex deployment if its tool surface differs.

## v0.5.0 — Resumable pipeline

Argus runs that crash, time out, hit a subscription window, or get user-cancelled mid-stage can be resumed from the last checkpoint via:

```bash
# Slash command (Claude Code)
/argus-resume <run-dir>

# Script (platform-agnostic)
python3 ~/.claude/skills/argus/scripts/argus_resume.py <run-dir>
```

The resume helper reads `$RUN_DIR/_manifest.json` (the checkpoint manifest written by every stage) and reports:

- Completed stages with timestamps + token costs.
- The next stage to resume from + reason (next-after-completed / in-progress at crash / failed-needs-retry).
- Per-stage partial-completion info (Stage 2's parallel angles, Stages 3-8's per-finding verdicts).
- Validation issues (manifest inconsistencies, missing output files).

A run resumed under Codex from a Claude-Code-originated `$RUN_DIR` (or vice versa) works as long as both have access to the same files; the manifest's `platform` field updates per-write.

See [`checkpoint-protocol.md`](checkpoint-protocol.md) for the manifest schema and the per-stage write protocol.

## If you hit a translation gap

If you're running Argus under Codex and hit a step where SKILL.md says to call a tool that doesn't exist on Codex, the rule is: **degrade gracefully to the closest equivalent and continue, with a `[CODEX-COMPAT]` note in the relevant verdict file** so the user can audit the fallback later.

Example: if Stage 4 calls for "spawn 4 parallel Sonnet checkers" and Codex's parallel-dispatch isn't available, the orchestrator writes to the verdict file:

```
[CODEX-COMPAT] Wave 2 ran sequentially in main conversation
(Codex parallel-dispatch not available); 4 checks completed serially
in ~4× wall-clock vs Claude Code's parallel execution. Unanimity rule
applied unchanged.
```

This preserves audit-trail honesty and flags areas where Codex compatibility could be tightened.
