#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# entropy-sweep.sh -- Entropy sweep orchestrator
#
# Runs all enabled entropy checks and produces aggregated
# structured output. Mirrors bin/gate-check.sh pattern.
#
# Usage:
#   bin/entropy-sweep.sh                          # run all enabled checks
#   bin/entropy-sweep.sh --check doc-consistency  # run single check
#   bin/entropy-sweep.sh --check architecture     # run architecture only
#   bin/entropy-sweep.sh --json-only              # suppress stderr output
#
# Output:
#   stdout: JSON {"sweep_type": "manual", "checks": [...], "summary": {...}}
#   stderr: Human-readable summary with ANSI colors
#   exit 0: all checks pass
#   exit 1: findings exist
#   exit 2: config error
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- ANSI color helpers (stderr is the human channel) ---
QUIET="false"
setup_colors() {
  if [ "$QUIET" = "true" ]; then
    RED=''; GREEN=''; YELLOW=''; BOLD=''; DIM=''; RESET=''
  elif [ -t 2 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
  else
    RED=''; GREEN=''; YELLOW=''; BOLD=''; DIM=''; RESET=''
  fi
}

log()  { [ "$QUIET" = "false" ] && echo -e "$1" >&2 || true; }
ok()   { log "${GREEN}  PASS${RESET} $1"; }
warn() { log "${YELLOW}  WARN${RESET} $1"; }
err()  { log "${RED}  FAIL${RESET} $1"; }
skip() { log "${DIM}  SKIP${RESET} $1"; }

# --- Parse arguments ---
SINGLE_CHECK=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)     SINGLE_CHECK="$2"; shift 2 ;;
    --json-only) QUIET="true"; shift ;;
    *)           shift ;;
  esac
done

setup_colors

# --- Load config ---
CONFIG_FILE="$PROJECT_ROOT/.planning/config.json"
ENTROPY_ENABLED="true"
ENTROPY_SCHEDULE="weekly"
DOC_CONSISTENCY_ENABLED="true"
ARCHITECTURE_ENABLED="true"
STALE_TODOS_ENABLED="true"

if [ -f "$CONFIG_FILE" ]; then
  ENTROPY_JSON=$(node -e "
    const c = JSON.parse(require('fs').readFileSync('$CONFIG_FILE','utf8'));
    const e = c.entropy || {};
    console.log(JSON.stringify({
      enabled: e.enabled !== undefined ? e.enabled : true,
      schedule: e.schedule || 'weekly',
      doc_consistency: e.checks ? (e.checks.doc_consistency ? e.checks.doc_consistency.enabled !== false : true) : true,
      architecture: e.checks ? (e.checks.architecture ? e.checks.architecture.enabled !== false : true) : true,
      stale_todos: e.checks ? (e.checks.stale_todos ? e.checks.stale_todos.enabled !== false : true) : true
    }));
  " 2>/dev/null || echo '{}')

  if [ "$ENTROPY_JSON" != '{}' ]; then
    ENTROPY_ENABLED=$(echo "$ENTROPY_JSON" | node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).enabled))")
    ENTROPY_SCHEDULE=$(echo "$ENTROPY_JSON" | node -e "process.stdout.write(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).schedule)")
    DOC_CONSISTENCY_ENABLED=$(echo "$ENTROPY_JSON" | node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).doc_consistency))")
    ARCHITECTURE_ENABLED=$(echo "$ENTROPY_JSON" | node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).architecture))")
    STALE_TODOS_ENABLED=$(echo "$ENTROPY_JSON" | node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).stale_todos))")
  fi
fi

# --- If entropy disabled globally, exit immediately ---
if [ "$ENTROPY_ENABLED" = "false" ]; then
  echo '{"sweep_type":"manual","timestamp":"'"$(date -u +"%Y-%m-%dT%H:%M:%SZ")"'","schedule":"'"$ENTROPY_SCHEDULE"'","checks":[],"summary":{"total_findings":0,"checks_run":0,"checks_passed":0},"skipped":true}'
  exit 0
fi

# --- Determine which checks to run ---
should_run() {
  local name="$1" enabled="$2"
  if [ -n "$SINGLE_CHECK" ]; then
    [ "$SINGLE_CHECK" = "$name" ] && return 0 || return 1
  fi
  [ "$enabled" = "true" ] && return 0 || return 1
}

# --- Results accumulator ---
CHECKS_RESULTS="[]"
TOTAL_FINDINGS=0
CHECKS_RUN=0
CHECKS_PASSED=0

append_check() {
  local name="$1" passed="$2" findings="$3"
  CHECKS_RESULTS=$(node -e "
    const checks = JSON.parse(process.argv[1]);
    checks.push({
      name: process.argv[2],
      passed: process.argv[3] === 'true',
      findings: JSON.parse(process.argv[4])
    });
    console.log(JSON.stringify(checks));
  " "$CHECKS_RESULTS" "$name" "$passed" "$findings")
  CHECKS_RUN=$((CHECKS_RUN + 1))
  [ "$passed" = "true" ] && CHECKS_PASSED=$((CHECKS_PASSED + 1))
  local finding_count
  finding_count=$(node -e "console.log(JSON.parse(process.argv[1]).length)" "$findings")
  TOTAL_FINDINGS=$((TOTAL_FINDINGS + finding_count))
}

log "\n${BOLD}=== ENTROPY SWEEP ===${RESET}\n"

# ============================================================
# CHECK 1: Doc Consistency
# ============================================================
if should_run "doc-consistency" "$DOC_CONSISTENCY_ENABLED"; then
  DOC_CHECKER="$SCRIPT_DIR/check-doc-consistency.sh"
  if [ -x "$DOC_CHECKER" ]; then
    DOC_OUTPUT=$(bash "$DOC_CHECKER" --project-root "$PROJECT_ROOT" 2>/dev/null) || true
    DOC_PASSED=$(echo "$DOC_OUTPUT" | node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).passed))" 2>/dev/null || echo "true")
    DOC_FINDINGS=$(echo "$DOC_OUTPUT" | node -e "process.stdout.write(JSON.stringify(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).findings || []))" 2>/dev/null || echo "[]")

    if [ "$DOC_PASSED" = "true" ]; then
      ok "Doc consistency"
    else
      warn "Doc consistency (findings detected)"
    fi
    append_check "doc-consistency" "$DOC_PASSED" "$DOC_FINDINGS"
  else
    skip "Doc consistency (checker not found)"
    append_check "doc-consistency" "true" "[]"
  fi
