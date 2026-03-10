#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Integration test: codex-task.sh
#
# Validates argument parsing, XML task extraction, dry-run mode,
# executor validation, and confidence routing.
#
# All tests use --dry-run so Codex CLI is NOT required.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_SCRIPT="$SCRIPT_DIR/bin/codex-task.sh"
REPO_ROOT="$SCRIPT_DIR"

PASS=0
FAIL=0

ok()  { echo "  ok  $1"; PASS=$((PASS + 1)); }
err() { echo "  err $1 -- $2"; FAIL=$((FAIL + 1)); }

# Temp directory for test fixtures
TEST_DIR=$(mktemp -d /tmp/gsd-codex-test-XXXXXX)

cleanup() {
  rm -rf "$TEST_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# Reference plan for parsing tests
REF_PLAN="$REPO_ROOT/.planning/phases/04-worktree-automation/04-01-PLAN.md"

echo ""
echo "=== codex-task.sh Integration Tests ==="
echo ""

# -------------------------------------------------------
# Test 1: Pre-flight -- no arguments exits 4
# -------------------------------------------------------
test_no_args() {
  echo "-- Pre-flight: no arguments --"
  local rc=0
  local out
  out=$(bash "$TASK_SCRIPT" 2>&1) || rc=$?
  if [ "$rc" -eq 4 ]; then
    ok "no-args exits 4"
  else
    err "no-args" "expected exit 4, got $rc"
  fi
  if echo "$out" | grep -qi "usage\|--plan\|--task"; then
    ok "no-args shows usage hint"
  else
    err "no-args-usage" "expected usage message in output"
  fi
}

# -------------------------------------------------------
# Test 2: Pre-flight -- nonexistent plan exits 2
# -------------------------------------------------------
test_missing_plan() {
  echo "-- Pre-flight: nonexistent plan --"
  local rc=0
  bash "$TASK_SCRIPT" --plan /tmp/nonexistent-$$.md --task 1 >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 2 ]; then
    ok "missing-plan exits 2"
  else
    err "missing-plan" "expected exit 2, got $rc"
  fi
}

# -------------------------------------------------------
# Test 3: Pre-flight -- nonexistent task number exits 2
# -------------------------------------------------------
test_task_not_found() {
  echo "-- Pre-flight: nonexistent task number --"
  if [ ! -f "$REF_PLAN" ]; then
    err "task-not-found" "reference plan not found: $REF_PLAN"
    return
  fi
  local rc=0
  bash "$TASK_SCRIPT" --plan "$REF_PLAN" --task 99 >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 2 ]; then
    ok "task-not-found exits 2"
  else
    err "task-not-found" "expected exit 2, got $rc"
  fi
}

# -------------------------------------------------------
# Test 4: Dry-run -- basic parsing (task 1)
# -------------------------------------------------------
test_dry_run_task1() {
  echo "-- Dry-run: basic parsing (task 1) --"
  if [ ! -f "$REF_PLAN" ]; then
    err "dry-run-task1" "reference plan not found"
    return
  fi
  local json_out rc=0
  json_out=$(bash "$TASK_SCRIPT" --plan "$REF_PLAN" --task 1 --dry-run 2>/dev/null) || rc=$?
  if [ "$rc" -ne 0 ]; then
    err "dry-run-task1" "script exited $rc"
    return
  fi
  # Validate JSON
  if ! echo "$json_out" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    err "dry-run-task1-json" "invalid JSON output"
    return
  fi
  ok "dry-run produces valid JSON"

  # Check fields
  local task_id executor confidence dry_run
  task_id=$(echo "$json_out" | python3 -c "import sys,json; print(json.load(sys.stdin).get('task_id',''))")
  executor=$(echo "$json_out" | python3 -c "import sys,json; print(json.load(sys.stdin).get('executor',''))")
  confidence=$(echo "$json_out" | python3 -c "import sys,json; print(json.load(sys.stdin).get('confidence',''))")
  dry_run=$(echo "$json_out" | python3 -c "import sys,json; print(json.load(sys.stdin).get('dry_run',False))")

  if [ "$task_id" = "04-01-T1" ]; then
    ok "task_id is 04-01-T1"
  else
    err "task_id" "expected 04-01-T1, got $task_id"
  fi
  if [ "$executor" = "codex" ]; then
    ok "executor is codex"
  else
    err "executor" "expected codex, got $executor"
  fi
  if [ "$confidence" = "high" ]; then
    ok "confidence is high"
  else
    err "confidence" "expected high, got $confidence"
  fi
  if [ "$dry_run" = "True" ]; then
    ok "dry_run is true"
  else
    err "dry_run" "expected True, got $dry_run"
  fi

  # Store for later tests
  DRY_RUN_T1_JSON="$json_out"
}

# -------------------------------------------------------
# Test 5: Dry-run -- task selection (task 2)
# -------------------------------------------------------
test_dry_run_task2() {
  echo "-- Dry-run: task selection (task 2) --"
  if [ ! -f "$REF_PLAN" ]; then
    err "dry-run-task2" "reference plan not found"
    return
  fi
  local json_out rc=0
  json_out=$(bash "$TASK_SCRIPT" --plan "$REF_PLAN" --task 2 --dry-run 2>/dev/null) || rc=$?
  if [ "$rc" -ne 0 ]; then
    err "dry-run-task2" "script exited $rc"
    return
  fi
  local task_id
  task_id=$(echo "$json_out" | python3 -c "import sys,json; print(json.load(sys.stdin).get('task_id',''))")
  if [ "$task_id" = "04-01-T2" ]; then
    ok "second task extracts as 04-01-T2"
  else
    err "dry-run-task2" "expected 04-01-T2, got $task_id"
  fi
}

