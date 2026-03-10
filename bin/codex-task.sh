#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# gsd codex-task -- Execute a planned task via Codex CLI
#
# Reads task specs from PLAN.md XML blocks, invokes Codex CLI
# in an isolated worktree, and produces structured JSON results.
#
# Usage:
#   bin/codex-task.sh --plan PATH --task N              # execute task
#   bin/codex-task.sh --plan PATH --task N --dry-run    # preview only
#   bin/codex-task.sh --plan PATH --task N --timeout 60 # custom timeout
#   bin/codex-task.sh --plan PATH --task N --force      # skip executor check
#
# Exit codes:
#   0 = success
#   1 = Codex failure (non-zero exit from Codex)
#   2 = parse error (plan not found, task not found, XML parse failure)
#   3 = timeout
#   4 = pre-flight failure (missing codex, missing args, executor
#       mismatch, low confidence)
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- ANSI color helpers with TTY detection ---
if [ -t 2 ]; then
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

ok()   { echo -e "${GREEN}  ok${RESET} $1" >&2; }
warn() { echo -e "${YELLOW}  warn${RESET} $1" >&2; }
err()  { echo -e "${RED}  err${RESET} $1" >&2; }

# ============================================================
# Section 1: Argument parsing and pre-flight checks
# ============================================================

PLAN_FILE=""
TASK_NUM=""
DRY_RUN=false
TIMEOUT=300
FORCE=false

usage() {
  cat >&2 <<USAGE
Usage: $(basename "$0") --plan PATH --task N [OPTIONS]

Required:
  --plan PATH     Path to PLAN.md file
  --task N        Task number to execute (1-based)

Options:
  --dry-run       Print what would be run without executing
  --timeout N     Kill Codex after N seconds (default: 300)
  --force         Skip executor validation (run even if not executor="codex")
  --json          JSON output mode (default, kept for consistency)
  -h, --help      Show this help message

Exit codes:
  0  success
  1  Codex failure
  2  parse error (plan/task not found)
  3  timeout
  4  pre-flight failure (missing args, codex not found, etc.)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)
      PLAN_FILE="$2"
      shift 2
      ;;
    --task)
      TASK_NUM="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --json)
      # JSON is default output mode; flag exists for consistency
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "Unknown argument: $1"
      usage
      exit 4
      ;;
  esac
done

# Validate required arguments
if [ -z "$PLAN_FILE" ] || [ -z "$TASK_NUM" ]; then
  err "Missing required arguments: --plan and --task"
  usage
  exit 4
fi

# Validate plan file exists
if [ ! -f "$PLAN_FILE" ]; then
  err "Plan file not found: $PLAN_FILE"
  exit 2
fi

# Check codex in PATH (skip for --dry-run)
if [ "$DRY_RUN" = false ] && ! command -v codex >/dev/null 2>&1; then
  err "Codex CLI not found. Install with: npm install -g @openai/codex"
  exit 4
fi

# Check git repo
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  err "Not a git repository. Run this from inside a git repo."
  exit 4
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"

# ============================================================
# Section 2: XML task extraction
# ============================================================

# Extract the Nth task block from the plan file
PLAN_CONTENT="$(cat "$PLAN_FILE")"

# Use awk to extract the Nth <task ...>...</task> block
TASK_BLOCK="$(awk -v n="$TASK_NUM" '
  /<task[[:space:]]/ { count++; if (count == n) { capturing = 1 } }
  capturing { print }
  capturing && /<\/task>/ { capturing = 0; exit }
' <<< "$PLAN_CONTENT")"

if [ -z "$TASK_BLOCK" ]; then
  err "Task $TASK_NUM not found in plan: $PLAN_FILE"
  exit 2
fi

# Extract attributes from opening <task> tag
TASK_OPENING_TAG="$(echo "$TASK_BLOCK" | head -1)"

extract_attr() {
  local attr="$1"
  local tag="$2"
  echo "$tag" | grep -oP "${attr}=\"[^\"]*\"" | head -1 | sed "s/${attr}=\"//;s/\"$//" || echo ""
}

EXECUTOR="$(extract_attr "executor" "$TASK_OPENING_TAG")"
CONFIDENCE="$(extract_attr "confidence" "$TASK_OPENING_TAG")"
TASK_TYPE="$(extract_attr "type" "$TASK_OPENING_TAG")"

