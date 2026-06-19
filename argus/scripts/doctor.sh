#!/bin/bash
# argus doctor — install verification + readiness check (NEW v0.4.0)
#
# Reports the health of the Argus install:
#   - skill is wired into Claude Code (~/.claude/skills/argus) AND/OR Codex CLI (~/.codex/agents/argus)
#   - all required reference files are present
#   - all helper scripts are executable and parse-clean
#   - python3 + bash + grep + git are available
#   - Optional: Rust toolchain + cargo-* backends for infra mode (delegates to install-infra-deps.sh)
#
# Usage:
#   bash $SKILL_DIR/scripts/doctor.sh                       # smoke check (does not run install-infra-deps)
#   bash $SKILL_DIR/scripts/doctor.sh --check-rust          # also probe Rust toolchain readiness
#   bash $SKILL_DIR/scripts/doctor.sh --json                # machine-readable output
#
# Exit codes:
#   0 — all critical checks pass
#   1 — one or more critical checks failed (skill/scripts/references)
#   2 — invocation error (bad flag)

set -u

JSON=0
CHECK_RUST=0
for arg in "$@"; do
  case "$arg" in
    --json) JSON=1 ;;
    --check-rust) CHECK_RUST=1 ;;
    -h|--help)
      sed -n '1,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "ERROR: unknown flag: $arg" >&2; exit 2 ;;
  esac
done

# ─── Resolve SKILL_DIR ────────────────────────────────────────────────────────
# When invoked from the install directory itself.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SKILL_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"

PASS=()
FAIL=()
WARN=()

ok()   { PASS+=("$1"); }
err()  { FAIL+=("$1"); }
warn() { WARN+=("$1"); }

# ─── 1. Skill installation locations ──────────────────────────────────────────

INSTALL_CC="$HOME/.claude/skills/argus"
INSTALL_CODEX="$HOME/.codex/skills/argus"

if [ -d "$INSTALL_CC" ]; then
  ok "Claude Code skill: installed at $INSTALL_CC"
elif [ -L "$INSTALL_CC" ]; then
  ok "Claude Code skill: symlinked at $INSTALL_CC"
else
  warn "Claude Code skill: NOT installed at $INSTALL_CC (run install.sh)"
fi

if [ -d "$INSTALL_CODEX" ]; then
  ok "Codex CLI skill: installed at $INSTALL_CODEX"
else
  warn "Codex CLI skill: NOT installed at $INSTALL_CODEX (run install.sh --target codex)"
fi

