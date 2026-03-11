#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# gsd-multi-model CLI
#
# Add-on layer for GSD. Installs multi-model skills on top of
# an existing GSD installation. Does NOT duplicate GSD itself.
#
# Usage:
#   npx gsd-multi-model           # Install skills only (safe default)
#   npx gsd-multi-model --all     # Skills + codex config + rules
#   npx gsd-multi-model --force   # Overwrite existing files
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- ANSI colors (TTY-aware) ---
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BOLD=''; DIM=''; RESET=''
fi

INSTALLED=0
SKIPPED=0

# --- Semver comparison (no external deps) ---
version_gte() {
  local IFS=.
  local i ver1=($1) ver2=($2)
  for ((i=0; i<${#ver2[@]}; i++)); do
    if ((${ver1[i]:-0} < ${ver2[i]:-0})); then return 1; fi
    if ((${ver1[i]:-0} > ${ver2[i]:-0})); then return 0; fi
  done
  return 0
}

# --- GSD base skill names (anti-duplication guard) ---
GSD_BASE_SKILLS=(
  "gsd-drive" "plan-phase" "execute-plan" "verify-work"
  "discuss-phase" "new-project" "status" "ideate"
)

ok()   { echo -e "${GREEN}  ✓${RESET} $1"; }
skip() { echo -e "${DIM}  · $1${RESET}"; SKIPPED=$((SKIPPED + 1)); }
warn() { echo -e "${YELLOW}  ⚠${RESET} $1"; }
err()  { echo -e "${RED}  ✗${RESET} $1"; }

# --- Parse flags ---
FORCE=false
WITH_CODEX=false
WITH_RULES=false
WITH_GLOBALS=false
SHOW_HELP=false

for arg in "$@"; do
  case "$arg" in
    --force)       FORCE=true ;;
    --with-codex)  WITH_CODEX=true ;;
    --with-rules)  WITH_RULES=true ;;
    --with-globals) WITH_GLOBALS=true ;;
    --all)         WITH_CODEX=true; WITH_RULES=true; WITH_GLOBALS=true ;;
    --help|-h)     SHOW_HELP=true ;;
    *)             warn "Unknown flag: $arg" ;;
  esac
done

if [ "$SHOW_HELP" = true ]; then
  echo "gsd-multi-model — Multi-model add-on for GSD"
  echo ""
  echo "Usage: npx gsd-multi-model [flags]"
  echo ""
  echo "Flags:"
  echo "  (none)          Install skills only (safe default)"
  echo "  --with-codex    Also install ~/.codex/ config"
  echo "  --with-rules    Also install ~/.claude/rules/ templates"
  echo "  --with-globals  Also append GSD section to ~/.claude/CLAUDE.md"
  echo "  --all           All of the above"
  echo "  --force         Overwrite existing files"
  echo "  --help          Show this help"
  echo ""
  echo "Prerequisites: GSD must be installed first:"
  echo "  npx get-shit-done-cc@latest --all --global"
  exit 0
fi

# --- Banner ---
echo ""
echo "═══════════════════════════════════════════════════════"
echo " gsd-multi-model — Multi-model add-on for GSD"
echo "═══════════════════════════════════════════════════════"
echo ""

# --------------------------------------------------
# 1. Check GSD prerequisite (warn, don't install)
# --------------------------------------------------
echo "==> Checking prerequisites..."

GSD_FOUND=false
if [ -d "$HOME/.claude/commands/gsd" ] || [ -d "$HOME/.claude/get-shit-done" ]; then
  GSD_FOUND=true
fi

