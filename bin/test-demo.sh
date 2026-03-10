#!/usr/bin/env bash
set -euo pipefail

# Test suite for bin/demo.sh
# Validates pre-flight, sandbox, stages, summary output

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_SCRIPT="$SCRIPT_DIR/demo.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1 -- $2"; FAIL=$((FAIL + 1)); }

# --- Test 1: Script exists and is executable ---
test_exists() {
  if [ -f "$DEMO_SCRIPT" ]; then
    pass "demo.sh exists"
  else
    fail "exists" "bin/demo.sh not found"
    return
  fi
  if [ -x "$DEMO_SCRIPT" ]; then
    pass "demo.sh is executable"
  else
    fail "executable" "bin/demo.sh not executable"
  fi
}

# --- Test 2: Passes bash syntax check ---
test_syntax() {
  if bash -n "$DEMO_SCRIPT" 2>/dev/null; then
    pass "syntax check"
  else
    fail "syntax" "bash -n failed"
  fi
}

# --- Test 3: Dry-run completes all 7 stages with exit 0 ---
test_dry_run() {
  local rc=0
  local out
  out=$(bash "$DEMO_SCRIPT" 2>&1) || rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "dry-run exits 0"
  else
    fail "dry-run" "expected exit 0, got $rc"
    echo "    Output (last 20 lines):" >&2
    echo "$out" | tail -20 >&2
    return
  fi
  # Check all 7 stages appear
  if echo "$out" | grep -qi "init-gsd bootstrap"; then
    pass "stage 1 (init-gsd bootstrap) ran"
  else
    fail "stage-1" "init-gsd bootstrap not found in output"
  fi
  if echo "$out" | grep -qi "plan validation"; then
    pass "stage 2 (plan validation) ran"
  else
    fail "stage-2" "plan validation not found in output"
  fi
  if echo "$out" | grep -qi "task splitting"; then
    pass "stage 3 (task splitting) ran"
  else
    fail "stage-3" "task splitting not found in output"
  fi
  if echo "$out" | grep -qi "worktree creation"; then
    pass "stage 4 (worktree creation) ran"
  else
    fail "stage-4" "worktree creation not found in output"
  fi
  if echo "$out" | grep -qi "codex execution"; then
    pass "stage 5 (codex execution) ran"
  else
    fail "stage-5" "codex execution not found in output"
  fi
  if echo "$out" | grep -qi "worktree cleanup"; then
    pass "stage 6 (worktree cleanup) ran"
  else
    fail "stage-6" "worktree cleanup not found in output"
  fi
  if echo "$out" | grep -qi "cross-review"; then
    pass "stage 7 (cross-review) ran"
  else
    fail "stage-7" "cross-review not found in output"
  fi
}

# --- Test 4: Summary table shows pass for all stages ---
test_summary() {
  local out
  out=$(bash "$DEMO_SCRIPT" 2>&1) || true
  if echo "$out" | grep -q "7/7 passed"; then
    pass "summary shows 7/7 passed"
  else
    fail "summary" "expected '7/7 passed' in output"
  fi
}

# --- Test 5: --keep flag preserves temp dir ---
test_keep() {
  local out
  out=$(bash "$DEMO_SCRIPT" --keep 2>&1) || true
  local sandbox_path
  sandbox_path=$(echo "$out" | grep -oP '/tmp/gsd-demo-\S+' | head -1)
  if [ -n "$sandbox_path" ] && [ -d "$sandbox_path" ]; then
    pass "--keep preserves sandbox"
    rm -rf "$sandbox_path"
  else
    fail "--keep" "sandbox not preserved at $sandbox_path"
  fi
}

# --- Test 6: --json outputs valid JSON to stdout ---
test_json() {
  local json_out
  json_out=$(bash "$DEMO_SCRIPT" --json 2>/dev/null) || true
  if echo "$json_out" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['success']==True" 2>/dev/null; then
    pass "--json produces valid JSON with success=true"
  else
    fail "--json" "invalid JSON output or success not true"
  fi
}

# --- Test 7: Sandbox is cleaned up on success ---
test_cleanup() {
  local out
  out=$(bash "$DEMO_SCRIPT" 2>&1) || true
  local sandbox_path
  sandbox_path=$(echo "$out" | grep -oP '/tmp/gsd-demo-\S+' | head -1)
  if [ -n "$sandbox_path" ] && [ ! -d "$sandbox_path" ]; then
    pass "sandbox cleaned up on success"
  else
    fail "cleanup" "sandbox still exists: $sandbox_path"
  fi
}

# --- Run all tests ---
echo "=== bin/demo.sh test suite ==="
test_exists
test_syntax
test_dry_run
test_summary
test_keep
test_json
test_cleanup

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
