#!/usr/bin/env bash
# ============================================================
#  ai-web3-skills — One-Command Install
#  Usage: bash <(curl -fsSL https://raw.githubusercontent.com/lipon101/ai-web3-skills/main/setup.sh)
#  OR:    git clone https://github.com/lipon101/ai-web3-skills && cd ai-web3-skills && bash setup.sh
# ============================================================
set -e

SKILLS_DIR="/home/user/skills"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   ai-web3-skills — Smart Contract Security Stack         ║"
echo "║   250 skills + full toolchain installer                  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# ── 1. Copy all skills ─────────────────────────────────────────
echo "📦 Installing skills to $SKILLS_DIR ..."
mkdir -p "$SKILLS_DIR"

SYSTEM_SKILLS="skill-creator gumloop-sdk gumcp-client trigger-builder spreadsheet-output script-connected-html-output .tools"

for skill_dir in "$REPO_DIR"/*/; do
    skill_name=$(basename "$skill_dir")
    if echo "$SYSTEM_SKILLS" | grep -qw "$skill_name"; then continue; fi
    if [[ "$skill_name" == .* ]]; then continue; fi
    if [ ! -f "$skill_dir/SKILL.md" ]; then continue; fi
    cp -rn "$skill_dir" "$SKILLS_DIR/$skill_name/" 2>/dev/null || true
done

TOTAL=$(ls "$SKILLS_DIR" | wc -l)
echo "  ✅ $TOTAL skills active"

# ── 2. Foundry (forge, cast, anvil, chisel) ────────────────────
if ! command -v forge &>/dev/null; then
    echo ""
    echo "🔨 Installing Foundry ..."
    curl -L https://foundry.paradigm.xyz | bash
    export PATH="$HOME/.foundry/bin:$PATH"
    foundryup
    echo "  ✅ Foundry $(forge --version 2>&1 | head -1)"
else
    echo "  ✅ Foundry already installed ($(forge --version 2>&1 | head -1))"
fi
export PATH="$HOME/.foundry/bin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

# ── 3. Rust + Cargo ────────────────────────────────────────────
if ! command -v rustc &>/dev/null; then
    echo ""
    echo "🦀 Installing Rust ..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    echo "  ✅ Rust $(rustc --version)"
else
    echo "  ✅ Rust already installed ($(rustc --version))"
fi
source "$HOME/.cargo/env" 2>/dev/null || true

# ── 4. Python security tools ───────────────────────────────────
echo ""
echo "🐍 Installing Python security tools ..."
pip install -q slither-analyzer crytic-compile solc-select semgrep halmos eth-wake prettytable 2>&1 | tail -3
echo "  ✅ slither, semgrep, halmos, wake"

# ── 5. Aderyn (Cyfrin, Rust-based) ────────────────────────────
if ! command -v aderyn &>/dev/null; then
    echo ""
    echo "🔍 Installing Aderyn ..."
    cargo install aderyn 2>&1 | tail -3
    echo "  ✅ Aderyn $(aderyn --version 2>&1 | head -1)"
else
    echo "  ✅ Aderyn already installed"
fi

# ── 6. Medusa fuzzer ───────────────────────────────────────────
if ! command -v medusa &>/dev/null; then
    echo ""
    echo "🐙 Installing Medusa ..."
    MEDUSA_VER="0.1.8"
    curl -sL "https://github.com/crytic/medusa/releases/download/v${MEDUSA_VER}/medusa-linux-x64.tar.gz" | tar -xz -C /tmp
    chmod +x /tmp/medusa && cp /tmp/medusa /usr/local/bin/medusa
    echo "  ✅ Medusa $(medusa --version 2>&1 | head -1)"
else
    echo "  ✅ Medusa already installed"
fi

# ── 7. Node.js tools ───────────────────────────────────────────
if ! command -v hardhat &>/dev/null; then
    echo ""
    echo "⬡ Installing Hardhat + Ganache + Solhint ..."
    npm install -g hardhat ganache solhint --silent 2>&1 | tail -3
    echo "  ✅ Hardhat, Ganache, Solhint"
else
    echo "  ✅ Hardhat already installed"
fi

# ── 8. Solc versions ───────────────────────────────────────────
echo ""
echo "🔧 Installing Solidity compiler versions ..."
for VER in 0.6.12 0.7.6 0.8.19 0.8.20 0.8.28; do
    solc-select install "$VER" 2>/dev/null || true
done
solc-select use 0.8.20 2>/dev/null || true
echo "  ✅ solc 0.6.12, 0.7.6, 0.8.19, 0.8.20 (active), 0.8.28"

# ── 9. Vyper ───────────────────────────────────────────────────
if ! command -v vyper &>/dev/null; then
    pip install -q vyper
    echo "  ✅ Vyper $(vyper --version 2>&1 | head -1)"
else
    echo "  ✅ Vyper already installed"
fi

# ── 10. PATH persistence ───────────────────────────────────────
BASHRC="$HOME/.bashrc"
PROFILE_LINE='export PATH="$HOME/.foundry/bin:$HOME/.cargo/bin:$HOME/.local/bin:$PATH"'
grep -qF ".foundry/bin" "$BASHRC" 2>/dev/null || echo "$PROFILE_LINE" >> "$BASHRC"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   ✅ INSTALL COMPLETE                                    ║"
echo "║                                                          ║"
echo "║   Tools: forge · cast · anvil · slither · aderyn        ║"
echo "║          semgrep · medusa · halmos · wake · solhint      ║"
echo "║          hardhat · ganache · vyper · rust · solc         ║"
echo "║                                                          ║"
echo "║   Skills: $TOTAL skill directories active                    ║"
echo "║                                                          ║"
echo "║   Usage: just say 'audit this contract' and paste URL   ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Run: source ~/.bashrc   (to reload PATH)"
