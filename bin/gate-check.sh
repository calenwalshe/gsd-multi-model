#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# gate-check.sh -- Deterministic gate orchestrator
#
# Runs all enabled quality checks on staged files and produces
# structured output. Blocks commits when gates fail.
#
# Usage:
#   bin/gate-check.sh                         # check staged files
#   bin/gate-check.sh --plan-path <path>      # also run structural tests
#   bin/gate-check.sh --files "a.sh b.js"     # explicit file list (testing)
#
# Output:
#   stdout: JSON result {"passed": bool, "duration_ms": N, "gates": [...]}
#   stderr: Human-readable summary with actionable error messages
#   exit 0: all gates pass (or all skipped)
#   exit 1: one or more gates failed
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- ANSI color helpers (stderr is the human channel) ---
if [ -t 2 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BOLD=''; DIM=''; RESET=''
fi

ok()   { echo -e "${GREEN}  PASS${RESET} $1" >&2; }
warn() { echo -e "${YELLOW}  WARN${RESET} $1" >&2; }
err()  { echo -e "${RED}  FAIL${RESET} $1" >&2; }
skip() { echo -e "${DIM}  SKIP${RESET} $1" >&2; }

# --- Parse arguments ---
PLAN_PATH=""
EXPLICIT_FILES=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan-path)  PLAN_PATH="$2"; shift 2 ;;
    --files)      EXPLICIT_FILES="$2"; shift 2 ;;
    *)            shift ;;
  esac
done

# --- Load config ---
CONFIG_FILE="$PROJECT_ROOT/.planning/config.json"
GATES_ENABLED="true"
LINT_ENABLED="true"
LINT_COMMAND=""
LINT_AUTO_DETECT="true"
ARCH_ENABLED="true"
ARCH_CONFIG_PATH=".architecture.json"
STRUCTURAL_ENABLED="true"
TIMEOUT_SECONDS=10
ON_TIMEOUT="warn"

if [ -f "$CONFIG_FILE" ]; then
  # Read gates config using node (reliable JSON parsing)
  GATES_JSON=$(node -e "
    const c = JSON.parse(require('fs').readFileSync('$CONFIG_FILE','utf8'));
    const g = c.gates || {};
    console.log(JSON.stringify({
      enabled: g.enabled !== undefined ? g.enabled : true,
      lint_enabled: g.lint ? (g.lint.enabled !== undefined ? g.lint.enabled : true) : true,
      lint_command: g.lint ? (g.lint.command || '') : '',
      lint_auto_detect: g.lint ? (g.lint.auto_detect !== undefined ? g.lint.auto_detect : true) : true,
      arch_enabled: g.architecture ? (g.architecture.enabled !== undefined ? g.architecture.enabled : true) : true,
      arch_config_path: g.architecture ? (g.architecture.config_path || '.architecture.json') : '.architecture.json',
      structural_enabled: g.structural ? (g.structural.enabled !== undefined ? g.structural.enabled : true) : true,
      timeout_seconds: g.timeout_seconds || 10,
      on_timeout: g.on_timeout || 'warn'
    }));
  " 2>/dev/null || echo '{}')

  if [ "$GATES_JSON" != '{}' ]; then
    GATES_ENABLED=$(echo "$GATES_JSON" | node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).enabled))")
    LINT_ENABLED=$(echo "$GATES_JSON" | node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).lint_enabled))")
    LINT_COMMAND=$(echo "$GATES_JSON" | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).lint_command)")
    LINT_AUTO_DETECT=$(echo "$GATES_JSON" | node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).lint_auto_detect))")
    ARCH_ENABLED=$(echo "$GATES_JSON" | node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).arch_enabled))")
    ARCH_CONFIG_PATH=$(echo "$GATES_JSON" | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).arch_config_path)")
    STRUCTURAL_ENABLED=$(echo "$GATES_JSON" | node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).structural_enabled))")
    TIMEOUT_SECONDS=$(echo "$GATES_JSON" | node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).timeout_seconds))")
    ON_TIMEOUT=$(echo "$GATES_JSON" | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).on_timeout)")
  fi
fi

# --- If gates disabled globally, exit immediately ---
if [ "$GATES_ENABLED" = "false" ]; then
  echo '{"passed":true,"gates":[],"skipped":true}'
  exit 0
fi

# --- Collect staged files ---
if [ -n "$EXPLICIT_FILES" ]; then
  STAGED_FILES="$EXPLICIT_FILES"
else
  STAGED_FILES=$(git diff --cached --name-only 2>/dev/null || echo "")
fi