# -------------------------------------------------------
# Test 6: Dry-run -- multi-line action extraction
# -------------------------------------------------------
test_action_extraction() {
  echo "-- Dry-run: action extraction --"
  if [ -z "${DRY_RUN_T1_JSON:-}" ]; then
    err "action-extraction" "no JSON from task 1 dry-run"
    return
  fi
  local codex_cmd
  codex_cmd=$(echo "$DRY_RUN_T1_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('codex_command',''))")
  if [ -n "$codex_cmd" ]; then
    ok "codex_command is non-empty (action extracted)"
  else
    err "action-extraction" "codex_command is empty"
  fi
}

# -------------------------------------------------------
# Test 7: Executor validation -- claude task without --force exits 4
# -------------------------------------------------------
test_executor_claude_no_force() {
  echo "-- Executor: claude task without --force --"
  local temp_plan="$TEST_DIR/claude-plan.md"
  cat > "$temp_plan" <<'PLAN'
---
phase: test
plan: 01
files_modified: []
---

<tasks>
<task type="auto" executor="claude" confidence="high">
  <name>Task 1: Test task</name>
  <files>test.txt</files>
  <action>Do something</action>
  <done>Done</done>
</task>
</tasks>
PLAN

  local rc=0
  bash "$TASK_SCRIPT" --plan "$temp_plan" --task 1 --dry-run >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 4 ]; then
    ok "claude executor without --force exits 4"
  else
    err "executor-claude" "expected exit 4, got $rc"
  fi
}

# -------------------------------------------------------
# Test 8: Executor validation -- claude task with --force exits 0
# -------------------------------------------------------
test_executor_claude_with_force() {
  echo "-- Executor: claude task with --force --"
  local temp_plan="$TEST_DIR/claude-plan.md"
  # Plan file created in test 7
  local rc=0
  bash "$TASK_SCRIPT" --plan "$temp_plan" --task 1 --dry-run --force >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "claude executor with --force exits 0"
  else
    err "executor-claude-force" "expected exit 0, got $rc"
  fi
}

# -------------------------------------------------------
# Test 9: Confidence routing -- low confidence exits 4
# -------------------------------------------------------
test_confidence_low() {
  echo "-- Confidence: low exits 4 --"
  local temp_plan="$TEST_DIR/low-plan.md"
  cat > "$temp_plan" <<'PLAN'
---
phase: test
plan: 01
files_modified: []
---

<tasks>
<task type="auto" executor="codex" confidence="low">
  <name>Task 1: Low confidence task</name>
  <files>test.txt</files>
  <action>Do something risky</action>
  <done>Done</done>
</task>
</tasks>
PLAN

  local rc=0
  bash "$TASK_SCRIPT" --plan "$temp_plan" --task 1 --dry-run >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 4 ]; then
    ok "low confidence exits 4"
  else
    err "confidence-low" "expected exit 4, got $rc"
  fi
}

# -------------------------------------------------------
# Test 10: Confidence routing -- high vs medium
# -------------------------------------------------------
test_confidence_routing() {
  echo "-- Confidence: high=full-auto, medium=no flag --"

  # High confidence: check from task 1 dry-run
  if [ -n "${DRY_RUN_T1_JSON:-}" ]; then
    local codex_cmd
    codex_cmd=$(echo "$DRY_RUN_T1_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('codex_command',''))")
    if echo "$codex_cmd" | grep -q "\-\-full-auto"; then
      ok "high confidence includes --full-auto"
    else
      err "confidence-high" "expected --full-auto in command: $codex_cmd"
    fi
  else
    err "confidence-high" "no JSON from task 1 dry-run"
  fi

  # Medium confidence
  local temp_plan="$TEST_DIR/medium-plan.md"
  cat > "$temp_plan" <<'PLAN'
---
phase: test
plan: 01
files_modified: []
---

<tasks>
<task type="auto" executor="codex" confidence="medium">
  <name>Task 1: Medium confidence task</name>
  <files>test.txt</files>
  <action>Do something moderately</action>
  <done>Done</done>
</task>
</tasks>
PLAN

  local json_out rc=0
  json_out=$(bash "$TASK_SCRIPT" --plan "$temp_plan" --task 1 --dry-run 2>/dev/null) || rc=$?
  if [ "$rc" -ne 0 ]; then
    err "confidence-medium" "script exited $rc"
    return
  fi
  local med_cmd
  med_cmd=$(echo "$json_out" | python3 -c "import sys,json; print(json.load(sys.stdin).get('codex_command',''))")
  if echo "$med_cmd" | grep -q "\-\-full-auto"; then
    err "confidence-medium" "medium should NOT include --full-auto: $med_cmd"
  else
    ok "medium confidence omits --full-auto"
  fi
}

# --- Run all tests ---
DRY_RUN_T1_JSON=""

test_no_args
test_missing_plan
test_task_not_found
test_dry_run_task1
test_dry_run_task2
test_action_extraction
test_executor_claude_no_force
test_executor_claude_with_force
test_confidence_low
test_confidence_routing

echo ""
echo "======================================================="
echo " Codex Task Tests: $PASS passed, $FAIL failed"
echo "======================================================="
echo ""

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