if [ "$GSD_FOUND" = true ]; then
  # Check version compatibility
  VERSION_FILE="$HOME/.claude/get-shit-done/VERSION"
  if [ -f "$VERSION_FILE" ]; then
    GSD_VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')
    ok "GSD v${GSD_VERSION} found"
  else
    ok "GSD found (version unknown)"
  fi

  # Version compatibility check against gsd-compat.json
  COMPAT_FILE="$SCRIPT_DIR/gsd-compat.json"
  if [ -n "${GSD_VERSION:-}" ] && [ -f "$COMPAT_FILE" ]; then
    MIN_VER=$(grep -o '"min": *"[^"]*"' "$COMPAT_FILE" | cut -d'"' -f4)
    MAX_VER=$(grep -o '"max": *"[^"]*"' "$COMPAT_FILE" | cut -d'"' -f4)
    if [ -n "$MIN_VER" ] && ! version_gte "$GSD_VERSION" "$MIN_VER"; then
      warn "GSD v${GSD_VERSION} is below minimum v${MIN_VER} -- some features may not work"
    fi
    if [ -n "$MAX_VER" ] && ! version_gte "$MAX_VER" "$GSD_VERSION"; then
      warn "GSD v${GSD_VERSION} is above tested range (max v${MAX_VER}) -- proceed with caution"
    fi
  fi
else
  warn "GSD not detected. Install it first:"
  echo -e "    ${BOLD}npx get-shit-done-cc@latest --all --global${RESET}"
  echo ""
  echo "  Skills will still be installed, but /gsd:* commands"
  echo "  won't work until GSD is present."
  echo ""
fi

# Check claude CLI
if command -v claude &>/dev/null; then
  ok "Claude Code CLI found"
else
  warn "Claude Code CLI not found (skills will install but won't activate without it)"
fi

echo ""

# --------------------------------------------------
# 2. Install skills (always — this is the core)
# --------------------------------------------------
echo "==> Installing skills..."

for skill_dir in "$SCRIPT_DIR/skills"/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name="$(basename "$skill_dir")"
  dest="$HOME/.claude/skills/$skill_name"

  # Anti-duplication guard: skip GSD base skills
  is_base_skill=false
  for base_skill in "${GSD_BASE_SKILLS[@]}"; do
    if [ "$skill_name" = "$base_skill" ]; then
      is_base_skill=true
      break
    fi
  done
  if [ "$is_base_skill" = true ]; then
    warn "Skipping $skill_name -- belongs to GSD base"
    continue
  fi

  if [ -d "$dest" ] && [ "$FORCE" != true ]; then
    # Check if source is newer or different
    if ! diff -rq "$skill_dir" "$dest" &>/dev/null 2>&1; then
      rm -rf "$dest"
      mkdir -p "$dest"
      cp -r "$skill_dir"* "$dest/"
      ok "Updated: /$skill_name"
      INSTALLED=$((INSTALLED + 1))
    else
      skip "/$skill_name (up to date)"
    fi
  else
    rm -rf "$dest" 2>/dev/null || true
    mkdir -p "$dest"
    cp -r "$skill_dir"* "$dest/"
    ok "Installed: /$skill_name"
    INSTALLED=$((INSTALLED + 1))
  fi
done

echo ""

# --------------------------------------------------
# 3. Codex config (opt-in via --with-codex or --all)
# --------------------------------------------------
if [ "$WITH_CODEX" = true ]; then
  echo "==> Installing Codex config..."
  mkdir -p "$HOME/.codex"

  # AGENTS.md
  CODEX_AGENTS="$HOME/.codex/AGENTS.md"
  if [ -f "$CODEX_AGENTS" ] && [ "$FORCE" != true ]; then
    skip "~/.codex/AGENTS.md (exists, use --force to overwrite)"
  else
    cp "$SCRIPT_DIR/global/codex-agents.md" "$CODEX_AGENTS"
    ok "Installed: ~/.codex/AGENTS.md"
    INSTALLED=$((INSTALLED + 1))
  fi

  # config.toml
  CODEX_CONFIG="$HOME/.codex/config.toml"
  if [ -f "$CODEX_CONFIG" ] && [ "$FORCE" != true ]; then
    skip "~/.codex/config.toml (exists, use --force to overwrite)"
  else
    cp "$SCRIPT_DIR/global/codex-config.toml" "$CODEX_CONFIG"
    ok "Installed: ~/.codex/config.toml"
    INSTALLED=$((INSTALLED + 1))
  fi

  echo ""
