#!/bin/bash
# Stage 3 (infra mode) pre-flight toolchain installer.
# Detects + reports + (with --install) installs the deterministic verification backends:
#   cargo-miri (nightly), cargo-kani, cargo-fuzz, cargo-audit, cargo-deny, cargo-geiger
# Plus runs `cargo kani setup` and `rustup +nightly component add miri` when --install.
#
# Usage:   install-infra-deps.sh <project-root> [--dry-run | --install]
# Default: --dry-run (no installs; reports presence + exit code 0 if all present, 2 if missing).
#
# Mirrors the SC-mode install-deps.sh pattern; do NOT sudo-install. System-package suggestions
# (clang, libssl-dev, cmake) are surfaced for the user to handle separately.

set -e
ROOT="${1:-.}"
MODE="${2:---dry-run}"

cd "$ROOT"

MISSING=()
PRESENT=()

# ─── rustup nightly (required for Miri + cargo-fuzz) ──────────────────────────

if rustup toolchain list 2>/dev/null | grep -q '^nightly'; then
  PRESENT+=("nightly toolchain")
else
  MISSING+=("nightly toolchain")
fi

# ─── cargo-miri component on nightly ──────────────────────────────────────────

if rustup +nightly component list --installed 2>/dev/null | grep -q '^miri'; then
  PRESENT+=("cargo-miri")
else
  MISSING+=("cargo-miri")
fi

# ─── cargo-kani ───────────────────────────────────────────────────────────────

if command -v cargo-kani >/dev/null 2>&1; then
  PRESENT+=("cargo-kani")
else
  MISSING+=("cargo-kani")
fi

# ─── cargo-fuzz (needs nightly to actually run, but the binary is stable) ─────

if command -v cargo-fuzz >/dev/null 2>&1; then
  PRESENT+=("cargo-fuzz")
else
  MISSING+=("cargo-fuzz")
fi

# ─── cargo-audit ──────────────────────────────────────────────────────────────

if command -v cargo-audit >/dev/null 2>&1; then
  PRESENT+=("cargo-audit")
else
  MISSING+=("cargo-audit")
fi

# ─── cargo-deny ───────────────────────────────────────────────────────────────

if command -v cargo-deny >/dev/null 2>&1; then
  PRESENT+=("cargo-deny")
else
  MISSING+=("cargo-deny")
fi

# ─── cargo-geiger ─────────────────────────────────────────────────────────────

if command -v cargo-geiger >/dev/null 2>&1; then
  PRESENT+=("cargo-geiger")
else
  MISSING+=("cargo-geiger")
fi

# ─── rudra (optional; out-of-tree) ────────────────────────────────────────────

if command -v rudra >/dev/null 2>&1 || command -v cargo-rudra >/dev/null 2>&1; then
  PRESENT+=("rudra")
else
  # rudra is not always installable; flag as informational missing
  MISSING+=("rudra (optional; Angle 2 falls back to Kani + manual)")
fi

# ─── Report ───────────────────────────────────────────────────────────────────

echo "=== infra-mode toolchain check (Stage 3) ==="
echo
echo "Present (${#PRESENT[@]}):"
for t in "${PRESENT[@]}"; do echo "  ✓ $t"; done
echo
echo "Missing (${#MISSING[@]}):"
for t in "${MISSING[@]}"; do echo "  ✗ $t"; done
echo

# ─── Install mode ─────────────────────────────────────────────────────────────

if [ "$MODE" = "--install" ]; then
  if [ ${#MISSING[@]} -eq 0 ]; then
    echo "All tools present; nothing to install."
    exit 0
  fi

  echo "Installing missing tools (user-space only; no sudo)..."
  echo

  if [[ " ${MISSING[*]} " =~ " nightly toolchain " ]]; then
    echo ">>> rustup install nightly"
    rustup install nightly
  fi

  if [[ " ${MISSING[*]} " =~ " cargo-miri " ]]; then
    echo ">>> rustup +nightly component add miri"
    rustup +nightly component add miri
  fi

  if [[ " ${MISSING[*]} " =~ " cargo-kani " ]]; then
    echo ">>> cargo install --locked kani-verifier"
    cargo install --locked kani-verifier
    echo ">>> cargo kani setup"
    cargo kani setup
  fi

  if [[ " ${MISSING[*]} " =~ " cargo-fuzz " ]]; then
    echo ">>> cargo install cargo-fuzz"
    cargo install cargo-fuzz
  fi

  if [[ " ${MISSING[*]} " =~ " cargo-audit " ]]; then
    echo ">>> cargo install cargo-audit"
    cargo install cargo-audit
  fi

  if [[ " ${MISSING[*]} " =~ " cargo-deny " ]]; then
    echo ">>> cargo install cargo-deny"
    cargo install cargo-deny
  fi

  if [[ " ${MISSING[*]} " =~ " cargo-geiger " ]]; then
    echo ">>> cargo install cargo-geiger"
    cargo install cargo-geiger
  fi

  echo
  echo "Install pass complete. Re-running dry-run check..."
  exec "$0" "$ROOT" --dry-run
fi

# ─── System-package suggestions (informational only) ──────────────────────────

echo "=== System-package suggestions (install separately if not present) ==="
echo "  - clang / lld   (Kani: CBMC backend may need)"
echo "  - cmake          (cargo-deny / various builds)"
echo "  - libssl-dev     (cargo-audit advisory DB fetch)"
echo "  - pkg-config     (general)"
echo
echo "On macOS: 'brew install cmake llvm' covers most."
echo "On Debian/Ubuntu: 'apt install clang cmake pkg-config libssl-dev'."
echo

# ─── Exit code ────────────────────────────────────────────────────────────────

# Required (non-optional) missing tools trigger exit 2.
# rudra is optional; missing rudra alone does not trip exit 2.
REQUIRED_MISSING=0
for t in "${MISSING[@]}"; do
  if [[ ! "$t" =~ ^rudra ]]; then
    REQUIRED_MISSING=$((REQUIRED_MISSING + 1))
  fi
done

if [ "$REQUIRED_MISSING" -gt 0 ]; then
  echo "EXIT 2: $REQUIRED_MISSING required tool(s) missing."
  echo "Run with --install to install user-space tools, or skip-with-coverage-cap at Stage 3."
  exit 2
fi

echo "EXIT 0: all required tools present."
exit 0
