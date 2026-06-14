#!/bin/bash
#
# Argus installer — installs to Claude Code (~/.claude/skills/) and/or Codex CLI (~/.codex/skills/)
# whichever (or both) are present.
#
# Usage:
#   ./install.sh                  — install to all detected targets
#   ./install.sh --target claude  — Claude Code only
#   ./install.sh --target codex   — Codex CLI only
#   ./install.sh --target both    — both (alias for default)

set -e

SKILL_NAME="argus"
SKILL_VERSION="$(cat VERSION)"
TARGET="${1:---all}"   # supports --target claude|codex|both|all (default: all)
case "$1" in
  --target)
    TARGET="$2"
    ;;
esac

# Normalize: --all and --target both → both
case "$TARGET" in
  --all|both) TARGET="both" ;;
  claude)     TARGET="claude" ;;
  codex)      TARGET="codex" ;;
  *)
    # Unknown arg → default to both
    TARGET="both"
    ;;
esac

CLAUDE_DIR="$HOME/.claude"
CODEX_DIR="$HOME/.codex"

CLAUDE_AVAILABLE=0
CODEX_AVAILABLE=0
[ -d "$CLAUDE_DIR" ] && CLAUDE_AVAILABLE=1
[ -d "$CODEX_DIR" ]  && CODEX_AVAILABLE=1

echo ""
echo "Installing Argus v$SKILL_VERSION..."
echo ""
echo "Targets detected: Claude=$CLAUDE_AVAILABLE, Codex=$CODEX_AVAILABLE"
echo "Requested target: $TARGET"
echo ""

# ─── Reusable install function ────────────────────────────────────────────────

