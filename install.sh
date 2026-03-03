#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# gsd-multi-model -- Installer
#
# Installs the multi-model GSD workflow:
#   - Claude Code skills (/init-gsd, /codex-review, /gsd-codex-verify)
#   - Global configs for Claude and Codex
#   - GSD framework across all runtimes
#
# Usage:
#   git clone <this-repo>
#   cd gsd-multi-model
#   bash install.sh
#   bash install.sh --force   # Overwrite existing configs
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- ANSI color helpers with TTY detection ---
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  BOLD=''
  RESET=''
fi

INSTALLED=0
SKIPPED=0
WARNINGS=0
ERRORS=0
SKIPPED_FILES=()

ok()   { echo -e "${GREEN}  ✓${RESET} $1"; }
warn() { echo -e "${YELLOW}  ⚠${RESET} $1"; WARNINGS=$((WARNINGS + 1)); }
err()  { echo -e "${RED}  ✗${RESET} $1"; ERRORS=$((ERRORS + 1)); }

# --- Parse --force flag ---
FORCE=false
for arg in "$@"; do [ "$arg" = "--force" ] && FORCE=true; done

# --- Banner ---
echo "═══════════════════════════════════════════════════════"
echo " gsd-multi-model -- Installer"
echo " Multi-model GSD + Claude Code + Codex workflow"
echo "═══════════════════════════════════════════════════════"
echo ""

