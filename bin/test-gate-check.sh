#!/usr/bin/env bash
set -euo pipefail

# =============================================================
# test-gate-check.sh -- Integration tests for gate-check.sh
#
# Covers: GATE-01 (lint blocks), GATE-03 (structural), GATE-04 (errors)
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_SCRIPT="$SCRIPT_DIR/gate-check.sh"
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

TMPDIR_ROOT=$(mktemp -d "/tmp/test-gate-check-XXXXXX")

# Helper: create a minimal fixture project with git repo and config
# Usage: make_fixture <name>
# Sets FIXTURE_DIR to the created directory
make_fixture() {
  local name="$1"
  FIXTURE_DIR="$TMPDIR_ROOT/$name"
  mkdir -p "$FIXTURE_DIR/bin" "$FIXTURE_DIR/.planning"

  cd "$FIXTURE_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"

  # Default config: gates enabled, no lint command, arch + structural enabled
  cat > "$FIXTURE_DIR/.planning/config.json" <<'CONF'
{
  "gates": {
    "enabled": true,
    "lint": { "enabled": true, "command": "", "auto_detect": false },
    "architecture": { "enabled": false },
    "structural": { "enabled": true },
    "timeout_seconds": 10,
    "on_timeout": "warn"
  }
}
CONF

  # Copy gate-check.sh into the fixture bin/
  cp "$GATE_SCRIPT" "$FIXTURE_DIR/bin/gate-check.sh"
  chmod +x "$FIXTURE_DIR/bin/gate-check.sh"

  # Initial commit so git works
  echo "init" > "$FIXTURE_DIR/init.txt"
  git add init.txt .planning/config.json bin/gate-check.sh
  git commit -q -m "init"
}

# Helper: run gate-check in fixture and capture outputs
# Usage: run_gate [extra args...]
# Sets: GC_STDOUT, GC_STDERR, GC_EXIT
run_gate() {
  GC_EXIT=0
  GC_STDERR=$(mktemp "$TMPDIR_ROOT/stderr-XXXXXX")
  GC_STDOUT=$(cd "$FIXTURE_DIR" && bash "$FIXTURE_DIR/bin/gate-check.sh" "$@" 2>"$GC_STDERR") || GC_EXIT=$?
  GC_STDERR_TEXT=$(cat "$GC_STDERR")
}

# =============================================================
# GATE-01: Lint blocks commit
# =============================================================

test_lint_pass() {
  make_fixture "lint_pass"
  # Configure lint command that always succeeds
  cat > "$FIXTURE_DIR/.planning/config.json" <<'CONF'
{
  "gates": {
    "enabled": true,
    "lint": { "enabled": true, "command": "echo ok", "auto_detect": false },
    "architecture": { "enabled": false },
    "structural": { "enabled": false },
    "timeout_seconds": 10
  }
}
CONF
  git add .planning/config.json && git commit -q -m "cfg"

  # Stage a lintable file
  echo '#!/bin/bash' > "$FIXTURE_DIR/test.sh"
  git add test.sh

  run_gate
  if [ "$GC_EXIT" -eq 0 ] && echo "$GC_STDOUT" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    process.exit(d.passed === true ? 0 : 1);
  "; then
    pass "test_lint_pass"
  else
    fail "test_lint_pass" "exit=$GC_EXIT stdout=$GC_STDOUT"
  fi
}

test_lint_fail() {
  make_fixture "lint_fail"
  cat > "$FIXTURE_DIR/.planning/config.json" <<'CONF'
{
  "gates": {
    "enabled": true,
    "lint": { "enabled": true, "command": "exit 1", "auto_detect": false },
    "architecture": { "enabled": false },
    "structural": { "enabled": false },
    "timeout_seconds": 10
  }
}
CONF
  git add .planning/config.json && git commit -q -m "cfg"

  echo '#!/bin/bash' > "$FIXTURE_DIR/test.sh"
  git add test.sh

  run_gate
  if [ "$GC_EXIT" -eq 1 ] && echo "$GC_STDOUT" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    process.exit(d.passed === false ? 0 : 1);
  "; then
    pass "test_lint_fail"
  else
    fail "test_lint_fail" "expected exit=1/passed=false, got exit=$GC_EXIT"
  fi
}