# Filter out .planning/ files -- gates only run on source files
FILTERED_FILES=""
for f in $STAGED_FILES; do
  case "$f" in
    .planning/*) continue ;;
    *)           FILTERED_FILES="$FILTERED_FILES $f" ;;
  esac
done
FILTERED_FILES=$(echo "$FILTERED_FILES" | xargs)

# --- Track timing ---
START_MS=$(date +%s%3N 2>/dev/null || echo "0")

# --- Gate results accumulator ---
OVERALL_PASSED="true"
GATES_RESULTS="[]"

# Helper: append a gate result to the JSON array
append_gate() {
  local name="$1" passed="$2" files_checked="$3" message="$4" violations="$5"
  GATES_RESULTS=$(node -e "
    const gates = JSON.parse(process.argv[1]);
    const entry = {name: process.argv[2], passed: process.argv[3] === 'true', files_checked: parseInt(process.argv[4]), message: process.argv[5]};
    const v = process.argv[6];
    if (v && v !== '[]') entry.violations = JSON.parse(v);
    gates.push(entry);
    console.log(JSON.stringify(gates));
  " "$GATES_RESULTS" "$name" "$passed" "$files_checked" "$message" "$violations")
}

# ============================================================
# GATE 1: Lint
# ============================================================
run_lint_gate() {
  local lint_cmd="$LINT_COMMAND"
  local file_count=0
  local lint_files=""

  # Filter to lintable files only
  for f in $FILTERED_FILES; do
    case "$f" in
      *.js|*.ts|*.cjs|*.mjs|*.jsx|*.tsx|*.py|*.sh|*.bash) lint_files="$lint_files $f"; file_count=$((file_count + 1)) ;;
    esac
  done
  lint_files=$(echo "$lint_files" | xargs)

  if [ "$LINT_ENABLED" = "false" ]; then
    skip "Lint (disabled)"
    append_gate "lint" "true" "0" "Lint gate disabled" "[]"
    return
  fi

  if [ -z "$lint_files" ]; then
    skip "Lint (no lintable staged files)"
    append_gate "lint" "true" "0" "No lintable files staged" "[]"
    return
  fi

  # Auto-detect linter if no command configured
  if [ -z "$lint_cmd" ] && [ "$LINT_AUTO_DETECT" = "true" ]; then
    if [ -f "$PROJECT_ROOT/.eslintrc" ] || [ -f "$PROJECT_ROOT/.eslintrc.js" ] || [ -f "$PROJECT_ROOT/.eslintrc.json" ] || [ -f "$PROJECT_ROOT/.eslintrc.yml" ] || [ -f "$PROJECT_ROOT/eslint.config.js" ] || [ -f "$PROJECT_ROOT/eslint.config.mjs" ]; then
      lint_cmd="npx eslint --no-warn-ignored {files}"
    elif [ -f "$PROJECT_ROOT/pyproject.toml" ] && grep -q '\[tool.ruff\]' "$PROJECT_ROOT/pyproject.toml" 2>/dev/null; then
      lint_cmd="ruff check {files}"
    elif [ -f "$PROJECT_ROOT/Makefile" ] && grep -q '^lint:' "$PROJECT_ROOT/Makefile" 2>/dev/null; then
      lint_cmd="make lint"
    fi
  fi

  if [ -z "$lint_cmd" ]; then
    skip "Lint (no linter found)"
    append_gate "lint" "true" "0" "No linter configured or detected" "[]"
    return
  fi

  # Substitute {files} placeholder
  local expanded_cmd="${lint_cmd//\{files\}/$lint_files}"

  # Run with timeout
  local lint_output="" lint_exit=0
  lint_output=$(cd "$PROJECT_ROOT" && timeout "${TIMEOUT_SECONDS}s" bash -c "$expanded_cmd" 2>&1) || lint_exit=$?

  if [ "$lint_exit" -eq 124 ]; then
    # Timeout
    if [ "$ON_TIMEOUT" = "warn" ]; then
      warn "Lint (timed out after ${TIMEOUT_SECONDS}s -- passing with warning)"
      append_gate "lint" "true" "$file_count" "Lint timed out (${TIMEOUT_SECONDS}s) -- passed as warning" "[]"
    else
      err "Lint (timed out after ${TIMEOUT_SECONDS}s)"
      append_gate "lint" "false" "$file_count" "Lint timed out (${TIMEOUT_SECONDS}s)" "[]"
      OVERALL_PASSED="false"
    fi
  elif [ "$lint_exit" -ne 0 ]; then
    err "Lint ($file_count files)"
    echo -e "\n${lint_output}\n" >&2
    append_gate "lint" "false" "$file_count" "Lint failed" "[]"
    OVERALL_PASSED="false"
  else
    ok "Lint ($file_count files)"
    append_gate "lint" "true" "$file_count" "All files pass lint" "[]"
  fi
}

# ============================================================
# GATE 2: Architecture
# ============================================================
run_architecture_gate() {
  if [ "$ARCH_ENABLED" = "false" ]; then
    skip "Architecture (disabled)"
    append_gate "architecture" "true" "0" "Architecture gate disabled" "[]"
    return
  fi

  local arch_file="$PROJECT_ROOT/$ARCH_CONFIG_PATH"
  if [ ! -f "$arch_file" ]; then
    skip "Architecture (no $ARCH_CONFIG_PATH found)"
    append_gate "architecture" "true" "0" "No architecture config found" "[]"
    return
  fi

  if [ -z "$FILTERED_FILES" ]; then
    skip "Architecture (no source files staged)"
    append_gate "architecture" "true" "0" "No source files to check" "[]"
    return
  fi

  local validator="$SCRIPT_DIR/validate-architecture.sh"
  if [ ! -x "$validator" ]; then
    warn "Architecture (validator not found at $validator)"
    append_gate "architecture" "true" "0" "Architecture validator not installed" "[]"
    return
  fi

  # Run architecture validator with timeout
  local arch_output="" arch_exit=0
  arch_output=$(cd "$PROJECT_ROOT" && timeout "${TIMEOUT_SECONDS}s" bash "$validator" "$ARCH_CONFIG_PATH" $FILTERED_FILES 2>/dev/null) || arch_exit=$?

  if [ "$arch_exit" -eq 124 ]; then
    if [ "$ON_TIMEOUT" = "warn" ]; then
      warn "Architecture (timed out after ${TIMEOUT_SECONDS}s -- passing with warning)"
      append_gate "architecture" "true" "0" "Architecture check timed out (${TIMEOUT_SECONDS}s) -- passed as warning" "[]"
    else
      err "Architecture (timed out after ${TIMEOUT_SECONDS}s)"
      append_gate "architecture" "false" "0" "Architecture check timed out (${TIMEOUT_SECONDS}s)" "[]"
      OVERALL_PASSED="false"
    fi
    return
  fi

  # Parse the JSON output from validator
  local arch_passed="" arch_files_checked="" arch_violations=""
  arch_passed=$(echo "$arch_output" | node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).passed))" 2>/dev/null || echo "true")
  arch_files_checked=$(echo "$arch_output" | node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).files_checked))" 2>/dev/null || echo "0")
  arch_violations=$(echo "$arch_output" | node -e "process.stdout.write(JSON.stringify(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).violations || []))" 2>/dev/null || echo "[]")

  if [ "$arch_passed" = "false" ]; then
    err "Architecture ($arch_files_checked files)"
    # Print violation details to stderr
    echo "$arch_violations" | node -e "
      const v = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
      v.forEach(item => {
        console.error('');
        console.error('  VIOLATION: ' + item.file);
        console.error('  Rule: ' + item.rule);
        console.error('  Issue: ' + item.message);
        console.error('  Fix: ' + item.fix);
      });
    " >&2
    append_gate "architecture" "false" "$arch_files_checked" "Architecture violations found" "$arch_violations"
    OVERALL_PASSED="false"
  else
    ok "Architecture ($arch_files_checked files)"
    append_gate "architecture" "true" "$arch_files_checked" "No architecture violations" "[]"
  fi
}

# ============================================================
# GATE 3: Structural tests
# ============================================================
run_structural_gate() {
  if [ "$STRUCTURAL_ENABLED" = "false" ]; then
    skip "Structural (disabled)"
    append_gate "structural" "true" "0" "Structural gate disabled" "[]"
    return
  fi

  if [ -z "$PLAN_PATH" ]; then
    skip "Structural (no plan path provided)"
    append_gate "structural" "true" "0" "No plan path provided" "[]"
    return
  fi

  if [ ! -f "$PLAN_PATH" ]; then
    skip "Structural (plan file not found: $PLAN_PATH)"
    append_gate "structural" "true" "0" "Plan file not found" "[]"
    return
  fi

  # Extract structural_tests block from plan
  local tests_block=""
  tests_block=$(sed -n '/<structural_tests>/,/<\/structural_tests>/p' "$PLAN_PATH" 2>/dev/null || echo "")

  if [ -z "$tests_block" ]; then
    skip "Structural (no tests defined in plan)"
    append_gate "structural" "true" "0" "No structural tests in plan" "[]"
    return
  fi

  # Parse and run each check
  local check_count=0
  local fail_count=0
  local violations="[]"

  while IFS= read -r check_line; do
    local check_type="" check_path="" check_pattern="" check_key=""

    check_type=$(echo "$check_line" | sed -n 's/.*type="\([^"]*\)".*/\1/p')
    check_path=$(echo "$check_line" | sed -n 's/.*path="\([^"]*\)".*/\1/p')
    check_pattern=$(echo "$check_line" | sed -n 's/.*pattern="\([^"]*\)".*/\1/p')
    check_key=$(echo "$check_line" | sed -n 's/.*key="\([^"]*\)".*/\1/p')

    [ -z "$check_type" ] && continue
    check_count=$((check_count + 1))

    local check_passed="true"
    local check_msg=""
    local resolved_path="$PROJECT_ROOT/$check_path"

    case "$check_type" in
      file-exists)
        if [ ! -f "$resolved_path" ]; then
          check_passed="false"
          check_msg="File does not exist: $check_path"
        fi
        ;;
      file-contains)
        if [ ! -f "$resolved_path" ] || ! grep -qE "$check_pattern" "$resolved_path" 2>/dev/null; then
          check_passed="false"
          check_msg="File $check_path does not contain pattern: $check_pattern"
        fi
        ;;
      file-not-contains)
        if [ -f "$resolved_path" ] && grep -qE "$check_pattern" "$resolved_path" 2>/dev/null; then
          check_passed="false"
          check_msg="File $check_path contains forbidden pattern: $check_pattern"
        fi
        ;;
      executable)
        if [ ! -x "$resolved_path" ]; then
          check_passed="false"
          check_msg="File is not executable: $check_path"
        fi
        ;;
      json-valid)
        if ! node -e "JSON.parse(require('fs').readFileSync('$resolved_path','utf8'))" 2>/dev/null; then
          check_passed="false"
          check_msg="File is not valid JSON: $check_path"
        fi
        ;;
      json-has-key)
        if ! node -e "
          const data = JSON.parse(require('fs').readFileSync('$resolved_path','utf8'));
          const keys = '$check_key'.split('.');
          let obj = data;
          for (const k of keys) { if (obj === undefined || obj === null) process.exit(1); obj = obj[k]; }
          if (obj === undefined) process.exit(1);
        " 2>/dev/null; then
          check_passed="false"
          check_msg="JSON key '$check_key' not found in $check_path"
        fi
        ;;
      *)
        warn "Unknown structural check type: $check_type"
        continue
        ;;
    esac

    if [ "$check_passed" = "false" ]; then
      fail_count=$((fail_count + 1))
      violations=$(node -e "
        const v = JSON.parse(process.argv[1]);
        v.push({file: process.argv[2], rule: 'structural:' + process.argv[3], message: process.argv[4], fix: 'Fix the structural check requirement'});
        console.log(JSON.stringify(v));
      " "$violations" "$check_path" "$check_type" "$check_msg")
    fi
  done < <(echo "$tests_block" | grep '<check ')

  if [ "$fail_count" -gt 0 ]; then
    err "Structural ($fail_count/$check_count checks failed)"
    echo "$violations" | node -e "
      const v = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
      v.forEach(item => {
        console.error('');
        console.error('  VIOLATION: ' + item.file);
        console.error('  Rule: ' + item.rule);
        console.error('  Issue: ' + item.message);
      });
    " >&2
    append_gate "structural" "false" "$check_count" "$fail_count structural checks failed" "$violations"
    OVERALL_PASSED="false"
  else
    ok "Structural ($check_count checks passed)"
    append_gate "structural" "true" "$check_count" "All structural checks pass" "[]"
  fi
}

