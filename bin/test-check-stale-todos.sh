#!/usr/bin/env bash
set -euo pipefail

# =============================================================
# test-check-stale-todos.sh -- Tests for check-stale-todos.sh
#
# Covers: ENTR-03 (stale TODO/FIXME detection with age tracking)
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_SCRIPT="$SCRIPT_DIR/check-stale-todos.sh"
PASS=0
FAIL=0
TMPDIR_ROOT=""

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1 -- $2"; FAIL=$((FAIL + 1)); }

cleanup() {
  if [ -n "$TMPDIR_ROOT" ] && [ -d "$TMPDIR_ROOT" ]; then
    rm -rf "$TMPDIR_ROOT"
  fi
}
trap cleanup EXIT

TMPDIR_ROOT=$(mktemp -d "/tmp/test-check-stale-todos-XXXXXX")

# Helper: create a minimal fixture project with git repo
make_fixture() {
  local name="$1"
  FIXTURE_DIR="$TMPDIR_ROOT/$name"
  mkdir -p "$FIXTURE_DIR/bin" "$FIXTURE_DIR/.planning"
  cd "$FIXTURE_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "init" > init.txt
  git add -A && git commit -q -m "init"
}

# =============================================================
# Test 1: Finds TODO comments
# =============================================================
test_finds_todos() {
  make_fixture "finds-todos"
  echo '#!/bin/bash
# TODO: fix this logic' > "$FIXTURE_DIR/src.sh"
  git add -A && git commit -q -m "add todo"

  local output="" exit_code=0
  output=$(bash "$CHECK_SCRIPT" --project-root "$FIXTURE_DIR" 2>/dev/null) || exit_code=$?

  if echo "$output" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const f=d.findings;
    process.exit(f && f.length > 0 && f[0].text.includes('TODO') ? 0 : 1);
  " 2>/dev/null; then
    pass "test_finds_todos"
  else
    fail "test_finds_todos" "output=$output"
  fi
}

# =============================================================
# Test 2: Finds FIXME comments
# =============================================================
test_finds_fixme() {
  make_fixture "finds-fixme"
  echo '#!/bin/bash
# FIXME: broken thing' > "$FIXTURE_DIR/fix.sh"
  git add -A && git commit -q -m "add fixme"

  local output="" exit_code=0
  output=$(bash "$CHECK_SCRIPT" --project-root "$FIXTURE_DIR" 2>/dev/null) || exit_code=$?

  if echo "$output" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const f=d.findings;
    process.exit(f && f.length > 0 && f[0].text.includes('FIXME') ? 0 : 1);
  " 2>/dev/null; then
    pass "test_finds_fixme"
  else
    fail "test_finds_fixme" "output=$output"
  fi
}

# =============================================================
# Test 3: Age computed from git blame (backdated commit)
# =============================================================
test_age_from_blame() {
  make_fixture "age-tracking"
  PAST_DATE="2026-01-01T00:00:00Z"
  echo '#!/bin/bash
# TODO: old item' > "$FIXTURE_DIR/old.sh"
  git add -A
  GIT_AUTHOR_DATE="$PAST_DATE" GIT_COMMITTER_DATE="$PAST_DATE" git commit -q -m "old commit"

  local output="" exit_code=0
  output=$(bash "$CHECK_SCRIPT" --project-root "$FIXTURE_DIR" 2>/dev/null) || exit_code=$?

  # Jan 1 to Mar 11 is ~69 days; check age > 60
  if echo "$output" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const f=d.findings;
    process.exit(f && f.length > 0 && f[0].age_days > 60 ? 0 : 1);
  " 2>/dev/null; then
    pass "test_age_from_blame"
  else
    fail "test_age_from_blame" "output=$output"
  fi
}

# =============================================================
# Test 4: Untracked files use current date (age_days = 0)
# =============================================================
test_untracked_age_zero() {
  make_fixture "untracked"
  echo '#!/bin/bash
# TODO: new item' > "$FIXTURE_DIR/untracked.sh"
  # Don't git add

  local output="" exit_code=0
  output=$(bash "$CHECK_SCRIPT" --project-root "$FIXTURE_DIR" 2>/dev/null) || exit_code=$?

  if echo "$output" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const f=d.findings;
    process.exit(f && f.length > 0 && f[0].age_days === 0 ? 0 : 1);
  " 2>/dev/null; then
    pass "test_untracked_age_zero"
  else
    fail "test_untracked_age_zero" "output=$output"
  fi
}