# Extract child elements
extract_element() {
  local element="$1"
  local block="$2"
  # For single-line elements like <name>...</name>
  local single_line
  single_line="$(echo "$block" | grep -oP "(?<=<${element}>).*(?=</${element}>)" | head -1)" || true
  if [ -n "$single_line" ]; then
    echo "$single_line"
    return
  fi
  # For multi-line elements, use awk
  echo "$block" | awk -v elem="$element" '
    $0 ~ "<"elem">" { capturing = 1; sub(".*<"elem">", ""); if (length($0) > 0) print; next }
    $0 ~ "</"elem">" { sub("</"elem">.*", ""); if (length($0) > 0) print; exit }
    capturing { print }
  '
}

TASK_NAME="$(extract_element "name" "$TASK_BLOCK")"
TASK_FILES="$(extract_element "files" "$TASK_BLOCK")"
TASK_ACTION="$(extract_element "action" "$TASK_BLOCK")"
TASK_DONE="$(extract_element "done" "$TASK_BLOCK")"

# Extract files_modified from plan frontmatter
FILES_MODIFIED="$(echo "$PLAN_CONTENT" | awk '
  /^---$/ { fm++; next }
  fm == 1 && /^files_modified:/ { in_fm = 1; next }
  fm == 1 && in_fm && /^  - / { sub(/^  - /, ""); print; next }
  fm == 1 && in_fm && !/^  / { in_fm = 0 }
  fm >= 2 { exit }
')"

# Derive task_id from plan filename + task number
PLAN_BASENAME="$(basename "$PLAN_FILE")"
if [[ "$PLAN_BASENAME" =~ ^([0-9]+)-([0-9]+)-PLAN\.md$ ]]; then
  PHASE_NUM="${BASH_REMATCH[1]}"
  PLAN_NUM="${BASH_REMATCH[2]}"
  TASK_ID="${PHASE_NUM}-${PLAN_NUM}-T${TASK_NUM}"
else
  TASK_ID="unknown-T${TASK_NUM}"
fi

# --- Executor validation ---
if [ "$EXECUTOR" != "codex" ] && [ "$FORCE" = false ]; then
  warn "Task executor is '$EXECUTOR', not 'codex'. Use --force to override."
  exit 4
fi

if [ "$EXECUTOR" != "codex" ] && [ "$FORCE" = true ]; then
  warn "Task executor is '$EXECUTOR', not 'codex'. Proceeding with --force."
fi

# --- Confidence routing ---
CODEX_MODE=""
case "${CONFIDENCE:-high}" in
  high)
    CODEX_MODE="--full-auto"
    ;;
  medium)
    CODEX_MODE=""
    ;;
  low)
    warn "Low confidence task -- escalate to Claude instead"
    exit 4
    ;;
  *)
    warn "Unknown confidence level: $CONFIDENCE. Defaulting to medium."
    CODEX_MODE=""
    ;;
esac

# ============================================================
# Section 3: Context injection and prompt building
# ============================================================

PROMPT_FILE="$(mktemp /tmp/gsd-codex-prompt-XXXXXX.md)"

{
  echo "You are working on a planned task. Follow the instructions exactly."
  echo ""
  echo "Task: $TASK_NAME"
  echo "Task ID: $TASK_ID"
  echo ""
  echo "## Instructions"
  echo ""
  echo "$TASK_ACTION"
  echo ""
  echo "## Acceptance Criteria"
  echo ""
  echo "$TASK_DONE"
  echo ""
  echo "## Files to Modify"
  echo ""
  if [ -n "$TASK_FILES" ]; then
    echo "$TASK_FILES"
  fi
  if [ -n "$FILES_MODIFIED" ]; then
    echo "$FILES_MODIFIED"
  fi

  # Append project instructions if available
  if [ -f "$REPO_ROOT/CLAUDE.md" ]; then
    echo ""
    echo "## Project Instructions (follow these conventions)"
    echo ""
    cat "$REPO_ROOT/CLAUDE.md"
  fi

  if [ -f "$REPO_ROOT/AGENTS.md" ]; then
    echo ""
    echo "## Build & Architecture Conventions"
    echo ""
    cat "$REPO_ROOT/AGENTS.md"
  fi
} > "$PROMPT_FILE"

# ============================================================
# Section 4: Dry-run output
# ============================================================