fi

# --------------------------------------------------
# 4. Rules (opt-in via --with-rules or --all)
# --------------------------------------------------
if [ "$WITH_RULES" = true ]; then
  echo "==> Installing rules..."
  mkdir -p "$HOME/.claude/rules"

  for rule_file in "$SCRIPT_DIR/rules/"*.md; do
    [ -f "$rule_file" ] || continue
    rule_name="$(basename "$rule_file")"
    dest="$HOME/.claude/rules/$rule_name"

    if [ -f "$dest" ] && [ "$FORCE" != true ]; then
      skip "$rule_name (exists, use --force to overwrite)"
    else
      cp "$rule_file" "$dest"
      ok "Installed: $rule_name"
      INSTALLED=$((INSTALLED + 1))
    fi
  done

  echo ""
fi

# --------------------------------------------------
# 5. Global CLAUDE.md (opt-in via --with-globals or --all)
# --------------------------------------------------
if [ "$WITH_GLOBALS" = true ]; then
  echo "==> Updating global Claude config..."
  mkdir -p "$HOME/.claude"

  CLAUDE_GLOBAL="$HOME/.claude/CLAUDE.md"
  if [ -f "$CLAUDE_GLOBAL" ]; then
    if grep -q "GSD Workflow" "$CLAUDE_GLOBAL" 2>/dev/null; then
      skip "~/.claude/CLAUDE.md (GSD section already present)"
    else
      # Append, don't overwrite
      cat >> "$CLAUDE_GLOBAL" << 'APPEND'

## GSD Workflow

- I use GSD for all non-trivial work
- Check for /gsd:status and .planning/ at session start
- After GSD verification, cross-validate with Codex
APPEND
      ok "Updated: ~/.claude/CLAUDE.md (appended GSD section)"
      INSTALLED=$((INSTALLED + 1))
    fi
  else
    cat > "$CLAUDE_GLOBAL" << 'CREATE'
# Global Preferences

## GSD Workflow

- I use GSD for all non-trivial work
- Check for /gsd:status and .planning/ at session start
- After GSD verification, cross-validate with Codex
CREATE
    ok "Created: ~/.claude/CLAUDE.md"
    INSTALLED=$((INSTALLED + 1))
  fi

  echo ""
fi

# --------------------------------------------------
# Summary
# --------------------------------------------------
echo "═══════════════════════════════════════════════════════"
echo " DONE"
echo "═══════════════════════════════════════════════════════"
echo ""
echo " Skills installed (available in ALL projects):"
for skill_dir in "$SCRIPT_DIR/skills"/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name="$(basename "$skill_dir")"
  echo "   /$skill_name"
done
echo ""

if [ "$WITH_CODEX" != true ] || [ "$WITH_RULES" != true ] || [ "$WITH_GLOBALS" != true ]; then
  echo " Optional layers (not installed):"
  [ "$WITH_CODEX" != true ]   && echo "   --with-codex    Codex CLI config (~/.codex/)"
  [ "$WITH_RULES" != true ]   && echo "   --with-rules    Claude rules (~/.claude/rules/)"
  [ "$WITH_GLOBALS" != true ] && echo "   --with-globals  Global CLAUDE.md update"
  echo "   --all           All of the above"
  echo ""
fi

if [ "$GSD_FOUND" != true ]; then
  echo -e " ${YELLOW}⚠ GSD not installed. Run this first:${RESET}"
  echo "   npx get-shit-done-cc@latest --all --global"
  echo ""
fi

echo " How to use (any project):"
echo "   1. cd my-project"
echo "   2. claude"
echo "   3. /init-gsd              <- bootstraps project files"
echo "   4. /gsd:new-project       <- start planning"
echo ""
echo -e " ${BOLD}$INSTALLED installed${RESET}, $SKIPPED unchanged"
echo "═══════════════════════════════════════════════════════"
