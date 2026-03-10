#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Integration test: bin/demo.sh
#
# Validates dry-run execution, JSON output mode, --keep flag,
# sandbox cleanup, and fixture validation.
#
# All tests run in dry-run mode (default) so no Codex CLI needed.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_SCRIPT="$SCRIPT_DIR/bin/demo.sh"

PASS=0
FAIL=0

ok()  { echo "  ok  $1"; PASS=$((PASS + 1)); }
err() { echo "  err $1 -- $2"; FAIL=$((FAIL + 1)); }

# Temp files for capturing output
STDERR_LOG=""

cleanup() {
  rm -f "$STDERR_LOG" 2>/dev/null || true
  # Clean up any leftover worktree/demo artifacts
  rm -rf /tmp/gsd-worktree-* 2>/dev/null || true
  rm -rf /tmp/gsd-demo-* 2>/dev/null || true
}
trap cleanup EXIT

# Pre-clean artifacts from any previous failed runs
rm -rf /tmp/gsd-worktree-* 2>/dev/null || true
rm -rf /tmp/gsd-demo-* 2>/dev/null || true

STDERR_LOG=$(mktemp /tmp/gsd-test-demo-stderr-XXXXXX)

echo ""
echo "=== bin/demo.sh Integration Tests ==="
echo ""

# -------------------------------------------------------
# Test 1: Fixture validation
# -------------------------------------------------------
test_fixtures() {
  echo "-- Fixture validation --"

  if [ -f "$SCRIPT_DIR/test/fixtures/demo-project/package.json" ]; then
    ok "fixture package.json exists"
  else
    err "fixture-package" "test/fixtures/demo-project/package.json not found"
  fi

  if [ -f "$SCRIPT_DIR/test/fixtures/demo-project/src/utils.js" ]; then
    ok "fixture src/utils.js exists"
  else
    err "fixture-utils" "test/fixtures/demo-project/src/utils.js not found"
  fi

  if [ -f "$SCRIPT_DIR/test/fixtures/demo-project/.planning/phases/01-add-utils/01-01-PLAN.md" ]; then
    ok "fixture PLAN.md exists"
  else
    err "fixture-plan" "test/fixtures/demo-project/.planning/phases/01-add-utils/01-01-PLAN.md not found"
  fi
}

# -------------------------------------------------------
# Test 2: Dry-run full execution
# -------------------------------------------------------
test_dry_run() {
  echo "-- Dry-run full execution --"
  rm -rf /tmp/gsd-worktree-* /tmp/gsd-demo-* 2>/dev/null || true

  local rc=0
  bash "$DEMO_SCRIPT" 2>"$STDERR_LOG" || rc=$?

  if [ "$rc" -eq 0 ]; then
    ok "dry-run exits 0"
  else
    err "dry-run-exit" "expected exit 0, got $rc"
  fi

  if grep -q "GSD End-to-End Demo Complete" "$STDERR_LOG"; then
    ok "summary contains completion message"
  else
    err "dry-run-summary" "stderr missing 'GSD End-to-End Demo Complete'"
  fi
}

# -------------------------------------------------------
# Test 3: JSON output mode
# -------------------------------------------------------
JSON_OUT=""

test_json_output() {
  echo "-- JSON output mode --"
  rm -rf /tmp/gsd-worktree-* /tmp/gsd-demo-* 2>/dev/null || true

  local rc=0
  JSON_OUT=$(bash "$DEMO_SCRIPT" --json 2>/dev/null) || rc=$?

  if [ "$rc" -eq 0 ]; then
    ok "json mode exits 0"
  else
    err "json-exit" "expected exit 0, got $rc"
    return
  fi

  # Validate JSON structure
  local json_ok
  json_ok=$(echo "$JSON_OUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['success'] == True, 'success not True'
assert len(d['stages']) >= 6, f'expected >=6 stages, got {len(d[\"stages\"])}'
print('json ok')
" 2>&1) || json_ok=""

  if [ "$json_ok" = "json ok" ]; then
    ok "JSON has success=true and >=6 stages"
  else
    err "json-structure" "JSON validation failed: $json_ok"
  fi
}

# -------------------------------------------------------
# Test 4: --keep flag preserves sandbox
# -------------------------------------------------------
test_keep_flag() {
  echo "-- --keep flag preserves sandbox --"
  rm -rf /tmp/gsd-worktree-* /tmp/gsd-demo-* 2>/dev/null || true

  local rc=0
  local keep_json
  keep_json=$(bash "$DEMO_SCRIPT" --json --keep 2>/dev/null) || rc=$?

  if [ "$rc" -ne 0 ]; then
    err "keep-exit" "expected exit 0, got $rc"
    return
  fi

  local sandbox_path
  sandbox_path=$(echo "$keep_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['sandbox'])" 2>/dev/null) || sandbox_path=""

  if [ -z "$sandbox_path" ]; then
    err "keep-sandbox" "could not extract sandbox path from JSON"
    return
  fi

  if [ -d "$sandbox_path" ]; then
    ok "--keep preserves sandbox directory"
    # Clean up sandbox and worktree artifacts
    rm -rf "$sandbox_path"
    rm -rf /tmp/gsd-worktree-* 2>/dev/null || true
  else
    err "keep-preserved" "sandbox directory not found: $sandbox_path"
  fi
}

# -------------------------------------------------------
# Test 5: Default cleanup (no --keep)
# -------------------------------------------------------
test_default_cleanup() {
  echo "-- Default cleanup --"
  rm -rf /tmp/gsd-worktree-* /tmp/gsd-demo-* 2>/dev/null || true

  local rc=0
  local cleanup_json
  cleanup_json=$(bash "$DEMO_SCRIPT" --json 2>/dev/null) || rc=$?

  if [ "$rc" -ne 0 ]; then
    err "cleanup-exit" "expected exit 0, got $rc"
    return
  fi

  local sandbox_path
  sandbox_path=$(echo "$cleanup_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['sandbox'])" 2>/dev/null) || sandbox_path=""

  if [ -z "$sandbox_path" ]; then
    err "cleanup-sandbox" "could not extract sandbox path from JSON"
    return
  fi

  if [ ! -d "$sandbox_path" ]; then
    ok "sandbox cleaned up by default"
  else
    err "cleanup-preserved" "sandbox still exists: $sandbox_path"
    rm -rf "$sandbox_path"
  fi
}

# -------------------------------------------------------
# Test 6: Stage count and status
# -------------------------------------------------------
test_stage_details() {
  echo "-- Stage count and status --"

  if [ -z "$JSON_OUT" ]; then
    err "stage-count" "no JSON output from test 3"
    return
  fi

  local all_pass
  all_pass=$(echo "$JSON_OUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
stages = d['stages']
all_pass = all(s['status'] == 'pass' for s in stages)
print(f'{len(stages)} stages, all_pass={all_pass}')
" 2>/dev/null) || all_pass=""

  local stage_count
  stage_count=$(echo "$all_pass" | grep -oP '^\d+')

  if [ "${stage_count:-0}" -ge 6 ]; then
    ok "at least 6 stages present ($stage_count)"
  else
    err "stage-count" "expected >=6 stages, got: $all_pass"
  fi

  if echo "$all_pass" | grep -q "all_pass=True"; then
    ok "all stages have status pass"
  else
    err "stage-status" "not all stages passed: $all_pass"
  fi
}

# --- Run all tests ---
test_fixtures
test_dry_run
test_json_output
test_keep_flag
test_default_cleanup
test_stage_details

echo ""
echo "======================================================="
echo " Demo Tests: $PASS passed, $FAIL failed"
echo "======================================================="
echo ""

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
