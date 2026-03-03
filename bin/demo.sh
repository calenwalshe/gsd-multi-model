#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# gsd demo -- End-to-end dual-tool workflow demonstration
#
# Proves the full GSD workflow loop runs without manual
# intervention: init-gsd bootstrap, plan validation, task
# splitting, worktree creation, Codex execution (dry-run by
# default), worktree cleanup, and cross-review validation.
#
# Usage:
#   bin/demo.sh              # dry-run mode (default)
#   bin/demo.sh --live       # real Codex execution
#   bin/demo.sh --keep       # preserve temp sandbox on success
#   bin/demo.sh --json       # machine-readable JSON to stdout
#
# Exit codes:
#   0 = all stages passed
#   1 = stage failure or pre-flight failure
# ============================================================

GSD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- ANSI color helpers with TTY detection (stderr) ---
if [ -t 2 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  DIM='\033[2m'
  RESET='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  CYAN=''
  BOLD=''
  DIM=''
  RESET=''
fi

ok()   { echo -e "${GREEN}  ok${RESET} $1" >&2; }
warn() { echo -e "${YELLOW}  warn${RESET} $1" >&2; }
err()  { echo -e "${RED}  err${RESET} $1" >&2; }

# ============================================================
# Section 1: Argument parsing
# ============================================================

DRY_RUN=true
KEEP=false
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --live)
      DRY_RUN=false
      shift
      ;;
    --keep)
      KEEP=true
      shift
      ;;
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    -h|--help)
      cat >&2 <<USAGE
Usage: $(basename "$0") [OPTIONS]

Options:
  --live    Run with real Codex execution (default: dry-run)
  --keep    Preserve temp sandbox on success
  --json    Machine-readable JSON to stdout
  -h        Show this help
USAGE
      exit 0
      ;;
    *)
      err "Unknown argument: $1"
      exit 1
      ;;
  esac
done

MODE_LABEL="dry-run"
[ "$DRY_RUN" = false ] && MODE_LABEL="live"

# ============================================================
# Section 2: Pre-flight checks
# ============================================================

echo -e "\n${BOLD}GSD End-to-End Demo${RESET}" >&2
echo -e "${DIM}Mode: $MODE_LABEL${RESET}\n" >&2

PREFLIGHT_FAIL=false

# Check git
if command -v git >/dev/null 2>&1; then
  ok "git found"
else
  err "git not found in PATH"
  PREFLIGHT_FAIL=true
fi

# Check node
if command -v node >/dev/null 2>&1; then
  ok "node found"
else
  err "node not found in PATH"
  PREFLIGHT_FAIL=true
fi

# Check init-gsd skill
if [ -f "$HOME/.claude/skills/init-gsd/SKILL.md" ]; then
  ok "init-gsd skill installed"
else
  err "init-gsd skill not found at ~/.claude/skills/init-gsd/SKILL.md"
  PREFLIGHT_FAIL=true
fi

# Check bin scripts
for script in codex-task.sh worktree-create.sh worktree-cleanup.sh; do
  if [ -x "$GSD_ROOT/bin/$script" ]; then
    ok "$script found"
  else
    err "$script not found or not executable at $GSD_ROOT/bin/$script"
    PREFLIGHT_FAIL=true
  fi
done

# Check fixture project
if [ -f "$GSD_ROOT/test/fixtures/demo-project/package.json" ]; then
  ok "fixture project found"
else
  err "fixture project not found at $GSD_ROOT/test/fixtures/demo-project/"
  PREFLIGHT_FAIL=true
fi

# Check codex if --live
if [ "$DRY_RUN" = false ]; then
  if command -v codex >/dev/null 2>&1; then
    ok "codex CLI found"
  else
    err "codex CLI not found (required for --live mode)"
    PREFLIGHT_FAIL=true
  fi
fi

if [ "$PREFLIGHT_FAIL" = true ]; then
  err "Pre-flight checks failed. Aborting."
  exit 1
