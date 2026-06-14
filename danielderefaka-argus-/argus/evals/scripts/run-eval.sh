#!/bin/bash
# Argus regression eval runner.
#
# For each benchmark in evals/benchmarks/, clone the repo at the pinned ref,
# run Argus end-to-end, and compare the SUBMIT/REFINE/DISCARD bucket assignments
# against the benchmark's ground-truth `expect_in:` annotations.
#
# Usage:   evals/scripts/run-eval.sh [benchmark-id]
# Example: evals/scripts/run-eval.sh bench-001-anchor-missing-signer
#          evals/scripts/run-eval.sh all

set -e

BENCH_DIR="$(cd "$(dirname "$0")/../benchmarks" && pwd)"
RESULTS_DIR="$(cd "$(dirname "$0")/.." && pwd)/results"
mkdir -p "$RESULTS_DIR"

run_one() {
  local BENCH_FILE="$1"
  local BENCH_ID="$(basename "$BENCH_FILE" .md)"
  echo "═══ Running $BENCH_ID ═══"

  # Parse frontmatter
  local REPO_URL=$(grep '^repo_url:' "$BENCH_FILE" | sed 's/repo_url: //' | tr -d '"')
  local REPO_REF=$(grep '^repo_ref:' "$BENCH_FILE" | sed 's/repo_ref: //' | tr -d '"')

  if [[ "$REPO_URL" == "<fill-in"* ]]; then
    echo "  SKIP: $BENCH_ID is a scaffold (no real repo URL)"
    return
  fi

  local WORK_DIR="$RESULTS_DIR/$BENCH_ID"
  rm -rf "$WORK_DIR"
  mkdir -p "$WORK_DIR"
  cd "$WORK_DIR"

  echo "  Cloning $REPO_URL @ $REPO_REF..."
  git clone --depth 50 "$REPO_URL" repo 2>/dev/null
  cd repo
  git checkout "$REPO_REF" 2>/dev/null || true

  echo "  Running Argus (manual: invoke /argus in Claude Code on $WORK_DIR/repo)"
  echo "  Then capture $WORK_DIR/repo/argus/<timestamp>/8-final/submission-grade.md"
  echo "  Run: evals/scripts/score-eval.sh $BENCH_ID"
}

if [ -z "$1" ] || [ "$1" = "all" ]; then
  for BENCH in "$BENCH_DIR"/bench-*.md; do
    run_one "$BENCH"
  done
else
  BENCH_FILE="$BENCH_DIR/$1.md"
  if [ ! -f "$BENCH_FILE" ]; then
    echo "Benchmark not found: $1" >&2
    echo "Available:" >&2
    ls "$BENCH_DIR" | grep '^bench-' >&2
    exit 1
  fi
  run_one "$BENCH_FILE"
fi

echo
echo "═══ Eval runs complete ═══"
echo "Argus runs are MANUAL — invoke /argus in Claude Code on each repo, then run score-eval.sh."
echo "(Future: automate via Claude Agent SDK once deployed.)"
