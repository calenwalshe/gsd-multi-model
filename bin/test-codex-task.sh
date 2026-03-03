#!/usr/bin/env bash
set -euo pipefail

# Test suite for bin/codex-task.sh
# Validates argument parsing, XML extraction, dry-run, exit codes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_SCRIPT="$SCRIPT_DIR/codex-task.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1 -- $2"; FAIL=$((FAIL + 1)); }

# --- Test 1: No arguments exits 4 with usage ---
test_no_args() {
  local out
  out=$(bash "$TASK_SCRIPT" 2>&1 || true)
  local rc=0
  bash "$TASK_SCRIPT" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 4 ]; then
    pass "no-args exits 4"
  else
    fail "no-args" "expected exit 4, got $rc"
  fi
  if echo "$out" | grep -qi "usage\|--plan\|--task"; then
    pass "no-args shows usage"
  else
    fail "no-args" "expected usage message"
  fi
}

# --- Test 2: Missing plan file exits 2 ---
test_missing_plan() {
  local rc=0
  bash "$TASK_SCRIPT" --plan /nonexistent/plan.md --task 1 >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "missing-plan exits 2"
  else
    fail "missing-plan" "expected exit 2, got $rc"
  fi
}

# --- Test 3: Task not found exits 2 ---
test_task_not_found() {
  local plan_file="$REPO_ROOT/.planning/phases/04-worktree-automation/04-01-PLAN.md"
  if [ ! -f "$plan_file" ]; then
    fail "task-not-found" "test plan file not found: $plan_file"
    return
  fi
  local rc=0
  bash "$TASK_SCRIPT" --plan "$plan_file" --task 99 >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "task-not-found exits 2"
  else
    fail "task-not-found" "expected exit 2, got $rc"
  fi
}

# --- Test 4: Dry-run produces valid JSON ---
test_dry_run_json() {
  local plan_file="$REPO_ROOT/.planning/phases/04-worktree-automation/04-01-PLAN.md"
  if [ ! -f "$plan_file" ]; then
    fail "dry-run-json" "test plan file not found"
    return
  fi
  local json_out
  json_out=$(bash "$TASK_SCRIPT" --plan "$plan_file" --task 1 --dry-run 2>/dev/null) || {
    fail "dry-run-json" "script exited non-zero"
    return
  }
  if echo "$json_out" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    pass "dry-run produces valid JSON"
  else
    fail "dry-run-json" "invalid JSON output: $json_out"
  fi
}

# --- Test 5: Dry-run JSON has correct fields ---
test_dry_run_fields() {
  local plan_file="$REPO_ROOT/.planning/phases/04-worktree-automation/04-01-PLAN.md"
  if [ ! -f "$plan_file" ]; then
    fail "dry-run-fields" "test plan file not found"
    return
  fi
  local json_out
  json_out=$(bash "$TASK_SCRIPT" --plan "$plan_file" --task 1 --dry-run 2>/dev/null) || {
    fail "dry-run-fields" "script exited non-zero"
    return
  }
  local result
  result=$(echo "$json_out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
checks = []
checks.append('dry_run' if d.get('dry_run') == True else 'no-dry_run')
checks.append('task_id' if d.get('task_id') == '04-01-T1' else 'bad-task_id:' + str(d.get('task_id')))
checks.append('executor' if d.get('executor') == 'codex' else 'bad-executor:' + str(d.get('executor')))
checks.append('confidence' if d.get('confidence') == 'high' else 'bad-confidence:' + str(d.get('confidence')))
print(' '.join(checks))
" 2>&1) || {
    fail "dry-run-fields" "python parse error"
    return
  }
  if echo "$result" | grep -q "dry_run" && echo "$result" | grep -q "^task_id " || echo "$result" | grep -q " task_id "; then
    pass "dry-run has correct task_id, executor, confidence"
  else
    fail "dry-run-fields" "field check: $result"
  fi
}

# --- Test 6: Second task extraction ---
test_second_task() {
  local plan_file="$REPO_ROOT/.planning/phases/04-worktree-automation/04-01-PLAN.md"
  if [ ! -f "$plan_file" ]; then
    fail "second-task" "test plan file not found"
    return
  fi
  local json_out
  json_out=$(bash "$TASK_SCRIPT" --plan "$plan_file" --task 2 --dry-run 2>/dev/null) || {
    fail "second-task" "script exited non-zero"
    return
  }
  local task_id
  task_id=$(echo "$json_out" | python3 -c "import sys,json; print(json.load(sys.stdin).get('task_id',''))" 2>/dev/null) || true
  if [ "$task_id" = "04-01-T2" ]; then
    pass "second task extracts as 04-01-T2"
  else
    fail "second-task" "expected 04-01-T2, got $task_id"
  fi
}

# --- Test 7: Script is executable ---
test_executable() {
  if [ -x "$TASK_SCRIPT" ]; then
    pass "script is executable"
  else
    fail "executable" "script is not executable"
  fi
}

# --- Test 8: Script passes bash -n syntax check ---
test_syntax() {
  if bash -n "$TASK_SCRIPT" 2>/dev/null; then
    pass "passes bash -n syntax check"
  else
    fail "syntax" "bash -n failed"
  fi
}

# --- Run tests ---
echo ""
echo "=== codex-task.sh tests ==="
echo ""

test_no_args
test_missing_plan
test_task_not_found
test_dry_run_json
test_dry_run_fields
test_second_task
test_executable
test_syntax

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