install_skill_to_dir() {
  local SKILLS_BASE="$1"      # e.g., ~/.claude/skills or ~/.codex/skills
  local COMMANDS_BASE="$2"    # e.g., ~/.claude/commands or "" (Codex has no slash-commands dir)
  local PLATFORM_LABEL="$3"   # human-readable label

  local SKILLS_DIR="$SKILLS_BASE/$SKILL_NAME"

  echo "→ Installing to $PLATFORM_LABEL: $SKILLS_DIR"

  mkdir -p "$SKILLS_DIR/references/hacking-agents/infra" \
           "$SKILLS_DIR/references/attack-vectors" \
           "$SKILLS_DIR/references/platform-criteria" \
           "$SKILLS_DIR/references/report-templates/infra" \
           "$SKILLS_DIR/references/skills" \
           "$SKILLS_DIR/references/strategies" \
           "$SKILLS_DIR/references/research" \
           "$SKILLS_DIR/scripts" \
           "$SKILLS_DIR/assets"

  cp SKILL.md "$SKILLS_DIR/SKILL.md"
  cp VERSION "$SKILLS_DIR/VERSION"
  cp CHANGELOG.md "$SKILLS_DIR/CHANGELOG.md"
  cp references/*.md "$SKILLS_DIR/references/"
  cp references/hacking-agents/*.md "$SKILLS_DIR/references/hacking-agents/"
  cp references/hacking-agents/infra/*.md "$SKILLS_DIR/references/hacking-agents/infra/" 2>/dev/null || true
  cp references/attack-vectors/*.md "$SKILLS_DIR/references/attack-vectors/"
  cp references/platform-criteria/*.md "$SKILLS_DIR/references/platform-criteria/"
  cp references/report-templates/*.md "$SKILLS_DIR/references/report-templates/"
  cp references/report-templates/infra/*.md "$SKILLS_DIR/references/report-templates/infra/" 2>/dev/null || true
  cp references/skills/*.md "$SKILLS_DIR/references/skills/" 2>/dev/null || true
  cp references/strategies/*.md "$SKILLS_DIR/references/strategies/" 2>/dev/null || true
  cp references/research/*.md "$SKILLS_DIR/references/research/" 2>/dev/null || true
  cp scripts/*.sh "$SKILLS_DIR/scripts/" 2>/dev/null || true
  cp scripts/*.py "$SKILLS_DIR/scripts/" 2>/dev/null || true
  cp assets/*.example.json "$SKILLS_DIR/assets/" 2>/dev/null || true
  chmod +x "$SKILLS_DIR/scripts/"*.sh 2>/dev/null || true
  chmod +x "$SKILLS_DIR/scripts/"*.py 2>/dev/null || true

  echo "  ✅ Skill files installed"

  # Slash commands (Claude only — Codex auto-loads via skill description)
  if [ -n "$COMMANDS_BASE" ]; then
    mkdir -p "$COMMANDS_BASE"
    cp commands/argus.md "$COMMANDS_BASE/argus.md"
    cp commands/argus-fix-verify.md "$COMMANDS_BASE/argus-fix-verify.md"
    cp commands/argus-doctor.md "$COMMANDS_BASE/argus-doctor.md"
    cp commands/argus-resume.md "$COMMANDS_BASE/argus-resume.md"
    echo "  ✅ Slash commands installed → /argus, /argus-fix-verify, /argus-doctor, /argus-resume"
  fi
}

# ─── Run installs based on target + availability ──────────────────────────────

INSTALLED_CLAUDE=0
INSTALLED_CODEX=0

if [ "$TARGET" = "claude" ] || [ "$TARGET" = "both" ]; then
  if [ "$CLAUDE_AVAILABLE" -eq 1 ]; then
    install_skill_to_dir "$CLAUDE_DIR/skills" "$CLAUDE_DIR/commands" "Claude Code"
    INSTALLED_CLAUDE=1
    echo ""
  elif [ "$TARGET" = "claude" ]; then
    echo "❌ Claude Code target requested but $CLAUDE_DIR not found."
    exit 1
  fi
fi

if [ "$TARGET" = "codex" ] || [ "$TARGET" = "both" ]; then
  if [ "$CODEX_AVAILABLE" -eq 1 ]; then
    install_skill_to_dir "$CODEX_DIR/skills" "" "Codex CLI"
    INSTALLED_CODEX=1
    echo ""
  elif [ "$TARGET" = "codex" ]; then
    echo "❌ Codex target requested but $CODEX_DIR not found."
    echo "   Install Codex CLI first (https://github.com/openai/codex)."
    exit 1
  fi
fi

if [ "$INSTALLED_CLAUDE" -eq 0 ] && [ "$INSTALLED_CODEX" -eq 0 ]; then
  echo "❌ No targets installed. Neither ~/.claude nor ~/.codex was found."
  echo "   Install Claude Code or Codex CLI first."
  exit 1
fi

# ─── Usage banner ─────────────────────────────────────────────────────────────

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Usage:"
echo ""
if [ "$INSTALLED_CLAUDE" -eq 1 ]; then
  echo "    Claude Code:"
  echo "      claude  →  /argus              ← full pipeline"
  echo "      claude  →  /argus-fix-verify   ← Stage 9 only"
  echo ""
fi
if [ "$INSTALLED_CODEX" -eq 1 ]; then
  echo "    Codex CLI:"
  echo "      codex   →  (auto-loads on \"audit this rust\" / \"run argus\" / \"find rust bugs\")"
  echo "      Restart Codex once after install to pick up the skill."
  echo "      See $CODEX_DIR/skills/$SKILL_NAME/references/codex-compat.md for"
  echo "      tool-translation notes (AskUserQuestion / TodoWrite / WebFetch equivalents)."
  echo ""
fi
echo "  Documentation:"
if [ "$INSTALLED_CLAUDE" -eq 1 ]; then
  echo "    $CLAUDE_DIR/skills/$SKILL_NAME/SKILL.md"
fi
if [ "$INSTALLED_CODEX" -eq 1 ]; then
  echo "    $CODEX_DIR/skills/$SKILL_NAME/SKILL.md"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