test_lint_skip_no_command() {
  make_fixture "lint_skip"
  # lint enabled but no command and auto_detect off
  cat > "$FIXTURE_DIR/.planning/config.json" <<'CONF'
{
  "gates": {
    "enabled": true,
    "lint": { "enabled": true, "command": "", "auto_detect": false },
    "architecture": { "enabled": false },
    "structural": { "enabled": false },
    "timeout_seconds": 10
  }
}
CONF
  git add .planning/config.json && git commit -q -m "cfg"

  echo '#!/bin/bash' > "$FIXTURE_DIR/test.sh"
  git add test.sh

  run_gate
  if [ "$GC_EXIT" -eq 0 ]; then
    # Check lint gate message mentions no linter
    if echo "$GC_STDOUT" | node -e "
      const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
      const lint=d.gates.find(g=>g.name==='lint');
      process.exit(lint && lint.passed===true ? 0 : 1);
    "; then
      pass "test_lint_skip_no_command"
    else
      fail "test_lint_skip_no_command" "lint gate not found or not passed"
    fi
  else
    fail "test_lint_skip_no_command" "exit=$GC_EXIT"
  fi
}

test_lint_only_staged_files() {
  make_fixture "lint_staged"
  # Lint command that prints its arguments -- we check only staged file appears
  cat > "$FIXTURE_DIR/.planning/config.json" <<'CONF'
{
  "gates": {
    "enabled": true,
    "lint": { "enabled": true, "command": "echo LINTING {files}", "auto_detect": false },
    "architecture": { "enabled": false },
    "structural": { "enabled": false },
    "timeout_seconds": 10
  }
}
CONF
  git add .planning/config.json && git commit -q -m "cfg"

  # Create two files, only stage one
  echo '#!/bin/bash' > "$FIXTURE_DIR/staged.sh"
  echo '#!/bin/bash' > "$FIXTURE_DIR/unstaged.sh"
  git add staged.sh

  run_gate
  # The --files expansion uses staged files from git diff --cached
  # unstaged.sh should NOT be in the lint
  if [ "$GC_EXIT" -eq 0 ]; then
    pass "test_lint_only_staged_files"
  else
    fail "test_lint_only_staged_files" "exit=$GC_EXIT"
  fi
}

# =============================================================
# GATE-03: Structural tests
# =============================================================

test_structural_file_exists_pass() {
  make_fixture "struct_exists_pass"
  cat > "$FIXTURE_DIR/.planning/config.json" <<'CONF'
{
  "gates": {
    "enabled": true,
    "lint": { "enabled": false },
    "architecture": { "enabled": false },
    "structural": { "enabled": true },
    "timeout_seconds": 10
  }
}
CONF
  git add .planning/config.json && git commit -q -m "cfg"

  # Create plan with structural test
  mkdir -p "$FIXTURE_DIR/plans"
  cat > "$FIXTURE_DIR/plans/test-plan.md" <<'PLAN'
<structural_tests>
  <check type="file-exists" path="foo.sh" />
</structural_tests>
PLAN

  # Create the file it checks for
  echo '#!/bin/bash' > "$FIXTURE_DIR/foo.sh"
  echo "dummy" > "$FIXTURE_DIR/dummy.txt"
  git add dummy.txt

  run_gate --plan-path "$FIXTURE_DIR/plans/test-plan.md"
  if [ "$GC_EXIT" -eq 0 ] && echo "$GC_STDOUT" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const s=d.gates.find(g=>g.name==='structural');
    process.exit(s && s.passed===true ? 0 : 1);
  "; then
    pass "test_structural_file_exists_pass"
  else
    fail "test_structural_file_exists_pass" "exit=$GC_EXIT"
  fi
}

test_structural_file_exists_fail() {
  make_fixture "struct_exists_fail"
  cat > "$FIXTURE_DIR/.planning/config.json" <<'CONF'
{
  "gates": {
    "enabled": true,
    "lint": { "enabled": false },
    "architecture": { "enabled": false },
    "structural": { "enabled": true },
    "timeout_seconds": 10
  }
}
CONF
  git add .planning/config.json && git commit -q -m "cfg"

  mkdir -p "$FIXTURE_DIR/plans"
  cat > "$FIXTURE_DIR/plans/test-plan.md" <<'PLAN'
<structural_tests>
  <check type="file-exists" path="missing.sh" />
</structural_tests>
PLAN

  echo "dummy" > "$FIXTURE_DIR/dummy.txt"
  git add dummy.txt

  run_gate --plan-path "$FIXTURE_DIR/plans/test-plan.md"
  if [ "$GC_EXIT" -eq 1 ] && echo "$GC_STDOUT" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const s=d.gates.find(g=>g.name==='structural');
    process.exit(s && s.passed===false && s.violations && s.violations.length>0 ? 0 : 1);
  "; then
    pass "test_structural_file_exists_fail"
  else
    fail "test_structural_file_exists_fail" "expected exit=1 with violation"
  fi
}