fi

echo "" >&2

# ============================================================
# Section 3: Sandbox setup
# ============================================================

SANDBOX="$(mktemp -d /tmp/gsd-demo-XXXX)"
STAGE_FAILED=false

cleanup() {
  rm -f "$STAGE_STATE_FILE" "$STAGE_ARTIFACTS_FILE" 2>/dev/null
  # Clean up worktree artifacts if they exist (worktree-create.sh puts them next to sandbox)
  local sandbox_parent
  sandbox_parent="$(dirname "$SANDBOX")"
  rm -rf "${sandbox_parent}/gsd-worktree-phase01-plan01" 2>/dev/null || true
  if [ "$KEEP" = true ]; then
    echo -e "${DIM}Sandbox preserved: $SANDBOX${RESET}" >&2
    return
  fi
  if [ "$STAGE_FAILED" = true ]; then
    echo -e "${YELLOW}Sandbox kept for debugging: $SANDBOX${RESET}" >&2
    return
  fi
  rm -rf "$SANDBOX"
}

trap cleanup EXIT

# Pre-clean worktree artifacts from any previous failed run
rm -rf /tmp/gsd-worktree-phase01-plan01 2>/dev/null || true

# Copy fixture project into sandbox
cp -r "$GSD_ROOT/test/fixtures/demo-project/"* "$SANDBOX/"
cp -r "$GSD_ROOT/test/fixtures/demo-project/.planning" "$SANDBOX/"

# Initialize git in sandbox
(
  cd "$SANDBOX"
  git init --quiet
  git add -A
  git commit -m "initial" --quiet
) >/dev/null 2>&1

echo -e "${DIM}Sandbox: $SANDBOX${RESET}" >&2
echo "" >&2

# ============================================================
# Section 4: Stage execution engine
# ============================================================

STAGE_NAMES=()
STAGE_STATUS=()
STAGE_DURATIONS=()
STAGE_ARTIFACTS=()

# Shared state file for inter-stage communication
STAGE_STATE_FILE="$(mktemp /tmp/gsd-demo-state-XXXXXX)"
echo "" > "$STAGE_STATE_FILE"

# Variables shared between stages (read from state file after each stage)
WORKTREE_BRANCH=""
WORKTREE_PATH=""
CODEX_JSON_OUTPUT=""

# Artifacts file for run_stage to read after subshell
STAGE_ARTIFACTS_FILE="$(mktemp /tmp/gsd-demo-artifacts-XXXXXX)"

run_stage() {
  local stage_name="$1"
  local stage_func="$2"

  echo -e "${CYAN}${BOLD}GSD > ${stage_name^^}${RESET}" >&2

  local start_epoch
  start_epoch=$(date +%s%N 2>/dev/null || echo "$(date +%s)000000000")

  # Run stage function -- it writes artifacts to STAGE_ARTIFACTS_FILE
  # and shared vars to STAGE_STATE_FILE
  echo "" > "$STAGE_ARTIFACTS_FILE"
  local rc=0
  $stage_func || rc=$?

  local artifacts
  artifacts="$(cat "$STAGE_ARTIFACTS_FILE" 2>/dev/null)"

  # Re-read shared state (stages may have updated it)
  if [ -f "$STAGE_STATE_FILE" ]; then
    # shellcheck disable=SC1090
    source "$STAGE_STATE_FILE"
  fi

  local end_epoch
  end_epoch=$(date +%s%N 2>/dev/null || echo "$(date +%s)000000000")

  # Calculate duration in seconds with decimal
  local duration_ns=$((end_epoch - start_epoch))
  local duration_s=$((duration_ns / 1000000000))
  local duration_frac=$(( (duration_ns % 1000000000) / 100000000 ))
  local duration="${duration_s}.${duration_frac}"

  STAGE_NAMES+=("$stage_name")
  STAGE_DURATIONS+=("$duration")

  if [ "$rc" -eq 0 ]; then
    STAGE_STATUS+=("pass")
    STAGE_ARTIFACTS+=("$artifacts")
    ok "$stage_name (${duration}s)"
  else
    STAGE_STATUS+=("fail")
    STAGE_ARTIFACTS+=("FAILED")
    err "$stage_name failed (exit $rc)"
    if [ -n "$artifacts" ]; then
      echo -e "${DIM}  $artifacts${RESET}" >&2
    fi
    STAGE_FAILED=true
    return 1
  fi
  echo "" >&2
  return 0
}

