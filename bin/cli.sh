#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# gsd-multi-model CLI
#
# Add-on layer for GSD. Installs gsd-multi:* commands on top of
# an existing GSD installation. Does NOT duplicate GSD itself.
#
# Usage:
#   npx gsd-multi-model           # Install commands only (safe default)
#   npx gsd-multi-model --all     # Commands + codex config + rules
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

ok()   { echo -e "${GREEN}  ✓${RESET} $1"; }
skip() { echo -e "${DIM}  · $1${RESET}"; SKIPPED=$((SKIPPED + 1)); }
warn() { echo -e "${YELLOW}  ⚠${RESET} $1"; }
err()  { echo -e "${RED}  ✗${RESET} $1"; }

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
  echo "gsd-multi-model -- Multi-model add-on for GSD"
  echo ""
  echo "Usage: npx gsd-multi-model [flags]"
  echo ""
  echo "Flags:"
  echo "  (none)          Install gsd-multi:* commands (safe default)"
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
echo " gsd-multi-model -- Multi-model add-on for GSD"
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
  VERSION_FILE="$HOME/.claude/get-shit-done/VERSION"
  if [ -f "$VERSION_FILE" ]; then
    GSD_VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')
    ok "GSD v${GSD_VERSION} found"
  else
    ok "GSD found (version unknown)"
  fi

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
  echo "  Commands will still be installed, but /gsd:* commands"
  echo "  won't work until GSD is present."
  echo ""
fi

if command -v claude &>/dev/null; then
  ok "Claude Code CLI found"
else
  warn "Claude Code CLI not found (commands will install but won't activate without it)"
fi

echo ""

# --------------------------------------------------
# 2. Install commands into ~/.claude/commands/gsd-multi/
# --------------------------------------------------
echo "==> Installing gsd-multi:* commands..."

COMMANDS_SRC="$SCRIPT_DIR/commands/gsd-multi"
COMMANDS_DEST="$HOME/.claude/commands/gsd-multi"

if [ -d "$COMMANDS_SRC" ]; then
  mkdir -p "$COMMANDS_DEST"

  for cmd_file in "$COMMANDS_SRC"/*.md; do
    [ -f "$cmd_file" ] || continue
    cmd_name="$(basename "$cmd_file" .md)"
    dest="$COMMANDS_DEST/$(basename "$cmd_file")"

    if [ -f "$dest" ] && [ "$FORCE" != true ]; then
      if ! cmp -s "$cmd_file" "$dest"; then
        cp "$cmd_file" "$dest"
        ok "Updated: /gsd-multi:$cmd_name"
        INSTALLED=$((INSTALLED + 1))
      else
        skip "/gsd-multi:$cmd_name (up to date)"
      fi
    else
      cp "$cmd_file" "$dest"
      ok "Installed: /gsd-multi:$cmd_name"
      INSTALLED=$((INSTALLED + 1))
    fi
  done
else
  err "commands/gsd-multi/ not found in package"
fi

echo ""

# --------------------------------------------------
# 3. Clean up legacy skills/ installs
# --------------------------------------------------
LEGACY_SKILLS=(codex-review gate-check gsd-codex-verify gsd-debug gsd-drive ideate init-gsd install-skill observe)
CLEANED=0

for skill_name in "${LEGACY_SKILLS[@]}"; do
  legacy_dir="$HOME/.claude/skills/$skill_name"
  if [ -d "$legacy_dir" ]; then
    rm -rf "$legacy_dir"
    ok "Removed legacy: /$skill_name (now /gsd-multi:*)"
    CLEANED=$((CLEANED + 1))
  fi
done

if [ "$CLEANED" -gt 0 ]; then
  echo ""
fi

# --------------------------------------------------
# 4. Codex config (opt-in via --with-codex or --all)
# --------------------------------------------------
if [ "$WITH_CODEX" = true ]; then
  echo "==> Installing Codex config..."
  mkdir -p "$HOME/.codex"

  CODEX_AGENTS="$HOME/.codex/AGENTS.md"
  if [ -f "$CODEX_AGENTS" ] && [ "$FORCE" != true ]; then
    skip "~/.codex/AGENTS.md (exists, use --force to overwrite)"
  else
    cp "$SCRIPT_DIR/global/codex-agents.md" "$CODEX_AGENTS"
    ok "Installed: ~/.codex/AGENTS.md"
    INSTALLED=$((INSTALLED + 1))
  fi

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
# 5. Rules (opt-in via --with-rules or --all)
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
# 6. Global CLAUDE.md (opt-in via --with-globals or --all)
# --------------------------------------------------
if [ "$WITH_GLOBALS" = true ]; then
  echo "==> Updating global Claude config..."
  mkdir -p "$HOME/.claude"

  CLAUDE_GLOBAL="$HOME/.claude/CLAUDE.md"
  if [ -f "$CLAUDE_GLOBAL" ]; then
    if grep -q "GSD Workflow" "$CLAUDE_GLOBAL" 2>/dev/null; then
      skip "~/.claude/CLAUDE.md (GSD section already present)"
    else
      cat >> "$CLAUDE_GLOBAL" << 'APPEND'

## GSD Workflow

- I use GSD for all non-trivial work
- Check for /gsd:status and .planning/ at session start
- After GSD verification, cross-validate with Codex via /gsd-multi:codex-review
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
- After GSD verification, cross-validate with Codex via /gsd-multi:codex-review
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
echo " Commands installed (available in ALL projects):"
echo "   /gsd-multi:init          -- Bootstrap any new project"
echo "   /gsd-multi:drive         -- Auto-drive full GSD workflow"
echo "   /gsd-multi:codex-review  -- Cross-model review with Codex"
echo "   /gsd-multi:codex-verify  -- Combined dual-tool verification"
echo "   /gsd-multi:gate-check    -- Pre-commit quality gates"
echo "   /gsd-multi:debug         -- Live telemetry debugging"
echo "   /gsd-multi:ideate        -- Structured brainstorming"
echo "   /gsd-multi:observe       -- Executor telemetry protocol"
echo "   /gsd-multi:install-skill -- Install skills from GitHub"
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
echo "   3. /gsd-multi:init         <- bootstraps project files"
echo "   4. /gsd:new-project        <- start planning"
echo "   5. /gsd-multi:drive        <- auto-pilot everything"
echo ""
echo -e " ${BOLD}$INSTALLED installed${RESET}, $SKIPPED unchanged"
echo "═══════════════════════════════════════════════════════"