# =============================================================
# Test 5: Severity "warning" when age >= warn_after_days (30)
# =============================================================
test_severity_warning() {
  make_fixture "severity-warning"
  # 45 days ago
  PAST_DATE=$(date -u -d "45 days ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -v-45d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
  echo '#!/bin/bash
# TODO: medium age' > "$FIXTURE_DIR/medium.sh"
  git add -A
  GIT_AUTHOR_DATE="$PAST_DATE" GIT_COMMITTER_DATE="$PAST_DATE" git commit -q -m "medium commit"

  local output="" exit_code=0
  output=$(bash "$CHECK_SCRIPT" --project-root "$FIXTURE_DIR" 2>/dev/null) || exit_code=$?

  if echo "$output" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const f=d.findings;
    process.exit(f && f.length > 0 && f[0].severity === 'warning' ? 0 : 1);
  " 2>/dev/null; then
    pass "test_severity_warning"
  else
    fail "test_severity_warning" "output=$output"
  fi
}

# =============================================================
# Test 6: Severity "critical" when age >= critical_after_days (90)
# =============================================================
test_severity_critical() {
  make_fixture "severity-critical"
  # 100 days ago
  PAST_DATE=$(date -u -d "100 days ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -v-100d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
  echo '#!/bin/bash
# TODO: ancient item' > "$FIXTURE_DIR/ancient.sh"
  git add -A
  GIT_AUTHOR_DATE="$PAST_DATE" GIT_COMMITTER_DATE="$PAST_DATE" git commit -q -m "ancient commit"

  local output="" exit_code=0
  output=$(bash "$CHECK_SCRIPT" --project-root "$FIXTURE_DIR" 2>/dev/null) || exit_code=$?

  if echo "$output" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const f=d.findings;
    process.exit(f && f.length > 0 && f[0].severity === 'critical' ? 0 : 1);
  " 2>/dev/null; then
    pass "test_severity_critical"
  else
    fail "test_severity_critical" "output=$output"
  fi
}

# =============================================================
# Test 7: Severity "info" when age < warn_after_days
# =============================================================
test_severity_info() {
  make_fixture "severity-info"
  # Recent commit (today)
  echo '#!/bin/bash
# TODO: recent item' > "$FIXTURE_DIR/recent.sh"
  git add -A && git commit -q -m "recent commit"

  local output="" exit_code=0
  output=$(bash "$CHECK_SCRIPT" --project-root "$FIXTURE_DIR" 2>/dev/null) || exit_code=$?

  if echo "$output" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const f=d.findings;
    process.exit(f && f.length > 0 && f[0].severity === 'info' ? 0 : 1);
  " 2>/dev/null; then
    pass "test_severity_info"
  else
    fail "test_severity_info" "output=$output"
  fi
}

# =============================================================
# Test 8: Output is valid JSON with required fields
# =============================================================
test_valid_json_output() {
  make_fixture "json-output"
  echo '#!/bin/bash
# TODO: something' > "$FIXTURE_DIR/code.sh"
  git add -A && git commit -q -m "add code"

  local output="" exit_code=0
  output=$(bash "$CHECK_SCRIPT" --project-root "$FIXTURE_DIR" 2>/dev/null) || exit_code=$?

  if echo "$output" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    if (typeof d.passed !== 'boolean') process.exit(1);
    if (!Array.isArray(d.findings)) process.exit(1);
    if (!d.thresholds || typeof d.thresholds.warn_after_days !== 'number' || typeof d.thresholds.critical_after_days !== 'number') process.exit(1);
    process.exit(0);
  " 2>/dev/null; then
    pass "test_valid_json_output"
  else
    fail "test_valid_json_output" "output=$output"
  fi
}

# =============================================================
# Test 9: Passed is true when no TODOs, false when any exist
# =============================================================
test_passed_flag() {
  # Test with TODOs -> passed = false
  make_fixture "passed-false"
  echo '#!/bin/bash
# TODO: exists' > "$FIXTURE_DIR/has-todo.sh"
  git add -A && git commit -q -m "add todo"

  local output="" exit_code=0
  output=$(bash "$CHECK_SCRIPT" --project-root "$FIXTURE_DIR" 2>/dev/null) || exit_code=$?

  local has_todos_ok="false"
  if echo "$output" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    process.exit(d.passed === false ? 0 : 1);
  " 2>/dev/null; then
    has_todos_ok="true"
  fi

  # Test without TODOs -> passed = true
  make_fixture "passed-true"
  echo '#!/bin/bash
echo "clean code"' > "$FIXTURE_DIR/clean.sh"
  git add -A && git commit -q -m "add clean"

  output=$(bash "$CHECK_SCRIPT" --project-root "$FIXTURE_DIR" 2>/dev/null) || exit_code=$?

  local no_todos_ok="false"
  if echo "$output" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    process.exit(d.passed === true ? 0 : 1);
  " 2>/dev/null; then
    no_todos_ok="true"
  fi

  if [ "$has_todos_ok" = "true" ] && [ "$no_todos_ok" = "true" ]; then
    pass "test_passed_flag"
  else
    fail "test_passed_flag" "has_todos_ok=$has_todos_ok no_todos_ok=$no_todos_ok"
  fi
}

# =============================================================
# Run all tests
# =============================================================
echo "=== bin/check-stale-todos.sh test suite ==="

test_finds_todos
test_finds_fixme
test_age_from_blame
test_untracked_age_zero
test_severity_warning
test_severity_critical
test_severity_info
test_valid_json_output
test_passed_flag

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
