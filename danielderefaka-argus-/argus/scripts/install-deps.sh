#!/bin/bash
# Stage 3 helper: detect and install the Rust toolchain dependencies needed to run PoCs
# for the target's project shape (Anchor / CosmWasm / Substrate / Solana-native / generic-Rust).
#
# Usage:
#   install-deps.sh <project-root> [--dry-run | --install]
#
# Default mode: --dry-run. Prints status + install commands without running them.
# Use --install only after the user has confirmed (Stage 3 calls AskUserQuestion first).
#
# All installs are user-space (rustup, cargo, solana-install-init, avm) — no sudo.
# System packages (clang, protobuf, cmake, build-essential) are only suggested, never
# auto-installed, since they need sudo and vary by OS.

set -e

ROOT="${1:-.}"
MODE="${2:---dry-run}"

if [ "$MODE" != "--dry-run" ] && [ "$MODE" != "--install" ]; then
  echo "Usage: $0 <project-root> [--dry-run | --install]"
  exit 1
fi

cd "$ROOT"

# ─── Detect project shape ────────────────────────────────────────────────────

detect_shape() {
  if [ -f Anchor.toml ] || find . -maxdepth 3 -name 'Anchor.toml' -not -path '*/target/*' 2>/dev/null | head -1 | grep -q .; then
    echo "anchor"
  elif [ -f Cargo.toml ] && grep -q 'cosmwasm-std' Cargo.toml 2>/dev/null; then
    echo "cosmwasm"
  elif find . -maxdepth 3 -name 'Cargo.toml' -not -path '*/target/*' -exec grep -l 'cosmwasm-std' {} \; 2>/dev/null | head -1 | grep -q .; then
    echo "cosmwasm"
  elif [ -f Cargo.toml ] && grep -qE 'frame-support|frame-system|pallet-' Cargo.toml 2>/dev/null; then
    echo "substrate"
  elif find . -maxdepth 3 -name 'Cargo.toml' -not -path '*/target/*' -exec grep -lE 'frame-support|frame-system|pallet-' {} \; 2>/dev/null | head -1 | grep -q .; then
    echo "substrate"
  elif [ -f Cargo.toml ] && grep -q 'solana-program' Cargo.toml 2>/dev/null; then
    echo "solana-native"
  elif find . -maxdepth 3 -name 'Cargo.toml' -not -path '*/target/*' -exec grep -l 'solana-program' {} \; 2>/dev/null | head -1 | grep -q .; then
    echo "solana-native"
  elif [ -f Cargo.toml ] || find . -maxdepth 3 -name 'Cargo.toml' -not -path '*/target/*' 2>/dev/null | head -1 | grep -q .; then
    echo "generic-rust"
  else
    echo "unknown"
  fi
}

SHAPE="$(detect_shape)"

# ─── Tool status ─────────────────────────────────────────────────────────────

declare -a MISSING=()
declare -a INSTALL_CMDS=()

check() {
  local name="$1"; local cmd="$2"; local install_cmd="$3"; local needed="${4:-yes}"
  if [ "$needed" != "yes" ]; then
    return
  fi
  if command -v "$cmd" >/dev/null 2>&1; then
    local v
    v="$($cmd --version 2>&1 | head -1 || true)"
    printf "  ✅ %-25s %s\n" "$name" "${v:-(installed)}"
  else
    printf "  ❌ %-25s missing\n" "$name"
    MISSING+=("$name")
    INSTALL_CMDS+=("$install_cmd")
  fi
}

check_target() {
  local target="$1"; local install_cmd="$2"; local needed="${3:-yes}"
  if [ "$needed" != "yes" ]; then
    return
  fi
  if rustup target list --installed 2>/dev/null | grep -q "^${target}$"; then
    printf "  ✅ %-25s installed\n" "rustup target $target"
  else
    printf "  ❌ %-25s missing\n" "rustup target $target"
    MISSING+=("rustup target $target")
    INSTALL_CMDS+=("$install_cmd")
  fi
}

# ─── Per-shape requirements ──────────────────────────────────────────────────

# All shapes: rustup + cargo
NEED_RUSTUP=yes
NEED_WASM32=no
NEED_SOLANA=no
NEED_ANCHOR=no
NEED_AVM=no
NEED_NODE=no
NEED_YARN=no

case "$SHAPE" in
  anchor)
    NEED_SOLANA=yes
    NEED_ANCHOR=yes
    NEED_AVM=yes
    NEED_NODE=yes
    NEED_YARN=yes
    ;;
  solana-native)
    NEED_SOLANA=yes
    ;;
  cosmwasm)
    NEED_WASM32=yes
    ;;
  substrate)
    NEED_WASM32=yes
    ;;
  generic-rust)
    ;;
esac

