#!/usr/bin/env bash
set -euo pipefail

# Verify gsd-multi-model installation integrity

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0
FAIL=0
WARN=0

check() {
  if [ -e "$1" ]; then
    echo "  ✓ $1"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $1 MISSING"
    FAIL=$((FAIL + 1))
  fi
}

check_integrity() {
  local src="$1"
  local dest="$2"
  local mode="$3"  # "strict" or "template"

  if [ ! -e "$dest" ]; then
    echo "  ✗ $dest MISSING"
    FAIL=$((FAIL + 1))
    return
  fi

  if cmp -s "$src" "$dest"; then
    echo "  ✓ $dest matches source"
    PASS=$((PASS + 1))
  elif [ "$mode" = "strict" ]; then
    echo "  ✗ $dest DIFFERS from source (re-run install.sh)"
    FAIL=$((FAIL + 1))
  else
    echo "  ⚠ $dest differs from template (user-customized?)"
    WARN=$((WARN + 1))
  fi
}

echo "=== Checking Claude Code skills ==="
check "$HOME/.claude/skills/init-gsd/SKILL.md"
check "$HOME/.claude/skills/codex-review/SKILL.md"
check "$HOME/.claude/skills/gsd-codex-verify/SKILL.md"

echo ""
echo "=== Checking GSD installation ==="
check "$HOME/.claude/commands/gsd/new-project.md"
check "$HOME/.claude/commands/gsd/execute-phase.md"
check "$HOME/.claude/commands/gsd/verify-work.md"
check "$HOME/.codex/skills/gsd-new-project"
check "$HOME/.gemini/commands/gsd/new-project.toml"

echo ""
echo "=== Checking global configs ==="
check "$HOME/.claude/CLAUDE.md"
check "$HOME/.codex/AGENTS.md"
check "$HOME/.codex/config.toml"

echo ""
echo "=== Checking GSD agents ==="
check "$HOME/.claude/agents/gsd-planner.md"
check "$HOME/.claude/agents/gsd-executor.md"
check "$HOME/.claude/agents/gsd-verifier.md"
check "$HOME/.codex/agents/gsd-planner.md"
check "$HOME/.codex/agents/gsd-executor.md"

echo ""
echo "=== Checking skill integrity ==="
for skill_dir in "$SCRIPT_DIR/skills"/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name="$(basename "$skill_dir")"
  while IFS= read -r -d '' src_file; do
    rel="${src_file#"$skill_dir"}"
    dest="$HOME/.claude/skills/$skill_name/$rel"
    check_integrity "$src_file" "$dest" "strict"
  done < <(find "$skill_dir" -type f -print0)
done

echo ""
echo "=== Checking rules integrity ==="
for rule_file in "$SCRIPT_DIR/rules/"*.md; do
  [ -f "$rule_file" ] || continue
  rule_name="$(basename "$rule_file")"
  check_integrity "$rule_file" "$HOME/.claude/rules/$rule_name" "template"
done

echo ""
echo "=== Checking config integrity ==="
check_integrity "$SCRIPT_DIR/global/codex-agents.md" "$HOME/.codex/AGENTS.md" "template"
check_integrity "$SCRIPT_DIR/global/codex-config.toml" "$HOME/.codex/config.toml" "template"

echo ""
echo "═══════════════════════════════"
echo " Results: $PASS passed, $FAIL failed, $WARN warnings"
echo "═══════════════════════════════"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
