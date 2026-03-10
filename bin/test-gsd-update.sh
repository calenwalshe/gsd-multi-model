#!/usr/bin/env bash
set -euo pipefail

# Test suite for bin/gsd-update.sh
# Validates script structure, inline semver_compare, and exit code contract via mocks

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPDATE_SCRIPT="$SCRIPT_DIR/gsd-update.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1 -- $2"; FAIL=$((FAIL + 1)); }

# ============================================================
# Structural Tests (no mocking needed)
# ============================================================
echo ""
echo "=== Structural tests ==="

# Test: syntax check
if bash -n "$UPDATE_SCRIPT" 2>/dev/null; then
  pass "passes bash -n syntax check"
else
  fail "syntax" "bash -n failed"
fi

# Test: executable
if [ -x "$UPDATE_SCRIPT" ]; then
  pass "script is executable"
else
  fail "executable" "script is not executable"
fi

# Test: exit code documentation in header
if head -20 "$UPDATE_SCRIPT" | grep -q "0 = success" && \
   head -20 "$UPDATE_SCRIPT" | grep -q "1 = GSD update failed" && \
   head -20 "$UPDATE_SCRIPT" | grep -q "2 = addon reinstall failed" && \
   head -20 "$UPDATE_SCRIPT" | grep -q "3 = compat warning"; then
  pass "header documents exit codes 0, 1, 2, 3"
else
  fail "exit-code-docs" "header missing exit code documentation"
fi

# Test: uses set -euo pipefail
if grep -q "set -euo pipefail" "$UPDATE_SCRIPT"; then
  pass "uses set -euo pipefail"
else
  fail "set-flags" "missing set -euo pipefail"
fi

# Test: SCRIPT_DIR resolution
if grep -q 'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE\[0\]}")" && pwd)"' "$UPDATE_SCRIPT"; then
  pass "SCRIPT_DIR resolution present"
else
  fail "SCRIPT_DIR" "missing SCRIPT_DIR resolution"
fi

# Test: contains semver_compare function
if grep -q "semver_compare()" "$UPDATE_SCRIPT"; then
  pass "contains semver_compare function"
else
  fail "semver_compare" "missing semver_compare function"
fi

# Test: references npx get-shit-done-cc
if grep -q "npx.*get-shit-done-cc" "$UPDATE_SCRIPT"; then
  pass "references npx get-shit-done-cc"
else
  fail "npx-ref" "missing npx get-shit-done-cc reference"
fi

# Test: references install.sh --force
if grep -q 'install\.sh.*--force' "$UPDATE_SCRIPT"; then
  pass "references install.sh --force"
else
  fail "install-ref" "missing install.sh --force reference"
fi

# Test: does not pipe npx through tee
if ! grep -q "npx.*|.*tee" "$UPDATE_SCRIPT"; then
  pass "does not pipe npx through tee"
else
  fail "no-tee" "npx output piped through tee"
fi

# ============================================================
# Inline semver_compare Unit Tests
# ============================================================
echo ""
echo "=== semver_compare unit tests ==="

# Local copy for testing (same implementation as gsd-update.sh and install.sh)
semver_compare() {
  local a="$1" b="$2"
  local IFS=.
  local a_parts=($a) b_parts=($b)
  local a_major=${a_parts[0]:-0} a_minor=${a_parts[1]:-0} a_patch=${a_parts[2]:-0}
  local b_major=${b_parts[0]:-0} b_minor=${b_parts[1]:-0} b_patch=${b_parts[2]:-0}

  if (( a_major != b_major )); then
    (( a_major > b_major )) && echo 1 || echo -1; return
  fi
  if (( a_minor != b_minor )); then
    (( a_minor > b_minor )) && echo 1 || echo -1; return
  fi
  if (( a_patch != b_patch )); then
    (( a_patch > b_patch )) && echo 1 || echo -1; return
  fi
  echo 0
}

check_semver() {
  local a="$1" b="$2" expected="$3"
  local actual
  actual=$(semver_compare "$a" "$b")
  if [ "$actual" = "$expected" ]; then
    pass "semver_compare $a $b = $expected"
  else
    fail "semver_compare $a $b" "expected $expected, got $actual"
  fi
}

check_semver "1.22.4" "1.22.4" "0"
check_semver "1.22.5" "1.22.4" "1"
check_semver "1.22.3" "1.22.4" "-1"
check_semver "1.23.0" "1.22.4" "1"
check_semver "2.0.0" "1.99.99" "1"
check_semver "1.100.0" "1.99.99" "1"