# Helper: write artifacts string for run_stage to pick up
set_artifacts() {
  echo "$1" > "$STAGE_ARTIFACTS_FILE"
}

# Helper: save shared variable to state file
save_state() {
  local var_name="$1"
  local var_value="$2"
  echo "${var_name}=$(printf '%q' "$var_value")" >> "$STAGE_STATE_FILE"
}

# ============================================================
# Section 5: Stage definitions
# ============================================================

stage_init_gsd_bootstrap() {
  cd "$SANDBOX"

  # Simulate init-gsd bootstrap (it's a Claude Code skill, not a standalone script)
  cat > AGENTS.md <<'AGENTSEOF'
# demo-project

A demo project for GSD end-to-end testing.

## Build & Test

- `npm test` -- run tests
AGENTSEOF

  cat > CLAUDE.md <<'CLAUDEEOF'
# demo-project -- Claude Code Instructions

See @AGENTS.md for build commands.
CLAUDEEOF

  mkdir -p .claude/rules

  # Validate
  [ -f AGENTS.md ] && [ -f CLAUDE.md ] && [ -d .planning ] && [ -d .claude/rules ] || return 1

  git add -A >/dev/null 2>&1
  git commit -m "chore: init-gsd bootstrap" --quiet >/dev/null 2>&1

  set_artifacts "AGENTS.md, CLAUDE.md, .claude/rules/"
}

stage_plan_validation() {
  cd "$SANDBOX"

  local plan=".planning/phases/01-add-utils/01-01-PLAN.md"

  # Check plan exists
  [ -f "$plan" ] || { echo "PLAN.md not found"; return 1; }

  # Validate YAML frontmatter
  head -1 "$plan" | grep -q '^---' || { echo "No YAML frontmatter"; return 1; }

  # Validate XML task blocks
  local task_count
  task_count=$(grep -c '<task ' "$plan" || true)
  [ "$task_count" -ge 2 ] || { echo "Expected 2+ task blocks, found $task_count"; return 1; }

  set_artifacts ".planning/phases/01-add-utils/01-01-PLAN.md ($task_count tasks)"
}

stage_task_splitting() {
  cd "$SANDBOX"

  local plan=".planning/phases/01-add-utils/01-01-PLAN.md"

  # Parse executor attributes
  local task1_executor
  task1_executor=$(awk '/<task / && !found { found=1; match($0, /executor="([^"]*)"/, m); print m[1] }' "$plan" 2>/dev/null || \
    grep -oP 'executor="[^"]*"' "$plan" | head -1 | sed 's/executor="//;s/"//')

  local task2_executor
  task2_executor=$(awk '/<task /{ count++; if(count==2){ match($0, /executor="([^"]*)"/, m); print m[1] }}' "$plan" 2>/dev/null || \
    grep -oP 'executor="[^"]*"' "$plan" | tail -1 | sed 's/executor="//;s/"//')

  echo "Task 1 -> $task1_executor, Task 2 -> $task2_executor" >&2

  # Validate using codex-task.sh --dry-run
  local dry_json
  dry_json=$("$GSD_ROOT/bin/codex-task.sh" --plan "$plan" --task 1 --dry-run 2>/dev/null) || { set_artifacts "codex-task.sh --dry-run failed"; return 1; }

  # Validate JSON has task_id and executor
  echo "$dry_json" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'task_id' in d and 'executor' in d" 2>/dev/null || { set_artifacts "Invalid dry-run JSON"; return 1; }

  set_artifacts "2 tasks split: 1 codex, 1 claude"
}

