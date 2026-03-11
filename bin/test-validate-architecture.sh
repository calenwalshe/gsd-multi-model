#!/usr/bin/env bash
set -euo pipefail

# =============================================================
# test-validate-architecture.sh -- Unit tests for validate-architecture.sh
#
# Covers: GATE-02 (architecture violations caught)
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/validate-architecture.sh"
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

TMPDIR_ROOT=$(mktemp -d "/tmp/test-validate-arch-XXXXXX")

# Helper: create a fixture directory with .architecture.json and source files
# Usage: make_fixture <name>
# Sets FIXTURE_DIR
make_fixture() {
  local name="$1"
  FIXTURE_DIR="$TMPDIR_ROOT/$name"
  mkdir -p "$FIXTURE_DIR/bin" "$FIXTURE_DIR/skills/foo" "$FIXTURE_DIR/skills/bar" "$FIXTURE_DIR/global"

  # Copy the validator into the fixture's bin/ (it derives PROJECT_ROOT from its location)
  cp "$VALIDATOR" "$FIXTURE_DIR/bin/validate-architecture.sh"
  chmod +x "$FIXTURE_DIR/bin/validate-architecture.sh"

  # Default architecture config
  cat > "$FIXTURE_DIR/.architecture.json" <<'ARCH'
{
  "version": "1.0",
  "modules": {
    "skills/*": {
      "description": "Claude Code skills",
      "can_import": ["bin/*"],
      "cannot_import": ["global/*", ".planning/*"]
    },
    "bin/*": {
      "description": "CLI scripts and tools",
      "can_import": ["bin/*"],
      "cannot_import": ["skills/*"]
    },
    "global/*": {
      "description": "Global config templates",
      "can_import": [],
      "cannot_import": ["skills/*", "bin/*"]
    }
  },
  "rules": [
    {
      "name": "no-circular-skill-deps",
      "description": "Skills must not reference other skills as dependencies",
      "from": "skills/*/",
      "cannot_reach": "skills/*/"
    }
  ]
}
ARCH

  cd "$FIXTURE_DIR"
}

# Helper: run validator in fixture
# Usage: run_validator <config-path> [files...]
# Sets: VA_STDOUT, VA_EXIT
run_validator() {
  VA_EXIT=0
  VA_STDOUT=$(cd "$FIXTURE_DIR" && bash "$FIXTURE_DIR/bin/validate-architecture.sh" "$@" 2>/dev/null) || VA_EXIT=$?
}

# =============================================================
# Clean passes
# =============================================================

test_no_files() {
  make_fixture "no_files"
  run_validator ".architecture.json"
  if [ "$VA_EXIT" -eq 0 ] && echo "$VA_STDOUT" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    process.exit(d.passed===true && d.files_checked===0 ? 0 : 1);
  "; then
    pass "test_no_files"
  else
    fail "test_no_files" "exit=$VA_EXIT"
  fi
}

test_clean_bin_script() {
  make_fixture "clean_bin"
  # A bin script that sources another bin script -- allowed
  echo '#!/bin/bash
source bin/helper.sh' > "$FIXTURE_DIR/bin/main.sh"
  echo '#!/bin/bash
echo helper' > "$FIXTURE_DIR/bin/helper.sh"

  run_validator ".architecture.json" "bin/main.sh"
  if [ "$VA_EXIT" -eq 0 ] && echo "$VA_STDOUT" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    process.exit(d.passed===true ? 0 : 1);
  "; then
    pass "test_clean_bin_script"
  else
    fail "test_clean_bin_script" "exit=$VA_EXIT stdout=$VA_STDOUT"
  fi
}

test_unmatched_file_skipped() {
  make_fixture "unmatched"
  echo '{}' > "$FIXTURE_DIR/package.json"

  run_validator ".architecture.json" "package.json"
  if [ "$VA_EXIT" -eq 0 ] && echo "$VA_STDOUT" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    process.exit(d.passed===true && d.files_checked===0 ? 0 : 1);
  "; then
    pass "test_unmatched_file_skipped"
  else
    fail "test_unmatched_file_skipped" "exit=$VA_EXIT"
  fi
}

# =============================================================
# Violation detection (GATE-02)
# =============================================================

test_skill_imports_skill() {
  make_fixture "skill_imports_skill"
  # A skill helper.sh that sources another skill's util.sh
  echo '#!/bin/bash
source skills/bar/util.sh' > "$FIXTURE_DIR/skills/foo/helper.sh"
  echo '#!/bin/bash
echo util' > "$FIXTURE_DIR/skills/bar/util.sh"

  run_validator ".architecture.json" "skills/foo/helper.sh"
  if [ "$VA_EXIT" -eq 1 ] && echo "$VA_STDOUT" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    process.exit(d.passed===false && d.violations.length>0 ? 0 : 1);
  "; then
    pass "test_skill_imports_skill"
  else
    fail "test_skill_imports_skill" "expected violation, exit=$VA_EXIT"
  fi
}

