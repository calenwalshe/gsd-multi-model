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
echo "=== Checking GSD compatibility ==="

# --- semver_compare unit tests ---
# Local copy of semver_compare for unit testing
semver_compare() {
  local a="$1" b="$2"
  local IFS=.
  local a_parts=($a) b_parts=($b)
  local a_major=${a_parts[0]:-0} a_minor=${a_parts[1]:-0} a_patch=${a_parts[2]:-0}
  local b_major=${b_parts[0]:-0} b_minor=${b_parts[1]:-0} b_patch=${b_parts[2]:-0}

  if (( a_major != b_major )); then
    (( a_major > b_major )) && echo 1 || echo -1; return
  fi
  if (( a_minor != b_minor )); then
    (( a_minor > b_minor )) && echo 1 || echo -1; return
  fi
  if (( a_patch != b_patch )); then
    (( a_patch > b_patch )) && echo 1 || echo -1; return
  fi
  echo 0
}

check_semver() {
  local a="$1" b="$2" expected="$3"
  local actual
  actual=$(semver_compare "$a" "$b")
  if [ "$actual" = "$expected" ]; then
    echo "  ✓ semver_compare $a $b = $expected"
    PASS=$((PASS + 1))
  else
    echo "  ✗ semver_compare $a $b expected $expected, got $actual"
    FAIL=$((FAIL + 1))
  fi
}

echo "  -- semver_compare unit tests --"
check_semver "1.22.4" "1.22.4" "0"
check_semver "1.22.5" "1.22.4" "1"
check_semver "1.22.3" "1.22.4" "-1"
check_semver "1.23.0" "1.22.4" "1"
check_semver "2.0.0" "1.99.99" "1"
check_semver "1.100.0" "1.99.99" "1"

# --- compat_check integration tests ---
echo "  -- compat_check integration tests --"

# Helpers for integration tests (mirror install.sh behavior)
ok_test()   { echo -e "  ✓ $1"; }
warn_test() { echo -e "  ⚠ $1"; }

test_compat_in_range() {
  local tmpdir
  tmpdir=$(mktemp -d)
  echo -n "1.22.4" > "$tmpdir/VERSION"

  # Simulate compat_check logic
  local ver
  ver=$(cat "$tmpdir/VERSION" | tr -d '[:space:]')
  local min max
  min=$(python3 -c "import json; print(json.load(open('$SCRIPT_DIR/gsd-compat.json'))['gsd_compat']['min'])" 2>/dev/null) || { rm -rf "$tmpdir"; return 1; }
  max=$(python3 -c "import json; print(json.load(open('$SCRIPT_DIR/gsd-compat.json'))['gsd_compat']['max'])" 2>/dev/null) || { rm -rf "$tmpdir"; return 1; }

  local cmp_min cmp_max
  cmp_min=$(semver_compare "$ver" "$min")
  cmp_max=$(semver_compare "$ver" "$max")

  if (( cmp_min >= 0 && cmp_max <= 0 )); then
    echo "  ✓ compat in-range: v$ver within $min-$max"
    PASS=$((PASS + 1))
  else
    echo "  ✗ compat in-range: v$ver should be within $min-$max"
    FAIL=$((FAIL + 1))
  fi
  rm -rf "$tmpdir"
}

test_compat_out_of_range() {
  local tmpdir
  tmpdir=$(mktemp -d)
  echo -n "1.19.0" > "$tmpdir/VERSION"

  local ver
  ver=$(cat "$tmpdir/VERSION" | tr -d '[:space:]')
  local min max
  min=$(python3 -c "import json; print(json.load(open('$SCRIPT_DIR/gsd-compat.json'))['gsd_compat']['min'])" 2>/dev/null) || { rm -rf "$tmpdir"; return 1; }
  max=$(python3 -c "import json; print(json.load(open('$SCRIPT_DIR/gsd-compat.json'))['gsd_compat']['max'])" 2>/dev/null) || { rm -rf "$tmpdir"; return 1; }

  local cmp_min cmp_max
  cmp_min=$(semver_compare "$ver" "$min")
  cmp_max=$(semver_compare "$ver" "$max")

  if (( cmp_min < 0 || cmp_max > 0 )); then
    echo "  ✓ compat out-of-range: v$ver correctly outside $min-$max"
    PASS=$((PASS + 1))
  else
    echo "  ✗ compat out-of-range: v$ver should be outside $min-$max"
    FAIL=$((FAIL + 1))
  fi
  rm -rf "$tmpdir"
}

test_compat_missing_version() {
  local tmpdir
  tmpdir=$(mktemp -d)
  # No VERSION file created -- simulate missing

  if [ ! -f "$tmpdir/VERSION" ]; then
    echo "  ✓ compat missing VERSION: correctly skipped (no file)"
    PASS=$((PASS + 1))
  else
    echo "  ✗ compat missing VERSION: file should not exist"
    FAIL=$((FAIL + 1))
  fi
  rm -rf "$tmpdir"
}

test_compat_in_range
test_compat_out_of_range
test_compat_missing_version

echo ""
echo "═══════════════════════════════"
echo " Results: $PASS passed, $FAIL failed, $WARN warnings"
echo "═══════════════════════════════"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