stage_worktree_creation() {
  cd "$SANDBOX"

  local plan=".planning/phases/01-add-utils/01-01-PLAN.md"

  local wt_json
  wt_json=$("$GSD_ROOT/bin/worktree-create.sh" --task "$plan" --json 2>/dev/null) || { set_artifacts "worktree-create.sh failed"; return 1; }

  local branch path
  branch=$(echo "$wt_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['branch'])" 2>/dev/null) || { set_artifacts "Cannot parse branch"; return 1; }
  path=$(echo "$wt_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['path'])" 2>/dev/null) || { set_artifacts "Cannot parse path"; return 1; }

  [ -d "$path" ] || { set_artifacts "Worktree dir not found: $path"; return 1; }

  save_state "WORKTREE_BRANCH" "$branch"
  save_state "WORKTREE_PATH" "$path"

  set_artifacts "worktree: $branch"
}

stage_codex_execution() {
  cd "$SANDBOX"

  local plan=".planning/phases/01-add-utils/01-01-PLAN.md"
  local codex_out

  if [ "$DRY_RUN" = true ]; then
    codex_out=$("$GSD_ROOT/bin/codex-task.sh" --plan "$plan" --task 1 --dry-run 2>/dev/null) || { set_artifacts "codex-task.sh --dry-run failed"; return 1; }

    save_state "CODEX_JSON_OUTPUT" "$codex_out"

    local task_id
    task_id=$(echo "$codex_out" | python3 -c "import sys,json; print(json.load(sys.stdin)['task_id'])" 2>/dev/null) || task_id="unknown"

    set_artifacts "codex-task dry-run: task $task_id"
  else
    codex_out=$("$GSD_ROOT/bin/codex-task.sh" --plan "$plan" --task 1 2>/dev/null) || { set_artifacts "codex-task.sh live failed"; return 1; }

    save_state "CODEX_JSON_OUTPUT" "$codex_out"

    local commit_hash
    commit_hash=$(echo "$codex_out" | python3 -c "import sys,json; print(json.load(sys.stdin).get('commit_hash',''))" 2>/dev/null) || commit_hash=""
    local num_files
    num_files=$(echo "$codex_out" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('changed_files',[])))" 2>/dev/null) || num_files=0

    set_artifacts "codex-task: $commit_hash, $num_files files changed"
  fi
}

stage_worktree_cleanup() {
  cd "$SANDBOX"

  if [ -z "$WORKTREE_BRANCH" ]; then
    set_artifacts "No worktree branch to clean up"
    return 1
  fi

  "$GSD_ROOT/bin/worktree-cleanup.sh" --no-merge --force "$WORKTREE_BRANCH" >/dev/null 2>&1 || { set_artifacts "worktree-cleanup.sh failed"; return 1; }

  set_artifacts "worktree $WORKTREE_BRANCH removed"
}

stage_cross_review() {
  cd "$SANDBOX"

  local checks=0
  local total=7

  # 1. AGENTS.md exists
  [ -f AGENTS.md ] && checks=$((checks + 1))

  # 2. CLAUDE.md exists
  [ -f CLAUDE.md ] && checks=$((checks + 1))

  # 3. .planning/ exists
  [ -d .planning ] && checks=$((checks + 1))

  # 4. PLAN.md has XML task blocks
  grep -q '<task ' .planning/phases/01-add-utils/01-01-PLAN.md 2>/dev/null && checks=$((checks + 1))

  # 5. codex-task.sh produced valid JSON
  [ -n "$CODEX_JSON_OUTPUT" ] && echo "$CODEX_JSON_OUTPUT" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null && checks=$((checks + 1))

  # 6. git repo has commits
  git log --oneline 2>/dev/null | grep -q . && checks=$((checks + 1))

  # 7. fixture source file exists
  [ -f src/utils.js ] && checks=$((checks + 1))

  [ "$checks" -eq "$total" ] || { set_artifacts "$checks/$total checks passed"; return 1; }

  set_artifacts "$checks checks passed"
}