test_bin_imports_skill() {
  make_fixture "bin_imports_skill"
  echo '#!/bin/bash
source skills/init-gsd/something.sh' > "$FIXTURE_DIR/bin/tool.sh"
  mkdir -p "$FIXTURE_DIR/skills/init-gsd"
  echo '#!/bin/bash' > "$FIXTURE_DIR/skills/init-gsd/something.sh"

  run_validator ".architecture.json" "bin/tool.sh"
  if [ "$VA_EXIT" -eq 1 ] && echo "$VA_STDOUT" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const v=d.violations.find(v=>v.rule==='cannot_import');
    process.exit(v ? 0 : 1);
  "; then
    pass "test_bin_imports_skill"
  else
    fail "test_bin_imports_skill" "expected cannot_import violation, exit=$VA_EXIT"
  fi
}

test_global_imports_bin() {
  make_fixture "global_imports_bin"
  echo '#!/bin/bash
source bin/util.sh' > "$FIXTURE_DIR/global/config.sh"
  echo '#!/bin/bash' > "$FIXTURE_DIR/bin/util.sh"

  run_validator ".architecture.json" "global/config.sh"
  if [ "$VA_EXIT" -eq 1 ] && echo "$VA_STDOUT" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const v=d.violations.find(v=>v.rule==='cannot_import');
    process.exit(v ? 0 : 1);
  "; then
    pass "test_global_imports_bin"
  else
    fail "test_global_imports_bin" "expected cannot_import violation, exit=$VA_EXIT"
  fi
}

# =============================================================
# Violation output format
# =============================================================

test_violation_has_required_fields() {
  make_fixture "violation_fields"
  echo '#!/bin/bash
source skills/bar/util.sh' > "$FIXTURE_DIR/skills/foo/helper.sh"
  echo '#!/bin/bash' > "$FIXTURE_DIR/skills/bar/util.sh"

  run_validator ".architecture.json" "skills/foo/helper.sh"
  if echo "$VA_STDOUT" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const v=d.violations[0];
    if (v && v.file && v.rule && v.message && v.fix) process.exit(0);
    process.exit(1);
  "; then
    pass "test_violation_has_required_fields"
  else
    fail "test_violation_has_required_fields" "violation missing file/rule/message/fix"
  fi
}

test_multiple_violations() {
  make_fixture "multi_violations"
  # A bin script importing from both skills and global (if global was forbidden)
  # Actually: a skill helper importing from another skill AND from global
  echo '#!/bin/bash
source skills/bar/util.sh
source global/template.sh' > "$FIXTURE_DIR/skills/foo/helper.sh"
  echo '#!/bin/bash' > "$FIXTURE_DIR/skills/bar/util.sh"
  echo '#!/bin/bash' > "$FIXTURE_DIR/global/template.sh"

  run_validator ".architecture.json" "skills/foo/helper.sh"
  if [ "$VA_EXIT" -eq 1 ] && echo "$VA_STDOUT" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    process.exit(d.violations.length>=2 ? 0 : 1);
  "; then
    pass "test_multiple_violations"
  else
    fail "test_multiple_violations" "expected >=2 violations, exit=$VA_EXIT"
  fi
}

# =============================================================
# Edge cases
# =============================================================

test_missing_architecture_file() {
  make_fixture "missing_arch"
  run_validator "nonexistent.json" "bin/tool.sh"
  if [ "$VA_EXIT" -eq 1 ] && echo "$VA_STDOUT" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    process.exit(d.passed===false ? 0 : 1);
  "; then
    pass "test_missing_architecture_file"
  else
    fail "test_missing_architecture_file" "expected exit=1 with passed=false"
  fi
}

test_relative_import_resolved() {
  make_fixture "relative_import"
  # A skill helper that uses ../ to reach another skill
  echo '#!/bin/bash
source ../bar/util.sh' > "$FIXTURE_DIR/skills/foo/helper.sh"
  echo '#!/bin/bash' > "$FIXTURE_DIR/skills/bar/util.sh"

  run_validator ".architecture.json" "skills/foo/helper.sh"
  # ../bar/util.sh from skills/foo/helper.sh resolves to skills/bar/util.sh
  # This should trigger no-circular-skill-deps
  if [ "$VA_EXIT" -eq 1 ] && echo "$VA_STDOUT" | node -e "
    const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    process.exit(d.passed===false && d.violations.length>0 ? 0 : 1);
  "; then
    pass "test_relative_import_resolved"
  else
    fail "test_relative_import_resolved" "expected violation for relative import, exit=$VA_EXIT stdout=$VA_STDOUT"
  fi
}

# =============================================================
# Run all tests
# =============================================================
echo "=== bin/validate-architecture.sh test suite ==="

# Clean passes
test_no_files
test_clean_bin_script
test_unmatched_file_skipped

# Violation detection
test_skill_imports_skill
test_bin_imports_skill
test_global_imports_bin

# Output format
test_violation_has_required_fields
test_multiple_violations

# Edge cases
test_missing_architecture_file
test_relative_import_resolved

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
