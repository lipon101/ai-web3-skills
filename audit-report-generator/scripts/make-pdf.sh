#!/usr/bin/env bash
set -euo pipefail

# Generate an audit report PDF using pandoc + eisvogel
# Usage:
#   bash make-pdf.sh <input.md> [--out <output.pdf>] [--logo </path/to/logo.pdf>] [--template </path/to/eisvogel.latex>]
# Examples:
#   bash make-pdf.sh reports/audit-report.md --out reports/audit-report.pdf
#   bash make-pdf.sh report.md --logo /path/to/custom-logo.pdf

# Locate skill assets directory (relative to this script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
ASSETS_DIR="$SKILL_DIR/assets"

TEMPLATE="${ASSETS_DIR}/eisvogel.latex"

if ! command -v pandoc >/dev/null 2>&1; then
  echo "pandoc is not installed or not in PATH." >&2
  echo "Install via Homebrew: brew install pandoc" >&2
  exit 1
fi

if [ ! -f "$TEMPLATE" ]; then
  echo "Template $TEMPLATE not found." >&2
  exit 1
fi

if [ $# -lt 1 ]; then
  echo "Usage: $0 <input.md> [--out <output.pdf>] [--logo </path/to/logo.pdf>] [--template </path/to/eisvogel.latex>]" >&2
  exit 1
fi

SRC="$1"; shift
# Convert to absolute path
SRC="$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")"
OUT="${SRC%.md}.pdf"
LOGO_SRC=""
CUSTOM_TEMPLATE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --out)
      OUT="$2"; shift 2;;
    --logo)
      LOGO_SRC="$2"; shift 2;;
    --template)
      CUSTOM_TEMPLATE="$2"; shift 2;;
    *)
      echo "Unknown option: $1" >&2; exit 1;;
  esac
done

if [ ! -f "$SRC" ]; then
  echo "Input markdown not found: $SRC" >&2
  exit 1
fi

# Convert output to absolute path if relative
case "$OUT" in
  /*) ;;  # Already absolute
  *) OUT="$(pwd)/$OUT" ;;
esac

# Use custom template if provided
if [ -n "$CUSTOM_TEMPLATE" ]; then
  if [ ! -f "$CUSTOM_TEMPLATE" ]; then
    echo "Custom template not found: $CUSTOM_TEMPLATE" >&2
    exit 1
  fi
  TEMPLATE="$CUSTOM_TEMPLATE"
fi

# Determine working directory for logo handling (where the source file is)
WORK_DIR="$(dirname "$SRC")"

# Handle logo provisioning
RESTORE_PREV=false
LOGO_PLACED=false

# Handle logo if provided
if [ -n "$LOGO_SRC" ]; then
  if [ ! -f "$LOGO_SRC" ]; then
    echo "Provided logo path not found: $LOGO_SRC" >&2
    exit 1
  fi
  case "$LOGO_SRC" in
    *.pdf|*.PDF) :;;
    *) echo "Logo must be a PDF file (got $LOGO_SRC)." >&2; exit 1;;
  esac
  if [ -f "${WORK_DIR}/logo.pdf" ]; then
    mv "${WORK_DIR}/logo.pdf" "${WORK_DIR}/logo.pdf.bak"
    RESTORE_PREV=true
  fi
  cp "$LOGO_SRC" "${WORK_DIR}/logo.pdf"
  LOGO_PLACED=true
fi

# Temporary pre-processing: strip phrases not for final deliverables
TMP_MD="${WORK_DIR}/.audit-report-tmp-$$.md"
# Remove the sentence "Auditor attributions are omitted per request" (case-insensitive)
perl -0777 -pe 's/\.?\s*Auditor attributions are omitted per request\.?//ig' "$SRC" > "$TMP_MD"

cleanup() {
  rm -f "$TMP_MD" >/dev/null 2>&1 || true
  if $LOGO_PLACED; then
    rm -f "${WORK_DIR}/logo.pdf" >/dev/null 2>&1 || true
  fi
  if $RESTORE_PREV; then
    mv -f "${WORK_DIR}/logo.pdf.bak" "${WORK_DIR}/logo.pdf"
  fi
}
trap cleanup EXIT

# Run pandoc from the source directory so logo.pdf is found
(cd "$WORK_DIR" && pandoc "$(basename "$TMP_MD")" -o "$OUT" --from markdown+raw_tex --template="$TEMPLATE" --listings)

echo "PDF written to: $OUT"
