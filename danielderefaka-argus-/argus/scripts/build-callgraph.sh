#!/bin/bash
# Argus callgraph builder (NEW v0.4.1).
#
# Drives a SCIP indexer over a Rust workspace, then converts the SCIP index
# into the JSON callgraph format consumed by scripts/reachability.py.
# When this script produces the callgraph, downstream FINDINGs are eligible
# for the [LSP-TRACE] evidence tag (per shared-rules.md § Evidence-quality tags).
# When this script cannot run (no SCIP indexer installed), reachability.py
# falls back to its grep-based caller search and findings carry only
# [CODE-TRACE].
#
# Usage:
#   build-callgraph.sh <project-root> --output <callgraph.json>
#   build-callgraph.sh <project-root> --output <callgraph.json> --indexer rust-analyzer
#   build-callgraph.sh <project-root> --output <callgraph.json> --indexer scip-rust
#   build-callgraph.sh <project-root> --output <callgraph.json> --auto
#
# Indexer selection:
#   --auto (default) — try rust-analyzer first, fall back to scip-rust
#   --indexer rust-analyzer — fail if rust-analyzer not installed
#   --indexer scip-rust — fail if scip-rust not installed
#
# Exit codes:
#   0 — callgraph written
#   1 — converted with warnings (e.g. unresolved external symbols)
#   2 — invocation error (bad project root, no indexer found, indexer failed)

set -u

PROJECT_ROOT=""
OUTPUT=""
INDEXER="auto"
KEEP_SCIP=0

usage() {
  sed -n '1,30p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage ;;
    --output|-o) shift; OUTPUT="$1" ;;
    --indexer) shift; INDEXER="$1" ;;
    --auto) INDEXER="auto" ;;
    --keep-scip) KEEP_SCIP=1 ;;
    --*) echo "ERROR: unknown flag: $1" >&2; exit 2 ;;
    *) if [ -z "$PROJECT_ROOT" ]; then PROJECT_ROOT="$1"; else echo "ERROR: unexpected arg: $1" >&2; exit 2; fi ;;
  esac
  shift
done

if [ -z "$PROJECT_ROOT" ]; then
  echo "ERROR: project root required (positional arg)" >&2
  exit 2
fi
if [ -z "$OUTPUT" ]; then
  echo "ERROR: --output <callgraph.json> required" >&2
  exit 2
fi
if [ ! -d "$PROJECT_ROOT" ]; then
  echo "ERROR: project root not a directory: $PROJECT_ROOT" >&2
  exit 2
fi
if [ ! -f "$PROJECT_ROOT/Cargo.toml" ]; then
  echo "ERROR: $PROJECT_ROOT/Cargo.toml not found — not a Rust workspace?" >&2
  exit 2
fi

# Resolve SCIP_DIR — temp dir for the .scip file
SCIP_DIR=$(mktemp -d -t argus-scip-XXXXXX)
trap '[ $KEEP_SCIP -eq 1 ] || rm -rf "$SCIP_DIR"' EXIT
SCIP_FILE="$SCIP_DIR/index.scip"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# ─── Select + run the indexer ─────────────────────────────────────────────────

have_ra=0
have_scip_rust=0
command -v rust-analyzer >/dev/null 2>&1 && have_ra=1
command -v scip-rust >/dev/null 2>&1 && have_scip_rust=1

run_rust_analyzer() {
  echo "→ Indexing with rust-analyzer scip" >&2
  ( cd "$PROJECT_ROOT" && rust-analyzer scip . --output "$SCIP_FILE" 2>&1 ) || return $?
}

run_scip_rust() {
  echo "→ Indexing with scip-rust" >&2
  ( cd "$PROJECT_ROOT" && scip-rust index --output "$SCIP_FILE" 2>&1 ) || return $?
}

case "$INDEXER" in
  rust-analyzer)
    if [ $have_ra -ne 1 ]; then
      echo "ERROR: rust-analyzer not found in PATH" >&2; exit 2
    fi
    run_rust_analyzer || { echo "ERROR: rust-analyzer scip failed" >&2; exit 2; }
    ;;
  scip-rust)
    if [ $have_scip_rust -ne 1 ]; then
      echo "ERROR: scip-rust not found in PATH" >&2; exit 2
    fi
    run_scip_rust || { echo "ERROR: scip-rust failed" >&2; exit 2; }
    ;;
  auto)
    if [ $have_ra -eq 1 ]; then
      if ! run_rust_analyzer; then
        echo "WARN: rust-analyzer scip failed; trying scip-rust" >&2
        if [ $have_scip_rust -eq 1 ]; then
          run_scip_rust || { echo "ERROR: both indexers failed" >&2; exit 2; }
        else
          echo "ERROR: rust-analyzer failed and scip-rust not installed" >&2; exit 2
        fi
      fi
    elif [ $have_scip_rust -eq 1 ]; then
      run_scip_rust || { echo "ERROR: scip-rust failed" >&2; exit 2; }
    else
      echo "ERROR: no SCIP indexer found in PATH (need rust-analyzer or scip-rust)" >&2
      echo "  Install one of:" >&2
      echo "    rustup component add rust-analyzer       # bundled with rustup" >&2
      echo "    cargo install scip-rust                  # standalone" >&2
      exit 2
    fi
    ;;
  *)
    echo "ERROR: unknown --indexer value: $INDEXER" >&2; exit 2 ;;
esac

if [ ! -s "$SCIP_FILE" ]; then
  echo "ERROR: SCIP indexer produced no output at $SCIP_FILE" >&2
  exit 2
fi

# ─── Convert SCIP → callgraph JSON ───────────────────────────────────────────

CONVERTER="$SCRIPT_DIR/scip_to_callgraph.py"
if [ ! -f "$CONVERTER" ]; then
  echo "ERROR: converter script missing: $CONVERTER" >&2
  exit 2
fi

python3 "$CONVERTER" "$SCIP_FILE" --output "$OUTPUT"
RC=$?

if [ $KEEP_SCIP -eq 1 ]; then
  echo "→ SCIP index preserved at $SCIP_FILE" >&2
fi

exit $RC