if [ ${#PASS[@]} -eq 0 ]; then
  err "No install location detected; run install.sh first"
fi

# ─── 2. Required reference files ──────────────────────────────────────────────

REQUIRED_REFS=(
  "SKILL.md"
  "VERSION"
  "CHANGELOG.md"
  "references/pipeline-overview.md"
  "references/cost-estimation.md"
  "references/threat-model-first.md"
  "references/stage1-output-templates.md"
  "references/infra-impact-analysis.md"
  "references/infra-verification-stage.md"
  "references/audit-modes.md"
  "references/hacking-agents/shared-rules.md"
  "references/attack-vectors/rust-attack-vectors.md"
  "references/rust-protocol-types.md"
  "references/codex-compat.md"
  "references/scip-callgraph.md"
  "references/checkpoint-protocol.md"
  "references/skills/README.md"
  "references/skills/anchor-account-validation.md"
  "references/skills/anchor-cpi-safety.md"
  "references/skills/pda-seed-space.md"
  "references/skills/spl-token-2022-extensions.md"
  "references/skills/solana-sysvars-and-clock.md"
  "references/skills/rust-panics-in-bpf.md"
)

for r in "${REQUIRED_REFS[@]}"; do
  if [ -s "$SKILL_DIR/$r" ]; then
    ok "ref: $r"
  else
    err "ref: $r MISSING or empty"
  fi
done

# ─── 3. Helper scripts ────────────────────────────────────────────────────────

REQUIRED_SCRIPTS=(
  "scripts/enumerate.sh"
  "scripts/estimate-cost.py"
  "scripts/install-deps.sh"
  "scripts/install-infra-deps.sh"
  "scripts/reachability.py"
  "scripts/assign_severity.py"
  "scripts/scip_to_callgraph.py"
  "scripts/build-callgraph.sh"
  "scripts/codex_driver.py"
  "scripts/argus_resume.py"
)

for s in "${REQUIRED_SCRIPTS[@]}"; do
  if [ -f "$SKILL_DIR/$s" ]; then
    if [ -x "$SKILL_DIR/$s" ] || [[ "$s" == *.py ]]; then
      ok "script: $s present"
    else
      warn "script: $s present but not executable (chmod +x recommended)"
    fi
  else
    err "script: $s MISSING"
  fi
done

# ─── 4. Python scripts parse cleanly ──────────────────────────────────────────

for py in "$SKILL_DIR/scripts/estimate-cost.py" "$SKILL_DIR/scripts/reachability.py" "$SKILL_DIR/scripts/assign_severity.py" "$SKILL_DIR/scripts/scip_to_callgraph.py" "$SKILL_DIR/scripts/codex_driver.py" "$SKILL_DIR/scripts/argus_resume.py"; do
  if [ -f "$py" ]; then
    if python3 -c "import ast; ast.parse(open('$py').read())" 2>/dev/null; then
      ok "python: $(basename "$py") parses"
    else
      err "python: $(basename "$py") syntax error"
    fi
  fi
done

# ─── 5. Tooling ───────────────────────────────────────────────────────────────

for tool in python3 bash grep git find; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok "tool: $tool $(command -v "$tool")"
  else
    err "tool: $tool NOT FOUND"
  fi
done

# ─── 6. Optional Rust readiness (--check-rust) ────────────────────────────────

if [ $CHECK_RUST -eq 1 ]; then
  if command -v rustc >/dev/null 2>&1; then
    ok "rust: $(rustc --version)"
  else
    warn "rust: rustc not in PATH — infra-mode runs will need it"
  fi

  if command -v cargo >/dev/null 2>&1; then
    ok "rust: $(cargo --version)"
  else
    warn "rust: cargo not in PATH"
  fi

  # Probe infra deps via the dedicated script (dry-run mode)
  if [ -f "$SKILL_DIR/scripts/install-infra-deps.sh" ]; then
    INFRA_OUT=$(bash "$SKILL_DIR/scripts/install-infra-deps.sh" "$(pwd)" --dry-run 2>&1 || true)
    if echo "$INFRA_OUT" | grep -qi "MISSING"; then
      warn "infra deps: some backends missing (run install-infra-deps.sh --install when needed)"
    else
      ok "infra deps: all deterministic backends present"
    fi
  fi

  # SCIP indexer probe — enables [LSP-TRACE] evidence tag (v0.4.1)
  if command -v rust-analyzer >/dev/null 2>&1; then
    RA_VER=$(rust-analyzer --version 2>&1 | head -1)
    ok "scip indexer: rust-analyzer ($RA_VER) — [LSP-TRACE] evidence available"
  elif command -v scip-rust >/dev/null 2>&1; then
    ok "scip indexer: scip-rust — [LSP-TRACE] evidence available"
  else
    warn "scip indexer: NEITHER rust-analyzer NOR scip-rust found — reachability falls back to grep-only ([CODE-TRACE] only)"
    warn "  install: rustup component add rust-analyzer    (preferred)"
    warn "       or: cargo install scip-rust               (standalone)"
  fi
fi

# ─── 7. VERSION sanity ────────────────────────────────────────────────────────

if [ -f "$SKILL_DIR/VERSION" ]; then
  V=$(cat "$SKILL_DIR/VERSION" | tr -d '[:space:]')
  if [[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    ok "version: $V"
  else
    err "version: VERSION file content malformed ($V)"
  fi
fi

# ─── Report ───────────────────────────────────────────────────────────────────

if [ $JSON -eq 1 ]; then
  printf '{\n  "skill_dir": "%s",\n  "pass_count": %d,\n  "warn_count": %d,\n  "fail_count": %d,\n' \
    "$SKILL_DIR" "${#PASS[@]}" "${#WARN[@]}" "${#FAIL[@]}"
  printf '  "pass": ['
  for i in "${!PASS[@]}"; do
    [ $i -gt 0 ] && printf ', '
    printf '"%s"' "$(echo "${PASS[$i]}" | sed 's/"/\\"/g')"
  done
  printf '],\n'
  printf '  "warn": ['
  for i in "${!WARN[@]}"; do
    [ $i -gt 0 ] && printf ', '
    printf '"%s"' "$(echo "${WARN[$i]}" | sed 's/"/\\"/g')"
  done
  printf '],\n'
  printf '  "fail": ['
  for i in "${!FAIL[@]}"; do
    [ $i -gt 0 ] && printf ', '
    printf '"%s"' "$(echo "${FAIL[$i]}" | sed 's/"/\\"/g')"
  done
  printf ']\n}\n'
else
  echo "═══ argus doctor — skill dir: $SKILL_DIR ═══"
  echo ""
  echo "PASS (${#PASS[@]}):"
  for p in "${PASS[@]}"; do echo "  ✓ $p"; done
  echo ""
  if [ ${#WARN[@]} -gt 0 ]; then
    echo "WARN (${#WARN[@]}):"
    for w in "${WARN[@]}"; do echo "  ! $w"; done
    echo ""
  fi
  if [ ${#FAIL[@]} -gt 0 ]; then
    echo "FAIL (${#FAIL[@]}):"
    for f in "${FAIL[@]}"; do echo "  ✗ $f"; done
    echo ""
  fi
  echo "Summary: ${#PASS[@]} pass / ${#WARN[@]} warn / ${#FAIL[@]} fail"
fi

[ ${#FAIL[@]} -eq 0 ] && exit 0 || exit 1