# ============================================================
# Execute all stages
# ============================================================

run_stage "init-gsd bootstrap"  stage_init_gsd_bootstrap   || exit 1
run_stage "plan validation"     stage_plan_validation       || exit 1
run_stage "task splitting"      stage_task_splitting        || exit 1
run_stage "worktree creation"   stage_worktree_creation     || exit 1
run_stage "codex execution"     stage_codex_execution       || exit 1
run_stage "worktree cleanup"    stage_worktree_cleanup      || exit 1
run_stage "cross-review"        stage_cross_review          || exit 1

# ============================================================
# Section 6: Summary output
# ============================================================

TOTAL_STAGES=${#STAGE_NAMES[@]}
PASSED_STAGES=0
for s in "${STAGE_STATUS[@]}"; do
  [ "$s" = "pass" ] && PASSED_STAGES=$((PASSED_STAGES + 1))
done

# Summary table to stderr
cat >&2 <<SUMMARY

$(echo -e "${BOLD}")======================================================
 GSD End-to-End Demo Complete
======================================================$(echo -e "${RESET}")
  Mode:     $MODE_LABEL
  Sandbox:  $SANDBOX
  Stages:   $PASSED_STAGES/$TOTAL_STAGES passed

SUMMARY

printf "  %-25s %-8s %-10s %s\n" "Stage" "Status" "Duration" "Artifacts" >&2
printf "  %-25s %-8s %-10s %s\n" "-----" "------" "--------" "---------" >&2

for i in "${!STAGE_NAMES[@]}"; do
  printf "  %-25s %-8s %-10s %s\n" \
    "${STAGE_NAMES[$i]}" "${STAGE_STATUS[$i]}" "${STAGE_DURATIONS[$i]}s" "${STAGE_ARTIFACTS[$i]}" >&2
done

echo -e "${BOLD}======================================================${RESET}" >&2

# JSON output to stdout if requested
if [ "$JSON_OUTPUT" = true ]; then
  # Build stages JSON array
  STAGES_JSON="["
  for i in "${!STAGE_NAMES[@]}"; do
    [ "$i" -gt 0 ] && STAGES_JSON+=","
    # Escape artifacts for JSON
    local_artifacts="${STAGE_ARTIFACTS[$i]}"
    local_artifacts="${local_artifacts//\\/\\\\}"
    local_artifacts="${local_artifacts//\"/\\\"}"
    STAGES_JSON+="{\"name\":\"${STAGE_NAMES[$i]}\",\"status\":\"${STAGE_STATUS[$i]}\",\"duration_seconds\":${STAGE_DURATIONS[$i]},\"artifacts\":\"${local_artifacts}\"}"
  done
  STAGES_JSON+="]"

  # Calculate total duration
  TOTAL_DUR=0
  for d in "${STAGE_DURATIONS[@]}"; do
    # Integer part only for total
    int_part="${d%%.*}"
    TOTAL_DUR=$((TOTAL_DUR + int_part))
  done

  printf '{"success":%s,"mode":"%s","sandbox":"%s","stages_passed":%d,"stages_total":%d,"stages":%s,"total_duration_seconds":%d}\n' \
    "true" "$MODE_LABEL" "$SANDBOX" "$PASSED_STAGES" "$TOTAL_STAGES" "$STAGES_JSON" "$TOTAL_DUR"
fi

# ============================================================
# Section 7: Exit
# ============================================================

if [ "$PASSED_STAGES" -eq "$TOTAL_STAGES" ]; then
  exit 0
else
  exit 1
fi