# --- Pre-flight dependency check ---
preflight_check() {
  local missing_required=()

  case "$(uname -s)" in
    Darwin*) PLATFORM="macOS" ;;
    Linux*)  PLATFORM="Linux" ;;
    *)       PLATFORM="unknown" ;;
  esac

  echo "==> Pre-flight checks..."

  # Required deps (hard fail)
  if ! command -v git &>/dev/null; then
    if [ "$PLATFORM" = "macOS" ]; then
      missing_required+=("git -- install with: brew install git")
    elif [ "$PLATFORM" = "Linux" ]; then
      missing_required+=("git -- install with: apt install git")
    else
      missing_required+=("git -- install from: https://git-scm.com")
    fi
  else
    ok "git found"
  fi

  if ! command -v node &>/dev/null; then
    if [ "$PLATFORM" = "macOS" ]; then
      missing_required+=("node -- install with: brew install node")
    elif [ "$PLATFORM" = "Linux" ]; then
      missing_required+=("node -- install with: apt install nodejs")
    else
      missing_required+=("node -- install from: https://nodejs.org")
    fi
  else
    ok "node found"
  fi

  # Optional deps (warn only)
  if ! command -v claude &>/dev/null; then
    warn "claude not found. Install: https://docs.anthropic.com/en/docs/claude-code"
  else
    ok "claude found"
  fi

  if ! command -v codex &>/dev/null; then
    warn "codex not found. Install: npm install -g @openai/codex"
  else
    ok "codex found"
  fi

  # Report required failures
  if [ ${#missing_required[@]} -gt 0 ]; then
    echo ""
    err "Missing required dependencies:"
    for dep in "${missing_required[@]}"; do
      echo -e "    ${RED}${dep}${RESET}"
    done
    echo ""
    exit 1
  fi

  echo ""
}

preflight_check

# --------------------------------------------------
# 1. Install skills into ~/.claude/skills/ (personal = all projects)
# --------------------------------------------------
echo "==> Installing Claude Code skills..."

for skill_dir in "$SCRIPT_DIR/skills"/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name="$(basename "$skill_dir")"
  dest="$HOME/.claude/skills/$skill_name"

  if [ -d "$dest" ]; then
    rm -rf "$dest"
    mkdir -p "$dest"
    cp -r "$skill_dir"* "$dest/"
    ok "Updated: $skill_name"
  else
    mkdir -p "$dest"
    cp -r "$skill_dir"* "$dest/"
    ok "Installed: $skill_name"
  fi
  INSTALLED=$((INSTALLED + 1))
done

echo ""

# --------------------------------------------------
# 2. Install .claude/rules/ templates
# --------------------------------------------------
echo "==> Installing .claude/rules/ templates..."
mkdir -p "$HOME/.claude/rules"

for rule_file in "$SCRIPT_DIR/rules/"*.md; do
  [ -f "$rule_file" ] || continue
  rule_name="$(basename "$rule_file")"
  dest="$HOME/.claude/rules/$rule_name"

  if [ "$FORCE" = true ]; then
    cp "$rule_file" "$dest"
    ok "Installed (force): $rule_name"
    INSTALLED=$((INSTALLED + 1))
  elif [ -f "$dest" ]; then
    ok "$rule_name exists, skipping"
    SKIPPED=$((SKIPPED + 1))
    SKIPPED_FILES+=("$dest")
  else
    cp "$rule_file" "$dest"
    ok "Installed: $rule_name"
    INSTALLED=$((INSTALLED + 1))
  fi
done

echo ""

# --------------------------------------------------
# 3. Set up global Claude preferences
# --------------------------------------------------
echo "==> Setting up global Claude config..."

CLAUDE_GLOBAL="$HOME/.claude/CLAUDE.md"
if [ "$FORCE" = true ]; then
  cat > "$CLAUDE_GLOBAL" << 'GLOBAL_CLAUDE'
# Global Preferences

## Workflow
- I use GSD (Get Shit Done) for all non-trivial work
- Check for /gsd:status and .planning/ at session start
- After GSD verification, cross-validate with Codex via /codex-review
- Use /gsd-codex-verify for combined dual-tool verification

## Dual-Tool Execution
- Claude Code: complex multi-file changes, architecture, interactive work
- Codex: autonomous tasks, CRUD, tests, scripts, CLI tools, CI/CD
- Split tasks by complexity, run in parallel via git worktrees
- Each tool reviews the OTHER's output (cross-review)

## Coding Style
- Clean, readable code — no unnecessary abstractions
- Tests mandatory for new features
- Atomic commits per task
- No debug statements in production code

## Communication
- Be concise and direct
- Lead with actions, not explanations
- Flag blockers immediately
GLOBAL_CLAUDE
  ok "Installed (force): ~/.claude/CLAUDE.md"
  INSTALLED=$((INSTALLED + 1))
elif [ -f "$CLAUDE_GLOBAL" ]; then
  ok "~/.claude/CLAUDE.md exists, skipping"
  SKIPPED=$((SKIPPED + 1))
  SKIPPED_FILES+=("$CLAUDE_GLOBAL")
else
  cat > "$CLAUDE_GLOBAL" << 'GLOBAL_CLAUDE'
# Global Preferences

## Workflow
- I use GSD (Get Shit Done) for all non-trivial work
- Check for /gsd:status and .planning/ at session start
- After GSD verification, cross-validate with Codex via /codex-review
- Use /gsd-codex-verify for combined dual-tool verification

## Dual-Tool Execution
- Claude Code: complex multi-file changes, architecture, interactive work
- Codex: autonomous tasks, CRUD, tests, scripts, CLI tools, CI/CD
- Split tasks by complexity, run in parallel via git worktrees
- Each tool reviews the OTHER's output (cross-review)

## Coding Style
- Clean, readable code — no unnecessary abstractions
- Tests mandatory for new features
- Atomic commits per task
- No debug statements in production code

## Communication
- Be concise and direct
- Lead with actions, not explanations
- Flag blockers immediately
GLOBAL_CLAUDE
  ok "Installed: ~/.claude/CLAUDE.md"
  INSTALLED=$((INSTALLED + 1))
fi

# --------------------------------------------------
# 4. Set up global Codex config
# --------------------------------------------------
echo ""
echo "==> Setting up global Codex config..."

CODEX_DIR="$HOME/.codex"
mkdir -p "$CODEX_DIR"

# Codex AGENTS.md
CODEX_AGENTS="$CODEX_DIR/AGENTS.md"
if [ "$FORCE" = true ]; then
  cp "$SCRIPT_DIR/global/codex-agents.md" "$CODEX_AGENTS"
  ok "Installed (force): ~/.codex/AGENTS.md"
  INSTALLED=$((INSTALLED + 1))
elif [ -f "$CODEX_AGENTS" ]; then
  ok "~/.codex/AGENTS.md exists, skipping"
  SKIPPED=$((SKIPPED + 1))
  SKIPPED_FILES+=("$CODEX_AGENTS")
else
  cp "$SCRIPT_DIR/global/codex-agents.md" "$CODEX_AGENTS"
  ok "Installed: ~/.codex/AGENTS.md"
  INSTALLED=$((INSTALLED + 1))
fi

# Codex config.toml
CODEX_CONFIG="$CODEX_DIR/config.toml"
if [ "$FORCE" = true ]; then
  cp "$SCRIPT_DIR/global/codex-config.toml" "$CODEX_CONFIG"
  ok "Installed (force): ~/.codex/config.toml"
  INSTALLED=$((INSTALLED + 1))
elif [ -f "$CODEX_CONFIG" ]; then
  ok "~/.codex/config.toml exists, skipping"
  SKIPPED=$((SKIPPED + 1))
  SKIPPED_FILES+=("$CODEX_CONFIG")
else
  cp "$SCRIPT_DIR/global/codex-config.toml" "$CODEX_CONFIG"
  ok "Installed: ~/.codex/config.toml"
  INSTALLED=$((INSTALLED + 1))
fi

# --------------------------------------------------
# 5. Install GSD framework across all runtimes
# --------------------------------------------------
echo ""
echo "==> Installing GSD framework..."

GSD_INSTALLED=false
[ -d "$HOME/.claude/commands/gsd" ] && GSD_INSTALLED=true
[ -d "$HOME/.claude/get-shit-done" ] && GSD_INSTALLED=true

if [ "$GSD_INSTALLED" = true ]; then
  ok "GSD already installed for Claude Code"
  echo "    Checking other runtimes..."

  # Install for missing runtimes
  [ ! -d "$HOME/.codex/skills/gsd-new-project" ] && {
    echo "    Installing for Codex..."
    npx get-shit-done-cc@latest --codex --global 2>&1 | tail -5
  } || ok "Codex: already installed"

  [ ! -d "$HOME/.gemini/commands/gsd" ] && {
    echo "    Installing for Gemini..."
    npx get-shit-done-cc@latest --gemini --global 2>&1 | tail -5
  } || ok "Gemini: already installed"
else
  echo "    Installing GSD for all runtimes..."
  npx get-shit-done-cc@latest --all --global 2>&1 | tail -20
fi

# --------------------------------------------------
# 6. Create .gitignore
# --------------------------------------------------
echo ""
echo "==> Setting up .gitignore..."
GITIGNORE="$SCRIPT_DIR/.gitignore"
touch "$GITIGNORE"
for pattern in ".claude/settings.local.json" "node_modules/" ".env" ".env.*"; do
  if ! grep -qF "$pattern" "$GITIGNORE" 2>/dev/null; then
    echo "$pattern" >> "$GITIGNORE"
  fi
done
ok ".gitignore configured"

# --------------------------------------------------
# 6b. Verify installation integrity
# --------------------------------------------------
verify_integrity() {
  echo ""
  echo "==> Verifying installation integrity..."

  local integrity_ok=true

  is_skipped() {
    local target="$1"
    for sf in "${SKIPPED_FILES[@]}"; do
      [ "$sf" = "$target" ] && return 0
    done
    return 1
  }

  # Skills: compare each file in source skill dir against installed
  for skill_dir in "$SCRIPT_DIR/skills"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    dest_dir="$HOME/.claude/skills/$skill_name"

    if [ ! -d "$dest_dir" ]; then
      err "Missing skill directory: $dest_dir"
      integrity_ok=false
      continue
    fi

    # Compare files within skill
    while IFS= read -r -d '' src_file; do
      rel="${src_file#"$skill_dir"}"
      dest_file="$dest_dir/$rel"
      if [ ! -f "$dest_file" ]; then
        err "Missing: $dest_file (source: $src_file)"
        integrity_ok=false
      elif ! cmp -s "$src_file" "$dest_file"; then
        err "Mismatch: $dest_file differs from source $src_file"
        integrity_ok=false
      fi
    done < <(find "$skill_dir" -type f -print0)
  done

  # Rules: compare each rule file
  for rule_file in "$SCRIPT_DIR/rules/"*.md; do
    [ -f "$rule_file" ] || continue
    rule_name="$(basename "$rule_file")"
    dest="$HOME/.claude/rules/$rule_name"

    if [ ! -f "$dest" ]; then
      err "Missing rule: $dest"
      integrity_ok=false
    elif ! cmp -s "$rule_file" "$dest"; then
      if is_skipped "$dest"; then
        ok "$rule_name skipped (user-customized), integrity N/A"
      else
        err "Mismatch: $dest differs from source $rule_file"
        integrity_ok=false
      fi
    else
      ok "$rule_name verified"
    fi
  done

  # Codex AGENTS.md
  if [ -f "$HOME/.codex/AGENTS.md" ]; then
    if ! cmp -s "$SCRIPT_DIR/global/codex-agents.md" "$HOME/.codex/AGENTS.md"; then
      if is_skipped "$HOME/.codex/AGENTS.md"; then
        ok "AGENTS.md skipped (user-customized), integrity N/A"
      else
        err "Mismatch: ~/.codex/AGENTS.md differs from source"
        integrity_ok=false
      fi
    else
      ok "~/.codex/AGENTS.md verified"
    fi
  fi

  # Codex config.toml
  if [ -f "$HOME/.codex/config.toml" ]; then
    if ! cmp -s "$SCRIPT_DIR/global/codex-config.toml" "$HOME/.codex/config.toml"; then
      if is_skipped "$HOME/.codex/config.toml"; then
        ok "config.toml skipped (user-customized), integrity N/A"
      else
        err "Mismatch: ~/.codex/config.toml differs from source"
        integrity_ok=false
      fi
    else
      ok "~/.codex/config.toml verified"
    fi
  fi

  if [ "$integrity_ok" = true ]; then
    ok "All files passed integrity check"
  fi
}

verify_integrity

# --------------------------------------------------
# 7. Summary
# --------------------------------------------------
echo ""
echo "═══════════════════════════════════════════════════════"
echo " INSTALLATION COMPLETE"
echo "═══════════════════════════════════════════════════════"
echo ""
echo " Skills installed (available in ALL projects):"
echo "   /init-gsd          -- Bootstrap any new project"
echo "   /codex-review      -- Cross-model review with Codex"
echo "   /gsd-codex-verify  -- Combined dual-tool verification"
echo ""
echo " GSD installed for:"
echo "   Claude Code  -- /gsd:new-project"
echo "   Codex CLI    -- \$gsd-new-project"
echo "   Gemini CLI   -- /gsd:new-project"
echo ""
echo " Global configs:"
echo "   ~/.claude/CLAUDE.md     -- GSD dual-tool workflow"
echo "   ~/.codex/AGENTS.md      -- Autonomous coder + cross-reviewer"
echo "   ~/.codex/config.toml    -- Codex CLI settings"
echo ""
echo " HOW TO USE (any new project):"
echo "   1. mkdir my-project && cd my-project"
echo "   2. claude"
echo "   3. /init-gsd              <- bootstraps everything"
echo "   4. /gsd:new-project       <- start planning"
echo ""
echo " The workflow:"
echo "   discuss -> plan -> execute (Claude + Codex parallel)"
echo "   -> /gsd-codex-verify (cross-review) -> advance"
echo -e " Status: ${BOLD}$INSTALLED installed${RESET}, $SKIPPED skipped, ${YELLOW}$WARNINGS warnings${RESET}, ${RED}$ERRORS errors${RESET}"
echo "═══════════════════════════════════════════════════════"

if [ "$ERRORS" -gt 0 ]; then
  echo -e "${RED} Some files failed integrity checks. Re-run with --force to reinstall.${RESET}"
  exit 1
fi