# ============================================================
# Mock-based Exit Code Tests
# ============================================================
echo ""
echo "=== Mock-based exit code tests ==="

setup_mock_env() {
  MOCK_DIR=$(mktemp -d)
  mkdir -p "$MOCK_DIR/bin"
  # Copy the real update script
  cp "$UPDATE_SCRIPT" "$MOCK_DIR/bin/gsd-update.sh"
  chmod +x "$MOCK_DIR/bin/gsd-update.sh"
  # Copy gsd-compat.json
  cp "$REPO_ROOT/gsd-compat.json" "$MOCK_DIR/gsd-compat.json"
  # Create mock HOME with VERSION directory
  MOCK_HOME=$(mktemp -d)
  mkdir -p "$MOCK_HOME/.claude/get-shit-done"
}

create_mock_npx() {
  local exit_code="$1"
  cat > "$MOCK_DIR/bin/npx" << MOCK_EOF
#!/bin/bash
echo "Mock GSD install (exit $exit_code)"
exit $exit_code
MOCK_EOF
  chmod +x "$MOCK_DIR/bin/npx"
}

create_mock_install() {
  local exit_code="$1"
  cat > "$MOCK_DIR/install.sh" << MOCK_EOF
#!/bin/bash
echo "Mock addon install (exit $exit_code)"
exit $exit_code
MOCK_EOF
  chmod +x "$MOCK_DIR/install.sh"
}

cleanup_mock_env() {
  rm -rf "$MOCK_DIR" "$MOCK_HOME"
}

# --- Test: GSD update failure -> exit 1 ---
test_exit_1_gsd_failure() {
  setup_mock_env
  create_mock_npx 1
  create_mock_install 0
  echo -n "1.22.4" > "$MOCK_HOME/.claude/get-shit-done/VERSION"

  local rc=0
  HOME="$MOCK_HOME" PATH="$MOCK_DIR/bin:$PATH" bash "$MOCK_DIR/bin/gsd-update.sh" >/dev/null 2>&1 || rc=$?

  if [ "$rc" -eq 1 ]; then
    pass "GSD update failure -> exit 1"
  else
    fail "exit-1" "expected exit 1, got $rc"
  fi
  cleanup_mock_env
}

# --- Test: Addon reinstall failure -> exit 2 ---
test_exit_2_install_failure() {
  setup_mock_env
  create_mock_npx 0
  create_mock_install 1
  echo -n "1.22.4" > "$MOCK_HOME/.claude/get-shit-done/VERSION"

  local rc=0
  HOME="$MOCK_HOME" PATH="$MOCK_DIR/bin:$PATH" bash "$MOCK_DIR/bin/gsd-update.sh" >/dev/null 2>&1 || rc=$?

  if [ "$rc" -eq 2 ]; then
    pass "addon reinstall failure -> exit 2"
  else
    fail "exit-2" "expected exit 2, got $rc"
  fi
  cleanup_mock_env
}

# --- Test: Full success -> exit 0 ---
test_exit_0_success() {
  setup_mock_env
  create_mock_npx 0
  create_mock_install 0
  echo -n "1.22.4" > "$MOCK_HOME/.claude/get-shit-done/VERSION"

  local rc=0
  HOME="$MOCK_HOME" PATH="$MOCK_DIR/bin:$PATH" bash "$MOCK_DIR/bin/gsd-update.sh" >/dev/null 2>&1 || rc=$?

  if [ "$rc" -eq 0 ]; then
    pass "full success -> exit 0"
  else
    fail "exit-0" "expected exit 0, got $rc"
  fi
  cleanup_mock_env
}

# --- Test: Compat warning -> exit 3 ---
test_exit_3_compat_warning() {
  setup_mock_env
  create_mock_npx 0
  create_mock_install 0
  echo -n "99.0.0" > "$MOCK_HOME/.claude/get-shit-done/VERSION"

  local rc=0
  HOME="$MOCK_HOME" PATH="$MOCK_DIR/bin:$PATH" bash "$MOCK_DIR/bin/gsd-update.sh" >/dev/null 2>&1 || rc=$?

  if [ "$rc" -eq 3 ]; then
    pass "compat warning -> exit 3"
  else
    fail "exit-3" "expected exit 3, got $rc"
  fi
  cleanup_mock_env
}

test_exit_1_gsd_failure
test_exit_2_install_failure
test_exit_0_success
test_exit_3_compat_warning

# ============================================================
# Summary
# ============================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