# ─── Banner ──────────────────────────────────────────────────────────────────

echo ""
echo "Argus Stage 3 — toolchain check"
echo "  project shape: $SHAPE"
echo "  project root:  $ROOT"
echo "  mode:          $MODE"
echo ""
echo "Toolchain status:"

# ─── Checks ──────────────────────────────────────────────────────────────────

# rustup / cargo
INSTALL_RUSTUP='curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable'
check "rustup" "rustup" "$INSTALL_RUSTUP" "$NEED_RUSTUP"
check "cargo" "cargo" "(installed with rustup)" "$NEED_RUSTUP"

# wasm32 target (CosmWasm + Substrate)
check_target "wasm32-unknown-unknown" "rustup target add wasm32-unknown-unknown" "$NEED_WASM32"

# Solana CLI
INSTALL_SOLANA='sh -c "$(curl -sSfL https://release.anza.xyz/stable/install)"'
check "solana CLI" "solana" "$INSTALL_SOLANA" "$NEED_SOLANA"

# Anchor + AVM
INSTALL_AVM='cargo install --git https://github.com/coral-xyz/anchor avm --locked --force'
check "avm" "avm" "$INSTALL_AVM" "$NEED_AVM"
INSTALL_ANCHOR='avm install latest && avm use latest'
check "anchor" "anchor" "$INSTALL_ANCHOR" "$NEED_ANCHOR"

# Node + yarn (Anchor JS tests)
INSTALL_NODE_HINT='install Node.js >= 18 (https://nodejs.org or via nvm)'
check "node" "node" "$INSTALL_NODE_HINT" "$NEED_NODE"
INSTALL_YARN='npm install -g yarn'
check "yarn" "yarn" "$INSTALL_YARN" "$NEED_YARN"

# ─── Summary ─────────────────────────────────────────────────────────────────

echo ""
if [ ${#MISSING[@]} -eq 0 ]; then
  echo "✅ All required tools present. Stage 3 PoC tier 1-2 should work."
  exit 0
fi

echo "❌ Missing: ${#MISSING[@]} tool(s)"
echo ""
echo "Install commands (run in order):"
i=0
for cmd in "${INSTALL_CMDS[@]}"; do
  i=$((i + 1))
  printf "  %d. %s\n" "$i" "$cmd"
done

# ─── Optional system-package hints ───────────────────────────────────────────

case "$SHAPE" in
  substrate)
    echo ""
    echo "Substrate also commonly needs system packages:"
    if [ "$(uname)" = "Darwin" ]; then
      echo "  brew install protobuf cmake openssl@3"
    else
      echo "  sudo apt-get install -y build-essential clang curl libssl-dev llvm libudev-dev pkg-config protobuf-compiler"
    fi
    echo "  (sudo / brew required — install separately, then re-run this script)"
    ;;
  anchor|solana-native)
    echo ""
    echo "Solana programs also commonly need:"
    if [ "$(uname)" = "Darwin" ]; then
      echo "  brew install pkg-config openssl"
    else
      echo "  sudo apt-get install -y build-essential pkg-config libudev-dev libssl-dev"
    fi
    ;;
esac

# ─── Execute or stop ─────────────────────────────────────────────────────────

if [ "$MODE" = "--dry-run" ]; then
  echo ""
  echo "Dry-run mode. To install, re-run with --install:"
  echo "  $0 $ROOT --install"
  exit 2  # exit code 2 = missing tools, action required
fi

# --install mode
echo ""
echo "Installing missing tools..."
echo ""

set +e  # don't abort the whole script if one install fails — surface and continue

for cmd in "${INSTALL_CMDS[@]}"; do
  # Skip pure hint lines (those starting with 'install' or '(installed' aren't shell commands)
  case "$cmd" in
    "(installed with rustup)") continue ;;
    install*) echo "⚠️  Manual step required: $cmd"; continue ;;
  esac

  echo "→ $cmd"
  if eval "$cmd"; then
    echo "  ✅ done"
  else
    echo "  ❌ failed (exit $?). Continuing — re-run after fixing."
  fi
  echo ""
done

# Rustup post-install: source the cargo env so subsequent commands see cargo/rustup
if [ -f "$HOME/.cargo/env" ]; then
  # shellcheck source=/dev/null
  . "$HOME/.cargo/env"
fi

# Solana post-install hint
if [ "$NEED_SOLANA" = "yes" ] && ! command -v solana >/dev/null 2>&1; then
  echo "⚠️  solana CLI installed but not on PATH. Add to your shell rc:"
  echo "    export PATH=\"\$HOME/.local/share/solana/install/active_release/bin:\$PATH\""
fi

echo ""
echo "Re-run the dry-run check to verify everything landed:"
echo "  $0 $ROOT --dry-run"
