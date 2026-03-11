#!/usr/bin/env bash
set -euo pipefail

# =============================================================
# test-entropy-sweep.sh -- Integration tests for entropy-sweep.sh
#
# Covers: ENTR-01 dispatch, ENTR-02 architecture sweep, ENTR-04 config
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWEEP_SCRIPT="$SCRIPT_DIR/entropy-sweep.sh"
DOC_CHECK_SCRIPT="$SCRIPT_DIR/check-doc-consistency.sh"
ARCH_VALIDATOR="$SCRIPT_DIR/validate-architecture.sh"
TODO_CHECKER="$SCRIPT_DIR/check-stale-todos.sh"
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

TMPDIR_ROOT=$(mktemp -d "/tmp/test-entropy-sweep-XXXXXX")

# Helper: create a full fixture with all scripts and configs
make_fixture() {
  local name="$1"
  FIXTURE_DIR="$TMPDIR_ROOT/$name"
  mkdir -p "$FIXTURE_DIR/bin" "$FIXTURE_DIR/.planning" "$FIXTURE_DIR/skills"
  cd "$FIXTURE_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"

  # AGENTS.md with conventions
  cat > "$FIXTURE_DIR/AGENTS.md" <<'AGENTS'
# Test Project

## Conventions

- Write tests for all new features
- No debug/log statements in production code
- All instruction files must stay under 200 lines for >92% rule adherence
AGENTS

  # Default config with entropy section
  cat > "$FIXTURE_DIR/.planning/config.json" <<'CONF'
{
  "entropy": {
    "enabled": true,
    "schedule": "weekly",
    "checks": {
      "doc_consistency": { "enabled": true },
      "architecture": { "enabled": true },
      "stale_todos": { "enabled": true }
    }
  }
}
CONF

  # Architecture config
  cat > "$FIXTURE_DIR/.architecture.json" <<'ARCH'
{
  "version": "1.0",
  "modules": {
    "bin/*": {
      "description": "CLI scripts",
      "can_import": ["bin/*"],
      "cannot_import": ["skills/*"]
    },
    "skills/*": {
      "description": "Skills",
      "can_import": ["bin/*"],
      "cannot_import": [".planning/*"]
    }
  },
  "rules": []
}
ARCH

  # Copy all needed scripts
  cp "$SWEEP_SCRIPT" "$FIXTURE_DIR/bin/entropy-sweep.sh"
  cp "$DOC_CHECK_SCRIPT" "$FIXTURE_DIR/bin/check-doc-consistency.sh"
  cp "$ARCH_VALIDATOR" "$FIXTURE_DIR/bin/validate-architecture.sh"
  [ -f "$TODO_CHECKER" ] && cp "$TODO_CHECKER" "$FIXTURE_DIR/bin/check-stale-todos.sh" || true
  chmod +x "$FIXTURE_DIR/bin/"*.sh

  # Add a clean source file so architecture has something to scan
  echo '#!/bin/bash
echo "hello"' > "$FIXTURE_DIR/bin/app.sh"
  echo '#!/bin/bash
echo "test"' > "$FIXTURE_DIR/bin/test-app.sh"
  chmod +x "$FIXTURE_DIR/bin/app.sh" "$FIXTURE_DIR/bin/test-app.sh"

  echo "init" > "$FIXTURE_DIR/init.txt"
  git add -A && git commit -q -m "init"
}

# Helper: run sweep in fixture and capture outputs
run_sweep() {
  SWEEP_EXIT=0
  SWEEP_STDERR=$(mktemp "$TMPDIR_ROOT/stderr-XXXXXX")
  SWEEP_STDOUT=$(cd "$FIXTURE_DIR" && bash "$FIXTURE_DIR/bin/entropy-sweep.sh" "$@" 2>"$SWEEP_STDERR") || SWEEP_EXIT=$?
  SWEEP_STDERR_TEXT=$(cat "$SWEEP_STDERR")
}

# =============================================================
# Test 1: Runs all checks by default
# =============================================================
test_runs_all_checks() {
  make_fixture "all-checks"
  run_sweep --json-only

  if echo "$SWEEP_STDOUT" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const names = d.checks.map(c => c.name).sort();
    const expected = ['architecture', 'doc-consistency', 'stale-todos'];
    process.exit(JSON.stringify(names) === JSON.stringify(expected) ? 0 : 1);
  " 2>/dev/null; then
    pass "test_runs_all_checks"
  else
    fail "test_runs_all_checks" "checks=$(echo "$SWEEP_STDOUT" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));console.log(d.checks.map(c=>c.name))" 2>/dev/null || echo 'parse-error')"
  fi
}

# =============================================================
# Test 2: --check flag runs single check
# =============================================================
test_single_check_flag() {
  make_fixture "single-check"
  run_sweep --json-only --check doc-consistency

  if echo "$SWEEP_STDOUT" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    process.exit(d.checks.length === 1 && d.checks[0].name === 'doc-consistency' ? 0 : 1);
  " 2>/dev/null; then
    pass "test_single_check_flag"
  else
    fail "test_single_check_flag" "stdout=$SWEEP_STDOUT"
  fi
}

