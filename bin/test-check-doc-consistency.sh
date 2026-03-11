#!/usr/bin/env bash
set -euo pipefail

# =============================================================
# test-check-doc-consistency.sh -- Tests for check-doc-consistency.sh
#
# Covers: ENTR-01 (doc consistency checks: debug statements,
#         line counts, missing tests)
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_SCRIPT="$SCRIPT_DIR/check-doc-consistency.sh"
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

TMPDIR_ROOT=$(mktemp -d "/tmp/test-check-doc-consistency-XXXXXX")

# Helper: create a minimal fixture project with git repo and AGENTS.md
make_fixture() {
  local name="$1"
  FIXTURE_DIR="$TMPDIR_ROOT/$name"
  mkdir -p "$FIXTURE_DIR/bin" "$FIXTURE_DIR/.planning" "$FIXTURE_DIR/skills"
  cd "$FIXTURE_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"

  # Minimal AGENTS.md with the conventions section the checker looks for
  cat > "$FIXTURE_DIR/AGENTS.md" <<'AGENTS'
# Test Project

## Conventions

- Write tests for all new features
- No debug/log statements in production code
- Keep functions small and focused
- Each commit should be atomic and revertable
- Skills must work across Claude Code sessions without re-explaining
- All instruction files must stay under 200 lines for >92% rule adherence
AGENTS

  echo "init" > "$FIXTURE_DIR/init.txt"
  git add -A && git commit -q -m "init"
}

# =============================================================
# Test 1: Detects console.log in production file
# =============================================================
test_detects_debug_statements() {
  make_fixture "detect-debug"
  cat > "$FIXTURE_DIR/bin/app.sh" <<'SCRIPT'
#!/bin/bash
console.log("test debug")
echo "normal output"
SCRIPT
  git add -A && git commit -q -m "add app with debug"

  local output="" exit_code=0
  output=$(bash "$CHECK_SCRIPT" --project-root "$FIXTURE_DIR" 2>/dev/null) || exit_code=$?

  if echo "$output" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const found = d.findings.some(f => f.check === 'debug-statements' && f.file.includes('app.sh'));
    process.exit(found ? 0 : 1);
  " 2>/dev/null; then
    pass "test_detects_debug_statements"
  else
    fail "test_detects_debug_statements" "output=$output"
  fi
}

# =============================================================
# Test 2: Skips console.log in test files
# =============================================================
test_skips_test_files() {
  make_fixture "skip-test-files"
  cat > "$FIXTURE_DIR/bin/test-app.sh" <<'SCRIPT'
#!/bin/bash
console.log("debug in test -- should be ignored")
SCRIPT
  git add -A && git commit -q -m "add test with debug"

  local output="" exit_code=0
  output=$(bash "$CHECK_SCRIPT" --project-root "$FIXTURE_DIR" 2>/dev/null) || exit_code=$?

  if echo "$output" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const debugFindings = d.findings.filter(f => f.check === 'debug-statements');
    process.exit(debugFindings.length === 0 ? 0 : 1);
  " 2>/dev/null; then
    pass "test_skips_test_files"
  else
    fail "test_skips_test_files" "output=$output"
  fi
}

# =============================================================
# Test 3: Flags instruction file over 200 lines
# =============================================================
test_flags_oversized_instruction() {
  make_fixture "oversized-skill"
  mkdir -p "$FIXTURE_DIR/skills/test-skill"
  # Create a 210-line SKILL.md
  for i in $(seq 1 210); do
    echo "Line $i of the skill file" >> "$FIXTURE_DIR/skills/test-skill/SKILL.md"
  done
  git add -A && git commit -q -m "add oversized skill"

  local output="" exit_code=0
  output=$(bash "$CHECK_SCRIPT" --project-root "$FIXTURE_DIR" 2>/dev/null) || exit_code=$?

  if echo "$output" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const found = d.findings.some(f => f.check === 'line-count' && f.file.includes('SKILL.md'));
    process.exit(found ? 0 : 1);
  " 2>/dev/null; then
    pass "test_flags_oversized_instruction"
  else
    fail "test_flags_oversized_instruction" "output=$output"
  fi
}

