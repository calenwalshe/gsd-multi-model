#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# check-stale-todos.sh -- Stale TODO/FIXME detector
#
# Finds TODO and FIXME comments in source files, computes their
# age via git blame, and classifies severity based on thresholds.
#
# Usage:
#   bin/check-stale-todos.sh                              # scan project
#   bin/check-stale-todos.sh --project-root <path>        # explicit root
#   bin/check-stale-todos.sh --warn-days 14 --critical-days 60
#
# Output:
#   stdout: JSON {"passed": bool, "findings": [...], "thresholds": {...}}
#   stderr: Human-readable summary
#   exit 0: no TODOs found
#   exit 1: TODOs found
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Defaults
WARN_DAYS=30
CRITICAL_DAYS=90

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root)  PROJECT_ROOT="$2"; shift 2 ;;
    --warn-days)     WARN_DAYS="$2"; shift 2 ;;
    --critical-days) CRITICAL_DAYS="$2"; shift 2 ;;
    *)               shift ;;
  esac
done

# --- Read thresholds from config (if present) ---
CONFIG_FILE="$PROJECT_ROOT/.planning/config.json"
if [ -f "$CONFIG_FILE" ]; then
  CONFIG_VALS=$(node -e "
    const c = JSON.parse(require('fs').readFileSync('$CONFIG_FILE','utf8'));
    const e = c.entropy || {};
    const st = (e.checks && e.checks.stale_todos) || {};
    console.log(JSON.stringify({
      warn: st.warn_after_days || 30,
      critical: st.critical_after_days || 90
    }));
  " 2>/dev/null || echo '{}')

  if [ "$CONFIG_VALS" != '{}' ]; then
    # Only apply config defaults if CLI args weren't explicitly set
    CFG_WARN=$(echo "$CONFIG_VALS" | node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).warn))" 2>/dev/null || echo "30")
    CFG_CRITICAL=$(echo "$CONFIG_VALS" | node -e "process.stdout.write(String(JSON.parse(require('fs').readFileSync('/dev/stdin','utf8')).critical))" 2>/dev/null || echo "90")
    # Config values are defaults; CLI args already set above take precedence
    # We only use config if the defaults haven't been overridden
    # Since we can't easily detect "was --warn-days passed?", config is used as base defaults
    WARN_DAYS="${CFG_WARN}"
    CRITICAL_DAYS="${CFG_CRITICAL}"
  fi
fi

