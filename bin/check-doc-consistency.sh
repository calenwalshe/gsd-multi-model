#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# check-doc-consistency.sh -- AGENTS.md convention checker
#
# Checks automatable conventions from AGENTS.md against actual
# code patterns. Reports drift as structured findings.
#
# Checks:
#   1. No debug/log statements in production code
#   2. Instruction files under 200 lines
#   3. Tests exist for bin/ scripts
#
# Usage:
#   bin/check-doc-consistency.sh
#   bin/check-doc-consistency.sh --project-root /path/to/project
#   bin/check-doc-consistency.sh --agents-file AGENTS.md
#
# Output:
#   stdout: JSON {"passed": bool, "findings": [...]}
#   stderr: Human-readable summary with ANSI colors
#   exit 0: check completed (even with findings)
#   exit 1: script error
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_FILE="AGENTS.md"

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --agents-file)  AGENTS_FILE="$2"; shift 2 ;;
    *)              shift ;;
  esac
done

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

echo -e "\n${BOLD}=== DOC CONSISTENCY CHECK ===${RESET}\n" >&2

# --- Findings accumulator ---
FINDINGS="[]"

add_finding() {
  local check="$1" file="$2" severity="$3" extra="$4"
  FINDINGS=$(node -e "
    const f = JSON.parse(process.argv[1]);
    const entry = Object.assign(
      { check: process.argv[2], file: process.argv[3], severity: process.argv[4] },
      JSON.parse(process.argv[5])
    );
    f.push(entry);
    console.log(JSON.stringify(f));
  " "$FINDINGS" "$check" "$file" "$severity" "$extra")
}

# ============================================================
# CHECK 1: No debug/log statements in production code
# ============================================================
run_debug_check() {
  local count=0

  # Search production files for debug statements
  # Include: .sh, .js, .cjs, .ts in bin/ and skills/
  # Exclude: test files (test-*.sh, *.test.js, *.test.ts), .planning/
  while IFS=: read -r file line text; do
    [ -z "$file" ] && continue

    # Skip test files
    local basename
    basename=$(basename "$file")
    case "$basename" in
      test-*|*.test.js|*.test.ts|*.test.cjs|*.spec.js|*.spec.ts) continue ;;
    esac

    add_finding "debug-statements" "$file" "warning" \
      "{\"line\": $line, \"text\": $(node -e "console.log(JSON.stringify(process.argv[1]))" "$text")}"
    count=$((count + 1))
  done < <(cd "$PROJECT_ROOT" && grep -rn \
    -e 'console\.log' \
    -e 'console\.debug' \
    -e 'echo.*DEBUG' \
    --include="*.sh" --include="*.js" --include="*.cjs" --include="*.ts" \
    bin/ skills/ 2>/dev/null || true)

  if [ "$count" -eq 0 ]; then
    ok "No debug statements in production code"
  else
    warn "Found $count debug statement(s) in production code"
  fi
}

# ============================================================
# CHECK 2: Instruction files under 200 lines
# ============================================================
run_linecount_check() {
  local count=0

  # Check SKILL.md files, AGENTS.md, and skill rule files
  local files_to_check=()

  # AGENTS.md in project root
  if [ -f "$PROJECT_ROOT/$AGENTS_FILE" ]; then
    files_to_check+=("$AGENTS_FILE")
  fi

  # SKILL.md files in skills/
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    files_to_check+=("$f")
  done < <(cd "$PROJECT_ROOT" && find skills -name "SKILL.md" -type f 2>/dev/null || true)

  # Rule files in skills/*/rules/
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    files_to_check+=("$f")
  done < <(cd "$PROJECT_ROOT" && find skills -path "*/rules/*.md" -type f 2>/dev/null || true)

  for f in "${files_to_check[@]}"; do
    local full_path="$PROJECT_ROOT/$f"
    [ -f "$full_path" ] || continue
    local lines
    lines=$(wc -l < "$full_path")
    if [ "$lines" -gt 200 ]; then
      add_finding "line-count" "$f" "warning" \
        "{\"lines\": $lines, \"limit\": 200}"
      count=$((count + 1))
    fi
  done

  local total=${#files_to_check[@]}
  if [ "$count" -eq 0 ]; then
    ok "All $total instruction files under 200 lines"
  else
    warn "$count of $total instruction files exceed 200 lines"
  fi
}

# ============================================================
# CHECK 3: Tests exist for bin/ scripts
# ============================================================
run_test_coverage_check() {
  local count=0
  local total=0

  for f in "$PROJECT_ROOT"/bin/*.sh; do
    [ -f "$f" ] || continue
    local basename
    basename=$(basename "$f")

    # Skip test files themselves
    case "$basename" in
      test-*) continue ;;
    esac

    total=$((total + 1))
    local expected_test="bin/test-${basename}"
    if [ ! -f "$PROJECT_ROOT/$expected_test" ]; then
      add_finding "missing-tests" "bin/$basename" "info" \
        "{\"expected_test\": \"$expected_test\"}"
      count=$((count + 1))
    fi
  done

  if [ "$count" -eq 0 ]; then
    ok "All $total bin/ scripts have test files"
  else
    warn "$count of $total bin/ scripts missing test files"
  fi
}

# --- Run all checks ---
run_debug_check
run_linecount_check
run_test_coverage_check

# --- Determine pass/fail ---
# Passed means no warning-severity findings (info is acceptable)
PASSED=$(node -e "
  const f = JSON.parse(process.argv[1]);
  const hasWarnings = f.some(item => item.severity === 'warning');
  console.log(!hasWarnings);
" "$FINDINGS")

# --- Output JSON to stdout ---
node -e "
  const result = {
    passed: process.argv[1] === 'true',
    findings: JSON.parse(process.argv[2])
  };
  console.log(JSON.stringify(result, null, 2));
" "$PASSED" "$FINDINGS"

# --- Human summary to stderr ---
FINDING_COUNT=$(node -e "console.log(JSON.parse(process.argv[1]).length)" "$FINDINGS")
echo "" >&2
if [ "$PASSED" = "true" ]; then
  echo -e "${GREEN}${BOLD}=== DOC CONSISTENCY PASSED ===${RESET} ($FINDING_COUNT finding(s))\n" >&2
else
  echo -e "${YELLOW}${BOLD}=== DOC CONSISTENCY: $FINDING_COUNT FINDING(S) ===${RESET}\n" >&2
fi
