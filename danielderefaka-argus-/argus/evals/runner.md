# Eval Runner

Run the Argus skill against benchmark Rust repos and compare results to ground truth. Mirrors the Solidity Auditor's eval pattern, adapted for Rust ecosystems.

## Usage

```
claude "read evals/runner.md and run all benchmarks"
claude "read evals/runner.md and run <benchmark-name>"
```

## Setup

Resolve paths, create the plugin symlink, get the commit hash, and generate a timestamp.

`SKILL_DIR` is the `argus/` directory (parent of `evals/`). `REPO_ROOT` is its parent (the git repo root). Both must be absolute paths.

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_DIR="$REPO_ROOT/argus"
mkdir -p /tmp/argus-plugin/skills && ln -sfn "$SKILL_DIR" /tmp/argus-plugin/skills/argus
COMMIT=$(git -C "$REPO_ROOT" rev-parse --short=7 HEAD)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
echo "commit=$COMMIT timestamp=$TIMESTAMP"
```

## Run

Each `.md` file in `evals/benchmarks/` is a benchmark with frontmatter:

```yaml
---
repo_url: https://github.com/<owner>/<repo>
repo_ref: <commit-or-tag>           # optional, defaults to main
project_path: programs/my-program   # optional, the path within the repo (Cargo workspace member)
project_shape: anchor | cosmwasm | substrate | generic-rust
bounty_url: <bounty page or "none">
target_repo: <github URL or "none">
---
```

The body of the benchmark file lists ground-truth findings in this format (one per line):

```
FINDING | severity: <Critical|High|Medium|Low> | crate: <name> | module: <module::path> | function: <function_name> | bug_class: <kebab-tag>
description: <one-sentence root cause>
```

Run all benchmarks unless the user named specific ones.

For each benchmark:
1. Clone the repo (shallow, skip if `/tmp/eval-{name}` exists).
2. Create `{run_dir}` at `evals/results/{name}/{timestamp}-{commit}`.

Run benchmarks **sequentially** in deterministic order (alphabetical by benchmark filename). Each run gets a fresh `claude` process so context does not carry over.

The `--plugin-dir /tmp/argus-plugin` flag is **required** — it makes the skill discoverable via the symlink created in Setup.

```bash
BENCHMARKS_DIR="$SKILL_DIR/evals/benchmarks"
RESULTS_DIR="$SKILL_DIR/evals/results"

for bench_file in "$BENCHMARKS_DIR"/*.md; do
  [ -f "$bench_file" ] || continue
  name=$(basename "$bench_file" .md)
  [ "$name" = "README" ] && continue

  PROJECT_PATH=$(grep '^project_path:' "$bench_file" | sed 's/project_path: *//' || true)
  WORK_DIR="/tmp/eval-$name${PROJECT_PATH:+/$PROJECT_PATH}"
  RUN_DIR="$RESULTS_DIR/$name/$TIMESTAMP-$COMMIT"

  echo "=== Starting $name ==="
  mkdir -p "$RUN_DIR"
  cd "$WORK_DIR"
  claude --print --plugin-dir /tmp/argus-plugin --dangerously-skip-permissions \
    "run argus skill end-to-end on this codebase, no manual prompts" 2>&1 \
    | tee "$RUN_DIR/full-output.txt"

  # Copy the latest argus run output into the eval run dir
  latest_argus_run=$(ls -dt argus/*/ 2>/dev/null | head -1)
  if [ -n "$latest_argus_run" ]; then
    cp -r "$latest_argus_run"* "$RUN_DIR/" 2>/dev/null
  fi
  cp "$bench_file" "$RUN_DIR/ground-truth.md"
  echo "=== Finished $name ==="
done
echo "All benchmarks complete."
```

## Compare

After all runs complete, for each `{run_dir}`:
1. Read `evals/compare.md`
2. Compare `{run_dir}/ground-truth.md` against `{run_dir}/8-final/submission-grade.md` (and `refine.md`, `discard.md` for missed findings)
3. Write `summary.md` to `{run_dir}/`

Print each summary and `=== All done. {count} benchmarks. ===`

## Notes

- LLM output is non-deterministic. Run each benchmark 3 times and use the best run for headline metrics; report variance separately.
- Argus's strict gates may KILL findings the ground truth marks as valid (e.g., a finding without a runnable PoC). This is correct behavior — the ground truth file should mark such findings with `expect_in: refine` or `expect_in: discard` to avoid penalizing the gate.
- Ground-truth files should reflect what's actually in the audited codebase, not aspirational findings.