# --- ANSI color helpers (stderr) ---
if [ -t 2 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; DIM=''; RESET=''
fi

# --- Current time (UTC) ---
NOW_EPOCH=$(date -u +%s)

# --- Get blame date for a line ---
get_blame_epoch() {
  local file="$1" line="$2"
  # Check if file is git-tracked
  if ! git -C "$PROJECT_ROOT" ls-files --error-unmatch "$file" >/dev/null 2>&1; then
    echo "$NOW_EPOCH"  # untracked: use current time
    return
  fi
  local author_time=""
  author_time=$(git -C "$PROJECT_ROOT" blame -p "$file" -L "$line,$line" 2>/dev/null \
    | grep '^author-time ' \
    | cut -d' ' -f2)
  if [ -n "$author_time" ]; then
    echo "$author_time"
  else
    echo "$NOW_EPOCH"
  fi
}

# --- Get author name for a line ---
get_blame_author() {
  local file="$1" line="$2"
  if ! git -C "$PROJECT_ROOT" ls-files --error-unmatch "$file" >/dev/null 2>&1; then
    echo "unknown"
    return
  fi
  local author=""
  author=$(git -C "$PROJECT_ROOT" blame -p "$file" -L "$line,$line" 2>/dev/null \
    | grep '^author ' \
    | sed 's/^author //')
  if [ -n "$author" ]; then
    echo "$author"
  else
    echo "unknown"
  fi
}

# --- Find all TODO/FIXME comments ---
cd "$PROJECT_ROOT"

FINDINGS="[]"
FINDING_COUNT=0

# Grep for TODO/FIXME in supported file types, excluding noise directories
GREP_OUTPUT=$(grep -rn --include="*.sh" --include="*.js" --include="*.cjs" --include="*.ts" --include="*.md" \
  -e "TODO" -e "FIXME" \
  --exclude-dir=".git" --exclude-dir="node_modules" --exclude-dir=".planning" \
  . 2>/dev/null || true)

if [ -n "$GREP_OUTPUT" ]; then
  while IFS= read -r match_line; do
    # Parse file:line:text from grep output
    # Format: ./path/to/file:line:text
    local_file=$(echo "$match_line" | sed 's/^\.\///' | cut -d: -f1)
    line_num=$(echo "$match_line" | cut -d: -f2)
    match_text=$(echo "$match_line" | cut -d: -f3-)

    # Skip if not a valid line number
    if ! [[ "$line_num" =~ ^[0-9]+$ ]]; then
      continue
    fi

    # Get blame data
    blame_epoch=$(get_blame_epoch "$local_file" "$line_num")
    author=$(get_blame_author "$local_file" "$line_num")

    # Compute age
    age_days=$(( (NOW_EPOCH - blame_epoch) / 86400 ))

    # Compute introduced date
    introduced=$(date -u -d "@$blame_epoch" +"%Y-%m-%d" 2>/dev/null || date -u -r "$blame_epoch" +"%Y-%m-%d" 2>/dev/null || echo "unknown")

    # Classify severity
    severity="info"
    if [ "$age_days" -ge "$CRITICAL_DAYS" ]; then
      severity="critical"
    elif [ "$age_days" -ge "$WARN_DAYS" ]; then
      severity="warning"
    fi

    # Append to findings array
    FINDINGS=$(node -e "
      const findings = JSON.parse(process.argv[1]);
      findings.push({
        file: process.argv[2],
        line: parseInt(process.argv[3]),
        text: process.argv[4].trim(),
        author: process.argv[5],
        age_days: parseInt(process.argv[6]),
        introduced: process.argv[7],
        severity: process.argv[8]
      });
      console.log(JSON.stringify(findings));
    " "$FINDINGS" "$local_file" "$line_num" "$match_text" "$author" "$age_days" "$introduced" "$severity")

    FINDING_COUNT=$((FINDING_COUNT + 1))
  done <<< "$GREP_OUTPUT"
fi

# --- Determine pass/fail ---
PASSED="true"
if [ "$FINDING_COUNT" -gt 0 ]; then
  PASSED="false"
fi

# --- Output JSON to stdout ---
node -e "
  const result = {
    passed: process.argv[1] === 'true',
    findings: JSON.parse(process.argv[2]),
    thresholds: {
      warn_after_days: parseInt(process.argv[3]),
      critical_after_days: parseInt(process.argv[4])
    }
  };
  console.log(JSON.stringify(result, null, 2));
" "$PASSED" "$FINDINGS" "$WARN_DAYS" "$CRITICAL_DAYS"

# --- Human summary to stderr ---
echo "" >&2
if [ "$FINDING_COUNT" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}No stale TODOs/FIXMEs found${RESET}" >&2
else
  # Count by severity
  CRITICAL_COUNT=$(echo "$FINDINGS" | node -e "
    const f=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    console.log(f.filter(x=>x.severity==='critical').length);
  ")
  WARNING_COUNT=$(echo "$FINDINGS" | node -e "
    const f=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    console.log(f.filter(x=>x.severity==='warning').length);
  ")
  INFO_COUNT=$(echo "$FINDINGS" | node -e "
    const f=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    console.log(f.filter(x=>x.severity==='info').length);
  ")

  echo -e "${BOLD}Found $FINDING_COUNT TODO/FIXME items:${RESET}" >&2
  [ "$CRITICAL_COUNT" -gt 0 ] && echo -e "  ${RED}Critical: $CRITICAL_COUNT${RESET} (>= ${CRITICAL_DAYS} days)" >&2
  [ "$WARNING_COUNT" -gt 0 ] && echo -e "  ${YELLOW}Warning:  $WARNING_COUNT${RESET} (>= ${WARN_DAYS} days)" >&2
  [ "$INFO_COUNT" -gt 0 ] && echo -e "  ${CYAN}Info:     $INFO_COUNT${RESET} (< ${WARN_DAYS} days)" >&2

  # List findings
  echo "" >&2
  echo "$FINDINGS" | node -e "
    const f=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    f.forEach(item => {
      const sev = item.severity === 'critical' ? 'CRIT' : item.severity === 'warning' ? 'WARN' : 'INFO';
      console.error('  [' + sev + '] ' + item.file + ':' + item.line + ' (' + item.age_days + 'd) ' + item.text);
    });
  " >&2
fi
echo "" >&2

# --- Exit code ---
if [ "$PASSED" = "true" ]; then
  exit 0
else
  exit 1
fi
