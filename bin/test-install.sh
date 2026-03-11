#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# test-install.sh -- Verify installation integrity
#
# Checks that all required project files exist, are valid,
# and have correct permissions. Run after install or as CI check.
#
# Usage:
#   bash bin/test-install.sh
#
# Exit: 0 = all checks pass, 1 = one or more checks failed
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- ANSI colors (TTY-aware) ---
if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BOLD=''; DIM=''; RESET=''
fi

PASS=0
FAIL=0

ok()   { echo -e "${GREEN}  ok${RESET}  $1"; PASS=$((PASS + 1)); }
err()  { echo -e "${RED}  FAIL${RESET}  $1"; FAIL=$((FAIL + 1)); }
skip() { echo -e "${DIM}  skip${RESET}  $1"; }

check_file() {
  local label="$1" filepath="$2"
  if [ -f "$PROJECT_ROOT/$filepath" ]; then
    ok "$label ($filepath)"
  else
    err "$label ($filepath) -- not found"
  fi
}

check_executable() {
  local label="$1" filepath="$2"
  if [ -x "$PROJECT_ROOT/$filepath" ]; then
    ok "$label ($filepath) is executable"
  elif [ -f "$PROJECT_ROOT/$filepath" ]; then
    err "$label ($filepath) -- exists but not executable"
  else
    err "$label ($filepath) -- not found"
  fi
}

check_valid_json() {
  local label="$1" filepath="$2"
  if [ ! -f "$PROJECT_ROOT/$filepath" ]; then
    err "$label ($filepath) -- not found"
    return
  fi
  if node -e "JSON.parse(require('fs').readFileSync('$PROJECT_ROOT/$filepath','utf8'))" 2>/dev/null; then
    ok "$label ($filepath) is valid JSON"
  else
    err "$label ($filepath) -- invalid JSON"
  fi
}

check_node_syntax() {
  local label="$1" filepath="$2"
  if [ ! -f "$PROJECT_ROOT/$filepath" ]; then
    err "$label ($filepath) -- not found"
    return
  fi
  if node -c "$PROJECT_ROOT/$filepath" 2>/dev/null; then
    ok "$label ($filepath) has valid syntax"
  else
    err "$label ($filepath) -- syntax error"
  fi
}

check_bash_syntax() {
  local label="$1" filepath="$2"
  if [ ! -f "$PROJECT_ROOT/$filepath" ]; then
    err "$label ($filepath) -- not found"
    return
  fi
  if bash -n "$PROJECT_ROOT/$filepath" 2>/dev/null; then
    ok "$label ($filepath) has valid syntax"
  else
    err "$label ($filepath) -- syntax error"
  fi
}

check_file_contains() {
  local label="$1" filepath="$2" pattern="$3"
  if [ ! -f "$PROJECT_ROOT/$filepath" ]; then
    err "$label ($filepath) -- not found"
    return
  fi
  if grep -qE "$pattern" "$PROJECT_ROOT/$filepath" 2>/dev/null; then
    ok "$label ($filepath) contains '$pattern'"
  else
    err "$label ($filepath) -- missing expected pattern '$pattern'"
  fi
}

# ============================================================
echo -e "\n${BOLD}=== gsd-multi-model Installation Check ===${RESET}\n"
# ============================================================

# --- Core files ---
echo -e "${BOLD}Core:${RESET}"
check_file "CLI installer" "bin/cli.sh"
check_bash_syntax "CLI installer" "bin/cli.sh"
check_file "Project config" "CLAUDE.md"
check_file "Agent config" "AGENTS.md"
check_file "Package manifest" "package.json"

# --- Skills ---
echo -e "\n${BOLD}Skills:${RESET}"
for skill_dir in "$PROJECT_ROOT"/skills/*/; do
  skill_name=$(basename "$skill_dir")
  check_file "Skill: $skill_name" "skills/$skill_name/SKILL.md"
done

# --- Gate system ---
echo -e "\n${BOLD}Gate System:${RESET}"
check_executable "Gate orchestrator" "bin/gate-check.sh"
check_bash_syntax "Gate orchestrator" "bin/gate-check.sh"
check_executable "Architecture validator" "bin/validate-architecture.sh"
check_bash_syntax "Architecture validator" "bin/validate-architecture.sh"
check_valid_json "Architecture config" ".architecture.json"
check_node_syntax "Gate CLI wrapper" "bin/gsd-tools-gate.cjs"
check_file "Gate-check skill" "skills/gate-check/SKILL.md"
check_file_contains "Gate-check skill" "skills/gate-check/SKILL.md" "task_commit"

# --- Gate tests ---
echo -e "\n${BOLD}Gate Tests:${RESET}"
check_file "Gate integration tests" "bin/test-gate-check.sh"
check_bash_syntax "Gate integration tests" "bin/test-gate-check.sh"
check_file "Architecture unit tests" "bin/test-validate-architecture.sh"
check_bash_syntax "Architecture unit tests" "bin/test-validate-architecture.sh"

# --- Utility scripts ---
echo -e "\n${BOLD}Utility Scripts:${RESET}"
for script in bin/worktree-create.sh bin/worktree-cleanup.sh bin/worktree-list.sh bin/codex-task.sh bin/gsd-update.sh; do
  if [ -f "$PROJECT_ROOT/$script" ]; then
    check_bash_syntax "$(basename "$script")" "$script"
  fi
done

# ============================================================
echo ""
echo -e "${BOLD}Results: ${GREEN}$PASS passed${RESET}, ${FAIL:+${RED}}$FAIL failed${RESET}"
echo ""
# ============================================================

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