# =============================================================
# Test 3: Config defaults when entropy section absent
# =============================================================
test_config_defaults() {
  make_fixture "no-entropy-config"
  # Replace config with one that has NO entropy section
  cat > "$FIXTURE_DIR/.planning/config.json" <<'CONF'
{
  "gates": {
    "enabled": true
  }
}
CONF
  git add -A && git commit -q -m "config without entropy"

  run_sweep --json-only

  if echo "$SWEEP_STDOUT" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    // Should still run (defaults to enabled) and have checks
    process.exit(d.checks && d.checks.length > 0 && d.summary.checks_run > 0 ? 0 : 1);
  " 2>/dev/null; then
    pass "test_config_defaults"
  else
    fail "test_config_defaults" "stdout=$SWEEP_STDOUT"
  fi
}

# =============================================================
# Test 4: Respects check disable flags
# =============================================================
test_disable_check() {
  make_fixture "disable-check"
  cat > "$FIXTURE_DIR/.planning/config.json" <<'CONF'
{
  "entropy": {
    "enabled": true,
    "schedule": "weekly",
    "checks": {
      "doc_consistency": { "enabled": false },
      "architecture": { "enabled": true },
      "stale_todos": { "enabled": true }
    }
  }
}
CONF
  git add -A && git commit -q -m "disable doc-consistency"

  run_sweep --json-only

  if echo "$SWEEP_STDOUT" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const names = d.checks.map(c => c.name);
    // doc-consistency should NOT be in the checks array
    process.exit(!names.includes('doc-consistency') && names.includes('architecture') ? 0 : 1);
  " 2>/dev/null; then
    pass "test_disable_check"
  else
    fail "test_disable_check" "checks=$(echo "$SWEEP_STDOUT" | node -e "const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));console.log(d.checks.map(c=>c.name))" 2>/dev/null || echo 'parse-error')"
  fi
}

# =============================================================
# Test 5: Architecture sweep finds violations
# =============================================================
test_architecture_violations() {
  make_fixture "arch-violation"
  # Create a bin/ script that imports from skills/ (forbidden by architecture rules)
  cat > "$FIXTURE_DIR/bin/bad-import.sh" <<'SCRIPT'
#!/bin/bash
source skills/test-skill/helper.sh
SCRIPT
  mkdir -p "$FIXTURE_DIR/skills/test-skill"
  echo '#!/bin/bash' > "$FIXTURE_DIR/skills/test-skill/helper.sh"
  git add -A && git commit -q -m "add violating skill"

  run_sweep --json-only --check architecture

  if echo "$SWEEP_STDOUT" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const arch = d.checks.find(c => c.name === 'architecture');
    process.exit(arch && arch.findings && arch.findings.length > 0 ? 0 : 1);
  " 2>/dev/null; then
    pass "test_architecture_violations"
  else
    fail "test_architecture_violations" "stdout=$SWEEP_STDOUT"
  fi
}

# =============================================================
# Test 6: Architecture sweep passes on clean project
# =============================================================
test_architecture_clean() {
  make_fixture "arch-clean"
  run_sweep --json-only --check architecture

  if echo "$SWEEP_STDOUT" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const arch = d.checks.find(c => c.name === 'architecture');
    process.exit(arch && arch.passed === true ? 0 : 1);
  " 2>/dev/null; then
    pass "test_architecture_clean"
  else
    fail "test_architecture_clean" "stdout=$SWEEP_STDOUT"
  fi
}

# =============================================================
# Test 7: Aggregates findings correctly
# =============================================================
test_aggregates_findings() {
  make_fixture "aggregate"
  # Add a file with console.log to trigger doc-consistency finding
  cat > "$FIXTURE_DIR/bin/buggy.sh" <<'SCRIPT'
#!/bin/bash
console.log("debug leak 1")
console.log("debug leak 2")
SCRIPT
  git add -A && git commit -q -m "add buggy file"

  run_sweep --json-only --check doc-consistency

  if echo "$SWEEP_STDOUT" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const docCheck = d.checks.find(c => c.name === 'doc-consistency');
    const actualFindings = docCheck ? docCheck.findings.length : 0;
    process.exit(d.summary.total_findings === actualFindings && actualFindings > 0 ? 0 : 1);
  " 2>/dev/null; then
    pass "test_aggregates_findings"
  else
    fail "test_aggregates_findings" "stdout=$SWEEP_STDOUT"
  fi
}

# =============================================================
# Test 8: Handles missing check scripts gracefully
# =============================================================
test_missing_check_script() {
  make_fixture "missing-script"
  # Remove the stale-todos checker
  rm -f "$FIXTURE_DIR/bin/check-stale-todos.sh"
  git add -A && git commit -q -m "remove todo checker"

  run_sweep --json-only

  # Sweep should complete without crashing
  if echo "$SWEEP_STDOUT" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    // Should have checks for doc-consistency and architecture, stale-todos skipped
    const names = d.checks.map(c => c.name);
    process.exit(names.includes('doc-consistency') && names.includes('architecture') ? 0 : 1);
  " 2>/dev/null; then
    pass "test_missing_check_script"
  else
    fail "test_missing_check_script" "exit=$SWEEP_EXIT stdout=$SWEEP_STDOUT"
  fi
}

# =============================================================
# Run all tests
# =============================================================
echo "=== bin/entropy-sweep.sh test suite ==="

test_runs_all_checks
test_single_check_flag
test_config_defaults
test_disable_check
test_architecture_violations
test_architecture_clean
test_aggregates_findings
test_missing_check_script

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