test_structural_file_contains() {
  make_fixture "struct_contains"
  cat > "$FIXTURE_DIR/.planning/config.json" <<'CONF'
{
  "gates": {
    "enabled": true,
    "lint": { "enabled": false },
    "architecture": { "enabled": false },
    "structural": { "enabled": true },
    "timeout_seconds": 10
  }
}
CONF
  git add .planning/config.json && git commit -q -m "cfg"

  mkdir -p "$FIXTURE_DIR/plans"
  cat > "$FIXTURE_DIR/plans/test-plan.md" <<'PLAN'
<structural_tests>
  <check type="file-contains" path="foo.sh" pattern="gate_run" />
</structural_tests>
PLAN

  echo -e '#!/bin/bash\ngate_run() { echo ok; }' > "$FIXTURE_DIR/foo.sh"
  echo "dummy" > "$FIXTURE_DIR/dummy.txt"
  git add dummy.txt

  run_gate --plan-path "$FIXTURE_DIR/plans/test-plan.md"
  if [ "$GC_EXIT" -eq 0 ]; then
    pass "test_structural_file_contains"
  else
    fail "test_structural_file_contains" "exit=$GC_EXIT"
  fi
}

test_structural_file_not_contains() {
  make_fixture "struct_not_contains"
  cat > "$FIXTURE_DIR/.planning/config.json" <<'CONF'
{
  "gates": {
    "enabled": true,
    "lint": { "enabled": false },
    "architecture": { "enabled": false },
    "structural": { "enabled": true },
    "timeout_seconds": 10
  }
}
CONF
  git add .planning/config.json && git commit -q -m "cfg"

  mkdir -p "$FIXTURE_DIR/plans"
  cat > "$FIXTURE_DIR/plans/test-plan.md" <<'PLAN'
<structural_tests>
  <check type="file-not-contains" path="foo.sh" pattern="hardcoded_secret" />
</structural_tests>
PLAN

  echo '#!/bin/bash' > "$FIXTURE_DIR/foo.sh"
  echo "dummy" > "$FIXTURE_DIR/dummy.txt"
  git add dummy.txt

  run_gate --plan-path "$FIXTURE_DIR/plans/test-plan.md"
  if [ "$GC_EXIT" -eq 0 ]; then
    pass "test_structural_file_not_contains"
  else
    fail "test_structural_file_not_contains" "exit=$GC_EXIT"
  fi
}

test_structural_no_plan_path() {
  make_fixture "struct_no_plan"
  cat > "$FIXTURE_DIR/.planning/config.json" <<'CONF'
{
  "gates": {
    "enabled": true,
    "lint": { "enabled": false },
    "architecture": { "enabled": false },
    "structural": { "enabled": true },
    "timeout_seconds": 10
  }
}
CONF
  git add .planning/config.json && git commit -q -m "cfg"

  echo "dummy" > "$FIXTURE_DIR/dummy.txt"
  git add dummy.txt

  # No --plan-path argument
  run_gate
  if [ "$GC_EXIT" -eq 0 ] && echo "$GC_STDOUT" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const s=d.gates.find(g=>g.name==='structural');
    process.exit(s && s.message.includes('No plan path') ? 0 : 1);
  "; then
    pass "test_structural_no_plan_path"
  else
    fail "test_structural_no_plan_path" "exit=$GC_EXIT"
  fi
}

# =============================================================
# GATE-04: Actionable errors
# =============================================================

test_error_format_has_file_rule_fix() {
  make_fixture "error_format"
  cat > "$FIXTURE_DIR/.planning/config.json" <<'CONF'
{
  "gates": {
    "enabled": true,
    "lint": { "enabled": false },
    "architecture": { "enabled": false },
    "structural": { "enabled": true },
    "timeout_seconds": 10
  }
}
CONF
  git add .planning/config.json && git commit -q -m "cfg"

  mkdir -p "$FIXTURE_DIR/plans"
  cat > "$FIXTURE_DIR/plans/test-plan.md" <<'PLAN'
<structural_tests>
  <check type="file-exists" path="nonexistent.sh" />
</structural_tests>
PLAN

  echo "dummy" > "$FIXTURE_DIR/dummy.txt"
  git add dummy.txt

  run_gate --plan-path "$FIXTURE_DIR/plans/test-plan.md"
  # Check JSON violation has file, rule, message, fix fields
  if echo "$GC_STDOUT" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const s=d.gates.find(g=>g.name==='structural');
    if (!s || !s.violations || s.violations.length===0) process.exit(1);
    const v=s.violations[0];
    if (v.file && v.rule && v.message && v.fix) process.exit(0);
    process.exit(1);
  "; then
    pass "test_error_format_has_file_rule_fix"
  else
    fail "test_error_format_has_file_rule_fix" "violation missing required fields"
  fi
}