if [ "$DRY_RUN" = true ]; then
  echo "--- Dry Run ---" >&2
  echo "Task:       $TASK_NAME" >&2
  echo "Task ID:    $TASK_ID" >&2
  echo "Executor:   $EXECUTOR" >&2
  echo "Confidence: $CONFIDENCE" >&2
  echo "Files:      $TASK_FILES" >&2
  echo "" >&2
  echo "Prompt (first 500 chars):" >&2
  head -c 500 "$PROMPT_FILE" >&2
  echo "" >&2
  echo "" >&2

  # Build the command that would be run
  CODEX_CMD="codex ${CODEX_MODE:+$CODEX_MODE }--quiet -p \"\$(cat $PROMPT_FILE)\""
  echo "Codex command: $CODEX_CMD" >&2

  # JSON output to stdout
  # Escape strings for JSON
  json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    echo "$s"
  }

  CODEX_CMD_ESCAPED="$(json_escape "$CODEX_CMD")"
  TASK_NAME_ESCAPED="$(json_escape "$TASK_NAME")"

  printf '{"dry_run":true,"task_id":"%s","task_name":"%s","executor":"%s","confidence":"%s","codex_command":"%s"}\n' \
    "$TASK_ID" "$TASK_NAME_ESCAPED" "${EXECUTOR:-unknown}" "${CONFIDENCE:-unknown}" "$CODEX_CMD_ESCAPED"

  rm -f "$PROMPT_FILE"
  exit 0
fi

# ============================================================
# Section 5: Worktree creation
# ============================================================

WT_CREATE_SCRIPT="$SCRIPT_DIR/worktree-create.sh"
if [ ! -x "$WT_CREATE_SCRIPT" ]; then
  err "worktree-create.sh not found or not executable at: $WT_CREATE_SCRIPT"
  exit 4
fi

WT_JSON="$(bash "$WT_CREATE_SCRIPT" --task "$PLAN_FILE" --json 2>/dev/null)" || {
  err "Failed to create worktree"
  rm -f "$PROMPT_FILE"
  exit 4
}

WT_BRANCH="$(echo "$WT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['branch'])" 2>/dev/null)"
WT_PATH="$(echo "$WT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['path'])" 2>/dev/null)"

ok "Worktree created: $WT_BRANCH at $WT_PATH"

# ============================================================
# Section 6: Codex invocation
# ============================================================

STDOUT_FILE="$(mktemp /tmp/gsd-codex-stdout-XXXXXX)"
STDERR_FILE="$(mktemp /tmp/gsd-codex-stderr-XXXXXX)"

START_EPOCH="$(date +%s)"

CODEX_EXIT=0
EXIT_REASON="success"

# Run Codex in the worktree
(
  cd "$WT_PATH"
  if [ -n "$CODEX_MODE" ]; then
    timeout "$TIMEOUT" codex $CODEX_MODE --quiet -p "$(cat "$PROMPT_FILE")" 2>"$STDERR_FILE" | tee "$STDOUT_FILE"
  else
    timeout "$TIMEOUT" codex --quiet -p "$(cat "$PROMPT_FILE")" 2>"$STDERR_FILE" | tee "$STDOUT_FILE"
  fi
) || CODEX_EXIT=$?

END_EPOCH="$(date +%s)"
DURATION=$((END_EPOCH - START_EPOCH))

case "$CODEX_EXIT" in
  0)
    EXIT_REASON="success"
    ;;
  124)
    EXIT_REASON="timeout"
    warn "Codex timed out after ${TIMEOUT}s"
    ;;
  *)
    EXIT_REASON="codex_error"
    err "Codex exited with code $CODEX_EXIT"
    ;;
esac

# ============================================================
# Section 7: Auto-commit and result capture
# ============================================================

COMMIT_HASH=""
CHANGED_FILES="[]"
DIFF_SUMMARY="{}"

if [ "$EXIT_REASON" = "success" ]; then
  (
    cd "$WT_PATH"
    git add -A

    if ! git diff --cached --quiet 2>/dev/null; then
      git commit -m "feat($TASK_ID): $TASK_NAME" --quiet 2>/dev/null
    fi
  ) || true

  # Capture results from worktree
  COMMIT_HASH="$(cd "$WT_PATH" && git rev-parse --short HEAD 2>/dev/null)" || true

  # Get changed files as JSON array
  CHANGED_FILES_RAW="$(cd "$WT_PATH" && git diff --name-only HEAD~1 2>/dev/null)" || true
  if [ -n "$CHANGED_FILES_RAW" ]; then
    CHANGED_FILES="$(echo "$CHANGED_FILES_RAW" | python3 -c "
import sys, json
files = [l.strip() for l in sys.stdin if l.strip()]
print(json.dumps(files))
" 2>/dev/null)" || CHANGED_FILES="[]"
  fi

  # Get diff summary
  DIFF_SUMMARY="$(cd "$WT_PATH" && git diff --numstat HEAD~1 2>/dev/null | python3 -c "
import sys, json
result = {}
for line in sys.stdin:
    parts = line.strip().split('\t')
    if len(parts) == 3:
        added, deleted, filename = parts
        result[filename] = {'+': int(added) if added != '-' else 0, '-': int(deleted) if deleted != '-' else 0}