# ============================================================
# Run all gates
# ============================================================
echo -e "\n${BOLD}=== GATE CHECK ===${RESET}\n" >&2

run_lint_gate
run_architecture_gate
run_structural_gate

# --- Calculate duration ---
END_MS=$(date +%s%3N 2>/dev/null || echo "0")
DURATION_MS=0
if [ "$START_MS" != "0" ] && [ "$END_MS" != "0" ]; then
  DURATION_MS=$((END_MS - START_MS))
fi

# --- Output JSON to stdout ---
node -e "
  const result = {
    passed: process.argv[1] === 'true',
    duration_ms: parseInt(process.argv[2]),
    gates: JSON.parse(process.argv[3])
  };
  console.log(JSON.stringify(result, null, 2));
" "$OVERALL_PASSED" "$DURATION_MS" "$GATES_RESULTS"

# --- Human summary to stderr ---
echo "" >&2
if [ "$OVERALL_PASSED" = "true" ]; then
  echo -e "${GREEN}${BOLD}=== ALL GATES PASSED ===${RESET}\n" >&2
  exit 0
else
  echo -e "${RED}${BOLD}=== GATE FAILED ===${RESET}" >&2
  echo -e "Task commit blocked. Fix violations and retry.\n" >&2
  exit 1
fi