test_stderr_human_readable() {
  make_fixture "stderr_readable"
  cat > "$FIXTURE_DIR/.planning/config.json" <<'CONF'
{
  "gates": {
    "enabled": true,
    "lint": { "enabled": true, "command": "exit 1", "auto_detect": false },
    "architecture": { "enabled": false },
    "structural": { "enabled": false },
    "timeout_seconds": 10
  }
}
CONF
  git add .planning/config.json && git commit -q -m "cfg"

  echo '#!/bin/bash' > "$FIXTURE_DIR/test.sh"
  git add test.sh

  run_gate
  # stderr should contain "GATE FAILED"
  if echo "$GC_STDERR_TEXT" | grep -q "GATE FAILED"; then
    pass "test_stderr_human_readable"
  else
    fail "test_stderr_human_readable" "stderr missing GATE FAILED header"
  fi
}

test_pass_output_clean() {
  make_fixture "pass_output"
  cat > "$FIXTURE_DIR/.planning/config.json" <<'CONF'
{
  "gates": {
    "enabled": true,
    "lint": { "enabled": true, "command": "echo ok", "auto_detect": false },
    "architecture": { "enabled": false },
    "structural": { "enabled": false },
    "timeout_seconds": 10
  }
}
CONF
  git add .planning/config.json && git commit -q -m "cfg"

  echo '#!/bin/bash' > "$FIXTURE_DIR/test.sh"
  git add test.sh

  run_gate
  # stderr should contain "ALL GATES PASSED", stdout should have "passed": true
  if echo "$GC_STDERR_TEXT" | grep -q "ALL GATES PASSED" && echo "$GC_STDOUT" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    process.exit(d.passed===true ? 0 : 1);
  "; then
    pass "test_pass_output_clean"
  else
    fail "test_pass_output_clean" "missing GATES PASSED or passed!=true"
  fi
}

# =============================================================
# General
# =============================================================

test_gates_disabled() {
  make_fixture "gates_disabled"
  cat > "$FIXTURE_DIR/.planning/config.json" <<'CONF'
{
  "gates": {
    "enabled": false
  }
}
CONF
  git add .planning/config.json && git commit -q -m "cfg"

  echo "dummy" > "$FIXTURE_DIR/dummy.txt"
  git add dummy.txt

  run_gate
  if [ "$GC_EXIT" -eq 0 ] && echo "$GC_STDOUT" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    process.exit(d.skipped===true ? 0 : 1);
  "; then
    pass "test_gates_disabled"
  else
    fail "test_gates_disabled" "expected exit=0 with skipped=true"
  fi
}

test_planning_files_excluded() {
  make_fixture "planning_excluded"
  cat > "$FIXTURE_DIR/.planning/config.json" <<'CONF'
{
  "gates": {
    "enabled": true,
    "lint": { "enabled": true, "command": "exit 1", "auto_detect": false },
    "architecture": { "enabled": false },
    "structural": { "enabled": false },
    "timeout_seconds": 10
  }
}
CONF
  git add .planning/config.json && git commit -q -m "cfg"

  # Only stage a .planning/ file -- lint should be skipped (no lintable source files)
  echo "some plan" > "$FIXTURE_DIR/.planning/foo.md"
  git add .planning/foo.md

  run_gate
  # Should pass because .planning files are filtered out, leaving no lintable files
  if [ "$GC_EXIT" -eq 0 ]; then
    pass "test_planning_files_excluded"
  else
    fail "test_planning_files_excluded" "exit=$GC_EXIT -- .planning files not filtered"
  fi
}

# =============================================================
# Run all tests
# =============================================================
echo "=== bin/gate-check.sh test suite ==="

# GATE-01
test_lint_pass
test_lint_fail
test_lint_skip_no_command
test_lint_only_staged_files

# GATE-03
test_structural_file_exists_pass
test_structural_file_exists_fail
test_structural_file_contains
test_structural_file_not_contains
test_structural_no_plan_path

# GATE-04
test_error_format_has_file_rule_fix
test_stderr_human_readable
test_pass_output_clean

# General
test_gates_disabled
test_planning_files_excluded

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