print(json.dumps(result))
" 2>/dev/null)" || DIFF_SUMMARY="{}"
fi

# ============================================================
# Section 8: Worktree cleanup
# ============================================================

MERGE_COMMIT=""
CLEANUP_SCRIPT="$SCRIPT_DIR/worktree-cleanup.sh"

cd "$REPO_ROOT"

if [ -x "$CLEANUP_SCRIPT" ]; then
  if [ "$EXIT_REASON" = "success" ]; then
    # Merge back on success
    CLEANUP_JSON="$(bash "$CLEANUP_SCRIPT" "$WT_BRANCH" --json 2>/dev/null)" || {
      warn "Worktree cleanup/merge failed"
    }
    MERGE_COMMIT="$(echo "$CLEANUP_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('merge_commit',''))" 2>/dev/null)" || true
  else
    # Discard on failure/timeout
    bash "$CLEANUP_SCRIPT" --no-merge --force "$WT_BRANCH" 2>/dev/null || {
      warn "Worktree discard failed"
    }
  fi
else
  warn "worktree-cleanup.sh not found, skipping cleanup"
fi

# Clean up temp files
rm -f "$PROMPT_FILE" "$STDOUT_FILE" "$STDERR_FILE"

# ============================================================
# Section 9: Structured JSON output
# ============================================================

CODEX_STDOUT=""
CODEX_STDERR=""
[ -f "$STDOUT_FILE" ] && CODEX_STDOUT="$(cat "$STDOUT_FILE" 2>/dev/null)" || true
[ -f "$STDERR_FILE" ] && CODEX_STDERR="$(cat "$STDERR_FILE" 2>/dev/null)" || true

json_escape_val() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  echo "$s"
}

TASK_NAME_ESC="$(json_escape_val "$TASK_NAME")"
CODEX_STDOUT_ESC="$(json_escape_val "$CODEX_STDOUT")"
CODEX_STDERR_ESC="$(json_escape_val "$CODEX_STDERR")"

# Determine final exit code
FINAL_EXIT=0
case "$EXIT_REASON" in
  success) FINAL_EXIT=0 ;;
  timeout) FINAL_EXIT=3 ;;
  codex_error) FINAL_EXIT=1 ;;
esac

# JSON to stdout
cat <<ENDJSON
{"exit_code":$FINAL_EXIT,"exit_reason":"$EXIT_REASON","changed_files":$CHANGED_FILES,"commit_hash":"$COMMIT_HASH","merge_commit":"$MERGE_COMMIT","task_id":"$TASK_ID","task_name":"$TASK_NAME_ESC","duration_seconds":$DURATION,"plan":"$(json_escape_val "$PLAN_FILE")","executor":"${EXECUTOR:-unknown}","confidence":"${CONFIDENCE:-unknown}","diff_summary":$DIFF_SUMMARY,"codex_stdout":"$CODEX_STDOUT_ESC","codex_stderr":"$CODEX_STDERR_ESC"}
ENDJSON

# Count total changes
TOTAL_ADDED=0
TOTAL_DELETED=0
NUM_FILES=0
if [ "$CHANGED_FILES" != "[]" ]; then
  NUM_FILES="$(echo "$CHANGED_FILES" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)" || NUM_FILES=0
  eval "$(echo "$DIFF_SUMMARY" | python3 -c "
import sys, json
d = json.load(sys.stdin)
a = sum(v.get('+',0) for v in d.values())
r = sum(v.get('-',0) for v in d.values())
print(f'TOTAL_ADDED={a}')
print(f'TOTAL_DELETED={r}')
" 2>/dev/null)" || true
fi

# Human-readable summary to stderr
STATUS_LABEL="success"
[ "$EXIT_REASON" = "timeout" ] && STATUS_LABEL="timeout"
[ "$EXIT_REASON" = "codex_error" ] && STATUS_LABEL="failed"

COMMIT_DISPLAY="$COMMIT_HASH"
[ -n "$MERGE_COMMIT" ] && COMMIT_DISPLAY="$COMMIT_HASH (merged as $MERGE_COMMIT)"
[ -z "$COMMIT_HASH" ] && COMMIT_DISPLAY="none"

cat >&2 <<SUMMARY

===================================================================
 GSD Codex Task Complete
===================================================================
  Task:        $TASK_ID: $TASK_NAME
  Status:      $STATUS_LABEL
  Duration:    ${DURATION}s
  Files:       $NUM_FILES changed (+$TOTAL_ADDED, -$TOTAL_DELETED)
  Commit:      $COMMIT_DISPLAY
===================================================================
SUMMARY

exit "$FINAL_EXIT"