# =============================================================
# Test 4: Passes instruction file under 200 lines
# =============================================================
test_passes_short_instruction() {
  make_fixture "short-skill"
  mkdir -p "$FIXTURE_DIR/skills/test-skill"
  # Create a 150-line SKILL.md
  for i in $(seq 1 150); do
    echo "Line $i" >> "$FIXTURE_DIR/skills/test-skill/SKILL.md"
  done
  git add -A && git commit -q -m "add short skill"

  local output="" exit_code=0
  output=$(bash "$CHECK_SCRIPT" --project-root "$FIXTURE_DIR" 2>/dev/null) || exit_code=$?

  if echo "$output" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const lineFindings = d.findings.filter(f => f.check === 'line-count');
    process.exit(lineFindings.length === 0 ? 0 : 1);
  " 2>/dev/null; then
    pass "test_passes_short_instruction"
  else
    fail "test_passes_short_instruction" "output=$output"
  fi
}

# =============================================================
# Test 5: Detects missing test file
# =============================================================
test_detects_missing_test() {
  make_fixture "missing-test"
  echo '#!/bin/bash
echo "production script"' > "$FIXTURE_DIR/bin/myapp.sh"
  chmod +x "$FIXTURE_DIR/bin/myapp.sh"
  git add -A && git commit -q -m "add app without test"

  local output="" exit_code=0
  output=$(bash "$CHECK_SCRIPT" --project-root "$FIXTURE_DIR" 2>/dev/null) || exit_code=$?

  if echo "$output" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const found = d.findings.some(f => f.check === 'missing-tests' && f.file.includes('myapp.sh'));
    process.exit(found ? 0 : 1);
  " 2>/dev/null; then
    pass "test_detects_missing_test"
  else
    fail "test_detects_missing_test" "output=$output"
  fi
}

# =============================================================
# Test 6: No finding when test file exists
# =============================================================
test_no_finding_when_test_exists() {
  make_fixture "test-exists"
  echo '#!/bin/bash
echo "production script"' > "$FIXTURE_DIR/bin/myapp.sh"
  echo '#!/bin/bash
echo "test for myapp"' > "$FIXTURE_DIR/bin/test-myapp.sh"
  chmod +x "$FIXTURE_DIR/bin/myapp.sh" "$FIXTURE_DIR/bin/test-myapp.sh"
  git add -A && git commit -q -m "add app with test"

  local output="" exit_code=0
  output=$(bash "$CHECK_SCRIPT" --project-root "$FIXTURE_DIR" 2>/dev/null) || exit_code=$?

  if echo "$output" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const missing = d.findings.filter(f => f.check === 'missing-tests' && f.file.includes('myapp.sh'));
    process.exit(missing.length === 0 ? 0 : 1);
  " 2>/dev/null; then
    pass "test_no_finding_when_test_exists"
  else
    fail "test_no_finding_when_test_exists" "output=$output"
  fi
}

# =============================================================
# Test 7: Output is valid JSON with required keys
# =============================================================
test_valid_json_output() {
  make_fixture "json-output"

  local output="" exit_code=0
  output=$(bash "$CHECK_SCRIPT" --project-root "$FIXTURE_DIR" 2>/dev/null) || exit_code=$?

  if echo "$output" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    if (typeof d.passed !== 'boolean') process.exit(1);
    if (!Array.isArray(d.findings)) process.exit(1);
    process.exit(0);
  " 2>/dev/null; then
    pass "test_valid_json_output"
  else
    fail "test_valid_json_output" "output=$output"
  fi
}

# =============================================================
# Test 8: Passed is true when no violations
# =============================================================
test_passed_true_when_clean() {
  make_fixture "clean-project"
  # Add a production script with its test -- no debug statements, short skills
  echo '#!/bin/bash
echo "clean code"' > "$FIXTURE_DIR/bin/myapp.sh"
  echo '#!/bin/bash
echo "test"' > "$FIXTURE_DIR/bin/test-myapp.sh"
  # check-doc-consistency.sh already has its own test (this file pattern)
  chmod +x "$FIXTURE_DIR/bin/myapp.sh" "$FIXTURE_DIR/bin/test-myapp.sh"
  git add -A && git commit -q -m "add clean project"

  local output="" exit_code=0
  output=$(bash "$CHECK_SCRIPT" --project-root "$FIXTURE_DIR" 2>/dev/null) || exit_code=$?

  if echo "$output" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    process.exit(d.passed === true ? 0 : 1);
  " 2>/dev/null; then
    pass "test_passed_true_when_clean"
  else
    fail "test_passed_true_when_clean" "output=$output"
  fi
}

# =============================================================
# Run all tests
# =============================================================
echo "=== bin/check-doc-consistency.sh test suite ==="

test_detects_debug_statements
test_skips_test_files
test_flags_oversized_instruction
test_passes_short_instruction
test_detects_missing_test
test_no_finding_when_test_exists
test_valid_json_output
test_passed_true_when_clean

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
