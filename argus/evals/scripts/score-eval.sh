#!/bin/bash
# Score an Argus eval run against ground-truth.
#
# Usage:   evals/scripts/score-eval.sh <benchmark-id>
# Reads:   evals/benchmarks/<benchmark-id>.md (ground truth)
#          evals/results/<benchmark-id>/repo/argus/<latest>/8-final/*.md (Argus output)
# Outputs: evals/results/<benchmark-id>/score.md

set -e

BENCH_ID="$1"
if [ -z "$BENCH_ID" ]; then
  echo "Usage: $0 <benchmark-id>" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BENCH_FILE="$ROOT/evals/benchmarks/$BENCH_ID.md"
RESULTS_REPO="$ROOT/evals/results/$BENCH_ID/repo"

if [ ! -f "$BENCH_FILE" ]; then
  echo "Benchmark file not found: $BENCH_FILE" >&2
  exit 1
fi

# Find the latest Argus run dir
LATEST_RUN=$(find "$RESULTS_REPO/argus" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort -r | head -1)
if [ -z "$LATEST_RUN" ]; then
  echo "No Argus run found at $RESULTS_REPO/argus/" >&2
  exit 1
fi

echo "Scoring $BENCH_ID against run at $LATEST_RUN..."

# Extract ground truth
GROUND_TRUTH=$(awk '/^FINDING/,/^expect_in:/' "$BENCH_FILE")

# Extract Argus SUBMIT findings (titles only)
ARGUS_SUBMIT=$(grep -E '^### \[' "$LATEST_RUN/8-final/submission-grade.md" 2>/dev/null | sed 's/.*\*\*F-\([0-9]*\): \(.*\)\*\*/\1: \2/' || true)
ARGUS_REFINE=$(grep -E '^## F-' "$LATEST_RUN/8-final/refine.md" 2>/dev/null | sed 's/^## F-//' || true)
ARGUS_DISCARD=$(grep -E '^## F-' "$LATEST_RUN/8-final/discard.md" 2>/dev/null | sed 's/^## F-//' || true)

SCORE_FILE="$ROOT/evals/results/$BENCH_ID/score.md"
mkdir -p "$(dirname "$SCORE_FILE")"

cat > "$SCORE_FILE" <<EOF
# Eval score — $BENCH_ID

- Benchmark: $BENCH_FILE
- Argus run: $LATEST_RUN
- Scored at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

## Ground truth

\`\`\`
$GROUND_TRUTH
\`\`\`

## Argus output

### SUBMIT bucket
$ARGUS_SUBMIT

### REFINE bucket
$ARGUS_REFINE

### DISCARD bucket
$ARGUS_DISCARD

## Manual scoring (fill in)

For each ground-truth finding:
- TP: caught in expected bucket (e.g. expect_in=submit AND finding in SUBMIT)
- FN: not caught (in DISCARD or absent)
- Severity match: yes/no
- Vector match: yes/no

For each Argus finding NOT in ground truth (extra findings):
- FP: false positive
- Adjacent: related but distinct from ground truth (acceptable — not penalized)
- Plausible novel: real bug not in ground truth (BONUS — promote to ground-truth on next eval)

## Metrics

- TP: <count>
- FN: <count>
- FP: <count>
- Recall: TP / (TP + FN) = <%>
- Precision: TP / (TP + FP) = <%>
- Severity accuracy: correct-severity-TPs / TPs = <%>
EOF

echo "Score template written: $SCORE_FILE"
echo "Manual scoring required — review $LATEST_RUN/8-final/submission-grade.md and fill in score.md."