else
  skip "Doc consistency (disabled)"
fi

# ============================================================
# CHECK 2: Architecture
# ============================================================
if should_run "architecture" "$ARCHITECTURE_ENABLED"; then
  ARCH_VALIDATOR="$SCRIPT_DIR/validate-architecture.sh"
  ARCH_CONFIG="$PROJECT_ROOT/.architecture.json"
  if [ -x "$ARCH_VALIDATOR" ] && [ -f "$ARCH_CONFIG" ]; then
    # Collect all source files, excluding .git, node_modules, .planning
    SOURCE_FILES=$(cd "$PROJECT_ROOT" && find . -type f \( -name "*.sh" -o -name "*.js" -o -name "*.cjs" -o -name "*.ts" \) \
      -not -path "./.git/*" -not -path "./node_modules/*" -not -path "./.planning/*" \
      | sed 's|^\./||' | sort)

    if [ -n "$SOURCE_FILES" ]; then
      # shellcheck disable=SC2086
      ARCH_OUTPUT=$(cd "$PROJECT_ROOT" && bash "$ARCH_VALIDATOR" .architecture.json $SOURCE_FILES 2>/dev/null) || true
      ARCH_PASSED=$(echo "$ARCH_OUTPUT" | node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).passed))" 2>/dev/null || echo "true")
      ARCH_VIOLATIONS=$(echo "$ARCH_OUTPUT" | node -e "process.stdout.write(JSON.stringify(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).violations || []))" 2>/dev/null || echo "[]")

      # Convert violations to findings format
      ARCH_FINDINGS=$(node -e "
        const v = JSON.parse(process.argv[1]);
        const findings = v.map(item => ({
          check: 'architecture',
          file: item.file,
          severity: 'warning',
          rule: item.rule,
          message: item.message
        }));
        console.log(JSON.stringify(findings));
      " "$ARCH_VIOLATIONS")

      if [ "$ARCH_PASSED" = "true" ]; then
        ok "Architecture"
      else
        warn "Architecture (violations detected)"
      fi
      append_check "architecture" "$ARCH_PASSED" "$ARCH_FINDINGS"
    else
      skip "Architecture (no source files found)"
      append_check "architecture" "true" "[]"
    fi
  else
    skip "Architecture (validator or config not found)"
    append_check "architecture" "true" "[]"
  fi
else
  skip "Architecture (disabled)"
fi

# ============================================================
# CHECK 3: Stale TODOs
# ============================================================
if should_run "stale-todos" "$STALE_TODOS_ENABLED"; then
  TODO_CHECKER="$SCRIPT_DIR/check-stale-todos.sh"
  if [ -x "$TODO_CHECKER" ]; then
    TODO_OUTPUT=$(bash "$TODO_CHECKER" --project-root "$PROJECT_ROOT" 2>/dev/null) || true
    TODO_PASSED=$(echo "$TODO_OUTPUT" | node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).passed))" 2>/dev/null || echo "true")
    TODO_FINDINGS=$(echo "$TODO_OUTPUT" | node -e "process.stdout.write(JSON.stringify(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).findings || []))" 2>/dev/null || echo "[]")

    if [ "$TODO_PASSED" = "true" ]; then
      ok "Stale TODOs"
    else
      warn "Stale TODOs (findings detected)"
    fi
    append_check "stale-todos" "$TODO_PASSED" "$TODO_FINDINGS"
  else
    skip "Stale TODOs (checker not yet created -- Plan 02)"
  fi
else
  skip "Stale TODOs (disabled)"
fi

# --- Output JSON to stdout ---
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
node -e "
  const result = {
    sweep_type: 'manual',
    timestamp: process.argv[1],
    schedule: process.argv[2],
    checks: JSON.parse(process.argv[3]),
    summary: {
      total_findings: parseInt(process.argv[4]),
      checks_run: parseInt(process.argv[5]),
      checks_passed: parseInt(process.argv[6])
    }
  };
  console.log(JSON.stringify(result, null, 2));
" "$TIMESTAMP" "$ENTROPY_SCHEDULE" "$CHECKS_RESULTS" "$TOTAL_FINDINGS" "$CHECKS_RUN" "$CHECKS_PASSED"

# --- Human summary to stderr ---
log ""
if [ "$TOTAL_FINDINGS" -eq 0 ]; then
  log "${GREEN}${BOLD}=== ENTROPY SWEEP PASSED ===${RESET} ($CHECKS_RUN checks run)\n"
  exit 0
else
  log "${YELLOW}${BOLD}=== ENTROPY SWEEP: $TOTAL_FINDINGS FINDING(S) ===${RESET} ($CHECKS_PASSED/$CHECKS_RUN checks passed)\n"
  exit 1
fi
