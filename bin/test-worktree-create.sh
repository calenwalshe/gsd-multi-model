#!/usr/bin/env bash
set -euo pipefail

# Test suite for bin/worktree-create.sh
# Uses temporary git repos to validate behavior

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREATE_SCRIPT="$SCRIPT_DIR/worktree-create.sh"
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1 -- $2"; FAIL=$((FAIL + 1)); }

cleanup() {
  rm -rf "$TEST_DIR" 2>/dev/null || true
}
trap cleanup EXIT

TEST_DIR=$(mktemp -d /tmp/gsd-wt-test-XXXXXX)

# --- Test 1: Exits 1 when not in a git repo ---
test_not_git_repo() {
  local tmpdir="$TEST_DIR/not-a-repo"
  mkdir -p "$tmpdir"
  if (cd "$tmpdir" && bash "$CREATE_SCRIPT" 2>/dev/null); then
    fail "not-git-repo" "should exit non-zero"
  else
    local rc=$?
    if [ "$rc" -eq 1 ]; then
      pass "not-git-repo exits 1"
    else
      fail "not-git-repo" "expected exit 1, got $rc"
    fi
  fi
}

# --- Test 2: Exits 1 when working tree is dirty ---
test_dirty_tree() {
  local repo="$TEST_DIR/dirty-repo"
  mkdir -p "$repo" && cd "$repo"
  git init -q && git commit --allow-empty -m "init" -q
  echo "dirty" > untracked.txt && git add untracked.txt
  if bash "$CREATE_SCRIPT" 2>/dev/null; then
    fail "dirty-tree" "should exit non-zero"
  else
    local rc=$?
    if [ "$rc" -eq 1 ]; then
      pass "dirty-tree exits 1"
    else
      fail "dirty-tree" "expected exit 1, got $rc"
    fi
  fi
}

# --- Test 3: Creates worktree successfully (no args) ---
test_create_no_args() {
  local repo="$TEST_DIR/clean-repo"
  mkdir -p "$repo" && cd "$repo"
  git init -q && git commit --allow-empty -m "init" -q
  local output
  output=$(bash "$CREATE_SCRIPT" --json 2>/dev/null)
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "create-no-args" "exit code $rc, output: $output"
    return
  fi
  # Validate JSON has required fields
  if echo "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'branch' in d and 'path' in d and 'base_commit' in d" 2>/dev/null; then
    pass "create-no-args produces valid JSON with required fields"
  else
    fail "create-no-args" "invalid JSON: $output"
  fi
  # Verify worktree dir exists
  local wt_path
  wt_path=$(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin)['path'])")
  if [ -d "$wt_path" ]; then
    pass "create-no-args worktree directory exists"
  else
    fail "create-no-args" "worktree directory not found: $wt_path"
  fi
  # Cleanup worktree
  git worktree remove "$wt_path" --force 2>/dev/null || true
}

# --- Test 4: --task flag derives branch name from plan file ---
test_task_flag() {
  local repo="$TEST_DIR/task-repo"
  mkdir -p "$repo" && cd "$repo"
  git init -q && git commit --allow-empty -m "init" -q
  mkdir -p .planning/phases/04-worktree
  touch .planning/phases/04-worktree/04-01-PLAN.md
  local output
  output=$(bash "$CREATE_SCRIPT" --task .planning/phases/04-worktree/04-01-PLAN.md --json 2>/dev/null)
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "task-flag" "exit code $rc"
    return
  fi
  local branch
  branch=$(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin)['branch'])")
  if [ "$branch" = "gsd/phase-04/plan-01" ]; then
    pass "task-flag derives correct branch name"
  else
    fail "task-flag" "expected gsd/phase-04/plan-01, got $branch"
  fi
  # Cleanup
  local wt_path
  wt_path=$(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin)['path'])")
  git worktree remove "$wt_path" --force 2>/dev/null || true
}

# --- Test 5: Exits 2 when branch already exists ---
test_branch_exists() {
  local repo="$TEST_DIR/branch-exists-repo"
  mkdir -p "$repo" && cd "$repo"
  git init -q && git commit --allow-empty -m "init" -q
  mkdir -p .planning/phases/05-test
  touch .planning/phases/05-test/05-01-PLAN.md
  # Create the branch first
  git branch "gsd/phase-05/plan-01"
  if bash "$CREATE_SCRIPT" --task .planning/phases/05-test/05-01-PLAN.md 2>/dev/null; then
    fail "branch-exists" "should exit non-zero"
  else
    local rc=$?
    if [ "$rc" -eq 2 ]; then
      pass "branch-exists exits 2"
    else
      fail "branch-exists" "expected exit 2, got $rc"
    fi
  fi
}

# --- Test 6: Warns on 3+ active worktrees ---
test_worktree_warning() {
  local repo="$TEST_DIR/warn-repo"
  mkdir -p "$repo" && cd "$repo"
  git init -q && git commit --allow-empty -m "init" -q
  # Create 3 worktrees with gsd-worktree naming
  for i in 1 2 3; do
    git worktree add "../gsd-worktree-warn-$i" -b "gsd/warn-$i" -q 2>/dev/null
  done
  local output
  output=$(bash "$CREATE_SCRIPT" --json 2>&1)
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "worktree-warning still succeeds with 3+ worktrees"
  else
    fail "worktree-warning" "should succeed even with warning, got exit $rc"
  fi
  # Cleanup
  for i in 1 2 3; do
    git worktree remove "../gsd-worktree-warn-$i" --force 2>/dev/null || true
  done
}

# --- Test 7: Sibling directory creation ---
test_sibling_dir() {
  local repo="$TEST_DIR/sibling-repo"
  mkdir -p "$repo" && cd "$repo"
  git init -q && git commit --allow-empty -m "init" -q
  mkdir -p .planning/phases/06-test
  touch .planning/phases/06-test/06-02-PLAN.md
  local output
  output=$(bash "$CREATE_SCRIPT" --task .planning/phases/06-test/06-02-PLAN.md --json 2>/dev/null)
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "sibling-dir" "exit code $rc"
    return
  fi
  local wt_path
  wt_path=$(echo "$output" | python3 -c "import sys,json; print(json.load(sys.stdin)['path'])")
  local repo_parent
  repo_parent=$(dirname "$repo")
  local wt_parent
  wt_parent=$(dirname "$wt_path")
  if [ "$repo_parent" = "$wt_parent" ]; then
    pass "sibling-dir worktree is sibling of repo"
  else
    fail "sibling-dir" "repo parent=$repo_parent, worktree parent=$wt_parent"
  fi
  # Cleanup
  git worktree remove "$wt_path" --force 2>/dev/null || true
}

echo "=== worktree-create.sh test suite ==="
test_not_git_repo
test_dirty_tree
test_create_no_args
test_task_flag
test_branch_exists
test_worktree_warning
test_sibling_dir
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
